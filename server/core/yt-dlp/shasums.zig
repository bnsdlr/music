const builtin = @import("builtin");
const std = @import("std");
const crypto = std.crypto;
const sha2 = crypto.hash.sha2;
const Io = std.Io;
const net = Io.net;
const http = std.http;
const mem = std.mem;
const Allocator = mem.Allocator;

const expectEqualDeep = std.testing.expectEqualDeep;

// verify sha sums {{{

pub const VerifyShaSumsResult = struct {
    sha256_match: ?bool = null,
    sha512_match: ?bool = null,
};

pub fn verifyShaSums(
    io: Io,
    gpa: Allocator,
    dir: Io.Dir,
    /// File for that the sha's should match.
    sub_path: []const u8,
    sha256: ?[]const u8,
    sha512: ?[]const u8,
    chunk_size: usize,
) CalculateShaSumsError!VerifyShaSumsResult {
    const sums = try calculateShaSums(io, gpa, dir, sub_path, sha256 != null, sha512 != null, chunk_size);

    var sha256_eql = false;
    var sha512_eql = false;

    if (sums.sha256) |calculated_sha256| {
        if (sha256) |s256| {
            sha256_eql = mem.eql(u8, s256, calculated_sha256);
        }
    }

    if (sums.sha512) |calculated_sha512| {
        if (sha512) |s512| {
            sha512_eql = mem.eql(u8, s512, calculated_sha512);
        }
    }

    return .{
        .sha256_match = sha256_eql,
        .sha512_match = sha512_eql,
    };
}

// }}}

// calculate sha sums {{{

pub const CalculateShaSumsResult = struct {
    sha256: ?[]const u8 = null,
    sha512: ?[]const u8 = null,
};

pub const CalculateShaSumsError = error{OutOfMemory} || Io.File.OpenError || Io.Reader.ShortError;

pub fn calculateShaSums(
    io: Io,
    gpa: Allocator,
    dir: Io.Dir,
    sub_path: []const u8,
    sha256: bool,
    sha512: bool,
    chunk_size: usize,
) CalculateShaSumsError!CalculateShaSumsResult {
    if (!sha256 and !sha512) return .{};
    var calculate_sha256 = if (sha256) sha2.Sha256.init(.{}) else null;
    var calculate_sha512 = if (sha512) sha2.Sha512.init(.{}) else null;

    const file = try dir.openFile(io, sub_path, .{ .allow_directory = false });
    defer file.close(io);

    const buffer = try gpa.alloc(u8, chunk_size);

    const file_reader = file.reader(io, buffer);
    var reader = file_reader.interface;

    var c_size: usize = chunk_size;

    std.debug.print("stream read yt-dlp bin to sha calculators\n", .{});

    var i: usize = 0;
    while (true) : (i += 1) {
        std.debug.print("{d}\n", .{i});
        const bytes = reader.take(chunk_size) catch |err| {
            if (err == error.ReadFailed) return error.ReadFailed;
            std.debug.print("end: {d}\n", .{reader.end});
            c_size /= 2;
            continue;
        };
        if (calculate_sha256) |*s256| s256.update(bytes);
        if (calculate_sha512) |*s512| s512.update(bytes);
    }

    const sha256_sum: ?[]u8 = null;
    if (calculate_sha256) |s256| {
        const result = s256.finalResult();
        sha256_sum = try gpa.alloc(u8, result.len);
        @memcpy(sha256_sum, result);
    }

    const sha512_sum: ?[]u8 = null;
    if (calculate_sha512) |s512| {
        const result = s512.finalResult();
        sha512_sum = try gpa.alloc(u8, result.len);
        @memcpy(sha512_sum, result);
    }

    return .{
        .sha256 = sha256_sum,
        .sha512 = sha512_sum,
    };
}

// }}}

// get sha sums {{{

pub const GetShaSumOptions = struct {
    selector: Selector,
    file_sub_path: []const u8,
    file_size_limit: Io.Limit = .limited(10 * 1024),
    sha_lenght: Length,
};

pub const Selector = union(enum) {
    /// starts at 0
    line: usize,
    ends_with: []const u8,
    contains: []const u8,
};

pub const Length = union(enum) {
    all,
    first_chars: usize,
    last_chars: usize,
    first: Sha,
    last: Sha,

    pub const Sha = enum(u8) {
        sha256 = crypto.hash.sha2.Sha256.block_length,
        sha512 = crypto.hash.sha2.Sha512.block_length,
    };
};

pub fn getShaSum(
    io: Io,
    gpa: Allocator,
    dir: Io.Dir,
    opts: GetShaSumOptions
) Io.Dir.ReadFileAllocError!?[]const u8 {
    const contents = try dir.readFileAlloc(io, opts.file_sub_path, gpa, opts.file_size_limit);
    defer gpa.free(contents);

    const shasum_line = getShaSumFromBuffer(contents, opts.selector, opts.sha_lenght);

    if (shasum_line) |line| {
        const copied = try gpa.alloc(u8, line.len);
        @memcpy(copied, line);
        return copied;
    }
    return null;
}

pub fn getShaSumFromBuffer(contents: []const u8, selector: Selector, length: Length) ?[]const u8 {
    var iter = mem.splitScalar(u8, contents, '\n');

    var sha_line: ?[]const u8 = null;

    switch (selector) {
        .line => |num| {
            for (0..num) |_| if (iter.next() == null) return null;
            if (iter.next()) |line| sha_line = line;
        },
        .contains => |needle| {
            while (iter.next()) |line| {
                if (mem.containsAtLeast(u8, line, 1, needle)) {
                    sha_line = line;
                    break;
                }
            }
        },
        .ends_with => |needle| {
            while (iter.next()) |line| {
                if (mem.endsWith(u8, line, needle)) {
                    sha_line = line;
                    break;
                }
            }
        }
    }

    if (sha_line) |line| {
        const sha = switch (length) {
            .all => line,
            .first_chars => |len| line[0..@min(len, line.len)],
            .last_chars => |len| line[line.len -| len..],
            .first => |s| line[0..@min(@intFromEnum(s), line.len)],
            .last => |s| line[line.len -| @intFromEnum(s)..],
        };
        return sha;
    }
    return null;
}

test getShaSumFromBuffer {
    const sha_sums_file_content = 
        \\3bda0968a01cde70d26720653003b28553c71be14dcb2e5f4c24e9921fdad745  test
        \\e80c47b3ce712acee51d5e3d4eace2d181b44d38f1942c3a32e3c7ff53cd9ed5  some_test
        \\0123456789
        ;

    const shasum1 = getShaSumFromBuffer(sha_sums_file_content, .{ .ends_with = "test" }, .{ .first = .sha256 });
    try expectEqualDeep("3bda0968a01cde70d26720653003b28553c71be14dcb2e5f4c24e9921fdad745", shasum1);

    const shasum2 = getShaSumFromBuffer(sha_sums_file_content, .{ .contains = "some" }, .{ .first = .sha256 });
    try expectEqualDeep("e80c47b3ce712acee51d5e3d4eace2d181b44d38f1942c3a32e3c7ff53cd9ed5", shasum2);

    const shasum3 = getShaSumFromBuffer(sha_sums_file_content, .{ .line = 2 }, .{ .first = .sha256 });
    try expectEqualDeep("0123456789", shasum3);

    const shasum4 = getShaSumFromBuffer(sha_sums_file_content, .{ .line = 2 }, .{ .last = .sha256 });
    try expectEqualDeep("0123456789", shasum4);
}

// }}}

test {
    std.testing.refAllDecls(@This());
}

