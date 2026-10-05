//! 터치패드 하나의 raw `input_event`를 `pointer.Frame`으로 바꾸는 순수한 층
//! (PD design 결정 8).
//!
//! 시스템 콜이 없다. 장치를 열고 축 정보를 ioctl로 읽는 것은 `main.zig`이고,
//! 이 파일은 그 값과 이벤트를 받아 판단만 한다 — 그래서 `touchpad_test`가
//! 부팅 없이 같은 판단을 본다. 출력이 마우스 디코더(`pointer.Mouse`)와 같은
//! `Frame`이라서 그 아래(`Pointer` · `Gesture`)는 터치패드를 모른다.
//!
//! 하는 것은 넷이다. 한 손가락은 이동, 짧게 두드리면 왼쪽 클릭, 두 손가락을
//! 세로로 밀면 휠, 물리 버튼은 그대로 통과. 안 하는 것은 design 비목표 6이다
//! (가속 · 손바닥 거부 · 가장자리 스크롤 · 세 손가락 · 관성 · 두 손가락 탭 등).
const std = @import("std");
const pointer = @import("pointer.zig");
const c = pointer.c;

/// 따라가는 접촉 칸의 수. 장치가 더 많은 칸을 알려도 여기서 자른다 — 이동과
/// 두 손가락 스크롤에는 둘이면 되고, 손가락 수는 `BTN_TOOL_*`가 따로 센다.
pub const MAX_SLOTS = 5;

/// 탭으로 치는 접촉의 최대 길이(마이크로초). design 결정 8의 출발값 180ms다.
/// 실기 없이 정한 값이라 사람이 손으로 본 뒤 고친다(design 위험 3) — 고치면
/// `touchpad_test`의 탭 검사도 함께 고친다.
pub const TAP_US: i64 = 180_000;

/// 탭이 움직여도 되는 거리. 축 범위의 2%다(design 결정 8의 출발값).
pub const TAP_SLOP_PERCENT: i64 = 2;

/// `EVIOCGABS`가 돌려준 축 하나(`struct input_absinfo`의 셋).
pub const Axis = struct {
    min: i32,
    max: i32,
    /// 단위/mm. 0이면 장치가 안 알려 준 것이다.
    res: i32 = 0,

    fn range(self: Axis) i64 {
        const r = @as(i64, self.max) - self.min;
        return if (r > 0) r else 1;
    }

    fn slop(self: Axis) i64 {
        return @divTrunc(self.range() * TAP_SLOP_PERCENT, 100);
    }
};

/// 접촉을 어디서 읽나. `mt`는 MT 프로토콜 B(`ABS_MT_SLOT`의 칸마다),
/// `st`는 단일 터치(`ABS_X` · `ABS_Y`와 `BTN_TOUCH` 하나)다.
pub const Mode = enum { mt, st };

/// 이 장치를 어느 방식으로 읽을지 고른다. 둘 다 안 되면 null이다 — `main.zig`가
/// 그 장치를 열지 않는다.
///
/// MT인데 `ABS_MT_SLOT`이 없는 장치(프로토콜 A)는 `ABS_X` · `ABS_Y`가 있으면
/// 단일 터치로 읽는다. 커널의 노트북 터치패드 드라이버(hid-multitouch · psmouse ·
/// RMI4)는 전부 프로토콜 B라서 이 갈래는 옛 장치의 대비다.
pub fn modeOf(caps: *const pointer.Caps) ?Mode {
    const has = pointer.bitSet;
    if (has(&caps.abs, c.ABS_MT_SLOT) and has(&caps.abs, c.ABS_MT_POSITION_X) and
        has(&caps.abs, c.ABS_MT_POSITION_Y)) return .mt;
    if (has(&caps.abs, c.ABS_X) and has(&caps.abs, c.ABS_Y)) return .st;
    return null;
}

/// 장치를 열 때 한 번 읽는 값. `main.zig`가 `EVIOCGABS`로 채운다.
pub const Setup = struct {
    mode: Mode,
    /// `mt`면 `ABS_MT_POSITION_X/Y`, `st`면 `ABS_X/Y`의 축.
    x: Axis,
    y: Axis,
    /// 접촉 칸의 수(`ABS_MT_SLOT`의 max + 1). `st`면 1이다.
    slots: usize = 1,
    /// 열 때의 `ABS_MT_SLOT` 값. 커널은 칸이 바뀔 때만 그 이벤트를 보낸다.
    slot: usize = 0,
};

/// 화면 쪽 값 둘. 패드의 단위를 픽셀로 바꾸고 스크롤을 눈금으로 바꾼다.
pub const Screen = struct {
    /// 프레임버퍼의 가로 픽셀. 패드 가로 전체가 이것이 된다(design 결정 8).
    w: u32,
    /// 휠 한 눈금으로 칠 손가락 이동(픽셀). `main.zig`가 `WHEEL_ROWS ×
    /// ROW_HEIGHT`를 넘긴다 — 한 눈금이 세 줄이므로 손가락과 글자가 같은
    /// 거리를 간다.
    notch_px: u32,
};

/// 이벤트 하나에 디코더가 내는 `Frame`들. 대개 0개이고, `SYN_REPORT`에 하나,
/// 탭이 끝난 `SYN_REPORT`에만 둘(누름 · 뗌)이다.
pub const Frames = struct {
    buf: [2]pointer.Frame = undefined,
    len: usize = 0,

    pub fn one(f: pointer.Frame) Frames {
        var out: Frames = .{};
        out.push(f);
        return out;
    }

    fn push(self: *Frames, f: pointer.Frame) void {
        self.buf[self.len] = f;
        self.len += 1;
    }

    pub fn slice(self: *const Frames) []const pointer.Frame {
        return self.buf[0..self.len];
    }
};

/// 접촉 칸 하나.
const Contact = struct {
    /// tracking id. -1이면 칸이 비었다.
    id: i32 = -1,
    /// 커널이 마지막으로 알린 자리. 커널의 입력 core는 같은 값을 다시 보내지
    /// 않으므로 손가락이 떨어졌다 같은 x에 다시 닿으면 x 이벤트가 안 온다 —
    /// 그래서 칸이 비어도 지우지 않는다.
    x: i32 = 0,
    y: i32 = 0,
    /// 직전 `SYN_REPORT` 때의 자리. 그때 닿아 있지 않았으면 null이다.
    prev: ?[2]i32 = null,
    /// 이번 묶음에서 새 tracking id를 받았다. 이 묶음은 변화량을 안 낸다.
    fresh: bool = false,
    /// 몇 번째로 닿은 접촉인가. 클수록 늦게 닿았다.
    order: u32 = 0,
};

pub const Touchpad = struct {
    setup: Setup,
    screen: Screen,
    contacts: [MAX_SLOTS]Contact = @splat(.{}),
    /// 지금 고른 칸(`ABS_MT_SLOT`). 범위 밖이면 그 칸의 이벤트를 버린다.
    slot: usize = 0,
    /// `BTN_TOOL_FINGER`(비트 0) ~ `BTN_TOOL_QUINTTAP`(비트 4) 중 눌린 것.
    tool_bits: u8 = 0,
    /// `BTN_TOUCH`. 단일 터치 모드의 접촉이다.
    touch: bool = false,
    /// 물리 버튼(clickpad의 `BTN_LEFT` 등). 그대로 통과한다.
    held: pointer.Buttons = .{},
    /// 마지막으로 낸 `Frame`의 버튼. 버튼만 바뀐 묶음도 `Frame`을 내려고 든다.
    sent: pointer.Buttons = .{},
    /// `SYN_DROPPED`를 받았다. 다음 `SYN_REPORT`까지 버린다.
    dropping: bool = false,
    /// 접촉에 붙이는 순번(`Contact.order`).
    touches: u32 = 0,
    /// 픽셀로 바꾸고 남은 나머지. 작은 이동이 버려지지 않게 다음 묶음에 넘긴다.
    rem_x: i64 = 0,
    rem_y: i64 = 0,
    /// 두 손가락 스크롤 중인가와, 눈금이 되기 전의 픽셀.
    scrolling: bool = false,
    scroll_rem: i64 = 0,
    scroll_px: i64 = 0,
    /// 손가락이 0에서 늘어난 뒤 다시 0이 될 때까지가 한 세션이다. 탭인지는
    /// 세션이 끝날 때 가린다.
    session: bool = false,
    tap_ok: bool = false,
    tap_order: u32 = 0,
    tap_start_us: i64 = 0,
    tap_x: i32 = 0,
    tap_y: i32 = 0,

    pub fn init(setup: Setup, screen: Screen) Touchpad {
        var s = setup;
        s.slots = @min(@max(s.slots, 1), MAX_SLOTS);
        if (s.mode == .st) s.slots = 1;
        return .{ .setup = s, .screen = screen, .slot = s.slot };
    }

    /// 이벤트 하나를 먹인다. `t_us`는 그 이벤트의 시각(`ev.time`)이다 — 커널이
    /// 묶음마다 찍으므로 terminal이 늦게 읽어도 탭의 길이가 안 흔들린다.
    pub fn feed(self: *Touchpad, ev_type: u16, code: u16, value: i32, t_us: i64) Frames {
        if (ev_type == c.EV_SYN) {
            if (code == c.SYN_DROPPED) {
                self.dropping = true;
                return .{};
            }
            if (code != c.SYN_REPORT) return .{};
            if (self.dropping) {
                self.dropping = false;
                return self.resync();
            }
            return self.report(t_us);
        }
        if (self.dropping) return .{};
        switch (ev_type) {
            c.EV_ABS => self.abs(code, value),
            c.EV_KEY => self.key(code, value),
            // `EV_MSC`(`MSC_TIMESTAMP` 등)와 그 밖은 버린다.
            else => {},
        }
        return .{};
    }

    fn current(self: *Touchpad) ?*Contact {
        if (self.slot >= self.setup.slots) return null;
        return &self.contacts[self.slot];
    }

    fn abs(self: *Touchpad, code: u16, value: i32) void {
        switch (self.setup.mode) {
            .mt => switch (code) {
                c.ABS_MT_SLOT => self.slot = if (value >= 0) @intCast(value) else MAX_SLOTS,
                c.ABS_MT_TRACKING_ID => if (self.current()) |k| {
                    if (value < 0) {
                        k.id = -1;
                    } else if (k.id != value) {
                        k.id = value;
                        k.fresh = true;
                        self.touches += 1;
                        k.order = self.touches;
                    }
                },
                c.ABS_MT_POSITION_X => if (self.current()) |k| {
                    k.x = value;
                },
                c.ABS_MT_POSITION_Y => if (self.current()) |k| {
                    k.y = value;
                },
                // MT 장치가 함께 내는 `ABS_X` · `ABS_Y`(포인터 흉내)는 버린다.
                else => {},
            },
            .st => switch (code) {
                c.ABS_X => self.contacts[0].x = value,
                c.ABS_Y => self.contacts[0].y = value,
                else => {},
            },
        }
    }

    fn key(self: *Touchpad, code: u16, value: i32) void {
        const on = value != 0;
        const tool: ?u3 = switch (code) {
            c.BTN_TOOL_FINGER => 0,
            c.BTN_TOOL_DOUBLETAP => 1,
            c.BTN_TOOL_TRIPLETAP => 2,
            c.BTN_TOOL_QUADTAP => 3,
            c.BTN_TOOL_QUINTTAP => 4,
            else => null,
        };
        if (tool) |bit| {
            const mask = @as(u8, 1) << bit;
            self.tool_bits = if (on) self.tool_bits | mask else self.tool_bits & ~mask;
            return;
        }
        switch (code) {
            c.BTN_LEFT => self.held.left = on,
            c.BTN_RIGHT => self.held.right = on,
            c.BTN_MIDDLE => self.held.middle = on,
            c.BTN_TOUCH => self.touch = on,
            else => {},
        }
    }

    /// `BTN_TOOL_*`가 말하는 손가락 수. 칸보다 손가락을 더 세는 장치가 있어서
    /// 따로 든다(design 결정 8).
    fn toolFingers(self: *const Touchpad) usize {
        if (self.tool_bits == 0) return 0;
        return 8 - @as(usize, @clz(self.tool_bits));
    }

    /// 단일 터치 모드의 칸 0을 `BTN_TOUCH`(또는 `BTN_TOOL_*`)로 열고 닫는다.
    fn stContact(self: *Touchpad) void {
        const k = &self.contacts[0];
        const down = self.touch or self.tool_bits != 0;
        if (down and k.id < 0) {
            k.id = 0;
            k.fresh = true;
            self.touches += 1;
            k.order = self.touches;
        } else if (!down) {
            k.id = -1;
        }
    }

    /// `SYN_REPORT` 하나 — 모은 상태를 `Frame`으로 바꾼다.
    fn report(self: *Touchpad, t_us: i64) Frames {
        if (self.setup.mode == .st) self.stContact();

        var active: usize = 0;
        // 포인터를 움직일 접촉은 가장 늦게 닿은 것이다. 엄지로 버튼을 누른 채
        // 검지로 끄는 동작에서 검지가 그것이다(design 결정 8의 물리 버튼 줄).
        var point: ?*Contact = null;
        for (self.contacts[0..self.setup.slots]) |*k| {
            if (k.id < 0) continue;
            active += 1;
            if (point == null or k.order > point.?.order) point = k;
        }
        const fingers = @max(active, self.toolFingers());
        const pressing = self.held.bits() != 0;

        var f: pointer.Frame = .{ .buttons = self.held };
        if (pressing or fingers == 1) {
            self.scrolling = false;
            if (point) |p| {
                if (!p.fresh) {
                    if (p.prev) |q| {
                        f.dx = scale(p.x - q[0], self.screen.w, self.setup.x.range(), &self.rem_x);
                        const yd = self.yRatio();
                        f.dy = scale(p.y - q[1], yd[0], yd[1], &self.rem_y);
                    }
                }
            }
        } else if (fingers == 2) {
            f.wheel = self.scroll();
        } else {
            // 손가락이 없거나 셋 이상이다. 셋 이상은 비목표 6이다.
            self.scrolling = false;
        }

        const tap = self.tapStep(fingers, pressing, point, t_us);

        for (self.contacts[0..self.setup.slots]) |*k| {
            k.prev = if (k.id >= 0) .{ k.x, k.y } else null;
            k.fresh = false;
        }

        var out: Frames = .{};
        if (tap) {
            // 누름과 뗌을 한 쌍으로 낸다(design 결정 8). 둘 다 같은 자리라서
            // `Pointer.apply`가 눌림 하나와 뗌 하나를 차례로 낸다 — 클릭이다.
            var down = f;
            down.buttons.left = true;
            out.push(down);
            out.push(.{ .buttons = self.held });
            self.sent = self.held;
            return out;
        }
        if (f.dx != 0 or f.dy != 0 or f.wheel != 0 or f.buttons.bits() != self.sent.bits()) {
            out.push(f);
            self.sent = f.buttons;
        }
        return out;
    }

    /// 세로의 픽셀/단위를 분수(분자, 분모)로. 두 축의 resolution이 다 있으면
    /// 가로와 같은 mm당 픽셀이 되게 맞추고, 없으면 가로와 같은 단위당 픽셀을
    /// 쓴다(design 결정 8). 패드 세로를 화면 세로에 맞추지 않는다 — 그러면 같은
    /// 손가락 거리가 가로와 세로에서 다른 픽셀이 된다.
    fn yRatio(self: *const Touchpad) [2]i64 {
        const x = self.setup.x;
        const y = self.setup.y;
        const w: i64 = self.screen.w;
        if (x.res > 0 and y.res > 0) return .{ w * x.res, x.range() * y.res };
        return .{ w, x.range() };
    }

    /// 두 손가락의 평균 세로 변화를 픽셀로 모아 눈금을 낸다. 손가락을 아래로
    /// 밀면 내용도 아래로 간다(macOS 트랙패드 기본) — 휠을 앞으로 민 것(양수,
    /// 위의 글을 보이게 한다)과 같은 쪽이다.
    fn scroll(self: *Touchpad) i32 {
        if (!self.scrolling) {
            self.scrolling = true;
            self.scroll_rem = 0;
            self.scroll_px = 0;
        }
        var sum: i64 = 0;
        var n: i64 = 0;
        for (self.contacts[0..self.setup.slots]) |*k| {
            if (k.id < 0 or k.fresh) continue;
            const q = k.prev orelse continue;
            sum += @as(i64, k.y) - q[1];
            n += 1;
        }
        if (n == 0) return 0;
        const yd = self.yRatio();
        self.scroll_px += scale(@divTrunc(sum, n), yd[0], yd[1], &self.scroll_rem);
        const notch: i64 = @max(self.screen.notch_px, 1);
        const notches = @divTrunc(self.scroll_px, notch);
        self.scroll_px -= notches * notch;
        return @intCast(notches);
    }

    /// 탭인지 가린다. 세션(손가락이 0에서 늘어난 뒤 다시 0이 될 때까지)이
    /// 한 손가락뿐이었고, 버튼이 안 눌렸고, 같은 접촉이 축 범위의 2% 안에
    /// 머물렀고, `TAP_US`보다 짧았으면 끝나는 묶음에서 참이다.
    fn tapStep(self: *Touchpad, fingers: usize, pressing: bool, point: ?*const Contact, t_us: i64) bool {
        if (fingers > 0 and !self.session) {
            self.session = true;
            self.tap_ok = !pressing and fingers == 1 and point != null;
            self.tap_start_us = t_us;
            if (point) |p| {
                self.tap_order = p.order;
                self.tap_x = p.x;
                self.tap_y = p.y;
            }
            return false;
        }
        if (fingers > 0) {
            if (fingers > 1 or pressing) self.tap_ok = false;
            if (point) |p| {
                if (p.order != self.tap_order or
                    far(p.x, self.tap_x, self.setup.x.slop()) or
                    far(p.y, self.tap_y, self.setup.y.slop())) self.tap_ok = false;
            }
            return false;
        }
        if (!self.session) return false;
        self.session = false;
        return self.tap_ok and !pressing and t_us - self.tap_start_us < TAP_US;
    }

    /// `SYN_DROPPED` 뒤 첫 `SYN_REPORT`. 모든 접촉과 버튼을 뗀 것으로 하고 새로
    /// 센다(design 결정 8). `EVIOCGMTSLOTS`로 다시 맞추지 않는다 — 아직 닿아
    /// 있는 손가락은 떨어졌다 다시 닿을 때까지 무시된다. 버튼을 눌린 채로 두면
    /// 버린 구간의 뗌을 잃었을 때 영영 눌린 채가 되므로 놓는다.
    fn resync(self: *Touchpad) Frames {
        for (&self.contacts) |*k| {
            k.id = -1;
            k.prev = null;
            k.fresh = false;
        }
        self.tool_bits = 0;
        self.touch = false;
        self.held = .{};
        self.session = false;
        self.scrolling = false;
        if (self.sent.bits() == 0) return .{};
        self.sent = .{};
        return Frames.one(.{});
    }
};

/// `du` 단위를 `num / den` 배율로 픽셀로 바꾼다. 나머지는 `rem`에 남겨 다음에
/// 더한다 — 10단위씩 열 번 민 것과 100단위를 한 번 민 것이 같은 픽셀이 된다.
fn scale(du: i64, num: i64, den: i64, rem: *i64) i32 {
    const t = du * num + rem.*;
    const q = @divTrunc(t, den);
    rem.* = t - q * den;
    return @intCast(std.math.clamp(q, std.math.minInt(i32), std.math.maxInt(i32)));
}

fn far(a: i32, b: i32, lim: i64) bool {
    const d = @as(i64, a) - b;
    return d > lim or d < -lim;
}
