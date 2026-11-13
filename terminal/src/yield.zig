//! DY-M0. 화면 양보 — 프로그램이 요청하면 terminal이 DRM master를 내려놓고, 연결이 닫히면
//! 되찾는다(DY design 결정 3 · 5 · 6 · 9).
//!
//! 두 부분이다. `Machine`은 상태 전이 규칙이고 ioctl · send · close를 직접 부르지 않는다 —
//! 부르는 쪽이 넘기는 `ops`(`anytype`)로 한다. 그래서 호스트 검사가 가짜 `ops`로 모든 전이를
//! 본다(`yield_test.zig`, init `control.zig`의 감독 규칙과 같은 수법). 아래 "socket" 절은
//! 시스템 콜이고 게이트(`display/check.sh`)가 본다.
//!
//! `ops`가 가져야 할 것: `dropMaster() !void` · `setMaster() !void`(남이 master면 `error.MasterBusy`) ·
//! `modeset() !void` · `send(fd, proto.Reply) void` · `close(fd) void`.

const std = @import("std");
const logline = @import("logline.zig");
const proto = @import("display_proto");
const linux = std.os.linux;

pub const State = enum {
    /// terminal이 master다. 손님이 붙어 있어도 `yield`를 말하기 전에는 여기다.
    ours,
    /// master를 놓았다. 손님의 연결이 살아 있는 동안이다.
    yielded,
    /// 손님은 갔는데 `SET_MASTER`가 아직 안 된다 — 누군가 아직 master다(확인 4).
    waiting,
};

/// `waiting`에서 다시 해 보는 간격(결정 6).
pub const RETRY_MS: c_int = 1000;

pub const Machine = struct {
    guest_fd: i32 = -1,
    guest_pid: i32 = 0,
    state: State = .ours,

    /// 그려도 되는가. 아니면 present를 부르지 않는다 — 놓은 쪽의 DIRTYFB · SETCRTC는
    /// `EACCES`이고(확인 2) terminal의 present는 `try`라 부르면 죽는다.
    pub fn ownsScreen(self: *const Machine) bool {
        return self.state == .ours;
    }

    /// poll이 이 상태 때문에 기다릴 상한. 없으면 -1(`pacing.soonest`의 "없다").
    pub fn timeout(self: *const Machine) c_int {
        return if (self.state == .waiting) RETRY_MS else -1;
    }

    /// 새 연결 하나. 손님은 한 번에 하나다 — 이미 있거나 화면이 아직 남의 것이면 `busy`.
    pub fn arrive(self: *Machine, ops: anytype, fd: i32, pid: i32) void {
        if (self.guest_fd >= 0 or self.state != .ours) {
            logline.print("terminal: display> busy pid {d}\n", .{pid});
            ops.send(fd, .busy);
            ops.close(fd);
            return;
        }
        self.guest_fd = fd;
        self.guest_pid = pid;
    }

    /// 손님이 보낸 메시지 하나. 양보 뒤의 말은 뜻이 없다 — 끝은 연결을 닫는 것뿐이다.
    pub fn said(self: *Machine, ops: anytype, bytes: []const u8) void {
        if (self.guest_fd < 0 or self.state != .ours) return;
        if (proto.parseRequest(bytes) == null) return self.refuse(ops, "unknown request");
        ops.dropMaster() catch |e| return self.refuse(ops, @errorName(e));
        ops.send(self.guest_fd, .ok);
        self.state = .yielded;
        logline.print("terminal: display> yield pid {d}\n", .{self.guest_pid});
    }

    fn refuse(self: *Machine, ops: anytype, why: []const u8) void {
        logline.print("terminal: display> refused pid {d} ({s})\n", .{ self.guest_pid, why });
        ops.send(self.guest_fd, .refused);
        ops.close(self.guest_fd);
        self.guest_fd = -1;
    }

    /// 손님의 연결이 닫혔다(HUP · EOF). true면 화면을 되찾았다 — 부른 쪽이 통째로 다시 그린다.
    pub fn gone(self: *Machine, ops: anytype) bool {
        if (self.guest_fd < 0) return false;
        ops.close(self.guest_fd);
        self.guest_fd = -1;
        if (self.state != .yielded) return false;
        return self.reclaim(ops);
    }

    /// 바퀴마다 부른다. `waiting`일 때만 다시 해 본다. true의 뜻은 `gone`과 같다.
    pub fn retry(self: *Machine, ops: anytype) bool {
        if (self.state != .waiting) return false;
        return self.reclaim(ops);
    }

    /// `SET_MASTER` → `modeset`(확인 5 — 앱이 죽으면 CRTC에 fb가 없어 DIRTYFB로는 안 돌아온다).
    /// `waiting` 줄은 들어갈 때 한 번만 찍는다 — 1초마다 찍으면 로그가 시끄럽다.
    fn reclaim(self: *Machine, ops: anytype) bool {
        ops.setMaster() catch {
            if (self.state != .waiting) logline.print("terminal: display> waiting for master\n", .{});
            self.state = .waiting;
            return false;
        };
        // 모드를 못 걸어도 master는 되찾았다. 다음 present가 실패하면 terminal이 죽고 init이
        // 되살린다 — 양보 전과 같은 길이다.
        ops.modeset() catch |e| logline.print("terminal: display> modeset after reclaim failed ({s})\n", .{@errorName(e)});
        self.state = .ours;
        logline.print("terminal: display> reclaim\n", .{});
        return true;
    }
};

// ── socket ─────────────────────────────────────────────────────────

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn noSocket(step: []const u8, e: linux.E, fd: ?i32) i32 {
    if (fd) |f| _ = linux.close(f);
    logline.print("terminal: display> no socket ({s} errno {d}), programs cannot take the screen\n", .{ step, @backingInt(e) });
    return -1;
}

/// listen fd를 세운다. 실패하면 -1 — terminal은 그대로 돌고 양보만 없다.
///
/// `root:<gid> 0660`이라 video 그룹(사용자)이 붙을 수 있다(결정 3 · 7). NONBLOCK은 accept가
/// "없다"를 EAGAIN으로, CLOEXEC는 이 fd가 패널의 셸로 새지 않게 한다. backlog 1 — 손님은 하나다.
pub fn listen(gid: u32) i32 {
    if (failed(linux.mkdir(proto.DIR.ptr, 0o755))) |e| if (e != .EXIST) return noSocket("mkdir", e, null);
    _ = linux.unlink(proto.PATH.ptr);
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return noSocket("socket", e, null);
    const fd: i32 = @intCast(rc);
    var a: linux.sockaddr.un = .{ .path = @splat(0) };
    @memcpy(a.path[0..proto.PATH.len], proto.PATH);
    if (failed(linux.bind(fd, @ptrCast(&a), @sizeOf(linux.sockaddr.un)))) |e| return noSocket("bind", e, fd);
    if (failed(linux.chown(proto.PATH.ptr, 0, gid))) |e| return noSocket("chown", e, fd);
    if (failed(linux.chmod(proto.PATH.ptr, 0o660))) |e| return noSocket("chmod", e, fd);
    if (failed(linux.listen(fd, 1))) |e| return noSocket("listen", e, fd);
    logline.print("terminal: display> listening on {s}\n", .{proto.PATH});
    return fd;
}

/// `SO_PEERCRED`의 값. std에 없어 여기 둔다(`struct ucred`, socket(7)).
const Ucred = extern struct { pid: i32, uid: u32, gid: u32 };

pub const Guest = struct { fd: i32, pid: i32 };

/// 기다리는 연결 하나를 받는다. 없으면 null. 손님의 fd도 NONBLOCK · CLOEXEC다.
pub fn accept(lfd: i32) ?Guest {
    const rc = linux.accept4(lfd, null, null, linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC);
    if (failed(rc)) |_| return null;
    const fd: i32 = @intCast(rc);
    var cred: Ucred = .{ .pid = 0, .uid = 0, .gid = 0 };
    var len: linux.socklen_t = @sizeOf(Ucred);
    _ = linux.getsockopt(fd, linux.SOL.SOCKET, linux.SO.PEERCRED, @ptrCast(&cred), &len);
    return .{ .fd = fd, .pid = cred.pid };
}

pub const Read = union(enum) { msg: []const u8, gone, none };

/// 손님의 fd가 깨웠을 때. 0바이트(EOF)와 EAGAIN 아닌 실패는 `gone`이다.
pub fn read(fd: i32, buf: []u8) Read {
    const n = linux.recvfrom(fd, buf.ptr, buf.len, linux.MSG.DONTWAIT, null, null);
    if (failed(n)) |e| return if (e == .AGAIN) .none else .gone;
    if (n == 0) return .gone;
    return .{ .msg = buf[0..n] };
}

/// 답 하나. 상대가 이미 닫았으면 EPIPE이고 그것으로 끝이다 — NOSIGNAL이라 SIGPIPE는 없다.
pub fn send(fd: i32, r: proto.Reply) void {
    const t = proto.text(r);
    _ = linux.sendto(fd, t.ptr, t.len, linux.MSG.NOSIGNAL | linux.MSG.DONTWAIT, null, 0);
}

pub fn close(fd: i32) void {
    _ = linux.close(fd);
}
