//! 뷰와 responder chain(AppKit 층, R-KIT-1 · 2, TK-M2 plan 확정 6 · 7).
//!
//! 뷰가 레이어를 가진다(layer-backed view). 뷰 트리는 키 · 포커스 · 포인터의 길이고 그림은 레이어 트리가 한다 — 뷰 하나가 레이어
//! 여럿을 가질 수 있다(리스트 = 바탕 · 강조 · 글자). 뷰를 트리에 붙이면 그 레이어의 `owner`가 그 뷰가 된다 — CA의 hit-test가 돌려준
//! 레이어에서 조상으로 올라가며 처음 만나는 `owner`가 포인터 아래의 뷰다(CA는 뷰를 모른다).
//!
//! 길(`Root.handle`):
//! - 키(누름만 — 반복 포함): first responder → 부모 → … → 루트 뷰의 `keyDown`. 받으면(참) 멈춘다. 아무도 안 받으면 Tab · Shift+Tab
//!   (Ctrl · Alt · Super 없이)은 루트가 포커스를 옮기고(R-KIT-2), 나머지는 `Root.unhandled`(TK-M6의 단축키 표 자리). Super가 섞인 키도
//!   같은 길이다(원래 모드 — 요구사항 결정 3). 뗌은 지금 아무 뷰도 안 쓴다.
//! - 포커스 순서: 뷰 트리의 깊이 우선(앞 순서)에서 `acceptsFocus`이고 보이는(자기와 조상 레이어가 hidden이 아닌) 뷰. 끝에서 처음으로 돈다.
//! - 클릭(왼쪽 버튼 누름): hit-test → 그 뷰에서 조상으로 `acceptsFocus`인 첫 뷰가 first responder → `mouseDown`은 맞은 뷰부터 조상으로.
//! - 휠: 포인터 아래 뷰부터 조상으로 `scroll`을 받는 첫 뷰(포커스와 상관없다 — AppKit과 같다).
//! - 창의 키보드 포커스(`focus`): 모든 뷰에 `windowFocusChanged`(리스트 강조의 활성 · 비활성).
//!
//! 뷰의 메모리는 그것을 가진 위젯이 든다(구조체 안에 `View`를 둔다). 자식 목록만 `addChild`의 allocator로 잡고 `deinit`이 놓는다.

const std = @import("std");
const input = @import("tk_input");
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

    pub fn init(tree: *Tree) Root {
        return .{ .tree = tree };
    }

    pub fn setView(self: *Root, v: *View) void {
        self.view = v;
        v.layer.owner = v;
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
            .key => |k| if (k.pressed) self.keyDown(k),
            .focus => |f| {
                self.window_focused = f;
                if (self.view) |v| notifyWindowFocus(v, f);
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
        var v = self.first orelse self.view;
        while (v) |x| : (v = x.parent) {
            if (x.vtable.keyDown) |f| if (f(x.ctx, k)) return;
        }
        if (k.key == .tab and !k.mods.ctrl and !k.mods.alt and !k.mods.super) {
            self.focusNext(k.mods.shift);
            return;
        }
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
