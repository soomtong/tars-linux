//! 패널 트리와 사각형 산수(WP design 결정 2).
//!
//! 순수 모듈이다. 시스템 콜도 ghostty도 프레임버퍼도 모른다 — `status.zig`가
//! 따로 서는 이유(IS 결정 5)와 같다. 그래서 `layout_test`가 컨테이너에서
//! 초 단위로 돌고, 분할 여덟 · 닫기 · 순환을 부팅 없이 본다.
//!
//! 좌표는 전부 셀 단위다. 픽셀로 옮기는 것은 `main.zig`의 몫이다.

/// 격자 안의 사각형. 셀 단위이고 `col` · `row`가 왼쪽 위다.
pub const Rect = struct { col: u16, row: u16, cols: u16, rows: u16 };

/// 격자 칸 하나가 어느 잎의 어느 칸인가(PD design 결정 5). `col` · `row`는
/// 그 잎의 사각형 안의 상대 칸이다 — 패널의 `vt.Screen`이 아는 좌표다.
pub const Hit = struct { leaf: u4, col: u16, row: u16 };

/// 새 패널이 어느 쪽에 서는가. 오른쪽(세로 구분선) 또는 아래(가로 구분선).
pub const Dir = enum { right, below };

/// 워크스페이스 하나의 패널 수 상한. 잎 번호가 0..7이고 `main.zig`의
/// 패널 배열이 이 번호로 바로 인덱싱된다.
pub const MAX_LEAVES = 8;

/// 잎 여덟을 가진 이진 트리의 노드 수 = 잎 8 + 내부 7.
const MAX_NODES = 2 * MAX_LEAVES - 1;

/// 노드 하나. 잎은 노드 번호가 아니라 잎 번호를 든다.
///
/// 노드 번호와 잎 번호를 가른 이유는 분할 때문이다. 잎을 가르면 그 노드가
/// 내부 노드가 되고 옛 잎은 새 노드로 내려간다(`split` 주석). 노드 번호를
/// 패널의 이름으로 쓰면 분할할 때마다 기존 패널의 이름이 바뀌고, 그것을
/// 들고 있던 `main.zig`의 포커스가 조용히 다른 패널을 가리킨다.
const Node = union(enum) {
    free,
    leaf: u4,
    split: struct { dir: Dir, first: u4, second: u4 },
};

pub const Tree = struct {
    // 노드 풀은 고정이다. 잎 8 + 내부 7 = 15. 동적 할당이 없고 "언제
    // 해제하는가"가 없다 — find_buf가 128바이트 고정인 것과 같은 판단.
    nodes: [MAX_NODES]Node,
    /// 뿌리 노드의 번호. 마지막 잎을 지우면 null이다.
    root: ?u4,

    /// 잎 0 하나짜리 트리. 부팅의 모양이다.
    pub fn init() Tree {
        var t: Tree = .{ .nodes = @splat(.free), .root = 0 };
        t.nodes[0] = .{ .leaf = 0 };
        return t;
    }

    /// 잎 `leaf`를 둘로 가르고 새 잎의 번호를 돌려준다. 옛 잎이 왼쪽(위),
    /// 새 잎이 오른쪽(아래)이다.
    ///
    /// null인 경우가 둘이다. 잎이 이미 여덟이거나, 그 잎의 사각형이 가를
    /// 수 없을 만큼 작다(가르는 방향의 길이가 3 미만 — 구분선 한 칸과
    /// 양쪽 한 칸씩). 크기를 보려면 격자 전체가 있어야 해서 `whole`을 받는다.
    ///
    /// 옛 잎의 노드를 그 자리에서 내부 노드로 바꾸고, 옛 잎과 새 잎을 빈
    /// 노드 둘로 내린다. 그러면 부모가 가리키던 번호가 그대로라 부모를 고칠
    /// 일이 없다.
    pub fn split(self: *Tree, leaf: u4, dir: Dir, whole: Rect) ?u4 {
        if (self.count() >= MAX_LEAVES) return null;
        const at = self.findLeaf(leaf) orelse return null;

        var rs: [MAX_LEAVES]Rect = undefined;
        self.rects(whole, &rs);
        const len = switch (dir) {
            .right => rs[leaf].cols,
            .below => rs[leaf].rows,
        };
        if (len < 3) return null;

        const new_leaf = self.freeLeaf();
        const a = self.freeNode(null);
        const b = self.freeNode(a);
        self.nodes[a] = .{ .leaf = leaf };
        self.nodes[b] = .{ .leaf = new_leaf };
        self.nodes[at] = .{ .split = .{ .dir = dir, .first = a, .second = b } };
        return new_leaf;
    }

    /// 잎 `leaf`를 지운다. 형제가 부모 자리로 올라간다 — 부모 노드를
    /// 형제의 내용으로 덮고 형제의 옛 노드를 비운다. 그러면 할아버지가
    /// 가리키던 번호가 그대로다(`split`과 같은 수).
    ///
    /// 마지막 잎이면 트리가 빈다(`root == null`). 없는 잎이면 아무 일도 안
    /// 한다.
    pub fn remove(self: *Tree, leaf: u4) void {
        const at = self.findLeaf(leaf) orelse return;
        const parent = self.findParent(at) orelse {
            self.nodes[at] = .free;
            self.root = null;
            return;
        };
        const s = self.nodes[parent].split;
        const sibling = if (s.first == at) s.second else s.first;
        self.nodes[parent] = self.nodes[sibling];
        self.nodes[sibling] = .free;
        self.nodes[at] = .free;
    }

    /// 잎마다 사각형을 `out[잎 번호]`에 쓴다. 없는 잎의 칸은 안 건드린다 —
    /// 부르는 쪽은 패널 배열의 null로 그것을 안다.
    ///
    /// 가로 `n`칸을 세로로 가르면 구분선 한 칸을 빼고
    /// `first = (n - 1) / 2`, `second = n - 1 - first`다. 홀수 나머지는
    /// 오른쪽(아래)으로 간다. 비율이 없다 — 드래그가 없는 시스템에서 비율은
    /// 영영 1/2이다.
    pub fn rects(self: *const Tree, whole: Rect, out: []Rect) void {
        const root = self.root orelse return;
        self.fill(root, whole, out);
    }

    /// 구분선 사각형을 `out`에 담고 그 앞부분을 돌려준다. 내부 노드마다
    /// 하나이고 순서는 트리의 앞 순회다. `out`은 `MAX_LEAVES - 1`칸이면
    /// 언제나 넉넉하다.
    ///
    /// 패널 사각형과 따로 꺼내는 이유가 WP-M1 plan 확정 4다. `cells()`는
    /// 글자도 색도 없는 셀을 안 내보내므로, 격자를 통째로 구분선 색으로
    /// 칠하고 패널이 덮게 두면 패널 안의 빈 칸이 구분선 색으로 남는다.
    ///
    /// 세로 분할이면 `first`의 바로 오른쪽 한 칸 폭에 부모 높이 전체,
    /// 가로 분할이면 `first`의 바로 아래 한 줄에 부모 폭 전체다.
    pub fn separators(self: *const Tree, whole: Rect, out: []Rect) []Rect {
        var n: usize = 0;
        if (self.root) |root| self.collectSeparators(root, whole, out, &n);
        return out[0..n];
    }

    /// 다음 잎. 트리의 왼쪽→오른쪽(위→아래) 순이고 끝에서 처음으로 감긴다.
    pub fn next(self: *const Tree, leaf: u4) u4 {
        var buf: [MAX_LEAVES]u4 = undefined;
        const order = self.leaves(&buf);
        const i = indexOf(order, leaf) orelse return leaf;
        return order[(i + 1) % order.len];
    }

    /// 이전 잎. `next`의 반대 방향이고 처음에서 끝으로 감긴다.
    pub fn prev(self: *const Tree, leaf: u4) u4 {
        var buf: [MAX_LEAVES]u4 = undefined;
        const order = self.leaves(&buf);
        const i = indexOf(order, leaf) orelse return leaf;
        return order[(i + order.len - 1) % order.len];
    }

    /// 잎 `leaf`를 지우면 그 자리를 넘겨받는 잎(WP-M2). 패널을 닫은 뒤
    /// 포커스가 갈 곳이다.
    ///
    /// `remove`는 형제 서브트리를 부모 자리로 올린다. 그 서브트리 안에서
    /// 닫힌 잎에 가장 가까운 잎이 받는다 — 잎이 부모의 `second`면 형제는
    /// 왼쪽(위)이라 순회의 `prev`가 그 마지막 잎이고, `first`면 `next`가
    /// 오른쪽(아래) 서브트리의 첫 잎이다. 형제가 있으면 둘 다 감기지 않는다.
    ///
    /// 순회의 `next`를 쓰던 M1은 0 | (1 / 2)에서 2를 닫으면 0으로 감겼다.
    /// 사람에게는 화면에서 커진 쪽(1)으로 가는 것이 맞다(iTerm2와 같다).
    ///
    /// 부모가 없으면(잎 하나) 자기 자신이다. `remove` 앞에 불러야 한다 —
    /// 지운 뒤에는 그 잎이 트리에 없다.
    pub fn heir(self: *const Tree, leaf: u4) u4 {
        const at = self.findLeaf(leaf) orelse return leaf;
        const parent = self.findParent(at) orelse return leaf;
        return if (self.nodes[parent].split.second == at) self.prev(leaf) else self.next(leaf);
    }

    /// 격자 칸 `(col, row)`가 든 잎과 그 안의 상대 칸(PD design 결정 5).
    /// 포인터가 가리키는 패널을 고르는 자리다.
    ///
    /// null이 둘이다. 구분선 칸은 어느 잎의 사각형에도 안 들어가고(`halves`가
    /// 구분선을 두 잎 사이에 따로 둔다), 격자 밖 칸은 `whole` 밖이다. 픽셀을
    /// 격자 칸으로 바꾸는 것은 `main.zig`다 — 이 파일은 셀 단위만 안다.
    ///
    /// 사각형은 `rects`로 얻는다. 같은 산수를 여기서 다시 하면 언젠가 한 칸
    /// 어긋나고, 그 어긋남은 "구분선 위를 가리켰는데 왼쪽 패널이 움직인다"로
    /// 나타난다.
    pub fn hit(self: *const Tree, whole: Rect, col: u16, row: u16) ?Hit {
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

    /// 잎의 수.
    pub fn count(self: *const Tree) usize {
        var n: usize = 0;
        for (self.nodes) |node| {
            if (node == .leaf) n += 1;
        }
        return n;
    }

    fn fill(self: *const Tree, at: u4, r: Rect, out: []Rect) void {
        switch (self.nodes[at]) {
            .free => {},
            .leaf => |leaf| out[leaf] = r,
            .split => |s| {
                const h = halves(r, s.dir);
                self.fill(s.first, h.first, out);
                self.fill(s.second, h.second, out);
            },
        }
    }

    fn collectSeparators(self: *const Tree, at: u4, r: Rect, out: []Rect, n: *usize) void {
        switch (self.nodes[at]) {
            .free, .leaf => {},
            .split => |s| {
                const h = halves(r, s.dir);
                out[n.*] = h.separator;
                n.* += 1;
                self.collectSeparators(s.first, h.first, out, n);
                self.collectSeparators(s.second, h.second, out, n);
            },
        }
    }

    /// 잎 번호를 트리의 왼쪽→오른쪽 순으로 `buf`에 담는다.
    fn leaves(self: *const Tree, buf: *[MAX_LEAVES]u4) []u4 {
        var n: usize = 0;
        if (self.root) |root| self.walk(root, buf, &n);
        return buf[0..n];
    }

    fn walk(self: *const Tree, at: u4, buf: *[MAX_LEAVES]u4, n: *usize) void {
        switch (self.nodes[at]) {
            .free => {},
            .leaf => |leaf| {
                buf[n.*] = leaf;
                n.* += 1;
            },
            .split => |s| {
                self.walk(s.first, buf, n);
                self.walk(s.second, buf, n);
            },
        }
    }

    fn findLeaf(self: *const Tree, leaf: u4) ?u4 {
        for (self.nodes, 0..) |node, i| {
            if (node == .leaf and node.leaf == leaf) return @intCast(i);
        }
        return null;
    }

    fn findParent(self: *const Tree, at: u4) ?u4 {
        for (self.nodes, 0..) |node, i| {
            if (node == .split and (node.split.first == at or node.split.second == at))
                return @intCast(i);
        }
        return null;
    }

    /// 쓰이지 않은 가장 작은 잎 번호. `split`이 잎 수를 먼저 보므로 언제나
    /// 있다.
    fn freeLeaf(self: *const Tree) u4 {
        var used = [_]bool{false} ** MAX_LEAVES;
        for (self.nodes) |node| {
            if (node == .leaf) used[node.leaf] = true;
        }
        for (used, 0..) |u, i| {
            if (!u) return @intCast(i);
        }
        unreachable;
    }

    /// 빈 노드 하나. `skip`은 방금 고른 노드다 — 아직 `.free`인 채로 있어서
    /// 건너뛰지 않으면 같은 번호를 두 번 준다. 잎이 일곱 이하면 빈 노드가
    /// 둘 이상 있다(잎 k개는 노드 2k-1개를 쓴다).
    fn freeNode(self: *const Tree, skip: ?u4) u4 {
        for (self.nodes, 0..) |node, i| {
            if (node == .free and (skip == null or skip.? != i)) return @intCast(i);
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
/// 한다 — `split`이 그보다 작은 잎을 안 만든다.
pub fn clampInto(r: Rect, leaf: u4, col: u16, row: u16) Hit {
    const c = @min(@max(col, r.col), r.col + r.cols - 1);
    const w = @min(@max(row, r.row), r.row + r.rows - 1);
    return .{ .leaf = leaf, .col = c - r.col, .row = w - r.row };
}

/// 사각형 하나를 둘과 구분선으로 가른다. `fill`과 `separators`가 같은
/// 산수를 따로 하면 언젠가 한 칸 어긋난다 — 그 어긋남은 "구분선이 패널
/// 위에 그려진다"로 나타나고 `layout_test`의 검사 10이 본다.
fn halves(r: Rect, dir: Dir) struct { first: Rect, second: Rect, separator: Rect } {
    var a = r;
    var b = r;
    var sep = r;
    switch (dir) {
        .right => {
            a.cols = (r.cols - 1) / 2;
            b.cols = r.cols - 1 - a.cols;
            b.col = r.col + a.cols + 1;
            sep.col = r.col + a.cols;
            sep.cols = 1;
        },
        .below => {
            a.rows = (r.rows - 1) / 2;
            b.rows = r.rows - 1 - a.rows;
            b.row = r.row + a.rows + 1;
            sep.row = r.row + a.rows;
            sep.rows = 1;
        },
    }
    return .{ .first = a, .second = b, .separator = sep };
}

fn indexOf(order: []const u4, leaf: u4) ?usize {
    for (order, 0..) |l, i| {
        if (l == leaf) return i;
    }
    return null;
}
