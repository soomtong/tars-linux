---
name: project_shutdown_signals
description: 대화형 셸은 SIGTERM을 무시한다. 종료 경로에서 무엇이 저장되는지는 누가 먼저 죽는지에 갈린다
metadata:
  type: project
---

TARS의 종료 경로는 `init/src/power.zig`의 셋이다 — `kill(-1, .TERM)` →
`GRACE_SECONDS = 3` → `kill(-1, .KILL)`. 이 셋을 놓고 *"셸이 나갈 때 하는
일"*(히스토리 저장 같은 것)이 일어나는지를 판단할 때 틀리기 쉽다.

2026-09-12에 SD-M0이 컨테이너와 게스트에서 쟀고, 다음 넷이 나왔다.

1. 대화형 셸은 자기에게 온 SIGTERM을 무시한다. zsh는 받고도 살아서 다음
   명령을 실행했다. `power.zig:178`의 주석이 이것을 이미 적고 있었다.
2. SIGHUP에서는 죽으면서 자기 정리 동작을 한다.
3. 셸 위의 PTY 주인이 죽으면 커널이 안쪽 셸에게 SIGHUP을 보낸다. 그래서
   같은 SIGTERM이 대상에 따라 정반대의 결과를 낸다.
4. 그 결과 TARS의 두 자식이 갈린다. 화면 셸은 PTY 주인이 `terminal`이고
   `terminal`에는 시그널 핸들러가 하나도 없어서 먼저 죽는다 — 그 순간 PTY가
   닫혀 셸이 SIGHUP을 받는다. 콘솔 셸은 `/dev/console`을 `setsid` +
   `TIOCSCTTY`로 잡으므로 닫힐 PTY가 없고, SIGTERM을 무시한 채 3초를 버틴 뒤
   SIGKILL에 죽는다.

게스트에서 전원 버튼을 눌러 확인한 값: 화면 셸에 친 명령은 히스토리에 남고
(`grep -c` 1) 콘솔 셸에 친 명령은 사라진다(0). 그 명령이 실제로 실행된 것은
시리얼 로그의 입력 줄과 출력으로 먼저 확인했다 — 그 증거가 없으면
*"잃었다"*와 *"애초에 안 쳐졌다"*가 안 갈린다.

여기서 따라 나오는 것 셋.

- 화면 셸이 무언가를 저장할 수 있는 것은 설계가 아니라 우연이다.
  `terminal`에 핸들러를 달아 정리 코드를 넣으면(언젠가 그럴 만한 이유가
  생긴다) 그 변경과 아무 상관 없는 저장이 함께 사라진다.
- 모든 종료가 `GRACE_SECONDS`를 꽉 쓴다. 셸이 TERM에 안 죽으므로 3초를
  기다린 뒤 KILL이 나간다.
- PID 1이 SIGHUP을 보내게 바꾸면 zsh와 fish는 고쳐지지만 bash는 안 고쳐진다
  (bash는 `exit` 말고는 전부 잃는다). 그리고 PM·BF 체인이 종료 로그와 감독
  루프의 계약을 판정에 쓰므로 그 변경은 체인을 다시 여는 일이다. SD는 이
  후보를 안 골랐다 — 근거는 SD design 결정 8.

SM design이 이 자리를 *"실기는 안전하다. 전원 버튼을 누르면 PID 1의 SIGTERM이
셸에게 가고 그때 zsh가 스스로 쓴다"*로 적었고 세 군데가 틀렸다. 그 문서의
실측 10·34와 결정 3·위험 3에 정정 블록을 달아 두었다. 본문은
[[project_shell_memory]]와 SD design에 있다.

관련: [[project_power_management]] · [[project_init_supervisor]] ·
[[project_shell_memory]]
