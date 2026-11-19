//! WY-M0: Wayland 서버의 순수한 부분(WY design 결정 1 · 9, plan 확정 4 · 8). 시스템 콜도 libwayland도 안 부른다 —
//! `wl_logic_test.zig`가 호스트에서 본다. `layout.zig`와 같은 경계다.
//!
//! 여섯이다. (1) 정수 배율과 가운데 자리(`fit`), (2) 그 자리로 옮기는 가장 가까운 픽셀 늘리기(`blit`),
//! (3) xdg toplevel의 configure 순서(`onCommit`), (4) `wl_keyboard.modifiers`의 비트(`modifierMask`, 단계 C),
//! (5) 클라이언트에 누름을 보낸 키의 목록(`Held`, 단계 C), (6) `Cmd+Q`의 2초 기한(`Deadline`, 단계 C).
//! WY-M2가 둘을 더했다 — pane 사각형 안의 자리(`fitIn`)와 configure의 states(`toplevelStates`).

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
