pub const shasum = @import("shasums.zig");
pub const github = @import("github.zig");
pub const YTID = @import("id.zig").YTID;

pub const Paths = struct {
    root: []const u8,
    downloads: []const u8,
    bin: []const u8,

const x = @compileLog("hi");
};

test {
    @import("std").testing.refAllDecls(@This());
}
