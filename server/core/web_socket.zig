const std = @import("std");
const fmt = std.fmt;
const http = std.http;
const Io = std.Io;
const net = Io.net;
const WebSocket = http.Server.WebSocket;
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const assert = std.debug.assert;

const hslToRgb = @import("color/root.zig").hslToRgb;

const log = std.log.scoped(.web_socket);

pub const Connection = struct {
    web_socket: WebSocket,
    stream: net.Stream,
    _input: ?*Reader = null,
    _output: ?*Writer = null,

    const Self = @This();

    const max_iovecs_len = 8;

    /// Creates a copy of the WebSocket so that it can be used on a seperate thread.
    /// 
    /// * `allocator` should be an allocator that is accessible to the thread that wants to use the 
    ///               WebSocket.
    pub fn copy(self: *const Self, io: Io, allocator: Allocator) error{OutOfMemory}!Self {
        var web_socket: WebSocket = undefined;
        web_socket.key = try allocator.dupe(u8, self.web_socket.key);

        const input_buffer = try allocator.dupe(u8, self.web_socket.input.buffer);
        errdefer allocator.free(input_buffer);
        const input = try allocator.create(Reader);
        errdefer allocator.destroy(input);
        input.init(self.stream, io, input_buffer);

        web_socket.input = &input.interface;
        web_socket.input.seek = self.web_socket.input.seek;
        web_socket.input.end = self.web_socket.input.end;

        const output_buffer = try allocator.dupe(u8, self.web_socket.output.buffer);
        errdefer allocator.free(output_buffer);
        const output = try allocator.create(Writer);
        // NO ERROR AFTER THIS; errdefer allocator.destroy(output);
        output.init(self.stream, io, output_buffer);

        web_socket.output = &output.interface;
        web_socket.output.end = self.web_socket.output.end;

        return .{
            .stream = self.stream,
            .web_socket = web_socket,
            ._input = input,
            ._output = output,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self._input) |input| allocator.destroy(input);
        if (self._output) |output| allocator.destroy(output);
        allocator.free(self.web_socket.input.buffer);
        allocator.free(self.web_socket.output.buffer);
        allocator.free(self.web_socket.key);
    }

    // some copied std code, to expose some functionality {{{

    pub const Reader = struct {
        io: Io,
        interface: Io.Reader,
        stream: net.Stream,
        err: ?Error,

        pub const Error = error{
            SystemResources,
            ConnectionResetByPeer,
            Timeout,
            SocketUnconnected,
            /// The file descriptor does not hold the required rights to read
            /// from it.
            AccessDenied,
            NetworkDown,
        } || Io.Cancelable || Io.UnexpectedError;

        pub fn init(self: *@This(), stream: net.Stream, io: Io, buffer: []u8) void {
            self.io = io;
            self.interface = .{
                    .vtable = &.{
                        .stream = streamImpl,
                        .readVec = readVec,
                    },
                    .buffer = buffer,
                    .seek = 0,
                    .end = 0,
            };
            self.stream = stream;
            self.err = null;
        }

        pub fn streamImpl(io_r: *Io.Reader, io_w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
            const dest = limit.slice(try io_w.writableSliceGreedy(1));
            var data: [1][]u8 = .{dest};
            const n = try readVec(io_r, &data);
            io_w.advance(n);
            return n;
        }

        pub fn readVec(io_r: *Io.Reader, data: [][]u8) Io.Reader.Error!usize {
            const r: *Reader = @alignCast(@fieldParentPtr("interface", io_r));
            const io = r.io;
            var iovecs_buffer: [max_iovecs_len][]u8 = undefined;
            const dest_n, const data_size = try io_r.writableVector(&iovecs_buffer, data);
            const dest = iovecs_buffer[0..dest_n];
            assert(dest[0].len > 0);
            const n = io.vtable.netRead(io.userdata, r.stream.socket.handle, dest) catch |err| {
                r.err = err;
                return error.ReadFailed;
            };
            if (n == 0) {
                return error.EndOfStream;
            }
            if (n > data_size) {
                r.interface.end += n - data_size;
                return data_size;
            }
            return n;
        }
    };

    pub const Writer = struct {
        io: Io,
        interface: Io.Writer,
        stream: net.Stream,
        err: ?Error = null,
        write_file_err: ?WriteFileError = null,

        pub const Error = error{
            /// Another TCP Fast Open is already in progress.
            FastOpenAlreadyInProgress,
            /// Network session was unexpectedly closed by recipient.
            ConnectionResetByPeer,
            /// The output queue for a network interface was full. This generally indicates that the
            /// interface has stopped sending, but may be caused by transient congestion. (Normally,
            /// this does not occur in Linux. Packets are just silently dropped when a device queue
            /// overflows.)
            ///
            /// This is also caused when there is not enough kernel memory available.
            SystemResources,
            /// No route to network.
            NetworkUnreachable,
            /// Network reached but no route to host.
            HostUnreachable,
            /// The local network interface used to reach the destination is down.
            NetworkDown,
            /// The destination address is not listening.
            ConnectionRefused,
            /// The passed address didn't have the correct address family in its sa_family field.
            AddressFamilyUnsupported,
            /// Local end has been shut down on a connection-oriented socket, or
            /// the socket was never connected.
            SocketUnconnected,
            SocketNotBound,
        } || Io.UnexpectedError || Io.Cancelable;

        pub const WriteFileError = error{
            NetworkDown,
        } || Io.Cancelable || Io.UnexpectedError;

        pub fn init(self: *@This(), stream: net.Stream, io: Io, buffer: []u8) void {
            self.io = io;
            self.stream = stream;
            self.interface = .{
                .vtable = &.{
                    .drain = drain,
                    .sendFile = sendFile,
                },
                .buffer = buffer,
            };
        }

        pub fn drain(io_w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
            const w: *Writer = @alignCast(@fieldParentPtr("interface", io_w));
            const io = w.io;
            const buffered = io_w.buffered();
            const handle = w.stream.socket.handle;
            const n = io.vtable.netWrite(io.userdata, handle, buffered, data, splat) catch |err| {
                w.err = err;
                return error.WriteFailed;
            };
            return io_w.consume(n);
        }

        pub fn sendFile(io_w: *Io.Writer, file_reader: *Io.File.Reader, limit: Io.Limit) Io.Writer.FileError!usize {
            _ = io_w;
            _ = file_reader;
            _ = limit;
            return error.Unimplemented; // TODO
        }
    };

    // }}}
};

pub const Connections = struct {
    mutex: Io.Mutex,
    connections: []Connection,
    capacity: usize,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, max_connections: usize) error{OutOfMemory}!Self {
        var connections = try allocator.alloc(Connection, max_connections);
        connections.len = 0;

        return .{
            .connections = connections,
            .capacity = max_connections,
            .mutex = Io.Mutex.init,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self, io: Io, gpa: Allocator) error{Canceled}!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        self.deinitUnchecked(gpa);
    }

    pub fn deinitUnchecked(self: *Self, gpa: Allocator) void {
        for (self.connections) |*connection| {
            connection.deinit(gpa);
        }
        
        self.connections.len += self.capacity;
        gpa.free(self.connections);
    }

    pub fn put(self: *Self, io: Io, connection: Connection) error{Canceled,NoSpace,OutOfMemory}!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        self.putUnchecked(io, connection);
    }

    pub fn putUnchecked(self: *Self, io: Io, connection: Connection) error{NoSpace,OutOfMemory}!void {
        if (self.capacity == 0) return error.NoSpace;
        self.connections.len += 1;
        self.connections[self.connections.len - 1] = try connection.copy(io, self.allocator);
        self.capacity -= 1;
    }

    pub fn removeUnchecked(self: *Self, index: usize) void {
        if (self.connections.len == 0) return;
        self.connections[self.connections.len - 1].deinit(self.allocator);
        mem.swap(Connection, &self.connections[index], &self.connections[self.connections.len - 1]);
        self.connections.len -= 1;
        self.capacity += 1;
    }

    pub fn iterator(self: *Self, io: Io) error{Canceled}!Iterator {
        try self.mutex.lock(io);
        return .{
            .distributor = self,
            .index = 0,
        };
    }

    pub const Iterator = struct {
        distributor: *Connections,
        index: usize,

        pub fn init(distibutor: *Connections, io: Io) error{Canceled}!Iterator {
            try distibutor.mutex.lock(io);
            return .{
                .distributor = distibutor,
                .index = 0,
            };
        }

        pub fn deinit(self: *Iterator, io: Io) void {
            self.distributor.mutex.unlock(io);
        }

        pub fn next(self: *Iterator) ?*Connection {
            if (self.distributor.connections.len <= self.index) return null;
            defer self.index += 1;
            return &self.distributor.connections[self.index];
        }

        pub fn removeLast(self: *Iterator) void {
            if (self.index == 0) return;
            self.index -= 1;
            self.distributor.removeUnchecked(self.index);
        }
    };
};

pub const Bucket = struct {
    mutex: Io.Mutex,
    items: []Connections,
    current: usize,
    delay: Io.Duration,

    const Self = @This();

    pub fn init(allocator: Allocator, size: usize, max_connections: usize, delay: Io.Duration) error{OutOfMemory}!Self {
        const items = try allocator.alloc(Connections, size);
        
        for (items) |*connections| {
            connections.* = try .init(allocator, max_connections);
        }

        return .{
            .current = 0,
            .items = items,
            .mutex = Io.Mutex.init,
            .delay = delay,
        };
    }

    pub fn put(self: *Self, io: Io, connection: Connection) error{NoSpace,OutOfMemory,Canceled}!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);

        if (self.items[self.current].mutex.tryLock()) {
            try self.items[self.current].putUnchecked(io, connection);
            self.items[self.current].mutex.unlock(io);
            self.next();
            return;
        }

        while (true) {
            for (self.items) |*connections| {
                if (connections.mutex.tryLock()) {
                    connections.putUnchecked(io, connection) catch |err| switch (err) {
                        error.NoSpace => continue,
                        error.OutOfMemory => return error.OutOfMemory,
                    };
                    connections.mutex.unlock(io);
                    break;
                }
            }
            try io.sleep(self.delay, .real);
        }
    }

    pub fn next(self: *Self) void {
        self.current += 1;
        if (self.current >= self.items.len) self.current = 0;
    }

    pub fn deinit(self: *Self, io: Io, allocator: Allocator) error{Canceled}!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);

        for (self.items) |*item| {
            try item.deinit(io, allocator);
        }
        allocator.free(self.items);
    }

    pub fn deinitUnchecked(self: *Self, gpa: Allocator) void {
        for (self.items) |*item| {
            item.deinitUnchecked(gpa);
        }
        gpa.free(self.items);
    }
};

pub const WorkFnError = error{
    OutOfMemory,
    Canceled,
};

pub const Fn = fn (Parameters) WorkFnError!void;
pub const Parameters = struct {
    io: Io,
    gpa: Allocator,
    worker_prefix: []const u8,
    connections: *Connections,
};

pub const WorkerGroupInitOptions = struct {
    max_connections_per_worker: usize,
    worker_count: usize,
    initial_worker_arena_bytes: usize,
    worker_arena_retain_limit: usize,
    woker_loop_delay: Io.Duration,
    bucket_try_lock_delay: Io.Duration,
};

pub fn WorkerGroup(
    comptime prefix: []const u8,
    comptime work_fn: Fn,
) type {
    return struct {
        bucket: Bucket,
        arenas: []ArenaAllocator,
        arena_retain_limit: usize,
        delay: Io.Duration,
        
        const Self = @This();

        pub fn init(allocator: Allocator, opts: WorkerGroupInitOptions) error{OutOfMemory}!Self {
            const arenas = try allocator.alloc(ArenaAllocator, opts.worker_count);

            for (arenas) |*arena| {
                arena.* = .init(allocator);
                _ = try arena.allocator().alloc(u8, opts.initial_worker_arena_bytes);
                if (!arena.reset(.{ .retain_with_limit = opts.worker_arena_retain_limit })) {
                    log.warn("Failed to reset worker arena with '.retain_with_limit' (limit: {d})", .{opts.worker_arena_retain_limit});
                }
            }

            return .{
                .bucket = try .init(allocator, opts.worker_count, opts.max_connections_per_worker, opts.bucket_try_lock_delay),
                .arenas = arenas,
                .arena_retain_limit = opts.worker_arena_retain_limit,
                .delay = opts.woker_loop_delay,
            };
        }

        pub fn deinit(self: *Self, io: Io, allocator: Allocator) error{Canceled}!void {
            try self.bucket.deinit(io, allocator);

            for (self.arenas) |*arena| {
                arena.deinit();
            }
            allocator.free(self.arenas);
        }

        pub fn deinitUnchecked(self: *Self, allocator: Allocator) void {
            self.bucket.deinitUnchecked(allocator);
            for (self.arenas) |*arena| {
                arena.deinit();
            }
            allocator.free(self.arenas);
        }

        pub fn spawnWorkers(
            self: *Self,
            io: Io,
            group: *Io.Group,
            hue_step: f32,
            offset: usize,
        ) error{Canceled,ConcurrencyUnavailable}!usize {
            for (self.arenas, self.bucket.items, 1..) |*arena, *connections, id| {
                const rgb = hslToRgb(hue_step * @as(f32, @floatFromInt(id + offset)), 0.195, 0.678);
                try group.concurrent(io, workerLoop, .{io, .{
                    .rgb = rgb,
                    .arena = arena,
                    .id = id + offset,
                    .arena_retain_limit = self.arena_retain_limit,
                    .delay = self.delay,
                    .connections = connections,
                }});
            }

            return self.arenas.len;
        }

        pub const Options = struct {
            rgb: struct{u8, u8, u8},
            arena: *ArenaAllocator,
            id: usize,
            arena_retain_limit: usize,
            delay: Io.Duration,
            connections: *Connections,
        };

        pub fn workerLoop(io: Io, opts: Options) error{Canceled}!void {
            const r, const g, const b = opts.rgb;

            var worker_prefix_buffer: [100]u8 = undefined;
            const worker_prefix = fmt.bufPrint(&worker_prefix_buffer, prefix ++ "\x1b[38;2;{d};{d};{d}mWorker({d:0>2})\x1b[0m", .{r, g, b, opts.id}) catch @panic("worker prefix too long");

            const allocator = opts.arena.allocator();

            while (true) {
                work_fn(.{ 
                    .gpa = allocator,
                    .io = io,
                    .worker_prefix = worker_prefix,
                    .connections = opts.connections,
                }) catch |err| {
                    if (err == error.Canceled) return error.Canceled;
                    log.err("{s} shutting down, reason '{t}'", .{worker_prefix, err});
                    break;
                };
                try io.sleep(opts.delay, .real);
                if (!opts.arena.reset(.{ .retain_with_limit = opts.arena_retain_limit })) {
                    log.warn("{s} Failed to reset arena...", .{worker_prefix});
                }
            }
        }
    };
}

