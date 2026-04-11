const std = @import("std");
const http = std.http;
const Uri = std.Uri;
const Io = std.Io;
const mem = std.mem;
const json = std.json;

const expectEqualDeep = std.testing.expectEqualDeep;
const assert = std.debug.assert;

const mb = @import("../music_brainz.zig");
const log = mb.log;

const MBID = mb.MBID;

const url = @import("../url.zig");

//  lookup:   /<ENTITY_TYPE>/<MBID>?inc=<INC>
// https://musicbrainz.org/ws/2/release-group/3bd76d40-7f0e-36b7-9348-91a33afee20e?inc=genres&fmt=json

pub const base_url = "https://musicbrainz.org/ws/2";
pub const base_uri = Uri.parse(base_url) catch unreachable;

// EntityType + Includes + Relations {{{
pub const EntityType = enum {
    area,
    /// recordings, releases, release-groups, works
    artist,
    /// (not implemented) user-collections (includes private collections, requires authentication)
    collection,
    event,
    genre,
    instrument,
    // releases
    label,
    place,
    recording,
    release,
    @"release-group",
    series,
    work,
    url,
};

/// https://musicbrainz.org/doc/MusicBrainz_API#:~:text=the%20Search%20page.-,Subqueries,-The%20inc=
///
/// !IMPORTANT! 
/// Everything with "user-" requires authentication, and is not implemented.
///
/// /ws/2/area
/// /ws/2/artist            recordings, releases, release-groups, works
/// /ws/2/collection        user-collections (includes private collections, requires authentication)
/// /ws/2/event
/// /ws/2/genre
/// /ws/2/instrument
/// /ws/2/label             releases
/// /ws/2/place
/// /ws/2/recording         releases, release-groups
/// /ws/2/release           collections, labels, recordings, release-groups
/// /ws/2/release-group     releases
/// /ws/2/series
/// /ws/2/work
/// /ws/2/url
pub const Entity = union(EntityType) {
    area: Default,
    artist: Artist,
    collection: Collection,
    event: Default,
    genre: Genre,
    instrument: Default,
    label: Label,
    place: Default,
    recording: Recording,
    release: Release,
    @"release-group": ReleaseGroup,
    series: Default,
    work: Default,
    url: Default,

    // default {{{
    pub const Default = struct {
        incl: MiscIncludes = .{},
        rels: Relations = .{},
        mbid: MBID,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{s}?fmt=json&inc=", .{self.mbid});
            _ = try formatStruct(self.incl, writer, true);
        }

        test format {
            var fmt_buf: [1024]u8 = undefined;
            var writer: Io.Writer = .fixed(&fmt_buf);

            const genre1: @This() = .{ .incl = .{
                .tags = true,
            }, .mbid = "00000000-0000-0000-0000-000000000000" };
            try genre1.format(&writer);
            try expectEqualDeep("00000000-0000-0000-0000-000000000000?fmt=json&inc=tags", writer.buffered());
            // _ = writer.consumeAll();
        }
    };
    // }}}

    // artist {{{
    pub const Artist = struct {
        incl: ArtistIncludes = .{},
        rels: Relations = .{},
        mbid: MBID,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{s}?fmt=json&inc=", .{self.mbid});
            _ = try formatStruct(self.incl, writer, true);
        }
    };

    pub const ArtistIncludes = packed struct(u13) {
        misc: MiscIncludes = .{},
        recordings: bool = false,
        releases: bool = false,
        @"release-groups": bool = false,
        works: bool = false,
        /// include only those releases where the artist appears on one of the
        /// tracks, but not in the artist credit for the release itself (this is
        /// only valid on a /ws/2/artist?inc=releases request).
        @"various-artists": bool = false,
    };
    // }}}

    // collection {{{
    pub const Collection = struct {
        incl: CollectionIncludes = .{},
        rels: Relations = .{},
        mbid: MBID,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{s}?fmt=json&inc=", .{self.mbid});
            _ = try formatStruct(self.incl, writer, true);
        }
    };

    pub const CollectionIncludes = packed struct(u9) {
        misc: MiscIncludes = .{},
        @"user-collections": bool = false,
    };
    // }}}

    // genre {{{
    pub const Genre = struct {
        incl: GenreIncludes = .{},
        rels: Relations = .{},
        select: Select = .all,

        pub const Select = union(enum) {
            mbid: MBID,
            all,
        };

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            switch (self.select) {
                .all => try writer.writeAll("all"),
                .mbid => |mbid| try writer.writeAll(mbid),
            }
            if (self.incl.offset > 0) {
                try writer.print("?fmt=json&offset={d}", .{self.incl.offset});
            } else {
                try writer.writeAll("?fmt=json");
            }
            if (self.incl.limit >= 0) {
                try writer.print("&limit={d}", .{self.incl.limit});
            }
        }

        test format {
            var fmt_buf: [1024]u8 = undefined;
            var writer: Io.Writer = .fixed(&fmt_buf);

            const genre1: @This() = .{ .incl = .{}, .select = .all };
            try genre1.format(&writer);
            try expectEqualDeep("all?fmt=json", writer.buffered());
            _ = writer.consumeAll();

            const genre2: @This() = .{ .incl = .{ .limit = 10, .offset = 50 }, .select = .{ .mbid = "00000000-0000-0000-0000-000000000000" } };
            try genre2.format(&writer);
            try expectEqualDeep("00000000-0000-0000-0000-000000000000?fmt=json&offset=50&limit=10", writer.buffered());
            // _ = writer.consumeAll();
        }
    };

    pub const GenreIncludes = packed struct(u20) {
        /// limit < 0 -> not in query (unset); I think the max is 100.
        limit: i8 = -1,
        offset: u12 = 0,
    };
    // }}}
    
    // recording {{{
    pub const Recording = struct {
        incl: RecordingIncludes = .{},
        rels: RecordingRelations = .{},
        mbid: MBID,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{s}?fmt=json&inc=", .{self.mbid});
            _ = try formatStruct(self.incl, writer, true);
        }
    };

    pub const RecordingIncludes = packed struct(u12) {
        misc: MiscIncludes = .{},
        releases: bool = false,
        @"release-groups": bool = false,
        /// include artists credits for all releases and recordings
        @"artist-credits": bool = false, 
        /// include isrcs for all recordings
        isrcs: bool = false,
    };

    /// In a release request, you might also be interested on relationships for the
    /// recordings linked to the release, or the release group linked to the
    /// release, or even for the works linked to those recordings that are linked
    /// to the release (for example, to find out who played guitar on a specific
    /// track, who wrote the lyrics for the song being performed, or whether the
    /// release group is part of a series). Similarly, for a recording request, you
    /// might want to get the relationships for any linked works. 
    ///
    /// Keep in mind these just act as switches. If you request work-level-rels for
    /// a recording, you will still need to request work-rels (to get the
    /// relationship from the recording to the work in the first place) and any
    /// other relationship types you want to see (for example, artist-rels if you
    /// want to see work-artist relationships).
    pub const RecordingRelations = packed struct(u14) {
        rels: Relations = .{},
        @"work-level-rels": bool = false,
    };
    // }}}

    // release {{{
    pub const Release = struct {
        incl: ReleaseIncludes = .{},
        rels: ReleaseRelations = .{},
        mbid: MBID,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{s}?fmt=json&inc=", .{self.mbid});
            _ = try formatStruct(self.incl, writer, true);
        }
    };

    pub const ReleaseIncludes = packed struct(u16) {
        misc: MiscIncludes = .{},
        recordings: bool = false,
        @"release-groups": bool = false,
        labels: bool = false,
        /// include artists credits for all releases and recordings
        @"artist-credits": bool = false,
        /// include discids for all media in the releases
        discids: bool = false,
        /// include media for all releases, this includes the # of tracks on each
        /// medium and its format.
        media: bool = false,
        /// include isrcs for all recordings
        isrcs: bool = false, 
        collections: bool = false,
    };

    /// In a release request, you might also be interested on relationships for the
    /// recordings linked to the release, or the release group linked to the
    /// release, or even for the works linked to those recordings that are linked
    /// to the release (for example, to find out who played guitar on a specific
    /// track, who wrote the lyrics for the song being performed, or whether the
    /// release group is part of a series). Similarly, for a recording request, you
    /// might want to get the relationships for any linked works. 
    ///
    /// Keep in mind these just act as switches. If you request work-level-rels for
    /// a recording, you will still need to request work-rels (to get the
    /// relationship from the recording to the work in the first place) and any
    /// other relationship types you want to see (for example, artist-rels if you
    /// want to see work-artist relationships).
    pub const ReleaseRelations = packed struct(u16) {
        rels: Relations = .{},
        @"work-level-rels": bool = false,
        @"recording-level-rels": bool = false,
        @"release-group-level-rels": bool = false,
    };
    // }}}

    // release-group {{{
    pub const ReleaseGroup = struct {
        incl: ReleaseGroupIncludes = .{},
        rels: Relations = .{},
        mbid: MBID,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{s}?fmt=json&inc=", .{self.mbid});
            _ = try formatStruct(self.incl, writer, true);
        }
    };

    pub const ReleaseGroupIncludes = packed struct(u10) {
        misc: MiscIncludes = .{},
        releases: bool = false,
        /// include artists credits for all releases and recordings
        @"artist-credits": bool = false,
    };
    // }}}

    // label {{{
    pub const Label = struct {
        incl: LabelIncludes = .{},
        rels: Relations = .{},
        mbid: MBID,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("{s}?fmt=json&inc=", .{self.mbid});
            _ = try formatStruct(self.incl, writer, true);
        }
    };

    pub const LabelIncludes = packed struct(u9) {
        misc: MiscIncludes = .{},
        releases: bool = false,
    };
    // }}}
};

/// inc= arguments which affect subqueries
/// Some additional inc= parameters are supported to specify how much of the data about the linked entities should be included.
pub const MiscIncludes = packed struct(u8) {
    /// include artist, label, area or work aliases; treat these as a set, as they are not deliberately ordered
    aliases: bool = false,
    /// include annotation
    annotation: bool = false,
    /// include tags for the entity
    tags: bool = false,
    /// include ratings for the entity
    ratings: bool = false,
    /// same as tags, but only return the tags submitted by the specified user
    @"user-tags": bool = false,
    /// same as ratings, but only return the ratings submitted by the specified user
    @"user-ratings": bool = false,
    /// include all genres (tags in the genres list)
    genres: bool = false,
    /// include genres (tags in the genres list) submitted by the user
    @"user-genres": bool = false,
};

/// These will load relationships between the requested entity and the specific
/// entity type. For example, if you request "work-rels" when looking up an
/// artist, you'll get all the relationships between this artist and any works,
/// and if you request "artist-rels" you'll get the relationships between this
/// artist and any other artists. As such, keep in mind requesting
/// "artist-rels" for an artist, "release-rels" for a release, etc. will not
/// load all the relationships for the entity, just the ones to other entities
/// of the same type.
pub const Relations = packed struct(u13) {
    @"area-rels": bool = false,
    @"artist-rels": bool = false,
    @"event-rels": bool = false,
    @"genre-rels": bool = false,
    @"instrument-rels": bool = false,
    @"label-rels": bool = false,
    @"place-rels": bool = false,
    @"recording-rels": bool = false,
    @"release-rels": bool = false,
    @"release-group-rels": bool = false,
    @"series-rels": bool = false,
    @"url-rels": bool = false,
    @"work-rels": bool = false,
};
// }}}

/// formtats a struct (containing only booleans, and similar structs) to "fieldname1+fieldname2+..."
pub fn formatStruct(value: anytype, writer: *Io.Writer, first: bool) Io.Writer.Error!bool {
    const V = @TypeOf(value);
    comptime assert(@typeInfo(V) == .@"struct");

    var f: bool = first;

    inline for (@typeInfo(V).@"struct".fields) |field| {
        if (field.type == bool) {
            if (@field(value, field.name)) {
                if (!f) {
                    try writer.writeByte('+');
                } else {
                    f = false;
                }
                try writer.writeAll(field.name);
            }
        } else {
            f = try formatStruct(@field(value, field.name), writer, f);
        }
    }

    return f;
}

pub const Error = error{
    MBIDNotValidUUID,
    NoReleasesFound,
    MusizBrainzAPIChanged,
    ExceededRateLimit,
    UnexpectedSatusCode,
};

pub const LookupError = Error || http.Client.FetchError || Io.Writer.Error || error{BufferUnderrun,DuplicateField,InvalidCharacter,InvalidEnumTag,InvalidNumber,LengthMismatch,MissingField,OutOfMemory,Overflow,SyntaxError,UnexpectedEndOfInput,UnexpectedToken,UnknownField,ValueTooLong};

/// /<ENTITY_TYPE>/<MBID>?inc=<INC>
///
/// 307 redirect to an index.json file, if there is a release with this MBID.
/// 400 if {mbid} cannot be parsed as a valid UUID.
/// 404 if there is no release with this MBID.
/// 405 if the request method is not one of GET or HEAD.
/// 406 if the server is unable to generate a response suitable to the Accept header.
/// 503 if the user has exceeded their rate limit.
pub fn lookupValue(client: *http.Client, allocator: mem.Allocator, entity: *const Entity) LookupError!json.Parsed(json.Value) {
    var lookup_url_buf: [2048]u8 = undefined;
    var lookup_url_writer: Io.Writer = .fixed(&lookup_url_buf);
    try formatUrl(entity, &lookup_url_writer);

    const lookup_url = lookup_url_writer.toArrayList();

    log.debug("lookup url: {s}", .{lookup_url.items});

    assert(mem.startsWith(u8, lookup_url.items, base_url));

    var body_writer: Io.Writer.Allocating = .init(allocator);
    defer body_writer.deinit();

    const fetch_res = try client.fetch(.{
        .location = .{ .url = lookup_url.items },
        .method = .GET,
        .response_writer = &body_writer.writer,
        .redirect_behavior = .init(1),
        .headers = .{ 
            .accept_encoding = .{ .override = "json" },
            .user_agent = .{ .override = mb.user_agent }
        },
    });

    var response = body_writer.toArrayList();
    defer response.deinit(allocator);

    log.debug("status: {t} ({d}); response body:\n{s}", .{fetch_res.status, @intFromEnum(fetch_res.status), response.items});

    switch (fetch_res.status) {
        // 200 
        .ok => {
            return try json.parseFromSlice(json.Value, allocator, response.items, .{});
        },
        // 400 if {mbid} cannot be parsed as a valid UUID.
        .bad_request => return Error.MBIDNotValidUUID,
        // 404 if there is no release with this MBID.
        .not_found => return Error.NoReleasesFound,
        // 405 if the request method is not one of GET or HEAD.
        .method_not_allowed => unreachable, // medthod is always GET
        // 406 if the server is unable to generate a response suitable to the Accept header.
        .not_acceptable => return Error.MusizBrainzAPIChanged,
        // 503 if the user has exceeded their rate limit.
        .service_unavailable => return Error.ExceededRateLimit,
        else => |status| {
            log.warn(
                "Got unexpected status code from '" ++ base_url ++ "' (status: {d}, {t}), response body: \n{s}", 
                .{@intFromEnum(status), status, response.items}
            );
            return Error.UnexpectedSatusCode;
        }
    }
}

pub fn formatUrl(entity: *const Entity, writer: *Io.Writer) Io.Writer.Error!void {
    try writer.writeAll(base_url);
    try writer.writeByte('/');
    try writer.writeAll(@tagName(entity.*));
    try writer.writeByte('/');

    switch (entity.*) {
        inline else => |s| try s.format(writer),
    }
}

// TODO: 
// All lookups which include release-groups allow a type= argument to filter
// the release-groups by a specific type. All lookups which include releases
// also allow the type= argument, and a status= argument is allowed.


// Note that the number of linked entities returned is always limited to 25. If
// you need the remaining results, you will have to perform a browse request.


// https://musicbrainz.org/ws/2/release-group/{mbid}?inc=genres+user-genres&fmt=json
//
// Relationships
// You can request relationships with the appropriate includes:
//
//  - area-rels
//  - artist-rels
//  - event-rels
//  - genre-rels
//  - instrument-rels
//  - label-rels
//  - place-rels
//  - recording-rels
//  - release-rels
//  - release-group-rels
//  - series-rels
//  - url-rels
//  - work-rels
//
//  additional
//   - recording-level-rels
//   - release-group-level-rels (for releases only)
//   - work-level-rels
//
// Keep in mind these just act as switches. If you request work-level-rels for
// a recording, you will still need to request work-rels (to get the
// relationship from the recording to the work in the first place) and any
// other relationship types you want to see (for example, artist-rels if you
// want to see work-artist relationships).

