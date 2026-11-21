//! `tars-files`의 검색(`Cmd+K`, R-FM-4, TK-M4 plan 확정 20) — 순수하다(호스트 검사가 가짜 `DirSource`와 주입한 시계로 돈다).
//!
//! 걷기(`Walker`): 뿌리(열 0의 경로)에서 너비 우선, `step` 한 번 = `DirSource.next` 한 번(getdents 한 번 — 창 층 `Handler.idle`의 한 조각). 숨김(`.` 시작)은 빼고,
//! 링크는 따라가지 않는다(디렉터리를 가리켜도 내려가지 않는다 — 고리가 없다). 뿌리가 `/`면 맨 위의 `proc` · `sys` · `dev` · `run`을 뺀다. 상한은 20만 항목 · 10초
//! (넘으면 `capped`). 항목은 뿌리 기준 상대 경로(`a/b/x.txt`)로 한 아레나에 쌓인다.
//!
//! 일치(`score`): 질의가 상대 경로의 부분열이면 후보(코드포인트 단위 — ASCII는 대소문자 무시, 한글 등은 그대로). 이름(마지막 성분) 안에서 다 맞으면 이름 일치로
//! 크게 가산하고, 연속한 짝 · 성분 처음에 맞은 글자마다 가산, 경로 바이트 길이만큼 감산(짧은 경로 우대). 같은 점수는 경로 바이트 순 — 전순서라 결과가 결정적이다.
//!
//! 상위 100(`Top`): 정렬된 배열에 끼워 넣기. 질의가 앞을 이으면(`setQuery`) 지난 후보만 다시 거르고, 걷기가 들여온 새 항목은 `scanNew`가 그 질의로 본다 —
//! 처음부터 매긴 것과 같은 결과다(호스트 표).

const std = @import("std");
/// 모델도 내보낸다 — 호스트 검사가 이 모듈 하나로 둘을 받는다(같은 파일이 두 모듈에 들 수 없다).
pub const model = @import("model.zig");

pub const MAX_ENTRIES: usize = 200_000;
pub const MAX_MS: u64 = 10_000;
pub const TOP: usize = 100;
/// 뿌리가 `/`일 때 맨 위에서 빼는 이름.
pub const EXCLUDED = [_][]const u8{ "proc", "sys", "dev", "run" };

pub const Clock = struct {
    ctx: *anyopaque,
    now_ms: *const fn (ctx: *anyopaque) u64,
};

pub const Item = struct {
    /// `Walker.paths`의 상대 경로 범위.
    off: u32,
    len: u32,
    /// 마지막 성분의 시작(상대 경로 안).
    name: u32,
    kind: model.Kind,
};

pub const Walker = struct {
    alloc: std.mem.Allocator,
    src: model.DirSource,
    clock: Clock,
    root_buf: [4096]u8 = undefined,
    root_len: usize = 0,
    paths: std.ArrayList(u8) = .empty,
    items: std.ArrayList(Item) = .empty,
    /// 아직 읽지 않은 디렉터리(`items`의 색인). 뿌리는 `started`가 거짓일 때 먼저.
    queue: std.ArrayList(u32) = .empty,
    qhead: usize = 0,
    started: bool = false,
    handle: ?*anyopaque = null,
    /// 지금 읽는 디렉터리(`items`의 색인, 뿌리면 null).
    cur: ?u32 = null,
    t0: u64 = 0,
    done: bool = false,
    capped: bool = false,
    ms: u64 = 0,

    pub fn init(alloc: std.mem.Allocator, src: model.DirSource, clock: Clock, root_path: []const u8) Walker {
        var w: Walker = .{ .alloc = alloc, .src = src, .clock = clock };
        const n = @min(root_path.len, w.root_buf.len);
        @memcpy(w.root_buf[0..n], root_path[0..n]);
        w.root_len = n;
        w.t0 = clock.now_ms(clock.ctx);
        return w;
    }

    pub fn deinit(self: *Walker) void {
        self.stop();
        self.paths.deinit(self.alloc);
        self.items.deinit(self.alloc);
        self.queue.deinit(self.alloc);
    }

    pub fn root(self: *const Walker) []const u8 {
        return self.root_buf[0..self.root_len];
    }

    pub fn path(self: *const Walker, i: u32) []const u8 {
        const it = self.items.items[i];
        return self.paths.items[it.off .. it.off + it.len];
    }

    pub fn name(self: *const Walker, i: u32) []const u8 {
        const it = self.items.items[i];
        return self.paths.items[it.off + it.name .. it.off + it.len];
    }

    /// 걷기를 멈춘다(열린 디렉터리를 닫는다).
    pub fn stop(self: *Walker) void {
        if (self.handle) |h| self.src.close(self.src.ctx, h);
        self.handle = null;
        self.done = true;
    }

    fn finish(self: *Walker, capped: bool) void {
        self.capped = capped;
        self.ms = self.clock.now_ms(self.clock.ctx) - self.t0;
        self.stop();
    }

    /// 한 조각. 할 일이 남았으면 참.
    pub fn step(self: *Walker) bool {
        if (self.done) return false;
        if (self.clock.now_ms(self.clock.ctx) - self.t0 >= MAX_MS) {
            self.finish(true);
            return false;
        }
        if (self.handle == null) {
            var pbuf: [8192]u8 = undefined;
            const full = blk: {
                if (!self.started) {
                    self.started = true;
                    self.cur = null;
                    break :blk self.root();
                }
                if (self.qhead >= self.queue.items.len) {
                    self.finish(false);
                    return false;
                }
                const d = self.queue.items[self.qhead];
                self.qhead += 1;
                self.cur = d;
                const rel = self.path(d);
                const r = self.root();
                break :blk (if (std.mem.eql(u8, r, "/"))
                    std.fmt.bufPrint(&pbuf, "/{s}", .{rel})
                else
                    std.fmt.bufPrint(&pbuf, "{s}/{s}", .{ r, rel })) catch return true;
            };
            self.handle = self.src.open(self.src.ctx, full) catch return true;
        }
        const raws = self.src.next(self.src.ctx, self.handle.?) catch null;
        const rs = raws orelse {
            self.src.close(self.src.ctx, self.handle.?);
            self.handle = null;
            return true;
        };
        const at_root = self.cur == null;
        const root_slash = std.mem.eql(u8, self.root(), "/");
        for (rs) |r| {
            if (model.hidden(r.name)) continue;
            if (at_root and root_slash and excluded(r.name)) continue;
            if (self.items.items.len >= MAX_ENTRIES) {
                self.finish(true);
                return false;
            }
            self.add(r) catch {
                self.finish(true);
                return false;
            };
        }
        return true;
    }

    fn add(self: *Walker, r: model.Raw) !void {
        const off: u32 = @intCast(self.paths.items.len);
        var name_at: u32 = 0;
        if (self.cur) |d| {
            const parent = self.path(d);
            // `path`는 아레나를 가리킨다 — 늘리기 전에 길이를 잡고 늘린 뒤 다시 복사한다.
            const plen = parent.len;
            const poff = self.items.items[d].off;
            try self.paths.ensureUnusedCapacity(self.alloc, plen + 1 + r.name.len);
            self.paths.appendSliceAssumeCapacity(self.paths.items[poff .. poff + plen]);
            self.paths.appendAssumeCapacity('/');
            name_at = @intCast(plen + 1);
        }
        try self.paths.appendSlice(self.alloc, r.name);
        const len: u32 = @intCast(self.paths.items.len - off);
        try self.items.append(self.alloc, .{ .off = off, .len = len, .name = name_at, .kind = r.kind });
        if (r.kind == .dir and !r.link) try self.queue.append(self.alloc, @intCast(self.items.items.len - 1));
    }
};

fn excluded(n: []const u8) bool {
    for (EXCLUDED) |e| if (std.mem.eql(u8, e, n)) return true;
    return false;
}

// ── 일치 · 점수 ─────────────────────────────────────────────────────

const Cp = struct { cp: u32, len: usize };

/// 코드포인트 하나(잘못된 바이트는 0x110000 + 바이트 — 그 바이트와만 맞는다). ASCII는 소문자로.
fn cpAt(s: []const u8, i: usize) Cp {
    const n = std.unicode.utf8ByteSequenceLength(s[i]) catch return .{ .cp = 0x110000 + @as(u32, s[i]), .len = 1 };
    if (i + n > s.len) return .{ .cp = 0x110000 + @as(u32, s[i]), .len = 1 };
    const cp = std.unicode.utf8Decode(s[i .. i + n]) catch return .{ .cp = 0x110000 + @as(u32, s[i]), .len = 1 };
    const c: u32 = cp;
    return .{ .cp = if (c < 0x80) std.ascii.toLower(@intCast(c)) else c, .len = n };
}

/// `q`가 `s[from..]`의 부분열이면 맞은 글자 수의 가산(연속 · 성분 처음)을, 아니면 null. 왼쪽부터 탐욕으로 맞춘다.
fn subseq(s: []const u8, from: usize, q: []const u8) ?i32 {
    var i = from;
    var j: usize = 0;
    var bonus: i32 = 0;
    var last_end: ?usize = null;
    while (j < q.len) {
        const qc = cpAt(q, j);
        while (true) {
            if (i >= s.len) return null;
            const sc = cpAt(s, i);
            if (sc.cp == qc.cp) {
                if (last_end) |e| if (e == i) {
                    bonus += 10;
                };
                if (i == 0 or s[i - 1] == '/') bonus += 15;
                i += sc.len;
                last_end = i;
                break;
            }
            i += sc.len;
        }
        j += qc.len;
    }
    return bonus;
}

/// 점수(plan 확정 20). 후보가 아니면 null. 빈 질의는 후보가 없다.
pub fn score(rel: []const u8, name_at: usize, q: []const u8) ?i32 {
    if (q.len == 0) return null;
    const len: i32 = @intCast(@min(rel.len, 100_000));
    if (subseq(rel, name_at, q)) |b| return 1000 + b - len;
    if (subseq(rel, 0, q)) |b| return b - len;
    return null;
}

// ── 상위 100 · 검색 상태 ───────────────────────────────────────────

pub const Hit = struct { item: u32, score: i32 };

pub const Search = struct {
    alloc: std.mem.Allocator,
    walker: Walker,
    query_buf: [256]u8 = undefined,
    query_len: usize = 0,
    /// 지금 질의에 맞은 항목(`items`의 색인, 들여온 순서).
    cands: std.ArrayList(u32) = .empty,
    /// 지금 질의로 본 항목 수(그 뒤의 것은 `scanNew`가 본다).
    scanned: usize = 0,
    top: [TOP]Hit = undefined,
    top_n: usize = 0,

    pub fn init(alloc: std.mem.Allocator, walker: Walker) Search {
        return .{ .alloc = alloc, .walker = walker };
    }

    pub fn deinit(self: *Search) void {
        self.cands.deinit(self.alloc);
        self.walker.deinit();
    }

    pub fn query(self: *const Search) []const u8 {
        return self.query_buf[0..self.query_len];
    }

    pub fn results(self: *const Search) []const Hit {
        return self.top[0..self.top_n];
    }

    fn scoreOf(self: *const Search, i: u32) ?i32 {
        const it = self.walker.items.items[i];
        return score(self.walker.path(i), it.name, self.query());
    }

    /// `a`가 `b`보다 앞인가(점수가 크면, 같으면 경로 바이트 순).
    fn before(self: *const Search, a: Hit, b: Hit) bool {
        if (a.score != b.score) return a.score > b.score;
        return std.mem.order(u8, self.walker.path(a.item), self.walker.path(b.item)) == .lt;
    }

    fn insertTop(self: *Search, h: Hit) void {
        var k = self.top_n;
        if (k == TOP) {
            if (!self.before(h, self.top[TOP - 1])) return;
            k = TOP - 1;
        } else self.top_n += 1;
        while (k > 0 and self.before(h, self.top[k - 1])) : (k -= 1) self.top[k] = self.top[k - 1];
        self.top[k] = h;
    }

    /// 질의를 바꾼다. 앞을 이으면 지난 후보만 다시 거르고, 아니면 들여온 항목 전부를 다시 본다. 상위 100을 새로 짓는다.
    pub fn setQuery(self: *Search, q: []const u8) !void {
        const n = @min(q.len, self.query_buf.len);
        const extends = self.query_len > 0 and n >= self.query_len and std.mem.eql(u8, q[0..self.query_len], self.query());
        @memcpy(self.query_buf[0..n], q[0..n]);
        self.query_len = n;
        self.top_n = 0;
        if (extends) {
            var w: usize = 0;
            for (self.cands.items) |c| {
                const s = self.scoreOf(c) orelse continue;
                self.cands.items[w] = c;
                w += 1;
                self.insertTop(.{ .item = c, .score = s });
            }
            self.cands.shrinkRetainingCapacity(w);
        } else {
            self.cands.clearRetainingCapacity();
            self.scanned = 0;
        }
        try self.scanNew();
    }

    /// 걷기가 들여온 새 항목을 지금 질의로 본다(후보 · 상위 100에 더한다).
    pub fn scanNew(self: *Search) !void {
        const total = self.walker.items.items.len;
        while (self.scanned < total) : (self.scanned += 1) {
            const i: u32 = @intCast(self.scanned);
            const s = self.scoreOf(i) orelse continue;
            try self.cands.append(self.alloc, i);
            self.insertTop(.{ .item = i, .score = s });
        }
    }
};
