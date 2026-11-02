//! 사용자 계정 하나의 규칙(HP design 결정 5 · 7, 위험 9).
//!
//! 이름이 무엇이면 되고, passwd · group · shadow에 어떤 줄로 들어가는가. 세 자리가 이것을
//! 본다 — 설치기(질문의 답을 거르고 p2에 `shadow`를 쓴다), init(부팅마다 tmpfs `/etc`에
//! 줄을 짓는다), 그리고 `tars.conf`의 `user=`를 읽는 `config.zig`.
//!
//! 이 파일은 순수하다. 시스템 콜도 로그도 없다 — 글자를 받아 글자를 짓고, 자리가
//! 모자라거나 입력이 규칙 밖이면 null이다. 파일을 읽고 쓰는 것은 부르는 쪽이다.
//! 그래서 `account_test`가 호스트에서 바이트 그대로 본다.

const std = @import("std");
const screen_args = @import("screen_args");

/// 이름의 최대 길이. Debian `useradd`의 기본 한도와 같다.
pub const NAME_MAX: usize = 32;

/// 홈 디렉터리들이 붙는 자리. 홈은 `/home/<이름>`이다.
pub const HOME_ROOT = "/home";

/// 설치 때 Enter만 치면 쓰는 값(사용자 결정 4 · 5, 2026-11-02). `--yes`도 이 값이다.
pub const DEFAULT_NAME = "tars";
pub const DEFAULT_PASSWORD = "tars-linux";

/// 규칙에 맞아도 받지 않는 이름. 정적 passwd · group(`make_initrd.sh`)에 이미 있는 이름이거나
/// 다른 뜻으로 예약된 것이다. 그룹 이름도 막는 것은 사용자와 같은 이름의 그룹을 만들기
/// 때문이다 — `audio`라는 사용자는 `audio` 그룹을 하나 더 만들려 한다. `linuxbrew`는
/// Homebrew의 prefix(`/home/linuxbrew`)가 쓸 자리다(PM).
pub const RESERVED = [_][]const u8{
    "root", "sshd", "messagebus", "nobody", "nogroup", "audio", "tty", "linuxbrew",
};

/// `[a-z_][a-z0-9_-]{0,31}`이고 `RESERVED`가 아니다(design 결정 5).
///
/// 이 모양이 막는 것이 위험 9다 — 콜론과 개행은 passwd 줄을 깨고, `/`와 `.`은 홈 경로를
/// 깬다. 대문자를 막는 것은 Debian의 기본 규칙(`NAME_REGEX`)과 같다.
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > NAME_MAX) return false;
    for (name, 0..) |ch, i| {
        const ok = switch (ch) {
            'a'...'z', '_' => true,
            '0'...'9', '-' => i > 0,
            else => false,
        };
        if (!ok) return false;
    }
    for (RESERVED) |r| {
        if (std.mem.eql(u8, name, r)) return false;
    }
    return true;
}

/// 해시로 받는 글자인가. `mkpasswd`가 내는 것은 `$y$…`이고 그 글자 집합은 crypt의
/// base64(`./0-9A-Za-z`)와 `$`다. 콜론 · 개행 · 공백이 들면 shadow 줄이 깨진다.
/// 잠긴 계정의 `!`도 받는다.
pub fn validHash(hash: []const u8) bool {
    if (hash.len == 0 or hash.len > HASH_MAX) return false;
    for (hash) |ch| {
        const ok = switch (ch) {
            'a'...'z', 'A'...'Z', '0'...'9', '.', '/', '$', '!', '*' => true,
            else => false,
        };
        if (!ok) return false;
    }
    return true;
}

/// yescrypt 해시는 73자 안팎이다. 여유를 둔다.
pub const HASH_MAX: usize = 128;

/// 해시를 못 얻었을 때의 값. `pam_unix`는 `!`로 시작하는 해시를 어떤 비밀번호와도 안 맞춘다.
pub const LOCKED_HASH = "!";

/// `/home/<이름>`. buf에 NUL로 닫아 짓는다.
pub fn homePath(buf: []u8, name: []const u8) ?[:0]const u8 {
    return std.fmt.bufPrintSentinel(buf, HOME_ROOT ++ "/{s}", .{name}, 0) catch null;
}

/// passwd 한 줄(개행 없음). 홈은 `/home/<이름>`, 셸은 `tars.conf`의 `shell=`이 정한 경로다.
pub fn passwdLine(buf: []u8, name: []const u8, shell: []const u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{s}:x:{d}:{d}::" ++ HOME_ROOT ++ "/{s}:{s}", .{
        name, screen_args.USER_UID, screen_args.USER_GID, name, shell,
    }) catch null;
}

/// shadow 한 줄(개행 없음). 날짜 칸을 비운다 — 비어 있으면 나이 규칙이 없다. `0`은
/// `pam_unix`가 "다음 로그인에 바꿔라"로 읽으므로 안 쓴다. 이 기계의 시계는 부팅 직후
/// 1970년일 수 있어서(TD) 오늘 날짜를 적는 것도 안 믿는다.
pub fn shadowLine(buf: []u8, name: []const u8, hash: []const u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{s}:{s}:::::::", .{ name, hash }) catch null;
}

/// 부팅의 `/etc/shadow` 전체. root는 `*`(비밀번호로는 못 들어간다 — 지금과 같다)이고
/// 사용자 줄이 뒤에 붙는다.
pub fn shadowFile(buf: []u8, name: []const u8, hash: []const u8) ?[]const u8 {
    var line_buf: [NAME_MAX + HASH_MAX + 16]u8 = undefined;
    const line = shadowLine(&line_buf, name, hash) orelse return null;
    return std.fmt.bufPrint(buf, "root:*:::::::\n{s}\n", .{line}) catch null;
}

/// `/config/shadow`의 한 줄(`<이름>:<해시>`)을 짓는다. 개행으로 끝난다.
pub fn storeLine(buf: []u8, name: []const u8, hash: []const u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{s}:{s}\n", .{ name, hash }) catch null;
}

/// `/config/shadow`에서 `name`의 해시를 찾는다. 이름이 다르거나 해시가 규칙 밖이면 null —
/// 부르는 쪽은 그때 `LOCKED_HASH`로 간다(부팅은 안 막는다).
pub fn parseStore(text: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (!std.mem.eql(u8, line[0..colon], name)) continue;
        const hash = line[colon + 1 ..];
        return if (validHash(hash)) hash else null;
    }
    return null;
}

/// `in`의 줄들을 `out`에 옮기되 `<name>:`으로 시작하는 줄은 빼고, 끝에 `add`를 붙인다.
/// passwd와 group에 같은 사용자를 두 번 넣지 않게 한다 — `reload`가 `login.apply`를
/// 다시 부르는 것처럼 이 함수도 한 부팅에 여러 번 불려도 결과가 같아야 한다.
///
/// `edit`이 null이 아니면 남는 줄마다 한 번 불러 바꿀 기회를 준다(group의 audio 줄).
fn rebuild(in: []const u8, name: []const u8, add: []const u8, out: []u8, comptime edit: ?fn ([]const u8, []const u8, []u8) ?[]const u8) ?[]const u8 {
    var w: std.Io.Writer = .fixed(out);
    var lines = std.mem.splitScalar(u8, in, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (line.len > name.len and std.mem.startsWith(u8, line, name) and line[name.len] == ':') continue;
        var tmp: [256]u8 = undefined;
        const kept = if (edit) |f| (f(line, name, &tmp) orelse return null) else line;
        w.print("{s}\n", .{kept}) catch return null;
    }
    w.print("{s}\n", .{add}) catch return null;
    return w.buffered();
}

/// passwd 전체에 사용자 줄을 넣은 사본.
pub fn withPasswd(in: []const u8, name: []const u8, shell: []const u8, out: []u8) ?[]const u8 {
    var line_buf: [256]u8 = undefined;
    const line = passwdLine(&line_buf, name, shell) orelse return null;
    return rebuild(in, name, line, out, null);
}

/// group 전체에 사용자 그룹(`<이름>:x:1000:`)을 넣고, `audio` 줄의 구성원을 그 사용자로
/// 둔 사본(plan 확정 6 — 보조 그룹은 audio 하나).
pub fn withGroup(in: []const u8, name: []const u8, out: []u8) ?[]const u8 {
    var line_buf: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "{s}:x:{d}:", .{ name, screen_args.USER_GID }) catch return null;
    return rebuild(in, name, line, out, audioMembers);
}

/// `audio:x:29:<구성원>`의 구성원 칸을 `name` 하나로. 다른 줄은 그대로.
fn audioMembers(line: []const u8, name: []const u8, buf: []u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, "audio:")) return line;
    const colon = std.mem.lastIndexOfScalar(u8, line, ':') orelse return null;
    return std.fmt.bufPrint(buf, "{s}{s}", .{ line[0 .. colon + 1], name }) catch null;
}

/// 비밀번호의 최대 길이. 사람이 치는 한 줄이다 — 이보다 길면 설치기가 다시 묻는다.
pub const PASSWORD_MAX: usize = 128;

/// 받을 수 있는 비밀번호인가. 빈 값은 여기 오기 전에 기본값으로 바뀐다(설치기). 제어 문자를
/// 막는 것은 `mkpasswd -s`가 stdin의 한 줄을 읽기 때문이다 — 개행이 들면 앞부분만 해시가 된다.
pub fn validPassword(pw: []const u8) bool {
    if (pw.len == 0 or pw.len > PASSWORD_MAX) return false;
    for (pw) |ch| if (ch < 0x20 or ch == 0x7f) return false;
    return true;
}

/// `mkpasswd -m yescrypt`의 출력에서 해시를 꺼낸다. 첫 줄이고 `$y$`로 시작해야 한다 —
/// 다른 무엇(경고 · 다른 방식의 해시)이면 null이고 설치기가 디스크를 건드리기 전에 멈춘다.
pub fn hashFromTool(out: []const u8) ?[]const u8 {
    const end = std.mem.indexOfScalar(u8, out, '\n') orelse out.len;
    const line = std.mem.trimEnd(u8, out[0..end], "\r");
    if (!std.mem.startsWith(u8, line, "$y$")) return null;
    return if (validHash(line)) line else null;
}
