# SW-M2 — viewport와 화면 밖 column

Date: 2026-11-18
Design: `docs/specs/2026-11-18-tars-strip-workspace-design.md`(확인 9~12, 결정 13~18)
Status: 끝났다(2026-11-19). 결과는 맨 아래. 다음은 SW-M3. 브랜치 `app-layer-0-3`.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트(`sw-impl`, Opus). lead는 plan · diff 대조 · 게이트 · commit. 서브에이전트는 commit하지 않는다.

고치는 파일:

- `terminal/src/layout.zig` — `first`, 폭 규칙, `visible` · `reveal` · `view`.
- `terminal/src/layout_test.zig` — 검사 5 · 10 · 15 · 16의 다시 쓰기(아래), 새 검사 21~23.
- `terminal/src/status.zig` · `status_test.zig` — `3/7` 칸.
- `terminal/src/main.zig` — `reveal` 부르기, `applyLayout`의 크기 비교, 그리기 · verify · 포인터의 `visible`, `strip>` 줄의 `view=`,
  상태 줄 꼬리 셈.
- `pane/check.sh` — 16d의 `strip>` 정규식, 새 검사 16e.
- `docs/help/desk.md` — 화면 밖 column과 `3/7`.

## 이 milestone이 끝나면

- column이 셋 이상이면 화면에는 반 폭 column 둘이 보이고, 포커스가 옮기면 viewport가 column 단위로 가장 적게 움직인다.
- 화면 밖 셸은 크기가 그대로다(scroll이 resize하지 않는다).
- 상태 줄에 `  2/3` 칸(포커스 column / 전체), column이 셋 이상일 때만.
- 지금 게이트의 모양(column 둘 이하)은 한 글자도 안 바뀐다.

## 착수 전에 확정한 것

1. 폭(결정 13). column 수 `n`이 1이면 `share(cols, 1, 0)`, 2 이상이면 모든 column이 `share(cols, 2, k)`의 폭이다. 보이는
   column 둘 가운데 왼쪽은 `k = 0`의 위치 · 폭, 오른쪽은 `k = 1`의 것을 쓴다. 155에서 77 · 77, 154에서 76 · 77이다.
   M0 · M1의 셋 이상 "고르게"(51 · 51 · 51)는 없어진다. 저장하는 폭은 없다.
2. `Strip.first: u4`(결정 14). 0 ≤ `first` ≤ max(0, `len` − 2)이다. 보이는 column은 `first`와 (있으면) `first + 1`이다.
   - `reveal(leaf) bool`: 그 slot의 column `c`가 `c < first`이면 `first = c`, `c > first + 1`이면 `first = c − 1`. 바뀌었으면
     true를 돌려준다. 없는 slot이면 false.
   - `remove`는 끝에 `first`를 범위 안으로 당긴다.
   - `split`은 `first`를 안 건드린다 — 보이게 하는 것은 `main.zig`가 `reveal`로 한다(포커스를 정하는 쪽이 `main.zig`다).
   - `first`는 `std.meta.eql` 비교에 들어간다 — scroll된 프레임은 통째로 다시 그린다(`last_strip`).
3. `rects`(결정 15)는 모든 slot에 쓴다. 크기는 1의 폭과 지금의 높이 나누기다. 보이는 column은 화면 좌표이고, 화면 밖 column은
   `col = whole.col`로 둔다(그려지지 않는다 — 크기만 뜻이 있다). `visible(leaf) bool`이 가른다.
4. `separators`는 보이는 것만 낸다 — 보이는 column이 둘이면 세로선 하나, 그리고 보이는 column들의 가로선. `hit`은 보이는
   slot만 본다. `neighbor`는 지금처럼 column 순번으로 고른다(화면 밖으로도 간다 — 그다음 `reveal`이 viewport를 옮긴다).
   `heir`도 그대로다.
5. `split`의 크기 판정. `.right`는 끼운 뒤의 보이는 개수 `min(len + 1, 2)`로 판정한다(155칸이면 언제나 된다). `.below`는
   그대로다.
6. `view() struct { first, last }`(0부터): `strip>` 줄의 `view=<first+1>-<last+1>`과 상태 칸이 쓴다.
7. `main.zig`:
   - 포커스를 바꾸는 모든 자리 뒤에 `if (ws.strip.reveal(ws.focus)) _ = try applyLayout(...)`과 다시 그리기. 자리: 분할(새
     slot을 포커스한 뒤), `focus_next` · `focus_prev`, 이웃, 닫기(`heir` 뒤 · `remove` 뒤). 닫기는 이미 `applyLayout`으로 가는지
     구현 전에 본다.
   - `applyLayout`: `cols` · `rows`가 다를 때만 `Screen.resize` · `pty.resize` · 버퍼 다시 잡기. 위치만 다르면 `p.rect`만 고친다.
   - `render`의 pane 루프와 `verifyFrame`의 pane 루프: `!ws.strip.visible(leaf)`이면 건너뛴다. 포커스는 언제나 보인다
     (`reveal`). 포인터는 `hit`이 걸러 준다. 끌기 중의 `clampInto`는 누른 pane(보이는 것)의 사각형을 쓴다.
   - `strip>` 줄: `terminal: strip> cols=<n> focus_col=<k> heights=<…> view=<a>-<b>`. 바뀐 프레임에만.
8. 상태 칸(결정 16). `statusText`에 인자 `columns: ?Columns`(`at` · `total`, 1~8)를 더하고, `W2` 칸 뒤 · `COPY` 앞에
   `GAP ++ "<at>/<total>"`를 쓴다. `COLS_TAIL_LEN = GAP.len + 3`. `main.zig`는 `len ≥ 3`일 때만 값을 넘긴다. `drawStatus`가
   물러나 세는 꼬리에 그 길이를 더한다(`ws_len`과 같은 모양). 색은 `W2` 칸과 같은 `STATUS_FG`다. `status_test`에 칸이 있는
   줄 · 없는 줄과 `W2` · `COPY`와 함께인 줄의 글자를 더한다.
9. pane 체인 16d의 `wait_for_strip` 정규식 둘(`heights=1,3$` · `heights=1,2$`)은 끝에 ` view=1-2`를 붙인다.
10. 새 검사 16e는 16d 뒤 · 검사 6 앞이다. 시작은 `0 | (1 / 2)`, 포커스 2(오른쪽 아래)다. slot 번호는 비어 있는 가장 작은 것이다.
    - `Cmd+D` → 새 slot 3이 셋째 column. `panes=4 focus=3 rect=78,0 77x47`, `strip> cols=3 focus_col=3 heights=1,2,1 view=2-3`,
      상태 줄 꼬리 `  3/3`.
    - `Cmd+D` → slot 4가 넷째 column. `rect=78,0 77x47`, `cols=4 focus_col=4 heights=1,2,1,1 view=3-4`, `  4/4`.
    - `Cmd+Opt+←` → slot 3, 화면 안이라 scroll 없음: `focus=3 rect=0,0 77x47`, `view=3-4`, `  3/4`.
    - `Cmd+Opt+←` → 둘째 column의 맨 위 줄 규칙으로 slot 1: `focus=1 rect=0,0 77x23`, `view=2-3`, `  2/4`.
    - `Cmd+Opt+←` → slot 0: `focus=0 rect=0,0 77x47`, `view=1-2`, `  1/4`.
    - 화면 밖 셸의 크기가 그대로인 것: 이 사이에 `spawned` 줄 수가 그대로이고, 새 slot 3 · 4의 셸이 `$COLUMNS` 77을 안다
      (검사 3과 같은 방법으로 slot 4에서 한 번).
    - 되돌리기: `Cmd+]`를 눌러 slot 4로(순서 0 · 1 · 2 · 3 · 4 — 네 번), `Cmd+W` → `heir`는 왼쪽 column의 slot 3, 다시 `Cmd+W`
      → 왼쪽 column의 맨 위 줄 slot 1. 그 뒤 `Cmd+Opt+↓` → slot 2. 끝 모양: `panes=3 focus=2 rect=78,24 77x23`,
      `strip> cols=2 focus_col=2 heights=1,2 view=1-2`, 상태 줄에 칸 없음. 닫을 때마다 `child exited`가 하나 는 것까지 기다린다.
11. 도움말: "column이 셋 이상이면 화면에는 둘이 보이고 `Cmd+Option+←→`로 옮겨 다닌다. 상태 줄의 `2/3`이 지금 column과 전체다."

## `layout_test`

- 그대로: 1~4 · 6~9 · 11~14 · 17~20. 단언을 고쳐야 통과하면 멈추고 보고한다.
- 다시 쓰는 것과 그 이유:
  - 5(여덟, 안 겹침, 격자 안): 보이는 slot만 "격자 안 · 안 겹침"을 본다. 화면 밖 slot은 크기만(폭 77 · 높이 > 0).
  - 10(정확히 한 번 덮기): `first`를 0부터 끝까지 옮기며 보이는 pane + 구분선이 격자를 정확히 한 번 덮는지 본다.
  - 15(이웃): "null ⇔ 끝"의 끝을 사각형이 아니라 순번으로 본다(← 첫 column, → 끝 column, ↑↓ column 안의 끝). 마주 봄은
    ← →가 옆 column(순번 ±1)이고 줄 조건은 그대로, ↑↓는 그대로다. 물은 수를 적는다.
  - 16(고르게): column 쪽만 바뀐다 — 셋이면 77 · 77 폭에 `view`가 정해지는 대로. 줄 쪽(15 · 15 · 15)은 그대로.
- 새 검사 21(`reveal`): 넷에서 `first`가 0 → 끝으로, 끝 → 0으로 움직이는 모든 순서에서 가장 적게 움직이고 포커스가 보인다.
- 새 검사 22(`remove`와 `first`): 넷 · `first = 2`에서 끝 column을 지우면 `first = 1`, 둘이 남으면 0, 하나면 전체 폭.
- 새 검사 23(크기 그대로): `reveal`로 scroll해도 모든 slot의 `cols` · `rows`가 그대로이고 바뀌는 것은 보이는 것의 위치다.

## 할 일

1. `layout.zig` · `layout_test.zig`. 호스트 `zig run terminal/src/layout_test.zig`.
2. `status.zig` · `status_test.zig`. 호스트 `zig run`이 되는지 보고(input 모듈을 받는다), 안 되면 `make quick`.
3. `main.zig`.
4. `pane/check.sh` 16d · 16e, 도움말.
5. lead: `make quick`, 체인 `pane` · `pointer` · `dictation` · `hangul`(상태 줄 글자), 루트 게이트.

## 판정

- `layout_test` · `status_test` 통과. 체인 `pane`(16e 포함) · `pointer` · `dictation` · `hangul` PASS. 루트 게이트 34/34.

## 결과 (2026-11-19)

1. 구현은 Herdr 서브에이전트(`sw-impl`, Opus) 8분 39초 + 고침 1분 38초. lead가 `layout.zig`의 코드 줄 전부와 `main.zig`의
   지운 줄 · 더한 줄을 대조했다. 닫기 경로는 `reveal` 다음 줄이 이미 `applyLayout`이다.
2. 고침 하나(design 결정 13에 적음): 첫 판은 셋 이상에서도 자리의 폭(`share(cols, 2, k)`)을 써서 짝수 격자(154)에서 column이
   오른쪽 자리(77) → 왼쪽 자리(76)로 넘어가면 resize가 일어났다(서브에이전트가 스스로 보고). 셋 이상은 모든 column이 왼쪽 반
   폭이고 짝수 격자의 끝 한 칸은 빈다. 검사 23이 155 · 154x46 두 격자에서 "reveal이 어느 slot의 크기도 안 바꾼다"를 보고, 옛
   규칙에서 실제로 실패한다(`slot 1 changed size on reveal(2)`).
3. `layout_test` · `status_test` 통과. `status_test`는 `zig run`으로 안 돈다(`c_input` 모듈) — 서브에이전트가 `translate-c`로
   묶어 호스트에서 돌렸고, 컨테이너 빌드는 체인이 했다. 검사 15의 물음은 66,384(M1과 같다, 끝 판정만 순번으로).
4. 체인: `pane` 200초 · `pointer` 273초 · `dictation` 228초 · `hangul` 214초 PASS. 16e의 줄: `view=2-3` → `view=3-4`(넷째
   셸 `$COLUMNS` 77) → `Cmd+Opt+←` 셋으로 `view=1-2`, 셸이 다시 뜨지 않음, 둘을 닫아 `0 | (1 / 2)`로 돌아오면 상태 칸이 없다.
   `hangul`이 그대로라 column 둘 이하의 상태 줄은 한 글자도 안 바뀌었다.
5. `status_text` 도우미가 검사 7 앞에 정의돼 있어 16e에서 못 썼다 — 도우미 절로 옮겼다.
6. 루트 게이트 34/34 첫 판 PASS(2,170초, `out/gate-logs/20261118-143052`).
7. 남은 것(게이트 밖): 끄는 선택 중에 키로 viewport가 옮겨 누른 pane이 화면 밖이 되면 `clampInto`가 의미 없는 위치(`col =
   whole.col`)의 사각형을 쓴다. 다시 보이는 pane은 그동안 `cellsReuse`를 안 불렀다가 통째 프레임에 한 번에 그린다 — verify
   모드(`TARS_RENDER_VERIFY=1`)의 pane 체인이 16e에서 잔상을 못 찾았다.
