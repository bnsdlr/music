const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const ID = @import("root.zig").ID;

pub const executable_name = @import("github.zig").asset_binary_name;
pub const path = @import("../Paths.zig").path;

pub const yt_tag_chars = @import("../media.zig").ID.tagAsChars(.yt);

pub fn update(io: Io) (std.process.Child.WaitError || std.process.SpawnError)!std.process.Child.Term {
    var child = try std.process.spawn(io, .{ 
        .argv = &.{
            (comptime path(&.{.yt_dlp, .bin})) ++ "/" ++ executable_name,
            "--update-to", "stable",
        },
    });

    return try child.wait(io);
}

pub const Identifier = union(enum) {
    id: ID,
    url: []const u8,
};

pub fn downloadAudio(io: Io, identifier: Identifier) (std.process.SpawnError || std.process.Child.WaitError)!std.process.Child.Term {
    const id = switch (identifier) {
        .url => |url| url,
        .id => |id| switch (id) {
            inline else => |i| &i.encode(),
        },
    };

    var child = try std.process.spawn(io, .{ 
        .argv = &.{
            (comptime path(&.{.yt_dlp, .bin})) ++ "/" ++ executable_name,
            "--cache-dir", (comptime path(&.{.yt_dlp, .cache})),
            "--path", (comptime path(&.{.media, .music})),
            "--split-chapters",
            "-x",
            "--audio-format", "opus",
            "-o", yt_tag_chars ++ "%(id)s/audio.%(ext)s",
            "-o", "chapter:" ++ yt_tag_chars ++ "%(id)s/audio-%(section_number)s.%(ext)s",
            "-o", "infojson:" ++ yt_tag_chars ++ "%(id)s/video",
            "--write-info-json",
            "--parse-metadata", "video::(?P<formats>)(?P<automatic_captions>)(?P<heatmap>)",
            "--sleep-interval", "0",
            "--max-sleep-interval", "2",
            "--audio-multistreams",
            id,
        },
        .cwd = .{ .dir = .cwd() },
        .stderr = .pipe,
        .stdin = .pipe,
        .stdout = .pipe,
    });

    const term = try child.wait(io);

    return term;
}

// TODO error
pub fn downloadVideo(io: Io, identifier: Identifier) (std.process.SpawnError || std.process.Child.WaitError)!std.process.Child.Term {
    const id = switch (identifier) {
        .url => |url| url,
        .id => |id| switch (id) {
            inline else => |i| &i.encode(),
        },
    };

    var child = try std.process.spawn(io, .{ 
        .argv = &.{
            (comptime path(&.{.yt_dlp, .bin})) ++ "/" ++ executable_name,
            "--cache-dir", (comptime path(&.{.yt_dlp, .cache})),
            "--path", (comptime path(&.{.media, .music})),
            // "--path", "temp:" ++ (comptime path(&.{.yt_dlp, .temp})),
            "--split-chapters",
            "--remux-video", "mp4",
            "-o", yt_tag_chars ++ "%(id)s/video.%(ext)s",
            "-o", "chapter:" ++ yt_tag_chars ++ "%(id)s/video-%(section_number)s.%(ext)s",
            "-o", "infojson:" ++ yt_tag_chars ++ "%(id)s/video",
            "--write-info-json",
            "--embed-thumbnail",
            "--parse-metadata", "video::(?P<formats>)(?P<automatic_captions>)(?P<heatmap>)",
            "--sleep-interval", "0",
            "--max-sleep-interval", "2",
            "--audio-multistreams",
            id,
        },
        .cwd = .{ .dir = .cwd() },
        .stderr = .pipe,
        .stdin = .pipe,
        .stdout = .pipe,
    });

    const term = try child.wait(io);

    return term;
}

pub const Options = struct {
    general: General,
    video: Video,
    download: Download,
    filesystem: Filesystem,
    thumbnail: Thumbnail,
    verbosity_and_simulation: VerbosityAndSimulation,
    workarounds: Workarounds,
    videoformat: VideoFormat,
    subtitle: Subtitle,
    postprocessing: Postprocessing,

    // General {{{

    pub const General = struct {
        /// Upgrade/downgrade to a specific version. CHANNEL can be a repository as
        /// well. CHANNEL and TAG default to "stable" and "latest" respectively if
        /// omitted; See "UPDATE" for details. Supported channels: stable, nightly,
        /// master
        @"--update-to": ?UpdateTo = null,
        /// Update this program to the latest version
        @"--update": bool = false,
        /// Continue with next video on download errors; 
        /// e.g. to skip unavailable videos in a playlist (default)
        @"--no-abort-on-error": bool = false,            
        /// Use this prefix for unqualified URLs. E.g. "gvsearch2:python" downloads
        /// two videos from google videos for the search term "python". Use the
        /// value "auto" to let yt-dlp guess ("auto_warning" to emit a warning when
        /// guessing). "error" just throws an error. The default value
        /// "fixup_error" repairs broken URLs, but emits an error if this is not
        /// possible instead of searching
        ///
        /// PREFIX
        @"--default-search": []const u8,

        pub const UpdateTo = union(enum) {
            master,
            nightly,
            stable,
            custom: []const u8,
        };
    };

    // }}}

    // Video {{{

    pub const Video = struct {
        /// Download only the video, if the URL refers
        /// to a video and a playlist
        @"--no-playlist": bool = false,
        /// Download the playlist, if the URL refers to
        /// a video and a playlist
        @"--yes-playlist": bool = false,
        /// Download only videos not listed in the
        /// archive file. Record the IDs of all
        /// downloaded videos in it
        ///
        /// FILE
        @"--download-archive": []const u8,
        /// Number of allowed failures until the rest of
        /// the playlist is skipped
        @"--skip-playlist-after-errors": usize,
    };

    // }}}

    // Download {{{

    pub const Download = struct {
        /// Number of retries (default is 10), or "infinite"
        @"--retries": Retries = @enumFromInt(10),
        /// Number of times to retry on file access error (default is 3), or
        /// "infinite"
        @"--file-access-retries": Retries = @enumFromInt(3),
        /// Number of retries for a fragment (default is 10), or "infinite"
        /// (DASH, hlsnative and ISM)
        @"--fragment-retries": Retries = @enumFromInt(10),
        /// Time to sleep between retries in seconds (optionally) prefixed by
        /// the type of retry (http (default), fragment, file_access,
        /// extractor) to apply the sleep to. EXPR can be a number,
        /// linear=START[:END[:STEP=1]] or exp=START[:END[:BASE=2]]. This
        /// option can be used multiple times to set the sleep for the
        /// different retry types, e.g. --retry-sleep linear=1::2 --retry-sleep
        /// fragment:exp=1:20
        @"--retry-sleep": ?RetrySleep = null,
        /// Process entries in the playlist as they are received. This disables
        /// n_entries, --playlist-random and --playlist-reverse
        @"--lazy-playlist": bool = false,

        pub const Retries = enum(u32) {
            infinite = std.math.maxInt(u32),
            _,

            pub fn format(
                self: @This(),
                writer: *std.io.Writer,
            ) std.io.Writer.Error!void {
                switch (self) {
                    .infinite => try writer.writeAll(@tagName(self)),
                    _ => |n| try writer.writeInt(u32, @intFromEnum(n), .native),
                }
            }
        };

        pub const RetrySleep = struct {
            type: Type = .none,
            /// Can be a number, linear=START[:END[:STEP=1]] or
            /// exp=START[:END[:BASE=2]]. This option can be used multiple
            /// times to set the sleep for the different retry types, e.g.
            /// --retry-sleep linear=1::2 --retry-sleep fragment:exp=1:20
            expr: []const u8,

            pub const Type = enum {
                http,
                fragment,
                file_access,
                extractor,
                none,

                pub fn prefix(self: @This()) []const u8 {
                    switch (self) {
                        .none => "",
                        inline else => |tag| @tagName(tag) ++ ":",
                    }
                }
            };

            pub fn format(
                self: @This(),
                writer: *std.io.Writer,
            ) std.io.Writer.Error!void {
                try writer.writeAll(self.type.prefix());
                try writer.writeAll(self.expr);
            }
        };
    };

    // }}}

    // Filesystem {{{

    pub const Filesystem = struct {
        /// The paths where the files should be downloaded. Specify the type of
        /// file and the path separated by a colon ":". All the same TYPES as
        /// --output are supported. Additionally, you can also provide "home"
        /// (default) and "temp" paths. All intermediary files are first
        /// downloaded to the temp path and then the final files are moved over
        /// to the home path after download is finished. This option is ignored
        /// if --output is an absolute path
        @"--paths": ?[]Path = null,

        /// Output filename template; see "OUTPUT TEMPLATE" for details
        @"--output": ?[]Output = null,

        /// Placeholder for unavailable fields in --output (default: "NA")
        @"--output-na-placeholder": ?[]const u8 = null,

        /// Restrict filenames to only ASCII characters, and avoid "&" and
        /// spaces in filenames
        @"--restrict-filenames": bool = false,

        /// Allow Unicode characters, "&" and spaces in filenames (default)
        @"--no-restrict-filenames": bool = false,

        /// Force filenames to be Windows-compatible
        @"--windows-filenames": bool = false,

        /// Sanitize filenames only minimally
        @"--no-windows-filenames": bool = false,

        /// Do not overwrite any files
        @"--no-overwrites": bool = false,

        /// Overwrite all video and metadata files. This option includes
        /// --no-continue
        @"--force-overwrites": bool = false,

        /// Do not overwrite the video, but overwrite related files (default)
        @"--no-force-overwrites": bool = false,

        /// Write video description to a .description file
        @"--write-description": bool = false,

        /// Do not write video description (default)
        @"--no-write-description": bool = false,

        /// Write video metadata to a .info.json file (this may contain
        /// personal information)
        @"--write-info-json": bool = false,

        /// Do not write video metadata (default)
        @"--no-write-info-json": bool = false,

        /// Write playlist metadata in addition to the video metadata when
        /// using --write-info-json, --write-description etc. (default)
        @"--write-playlist-metafiles": bool = false,

        /// Do not write playlist metadata when using --write-info-json,
        /// --write-description etc.
        @"--no-write-playlist-metafiles": bool = false,

        /// Remove some internal metadata such as filenames from the infojson
        /// (default)
        @"--clean-info-json": bool = false,

        /// Write all fields to the infojson
        @"--no-clean-info-json": bool = false,

        /// JSON file containing the video information (created with the
        /// "--write-info-json" option)
        @"--load-info-json": ?[]const u8 = null,

        /// Netscape formatted file to read cookies from and dump cookie jar in
        @"--cookies": ?[]const u8 = null,

        /// Do not read/dump cookies from/to file (default)
        @"--no-cookies": bool = false,

        /// Location in the filesystem where yt-dlp can store some downloaded
        /// information (such as client ids and signatures) permanently. By
        /// default ${XDG_CACHE_HOME}/yt-dlp
        @"--cache-dir": ?[]const u8 = null,

        /// Disable filesystem caching
        @"--no-cache-dir": bool = false,

        /// Delete all filesystem cache files
        @"--rm-cache-dir": bool = false,
    };

    // }}}

    // Thumbnail {{{

    pub const Thumbnail = struct {
        /// Write thumbnail image to disk
        @"--write-thumbnail": bool = false,

        /// Do not write thumbnail image to disk (default)
        @"--no-write-thumbnail": bool = false,

        /// Write all thumbnail image formats to disk
        @"--write-all-thumbnails": bool = false,

        /// List available thumbnails of each video.
        /// Simulate unless --no-simulate is used
        @"--list-thumbnails": bool = false,
    };

    // }}}

    // VerbosityAndSimulation {{{

    pub const VerbosityAndSimulation = struct {
        /// Activate quiet mode. If used with --verbose, print the log to
        /// stderr
        @"--quiet": bool = false,

        /// Deactivate quiet mode. (Default)
        @"--no-quiet": bool = false,

        /// Ignore warnings
        @"--no-warnings": bool = false,

        /// Do not download the video and do not write anything to disk
        @"--simulate": bool = false,

        /// Download the video even if printing/listing options are used
        @"--no-simulate": bool = false,

        /// Field name or output template to print to screen, optionally
        /// prefixed with when to print it, separated by a ":". Supported
        /// values of "WHEN" are the same as that of --use-postprocessor
        /// (default: video). Implies --quiet. Implies --simulate unless
        /// --no-simulate or later stages of WHEN are used. This option can be
        /// used multiple times
        @"--print": ?[]const []const u8 = null,

        /// Append given template to the file. The values of WHEN and TEMPLATE
        /// are the same as that of --print. FILE uses the same syntax as the
        /// output template. This option can be used multiple times
        @"--print-to-file": ?[]PrintToFile = null,

        /// Quiet, but print JSON information for each video. Simulate unless
        /// --no-simulate is used. See "OUTPUT TEMPLATE" for a description of
        /// available keys
        @"--dump-json": bool = false,

        /// Quiet, but print JSON information for each URL or infojson passed.
        /// Simulate unless --no-simulate is used. If the URL refers to a
        /// playlist, the whole playlist information is dumped in a single line
        @"--dump-single-json": bool = false,

        /// Output progress bar as new lines
        @"--newline": bool = false,

        /// Do not print progress bar
        @"--no-progress": bool = false,

        /// Show progress bar, even if in quiet mode
        @"--progress": bool = false,

        /// Template for progress outputs, optionally
        /// prefixed with one of "download:" (default),
        /// "download-title:" (the console title),
        /// "postprocess:",  or "postprocess-title:".
        /// The video's fields are accessible under the
        /// "info" key and the progress attributes are
        /// accessible under "progress" key. E.g.
        /// --console-title --progress-template
        /// "download-title:%(info.id)s-%(progress.eta)s"
        @"--progress-template": ?[]const u8 = null,

        /// Time between progress output (default: 0)
        @"--progress-delta": ?usize = null,

        /// Print various debugging information
        @"--verbose": bool = false,

        /// Print downloaded pages encoded using base64
        /// to debug problems (very verbose)
        @"--dump-pages": bool = false,

        /// Write downloaded intermediary pages to files
        /// in the current directory to debug problems
        @"--write-pages": bool = false,

        /// Display sent and read HTTP traffic
        @"--print-traffic": bool = false,
    };

    // }}}

    // Workarounds {{{

    pub const Workarounds = struct {
        /// Force the specified encoding (experimental)
        @"--encoding": ?[]const u8 = null,

        /// Number of seconds to sleep between requests
        /// during data extraction
        @"--sleep-requests": ?usize = null,

        /// Number of seconds to sleep before each
        /// download. This is the minimum time to sleep
        /// when used along with --max-sleep-interval
        /// (Alias: --min-sleep-interval)
        @"--sleep-interval": ?usize = null,

        /// Maximum number of seconds to sleep. Can only
        /// be used along with --min-sleep-interval
        @"--max-sleep-interval": ?usize = null,

        /// Number of seconds to sleep before each
        /// subtitle download
        @"--sleep-subtitles": ?usize = null,
    };

    // }}}

    // VideoFormat {{{

    pub const VideoFormat = struct {
        /// Video format code, see "FORMAT SELECTION"
        /// for more details
        @"--format": ?[]const u8 = null,

        /// Allow multiple video streams to be merged
        /// into a single file
        @"--video-multistreams": bool = false,

        /// Only one video stream is downloaded for each
        /// output file (default)
        @"--no-video-multistreams": bool = false,

        /// Allow multiple audio streams to be merged
        /// into a single file
        @"--audio-multistreams": bool = false,

        /// Only one audio stream is downloaded for each
        /// output file (default)
        @"--no-audio-multistreams": bool = false,

        /// Make sure formats are selected only from
        /// those that are actually downloadable
        @"--check-formats": bool = false,

        /// Check all formats for whether they are
        /// actually downloadable
        @"--check-all-formats": bool = false,

        /// Do not check that the formats are actually
        /// downloadable
        @"--no-check-formats": bool = false,

        /// List available formats of each video.
        /// Simulate unless --no-simulate is used
        @"--list-formats": bool = false,
    };

    // }}}

    // Subtitle {{{

    pub const Subtitle = struct {
        /// Write subtitle file
        @"--write-subs": bool = false,

        /// Do not write subtitle file (default)
        @"--no-write-subs": bool = false,

        /// Write automatically generated subtitle file
        /// (Alias: --write-automatic-subs)
        @"--write-auto-subs": bool = false,

        /// Do not write auto-generated subtitles
        /// (default) (Alias: --no-write-automatic-subs)
        @"--no-write-auto-subs": bool = false,

        /// List available subtitles of each video.
        /// Simulate unless --no-simulate is used
        @"--list-subs": bool = false,

        /// Subtitle format; accepts formats preference
        /// separated by "/", e.g. "srt" or "ass/srt/best"
        @"--sub-format": ?[]const u8 = null,

        /// Languages of the subtitles to download (can
        /// be regex) or "all" separated by commas, e.g.
        /// --sub-langs "en.*,ja" (where "en.*" is a
        /// regex pattern that matches "en" followed by
        /// 0 or more of any character). You can prefix
        /// the language code with a "-" to exclude it
        /// from the requested languages, e.g. --sub-
        /// langs all,-live_chat. Use --list-subs for a
        /// list of available language tags
        @"--sub-langs": ?[]const u8 = null,
    };

    // }}}

    // Postprocessing {{{

    pub const Postprocessing = struct {
        /// Convert video files to audio-only files
        /// (requires ffmpeg and ffprobe)
        @"--extract-audio": bool = false,

        /// Format to convert the audio to when -x is
        /// used. (currently supported: best (default),
        /// aac, alac, flac, m4a, mp3, opus, vorbis,
        /// wav). You can specify multiple rules using
        /// similar syntax as --remux-video
        @"--audio-format": ?[]const u8 = null,

        /// Specify ffmpeg audio quality to use when
        /// converting the audio with -x. Insert a value
        /// between 0 (best) and 10 (worst) for VBR or a
        /// specific bitrate like 128K (default 5)
        @"--audio-quality": ?[]const u8 = null,

        /// Remux the video into another container if
        /// necessary (currently supported: avi, flv,
        /// gif, mkv, mov, mp4, webm, aac, aiff, alac,
        /// flac, m4a, mka, mp3, ogg, opus, vorbis,
        /// wav). If the target container does not
        /// support the video/audio codec, remuxing will
        /// fail. You can specify multiple rules; e.g.
        /// "aac>m4a/mov>mp4/mkv" will remux aac to m4a,
        /// mov to mp4 and anything else to mkv
        @"--remux-video": ?[]const u8 = null,

        /// Re-encode the video into another format if
        /// necessary. The syntax and supported formats
        /// are the same as --remux-video
        @"--recode-video": ?[]const u8 = null,

        /// Keep the intermediate video file on disk
        /// after post-processing
        @"--keep-video": bool = false,

        /// Delete the intermediate video file after
        /// post-processing (default)
        @"--no-keep-video": bool = false,

        /// Overwrite post-processed files (default)
        @"--post-overwrites": bool = false,

        /// Do not overwrite post-processed files
        @"--no-post-overwrites": bool = false,

        /// Embed subtitles in the video (only for mp4,
        /// webm and mkv videos)
        @"--embed-subs": bool = false,

        /// Do not embed subtitles (default)
        @"--no-embed-subs": bool = false,

        /// Embed thumbnail in the video as cover art
        @"--embed-thumbnail": bool = false,

        /// Do not embed thumbnail (default)
        @"--no-embed-thumbnail": bool = false,

        /// Embed metadata to the video file. Also
        /// embeds chapters/infojson if present unless
        /// --no-embed-chapters/--no-embed-info-json are
        /// used (Alias: --add-metadata)
        @"--embed-metadata": bool = false,

        /// Do not add metadata to file (default)
        /// (Alias: --no-add-metadata)
        @"--no-embed-metadata": bool = false,

        /// Add chapter markers to the video file
        /// (Alias: --add-chapters)
        @"--embed-chapters": bool = false,

        /// Do not add chapter markers (default) (Alias:
        /// --no-add-chapters)
        @"--no-embed-chapters": bool = false,

        /// Embed the infojson as an attachment to
        /// mkv/mka video files
        @"--embed-info-json": bool = false,

        /// Do not embed the infojson as an attachment
        /// to the video file
        @"--no-embed-info-json": bool = false,

        /// Parse additional metadata like title/artist
        /// from other fields; see "MODIFYING METADATA"
        /// for details. Supported values of "WHEN" are
        /// the same as that of --use-postprocessor
        /// (default: pre_process)
        @"--parse-metadata": ?[]const u8 = null,

        /// Replace text in a metadata field using the
        /// given regex. This option can be used
        /// multiple times. Supported values of "WHEN"
        /// are the same as that of --use-postprocessor
        /// (default: pre_process)
        @"--replace-in-metadata": ?[]const u8 = null,

        /// Write metadata to the video file's xattrs
        /// (using Dublin Core and XDG standards)
        @"--xattrs": bool = false,

        /// Location of the ffmpeg binary; either the
        /// path to the binary or its containing directory
        @"--ffmpeg-location": ?[]const u8 = null,

        /// Convert the subtitles to another format
        /// (currently supported: ass, lrc, srt, vtt).
        /// Use "--convert-subs none" to disable
        /// conversion (default) (Alias: --convert-
        /// subtitles)
        @"--convert-subs": ?[]const u8 = null,

        /// Convert the thumbnails to another format
        /// (currently supported: jpg, png, webp). You
        /// can specify multiple rules using similar
        /// syntax as "--remux-video". Use "--convert-
        /// thumbnails none" to disable conversion
        /// (default)
        @"--convert-thumbnails": ?[]const u8 = null,

        /// Split video into multiple files based on
        /// internal chapters. The "chapter:" prefix can
        /// be used with "--paths" and "--output" to set
        /// the output filename for the split files. See
        /// "OUTPUT TEMPLATE" for details
        @"--split-chapters": bool = false,

        /// Do not split video based on chapters (default)
        @"--no-split-chapters": bool = false,
    };

    // }}}
};

pub const PrintToFile = struct {
    when: ?[]const u8,
    type: []Output.Type,
    file: []const u8,
};

pub const Path = struct {
    type: Type,
    path: []const u8,

    pub const Type = enum {
        subtitle,
        thumbnail,
        description,
        /// deprecated
        annotation, 
        infojson,
        link,
        pl_thumbnail,
        pl_description,
        pl_infojson,
        chapter, 
        pl_video,

        // aditional
        home,
        temp,

        // misc
        none,
    };
};


/// https://github.com/yt-dlp/yt-dlp?tab=readme-ov-file#output-template
pub const Output = struct {
    type: Type = .none,
    fmt: []const u8,

    pub const Type = enum {
        subtitle,
        thumbnail,
        description,
        /// deprecated
        annotation, 
        infojson,
        link,
        pl_thumbnail,
        pl_description,
        pl_infojson,
        chapter, 
        pl_video,
        none,

        pub fn prefix(self: @This()) []const u8 {
            switch (self) {
                .none => "",
                inline else => |tag| @tagName(tag) ++ ":",
            }
        }
    };

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.writeAll(self.type.prefix());
        try writer.writeAll(self.fmt);
    }
};

// Note: Due to post-processing (i.e. merging etc.), the actual output filename
// might differ. Use --print after_move:filepath to get the name after all
// post-processing is complete.
//
// The available fields are:
//
// id                    (string): Video identifier
// title                 (string): Video title
// fulltitle             (string): Video title ignoring live timestamp and generic title
// ext                   (string): Video filename extension
// alt_title             (string): A secondary title of the video
// description           (string): The description of the video
// display_id            (string): An alternative identifier for the video
// uploader              (string): Full name of the video uploader
// uploader_id           (string): Nickname or id of the video uploader
// uploader_url          (string): URL to the video uploader's profile
// license               (string): License name the video is licensed under
// creators                (list): The creators of the video
// creator               (string): The creators of the video; comma-separated
// timestamp             (numeric): UNIX timestamp of the moment the video became available
// upload_date           (string): Video upload date in UTC (YYYYMMDD)
// release_timestamp     (numeric): UNIX timestamp of the moment the video was released
// release_date          (string): The date (YYYYMMDD) when the video was released in UTC
// release_year          (numeric): Year (YYYY) when the video or album was released
// modified_timestamp    (numeric): UNIX timestamp of the moment the video was last modified
// modified_date         (string): The date (YYYYMMDD) when the video was last modified in UTC
// channel               (string): Full name of the channel the video is uploaded on
// channel_id            (string): Id of the channel
// channel_url           (string): URL of the channel
// channel_follower_count(numeric): Number of followers of the channel
// channel_is_verified   (boolean): Whether the channel is verified on the platform
// location              (string): Physical location where the video was filmed
// duration              (numeric): Length of the video in seconds
// duration_string       (string): Length of the video (HH:mm:ss)
// view_count            (numeric): How many users have watched the video on the platform
// concurrent_view_count (numeric): How many users are currently watching the video on the platform.
// like_count            (numeric): Number of positive ratings of the video
// dislike_count         (numeric): Number of negative ratings of the video
// repost_count          (numeric): Number of reposts of the video
// average_rating        (numeric): Average rating given by users, the scale used depends on the webpage
// comment_count         (numeric): Number of comments on the video (For some extractors, comments are only downloaded at the end, and so this field cannot be used)
// save_count            (numeric): Number of times the video has been saved or bookmarked
// age_limit             (numeric): Age restriction for the video (years)
// live_status           (string): One of "not_live", "is_live", "is_upcoming", "was_live", "post_live" (was live, but VOD is not yet processed)
// is_live               (boolean): Whether this video is a live stream or a fixed-length video
// was_live              (boolean): Whether this video was originally a live stream
// playable_in_embed     (string): Whether this video is allowed to play in embedded players on other sites
// availability          (string): Whether the video is "private", "premium_only", "subscriber_only", "needs_auth", "unlisted" or "public"
// media_type            (string): The type of media as classified by the site, e.g. "episode", "clip", "trailer"
// start_time            (numeric): Time in seconds where the reproduction should start, as specified in the URL
// end_time              (numeric): Time in seconds where the reproduction should end, as specified in the URL
// extractor             (string): Name of the extractor
// extractor_key         (string): Key name of the extractor
// epoch                 (numeric): Unix epoch of when the information extraction was completed
// autonumber            (numeric): Number that will be increased with each download, starting at --autonumber-start, padded with leading zeros to 5 digits
// video_autonumber      (numeric): Number that will be increased with each video
// n_entries             (numeric): Total number of extracted items in the playlist
// playlist_id           (string): Identifier of the playlist that contains the video
// playlist_title        (string): Name of the playlist that contains the video
// playlist              (string): playlist_title if available or else playlist_id
// playlist_count        (numeric): Total number of items in the playlist. May not be known if entire playlist is not extracted
// playlist_index        (numeric): Index of the video in the playlist padded with leading zeros according the final index
// playlist_autonumber   (numeric): Position of the video in the playlist download queue padded with leading zeros according to the total length of the playlist
// playlist_uploader     (string): Full name of the playlist uploader
// playlist_uploader_id  (string): Nickname or id of the playlist uploader
// playlist_channel      (string): Display name of the channel that uploaded the playlist
// playlist_channel_id   (string): Identifier of the channel that uploaded the playlist
// playlist_webpage_url  (string): URL of the playlist webpage
// webpage_url           (string): A URL to the video webpage which, if given to yt-dlp, should yield the same result again
// webpage_url_basename  (string): The basename of the webpage URL
// webpage_url_domain    (string): The domain of the webpage URL
// original_url          (string): The URL given by the user (or the same as webpage_url for playlist entries)
// categories            (list): List of categories the video belongs to
// tags                  (list): List of tags assigned to the video
// cast                  (list): List of cast members
//
// All the fields in Filtering Formats can also be used
//
// Available for the video that belongs to some logical chapter or section     :
//
// chapter (string)        : Name or title of the chapter the video belongs to
// chapter_number (numeric): Number of the chapter the video belongs to
// chapter_id (string)     : Id of the chapter the video belongs to
//
// Available for the video that is an episode of some series or program:
//
// series (string)                                                             : Title of the series or program the video episode belongs to
// series_id (string)                                                          : Id of the series or program the video episode belongs to
// season (string)                                                             : Title of the season the video episode belongs to
// season_number (numeric)                                                     : Number of the season the video episode belongs to
// season_id (string)                                                          : Id of the season the video episode belongs to
// episode (string)                                                            : Title of the video episode
// episode_number (numeric)                                                    : Number of the video episode within a season
// episode_id (string)                                                         : Id of the video episode
// 
// Available for the media that is a track or a part of a music album          :
//
// track (string)                                                              : Title of the track
// track_number (numeric)                                                      : Number of the track within an album or a disc
// track_id (string)                                                           : Id of the track
// artists (list)                                                              : Artist(s) of the track
// artist (string)                                                             : Artist(s) of the track; comma-separated
// genres (list)                                                               : Genre(s) of the track
// genre (string)                                                              : Genre(s) of the track; comma-separated
// composers (list)                                                            : Composer(s) of the piece
// composer (string)                                                           : Composer(s) of the piece; comma-separated
// album (string)                                                              : Title of the album the track belongs to
// album_type (string)                                                         : Type of the album
// album_artists (list)                                                        : All artists appeared on the album
// album_artist (string)                                                       : All artists appeared on the album; comma-separated
// disc_number (numeric)                                                       : Number of the disc or other physical medium the track belongs to
//
// Available only when using --download-sections and for chapter               : prefix when using --split-chapters for videos with internal chapters:
//
// section_title (string)                                                      : Title of the chapter
// section_number (numeric)                                                    : Number of the chapter within the file
// section_start (numeric)                                                     : Start time of the chapter in seconds
// section_end (numeric)                                                       : End time of the chapter in seconds
//
// Available only when used in --print                                         :
//
// urls (string)                                                               : The URLs of all requested formats, one in each line
// filename (string)                                                           : Name of the video file. Note that the actual filename may differ
// formats_table (table)                                                       : The video format table as printed by --list-formats
// thumbnails_table (table)                                                    : The thumbnail format table as printed by --list-thumbnails
// subtitles_table (table)                                                     : The subtitle format table as printed by --list-subs
// automatic_captions_table (table)                                            : The automatic subtitle format table as printed by --list-subs
