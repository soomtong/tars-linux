//! TC-M0. `tars-config`의 순수한 쪽(TC design 결정 4).
//!
//! 시스템 콜이 하나도 없다 — `config_edit_test.zig`가 호스트에서 전부 본다. 파일을
//! 열고 쓰는 것과 마운트 표 · zoneinfo · rc 파일을 읽는 것은 `config_cli.zig`다.
//! `service_cli.zig`(시스템 콜)와 `control.zig`(글자)를 가른 선과 같다.
//!
//! 값이 맞는지는 여기서 정하지 않는다. `config.parse`에 한 줄을 주고 그 함수가
//! 무슨 말을 하는지 듣는다(`judge`). init이 부팅에 쓰는 바로 그 함수라서, 이
//! 명령이 받은 값을 init이 거절하는 일이 구조로 없다(결정 3).
const std = @import("std");
const config = @import("config.zig");

/// 값 하나의 글자를 담는 버퍼의 크기. 가장 긴 값이 `timezone`(64)이다.
pub const VALUE_MAX = 64;

comptime {
    if (VALUE_MAX < config.TZ_NAME_MAX or VALUE_MAX < config.TOGGLE_ARG_MAX or
        VALUE_MAX < config.NTP_ARG_MAX)
        @compileError("VALUE_MAX is smaller than a value config.zig can hold");
}

/// `key=value` 한 줄을 지을 버퍼의 크기. 키는 가장 긴 것이 `hangul_layout`
/// 열세 글자이고, 사람이 준 값은 `judge`가 이 안에 들어갈 때만 받는다.
pub const LINE_MAX = 256;

// ── 키 ────────────────────────────────────────────────────────────────

/// 키 이름. `Config`의 필드 이름이 곧 키다 — `parse`가 그 이름으로 가른다.
///
/// 둘이 같다는 것은 컴파일러가 아니라 `config_edit_test`가 본다. 모든 필드
/// 이름을 기본값과 함께 `parse`에 넣어 "모르는 키"가 하나도 안 나오는지를 잰다.
/// 필드를 하나 더하고 `parse`의 갈래를 빠뜨리면 거기서 멈춘다.
pub const KEYS = blk: {
    const info = @typeInfo(config.Config).@"struct";
    var names: [info.field_names.len][]const u8 = undefined;
    for (info.field_names, 0..) |f_name, i| names[i] = f_name;
    const out = names;
    break :blk out;
};

pub fn isKey(key: []const u8) bool {
    for (KEYS) |k| if (std.mem.eql(u8, k, key)) return true;
    return false;
}

/// 그 키의 값을 설정 파일에 적는 글자로. 모르는 키면 null.
///
/// 필드의 타입마다 글자로 바꾸는 법이 config.zig에 이미 있다(`@tagName` ·
/// `Toggles.arg` · `Ntp.arg` · `Timezone.slice`). 여기는 그것을 고르기만 한다.
/// 모르는 타입의 필드가 생기면 `fieldText`가 컴파일 에러를 낸다 — 새 키를
/// 더한 사람이 이 명령을 잊을 수가 없다.
pub fn valueText(c: *const config.Config, key: []const u8, buf: *[VALUE_MAX]u8) ?[]const u8 {
    inline for (@typeInfo(config.Config).@"struct".field_names, @typeInfo(config.Config).@"struct".field_types) |f_name, f_type| {
        if (std.mem.eql(u8, key, f_name)) return fieldText(f_type, @field(c, f_name), buf);
    }
    return null;
}

fn fieldText(comptime T: type, v: T, buf: *[VALUE_MAX]u8) []const u8 {
    if (T == config.Toggles) return v.arg(buf);
    if (T == config.Ntp) return v.arg(buf);
    if (T == config.Timezone) {
        const s = v.slice();
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    }
    if (@typeInfo(T) == .@"enum") return @tagName(v);
    @compileError("tars-config cannot print a " ++ @typeName(T) ++ "; teach config_edit.fieldText");
}

/// 그 키에 적을 수 있는 것. `help`와 거절의 둘째 줄이 쓴다. 모르는 키면 null.
///
/// enum은 이름을 컴파일 타임에 모으므로 config.zig에 이름을 하나 더하면 여기도
/// 따라온다. enum이 아닌 셋만 글로 적는다.
pub fn hint(key: []const u8) ?[]const u8 {
    inline for (@typeInfo(config.Config).@"struct".field_names, @typeInfo(config.Config).@"struct".field_types) |f_name, f_type| {
        if (std.mem.eql(u8, key, f_name)) return comptime hintFor(f_type);
    }
    return null;
}

fn hintFor(comptime T: type) []const u8 {
    if (T == config.Toggles)
        return "a comma list of " ++ join(config.ToggleKey, ", ") ++ "; empty turns them all off";
    if (T == config.Ntp) return "off | dhcp | <IPv4 address>";
    if (T == config.Timezone) return "UTC | <a name under /usr/share/zoneinfo, e.g. Asia/Seoul>";
    if (@typeInfo(T) == .@"enum") return join(T, " | ");
    @compileError("tars-config has no hint for a " ++ @typeName(T) ++ "; teach config_edit.hintFor");
}

fn join(comptime E: type, comptime sep: []const u8) []const u8 {
    comptime {
        var s: []const u8 = "";
        for (@typeInfo(E).@"enum".field_names, 0..) |f_name, i| s = s ++ (if (i == 0) "" else sep) ++ f_name;
        return s;
    }
}

// ── 줄 ────────────────────────────────────────────────────────────────

pub const Pair = struct { key: []const u8, value: []const u8 };

/// 한 줄의 종류. `config.parse`와 같은 규칙으로 가른다 — 양 끝의 " \t\r"를
/// 떼고, 비었거나 `#`로 시작하면 건너뛰고, 첫 `=`에서 나눠 양쪽의 " \t"를 뗀다.
/// 규칙이 두 벌인 것은 `parse`가 줄의 자리(바이트 위치)를 돌려주지 않기
/// 때문이다. 두 벌이 같은지는 `config_edit_test`가 같은 줄을 둘에 넣어 본다.
pub const Line = union(enum) {
    skip,
    no_equals,
    pair: Pair,
};

pub fn classify(raw: []const u8) Line {
    const line = std.mem.trim(u8, raw, " \t\r");
    if (line.len == 0 or line[0] == '#') return .skip;
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return .no_equals;
    return .{ .pair = .{
        .key = std.mem.trim(u8, line[0..eq], " \t"),
        .value = std.mem.trim(u8, line[eq + 1 ..], " \t"),
    } };
}

/// 파일의 줄 하나. `end`는 `\n` 앞이고 `number`는 1부터 센다.
pub const Span = struct { start: usize, end: usize, number: usize };

/// 줄을 하나씩 돌려준다. 끝에 개행이 없는 마지막 줄도 줄이다.
pub const Lines = struct {
    text: []const u8,
    pos: usize = 0,
    number: usize = 0,
    done: bool = false,

    pub fn next(self: *Lines) ?Span {
        if (self.done) return null;
        const end = std.mem.indexOfScalarPos(u8, self.text, self.pos, '\n') orelse blk: {
            self.done = true;
            if (self.pos == self.text.len) return null;
            break :blk self.text.len;
        };
        self.number += 1;
        const span = Span{ .start = self.pos, .end = end, .number = self.number };
        self.pos = end + 1;
        return span;
    }
};

/// key를 적은 마지막 줄. `parse`에서 이기는 줄이 이것이다("마지막 줄이 이긴다").
pub fn lastLine(text: []const u8, key: []const u8) ?Span {
    var found: ?Span = null;
    var it = Lines{ .text = text };
    while (it.next()) |span| switch (classify(text[span.start..span.end])) {
        .pair => |p| if (std.mem.eql(u8, p.key, key)) {
            found = span;
        },
        else => {},
    };
    return found;
}

/// key를 적은 줄의 번호들. `check`가 같은 키가 두 번 이상 적힌 자리를 알린다.
/// out보다 많으면 out만큼만 담고 전체 수를 돌려준다.
pub fn lineNumbers(text: []const u8, key: []const u8, out: []usize) usize {
    var n: usize = 0;
    var it = Lines{ .text = text };
    while (it.next()) |span| switch (classify(text[span.start..span.end])) {
        .pair => |p| if (std.mem.eql(u8, p.key, key)) {
            if (n < out.len) out[n] = span.number;
            n += 1;
        },
        else => {},
    };
    return n;
}

/// text에서 key의 줄 하나만 `key=value`로 바꾼 글자를 out에 짓는다(결정 5).
///
/// 바꾸는 것은 이기는 줄(마지막 줄) 하나다. 그 줄의 앞뒤 — 사람이 적은 주석,
/// 모르는 키, 같은 키의 앞선 줄 — 는 바이트 하나 안 건드린다. 그 키의 줄이
/// 없으면 끝에 더한다. 끝에 개행이 없던 파일이면 개행을 먼저 넣는다.
///
/// 넘치면 null이다. 호출자는 그 결과가 `config.MAX_FILE`을 넘는지도 본다.
pub fn setLine(out: []u8, text: []const u8, key: []const u8, value: []const u8) ?[]const u8 {
    if (lastLine(text, key)) |s| {
        return std.fmt.bufPrint(out, "{s}{s}={s}{s}", .{
            text[0..s.start], key, value, text[s.end..],
        }) catch null;
    }
    const sep: []const u8 = if (text.len > 0 and text[text.len - 1] != '\n') "\n" else "";
    return std.fmt.bufPrint(out, "{s}{s}{s}={s}\n", .{ text, sep, key, value }) catch null;
}

// ── 듣기 ──────────────────────────────────────────────────────────────

/// `config.parse`가 한 말. 첫 줄만 담고 수를 센다.
pub const Heard = struct {
    count: usize = 0,
    len: usize = 0,
    buf: [LINE_MAX + 64]u8 = undefined,

    pub fn first(self: *const Heard) []const u8 {
        return self.buf[0..self.len];
    }
};

/// 이 명령은 스레드가 하나라 전역 하나로 된다. 듣기 전에 `.{}`로 비운다.
pub var heard: Heard = .{};

/// config.zig의 `log`가 root에서 찾는 이름. root(`config_cli.zig` ·
/// `config_edit_test.zig`)가 `pub const configLog = config_edit.configLog;`로 건다.
pub fn configLog(comptime fmt: []const u8, args: anytype) void {
    heard.count += 1;
    if (heard.count > 1) return;
    var w: std.Io.Writer = .fixed(&heard.buf);
    w.print(fmt, args) catch {};
    heard.len = w.end;
}

/// 사람이 준 `key=value` 하나에 대한 답.
pub const Verdict = union(enum) {
    /// init이 아무 말 없이 받는다. 그 한 줄만 읽은 `Config`다 — 이 키의 값을
    /// 정규형으로 되돌릴 때(`valueText`) 쓴다.
    ok: config.Config,
    unknown_key,
    /// 제어 문자. 개행 하나면 한 번의 `set`이 줄을 둘 쓴다.
    control_byte,
    too_long,
    /// init이 부팅에 이 말을 하고 그 값을 버린다. 글자는 `heard`를 가리키므로
    /// 다음 `judge` 전에 쓴다.
    refused: []const u8,
};

/// key=value를 init의 파서에 한 줄로 넣어 본다(결정 3).
///
/// 판정은 "parse가 말을 했는가" 하나다. 키마다 값을 따로 검사하는 표를 여기
/// 두지 않는다 — 그런 표는 config.zig와 두 벌이 되고, 둘이 갈라지는 날 이
/// 명령은 init이 버릴 값을 써 준다.
pub fn judge(line_buf: *[LINE_MAX]u8, key: []const u8, value: []const u8) Verdict {
    for (key) |b| if (b < 0x20 or b == 0x7f) return .control_byte;
    for (value) |b| if (b < 0x20 or b == 0x7f) return .control_byte;
    if (!isKey(key)) return .unknown_key;
    const line = std.fmt.bufPrint(line_buf, "{s}={s}", .{ key, value }) catch return .too_long;
    heard = .{};
    const c = config.parse(line);
    if (heard.count != 0) return .{ .refused = heard.first() };
    return .{ .ok = c };
}

/// 그 키를 파일의 어느 줄이 정하는가. 정하는 줄이 없으면(줄이 없거나 있는
/// 줄을 init이 전부 버리면) 기본값이고 `show`가 그 줄 앞에 `#`를 붙인다.
///
/// `lastLine`만 보면 틀린다. 마지막 줄의 값이 틀리면 `parse`는 그 줄을 버리고
/// 앞 줄의 값에 머문다 — 줄마다 `judge`로 듣는다.
pub fn setByFile(line_buf: *[LINE_MAX]u8, text: []const u8, key: []const u8) bool {
    var it = Lines{ .text = text };
    while (it.next()) |span| switch (classify(text[span.start..span.end])) {
        .pair => |p| if (std.mem.eql(u8, p.key, key)) {
            if (judge(line_buf, p.key, p.value) == .ok) return true;
        },
        else => {},
    };
    return false;
}

// ── 파일 밖의 글자 ────────────────────────────────────────────────────

/// `/proc/mounts`에서 mountpoint에 붙은 것의 원천(`/dev/vda`). 없으면 null.
/// 같은 자리에 여럿이 붙었으면 마지막 것이 보이는 것이다.
pub fn mountSource(mounts: []const u8, mountpoint: []const u8) ?[]const u8 {
    var found: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, mounts, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        const source = fields.next() orelse continue;
        const target = fields.next() orelse continue;
        if (std.mem.eql(u8, target, mountpoint)) found = source;
    }
    return found;
}

/// 옛 seed가 rc에 남긴 `alias tars-config=…`의 줄 번호(결정 6). 없으면 null.
///
/// 그 별칭은 대화형 셸에서 `/usr/bin/tars-config`를 가린다 — 친 것이 이 명령이
/// 아니라 `cat /config/tars.conf`가 된다. seed는 "없으면 만든다"라서 TC 전에
/// 만든 디스크의 rc에는 그 줄이 그대로 있다. 이 명령은 그 줄을 지우지 않는다.
/// rc는 사람의 파일이다(SC design 결정 7). 알리기만 한다.
pub fn staleAlias(rc: []const u8) ?usize {
    const name = "alias tars-config";
    var it = Lines{ .text = rc };
    while (it.next()) |span| {
        const line = std.mem.trim(u8, rc[span.start..span.end], " \t\r");
        if (!std.mem.startsWith(u8, line, name)) continue;
        if (line.len == name.len) continue;
        switch (line[name.len]) {
            '=', ' ', '\t' => return span.number,
            else => {},
        }
    }
    return null;
}

// ── 명령 ──────────────────────────────────────────────────────────────

/// 한 번의 `set` · `reset`이 받는 쌍의 상한.
pub const PAIRS_MAX = 16;

/// 동사 뒤의 인자. argv를 가리킨다 — argv는 프로세스 수명이다.
pub const Rest = []const [*:0]const u8;

/// `tars-config`의 동사 하나(HC design 결정 4). 거절도 칸이다 — 그 문장은 `config_cli`의 `main`이 찍는다.
pub const Command = union(enum) {
    show,
    help,
    /// BV-M0. 글자는 빌드가 박은 것이다 — VERSION과 git의 답(BV design 결정 2 · 7).
    version,
    list,
    /// "언세팅"은 reset이다. unset이라는 이름은 받지 않는다 — 그 낱말은 "줄을 지운다"로
    /// 읽히는데 reset은 줄을 지우지 않고 기본값을 적는다(design 결정 1의 덧붙임).
    /// 친 사람이 길을 잃지 않게 그 차이를 말하고 쓰는 법으로 끝낸다.
    unset,
    /// `reload` · `reload terminal`. true가 terminal.
    reload: bool,
    check,
    /// 앞문 다섯(TC-M1). 인자는 각자 가른다.
    wifi: Rest,
    ssh: Rest,
    ssh_key: Rest,
    firewall: Rest,
    dictation: Rest,
    /// 공백을 벗긴 키. 아는 키인지는 `get`이 `isKey`로 본다.
    get: []const u8,
    /// `set K=V…` · `reset K…`가 같은 칸이다 — `change`는 쌍만 받는다.
    change: []const Pair,
    usage,
    /// `set`의 인자에 `=`가 없다. 그 인자다.
    no_equals: []const u8,
    /// `reset`의 모르는 키.
    unknown_key: []const u8,
};

/// argv[1..]을 가른다. `set`의 쌍은 pairs에, `reset`의 기본값 글자는 default_bufs에 짓는다 — 둘 다 호출자의 스택이다.
///
/// 하나라도 거절이면 그 자리에서 멈춘다. 앞의 쌍은 pairs에 남지만 아무도 안 읽는다.
pub fn parseCommand(args: Rest, pairs: *[PAIRS_MAX]Pair, default_bufs: *[PAIRS_MAX][VALUE_MAX]u8) Command {
    if (args.len == 0) return .show;
    const verb = std.mem.span(args[0]);
    const rest = args[1..];

    if (std.mem.eql(u8, verb, "help") or std.mem.eql(u8, verb, "-h") or std.mem.eql(u8, verb, "--help"))
        return if (rest.len == 0) .help else .usage;
    if (std.mem.eql(u8, verb, "version") or std.mem.eql(u8, verb, "--version") or std.mem.eql(u8, verb, "-V"))
        return if (rest.len == 0) .version else .usage;
    if (std.mem.eql(u8, verb, "list")) return if (rest.len == 0) .list else .usage;
    if (std.mem.eql(u8, verb, "unset")) return .unset;
    if (std.mem.eql(u8, verb, "reload")) {
        if (rest.len == 0) return .{ .reload = false };
        if (rest.len == 1 and std.mem.eql(u8, std.mem.span(rest[0]), "terminal")) return .{ .reload = true };
        return .usage;
    }
    if (std.mem.eql(u8, verb, "check")) return if (rest.len == 0) .check else .usage;
    if (std.mem.eql(u8, verb, "wifi")) return .{ .wifi = rest };
    if (std.mem.eql(u8, verb, "ssh")) return .{ .ssh = rest };
    if (std.mem.eql(u8, verb, "ssh-key")) return .{ .ssh_key = rest };
    if (std.mem.eql(u8, verb, "firewall")) return .{ .firewall = rest };
    if (std.mem.eql(u8, verb, "dictation")) return .{ .dictation = rest };
    if (std.mem.eql(u8, verb, "get")) {
        if (rest.len != 1) return .usage;
        return .{ .get = std.mem.trim(u8, std.mem.span(rest[0]), " \t") };
    }
    const is_set = std.mem.eql(u8, verb, "set");
    if (!is_set and !std.mem.eql(u8, verb, "reset")) return .usage;
    if (rest.len == 0 or rest.len > PAIRS_MAX) return .usage;

    const defaults = config.Config{};
    for (rest, 0..) |arg_z, i| {
        const arg = std.mem.span(arg_z);
        if (is_set) {
            // 설정 파일의 한 줄과 같은 규칙으로 가른다 — 첫 `=`, 양쪽 공백.
            const eq = std.mem.indexOfScalar(u8, arg, '=') orelse return .{ .no_equals = arg };
            pairs[i] = .{
                .key = std.mem.trim(u8, arg[0..eq], " \t"),
                .value = std.mem.trim(u8, arg[eq + 1 ..], " \t"),
            };
        } else {
            const key = std.mem.trim(u8, arg, " \t");
            const value = valueText(&defaults, key, &default_bufs[i]) orelse return .{ .unknown_key = key };
            pairs[i] = .{ .key = key, .value = value };
        }
    }
    return .{ .change = pairs[0..rest.len] };
}

// ── init의 답(TC-M2) ──────────────────────────────────────────────────
//
// 답을 짓는 쪽은 `reload.configReply`다. 이 파일은 reload.zig를 import하지 않는다(그것은 PID 1의
// 것이다) — 두 벌이 맞는지는 `config_edit_test`가 지은 답을 그대로 넣어 본다(HC design 결정 7).

/// `config`의 답에서 그 키의 값.
pub fn nowValue(reply: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, reply, '\n');
    while (it.next()) |line| {
        if (line.len > key.len and std.mem.startsWith(u8, line, key) and line[key.len] == '=') return line[key.len + 1 ..];
    }
    return null;
}

/// `config`의 답의 `screen …` 줄(화면이 대기 중인 키)의 꼬리. 없으면 null.
pub fn screenLine(reply: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, reply, '\n');
    while (it.next()) |line| if (std.mem.startsWith(u8, line, "screen ")) return line["screen".len..];
    return null;
}

// ── 문장 ──────────────────────────────────────────────────────────────
//
// 여러 줄을 찍는 함수는 `sink`를 받는다 — `print(fmt, args)`가 있는 것이면 된다. `config_cli`는 줄마다
// `write` 한 번인 `Say`를, 검사는 `control.Out`을 준다. 버퍼 하나에 모으지 않는 것은 `checkLines`의
// 출력이 파일의 줄 수에 비례하기 때문이다(HC-M0 plan 확정 3).

/// `set` · `reset`이 키마다 찍는 결과 한 줄. 키는 `judge`가 받은 것(13자 이하)이고 값 둘은
/// `VALUE_MAX` 안이라 `LINE_MAX`를 넘지 않는다.
pub fn changeLine(buf: *[LINE_MAX]u8, key: []const u8, old: []const u8, old_default: bool, new: []const u8) []const u8 {
    if (std.mem.eql(u8, old, new)) return std.fmt.bufPrint(buf, "{s}: {s} (unchanged)\n", .{ key, new }) catch unreachable;
    return std.fmt.bufPrint(buf, "{s}: {s}{s} -> {s}\n", .{ key, old, if (old_default) " (default)" else "", new }) catch unreachable;
}

/// 열두 키를 `key=기본값`과 받는 값으로 한 줄씩. `help`와 `list`가 함께 쓴다. 왼쪽 칸은
/// 그대로 `set`에 줄 수 있는 모양이고(`reset`이 적는 값이 그것이다), 오른쪽은
/// `hint` — enum이면 config.zig의 이름에서 컴파일 타임에 나온다.
pub fn keyTable(sink: anytype) void {
    const defaults = config.Config{};
    for (KEYS) |key| {
        var vbuf: [VALUE_MAX]u8 = undefined;
        var pair_buf: [LINE_MAX]u8 = undefined;
        const pair = std.fmt.bufPrint(&pair_buf, "{s}={s}", .{ key, valueText(&defaults, key, &vbuf).? }) catch key;
        sink.print("  {s:<26} {s}\n", .{ pair, hint(key).? });
    }
}

/// `show`의 키 줄 열둘. 파일이 정하지 않는 키는 `#`로 시작한다. text는 파일 전체이고 init처럼 앞의
/// `MAX_FILE` 바이트만 본다. c는 그것을 `parse`한 것, now는 init의 `config` 답(못 받았으면 null).
///
/// TC-M2. init이 지금 쓰는 값(reload design 결정 1). 파일과 다른 키는 그 줄 밑에 주석 한 줄로
/// 적는다 — 같은 줄 끝에 적으면 이 출력이 더는 그대로 쓸 수 있는 tars.conf가 아니다(TC 결정 8).
pub fn showKeyLines(sink: anytype, text: []const u8, c: *const config.Config, now: ?[]const u8) void {
    var line_buf: [LINE_MAX]u8 = undefined;
    for (KEYS) |key| {
        var vbuf: [VALUE_MAX]u8 = undefined;
        const value = valueText(c, key, &vbuf).?;
        const mark = if (setByFile(&line_buf, text[0..@min(text.len, config.MAX_FILE)], key)) "" else "#";
        sink.print("{s}{s}={s}\n", .{ mark, key, value });
        if (now) |r| if (nowValue(r, key)) |v| if (!std.mem.eql(u8, v, value))
            sink.print("#   init uses {s}={s} now; tars-config reload applies the line above\n", .{ key, v });
    }
}

/// `check`의 글자만 보는 둘 — init이 말하는 줄과 같은 키가 여러 줄인 자리. 돌려주는 것은 문제의 수다.
/// `heard`를 줄마다 비우고 쓴다(`judge`와 같다).
pub fn checkLines(sink: anytype, text: []const u8) usize {
    var problems: usize = 0;

    // 줄마다 init의 파서에 따로 넣는다. 줄 사이에 상태가 없는 파서라(마지막 줄이
    // 이긴다는 것뿐이다) 한 줄씩 들어도 init이 파일째로 읽을 때와 같은 말을 한다.
    var it = Lines{ .text = text };
    while (it.next()) |span| {
        if (span.start >= config.MAX_FILE) break;
        const raw = text[span.start..span.end];
        if (classify(raw) == .skip) continue;
        heard = .{};
        _ = config.parse(raw);
        if (heard.count == 0) continue;
        sink.print("line {d}: {s}\n", .{ span.number, heard.first() });
        problems += 1;
    }

    // 같은 키가 둘 이상이면 알린다. 틀린 것은 아니다 — 마지막 줄이 이긴다.
    for (KEYS) |key| {
        var numbers: [8]usize = undefined;
        const n = lineNumbers(text, key, &numbers);
        if (n < 2) continue;
        sink.print("{s} is on {d} lines (", .{ key, n });
        for (numbers[0..@min(n, numbers.len)], 0..) |num, i| sink.print("{s}{d}", .{ if (i == 0) "" else ", ", num });
        sink.print("); the last one wins\n", .{});
    }
    return problems;
}
