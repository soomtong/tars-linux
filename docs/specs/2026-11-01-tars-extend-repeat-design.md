# TARS Extend Repeat — Design

Date: 2026-11-01
Status: design — ER-M0 착수 전.

SE design(`docs/specs/2026-11-01-tars-shift-extend-design.md`)의 비목표 4 "Shift + 더블클릭으로 단어 단위 늘리기"를 연다. 사용자가
2026-11-01에 HANDOFF의 후보 넷(Shift + 더블클릭 단어 늘리기 · 휠 방향 설정 · 0.1.3 릴리스 · CB 범위 workspace)에서 골랐다. 같은
자리에서 사용자가 정한 것 둘 — 단위가 바뀌면 양 끝이 다 넓어진다(결정 3) · 연속의 첫 누름이 늘리기인지를 정한다(결정 2).

## 한 줄 요약

남은 선택 위에서 Shift를 누른 채 두 번 누르면 단어 단위로, 세 번 누르면 줄 단위로 는다. 첫 누름은 지금(SE)과 같다 — 남은 선택의
방식으로 가까운 끝을 옮긴다. 둘째 · 셋째 누름은 첫 누름이 정한 앵커를 두고 단위만 바꿔 선택을 다시 짓는다. 떼면 그때마다 복사한다.

## 배경 — 착수 전 조사 (2026-11-01, HEAD `56a2e0f`)

1. 지금 늘리기 누름은 연속을 기억하지 않는다. `Gesture.press`(`pointer.zig`)가 `at.extend`면 `self.last = null`로 두고 `select_extend`를
   낸다(SE 결정 3 "늘리기 누름은 연속을 끊는다"). 그래서 남은 선택 위에서 Shift를 누른 채 같은 칸을 두 번 누르면, 둘째 누름도
   반복이 아니고(`last == null`) 다시 `extend`다(첫 뗌의 `copyRelease`가 선택을 남겼다). 같은 칸으로 문자 단위 늘리기를 두 번 한다 —
   결과가 안 바뀐다.
2. 반대 방향은 이미 정해져 있다. 보통 누름 뒤 500ms 안의 Shift 누름은 더블클릭이다(SE 결정 3의 5, `pointer_test` 검사 37) —
   반복 판정은 Shift를 안 본다.
3. 단어 식은 `copyWordSel(앵커, 커서)` 하나다(MC 결정 4) — 앵커 쪽 단어의 시작 ~ 커서 쪽 단어의 끝(뒤집히면 반대). 줄 식은
   `copyLineSel(앵커, 커서)`. 둘 다 앵커가 단어 · 줄 가운데 어디에 있어도 된다. 방식을 바꾸고 `copyApply(앵커, 커서)`를 부르면
   선택이 새 단위로 다시 선다.
4. 앵커가 어디 남는가. 늘리기는 `copyApply(앵커, 커서)` → `Selection.init(앵커, 커서)`이고 `start()`는 넣은 순서 그대로다(SE 기억 1).
   뗌(`copyRelease`)은 선택을 그대로 두므로 둘째 누름 때 `sel.start()`가 첫 누름이 고른 앵커다. 단어 방식은 `copy_word` pin이 앵커다.
5. 둘째 누름에서 "가까운 끝"을 다시 고르면 틀린다. 둘째 누름은 첫 누름과 8픽셀 안 — 같은 칸이고, 그 칸은 첫 누름이 옮긴 끝이다.
   왼쪽으로 늘렸으면 그 칸이 곧 `topLeft`라 `cursor.before(topLeft)`가 거짓이고 앵커로 `topLeft` = 커서 자신이 뽑힌다.
6. 게이트. `pointer` 체인의 Shift 클릭은 `sendkey shift 3000` 뒤 `hmp`로만 보낸다(SE 기억 3). `hmp` 넷의 두 누름 차는 97~120ms라
   500ms 안이다(MC 기억 2) — 여섯이면 트리플이다. `repeat_count` · `last_clip` 헬퍼가 있다.

## 결정

### 결정 1 — 늘리기 누름도 연속을 기억한다. 연속이 늘리기로 시작했는지를 함께 둔다

`Gesture.Last`에 `extend: bool`을 더한다. 반복이 아닌 누름은 `t_us`가 있으면 언제나 `last`를 새로 쓰고, `extend`에 `at.extend`를 담는다.
SE 결정 3의 "늘리기 누름은 연속을 끊는다"를 이것으로 바꾼다.

반복 판정(MC 결정 3의 넷)은 그대로다. 늘리기 누름은 누름에서 곧바로 `dragging`이므로 끌면 `motion`이 연속을 끊는다 — "앞 누름이 안
끌렸다"가 늘리기에도 선다.

### 결정 2 — 연속의 첫 누름이 늘리기인지를 정한다(사용자 결정, 2026-11-01)

반복 누름은 `last.extend`를 본다. 참이면 늘리기 반복이고 둘째 · 셋째 누름의 Shift는 안 본다. 거짓이면 지금의 더블 · 트리플클릭이다
(조사 2 — Shift가 있어도). 반복 판정이 Shift를 안 본다는 한 규칙이 양쪽에 같다.

| 연속 | 둘째 누름 | 셋째 누름 |
|---|---|---|
| 첫 누름이 보통(남은 선택 없음 · Shift 없음) | 단어 고르기(`select_start`) | 줄 고르기 |
| 첫 누름이 늘리기 | 단어 단위 늘리기(`select_extend`, unit word) | 줄 단위 늘리기 |

넷째부터는 줄이다(MC와 같다, `count`가 3에서 멈춘다).

### 결정 3 — 단위가 바뀌면 앵커 쪽 끝도 그 단위로 넓어진다(사용자 결정, 2026-11-01)

`c-tw`(8~11열)를 끌어 두고 `three`(14~18열)를 Shift 더블클릭하면 `mc-two:three`다 — 앵커 쪽 단어(`mc-two`)부터 커서 쪽 단어(`three`)까지.
`copyWordSel`이 그대로 하는 일이고(조사 3) 더블클릭으로 고른 단어를 끌 때와 같은 모양이다. 셋째 누름은 두 줄(앵커 줄 · 커서 줄)
전체다.

움직이는 끝만 넓히는 안(`c-two:three`)은 새 선택 식이 하나 더 생겨서 고르지 않았다.

### 결정 4 — 반복의 앵커는 첫 누름이 정한 것이다. 가까운 끝을 다시 고르지 않는다

조사 5. 반복 늘리기의 앵커는 단어 방식이면 `copy_word` pin, 아니면 `sel.start()`다(조사 4). 방식은 횟수가 정한다 — 2는 단어, 3은 줄.
남은 선택이 무슨 방식이었든 그렇다(트리플로 고른 줄을 Shift 더블클릭하면 단어 단위가 된다 — 횟수가 단위라는 MC 결정 6과 같다).
단어로 바뀌면 `copy_word`를 앵커 자리로 든다(이미 단어 방식이면 그 pin 그대로). 줄로 바뀌면 `dropWordAnchor`.

첫 누름(unit 없음)은 SE 결정 4 그대로다 — 가까운 끝, 남은 선택의 방식.

### 결정 5 — `select_extend`가 단위를 싣는다. `copyExtendAt`이 인자 하나를 더 받는다

```zig
/// Shift 누름이 늘릴 칸과 단위. `unit`이 null이면 첫 누름이다 — 남은 선택의
/// 방식으로 가까운 끝을 옮긴다(SE design 결정 4). 반복이면 word · line이다
/// (ER design 결정 2 · 4).
pub const Extend = struct { at: Cell, unit: ?Unit = null };

select_extend: Extend,
```

`vt.Screen.copyExtendAt(x, y, kind: ?SelectKind)`. null이면 지금과 같고, 값이 있으면 결정 4다. `main.zig`의 `.select_extend` 갈래는
`select_start`가 쓰는 `Unit` → `SelectKind` 옮김을 함께 쓴다. `Intents`의 버퍼 3은 그대로 찬다(`cancel` · `focus?` · `select_extend`).

### 결정 6 — 새 로그 줄은 없다

반복 늘리기도 `copy> extend row=R col=C`를 찍고(`dumpCopy`), 반복이므로 `pointer> repeat n=N dt=MS`가 앞에 선다. 단위는 그 둘과 `clip>`
글자로 보인다. 줄 모양을 안 바꾸므로 SE 검사 39 · 40의 `copy> extend` 판정이 그대로 선다.

## 검증

호스트.

- `pointer_test`: (a) 늘리기 누름 · 뗌 뒤 100ms의 같은 자리 누름(`extend = false` — Shift를 뗐다)이 `cancel` ·
  `select_extend{ unit = word }`, `clicks` 2, `dragging`. 셋째가 `line`, `clicks` 3. 넷째도 `line`. (b) 늘리기 뒤 끌고 뗀 다음 누름은
  처음부터다(`cancel` · `deselect`). (c) 보통 연속의 둘째 누름이 `extend = true`여도 `select_start(word)` — 검사 37 그대로. SE 검사 35의
  마지막 두 줄("the press after an extension starts over")은 (a)가 뒤집는다 — 끌고 뗀 뒤로 옮긴다.
- `vt_test`(같은 `mc` 화면 `alpha beta-gamma (delta)  eps`): (a) `beta`(6~9)를 남기고 `copyExtendAt(0, 0, null)` → `alpha beta`, 뗀 뒤
  `copyExtendAt(0, 0, .word)` → 앵커 쪽 단어까지 `alpha beta-gamma`, 단어 앵커 pin 하나가 는다. (b) 같은 자리에서 `.line` → 줄 전체,
  pin이 다시 줄어든다. (c) 오른쪽 — `be`(6~7)를 남기고 `(delta)`의 `l`로 null → `.word` → `beta-gamma (delta`. (d) 단어 방식의 남은 선택에
  `.word` — pin 수 그대로, 앵커가 안 옮겨 간다. (e) 남은 선택이 없으면 `.word`도 아무 일도 안 한다.

게스트(ER-M0, `pointer` 체인 부팅 A — SE 검사 41 뒤, 같은 줄 ROW `mc-one mc-two:three`. `mc-one` 0~5열, `mc-two` 7~12열, `three` 14~18열).

1. (검사 42) 8열에서 11열로 끌어 뗌 → `clip> len=4 text=c-tw`. Shift를 누른 채 1열을 두 번 클릭(hmp 넷) → `repeat n=2`, 마지막
   `clip> len=13 text=mc-one mc-two`. 첫 뗌의 `clip>`은 `c-one mc-tw`(11)다. 왼쪽인 이유 — 반복에서 가까운 끝을 다시 고르는 mutation은
   오른쪽 늘리기에서는 같은 앵커를 뽑아 못 잡는다(조사 5). 그 mutation이면 `mc-one`(6), 연속을 안 기억하면 `c-one mc-tw`(11).
2. (검사 43) Shift가 떨어진 뒤(`sleep 3.2`) 다시 8~11열을 끌어 뗌 → Shift를 누른 채 16열을 세 번 클릭(hmp 여섯) → `repeat n=3`,
   마지막 `clip> len=19 text=mc-one mc-two:three`. 셋째를 단어로 두면 `mc-two:three`(12), 연속을 안 기억하면 `c-two:thr`(9).

기존 검사의 영향: SE 검사 39(18열) → 40(0열)은 열이 멀고 0.7초 넘게 떨어져 반복이 아니다. 41의 둘째 클릭은 남은 선택이 없는 보통
누름이다. 판정 줄은 그대로다.

mutation: (1) 늘리기 누름이 `last`를 안 쓴다(SE의 모양) → 검사 42가 11. (2) 반복의 앵커를 가까운 끝으로 → 검사 42가 6. (3) 횟수 3을
단어로 → 검사 43이 12. 셋 다 호스트 테스트가 먼저 잡을 것이므로 게스트까지 보낼 때는 `zig build test` 줄을 `if false`로 바꾼
`check.sh` 사본을 마운트한다(SE 기억 4).

## Milestone

- ER-M0 하나. 순수 층(`pointer` · `vt`)과 배선(`main.zig`의 한 갈래)이 함께 작고, 따로 떼면 M0이 게스트 동작을 이미 바꾼다(`Gesture`의
  연속 기억) — SE처럼 "배선은 하되 동작은 그대로"인 M0을 만들 자리가 없다. 호스트 테스트 · 게이트 검사 42 · 43 · mutation 셋 · 루트 게이트,
  닫기(design `Status` · completed · 소개 페이지 "마우스 · 터치패드" 한 줄 · 기억 · HANDOFF).

## 위험

1. Shift가 떨어진 뒤의 빠른 클릭이 늘리기가 된다(결정 2). Shift 클릭 바로 뒤 500ms · 8픽셀 안에서 Shift 없이 누르면 단어 늘리기다 —
   사람은 그 자리에서 선택을 지우려 했을 수 있다. 같은 규칙이 반대쪽(보통 클릭 뒤 Shift 클릭은 더블클릭)에도 이미 있다. 실기에서
   어색하면 둘째 누름의 Shift를 보는 것이 다른 후보였다.
2. 첫 Shift 클릭의 뗌도 복사한다 — 더블클릭의 첫 누름(보통 클릭)이 아무것도 안 복사하는 것과 다르다. 클립보드에는 마지막 뗌의 글자가
   남으므로 사람이 보는 결과는 같다. `clip>` 줄은 누름마다 하나다(검사 42 · 43이 마지막 줄을 본다).
3. 늘리기 반복 중 단어가 없는 칸(빈 칸)을 누르면 `copyWordSel`이 null이라 선택이 비고 남은 선택이 사라진다(MC의 빈 칸 더블클릭과 같다).
   그 뒤의 셋째 누름은 `hasLinger`가 거짓이라 `copyExtendAt`이 아무 일도 안 한다 — copy mode에 안 들어가므로 뗌도 복사하지 않는다.

## 비목표

1. 둘째 누름의 Shift를 보기(결정 2의 다른 후보). 위험 1이 실기에서 거슬리면 연다 — `repeats`에 조건 하나.
2. 움직이는 끝만 단위로 넓히기(결정 3의 다른 후보).
3. SE 비목표 1 · 2 · 3 · 5 · 6 · 7은 그대로 닫혀 있다(키 입력이 지우기, 키보드 `y` 뒤 남기기, 다시 복사하는 키, 오른쪽 버튼 늘리기, 끌어
   옮기기, 자동 스크롤).

## 관련

- SE design 결정 3(이번에 바꾸는 "연속을 끊는다") · 결정 4(가까운 끝) · 비목표 4(이번에 연 것).
- MC design 결정 3(반복) · 결정 4(단어 앵커 pin) · 결정 6(횟수가 단위).
- `docs/decisions/project_shift_extend.md` · `project_multi_click.md`.
