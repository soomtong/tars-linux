//! `account.zig`의 검사(HP-M1 plan Task 1, design 위험 9). 순수한 함수뿐이라 파일도
//! 시스템 콜도 없다.
const std = @import("std");
const account = @import("account.zig");

fn expectText(what: []const u8, got: ?[]const u8, want: []const u8) !void {
    const g = got orelse {
        std.debug.print("FAIL: {s} returned null, want \"{s}\"\n", .{ what, want });
        return error.UnexpectedNull;
    };
    if (!std.mem.eql(u8, g, want)) {
        std.debug.print("FAIL: {s}\n  got  \"{s}\"\n  want \"{s}\"\n", .{ what, g, want });
        return error.UnexpectedText;
    }
}

pub fn main() !void {
    // ── 1. 이름 — 받는 것 ──
    const max_name_arr: [account.NAME_MAX]u8 = @splat('a');
    const max_name: []const u8 = &max_name_arr;
    for ([_][]const u8{ "tars", "a", "_x", "hp-user", "u2", "a_b-c9", max_name }) |n| {
        if (!account.validName(n)) {
            std.debug.print("FAIL: validName rejected \"{s}\"\n", .{n});
            return error.NameRejected;
        }
    }

    // ── 2. 이름 — 거절하는 것(위험 9) ──
    const too_long_arr: [account.NAME_MAX + 1]u8 = @splat('a');
    const too_long: []const u8 = &too_long_arr;
    for ([_][]const u8{
        "",           "root",   "Tars", "1abc", "-a",  "a:b",   "a b",  "../x",
        "a/b",        "a.b",    "a\n",  "\n",   "tty", "audio", "sudo", "linuxbrew",
        "messagebus", too_long,
    }) |n| {
        if (account.validName(n)) {
            std.debug.print("FAIL: validName accepted \"{s}\"\n", .{n});
            return error.NameAccepted;
        }
    }

    // ── 3. 해시 ──
    const hash = "$y$j9T$abcdefghijklmnop/.$ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefg";
    if (!account.validHash(hash)) return error.HashRejected;
    if (!account.validHash(account.LOCKED_HASH)) return error.LockedHashRejected;
    for ([_][]const u8{ "", "$y$a:b", "$y$a\nb", "$y$a b" }) |h| {
        if (account.validHash(h)) {
            std.debug.print("FAIL: validHash accepted \"{s}\"\n", .{h});
            return error.HashAccepted;
        }
    }

    // ── 4. 줄 짓기 ──
    var buf: [512]u8 = undefined;
    try expectText("passwdLine", account.passwdLine(&buf, "tars", "/usr/bin/fish"), "tars:x:1000:1000::/home/tars:/usr/bin/fish");
    try expectText("shadowLine", account.shadowLine(&buf, "tars", "$y$x"), "tars:$y$x:::::::");
    try expectText("shadowFile", account.shadowFile(&buf, "tars", "$y$x"), "root:*:::::::\ntars:$y$x:::::::\n");
    try expectText("storeLine", account.storeLine(&buf, "tars", "$y$x"), "tars:$y$x\n");
    var home_buf: [64]u8 = undefined;
    try expectText("homePath", account.homePath(&home_buf, "hpuser"), "/home/hpuser");
    // shadow 줄의 칸 수는 아홉이다(콜론 여덟).
    const sl = account.shadowLine(&buf, "tars", "$y$x").?;
    if (std.mem.count(u8, sl, ":") != 8) return error.ShadowFieldCount;

    // ── 5. /config/shadow 읽기 ──
    try expectText("parseStore", account.parseStore("tars:$y$x\n", "tars"), "$y$x");
    try expectText("parseStore crlf", account.parseStore("other:$y$o\r\ntars:$y$x\r\n", "tars"), "$y$x");
    if (account.parseStore("tars:$y$x\n", "hpuser") != null) return error.StoreWrongName;
    if (account.parseStore("tars:\n", "tars") != null) return error.StoreEmptyHash;
    if (account.parseStore("tars:$y$a:b\n", "tars") != null) return error.StoreBadHash;
    if (account.parseStore("", "tars") != null) return error.StoreEmpty;
    // 이름의 접두사로는 안 맞는다.
    if (account.parseStore("tarsx:$y$x\n", "tars") != null) return error.StorePrefix;

    // ── 6. passwd · group 사본 — make_initrd.sh의 정적 파일 모양 그대로 ──
    const passwd =
        \\root:x:0:0:root:/:/usr/bin/fish
        \\sshd:x:100:65534::/run/sshd:/usr/sbin/nologin
        \\messagebus:x:101:101::/nonexistent:/usr/sbin/nologin
        \\
    ;
    const passwd_want =
        \\root:x:0:0:root:/:/usr/bin/fish
        \\sshd:x:100:65534::/run/sshd:/usr/sbin/nologin
        \\messagebus:x:101:101::/nonexistent:/usr/sbin/nologin
        \\tars:x:1000:1000::/home/tars:/usr/bin/fish
        \\
    ;
    var out: [1024]u8 = undefined;
    const p1 = account.withPasswd(passwd, "tars", "/usr/bin/fish", &out) orelse return error.PasswdNull;
    try expectText("withPasswd", p1, passwd_want);
    // 두 번 불러도 같다 — 셸이 바뀐 reload면 그 줄만 바뀐다.
    var out2: [1024]u8 = undefined;
    const p2 = account.withPasswd(p1, "tars", "/usr/bin/zsh", &out2) orelse return error.PasswdNull;
    if (std.mem.count(u8, p2, "tars:x:1000") != 1) return error.PasswdDuplicated;
    if (std.mem.indexOf(u8, p2, "tars:x:1000:1000::/home/tars:/usr/bin/zsh\n") == null) return error.PasswdNotReplaced;
    // 이름의 접두사가 같은 남의 줄은 안 지운다.
    const p3 = account.withPasswd("tarsx:x:5:5::/:/bin/sh\n", "tars", "/bin/sh", &out) orelse return error.PasswdNull;
    if (std.mem.indexOf(u8, p3, "tarsx:") == null) return error.PasswdPrefixEaten;

    const group =
        \\root:x:0:
        \\tty:x:5:
        \\sudo:x:27:
        \\audio:x:29:
        \\messagebus:x:101:
        \\nogroup:x:65534:
        \\
    ;
    const group_want =
        \\root:x:0:
        \\tty:x:5:
        \\sudo:x:27:tars
        \\audio:x:29:tars
        \\messagebus:x:101:
        \\nogroup:x:65534:
        \\tars:x:1000:
        \\
    ;
    const g1 = account.withGroup(group, "tars", &out) orelse return error.GroupNull;
    try expectText("withGroup", g1, group_want);
    const g2 = account.withGroup(g1, "tars", &out2) orelse return error.GroupNull;
    try expectText("withGroup twice", g2, group_want);
    // 정적 group에 sudo · audio 줄이 없으면 null(HP-M2) — initrd와 코드가 어긋난 것을 부팅 로그로 드러낸다.
    // 접두사만 같은 줄(`sudoers:`)은 그 줄로 치지 않는다.
    if (account.withGroup("root:x:0:\naudio:x:29:\n", "tars", &out) != null) return error.GroupWithoutSudo;
    if (account.withGroup("root:x:0:\nsudo:x:27:\n", "tars", &out) != null) return error.GroupWithoutAudio;
    if (account.withGroup("audio:x:29:\nsudoers:x:30:\n", "tars", &out) != null) return error.GroupPrefixTaken;

    // 자리가 모자라면 null — 잘린 파일을 쓰지 않는다.
    var tiny: [16]u8 = undefined;
    if (account.withPasswd(passwd, "tars", "/usr/bin/fish", &tiny) != null) return error.TinyNotNull;

    // ── 7. 비밀번호 · mkpasswd의 출력 ──
    if (!account.validPassword(account.DEFAULT_PASSWORD)) return error.DefaultPasswordRejected;
    if (!account.validPassword("p a s s:with/odd$chars")) return error.PasswordRejected;
    for ([_][]const u8{ "", "a\nb", "a\x00b", "tab\there", "del\x7f" }) |pw| {
        if (account.validPassword(pw)) return error.PasswordAccepted;
    }
    const long_pw: [account.PASSWORD_MAX + 1]u8 = @splat('p');
    if (account.validPassword(&long_pw)) return error.LongPasswordAccepted;
    try expectText("hashFromTool", account.hashFromTool(hash ++ "\n"), hash);
    try expectText("hashFromTool no newline", account.hashFromTool(hash), hash);
    for ([_][]const u8{ "", "\n", "$6$salt$abc\n", "mkpasswd: unknown method\n", "$y$a b\n" }) |o| {
        if (account.hashFromTool(o) != null) {
            std.debug.print("FAIL: hashFromTool took \"{s}\"\n", .{o});
            return error.HashFromToolTook;
        }
    }

    std.debug.print("account_test: all checks passed\n", .{});
}
