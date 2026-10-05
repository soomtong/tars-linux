//! 포인터 장치(마우스 · 터치패드)의 순수한 층(PD design 결정 2 · 3).
//!
//! 시스템 콜이 없다. `vt.zig` · `layout.zig`도 import하지 않는다. 장치를 찾고
//! 열고 읽는 것은 `main.zig`이고, 이 파일은 그 바이트를 받아 판단만 한다 —
//! 그래서 `pointer_test`가 부팅 없이 같은 판단을 본다.
//!
//! 층은 셋이다. `classify`(이 장치를 열 것인가) → `Mouse`(raw `input_event`를
//! `SYN_REPORT` 단위의 `Frame`으로) → `Pointer`(화면에 하나인 좌표와 버튼).
//! 누름 · 끎 · 뗌을 의도로 바꾸는 `Gesture`는 PD-M2가 여기에 더한다.
const std = @import("std");

/// `input.zig`의 `c`와 같은 번역(`linux/input.h`)이다. `pub`인 이유도 같다 —
/// `pointer_test`가 커널이 정한 이름(`c.BTN_LEFT`)으로 검사를 쓴다.
pub const c = @import("c_input");

/// 장치 칸의 수(PD design "모델" 절). `Pointer`가 장치별 버튼을 이 수만큼 든다.
pub const MAX_DEVICES = 8;

/// 비트 번호 `max`까지 담는 바이트 수.
fn bytesFor(comptime max: usize) usize {
    return max / 8 + 1;
}

/// 장치의 성질. 연 fd에 ioctl로 묻는 비트맵 다섯이다(PD design 결정 1).
///
/// 크기는 커널의 `*_MAX`에서 나온다 — EV 4 · KEY 96 · REL 2 · ABS 8 · PROP 4
/// 바이트. ioctl에 이 길이를 그대로 넘기므로 커널이 그보다 많이 쓰지 않는다.
pub const Caps = struct {
    ev: [bytesFor(c.EV_MAX)]u8 = @splat(0),
    key: [bytesFor(c.KEY_MAX)]u8 = @splat(0),
    rel: [bytesFor(c.REL_MAX)]u8 = @splat(0),
    abs: [bytesFor(c.ABS_MAX)]u8 = @splat(0),
    prop: [bytesFor(c.INPUT_PROP_MAX)]u8 = @splat(0),
};

/// 비트 `n`이 서 있는가.
///
/// ioctl이 채운 비트맵은 낮은 번호부터다 — 비트 n은 바이트 n/8의 비트 n%8이다.
/// 커널이 `unsigned long` 배열을 그대로 복사하고 x86_64 · aarch64가
/// little-endian이라 그렇다. sysfs의 "높은 워드가 앞" 문자열(init의
/// `devices.zig`)과 순서가 반대라서 그쪽 함수를 옮겨 오지 않는다(design 결정 2).
/// 범위 밖은 거짓이다.
pub fn bitSet(map: []const u8, n: usize) bool {
    if (n / 8 >= map.len) return false;
    return map[n / 8] & (@as(u8, 1) << @intCast(n % 8)) != 0;
}

pub const Kind = enum { mouse, touchpad, none };

/// 이 장치를 포인터로 열 것인가(PD design 결정 2). 이름이 아니라 capability로
/// 가른다(HD 결정 2와 같다).
///
/// 순서에 뜻이 있다. `INPUT_PROP_DIRECT`(터치스크린)는 다른 조건과 상관없이
/// `none`이다. 터치패드를 마우스보다 먼저 본다 — 마우스 모드 노드를 함께 내는
/// 터치패드가 있어서다. usb-tablet은 `ABS_X` · `ABS_Y`가 있어도
/// `INPUT_PROP_POINTER`와 `BTN_TOOL_FINGER`가 없어 `none`이다(design 실측 3).
pub fn classify(caps: *const Caps) Kind {
    if (bitSet(&caps.prop, c.INPUT_PROP_DIRECT)) return .none;
    const has_key = bitSet(&caps.ev, c.EV_KEY);
    if (bitSet(&caps.ev, c.EV_ABS)) {
        const mt = bitSet(&caps.abs, c.ABS_MT_POSITION_X) and bitSet(&caps.abs, c.ABS_MT_POSITION_Y);
        const st = bitSet(&caps.abs, c.ABS_X) and bitSet(&caps.abs, c.ABS_Y);
        const pad = bitSet(&caps.prop, c.INPUT_PROP_POINTER) or
            (has_key and bitSet(&caps.key, c.BTN_TOOL_FINGER));
        if ((mt or st) and pad) return .touchpad;
    }
    if (bitSet(&caps.ev, c.EV_REL) and bitSet(&caps.rel, c.REL_X) and bitSet(&caps.rel, c.REL_Y) and
        has_key and bitSet(&caps.key, c.BTN_LEFT)) return .mouse;
    return .none;
}

/// ioctl 요청 번호 넷(PD design 결정 1). 번역이 `linux/input.h`의 매크로를
/// 함수로 넘겨주므로 그것을 그대로 부른다 — 커널 헤더가 정한 값이 한 벌이다
/// (PD-M0 plan 확정 4). design은 `drm.zig`의 `drmIowr`처럼 손으로 짓기로
/// 했는데, 그것은 `@cImport` 시절 HD 조사 6의 사실이었다.
///
/// 인자가 `comptime`인 이유. 번역된 매크로는 `anytype`이라 runtime 값을 섞으면
/// 시프트의 타입이 갈린다. 부르는 자리는 전부 `Caps`의 배열 길이라 컴파일
/// 때 정해진다. 값은 `pointer_test`가 C 헤더로 잰 수와 대조한다.
pub fn eviocgbit(comptime ev: u16, comptime len: usize) c_ulong {
    return @intCast(c.EVIOCGBIT(ev, len));
}

pub fn eviocgprop(comptime len: usize) c_ulong {
    return @intCast(c.EVIOCGPROP(len));
}

pub fn eviocgname(comptime len: usize) c_ulong {
    return @intCast(c.EVIOCGNAME(len));
}

/// 터치패드의 축 범위를 읽는다. PD-M0은 부르지 않는다 — PD-M3의 터치패드
/// 디코더가 쓴다. 번호만 여기 두고 `pointer_test`가 본다.
pub fn eviocgabs(comptime abs: u16) c_ulong {
    return @intCast(c.EVIOCGABS(abs));
}

/// 커널 uevent 하나에서 새로 생긴 evdev 노드의 이름(`event3`)을 꺼낸다.
/// 아니면 null이다.
///
/// uevent는 NUL로 나뉜 필드들이다 — 머리 `add@/devices/…/event3` 뒤에
/// `ACTION=add` · `SUBSYSTEM=input` · `DEVNAME=input/event3` 같은 `KEY=value`가
/// 온다(PD-M0 plan 확정 7에서 본 글자). 셋이 다 맞는 것만 고른다. 같은 장치가
/// `input/inputN`(노드 없음) · `hidraw` · `usb` uevent도 함께 내고, `mouseN`은
/// `INPUT_MOUSEDEV`가 꺼져 있어 안 온다. 머리는 `=`가 없어 어느 조건에도 안
/// 걸린다.
///
/// 돌려주는 조각은 `msg` 안을 가리킨다. 부르는 쪽이 경로로 복사한다.
pub fn ueventAddedNode(msg: []const u8) ?[]const u8 {
    var added = false;
    var input = false;
    var node: ?[]const u8 = null;
    var it = std.mem.splitScalar(u8, msg, 0);
    while (it.next()) |field| {
        if (std.mem.eql(u8, field, "ACTION=add")) {
            added = true;
        } else if (std.mem.eql(u8, field, "SUBSYSTEM=input")) {
            input = true;
        } else if (std.mem.startsWith(u8, field, "DEVNAME=input/event")) {
            node = field["DEVNAME=input/".len..];
        }
    }
    if (!added or !input) return null;
    return node;
}

/// 버튼 셋. 비트 순서가 QEMU HMP `mouse_button`의 비트(1 왼쪽 · 2 오른쪽 ·
/// 4 가운데)와 같다 — `pointer> at`의 `buttons=`가 그 수로 찍힌다.
pub const Buttons = packed struct(u3) {
    left: bool = false,
    right: bool = false,
    middle: bool = false,

    pub fn bits(self: Buttons) u3 {
        return @bitCast(self);
    }
};

/// 디코더의 출력(PD design 결정 3). 마우스든 터치패드든 이 모양이다.
///
/// `buttons`는 변화가 아니라 그 순간의 상태다. 눌림과 뗌의 전이는
/// `Pointer.apply`가 장치 전체를 합친 뒤에 낸다.
pub const Frame = struct {
    dx: i32 = 0,
    dy: i32 = 0,
    /// `REL_WHEEL`의 눈금. 양수가 휠을 앞으로 민 것이다.
    wheel: i32 = 0,
    buttons: Buttons = .{},
};

/// 마우스 하나의 raw `input_event`를 `Frame`으로 묶는다.
///
/// `SYN_REPORT`를 만나야 `Frame`을 낸다. 그 사이의 이동과 휠은 더해 둔다 —
/// QEMU는 127을 넘는 이동을 보고 여럿으로 쪼개 보내고(PD-M0 plan 확정 2),
/// 커널은 보고 하나를 여러 이벤트로 낸다.
pub const Mouse = struct {
    /// 다음 `SYN_REPORT`까지 모으는 이동과 휠.
    pending: Frame = .{},
    /// 지금 눌린 버튼. 보고를 넘어 유지된다 — 버튼 이벤트는 바뀔 때만 온다.
    held: Buttons = .{},
    /// `SYN_DROPPED`를 받았다. 다음 `SYN_REPORT`까지 버린다(TF 결정 6).
    dropping: bool = false,

    pub fn feed(self: *Mouse, ev_type: u16, code: u16, value: i32) ?Frame {
        if (ev_type == c.EV_SYN) {
            if (code == c.SYN_DROPPED) {
                self.dropping = true;
                self.pending = .{};
                return null;
            }
            if (code != c.SYN_REPORT) return null;
            if (self.dropping) {
                // 버린 구간에 버튼 이벤트가 있었으면 `held`가 낡았다. 마우스는
                // 다음 누름이 그것을 고친다(design 결정 3).
                self.dropping = false;
                self.pending = .{};
                return null;
            }
            var frame = self.pending;
            frame.buttons = self.held;
            self.pending = .{};
            return frame;
        }
        if (self.dropping) return null;
        switch (ev_type) {
            c.EV_REL => switch (code) {
                c.REL_X => self.pending.dx +|= value,
                c.REL_Y => self.pending.dy +|= value,
                c.REL_WHEEL => self.pending.wheel +|= value,
                // `REL_WHEEL_HI_RES`는 버린다. 커널이 120마다 `REL_WHEEL`도
                // 내므로 둘 다 세면 두 번 움직인다(design 결정 7). 가로 휠도
                // 버린다 — 쓰는 자리가 없다.
                else => {},
            },
            c.EV_KEY => switch (code) {
                c.BTN_LEFT => self.held.left = value != 0,
                c.BTN_RIGHT => self.held.right = value != 0,
                c.BTN_MIDDLE => self.held.middle = value != 0,
                // `KEY_*`와 나머지 버튼(BTN_SIDE · BTN_EXTRA 등)은 버린다.
                // 키보드와 마우스를 한 노드로 내는 장치에서 키는 키보드
                // 경로가 읽는다(design 결정 2).
                else => {},
            },
            // `EV_MSC`(`MSC_SCAN`, design 실측 2)와 그 밖은 버린다.
            else => {},
        }
        return null;
    }
};

/// 한 `Frame`을 적용한 결과. 눌림과 뗌은 장치 전체의 합이 바뀔 때만 나온다.
pub const Events = struct {
    pressed: Buttons = .{},
    released: Buttons = .{},
    moved: bool = false,
    wheel: i32 = 0,
};

/// 화면에 하나인 포인터(PD design "모델" 절). 좌표는 프레임버퍼 픽셀이고
/// `0..w-1` · `0..h-1` 안에 머문다. 출발은 가운데다(design 결정 4).
pub const Pointer = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    /// 장치 칸마다 지금 눌린 버튼. 칸 번호는 `main.zig`의 장치 칸 번호다.
    dev_buttons: [MAX_DEVICES]Buttons = @splat(.{}),
    /// 위의 합(OR).
    buttons: Buttons = .{},

    pub fn init(w: u32, h: u32) Pointer {
        return .{ .x = w / 2, .y = h / 2, .w = w, .h = h };
    }

    pub fn apply(self: *Pointer, dev: u3, f: Frame) Events {
        self.x = clampAdd(self.x, f.dx, self.w);
        self.y = clampAdd(self.y, f.dy, self.h);
        self.dev_buttons[dev] = f.buttons;
        var ev = self.merge();
        ev.moved = f.dx != 0 or f.dy != 0;
        ev.wheel = f.wheel;
        return ev;
    }

    /// 장치가 빠졌다. 누른 채 뽑힌 버튼이 영영 눌린 채로 남지 않게 그 칸을
    /// 비운다. 합이 바뀌면 뗌이 나온다.
    pub fn forget(self: *Pointer, dev: u3) Events {
        self.dev_buttons[dev] = .{};
        return self.merge();
    }

    fn merge(self: *Pointer) Events {
        var sum: u3 = 0;
        for (self.dev_buttons) |b| sum |= b.bits();
        const before = self.buttons.bits();
        self.buttons = @bitCast(sum);
        return .{
            .pressed = @bitCast(sum & ~before),
            .released = @bitCast(before & ~sum),
        };
    }
};

/// `pos + delta`를 `0..limit-1` 안에 둔다. 넘침 없이 `i64`로 셈한다.
fn clampAdd(pos: u32, delta: i32, limit: u32) u32 {
    if (limit == 0) return 0;
    const next = @as(i64, pos) + delta;
    if (next < 0) return 0;
    if (next >= limit) return limit - 1;
    return @intCast(next);
}
