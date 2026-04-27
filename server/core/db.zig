const id = @import("shared").id;

pub const Paths = struct {
    root: []const u8,
    backups: []const u8,
    db_file: []const u8,

    pub const default: @This() = .{ .root = "db", .backups = "backups", .db_file = "db" };
};

pub const Tag = enum(u6) {
    yt,
    acoustid,
    music_brainz,
    queue_entry,
    _,
};

pub const ID = id.ID(Tag, u66);

