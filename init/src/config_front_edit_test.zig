//! TC-M1. `config_front_edit.zig`의 검사. config_edit_test와 같은 모양이다 — 호스트 아키텍처의
//! 실행 파일이고, 실패하면 `FAIL:` 줄을 찍고 0이 아닌 코드로 끝난다.
const std = @import("std");
const linux = std.os.linux;
const fe = @import("config_front_edit.zig");
const control = @import("control.zig");

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

/// 인자 union의 칸이 want인가.
fn expectTag(got: anytype, want: std.meta.Tag(@TypeOf(got)), what: []const u8) !void {
    if (std.meta.activeTag(got) != want) return fail("{s}: got .{s}, want .{s}", .{ what, @tagName(got), @tagName(want) });
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

    // ── 5. 동사 다섯의 인자 ────────────────────────────────────────────
    try expectTag(fe.wifiArgs(&.{}), .status, "wifi");
    const w1 = fe.wifiArgs(&.{"tars-wl"});
    try expectTag(w1, .add, "wifi tars-wl");
    try expectText(w1.add.ssid, "tars-wl", "wifi tars-wl ssid");
    if (w1.add.country != null) return fail("wifi tars-wl has a country", .{});
    const w2 = fe.wifiArgs(&.{ "tars-wl", "--country", "KR" });
    try expectTag(w2, .add, "wifi tars-wl --country KR");
    try expectText(w2.add.country, "KR", "wifi tars-wl --country KR country");
    try expectTag(fe.wifiArgs(&.{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}), .add, "wifi with a 32-byte SSID");
    try expectTag(fe.wifiArgs(&.{ "tars-wl", "--country", "kr" }), .bad_country, "wifi --country kr");
    try expectTag(fe.wifiArgs(&.{ "", "--country", "kr" }), .bad_country, "wifi looks at the country before the SSID");
    try expectTag(fe.wifiArgs(&.{ "tars-wl", "--country" }), .usage, "wifi --country without CC");
    try expectTag(fe.wifiArgs(&.{ "tars-wl", "-c", "KR" }), .usage, "wifi -c KR");
    try expectTag(fe.wifiArgs(&.{""}), .bad_ssid, "wifi ''");
    try expectTag(fe.wifiArgs(&.{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}), .bad_ssid, "wifi with a 33-byte SSID");
    try expectTag(fe.wifiArgs(&.{"a\tb"}), .bad_ssid, "wifi with a tab");

    try expectTag(fe.sshArgs(&.{}), .status, "ssh");
    try expectTag(fe.sshArgs(&.{"on"}), .on, "ssh on");
    try expectTag(fe.sshArgs(&.{"off"}), .off, "ssh off");
    try expectTag(fe.sshArgs(&.{"foo"}), .bad_verb, "ssh foo");
    try expectTag(fe.sshArgs(&.{ "on", "x" }), .usage, "ssh on x");

    try expectTag(fe.sshKeyArgs(&.{}), .usage, "ssh-key");
    try expectTag(fe.sshKeyArgs(&.{"list"}), .list, "ssh-key list");
    try expectTag(fe.sshKeyArgs(&.{ "list", "x" }), .usage, "ssh-key list x");
    const k_in = fe.sshKeyArgs(&.{"add"});
    try expectTag(k_in, .add, "ssh-key add");
    if (k_in.add != null) return fail("ssh-key add without KEY is not stdin", .{});
    try expectText(fe.sshKeyArgs(&.{ "add", k1 }).add, k1, "ssh-key add KEY");
    try expectTag(fe.sshKeyArgs(&.{ "add", "a", "b" }), .usage, "ssh-key add a b");
    try expectTag(fe.sshKeyArgs(&.{"rm"}), .usage, "ssh-key rm");

    try expectTag(fe.firewallArgs(&.{}), .status, "firewall");
    const f1 = fe.firewallArgs(&.{ "allow", "22" });
    try expectTag(f1, .change, "firewall allow 22");
    if (!f1.change.allow or f1.change.spec.port != 22 or f1.change.spec.proto != .tcp) return fail("firewall allow 22", .{});
    const f2 = fe.firewallArgs(&.{ "deny", "5353/udp" });
    try expectTag(f2, .change, "firewall deny 5353/udp");
    if (f2.change.allow or f2.change.spec.port != 5353 or f2.change.spec.proto != .udp) return fail("firewall deny 5353/udp", .{});
    try expectTag(fe.firewallArgs(&.{"allow"}), .usage, "firewall allow");
    try expectTag(fe.firewallArgs(&.{ "open", "22" }), .usage, "firewall open 22");
    try expectTag(fe.firewallArgs(&.{ "allow", "0" }), .bad_port, "firewall allow 0");
    try expectTag(fe.firewallArgs(&.{ "open", "0" }), .usage, "firewall looks at the verb before the port");

    try expectTag(fe.dictationArgs(&.{}), .status, "dictation");
    const d_in = fe.dictationArgs(&.{"key"});
    try expectTag(d_in, .key, "dictation key");
    if (d_in.key != null) return fail("dictation key without KEY is not stdin", .{});
    try expectText(fe.dictationArgs(&.{ "key", "gsk_abc" }).key, "gsk_abc", "dictation key KEY");
    try expectTag(fe.dictationArgs(&.{ "key", "a", "b" }), .usage, "dictation key a b");
    try expectTag(fe.dictationArgs(&.{"set"}), .usage, "dictation set");
    try expectTag(fe.dictationArgs(&.{"bogus"}), .usage, "dictation bogus");
    const d_set = fe.dictationArgs(&.{ "set", " language = ko", "max_seconds=1" });
    try expectTag(d_set, .set, "dictation set two");
    if (d_set.set.len != 2) return fail("dictation set two gives {d}", .{d_set.set.len});
    try expectText(fe.dictationArgs(&.{ "set", "max_seconds" }).no_equals, "max_seconds", "dictation set without =");
    try expectText(fe.dictationArgs(&.{ "set", "colour=red" }).unknown_key, "colour", "dictation set colour");
    try expectText(fe.dictationArgs(&.{ "set", "language=k\x1bo" }).control_byte, "language", "dictation set with ESC");
    try expectText(fe.dictationArgs(&.{ "set", "colour", "language=x" }).no_equals, "colour", "dictation set stops at the first");
    try expectText(fe.dictationArgs(&.{ "set", "language=ko", "colour=x", "nokey" }).unknown_key, "colour", "dictation set stops at the first refusal");
    std.debug.print("config_front_edit_test: the five verbs' arguments — what each takes, which refusal, stopping at the first\n", .{});

    // ── 6. wifi의 말 ───────────────────────────────────────────────────
    var sbuf: [2048]u8 = undefined;
    var s = control.Out{ .buf = &sbuf };
    fe.wifiStatusLines(&s, "country=KR\nnetwork={\n\tssid=\"tars-wl\"\n\tpsk=abc\n}\n");
    try expectText(s.bytes(), "country=KR\nssid=\"tars-wl\"\n", "wifiStatusLines shows names, not psk");
    const WPA = "/config/wpa_supplicant.conf";
    s = control.Out{ .buf = &sbuf };
    fe.wifiDone(&s, "tars-wl", WPA, false, false, false, false);
    try expectText(s.bytes(), "wifi: tars-wl added in /config/wpa_supplicant.conf\n" ++
        "apply now: tars-config reload starts wpa_supplicant (or the next boot)\n", "wifiDone on a new file");
    s = control.Out{ .buf = &sbuf };
    fe.wifiDone(&s, "tars-wl", WPA, true, true, false, true);
    try expectText(s.bytes(), "wifi: tars-wl replaced in /config/wpa_supplicant.conf (with country)\n" ++
        "apply now: tars-service restart wpa_supplicant\n", "wifiDone replaced with country");
    s = control.Out{ .buf = &sbuf };
    fe.wifiDone(&s, "tars-wl", WPA, false, false, true, false);
    try expectText(s.bytes(), "wifi: tars-wl added in /config/wpa_supplicant.conf\n" ++
        "net=off: wifi needs the network on — tars-config set net=dhcp\n" ++
        "apply now: tars-config reload starts wpa_supplicant (or the next boot)\n", "wifiDone with net=off");
    s = control.Out{ .buf = &sbuf };
    fe.wifiDone(&s, "tars-wl", WPA, false, true, true, true);
    try expectText(s.bytes(), "wifi: tars-wl added in /config/wpa_supplicant.conf (with country)\n" ++
        "net=off: wifi needs the network on — tars-config set net=dhcp\n" ++
        "apply now: tars-service restart wpa_supplicant\n", "wifiDone added to a file with country and net=off");
    std.debug.print("config_front_edit_test: wifi shows only ssid and country, and says what it did and the next step\n", .{});

    // ── 7. ssh의 말 ────────────────────────────────────────────────────
    try expectText(fe.keyLine("  " ++ k1 ++ "\r\n"), k1, "keyLine trims");
    for ([_][]const u8{ "", " \n ", k1 ++ "\n" ++ k1, "ssh-ed25519 AAAA\x1b x" }) |b| if (fe.keyLine(b) != null) return fail("keyLine took '{s}'", .{b});
    try expectText(fe.sshdText(.template), "on (/config/services.d/sshd -> /etc/tars/services/sshd)", "sshdText template");
    try expectText(fe.sshdText(.other), "/config/services.d/sshd is yours, not the template", "sshdText other");
    try expectText(fe.sshdText(.none), "off", "sshdText none");
    const NFT_DIR = "/config/nftables.d";
    s = control.Out{ .buf = &sbuf };
    fe.firewall22(&s, fe.RULES_HEADER ++ "tcp dport 22 accept\n", NFT_DIR);
    try expectText(s.bytes(), "firewall=on: tars-config opened port 22\n", "firewall22 opened");
    s = control.Out{ .buf = &sbuf };
    fe.firewall22(&s, fe.RULES_HEADER, NFT_DIR);
    try expectText(s.bytes(), "firewall=on: port 22 is open only if a file in /config/nftables.d says so; tars-config firewall allow 22\n", "firewall22 not here");
    std.debug.print("config_front_edit_test: one key line, the sshd link in words, and whether tars-config opened 22\n", .{});

    // ── 8. firewall의 말 ───────────────────────────────────────────────
    s = control.Out{ .buf = &sbuf };
    const n_rules = fe.firewallRules(&s, fe.RULES_HEADER ++ "tcp dport 22 accept\n\n  udp dport 5353 accept \n");
    try expectText(s.bytes(), "tcp dport 22 accept\nudp dport 5353 accept\n", "firewallRules");
    if (n_rules != 2) return fail("firewallRules counted {d}", .{n_rules});
    s = control.Out{ .buf = &sbuf };
    if (fe.firewallRules(&s, fe.RULES_HEADER) != 0 or s.len != 0) return fail("firewallRules on the header", .{});

    const r22 = "tcp dport 22 accept";
    const with22 = fe.RULES_HEADER ++ r22 ++ "\n";
    var fc: [4096]u8 = undefined;
    try expectText(fe.firewallChange(&fc, "", true, r22).changed, with22, "firewallChange allow on a new file");
    try expectTag(fe.firewallChange(&fc, with22, true, r22), .same, "firewallChange allow again");
    try expectText(fe.firewallChange(&fc, with22, false, r22).changed, fe.RULES_HEADER, "firewallChange deny");
    try expectTag(fe.firewallChange(&fc, "", false, r22), .same, "firewallChange deny what is not here");
    var small: [8]u8 = undefined;
    try expectTag(fe.firewallChange(&small, "", true, r22), .overflow, "firewallChange overflow");

    s = control.Out{ .buf = &sbuf };
    fe.firewallSaid(&s, true, r22, true, NFT_DIR);
    try expectText(s.bytes(), "firewall: opened tcp dport 22 accept\n", "firewallSaid opened");
    s = control.Out{ .buf = &sbuf };
    fe.firewallSaid(&s, false, r22, true, NFT_DIR);
    try expectText(s.bytes(), "firewall: closed tcp dport 22 accept\n", "firewallSaid closed");
    s = control.Out{ .buf = &sbuf };
    fe.firewallSaid(&s, true, r22, false, NFT_DIR);
    try expectText(s.bytes(), "firewall: tcp dport 22 accept was already open here\n", "firewallSaid already open");
    s = control.Out{ .buf = &sbuf };
    fe.firewallSaid(&s, false, r22, false, NFT_DIR);
    try expectText(s.bytes(), "firewall: tcp dport 22 accept was not opened by tars-config\n" ++
        "rules you wrote yourself live in other files under /config/nftables.d; this command does not touch them\n", "firewallSaid not opened here");
    std.debug.print("config_front_edit_test: firewall lists its rules, adds over the header, removes only its own, and says so\n", .{});

    // ── 9. dictation의 말 ──────────────────────────────────────────────
    var wa: [256]u8 = undefined;
    var wb: [256]u8 = undefined;
    const set_args = fe.dictationArgs(&.{ "set", " language = ko", "max_seconds=1" }).set;
    s = control.Out{ .buf = &sbuf };
    try expectText(fe.dictationApply(&s, .{ &wa, &wb }, "# mine\nlanguage=en\n", set_args), "# mine\nlanguage=ko\nmax_seconds=1\n", "dictationApply text");
    try expectText(s.bytes(), "dictation: language=ko\ndictation: max_seconds=1\n", "dictationApply lines");
    var na: [16]u8 = undefined;
    var nb: [16]u8 = undefined;
    s = control.Out{ .buf = &sbuf };
    if (fe.dictationApply(&s, .{ &na, &nb }, "", set_args) != null) return fail("dictationApply did not overflow", .{});
    try expectText(s.bytes(), "dictation: language=ko\n", "dictationApply printed the pair before the overflow");

    s = control.Out{ .buf = &sbuf };
    const unknown = fe.dictationUnknown(&s, "# colour=x\n\nlanguage=ko\ncolour=red\nno equals here\n  speed = 2\n", "/config/dictation.conf");
    try expectText(s.bytes(), "/config/dictation.conf line 4: tars-dictate does not know the key 'colour'\n" ++
        "/config/dictation.conf line 6: tars-dictate does not know the key 'speed'\n", "dictationUnknown");
    if (unknown != 2) return fail("dictationUnknown counted {d}", .{unknown});
    std.debug.print("config_front_edit_test: dictation writes pair by pair, and check names the unknown keys by line\n", .{});

    std.debug.print("PASS\n", .{});
}
