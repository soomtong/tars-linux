const std = @import("std");
const linux = std.os.linux;
const control = @import("control.zig");

/// 이 검사가 쓰는 소켓 자리. 게스트가 아니라 빌드 컨테이너의 /tmp다.
const DIR = "/tmp/tars-control-test";
const PATH = DIR ++ "/init.sock";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

/// `Child`에서 규칙이 만지는 다섯 칸만 든 가짜. 필드 이름이 곧 계약이다.
const Fake = struct {
    pid: linux.pid_t = -1,
    given_up: bool = false,
    fast_restarts: u32 = 0,
    hold: control.Hold = .none,
    kill_at: isize = 0,
};

fn expectParse(bytes: []const u8, verb: ?control.Verb, name: ?[]const u8) !void {
    const got = control.parseRequest(bytes);
    if (verb == null) {
        if (got != null) return fail("parseRequest(\"{s}\") accepted, want rejected", .{bytes});
        return;
    }
    const r = got orelse return fail("parseRequest(\"{s}\") rejected", .{bytes});
    if (r.verb != verb.?) return fail("parseRequest(\"{s}\") verb {s}", .{ bytes, @tagName(r.verb) });
    if ((r.name == null) != (name == null)) return fail("parseRequest(\"{s}\") name presence", .{bytes});
    if (name) |n| if (!std.mem.eql(u8, r.name.?, n)) return fail("parseRequest(\"{s}\") name {s}", .{ bytes, r.name.? });
}

fn expectRow(label: []const u8, state: control.State, pid: linux.pid_t, up: isize, want: []const u8) !void {
    var buf: [256]u8 = undefined;
    var out = control.Out{ .buf = &buf };
    control.row(&out, label, state, pid, up);
    if (!std.mem.eql(u8, out.bytes(), want)) return fail("row gave [{s}], want [{s}]", .{ out.bytes(), want });
    const seen = control.parseRow(out.bytes(), label) orelse return fail("parseRow could not read [{s}]", .{want});
    if (seen.state != state or seen.pid != pid) return fail("parseRow read {s}/{d} from [{s}]", .{ @tagName(seen.state), seen.pid, want });
}

fn expectApplied(got: control.Applied, outcome: control.Outcome, signal: bool) !void {
    if (got.outcome != outcome or got.signal != signal)
        return fail("apply gave {s}/signal={any}, want {s}/signal={any}", .{ @tagName(got.outcome), got.signal, @tagName(outcome), signal });
}

fn expectState(c: *const Fake, want: control.State) !void {
    const got = control.stateOf(c);
    if (got != want) return fail("stateOf gave {s}, want {s}", .{ @tagName(got), @tagName(want) });
}

fn rawConnect() !i32 {
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return fail("socket errno {d}", .{@intFromEnum(e)});
    const fd: i32 = @intCast(rc);
    var a: linux.sockaddr.un = .{ .path = [_]u8{0} ** 108 };
    @memcpy(a.path[0..PATH.len], PATH);
    if (failed(linux.connect(fd, &a, @sizeOf(linux.sockaddr.un)))) |e| return fail("connect errno {d}", .{@intFromEnum(e)});
    return fd;
}

pub fn main() !void {
    // ── 요청의 글자 ─────────────────────────────────────────────────
    try expectParse("status", .status, null);
    try expectParse("status sshd", .status, "sshd");
    try expectParse("stop sshd", .stop, "sshd");
    try expectParse("start web-1.x", .start, "web-1.x");
    try expectParse("restart sshd", .restart, "sshd");
    try expectParse("a" ** 0, null, null);
    try expectParse("stop", null, null);
    try expectParse("fly sshd", null, null);
    try expectParse("stop a b", null, null);
    try expectParse("stop  sshd", null, null);
    try expectParse("stop sshd\n", null, null);
    try expectParse("stop " ++ "n" ** 32, .stop, "n" ** 32);
    try expectParse("stop " ++ "n" ** 33, null, null);
    try expectParse("stop \x1b[2J", null, null);
    var req_buf: [control.REQUEST_MAX]u8 = undefined;
    const req = control.formatRequest(&req_buf, .restart, "sshd") orelse return fail("formatRequest failed", .{});
    try expectParse(req, .restart, "sshd");
    std.debug.print("control_test: requests — four verbs, one name, nothing else\n", .{});

    // ── 답의 글자 ──────────────────────────────────────────────────
    try expectRow("service sshd", .running, 51, 118, "service sshd    running   pid 51   up 118s\n");
    try expectRow("console shell", .running, 46, 120, "console shell   running   pid 46   up 120s\n");
    try expectRow("service broken", .given_up, -1, 0, "service broken  given up\n");
    try expectRow("service web", .stopped, -1, 0, "service web     stopped\n");
    try expectRow("service web", .stopping, 70, 3, "service web     stopping  pid 70   up 3s\n");
    try expectRow("service web", .restarting, 70, 3, "service web     restarting pid 70   up 3s\n");
    try expectRow("service web", .starting, -1, 0, "service web     starting\n");
    const long = "service " ++ "l" ** 32;
    try expectRow(long, .running, 9, 1, long ++ " running   pid 9   up 1s\n");
    if (control.parseRow("service sshd2   running   pid 5   up 1s\n", "service sshd") != null)
        return fail("parseRow matched service sshd2 for service sshd", .{});
    var tiny: [8]u8 = undefined;
    var small = control.Out{ .buf = &tiny };
    control.row(&small, "service sshd", .running, 51, 118);
    if (!small.full) return fail("an 8-byte Out did not report full", .{});
    std.debug.print("control_test: rows — fixed columns, parseRow reads back what row wrote\n", .{});

    // ── 감독 규칙 ──────────────────────────────────────────────────
    const now: isize = 100;
    var c = Fake{ .pid = 51 };
    try expectState(&c, .running);
    try expectApplied(control.apply(.start, &c, now), .already_running, false);
    try expectApplied(control.apply(.stop, &c, now), .stopping, true);
    if (c.hold != .stop or c.kill_at != now + control.GRACE_SECONDS) return fail("stop left hold {s} kill_at {d}", .{ @tagName(c.hold), c.kill_at });
    try expectState(&c, .stopping);
    try expectApplied(control.apply(.stop, &c, now + 1), .stopping, false); // 두 번 보내지 않는다
    if (c.kill_at != now + control.GRACE_SECONDS) return fail("a second stop moved kill_at", .{});
    if (control.overdue(&c, now + control.GRACE_SECONDS - 1)) return fail("overdue before the grace ran out", .{});
    if (!control.overdue(&c, now + control.GRACE_SECONDS)) return fail("not overdue when the grace ran out", .{});
    if (control.overdue(&c, now + control.GRACE_SECONDS + 1)) return fail("overdue twice for one stop", .{});
    c.pid = -1;
    if (control.reaped(&c) != .stays_stopped) return fail("a stopped death did not stay stopped", .{});
    if (control.wantsRunning(&c)) return fail("a stopped service wants to run", .{});
    try expectState(&c, .stopped);
    try expectApplied(control.apply(.stop, &c, now), .already_stopped, false);
    try expectApplied(control.apply(.start, &c, now), .starting, false);
    if (!control.wantsRunning(&c)) return fail("a started service does not want to run", .{});
    std.debug.print("control_test: stop sends SIGTERM once, holds after the reap, start lets go\n", .{});

    c = Fake{ .pid = 60, .fast_restarts = 2 };
    try expectApplied(control.apply(.restart, &c, now), .restarting, true);
    try expectApplied(control.apply(.restart, &c, now), .restarting, false);
    if (c.fast_restarts != 0) return fail("restart kept fast_restarts {d}", .{c.fast_restarts});
    try expectState(&c, .restarting);
    c.pid = -1;
    if (control.reaped(&c) != .restarts) return fail("a restarted death did not restart", .{});
    if (c.hold != .none or c.kill_at != 0) return fail("restart left hold {s} kill_at {d}", .{ @tagName(c.hold), c.kill_at });
    if (!control.wantsRunning(&c)) return fail("a restarted service does not want to run", .{});
    try expectState(&c, .starting);
    std.debug.print("control_test: restart is not a fast death and comes back\n", .{});

    c = Fake{ .given_up = true, .fast_restarts = 3 };
    try expectState(&c, .given_up);
    try expectApplied(control.apply(.start, &c, now), .starting, false);
    if (c.given_up or c.fast_restarts != 0) return fail("start did not clear a given-up service", .{});
    c = Fake{ .given_up = true };
    try expectApplied(control.apply(.restart, &c, now), .starting, false);
    if (c.given_up) return fail("restart did not clear a given-up service", .{});
    c = Fake{ .pid = 70 };
    _ = control.apply(.stop, &c, now);
    try expectApplied(control.apply(.start, &c, now), .starting, false); // 죽어 가는 중이면 뜻만 바꾼다
    c.pid = -1;
    if (control.reaped(&c) != .restarts) return fail("start during a stop did not restart", .{});
    c = Fake{ .pid = 80 };
    if (control.reaped(&c) != .normal) return fail("an unrequested death was not normal", .{});
    std.debug.print("control_test: start revives a given-up service, a plain death is normal\n", .{});

    // ── 클라이언트가 기다리는 끝 ─────────────────────────────────────
    if (!control.reached(.stop, .{ .state = .stopped, .pid = -1 }, 5)) return fail("reached stop", .{});
    if (control.reached(.stop, .{ .state = .stopping, .pid = 5 }, 5)) return fail("reached stop while stopping", .{});
    if (!control.reached(.start, .{ .state = .running, .pid = 6 }, -1)) return fail("reached start", .{});
    if (control.reached(.restart, .{ .state = .running, .pid = 5 }, 5)) return fail("reached restart with the old pid", .{});
    if (!control.reached(.restart, .{ .state = .running, .pid = 6 }, 5)) return fail("reached restart", .{});
    std.debug.print("control_test: the client waits for stopped, running, or running with a new pid\n", .{});

    // ── 소켓 왕복 ─────────────────────────────────────────────────
    const lfd = control.open(DIR, PATH) orelse return fail("open gave no socket", .{});
    var st: linux.Statx = undefined;
    _ = linux.statx(linux.AT.FDCWD, PATH, 0, .{ .TYPE = true, .MODE = true }, &st);
    if (st.mode != 0o140600) return fail("socket mode {o}, want 140600", .{st.mode});

    const d = control.dial(PATH, "stop sshd");
    const cfd = switch (d) {
        .fd => |fd| fd,
        .failed => |e| return fail("dial errno {d}", .{@intFromEnum(e)}),
    };
    var in_buf: [control.REQUEST_MAX]u8 = undefined;
    const got = control.receive(lfd, &in_buf) orelse return fail("receive got nothing", .{});
    switch (got.what) {
        .request => |bytes| if (!std.mem.eql(u8, bytes, "stop sshd")) return fail("receive got [{s}]", .{bytes}),
        else => return fail("receive got {s}", .{@tagName(got.what)}),
    }
    control.reply(got.fd, "stopping service sshd (pid 51)\n");
    var out_buf: [control.REPLY_MAX]u8 = undefined;
    const answer = control.awaitReply(cfd, &out_buf, 1000) orelse return fail("awaitReply got nothing", .{});
    if (!std.mem.eql(u8, answer, "stopping service sshd (pid 51)\n")) return fail("awaitReply got [{s}]", .{answer});

    const big = [_]u8{'x'} ** 100;
    const bfd = switch (control.dial(PATH, &big)) {
        .fd => |fd| fd,
        .failed => |e| return fail("dial big errno {d}", .{@intFromEnum(e)}),
    };
    const g2 = control.receive(lfd, &in_buf) orelse return fail("receive big got nothing", .{});
    switch (g2.what) {
        .too_long => |n| if (n != 100) return fail("too_long {d}, want 100", .{n}),
        else => return fail("a 100-byte request was {s}", .{@tagName(g2.what)}),
    }
    control.reply(g2.fd, "x");
    _ = linux.close(bfd);

    const sfd = try rawConnect();
    const g3 = control.receive(lfd, &in_buf) orelse return fail("receive silent got nothing", .{});
    if (g3.what != .silent) return fail("a silent client was {s}", .{@tagName(g3.what)});
    _ = linux.close(g3.fd);
    _ = linux.close(sfd);
    if (control.receive(lfd, &in_buf) != null) return fail("receive with nobody waiting returned something", .{});

    _ = linux.close(lfd);
    switch (control.dial(PATH, "status")) {
        .failed => |e| if (e != .CONNREFUSED) return fail("dial to a closed listener errno {d}", .{@intFromEnum(e)}),
        .fd => return fail("dial to a closed listener succeeded", .{}),
    }
    _ = linux.unlink(PATH);
    switch (control.dial(PATH, "status")) {
        .failed => |e| if (e != .NOENT) return fail("dial to no socket errno {d}", .{@intFromEnum(e)}),
        .fd => return fail("dial to no socket succeeded", .{}),
    }
    std.debug.print("control_test: socket — 0600, one request each way, 100 bytes too long, silence ends, no listener is refused\n", .{});
}
