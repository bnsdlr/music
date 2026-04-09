const std = @import("std");

pub const ID = [36]u8;

test {
    std.testing.refAllDecls(@This());
}
