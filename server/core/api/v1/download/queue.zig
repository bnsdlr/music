const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const api = @import("../../../api.zig");
const WorkFnError = api.WorkFnError;
const log = api.log;
const handleRespondError = api.handleRespondError;
const CurrentTarget = api.CurrentTarget;

const yt_dlp = @import("../../../yt-dlp/root.zig");

const yt = @import("queue/yt.zig");

/// /api/download/queue
pub fn handleConnection(
    io: Io,
    gpa: Allocator,
    wp: []const u8,
    request: *http.Server.Request,
    target: *CurrentTarget,
    extra: *const api.ConnectionExtra,
) WorkFnError!void {
    if (target.partStartsWith("/yt")) {
        return yt.handleConnection(io, gpa, wp, request, target, extra);
    }

    api.respondWithNotFound(request);
}
