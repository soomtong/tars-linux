//! `tars-files`의 순수 모델(TK-M3 plan 확정 10 · 11 · 12). 파일 시스템도 툴킷도 모른다 — 항목은 `DirSource`가 조각으로 주고(게스트는
//! getdents64, 호스트 검사는 메모리 표), 이 파일은 거르기 · 정렬 · 병합 · 선택을 따라가는 셈만 한다.
//!
//! 순서(확정 11): 디렉터리 먼저, 그 안에서 자연 정렬 — 숫자 덩어리는 값으로(`a2` < `a10`, 앞의 0은 값에 안 든다), ASCII 글자는 대소문자를
//! 무시하고, 그 밖의 바이트(한글 등 UTF-8)는 바이트 순이다(한글 음절은 코드 포인트가 가나다 순이라 바이트 순이 곧 가나다 순). 그래도 같으면
//! 바이트 순으로 가른다 — 같은 디렉터리 안에서 이름은 유일하니 순서는 전순서다(이분 탐색이 기대는 성질).
//! 숨김(`.`으로 시작 — `.` · `..` 포함)은 뺀다.
//!
//! 로딩(확정 9): `Listing`이 조각 하나를 받으면 걸러 이름을 복사하고, 조각만 정렬한 뒤 이미 정렬된 목록과 병합한다(O(n + k)). 받은 만큼
//! 바로 보일 수 있다.
//!
//! 선택(확정 10 · 12): 열쇠는 이름이다. `follow`가 목록이 바뀐 뒤의 선택 색인과 오프셋을 셈한다 — 첫 로딩에서 사용자가 선택을 건드리지
//! 않았으면 늘 0행, 건드렸거나 갱신이면 옛 선택 이름을 새 목록에서 찾는다(없으면 삽입 자리, 끝을 넘으면 마지막, 0행이면 선택 없음).
//! 스크롤은 선택 행의 화면 위치를 지킨다(선택이 화면 밖이었으면 오프셋 그대로 — 자르기만).

const std = @import("std");

pub const Kind = enum(u8) { dir, file };

pub const Entry = struct {
    name: []const u8,
    kind: Kind,
};

/// 소스가 주는 날 항목 하나(이름은 다음 `next`까지만 산다).
pub const Raw = Entry;

/// 디렉터리를 조각으로 읽는 곳. `open`이 준 손잡이로 `next`를 부르면 조각 하나(빈 조각도 된다), 끝이면 null. `close`는 끝났든 아니든
/// 한 번(취소).
pub const DirSource = struct {
    ctx: *anyopaque,
    open: *const fn (ctx: *anyopaque, path: []const u8) anyerror!*anyopaque,
    next: *const fn (ctx: *anyopaque, handle: *anyopaque) anyerror!?[]const Raw,
    close: *const fn (ctx: *anyopaque, handle: *anyopaque) void,
};

pub fn hidden(name: []const u8) bool {
    return name.len == 0 or name[0] == '.';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

/// 자연 순서(대소문자 무시 · 숫자 덩어리는 값). 같으면 바이트 순.
pub fn naturalOrder(a: []const u8, b: []const u8) std.math.Order {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (isDigit(a[i]) and isDigit(b[j])) {
            while (i < a.len and a[i] == '0') i += 1;
            while (j < b.len and b[j] == '0') j += 1;
            const si = i;
            const sj = j;
            while (i < a.len and isDigit(a[i])) i += 1;
            while (j < b.len and isDigit(b[j])) j += 1;
            const la = i - si;
            const lb = j - sj;
            if (la != lb) return std.math.order(la, lb);
            const o = std.mem.order(u8, a[si..i], b[sj..j]);
            if (o != .eq) return o;
            continue;
        }
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[j]);
        if (ca != cb) return std.math.order(ca, cb);
        i += 1;
        j += 1;
    }
    if (i < a.len) return .gt;
    if (j < b.len) return .lt;
    return std.mem.order(u8, a, b);
}

pub fn order(a: Entry, b: Entry) std.math.Order {
    if (a.kind != b.kind) return if (a.kind == .dir) .lt else .gt;
    return naturalOrder(a.name, b.name);
}

pub fn lessThan(_: void, a: Entry, b: Entry) bool {
    return order(a, b) == .lt;
}

/// 정렬된 `entries`에서 `e`가 들어갈 자리(같은 것이 있으면 그 자리).
pub fn lowerBound(entries: []const Entry, e: Entry) usize {
    var lo: usize = 0;
    var hi: usize = entries.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (order(entries[mid], e) == .lt) lo = mid + 1 else hi = mid;
    }
    return lo;
}

/// 이름 `name`의 자리. 같은 종류로 먼저 찾고(이분 탐색), 없으면 종류가 바뀐 것(파일 ↔ 디렉터리)을 찾는다.
pub fn find(entries: []const Entry, e: Entry) ?usize {
    const i = lowerBound(entries, e);
    if (i < entries.len and entries[i].kind == e.kind and std.mem.eql(u8, entries[i].name, e.name)) return i;
    const other: Entry = .{ .name = e.name, .kind = if (e.kind == .dir) .file else .dir };
    const k = lowerBound(entries, other);
    if (k < entries.len and entries[k].kind == other.kind and std.mem.eql(u8, entries[k].name, e.name)) return k;
    return null;
}

pub const State = enum { loading, done, failed };

/// 디렉터리 하나의 항목(정렬됨). 이름은 목록의 아레나에 산다 — 항목 배열이 늘어도 이름 포인터는 그대로다.
pub const Listing = struct {
    alloc: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,
    /// 조각 정렬용 임시(조각마다 다시 쓴다).
    chunk: std.ArrayList(Entry) = .empty,
    state: State = .loading,
    chunks: u32 = 0,

    pub fn init(alloc: std.mem.Allocator) Listing {
        return .{ .alloc = alloc, .arena = std.heap.ArenaAllocator.init(alloc) };
    }

    pub fn deinit(self: *Listing) void {
        self.entries.deinit(self.alloc);
        self.chunk.deinit(self.alloc);
        self.arena.deinit();
    }

    pub fn items(self: *const Listing) []const Entry {
        return self.entries.items;
    }

    /// 조각 하나: 숨김을 거르고 이름을 복사해 조각만 정렬한 뒤 병합한다. 더한 항목 수를 돌려준다.
    pub fn addChunk(self: *Listing, raws: []const Raw) !usize {
        self.chunks += 1;
        self.chunk.clearRetainingCapacity();
        const a = self.arena.allocator();
        for (raws) |r| {
            if (hidden(r.name)) continue;
            try self.chunk.append(self.alloc, .{ .name = try a.dupe(u8, r.name), .kind = r.kind });
        }
        const k = self.chunk.items.len;
        if (k == 0) return 0;
        std.sort.pdq(Entry, self.chunk.items, {}, lessThan);
        // 뒤에서부터 병합(제자리, O(n + k)).
        const n = self.entries.items.len;
        try self.entries.resize(self.alloc, n + k);
        const dst = self.entries.items;
        const src = self.chunk.items;
        var i: usize = n; // 옛 목록의 남은 끝(넣지 않음)
        var j: usize = k; // 조각의 남은 끝
        var w: usize = n + k;
        while (j > 0) {
            w -= 1;
            if (i > 0 and order(dst[i - 1], src[j - 1]) == .gt) {
                dst[w] = dst[i - 1];
                i -= 1;
            } else {
                dst[w] = src[j - 1];
                j -= 1;
            }
        }
        return k;
    }
};

/// 소스 하나를 끝까지 읽어 목록 하나로(호스트 검사 · 측정용 — 앱은 조각마다 돌린다).
pub fn readAll(alloc: std.mem.Allocator, src: DirSource, path: []const u8) !Listing {
    var l = Listing.init(alloc);
    errdefer l.deinit();
    const h = try src.open(src.ctx, path);
    defer src.close(src.ctx, h);
    while (try src.next(src.ctx, h)) |raws| _ = try l.addChunk(raws);
    l.state = .done;
    return l;
}

// ── 선택 따라가기(확정 10 · 12) ───────────────────────────────────────

/// 목록이 바뀌기 전의 선택과 스크롤.
pub const Before = struct {
    /// 옛 선택 항목(0행이었으면 null). 이름은 옛 목록에 산다 — `follow`가 끝날 때까지 살아 있어야 한다.
    sel: ?Entry,
    index: usize,
    offset: u64,
    /// 사용자가 이 열의 선택을 키 · 클릭으로 건드렸다(첫 로딩에서만 뜻이 있다 — 갱신은 늘 참으로 부른다).
    touched: bool,
};

pub const After = struct {
    /// 새 선택 색인. 0행이면 null.
    index: ?usize,
    offset: u64,
    /// 옛 선택 이름이 새 목록에 없다.
    gone: bool,
};

/// 행 높이 `row_h` · 뷰 높이 `view_h`의 리스트에서 목록이 `entries`로 바뀐 뒤의 선택 · 오프셋.
pub fn follow(before: Before, entries: []const Entry, view_h: u64, row_h: u64) After {
    const n = entries.len;
    const content = @as(u64, n) * row_h;
    const max_off = if (content > view_h) content - view_h else 0;
    if (n == 0) return .{ .index = null, .offset = 0, .gone = before.sel != null };
    if (!before.touched or before.sel == null) {
        return .{ .index = 0, .offset = @min(before.offset, max_off), .gone = false };
    }
    const sel = before.sel.?;
    var gone = false;
    const idx = find(entries, sel) orelse blk: {
        gone = true;
        break :blk @min(lowerBound(entries, sel), n - 1);
    };
    // 옛 선택 행이 화면에 (일부라도) 보였으면 그 화면 위치를 지킨다.
    const old_top = @as(u64, before.index) * row_h;
    const visible = old_top + row_h > before.offset and old_top < before.offset + view_h;
    var off: u64 = before.offset;
    if (visible) {
        const screen: i64 = @as(i64, @intCast(old_top)) - @as(i64, @intCast(before.offset));
        const want: i64 = @as(i64, @intCast(@as(u64, idx) * row_h)) - screen;
        off = if (want < 0) 0 else @intCast(want);
    }
    return .{ .index = idx, .offset = @min(off, max_off), .gone = gone };
}

/// 경로 `dir` 아래 `name`(`dir`이 `/`면 `/name`). `buf`에 쓴다.
pub fn join(buf: []u8, dir: []const u8, name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, dir, "/")) return std.fmt.bufPrint(buf, "/{s}", .{name});
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ dir, name });
}

// ── 경로 입력(TK-M4 plan 확정 14) ────────────────────────────────────

pub const PathError = error{ Empty, NoHome, TooLong, TooDeep };

/// 경로 필드의 글을 절대 경로로: `~` · `~/…`는 `home`, `/`로 시작하면 그대로, 아니면 `base`(포커스 열) 기준. `.` · 빈 성분 · 겹친 `/`는
/// 버리고 `..`는 하나 올라간다(뿌리에서는 그대로). 끝 `/`는 뗀다(뿌리는 `/`). 앞뒤 공백은 뗀다. `buf`에 쓴다.
pub fn resolvePath(buf: []u8, text: []const u8, base: []const u8, home: ?[]const u8) PathError![]const u8 {
    const t = std.mem.trim(u8, text, " \t");
    if (t.len == 0) return error.Empty;
    var raw_buf: [8192]u8 = undefined;
    var raw: []const u8 = undefined;
    if (t[0] == '~' and (t.len == 1 or t[1] == '/')) {
        const h = home orelse return error.NoHome;
        raw = std.fmt.bufPrint(&raw_buf, "{s}/{s}", .{ h, t[1..] }) catch return error.TooLong;
    } else if (t[0] == '/') {
        raw = t;
    } else {
        raw = std.fmt.bufPrint(&raw_buf, "{s}/{s}", .{ base, t }) catch return error.TooLong;
    }
    var parts: [512][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, raw, '/');
    while (it.next()) |p| {
        if (p.len == 0 or std.mem.eql(u8, p, ".")) continue;
        if (std.mem.eql(u8, p, "..")) {
            if (n > 0) n -= 1;
            continue;
        }
        if (n >= parts.len) return error.TooDeep;
        parts[n] = p;
        n += 1;
    }
    if (n == 0) {
        if (buf.len < 1) return error.TooLong;
        buf[0] = '/';
        return buf[0..1];
    }
    var len: usize = 0;
    for (parts[0..n]) |p| {
        if (len + 1 + p.len > buf.len) return error.TooLong;
        buf[len] = '/';
        @memcpy(buf[len + 1 .. len + 1 + p.len], p);
        len += 1 + p.len;
    }
    return buf[0..len];
}

/// 열을 다시 세울 경로들(정규화된 절대 경로 `target`의 조상들): `target`이 `start`(열 0의 경로)이거나 그 안이면 `start`부터, 아니면 `/`부터
/// 성분마다 하나. 조각은 `target`(또는 `/` 글자)을 가리킨다. 32(열 풀)를 넘으면 `error.TooDeep`.
pub fn columnPaths(start: []const u8, target: []const u8, out: [][]const u8) PathError![]const []const u8 {
    const inside = std.mem.eql(u8, start, "/") or std.mem.eql(u8, target, start) or
        (std.mem.startsWith(u8, target, start) and target.len > start.len and target[start.len] == '/');
    var n: usize = 0;
    var from: usize = undefined;
    if (inside and !std.mem.eql(u8, start, "/")) {
        out[0] = target[0..start.len];
        from = start.len;
    } else {
        out[0] = "/";
        from = 0;
    }
    n = 1;
    if (std.mem.eql(u8, target, "/")) return out[0..1];
    var i = from + 1;
    while (i <= target.len) : (i += 1) {
        if (i == target.len or target[i] == '/') {
            if (i > from + 1 or (from == 0 and i > 1)) {
                if (n >= out.len) return error.TooDeep;
                out[n] = target[0..i];
                n += 1;
            }
            from = i;
        }
    }
    return out[0..n];
}

/// 경로의 마지막 성분(`/`면 빈 글).
pub fn basename(path: []const u8) []const u8 {
    const k = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[k + 1 ..];
}

/// 경로의 부모(`/a`의 부모는 `/`, `/`의 부모는 `/`).
pub fn dirname(path: []const u8) []const u8 {
    const k = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return if (k == 0) "/" else path[0..k];
}
