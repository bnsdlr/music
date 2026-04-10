const std = @import("std");
const fmt = std.fmt;
const http = std.http;
const Io = std.Io;
const math = std.math;
const mem = std.mem;

const assert = std.debug.assert;
const expectEqualDeep = std.testing.expectEqualDeep;

const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;

pub const UrlFormat = struct {
    field: []const u8,
    key_fmt: []const KeyFmtToken = &.{
        .field_name,
    },
    // if null: &names=<value1>&names=<value2>&...
    // else: &names=<value1><delimiter><value2><delimiter>...
    array_delimiter: ?[]const u8 = "+",
};

pub const KeyFmtToken = union(enum) {
    field_name,
    /// if the field is not only a single item (Vector, Slice, Array)
    /// if set to a function ptr, it will call the function with the index and use its return value 
    /// instead.
    index: ?*const fn (usize) i32,
    char: u8,
    string: []const u8,

    pub fn default(index: usize) i32 {
        return @intCast(index);
    }
};

pub const UrlQueryDelimiter = enum(u8) {
    first = '?',
    seperator = '&',
    none,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .first, .seperator => |c| try writer.writeByte(@intFromEnum(c)),
            else => {},
        }
    }
};

// fmtUrl {{{
/// Will format the url query.
///
/// # Formating
///
/// - null values are ignored.
/// - []const u8|[N]const u8 have to be valid url strings.
///
/// opts: struct {
///     id: i32,                        // required (&id=<id>)
///     title: []const u8,              // required (&title=<title_as_string>)
///     discno: ?u32 = null,            // optional (&discno=<discno> if not null)
///     artists: []const []const u8,    // required (&artists=<artist1>+<artist2>+...)
///     favorite: bool = false,         // optional with default (&favorite=false)
///     names: []const []const u8,
///
///     const url_formats: []const UrlFormat = &.{
///         .{ 
///             field = "names",
///             key_fmt = &.{
///                 KeyFmtToken{.field_name},
///                 KeyFmtToken{.char = '.'},
///                 KeyFmtToken{.index = null},
///             },
///             array_delimiter = null,
///         },              // &names.0=<name1>&names.1=<name2>&...
///     };
/// }
pub fn fmtUrlAlloc(allocator: Allocator, comptime base_url: ?[]const u8, opts: anytype) error{OutOfMemory}!ArrayList(u8) {
    // TODO: check for valid strings
    const OptsType = @TypeOf(opts);
    comptime {
        if (@typeInfo(OptsType) != .@"struct") @compileError("'opts' have to be of type struct.");
    }

    var buf: ArrayList(u8) = .empty;
    try buf.ensureTotalCapacity(allocator, (if (base_url) |u| u.len else 0) + @sizeOf(OptsType));
    if (base_url) |payload| {
        buf.printAssumeCapacity(payload, .{});
    }

    const opts_info = @typeInfo(OptsType).@"struct";

    var first: bool = true;

    const formats: ?[]const UrlFormat = blk: {
        inline for (opts_info.decls) |decl| {
            if (@TypeOf(@field(OptsType, decl.name)) == []const UrlFormat) {
                break :blk @field(OptsType, decl.name);
            }
        }
        break :blk null;
    };
    
    inline for (opts_info.fields) |field| {
        const delimiter: UrlQueryDelimiter = if (base_url == null and first) 
                .none
            else if (first) 
                .first 
            else 
                .seperator;

        if (try appendToUrl(allocator, &buf, field.name, @field(opts, field.name), delimiter, formats)) {
            first = false;
        }
    }

    return buf;
}

// test fmtUrl {{{
test fmtUrlAlloc {
    const gpa = std.testing.allocator;

    const TestStruct = struct {
        format: ?enum {json, plain} = null,
        client: []const u8,
        duration: i64,
        fingerprint: []const u8,
        meta: ?[]const enum {recordings, recordingids, releases} = null,
    };
    
    var url1 = try fmtUrlAlloc(gpa, null, TestStruct{
        .client = "<client_str>",
        .duration = 123,
        .fingerprint = "<fingerprint>",
    });
    defer url1.deinit(gpa);
    try expectEqualDeep("client=<client_str>&duration=123&fingerprint=<fingerprint>", url1.items);
    
    var url2 = try fmtUrlAlloc(gpa, null, TestStruct{
        .client = "<client_str>",
        .duration = 123,
        .fingerprint = "<fingerprint>",
        .format = .json,
        .meta = &.{}
    });
    defer url2.deinit(gpa);
    try expectEqualDeep("format=json&client=<client_str>&duration=123&fingerprint=<fingerprint>&meta=", url2.items);
    
    var url3 = try fmtUrlAlloc(gpa, "", TestStruct{
        .client = "<client_str>",
        .duration = 123,
        .fingerprint = "<fingerprint>",
        .format = .json,
        .meta = &.{
            .recordings, 
            .recordingids,
            .releases,
        }
    });
    defer url3.deinit(gpa);
    try expectEqualDeep("?format=json&client=<client_str>&duration=123&fingerprint=<fingerprint>&meta=recordings+recordingids+releases", url3.items);

    const Advanced1 = struct {
        durations: []const i64,

        pub const example_url_formats: []const UrlFormat = &.{
            .{
                .field = "durations",
                .key_fmt = &.{
                    .field_name,
                    .{ .char = '.' },
                    .{ .index = null },
                },
                .array_delimiter = null,
            },
        };
    };
    var url4 = try fmtUrlAlloc(gpa, "", Advanced1{
        .durations = &.{
            123,
            456,
            789,
        },
    });
    defer url4.deinit(gpa);
    try expectEqualDeep("?durations.0=123&durations.1=456&durations.2=789", url4.items);

    const Advanced2 = struct {
        durations: []const i64,

        pub const example_url_formats: []const UrlFormat = &.{
            .{
                .field = "durations",
                .key_fmt = &.{
                    .field_name,
                    .{ .index = &index1 },
                    .{ .string = "._." },
                    .{ .index = &index0 },
                },
                .array_delimiter = null,
            },
        };

        fn index0(i: usize) i32 {
            return @intCast(i + 1);
        }
        
        fn index1(i: usize) i32 {
            return ~@as(i32, @intCast(i));
        }
    };
    var url5 = try fmtUrlAlloc(gpa, "", Advanced2{
        .durations = &.{
            -123,
            456,
            -789,
        },
    });
    defer url5.deinit(gpa);
    try expectEqualDeep("?durations-1._.1=-123&durations-2._.2=456&durations-3._.3=-789", url5.items);
}
/// }}}

pub fn appendToUrl(
    allocator: Allocator,
    buf: *ArrayList(u8),
    comptime name: []const u8,
    value: anytype,
    delimiter: UrlQueryDelimiter,
    comptime formats: ?[]const UrlFormat
) error{OutOfMemory}!bool {
    switch (@typeInfo(@TypeOf(value))) {
        .optional => {
            if (value != null) return try appendToUrl(allocator, buf, name, value.?, delimiter, formats);
            return false;
        },
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                return try appendToUrl(allocator, buf, name ++ "." ++ field.name, @field(value, field.name), delimiter, formats);
            }
        },
        .pointer => |info| switch (info.size) {
            .one => try buf.print(allocator, "{f}" ++ name ++ "={" ++ getFormatter(info.child) ++ "}", .{delimiter, value.*}),
            .slice => return fmtUrlSlice(allocator, buf, name, value, delimiter, formats),
            .many, .c => @compileError("'appendToUrl' not implemented for pointers of size `.many` or `.c`"),
        },
        .array => |info| return fmtUrlSlice(allocator, buf, name, value[0..info.len], delimiter, formats),
        .error_union => {
            if (value) |val| {
                return appendToUrl(allocator, buf, name, val, delimiter, formats);
            } else |err| {
                return appendToUrl(allocator, buf, name, err, delimiter, formats);
            }
        },
        .@"union" => {
            // TODO
            unreachable;
        },
        .vector => |info| {
            return fmtUrlSlice(allocator, buf, name, (&@as([info.len]info.child, value))[0..], delimiter, formats);
        },
        .bool => try buf.print(allocator, "{f}" ++ name ++ "={}", .{delimiter, value}),
        .int, .float, .comptime_int, .comptime_float => try buf.print(allocator, "{f}" ++ name ++ "={d}", .{delimiter, value}),
        .error_set, .@"enum", .enum_literal => try buf.print(allocator, "{f}" ++ name ++ "={t}", .{delimiter, value}),
        .null => return false,
        else => @compileError("'appendToUrl' not implemented for type '" ++ @typeName(@TypeOf(value)) ++ "'"),
    }
    return true;
}

pub fn fmtUrlSlice(
    allocator: Allocator,
    buf: *ArrayList(u8),
    comptime name: []const u8,
    value: anytype,
    delimiter: UrlQueryDelimiter,
    comptime formats: ?[]const UrlFormat,
) error{OutOfMemory}!bool {
    const info = @typeInfo(@TypeOf(value));
    comptime assert(info == .pointer and info.pointer.size == .slice);

    const formatter = getFormatter(info.pointer.child);

    if (info.pointer.child == u8) {
        try buf.print(allocator, "{f}" ++ name ++ "={s}", .{delimiter, value});
        return true;
    } else if (formats) |fmts| {
        inline for (fmts) |format| {
            if (mem.eql(u8, format.field, name)) {
                if (format.array_delimiter) |arr_delimiter| {
                    try buf.print(allocator, "{f}" ++ name ++ "=", .{delimiter});
                    var f: bool = true;
                    for (value) |v| {
                        if (f) {
                            try buf.print(allocator, "{" ++ formatter ++ "}", .{v});
                            f = false;
                        } else {
                            try buf.print(allocator, arr_delimiter ++ "{" ++ formatter ++ "}", .{v});
                        }
                    }
                } else {
                    var current_delimiter: UrlQueryDelimiter = delimiter;
                    for (value, 0..) |v, i| {
                        const V = @TypeOf(v);
                        if (@typeInfo(V) == .optional and v == null) continue;
                        comptime var literal: []const u8 = "{f}";
                        comptime var index_fn: [10]?*const fn (usize) i32 = undefined;
                        comptime var index_fn_at_index: [10]usize = undefined;
                        comptime var index_fn_count = 0;

                        inline for (format.key_fmt) |key_fmt| {
                            switch (key_fmt) {
                                .char => |char| literal = literal ++ (&char)[0..1],
                                .index => |f| {
                                    index_fn_at_index[index_fn_count] = literal.len;
                                    literal = literal ++ "{d}";
                                    index_fn[index_fn_count] = f;
                                    index_fn_count += 1;
                                },
                                .field_name => literal = literal ++ name,
                                .string => |str| literal = literal ++ str,
                            }
                        }

                        comptime var print_arg_types: [12]type = undefined;
                        comptime var print_arg_types_len = 1;
                        print_arg_types[0] = UrlQueryDelimiter;
                        inline for (0..index_fn_count) |_| {
                            print_arg_types[print_arg_types_len] = i32;
                            print_arg_types_len += 1;
                        }
                        print_arg_types[print_arg_types_len] = V;
                        print_arg_types_len += 1;

                        const PrintArgType = @Tuple(print_arg_types[0..print_arg_types_len]);

                        var args: PrintArgType = undefined;
                        args[0] = current_delimiter;
                        inline for (0..index_fn_count) |a_i| {
                            args[a_i + 1] = if (index_fn[a_i]) |f| f(i) else KeyFmtToken.default(i);
                        }
                        args[print_arg_types_len-1] = v;

                        try buf.print(allocator, literal ++ "={" ++ formatter ++ "}", args);
                        if (current_delimiter != .seperator) current_delimiter = .seperator;
                     }
                }
                return true;
            }
        }
    } 

    try buf.print(allocator, "{f}" ++ name ++ "=", .{delimiter});
    var f: bool = true;
    for (value) |v| {
        if (f) {
            try buf.print(allocator, "{" ++ formatter ++ "}", .{v});
            f = false;
        } else {
            try buf.print(allocator, "+{" ++ formatter ++ "}", .{v});
        }
    }

    return true;
}
// }}}

inline fn getFormatter(comptime T: type) []const u8 {
    return comptime switch (@typeInfo(T)) {
        .@"struct" => "f",
        .error_set, .@"enum", .enum_literal => "t",
        .int, .float, .comptime_int, .comptime_float => "d",
        .bool, .null => "",
        .pointer => |info| switch (info.size) {
            .slice => if (info.child == u8) "s" else "any",
            .c, .many, .one => "any",
        },
        .array => |info| if (info.child == u8) "s" else "any",
        .optional => |info| {
            const child_info = @typeInfo(info.child);
            if (child_info == .pointer and child_info.pointer.child == u8) return "?s";
            return "any";
        },
        else => "any",
    };
}

test {
    std.testing.refAllDecls(@This());
}

