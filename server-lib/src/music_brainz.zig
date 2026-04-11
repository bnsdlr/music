const std = @import("std");

pub const cover_art_archive = @import("music_brainz/cover_art_archive.zig");
pub const lookup = @import("music_brainz/lookup.zig");

pub const json_response = @import("music_brainz/json_response_struct.zig");

pub const iso = @import("music_brainz/iso.zig");

pub const lookupEntityValue = lookup.lookupValue;
pub const Entity = lookup.Entity;

pub const MBID = *const [36:0]u8;

pub const log = std.log.scoped(.music_brainz);

// pub const user_agent = @import("root.zig").build_options.music_brainz_user_agent;
pub const user_agent = @import("build_options").music_brainz_user_agent;
pub const x = 1;

pub fn createUserAgent(comptime application_name: []const u8, comptime version: []const u8, comptime contact: []const u8) []const u8 {
    return application_name ++ "/" ++ version ++ " ( " ++ contact ++ " )";
}

test {
    std.testing.refAllDecls(@This());
}
