---
name: project_shutdown_latency
description: PID 1이 SIGTERM 뒤에 SIGHUP도 보낸다(SL-M0~M2, 2026-09-13). 콘솔 셸이 유예를 꽉 쓰던 2.9초가 0.13초가 됐다 — 남는 130ms 중 100은 reapAll의 sleepMillis(100)
metadata:
  type: project
---

2026-09-13에 SL-M0~M2가 했다. 고친 자리는 `init/src/power.zig`의 `shutdown()` 한 함수이고, 들어간 것은 상수
하나와 `for` 한 줄이다.

```zig
pub const TERMINATION_SIGNALS = [_]linux.SIG{ .TERM, .HUP };
```

왜 TERM 하나로는 콘솔 셸이 안 죽었는지(PTY가 없어 커널의 SIGHUP을 못 받는다)는 [[project_shutdown_signals]].
셸별 사실은 measurements 22 · 36 · 37.

## 잰 값

`system_powerdown`부터 `reboot(POWER_OFF)` 직전까지. 단위는 밀리초.

| 셸 | 전 | 후 |
|---|---|---|
| fish | 138 | 135 |
| zsh | 2525 | 133 |
| bash | 2516 | 126 |

남는 130밀리초 중 100은 `reapAll()`의 `sleepMillis(100)` 한 번이다. 자식은 `kill` 직후에 죽는데 첫 `waitpid`가
그보다 먼저 돌아 0을 받는다. 더 줄이려면 폴링을 짧게 해야 하고, 그것은 안 한다. 게이트 시간은 안 줄었다 —
정상 종료를 밟는 부팅이 `device` 하나 · `power` 둘뿐이고 `device`는 fish라 원래 유예를 안 썼다.

## 게이트가 지키는 것

`power/check.sh` 부팅 1의 음성 검사 둘(`grace period expired` · `sent SIGKILL to what was left`가 없을 것)과 세
자리의 양성 `sent SIGHUP to every process` — 자리와 `device`에 음성이 없는 이유는 `docs/guides/key-files.md`의
`power/check.sh` 항목. mutation이 겨냥한 음성 검사가 아니라 앞의 양성 검사에서 죽은 일은 `docs/guides/dead-ends.md`의
SL-M2 항목.

본문은 `docs/specs/2026-09-13-tars-shutdown-latency-design.md`.

관련: [[project_shutdown_signals]] · [[project_power_management]] · [[project_init_supervisor]] · [[project_shell_history]]
