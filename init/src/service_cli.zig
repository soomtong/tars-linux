//! CT-M1. `tars-service` — 사람이 서비스를 보고 멈추고 띄우는 명령.
//!
//! PID 1에게 요청 하나를 보내고 답을 찍는다. 기다림은 이쪽이 진다(design 결정 6) —
//! PID 1은 SIGTERM을 보내고 곧바로 답하므로, stop · start · restart는 `status NAME`을
//! 다시 물어 원하는 상태가 될 때까지 본다. 이름은 거르지 않고 보낸다(M1-A) — 거르는
//! 것은 PID 1 한 곳이다.
//!
//! TP-M11. `enable|disable NAME`은 PID 1의 동사가 아니다 — 이쪽이 `/config/services.d/NAME` 링크를 만들거나
//! 지우고 `reload`를 보낸다(plan 결정 C). 무엇을 할지는 `service_link.zig`가 정한다.
const std = @import("std");
const linux = std.os.linux;
const control = @import("control.zig");
const services = @import("services.zig");
const link = @import("service_link.zig");

const EXIT_OK: u8 = 0;
/// PID 1이 `error: `로 답했다.
const EXIT_REFUSED: u8 = 1;
/// 소켓이 없거나 PID 1이 답하지 않았다.
const EXIT_UNREACHABLE: u8 = 2;
/// 원하는 상태가 시한 안에 안 됐다.
const EXIT_TIMEOUT: u8 = 3;
const EXIT_USAGE: u8 = 64;
/// TP-M11. 링크를 만들거나 지우지 못했다(`tars-config`의 EXIT_IO와 같은 값).
const EXIT_IO: u8 = 2;
/// HP-M2. 소켓이 root 0600이라 사용자가 닿지 못했다(sysexits의 `EX_NOPERM`, `tars-config`와 같은 값).
const EXIT_DENIED: u8 = 77;

const REPLY_WAIT_MS: i32 = 2000;
/// `reload`의 답. `tars-config reload`와 같다 — init이 nft 한 번과 services.d를 지나 답한다.
const RELOAD_WAIT_MS: i32 = 10000;
/// 기다림의 시한(M1-B). SIGTERM을 무시하는 서비스가 최악 5초에 거둬진다.
const SETTLE_MS: u64 = 8000;
const SETTLE_STEP_MS: u64 = 200;

fn writeAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (linux.errno(n) != .SUCCESS) {
            if (linux.errno(n) == .INTR) continue;
            return;
        }
        off += n;
    }
}

fn complain(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-service: " ++ fmt ++ "\n", args) catch return;
    writeAll(2, text);
}

fn usage() u8 {
    writeAll(2,
        \\usage: tars-service status [NAME]
        \\       tars-service stop|start|restart NAME
        \\       tars-service enable|disable NAME
        \\
    );
    return EXIT_USAGE;
}

fn sleepMs(ms: u64) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

const Asked = union(enum) { reply: []const u8, down: linux.E, silent };

fn ask(request: []const u8, buf: []u8, ms: i32) Asked {
    return switch (control.dial(control.PATH, request)) {
        .failed => |e| .{ .down = e },
        .fd => |fd| if (control.awaitReply(fd, buf, ms)) |r|
            (if (r.len == 0) .silent else .{ .reply = r })
        else
            .silent,
    };
}

/// `status NAME`을 물어 한 줄을 읽는다. 못 읽으면 null.
fn look(name: []const u8, label: []const u8, buf: []u8) ?control.Seen {
    var req_buf: [256]u8 = undefined;
    const req = control.formatRequest(&req_buf, .status, name) orelse return null;
    return switch (ask(req, buf, REPLY_WAIT_MS)) {
        .reply => |r| control.parseRow(r, label),
        else => null,
    };
}

fn settle(verb: control.Verb, name: []const u8, label: []const u8, old_pid: linux.pid_t) u8 {
    var buf: [control.REPLY_MAX]u8 = undefined;
    var waited: u64 = 0;
    while (waited <= SETTLE_MS) : (waited += SETTLE_STEP_MS) {
        if (look(name, label, &buf)) |seen| {
            if (control.reached(verb, seen, old_pid)) {
                var line: [control.REPLY_MAX]u8 = undefined;
                var out = control.Out{ .buf = &line };
                control.row(&out, label, seen.state, seen.pid, 0);
                // 산 시간은 방금 뜬 것이라 0 안팎이다 — 상태와 pid만 보인다.
                writeAll(1, out.bytes()[0 .. std.mem.indexOf(u8, out.bytes(), "   up ") orelse out.len]);
                writeAll(1, "\n");
                return EXIT_OK;
            }
        }
        sleepMs(SETTLE_STEP_MS);
    }
    complain("{s} did not {s} in {d}s", .{ label, @tagName(verb), SETTLE_MS / 1000 });
    return EXIT_TIMEOUT;
}

/// HP-M2 plan 확정 6. 소켓은 root만 연다 — 사용자에게는 다음 걸음을 말한다.
fn denied(argv: []const [*:0]const u8) u8 {
    writeAll(2, "tars-service: permission denied; try: sudo tars-service");
    for (argv[1..]) |a| {
        writeAll(2, " ");
        writeAll(2, std.mem.span(a));
    }
    writeAll(2, "\n");
    return EXIT_DENIED;
}

/// 못 닿았거나 답이 없을 때의 끝. 답이 있으면 null.
fn unreached(asked: Asked, argv: []const [*:0]const u8) ?u8 {
    switch (asked) {
        .down => |e| {
            if (e == .ACCES or e == .PERM) return denied(argv);
            complain("cannot reach init at {s} (errno {d})", .{ control.PATH, @backingInt(e) });
            return EXIT_UNREACHABLE;
        },
        .silent => {
            complain("init did not answer", .{});
            return EXIT_UNREACHABLE;
        },
        .reply => return null,
    }
}

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 링크가 지금 무엇인가. `readlink`의 ENOENT는 없음, EINVAL은 링크가 아닌 무엇.
fn linkNow(path: [:0]const u8, template: []const u8) link.Link {
    var buf: [256]u8 = undefined;
    const rc = linux.readlink(path.ptr, &buf, buf.len);
    if (failed(rc)) |e| return link.classify(null, e != .NOENT, template);
    return link.classify(buf[0..rc], false, template);
}

fn executable(path: [:0]const u8) bool {
    var st: linux.Statx = undefined;
    const rc = linux.statx(linux.AT.FDCWD, path.ptr, 0, .{ .TYPE = true, .MODE = true }, &st);
    return failed(rc) == null and linux.S.ISREG(st.mode) and st.mode & 0o111 != 0;
}

/// 템플릿이 없을 때 있는 것을 보인다. 실행 파일만, 이름 순. `services.discover`는 쓰지 않는다 — 그것은
/// init의 로그 줄(`tars-init: …`)을 찍는다.
fn sayTemplates() void {
    const rc = linux.open(link.TEMPLATE_DIR, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc) != null) return;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var name_bufs: [16][services.NAME_MAX]u8 = undefined;
    var names: [16][]const u8 = undefined;
    var n: usize = 0;
    var buf: [2048]u8 align(8) = undefined;
    while (n < names.len) {
        const got = linux.getdents64(fd, &buf, buf.len);
        if (failed(got) != null or got == 0) break;
        var off: usize = 0;
        while (off < got and n < names.len) {
            const d: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += d.reclen;
            const entry = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&d.name)), 0);
            if (!link.nameOk(entry)) continue;
            var p_buf: [128]u8 = undefined;
            const p = services.joinPath(&p_buf, link.TEMPLATE_DIR, entry) orelse continue;
            if (!executable(p)) continue;
            @memcpy(name_bufs[n][0..entry.len], entry);
            names[n] = name_bufs[n][0..entry.len];
            n += 1;
        }
    }
    services.sortNames(names[0..n]);
    writeAll(2, "tars-service: templates in " ++ link.TEMPLATE_DIR ++ ":");
    for (names[0..n]) |name| {
        writeAll(2, " ");
        writeAll(2, name);
    }
    writeAll(2, "\n");
}

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch return;
    writeAll(1, text);
}

/// TP-M11 `enable|disable NAME`. 링크를 맞추고 reload를 보낸 뒤, 답에 그 서비스가 띄워지거나 멈춘다고 나오면 그 상태까지 기다린다.
fn enableDisable(verb: link.Verb, name: []const u8, argv: []const [*:0]const u8) u8 {
    if (!link.nameOk(name)) {
        complain("{s} is not a service name", .{name});
        return EXIT_USAGE;
    }
    var t_buf: [128]u8 = undefined;
    var l_buf: [128]u8 = undefined;
    const template = services.joinPath(&t_buf, link.TEMPLATE_DIR, name) orelse return usage();
    const path = services.joinPath(&l_buf, services.DIR, name) orelse return usage();

    switch (link.decide(verb, linkNow(path, template))) {
        .foreign => {
            complain("{s} is there and is not a link to {s}; leaving it", .{ path, template });
            return EXIT_REFUSED;
        },
        .already_on => say("{s}: already enabled", .{name}),
        .already_off => say("{s}: already disabled", .{name}),
        .link => {
            if (!executable(template)) {
                complain("no service template {s}", .{template});
                sayTemplates();
                return EXIT_USAGE;
            }
            if (failed(linux.mkdir(services.DIR.ptr, 0o755))) |e| switch (e) {
                .EXIST => {},
                .ACCES, .PERM, .ROFS => return denied(argv),
                else => {
                    complain("cannot make {s} (errno {d})", .{ services.DIR, @backingInt(e) });
                    return EXIT_IO;
                },
            };
            if (failed(linux.symlink(template.ptr, path.ptr))) |e| {
                if (e == .ACCES or e == .PERM) return denied(argv);
                complain("cannot link {s} (errno {d})", .{ path, @backingInt(e) });
                return EXIT_IO;
            }
            say("{s}: enabled, {s} -> {s}", .{ name, path, template });
        },
        .unlink => {
            if (failed(linux.unlink(path.ptr))) |e| {
                if (e == .ACCES or e == .PERM) return denied(argv);
                complain("cannot remove {s} (errno {d})", .{ path, @backingInt(e) });
                return EXIT_IO;
            }
            say("{s}: disabled, removed {s}", .{ name, path });
        },
    }

    // reload의 답은 그대로 찍는다 — tars.conf에 미뤄 둔 변경도 함께 들어간다(같은 동사다).
    var buf: [control.REPLY_MAX]u8 = undefined;
    const asked = ask("reload", &buf, RELOAD_WAIT_MS);
    if (unreached(asked, argv)) |rc| return rc;
    const text = asked.reply;
    writeAll(1, text);
    if (std.mem.startsWith(u8, text, control.ERROR_PREFIX)) return EXIT_REFUSED;

    var label_buf: [64]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, services.LABEL_PREFIX ++ "{s}", .{name}) catch return EXIT_OK;
    return switch (link.said(text, label) orelse return EXIT_OK) {
        .starts => settle(.start, name, label, -1),
        .stops => settle(.stop, name, label, -1),
    };
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len >= 2) {
        if (std.meta.stringToEnum(link.Verb, std.mem.span(argv[1]))) |lv| {
            if (argv.len != 3) return usage();
            return enableDisable(lv, std.mem.span(argv[2]), argv);
        }
    }
    if (argv.len < 2 or argv.len > 3) return usage();
    const verb = std.meta.stringToEnum(control.Verb, std.mem.span(argv[1])) orelse return usage();
    // TC-M2의 둘(config · reload)은 tars-config의 동사다(reload design 결정 1).
    if (verb == .config or verb == .reload) return usage();
    const name: ?[]const u8 = if (argv.len == 3) std.mem.span(argv[2]) else null;
    if (verb != .status and name == null) return usage();

    var req_buf: [256]u8 = undefined;
    const req = control.formatRequest(&req_buf, verb, name) orelse return usage();
    var label_buf: [256]u8 = undefined;
    const label: []const u8 = if (name) |n|
        (std.fmt.bufPrint(&label_buf, "service {s}", .{n}) catch return usage())
    else
        "";

    var buf: [control.REPLY_MAX]u8 = undefined;
    // restart는 옛 pid를 먼저 안다 — 다른 pid로 running이 되는 것이 "다시 떴다"다.
    const old_pid: linux.pid_t = if (verb == .restart)
        (if (look(name.?, label, &buf)) |s| s.pid else -1)
    else
        -1;

    const asked = ask(req, &buf, REPLY_WAIT_MS);
    if (unreached(asked, argv)) |rc| return rc;
    const text = asked.reply;
    writeAll(1, text);
    if (std.mem.startsWith(u8, text, control.ERROR_PREFIX)) return EXIT_REFUSED;
    if (verb == .status) return EXIT_OK;
    return settle(verb, name.?, label, old_pid);
}
