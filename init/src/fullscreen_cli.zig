//! DY-M0. `tars-fullscreen <명령> [인자…]` — terminal에게 화면을 달라고 하고, 받으면 그 명령이 된다.
//!
//! terminal의 `/run/tars/display.sock`에 붙어 `yield`를 보내고 `ok`를 받으면, 그 연결을 연 채로
//! (CLOEXEC 없이) 명령을 exec한다(DY design 결정 4). fork하지 않는다 — 명령이 이 프로세스의 자리(pid ·
//! 전경 job)를 그대로 잇고, 연결은 명령과 그 자손이 다 죽을 때 커널이 닫는다. 그 닫힘이 양보의 끝이다
//! — 명령이 어떻게 끝나든(정상 · 신호 · SIGKILL) terminal이 화면을 되찾는다.
//!
//! `ok`가 아니면 명령을 띄우지 않고 까닭을 찍고 1로 끝난다. exec가 실패하면 셸의 관례대로
//! 127(못 찾음) · 126(실행 못 함)이고, 그때 이 프로세스가 끝나며 연결이 닫혀 terminal이 되찾는다.
const std = @import("std");
const linux = std.os.linux;
const proto = @import("display_proto");

const EXIT_REFUSED: u8 = 1;
const EXIT_CANNOT_EXEC: u8 = 126;
const EXIT_NOT_FOUND: u8 = 127;
const EXIT_USAGE: u8 = 64;
/// terminal은 요청을 받은 바퀴에 답한다. 그 바퀴가 그리는 중이어도 이 안이다.
const REPLY_WAIT_MS: i32 = 3000;
/// 명령 이름이 PATH의 디렉터리와 이어 붙는 버퍼.
const PATH_MAX = 4096;

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
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-fullscreen: " ++ fmt ++ "\n", args) catch return;
    writeAll(2, text);
}

fn usage() u8 {
    writeAll(2,
        \\usage: tars-fullscreen COMMAND [ARG...]
        \\  ask the terminal for the screen, then run COMMAND with it;
        \\  the console comes back when COMMAND (and anything it left running) ends
        \\
    );
    return EXIT_USAGE;
}

/// 붙어서 `yield`를 보내고 답을 받는다. 성공하면 연결된 fd, 아니면 까닭을 찍고 null.
/// socket은 CLOEXEC 없이 만든다 — exec 뒤에도 명령이 이 연결을 쥐고 있어야 한다.
fn ask() ?i32 {
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET, 0);
    if (linux.errno(rc) != .SUCCESS) {
        complain("cannot make a socket (errno {d})", .{@backingInt(linux.errno(rc))});
        return null;
    }
    const fd: i32 = @intCast(rc);
    var a: linux.sockaddr.un = .{ .path = @splat(0) };
    @memcpy(a.path[0..proto.PATH.len], proto.PATH);
    const c = linux.errno(linux.connect(fd, &a, @sizeOf(linux.sockaddr.un)));
    if (c != .SUCCESS) {
        _ = linux.close(fd);
        switch (c) {
            .NOENT, .CONNREFUSED => complain("no terminal is listening on {s}", .{proto.PATH}),
            .ACCES, .PERM => complain("not allowed to reach {s} (the video group can)", .{proto.PATH}),
            else => complain("cannot reach {s} (errno {d})", .{ proto.PATH, @backingInt(c) }),
        }
        return null;
    }
    // 보내기가 실패해도(EPIPE) 답을 읽어 본다. terminal은 둘째 손님을 요청을 기다리지 않고 받자마자
    // `busy`로 답하고 닫는다 — 그 답은 이미 소켓에 와 있다(DY-M0 체인이 처음 돌 때 이 경합을 봤다).
    const word = proto.text(proto.Request.yield);
    _ = linux.sendto(fd, word.ptr, word.len, linux.MSG.NOSIGNAL, null, 0);
    var p = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const ready = linux.poll(&p, 1, REPLY_WAIT_MS);
    var buf: [proto.MSG_MAX]u8 = undefined;
    const n = if (linux.errno(ready) == .SUCCESS and ready > 0) linux.recvfrom(fd, &buf, buf.len, 0, null, null) else 0;
    const reply: ?proto.Reply = if (linux.errno(n) == .SUCCESS and n > 0) proto.parseReply(buf[0..n]) else null;
    if (reply == .ok) return fd;
    _ = linux.close(fd);
    if (reply) |r| switch (r) {
        .busy => complain("the screen is in use by another program", .{}),
        .refused => complain("the terminal could not give up the screen (see its log)", .{}),
        .ok => unreachable,
    } else complain("no answer from the terminal", .{});
    return null;
}

/// `PATH`의 값. 없으면 init이 주는 기본(`environ.zig`의 PATH_ENTRY)과 같은 목록이다.
fn pathOf(envp: [*:null]const ?[*:0]const u8) []const u8 {
    var i: usize = 0;
    while (envp[i]) |e| : (i += 1) {
        const s = std.mem.span(e);
        if (std.mem.startsWith(u8, s, "PATH=")) return s[5..];
    }
    return "/usr/local/bin:/usr/bin:/bin";
}

/// execvp. libc가 없어 PATH를 직접 훑는다. 돌아오면 실패이고 값은 종료값이다.
/// 디렉터리마다 ENOENT면 다음으로, 그 밖의 실패(EACCES 등)는 기억해 두었다가 126이다 — 셸과 같다.
fn execvp(argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) u8 {
    const name = std.mem.span(argv[0].?);
    if (std.mem.indexOfScalar(u8, name, '/') != null) {
        const e = linux.errno(linux.execve(argv[0].?, argv, envp));
        complain("cannot run {s} (errno {d})", .{ name, @backingInt(e) });
        return if (e == .NOENT) EXIT_NOT_FOUND else EXIT_CANNOT_EXEC;
    }
    var buf: [PATH_MAX]u8 = undefined;
    var denied = false;
    var it = std.mem.splitScalar(u8, pathOf(envp), ':');
    while (it.next()) |dir| {
        const d = if (dir.len == 0) "." else dir;
        const full = std.fmt.bufPrintSentinel(&buf, "{s}/{s}", .{ d, name }, 0) catch continue;
        const e = linux.errno(linux.execve(full.ptr, argv, envp));
        if (e != .NOENT and e != .NOTDIR) denied = true;
    }
    if (denied) {
        complain("cannot run {s}", .{name});
        return EXIT_CANNOT_EXEC;
    }
    complain("{s}: command not found", .{name});
    return EXIT_NOT_FOUND;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len < 2) return usage();
    const fd = ask() orelse return EXIT_REFUSED;
    // 연결이 exec를 넘어 살아남는지 한 번 본다(plan Task 3). socket을 CLOEXEC 없이 만들었으니
    // 늘 꺼져 있어야 한다 — 켜져 있으면 exec 순간 연결이 닫혀 terminal이 곧바로 되찾는다.
    const flags = linux.fcntl(fd, linux.F.GETFD, 0);
    if (linux.errno(flags) != .SUCCESS or flags & linux.FD_CLOEXEC != 0) {
        complain("the connection would close at exec, not running {s}", .{std.mem.span(argv[1])});
        return EXIT_REFUSED;
    }
    const cmd: [*:null]const ?[*:0]const u8 = @ptrCast(argv[1..].ptr);
    return execvp(cmd, init.environ.block.slice.ptr);
}
