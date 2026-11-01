---
name: project_extend_repeat
description: "남은 선택 위의 Shift 더블 · 트리플클릭이 단어 · 줄 단위로 늘리는 서브프로젝트(ER-M0, 2026-11-01). 늘리기 누름도 연속을 기억하고(Last.extend), 반복은 첫 누름의 앵커를 둔 채 단위만 바꾼다. 함정 — QEMU sendkey N은 키보드 큐를 2N ms 쥔다(게이트는 hold_shift로 6.1초 간격)"
metadata:
  node_type: memory
  type: project
---

# Extend Repeat (ER)

design은 `docs/specs/2026-11-01-tars-extend-repeat-design.md`, plan은 `docs/plans/2026-11-01-tars-extend-repeat-er-m0.md`.
2026-11-01에 사용자가 HANDOFF의 후보 넷(Shift + 더블클릭 단어 늘리기 · 휠 방향 · 0.1.3 릴리스 · CB 범위 workspace)에서 골랐다. SE 비목표
4를 열었다. 같은 자리에서 사용자가 정한 둘: 단위가 바뀌면 양 끝이 다 넓어진다(앵커 쪽도) · 연속의 첫 누름이 늘리기인지를 정한다
(둘째 · 셋째 누름의 Shift는 안 본다).

## 무엇이 섰나

- `pointer.Gesture.Last.extend` — 늘리기 누름도 연속을 기억한다(SE 결정 3의 "연속을 끊는다"를 바꿨다). 그 연속의 반복은
  `select_extend: Extend{ at, unit }`(둘째 word, 셋째부터 line). 보통 연속의 반복은 Shift가 있어도 그대로 `select_start`다.
- `vt.Screen.copyExtendAt(x, y, unit: ?SelectKind)` — null은 SE 그대로(가까운 끝). 값이 있으면 앵커 = `copy_word` pin이 있으면 그것,
  아니면 `sel.start()`이고 방식만 바꿔 `copyApply`. 단어 · 줄 식이 앵커 쪽 끝도 넓힌다 — 새 선택 식은 없다.
- 새 로그 줄 없음. `pointer> repeat n=N`과 `clip>` 글자로 판정. `pointer` 검사 42(왼쪽 Shift 더블, `mc-one mc-two`) · 43(오른쪽 Shift
  트리플, 줄 전체).

## 배운 것 — 다시 조사하지 말 것

1. 반복에서 가까운 끝을 다시 고르면 틀린다 — 반복은 첫 누름과 같은 칸이고 그 칸이 첫 누름이 옮긴 끝이라, 왼쪽으로 늘렸으면 커서 자신이
   앵커로 뽑힌다. 오른쪽 늘리기는 우연히 같은 앵커를 뽑아 이 mutation을 못 잡는다 — 게이트 검사 42가 왼쪽인 이유.
2. 단어 → 줄 반복의 앵커는 `copy_word`에서 읽어야 한다. 단어 단계를 지난 선택은 뒤집혀 있어 `start()`가 커서 쪽 단어의 첫 글자다.
3. QEMU `sendkey KEY N`은 뗀 뒤에도 N ms delay를 큐에 남겨 키보드 큐를 2N ms 쥔다(measurements 99). 그 안에 보낸 `sendkey`는 줄을
   서서 늦게 가고, 마우스는 큐를 안 거쳐 먼저 간다. SE 검사 40이 39의 1.3초 뒤에 Shift를 보내 그 뒤의 Shift가 전부 사슬로 밀렸다 —
   40은 39의 Shift가 아직 눌려 있어서, 41은 음성 검사라서 초록이었다. `pointer/check.sh`의 `hold_shift`가 앞 `sendkey`에서 6.1초를
   기다린다. 다른 체인에서 hold가 긴 `sendkey`를 이어 보낼 때도 같다.
4. 진단 법: Shift 상태가 바뀔 때와 누름 때 게스트 `CLOCK_MONOTONIC`(libc `std.c.clock_gettime` — Zig 0.17에 `std.posix.clock_gettime`은
   없다)을 찍고, 체인에서 `date +%s.%3N`을 찍어 한 쌍(`sendkey` → 누름)으로 두 시계를 맞춘다. 로그 줄이 붙어 있다고 시각이 붙어 있지 않다.

## 숫자

루트 게이트 22/22, 10분 50초(prebuild 346 + lanes 303초), verify 8218줄 전부 통과. 게스트의 두 누름 차 103~114ms.

관련: [[project_shift_extend]] · [[project_multi_click]] · [[project_pointer_devices]].
