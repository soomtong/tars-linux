const std = @import("std");
const layout = @import("layout.zig");

const Rect = layout.Rect;

/// 1280x800 화면의 격자(`terminal: grid 155x47`). 홀수 폭 · 홀수 높이라
/// 가르면 양쪽이 같아지고, 짝수 쪽 검사는 따로 154를 쓴다.
const WHOLE: Rect = .{ .col = 0, .row = 0, .cols = 155, .rows = 47 };

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

fn expectCount(t: *const layout.Tree, want: usize) !void {
    if (t.count() == want) return;
    std.debug.print("FAIL: count = {d}, want {d}\n", .{ t.count(), want });
    return error.WrongCount;
}

/// 트리 산수의 검사. 부팅도 PTY도 프레임버퍼도 안 쓴다 — 트리를 만들고
/// 사각형을 받는 순수 계산이다(WP design 결정 2).
pub fn main() !void {
    var rs: [layout.MAX_LEAVES]Rect = undefined;

    // ── 검사 1: 잎 하나의 사각형은 격자 전체다 ──────────────────────
    //
    // WP-M0의 판정 전체가 이 한 줄에 기댄다. 패널 하나면 `rect`가 격자
    // 전체라 `main.zig`의 원점 산수가 지금과 같은 값을 낸다.
    {
        const t = layout.Tree.init();
        try expectCount(&t, 1);
        t.rects(WHOLE, &rs);
        try expectRect("one leaf", rs[0], WHOLE);
    }

    // ── 검사 2: 오른쪽 분할 — 두 폭의 합 + 구분선 1 = 격자 폭 ────────
    //
    // 155는 홀수라 구분선을 빼면 154이고 반씩 77이다. 154(짝수)는 153이
    // 남아 76 · 77이다 — 나머지가 오른쪽으로 간다.
    {
        var t = layout.Tree.init();
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
        var t = layout.Tree.init();
        try expectLeaf("split below", t.split(0, .below, WHOLE), 1);
        t.rects(WHOLE, &rs);
        try expectRect("top", rs[0], .{ .col = 0, .row = 0, .cols = 155, .rows = 23 });
        try expectRect("bottom", rs[1], .{ .col = 0, .row = 24, .cols = 155, .rows = 23 });
        if (rs[0].rows + rs[1].rows + 1 != WHOLE.rows) return error.HeightSum;
    }

    // ── 검사 4: 셋을 가른 뒤 가운데를 지우면 형제가 올라간다 ──────────
    //
    // 0 | (1 / 2). 순서로는 1이 가운데다. 1을 지우면 2가 부모 자리 — 오른쪽
    // 절반 전체 — 를 받는다. 0은 안 움직인다.
    {
        var t = layout.Tree.init();
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

    // ── 검사 5: 여덟 뒤 아홉째는 null, 사각형이 안 겹치고 격자 안이다 ──
    //
    // 방향을 번갈아 가르며 늘 가장 최근 잎을 가른다 — 크기 제한(검사 6)에
    // 안 걸리고 여덟까지 간다(가장 작은 것이 8x5).
    {
        var t = layout.Tree.init();
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

        // 칸마다 몇 개의 사각형이 덮는지 센다. 2 이상이면 겹친 것이고,
        // 격자 밖이면 인덱스가 넘친다.
        t.rects(WHOLE, &rs);
        var cover = [_][155]u8{[_]u8{0} ** 155} ** 47;
        var area: usize = 0;
        for (rs) |r| {
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
        // 구분선은 분할마다 한 줄(한 칸 폭)이다. 남은 칸 = 격자 - 잎 넓이가
        // 0보다 커야 하고(구분선이 있다) 격자보다 작아야 한다.
        if (area == 0 or area >= @as(usize, WHOLE.cols) * WHOLE.rows) return error.AreaSum;
        std.debug.print("layout_test: 8 leaves, no overlap, area {d} of {d} OK\n", .{
            area, @as(usize, WHOLE.cols) * WHOLE.rows,
        });
    }

    // ── 검사 6: 가를 수 없을 만큼 작으면 null ────────────────────────
    //
    // 길이 3이 최소다 — 왼쪽 한 칸 · 구분선 · 오른쪽 한 칸. 2에서 가르면
    // 한쪽이 0칸이 되고 `vt.Screen.init`이 0x47 화면을 받는다.
    {
        const narrow: Rect = .{ .col = 0, .row = 0, .cols = 2, .rows = 2 };
        var t = layout.Tree.init();
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
        var t = layout.Tree.init();
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .right, WHOLE);
        try expectLeaf("next(last) wraps", t.next(2), 0);
        try expectLeaf("prev(first) wraps", t.prev(0), 2);
        try expectLeaf("prev(2)", t.prev(2), 1);

        const one = layout.Tree.init();
        try expectLeaf("next on one leaf", one.next(0), 0);
        try expectLeaf("prev on one leaf", one.prev(0), 0);
    }

    // ── 검사 8: 마지막 잎을 지우면 트리가 빈다 ───────────────────────
    //
    // WP design 결정 5의 "남은 패널이 없으면 나간다"가 이 성질을 본다.
    {
        var t = layout.Tree.init();
        t.remove(0);
        try expectCount(&t, 0);
        if (t.root != null) return error.RootNotCleared;
        std.debug.print("layout_test: last leaf removed, root=null OK\n", .{});
    }

    // ── 검사 9: 구분선은 내부 노드마다 하나다 (WP-M1) ───────────────────
    //
    // `cells()`가 빈 셀을 안 내보내므로 격자를 통째로 구분선 색으로 칠하고
    // 패널이 덮게 둘 수 없다(WP-M1 plan 확정 4). 그래서 구분선을 사각형으로
    // 따로 꺼낸다. 오른쪽 분할 하나면 77번 열 한 칸 폭, 높이 전체다.
    {
        var seps: [layout.MAX_LEAVES - 1]Rect = undefined;
        const one = layout.Tree.init();
        if (one.separators(WHOLE, &seps).len != 0) return error.SeparatorOnOneLeaf;

        var t = layout.Tree.init();
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

    // ── 검사 10: 패널 넓이 + 구분선 넓이 = 격자 넓이 ──────────────────────
    //
    // 검사 5는 "안 겹친다"만 봤다. 여기서 빈 칸이 없다는 것까지 본다 —
    // 구분선을 한 칸 어긋나게 그리면 패널과 겹치거나 틈이 생기고, 둘 다
    // 이 합이 어긋난다. 여덟 잎 트리와 구분선 일곱을 칸 단위로 칠해
    // 모든 칸이 정확히 한 번 덮이는지 본다.
    {
        var t = layout.Tree.init();
        var last: u4 = 0;
        var i: usize = 1;
        while (i < layout.MAX_LEAVES) : (i += 1) {
            const dir: layout.Dir = if (i % 2 == 1) .right else .below;
            last = t.split(last, dir, WHOLE) orelse return error.SplitFailed;
        }
        t.rects(WHOLE, &rs);
        var seps: [layout.MAX_LEAVES - 1]Rect = undefined;
        const ss = t.separators(WHOLE, &seps);
        if (ss.len != 7) return error.WrongSeparatorCount;

        var cover = [_][155]u8{[_]u8{0} ** 155} ** 47;
        for (rs ++ seps) |r| {
            var y = r.row;
            while (y < r.row + r.rows) : (y += 1) {
                var x = r.col;
                while (x < r.col + r.cols) : (x += 1) cover[y][x] += 1;
            }
        }
        for (cover) |row| for (row) |n| {
            if (n != 1) {
                std.debug.print("FAIL: a cell is covered {d} time(s)\n", .{n});
                return error.CoverNotExact;
            }
        };
        std.debug.print("layout_test: 8 panes + 7 separators cover the grid exactly once OK\n", .{});
    }

    // ── 검사 11: 지운 잎의 자리를 넘겨받는 잎 (WP-M2) ────────────────────
    //
    // 닫은 뒤 포커스는 자리를 넘겨받는 형제로 간다(WP-M1 실측 6, 사용자가
    // 2026-10-03에 골랐다). 0 | (1 / 2)에서 2를 닫으면 1이 그 자리를
    // 받는다 — 순회의 다음(0으로 감긴다)이 아니다. 둘을 가르는 것이 이 검사다.
    {
        var t = layout.Tree.init();
        try expectLeaf("heir on one leaf", t.heir(0), 0);
        _ = t.split(0, .right, WHOLE);
        _ = t.split(1, .below, WHOLE);
        try expectLeaf("heir(2) is its sibling above", t.heir(2), 1);
        try expectLeaf("heir(1) is its sibling below", t.heir(1), 2);
        // 0의 형제는 1과 2를 담은 서브트리다. 그 서브트리의 첫 잎이 받는다.
        try expectLeaf("heir(0) is the first leaf of the right half", t.heir(0), 1);
        // 순회의 next와 갈리는 자리를 직접 본다.
        try expectLeaf("next(2) wraps instead", t.next(2), 0);
    }

    std.debug.print("layout_test: all checks passed\n", .{});
}
