# SW-M0 — 트리를 strip으로 (눈에 보이는 변화 0)

Date: 2026-11-18
Design: `docs/specs/2026-11-18-tars-strip-workspace-design.md`(결정 1~10, 12)
Status: 끝났다(2026-11-18). 결과는 맨 아래. 다음은 SW-M1. 브랜치 `app-layer-0-3`.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트(Opus)에 맡긴다(기억 `feedback_herdr_subagents`). lead는 plan, 보고된 diff를 실제 파일과 대조,
`git diff --stat`의 더한 줄 · 지운 줄, 게이트, commit을 맡는다. 서브에이전트는 commit하지 않는다.

고치는 파일:

- `terminal/src/layout.zig` — `Tree`를 `Strip`으로 다시 쓴다. 바깥 면은 그대로(design 결정 2).
- `terminal/src/layout_test.zig` — 타입 이름, 검사 8, 새 검사 16~19.
- `terminal/src/main.zig` — 타입 · 필드 이름(`tree` → `strip`, `last_tree` → `last_strip`)과 트리를 말하는 주석. 동작 변화 0.
- `pointer/check.sh:874` — 주석 한 줄의 `layout.Tree.hit` → `layout.Strip.hit`. 판정 줄은 안 바뀐다.
- `docs/guides/key-files.md:106` — `layout.zig` 줄의 "패널 트리" → strip.

안 고치는 것: `pane/check.sh` · `dictation/check.sh`의 판정, `input.zig`(키는 그대로), `status.zig`(`3/7`은 M2).

## 이 milestone이 끝나면

- `layout.Strip`이 column 목록 · column 안 pane 목록으로 사각형을 낸다. 폭과 높이는 고르게 나눈다(design 결정 4).
- 게이트가 쓰는 세 모양(패널 하나 · `0 | 1` · `0 | (1 / 2)`)의 `pane>` 줄 · 화면 · `$COLUMNS`가 지금과 한 글자도 같다.
- 게이트가 안 쓰는 모양은 달라진다(design 결정 10): `Cmd+D` 셋째가 51 · 51 · 51, column 안 셋째가 15 · 15 · 15.

## 착수 전에 확정한 것

2026-11-18, HEAD `9d1a0cd` + 이 plan의 commit.

1. 자료 모양(결정 1). 이름은 자유이나 뜻은 이것이다.

   ~~~zig
   const Column = struct { slots: [MAX_LEAVES]u4, len: u4 };
   pub const Strip = struct { cols: [MAX_LEAVES]Column, len: u4 };
   ~~~

   쓰지 않는 칸은 늘 0이다. 빼고 당긴 뒤 비는 끝 칸도 0으로 되돌린다. 그래야 같은 배치의 두 값이 `std.meta.eql`로
   같다(`main.zig`의 `last_strip` 비교, 확인 1). 검사 17이 이것을 본다.
2. 고르게 나누기(결정 4)는 함수 하나다 — 길이 `L`, 개수 `n`, 순번 `i`를 받아 (시작, 길이)를 낸다. `rects` · `separators` ·
   `split`의 크기 판정 · `neighbor`가 모두 이것을 부른다. 같은 산수를 두 번 짜지 않는다(옛 `halves` 주석과 같은 이유).
   나머지 `r = (L-(n-1)) % n`은 뒤의 `r`개가 한 칸씩 더 받는다. 155에서 둘이면 77 · 77, 154에서 둘이면 76 · 77이다.
3. `split`(결정 5). `.right`는 포커스 column 뒤에 column 하나를 끼운다. 판정 길이는 `whole.cols`, 개수는 끼운 뒤의 column
   수다. `.below`는 같은 column에서 포커스 다음 자리에 끼운다. 판정 길이는 `whole.rows`, 개수는 끼운 뒤 그 column의 pane
   수다. `L < 2n-1`이면 null이다. pane이 여덟이어도 null이다. 없는 slot이면 null이다.
4. `remove`(결정 6). column이 비면 column을 빼고 뒤를 당긴다. 없는 slot이면 아무 일도 안 한다.
5. `separators`의 순서. column 순서대로, 둘째 column부터는 그 앞의 세로선을 먼저 내고, 그다음 그 column의 가로선을 위에서
   아래로 낸다. `0 | (1 / 2)`이면 `[77,0 1x47, 78,23 77x1]`이다. 검사 9가 `s2[1]`을 가로선으로 본다.
6. `neighbor`(결정 8). `hit`에 묻지 않고 목록으로 고른다. `←` `→`: 옆 column의 pane 가운데 시작 줄 ≤ 포커스의 맨 위 줄인
   마지막 pane이다. 이 규칙이면 그 줄이 가로 구분선일 때 구분선 위 pane이 된다. `↑` `↓`: 같은 column에서 순번 ±1이다.
7. `heir`(결정 9). 같은 column의 순번 −1, 없으면 +1. column에 하나뿐이면 왼쪽 column, 없으면 오른쪽 column에서 6의
   `←` `→` 규칙으로 고른다. strip에 하나뿐이면 자기 자신이다.
8. `hit`은 `rects`로 얻은 사각형을 훑는 지금 모양 그대로 둔다. `clampInto`는 안 바뀐다.
9. 크기. `Strip`은 8 × (8 + 1) + 1 = 73바이트 남짓이다. `Workspace` 아홉에 들어가도 `App`의 크기는 거의 그대로다.

## `layout_test`

- 검사 1~7 · 9~15: `layout.Tree` → `layout.Strip`. 단언은 그대로 둔다. 주석의 "트리" · "형제"는 strip의 말로 고친다. 단언을
  고쳐야 통과한다면 그것은 구현이 틀린 것이다. 고치지 말고 lead에게 보고한다.
- 검사 8: `t.root != null` 대신 `count() == 0`과 `rects`가 아무 칸도 안 쓰는 것을 본다.
- 검사 15는 단언까지 그대로다. 47줄 · 46줄 격자에서 옆 column의 구분선 줄에 시작 줄이 떨어지는 조합은 모두 pane이 아홉
  이상이다(lead가 셈, 한도 여덟). 그래서 "마주 보는 pane이 맨 위 줄을 덮는다"가 strip에서도 그대로 서야 한다. 떨어지는
  경우는 검사 18이 따로 본다.
- 새 검사 16(고르게): `.right` 셋이면 155에서 `0,0 51x47 · 52,0 51x47 · 104,0 51x47`, `.below` 셋이면 47에서
  `0,0 155x15 · 0,16 155x15 · 0,32 155x15`. 154 · 46에서 나머지가 뒤로 가는 것도 하나씩 본다.
- 새 검사 17(slot 번호와 같음): `0 | 1 | 2`에서 가운데 column(1)을 지우면 0 · 2의 slot이 그대로이고, 다시 `.right`로 가르면
  1이 돌아온다. 같은 배치를 다른 순서로 만든 두 strip이 `std.meta.eql`로 같다(지우고 당긴 칸이 0인지).
- 새 검사 18(이웃이 구분선 줄에 떨어짐): 45줄 격자에 왼쪽 column pane 둘(`0,0 x22` · 구분선 22 · 시작 23)과 오른쪽 column
  pane 넷(시작 0 · 11 · 22 · 34, 높이 10 · 10 · 11 · 11)을 만든다. 오른쪽 셋째(시작 22)의 `←`는 구분선 위의 왼쪽 첫 pane이다.
  왼쪽 둘째(시작 23)의 `→`는 오른쪽 셋째다. 사각형 숫자도 함께 단언한다.
- 새 검사 19(heir의 갈래 넷): 같은 column 위 · 같은 column 아래 · 빈 column의 왼쪽 · 맨 왼쪽 빈 column의 오른쪽.

## 할 일

1. `layout.zig`를 다시 쓴다. 파일 머리 주석은 strip의 말로 쓴다(R-SW-8: 순수 모듈, 좌표는 셀).
2. `layout_test.zig`를 위대로 고친다. 호스트에서 `zig run terminal/src/layout_test.zig`, 마지막 줄 `all checks passed`.
3. `main.zig`의 이름과 주석. `zig build`가 컨테이너에서 서는지는 lead가 체인으로 본다.
4. `pointer/check.sh` 주석 한 줄, `key-files.md` 한 줄.
5. lead: `make quick`, 체인 `pane` · `pointer` · `dictation`(각각 `make check CHAIN=…`). 그다음 루트 게이트(35분쯤).

## 판정

- `layout_test`: 모든 검사 통과. 검사 1~7 · 9~14의 단언이 diff에 없다(`git diff terminal/src/layout_test.zig | rg '^-.*expect'`가
  검사 8 밖에서 이름만 바뀐 줄이다).
- `pane` · `pointer` · `dictation` 체인 PASS. 판정 줄 diff 0.
- 루트 게이트 34/34.

## 결과 (2026-11-18)

1. 구현은 Herdr 서브에이전트(Opus, pane `sw-impl`)가 5분 51초에 했다. lead가 diff를 대조했다: `main.zig`의 주석 아닌 변경
   줄은 이름 바꾸기 29쌍뿐이고, `layout_test`에서 지워진 `expect` 줄은 `expectCount`의 시그니처 하나다(검사 1~7 · 9~15의 단언
   그대로).
2. `layout_test`(호스트 zig 0.17.1): 모든 검사 통과, OK 139줄. 검사 15는 71,680 물음. 검사 17은 "당긴 칸을 0으로"를 빼면
   `PulledColumnNotCleared` · `PulledSlotNotCleared`로 실패한다(서브에이전트가 사본으로 확인).
3. 고르게 나누기는 `share(l, n, i)` 하나다. 빼기는 `-|`로 넘치지 않게 했다 — 선 배치에서 격자가 줄면(전체 화면 끄기) 몫이
   0이 될 수 있다. 트리의 `halves`도 같은 경우에 0을 냈다.
4. `heir`는 `whole`이 필요 없다 — 혼자인 pane의 맨 위 줄은 0이고, 그 줄 이하에서 시작하는 pane은 어느 column이든 첫 pane이다.
5. `key-files.md`는 106~109 네 줄을 고쳤다(뒤 세 줄이 노드 풀을 설명하고 있었다).
6. 체인: `pane` 192초 · `pointer` 279초 · `dictation` 237초 모두 PASS, 판정 줄 diff 0. pane 체인의 덤프가 트리 때와 같은
   숫자다 — `rect=78,0 77x47 sep ink=6016`, `rect=78,24 77x23 sep ink=15872`.
7. 루트 게이트 34/34 첫 판 PASS(2,169초, `out/gate-logs/20261118-122629`).
8. 다시 밟은 함정: 게이트의 출력을 `out/` 안의 파일로 돌리면 게이트가 `out/`을 지워 파일이 사라진다(fd에는 계속 쓴다).
   게이트 로그는 scratchpad나 `out/` 밖에 둔다.
