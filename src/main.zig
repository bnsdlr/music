const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const process = std.process;
const Init = process.Init;

const lib = @import("lib");
const AppConfig = @import("args.zig").AppConfig;

const Server = @import("core/Server.zig");

var app_config: AppConfig = .{
    .acoustid_table = .{},
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


    const cpu_core_count = try std.Thread.getCpuCount();

    var server: Server = try .init(gpa, Server.Options{
        .queue_buffer_size = 100,
        .worker_count = cpu_core_count - 1,
        .initial_worker_arena_bytes = 64 * 1024 * 1024,
        .worker_arena_retain_limit = 64 * 1024 * 1024,
    });
    defer server.deinit(init.gpa);
    try server.run(io, app_config);
}

test {
    std.testing.refAllDecls(@This());
}
