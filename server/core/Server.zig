const std = @import("std");
const fmt = std.fmt;
const Io = std.Io;
const net = Io.net;
const http = std.http;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const assert = std.debug.assert;

const AppConfig = @import("../args.zig").AppConfig;

const hslToRgb = @import("color/root.zig").hslToRgb;

const api = @import("api.zig");

const yt_dlp = @import("yt-dlp/root.zig");

const worker = @import("worker.zig");
const Worker = worker.Worker;
const WorkerGroup = worker.WorkerGroup;
const WorkerGroupInitOptions = worker.WorkerGroupInitOptions;
pub const WorkFnError = worker.WorkFnError;

const web_socket = @import("web_socket.zig");

pub const log = std.log.scoped(.server);

pub const ConnectionGroupExtra = struct {
    download_queue: *Io.Queue(api.DownloadTask),
    research_queue: *Io.Queue(api.ResearchTask),
    websocket_bucket: *web_socket.Bucket,
};

pub const ConnectionGroup = WorkerGroup(api.ConnectionTask, ConnectionGroupExtra,   "\x1b[1;34mConn", api.handleConnection);
pub const DownloaderGroup = WorkerGroup(api.DownloadTask,   void,                   "\x1b[1;31m  Yt", api.handleDownload);
pub const ResearcherGroup = WorkerGroup(api.ResearchTask,   void,                   "\x1b[1;33m  MB", api.research);
pub const WebSocketGroup  = web_socket.WorkerGroup("\x1b[1;33mWebS", api.handleWebSockets);

connection_group: ConnectionGroup,
download_group: DownloaderGroup,
research_group: ResearcherGroup,
websocket_group: WebSocketGroup,

const Server = @This();

// init / deinit {{{

pub const InitOptions = struct {
    connection_group: WorkerGroupInitOptions,
    download_group: WorkerGroupInitOptions,
    research_group: WorkerGroupInitOptions,
    websocket_group: web_socket.WorkerGroupInitOptions,
};

pub fn init(base_allocator: Allocator, opts: InitOptions) error{OutOfMemory}!Server {
    return .{
        .connection_group = try .init(base_allocator, opts.connection_group),
        .download_group = try .init(base_allocator, opts.download_group),
        .research_group = try .init(base_allocator, opts.research_group),
        .websocket_group = try .init(base_allocator, opts.websocket_group),
    };
}

pub fn deinit(self: *Server, io: Io, allocator: Allocator) error{Canceled}!void {
    try self.websocket_group.deinit(io, allocator);
    self.connection_group.deinit(allocator);
    self.download_group.deinit(allocator);
    self.research_group.deinit(allocator);
}

pub fn deinitUnchecked(self: *Server, allocator: Allocator) void {
    self.connection_group.deinit(allocator);
    self.download_group.deinit(allocator);
    self.research_group.deinit(allocator);
    self.websocket_group.deinitUnchecked(allocator);
}

// }}}

// run {{{

pub fn run(self: *Server, io: Io, config: AppConfig) !void {
    log.info("Running on \x1b[4m{s}:{d}\x1b[0m", .{config.host, config.port});

    const address = try net.IpAddress.parse(config.host, config.port);

    var server = try address.listen(io, .{});
    defer server.deinit(io);

    var accept_loop = try io.concurrent(Server.acceptLoop, .{io, &self.connection_group.queue, &server});
    defer accept_loop.cancel(io) catch {};

    try @call(.always_inline, Server.spawnWorkers, .{self, io});

    try accept_loop.await(io);
}

// }}}

// spawnWorkers {{{

pub fn spawnWorkers(self: *Server, io: Io) error{Canceled,ConcurrencyUnavailable}!void {
    var group = Io.Group.init;

    const worker_count = self.connection_group.arenas.len 
        + self.download_group.arenas.len 
        + self.research_group.arenas.len
        + self.websocket_group.arenas.len;

    log.info("Spawning {d} workers (connection: {d}, download: {d}, reseracher: {d}, web socket: {d})", .{
        worker_count,
        self.connection_group.arenas.len,
        self.download_group.arenas.len,
        self.research_group.arenas.len,
        self.websocket_group.arenas.len,
    });

    const hue_step = 360 / @as(f32, @floatFromInt(worker_count));

    var offset: usize = 0;

    const extra: ConnectionGroupExtra = .{ 
        .download_queue = &self.download_group.queue,
        .research_queue = &self.research_group.queue,
        .websocket_bucket = &self.websocket_group.bucket,
    };

    offset += try self.connection_group.spawnWorkers(io, &group, hue_step, offset, extra);
    offset += try self.download_group.spawnWorkers(io, &group, hue_step, offset, {});
    offset += try self.research_group.spawnWorkers(io, &group, hue_step, offset, {});
    offset += try self.websocket_group.spawnWorkers(io, &group, hue_step, offset);

    try group.await(io);
}

// }}}

// acceptLoop {{{

pub fn acceptLoop(io: Io, req_queue: *Io.Queue(net.Stream), server: *net.Server) !void {
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

// Paths {{{

pub const Paths = struct {
    public: []const u8,
};

// }}}

test {
    std.testing.refAllDecls(@This());
}
