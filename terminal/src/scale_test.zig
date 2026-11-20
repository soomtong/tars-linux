const std = @import("std");
const scale = @import("scale.zig");

// 배율 고르기와 사각형 늘리기를 호스트에서 본다(HS-M0). `drm.zig`가 이 둘을 부르고, 화면에
// 닿는 것(물리 dumb 버퍼 · DIRTYFB)은 hidpi 체인의 screendump가 본다.

fn expectPick(fixed: ?u32, w: u32, h: u32, want: u32) !void {
    const got = scale.pick(fixed, w, h);
    if (got == want) return;
    std.debug.print("FAIL: pick({?d}, {d}, {d}) = {d}, want {d}\n", .{ fixed, w, h, got, want });
    return error.WrongScale;
}

/// 물리 버퍼의 표식. 늘리기가 사각형 밖을 건드리면 이 값이 바뀐다.
const SENTINEL: u32 = 0xDEADBEEF;

/// 논리 `lw × lh`를 픽셀마다 다른 값으로 채운 버퍼를 `s`배로 옮기고, 물리 픽셀 전부를 본다 —
/// `r` 안의 블록은 논리 픽셀 `(x / s, y / s)`이고 밖은 표식이다. 물리 pitch에 여분을 두어
/// "pitch가 폭 × 4가 아니다"(dumb 버퍼의 pitch는 드라이버가 정한다)도 함께 본다.
fn expectUpscale(lw: u32, lh: u32, r: scale.Rect, s: u32) !void {
    const src_pitch: usize = @as(usize, lw) * 4;
    const pw: usize = @as(usize, lw) * s + 3;
    const ph: usize = @as(usize, lh) * s + 2;
    const dst_pitch: usize = pw * 4 + 16;

    var src_buf: [16 * 16]u32 = undefined;
    var dst_buf: [4096 * 2]u32 = undefined;
    const dst_words = dst_pitch / 4 * ph;
    if (lw * lh > src_buf.len or dst_words > dst_buf.len) return error.TestBufferTooSmall;
    for (src_buf[0 .. lw * lh], 0..) |*p, i| p.* = 0x00100000 + @as(u32, @intCast(i));
    @memset(dst_buf[0..dst_words], SENTINEL);

    scale.upscale(@ptrCast(&src_buf), src_pitch, @ptrCast(&dst_buf), dst_pitch, r, s);

    var y: usize = 0;
    while (y < ph) : (y += 1) {
        var x: usize = 0;
        while (x < dst_pitch / 4) : (x += 1) {
            const got = dst_buf[y * dst_pitch / 4 + x];
            const lx = x / s;
            const ly = y / s;
            const inside = x < @as(usize, lw) * s and y < @as(usize, lh) * s and
                lx >= r.x1 and lx < r.x2 and ly >= r.y1 and ly < r.y2;
            const want = if (inside) src_buf[ly * lw + lx] else SENTINEL;
            if (got != want) {
                std.debug.print("FAIL: upscale {d}x{d} rect {d},{d}-{d},{d} by {d}: physical ({d},{d}) = {x}, want {x}\n", .{
                    lw, lh, r.x1, r.y1, r.x2, r.y2, s, x, y, got, want,
                });
                return error.WrongUpscale;
            }
        }
    }
}

pub fn main() !void {
    // ── 검사 1: auto의 표(HS design 결정 3) ─────────────────────────────
    try expectPick(null, 1280, 800, 1);
    try expectPick(null, 1366, 768, 1);
    try expectPick(null, 1920, 1080, 1);
    try expectPick(null, 2560, 1600, 2);
    try expectPick(null, 2880, 1800, 2);
    try expectPick(null, 3840, 2160, 2);
    try expectPick(null, 3840, 2400, 3);
    // 1280×800보다 작은 화면도 1이다 — 0이 되면 논리 크기가 0으로 나뉜다.
    try expectPick(null, 1024, 768, 1);
    try expectPick(null, 640, 480, 1);
    // 상한 3.
    try expectPick(null, 7680, 4800, 3);
    std.debug.print("scale_test: 1. auto keeps the screen at least 1280x800, 1..3 OK\n", .{});

    // ── 검사 2: 강제한 배율이 auto를 이긴다 ─────────────────────────────
    try expectPick(1, 2880, 1800, 1);
    try expectPick(2, 1280, 800, 2);
    try expectPick(3, 2880, 1800, 3);
    std.debug.print("scale_test: 2. a fixed scale wins over auto OK\n", .{});

    // ── 검사 3: 늘리기 — 사각형 안은 s × s 블록, 밖은 그대로 ─────────────
    // 전체(clip 없는 present가 쓰는 것), 가운데 한 조각(키 하나의 행), 픽셀 하나, 빈 사각형.
    for ([_]u32{ 1, 2, 3 }) |s| {
        try expectUpscale(5, 4, .{ .x1 = 0, .y1 = 0, .x2 = 5, .y2 = 4 }, s);
        try expectUpscale(5, 4, .{ .x1 = 1, .y1 = 2, .x2 = 4, .y2 = 3 }, s);
        try expectUpscale(5, 4, .{ .x1 = 4, .y1 = 3, .x2 = 5, .y2 = 4 }, s);
        try expectUpscale(5, 4, .{ .x1 = 2, .y1 = 2, .x2 = 2, .y2 = 3 }, s);
    }
    std.debug.print("scale_test: 3. upscale writes s x s blocks inside the rect and nothing outside OK\n", .{});

    // ── 검사 4: 마스크 늘리기(WY-M3) — 마스크가 참인 픽셀만 블록, 나머지 물리는 그대로 ──────────
    // 논리 4 × 3의 사각형 (1, 1)–(3, 3)(2 × 2)에 대각선 마스크. 배율 2 → 참인 두 블록만 바뀐다.
    {
        const s: u32 = 2;
        var src: [4 * 3]u32 = undefined;
        for (&src, 0..) |*p, i| p.* = 0x100 + @as(u32, @intCast(i));
        var dst: [8 * 6]u32 = @splat(SENTINEL);
        const mask = [_]bool{ true, false, false, true };
        scale.upscaleMasked(@ptrCast(&src), 4 * 4, @ptrCast(&dst), 8 * 4, .{ .x1 = 1, .y1 = 1, .x2 = 3, .y2 = 3 }, s, &mask, 2);
        for (0..6) |y| for (0..8) |x| {
            const lx = x / s;
            const ly = y / s;
            const on = lx >= 1 and lx < 3 and ly >= 1 and ly < 3 and mask[(ly - 1) * 2 + (lx - 1)];
            const want = if (on) src[ly * 4 + lx] else SENTINEL;
            if (dst[y * 8 + x] != want) {
                std.debug.print("FAIL: upscaleMasked physical ({d},{d}) = {x}, want {x}\n", .{ x, y, dst[y * 8 + x], want });
                return error.WrongMaskedUpscale;
            }
        };
    }
    std.debug.print("scale_test: 4. upscaleMasked writes only the masked pixels as s x s blocks OK\n", .{});
}
