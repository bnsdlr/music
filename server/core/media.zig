//! media/
//!     music/
//!         {music_id}/
//!             audio.{format}
//!             video.{format}
//!             info.json

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const music = @import("media/music.zig");

pub const Tag = enum(u6) {
    yt = 0,
    _,
};

pub const ID = @import("shared").id.ID(Tag, u66);

pub const Paths = struct {
    root: []const u8,
    music: music.Paths,

    pub const default: @This() = .{ .music = .default, .root = "media" };
};
