pub const shasum = @import("shasums.zig");
pub const verifyShaSums = shasum.verifyShaSums;

pub const github = @import("github.zig");
pub const update = github.update;
pub const downloadLatest = github.downloadLatest;

pub const cli = @import("cli.zig");
pub const downloadVideo = cli.downloadVideo;
pub const downloadAudio = cli.downloadAudio;
pub const Options = cli.Options;
pub const Identifier = cli.Identifier;

pub const log = @import("std").log.scoped(.yt_dlp);

pub const VideoID = @import("../id.zig").ID(void, u66);
pub const PlaylistTag = enum(u12) {
    /// PL
    default = (@as(u12, @intCast('P')) << 6) | (@as(u12, @intCast('L'))),
    /// FL
    favorites = (@as(u12, @intCast('F')) << 6) | (@as(u12, @intCast('L'))),
    /// UU
    uploaded = (@as(u12, @intCast('U')) << 6) | (@as(u12, @intCast('U'))),
    /// LL
    linked = (@as(u12, @intCast('L')) << 6) | (@as(u12, @intCast('L'))),
    _,
};
pub const PlaylistID = @import("../id.zig").ID(PlaylistTag, u192);

pub const ID = union(enum) {
    video: VideoID,
    playlist: PlaylistID,
};

pub const Paths = struct {
    root: []const u8,
    bin: []const u8,
    cache: []const u8,
    temp: []const u8,

    pub const default: @This() = .{ .root = "yt-dlp", .bin = "bin", .cache = "cache", .temp = "temp" };
};

test {
    @import("std").testing.refAllDecls(@This());
}
