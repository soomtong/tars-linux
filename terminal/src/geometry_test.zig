const std = @import("std");
const geometry = @import("geometry.zig");

// 격자 자리 셈과 사각형 자르기를 호스트에서 본다(FU-M0). 화면에 닿는 것은 fullscreen 체인이 본다.
// 화면 셋: QEMU(게이트) 1280 × 800, MacBook Air 11" 1366 × 768, 배율 2의 논리 1440 × 900(hidpi 체인의 `grid 175x53`).

fn expectGrid(w: u32, h: u32, full: bool, want: geometry.Grid) !void {
    const got = geometry.grid(w, h, full);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: grid({d}, {d}, {}) = {any}, want {any}\n", .{ w, h, full, got, want });
    return error.WrongGrid;
}

fn expectClip(r: geometry.Rect, fw: u32, fh: u32, want: ?geometry.Rect) !void {
    const got = geometry.clip(r, fw, fh);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: clip({any}, {d}, {d}) = {any}, want {any}\n", .{ r, fw, fh, got, want });
    return error.WrongClip;
}

pub fn main() !void {
    // 여백 — FU 전의 셈 그대로(machine 체인의 `grid 155x47 (fb 1280x800)`).
    try expectGrid(1280, 800, false, .{ .x = 20, .y = 20, .cols = 155, .rows = 47 });
    try expectGrid(1366, 768, false, .{ .x = 20, .y = 20, .cols = 165, .rows = 45 });
    try expectGrid(1440, 900, false, .{ .x = 20, .y = 20, .cols = 175, .rows = 53 });
    // 전체 화면 — 남는 픽셀의 반이 원점이다.
    try expectGrid(1280, 800, true, .{ .x = 0, .y = 0, .cols = 160, .rows = 50 });
    try expectGrid(1366, 768, true, .{ .x = 3, .y = 0, .cols = 170, .rows = 48 });
    try expectGrid(1440, 900, true, .{ .x = 0, .y = 2, .cols = 180, .rows = 56 });
    std.debug.print("geometry_test: grid 6 screens\n", .{});

    // 자르기 — 안 · 오른쪽으로 반 칸 · 아래로 · 모서리 · 다 밖 · 빈 사각형.
    try expectClip(.{ .x = 0, .y = 0, .w = 8, .h = 16 }, 1280, 800, .{ .x = 0, .y = 0, .w = 8, .h = 16 });
    try expectClip(.{ .x = 1272, .y = 784, .w = 16, .h = 16 }, 1280, 800, .{ .x = 1272, .y = 784, .w = 8, .h = 16 });
    try expectClip(.{ .x = 0, .y = 790, .w = 8, .h = 16 }, 1280, 800, .{ .x = 0, .y = 790, .w = 8, .h = 10 });
    try expectClip(.{ .x = 1276, .y = 796, .w = 16, .h = 16 }, 1280, 800, .{ .x = 1276, .y = 796, .w = 4, .h = 4 });
    try expectClip(.{ .x = 1280, .y = 0, .w = 8, .h = 16 }, 1280, 800, null);
    try expectClip(.{ .x = 0, .y = 800, .w = 8, .h = 16 }, 1280, 800, null);
    try expectClip(.{ .x = 0, .y = 0, .w = 0, .h = 16 }, 1280, 800, null);
    std.debug.print("geometry_test: clip 7 cases\n", .{});
    std.debug.print("geometry_test: all checks passed\n", .{});
}
