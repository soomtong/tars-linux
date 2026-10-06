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
const std = @import("std");

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

// ── 받아쓰기 ──────────────────────────────────────────────────────────

/// `/config/dictation.conf`의 키 여덟(VD design 결정 3). 그 파일의 파서는
/// `kernel/dictation/tars-dictate`(bash)이고 이 목록은 그 `case`의 이름과 같아야 한다 —
/// 이 명령은 이름만 알고 값은 거르지 않는다(결정 15). 이름이 어긋나면 `set`이 쓴 줄을
/// tars-dictate가 "unknown key"로 버린다. `config_front_edit_test`가 그 파일에서 이름을
/// 읽어 이 목록과 견준다.
pub const DICTATION_KEYS = [_][]const u8{
    "transcribe_url", "transcribe_model", "language",        "max_seconds",
    "cleanup",        "cleanup_url",      "cleanup_model",   "cleanup_timeout",
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
