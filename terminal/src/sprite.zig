//! 폰트 없이 코드로 그리는 기호(NS-M0, `docs/specs/2026-11-08-tars-nerd-symbols-design.md`).
//!
//! Powerline 넷 — U+E0B0(오른쪽을 향한 채운 삼각형) · E0B1(오른쪽 선 화살표) · E0B2(왼쪽 채운 삼각형) ·
//! E0B3(왼쪽 선 화살표). 셸 프롬프트 테마가 색 띠를 잇는 데 쓴다.
//!
//! 왜 폰트가 아니라 코드인가. unifont에는 이 넷이 없어(gid 0) stb가 `.notdef`의 6x11 상자를 굽는다. Nerd Font의
//! 아웃라인 기호 폰트는 16px에서 잉크의 절반 넘게가 중간값이라 문턱값 렌더링(TR design 결정 4)과 겨룬다. 삼각형은 셀
//! 격자 위에서 식 하나로 정확히 정해지는 모양이라, 그리는 편이 폰트를 싣는 것보다 작고 정확하다. ghostty도 같은
//! 기호를 코드로 그린다(`src/font/sprite/draw/powerline.zig`).
//!
//! `font.Cache.find()`가 캐시를 본 다음, stb보다 먼저 이것을 묻는다(design 결정 2). 나중에 이 코드포인트를 가진
//! fallback 폰트가 들어와도 여기서 그린 것이 이긴다 — 셀을 꽉 채워야 옆 칸의 배경과 이어진다.
//!
//! 시스템 콜도 로그도 없는 순수한 모듈이다. 비트맵은 comptime에 만든 상수라 malloc도 풀 것도 없다(결정 3).

const std = @import("std");

/// 셀 하나의 크기. `main.zig`의 `CELL_W` · `ROW_HEIGHT`와 같아야 한다(거기 comptime 단언, design 위험 2).
pub const W: u32 = 8;
pub const H: u32 = 16;

/// 채운 삼각형의 행 y가 칠하는 폭(design 결정 5). 꼭짓점 (0,0) · (W, H/2) · (0,H)의 삼각형 안에 픽셀의 가운데가
/// 들어가면 칠한다: `x + 0.5 ≤ W - |y + 0.5 - H/2|`. 두 배로 늘려 정수로만 셈한다 — 행 폭은 위에서부터
/// 1 · 2 · … · 8 · 8 · … · 1이고 가운데 두 행이 셀 폭을 꽉 채운다.
fn fill(y: u32) u32 {
    const cy2: i32 = @as(i32, @intCast(2 * y + 1)) - @as(i32, @intCast(H)); // 2(y + 0.5 - H/2)
    const limit2: i32 = 2 * @as(i32, @intCast(W)) - @as(i32, @intCast(@abs(cy2))); // 2(W - |…|)
    // x + 0.5 ≤ limit2 / 2  ⇔  2x + 1 ≤ limit2  ⇔  x ≤ (limit2 - 1) / 2
    return @intCast(@divFloor(limit2 - 1, 2) + 1);
}

const Shape = enum { filled, line };

/// 비트맵 하나를 만든다. 값은 0 아니면 255 — 문턱값(`> 127`)과 겨루지 않는다.
/// 선 화살표는 채운 삼각형의 각 행에서 가장 오른쪽 픽셀 하나다(결정 6) — 행마다 하나라 대각선이 끊기지 않고 두께가 1이다.
/// `mirror`는 좌우 뒤집기다(결정 7): 왼쪽을 향한 둘은 오른쪽 둘과 같은 정의에서 나온다.
fn make(comptime shape: Shape, comptime mirror: bool) [W * H]u8 {
    var bm: [W * H]u8 = @splat(0);
    for (0..H) |y| {
        const f = fill(@intCast(y));
        for (0..W) |x| {
            const sx = if (mirror) W - 1 - x else x;
            const on = switch (shape) {
                .filled => sx < f,
                .line => sx == f - 1,
            };
            if (on) bm[y * W + x] = 255;
        }
    }
    return bm;
}

const e0b0 = make(.filled, false);
const e0b1 = make(.line, false);
const e0b2 = make(.filled, true);
const e0b3 = make(.line, true);

/// 코드로 그리는 기호면 W*H바이트(행 우선)를, 아니면 null을 돌려준다.
pub fn lookup(cp: u32) ?[]const u8 {
    return switch (cp) {
        0xE0B0 => &e0b0,
        0xE0B1 => &e0b1,
        0xE0B2 => &e0b2,
        0xE0B3 => &e0b3,
        else => null,
    };
}
