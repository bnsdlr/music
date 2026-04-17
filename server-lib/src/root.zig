pub const acoustid = @import("acoustid.zig");
pub const color = @import("color.zig");
pub const music_brainz = @import("music_brainz.zig");
pub const url = @import("url.zig");
pub const yt_dlp = @import("yt-dlp.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
