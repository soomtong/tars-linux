//! 가상화 리스트(R-KIT-4, TK-M2 plan 확정 9~12). 행 수를 모른 채 데이터 소스의 `count`와 `drawRow`만 부른다 — 보이는 행만 그리고, 선택 ·
//! 스크롤 · 범위 셈은 행 수에 비례하는 일을 하지 않는다(10만 행이든 1,000만 행이든 같은 일).
//!
//! 레이어: 컨테이너(뷰의 레이어 — masks, 바탕) → 강조(선택 행의 사각형, 배경색이 곧 포커스 표시) → 글자(content — clip과 겹치는 행만
//! `drawRow`) → 막대(스크롤 위치). 선택 행의 글자색은 그대로라 선택만 옮기면 더티가 강조 레이어의 옛 ∪ 새로 끝난다.
//!
//! 오프셋은 정수 논리 픽셀(`u64`)이다. 레이어 frame은 f32라 행 수 × 행 높이짜리 큰 레이어를 옮기는 길은 정밀도가 깨진다(f32의 정수 한계
//! 16,777,216) — 글자 레이어는 뷰 크기 그대로이고 행의 y를 정수로 셈해 그린다.
//!
//! 키(포커스일 때): `↓` `↑` 한 행, PgDn PgUp 보이는 행 수 − 1, Home End. 선택이 보이게 최소만 스크롤한다(아래로 넘으면 행 바닥을 뷰 바닥에,
//! 위로 넘으면 꼭대기를 꼭대기에). 휠(포인터 아래일 때): `discrete`가 있으면 칸당 3행, 없으면 `dy` px — 선택은 안 바꾼다. 클릭: 그 행을 선택.
//! 스크롤 한 번은 리스트 통째 다시 그림이다(버퍼 안 복사 · 부드러운 스크롤은 carryover). 강조 레이어의 이동만 애니메이션한다(`anim_ms`,
//! 기본 120 ms ease-out — 녹화 C의 "짧게 움직인다"). 스크롤이 생기는 이동 · 강조가 안 보이던 때는 바로 옮긴다.
//!
//! 앱은 컨테이너 레이어(`view.layer`)를 자기 트리에 붙이고 frame을 준 뒤(스택 등) `sync()`를 부른다 — 크기가 바뀔 때마다.

const std = @import("std");
const geom = @import("tk_geom");
const Rect = geom.Rect;
const RectF = geom.RectF;
const input = @import("tk_input");
const tokens = @import("tk_tokens");
const Painter = @import("tk_cg").Painter;
const ca = @import("tk_ca");
const Layer = ca.Layer;
const Tree = ca.Tree;
const view_mod = @import("view.zig");
const View = view_mod.View;
const VTable = view_mod.VTable;

/// 막대의 폭(논리 px)과 최소 높이, 휠 한 칸의 행 수.
pub const BAR_W: f32 = 6;
pub const BAR_MIN_H: f32 = 24;
pub const WHEEL_ROWS: u64 = 3;

pub const RowState = struct {
    selected: bool,
    /// 리스트가 first responder이고 창이 키보드 포커스를 가졌다(강조가 `TK_SELECTION`).
    focused: bool,
    /// 누적 불투명도(0..255) — 그리는 쪽이 글자에 그대로 넘긴다.
    alpha: u8 = 255,
};

pub const ListSource = struct {
    ctx: *anyopaque,
    count: *const fn (ctx: *anyopaque) usize,
    /// 행 `index`를 `rect`(물리 픽셀, 글자 레이어의 왼쪽 위 기준 — painter가 이미 옮겨 놓았다)에 그린다. 바탕은 리스트가 칠한다.
    drawRow: *const fn (ctx: *anyopaque, p: *Painter, index: usize, rect: Rect, state: RowState) anyerror!void,
};

/// 선택 · 스크롤을 듣는 곳(창 층의 `tk> list` · `tk> scroll` 줄 — kit은 창을 모르므로 바깥이 찍는다).
pub const ListEvent = union(enum) {
    /// 키 · 클릭마다 하나(바뀌지 않았어도).
    select: struct { sel: usize, first: u64, offset: u64 },
    /// 휠마다 하나.
    scroll: struct { offset: u64 },
};

pub const ListHook = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, list: *List, ev: ListEvent) void,
};

pub const List = struct {
    view: View,
    tree: *Tree,
    highlight: *Layer,
    text: *Layer,
    bar: *Layer,
    source: ListSource,
    anim_ms: u32,
    offset: u64 = 0,
    selected: usize = 0,
    focused: bool = false,
    window_focused: bool = false,
    hook: ?ListHook = null,

    const vtable: VTable = .{
        .keyDown = keyDown,
        .scroll = scroll,
        .mouseDown = mouseDown,
        .acceptsFocus = acceptsFocus,
        .focusChanged = focusChanged,
        .windowFocusChanged = windowFocusChanged,
    };

    /// 레이어 넷을 만든다(어디에도 안 붙음 — 앱이 `view.layer`를 붙인다). `self`는 리스트가 사는 동안 옮기지 않는다(레이어 · 뷰가 가리킨다).
    pub fn init(self: *List, tree: *Tree, name: []const u8, source: ListSource, anim_ms: u32) !void {
        const container = try tree.create(.{ .background = tokens.color.bg, .masks = true });
        const highlight = try tree.create(.{ .background = tokens.color.selection_inactive, .hidden = true });
        const text = try tree.create(.{ .content = .{ .ctx = self, .draw = drawText } });
        const bar = try tree.create(.{ .background = tokens.color.text_dim, .radius = BAR_W / 2, .hidden = true });
        try container.addChild(highlight);
        try container.addChild(text);
        try container.addChild(bar);
        self.* = .{
            .view = .{ .layer = container, .vtable = &vtable, .ctx = self, .name = name },
            .tree = tree,
            .highlight = highlight,
            .text = text,
            .bar = bar,
            .source = source,
            .anim_ms = anim_ms,
        };
        container.owner = &self.view;
    }

    pub fn deinit(self: *List, alloc: std.mem.Allocator) void {
        self.view.deinit(alloc);
    }

    // ── 셈(행 수에 비례하지 않는다) ─────────────────────────────────────

    pub fn rowH() u64 {
        return @intFromFloat(tokens.size.row);
    }

    pub fn count(self: *const List) usize {
        return self.source.count(self.source.ctx);
    }

    /// 뷰의 높이(논리 px, 내림).
    pub fn viewH(self: *const List) u64 {
        const h = self.view.layer.frame.h;
        return if (h > 0) @intFromFloat(@floor(h)) else 0;
    }

    pub fn maxOffset(self: *const List) u64 {
        const content = @as(u64, self.count()) * rowH();
        const vh = self.viewH();
        return if (content > vh) content - vh else 0;
    }

    /// 처음 보이는 행.
    pub fn first(self: *const List) u64 {
        return self.offset / rowH();
    }

    /// 보이는 행의 끝(넣지 않음) — `ceil((offset + view_h) / row_h)`를 행 수로 자른다.
    pub fn visibleEnd(self: *const List) u64 {
        const end = (self.offset + self.viewH() + rowH() - 1) / rowH();
        return @min(end, @as(u64, self.count()));
    }

    /// PgDn · PgUp의 한 번: 보이는 행 수 − 1(적어도 1).
    pub fn page(self: *const List) usize {
        const rows = self.viewH() / rowH();
        return @intCast(@max(rows, 2) - 1);
    }

    // ── 배치 ────────────────────────────────────────────────────────

    /// 컨테이너의 frame이 정해진 뒤(그리고 바뀔 때마다) — 글자 레이어 · 강조 · 막대를 맞추고 오프셋을 자른다.
    pub fn sync(self: *List) void {
        const c = self.view.layer.frame;
        self.text.setFrame(.{ .x = 0, .y = 0, .w = c.w, .h = c.h });
        const before = self.offset;
        self.offset = @min(self.offset, self.maxOffset());
        if (self.offset != before) self.text.setNeedsDisplay();
        self.placeHighlight(false);
        self.placeBar();
        self.updateColor();
    }

    fn placeHighlight(self: *List, animate: bool) void {
        const n = self.count();
        if (n == 0) {
            self.tree.cancel(self.highlight, .frame);
            self.highlight.setHidden(true);
            return;
        }
        const y: i64 = @as(i64, @intCast(@as(u64, self.selected) * rowH())) - @as(i64, @intCast(self.offset));
        const vh: i64 = @intCast(self.viewH());
        const rh: i64 = @intCast(rowH());
        if (y + rh <= 0 or y >= vh) {
            // 보이지 않는다 — 숨긴다(멀리 있는 y를 f32 frame에 넣지 않는다).
            self.tree.cancel(self.highlight, .frame);
            self.highlight.setHidden(true);
            return;
        }
        const f: RectF = .{ .x = 0, .y = @floatFromInt(y), .w = self.view.layer.frame.w, .h = tokens.size.row };
        if (animate and !self.highlight.hidden and self.anim_ms > 0) {
            self.tree.animate(self.highlight, .{ .frame = f }, self.anim_ms, .ease_out_cubic) catch {
                self.tree.cancel(self.highlight, .frame);
                self.highlight.setFrame(f);
            };
        } else {
            self.tree.cancel(self.highlight, .frame);
            self.highlight.setFrame(f);
        }
        self.highlight.setHidden(false);
    }

    fn placeBar(self: *List) void {
        const content = @as(u64, self.count()) * rowH();
        const vh = self.viewH();
        if (content <= vh or vh == 0) {
            self.bar.setHidden(true);
            return;
        }
        const h: f64 = @floatFromInt(vh);
        const bh: f64 = @max(BAR_MIN_H, @floor(h * h / @as(f64, @floatFromInt(content))));
        const t: f64 = @as(f64, @floatFromInt(self.offset)) / @as(f64, @floatFromInt(content - vh));
        const y: f64 = @round((h - bh) * t);
        self.bar.setFrame(.{ .x = self.view.layer.frame.w - BAR_W, .y = @floatCast(y), .w = BAR_W, .h = @floatCast(bh) });
        self.bar.setHidden(false);
    }

    fn updateColor(self: *List) void {
        self.highlight.setBackground(if (self.focused and self.window_focused) tokens.color.selection else tokens.color.selection_inactive);
    }

    // ── 바꾸기 ──────────────────────────────────────────────────────

    /// 오프셋을 `o`로(잘라서). 바뀌면 리스트 통째를 다시 그린다.
    fn setOffset(self: *List, o: u64) bool {
        const v = @min(o, self.maxOffset());
        if (v == self.offset) return false;
        self.offset = v;
        self.text.setNeedsDisplay();
        self.placeBar();
        return true;
    }

    /// 선택을 `index`로 — 보이게 최소만 스크롤하고, 스크롤이 없으면 강조를 애니메이션으로 옮긴다. 줄 하나.
    pub fn select(self: *List, index: usize) void {
        const n = self.count();
        if (n != 0) {
            self.selected = @min(index, n - 1);
            const top = @as(u64, self.selected) * rowH();
            const bottom = top + rowH();
            const vh = self.viewH();
            var want = self.offset;
            if (top < self.offset) want = top else if (bottom > self.offset + vh) want = bottom -| vh;
            const scrolled = self.setOffset(want);
            self.placeHighlight(!scrolled);
        }
        self.emit(.{ .select = .{ .sel = self.selected, .first = self.first(), .offset = self.offset } });
    }

    fn emit(self: *List, ev: ListEvent) void {
        if (self.hook) |h| h.on(h.ctx, self, ev);
    }

    // ── 뷰 ──────────────────────────────────────────────────────────

    fn me(ctx: *anyopaque) *List {
        return @ptrCast(@alignCast(ctx));
    }

    fn keyDown(ctx: *anyopaque, ev: input.KeyEvent) bool {
        const self = me(ctx);
        const s = self.selected;
        const n = self.count();
        const last = if (n == 0) 0 else n - 1;
        const to: usize = switch (ev.key) {
            .down => @min(s + 1, last),
            .up => s -| 1,
            .page_down => @min(s +| self.page(), last),
            .page_up => s -| self.page(),
            .home => 0,
            .end => last,
            else => return false,
        };
        // Super · Ctrl이 섞인 이동 키는 리스트의 것이 아니다(TK-M6의 단축키 자리).
        if (ev.mods.super or ev.mods.ctrl or ev.mods.alt) return false;
        self.select(to);
        return true;
    }

    fn scroll(ctx: *anyopaque, ev: input.ScrollEvent) bool {
        const self = me(ctx);
        const delta: i64 = if (ev.discrete != 0)
            @as(i64, ev.discrete) * @as(i64, @intCast(WHEEL_ROWS * rowH()))
        else
            @intFromFloat(@round(ev.dy));
        const o: i64 = @as(i64, @intCast(self.offset)) + delta;
        if (self.setOffset(if (o < 0) 0 else @intCast(o))) self.placeHighlight(false);
        self.emit(.{ .scroll = .{ .offset = self.offset } });
        return true;
    }

    fn mouseDown(ctx: *anyopaque, ev: input.ButtonEvent, lx: f32, ly: f32) bool {
        _ = ev;
        _ = lx;
        const self = me(ctx);
        if (ly < 0) return false;
        const row = (self.offset + @as(u64, @intFromFloat(@floor(ly)))) / rowH();
        if (row < self.count()) self.select(@intCast(row));
        return true;
    }

    fn acceptsFocus(_: *anyopaque) bool {
        return true;
    }

    fn focusChanged(ctx: *anyopaque, on: bool) void {
        const self = me(ctx);
        self.focused = on;
        self.updateColor();
    }

    fn windowFocusChanged(ctx: *anyopaque, on: bool) void {
        const self = me(ctx);
        self.window_focused = on;
        self.updateColor();
    }

    // ── 그리기 ──────────────────────────────────────────────────────

    /// 글자 레이어의 content — clip과 겹치는 보이는 행만 `drawRow`(clip 밖 행은 글자를 하나씩 자르는 값도 안 치른다 — 조사 5절).
    fn drawText(ctx: *anyopaque, p: *Painter, size: [2]f32, alpha: u8) anyerror!void {
        const self = me(ctx);
        const clip = p.clipBounds() orelse return;
        const s: i64 = @intCast(self.tree.scale);
        // 레이어 왼쪽 위 기준의 clip 세로 범위(물리).
        const cy0: i64 = clip.y - p.ty;
        const cy1: i64 = cy0 + clip.h;
        const rh: i64 = @intCast(rowH());
        const w: i32 = @intFromFloat(@ceil(size[0]));
        const on = self.focused and self.window_focused;
        var i = self.first();
        const end = self.visibleEnd();
        while (i < end) : (i += 1) {
            const y = (@as(i64, @intCast(i * rowH())) - @as(i64, @intCast(self.offset))) * s;
            if (y + rh * s <= cy0 or y >= cy1) continue;
            const rect: Rect = .{ .x = 0, .y = @intCast(y), .w = w, .h = @intCast(rh * s) };
            try self.source.drawRow(self.source.ctx, p, @intCast(i), rect, .{ .selected = i == self.selected, .focused = on, .alpha = alpha });
        }
    }
};
