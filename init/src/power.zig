const std = @import("std");
const linux = std.os.linux;

/// main.zig와 config.zig에도 같은 함수가 있다. 이것이 **세 벌째**다.
/// config.zig:4가 "다섯 개쯤 되면 sys.zig로 모은다"고 적어 뒀고, 아직
/// 다섯이 아니므로 그 판단을 유지한다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// PID 1이 시그널을 받고 하기로 한 일. 값이 0이 아닌 이유는 pending의 0이
/// "요청 없음"을 뜻하기 때문이다.
pub const Action = enum(u8) {
    power_off = 1,
    restart = 2,
};

/// 시그널 핸들러가 만질 수 있는 유일한 상태. 0은 "요청 없음"이다.
var pending: u8 = 0;

/// 시그널 핸들러 안에서는 재진입 안전하지 않은 것을 부를 수 없다. 우리 로그
/// 함수(std.debug.print)가 바로 그런 것이므로, 핸들러는 정수 하나를 남기고
/// 즉시 돌아온다. 로그는 깨어난 감독 루프가 찍는다.
fn onSignal(sig: linux.SIG) callconv(.c) void {
    const action: Action = switch (sig) {
        .TERM => .power_off,
        .INT => .restart,
        else => return,
    };
    @atomicStore(u8, &pending, @intFromEnum(action), .seq_cst);
}

/// 시그널 처리를 켠다. 이 함수를 부르기 전까지 PID 1에게 보낸 SIGTERM은
/// **커널이 조용히 버린다** — 기본 동작(종료)이 PID 1에 적용되면 곧바로
/// 커널 패닉이 되기 때문에 커널이 미리 막아 놓았다. 그래서 이 한 번의
/// 호출이 곧 "게스트에서 전원을 다룰 수 있다"는 기능 자체다.
pub fn install() void {
    const act: linux.Sigaction = .{
        .handler = .{ .handler = onSignal },
        .mask = linux.sigemptyset(),
        // SA_RESTART를 켜지 않는다. 켜면 커널이 supervise의 waitpid를 안에서
        // 자동 재시작해버려서, 플래그를 세워도 루프 머리로 영영 돌아오지
        // 못한다. 끄면 그 waitpid가 EINTR로 깨어나고, supervise의 errno
        // 분기(`if (e == .INTR) continue;`)가 이미 그것을 받고 있다.
        .flags = 0,
    };
    if (failed(linux.sigaction(.TERM, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGTERM handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    // 같은 act를 그대로 재사용한다. 두 시그널이 하는 일은 "정수 하나를
    // 남긴다"로 동일하고, 무엇을 남길지는 onSignal 안에서 갈린다.
    if (failed(linux.sigaction(.INT, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGINT handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    std.debug.print("tars-init: signal handlers installed (TERM, INT)\n", .{});
}

/// 밀린 요청을 꺼내면서 지운다. 감독 루프가 매 바퀴 부른다.
pub fn take() ?Action {
    const raw = @atomicRmw(u8, &pending, .Xchg, 0, .seq_cst);
    if (raw == 0) return null;
    return @enumFromInt(raw);
}

/// 자식에게 주는 유예. 감독 루프의 재시작 backoff가 1초이고 우리 자식은
/// 터미널과 셸뿐이라 정리에 이보다 오래 걸릴 일이 없다.
const GRACE_SECONDS: isize = 3;

fn monotonicSeconds() isize {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
    return ts.sec;
}

fn sleepMillis(ms: isize) void {
    const req = linux.timespec{
        .sec = @divTrunc(ms, 1000),
        .nsec = @rem(ms, 1000) * 1_000_000,
    };
    _ = linux.nanosleep(&req, null);
}

/// 자식이 전부 사라질 때까지 거둔다. 다 거뒀으면 true, 유예가 끝났으면
/// false.
///
/// WNOHANG이라 살아 있는 자식이 있으면 0을 돌려주고 즉시 반환한다. 그래서
/// "잠깐 자고 다시 묻는" 모양이 된다 — 그냥 blocking waitpid를 쓰면 죽지
/// 않는 자식 하나 때문에 영영 못 나온다. 대화형 셸이 정확히 그런
/// 자식이다(SIGTERM을 무시한다).
fn reapAll() bool {
    const deadline = monotonicSeconds() + GRACE_SECONDS;
    var reaped: usize = 0;
    while (true) {
        var status: u32 = 0;
        const rc = linux.waitpid(-1, &status, linux.W.NOHANG);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                // rc가 0이면 "살아 있지만 아직 안 죽었다"이므로 아래로 간다.
                if (rc != 0) {
                    reaped += 1;
                    continue;
                }
            },
            .CHILD => {
                std.debug.print("tars-init: every child is gone (reaped {d})\n", .{reaped});
                return true;
            },
            // EINTR 등. 아래에서 기다렸다가 다시 묻는다.
            else => {},
        }
        if (monotonicSeconds() >= deadline) {
            std.debug.print("tars-init: grace period expired (reaped {d})\n", .{reaped});
            return false;
        }
        sleepMillis(100);
    }
}

/// 시스템을 끈다. **절대 반환하지 않는다** — supervise가 noreturn인 것과
/// 같은 이유이고, 그보다 하나 더 있다. 이 함수가 도는 동안 감독 루프로
/// 돌아가면 "안 떠 있는 자식을 띄운다"는 규칙이 방금 죽인 셸을 되살린다.
/// 돌아갈 길 자체를 타입으로 막아둔다.
pub fn shutdown(action: Action) noreturn {
    std.debug.print("tars-init: shutdown requested (action {s})\n", .{@tagName(action)});

    // -1은 "자기를 제외한 모든 프로세스"다. 감독 대상 둘뿐 아니라 PTY 안에서
    // 도는 셸까지 한 번에 닿으므로 자식 목록을 순회할 필요가 없고, 리눅스가
    // 호출자를 대상에서 빼주므로 PID 1이 자기를 죽이는 일도 없다.
    _ = linux.kill(-1, .TERM);
    std.debug.print("tars-init: sent SIGTERM to every process\n", .{});

    // 대화형 셸은 SIGTERM을 무시한다(POSIX). 그래서 여기서 false가 나오는
    // 것이 정상이고, SIGKILL은 예외 처리가 아니라 정상 경로의 일부다.
    if (!reapAll()) {
        _ = linux.kill(-1, .KILL);
        std.debug.print("tars-init: sent SIGKILL to what was left\n", .{});
        _ = reapAll();
    }

    // 커널은 reboot(2)에서 sync를 대신 해주지 않는다. 리눅스 소스의
    // kernel/reboot.c:726이 "reboot doesn't sync: do that yourself before
    // calling this"라고 직접 적어 두었다. /config는 MS_SYNCHRONOUS라 그
    // 파일시스템만 보면 필요 없지만, 시스템 콜 한 번이고 다른 파일시스템에는
    // 그 보장이 없다.
    linux.sync();
    std.debug.print("tars-init: filesystems synced\n", .{});

    // RESTART는 POWER_OFF와 달리 ACPI 없이도 그대로 동작한다. 커널이
    // kernel_restart()로 들어가 "Restarting system"을 찍고(reboot.c:294)
    // 기계를 리셋한다 — QEMU에서는 -no-reboot이 없으면 정말 다시 뜬다.
    const cmd: linux.LINUX_REBOOT.CMD = switch (action) {
        .power_off => .POWER_OFF,
        .restart => .RESTART,
    };
    std.debug.print("tars-init: calling reboot({s})\n", .{@tagName(cmd)});
    _ = linux.reboot(.MAGIC1, .MAGIC2, cmd, null);

    // 여기에 도달했다는 것은 reboot(2)가 실패했다는 뜻이다. PID 1의 반환은
    // 곧 커널 패닉이므로 돌아가지 않고 여기서 쉰다.
    std.debug.print("tars-init: reboot syscall returned; PID 1 stays alive\n", .{});
    while (true) sleepMillis(1000);
}
