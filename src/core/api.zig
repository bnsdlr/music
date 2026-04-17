const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;
const Connection = net.Stream;

const main = @import("../main.zig");
const path = @import("Paths.zig").path;

const Server = @import("Server.zig");
const log = Server.log;
pub const HandleConnectionError = Server.WorkFnError;
pub const WorkFnParams = Server.WorkFnParameters;

pub const v1 = @import("api/v1.zig");

pub const helper = @import("api/helper.zig");
pub const handleRespondError = helper.handleRespondError;

// connection handlig {{{

pub fn handleConnection(params: WorkFnParams) HandleConnectionError!void {
    const io = params.io;
    const gpa = params.gpa;
    const wp = params.worker_prefix;
    const connection = params.connection;

    defer connection.close(io);

    const reader_buffer = try gpa.alloc(u8, main.config().request_reader_buffer_size);
    var reader = connection.reader(io, reader_buffer);

    const writer_buffer = try gpa.alloc(u8, main.config().response_writer_buffer_size);
    var writer = connection.writer(io, writer_buffer);

    var http_server = http.Server.init(&reader.interface, &writer.interface);

    var req = http_server.receiveHead() catch |err| switch (err) {
        error.HttpHeadersInvalid => {
            log.info("{s} Received invalid http headers", .{wp});
            return;
        },
        error.HttpHeadersOversize => {
            log.info("{s} Received oversized headers", .{wp});
            writer.interface.print("HTTP/1.1 {d} {s}\r\n", .{
                @intFromEnum(http.Status.request_header_fields_too_large),
                http.Status.request_header_fields_too_large.phrase().?,
            }) catch {
                log.info("{s} Failed to write response", .{wp});
            };
            writer.interface.flush() catch {
                log.info("{s} Failed to write response", .{wp});
            };
            return;
        },
        error.HttpRequestTruncated => {
            log.info("{s} Connection was closed early", .{wp});
            return;
        },
        error.HttpConnectionClosing => {
            log.info("{s} keep-alive connection closed", .{wp});
            return;
        },
        error.ReadFailed => {
            log.warn("{s} Transitive error occurred reading from `in`.", .{wp});
            return;
        },
    };

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

    if (mem.startsWith(u8, req.head.target, "/api")) {
        try v1.handleConnection(io, gpa, wp, &req);
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

test {
    std.testing.refAllDecls(@This());
}
