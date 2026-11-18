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
//!
//! column마다 폭(`Width`)을 저장한다(SW-M3, design 결정 19). column이 하나면 저장한
//! 폭과 상관없이 격자 전체 폭, 정확히 둘이고 둘 다 `half`면 반씩(155에서 77 · 77,
//! 154에서 76 · 77), 그 밖에는 `first`부터 왼쪽에서 폭 + 구분선 1을 쌓아 격자 안에
//! 드는 데까지가 화면(viewport)이다(design 결정 21 · 22 · 23). 모두 `half`이고 셋
//! 이상이면 둘이 든다 — SW-M2의 모양이다. 화면 밖 column도 크기는 있다 — 그 셸의
//! PTY는 화면 밖에서도 그 크기다.

/// 격자 안의 사각형. 셀 단위이고 `col` · `row`가 왼쪽 위다.
pub const Rect = struct { col: u16, row: u16, cols: u16, rows: u16 };

/// 격자 칸 하나가 어느 slot의 어느 칸인가(PD design 결정 5). `col` · `row`는
/// 그 slot의 사각형 안의 상대 칸이다 — 패널의 `vt.Screen`이 아는 좌표다.
pub const Hit = struct { leaf: u4, col: u16, row: u16 };

/// 새 패널이 어느 쪽에 서는가. 오른쪽(새 column) 또는 아래(같은 column 안).
pub const Dir = enum { right, below };

/// column의 폭(SW-M3, design 결정 19). 셀로 풀 때 `half`는 `(cols-1)/2`, `full`은
/// `cols`, `c80` · `c120`은 그 셀 수이고 어느 것도 `cols`를 넘지 않는다. 비율과 셀이
/// 섞인 것은 요구사항 결정 13의 값 그대로다 — 셀 preset은 전체 화면을 켜고 꺼도 같은
/// 셀 수로 남는다.
pub const Width = enum {
    half,
    full,
    c80,
    c120,

    /// 격자 폭 `l`에서의 셀 수. `half`는 둘이 구분선 하나를 사이에 두고 드는 폭이다.
    pub fn cells(self: Width, l: u16) u16 {
        return switch (self) {
            .half => (l -| 1) / 2,
            .full => l,
            .c80 => @min(80, l),
            .c120 => @min(120, l),
        };
    }
};

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
/// `len`이 둘을 가른다. 쓰지 않는 칸의 `width`도 같은 이유로 늘 기본값 `half`다.
const Column = struct {
    slots: [MAX_LEAVES]u4 = @splat(0),
    len: u4 = 0,
    /// 저장한 폭(SW-M3). column이 하나일 때는 안 쓴다(design 결정 21).
    width: Width = .half,
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
    /// 화면에 보이는 첫 column의 순번(SW-M2, design 결정 14). 0 ≤ `first` ≤
    /// max(0, `len` − 1)이고, 보이는 column은 `first`부터 폭을 쌓아 격자 안에 드는
    /// 데까지다(SW-M3, `lastFrom`). 옮기는 것은 `reveal`과 `remove`(범위 안으로 당기고
    /// 채운다)뿐이다. `std.meta.eql` 비교에 들어가므로 scroll된 프레임은 `main.zig`가
    /// 통째로 다시 그린다.
    first: u4,

    /// column 하나에 slot 0 하나. 부팅의 모양이다.
    pub fn init() Strip {
        var s: Strip = .{ .cols = @splat(.{}), .len = 1, .first = 0 };
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
    /// 격자 높이다 — column 폭과 pane 높이는 그 길이를 나눈 것이라 크기를 보려면
    /// 격자 전체가 있어야 해서 `whole`을 받는다.
    ///
    /// `.right`는 SW-M3부터 "새 column의 폭이 한 칸 이상"이다(plan 확정 5). 새
    /// column의 폭은 design 결정 20이다 — 혼자인 column을 가르면 둘 다 `half`, 아니면
    /// 포커스 column의 폭을 물려받는다. `half`는 격자 폭 3 이상에서 한 칸 이상이라
    /// SW-M2의 `L ≥ 2n-1`(n = 2)과 같은 판정이다. 다른 column의 폭은 안 바뀐다.
    ///
    /// `first`는 안 건드린다. 새 pane을 보이게 하는 것은 포커스를 정하는
    /// `main.zig`가 `reveal`로 한다.
    ///
    /// 새 slot 번호는 비어 있는 가장 작은 번호다. 다른 pane의 번호는 안
    /// 바뀐다(R-SW-7) — `main.zig`의 패널 배열이 이 번호로 인덱싱된다.
    pub fn split(self: *Strip, leaf: u4, dir: Dir, whole: Rect) ?u4 {
        if (self.count() >= MAX_LEAVES) return null;
        const at = self.find(leaf) orelse return null;
        if (dir == .below and self.cols[at.c].len >= MAX_PER_COLUMN) return null;
        const width: Width = if (self.len == 1) .half else self.cols[at.c].width;
        switch (dir) {
            .right => if (width.cells(whole.cols) < 1) return null,
            .below => {
                const n: usize = @as(usize, self.cols[at.c].len) + 1;
                if (whole.rows < 2 * n - 1) return null;
            },
        }

        const new_leaf = self.freeLeaf();
        switch (dir) {
            .right => {
                // 뒤의 column을 한 칸씩 민다. 끝에서부터 옮겨야 덮어쓰지 않는다.
                var k: usize = self.len;
                while (k > at.c + 1) : (k -= 1) self.cols[k] = self.cols[k - 1];
                self.cols[at.c + 1] = .{ .width = width };
                self.cols[at.c + 1].slots[0] = new_leaf;
                self.cols[at.c + 1].len = 1;
                if (self.len == 1) self.cols[at.c].width = .half;
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
    /// 안 한다. column이 줄면 끝에서 `first`를 범위 안으로 당기고 채운다(SW-M2 ·
    /// SW-M3 plan 확정 4, `fill`) — 그래서 격자 폭이 든 `whole`을 받는다. 포커스가
    /// 보이게 하는 것은 그 뒤 `main.zig`의 `reveal`이다.
    pub fn remove(self: *Strip, leaf: u4, whole: Rect) void {
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
        self.first = @min(self.first, self.len -| 1);
        self.fill(whole.cols);
    }

    /// slot마다 사각형을 `out[slot 번호]`에 쓴다. 없는 slot의 칸은 안 건드린다 —
    /// 부르는 쪽은 패널 배열의 null로 그것을 안다.
    ///
    /// 화면 밖 slot에도 쓴다(SW-M2, design 결정 15). 크기는 화면 안에 있을 때와
    /// 같고 — 그 셸의 PTY가 그 크기다 — 위치는 `col = whole.col`로 둔다. 그려지지
    /// 않으므로 위치는 뜻이 없다. 가르는 것은 `visible`이다.
    ///
    /// column 폭은 `colSpan`, column 안 pane 높이는 격자 높이를 고르게 나눈
    /// 것이다(`share`, SW design 결정 4). 비율이 없다 — 드래그가 없는 시스템에서
    /// 비율을 들 일이 없다.
    pub fn rects(self: *const Strip, whole: Rect, out: []Rect) void {
        for (self.cols[0..self.len], 0..) |col, c| {
            const x = self.colSpan(whole.cols, c);
            const left = if (x.visible) whole.col + x.start else whole.col;
            for (col.slots[0..col.len], 0..) |leaf, i| {
                const y = share(whole.rows, col.len, i);
                out[leaf] = .{ .col = left, .row = whole.row + y.start, .cols = x.len, .rows = y.len };
            }
        }
    }

    /// slot `leaf`가 화면에 보이는가(SW-M2). 그 column이 `view` 안이면 보인다. 없는
    /// slot이면 false다. 그리기 · verify가 이것으로 건너뛴다.
    pub fn visible(self: *const Strip, leaf: u4, whole: Rect) bool {
        const at = self.find(leaf) orelse return false;
        return self.colVisible(whole.cols, at.c);
    }

    /// slot `leaf`의 column이 보이도록 `first`를 가장 적게 옮긴다(SW-M2 · SW-M3,
    /// design 결정 23 · R-SW-5). 왼쪽 밖이면 그 column이 첫째가 되고, 오른쪽 밖이면
    /// 그 column이 마지막으로 드는 가장 작은 `first`가 된다. 폭이 격자 폭을 안
    /// 넘으므로 늘 든다. 그다음 채운다(`fill`). 옮겼으면 true다 — 부르는 쪽은
    /// `applyLayout`으로 위치를 다시 잡는다. 없는 slot이면 false다.
    pub fn reveal(self: *Strip, leaf: u4, whole: Rect) bool {
        const at = self.find(leaf) orelse return false;
        const l = whole.cols;
        const old = self.first;
        if (at.c < self.first) {
            self.first = @intCast(at.c);
        } else if (at.c > self.lastFrom(l, self.first)) {
            var f: usize = self.first;
            while (self.lastFrom(l, f) < at.c) f += 1;
            self.first = @intCast(f);
        }
        self.fill(l);
        return self.first != old;
    }

    /// 채우기(SW-M3, design 결정 23). `first - 1`부터 지금 보이는 끝까지가 함께
    /// 격자에 들면 `first`를 하나 줄이기를 되풀이한다 — 왼쪽에 들 수 있는 column이
    /// 있는데 비워 두지 않는다. 보이는 끝은 안 바뀐다(더 들 column이 있었다면 이미
    /// 보였다). 모두 `half`이고 셋 이상이면 셋이 함께 들 수 없어 일어나지 않는다.
    fn fill(self: *Strip, l: u16) void {
        if (self.len == 0) return;
        const last = self.lastFrom(l, self.first);
        while (self.first > 0 and self.spanCells(l, self.first - 1, last) <= l) self.first -= 1;
    }

    /// slot `leaf`의 사각형 바로 오른쪽 칸이 세로 구분선인가(SW-M3). 보이는 column이고 그
    /// 오른쪽에 보이는 column이 있으면 참이다 — `separators`가 그 둘 사이에 세로선을 낸다. 보이는
    /// 끝 column이면 거짓이다. 그 오른쪽은 격자 끝의 여백이거나, 폭 preset으로 남은 빈 공간
    /// (여백 색, `peekRect`는 한 칸 건너 시작한다)이다. `main.zig`의 부분 갱신이 패널 오른쪽
    /// 한 칸을 되칠할 색을 이것으로 고른다(`stripColor`). 화면 밖 · 없는 slot도 거짓이다.
    pub fn separatorRight(self: *const Strip, leaf: u4, whole: Rect) bool {
        const at = self.find(leaf) orelse return false;
        if (self.len <= 1 or !self.colVisible(whole.cols, at.c)) return false;
        return at.c < self.lastFrom(whole.cols, self.first);
    }

    /// 보이는 column의 처음과 끝 순번(0부터, SW-M2). column이 하나면 둘이 같다.
    /// `strip>` 줄의 `view=`와 상태 줄의 칸이 쓴다. 끝은 격자 폭에 따라 다르다
    /// (SW-M3) — 그래서 `whole`을 받는다.
    pub fn view(self: *const Strip, whole: Rect) struct { first: usize, last: usize } {
        if (self.len <= 1) return .{ .first = 0, .last = 0 };
        return .{ .first = self.first, .last = self.lastFrom(whole.cols, self.first) };
    }

    /// slot `leaf`의 column 폭을 다음 preset으로 돌리고 새 값을 돌려준다(SW-M3, design
    /// 결정 24). 순서는 `c80 → c120 → half → full → c80`이다. column이 하나면 폭이
    /// 늘 격자 전체라(결정 21) 아무것도 안 바꾸고 null이다 — `main.zig`가 `pane> width
    /// refused`를 찍는다. 없는 slot도 null이다. `first`는 안 건드린다 — 포커스를 보이게
    /// 하고 채우는 것은 그 뒤 `main.zig`의 `reveal`이다.
    pub fn cycleWidth(self: *Strip, leaf: u4) ?Width {
        if (self.len <= 1) return null;
        const at = self.find(leaf) orelse return null;
        const w = &self.cols[at.c].width;
        w.* = switch (w.*) {
            .c80 => .c120,
            .c120 => .half,
            .half => .full,
            .full => .c80,
        };
        return w.*;
    }

    /// 빈 공간에 이름을 띄울 slot(SW-M3, design 결정 25). 보이는 끝 column 오른쪽에
    /// 구분선 자리 한 칸을 빼고도 빈 칸이 한 칸 이상이고 그다음 column이 있으면, 그
    /// column 맨 위 pane의 slot이다. 아니면 null이다. 모두 `half`면 빈 칸이 짝수
    /// 격자에서도 한 칸뿐이라(구분선 자리) null이다 — `strip>` 줄이 `peek=-`다.
    pub fn peek(self: *const Strip, whole: Rect) ?u4 {
        const g = self.gap(whole.cols) orelse return null;
        return self.cols[g.next].slots[0];
    }

    /// `peek`의 이름을 그릴 사각형(SW-M3, plan 확정 7). 빈 칸의 첫 줄 한 줄이고 폭은
    /// 빈 칸 전체다. 보이는 끝 column과 그 사이 한 칸은 구분선 자리로 비워 둔다.
    pub fn peekRect(self: *const Strip, whole: Rect) ?Rect {
        const g = self.gap(whole.cols) orelse return null;
        return .{ .col = whole.col + g.used + 1, .row = whole.row, .cols = whole.cols - g.used - 1, .rows = 1 };
    }

    /// 보이는 column이 쓰는 셀 수(구분선 포함)와 그다음 column의 순번. 빈 칸이 구분선
    /// 자리 뒤로 한 칸 이상이고 다음 column이 있을 때만 값이 있다.
    fn gap(self: *const Strip, l: u16) ?struct { used: u16, next: usize } {
        if (self.len <= 1) return null;
        const last = self.lastFrom(l, self.first);
        if (last + 1 >= self.len) return null;
        const used = self.spanCells(l, self.first, last);
        if (used + 1 >= l) return null;
        return .{ .used = @intCast(used), .next = last + 1 };
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
    /// 위 한 줄에 그 column 폭이다. 위치는 `rects`와 같은 `colSpan` · `share`에서
    /// 나온다.
    ///
    /// 보이는 column의 것만 낸다(SW-M2 plan 확정 4) — 보이는 column이 둘이면
    /// 세로선 하나와 두 column의 가로선이다. 그래서 수는 보이는 pane 수 − 1이다.
    pub fn separators(self: *const Strip, whole: Rect, out: []Rect) []Rect {
        var n: usize = 0;
        for (self.cols[0..self.len], 0..) |col, c| {
            const x = self.colSpan(whole.cols, c);
            if (!x.visible) continue;
            if (c > self.first) {
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
    /// 나타난다. 화면 밖 slot은 건너뛴다(SW-M2) — 그 사각형은 위치가 뜻이 없다.
    pub fn hit(self: *const Strip, whole: Rect, col: u16, row: u16) ?Hit {
        var rs: [MAX_LEAVES]Rect = undefined;
        self.rects(whole, &rs);
        var buf: [MAX_LEAVES]u4 = undefined;
        for (self.leaves(&buf)) |leaf| {
            if (!self.visible(leaf, whole)) continue;
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
    ///
    /// 화면 밖 column으로도 간다(SW-M2 plan 확정 4). 그다음 `main.zig`의 `reveal`이
    /// viewport를 옮긴다.
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

    /// column `c`의 시작(격자 왼쪽에서의 상대 위치) · 폭과 화면에 보이는가(SW-M2 ·
    /// SW-M3, design 결정 21 · 22). 갈래가 셋이다.
    ///
    /// - column 하나: 저장한 폭과 상관없이 격자 전체 폭.
    /// - 정확히 둘이고 둘 다 `half`: 왼쪽은 `share(l, 2, 0)`, 오른쪽은 `share(l, 2, 1)`의
    ///   위치 · 폭. 155에서 77 · 77, 154에서 76 · 77이다(`layout_test` 검사 2). 둘 다
    ///   늘 보이므로(77 + 1 + 77 ≤ 155) 두 폭이 달라도 scroll로 크기가 오가지 않는다.
    /// - 그 밖: 폭은 `colWidth`이고, 보이는 column은 `first`부터 폭 + 구분선 1을 쌓은
    ///   자리에 선다. 모두 `half`이고 셋 이상이면 보이든 안 보이든 `(l-1)/2`이고 보이는
    ///   왼쪽은 0, 오른쪽은 `w + 1`이다 — 짝수 폭이면 오른쪽 끝 한 칸이 비고 여백 색으로
    ///   남는다(SW-M2의 모양). 폭은 `first`와 무관하므로 scroll이 어느 격자에서도 셸을
    ///   resize하지 않는다(검사 23).
    ///
    /// 시작은 화면 밖 column에서 뜻이 없다.
    fn colSpan(self: *const Strip, l: u16, c: usize) struct { start: u16, len: u16, visible: bool } {
        if (self.len <= 1) {
            const x = share(l, 1, 0);
            return .{ .start = x.start, .len = x.len, .visible = true };
        }
        const vis = self.colVisible(l, c);
        if (self.bothHalf()) {
            const x = share(l, 2, c);
            const base = share(l, 2, self.first).start;
            return .{ .start = if (vis) x.start - base else 0, .len = x.len, .visible = vis };
        }
        var start: u16 = 0;
        if (vis) {
            for (self.first..c) |k| start += self.colWidth(l, k) + 1;
        }
        return .{ .start = start, .len = self.colWidth(l, c), .visible = vis };
    }

    fn colVisible(self: *const Strip, l: u16, c: usize) bool {
        return c >= self.first and c <= self.lastFrom(l, self.first);
    }

    /// column `c`의 셀 폭. column이 하나면 격자 전체(design 결정 21), 아니면 저장한
    /// 폭을 푼 것이다(`Width.cells`). 쌓기 · 채우기 · `peek`의 판정이 이것으로 센다.
    fn colWidth(self: *const Strip, l: u16, c: usize) u16 {
        if (self.len <= 1) return l;
        return self.cols[c].width.cells(l);
    }

    /// column `a`..`b`(둘 다 포함)를 구분선 한 칸씩 사이에 두고 놓은 셀 수.
    fn spanCells(self: *const Strip, l: u16, a: usize, b: usize) usize {
        var n: usize = 0;
        for (a..b + 1) |k| n += self.colWidth(l, k);
        return n + (b - a);
    }

    /// `f`부터 쌓아 격자 폭 `l` 안에 드는 마지막 column의 순번(SW-M3, design 결정
    /// 23). 첫 column은 폭이 `l`을 안 넘으므로 늘 든다 — 답은 `f` 이상이다.
    fn lastFrom(self: *const Strip, l: u16, f: usize) usize {
        var k = f;
        while (k + 1 < self.len and self.spanCells(l, f, k + 1) <= l) k += 1;
        return k;
    }

    /// 정확히 둘이고 둘 다 `half`인가(design 결정 22) — `share`로 나누는 갈래다.
    fn bothHalf(self: *const Strip) bool {
        return self.len == 2 and self.cols[0].width == .half and self.cols[1].width == .half;
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
