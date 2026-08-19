const std = @import("std");
const linux = std.os.linux;

/// main.zig와 config.zig에도 같은 함수가 있다. 이것이 **세 벌째**다.
/// config.zig:4가 "다섯 개쯤 되면 sys.zig로 모은다"고 적어 뒀고, 아직
/// 다섯이 아니므로 그 판단을 유지한다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// PID 1이 시그널을 받고 하기로 한 일. PM-M0은 끄는 것 하나뿐이고,
/// PM-M1에서 SIGINT가 restart를 더한다.
pub const Action = enum(u8) {
    power_off = 1,
};

/// 시그널 핸들러가 만질 수 있는 유일한 상태. 0은 "요청 없음"이다.
var pending: u8 = 0;

/// 시그널 핸들러 안에서는 재진입 안전하지 않은 것을 부를 수 없다. 우리 로그
/// 함수(std.debug.print)가 바로 그런 것이므로, 핸들러는 정수 하나를 남기고
/// 즉시 돌아온다. 로그는 깨어난 감독 루프가 찍는다.
fn onSignal(sig: linux.SIG) callconv(.c) void {
    const action: Action = switch (sig) {
        .TERM => .power_off,
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
    std.debug.print("tars-init: signal handlers installed (TERM)\n", .{});
}

/// 밀린 요청을 꺼내면서 지운다. 감독 루프가 매 바퀴 부른다.
pub fn take() ?Action {
    const raw = @atomicRmw(u8, &pending, .Xchg, 0, .seq_cst);
    if (raw == 0) return null;
    return @enumFromInt(raw);
}
