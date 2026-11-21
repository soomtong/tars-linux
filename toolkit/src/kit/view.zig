//! 뷰와 responder chain(AppKit 층, R-KIT-1 · 2, TK-M2 plan 확정 6 · 7).
//!
//! 뷰가 레이어를 가진다(layer-backed view). 뷰 트리는 키 · 포커스 · 포인터의 길이고 그림은 레이어 트리가 한다 — 뷰 하나가 레이어
//! 여럿을 가질 수 있다(리스트 = 바탕 · 강조 · 글자). 뷰를 트리에 붙이면 그 레이어의 `owner`가 그 뷰가 된다 — CA의 hit-test가 돌려준
//! 레이어에서 조상으로 올라가며 처음 만나는 `owner`가 포인터 아래의 뷰다(CA는 뷰를 모른다).
//!
//! 길(`Root.handle`):
//! - 키(누름만 — 반복 포함, TK-M6 plan 확정 3): (가) Super가 섞인 키는 먼저 메뉴 표(`Root.menu`, 없으면 `tk_menu.default_table`)에 맞춘다 —
//!   맞으면 그 항목의 action을 `validate`로 chain에 묻고 활성이면 `perform`을 chain으로, 비활성이면 먹고 끝(macOS의 key equivalent). (나) 안
//!   맞으면 first responder → 부모 → … → 루트 뷰의 `keyDown`. 받으면(참) 멈춘다. 아무도 안 받으면 Tab · Shift+Tab(Ctrl · Alt · Super 없이)은
//!   루트가 포커스를 옮기고(R-KIT-2), (다) 수정키 없는 키는 메뉴 표를 한 번 더 본다(`Space` — 필드에서는 글자라 여기 안 온다), 나머지는
//!   `Root.unhandled`. 뗌은 지금 아무 뷰도 안 쓴다.
//! - action(TK-M6 plan 확정 2 · 5, R-KIT-9): 메뉴 항목 하나가 단축키와 메뉴 둘 다의 원천이다. `validate`는 first responder(없으면 루트 뷰)부터
//!   조상으로 처음 null이 아닌 답을 쓰고(아무도 모르면 비활성), `perform`은 같은 길에서 처음 참을 돌려준 뷰에서 멈춘다. 그래서 `copy`는 필드가
//!   first responder면 필드의 것, 아니면 루트 뷰(앱)의 것이다. 서버 메뉴의 `activated(id)`(`Event.menu`)도 같은 함수를 지난다.
//! - 메뉴의 비활성(plan 확정 6): 입력 이벤트(수정키 아닌 키 누름 · 버튼 누름 · 창 포커스 · menu) 하나를 처리한 뒤 모든 항목을 다시 묻고, 지난번과
//!   다를 때만 `menu_hook`으로 보낸다. 수정키 · 포인터 움직임 · 휠 · ime · idle에서는 셈하지 않는다 — 서버 메뉴가 열린 동안 앱에 오는 것은 수정키
//!   뿐이고(그리고 열 때 서버가 확정한 ime 하나), 그때 다시 보내면 서버가 열린 메뉴를 닫는다(`why=model`).
//! - 포커스 순서: 뷰 트리의 깊이 우선(앞 순서)에서 `acceptsFocus`이고 보이는(자기와 조상 레이어가 hidden이 아닌) 뷰. 끝에서 처음으로 돈다.
//! - 클릭(왼쪽 버튼 누름): hit-test → 그 뷰에서 조상으로 `acceptsFocus`인 첫 뷰가 first responder → `mouseDown`은 맞은 뷰부터 조상으로.
//! - 휠: 포인터 아래 뷰부터 조상으로 `scroll`을 받는 첫 뷰(포커스와 상관없다 — AppKit과 같다).
//! - 창의 키보드 포커스(`focus`): 모든 뷰에 `windowFocusChanged`(리스트 강조의 활성 · 비활성).
//!
//! 뷰의 메모리는 그것을 가진 위젯이 든다(구조체 안에 `View`를 둔다). 자식 목록만 `addChild`의 allocator로 잡고 `deinit`이 놓는다.

const std = @import("std");
const input = @import("tk_input");
const menu = @import("tk_menu");
const ca = @import("tk_ca");
const Layer = ca.Layer;
const Tree = ca.Tree;

pub const VTable = struct {
    /// 키 누름. 받았으면 참(체인이 멈춘다).
    keyDown: ?*const fn (ctx: *anyopaque, ev: input.KeyEvent) bool = null,
    /// 휠. 받았으면 참.
    scroll: ?*const fn (ctx: *anyopaque, ev: input.ScrollEvent) bool = null,
    /// 왼쪽 버튼 누름. `lx` · `ly`는 이 뷰 레이어의 왼쪽 위 기준(논리). 받았으면 참.
    mouseDown: ?*const fn (ctx: *anyopaque, ev: input.ButtonEvent, lx: f32, ly: f32) bool = null,
    /// first responder가 될 수 있는가. 없으면 거짓.
    acceptsFocus: ?*const fn (ctx: *anyopaque) bool = null,
    /// first responder가 됐다(참) · 그만뒀다(거짓).
    focusChanged: ?*const fn (ctx: *anyopaque, focused: bool) void = null,
    /// 창이 키보드 포커스를 얻었다 · 잃었다.
    windowFocusChanged: ?*const fn (ctx: *anyopaque, focused: bool) void = null,
    /// IME의 확정 · 조합(TK-M4). 받았으면 참.
    textInput: ?*const fn (ctx: *anyopaque, ev: input.ImeEvent) bool = null,
    /// first responder일 때 text-input을 켜야 하는가(텍스트 필드 — TK design 결정 8). 없으면 거짓.
    wantsTextInput: ?*const fn (ctx: *anyopaque) bool = null,
    /// action 하나를 한다(TK-M6 plan 확정 2). 했으면 참(chain이 멈춘다).
    perform: ?*const fn (ctx: *anyopaque, action: u32) bool = null,
    /// action이 지금 되는가. 모르면 null(부모에게 묻는다).
    validate: ?*const fn (ctx: *anyopaque, action: u32) ?bool = null,
};

pub const View = struct {
    layer: *Layer,
    parent: ?*View = null,
    children: std.ArrayList(*View) = .empty,
    vtable: *const VTable,
    ctx: *anyopaque,
    /// 줄(`tk> focus view=`)과 검사에서 부르는 이름.
    name: []const u8,

    pub fn deinit(self: *View, alloc: std.mem.Allocator) void {
        self.children.deinit(alloc);
    }

    /// 자식 뷰를 붙인다(레이어는 붙이지 않는다 — 레이어 트리는 위젯이 짠다). 자식 레이어의 `owner`가 그 뷰가 된다.
    pub fn addChild(self: *View, alloc: std.mem.Allocator, child: *View) !void {
        std.debug.assert(child.parent == null);
        try self.children.append(alloc, child);
        child.parent = self;
        child.layer.owner = child;
    }

    /// 자식 뷰를 뗀다(TK-M3 — column view의 열 풀). 레이어는 건드리지 않는다(레이어 트리는 위젯이 뗀다). 떼어 낸 뷰나 그 자손이
    /// first responder였으면 부르는 쪽이 `Root.viewRemoved`로 알린다.
    pub fn removeChild(self: *View, child: *View) void {
        const i = std.mem.indexOfScalar(*View, self.children.items, child) orelse return;
        _ = self.children.orderedRemove(i);
        child.parent = null;
    }

    /// `self`가 `v`이거나 `v`의 자손이다.
    pub fn within(self: *const View, v: *const View) bool {
        var x: ?*const View = self;
        while (x) |y| : (x = y.parent) if (y == v) return true;
        return false;
    }

    pub fn acceptsFocus(self: *const View) bool {
        const f = self.vtable.acceptsFocus orelse return false;
        return f(self.ctx);
    }

    /// 자기 레이어와 그 조상 레이어 어느 것도 hidden이 아니다.
    pub fn visible(self: *const View) bool {
        var l: ?*const Layer = self.layer;
        while (l) |x| : (l = x.parent) if (x.hidden) return false;
        return true;
    }
};

/// first responder가 바뀐 것을 듣는 곳(창 층의 `tk> focus view=` 줄 — kit은 창을 모르므로 바깥이 찍는다).
pub const FocusHook = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, view: ?*View) void,
};

/// 클릭(왼쪽 누름)이 맞힌 뷰를 듣는 곳(`tk> hit x= y= view=` 줄 — TK-M2 plan 확정 14). 아무 뷰도 아니면 null.
pub const HitHook = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, x: f32, y: f32, view: ?*View) void,
};

/// text-input을 켜고 끄는 곳(TK-M4 plan 확정 10 — kit은 창을 모르므로 `tk.connectIme`가 창의 `setTextInput`에 잇는다). first responder가
/// 바뀔 때 그 뷰의 `wantsTextInput`이 바뀌었으면 부른다.
pub const ImeHook = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, on: bool) void,
};

/// 체인 끝까지 아무도 안 받은 키.
pub const Unhandled = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, ev: input.KeyEvent) void,
};

/// action이 어느 길로 왔나(줄 `tk> action name= via=`).
pub const Via = enum { key, menu };

/// action을 했다(창 층의 줄 — kit은 창을 모르므로 바깥이 찍는다).
pub const ActionHook = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, name: []const u8, via: Via) void,
};

/// 메뉴의 비활성이 바뀌었다 — 모델 전체를 다시 보낼 때(`tk.connectMenu`가 창의 `sendMenu`에 잇는다).
pub const MenuHook = struct {
    ctx: *anyopaque,
    send: *const fn (ctx: *anyopaque, disabled: *const menu.Disabled) void,
};

/// 창 하나의 뷰 트리 뿌리와 입력 상태(first responder · 창 포커스 · 포인터 자리).
pub const Root = struct {
    tree: *Tree,
    view: ?*View = null,
    first: ?*View = null,
    window_focused: bool = false,
    ptr_x: f32 = 0,
    ptr_y: f32 = 0,
    hook: ?FocusHook = null,
    hit_hook: ?HitHook = null,
    unhandled: ?Unhandled = null,
    ime_hook: ?ImeHook = null,
    /// 지금 켜 달라고 한 값(훅에 마지막으로 알린 것).
    ime_want: bool = false,
    /// 앱의 메뉴 모델(TK-M6). null이면 키는 `tk_menu.default_table`에 맞춘다.
    menu: ?*const menu.Model = null,
    /// 마지막으로 셈한(보낸) 비활성.
    disabled: menu.Disabled = .empty,
    menu_hook: ?MenuHook = null,
    action_hook: ?ActionHook = null,

    pub fn init(tree: *Tree) Root {
        return .{ .tree = tree };
    }

    pub fn setView(self: *Root, v: *View) void {
        self.view = v;
        v.layer.owner = v;
    }

    /// 앱의 메뉴 모델을 건다(뷰 트리와 first responder를 세운 뒤 — 첫 비활성을 여기서 셈한다, 창을 열 때 그것을 함께 보낸다).
    pub fn setMenu(self: *Root, m: *const menu.Model) void {
        self.menu = m;
        self.computeDisabled(&self.disabled);
    }

    fn table(self: *const Root) *const menu.Model {
        return self.menu orelse &menu.default_table;
    }

    /// action이 지금 되는가 — first responder(없으면 루트 뷰)부터 조상으로 처음 답한 뷰. 아무도 모르면 거짓.
    pub fn validate(self: *const Root, action: u32) bool {
        return self.answer(action) orelse false;
    }

    /// chain의 첫 답(아무도 모르면 null).
    fn answer(self: *const Root, action: u32) ?bool {
        var v = self.first orelse self.view;
        while (v) |x| : (v = x.parent) {
            if (x.vtable.validate) |f| if (f(x.ctx, action)) |r| return r;
        }
        return null;
    }

    /// action을 chain으로 — 처음 한 뷰에서 멈춘다. 아무도 안 했으면 거짓.
    pub fn perform(self: *Root, action: u32) bool {
        var v = self.first orelse self.view;
        while (v) |x| : (v = x.parent) {
            if (x.vtable.perform) |f| if (f(x.ctx, action)) return true;
        }
        return false;
    }

    /// 메뉴 항목 하나를 쏜다: 되면 하고 줄, 안 되면 아무것도(키 · 메뉴 둘 다 먹은 채).
    fn fire(self: *Root, it: menu.Item, via: Via) void {
        if (!self.validate(it.action)) return;
        if (!self.perform(it.action)) return;
        if (self.action_hook) |h| h.on(h.ctx, it.name, via);
    }

    /// 모델의 모든 항목을 chain에 물어 비활성 비트를 셈한다(구분선 자리는 0).
    pub fn computeDisabled(self: *const Root, out: *menu.Disabled) void {
        out.* = .empty;
        const m = self.menu orelse return;
        const n = m.entryCount();
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const it = m.itemAt(i) orelse continue;
            if (!self.validate(it.action)) out.set(i);
        }
    }

    /// 입력 하나 뒤의 다시 셈(plan 확정 6) — 바뀌었으면 보낸다.
    fn refreshMenu(self: *Root) void {
        if (self.menu == null) return;
        var now: menu.Disabled = undefined;
        self.computeDisabled(&now);
        if (now.eql(self.disabled)) return;
        self.disabled = now;
        if (self.menu_hook) |h| h.send(h.ctx, &self.disabled);
    }

    /// `v`를 first responder로(null이면 아무도). `acceptsFocus`가 아니면 거짓이고 그대로다.
    pub fn setFirstResponder(self: *Root, v: ?*View) bool {
        if (v == self.first) return true;
        if (v) |nv| if (!nv.acceptsFocus()) return false;
        if (self.first) |old| if (old.vtable.focusChanged) |f| f(old.ctx, false);
        self.first = v;
        if (v) |nv| if (nv.vtable.focusChanged) |f| f(nv.ctx, true);
        if (self.hook) |h| h.on(h.ctx, v);
        self.syncIme();
        return true;
    }

    /// first responder가 text-input을 바라는지 훅에 맞춘다(바뀌었을 때만).
    fn syncIme(self: *Root) void {
        const want = if (self.first) |f| (if (f.vtable.wantsTextInput) |w| w(f.ctx) else false) else false;
        if (want == self.ime_want) return;
        self.ime_want = want;
        if (self.ime_hook) |h| h.on(h.ctx, want);
    }

    /// 뷰 `v`를 트리에서 뗐다 — first responder가 `v`나 그 자손이면 아무도 아니게 한다(`focusChanged(false)` · 줄). 새 자리는 부르는
    /// 쪽이 정한다(column view는 떼기 전에 포커스 열로 옮겨 이것이 할 일이 없게 한다).
    pub fn viewRemoved(self: *Root, v: *const View) void {
        const f = self.first orelse return;
        if (f.within(v)) _ = self.setFirstResponder(null);
    }

    /// 창 층의 이벤트 하나.
    pub fn handle(self: *Root, ev: input.Event) void {
        switch (ev) {
            .key => |k| if (k.pressed) {
                self.keyDown(k);
                if (!input.isModifier(k.code)) self.refreshMenu();
            },
            .focus => |f| {
                self.window_focused = f;
                if (self.view) |v| notifyWindowFocus(v, f);
                self.refreshMenu();
            },
            .menu => |id| {
                if (menu.find(self.table(), id)) |hit| self.fire(hit.item, .menu);
                self.refreshMenu();
            },
            .pointer_motion => |m| {
                self.ptr_x = m.x;
                self.ptr_y = m.y;
            },
            .pointer_leave => {},
            .button => |b| {
                self.ptr_x = b.x;
                self.ptr_y = b.y;
                if (b.pressed and b.code == input.BTN_LEFT) self.mouseDown(b);
                if (b.pressed) self.refreshMenu();
            },
            .ime => |m| {
                var v = self.first;
                while (v) |x| : (v = x.parent) {
                    if (x.vtable.textInput) |f| if (f(x.ctx, m)) return;
                }
            },
            .scroll => |s| {
                var v = self.viewAt(s.x, s.y);
                while (v) |x| : (v = x.parent) {
                    if (x.vtable.scroll) |f| if (f(x.ctx, s)) return;
                }
            },
        }
    }

    fn keyDown(self: *Root, k: input.KeyEvent) void {
        // (가) Super가 섞인 키 — 메뉴 표가 먼저(비활성이어도 먹는다). 모델이 없을 때의 기본 표는 chain의 누군가가 그 action을 알 때만 단축키다 —
        // 필드가 없는 데모의 `Cmd+A`는 지금처럼 chain · `unhandled`로 간다.
        if (k.mods.super) if (menu.match(self.table(), k.mods, k.code)) |hit| {
            if (self.menu != null or self.answer(hit.item.action) != null) return self.fire(hit.item, .key);
        };
        // (나) chain.
        var v = self.first orelse self.view;
        while (v) |x| : (v = x.parent) {
            if (x.vtable.keyDown) |f| if (f(x.ctx, k)) return;
        }
        if (k.key == .tab and !k.mods.ctrl and !k.mods.alt and !k.mods.super) {
            self.focusNext(k.mods.shift);
            return;
        }
        // (다) chain이 다 거절한 수정키 없는 키.
        if (k.mods.none()) if (menu.match(self.table(), k.mods, k.code)) |hit| {
            if (self.menu != null or self.answer(hit.item.action) != null) return self.fire(hit.item, .key);
        };
        if (self.unhandled) |u| u.on(u.ctx, k);
    }

    fn mouseDown(self: *Root, b: input.ButtonEvent) void {
        const hit_v = self.viewAt(b.x, b.y);
        if (self.hit_hook) |h| h.on(h.ctx, b.x, b.y, hit_v);
        const hit = hit_v orelse return;
        var f: ?*View = hit;
        while (f) |x| : (f = x.parent) {
            if (x.acceptsFocus()) {
                _ = self.setFirstResponder(x);
                break;
            }
        }
        var v: ?*View = hit;
        while (v) |x| : (v = x.parent) {
            const md = x.vtable.mouseDown orelse continue;
            const o = x.layer.origin();
            if (md(x.ctx, b, b.x - o[0], b.y - o[1])) return;
        }
    }

    /// 점 (x, y) 아래의 뷰 — hit-test가 준 레이어에서 조상으로 올라가며 처음 만나는 `owner`.
    pub fn viewAt(self: *Root, x: f32, y: f32) ?*View {
        var l = self.tree.hitTest(x, y);
        while (l) |layer| : (l = layer.parent) {
            if (layer.owner) |o| return @ptrCast(@alignCast(o));
        }
        return null;
    }

    /// Tab(`backward` 거짓) · Shift+Tab. 순서에 뷰가 없으면 아무것도 안 한다.
    pub fn focusNext(self: *Root, backward: bool) void {
        const root = self.view orelse return;
        var w: Walk = .{ .current = self.first };
        w.visit(root);
        const next = if (backward)
            (w.before orelse w.last)
        else
            (w.after orelse w.first);
        if (next) |n| _ = self.setFirstResponder(n);
    }
};

/// 포커스 순서를 한 번 걸으며 지금 것의 앞 · 뒤와 처음 · 끝을 모은다(메모리를 잡지 않는다).
const Walk = struct {
    current: ?*View,
    seen: bool = false,
    first: ?*View = null,
    last: ?*View = null,
    before: ?*View = null,
    after: ?*View = null,

    fn visit(self: *Walk, v: *View) void {
        if (v.acceptsFocus() and v.visible()) {
            if (self.first == null) self.first = v;
            self.last = v;
            if (v == self.current) {
                self.seen = true;
            } else if (!self.seen) {
                self.before = v;
            } else if (self.after == null) {
                self.after = v;
            }
        }
        for (v.children.items) |c| self.visit(c);
    }
};

fn notifyWindowFocus(v: *View, f: bool) void {
    if (v.vtable.windowFocusChanged) |cb| cb(v.ctx, f);
    for (v.children.items) |c| notifyWindowFocus(c, f);
}
