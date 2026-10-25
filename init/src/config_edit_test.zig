//! TC-M0. `config_edit.zig`의 검사. config_test와 같은 모양이다 — 호스트 아키텍처의
//! 실행 파일이고, 실패하면 `FAIL:` 줄을 찍고 0이 아닌 코드로 끝난다.
//!
//! 이 파일이 root라서 아래 `configLog`가 config.zig의 로그를 가로챈다. `judge`가
//! 듣는 것이 그 길이고, 그래서 여기서는 `tars-init:` 줄이 하나도 안 찍힌다.
const std = @import("std");
const scratch = @import("test_scratch.zig");
const linux = std.os.linux;
const config = @import("config.zig");
const edit = @import("config_edit.zig");
// HC-M0. init의 `config` 답을 짓는 쪽 — 읽는 쪽(`nowValue` · `screenLine`)과 왕복으로 본다. config_edit.zig는
// reload.zig를 import하지 않는다. 둘을 함께 아는 것은 이 검사뿐이다(HC design 결정 7).
const control = @import("control.zig");
const reload = @import("reload.zig");

pub const configLog = edit.configLog;

/// `config.save`가 seed를 쓰는 자리. 게스트가 아니라 빌드 컨테이너의 /tmp 아래, 프로세스마다 따로인 자리다(test_scratch.zig).
const SEED_PATH: [:0]const u8 = "tars-config-edit-test.conf";

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

/// 기본값이 아닌 값 하나씩. 키를 하나 더하면 이 표가 먼저 멈춘다 — 모든 키를
/// 진짜 seed에 써 보는 검사(아래 4)가 그 키를 빠뜨리지 않게 하는 자리다.
const OTHER = [_]edit.Pair{
    .{ .key = "shell", .value = "zsh" },
    .{ .key = "keyboard", .value = "pc" },
    .{ .key = "hangul_layout", .value = "dubeol" },
    .{ .key = "latin_layout", .value = "dvorak" },
    .{ .key = "hangul_toggle", .value = "shift_space" },
    .{ .key = "shell_config", .value = "off" },
    .{ .key = "net", .value = "dhcp" },
    .{ .key = "ntp", .value = "10.0.2.2" },
    .{ .key = "timezone", .value = "Asia/Seoul" },
    .{ .key = "firewall", .value = "on" },
    .{ .key = "esc_latin", .value = "off" },
    .{ .key = "clipboard", .value = "pane" },
};

fn other(key: []const u8) ?[]const u8 {
    for (OTHER) |p| if (std.mem.eql(u8, p.key, key)) return p.value;
    return null;
}

fn valueOf(c: *const config.Config, key: []const u8, buf: *[edit.VALUE_MAX]u8) []const u8 {
    return edit.valueText(c, key, buf).?;
}

fn expectOk(key: []const u8, value: []const u8, want_canon: []const u8) !void {
    var line: [edit.LINE_MAX]u8 = undefined;
    switch (edit.judge(&line, key, value)) {
        .ok => |c| {
            var buf: [edit.VALUE_MAX]u8 = undefined;
            const got = valueOf(&c, key, &buf);
            if (!std.mem.eql(u8, got, want_canon))
                return fail("judge {s}=\"{s}\" wrote \"{s}\", want \"{s}\"", .{ key, value, got, want_canon });
        },
        else => |v| return fail("judge {s}=\"{s}\" gave {s}, want ok", .{ key, value, @tagName(v) }),
    }
}

fn expectRefused(key: []const u8, value: []const u8, want_said: []const u8) !void {
    var line: [edit.LINE_MAX]u8 = undefined;
    switch (edit.judge(&line, key, value)) {
        .refused => |said| if (!std.mem.eql(u8, said, want_said))
            return fail("judge {s}=\"{s}\" heard \"{s}\", want \"{s}\"", .{ key, value, said, want_said }),
        else => |v| return fail("judge {s}=\"{s}\" gave {s}, want refused", .{ key, value, @tagName(v) }),
    }
}

fn expectVerdict(key: []const u8, value: []const u8, want: std.meta.Tag(edit.Verdict)) !void {
    var line: [edit.LINE_MAX]u8 = undefined;
    const got = edit.judge(&line, key, value);
    if (got != want) return fail("judge {s}=\"{s}\" gave {s}, want {s}", .{ key, value, @tagName(got), @tagName(want) });
}

fn expectSet(text: []const u8, key: []const u8, value: []const u8, want: []const u8) !void {
    var out: [config.MAX_FILE * 2]u8 = undefined;
    const got = edit.setLine(&out, text, key, value) orelse return fail("setLine {s}={s} overflowed", .{ key, value });
    if (!std.mem.eql(u8, got, want))
        return fail("setLine {s}={s} on\n{s}\n--- gave ---\n{s}\n--- want ---\n{s}", .{ key, value, text, got, want });
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

fn expectText(got: []const u8, want: []const u8, what: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) return fail("{s}:\n--- got ---\n{s}\n--- want ---\n{s}", .{ what, got, want });
}

var cmd_pairs: [edit.PAIRS_MAX]edit.Pair = undefined;
var cmd_defaults: [edit.PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;

fn command(args: edit.Rest) edit.Command {
    return edit.parseCommand(args, &cmd_pairs, &cmd_defaults);
}

fn expectCommand(args: edit.Rest, want: std.meta.Tag(edit.Command)) !edit.Command {
    const got = command(args);
    if (got != want) return fail("parseCommand {s}… gave {s}, want {s}", .{ if (args.len > 0) std.mem.span(args[0]) else "(none)", @tagName(got), @tagName(want) });
    return got;
}

/// a와 b가 정확히 한 줄만 다른가.
fn oneLineApart(a: []const u8, b: []const u8) bool {
    var ia = edit.Lines{ .text = a };
    var ib = edit.Lines{ .text = b };
    var diffs: usize = 0;
    while (true) {
        const sa = ia.next();
        const sb = ib.next();
        if (sa == null and sb == null) break;
        if (sa == null or sb == null) return false;
        if (!std.mem.eql(u8, a[sa.?.start..sa.?.end], b[sb.?.start..sb.?.end])) diffs += 1;
    }
    return diffs == 1;
}

pub fn main() !void {
    try scratch.enter();
    // ── 1. 키는 Config의 필드 이름이고, parse가 그 이름을 전부 안다 ─────
    //
    // 필드를 더하고 parse의 갈래를 빠뜨리면 여기서 "unknown config key"를 듣는다.
    // 기본값을 글자로 바꿨다가 되읽어 같은지도 본다 — valueText와 parse가 같은
    // 글자를 쓴다는 것이 `set`이 쓰는 줄을 init이 읽는다는 뜻이다.
    if (edit.KEYS.len != 12) return fail("{d} keys, want 12 (the seed has twelve)", .{edit.KEYS.len});
    const defaults = config.Config{};
    for (edit.KEYS) |key| {
        var buf: [edit.VALUE_MAX]u8 = undefined;
        try expectOk(key, valueOf(&defaults, key, &buf), valueOf(&defaults, key, &buf));
        const v = other(key) orelse return fail("OTHER has no row for {s}", .{key});
        try expectOk(key, v, v);
        if (edit.hint(key) == null) return fail("no hint for {s}", .{key});
    }
    if (OTHER.len != edit.KEYS.len) return fail("OTHER has {d} rows for {d} keys", .{ OTHER.len, edit.KEYS.len });
    if (edit.isKey("colour") or edit.hint("colour") != null) return fail("colour is a key", .{});
    if (!std.mem.eql(u8, edit.hint("shell").?, "fish | bash | zsh")) return fail("shell hint {s}", .{edit.hint("shell").?});
    std.debug.print("config_edit_test: twelve keys, each read back by parse as written\n", .{});

    // ── 2. judge — init이 하는 말이 곧 거절의 이유다 ───────────────────
    try expectRefused("shell", "fsh", "unknown shell 'fsh', falling back to fish");
    try expectRefused("net", "on", "unknown net 'on', falling back to off");
    try expectRefused("ntp", "pool.ntp.org", "unknown ntp 'pool.ntp.org', falling back to off");
    try expectRefused("timezone", "/etc/passwd", "unknown timezone '/etc/passwd', falling back to UTC");
    // 목록은 init이 이름 하나만 버리고 나머지를 받는다. set은 그 하나 때문에 통째로 거절한다.
    try expectRefused("hangul_toggle", "nosuch,shift_space", "unknown hangul_toggle 'nosuch', ignored");
    try expectRefused("shell", "", "unknown shell '', falling back to fish");
    try expectVerdict("colour", "red", .unknown_key);
    try expectVerdict("", "zsh", .unknown_key);
    // 개행 하나가 한 번의 set을 두 줄로 만든다.
    try expectVerdict("shell", "zsh\nnet=dhcp", .control_byte);
    try expectVerdict("shell", "zsh\r", .control_byte);
    try expectVerdict("timezone", &@as([300]u8, @splat('a')), .too_long);
    // 정규형으로 쓴다 — 적은 순서 · 공백 · 0으로 시작하는 주소가 init의 글자로 바뀐다.
    try expectOk("hangul_toggle", " lctrl_tap , shift_space ", "shift_space,lctrl_tap");
    try expectOk("hangul_toggle", "", "none");
    try expectOk("hangul_toggle", "none", "none");
    try expectOk("ntp", "010.000.2.2", "10.0.2.2");
    // 모양만 본다. 그 파일이 있는지는 config_cli의 bootRefuses가 게스트에서 본다.
    try expectOk("timezone", "Asia/Seol", "Asia/Seol");
    std.debug.print("config_edit_test: judge hears init's own words, refuses control bytes, writes the canonical form\n", .{});

    // ── 3. classify는 parse와 같은 규칙으로 가른다 ───────────────────────
    //
    // 줄마다 둘에 함께 넣는다. parse가 말없이 받는 줄은 classify가 건너뛰는 줄이거나
    // judge가 받는 쌍이어야 하고, 그 반대도 같다.
    const lines = [_][]const u8{
        "",                "   ",                   "# shell=zsh", "  # x",           "shell=zsh",
        "  shell = zsh  ", "\tshell\t=\tzsh",       "shell=zsh\r", "shell=zsh=extra", "no equals",
        "=zsh",            "shell=",                "colour=red",  "net = dhcp",      "hangul_toggle=",
        "ntp=1.2.3",       "timezone = Asia/Seoul",
    };
    for (lines) |raw| {
        edit.heard = .{};
        _ = config.parse(raw);
        const quiet = edit.heard.count == 0;
        var lbuf: [edit.LINE_MAX]u8 = undefined;
        const accepted = switch (edit.classify(raw)) {
            .skip => true,
            .no_equals => false,
            .pair => |p| edit.judge(&lbuf, p.key, p.value) == .ok,
        };
        if (quiet != accepted) return fail("\"{s}\": parse quiet={}, classify+judge accepted={}", .{ raw, quiet, accepted });
    }
    switch (edit.classify("  shell = zsh  \r")) {
        .pair => |p| if (!std.mem.eql(u8, p.key, "shell") or !std.mem.eql(u8, p.value, "zsh"))
            return fail("classify gave [{s}]=[{s}]", .{ p.key, p.value }),
        else => return fail("classify did not see a pair", .{}),
    }
    std.debug.print("config_edit_test: classify splits {d} lines the way parse does\n", .{lines.len});

    // ── 4. setLine — 그 키의 이기는 줄 하나만 바꾼다 ─────────────────────
    try expectSet("", "net", "dhcp", "net=dhcp\n");
    try expectSet("shell=zsh", "net", "dhcp", "shell=zsh\nnet=dhcp\n");
    try expectSet("shell=zsh\n", "net", "dhcp", "shell=zsh\nnet=dhcp\n");
    // 마지막 줄이 이기므로 그 줄을 바꾼다. 앞 줄은 그대로 둔다(check가 알린다).
    try expectSet("shell=zsh\nnet=off\nshell=bash\n", "shell", "fish", "shell=zsh\nnet=off\nshell=fish\n");
    // 사람의 주석 · 모르는 키 · 틀린 줄 · 끝에 개행 없음 — 바꾸는 줄 밖은 바이트 하나 안 바뀐다.
    try expectSet("# mine\ncolour=red\n  net = off  # old\nno equals\nkeyboard=pc", "net", "dhcp", "# mine\ncolour=red\nnet=dhcp\nno equals\nkeyboard=pc");
    // CRLF 줄은 그 줄만 LF가 된다(parse는 \r을 뗀다).
    try expectSet("shell=zsh\r\nnet=off\r\n", "net", "dhcp", "shell=zsh\r\nnet=dhcp\n");
    // 주석 안의 키는 줄이 아니다.
    try expectSet("#net=dhcp\n", "net", "off", "#net=dhcp\nnet=off\n");
    {
        var small: [8]u8 = undefined;
        if (edit.setLine(&small, "shell=zsh\n", "net", "dhcp") != null) return fail("setLine fit 19 bytes in 8", .{});
    }
    if (edit.lastLine("shell=zsh\nnet=off\nshell=bash", "shell").?.number != 3) return fail("lastLine number", .{});
    if (edit.lastLine("#shell=zsh\n", "shell") != null) return fail("lastLine found a comment", .{});
    {
        var nums: [4]usize = undefined;
        const n = edit.lineNumbers("shell=a\n\nshell=b\n# shell=c\nshell=d\n", "shell", &nums);
        if (n != 3 or nums[0] != 1 or nums[1] != 3 or nums[2] != 5) return fail("lineNumbers gave {d}", .{n});
    }

    // 진짜 seed — init이 첫 부팅에 쓰는 그 파일 — 에서 키마다 한 번씩. 바뀐 것이 그
    // 한 줄뿐이고, parse가 새 값을 읽고, 다른 열한 키는 기본값 그대로다.
    config.save(SEED_PATH, defaults) catch return fail("config.save {s}", .{SEED_PATH});
    var seed_buf: [config.MAX_FILE]u8 = undefined;
    const seed = try readAll(SEED_PATH, &seed_buf);
    _ = linux.unlink(SEED_PATH);
    if (seed.len < 500) return fail("the seed is only {d} bytes", .{seed.len});
    for (edit.KEYS) |key| {
        var out: [config.MAX_FILE * 2]u8 = undefined;
        const v = other(key).?;
        const got = edit.setLine(&out, seed, key, v).?;
        if (!oneLineApart(seed, got)) return fail("set {s} on the seed changed more or less than one line", .{key});
        if (got.len > config.MAX_FILE) return fail("set {s} grew the seed past MAX_FILE", .{key});
        edit.heard = .{};
        const c = config.parse(got);
        if (edit.heard.count != 0) return fail("parse complained after set {s}: {s}", .{ key, edit.heard.first() });
        for (edit.KEYS) |k| {
            var b1: [edit.VALUE_MAX]u8 = undefined;
            var b2: [edit.VALUE_MAX]u8 = undefined;
            const want = if (std.mem.eql(u8, k, key)) v else valueOf(&defaults, k, &b2);
            const now = valueOf(&c, k, &b1);
            if (!std.mem.eql(u8, now, want)) return fail("after set {s}: {s}={s}, want {s}", .{ key, k, now, want });
        }
        var lbuf: [edit.LINE_MAX]u8 = undefined;
        if (!edit.setByFile(&lbuf, seed, key)) return fail("the seed does not set {s}", .{key});
    }
    std.debug.print("config_edit_test: set on the real seed ({d} bytes) changes one line per key and parse reads it\n", .{seed.len});

    // ── 5. setByFile — 줄이 있어도 init이 버리면 기본값이다 ──────────────
    {
        var lbuf: [edit.LINE_MAX]u8 = undefined;
        if (edit.setByFile(&lbuf, "", "shell")) return fail("setByFile on an empty file", .{});
        if (edit.setByFile(&lbuf, "#shell=zsh\n", "shell")) return fail("setByFile on a comment", .{});
        if (edit.setByFile(&lbuf, "shell=fsh\n", "shell")) return fail("setByFile on a refused line", .{});
        if (!edit.setByFile(&lbuf, "shell=zsh\nshell=fsh\n", "shell")) return fail("setByFile missed the line parse keeps", .{});
    }

    // ── 6. 마운트 표와 옛 별칭 ────────────────────────────────────────────
    const mounts =
        \\rootfs / rootfs rw 0 0
        \\proc /proc proc rw,relatime 0 0
        \\/dev/vda /config ext2 rw,sync,nosuid,nodev,relatime 0 0
        \\
    ;
    if (!std.mem.eql(u8, edit.mountSource(mounts, "/config") orelse "", "/dev/vda")) return fail("mountSource /config", .{});
    if (edit.mountSource(mounts, "/conf") != null) return fail("mountSource matched a prefix", .{});
    if (edit.mountSource("rootfs / rootfs rw 0 0\n", "/config") != null) return fail("mountSource without /config", .{});

    if (edit.staleAlias("# x\nalias tars-config='cat /config/tars.conf'\n") != 2) return fail("staleAlias missed the old seed line", .{});
    if (edit.staleAlias("alias tars-config 'cat /config/tars.conf'\n") != 1) return fail("staleAlias missed the fish form", .{});
    if (edit.staleAlias("alias tars-configs='x'\n# alias tars-config='x'\nalias tars-rc='x'\n") != null)
        return fail("staleAlias matched something else", .{});
    // 지금의 seed 셋에는 그 줄이 없다 — 이 명령을 가리는 별칭을 우리가 다시 깔지 않는다.
    for (std.enums.values(config.Shell)) |sh| {
        if (edit.staleAlias(sh.rcSeed())) |n| return fail("the {s} seed line {d} aliases tars-config", .{ @tagName(sh), n });
    }
    std.debug.print("config_edit_test: /config's device is read from the mount table; no seed aliases tars-config\n", .{});

    // HC-M0. 아래 7 ~ 11의 기대 글자는 옮기기 전 config_cli.zig의 서식 문자열에서 베꼈다 — 옮긴 함수의
    // 출력에서 베끼면 검사가 그 함수를 그대로 되풀이할 뿐이다(HC design 결정 9). 폭 26칸 패딩은
    // 셸의 `printf '%-26s'`로 셌다.

    // ── 7. parseCommand — main의 사다리를 그대로 ─────────────────────────
    const A = [*:0]const u8;
    _ = try expectCommand(&[_]A{}, .show);
    for ([_]A{ "help", "-h", "--help" }) |v| _ = try expectCommand(&[_]A{v}, .help);
    for ([_]A{ "version", "--version", "-V" }) |v| _ = try expectCommand(&[_]A{v}, .version);
    _ = try expectCommand(&[_]A{"list"}, .list);
    _ = try expectCommand(&[_]A{"check"}, .check);
    _ = try expectCommand(&[_]A{"unset"}, .unset);
    // unset은 뒤에 무엇이 와도 같은 말을 한다.
    _ = try expectCommand(&[_]A{ "unset", "shell" }, .unset);
    if ((try expectCommand(&[_]A{"reload"}, .reload)).reload) return fail("reload gave reload terminal", .{});
    if (!(try expectCommand(&[_]A{ "reload", "terminal" }, .reload)).reload) return fail("reload terminal gave reload", .{});
    // 앞문 다섯은 동사 뒤를 그대로 넘긴다. 비어 있어도 그 동사다.
    if ((try expectCommand(&[_]A{ "wifi", "a", "b" }, .wifi)).wifi.len != 2) return fail("wifi a b did not keep two args", .{});
    if ((try expectCommand(&[_]A{"ssh"}, .ssh)).ssh.len != 0) return fail("ssh kept an arg", .{});
    _ = try expectCommand(&[_]A{ "ssh-key", "list" }, .ssh_key);
    _ = try expectCommand(&[_]A{ "firewall", "allow", "22" }, .firewall);
    _ = try expectCommand(&[_]A{"dictation"}, .dictation);
    try expectText((try expectCommand(&[_]A{ "get", "shell" }, .get)).get, "shell", "get shell");
    try expectText((try expectCommand(&[_]A{ "get", " shell\t" }, .get)).get, "shell", "get with spaces");
    {
        const ps = (try expectCommand(&[_]A{ "set", "shell=zsh", " net = dhcp " }, .change)).change;
        if (ps.len != 2) return fail("set gave {d} pairs, want 2", .{ps.len});
        try expectText(ps[0].key, "shell", "set pair 0 key");
        try expectText(ps[0].value, "zsh", "set pair 0 value");
        try expectText(ps[1].key, "net", "set pair 1 key");
        try expectText(ps[1].value, "dhcp", "set pair 1 value");
        // 첫 `=`에서 나눈다 — 값 속의 `=`는 값이다(judge가 거절할 일이다).
        const eqs = (try expectCommand(&[_]A{ "set", "shell=a=b" }, .change)).change;
        try expectText(eqs[0].value, "a=b", "set splits at the first =");
        // reset은 기본값을 적는 set이다.
        const rs = (try expectCommand(&[_]A{ "reset", " shell ", "net" }, .change)).change;
        if (rs.len != 2) return fail("reset gave {d} pairs, want 2", .{rs.len});
        try expectText(rs[0].key, "shell", "reset pair 0 key");
        try expectText(rs[0].value, "fish", "reset pair 0 value");
        try expectText(rs[1].value, "off", "reset pair 1 value");
    }
    const usages = [_][]const A{
        &.{ "help", "x" }, &.{ "-h", "x" },       &.{ "version", "x" }, &.{ "-V", "x" },
        &.{ "list", "x" }, &.{ "check", "x" },    &.{ "reload", "x" },  &.{ "reload", "terminal", "x" },
        &.{"get"},         &.{ "get", "a", "b" }, &.{"set"},            &.{"reset"},
        &.{"frobnicate"},  &.{"Set"},             &.{"--list"},
    };
    for (usages) |args| _ = try expectCommand(args, .usage);
    {
        var many: [1 + edit.PAIRS_MAX + 1]A = @splat("shell=zsh");
        many[0] = "set";
        _ = try expectCommand(&many, .usage);
        if ((try expectCommand(many[0 .. 1 + edit.PAIRS_MAX], .change)).change.len != edit.PAIRS_MAX) return fail("set with PAIRS_MAX pairs", .{});
    }
    try expectText((try expectCommand(&[_]A{ "set", "shell" }, .no_equals)).no_equals, "shell", "set shell");
    // 거절은 처음 걸린 인자에서 멈춘다.
    try expectText((try expectCommand(&[_]A{ "set", "net=dhcp", "shell", "x" }, .no_equals)).no_equals, "shell", "set with a bare second arg");
    try expectText((try expectCommand(&[_]A{ "reset", "shell", " nope " }, .unknown_key)).unknown_key, "nope", "reset nope");
    std.debug.print("config_edit_test: parseCommand sorts the verbs the way main did, refusals included\n", .{});

    // ── 8. init의 답을 읽는다 — reload가 지은 그대로 ────────────────────
    {
        var file_buf: [512]u8 = undefined;
        var w: std.Io.Writer = .fixed(&file_buf);
        for (OTHER) |p| w.print("{s}={s}\n", .{ p.key, p.value }) catch return fail("OTHER does not fit", .{});
        edit.heard = .{};
        const live = config.parse(file_buf[0..w.end]);
        if (edit.heard.count != 0) return fail("parse complained about OTHER: {s}", .{edit.heard.first()});

        var rbuf: [control.REPLY_MAX]u8 = undefined;
        var out = reload.Out{ .buf = &rbuf };
        reload.configReply(&out, live, live);
        for (OTHER) |p| {
            const got = edit.nowValue(out.bytes(), p.key) orelse return fail("nowValue found no {s}", .{p.key});
            try expectText(got, p.value, p.key);
        }
        if (edit.nowValue(out.bytes(), "colour") != null) return fail("nowValue found colour", .{});
        // 화면과 init이 같으면 screen 줄이 없다.
        if (edit.screenLine(out.bytes()) != null) return fail("screenLine with nothing pending", .{});
        // 키가 다른 키의 앞부분이어도 그 키만 — shell은 shell_config가 아니다.
        try expectText(edit.nowValue("shell_config=off\nshell=zsh\n", "shell") orelse "", "zsh", "nowValue shell after shell_config");

        // 화면이 기다리는 키. reload_test 4의 그 답이다.
        var sbuf: [control.REPLY_MAX]u8 = undefined;
        var so = reload.Out{ .buf = &sbuf };
        reload.configReply(&so, config.parse("keyboard=pc\nnet=dhcp\ntimezone=Asia/Seoul\n"), defaults);
        try expectText(edit.screenLine(so.bytes()) orelse "", " keyboard=apple timezone=UTC", "screenLine");
        try expectText(edit.nowValue(so.bytes(), "keyboard") orelse "", "pc", "nowValue keyboard with a screen line");
    }
    std.debug.print("config_edit_test: nowValue and screenLine read what reload.configReply writes\n", .{});

    // ── 9. changeLine — set · reset의 결과 한 줄 ─────────────────────────
    {
        var lb: [edit.LINE_MAX]u8 = undefined;
        try expectText(edit.changeLine(&lb, "shell", "fish", true, "zsh"), "shell: fish (default) -> zsh\n", "changeLine from the default");
        try expectText(edit.changeLine(&lb, "shell", "bash", false, "zsh"), "shell: bash -> zsh\n", "changeLine from a line");
        try expectText(edit.changeLine(&lb, "shell", "zsh", false, "zsh"), "shell: zsh (unchanged)\n", "changeLine unchanged");
        // 같으면 기본값이었는지는 말하지 않는다.
        try expectText(edit.changeLine(&lb, "net", "off", true, "off"), "net: off (unchanged)\n", "changeLine unchanged default");
        // 가장 긴 것도 LINE_MAX 안이다.
        const old: [edit.VALUE_MAX]u8 = @splat('a');
        const new: [edit.VALUE_MAX]u8 = @splat('b');
        if (edit.changeLine(&lb, "hangul_layout", &old, true, &new).len != "hangul_layout: ".len + old.len + " (default) -> ".len + new.len + 1)
            return fail("changeLine of the longest values", .{});
    }
    std.debug.print("config_edit_test: changeLine says unchanged, (default) or the old value\n", .{});

    // ── 10. keyTable · showKeyLines ─────────────────────────────────────
    {
        var tbuf: [4096]u8 = undefined;
        var t = control.Out{ .buf = &tbuf };
        edit.keyTable(&t);
        if (t.full) return fail("keyTable did not fit in 4096 bytes", .{});
        if (std.mem.count(u8, t.bytes(), "\n") != edit.KEYS.len) return fail("keyTable printed {d} lines", .{std.mem.count(u8, t.bytes(), "\n")});
        if (!std.mem.startsWith(u8, t.bytes(), "  shell=fish                 fish | bash | zsh\n")) return fail("keyTable first row:\n{s}", .{t.bytes()});
        const rows = [_][]const u8{
            "\n  net=off                    off | dhcp\n",
            "\n  ntp=off                    off | dhcp | <IPv4 address>\n",
            "\n  timezone=UTC               UTC | <a name under /usr/share/zoneinfo, e.g. Asia/Seoul>\n",
            "\n  firewall=off               off | on\n",
            // 26칸을 넘는 쌍은 자르지 않고 빈칸 하나로 잇는다.
            "\n  hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap a comma list of ",
        };
        for (rows) |row| if (std.mem.indexOf(u8, t.bytes(), row) == null) return fail("keyTable has no row{s}--- got ---\n{s}", .{ row, t.bytes() });

        const text = "shell=zsh\nnet=bogus\n";
        edit.heard = .{};
        const c = config.parse(text);
        const keys_tail = "#keyboard=apple\n#hangul_layout=shin_pcs\n#latin_layout=qwerty\n" ++
            "#hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap\n#shell_config=on\n#net=off\n";
        const keys_end = "#ntp=off\n#timezone=UTC\n#firewall=off\n#esc_latin=on\n#clipboard=shared\n";
        var sbuf: [2048]u8 = undefined;
        var s = control.Out{ .buf = &sbuf };
        edit.showKeyLines(&s, text, &c, null);
        // 틀린 줄(net=bogus)은 init이 버리므로 기본값이고 `#`이다.
        try expectText(s.bytes(), "shell=zsh\n" ++ keys_tail ++ keys_end, "showKeyLines without init");

        var rbuf: [control.REPLY_MAX]u8 = undefined;
        var r = reload.Out{ .buf = &rbuf };
        const live = config.parse("shell=zsh\nnet=dhcp\n");
        reload.configReply(&r, live, live);
        s = control.Out{ .buf = &sbuf };
        edit.showKeyLines(&s, text, &c, r.bytes());
        try expectText(s.bytes(), "shell=zsh\n" ++ keys_tail ++
            "#   init uses net=dhcp now; tars-config reload applies the line above\n" ++ keys_end, "showKeyLines with init's answer");

        // MAX_FILE 밖의 줄은 init이 안 읽는다 — 그 줄은 키를 정하지 않는다.
        var long_buf: [config.MAX_FILE + 16]u8 = undefined;
        long_buf[0] = '#';
        @memset(long_buf[1 .. config.MAX_FILE - 1], 'x');
        long_buf[config.MAX_FILE - 1] = '\n';
        const tail = "shell=zsh\n";
        @memcpy(long_buf[config.MAX_FILE..][0..tail.len], tail);
        const long_text = long_buf[0 .. config.MAX_FILE + tail.len];
        edit.heard = .{};
        const lc = config.parse(long_text[0..config.MAX_FILE]);
        s = control.Out{ .buf = &sbuf };
        edit.showKeyLines(&s, long_text, &lc, null);
        if (!std.mem.startsWith(u8, s.bytes(), "#shell=fish\n#keyboard=apple\n")) return fail("showKeyLines read past MAX_FILE:\n{s}", .{s.bytes()});
    }
    std.debug.print("config_edit_test: keyTable rows and show's key lines, with init's value under the line it differs from\n", .{});

    // ── 11. checkLines ──────────────────────────────────────────────────
    {
        var cbuf: [1024]u8 = undefined;
        var o = control.Out{ .buf = &cbuf };
        if (edit.checkLines(&o, "# mine\nshell=zsh\n\nnet=dhcp\n") != 0 or o.len != 0) return fail("checkLines on a clean file:\n{s}", .{o.bytes()});
        o = control.Out{ .buf = &cbuf };
        if (edit.checkLines(&o, "#x\nshell=fsh") != 1) return fail("checkLines did not count shell=fsh", .{});
        try expectText(o.bytes(), "line 2: unknown shell 'fsh', falling back to fish\n", "checkLines shell=fsh");
        // 같은 키가 여러 줄인 것은 알리지만 문제로 세지 않는다 — 마지막 줄이 이긴다.
        o = control.Out{ .buf = &cbuf };
        if (edit.checkLines(&o, "shell=zsh\n#x\nshell=fish\n") != 0) return fail("checkLines counted a repeated key", .{});
        try expectText(o.bytes(), "shell is on 2 lines (1, 3); the last one wins\n", "checkLines repeated key");
        // 둘 다 — 틀린 줄이 먼저, 겹친 키가 뒤.
        o = control.Out{ .buf = &cbuf };
        if (edit.checkLines(&o, "net=on\nnet=dhcp\n") != 1) return fail("checkLines net=on", .{});
        try expectText(o.bytes(), "line 1: unknown net 'on', falling back to off\nnet is on 2 lines (1, 2); the last one wins\n", "checkLines both");
        // MAX_FILE 밖의 틀린 줄은 init이 안 읽으므로 말하지 않는다.
        var long_buf: [config.MAX_FILE + 16]u8 = undefined;
        long_buf[0] = '#';
        @memset(long_buf[1 .. config.MAX_FILE - 1], 'x');
        long_buf[config.MAX_FILE - 1] = '\n';
        const tail = "shell=fsh\n";
        @memcpy(long_buf[config.MAX_FILE..][0..tail.len], tail);
        o = control.Out{ .buf = &cbuf };
        if (edit.checkLines(&o, long_buf[0 .. config.MAX_FILE + tail.len]) != 0) return fail("checkLines read past MAX_FILE:\n{s}", .{o.bytes()});
    }
    std.debug.print("config_edit_test: checkLines names init's complaint per line and the keys written twice\n", .{});

    std.debug.print("PASS\n", .{});
}
