const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const json = std.json;
const Io = std.Io;
const Uri = std.Uri;
const net = Io.net;
const http = std.http;
const mem = std.mem;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;

const expectEqualDeep = std.testing.expectEqualDeep;

const paths = @import("../../main.zig").paths;

const cli = @import("cli.zig");
const shasums = @import("shasums.zig");
const Paths = @import("root.zig").Paths;
const log = @import("root.zig").log;

pub const asset_os = switch (builtin.os.tag) {
    .linux => switch (builtin.cpu.arch) {
        .aarch64_be, .aarch64 => "linux_aarch64",
        .arm, .armeb => "linux_armv7l",
        else => "linux",
    },
    .macos => "macos",
    .windows => switch (builtin.cpu.arch) {
        .aarch64 => "win_arm64",
        .x86 => "win_x86",
        else => "win",
    },
    else => @compileError("unsupported OS"),
};

pub const asset_binary_prefix = "yt-dlp_";
pub const asset_binary_name = asset_binary_prefix ++ asset_os;

pub const sha2_256sums_name = "SHA2-256SUMS";
pub const sha2_512sums_name = "SHA2-512SUMS";

pub const last_latest_release_response_json_file_name = "release.json";

pub const latest_release_url = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest";
pub const latest_release_uri = Uri.parse(latest_release_url) catch unreachable;

// update {{{

pub fn update(io: Io, gpa: Allocator) Io.Dir.CreateDirPathOpenError!void {
    if (Io.Dir.cwd().access(io, paths.p(&.{.yt_dlp, .bin}), .{})) {
        log.info("Updating yt-dlp", .{});
        if (cli.update(io)) |term| {
            switch (term) {
                .exited => |status| {
                    if (status == 0) return;
                    log.warn("Failed to update yt-dlp, exited with '{d}'", .{status});
                },
                .signal => |sig| log.warn("Failed to update yt-dlp, recevied signal '{any}'", .{sig}),
                .stopped => |sig| log.warn("Failed to update yt-dlp, stopped with '{any}'", .{sig}),
                .unknown => |unknown| log.warn("Failed to update yt-dlp, returned unknown '{d}'", .{unknown}),
            }
        } else |err| {
            log.warn("Failed to update yt-dlp with error '{t}'", .{err});
        }

        log.info("Now trying to download update from github", .{});
    } else |err| {
        err catch {};
    }

    var client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    const dir = try std.Io.Dir.createDirPathOpen(.cwd(), io, paths.p(&.{.yt_dlp}), .{});
    defer dir.close(io);

    var result = downloadLatest(io, &client, dir, paths.yt_dlp, gpa, .always);

    if (result) |*r| {
        switch (r.*) {
            .github_error => |status| {
                log.err("github responded with unexpected status code '{t}'", .{status});
            },
            .ok => |*ok| {
                defer ok.assets.deinit(gpa);
                for (ok.assets.items) |*asset| {
                    defer asset.asset.deinit(gpa);
                    switch (asset.download_result) {
                        .@"error" => |err| {
                            log.err("Failed to download asset '{s}' with error '{t}'", .{asset.asset.name, err});
                        },
                        .ok => |a| switch (a) {
                            .would_overwrite => log.warn("Downloading asset '{s}' would overwrite", .{asset.asset.name}),
                            .status => |status| {
                                if (status == .ok) {
                                    log.info("Successfully downloaded '{s}'", .{asset.asset.name});
                                } else {
                                    log.info("Unexpected status code downloading '{s}' (status: {t})", .{asset.asset.name, status});
                                }
                            }
                        }
                    }
                }
                // const verify_result = ok.verification_result catch |err| {
                //     std.debug.print("Failed to verify sha sums: '{t}'", .{err});
                //     return;
                // };
                // std.debug.print("verified {any}", .{verify_result});
            }
        }
    } else |err| {
        log.err("Download failed with error '{t}'", .{err});
    }
}

// }}}

// release json parse struct {{{

const ReleaseAsset = struct {
    url: []const u8,
    browser_download_url: []const u8,
    name: []const u8,
    label: ?[]const u8,
    state: enum { uploaded, open },
    content_type: []const u8,
    size: i64,

    pub fn clone(self: *const @This(), gpa: Allocator) error{OutOfMemory}!@This() {
        var out: @This() = undefined;
        out.url = try gpa.dupe(u8, self.url);
        out.browser_download_url = try gpa.dupe(u8, self.browser_download_url);
        out.name = try gpa.dupe(u8, self.name);

        if (self.label) |label| {
            out.label = try gpa.dupe(u8, label);
        } else {
            out.label = null;
        }

        out.state = self.state;
        out.content_type = try gpa.dupe(u8, self.content_type);
        out.size = self.size;

        return out;
    }

    pub fn deinit(self: *@This(), gpa: Allocator) void {
        gpa.free(self.url);
        gpa.free(self.browser_download_url);
        gpa.free(self.name);
        if (self.label) |l| gpa.free(l);
        gpa.free(self.content_type);
    }
};

const Release = struct {
    assets: []ReleaseAsset,
};

// }}}

pub const OverwriteMode = enum {
    always,
    if_not_same_size,
    never,
};

// download latest {{{

pub const DownloadLatestError = Io.File.Writer.Error || Io.Dir.CreateDirPathOpenError || http.Client.FetchError || json.ParseFromValueError || error{
    GithubNotFound,
    GithubServerError,
    // json errors
    SyntaxError,
    UnexpectedEndOfInput,
    BufferUnderrun,
    ValueTooLong,
};

pub const DownloadLatestResultAssetsItem = struct {
    asset: ReleaseAsset,
    download_result: DownloadAssetUnion,

};
pub const DownloadLatestResult = union(enum) {
    github_error: http.Status,
    ok: Ok,

    const Ok = struct {
        assets: ArrayList(DownloadLatestResultAssetsItem),
        // verification_result: @typeInfo(@TypeOf(shasums.verifyShaSums)).@"fn".return_type.?,
    };
};

/// docs: https://docs.github.com/de/rest/releases/releases?apiVersion=2026-03-10#get-the-latest-release
pub fn downloadLatest(
    io: Io,
    client: *http.Client,
    dir: Io.Dir,
    yt_paths: Paths,
    gpa: Allocator,
    overwrite: OverwriteMode,
) DownloadLatestError!DownloadLatestResult {
    var response_writer: Io.Writer.Allocating = .init(gpa);
    defer response_writer.deinit();

    std.debug.print("fetching releases from github\n", .{});
    const status = try fetchLatestRelease(client, &response_writer.writer);

    if (status != .ok) {
        if (status == .not_found) return error.GithubNotFound;
        return @unionInit(DownloadLatestResult, "github_error", status);
    }

    var response_array_list = response_writer.toArrayList();
    defer response_array_list.deinit(gpa);
    const response = response_array_list.items;

    const parsed_release = try json.parseFromSlice(Release, gpa, response, .{ .ignore_unknown_fields = true });
    defer parsed_release.deinit();

    const bin_dir = try dir.createDirPathOpen(io, yt_paths.bin, .{});
    defer bin_dir.close(io);

    // write the response to a file
    var response_file = try bin_dir.createFile(io, last_latest_release_response_json_file_name, .{ .truncate = true });
    defer response_file.close(io);

    try response_file.writeStreamingAll(io, response);

    // parse the response data
    var download_results: ArrayList(DownloadLatestResultAssetsItem) = try .initCapacity(gpa, 4);
    errdefer download_results.deinit(gpa);

    for (parsed_release.value.assets) |asset| {
        std.debug.print("asset '{s}'\n", .{asset.name});
        if (asset.size > 0 
            and (mem.eql(u8, asset.name, sha2_256sums_name)
            or mem.eql(u8, asset.name, sha2_512sums_name)
            or mem.eql(u8, asset.name, asset_binary_name))) {

            const download_result = download_results.addOne(gpa) catch break;
            download_result.asset = try asset.clone(gpa);

            if (downloadAsset(io, client, bin_dir, gpa, asset, overwrite)) |v| {
                download_result.download_result = @unionInit(DownloadAssetUnion, "ok", v);
            } else |err| {
                download_result.download_result = @unionInit(DownloadAssetUnion, "error", err);
            }
        }
    }

    
    // TODO: throws a bus error.
    // const verify_sha_sums_result = shasums.verifyShaSums(
    //     io,
    //     gpa,
    //     bin_dir,
    //     asset_binary_name,
    //     sha2_256sums_name,
    //     sha2_512sums_name,
    //     64 * 1024
    // );

    return @unionInit(DownloadLatestResult, "ok", .{
        .assets = download_results,
        // .verification_result = verify_sha_sums_result,
    });
}

// }}}

// download asset {{{

pub const DownloadAssetError = Io.File.SetLengthError || Io.File.Writer.Error || Io.File.StatError || Io.File.OpenError || http.Client.FetchError || error{
    OutOfMemory,
};

pub const DownloadAssetResult = union(enum) {
    would_overwrite,
    status: http.Status,
};

pub const DownloadAssetUnion = union(enum) {
    @"error": DownloadAssetError,
    ok: DownloadAssetResult,
};

pub fn downloadAsset(
    io: Io,
    client: *http.Client,
    dir: Io.Dir,
    gpa: Allocator,
    asset: ReleaseAsset,
    overwrite: OverwriteMode,
) DownloadAssetError!DownloadAssetResult {
    const file = dir.createFile(io, asset.name, .{ 
        .exclusive = overwrite == .never,
        .truncate = false, 
    }) catch |err| switch (err) {
        error.PathAlreadyExists => return @unionInit(DownloadAssetResult, "would_overwrite", {}),
        else => return err,
    };
    defer file.close(io);

    if (overwrite == .if_not_same_size) {
        const stats = try file.stat(io);
        if (@as(i64, @intCast(stats.size)) == asset.size) {
            return @unionInit(DownloadAssetResult, "would_overwrite", {});
        }
    }

    try file.setLength(io, 0);

    const write_buffer = try gpa.alloc(u8, 1024 * 1024);
    defer gpa.free(write_buffer);

    var file_writer = file.writer(io, write_buffer);

    const fetch_res = try client.fetch(.{
        .location = .{ .url = asset.browser_download_url },
        .method = .GET,
        .response_writer = &file_writer.interface,
    });

    try file_writer.flush();

    return @unionInit(DownloadAssetResult, "status", fetch_res.status);
}

// }}}

// fetch latest release {{{

pub fn fetchLatestRelease(
    client: *http.Client,
    writer: *Io.Writer,
) http.Client.FetchError!http.Status {
    const fetch_res = try client.fetch(.{
        .location = .{ .uri = latest_release_uri },
        .method = .GET,
        .response_writer = writer,
        .headers = .{ .accept_encoding = .{ .override = "application/vnd.github+json" } },
        .extra_headers = &.{
            .{ .name = "X-GitHub-Api-Version", .value = "2026-03-10" },
        },
    });

    return fetch_res.status;
}

// }}}

test {
    std.testing.refAllDecls(@This());
}

