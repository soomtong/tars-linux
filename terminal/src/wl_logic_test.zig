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
        logic.blit(@ptrCast(&dst), 8 * 4, f, @ptrCast(&src), 2 * 4, 1);
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
        logic.blit(@ptrCast(&dst), 2 * 4, f, @ptrCast(&src), 5 * 4, 1);
        if (dst[0] != 2 or dst[1] != 3) {
            std.debug.print("FAIL: blit k=1 crop = {any}\n", .{dst});
            return error.WrongCrop;
        }
    }
    if (!logic.formatOk(logic.FORMAT_ARGB8888) or !logic.formatOk(logic.FORMAT_XRGB8888) or logic.formatOk(0x34325241))
        return error.WrongFormat;
    std.debug.print("wl_logic_test: blit 2 cases, format 3\n", .{});

    // WY-M3: 버퍼 배율. surface 크기는 버퍼 ÷ bs, 규칙 둘(invalid_scale · invalid_size).
    {
        if (!std.meta.eql(logic.surfaceSize(1392, 1696, 2), logic.Size{ .w = 696, .h = 848 })) return error.WrongSurfaceSize;
        if (!std.meta.eql(logic.surfaceSize(320, 200, 1), logic.Size{ .w = 320, .h = 200 })) return error.WrongSurfaceSize;
        if (logic.scaleOk(0) or logic.scaleOk(-1) or !logic.scaleOk(1) or !logic.scaleOk(3)) return error.WrongScaleRule;
        if (!logic.sizeOk(640, 400, 2) or logic.sizeOk(641, 400, 2) or logic.sizeOk(640, 401, 2) or !logic.sizeOk(7, 5, 1))
            return error.WrongSizeRule;
        // bs 2 버퍼를 surface 크기로 놓는다 — 696 × 848 column에 1392 × 1696 버퍼면 1배, 둘레 없음(버퍼 크기로 놓던 WY-M2는
        // k = 1 · 가운데를 잘라 왼쪽 위가 (348, 424)였다).
        const sz = logic.surfaceSize(1392, 1696, 2);
        const f = logic.fitIn(.{ .x = 704, .y = 20, .w = 696, .h = 848 }, sz.w, sz.h).?;
        if (!std.meta.eql(f, logic.Fit{ .k = 1, .x = 704, .y = 20, .w = 696, .h = 848, .ox = 0, .oy = 0 })) return error.WrongScaledFit;
    }
    // 솎기 — 4x4 바둑판 버퍼(bs 2, surface 2x2)를 2x2 화면에 k = 1: 버퍼의 짝수 행 · 짝수 열만 남는다.
    {
        var src: [16]u32 = undefined;
        for (0..4) |y| for (0..4) |x| {
            src[y * 4 + x] = @intCast(y * 4 + x);
        };
        var dst: [4]u32 = @splat(0);
        const f = logic.fit(2, 2, 2, 2).?;
        logic.blit(@ptrCast(&dst), 2 * 4, f, @ptrCast(&src), 4 * 4, 2);
        if (!std.mem.eql(u32, &dst, &.{ 0, 2, 8, 10 })) {
            std.debug.print("FAIL: blit bs=2 k=1 = {any}\n", .{dst});
            return error.WrongDecimate;
        }
    }
    // k == bs는 1:1 — 2x2 버퍼(bs 2, surface 1x1)를 2x2 화면에 k = 2: 버퍼 그대로.
    {
        const src = [4]u32{ 1, 2, 3, 4 };
        var dst: [4]u32 = @splat(0);
        const f = logic.fit(2, 2, 1, 1).?;
        if (f.k != 2) return error.WrongSmallFit;
        logic.blit(@ptrCast(&dst), 2 * 4, f, @ptrCast(&src), 2 * 4, 2);
        if (!std.mem.eql(u32, &dst, &.{ 1, 2, 3, 4 })) {
            std.debug.print("FAIL: blit bs=2 k=2 = {any}\n", .{dst});
            return error.WrongOneToOne;
        }
    }
    // bs 2 · k 3(surface 1x1을 3배) — 화면 픽셀 p는 버퍼 p · 2 / 3: 0, 0, 1.
    {
        const src = [4]u32{ 1, 2, 3, 4 };
        var dst: [9]u32 = @splat(0);
        const f = logic.fit(3, 3, 1, 1).?;
        logic.blit(@ptrCast(&dst), 3 * 4, f, @ptrCast(&src), 2 * 4, 2);
        if (!std.mem.eql(u32, &dst, &.{ 1, 1, 2, 1, 1, 2, 3, 3, 4 })) {
            std.debug.print("FAIL: blit bs=2 k=3 = {any}\n", .{dst});
            return error.WrongDecimate;
        }
    }
    std.debug.print("wl_logic_test: buffer scale 5 cases, blit bs 3 cases\n", .{});

    // WY-M3 단계 B: 물리 합성의 셈. 교집합 · × 배율, 그리고 잘라 옮기기 = 통째 blit의 그 사각형.
    {
        const a: logic.Area = .{ .x = 2, .y = 1, .w = 4, .h = 3 };
        if (!std.meta.eql(logic.intersect(a, .{ .x = 4, .y = 0, .w = 5, .h = 2 }), logic.Area{ .x = 4, .y = 1, .w = 2, .h = 1 }))
            return error.WrongIntersect;
        if (logic.intersect(a, .{ .x = 6, .y = 1, .w = 2, .h = 2 }) != null) return error.WrongIntersect;
        if (!std.meta.eql(logic.scaleArea(a, 2), logic.Area{ .x = 4, .y = 2, .w = 8, .h = 6 })) return error.WrongScaleArea;
        const f: logic.Fit = .{ .k = 1, .x = 3, .y = 2, .w = 4, .h = 3, .ox = 1, .oy = 0 };
        if (!std.meta.eql(logic.scaleFit(f, 2), logic.Fit{ .k = 2, .x = 6, .y = 4, .w = 8, .h = 6, .ox = 2, .oy = 0 }))
            return error.WrongScaleFit;
    }
    // bs 2 버퍼(surface 3 × 2 → 버퍼 6 × 4)를 논리 (1, 1)에 k 1로 둔 자리를 배율 2 물리(12 × 8)에 — 1:1이라 버퍼가 그대로
    // 물리 (2, 2)부터 놓인다. 그리고 clip 셋(창 안 조각 · 걸친 것 · 밖)으로 잘라 옮긴 것이 통째의 그 자리와 같고 밖은 손대지 않는다.
    {
        var src: [6 * 4]u32 = undefined;
        for (&src, 0..) |*p, i| p.* = 0x1000 + @as(u32, @intCast(i));
        const lf = logic.fitIn(.{ .x = 1, .y = 1, .w = 3, .h = 2 }, 3, 2).?;
        const pf = logic.scaleFit(lf, 2);
        if (pf.k != 2) return error.WrongScaleFit;
        var whole: [12 * 8]u32 = @splat(0);
        logic.blit(@ptrCast(&whole), 12 * 4, pf, @ptrCast(&src), 6 * 4, 2);
        for (0..8) |y| for (0..12) |x| {
            const in = x >= 2 and x < 8 and y >= 2 and y < 6;
            const want: u32 = if (in) src[(y - 2) * 6 + (x - 2)] else 0;
            if (whole[y * 12 + x] != want) {
                std.debug.print("FAIL: physical 1:1 blit at {d},{d} = {x}, want {x}\n", .{ x, y, whole[y * 12 + x], want });
                return error.WrongPhysicalBlit;
            }
        };
        for ([_]logic.Area{ .{ .x = 3, .y = 3, .w = 2, .h = 2 }, .{ .x = 0, .y = 4, .w = 5, .h = 4 }, .{ .x = 9, .y = 0, .w = 3, .h = 8 } }) |c| {
            var part: [12 * 8]u32 = @splat(0xDEAD);
            logic.blitClip(@ptrCast(&part), 12 * 4, pf, @ptrCast(&src), 6 * 4, 2, c);
            for (0..8) |y| for (0..12) |x| {
                const in_clip = x >= c.x and x < c.x + c.w and y >= c.y and y < c.y + c.h;
                const in_win = x >= 2 and x < 8 and y >= 2 and y < 6;
                const want: u32 = if (in_clip and in_win) whole[y * 12 + x] else 0xDEAD;
                if (part[y * 12 + x] != want) {
                    std.debug.print("FAIL: blitClip {any} at {d},{d} = {x}, want {x}\n", .{ c, x, y, part[y * 12 + x], want });
                    return error.WrongBlitClip;
                }
            };
        }
        // 솎는 갈래(k ≠ bs)도 잘라 옮기기가 통째와 같다 — 같은 버퍼를 논리(k 1, bs 2)로.
        var lw: [5 * 4]u32 = @splat(0);
        logic.blit(@ptrCast(&lw), 5 * 4, lf, @ptrCast(&src), 6 * 4, 2);
        var lp: [5 * 4]u32 = @splat(0);
        logic.blitClip(@ptrCast(&lp), 5 * 4, lf, @ptrCast(&src), 6 * 4, 2, .{ .x = 2, .y = 0, .w = 3, .h = 4 });
        for (0..4) |y| for (0..5) |x| {
            const want: u32 = if (x >= 2) lw[y * 5 + x] else 0;
            if (lp[y * 5 + x] != want) return error.WrongBlitClip;
        };
    }
    std.debug.print("wl_logic_test: physical compose 4 cases, 1:1 blit 1, blitClip 4 cases\n", .{});

    // damage(WY-M6 단계 B, design 결정 47) — 쌓기 · 자르기 · 화면 자리.
    {
        // 빈 사각형은 damage가 아니다. `damage`(surface 좌표)는 × buffer_scale.
        if (logic.boxOf(0, 0, 0, 5, 1) != null or logic.boxOf(0, 0, 5, -1, 1) != null) return error.WrongDamage;
        const s2 = logic.boxOf(3, 4, 5, 6, 2).?;
        if (!std.meta.eql(s2, logic.Box{ .x0 = 6, .y0 = 8, .x1 = 16, .y1 = 20 })) return error.WrongDamage;
        // `damage_buffer(0, 0, INT32_MAX, INT32_MAX)`(tars-wl-test · SDL의 통째)는 버퍼 전체로 잘린다. 음수 자리도 자른다.
        const all = logic.boxOf(0, 0, std.math.maxInt(i32), std.math.maxInt(i32), 1).?;
        if (!std.meta.eql(logic.boxClamp(all, 300, 200), logic.Area{ .x = 0, .y = 0, .w = 300, .h = 200 })) return error.WrongDamage;
        const neg = logic.boxOf(-10, -10, 20, 15, 1).?;
        if (!std.meta.eql(logic.boxClamp(neg, 300, 200), logic.Area{ .x = 0, .y = 0, .w = 10, .h = 5 })) return error.WrongDamage;
        if (logic.boxClamp(logic.boxOf(400, 0, 10, 10, 1).?, 300, 200) != null) return error.WrongDamage;
        // 합집합 — 한 commit에 `damage_buffer` 하나와 `damage` 하나(실측 4의 모양), 그리고 commit 둘(실측 7).
        const u = logic.boxUnion(logic.boxOf(0, 0, 32, 32, 1), logic.boxOf(64, 0, 32, 32, 1).?);
        if (!std.meta.eql(logic.boxClamp(u, 616, 752), logic.Area{ .x = 0, .y = 0, .w = 96, .h = 32 })) return error.WrongDamage;
        const au = logic.areaUnion(.{ .x = 0, .y = 64, .w = 32, .h = 32 }, .{ .x = 64, .y = 64, .w = 32, .h = 32 });
        if (!std.meta.eql(au, logic.Area{ .x = 0, .y = 64, .w = 96, .h = 32 })) return error.WrongDamage;
        if (!std.meta.eql(logic.areaUnion(null, au), au)) return error.WrongDamage;

        const r: logic.Area = .{ .x = 3, .y = 5, .w = 4, .h = 2 };
        const cases = [_]struct { f: logic.Fit, bs: u32, want: ?logic.Area }{
            // k 1 · bs 1 — column을 1배로 채운 창(x 644, y 20): 그대로 옮긴다.
            .{ .f = .{ .k = 1, .x = 644, .y = 20, .w = 616, .h = 752, .ox = 0, .oy = 0 }, .bs = 1, .want = .{ .x = 647, .y = 25, .w = 4, .h = 2 } },
            // k 2 · bs 1 — 2배로 늘린 창: 자리와 크기가 둘 다 두 배.
            .{ .f = .{ .k = 2, .x = 40, .y = 0, .w = 600, .h = 400, .ox = 0, .oy = 0 }, .bs = 1, .want = .{ .x = 46, .y = 10, .w = 8, .h = 4 } },
            // k 1 · bs 2 — 배율 2 화면의 논리 그림자에 bs 2 버퍼(솎기): 버퍼 [3, 7) → 화면 [1, 4)(바깥으로), [5, 7) → [2, 4).
            .{ .f = .{ .k = 1, .x = 0, .y = 0, .w = 100, .h = 100, .ox = 0, .oy = 0 }, .bs = 2, .want = .{ .x = 1, .y = 2, .w = 3, .h = 2 } },
            // 잘린 창(버퍼가 사각형보다 크다, ox 4 · oy 0) — [3, 7)의 보이는 쪽 [4, 7)이 화면 x 10 + 0부터 3.
            .{ .f = .{ .k = 1, .x = 10, .y = 0, .w = 20, .h = 20, .ox = 4, .oy = 0 }, .bs = 1, .want = .{ .x = 10, .y = 5, .w = 3, .h = 2 } },
            // 보이는 자리 밖(ox가 damage보다 오른쪽) — null.
            .{ .f = .{ .k = 1, .x = 10, .y = 0, .w = 20, .h = 20, .ox = 8, .oy = 0 }, .bs = 1, .want = null },
        };
        for (cases) |cs| {
            const got = logic.damageScreen(cs.f, cs.bs, r);
            if (!std.meta.eql(got, cs.want)) {
                std.debug.print("FAIL: damageScreen({any}, bs {d}) = {any}, want {any}\n", .{ cs.f, cs.bs, got, cs.want });
                return error.WrongDamage;
            }
        }
    }
    std.debug.print("wl_logic_test: damage box 7 cases, damageScreen 5 cases\n", .{});

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

    // 수정키 비트(단계 C) — 확인 3의 값. 잠금은 locked 쪽이다.
    {
        const none = logic.modifierMask(.{});
        if (none.depressed != 0 or none.locked != 0) return error.WrongMask;
        const all = logic.modifierMask(.{ .shift = true, .caps = true, .ctrl = true, .alt = true, .super = true });
        if (all.depressed != 0x1 | 0x4 | 0x8 | 0x40 or all.locked != 0x2) {
            std.debug.print("FAIL: mask all = {any}\n", .{all});
            return error.WrongMask;
        }
        // Cmd 하나 = Super 0x40.
        if (logic.modifierMask(.{ .super = true }).depressed != 0x40) return error.WrongMask;
        if (logic.modifierMask(.{ .caps = true }).depressed != 0) return error.WrongMask;
    }
    std.debug.print("wl_logic_test: modifiers 4 cases\n", .{});

    // 호환 모드(WY-M6, design 결정 45) — Super가 Ctrl로 보인다. 잠금은 그대로.
    {
        const cases = [_]struct { in: logic.Mask, out: logic.Mask }{
            // Super만 → Ctrl.
            .{ .in = .{ .depressed = 0x40, .locked = 0 }, .out = .{ .depressed = 0x4, .locked = 0 } },
            // Super + Shift → Ctrl + Shift, 잠금 유지.
            .{ .in = .{ .depressed = 0x41, .locked = 0x2 }, .out = .{ .depressed = 0x5, .locked = 0x2 } },
            // Super + Ctrl → Ctrl 하나.
            .{ .in = .{ .depressed = 0x44, .locked = 0 }, .out = .{ .depressed = 0x4, .locked = 0 } },
            // Super 없음 → 그대로(Ctrl + Alt).
            .{ .in = .{ .depressed = 0xC, .locked = 0x2 }, .out = .{ .depressed = 0xC, .locked = 0x2 } },
        };
        for (cases) |cs| {
            const got = logic.compatMask(cs.in);
            if (!std.meta.eql(got, cs.out)) {
                std.debug.print("FAIL: compatMask({any}) = {any}, want {any}\n", .{ cs.in, got, cs.out });
                return error.WrongMask;
            }
        }
    }
    std.debug.print("wl_logic_test: compat mask 4 cases\n", .{});

    // 보낸 누름 — 누름을 보낸 키만 뗌이 간다(R-KEY-2 · R-KEY-7).
    {
        var h: logic.Held = .{};
        // 포커스 전에 누른 키(30)의 뗌은 안 간다.
        if (h.release(30)) return error.WrongHeld;
        if (!h.press(30) or !h.release(30)) return error.WrongHeld;
        // 같은 뗌이 두 번 오면 둘째는 안 간다.
        if (h.release(30)) return error.WrongHeld;
        // 비우면(포커스가 바뀌면) 쥐었던 키의 뗌도 안 간다.
        _ = h.press(125);
        h.clear();
        if (h.release(125)) return error.WrongHeld;
        // 범위 밖은 보내지 않는다.
        if (h.press(0x300) or h.release(0x300)) return error.WrongHeld;
        if (!h.press(0x2ff) or !h.release(0x2ff)) return error.WrongHeld;
    }
    std.debug.print("wl_logic_test: held 6 cases\n", .{});

    // Cmd+Q의 기한 — 2초, pong이면 버린다, 거듭 눌러도 안 밀린다.
    {
        var d: logic.Deadline = .{};
        if (d.timeout(0) != -1 or d.expired(1_000_000)) return error.WrongDeadline;
        if (!d.arm(1000, 7)) return error.WrongDeadline;
        if (d.timeout(1000) != 2000 or d.timeout(2500) != 500 or d.timeout(9000) != 0) return error.WrongDeadline;
        // 둘째 Cmd+Q는 기한을 밀지 않는다.
        if (d.arm(2000, 8) or d.serial != 7) return error.WrongDeadline;
        if (d.expired(2999)) return error.WrongDeadline;
        if (!d.expired(3000)) return error.WrongDeadline;
        // 한 번만 참이다(SIGKILL을 두 번 안 보낸다).
        if (d.expired(3001) or d.timeout(3001) != -1) return error.WrongDeadline;
        // pong — 다른 serial은 안 버리고, 기다리던 serial은 버린다.
        _ = d.arm(5000, 9);
        if (d.pong(8)) return error.WrongDeadline;
        if (!d.pong(9) or d.expired(10_000)) return error.WrongDeadline;
    }
    std.debug.print("wl_logic_test: deadline 9 cases\n", .{});

    // WY-M2: pane 사각형 안의 자리(fitIn). 오른쪽 column 하나를 흉내 낸 사각형(x 632, 616 × 752)이다 — 셀 크기와는
    // 무관하게 사각형 산수만 본다.
    {
        const right: logic.Area = .{ .x = 632, .y = 0, .w = 616, .h = 752 };
        // configure를 따른 버퍼 — 1배로 사각형을 채운다.
        if (!std.meta.eql(logic.fitIn(right, 616, 752), logic.Fit{ .k = 1, .x = 632, .y = 0, .w = 616, .h = 752, .ox = 0, .oy = 0 }))
            return error.WrongFitIn;
        // 따르지 않은 작은 버퍼(SDL의 RESIZABLE 아닌 창 300x200) — 2배 600x400, 사각형 안 가운데.
        if (!std.meta.eql(logic.fitIn(right, 300, 200), logic.Fit{ .k = 2, .x = 632 + 8, .y = 176, .w = 600, .h = 400, .ox = 0, .oy = 0 }))
            return error.WrongFitIn;
        // 사각형보다 큰 버퍼(화면 크기 640x480보다 넓은 창) — 1배, 가운데가 잘린다.
        if (!std.meta.eql(logic.fitIn(right, 640, 480), logic.Fit{ .k = 1, .x = 632, .y = 136, .w = 616, .h = 480, .ox = 12, .oy = 0 }))
            return error.WrongFitIn;
        // 화면 전체의 사각형이면 fit과 같다.
        if (!std.meta.eql(logic.fitIn(.{ .x = 0, .y = 0, .w = 1280, .h = 800 }, 300, 200), logic.fit(1280, 800, 300, 200)))
            return error.WrongFitIn;
        if (logic.fitIn(right, 0, 10) != null or logic.fitIn(.{ .x = 0, .y = 0, .w = 0, .h = 10 }, 1, 1) != null)
            return error.WrongFitIn;
    }
    std.debug.print("wl_logic_test: fitIn 5 cases\n", .{});

    // WY-M2: configure의 states. 자기 workspace는 fullscreen · activated, column은 activated(포커스일 때) + tiled 넷(판 2+).
    {
        var buf: [6]u32 = undefined;
        if (!std.mem.eql(u32, logic.toplevelStates(.workspace, false, 5, &buf), &.{ 2, 4 })) return error.WrongStates;
        if (!std.mem.eql(u32, logic.toplevelStates(.column, true, 5, &buf), &.{ 4, 5, 6, 7, 8 })) return error.WrongStates;
        if (!std.mem.eql(u32, logic.toplevelStates(.column, false, 5, &buf), &.{ 5, 6, 7, 8 })) return error.WrongStates;
        // 판 1에는 tiled가 없다.
        if (!std.mem.eql(u32, logic.toplevelStates(.column, true, 1, &buf), &.{4})) return error.WrongStates;
        if (logic.toplevelStates(.column, false, 1, &buf).len != 0) return error.WrongStates;
    }
    std.debug.print("wl_logic_test: states 5 cases\n", .{});

    // WY-M2 단계 C: 화면 → surface 좌표(24.8). 오른쪽 column 616x752를 1배로 채운 창, x 644 · y 20에서 시작.
    {
        const f = logic.fitIn(.{ .x = 644, .y = 20, .w = 616, .h = 752 }, 616, 752).?;
        if (!std.meta.eql(logic.surfacePoint(f, 644, 20), logic.Point{ .x = 0, .y = 0 })) return error.WrongPoint;
        if (!std.meta.eql(logic.surfacePoint(f, 952, 396), logic.Point{ .x = 308 * 256, .y = 376 * 256 })) return error.WrongPoint;
        // 창 밖(grab 중의 끎) — 음수.
        if (!std.meta.eql(logic.surfacePoint(f, 600, 10), logic.Point{ .x = -44 * 256, .y = -10 * 256 })) return error.WrongPoint;
        if (!logic.inside(f, 644, 20) or logic.inside(f, 643, 20) or logic.inside(f, 1260, 20)) return error.WrongPoint;
        // 4배로 늘린 둠(320x200 → 1280x800) — 화면 픽셀 넷이 버퍼 픽셀 하나다.
        const d = logic.fit(1280, 800, 320, 200).?;
        if (!std.meta.eql(logic.surfacePoint(d, 6, 10), logic.Point{ .x = 384, .y = 640 })) return error.WrongPoint;
        // 가운데가 잘린 큰 버퍼(1배, ox 60) — 화면 0이 버퍼 60이다.
        const c = logic.fit(1280, 800, 1400, 900).?;
        if (!std.meta.eql(logic.surfacePoint(c, 0, 0), logic.Point{ .x = 60 * 256, .y = 50 * 256 })) return error.WrongPoint;
    }
    // WY-M3: 같은 column에 bs 1 버퍼(696 × 848)와 bs 2 버퍼(1392 × 1696) — surface 크기로 놓으면 같은 화면 점이 같은 surface
    // 점이다(포인터 좌표는 surface 단위, 버퍼 픽셀이 아니다).
    {
        const area: logic.Area = .{ .x = 704, .y = 20, .w = 696, .h = 848 };
        const one = logic.fitIn(area, 696, 848).?;
        const s2 = logic.surfaceSize(1392, 1696, 2);
        const two = logic.fitIn(area, s2.w, s2.h).?;
        for ([_][2]u32{ .{ 704, 20 }, .{ 1000, 500 }, .{ 1399, 867 } }) |p| {
            const a = logic.surfacePoint(one, p[0], p[1]);
            const b = logic.surfacePoint(two, p[0], p[1]);
            if (!std.meta.eql(a, b)) return error.WrongScaledPoint;
        }
        if (!std.meta.eql(logic.surfacePoint(two, 1000, 500), logic.Point{ .x = 296 * 256, .y = 480 * 256 })) return error.WrongScaledPoint;
    }
    std.debug.print("wl_logic_test: surface points 6 cases, bs 1 = bs 2 4 cases\n", .{});

    // 포인터 포커스와 grab.
    {
        var p: logic.PointerFocus = .{};
        // 창 3 위로 — enter.
        if (!std.meta.eql(p.move(3), logic.PointerFocus.Move{ .enter = 3 })) return error.WrongPointer;
        if (!std.meta.eql(p.move(3), logic.PointerFocus.Move{ .motion = 3 })) return error.WrongPointer;
        // 누르고 창 밖(셸 위, under null)으로 끈다 — leave가 미뤄지고 움직임은 3으로.
        if (p.press() != 3) return error.WrongPointer;
        if (!std.meta.eql(p.move(null), logic.PointerFocus.Move{ .motion = 3 })) return error.WrongPointer;
        // 뗌은 3으로 가고, 그다음 move가 미룬 leave를 낸다.
        if (p.release() != 3) return error.WrongPointer;
        if (!std.meta.eql(p.move(null), logic.PointerFocus.Move{ .leave = 3 })) return error.WrongPointer;
        // 셸 위의 누름은 창에 안 간다.
        if (p.press() != null or p.release() != null) return error.WrongPointer;
        // 창 3에서 창 5로 곧장 — leave 3, enter 5.
        _ = p.move(3);
        if (!std.meta.eql(p.move(5), logic.PointerFocus.Move{ .leave = 3, .enter = 5 })) return error.WrongPointer;
        // 쥔 채 창이 사라지면 grab도 끝난다.
        _ = p.press();
        p.drop(5);
        if (p.focus != null or p.held != 0 or p.release() != null) return error.WrongPointer;
        if (!std.meta.eql(p.move(3), logic.PointerFocus.Move{ .enter = 3 })) return error.WrongPointer;
    }
    std.debug.print("wl_logic_test: pointer focus 13 cases\n", .{});

    // 휠 — 앞으로 한 눈금(위)은 -10, 아래로 둘은 +20.
    {
        if (!std.meta.eql(logic.axisFor(1), logic.Axis{ .value = -2560, .discrete = -1 })) return error.WrongAxis;
        if (!std.meta.eql(logic.axisFor(-2), logic.Axis{ .value = 5120, .discrete = 2 })) return error.WrongAxis;
    }
    std.debug.print("wl_logic_test: axis 2 cases\n", .{});

    // 클립보드(WY-M4) — 받을 mime 고르기(design 결정 34).
    {
        const Case = struct { offered: []const []const u8, want: ?[]const u8 };
        const cases = [_]Case{
            // SDL3 3.2.10이 텍스트를 내는 다섯(`SDL_waylandclipboard.c` text_mime_types) — 첫째가 이긴다.
            .{ .offered = &.{ "text/plain;charset=utf-8", "text/plain", "TEXT", "UTF8_STRING", "STRING" }, .want = "text/plain;charset=utf-8" },
            // 순서는 source가 아니라 우선순위가 정한다 — `UTF8_STRING`이 맨 `text/plain`보다 앞이다.
            .{ .offered = &.{ "TEXT", "text/plain", "UTF8_STRING" }, .want = "UTF8_STRING" },
            .{ .offered = &.{ "STRING", "text/plain" }, .want = "text/plain" },
            .{ .offered = &.{"TEXT"}, .want = "TEXT" },
            // 텍스트가 없다(이미지만) — 받지 않는다.
            .{ .offered = &.{ "image/png", "STRING" }, .want = null },
            .{ .offered = &.{}, .want = null },
            // 대소문자 · 띄어쓰기가 다른 이름은 다른 mime이다.
            .{ .offered = &.{"text/plain; charset=utf-8"}, .want = null },
        };
        for (cases) |cs| {
            const got = logic.pickMime(cs.offered);
            const ok = if (cs.want) |w| (got != null and std.mem.eql(u8, got.?, w)) else got == null;
            if (!ok) {
                std.debug.print("FAIL: pickMime({any}) = {?s}, want {?s}\n", .{ cs.offered, got, cs.want });
                return error.WrongMime;
            }
        }
        // 내는 넷은 전부 받을 수 있는 것이다(셸 → 앱 → 셸이 한 바퀴 돈다).
        for (logic.OFFER_MIMES) |m| {
            const one = [_][]const u8{m};
            if (logic.pickMime(&one) == null) return error.WrongMime;
        }
    }
    std.debug.print("wl_logic_test: mime pick 7 cases, offered 4 all pickable\n", .{});

    // 받아들이는 조건(design 결정 36).
    {
        var g: logic.SelectionGate = .{};
        // 포커스를 가져 본 적 없는 클라이언트는 안 된다.
        if (g.allows(1)) return error.WrongGate;
        g.focus(1);
        if (!g.allows(1) or g.allows(2)) return error.WrongGate;
        // 셸로 갔다(null) — 1은 여전히 가장 최근이다(`Cmd+C` 바로 뒤의 `Cmd+1`).
        g.focus(null);
        if (!g.allows(1)) return error.WrongGate;
        // 2가 포커스를 받으면 1은 더는 아니다.
        g.focus(2);
        if (g.allows(1) or !g.allows(2)) return error.WrongGate;
        // 끝난 클라이언트는 잊는다 — 다른 클라이언트의 forget은 영향이 없다.
        g.forget(1);
        if (!g.allows(2)) return error.WrongGate;
        g.forget(2);
        if (g.allows(2)) return error.WrongGate;
    }
    std.debug.print("wl_logic_test: selection gate 8 cases\n", .{});

    // 한도(design 결정 33) — 숫자를 여기 한 번 더 적어, 바꾸면 이 줄도 함께 고치게 한다.
    if (logic.SELECTION_MAX_BYTES != 1048576 or logic.SELECTION_TIMEOUT_MS != 2000) return error.WrongLimit;
    std.debug.print("wl_logic_test: selection limits 1 MiB 2000 ms\n", .{});

    // text_input 상태(WY-M5, design 결정 43).
    {
        var t: logic.TextInput = .{};
        // 들어가기 전의 enable · commit — 적용하지 않지만 commit은 센다(serial은 클라이언트가 보낸 commit 수).
        t.enable();
        t.commit();
        if (t.enabled or t.commits != 1) return error.WrongTextInput;
        // enter(surface 7) 뒤 enable + commit → 켜짐. 다른 surface에서는 켜진 것이 아니다.
        t.enter(7);
        if (t.activeOn(7)) return error.WrongTextInput;
        t.enable();
        if (t.activeOn(7)) return error.WrongTextInput; // commit 전에는 pending뿐
        t.commit();
        if (!t.activeOn(7) or t.activeOn(8) or t.activeOn(0) or t.commits != 2) return error.WrongTextInput;
        // enable 없는 commit은 current를 안 바꾼다.
        t.commit();
        if (!t.activeOn(7) or t.commits != 3) return error.WrongTextInput;
        // 연속 enable · disable — 마지막 것이 이긴다.
        t.enable();
        t.disable();
        t.commit();
        if (t.activeOn(7) or t.commits != 4) return error.WrongTextInput;
        t.disable();
        t.enable();
        t.enable();
        t.commit();
        if (!t.activeOn(7)) return error.WrongTextInput;
        // leave → 꺼짐. leave 뒤의 enable + commit은 무시되지만 센다.
        t.leave();
        if (t.activeOn(7)) return error.WrongTextInput;
        t.enable();
        t.commit();
        if (t.enabled or t.commits != 6) return error.WrongTextInput;
        // 다시 enter — 상태는 무효(pending도 버린다). enable 없이 commit하면 꺼진 채다.
        t.enable();
        t.enter(9);
        t.commit();
        if (t.activeOn(9) or t.commits != 7) return error.WrongTextInput;
        // 켜진 채로 다른 surface에 enter — 무효가 된다(SDL은 키보드 enter에 다시 enable한다).
        t.enable();
        t.commit();
        if (!t.activeOn(9)) return error.WrongTextInput;
        t.enter(11);
        if (t.activeOn(9) or t.activeOn(11)) return error.WrongTextInput;
        // 키보드 enter에 enable하는 클라이언트(SDL)도 받힌다 — 서버가 enter를 먼저 보냈으므로 요청이 올 때 entered가 서 있다.
        t.enable();
        t.commit();
        if (!t.activeOn(11) or t.commits != 9) return error.WrongTextInput;
    }
    std.debug.print("wl_logic_test: text_input 13 cases\n", .{});
    std.debug.print("wl_logic_test: all checks passed\n", .{});
}
