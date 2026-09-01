const std = @import("std");
const linux = std.os.linux;

/// main.zig에도 같은 함수가 있다. 세 줄짜리 헬퍼 하나 때문에 공용 모듈을
/// 만드는 것보다 각자 갖고 있는 편이 읽기 쉽다고 판단했다 — 이런 것이
/// 다섯 개쯤 되면 그때 sys.zig로 모은다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
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
        \\
    , .{
        @tagName(c.shell),
        @tagName(c.keyboard),
        @tagName(c.hangul_layout),
        @tagName(c.latin_layout),
        c.hangul_toggle.arg(&toggle_buf),
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

    // /config는 MS_SYNCHRONOUS로 마운트돼 있다. 그래서 이 write가 돌아온
    // 시점에 데이터도 디렉터리 엔트리도 이미 디스크에 있다 — fsync를 따로
    // 부르지 않는 것이 실수가 아니라 그 마운트 플래그의 값어치다.
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
