const builtin = @import("builtin");
const build_zon = @import("build.zig.zon");
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const process = std.process;
const Init = process.Init;

const core = @import("core.zig");
const AppConfig = @import("args.zig").AppConfig;

const Server = @import("core/Server.zig");

pub const Paths = @import("core.zig").Paths;
pub const paths: Paths = .{
    .root = "sdir",
    .server = .{
        .public = "public",
    },
    .yt_dlp = .{ 
        .root = "yt-dlp",
        .bin = "bin",
        .cache = "cache",
        .temp = "temp" 
    },
    .database = .{ 
        .root = "db",
        .backups = "backups",
        .db_file = "db" 
    },
    .media = .{ 
        .music = .{ 
            .root = "music" 
        },
        .root = "media" 
    },
};

var app_config: AppConfig = .{
    .acoustid_table = .{},
    .request_reader_buffer_size = 10 * 1024,
    .max_send_file_size = 64 * 1024,
    .response_writer_buffer_size = 64 * 1024,
    .music_brainz_user_agent = @tagName(build_zon.name) ++ "/" ++ build_zon.version ++ " ( me@bsdlr.de )",
};

pub fn config() *const AppConfig {
    return &app_config;
}

const log = std.log.scoped(.main);

pub fn main(init: Init) !void {
    try app_config.init(init.environ_map, init.minimal.args);

    // Threaded
    var threaded: Io.Threaded = .init(init.gpa, .{
        .environ = init.minimal.environ,
        .async_limit = null,
        .concurrent_limit = .unlimited,
    });
    defer threaded.deinit();
    const io = threaded.io();

    // // Evented
    // var evented: Io.Evented = undefined;
    // try evented.init(init.gpa, .{
    //     .environ = init.minimal.environ,
    //     // .backing_allocator_needs_mutex = false,
    // });
    // // defer evented.deinit();
    // const io = evented.io();

    const gpa = if (builtin.mode == .Debug)
            init.gpa
        else
            std.heap.smp_allocator;

    if (app_config.update_yt_dlp) {
        core.yt_dlp.update(io, gpa) catch |err| {
            log.err("Failed to update yt-dlp with '{t}'", .{err});
            return;
        };
    }

    // const term = try core.yt_dlp.cli.downloadVideo(io, .{ .url = "https://www.youtube.com/watch?v=e0T0rI-GiR4" });
    // log.info("exited with '{any}'", .{term});

    const cpu_core_count = try std.Thread.getCpuCount();

    var server: Server = try .init(gpa, Server.InitOptions{
        .connection_group = .{
            .queue_buffer_size = 100,
            .worker_count = cpu_core_count,
            .initial_worker_arena_bytes = 64 * 1024 * 1024,
            .worker_arena_retain_limit = 64 * 1024 * 1024,
        },
        .websocket_group = .{
            .woker_loop_delay = .fromMilliseconds(10),
            .bucket_try_lock_delay = .fromMilliseconds(10),
            .max_connections_per_worker = 10,
            .initial_worker_arena_bytes = 64 * 1024,
            .worker_arena_retain_limit = 64 * 1024 * 1024,
            .worker_count = cpu_core_count,
        },
        .download_group = .{
            .queue_buffer_size = 1000,
            .worker_count = 1,
            .initial_worker_arena_bytes = 64 * 1024 * 1024,
            .worker_arena_retain_limit = 64 * 1024 * 1024,
        },
        .research_group = .{
            .queue_buffer_size = 1000,
            .worker_count = 2,
            .initial_worker_arena_bytes = 64 * 1024 * 1024,
            .worker_arena_retain_limit = 64 * 1024 * 1024,
        },
    });
    defer server.deinit(io, gpa) catch server.deinitUnchecked(gpa);
    try server.run(io, app_config);
}

test {
    std.testing.refAllDecls(@This());
}
