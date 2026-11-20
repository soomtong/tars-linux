//! 애니메이션(R-CA-3, TK-M1 plan 확정 6) — 속성 보간. 넷(위치 · 크기 = `frame`, 불투명도, 배경 색)을 같은 틀로 다룬다.
//!
//! 시계는 바깥에서 받는다: 트리의 `tick(now_ns)`이 시각을 인자로 받고(창 층은 자기 monotonic을, 호스트 검사는 지어낸 시각을 넣는다),
//! 첫 tick이 시작 시각이 된다. tick마다 값을 셈해 레이어의 setter로 넣는다 — 더티는 setter가 낸다. 값이 그대로여도 그 레이어를
//! 더티로 둔다: 애니메이션이 도는 동안은 tick마다 그림이 하나 생겨 다음 frame 콜백이 오고, 그래야 다음 tick이 온다(창 층은 그릴 수
//! 있을 때만 tick을 부른다 — window.zig). 목록이 비면 tick이 아무것도 안 하므로 frame도 commit도 없다(idle commit 0).

const std = @import("std");
const geom = @import("tk_geom");
const RectF = geom.RectF;
const Layer = @import("layer.zig").Layer;

pub const Easing = enum {
    /// 1 − (1 − t)³ — UI의 기본 감속.
    ease_out_cubic,
    linear,

    pub fn apply(self: Easing, t: f32) f32 {
        const c = std.math.clamp(t, 0, 1);
        return switch (self) {
            .linear => c,
            .ease_out_cubic => 1 - (1 - c) * (1 - c) * (1 - c),
        };
    }
};

pub const Prop = enum { frame, opacity, background };

pub const Value = union(Prop) {
    frame: RectF,
    opacity: f32,
    background: u32,

    fn of(l: *const Layer, p: Prop) Value {
        return switch (p) {
            .frame => .{ .frame = l.frame },
            .opacity => .{ .opacity = l.opacity },
            // 배경이 없던 레이어는 처음부터 끝 색이다(없음 → 색의 보간은 그룹 불투명도의 일이라 하지 않는다).
            .background => .{ .background = l.background orelse 0 },
        };
    }
};

pub const Anim = struct {
    layer: *Layer,
    from: Value,
    to: Value,
    dur_ns: u64,
    easing: Easing,
    start_ns: ?u64 = null,
    /// 값을 넣은 tick 수 — tick마다 그림이 하나이므로 이 애니메이션이 그린 프레임 수다.
    frames: u32 = 0,
};

/// 시작 · 끝 알림(창 층의 `tk> anim …` 줄 — CA는 창을 모르므로 바깥이 받아 찍는다).
pub const Event = union(enum) {
    start: struct { prop: Prop, dur_ms: u64 },
    end: struct { prop: Prop, frames: u32, ms: u64 },
};

pub const Hook = struct {
    ctx: *anyopaque,
    on: *const fn (ctx: *anyopaque, ev: Event) void,
};

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn lerpChannel(a: u32, b: u32, t: f32) u32 {
    const v = lerp(@floatFromInt(a), @floatFromInt(b), t);
    return @intFromFloat(@round(std.math.clamp(v, 0, 255)));
}

/// `from`에서 `to`로 `t`(0..1, 이징을 지난 값)만큼.
pub fn interpolate(from: Value, to: Value, t: f32) Value {
    return switch (to) {
        .frame => |b| blk: {
            const a = from.frame;
            break :blk .{ .frame = .{ .x = lerp(a.x, b.x, t), .y = lerp(a.y, b.y, t), .w = lerp(a.w, b.w, t), .h = lerp(a.h, b.h, t) } };
        },
        .opacity => |b| .{ .opacity = lerp(from.opacity, b, t) },
        .background => |b| blk: {
            const a = from.background;
            const r = lerpChannel((a >> 16) & 0xFF, (b >> 16) & 0xFF, t);
            const g = lerpChannel((a >> 8) & 0xFF, (b >> 8) & 0xFF, t);
            const bb = lerpChannel(a & 0xFF, b & 0xFF, t);
            break :blk .{ .background = (r << 16) | (g << 8) | bb };
        },
    };
}

pub fn set(l: *Layer, v: Value) void {
    switch (v) {
        .frame => |f| l.setFrame(f),
        .opacity => |o| l.setOpacity(o),
        .background => |c| l.setBackground(c),
    }
}

pub fn current(l: *const Layer, p: Prop) Value {
    return Value.of(l, p);
}
