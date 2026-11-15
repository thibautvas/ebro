pub const Rect = struct { x: i32, y: i32, w: i32, h: i32 };

pub fn bsp(area: Rect, out: []Rect) void {
    const mfact: f32 = 0.5;
    var rest = area;

    for (out, 0..) |*r, i| {
        if (i == out.len - 1) {
            r.* = rest;
            break;
        }

        if (i % 2 == 0) {
            const w: i32 = @intFromFloat(@as(f32, @floatFromInt(rest.w)) * mfact);
            r.* = .{ .x = rest.x, .y = rest.y, .w = w, .h = rest.h };
            rest.x += w;
            rest.w -= w;
        } else {
            const h: i32 = @intFromFloat(@as(f32, @floatFromInt(rest.h)) * mfact);
            r.* = .{ .x = rest.x, .y = rest.y, .w = rest.w, .h = h };
            rest.y += h;
            rest.h -= h;
        }
    }
}
