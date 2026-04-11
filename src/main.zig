const std = @import("std");
const process = std.process;
const Init = process.Init;

pub const lib = @import("lib");

const server = @import("core/server.zig");

pub const AppConfig = struct {
    acoustid_api_key: []const u8 = undefined,
    acoustid_table: lib.acoustid.TableOptions,
    music_brainz_user_agent: []const u8 = undefined,

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

pub const music_brainz_user_agent = lib.music_brainz.createUserAgent("music", "0.0.1", "me@bsdlr.de");

var app_config: AppConfig = .{
    .acoustid_table = .{},
    .music_brainz_user_agent = music_brainz_user_agent,
};

pub fn config() *const AppConfig {
    return &app_config;
}

const log = std.log.scoped(.main);

pub fn main(init: Init) !void {
    AppConfig.init(init.environ_map);

    inline for (@typeInfo(lib.music_brainz.json_response).@"struct".decls) |d| {
        const T = @field(lib.music_brainz.json_response, d.name);
        if (@TypeOf(T) != type) continue;
        std.debug.print("{s: <52}: {d: <6} (optional: +{d})\n", .{@typeName(T), @sizeOf(T), @sizeOf(?T) - @sizeOf(T)});
    }
    //
    // inline for (.{
    //     std.json.Value,
    // }) |t| {
    //     std.debug.print("{s: <52}: {d: <6} (optional: +{d})\n", .{@typeName(t), @sizeOf(t), @bitSizeOf(?t) - @bitSizeOf(t)});
    // }
    //
    process.exit(0);

    try server.run(init);
}

test {
    std.testing.refAllDecls(@This());
}
