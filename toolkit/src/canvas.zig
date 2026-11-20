//! 픽셀 판 하나에 그리는 것(CG 층, TK design 결정 3). 판은 바깥 메모리(wl_shm의 mmap, 또는 호스트 검사의 배열)이고 ARGB8888
//! (리틀 엔디언 u32 하나, 알파 FF — 창은 늘 불투명하다)다. 경로 채우기는 z2d, 글자 섞기는 여기서 직접 한다.
//!
//! z2d의 `Surface.initBuffer`는 부를 때마다 판 전체를 지운다(design 확인 3) — 그래서 `Canvas`를 판마다 한 번 만들어 들고 있는다.
//! z2d에는 clip이 없다(결정 4). TK-M0은 통째 그리기라 아직 필요 없다.

const std = @import("std");
const z2d = @import("z2d");
const text = @import("text.zig");

pub const Canvas = struct {
    pixels: []u32,
    width: u32,
    height: u32,
    surface: z2d.Surface,

    /// 판 `pixels`(폭 × 높이, stride = 폭 × 4)를 감싼다. z2d가 이 자리에서 판을 0(투명 검정)으로 지운다.
    pub fn init(pixels: []u32, width: u32, height: u32) Canvas {
        const px: []z2d.pixel.ARGB = @ptrCast(pixels);
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .surface = z2d.Surface.initBuffer(.image_surface_argb, null, px, @intCast(width), @intCast(height)),
        };
    }

    /// 판 전체를 한 색(0xRRGGBB)으로.
    pub fn fill(self: *Canvas, color: u32) void {
        @memset(self.pixels, 0xFF000000 | color);
    }

    /// 둥근 사각형 하나를 채운다(z2d, 안티에일리어스 기본). 자리 · 크기 · 반지름은 이 판의 픽셀이다.
    pub fn roundedRect(self: *Canvas, io: std.Io, alloc: std.mem.Allocator, x: f64, y: f64, w: f64, h: f64, r: f64, color: u32) !void {
        var ctx = z2d.Context.init(io, alloc, &self.surface);
        defer ctx.deinit();
        ctx.setSourceToPixel(.{ .rgb = .{
            .r = @truncate(color >> 16),
            .g = @truncate(color >> 8),
            .b = @truncate(color),
        } });
        const pi = std.math.pi;
        const rr = @min(r, @min(w, h) / 2.0);
        try ctx.moveTo(x + rr, y);
        try ctx.lineTo(x + w - rr, y);
        try ctx.arc(x + w - rr, y + rr, rr, -pi / 2.0, 0);
        try ctx.lineTo(x + w, y + h - rr);
        try ctx.arc(x + w - rr, y + h - rr, rr, 0, pi / 2.0);
        try ctx.lineTo(x + rr, y + h);
        try ctx.arc(x + rr, y + h - rr, rr, pi / 2.0, pi);
        try ctx.lineTo(x, y + rr);
        try ctx.arc(x + rr, y + rr, rr, pi, 3.0 * pi / 2.0);
        try ctx.closePath();
        try ctx.fill();
    }

    /// UTF-8 한 줄을 baseline `baseline`, 펜 시작 `x`(소수)에서 그린다. 색은 0xRRGGBB, 섞는 양은 coverage를 `lut`(감마)로 고친
    /// 값이다. 돌려주는 것은 끝난 펜 x. 판 밖은 자른다.
    pub fn drawText(self: *Canvas, face: *text.Face, x: f32, baseline: i32, str: []const u8, color: u32, lut: *const [256]u8) !f32 {
        var pen = x;
        var prev: ?u32 = null;
        var it = text.Utf8.init(str);
        while (it.next()) |cp| {
            if (prev) |p| pen += face.kern(p, cp);
            const at = text.splitPen(pen);
            const g = try face.get(cp, at.sub);
            self.blend(g, at.ix + g.x_offset, baseline + g.y_offset, color, lut);
            pen += face.advance(cp);
            prev = cp;
        }
        return pen;
    }

    /// 글자 비트맵 하나를 (x0, y0)에 섞는다. 바탕은 불투명이라 결과의 알파는 늘 FF다.
    fn blend(self: *Canvas, g: text.Glyph, x0: i32, y0: i32, color: u32, lut: *const [256]u8) void {
        const sr: u32 = (color >> 16) & 0xFF;
        const sg: u32 = (color >> 8) & 0xFF;
        const sb: u32 = color & 0xFF;
        var gy: u32 = 0;
        while (gy < g.height) : (gy += 1) {
            const y = y0 + @as(i32, @intCast(gy));
            if (y < 0 or y >= @as(i32, @intCast(self.height))) continue;
            var gx: u32 = 0;
            while (gx < g.width) : (gx += 1) {
                const x = x0 + @as(i32, @intCast(gx));
                if (x < 0 or x >= @as(i32, @intCast(self.width))) continue;
                const a: u32 = lut[g.pixels[gy * g.width + gx]];
                if (a == 0) continue;
                const i = @as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x));
                if (a == 255) {
                    self.pixels[i] = 0xFF000000 | color;
                    continue;
                }
                const d = self.pixels[i];
                const inv = 255 - a;
                const r = (sr * a + ((d >> 16) & 0xFF) * inv + 127) / 255;
                const gg = (sg * a + ((d >> 8) & 0xFF) * inv + 127) / 255;
                const b = (sb * a + (d & 0xFF) * inv + 127) / 255;
                self.pixels[i] = 0xFF000000 | (r << 16) | (gg << 8) | b;
            }
        }
    }
};
