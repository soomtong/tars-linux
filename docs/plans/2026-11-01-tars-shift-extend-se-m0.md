# SE-M0 — 순수 층: 뗀 뒤 선택이 남고, Shift 클릭이 가까운 끝을 옮긴다

> 게스트 동작은 아직 안 바뀐다. `main.zig`는 새 의도 둘의 갈래를 배선하되 `Stamp.extend`에 `false`를 넘기고 뗌은 `copyYank`
> 그대로라, 남는 선택이 없고 `deselect`는 지울 것이 없다. 뗌을 `copyRelease`로 바꾸고 Shift를 읽고 게이트가 보는 것은 SE-M1이다.

Goal: design 결정 1~6을 순수한 두 층(`pointer.Gesture` · `vt.Screen`)에 넣고 호스트 테스트로 선다.

Architecture: `Gesture.press`가 `Stamp.extend`를 보고 반복 → 늘리기 → 보통 누름 순서로 가른다. 늘리기는 `select_extend`를 내고
`dragging`으로, 보통 누름과 `handOff` · 여백 누름은 `deselect`를 더 낸다. `vt.Screen`은 `copyExit`의 "커서 · 검색을 버리는 반"을
`copyDetach`로 떼어 `copyRelease`가 쓰고, `hasLinger` · `clearLinger` · `copyExtendAt`을 더한다. `feed`의 앵커 감시는 남은 선택이면
조용히 지운다.

---

## 착수 전에 확정한 것

1. 늘리기 여부는 `press`의 인자가 아니라 `Stamp.extend: bool = false`다(design 결정 5의 서명을 고쳤다). `Stamp`는 "누름 하나의
   사실"이고 `pointer_test`의 `Gesture.press` 호출 서른 곳이 `stamp()` · `NO_TIME`을 그대로 쓴다 — 새 검사만 `extend = true`를 든다.
2. `Selection.start()`는 `init(a, b)`의 a 그대로다(design 조사 2). 늘리기가 `init(앵커, 커서)`로 넣으면 그 뒤 `copyPointTo`의
   `sel.start()`가 그 앵커다 — `copyPointTo`는 안 바꾼다.
3. `topLeft(s)` · `bottomRight(s)`는 `*const ghostty_vt.Screen`을 받고 `Pin.before`로 견준다(`copyWordSel`이 쓰는 것과 같다).
4. 남은 선택의 방식은 `copy_kind`에 남아 있어야 한다 — `copyRelease`가 `copy_kind` · `copy_word` · `copy_anchor_y`를 둔다. 셋을 함께
   버리는 자리가 `clearLinger`이고 `copyExit`도 그것을 지난다.
5. `feed`의 앵커 감시가 남은 선택을 지울 때 `copy_pruned`를 세우지 않는다(design 결정 2) — `main.zig`의 `copy> pruned` · 입력 모드
   되돌림은 copy mode가 끊긴 것을 말한다.
6. `deselect`는 보통 누름의 `cancel` 바로 뒤다. 실행이 지금 워크스페이스의 패널 전부를 보므로 `focus`와의 순서는 뜻이 없다. 반복
   누름(횟수 2 · 3)은 `deselect`를 안 낸다 — 버퍼 3이 `cancel` · `focus?` · `select_start`로 차고, 그 연속의 첫 누름이 이미 지웠다.

## Task 1: `pointer.zig`

- `Stamp`에 `extend: bool = false` — "Shift가 눌렸고 누른 패널에 남은 선택이 있다"(`main.zig`가 셈한다).
- `Intent`에 `deselect`, `select_extend: Cell`.
- `press`: `hit == null` → 지금 일에 `deselect`를 더한다. 반복이면 지금과 같다. 반복이 아니고 `at.extend`면 — `clicks = 1`,
  `gap_us = 0`, `breakRun()`, `start = cur = h`, `cancel` · `focus?` · `select_extend{h}`, `phase = dragging`. 아니면 지금의 횟수 1에
  `deselect`를 `cancel` 뒤에 더한다.
- `handOff`: `cancel` 뒤에 `deselect`.
- 머리 주석 · `Intents`의 "셋을 넘지 않는다" 설명을 새 조합으로 고친다.

## Task 2: `pointer_test.zig`

기존 기대값: 보통 누름 `.{.cancel}` → `.{ .cancel, .deselect }`(검사 16 둘, 29의 첫 누름, 33), 여백 누름 `&.{}` → `&.{.deselect}`
(검사 17), `handOff`(검사 26 둘)에 `.deselect`. 반복 누름의 기대값은 그대로다.

새 검사(35~38).

1. 35 — 늘리기 누름: `extend = true`의 첫 누름이 `cancel` · `select_extend{w}`, `phase == .dragging`, `held() == 0`, `clicks == 1`.
   `motion`이 `select_to`, `release(.copy)`가 `copy`. 100ms 뒤 같은 자리의 누름은 `clicks == 1`(연속이 끊겼다).
2. 36 — 다른 패널이 포커스: `cancel` · `focus 0` · `select_extend` 셋.
3. 37 — 반복이 먼저: 1000ms 보통 누름 · 뗌 뒤 1100ms `extend = true` 누름이 `cancel` · `select_start(word)`, `clicks == 2`.
4. 38 — `deselect`의 자리: `extend = true`지만 `hit == null`이면 `deselect`만(여백). 반복 누름(둘째)은 `deselect`가 없다.

## Task 3: `vt.zig`

- `copyDetach()`(private): `copy_cursor = null`과 검색 상태 다섯 줄(`findCancel` · `find` · `find_matches` · `hl_spans` · `find_status`).
  `copyExit` = `copyDetach` + `copy_kind = null` + `dropWordAnchor` + `copy_anchor_y = null` + `clearSelection`.
- `copyRelease(clip) !?[]const u8`: 선택이 없으면 `copyExit`하고 null(`copyYank`와 같다). 있으면 문자열을 뽑아 `clip.set` 뒤 `copyDetach`.
- `hasLinger() bool`, `clearLinger() bool`(지웠으면 참 — `main.zig`가 `copy> deselect`를 찍는 조건), `copyExtendAt(x, y) !void`(design
  결정 4 · 6). 단어 방식은 `dropWordAnchor` 뒤 앵커 자리를 `trackPin`.
- `copyEnter` · `copyEnterAt`: 들어가기 전 `clearLinger`(`copyEnterAt`은 copy mode면 `copyExit`, 아니면 `clearLinger`).
- `feed`: 앵커가 어긋났을 때 `copy_cursor == null`이면 `clearLinger`만.
- `SelectKind` 주석의 "word는 더블클릭만 쓴다"는 그대로다. `copy_word` 주석에 "남은 선택에서도 든다" 한 줄.

## Task 4: `vt_test.zig`

`mc` 화면(40 × 5, `alpha beta-gamma (delta)  eps`)을 이어 쓴다. 검사 113 뒤, 번호 114부터. 도구 하나 — `linger(scr, clip, x0, x1)` =
`copyEnterAt(x0, 0, .char)` · `copyPointTo(x1, 0)` · `copyRelease`.

1. 114 — `copyRelease`: `linger(6, 9)`의 글자가 `beta`, `copyActive` 거짓, `hasLinger` 참, pin이 `mc_pins + 2`.
2. 115 — 오른쪽 늘리기: `copyExtendAt(18, 0)` 뒤 `copyActive` 참, `expectYank` → `beta-gamma (d`.
3. 116 — 가까운 끝(왼쪽): `linger(18, 22)`(`delta`) · `copyExtendAt(0, 0)` → `alpha beta-gamma (delta`. 앵커 고정이면 `alpha beta-gamma (d`.
4. 117 — 선택 안: `linger(6, 15)` · `copyExtendAt(9, 0)` → `beta`.
5. 118 — 단어 방식: `copyEnterAt(19, 0, .word)` · `copyRelease` → `delta`, pin `mc_pins + 3`. `copyExtendAt(7, 0)` → pin 그대로 `+ 3`,
   yank `beta-gamma (delta`.
6. 119 — 줄 방식: `feed("zeta eta\r\n")`로 1행을 만든 뒤 `copyEnterAt(7, 0, .line)` · `copyRelease` · `copyExtendAt(2, 1)` →
   `alpha beta-gamma (delta)  eps\nzeta eta`.
7. 120 — 늘린 뒤 끌기: `linger(6, 9)` · `copyExtendAt(18, 0)` · `copyPointTo(20, 0)` → `beta-gamma (del`(앵커가 안 끌려간다),
   `copyPointTo(1, 0)` → `lpha b`.
8. 121 — `clearLinger`: `linger(6, 9)` 뒤 참, `hasLinger` 거짓, pin `mc_pins`, 다시 부르면 거짓.
9. 122 — 새 선택이 지운다: `linger(6, 9)` · `copyEnterAt(18, 0, .char)` → pin `mc_pins + 2`, yank `d`. `linger(6, 9)` · `copyEnter()` →
   선택 null, `copyExit`.
10. 123 — 가지치기: 검사 9의 `pruned` 모양(20 × 5, 200줄)으로 새 화면. `scrollByRows(-10)` · `copyEnterAt(0, 0, .char)` ·
    `copyPointTo(1, 0)` · `copyRelease` 뒤 3000줄 → `hasLinger` 거짓, `copyTakePruned` 거짓.
11. 124 — copy mode 안: `copyEnterAt(6, 0, .char)` 뒤 `hasLinger` 거짓, `copyExtendAt(18, 0)`이 아무 일도 안 해 yank `b`.

## Task 5: `main.zig` — 컴파일되는 최소

- `run`에 `.deselect` — `for (&self.ws.panes) |*slot|`의 `clearLinger()`가 참인 패널마다 `terminal: copy> deselect`, `redraw`.
- `run`에 `.select_extend => |at|` — `copyExtendAt` 뒤 `copyActive()`면 `forceMode(.copy)`(조합 중인 한글은 `select_start`와 같이
  그 패널 PTY로) · `dumpCopy(screen, "extend")` · `redraw`. 화면이 안 들어갔으면 입력 모드도 안 바꾼다 — 두 사본이 함께 간다(PD 결정 6).
- `press`: `Stamp`에 `.extend = false`(M1이 `mods.shift and hasLinger`로 바꾼다 — 주석 한 줄).

## Task 6: 판정

1. 호스트 macOS `zig fmt --check` · `ast-check`(`make quick`).
2. 컨테이너 `cd terminal && zig build test` — `pointer_test` · `vt_test` · `dirty_test` · `input_test`.
3. 게이트는 안 돈다 — 게스트 동작 0 변경(M1의 루트 게이트가 M0의 코드도 함께 지난다).
