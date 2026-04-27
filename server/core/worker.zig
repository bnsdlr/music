const std = @import("std");
const fmt = std.fmt;
const Io = std.Io;
const net = Io.net;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const hslToRgb = @import("color/root.zig").hslToRgb;

const yt_dlp = @import("yt-dlp/root.zig");

const log = std.log.scoped(.worker);

pub const WorkerGroupInitOptions = struct {
    queue_buffer_size: usize,
    worker_count: usize,
    initial_worker_arena_bytes: usize,
    worker_arena_retain_limit: usize,
};

pub fn WorkerGroup(
    comptime T: type,
    comptime Extra: type,
    comptime prefix: []const u8,
    comptime work_fn: WorkerFn(T, Extra).Fn,
) type {
    return struct {
        queue_buffer: []T,
        queue: Io.Queue(T),
        arenas: []ArenaAllocator,
        arena_retain_limit: usize,

        pub const W = Worker(T, Extra, prefix, work_fn);

        pub const Self = @This();

        pub fn init(base_allocator: Allocator, opts: WorkerGroupInitOptions) error{OutOfMemory}!Self {
            const connection_queue_buffer = try base_allocator.alloc(T, opts.queue_buffer_size);
            const connection_queue: Io.Queue(T) = .init(connection_queue_buffer);

            const arenas = try base_allocator.alloc(ArenaAllocator, opts.worker_count);

            for (arenas) |*arena| {
                arena.* = ArenaAllocator.init(base_allocator);
                _ = try arena.allocator().alloc(u8, opts.initial_worker_arena_bytes);
                if (!arena.reset(.{ .retain_with_limit = opts.worker_arena_retain_limit })) {
                    log.warn("Failed to reset worker arena with '.retain_with_limit' (limit: {d})", .{opts.worker_arena_retain_limit});
                }
            }

            return .{
                .queue_buffer = connection_queue_buffer,
                .queue = connection_queue,
                .arena_retain_limit = opts.worker_arena_retain_limit,
                .arenas = arenas,
            };
        }

        pub fn spawnWorkers(
            self: *Self,
            io: Io,
            group: *Io.Group,
            hue_step: f32,
            offset: usize,
            extra: Extra
        ) error{Canceled,ConcurrencyUnavailable}!usize {
            for (self.arenas, 1..) |*arena, id| {
                const rgb = hslToRgb(hue_step * @as(f32, @floatFromInt(id + offset)), 0.195, 0.678);
                try group.concurrent(io, W.workerLoop, .{io, .{
                    .rgb = rgb,
                    .arena = arena,
                    .queue = &self.queue,
                    .id = id + offset,
                    .arena_retain_limit = self.arena_retain_limit,
                    .extra = extra,
                }});
            }

            return self.arenas.len;
        }

        pub fn deinit(self: *Self, base_allocator: Allocator) void {
            base_allocator.free(self.queue_buffer);

            for (self.arenas) |*arena| {
                arena.deinit();
            }

            base_allocator.free(self.arenas);
        }
    };
}

pub const WorkFnError = error{
    OutOfMemory,
};

pub fn WorkerFn(comptime T: type, comptime Extra: type) type {
    return struct {
        pub const Fn = fn (Parameters) WorkFnError!void;
        pub const Parameters = struct {
            gpa: Allocator,
            io: Io,
            worker_prefix: []const u8,
            task: T,
            extra: Extra,
        };
    };
}

pub fn Worker(
    comptime T: type,
    comptime Extra: type,
    comptime prefix: []const u8,
    comptime work_fn: WorkerFn(T, Extra).Fn,
) type {
    return struct {
        pub const QueueItem = T;

        pub const Fn = WorkerFn(T, Extra).Fn;
        pub const Parameters = WorkerFn(T, Extra).Parameters;

        pub const Options = struct {
            rgb: struct{u8, u8, u8},
            arena: *ArenaAllocator,
            id: usize,
            arena_retain_limit: usize,
            queue: *Io.Queue(T),
            extra: Extra,
        };

        pub fn workerLoop(io: Io, opts: Options) error{Canceled}!void {
            const r, const g, const b = opts.rgb;

            var worker_prefix_buffer: [100]u8 = undefined;
            const worker_prefix = fmt.bufPrint(&worker_prefix_buffer, prefix ++ "\x1b[38;2;{d};{d};{d}mWorker({d:0>2})\x1b[0m", .{r, g, b, opts.id}) catch @panic("worker prefix too long");

            const allocator = opts.arena.allocator();

            while (true) {
                const task = opts.queue.getOne(io) catch |err| switch (err) {
                    error.Closed => {
                        log.info("{s} Queue closed: shutting down...", .{worker_prefix});
                        break;
                    },
                    error.Canceled => return error.Canceled,
                };
                log.info("{s} \x1b[1;90mReceived task\x1b[0m", .{worker_prefix});
                work_fn(.{ 
                    .gpa = allocator,
                    .io = io,
                    .worker_prefix = worker_prefix,
                    .task = task,
                    .extra = opts.extra,
                }) catch |err| {
                    log.err("{s} shutting down, reason '{t}'", .{worker_prefix, err});
                    break;
                };
                log.info("{s} \x1b[1;90mHandled task\x1b[0m", .{worker_prefix});
                if (!opts.arena.reset(.{ .retain_with_limit = opts.arena_retain_limit })) {
                    log.warn("{s} Failed to reset arena...", .{worker_prefix});
                }
            }
        }
    };
}

