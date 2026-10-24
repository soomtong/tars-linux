//! init이 terminal에 argv로 넘기는 값의 계약(SA design 결정 1 · 2).
//!
//! 두 프로그램이 이 파일 하나를 각자의 build.zig에서 `screen_args`라는 이름의
//! 모듈로 컴파일한다. SA 전에는 아래 enum이 `init/src/config.zig`와
//! `terminal/src/{hangul,input,clipboard}.zig`에 한 벌씩 있었고 둘을 잇는 것이
//! argv의 문자열과 "짝이어야 한다"는 주석뿐이었다. 이제 한 벌이라, 이름을
//! 더하면 두 프로그램의 switch가 함께 컴파일 에러를 낸다.
//!
//! 이 파일은 순수하다. 시스템 콜도 libc도 로그도 없다 — init이 libc를 링크하지
//! 않으므로(`project_zig_c_uapi_rule`) 여기서 libc를 끌어오면 init이 깨진다.
//! 모르는 이름을 알리는 길은 호출자가 주는 sink다(`Toggles.parse`).
//!
//! 여기 드는 것은 "값의 이름이 무엇이고 몇 번 칸에 가는가"까지다. 그 값이 무엇을
//! 하는가 — 자판 표 · 키 번역 · 클립보드 고르기 — 는 terminal의 파일들에, 설정
//! 파일의 다른 키들은 `config.zig`에 그대로 있다.

const std = @import("std");

/// 물리 키보드 종류. 재배치가 아니라 하드웨어 선언이다 — 사용자가 키를
/// 임의로 옮기는 문이 아니라, "스페이스 옆 두 키가 어느 순서인가"라는 사실
/// 하나를 알려주는 것이다(IP design 비목표: 범용 키바인딩 엔진은 안 만든다).
///
/// `config.Shell`과 같은 화이트리스트 구조다. enum에 없는 이름은 파싱을
/// 통과할 수 없으므로 검사 목록을 따로 유지할 필요가 없다. terminal은 이
/// 값으로 `swap_alt_meta`를 정한다(`pc`면 켠다).
pub const Keyboard = enum {
    apple,
    pc,

    /// argv에 넣고 로그에 찍을 글자. `@tagName`은 sentinel이 있는 문자열을
    /// 주므로(0.17) execve의 argv에 `.ptr`로 바로 들어간다 — SA 전의 switch는
    /// 그 반대를 전제로 손으로 쓴 것이었다.
    pub fn arg(self: Keyboard) [:0]const u8 {
        return @tagName(self);
    }
};

/// 한글 자판(HI design 결정 7). 화이트리스트 구조는 `Keyboard`와 같다.
/// 각 자판이 어떻게 조합하는가는 `terminal/src/hangul.zig`의 표들이다.
pub const HangulLayout = enum {
    dubeol,
    sebeol_3p3,
    shin_p2,
    shin_pcs,

    pub fn arg(self: HangulLayout) [:0]const u8 {
        return @tagName(self);
    }
};

/// 영문 자판. 한글 자판과 직교한다(HI design 결정 13) — 한글 배열은
/// 물리 키 위치를 쓰므로 이 값이 무엇이든 안 흔들린다.
pub const LatinLayout = enum {
    qwerty,
    dvorak,

    pub fn arg(self: LatinLayout) [:0]const u8 {
        return @tagName(self);
    }
};

/// terminal의 클립보드를 누구와 나누는가(CB design 결정 2). `shared`면 모든
/// 패널과 워크스페이스가 하나를 쓰고, `pane`이면 패널마다 따로다. `workspace`는
/// 이름이 없다(CB design 비목표 1).
pub const ClipboardScope = enum {
    shared,
    pane,

    pub fn arg(self: ClipboardScope) [:0]const u8 {
        return @tagName(self);
    }
};

/// 한/영 전환 키의 이름(HI design 결정 7).
///
/// 자판 · 키보드와 모양이 다른 유일한 설정이다. 그것들은 하나를 고르는 것이지만
/// 전환 키는 배타적이지 않다 — 한/영 키를 쓰면서 CapsLock도 쓰는 것이 정상이다.
/// 그래서 enum 하나가 아니라 아래 `Toggles` 집합이 값이 되고, 이 enum은 이름의
/// 화이트리스트 역할만 한다.
///
/// 다섯째 `esc_latin`(EL-M0)은 오는 길이 다르다. 앞의 넷은 설정 파일
/// `hangul_toggle=` 목록의 이름이고 `esc_latin`은 따로 있는 키(`esc_latin=on`)인데,
/// init이 둘을 argv 문자열 하나로 합쳐 넘긴다(`Config.terminalToggles`, EL design
/// 결정 1). 그래서 `Toggles.parse`가 `Source`를 받는다 — 파일에서는 이 이름이
/// 모르는 이름이고 argv에서는 받는다.
pub const ToggleKey = enum {
    /// 실기의 한/영 키(evdev 122). 게이트가 못 보낸다 — QEMU가
    /// `sendkey lang1`을 이름만 받고 조용히 버린다(HI-M0 실측 1). 그래서 이
    /// 갈래를 덮는 것은 `input_test`의 호스트 검사뿐이다.
    hangul_key,
    /// Shift+Space. HI-M1이 유일한 전환 키로 골랐던 것이고 이제 끌 수 있다 —
    /// `HELLO WORLD`를 칠 때 한/영이 바뀌는 것이 그 대가였다.
    shift_space,
    /// CapsLock을 짧게 눌렀다 뗀 것. 길게 누르면 대문자 잠금이다(HI 결정 9).
    capslock_tap,
    /// 왼쪽 Ctrl을 짧게 눌렀다 뗀 것. 누른 동안 다른 키가 오면 평범한
    /// modifier이므로 아무 일도 안 일어난다(HI 결정 8).
    lctrl_tap,
    /// 한글을 치다가 수정키 없는 Esc를 누르면 영문으로 돌아온다(EL design
    /// 결정 2). 앞의 넷과 달리 한 방향이다 — 끄기만 하고 켜지는 않는다.
    esc_latin,
};

/// `Toggles.arg`가 만드는 문자열을 담을 버퍼의 크기. 다섯을 전부 켠 목록이
/// 55바이트이고 NUL 하나가 더 든다.
pub const TOGGLE_ARG_MAX = 64;

/// 가장 긴 목록 — 다섯이 전부 켜진 것. argv의 기본값이기도 하다(아래 `default_toggles_arg`).
const LONGEST_TOGGLES = "hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin";

comptime {
    if (LONGEST_TOGGLES.len + 1 > TOGGLE_ARG_MAX)
        @compileError("TOGGLE_ARG_MAX is too small for the full toggle list");
}

/// 켜진 전환 키의 집합.
pub const Toggles = struct {
    hangul_key: bool = false,
    shift_space: bool = false,
    capslock_tap: bool = false,
    lctrl_tap: bool = false,
    /// 설정 파일의 `hangul_toggle` 목록으로는 못 켠다(`parse(.file, …)`가 모르는
    /// 이름으로 넘긴다). 켜는 것은 `Config.terminalToggles` 하나이고, 그 값은
    /// 파일의 `esc_latin=` 줄에서 온다(EL design 결정 1).
    esc_latin: bool = false,

    /// 글자가 어디서 왔는가. 파일은 이름 넷, argv는 다섯을 받는다.
    pub const Source = enum { file, argv };

    /// 콤마 목록을 집합으로 바꾼다.
    ///
    /// 모르는 이름은 `sink.unknown(name)`에 알리고 넘어간다 — 설정 파일은 사람이
    /// 손으로 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이라는 CP의 판단
    /// 그대로다. 그 규칙이 목록 안에서도 선다: 이름 하나가 틀려도 나머지는
    /// 살아남는다. init은 sink로 로그를 찍고, terminal은 `ignore_unknown`을 준다 —
    /// init이 이미 한 번 경고를 찍었으므로 같은 줄을 두 번 낼 이유가 없다.
    ///
    /// 빈 값(`hangul_toggle=`)은 뜻이 있는 입력이다. 기본값으로 떨어뜨리지
    /// 않는다 — 그러면 전환 키를 전부 끌 방법이 없어진다. `none`은 `arg()`가 빈
    /// 집합에 쓰는 이름이라 조용히 건너뛴다 — 안 그러면 전환 키를 다 끈 사람의
    /// 부팅 로그에 매번 "모르는 이름 none"이 찍힌다.
    pub fn parse(comptime source: Source, text: []const u8, sink: anytype) Toggles {
        var t = Toggles{};
        var it = std.mem.splitScalar(u8, text, ',');
        while (it.next()) |raw| {
            const name = std.mem.trim(u8, raw, " \t");
            if (name.len == 0) continue;
            if (std.mem.eql(u8, name, "none")) continue;
            const key = std.meta.stringToEnum(ToggleKey, name) orelse {
                sink.unknown(name);
                continue;
            };
            switch (key) {
                .hangul_key => t.hangul_key = true,
                .shift_space => t.shift_space = true,
                .capslock_tap => t.capslock_tap = true,
                .lctrl_tap => t.lctrl_tap = true,
                .esc_latin => switch (source) {
                    .argv => t.esc_latin = true,
                    .file => sink.unknown(name),
                },
            }
        }
        return t;
    }

    /// argv로 넘기고 로그에 찍을 정규형 콤마 목록. 버퍼는 호출자가 준다 —
    /// init에는 힙이 없고, `Keyboard.arg()`처럼 상수 문자열을 돌려줄 수도
    /// 없다(조합이 서른두 가지다).
    ///
    /// 정규화가 이 함수의 값이다. 어떤 순서로 적었든 enum 선언 순서로 나오므로,
    /// 로그에 찍힌 문자열 하나가 곧 집합 전체다. HI 게이트가 그 줄 하나로
    /// "무엇이 켜지고 무엇이 꺼졌는가"를 본다.
    ///
    /// 하나도 안 켜졌으면 `none`이다 — 빈 문자열을 argv에 넣으면 terminal
    /// 쪽에서 "인자가 없다"와 구분이 안 된다.
    pub fn arg(self: Toggles, buf: []u8) [:0]const u8 {
        var len: usize = 0;
        if (self.hangul_key) appendName(buf, &len, "hangul_key");
        if (self.shift_space) appendName(buf, &len, "shift_space");
        if (self.capslock_tap) appendName(buf, &len, "capslock_tap");
        if (self.lctrl_tap) appendName(buf, &len, "lctrl_tap");
        if (self.esc_latin) appendName(buf, &len, "esc_latin");
        if (len == 0) appendName(buf, &len, "none");
        buf[len] = 0;
        return buf[0..len :0];
    }
};

/// `Toggles.arg`가 쓰는 이어붙이기. 첫 항목이 아니면 콤마를 먼저 넣는다.
///
/// 모자라면 자른다. 위 `comptime`이 `TOGGLE_ARG_MAX`가 최악의 경우보다
/// 크다는 것을 못 박으므로 이 길로 실제로 갈 일은 없고, 그래도 배열 밖을
/// 쓰지 않는 쪽으로 적어 둔다. `len.* + 1`을 보는 것은 `buf[len]`에 들어갈
/// NUL 한 칸을 남기기 위해서다.
fn appendName(buf: []u8, len: *usize, name: []const u8) void {
    if (len.* > 0) {
        if (len.* + 1 >= buf.len) return;
        buf[len.*] = ',';
        len.* += 1;
    }
    for (name) |ch| {
        if (len.* + 1 >= buf.len) return;
        buf[len.*] = ch;
        len.* += 1;
    }
}

/// 모르는 이름을 버리는 sink. terminal과 검사가 `Toggles.parse`에 준다.
pub const ignore_unknown = struct {
    pub fn unknown(_: @This(), _: []const u8) void {}
}{};

/// terminal argv의 자리(SA design 결정 3). 0번은 `/terminal` 자신이다.
///
/// init은 `Child.argv[@backingInt(slot)]`에 쓰고(부팅 · `reload terminal` ·
/// 탈출로) terminal은 같은 자리를 읽는다. SA 전에는 init의 상수 일곱과 terminal의
/// `args[n]` 여덟이 주석으로만 묶여 있었고, 어긋나면 탈출로가 키보드 종류 자리를
/// 덮어썼다. 칸을 더할 때는 여기에 이름을 더하고 `ARGC`를 올린다 — 콘솔 셸과
/// 서비스 셋의 argv도 같은 길이라 그쪽은 null이 하나 늘 뿐이다.
pub const Slot = enum(u8) {
    /// 셸 경로. init이 `resolveShell`로 정한다.
    shell = 1,
    /// 셸에 넘길 플래그 — `--no-config` 같은 것, 또는 "아무것도 안 붙인다"는 뜻의
    /// `none`(SC design 결정 3). 탈출로가 덮는 자리다(결정 8).
    flag = 2,
    keyboard = 3,
    /// 키보드 장치 경로. init이 하드웨어를 살펴 고른다(HD-M0). `reload terminal`은
    /// 설정이 아니라 안 건드린다.
    device = 4,
    hangul = 5,
    latin = 6,
    /// `Toggles.arg`의 글자 — 파일의 `hangul_toggle`에 `esc_latin`을 합친 것.
    toggles = 7,
    clipboard = 8,

    /// 배열 인덱스. `encode` · `decode`가 칸을 가리키는 길이고, 밖에서는 init의
    /// 탈출로(`Rescue.slot`) 하나만 쓴다 — 그 자리는 terminal과 콘솔 셸을 같은 코드로
    /// 다루므로 `Args`를 모르는 편이 맞다(SA-M1 plan 확정 5).
    pub fn index(self: Slot) usize {
        return @backingInt(self);
    }
};

/// argv 배열의 길이. `Argv`가 init의 `Child.argv`와 서비스 셋의 `*_ARGV` 상수의
/// 타입이다.
pub const ARGC = 9;

/// execve에 그대로 넘기는 argv. 첫 null에서 멈추므로 인자가 하나인 자식(콘솔 셸 ·
/// 서비스)도 같은 타입을 쓴다. 힙이 없어서 길이가 컴파일 타임에 고정이다.
pub const Argv = [ARGC:null]?[*:0]const u8;

/// terminal 바이너리의 경로. `encode`가 0번 칸에 넣고 init의 `Child.path`가 같은 글자다 —
/// 우리가 빌드해 initrd 루트에 넣는 것이라 설정 대상이 아니다.
pub const TERMINAL_PATH: [:0]const u8 = "/terminal";

comptime {
    // 자리가 전부 배열 안에 있고 겹치지 않는다. enum이 값의 중복을 이미 막으므로
    // 볼 것은 상한 하나다.
    for (std.enums.values(Slot)) |s| {
        if (@backingInt(s) >= ARGC) @compileError("a Slot is outside ARGC");
    }
}

/// 인자 없이 손으로 띄웠을 때의 값. init이 있으면 이 자리들은 언제나 차 있으므로
/// 이 값들은 개발 중 `./terminal`을 그냥 실행할 때만 쓰인다. 설정 파일의
/// 기본값(`config.Config`)과 같아야 한다 — 다르면 "init 없이 띄운 terminal"이
/// "설정 파일 없는 TARS"와 다르게 뜬다.
pub const default_shell_path: [*:0]const u8 = "/usr/bin/fish";
/// init이 없어서 `none`을 넘겨줄 사람이 없으므로 `--no-config`다.
pub const default_shell_flag: [*:0]const u8 = "--no-config";
pub const default_device_path: [*:0]const u8 = "/dev/input/event0";
pub const default_keyboard: Keyboard = .apple;
pub const default_hangul: HangulLayout = .shin_pcs;
pub const default_latin: LatinLayout = .qwerty;
pub const default_toggles_arg: []const u8 = LONGEST_TOGGLES;
/// 위 글자를 집합으로 적은 것 — 다섯이 전부 켜진다. 둘이 같은 것은 `screen_args_test`가 본다.
pub const default_toggles: Toggles = .{
    .hangul_key = true,
    .shift_space = true,
    .capslock_tap = true,
    .lctrl_tap = true,
    .esc_latin = true,
};
pub const default_clipboard: ClipboardScope = .shared;

/// terminal argv의 값 전체(SA design 결정 7). init이 채우고 terminal이 읽는 것은 이
/// 구조체 하나이고, 칸 번호와 글자는 아래 `encode` · `decode` 안에만 있다.
///
/// 값을 타입으로 든다 — 전환 키는 `Toggles`(집합)이고 글자가 아니다. 글자는 `encode`
/// 안에서만 생기고 `decode`가 되돌린다. 기본값이 없는 것은 일부러다: init이 필드 하나를
/// 빠뜨리면 컴파일이 막혀야 한다. SA-M0까지는 `Slot`에 이름을 더하고 그 칸을 안 채워도
/// 통과했다(null일 뿐이다). 없는 칸의 기본값은 `decode`의 일이다.
///
/// 포인터 셋(`shell_path` · `shell_flag` · `device_path`)은 소유하지 않는다. init에서는
/// `main()`의 스택과 `Live`를 가리키고 프로세스 수명 내내 유효하다 — terminal에서는
/// 커널이 준 argv다.
pub const Args = struct {
    shell_path: [*:0]const u8,
    shell_flag: [*:0]const u8,
    keyboard: Keyboard,
    device_path: [*:0]const u8,
    hangul: HangulLayout,
    latin: LatinLayout,
    toggles: Toggles,
    clipboard: ClipboardScope,
};

/// `Args`에서 argv를 짓는다. 0번은 `TERMINAL_PATH`다.
///
/// `toggle_buf`는 호출자가 들고 argv가 살아 있는 동안 유지한다 — init에는 힙이 없다.
/// 부팅은 `main()`의 `terminal_toggle_buf`, `reload terminal`은 `Live.toggle`이다
/// (SA-M1 plan 확정 2). `Toggles.arg`가 그 버퍼에 글자를 쓰고 그 포인터가 7번 칸이다.
pub fn encode(a: Args, toggle_buf: *[TOGGLE_ARG_MAX]u8) Argv {
    var v: Argv = @splat(null);
    v[0] = TERMINAL_PATH.ptr;
    v[Slot.shell.index()] = a.shell_path;
    v[Slot.flag.index()] = a.shell_flag;
    v[Slot.keyboard.index()] = a.keyboard.arg().ptr;
    v[Slot.device.index()] = a.device_path;
    v[Slot.hangul.index()] = a.hangul.arg().ptr;
    v[Slot.latin.index()] = a.latin.arg().ptr;
    v[Slot.toggles.index()] = a.toggles.arg(toggle_buf).ptr;
    v[Slot.clipboard.index()] = a.clipboard.arg().ptr;
    return v;
}

/// argv에서 `Args`를 되돌린다. 없는 칸(null)과 못 읽는 글자는 위 `default_*`다.
///
/// init이 화이트리스트를 이미 거쳤으므로 init이 띄운 terminal에서 기본값으로 떨어지는
/// 길은 없다 — 그 길은 손으로 `./terminal`을 띄울 때를 위한 것이다. 그때 엉뚱한 글자를
/// 주면 로그에 기본값의 이름이 찍힌다(글자가 아니라 읽은 결과를 찍는다). 전환 키의
/// 모르는 이름은 버린다 — init이 이미 한 번 경고를 찍었다.
///
/// init의 `reload terminal`도 이것을 쓴다 — 떠 있는 argv를 되돌려 설정에서 온 필드만
/// 바꾸고 다시 `encode`한다. 장치 경로가 그대로 되돌아가는 것이 "설정이 아니라 안
/// 건드린다"를 코드로 세우는 자리다(plan 확정 4).
pub fn decode(v: Argv) Args {
    return .{
        .shell_path = v[Slot.shell.index()] orelse default_shell_path,
        .shell_flag = v[Slot.flag.index()] orelse default_shell_flag,
        .keyboard = enumAt(Keyboard, v, .keyboard, default_keyboard),
        .device_path = v[Slot.device.index()] orelse default_device_path,
        .hangul = enumAt(HangulLayout, v, .hangul, default_hangul),
        .latin = enumAt(LatinLayout, v, .latin, default_latin),
        .toggles = if (v[Slot.toggles.index()]) |t|
            Toggles.parse(.argv, std.mem.span(t), ignore_unknown)
        else
            default_toggles,
        .clipboard = enumAt(ClipboardScope, v, .clipboard, default_clipboard),
    };
}

/// `decode`의 enum 칸 하나.
fn enumAt(comptime T: type, v: Argv, s: Slot, default: T) T {
    const raw = v[s.index()] orelse return default;
    return std.meta.stringToEnum(T, std.mem.span(raw)) orelse default;
}

/// 커널이 준 argv(`std.process.Init.minimal.args.vector`, 길이가 가변인 슬라이스)를
/// `decode`가 받는 아홉 칸으로 옮긴다. 앞 `ARGC`칸까지만 보고 남는 칸은 null이다 —
/// 손으로 띄우면 인자가 없거나 적고, 더 많은 인자는 뜻이 없다(plan 확정 3).
pub fn argvOf(args: []const [*:0]const u8) Argv {
    var v: Argv = @splat(null);
    const n = @min(args.len, ARGC);
    for (v[0..n], args[0..n]) |*dst, src| dst.* = src;
    return v;
}
