const std = @import("std");

const server = @import("core/server.zig");

pub fn main(init: std.process.Init) !void {
    try server.run(init);
}

test {
    std.testing.refAllDecls(@This());
}
