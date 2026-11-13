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
///
/// `apple` · `pc`는 모든 키보드에 같은 값을 강제한다. `auto`는 terminal이 키보드를
/// 열 때마다 vendor로 고른다 — Apple이면 `apple`, 아니면 `pc`(KK design 결정 1 · 2).
pub const Keyboard = enum {
    apple,
    pc,
    auto,

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

/// 휠 방향(PS design 결정 1 · 2). 마우스와 터치패드가 따로 하나씩 든다 — terminal이
/// 장치를 열 때 그 장치의 종류로 둘 중 하나를 고른다(`pointer.wheelSign`).
///
/// `normal`은 "휠을 앞으로 밀거나 손가락을 위로 밀면 위의 글이 보인다"(리눅스 · 윈도우의
/// 마우스), `natural`은 "내용이 휠 · 손가락을 따라간다"(macOS)이다. 이름은 macOS의
/// "자연스러운 스크롤"에서 왔다. `pointer.zig`의 `Scroll`(끄는 중의 휠)과 겹치지 않게
/// 이름이 `WheelDirection`이다(PS-M0 plan 확정 1).
pub const WheelDirection = enum {
    normal,
    natural,

    pub fn arg(self: WheelDirection) [:0]const u8 {
        return @tagName(self);
    }
};

/// 포인터 가속의 단계(PS design 결정 3). 0은 가속 없음이고 지금 동작과 같다. 10이 가장
/// 세다. 범위가 0~10인 것은 사용자가 정했다(2026-11-04) — 실기 근거 없이 그보다 잘게
/// 가를 수 없다.
///
/// 맨 `u4`가 아니라 구조체인 것은 init의 `reload.same` · `reload.text` ·
/// `config_edit.fieldText` · `hintFor`가 `Ntp` · `Timezone`처럼 타입으로 갈래를 고르기
/// 때문이다(PS-M0 plan 확정 2). `u4`면 다른 정수 필드와 구분이 안 된다.
pub const Accel = struct {
    level: u4 = 0,

    pub const MAX = 10;

    /// 10진 정수 하나. 부호 · 공백 · 다른 글자가 붙으면 거절한다 — 설정 파일의 값은
    /// 이미 앞뒤 공백이 벗겨져 온다. 범위 밖은 잘라 쓰지 않고 거절한다(PS design 결정 6):
    /// `11`을 10으로 올리면 사람이 적은 것과 다른 값이 조용히 쓰인다.
    pub fn parse(text: []const u8) ?Accel {
        if (text.len == 0 or text.len > 2) return null;
        var n: u8 = 0;
        for (text) |ch| {
            if (ch < '0' or ch > '9') return null;
            n = n * 10 + (ch - '0');
        }
        if (n > MAX) return null;
        return .{ .level = @intCast(n) };
    }

    /// argv에 넣고 로그에 찍을 글자. 표에서 고르므로 버퍼가 필요 없다 — `@tagName`처럼
    /// sentinel이 있는 상수 글자다.
    pub fn arg(self: Accel) [:0]const u8 {
        const names = [_][:0]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" };
        return names[@min(self.level, MAX)];
    }

    pub fn eql(a: Accel, b: Accel) bool {
        return a.level == b.level;
    }
};

/// 화면 배율(HS design 결정 3). `auto`는 terminal이 화면을 연 뒤 물리 해상도로 고른다 —
/// 논리 화면이 1280×800보다 작아지지 않는 가장 큰 정수, 1~3(`drm.pickScale`). 숫자 셋은 그
/// 배율을 강제한다. 이름이 숫자인 enum이라 `@tagName`이 곧 설정 파일과 argv의 글자이고,
/// init의 `parse` · `hint` · `reload.same`이 다른 enum 키와 같은 길로 다룬다.
///
/// 소수 배율(1.5)은 이름이 없다(HS design 비목표 1) — 비트맵 폰트를 늘리는 이 방식은
/// 정수배만 선명하다.
pub const DisplayScale = enum {
    auto,
    @"1",
    @"2",
    @"3",

    pub fn arg(self: DisplayScale) [:0]const u8 {
        return @tagName(self);
    }

    /// 강제한 배율. `auto`면 null이고 고르는 것은 화면을 연 쪽이다.
    pub fn fixed(self: DisplayScale) ?u32 {
        return switch (self) {
            .auto => null,
            .@"1" => 1,
            .@"2" => 2,
            .@"3" => 3,
        };
    }
};

/// 전체 화면(FU design 결정 4). 부팅 때의 시작 상태다 — 실행 중에는 `Cmd+Ctrl+F`와 패널의
/// `CSI 10 ; Ps t`가 바꾸고, 그 상태는 설정 파일로 돌아가지 않는다.
pub const Fullscreen = enum {
    off,
    on,

    pub fn arg(self: Fullscreen) [:0]const u8 {
        return @tagName(self);
    }
};

/// 프로그램이 DECSCUSR로 정하지 않았을 때의 커서 모양(CO design 결정 5 · 6). terminal이 lib-vt의
/// `default_cursor_style`로 준다 — `CSI 0 SP q`와 RIS가 이 모양으로 돌아간다. 이름은 terminal의
/// `vt.CursorShape`와 같지만 이 파일은 vt를 import하지 않으므로 따로 둔다(`Fullscreen`처럼).
pub const CursorShape = enum {
    block,
    bar,
    underline,

    pub fn arg(self: CursorShape) [:0]const u8 {
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
/// 서비스 셋의 argv도 같은 길이라 그쪽은 null이 하나 늘 뿐이다. PS-M0이 포인터 칸 넷을 더해 열셋이고,
/// HS-M0이 배율 칸 하나를 더해 열넷이다.
///
/// IK-M0에서 4번 칸(키보드 장치 경로, HD-M0)이 빠지고 뒤 다섯이 하나씩 당겨졌다.
/// KH부터 terminal이 키보드를 스스로 고르고 열어 그 칸을 읽기만 했다. 비워 두지
/// 않고 뺀 것은 execve의 argv가 첫 null에서 끝나서다 — null로 비우면 뒤 칸이 잘린다.
pub const Slot = enum(u8) {
    /// 셸 경로. init이 `resolveShell`로 정한다.
    shell = 1,
    /// 셸에 넘길 플래그 — `--no-config` 같은 것, 또는 "아무것도 안 붙인다"는 뜻의
    /// `none`(SC design 결정 3). 탈출로가 덮는 자리다(결정 8).
    flag = 2,
    keyboard = 3,
    hangul = 4,
    latin = 5,
    /// `Toggles.arg`의 글자 — 파일의 `hangul_toggle`에 `esc_latin`을 합친 것.
    toggles = 6,
    clipboard = 7,
    /// 화면 셸을 띄울 사용자 이름, 또는 root로 띄운다는 뜻의 `NO_USER`(HP design 결정 3 · 8).
    /// init이 `/home`이 붙고 `tars.conf`에 `user=`가 있을 때만 이름을 넣는다.
    user = 8,
    /// 포인터 설정 넷(PS design 결정 5). 방향 둘은 `WheelDirection`, 가속 둘은 `Accel`의 글자다.
    mouse_scroll = 9,
    touchpad_scroll = 10,
    mouse_accel = 11,
    touchpad_accel = 12,
    /// 화면 배율(HS design 결정 4). `DisplayScale`의 글자다.
    display_scale = 13,
    /// 전체 화면의 시작 상태(FU design 결정 4). `Fullscreen`의 글자다.
    fullscreen = 14,
    /// 프로그램이 정하지 않았을 때의 커서 모양(CO design 결정 5). `CursorShape`의 글자다.
    cursor_shape = 15,

    /// 배열 인덱스. `encode` · `decode`가 칸을 가리키는 길이고, 밖에서는 init의
    /// 탈출로(`Rescue.slot`) 하나만 쓴다 — 그 자리는 terminal과 콘솔 셸을 같은 코드로
    /// 다루므로 `Args`를 모르는 편이 맞다(SA-M1 plan 확정 5).
    pub fn index(self: Slot) usize {
        return @backingInt(self);
    }
};

/// argv 배열의 길이. `Argv`가 init의 `Child.argv`와 서비스 셋의 `*_ARGV` 상수의
/// 타입이다. CO-M1이 커서 모양 칸 하나를 더해 열여섯이다.
pub const ARGC = 16;

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
pub const default_keyboard: Keyboard = .auto;
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
/// `user` 칸의 "사용자 없음" — 화면 셸이 root로 뜬다. init 없이 띄운 terminal도 이 값이다.
pub const NO_USER: [:0]const u8 = "none";
pub const default_user: [*:0]const u8 = NO_USER.ptr;
/// 포인터 넷(PS design 결정 2 · 3). 방향은 지금 동작 그대로, 가속은 끔.
pub const default_mouse_scroll: WheelDirection = .normal;
pub const default_touchpad_scroll: WheelDirection = .natural;
pub const default_mouse_accel: Accel = .{};
pub const default_touchpad_accel: Accel = .{};
/// 화면 배율(HS design 결정 3). 1280×800 이하의 화면에서는 1이라 HS 전과 같다.
pub const default_display_scale: DisplayScale = .auto;
/// 전체 화면(FU design 결정 4). 꺼짐이라 FU 전과 같다.
pub const default_fullscreen: Fullscreen = .off;
/// 커서 모양(CO design 결정 5). block이라 CO 전과 같다.
pub const default_cursor_shape: CursorShape = .block;

// ── 계정의 번호(HP design 결정 5 · 8) ──────────────────────────────────
//
// TARS의 사용자는 하나이고 번호가 고정이다. 세 프로그램이 이 상수 하나를 본다 —
// 설치기(홈 디렉터리의 chown), init(passwd · group 줄), terminal(셸 자식의 setuid · pty
// chown). 어긋나면 증상은 "홈이 남의 것"이거나 "셸이 자기 tty를 못 연다"이고 원인에서 멀다.

/// 사용자의 uid, 그리고 같은 이름의 그룹 gid.
pub const USER_UID: u32 = 1000;
pub const USER_GID: u32 = 1000;
/// devpts의 그룹. init이 `gid=5`로 devpts를 붙이고 terminal이 셸의 pty를 이 그룹으로 준다.
/// 5는 Debian의 번호다.
pub const TTY_GID: u32 = 5;
/// 사용자의 보조 그룹 하나. alsa-lib의 dmix가 이 그룹을 찾는다(`make_initrd.sh`의 AU-M0 주석).
pub const AUDIO_GID: u32 = 29;
/// 사용자의 둘째 보조 그룹. `/etc/sudoers`의 `%sudo` 줄이 이 그룹에 root 권한을 준다(HP-M2 plan
/// 확정 3 — 사용자 이름이 아니라 그룹이라 sudoers가 initrd의 정적 파일로 남는다). 27은 Debian의 번호다.
pub const SUDO_GID: u32 = 27;
/// 사용자의 셋째 보조 그룹. init이 `/dev/dri`의 노드를 `root:video 0660`으로 열어 화면 셸의 프로그램이
/// terminal이 양보한 화면을 잡는다(DY design 결정 7). 44는 Debian의 번호다.
pub const VIDEO_GID: u32 = 44;

/// terminal argv의 값 전체(SA design 결정 7). init이 채우고 terminal이 읽는 것은 이
/// 구조체 하나이고, 칸 번호와 글자는 아래 `encode` · `decode` 안에만 있다.
///
/// 값을 타입으로 든다 — 전환 키는 `Toggles`(집합)이고 글자가 아니다. 글자는 `encode`
/// 안에서만 생기고 `decode`가 되돌린다. 기본값이 없는 것은 일부러다: init이 필드 하나를
/// 빠뜨리면 컴파일이 막혀야 한다. SA-M0까지는 `Slot`에 이름을 더하고 그 칸을 안 채워도
/// 통과했다(null일 뿐이다). 없는 칸의 기본값은 `decode`의 일이다.
///
/// 포인터 셋(`shell_path` · `shell_flag` · `user`)은 소유하지 않는다. init에서는
/// `main()`의 스택과 `Live`를 가리키고 프로세스 수명 내내 유효하다 — terminal에서는
/// 커널이 준 argv다.
pub const Args = struct {
    shell_path: [*:0]const u8,
    shell_flag: [*:0]const u8,
    keyboard: Keyboard,
    hangul: HangulLayout,
    latin: LatinLayout,
    toggles: Toggles,
    clipboard: ClipboardScope,
    /// 사용자 이름이거나 `NO_USER`. init에서는 `Config.user`의 버퍼를 가리킨다.
    user: [*:0]const u8,
    mouse_scroll: WheelDirection,
    touchpad_scroll: WheelDirection,
    mouse_accel: Accel,
    touchpad_accel: Accel,
    display_scale: DisplayScale,
    fullscreen: Fullscreen,
    cursor_shape: CursorShape,
};

/// `Args`에서 argv를 짓는다. 0번은 `TERMINAL_PATH`다.
///
/// `toggle_buf`는 호출자가 들고 argv가 살아 있는 동안 유지한다 — init에는 힙이 없다.
/// 부팅은 `main()`의 `terminal_toggle_buf`, `reload terminal`은 `Live.toggle`이다
/// (SA-M1 plan 확정 2). `Toggles.arg`가 그 버퍼에 글자를 쓰고 그 포인터가 6번 칸이다.
pub fn encode(a: Args, toggle_buf: *[TOGGLE_ARG_MAX]u8) Argv {
    var v: Argv = @splat(null);
    v[0] = TERMINAL_PATH.ptr;
    v[Slot.shell.index()] = a.shell_path;
    v[Slot.flag.index()] = a.shell_flag;
    v[Slot.keyboard.index()] = a.keyboard.arg().ptr;
    v[Slot.hangul.index()] = a.hangul.arg().ptr;
    v[Slot.latin.index()] = a.latin.arg().ptr;
    v[Slot.toggles.index()] = a.toggles.arg(toggle_buf).ptr;
    v[Slot.clipboard.index()] = a.clipboard.arg().ptr;
    v[Slot.user.index()] = a.user;
    v[Slot.mouse_scroll.index()] = a.mouse_scroll.arg().ptr;
    v[Slot.touchpad_scroll.index()] = a.touchpad_scroll.arg().ptr;
    v[Slot.mouse_accel.index()] = a.mouse_accel.arg().ptr;
    v[Slot.touchpad_accel.index()] = a.touchpad_accel.arg().ptr;
    v[Slot.display_scale.index()] = a.display_scale.arg().ptr;
    v[Slot.fullscreen.index()] = a.fullscreen.arg().ptr;
    v[Slot.cursor_shape.index()] = a.cursor_shape.arg().ptr;
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
/// 바꾸고 다시 `encode`한다. `user`가 그대로 되돌아가는 것이 "부팅 때 정해져 안
/// 건드린다"를 코드로 세우는 자리다(SA-M1 plan 확정 4는 IK-M0에 빠진 장치 경로로 이것을 세웠다).
pub fn decode(v: Argv) Args {
    return .{
        .shell_path = v[Slot.shell.index()] orelse default_shell_path,
        .shell_flag = v[Slot.flag.index()] orelse default_shell_flag,
        .keyboard = enumAt(Keyboard, v, .keyboard, default_keyboard),
        .hangul = enumAt(HangulLayout, v, .hangul, default_hangul),
        .latin = enumAt(LatinLayout, v, .latin, default_latin),
        .toggles = if (v[Slot.toggles.index()]) |t|
            Toggles.parse(.argv, std.mem.span(t), ignore_unknown)
        else
            default_toggles,
        .clipboard = enumAt(ClipboardScope, v, .clipboard, default_clipboard),
        .user = v[Slot.user.index()] orelse default_user,
        .mouse_scroll = enumAt(WheelDirection, v, .mouse_scroll, default_mouse_scroll),
        .touchpad_scroll = enumAt(WheelDirection, v, .touchpad_scroll, default_touchpad_scroll),
        .mouse_accel = accelAt(v, .mouse_accel, default_mouse_accel),
        .touchpad_accel = accelAt(v, .touchpad_accel, default_touchpad_accel),
        .display_scale = enumAt(DisplayScale, v, .display_scale, default_display_scale),
        .fullscreen = enumAt(Fullscreen, v, .fullscreen, default_fullscreen),
        .cursor_shape = enumAt(CursorShape, v, .cursor_shape, default_cursor_shape),
    };
}

/// `decode`의 가속 칸 하나. 0~10 밖이거나 숫자가 아니면 기본값이다.
fn accelAt(v: Argv, s: Slot, default: Accel) Accel {
    const raw = v[s.index()] orelse return default;
    return Accel.parse(std.mem.span(raw)) orelse default;
}

/// `decode`의 enum 칸 하나.
fn enumAt(comptime T: type, v: Argv, s: Slot, default: T) T {
    const raw = v[s.index()] orelse return default;
    return std.meta.stringToEnum(T, std.mem.span(raw)) orelse default;
}

/// 커널이 준 argv(`std.process.Init.minimal.args.vector`, 길이가 가변인 슬라이스)를
/// `decode`가 받는 열 칸으로 옮긴다. 앞 `ARGC`칸까지만 보고 남는 칸은 null이다 —
/// 손으로 띄우면 인자가 없거나 적고, 더 많은 인자는 뜻이 없다(plan 확정 3).
pub fn argvOf(args: []const [*:0]const u8) Argv {
    var v: Argv = @splat(null);
    const n = @min(args.len, ARGC);
    for (v[0..n], args[0..n]) |*dst, src| dst.* = src;
    return v;
}
