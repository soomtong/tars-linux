const std = @import("std");
const layout = @import("layout.zig");

const Rect = layout.Rect;

/// 1280x800 화면의 격자(`terminal: grid 155x47`). 홀수 폭 · 홀수 높이라
/// 가르면 양쪽이 같아지고, 짝수 쪽 검사는 따로 154를 쓴다.
const WHOLE: Rect = .{ .col = 0, .row = 0, .cols = 155, .rows = 47 };

/// 방향 넷(WP-M3). 배열이라 `inline for`의 `switch`가 빠짐없이 닫힌다.
const SIDES = [_]layout.Side{ .left, .right, .up, .down };

fn expectRect(what: []const u8, got: Rect, want: Rect) !void {
    if (std.meta.eql(got, want)) {
        std.debug.print("layout_test: {s} = {d},{d} {d}x{d} OK\n", .{
            what, got.col, got.row, got.cols, got.rows,
        });
        return;
    }
    std.debug.print("FAIL: {s} = {d},{d} {d}x{d}, want {d},{d} {d}x{d}\n", .{
        what,     got.col,  got.row,   got.cols,  got.rows,
        want.col, want.row, want.cols, want.rows,
    });
    return error.WrongRect;
}

fn expectLeaf(what: []const u8, got: ?u4, want: ?u4) !void {
    if (got == want) {
        std.debug.print("layout_test: {s} = {?d} OK\n", .{ what, got });
        return;
    }
    std.debug.print("FAIL: {s} = {?d}, want {?d}\n", .{ what, got, want });
    return error.WrongLeaf;
}

fn expectHit(what: []const u8, got: ?layout.Hit, want: ?layout.Hit) !void {
    if (std.meta.eql(got, want)) {
        if (got) |h| {
            std.debug.print("layout_test: hit {s} = leaf {d} at {d},{d} OK\n", .{ what, h.leaf, h.col, h.row });
        } else {
            std.debug.print("layout_test: hit {s} = none OK\n", .{what});
        }
        return;
    }
    std.debug.print("FAIL: hit {s} = {any}, want {any}\n", .{ what, got, want });
    return error.WrongHit;
}

fn expectCount(t: *const layout.Strip, want: usize) !void {
    if (t.count() == want) return;
    std.debug.print("FAIL: count = {d}, want {d}\n", .{ t.count(), want });
    return error.WrongCount;
}

/// 사각형이 덮는 칸마다 1을 더한다(검사 10).
fn paint(cover: *[47][155]u8, r: Rect) void {
    var y = r.row;
    while (y < r.row + r.rows) : (y += 1) {
        var x = r.col;
        while (x < r.col + r.cols) : (x += 1) cover[y][x] += 1;
    }
}

/// strip 산수의 검사. 부팅도 PTY도 프레임버퍼도 안 쓴다 — strip을 만들고
/// 사각형을 받는 순수 계산이다(WP design 결정 2, SW design 결정 1).
///
/// 검사 1~15는 WP의 트리 때 쓴 것이고, 트리에만 있던 것을 보던 검사 8 말고는
/// 단언이 그대로다(SW-M0 plan). 게이트가 쓰는
/// 세 모양(패널 하나 · `0 | 1` · `0 | (1 / 2)`)에서 strip이 트리와 같은 숫자를
/// 내는 것을 이 단언들이 본다. 16~19는 strip에서 새로 생긴 성질이다.
pub fn main() !void {
    var rs: [layout.MAX_LEAVES]Rect = undefined;

    // ── 검사 1: pane 하나의 사각형은 격자 전체다 ────────────────────
    //
    // WP-M0의 판정 전체가 이 한 줄에 기댄다. 패널 하나면 `rect`가 격자
    // 전체라 `main.zig`의 원점 산수가 지금과 같은 값을 낸다.
    {
        const t = layout.Strip.init();
        try expectCount(&t, 1);
        t.rects(WHOLE, &rs);
        try expectRect("one leaf", rs[0], WHOLE);
    }

    // ── 검사 2: 오른쪽 분할 — 두 폭의 합 + 구분선 1 = 격자 폭 ────────
    //
    // 155는 홀수라 구분선을 빼면 154이고 반씩 77이다. 154(짝수)는 153이
    // 남아 76 · 77이다 — 나머지가 오른쪽으로 간다.
    {
        var t = layout.Strip.init();
        try expectLeaf("split right", t.split(0, .right, WHOLE), 1);
        try expectCount(&t, 2);
        t.rects(WHOLE, &rs);
        try expectRect("left", rs[0], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("right", rs[1], .{ .col = 78, .row = 0, .cols = 77, .rows = 47 });
        if (rs[0].cols + rs[1].cols + 1 != WHOLE.cols) return error.WidthSum;

        const even: Rect = .{ .col = 0, .row = 0, .cols = 154, .rows = 47 };
        t.rects(even, &rs);
        try expectRect("even left", rs[0], .{ .col = 0, .row = 0, .cols = 76, .rows = 47 });
        try expectRect("even right", rs[1], .{ .col = 77, .row = 0, .cols = 77, .rows = 47 });
    }

    // ── 검사 3: 아래 분할 — 같은 산수가 줄에 ─────────────────────────
    {
        var t = layout.Strip.init();
        try expectLeaf("split below", t.split(0, .below, WHOLE), 1);
        t.rects(WHOLE, &rs);
        try expectRect("top", rs[0], .{ .col = 0, .row = 0, .cols = 155, .rows = 23 });
        try expectRect("bottom", rs[1], .{ .col = 0, .row = 24, .cols = 155, .rows = 23 });
        if (rs[0].rows + rs[1].rows + 1 != WHOLE.rows) return error.HeightSum;
    }

    // ── 검사 4: 셋을 가른 뒤 가운데를 지우면 같은 column이 그 자리를 채운다 ──
    //
    // 0 | (1 / 2). 순서로는 1이 가운데다. 1을 지우면 오른쪽 column에 2만
    // 남아 column 높이 전체 — 오른쪽 절반 전체 — 를 받는다. 0은 안 움직인다.
    {
        var t = layout.Strip.init();
        try expectLeaf("split 0 right", t.split(0, .right, WHOLE), 1);
        try expectLeaf("split 1 below", t.split(1, .below, WHOLE), 2);
        try expectLeaf("next(0)", t.next(0), 1);
        try expectLeaf("next(1)", t.next(1), 2);
        t.rects(WHOLE, &rs);
        try expectRect("right top", rs[1], .{ .col = 78, .row = 0, .cols = 77, .rows = 23 });
        try expectRect("right bottom", rs[2], .{ .col = 78, .row = 24, .cols = 77, .rows = 23 });

        t.remove(1);
        try expectCount(&t, 2);
        t.rects(WHOLE, &rs);
        try expectRect("left stays", rs[0], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("sibling rises", rs[2], .{ .col = 78, .row = 0, .cols = 77, .rows = 47 });
        try expectLeaf("next(0) after remove", t.next(0), 2);

        // 지운 번호는 다시 쓰인다 — 가장 작은 빈 번호다. `main.zig`의
        // 패널 배열 여덟 칸이 이 번호로 인덱싱되므로 9 이상이 나오면 안 된다.
        try expectLeaf("reuse freed leaf", t.split(0, .below, WHOLE), 1);
    }

    // ── 검사 5: 여덟 뒤 아홉째는 null, 보이는 사각형이 안 겹치고 격자 안이다 ──
    //
    // 방향을 번갈아 가르며 늘 가장 최근 pane을 가른다 — 크기 제한(검사 6)에
    // 안 걸리고 여덟까지 간다. strip에서는 column 다섯(`0` · `1/2` · `3/4` ·
    // `5/6` · `7`)이 된다. SW-M2부터 화면에는 column 둘만 보이므로(design 결정
    // 13 · 14) "격자 안 · 안 겹침"은 보이는 slot만 본다. `first`를 0부터 끝까지
    // 옮기며 본다. 화면 밖 slot은 크기만 뜻이 있다 — 반 폭 77, 높이가 0보다 크다.
    {
        var t = layout.Strip.init();
        var last: u4 = 0;
        var i: usize = 1;
        while (i < layout.MAX_LEAVES) : (i += 1) {
            const dir: layout.Dir = if (i % 2 == 1) .right else .below;
            last = t.split(last, dir, WHOLE) orelse {
                std.debug.print("FAIL: split #{d} returned null\n", .{i});
                return error.SplitFailed;
            };
        }
        try expectCount(&t, 8);
        try expectLeaf("ninth split", t.split(last, .right, WHOLE), null);
        try expectLeaf("ninth split of leaf 0", t.split(0, .below, WHOLE), null);
        try expectCount(&t, 8);

        var views: usize = 0;
        var first: u4 = 0;
        while (first + 1 < t.len) : (first += 1) {
            t.first = first;
            views += 1;
            // 칸마다 몇 개의 사각형이 덮는지 센다. 2 이상이면 겹친 것이고,
            // 격자 밖이면 인덱스가 넘친다.
            t.rects(WHOLE, &rs);
            var cover: [47][155]u8 = @splat(@splat(0));
            var area: usize = 0;
            for (rs, 0..) |r, li| {
                if (!t.visible(@intCast(li))) {
                    if (r.cols != 77 or r.rows == 0) {
                        std.debug.print("FAIL: off-screen slot {d} is {d}x{d}, want 77 wide\n", .{ li, r.cols, r.rows });
                        return error.OffscreenSize;
                    }
                    continue;
                }
                if (r.col + r.cols > WHOLE.cols or r.row + r.rows > WHOLE.rows or r.cols == 0 or r.rows == 0) {
                    std.debug.print("FAIL: rect {d},{d} {d}x{d} out of the grid\n", .{ r.col, r.row, r.cols, r.rows });
                    return error.RectOutside;
                }
                var y = r.row;
                while (y < r.row + r.rows) : (y += 1) {
                    var x = r.col;
                    while (x < r.col + r.cols) : (x += 1) {
                        cover[y][x] += 1;
                        if (cover[y][x] > 1) return error.RectOverlap;
                    }
                }
                area += @as(usize, r.cols) * r.rows;
            }
            // 구분선이 있으니 보이는 pane 넓이는 0보다 크고 격자보다 작다.
            if (area == 0 or area >= @as(usize, WHOLE.cols) * WHOLE.rows) return error.AreaSum;
        }
        if (views != 4) return error.WrongViewCount;
        std.debug.print("layout_test: 8 leaves in 5 columns, 4 views, visible ones inside and apart OK\n", .{});
    }

    // ── 검사 6: 가를 수 없을 만큼 작으면 null ────────────────────────
    //
    // 길이 3이 최소다 — 왼쪽 한 칸 · 구분선 · 오른쪽 한 칸. 2에서 가르면
    // 한쪽이 0칸이 되고 `vt.Screen.init`이 0x47 화면을 받는다.
    {
        const narrow: Rect = .{ .col = 0, .row = 0, .cols = 2, .rows = 2 };
        var t = layout.Strip.init();
        try expectLeaf("split right at 2 cols", t.split(0, .right, narrow), null);
        try expectLeaf("split below at 2 rows", t.split(0, .below, narrow), null);
        try expectCount(&t, 1);

        const three: Rect = .{ .col = 0, .row = 0, .cols = 3, .rows = 3 };
        try expectLeaf("split right at 3 cols", t.split(0, .right, three), 1);
        t.rects(three, &rs);
        try expectRect("3 cols left", rs[0], .{ .col = 0, .row = 0, .cols = 1, .rows = 3 });
        try expectRect("3 cols right", rs[1], .{ .col = 2, .row = 0, .cols = 1, .rows = 3 });
    }

    // ── 검사 7: next는 끝에서 처음으로, prev는 처음에서 끝으로 ────────
    //
    // 둘을 따로 본다. 하나만 보면 "감기지 않고 끝에 멈춘다"가 반대쪽에서
    // 통과한다.
    {
        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .right, WHOLE);
        try expectLeaf("next(last) wraps", t.next(2), 0);
        try expectLeaf("prev(first) wraps", t.prev(0), 2);
        try expectLeaf("prev(2)", t.prev(2), 1);

        const one = layout.Strip.init();
        try expectLeaf("next on one leaf", one.next(0), 0);
        try expectLeaf("prev on one leaf", one.prev(0), 0);
    }

    // ── 검사 8: 마지막 pane을 지우면 strip이 빈다 ─────────────────────
    //
    // WP design 결정 5의 "남은 패널이 없으면 나간다"가 이 성질을 본다.
    // 빈 strip은 `rects`가 아무 칸도 안 쓴다 — 미리 채운 표지가 그대로 남는다.
    {
        var t = layout.Strip.init();
        t.remove(0);
        try expectCount(&t, 0);
        const mark: Rect = .{ .col = 999, .row = 999, .cols = 999, .rows = 999 };
        var untouched: [layout.MAX_LEAVES]Rect = @splat(mark);
        t.rects(WHOLE, &untouched);
        for (untouched) |r| {
            if (!std.meta.eql(r, mark)) return error.RectsOnEmptyStrip;
        }
        std.debug.print("layout_test: last pane removed, count=0, rects writes nothing OK\n", .{});
    }

    // ── 검사 9: 구분선은 pane 수 − 1이다 (WP-M1) ─────────────────────────
    //
    // `cells()`가 빈 셀을 안 내보내므로 격자를 통째로 구분선 색으로 칠하고
    // 패널이 덮게 둘 수 없다(WP-M1 plan 확정 4). 그래서 구분선을 사각형으로
    // 따로 꺼낸다. 오른쪽 분할 하나면 77번 열 한 칸 폭, 높이 전체다. 순서는
    // column 순이고, 둘째 column의 세로선 다음에 그 column의 가로선이 온다.
    {
        var seps: [layout.MAX_LEAVES - 1]Rect = undefined;
        const one = layout.Strip.init();
        if (one.separators(WHOLE, &seps).len != 0) return error.SeparatorOnOneLeaf;

        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        const s1 = t.separators(WHOLE, &seps);
        if (s1.len != 1) return error.WrongSeparatorCount;
        try expectRect("separator", s1[0], .{ .col = 77, .row = 0, .cols = 1, .rows = 47 });

        // 오른쪽을 다시 아래로 가르면 둘. 둘째는 오른쪽 절반 안의 가로선이다.
        _ = t.split(1, .below, WHOLE);
        const s2 = t.separators(WHOLE, &seps);
        if (s2.len != 2) return error.WrongSeparatorCount;
        try expectRect("separator 2", s2[1], .{ .col = 78, .row = 23, .cols = 77, .rows = 1 });
    }

    // ── 검사 10: 보이는 패널 넓이 + 구분선 넓이 = 격자 넓이 ──────────────
    //
    // 검사 5는 "안 겹친다"만 봤다. 여기서 빈 칸이 없다는 것까지 본다 —
    // 구분선을 한 칸 어긋나게 그리면 패널과 겹치거나 틈이 생기고, 둘 다
    // 이 합이 어긋난다. pane 여덟 strip에서 `first`를 0부터 끝까지 옮기며, 보이는
    // pane과 구분선(보이는 pane 수 − 1, SW-M2 plan 확정 4)을 칸 단위로 칠해 모든
    // 칸이 정확히 한 번 덮이는지 본다.
    {
        var t = layout.Strip.init();
        var last: u4 = 0;
        var i: usize = 1;
        while (i < layout.MAX_LEAVES) : (i += 1) {
            const dir: layout.Dir = if (i % 2 == 1) .right else .below;
            last = t.split(last, dir, WHOLE) orelse return error.SplitFailed;
        }
        var first: u4 = 0;
        while (first + 1 < t.len) : (first += 1) {
            t.first = first;
            t.rects(WHOLE, &rs);
            var seps: [layout.MAX_LEAVES - 1]Rect = undefined;
            const ss = t.separators(WHOLE, &seps);
            var cover: [47][155]u8 = @splat(@splat(0));
            var shown: usize = 0;
            for (rs, 0..) |r, li| {
                if (!t.visible(@intCast(li))) continue;
                shown += 1;
                paint(&cover, r);
            }
            for (ss) |r| paint(&cover, r);
            if (ss.len != shown - 1) {
                std.debug.print("FAIL: first={d}: {d} separators for {d} visible panes\n", .{ first, ss.len, shown });
                return error.WrongSeparatorCount;
            }
            for (cover) |row| for (row) |n| {
                if (n != 1) {
                    std.debug.print("FAIL: first={d}: a cell is covered {d} time(s)\n", .{ first, n });
                    return error.CoverNotExact;
                }
            };
        }
        std.debug.print("layout_test: every view of 8 panes covers the grid exactly once OK\n", .{});
    }

    // ── 검사 11: 지운 pane의 포커스를 넘겨받는 pane (WP-M2) ───────────────
    //
    // 닫은 뒤 포커스는 화면에서 커지는 쪽으로 간다(WP-M1 실측 6, 사용자가
    // 2026-10-03에 골랐다. strip의 규칙은 SW design 결정 9). 0 | (1 / 2)에서
    // 2를 닫으면 같은 column의 위 pane 1이 받는다 — 순회의 다음(0으로
    // 감긴다)이 아니다. 둘을 가르는 것이 이 검사다. 갈래 넷은 검사 19가 본다.
    {
        var t = layout.Strip.init();
        try expectLeaf("heir on one leaf", t.heir(0), 0);
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .below, WHOLE);
        try expectLeaf("heir(2) is its sibling above", t.heir(2), 1);
        try expectLeaf("heir(1) is its sibling below", t.heir(1), 2);
        // 0은 column에 혼자라 column이 빈다. 왼쪽 column이 없으니 오른쪽
        // column에서 0의 맨 위 줄을 덮는 pane(첫 pane)이 받는다.
        try expectLeaf("heir(0) is the first leaf of the right half", t.heir(0), 1);
        // 순회의 next와 갈리는 자리를 직접 본다.
        try expectLeaf("next(2) wraps instead", t.next(2), 0);
    }

    // ── 검사 12: 격자 칸 → pane (PD-M1) ────────────────────────────────
    //
    // 포인터 아래 패널을 고르는 자리다(PD design 결정 5). 0 | (1 / 2)에서
    // 각 pane의 네 모서리 칸이 그 pane의 상대 칸 네 모서리가 되고, 구분선 칸과
    // 격자 밖은 null이다. 왼쪽은 0,0 77x47, 세로 구분선이 77열, 오른쪽 위가
    // 78,0 77x23, 가로 구분선이 23줄, 오른쪽 아래가 78,24 77x23이다(검사 9).
    {
        const one = layout.Strip.init();
        try expectHit("one leaf, top left", one.hit(WHOLE, 0, 0), .{ .leaf = 0, .col = 0, .row = 0 });
        try expectHit("one leaf, bottom right", one.hit(WHOLE, 154, 46), .{ .leaf = 0, .col = 154, .row = 46 });
        try expectHit("one leaf, past the right edge", one.hit(WHOLE, 155, 0), null);
        try expectHit("one leaf, past the bottom", one.hit(WHOLE, 0, 47), null);

        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .below, WHOLE);
        // 왼쪽 pane 0의 네 모서리.
        try expectHit("leaf 0 top left", t.hit(WHOLE, 0, 0), .{ .leaf = 0, .col = 0, .row = 0 });
        try expectHit("leaf 0 top right", t.hit(WHOLE, 76, 0), .{ .leaf = 0, .col = 76, .row = 0 });
        try expectHit("leaf 0 bottom left", t.hit(WHOLE, 0, 46), .{ .leaf = 0, .col = 0, .row = 46 });
        try expectHit("leaf 0 bottom right", t.hit(WHOLE, 76, 46), .{ .leaf = 0, .col = 76, .row = 46 });
        // 오른쪽 위 pane 1의 네 모서리.
        try expectHit("leaf 1 top left", t.hit(WHOLE, 78, 0), .{ .leaf = 1, .col = 0, .row = 0 });
        try expectHit("leaf 1 top right", t.hit(WHOLE, 154, 0), .{ .leaf = 1, .col = 76, .row = 0 });
        try expectHit("leaf 1 bottom left", t.hit(WHOLE, 78, 22), .{ .leaf = 1, .col = 0, .row = 22 });
        try expectHit("leaf 1 bottom right", t.hit(WHOLE, 154, 22), .{ .leaf = 1, .col = 76, .row = 22 });
        // 오른쪽 아래 pane 2의 네 모서리.
        try expectHit("leaf 2 top left", t.hit(WHOLE, 78, 24), .{ .leaf = 2, .col = 0, .row = 0 });
        try expectHit("leaf 2 top right", t.hit(WHOLE, 154, 24), .{ .leaf = 2, .col = 76, .row = 0 });
        try expectHit("leaf 2 bottom left", t.hit(WHOLE, 78, 46), .{ .leaf = 2, .col = 0, .row = 22 });
        try expectHit("leaf 2 bottom right", t.hit(WHOLE, 154, 46), .{ .leaf = 2, .col = 76, .row = 22 });
        // 구분선 칸.
        try expectHit("vertical separator, top", t.hit(WHOLE, 77, 0), null);
        try expectHit("vertical separator, bottom", t.hit(WHOLE, 77, 46), null);
        try expectHit("horizontal separator, left end", t.hit(WHOLE, 78, 23), null);
        try expectHit("horizontal separator, right end", t.hit(WHOLE, 154, 23), null);
        // 격자 밖.
        try expectHit("past the right edge", t.hit(WHOLE, 155, 10), null);
        try expectHit("past the bottom", t.hit(WHOLE, 10, 47), null);
    }

    // ── 검사 13: 끄는 칸을 누른 패널 안으로 붙인다 (PD-M2) ────────────────
    //
    // 끄는 동안 선택 끝이 이웃 패널로 넘어가지 않는 자리다(PD design 결정 5).
    // 0 | 1에서 왼쪽은 0,0 77x47, 오른쪽은 78,0 77x47이다. 안의 칸은 `hit`과
    // 같은 상대 칸이 되고, 밖의 칸은 가장 가까운 가장자리 칸이 된다. 구분선
    // 칸(77열)은 왼쪽 pane에서는 마지막 열, 오른쪽 pane에서는 첫 열이다.
    {
        const left: Rect = .{ .col = 0, .row = 0, .cols = 77, .rows = 47 };
        const right: Rect = .{ .col = 78, .row = 0, .cols = 77, .rows = 47 };
        try expectHit("clamp inside the left leaf", layout.clampInto(left, 0, 10, 5), .{ .leaf = 0, .col = 10, .row = 5 });
        try expectHit("clamp the separator into the left leaf", layout.clampInto(left, 0, 77, 5), .{ .leaf = 0, .col = 76, .row = 5 });
        try expectHit("clamp the right leaf into the left leaf", layout.clampInto(left, 0, 120, 5), .{ .leaf = 0, .col = 76, .row = 5 });
        try expectHit("clamp past the bottom into the left leaf", layout.clampInto(left, 0, 3, 60), .{ .leaf = 0, .col = 3, .row = 46 });
        try expectHit("clamp the separator into the right leaf", layout.clampInto(right, 1, 77, 5), .{ .leaf = 1, .col = 0, .row = 5 });
        try expectHit("clamp the left leaf into the right leaf", layout.clampInto(right, 1, 10, 0), .{ .leaf = 1, .col = 0, .row = 0 });
        try expectHit("clamp inside the right leaf", layout.clampInto(right, 1, 154, 46), .{ .leaf = 1, .col = 76, .row = 46 });
        // 가로 분할의 아래 pane(78,24 77x23, 검사 12). 위로 끌어 나가면 첫 줄이다.
        const lower: Rect = .{ .col = 78, .row = 24, .cols = 77, .rows = 23 };
        try expectHit("clamp above the lower leaf", layout.clampInto(lower, 2, 100, 3), .{ .leaf = 2, .col = 22, .row = 0 });
    }

    // ── 검사 14: 방향의 이웃 (WP-M3) ───────────────────────────────────
    //
    // 0 | (1 / 2)에서 모든 pane · 모든 방향(검사 12와 같은 사각형). 0의 →가
    // 이 검사의 중심이다 — 1과 2가 둘 다 0의 오른쪽 변과 마주 보고, 변의
    // 시작점(맨 위 줄)과 마주 보는 1이 이긴다(사용자 결정, 2026-10-26).
    // 끝에서는 감기지 않는다 — 감기는 이동은 순환의 몫이다.
    {
        const one = layout.Strip.init();
        inline for (SIDES) |side| {
            try expectLeaf("one leaf has no neighbor " ++ @tagName(side), one.neighbor(WHOLE, 0, side), null);
        }

        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .below, WHOLE);
        try expectLeaf("0 right is the top of the two (1, not 2)", t.neighbor(WHOLE, 0, .right), 1);
        try expectLeaf("1 left is 0", t.neighbor(WHOLE, 1, .left), 0);
        try expectLeaf("2 left is 0", t.neighbor(WHOLE, 2, .left), 0);
        try expectLeaf("1 down is 2", t.neighbor(WHOLE, 1, .down), 2);
        try expectLeaf("2 up is 1", t.neighbor(WHOLE, 2, .up), 1);
        try expectLeaf("0 left is the edge", t.neighbor(WHOLE, 0, .left), null);
        try expectLeaf("0 up is the edge", t.neighbor(WHOLE, 0, .up), null);
        try expectLeaf("0 down is the edge", t.neighbor(WHOLE, 0, .down), null);
        try expectLeaf("1 right is the edge", t.neighbor(WHOLE, 1, .right), null);
        try expectLeaf("1 up is the edge", t.neighbor(WHOLE, 1, .up), null);
        try expectLeaf("2 right is the edge", t.neighbor(WHOLE, 2, .right), null);
        try expectLeaf("2 down is the edge", t.neighbor(WHOLE, 2, .down), null);
        try expectLeaf("a leaf not in the tree", t.neighbor(WHOLE, 5, .left), null);
    }

    // ── 검사 15: 이웃은 변의 시작점과 마주 본다 (WP-M3) ─────────────────
    //
    // WP 트리의 `neighbor`는 구분선 한 칸을 건너뛴 칸을 `hit`에 물었고, 이
    // 검사는 그 칸이 구분선에 안 떨어지는 것을 봤다(WP-M3 plan 확정 2). strip은
    // 목록으로 고르지만 성질은 같아야 한다. 47줄 · 46줄 격자에서 옆 column의
    // 구분선 줄에 시작 줄이 떨어지는 조합은 column당 셋에서 나오지 않아 여기서는
    // 늘 마주 보는 pane이 맨 위 줄을 덮는다. 떨어지는 경우는 검사 18이 따로 본다.
    // 분할 모양 256가지 × 격자 둘(홀수 · 짝수)을 pane 여덟까지 쌓으며 매 단계
    // 모든 pane · 모든 방향에서 둘을 본다. column당 셋(SW-M1)에 걸린 `.below`는
    // `_ =`로 넘어가므로 여덟에 못 미치는 모양도 있다(SW-M1 plan 확정 4).
    //
    // SW-M2부터 화면 밖 column이 있어 끝과 옆을 사각형이 아니라 순번으로 본다
    // (SW-M2 plan). 분할마다 새 pane을 `reveal`해 `main.zig`처럼 viewport를 옮긴다.
    //   1. null이면 그 변이 끝이고, 끝이면 null이다. ←는 첫 column, →는 끝
    //      column, ↑ ↓는 column 안의 처음 · 끝이다.
    //   2. null이 아니면 ← →는 순번 ±1인 column의 pane이고 포커스의 맨 위 줄을
    //      덮는다. ↑ ↓는 같은 column에서 구분선 한 칸 건너편에서 시작한다.
    {
        const grids = [_]Rect{ WHOLE, .{ .col = 0, .row = 0, .cols = 154, .rows = 46 } };
        var asked: usize = 0;
        for (grids) |whole| {
            for (0..256) |p| {
                var t = layout.Strip.init();
                for (0..layout.MAX_LEAVES - 1) |k| {
                    const dir: layout.Dir = if ((p >> @intCast(k)) & 1 == 1) .right else .below;
                    // 지운 적이 없으니 slot 번호는 0..count-1로 빈틈이 없다.
                    const target: u4 = @intCast((p * 7 + k * 3) % t.count());
                    if (t.split(target, dir, whole)) |new| _ = t.reveal(new);
                    var at: [layout.MAX_LEAVES]Rect = undefined;
                    t.rects(whole, &at);
                    for (0..t.count()) |li| {
                        const leaf: u4 = @intCast(li);
                        const f = at[leaf];
                        const fc = t.columnOf(leaf).?;
                        inline for (SIDES) |side| {
                            asked += 1;
                            const edge = switch (side) {
                                .left => fc.col == 0,
                                .right => fc.col + 1 == fc.cols,
                                .up => f.row == whole.row,
                                .down => f.row + f.rows == whole.row + whole.rows,
                            };
                            const got = t.neighbor(whole, leaf, side);
                            if ((got == null) != edge) {
                                std.debug.print("FAIL: grid {d}x{d} shape {d} step {d} leaf {d} {s}: got {?d}, edge={}\n", .{
                                    whole.cols, whole.rows, p, k, leaf, @tagName(side), got, edge,
                                });
                                return error.NeighborOnSeparator;
                            }
                            if (got) |n| {
                                const r = at[n];
                                const nc = t.columnOf(n).?.col;
                                const ok = switch (side) {
                                    .left => nc + 1 == fc.col and r.row <= f.row and f.row < r.row + r.rows,
                                    .right => nc == fc.col + 1 and r.row <= f.row and f.row < r.row + r.rows,
                                    .up => nc == fc.col and r.row + r.rows + 1 == f.row,
                                    .down => nc == fc.col and r.row == f.row + f.rows + 1,
                                };
                                if (!ok) {
                                    std.debug.print("FAIL: grid {d}x{d} shape {d} step {d} leaf {d} {s} -> {d} does not face the edge's start\n", .{
                                        whole.cols, whole.rows, p, k, leaf, @tagName(side), n,
                                    });
                                    return error.NeighborNotFacing;
                                }
                            }
                        }
                    }
                }
            }
        }
        std.debug.print("layout_test: {d} neighbor answers are the edge or the leaf facing its start OK\n", .{asked});
    }

    // ── 검사 16: column 셋부터는 반 폭이고, 줄은 고르게 나눈다 (SW design 결정 4 · 13) ──
    //
    // M0 · M1은 column 셋을 51 · 51 · 51로 고르게 나눴다. SW-M2부터 column이 둘이면
    // 반씩(155에서 77 · 77, 154에서 76 · 77), 셋 이상이면 모두 왼쪽 반의 폭이고(155에서
    // 77, 154에서 76 — 오른쪽 끝 한 칸은 빈다) 화면에는 둘이 보인다. 셋째는 화면 밖에
    // 서고, `reveal`하면 viewport가 한 column 옮겨 둘째 · 셋째가 보인다. 줄 쪽은 그대로다 — 47에서 둘을 빼면 45, 셋으로 15씩,
    // 46은 나머지가 2라 뒤의 둘이 한 칸씩 더 받는다(14 · 15 · 15).
    {
        var t = layout.Strip.init();
        try expectLeaf("second column", t.split(0, .right, WHOLE), 1);
        try expectLeaf("third column", t.split(1, .right, WHOLE), 2);
        t.rects(WHOLE, &rs);
        try expectRect("half column 0", rs[0], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("half column 1", rs[1], .{ .col = 78, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("off-screen column 2", rs[2], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        if (t.visible(2) or !t.visible(0) or !t.visible(1)) return error.WrongVisible;
        if (!t.reveal(2)) return error.RevealDidNotMove;
        t.rects(WHOLE, &rs);
        try expectRect("revealed: column 1 on the left", rs[1], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("revealed: column 2 on the right", rs[2], .{ .col = 78, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("revealed: column 0 off-screen", rs[0], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        if (t.visible(0) or !t.visible(1) or !t.visible(2)) return error.WrongVisible;
        const narrow: Rect = .{ .col = 0, .row = 0, .cols = 154, .rows = 46 };
        t.rects(narrow, &rs);
        try expectRect("154 column 1 on the left", rs[1], .{ .col = 0, .row = 0, .cols = 76, .rows = 46 });
        try expectRect("154 column 2 on the right", rs[2], .{ .col = 77, .row = 0, .cols = 76, .rows = 46 });
        try expectRect("154 column 0 off-screen on the left", rs[0], .{ .col = 0, .row = 0, .cols = 76, .rows = 46 });

        var s = layout.Strip.init();
        try expectLeaf("second in the column", s.split(0, .below, WHOLE), 1);
        try expectLeaf("third in the column", s.split(1, .below, WHOLE), 2);
        s.rects(WHOLE, &rs);
        try expectRect("even pane 0", rs[0], .{ .col = 0, .row = 0, .cols = 155, .rows = 15 });
        try expectRect("even pane 1", rs[1], .{ .col = 0, .row = 16, .cols = 155, .rows = 15 });
        try expectRect("even pane 2", rs[2], .{ .col = 0, .row = 32, .cols = 155, .rows = 15 });
        s.rects(narrow, &rs);
        try expectRect("46 pane 0", rs[0], .{ .col = 0, .row = 0, .cols = 154, .rows = 14 });
        try expectRect("46 pane 1", rs[1], .{ .col = 0, .row = 15, .cols = 154, .rows = 15 });
        try expectRect("46 pane 2", rs[2], .{ .col = 0, .row = 31, .cols = 154, .rows = 15 });

        // `.right`는 보이는 column 수(많아야 둘)로 판정한다(SW-M2 plan 확정 5).
        // 4칸이면 둘째가 서고(3 이상) 셋째도 선다 — 화면 밖에 서므로 폭이 안 준다.
        // 2칸이면 둘째부터 null이다. 줄 쪽은 셋째가 5줄을 바란다.
        const four: Rect = .{ .col = 0, .row = 0, .cols = 4, .rows = 4 };
        var u = layout.Strip.init();
        try expectLeaf("second column at 4 cols", u.split(0, .right, four), 1);
        try expectLeaf("third column at 4 cols", u.split(1, .right, four), 2);
        try expectLeaf("second pane at 4 rows", u.split(1, .below, four), 3);
        try expectLeaf("third pane at 4 rows", u.split(3, .below, four), null);
        const two: Rect = .{ .col = 0, .row = 0, .cols = 2, .rows = 2 };
        var v = layout.Strip.init();
        try expectLeaf("second column at 2 cols", v.split(0, .right, two), null);
    }

    // ── 검사 17: slot 번호는 안 바뀌고, 같은 배치는 같은 값이다 (R-SW-7) ──
    //
    // `main.zig`의 패널 배열이 slot 번호로 인덱싱되므로 다른 pane을 지워도
    // 번호가 그대로여야 한다. 그리고 `last_strip`과 `std.meta.eql`로 견주므로
    // 같은 배치를 다른 순서로 만든 두 strip이 같은 값이어야 한다 — 빼고 당긴
    // 뒤 비는 끝 칸이 0으로 돌아오지 않으면 여기서 갈린다(SW-M0 plan 확정 1).
    {
        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .right, WHOLE);
        t.remove(1);
        t.rects(WHOLE, &rs);
        try expectRect("slot 0 after the middle column goes", rs[0], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("slot 2 after the middle column goes", rs[2], .{ .col = 78, .row = 0, .cols = 77, .rows = 47 });
        try expectLeaf("next(0) is 2", t.next(0), 2);
        try expectLeaf("freed slot comes back", t.split(0, .right, WHOLE), 1);

        var fresh = layout.Strip.init();
        _ = fresh.split(0, .right, WHOLE);
        _ = fresh.split(1, .right, WHOLE);
        if (!std.meta.eql(t, fresh)) return error.SameLayoutDiffers;

        // column을 뺀 두 길: 가운데를 빼고 당기기(a), 끝을 빼기(b).
        // a: [0] [1] [2]에서 1을 빼면 [0] [2]. b: [0] [2] [1]에서 1을 빼면 [0] [2].
        var a = layout.Strip.init();
        _ = a.split(0, .right, WHOLE);
        _ = a.split(1, .right, WHOLE);
        a.remove(1);
        var b = layout.Strip.init();
        _ = b.split(0, .right, WHOLE);
        try expectLeaf("column after 0", b.split(0, .right, WHOLE), 2);
        b.remove(1);
        if (!std.meta.eql(a, b)) return error.PulledColumnNotCleared;

        // column 안에서 같은 두 길: [0 / 1 / 2]에서 1을 빼기, [0 / 2 / 1]에서 1을 빼기.
        var c = layout.Strip.init();
        _ = c.split(0, .below, WHOLE);
        _ = c.split(1, .below, WHOLE);
        c.remove(1);
        var d = layout.Strip.init();
        _ = d.split(0, .below, WHOLE);
        try expectLeaf("pane below 0", d.split(0, .below, WHOLE), 2);
        d.remove(1);
        if (!std.meta.eql(c, d)) return error.PulledSlotNotCleared;

        // 모두 지우고 다시 하나로 돌아오면 `init`과 같은 값이다.
        c.remove(2);
        if (!std.meta.eql(c, layout.Strip.init())) return error.ShrunkStripDiffers;
        std.debug.print("layout_test: slots keep their numbers, equal layouts are equal values OK\n", .{});
    }

    // ── 검사 18: 마주 보는 줄이 옆 column의 구분선일 때 (SW design 결정 8) ──
    //
    // column마다 높이를 따로 나누므로 한쪽의 시작 줄이 옆 column의 가로
    // 구분선일 수 있다. column당 셋(SW-M1)이면 그런 격자는 5~9줄뿐이라(SW-M1
    // plan 확정 3) 8줄 격자로 본다. 왼쪽 column pane 둘(7을 둘로 3 · 4, 시작
    // 0 · 4, 구분선 3)과 오른쪽 column pane 셋(6을 셋으로 2 · 2 · 2, 시작 0 · 3 ·
    // 6)이면 오른쪽 둘째가 3줄에서 시작한다. 그 ←는 구분선 바로 위의 왼쪽 첫
    // pane이다. 왼쪽 둘째(시작 4)의 →는 4줄을 덮는 오른쪽 둘째다.
    {
        const whole: Rect = .{ .col = 0, .row = 0, .cols = 155, .rows = 8 };
        var t = layout.Strip.init();
        try expectLeaf("right column", t.split(0, .right, whole), 1);
        try expectLeaf("left second", t.split(0, .below, whole), 2);
        try expectLeaf("right second", t.split(1, .below, whole), 3);
        try expectLeaf("right third", t.split(3, .below, whole), 4);
        t.rects(whole, &rs);
        try expectRect("left first", rs[0], .{ .col = 0, .row = 0, .cols = 77, .rows = 3 });
        try expectRect("left second", rs[2], .{ .col = 0, .row = 4, .cols = 77, .rows = 4 });
        try expectRect("right first", rs[1], .{ .col = 78, .row = 0, .cols = 77, .rows = 2 });
        try expectRect("right second", rs[3], .{ .col = 78, .row = 3, .cols = 77, .rows = 2 });
        try expectRect("right third", rs[4], .{ .col = 78, .row = 6, .cols = 77, .rows = 2 });
        try expectHit("row 3 of the left column is the separator", t.hit(whole, 10, 3), null);
        try expectLeaf("right second left is above the separator", t.neighbor(whole, 3, .left), 0);
        try expectLeaf("left second right is the right second", t.neighbor(whole, 2, .right), 3);
        try expectLeaf("right third left is the left second", t.neighbor(whole, 4, .left), 2);
        try expectLeaf("left first right is the right first", t.neighbor(whole, 0, .right), 1);
    }

    // ── 검사 19: heir의 갈래 넷 (SW design 결정 9) ────────────────────────
    //
    // 같은 column의 위, 없으면 아래. column에 혼자면 column이 비므로 왼쪽
    // column, 없으면 오른쪽 column의 pane이다. `[0 / 2] | [1] | [3]`에서 본다.
    {
        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        try expectLeaf("pane below 0", t.split(0, .below, WHOLE), 2);
        try expectLeaf("column after 1", t.split(1, .right, WHOLE), 3);
        try expectLeaf("heir in the same column, above", t.heir(2), 0);
        try expectLeaf("heir in the same column, below", t.heir(0), 2);
        try expectLeaf("heir of a lone pane is in the left column", t.heir(1), 0);
        try expectLeaf("heir of the last lone pane is in the left column", t.heir(3), 1);
        var s = layout.Strip.init();
        _ = s.split(0, .right, WHOLE);
        _ = s.split(1, .below, WHOLE);
        try expectLeaf("heir of the leftmost lone pane is in the right column", s.heir(0), 1);
    }

    // ── 검사 20: column당 셋 (SW-M1, SW design 결정 12) ──────────────────
    //
    // 한 column에 셋이면 넷째 `.below`는 null이고 아무것도 안 바뀐다 — pane 수도
    // 사각형도 그대로다. 한도는 column마다라 다른 column의 `.below`는 되고,
    // `.right`는 한도와 무관하다(새 column은 pane 하나로 선다).
    {
        var t = layout.Strip.init();
        _ = t.split(0, .below, WHOLE);
        _ = t.split(1, .below, WHOLE);
        try expectCount(&t, 3);
        var before: [layout.MAX_LEAVES]Rect = undefined;
        t.rects(WHOLE, &before);
        try expectLeaf("fourth below the last of three", t.split(2, .below, WHOLE), null);
        try expectLeaf("fourth below the first of three", t.split(0, .below, WHOLE), null);
        try expectCount(&t, 3);
        t.rects(WHOLE, &rs);
        for (0..3) |k| {
            if (!std.meta.eql(rs[k], before[k])) return error.RefusedSplitMoved;
        }
        try expectRect("still 15 rows after the refusal", rs[2], .{ .col = 0, .row = 32, .cols = 155, .rows = 15 });
        try expectLeaf("right is not limited", t.split(1, .right, WHOLE), 3);
        try expectLeaf("below in the other column", t.split(3, .below, WHOLE), 4);
        try expectLeaf("third in the other column", t.split(4, .below, WHOLE), 5);
        try expectLeaf("fourth in the other column", t.split(3, .below, WHOLE), null);
        try expectCount(&t, 6);
    }

    // ── 검사 21: reveal은 가장 적게 옮기고 포커스를 보이게 한다 (SW design 결정 14) ──
    //
    // column 넷 `[0] [1] [2] [3]`에서 `first`가 될 수 있는 값은 0 · 1 · 2다. 모든
    // 시작 `first`와 모든 대상 column에서, `reveal` 뒤 대상이 보이고, 새 `first`는
    // 대상을 보이게 하는 값들 가운데 옛 값에 가장 가깝고, 옮겼을 때만 true다.
    // 기대값은 `layout.zig`의 산수가 아니라 후보를 모두 훑어 고른다.
    {
        var pairs: usize = 0;
        for (0..3) |start| {
            for (0..4) |target| {
                var t = layout.Strip.init();
                _ = t.split(0, .right, WHOLE);
                _ = t.split(1, .right, WHOLE);
                _ = t.split(2, .right, WHOLE);
                t.first = @intCast(start);
                var want: usize = start;
                var best: usize = 99;
                for (0..3) |f| {
                    if (target < f or target > f + 1) continue;
                    const d = if (f > start) f - start else start - f;
                    if (d < best) {
                        best = d;
                        want = f;
                    }
                }
                const moved = t.reveal(@intCast(target));
                if (t.first != want or moved != (want != start) or !t.visible(@intCast(target))) {
                    std.debug.print("FAIL: reveal({d}) from first={d}: first={d} moved={}, want first={d}\n", .{ target, start, t.first, moved, want });
                    return error.RevealNotMinimal;
                }
                pairs += 1;
            }
        }
        // 한 걸음씩 오른쪽 끝까지, 그리고 왼쪽 끝까지 — 포커스를 옆으로 옮길 때의 모양.
        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .right, WHOLE);
        _ = t.split(2, .right, WHOLE);
        const walk = [_]struct { leaf: u4, moved: bool, first: u4 }{
            .{ .leaf = 1, .moved = false, .first = 0 }, .{ .leaf = 2, .moved = true, .first = 1 },
            .{ .leaf = 3, .moved = true, .first = 2 },  .{ .leaf = 2, .moved = false, .first = 2 },
            .{ .leaf = 1, .moved = true, .first = 1 },  .{ .leaf = 0, .moved = true, .first = 0 },
        };
        for (walk) |w| {
            if (t.reveal(w.leaf) != w.moved or t.first != w.first) return error.RevealWalk;
        }
        if (t.reveal(9)) return error.RevealMissingSlot;
        const v = t.view();
        if (v.first != 0 or v.last != 1) return error.WrongView;
        std.debug.print("layout_test: reveal moves the least in all {d} cases and on a walk OK\n", .{pairs});
    }

    // ── 검사 22: remove는 first를 범위 안으로 당긴다 (SW-M2 plan 확정 2) ────
    //
    // column 넷에서 `first = 2`(셋째 · 넷째가 보인다). 끝 column을 지우면 셋이
    // 남고 `first`는 1이 된다 — 1보다 크면 오른쪽에 빈 반이 생긴다. 둘이 남으면
    // 0, 하나면 그 column이 격자 전체 폭이다(pane 체인 검사 9a의 `155x47`).
    {
        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .right, WHOLE);
        _ = t.split(2, .right, WHOLE);
        _ = t.reveal(3);
        if (t.first != 2) return error.RevealFailed;
        t.remove(3);
        if (t.first != 1) return error.FirstNotPulled;
        const v = t.view();
        if (v.first != 1 or v.last != 2) return error.WrongView;
        t.remove(2);
        if (t.first != 0) return error.FirstNotPulled;
        t.remove(1);
        if (t.first != 0) return error.FirstNotPulled;
        t.rects(WHOLE, &rs);
        try expectRect("one column left is the whole grid", rs[0], WHOLE);
        const one = t.view();
        if (one.first != 0 or one.last != 0) return error.WrongView;
        if (!std.meta.eql(t, layout.Strip.init())) return error.ShrunkStripDiffers;
        std.debug.print("layout_test: remove pulls first back in range OK\n", .{});
    }

    // ── 검사 23: scroll은 크기를 안 바꾼다 (SW design 결정 15) ─────────────
    //
    // `[0] [1 / 4] [2] [3]`에서 `reveal(3)`으로 viewport를 오른쪽 끝까지 옮긴다.
    // 모든 slot의 `cols` · `rows`가 그대로다 — `main.zig`의 `applyLayout`이 크기가
    // 다를 때만 셸을 resize하므로, 화면 밖 셸은 scroll로 SIGWINCH를 안 받는다.
    // 바뀌는 것은 보이는 slot의 위치다. column 셋 이상은 보이든 안 보이든 모두
    // 왼쪽 반의 폭이라(`colSpan`) 홀수 155 · 짝수 154 어느 격자에서도 그렇다 — 두
    // 격자에서 `first`를 0 → 1 → 2 → 1 → 0으로 옮기며 매번 견준다. 154에서는 오른쪽
    // 보이는 column이 77에서 76칸에 서고 오른쪽 끝 한 칸(153열)이 빈다.
    {
        const narrow: Rect = .{ .col = 0, .row = 0, .cols = 154, .rows = 46 };
        for ([_]Rect{ WHOLE, narrow }) |whole| {
            var g = layout.Strip.init();
            _ = g.split(0, .right, whole);
            _ = g.split(1, .right, whole);
            _ = g.split(2, .right, whole);
            _ = g.split(1, .below, whole);
            var base: [layout.MAX_LEAVES]Rect = undefined;
            g.rects(whole, &base);
            for ([_]u4{ 2, 3, 2, 1, 0 }) |target| {
                _ = g.reveal(target);
                var now: [layout.MAX_LEAVES]Rect = undefined;
                g.rects(whole, &now);
                for (0..5) |li| {
                    if (base[li].cols != now[li].cols or base[li].rows != now[li].rows) {
                        std.debug.print("FAIL: grid {d}x{d}: slot {d} changed size on reveal({d})\n", .{ whole.cols, whole.rows, li, target });
                        return error.ScrollResized;
                    }
                }
            }
        }
        var n = layout.Strip.init();
        _ = n.split(0, .right, narrow);
        _ = n.split(1, .right, narrow);
        _ = n.reveal(2);
        n.rects(narrow, &rs);
        try expectRect("154: left visible column", rs[1], .{ .col = 0, .row = 0, .cols = 76, .rows = 46 });
        try expectRect("154: right visible column leaves the last cell empty", rs[2], .{ .col = 77, .row = 0, .cols = 76, .rows = 46 });

        var t = layout.Strip.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .right, WHOLE);
        _ = t.split(2, .right, WHOLE);
        try expectLeaf("pane below 1", t.split(1, .below, WHOLE), 4);
        var before: [layout.MAX_LEAVES]Rect = undefined;
        t.rects(WHOLE, &before);
        if (!t.reveal(3)) return error.RevealDidNotMove;
        var after: [layout.MAX_LEAVES]Rect = undefined;
        t.rects(WHOLE, &after);
        try expectRect("slot 1 was on the right", before[1], .{ .col = 78, .row = 0, .cols = 77, .rows = 23 });
        try expectRect("slot 2 now on the left", after[2], .{ .col = 0, .row = 0, .cols = 77, .rows = 47 });
        try expectRect("slot 3 now on the right", after[3], .{ .col = 78, .row = 0, .cols = 77, .rows = 47 });
        if (t.visible(0) or t.visible(1) or t.visible(4) or !t.visible(2) or !t.visible(3)) return error.WrongVisible;
        try expectHit("an off-screen slot is never hit", t.hit(WHOLE, 10, 30), .{ .leaf = 2, .col = 10, .row = 30 });
        std.debug.print("layout_test: scrolling keeps every size, only the visible ones move OK\n", .{});
    }

    std.debug.print("layout_test: all checks passed\n", .{});
}
