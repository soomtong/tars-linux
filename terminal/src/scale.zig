//! HiDPI 배율(HS-M0)의 순수한 반쪽 — 배율 고르기와 사각형 늘리기.
//!
//! `drm.zig`가 이것을 부른다. 따로 둔 이유는 호스트 검사다(`scale_test`) — `drm.zig`는 `c_drm`
//! 번역을 끌어와 호스트에서 안 돈다. 여기는 시스템 콜도 로그도 없고, 픽셀은 바이트 포인터와
//! pitch로만 받는다.

const std = @import("std");

/// `auto`가 지키는 논리 화면의 하한(HS design 결정 3). QEMU 기본(1280×800)과 MacBookAir4,1
/// (1366×768)이 배율 1에 남는 선이다 — 지금 게이트 스물일곱이 도는 화면이 그대로다.
pub const MIN_W: u32 = 1280;
pub const MIN_H: u32 = 800;
/// 배율의 상한. 3840×2400보다 큰 패널도 3이다.
pub const MAX: u32 = 3;

/// 배율을 고른다. `fixed`가 있으면(설정의 `1` · `2` · `3`) 그것이고, 없으면(`auto`)
/// `min(w / MIN_W, h / MIN_H)`을 내림해 1~`MAX`로 자른다. 정수 나눗셈이 곧 내림이다.
///
/// 강제한 배율은 화면이 작아도 그대로 쓴다 — 1280×800에 3을 적으면 논리 426×266이다. 사람이
/// 적은 값을 조용히 바꾸지 않는다는 것은 PS의 가속(`Accel.parse`)과 같은 규칙이고, 로그 한 줄
/// (`kms: scale`)이 무엇이 쓰였는지 말한다.
pub fn pick(fixed: ?u32, w: u32, h: u32) u32 {
    if (fixed) |s| return std.math.clamp(s, 1, MAX);
    return std.math.clamp(@min(w / MIN_W, h / MIN_H), 1, MAX);
}

/// 논리 좌표의 사각형 하나. `x2` · `y2`는 끝 다음이다(`drm.Clip`과 같은 규칙).
pub const Rect = struct { x1: u32, y1: u32, x2: u32, y2: u32 };

/// 논리 버퍼(`src`)의 사각형 `r`을 물리 버퍼(`dst`)의 `s`배 사각형으로 옮긴다. 논리 픽셀
/// 하나가 물리 `s × s` 블록 하나가 된다(HS design 결정 1).
///
/// 논리 행 하나마다 물리 첫 행을 픽셀째 짓고(`@memset` s칸), 나머지 `s - 1`행은 그 행을
/// 통째로 복사한다. 픽셀마다 `s × s`번 쓰는 것보다 쓰기가 넓게 묶인다 — `drm.fillRect`가
/// 행마다 `@memset` 한 번인 것과 같은 생각이다.
///
/// 범위 검사가 없다. 부르는 자리(`drm.Framebuffer.present`)가 논리 fb 안으로 자른 clip만
/// 넘기고(`ClipList.push`), 물리 버퍼는 논리 × `s`보다 작지 않다(`drm.open`이 논리 크기를
/// 내림으로 정한다).
pub fn upscale(src: [*]const u8, src_pitch: usize, dst: [*]u8, dst_pitch: usize, r: Rect, s: u32) void {
    if (r.x2 <= r.x1 or r.y2 <= r.y1) return;
    const n: usize = r.x2 - r.x1;
    const off: usize = @as(usize, r.x1) * s * 4;
    const bytes: usize = n * s * 4;
    var y: usize = r.y1;
    while (y < r.y2) : (y += 1) {
        const line: [*]const u32 = @ptrCast(@alignCast(src + y * src_pitch));
        const top = y * s * dst_pitch;
        const out: [*]u32 = @ptrCast(@alignCast(dst + top));
        var x: usize = r.x1;
        while (x < r.x2) : (x += 1) @memset(out[x * s ..][0..s], line[x]);
        var k: usize = 1;
        while (k < s) : (k += 1) {
            @memcpy((dst + top + k * dst_pitch + off)[0..bytes], (dst + top + off)[0..bytes]);
        }
    }
}
