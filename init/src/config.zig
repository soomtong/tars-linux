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
/// `bool`이 아니라 enum인 데 뜻이 있다. 이 파일의 다른 키가 전부
/// `stringToEnum` 화이트리스트이고, 그 모양을 따르면 "모르는 값은 로그만
/// 남기고 기본값에 머문다"는 규칙이 공짜로 따라온다. 여섯째 키만 다른
/// 모양일 이유가 없다.
pub const ShellConfig = enum {
    on,
    off,
};

/// 이 기계가 네트워크를 켜는가(NW design 결정 5).
///
/// 기본값이 `off`인 것이 게이트를 지킨다. 부팅 수십 개가 전부 DHCP 응답을
/// 기다리면 시간이 늘고 잡음도 는다 — 기본값을 꺼짐으로 두고 네트워크 체인만
/// 켜면 기존 부팅의 시간이 한 밀리초도 안 는다.
///
/// `static:...` 같은 셋째 값은 안 만든다. 만들 근거가 아직 없고, 쓸 자리가
/// 생기면 그때 더한다.
pub const Net = enum {
    off,
    dhcp,
};

/// 점 넷으로 적은 IPv4 주소를 바이트 넷으로 바꾼다. 시스템 콜이 없는 순수
/// 함수이고, 이 파일에서 `parse`·`cmdlineWantsNoConfig`와 같은 성질이다.
///
/// 이 저장소의 첫 자유 문자열 설정 값이라 파서가 필요해졌다(TS 확인 9).
/// 다른 일곱 키는 전부 `stringToEnum` 화이트리스트라 "모르는 값은 기본값"이
/// 공짜로 따라왔는데, 주소는 그 수법이 안 선다.
///
/// `inet_aton`과 다르게 구는 자리가 하나다 — `010`을 8이 아니라 10으로
/// 읽는다. 8진수 해석은 사람을 놀라게 하는 쪽이고, 설정 파일은 사람이 손으로
/// 고치는 물건이다.
///
/// 이 함수가 `sntp.zig`가 아니라 여기 있는 이유는 import 방향이다(TS-M1
/// plan 결정 M1-C). `net.zig`가 `config.Net`을 받고 `config.zig`는 `net`을
/// 모르는데, 주소 파서를 저쪽에 두면 그 방향이 순환한다.
///
/// 힙이 없으므로 돌려주는 것이 배열이다. optional이라 "못 읽었다"가 값으로
/// 온다.
pub fn parseIpv4(text: []const u8) ?[4]u8 {
    var out: [4]u8 = undefined;
    var i: usize = 0;
    var it = std.mem.splitScalar(u8, text, '.');
    while (it.next()) |part| {
        // 다섯째 조각이 오면 주소가 아니다. `1.2.3.4.5`가 여기서 걸린다.
        if (i == 4) return null;
        if (part.len == 0 or part.len > 3) return null;
        var v: u16 = 0;
        for (part) |ch| {
            if (ch < '0' or ch > '9') return null;
            v = v * 10 + (ch - '0');
        }
        if (v > 255) return null;
        out[i] = @intCast(v);
        i += 1;
    }
    // 조각이 넷이 아니면 주소가 아니다. `1.2.3`이 여기서 걸린다.
    if (i != 4) return null;
    return out;
}

/// `Ntp.arg`가 만드는 문자열을 담을 버퍼의 크기. 가장 긴 것이
/// `255.255.255.255` 15바이트이고 NUL 하나가 더 든다.
pub const NTP_ARG_MAX = 16;

comptime {
    const longest = "255.255.255.255";
    if (longest.len + 1 > NTP_ARG_MAX)
        @compileError("NTP_ARG_MAX is too small for a dotted quad");
}

/// 부팅할 때 시각을 어디에 묻는가(TS design 결정 5).
///
/// 키 하나가 "켜고 끄는 것"과 "어디에 묻는지"를 함께 정한다. 그래서 "켰는데
/// 어디에 물을지를 안 적은" 모순 상태가 구조적으로 없다.
///
/// `Net`과 달리 enum이 아니라 union인 이유는 셋째 값이 자유 문자열이기
/// 때문이다. 이것이 이 파일에서 `stringToEnum` 화이트리스트가 아닌 두 번째
/// 값이고(앞은 `Toggles`), 둘 다 파싱 함수를 자기가 갖는다.
///
/// 이름이 아니라 주소만 받는 근거는 `init`에 resolver가 없다는 것이다
/// (design 결정 5). libc도 힙도 없으므로 `pool.ntp.org`를 풀려면 DNS
/// 클라이언트를 직접 써야 하고, 그러면 이 사이클이 "시계 맞추기"에서
/// "DNS 구현하기"로 넘어간다.
pub const Ntp = union(enum) {
    off,
    dhcp,
    server: [4]u8,

    /// 설정 파일의 값을 이 타입으로 바꾼다. 모르는 값이면 null이고,
    /// 호출자가 로그를 찍고 기본값에 머문다 — 다른 일곱 키와 같은 규칙이다.
    pub fn parse(value: []const u8) ?Ntp {
        if (std.mem.eql(u8, value, "off")) return .off;
        if (std.mem.eql(u8, value, "dhcp")) return .dhcp;
        const ip = parseIpv4(value) orelse return null;
        return .{ .server = ip };
    }

    /// 로그와 씨앗 파일에 찍을 정규형. 버퍼는 호출자가 준다 —
    /// `Toggles.arg`와 같은 이유로, 이 파일에는 힙이 없고 주소는 상수
    /// 문자열로 돌려줄 수가 없다.
    pub fn arg(self: Ntp, buf: []u8) [:0]const u8 {
        switch (self) {
            .off => return "off",
            .dhcp => return "dhcp",
            .server => |ip| {
                const text = std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{
                    ip[0], ip[1], ip[2], ip[3],
                }) catch return "off";
                buf[text.len] = 0;
                return buf[0..text.len :0];
            },
        }
    }

    /// 두 값이 같은가. `config_test`의 필드 비교가 쓴다 — union은 `==`로
    /// 비교되지 않고, 그 자리에 `std.meta.eql`을 쓰면 검사가 무엇을 보는지가
    /// 흐려진다.
    pub fn eql(self: Ntp, other: Ntp) bool {
        return switch (self) {
            .off => other == .off,
            .dhcp => other == .dhcp,
            .server => |a| switch (other) {
                .server => |b| std.mem.eql(u8, &a, &b),
                else => false,
            },
        };
    }
};

/// `timezone` 값의 최대 길이(NUL 제외). trixie의 tzdata에서 가장 긴 이름이
/// `America/Argentina/Buenos_Aires`·`America/North_Dakota/New_Salem` 30글자이고
/// 옛 이름(`tzdata-legacy`)까지 세면 32다. 두 배를 둔다.
pub const TZ_NAME_MAX = 64;

/// zoneinfo가 사는 자리. glibc의 `TZDIR` 기본값이고 Debian도 같다.
/// `kernel/make_initrd.sh`가 sysroot의 같은 경로를 통째로 복사한다 — 둘이
/// 어긋나면 증상은 "모든 시간대가 UTC"이고 원인에서 멀다.
pub const ZONEINFO_DIR = "/usr/share/zoneinfo/";

/// `zoneinfoPath`가 만드는 경로를 담을 버퍼의 크기. 디렉터리 + 가장 긴
/// 이름 + NUL.
pub const ZONEINFO_PATH_MAX = ZONEINFO_DIR.len + TZ_NAME_MAX + 1;

/// TZif 파일의 첫 넉 자. glibc의 `tzfile.c`가 같은 넉 자를 보고 파일을
/// 받거나 버린다. `main.zig`의 `resolveTimezone`이 파일을 열어 이만큼 읽고
/// `looksLikeTzif`에 넘긴다(TS-M3 plan 결정 M3-B).
pub const TZIF_MAGIC = "TZif";

/// 사람이 읽는 시각의 시간대(TS design 결정 8). 값을 해석하지 않는다 —
/// `Asia/Seoul`이 무슨 뜻인지는 glibc가 알고, 이 타입이 하는 일은 그 이름을
/// 힙 없이 담는 것과 담을 수 있는 모양인지 보는 것뿐이다.
///
/// 이 저장소의 둘째 자유 문자열 설정 값이다(첫째는 `ntp`의 주소). `Ntp`가
/// `[4]u8`을 갖는 것과 같은 모양이고 크기만 다르다 — `Config`가 값으로
/// 돌려지고 힙이 없으므로, `parse`가 받은 텍스트를 가리키는 슬라이스를
/// 담으면 `load`가 돌아오는 순간 댕글링이다(TS-M3 plan 결정 M3-A).
pub const Timezone = struct {
    name: [TZ_NAME_MAX]u8,
    len: usize,

    /// 기본값. 이 키를 안 적은 기계의 `date`가 지금과 한 글자도 안 달라지는
    /// 근거가 이 세 글자다 — 파일도 `TZ`도 없는 지금 glibc가 이미 UTC를
    /// 찍고, `TZ=UTC`는 파일 없이도 glibc가 이름만으로 안다.
    pub const UTC: Timezone = Timezone.parse("UTC") orelse unreachable;

    /// 설정 파일의 값을 이 타입으로 바꾼다. 모르는 값이면 null이고,
    /// 호출자가 로그를 찍고 기본값에 머문다 — 다른 여덟 키와 같은 규칙이다.
    ///
    /// 거르는 것이 넷이다. 빈 값, `/`로 시작하는 것, `..`이 든 것, 버퍼보다
    /// 긴 것. 위협 모델이 있어서가 아니라 경로를 조립하는 코드가 검증 없이
    /// 값을 먹는 것을 이 저장소에 남기지 않기 위해서다(design 결정 8).
    /// 글자 화이트리스트는 안 둔다 — 파일이 정말 있는지는 `main.zig`가
    /// 열어서 보고, 그것이 진짜 판정이다.
    pub fn parse(value: []const u8) ?Timezone {
        if (value.len == 0 or value.len > TZ_NAME_MAX) return null;
        if (value[0] == '/') return null;
        if (std.mem.indexOf(u8, value, "..") != null) return null;
        var tz = Timezone{ .name = [_]u8{0} ** TZ_NAME_MAX, .len = value.len };
        @memcpy(tz.name[0..value.len], value);
        return tz;
    }

    /// 담긴 이름. 로그 · 씨앗 파일 · `TZ` 항목이 전부 이것을 쓴다.
    pub fn slice(self: *const Timezone) []const u8 {
        return self.name[0..self.len];
    }

    /// 두 값이 같은가. `config_test`의 필드 비교가 쓴다 — `Ntp.eql`과 같은
    /// 이유다.
    pub fn eql(self: Timezone, other: Timezone) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }
};

/// `/usr/share/zoneinfo/<이름>`을 NUL로 닫아 buf에 만든다. 시스템 콜이 없는
/// 순수 함수라 `config_test`가 본다 — 여는 것은 `main.zig`다(TS-M3 plan
/// 결정 M3-C).
///
/// `catch unreachable`인 이유는 길이가 구조로 보장되기 때문이다 —
/// `Timezone.parse`가 `TZ_NAME_MAX`를 넘는 이름을 안 만들고 버퍼가 그만큼
/// 크다. 그 관계가 깨지면 `config_test`의 "가장 긴 이름" 검사가 먼저 죽는다.
pub fn zoneinfoPath(buf: *[ZONEINFO_PATH_MAX]u8, tz: Timezone) [:0]const u8 {
    const text = std.fmt.bufPrint(buf, ZONEINFO_DIR ++ "{s}", .{tz.slice()}) catch unreachable;
    buf[text.len] = 0;
    return buf[0..text.len :0];
}

/// 파일의 머리가 TZif인가. `main.zig`가 읽은 넉 자를 넘긴다.
pub fn looksLikeTzif(head: []const u8) bool {
    return head.len >= TZIF_MAGIC.len and
        std.mem.eql(u8, head[0..TZIF_MAGIC.len], TZIF_MAGIC);
}

/// 커널 cmdline이 rc를 끄는 토큰(SC design 결정 9). `tars.conf`를 이기는
/// 것은 이 키 하나뿐이다 — 우선순위는 cmdline > tars.conf > 기본값이고,
/// 다른 다섯 키는 cmdline을 안 본다. 그 예외의 근거는 하나다: *"`tars.conf`를
/// 고칠 셸이 없을 때 쓰는 것"*.
pub const NO_CONFIG_TOKEN = "tars.noconfig";

/// 커널 cmdline이 사는 자리. `/proc`은 설정을 읽기 전에 이미 붙어 있다
/// (design 실측 13 — `main.zig`가 `/proc`을 먼저 붙이고 그 다음이 `/config`다).
pub const CMDLINE_PATH: [:0]const u8 = "/proc/cmdline";

/// cmdline 문자열에 위 토큰이 있는가. 시스템 콜이 없는 순수 함수라서
/// `parse`와 같은 성질이다 — 게스트를 안 띄우고 검증할 수 있고,
/// `config_test.zig`가 실제로 그렇게 한다.
///
/// 부분 문자열이 아니라 토큰으로 본다. `indexOf` 한 줄로 짜면
/// `tars.noconfigured`나 `nottars.noconfig`에도 걸리고, 그 실수의 증상은
/// "부팅했더니 rc가 안 읽힌다" 하나뿐이라 원인에서 아주 멀다.
///
/// 값이 붙어 있어도 받는다(`tars.noconfig=1`). 이 토큰은 있고 없음이
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

/// 셸 화이트리스트. 설정 파일에 적을 수 있는 것은 이름뿐이고 경로가
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
    /// 여기 적힌 경로는 kernel/make_initrd.sh가 복사해 넣는 자리와 같아야
    /// 한다. 어긋나면 부팅 후 execve 실패로만 드러난다.
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
    /// `on`이면 `"none"`이다.
    ///
    /// 왜 빈 문자열이나 null이 아닌가. terminal은 argv를 짓는 쪽과
    /// 쓰는 쪽이 다르다 — 이 값이 프로세스 경계를 문자열로 건너가므로
    /// "인자가 없다"를 포인터로 표현할 수 없고, 빈 문자열을 넣으면 저쪽에서
    /// "인자를 안 받았다"와 구분이 안 된다. `Toggles.arg`가 빈 집합에
    /// `none`을 쓰는 것과 글자 그대로 같은 이유다(아래 그 주석을 볼 것).
    ///
    /// 콘솔 셸은 이 함수를 안 쓴다. 그쪽은 init이 argv를 직접 짓기 때문에
    /// 슬롯을 null로 두면 그만이다.
    pub fn configFlag(self: Shell, sc: ShellConfig) [:0]const u8 {
        return switch (sc) {
            .off => self.noConfigFlag(),
            .on => "none",
        };
    }

    /// 이 셸의 rc 파일이 설정 디스크에서 갖는 이름(SC design 결정 1).
    ///
    /// 홈의 이름이 아니라 여기 이름이다. 홈에는 링크만 있고
    /// (`kernel/make_initrd.sh`가 건다) 실체는 전부 이 자리다 — 홈(`/`)은
    /// tmpfs라 부팅마다 비워지고, 살아남는 것은 `/config` 하나뿐이다.
    ///
    /// | 홈의 이름 | 여기 |
    /// |---|---|
    /// | `/.bashrc` | `/config/bashrc` |
    /// | `/.zshrc` | `/config/zshrc` |
    /// | `/.config/fish/config.fish` | `/config/fish.config` |
    ///
    /// `fish.config`로 적은 것에 뜻이 있다 — `/config` 안을 평평하게
    /// 두어 `gitconfig`과 같은 층에 세운다(결정 1).
    ///
    /// `main.zig`의 `CONFIG_PATH`가 같은 `/config`를 알고 있다. 둘을 한
    /// 자리로 모으려면 힙 없이 경로를 조립해야 해서, 지금은 이름 셋이
    /// `make_initrd.sh`의 링크 셋과 짝이라는 것을 주석으로 못 박는 쪽을
    /// 고른다 — 어긋나면 증상은 "rc를 고쳤는데 안 읽힌다"이고,
    /// `config/check.sh`의 2차 부팅이 그것을 본다.
    pub fn rcPath(self: Shell) [:0]const u8 {
        return switch (self) {
            .fish => "/config/fish.config",
            .bash => "/config/bashrc",
            .zsh => "/config/zshrc",
        };
    }

    /// 이 기계가 기억하는 것 둘 중 쳤던 명령의 자리(SM design 결정 3).
    ///
    /// 셸마다 다른 파일인 이유는 형식이다 — zsh는 `: <ts>:<dur>;<cmd>`,
    /// bash는 평문이라 한 파일에 섞으면 서로의 것을 못 읽는다. init이
    /// `cfg.shell`을 이미 알고 있으므로 그 자리에서 정한다.
    ///
    /// fish는 빈 목록이다. fish의 히스토리는 `XDG_DATA_HOME` 아래로 통째로
    /// 따라오고(실측 11·40), 줄 수를 정하는 변수가 아예 없다(비목표 4).
    ///
    /// 히스토리 env는 씨앗 rc를 한 글자도 안 건드린다(SM 결정 3). 실측
    /// 9·10이 근거다 — 셋 다 env에서 먹는다.
    ///
    /// 그 문장을 옵션까지 덮는 것으로 읽으면 안 된다. `setopt`를 zsh에
    /// 나르는 환경 변수는 없어서 옵션은 파일로만 줄 수 있다(SD 확인 1).
    /// 그래서 SD-M1이 씨앗의 zsh 갈래에 한 줄을 더했고, 그 줄의 목록이
    /// 아래 `histOptionLines()`다. env로 되는 것과 파일로만 되는 것이
    /// 갈리는 자리가 여기다.
    const HIST_BASH = [_][:0]const u8{
        "HISTFILE=/config/bash_history",
        // bash는 `HISTFILESIZE`를 안 줘도 이 수로 파일까지 자른다
        // (실측 37). 5,000줄 = 약 250KB = 16MiB 디스크의 1.5%(결정 4).
        "HISTSIZE=5000",
    };
    const HIST_ZSH = [_][:0]const u8{
        "HISTFILE=/config/zsh_history",
        "HISTSIZE=5000",
        // zsh는 이것이 없으면 한 줄도 안 쓴다(실측 9). `HISTFILE`만 주고
        // 끝내는 것이 이 자리에서 가장 흔한 실수이고, 증상은 "히스토리가
        // 그냥 안 남는다"라 원인에서 멀다.
        "SAVEHIST=5000",
    };

    /// 이 셸에게 줄 히스토리 env. `environ.zig`가 커널 블록 뒤에 그대로 붙인다.
    pub fn histEntries(self: Shell) []const [:0]const u8 {
        return switch (self) {
            .fish => &[_][:0]const u8{},
            .bash => &HIST_BASH,
            .zsh => &HIST_ZSH,
        };
    }

    /// 씨앗 rc가 담는 훅 줄들(SM design 결정 5). 셸마다 둘이다 — `zoxide`가
    /// "어디에 갔는가"를, `fzf`가 "무엇을 쳤는가"를 이 기계에 잇는다.
    ///
    /// `command -v`/`type -q` 관문을 지우면 안 된다. 도구가 없을 때 관문
    /// 없는 훅은 부팅하면서 `command not found`를 찍는다 — zsh 50바이트 ·
    /// bash 38바이트 · fish 191바이트(6줄)(SM-M1 실측 27). 그 한 줄이
    /// 설정 디스크를 붙이는 다섯 체인의 화면 좌표를 밀어 버린다. 관문이 있으면
    /// 셋 다 0바이트다(실측 23).
    ///
    /// `fzf`의 통합은 `.deb`의 예제 스크립트가 아니라 바이너리 내장이다
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

    /// 이 셸의 훅 줄들. `rcSeed()`가 담는 글자와 여기 글자가 두 벌인 것은
    /// 실수가 아니다(SM design 결정 10).
    ///
    /// `rcSeed()`를 이 목록에서 `++`로 조립하면 두 벌이 하나가 되고, 그 순간
    /// `config_test.zig`의 역방향 검사가 tautology가 된다 — "훅이 씨앗에
    /// 있는가"를 묻는데 답이 언제나 참이 되기 때문이다. 이 저장소가 반복해서
    /// 부딪친 자리다(UT-M1의 정적 목록 검사가 같은 이유로 가짜였다).
    ///
    /// 두 벌을 잇는 것은 컴파일러가 아니라 그 검사이고, 그것이 결정 6의
    /// 목적이다 — `HangulLayout` ↔ `hangul.Layout`, `Shell.path()` ↔
    /// `make_initrd.sh`와 같은 종류의 이음매를 이 파일이 이미 둘 갖고 있다.
    pub fn hookLines(self: Shell) []const []const u8 {
        return switch (self) {
            .fish => &HOOKS_FISH,
            .bash => &HOOKS_BASH,
            .zsh => &HOOKS_ZSH,
        };
    }

    /// 씨앗 rc가 담는 히스토리 옵션 줄(SD design 결정 1·3). zsh만 하나이고
    /// bash와 fish는 빈 목록이다.
    ///
    /// 이 한 줄이 하는 일은 쓰는 시점을 옮기는 것이다. 이 줄이 없으면 zsh는
    /// 셸이 죽으면서 한 번에 쓰는데, 그 기회가 두 셸에게 다르게 온다 —
    /// 화면 셸은 `terminal`이 먼저 죽어 PTY가 닫히면서 SIGHUP을 받고, 콘솔
    /// 셸은 받을 데가 없어 SIGTERM을 무시한 채 3초를 버틴 뒤 SIGKILL에
    /// 죽는다. 그래서 전원 버튼을 누르면 콘솔 셸에 친 명령이 통째로
    /// 사라진다(SD 실측 4·14 — 게스트에서 콘솔 0, 화면 1을 쟀다).
    ///
    /// 이 줄이 있으면 명령마다 그 자리에서 파일에 쓰므로 SIGKILL에도
    /// 남는다(실측 3·6).
    ///
    /// bash는 BH-M1이 채웠다. `setopt` 한 줄에 대응하는 것이 없어서
    /// 프롬프트 훅을 쓰고, 그래서 순서가 생긴다 — 아래 `HIST_OPTIONS_BASH`의
    /// 주석에 있다. fish는 `exit`·SIGTERM·SIGHUP 셋 다에서 쓰므로 고칠 것이
    /// 애초에 없다(실측 8).
    ///
    /// `rcSeed()`가 담는 글자와 여기 글자가 두 벌인 이유는 `hookLines()`의
    /// 머리 주석과 같다 — 조립하면 역방향 검사가 tautology가 된다.
    const HIST_OPTIONS_ZSH = [_][]const u8{
        "setopt INC_APPEND_HISTORY",
    };

    /// bash의 히스토리 옵션 줄(BH design 결정 1·3).
    ///
    /// zsh의 `setopt`와 하는 일은 같고 생긴 것이 다르다. bash에는 쓰는
    /// 시점을 옮기는 옵션이 없어서 프롬프트 훅을 쓴다 — `PROMPT_COMMAND`는
    /// 명령이 끝나고 다음 프롬프트를 그리기 직전에 도는 자리다.
    ///
    /// 그래서 zsh와 타이밍이 한 칸 다르다. zsh는 명령을 읽자마자 쓰므로
    /// 실행 중인 명령이 이미 파일에 있는데(SD 실측 24), bash는 직전 명령까지만
    /// 있다(BH 실측 4). 게이트가 이 파일을 세는 자리에서 이 차이가 값을
    /// 바꾼다.
    ///
    /// `shopt -s histappend`는 안 쓴다. 그 옵션이 정하는 것은 셸이 끝날 때
    /// 덮어쓸 것인가 이어 쓸 것인가이고, 우리가 지는 싸움은 "끝날 때가 아예
    /// 안 온다"이다(BH 실측 10 — SIGKILL 칸). `history -a`는 언제나 append라
    /// 함께 켤 이유도 없다.
    const HIST_OPTIONS_BASH = [_][]const u8{
        "PROMPT_COMMAND='history -a'",
    };

    /// 이 셸의 히스토리 옵션 줄들.
    pub fn histOptionLines(self: Shell) []const []const u8 {
        return switch (self) {
            .fish => &[_][]const u8{},
            .bash => &HIST_OPTIONS_BASH,
            .zsh => &HIST_OPTIONS_ZSH,
        };
    }

    /// 첫 부팅에 깔아 두는 내용(결정 7).
    ///
    /// 규칙이 하나뿐이다: 아무것도 찍지 않는다. 설정 디스크를 붙이는
    /// 체인이 다섯이고 그중 셋이 화면의 셀 좌표로 판정한다 — 씨앗이 배너
    /// 한 줄을 찍으면 그 좌표가 통째로 밀린다. 그래서 여기 쓸 수 있는 줄은
    /// 주석 · alias · 위 `hookLines()`와 `histOptionLines()`에 글자 그대로
    /// 있는 줄뿐이고,
    /// `config_test.zig`의 `expectQuietSeed`가 그 규칙을 부팅 없이 0.1초에
    /// 확인한다.
    ///
    /// SM-M1이 그 문을 두 줄만큼 넓혔다. 넓힌 방식이 "`eval`도 허용"이
    /// 아니라 정확 허용 목록인 이유는 결정 6에 있다 — `eval` 뒤에는 아무
    /// 문장이나 올 수 있고, 그러면 이 규칙이 막으려던 것이 그대로 열린다.
    ///
    /// SD-M1이 zsh 갈래에서 한 줄 더 넓혔다. 같은 방식이다 — 범주
    /// (`setopt `로 시작하면 통과)가 아니라 정확 허용 목록이고, 그 줄을
    /// 허용하는 근거는 취향이 아니라 재 본 값이다(SD 실측 9 — 0바이트,
    /// 오타는 stderr 65바이트).
    ///
    /// 프롬프트를 안 건드린다(비목표 5). 실측 9가 그 비용을 적고 있고,
    /// 그 비용은 사용자가 자기 rc에 프롬프트를 쓸 때 자기 기계에서만
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
            \\# 아래 넷이 eza를 습관적인 이름으로 부른다. 이 기계는 도구 예순
            \\# 다섯 개를 싣고 있는데 그중 대부분은 이름으로만 닿는다 — 그 하나를
            \\# ls 자리에 앉힌다.
            \\#
            \\# ls가 여기서 유일한 셰도다. 설정 디스크를 붙이는 여섯 체인이 rc
            \\# 켜진 셸에 명령을 넣으므로 별칭 하나가 게이트의 판정 글자를 바꿀
            \\# 수 있다. ls가 돌아가는 자리 셋(/config/zshrc · /config/xdg/zoxide ·
            \\# /sys/class/net)을 부팅으로 재서 eza가 같은 글자를 내는 것을
            \\# 확인했다. 새 이름을 더할 때는 게이트가 치는 이름인지 먼저 볼 것.
            \\#
            \\# --icons는 안 붙인다 — eza의 아이콘은 유니코드 사설 영역이고 이
            \\# 화면의 폰트에 그 글리프가 하나도 없다. 붙이면 빈 칸만 생긴다.
            \\alias ls='eza'
            \\alias ll='eza -l --group-directories-first'
            \\alias la='eza -la --group-directories-first'
            \\alias lt='eza --tree --level=2'
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
            \\# 아래 넷이 eza를 습관적인 이름으로 부른다. 이 기계는 도구 예순
            \\# 다섯 개를 싣고 있는데 그중 대부분은 이름으로만 닿는다 — 그 하나를
            \\# ls 자리에 앉힌다.
            \\#
            \\# ls가 여기서 유일한 셰도다. 설정 디스크를 붙이는 여섯 체인이 rc
            \\# 켜진 셸에 명령을 넣으므로 별칭 하나가 게이트의 판정 글자를 바꿀
            \\# 수 있다. ls가 돌아가는 자리 셋(/config/zshrc · /config/xdg/zoxide ·
            \\# /sys/class/net)을 부팅으로 재서 eza가 같은 글자를 내는 것을
            \\# 확인했다. 새 이름을 더할 때는 게이트가 치는 이름인지 먼저 볼 것.
            \\#
            \\# --icons는 안 붙인다 — eza의 아이콘은 유니코드 사설 영역이고 이
            \\# 화면의 폰트에 그 글리프가 하나도 없다. 붙이면 빈 칸만 생긴다.
            \\alias ls='eza'
            \\alias ll='eza -l --group-directories-first'
            \\alias la='eza -la --group-directories-first'
            \\alias lt='eza --tree --level=2'
            \\#
            \\# 아래 둘이 이 기계가 기억하는 법이다.
            \\#   zoxide  어느 디렉터리에 갔는지 — 프롬프트마다 배우고 z <조각>으로 간다
            \\#   fzf     무엇을 쳤는지 — Ctrl+R(히스토리) · Ctrl+T(파일) · Alt+C(디렉터리)
            \\#
            \\# 아래 한 줄이 히스토리를 명령마다 그 자리에서 파일에 쓴다. 이 줄이
            \\# 없으면 bash는 셸이 끝날 때 한 번에 쓰는데, 전원 버튼을 눌러도 콘솔
            \\# 셸에는 그 기회가 안 온다 — 대화형 셸은 SIGTERM을 무시하고 3초 뒤
            \\# SIGKILL에 죽으므로 그 세션에 친 명령이 통째로 사라진다.
            \\#
            \\# 이 줄은 아래 훅보다 먼저 있어야 한다. PROMPT_COMMAND는 변수가
            \\# 하나뿐이라 마지막 대입이 이기는데, zoxide의 훅이 같은 변수를 쓴다.
            \\# 순서가 이대로면 zoxide가 우리 값을 보존하며 앞에 붙여
            \\# __zoxide_hook;history -a가 되고 둘 다 돈다. 뒤집으면 우리 대입이
            \\# zoxide를 지우고, 증상은 히스토리는 남는데 z가 아무 디렉터리도 안
            \\# 배우는 것이다.
            \\PROMPT_COMMAND='history -a'
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
            \\# 아래 넷이 eza를 습관적인 이름으로 부른다. 이 기계는 도구 예순
            \\# 다섯 개를 싣고 있는데 그중 대부분은 이름으로만 닿는다 — 그 하나를
            \\# ls 자리에 앉힌다.
            \\#
            \\# ls가 여기서 유일한 셰도다. 설정 디스크를 붙이는 여섯 체인이 rc
            \\# 켜진 셸에 명령을 넣으므로 별칭 하나가 게이트의 판정 글자를 바꿀
            \\# 수 있다. ls가 돌아가는 자리 셋(/config/zshrc · /config/xdg/zoxide ·
            \\# /sys/class/net)을 부팅으로 재서 eza가 같은 글자를 내는 것을
            \\# 확인했다. 새 이름을 더할 때는 게이트가 치는 이름인지 먼저 볼 것.
            \\#
            \\# --icons는 안 붙인다 — eza의 아이콘은 유니코드 사설 영역이고 이
            \\# 화면의 폰트에 그 글리프가 하나도 없다. 붙이면 빈 칸만 생긴다.
            \\alias ls='eza'
            \\alias ll='eza -l --group-directories-first'
            \\alias la='eza -la --group-directories-first'
            \\alias lt='eza --tree --level=2'
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
            \\#
            \\# 아래 한 줄이 히스토리를 명령마다 그 자리에서 파일에 쓴다.
            \\# 이 줄이 없으면 zsh는 셸이 죽으면서 한 번에 쓰는데, 전원 버튼을
            \\# 눌러도 콘솔 셸에는 그 기회가 안 온다 — 대화형 셸은 SIGTERM을
            \\# 무시하고 3초 뒤 SIGKILL에 죽으므로, 그 세션에 친 명령이 통째로
            \\# 사라진다. 지우면 그 동작으로 돌아간다.
            \\setopt INC_APPEND_HISTORY
            \\
            ,
        };
    }
};

/// 물리 키보드 종류. 재배치가 아니라 하드웨어 선언이다 — 사용자가 키를
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

/// 한글 자판(HI design 결정 7). `Shell`·`Keyboard`와 같은 화이트리스트
/// 구조다 — enum에 없는 이름은 파싱을 통과할 수 없다.
///
/// 이름이 `terminal/src/hangul.zig`의 `Layout`과 짝이어야 한다. 여기가
/// "무엇을 적을 수 있는가"이고 저기가 "그것이 어떻게 조합하는가"인데, 둘을
/// 잇는 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다. 어긋나면
/// 증상은 "설정을 적었는데 기본 자판으로 뜬다"이고, 로그에 자판 이름이
/// 찍히므로 HI 게이트가 그것을 본다.
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

/// 영문 자판. 한글 자판과 직교한다(HI design 결정 13) — 한글 배열은
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
/// `Shell`·`Keyboard`·자판 둘과 모양이 다른 유일한 설정이다. 그 넷은
/// 하나를 고르는 것이지만 전환 키는 배타적이지 않다 — 한/영 키를 쓰면서
/// CapsLock도 쓰는 것이 정상이다. 그래서 enum 하나가 아니라 아래 `Toggles`
/// 집합이 값이 되고, 이 enum은 이름의 화이트리스트 역할만 한다.
pub const ToggleKey = enum {
    /// 실기의 한/영 키(evdev 122). 게이트가 못 보낸다 — QEMU가
    /// `sendkey lang1`을 이름만 받고 조용히 버린다(HI-M0 실측 1). 그래서 이
    /// 갈래를 덮는 것은 `input_test`의 호스트 검사뿐이다.
    hangul_key,
    /// Shift+Space. HI-M1이 유일한 전환 키로 골랐던 것이고 이제 끌 수 있다 —
    /// `HELLO WORLD`를 칠 때 한/영이 바뀌는 것이 그 대가였다.
    shift_space,
    /// CapsLock을 짧게 눌렀다 뗀 것. 길게 누르면 대문자 잠금이다(결정 9).
    capslock_tap,
    /// 왼쪽 Ctrl을 짧게 눌렀다 뗀 것. 누른 동안 다른 키가 오면 평범한
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
    /// 모르는 이름은 로그만 남기고 넘어간다 — 설정 파일은 사람이 손으로
    /// 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이라는 CP의 판단 그대로다.
    /// 그 규칙이 목록 안에서도 서는 것이 여기서 새로운 점이다: 이름 하나가
    /// 틀려도 나머지는 살아남는다.
    ///
    /// 빈 값(`hangul_toggle=`)은 뜻이 있는 입력이다. 기본값으로 떨어뜨리지
    /// 않는다 — 그러면 전환 키를 전부 끌 방법이 없어진다.
    pub fn parse(value: []const u8) Toggles {
        var t = Toggles{};
        var it = std.mem.splitScalar(u8, value, ',');
        while (it.next()) |raw| {
            const name = std.mem.trim(u8, raw, " \t");
            if (name.len == 0) continue;
            // `arg()`가 빈 집합에 쓰는 이름이다. 왕복을 위해 여기서 받는다 —
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

    /// argv로 넘기고 로그에 찍을 정규형 콤마 목록. 버퍼는 호출자가 준다 —
    /// 이 파일에는 힙이 없고, `Keyboard.arg()`처럼 상수 문자열을 돌려줄 수도
    /// 없다(조합이 열여섯 가지다).
    ///
    /// 정규화가 이 함수의 값이다. 설정 파일에 어떤 순서로 적었든 enum 선언
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
/// 모자라면 자른다. 위 `comptime`이 `TOGGLE_ARG_MAX`가 최악의 경우보다
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
/// 먼저 꽂기 때문이다. pc는 보정을 켜는 쪽이라 명시적으로 적어야 한다.
pub const Config = struct {
    shell: Shell = .fish,
    keyboard: Keyboard = .apple,
    /// 기본값이 `shin_pcs`인 것은 `keyboard`가 `apple`인 것과 같은
    /// 근거다 — 이 기계를 쓰는 사람이 쓰는 것이 기본값이다. 두벌식이 더
    /// 흔하다는 것은 이 기계의 사실이 아니다.
    hangul_layout: HangulLayout = .shin_pcs,
    latin_layout: LatinLayout = .qwerty,
    /// 기본값은 넷 다 켜진 것이다(2026-09-01에 사용자가 정했다).
    /// 전환 키가 많아서 곤란한 경우는 없고 없어서 곤란한 경우는 있다 —
    /// 특히 `hangul_key`는 실기에서만 오는 키라 기본으로 꺼 두면 "왜 한/영
    /// 키가 안 먹지"가 된다.
    hangul_toggle: Toggles = .{
        .hangul_key = true,
        .shift_space = true,
        .capslock_tap = true,
        .lctrl_tap = true,
    },
    /// 기본값이 `on`인 근거는 위 `keyboard`·`hangul_layout`과 같다 —
    /// 이 기계를 쓰는 사람이 쓰는 것이 기본값이고, 이 기계는 개발용이다.
    /// embedded 장비의 init 1으로 쓰는 사람은 `keyboard=pc`를 적듯 `off`를
    /// 명시적으로 적는다(design 비목표 4).
    shell_config: ShellConfig = .on,
    /// 기본값이 `off`인 유일한 키다. 다른 여섯은 "이 기계를 쓰는 사람이
    /// 쓰는 것"이 기본값인데(keyboard=apple · hangul_layout=shin_pcs),
    /// 이 키는 근거가 다르다 — 켜는 비용이 부팅마다 붙기 때문이다.
    net: Net = .off,
    /// 기본값이 `off`인 둘째 키다. 근거는 바로 위 `net`과 같고 하나가 더
    /// 있다 — 이 키는 `net`이 꺼져 있으면 아무 일도 못 한다(TS design
    /// 결정 3).
    ntp: Ntp = .off,
    /// 기본값이 `UTC`인 것은 "꺼짐"이 아니라 "지금과 같은 동작"이다(TS
    /// design 확인 10). zoneinfo가 없던 게스트가 이미 UTC를 찍고 있었고,
    /// 이 키를 안 적은 기계는 한 글자도 안 바뀐다. `net`·`ntp`와 달리 이
    /// 키는 켜는 비용이 없다 — 파일 하나를 읽는 것이 전부다.
    timezone: Timezone = Timezone.UTC,
};

/// 설정 파일을 통째로 담는 스택 버퍼의 크기. 힙이 없으므로 상한이 필요하고,
/// 키가 수십 개가 되어도 4KB를 넘길 일은 없다. 넘치면 잘라서 파싱하고
/// 경고를 찍는다(조용히 무시하지 않는다).
const MAX_FILE = 4096;

/// 설정 파일을 읽어 파싱한다.
///
/// optional을 돌려주는 이유는 딱 하나를 구분하기 위해서다. null은 오직
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
/// 나머지는 첫 번째 `=`에서 키와 값으로 나누고 양쪽 공백을 뗀다.
/// 모르는 키와 모르는 값은 로그만 남기고 넘어간다 — 설정 파일은 사용자가
/// 손으로 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이다.
/// pub인 이유는 config_test.zig가 부르기 때문이다. 이 파일에서 유일하게
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
            // 앞의 넷과 모양이 다른 유일한 키다(결정 7). `stringToEnum`
            // 하나로 안 끝나고 콤마로 갈라야 한다. 모르는 이름을 흘려보내는
            // 규칙은 같고, 그 규칙이 목록 안에서도 선다.
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
        } else if (std.mem.eql(u8, key, "net")) {
            // shell·keyboard·자판 둘·shell_config와 완전히 같은 모양이다.
            c.net = std.meta.stringToEnum(Net, value) orelse {
                std.debug.print("tars-init: unknown net '{s}', falling back to {s}\n", .{
                    value, @tagName(c.net),
                });
                continue;
            };
        } else if (std.mem.eql(u8, key, "ntp")) {
            // 앞의 일곱과 모양이 다른 유일한 자리다. `stringToEnum`이 아니라
            // `Ntp.parse`인 이유는 값의 셋째 갈래가 주소 리터럴이기
            // 때문이다(TS design 결정 5). 모르는 값을 흘려보내는 규칙은 같다.
            var ntp_buf: [NTP_ARG_MAX]u8 = undefined;
            c.ntp = Ntp.parse(value) orelse {
                std.debug.print("tars-init: unknown ntp '{s}', falling back to {s}\n", .{
                    value, c.ntp.arg(&ntp_buf),
                });
                continue;
            };
        } else if (std.mem.eql(u8, key, "timezone")) {
            // 둘째 자유 문자열 키다. `ntp`와 다른 것은 값을 해석하지 않는다는
            // 것이다(design 결정 8) — 담을 수 있는 모양인지만 보고, 파일이
            // 정말 있는지는 `main.zig`가 본다. 모르는 값을 흘려보내는 규칙은
            // 같다.
            c.timezone = Timezone.parse(value) orelse {
                std.debug.print("tars-init: unknown timezone '{s}', falling back to {s}\n", .{
                    value, c.timezone.slice(),
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
    // `Ntp`도 같은 이유로 버퍼가 필요하다 — 값 셋 중 하나가 주소라 상수
    // 문자열이 아니다.
    var ntp_buf: [NTP_ARG_MAX]u8 = undefined;
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
        \\#   CapsLock과 왼쪽 Ctrl은 0.3초보다 짧게 눌렀다 뗐을 때만 한/영이고,
        \\#   길게 누르면 CapsLock은 대문자 잠금, Ctrl은 평소의 Ctrl이다
        \\hangul_toggle={s}
        \\# shell_config: on | off
        \\#   on이면 셸이 홈의 rc 파일을 읽는다. 그 파일들은 /config에 있고
        \\#   홈에는 링크만 있다 — /config/bashrc · /config/zshrc ·
        \\#   /config/fish.config. off면 셸이 설정 없이 뜬다
        \\shell_config={s}
        \\# net: off | dhcp
        \\#   dhcp면 init이 eth0을 UP으로 올리고 dhcpcd를 띄운다. 주소도
        \\#   라우트도 /etc/resolv.conf도 dhcpcd가 쓴다
        \\net={s}
        \\# ntp: off | dhcp | <IPv4 주소>
        \\#   dhcp면 DHCP 서버가 알려 준 NTP 서버에 묻고, 주소를 적으면 그
        \\#   주소에 묻는다. 부팅할 때 한 번만 묻고 시계를 그 값으로 뛴다 —
        \\#   그 뒤로는 시계를 안 건드린다. net=off면 아무 일도 안 한다
        \\ntp={s}
        \\# timezone: UTC | <IANA 이름. 예: Asia/Seoul>
        \\#   /usr/share/zoneinfo 아래의 이름이다. 없는 이름이면 로그를 찍고
        \\#   UTC로 떨어진다. ntp가 시계를 맞추는 것과 별개다 — 이 값은
        \\#   그 시각을 어느 지역의 시각으로 보여 줄지만 정한다
        \\timezone={s}
        \\
    , .{
        @tagName(c.shell),
        @tagName(c.keyboard),
        @tagName(c.hangul_layout),
        @tagName(c.latin_layout),
        c.hangul_toggle.arg(&toggle_buf),
        @tagName(c.shell_config),
        @tagName(c.net),
        c.ntp.arg(&ntp_buf),
        c.timezone.slice(),
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

/// fd에 전부 쓴다. `save`와 `seedRcFiles`가 같은 루프를 쓴다 — SC-M1이
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
/// `/config`가 마운트됐을 때만 부른다. 안 붙은 부팅에서는 `/config`가
/// initrd 안의 빈 디렉터리(tmpfs)이므로, 여기서 만들면 부팅마다 새로 생겼다
/// 사라지는 파일이 되고 "고치고 재부팅하면 남는다"는 약속이 그 부팅에서만
/// 거짓이 된다. 없는 편이 낫다 — 링크가 끊긴 채로 셸이 뜨고, 그것은
/// SC-M0이 이미 여섯 체인에서 확인한 정상 경로다.
///
/// `shell_config`를 안 본다. `off`여도 깐다 — 셸이 안 읽을 뿐 파일은
/// 있는 것이 맞고, 나중에 `on`으로 바꾼 사람이 빈 디렉터리를 안 만난다.
/// `shell`도 안 본다: 셋 다 깐다는 결정 7의 근거가 같다 — `tars.conf`의
/// `shell`은 언제든 바뀔 수 있고, 바뀐 뒤에야 씨앗이 생기면 "고치고
/// 재부팅했는데 rc가 없다"가 된다. 비용은 부팅마다 `open()` 셋이다.
///
/// 이미 있으면 손대지 않는다. 그때부터 그 파일은 사용자의 것이다.
/// `O_EXCL`이 그 질문을 커널에게 한 번에 묻는다 — `save`가 `O_EXCL`을 안
/// 쓰는 것과 다른 이유는, 저쪽은 "파일이 없다"를 `load`가 이미 답했기
/// 때문이다.
pub fn seedRcFiles() void {
    for (std.enums.values(Shell)) |sh| seedOneFile(sh.rcPath(), sh.rcSeed());
}

/// git의 전역 설정 자리 — UT-M3 결정 8이 건 링크(`/.gitconfig`)가 가리키는
/// 곳이다.
pub const GITCONFIG_PATH: [:0]const u8 = "/config/gitconfig";

/// 첫 부팅에 깔아 두는 git 설정(ST-M2 결정 5).
///
/// 우리가 이 파일을 만드는 이유는 링크가 끊겨 있었기 때문이다.
/// `kernel/make_initrd.sh`가 `/.gitconfig -> config/gitconfig`를 걸어 두는데
/// 그 실체를 만드는 코드가 저장소에 한 줄도 없었다 — `tools/check.sh`의
/// 검사 13만 `git config --global`로 그것을 만들 뿐이고, 그래서 새 디스크의
/// 그 링크는 영원히 댕글링이었다(design 실측 1).
///
/// 줄마다 근거가 있다.
///
///   init.defaultBranch  실측: 지금 게스트의 `GIT_DEFAULT_BRANCH=master`다.
///                       새 저장소가 `main`으로 뜨는 것이 요즘 기본값이다
///   core.pager          `-X`가 요점이다. less가 alternate screen을 안 쓰면
///                       `git log`의 출력이 화면의 스크롤백에 남고, CM·CN·CS가
///                       세운 copy mode로 그 로그를 훑을 수 있다. `-F`는 한
///                       화면짜리 출력이면 pager를 아예 안 띄운다
///   color.ui            지금도 `auto`가 기본이지만 적어 둔다 — 끄고 켤 자리를
///                       `tars-config`가 가리키는 파일 안에 두는 것이 목적이다
///   alias               자주 치는 넷. git은 alias를 자기가 직접 풀어서
///                       셸 별칭과 달리 셸 없이도 돈다(`git st`)
///
/// 들여쓰기가 탭이 아니라 공백 넷인 이유가 있다. Zig의 multiline 문자열
/// 리터럴이 탭을 거부한다(`string literal contains invalid byte`). git은 둘 다
/// 받아들이고, `git config --global`이 이 파일을 다시 쓸 때는 자기가 탭으로
/// 쓴다 — 그래서 이 파일은 언젠가 둘이 섞이는데, 그것이 정상이다.
///
/// `[user]` 절은 빠뜨린 것이 아니라 안 넣은 것이다. 신원은 git이
/// `/etc/passwd`에서 유도한다(실측: `GIT_AUTHOR_IDENT=root <root@(none).(none)>`).
/// 그리고 넣으면 `tools/check.sh` 검사 13의 판정 값(`email = tars`)과 겹칠 수
/// 있다 — 그 검사는 "git이 링크를 풀어 /config에 썼다"를 보는 것이고, 씨앗에
/// 같은 값이 있으면 검사가 거짓으로 초록이 된다(GA가 없애려는 모양).
pub const GITCONFIG_SEED =
    \\# TARS git config — 이 파일의 실체는 설정 디스크의 /config/gitconfig이고
    \\# 홈의 ~/.gitconfig는 그리로 가는 링크다. 홈(/)은 tmpfs라 부팅마다
    \\# 비워지므로 살아남는 자리는 설정 디스크 하나뿐이다.
    \\#
    \\# 고치는 길이 둘이다. 이 파일을 직접 고치거나
    \\#   git config --global <키> <값>
    \\# 을 치면 링크를 통해 여기에 쓰인다. 둘 다 재부팅이 필요 없다 — git은
    \\# 명령마다 이 파일을 읽는다.
    \\#
    \\# [user]가 없는 것은 일부러다. 작성자를 git이 /etc/passwd에서 유도한다.
    \\# 바꾸려면 여기에 [user] 절을 더한다.
    \\[init]
    \\    defaultBranch = main
    \\[core]
    \\    pager = less -FRX
    \\[color]
    \\    ui = auto
    \\[alias]
    \\    st = status -sb
    \\    lg = log --oneline --graph --decorate
    \\    co = checkout
    \\    br = branch
    \\
;

/// gitconfig 하나를 rc 셋과 같은 규칙으로 깐다(ST-M2).
pub fn seedGitconfig() void {
    seedOneFile(GITCONFIG_PATH, GITCONFIG_SEED);
}

/// 씨앗 파일 하나를 "없으면 만든다".
///
/// `O_EXCL`이 그 질문("이미 있나")을 커널에게 한 번에 묻는다 — `save`가
/// `O_EXCL`을 안 쓰는 것과 다른 이유는, 저쪽은 "파일이 없다"를 `load`가 이미
/// 답했기 때문이다.
///
/// 이미 있으면 손대지 않는다. 그때부터 그 파일은 사용자의 것이다.
fn seedOneFile(path: [:0]const u8, text: []const u8) void {
    const rc = linux.open(path.ptr, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .EXCL = true,
    }, 0o644);
    if (failed(rc)) |e| {
        // 이미 있다 = 사용자의 파일이다. 조용히 둔다 — 여기서 로그를 찍으면
        // 부팅마다 네 줄이 늘고, 그 넷은 아무것도 알려주지 않는다.
        if (e == .EXIST) return;
        std.debug.print("tars-init: could not seed {s} (errno {d})\n", .{
            path, @intFromEnum(e),
        });
        return;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    writeAll(fd, text, path) catch return;

    // `created`가 아니라 `seeded`다. `tars-init: created /config/tars.conf`
    // 를 config 체인이 1차·2차 부팅의 판정으로 쓰고 있어서, 앞부분이 겹치면
    // 그 검사가 씨앗 몇 줄까지 함께 보게 된다.
    std.debug.print("tars-init: seeded {s}\n", .{path});
}

/// `/proc/cmdline`을 읽어 `NO_CONFIG_TOKEN`이 있는지 본다(SC-M2 결정 9).
///
/// 못 읽으면 false다. 이 함수의 답은 "사용자의 설정을 덮어쓸까"이고,
/// 못 읽었을 때 덮는 쪽으로 기울면 `/proc`이 안 붙은 부팅에서 rc가 조용히
/// 꺼진다 — `load`가 "읽기에 실패한 파일은 덮어쓰지 않는다"고 정한 것과 같은
/// 방향이다.
///
/// `load`의 읽기 루프를 공유하지 않는다. 저쪽은 optional로 ENOENT 하나를
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
