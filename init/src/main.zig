const std = @import("std");
const linux = std.os.linux;

/// 리눅스는 시스템 콜 실패를 "음수 errno"로 그대로 돌려준다. libc가 그것을
/// -1 리턴 + errno 전역 변수로 바꿔주는데, 여기서는 libc를 링크하지 않으므로
/// 그 변환을 직접 한다. 성공이면 null, 실패면 errno를 돌려준다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn mountFs(source: [:0]const u8, target: [:0]const u8, fstype: [:0]const u8) void {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, 0, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to mount {s} at {s} (errno {d})\n", .{
            fstype, target, @intFromEnum(e),
        });
    } else {
        std.debug.print("tars-init: mounted {s} at {s}\n", .{ fstype, target });
    }
}

/// devtmpfs는 드라이버가 등록한 장치 노드만 담기 때문에 /dev/pts 디렉터리를
/// 만들어주지 않는다. forkpty()는 /dev/ptmx를 연 뒤 커널이 지정한
/// /dev/pts/N을 열어야 하므로, 마운트 지점을 먼저 만들고 devpts를 붙인다.
fn mountDevpts() void {
    const rc = linux.mkdir("/dev/pts", 0o755);
    if (failed(rc)) |e| {
        if (e != .EXIST) {
            std.debug.print("tars-init: failed to create /dev/pts (errno {d})\n", .{
                @intFromEnum(e),
            });
            return;
        }
    }
    mountFs("devpts", "/dev/pts", "devpts");
}

fn logDrmDevicePresence() void {
    // 열지 않고 존재만 본다. 곧 fork될 /terminal이 이 장치를 독점해서
    // 열 것이므로 여기서는 건드리지 않는 편이 안전하다.
    if (failed(linux.access("/dev/dri/card0", linux.F_OK))) |_| {
        std.debug.print("tars-init: /dev/dri/card0 not found\n", .{});
    } else {
        std.debug.print("tars-init: /dev/dri/card0 exists\n", .{});
    }
}

/// 제어 터미널 잡기는 PID 1이 아니라 **콘솔 셸 자식**이 한다. setsid()로 새
/// 세션의 리더가 된 뒤 TIOCSCTTY로 /dev/console을 제어 터미널로 붙여야
/// Ctrl-C 같은 것이 그 셸에 전달된다. PID 1은 초기 세션에 그대로 남아
/// 커널이 열어준 fd 0/1/2로 자기 로그를 계속 찍는다.
fn setupControllingTerminal() void {
    const rc = linux.open("/dev/console", .{ .ACCMODE = .RDWR }, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to open /dev/console (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    const fd: i32 = @intCast(rc);

    _ = linux.setsid();
    _ = linux.ioctl(fd, linux.T.IOCSCTTY, 0);
    _ = linux.dup2(fd, 0);
    _ = linux.dup2(fd, 1);
    _ = linux.dup2(fd, 2);
    if (fd > 2) _ = linux.close(fd);
}

/// 감독 대상. 지금은 둘뿐이라 배열을 컴파일 타임에 고정한다. 설정 파일에서
/// 목록을 읽는 것은 다음 서브프로젝트(설정 영속화)의 일이다.
const Kind = enum {
    terminal,
    console_shell,

    fn name(self: Kind) []const u8 {
        return switch (self) {
            .terminal => "terminal",
            .console_shell => "console shell",
        };
    }

    fn path(self: Kind) [:0]const u8 {
        return switch (self) {
            .terminal => "/terminal",
            .console_shell => "/usr/bin/fish",
        };
    }
};

/// 이 초를 못 채우고 죽으면 "빨리 죽었다"로 센다.
const FAST_EXIT_SECONDS: isize = 10;
/// 빨리 죽는 것이 연속 이 횟수면 그 컴포넌트를 포기한다. BF 체인은 GPU가
/// 없어 /terminal이 매번 죽으므로 이 숫자가 곧 BF 로그의 노이즈 양이다.
const MAX_FAST_RESTARTS: u32 = 3;

const Child = struct {
    kind: Kind,
    /// -1이면 지금 돌고 있지 않다는 뜻이다.
    pid: linux.pid_t = -1,
    started_at: isize = 0,
    fast_restarts: u32 = 0,
    given_up: bool = false,
};

fn monotonicSeconds() isize {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
    return ts.sec;
}

fn sleepOneSecond() void {
    const req = linux.timespec{ .sec = 1, .nsec = 0 };
    _ = linux.nanosleep(&req, null);
}

fn spawn(kind: Kind, envp: [*:null]const ?[*:0]const u8) linux.pid_t {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: fork for {s} failed (errno {d})\n", .{
            kind.name(), @intFromEnum(e),
        });
        return -1;
    }
    if (pid == 0) {
        // 여기부터는 자식이다.
        if (kind == .console_shell) setupControllingTerminal();
        const p = kind.path();
        const argv = [_:null]?[*:0]const u8{p.ptr};
        _ = linux.execve(p.ptr, &argv, envp);
        // execve가 돌아왔다는 것은 실패했다는 뜻이다.
        std.debug.print("tars-init: execve {s} failed\n", .{p});
        linux.exit(127);
    }
    return @intCast(pid);
}

fn start(c: *Child, envp: [*:null]const ?[*:0]const u8) void {
    const pid = spawn(c.kind, envp);
    if (pid < 0) return; // 다음 바퀴에서 다시 시도한다
    c.pid = pid;
    c.started_at = monotonicSeconds();
    std.debug.print("tars-init: started {s} (pid {d})\n", .{ c.kind.name(), pid });
}

fn find(children: []Child, pid: linux.pid_t) ?*Child {
    for (children) |*c| {
        if (c.pid == pid) return c;
    }
    return null;
}

/// PID 1의 본체. **절대 반환하지 않는다** — 반환하면 커널이 패닉한다.
fn supervise(children: []Child, envp: [*:null]const ?[*:0]const u8) noreturn {
    while (true) {
        var alive: usize = 0;
        for (children) |*c| {
            if (c.pid < 0 and !c.given_up) start(c, envp);
            if (c.pid >= 0) alive += 1;
        }

        // 감독 대상이 전부 포기 상태여도 PID 1은 죽으면 안 되고, 재부모화된
        // 고아를 거둘 의무도 남는다. 그래서 종료하지 않고 쉬면서 돈다.
        if (alive == 0) {
            sleepOneSecond();
            continue;
        }

        var status: u32 = 0;
        const rc = linux.waitpid(-1, &status, 0);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            if (e != .CHILD) {
                std.debug.print("tars-init: waitpid failed (errno {d})\n", .{
                    @intFromEnum(e),
                });
            }
            sleepOneSecond();
            continue;
        }
        const pid: linux.pid_t = @intCast(rc);

        // -1은 "아무 자식이나"라서 내 자식뿐 아니라 부모를 잃고 PID 1에
        // 재부모화된 프로세스까지 함께 거둔다. 그것이 PID 1의 의무다.
        const c = find(children, pid) orelse {
            std.debug.print("tars-init: reaped orphan pid {d}\n", .{pid});
            continue;
        };

        const lived = monotonicSeconds() - c.started_at;
        c.pid = -1;

        if (linux.W.IFEXITED(status)) {
            std.debug.print("tars-init: {s} exited (pid {d}, status {d}, lived {d}s)\n", .{
                c.kind.name(), pid, linux.W.EXITSTATUS(status), lived,
            });
        } else {
            std.debug.print("tars-init: {s} killed (pid {d}, signal {d}, lived {d}s)\n", .{
                c.kind.name(), pid, @intFromEnum(linux.W.TERMSIG(status)), lived,
            });
        }

        if (lived < FAST_EXIT_SECONDS) {
            c.fast_restarts += 1;
        } else {
            c.fast_restarts = 0;
        }

        if (c.fast_restarts >= MAX_FAST_RESTARTS) {
            c.given_up = true;
            std.debug.print("tars-init: giving up on {s} after {d} fast exits\n", .{
                c.kind.name(), c.fast_restarts,
            });
            continue;
        }

        std.debug.print("tars-init: restarting {s} in 1s\n", .{c.kind.name()});
        sleepOneSecond();
    }
}

pub fn main(init: std.process.Init.Minimal) void {
    // 커널이 PID 1의 스택에 올려준 환경 변수 블록.
    const envp = init.environ.block.slice.ptr;

    std.debug.print("tars-init: starting as PID 1\n", .{});

    mountFs("proc", "/proc", "proc");
    mountFs("sysfs", "/sys", "sysfs");
    mountFs("devtmpfs", "/dev", "devtmpfs");
    mountDevpts();

    logDrmDevicePresence();

    var children = [_]Child{
        .{ .kind = .terminal },
        .{ .kind = .console_shell },
    };
    supervise(&children, envp);
}
