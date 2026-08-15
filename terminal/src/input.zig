const std = @import("std");

const c = @cImport({
    @cInclude("linux/input.h");
});

/// libc의 open을 직접 선언한다. glibc의 `open`은 가변 인자
/// (`int open(const char *, int, ...)`)라 translate-c가 만든 래퍼를 그대로
/// 쓰기 번거롭다 — `pty.zig`가 `execv`를 직접 선언한 것과 같은 이유다.
extern "c" fn open(path: [*:0]const u8, flags: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;

const O_RDONLY: c_int = 0;

/// evdev keycode → (Shift 안 누름, Shift 누름) 문자.
/// 0은 "이 키는 문자를 만들지 않는다"는 뜻이다(modifier 키 등).
/// 값은 리눅스 `input-event-codes.h`의 KEY_* 상수 순서 그대로이며,
/// US QWERTY 레이아웃 하나만 하드코딩한다(design doc 6번 결정).
const keymap = [_][2]u8{
    .{ 0, 0 }, //  0: (없음)
    .{ 0x1b, 0x1b }, //  1: KEY_ESC
    .{ '1', '!' }, //  2
    .{ '2', '@' }, //  3
    .{ '3', '#' }, //  4
    .{ '4', '$' }, //  5
    .{ '5', '%' }, //  6
    .{ '6', '^' }, //  7
    .{ '7', '&' }, //  8
    .{ '8', '*' }, //  9
    .{ '9', '(' }, // 10
    .{ '0', ')' }, // 11
    .{ '-', '_' }, // 12
    .{ '=', '+' }, // 13
    .{ 0x7f, 0x7f }, // 14: KEY_BACKSPACE — 터미널 관례상 BS(0x08)가 아니라 DEL
    .{ '\t', '\t' }, // 15: KEY_TAB
    .{ 'q', 'Q' }, // 16
    .{ 'w', 'W' }, // 17
    .{ 'e', 'E' }, // 18
    .{ 'r', 'R' }, // 19
    .{ 't', 'T' }, // 20
    .{ 'y', 'Y' }, // 21
    .{ 'u', 'U' }, // 22
    .{ 'i', 'I' }, // 23
    .{ 'o', 'O' }, // 24
    .{ 'p', 'P' }, // 25
    .{ '[', '{' }, // 26
    .{ ']', '}' }, // 27
    .{ '\r', '\r' }, // 28: KEY_ENTER — 실제 터미널은 CR을 보낸다
    .{ 0, 0 }, // 29: KEY_LEFTCTRL (이번 범위 밖)
    .{ 'a', 'A' }, // 30
    .{ 's', 'S' }, // 31
    .{ 'd', 'D' }, // 32
    .{ 'f', 'F' }, // 33
    .{ 'g', 'G' }, // 34
    .{ 'h', 'H' }, // 35
    .{ 'j', 'J' }, // 36
    .{ 'k', 'K' }, // 37
    .{ 'l', 'L' }, // 38
    .{ ';', ':' }, // 39
    .{ '\'', '"' }, // 40
    .{ '`', '~' }, // 41
    .{ 0, 0 }, // 42: KEY_LEFTSHIFT
    .{ '\\', '|' }, // 43
    .{ 'z', 'Z' }, // 44
    .{ 'x', 'X' }, // 45
    .{ 'c', 'C' }, // 46
    .{ 'v', 'V' }, // 47
    .{ 'b', 'B' }, // 48
    .{ 'n', 'N' }, // 49
    .{ 'm', 'M' }, // 50
    .{ ',', '<' }, // 51
    .{ '.', '>' }, // 52
    .{ '/', '?' }, // 53
    .{ 0, 0 }, // 54: KEY_RIGHTSHIFT
    .{ '*', '*' }, // 55: KEY_KPASTERISK
    .{ 0, 0 }, // 56: KEY_LEFTALT
    .{ ' ', ' ' }, // 57: KEY_SPACE
};

/// "보낼 것이 없다"를 뜻하는 빈 슬라이스. IP-M0 전에는 `null`이 이 자리였다.
const none: []const u8 = &[_]u8{};

/// modifier 상태를 들고 있는 작은 상태 머신.
/// design doc 결정 2의 세 단계 중 1번(modifier 갱신)과 3번(기본 번역)에
/// 해당한다. 2번(조합 dispatch)은 IP-M2에서 들어온다.
pub const State = struct {
    shift_left: bool = false,
    shift_right: bool = false,

    /// 반환 슬라이스의 저장소. 힙을 쓰지 않는다.
    ///
    /// 호출자(readKeys)가 반환값을 즉시 out으로 복사하므로, 같은 read
    /// 배치의 다음 키가 이 배열을 덮어써도 안전하다. 8바이트인 이유는 이
    /// 서브프로젝트에서 가장 긴 시퀀스가 6바이트이기 때문이다
    /// (`ESC [ 1 ; 5 D` 형태, IP-M1).
    seq: [8]u8 = undefined,

    fn shifted(self: State) bool {
        return self.shift_left or self.shift_right;
    }

    /// 바이트 하나를 seq에 담아 슬라이스로 돌려준다.
    fn one(self: *State, byte: u8) []const u8 {
        self.seq[0] = byte;
        return self.seq[0..1];
    }

    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    /// PTY로 보낼 바이트열을 반환한다. 보낼 것이 없으면 빈 슬라이스다.
    pub fn handleKey(self: *State, code: u16, value: i32) []const u8 {
        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return none;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return none;
            },
            else => {},
        }
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return none;
        if (code >= keymap.len) return none;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        return if (ch == 0) none else self.one(ch);
    }
};

pub fn openDevice(path: [*:0]const u8) !c_int {
    const fd = open(path, O_RDONLY);
    if (fd < 0) return error.OpenInputDeviceFailed;
    return fd;
}

/// fd에서 한 번 read하고(poll이 읽을 게 있다고 알려준 뒤에만 호출한다),
/// 그 안의 EV_KEY 이벤트들을 문자 바이트로 바꿔 out에 채운다.
pub fn readKeys(self: *State, fd: c_int, out: []u8) []const u8 {
    const ev_size = @sizeOf(c.struct_input_event);
    var raw: [ev_size * 64]u8 = undefined;

    const n = read(fd, &raw, raw.len);
    if (n <= 0) return out[0..0];

    const count = @as(usize, @intCast(n)) / ev_size;
    var written: usize = 0;
    var i: usize = 0;
    while (i < count and written < out.len) : (i += 1) {
        const ev: *align(1) const c.struct_input_event =
            @ptrCast(&raw[i * ev_size]);
        if (ev.@"type" != c.EV_KEY) continue;
        // 키 하나가 여러 바이트가 될 수 있으므로(IP-M1의 이스케이프 시퀀스)
        // 슬라이스를 통째로 옮긴다. out이 모자라면 거기서 멈춘다 — 다음
        // poll에서 이어지지 않고 버려지지만, out은 64바이트이고 한 번의
        // read에 그만큼의 키가 들어오는 일은 사람 손으로는 일어나지 않는다.
        for (self.handleKey(ev.code, ev.value)) |byte| {
            if (written >= out.len) break;
            out[written] = byte;
            written += 1;
        }
    }
    return out[0..written];
}

/// translate-c가 struct input_event를 제대로 가져왔는지 확인하기 위한 헬퍼.
/// x86_64에서 24바이트(timeval 16 + type 2 + code 2 + value 4)여야 한다.
pub fn eventSize() usize {
    return @sizeOf(c.struct_input_event);
}
