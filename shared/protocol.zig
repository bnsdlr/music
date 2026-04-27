const builtin = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const Io = std.Io;
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;

const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const assert = std.debug.assert;
const Smith = std.testing.Smith;

const yt = @import("yt.zig");

pub const protocol_endian: std.builtin.Endian = .big;
pub const native_endian: std.builtin.Endian = .native;

// pub const ErrorSetInt = @Int(.unsigned, @bitSizeOf(anyerror));
pub const SliceLengthInt = u32;

// helper {{{

pub fn getUnionTag(comptime tag_type: type, comptime name: []const u8) tag_type {
    switch (@typeInfo(tag_type)) {
        .@"enum" => |info| {
            inline for (info.fields) |field| {
                if (comptime mem.eql(u8, field.name, name)) return @enumFromInt(field.value);
            }
        },
        else => @compileError("Expected enum found '" ++ @typeName(tag_type) ++ "'"),
    }
    @compileError("Enum does not have a field named '" ++ name ++ "'");
}

pub fn minimalBytes(comptime T: type) comptime_int {
    return (@bitSizeOf(T) / 8) + (if (@mod(@bitSizeOf(T), 8) != 0) 1 else 0);
}

pub fn FullByte(comptime T: type) type {
    switch (@typeInfo(T)) {
        .int => |info| {
            if (@mod(info.bits, 8) != 0) {
                return @Int(info.signedness, info.bits + (8 - @mod(info.bits, 8)));
            } else { 
                return T;
            }
        },
        else => return T,
    }
}

pub fn asFullByte(comptime T: type, value: *const T) FullByte(T) {
    switch (@typeInfo(T)) {
        .int => |info| {
            if (@mod(info.bits, 8) != 0) {
                return @as(FullByte(T), @intCast(value.*));
            } else { 
                return value.*;
            }
        },
        else => return value,
    }
}

// }}}

// serialize {{{

pub fn serialize(comptime T: type, value_ptr: *const T, writer: *Io.Writer) error{WriteFailed}!void {
    switch (@typeInfo(T)) {
        .int => {
            const native = mem.nativeTo(FullByte(T), asFullByte(T, value_ptr), protocol_endian);
            try writer.writeAll(mem.asBytes(&native));
        },
        .float => try writer.writeAll(mem.asBytes(value_ptr)),
        .bool => {
            try writer.writeByte(if (value_ptr.*) std.math.maxInt(u8) else 0);
        },
        .pointer => |info| switch (info.size) {
            .c, .many => @compileError("Serialization not implemented for type '" ++ @typeName(T) ++ "'"),
            .one => try serialize(info.child, (value_ptr.*), writer),
            .slice => {
                try serialize(SliceLengthInt, &@as(SliceLengthInt, @intCast(value_ptr.len)), writer);
                for (value_ptr.*) |item| try serialize(info.child, &item, writer);
            },
        },
        .array => |info| for (value_ptr.*) |item| try serialize(info.child, &item, writer),
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (info.layout == .@"packed") {
                    const v: field.type = @field(value_ptr.*, field.name);
                    try serialize(field.type, &v, writer);
                } else {
                    try serialize(field.type, &@field(value_ptr.*, field.name), writer);
                }
            }
        },
        .optional => |info| {
            if (value_ptr.*) |v| {
                try serialize(bool, &false, writer);
                try serialize(info.child, &v, writer);
            } else {
                try serialize(bool, &true, writer);
            }
        },
        // .error_union => |info| {
        //     std.debug.print("error_union: {any}\n", .{value.*});
        //     if (value.*) |*payload| {
        //         try serialize(bool, &false, writer);
        //         try serialize(info.payload, payload, writer);
        //     } else |err| {
        //         try serialize(bool, &true, writer);
        //         try serialize(info.error_set, &err, writer);
        //     }
        // },
        // .error_set => {
        //     const Int = @Int(.unsigned, @bitSizeOf(T));
        //     std.debug.print("error_set: {any} (int: {d})\n", .{value.*, @intFromError(value.*)});
        //     try serialize(Int, &@as(Int, @intFromError(value.*)), writer);
        // },
        .@"enum" => |info| try serialize(info.tag_type, &@as(info.tag_type, @intFromEnum(value_ptr.*)), writer),
        .@"union" => |info| {
            if (info.tag_type) |tag_type| {
                inline for (info.fields) |field| {
                    if (mem.eql(u8, field.name, @tagName(value_ptr.*))) {
                        try serialize(tag_type, &getUnionTag(tag_type, field.name), writer);
                        try serialize(field.type, &@field(value_ptr.*, field.name), writer);
                        break;
                    }
                }
            } else {
                @compileError("Can not serialize untaged union");
            }
        },
        .vector => |info| inline for (0..info.len) |i| try serialize(info.child, &value_ptr[i], writer),
        .void => {},
        else => {
            @compileError("No serialization implemented for type '" ++ @typeName(T) ++ "'");
        }
    }
}

// }}}

// deserialize {{{

pub fn deserialize(
    comptime T: type,
    out: *T,
    reader: *Io.Reader,
    allocator: Allocator
) error{OutOfMemory,ReadFailed,EndOfStream}!void {
    switch (@typeInfo(T)) {
        .int => {
            const Full = FullByte(T);
            const bytes = try reader.takeArray(@sizeOf(Full));
            out.* = @truncate(mem.toNative(Full, mem.bytesAsValue(Full, bytes).*, protocol_endian));
        },
        .float => {
            const bytes = try reader.takeArray(@sizeOf(T));
            out.* = mem.bytesAsValue(T, bytes).*;
        },
        .bool => out.* = (try reader.takeByte()) != 0,
        .pointer => |info| switch (info.size) {
            .c, .many => @compileError("Deserialization not implemented for type '" ++ @typeName(T) ++ "'"),
            .one => {
                const o: *info.child = try allocator.create(info.child);
                errdefer allocator.destroy(o);
                try deserialize(info.child, o, reader, allocator);
                out.* = o;
            },
            .slice => {
                var len: SliceLengthInt = 0;
                try deserialize(SliceLengthInt, &len, reader, allocator);
                var o: []info.child = try allocator.alloc(info.child, len);
                errdefer allocator.free(o);
                for (0..len) |i| {
                    try deserialize(info.child, &o[i], reader, allocator);
                }
                out.* = o;
            },
        },
        .array => |info| {
            for (0..info.len) |i| {
                try deserialize(info.child, &out[i], reader, allocator);
            }
        },
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (info.layout == .@"packed") {
                    var v: field.type = undefined;
                    try deserialize(field.type, &v, reader, allocator);
                    @field(out.*, field.name) = v;
                } else {
                    try deserialize(field.type, &@field(out.*, field.name), reader, allocator);
                }
            }
        },
        .optional => |info| {
            var is_null: bool = false;
            try deserialize(bool, &is_null, reader, allocator);
            if (!is_null) {
                try deserialize(info.child, @ptrCast(out), reader, allocator);
            } else {
                out.* = null;
            }
        },
        // .error_union => |info| {
        //     var is_err: bool = true;
        //     try deserialize(bool, &is_err, reader, allocator);
        //     std.debug.print("is error: {}\n", .{is_err});
        //     if (!is_err) {
        //         try deserialize(info.payload, @ptrCast(out), reader, allocator);
        //     } else {
        //         std.debug.print("error set type: {s}\n", .{@typeName(info.error_set)});
        //         try deserialize(info.error_set, @ptrCast(out), reader, allocator);
        //     }
        // },
        // .error_set => {
        //     const Int = @Int(.unsigned, @bitSizeOf(T));
        //     var error_int: Int = 0;
        //     try deserialize(Int, &error_int, reader, allocator);
        //     std.debug.print("error int: {d} (err: {any})\n", .{error_int, @as(T, @errorCast(@errorFromInt(error_int)))});
        //     out.* = @as(T, @errorCast(@errorFromInt(error_int)));
        //     std.debug.print("out: {any}\n", .{out.*});
        // },
        .@"enum" => |info| {
            var tag_int: info.tag_type = undefined;
            try deserialize(info.tag_type, &tag_int, reader, allocator);
            out.* = @enumFromInt(tag_int);
        },
        .@"union" => |info| {
            if (info.tag_type) |tag_type| {
                var tag: tag_type = undefined;
                try deserialize(tag_type, &tag, reader, allocator);

                inline for (info.fields) |field| {
                    if (mem.eql(u8, field.name, @tagName(tag))) {
                        var value: field.type = undefined;
                        try deserialize(field.type, &value, reader, allocator);
                        out.* = @unionInit(T, field.name, value);
                        return;
                    }
                }

                @panic("Failed to deserialize union, unkown field type");
            } else {
                @compileError("Can not deserialize untaged unions");
            }
        },
        .vector => |info| {
            const A = [info.len]info.child;
            var arr: A = undefined;
            try deserialize(A, &arr, reader, allocator);
            out.* = arr;
        },
        .void => {},
        else => {
            @compileError("No deserialization implemented for type '" ++ @typeName(T) ++ "'");
        }
    }
}

// }}}

// free {{{

pub fn free(value: anytype, allocator: Allocator) void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .pointer => freePtr(value, allocator),
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (@typeInfo(field.type) == .pointer) {
                    freePtr(@field(value, field.name), allocator);
                }
            }
        },
        .@"union" => |info| {
            inline for (info.fields) |field| {
                if (mem.eql(u8, field.name, @tagName(value))) {
                    free(@field(value, field.name), allocator);
                }
            }
        },
        else => {},
    }
}

pub fn freePtr(ptr: anytype, allocator: Allocator) void {
    const T = @TypeOf(ptr);
    const ptr_info = @typeInfo(T).pointer;

    switch (ptr_info.size) {
        .c, .many => @compileError("Cannot free c or many ptrs"),
        .one => {
            freeInternalOne(ptr_info.child, ptr, allocator);
            // std.debug.print("\x1b[31mdestroy\x1b[0m: {s}\n", .{@typeName(T)});
            allocator.destroy(ptr);
        },
        .slice => {
            freeInternalSlice(ptr_info.child, ptr, allocator);
        },
    }
}

fn freeInternalSlice(comptime child: type, ptr: []const child, allocator: Allocator) void {
    // std.debug.print("\x1b[33mfree slice\x1b[0m: []const {s}\n", .{@typeName(child)});
    switch (@typeInfo(child)) {
        .@"struct", .@"union", .pointer, .optional, .array, .vector => {
            for (0..ptr.len) |i| freeInternalOne(child, &ptr[i], allocator);
        },
        else => {},
    }
    allocator.free(ptr);
}

fn freeInternalOne(comptime child: type, ptr: *const child, allocator: Allocator) void {
    // std.debug.print("free one: *const {s}\n", .{@typeName(child)});
    switch (@typeInfo(child)) {
        .pointer => free(ptr.*, allocator),
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                free(@field(ptr.*, field.name), allocator);
            }
        },
        .@"union" => |info| {
            inline for (info.fields) |field| {
                if (mem.eql(u8, field.name, @tagName(ptr.*))) {
                    free(@field(ptr.*, field.name), allocator);
                    return;
                }
            }
        },
        .optional => if (ptr.* != null) free(ptr.*, allocator),
        .array => |info| for (ptr.*) |*v| freeInternalOne(info.child, v, allocator),
        .vector => |info| inline for (ptr.*) |v| freeInternalOne(info.child, v, allocator),
        else => {},
    }
}

// }}}

// tests {{{

// fuzzer {{{

pub fn Fuzzer(comptime types: anytype) type {
    comptime var min_bytes = 1;
    for (types) |T| {
        if (@sizeOf(T) > min_bytes) min_bytes = @sizeOf(T);
    }
    return struct {
        pub fn one(_: void, smith: *Smith) anyerror!void {
            while (!smith.eos()) {
                var buffer: [min_bytes * 2]u8 = undefined;
                var writer: Io.Writer = .fixed(&buffer);
                var reader: Io.Reader = .fixed(&buffer);

                inline for (types) |T| {
                    const v = smith.value(T);
                    try serialize(T, &v, &writer);
                    var out: T = undefined;
                    try deserialize(T, &out, &reader, std.testing.failing_allocator);

                    switch (@typeInfo(T)) {
                        .float => {
                            if (!std.math.isNan(v)) {
                                try expectEqualDeep(v, out);
                            }
                        },
                        else => try expect(std.meta.eql(v, out)),
                    }
                    _ = writer.consumeAll();
                    reader.seek = 0;
                }
            }
        }
    };
}

// }}}

// primitive types {{{

test "(fuzzer) primitive type serialization and deserialization" {
    const fuzzer = Fuzzer(.{
        u1, i1,
        u8, i8,
        u12, i12,
        u16, i16,
        u32, i32,
        u33, i33,
        u61, i61,
        u111, i111,
        u322, i322,
        f16,
        f32,
        f64,
        f80,
        f128,
        bool,
    });
    try std.testing.fuzz({}, fuzzer.one, .{});
}

test "primitive type serialization and deserialization" {
    const values = .{
        @as(u1, 0),
        @as(u1, 1),

        @as(u8, 'A'),
        @as(u8, 0),
        @as(u8, std.math.maxInt(u8)),

        @as(i10, std.math.minInt(i10)),
        @as(i10, 0),
        @as(i10, 190),
        @as(i10, std.math.maxInt(i10)),

        @as(i33, 0),
        @as(i33, 18276),
        @as(i33, std.math.maxInt(i33)),

        @as(i111, std.math.minInt(i111)),
        @as(i111, 0),
        @as(i111, 180820),
        @as(i111, std.math.maxInt(i111)),

        @as(f32, std.math.floatMin(f32)),
        @as(f32, 0),
        @as(f32, 180820.128),
        @as(f32, std.math.floatMax(f32)),

        @as(f64, std.math.floatMin(f64)),
        @as(f64, 0),
        @as(f64, 180820.128),
        @as(f64, std.math.floatMax(f64)),

        @as(f80, std.math.floatMin(f80)),
        @as(f80, 0),
        @as(f80, 180820.128),
        @as(f80, std.math.floatMax(f80)),

        @as(f128, std.math.floatMin(f128)),
        @as(f128, 0),
        @as(f128, 1820172.1281276182),
        @as(f128, std.math.floatMax(f128)),

        @as(bool, false),
        @as(bool, true),
    };

    var buffer = [_]u8{0} ** 100;
    var writer: Io.Writer = .fixed(&buffer);
    var reader: Io.Reader = .fixed(&buffer);

    inline for (values) |v| {
        const T = @TypeOf(v);
        // std.debug.print("{any} ({s})\n", .{v, @typeName(T)});
        try serialize(T, &v, &writer);
        // std.debug.print("writer: {any} (end: {d})\n", .{writer.buffered(), writer.end});
        var out: T = undefined;
        try deserialize(T, &out, &reader, std.testing.failing_allocator);
        // std.debug.print("{any: >10} => {any: >3} => {any: >10}\n", .{v, buffer[0..@sizeOf(T)], out});
        try expectEqual(v, out);
        _ = writer.consumeAll();
        reader.seek = 0;
    }
}

// }}}

// optionals {{{

test "(fuzzer) serialize and deserialize optionals" {
    const fuzzer = Fuzzer(.{
        ?u1, ?i1,
        ?u8, ?i8,
        ?u12, ?i12,
        ?u16, ?i16,
        ?u32, ?i32,
        ?u33, ?i33,
        ?u61, ?i61,
        ?u111, ?i111,
        ?u322, ?i322,
        ?f16,
        ?f32,
        ?f64,
        ?f128,
        ?bool,
    });
    try std.testing.fuzz({}, fuzzer.one, .{});
}

test "seralize and deseralize optionals" {
    const values = .{
        @as(?u1, null),
        @as(?u8, null),
        @as(?i10, null),
        @as(?i33, null),
        @as(?i111, null),
        @as(?f32, null),
        @as(?f64, null),
        @as(?f128, null),
        @as(?bool, null),
    };

    var buffer = [_]u8{0} ** 100;
    var writer: Io.Writer = .fixed(&buffer);
    var reader: Io.Reader = .fixed(&buffer);

    inline for (values) |v| {
        const T = @TypeOf(v);
        try serialize(T, &v, &writer);
        // std.debug.print("writer: {any} (end: {d})\n", .{writer.buffered(), writer.end});
        var out: T = undefined;
        try deserialize(T, &out, &reader, std.testing.failing_allocator);
        // std.debug.print("{any: >10} => {any: >3} => {any: >10}\n", .{v, buffer[0..@sizeOf(T)], out});
        try expectEqual(v, out);
        _ = writer.consumeAll();
        reader.seek = 0;
    }
}

// }}}

// pointers {{{

// one {{{

test "seralize and deseralize pointers" {
    const values = .{
        @as(?u1, null),
        @as(?u8, null),
        @as(?i10, null),
        @as(?i33, null),
        @as(?i111, null),
        @as(?f32, null),
        @as(?f64, null),
        @as(?f128, null),
        @as(?bool, null),
    };

    var buffer = [_]u8{0} ** 100;
    var writer: Io.Writer = .fixed(&buffer);
    var reader: Io.Reader = .fixed(&buffer);

    inline for (values) |v| {
        const T = @TypeOf(v);
        try serialize(T, &v, &writer);
        // std.debug.print("writer: {any} (end: {d})\n", .{writer.buffered(), writer.end});
        var out: T = undefined;
        try deserialize(T, &out, &reader, std.testing.failing_allocator);
        // std.debug.print("{any: >10} => {any: >3} => {any: >10}\n", .{v, buffer[0..@sizeOf(T)], out});
        try expectEqual(v, out);
        _ = writer.consumeAll();
        reader.seek = 0;
    }
}

// }}}

// slice {{{

test "(fuzzer) serialize and deserialize slice pointers" {
    const fuzzer = struct {
        pub fn one(_: void, smith: *Smith) anyerror!void {
            var buffer: [1000]u8 = undefined;
            var writer: Io.Writer = .fixed(&buffer);
            var reader: Io.Reader = .fixed(&buffer);

            while (!smith.eos()) {
                var slice_buffer: [1000]u8 = undefined;
                const len = smith.slice(&slice_buffer);
                try serialize([]const u8, &slice_buffer[0..len], &writer);
                var out: []const u8 = undefined;
                try deserialize([]const u8, &out, &reader, std.testing.allocator);
                defer free(out, std.testing.allocator);

                try expectEqualDeep(slice_buffer[0..len], out);
                _ = writer.consumeAll();
                reader.seek = 0;
            }
        }
    };
    try std.testing.fuzz({}, fuzzer.one, .{});
}

// }}}

// }}}

// (packed) structs {{{

const test_structs = struct {
    const Primitives1 = struct {
        int: u8,
        float: f32,
        boolean: bool,
    };
    
    const Primitives2 = struct {
        int: i33,
        float: f80,
        boolean: bool,
    };

    const Optionals1 = struct {
        int: ?i128,
        float: ?f128,
        boolean: ?bool,
    };

    const Packed1 = packed struct(u32) {
        hh: u16,
        lh: u16,
    };

    const Packed2 = packed struct {

    };
};

// test "(fuzzer) serialize and deserialize (packed) structs" {
//     const fuzzer = Fuzzer(.{
//         test_structs.Primitives1,
//     });
//     try std.testing.fuzz({}, fuzzer.one, .{});
// }

test "seralize and deseralize (packed) structs" {
    const values = .{
        test_structs.Primitives1{.int = 10, .float = 12127.127, .boolean = false},
        test_structs.Primitives1{.int = 255, .float = 126891.126816, .boolean = true},
        test_structs.Primitives2{.int = 0b10101110, .float = 948923.2367, .boolean = false},
        test_structs.Primitives2{.int = 0xaf1286d, .float = 1268.126, .boolean = true},
        test_structs.Optionals1{.int = null, .float = null, .boolean = null},
        test_structs.Optionals1{.int = 182, .float = null, .boolean = true},
        test_structs.Optionals1{.int = 16829, .float = 1682658.28330, .boolean = false},
        test_structs.Optionals1{.int = null, .float = 618626.6182, .boolean = null},
    };

    var buffer = [_]u8{0} ** 100;
    var writer: Io.Writer = .fixed(&buffer);
    var reader: Io.Reader = .fixed(&buffer);

    inline for (values) |v| {
        const T = @TypeOf(v);
        try serialize(T, &v, &writer);
        // std.debug.print("writer: {any} (end: {d})\n", .{writer.buffered(), writer.end});
        var out: T = undefined;
        try deserialize(T, &out, &reader, std.testing.failing_allocator);
        // std.debug.print("{any: >10} => {any: >3} => {any: >10}\n", .{v, buffer[0..@sizeOf(T)], out});
        try expectEqual(v, out);
        _ = writer.consumeAll();
        reader.seek = 0;
    }
}

// }}}

// enums and unions {{{

const test_enums_and_unions = struct {
    const SimpleEnum = enum(u8) {
        apple,
        banana,
        cherry = 255,
    };

    const StatusEnum = enum(u16) {
        ok = 200,
        not_found = 404,
        server_error = 500,
    };

    const TaggedUnion = union(enum) {
        integer: i64,
        float: f32,
        boolean: bool,
        empty: void,
    };

    const PackedStructLikeUnion = packed struct(u8) {
        tag: u2,
        value: u6,
    };
};

test "(fuzzer) serialize and deserialize enums and unions" {
    const fuzzer = Fuzzer(.{
        test_enums_and_unions.SimpleEnum,
        test_enums_and_unions.StatusEnum,
        test_enums_and_unions.TaggedUnion,
        test_enums_and_unions.PackedStructLikeUnion,
    });
    try std.testing.fuzz({}, fuzzer.one, .{});
}

test "serialize and deserialize enums and unions" {
    const values = .{
        @as(test_enums_and_unions.SimpleEnum, .apple),
        @as(test_enums_and_unions.SimpleEnum, .cherry),
        
        @as(test_enums_and_unions.StatusEnum, .ok),
        @as(test_enums_and_unions.StatusEnum, .server_error),

        test_enums_and_unions.TaggedUnion{ .integer = -1827364 },
        test_enums_and_unions.TaggedUnion{ .float = 3.14159 },
        test_enums_and_unions.TaggedUnion{ .boolean = true },
        test_enums_and_unions.TaggedUnion{ .empty = {} },

        test_enums_and_unions.PackedStructLikeUnion{ .tag = 3, .value = 63 },
        test_enums_and_unions.PackedStructLikeUnion{ .tag = 0, .value = 0 },
    };

    var buffer = [_]u8{0} ** 256;
    var writer: Io.Writer = .fixed(&buffer);
    var reader: Io.Reader = .fixed(&buffer);

    inline for (values) |v| {
        const T = @TypeOf(v);
        try serialize(T, &v, &writer);
        
        var out: T = undefined;
        try deserialize(T, &out, &reader, std.testing.failing_allocator);
        
        try std.testing.expectEqualDeep(v, out);
        
        _ = writer.consumeAll();
        reader.seek = 0;
    }
}

// }}}

// structs with pointers {{{

const test_complex_ptrs = struct {
    const Metadata = struct {
        timestamp: u64,
        is_active: bool,
    };

    const Node = struct {
        id: u32,
        labels: []const u8,
        payload_ptr: *const test_enums_and_unions.TaggedUnion,
    };

    const GraphContainer = struct {
        nodes: []const Node,
        meta: *const Metadata,
        flags: []const *const test_enums_and_unions.StatusEnum,
    };
};

test "serialize and deserialize structs with pointers" {
    const meta_data = test_complex_ptrs.Metadata{ .timestamp = 1682017281, .is_active = true };
    const union_val_1 = test_enums_and_unions.TaggedUnion{ .float = 2.718 };
    const union_val_2 = test_enums_and_unions.TaggedUnion{ .integer = 42 };
    
    const status_1 = test_enums_and_unions.StatusEnum.ok;
    const status_2 = test_enums_and_unions.StatusEnum.not_found;
    const flags_array = [_]*const test_enums_and_unions.StatusEnum{ &status_1, &status_2 };

    const nodes_array = [_]test_complex_ptrs.Node{
        .{
            .id = 1,
            .labels = "root_node",
            .payload_ptr = &union_val_1,
        },
        .{
            .id = 2,
            .labels = "child_node",
            .payload_ptr = &union_val_2,
        },
    };

    const values = .{
        test_complex_ptrs.GraphContainer{
            .nodes = &nodes_array,
            .meta = &meta_data,
            .flags = &flags_array,
        },
        test_complex_ptrs.GraphContainer{
            .nodes = &[_]test_complex_ptrs.Node{},
            .meta = &meta_data,
            .flags = &[_]*const test_enums_and_unions.StatusEnum{},
        },
    };

    var buffer = [_]u8{0} ** 2048;
    var writer: Io.Writer = .fixed(&buffer);
    var reader: Io.Reader = .fixed(&buffer);

    inline for (values) |v| {
        const T = @TypeOf(v);
        try serialize(T, &v, &writer);
        
        var out: T = undefined;
        try deserialize(T, &out, &reader, std.testing.allocator);
        defer free(out, std.testing.allocator);

        try std.testing.expectEqualDeep(v, out);
        
        _ = writer.consumeAll();
        reader.seek = 0;
    }
}

// }}}

// FIXME: error union {{{

// test "seralize and deseralize error union" {
//     const TestError = error{
//         SomeError,
//         SomeOtherError,
//         AnotherError,
//     };
//     const values = .{
//         @as(TestError!u1, error.SomeError),
//         @as(TestError!u8, error.SomeOtherError),
//         // @as(TestError!i10, error.AnotherError),
//         @as(TestError!i10, -326),
//         // @as(TestError!i33, error.SomeError),
//         @as(TestError!i33, 12861),
//         // @as(TestError!i111, error.SomeOtherError),
//         // @as(TestError!f32, error.AnotherError),
//         // @as(TestError!f64, error.SomeError),
//         @as(TestError!f64, 128671.126),
//         // @as(TestError!f128, error.SomeOtherError),
//         @as(TestError!f128, 167280.1280),
//         // @as(TestError!bool, error.AnotherError),
//         @as(TestError!bool, true),
//     };
//
//     var buffer = [_]u8{0} ** 100;
//     var writer: Io.Writer = .fixed(&buffer);
//     var reader: Io.Reader = .fixed(&buffer);
//
//     inline for (values) |v| {
//         std.debug.print("type: {s}\n", .{@typeName(@TypeOf(v))});
//         const T = @TypeOf(v);
//         try serialize(T, &v, &writer);
//         std.debug.print("writer: {any} (end: {d})\n", .{writer.buffered(), writer.end});
//         var out: T = undefined;
//         try deserialize(T, &out, &reader, std.testing.failing_allocator);
//         std.debug.print("{any} => {any} => {any}\n", .{v, buffer[0..@sizeOf(T)], out});
//         try expectEqual(v, out);
//         _ = writer.consumeAll();
//         reader.seek = 0;
//     }
// }

// }}}

// }}}

test {
    std.testing.refAllDecls(@This());
}
