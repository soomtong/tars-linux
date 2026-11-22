//! WY-M0: Wayland 서버의 순수한 부분(WY design 결정 1 · 9, plan 확정 4 · 8). 시스템 콜도 libwayland도 안 부른다 —
//! `wl_logic_test.zig`가 호스트에서 본다. `layout.zig`와 같은 경계다.
//!
//! 여섯이다. (1) 정수 배율과 가운데 자리(`fit`), (2) 그 자리로 옮기는 가장 가까운 픽셀 늘리기(`blit`),
//! (3) xdg toplevel의 configure 순서(`onCommit`), (4) `wl_keyboard.modifiers`의 비트(`modifierMask`, 단계 C),
//! (5) 클라이언트에 누름을 보낸 키의 목록(`Held`, 단계 C), (6) `Cmd+Q`의 2초 기한(`Deadline`, 단계 C).
//! WY-M2가 다섯을 더했다 — pane 사각형 안의 자리(`fitIn`), configure의 states(`toplevelStates`), 그리고 포인터 셋
//! (단계 C): 화면 좌표 → surface 좌표(`surfacePoint`), enter · leave와 버튼 grab(`PointerFocus`), 휠의 axis 값(`axisFor`).
//! WY-M3(design 결정 28 · 29)이 버퍼 배율을 더했다 — surface 크기(`surfaceSize`), 버퍼 배율의 규칙(`scaleOk`), `blit`의 솎기(`bs`).
//! 단계 B(결정 30)는 물리 합성의 셈 — 잘라 옮기기(`blitClip`), 교집합(`intersect`), × 배율(`scaleFit` · `scaleArea`).
//! WY-M4(design 결정 33 · 34 · 36)가 클립보드의 셋을 더했다 — 받을 mime 고르기(`pickMime`), `set_selection`을 받아들이는
//! 조건(`SelectionGate`), 받는 한도(`SELECTION_MAX_BYTES` · `SELECTION_TIMEOUT_MS`).
//! WY-M5(design 결정 43)가 `zwp_text_input_v3`의 이중 버퍼 셈(`TextInput`)을 더했다.

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

/// 사각형 하나(픽셀). strip의 pane이 프레임버퍼에서 차지하는 자리다(WY-M2).
pub const Area = struct { x: u32, y: u32, w: u32, h: u32 };

/// `fit`을 화면 전체 대신 사각형 `a` 안에서 한다(WY-M2 확정 5, design 결정 22). 돌려준 `x` · `y`는 프레임버퍼
/// 좌표다 — `blit`이 그대로 쓴다. configure를 따른 클라이언트는 1배로 사각형을 채우고, 따르지 않는 클라이언트(RESIZABLE이
/// 아닌 SDL 창)는 정수 배로 늘려 가운데에 서거나, 사각형보다 크면 가운데가 잘려 보인다.
pub fn fitIn(a: Area, buf_w: u32, buf_h: u32) ?Fit {
    var f = fit(a.w, a.h, buf_w, buf_h) orelse return null;
    f.x += a.x;
    f.y += a.y;
    return f;
}

// ── 옮기기 ─────────────────────────────────────────────────────────────

/// `wl_shm`의 두 형식(확정 8 — 이 둘만 받는다). 값은 프로토콜의 enum 값이다.
pub const FORMAT_ARGB8888: u32 = 0;
pub const FORMAT_XRGB8888: u32 = 1;

pub fn formatOk(format: u32) bool {
    return format == FORMAT_ARGB8888 or format == FORMAT_XRGB8888;
}

// ── 버퍼 배율(WY-M3, design 결정 28 · 29) ──────────────────────────────

/// surface 크기(논리 — configure · `fit` · 포인터 좌표의 단위)는 버퍼 크기 ÷ buffer_scale이다(wayland.xml의 attach).
pub const Size = struct { w: u32, h: u32 };

pub fn surfaceSize(buf_w: u32, buf_h: u32, bs: u32) Size {
    return .{ .w = buf_w / bs, .h = buf_h / bs };
}

/// buffer_scale이 받을 수 있는 값인가(`invalid_scale` — 0 이하는 오류).
pub fn scaleOk(bs: i32) bool {
    return bs > 0;
}

/// 버퍼 크기가 buffer_scale의 정수 배인가(`invalid_size` — commit 때 본다).
pub fn sizeOk(buf_w: u32, buf_h: u32, bs: u32) bool {
    return buf_w % bs == 0 and buf_h % bs == 0;
}

/// `src`(클라이언트의 버퍼, 행 간격 `src_stride` 바이트, buffer_scale `bs`)를 `f`의 자리에 가장 가까운 픽셀로 늘려
/// `dst`(프레임버퍼, 행 간격 `dst_pitch` 바이트)에 쓴다. `f`는 surface 크기로 셈한 것이다 — 화면 픽셀 `f.k`개가 surface
/// 단위 하나이고 버퍼 픽셀 `bs`개가 surface 단위 하나라, 화면 픽셀 `p`(늘린 그림 안)는 버퍼 픽셀 `p · bs / k`다(WY-M3 확정 6).
/// `k == bs`이면 1:1(행 memcpy) — bs 1 · k 1이 그 경우이고 WY-M2까지의 길과 같다. `bs > k`이면 솎는다(배율 2 화면의
/// 논리 그림자에 bs 2 버퍼를 놓을 때 — 물리 합성은 단계 B).
///
/// 픽셀은 u32 하나를 그대로 옮긴다. 프레임버퍼는 XRGB8888이라 위 8비트는 화면에 안 나간다. ARGB8888은
/// 미리 곱한 알파(premultiplied)라 검정 위에 겹친 값이 곧 RGB 셋이다 — 따로 섞을 것이 없다(둘레가 검정이고
/// 겹친 창이 없으므로).
///
/// `src`는 `buf_h` 행이 다 있어야 하고 `dst`는 `f`의 사각형이 다 들어가야 한다 — 부르는 쪽이 크기를 본다.
pub fn blit(dst: [*]u8, dst_pitch: u32, f: Fit, src: [*]const u8, src_stride: u32, bs: u32) void {
    blitClip(dst, dst_pitch, f, src, src_stride, bs, .{ .x = f.x, .y = f.y, .w = f.w, .h = f.h });
}

/// `blit`을 사각형 `clip`과 겹친 자리만 한다(WY-M3, design 결정 30). 물리 합성이 프레임의 clip마다 부른다 — 화살표만
/// 옮기는 바퀴의 clip은 화살표 상자뿐이라 창 전체를 다시 옮기지 않는다. 겹치지 않으면 아무것도 안 한다.
pub fn blitClip(dst: [*]u8, dst_pitch: u32, f: Fit, src: [*]const u8, src_stride: u32, bs: u32, clip: Area) void {
    const r = intersect(.{ .x = f.x, .y = f.y, .w = f.w, .h = f.h }, clip) orelse return;
    const lx = r.x - f.x;
    var y: u32 = r.y;
    while (y < r.y + r.h) : (y += 1) {
        const sy = (f.oy + (y - f.y)) * bs / f.k;
        const srow: [*]align(1) const u32 = @ptrCast(src + @as(usize, sy) * src_stride);
        const drow: [*]align(1) u32 = @ptrCast(dst + @as(usize, y) * dst_pitch + @as(usize, r.x) * 4);
        if (f.k == bs) {
            const from = f.ox + lx;
            @memcpy(drow[0..r.w], srow[from .. from + r.w]);
            continue;
        }
        var x: u32 = 0;
        while (x < r.w) : (x += 1) drow[x] = srow[(f.ox + lx + x) * bs / f.k];
    }
}

/// 두 사각형이 겹친 자리. 겹치지 않으면 null.
pub fn intersect(a: Area, b: Area) ?Area {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

// ── damage(WY-M6 단계 B, design 결정 47, R-WY-10) ─────────────────────────

/// commit 전에 쌓는 damage — 버퍼 좌표, 반열린 [x0, x1) × [y0, y1). 클라이언트가 준 값 그대로라 음수 · 버퍼 밖 · `INT32_MAX`가 들
/// 수 있어 i64다(`damage`는 × buffer_scale을 하므로 i32를 넘을 수 있다). 버퍼로 자르는 것은 commit 때다(`boxClamp`) — attach가 같은
/// commit 안에서 damage보다 늦게 올 수 있어 그 전에는 버퍼 크기를 모른다.
pub const Box = struct { x0: i64, y0: i64, x1: i64, y1: i64 };

/// `damage`(surface 좌표, `mul` = buffer_scale)나 `damage_buffer`(버퍼 좌표, `mul` = 1)의 사각형 하나. 폭이나 높이가 0 이하면 null —
/// 비어 있는 damage다(xml은 오류로 정하지 않는다).
pub fn boxOf(x: i32, y: i32, w: i32, h: i32, mul: u32) ?Box {
    if (w <= 0 or h <= 0) return null;
    const m: i64 = mul;
    return .{ .x0 = @as(i64, x) * m, .y0 = @as(i64, y) * m, .x1 = (@as(i64, x) + w) * m, .y1 = (@as(i64, y) + h) * m };
}

/// 두 상자를 덮는 가장 작은 상자(합집합 사각형 하나 — 결정 47, 목록은 숫자가 바랄 때).
pub fn boxUnion(a: ?Box, b: Box) Box {
    const p = a orelse return b;
    return .{ .x0 = @min(p.x0, b.x0), .y0 = @min(p.y0, b.y0), .x1 = @max(p.x1, b.x1), .y1 = @max(p.y1, b.y1) };
}

/// 상자를 버퍼 `bw × bh` 안으로 자른다. 겹치지 않으면 null.
pub fn boxClamp(b: Box, bw: u32, bh: u32) ?Area {
    const x0 = @max(b.x0, 0);
    const y0 = @max(b.y0, 0);
    const x1 = @min(b.x1, @as(i64, bw));
    const y1 = @min(b.y1, @as(i64, bh));
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = @intCast(x0), .y = @intCast(y0), .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
}

/// 두 사각형을 덮는 가장 작은 사각형. commit이 둘 이상 한 프레임에 모이면 그 damage를 이것으로 잇는다.
pub fn areaUnion(a: ?Area, b: Area) Area {
    const p = a orelse return b;
    const x0 = @min(p.x, b.x);
    const y0 = @min(p.y, b.y);
    const x1 = @max(p.x + p.w, b.x + b.w);
    const y1 = @max(p.y + p.h, b.y + b.h);
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

/// 버퍼 좌표의 damage `r`가 화면(프레임버퍼)에서 차지하는 자리 — 창이 놓인 `f`(surface 크기로 셈한 것)와 buffer_scale `bs`로.
/// `blitClip`은 늘린 그림의 픽셀 `p`를 버퍼 픽셀 `p · bs / k`에서 읽으므로, 버퍼 [x0, x1)을 읽는 화면 픽셀은 [⌊x0 · k / bs⌋,
/// ⌈x1 · k / bs⌉)에 든다(바깥으로 반올림 — 덜 옮기는 일이 없다). 거기서 `ox` · `oy`(잘린 창)를 빼고 `f`의 사각형으로 자른다.
/// 보이는 자리 밖이면 null.
pub fn damageScreen(f: Fit, bs: u32, r: Area) ?Area {
    const k: u64 = f.k;
    const b: u64 = bs;
    const px0 = @as(u64, r.x) * k / b;
    const py0 = @as(u64, r.y) * k / b;
    const px1 = (@as(u64, r.x + r.w) * k + b - 1) / b;
    const py1 = (@as(u64, r.y + r.h) * k + b - 1) / b;
    // 늘린 그림의 보이는 창은 [ox, ox + w) × [oy, oy + h)다.
    const vx0 = @max(px0, f.ox);
    const vy0 = @max(py0, f.oy);
    const vx1 = @min(px1, @as(u64, f.ox) + f.w);
    const vy1 = @min(py1, @as(u64, f.oy) + f.h);
    if (vx1 <= vx0 or vy1 <= vy0) return null;
    return .{
        .x = f.x + @as(u32, @intCast(vx0 - f.ox)),
        .y = f.y + @as(u32, @intCast(vy0 - f.oy)),
        .w = @intCast(vx1 - vx0),
        .h = @intCast(vy1 - vy0),
    };
}

/// 논리 사각형의 물리 자리(× `s`).
pub fn scaleArea(a: Area, s: u32) Area {
    return .{ .x = a.x * s, .y = a.y * s, .w = a.w * s, .h = a.h * s };
}

/// 논리 프레임버퍼 위의 자리 `f`를 물리 버퍼의 자리로(× `s`, design 결정 30). 물리 픽셀 `k · s`개가 surface 단위 하나다 —
/// `blit(…, bs)`에 이것을 넘기면 `k · s == bs`일 때 1:1(행 memcpy)이다(configure를 따른 column은 k = 1이라 bs == 배율).
pub fn scaleFit(f: Fit, s: u32) Fit {
    return .{ .k = f.k * s, .x = f.x * s, .y = f.y * s, .w = f.w * s, .h = f.h * s, .ox = f.ox * s, .oy = f.oy * s };
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

// ── configure의 states(WY-M2 확정 4, design 결정 21 · 22) ────────────────

/// 창이 놓인 자리. 자기 workspace(첫 commit 전에 `set_fullscreen` — 둠)이거나 strip의 column이다.
pub const Place = enum { workspace, column };

/// `xdg_toplevel.state`의 값(xdg-shell.xml). `tiled_*`는 toplevel 판 2부터다.
pub const STATE_FULLSCREEN: u32 = 2;
pub const STATE_ACTIVATED: u32 = 4;
pub const STATE_TILED_LEFT: u32 = 5;
pub const STATE_TILED_RIGHT: u32 = 6;
pub const STATE_TILED_TOP: u32 = 7;
pub const STATE_TILED_BOTTOM: u32 = 8;
pub const TILED_SINCE: u32 = 2;

/// configure에 실을 states. 자기 workspace는 fullscreen과 activated(WY-M0 그대로 — 늘 앞이다). column은 activated(키보드
/// 포커스일 때)와 네 변의 tiled(판 2+)다 — tiled가 있어야 SDL3가 창을 떠 있는 것(floating)으로 보지 않고 크기를 따른다
/// (조사 1절, `SDL_waylandwindow.c:775-801`). 돌려준 조각은 `out` 안이다.
pub fn toplevelStates(place: Place, activated: bool, version: u32, out: *[6]u32) []u32 {
    var n: usize = 0;
    switch (place) {
        .workspace => {
            out[0] = STATE_FULLSCREEN;
            out[1] = STATE_ACTIVATED;
            n = 2;
        },
        .column => {
            if (activated) {
                out[n] = STATE_ACTIVATED;
                n += 1;
            }
            if (version >= TILED_SINCE) {
                for ([_]u32{ STATE_TILED_LEFT, STATE_TILED_RIGHT, STATE_TILED_TOP, STATE_TILED_BOTTOM }) |st| {
                    out[n] = st;
                    n += 1;
                }
            }
        },
    }
    return out[0..n];
}

// ── 포인터(WY-M2 단계 C, plan 확정 8, design 결정 24) ─────────────────────

/// evdev의 버튼 코드(linux/input-event-codes.h). `wl_pointer.button`은 이 값 그대로다.
pub const BTN_LEFT: u32 = 0x110;
pub const BTN_RIGHT: u32 = 0x111;
pub const BTN_MIDDLE: u32 = 0x112;

/// surface 좌표(`wl_fixed` — 24.8 고정소수, 날 i32).
pub const Point = struct { x: i32, y: i32 };

/// 화면(프레임버퍼) 좌표 `x` · `y`를 창이 놓인 자리 `f`(마지막으로 옮긴 `fit`)의 surface 좌표로 거꾸로 옮긴다. 버퍼 픽셀
/// 하나가 화면 `k × k`이고, 잘려 보이면(`ox` · `oy`) 그만큼 더한다. 창 밖이면 음수나 크기 밖이다 — 버튼을 쥔 채 끄는
/// 동안(grab)은 그 값을 그대로 보낸다(xdg의 implicit grab).
pub fn surfacePoint(f: Fit, x: u32, y: u32) Point {
    const k: i64 = f.k;
    const sx = (@as(i64, x) - f.x + f.ox) * 256;
    const sy = (@as(i64, y) - f.y + f.oy) * 256;
    return .{ .x = @intCast(@divFloor(sx, k)), .y = @intCast(@divFloor(sy, k)) };
}

/// 화면 좌표가 창이 보이는 사각형 안인가(둘레의 검정은 창이 아니다).
pub fn inside(f: Fit, x: u32, y: u32) bool {
    return x >= f.x and x < f.x + f.w and y >= f.y and y < f.y + f.h;
}

/// 포인터 포커스(어느 창이 enter를 받았나)와 버튼 grab. 버튼을 쥔 동안은 포인터가 창 밖으로 나가도 그 창이 움직임과
/// 뗌을 받고, leave는 마지막 뗌 뒤로 미룬다(wl_pointer의 implicit grab — weston · wlroots와 같다).
pub const PointerFocus = struct {
    /// enter를 받은 창. null이면 포인터가 어느 창 위에도 없다.
    focus: ?u32 = null,
    /// 그 창에 누름을 보낸 버튼 수.
    held: u8 = 0,

    /// 한 움직임에 서버가 보낼 것. `leave`가 `enter`보다 먼저 간다.
    pub const Move = struct { leave: ?u32 = null, enter: ?u32 = null, motion: ?u32 = null };

    /// 포인터가 움직였고 지금 아래 창이 `under`다.
    pub fn move(self: *PointerFocus, under: ?u32) Move {
        // grab — 아래가 바뀌어도 쥔 창이 움직임을 받는다.
        if (self.held > 0) return .{ .motion = self.focus };
        if (under == self.focus) return .{ .motion = under };
        const m: Move = .{ .leave = self.focus, .enter = under };
        self.focus = under;
        return m;
    }

    /// 버튼을 눌렀다. 보낼 창(포인터 아래 창이 없으면 null — 셸이나 여백의 누름이다).
    pub fn press(self: *PointerFocus) ?u32 {
        const id = self.focus orelse return null;
        self.held += 1;
        return id;
    }

    /// 버튼을 뗐다. 누름을 보낸 버튼이면 그 창. 마지막 뗌 뒤 부르는 쪽이 `move`를 다시 불러 미룬 leave를 낸다.
    pub fn release(self: *PointerFocus) ?u32 {
        if (self.held == 0) return null;
        self.held -= 1;
        return self.focus;
    }

    /// 창이 사라졌다. 그 창이 포커스였으면 grab도 끝난다(보낼 곳이 없다).
    pub fn drop(self: *PointerFocus, id: u32) void {
        if (self.focus != id) return;
        self.focus = null;
        self.held = 0;
    }
};

/// 휠 눈금 `notches`(양수가 앞으로 민 것 — 위로)의 `wl_pointer.axis`(세로). 값은 눈금마다 10(weston · libinput의 관례),
/// 아래로가 양수라 부호가 뒤집힌다. `discrete`는 판 5~7의 `axis_discrete`다.
pub const Axis = struct { value: i32, discrete: i32 };

pub fn axisFor(notches: i32) Axis {
    return .{ .value = -notches * 10 * 256, .discrete = -notches };
}

// ── 수정키 비트(design 결정 6, 확인 3) ──────────────────────────────────

/// `wl_keyboard.modifiers`에 실을 수정키. 좌우를 합친 것이고 `caps`는 잠금이다.
pub const Mods = struct {
    shift: bool = false,
    caps: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
};

/// 키맵(us · evdev · pc105)의 수정키 비트 — Shift 0x1 · Lock 0x2 · Control 0x4 · Mod1(Alt) 0x8 · Mod4(Super = Cmd)
/// 0x40(확인 3). NumLock(Mod2 0x10)은 안 쓴다. 대문자 잠금은 누른 것(depressed)이 아니라 잠긴 것(locked)이다 —
/// 클라이언트의 xkb가 그 둘을 다르게 센다(잠금은 떼도 남는다).
pub const MOD_SHIFT: u32 = 0x1;
pub const MOD_LOCK: u32 = 0x2;
pub const MOD_CTRL: u32 = 0x4;
pub const MOD_ALT: u32 = 0x8;
pub const MOD_SUPER: u32 = 0x40;

pub const Mask = struct { depressed: u32, locked: u32 };

pub fn modifierMask(m: Mods) Mask {
    var d: u32 = 0;
    if (m.shift) d |= MOD_SHIFT;
    if (m.ctrl) d |= MOD_CTRL;
    if (m.alt) d |= MOD_ALT;
    if (m.super) d |= MOD_SUPER;
    return .{ .depressed = d, .locked = if (m.caps) MOD_LOCK else 0 };
}

/// 호환 모드(WY-M6, design 결정 45 · 요구사항 결정 3)의 마스크. 눌린 것(depressed)에 Super(0x40)가 있으면 지우고
/// Ctrl(0x4)을 켠다 — Super를 모르는 클라이언트가 `Cmd+V`를 `Ctrl+V`로 받는다. 표의 chord는 compositor가 이미 먹었으므로
/// 이것이 "표에 없는 Cmd 조합 전부"다. Cmd와 Ctrl을 함께 쥐면 Ctrl 하나다(구별을 잃는 것이 호환 모드의 뜻). 잠금은 그대로.
pub fn compatMask(m: Mask) Mask {
    if (m.depressed & MOD_SUPER == 0) return m;
    return .{ .depressed = (m.depressed & ~MOD_SUPER) | MOD_CTRL, .locked = m.locked };
}

// ── 보낸 누름(R-KEY-2 · R-KEY-7) ────────────────────────────────────────

/// 포커스 창에 누름을 보낸 키. 뗌은 누름을 보낸 키만 보낸다 — compositor가 먹은 chord의 뗌(R-KEY-2)과 포커스가
/// 들어오기 전에 누른 키의 뗌(`enter`는 빈 목록이다, R-KEY-7)이 같은 길로 걸러진다. 포커스가 바뀌면 비운다.
/// 크기는 evdev의 `KEY_MAX`(0x2ff) + 1이다.
pub const Held = struct {
    bits: std.StaticBitSet(KEY_LIMIT) = .empty,

    pub const KEY_LIMIT = 0x300;

    /// 누름이다. 보낼 것이면 true(이미 보낸 누름의 되풀이도 보낸다 — 커널은 반복을 2로 주므로 1이 겹치지 않는다).
    pub fn press(self: *Held, code: u16) bool {
        if (code >= KEY_LIMIT) return false;
        self.bits.set(code);
        return true;
    }

    /// 뗌이다. 누름을 보낸 키면 true(그리고 목록에서 뺀다).
    pub fn release(self: *Held, code: u16) bool {
        if (code >= KEY_LIMIT or !self.bits.isSet(code)) return false;
        self.bits.unset(code);
        return true;
    }

    pub fn clear(self: *Held) void {
        self.bits = .empty;
    }
};

// ── Cmd+Q의 기한(design 결정 12, plan 확정 11) ───────────────────────────

/// close + ping 뒤 2초. 그 안에 pong도 끝도 없으면 SIGKILL이다.
pub const KILL_AFTER_MS: i64 = 2000;

/// 창 하나의 기한. `poll`의 시간 제한으로 건다 — 화면 양보의 SIGKILL 기한(`yield.Machine.timeout`)과 같은 모양이다.
pub const Deadline = struct {
    /// 이 시각(루프의 밀리초 시계)이 지나면 죽인다. null이면 기한이 없다.
    at: ?i64 = null,
    /// 기다리는 ping의 serial. 이 serial의 pong만 기한을 버린다.
    serial: u32 = 0,

    /// close + ping을 보냈다. 이미 걸려 있으면 그대로 둔다 — `Cmd+Q`를 거듭 눌러도 기한이 밀리지 않는다.
    pub fn arm(self: *Deadline, now_ms: i64, serial: u32) bool {
        if (self.at != null) return false;
        self.at = now_ms + KILL_AFTER_MS;
        self.serial = serial;
        return true;
    }

    /// pong이 왔다. 기다리던 serial이면 기한을 버린다.
    pub fn pong(self: *Deadline, serial: u32) bool {
        if (self.at == null or serial != self.serial) return false;
        self.at = null;
        return true;
    }

    /// `poll`에 넘길 밀리초. 기한이 없으면 -1(무한).
    pub fn timeout(self: Deadline, now_ms: i64) i32 {
        const at = self.at orelse return -1;
        return @intCast(@max(0, @min(at - now_ms, std.math.maxInt(i32))));
    }

    /// 기한이 지났으면 true를 한 번 돌려주고 기한을 버린다.
    pub fn expired(self: *Deadline, now_ms: i64) bool {
        const at = self.at orelse return false;
        if (now_ms < at) return false;
        self.at = null;
        return true;
    }
};

// ── 클립보드(WY-M4, design 결정 33 · 34 · 36) ──────────────────────────────

/// 서버가 내는 텍스트 mime(design 결정 34). 어느 것을 청해도 같은 바이트다. `STRING`은 X11에서 Latin-1이라는 뜻이라 안 낸다.
/// 내는 것은 단계 B(offer)이고, 이 순서가 `offer` 이벤트의 순서다.
pub const OFFER_MIMES = [_][:0]const u8{ "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT" };

/// 클라이언트 source에서 받을 때의 우선순위(design 결정 34). `UTF8_STRING`이 둘째인 것은 그 이름이 인코딩을 못박기
/// 때문이다 — 맨 `text/plain`은 인코딩을 말하지 않는다.
pub const PICK_ORDER = [_][:0]const u8{ "text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT" };

/// source가 offer한 mime 중 받을 것 하나. 우선순위가 높은 것부터 보고, 하나도 없으면(이미지만 있는 source 등) null이다.
/// 돌려주는 것은 `PICK_ORDER`의 상수다 — source의 문자열은 source와 함께 사라지므로 그것을 들고 있지 않는다.
pub fn pickMime(offered: []const []const u8) ?[:0]const u8 {
    for (PICK_ORDER) |want| {
        for (offered) |m| if (std.mem.eql(u8, m, want)) return want;
    }
    return null;
}

/// 받는 한도(design 결정 33). 넘으면 통째로 버리고 클립보드는 그대로 둔다. 1 MiB는 PTY에 bracketed paste로 넣기에
/// 이미 넉넉하다 — 브라우저가 페이지 전체를 복사하는 경우를 막는 상한이다.
pub const SELECTION_MAX_BYTES: usize = 1 << 20;

/// 받는 기한(design 결정 33). `Cmd+Q`의 기한(`KILL_AFTER_MS`)과 같은 2초 — 클라이언트가 멈춰도(SIGSTOP) 읽기가 영영
/// 매달리지 않는다.
pub const SELECTION_TIMEOUT_MS: i32 = 2000;

/// `set_selection`을 받아들이는 조건(design 결정 36). serial 값은 보지 않는다 — SDL은 serial 0을 보내는 길이 있다.
/// 받아들이는 것은 "지금 또는 가장 최근에 키보드 포커스를 가졌던 클라이언트"다. 포커스가 셸로 가도(null) `last`는 남는다 —
/// `Cmd+C` 바로 뒤의 `Cmd+1`은 `leave`가 `set_selection`보다 먼저 갈 수 있기 때문이다. 포커스가 있으면 `last`가 곧 지금
/// 클라이언트이므로 칸 하나로 둘을 함께 본다.
///
/// 클라이언트는 수(`usize` — 서버가 `wl_client` 포인터를 넣는다)로만 안다. 포인터는 클라이언트가 끝난 뒤 다시 쓰일 수
/// 있으므로, 끝난 클라이언트는 `forget`으로 지운다.
pub const SelectionGate = struct {
    last: ?usize = null,

    /// 키보드 포커스가 `client`로 갔다(null이면 셸 — `last`는 그대로).
    pub fn focus(self: *SelectionGate, client: ?usize) void {
        if (client) |c| self.last = c;
    }

    /// 클라이언트가 끝났다.
    pub fn forget(self: *SelectionGate, client: usize) void {
        if (self.last == client) self.last = null;
    }

    /// `client`의 `set_selection`을 받아들이는가. 포커스를 가져 본 적 없는 클라이언트(배경 프로세스)는 안 된다.
    pub fn allows(self: SelectionGate, client: usize) bool {
        return self.last == client;
    }
};

// ── text_input 상태(WY-M5, design 결정 38 · 43) ────────────────────────────

/// `zwp_text_input_v3` 객체 하나의 서버 쪽 상태. xml의 이중 버퍼를 셈만으로 든다 — `enable` · `disable`은 pending을 바꾸고
/// `commit`이 current(`enabled`)로 옮긴다. 상태 요청 셋(surrounding · content_type · cursor_rectangle)은 받기만 하므로 여기 없다.
///
/// surface는 수(`usize` — 서버가 `wl_surface` 포인터를 넣는다)로만 안다. 0은 "들어간 surface가 없다"다.
///
/// 규칙(xml 1.44):
/// - `enter`는 current surface를 정하고 모든 상태를 무효로 한다 — 클라이언트가 다시 enable해야 켜진다.
/// - `leave` 뒤 다음 `enter`까지 요청은 무시한다(`enable` · `disable`은 pending을 안 바꾸고 `commit`은 적용하지 않는다).
/// - enable · disable은 짝이 안 맞아도, 연속이어도 된다 — 마지막 것이 이긴다.
/// - `commit`은 들어가 있든 없든 센다. `done`의 serial은 "그 객체에서 온 commit 요청 수"다 — 클라이언트가 세는 수와
///   같아야 하므로 무시한 commit도 센다.
pub const TextInput = struct {
    entered: usize = 0,
    pending: ?bool = null,
    enabled: bool = false,
    commits: u32 = 0,

    /// 키보드 포커스가 그 클라이언트의 surface로 왔다.
    pub fn enter(self: *TextInput, surface: usize) void {
        self.entered = surface;
        self.pending = null;
        self.enabled = false;
    }

    /// 키보드 포커스가 떠났다(또는 그 surface가 사라졌다).
    pub fn leave(self: *TextInput) void {
        self.entered = 0;
        self.pending = null;
        self.enabled = false;
    }

    pub fn enable(self: *TextInput) void {
        if (self.entered != 0) self.pending = true;
    }

    pub fn disable(self: *TextInput) void {
        if (self.entered != 0) self.pending = false;
    }

    /// `commit` 요청. 셈을 하나 올리고, 들어가 있으면 pending을 current로 옮긴다.
    pub fn commit(self: *TextInput) void {
        self.commits +%= 1;
        if (self.entered == 0) return;
        if (self.pending) |p| self.enabled = p;
        self.pending = null;
    }

    /// 이 surface에서 켜져 있는가 — 서버의 `imeActive`가 포커스 surface로 묻는다.
    pub fn activeOn(self: TextInput, surface: usize) bool {
        return surface != 0 and self.enabled and self.entered == surface;
    }
};

// ── surface 트리(WY-M7 단계 A, design 결정 48 ~ 51) ──────────────────────────

/// window geometry(`xdg_surface.set_window_geometry`) — surface 좌표의 사각형. 클라이언트가 준 값 그대로라 음수가 들 수 있다.
pub const Rect = struct { x: i32, y: i32, w: i32, h: i32 };

/// `fitIn`을 window geometry로 한다(design 결정 50). geometry가 없거나 surface와 겹치지 않으면 `fitIn` 그대로 — geometry를 안
/// 보내는 클라이언트(둠 · SDL · tars-wl-test)의 자리는 한 픽셀도 안 바뀐다. 있으면 surface 안으로 자른 geometry 크기로 `fitIn`을
/// 하고 `ox` · `oy`에 geometry의 왼쪽 위를 더한다 — 그림자 여백이 화면 밖(잘린 쪽)으로 간다. `ox` · `oy`는 늘린 surface 그림의
/// 자리라(`blitClip` · `surfacePoint` · `damageScreen`이 그렇게 읽는다) 포인터 좌표는 여전히 surface 좌표다.
pub fn fitGeom(a: Area, sw: u32, sh: u32, geom: ?Rect) ?Fit {
    const g = geom orelse return fitIn(a, sw, sh);
    const x0: i64 = @max(@as(i64, g.x), 0);
    const y0: i64 = @max(@as(i64, g.y), 0);
    const x1: i64 = @min(@as(i64, g.x) + g.w, @as(i64, sw));
    const y1: i64 = @min(@as(i64, g.y) + g.h, @as(i64, sh));
    if (x1 <= x0 or y1 <= y0) return fitIn(a, sw, sh);
    var f = fitIn(a, @intCast(x1 - x0), @intCast(y1 - y0)) orelse return null;
    f.ox += @as(u32, @intCast(x0)) * f.k;
    f.oy += @as(u32, @intCast(y0)) * f.k;
    return f;
}

/// 창의 surface 좌표 (0, 0)이 놓인 화면 자리(늘린 단위 `f.k`). 자식의 화면 원점은 여기에 (뿌리 좌표의 자리 × `k`)를 더한다.
pub fn rootOrigin(f: Fit) [2]i64 {
    return .{ @as(i64, f.x) - f.ox, @as(i64, f.y) - f.oy };
}

/// premultiplied ARGB `src`를 `dst` 위에 얹는다(over). 결과의 알파는 FF — 프레임버퍼는 XRGB다.
pub fn over(src: u32, dst: u32) u32 {
    const a = src >> 24;
    if (a == 0xFF) return src;
    if (a == 0) return dst;
    const inv = 255 - a;
    var out: u32 = 0xFF000000;
    var sh: u5 = 0;
    while (true) : (sh += 8) {
        const s = (src >> sh) & 0xFF;
        const d = (dst >> sh) & 0xFF;
        const c: u32 = @min(@as(u32, 255), s + (d * inv + 127) / 255);
        out |= c << sh;
        if (sh == 16) break;
    }
    return out;
}

/// surface 하나(`src`, `sw` × `sh` surface 단위, buffer_scale `bs`)를 화면 원점 (`ox`, `oy`)에 `k`배로 놓아 `clip` 안만 그린다(design 결정 49).
/// `argb`면 premultiplied over로 섞고, 아니면(XRGB) 덮는다. 원점은 음수일 수 있다(자식이 부모 밖으로 나간 자리). 화면 픽셀 `X`는 버퍼 픽셀
/// `(X − ox) · bs / k`다 — `blitClip`과 같은 셈이다.
pub fn blendClip(dst: [*]u8, dst_pitch: u32, ox: i64, oy: i64, k: u32, src: [*]const u8, src_stride: u32, bs: u32, sw: u32, sh: u32, clip: Area, argb: bool) void {
    const kk: i64 = k;
    const x0 = @max(ox, @as(i64, clip.x));
    const y0 = @max(oy, @as(i64, clip.y));
    const x1 = @min(ox + @as(i64, sw) * kk, @as(i64, clip.x) + clip.w);
    const y1 = @min(oy + @as(i64, sh) * kk, @as(i64, clip.y) + clip.h);
    if (x1 <= x0 or y1 <= y0) return;
    const b: i64 = bs;
    var y = y0;
    while (y < y1) : (y += 1) {
        const sy: usize = @intCast(@divFloor((y - oy) * b, kk));
        const srow: [*]align(1) const u32 = @ptrCast(src + sy * src_stride);
        const drow: [*]align(1) u32 = @ptrCast(dst + @as(usize, @intCast(y)) * dst_pitch);
        // 1:1(k == bs — 배율 1의 bs 1, 물리의 bs 2)은 나눗셈 없이 같은 자리를 읽는다(WY-M7 단계 B 실측 — 메뉴 한 장이 이 길이다). XRGB는 행 복사.
        if (k == bs) {
            const from: usize = @intCast(x0 - ox);
            const n: usize = @intCast(x1 - x0);
            const d0: usize = @intCast(x0);
            if (!argb) {
                @memcpy(drow[d0..][0..n], srow[from..][0..n]);
                continue;
            }
            for (0..n) |i| {
                const sp = srow[from + i];
                if (sp >> 24 == 0xFF) {
                    drow[d0 + i] = sp;
                } else if (sp >> 24 != 0) drow[d0 + i] = over(sp, drow[d0 + i]);
            }
            continue;
        }
        var x = x0;
        while (x < x1) : (x += 1) {
            const sp = srow[@intCast(@divFloor((x - ox) * b, kk))];
            const di: usize = @intCast(x);
            drow[di] = if (argb) over(sp, drow[di]) else sp;
        }
    }
}

/// 버퍼 좌표의 damage `r`(그 surface의 buffer_scale `bs`)가 화면에서 차지하는 자리 — surface 원점 (`ox`, `oy`), 늘림 `k`. `clip`으로 자르고
/// 겹치지 않으면 null. 바깥으로 반올림한다(`damageScreen`과 같다). 자식의 damage를 부분 blit에 더할 때 쓴다(design 결정 49).
pub fn damageAt(ox: i64, oy: i64, k: u32, bs: u32, r: Area, clip: Area) ?Area {
    const kk: i64 = k;
    const b: i64 = bs;
    const x0 = @max(ox + @divFloor(@as(i64, r.x) * kk, b), @as(i64, clip.x));
    const y0 = @max(oy + @divFloor(@as(i64, r.y) * kk, b), @as(i64, clip.y));
    const x1 = @min(ox + @divFloor((@as(i64, r.x) + r.w) * kk + b - 1, b), @as(i64, clip.x) + clip.w);
    const y1 = @min(oy + @divFloor((@as(i64, r.y) + r.h) * kk + b - 1, b), @as(i64, clip.y) + clip.h);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = @intCast(x0), .y = @intCast(y0), .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
}

/// 화면 사각형 (`x`, `y`, `w` × `h` — 원점은 음수일 수 있다)이 `a` 안에 다 드는가. 자식이 창의 보이는 사각형 밖으로 나가면 부분 blit을 안 쓰고
/// 통째로 간다(그 바깥은 통째 프레임만 다시 그리므로).
pub fn within(x: i64, y: i64, w: i64, h: i64, a: Area) bool {
    return x >= a.x and y >= a.y and x + w <= @as(i64, a.x) + a.w and y + h <= @as(i64, a.y) + a.h;
}

/// 입력 영역(`wl_surface.set_input_region`, design 결정 50). `all`이면 무한(xml의 처음 값 · null region), 아니면 `box`(상자의 합 — 없으면 빈 영역).
pub const Input = struct {
    all: bool = true,
    box: ?Box = null,

    /// surface 좌표의 점(`wl_fixed`)이 영역 안인가.
    pub fn contains(self: Input, fx: i64, fy: i64) bool {
        if (self.all) return true;
        const b = self.box orelse return false;
        return fx >= b.x0 * 256 and fx < b.x1 * 256 and fy >= b.y0 * 256 and fy < b.y1 * 256;
    }
};

/// 포인터가 고를 수 있는 surface 하나(design 결정 51) — 뿌리 surface 좌표의 자리(`x` · `y`, surface 단위)와 크기, 입력 영역.
pub const Cand = struct { x: i64, y: i64, w: i64, h: i64, input: Input };

/// 뿌리 surface 좌표의 점(`wl_fixed` — `surfacePoint`가 준 값)이 어느 후보 위인가. `cands`는 위에서부터다 — 처음 맞는 것. 없으면 null(부르는 쪽이
/// 뿌리를 고른다). 후보의 사각형 안이고 그 입력 영역 안이어야 한다(Chromium의 bubble은 위 44줄을 입력 영역에서 뺀다 — 그 자리는 부모의 주소창이다).
pub fn pick(cands: []const Cand, fx: i64, fy: i64) ?usize {
    for (cands, 0..) |c, i| {
        if (fx < c.x * 256 or fy < c.y * 256 or fx >= (c.x + c.w) * 256 or fy >= (c.y + c.h) * 256) continue;
        if (c.input.contains(fx - c.x * 256, fy - c.y * 256)) return i;
    }
    return null;
}

/// 쌓임 순서의 한 칸을 다른 칸 바로 위(`above`) 또는 아래로 옮긴다(`wl_subsurface.place_above/below`). `items`는 아래에서부터이고 둘 다 들어 있어야
/// 한다 — 없으면 false. 길이는 그대로다(빼고 넣기).
pub fn restack(comptime T: type, items: []T, who: T, ref: T, above: bool) bool {
    const from = std.mem.indexOfScalar(T, items, who) orelse return false;
    _ = std.mem.indexOfScalar(T, items, ref) orelse return false;
    if (who == ref) return false;
    // 빼기 — 뒤를 당긴다.
    var i = from;
    while (i + 1 < items.len) : (i += 1) items[i] = items[i + 1];
    const n = items.len - 1;
    const r = std.mem.indexOfScalar(T, items[0..n], ref).?;
    const at = if (above) r + 1 else r;
    // 넣기 — 뒤를 민다.
    var j = n;
    while (j > at) : (j -= 1) items[j] = items[j - 1];
    items[at] = who;
    return true;
}

/// subsurface가 실제로 sync처럼 구는가(xml) — 자기가 sync이거나, 부모가 sync처럼 굴면(재귀) 그렇다. `chain`은 자기부터 위로 각 subsurface의 sync
/// 깃발이다(뿌리 surface는 subsurface가 아니라 들지 않는다 — 늘 desync처럼 군다).
pub fn effectiveSync(chain: []const bool) bool {
    for (chain) |s| if (s) return true;
    return false;
}

// ── popup의 자리(WY-M7 단계 B, design 결정 52) ────────────────────────────────

/// `xdg_positioner`의 상태(xml). 크기는 popup의 window geometry, anchor 사각형은 부모 window geometry 좌표다. `anchor` · `gravity`는 enum 값(0 ~ 8),
/// `ca`는 constraint_adjustment 비트(slide_x 1 · slide_y 2 · flip_x 4 · flip_y 8 · resize_x 16 · resize_y 32).
pub const Positioner = struct {
    w: i32 = 0,
    h: i32 = 0,
    ax: i32 = 0,
    ay: i32 = 0,
    aw: i32 = 0,
    ah: i32 = 0,
    anchor: u32 = 0,
    gravity: u32 = 0,
    ca: u32 = 0,
    ox: i32 = 0,
    oy: i32 = 0,

    /// xml: 크기와 anchor 사각형이 있어야 완전하다(`invalid_positioner`).
    pub fn complete(self: Positioner) bool {
        return self.w > 0 and self.h > 0 and self.aw > 0 and self.ah > 0;
    }
};

pub const CA_SLIDE_X: u32 = 1;
pub const CA_SLIDE_Y: u32 = 2;
pub const CA_FLIP_X: u32 = 4;
pub const CA_FLIP_Y: u32 = 8;
pub const CA_RESIZE_X: u32 = 16;
pub const CA_RESIZE_Y: u32 = 32;

/// enum 값(anchor · gravity 같다)의 x 쪽 — 왼쪽 -1, 가운데 0, 오른쪽 1.
fn sideX(v: u32) i32 {
    return switch (v) {
        3, 5, 6 => -1,
        4, 7, 8 => 1,
        else => 0,
    };
}

/// y 쪽 — 위 -1, 가운데 0, 아래 1.
fn sideY(v: u32) i32 {
    return switch (v) {
        1, 5, 7 => -1,
        2, 6, 8 => 1,
        else => 0,
    };
}

/// 한 축의 제약 없는 자리: anchor 점(사각형의 그 쪽 끝 · 가운데) + offset에서 gravity 쪽으로 놓는다.
fn axisAt(a0: i32, alen: i32, aside: i32, gside: i32, size: i32, off: i32) i32 {
    const pt = a0 + switch (aside) {
        -1 => @as(i32, 0),
        1 => alen,
        else => @divTrunc(alen, 2),
    };
    return pt + off - switch (gside) {
        -1 => size,
        1 => @as(i32, 0),
        else => @divTrunc(size, 2),
    };
}

const Span = struct { pos: i32, size: i32 };

fn fits(pos: i32, size: i32, lo: i32, hi: i32) bool {
    return pos >= lo and pos + size <= hi;
}

/// 한 축(xml의 순서 flip → slide → resize). flip은 뒤집은 자리가 안 걸릴 때만 쓴다(걸리면 뒤집기 전으로 — xml). slide는 넘친 쪽을 안으로 밀고, 그래도
/// 넘치면(경계보다 크다) 시작 쪽(왼쪽 · 위)을 맞춘다. resize는 경계 밖을 잘라 낸다(남는 크기가 0 이하면 그대로).
fn axisPlace(a0: i32, alen: i32, aside: i32, gside: i32, size: i32, off: i32, lo: i32, hi: i32, flip: bool, slide: bool, resize: bool) Span {
    var pos = axisAt(a0, alen, aside, gside, size, off);
    var len = size;
    if (fits(pos, len, lo, hi)) return .{ .pos = pos, .size = len };
    if (flip) {
        const fp = axisAt(a0, alen, -aside, -gside, size, off);
        if (fits(fp, len, lo, hi)) return .{ .pos = fp, .size = len };
    }
    if (slide) {
        if (pos + len > hi) pos = hi - len;
        if (pos < lo) pos = lo;
    }
    if (resize and !fits(pos, len, lo, hi)) {
        const x0 = @max(pos, lo);
        const x1 = @min(pos + len, hi);
        if (x1 > x0) {
            pos = x0;
            len = x1 - x0;
        }
    }
    return .{ .pos = pos, .size = len };
}

/// popup의 자리와 크기(부모 window geometry 좌표 — `xdg_popup.configure`의 값). `bounds`도 부모 geometry 좌표의 경계(앞 workspace의 화면에서 위 띠와 상태 줄을
/// 뺀 것 — design 결정 52)이고, null이면 제약 없이 놓는다(부모가 아직 안 그려졌다).
pub fn placePopup(p: Positioner, bounds: ?Rect) Rect {
    const b = bounds orelse return .{
        .x = axisAt(p.ax, p.aw, sideX(p.anchor), sideX(p.gravity), p.w, p.ox),
        .y = axisAt(p.ay, p.ah, sideY(p.anchor), sideY(p.gravity), p.h, p.oy),
        .w = p.w,
        .h = p.h,
    };
    const x = axisPlace(p.ax, p.aw, sideX(p.anchor), sideX(p.gravity), p.w, p.ox, b.x, b.x + b.w, p.ca & CA_FLIP_X != 0, p.ca & CA_SLIDE_X != 0, p.ca & CA_RESIZE_X != 0);
    const y = axisPlace(p.ay, p.ah, sideY(p.anchor), sideY(p.gravity), p.h, p.oy, b.y, b.y + b.h, p.ca & CA_FLIP_Y != 0, p.ca & CA_SLIDE_Y != 0, p.ca & CA_RESIZE_Y != 0);
    return .{ .x = x.pos, .y = y.pos, .w = x.size, .h = y.size };
}
