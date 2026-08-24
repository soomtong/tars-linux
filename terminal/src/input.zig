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

    /// PC 키보드 보정(design doc 결정 9). IP-M1에 자리만 만들어 두고
    /// IP-M2가 읽기 시작했다. handleKey 맨 앞에서 56↔125, 100↔126을
    /// 맞바꾸는 데 쓰인다(swapAltMeta).
    ///
    /// DECCKM과 달리 이 값은 **부팅 내내 상수다.** PID 1이 설정 파일을
    /// 읽어 argv로 넘긴 것을 main.zig가 그대로 채우므로, 프로세스가 사는
    /// 동안 바뀌지 않는다 — 누를 때와 뗄 때 값이 달라져 modifier가 눌린
    /// 채로 남는 일이 구조적으로 없다는 뜻이다.
    swap_alt_meta: bool = false,
};

/// 스크롤백을 움직이는 동작(design 결정 12).
///
/// **여기에 화면 크기가 없는 것이 요점이다.** `page_up`이 몇 줄인지는
/// `input.zig`가 알 수 없고 알 필요도 없다 — 격자 크기를 아는 것은
/// `main.zig`이고, 그쪽이 이 값을 `rows` 만큼의 delta로 바꾼다. design doc
/// 결정 6이 "input.zig는 vt.zig를 import하지 않는다"로 세운 경계와 같은
/// 것이고, TR-M0이 색을 vt.zig에서 확정해 넘긴 것과도 같다.
pub const Scroll = enum {
    /// 스크롤백의 맨 위
    top,
    /// 활성 영역의 맨 아래 = 평소 상태
    bottom,
    /// 한 화면 위
    page_up,
    /// 한 화면 아래
    page_down,
};

/// 키 하나가 만드는 결과.
///
/// IP 시절 이 자리는 `[]const u8` 하나였다. 보낼 것이 바이트뿐이었기
/// 때문이다. **스크롤 키는 바이트가 아니라 동작이고 PTY로 새어 나가면 안
/// 되므로**, 그 구분을 표현할 수 있게 넓힌다(design 결정 11).
///
/// `project_copy_mode`가 "IP의 dispatch 단계가 그대로 진입점"이라고 적어 둔
/// 자리가 이곳이다. 이번에 넓히는 것은 **통로**이고 모드 상태는 넣지
/// 않는다 — copy mode가 나중에 이 union에 자기 variant를 더한다.
pub const Action = union(enum) {
    /// PTY로 보낼 바이트열. 빈 슬라이스는 "보낼 것이 없다"는 뜻이다.
    bytes: []const u8,
    /// 우리가 처리할 동작. **PTY로 보내지 않는다.**
    scroll: Scroll,
    /// copy mode의 명령. 이것도 PTY로 보내지 않는다.
    copy: Copy,
};

/// copy mode 안에서 키가 만드는 명령.
///
/// design 결정 2의 조각은 `select_char`·`yank`·`paste`까지 적었지만 CM-M0은
/// 여섯 개만 만든다. **variant를 미리 만들어 두면 `main.zig`의 switch가
/// `else`로 열려야 하고, 그러면 CM-M1에서 배선을 잊어도 컴파일이 통과한다.**
/// 지금 닫아 두면 variant를 더하는 순간 컴파일러가 배선할 자리를 알려준다.
pub const Copy = enum {
    enter,
    exit,
    left,
    down,
    up,
    right,
};

/// 한 번의 read가 만든 것 전부.
pub const Keys = struct {
    bytes: []const u8,
    /// **순서대로 적용해야 한다.** PageUp을 누르고 있으면 자동 반복이 한
    /// 번의 read에 여러 개를 실어 오는데, 마지막 하나만 보면 몇 번을 눌렀든
    /// 한 화면만 올라간다.
    scrolls: []const Scroll,
    /// copy mode 명령도 같은 이유로 순서대로 모은다. `j`를 누르고 있으면
    /// 자동 반복이 여러 개를 실어 오고, 그만큼 내려가야 한다.
    copies: []const Copy,
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

/// PC 키보드 보정(design doc 결정 9). 스페이스 옆 두 키의 순서가 Apple과
/// 정확히 뒤집혀 있으므로 코드를 맞바꾼다.
///
/// **파이프라인의 맨 앞에서 한 번만 부른다.** 그러면 그 뒤 로직은 어느
/// 키보드인지 전혀 몰라도 된다 — chord도 keymap도 specialKey도 고칠 것이
/// 없다는 것이 이 자리를 고른 이유다. 뒤로 갈수록 "여기도 보정해야 하나"를
/// 물어야 하는 곳이 늘어난다.
///
/// 문자 키는 건드리지 않는다. 두 키보드에서 실제로 자리가 다른 것은 이 넷뿐이다.
fn swapAltMeta(code: u16) u16 {
    return switch (code) {
        c.KEY_LEFTALT => c.KEY_LEFTMETA,
        c.KEY_LEFTMETA => c.KEY_LEFTALT,
        c.KEY_RIGHTALT => c.KEY_RIGHTMETA,
        c.KEY_RIGHTMETA => c.KEY_RIGHTALT,
        else => code,
    };
}

/// "보낼 것이 없다"를 뜻하는 빈 슬라이스. IP-M0 전에는 `null`이 이 자리였다.
const none: []const u8 = &[_]u8{};

/// 같은 뜻을 Action으로 감싼 것. TR-M2 전에는 `none` 자체가 반환값이었다.
const nothing: Action = .{ .bytes = none };

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

    /// 한 번의 read에서 나온 스크롤 동작의 저장소. `seq`와 같은 이유로 힙을
    /// 쓰지 않는다.
    ///
    /// 여덟을 넘기면 나머지는 버린다. 자동 반복이 그만큼 쌓이려면 poll이
    /// 여덟 프레임을 놓쳐야 하고, 그런 상황에서 한 화면 덜 올라가는 것은
    /// 문제가 아니다 — out이 모자랄 때 바이트를 버리는 것과 같은 판단이다.
    scrolls: [8]Scroll = undefined,

    /// 한 번의 read에서 나온 copy 명령의 저장소. `seq`·`scrolls`와 같은
    /// 이유로 힙을 쓰지 않는다.
    copies: [8]Copy = undefined,

    /// 지금 키를 어떻게 해석하는가. **모드가 `input`에 있는 이유가 design
    /// 결정 1이다** — "이 키를 어떻게 해석하는가"는 번역의 문제이고, 선택
    /// 영역이 `vt`에 있는 것은 그것이 화면 상태이기 때문이다.
    mode: Mode = .normal,

    pub const Mode = enum { normal, copy };

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
    fn chord(self: *State, code: u16) ?Action {
        if (self.metaed()) {
            // copy mode 진입(CM-M0). **Meta 분기 안에서 Shift를 한 번 더 보는
            // 예외가 여기 하나뿐이어야 한다**(design 위험 2). iTerm2의 copy
            // mode 진입키와 같은 자리를 고른 대가다.
            //
            // 모드를 여기서 바로 세우고 나가는 이유는, 이 뒤에 오는 키들이
            // handleKey 앞쪽의 copy 분기로 빠져야 하기 때문이다.
            if (self.shifted() and code == c.KEY_C) {
                self.mode = .copy;
                return .{ .copy = .enter };
            }
            // Cmd 계열은 제어 문자 한 바이트다. 0x01이 beginning-of-line인
            // 이유는 그것이 readline의 기본 바인딩이기 때문이지 Cmd와 A
            // 사이에 무슨 관계가 있어서가 아니다.
            return switch (code) {
                c.KEY_LEFT => .{ .bytes = self.one(0x01) }, // beginning-of-line
                c.KEY_RIGHT => .{ .bytes = self.one(0x05) }, // end-of-line
                // 0x15는 bash에서 커서 앞까지, zsh에서는 줄 전체를 지운다.
                // macOS의 Cmd+Backspace는 bash 쪽이다 — 셸을 바꿔 끼울 수
                // 있는 시스템에서 이 어긋남은 A안을 고른 대가이고, 감추지
                // 않고 여기 적어둔다(design doc 결정 8).
                c.KEY_BACKSPACE => .{ .bytes = self.one(0x15) },
                else => null,
            };
        }
        if (self.alted()) {
            return switch (code) {
                c.KEY_LEFT => .{ .bytes = self.escPrefixed('b') }, // backward-word
                c.KEY_RIGHT => .{ .bytes = self.escPrefixed('f') }, // forward-word
                c.KEY_BACKSPACE => .{ .bytes = self.escPrefixed(0x7f) }, // backward-kill-word
                c.KEY_DELETE => .{ .bytes = self.escPrefixed('d') }, // kill-word
                else => null,
            };
        }
        // Shift 계열 — 스크롤(TR design 결정 12). **바이트가 아니라 동작이다.**
        //
        // Cmd·Option보다 **뒤에** 있는 것에 뜻이 있다. 위 두 분기는 조합이
        // 표에 없어도 null을 돌려주며 chord 전체를 끝내므로, Cmd+Shift+PageUp은
        // 스크롤하지 않고 맨 PageUp이 된다. 임의의 선택이지만 결정적이고,
        // Cmd는 project_copy_mode가 예약한 자리라 여기서 뜻을 더하지 않는다.
        //
        // Shift+PageUp을 고른 이유는 xterm·리눅스 콘솔·tmux가 전부 쓰는
        // 형태라서다. Mac 노트북의 Fn+↑도 evdev에는 KEY_PAGEUP으로 도착하므로
        // 키보드 종류와 무관하게 동작한다.
        if (self.shifted()) {
            return switch (code) {
                c.KEY_PAGEUP => .{ .scroll = .page_up },
                c.KEY_PAGEDOWN => .{ .scroll = .page_down },
                c.KEY_HOME => .{ .scroll = .top },
                c.KEY_END => .{ .scroll = .bottom },
                else => null,
            };
        }
        return null;
    }

    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    ///
    /// TR-M2부터 반환이 `Action`이다. 그전에는 `[]const u8` 하나였고, 그래서
    /// "PTY로 보내지 않고 우리가 처리한다"를 표현할 방법이 없었다
    /// (design 결정 11).
    pub fn handleKey(self: *State, raw_code: u16, value: i32, ctx: Context) Action {
        // 0번 단계 — 키보드 보정. modifier를 **기록하기 전에** 맞바꾼다.
        // 인자 이름을 raw_code로 바꾼 것은 실수를 막기 위해서다: 아래에서
        // 실수로 raw_code를 다시 쓰면 보정이 빠진 코드가 흘러가는데, 이름이
        // 다르면 그 실수가 눈에 띈다.
        const code = if (ctx.swap_alt_meta) swapAltMeta(raw_code) else raw_code;

        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return nothing;
            },
            c.KEY_LEFTCTRL => {
                self.ctrl_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTCTRL => {
                self.ctrl_right = value != 0;
                return nothing;
            },
            c.KEY_LEFTALT => {
                self.alt_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTALT => {
                self.alt_right = value != 0;
                return nothing;
            },
            c.KEY_LEFTMETA => {
                self.meta_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTMETA => {
                self.meta_right = value != 0;
                return nothing;
            },
            else => {},
        }
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return nothing;

        // 1.5번 단계 — copy mode(design 결정 3). **아는 키만 명령이 되고
        // 나머지는 전부 삼킨다.** "모르는 키는 흘려보낸다"로 하면 모드 안에서
        // 친 글자가 셸에 도착하는 사고가 조용히 나고, 그것이 이 milestone의
        // 음성 검사 대상이다.
        //
        // chord()보다 **앞**이라 모드 안에서는 Cmd 조합도 전부 삼켜진다.
        // CM-M1의 `Cmd+C`와 CM-M2의 `Cmd+V`는 chord()가 아니라 이 표에
        // 들어와야 한다.
        //
        // 방향키를 함께 받는 이유는 project_copy_mode가 기록한 원래 요청이
        // "커서 키로 이동하고"였기 때문이다.
        if (self.mode == .copy) {
            switch (code) {
                c.KEY_ESC => {
                    self.mode = .normal;
                    return .{ .copy = .exit };
                },
                c.KEY_H, c.KEY_LEFT => return .{ .copy = .left },
                c.KEY_J, c.KEY_DOWN => return .{ .copy = .down },
                c.KEY_K, c.KEY_UP => return .{ .copy = .up },
                c.KEY_L, c.KEY_RIGHT => return .{ .copy = .right },
                else => return nothing,
            }
        }

        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
        // 뒤에 두면 Cmd+←가 여기 닿기 전에 ESC [ D로 번역돼 새어 나가고,
        // TR-M2부터는 Shift+PageUp이 ESC [ 5 ~ 로 번역돼 새어 나간다.
        if (self.chord(code)) |action| return action;

        // 특수키를 keymap 조회보다 **먼저** 본다. 방향키(102~111)는 어차피
        // keymap 배열 밖이라 순서를 바꿔도 결과는 같지만, design doc 결정 2가
        // 정한 "가로챌 것을 먼저 가로채고 남은 것만 평소대로"를 코드 순서로
        // 남겨둔다 — IP-M2의 조합 dispatch가 바로 위에 얹혔다.
        //
        // `Ctrl+←`(`ESC [ 1 ; 5 D`)는 **IP-M2도 하지 않는다.** 결정 8의
        // 표에 있는 것은 Option과 Cmd 일곱 줄뿐이고, Ctrl+방향키를 누를
        // 이유가 있는 앱이 아직 없다. 지금도 Ctrl/Shift를 무시하고 맨
        // 시퀀스를 보낸다.
        if (specialKey(code)) |key| return .{ .bytes = self.escape(key, ctx) };

        if (code >= keymap.len) return nothing;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        if (ch == 0) return nothing;

        // Ctrl이 눌려 있고 이 문자가 마스크 대상이면 제어 문자로 바꾼다.
        // 대상이 아니면(숫자 등) Ctrl을 무시하고 원래 문자를 보낸다.
        if (self.ctrled()) {
            if (control(ch)) |ctl| return .{ .bytes = self.one(ctl) };
        }
        return .{ .bytes = self.one(ch) };
    }
};

pub fn openDevice(path: [*:0]const u8) !c_int {
    const fd = open(path, O_RDONLY);
    if (fd < 0) return error.OpenInputDeviceFailed;
    return fd;
}

/// fd에서 한 번 read하고(poll이 읽을 게 있다고 알려준 뒤에만 호출한다),
/// 그 안의 EV_KEY 이벤트들을 처리한다. PTY로 보낼 바이트는 out에 채우고,
/// 스크롤 동작은 State의 배열에 모아 둘 다 돌려준다.
///
/// **루프 조건에서 `written < out.len`이 빠진 것이 TR-M2의 변경이다.**
/// 그전에는 바이트 버퍼가 차면 이벤트 처리 자체가 멈췄는데, 그러면 뒤따라온
/// 스크롤 키가 통째로 사라진다. 바이트는 여전히 버려지지만(아래 break),
/// 그것과 "동작을 못 본다"는 다른 종류의 손실이다.
pub fn readKeys(self: *State, fd: c_int, out: []u8, ctx: Context) Keys {
    const ev_size = @sizeOf(c.struct_input_event);
    var raw: [ev_size * 64]u8 = undefined;

    const n = read(fd, &raw, raw.len);
    if (n <= 0) return .{
        .bytes = out[0..0],
        .scrolls = self.scrolls[0..0],
        .copies = self.copies[0..0],
    };

    const count = @as(usize, @intCast(n)) / ev_size;
    var written: usize = 0;
    var scrolled: usize = 0;
    var copied: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const ev: *align(1) const c.struct_input_event =
            @ptrCast(&raw[i * ev_size]);
        if (ev.@"type" != c.EV_KEY) continue;
        switch (self.handleKey(ev.code, ev.value, ctx)) {
            // 키 하나가 여러 바이트가 될 수 있으므로(IP-M1의 이스케이프
            // 시퀀스) 슬라이스를 통째로 옮긴다. handleKey가 돌려준 슬라이스는
            // State.seq를 가리키고 다음 키가 그것을 덮어쓰므로, **여기서 즉시
            // 복사하는 것이 계약이다.**
            .bytes => |bytes| for (bytes) |byte| {
                if (written >= out.len) break;
                out[written] = byte;
                written += 1;
            },
            // 순서를 지켜 모은다. 자동 반복으로 여러 개가 한 번에 올 수 있고,
            // 마지막 하나만 남기면 몇 번을 눌렀든 한 화면만 올라간다.
            .scroll => |s| if (scrolled < self.scrolls.len) {
                self.scrolls[scrolled] = s;
                scrolled += 1;
            },
            // 스크롤과 같은 이유로 순서대로 모은다. 넘치면 버리는 것도 같다.
            .copy => |cmd| if (copied < self.copies.len) {
                self.copies[copied] = cmd;
                copied += 1;
            },
        }
    }
    return .{
        .bytes = out[0..written],
        .scrolls = self.scrolls[0..scrolled],
        .copies = self.copies[0..copied],
    };
}

/// translate-c가 struct input_event를 제대로 가져왔는지 확인하기 위한 헬퍼.
/// x86_64에서 24바이트(timeval 16 + type 2 + code 2 + value 4)여야 한다.
pub fn eventSize() usize {
    return @sizeOf(c.struct_input_event);
}
