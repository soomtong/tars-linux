---
name: project_workspace_panes
description: 화면 하나가 셸 여럿을 담는다 — 워크스페이스(탭) 아홉 × 패널 여덟, 키는 iTerm2 그대로. 패널 하나가 PTY · vt.Screen · 사각형이고 키보드는 포커스 패널에만 간다(WP-M0~M2, 2026-10-04 종료). 열여덟번째 체인 pane/check.sh
metadata:
  type: project
---

Workspace Panes(WP)는 2026-10-03~04에 M0~M2로 닫혔다. 사용자의 요청 네
줄("Cmd+1~9 workspace 전환, Cmd+D · Cmd+Shift+D pane split" · "닫는 것은
Cmd+W" · "포커스 이동도 필요" · "Cmd+T 새 탭")에서 시작했고, 모델은 iTerm2
그대로다 — 워크스페이스가 탭(아홉), 각 워크스페이스는 패널을 이진 분할로
여덟까지, 패널 하나가 셸 하나(PTY · `vt.Screen` · 격자 안 사각형).
design은 `docs/specs/2026-10-03-tars-workspace-panes-design.md`.

이 서브프로젝트는 설계를 Fable이, 구현을 Opus 서브에이전트가 했다(사용자의
지시, 2026-10-03). 서브에이전트는 commit하지 않고 diff · 로그만 보고하고,
lead가 파일을 직접 대조한 뒤 commit했다 — "만들었다"는 보고와 실제 파일이
어긋난 적은 세 milestone에서 없었다.

구조에서 배운 것:

- 본론은 새 기능이 아니라 "하나였던 것을 N개로"였다. `main.zig`가 변수로
  들던 `screen` · `session`이 `Pane`의 필드가 되고, 키 · copy · 프롬프트 ·
  덤프는 `focus.screen`으로 이름만 바뀌었다. 바뀌는 자리는 둘뿐이다 — `poll`이
  패널마다 fd를 보는 것(매 바퀴 배열을 다시 짓는다)과 `render`가 패널마다
  도는 것. M0은 눈에 보이는 변화 0으로 그것을 증명했다.
- 레이아웃 산수는 순수 `layout.zig`다(`status.zig`와 같은 이유 — 호스트에서
  초 단위). 잎 번호(0..7)와 노드 번호(0..14)를 갈라야 분할이 기존 패널의
  번호를 안 바꾼다. 트리는 크기를 모르므로 `split`이 격자 사각형을 받는다
  (아래로 다섯 번 가르면 47 → 23 → 11 → 5 → 2로 실제로 닿는 경계).
- 원점 산수는 `paneOrigin(rect)` 하나다. 그리는 쪽과 프레임버퍼를 되읽는
  덤프 넷이 같은 함수를 부르므로 둘이 다른 원점을 볼 수 없다.
- 닫기는 길이 하나다. `Cmd+W`는 SIGHUP 한 줄이고(zsh · bash는 SIGTERM을
  무시한다, [[project_shutdown_signals]]), 닫힘은 PTY EOF 경로가 한다 —
  `exit`를 친 것과 같은 코드. 거두는 것은 `waitpid`(terminal이 살아
  있으므로 좀비가 생긴다).
- 크기가 바뀐 패널만 다시 잰다(`applyLayout`). 분할 뒤와 닫기 뒤를 규칙
  하나가 덮는다. 크기가 바뀌는 패널은 copy mode를 닫는다 — reflow가 pin을
  옮기는 것은 CM-M1이 가지치기에서 배운 병과 같다([[project_copy_mode]]).
- copy mode 안에서는 패널 명령이 없다. `handleKey`의 copy 분기가 `chord`
  보다 앞이라 코드를 안 고치고 그렇게 됐고, 덕분에 "copy mode인 패널을
  떠났다 돌아오면"이라는 물음이 안 생긴다.
- 워크스페이스를 지워 배열이 당겨지면 같은 바퀴의 `PaneRef.ws`가 낡는다.
  지운 직후 PTY 루프를 끊는다 — 안 읽은 출력은 다음 `poll`이 다시 알린다.

게이트에서 배운 것:

- "크기를 바꿨다"는 셀 수가 아니라 셸이 아는 폭으로만 증명된다. `pty.resize`
  (`TIOCSWINSZ`)를 빼도 짧은 `echo`는 77칸 안에서 똑같이 보여 plan의
  검사만으로는 초록이었다. fish의 `$COLUMNS`를 화면에 찍게 하자 mutation이
  `left-side 155`로 빨개졌다(M1 실측 2).
- "terminal이 살았다"를 `pane>` 줄로 보면 안 된다. 죽은 terminal을 init이
  되살리면 새 첫 프레임이 같은 줄을 찍는다. `spawned child pid` 수로 본다
  (M2 실측 1).
- 글자가 맞고 색만 밀리는 고장(`W2` 칸만큼 안 물러난 `drawStatus`)은
  `caps ink off=`가 잡는다 — CI가 `copy ink`로 잡은 것과 같은 병
  ([[project_copy_indicator]]).
- `screen>`은 포커스 패널만 찍는다. 패널 하나면 바이트까지 같아서 열일곱
  체인이 안 흔들렸다. 포커스를 옮긴 뒤의 음성 판정은 `wait_for_screen`
  (로그 전체)이 아니라 마지막 `screen>` 줄 하나로 본다
  ([[project_gate_screen_echo]]).

열지 않은 것: M3 방향 포커스(`Cmd+Option+화살표`, `Tree.neighbor`), 패널 간
클립보드(지금은 `vt.Screen`마다 하나 — CB가 2026-10-05에 `main.zig`로 올렸다,
[[project_clipboard_scope]]), 비율 조절, 세션 복원. M1이 바꾼
`Cmd+Shift+←·→·Backspace`(Shift를 무시하던 것이 맨 키로)는 사용자가 그대로
두기로 했다.
