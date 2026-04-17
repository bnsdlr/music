const std = @import("std");
const math = std.math;

const Smith = std.testing.Smith;
const Weight = Smith.Weight;
const expectEqualDeep = std.testing.expectEqualDeep;

pub const YTID = struct {
    v: u66,

    const char_count = 11;
    const char_set = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";
    /// 64^11 - 1
    const posible_combinations: u66 = 73_786_976_294_838_206_463;

    const Self = @This();

    pub fn parse(str: *const [char_count]u8) error{InvalidCharacter}!Self {
        var v: u66 = 0;

        for (str) |char| {
            if (parseChar(char)) |num| {
                v <<= 6;
                v += num;
            } else {
                return error.InvalidCharacter;
            }
        }

        return .{ .v = v };
    }

    pub fn parseChar(char: u8) ?u66 {
        switch (char) {
            'a' ... 'z' => return @intCast(char - 'a'),         //  0 .. 25
            'A' ... 'Z' => return @intCast(char - 'A' + 26),    // 26 .. 51
            '0' ... '9' => return @intCast(char - '0' + 52),    // 52 .. 61
            '_' => return 62,
            '-' => return 63,
            else => return null,
        }
    }

    pub fn numAsChar(num: u66) ?u8 {
        switch (num) {
             0 ... 25 => return @as(u8, @intCast(num)) + 'a',
            26 ... 51 => return @as(u8, @intCast(num)) + 'A' - 26,
            52 ... 61 => return @as(u8, @intCast(num)) + '0' - 52,
            62 => return '_',
            63 => return '-',
            else => return null,
        }
    }

    pub fn asChars(self: Self) [char_count]u8 {
        var id_str = [_]u8{0} ** char_count;

        inline for (&id_str, 0..) |*c, i| {
            const num = (self.v >> (66 - ((i+1)*6))) & ~(((@as(u66, 1) << (i*6)) - 1) << 6);
            c.* = numAsChar(num).?;
        }

        return id_str;
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
                try expectEqualDeep(id, asChars(try parse(&id)));
            }
        };

        const id1 = "rientaoresn";
        try expectEqualDeep(id1.*, asChars(try parse(id1)));
        const id2 = "aorsntaorse";
        try expectEqualDeep(id2.*, asChars(try parse(id2)));
        const id3 = "RIENTAORESN";
        try expectEqualDeep(id3.*, asChars(try parse(id3)));
        const id4 = "AORSNTAORSE";
        try expectEqualDeep(id4.*, asChars(try parse(id4)));

        try std.testing.fuzz({}, fuzzer.one, .{});
    }

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
};


test {
    std.testing.refAllDecls(@This());
}

