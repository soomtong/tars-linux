//! TC-M1. `tars-config`의 앞문 넷(wifi · ssh · firewall · dictation)이 쓰는 글자의 일
//! (TC design 결정 12 ~ 15).
//!
//! 시스템 콜이 하나도 없다 — `config_front_edit_test.zig`가 호스트에서 전부 본다. 파일을
//! 열고 쓰고 남의 도구(`wpa_passphrase` · `ssh-keygen` · `nft`)를 부르는 것은
//! `config_front.zig`다. M0의 `config_edit.zig` ↔ `config_cli.zig`와 같은 가름이다.
//!
//! 여기서 남의 문법을 파싱하지 않는다(결정 10). 하는 일은 셋뿐이다 — 우리가 짓는 한 줄
//! (`tcp dport 22 accept`)을 짓고 찾는 것, 남의 도구가 낸 덩어리를 그대로 옮기는 것, 그
//! 덩어리를 같은 이름의 덩어리와 바꿔 끼울 자리를 찾는 것.
//!
//! HC-M1. 동사마다 인자를 가르는 것과 찍는 문장도 여기다(HC design 결정 5 · 6). 시스템 콜 쪽은
//! 가른 칸을 `switch`로 받고, 파일 · 링크 · tars.conf에서 읽은 것을 문장 함수에 넘긴다.
const std = @import("std");
const edit = @import("config_edit.zig");

// ── 방화벽 ────────────────────────────────────────────────────────────

pub const Proto = enum { tcp, udp };

pub const PortSpec = struct { port: u16, proto: Proto };

/// `22` · `5353/udp` · `8080/tcp`. 포트는 1 ~ 65535, 앞의 0은 안 받는다.
pub fn parsePort(text: []const u8) ?PortSpec {
    var it = std.mem.splitScalar(u8, text, '/');
    const num = it.next() orelse return null;
    const proto_text = it.next();
    if (it.next() != null) return null;
    if (num.len == 0 or num.len > 5 or num[0] == '0') return null;
    var v: u32 = 0;
    for (num) |c| {
        if (c < '0' or c > '9') return null;
        v = v * 10 + (c - '0');
    }
    if (v == 0 or v > 65535) return null;
    const proto: Proto = if (proto_text) |p| (std.meta.stringToEnum(Proto, p) orelse return null) else .tcp;
    return .{ .port = @intCast(v), .proto = proto };
}

/// 이 명령이 쓰는 nft 한 줄. 사람이 `nftables.d`에 손으로 적는 모양과 같다(FW design 결정 3) —
/// `firewall.nft`의 `chain input` 안으로 include된다.
pub fn ruleLine(buf: []u8, spec: PortSpec) []const u8 {
    return std.fmt.bufPrint(buf, "{s} dport {d} accept", .{ @tagName(spec.proto), spec.port }) catch unreachable;
}

/// text에 그 줄이 있는가(양 끝 공백을 떼고 글자 그대로).
pub fn hasLine(text: []const u8, line: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| if (std.mem.eql(u8, std.mem.trim(u8, raw, " \t\r"), line)) return true;
    return false;
}

/// 끝에 한 줄을 더한다. 끝에 개행이 없던 글자면 개행을 먼저. 넘치면 null.
pub fn appendLine(out: []u8, text: []const u8, line: []const u8) ?[]const u8 {
    const sep: []const u8 = if (text.len > 0 and text[text.len - 1] != '\n') "\n" else "";
    return std.fmt.bufPrint(out, "{s}{s}{s}\n", .{ text, sep, line }) catch null;
}

/// 그 줄(양 끝 공백을 뗀 글자가 같은 줄)을 전부 뺀다. 다른 줄은 바이트 하나 안 바뀐다.
pub fn removeLine(out: []u8, text: []const u8, line: []const u8) ?[]const u8 {
    var len: usize = 0;
    var start: usize = 0;
    while (start < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        const next = if (end < text.len) end + 1 else end;
        if (!std.mem.eql(u8, std.mem.trim(u8, text[start..end], " \t\r"), line)) {
            const piece = text[start..next];
            if (len + piece.len > out.len) return null;
            @memcpy(out[len..][0..piece.len], piece);
            len += piece.len;
        }
        start = next;
    }
    return out[0..len];
}

/// 이 명령이 쓰는 nft 파일의 머리. 사람이 그 파일을 열었을 때 누가 쓰는지를 안다.
pub const RULES_HEADER =
    \\# Written by tars-config firewall allow|deny (TC design 결정 14). Your own rules go in
    \\# another file in this directory; this one is rewritten by that command.
    \\
;

/// `firewall` 상태의 규칙 줄 — 이 명령의 nft 파일에서 빈 줄 · 주석을 뺀 줄을 하나씩. 그 수를 돌려준다.
pub fn firewallRules(sink: anytype, text: []const u8) usize {
    var it = std.mem.splitScalar(u8, text, '\n');
    var n: usize = 0;
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        sink.print("{s}\n", .{t});
        n += 1;
    }
    return n;
}

/// `allow` · `deny`가 그 파일에 할 일. `same`이면 쓸 것이 없다 — 이미 열렸거나, 이 명령이 연 적이 없다.
pub const FirewallChange = union(enum) { same, changed: []const u8, overflow };

/// allow는 빈 파일이면 `RULES_HEADER` 위에 더한다. deny는 이 명령의 파일에서만 뺀다(결정 14).
pub fn firewallChange(out: []u8, text: []const u8, allow: bool, rule: []const u8) FirewallChange {
    if (allow) {
        const base = if (text.len == 0) RULES_HEADER else text;
        if (hasLine(base, rule)) return .same;
        return if (appendLine(out, base, rule)) |t| .{ .changed = t } else .overflow;
    }
    if (!hasLine(text, rule)) return .same;
    return if (removeLine(out, text, rule)) |t| .{ .changed = t } else .overflow;
}

/// `allow` · `deny`의 결과. changed는 `firewallChange`가 `changed`였는가.
pub fn firewallSaid(sink: anytype, allow: bool, rule: []const u8, changed: bool, nft_dir: []const u8) void {
    if (changed) {
        sink.print("firewall: {s} {s}\n", .{ if (allow) "opened" else "closed", rule });
        return;
    }
    sink.print("firewall: {s} was {s}\n", .{ rule, if (allow) "already open here" else "not opened by tars-config" });
    if (!allow) sink.print("rules you wrote yourself live in other files under {s}; this command does not touch them\n", .{nft_dir});
}

// ── 무선 ──────────────────────────────────────────────────────────────

/// `wpa_passphrase`의 출력에서 `network={ … }` 덩어리만 남긴다(결정 12).
///
/// 버리는 것은 `#`로 시작하는 줄 — `# reading passphrase from stdin`과 평문 비밀번호
/// `#psk="…"`다. 남기는 것의 모양을 본다: 첫 줄이 `network={`, 마지막 줄이 `}`. 그 밖의
/// 모양이면 null — `wpa_passphrase`가 바뀐 것이고 그때는 쓰지 않는다.
pub fn networkBlock(out: []u8, output: []const u8) ?[]const u8 {
    var len: usize = 0;
    var first = true;
    var last: []const u8 = "";
    var it = std.mem.splitScalar(u8, output, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (first and !std.mem.eql(u8, t, "network={")) return null;
        first = false;
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (len + line.len + 1 > out.len) return null;
        @memcpy(out[len..][0..line.len], line);
        out[len + line.len] = '\n';
        len += line.len + 1;
        last = t;
    }
    if (first or !std.mem.eql(u8, last, "}")) return null;
    return out[0..len];
}

/// 덩어리의 `ssid=…` 줄(양 끝 공백을 뗀 글자). 같은 망의 옛 덩어리를 이 글자로 찾는다.
pub fn ssidLine(block: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, block, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, t, "ssid=")) return t;
    }
    return null;
}

pub const Placed = struct { text: []const u8, replaced: bool };

/// conf에서 `ssid` 줄이 같은 첫 `network={ … }` 덩어리를 block으로 바꾼다. 없으면 끝에 더한다.
///
/// 덩어리의 경계는 줄 둘이다 — 양 끝 공백을 뗀 글자가 `network={`인 줄과 그 뒤 처음 나오는
/// `}`인 줄. `wpa_passphrase`가 내는 모양이고 running-tars.md가 사람에게 시킨 모양이다. 그
/// 밖의 모양(한 줄에 쓴 덩어리 등)은 못 찾고, 그때는 더한다 — 지우는 쪽으로 틀리지 않는다.
pub fn placeNetwork(out: []u8, conf: []const u8, block: []const u8) ?Placed {
    const want = ssidLine(block) orelse return null;
    var start: usize = 0;
    var block_start: ?usize = null;
    var matched = false;
    while (start < conf.len) {
        const end = std.mem.indexOfScalarPos(u8, conf, start, '\n') orelse conf.len;
        const next = if (end < conf.len) end + 1 else end;
        const t = std.mem.trim(u8, conf[start..end], " \t\r");
        if (block_start == null) {
            if (std.mem.eql(u8, t, "network={")) {
                block_start = start;
                matched = false;
            }
        } else if (std.mem.eql(u8, t, "}")) {
            if (matched) {
                const text = std.fmt.bufPrint(out, "{s}{s}{s}", .{ conf[0..block_start.?], block, conf[next..] }) catch return null;
                return .{ .text = text, .replaced = true };
            }
            block_start = null;
        } else if (std.mem.eql(u8, t, want)) {
            matched = true;
        }
        start = next;
    }
    const sep: []const u8 = if (conf.len > 0 and conf[conf.len - 1] != '\n') "\n" else "";
    const text = std.fmt.bufPrint(out, "{s}{s}{s}", .{ conf, sep, block }) catch return null;
    return .{ .text = text, .replaced = false };
}

/// 나라 코드. 대문자 둘(`KR`)만 받는다 — 규제 도메인의 이름이 그 모양이다.
pub fn countryOk(cc: []const u8) bool {
    return cc.len == 2 and std.ascii.isUpper(cc[0]) and std.ascii.isUpper(cc[1]);
}

/// 맨 앞의 `country=` 줄을 바꾸거나, 없으면 맨 앞에 더한다. `network={` 안은 안 본다.
pub fn setCountry(out: []u8, conf: []const u8, cc: []const u8) ?[]const u8 {
    var start: usize = 0;
    var depth: usize = 0;
    while (start < conf.len) {
        const end = std.mem.indexOfScalarPos(u8, conf, start, '\n') orelse conf.len;
        const next = if (end < conf.len) end + 1 else end;
        const t = std.mem.trim(u8, conf[start..end], " \t\r");
        if (std.mem.eql(u8, t, "network={")) depth += 1;
        if (depth > 0 and std.mem.eql(u8, t, "}")) depth -= 1;
        if (depth == 0 and std.mem.startsWith(u8, t, "country=")) {
            return std.fmt.bufPrint(out, "{s}country={s}{s}", .{ conf[0..start], cc, conf[end..] }) catch null;
        }
        start = next;
    }
    return std.fmt.bufPrint(out, "country={s}\n{s}", .{ cc, conf }) catch null;
}

/// `wifi` 상태. 망의 이름만 보인다 — psk 줄은 안 찍는다.
pub fn wifiStatusLines(sink: anytype, conf: []const u8) void {
    var it = std.mem.splitScalar(u8, conf, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, t, "ssid=") or std.mem.startsWith(u8, t, "country=")) sink.print("{s}\n", .{t});
    }
}

/// `wifi SSID`가 쓴 뒤의 말 — 쓴 것 한 줄과 다음 걸음. 파일이 없던 자리면 wpa_supplicant가 아직 안
/// 떠 있으므로 restart가 아니라 reload다.
pub fn wifiDone(sink: anytype, ssid: []const u8, path: []const u8, replaced: bool, with_country: bool, net_off: bool, existed: bool) void {
    sink.print("wifi: {s} {s} in {s}{s}\n", .{
        ssid,
        if (replaced) "replaced" else "added",
        path,
        if (with_country) " (with country)" else "",
    });
    if (net_off) sink.print("net=off: wifi needs the network on — tars-config set net=dhcp\n", .{});
    if (existed) {
        sink.print("apply now: tars-service restart wpa_supplicant\n", .{});
    } else {
        sink.print("apply now: tars-config reload starts wpa_supplicant (or the next boot)\n", .{});
    }
}

// ── ssh ───────────────────────────────────────────────────────────────

/// 공개 키 한 줄의 몸통(base64). 키 줄은 `[옵션] 형식 몸통 [설명]`이고 몸통은 늘 `AAAA`로
/// 시작한다(길이 4바이트 + 형식 이름의 base64). 같은 키를 두 번 더하지 않는 데 쓴다.
pub fn keyBody(line: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    while (it.next()) |tok| if (std.mem.startsWith(u8, tok, "AAAA") and tok.len >= 16) return tok;
    return null;
}

/// authorized_keys의 줄 가운데 몸통이 같은 것이 있는가.
pub fn hasKey(keys: []const u8, body: []const u8) bool {
    var it = std.mem.splitScalar(u8, keys, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        if (keyBody(t)) |b| if (std.mem.eql(u8, b, body)) return true;
    }
    return false;
}

/// 빈 줄 · 주석을 뺀 줄의 수. authorized_keys의 키 수와 이 명령의 nft 파일의 규칙 수를 센다.
pub fn keyCount(keys: []const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, keys, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len != 0 and t[0] != '#') n += 1;
    }
    return n;
}

/// `ssh-key add`가 받은 글자에서 키 한 줄. 앞뒤 공백 · 개행을 뗀다. 비었거나 개행 · 제어 문자가
/// 남으면 null — 키 둘이 한 번에 들어가거나 파일의 한 줄이 둘이 되는 길이다.
pub fn keyLine(raw: []const u8) ?[]const u8 {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0 or std.mem.indexOfScalar(u8, line, '\n') != null or hasControl(line)) return null;
    return line;
}

/// `/config/services.d/sshd`가 무엇인가. 사람이 다른 sshd 스크립트를 그 이름으로 두었으면 `other`다.
pub const Sshd = enum { none, template, other };

/// `ssh` 상태의 `sshd:` 뒤.
pub fn sshdText(s: Sshd) []const u8 {
    return switch (s) {
        .template => "on (/config/services.d/sshd -> /etc/tars/services/sshd)",
        .other => "/config/services.d/sshd is yours, not the template",
        .none => "off",
    };
}

/// firewall=on일 때 22를 이 명령이 열었는지. nft_text는 이 명령의 파일이다. 사람의 nft 파일은 안
/// 읽는다(결정 10) — 열려 있을 수도 있다고만 말한다.
pub fn firewall22(sink: anytype, nft_text: []const u8, nft_dir: []const u8) void {
    if (hasLine(nft_text, "tcp dport 22 accept")) {
        sink.print("firewall=on: tars-config opened port 22\n", .{});
    } else {
        sink.print("firewall=on: port 22 is open only if a file in {s} says so; tars-config firewall allow 22\n", .{nft_dir});
    }
}

// ── 받아쓰기 ──────────────────────────────────────────────────────────

/// `/config/dictation.conf`의 키 여덟(VD design 결정 3). 그 파일의 파서는
/// `kernel/dictation/tars-dictate`(bash)이고 이 목록은 그 `case`의 이름과 같아야 한다 —
/// 이 명령은 이름만 알고 값은 거르지 않는다(결정 15). 이름이 어긋나면 `set`이 쓴 줄을
/// tars-dictate가 "unknown key"로 버린다. `config_front_edit_test`가 그 파일에서 이름을
/// 읽어 이 목록과 견준다.
pub const DICTATION_KEYS = [_][]const u8{
    "transcribe_url", "transcribe_model", "language",      "max_seconds",
    "cleanup",        "cleanup_url",      "cleanup_model", "cleanup_timeout",
};

pub fn isDictationKey(key: []const u8) bool {
    for (DICTATION_KEYS) |k| if (std.mem.eql(u8, k, key)) return true;
    return false;
}

/// API 키 한 줄. 앞뒤 공백 · 개행을 뗀다. 비었거나 그 안에 공백 · 제어 문자가 있으면 null —
/// 그 글자는 키가 아니고, 개행 하나면 파일이 두 줄이 된다. 글자의 종류를 더 좁히는 것은
/// tars-dictate의 몫이다(결정 15).
pub fn apiKey(text: []const u8) ?[]const u8 {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len == 0) return null;
    for (t) |b| if (b <= 0x20 or b == 0x7f) return null;
    return t;
}

/// `KEY=VALUE`의 값에 제어 문자가 있는가(개행 하나면 줄이 둘이 된다).
pub fn hasControl(text: []const u8) bool {
    for (text) |b| if (b < 0x20 or b == 0x7f) return true;
    return false;
}

/// `dictation set`의 쌍을 text에 차례로 적고, 쌍마다 한 줄을 찍는다. 같은 문법(`#` 주석 · 첫 `=` ·
/// 양쪽 공백)이라 tars.conf의 줄 바꾸기를 그대로 쓴다. work 둘을 번갈아 쓴다.
///
/// args는 `dictationArgs`가 `.set`으로 준 것이다(쌍마다 `=`가 있다). 넘치면 null이고, 그 앞의 쌍은
/// 이미 찍혔다.
pub fn dictationApply(sink: anytype, work: [2][]u8, text: []const u8, args: edit.Rest) ?[]const u8 {
    var cur = text;
    for (args, 0..) |a, i| {
        const arg = std.mem.span(a);
        const eq = std.mem.indexOfScalar(u8, arg, '=').?;
        const key = std.mem.trim(u8, arg[0..eq], " \t");
        const value = std.mem.trim(u8, arg[eq + 1 ..], " \t");
        cur = edit.setLine(work[i % 2], cur, key, value) orelse return null;
        sink.print("dictation: {s}={s}\n", .{ key, value });
    }
    return cur;
}

/// `check`의 받아쓰기 줄 — tars-dictate가 모르는 키의 줄마다 한 줄. 빈 줄 · 주석 · `=` 없는 줄은
/// 건너뛴다. 돌려주는 것은 문제의 수다.
pub fn dictationUnknown(sink: anytype, text: []const u8, path: []const u8) usize {
    var problems: usize = 0;
    var it = std.mem.splitScalar(u8, text, '\n');
    var number: usize = 0;
    while (it.next()) |raw| {
        number += 1;
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = std.mem.trim(u8, t[0..eq], " \t");
        if (!isDictationKey(key)) {
            sink.print("{s} line {d}: tars-dictate does not know the key '{s}'\n", .{ path, number, key });
            problems += 1;
        }
    }
    return problems;
}

// ── 인자 ──────────────────────────────────────────────────────────────
//
// 동사 뒤의 argv를 가른다. 거절도 칸이다 — 그 문장은 `config_front`가 찍는다. 칸을 거절마다 따로 두는
// 것은 시스템 콜 쪽이 `needDisk`와의 순서를 지금 그대로 지키게 하려는 것이다(HC-M1 plan 확정 2).

pub const WifiArgs = union(enum) {
    status,
    add: struct { ssid: []const u8, country: ?[]const u8 },
    usage,
    /// `--country` 뒤가 대문자 둘이 아니다.
    bad_country,
    /// SSID가 0바이트 · 32바이트 넘음 · 제어 문자.
    bad_ssid,
};

/// `wifi SSID [--country CC]` (결정 12). 나라를 SSID보다 먼저 본다.
pub fn wifiArgs(args: edit.Rest) WifiArgs {
    if (args.len == 0) return .status;
    const ssid = std.mem.span(args[0]);
    var country: ?[]const u8 = null;
    if (args.len == 3 and std.mem.eql(u8, std.mem.span(args[1]), "--country")) {
        country = std.mem.span(args[2]);
        if (!countryOk(country.?)) return .bad_country;
    } else if (args.len != 1) return .usage;
    if (ssid.len == 0 or ssid.len > 32 or hasControl(ssid)) return .bad_ssid;
    return .{ .add = .{ .ssid = ssid, .country = country } };
}

/// `bad_verb`는 `usage`와 같은 문장이지만 디스크를 본 뒤에 찍는다 — `ssh foo`는 디스크가 없으면
/// "no config disk"다.
pub const SshArgs = union(enum) { status, on, off, usage, bad_verb };

/// `ssh [on|off]` (결정 13).
pub fn sshArgs(args: edit.Rest) SshArgs {
    if (args.len > 1) return .usage;
    if (args.len == 0) return .status;
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "on")) return .on;
    if (std.mem.eql(u8, verb, "off")) return .off;
    return .bad_verb;
}

/// `add`의 null은 표준 입력(`< id_ed25519.pub`)이다.
pub const SshKeyArgs = union(enum) { list, add: ?[]const u8, usage };

/// `ssh-key add [KEY] | list` (결정 13).
pub fn sshKeyArgs(args: edit.Rest) SshKeyArgs {
    if (args.len == 0) return .usage;
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "list")) return if (args.len == 1) .list else .usage;
    if (!std.mem.eql(u8, verb, "add") or args.len > 2) return .usage;
    return .{ .add = if (args.len == 2) std.mem.span(args[1]) else null };
}

pub const FirewallArgs = union(enum) {
    status,
    change: struct { allow: bool, spec: PortSpec },
    usage,
    bad_port,
};

/// `firewall [allow|deny PORT[/udp]]` (결정 14). 동사를 포트보다 먼저 본다.
pub fn firewallArgs(args: edit.Rest) FirewallArgs {
    if (args.len == 0) return .status;
    if (args.len != 2) return .usage;
    const verb = std.mem.span(args[0]);
    const allow = std.mem.eql(u8, verb, "allow");
    if (!allow and !std.mem.eql(u8, verb, "deny")) return .usage;
    const spec = parsePort(std.mem.span(args[1])) orelse return .bad_port;
    return .{ .change = .{ .allow = allow, .spec = spec } };
}

pub const DictationArgs = union(enum) {
    status,
    /// null은 표준 입력이다.
    key: ?[]const u8,
    /// 쌍 검사를 지난 인자. `dictationApply`에 그대로 준다.
    set: edit.Rest,
    usage,
    /// 그 인자.
    no_equals: []const u8,
    /// 그 키.
    unknown_key: []const u8,
    /// 그 키.
    control_byte: []const u8,
};

/// `dictation [key [KEY] | set KEY=VALUE…]` (결정 15). 쌍은 앞에서부터 보고 처음 걸린 것에서 멈춘다.
/// 한 쌍 안에서는 `=` → 이름 → 제어 문자 순이다. 이름만 거른다 — 값은 tars-dictate가 실행마다 읽고
/// 틀리면 경고한다.
pub fn dictationArgs(args: edit.Rest) DictationArgs {
    if (args.len == 0) return .status;
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "key")) {
        if (args.len > 2) return .usage;
        return .{ .key = if (args.len == 2) std.mem.span(args[1]) else null };
    }
    if (!std.mem.eql(u8, verb, "set") or args.len < 2) return .usage;
    for (args[1..]) |a| {
        const arg = std.mem.span(a);
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse return .{ .no_equals = arg };
        const key = std.mem.trim(u8, arg[0..eq], " \t");
        if (!isDictationKey(key)) return .{ .unknown_key = key };
        if (hasControl(arg)) return .{ .control_byte = key };
    }
    return .{ .set = args[1..] };
}
