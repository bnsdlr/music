const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

// conversion {{{

// hsl to rgb {{{

/// src: https://www.rapidtables.com/convert/color/hsl-to-rgb.html
///
/// * `hue`         float from 0 to 360
/// * `saturation`  float from 0 to 1
/// * `lightness`   float from 0 to 1
pub fn hslToRgb(hue: f32, saturation: f32, lightness: f32) struct{u8, u8, u8} {
    assert(hue <= 360 and hue >= 0);
    assert(saturation <= 100 and saturation >= 0);
    assert(lightness <= 100 and lightness >= 0);
    const c = (1 - @abs(2 * lightness - 1)) * saturation;
    const x = c * (1 - @abs(@mod(hue / 60.0, 2) - 1));
    const m = lightness - c / 2;

    const r_prime, const g_prime, const b_prime = if (hue < 60)
            .{ c, x, 0 }
        else if (hue < 120)
            .{ x, c, 0 }
        else if (hue < 180)
            .{ 0, c, x }
        else if (hue < 240)
            .{ 0, x, c }
        else if (hue < 300)
            .{ x, 0, c }
        else
            .{ c, 0, x };

    return .{ 
        @intFromFloat(@round((r_prime + m) * 255)),
        @intFromFloat(@round((g_prime + m) * 255)),
        @intFromFloat(@round((b_prime + m) * 255)),
    };
}

test hslToRgb {
    try expectEqual(.{0,0,0}, hslToRgb(0,0,0));
    try expectEqual(.{255,255,255}, hslToRgb(0,0,1));
    try expectEqual(.{255,0,0}, hslToRgb(0,1.0,0.5));
    try expectEqual(.{0,255,0}, hslToRgb(120,1.0,0.5));
    try expectEqual(.{0,0,255}, hslToRgb(240,1.0,0.5));
    try expectEqual(.{255,255,0}, hslToRgb(60,1.0,0.5));
    try expectEqual(.{0,255,255}, hslToRgb(180,1.0,0.5));
    try expectEqual(.{255,0,255}, hslToRgb(300,1.0,0.5));
    try expectEqual(.{191,191,191}, hslToRgb(0,0.0,0.75));
    try expectEqual(.{128,128,128}, hslToRgb(0,0.0,0.5));
    try expectEqual(.{128,0,0}, hslToRgb(0,1.0,0.25));
    try expectEqual(.{128,128,0}, hslToRgb(60,1.0,0.25));
    try expectEqual(.{0,128,0}, hslToRgb(120,1.0,0.25));
    try expectEqual(.{128,0,128}, hslToRgb(300,1.0,0.25));
    try expectEqual(.{0,128,128}, hslToRgb(180,1.0,0.25));
    try expectEqual(.{0,0,128}, hslToRgb(240,1.0,0.25));
    try expectEqual(.{187,157,189}, hslToRgb(296,0.195,0.678));
}

// }}}

// }}}

test {
    std.testing.refAllDecls(@This());
}

