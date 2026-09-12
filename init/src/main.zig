const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const power = @import("power.zig");
const devices = @import("devices.zig");
const storage = @import("storage.zig");
const environ = @import("environ.zig");

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

/// `XDG_DATA_HOME`이 가리키는 디렉터리를 만든다(SM design 결정 9).
/// **설정 디스크가 붙었을 때만** 부른다 — 안 붙은 기계에서는 `/config`가
/// tmpfs의 빈 디렉터리이고, 거기에 도구가 자기 자리를 만드는 것이 정상
/// 경로다(실측 4).
///
/// **도구 둘이 없는 경로를 스스로 만든다는 것을 알고도 만드는 이유**는
/// 실패의 자리를 정하기 위해서다. 디스크가 붙었는데 여기에 못 쓰면 그것은
/// 이상한 일이고, 그때 로그 한 줄이 남는 편이 "기억이 안 남는다"를 나중에
/// 셸에서 조사하는 것보다 낫다. `mountDevpts`가 `/dev/pts`에 대해 하는 것과
/// 같은 모양이다.
fn makeXdgDir() void {
    const rc = linux.mkdir(environ.XDG_DATA_DIR, 0o755);
    if (failed(rc)) |e| {
        // 이미 있다 = 두 번째 부팅부터의 정상 경로다. 조용히 둔다.
        if (e == .EXIST) return;
        std.debug.print("tars-init: could not create {s} (errno {d})\n", .{
            environ.XDG_DATA_DIR, @intFromEnum(e),
        });
    }
}

/// 설정 저장소를 붙인다. initramfs는 tmpfs라 전원이 꺼지면 통째로 사라진다 —
/// 재부팅을 넘어 살아남는 것은 이 디스크 하나뿐이다. 파티션 테이블 없이
/// 디스크 전체가 ext2라서 /dev/nvme0n1p1이 아니라 /dev/nvme0n1이다.
///
/// **RM-M2까지는 /dev/vda가 여기 박혀 있었다.** 그 이름은 virtio-blk에만
/// 있어서 노트북에서는 저장소를 영영 못 찾았다 — 부팅은 됐고 설정만 매번
/// 사라졌다. 이제 storage.zig가 후보 열넷을 훑어 **ext2 라벨이 `tars-`로
/// 시작하는** 첫 디스크를 고른다. 이름이 아니라 디스크 안의 표식으로 고르는
/// 것이라, virtio든 NVMe든 SATA든 같은 코드가 지난다.
///
/// MS_SYNCHRONOUS로 붙이는 이유가 이 서브프로젝트의 핵심이다. 보통 파일에
/// 쓴 내용은 page cache에만 올라가고 커널이 알아서 나중에 디스크로 내려보낸다.
/// 그런데 우리 사용 시나리오는 "설정을 고치고 전원을 끈다"이고, 게이트는 실제로
/// 쓴 직후 QEMU를 죽인다. 동기 마운트면 write(2)가 돌아온 시점에 이미 디스크에
/// 있다. 설정 파일은 어쩌다 한 번 쓰는 것이라 성능 대가가 사실상 없다.
///
/// 디스크가 없는 부팅도 정상 경로다 — BF 체인은 ISO 부팅이라 -drive가 없다.
/// 그때는 후보 열넷이 전부 ENOENT로 열리지 않아 로그 한 줄만 남으며, 부팅은
/// 계속된다.
fn mountConfig() bool {
    var found: storage.Found = .{};
    if (!storage.findConfigDisk(&found)) {
        std.debug.print("tars-init: no disk labelled {s}* among {d} candidates\n", .{
            storage.LABEL_PREFIX, storage.CANDIDATES.len,
        });
        return false;
    }

    // **이 줄이 RM-M2의 판정이다.** 고른 이름과 고른 근거가 한 줄에 함께
    // 있어야 실패했을 때 갈린다 — "후보에 그 이름이 없었다"와 "라벨을 못
    // 읽었다"와 "라벨이 우리 것이 아니었다"와 "골랐는데 mount가 실패했다"가
    // 서로 다른 병이다(IS-M1 실측 5와 같은 종류).
    std.debug.print("tars-init: config storage {s} (label {s})\n", .{
        found.path, found.label(),
    });

    // mountFs는 한 글자도 안 고친다. 이 함수가 찍는
    // `tars-init: mounted ext2 at /config`를 config/check.sh:206과
    // power/check.sh:85가 마커로 갖고 있다.
    return mountFs(found.path, "/config", "ext2", linux.MS.SYNCHRONOUS);
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

/// 탈출로 1(SC design 결정 8). 감독자가 포기하기 **직전에** argv의 이 자리를
/// 이 값으로 바꾸고 딱 한 번 다시 띄운다.
///
/// **자리가 자식마다 다르다.** terminal은 argv[2]가 "셸에 넘길 플래그"이고
/// (argv[1]은 셸 경로다), 콘솔 셸은 argv[1]이 그 플래그 자체다 — argv를 짓는
/// 쪽과 쓰는 쪽이 갈리느냐 아니냐의 차이가 여기서도 한 번 더 나온다
/// (`config.zig`의 `configFlag` 주석이 같은 비대칭을 적고 있다). 그래서
/// 슬롯 번호를 값으로 들고 다닌다.
const Rescue = struct {
    slot: usize,
    flag: [:0]const u8,
};

/// 위 슬롯 둘. **아래 `children` 배열의 argv 리터럴과 짝이고, 어긋나면
/// 탈출로가 엉뚱한 인자를 덮어쓴다** — terminal이면 키보드 종류 자리다.
const TERMINAL_FLAG_SLOT: usize = 2;
const CONSOLE_FLAG_SLOT: usize = 1;

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
    /// IP-M2에서 셋에서 넷으로, HD-M0에서 넷에서 다섯으로, HI-M2에서
    /// 다섯에서 일곱으로, **HI-M3에서 일곱에서 여덟으로** 늘었다. terminal이
    /// 받는 넷째가 keyboard, 다섯째가 키보드 장치 경로, 여섯째가 한글 자판,
    /// 일곱째가 영문 자판, 여덟째가 한/영 전환 키 목록이고, 콘솔 셸은 그
    /// 자리를 전부 null로 둔다.
    argv: [8:null]?[*:0]const u8,
    /// -1이면 지금 돌고 있지 않다는 뜻이다.
    pid: linux.pid_t = -1,
    started_at: isize = 0,
    fast_restarts: u32 = 0,
    given_up: bool = false,
    /// 남아 있는 탈출로. **한 번 쓰면 null이 된다** — 결정 8의 "한 번만"이
    /// 상태 하나로 표현되는 자리다. 처음부터 null이면 이 자식에게는 탈출로가
    /// 없다(설정 디스크가 없거나 이미 `shell_config=off`다).
    rescue: ?Rescue = null,
};

fn monotonicSeconds() isize {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
    return ts.sec;
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

/// 감독 루프가 한 바퀴에 잠드는 시간. 이 값이 세 가지를 동시에 정한다.
///
///   1. 전원 버튼을 눌렀을 때 최대 지각 — 사람이 못 느낀다.
///   2. 자식이 죽고 나서 다시 뜰 때까지의 backoff — 예전 sleepOneSecond()가
///      하던 일을 이제 이 타임아웃이 한다.
///   3. SIGCHLD 경합의 창 — waitpid(WNOHANG)이 "없다"를 답한 뒤 poll이 잠들기
///      전까지의 틈에 자식이 죽으면 그 죽음을 알려 줄 것이 아무것도 없다.
///      SIGCHLD 핸들러를 새로 달면 그 틈이 닫히지만, 그러면 power.zig의
///      "signal handlers installed (TERM, INT)" 로그와 그것을 grep하는
///      게이트까지 함께 흔들린다(design 결정 8).
const POLL_TIMEOUT_MS: i32 = 1000;

/// PID 1의 본체. **절대 반환하지 않는다** — 반환하면 커널이 패닉한다.
///
/// buttons가 비어 있어도 이 구조는 그대로 성립한다. fd 0개에 1초 타임아웃인
/// poll은 그냥 sleep이고, 그것이 design 결정 6의 폴백을 자연스럽게 받쳐 준다.
fn supervise(
    children: []Child,
    buttons: []const i32,
    envp: [*:null]const ?[*:0]const u8,
) noreturn {
    // poll에 넘길 배열. 버튼 fd는 부팅 때 한 번 정해지고 변하지 않으므로
    // 루프 밖에서 한 번만 채운다. revents만 커널이 매 호출 덮어쓴다.
    var fds: [devices.MAX_BUTTONS]linux.pollfd = undefined;
    for (buttons, 0..) |fd, i| {
        fds[i] = .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 };
    }
    const nfds: linux.nfds_t = buttons.len;

    while (true) {
        // 자식을 다시 띄우기 **전에** 본다. 순서가 뒤집히면 방금 SIGTERM으로
        // 죽인 셸을 이 루프가 되살린다. 시그널로 왔든 버튼으로 왔든 종료가
        // 시작되는 자리는 여기 하나다(design 결정 9).
        if (power.take()) |action| power.shutdown(action);

        for (children) |*c| {
            if (c.pid < 0 and !c.given_up) start(c, envp);
        }

        // ── 거둘 것을 전부 거둔다 ────────────────────────────────────
        //
        // 이것이 poll보다 **앞**인 것이 backoff를 만든다. 자식이 죽으면 이
        // 바퀴에서 거두고 곧바로 아래 poll에서 1초를 자므로, 재시작은 다음
        // 바퀴 머리에서 일어난다. 예전 코드의 sleepOneSecond()가 하던 일을
        // 순서 하나가 대신한다.
        while (true) {
            var status: u32 = 0;
            const rc = linux.waitpid(-1, &status, linux.W.NOHANG);
            if (failed(rc)) |e| {
                if (e == .INTR) continue;
                // ECHILD는 자식이 하나도 없다는 뜻이고, 감독 대상이 전부
                // 포기 상태일 때의 정상 경로다.
                if (e != .CHILD) {
                    std.debug.print("tars-init: waitpid failed (errno {d})\n", .{
                        @intFromEnum(e),
                    });
                }
                break;
            }
            // 0은 "살아 있고 아직 안 죽었다"이다. 더 거둘 것이 없다.
            if (rc == 0) break;

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
                // ── 탈출로 1(SC-M2 결정 8) ──────────────────────────────
                //
                // 포기하기 **직전에** rc 없이 한 번 더 띄운다. 빨리 죽는
                // 이유 중 우리가 고칠 수 있는 것은 사용자의 rc 하나뿐이고,
                // 그것을 뺀 셸은 SC 이전의 셸과 같다 — 이 저장소가 오래
                // 돌려 온 상태다. `resolveShell()`이 없는 셸에 대해 하는
                // 폴백과 **같은 모양**이다: 설정이 가리키는 것이 실제로 안
                // 되면 되는 것으로 떨어지고, 부팅은 계속된다.
                //
                // **덮는 것은 "죽는 rc"까지다.** 매달리는 rc(`read` 한 줄,
                // 무한 루프)는 자식이 안 죽으니 이 길로 안 온다 — 그것이
                // 탈출로 2가 따로 있는 이유다(결정 9).
                if (c.rescue) |r| {
                    c.argv[r.slot] = r.flag.ptr;
                    c.rescue = null; // 한 번만
                    // 이 줄 둘이 이 기능의 사용자 인터페이스 전부다.
                    // "왜 내 rc가 안 먹지"가 로그 한 줄로 답이 되어야 한다.
                    std.debug.print("tars-init: {s} died {d} times fast, the rc files are the suspect; restarting it with {s}\n", .{
                        c.kind.name(), c.fast_restarts, r.flag,
                    });
                    std.debug.print("tars-init: to keep it that way put shell_config=off in {s}, or {s} on the kernel command line\n", .{
                        CONFIG_PATH, config.NO_CONFIG_TOKEN,
                    });
                    // 로그 **뒤**에 0으로 되돌린다 — 찍는 수가 "몇 번 죽고
                    // 나서 이 결정을 했는가"여야 한다.
                    c.fast_restarts = 0;
                    continue;
                }
                c.given_up = true;
                std.debug.print("tars-init: giving up on {s} after {d} fast exits\n", .{
                    c.kind.name(), c.fast_restarts,
                });
                continue;
            }

            // "1s"가 여전히 참인 이유는 아래 poll이 그만큼 자기 때문이다.
            // terminal/check.sh:178이 이 문구를 진단 목록에 갖고 있다.
            std.debug.print("tars-init: restarting {s} in 1s\n", .{c.kind.name()});
        }

        // ── 유일하게 잠드는 자리 ─────────────────────────────────────
        //
        // EINTR로 깨어나 루프 머리로 돌아가는 것이 시그널 경로의 전부다.
        // power.zig가 SA_RESTART를 켜지 않는 이유가 이 한 줄이며, 켜면
        // 커널이 이 poll을 안에서 재시작해버려 플래그를 세워도 영영 머리로
        // 못 돌아온다(PM-M0이 milestone 하나를 써서 얻은 자리다).
        const ready = linux.poll(&fds, nfds, POLL_TIMEOUT_MS);
        if (failed(ready)) |e| {
            if (e != .INTR) {
                std.debug.print("tars-init: poll failed (errno {d})\n", .{
                    @intFromEnum(e),
                });
            }
            continue;
        }
        if (ready == 0) continue; // 타임아웃. 흔한 경로다.

        for (fds[0..buttons.len]) |*p| {
            if (p.revents == 0) continue;

            // POLLIN이 아니라 POLLERR/POLLHUP으로 깨어났어도 일단 읽어 본다.
            // 읽지 않고 넘어가면 그 revents가 매 poll마다 다시 서서 PID 1이
            // CPU를 태우는 바쁜 루프가 되기 때문이다.
            if (devices.drainButton(p.fd)) {
                // device/check.sh가 이 줄을 grep한다.
                std.debug.print("tars-init: power button pressed\n", .{});
                power.request(.power_off);
            }

            // 읽어도 해결되지 않는 종류로 깨어났으면 이 fd를 목록에서 뺀다.
            // fd를 음수로 두면 커널이 그 자리를 통째로 건너뛴다(POSIX). 이것이
            // 없으면 장치가 사라졌을 때 read가 계속 실패하고 revents가 계속
            // 서서 바쁜 루프가 된다.
            //
            // **핫플러그를 지원하는 것이 아니다**(design 비목표). 장치가
            // 빠졌을 때 PID 1이 CPU를 태우지 않게 하는 것뿐이고, 그러고 나면
            // 버튼 없이 도는 상태가 된다 — 결정 6이 이미 허용한 상태다.
            const broken = linux.POLL.ERR | linux.POLL.HUP | linux.POLL.NVAL;
            if (p.revents & broken != 0) {
                std.debug.print("tars-init: power button fd {d} went away (revents {d})\n", .{
                    p.fd, p.revents,
                });
                p.fd = -1;
            }
        }
    }
}

pub fn main(init: std.process.Init.Minimal) void {
    std.debug.print("tars-init: starting as PID 1\n", .{});

    // mount보다 먼저 켠다. 핸들러가 하는 일은 플래그를 세우는 것뿐이라 이
    // 시점에 달아도 안전하고, "PID 1은 태어날 때부터 시그널을 안다"가 읽기에
    // 맞다. 이 호출 전까지 커널은 PID 1에게 온 SIGTERM을 조용히 버린다.
    power.install();

    // install()보다 뒤여야 한다. 순서가 뒤집히면 그 사이의 짧은 창에서
    // 눌린 Ctrl+Alt+Del이 핸들러 없는 SIGINT로 도착한다. PID 1이라 커널이
    // 버려 주므로 사고는 안 나지만, "키를 빼앗기 전에 받을 준비를 끝낸다"가
    // 읽기에 맞다.
    power.disableCtrlAltDel();

    _ = mountFs("proc", "/proc", "proc", 0);
    _ = mountFs("sysfs", "/sys", "sysfs", 0);
    _ = mountFs("devtmpfs", "/dev", "devtmpfs", 0);
    mountDevpts();

    const storage_mounted = mountConfig();
    var cfg = loadConfig(storage_mounted);
    // SC-M2 결정 9 — 탈출로 2. **cmdline > tars.conf > 기본값.**
    //
    // 이 키 하나만 이 예외를 갖는다. 근거는 *"`tars.conf`를 고칠 셸이 없을
    // 때 쓰는 것"*이다 — 사용자의 rc가 셸을 죽이거나 매달리게 만들면 설정을
    // 고칠 자리가 통째로 사라진다(design 위험 3). 실기는 limine 메뉴를
    // 지나므로 사람이 부팅 순간에 이 단어를 적어 넣을 수 있다(실측 12).
    //
    // **`loadConfig` 바로 뒤인 것이 중요하다.** 아래의 `config shell=` 로그
    // 줄과 argv 배선이 전부 `cfg`를 보므로, 여기서 덮으면 그 뒤는 아무것도
    // 안 고쳐도 된다 — 게이트도 그 한 줄에서 **실효값**을 읽는다.
    //
    // **매달리는 rc까지 덮는 것이 탈출로 1과 다른 점이다**(결정 8은 자식이
    // 죽어야 발동한다). 대가는 사람이 부팅 순간에 개입해야 한다는 것이고,
    // 그래서 둘이 서로를 대체하지 않는다.
    if (config.cmdlineNoConfig(config.CMDLINE_PATH)) {
        // **크게 찍는다.** 이 줄이 없으면 "설정 파일에는 on이라고 적혀 있는데
        // 왜 rc가 안 읽히지"가 영영 안 풀린다.
        std.debug.print("tars-init: {s} on the kernel command line beats {s}, shell_config=off\n", .{
            config.NO_CONFIG_TOKEN, CONFIG_PATH,
        });
        cfg.shell_config = .off;
    }
    // SC-M1 결정 7. **`loadConfig`보다 뒤이고 자식을 띄우기보다 앞이다** —
    // 앞이어야 하는 이유는 이 부팅의 셸이 곧바로 이 파일을 읽기 때문이고,
    // `loadConfig` 뒤인 이유는 `tars.conf`의 씨앗이 먼저 생기는 편이 로그의
    // 순서로 읽기에 맞기 때문이다(둘 사이에 의존은 없다).
    //
    // **`cfg`를 안 넘긴다.** 씨앗은 `shell_config`도 `shell`도 안 본다 —
    // 그 근거는 `config.seedRcFiles`의 주석에 있다.
    if (storage_mounted) {
        config.seedRcFiles();
        // SM-M2 결정 9. **씨앗 rc와 같은 조건이다** — 디스크가 붙은 기계에만
        // 우리가 만든다. 값(`XDG_DATA_HOME`)은 조건 없이 주고 디렉터리만
        // 여기서 만드는 것이 비대칭으로 보이지만, 그 비대칭이 결정 9 그
        // 자체다: **에러가 안 나는 것이 화면 좌표를 지키는 것이다.**
        makeXdgDir();
    }
    // **줄을 새로 만들지 않고 이 줄을 넓힌다**(HI-M2). 다른 체인들이
    // `tars-init: config shell=`로 grep하고 있어서 앞부분이 안 바뀌어야 한다.
    //
    // 이 배열이 argv로도 간다. **`main()`의 스택에 살고 `supervise()`가 영영
    // 반환하지 않으므로** 프로세스 수명 내내 유효하다 — `keyboard_path`와
    // 같은 근거다.
    var toggle_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    const toggle_arg = cfg.hangul_toggle.arg(&toggle_buf);
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s}\n",
        .{
            @tagName(cfg.shell),
            @tagName(cfg.keyboard),
            @tagName(cfg.hangul_layout),
            @tagName(cfg.latin_layout),
            toggle_arg,
            @tagName(cfg.shell_config),
        },
    );

    logDrmDevicePresence();

    // sysfs를 붙인 뒤여야 한다(:332). 이 값은 main()의 스택에 살고,
    // supervise()가 영영 반환하지 않으므로 argv에 넣은 포인터가 뜨지 않는다.
    var keyboard_path = devices.Path{};
    devices.resolveKeyboard(devices.SYS_INPUT, &keyboard_path);

    // 전원 버튼은 PID 1이 직접 연다(design 결정 7). terminal이 읽는 안은
    // 물렸다 — 자식이 전부 포기 상태여도 버튼은 살아 있어야 하고, 하필 다
    // 망가졌을 때 눌러야 하는 것이 전원 버튼이기 때문이다. BF 체인처럼
    // /dev/dri/card0이 없어 감독자가 terminal을 포기한 상태가 정확히 그
    // 경우다.
    //
    // keyboard_path와 마찬가지로 이 배열은 main()의 스택에 살고, supervise()가
    // 영영 반환하지 않으므로 프로세스 수명 내내 유효하다.
    var button_fds: [devices.MAX_BUTTONS]i32 = undefined;
    const button_count = devices.openPowerButtons(devices.SYS_INPUT, &button_fds);

    // 설정이 실제 동작이 되는 유일한 자리. 여기서 한 번 정해지면 감독 루프는
    // 설정을 모른 채 이 값을 반복해서 띄운다 — 재시작이 설정을 다시 읽지
    // 않는다는 뜻이고, "고치고 재부팅해야 반영된다"는 정책이 그래서 지켜진다.
    const shell = resolveShell(cfg.shell);
    const shell_path = shell.path();

    // ── env 블록은 여기서 짓는다(SM-M2) ──────────────────────────────────
    //
    // **UT-M0에서는 `main()`의 첫 줄이었다.** 내려온 이유는 `HISTFILE`이
    // 셸마다 다른 파일이어야 하기 때문이다(결정 3) — 그 값을 알려면 설정을
    // 읽고 `resolveShell`이 끝나 있어야 한다.
    //
    // **`cfg.shell`이 아니라 `shell`을 보는 것이 중요하다.** `tars.conf`가
    // zsh라고 적어도 initrd에 zsh가 없으면 실제로 도는 것은 fish이고, 그때
    // `HISTFILE=/config/zsh_history`를 주면 **아무도 안 읽는 파일 이름을 env에
    // 심는 것**이 된다. 폴백 뒤의 값을 쓰면 로그의 `config shell=`과 여기가
    // 언제나 같은 셸을 말한다.
    //
    // **이 버퍼가 `main()`의 스택에 있는 것이 중요하다.** `supervise()`가 영영
    // 반환하지 않으므로 프로세스 수명 내내 유효하다 — `keyboard_path`·argv와
    // 같은 근거다. 자식은 fork 뒤 execve로 이 포인터를 읽는다.
    var env_buf: environ.Block = undefined;
    const envp = environ.withTarsEnv(
        init.environ.block.slice.ptr,
        &env_buf,
        shell.histEntries(),
    );

    // UT-M0: 게이트가 "블록을 제대로 지었는가"를 보는 자리. 자식 둘이 같은
    // 블록을 받는다는 것은 `supervise()`가 `start(c, envp)`를 한 루프에서
    // 부르는 코드 구조가 보장한다.
    //
    // withTarsEnv가 자리 부족으로 폴백했으면 이 줄들이 안 나온다. 그 침묵이
    // 곧 판정이다.
    //
    // **`tools/check.sh:233`이 `tars-init: env PATH=/usr/bin:/bin`을 그대로
    // grep한다** — 그래서 PATH가 이 줄의 맨 앞에 남아 있어야 한다.
    if (envp != init.environ.block.slice.ptr) {
        std.debug.print("tars-init: env {s} {s}\n", .{
            environ.PATH_ENTRY, environ.XDG_ENTRY,
        });
        // 셸마다 갈리는 것은 줄을 따로 낸다. `shell=fish`면 한 줄도 안 나오고,
        // **그 침묵이 결정 3의 절반**(fish는 XDG 하나로 끝난다)을 로그에서
        // 읽는 법이다.
        for (shell.histEntries()) |entry| {
            std.debug.print("tars-init: env {s}\n", .{entry});
        }
    } else {
        std.debug.print("tars-init: env unchanged (no room for PATH)\n", .{});
    }

    // SC-M0 결정 3. `off`면 지금까지의 플래그이고, `on`이면 `"none"`이다 —
    // terminal이 그 값을 보면 셸 argv에 아무것도 안 붙인다.
    const shell_flag = shell.configFlag(cfg.shell_config);
    // **콘솔 셸은 `"none"`을 안 쓴다**(결정 4). 이쪽은 init이 셸을 직접
    // exec하므로 argv를 짓는 쪽과 쓰는 쪽이 같다 — "인자가 없다"를 null
    // 슬롯으로 그대로 말할 수 있다. 지금까지 이 자리는 **조건 없이 null**
    // 이었고, `main.zig`의 아래 주석이 *"나중에 설정 파일이 생기면 그것을
    // 읽는 편이 맞다"*고 예고해 둔 자리다.
    const console_flag: ?[*:0]const u8 = switch (cfg.shell_config) {
        .on => null,
        .off => shell.noConfigFlag().ptr,
    };
    // SC-M2 결정 8 — 탈출로 1. **자식 둘 다에게 준다**(결정 4가 두 셸을 같은
    // 설정으로 묶은 것의 연장이다).
    //
    // **`storage_mounted`를 함께 보는 것이 이 조건의 핵심이다.** 디스크가 안
    // 붙은 부팅에는 rc 실체가 아예 없다 — 홈의 링크는 끊어져 있고 셸은
    // 아무것도 안 읽는다(SC-M0이 여섯 체인에서 확인한 정상 경로다). 그런
    // 기계에서 자식이 죽는 이유는 rc가 아니고, **고칠 수 있는 것이 없는데
    // 다시 띄우는 것은 탈출이 아니라 소음이다.**
    //
    // 그리고 그 소음은 남의 검사를 깬다: BF 체인은 `-vga none`이라 terminal이
    // 매번 죽고, `boot/check.sh`가 그 재시작 횟수를 **정확히 3**으로 세고
    // 있다(그 수가 곧 `MAX_FAST_RESTARTS` 정책이다). 조건 없이 주면 6이 된다.
    //
    // `off`일 때 안 주는 이유는 단순하다 — 이미 rc를 안 읽는 셸에서 뺄 것이
    // 없다.
    const rescue_flag: ?[:0]const u8 = if (storage_mounted and cfg.shell_config == .on)
        shell.noConfigFlag()
    else
        null;
    // 셸과 달리 폴백 검사(resolveShell 같은 것)가 없다. 키보드 종류는
    // 파일시스템에 존재를 확인할 대상이 아니고, enum이 이미 화이트리스트다.
    const keyboard_arg = cfg.keyboard.arg();
    // 자판 둘도 같은 성질이다 — enum이 화이트리스트이고, 확인할 파일이 없다
    // (HI design 결정 7). 런타임 전환이 없으므로 여기서 한 번 정해진다.
    const hangul_arg = cfg.hangul_layout.arg();
    const latin_arg = cfg.latin_layout.arg();

    var children = [_]Child{
        .{
            .kind = .terminal,
            .path = TERMINAL_PATH,
            // terminal은 설정 파일을 읽지 않는다. 어느 셸을 PTY에 띄울지와
            // 어느 키보드인지를 PID 1이 정해서 인자로 넘긴다 — 파서가 두
            // 벌이 되면 두 프로세스가 서로 다른 답을 얻을 수 있다.
            //
            // 넷째 자리를 쓰는 것이 안전한 이유는 terminal이 셸에 넘기는
            // argv를 {shell_path, shell_flag} 둘로 따로 조립하기 때문이다 —
            // 이 인자는 셸로 새지 않는다.
            .argv = .{
                TERMINAL_PATH.ptr,
                shell_path.ptr,
                shell_flag.ptr,
                keyboard_arg.ptr,
                keyboard_path.cstr(),
                hangul_arg.ptr,
                latin_arg.ptr,
                toggle_arg.ptr,
            },
            .rescue = if (rescue_flag) |f| .{ .slot = TERMINAL_FLAG_SLOT, .flag = f } else null,
        },
        .{
            .kind = .console_shell,
            .path = shell_path,
            // **위 주석이 예고한 것을 SC-M0이 실행한 자리다.** 그때 적어
            // 둔 것은 *"나중에 설정 파일이 생기면 그것을 읽는 편이 맞다"*
            // 였고, 이제 설정 파일이 생겼다. `on`이면 이 슬롯이 null이라
            // 지금까지와 같고, `off`면 플래그가 들어간다 — **두 셸이 같은
            // 설정을 따른다**(결정 4).
            .argv = .{ shell_path.ptr, console_flag, null, null, null, null, null, null },
            .rescue = if (rescue_flag) |f| .{ .slot = CONSOLE_FLAG_SLOT, .flag = f } else null,
        },
    };
    supervise(&children, button_fds[0..button_count], envp);
}
