//! WY-M0: Wayland 서버의 순수한 부분(WY design 결정 1 · 9, plan 확정 4 · 8). 시스템 콜도 libwayland도 안 부른다 —
//! `wl_logic_test.zig`가 호스트에서 본다. `layout.zig`와 같은 경계다.
//!
//! 셋이다. (1) 정수 배율과 가운데 자리(`fit`), (2) 그 자리로 옮기는 가장 가까운 픽셀 늘리기(`blit`),
//! (3) xdg toplevel의 configure 순서(`onCommit`).

const std = @import("std");

// ── 배율과 가운데(확정 8) ───────────────────────────────────────────────

/// 클라이언트 버퍼 하나를 화면에 놓는 자리. `k`배로 늘린 뒤 가운데에 둔다. 늘린 것이 화면보다 크면
/// (화면보다 큰 버퍼, k=1) 가운데를 잘라 보인다 — `ox` · `oy`가 늘린 그림 안에서 잘라 낸 왼쪽 위다.
pub const Fit = struct {
    /// 정수 배율. 1 이상.
    k: u32,
    /// 화면 위의 왼쪽 위(픽셀).
    x: u32,
    y: u32,
    /// 화면에 보이는 크기(픽셀). 화면 안이다.
    w: u32,
    h: u32,
    /// 늘린 그림에서 보이기 시작하는 자리(픽셀). 화면보다 작으면 0이다.
    ox: u32,
    oy: u32,
};

/// `k = min(fbW / w, fbH / h)`(1 이상) 배로 늘려 가운데에 둔다(확정 8). 크기가 0이면 null이다.
pub fn fit(fb_w: u32, fb_h: u32, buf_w: u32, buf_h: u32) ?Fit {
    if (fb_w == 0 or fb_h == 0 or buf_w == 0 or buf_h == 0) return null;
    const k = @max(1, @min(fb_w / buf_w, fb_h / buf_h));
    const sw = buf_w * k;
    const sh = buf_h * k;
    return .{
        .k = k,
        .x = if (sw < fb_w) (fb_w - sw) / 2 else 0,
        .y = if (sh < fb_h) (fb_h - sh) / 2 else 0,
        .w = @min(sw, fb_w),
        .h = @min(sh, fb_h),
        .ox = if (sw > fb_w) (sw - fb_w) / 2 else 0,
        .oy = if (sh > fb_h) (sh - fb_h) / 2 else 0,
    };
}

// ── 옮기기 ─────────────────────────────────────────────────────────────

/// `wl_shm`의 두 형식(확정 8 — 이 둘만 받는다). 값은 프로토콜의 enum 값이다.
pub const FORMAT_ARGB8888: u32 = 0;
pub const FORMAT_XRGB8888: u32 = 1;

pub fn formatOk(format: u32) bool {
    return format == FORMAT_ARGB8888 or format == FORMAT_XRGB8888;
}

/// `src`(클라이언트의 버퍼, 행 간격 `src_stride` 바이트)를 `f`의 자리에 가장 가까운 픽셀로 늘려
/// `dst`(프레임버퍼, 행 간격 `dst_pitch` 바이트)에 쓴다.
///
/// 픽셀은 u32 하나를 그대로 옮긴다. 프레임버퍼는 XRGB8888이라 위 8비트는 화면에 안 나간다. ARGB8888은
/// 미리 곱한 알파(premultiplied)라 검정 위에 겹친 값이 곧 RGB 셋이다 — 따로 섞을 것이 없다(둘레가 검정이고
/// 겹친 창이 없으므로).
///
/// `src`는 `buf_h` 행이 다 있어야 하고 `dst`는 `f`의 사각형이 다 들어가야 한다 — 부르는 쪽이 크기를 본다.
pub fn blit(dst: [*]u8, dst_pitch: u32, f: Fit, src: [*]const u8, src_stride: u32) void {
    var y: u32 = 0;
    while (y < f.h) : (y += 1) {
        const sy = (f.oy + y) / f.k;
        const srow: [*]align(1) const u32 = @ptrCast(src + @as(usize, sy) * src_stride);
        const drow: [*]align(1) u32 = @ptrCast(dst + @as(usize, f.y + y) * dst_pitch + @as(usize, f.x) * 4);
        if (f.k == 1) {
            @memcpy(drow[0..f.w], srow[f.ox .. f.ox + f.w]);
            continue;
        }
        var x: u32 = 0;
        while (x < f.w) : (x += 1) drow[x] = srow[(f.ox + x) / f.k];
    }
}

// ── configure의 순서(xdg-shell) ─────────────────────────────────────────

/// toplevel 하나의 단계. 역할이 붙은 뒤 첫 commit에 서버가 configure를 보내고(`configured`), 클라이언트가
/// ack한 뒤 버퍼를 commit하면 보인다(`mapped`).
pub const Phase = enum { fresh, configured, mapped };

/// commit 하나에 서버가 할 일.
pub const Action = enum {
    /// 첫 commit — configure를 보낸다.
    send_configure,
    /// 아직 버퍼가 없다. 아무것도 안 한다.
    wait,
    /// 처음 보인다. 다시 그린다.
    map,
    /// 이미 보이는 창의 commit. 다시 그린다(버퍼가 빠졌으면 검정).
    update,
    /// configure를 ack하기 전에 버퍼를 붙였다 — xdg_surface의 `unconfigured_buffer` 오류다.
    unconfigured_buffer,
};

pub const Step = struct { action: Action, next: Phase };

/// commit 뒤의 상태(`has_buffer` — 그 commit 뒤 surface에 버퍼가 있는가)로 할 일과 다음 단계를 정한다.
pub fn onCommit(phase: Phase, acked: bool, has_buffer: bool) Step {
    return switch (phase) {
        .fresh => if (has_buffer)
            .{ .action = .unconfigured_buffer, .next = .fresh }
        else
            .{ .action = .send_configure, .next = .configured },
        .configured => if (!has_buffer)
            .{ .action = .wait, .next = .configured }
        else if (!acked)
            .{ .action = .unconfigured_buffer, .next = .configured }
        else
            .{ .action = .map, .next = .mapped },
        .mapped => .{ .action = .update, .next = .mapped },
    };
}
