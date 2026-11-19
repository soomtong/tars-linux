const std = @import("std");
const logic = @import("wl_logic.zig");

// WY-M0: Wayland 서버의 순수한 셋(배율 · 옮기기 · configure 순서)을 호스트에서 본다. 화면에 닿는 것은 wayland 체인이 본다.
// 화면은 QEMU(게이트) 1280 × 800과 MacBook Air 11" 1366 × 768이다.

fn expectFit(fw: u32, fh: u32, bw: u32, bh: u32, want: ?logic.Fit) !void {
    const got = logic.fit(fw, fh, bw, bh);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: fit({d}, {d}, {d}, {d}) = {any}, want {any}\n", .{ fw, fh, bw, bh, got, want });
    return error.WrongFit;
}

fn expectStep(phase: logic.Phase, acked: bool, has: bool, want: logic.Step) !void {
    const got = logic.onCommit(phase, acked, has);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: onCommit({s}, {}, {}) = {any}, want {any}\n", .{ @tagName(phase), acked, has, got, want });
    return error.WrongStep;
}

pub fn main() !void {
    // tars-wl-test의 기본 320x200은 1280x800을 4배로 꽉 채운다 — 둘레가 없다. 그래서 체인은 다른 크기를 줘야 모서리가 검정이다.
    try expectFit(1280, 800, 320, 200, .{ .k = 4, .x = 0, .y = 0, .w = 1280, .h = 800, .ox = 0, .oy = 0 });
    // 300x200 → 4배 1200x800, 가로 둘레 40.
    try expectFit(1280, 800, 300, 200, .{ .k = 4, .x = 40, .y = 0, .w = 1200, .h = 800, .ox = 0, .oy = 0 });
    // 둠의 320x200을 1366x768에: min(4, 3) = 3 → 960x600, 둘레 203 · 84.
    try expectFit(1366, 768, 320, 200, .{ .k = 3, .x = 203, .y = 84, .w = 960, .h = 600, .ox = 0, .oy = 0 });
    // 화면 크기 그대로(configure를 따른 클라이언트) — 1배, 둘레 없음.
    try expectFit(1280, 800, 1280, 800, .{ .k = 1, .x = 0, .y = 0, .w = 1280, .h = 800, .ox = 0, .oy = 0 });
    // 화면보다 큰 버퍼 — 1배이고 가운데를 잘라 보인다.
    try expectFit(1280, 800, 1400, 900, .{ .k = 1, .x = 0, .y = 0, .w = 1280, .h = 800, .ox = 60, .oy = 50 });
    // 한쪽만 큰 버퍼 — 가로는 자르고 세로는 가운데.
    try expectFit(1280, 800, 2000, 100, .{ .k = 1, .x = 0, .y = 350, .w = 1280, .h = 100, .ox = 360, .oy = 0 });
    // 크기 0.
    try expectFit(1280, 800, 0, 200, null);
    try expectFit(0, 800, 320, 200, null);
    std.debug.print("wl_logic_test: fit 8 cases\n", .{});

    // 옮기기 — 2x2 버퍼를 8x6 화면에: k = min(4, 3) = 3 → 6x6, 가로 둘레 1.
    {
        const src = [4]u32{ 0xFF112233, 0xFF445566, 0x00778899, 0xFFAABBCC };
        var dst: [8 * 6]u32 = @splat(0xDEADBEEF);
        const f = logic.fit(8, 6, 2, 2).?;
        if (f.k != 3 or f.x != 1 or f.y != 0) return error.WrongSmallFit;
        logic.blit(@ptrCast(&dst), 8 * 4, f, @ptrCast(&src), 2 * 4);
        for (0..6) |y| {
            for (0..8) |x| {
                const want: u32 = if (x == 0 or x == 7) 0xDEADBEEF else src[(y / 3) * 2 + (x - 1) / 3];
                if (dst[y * 8 + x] != want) {
                    std.debug.print("FAIL: blit k=3 at {d},{d} = {x}, want {x}\n", .{ x, y, dst[y * 8 + x], want });
                    return error.WrongBlit;
                }
            }
        }
    }
    // 1배 · 잘림 — 4x1 버퍼(행 간격 20바이트, 뒤 넷은 군더더기)를 2x1 화면에: 가운데 둘(ox=1).
    {
        const src = [5]u32{ 1, 2, 3, 4, 0xBAD };
        var dst: [2]u32 = @splat(0);
        const f = logic.fit(2, 1, 4, 1).?;
        logic.blit(@ptrCast(&dst), 2 * 4, f, @ptrCast(&src), 5 * 4);
        if (dst[0] != 2 or dst[1] != 3) {
            std.debug.print("FAIL: blit k=1 crop = {any}\n", .{dst});
            return error.WrongCrop;
        }
    }
    if (!logic.formatOk(logic.FORMAT_ARGB8888) or !logic.formatOk(logic.FORMAT_XRGB8888) or logic.formatOk(0x34325241))
        return error.WrongFormat;
    std.debug.print("wl_logic_test: blit 2 cases, format 3\n", .{});

    // configure 순서 — 첫 commit은 버퍼 없이(configure를 보낸다), ack 뒤 버퍼(보인다), 그 뒤는 다시 그린다.
    try expectStep(.fresh, false, false, .{ .action = .send_configure, .next = .configured });
    try expectStep(.fresh, false, true, .{ .action = .unconfigured_buffer, .next = .fresh });
    try expectStep(.configured, false, false, .{ .action = .wait, .next = .configured });
    try expectStep(.configured, false, true, .{ .action = .unconfigured_buffer, .next = .configured });
    try expectStep(.configured, true, false, .{ .action = .wait, .next = .configured });
    try expectStep(.configured, true, true, .{ .action = .map, .next = .mapped });
    try expectStep(.mapped, true, true, .{ .action = .update, .next = .mapped });
    try expectStep(.mapped, true, false, .{ .action = .update, .next = .mapped });
    std.debug.print("wl_logic_test: configure 8 steps\n", .{});
    std.debug.print("wl_logic_test: all checks passed\n", .{});
}
