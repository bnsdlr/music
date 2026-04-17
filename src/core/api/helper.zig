const std = @import("std");
const Io = std.Io;
const net = std.net;
const http = std.http;

pub fn handleRespondError(err: error{WriteFailed,HttpExpectationFailed}) void {
    err catch unreachable;
}
