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

/// 설정 전체. 필드의 기본값이 곧 "설정 파일이 없을 때의 TARS"다.
pub const Config = struct {
    shell: Shell = .fish,
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
fn parse(text: []const u8) Config {
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
    const text = std.fmt.bufPrint(&buf,
        \\# TARS configuration. Edit and reboot to apply.
        \\# shell: fish | bash | zsh
        \\shell={s}
        \\
    , .{@tagName(c.shell)}) catch return error.FormatFailed;

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
