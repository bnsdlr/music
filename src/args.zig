const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const process = std.process;

const lib = @import("lib");

const log = std.log.scoped(.args);

pub const AppConfig = struct {
    acoustid_api_key: []const u8 = undefined,
    acoustid_table: lib.acoustid.TableOptions,
    port: u16 = 8080,
    host: []const u8 = "127.0.0.1",

    const Self = @This();

    var set = false;

    pub const ArgsParseError = error{ParseError,WriteFailed,InvalidCharacter,Overflow};
    pub const error_prefix = "\x1b[1;31merror\x1b[90m:\x1b[0m ";

    pub fn init(self: *Self, environ_map: *process.Environ.Map, args: process.Args) !void {
        if (set) @panic("AppConfig can only be initilized once.");
        set = true;
        var iter = args.iterate();

        var set_acoustid_api_key: bool = false;
        
        var i: usize = 0;
        while (iter.next()) |arg| {
            if (try anyArg(u16, &.{"port"}, arg, &i)) |r| {
                self.port = r;
            } else if (try anyArg([]const u8, &.{"acoustid-api-key", "acoustid"}, arg, &i)) |r| {
                self.acoustid_api_key = r;
                set_acoustid_api_key = true;
            } else {
                i += arg.len;
            }
            i += 1;
        }

        if (!set_acoustid_api_key) self.acoustid_api_key = lib.acoustid.getClientAPIKey(environ_map) orelse {
            log.err("Could not find environment variable '" ++ lib.acoustid.env_acoustid_api_key_key ++ "', or argument --acoustid-api-key=<api-key>.", .{});
            process.exit(1);
        };
    }

    fn anyArg(comptime T: type, comptime any: []const []const u8, argument: []const u8, index: *usize) ArgsParseError!?T {
        if (mem.startsWith(u8, argument, "-")) {
            const trimed = mem.trimStart(u8, argument, "-");
            inline for (any) |a| {
                if (trimed.len > a.len and mem.startsWith(u8, trimed, a) and trimed[a.len] == '=') {
                    const value_start = mem.find(u8, argument, "=").? + 1;
                    index.* += value_start;
                    const value = argument[value_start..];
                    switch (@typeInfo(T)) {
                        .int => return try fmt.parseInt(T, value, 10),
                        .float => return try fmt.parseFloat(T, value),
                        .pointer => |info| switch (info.size) {
                            .many, .c, .one => @compileError("not implemened"),
                            .slice => return value,
                        },
                        .bool => {
                            if (eqlAny(.{"1", "t", "true"}, value)) return true;
                            if (eqlAny(.{"0", "f", "false"}, value)) return false;
                            try log.err("Failed to parse bool at index {d}\n", .{index.*});
                        },
                        else => @compileError("not implemented"),
                    }
                    return error.ParseError;
                }
            }
        }
        return null;
    }

    fn eqlAny(comptime any: anytype, value: []const u8) bool {
        for (any) |a| if (mem.eql(u8, a, value)) return true;
        return false;
    }
};
