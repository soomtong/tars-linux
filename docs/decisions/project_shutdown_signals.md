---
name: project_shutdown_signals
description: 종료 경로에서 셸이 무엇을 저장하는지는 누가 먼저 죽는지에 갈린다 — zsh · bash는 SIGTERM을 무시하고 PTY 주인이 죽을 때의 SIGHUP에 정리한다, 콘솔 셸은 그 통지를 못 받는다(SD-M0 · SL, 2026-09-12~13)
metadata:
  type: project
---

TARS의 종료 경로는 `init/src/power.zig`의 셋이다 — `TERMINATION_SIGNALS`(`.TERM` 다음 `.HUP`, SL-M1) →
`GRACE_SECONDS = 3` → `kill(-1, .KILL)`. 이 셋을 놓고 "셸이 나갈 때 하는 일"(히스토리 저장 같은 것)이
일어나는지를 판단할 때 틀리기 쉽다. 셸별 사실은 measurements 22(zsh · bash는 SIGTERM을 무시하고 SIGHUP에
정리한다, PTY 주인이 죽으면 커널이 안쪽 셸에 SIGHUP을 보낸다) · 36(fish는 SIGTERM에 죽는다) ·
37(`GRACE_SECONDS`는 상한이지 실제 대기가 아니다)이다. 여기에는 그것이 TARS에서 뜻하는 것만 둔다.

## 두 자식이 갈리는 이유

화면 셸의 PTY 주인은 `terminal`이고 `terminal`에는 시그널 핸들러가 없어서 SIGTERM에 먼저 죽는다 — 그 순간
PTY가 닫혀 커널이 안쪽 셸에 SIGHUP을 보낸다. 콘솔 셸은 `/dev/console`을 `setsid` + `TIOCSCTTY`로 잡으므로
닫힐 PTY가 없고, 그 통지를 못 받는다. SL-M1 전에는 그래서 콘솔 셸(zsh · bash)이 유예를 꽉 쓴 뒤 SIGKILL에
죽었고 모든 종료가 2.9초였다. PID 1이 TERM 뒤에 HUP을 보내는 것은 "더 센 수단"이 아니라 "커널이 한쪽에만 해
주던 통지를 양쪽에 한다"이다 — 값은 [[project_shutdown_latency]].

게스트에서 전원 버튼을 눌러 확인한 값(SD-M0): 화면 셸에 친 명령은 히스토리에 남고(`grep -c` 1) 콘솔 셸에 친
명령은 사라졌다(0). 그 명령이 실제로 실행된 것은 시리얼 로그의 입력 줄과 출력으로 먼저 확인했다 — 그 증거가
없으면 "잃었다"와 "애초에 안 쳐졌다"가 안 갈린다(`docs/guides/dead-ends.md`의 SD-M0 항목).

## 따라 나오는 것

- 화면 셸이 무언가를 저장할 수 있는 것은 설계가 아니라 우연이다. `terminal`에 핸들러를 달아 정리 코드를
  넣으면(언젠가 그럴 만한 이유가 생긴다) 그 변경과 아무 상관 없는 저장이 함께 사라진다.
- SIGHUP을 보내는 목적은 저장이 아니라 "안 기다리는 것" 하나다. SD design 결정 8이 이 후보를 안 고른 근거("bash는
  `exit` 말고는 전부 잃는다")는 SD-M1 · BH-M1이 셸 셋을 증분 쓰기로 바꿔 사라졌고, SL-M0 실측 9가 term과 hup에서
  히스토리가 같다는 것을 zsh · bash 넷으로 확인했다. 본문은 `docs/specs/2026-09-13-tars-shutdown-latency-design.md`.
- SM design의 "실기는 안전하다. 전원 버튼을 누르면 PID 1의 SIGTERM이 셸에게 가고 그때 zsh가 스스로 쓴다"는 세
  군데가 틀렸다. 그 문서의 실측 10 · 34와 결정 3 · 위험 3에 정정 블록이 있다([[project_shell_memory]]).

관련: [[project_shutdown_latency]] · [[project_power_management]] · [[project_init_supervisor]] ·
[[project_shell_history]]
