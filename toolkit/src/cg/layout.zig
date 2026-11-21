//! 비례폭 텍스트의 놓기(TK-M4 단계 A, R-TXT-1 · 2 · 4, TK design 결정 15). 픽셀을 모르고 글꼴도 모른다 — 폭은 `Metrics`(advance · kern ·
//! 글리프 유무)로만 받는다. 그래서 호스트 표는 고정 폭 가짜 Metrics로 결정적이고, 실제 글꼴은 `text.Face.metrics()`가 준다.
//!
//! 클러스터 = 캐럿이 설 수 있는 경계 사이(plan 확정 2). 셰이핑은 없으므로(R-TXT-4) 자소 클러스터 규칙의 아주 작은 부분집합이다:
//! - 정상 UTF-8 코드포인트 하나.
//! - 잘못된 바이트 하나(1바이트 클러스터). 표시는 `?` — 버퍼의 바이트는 그대로다(경로는 파일 시스템의 바이트라야 맞는다).
//! - 결합 표시(U+0300~036F)는 앞 글자에 붙는다(NFD 라틴 `e` + U+0301).
//! - 현대 조합형 자모 L(1100~1112) + V(1161~1175) + T?(11A8~11C2)는 한 클러스터이고 표시할 때 음절로 합친다 — Pretendard에는 U+1100대
//!   글리프가 없다(조사 `tk-m4`). 홀로 선 자모는 호환 자모(U+3131~)로.
//! 정규화는 표시에서만 한다 — 버퍼 · 경로 · 정렬은 바이트 그대로.
//!
//! 대체: 글리프가 없는 글자는 `□`(U+25A1), 없는 결합 표시는 그리지 않는다. 측정(`StopIter`)과 그리기(`Placer`)가 같은 `resolve`를 지나므로
//! 폭이 어긋나지 않는다. 펜 규칙은 TK-M0부터 그대로다 — 앞 글자와의 kern을 더하고 그 자리에 놓은 뒤 advance만큼 나아간다.
//!
//! 캐럿 x: 경계 i의 x는 그 앞 글을 따로 잰 폭이다(경계의 kern을 넣기 전의 펜). 그래서 `stops[b].x - stops[a].x - stops[a].kern`이 곧
//! `measure(s[a..b])`다.

const std = @import("std");

/// 글리프가 없는 글자의 대체(□).
pub const FALLBACK: u21 = 0x25A1;
/// 잘못된 바이트 하나의 표시.
pub const INVALID: u21 = '?';
pub const ELLIPSIS_CP: u21 = 0x2026;
pub const ELLIPSIS = "\u{2026}";
/// 클러스터 하나가 들 수 있는 표시 코드포인트(바탕 하나 + 결합 표시 셋). 넘친 결합 표시는 버퍼에 남고 그리지 않는다.
pub const MAX_CPS = 4;

/// 폭을 재는 길. `ctx`는 글꼴(`text.Face`)이거나 호스트 표의 가짜다.
pub const Metrics = struct {
    ctx: *anyopaque,
    advance_fn: *const fn (ctx: *anyopaque, cp: u21) f32,
    kern_fn: *const fn (ctx: *anyopaque, left: u21, right: u21) f32,
    has_fn: *const fn (ctx: *anyopaque, cp: u21) bool,

    pub fn advance(self: Metrics, cp: u21) f32 {
        return self.advance_fn(self.ctx, cp);
    }
    pub fn kern(self: Metrics, left: u21, right: u21) f32 {
        return self.kern_fn(self.ctx, left, right);
    }
    pub fn has(self: Metrics, cp: u21) bool {
        return self.has_fn(self.ctx, cp);
    }
};

/// 줄 나누기의 갈래(클러스터의 첫 원래 코드포인트로 정한다).
pub const Class = enum {
    space,
    newline,
    /// 한글 · 호환 자모 · 조합형 자모 · 한자 · 가나 · CJK 문장 부호 · 전각 — 글자마다 나눌 수 있다(R-TXT-1 "한글은 글자 단위").
    cjk,
    /// 뒤에서 나누지 않는 여는 부호(최소 금칙).
    open,
    /// 앞에서 나누지 않는 닫는 부호 · 구두점(최소 금칙).
    close,
    other,
};

pub const Cluster = struct {
    /// 원래 바이트 범위.
    start: usize,
    end: usize,
    /// 표시 코드포인트(정규화 뒤, 글꼴 대체 전).
    cps: [MAX_CPS]u21 = undefined,
    n: u8 = 0,
    class: Class = .other,

    pub fn display(self: *const Cluster) []const u21 {
        return self.cps[0..self.n];
    }
};

fn isL(cp: u21) bool {
    return cp >= 0x1100 and cp <= 0x1112;
}
fn isV(cp: u21) bool {
    return cp >= 0x1161 and cp <= 0x1175;
}
fn isT(cp: u21) bool {
    return cp >= 0x11A8 and cp <= 0x11C2;
}
pub fn isMark(cp: u21) bool {
    return cp >= 0x0300 and cp <= 0x036F;
}

/// 현대 초성(L 19) · 종성(T 27)의 호환 자모. 중성(V 21)은 U+314F부터 같은 순서다.
const L_COMPAT = [19]u16{ 0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141, 0x3142, 0x3143, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149, 0x314A, 0x314B, 0x314C, 0x314D, 0x314E };
const T_COMPAT = [27]u16{ 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136, 0x3137, 0x3139, 0x313A, 0x313B, 0x313C, 0x313D, 0x313E, 0x313F, 0x3140, 0x3141, 0x3142, 0x3144, 0x3145, 0x3146, 0x3147, 0x3148, 0x314A, 0x314B, 0x314C, 0x314D, 0x314E };

/// 홀로 선 현대 조합형 자모의 호환 자모. 옛 자모 등은 null(그대로 두고 글꼴 대체에 맡긴다).
pub fn compatJamo(cp: u21) ?u21 {
    if (isL(cp)) return L_COMPAT[cp - 0x1100];
    if (isV(cp)) return 0x314F + (cp - 0x1161);
    if (isT(cp)) return T_COMPAT[cp - 0x11A8];
    return null;
}

pub fn classOf(cp: u21) Class {
    return switch (cp) {
        ' ', '\t' => .space,
        '\n' => .newline,
        '(', '[', '{', 0x300C, 0x300E, 0x2018, 0x201C => .open,
        '.', ',', '!', '?', ')', ']', '}', ':', ';', 0x300D, 0x300F, 0x2019, 0x201D, 0x2026, 0x3001, 0x3002 => .close,
        0x1100...0x11FF, 0x3000, 0x3003...0x300B, 0x3010...0x303F, 0x3040...0x30FF, 0x3130...0x318F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFF00...0xFFEF => .cjk,
        else => .other,
    };
}

const Decoded = struct { cp: ?u21, len: usize };

/// `s[i..]`의 코드포인트 하나. 잘못된 바이트면 cp null · 길이 1, 끝이면 길이 0.
fn decode(s: []const u8, i: usize) Decoded {
    if (i >= s.len) return .{ .cp = null, .len = 0 };
    const n = std.unicode.utf8ByteSequenceLength(s[i]) catch return .{ .cp = null, .len = 1 };
    if (i + n > s.len) return .{ .cp = null, .len = 1 };
    const cp = std.unicode.utf8Decode(s[i .. i + n]) catch return .{ .cp = null, .len = 1 };
    return .{ .cp = cp, .len = n };
}

/// 클러스터를 차례로.
pub const Clusters = struct {
    s: []const u8,
    i: usize = 0,

    pub fn init(s: []const u8) Clusters {
        return .{ .s = s };
    }

    pub fn next(self: *Clusters) ?Cluster {
        const s = self.s;
        if (self.i >= s.len) return null;
        const start = self.i;
        const d = decode(s, start);
        var c: Cluster = .{ .start = start, .end = start + d.len };
        const cp = d.cp orelse {
            c.cps[0] = INVALID;
            c.n = 1;
            self.i = c.end;
            return c;
        };
        c.class = classOf(cp);
        var base: ?u21 = null;
        if (isL(cp)) {
            const dv = decode(s, c.end);
            if (dv.cp) |v| if (isV(v)) {
                var syl: u21 = 0xAC00 + ((cp - 0x1100) * 21 + (v - 0x1161)) * 28;
                c.end += dv.len;
                const dt = decode(s, c.end);
                if (dt.cp) |t| if (isT(t)) {
                    syl += t - 0x11A7;
                    c.end += dt.len;
                };
                base = syl;
            };
        }
        c.cps[0] = base orelse (compatJamo(cp) orelse cp);
        c.n = 1;
        // 결합 표시는 앞 글자에 붙는다. 줄 바꿈 뒤의 결합 표시는 붙이지 않는다(줄 바꿈은 클러스터 하나로 남아야 한다).
        if (c.class != .newline) while (c.end < s.len) {
            const dm = decode(s, c.end);
            const m = dm.cp orelse break;
            if (!isMark(m)) break;
            if (c.n < MAX_CPS) {
                c.cps[c.n] = m;
                c.n += 1;
            }
            c.end += dm.len;
        };
        self.i = c.end;
        return c;
    }
};

/// 표시 코드포인트를 글꼴에 맞춘다: 있으면 그대로, 없는 바탕은 □(□도 없으면 그대로 — 글꼴의 `.notdef`), 없는 결합 표시는 null(안 그림).
pub fn resolve(m: Metrics, cp: u21, base: bool) ?u21 {
    if (m.has(cp)) return cp;
    if (!base) return null;
    return if (m.has(FALLBACK)) FALLBACK else cp;
}

/// 글리프 하나의 자리 — `Placer`가 준다(그리는 쪽).
pub const Placed = struct { cp: u21, x: f32 };

/// 글자를 차례로 놓는다(그리기). 펜 규칙은 `StopIter`와 같다.
pub const Placer = struct {
    m: Metrics,
    it: Clusters,
    pen: f32 = 0,
    prev: ?u21 = null,
    cl: Cluster = .{ .start = 0, .end = 0 },
    k: u8 = 0,

    pub fn init(m: Metrics, s: []const u8, x: f32) Placer {
        return .{ .m = m, .it = Clusters.init(s), .pen = x };
    }

    pub fn next(self: *Placer) ?Placed {
        while (true) {
            if (self.k < self.cl.n) {
                const raw = self.cl.cps[self.k];
                const base = self.k == 0;
                self.k += 1;
                const cp = resolve(self.m, raw, base) orelse continue;
                if (self.prev) |p| self.pen += self.m.kern(p, cp);
                const x = self.pen;
                self.pen += self.m.advance(cp);
                self.prev = cp;
                return .{ .cp = cp, .x = x };
            }
            self.cl = self.it.next() orelse return null;
            self.k = 0;
        }
    }
};

/// 경계 하나: 그 클러스터가 시작하는 바이트, 그 앞 글의 폭(`x`), 그 클러스터의 첫 글자가 앞 글자와 맺는 kern, 그 클러스터의 갈래.
/// 마지막 경계는 글 끝(`byte` = 길이, `x` = 전체 폭, kern 0).
pub const Stop = struct { byte: usize, x: f32, kern: f32 = 0, class: Class = .other };

pub const StopIter = struct {
    m: Metrics,
    it: Clusters,
    pen: f32 = 0,
    prev: ?u21 = null,
    done: bool = false,

    pub fn init(m: Metrics, s: []const u8) StopIter {
        return .{ .m = m, .it = Clusters.init(s) };
    }

    pub fn next(self: *StopIter) ?Stop {
        if (self.done) return null;
        const cl = self.it.next() orelse {
            self.done = true;
            return .{ .byte = self.it.s.len, .x = self.pen };
        };
        const x0 = self.pen;
        var first: ?f32 = null;
        for (cl.display(), 0..) |raw, i| {
            const cp = resolve(self.m, raw, i == 0) orelse continue;
            const k: f32 = if (self.prev) |p| self.m.kern(p, cp) else 0;
            if (first == null) first = k;
            self.pen += k + self.m.advance(cp);
            self.prev = cp;
        }
        return .{ .byte = cl.start, .x = x0, .kern = first orelse 0, .class = cl.class };
    }
};

pub const Error = error{NoSpace};

/// 경계 전부(클러스터 수 + 1)를 `out`에. 모자라면 `error.NoSpace`.
pub fn stops(m: Metrics, s: []const u8, out: []Stop) Error![]Stop {
    var it = StopIter.init(m, s);
    var n: usize = 0;
    while (it.next()) |st| {
        if (n >= out.len) return error.NoSpace;
        out[n] = st;
        n += 1;
    }
    return out[0..n];
}

/// 경계마다의 캐럿 x(클러스터 수 + 1). 모자라면 `error.NoSpace`.
pub fn caretXs(m: Metrics, s: []const u8, out: []f32) Error![]f32 {
    var it = StopIter.init(m, s);
    var n: usize = 0;
    while (it.next()) |st| {
        if (n >= out.len) return error.NoSpace;
        out[n] = st.x;
        n += 1;
    }
    return out[0..n];
}

/// 바이트 색인 `index`(클러스터 경계)의 캐럿 x. 경계가 아니면 그 색인을 품은 클러스터의 앞.
pub fn caretX(m: Metrics, s: []const u8, index: usize) f32 {
    var it = StopIter.init(m, s);
    var last: f32 = 0;
    while (it.next()) |st| {
        if (st.byte > index) return last;
        last = st.x;
        if (st.byte == index) return st.x;
    }
    return last;
}

/// 글 전체의 폭(그리기의 끝 펜과 같다).
pub fn measure(m: Metrics, s: []const u8) f32 {
    var it = StopIter.init(m, s);
    var x: f32 = 0;
    while (it.next()) |st| x = st.x;
    return x;
}

/// x 좌표(글 왼쪽 기준)에 가장 가까운 경계의 바이트 색인. 클러스터의 가운데를 넘으면 오른쪽 경계다(R-TXT-2).
pub fn indexAt(m: Metrics, s: []const u8, x: f32) usize {
    var it = StopIter.init(m, s);
    var prev = it.next() orelse return 0;
    while (it.next()) |st| {
        if (x < (prev.x + st.x) / 2) return prev.byte;
        prev = st;
    }
    return prev.byte;
}

/// 경계 a..b(색인)의 글을 따로 잰 폭.
pub fn spanWidth(st: []const Stop, a: usize, b: usize) f32 {
    if (b <= a) return 0;
    return st[b].x - st[a].x - st[a].kern;
}

/// 가운데 생략(R-TXT-1). `max_w` 안에 들면 `s` 그대로, 아니면 머리 + `…` + 꼬리를 `buf`에(꼬리 쪽으로 기울인다 — 같으면 꼬리가 하나 더,
/// 확장자 · 끝 번호가 남는다). `…`조차 안 들어가면 빈 글. 머리 · 꼬리는 클러스터 경계에서 자른다. `scratch`는 클러스터 수 + 1의 경계 칸.
/// 결과를 다시 재어 `max_w`를 넘으면(이음매의 kern) 한 클러스터씩 더 깎는다 — 결과 폭 ≤ `max_w`는 늘 참이다.
pub fn elideMiddle(m: Metrics, s: []const u8, max_w: f32, scratch: []Stop, buf: []u8) Error![]const u8 {
    const st = try stops(m, s, scratch);
    const n = st.len - 1;
    if (st[n].x <= max_w) return s;
    const ell = resolve(m, ELLIPSIS_CP, true).?;
    const ell_w = m.advance(ell);
    if (ell_w > max_w) return buf[0..0];
    const target = max_w - ell_w;
    var h: usize = 0;
    var t: usize = 0;
    while (h + t < n) {
        const tail_first = t <= h;
        var grew = false;
        var pass: u2 = 0;
        while (pass < 2 and !grew) : (pass += 1) {
            const try_tail = (pass == 0) == tail_first;
            const nh = if (try_tail) h else h + 1;
            const nt = if (try_tail) t + 1 else t;
            if (nh + nt > n) continue;
            if (st[nh].x + spanWidth(st, n - nt, n) <= target) {
                h = nh;
                t = nt;
                grew = true;
            }
        }
        if (!grew) break;
    }
    while (true) {
        const out = try join3(buf, s[0..st[h].byte], ELLIPSIS, s[st[n - t].byte..]);
        if (measure(m, out) <= max_w or (h == 0 and t == 0)) return out;
        if (h > t) h -= 1 else t -= 1;
    }
}

fn join3(buf: []u8, a: []const u8, b: []const u8, c: []const u8) Error![]const u8 {
    const len = a.len + b.len + c.len;
    if (len > buf.len) return error.NoSpace;
    @memcpy(buf[0..a.len], a);
    @memcpy(buf[a.len..][0..b.len], b);
    @memcpy(buf[a.len + b.len ..][0..c.len], c);
    return buf[0..len];
}

/// 줄 하나(바이트 범위, 줄 끝의 공백 · 줄 바꿈은 뺐다).
pub const Line = struct { start: usize, end: usize };

/// 경계 `i`(클러스터 i-1과 i 사이)에서 나눌 수 있는가(최소 금칙 포함).
fn canBreak(prev: Class, cur: Class) bool {
    if (cur == .close or prev == .open or cur == .space) return false;
    if (prev == .space) return true;
    return prev == .cjk or cur == .cjk;
}

/// 줄 나누기(R-TXT-1): 공백 뒤 · 한글/CJK는 글자 사이 어디서나, 한 낱말이 줄보다 길면 클러스터 단위로 강제, 최소 금칙, `\n`은 강제 줄 바꿈.
/// 줄 끝의 공백은 폭에 안 센다(걸어 둔다). 빈 글은 빈 줄 하나. `scratch`는 클러스터 수 + 1의 경계 칸, `out`은 줄 칸.
pub fn wrap(m: Metrics, s: []const u8, max_w: f32, scratch: []Stop, out: []Line) Error![]Line {
    const st = try stops(m, s, scratch);
    const n = st.len - 1;
    var lines: usize = 0;
    var s0: usize = 0;
    var last_break: ?usize = null;
    var i: usize = 0;
    while (i < n) {
        const c = st[i].class;
        if (c == .newline) {
            try emitLine(st, s0, i, out, &lines);
            s0 = i + 1;
            last_break = null;
            i += 1;
            continue;
        }
        if (i > s0 and canBreak(st[i - 1].class, c)) last_break = i;
        if (c != .space and i > s0 and spanWidth(st, s0, i + 1) > max_w) {
            const brk = if (last_break) |b| (if (b > s0) b else i) else i;
            try emitLine(st, s0, brk, out, &lines);
            s0 = brk;
            while (s0 < n and st[s0].class == .space) s0 += 1;
            last_break = null;
            i = s0;
            continue;
        }
        i += 1;
    }
    try emitLine(st, s0, n, out, &lines);
    return out[0..lines];
}

fn emitLine(st: []const Stop, a: usize, b0: usize, out: []Line, lines: *usize) Error!void {
    var b = b0;
    while (b > a and st[b - 1].class == .space) b -= 1;
    if (lines.* >= out.len) return error.NoSpace;
    out[lines.*] = .{ .start = st[a].byte, .end = st[b].byte };
    lines.* += 1;
}
