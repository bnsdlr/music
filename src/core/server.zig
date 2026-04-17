const std = @import("std");
const fmt = std.fmt;
const Io = std.Io;
const net = Io.net;
const http = std.http;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Connection = net.Stream;

const assert = std.debug.assert;

const AppConfig = @import("../args.zig").AppConfig;

const hslToRgb = @import("color/root.zig").hslToRgb;

const api = @import("api.zig");

pub const log = std.log.scoped(.Server);

queue_buffer: []Connection,
queue: Io.Queue(Connection),
worker_arenas: []ArenaAllocator,
worker_arena_retain_limit: usize,

const Self = @This();

pub const WorkFnError = error{
    OutOfMemory,
};

pub const WorkFn = *const fn (WorkFnParameters) WorkFnError!void;
pub const WorkFnParameters = struct {
    gpa: Allocator,
    io: Io,
    worker_prefix: []const u8,
    connection: net.Stream,
};

// init / deinit {{{

pub fn init(base_allocator: Allocator, opts: Options) !Self {
    const queue_buffer = try base_allocator.alloc(Connection, opts.queue_buffer_size);
    const queue: Io.Queue(Connection) = .init(queue_buffer);

    const worker_arenas = try base_allocator.alloc(ArenaAllocator, opts.worker_count);

    for (worker_arenas) |*arena| {
        arena.* = ArenaAllocator.init(base_allocator);
        _ = try arena.allocator().alloc(u8, opts.initial_worker_arena_bytes);
        if (!arena.reset(.{ .retain_with_limit = opts.worker_arena_retain_limit })) {
            log.warn("Failed to reset worker arena with '.retain_with_limit' (limit: {d})", .{opts.worker_arena_retain_limit});
        }
    }

    return .{
        .queue_buffer = queue_buffer,
        .queue = queue,
        .worker_arena_retain_limit = opts.worker_arena_retain_limit,
        .worker_arenas = worker_arenas,
    };
}

pub fn deinit(self: *Self, base_allocator: Allocator) void {
    base_allocator.free(self.queue_buffer);

    for (self.worker_arenas) |*arena| {
        arena.deinit();
    }

    base_allocator.free(self.worker_arenas);
}

// }}}

// run {{{

pub fn run(self: *Self, io: Io, config: AppConfig) !void {
    log.info("host                      : {s}", .{config.host});
    log.info("port                      : {d}", .{config.port});
    log.info("acoustid api key          : {s}", .{config.acoustid_api_key});

    const address = try net.IpAddress.parse(config.host, config.port);

    var server = try address.listen(io, .{});
    defer server.deinit(io);

    var accept_loop = try io.concurrent(Self.acceptLoop, .{io, &self.queue, &server});
    defer accept_loop.cancel(io) catch {};

    try @call(.always_inline, Self.spawnWorkers, .{self, io, &api.handleConnection});

    try accept_loop.await(io);
}

// }}}

// spawnWorkers {{{

pub fn spawnWorkers(self: *Self, io: Io, work_fn: WorkFn) error{Canceled,ConcurrencyUnavailable}!void {
    var group = Io.Group.init;

    log.info("Spawning {d} workers", .{self.worker_arenas.len});

    const hue_step = 360 / @as(f32, @floatFromInt(self.worker_arenas.len));

    for (self.worker_arenas, 1..) |*arena, id| {
        const rgb = hslToRgb(hue_step * @as(f32, @floatFromInt(id)), 0.195, 0.678);
        try group.concurrent(io, Self.workerLoop, .{io, .{
            .rgb = rgb,
            .arena = arena,
            .req_queue = &self.queue,
            .id = id,
            .work_fn = work_fn,
            .arena_retain_limit = self.worker_arena_retain_limit,
        }});
    }

    try group.await(io);
}

// }}}

// workerLoop {{{

pub const WorkerOptions = struct {
    rgb: struct{u8, u8, u8},
    arena: *ArenaAllocator,
    req_queue: *Io.Queue(Connection),
    id: usize,
    work_fn: WorkFn,
    arena_retain_limit: usize,
};

pub fn workerLoop(io: Io, opts: WorkerOptions) error{Canceled}!void {
    const r, const g, const b = opts.rgb;

    var worker_prefix_buffer: [100]u8 = undefined;
    const worker_prefix = fmt.bufPrint(&worker_prefix_buffer, "\x1b[38;2;{d};{d};{d}mWorker({d})\x1b[0m", .{r, g, b, opts.id}) catch @panic("worker prefix too long");

    const allocator = opts.arena.allocator();

    while (true) {
        const connection = opts.req_queue.getOne(io) catch |err| switch (err) {
            error.Closed => {
                log.info("{s} Queue closed: shutting down...", .{worker_prefix});
                break;
            },
            error.Canceled => return error.Canceled,
        };
        log.info("{s} \x1b[1;90mReceived connection\x1b[0m", .{worker_prefix});
        opts.work_fn(.{ 
            .gpa = allocator,
            .io = io,
            .worker_prefix = worker_prefix,
            .connection = connection 
        }) catch |err| {
            log.err("{s} shutting down, reason '{t}'", .{worker_prefix, err});
            break;
        };
        log.info("{s} \x1b[1;90mHandled connection\x1b[0m", .{worker_prefix});
        if (!opts.arena.reset(.{ .retain_with_limit = opts.arena_retain_limit })) {
            log.warn("{s} Failed to reset arena...", .{worker_prefix});
        }
    }
}

// }}}

// acceptLoop {{{

pub fn acceptLoop(io: Io, req_queue: *Io.Queue(Connection), server: *net.Server) !void {
    while (true) {
        // log.debug("accepting connection", .{});
        const connection = server.accept(io) catch |err| switch (err) {
            error.ConnectionAborted => {
                log.debug("connection aborted", .{});
                continue;
            },
            else => return err,
        };
        // log.debug("received connection, forwarding to connection queue...", .{});
        try req_queue.putOne(io, connection);
    }
}

// }}}

// Options {{{

pub const Options = struct {
    queue_buffer_size: usize,
    worker_count: usize,
    initial_worker_arena_bytes: usize,
    worker_arena_retain_limit: usize,
};

// }}}

// Paths {{{

pub const Paths = struct {
    public: []const u8,
};

// }}}

test {
    std.testing.refAllDecls(@This());
}
