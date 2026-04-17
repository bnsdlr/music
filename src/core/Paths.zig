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
const MusicID = import_media.MusicID;
const MediaPaths = import_media.Paths;
const FileOptions = import_media.music.FileOptions;
const core = @import("../core.zig");

pub const paths = @import("../main.zig").paths;

const Self = @This();

root: []const u8,
server: Server.Paths,
yt_dlp: core.yt_dlp.Paths,
database: core.db.Paths,
media: MediaPaths,

// musicPath {{{

pub fn musicPath(gpa: Allocator, music_id: *const MusicID, file_opts: FileOptions) error{OutOfMemory,WriteFailed}![]u8 {
    return musicPathInternal(paths, gpa, music_id, file_opts);
}

fn musicPathInternal(comptime pa: Self, gpa: Allocator, music_id: *const MusicID, file_opts: FileOptions) error{OutOfMemory,WriteFailed}![]u8 {
    const music_path = comptime path(&.{.media, .music});

    var allocating_writer: Io.Writer.Allocating = .init(gpa);
    defer allocating_writer.deinit();
    try allocating_writer.ensureTotalCapacity(music_path.len);

    var writer = allocating_writer.writer;

    try writer.writeAll(music_path);
    try pa.media.music.fileWrite(music_id, file_opts, &writer);
    try writer.flush();

    return allocating_writer.toOwnedSlice();
}

// test musicPathInternal {
//     const gpa = std.testing.allocator;
//     const test_paths: Self = .{ 
//         .root = ".",
//         .server = .{ .public = "", }, .yt_dlp = .{ .root = "", .downloads = "", .bin = "" },
//         .database = .{ .root = "", .backups = "", .db_file = "", },
//         .media = .{
//             .root = "media",
//             .music = .{
//                 .root = "music",
//             },
//         }
//     };
//
//     const path1 = try musicPathInternal(test_paths, gpa, "0123456789", .info);
//     defer gpa.free(path1);
//     try expectEqualDeep("./media/music/0123456789/info.json", path1);
//
//     const path2 = try musicPathInternal(test_paths, gpa, "0123456789", .{ .audio = .opus });
//     defer gpa.free(path2);
//     try expectEqualDeep("./media/music/0123456789/audio.opus", path2);
//
//     const path3 = try musicPathInternal(test_paths, gpa, "0123456789", .{ .audio = .m4a });
//     defer gpa.free(path3);
//     try expectEqualDeep("./media/music/0123456789/audio.m4a", path3);
//
//     const path4 = try musicPathInternal(test_paths, gpa, "0123456789", .{ .video = .mp4 });
//     defer gpa.free(path4);
//     try expectEqualDeep("./media/music/0123456789/video.mp4", path4);
//
//     const path5 = try musicPathInternal(test_paths, gpa, "0123456789", .{ .cover = .{ .fmt = .jpg, .size = .large, .type = .front } });
//     defer gpa.free(path5);
//     try expectEqualDeep("./media/music/0123456789/front-large.jpg", path5);
//
//     const path6 = try musicPathInternal(test_paths, gpa, "0123456789", .{ .cover = .{ .fmt = .png, .size = .@"500x500", .type = .back } });
//     defer gpa.free(path6);
//     try expectEqualDeep("./media/music/0123456789/back-500x500.png", path6);
//
//     const path7 = try musicPathInternal(test_paths, gpa, "0123456789", .{ .cover = .{ .fmt = .webp, .size = .@"1200x1200", .type = .front } });
//     defer gpa.free(path7);
//     try expectEqualDeep("./media/music/0123456789/front-1200x1200.webp", path7);
// }

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
            .downloads = "downloads",
            .bin = "bin",
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
    try expectEqualDeep("./yt-dlp/downloads", pathInternal(&.{.yt_dlp, .downloads}, test_paths, null));
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
