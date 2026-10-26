# WP-M3 — 방향 포커스

Date: 2026-10-27
Design: `docs/specs/2026-10-03-tars-workspace-panes-design.md`
Status: 끝났다(2026-10-27). `layout_test` 검사 14 · 15, `input_test` 검사 84 · 85, `pane/check.sh` 검사 16이 섰고
루트 게이트 22/22 PASS(10분 27초). 값은 아래 "M3가 실측한 것" 절에 있다.

## 이 milestone이 끝나면

- `Cmd+Option+←↑↓→`가 그 방향의 이웃 패널로 포커스를 옮긴다(design 키 표의
  마지막 줄). 순환(`Cmd+]` · `Cmd+[`)은 그대로다.
- 마주 보는 이웃이 여럿이면 포커스 변의 시작점(좌우 이동이면 맨 위 줄, 상하
  이동이면 맨 왼쪽 칸)과 마주 보는 패널로 간다. `0 | (1 / 2)`에서 0의
  `Cmd+Option+→`는 1이다(사용자 결정, 2026-10-26).
- 그 방향에 패널이 없으면 아무 일도 안 한다 — 감기지 않는다. 감기는 이동은
  순환이 맡는다(사용자 결정, 2026-10-26). 로그도 다시 그리기도 없다.
- `pane/check.sh`에 검사 16이 붙는다. 루트 게이트 22/22.

## 착수 전에 확정한 것

1. 이웃은 `hit`이 찾는다. 포커스 사각형 `f`의 변 시작점에서 구분선 한 칸을
   건너뛴 격자 칸이다 — ← `(f.col - 2, f.row)`, → `(f.col + f.cols + 1, f.row)`,
   ↑ `(f.col, f.row - 2)`, ↓ `(f.col, f.row + f.rows + 1)`. 사각형 산수를 다시
   하지 않는다(`hit` 주석의 "한 칸 어긋남").
2. 그 칸은 구분선 위에 떨어지지 않는다. 구분선의 양쪽은 같은 행(열) 구간을
   같은 `halves`로 나누므로 칸 구간이 하나의 이분 나무에서 나온다. 한쪽 잎이
   시작하는 행은 그 나무의 어느 구간의 시작이고, 구분선은 어느 구간의
   가운데다. 시작이 가운데와 같으려면 그 구간을 부분으로 품거나 품겨야 하는데
   어느 쪽도 안 된다. `layout_test`가 잎 여덟까지의 모양으로 이것을 본다
   (검사 14의 "null이 아닌데 구분선" 없음).
3. 격자 끝은 `hit`의 null이다. 다만 ← · ↑은 `u16` 뺄셈이 넘치므로 `f.col < 2`
   · `f.row < 2`면 먼저 null이다(`whole`의 왼쪽 위가 0,0이 아니어도 `hit`이
   `whole` 밖을 null로 본다).
4. 키는 Meta 분기의 `shifted()` switch 뒤에 `alted()` switch 하나다(design
   위험 6이 예고한 모양). 표에 없는 `Cmd+Option` 조합은 null이고 Option 없는
   Cmd 표로 떨어지지 않는다 — Shift와 같은 규칙(WP-M1 실측 5). 바뀌는 것이
   셋이다: `Cmd+Option+←` · `→`가 `0x01` · `0x05`가 아니라 포커스 이동이 되고,
   `Cmd+Option+Backspace`가 `0x15`가 아니라 맨 Backspace, `Cmd+Option+D` 등이
   패널 명령이 아니라 맨 글자가 된다.
5. `Cmd+Shift+Option+화살표`는 `shifted()` switch가 먼저 보므로 null이다.
6. `Pane` enum에 variant 넷(`focus_left` · `focus_right` · `focus_up` ·
   `focus_down`)을 더한다. payload를 안 두는 이유는 `workspace_N`과 같다(결정 4).
   `layout`에는 `Side = enum { left, right, up, down }`이 선다 — 분할의
   `Dir`(right · below)과 따로인 이유는 분할에 왼쪽 · 위가 없어서다.
7. 이웃이 없으면 `main.zig`가 `continue`한다 — `workspace_N`의 없는 번호와
   같은 길이라 `needs_redraw`를 건너뛴다. `dumpPane`은 서명이 같으면 안
   찍으므로 게이트는 `pane>` 줄 수가 안 느는 것으로 본다.
8. copy mode 안에서는 copy 분기가 `chord()`보다 앞이라 이 키가 패널 명령이
   안 된다(검사 61과 같은 성질). `input_test`에 한 줄 더한다.

## Task 1: `layout.zig` · `layout_test.zig`

- `pub const Side = enum { left, right, up, down };`
- `pub fn neighbor(self: *const Tree, whole: Rect, leaf: u4, side: Side) ?u4` —
  확정 1 · 3. 없는 잎이면 null.
- `layout_test` 검사 14: `0 | (1 / 2)`에서 1←0 · 2←0 · 0→1(동률, 시작점) ·
  1↓2 · 2↑1 · 0의 ← · ↑ · ↓과 1의 → · ↑과 2의 → · ↓이 null · 잎 하나면 넷 다
  null. 검사 15: 확정 2 — 분할을 여러 모양으로 여덟까지 쌓으며 매번 모든 잎 ·
  모든 방향의 결과가 null이거나 그 방향에 있는 잎이다(사각형이 변 너머에 있고
  변과 겹친다).

## Task 2: `input.zig` · `input_test.zig`

- `Pane`에 확정 6의 넷. `chord` Meta 분기에 확정 4의 `alted()` switch.
- `input_test` 검사 84: `Cmd+Option+←↑↓→` 넷이 `.focus_*` · `Cmd+Option+D`가
  `"d"`(Option 없는 표로 안 떨어진다) · Option을 떼면 `Cmd+←`가 다시 `0x01`.
  검사 85(음성): copy mode 안의 `Cmd+Option+←`가 패널 명령이 아니다.

## Task 3: `main.zig`

- 패널 명령 switch에 `.focus_left, .focus_right, .focus_up, .focus_down`.
  `layout.Side`로 옮기고 `ws.tree.neighbor(self.whole, ws.focus, side)`.
  null이면 `continue`(확정 7).

## Task 4: `pane/check.sh`

검사 5 뒤(패널 셋 `0 | (1 / 2)`, 포커스 2) · 검사 6 앞에 붙인다. 끝에 포커스가
2로 돌아와야 검사 6(`hangup leaf=2`)이 그대로 선다.

| 검사 | 친다 | 본다 |
|---|---|---|
| 16 | `meta_l-alt-up` | `panes=3 focus=1 rect=78,0 ` |
| 16a | `meta_l-alt-left` | `focus=0 rect=0,0 ` |
| 16b | `meta_l-alt-right` | `focus=1 rect=78,0 `(동률에서 시작점 — 2가 아니다) |
| 16c(음성) | `meta_l-alt-right` · `meta_l-alt-up` | `pane>` 줄 수 · `key>` 줄 수가 안 는다(1은 오른쪽 위 끝) |
| 16d | `meta_l-alt-down` | `focus=2 `, row > 0 |

16c의 대조군은 16b다 — 같은 키가 바로 앞에서 포커스를 옮겼다. 모든 줄에서
`key>` 줄 수가 안 늘어야 한다(바이트가 PTY로 안 샌다).

## Task 5: 게이트

- `zig build test` — 음성 검사(검사 85 · 16c)는 빨강을 먼저 본다.
- `pane/check.sh` 한 번.
- mutation 하나: `neighbor`의 → 를 변 시작점 대신 변 끝(`f.row + f.rows - 1`)
  으로 바꾸고 `layout_test` 검사 14와 pane 체인 16b가 빨간지 본다. 되돌린다.
- 루트 게이트(배경, 약 12분).

## Task 6: 문서

plan `Status` · design `Status`(M3까지) · `project_workspace_panes.md` ·
`running-tars.md` 키 표 · `completed.md`의 WP 행 · `HANDOFF.md`. 소개 페이지는
기능 추가라 넣는다(`site/README.md`의 순서) — 사용자에게 먼저 묻는다.

## M3가 실측한 것

2026-10-27. lead가 직접 구현했다.

1. 첫 pane 체인은 부팅 전에 `input_test`에서 빨갰다 — `FAIL: code=105 -> got pane
   .focus_left`. IP-M2의 "둘 다 눌리면 Cmd가 이긴다" 검사가 `Cmd+Option+←`를
   `0x01`로 못 박고 있었다. 확정 4가 바꾸기로 한 바로 그 동작이라 기대값을
   `.focus_left`로 고쳤다. "Cmd 분기가 먼저 본다"는 순서 판정은 남는다(ESC b가
   아니다). plan이 바뀌는 셋을 적고도 그것을 못 박은 옛 검사를 안 찾았다 —
   동작을 바꾸는 확정은 `input_test`에서 그 키의 옛 기대값부터 `rg`한다.
2. 검사 15는 분할 모양 256 × 격자 둘에서 71,528번 물었고 전부 끝이거나 시작점과
   마주 보는 잎이었다(확정 2). ←의 건너뛰기를 한 칸으로 줄이면(구분선 위를
   묻는다) 검사 14의 `1 left is 0 = null`이 먼저 잡는다.
3. mutation(→가 변의 끝 `f.row + f.rows - 1`을 본다)은 `layout_test` 검사 14의
   `0 right is the top of the two (1, not 2) = 2, want 1`로 잡혔다. 체인의 16b까지는
   안 닿는다 — pane 체인이 부팅 전에 `zig build test`를 돌려 거기서 멈춘다. 그래서
   호스트 `zig run`으로 봤다.
4. 게스트의 `panes=3` 배치 줄은 정확히 다섯이다 — `focus=2`(검사 5) → `1 rect=78,0`
   (↑) → `0 rect=0,0`(←) → `1 rect=78,0`(→, 시작점) → `2 rect=78,24`(↓). 16c의 → · ↑은
   줄을 하나도 안 만들었다(감기지 않는다).
5. 호스트 `zig test src/layout_test.zig`는 `All 0 tests passed`다 — `layout_test`는
   `test` 블록이 아니라 `main`이라 `zig run`으로 돌린다.
6. 루트 게이트: 22/22 PASS, `FAIL` 0줄, prebuild 322초 + lanes 305초(단발). pane 체인
   (`CB-M0`) 51초.
