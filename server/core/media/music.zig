const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

const expectEqualDeep = std.testing.expectEqualDeep;
const ID = @import("../media.zig").ID;

/// {root}/
///     {music_id}/
///         audio.{format}
///         video.{format}
///         {type}-{size}.{format}
///         thumbnail-{size}.{formt}
///         info.json
pub const Paths = struct {
    root: []const u8,

    pub const default: Self = .{ .root = "music" };

    const Self = @This();

    pub fn fileAlloc(self: *const Self, gpa: Allocator, id: ID, file_opts: FileOptions) error{OutOfMemory}![]u8 {
        return fmt.allocPrint(gpa, "{s}/{f}/{f}", .{self.root, id, file_opts});
    }

    pub fn fileWrite(
        self: *const Self,
        id: ID,
        file_opts: FileOptions,
        writer: *std.Io.Writer
    ) std.Io.Writer.Error!void {
        try writer.print("{s}/{f}/{f}", .{self.root, id, file_opts});
    }

    test fileAlloc {
        const gpa = std.testing.allocator;
        const path: Self = .{ .root = "music" };

        const path1 = try path.fileAlloc(gpa, try .decode("0123456789ab"), .info);
        defer gpa.free(path1);
        try expectEqualDeep("music/0123456789ab/info.json", path1);

        const path2 = try path.fileAlloc(gpa, try .decode("0123456789ab"), .{ .audio = .opus });
        defer gpa.free(path2);
        try expectEqualDeep("music/0123456789ab/audio.opus", path2);

        const path3 = try path.fileAlloc(gpa, try .decode("0123456789ab"), .{ .audio = .m4a });
        defer gpa.free(path3);
        try expectEqualDeep("music/0123456789ab/audio.m4a", path3);

        const path4 = try path.fileAlloc(gpa, try .decode("0123456789ab"), .{ .video = .mp4 });
        defer gpa.free(path4);
        try expectEqualDeep("music/0123456789ab/video.mp4", path4);

        const path5 = try path.fileAlloc(gpa, try .decode("0123456789ab"), .{ .cover = .{ .fmt = .jpg, .size = .large, .type = .front } });
        defer gpa.free(path5);
        try expectEqualDeep("music/0123456789ab/front-large.jpg", path5);

        const path6 = try path.fileAlloc(gpa, try .decode("0123456789ab"), .{ .cover = .{ .fmt = .png, .size = .@"500x500", .type = .back } });
        defer gpa.free(path6);
        try expectEqualDeep("music/0123456789ab/back-500x500.png", path6);

        const path7 = try path.fileAlloc(gpa, try .decode("0123456789ab"), .{ .cover = .{ .fmt = .webp, .size = .@"1200x1200", .type = .front } });
        defer gpa.free(path7);
        try expectEqualDeep("music/0123456789ab/front-1200x1200.webp", path7);
    }
};

// file options {{{

pub const FileOptions = union(enum) {
    audio: AudioFormat,
    video: VideoFormat,
    cover: Cover,
    info,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .info => try writer.writeAll("info.json"),
            .cover => |cover| try cover.format(writer),
            .audio => |audio_fmt| try writer.print("audio.{t}", .{audio_fmt}),
            .video => |video_fmt| try writer.print("video.{t}", .{video_fmt}),
        }
    }
};

// Audio {{{

pub const AudioFormat = enum {
    mp3,
    m4a,
    opus,
};

// }}}

// Video {{{

pub const VideoFormat = enum {
    mp4,
};

// }}}

// Cover {{{

pub const Cover = struct {
    size: Size = .large,
    fmt: Format = .jpg,
    type: Type = .front,

    pub const Type = enum {
        front,
        back,
    };

    pub const Size = union(enum) {
        @"250x250",
        @"500x500",
        @"1200x1200",
        large,
        small,
    };

    pub const Format = enum {
        png,
        jpg,
        webp,
    };

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{t}-{t}.{t}", .{self.type, self.size, self.fmt});
    }
};

// }}}

// Thumbnail {{{

pub const Thumbnail = struct {
    tag: Tag = .@"maxresdefault.webp",

    pub const Tag = enum(i8) {
        @"3.jpg"                = -37,
        @"3.webp"               = -36,
        @"2.jpg"                = -35,
        @"2.webp"               = -34,
        @"1.jpg"                = -33,
        @"1.webp"               = -32,
        @"mq3.jpg"              = -31,
        @"mq3.webp"             = -30,
        @"mq2.jpg"              = -29,
        @"mq2.webp"             = -28,
        @"mq1.jpg"              = -27,
        @"mq1.webp"             = -26,
        @"hq3.jpg"              = -25,
        @"hq3.webp"             = -24,
        @"hq2.jpg"              = -23,
        @"hq2.webp"             = -22,
        @"hq1.jpg"              = -21,
        @"hq1.webp"             = -20,
        @"sd3.jpg"              = -19,
        @"sd3.webp"             = -18,
        @"sd2.jpg"              = -17,
        @"sd2.webp"             = -16,
        @"sd1.jpg"              = -15,
        @"sd1.webp"             = -14,
        @"default.jpg"          = -13,
        @"default.webp"         = -12,
        @"mqdefault.jpg"        = -11,
        @"mqdefault.webp"       = -10,
        @"0.jpb"                = -9,
        @"0.webp"               = -8,
        @"hqdefault.jpg"        = -7,
        @"hqdefault.webp"       = -6,
        @"sddefault.jpg"        = -5,
        @"sddefault.webp"       = -4,
        @"hq720.jpg"            = -3,
        @"hq720.webp"           = -2,
        @"maxresdefault.jpg"    = -1,
        @"maxresdefault.webp"   = -1,
    };

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{t}-{t}.{t}", .{self.type, self.size, self.fmt});
    }
};


// }}}

// }}}

test {
    std.testing.refAllDecls(@This());
}
