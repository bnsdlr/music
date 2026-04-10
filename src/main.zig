const std = @import("std");
const process = std.process;
const Init = process.Init;
pub const lib = @import("root.zig");

const server = @import("core/server.zig");

pub const AppConfig = struct {
    acoustid_api_key: []const u8,

    const Self = @This();

    var set = false;

    pub fn init(environ_map: *process.Environ.Map) void {
        if (set) @panic("AppConfig can only be initilized once.");
        set = true;
        app_config.acoustid_api_key = lib.acoustid.getClientAPIKey(environ_map) orelse {
            log.err("Could not find environment variable '" ++ lib.acoustid.env_acoustid_api_key_key ++ "'.", .{});
            process.exit(1);
        };
    }
};

var app_config: AppConfig = undefined;

pub fn config() *const AppConfig {
    return &app_config;
}

const log = std.log.scoped(.main);

pub fn main(init: Init) !void {
    AppConfig.init(init.environ_map);
    try server.run(init);
}

test {
    std.testing.refAllDecls(@This());
}
