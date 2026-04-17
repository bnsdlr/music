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

const Paths = @import("../yt-dlp.zig").Paths;

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

pub const asset_binary_name = "yt-dlp_" ++ asset_os;

pub const sha2_256sums_name = "SHA2-256SUMS";
pub const sha2_512sums_name = "SHA2-512SUMS";

pub const last_latest_release_response_json_file_name = "release.json";

pub const latest_release_url = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest";
pub const latest_release_uri = Uri.parse(latest_release_url) catch unreachable;

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
    assets: ArrayList(DownloadLatestResultAssetsItem),
};

/// docs: https://docs.github.com/de/rest/releases/releases?apiVersion=2026-03-10#get-the-latest-release
pub fn downloadLatest(
    io: Io,
    client: *http.Client,
    dir: Io.Dir,
    paths: Paths,
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

    const bin_dir = try dir.createDirPathOpen(io, paths.bin, .{});
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

    return @unionInit(DownloadLatestResult, "assets", download_results);
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

