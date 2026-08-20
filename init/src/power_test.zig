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
    //    Ctrl+Alt+Del은 reboot(CAD_OFF) 뒤에 **SIGINT로** 도착하므로
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
}
