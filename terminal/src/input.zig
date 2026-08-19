const std = @import("std");

/// `pub`인 이유는 `input_test.zig`가 `input.c.KEY_LEFT`처럼 커널이 정한
/// 이름으로 검사를 쓰기 위해서다. IP-M1까지 테스트는 103/105 같은 숫자
/// 리터럴을 썼는데, 그건 테스트가 `linux/input.h`에 닿을 방법이 없어서였다 —
/// 실은 이 파일이 이미 가져와 두고 잠가 뒀을 뿐이었다.
///
/// "테스트가 구현과 같은 출처를 쓰면 독립성을 잃는다"는 반론은 여기서
/// 성립하지 않는다. "103이 정말 ←인가"에 답하는 것은 부팅 게이트이고
/// (sendkey → 스캔코드 → atkbd → evdev), 단위 검사가 답하는 것은
/// "KEY_LEFT가 ESC [ D가 되는가"다.
pub const c = @cImport({
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
    .{ 0, 0 }, // 29: KEY_LEFTCTRL — modifier로 처리한다(아래 handleKey)
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
    .{ 0, 0 }, // 56: KEY_LEFTALT — modifier로 처리한다(IP-M2)
    .{ ' ', ' ' }, // 57: KEY_SPACE
};

// 위 표의 규약은 "N번째 칸이 evdev 코드 N"인데, IP-M1까지 그것을 지켜주는
// 것은 주석뿐이었다. 중간에 한 줄이 끼면 뒤가 전부 한 칸씩 밀리고, 그래도
// **컴파일은 통과하며**, 주석만 거짓말이 된다. 증상은 "게스트에서 a를 쳤는데
// s가 나온다"로 나타나므로 원인을 찾는 데 부팅 한 바퀴가 든다.
//
// 그래서 표의 양끝과 가운데를 커널의 이름에 못 박는다. 다섯 줄로 표 전체의
// 정렬을 잡는 이유는, 한 줄이 끼면 그 뒤의 앵커가 **반드시** 하나는 어긋나기
// 때문이다. IP-M2가 이 표 밖의 코드(KEY_LEFTMETA=125)를 처음 다루므로
// 지금이 못을 박을 자리다.
comptime {
    if (keymap.len != c.KEY_SPACE + 1)
        @compileError("keymap must end exactly at KEY_SPACE");
    if (keymap[c.KEY_1][0] != '1') @compileError("keymap drifted at KEY_1");
    if (keymap[c.KEY_ENTER][0] != '\r') @compileError("keymap drifted at KEY_ENTER");
    if (keymap[c.KEY_A][0] != 'a') @compileError("keymap drifted at KEY_A");
    if (keymap[c.KEY_Z][0] != 'z') @compileError("keymap drifted at KEY_Z");
}

/// 키 하나를 어떻게 번역할지 바꾸는, **바깥에서 들어오는** 상태.
///
/// design doc 결정 6: `input.zig`는 `vt.zig`를 import하지 않는다. DECCKM
/// 상태가 VT 안에 있다고 해서 여기서 직접 부르게 하면 (1) 지금 단방향인
/// 모듈 의존(main만 다섯을 안다)이 깨지고, (2) `ghostty-vt`를 링크하지 않는
/// `input_test`가 빌드조차 되지 않는다. 그래서 `main.zig`가 매 키마다
/// **값으로** 채워 넘긴다 — packed struct의 비트 읽기 한 번이라 값이 없다.
pub const Context = struct {
    /// DECCKM(DEC Cursor Key Mode, private mode 1). 켜져 있으면 방향키와
    /// Home/End가 `ESC [` 대신 `ESC O`로 시작한다. 이 모드를 켜는 것은
    /// 셸이 보내는 `ESC [ ? 1 h`이고, 그 시퀀스는 이미 우리가 파싱해서
    /// libghostty-vt에 먹이고 있다. main.zig가
    /// `screen.term.modes.get(.cursor_keys)`로 되읽어 채운다.
    cursor_keys: bool = false,

    /// PC 키보드 보정(design doc 결정 9). **IP-M2에서 처음 읽힌다** —
    /// 지금은 자리만 있다. 여기 적어두는 이유는 Context가 생기는 이유가
    /// DECCKM 하나가 아니라는 것을 남기기 위해서다.
    swap_alt_meta: bool = false,
};

/// ESC(0x1b). 아래 escape()가 계산 문맥에서 쓰므로 이름을 붙인다.
/// 반대로 **테스트 쪽 `"\x1b[A"`는 이름을 붙이지 않는다** — 거기서는 그것이
/// 와이어 포맷 자체이고, 쪼개는 순간 무슨 바이트가 나가는지 한눈에 안 보인다.
const ESC: u8 = 0x1b;

/// 특수키가 만드는 이스케이프 시퀀스는 모양이 **둘뿐**이다.
///
/// 이 셋을 keymap 배열에 넣지 않는 이유는 두 가지다. (1) keymap의 칸은
/// `[2]u8`(Shift 안 누름 / 누름) 문자 한 쌍이라 여러 바이트를 담을 수 없다.
/// (2) 방향키는 evdev 코드 102~111에 있어서 표를 거기까지 늘리면 58~101
/// 마흔네 칸이 전부 `.{ 0, 0 }`인 표가 된다.
const SpecialKey = union(enum) {
    /// `ESC [ X`. DECCKM이 켜져 있으면 `ESC O X`가 된다(design doc 결정 5).
    cursor: u8,
    /// `ESC [ N ~`. **DECCKM의 영향을 받지 않는다** — 흔한 오해라 여기 적어둔다.
    tilde: u8,
};

/// evdev 코드 → 특수키. 대상이 아니면 null.
///
/// F1~F12(59~88)·키패드·Insert(110)는 일부러 없다. TUI 앱이 하나도 없어서
/// 누를 이유가 없고, 게이트가 볼 수 없는 표를 늘리는 것은
/// project_gate_chain_composition이 경고한 부채다(design doc 비목표).
fn specialKey(code: u16) ?SpecialKey {
    return switch (code) {
        c.KEY_UP => .{ .cursor = 'A' },
        c.KEY_DOWN => .{ .cursor = 'B' },
        c.KEY_RIGHT => .{ .cursor = 'C' },
        c.KEY_LEFT => .{ .cursor = 'D' },
        c.KEY_HOME => .{ .cursor = 'H' },
        c.KEY_END => .{ .cursor = 'F' },
        c.KEY_DELETE => .{ .tilde = '3' },
        c.KEY_PAGEUP => .{ .tilde = '5' },
        c.KEY_PAGEDOWN => .{ .tilde = '6' },
        else => null,
    };
}

/// "보낼 것이 없다"를 뜻하는 빈 슬라이스. IP-M0 전에는 `null`이 이 자리였다.
const none: []const u8 = &[_]u8{};

/// modifier 상태를 들고 있는 작은 상태 머신.
/// design doc 결정 2의 세 단계 중 1번(modifier 갱신)과 3번(기본 번역)에
/// 해당한다. 2번(조합 dispatch)은 IP-M2에서 들어온다.
pub const State = struct {
    shift_left: bool = false,
    shift_right: bool = false,
    // Ctrl 둘을 좌우로 나눠 두는 이유는 Shift와 같다 — 하나를 누른 채
    // 다른 하나를 눌렀다 떼도 풀리면 안 된다.
    ctrl_left: bool = false,
    ctrl_right: bool = false,

    // Alt(Option)와 Meta(Cmd). design doc 결정 4의 여덟 중 나머지 넷이고,
    // IP-M0가 "관측 가능해지는 시점에 넣는다"며 미뤄둔 것이다. 그 시점이
    // 아래 chord()가 생기는 지금이다 — 비트만 있으면 반환값이 안 바뀌어서
    // 검사할 수가 없었다.
    //
    // 이름을 alt/meta로 붙이는 것은 **물리 키 이름**을 따른 것이다.
    // 어느 것이 Option이고 어느 것이 Cmd인지는 키보드 종류가 정하며,
    // 그 보정은 handleKey 맨 앞에서 코드를 맞바꾸는 것으로 끝난다(결정 9).
    // 여기까지 내려오면 "왼쪽 Alt 키가 눌려 있다"는 사실만 남는다.
    alt_left: bool = false,
    alt_right: bool = false,
    meta_left: bool = false,
    meta_right: bool = false,

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

    fn ctrled(self: State) bool {
        return self.ctrl_left or self.ctrl_right;
    }

    fn alted(self: State) bool {
        return self.alt_left or self.alt_right;
    }

    fn metaed(self: State) bool {
        return self.meta_left or self.meta_right;
    }

    /// Ctrl과 조합됐을 때 보낼 제어 문자. 대상이 아니면 null.
    ///
    /// 마스크(& 0x1F)는 문자가 0x40~0x7F일 때만 의미가 있다. Ctrl+1에
    /// 적용하면 0x11(XON)이 나오는데 아무도 그런 뜻으로 쓰지 않으므로,
    /// 대상을 여기 적힌 것으로 명시적으로 한정한다. xterm이 하는 것과 같다.
    fn control(ch: u8) ?u8 {
        return switch (ch) {
            'a'...'z', 'A'...'Z' => ch & 0x1f,
            '@', '[', '\\', ']', '^', '_' => ch & 0x1f,
            ' ' => 0x00,
            '?' => 0x7f,
            else => null,
        };
    }

    /// 바이트 하나를 seq에 담아 슬라이스로 돌려준다.
    fn one(self: *State, byte: u8) []const u8 {
        self.seq[0] = byte;
        return self.seq[0..1];
    }

    /// 특수키의 바이트열을 seq에 담아 슬라이스로 돌려준다.
    /// `one`과 같은 저장소를 쓴다 — 호출자가 즉시 복사하므로 안전하다.
    fn escape(self: *State, key: SpecialKey, ctx: Context) []const u8 {
        self.seq[0] = ESC;
        switch (key) {
            .cursor => |final| {
                // 여기가 결정 5다. `ESC [`인지 `ESC O`인지를 **추측하지
                // 않는다** — 셸이 보낸 `ESC [ ? 1 h`를 libghostty-vt가 이미
                // 받아뒀고, main.zig가 그 값을 ctx에 담아 넘겨준다.
                self.seq[1] = if (ctx.cursor_keys) 'O' else '[';
                self.seq[2] = final;
                return self.seq[0..3];
            },
            .tilde => |num| {
                self.seq[1] = '[';
                self.seq[2] = num;
                self.seq[3] = '~';
                return self.seq[0..4];
            },
        }
    }

    /// `ESC <byte>` 두 바이트. 터미널에서 "Meta+그 글자"를 뜻하는 오래된
    /// 관례이고, readline·zle·fish가 전부 기본값으로 안다.
    ///
    /// 이 ESC는 `Ctrl+[`가 만드는 것과 **완전히 같은 바이트**다. 그래서
    /// 받는 쪽은 ESC 다음 바이트를 잠깐 기다려서 "Meta 조합"인지 "혼자 온
    /// ESC"인지 가른다(readline의 keyseq-timeout). 우리 쪽에서 지켜야 할
    /// 것은 **두 바이트를 한 번의 write로 보내는 것**뿐인데, readKeys가
    /// out에 모아 main.zig가 한 번 pty.write하는 지금 구조가 이미 그렇다.
    fn escPrefixed(self: *State, byte: u8) []const u8 {
        self.seq[0] = ESC;
        self.seq[1] = byte;
        return self.seq[0..2];
    }

    /// design doc 결정 2의 **2번 단계 — 조합 dispatch**. TF design doc이
    /// "여긴 나중에"라고 비워두고 두 서브프로젝트를 건너온 자리다.
    ///
    /// 여기가 3번(기본 번역)보다 **먼저** 불려야 한다. 뒤에 두면 Cmd+←가
    /// 여기 닿기 전에 특수키 조회에서 그냥 ESC [ D로 번역돼 새어 나간다.
    /// "가로챌 것을 먼저 가로채고, 남은 것만 평소대로"가 규칙이다.
    ///
    /// 표에 없는 조합(Option+b, Cmd+C 등)은 null을 돌려주고 modifier가
    /// 없었던 것처럼 흘러간다. Ctrl이 마스크 대상이 아닌 문자를 다루는
    /// 방식(Ctrl+1 → '1')과 같은 규칙이다.
    ///
    /// Meta를 먼저 보는 것은 **둘 다 눌렸을 때 Cmd가 이긴다**는 뜻이고,
    /// 임의의 선택이지만 결정적이어야 해서 여기 한 곳에서만 정한다.
    fn chord(self: *State, code: u16) ?[]const u8 {
        if (self.metaed()) {
            // Cmd 계열은 제어 문자 한 바이트다. 0x01이 beginning-of-line인
            // 이유는 그것이 readline의 기본 바인딩이기 때문이지 Cmd와 A
            // 사이에 무슨 관계가 있어서가 아니다.
            return switch (code) {
                c.KEY_LEFT => self.one(0x01), // Ctrl+A: beginning-of-line
                c.KEY_RIGHT => self.one(0x05), // Ctrl+E: end-of-line
                // 0x15는 bash에서 커서 앞까지, zsh에서는 줄 전체를 지운다.
                // macOS의 Cmd+Backspace는 bash 쪽이다 — 셸을 바꿔 끼울 수
                // 있는 시스템에서 이 어긋남은 A안을 고른 대가이고, 감추지
                // 않고 여기 적어둔다(design doc 결정 8).
                c.KEY_BACKSPACE => self.one(0x15),
                else => null,
            };
        }
        if (self.alted()) {
            return switch (code) {
                c.KEY_LEFT => self.escPrefixed('b'), // backward-word
                c.KEY_RIGHT => self.escPrefixed('f'), // forward-word
                c.KEY_BACKSPACE => self.escPrefixed(0x7f), // backward-kill-word
                c.KEY_DELETE => self.escPrefixed('d'), // kill-word
                else => null,
            };
        }
        return null;
    }

    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    /// PTY로 보낼 바이트열을 반환한다. 보낼 것이 없으면 빈 슬라이스다.
    pub fn handleKey(self: *State, code: u16, value: i32, ctx: Context) []const u8 {
        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return none;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return none;
            },
            c.KEY_LEFTCTRL => {
                self.ctrl_left = value != 0;
                return none;
            },
            c.KEY_RIGHTCTRL => {
                self.ctrl_right = value != 0;
                return none;
            },
            c.KEY_LEFTALT => {
                self.alt_left = value != 0;
                return none;
            },
            c.KEY_RIGHTALT => {
                self.alt_right = value != 0;
                return none;
            },
            c.KEY_LEFTMETA => {
                self.meta_left = value != 0;
                return none;
            },
            c.KEY_RIGHTMETA => {
                self.meta_right = value != 0;
                return none;
            },
            else => {},
        }
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return none;

        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
        // 뒤에 두면 Cmd+←가 여기 닿기 전에 ESC [ D로 번역돼 새어 나간다.
        if (self.chord(code)) |bytes| return bytes;

        // 특수키를 keymap 조회보다 **먼저** 본다. 방향키(102~111)는 어차피
        // keymap 배열 밖이라 순서를 바꿔도 결과는 같지만, design doc 결정 2가
        // 정한 "가로챌 것을 먼저 가로채고 남은 것만 평소대로"를 코드 순서로
        // 남겨둔다 — IP-M2의 조합 dispatch가 바로 위에 얹혔다.
        //
        // `Ctrl+←`(`ESC [ 1 ; 5 D`)는 **IP-M2도 하지 않는다.** 결정 8의
        // 표에 있는 것은 Option과 Cmd 일곱 줄뿐이고, Ctrl+방향키를 누를
        // 이유가 있는 앱이 아직 없다. 지금도 Ctrl/Shift를 무시하고 맨
        // 시퀀스를 보낸다.
        if (specialKey(code)) |key| return self.escape(key, ctx);

        if (code >= keymap.len) return none;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        if (ch == 0) return none;

        // Ctrl이 눌려 있고 이 문자가 마스크 대상이면 제어 문자로 바꾼다.
        // 대상이 아니면(숫자 등) Ctrl을 무시하고 원래 문자를 보낸다.
        if (self.ctrled()) {
            if (control(ch)) |ctl| return self.one(ctl);
        }
        return self.one(ch);
    }
};

pub fn openDevice(path: [*:0]const u8) !c_int {
    const fd = open(path, O_RDONLY);
    if (fd < 0) return error.OpenInputDeviceFailed;
    return fd;
}

/// fd에서 한 번 read하고(poll이 읽을 게 있다고 알려준 뒤에만 호출한다),
/// 그 안의 EV_KEY 이벤트들을 문자 바이트로 바꿔 out에 채운다.
pub fn readKeys(self: *State, fd: c_int, out: []u8, ctx: Context) []const u8 {
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
        for (self.handleKey(ev.code, ev.value, ctx)) |byte| {
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
