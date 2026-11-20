//! 사각형 둘(TK-M1). 어느 층에도 속하지 않는 순수 값이라 창 · CG · CA가 함께 쓴다(모듈 `tk_geom` — R-ARCH-1의 층 경계 밖).
//!
//! `Rect`는 정수 픽셀(버퍼 좌표, 물리)이고 `RectF`는 소수(레이어의 논리 좌표, 애니메이션이 소수 위치를 낳는다). 소수 → 정수는 늘
//! 바깥쪽으로 반올림한다 — 안티에일리어스 가장자리 한 칸을 더티에서 놓치지 않으려는 것이다.

const std = @import("std");

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn isEmpty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }

    pub fn eql(a: Rect, b: Rect) bool {
        return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
    }

    /// 겹치는 부분. 없으면 null.
    pub fn intersect(a: Rect, b: Rect) ?Rect {
        const x0 = @max(a.x, b.x);
        const y0 = @max(a.y, b.y);
        const x1 = @min(a.x + a.w, b.x + b.w);
        const y1 = @min(a.y + a.h, b.y + b.h);
        if (x1 <= x0 or y1 <= y0) return null;
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    /// 둘을 덮는 사각형 하나(합집합의 테두리 — damage가 사각형 하나라서, design 결정 9).
    pub fn cover(a: Rect, b: Rect) Rect {
        if (a.isEmpty()) return b;
        if (b.isEmpty()) return a;
        const x0 = @min(a.x, b.x);
        const y0 = @min(a.y, b.y);
        const x1 = @max(a.x + a.w, b.x + b.w);
        const y1 = @max(a.y + a.h, b.y + b.h);
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    /// null을 "없음"으로 읽는 `cover`.
    pub fn coverOpt(a: ?Rect, b: ?Rect) ?Rect {
        const aa = a orelse return b;
        const bb = b orelse return a;
        return cover(aa, bb);
    }

    /// `b`가 `a` 안에 다 드는가.
    pub fn contains(a: Rect, b: Rect) bool {
        return b.x >= a.x and b.y >= a.y and b.x + b.w <= a.x + a.w and b.y + b.h <= a.y + a.h;
    }

    pub fn offset(self: Rect, dx: i32, dy: i32) Rect {
        return .{ .x = self.x + dx, .y = self.y + dy, .w = self.w, .h = self.h };
    }
};

pub const RectF = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn offset(self: RectF, dx: f32, dy: f32) RectF {
        return .{ .x = self.x + dx, .y = self.y + dy, .w = self.w, .h = self.h };
    }

    pub fn scaled(self: RectF, s: f32) RectF {
        return .{ .x = self.x * s, .y = self.y * s, .w = self.w * s, .h = self.h * s };
    }

    /// 덮는 정수 사각형(바깥쪽 반올림).
    pub fn outward(self: RectF) Rect {
        const x0: i32 = @intFromFloat(@floor(self.x));
        const y0: i32 = @intFromFloat(@floor(self.y));
        const x1: i32 = @intFromFloat(@ceil(self.x + self.w));
        const y1: i32 = @intFromFloat(@ceil(self.y + self.h));
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    /// 네 변이 다 정수인가(빠른 길 — 직접 채우기 — 를 쓸 수 있는가).
    pub fn isIntegral(self: RectF) bool {
        return self.x == @floor(self.x) and self.y == @floor(self.y) and self.w == @floor(self.w) and self.h == @floor(self.h);
    }
};
