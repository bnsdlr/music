//! media/
//!     music/
//!         {music_id}/
//!             audio.{format}
//!             video.{format}
//!             info.json

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const music = @import("media/music.zig");
pub const MusicID = music.ID;

pub const Paths = struct {
    root: []const u8,
    music: music.Paths,
};
