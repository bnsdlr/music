const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const net = std.net;
const http = std.http;
const Allocator = mem.Allocator;

pub fn handleRespondError(err: error{WriteFailed,HttpExpectationFailed}) void {
    err catch unreachable;
}

pub fn respondWithNotFound(req: *http.Server.Request) void {
    req.respond(
        comptime http.Status.not_found.phrase().?,
        .{
            .keep_alive = false,
            .status = .not_found,
            .reason = comptime http.Status.not_found.phrase(),
        }
    ) catch |err| handleRespondError(err);
}

pub const CurrentTarget = struct {
    full: []const u8,
    part: []const u8,

    const Self = @This();

    pub fn fromOwned(slice: []const u8) Self {
        return .{
            .full = slice,
            .part = slice,
        };
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        gpa.free(self.full);
    }

    /// Will update path if it starts with needle
    pub fn partStartsWith(self: *Self, needle: []const u8) bool {
        if (mem.startsWith(u8, self.part, needle)) {
            self.part = self.part[needle.len..];
            return true;
        }
        return false;
    }
};
