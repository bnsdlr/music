const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const process = std.process;
const Init = process.Init;

const lib = @import("lib");
const AppConfig = @import("args.zig").AppConfig;

const Server = @import("core/Server.zig");

const YTID = lib.yt_dlp.YTID;

pub const Paths = @import("core.zig").Paths;
pub const paths: Paths = .{
    .root = "server-dir",
    .server = .{
        .public = "src/public",
    },
    .yt_dlp = .{
        .root = "yt-dlp",
        .downloads = "downloads",
        .bin = "bin",
    },
    .database = .{
        .root = "db",
        .backups = "backups",
        .db_file = "db.sqlite",
    },
    .media = .{
        .root = "media",
        .music = .{
            .root = "music",
        },
    }
};

var app_config: AppConfig = .{
    .acoustid_table = .{},
    .request_reader_buffer_size = 10 * 1024,
    .max_send_file_size = 64 * 1024,
    .response_writer_buffer_size = 64 * 1024,
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
    // defer evented.deinit();
    // const io = evented.io();

    // try @import("core/pool.zig").testQueue(io);

    const gpa = if (builtin.mode == .Debug)
            init.gpa
        else
            std.heap.smp_allocator;

    var client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    const dir = try std.Io.Dir.createDirPathOpen(.cwd(), io, paths.p(&.{.yt_dlp}), .{});
    defer dir.close(io);

    var result = lib.yt_dlp.github.downloadLatest(io, &client, dir, paths.yt_dlp, gpa, .always);

    if (result) |*r| {
        switch (r.*) {
            .github_error => |status| {
                std.debug.print("github responded with '{t}'\n", .{status});
            },
            .assets => |*assets| {
                defer assets.deinit(gpa);
                for (assets.items) |*asset| {
                    defer asset.asset.deinit(gpa);
                    switch (asset.download_result) {
                        .@"error" => |err| {
                            std.debug.print("Failed to download asset '{s}' with error '{t}'\n", .{asset.asset.name, err});
                        },
                        .ok => |a| switch (a) {
                            .would_overwrite => std.debug.print("Downloading asset '{s}' would overwrite\n", .{asset.asset.name}),
                            .status => |status| std.debug.print("Downloading asset '{s}' returned with status '{t}'\n", .{asset.asset.name, status}),
                        }
                    }
                }
            }
        }
    } else |err| {
        std.debug.print("failed with error '{t}'\n", .{err});
    }

    // const cpu_core_count = try std.Thread.getCpuCount();
    //
    // var server: Server = try .init(gpa, Server.Options{
    //     .queue_buffer_size = 100,
    //     .worker_count = cpu_core_count * 2,
    //     .initial_worker_arena_bytes = 64 * 1024 * 1024,
    //     .worker_arena_retain_limit = 64 * 1024 * 1024,
    // });
    // defer server.deinit(init.gpa);
    // try server.run(io, app_config);
}

test {
    std.testing.refAllDecls(@This());
}
