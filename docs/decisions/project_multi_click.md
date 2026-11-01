---
name: project_multi_click
description: "더블클릭은 단어, 트리플클릭은 줄을 골라 떼면 복사하는 서브프로젝트(MC-M0~M2, 2026-11-01). 횟수는 우리 pointer.Gesture가 세고(라이브러리 SelectionGesture는 안 쓴다), 시각은 EVIOCSCLOCKID로 단조 시계를 고른 ev.time이다. 단어 앵커는 tracked pin 하나. 게이트는 hmp를 기다림 없이 이어 보내야 한다"
metadata:
  node_type: memory
  type: project
---

# Multi Click (MC)

design은 `docs/specs/2026-11-01-tars-multi-click-design.md`, plan은 `docs/plans/2026-11-01-tars-multi-click-mc-m{0,1,2}.md`.
2026-11-01에 사용자가 HANDOFF의 PD 비목표 셋(더블클릭 · 휠 방향 · 포인터 가속)에서 골랐다. 같은 자리에서 정한 것: 범위는 더블 +
트리플(Shift 클릭 늘리기는 MC 비목표 1), 뗌은 곧바로 복사(끌기와 같은 "뗌 = 클립보드 + copy mode 종료").

## 무엇이 섰나

- `pointer.Gesture`가 지난 누름을 `Last`로 기억한다. 반복의 조건 넷 — 앞 누름과 0~500ms(`MULTI_CLICK_US`), 첫 누름에서 8픽셀
  (`MULTI_CLICK_PX` = `CELL_W`, comptime 단언), 같은 잎 · 같은 ws, 앞 누름이 끌리지 않았다. 3에서 멈춘다(넷째도 줄). 두 번째 ·
  세 번째 누름은 누름에서 곧바로 `select_start{ unit = word | line }`을 내고 `dragging`으로 간다 — 뗌은 기존 길로 복사한다.
- `vt.Screen.SelectKind.word`. 누른 자리를 `copy_word`(tracked pin + 그 화면)로 따로 든다. 놓는 곳은 `dropWordAnchor` 하나이고
  `copyExit` · `copySelect`가 지난다. 단어 식은 라이브러리 `dragSelectionWord`를 옮긴 `copyWordSel`(`selectWordBetween` 둘).
- 시각: `PointerEdge.t_us` = 그 이벤트의 `ev.time`. 장치를 열 때 `EVIOCSCLOCKID(CLOCK_MONOTONIC)` — 실패할 때만 `pointer> clock`
  줄. 로그는 `press` 줄을 그대로 두고 반복일 때만 `pointer> repeat n=N dt=MS`.
- 게이트: `pointer` 체인 부팅 A의 검사 33~37(더블 · 트리플 · 단어 끌기 · 느린 두 클릭 · 끌기 직후 클릭), 판정은 `clip>` 줄.

## 배운 것 — 다시 조사하지 말 것

1. evdev의 기본 시계는 `CLOCK_REALTIME`이다(`evdev_client`를 0으로 할당, `INPUT_CLK_REAL = 0`). `EVIOCSCLOCKID`는 translate-c가
   상수로 넘긴다. 고른 뒤 `ev.time`과 읽은 순간의 단조 시계 차는 0.05~0.23ms.
2. HMP `mouse_button` 넷을 `hmp`(명령마다 50ms 수면)로 이어 보내면 게스트의 두 누름 차는 97~120ms이고 루트 게이트 부하에도 안
   늘어난다. 그러나 `button_down` · `button_up` · `move_to`는 로그 줄을 0.1초씩 기다리므로 사이에 끼면 500ms와 8픽셀이 먼저
   연속을 끊는다 — 검사 37의 첫 판이 그래서 "끌기가 끊는다" mutation을 초록으로 놓쳤다. 반복을 보는 검사는 hmp만 이어 보낸다.
3. 한 poll 회차에 누름 · 이동 · 뗌이 다 들어와도 된다 — `main.zig`의 `round.edges` 루프가 전이마다 그 자리로 먼저 `moved`를
   부른다.
4. 라이브러리 선택 자체가 tracked다 — 양 끝이 pin 둘. 선택 없음 2, 문자 선택 4, 단어 선택 5(앵커 하나 더).
5. `selectWord`는 `WORD_BOUNDARY` 스무 개를 한 부류로 본다 — 공백을 두 번 누르면 이웃한 괄호 · 따옴표와 한 덩어리이고
   `selectionString`이 끝 공백을 자른다(`)  ` → `)`). ghostty와 같아 그대로 둔다.
6. `u2` 횟수를 `@min(n + 1, 3)`으로 올리면 3 + 1이 `u2`에서 넘친다.

Shift 클릭 늘리기(비목표 1)는 Shift Extend(2026-11-01, [[project_shift_extend]])가 열었다 — 뗌이 선택을 남기고 Shift 클릭이
가까운 끝을 옮긴다.

관련: [[project_pointer_devices]] · [[project_copy_mode]] · [[feedback_gate_runs]].
