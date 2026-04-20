const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const api = @import("../../../../api.zig");
const WorkFnError = api.WorkFnError;
const log = api.log;
const handleRespondError = api.handleRespondError;
const CurrentTarget = api.CurrentTarget;

const yt_dlp = @import("../../../../yt-dlp/root.zig");

/// /api/download/queue/yt
pub fn handleConnection(
    io: Io,
    gpa: Allocator,
    wp: []const u8,
    request: *http.Server.Request,
    target: *CurrentTarget,
    extra: *const api.ConnectionExtra,
) WorkFnError!void {
    _ = gpa;

    const media_type: api.DownloadTask.Yt.Type = if (target.partStartsWith("/audio"))
            .audio
        else if (target.partStartsWith("/video"))
            .video
        else
            return api.respondWithNotFound(request);

    if (target.part.len < 12) {
        request.respond("Invalid YouTube id", .{ .status = .bad_request }) catch |e| handleRespondError(e);
        return;
    }
    const id = target.part[1..12];

    const task = @unionInit(api.DownloadTask, "yt", .{ 
        .id = .{ .video = yt_dlp.VideoID.decode(id) catch unreachable },
        .type = media_type,
    });
    extra.download_queue.putOne(io, task) catch |err| {
        log.warn("{s} Download service unavailable '{t}'", .{wp, err});
        request.respond("Download unavailable", .{ .keep_alive = false, .status = .service_unavailable })
            catch |e| handleRespondError(e);
        return;
    };
    request.respond("Queued download", .{.keep_alive = false}) catch |e| handleRespondError(e);
}
