---
name: project_shutdown_latency
description: PID 1이 SIGTERM 뒤에 SIGHUP도 보낸다. 콘솔 셸이 유예를 꽉 쓰던 2.9초가 0.13초가 됐다
metadata:
  type: project
---

2026-09-13에 SL-M0~M2가 했다. 고친 자리는 `init/src/power.zig`의
`shutdown()` 한 함수이고, 들어간 것은 상수 하나와 `for` 한 줄이다.

```zig
pub const TERMINATION_SIGNALS = [_]linux.SIG{ .TERM, .HUP };
```

## 무엇이 문제였나

`shutdown()`이 `kill(-1, .TERM)`만 보냈다. 대화형 zsh와 bash는 SIGTERM을
무시하므로(POSIX) 콘솔 셸이 유예를 꽉 쓴 뒤 SIGKILL에 죽었다. 그래서 모든
종료가 2.9초였다.

자식 둘이 갈린 이유는 제어 터미널이다. 화면 셸의 PTY 주인은 `terminal`이고
`terminal`에는 시그널 핸들러가 없어서 SIGTERM에 먼저 죽는다 — 그 순간 PTY가
닫혀 커널이 안쪽 셸에 SIGHUP을 보낸다. 콘솔 셸은 `/dev/console`을
`setsid` + `TIOCSCTTY`로 잡으므로 닫힐 PTY가 없고, 그 통지를 못 받았다.

그래서 이 변경은 "셸을 죽이는 더 센 수단을 쓴다"가 아니라 "커널이 한쪽에만
해 주던 통지를 양쪽에 한다"이다.

## 잰 값

`system_powerdown`부터 `reboot(POWER_OFF)` 직전까지. 단위는 밀리초.

| 셸 | 전 | 후 |
|---|---|---|
| fish | 138 | 135 |
| zsh | 2525 | 133 |
| bash | 2516 | 126 |

## 다시 조사하지 말 것 넷

1. fish는 SIGTERM에 죽는다. "대화형 셸은 SIGTERM을 무시한다"가 셋 다에
   해당하지 않는다 — SD-M0이 zsh로만 재서 생긴 일반화였다.
   [[project_shutdown_signals]]의 첫 항목에 정정을 달았다. 게스트의 기본
   셸이 fish이므로 설정 디스크 없이 뜨는 부팅은 원래부터 빨랐다.

2. `GRACE_SECONDS = 3`은 상한이지 실제 대기가 아니다. `reapAll()`의
   deadline이 `monotonicSeconds() + 3`인데 그 함수가 초 단위로 자르므로,
   끝까지 가더라도 실제 대기가 2~3초 사이에서 흔들린다. 관측값이 타이핑
   없는 회차 2495~2506, 타이핑 둘 있는 회차 2895~2898이었다.

3. 남는 130밀리초 중 100은 `reapAll()`의 `sleepMillis(100)` 한 번이다.
   자식은 `kill` 직후에 죽는데 첫 `waitpid`가 그보다 먼저 돌아 0을 받는다.
   더 줄이려면 폴링을 짧게 해야 하고, 그것은 안 한다.

4. 게이트는 안 빨라진다. 체인 열하나에서 정상 종료를 밟는 부팅이 셋뿐이고
   (`device` 하나 · `power` 둘) 그중 `device`는 fish라 원래 유예를 안 썼다.
   나머지 부팅은 전부 `kill "$QEMU_PID"`로 전원을 뽑는다. 이론상 절약이
   2 × 2.5초 × 3회차 = 약 15초이고 이 게이트의 잡음이 ±3분이다.

## 게이트가 지키는 것

`power/check.sh` 부팅 1에 음성 검사 둘이 섰다 — `grace period expired`가
없을 것, `sent SIGKILL to what was left`가 없을 것. 그 자리는 원래
`note:`만 찍고 어느 쪽이든 통과시키던 `if`/`else`였다.

양성 `sent SIGHUP to every process`는 세 자리가 본다(`power` 부팅 둘 ·
`device`). `device`에 음성을 안 넣은 이유는 위의 1번이다 — fish는 SIGHUP을
빼도 유예를 안 쓰므로 거기 넣은 음성은 아무것도 안 막는다.

반사실에서 배운 것이 하나 있다. 겨냥한 검사가 아니라 앞의 검사가 죽는다 —
`.HUP`을 뺀 사본은 음성 5가 아니라 양성 검사에서 죽었다(양성이 목록에서
앞이다). 음성을 겨냥하려면 "로그는 찍되 실제로는 안 보내는" 사본이 따로
필요했다.

본문은 `docs/superpowers/specs/2026-09-13-tars-shutdown-latency-design.md`.

관련: [[project_shutdown_signals]] · [[project_power_management]] ·
[[project_init_supervisor]] · [[project_shell_history]]
