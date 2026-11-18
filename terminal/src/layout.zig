//! 패널 strip과 사각형 산수(SW design 결정 1 · 4).
//!
//! strip은 column 목록이고 column은 pane(slot 번호) 목록이다. column은 왼쪽에서
//! 오른쪽으로, column 안의 pane은 위에서 아래로 선다. 바깥이 보는 것은 WP의
//! 트리 때와 같이 "slot 번호 → 사각형"이다(SW design 결정 2).
//!
//! 순수 모듈이다. 시스템 콜도 ghostty도 프레임버퍼도 모른다 — `status.zig`가
//! 따로 서는 이유(IS 결정 5)와 같다. 그래서 `layout_test`가 컨테이너에서
//! 초 단위로 돌고, 분할 여덟 · 닫기 · 순환을 부팅 없이 본다.
//!
//! 좌표는 전부 셀 단위다(SW design 결정 3). 픽셀로 옮기는 것은 `main.zig`의 몫이다.

/// 격자 안의 사각형. 셀 단위이고 `col` · `row`가 왼쪽 위다.
pub const Rect = struct { col: u16, row: u16, cols: u16, rows: u16 };

/// 격자 칸 하나가 어느 slot의 어느 칸인가(PD design 결정 5). `col` · `row`는
/// 그 slot의 사각형 안의 상대 칸이다 — 패널의 `vt.Screen`이 아는 좌표다.
pub const Hit = struct { leaf: u4, col: u16, row: u16 };

/// 새 패널이 어느 쪽에 서는가. 오른쪽(새 column) 또는 아래(같은 column 안).
pub const Dir = enum { right, below };

/// 포커스가 어느 쪽 이웃으로 가는가(WP-M3). 분할의 `Dir`과 따로인 이유는
/// 분할에 왼쪽 · 위가 없어서다 — 새 패널은 늘 오른쪽(아래)에 선다.
pub const Side = enum { left, right, up, down };

/// 워크스페이스 하나의 패널 수 상한. slot 번호가 0..7이고 `main.zig`의
/// 패널 배열이 이 번호로 바로 인덱싱된다.
pub const MAX_LEAVES = 8;

/// column 하나의 pane 수 상한(SW-M1, SW design 결정 12 · 요구사항 결정 7). 47줄
/// 격자에서 셋이면 15줄씩이다. 넘는 `.below`는 `split`이 null로 거절한다.
pub const MAX_PER_COLUMN = 3;

/// column 하나. 위에서 아래 순서의 slot 번호와 그 수다.
///
/// 쓰지 않는 칸은 늘 0이다. 빼고 당긴 뒤 비는 끝 칸도 0으로 되돌린다 — 같은
/// 배치의 두 strip이 `std.meta.eql`로 같아야 `main.zig`가 지난 프레임의 배치와
/// 견줄 수 있다(`last_strip`, SW design 결정 1). slot 0과 빈 칸은 둘 다 0이지만
/// `len`이 둘을 가른다.
const Column = struct {
    slots: [MAX_LEAVES]u4 = @splat(0),
    len: u4 = 0,
};

/// slot 하나가 strip의 어디에 있는가. `c`는 column 순번, `i`는 그 column 안의 순번이다.
const Place = struct { c: usize, i: usize };

pub const Strip = struct {
    // column도 pane도 고정 배열이다. 동적 할당이 없고 "언제 해제하는가"가
    // 없다 — find_buf가 128바이트 고정인 것과 같은 판단. pane이 여덟이면
    // column도 많아야 여덟이다.
    cols: [MAX_LEAVES]Column,
    /// 쓰는 column의 수. 마지막 pane을 지우면 0이다.
    len: u4,

    /// column 하나에 slot 0 하나. 부팅의 모양이다.
    pub fn init() Strip {
        var s: Strip = .{ .cols = @splat(.{}), .len = 1 };
        s.cols[0].len = 1;
        return s;
    }

    /// slot `leaf`의 옆에 새 pane을 세우고 새 slot 번호를 돌려준다(SW design
    /// 결정 5). `.right`는 포커스 column 바로 오른쪽에 pane 하나짜리 column을
    /// 끼우고, `.below`는 같은 column에서 포커스 pane 바로 아래에 끼운다.
    ///
    /// null인 경우가 넷이고 이 순서로 본다(SW-M1 plan 확정 2). pane이 이미
    /// 여덟이거나, 없는 slot이거나, `.below`인데 그 column이 이미 셋이거나
    /// (`MAX_PER_COLUMN`), 끼운 뒤 고르게 나눈 몫이 한 칸 미만이다 — 길이
    /// `L`에 `n`개를 놓으려면 구분선 `n-1`과 한 칸씩 `n`이 들어야 해서
    /// `L ≥ 2n-1`이다. 둘째 pane에서는 WP
    /// 트리의 "길이 3 미만"과 같다. 판정 길이는 `.right`가 격자 폭, `.below`가
    /// 격자 높이다 — column 폭과 pane 높이는 그 길이를 고르게 나눈 것이라
    /// 크기를 보려면 격자 전체가 있어야 해서 `whole`을 받는다.
    ///
    /// 새 slot 번호는 비어 있는 가장 작은 번호다. 다른 pane의 번호는 안
    /// 바뀐다(R-SW-7) — `main.zig`의 패널 배열이 이 번호로 인덱싱된다.
    pub fn split(self: *Strip, leaf: u4, dir: Dir, whole: Rect) ?u4 {
        if (self.count() >= MAX_LEAVES) return null;
        const at = self.find(leaf) orelse return null;
        if (dir == .below and self.cols[at.c].len >= MAX_PER_COLUMN) return null;
        const len: usize, const n: usize = switch (dir) {
            .right => .{ whole.cols, @as(usize, self.len) + 1 },
            .below => .{ whole.rows, @as(usize, self.cols[at.c].len) + 1 },
        };
        if (len < 2 * n - 1) return null;

        const new_leaf = self.freeLeaf();
        switch (dir) {
            .right => {
                // 뒤의 column을 한 칸씩 민다. 끝에서부터 옮겨야 덮어쓰지 않는다.
                var k: usize = self.len;
                while (k > at.c + 1) : (k -= 1) self.cols[k] = self.cols[k - 1];
                self.cols[at.c + 1] = .{};
                self.cols[at.c + 1].slots[0] = new_leaf;
                self.cols[at.c + 1].len = 1;
                self.len += 1;
            },
            .below => {
                const col = &self.cols[at.c];
                var k: usize = col.len;
                while (k > at.i + 1) : (k -= 1) col.slots[k] = col.slots[k - 1];
                col.slots[at.i + 1] = new_leaf;
                col.len += 1;
            },
        }
        return new_leaf;
    }

    /// slot `leaf`를 지운다(SW design 결정 6). 그 column에서 빼고 아래를 당긴다.
    /// column이 비면 column을 빼고 뒤의 column을 당긴다. 당긴 뒤 비는 끝 칸은
    /// 0으로 되돌린다(`Column`의 주석). 다른 pane의 slot 번호는 안 바뀐다.
    ///
    /// 마지막 pane이면 strip이 빈다(`count() == 0`). 없는 slot이면 아무 일도
    /// 안 한다.
    pub fn remove(self: *Strip, leaf: u4) void {
        const at = self.find(leaf) orelse return;
        const col = &self.cols[at.c];
        var k = at.i;
        while (k + 1 < col.len) : (k += 1) col.slots[k] = col.slots[k + 1];
        col.len -= 1;
        col.slots[col.len] = 0;
        if (col.len > 0) return;

        k = at.c;
        while (k + 1 < self.len) : (k += 1) self.cols[k] = self.cols[k + 1];
        self.len -= 1;
        self.cols[self.len] = .{};
    }

    /// slot마다 사각형을 `out[slot 번호]`에 쓴다. 없는 slot의 칸은 안 건드린다 —
    /// 부르는 쪽은 패널 배열의 null로 그것을 안다.
    ///
    /// column 폭은 격자 폭을, column 안 pane 높이는 격자 높이를 고르게 나눈다
    /// (`share`, SW design 결정 4). 비율이 없다 — 드래그가 없는 시스템에서
    /// 비율을 들 일이 없다.
    pub fn rects(self: *const Strip, whole: Rect, out: []Rect) void {
        for (self.cols[0..self.len], 0..) |col, c| {
            const x = share(whole.cols, self.len, c);
            for (col.slots[0..col.len], 0..) |leaf, i| {
                const y = share(whole.rows, col.len, i);
                out[leaf] = .{ .col = whole.col + x.start, .row = whole.row + y.start, .cols = x.len, .rows = y.len };
            }
        }
    }

    /// 구분선 사각형을 `out`에 담고 그 앞부분을 돌려준다. 수는 pane 수 − 1이다 —
    /// column 사이마다 세로선 하나, column 안 pane 사이마다 가로선 하나. `out`은
    /// `MAX_LEAVES - 1`칸이면 언제나 넉넉하다.
    ///
    /// 순서는 column 순이다. 둘째 column부터는 그 앞의 세로선을 먼저 내고, 그다음
    /// 그 column의 가로선을 위에서 아래로 낸다(SW-M0 plan 확정 5).
    ///
    /// 패널 사각형과 따로 꺼내는 이유가 WP-M1 plan 확정 4다. `cells()`는
    /// 글자도 색도 없는 셀을 안 내보내므로, 격자를 통째로 구분선 색으로
    /// 칠하고 패널이 덮게 두면 패널 안의 빈 칸이 구분선 색으로 남는다.
    ///
    /// 세로선은 column 바로 왼쪽 한 칸 폭에 격자 높이 전체, 가로선은 pane 바로
    /// 위 한 줄에 그 column 폭이다. 위치는 `rects`와 같은 `share`에서 나온다.
    pub fn separators(self: *const Strip, whole: Rect, out: []Rect) []Rect {
        var n: usize = 0;
        for (self.cols[0..self.len], 0..) |col, c| {
            const x = share(whole.cols, self.len, c);
            if (c > 0) {
                out[n] = .{ .col = whole.col + x.start - 1, .row = whole.row, .cols = 1, .rows = whole.rows };
                n += 1;
            }
            for (1..col.len) |i| {
                const y = share(whole.rows, col.len, i);
                out[n] = .{ .col = whole.col + x.start, .row = whole.row + y.start - 1, .cols = x.len, .rows = 1 };
                n += 1;
            }
        }
        return out[0..n];
    }

    /// 다음 slot. column 순, column 안은 위→아래이고 끝에서 처음으로 감긴다
    /// (SW design 결정 7).
    pub fn next(self: *const Strip, leaf: u4) u4 {
        var buf: [MAX_LEAVES]u4 = undefined;
        const order = self.leaves(&buf);
        const i = indexOf(order, leaf) orelse return leaf;
        return order[(i + 1) % order.len];
    }

    /// 이전 slot. `next`의 반대 방향이고 처음에서 끝으로 감긴다.
    pub fn prev(self: *const Strip, leaf: u4) u4 {
        var buf: [MAX_LEAVES]u4 = undefined;
        const order = self.leaves(&buf);
        const i = indexOf(order, leaf) orelse return leaf;
        return order[(i + order.len - 1) % order.len];
    }

    /// slot `leaf`를 지우면 포커스를 넘겨받는 slot(WP-M2, SW design 결정 9).
    /// 패널을 닫은 뒤 포커스가 갈 곳이다.
    ///
    /// 같은 column의 바로 위 pane, 없으면 바로 아래 pane이다. `0 | (1 / 2)`에서
    /// 2를 닫으면 1이다 — 화면에서 커지는 쪽이다(iTerm2와 같다). column에 하나뿐이면
    /// column이 비므로 왼쪽 column, 없으면 오른쪽 column에서 `neighbor`의 ← → 규칙
    /// (시작 줄 ≤ 포커스의 맨 위 줄인 마지막 pane)으로 고른다. 혼자인 pane의 맨 위
    /// 줄은 격자의 맨 위이고, 그 줄에서 시작하는 것은 어느 column이든 첫 pane
    /// 하나뿐이라 그 column의 첫 pane이 답이다 — 그래서 `whole`이 없어도 된다.
    ///
    /// strip에 하나뿐이면 자기 자신이다. `remove` 앞에 불러야 한다 — 지운 뒤에는
    /// 그 slot이 strip에 없다.
    pub fn heir(self: *const Strip, leaf: u4) u4 {
        const at = self.find(leaf) orelse return leaf;
        const col = self.cols[at.c];
        if (col.len > 1) return if (at.i > 0) col.slots[at.i - 1] else col.slots[at.i + 1];
        if (at.c > 0) return self.cols[at.c - 1].slots[0];
        if (at.c + 1 < self.len) return self.cols[at.c + 1].slots[0];
        return leaf;
    }

    /// 격자 칸 `(col, row)`가 든 slot과 그 안의 상대 칸(PD design 결정 5).
    /// 포인터가 가리키는 패널을 고르는 자리다.
    ///
    /// null이 둘이다. 구분선 칸은 어느 slot의 사각형에도 안 들어가고(`share`가
    /// 구분선을 이웃 사이에 따로 둔다), 격자 밖 칸은 `whole` 밖이다. 픽셀을
    /// 격자 칸으로 바꾸는 것은 `main.zig`다 — 이 파일은 셀 단위만 안다.
    ///
    /// 사각형은 `rects`로 얻는다. 같은 산수를 여기서 다시 하면 언젠가 한 칸
    /// 어긋나고, 그 어긋남은 "구분선 위를 가리켰는데 왼쪽 패널이 움직인다"로
    /// 나타난다.
    pub fn hit(self: *const Strip, whole: Rect, col: u16, row: u16) ?Hit {
        var rs: [MAX_LEAVES]Rect = undefined;
        self.rects(whole, &rs);
        var buf: [MAX_LEAVES]u4 = undefined;
        for (self.leaves(&buf)) |leaf| {
            const r = rs[leaf];
            if (col < r.col or col >= r.col + r.cols) continue;
            if (row < r.row or row >= r.row + r.rows) continue;
            return .{ .leaf = leaf, .col = col - r.col, .row = row - r.row };
        }
        return null;
    }

    /// slot `leaf`의 `side` 쪽 이웃(WP-M3, SW design 결정 8). 그쪽에 pane이
    /// 없으면(strip의 끝, column의 끝) null — 감기지 않는다. 감기는 이동은
    /// `next` · `prev`가 맡는다.
    ///
    /// ↑ ↓는 같은 column의 바로 위 · 아래 pane이다. ← →는 옆 column에서 시작 줄이
    /// 포커스 pane의 맨 위 줄 이하인 마지막 pane이다 — 그 줄을 덮는 pane이고,
    /// 그 줄이 옆 column의 가로 구분선이면 구분선 바로 위 pane이다. `0 | (1 / 2)`
    /// 에서 0의 →는 1이다. 사람이 고른 규칙이고(2026-10-26), 상태 없이 배치만으로
    /// 정해진다.
    ///
    /// WP 트리는 구분선 한 칸을 건너뛴 칸을 `hit`에 물었다. strip은 column마다
    /// 높이를 따로 나누므로 그 칸이 옆 column의 구분선에 떨어질 수 있어서
    /// (`layout_test` 검사 18) 목록으로 직접 고른다. 시작 줄은 `rects`와 같은
    /// `share`에서 나온다.
    pub fn neighbor(self: *const Strip, whole: Rect, leaf: u4, side: Side) ?u4 {
        const at = self.find(leaf) orelse return null;
        const col = self.cols[at.c];
        const tc: usize = switch (side) {
            .up => return if (at.i > 0) col.slots[at.i - 1] else null,
            .down => return if (at.i + 1 < col.len) col.slots[at.i + 1] else null,
            .left => if (at.c > 0) at.c - 1 else return null,
            .right => if (at.c + 1 < self.len) at.c + 1 else return null,
        };
        const top = share(whole.rows, col.len, at.i).start;
        const other = self.cols[tc];
        var j: usize = 0;
        while (j + 1 < other.len and share(whole.rows, other.len, j + 1).start <= top) j += 1;
        return other.slots[j];
    }

    /// slot `leaf`가 든 column의 순번(0부터)과 column 수(SW-M1). `main.zig`의
    /// `strip>` 줄이 쓴다. 없는 slot이면 null이다.
    pub fn columnOf(self: *const Strip, leaf: u4) ?struct { col: usize, cols: usize } {
        const at = self.find(leaf) orelse return null;
        return .{ .col = at.c, .cols = self.len };
    }

    /// column마다 pane 수를 `buf`에 담고 그 앞부분을 돌려준다(SW-M1, `strip>` 줄의
    /// `heights`).
    pub fn heights(self: *const Strip, buf: *[MAX_LEAVES]u4) []u4 {
        for (self.cols[0..self.len], 0..) |col, c| buf[c] = col.len;
        return buf[0..self.len];
    }

    /// pane의 수.
    pub fn count(self: *const Strip) usize {
        var n: usize = 0;
        for (self.cols[0..self.len]) |col| n += col.len;
        return n;
    }

    /// slot 번호를 column 순, column 안은 위→아래 순으로 `buf`에 담는다.
    fn leaves(self: *const Strip, buf: *[MAX_LEAVES]u4) []u4 {
        var n: usize = 0;
        for (self.cols[0..self.len]) |col| {
            for (col.slots[0..col.len]) |leaf| {
                buf[n] = leaf;
                n += 1;
            }
        }
        return buf[0..n];
    }

    fn find(self: *const Strip, leaf: u4) ?Place {
        for (self.cols[0..self.len], 0..) |col, c| {
            for (col.slots[0..col.len], 0..) |l, i| {
                if (l == leaf) return .{ .c = c, .i = i };
            }
        }
        return null;
    }

    /// 쓰이지 않은 가장 작은 slot 번호. `split`이 pane 수를 먼저 보므로 언제나
    /// 있다.
    fn freeLeaf(self: *const Strip) u4 {
        var used: [MAX_LEAVES]bool = @splat(false);
        for (self.cols[0..self.len]) |col| {
            for (col.slots[0..col.len]) |leaf| used[leaf] = true;
        }
        for (used, 0..) |u, i| {
            if (!u) return @intCast(i);
        }
        unreachable;
    }
};

/// 격자 칸 `(col, row)`를 사각형 `r` 안으로 붙이고 그 안의 상대 칸으로
/// 돌려준다(PD design 결정 5). 끄는 동안 선택 끝이 누른 패널 밖으로 안
/// 나가게 하는 자리다 — 이웃 패널이나 구분선 위로 끌어도 누른 패널의
/// 가장자리 칸에서 멈춘다.
///
/// `hit`과 달리 null이 없다. 끄는 중에는 포인터가 어디에 있든 선택 끝이
/// 있어야 하기 때문이다. 격자 밖의 픽셀을 격자 칸으로 붙이는 것은
/// `main.zig`의 몫이다(이 파일은 셀 단위만 안다). `r`은 넓이가 1 이상이어야
/// 한다 — `split`이 그보다 작은 pane을 안 만든다.
pub fn clampInto(r: Rect, leaf: u4, col: u16, row: u16) Hit {
    const c = @min(@max(col, r.col), r.col + r.cols - 1);
    const w = @min(@max(row, r.row), r.row + r.rows - 1);
    return .{ .leaf = leaf, .col = c - r.col, .row = w - r.row };
}

/// 길이 `l`에 `n`개를 구분선 한 칸씩 사이에 두고 고르게 놓았을 때 `i`번째의
/// 시작(0부터의 상대 위치)과 길이(SW design 결정 4).
///
/// 구분선 `n-1`을 빼고 `(l-(n-1))/n`씩이다. 나머지 `r`은 뒤의 `r`개가 한 칸씩
/// 더 받는다 — 155에서 둘이면 77 · 77, 154에서 둘이면 76 · 77이다. `n = 2`이면
/// WP 트리의 반 가르기와 같은 숫자다.
///
/// `rects` · `separators` · `split`의 크기 판정 · `neighbor`가 모두 이것에
/// 기댄다. 같은 산수를 따로 하면 언젠가 한 칸 어긋난다 — 그 어긋남은 "구분선이
/// 패널 위에 그려진다"로 나타나고 `layout_test`의 검사 10이 본다.
///
/// `l < 2n-1`이면 몫이 0이 된다. `split`이 그런 배치를 안 만들지만, 이미 선
/// 배치에서 격자가 줄면(전체 화면을 끔) 생길 수 있어 빼기는 넘치지 않게 한다.
fn share(l: u16, n: usize, i: usize) struct { start: u16, len: u16 } {
    const avail: usize = @as(usize, l) -| (n - 1);
    const base = avail / n;
    const plain = n - avail % n; // 앞의 이만큼은 `base`, 나머지는 `base + 1`이다.
    const start = i * (base + 1) + (i -| plain);
    const len = base + @intFromBool(i >= plain);
    return .{ .start = @intCast(start), .len = @intCast(len) };
}

fn indexOf(order: []const u4, leaf: u4) ?usize {
    for (order, 0..) |l, i| {
        if (l == leaf) return i;
    }
    return null;
}
