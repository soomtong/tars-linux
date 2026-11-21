//! 텍스트 필드(R-KIT-6, TK-M4 plan 확정 6~8 · 11). 한 줄 · 커서 · 선택 · 되돌리기 한 단계 · preedit.
//!
//! 모델(`Model`)은 순수하다 — 바이트 버퍼(4096, PATH_MAX)와 `caret` · `anchor`(바이트 색인, 늘 클러스터 경계 — `cg/layout.zig`), preedit 칸(64 — 서버
//! `imeSend`의 칸과 같다), 되돌리기 스냅숏 하나. preedit은 버퍼에 넣지 않는다 — 캐럿 자리에 겹쳐 그린다(text-input-v3의 적용 순서: 확정을 캐럿에
//! 넣고 그 뒤에 조합). 선택이 있을 때 첫 확정 · 첫 조합은 선택을 먼저 지운다. 되돌리기: 같은 종류의 연속(입력 · 지움)은 한 묶음이고 묶음의 시작에서
//! 스냅숏을 찍는다. `Cmd+Z`는 스냅숏과 지금을 맞바꾼다(다시 누르면 되살리기).
//!
//! 뷰(`TextField`): 키(plan 확정 7) · 클릭 · IME 이벤트를 모델에 넣고, 클립보드와 Enter · Esc는 앱의 `Delegate`로 낸다(kit은 창을 모른다).
//! 편집 명령 `Cmd+Z/X/C/V/A`는 키로 받지 않는다 — 메뉴 표(`Root`)가 맞춘 표준 action(`tk_menu.UNDO` …)을 `perform`으로 받고 `validate`로
//! 활성을 답한다(TK-M6 plan 확정 2, R-KIT-9). 단축키의 정의는 메뉴 모델 하나이고 필드는 동작만 가진다. `Cmd+←` `→`는 메뉴 항목이 아니라 키로 남는다.
//! first responder인 동안 text-input을 바란다(`wantsTextInput` — `Root`의 훅이 창에 알린다). 포커스를 잃을 때 남은 preedit은 본문에 넣는다
//! (WY 결정 42와 같은 뜻 — 서버 쪽 음절은 disable 뒤 다음 키 배치에서 버려진다).
//!
//! 그리기(물리 픽셀): 바탕 `TK_SURFACE` 둥근 사각형, 포커스면 2 논리 px 링(`focus_ring`), 선택 `TK_SELECTION`(창 포커스가 없으면 흐린 색), 글자
//! `TK_TEXT`, preedit 밑줄 1 논리 px을 baseline + 2에, 캐럿 1 논리 px(깜빡이지 않는다 — idle commit 0). 글자는 좌우 여백 `size.field_pad` 안을
//! clip하고 가로 스크롤(`scroll`, 물리)은 캐럿(조합이 있으면 그 끝)이 보이게 최소만 옮긴다. 편집의 더티는 필드 레이어 사각형뿐이다.

const std = @import("std");
const input = @import("tk_input");
const menu = @import("tk_menu");
const tokens = @import("tk_tokens");
const cg = @import("tk_cg");
const layout = cg.layout;
const Face = cg.Face;
const Painter = cg.Painter;
const Rect = @import("tk_geom").Rect;
const ca = @import("tk_ca");
const Layer = ca.Layer;
const Tree = ca.Tree;
const view_mod = @import("view.zig");
const View = view_mod.View;
const VTable = view_mod.VTable;

pub const MAX_TEXT: usize = 4096;
pub const MAX_PREEDIT: usize = 64;

const Kind = enum { none, insert, delete, other };

/// 낱말 클러스터인가(낱말 이동 · 지움의 단위 — 공백 · 구두점 · `/`가 경계, plan 확정 7).
fn isWord(cl: layout.Cluster) bool {
    const cp = cl.cps[0];
    if (cp < 0x80) return std.ascii.isAlphanumeric(@intCast(cp)) or cp == '_';
    return switch (cl.class) {
        .space, .newline, .open, .close => false,
        else => true,
    };
}

/// `s`를 `room` 바이트 안에서 클러스터 경계로 자른 앞부분.
fn fitPrefix(s: []const u8, room: usize) []const u8 {
    if (s.len <= room) return s;
    var it = layout.Clusters.init(s);
    var end: usize = 0;
    while (it.next()) |cl| {
        if (cl.end > room) break;
        end = cl.end;
    }
    return s[0..end];
}

pub const Model = struct {
    buf: [MAX_TEXT]u8 = undefined,
    len: usize = 0,
    caret: usize = 0,
    anchor: usize = 0,
    pre: [MAX_PREEDIT]u8 = undefined,
    pre_len: usize = 0,
    undo_buf: [MAX_TEXT]u8 = undefined,
    undo_len: usize = 0,
    undo_caret: usize = 0,
    undo_anchor: usize = 0,
    has_undo: bool = false,
    last: Kind = .none,
    /// 버퍼가 바뀐 횟수(조합은 안 센다) — 뷰가 `Delegate.changed`를 낼지 가른다.
    gen: u64 = 0,

    pub fn text(self: *const Model) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn preedit(self: *const Model) []const u8 {
        return self.pre[0..self.pre_len];
    }

    /// 선택(앞 · 뒤). 없으면 null.
    pub fn selection(self: *const Model) ?[2]usize {
        if (self.caret == self.anchor) return null;
        return .{ @min(self.caret, self.anchor), @max(self.caret, self.anchor) };
    }

    pub fn selected(self: *const Model) []const u8 {
        const s = self.selection() orelse return "";
        return self.buf[s[0]..s[1]];
    }

    /// 글 전체를 바꾼다(캐럿은 끝, 선택 · 조합 · 되돌리기 없음) — 필드를 열 때.
    pub fn setText(self: *Model, t: []const u8) void {
        const f = fitPrefix(t, MAX_TEXT);
        @memcpy(self.buf[0..f.len], f);
        self.len = f.len;
        self.caret = f.len;
        self.anchor = f.len;
        self.pre_len = 0;
        self.has_undo = false;
        self.last = .none;
    }

    /// 묶음의 시작이면 스냅숏(같은 종류가 이어지면 안 찍는다, `other`는 늘 찍는다).
    fn snapshot(self: *Model, kind: Kind) void {
        if (kind != .other and kind == self.last) return;
        @memcpy(self.undo_buf[0..self.len], self.buf[0..self.len]);
        self.undo_len = self.len;
        self.undo_caret = self.caret;
        self.undo_anchor = self.anchor;
        self.has_undo = true;
        self.last = kind;
    }

    /// `[a, b)`를 `bytes`로 바꾸고 캐럿 · 앵커를 넣은 끝에. 넘치는 것은 클러스터 경계에서 자른다.
    fn replace(self: *Model, a: usize, b: usize, bytes: []const u8) void {
        const room = MAX_TEXT - (self.len - (b - a));
        const ins = fitPrefix(bytes, room);
        const tail = self.len - b;
        std.mem.copyBackwards(u8, self.buf[a + ins.len .. a + ins.len + tail], self.buf[b..self.len]);
        @memcpy(self.buf[a .. a + ins.len], ins);
        self.len = a + ins.len + tail;
        self.gen +%= 1;
        self.caret = a + ins.len;
        self.anchor = self.caret;
    }

    /// 글을 넣는다(선택이 있으면 바꾼다) — 타이핑.
    pub fn insert(self: *Model, bytes: []const u8) void {
        if (bytes.len == 0) return;
        self.snapshot(if (self.selection() != null) .other else .insert);
        const s = self.selection() orelse [2]usize{ self.caret, self.caret };
        self.replace(s[0], s[1], bytes);
    }

    /// 붙여넣기: 첫 줄 바꿈 앞까지(plan 확정 12), 선택을 바꾼다. 묶음은 늘 새로.
    pub fn paste(self: *Model, bytes: []const u8) void {
        const line = firstLine(bytes);
        self.snapshot(.other);
        const s = self.selection() orelse [2]usize{ self.caret, self.caret };
        self.replace(s[0], s[1], line);
        self.last = .other;
    }

    /// 선택을 지운다(자르기). 없으면 아무것도 안 한다.
    pub fn deleteSelection(self: *Model) void {
        const s = self.selection() orelse return;
        self.snapshot(.other);
        self.replace(s[0], s[1], "");
    }

    /// Backspace(`word`면 Opt+Backspace — 앞 낱말까지).
    pub fn backspace(self: *Model, word: bool) void {
        if (self.selection()) |s| {
            self.snapshot(.delete);
            self.replace(s[0], s[1], "");
            return;
        }
        if (self.caret == 0) return;
        const from = if (word) self.prevWord(self.caret) else self.prevCluster(self.caret);
        self.snapshot(.delete);
        self.replace(from, self.caret, "");
    }

    /// Delete — 뒤 클러스터 하나(선택이 있으면 선택).
    pub fn deleteForward(self: *Model) void {
        if (self.selection()) |s| {
            self.snapshot(.delete);
            self.replace(s[0], s[1], "");
            return;
        }
        if (self.caret >= self.len) return;
        const to = self.nextCluster(self.caret);
        self.snapshot(.delete);
        self.replace(self.caret, to, "");
    }

    /// 캐럿을 `to`로(`extend`면 앵커는 그대로 — 선택이 는다). 되돌리기 묶음을 끊는다.
    pub fn moveTo(self: *Model, to: usize, extend: bool) void {
        self.caret = @min(to, self.len);
        if (!extend) self.anchor = self.caret;
        self.last = .none;
    }

    /// `←` `→`: 선택이 있고 Shift가 없으면 선택의 그쪽 끝으로 모은다(macOS), 아니면 클러스터(`word`면 낱말) 하나.
    pub fn step(self: *Model, forward: bool, word: bool, extend: bool) void {
        if (!extend) if (self.selection()) |s| {
            self.moveTo(if (forward) s[1] else s[0], false);
            return;
        };
        const to = if (forward)
            (if (word) self.nextWord(self.caret) else self.nextCluster(self.caret))
        else
            (if (word) self.prevWord(self.caret) else self.prevCluster(self.caret));
        self.moveTo(to, extend);
    }

    pub fn selectAll(self: *Model) void {
        self.anchor = 0;
        self.caret = self.len;
        self.last = .none;
    }

    /// `Cmd+Z`: 스냅숏과 지금을 맞바꾼다. 스냅숏이 없으면 거짓.
    pub fn undo(self: *Model) bool {
        if (!self.has_undo) return false;
        var tmp: [MAX_TEXT]u8 = undefined;
        const n = self.len;
        @memcpy(tmp[0..n], self.buf[0..n]);
        const c = self.caret;
        const a = self.anchor;
        @memcpy(self.buf[0..self.undo_len], self.undo_buf[0..self.undo_len]);
        self.len = self.undo_len;
        self.caret = self.undo_caret;
        self.anchor = self.undo_anchor;
        self.gen +%= 1;
        @memcpy(self.undo_buf[0..n], tmp[0..n]);
        self.undo_len = n;
        self.undo_caret = c;
        self.undo_anchor = a;
        self.last = .none;
        return true;
    }

    /// IME의 `done` 하나(text-input-v3의 순서): 확정이 있거나 조합이 처음 생기면 선택을 먼저 지우고, 확정을 캐럿에 넣고, 조합을 바꾼다.
    pub fn ime(self: *Model, commit: []const u8, pre: []const u8) void {
        if ((commit.len > 0 or (pre.len > 0 and self.pre_len == 0)) and self.selection() != null) self.deleteSelection();
        if (commit.len > 0) {
            self.snapshot(.insert);
            self.replace(self.caret, self.caret, commit);
        }
        const p = fitPrefix(pre, MAX_PREEDIT);
        @memcpy(self.pre[0..p.len], p);
        self.pre_len = p.len;
    }

    /// 남은 조합을 본문에 넣는다(포커스를 잃을 때 — plan 확정 11). 조합이 없으면 거짓.
    pub fn commitPreedit(self: *Model) bool {
        if (self.pre_len == 0) return false;
        var tmp: [MAX_PREEDIT]u8 = undefined;
        const n = self.pre_len;
        @memcpy(tmp[0..n], self.pre[0..n]);
        self.pre_len = 0;
        self.snapshot(.insert);
        self.replace(self.caret, self.caret, tmp[0..n]);
        return true;
    }

    // ── 경계 ──────────────────────────────────────────────────────────

    pub fn prevCluster(self: *const Model, i: usize) usize {
        var it = layout.Clusters.init(self.text());
        var last: usize = 0;
        while (it.next()) |cl| {
            if (cl.start >= i) break;
            last = cl.start;
        }
        return last;
    }

    pub fn nextCluster(self: *const Model, i: usize) usize {
        var it = layout.Clusters.init(self.text());
        while (it.next()) |cl| if (cl.start >= i) return cl.end;
        return self.len;
    }

    /// 앞 낱말의 처음: 앞의 낱말 아닌 것을 건너뛰고 낱말을 건너뛴다.
    pub fn prevWord(self: *const Model, i: usize) usize {
        var starts: [MAX_TEXT + 1]u16 = undefined;
        var words: [MAX_TEXT + 1]bool = undefined;
        var n: usize = 0;
        var it = layout.Clusters.init(self.text());
        while (it.next()) |cl| {
            if (cl.start >= i) break;
            starts[n] = @intCast(cl.start);
            words[n] = isWord(cl);
            n += 1;
        }
        var k = n;
        while (k > 0 and !words[k - 1]) k -= 1;
        while (k > 0 and words[k - 1]) k -= 1;
        return if (k < n) starts[k] else i;
    }

    /// 뒤 낱말의 끝: 뒤의 낱말 아닌 것을 건너뛰고 낱말을 건너뛴다.
    pub fn nextWord(self: *const Model, i: usize) usize {
        var it = layout.Clusters.init(self.text());
        var pos = i;
        var in_word = false;
        while (it.next()) |cl| {
            if (cl.start < i) continue;
            const w = isWord(cl);
            if (in_word and !w) return pos;
            if (w) in_word = true;
            pos = cl.end;
        }
        return pos;
    }
};

/// 첫 줄 바꿈(`\n` · `\r`) 앞까지.
pub fn firstLine(bytes: []const u8) []const u8 {
    const k = std.mem.indexOfAny(u8, bytes, "\r\n") orelse bytes.len;
    return bytes[0..k];
}

pub const Action = enum { enter, escape };

/// 앱이 받는 것: Enter · Esc, 클립보드(창 층의 `copyText` · `pasteText`로 잇는다).
pub const Delegate = struct {
    ctx: *anyopaque,
    action: *const fn (ctx: *anyopaque, field: *TextField, a: Action) void,
    copy: *const fn (ctx: *anyopaque, bytes: []const u8) void,
    /// 붙일 글을 `buf`에 받아 돌려준다(없으면 null).
    paste: *const fn (ctx: *anyopaque, buf: []u8) ?[]const u8,
    /// 글이 바뀌었다(타이핑 · IME 확정 · 붙여넣기 · 지움 · 되돌리기 — 조합만 바뀐 것은 아니다, TK-M4 plan 확정 18). `setText`는 안 알린다.
    changed: ?*const fn (ctx: *anyopaque, field: *TextField) void = null,
};

pub const TextField = struct {
    view: View,
    tree: *Tree,
    model: Model = .{},
    /// 앱의 글꼴 칸(배율이 바뀌면 앱이 다시 만든다).
    face: *?Face,
    /// 가로 스크롤(물리 px).
    scroll: f32 = 0,
    focused: bool = false,
    window_focused: bool = true,
    delegate: ?Delegate = null,

    const vtable: VTable = .{
        .keyDown = keyDown,
        .mouseDown = mouseDown,
        .acceptsFocus = acceptsFocus,
        .focusChanged = focusChanged,
        .windowFocusChanged = windowFocusChanged,
        .textInput = textInput,
        .wantsTextInput = wantsTextInput,
        .perform = perform,
        .validate = validate,
    };

    /// 레이어 하나를 만든다(어디에도 안 붙음 — 앱이 붙인다). `self`는 사는 동안 옮기지 않는다.
    pub fn init(self: *TextField, tree: *Tree, name: []const u8, face: *?Face) !void {
        self.* = .{
            .view = undefined,
            .tree = tree,
            .face = face,
        };
        const l = try tree.create(.{ .content = .{ .ctx = self, .draw = draw } });
        self.view = .{ .layer = l, .vtable = &vtable, .ctx = self, .name = name };
        l.owner = &self.view;
    }

    pub fn setText(self: *TextField, t: []const u8) void {
        self.model.setText(t);
        self.scroll = 0;
        self.changed();
    }

    pub fn text(self: *const TextField) []const u8 {
        return self.model.text();
    }

    fn me(ctx: *anyopaque) *TextField {
        return @ptrCast(@alignCast(ctx));
    }

    /// 다시 그린다 — 보이지 않으면 건너뛴다(숨긴 바의 필드가 창 포커스 바뀜에 숨은 자리를 다시 그리던 것, TK-M4 단계 B carryover).
    fn changed(self: *TextField) void {
        if (!self.view.visible()) return;
        self.view.layer.setNeedsDisplay();
    }

    /// 글이 바뀌었으면 앱에 알린다.
    fn notify(self: *TextField, gen: u64) void {
        if (self.model.gen == gen) return;
        if (self.delegate) |d| if (d.changed) |f| f(d.ctx, self);
    }

    fn keyDown(ctx: *anyopaque, ev: input.KeyEvent) bool {
        const self = me(ctx);
        const gen = self.model.gen;
        const handled = self.key(ev);
        if (handled) {
            self.changed();
            self.notify(gen);
        }
        return handled;
    }

    /// 표준 action이 지금 되는가(TK-M6 plan 확정 9의 활성): 되돌리기 = 스냅숏, 오려두기 · 복사 = 선택, 붙여넣기 · 전체 선택 = 늘(first responder인
    /// 동안만 chain에 있다). 클립보드가 필요한 셋은 delegate가 있어야 한다. 그 밖의 action은 모른다(부모에게).
    fn validate(ctx: *anyopaque, action: u32) ?bool {
        const self = me(ctx);
        const m = &self.model;
        const has_clip = self.delegate != null;
        return switch (action) {
            menu.UNDO => m.has_undo,
            menu.CUT, menu.COPY => has_clip and m.selection() != null,
            menu.PASTE => has_clip,
            menu.SELECT_ALL => true,
            else => null,
        };
    }

    /// 표준 action을 한다 — 키로 받던 때와 같은 일과 같은 다시 그림 · 알림.
    fn perform(ctx: *anyopaque, action: u32) bool {
        const self = me(ctx);
        const m = &self.model;
        const gen = m.gen;
        switch (action) {
            menu.UNDO => _ = m.undo(),
            menu.CUT => if (self.delegate) |d| if (m.selection() != null) {
                d.copy(d.ctx, m.selected());
                m.deleteSelection();
            },
            menu.COPY => if (self.delegate) |d| {
                if (m.selection() != null) d.copy(d.ctx, m.selected());
            },
            menu.PASTE => if (self.delegate) |d| {
                var buf: [MAX_TEXT]u8 = undefined;
                if (d.paste(d.ctx, &buf)) |t| m.paste(t);
            },
            menu.SELECT_ALL => m.selectAll(),
            else => return false,
        }
        self.changed();
        self.notify(gen);
        return true;
    }

    fn key(self: *TextField, ev: input.KeyEvent) bool {
        const m = &self.model;
        const md = ev.mods;
        if (md.super) {
            if (md.ctrl or md.alt) return false;
            switch (ev.key) {
                .left => m.moveTo(0, md.shift),
                .right => m.moveTo(m.len, md.shift),
                else => return false,
            }
            return true;
        }
        if (md.ctrl) {
            if (md.alt) return false;
            switch (ev.code) {
                input.KEY_A => m.moveTo(0, md.shift),
                input.KEY_E => m.moveTo(m.len, md.shift),
                else => return false,
            }
            return true;
        }
        if (md.alt) {
            switch (ev.key) {
                .left => m.step(false, true, md.shift),
                .right => m.step(true, true, md.shift),
                .backspace => m.backspace(true),
                else => return false,
            }
            return true;
        }
        switch (ev.key) {
            .left => m.step(false, false, md.shift),
            .right => m.step(true, false, md.shift),
            .home => m.moveTo(0, md.shift),
            .end => m.moveTo(m.len, md.shift),
            .backspace => m.backspace(false),
            .delete => m.deleteForward(),
            .enter, .escape => if (self.delegate) |d| d.action(d.ctx, self, if (ev.key == .enter) .enter else .escape),
            .tab, .up, .down, .page_up, .page_down => return false,
            else => {
                const cp = input.charFor(ev.code, md) orelse return false;
                var u: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &u) catch return false;
                m.insert(u[0..n]);
            },
        }
        return true;
    }

    fn mouseDown(ctx: *anyopaque, ev: input.ButtonEvent, lx: f32, ly: f32) bool {
        _ = ly;
        _ = ev;
        const self = me(ctx);
        const f = if (self.face.*) |*x| x else return true;
        const s: f32 = @floatFromInt(self.tree.scale);
        const x = lx * s - tokens.size.field_pad * s + self.scroll;
        self.model.moveTo(layout.indexAt(f.metrics(), self.model.text(), x), false);
        self.changed();
        return true;
    }

    fn acceptsFocus(ctx: *anyopaque) bool {
        return me(ctx).view.visible();
    }

    fn focusChanged(ctx: *anyopaque, on: bool) void {
        const self = me(ctx);
        self.focused = on;
        const gen = self.model.gen;
        if (!on) _ = self.model.commitPreedit();
        self.changed();
        self.notify(gen);
    }

    fn windowFocusChanged(ctx: *anyopaque, on: bool) void {
        const self = me(ctx);
        self.window_focused = on;
        self.changed();
    }

    fn textInput(ctx: *anyopaque, ev: input.ImeEvent) bool {
        const self = me(ctx);
        const gen = self.model.gen;
        self.model.ime(ev.commit, ev.preedit);
        self.changed();
        self.notify(gen);
        return true;
    }

    fn wantsTextInput(ctx: *anyopaque) bool {
        _ = ctx;
        return true;
    }

    /// 가로 스크롤을 캐럿 x(물리, 글 왼쪽 기준)가 보이게 최소만 옮긴다 — 글 전체 폭 `total`, 보이는 폭 `avail`.
    pub fn scrollFor(scroll: f32, caret_x: f32, total: f32, avail: f32) f32 {
        var sc = scroll;
        if (caret_x - sc > avail - 1) sc = caret_x - avail + 1;
        if (caret_x - sc < 0) sc = caret_x;
        const max = @max(0, total - avail + 1);
        return std.math.clamp(sc, 0, max);
    }

    fn draw(ctx: *anyopaque, p: *Painter, size: [2]f32, alpha: u8) anyerror!void {
        const self = me(ctx);
        const s: f32 = @floatFromInt(self.tree.scale);
        const w = size[0];
        const h = size[1];
        const r = tokens.radius.s * s;
        if (self.focused) {
            try p.fillRoundedRect(.{ .x = 0, .y = 0, .w = w, .h = h }, r, tokens.color.focus_ring, alpha);
            const ring = 2 * s;
            try p.fillRoundedRect(.{ .x = ring, .y = ring, .w = w - 2 * ring, .h = h - 2 * ring }, @max(0, r - ring), tokens.color.surface, alpha);
        } else {
            try p.fillRoundedRect(.{ .x = 0, .y = 0, .w = w, .h = h }, r, tokens.color.surface, alpha);
        }
        const f = if (self.face.*) |*x| x else return;
        const m = f.metrics();
        const t = self.model.text();
        const pre = self.model.preedit();
        const pad = tokens.size.field_pad * s;
        const avail = @max(1, w - 2 * pad);
        const cx = layout.caretX(m, t, self.model.caret);
        const pw = if (pre.len > 0) layout.measure(m, pre) else 0;
        const total = layout.measure(m, t) + pw;
        self.scroll = scrollFor(self.scroll, cx + pw, total, avail);
        const baseline: i32 = @intFromFloat(@round((h + f.ascent - f.descent) / 2));
        const ox = pad - self.scroll;
        p.pushClip(.{ .x = @intFromFloat(@round(pad)), .y = 0, .w = @intFromFloat(@round(avail)), .h = @intFromFloat(@round(h)) });
        defer p.popClip();
        const top: i32 = baseline - @as(i32, @intFromFloat(@ceil(f.ascent)));
        const line_h: i32 = @intFromFloat(@ceil(f.ascent) + @ceil(f.descent));
        if (self.model.selection()) |sel| {
            const xa = layout.caretX(m, t, sel[0]);
            const xb = layout.caretX(m, t, sel[1]);
            const col = if (self.window_focused and self.focused) tokens.color.selection else tokens.color.selection_inactive;
            p.fillRect(.{ .x = @intFromFloat(@round(ox + xa)), .y = top, .w = @intFromFloat(@round(xb - xa)), .h = line_h }, col, alpha);
        }
        if (pre.len == 0) {
            _ = try p.drawGlyphs(f, ox, baseline, t, tokens.color.text, alpha);
        } else {
            const c = self.model.caret;
            _ = try p.drawGlyphs(f, ox, baseline, t[0..c], tokens.color.text, alpha);
            _ = try p.drawGlyphs(f, ox + cx, baseline, pre, tokens.color.text, alpha);
            _ = try p.drawGlyphs(f, ox + cx + pw, baseline, t[c..], tokens.color.text, alpha);
            // preedit 밑줄(R-TXT-3): baseline + 2 논리 px에 1 논리 px.
            const ux: i32 = @intFromFloat(@round(ox + cx));
            const uw: i32 = @intFromFloat(@round(ox + cx + pw));
            p.fillRect(.{ .x = ux, .y = baseline + @as(i32, @intFromFloat(2 * s)), .w = uw - ux, .h = @intFromFloat(s) }, tokens.color.text, alpha);
        }
        if (self.focused and self.window_focused) {
            const kx: i32 = @intFromFloat(@round(ox + cx + pw));
            p.fillRect(.{ .x = kx, .y = top, .w = @intFromFloat(s), .h = line_h }, tokens.color.text, alpha);
        }
    }
};
