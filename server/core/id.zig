const std = @import("std");
const math = std.math;

const Smith = std.testing.Smith;
const Weight = Smith.Weight;
const expectEqualDeep = std.testing.expectEqualDeep;
const expectEqual = std.testing.expectEqual;
const assert = std.debug.assert;

pub fn ID(comptime Tag: type, comptime Int: type) type {
    comptime var tbits = 0;
    // validate types {{{
    comptime {
        switch (@typeInfo(Tag)) {
            .int => |info| {
                assert(@mod(info.bits, 6) == 0);
                tbits = info.bits;
            },
            .@"enum" => |info| {
                assert(@mod(@typeInfo(info.tag_type).int.bits, 6) == 0);
                assert(@typeInfo(info.tag_type).int.signedness == .unsigned);
                tbits = @typeInfo(info.tag_type).int.bits;
            },
            .@"union" => |info| {
                assert(info.layout == .@"packed");
                assert(@mod(@typeInfo(info.tag_type.?).int.bits, 6) == 0);
                assert(@typeInfo(info.tag_type.?).int.signedness == .unsigned);
                tbits = @typeInfo(info.tag_type).int.bits;
            },
            .@"struct" => |info| {
                assert(info.layout == .@"packed");
                assert(@mod(@typeInfo(info.backing_integer.?).int.bits, 6) == 0);
                assert(@typeInfo(info.backing_integer.?).int.signedness == .unsigned);
                tbits = @typeInfo(info.backing_integer.?).int.bits;
            },
            .void => {},
            else => unreachable,
        }

        assert(@typeInfo(Int).int.signedness == .unsigned);
    }
    // }}}
    return packed struct(BackingInt) {
        tag: Tag,
        v: Int,

        pub const tag_bits = tbits;
        pub const int_bits = @typeInfo(Int).int.bits;
        pub const bits = int_bits + tag_bits;
        pub const TagInt = if (tag_bits == 0) void else @Int(.unsigned, tag_bits);
        pub const VInt = Int;
        pub const BackingInt = @Int(.unsigned, bits);

        pub const char_count = @divExact(bits, 6);
        pub const tag_char_count = @divExact(tag_bits, 6);
        pub const int_char_count = @divExact(int_bits, 6);
        pub const char_set = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";

        const Self = @This();

        // extract int {{{

        pub fn extractInt(int: BackingInt) Int {
            return @truncate(int);
        }

        test extractInt {
            const fuzzer = struct {
                fn one(_: void, smith: *Smith) anyerror!void {
                    const T = ID(u6, u12);
                    const tag = smith.value(T.TagInt);
                    const v = smith.value(T.VInt);
                    try expectEqual(v, T.extractInt((T{.tag = tag, .v = v}).asBackingInt()));
                }
            };
            try std.testing.fuzz({}, fuzzer.one, .{});

            const TestID = ID(u6, u12);
            try expectEqual(0b000000_000000, TestID.extractInt(0b111111_000000_000000));
            try expectEqual(0b000000_010100, TestID.extractInt(0b111111_000000_010100));
            try expectEqual(0b111111_111111, TestID.extractInt(0b111111_111111_111111));
        }

        // }}}

        // extract tag {{{

        pub fn extractTag(int: BackingInt) Tag {
            if (comptime tag_bits == 0) return;
            const tag: TagInt = @intCast(int >> int_bits);
            return intAsTag(tag);
        }

        test extractTag {
            const fuzzer = struct {
                fn one(_: void, smith: *Smith) anyerror!void {
                    const T = ID(u6, u12);
                    const tag = smith.value(T.TagInt);
                    const v = smith.value(T.VInt);
                    try expectEqual(tag, T.extractTag((T{.tag = tag, .v = v}).asBackingInt()));
                }
            };
            try std.testing.fuzz({}, fuzzer.one, .{});

            const TestID = ID(u6, u12);
            try expectEqual(0b000000, TestID.extractTag(0b000000_000000_000000));
            try expectEqual(0b100001, TestID.extractTag(0b100001_000000_000000));
            try expectEqual(0b111111, TestID.extractTag(0b111111_111111_111111));
        }
        
        // }}}
        
        // from/to backing int {{{

        pub fn fromBackingInt(int: BackingInt) Self {
            return .{
                .tag = extractTag(int),
                .v = extractInt(int),
            };
        }

        pub fn asBackingInt(self: Self) BackingInt {
            if (comptime tag_bits != 0) {
                var out: BackingInt = @intCast(tagAsInt(self.tag));
                out <<= int_bits;
                out += @intCast(self.v);
                return out;
            } else {
                return self.v;
            }
        }

        // }}}

        // tag to int (and vice versa) {{{

        pub fn tagAsInt(tag: Tag) TagInt {
            return switch (@typeInfo(Tag)) {
                .int => |info| switch (info.signedness) {
                    .signed => @bitCast(tag),
                    .unsigned => tag,
                },
                .void => {},
                else => @intFromEnum(tag),
            };
        }

        pub fn intAsTag(int: TagInt) Tag {
            return switch (@typeInfo(Tag)) {
                .int => |info| switch (info.signedness) {
                    .signed => @bitCast(int),
                    .unsigned => int,
                },
                .void => {},
                else => @enumFromInt(int),
            };
        }

        pub fn tagAsChars(tag: Tag) [tag_char_count]u8 {
            var chars = [_]u8{0} ** tag_char_count;

            const tag_int: BackingInt = @intCast(tagAsInt(tag));

            for (0..tag_char_count) |i| {
                chars[tag_char_count - 1 - i] = numAsChar(@truncate(tag_int >> @truncate(i*6)));
            }

            return chars;
        }

        test tagAsChars {
            const TestID = ID(u12, u6);
            try expectEqual("aa".*, TestID.tagAsChars(0));
            try expectEqual("aA".*, TestID.tagAsChars(26));
            try expectEqual("--".*, TestID.tagAsChars(math.maxInt(u12)));
        }

        // }}}

        // encode/decode {{{

        // decode {{{

        pub fn decode(str: *const [char_count]u8) error{InvalidCharacter}!Self {
            var v: BackingInt = 0;

            for (str) |char| {
                if (decodeChar(char)) |num| {
                    v <<= 6;
                    v += num;
                } else {
                    return error.InvalidCharacter;
                }
            }

            return .{ .tag = extractTag(v), .v = extractInt(v) };
        }

        pub fn validChar(char: u8) bool {
            switch (char) {
                'a' ... 'z', 
                'A' ... 'Z',
                '0' ... '9',
                '_', '-' => return true,
                else => return false,
            }
        }

        pub fn decodeChar(char: u8) ?Int {
            switch (char) {
                'a' ... 'z' => return @intCast(char - 'a'),         //  0 .. 25
                'A' ... 'Z' => return @intCast(char - 'A' + 26),    // 26 .. 51
                '0' ... '9' => return @intCast(char - '0' + 52),    // 52 .. 61
                '_' => return 62,
                '-' => return 63,
                else => return null,
            }
        }

        // }}}

        // encode {{{

        pub fn encode(self: Self) [char_count]u8 {
            return backingIntAsChars(self.asBackingInt());
        }

        pub fn backingIntAsChars(int: BackingInt) [char_count]u8 {
            var id_str = [_]u8{0} ** char_count;

            inline for (&id_str, 0..) |*c, i| {
                const num = (int >> (bits - ((i+1)*6))) & ~(((@as(BackingInt, 1) << (i*6)) - 1) << 6);
                c.* = numAsChar(@truncate(num));
            }

            return id_str;
        }

        pub fn numAsChar(num: u6) u8 {
            switch (num) {
                 0 ... 25 => return @as(u8, @intCast(num)) + 'a',
                26 ... 51 => return @as(u8, @intCast(num)) + 'A' - 26,
                52 ... 61 => return @as(u8, @intCast(num)) + '0' - 52,
                62 => return '_',
                63 => return '-',
            }
        }

        pub fn backingAsChar(int: BackingInt) ?u8 {
            if (int > 63) return null;
            return numAsChar(@truncate(int));
        }

        // }}}

        test "to int and back" {
            const fuzzer = struct {
                fn one(_: void, smith: *Smith) anyerror!void {
                    var id: [char_count]u8 = undefined;
                    smith.bytesWeighted(&id, &.{
                        Weight.rangeAtMost(u8, 'a', 'z', 26),
                        Weight.rangeAtMost(u8, 'A', 'Z', 26),
                        Weight.rangeAtMost(u8, '0', '9', 10),
                        Weight.value(u8, '_', 1),
                        Weight.value(u8, '-', 1),
                    });
                    try expectEqualDeep(id, encode(try decode(&id)));
                }
            };
            try std.testing.fuzz({}, fuzzer.one, .{});
        }

        // }}}

        // format {{{

        pub fn formatNumber(
            self: @This(),
            writer: *std.Io.Writer,
            opts: std.fmt.Number,
        ) std.Io.Writer.Error!void {
            try writer.printInt(self.v, opts.mode.base().?, opts.case, .{ 
                .alignment = opts.alignment,
                .precision = opts.precision,
                .width = opts.width,
                .fill = opts.fill,
            });
        }

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.writeAll(&self.encode());
        }

        // }}}
    };
}

test {
    std.testing.refAllDecls(@This());
}


