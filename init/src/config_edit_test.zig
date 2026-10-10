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
    try expectVerdict("timezone", "a" ** 300, .too_long);
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
        "",               "   ",            "# shell=zsh",  "  # x",           "shell=zsh",
        "  shell = zsh  ", "\tshell\t=\tzsh", "shell=zsh\r",  "shell=zsh=extra", "no equals",
        "=zsh",           "shell=",         "colour=red",   "net = dhcp",      "hangul_toggle=",
        "ntp=1.2.3",      "timezone = Asia/Seoul",
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
    try expectSet("# mine\ncolour=red\n  net = off  # old\nno equals\nkeyboard=pc",
        "net", "dhcp", "# mine\ncolour=red\nnet=dhcp\nno equals\nkeyboard=pc");
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

    std.debug.print("PASS\n", .{});
}
