//! TP-M11 plan 결정 E. 사람이 믿기로 한 인증 기관이 재부팅을 넘는다.
//!
//! 시스템의 CA 묶음 `/etc/ssl/certs/ca-certificates.crt`는 `/etc`(RAM)에 있어 부팅마다 initrd의 것(mozilla만)으로
//! 돌아온다. 사람이 더한 인증서는 Debian의 자리 `/usr/local/share/ca-certificates/`에 둔다 — `/usr/local`은 p3의 쓰기 층이라
//! 남는다(TP-M4). `sudo mkcert -install`이 바로 그 자리에 쓰고 `update-ca-certificates`를 부른다. 부팅 때는 init이 그 명령을
//! 한 번 부른다 — `.crt`가 하나라도 있을 때만. 없으면 fork도 하지 않는다(다른 체인 · 대부분의 부팅은 아무것도 안 바뀐다).
//!
//! PID 1이 기다리는 일이라 시한이 있다(`WAIT_MS`). 넘으면 그 명령의 프로세스 그룹째 죽이고(SS-M2) 한 줄을 남긴 뒤 원본 묶음 그대로 간다.
const std = @import("std");
const linux = std.os.linux;
const logline = @import("logline.zig");

pub const DIR: [:0]const u8 = "/usr/local/share/ca-certificates";
pub const CMD: [:0]const u8 = "/usr/bin/update-ca-certificates";
const WAIT_MS: u64 = 5000;
const STEP_MS: u64 = 100;
/// 하위 디렉터리를 몇 단계까지 보는가. Debian의 명령은 `DIR/<이름>/*.crt`까지 읽는다 — 스크립트와 같게 한 단계.
const DEPTH_MAX: usize = 1;

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 숨은 파일이 아니고 `.crt`로 끝나는 이름. Debian의 명령도 `.crt`만 읽는다.
pub fn isCrt(name: []const u8) bool {
    return name.len > ".crt".len and name[0] != '.' and std.mem.endsWith(u8, name, ".crt");
}

/// `dir`(또는 한 단계 아래)에 `.crt`가 하나라도 있는가. 디렉터리가 없으면 false.
pub fn hasCrt(dir: [:0]const u8) bool {
    return scan(dir, 0);
}

fn scan(dir: [:0]const u8, depth: usize) bool {
    const rc = linux.open(dir.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc) != null) return false;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var buf: [2048]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &buf, buf.len);
        if (failed(n) != null or n == 0) return false;
        var off: usize = 0;
        while (off < n) {
            const d: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += d.reclen;
            const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&d.name)), 0);
            if (name.len == 0 or name[0] == '.') continue;
            switch (d.type) {
                // 링크는 따라가 보지 않고 이름만 본다 — 스크립트의 `[ -f ]`가 끝을 본다.
                linux.DT.REG, linux.DT.LNK => if (isCrt(name)) return true,
                linux.DT.DIR => if (depth < DEPTH_MAX) {
                    var p_buf: [256]u8 = undefined;
                    const p = std.fmt.bufPrintSentinel(&p_buf, "{s}/{s}", .{ dir, name }, 0) catch continue;
                    if (scan(p, depth + 1)) return true;
                },
                else => {},
            }
        }
    }
}

fn sleepMs(ms: u64) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

/// `runWithin`의 결과.
pub const Run = union(enum) {
    ok,
    /// 0이 아닌 종료 · 시그널 — `wait4`의 status 그대로.
    failed: u32,
    timed_out,
    no_fork: linux.E,
    no_wait: linux.E,
};

/// SS-M2. 명령 하나를 시한 안에 돌린다. 넘으면 죽이고 거둔 뒤 `timed_out`.
///
/// 명령은 제 프로세스 그룹을 갖고, 시한 넘김은 그 그룹째 죽인다. `update-ca-certificates`는 셸 스크립트라 그 아래의
/// `run-parts` · `openssl`이 일을 한다 — 셸 pid만 죽이면 그들이 남아 묶음 파일을 계속 쓴다(SS design 확인 5).
/// 그룹은 자식과 부모가 둘 다 세운다 — 어느 쪽이 먼저 돌든 `kill(-pid)` 전에 그룹이 있다.
pub fn runWithin(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8, wait_ms: u64) Run {
    const pid = linux.fork();
    if (failed(pid)) |e| return .{ .no_fork = e };
    if (pid == 0) {
        _ = linux.setpgid(0, 0);
        _ = linux.execve(path, argv, envp);
        logline.print("tars-init: trust: cannot exec {s}\n", .{std.mem.sliceTo(path, 0)});
        linux.exit(127);
    }
    _ = linux.setpgid(@intCast(pid), @intCast(pid));
    var waited: u64 = 0;
    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), @ptrCast(&status), linux.W.NOHANG, null);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            return .{ .no_wait = e };
        }
        if (rc != 0) break;
        if (waited >= wait_ms) {
            const leader: linux.pid_t = @intCast(pid);
            _ = linux.kill(-leader, .KILL);
            while (failed(linux.wait4(@intCast(pid), @ptrCast(&status), 0, null))) |e| {
                if (e != .INTR) break;
            }
            return .timed_out;
        }
        sleepMs(STEP_MS);
        waited += STEP_MS;
    }
    if (linux.W.IFEXITED(status) and linux.W.EXITSTATUS(status) == 0) return .ok;
    return .{ .failed = status };
}

/// 부팅마다 한 번, `/usr/local`을 연 뒤(`layers.mountLocal`) 부른다. 아무것도 안 하거나, 명령을 한 번 돌리고 한 줄을 남긴다.
pub fn refresh() void {
    if (!hasCrt(DIR)) return;
    const argv = [_:null]?[*:0]const u8{ CMD.ptr, null };
    const envp = [_:null]?[*:0]const u8{ "PATH=/usr/bin:/bin", null };
    switch (runWithin(CMD.ptr, &argv, &envp, WAIT_MS)) {
        .ok => logline.print("tars-init: trust: {s} added the certificates in {s}\n", .{ CMD, DIR }),
        .failed => |status| logline.print("tars-init: trust: {s} failed (status {d}); the CA bundle is the initrd's\n", .{ CMD, status }),
        .timed_out => logline.print("tars-init: trust: {s} took over {d}s, killed its process group; the CA bundle is the initrd's\n", .{ CMD, WAIT_MS / 1000 }),
        .no_fork => |e| logline.print("tars-init: trust: cannot fork for {s} (errno {d})\n", .{ CMD, @backingInt(e) }),
        .no_wait => |e| logline.print("tars-init: trust: waiting for {s} failed (errno {d})\n", .{ CMD, @backingInt(e) }),
    }
}
