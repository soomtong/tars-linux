//! 레이어 트리(CA 층, R-CA-1 · 2, TK-M1 plan 확정 3 · 4). 유지 모드다 — 앱은 레이어를 만들어 속성을 바꾸고, 트리는 바뀐 사각형을 모아
//! 창에 알리고, 창이 그릴 때 clip 안만 다시 그린다. 그리기는 CG의 `Painter`만 부른다(R-ARCH-2 — 여기에 픽셀 포인터가 없다).
//!
//! 좌표: `frame`은 논리 픽셀(소수 — 애니메이션이 소수 위치를 낳는다), 부모의 왼쪽 위 기준이다. 그릴 때와 더티를 셀 때 트리의
//! `scale`을 곱해 물리로 바꾸고, 정수 사각형은 바깥쪽으로 반올림한다.
//!
//! 더티: 속성은 setter로만 바꾼다. setter는 바꾸기 전 · 뒤의 화면 사각형을 덮는 사각형을 트리에 알린다. 화면 사각형은 그 레이어와
//! (masks가 아니면) 자식들까지 덮는 것을 masks 조상으로 자른 것이다. 루트에 붙지 않은 레이어는 알리지 않는다.
//!
//! 불투명도(확정 4): 그리는 동안 누적 알파를 곱해 내려간다 — 배경과 content가 그 알파로 그려진다. 자식이 서로 겹치면 정확한 "그룹
//! 불투명도"와 다르다(carryover).
//!
//! content: 레이어가 앱의 그리기 콜백을 들 수 있다. 콜백은 레이어 왼쪽 위가 (0, 0)인 물리 좌표로 그리고(트리가 `translate`한다 — 정수로
//! 반올림한 자리), 레이어 사각형 밖에 그리면 안 된다(clip 검사가 레이어 사각형으로 건너뛰므로 밖의 잉크는 부분 그리기에서 빠진다).

const std = @import("std");
const geom = @import("tk_geom");
const Rect = geom.Rect;
const RectF = geom.RectF;
const Painter = @import("tk_cg").Painter;

pub const Content = struct {
    ctx: *anyopaque,
    /// `size`는 레이어의 물리 크기(소수), `alpha`는 누적 불투명도(0..255).
    draw: *const fn (ctx: *anyopaque, p: *Painter, size: [2]f32, alpha: u8) anyerror!void,
};

/// 트리가 더티를 알리는 곳(앱이 창의 `invalidate`에 잇는다 — CA는 창을 모른다).
pub const Sink = struct {
    ctx: *anyopaque,
    invalidate: *const fn (ctx: *anyopaque, r: Rect) void,
};

pub const Layer = struct {
    tree: *Tree,
    parent: ?*Layer = null,
    children: std.ArrayList(*Layer) = .empty,
    frame: RectF = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    background: ?u32 = null,
    radius: f32 = 0,
    opacity: f32 = 1,
    masks: bool = false,
    hidden: bool = false,
    content: ?Content = null,

    // ── setter(더티를 낸다) ───────────────────────────────────────────

    pub fn setFrame(self: *Layer, f: RectF) void {
        if (std.meta.eql(self.frame, f)) return;
        const before = self.dirtyRect();
        self.frame = f;
        self.tree.invalidateOpt(Rect.coverOpt(before, self.dirtyRect()));
    }

    pub fn setBackground(self: *Layer, c: ?u32) void {
        if (std.meta.eql(self.background, c)) return;
        self.background = c;
        self.setNeedsDisplay();
    }

    pub fn setRadius(self: *Layer, r: f32) void {
        if (self.radius == r) return;
        self.radius = r;
        self.setNeedsDisplay();
    }

    pub fn setOpacity(self: *Layer, o: f32) void {
        const v = std.math.clamp(o, 0, 1);
        if (self.opacity == v) return;
        self.opacity = v;
        self.tree.invalidateOpt(self.dirtyRect());
    }

    pub fn setMasks(self: *Layer, m: bool) void {
        if (self.masks == m) return;
        const before = self.dirtyRect();
        self.masks = m;
        self.tree.invalidateOpt(Rect.coverOpt(before, self.dirtyRect()));
    }

    pub fn setHidden(self: *Layer, h: bool) void {
        if (self.hidden == h) return;
        self.hidden = h;
        self.tree.invalidateOpt(self.dirtyRect());
    }

    pub fn setContent(self: *Layer, c: ?Content) void {
        self.content = c;
        self.setNeedsDisplay();
    }

    /// content가 바뀌었다 — 이 레이어의 사각형을 다시 그린다.
    pub fn setNeedsDisplay(self: *Layer) void {
        self.tree.invalidateOpt(self.dirtyRect());
    }

    pub fn addChild(self: *Layer, child: *Layer) !void {
        std.debug.assert(child.parent == null and child.tree == self.tree);
        try self.children.append(self.tree.alloc, child);
        child.parent = self;
        self.tree.invalidateOpt(child.dirtyRect());
    }

    pub fn removeChild(self: *Layer, child: *Layer) void {
        const i = std.mem.indexOfScalar(*Layer, self.children.items, child) orelse return;
        self.tree.invalidateOpt(child.dirtyRect());
        _ = self.children.orderedRemove(i);
        child.parent = null;
    }

    // ── 사각형 ─────────────────────────────────────────────────────

    /// 이 레이어의 왼쪽 위(논리, 루트 기준).
    pub fn origin(self: *const Layer) [2]f32 {
        var x: f32 = self.frame.x;
        var y: f32 = self.frame.y;
        var p = self.parent;
        while (p) |l| : (p = l.parent) {
            x += l.frame.x;
            y += l.frame.y;
        }
        return .{ x, y };
    }

    /// 화면(물리, 버퍼 좌표)의 이 레이어 사각형 — 자식은 빼고, 조상의 masks로 자르지 않은 것.
    pub fn screenRect(self: *const Layer) Rect {
        const o = self.origin();
        return physOut(.{ .x = o[0], .y = o[1], .w = self.frame.w, .h = self.frame.h }, self.tree.scale);
    }

    /// 이 레이어가 바뀌면 다시 그릴 사각형. 루트에 붙지 않았으면 null.
    pub fn dirtyRect(self: *const Layer) ?Rect {
        if (!self.attached()) return null;
        const pf = if (self.parent) |p| p.origin() else [2]f32{ 0, 0 };
        var r = subtreeRect(self, pf[0], pf[1], self.tree.scale);
        var a = self.parent;
        while (a) |l| : (a = l.parent) {
            if (l.masks) r = Rect.intersect(r, l.screenRect()) orelse return null;
        }
        return r;
    }

    fn attached(self: *const Layer) bool {
        var l: *const Layer = self;
        while (l.parent) |p| l = p;
        return self.tree.root == l;
    }
};

fn physOut(r: RectF, scale: u32) Rect {
    return r.scaled(@floatFromInt(scale)).outward();
}

/// 레이어 `l`(부모의 루트 기준 왼쪽 위 (ox, oy))과, masks가 아니면 자식들까지 덮는 물리 사각형.
fn subtreeRect(l: *const Layer, ox: f32, oy: f32, scale: u32) Rect {
    const f = l.frame.offset(ox, oy);
    var r = physOut(f, scale);
    if (l.masks) return r;
    for (l.children.items) |c| r = Rect.cover(r, subtreeRect(c, f.x, f.y, scale));
    return r;
}

pub const Tree = struct {
    alloc: std.mem.Allocator,
    root: ?*Layer = null,
    /// 물리 픽셀 = 논리 × scale.
    scale: u32 = 1,
    /// 아직 그리지 않은 더티의 합(물리). 호스트 검사가 `takeDirty`로 꺼낸다 — 창에 붙은 앱은 `sink`로 받는다.
    dirty: ?Rect = null,
    sink: ?Sink = null,
    /// 만든 레이어 전부(트리가 지운다).
    all: std.ArrayList(*Layer) = .empty,

    pub fn init(alloc: std.mem.Allocator) Tree {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Tree) void {
        for (self.all.items) |l| {
            l.children.deinit(self.alloc);
            self.alloc.destroy(l);
        }
        self.all.deinit(self.alloc);
    }

    /// 새 레이어(어디에도 안 붙음). 메모리는 트리가 든다.
    pub fn create(self: *Tree, init_: struct {
        frame: RectF = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        background: ?u32 = null,
        radius: f32 = 0,
        opacity: f32 = 1,
        masks: bool = false,
        hidden: bool = false,
        content: ?Content = null,
    }) !*Layer {
        try self.all.ensureUnusedCapacity(self.alloc, 1);
        const l = try self.alloc.create(Layer);
        l.* = .{
            .tree = self,
            .frame = init_.frame,
            .background = init_.background,
            .radius = init_.radius,
            .opacity = init_.opacity,
            .masks = init_.masks,
            .hidden = init_.hidden,
            .content = init_.content,
        };
        self.all.appendAssumeCapacity(l);
        return l;
    }

    pub fn setRoot(self: *Tree, l: ?*Layer) void {
        if (self.root) |r| self.invalidateOpt(r.dirtyRect());
        self.root = l;
        if (l) |r| self.invalidateOpt(r.dirtyRect());
    }

    /// 배율이 바뀌었다 — 물리 사각형이 다 바뀐다. 창 층은 이때 어차피 통째로 그린다.
    pub fn setScale(self: *Tree, s: u32) void {
        if (self.scale == s) return;
        self.scale = s;
        if (self.root) |r| self.invalidateOpt(r.dirtyRect());
    }

    pub fn invalidate(self: *Tree, r: Rect) void {
        if (r.isEmpty()) return;
        self.dirty = Rect.coverOpt(self.dirty, r);
        if (self.sink) |s| s.invalidate(s.ctx, r);
    }

    fn invalidateOpt(self: *Tree, r: ?Rect) void {
        if (r) |rr| self.invalidate(rr);
    }

    pub fn takeDirty(self: *Tree) ?Rect {
        const d = self.dirty;
        self.dirty = null;
        return d;
    }

    /// 루트부터 깊이 우선으로 그린다. painter의 clip과 안 겹치는 레이어는 건너뛴다(masks면 그 하위 트리까지). 그린 레이어 수를 돌려준다.
    pub fn draw(self: *Tree, p: *Painter) !u32 {
        const r = self.root orelse return 0;
        var n: u32 = 0;
        try drawLayer(self, p, r, 0, 0, 1, &n);
        return n;
    }
};

fn drawLayer(tree: *Tree, p: *Painter, l: *Layer, ox: f32, oy: f32, acc: f32, n: *u32) !void {
    if (l.hidden) return;
    const a = acc * l.opacity;
    const alpha: u8 = @intFromFloat(@round(std.math.clamp(a, 0, 1) * 255));
    if (alpha == 0) return;
    const s: f32 = @floatFromInt(tree.scale);
    const f = l.frame.offset(ox, oy);
    const phys = f.scaled(s);
    const bounds = phys.outward();
    const clip = p.clipBounds() orelse return;
    const visible = Rect.intersect(bounds, clip) != null;
    if (l.masks) {
        if (!visible) return;
        p.pushClip(bounds);
    }
    defer if (l.masks) p.popClip();
    if (visible) {
        n.* += 1;
        if (l.background) |bg| try p.fillRoundedRect(phys, l.radius * s, bg, alpha);
        if (l.content) |c| {
            const ix: i32 = @intFromFloat(@round(phys.x));
            const iy: i32 = @intFromFloat(@round(phys.y));
            p.translate(ix, iy);
            defer p.translate(-ix, -iy);
            try c.draw(c.ctx, p, .{ phys.w, phys.h }, alpha);
        }
    }
    for (l.children.items) |c| try drawLayer(tree, p, c, f.x, f.y, a, n);
}
