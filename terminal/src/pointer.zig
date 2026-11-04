//! 포인터 장치(마우스 · 터치패드)의 순수한 층(PD design 결정 2 · 3).
//!
//! 시스템 콜이 없다. `vt.zig` · `layout.zig`도 import하지 않는다. 장치를 찾고
//! 열고 읽는 것은 `main.zig`이고, 이 파일은 그 바이트를 받아 판단만 한다 —
//! 그래서 `pointer_test`가 부팅 없이 같은 판단을 본다.
//!
//! 층은 넷이다. `classify`(이 장치를 열 것인가) → `Mouse`(raw `input_event`를
//! `SYN_REPORT` 단위의 `Frame`으로) → `Pointer`(화면에 하나인 좌표와 버튼) →
//! `Gesture`(누름 · 끎 · 뗌 · 휠을 의도로, PD-M2). 자식이 마우스를 원하면
//! `Grab`이 그 누름을 자식의 것으로 정하고 `Gesture`를 건너뛴다(PD-M4).
const std = @import("std");
const screen_args = @import("screen_args");

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

/// 포인터 설정의 값 둘(PS design 결정 1 · 3). 이름과 글자는 init과 함께 컴파일하는
/// `shared/screen_args.zig`에 있다.
pub const WheelDirection = screen_args.WheelDirection;
pub const Accel = screen_args.Accel;

/// argv로 온 포인터 설정 넷(PS-M0 plan 확정 6). 장치를 여는 자리(`takePointer`)까지 이
/// 구조체 하나로 나른다. 장치를 열 때 그 장치의 종류로 반쪽을 고른다.
pub const Prefs = struct {
    mouse_scroll: WheelDirection = screen_args.default_mouse_scroll,
    touchpad_scroll: WheelDirection = screen_args.default_touchpad_scroll,
    mouse_accel: Accel = screen_args.default_mouse_accel,
    touchpad_accel: Accel = screen_args.default_touchpad_accel,

    /// 그 종류의 가속 단계. `none`은 열리지 않으므로 0이다.
    pub fn accelFor(self: Prefs, kind: Kind) Accel {
        return switch (kind) {
            .mouse => self.mouse_accel,
            .touchpad => self.touchpad_accel,
            .none => .{},
        };
    }

    /// 그 종류의 휠 방향 — `open` 줄에 찍는다(PS design 결정 7). `none`은 열리지 않는다.
    pub fn scrollFor(self: Prefs, kind: Kind) WheelDirection {
        return switch (kind) {
            .mouse => self.mouse_scroll,
            .touchpad => self.touchpad_scroll,
            .none => .normal,
        };
    }
};

/// 이 장치의 `Frame.wheel`에 곱할 부호(PS design 결정 2).
///
/// 두 디코더의 휠은 같은 부호 규약으로 나온다 — 양수가 "위의 글을 보이게 한다"이다.
/// 마우스는 `REL_WHEEL` 양수(휠을 앞으로 밂)가 그렇고(PD 결정 7), 터치패드는 두 손가락을
/// 아래로 밀면 그렇다(PD 결정 8, 내용이 손가락을 따라간다). 그래서 +1이 PS 전의 동작이고,
/// 마우스는 `natural`일 때, 터치패드는 `normal`일 때 뒤집는다. 디코더는 안 바뀐다.
/// `none`은 열리지 않는 장치라 쓰이지 않는다 — 1을 준다.
pub fn wheelSign(kind: Kind, mouse: WheelDirection, touchpad: WheelDirection) i32 {
    return switch (kind) {
        .mouse => if (mouse == .natural) -1 else 1,
        .touchpad => if (touchpad == .normal) -1 else 1,
        .none => 1,
    };
}

/// 가속 곡선의 출발값 넷(PS design 결정 3). 재지 않은 제안이다 — 실기에서 사람이 손으로
/// 본 뒤 고친다(design 위험 2). 고치면 `pointer_test`의 곡선 검사도 함께 고친다.
/// 속도의 단위 `MPX`는 1/1000 픽셀 / ms다.
pub const ACCEL_V_LOW_MPX: i64 = 300; // 0.3 px/ms — 이보다 느리면 배율 1
pub const ACCEL_V_HIGH_MPX: i64 = 3000; // 3.0 px/ms — 이보다 빠르면 배율 상한
pub const ACCEL_GAIN_MAX: i64 = 4; // 단계 10의 상한. 단계 5면 2.5
pub const ACCEL_IDLE_US: i64 = 100_000; // 직전 이동과 이보다 멀면 간격을 모르는 것으로 한다

/// 장치 하나의 가속 상태(PS design 결정 3 · 4, PS-M1 plan 확정 1~6). 칸마다 하나라 두 장치를
/// 함께 움직여도 서로의 속도가 섞이지 않는다.
///
/// 입력은 `Frame`의 이동과 그 `SYN_REPORT`의 시각, 출력은 배율을 곱한 이동이다. 배율은
/// 직전 이동 보고와의 간격으로 잰 속도에서 나온다.
///
///   t    = clamp((v − V_LOW) / (V_HIGH − V_LOW), 0, 1)
///   gain = 1 + (level / 10) × (GAIN_MAX − 1) × t
///
/// 셈은 1/1000 고정소수점이고 곱하고 남은 끝수는 축마다 다음 보고에 넘긴다(`touchpad.scale`과
/// 같은 이유 — 느린 이동이 반올림으로 사라지지 않게). 휠은 이 구조체를 안 지난다(결정 4).
pub const Ballistics = struct {
    /// 0~10. 0이면 `apply`가 입력을 그대로 돌려준다.
    level: u4,
    /// 직전 이동 보고(dx나 dy가 0이 아닌)의 시각(µs). 아직 없으면 null.
    last_us: ?i64 = null,
    /// 배율을 곱하고 남은 1/1000 픽셀.
    rem_x: i64 = 0,
    rem_y: i64 = 0,

    pub fn init(a: Accel) Ballistics {
        return .{ .level = a.level };
    }

    pub fn apply(self: *Ballistics, dx: i32, dy: i32, t_us: i64) [2]i32 {
        // 단계 0은 PS 전의 동작과 비트 단위로 같다(결정 3) — 셈의 우연이 아니라 갈래로 지킨다.
        if (self.level == 0) return .{ dx, dy };
        // 이동 없는 보고(버튼 · 휠 · 터치패드의 닿음과 뗌)는 속도의 기준을 안 바꾼다.
        if (dx == 0 and dy == 0) return .{ dx, dy };

        var gain_m: i64 = 1000;
        if (self.last_us) |last| {
            const dt = t_us - last;
            if (dt > 0 and dt <= ACCEL_IDLE_US) {
                // 속도만 재는 값은 ±2^15에서 자른다 — 제곱의 합 × 10^6이 u64 안에 든다.
                const sx: u64 = @abs(std.math.clamp(dx, -32768, 32768));
                const sy: u64 = @abs(std.math.clamp(dy, -32768, 32768));
                const dist_m: i64 = @intCast(std.math.sqrt((sx * sx + sy * sy) * 1_000_000));
                const v_m = @divTrunc(dist_m * 1000, dt);
                const t_m = std.math.clamp(@divTrunc((v_m - ACCEL_V_LOW_MPX) * 1000, ACCEL_V_HIGH_MPX - ACCEL_V_LOW_MPX), 0, 1000);
                gain_m = 1000 + @divTrunc(@as(i64, self.level) * (ACCEL_GAIN_MAX - 1) * t_m, 10);
            }
        }
        self.last_us = t_us;
        return .{ mulGain(dx, gain_m, &self.rem_x), mulGain(dy, gain_m, &self.rem_y) };
    }
};

/// `d`에 `gain_m / 1000`을 곱한다. 나머지는 `rem`에 남겨 다음에 더한다.
fn mulGain(d: i32, gain_m: i64, rem: *i64) i32 {
    const t = @as(i64, d) * gain_m + rem.*;
    const q = @divTrunc(t, 1000);
    rem.* = t - q * 1000;
    return @intCast(std.math.clamp(q, std.math.minInt(i32), std.math.maxInt(i32)));
}

/// 이 장치를 키보드로 열 것인가(KH design 결정 2). `EV_KEY`가 있고 `KEY_ESC`(1)부터
/// `KEY_D`(32)까지 서른두 키가 다 있다.
///
/// init의 `devices.looksLikeKeyboard`와 기준이 같다. 같은 기계에서 init이 "키보드"라고
/// 부르는 것과 terminal이 여는 것이 달라지면 로그를 읽는 사람이 헷갈린다. 함수를 하나로
/// 합치지 않는 이유는 비트맵의 모양이다 — 그쪽은 sysfs의 "높은 워드가 앞" 문자열이고
/// 이쪽은 ioctl의 바이트 배열이다(`bitSet`의 주석).
///
/// 전원 버튼 · `Video Bus` · 마우스 · 미디어 키 노드(`Consumer Control`)는 글자 키가
/// 없어 아니다(KH-M0 실측 5). `classify`와 따로 묻는다 — 한 노드가 키보드이자
/// 포인터일 수 있다(결정 2).
pub fn looksLikeKeyboard(caps: *const Caps) bool {
    if (!bitSet(&caps.ev, c.EV_KEY)) return false;
    var code: usize = c.KEY_ESC;
    while (code <= c.KEY_D) : (code += 1) {
        if (!bitSet(&caps.key, code)) return false;
    }
    return true;
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

/// 장치의 bus · vendor · product · version(`struct input_id`). 키보드의 종류를 고를 때
/// 쓴다(KK design 결정 2). 길이가 고정이라 인자가 없다.
pub fn eviocgid() c_ulong {
    return @intCast(c.EVIOCGID);
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

    /// 버튼 `b`가 서 있는가(PD-M4).
    pub fn has(self: Buttons, b: Button) bool {
        return switch (b) {
            .left => self.left,
            .right => self.right,
            .middle => self.middle,
        };
    }

    /// 버튼 `b` 하나를 세우거나 내린 값(PD-M4).
    pub fn with(self: Buttons, b: Button, down: bool) Buttons {
        var out = self;
        switch (b) {
            .left => out.left = down,
            .right => out.right = down,
            .middle => out.middle = down,
        }
        return out;
    }
};

/// 버튼 하나의 이름(PD-M4). 보고는 셋을 다 보낸다 — 우리 제스처는 왼쪽만 쓴다.
pub const Button = enum { left, right, middle };

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

// ── 화살표(PD-M1) ─────────────────────────────────────────────────────
//
// 화면에 그리는 쪽의 산수다. 대상은 `anytype` — `getPixel(x, y) u32`와
// `setPixel(x, y, color)`가 있는 것 — 이라 게스트에서는 `drm.Framebuffer`가,
// `pointer_test`에서는 `u32` 배열이 들어온다. `image.zig`와 같은 모양이다.

/// 화살표의 크기(PD design 결정 4). hotspot은 왼쪽 위 끝 (0, 0)이다.
pub const ARROW_W: u32 = 12;
pub const ARROW_H: u32 = 19;

/// 화살표 안쪽의 색(PD design 결정 4). 전용 색이다 — 게이트가 이 색과
/// `POINTER_EDGE`만 세어 "그 자리에 그렸는가"를 본다(CI 결정 3 · WP의
/// `SEPARATOR`와 같은 이유). 지금의 색 상수와 xterm 256색 팔레트에 없다.
pub const POINTER_FILL: u32 = 0x00FCFCF4;

/// 화살표 테두리 한 픽셀의 색. 밝은 글자 위에서도 화살표가 보이게 한다.
pub const POINTER_EDGE: u32 = 0x00040810;

/// 화살표 모양. `E`는 테두리, `F`는 안쪽, `.`은 그리지 않는 자리다. 줄이
/// y, 글자가 x다. 고전적인 12 × 19 화살표를 그대로 옮겼다.
const ARROW = [ARROW_H]*const [ARROW_W]u8{
    "E...........",
    "EE..........",
    "EFE.........",
    "EFFE........",
    "EFFFE.......",
    "EFFFFE......",
    "EFFFFFE.....",
    "EFFFFFFE....",
    "EFFFFFFFE...",
    "EFFFFFFFFE..",
    "EFFFFFFFFFE.",
    "EFFFFFFEEEEE",
    "EFFFEFFE....",
    "EFFEEFFE....",
    "EFE..EFFE...",
    "EE...EFFE...",
    "E.....EFFE..",
    "......EFFE..",
    ".......EE...",
};

/// 화살표가 다 보일 때의 `ink`(테두리 49 + 안쪽 69). `pointer> at` 줄이 이
/// 수를 찍고 `pointer/check.sh`가 이 글자를 본다. `pointer_test`가 `ARROW`에서
/// 다시 세어 대조한다 — 모양을 고치면 이 수와 게이트를 함께 고친다.
pub const ARROW_INK: u32 = 118;

/// 화살표 안의 한 자리 `(dx, dy)`의 색. 그리지 않는 자리면 null이다.
pub fn arrowColor(dx: u32, dy: u32) ?u32 {
    return switch (ARROW[dy][dx]) {
        'E' => POINTER_EDGE,
        'F' => POINTER_FILL,
        else => null,
    };
}

/// 화살표의 자리. 대상의 픽셀 좌표이고 hotspot(왼쪽 위 끝)의 자리다.
pub const Spot = struct { x: u32, y: u32 };

/// 두 자리가 같은가. 둘 다 null이면 같다.
pub fn sameSpot(a: ?Spot, b: ?Spot) bool {
    const p = a orelse return b == null;
    const q = b orelse return false;
    return p.x == q.x and p.y == q.y;
}

/// 화면의 화살표 하나와 그 밑의 픽셀(save-under, PD design 결정 4).
///
/// 움직임만 있는 회차는 화면 전체를 다시 그리지 않는다. 저장해 둔 픽셀을
/// 되돌리고(`restore`), 새 자리 밑을 저장하고 그린다(`show`). 셀이 바뀐
/// 회차는 화면 전체를 다시 칠하므로 저장한 픽셀이 낡는다 — 그때는 되돌리지
/// 않고 잊는다(`forget`). 되돌리면 새 프레임 위에 지난 프레임의 조각을 붙인다.
///
/// 화살표가 덮는 픽셀(`arrowColor`가 null이 아닌 자리)만 저장하고 되돌린다.
/// 나머지는 화살표가 안 건드리므로 그대로다. 실기의 프레임버퍼는 캐시가 없는
/// 메모리라 되읽기가 비싸다(design 결정 10) — 읽는 수를 줄인다.
///
/// 대상의 가장자리에서 화살표가 잘린다. `drm.Framebuffer.setPixel`에 범위
/// 검사가 없으므로 이 자르기가 곧 프레임버퍼 밖 쓰기를 막는 자리다.
pub const Sprite = struct {
    /// 대상의 크기. 자르기에 쓴다.
    w: u32,
    h: u32,
    /// 지금 화살표가 그려진 자리. null이면 화면에 화살표가 없다.
    at: ?Spot = null,
    /// `at`에 그리기 전에 저장한 픽셀. `[dy * ARROW_W + dx]`다.
    saved: [ARROW_H * ARROW_W]u32 = @splat(0),

    pub fn init(w: u32, h: u32) Sprite {
        return .{ .w = w, .h = h };
    }

    /// `s`에서 대상 안에 남는 폭과 높이. 대상 밖이면 0이다.
    fn span(self: *const Sprite, s: Spot) struct { w: u32, h: u32 } {
        return .{
            .w = if (s.x >= self.w) 0 else @min(ARROW_W, self.w - s.x),
            .h = if (s.y >= self.h) 0 else @min(ARROW_H, self.h - s.y),
        };
    }

    /// `s`에 화살표를 그린다. 그리기 전에 그 밑을 저장한다. 이미 그려진
    /// 화살표가 있으면 먼저 `restore`나 `forget`을 불러야 한다 — 이 함수는
    /// 옛 자리를 모른다.
    pub fn show(self: *Sprite, target: anytype, s: Spot) void {
        const sp = self.span(s);
        var dy: u32 = 0;
        while (dy < sp.h) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < sp.w) : (dx += 1) {
                const color = arrowColor(dx, dy) orelse continue;
                self.saved[dy * ARROW_W + dx] = target.getPixel(s.x + dx, s.y + dy);
                target.setPixel(s.x + dx, s.y + dy, color);
            }
        }
        self.at = s;
    }

    /// 저장한 픽셀을 되돌린다. 화살표가 없으면 아무 일도 안 한다.
    pub fn restore(self: *Sprite, target: anytype) void {
        const s = self.at orelse return;
        const sp = self.span(s);
        var dy: u32 = 0;
        while (dy < sp.h) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < sp.w) : (dx += 1) {
                if (arrowColor(dx, dy) == null) continue;
                target.setPixel(s.x + dx, s.y + dy, self.saved[dy * ARROW_W + dx]);
            }
        }
        self.at = null;
    }

    /// 화면 전체가 새로 칠해졌다. 화살표는 이미 지워졌고 저장한 픽셀은 낡았다.
    pub fn forget(self: *Sprite) void {
        self.at = null;
    }

    /// 두 사각형(직전 자리 `before`와 지금 자리 `at`, 각 12 × 19) 안에서
    /// `POINTER_FILL` · `POINTER_EDGE` 픽셀을 센다(PD design 결정 10).
    ///
    /// 화살표가 다 보이면 `ARROW_INK`이고, 숨었으면 0이고, 가장자리에서
    /// 잘리면 그 사이다. 옛 자리를 못 지웠으면 `ARROW_INK`보다 크다 — 자국은
    /// 되돌리지 못한 옛 자리에 남으므로 이 두 사각형 안에서 잡힌다. 두
    /// 사각형이 겹치면 겹친 픽셀은 한 번만 센다.
    ///
    /// 화면 전체를 세지 않는 이유는 이 수가 움직임 회차마다 찍히기 때문이다.
    pub fn ink(self: *const Sprite, target: anytype, before: ?Spot) u32 {
        var n: u32 = 0;
        if (before) |b| n += self.countRect(target, b, null);
        if (self.at) |a| n += self.countRect(target, a, before);
        return n;
    }

    /// 사각형 `s` 안의 화살표 색 픽셀 수. `skip` 사각형 안의 픽셀은 안 센다.
    fn countRect(self: *const Sprite, target: anytype, s: Spot, skip: ?Spot) u32 {
        const sp = self.span(s);
        var n: u32 = 0;
        var dy: u32 = 0;
        while (dy < sp.h) : (dy += 1) {
            var dx: u32 = 0;
            while (dx < sp.w) : (dx += 1) {
                const x = s.x + dx;
                const y = s.y + dy;
                if (skip) |k| {
                    if (x >= k.x and x < k.x + ARROW_W and y >= k.y and y < k.y + ARROW_H) continue;
                }
                const p = target.getPixel(x, y) & 0x00FFFFFF;
                if (p == POINTER_FILL or p == POINTER_EDGE) n += 1;
            }
        }
        return n;
    }
};

// ── 제스처(PD-M2) ─────────────────────────────────────────────────────
//
// 누름 · 끎 · 뗌 · 휠을 "포커스 옮김 · 선택 시작 · 선택 늘림 · 복사 · 스크롤"
// 의도로 바꾼다(PD design 결정 3 · 6). 판단만 한다 — 패널도 화면도 모른다.
// 의도를 실행하는 것은 `main.zig`이고, 그 실행이 바꾼 것(포커스가 옮겨졌다,
// 키보드가 copy mode를 닫았다)은 `main.zig`가 다음 단계에 `Target`으로
// 알려 준다.

/// 패널 안의 칸 하나. `layout.Hit`과 같은 모양이다 — 이 파일은 `layout.zig`를
/// import하지 않으므로(머리 주석) `main.zig`가 옮겨 담는다. `col` · `row`는
/// 그 잎의 사각형 안의 상대 칸이고 `vt.Screen`이 아는 뷰포트 좌표다.
pub const Cell = struct { leaf: u4, col: u16, row: u16 };

/// 누른 패널이 지금 어떤 상태인가. `main.zig`가 단계마다 알려 준다.
pub const Target = enum {
    /// 누른 패널이 더는 포커스가 아니다. 누른 뒤 키보드가 포커스나
    /// 워크스페이스를 옮겼거나, 그 패널이 닫혔다.
    gone,
    /// 포커스이고 copy mode가 아니다.
    normal,
    /// 포커스이고 copy mode다.
    copy,
};

/// 다시 누름으로 치는 간격(µs)과 첫 누름에서의 거리(픽셀, MC design 결정 3).
/// 500ms는 ghostty의 기본값이고 macOS 기본과 같다. 거리는 한 칸 너비다 — 칸이
/// 아니라 픽셀로 재는 것은 칸 경계 위의 한 픽셀 떨림에 칸이 바뀌기 때문이다.
/// `MULTI_CLICK_PX`는 `main.zig`의 `CELL_W`와 같아야 한다(거기 comptime 단언).
pub const MULTI_CLICK_US: i64 = 500_000;
pub const MULTI_CLICK_PX: u32 = 8;

/// 선택의 단위(MC design 결정 6). 한 번 누름은 문자, 두 번은 단어, 세 번은
/// 줄이다. `vt.Screen.SelectKind`와 짝이고 `main.zig`가 옮겨 담는다 — 이
/// 파일은 `vt.zig`를 import하지 않는다(머리 주석).
pub const Unit = enum { char, word, line };

/// copy mode에 들어가며 선택을 시작할 칸과 그 단위.
pub const Start = struct { at: Cell, unit: Unit };

/// Shift 누름이 늘릴 칸과 단위. `unit`이 null이면 늘리기 연속의 첫 누름이다 —
/// 남은 선택의 방식으로 가까운 끝을 옮긴다(SE design 결정 4). 반복이면 둘째가
/// word, 셋째부터 line이고 첫 누름이 정한 앵커를 둔 채 단위만 바꾼다(ER design
/// 결정 2 · 4).
pub const Extend = struct { at: Cell, unit: ?Unit = null };

/// 누름 하나의 사실(MC design 결정 2 · 3, SE design 결정 5). `t_us`는 커널이
/// 이벤트에 찍은 단조 시각이고, null이면 이 누름은 반복이 될 수 없다(라이브러리
/// `pressRepeat`와 같다). `x` · `y`는 프레임버퍼 픽셀, `ws`는 워크스페이스 번호다.
/// `extend`는 "Shift가 눌렸고 누른 패널에 남은 선택이 있다"다 — 둘을 합친 bool로
/// 받는 이유는 이 파일이 `input.zig`도 `vt.zig`도 import하지 않기 때문이다(머리 주석).
pub const Stamp = struct { t_us: ?i64, x: u32, y: u32, ws: usize, extend: bool = false };

/// 끄는 중의 휠(design 결정 7). 누른 패널을 `notches` 눈금만큼 움직인다.
/// 양수가 휠을 앞으로 민 것이고 위로 간다 — `Frame.wheel`과 같다.
pub const Scroll = struct { leaf: u4, notches: i32 };

/// `Gesture`가 내는 의도. `main.zig`의 switch가 `else` 없이 닫는다 —
/// variant를 하나 더하면 컴파일러가 배선할 자리를 알려 준다(design 결정 3).
pub const Intent = union(enum) {
    /// 키보드 쪽 모드를 끝낸다. 조합 중인 한글을 확정하거나 버리고, 지금
    /// 포커스 패널의 copy mode와 검색 프롬프트를 복사 없이 닫는다.
    cancel,
    /// 포커스를 이 잎으로 옮긴다.
    focus: u4,
    /// copy mode에 들어가며 이 칸에서 선택을 시작한다. 단위는 누른 횟수가
    /// 정한다(MC design 결정 4) — 끌기의 첫 이동은 언제나 문자다.
    select_start: Start,
    /// 선택 끝을 이 칸으로 옮긴다. 칸이 같아도 다시 맞춘다 — 휠이 뷰포트를
    /// 밀었으면 같은 칸이 다른 글자다.
    select_to: Cell,
    /// 누른 패널을 휠 눈금만큼 움직인다.
    scroll: Scroll,
    /// 이 잎의 선택을 클립보드에 넣고 copy mode를 나간다(`Cmd+C`와 같다).
    copy: u4,
    /// 남은 선택(뗀 뒤 화면에 남은 반전, SE design 결정 1)을 지운다 — 지금
    /// 워크스페이스의 패널 전부에서(SE design 결정 2). 늘리기가 아닌 누름이 낸다.
    deselect,
    /// 남은 선택을 이 칸까지 늘리며 copy mode에 들어간다 — 첫 누름은 가까운
    /// 끝을 옮기고(SE design 결정 4), 반복은 단위를 바꾼다(ER design 결정 2).
    /// 그 뒤의 끌기는 `select_to`, 뗌은 `copy`로 끌기와 같다.
    select_extend: Extend,
};

/// 한 단계가 내는 의도들. 셋을 넘지 않는다 — 누름이 `cancel` · `deselect` ·
/// `focus`(두 번째 · 세 번째 누름은 `cancel` · `focus` · `select_start`, 늘리기는
/// `cancel` · `focus` · `select_extend`), 첫 이동이 `select_start` · `select_to`,
/// 누른 채 첫 휠이 `select_start` · `scroll` · `select_to`다. 순서대로 실행한다.
pub const Intents = struct {
    buf: [3]Intent = undefined,
    len: usize = 0,

    fn push(self: *Intents, it: Intent) void {
        self.buf[self.len] = it;
        self.len += 1;
    }

    pub fn items(self: *const Intents) []const Intent {
        return self.buf[0..self.len];
    }
};

/// 왼쪽 버튼 하나의 누름 · 끎 · 뗌(PD design 결정 6).
///
/// | phase | 뜻 |
/// |---|---|
/// | `idle` | 버튼이 안 눌렸다 |
/// | `pressed` | 패널 칸 위에서 눌렀고 아직 다른 칸에 안 닿았다. copy mode에 아직 안 들어갔다 |
/// | `dragging` | 다른 칸에 닿아 선택 중이다 |
/// | `ignored` | 뗄 때까지 아무것도 안 한다 — 여백 · 구분선을 눌렀거나, 키보드가 모드를 닫았거나, 누른 패널이 포커스를 잃었다 |
///
/// copy mode에 누름이 아니라 첫 칸 이동에 들어가는 이유는 클릭이다(design
/// 결정 6). 누름에 들어가면 모든 클릭이 한 프레임 동안 `COPY`를 띄우고,
/// 떼는 순간 앵커와 끝이 같은 한 칸 선택이 남는다.
///
/// 누른 잎을 기억하는 것이 가장자리 처리의 절반이다(design 결정 5). 선택
/// 끝의 잎은 언제나 누른 잎이다 — `motion`이 받은 칸의 잎은 안 본다.
/// 나머지 절반(끄는 칸을 누른 패널의 사각형으로 자르는 것)은 사각형을
/// 아는 `main.zig`가 한다.
pub const Gesture = struct {
    phase: Phase = .idle,
    /// 누른 칸. `phase`가 `pressed` · `dragging`일 때만 뜻이 있다.
    start: Cell = .{ .leaf = 0, .col = 0, .row = 0 },
    /// 마지막으로 선택 끝을 맞춘 칸. `pressed`에서는 `start`와 같다.
    cur: Cell = .{ .leaf = 0, .col = 0, .row = 0 },
    /// 이 연속의 기억(MC design 결정 3). null이면 다음 누름은 처음부터다.
    last: ?Last = null,
    /// 마지막 누름이 이 연속의 몇 번째였나(1~3). 패널 칸이 아닌 누름은 0이다.
    /// `main.zig`가 `repeat` 줄에 찍는다.
    clicks: u2 = 0,
    /// 마지막 누름과 그 앞 누름의 시각 차(µs). `clicks`가 2 이상일 때만 뜻이 있다.
    gap_us: i64 = 0,

    pub const Phase = enum { idle, pressed, dragging, ignored };

    /// 반복을 견줄 지난 누름. `x0` · `y0`은 이 연속의 첫 누름 자리이고
    /// (거리는 첫 누름에서 잰다 — 라이브러리와 같다), `t_us`는 가장 최근
    /// 누름의 시각이다(간격은 앞 누름과 잰다). `extend`는 이 연속의 첫 누름이
    /// 늘리기였나다 — 반복의 뜻을 그것이 정한다(ER design 결정 2).
    const Last = struct { t_us: i64, x0: u32, y0: u32, leaf: u4, ws: usize, count: u2, extend: bool };

    /// 이 누름이 지난 누름의 반복인가(MC design 결정 3의 넷).
    fn repeats(self: *const Gesture, at: Stamp, leaf: u4) bool {
        const l = self.last orelse return false;
        const t = at.t_us orelse return false;
        const dt = t - l.t_us;
        if (dt < 0 or dt > MULTI_CLICK_US) return false;
        const dx = @as(i64, at.x) - @as(i64, l.x0);
        const dy = @as(i64, at.y) - @as(i64, l.y0);
        const max = @as(i64, MULTI_CLICK_PX);
        if (dx * dx + dy * dy > max * max) return false;
        return leaf == l.leaf and at.ws == l.ws;
    }

    /// 연속을 끊는다. 다음 누름은 처음부터다.
    fn breakRun(self: *Gesture) void {
        self.last = null;
    }

    /// 누른 잎. 버튼이 패널 칸 위에서 눌린 채이면 그 잎이고, 아니면 null이다.
    /// `main.zig`가 끄는 칸을 자를 사각형과 `Target`을 이것으로 고른다.
    pub fn held(self: *const Gesture) ?u4 {
        return switch (self.phase) {
            .pressed, .dragging => self.start.leaf,
            .idle, .ignored => null,
        };
    }

    /// 왼쪽 버튼이 눌렸다. `hit`은 누른 자리의 칸이고 여백 · 구분선 ·
    /// 상태 줄이면 null이다. `focus`는 지금 포커스 잎이다.
    ///
    /// 패널 칸이면 언제나 `cancel`을 낸다 — 그 패널이 키보드 copy mode였으면
    /// 닫히고(선택의 주인은 한 번에 하나다), 다른 패널이면 옛 포커스 패널의
    /// copy mode가 닫힌다. 키보드 copy mode는 포커스 패널에만 있다(copy 표가
    /// `Cmd+]`를 삼킨다). 그리고 다른 패널이면 `focus`를 낸다. 순서가
    /// 계약이다 — 조합 중인 한글은 옛 포커스의 PTY로 가야 한다(WP 결정 4).
    ///
    /// `at`이 지난 누름의 반복이면(MC design 결정 3) 두 번째는 단어, 세 번째부터는
    /// 줄을 곧바로 고른다 — `select_start`를 내고 `dragging`으로 간다. 그래서
    /// 뗌은 끌기와 같은 길로 복사한다(MC design 결정 5).
    ///
    /// 반복이 아니고 `at.extend`면 늘리기다(SE design 결정 3) — `select_extend`를
    /// 내고 `dragging`으로 간다. 반복이 늘리기보다 먼저인 것은 ghostty와 같다.
    /// 늘리기 누름도 연속을 기억하고, 그 연속의 반복은 단어 · 줄 단위
    /// 늘리기다(ER design 결정 1 · 2) — 반복 누름의 Shift는 안 본다. 연속이
    /// 무엇인지는 첫 누름이 정한다. 그 밖의 누름(여백 포함)은 `deselect`를 더 낸다 — 남은
    /// 선택은 다음 누름이 지운다(SE design 결정 2). 반복 누름은 안 낸다 — 그
    /// 연속의 첫 누름이 이미 지웠고, 버퍼 셋이 `cancel` · `focus` ·
    /// `select_start`로 찬다.
    pub fn press(self: *Gesture, hit: ?Cell, focus: u4, at: Stamp) Intents {
        var out: Intents = .{};
        const h = hit orelse {
            self.phase = .ignored;
            self.clicks = 0;
            self.breakRun();
            out.push(.deselect);
            return out;
        };
        const repeat = self.repeats(at, h.leaf);
        if (repeat) {
            const l = &self.last.?;
            self.gap_us = at.t_us.? - l.t_us;
            l.t_us = at.t_us.?;
            // 3에서 멈춘다(넷째도 줄, 라이브러리와 같다). `u2`라 3 + 1을 먼저
            // 셈하면 넘친다 — 비교가 먼저다.
            if (l.count < 3) l.count += 1;
            self.clicks = l.count;
        } else {
            self.gap_us = 0;
            self.clicks = 1;
            self.last = null;
            if (at.t_us) |t| {
                self.last = .{ .t_us = t, .x0 = at.x, .y0 = at.y, .leaf = h.leaf, .ws = at.ws, .count = 1, .extend = at.extend };
            }
        }
        self.start = h;
        self.cur = h;
        out.push(.cancel);
        if (!repeat and !at.extend) out.push(.deselect);
        if (h.leaf != focus) out.push(.{ .focus = h.leaf });
        if (repeat) {
            self.phase = .dragging;
            const unit: Unit = if (self.clicks == 2) .word else .line;
            if (self.last.?.extend) {
                out.push(.{ .select_extend = .{ .at = h, .unit = unit } });
            } else {
                out.push(.{ .select_start = .{ .at = h, .unit = unit } });
            }
        } else if (at.extend) {
            self.phase = .dragging;
            out.push(.{ .select_extend = .{ .at = h } });
        } else {
            self.phase = .pressed;
        }
        return out;
    }

    /// 포인터가 움직였다. `cell`은 누른 패널의 사각형으로 이미 자른 칸이다
    /// (`target`이 `gone`이면 무엇이든 된다).
    pub fn motion(self: *Gesture, cell: Cell, target: Target) Intents {
        var out: Intents = .{};
        const at: Cell = .{ .leaf = self.start.leaf, .col = cell.col, .row = cell.row };
        switch (self.phase) {
            .idle, .ignored => {},
            .pressed => {
                if (target == .gone) {
                    self.phase = .ignored;
                    self.breakRun();
                } else if (!sameCell(at, self.start)) {
                    self.phase = .dragging;
                    self.breakRun();
                    out.push(.{ .select_start = .{ .at = self.start, .unit = .char } });
                    out.push(.{ .select_to = at });
                    self.cur = at;
                }
            },
            .dragging => {
                // 키보드가 모드를 닫았다(`Esc` · `y` · `Cmd+C`, design 결정 6의
                // 표). 뗄 때까지의 움직임은 무시한다.
                // 선택 끝이 누른 칸을 떠나면 연속을 끊는다(MC-M1 plan 확정 2) —
                // 두 번째 누름은 누름에서 이미 `dragging`이라 phase로는 못 가른다.
                if (target != .copy) {
                    self.phase = .ignored;
                    self.breakRun();
                } else if (!sameCell(at, self.cur)) {
                    self.breakRun();
                    out.push(.{ .select_to = at });
                    self.cur = at;
                }
            },
        }
        return out;
    }

    /// 왼쪽 버튼을 뗐다. 끈 뒤이고 copy mode가 살아 있으면 `copy`를 낸다.
    /// 안 끈 채(클릭)면 아무 일도 없다 — 클릭의 일은 누름이 이미 했다.
    pub fn release(self: *Gesture, target: Target) Intents {
        var out: Intents = .{};
        if (self.phase == .dragging and target == .copy) out.push(.{ .copy = self.start.leaf });
        self.phase = .idle;
        return out;
    }

    /// 이 누름은 자식의 것이다(PD-M4, design 결정 12). 누름처럼 `cancel` ·
    /// `deselect`와 (다른 패널이면) `focus`를 내고, 뗄 때까지 아무것도 안 한다 —
    /// 끎과 뗌은 자식에게 보고로 간다.
    ///
    /// 포커스를 먼저 옮기는 것은 tmux의 기본 바인딩(`select-pane` 뒤에
    /// `send-keys -M`)과 같다. 확정한 한글이 보고보다 먼저 PTY에 간다.
    pub fn handOff(self: *Gesture, leaf: u4, focus: u4) Intents {
        var out: Intents = .{};
        self.phase = .ignored;
        self.clicks = 0;
        self.breakRun();
        out.push(.cancel);
        out.push(.deselect);
        if (leaf != focus) out.push(.{ .focus = leaf });
        return out;
    }

    /// 휠을 굴렸다. 버튼이 패널 칸 위에서 눌린 채면 누른 패널을 움직이고
    /// 선택 끝을 다시 맞춘다(design 결정 7의 "끄는 중"). 한 화면보다 긴
    /// 선택을 만드는 길이다.
    ///
    /// null이면 이 휠은 제스처의 것이 아니다 — `main.zig`가 평소의 휠(포인터
    /// 아래 패널)로 다룬다.
    ///
    /// 아직 안 끌었으면(`pressed`) 여기서 선택을 시작한다. 시작이 스크롤보다
    /// 먼저인 것이 요점이다 — 앵커가 누른 글자에 붙은 뒤에 뷰포트가 움직여야
    /// 한다. 순서가 뒤집히면 누른 칸의 뷰포트 좌표가 다른 글자를 가리킨다.
    pub fn wheel(self: *Gesture, notches: i32, target: Target) ?Intents {
        var out: Intents = .{};
        switch (self.phase) {
            .idle, .ignored => return null,
            .pressed => {
                if (target == .gone) {
                    self.phase = .ignored;
                    self.breakRun();
                    return null;
                }
                self.phase = .dragging;
                out.push(.{ .select_start = .{ .at = self.start, .unit = .char } });
            },
            .dragging => {
                if (target != .copy) {
                    self.phase = .ignored;
                    self.breakRun();
                    return null;
                }
            },
        }
        self.breakRun();
        out.push(.{ .scroll = .{ .leaf = self.start.leaf, .notches = notches } });
        out.push(.{ .select_to = self.cur });
        return out;
    }
};

/// 두 칸이 같은가.
pub fn sameCell(a: Cell, b: Cell) bool {
    return a.leaf == b.leaf and a.col == b.col and a.row == b.row;
}

// ── 마우스 보고(PD-M4) ────────────────────────────────────────────────
//
// 자식이 마우스를 원하면(모드 9 · 1000 · 1002 · 1003) 누름 · 끎 · 뗌 · 휠을
// 우리 제스처 대신 그 자식에게 보낸다(PD design 결정 12). 여기는 "누구의
// 것인가"만 정한다. 바이트를 짜는 것은 `vt.Screen.mouseEncode`(ghostty의
// 인코더)이고, 쓰는 것은 `main.zig`다.

/// 누름의 주인.
pub const Owner = enum {
    /// 우리 것이다 — 왼쪽 버튼은 `Gesture`로 가고 휠은 스크롤백을 움직인다.
    ours,
    /// 자식의 것이다 — 그 패널의 PTY에 보고로 간다.
    child,
};

/// 포인터 아래 패널의 지금 상태. `main.zig`가 그 패널의 `vt.Screen`에서
/// 읽어 채운다 — 이 파일은 `vt.zig`를 import하지 않는다(머리 주석).
pub const Pane = struct {
    leaf: u4,
    /// 자식이 마우스 보고를 켰다(모드 9 · 1000 · 1002 · 1003 중 하나).
    wants: bool,
    /// 키보드 copy mode다.
    copy: bool,
    /// 휠을 화살표 키로 바꿀 자리다 — 대체 화면이고 모드 1007이 켜져 있다.
    alt_keys: bool,
};

/// 이 패널 위의 누름 · 움직임이 누구의 것인가(design 결정 12).
///
/// 자식이 원하고, 그 패널이 키보드 copy mode가 아니고, Shift가 안 눌렸으면
/// 자식의 것이다. 여백 · 구분선 · 상태 줄(null)은 언제나 우리 것이다 — 우리
/// 것이어도 거기서는 아무 일도 없다(design 결정 5).
///
/// Shift가 우리에게 돌려준다. xterm 이래의 관례이고 ghostty · kitty · tmux가
/// 같다. copy mode는 사람이 `Cmd+Shift+C`로 "우리 선택"을 고른 상태라 거기서의
/// 누름도 우리 것이다.
pub fn ownerOf(under: ?Pane, shift: bool) Owner {
    const p = under orelse return .ours;
    return if (p.wants and !p.copy and !shift) .child else .ours;
}

/// 버튼이 눌린 동안의 주인(design 결정 12). 버튼이 하나도 안 눌렸을 때의
/// 첫 누름이 주인과 패널을 정하고, 마지막 버튼을 뗄 때까지 간다.
///
/// 붙어 있는 이유는 짝을 맞추기 위해서다. 자식이 누름을 받았으면 뗌도 받아야
/// 하고(vim은 뗌이 올 때까지 Visual을 늘린다), 우리 제스처가 누름을 받았으면
/// 뗌도 받아야 한다(복사가 뗌에 있다). 누른 뒤 자식이 모드를 켜고 끄거나
/// Shift를 떼도 주인은 안 바뀐다.
pub const Grab = struct {
    held: Buttons = .{},
    owner: Owner = .ours,
    /// 첫 누름의 잎. `owner`가 `child`일 때 보고가 가는 패널이다.
    leaf: u4 = 0,

    pub fn active(self: *const Grab) bool {
        return self.held.bits() != 0;
    }

    /// 버튼 `b`가 눌렸다. `under`는 누른 자리의 패널이다. 돌려주는 것이 이
    /// 누름의 주인이다.
    pub fn press(self: *Grab, b: Button, under: ?Pane, shift: bool) Owner {
        if (!self.active()) {
            self.owner = ownerOf(under, shift);
            self.leaf = if (under) |p| p.leaf else 0;
        }
        self.held = self.held.with(b, true);
        return self.owner;
    }

    /// 버튼 `b`를 뗐다. 돌려주는 것이 이 뗌의 주인이다 — 마지막 버튼이어도
    /// 그 버튼의 주인을 돌려준 뒤에 풀린다.
    pub fn release(self: *Grab, b: Button) Owner {
        self.held = self.held.with(b, false);
        return self.owner;
    }

    /// 포인터가 아는 버튼 상태에 맞춘다. 장치가 누른 채 빠졌거나(`Pointer.forget`)
    /// 한 회차의 전이가 넘쳐 뗌을 잃으면 `held`가 영영 눌린 채로 남고, 그
    /// 뒤의 모든 누름이 옛 주인에게 간다. 회차마다 끝에서 부른다.
    pub fn settle(self: *Grab, now: Buttons) void {
        self.held = @bitCast(self.held.bits() & now.bits());
    }

    /// 끄는 보고에 실을 버튼. 여럿이 눌렸으면 왼쪽 · 가운데 · 오른쪽 순이다.
    /// 아무것도 안 눌렸으면 null — 버튼 없는 움직임이다.
    pub fn dragButton(self: *const Grab) ?Button {
        if (self.held.left) return .left;
        if (self.held.middle) return .middle;
        if (self.held.right) return .right;
        return null;
    }
};

/// 휠 한 회차가 어디로 가나(design 결정 12의 휠 표).
pub const WheelRoute = enum {
    /// 아무 일도 없다 — 키보드 copy mode인 패널(design 결정 7).
    ignore,
    /// 버튼 4 · 5의 누름으로 자식에게 보고한다.
    report,
    /// 화살표 키(위 · 아래)로 자식에게 보낸다. 한 눈금이 세 번이다.
    keys,
    /// 우리 스크롤백을 움직인다(PD-M1).
    scroll,
};

/// 포인터 아래 패널 `p`에서 굴린 휠의 갈 곳. 끄는 중의 휠(`Gesture.wheel`)은
/// 이것보다 먼저 본다.
///
/// Shift는 누름과 같이 우리에게 돌려준다. 대체 화면에서 우리 스크롤은 움직일
/// 스크롤백이 없으므로 아무 일도 없다.
pub fn wheelRoute(p: Pane, shift: bool) WheelRoute {
    if (p.copy) return .ignore;
    if (shift) return .scroll;
    if (p.wants) return .report;
    if (p.alt_keys) return .keys;
    return .scroll;
}
