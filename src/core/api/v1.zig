const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const api = @import("../api.zig");
const HandleConnectionError = api.HandleConnectionError;

pub fn handleConnection(
    io: Io,
    gpa: *Allocator,
    wp: []const u8,
    request: *http.Server.Request
) HandleConnectionError!void {
    _ = io;
    _ = gpa;
    _ = wp;
    request.respond("hello from api v1", .{}) catch unreachable;
}
