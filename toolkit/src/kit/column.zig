//! column view(R-KIT-5, TK-M3 plan 확정 2~6) — 리스트의 가로 스택. Miller column의 뼈대이고 파일을 모른다: 열마다의 데이터와 "이 행이
//! 열리는가"는 `ColumnSource`가 준다(앱이 파일 · 로딩을 든다).
//!
//! 레이어: 컨테이너(뷰의 레이어 — masks, 바탕) → 내용(x = −scroll, 폭 = 열 수 × 201) → 열마다 리스트 컨테이너(x = i × 201, 폭
//! `tokens.size.column` 200) + 오른쪽 1 px 구분선(`TK_SEPARATOR`). 끌어서 폭 바꾸기는 없다.
//!
//! 열 모델(명시 모델 — `→`가 연다):
//! - 처음엔 열 하나(`init`의 소스). 포커스 열은 하나이고 그 리스트만 `acceptsFocus`다(확정 6 — Tab에서 column view는 한 자리).
//! - `→` · Enter(수정키 없음): 포커스 열의 오른쪽에 열이 이미 있으면 포커스만 그리로 옮긴다(그 열은 늘 지금 선택의 열이다 — 선택이
//!   바뀌면 오른쪽을 버리므로 — 선택 · 스크롤 · 로딩이 그대로 남는다). 없으면 포커스 열의 선택 행을 `ColumnSource.open`에 묻는다.
//!   열리면(소스를 돌려주면) 새 열을 붙여 포커스를 거기로(선택 0). 안 열리면(파일) 아무 일 없이 받았다고 답한다. 깊이
//!   `MAX_COLUMNS`(32)이면 거절한다.
//! - `←`(수정키 없음): 포커스를 왼쪽 열로. 오른쪽 열은 남긴다(선택이 그대로라 내용이 맞다). 첫 열에서는 아무 일 없음.
//! - 열의 선택이 키 · 클릭으로 바뀌면 그 열의 오른쪽 열을 버린다. 포커스가 아닌 열을 클릭하면 그 열이 포커스가 된다.
//! - 가로 스크롤(확정 5): 포커스 열이 보이게 최소만, 열 경계에 맞춘다 — 포커스 열의 오른쪽이 뷰 밖이면 그 열이 다 보이는 가장 작은
//!   열 왼쪽 경계, 왼쪽 밖이면 그 열의 왼쪽 경계. 열을 버리거나 창이 넓어지면 마지막 열이 보이는 가장 작은 경계까지 줄인다(다 들어가면 0).
//!   애니메이션은 없다(carryover).
//!
//! 열은 풀로 다시 쓴다(확정 4): 열 객체는 처음 쓸 때 한 번 레이어를 만들고, 버리면 레이어 · 뷰를 떼기만 하며, 다시 쓸 때
//! `List.reset(source)` — 오가도 레이어 수가 늘지 않는다.
//!
//! 앱은 컨테이너 레이어(`view.layer`)를 자기 트리에 붙이고 frame을 준 뒤 `sync()`를 부른다(분할 뷰의 알림 등) — 크기가 바뀔 때마다.

const std = @import("std");
const input = @import("tk_input");
const tokens = @import("tk_tokens");
const ca = @import("tk_ca");
const Layer = ca.Layer;
const Tree = ca.Tree;
const view_mod = @import("view.zig");
const View = view_mod.View;
const VTable = view_mod.VTable;
const Root = view_mod.Root;
const list_mod = @import("list.zig");
const List = list_mod.List;
const ListSource = list_mod.ListSource;

pub const MAX_COLUMNS: usize = 32;
/// 열 사이 구분선의 폭(논리 px).
pub const SEPARATOR_W: f32 = 1;

/// 열 i의 왼쪽(논리 px, 내용 기준).
pub fn columnX(i: usize) u64 {
    return @as(u64, i) * pitch();
}

/// 열 하나가 차지하는 폭(열 + 구분선) = 201.
pub fn pitch() u64 {
    return @as(u64, @intFromFloat(tokens.size.column)) + @as(u64, @intFromFloat(SEPARATOR_W));
}

/// 열 뷰의 이름(`tk> focus view=col1` — plan 확정 14).
const NAMES: [MAX_COLUMNS][]const u8 = blk: {
    var n: [MAX_COLUMNS][]const u8 = undefined;
    for (0..MAX_COLUMNS) |i| n[i] = std.fmt.comptimePrint("col{d}", .{i});
    break :blk n;
};

/// column view가 데이터를 받는 곳 — kit은 파일을 모른다.
pub const ColumnSource = struct {
    ctx: *anyopaque,
    /// 열 `column`의 행 `row`를 연다: 열리면(디렉터리) 오른쪽 새 열(`column + 1`)의 소스, 아니면 null. 앱은 여기서 로딩을 시작한다.
    open: *const fn (ctx: *anyopaque, column: usize, row: usize) ?ListSource,
    /// 열 `n`부터 오른쪽을 버렸다(앱이 로딩을 취소하는 자리). 열 수가 `n`이 된 뒤 부른다.
    truncated: ?*const fn (ctx: *anyopaque, n: usize) void = null,
};

/// column view의 일을 듣는 곳(앱의 `tk> columns` · `tk> column` 줄과 미리보기 — kit은 창을 모르므로 바깥이 찍는다).
pub const ColumnEvent = union(enum) {
    /// 열 수 · 포커스 열 · 가로 스크롤이 바뀌었다.
    columns: struct { n: usize, focus: usize, scroll: u64 },
    /// 열 `column`의 선택(키 · 클릭마다 — 바뀌지 않았어도).
    select: struct { column: usize, sel: usize, changed: bool },
};

pub const ColumnHook = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, cv: *ColumnView, ev: ColumnEvent) void,
};

const Column = struct {
    list: List = undefined,
    sep: *Layer = undefined,
    inited: bool = false,
    index: usize = 0,
    owner: *ColumnView = undefined,
};

pub const ColumnView = struct {
    view: View,
    tree: *Tree,
    root: *Root,
    alloc: std.mem.Allocator,
    content: *Layer,
    source: ColumnSource,
    anim_ms: u32,
    cols: [MAX_COLUMNS]Column = @splat(.{}),
    /// 쓰는 열 수(1..MAX_COLUMNS).
    n: usize = 0,
    focus: usize = 0,
    scroll: u64 = 0,
    hook: ?ColumnHook = null,

    const vtable: VTable = .{ .keyDown = keyDown };

    /// 열 하나(첫 열의 소스 `first`)로 시작한다. 앱이 `view.layer`를 붙이고 `view`를 뷰 트리에 붙인다. `self`는 사는 동안 옮기지 않는다.
    /// 첫 열의 리스트를 first responder로 하는 것은 앱이 `focusFirst()`로.
    pub fn init(self: *ColumnView, tree: *Tree, root: *Root, alloc: std.mem.Allocator, name: []const u8, source: ColumnSource, first: ListSource, anim_ms: u32) !void {
        const container = try tree.create(.{ .background = tokens.color.bg, .masks = true });
        const content = try tree.create(.{});
        try container.addChild(content);
        self.* = .{
            .view = .{ .layer = container, .vtable = &vtable, .ctx = self, .name = name },
            .tree = tree,
            .root = root,
            .alloc = alloc,
            .content = content,
            .source = source,
            .anim_ms = anim_ms,
        };
        container.owner = &self.view;
        try self.activate(0, first);
        self.n = 1;
        self.cols[0].list.accepts_focus = true;
    }

    pub fn deinit(self: *ColumnView) void {
        for (&self.cols) |*c| if (c.inited) c.list.deinit(self.alloc);
        self.view.deinit(self.alloc);
    }

    /// 열 `i`의 리스트(쓰는 열만).
    pub fn list(self: *ColumnView, i: usize) *List {
        std.debug.assert(i < self.n);
        return &self.cols[i].list;
    }

    /// 포커스 열의 리스트를 first responder로.
    pub fn focusFirst(self: *ColumnView) void {
        _ = self.root.setFirstResponder(&self.cols[self.focus].list.view);
    }

    /// 컨테이너의 frame이 정해진 뒤(그리고 바뀔 때마다) — 열 · 구분선 · 내용 레이어를 맞추고 스크롤을 다시 셈한다.
    pub fn sync(self: *ColumnView) void {
        const h = self.view.layer.frame.h;
        for (self.cols[0..self.n], 0..) |*c, i| self.place(c, i, h);
        _ = self.updateScroll();
        self.placeContent();
    }

    fn place(self: *ColumnView, c: *Column, i: usize, h: f32) void {
        _ = self;
        const x: f32 = @floatFromInt(columnX(i));
        c.list.view.layer.setFrame(.{ .x = x, .y = 0, .w = tokens.size.column, .h = h });
        c.sep.setFrame(.{ .x = x + tokens.size.column, .y = 0, .w = SEPARATOR_W, .h = h });
        c.list.sync();
    }

    fn placeContent(self: *ColumnView) void {
        const w: f32 = @floatFromInt(@as(u64, self.n) * pitch());
        self.content.setFrame(.{ .x = -@as(f32, @floatFromInt(self.scroll)), .y = 0, .w = w, .h = self.view.layer.frame.h });
    }

    /// 포커스 열이 보이게 최소만, 열 경계에 맞춘다. 바뀌었으면 참.
    fn updateScroll(self: *ColumnView) bool {
        const vw_f = self.view.layer.frame.w;
        const vw: u64 = if (vw_f > 0) @intFromFloat(@floor(vw_f)) else 0;
        const left = columnX(self.focus);
        const right = left + @as(u64, @intFromFloat(tokens.size.column));
        // 열이 다 들어가면 0, 아니면 마지막 열(구분선까지)이 보이는 가장 작은 열 경계를 넘지 않는다(열을 버렸거나 창이 넓어졌을 때).
        const total = @as(u64, self.n) * pitch();
        const max = if (total <= vw) 0 else (total - vw + pitch() - 1) / pitch() * pitch();
        var s = @min(self.scroll, max);
        if (left < s) {
            s = left;
        } else if (right > s + vw) {
            // 오른쪽이 보이는 가장 작은 열 경계 k × 201 — 그래도 왼쪽을 넘지 않게.
            const need = right - vw;
            s = @min((need + pitch() - 1) / pitch() * pitch(), left);
        }
        if (s == self.scroll) return false;
        self.scroll = s;
        return true;
    }

    // ── 열 붙이기 · 버리기 ──────────────────────────────────────────

    fn activate(self: *ColumnView, i: usize, src: ListSource) !void {
        const c = &self.cols[i];
        if (!c.inited) {
            try c.list.init(self.tree, NAMES[i], src, self.anim_ms);
            c.sep = try self.tree.create(.{ .background = tokens.color.separator });
            c.index = i;
            c.owner = self;
            c.list.delegate = .{ .ctx = c, .selected = listSelected };
            c.inited = true;
        } else {
            c.list.reset(src);
        }
        c.list.accepts_focus = false;
        c.list.focused = false;
        c.list.window_focused = self.root.window_focused;
        try self.content.addChild(c.list.view.layer);
        try self.content.addChild(c.sep);
        try self.view.addChild(self.alloc, &c.list.view);
        self.place(c, i, self.view.layer.frame.h);
    }

    fn deactivate(self: *ColumnView, i: usize) void {
        const c = &self.cols[i];
        self.tree.cancel(c.list.highlight, .frame);
        self.content.removeChild(c.list.view.layer);
        self.content.removeChild(c.sep);
        self.view.removeChild(&c.list.view);
        self.root.viewRemoved(&c.list.view);
        c.list.accepts_focus = false;
    }

    /// 열 `n`부터 오른쪽을 버린다(열 수를 `n`으로, 1 이상). 포커스가 버린 열이면 남은 마지막 열로 먼저 옮긴다.
    pub fn truncate(self: *ColumnView, n: usize) void {
        std.debug.assert(n >= 1);
        if (n >= self.n) return;
        if (self.focus >= n) self.setFocus(n - 1);
        var i = self.n;
        while (i > n) {
            i -= 1;
            self.deactivate(i);
        }
        self.n = n;
        _ = self.updateScroll();
        self.placeContent();
        if (self.source.truncated) |f| f(self.source.ctx, n);
    }

    /// 열을 통째로 다시 세운다(TK-M4 plan 확정 14 — 경로 필드의 Enter): 열 0은 `sources[0]`로 다시 쓰고(`List.reset`), 나머지는 새로 붙인다.
    /// 포커스는 마지막 열, 가로 스크롤은 그 열이 보이게. first responder는 옮기지 않는다(앱이 `focusFirst`로 — 필드에서 돌아올 때). 줄 하나.
    pub fn setColumns(self: *ColumnView, sources: []const ListSource) !void {
        std.debug.assert(sources.len >= 1 and sources.len <= MAX_COLUMNS);
        self.truncate(1);
        self.cols[0].list.reset(sources[0]);
        var i: usize = 1;
        while (i < sources.len) : (i += 1) {
            self.activate(i, sources[i]) catch |e| {
                self.n = i;
                self.setFocus(i - 1);
                _ = self.updateScroll();
                self.placeContent();
                self.emitColumns();
                return e;
            };
            self.n = i + 1;
        }
        self.n = sources.len;
        self.setFocus(sources.len - 1);
        _ = self.updateScroll();
        self.placeContent();
        self.emitColumns();
    }

    /// 포커스 열을 `i`로(그 리스트만 first responder가 될 수 있다). first responder가 column view 안에 있었으면 새 열로 옮긴다.
    fn setFocus(self: *ColumnView, i: usize) void {
        const old = &self.cols[self.focus].list;
        const had = if (self.root.first) |f| f.within(&self.view) else false;
        old.accepts_focus = false;
        self.focus = i;
        const nl = &self.cols[i].list;
        nl.accepts_focus = true;
        if (had) _ = self.root.setFirstResponder(&nl.view);
    }

    fn emit(self: *ColumnView, ev: ColumnEvent) void {
        if (self.hook) |h| h.on(h.ctx, self, ev);
    }

    fn emitColumns(self: *ColumnView) void {
        self.emit(.{ .columns = .{ .n = self.n, .focus = self.focus, .scroll = self.scroll } });
    }

    // ── 키 · 선택 ───────────────────────────────────────────────────

    /// `→` · Enter: 포커스 열의 선택이 열리면 오른쪽에 새 열. 받았으면(열렸든 아니든) 참.
    pub fn openSelection(self: *ColumnView) void {
        const l = &self.cols[self.focus].list;
        if (l.count() == 0) return;
        // 오른쪽 열이 이미 있으면 그것은 늘 지금 선택의 열이다(선택이 바뀌면 오른쪽을 버리므로) — 새로 열지 않고 포커스만 옮긴다.
        // 그 열의 선택 · 스크롤 · 로딩이 그대로 남는다.
        if (self.focus + 1 < self.n) {
            self.setFocus(self.focus + 1);
        } else {
            if (self.focus + 1 >= MAX_COLUMNS) return;
            const src = self.source.open(self.source.ctx, self.focus, l.selected) orelse return;
            self.activate(self.focus + 1, src) catch return;
            self.n = self.focus + 2;
            self.setFocus(self.focus + 1);
        }
        _ = self.updateScroll();
        self.placeContent();
        self.emitColumns();
    }

    /// `←`: 포커스를 왼쪽 열로(오른쪽 열은 남는다).
    pub fn focusLeft(self: *ColumnView) void {
        if (self.focus == 0) return;
        self.setFocus(self.focus - 1);
        _ = self.updateScroll();
        self.placeContent();
        self.emitColumns();
    }

    fn me(ctx: *anyopaque) *ColumnView {
        return @ptrCast(@alignCast(ctx));
    }

    fn keyDown(ctx: *anyopaque, ev: input.KeyEvent) bool {
        const self = me(ctx);
        if (ev.mods.shift or ev.mods.ctrl or ev.mods.alt or ev.mods.super) return false;
        switch (ev.key) {
            .right, .enter => self.openSelection(),
            .left => self.focusLeft(),
            else => return false,
        }
        return true;
    }

    /// 열 리스트의 delegate — 키 · 클릭의 선택마다.
    fn listSelected(ctx: *anyopaque, _: *List, sel: usize, changed: bool) void {
        const c: *Column = @ptrCast(@alignCast(ctx));
        const self = c.owner;
        const i = c.index;
        if (i >= self.n) return;
        var moved = false;
        if (i != self.focus) {
            self.setFocus(i);
            // 클릭은 Root가 이미 first responder를 정하려 했지만(그때는 이 열이 받지 않았다) 이제 받는다.
            _ = self.root.setFirstResponder(&c.list.view);
            moved = true;
        }
        if (changed and self.n > i + 1) {
            self.truncate(i + 1);
            moved = true;
        }
        if (moved) {
            _ = self.updateScroll();
            self.placeContent();
        }
        self.emit(.{ .select = .{ .column = i, .sel = sel, .changed = changed } });
        if (moved) self.emitColumns();
    }
};
