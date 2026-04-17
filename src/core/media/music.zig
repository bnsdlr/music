const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

const expectEqualDeep = std.testing.expectEqualDeep;

pub const ID = [10]u8;

/// {root}/
///     {music_id}/
///         audio.{format}
///         video.{format}
///         {type}-{size}.{format}
///         info.json
pub const Paths = struct {
    root: []const u8,

    const Self = @This();

    pub fn fileAlloc(self: *const Self, gpa: Allocator, music_id: *const ID, file_opts: FileOptions) error{OutOfMemory}![]u8 {
        return fmt.allocPrint(gpa, "{s}/{s}/{f}", .{self.root, music_id.*, file_opts});
    }

    pub fn fileWrite(
        self: *const Self,
        music_id: *const ID,
        file_opts: FileOptions,
        writer: *std.Io.Writer
    ) std.Io.Writer.Error!void {
        try writer.print("{s}/{s}/{f}", .{self.root, music_id.*, file_opts});
    }

    test fileAlloc {
        const gpa = std.testing.allocator;
        const path: Self = .{ .root = "music" };

        const path1 = try path.fileAlloc(gpa, "0123456789", .info);
        defer gpa.free(path1);
        try expectEqualDeep("music/0123456789/info.json", path1);

        const path2 = try path.fileAlloc(gpa, "0123456789", .{ .audio = .opus });
        defer gpa.free(path2);
        try expectEqualDeep("music/0123456789/audio.opus", path2);

        const path3 = try path.fileAlloc(gpa, "0123456789", .{ .audio = .m4a });
        defer gpa.free(path3);
        try expectEqualDeep("music/0123456789/audio.m4a", path3);

        const path4 = try path.fileAlloc(gpa, "0123456789", .{ .video = .mp4 });
        defer gpa.free(path4);
        try expectEqualDeep("music/0123456789/video.mp4", path4);

        const path5 = try path.fileAlloc(gpa, "0123456789", .{ .cover = .{ .fmt = .jpg, .size = .large, .type = .front } });
        defer gpa.free(path5);
        try expectEqualDeep("music/0123456789/front-large.jpg", path5);

        const path6 = try path.fileAlloc(gpa, "0123456789", .{ .cover = .{ .fmt = .png, .size = .@"500x500", .type = .back } });
        defer gpa.free(path6);
        try expectEqualDeep("music/0123456789/back-500x500.png", path6);

        const path7 = try path.fileAlloc(gpa, "0123456789", .{ .cover = .{ .fmt = .webp, .size = .@"1200x1200", .type = .front } });
        defer gpa.free(path7);
        try expectEqualDeep("music/0123456789/front-1200x1200.webp", path7);
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

// }}}

test {
    std.testing.refAllDecls(@This());
}
