const std = @import("std");
const linux = std.os.linux;

/// main.zig에도 같은 함수가 있다. 세 줄짜리 헬퍼 하나 때문에 공용 모듈을
/// 만드는 것보다 각자 갖고 있는 편이 읽기 쉽다고 판단했다 — 이런 것이
/// 다섯 개쯤 되면 그때 sys.zig로 모은다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 셸이 사용자의 rc 파일을 읽을 것인가(SC design 결정 2).
///
/// **`bool`이 아니라 enum인 데 뜻이 있다.** 이 파일의 다른 키가 전부
/// `stringToEnum` 화이트리스트이고, 그 모양을 따르면 "모르는 값은 로그만
/// 남기고 기본값에 머문다"는 규칙이 공짜로 따라온다. 여섯째 키만 다른
/// 모양일 이유가 없다.
pub const ShellConfig = enum {
    on,
    off,
};

/// 커널 cmdline이 rc를 끄는 토큰(SC design 결정 9). **`tars.conf`를 이기는
/// 것은 이 키 하나뿐이다** — 우선순위는 **cmdline > tars.conf > 기본값**이고,
/// 다른 다섯 키는 cmdline을 안 본다. 그 예외의 근거는 하나다: *"`tars.conf`를
/// 고칠 셸이 없을 때 쓰는 것"*.
pub const NO_CONFIG_TOKEN = "tars.noconfig";

/// 커널 cmdline이 사는 자리. `/proc`은 설정을 읽기 전에 이미 붙어 있다
/// (design 실측 13 — `main.zig`가 `/proc`을 먼저 붙이고 그 다음이 `/config`다).
pub const CMDLINE_PATH: [:0]const u8 = "/proc/cmdline";

/// cmdline 문자열에 위 토큰이 있는가. **시스템 콜이 없는 순수 함수라서
/// `parse`와 같은 성질이다** — 게스트를 안 띄우고 검증할 수 있고,
/// `config_test.zig`가 실제로 그렇게 한다.
///
/// **부분 문자열이 아니라 토큰으로 본다.** `indexOf` 한 줄로 짜면
/// `tars.noconfigured`나 `nottars.noconfig`에도 걸리고, 그 실수의 증상은
/// "부팅했더니 rc가 안 읽힌다" 하나뿐이라 원인에서 아주 멀다.
///
/// **값이 붙어 있어도 받는다**(`tars.noconfig=1`). 이 토큰은 있고 없음이
/// 전부이고 값은 뜻이 없다 — 그래서 값을 본 것을 로그로 알린다. 끄는 방법은
/// `tars.noconfig=0`이 아니라 그 단어를 안 적는 것이다.
pub fn cmdlineWantsNoConfig(text: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (it.next()) |token| {
        const eq = std.mem.indexOfScalar(u8, token, '=') orelse token.len;
        if (!std.mem.eql(u8, token[0..eq], NO_CONFIG_TOKEN)) continue;
        if (eq != token.len) {
            std.debug.print("tars-init: {s} takes no value, '{s}' means the same thing\n", .{
                NO_CONFIG_TOKEN, token,
            });
        }
        return true;
    }
    return false;
}

/// 셸 화이트리스트. 설정 파일에 적을 수 있는 것은 **이름**뿐이고 경로가
/// 아니다 — `shell=/etc/passwd` 같은 입력이 애초에 성립하지 않는다
/// (design doc "5. 설정 하나로 부팅이 막히지 않게 하는 세 장치"의 1번).
pub const Shell = enum {
    fish,
    bash,
    zsh,

    /// 이름 → initrd 안의 바이너리 경로. 화이트리스트의 나머지 절반이다:
    /// enum이 "무엇을 적을 수 있는가"를, 이 switch가 "그것이 무엇을
    /// 실행하는가"를 정한다. 둘을 붙여 두면 Shell에 이름을 하나 더 넣는 순간
    /// switch가 컴파일 에러를 내서 경로를 빼먹을 수 없다.
    ///
    /// 여기 적힌 경로는 kernel/make_initrd.sh가 복사해 넣는 자리와 **같아야
    /// 한다.** 어긋나면 부팅 후 execve 실패로만 드러난다.
    pub fn path(self: Shell) [:0]const u8 {
        return switch (self) {
            .fish => "/usr/bin/fish",
            .bash => "/usr/bin/bash",
            .zsh => "/usr/bin/zsh",
        };
    }

    /// "사용자 설정 파일을 읽지 말라"는 플래그. 셋의 철자가 전부 다르다.
    /// initrd에는 ~/.bashrc도 ~/.zshrc도 없어서 지금은 있으나 없으나 동작이
    /// 같지만, 프롬프트가 예측 가능해야 게이트가 화면을 검사할 수 있다
    /// (TF-M3이 fish에 --no-config를 준 이유가 그것이다).
    pub fn noConfigFlag(self: Shell) [:0]const u8 {
        return switch (self) {
            .fish => "--no-config",
            .bash => "--norc",
            .zsh => "-f",
        };
    }

    /// terminal의 argv에 넣을 값(SC design 결정 3). `off`면 위 플래그이고,
    /// `on`이면 **`"none"`**이다.
    ///
    /// **왜 빈 문자열이나 null이 아닌가.** terminal은 argv를 **짓는 쪽과
    /// 쓰는 쪽이 다르다** — 이 값이 프로세스 경계를 문자열로 건너가므로
    /// "인자가 없다"를 포인터로 표현할 수 없고, 빈 문자열을 넣으면 저쪽에서
    /// "인자를 안 받았다"와 구분이 안 된다. `Toggles.arg`가 빈 집합에
    /// `none`을 쓰는 것과 **글자 그대로 같은 이유다**(아래 그 주석을 볼 것).
    ///
    /// 콘솔 셸은 이 함수를 안 쓴다. 그쪽은 init이 argv를 직접 짓기 때문에
    /// 슬롯을 null로 두면 그만이다.
    pub fn configFlag(self: Shell, sc: ShellConfig) [:0]const u8 {
        return switch (sc) {
            .off => self.noConfigFlag(),
            .on => "none",
        };
    }

    /// 이 셸의 rc 파일이 **설정 디스크에서** 갖는 이름(SC design 결정 1).
    ///
    /// **홈의 이름이 아니라 여기 이름이다.** 홈에는 링크만 있고
    /// (`kernel/make_initrd.sh`가 건다) 실체는 전부 이 자리다 — 홈(`/`)은
    /// tmpfs라 부팅마다 비워지고, 살아남는 것은 `/config` 하나뿐이다.
    ///
    /// | 홈의 이름 | 여기 |
    /// |---|---|
    /// | `/.bashrc` | `/config/bashrc` |
    /// | `/.zshrc` | `/config/zshrc` |
    /// | `/.config/fish/config.fish` | `/config/fish.config` |
    ///
    /// **`fish.config`로 적은 것에 뜻이 있다** — `/config` 안을 평평하게
    /// 두어 `gitconfig`과 같은 층에 세운다(결정 1).
    ///
    /// `main.zig`의 `CONFIG_PATH`가 같은 `/config`를 알고 있다. 둘을 한
    /// 자리로 모으려면 힙 없이 경로를 조립해야 해서, 지금은 **이름 셋이
    /// `make_initrd.sh`의 링크 셋과 짝이라는 것**을 주석으로 못 박는 쪽을
    /// 고른다 — 어긋나면 증상은 "rc를 고쳤는데 안 읽힌다"이고,
    /// `config/check.sh`의 2차 부팅이 그것을 본다.
    pub fn rcPath(self: Shell) [:0]const u8 {
        return switch (self) {
            .fish => "/config/fish.config",
            .bash => "/config/bashrc",
            .zsh => "/config/zshrc",
        };
    }

    /// 씨앗 rc가 담는 훅 줄들(SM design 결정 5). 셸마다 둘이다 — `zoxide`가
    /// "어디에 갔는가"를, `fzf`가 "무엇을 쳤는가"를 이 기계에 잇는다.
    ///
    /// **`command -v`/`type -q` 관문을 지우면 안 된다.** 도구가 없을 때 관문
    /// 없는 훅은 부팅하면서 `command not found`를 찍는다 — zsh 50바이트 ·
    /// bash 38바이트 · **fish 191바이트(6줄)**(SM-M1 실측 27). 그 한 줄이
    /// 설정 디스크를 붙이는 다섯 체인의 화면 좌표를 밀어 버린다. 관문이 있으면
    /// 셋 다 **0바이트**다(실측 23).
    ///
    /// **`fzf`의 통합은 `.deb`의 예제 스크립트가 아니라 바이너리 내장이다**
    /// (결정 7) — `--zsh`/`--bash`/`--fish`가 자동완성까지 함께 낸다. 그래서
    /// 두 줄이 `zoxide`와 대칭으로 생긴다.
    const HOOKS_FISH = [_][]const u8{
        "type -q zoxide && zoxide init fish | source",
        "type -q fzf && fzf --fish | source",
    };
    const HOOKS_BASH = [_][]const u8{
        "command -v zoxide >/dev/null && eval \"$(zoxide init bash)\"",
        "command -v fzf >/dev/null && eval \"$(fzf --bash)\"",
    };
    const HOOKS_ZSH = [_][]const u8{
        "command -v zoxide >/dev/null && eval \"$(zoxide init zsh)\"",
        "command -v fzf >/dev/null && eval \"$(fzf --zsh)\"",
    };

    /// 이 셸의 훅 줄들. **`rcSeed()`가 담는 글자와 여기 글자가 두 벌인 것은
    /// 실수가 아니다**(SM design 결정 10).
    ///
    /// `rcSeed()`를 이 목록에서 `++`로 조립하면 두 벌이 하나가 되고, 그 순간
    /// `config_test.zig`의 **역방향 검사가 tautology가 된다** — "훅이 씨앗에
    /// 있는가"를 묻는데 답이 언제나 참이 되기 때문이다. 이 저장소가 반복해서
    /// 부딪친 자리다(UT-M1의 정적 목록 검사가 같은 이유로 가짜였다).
    ///
    /// **두 벌을 잇는 것은 컴파일러가 아니라 그 검사이고, 그것이 결정 6의
    /// 목적이다** — `HangulLayout` ↔ `hangul.Layout`, `Shell.path()` ↔
    /// `make_initrd.sh`와 같은 종류의 이음매를 이 파일이 이미 둘 갖고 있다.
    pub fn hookLines(self: Shell) []const []const u8 {
        return switch (self) {
            .fish => &HOOKS_FISH,
            .bash => &HOOKS_BASH,
            .zsh => &HOOKS_ZSH,
        };
    }

    /// 첫 부팅에 깔아 두는 내용(결정 7).
    ///
    /// **규칙이 하나뿐이다: 아무것도 찍지 않는다.** 설정 디스크를 붙이는
    /// 체인이 다섯이고 그중 셋이 화면의 셀 좌표로 판정한다 — 씨앗이 배너
    /// 한 줄을 찍으면 그 좌표가 통째로 밀린다. 그래서 여기 쓸 수 있는 줄은
    /// **주석 · alias · 위 `hookLines()`에 글자 그대로 있는 줄** 셋뿐이고,
    /// `config_test.zig`의 `expectQuietSeed`가 그 규칙을 부팅 없이 0.1초에
    /// 확인한다.
    ///
    /// **SM-M1이 그 문을 두 줄만큼 넓혔다.** 넓힌 방식이 "`eval`도 허용"이
    /// 아니라 **정확 허용 목록**인 이유는 결정 6에 있다 — `eval` 뒤에는 아무
    /// 문장이나 올 수 있고, 그러면 이 규칙이 막으려던 것이 그대로 열린다.
    ///
    /// **프롬프트를 안 건드린다**(비목표 5). 실측 9가 그 비용을 적고 있고,
    /// 그 비용은 사용자가 자기 rc에 프롬프트를 쓸 때 **자기 기계에서만**
    /// 치르면 된다.
    ///
    /// 셋의 문법 차이를 나란히 두는 것에도 뜻이 있다 — `shell`을 바꾼
    /// 사용자가 새 셸의 파일을 열었을 때 빈 파일이 아니라 읽을 것이 있다.
    pub fn rcSeed(self: Shell) []const u8 {
        return switch (self) {
            .fish =>
            \\# TARS shell config — fish
            \\#
            \\# 이 파일의 실체는 설정 디스크의 /config/fish.config이고, 홈의
            \\# ~/.config/fish/config.fish는 그리로 가는 링크다. 홈(/)은 tmpfs라
            \\# 부팅마다 비워지므로 살아남는 자리는 설정 디스크 하나뿐이다.
            \\#
            \\# /config/tars.conf에 shell_config=off를 적으면 셸이 이 파일을
            \\# 안 읽는다. 고친 것은 재부팅해야 반영된다 — 지금 적용하려면
            \\# source ~/.config/fish/config.fish
            \\#
            \\# 여기 있는 것이 주석과 alias와 훅 두 줄뿐인 데 이유가 있다: 이
            \\# 파일이 부팅할 때 무언가를 찍으면 게이트가 화면에서 세는 좌표가
            \\# 밀린다. 늘리는 것도 지우는 것도 마음대로지만, 그 대가는 자기
            \\# 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/fish.config'
            \\#
            \\# 아래 둘이 이 기계가 기억하는 법이다.
            \\#   zoxide  어느 디렉터리에 갔는지 — cd할 때마다 배우고 z <조각>으로 간다
            \\#   fzf     무엇을 쳤는지 — Ctrl+R(히스토리) · Ctrl+T(파일) · Alt+C(디렉터리)
            \\#
            \\# type -q 관문을 지우지 말 것. 도구가 없을 때 그것이 없으면 fish가
            \\# 부팅하면서 여섯 줄을 찍고, 그 여섯 줄이 게이트 다섯 체인의 화면
            \\# 좌표를 밀어 버린다.
            \\type -q zoxide && zoxide init fish | source
            \\type -q fzf && fzf --fish | source
            \\
            ,
            .bash =>
            \\# TARS shell config — bash
            \\#
            \\# 이 파일의 실체는 설정 디스크의 /config/bashrc이고, 홈의
            \\# ~/.bashrc는 그리로 가는 링크다. 홈(/)은 tmpfs라 부팅마다
            \\# 비워지므로 살아남는 자리는 설정 디스크 하나뿐이다.
            \\#
            \\# /config/tars.conf에 shell_config=off를 적으면 셸이 이 파일을
            \\# 안 읽는다. 고친 것은 재부팅해야 반영된다 — 지금 적용하려면
            \\# source ~/.bashrc
            \\#
            \\# 여기 있는 것이 주석과 alias와 훅 두 줄뿐인 데 이유가 있다: 이
            \\# 파일이 부팅할 때 무언가를 찍으면 게이트가 화면에서 세는 좌표가
            \\# 밀린다. 늘리는 것도 지우는 것도 마음대로지만, 그 대가는 자기
            \\# 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/bashrc'
            \\#
            \\# 아래 둘이 이 기계가 기억하는 법이다.
            \\#   zoxide  어느 디렉터리에 갔는지 — 프롬프트마다 배우고 z <조각>으로 간다
            \\#   fzf     무엇을 쳤는지 — Ctrl+R(히스토리) · Ctrl+T(파일) · Alt+C(디렉터리)
            \\#
            \\# command -v 관문을 지우지 말 것. 도구가 없을 때 그것이 없으면 bash가
            \\# 부팅하면서 command not found를 찍고, 그 한 줄이 게이트 다섯 체인의
            \\# 화면 좌표를 밀어 버린다.
            \\command -v zoxide >/dev/null && eval "$(zoxide init bash)"
            \\command -v fzf >/dev/null && eval "$(fzf --bash)"
            \\
            ,
            .zsh =>
            \\# TARS shell config — zsh
            \\#
            \\# 이 파일의 실체는 설정 디스크의 /config/zshrc이고, 홈의
            \\# ~/.zshrc는 그리로 가는 링크다. 홈(/)은 tmpfs라 부팅마다
            \\# 비워지므로 살아남는 자리는 설정 디스크 하나뿐이다.
            \\#
            \\# /config/tars.conf에 shell_config=off를 적으면 셸이 이 파일을
            \\# 안 읽는다. 고친 것은 재부팅해야 반영된다 — 지금 적용하려면
            \\# source ~/.zshrc
            \\#
            \\# 여기 있는 것이 주석과 alias와 훅 두 줄뿐인 데 이유가 있다: 이
            \\# 파일이 부팅할 때 무언가를 찍으면 게이트가 화면에서 세는 좌표가
            \\# 밀린다. 늘리는 것도 지우는 것도 마음대로지만, 그 대가는 자기
            \\# 기계에서 치른다.
            \\alias tars-config='cat /config/tars.conf'
            \\alias tars-rc='cat /config/zshrc'
            \\#
            \\# 아래 둘이 이 기계가 기억하는 법이다.
            \\#   zoxide  어느 디렉터리에 갔는지 — cd할 때마다 배우고 z <조각>으로 간다
            \\#   fzf     무엇을 쳤는지 — Ctrl+R(히스토리) · Ctrl+T(파일) · Alt+C(디렉터리)
            \\#
            \\# command -v 관문을 지우지 말 것. 도구가 없을 때 그것이 없으면 zsh가
            \\# 부팅하면서 command not found를 찍고, 그 한 줄이 게이트 다섯 체인의
            \\# 화면 좌표를 밀어 버린다.
            \\command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
            \\command -v fzf >/dev/null && eval "$(fzf --zsh)"
            \\
            ,
        };
    }
};

/// 물리 키보드 종류. **재배치가 아니라 하드웨어 선언이다** — 사용자가 키를
/// 임의로 옮기는 문이 아니라, "스페이스 옆 두 키가 어느 순서인가"라는 사실
/// 하나를 알려주는 것이다(design doc 비목표: 범용 키바인딩 엔진은 안 만든다).
///
/// Shell과 같은 화이트리스트 구조다. enum에 없는 이름은 파싱을 통과할 수
/// 없으므로 검사 목록을 따로 유지할 필요가 없다.
pub const Keyboard = enum {
    apple,
    pc,

    /// terminal에 argv로 넘길 문자열. @tagName은 sentinel이 없는 슬라이스를
    /// 주는데 execve의 argv는 널 종료 문자열이 필요하다 — Shell.path()가
    /// 경로를 [:0]const u8로 돌려주는 것과 같은 이유로 여기서 짝을 맞춘다.
    ///
    /// enum에 이름을 하나 더 넣으면 이 switch가 컴파일 에러를 내서
    /// 빠뜨릴 수 없다.
    pub fn arg(self: Keyboard) [:0]const u8 {
        return switch (self) {
            .apple => "apple",
            .pc => "pc",
        };
    }
};

/// 한글 자판(HI design 결정 7). **`Shell`·`Keyboard`와 같은 화이트리스트
/// 구조다** — enum에 없는 이름은 파싱을 통과할 수 없다.
///
/// **이름이 `terminal/src/hangul.zig`의 `Layout`과 짝이어야 한다.** 여기가
/// "무엇을 적을 수 있는가"이고 저기가 "그것이 어떻게 조합하는가"인데, 둘을
/// 잇는 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다. **어긋나면
/// 증상은 "설정을 적었는데 기본 자판으로 뜬다"이고, 로그에 자판 이름이
/// 찍히므로 HI 게이트가 그것을 본다.**
pub const HangulLayout = enum {
    dubeol,
    sebeol_3p3,
    shin_p2,
    shin_pcs,

    pub fn arg(self: HangulLayout) [:0]const u8 {
        return switch (self) {
            .dubeol => "dubeol",
            .sebeol_3p3 => "sebeol_3p3",
            .shin_p2 => "shin_p2",
            .shin_pcs => "shin_pcs",
        };
    }
};

/// 영문 자판. **한글 자판과 직교한다**(HI design 결정 13) — 한글 배열은
/// 물리 키 위치를 쓰므로 이 값이 무엇이든 안 흔들린다.
pub const LatinLayout = enum {
    qwerty,
    dvorak,

    pub fn arg(self: LatinLayout) [:0]const u8 {
        return switch (self) {
            .qwerty => "qwerty",
            .dvorak => "dvorak",
        };
    }
};

/// 한/영 전환 키(HI design 결정 7).
///
/// **`Shell`·`Keyboard`·자판 둘과 모양이 다른 유일한 설정이다.** 그 넷은
/// 하나를 고르는 것이지만 전환 키는 배타적이지 않다 — 한/영 키를 쓰면서
/// CapsLock도 쓰는 것이 정상이다. 그래서 enum 하나가 아니라 아래 `Toggles`
/// 집합이 값이 되고, 이 enum은 **이름의 화이트리스트** 역할만 한다.
pub const ToggleKey = enum {
    /// 실기의 한/영 키(evdev 122). **게이트가 못 보낸다** — QEMU가
    /// `sendkey lang1`을 이름만 받고 조용히 버린다(HI-M0 실측 1). 그래서 이
    /// 갈래를 덮는 것은 `input_test`의 호스트 검사뿐이다.
    hangul_key,
    /// Shift+Space. HI-M1이 유일한 전환 키로 골랐던 것이고 이제 끌 수 있다 —
    /// `HELLO WORLD`를 칠 때 한/영이 바뀌는 것이 그 대가였다.
    shift_space,
    /// CapsLock을 **짧게** 눌렀다 뗀 것. 길게 누르면 대문자 잠금이다(결정 9).
    capslock_tap,
    /// 왼쪽 Ctrl을 **짧게** 눌렀다 뗀 것. 누른 동안 다른 키가 오면 평범한
    /// modifier이므로 아무 일도 안 일어난다(결정 8).
    lctrl_tap,
};

/// `Toggles.arg`가 만드는 문자열을 담을 버퍼의 크기. 넷을 전부 켠 목록이
/// 45바이트이고 NUL 하나가 더 든다.
pub const TOGGLE_ARG_MAX = 64;

comptime {
    const longest = "hangul_key,shift_space,capslock_tap,lctrl_tap";
    if (longest.len + 1 > TOGGLE_ARG_MAX)
        @compileError("TOGGLE_ARG_MAX is too small for the full toggle list");
}

/// 켜진 전환 키의 집합.
pub const Toggles = struct {
    hangul_key: bool = false,
    shift_space: bool = false,
    capslock_tap: bool = false,
    lctrl_tap: bool = false,

    /// 콤마 목록을 집합으로 바꾼다.
    ///
    /// **모르는 이름은 로그만 남기고 넘어간다** — 설정 파일은 사람이 손으로
    /// 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이라는 CP의 판단 그대로다.
    /// 그 규칙이 **목록 안에서도** 서는 것이 여기서 새로운 점이다: 이름 하나가
    /// 틀려도 나머지는 살아남는다.
    ///
    /// **빈 값(`hangul_toggle=`)은 뜻이 있는 입력이다.** 기본값으로 떨어뜨리지
    /// 않는다 — 그러면 전환 키를 전부 끌 방법이 없어진다.
    pub fn parse(value: []const u8) Toggles {
        var t = Toggles{};
        var it = std.mem.splitScalar(u8, value, ',');
        while (it.next()) |raw| {
            const name = std.mem.trim(u8, raw, " \t");
            if (name.len == 0) continue;
            // `arg()`가 빈 집합에 쓰는 이름이다. **왕복을 위해 여기서 받는다** —
            // 안 받으면 전환 키를 다 끈 사람의 부팅 로그에 매번
            // "모르는 이름 none"이 찍힌다.
            if (std.mem.eql(u8, name, "none")) continue;
            const key = std.meta.stringToEnum(ToggleKey, name) orelse {
                std.debug.print("tars-init: unknown hangul_toggle '{s}', ignored\n", .{name});
                continue;
            };
            switch (key) {
                .hangul_key => t.hangul_key = true,
                .shift_space => t.shift_space = true,
                .capslock_tap => t.capslock_tap = true,
                .lctrl_tap => t.lctrl_tap = true,
            }
        }
        return t;
    }

    /// argv로 넘기고 로그에 찍을 **정규형** 콤마 목록. 버퍼는 호출자가 준다 —
    /// 이 파일에는 힙이 없고, `Keyboard.arg()`처럼 상수 문자열을 돌려줄 수도
    /// 없다(조합이 열여섯 가지다).
    ///
    /// **정규화가 이 함수의 값이다.** 설정 파일에 어떤 순서로 적었든 enum 선언
    /// 순서로 나오므로, 로그에 찍힌 문자열 하나가 곧 집합 전체다. HI 게이트가
    /// 그 줄 하나로 "무엇이 켜지고 무엇이 꺼졌는가"를 본다.
    ///
    /// 하나도 안 켜졌으면 `none`이다 — 빈 문자열을 argv에 넣으면 terminal
    /// 쪽에서 "인자가 없다"와 구분이 안 된다.
    pub fn arg(self: Toggles, buf: []u8) [:0]const u8 {
        var len: usize = 0;
        if (self.hangul_key) appendToggleName(buf, &len, "hangul_key");
        if (self.shift_space) appendToggleName(buf, &len, "shift_space");
        if (self.capslock_tap) appendToggleName(buf, &len, "capslock_tap");
        if (self.lctrl_tap) appendToggleName(buf, &len, "lctrl_tap");
        if (len == 0) appendToggleName(buf, &len, "none");
        buf[len] = 0;
        return buf[0..len :0];
    }
};

/// `Toggles.arg`가 쓰는 이어붙이기. 첫 항목이 아니면 콤마를 먼저 넣는다.
///
/// **모자라면 자른다.** 위 `comptime`이 `TOGGLE_ARG_MAX`가 최악의 경우보다
/// 크다는 것을 못 박으므로 이 길로 실제로 갈 일은 없고, 그래도 배열 밖을
/// 쓰지 않는 쪽으로 적어 둔다. `len.* + 1`을 보는 것은 `buf[len]`에 들어갈
/// NUL 한 칸을 남기기 위해서다.
fn appendToggleName(buf: []u8, len: *usize, name: []const u8) void {
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

/// 설정 전체. 필드의 기본값이 곧 "설정 파일이 없을 때의 TARS"다.
///
/// keyboard의 기본값이 apple인 이유는 이 기계를 쓰는 사람이 Apple 키보드를
/// 먼저 꽂기 때문이다. pc는 보정을 **켜는** 쪽이라 명시적으로 적어야 한다.
pub const Config = struct {
    shell: Shell = .fish,
    keyboard: Keyboard = .apple,
    /// **기본값이 `shin_pcs`인 것은 `keyboard`가 `apple`인 것과 같은
    /// 근거다** — 이 기계를 쓰는 사람이 쓰는 것이 기본값이다. 두벌식이 더
    /// 흔하다는 것은 이 기계의 사실이 아니다.
    hangul_layout: HangulLayout = .shin_pcs,
    latin_layout: LatinLayout = .qwerty,
    /// **기본값은 넷 다 켜진 것이다**(2026-09-01에 사용자가 정했다).
    /// 전환 키가 많아서 곤란한 경우는 없고 없어서 곤란한 경우는 있다 —
    /// 특히 `hangul_key`는 실기에서만 오는 키라 기본으로 꺼 두면 "왜 한/영
    /// 키가 안 먹지"가 된다.
    hangul_toggle: Toggles = .{
        .hangul_key = true,
        .shift_space = true,
        .capslock_tap = true,
        .lctrl_tap = true,
    },
    /// **기본값이 `on`인 근거는 위 `keyboard`·`hangul_layout`과 같다** —
    /// 이 기계를 쓰는 사람이 쓰는 것이 기본값이고, 이 기계는 개발용이다.
    /// embedded 장비의 init 1으로 쓰는 사람은 `keyboard=pc`를 적듯 `off`를
    /// 명시적으로 적는다(design 비목표 4).
    shell_config: ShellConfig = .on,
};

/// 설정 파일을 통째로 담는 스택 버퍼의 크기. 힙이 없으므로 상한이 필요하고,
/// 키가 수십 개가 되어도 4KB를 넘길 일은 없다. 넘치면 잘라서 파싱하고
/// 경고를 찍는다(조용히 무시하지 않는다).
const MAX_FILE = 4096;

/// 설정 파일을 읽어 파싱한다.
///
/// **optional을 돌려주는 이유는 딱 하나를 구분하기 위해서다.** null은 오직
/// "파일이 없다"(ENOENT)는 뜻이고, 그때만 호출자가 seeding(save)을 한다.
/// 파일은 있는데 못 열었거나 못 읽었으면 null이 아니라 기본값 Config를
/// 돌려준다 — 읽기에 실패한 파일을 우리가 덮어써 버리면 사용자가 손으로 쓴
/// 설정이 사라지기 때문이다.
pub fn load(path: [:0]const u8) ?Config {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| {
        if (e == .NOENT) return null;
        std.debug.print("tars-init: failed to open {s} (errno {d})\n", .{
            path, @intFromEnum(e),
        });
        return Config{};
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var buf: [MAX_FILE]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        // read(2)는 요청한 만큼을 다 준다는 보장이 없다. 파일이라 사실상 한
        // 번에 오지만, "돌아온 만큼 더한다"가 이 호출의 계약이다.
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to read {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return Config{};
        }
        if (n == 0) break; // EOF
        len += n;
    }
    if (len == buf.len) {
        std.debug.print("tars-init: {s} is at least {d} bytes, parsing that much only\n", .{
            path, buf.len,
        });
    }

    return parse(buf[0..len]);
}

/// 파일 내용을 Config로 바꾼다. 시스템 콜이 하나도 없는 순수 함수라서, 이
/// 파일에서 유일하게 게스트를 띄우지 않고도 검증할 수 있는 부분이다.
///
/// 규칙(design doc "3. 설정 파일"): `#`으로 시작하면 주석, 빈 줄은 무시,
/// 나머지는 **첫 번째** `=`에서 키와 값으로 나누고 양쪽 공백을 뗀다.
/// 모르는 키와 모르는 값은 로그만 남기고 넘어간다 — 설정 파일은 사용자가
/// 손으로 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이다.
/// **pub인 이유는 config_test.zig가 부르기 때문이다.** 이 파일에서 유일하게
/// 시스템 콜이 없는 함수이고, 그래서 유일하게 게스트를 띄우지 않고 검증할 수
/// 있는 부분이다 — IP-M2가 그 검사를 실제로 만들었다.
pub fn parse(text: []const u8) Config {
    var c = Config{};

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        // \r까지 떼는 것은 사용자가 호스트에서 편집한 파일을 넣을 수도 있기
        // 때문이다. CRLF 한 글자 때문에 값이 "fish\r"가 되면 원인을 찾기 어렵다.
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse {
            std.debug.print("tars-init: config line without '=' ignored: {s}\n", .{line});
            continue;
        };
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, key, "shell")) {
            // stringToEnum이 곧 화이트리스트다. enum에 없는 이름은 통과할 수
            // 없으므로 검사 목록을 따로 유지할 필요가 없다.
            c.shell = std.meta.stringToEnum(Shell, value) orelse {
                std.debug.print("tars-init: unknown shell '{s}', falling back to {s}\n", .{
                    value, @tagName(c.shell),
                });
                continue;
            };
        } else if (std.mem.eql(u8, key, "keyboard")) {
            // shell과 완전히 같은 모양이다. 모르는 값은 로그만 남기고
            // 기본값(apple)에 머문다 — 설정 파일은 사용자가 손으로 고치는
            // 물건이라 깨진 입력이 예외가 아니라 규칙이다.
            c.keyboard = std.meta.stringToEnum(Keyboard, value) orelse {
                std.debug.print("tars-init: unknown keyboard '{s}', falling back to {s}\n", .{
                    value, @tagName(c.keyboard),
                });
                continue;
            };
        } else if (std.mem.eql(u8, key, "hangul_layout")) {
            // shell·keyboard와 완전히 같은 모양이다.
            c.hangul_layout = std.meta.stringToEnum(HangulLayout, value) orelse {
                std.debug.print("tars-init: unknown hangul_layout '{s}', falling back to {s}\n", .{
                    value, @tagName(c.hangul_layout),
                });
                continue;
            };
        } else if (std.mem.eql(u8, key, "latin_layout")) {
            c.latin_layout = std.meta.stringToEnum(LatinLayout, value) orelse {
                std.debug.print("tars-init: unknown latin_layout '{s}', falling back to {s}\n", .{
                    value, @tagName(c.latin_layout),
                });
                continue;
            };
        } else if (std.mem.eql(u8, key, "hangul_toggle")) {
            // **앞의 넷과 모양이 다른 유일한 키다**(결정 7). `stringToEnum`
            // 하나로 안 끝나고 콤마로 갈라야 한다. 모르는 이름을 흘려보내는
            // 규칙은 같고, 그 규칙이 **목록 안에서도** 선다.
            c.hangul_toggle = Toggles.parse(value);
        } else if (std.mem.eql(u8, key, "shell_config")) {
            // shell·keyboard·자판 둘과 완전히 같은 모양이다. `hangul_toggle`만
            // 집합이라 다르고, 여섯째 키는 다시 enum 하나다.
            c.shell_config = std.meta.stringToEnum(ShellConfig, value) orelse {
                std.debug.print("tars-init: unknown shell_config '{s}', falling back to {s}\n", .{
                    value, @tagName(c.shell_config),
                });
                continue;
            };
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
    }

    return c;
}

pub const SaveError = error{
    FormatFailed,
    OpenFailed,
    WriteFailed,
};

/// 설정을 파일로 쓴다. 이번 범위에서 이 함수의 유일한 호출자는 first-boot
/// seeding이다 — 빈 디스크로 처음 부팅하면 init이 기본 설정을 주석과 함께
/// 만들어 둔다. 그래야 사용자가 빈 디렉터리 앞에서 무엇을 쓸 수 있는지 알게
/// 되고, "쓰기" 코드가 아무도 부르지 않는 죽은 코드가 되지 않는다.
///
/// 파일 내용을 상수 문자열로 박지 않고 Config에서 만들어 내는 이유는 진실의
/// 출처를 하나로 두기 위해서다. Config의 기본값을 바꾸면 씨앗 파일도 따라
/// 바뀐다.
pub fn save(path: [:0]const u8, c: Config) SaveError!void {
    var buf: [MAX_FILE]u8 = undefined;
    // `Toggles`만 상수 문자열이 아니라 조립해야 한다(조합이 열여섯 가지다).
    // 이 배열은 아래 bufPrint가 값을 복사할 때까지만 살아 있으면 된다.
    var toggle_buf: [TOGGLE_ARG_MAX]u8 = undefined;
    const text = std.fmt.bufPrint(&buf,
        \\# TARS configuration. Edit and reboot to apply.
        \\# shell: fish | bash | zsh
        \\shell={s}
        \\# keyboard: apple | pc
        \\#   apple = [Ctrl][Option][Cmd], pc = [Ctrl][Win][Alt]
        \\keyboard={s}
        \\# hangul_layout: dubeol | sebeol_3p3 | shin_p2 | shin_pcs
        \\hangul_layout={s}
        \\# latin_layout: qwerty | dvorak
        \\#   한글 자판은 물리 키 위치를 쓰므로 이 값에 안 흔들린다
        \\latin_layout={s}
        \\# hangul_toggle: hangul_key | shift_space | capslock_tap | lctrl_tap
        \\#   콤마로 여럿을 켠다. 빈 값이면 전환 키가 하나도 없다
        \\#   CapsLock과 왼쪽 Ctrl은 0.3초보다 **짧게** 눌렀다 뗐을 때만 한/영이고,
        \\#   길게 누르면 CapsLock은 대문자 잠금, Ctrl은 평소의 Ctrl이다
        \\hangul_toggle={s}
        \\# shell_config: on | off
        \\#   on이면 셸이 홈의 rc 파일을 읽는다. 그 파일들은 /config에 있고
        \\#   홈에는 링크만 있다 — /config/bashrc · /config/zshrc ·
        \\#   /config/fish.config. off면 셸이 설정 없이 뜬다
        \\shell_config={s}
        \\
    , .{
        @tagName(c.shell),
        @tagName(c.keyboard),
        @tagName(c.hangul_layout),
        @tagName(c.latin_layout),
        c.hangul_toggle.arg(&toggle_buf),
        @tagName(c.shell_config),
    }) catch return error.FormatFailed;

    // O_EXCL을 쓰지 않는다. "파일이 있는가"는 load가 이미 답했고, save의
    // 계약은 "이 내용으로 만든다"이다. O_TRUNC는 나중에 이 함수가 갱신에도
    // 쓰일 때 남은 꼬리가 붙지 않게 한다.
    const rc = linux.open(path.ptr, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to create {s} (errno {d})\n", .{
            path, @intFromEnum(e),
        });
        return error.OpenFailed;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    return writeAll(fd, text, path);
}

/// fd에 전부 쓴다. **`save`와 `seedRcFiles`가 같은 루프를 쓴다** — SC-M1이
/// 둘째 호출자를 만들면서 뺐다.
///
/// `/config`는 `MS_SYNCHRONOUS`로 마운트돼 있다. 그래서 이 write가 돌아온
/// 시점에 데이터도 디렉터리 엔트리도 이미 디스크에 있다 — fsync를 따로
/// 부르지 않는 것이 실수가 아니라 그 마운트 플래그의 값어치다.
fn writeAll(fd: i32, text: []const u8, path: [:0]const u8) SaveError!void {
    var written: usize = 0;
    while (written < text.len) {
        const n = linux.write(fd, text.ptr + written, text.len - written);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to write {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return error.WriteFailed;
        }
        if (n == 0) return error.WriteFailed;
        written += n;
    }
}

/// 셸 rc 파일 셋을 "없으면 만든다"(SC design 결정 7).
///
/// **`/config`가 마운트됐을 때만 부른다.** 안 붙은 부팅에서는 `/config`가
/// initrd 안의 빈 디렉터리(tmpfs)이므로, 여기서 만들면 부팅마다 새로 생겼다
/// 사라지는 파일이 되고 "고치고 재부팅하면 남는다"는 약속이 그 부팅에서만
/// 거짓이 된다. **없는 편이 낫다** — 링크가 끊긴 채로 셸이 뜨고, 그것은
/// SC-M0이 이미 여섯 체인에서 확인한 정상 경로다.
///
/// **`shell_config`를 안 본다.** `off`여도 깐다 — 셸이 안 읽을 뿐 파일은
/// 있는 것이 맞고, 나중에 `on`으로 바꾼 사람이 빈 디렉터리를 안 만난다.
/// `shell`도 안 본다: 셋 다 깐다는 결정 7의 근거가 같다 — `tars.conf`의
/// `shell`은 언제든 바뀔 수 있고, 바뀐 뒤에야 씨앗이 생기면 "고치고
/// 재부팅했는데 rc가 없다"가 된다. 비용은 부팅마다 `open()` 셋이다.
///
/// **이미 있으면 손대지 않는다.** 그때부터 그 파일은 사용자의 것이다.
/// `O_EXCL`이 그 질문을 커널에게 한 번에 묻는다 — `save`가 `O_EXCL`을 안
/// 쓰는 것과 다른 이유는, 저쪽은 "파일이 없다"를 `load`가 이미 답했기
/// 때문이다.
pub fn seedRcFiles() void {
    for (std.enums.values(Shell)) |sh| seedRcFile(sh);
}

fn seedRcFile(sh: Shell) void {
    const path = sh.rcPath();
    const rc = linux.open(path.ptr, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .EXCL = true,
    }, 0o644);
    if (failed(rc)) |e| {
        // 이미 있다 = 사용자의 파일이다. 조용히 둔다 — 여기서 로그를 찍으면
        // 부팅마다 세 줄이 늘고, 그 셋은 아무것도 알려주지 않는다.
        if (e == .EXIST) return;
        std.debug.print("tars-init: could not seed {s} (errno {d})\n", .{
            path, @intFromEnum(e),
        });
        return;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    writeAll(fd, sh.rcSeed(), path) catch return;

    // **`created`가 아니라 `seeded`다.** `tars-init: created /config/tars.conf`
    // 를 config 체인이 1차·2차 부팅의 판정으로 쓰고 있어서, 앞부분이 겹치면
    // 그 검사가 rc 세 줄까지 함께 보게 된다.
    std.debug.print("tars-init: seeded {s}\n", .{path});
}

/// `/proc/cmdline`을 읽어 `NO_CONFIG_TOKEN`이 있는지 본다(SC-M2 결정 9).
///
/// **못 읽으면 false다.** 이 함수의 답은 "사용자의 설정을 덮어쓸까"이고,
/// 못 읽었을 때 덮는 쪽으로 기울면 `/proc`이 안 붙은 부팅에서 rc가 조용히
/// 꺼진다 — `load`가 "읽기에 실패한 파일은 덮어쓰지 않는다"고 정한 것과 같은
/// 방향이다.
///
/// **`load`의 읽기 루프를 공유하지 않는다.** 저쪽은 optional로 ENOENT 하나를
/// 구분해야 해서 계약이 다르다(그 구분이 seeding을 부르는 조건이다). 세 줄을
/// 아끼려고 그 구분을 흐리는 것보다 각자 갖는 편이 읽기 쉽다 — 이 파일 머리의
/// `failed`가 `main.zig`와 겹치는 것과 같은 판단이다.
pub fn cmdlineNoConfig(path: [:0]const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: cannot read {s} (errno {d}), assuming no {s}\n", .{
            path, @intFromEnum(e), NO_CONFIG_TOKEN,
        });
        return false;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    // x86의 COMMAND_LINE_SIZE가 2048이라 MAX_FILE 안에 넉넉히 들어간다.
    var buf: [MAX_FILE]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to read {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return false;
        }
        if (n == 0) break;
        len += n;
    }
    return cmdlineWantsNoConfig(buf[0..len]);
}
