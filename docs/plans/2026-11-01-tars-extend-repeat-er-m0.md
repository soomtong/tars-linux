# ER-M0 — Shift 더블 · 트리플클릭이 단어 · 줄 단위로 늘린다

Goal: 남은 선택 위의 Shift 클릭 연속에서 둘째 누름이 단어 단위, 셋째부터 줄 단위로 늘리게 한다(ER design 결정 1~5). 호스트
테스트와 `pointer` 체인 검사 42 · 43으로 보고, 루트 게이트로 닫고 서브프로젝트를 끝낸다.

Architecture: `pointer.Gesture.Last`에 `extend`를 더해 늘리기 누름도 연속을 기억하고, 늘리기 연속의 반복이 `select_extend`에
`unit`을 실어 낸다. `vt.Screen.copyExtendAt`이 `?SelectKind`를 받아, 값이 있으면 첫 누름의 앵커(`copy_word` 또는 `sel.start()`)를
두고 방식만 바꿔 `copyApply`한다. `main.zig`는 `.select_extend` 갈래에서 `unitKind`를 함께 쓴다.

---

## 착수 전에 확정한 것

1. `WORD_BOUNDARY`(`vt.zig`)에 `-`는 없고 `:`는 있다 — `mc-two` · `beta-gamma`는 한 단어, `mc-two:three`는 셋이다. design의 예시 글자는
   이것으로 셈했다.
2. `Intent.select_extend`의 짐을 `Cell`에서 `Extend{ at: Cell, unit: ?Unit = null }`로 바꾼다. `pointer_test`에서 `.{ .select_extend = w }`를
   쓰는 두 자리는 `.{ .select_extend = .{ .at = w } }`가 된다. `main.zig`는 `unitKind`(`Unit` → `SelectKind`)를 `?`로 감싸 쓴다.
3. 반복 늘리기의 `unit`은 `clicks == 2`면 word, 아니면 line — `select_start`와 같은 식이다.
4. `copyExtendAt(x, y, kind)`에서 `kind != null`일 때의 앵커 값은 pin을 놓기 전에 복사해 둔다 — `copy_word`가 앵커이고
   `dropWordAnchor`가 그 pin을 놓는다. 이미 단어 방식이고 `kind == .word`면 pin을 그대로 둔다(놓고 다시 들지 않는다).
5. SE의 `pointer_test` 검사 35 끝 두 줄("the press after an extension starts over")은 끌고 뗀 뒤로 옮긴다 — 늘리기 누름 뒤 같은 자리
   100ms의 누름은 이제 반복이다.
6. 게이트의 Shift 연속은 `sendkey shift 3000` · `sleep 0.3` 뒤 `hmp`만 이어 보낸다(SE 기억 3, MC 기억 2). 검사 42는 넷, 43은 여섯.
   떼는 줄이 그만큼 늘었는지 `pointer_count 'release '`로 기다린다.

## Task 1: 순수 층과 호스트 테스트

`pointer.zig`.

- `pub const Extend = struct { at: Cell, unit: ?Unit = null };`, `select_extend: Extend`.
- `Last`에 `extend: bool`. 반복이 아닌 패널 칸 누름은 `t_us`가 있으면 언제나 `last`를 쓰고 `extend = at.extend`.
- 반복이면 `l.extend`에 따라 `select_extend{ at = h, unit }` 또는 `select_start`. `press`의 문서 주석과 `Intent`의 주석을 고친다.

`vt.zig`.

- `copyExtendAt(self, x, y, kind: ?SelectKind)`. null은 지금 그대로. 값이 있으면 앵커 = `copy_kind == .word`이면 `copy_word.?.pin.*`,
  아니면 `sel.start()`. `kind == .word`이면 (이미 단어가 아닐 때만) 앵커 자리로 `copy_word`를 들고, `.line`이면 `dropWordAnchor`.
  `copy_kind = kind` 뒤 `copyApply(앵커, 커서)`. `.char`가 오면 null과 같이 다룬다(반복은 char를 안 낸다).

`pointer_test.zig` — 검사 35의 끝을 고치고 검사 39 · 40을 더한다.

- 39: 늘리기 누름 · 뗌 → 100ms 뒤 같은 자리 `extend = false` 누름이 `cancel` · `select_extend{ w, word }`, `clicks` 2, `dragging` →
  뗌이 `copy` → 셋째 `line`, `clicks` 3 → 넷째 `line`.
- 40: 늘리기 누름 뒤 끌고 뗀 다음 누름은 처음부터(`cancel` · `deselect`, `clicks` 1).

`vt_test.zig` — 검사 125~129(design 검증의 호스트 (a)~(e)).

- 125: `linger(6, 9)`(`beta`) → `copyExtendAt(0, 0, null)` → `copyRelease` = `alpha beta` → `copyExtendAt(0, 0, .word)` → pin `mc_pins + 3`,
  yank `alpha beta-gamma`.
- 126: 같은 시작에서 `.word` 뒤 뗌 → `copyExtendAt(0, 0, .line)` → pin `mc_pins + 2`, yank 줄 전체 `alpha beta-gamma (delta)  eps`.
- 127: `linger(6, 7)`(`be`) → `(20, null)` → 뗌 → `(20, .word)` → `beta-gamma (delta`.
- 128: 더블클릭(`copyEnterAt(19, 0, .word)`)의 남은 선택 → `(7, null)` → 뗌 → `(7, .word)` → pin `mc_pins + 3`, `beta-gamma (delta`.
- 129: `clearLinger` 뒤 `(0, 0, .word)` → `copyActive` 거짓, 선택 없음.

판정: `zig build test`(컨테이너 — 호스트 macOS의 0.17로는 `fmt --check` · `ast-check`만).

## Task 2: `main.zig`

`.select_extend => |e|` — `copyExtendAt(e.at.col, e.at.row, if (e.unit) |u| unitKind(u) else null)`, `e.at.leaf`. 주석에 ER design 결정 4.

## Task 3: `pointer/check.sh` — 검사 42 · 43

자리는 SE 검사 41 뒤(`sleep 3` 다음), `move_to 679 0` 앞. 같은 줄 ROW · PY.

1. 검사 42 — `move_to (cell_x 8)` · `button_down` · `move_to (cell_x 11)` · `button_up` → `clip> len=4 text=c-tw`. `move_to (cell_x 1)` ·
   `sendkey shift 3000` · `sleep 0.3` · `hmp 1; hmp 0; hmp 1; hmp 0`. 뗌 둘을 기다리고, `clip>` 둘이 늘었고, `repeat` 줄이 하나 늘어
   `n=2`, 마지막 `clip> len=13 text=mc-one mc-two`.
2. 검사 43 — `sleep 3.2` 뒤 같은 끌기(`c-tw`), `move_to (cell_x 16)` · `sendkey shift 3000` · `sleep 0.3` · hmp 여섯. 뗌 셋, `clip>` 셋,
   마지막 `repeat` `n=3`, 마지막 `clip> len=19 text=mc-one mc-two:three`. 끝에 `sleep 3`.

## Task 4: 판정

1. `make quick`.
2. `pointer` 체인 단독(`make check CHAIN=pointer`, 약 3분 30초).
3. mutation 셋(되돌린다). 호스트 테스트가 먼저 잡는지 보고, 게스트는 `zig build test` 줄을 `if false`로 바꾼 `check.sh` 사본을
   마운트해 `pointer` 체인으로 보낸다(SE 기억 4): (1) 늘리기 누름이 `last`를 안 씀 → 검사 42가 `c-one mc-tw`. (2) 반복의 앵커를 가까운
   끝으로 → 검사 42가 `mc-one`. (3) `clicks == 3`도 word → 검사 43이 `mc-two:three`.
4. 루트 게이트(`make gate`, 약 10분 30초).

## Task 5: 닫기

design `Status` · `docs/guides/completed.md` 한 행 · 소개 페이지 "마우스 · 터치패드" 한 줄(`site/README.md`의 순서) ·
`docs/decisions/project_extend_repeat.md`와 `MEMORY.md` 한 줄 · SE 기억의 비목표 4 줄 · HANDOFF.

## 결과 (2026-11-01)

- 호스트: `zig build test` PASS. `pointer_test` 39 · 40, `vt_test` 125~129. pin 수는 단어 반복 뒤 5(기본 2 + 양 끝 + 단어 앵커),
  줄 반복 뒤 4 — 단어 → 줄에서 앵커를 `copy_word`에서 읽는 것이 요점이다(단어 단계를 지난 선택의 `start()`는 뒤집혀 0열이다).
- 게스트 로그(검사 42 · 43): `c-tw` → `copy> extend row=45 col=1` · `c-one mc-tw`(11) → `repeat n=2 dt=114` · `mc-one mc-two`(13).
  `c-tw` → `c-two:thr`(9) → `repeat n=2 dt=103` · `mc-two:three`(12) → `repeat n=3 dt=103` · `mc-one mc-two:three`(19). design의 글자 그대로다.
- 첫 판이 검사 42에서 두 번 연속 빨갰다 — 첫 누름이 `copy> deselect`(Shift가 안 보임) → 보통 더블클릭 `mc-one`. 임시 진단(Shift 상태가
  바뀔 때와 누름 때의 게스트 단조 시각, 호스트의 `sendkey` · `hmp` 시각)으로 원인을 쟀다: QEMU `sendkey shift 3000`이 뗀 뒤에도 3초 delay를
  큐에 남겨 큐를 6초 쥐고, SE 검사 40이 39의 1.3초 뒤에 보낸 Shift가 4.7초 늦게 닿은 뒤로 모든 Shift가 사슬로 밀렸다(measurements 99).
  SE 검사 40은 39의 Shift가 아직 눌려 있어서, 41의 Shift 클릭은 음성 검사라서 초록이었다 — SE 게이트의 숨은 구멍이다. 고친 것은 게이트
  쪽 `hold_shift`(앞 `sendkey`에서 6.1초를 기다린 뒤 보낸다) 하나이고, 체인의 여섯 자리가 쓴다. 진단 줄은 모두 걷었다.
- `make quick` PASS. `pointer` 체인 단독 PASS.
- 루트 게이트 22/22, 10분 50초(prebuild 346 + lanes 303초), verify 8218줄 전부 통과. `pointer`(PD-M4) 121초.
- mutation 셋 전부 빨강(호스트 · 게스트 각각, 게스트는 `zig build test` 줄을 `if false`로 바꾼 사본 마운트):
  1. 늘리기가 `last`를 안 씀 → 호스트 `pointer_test` 39 "the second press of an extending run" (`deselect`), 게스트 검사 42의 `repeat` 수
     (0 new) — design이 예고한 `clip>` 글자보다 앞 판정이 먼저 잡았다.
  2. 반복의 앵커를 가까운 끝으로 → 호스트 `vt_test` 125 `alpha`, 게스트 검사 42 `mc-one`(6).
  3. 늘리기 연속의 셋째도 단어 → 호스트 `pointer_test` 39 "the third press", 게스트 검사 43 `mc-two:three`(12).
