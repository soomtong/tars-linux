//! TC-M1. `config_front_edit.zig`의 검사. config_edit_test와 같은 모양이다 — 호스트 아키텍처의
//! 실행 파일이고, 실패하면 `FAIL:` 줄을 찍고 0이 아닌 코드로 끝난다.
const std = @import("std");
const linux = std.os.linux;
const fe = @import("config_front_edit.zig");

/// tars-dictate의 자리. `zig build test`는 init/에서 돈다.
const DICTATE_PATH: [:0]const u8 = "../kernel/dictation/tars-dictate";

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

fn expectText(got: ?[]const u8, want: []const u8, what: []const u8) !void {
    const g = got orelse return fail("{s}: got null, want\n{s}", .{ what, want });
    if (!std.mem.eql(u8, g, want)) return fail("{s}:\n--- got ---\n{s}\n--- want ---\n{s}", .{ what, g, want });
}

fn readAll(path: [:0]const u8, buf: []u8) ![]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (linux.errno(rc) != .SUCCESS) return fail("cannot open {s}", .{path});
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (linux.errno(n) != .SUCCESS) return fail("cannot read {s}", .{path});
        if (n == 0) break;
        len += n;
    }
    return buf[0..len];
}

/// `wpa_passphrase tars-wl`에 `tars-secret`을 표준 입력으로 준 출력의 모양. 첫 줄은 표준 입력에서
/// 읽을 때만 나온다. psk는 PBKDF2-SHA1(4096회)의 값이다. 게스트의 진짜 출력이 같은 길을 지나는 것은
/// wifi 체인 검사 12가 본다.
const WPA_OUT =
    "# reading passphrase from stdin\n" ++
    "network={\n" ++
    "\tssid=\"tars-wl\"\n" ++
    "\t#psk=\"tars-secret\"\n" ++
    "\tpsk=3c51e611003bdbb9d4c5553147982976c6760ed39de1705f73d5c1c08f97c3ac\n" ++
    "}\n";
const WPA_BLOCK =
    "network={\n" ++
    "\tssid=\"tars-wl\"\n" ++
    "\tpsk=3c51e611003bdbb9d4c5553147982976c6760ed39de1705f73d5c1c08f97c3ac\n" ++
    "}\n";

/// 소문자와 밑줄만으로 된 낱말인가 — tars-dictate의 case 줄에서 키 이름을 고른다.
fn isName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| if (!(ch >= 'a' and ch <= 'z') and ch != '_') return false;
    return true;
}

pub fn main() !void {
    // ── 1. 포트와 규칙 한 줄 ────────────────────────────────────────────
    const good = [_]struct { []const u8, u16, fe.Proto }{
        .{ "22", 22, .tcp }, .{ "65535", 65535, .tcp }, .{ "5353/udp", 5353, .udp }, .{ "8080/tcp", 8080, .tcp },
    };
    for (good) |g| {
        const s = fe.parsePort(g[0]) orelse return fail("parsePort {s} refused", .{g[0]});
        if (s.port != g[1] or s.proto != g[2]) return fail("parsePort {s}", .{g[0]});
    }
    for ([_][]const u8{ "", "0", "65536", "022", "22/sctp", "22/", "/udp", "2 2", "22/udp/x", "-1", "99999" }) |b| {
        if (fe.parsePort(b) != null) return fail("parsePort accepted '{s}'", .{b});
    }
    var rb: [32]u8 = undefined;
    try expectText(fe.ruleLine(&rb, .{ .port = 22, .proto = .tcp }), "tcp dport 22 accept", "ruleLine tcp");
    try expectText(fe.ruleLine(&rb, .{ .port = 5353, .proto = .udp }), "udp dport 5353 accept", "ruleLine udp");

    var out: [4096]u8 = undefined;
    const header = fe.RULES_HEADER;
    const one = fe.appendLine(&out, header, "tcp dport 22 accept").?;
    var two_buf: [4096]u8 = undefined;
    const two = fe.appendLine(&two_buf, one, "udp dport 5353 accept").?;
    if (!fe.hasLine(two, "tcp dport 22 accept") or !fe.hasLine(two, "udp dport 5353 accept")) return fail("hasLine missed a rule", .{});
    if (fe.hasLine(two, "tcp dport 2 accept")) return fail("hasLine matched a prefix", .{});
    var rm_buf: [4096]u8 = undefined;
    const back = fe.removeLine(&rm_buf, two, "udp dport 5353 accept").?;
    try expectText(back, one, "removeLine gives back the one-rule file");
    try expectText(fe.removeLine(&rm_buf, "a\n  tcp dport 22 accept  \nb", "tcp dport 22 accept"), "a\nb", "removeLine with spaces and no final newline");
    try expectText(fe.appendLine(&out, "x", "y"), "x\ny\n", "appendLine without a final newline");
    try expectText(fe.appendLine(&out, "", "y"), "y\n", "appendLine on nothing");
    if (fe.keyCount(header) != 0 or fe.keyCount(two) != 2) return fail("rule count", .{});
    std.debug.print("config_front_edit_test: ports, the one rule line, and adding · finding · removing it\n", .{});

    // ── 2. wpa_passphrase의 덩어리 ──────────────────────────────────────
    var blk: [1024]u8 = undefined;
    try expectText(fe.networkBlock(&blk, WPA_OUT), WPA_BLOCK, "networkBlock drops the comment and #psk");
    if (fe.networkBlock(&blk, "Passphrase must be 8..63 characters\n") != null) return fail("networkBlock took an error", .{});
    if (fe.networkBlock(&blk, "network={\n\tssid=\"x\"\n") != null) return fail("networkBlock took an unclosed block", .{});
    try expectText(fe.ssidLine(WPA_BLOCK), "ssid=\"tars-wl\"", "ssidLine");

    const human =
        "country=KR\n" ++
        "# my home\n" ++
        "network={\n" ++
        "\tssid=\"other\"\n" ++
        "\tpsk=\"x\"\n" ++
        "}\n" ++
        "network={\n" ++
        "\tssid=\"tars-wl\"\n" ++
        "\tpsk=\"wrong-secret\"\n" ++
        "\tpriority=3\n" ++
        "}\n";
    var pl: [4096]u8 = undefined;
    const placed = fe.placeNetwork(&pl, human, WPA_BLOCK).?;
    if (!placed.replaced) return fail("placeNetwork did not find the tars-wl block", .{});
    try expectText(placed.text, "country=KR\n# my home\nnetwork={\n\tssid=\"other\"\n\tpsk=\"x\"\n}\n" ++ WPA_BLOCK, "placeNetwork replaces only that block");
    const appended = fe.placeNetwork(&pl, "country=KR\n# ssid=\"tars-wl\" is not a block\n", WPA_BLOCK).?;
    if (appended.replaced) return fail("placeNetwork matched a comment", .{});
    try expectText(appended.text, "country=KR\n# ssid=\"tars-wl\" is not a block\n" ++ WPA_BLOCK, "placeNetwork appends");
    try expectText(fe.placeNetwork(&pl, "", WPA_BLOCK).?.text, WPA_BLOCK, "placeNetwork on a new file");
    try expectText(fe.placeNetwork(&pl, "ctrl_interface=x", WPA_BLOCK).?.text, "ctrl_interface=x\n" ++ WPA_BLOCK, "placeNetwork without a final newline");

    var cc: [4096]u8 = undefined;
    try expectText(fe.setCountry(&cc, WPA_BLOCK, "KR"), "country=KR\n" ++ WPA_BLOCK, "setCountry adds at the top");
    try expectText(fe.setCountry(&cc, human, "US"), "country=US" ++ human["country=KR".len..], "setCountry replaces");
    try expectText(fe.setCountry(&cc, "network={\n\tcountry=XX\n}\n", "KR"), "country=KR\nnetwork={\n\tcountry=XX\n}\n", "setCountry skips the inside of a block");
    for ([_][]const u8{ "KR", "US" }) |c| if (!fe.countryOk(c)) return fail("countryOk {s}", .{c});
    for ([_][]const u8{ "kr", "K", "KOR", "K1", "" }) |c| if (fe.countryOk(c)) return fail("countryOk took {s}", .{c});
    std.debug.print("config_front_edit_test: wpa_passphrase's block without #psk, put over the same SSID or appended, country at the top\n", .{});

    // ── 3. ssh 키 ──────────────────────────────────────────────────────
    const k1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk1 tc1@host";
    const k1_body = "AAAAC3NzaC1lZDI1NTE5AAAAIOk1";
    try expectText(fe.keyBody(k1), k1_body, "keyBody");
    try expectText(fe.keyBody("no-pty,from=\"10.0.0.0/8\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk1 x"), k1_body, "keyBody behind options");
    if (fe.keyBody("ssh-ed25519 AAAA") != null) return fail("keyBody took a stub", .{});
    const keys = "# mine\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk1 other-comment\n\n";
    if (!fe.hasKey(keys, k1_body)) return fail("hasKey missed the same body under another comment", .{});
    if (fe.hasKey(keys, "AAAAC3NzaC1lZDI1NTE5AAAAIOk2")) return fail("hasKey matched another key", .{});
    if (fe.keyCount(keys) != 1 or fe.keyCount("") != 0) return fail("keyCount", .{});
    std.debug.print("config_front_edit_test: a key is the same key by its AAAA body, whatever the comment or options\n", .{});

    // ── 4. 받아쓰기 ────────────────────────────────────────────────────
    try expectText(fe.apiKey("  gsk_abc123\n"), "gsk_abc123", "apiKey trims");
    for ([_][]const u8{ "", " \n", "gsk abc", "gsk_\x1b[0m" }) |b| if (fe.apiKey(b) != null) return fail("apiKey took '{s}'", .{b});
    if (!fe.hasControl("a\nb") or fe.hasControl("https://x/y?z=1")) return fail("hasControl", .{});

    // 이름 여덟이 tars-dictate의 case와 같다. 그 파일의 `case $key in` ~ `esac`에서 `이름)` 줄을 모은다 —
    // 이름은 소문자와 밑줄뿐이라 안쪽 case의 `on|off)` · `*)`는 안 걸린다.
    var dbuf: [65536]u8 = undefined;
    const dictate = try readAll(DICTATE_PATH, &dbuf);
    const from = std.mem.indexOf(u8, dictate, "case $key in") orelse return fail("tars-dictate has no case $key in", .{});
    const to = std.mem.indexOfPos(u8, dictate, from, "\n    esac") orelse return fail("no esac after it", .{});
    var seen: usize = 0;
    var it = std.mem.splitScalar(u8, dictate[from..to], '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t");
        const close = std.mem.indexOfScalar(u8, t, ')') orelse continue;
        const name = t[0..close];
        if (!isName(name)) continue;
        if (!fe.isDictationKey(name)) return fail("tars-dictate knows '{s}', DICTATION_KEYS does not", .{name});
        seen += 1;
    }
    if (seen != fe.DICTATION_KEYS.len) return fail("tars-dictate's case has {d} keys, DICTATION_KEYS {d}", .{ seen, fe.DICTATION_KEYS.len });
    std.debug.print("config_front_edit_test: the {d} dictation keys are tars-dictate's own, read from its case\n", .{seen});

    std.debug.print("PASS\n", .{});
}
