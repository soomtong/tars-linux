---
name: project_shift_extend
description: "끌어 떼도 선택이 화면에 남고 Shift 클릭이 그 선택의 가까운 끝을 옮기는 서브프로젝트(SE-M0~M1, 2026-11-01). 남은 선택은 새 필드가 아니라 selection != null && copy_cursor == null이고 다음 누름이 지운다. 함정 — Selection.start()는 넣은 순서 그대로다 · Shift 클릭 검사는 sendkey 3초 안에 hmp 둘로 · 호스트 테스트가 먼저 잡는 게스트 mutation은 check.sh 사본을 마운트"
metadata:
  node_type: memory
  type: project
---

# Shift Extend (SE)

design은 `docs/specs/2026-11-01-tars-shift-extend-design.md`, plan은 `docs/plans/2026-11-01-tars-shift-extend-se-m{0,1}.md`.
2026-11-01에 사용자가 HANDOFF의 후보 넷(PD 비목표의 휠 방향 · 포인터 가속, Shift 클릭 늘리기, CB 범위 workspace, 큰 kitty
이미지)에서 골랐다. MC 비목표 1과 PD 비목표 5를 함께 열었다 — 뗌이 선택을 지우면 늘릴 것이 없다. 같은 자리에서 사용자가 정한 셋:
가까운 끝이 움직인다(xterm, ghostty의 앵커 고정이 아니다) · 키 입력은 남은 선택을 지우지 않는다(xterm) · 키보드 `y`는 그대로다.

## 무엇이 섰나

- 포인터의 뗌은 `copyRelease` — `copyYank`와 같은 `clip>` 줄이지만 선택 · 방식 · 단어 앵커 · 앵커 감시를 둔다. "남은 선택"은
  `vt.Screen.hasLinger()` = `copy_cursor == null and selection != null`. 입력 모드는 normal, `COPY`는 꺼짐, 반전만 남는다.
- 지우는 자리 셋: 늘리기가 아닌 모든 왼쪽 누름(`Intent.deselect` — 여백 · 자식의 것 포함, 지금 ws의 패널 전부에서 `clearLinger`),
  새 선택의 시작(`copyEnter` · `copyEnterAt`), 가지치기(`feed`의 앵커 감시가 `copy_cursor == null`이면 조용히 지운다 —
  `copy> pruned`가 아니다). 키 · 출력 · 휠 · 키보드 포커스 이동은 안 지운다.
- 늘리기: `Stamp.extend`(= `mods.shift and 누른 패널.hasLinger()`, `main.zig`가 셈한다)가 참이고 반복이 아니면 `Gesture.press`가
  `cancel` · `focus?` · `select_extend`를 내고 `dragging`으로 간다(연속은 끊는다). `copyExtendAt`이 누른 칸이 `topLeft`보다 앞이면
  앵커 = `bottomRight`, 아니면 `topLeft`로 `copyApply(앵커, 커서)`. 단어 방식은 `copy_word` pin을 앵커 자리로 다시 든다. 그 뒤
  끌기 · 뗌은 끌기와 같다 — 떼면 늘어난 글자가 다시 클립보드에, 다시 남는다.
- 로그: `copy> extend row=R col=C`, 실제로 지운 패널마다 `copy> deselect`. 나머지 줄은 그대로. 게이트: `pointer` 체인 검사 38~41,
  반전은 copy 체인의 `inverted_cells`(`style>`의 `fg=102030`)를 옮겨 센다.

## 배운 것 — 다시 조사하지 말 것

1. 라이브러리 `Selection.start()` · `end()`는 `init(a, b)`에 넣은 순서 그대로다. 정렬된 끝은 `topLeft(s)` · `bottomRight(s)`.
   그래서 `copyPointTo`의 "앵커 = `start()`"는 선택이 뒤집혀도 앵커이고, 늘리기가 `init(앵커, 커서)`로 넣으면 그 뒤의 끌기가
   그대로 간다.
2. 반복이 늘리기보다 먼저다(ghostty와 같다). 더블클릭으로 고른 단어가 남아 있을 때 500ms 안의 Shift 클릭은 트리플이다.
3. 게이트의 Shift 클릭은 `sendkey shift 3000` 뒤 `hmp` 둘로만 보낸다 — `button_down` · `move_to`의 기다림이 3초를 먹는다. Shift
   없는 클릭이 뒤따르면 `sleep 3.2`. 안 기다리면 그 클릭이 늘리기가 된다.
4. 호스트 테스트가 먼저 잡는 게스트 mutation(앵커 고정 → `vt_test` 116)은 `terminal`의 `zig build test` 줄을 `if false`로 바꾼
   `check.sh` 사본을 `/workspace/pointer/check.sh`에 `:ro`로 마운트해 게스트까지 보낸다(DR-M3과 같다). 검사 40이 `mc-one m`(8)으로
   잡았다.
5. "보통 누름은 늘리기가 아니다"는 기존 검사가 이미 지킨다 — Shift를 안 보는 mutation은 검사 41보다 검사 16의 둘째가 먼저
   빨개졌다(앞 끌기의 남은 선택을 다음 누름이 늘려 `copy> enter`가 안 나왔다).
6. `Stamp`에 `extend: bool = false`를 둔 것은 `pointer_test`의 `press` 호출 서른 곳을 안 바꾸려는 것이다. 늘리기 여부는
   `press`의 인자가 아니라 "누름 하나의 사실"로 둔다.

## 숫자

루트 게이트 22/22, 10분 20초(prebuild 321 + lanes 299초), verify 8219줄 전부 통과.

관련: [[project_pointer_devices]] · [[project_multi_click]] · [[project_copy_mode]].
