//! TC-M0. `tars-config` — `/config/tars.conf`를 보고 고치는 명령(TC design 결정 1).
//!
//! init이 부팅에 한 번 읽는 그 파일을 사람이 셸에서 다룬다. 인자 없이 치면 init이
//! 읽을 모양으로 보여 주고, `get` · `set` · `reset` · `check`가 있다. 값이 맞는지는
//! init과 같은 `config.parse`가 정하고(`config_edit.judge`), 쓰는 것은 그 키의 줄
//! 하나다. 고친 것은 다음 부팅부터다 — init은 이 파일을 다시 읽지 않는다(결정 7).
//!
//! 이 파일은 시스템 콜 쪽이다. 글자를 다루는 것은 전부 `config_edit.zig`이고 호스트
//! 검사가 본다. 표준 출력은 사람이 읽는 답이고, 거절과 실패는 `tars-config: `로
//! 시작하는 줄로 표준 에러에 간다.
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const edit = @import("config_edit.zig");
const front = @import("config_front.zig");
const control = @import("control.zig");

/// config.zig의 로그를 가로챈다(config.zig의 `log`). 이 한 줄이 없으면 `set`이 틀린
/// 값을 받을 때 `tars-init: unknown shell …`이 이 명령의 표준 에러에 그대로 찍히고,
/// 거절의 이유를 이 명령이 들을 수 없다.
pub const configLog = edit.configLog;

pub const CONF_PATH: [:0]const u8 = "/config/tars.conf";
/// 새 내용을 먼저 여기 쓰고 `rename`으로 갈아 끼운다(결정 5). 쓰다 끊겨도 init이
/// 읽는 파일은 옛것 그대로이거나 새것 그대로다. `/config`는 `MS_SYNCHRONOUS`라
/// write와 rename이 돌아온 때 이미 디스크에 있다.
const TEMP_PATH: [:0]const u8 = "/config/.tars.conf.new";
const MOUNTS_PATH: [:0]const u8 = "/proc/mounts";
const CONFIG_DIR = "/config";

pub const EXIT_OK: u8 = 0;
/// 값을 거절했다 · `check`가 문제를 찾았다.
pub const EXIT_REFUSED: u8 = 1;
/// 설정 디스크가 없다 · 파일을 못 읽거나 못 썼다.
pub const EXIT_IO: u8 = 2;
pub const EXIT_USAGE: u8 = 64;

/// 한 번의 `set` · `reset`이 받는 쌍의 상한.
const PAIRS_MAX = 16;
/// 파일을 읽는 버퍼. `config.MAX_FILE`의 두 배라 넘는 파일을 "넘는다"고 말할 수 있다.
pub const READ_MAX = 2 * config.MAX_FILE;

pub fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

pub fn writeAll(fd: i32, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return false;
        }
        if (n == 0) return false;
        off += n;
    }
    return true;
}

pub fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [READ_MAX + 256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = writeAll(1, text);
}

pub fn complain(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-config: " ++ fmt ++ "\n", args) catch return;
    _ = writeAll(2, text);
}

const USAGE =
    \\usage: tars-config                     show /config/tars.conf as init reads it
    \\       tars-config get KEY             print one value
    \\       tars-config set KEY=VALUE...    change values; init reads them at the next boot
    \\       tars-config reset KEY...        put keys back to their defaults
    \\       tars-config check               list the lines init would complain about
    \\       tars-config list                every key with its default and the values it takes
    \\       tars-config reload              init rereads tars.conf and services.d now (TC-M2)
    \\       tars-config help                this text and the list
    \\
    \\other files under /config (TC-M1):
    \\       tars-config wifi [SSID [--country CC]]       add or replace a network; the passphrase is asked for
    \\       tars-config ssh [on|off]                     sshd at boot (the services.d link)
    \\       tars-config ssh-key add [KEY] | list         /config/ssh/authorized_keys
    \\       tars-config firewall [allow|deny PORT[/udp]] ports tars-config opens, applied now if firewall=on
    \\       tars-config dictation [key [KEY] | set KEY=VALUE...]   /config/groq.key and dictation.conf
    \\
;

pub fn usage() u8 {
    _ = writeAll(2, USAGE);
    return EXIT_USAGE;
}

fn help() u8 {
    _ = writeAll(1, USAGE);
    say("\nkeys (with their defaults):\n", .{});
    keyTable();
    say("\ninit reads /config/tars.conf only at boot. To reboot: kill -INT 1\n", .{});
    return EXIT_OK;
}

/// 무엇을 적을 수 있는가(TC-M0 수정 1 — 사용자: "어떤 설정 정보를 쓸 수 있는지 알아야
/// 세팅을 하거나 언세팅을 할 수 있지 않을까"). `help`의 표만 찍는다. 파일도 디스크도 안
/// 본다 — 지금 값은 인자 없는 `tars-config`가 보여 준다.
fn list() u8 {
    keyTable();
    say("  (wifi · ssh · ssh-key · firewall · dictation write other files — tars-config help)\n", .{});
    return EXIT_OK;
}

/// 열두 키를 `key=기본값`과 받는 값으로 한 줄씩. `help`와 `list`가 함께 쓴다. 왼쪽 칸은
/// 그대로 `set`에 줄 수 있는 모양이고(`reset`이 적는 값이 그것이다), 오른쪽은
/// `config_edit.hint` — enum이면 config.zig의 이름에서 컴파일 타임에 나온다.
fn keyTable() void {
    const defaults = config.Config{};
    for (edit.KEYS) |key| {
        var vbuf: [edit.VALUE_MAX]u8 = undefined;
        var pair_buf: [edit.LINE_MAX]u8 = undefined;
        const pair = std.fmt.bufPrint(&pair_buf, "{s}={s}", .{ key, edit.valueText(&defaults, key, &vbuf).? }) catch key;
        say("  {s:<26} {s}\n", .{ pair, edit.hint(key).? });
    }
}

// ── 읽기 ──────────────────────────────────────────────────────────────

pub const Read = union(enum) { missing, failed: linux.E, bytes: []const u8 };

pub fn readFile(path: [*:0]const u8, buf: []u8) Read {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| return if (e == .NOENT) .missing else .{ .failed = e };
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return .{ .failed = e };
        }
        if (n == 0) break;
        len += n;
    }
    return .{ .bytes = buf[0..len] };
}

/// `/config`에 붙은 장치. init이 설정 디스크를 찾았을 때만 있다 — 못 찾은 부팅의
/// `/config`는 initrd 안의 빈 디렉터리이고 init은 거기서 파일을 읽지도 않는다.
pub fn configDisk(buf: []u8) ?[]const u8 {
    return switch (readFile(MOUNTS_PATH, buf)) {
        .bytes => |b| edit.mountSource(b, CONFIG_DIR),
        else => null,
    };
}

/// 지금의 설정. init이 다음 부팅에 읽을 것과 같은 길로 읽는다.
const Current = struct {
    /// 설정 디스크의 장치. null이면 디스크가 없고 `text`는 비어 있다.
    disk: ?[]const u8,
    exists: bool,
    text: []const u8,
};

fn current(mounts_buf: []u8, text_buf: []u8) ?Current {
    const disk = configDisk(mounts_buf) orelse return .{ .disk = null, .exists = false, .text = "" };
    return switch (readFile(CONF_PATH, text_buf)) {
        .missing => .{ .disk = disk, .exists = false, .text = "" },
        .bytes => |b| .{ .disk = disk, .exists = true, .text = b },
        .failed => |e| {
            complain("cannot read {s} (errno {d})", .{ CONF_PATH, @intFromEnum(e) });
            return null;
        },
    };
}

/// init의 `load`가 하는 것과 같다 — 앞의 `MAX_FILE` 바이트만 `parse`에 준다.
pub fn parsed(text: []const u8) config.Config {
    return config.parse(text[0..@min(text.len, config.MAX_FILE)]);
}

/// main.zig의 `zoneinfoIsTzif`와 같은 판정이다(그 함수가 private이라 여기 둔다 —
/// 열 줄짜리 시스템 콜을 공용 모듈로 빼는 것보다 각자 갖는 편이 이 저장소의 선이다).
fn zoneinfoIsTzif(path: [:0]const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return false;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var head: [config.TZIF_MAGIC.len]u8 = undefined;
    const n = linux.read(fd, &head, head.len);
    if (failed(n)) |_| return false;
    return config.looksLikeTzif(head[0..n]);
}

/// init이 부팅에 받아 놓고 다른 길로 버리는 값. 지금은 `timezone` 하나다 —
/// `parse`는 모양만 보고, 파일이 정말 있는지는 main.zig의 `resolveTimezone`이 본다.
/// 버리면 null이 아니라 그 이유를 path_buf에 지어 돌려준다.
fn bootRefuses(c: *const config.Config, path_buf: *[config.ZONEINFO_PATH_MAX]u8) ?[:0]const u8 {
    if (c.timezone.eql(config.Timezone.UTC)) return null;
    const path = config.zoneinfoPath(path_buf, c.timezone);
    if (zoneinfoIsTzif(path)) return null;
    return path;
}

// ── init에 묻기(TC-M2) ────────────────────────────────────────────────

/// `config`의 답을 기다리는 시간. `tars-service`와 같다.
const ASK_MS: i32 = 2000;
/// `reload`의 답. init이 nft 한 번과 services.d를 지나 답한다(reload design 결정 4).
const RELOAD_MS: i32 = 10000;

/// init.sock에 동사 하나를 보내고 답을 받는다. 못 닿거나 답이 없으면 null.
fn askInit(verb: control.Verb, buf: []u8, ms: i32) ?[]const u8 {
    var req_buf: [16]u8 = undefined;
    const req = control.formatRequest(&req_buf, verb, null) orelse return null;
    return switch (control.dial(control.PATH, req)) {
        .failed => null,
        .fd => |fd| control.awaitReply(fd, buf, ms),
    };
}

/// `config`의 답에서 그 키의 값.
fn nowValue(reply: []const u8, key: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, reply, '\n');
    while (it.next()) |line| {
        if (line.len > key.len and std.mem.startsWith(u8, line, key) and line[key.len] == '=') return line[key.len + 1 ..];
    }
    return null;
}

/// `config`의 답의 `screen …` 줄(화면이 대기 중인 키)의 꼬리. 없으면 null.
fn screenLine(reply: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, reply, '\n');
    while (it.next()) |line| if (std.mem.startsWith(u8, line, "screen ")) return line["screen".len..];
    return null;
}

/// `tars-config reload`(reload design 결정 7). init의 답을 그대로 찍는다.
fn reloadInit() u8 {
    var buf: [control.REPLY_MAX]u8 = undefined;
    const r = askInit(.reload, &buf, RELOAD_MS) orelse {
        complain("init did not answer at {s}", .{control.PATH});
        return EXIT_IO;
    };
    _ = writeAll(1, r);
    return if (std.mem.startsWith(u8, r, control.ERROR_PREFIX)) EXIT_REFUSED else EXIT_OK;
}

// ── show · get ────────────────────────────────────────────────────────

fn show() u8 {
    var mounts_buf: [8192]u8 = undefined;
    var text_buf: [READ_MAX]u8 = undefined;
    const cur = current(&mounts_buf, &text_buf) orelse return EXIT_IO;
    if (cur.disk) |disk| {
        if (cur.exists) {
            say("# {s} on {s}, as init reads it at boot\n", .{ CONF_PATH, disk });
        } else {
            say("# {s} on {s} does not exist yet; init writes it at the next boot\n", .{ CONF_PATH, disk });
        }
    } else {
        say("# no config disk: init uses the defaults and nothing here outlives a power off\n", .{});
    }
    say("# a line starting with # is a default; the file does not set it\n", .{});

    edit.heard = .{};
    const c = parsed(cur.text);
    const complaints = edit.heard.count;
    // TC-M2. init이 지금 쓰는 값(reload design 결정 1). 파일과 다른 키는 그 줄 밑에 주석 한 줄로
    // 적는다 — 같은 줄 끝에 적으면 이 출력이 더는 그대로 쓸 수 있는 tars.conf가 아니다(TC 결정 8).
    var now_buf: [control.REPLY_MAX]u8 = undefined;
    const now = askInit(.config, &now_buf, ASK_MS);
    var line_buf: [edit.LINE_MAX]u8 = undefined;
    for (edit.KEYS) |key| {
        var vbuf: [edit.VALUE_MAX]u8 = undefined;
        const value = edit.valueText(&c, key, &vbuf).?;
        const mark = if (edit.setByFile(&line_buf, cur.text[0..@min(cur.text.len, config.MAX_FILE)], key)) "" else "#";
        say("{s}{s}={s}\n", .{ mark, key, value });
        if (now) |r| if (nowValue(r, key)) |v| if (!std.mem.eql(u8, v, value))
            say("#   init uses {s}={s} now; tars-config reload applies the line above\n", .{ key, v });
    }
    if (now) |r| if (screenLine(r)) |sl|
        say("# the screen keeps{s} until the next boot\n", .{sl});
    if (now == null and cur.disk != null) say("# init did not answer at {s}; only the file is shown\n", .{control.PATH});

    if (complaints > 0) say("# init complains about {d} line(s) of this file; tars-config check lists them\n", .{complaints});
    var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
    if (bootRefuses(&c, &path_buf)) |path| say("# {s} is not a zoneinfo file; init falls back to UTC\n", .{path});
    edit.heard = .{};
    if (config.cmdlineNoConfig(config.CMDLINE_PATH))
        say("# {s} is on the kernel command line: this boot's shells read no rc\n", .{config.NO_CONFIG_TOKEN});
    if (cur.disk != null) say("# change: tars-config set KEY=VALUE, then tars-config reload (or reboot)\n", .{});
    return EXIT_OK;
}

fn get(key: []const u8) u8 {
    if (!edit.isKey(key)) return unknownKey(key);
    var mounts_buf: [8192]u8 = undefined;
    var text_buf: [READ_MAX]u8 = undefined;
    const cur = current(&mounts_buf, &text_buf) orelse return EXIT_IO;
    edit.heard = .{};
    const c = parsed(cur.text);
    var vbuf: [edit.VALUE_MAX]u8 = undefined;
    say("{s}\n", .{edit.valueText(&c, key, &vbuf).?});
    return EXIT_OK;
}

fn unknownKey(key: []const u8) u8 {
    complain("unknown key '{s}'; tars-config help lists the keys", .{key});
    return EXIT_USAGE;
}

// ── set · reset ───────────────────────────────────────────────────────

/// set과 reset이 함께 쓰는 길. pairs의 값은 사람이 준 글자다.
fn change(pairs: []const edit.Pair) u8 {
    var mounts_buf: [8192]u8 = undefined;
    if (configDisk(&mounts_buf) == null) {
        complain("no config disk is mounted at /config; a change there would be gone at the next boot", .{});
        complain("attach an ext2 disk labelled tars-* (docs/guides/running-tars.md)", .{});
        return EXIT_IO;
    }

    // 1. 전부 먼저 듣는다. 하나라도 거절이면 아무것도 안 쓴다.
    var canon_bufs: [PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;
    var canon: [PAIRS_MAX][]const u8 = undefined;
    var line_buf: [edit.LINE_MAX]u8 = undefined;
    var refused = false;
    for (pairs, 0..) |p, i| {
        switch (edit.judge(&line_buf, p.key, p.value)) {
            .ok => |c| {
                canon[i] = edit.valueText(&c, p.key, &canon_bufs[i]).?;
                var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
                if (bootRefuses(&c, &path_buf)) |path| {
                    complain("{s}={s}: {s} is not a zoneinfo file; init would fall back to UTC", .{ p.key, p.value, path });
                    refused = true;
                }
            },
            .unknown_key => {
                complain("unknown key '{s}'; tars-config help lists the keys", .{p.key});
                refused = true;
            },
            .control_byte => {
                complain("{s}: a control character cannot go into a config line", .{p.key});
                refused = true;
            },
            .too_long => {
                complain("{s}: the value is too long", .{p.key});
                refused = true;
            },
            .refused => |said| {
                complain("{s}={s}: init would say \"{s}\"", .{ p.key, p.value, said });
                complain("{s} takes {s}", .{ p.key, edit.hint(p.key).? });
                refused = true;
            },
        }
    }
    if (refused) {
        complain("nothing was written", .{});
        return EXIT_REFUSED;
    }

    // 2. 지금의 파일. 없으면 init이 첫 부팅에 쓸 seed를 먼저 짓고 거기에 고친다 —
    //    한 줄짜리 파일을 만들면 사람이 seed의 주석을 영영 못 받는다.
    var text_buf: [READ_MAX]u8 = undefined;
    var text: []const u8 = switch (readFile(CONF_PATH, &text_buf)) {
        .bytes => |b| b,
        .failed => |e| {
            complain("cannot read {s} (errno {d})", .{ CONF_PATH, @intFromEnum(e) });
            return EXIT_IO;
        },
        .missing => seed: {
            edit.heard = .{};
            config.save(TEMP_PATH, .{}) catch {
                complain("cannot write {s}: {s}", .{ TEMP_PATH, edit.heard.first() });
                return EXIT_IO;
            };
            break :seed switch (readFile(TEMP_PATH, &text_buf)) {
                .bytes => |b| b,
                else => {
                    complain("cannot read back {s}", .{TEMP_PATH});
                    return EXIT_IO;
                },
            };
        },
    };
    if (text.len > config.MAX_FILE) {
        complain("{s} is longer than the {d} bytes init reads; shorten it first", .{ CONF_PATH, config.MAX_FILE });
        return EXIT_REFUSED;
    }
    const before = text;

    // 3. 쌍마다 그 키의 줄 하나를 바꾼다. 버퍼 둘을 번갈아 쓴다.
    var work: [2][READ_MAX]u8 = undefined;
    var olds: [PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;
    var old_text: [PAIRS_MAX][]const u8 = undefined;
    var old_default: [PAIRS_MAX]bool = undefined;
    for (pairs, 0..) |p, i| {
        edit.heard = .{};
        const was = parsed(text);
        old_text[i] = edit.valueText(&was, p.key, &olds[i]).?;
        old_default[i] = !edit.setByFile(&line_buf, text, p.key);
        text = edit.setLine(&work[i % 2], text, p.key, canon[i]) orelse {
            complain("{s} would grow past {d} bytes", .{ CONF_PATH, READ_MAX });
            return EXIT_REFUSED;
        };
    }
    if (text.len > config.MAX_FILE) {
        complain("{s} would be longer than the {d} bytes init reads; nothing was written", .{ CONF_PATH, config.MAX_FILE });
        return EXIT_REFUSED;
    }

    // 4. 쓴다. 같으면 안 쓴다.
    if (!std.mem.eql(u8, text, before) or !fileExists(CONF_PATH)) {
        if (!writeFile(TEMP_PATH, text)) return EXIT_IO;
        if (failed(linux.rename(TEMP_PATH, CONF_PATH))) |e| {
            complain("cannot rename {s} to {s} (errno {d})", .{ TEMP_PATH, CONF_PATH, @intFromEnum(e) });
            return EXIT_IO;
        }
    }
    for (pairs, 0..) |p, i| {
        if (std.mem.eql(u8, old_text[i], canon[i])) {
            say("{s}: {s} (unchanged)\n", .{ p.key, canon[i] });
        } else {
            say("{s}: {s}{s} -> {s}\n", .{ p.key, old_text[i], if (old_default[i]) " (default)" else "", canon[i] });
        }
    }
    say("apply it now: tars-config reload (the screen's keys wait for the next boot)\n", .{});
    return EXIT_OK;
}

fn fileExists(path: [:0]const u8) bool {
    return failed(linux.access(path.ptr, linux.F_OK)) == null;
}

fn writeFile(path: [:0]const u8, text: []const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ path, @intFromEnum(e) });
        return false;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    if (!writeAll(fd, text)) {
        complain("cannot write {s}", .{path});
        return false;
    }
    return true;
}

// ── check ─────────────────────────────────────────────────────────────

fn check() u8 {
    var mounts_buf: [8192]u8 = undefined;
    var text_buf: [READ_MAX]u8 = undefined;
    const cur = current(&mounts_buf, &text_buf) orelse return EXIT_IO;
    if (cur.disk == null) {
        say("no config disk: init uses the defaults and reads no file\n", .{});
        return EXIT_OK;
    }
    if (!cur.exists) {
        say("{s} does not exist yet; init writes it at the next boot\n", .{CONF_PATH});
        return EXIT_OK;
    }
    var problems: usize = 0;
    const text = cur.text;
    if (text.len > config.MAX_FILE) {
        say("{s} is {d} bytes or more; init reads only the first {d}\n", .{ CONF_PATH, text.len, config.MAX_FILE });
        problems += 1;
    }

    // 줄마다 init의 파서에 따로 넣는다. 줄 사이에 상태가 없는 파서라(마지막 줄이
    // 이긴다는 것뿐이다) 한 줄씩 들어도 init이 파일째로 읽을 때와 같은 말을 한다.
    var it = edit.Lines{ .text = text };
    while (it.next()) |span| {
        if (span.start >= config.MAX_FILE) break;
        const raw = text[span.start..span.end];
        if (edit.classify(raw) == .skip) continue;
        edit.heard = .{};
        _ = config.parse(raw);
        if (edit.heard.count == 0) continue;
        say("line {d}: {s}\n", .{ span.number, edit.heard.first() });
        problems += 1;
    }

    // 같은 키가 둘 이상이면 알린다. 틀린 것은 아니다 — 마지막 줄이 이긴다.
    for (edit.KEYS) |key| {
        var numbers: [8]usize = undefined;
        const n = edit.lineNumbers(text, key, &numbers);
        if (n < 2) continue;
        say("{s} is on {d} lines (", .{ key, n });
        for (numbers[0..@min(n, numbers.len)], 0..) |num, i| say("{s}{d}", .{ if (i == 0) "" else ", ", num });
        say("); the last one wins\n", .{});
    }

    edit.heard = .{};
    const c = parsed(text);
    var path_buf: [config.ZONEINFO_PATH_MAX]u8 = undefined;
    if (bootRefuses(&c, &path_buf)) |path| {
        say("timezone {s}: {s} is not a zoneinfo file; init falls back to UTC\n", .{ c.timezone.slice(), path });
        problems += 1;
    }

    // 앞문 넷의 파일(TC-M1 결정 16). 남의 문법은 안 읽고 있는지 · 모드 · tars.conf와 맞는지만.
    problems += front.check(c);

    // 옛 seed의 별칭(결정 6). 이 명령을 가리므로 문제로 센다. 지우지는 않는다.
    var rc_buf: [65536]u8 = undefined;
    for (std.enums.values(config.Shell)) |sh| {
        const rc = switch (readFile(sh.rcPath(), &rc_buf)) {
            .bytes => |b| b,
            else => continue,
        };
        const number = edit.staleAlias(rc) orelse continue;
        say("{s} line {d}: alias tars-config hides this command in {s}; delete that line\n", .{ sh.rcPath(), number, @tagName(sh) });
        problems += 1;
    }

    if (problems == 0) {
        say("{s}: init reads every line without a complaint\n", .{CONF_PATH});
        return EXIT_OK;
    }
    say("{d} problem(s)\n", .{problems});
    return EXIT_REFUSED;
}

// ── main ──────────────────────────────────────────────────────────────

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len < 2) return show();
    const verb = std.mem.span(argv[1]);
    const rest = argv[2..];

    if (std.mem.eql(u8, verb, "help") or std.mem.eql(u8, verb, "-h") or std.mem.eql(u8, verb, "--help")) {
        if (rest.len != 0) return usage();
        return help();
    }
    if (std.mem.eql(u8, verb, "list")) {
        if (rest.len != 0) return usage();
        return list();
    }
    // "언세팅"은 reset이다. unset이라는 이름은 받지 않는다 — 그 낱말은 "줄을 지운다"로
    // 읽히는데 reset은 줄을 지우지 않고 기본값을 적는다(design 결정 1의 덧붙임).
    // 친 사람이 길을 잃지 않게 그 차이를 말하고 쓰는 법으로 끝낸다.
    if (std.mem.eql(u8, verb, "unset")) {
        complain("there is no unset; reset KEY writes the default value into that key's line (the line stays)", .{});
        return usage();
    }
    if (std.mem.eql(u8, verb, "reload")) {
        if (rest.len != 0) return usage();
        return reloadInit();
    }
    if (std.mem.eql(u8, verb, "check")) {
        if (rest.len != 0) return usage();
        return check();
    }
    // 앞문 넷(TC-M1). 인자는 각자 가른다.
    if (std.mem.eql(u8, verb, "wifi")) return front.wifi(rest);
    if (std.mem.eql(u8, verb, "ssh")) return front.ssh(rest);
    if (std.mem.eql(u8, verb, "ssh-key")) return front.sshKey(rest);
    if (std.mem.eql(u8, verb, "firewall")) return front.firewall(rest);
    if (std.mem.eql(u8, verb, "dictation")) return front.dictation(rest);
    if (std.mem.eql(u8, verb, "get")) {
        if (rest.len != 1) return usage();
        return get(std.mem.trim(u8, std.mem.span(rest[0]), " \t"));
    }
    const is_set = std.mem.eql(u8, verb, "set");
    if (!is_set and !std.mem.eql(u8, verb, "reset")) return usage();
    if (rest.len == 0 or rest.len > PAIRS_MAX) return usage();

    var pairs: [PAIRS_MAX]edit.Pair = undefined;
    var default_bufs: [PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;
    const defaults = config.Config{};
    for (rest, 0..) |arg_z, i| {
        const arg = std.mem.span(arg_z);
        if (is_set) {
            // 설정 파일의 한 줄과 같은 규칙으로 가른다 — 첫 `=`, 양쪽 공백.
            const eq = std.mem.indexOfScalar(u8, arg, '=') orelse {
                complain("'{s}' has no '='; set takes KEY=VALUE", .{arg});
                return EXIT_USAGE;
            };
            pairs[i] = .{
                .key = std.mem.trim(u8, arg[0..eq], " \t"),
                .value = std.mem.trim(u8, arg[eq + 1 ..], " \t"),
            };
        } else {
            const key = std.mem.trim(u8, arg, " \t");
            const value = edit.valueText(&defaults, key, &default_bufs[i]) orelse return unknownKey(key);
            pairs[i] = .{ .key = key, .value = value };
        }
    }
    return change(pairs[0..rest.len]);
}
