//! CT-M1. `tars-service` — 사람이 서비스를 보고 멈추고 띄우는 명령.
//!
//! PID 1에게 요청 하나를 보내고 답을 찍는다. 기다림은 이쪽이 진다(design 결정 6) —
//! PID 1은 SIGTERM을 보내고 곧바로 답하므로, stop · start · restart는 `status NAME`을
//! 다시 물어 원하는 상태가 될 때까지 본다. 이름은 거르지 않고 보낸다(M1-A) — 거르는
//! 것은 PID 1 한 곳이다.
const std = @import("std");
const linux = std.os.linux;
const control = @import("control.zig");

const EXIT_OK: u8 = 0;
/// PID 1이 `error: `로 답했다.
const EXIT_REFUSED: u8 = 1;
/// 소켓이 없거나 PID 1이 답하지 않았다.
const EXIT_UNREACHABLE: u8 = 2;
/// 원하는 상태가 시한 안에 안 됐다.
const EXIT_TIMEOUT: u8 = 3;
const EXIT_USAGE: u8 = 64;

const REPLY_WAIT_MS: i32 = 2000;
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
        \\
    );
    return EXIT_USAGE;
}

fn sleepMs(ms: u64) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

const Asked = union(enum) { reply: []const u8, down: linux.E, silent };

fn ask(request: []const u8, buf: []u8) Asked {
    return switch (control.dial(control.PATH, request)) {
        .failed => |e| .{ .down = e },
        .fd => |fd| if (control.awaitReply(fd, buf, REPLY_WAIT_MS)) |r|
            (if (r.len == 0) .silent else .{ .reply = r })
        else
            .silent,
    };
}

/// `status NAME`을 물어 한 줄을 읽는다. 못 읽으면 null.
fn look(name: []const u8, label: []const u8, buf: []u8) ?control.Seen {
    var req_buf: [256]u8 = undefined;
    const req = control.formatRequest(&req_buf, .status, name) orelse return null;
    return switch (ask(req, buf)) {
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

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
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

    const text = switch (ask(req, &buf)) {
        .down => |e| {
            complain("cannot reach init at {s} (errno {d})", .{ control.PATH, @intFromEnum(e) });
            return EXIT_UNREACHABLE;
        },
        .silent => {
            complain("init did not answer", .{});
            return EXIT_UNREACHABLE;
        },
        .reply => |r| r,
    };
    writeAll(1, text);
    if (std.mem.startsWith(u8, text, control.ERROR_PREFIX)) return EXIT_REFUSED;
    if (verb == .status) return EXIT_OK;
    return settle(verb, name.?, label, old_pid);
}
