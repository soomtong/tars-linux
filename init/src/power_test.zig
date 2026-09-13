const std = @import("std");
const linux = std.os.linux;
const power = @import("power.zig");

/// PM-M0의 유일한 호스트 검사. 부팅 없이 판정할 수 있는 것은 "시그널이
/// 플래그가 되는가" 하나뿐이다 — 그 뒤의 종료 순서(reboot(2))는 부르는
/// 순간 이 컨테이너가 멈추므로 게스트에서만 볼 수 있다.
///
/// config_test와 같은 모양이다(호스트 아키텍처 실행 파일, 실패하면 0이
/// 아닌 종료 코드). 체인 스크립트가 둘을 똑같이 다룰 수 있어야 한다.
pub fn main() !void {
    // 1. 아직 아무 시그널도 오지 않았다.
    if (power.take() != null) {
        std.debug.print("FAIL: nothing was sent yet but take() returned something\n", .{});
        return error.UnexpectedAction;
    }

    power.install();

    // 2. 자기 자신에게 SIGTERM을 보낸다. 자기에게 보낸 시그널은 블록돼 있지
    //    않으면 kill(2)이 돌아오기 전에 배달되므로, 여기서 잠들 필요가 없다.
    _ = linux.kill(linux.getpid(), .TERM);

    const got = power.take() orelse {
        std.debug.print("FAIL: SIGTERM was delivered but no action was recorded\n", .{});
        return error.SignalNotObserved;
    };
    if (got != .power_off) {
        std.debug.print("FAIL: SIGTERM recorded {s}, want power_off\n", .{@tagName(got)});
        return error.WrongAction;
    }

    // 3. 한 번 읽으면 소비된다. 감독 루프가 매 바퀴 묻기 때문에, 남아 있으면
    //    같은 종료 요청을 두 번 처리하게 된다.
    if (power.take() != null) {
        std.debug.print("FAIL: the action was not consumed by take()\n", .{});
        return error.ActionNotConsumed;
    }

    std.debug.print("power_test: SIGTERM becomes a pending power_off action\n", .{});

    // 4. 같은 핸들러가 SIGINT를 다르게 기록해야 한다. 이것이 PM-M1의 전부다 —
    //    Ctrl+Alt+Del은 reboot(CAD_OFF) 뒤에 SIGINT로 도착하므로
    //    (kernel/reboot.c:835의 kill_cad_pid(SIGINT, 1)), 키보드 경로와
    //    `kill -INT 1` 경로가 이 한 분기로 합쳐진다.
    _ = linux.kill(linux.getpid(), .INT);

    const got_int = power.take() orelse {
        std.debug.print("FAIL: SIGINT was delivered but no action was recorded\n", .{});
        return error.SignalNotObserved;
    };
    if (got_int != .restart) {
        std.debug.print("FAIL: SIGINT recorded {s}, want restart\n", .{@tagName(got_int)});
        return error.WrongAction;
    }

    // 5. 마지막에 온 시그널이 이긴다. 감독 루프는 take()를 한 번에 하나씩만
    //    처리하므로, 두 요청이 겹치면 나중 것이 남는 편이 예측 가능하다.
    _ = linux.kill(linux.getpid(), .TERM);
    _ = linux.kill(linux.getpid(), .INT);
    const last = power.take() orelse {
        std.debug.print("FAIL: nothing was recorded after two signals\n", .{});
        return error.SignalNotObserved;
    };
    if (last != .restart) {
        std.debug.print("FAIL: TERM then INT recorded {s}, want restart\n", .{@tagName(last)});
        return error.WrongAction;
    }

    std.debug.print("power_test: SIGINT becomes a pending restart action\n", .{});

    // 6. 시그널을 거치지 않고도 같은 자리에 요청이 선다.
    //
    //    전원 버튼이 쓰는 경로다(design 결정 9). 버튼을 보고 곧바로
    //    shutdown()을 부르지 않는 이유는 종료가 시작되는 자리가 한 곳이어야
    //    나중에 읽히기 때문이고, 이 검사가 그 한 곳을 붙박는다. take()의
    //    소비 규칙도 시그널 경로와 같아야 한다.
    power.request(.power_off);

    const from_button = power.take() orelse {
        std.debug.print("FAIL: request() did not leave a pending action\n", .{});
        return error.RequestNotObserved;
    };
    if (from_button != .power_off) {
        std.debug.print("FAIL: request(power_off) recorded {s}\n", .{@tagName(from_button)});
        return error.WrongAction;
    }
    if (power.take() != null) {
        std.debug.print("FAIL: the requested action was not consumed by take()\n", .{});
        return error.ActionNotConsumed;
    }

    std.debug.print("power_test: a button press takes the same road as a signal\n", .{});

    // 7. 종료 시그널 목록에 SIGHUP이 있어야 한다.
    //
    //    호스트에서 shutdown()을 부를 수 없으므로(kill(-1)이 이 컨테이너를
    //    죽이고 reboot(2)가 개발 기계를 끈다) 이 검사가 보는 것은 데이터
    //    한 벌뿐이다. 막는 것은 하나다 — 누가 .HUP을 지우면 부팅 전에
    //    빨개진다. 진짜 판정은 power 체인에 있다(SL-M2).
    //
    //    목록을 그대로 비교하지 않고 성질만 보는 이유는 tautology를 피하려는
    //    것이다. 상수를 복사한 기대값은 상수와 함께 고쳐지므로 아무것도
    //    안 막는다.
    var hup_at: ?usize = null;
    var term_at: ?usize = null;
    for (power.TERMINATION_SIGNALS, 0..) |sig, i| {
        if (sig == .HUP) hup_at = i;
        if (sig == .TERM) term_at = i;
    }

    if (hup_at == null) {
        std.debug.print("FAIL: TERMINATION_SIGNALS has no SIGHUP; the console shell will sit out the grace period\n", .{});
        return error.NoHangupSignal;
    }
    if (term_at == null) {
        std.debug.print("FAIL: TERMINATION_SIGNALS has no SIGTERM\n", .{});
        return error.NoTermSignal;
    }

    // 8. SIGTERM이 SIGHUP보다 앞이어야 한다.
    //
    //    순서가 뒤집혀도 셸은 죽는다 — 그래서 이 검사가 없으면 아무도
    //    모르게 뒤집힌다. 앞이어야 하는 이유는 의미다(design 결정 3):
    //    정중한 요청을 먼저 보내고, SIGTERM에만 정리 코드를 단 프로그램이
    //    나중에 생겨도 그 코드가 돌게 둔다.
    if (term_at.? > hup_at.?) {
        std.debug.print("FAIL: SIGHUP comes before SIGTERM (term at {d}, hup at {d})\n", .{
            term_at.?, hup_at.?,
        });
        return error.SignalOrderReversed;
    }

    std.debug.print("power_test: the shutdown sends SIGTERM then SIGHUP\n", .{});
}
