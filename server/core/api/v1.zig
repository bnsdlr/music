const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const api = @import("../api.zig");
const log = api.log;
const WorkFnError = api.WorkFnError;
const handleRespondError = api.handleRespondError;
const CurrentTarget = api.CurrentTarget;

pub const download = @import("v1/download.zig");

/// /api
pub fn handleConnection(
    io: Io,
    gpa: Allocator,
    wp: []const u8,
    request: *http.Server.Request,
    target: *CurrentTarget,
    extra: *const api.ConnectionExtra,
) WorkFnError!void {
    log.info("{s} target: (full: {s}, part: {s})", .{wp, target.full, target.part});

    if (target.partStartsWith("/download")) {
        return download.handleConnection(io, gpa, wp, request, target, extra);
    } else {
        request.respond("hello from api v1", .{}) catch |err| handleRespondError(err);
    }
    api.respondWithNotFound(request);
}
