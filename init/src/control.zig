//! CT-M1. 사람의 명령이 PID 1까지 오는 세 번째 입력 — Unix 소켓 하나.
//!
//! PID 1이 바깥에서 받는 입력은 시그널 둘과 전원 버튼 fd였다(CT design 확인 3). 이
//! 파일은 셋째 입력의 양 끝을 든다 — `main.zig`의 감독 루프가 쓰는 listen 쪽(`open` ·
//! `receive` · `reply`)과 `tars-service`가 쓰는 connect 쪽(`dial` · `awaitReply`).
//!
//! 감독 규칙(무엇을 띄우고 무엇을 두는가)도 여기 있다. 규칙은 `Child`를 모르고 필드
//! 이름(`pid` · `given_up` · `fast_restarts` · `hold` · `kill_at`)으로만 만진다 —
//! `anytype`이라 호스트 검사가 가짜 구조체로 전부 본다(`control_test.zig`). 시그널을
//! 보내는 것은 규칙이 아니라 `main.zig`다. 규칙은 "보내라"를 돌려줄 뿐이다.
const std = @import("std");
const linux = std.os.linux;
const services = @import("services.zig");

pub const DIR: [:0]const u8 = "/run/tars";
pub const PATH: [:0]const u8 = "/run/tars/init.sock";

/// 요청 한 개의 상한(design 결정 3). 가장 긴 옳은 요청이 "restart " + 32 = 40이다.
pub const REQUEST_MAX: usize = 64;
/// 답 한 개의 상한. status 한 벌이 줄 열 개 × 70바이트 안팎이고, SEQPACKET은 1000바이트
/// 답을 `recv` 한 번에 보냈다(CT-M0 실측 2).
pub const REPLY_MAX: usize = 2048;
/// 붙은 상대가 요청을 보낼 때까지 PID 1이 기다리는 시간. 이것이 PID 1이 한 연결에
/// 붙잡히는 상한이다(결정 3, 실측 2).
pub const WAIT_MS: i32 = 200;
/// SIGTERM 뒤 SIGKILL까지의 유예. `power.zig`의 종료 유예와 같은 값이다.
pub const GRACE_SECONDS: isize = 3;

pub const ERROR_PREFIX = "error: ";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

// ── 요청 ───────────────────────────────────────────────────────────

pub const Verb = enum { status, stop, start, restart };

pub const Request = struct {
    verb: Verb,
    /// 서비스 이름. `status`만 null일 수 있다. 요청 버퍼 안을 가리킨다.
    name: ?[]const u8,
};

/// 이름은 services.d의 파일 이름이라 무엇이든 될 수 있지만, 요청으로 오는 이름은
/// 공백과 제어 문자를 받지 않는다 — 공백은 낱말을 가르고, 제어 문자는 PID 1이 그 이름을
/// 로그와 답에 되돌려 찍을 때 터미널을 조종한다(DI-M1 실측 15와 같은 까닭).
fn nameOk(name: []const u8) bool {
    if (name.len == 0 or name.len > services.NAME_MAX) return false;
    for (name) |b| if (b <= 0x20 or b == 0x7f) return false;
    return true;
}

/// "동사" 또는 "동사 이름". 공백 하나로만 가르고 줄 끝 문자도 받지 않는다 — 요청을
/// 짓는 것은 `formatRequest` 하나라서 그 모양 밖의 것은 전부 거절이다.
pub fn parseRequest(bytes: []const u8) ?Request {
    var it = std.mem.splitScalar(u8, bytes, ' ');
    const word = it.next() orelse return null;
    const verb = std.meta.stringToEnum(Verb, word) orelse return null;
    const name = it.next();
    if (it.next() != null) return null;
    if (name) |n| {
        if (!nameOk(n)) return null;
    } else if (verb != .status) return null;
    return .{ .verb = verb, .name = name };
}

pub fn formatRequest(buf: []u8, verb: Verb, name: ?[]const u8) ?[]const u8 {
    const text = if (name) |n|
        std.fmt.bufPrint(buf, "{s} {s}", .{ @tagName(verb), n })
    else
        std.fmt.bufPrint(buf, "{s}", .{@tagName(verb)});
    return text catch null;
}

// ── 감독 규칙 ───────────────────────────────────────────────────────

/// 사람이 요청한 것. `none`이 SV의 감독 그대로다.
pub const Hold = enum { none, stop, restart };

pub const State = enum {
    running,
    stopping,
    restarting,
    stopped,
    given_up,
    starting,

    pub fn word(self: State) []const u8 {
        return switch (self) {
            .given_up => "given up",
            else => @tagName(self),
        };
    }
};

/// status 한 줄의 상태. 살아 있으면 `hold`가, 죽어 있으면 그 뒤의 뜻이 가른다.
/// `starting`은 죽었고 다시 뜰 차례라는 뜻이다(재시작 1초 사이 · start 직후).
pub fn stateOf(c: anytype) State {
    if (c.pid >= 0) return switch (c.hold) {
        .none => .running,
        .stop => .stopping,
        .restart => .restarting,
    };
    if (c.hold == .stop) return .stopped;
    if (c.given_up) return .given_up;
    return .starting;
}

/// 감독 루프 머리의 띄우는 조건(design 결정 4 규칙 1).
pub fn wantsRunning(c: anytype) bool {
    return c.pid < 0 and !c.given_up and c.hold != .stop;
}

pub const Outcome = enum { stopping, stopped, already_stopped, starting, already_running, restarting };

pub const Applied = struct {
    outcome: Outcome,
    /// true면 `main.zig`가 지금 그룹에 SIGTERM을 보낸다.
    signal: bool,
};

fn revive(c: anytype) void {
    c.hold = .none;
    c.given_up = false;
    c.fast_restarts = 0;
}

/// 사람의 요청 하나를 칸에 반영한다. SIGTERM은 한 죽음에 한 번만 보낸다 — 이미 보낸
/// 뒤(`hold`가 `none`이 아니고 살아 있다)에 온 요청은 뜻만 바꾼다. 시한도 그때 한 번
/// 정해진다.
pub fn apply(verb: Verb, c: anytype, now: isize) Applied {
    switch (verb) {
        .status => unreachable,
        .stop => {
            if (c.pid < 0) {
                const was = c.hold == .stop;
                c.hold = .stop;
                return .{ .outcome = if (was) .already_stopped else .stopped, .signal = false };
            }
            const sent = c.hold != .none;
            c.hold = .stop;
            if (!sent) c.kill_at = now + GRACE_SECONDS;
            return .{ .outcome = .stopping, .signal = !sent };
        },
        .start => {
            if (c.pid >= 0) {
                if (c.hold == .none) return .{ .outcome = .already_running, .signal = false };
                // 죽어 가는 중이다. 거두고 나서 다시 띄우게 뜻만 바꾼다.
                c.hold = .restart;
                c.fast_restarts = 0;
                return .{ .outcome = .starting, .signal = false };
            }
            revive(c);
            return .{ .outcome = .starting, .signal = false };
        },
        .restart => {
            if (c.pid < 0) {
                revive(c);
                return .{ .outcome = .starting, .signal = false };
            }
            const sent = c.hold != .none;
            c.hold = .restart;
            c.fast_restarts = 0;
            if (!sent) c.kill_at = now + GRACE_SECONDS;
            return .{ .outcome = .restarting, .signal = !sent };
        },
    }
}

pub const Reaped = enum { normal, stays_stopped, restarts };

/// 감독 루프가 자식을 거두고 `pid = -1`로 둔 직후에 부른다. 사람이 요청한 죽음이면
/// 빨리 죽음으로 세지 않는다(design 결정 4 규칙 2) — 세면 `restart` 셋에 포기된다
/// (CT-M0 실측 6).
pub fn reaped(c: anytype) Reaped {
    c.kill_at = 0;
    return switch (c.hold) {
        .none => .normal,
        .stop => .stays_stopped,
        .restart => blk: {
            c.hold = .none;
            break :blk .restarts;
        },
    };
}

/// SIGTERM의 유예가 지났는가. true를 한 번만 돌려준다 — 시한을 지우므로 SIGKILL도
/// 한 죽음에 한 번이다.
pub fn overdue(c: anytype, now: isize) bool {
    if (c.pid < 0 or c.kill_at == 0 or now < c.kill_at) return false;
    c.kill_at = 0;
    return true;
}

/// 클라이언트가 기다리는 끝(design 결정 6). restart는 옛 pid와 다른 pid로 돌아야 끝이다.
pub fn reached(verb: Verb, seen: Seen, old_pid: linux.pid_t) bool {
    return switch (verb) {
        .status => true,
        .stop => seen.state == .stopped,
        .start => seen.state == .running,
        .restart => seen.state == .running and seen.pid != old_pid,
    };
}

// ── 답의 글자 ───────────────────────────────────────────────────────

/// 고정 버퍼에 이어 쓴다. 넘치면 멈추고 `full`을 세운다 — PID 1이 답을 짓다가 죽는
/// 길을 두지 않는다.
pub const Out = struct {
    buf: []u8,
    len: usize = 0,
    full: bool = false,

    pub fn print(self: *Out, comptime fmt: []const u8, args: anytype) void {
        if (self.full) return;
        const s = std.fmt.bufPrint(self.buf[self.len..], fmt, args) catch {
            self.full = true;
            return;
        };
        self.len += s.len;
    }

    pub fn bytes(self: *const Out) []const u8 {
        return self.buf[0..self.len];
    }
};

const LABEL_COLUMN: usize = 16;
const STATE_COLUMN: usize = 10;

/// 칸을 맞춘다. 이미 넘었으면 공백 하나 — 라벨과 상태가 붙어 버리면 `parseRow`가 못 읽는다.
fn pad(out: *Out, used: usize, column: usize) void {
    var n: usize = if (used < column) column - used else 1;
    while (n > 0) : (n -= 1) out.print(" ", .{});
}

/// status의 한 줄. 살아 있을 때만 pid와 산 시간이 붙는다.
pub fn row(out: *Out, label: []const u8, state: State, pid: linux.pid_t, up: isize) void {
    out.print("{s}", .{label});
    pad(out, label.len, LABEL_COLUMN);
    const w = state.word();
    out.print("{s}", .{w});
    if (pid >= 0) {
        pad(out, w.len, STATE_COLUMN);
        out.print("pid {d}   up {d}s", .{ pid, up });
    }
    out.print("\n", .{});
}

pub fn outcome(out: *Out, o: Outcome, label: []const u8, pid: linux.pid_t) void {
    switch (o) {
        .stopping => out.print("stopping {s} (pid {d})\n", .{ label, pid }),
        .stopped => out.print("stopped {s}\n", .{label}),
        .already_stopped => out.print("{s} is already stopped\n", .{label}),
        .starting => out.print("starting {s}\n", .{label}),
        .already_running => out.print("{s} is already running (pid {d})\n", .{ label, pid }),
        .restarting => out.print("restarting {s} (pid {d})\n", .{ label, pid }),
    }
}

pub const Seen = struct { state: State, pid: linux.pid_t };

/// `row`가 쓴 줄에서 상태와 pid를 읽는다. 라벨 바로 뒤가 공백이어야 한다 — 그래야
/// `service sshd2`가 `service sshd`로 읽히지 않는다.
pub fn parseRow(line: []const u8, label: []const u8) ?Seen {
    if (!std.mem.startsWith(u8, line, label)) return null;
    const after = line[label.len..];
    if (after.len == 0 or after[0] != ' ') return null;
    const rest = std.mem.trimStart(u8, after, " ");
    const states = [_]State{ .given_up, .running, .stopping, .restarting, .stopped, .starting };
    for (states) |s| {
        const w = s.word();
        if (!std.mem.startsWith(u8, rest, w)) continue;
        var tail = std.mem.trimStart(u8, rest[w.len..], " ");
        var pid: linux.pid_t = -1;
        if (std.mem.startsWith(u8, tail, "pid ")) {
            tail = tail["pid ".len..];
            const end = std.mem.indexOfAny(u8, tail, " \n") orelse tail.len;
            pid = std.fmt.parseInt(linux.pid_t, tail[0..end], 10) catch return null;
        }
        return .{ .state = s, .pid = pid };
    }
    return null;
}

// ── 소켓 ───────────────────────────────────────────────────────────

const ALEN: linux.socklen_t = @sizeOf(linux.sockaddr.un);

fn addrOf(path: []const u8) ?linux.sockaddr.un {
    var a: linux.sockaddr.un = .{ .path = [_]u8{0} ** 108 };
    if (path.len >= a.path.len) return null;
    @memcpy(a.path[0..path.len], path);
    return a;
}

fn noSocket(step: []const u8, e: linux.E) ?i32 {
    std.debug.print("tars-init: no control socket ({s} errno {d})\n", .{ step, @intFromEnum(e) });
    return null;
}

fn closeAnd(fd: i32, step: []const u8, e: linux.E) ?i32 {
    _ = linux.close(fd);
    return noSocket(step, e);
}

/// PID 1 쪽. 소켓을 세우고 listen fd를 돌려준다. 무엇이 실패해도 null로 돌아온다 —
/// 통로가 없는 것은 CT 전의 상태 그대로다(feedback_boot_never_blocks).
///
/// NONBLOCK은 `receive`의 accept가 "없다"를 EAGAIN으로 답하게 하고, CLOEXEC는 이 fd가
/// 서비스와 콘솔 셸로 새지 않게 한다(위험 2, CT-M0 실측 2 · 7).
pub fn open(dir: [:0]const u8, path: [:0]const u8) ?i32 {
    if (failed(linux.mkdir(dir.ptr, 0o755))) |e| if (e != .EXIST) return noSocket("mkdir", e);
    _ = linux.unlink(path.ptr);
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return noSocket("socket", e);
    const fd: i32 = @intCast(rc);
    const a = addrOf(path) orelse return closeAnd(fd, "path", .NAMETOOLONG);
    if (failed(linux.bind(fd, @ptrCast(&a), ALEN))) |e| return closeAnd(fd, "bind", e);
    if (failed(linux.chmod(path.ptr, 0o600))) |e| return closeAnd(fd, "chmod", e);
    if (failed(linux.listen(fd, 4))) |e| return closeAnd(fd, "listen", e);
    std.debug.print("tars-init: control socket {s}\n", .{path});
    return fd;
}

pub const Received = struct {
    /// 받은 연결. 부른 쪽이 `reply`로 닫는다.
    fd: i32,
    what: union(enum) {
        /// WAIT_MS 안에 아무것도 안 왔다.
        silent,
        /// REQUEST_MAX를 넘었다. 값은 원래 길이다(MSG_TRUNC, 실측 2).
        too_long: usize,
        request: []const u8,
    },
};

/// PID 1 쪽. listen fd가 읽을 수 있다고 깨웠을 때 부른다. 연결 하나를 받아 요청 하나를
/// 읽는다. null이면 받을 연결이 없었다.
pub fn receive(lfd: i32, buf: *[REQUEST_MAX]u8) ?Received {
    const rc = linux.accept4(lfd, null, null, linux.SOCK.CLOEXEC);
    if (failed(rc)) |_| return null;
    const fd: i32 = @intCast(rc);
    var p = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const ready = linux.poll(&p, 1, WAIT_MS);
    if (failed(ready) != null or ready == 0) return .{ .fd = fd, .what = .silent };
    const n = linux.recvfrom(fd, buf, buf.len, linux.MSG.TRUNC | linux.MSG.DONTWAIT, null, null);
    if (failed(n) != null) return .{ .fd = fd, .what = .silent };
    if (n > buf.len) return .{ .fd = fd, .what = .{ .too_long = n } };
    return .{ .fd = fd, .what = .{ .request = buf[0..n] } };
}

/// 답을 보내고 연결을 닫는다. 상대가 이미 닫았으면 EPIPE이고 그것으로 끝이다 —
/// MSG_NOSIGNAL이라 SIGPIPE는 없다(실측 2).
pub fn reply(fd: i32, bytes: []const u8) void {
    _ = linux.sendto(fd, bytes.ptr, bytes.len, linux.MSG.NOSIGNAL | linux.MSG.DONTWAIT, null, 0);
    _ = linux.close(fd);
}

pub const Dialed = union(enum) { fd: i32, failed: linux.E };

/// `tars-service` 쪽. 붙어서 요청을 보낸다. 답은 `awaitReply`가 읽는다 — 둘을 가른
/// 것은 호스트 검사가 한 스레드에서 양 끝을 다 돌리기 위해서다. 받는 쪽이 없으면
/// ECONNREFUSED(소켓 파일만 남았다)나 ENOENT(파일도 없다)다(실측 2).
pub fn dial(path: [:0]const u8, request: []const u8) Dialed {
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return .{ .failed = e };
    const fd: i32 = @intCast(rc);
    const a = addrOf(path) orelse {
        _ = linux.close(fd);
        return .{ .failed = .NAMETOOLONG };
    };
    if (failed(linux.connect(fd, &a, ALEN))) |e| {
        _ = linux.close(fd);
        return .{ .failed = e };
    }
    if (failed(linux.sendto(fd, request.ptr, request.len, linux.MSG.NOSIGNAL, null, 0))) |e| {
        _ = linux.close(fd);
        return .{ .failed = e };
    }
    return .{ .fd = fd };
}

/// 답 하나를 읽고 닫는다. `ms` 안에 안 오면 null. 빈 답(PID 1이 답 없이 닫았다)은 빈
/// 슬라이스다.
pub fn awaitReply(fd: i32, buf: []u8, ms: i32) ?[]const u8 {
    defer _ = linux.close(fd);
    var p = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const ready = linux.poll(&p, 1, ms);
    if (failed(ready) != null or ready == 0) return null;
    const n = linux.recvfrom(fd, buf.ptr, buf.len, 0, null, null);
    if (failed(n) != null) return null;
    return buf[0..n];
}
