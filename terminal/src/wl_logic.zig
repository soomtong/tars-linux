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
