const std = @import("std");
const http = std.http;
const Io = std.Io;

const expectEqualDeep = std.testing.expectEqualDeep;

const chromaprint = @import("../root.zig").chromaprint;

const url = @import("url.zig");

const music_brainz = @import("music_brainz.zig");

pub const ID = [36:0]u8;

pub const Status = enum {
    lookup,
    submit,
    submission_status,
    @"error",
};

pub const Response = union(Status) {
    lookup: Lookup,
    submit: Submit,
    submission_status: SubmissionStatus,
    @"error": Error,

    // {
    //   "status": "ok",
    //   "results": [
    //     {
    //       "id": "893796d1-419b-4654-8c01-f51b9e075e0c",
    //       "score": 0.985,
    //       "recordings": [
    //         {
    //           "id": "70c17f8d-6401-4475-87f5-20786520b991",
    //           "title": "Stairway to Heaven",
    //           "artists": [{"id": "678d9611-557c-4541-99ad-45cae2030f82", "name": "Led Zeppelin"}]
    //         }
    //       ]
    //     }
    //   ]
    // }
    pub const Lookup = struct {
        results: []Result,

        pub const Result = struct {
            id: ID,
            score: f32,
            recordings: []Recording,

            pub const Recording = struct {
                id: music_brainz.ID,
                title: []const u8,
                artists: []Artist,

                pub const Artist = struct {
                    id: ID,
                    name: []const u8,
                };
            };
        };
    };

    // {
    //   "status": "ok",
    //   "submissions": [
    //     {
    //       "id": 12345678,
    //       "status": "pending"
    //     }
    //   ]
    // }
    pub const Submit = struct {
    };

    //     {
    //   "status": "ok",
    //   "submissions": [{
    //     "id": 123456789,
    //     "status": "imported",
    //     "result": {
    //       "id": "9ff43b6a-4f16-427c-93c2-92307ca505e0"
    //     }
    //   }, {
    //     "id": 123456790,
    //     "status": "pending"
    //   }]
    // }
    pub const SubmissionStatus = struct {
    };

    // {"error": {"code": 2, "message": "missing required parameter \"client\""}, "status": "error"}
    pub const Error = struct {
        code: i32,
        message: []const u8,
    };
};

// API {{{
pub const base_url = "https://api.acoustid.org/v2";

pub const Metadata = enum {
    recordings, 
    recordingids,
    releases,
    releaseids,
    releasegroups,
    releasegroupids,
    tracks,
    compress,
    usermeta,
    sources,
};

pub const lookup = "lookup";
pub const lookup_url = base_url ++ "/" ++ lookup;

// lookup by fingerprint {{{
pub const LookupByFingerprintOptions = struct {
    format: ?enum{json, jsonp, xml} = null,
    /// JSONP callback, only applicable if you select the jsonp format
    // jsoncallback: ?*anyopaque = null,
    /// application's API key
    client: []const u8,
    /// duration of the whole audio file in seconds
    duration: i64,
    /// audio fingerprint data
    fingerprint: []const u8,
    /// returned metadata
    meta: ?[]const Metadata = null,
};

pub const lookup_by_fingerprint_base_url = "https://api.acoustid.org/v2/lookup";

pub fn lookupByFingerprint() void {
}
// }}}

// lookup by track id {{{
pub const LookupByTrackIDOptions = struct {
    format: ?enum{json, jsonp, xml} = null,
    /// JSONP callback, only applicable if you select the jsonp format
    // jsoncallback: ?*anyopaque = null,
    /// application's API key
    client: []const u8,
    /// track id (UUID)
    track_id: []const u8,
    /// returned metadata
    meta: ?[]const Metadata = null,
};

pub fn lookupByTrackID() void {
}
// }}}

// submit {{{
pub const submit = "submit";
pub const submit_url = base_url ++ "/" ++ submit;

pub const SubmitOptions = struct {
    /// response format
    format: ?enum{json, xml} = null,
    /// application's API key
    client: []const u8,
    /// application's version (e.g. '1.0')
    clientversion: ?[]const u8 = null,
    /// users's API key
    user: []const u8,

    // (duration.#) duration of the whole audio file in seconds
    duration: []const i64,
    // (fingerprint.#) audio fingerprint data
    fingerprint: []const []const u8,
    // (bitrate.#) bitrate of the audio file
    bitrate: ?[]const ?u32 = null,
    // (fileformat.#) (e.g. MP3, M4A, ...) file format of the audio file
    fileformat: ?[]const ?[]const u8 = null,
    // (mbid.#) (4e0d8649-1f89-44f3-91af-4c0dbee81f28) corresponding MusicBrainz recording ID
    mbid: ?[]const ?[]const u8 = null,
    // (track.#) track title
    track: ?[]const ?[]const u8 = null,
    // (artist.#) track artist
    artist: ?[]const ?[]const u8 = null,
    // (album.#) album title
    album: ?[]const ?[]const u8 = null,
    // (albumartist.#) album artist
    albumartist: ?[]const ?[]const u8 = null,
    // (year.#) album release year
    year: ?[]const ?i32 = null,
    // (trackno.#) track number
    trackno: ?[]const ?i32 = null,
    // (discno.#) disc number
    discno: ?[]const ?i32 = null,

    /// <name>.# (starting form 1)
    pub const key_fmt: []const url.KeyFmtToken = &.{ .field_name, .{.char = '.'}, .{.index = &index0} };

    pub const formats: []const url.UrlFormat = &.{
        .{ .field = "duration",     .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "fingerprint",  .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "bitrate",      .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "fileformat",   .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "mbid",         .key_fmt = key_fmt, .array_delimiter = null, }, 
        .{ .field = "track",        .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "artist",       .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "album",        .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "albumartist",  .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "year",         .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "trackno",      .key_fmt = key_fmt, .array_delimiter = null, },
        .{ .field = "discno",       .key_fmt = key_fmt, .array_delimiter = null, },
    };

    pub fn index0(index: usize) i32 {
        return @intCast(index + 1);
    }
};

test {
    const gpa = std.testing.allocator;
    var url1 = try url.fmtUrl(gpa, "", SubmitOptions{
        .client = "<client>",
        .user = "<user>",
        .clientversion = "1.0",
        .format = .xml,
        .duration = &.{123, 456},
        .fingerprint = &.{"<fp1>", "<fp2>"},
        .album = &.{null, "<album2>"},
        .albumartist = &.{"<albumartist1>", null},
        .artist = &.{"<artist1>", "<artist2>"},
        .discno = &.{1, null},
    });
    defer url1.deinit(gpa);
    // std.debug.print("'{s}'\n", .{url1.items});
    try expectEqualDeep("?format=xml&client=<client>&clientversion=1.0&user=<user>&duration.1=123&duration.2=456&fingerprint.1=<fp1>&fingerprint.2=<fp2>&artist.1=<artist1>&artist.2=<artist2>&album.2=<album2>&albumartist.1=<albumartist1>&discno.1=1", url1.items);
}
// }}}

// submission status {{{
pub const submission_status = "submission_status";
pub const submission_status_url = base_url ++ "/" ++ submission_status;

pub const SubmissionStatusOptions = struct {
    format: ?enum {json, xml} = null,
    /// application's API key
    client: []const u8,
    /// application's version (e.g. '1.0')
    clientversion: ?[]const u8 = null,
    /// ID, can be used multiple times
    id: []const usize,

    pub const formats: []const url.UrlFormat = &.{
        .{ .field = "id", .key_fmt = &.{ .field_name }, .array_delimiter = null, },
    };
};

test {
    const gpa = std.testing.allocator;
    var url1 = try url.fmtUrl(gpa, "", SubmissionStatusOptions{
        .client = "<client>",
        .id = &.{1, 2, 3},
        .clientversion = "1.0",
    });
    defer url1.deinit(gpa);
    try expectEqualDeep("?client=<client>&clientversion=1.0&id=1&id=2&id=3", url1.items);
}
// }}}

// }}}

test {
    std.testing.refAllDecls(@This());
}

