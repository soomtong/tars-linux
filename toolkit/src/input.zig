//! 입력 이벤트(TK-M2 plan 확정 1, TK design 결정 13). 창 층이 Wayland 이벤트를 이것으로 바꿔 올리고, AppKit 층(`tk_kit`)이 받는다.
//! 어느 층에도 속하지 않는 순수 값이라 모듈 `tk_input`으로 따로 둔다(`tk_geom`과 같은 자리) — kit은 창 층을 모른 채 이벤트를 받고,
//! 호스트 검사는 Wayland 없이 이벤트를 지어낸다(R-ARCH-4).
//!
//! xkb를 쓰지 않는다. 서버(TARS terminal)의 키맵은 고정 us · pc105 텍스트(`terminal/vendor/keymap-us.xkb`)이고 `wl_keyboard.modifiers`의
//! 비트는 서버가 직접 채운다(R-WY-7, `terminal/src/wl_logic.zig`의 `MOD_*`). 그래서 키는 evdev 코드 → `Key` 표로, 수정키는 mask → `Mods`로
//! 읽으면 서버가 뜻한 그대로다. initrd에 libxkbcommon도 없다. 글자 키의 문자 표(`charFor`)는 TK-M4가 더했다 — 영문은 text-input을 켠 창에서도
//! `wl_keyboard`로 오고, 한글 모드의 숫자 · 기호 · 공백도 "확정 → 키"로 온다(TK design 결정 15). 표는 호스트 검사가 서버 키맵 파일과 대조한다.

/// 수정키. `wl_keyboard.modifiers`의 depressed(+ latched)에서 shift · ctrl · alt · super, locked에서 caps.
pub const Mods = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    caps: bool = false,
    _: u3 = 0,

    pub fn none(self: Mods) bool {
        return !self.shift and !self.ctrl and !self.alt and !self.super;
    }
};

/// mask 비트(서버의 `wl_logic.zig` `MOD_*`와 같은 값 — 고정 키맵의 Shift · Lock · Control · Mod1 · Mod4).
pub const MASK_SHIFT: u32 = 0x1;
pub const MASK_LOCK: u32 = 0x2;
pub const MASK_CTRL: u32 = 0x4;
pub const MASK_ALT: u32 = 0x8;
pub const MASK_SUPER: u32 = 0x40;

pub fn modsFromMask(depressed: u32, locked: u32) Mods {
    return .{
        .shift = depressed & MASK_SHIFT != 0,
        .ctrl = depressed & MASK_CTRL != 0,
        .alt = depressed & MASK_ALT != 0,
        .super = depressed & MASK_SUPER != 0,
        .caps = locked & MASK_LOCK != 0,
    };
}

/// 이름 있는 키. 나머지는 `other`(코드는 `Event.key.code`에 그대로 있다).
pub const Key = enum { tab, enter, escape, space, backspace, delete, up, down, left, right, page_up, page_down, home, end, other };

/// evdev 코드(linux/input-event-codes.h — 서버가 보내는 값, xkb 코드는 이것 + 8).
pub const KEY_ESC: u32 = 1;
pub const KEY_BACKSPACE: u32 = 14;
pub const KEY_TAB: u32 = 15;
pub const KEY_ENTER: u32 = 28;
pub const KEY_LEFTCTRL: u32 = 29;
pub const KEY_LEFTSHIFT: u32 = 42;
pub const KEY_RIGHTSHIFT: u32 = 54;
pub const KEY_LEFTALT: u32 = 56;
pub const KEY_SPACE: u32 = 57;
pub const KEY_CAPSLOCK: u32 = 58;
pub const KEY_RIGHTCTRL: u32 = 97;
pub const KEY_RIGHTALT: u32 = 100;
pub const KEY_HOME: u32 = 102;
pub const KEY_UP: u32 = 103;
pub const KEY_PAGEUP: u32 = 104;
pub const KEY_LEFT: u32 = 105;
pub const KEY_RIGHT: u32 = 106;
pub const KEY_END: u32 = 107;
pub const KEY_DOWN: u32 = 108;
pub const KEY_PAGEDOWN: u32 = 109;
pub const KEY_DELETE: u32 = 111;
pub const KEY_LEFTMETA: u32 = 125;
pub const KEY_RIGHTMETA: u32 = 126;
/// 포인터 버튼(`wl_pointer.button`의 코드).
pub const BTN_LEFT: u32 = 272;

pub fn keyFromCode(code: u32) Key {
    return switch (code) {
        KEY_TAB => .tab,
        KEY_ENTER => .enter,
        KEY_ESC => .escape,
        KEY_SPACE => .space,
        KEY_BACKSPACE => .backspace,
        KEY_DELETE => .delete,
        KEY_UP => .up,
        KEY_DOWN => .down,
        KEY_LEFT => .left,
        KEY_RIGHT => .right,
        KEY_PAGEUP => .page_up,
        KEY_PAGEDOWN => .page_down,
        KEY_HOME => .home,
        KEY_END => .end,
        else => .other,
    };
}

pub fn isModifier(code: u32) bool {
    return switch (code) {
        KEY_LEFTCTRL, KEY_RIGHTCTRL, KEY_LEFTSHIFT, KEY_RIGHTSHIFT, KEY_LEFTALT, KEY_RIGHTALT, KEY_LEFTMETA, KEY_RIGHTMETA, KEY_CAPSLOCK => true,
        else => false,
    };
}

/// 누르고 있으면 반복하는 키인가(TK-M2 plan 확정 2): 수정키 · Tab · Enter · Esc가 아닌 것.
pub fn repeats(code: u32) bool {
    if (isModifier(code)) return false;
    return switch (code) {
        KEY_TAB, KEY_ENTER, KEY_ESC => false,
        else => true,
    };
}

/// us 배열의 글자 키 표(evdev 2..57 — 서버 키맵 `terminal/vendor/keymap-us.xkb`와 같은 뜻, 호스트 검사가 대조한다). 칸마다 (Shift 없음, Shift).
/// 0은 글자가 아닌 키(Esc · Backspace · Tab · Enter · 수정키 · 키패드). 키패드는 NumLock 비트를 서버가 안 보내므로 뺐다.
pub const US_CHARS = [58][2]u8{
    .{ 0, 0 },      .{ 0, 0 },     .{ '1', '!' }, .{ '2', '@' },  .{ '3', '#' }, .{ '4', '$' }, .{ '5', '%' }, .{ '6', '^' },
    .{ '7', '&' },  .{ '8', '*' }, .{ '9', '(' }, .{ '0', ')' },  .{ '-', '_' }, .{ '=', '+' }, .{ 0, 0 },     .{ 0, 0 },
    .{ 'q', 'Q' },  .{ 'w', 'W' }, .{ 'e', 'E' }, .{ 'r', 'R' },  .{ 't', 'T' }, .{ 'y', 'Y' }, .{ 'u', 'U' }, .{ 'i', 'I' },
    .{ 'o', 'O' },  .{ 'p', 'P' }, .{ '[', '{' }, .{ ']', '}' },  .{ 0, 0 },     .{ 0, 0 },     .{ 'a', 'A' }, .{ 's', 'S' },
    .{ 'd', 'D' },  .{ 'f', 'F' }, .{ 'g', 'G' }, .{ 'h', 'H' },  .{ 'j', 'J' }, .{ 'k', 'K' }, .{ 'l', 'L' }, .{ ';', ':' },
    .{ '\'', '"' }, .{ '`', '~' }, .{ 0, 0 },     .{ '\\', '|' }, .{ 'z', 'Z' }, .{ 'x', 'X' }, .{ 'c', 'C' }, .{ 'v', 'V' },
    .{ 'b', 'B' },  .{ 'n', 'N' }, .{ 'm', 'M' }, .{ ',', '<' },  .{ '.', '>' }, .{ '/', '?' }, .{ 0, 0 },     .{ 0, 0 },
    .{ 0, 0 },      .{ ' ', ' ' },
};

/// 글자 키 하나의 문자(TK design 결정 13 · 15). Ctrl · Alt · Super가 있으면 null(명령이다). 글자(a~z)는 Shift와 잠긴 CapsLock 중 하나만이면
/// 대문자(서버 키맵의 `ALPHABETIC` 타입 — Shift+Caps는 소문자), 나머지는 Shift만 본다. 글자가 아닌 키는 null.
pub fn charFor(code: u32, mods: Mods) ?u21 {
    if (mods.ctrl or mods.alt or mods.super) return null;
    if (code >= US_CHARS.len) return null;
    const pair = US_CHARS[code];
    if (pair[0] == 0) return null;
    const letter = pair[0] >= 'a' and pair[0] <= 'z';
    const upper = if (letter) mods.shift != mods.caps else mods.shift;
    return pair[if (upper) 1 else 0];
}

pub const KeyEvent = struct { code: u32, key: Key, pressed: bool, repeat: bool = false, mods: Mods = .{} };
pub const ButtonEvent = struct { code: u32, pressed: bool, x: f32, y: f32 };
/// 휠(`wl_pointer.frame`에서 모은 값). `dy`는 px(wl_fixed 그대로 — 서버는 한 칸에 10), 아래로가 양수. `discrete`는 칸 수(없으면 0).
pub const ScrollEvent = struct { dy: f32, discrete: i32, x: f32, y: f32 };

/// 창 층이 올리는 이벤트 하나. 포인터 좌표는 surface 논리 좌표(레이어 frame과 같은 단위)다.
pub const Event = union(enum) {
    key: KeyEvent,
    /// 창이 키보드 포커스를 얻었다(참) · 잃었다(거짓) — `wl_keyboard.enter` · `leave`.
    focus: bool,
    /// 포인터가 들어왔거나 움직였다(`enter`도 이것으로).
    pointer_motion: struct { x: f32, y: f32 },
    pointer_leave,
    button: ButtonEvent,
    scroll: ScrollEvent,
};
