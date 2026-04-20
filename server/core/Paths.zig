//! * `{song_id}` is used for the database
//! 
//! # Example
//!
//! ./
//!     public/...
//!     db/
//!         backups/...
//!         db.sqlite
//!     yt-dlp/
//!         downloads/...
//!     media/
//!         music/
//!             {song_id}/
//!                 audio.{format}
//!                 video.{format}
//!                 info.json
//!     

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const expectEqualDeep = std.testing.expectEqualDeep;

const Server = @import("Server.zig");
const import_media = @import("media.zig");
const MediaPaths = import_media.Paths;
const FileOptions = import_media.music.FileOptions;
const core = @import("../core.zig");
const ID = import_media.ID;

pub const paths = @import("../main.zig").paths;

const Self = @This();

root: []const u8,
server: Server.Paths,
yt_dlp: core.yt_dlp.Paths,
database: core.db.Paths,
media: MediaPaths,

// musicPath {{{

pub fn musicPath(gpa: Allocator, id: ID, file_opts: FileOptions) error{OutOfMemory,WriteFailed}![]u8 {
    return musicPathInternal(paths, gpa, id, file_opts);
}

fn musicPathInternal(comptime pa: Self, gpa: Allocator, id: ID, file_opts: FileOptions) error{OutOfMemory,WriteFailed}![]u8 {
    const music_path = comptime pathInternal(&.{.media}, pa, null) ++ "/";

    var allocating_writer: Io.Writer.Allocating = try .initCapacity(gpa, music_path.len * 8);
    defer allocating_writer.deinit();

    var writer = allocating_writer.writer;

    try writer.writeAll(music_path);
    try pa.media.music.fileWrite(id, file_opts, &writer);
    try writer.flush();

    const array_list = writer.toArrayList();

    const out = try gpa.alloc(u8, array_list.items.len);
    @memcpy(out, array_list.items);

    return out;
}

test musicPathInternal {
    const gpa = std.testing.allocator;
    const test_paths: Self = .{ 
        .root = ".",
        .server = .{ .public = "", }, 
        .database = .default,
        .yt_dlp = .default,
        .media = .{
            .root = "media",
            .music = .{
                .root = "music",
            },
        }
    };

    const path1 = try musicPathInternal(test_paths, gpa, try .decode("0123456789ab"), .info);
    defer gpa.free(path1);
    try expectEqualDeep("./media/music/0123456789ab/info.json", path1);

    const path2 = try musicPathInternal(test_paths, gpa, try .decode("0123456789ab"), .{ .audio = .opus });
    defer gpa.free(path2);
    try expectEqualDeep("./media/music/0123456789ab/audio.opus", path2);

    const path3 = try musicPathInternal(test_paths, gpa, try .decode("0123456789ab"), .{ .audio = .m4a });
    defer gpa.free(path3);
    try expectEqualDeep("./media/music/0123456789ab/audio.m4a", path3);

    const path4 = try musicPathInternal(test_paths, gpa, try .decode("0123456789ab"), .{ .video = .mp4 });
    defer gpa.free(path4);
    try expectEqualDeep("./media/music/0123456789ab/video.mp4", path4);

    const path5 = try musicPathInternal(test_paths, gpa, try .decode("0123456789ab"), .{ .cover = .{ .fmt = .jpg, .size = .large, .type = .front } });
    defer gpa.free(path5);
    try expectEqualDeep("./media/music/0123456789ab/front-large.jpg", path5);

    const path6 = try musicPathInternal(test_paths, gpa, try .decode("0123456789ab"), .{ .cover = .{ .fmt = .png, .size = .@"500x500", .type = .back } });
    defer gpa.free(path6);
    try expectEqualDeep("./media/music/0123456789ab/back-500x500.png", path6);

    const path7 = try musicPathInternal(test_paths, gpa, try .decode("0123456789ab"), .{ .cover = .{ .fmt = .webp, .size = .@"1200x1200", .type = .front } });
    defer gpa.free(path7);
    try expectEqualDeep("./media/music/0123456789ab/front-1200x1200.webp", path7);
}

// }}}

// path {{{

pub fn p(comptime self: Self, comptime tags: anytype) []const u8 {
    return pathInternal(tags, self, null);
}

pub fn path(comptime tags: anytype) []const u8 {
    return pathInternal(tags, paths, null);
}

fn pathInternal(comptime tags: []const @EnumLiteral(), comptime pa: anytype, comptime accumulator: ?[]const u8) []const u8 {
    // 1. If tags.len is 0 or p is null, return accumulator
    if (tags.len == 0 or @TypeOf(pa) == @TypeOf(null)) {
        const root = if (comptime @hasField(@TypeOf(pa), "root")) 
                @field(pa, "root") 
            else 
                "";
        if (accumulator) |acc| {
            return acc ++ "/" ++ root;
        } else {
            return root;
        }
    }

    switch (tags[0]) {
        inline else => |tag| {
            // 2. If accumulator is not null `acc ++ "/"` else ""
            comptime var literal: []const u8 = if (accumulator) |acc|
                    acc ++ "/"
                else
                    "";

            comptime var has_root = false;

            // 3. If p has field .root append it to the literal
            if (comptime @hasField(@TypeOf(pa), "root")) {
                literal = literal ++ @field(pa, "root");
                has_root = true;
            }

            // 4. If p field `tag` is of type struct continue with the struct as p
            if (@typeInfo(@FieldType(@TypeOf(pa), @tagName(tag))) == .@"struct") {
                return pathInternal(tags[1..], @field(pa, @tagName(tag)), literal);
            }

            // 5. append fields value to literal and return
            return literal ++ (if (has_root) "/" else "") ++ @field(pa, @tagName(tag));
        }
    }
}

test pathInternal {
    const test_paths: Self = .{ 
        .root = ".",
        .server = .{
            .public = "src/public",
        },
        .yt_dlp = .{
            .root = "yt-dlp",
            .bin = "bin",
            .cache = "cache",
            .temp = "temp",
        },
        .database = .{
            .root = "db",
            .backups = "backups",
            .db_file = "db.sqlite",
        },
        .media = .{
            .root = "media",
            .music = .{
                .root = "music",
            },
        }
    };

    try expectEqualDeep(".", pathInternal(&.{}, test_paths, null));
    try expectEqualDeep("./src/public", pathInternal(&.{.server, .public}, test_paths, null));
    try expectEqualDeep("./yt-dlp", pathInternal(&.{.yt_dlp}, test_paths, null));
    try expectEqualDeep("./yt-dlp/temp", pathInternal(&.{.yt_dlp, .temp}, test_paths, null));
    try expectEqualDeep("./db", pathInternal(&.{.database}, test_paths, null));
    try expectEqualDeep("./db/backups", pathInternal(&.{.database, .backups}, test_paths, null));
    try expectEqualDeep("./db/db.sqlite", pathInternal(&.{.database, .db_file}, test_paths, null));
    try expectEqualDeep("./media", pathInternal(&.{.media}, test_paths, null));
    try expectEqualDeep("./media/music", pathInternal(&.{.media, .music}, test_paths, null));
}

// }}}

test {
    std.testing.refAllDecls(@This());
}
