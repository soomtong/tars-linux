//! 분할 뷰(R-KIT-3, TK-M3 plan 확정 8) — 가로 둘: 앞은 신축, 뒤는 고정 폭, 사이 1 px 구분선(`TK_SEPARATOR`). 끌기 · 접기 · 세로 분할은
//! 없다. 배치는 CA의 스택 하나이고, 배치 뒤 `notify`로 알린다(자식 위젯이 `sync()`를 부르는 자리 — column view · 리스트는 frame이
//! 정해진 뒤 자기 안을 맞춘다).
//!
//! 뷰로서는 아무 키도 받지 않는다 — 자식 뷰(앱이 `view.addChild`로 붙인다)가 받고, 안 받은 키는 이 뷰를 지나 위로 간다.
//! 컨테이너는 masks다: 창이 뒤 폭보다 좁으면 앞은 0이 되고 뒤가 넘친 몫은 잘린다.

const std = @import("std");
const RectF = @import("tk_geom").RectF;
const tokens = @import("tk_tokens");
const ca = @import("tk_ca");
const Layer = ca.Layer;
const Tree = ca.Tree;
const view_mod = @import("view.zig");
const View = view_mod.View;
const VTable = view_mod.VTable;

pub const SEPARATOR_W: f32 = 1;

pub const Notify = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, split: *SplitView) void,
};

pub const SplitView = struct {
    view: View,
    separator: *Layer,
    first: *Layer,
    second: *Layer,
    /// 뒤 칸의 폭(논리 px).
    second_w: f32,
    notify: ?Notify = null,

    const vtable: VTable = .{};

    /// 앞 · 뒤 레이어(앱이 만든 위젯의 컨테이너)를 받아 컨테이너 → 앞 · 구분선 · 뒤로 붙인다. `self`는 사는 동안 옮기지 않는다.
    pub fn init(self: *SplitView, tree: *Tree, name: []const u8, first: *Layer, second: *Layer, second_w: f32) !void {
        const container = try tree.create(.{ .masks = true });
        const sep = try tree.create(.{ .background = tokens.color.separator });
        try container.addChild(first);
        try container.addChild(sep);
        try container.addChild(second);
        self.* = .{
            .view = .{ .layer = container, .vtable = &vtable, .ctx = self, .name = name },
            .separator = sep,
            .first = first,
            .second = second,
            .second_w = second_w,
        };
        container.owner = &self.view;
    }

    pub fn deinit(self: *SplitView, alloc: std.mem.Allocator) void {
        self.view.deinit(alloc);
    }

    /// 컨테이너를 `frame`(부모 좌표)에 놓고 안을 배치한 뒤 알린다.
    pub fn layout(self: *SplitView, frame: RectF) void {
        self.view.layer.setFrame(frame);
        const stack: ca.Stack = .{
            .axis = .horizontal,
            .items = &.{
                .{ .layer = self.first, .flex = 1 },
                .{ .layer = self.separator, .size = SEPARATOR_W },
                .{ .layer = self.second, .size = self.second_w },
            },
        };
        stack.layout(.{ .x = 0, .y = 0, .w = frame.w, .h = frame.h });
        if (self.notify) |n| n.on(n.ctx, self);
    }
};
