//! 스택 레이아웃(R-CA-4, TK-M1 plan 확정 7) — 세로 · 가로 한 줄, 간격 · 여백 · 정렬, 자식마다 고정/신축. 제약식은 없다.
//!
//! 순수 셈이다: `layout(container)`가 자식들의 `setFrame`을 부르고(더티는 setter가 낸다) 그 밖의 상태는 없다. `container`는 자식들의
//! 부모 좌표(보통 부모의 (0, 0, w, h))다.
//!
//! 주축: 안쪽 길이 − 고정 크기의 합 − 간격 × (n − 1)이 남은 공간이고, 신축 자식(flex > 0)이 비율로 나눈다. 남은 공간이 0 이하면 신축
//! 자식은 0이다(고정은 그대로 — 넘치면 부모의 masks가 자른다). 위치는 누적값을 정수로 반올림해 정한다 — 자식 사이에 소수 경계(AA)가
//! 생기지 않는다. 신축 자식이 남은 공간을 나누면(남은 공간 > 0) 마지막 자식의 끝을 안쪽 끝에 맞춰 누적 오차를 그 자식이 흡수한다.
//! 교차축: `alignment`(`align`은 Zig 예약어) — start · center(내림) · end는 자식의 `cross`(없으면 안쪽 폭)를 쓰고, fill은 늘 안쪽 폭이다.

const std = @import("std");
const RectF = @import("tk_geom").RectF;
const Layer = @import("layer.zig").Layer;

pub const Axis = enum { vertical, horizontal };
pub const Align = enum { start, center, end, fill };

pub const Insets = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,

    pub fn all(v: f32) Insets {
        return .{ .top = v, .right = v, .bottom = v, .left = v };
    }
};

pub const Item = struct {
    layer: *Layer,
    /// 주축의 고정 크기(flex가 0일 때).
    size: f32 = 0,
    /// 0이면 고정, 0보다 크면 남은 공간을 이 비율로.
    flex: f32 = 0,
    /// 교차축 크기(fill이 아닐 때). null이면 안쪽 폭.
    cross: ?f32 = null,
};

pub const Stack = struct {
    axis: Axis = .vertical,
    spacing: f32 = 0,
    padding: Insets = .{},
    alignment: Align = .fill,
    items: []const Item,

    pub fn layout(self: Stack, container: RectF) void {
        const v = self.axis == .vertical;
        const p = self.padding;
        const main0 = if (v) container.y + p.top else container.x + p.left;
        const main_len = (if (v) container.h - p.top - p.bottom else container.w - p.left - p.right);
        const cross0 = if (v) container.x + p.left else container.y + p.top;
        const cross_len = (if (v) container.w - p.left - p.right else container.h - p.top - p.bottom);
        const n = self.items.len;
        if (n == 0) return;

        var fixed: f32 = 0;
        var flex: f32 = 0;
        for (self.items) |it| {
            if (it.flex > 0) flex += it.flex else fixed += it.size;
        }
        const free = main_len - fixed - self.spacing * @as(f32, @floatFromInt(n - 1));
        const share = if (flex > 0 and free > 0) free / flex else 0;

        var pos: f32 = main0;
        for (self.items, 0..) |it, i| {
            const want = if (it.flex > 0) it.flex * share else it.size;
            const start = @round(pos);
            var end = @round(pos + want);
            if (share > 0 and i == n - 1) end = @round(main0 + main_len);
            pos += want + self.spacing;

            const csize = switch (self.alignment) {
                .fill => cross_len,
                else => it.cross orelse cross_len,
            };
            const cstart = switch (self.alignment) {
                .start, .fill => cross0,
                .center => cross0 + @floor((cross_len - csize) / 2),
                .end => cross0 + cross_len - csize,
            };
            const len = @max(0, end - start);
            const f: RectF = if (v)
                .{ .x = cstart, .y = start, .w = csize, .h = len }
            else
                .{ .x = start, .y = cstart, .w = len, .h = csize };
            it.layer.setFrame(f);
        }
    }
};
