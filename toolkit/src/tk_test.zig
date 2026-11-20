//! 툴킷의 호스트 검사(R-ARCH-4 — Wayland 없이, 판은 메모리 배열). `zig build test`가 빌드 호스트에서 돌린다. 글꼴을
//! `vendor/fonts/Pretendard-Regular.otf` 상대 경로로 읽으므로 toolkit/ 안에서 돌린다(게이트가 그렇게 한다).
//!
//! 표는 이 판(z2d v0.13.2 · stb_truetype v1.26 · Pretendard 1.3.9)의 실측이다. 판을 올리면 다시 잰다.

const std = @import("std");
const theme = @import("theme");
const Canvas = @import("canvas.zig").Canvas;
const text = @import("text.zig");

const W: u32 = 200;
const H: u32 = 120;

var failures: u32 = 0;

fn check(ok: bool, comptime name: []const u8, args: anytype) void {
    if (ok) {
        std.debug.print("tk_test: " ++ name ++ " OK\n", args);
    } else {
        std.debug.print("tk_test: FAIL " ++ name ++ "\n", args);
        failures += 1;
    }
}

fn px(c: *const Canvas, x: u32, y: u32) u32 {
    return c.pixels[y * c.width + x] & 0x00FFFFFF;
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.gpa;
    var pixels: [W * H]u32 = undefined;
    var c = Canvas.init(&pixels, W, H);

    // ── 둥근 사각형(20, 20, 160 × 80, r 12) ──────────────────────────
    c.fill(theme.TK_BG);
    try c.roundedRect(init.io, alloc, 20, 20, 160, 80, 12, theme.TK_ACCENT);
    check(px(&c, 100, 60) == theme.TK_ACCENT, "rect centre (100,60) is TK_ACCENT {x:0>6}", .{px(&c, 100, 60)});
    check(px(&c, 20, 20) == theme.TK_BG, "corner outside (20,20) is TK_BG {x:0>6}", .{px(&c, 20, 20)});
    check(px(&c, 19, 60) == theme.TK_BG and px(&c, 20, 60) == theme.TK_ACCENT, "left edge: x=19 bg, x=20 fill", .{});
    check(px(&c, 179, 60) == theme.TK_ACCENT and px(&c, 180, 60) == theme.TK_BG, "right edge: x=179 fill, x=180 bg", .{});
    check(px(&c, 100, 19) == theme.TK_BG and px(&c, 100, 20) == theme.TK_ACCENT, "top edge: y=19 bg, y=20 fill", .{});
    // 모서리 대각선(원의 중심 (32,32)에서 반지름 12 — 경계는 (23.5,23.5) 언저리). 그 칸은 바탕도 채움도 아닌 중간값이다(AA).
    var mid: u32 = 0;
    var d: u32 = 20;
    while (d < 32) : (d += 1) {
        const v = px(&c, d, d);
        if (v != theme.TK_BG and v != theme.TK_ACCENT) mid += 1;
    }
    check(mid >= 1, "corner diagonal has {d} antialiased pixel(s)", .{mid});
    check(px(&c, 32, 20) == theme.TK_ACCENT and px(&c, 20, 32) == theme.TK_ACCENT, "arc ends (32,20) (20,32) are filled", .{});

    // ── 글자 ────────────────────────────────────────────────────────
    const font = try std.Io.Dir.cwd().readFileAlloc(init.io, "vendor/fonts/Pretendard-Regular.otf", alloc, .unlimited);
    defer alloc.free(font);

    var f13 = try text.Face.init(alloc, font, 13);
    defer f13.deinit();
    var f14 = try text.Face.init(alloc, font, 14);
    defer f14.deinit();
    // Pretendard: upm 2048, ascent 1950, descent −494, gap 0 → 13 px에서 12.38 + 3.14 = 15.51(올림 16, design 확인 4).
    check(@ceil(f13.line_height) == 16, "13 px line height {d:.2} ceils to 16", .{f13.line_height});
    check(@ceil(f14.line_height) == 17, "14 px line height {d:.2} ceils to 17", .{f14.line_height});
    const a_han = f14.advance('한');
    const a_i = f14.advance('i');
    check(a_han > 10 and a_han < 15 and a_i > 2 and a_i < a_han / 2, "proportional: 14 px 한 {d:.3} vs i {d:.3}", .{ a_han, a_i });

    // 서브픽셀 칸: 같은 글자를 0 · 2칸으로 구우면 coverage가 다르다.
    const g0 = try f14.get('l', 0);
    const g2 = try f14.get('l', 2);
    check(!std.mem.eql(u8, g0.pixels, g2.pixels) or g0.width != g2.width, "subpixel 0 and 2/4 give different bitmaps for 'l'", .{});
    const sp = text.splitPen(10.9);
    check(sp.ix == 11 and sp.sub == 0, "splitPen(10.9) rounds to the next pixel ({d},{d})", .{ sp.ix, sp.sub });

    // 감마 1.0은 그대로다.
    const lut1 = text.gammaLut(1.0);
    var same = true;
    for (lut1, 0..) |v, i| same = same and v == i;
    check(same, "gamma 1.0 table is the identity", .{});
    // 기본 감마(1.8, 결정 4의 판정)는 끝점을 지키고 중간값을 밝힌다 — 어두운 바탕에서 획이 굵어진다.
    const lutd = text.gammaLut(text.GAMMA);
    check(lutd[0] == 0 and lutd[255] == 255 and lutd[128] > 128, "default gamma {d:.1}: 0 -> {d}, 128 -> {d}, 255 -> {d}", .{ text.GAMMA, lutd[0], lutd[128], lutd[255] });

    // "안녕"(14 px)을 (60, baseline 60)에 — 상자 안 잉크와 중간값.
    c.fill(theme.TK_BG);
    const end = try c.drawText(&f14, 60, 60, "안녕", theme.TK_TEXT, &lut1);
    var ink: u32 = 0;
    var full: u32 = 0;
    var y: u32 = 40;
    while (y < 66) : (y += 1) {
        var x: u32 = 58;
        while (x < 92) : (x += 1) {
            const v = px(&c, x, y);
            if (v != theme.TK_BG) ink += 1;
            if (v == theme.TK_TEXT) full += 1;
        }
    }
    check(ink > 0 and ink > full, "안녕 box: ink {d}, full {d}, antialiased {d}, pen end {d:.2}", .{ ink, full, ink - full, end });
    check(px(&c, 10, 10) == theme.TK_BG, "outside the text stays TK_BG", .{});

    if (failures != 0) {
        std.debug.print("tk_test: {d} failure(s)\n", .{failures});
        return 1;
    }
    std.debug.print("tk_test: all checks passed\n", .{});
    return 0;
}
