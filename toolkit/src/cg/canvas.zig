//! 픽셀 판 하나(CG 층, TK design 결정 3). 판은 바깥 메모리(wl_shm의 mmap, 임시 판, 호스트 검사의 배열)이고 ARGB8888(리틀 엔디언
//! u32 하나)이다. 경로 채우기는 z2d, 사각형 채우기와 글자 섞기는 여기서 직접 한다. 좌표는 이 판의 픽셀이고 clip을 모른다 — clip과
//! 평행 이동은 `Painter`(painter.zig)의 일이다.
//!
//! z2d의 `Surface.initBuffer`는 부를 때마다 판 전체를 지운다(design 확인 3). 버퍼에는 지난 그림이 남아 있어야 하므로(버퍼 나이)
//! 버퍼는 `wrap`으로 감싼다 — z2d `ImageSurface`의 공개 필드(width · height · buf)를 그대로 채우는 것이고 지우지 않는다. 그래서 창 층이
//! 판을 미리 감싸 들고 있을 까닭이 없다(TK-M0은 버퍼마다 한 번 감쌌다). 임시 판은 `initClear`(z2d `initBuffer`, 투명 0으로 지움).

const std = @import("std");
const z2d = @import("z2d");
const text = @import("text.zig");

pub const Canvas = struct {
    pixels: []u32,
    width: u32,
    height: u32,
    surface: z2d.Surface,

    /// 판 `pixels`(폭 × 높이, stride = 폭 × 4)를 지우지 않고 감싼다.
    pub fn wrap(pixels: []u32, width: u32, height: u32) Canvas {
        const px: []z2d.pixel.ARGB = @ptrCast(pixels[0 .. @as(usize, width) * height]);
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .surface = .{ .image_surface_argb = .{ .width = @intCast(width), .height = @intCast(height), .buf = px } },
        };
    }

    /// 판을 0(투명 검정)으로 지우고 감싼다(z2d `initBuffer`).
    pub fn initClear(pixels: []u32, width: u32, height: u32) Canvas {
        const px: []z2d.pixel.ARGB = @ptrCast(pixels[0 .. @as(usize, width) * height]);
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .surface = z2d.Surface.initBuffer(.image_surface_argb, null, px, @intCast(width), @intCast(height)),
        };
    }

    /// 판 전체를 한 색(0xRRGGBB, 불투명)으로.
    pub fn fill(self: *Canvas, color: u32) void {
        @memset(self.pixels[0 .. @as(usize, self.width) * self.height], 0xFF000000 | color);
    }

    /// 판 안의 사각형 (x, y, w, h)를 채운다(빠른 길 — TK-M1 plan 확정 1). 판 밖으로 나가지 않게 부르는 쪽이 자른다. `alpha` 255면
    /// 행마다 memset, 아니면 불투명 바탕 위에 섞는다.
    pub fn fillRect(self: *Canvas, x: u32, y: u32, w: u32, h: u32, color: u32, alpha: u8) void {
        var row = y;
        while (row < y + h) : (row += 1) {
            const off = @as(usize, row) * self.width + x;
            const line = self.pixels[off .. off + w];
            if (alpha == 255) {
                @memset(line, 0xFF000000 | color);
            } else {
                for (line) |*p| p.* = mix(p.*, color, alpha);
            }
        }
    }

    /// 둥근 사각형 하나를 z2d로 채운다(안티에일리어스 기본). 자리 · 크기 · 반지름은 사용자 좌표이고 `(dx, dy)`를 더한 것이 이 판의
    /// 픽셀이다(z2d의 변환 행렬 — 정수 이동이면 AA 픽셀이 이동 전과 같다). 판 밖은 z2d가 자른다. 반지름이 0이면 네 변의 사각형.
    pub fn roundedRect(
        self: *Canvas,
        io: std.Io,
        alloc: std.mem.Allocator,
        dx: f64,
        dy: f64,
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        r: f64,
        color: u32,
        alpha: u8,
    ) !void {
        var ctx = z2d.Context.init(io, alloc, &self.surface);
        defer ctx.deinit();
        const cr: u8 = @truncate(color >> 16);
        const cg: u8 = @truncate(color >> 8);
        const cb: u8 = @truncate(color);
        if (alpha == 255) {
            ctx.setSourceToPixel(.{ .rgb = .{ .r = cr, .g = cg, .b = cb } });
        } else {
            // z2d의 ARGB는 premultiplied다(design 확인 3).
            const a: u32 = alpha;
            ctx.setSourceToPixel(.{ .argb = .{
                .a = alpha,
                .r = @intCast((@as(u32, cr) * a + 127) / 255),
                .g = @intCast((@as(u32, cg) * a + 127) / 255),
                .b = @intCast((@as(u32, cb) * a + 127) / 255),
            } });
        }
        ctx.translate(dx, dy);
        const pi = std.math.pi;
        const rr = @max(0, @min(r, @min(w, h) / 2.0));
        if (rr == 0) {
            try ctx.moveTo(x, y);
            try ctx.lineTo(x + w, y);
            try ctx.lineTo(x + w, y + h);
            try ctx.lineTo(x, y + h);
            try ctx.closePath();
            try ctx.fill();
            return;
        }
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

    /// 글자 비트맵 하나를 판의 (x0, y0)에 섞는다. 판 좌표의 사각형 `clip` 밖은 건너뛴다. 섞는 양은 coverage를 `lut`(감마)로 고친
    /// 값에 `alpha`를 곱한 것이다. 바탕은 불투명이라 결과의 알파는 늘 FF다.
    pub fn blendGlyph(self: *Canvas, g: text.Glyph, x0: i32, y0: i32, color: u32, lut: *const [256]u8, alpha: u8, cx0: i32, cy0: i32, cx1: i32, cy1: i32) void {
        var gy: u32 = 0;
        while (gy < g.height) : (gy += 1) {
            const y = y0 + @as(i32, @intCast(gy));
            if (y < cy0 or y >= cy1) continue;
            var gx: u32 = 0;
            while (gx < g.width) : (gx += 1) {
                const x = x0 + @as(i32, @intCast(gx));
                if (x < cx0 or x >= cx1) continue;
                var a: u32 = lut[g.pixels[gy * g.width + gx]];
                if (alpha != 255) a = (a * alpha + 127) / 255;
                if (a == 0) continue;
                const i = @as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x));
                if (a == 255) {
                    self.pixels[i] = 0xFF000000 | color;
                    continue;
                }
                self.pixels[i] = mix(self.pixels[i], color, @intCast(a));
            }
        }
    }

    /// premultiplied ARGB 판 `src`(폭 `sw`)의 사각형 (0, 0, w, h)를 이 판의 (x, y)에 src-over로 얹는다(바탕은 불투명). painter의 겹친
    /// clip 길이 쓴다.
    pub fn compositeOver(self: *Canvas, src: []const u32, sw: u32, x: u32, y: u32, w: u32, h: u32) void {
        var row: u32 = 0;
        while (row < h) : (row += 1) {
            const so = @as(usize, row) * sw;
            const doff = @as(usize, y + row) * self.width + x;
            for (src[so .. so + w], self.pixels[doff .. doff + w]) |s, *d| {
                const sa = s >> 24;
                if (sa == 0) continue;
                if (sa == 255) {
                    d.* = s;
                    continue;
                }
                const inv = 255 - sa;
                const r: u32 = @min(255, ((s >> 16) & 0xFF) + (((d.* >> 16) & 0xFF) * inv + 127) / 255);
                const gg: u32 = @min(255, ((s >> 8) & 0xFF) + (((d.* >> 8) & 0xFF) * inv + 127) / 255);
                const b: u32 = @min(255, (s & 0xFF) + ((d.* & 0xFF) * inv + 127) / 255);
                d.* = 0xFF000000 | (r << 16) | (gg << 8) | b;
            }
        }
    }
};

/// 불투명 바탕 `d` 위에 색 `color`(0xRRGGBB)를 양 `a`로 섞는다.
fn mix(d: u32, color: u32, a: u8) u32 {
    const aa: u32 = a;
    const inv = 255 - aa;
    const r = (((color >> 16) & 0xFF) * aa + ((d >> 16) & 0xFF) * inv + 127) / 255;
    const g = (((color >> 8) & 0xFF) * aa + ((d >> 8) & 0xFF) * inv + 127) / 255;
    const b = ((color & 0xFF) * aa + (d & 0xFF) * inv + 127) / 255;
    return 0xFF000000 | (r << 16) | (g << 8) | b;
}
