pub const VideoID = @import("shared").id.ID(void, u66);
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
pub const PlaylistID = @import("shared").id.ID(PlaylistTag, u192);

pub const ID = union(enum) {
    video: VideoID,
    playlist: PlaylistID,
};

pub const Media = struct {
    id: ID,
    type: Type,

    pub const Type = enum {
        audio,
        video,
    };
};

