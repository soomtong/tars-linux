const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");

/// 리눅스는 시스템 콜 실패를 "음수 errno"로 그대로 돌려준다. libc가 그것을
/// -1 리턴 + errno 전역 변수로 바꿔주는데, 여기서는 libc를 링크하지 않으므로
/// 그 변환을 직접 한다. 성공이면 null, 실패면 errno를 돌려준다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 성공하면 true. /proc·/sys·/dev는 실패해도 할 수 있는 일이 없어서 결과를
/// 버리지만, /config는 다르다 — 저장소가 안 붙었는데 설정을 읽으려 들면
/// initramfs(tmpfs) 위의 빈 디렉터리에 파일을 만들게 되고, 그건 재부팅하면
/// 사라지는 가짜 영속성이다.
fn mountFs(
    source: [:0]const u8,
    target: [:0]const u8,
    fstype: [:0]const u8,
    flags: u32,
) bool {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, flags, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to mount {s} at {s} (errno {d})\n", .{
            fstype, target, @intFromEnum(e),
        });
        return false;
    }
    std.debug.print("tars-init: mounted {s} at {s}\n", .{ fstype, target });
    return true;
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
    _ = mountFs("devpts", "/dev/pts", "devpts", 0);
}

/// 설정 저장소를 붙인다. initramfs는 tmpfs라 전원이 꺼지면 통째로 사라진다 —
/// 재부팅을 넘어 살아남는 것은 이 virtio-blk 디스크(/dev/vda) 하나뿐이다.
/// 파티션 테이블 없이 디스크 전체가 ext2라서 /dev/vda1이 아니라 /dev/vda다.
///
/// MS_SYNCHRONOUS로 붙이는 이유가 이 서브프로젝트의 핵심이다. 보통 파일에
/// 쓴 내용은 page cache에만 올라가고 커널이 알아서 나중에 디스크로 내려보낸다.
/// 그런데 우리 사용 시나리오는 "설정을 고치고 전원을 끈다"이고, 게이트는 실제로
/// 쓴 직후 QEMU를 죽인다. 동기 마운트면 write(2)가 돌아온 시점에 이미 디스크에
/// 있다. 설정 파일은 어쩌다 한 번 쓰는 것이라 성능 대가가 사실상 없다.
///
/// 디스크가 없는 부팅도 정상 경로다 — BF 체인은 ISO 부팅이라 -drive가 없다.
/// 그때는 errno 2(ENOENT)로 실패하고 로그 한 줄만 남으며, 부팅은 계속된다.
fn mountConfig() bool {
    return mountFs("/dev/vda", "/config", "ext2", linux.MS.SYNCHRONOUS);
}

/// 설정 파일의 자리. 저장소가 붙은 뒤에만 의미가 있다.
const CONFIG_PATH: [:0]const u8 = "/config/tars.conf";

/// 설정을 결정한다. 세 경로 전부 **부팅을 계속한다** — 설정 하나 때문에
/// 부팅이 막히면 그것이 이 설계의 실패다(design doc의 세 장치 중 3번).
///
///   저장소 없음  → 내장 기본값. BF·TF 체인이 매번 지나는 정상 경로다.
///   파일 없음    → first-boot seeding. 기본값을 주석과 함께 써 둔다.
///   파일 있음    → 읽어서 쓴다.
fn loadConfig(storage_mounted: bool) config.Config {
    if (!storage_mounted) {
        std.debug.print("tars-init: no config storage, using defaults\n", .{});
        return .{};
    }

    if (config.load(CONFIG_PATH)) |c| {
        std.debug.print("tars-init: loaded {s}\n", .{CONFIG_PATH});
        return c;
    }

    // load가 null을 준다는 것은 파일이 없다는 뜻뿐이다 = 이 디스크로 처음
    // 부팅했다. 씨앗을 심는다.
    const defaults = config.Config{};
    config.save(CONFIG_PATH, defaults) catch {
        std.debug.print("tars-init: could not seed {s}, using defaults\n", .{CONFIG_PATH});
        return defaults;
    };
    std.debug.print("tars-init: created {s}\n", .{CONFIG_PATH});
    return defaults;
}

/// 설정이 고른 셸의 바이너리가 정말 있는지 확인하고, 없으면 기본값으로
/// 내려온다. design doc의 "세 장치" 중 2번(모르는 값 → 기본값)의 연장이다 —
/// 이름은 화이트리스트가 막아주지만 **initrd에 안 들어간 셸**은 이름이
/// 맞아도 실행되지 않는다.
///
/// 이 함수가 없으면 그 상황이 이렇게 나타난다: execve가 127로 죽고, 감독
/// 루프가 1초 간격으로 세 번 재시작한 뒤 포기하고, **셸이 하나도 없는 부팅**이
/// 된다. 원인은 로그 깊숙한 곳의 execve 한 줄뿐이다. 미리 확인하면 한 줄로
/// 드러나고 부팅은 계속된다.
fn resolveShell(want: config.Shell) config.Shell {
    if (failed(linux.access(want.path().ptr, linux.X_OK)) == null) return want;

    const fallback = config.Config{};
    std.debug.print("tars-init: shell {s} is not executable, falling back to {s}\n", .{
        want.path(), @tagName(fallback.shell),
    });
    return fallback.shell;
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

/// 감독 대상의 종류. **무엇을 실행할지는 여기 없다** — 그것은 Child가
/// 들고 있고, 설정을 읽은 뒤 main에서 한 번 정해진다. Kind는 "이 자식이
/// 제어 터미널을 잡아야 하는가"와 로그 이름만 결정한다.
const Kind = enum {
    terminal,
    console_shell,

    fn name(self: Kind) []const u8 {
        return switch (self) {
            .terminal => "terminal",
            .console_shell => "console shell",
        };
    }
};

/// terminal은 우리가 빌드해 initrd 루트에 넣는 것이라 설정 대상이 아니다.
const TERMINAL_PATH: [:0]const u8 = "/terminal";

/// 이 초를 못 채우고 죽으면 "빨리 죽었다"로 센다.
const FAST_EXIT_SECONDS: isize = 10;
/// 빨리 죽는 것이 연속 이 횟수면 그 컴포넌트를 포기한다. BF 체인은 GPU가
/// 없어 /terminal이 매번 죽으므로 이 숫자가 곧 BF 로그의 노이즈 양이다.
const MAX_FAST_RESTARTS: u32 = 3;

const Child = struct {
    kind: Kind,
    /// 실행할 바이너리. 로그에 찍는 것도 이 값이다.
    path: [:0]const u8,
    /// execve에 그대로 넘길 argv. argv[0]은 path와 같고 남는 자리는 null이다 —
    /// execve는 첫 null에서 멈추므로 인자가 하나인 자식도 같은 배열 타입을
    /// 쓸 수 있다. 힙이 없어서 길이를 컴파일 타임에 고정한다.
    argv: [3:null]?[*:0]const u8,
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

fn spawn(c: *const Child, envp: [*:null]const ?[*:0]const u8) linux.pid_t {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: fork for {s} failed (errno {d})\n", .{
            c.kind.name(), @intFromEnum(e),
        });
        return -1;
    }
    if (pid == 0) {
        // 여기부터는 자식이다.
        if (c.kind == .console_shell) setupControllingTerminal();
        _ = linux.execve(c.path.ptr, &c.argv, envp);
        // execve가 돌아왔다는 것은 실패했다는 뜻이다.
        std.debug.print("tars-init: execve {s} failed\n", .{c.path});
        linux.exit(127);
    }
    return @intCast(pid);
}

fn start(c: *Child, envp: [*:null]const ?[*:0]const u8) void {
    const pid = spawn(c, envp);
    if (pid < 0) return; // 다음 바퀴에서 다시 시도한다
    c.pid = pid;
    c.started_at = monotonicSeconds();
    // 경로까지 찍는다. "셸이 바뀌었는가"를 게이트가 확인할 수 있는 유일한
    // 줄이다 — 프로세스가 무엇을 exec했는지는 밖에서 볼 방법이 없다.
    std.debug.print("tars-init: started {s} (pid {d}, {s})\n", .{
        c.kind.name(), pid, c.path,
    });
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

    _ = mountFs("proc", "/proc", "proc", 0);
    _ = mountFs("sysfs", "/sys", "sysfs", 0);
    _ = mountFs("devtmpfs", "/dev", "devtmpfs", 0);
    mountDevpts();

    const storage_mounted = mountConfig();
    const cfg = loadConfig(storage_mounted);
    std.debug.print("tars-init: config shell={s}\n", .{@tagName(cfg.shell)});

    logDrmDevicePresence();

    // 설정이 실제 동작이 되는 유일한 자리. 여기서 한 번 정해지면 감독 루프는
    // 설정을 모른 채 이 값을 반복해서 띄운다 — 재시작이 설정을 다시 읽지
    // 않는다는 뜻이고, "고치고 재부팅해야 반영된다"는 정책이 그래서 지켜진다.
    const shell = resolveShell(cfg.shell);
    const shell_path = shell.path();
    const shell_flag = shell.noConfigFlag();

    var children = [_]Child{
        .{
            .kind = .terminal,
            .path = TERMINAL_PATH,
            // terminal은 설정 파일을 읽지 않는다. 어느 셸을 PTY에 띄울지를
            // PID 1이 정해서 인자로 넘긴다 — 파서가 두 벌이 되면 두
            // 프로세스가 서로 다른 답을 얻을 수 있다.
            .argv = .{ TERMINAL_PATH.ptr, shell_path.ptr, shell_flag.ptr },
        },
        .{
            .kind = .console_shell,
            .path = shell_path,
            // 콘솔 셸에는 플래그를 주지 않는다. 이쪽은 사용자가 직접 쓰는
            // 자리이므로, 나중에 설정 파일이 생기면 그것을 읽는 편이 맞다.
            .argv = .{ shell_path.ptr, null, null },
        },
    };
    supervise(&children, envp);
}
