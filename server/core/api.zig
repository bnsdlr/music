const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const main = @import("../main.zig");
const path = @import("Paths.zig").path;

const yt_dlp = @import("yt-dlp/root.zig");

const web_socket = @import("web_socket.zig");

const Server = @import("Server.zig");
const worker = @import("worker.zig");
pub const WorkFnError = worker.WorkFnError;

pub const v1 = @import("api/v1.zig");

pub const helper = @import("api/helper.zig");
pub const handleRespondError = helper.handleRespondError;
pub const CurrentTarget = helper.CurrentTarget;
pub const respondWithNotFound = helper.respondWithNotFound;
pub const ConnectionExtra = Server.ConnectionGroupExtra;

pub const log = std.log.scoped(.api);

// connection {{{

pub const ConnectionWorkFnParams = worker.WorkerFn(ConnectionTask, ConnectionExtra).Parameters;

pub const ConnectionTask = net.Stream;

pub fn handleConnection(params: ConnectionWorkFnParams) WorkFnError!void {
    const io = params.io;
    const gpa = params.gpa;
    const wp = params.worker_prefix;
    const connection = params.task;

    const reader_buffer = try gpa.alloc(u8, main.config().request_reader_buffer_size);
    var reader = connection.reader(io, reader_buffer);

    const writer_buffer = try gpa.alloc(u8, main.config().response_writer_buffer_size);
    var writer = connection.writer(io, writer_buffer);

    var http_server = http.Server.init(&reader.interface, &writer.interface);

    var req = http_server.receiveHead() catch |err| {
        switch (err) {
            error.HttpHeadersInvalid => {
                log.warn("{s} Received invalid http headers", .{wp});
            },
            error.HttpHeadersOversize => {
                log.warn("{s} Received oversized headers", .{wp});
                writer.interface.print("HTTP/1.1 {d} {s}\r\n", .{
                    @intFromEnum(http.Status.request_header_fields_too_large),
                    http.Status.request_header_fields_too_large.phrase().?,
                }) catch {
                    log.warn("{s} Failed to write response", .{wp});
                };
                writer.interface.flush() catch {
                    log.warn("{s} Failed to write response", .{wp});
                };
            },
            error.HttpRequestTruncated => {
                log.warn("{s} Connection was closed early", .{wp});
            },
            error.HttpConnectionClosing => {
                log.warn("{s} keep-alive connection closed", .{wp});
            },
            error.ReadFailed => {
                log.warn("{s} Transitive error occurred reading from `in`.", .{wp});
            },
        }
        return;
    };

    log.info("{s} ip address: '{f}'", .{wp, connection.socket.address});

    switch (req.upgradeRequested()) {
        .websocket => |mb_key| {
            if (mb_key) |key| {
                const magic_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
                const concatenated = try std.fmt.allocPrint(gpa, magic_guid ++ "{s}", .{key});
                var sha1: [20]u8 = undefined;
                std.crypto.hash.Sha1.hash(concatenated, &sha1, .{});

                var encoded_buffer: [200]u8 = undefined;
                const encoded = std.crypto.codecs.base64.encode(&encoded_buffer, &sha1, .standard) catch unreachable;

                log.info("{s} encoded: '{s}'", .{wp, encoded});

                const ws = req.respondWebSocket(.{ .key = encoded }) catch |err| {
                    log.warn("{s} Upgrade to WebSocket failed with error '{t}'", .{wp, err});
                    return;
                };

                // ws.writeMessage("hi", .text) catch unreachable;

                params.extra.websocket_bucket.put(io, .{ 
                    .web_socket = ws,
                    .stream = connection,
                }) catch |err| {
                    req.respond(@errorName(err), .{ .keep_alive = false, .status = .not_acceptable }) catch |e| {
                        log.warn("{s} Failed to respond ('{t}')", .{wp, e});
                    };
                };

                return;
            }
        },
        .other => |other| {
            log.info("{s} Continuing as normal request, unknown upgrade '{s}'", .{wp, other});
        },
        .none => {},
    }

    defer connection.close(io);

    var header_iterator = req.iterateHeaders();

    while (header_iterator.next()) |header| {
        log.info("{s} {s}: {s}", .{wp, header.name, header.value});
    }

    log.info("{s} method                : {t}", .{wp, req.head.method});
    log.info("{s} version               : {t}", .{wp, req.head.version});
    log.info("{s} target                : {s}", .{wp, req.head.target});
    log.info("{s} keep alive            : {}", .{wp, req.head.keep_alive});
    log.info("{s} content length        : {?d}", .{wp, req.head.content_length});
    log.info("{s} content type          : {?s}", .{wp, req.head.content_type});
    log.info("{s} expect                : {?s}", .{wp, req.head.expect});
    log.info("{s} transfer compression  : {t}", .{wp, req.head.transfer_compression});
    log.info("{s} transfer encoding     : {t}", .{wp, req.head.transfer_encoding});

    var current_target: CurrentTarget = .fromOwned(try gpa.dupe(u8, req.head.target));
    defer current_target.deinit(gpa);

    if (current_target.partStartsWith("/api")) {
        return v1.handleConnection(io, gpa, wp, &req, &current_target, &params.extra);
    } else {
        const target_file_rel_path = try mem.replaceOwned(u8, gpa, req.head.target, "../", "");

        log.debug("{s} '{s}' -> '{s}'", .{wp, req.head.target, target_file_rel_path});

        const target_path = if (mem.endsWith(u8, req.head.target, "/")) 
                try fmt.allocPrint(gpa, "{s}{s}index.html", .{path(&.{.server, .public}), target_file_rel_path})
            else
                try fmt.allocPrint(gpa, "{s}{s}", .{path(&.{.server, .public}), target_file_rel_path});

        const contents = Io.Dir.cwd().readFileAlloc(io, target_path, gpa, .limited(main.config().max_send_file_size)) catch |err| {
            log.warn("{s} Failed to open file '{s}' with '{t}'", .{wp, target_path, err});
            switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.IsDir,
                error.AccessDenied,
                error.AntivirusInterference,
                error.BadPathName,
                error.FileLocksUnsupported,
                error.FileNotFound,
                error.NetworkNotFound,
                error.NoDevice,
                error.NotOpenForReading,
                error.PermissionDenied,
                error.FileTooBig => {
                    req.respond("404 File Not Found", .{ .keep_alive = false, .status = .not_found, .reason = "FileNotFound" }) 
                        catch |e| helper.handleRespondError(e);
                },
                // error.DeviceBusy,
                // error.FileBusy,
                // error.InputOutput,
                // error.LockViolation,
                // error.NoSpaceLeft,
                // error.PipeBusy,
                else => {},
            }
            return;
        };
        defer gpa.free(contents);

        req.respond(contents, .{ .keep_alive = false }) catch |err| helper.handleRespondError(err);
        log.info("{s} Send File '{s}'", .{wp, target_path});
        return;
    }
}

// }}}

// download {{{

pub const DownloadWorkFnParams = worker.WorkerFn(DownloadTask, void).Parameters;

pub const DownloadTask = union(enum) {
    yt: Yt,

    pub const Yt = struct {
        id: yt_dlp.ID,
        type: Type = .audio,

        pub const Type = enum { audio, video };
    };
};

pub fn handleDownload(params: DownloadWorkFnParams) WorkFnError!void {
    const io = params.io;
    const gpa = params.gpa;
    const wp = params.worker_prefix;
    const task = params.task;

    _ = gpa;

    switch (task) {
        .yt => |yt| {
            switch (yt.type) {
                .audio => {
                    const term = yt_dlp.downloadAudio(io, .{ .id = yt.id }) catch |err| {
                        log.err("{s} Audio download failed with error '{t}'", .{wp, err});
                        return;
                    };
                    switch (term) {
                        .exited => |status| {
                            if (status == 0) return;
                            log.warn("{s} Audio download failed with status '{d}'", .{wp, status});
                        },
                        .signal => |sig| log.warn("{s} Audio download failed with signal '{any}'", .{wp, sig}),
                        .stopped => |sig| log.warn("{s} Audio download stopped with signal '{any}'", .{wp, sig}),
                        .unknown => |unknown| log.warn("{s} Audio download returned unknown status '{d}'", .{wp, unknown}),
                    }
                },
                .video => {
                    const term = yt_dlp.downloadVideo(io, .{ .id = yt.id }) catch |err| {
                        log.err("{s} Video download failed with error '{t}'", .{wp, err});
                        return;
                    };
                    switch (term) {
                        .exited => |status| {
                            if (status == 0) return;
                            log.warn("{s} Video download failed with status '{d}'", .{wp, status});
                        },
                        .signal => |sig| log.warn("{s} Video download failed with signal '{any}'", .{wp, sig}),
                        .stopped => |sig| log.warn("{s} Video download stopped with signal '{any}'", .{wp, sig}),
                        .unknown => |unknown| log.warn("{s} Video download returned unknown status '{d}'", .{wp, unknown}),
                    }
                },
            }
        },
    }
}

// }}}

// find info {{{

pub const ResearchWorkFnParams = worker.WorkerFn(ResearchTask, void).Parameters;

pub const ResearchTask = struct {
    id: u8,
};

pub fn research(params: ResearchWorkFnParams) WorkFnError!void {
    const io = params.io;
    const gpa = params.gpa;
    const wp = params.worker_prefix;
    const task = params.task;

    _ = io;
    _ = gpa;
    _ = task;

    log.info("{s} working on task", .{wp});
}

// }}}

// web sockets {{{

pub fn handleWebSockets(params: web_socket.Parameters) web_socket.WorkFnError!void {
    const io = params.io;
    const gpa = params.gpa;
    // const wp = params.worker_prefix;
    const connections = params.connections;

    _ = gpa;

    var iter = try connections.iterator(io);
    defer iter.deinit(io);

    // if (connections.connections.len > 0) log.info("{s} there are {d} websockets currently connected", .{wp, connections.connections.len});

    while (iter.next()) |connection| {
        connection.web_socket.writeMessage("hi", .text) catch iter.removeLast();
    }
}

// }}}

test {
    std.testing.refAllDecls(@This());
}
