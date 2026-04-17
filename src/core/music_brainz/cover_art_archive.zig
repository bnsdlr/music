//! Documentation https://musicbrainz.org/doc/Cover_Art_Archive/API
//!
//! 307 redirect to an index.json file, if there is a release with this MBID.
//! 400 if {mbid} cannot be parsed as a valid UUID.
//! 404 if there is no release with this MBID.
//! 405 if the request method is not one of GET or HEAD.
//! 406 if the server is unable to generate a response suitable to the Accept header.
//! 503 if the user has exceeded their rate limit.

const std = @import("std");
const http = std.http;
const Uri = std.Uri;

// pub const base_url = "coverartarchive.org/release";
// pub const base_uri = Uri.parse(base_url) catch unreachable;

test {
    std.testing.refAllDecls(@This());
}
