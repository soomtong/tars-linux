# TARS Shift Extend — Design

Date: 2026-11-01
Status: 끝났다 — SE-M0~M1(2026-11-01). 루트 게이트 22/22, 10분 20초(prebuild 321 + lanes 299초), verify 8219줄 전부 통과. plan은 `docs/plans/2026-11-01-tars-shift-extend-se-m{0,1}.md`,
기억은 `docs/decisions/project_shift_extend.md`. `pointer` 체인 검사 38~41이 남은 반전 · 오른쪽 늘리기 · 왼쪽(가까운 끝) 늘리기 ·
보통 클릭의 지우기를 보고, mutation 넷을 잡는다.

MC design(`docs/specs/2026-11-01-tars-multi-click-design.md`)의 비목표 1 "Shift 클릭으로 늘리기"를 연다. 사용자가 2026-11-01에
HANDOFF의 후보 넷(PD 비목표의 휠 방향 · 포인터 가속, Shift 클릭 늘리기, CB 범위 workspace, 큰 kitty 이미지)에서 골랐다. MC 비목표 1이 적어
둔 대로 혼자 열 수 없다 — 뗌이 복사하고 모드를 나가며 선택을 지우므로 늘릴 선택이 없다. 그래서 PD 비목표 5 "뗀 뒤 반전 남기기"를
함께 연다. 둘이 한 서브프로젝트인 이유는 앞이 뒤의 전제이고, 앞만 열면 "왜 남는가"에 답이 없기 때문이다. 같은 자리에서 사용자가
정한 것 셋 — 가까운 끝이 움직인다(결정 4) · 키 입력은 남은 선택을 지우지 않는다(결정 2) · 키보드 `y`는 지금 그대로다(결정 1).

## 한 줄 요약

끌어 떼면 지금처럼 클립보드에 들어가고 copy mode를 나가지만, 반전은 화면에 남는다(남은 선택). Shift를 누른 채 그 패널을 누르면
남은 선택의 가까운 끝이 누른 칸으로 옮겨 가고, 누른 채 끌면 그대로 늘어나며, 떼면 늘어난 글자가 다시 클립보드에 들어가고 다시
남는다. 남은 선택은 Shift 없는 다음 누름이 지운다. 키보드 copy mode(`Cmd+Shift+C` · `v` · `y`)는 바뀌지 않는다.

## 배경 — 착수 전 조사 (2026-11-01, HEAD `4c4fedd`)

1. 뗌의 길. `Gesture.release`가 `dragging`이고 누른 패널이 copy mode면 `copy`를 내고, `PointerWire.run`의 `.copy` 갈래가
   `Clips.yank` → `vt.Screen.copyYank` → `copyExit`을 지난다. `copyExit`이 `clearSelection`까지 하므로 뗀 프레임에 반전이 없다.
   PD 결정 6이 "뗀 뒤에는 반전이 남지 않는다 … 비목표 5"로 적은 자리다.
2. 선택의 표현. 라이브러리 `Screen.selection`은 tracked pin 둘(단어 방식은 우리 `copy_word`까지 셋)이고 뷰포트 · 스크롤백 변화를
   따라간다. `Selection.start()` · `end()`는 우리가 `init(a, b)`에 넣은 순서 그대로다 — 정렬된 끝은 `topLeft(s)` · `bottomRight(s)`가
   따로 있다(`Selection.zig`). 그래서 `copyPointTo`의 "앵커 = 지금 선택의 `start()`"는 선택이 뒤집혀도 앵커를 가리킨다.
3. 가지치기 감시. `feed`는 `copy_anchor_y`가 있을 때만 앵커의 screen y를 다시 재고, 어긋나면 `copyExit` + `copy_pruned`다.
   `main.zig`가 `copyTakePruned`로 `copy> pruned` 줄을 찍고 포커스 패널이면 입력 모드를 normal로 되돌린다(LE 결정 1).
4. 지우는 자리. `copyExit`은 커서 · 방식 · 단어 앵커 · `copy_anchor_y` · 검색 상태 · 선택을 한 번에 버린다. `copyEnterAt`은 이미
   copy mode면 먼저 `copyExit`한다. 키보드 `Cmd+Shift+C`의 `copyEnter`는 커서만 놓는다.
5. Shift. `input.State.modifiers()`가 회차마다 `PointerWire.mods`로 온다(PD-M4). Shift를 누른 누름은 자식이 마우스를 원해도 우리
   것이다(`ownerOf`). 눌린 동안 Shift가 바뀌어도 주인은 안 바뀐다(`Grab`). `Gesture.press`는 Shift를 모른다.
6. 반복과의 관계. ghostty `Surface.zig`의 `mouseButtonCallback`은 Shift 왼쪽 누름이 (a) 선택이 있고 (b) 지난 클릭에서 반복 간격을
   넘었을 때만 늘린다 — 간격 안이면 횟수를 센다. 늘리기는 `cursorPosCallback`을 부르는 것이라 앵커가 지난 누름 자리 그대로다
   (앵커 고정). xterm은 가까운 끝이 움직인다. ghostty는 수정키 아닌 모든 키 누름에 선택을 지우고(`keyCallback`), xterm은 다음
   클릭까지 둔다.
7. 렌더. 반전은 `cells()`가 `row_data`의 `selection` 범위로 그린다 — copy mode와 무관하게 `Screen.selection`이 있으면 그린다.
   `Screen.select` · `clearSelection`은 라이브러리의 `dirty.selection`을 켜고, DR-M3의 `cellsReuse`가 그 행 비트를 읽는다 — copy
   mode의 선택이 이미 그 길을 지난다.
8. 게이트. `pointer/check.sh`의 `button_down` · `button_up` · `move_to`는 로그 줄을 기다리고(MC 함정), Shift는 `sendkey shift 3000`으로
   3초 누른 채 둔다(검사 29). 반전 셀은 copy 체인의 `inverted_cells(row)`가 `style>` 줄에서 `fg=102030`(기본 배경색이 전경이 된 셀)을
   세는 식으로 본다 — `style>`은 포커스 패널의 기본색 아닌 셀을 `STYLE_DUMP_LIMIT`까지 찍는다. pointer 체인에는 그 헬퍼가 없다.
9. 마우스를 누르는 체인은 `pointer` 하나다(`rg -l mouse_button */check.sh`). 남은 선택이 다른 체인의 판정에 닿을 길이 없다.

## 결정

### 결정 1 — 뗌은 복사하고 모드를 나가지만 선택을 지우지 않는다. 포인터 뗌만이다(사용자 결정, 2026-11-01)

"남은 선택"은 새 상태 필드가 아니다 — `Screen.selection != null`이면서 `copy_cursor == null`인 것이다. 입력 모드는 normal이고(친 글자는
셸로 간다, 검사 18 그대로) 상태 줄의 `COPY`는 꺼진다. 바뀌는 것은 반전이 화면에 남는 것 하나다.

남는 것은 포인터의 뗌(`Intent.copy`)만이다. 키보드 `y` · `Cmd+C`는 지금처럼 복사하고 선택도 지운다. 이유 둘.

- 남은 선택의 쓸모는 Shift 클릭으로 늘리는 것이고 그것은 포인터의 일이다. 키보드 쪽 선택은 커서로 늘린다.
- copy 체인의 검사가 `y` 뒤의 반전을 음성으로 보는 자리가 있다(검사 9 "모드를 닫는다" 뒤의 `inverted_cells`). 키보드 길을 건드리면
  CM의 판정을 다시 짜게 된다 — 얻는 것이 없는 비용이다.

뗌이 "`y`와 같은 바이트"라는 PD 결정 6의 말은 그대로다(`clip>` 줄은 같다). 다른 것은 뗀 뒤의 화면이다.

### 결정 2 — 남은 선택은 다음 누름이 지운다. 키 · 출력 · 휠은 안 지운다(키는 사용자 결정, 2026-11-01)

지우는 때는 셋이다.

| 때 | 어디서 | 왜 |
|---|---|---|
| 왼쪽 버튼 누름 — 늘리기(결정 3)가 아닌 모든 것. 패널 칸 · 여백 · 구분선 · 자식의 것(`handOff`) | `Gesture`가 `deselect` 의도를 내고 `main.zig`가 지금 워크스페이스의 패널 전부에서 지운다 | 선택의 주인은 한 번에 하나다(PD 결정 6). ghostty · xterm 다 클릭이 지운다 |
| 새 선택이 시작된다 — 포인터 `copyEnterAt`, 키보드 `copyEnter`(`Cmd+Shift+C`) | `vt.Screen` 안에서 | 옛 반전 위에 새 커서가 서는 프레임을 안 만든다 |
| 가지치기 · 대체 화면 전환 | `feed`의 앵커 감시가 `copy_cursor == null`이면 `copyExit` 대신 선택만 조용히 지운다 — `copy_pruned`를 안 세운다 | 이미 복사한 뒤라 잘못 복사될 것이 없고, 입력 모드도 normal이라 되돌릴 것이 없다. `copy> pruned`는 copy mode가 끊긴 것을 말하는 줄이다 |

안 지우는 것: 키 입력(xterm을 따른다 — ghostty식으로 하려면 키 경로에 자리가 하나 더 생기고, 선택은 tracked라 틀린 자리를 가리킬 일이
없다) · 출력(pin이 따라간다, 뷰포트 밖으로 밀리면 안 보일 뿐이다) · 휠 · 키보드 포커스 이동 · 워크스페이스 전환(다른 워크스페이스의 남은
선택은 돌아와서 누를 때 지워진다). 지금 워크스페이스의 패널 전부에서 지우는 이유는 포커스를 옮기는 클릭 — 패널 A에서 끌어 떼고
패널 B를 누르면 A의 선택이 남아 있다 — 때문이다. 하나만 남는다는 규칙을 포인터 경로의 한 자리에서 지킨다.

### 결정 3 — 늘리기의 조건: Shift · 왼쪽 · 패널 칸 · 그 패널에 남은 선택 · 반복이 아니다

다섯이 다 참일 때 그 누름은 늘리기다.

1. 누름 회차의 수정키에 Shift가 있다(`mods.shift`, 조사 5).
2. 왼쪽 버튼이고 우리 것이다 — Shift면 언제나 우리 것이다(`ownerOf`).
3. 패널 칸을 눌렀다(`hit != null`).
4. 그 패널에 남은 선택이 있다(`hasLinger`). 키보드 copy mode인 패널은 남은 선택이 아니라(`copy_cursor != null`) 지금처럼 모드를
   닫는 클릭이다(PD 결정 6의 표 그대로).
5. 지난 누름의 반복이 아니다(MC 결정 3). 반복이면 횟수를 센다 — ghostty와 같은 순서다(조사 6). 더블클릭으로 고른 단어가 남아 있을 때
   500ms 안에 Shift를 누른 채 다시 누르면 그것은 트리플이다.

Shift가 있어도 남은 선택이 없으면 지금과 같은 누름이다 — 자식이 마우스를 원하는 패널에서는 우리 끌기의 시작(검사 29 그대로)이고,
아니면 보통 클릭이다.

늘리기 누름은 `cancel` · (다른 패널이면) `focus` · `select_extend`를 낸다. `deselect`는 안 낸다. 그리고 `dragging`으로 가고 연속을
끊는다(`breakRun`) — 늘린 뒤의 누름은 처음부터다. `cancel`을 그대로 내는 이유는 그 뜻이 "키보드 쪽 모드를 끝낸다"(조합 중인 한글
확정 · 포커스 패널의 copy mode 닫기)이고 그 일은 늘리기에도 맞기 때문이다 — 누른 패널은 copy mode가 아니므로(조건 4) 그 패널의
선택은 `cancel`에 안 닿는다.

### 결정 4 — 가까운 끝이 움직인다(사용자 결정, 2026-11-01). 방식은 남은 선택의 것 그대로다

누른 칸의 pin이 선택의 `topLeft`보다 앞이면 앵커는 `bottomRight`이고, 아니면(선택 안이거나 뒤) 앵커는 `topLeft`다. 커서는 누른 칸이고
`copyApply(앵커, 커서)`가 선택을 다시 짓는다. 선택 안을 누르면 오른쪽 끝이 당겨져 줄어든다 — ghostty와 같다.

xterm의 "가까운 끝"을 고르고 ghostty의 "앵커 고정"을 안 고른 이유. 끌어 `mc-two`를 고른 뒤 그 앞의 `mc-one`을 Shift 클릭하면 앵커 고정은
`mc-one m`(누른 칸 ~ 옛 앵커)이 되어 처음 고른 글자가 사라진다. 사람이 뜻한 것은 `mc-one mc-two`다.

방식(`copy_kind`)은 남은 선택의 것이다 — 끌어 만든 것은 문자, 더블클릭의 것은 단어, 트리플의 것은 줄. 단어 방식은 앵커를 `copy_word`
pin에서 읽으므로(MC 결정 4) 늘리기가 그 pin을 새 앵커 자리로 다시 든다(`untrackPin` → `trackPin`). 줄 방식은 `copyLineSel`이 앵커 줄과
커서 줄의 위아래를 라이브러리에 묻는다 — 앵커 pin이 어느 끝이든 된다.

그 뒤의 끌기는 `select_to` → `copyPointTo` 그대로다. `copyPointTo`가 앵커를 `sel.start()`에서 읽고(조사 2) 우리가 `init(앵커, 커서)`로
넣었으므로 `start()`가 곧 그 앵커다. 뗌은 `copy` → 복사 → 다시 남는다(결정 1). Shift 클릭을 거듭하면 그때마다 늘고 그때마다 복사한다.

### 결정 5 — `Intent`에 둘을 더하고 `press`가 늘리기 여부를 인자로 받는다

```zig
/// 남은 선택을 지운다 — 지금 워크스페이스의 패널 전부에서(SE design 결정 2).
deselect,
/// 이 칸으로 남은 선택의 가까운 끝을 옮기고 copy mode에 들어간다(SE design 결정 4).
select_extend: Cell,
```

`Stamp`에 `extend: bool = false`를 더한다. 값은 `main.zig`가 셈한 "Shift가 눌렸고 누른 패널에 남은 선택이 있다"다 — `pointer.zig`는
`vt.zig`도 `input.zig`도 import하지 않으므로(머리 주석) 두 사실을 합친 bool 하나를 받는다. `press`의 인자가 아니라 `Stamp`의 칸인
이유는 `pointer_test`의 호출 서른 곳이 그대로 서기 때문이다(SE-M0 plan 확정 1). 반복 판정이 먼저이고(결정 3의
5), 반복이 아니고 `extend`면 늘리기, 아니면 지금의 누름에 `deselect`를 더한다. `handOff`(자식의 것)도 `deselect`를 낸다. `Intents`의
버퍼 3은 그대로 찬다 — 보통 누름 `cancel` · `deselect` · `focus?`, 반복 `cancel` · `focus?` · `select_start`, 늘리기 `cancel` · `focus?` ·
`select_extend`.

`deselect`를 `cancel`에 합치지 않는 이유. 늘리기 누름도 `cancel`을 내는데(결정 3) 그 자리에서 선택을 지우면 늘릴 것이 없어진다. 둘은
다른 일이다 — `cancel`은 키보드 쪽 모드, `deselect`는 화면에 남은 선택.

`main.zig`의 switch는 `else`가 없어 두 variant의 배선 자리를 컴파일러가 짚는다(PD 결정 3).

### 결정 6 — `vt.Screen`의 함수 넷. `copyExit` · `feed`는 조금 바뀐다

| 함수 | 하는 일 |
|---|---|
| `copyRelease(clip) !?[]const u8` | `copyYank`와 같이 선택을 문자열로 뽑아 `clip`에 넣고 copy mode를 나간다. 다르게, 선택 · `copy_kind` · `copy_word` · `copy_anchor_y`를 둔다. 커서 · 검색 상태는 `copyYank`와 같이 버린다 |
| `hasLinger() bool` | `copy_cursor == null and selection != null` |
| `clearLinger()` | 남은 선택이면 선택 · 방식 · 단어 앵커 · `copy_anchor_y`를 버린다. copy mode면 아무 일도 안 한다 |
| `copyExtendAt(x, y) !void` | 남은 선택이 아니면 아무 일도 안 한다. 커서를 `(x, y)`(clamp)에 두고 결정 4의 앵커를 고르고 `copyApply`. 단어 방식이면 `copy_word`를 앵커 자리로 다시 든다 |

`copyExit`은 그대로 모든 것을 버린다 — 그 안의 "커서 · 검색을 버리는 반"을 `copyRelease`가 함께 쓰도록 private 함수로 뗀다. `copyEnter` ·
`copyEnterAt`은 들어가기 전에 `clearLinger`(결정 2). `feed`의 앵커 감시는 어긋났을 때 `copy_cursor == null`이면 `clearLinger`만 한다(결정 2의
표). 단어 앵커를 놓는 자리는 여전히 `dropWordAnchor` 하나다(MC 위험 3) — `clearLinger`도 그것을 지난다.

### 결정 7 — 로그: `copy> extend row=R col=C` · `copy> deselect`. 나머지 줄은 그대로

- `select_extend`를 실행하면 `dumpCopy(screen, "extend")` — 커서가 있으므로 좌표가 붙는다.
- `deselect`가 실제로 지운 패널마다 `terminal: copy> deselect` 한 줄. 지울 것이 없으면 안 찍는다 — 클릭마다 줄이 늘면 `copy>` 줄을 세는
  검사들이 흔들린다.
- `press` · `release drag=` · `clip>` · `copy> yank` · `repeat` 줄은 모양도 순서도 그대로다. 남은 선택은 `style>` 줄의 반전 셀로 본다 —
  copy 체인의 `inverted_cells(row)`를 pointer 체인으로 옮긴다(조사 8).

## 검증

호스트(SE-M0).

- `pointer_test`: (a) 늘리기 누름 — `extend = true`의 첫 누름이 `cancel` · `select_extend`, phase `dragging`, `last == null`, 뗌이
  `copy`. (b) 다른 패널이 포커스일 때 `cancel` · `focus` · `select_extend` 셋. (c) 반복이 먼저 — 더블클릭 간격 안의 `extend = true`
  누름이 `select_start(word)`. (d) 보통 누름 · 여백 누름 · `handOff`가 `deselect`를 내고, 늘리기 누름은 안 낸다. (e) `extend = true`지만
  `hit == null`이면 여백 누름이다.
- `vt_test`(문자열 `alpha beta-gamma (delta)  eps` 재사용): (a) `copyRelease` 뒤 문자열이 `copyYank`와 같고 `hasLinger`, `copyActive`
  거짓, tracked pin이 모드 안과 같은 수. (b) 오른쪽 늘리기 — `beta`를 끌어 놓고 `(delta)`의 `d`를 `copyExtendAt` → `beta-gamma (d`.
  (c) 왼쪽 늘리기(가까운 끝) — `delta`를 놓고 `alpha`의 `a` → `alpha beta-gamma (delta`. 앵커 고정이었다면 `alpha beta-gamma (d`가 남는다 —
  mutation 2가 노리는 자리. (d) 단어 방식 — 더블클릭 선택을 놓고 왼쪽 단어로 늘리면 두 단어 통째, `copy_word`가 새 앵커 자리이고 pin
  수가 N + 1 그대로. (e) 줄 방식. (f) 늘린 뒤 `copyPointTo`로 더 끌기 — 앵커가 안 끌려간다. (g) `clearLinger` 뒤 pin 수 N, `hasLinger`
  거짓. (h) `copyEnterAt` · `copyEnter`가 남은 선택을 지운다. (i) `feed`로 앵커 줄이 지워지면 선택이 조용히 사라지고 `copyTakePruned`가
  거짓. (j) copy mode 안에서는 `hasLinger` 거짓이고 `copyExtendAt`이 아무 일도 안 한다.

게스트(SE-M1, `pointer` 체인 부팅 A — MC 검사 37 뒤, 같은 줄 `mc-one mc-two:three`(ROW)를 쓴다. `mc-two`는 7~12열, `three`는 14~18열).

1. (검사 38) 7열을 누르고 12열로 끌어 뗌 → `clip> len=6 text=mc-two`, `COPY` 꺼짐, 그리고 ROW의 반전 셀이 6 이상이다(지금은 0).
2. (검사 39) Shift를 누른 채 18열 클릭 → `copy> extend row=ROW col=18`, 뗌에 `clip> len=12 text=mc-two:three`, `repeat` 줄 없음.
3. (검사 40) Shift를 누른 채 0열 클릭 → 가까운 끝(왼쪽)이 움직여 `clip> len=19 text=mc-one mc-two:three`. 앵커 고정이면
   `mc-one m`(8)이다.
4. (검사 41) Shift 없이 3열 클릭 → `copy> deselect`, ROW의 반전 셀 0, 새 `clip>` 없음. 이어서 Shift를 누른 채 10열 클릭 → `copy> extend`
   없음, 새 `clip>` 없음(남은 선택이 없으니 보통 클릭이다).

기존 검사의 영향: 15 · 29 · 33~37의 뗌 뒤에 선택이 남지만, 그 다음 검사의 첫 누름이 지운다. 판정 줄(`clip>` · `repeat` · `COPY` 꺼짐)은
그대로다. 검사 17의 `Cmd+Shift+C`는 `copyEnter`가 남은 선택을 지우고 들어간다.

mutation(SE-M1): (1) `.copy`를 `copyYank`로 되돌림 → 검사 38의 반전 0, 39의 `extend` 없음. (2) 앵커를 언제나 `topLeft`로 → 검사 40의
글자가 `mc-one m`. (3) `deselect` 실행을 비움 → 검사 41의 반전이 남고 둘째 클릭이 늘린다. (4) `extend`에서 Shift를 안 봄 → 검사 41의
Shift 없는 클릭이 늘린다.

## Milestone

- SE-M0 — 순수 층. `pointer.Gesture`의 `extend` 인자와 `deselect` · `select_extend`, `vt.Screen`의 함수 넷과 `copyExit` · `feed`의 변화,
  호스트 테스트. `main.zig`는 컴파일이 되는 최소 — 두 variant의 갈래를 배선하되 `extend`는 `false`를 넘기고 `.copy`는 `copyYank`
  그대로라 게스트 동작은 안 바뀐다(`deselect`는 지울 것이 없다). 실측 milestone은 두지 않는다 — 조사 2 · 6 · 7이 읽기로 확인됐고 새 장치
  · 새 시각이 없다.
- SE-M1 — 배선과 게이트. `.copy` → `copyRelease`, `extend = mods.shift and hasLinger`, 로그 둘, pointer 체인에 `inverted_cells`와
  검사 38~41, mutation 넷, 루트 게이트. 닫기(design `Status` · completed · 소개 페이지 "마우스 · 터치패드" 한 줄 · 기억 · HANDOFF).

## 위험

1. 남은 선택이 tracked pin을 든다 — 문자 · 줄 2, 단어 3. 패널마다 하나이고 다음 누름이 놓으므로 상한이 있다. `vt_test`가 수를 센다.
2. copy mode 밖에서 선택이 바뀌는 프레임을 DR-M3의 증분 렌더가 놓치면 반전이 한 프레임 늦게 지워진다. 조사 7 — `select` · `clearSelection`이
   라이브러리 행 비트를 켠다. 놓치면 verify가 `mismatch cells`로 잡는다(DR 결정 11).
3. 게이트의 Shift. `sendkey shift 3000`은 3초 뒤 저절로 떨어진다 — 그 안에 `hmp "mouse_button 1"` · `0`을 이어 보낸다(검사 29 · MC
   함정 2). 늘리기 판정은 누름 회차의 Shift만 본다(`Grab`과 같다). 검사 하나가 3초를 넘으면 그 검사 안에서 다시 누른다.
4. `style>`은 `STYLE_DUMP_LIMIT`까지만 찍는다. 왼쪽 패널의 프롬프트 색이 그 수를 먹으면 `inverted_cells`가 모자라게 센다 — 검사 38은
   하한(6 이상)이고 검사 41은 0이라 상한에 안 걸린다. 걸리면 `more cell(s) not shown` 줄이 말한다.
5. 다른 워크스페이스에 남은 선택은 돌아와 누를 때까지 남는다(결정 2). 사람이 거기서 Shift 클릭하면 늘어난다 — 뜻한 것일 가능성이 크다.
6. 남은 선택이 있는 패널의 셸이 끝나면 패널이 닫히며 `Screen`이 사라진다 — pin도 함께다. 새 자리가 아니다.

## 비목표

다시 열 조건을 함께 적는다.

1. 키 입력이 남은 선택을 지우기(ghostty식). 친 글자 옆에 옛 반전이 남는 것이 거슬리면 연다 — 키 경로(`bytes`가 PTY로 가는 자리)에서
   포커스 패널의 `clearLinger` 한 줄이다.
2. 키보드 `y` · `Cmd+C` 뒤에 남기기(결정 1). 키보드 선택을 Shift 클릭으로 늘리고 싶어지면 — copy 체인 검사 9의 음성 판정을 함께 고친다.
3. 남은 선택을 다시 복사하는 키(normal 모드의 `Cmd+C`). CM 비목표 그대로다 — 뗌이 이미 복사했다.
4. Shift + 더블클릭으로 단어 단위 늘리기(ghostty에는 없다, macOS 텍스트 뷰에는 있다). 반복이 늘리기보다 먼저다(결정 3).
5. 오른쪽 버튼으로 늘리기(xterm의 버튼 3). 오른쪽 버튼은 로그에만 나온다(PD 비목표 8).
6. 남은 선택을 끌어 옮기기 · 선택 안을 눌러 끌기(드래그 앤 드롭). 터미널에 없다.
7. 늘리기 중 가장자리 자동 스크롤(PD 비목표 3). 끄는 중의 휠이 대신이다.

## 관련

- PD design 결정 6(뗌 = 복사 + 종료, 비목표 5의 자리) · 결정 12(Shift는 우리 것) · 비목표 5(이번에 연 것).
- MC design 결정 3(반복) · 결정 4(단어 앵커 pin) · 비목표 1(이번에 연 것).
- CM design 결정 5 · 11(앵커 = `start()`, 이동 수단은 `copyApply` 하나).
- `docs/decisions/project_pointer_devices.md` · `project_multi_click.md` · `project_copy_mode.md`.
