const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;
const Connection = net.Stream;

const Server = @import("Server.zig");

const log = Server.log;
pub const HandleConnectionError = Server.WorkFnError;

pub const v1 = @import("api/v1.zig");

// connection handlig {{{

pub fn handleConnection(io: Io, gpa: *Allocator, wp: []const u8, connection: Connection) HandleConnectionError!void {
    defer connection.close(io);

    const reader_buffer = try gpa.alloc(u8, 10 * 1024);
    var reader = connection.reader(io, reader_buffer);

    const writer_buffer = try gpa.alloc(u8, 4 * 1024);
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

    if (mem.startsWith(u8, req.head.target, "/v1")) {
        try v1.handleConnection(io, gpa, wp, &req);
    } else {
        // send files
    }
}

// }}}

test {
    std.testing.refAllDecls(@This());
}
