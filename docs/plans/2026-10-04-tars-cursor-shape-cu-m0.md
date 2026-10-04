# CU-M0 — 터미널이 DECSCUSR 모양 셋을 그린다

Date: 2026-10-04
Design: `docs/specs/2026-10-04-tars-cursor-shape-design.md`
Status: 끝났다(2026-10-04). `vt_test` 82~92 · `render` 검사 20~24가 초록이고,
regression 체인 셋과 반사실 둘을 돌렸다. 루트 게이트 18체인 3/3 PASS, 1시간 4분 5초,
`FAIL` 0줄. 값은 아래 "CU-M0이 실측한 것" 절에 있다.

## 이 milestone이 끝나면

- 자식이 `CSI Ps SP q`(DECSCUSR)를 보내면 셸 커서가 그 모양으로 그려진다.
  `2`(과 `1`)는 block, `6`(과 `5`)은 bar, `4`(와 `3`)는 underline, `0`과 빈
  인자는 기본값 block이다. 깜빡임 번호는 같은 모양을 가만히 그린다(design
  결정 2).
- block은 지금과 바이트까지 같다. bar는 셀 왼쪽 2×16, underline은 셀 아래
  8×2(폭 2 글자 위면 16×2)를 전용 색 `CURSOR_COLOR`(`0x00F0F0F0`)로
  칠한다(결정 1).
- copy mode · preedit · 포커스 없는 패널은 지금 규칙 그대로이고 모양보다
  앞선다(결정 4 · 5).
- `cells()`가 셸 커서에 대한 판단을 한 번 해서 `Screen.shell_cursor`에 두고,
  `main.zig`는 `cursorMark()`로 그것을 받아 칠한다. `CellGlyph`는 안
  바뀐다(결정 3).
- 새 로그 줄 `terminal: cursor>`가 매 프레임 찍힌다(결정 6).
- `vt_test` 검사 82~92, `render/check.sh` 검사 20~24가 더해진다. 새 체인은
  없다.
- 게스트의 vi는 아직 안 바뀐다(그것은 CU-M1). 이 milestone 뒤에는 셸에서
  `printf '\033[6 q'`를 치면 프롬프트의 커서가 bar로 보인다.

## 착수 전에 확정한 것

1. `RenderState.update`가 `state.cursor.visual_style`을 매번 채운다 —
   `viewport`를 정하는 같은 함수 안이다(design 실측 9). `cells()` 첫 줄의
   `try self.state.update(...)` 뒤라면 어디서든 읽을 수 있다.
2. 그 타입은 `ghostty_vt`의 `cursor.Style`이고 값이 넷이다(`bar` · `block` ·
   `underline` · `block_hollow`). `vt.zig`에서 어떤 이름으로 닿는지는
   `@TypeOf(self.state.cursor.visual_style)`로 쓰면 import 경로를 몰라도 된다.
   `switch`에 `else`를 두지 않는다 — 업스트림이 값을 더하면 컴파일이 막혀야
   한다.
3. 셸 셋(fish · zsh · bash)은 기동 · 명령 · 종료에 DECSCUSR을 한 바이트도 안
   보낸다(design 실측 8). 그래서 기존 체인의 셸 커서는 언제나 block이다.
   셸 커서의 반전에 기대는 검사는 다섯 자리다(`rg -n 'fg=102030' --glob
   '*/check.sh'`): `render/check.sh` 검사 3 · `hangul/check.sh`의
   `inverted_cells`를 부르는 넷. `copy/check.sh`의 `inverted_cells`는 copy
   커서를 센다. 다섯 다 안 흔들려야 하고, Task 5가 hangul · copy 체인을 한
   번씩 돌려 그것을 본다.
4. `dumpStyles`의 `pixel>`은 셀 가운데(`+CELL_W / 2`, `+ROW_HEIGHT / 2`)를
   읽는다. 띠는 왼쪽 두 열이나 아래 두 줄이라 거기 안 닿는다.
5. `render/check.sh`의 `type_text`에 `[`가 없다. `'[') keys+=(bracket_left) ;;`
   한 줄을 더해야 `printf '\033[6 q'`를 칠 수 있다. 나머지 글자(`p r i n t f`
   · 공백 · `'` · `\` · 숫자 · `q`)는 이미 있다.
6. 이 체인은 `set -uo pipefail`이다. `x="$(grep … | tail -n 1)"`에서 grep이
   0줄이면 파이프의 종료 코드가 1이 되므로 `|| true`를 붙인다(`set -e`는
   없어서 죽지는 않지만 습관으로 붙인다). 파이프 뒤에 `grep -q`를 두지
   않는다 — 진입 검사가 막는다(lessons "파이프 뒤의 `grep -q`").
7. 한 프레임의 덤프 순서는 `dumpImages` → `dumpScreen` → … → `dumpStyles`
   → `dumpInk` → `dumpScroll`이다. `cursor>`를 `dumpInk` 뒤에 두면
   `copy/check.sh`의 `last_frame`(마지막 `screen>`부터 파일 끝까지)이 그 줄을
   담는다. 이 체인에는 `last_frame`이 없으므로 같은 awk를 옮겨 온다.
8. `renderPane`을 부르는 자리는 둘이다(포커스 아닌 패널의 루프 · 포커스
   패널). 둘 다 `cells()` 바로 뒤라 `cursorMark()`를 부를 수 있다. 포커스
   아닌 패널은 `focused = false`라 null이 나온다 — 따로 막을 코드가 없다.
9. `vt_test`에 `cu_`로 시작하는 이름이 없다(`rg -c '\bcu_' terminal/src/vt_test.zig`
   0줄). `vt_test`는 `main()` 하나가 파일 전체라 지역 변수 이름이 전부
   부딪친다 — 새 이름은 전부 `cu_`로 시작한다.
10. `copyEnter`는 `state.cursor.viewport`를 읽으므로 그 화면에서 `cells()`를
    한 번 부른 뒤에 부른다(lessons "`vt.Screen`을 새로 만들고 곧바로
    `copyMove`").
11. 기대값의 산수. 셀이 8×16이고(`vt_test`의 `CELL`, `main.zig`의 `CELL_W` ·
    `ROW_HEIGHT`) 두께가 둘 다 2다. bar는 `ink=32 box=2x16`, underline은
    `ink=16 box=8x2`, block은 `ink=0 box=0x0`이다.
12. `dumpStyles`는 프레임당 96셀(`STYLE_DUMP_LIMIT`)에서 자르고 셀을 행
    순서로 찍는다. 셸 커서는 프롬프트 줄, 곧 맨 아래에 가깝다. 검사 19 뒤의
    화면에는 fish가 구문 강조 색을 입힌 긴 PNG 명령 줄이 있어서 그 상한을
    넘기기 쉽고(lessons 실측 71), 넘기면 커서 셀의 `style>` 줄이 잘려
    "반전 셀 0"이 거짓으로 나온다 — 검사 21~23의 음성 판정이 아무것도 안
    보는 검사가 된다. 그래서 검사마다 `\033[H\033[2J`로 화면을 먼저 지우고,
    마지막 프레임에 `more cell(s) not shown` 줄이 없는 것을 함께 본다.
13. `main.zig`는 `zig build test`가 컴파일하지 않는다. `vt_test`가 `vt.zig`만
    import하기 때문이다. `main.zig`를 고친 뒤에는 `./prepare.sh`(= `zig
    build`)를 함께 돌린다(lessons 실측 1과 같은 구멍).

## Task 1: `terminal/src/vt.zig`

파일 스코프(`CellPx` 근처)에 상수 셋과 타입 셋을 둔다. 전부 `pub`이다 —
`vt_test`와 `main.zig`가 본다.

```zig
/// bar · underline 커서의 색(CU design 결정 1). 이 색은 커서 띠만 쓴다.
/// 기본 팔레트 256색에 없는 값이라(design 실측 9) 셀 안에서 이 색의 픽셀을
/// 세면 그것이 곧 띠다 — `main.zig`의 `SEPARATOR` · `STATUS_COPY`와 같은 이유.
pub const CURSOR_COLOR: u32 = 0x00F0F0F0;
/// bar의 폭과 underline의 높이(픽셀). 1이면 ink 값이 bar 16 · underline 16으로
/// 같아져 게이트가 숫자로 못 가른다(결정 1의 후보 표).
pub const CURSOR_BAR_W: u32 = 2;
pub const CURSOR_UNDERLINE_H: u32 = 2;

pub const CursorShape = enum { block, bar, underline };
pub const PxRect = struct { x: u32, y: u32, w: u32, h: u32 };
pub const CursorMark = struct {
    row: u16,
    col: u16,
    asked: CursorShape,
    shape: CursorShape,
    cols: u8,
    px: ?PxRect,
};
```

필드마다 doc 주석을 단다(design 결정 3의 표가 내용이다).

`Screen`에 필드 하나 — 이름이 `shell_cursor`인 이유는 copy 커서
(`copy_cursor`)와 짝을 이루게 하려는 것이고, `cells()` 안의 지역 상수
`cursor`(`self.state.cursor.viewport`)와 헷갈리지 않게 하려는 것이다.

```zig
/// 이 프레임에 그리는 셸 커서(CU design 결정 3). `cells()`가 매번 다시 정한다.
/// null이면 셸 커서가 없다 — copy mode · 포커스 없음 · 뷰포트 밖.
shell_cursor: ?CursorMark = null,
```

함수 넷.

- `fn askedShape(self: *const Screen) CursorShape` — `self.state.cursor.visual_style`을
  옮긴다. `.block`, `.block_hollow` → `.block`(결정 1), `.bar` → `.bar`,
  `.underline` → `.underline`. `else` 없음.
- `fn computeShellCursor(self: *const Screen) ?CursorMark` — design 결정 4의
  순서 그대로다.
  1. `self.copy_cursor != null`이면 null.
  2. `!self.focused`이면 null.
  3. `self.state.cursor.viewport`가 null이면 null.
  4. `asked = self.askedShape()`.
  5. `self.preedit != null`이면 `shape = .block`, `cols = 2`.
  6. 아니면 `shape = asked`. `cols`는 커서 칸의 `raw.wide == .wide`면 2, 아니면
     1이다(`row_data.items(.cells)[vp.y].slice().items(.raw)[vp.x]` — `cells()`
     본문이 같은 길로 `raws`를 얻는다).
  7. `cols`가 격자 밖으로 넘치지 않게 `@min(cols, self.state.cols - vp.x)`.
  8. `px`: block이면 null. bar면 `{ .x = col * cell.w, .y = row * cell.h, .w =
     CURSOR_BAR_W, .h = cell.h }`. underline이면 `{ .x = col * cell.w, .y =
     row * cell.h + cell.h - CURSOR_UNDERLINE_H, .w = cols * cell.w, .h =
     CURSOR_UNDERLINE_H }`.
- `pub fn cursorMark(self: *const Screen) ?CursorMark` — `self.shell_cursor`를
  돌려준다. doc 주석에 "`cells()` 뒤에 부를 것. 계산은 `cells()`가 한 번만
  한다 — 반전과 띠를 같은 값이 정해야 둘이 함께 그려지는 일이 없다".
- `pub fn cursorAsked(self: *const Screen) CursorShape` — `askedShape()`를
  돌려준다. 게이트의 `vt=` 칸이다. 이것도 "`cells()` 뒤".

`cells()`를 두 자리 고친다.

1. `findSpans()` 뒤, 행 루프 앞에 `self.shell_cursor = self.computeShellCursor();`.
2. 셸 커서 반전 조건. 지금은 `self.focused and @as(usize, vp.y) == y and …`이다.
   루프 앞에 다음 한 줄을 두고 `self.focused`를 그것으로 바꾼다.

   ```zig
   // 반전은 block일 때만이다(CU design 결정 3). bar · underline은 main.zig가
   // 띠로 칠한다. 포커스 없음은 `shell_cursor`가 이미 null로 담고 있다.
   const invert_cursor = self.shell_cursor != null and self.shell_cursor.?.shape == .block;
   ```

   capture(`|sc|`)를 안 만드는 이유는 lessons의 "짧은 이름을 새 capture에
   쓰기" 항목이다. `span`(preedit 2 · 아니면 1)과 preedit 글자 치환은 그대로
   둔다 — 폭 2 글자의 둘째 칸은 지금처럼 spacer 층이 물려받는다.

`CellGlyph`의 doc 주석 중 "inverse와 커서도 여기서 두 색을 맞바꿔 해소"를
"block 커서는 … bar · underline은 `cursorMark()`의 사각형으로 `main.zig`가
칠한다"로 고친다. 커서 층 주석("커서는 inverse와 같은 연산이다")에도 한
문단을 더해 결정 3 · 4를 가리킨다.

## Task 2: `terminal/src/vt_test.zig` — 검사 82~92

검사 81 뒤, `PASS` 앞. 화면마다 20×5 · `CELL`. 검사마다 `vt_test: … OK` 한
줄을 찍고, 실패하면 무엇이 나왔는지(`asked` · `shape` · `px` · `fg` · `bg`)를
찍은 뒤 이름 있는 error를 돌려준다(검사 81의 모양).

| 검사 | 화면 · 먹이는 것 | 본다 |
|---|---|---|
| 82 | `cu_bk`: `XY\x1b[1;2H` | 대조군. `cursorMark()`가 `row=0 col=1 asked=block shape=block cols=1 px=null` · 셀 (0,1)이 `fg=102030 bg=FFFFFF` |
| 83 | `cu_bk`에 `\x1b[6 q` | `asked=bar shape=bar px={8,0,2,16}` · 셀 (0,1)이 `'Y'`이고 `fg=FFFFFF bg=102030`(반전 없음) |
| 84 | `cu_bk`에 `\x1b[4 q` | `shape=underline px={8,14,8,2}` · 반전 없음 |
| 85 | `cu_bk`에 `\x1b[5 q` → `\x1b[3 q` → `\x1b[1 q` | 차례로 bar · underline · block(깜빡임 번호는 같은 모양, 결정 2). block에서 반전이 돌아온다 |
| 86 | `cu_bk`에 `\x1b[6 q\x1b[0 q`, 다시 `\x1b[6 q\x1b[ q` | 둘 다 block(기본값) |
| 87 | `cu_pe`: `\x1b[6 q`, `setPreedit(0xAC00)` | `asked=bar shape=block cols=2 px=null` · (0,0) · (0,1) 둘 다 반전. 이어서 `setPreedit(null)` → `shape=bar` |
| 88 | `cu_cp`: `XY\x1b[1;2H\x1b[6 q`, `cells()`, `copyEnter()` | `cursorMark()`가 null · 마지막 `cells()`에서 반전 셀이 정확히 하나(copy 커서, (0,1)). `copyExit()` 뒤 `shape=bar` |
| 89 | `cu_bk`에 `\x1b[6 q`, `focused = false` | null · 셀 (0,1) 반전 없음. 끝에 `focused = true`로 되돌린다 |
| 90 | `cu_wd`: `가\x1b[1;1H\x1b[4 q` | `cols=2 px={0,14,16,2}`. 이어서 `\x1b[6 q` → `cols=2 px={0,0,2,16}` |
| 91 | `cu_alt`: `\x1b[?1049h\x1b[6 q` → `\x1b[?1049l` | 대체 화면에서 `asked=bar`, 나온 뒤 `asked=block`이고 반전이 있다(design 실측 10) |
| 92 | `cu_sc`: 30줄을 먹이고 `\x1b[6 q`, `scrollByRows(-3)` | null(뷰포트 밖). `scrollToBottom()` 뒤 `shape=bar` |

"반전 셀"은 `fg == 0x102030`인 셀로 센다(게이트의 `inverted_cells`와 같은
표식). 검사 85 · 86처럼 같은 화면에 이어 먹일 때는 먹일 때마다 `cells()`를
다시 부른다.

먼저 82 · 83만 넣고 Task 1 전의 `vt.zig`로 돌려 83이 컴파일 에러(`cursorMark`가
없다)로 막히는 것을 본다. 그다음 Task 1을 넣고 82~92가 전부 초록인지 본다.
음성 쪽 빨강은 Task 5의 반사실 C가 맡는다.

## Task 3: `terminal/src/main.zig`

- `fillRect(fb, x, y, w, h, color)` — 두 겹 루프로 `setPixel`.
  `drawCellBackground` 옆에 둔다. `setPixel`에 범위 검사가 없다는 것을 주석에
  적는다(사각형은 패널 안에서만 나오므로 호출부가 안전하다 — `cursorMark`가
  `cols`를 격자 안으로 자른다).
- `renderPane`에 마지막 인자 `cursor: ?vt.CursorMark`를 더한다. 본문 맨 끝
  (`drawImages(.above_text)` 뒤)에서:

  ```zig
  // 커서는 무엇에도 안 가려진다(CU design 결정 3). block은 `cells()`가 이미
  // 반전으로 그렸고 `px`가 null이다.
  if (cursor) |cm| if (cm.px) |cr| fillRect(fb, o.x + cr.x, o.y + cr.y, cr.w, cr.h, vt.CURSOR_COLOR);
  ```

  capture 이름은 그 함수 안의 다른 이름과 안 부딪치게 `rg`로 먼저 본다.
- 부르는 자리 둘: 포커스 아닌 패널은 `p.screen.cursorMark()`, 포커스 패널은
  `focus.screen.cursorMark()`. 둘 다 그 화면의 `cells()` 뒤다.
- `dumpCursor(fb: drm.Framebuffer, screen: *vt.Screen, rect: layout.Rect) void` —
  `dumpInk` 뒤, `dumpScroll` 앞에서 매 프레임 부른다.

  ```
  mark가 null  → terminal: cursor> vt={asked} drawn=none
  아니면       → 커서 칸들(x: o.x + col*CELL_W .. + cols*CELL_W,
                 y: o.y + row*ROW_HEIGHT .. + ROW_HEIGHT) 안에서
                 getPixel & 0x00FFFFFF == vt.CURSOR_COLOR 인 픽셀을 세고
                 그 픽셀들의 경계 사각형(없으면 0x0)을 구한다
                 terminal: cursor> vt={asked} drawn={shape} row={d} col={d} cols={d} ink={d} box={w}x{h}
  ```

  `{asked}` · `{shape}`는 `@tagName`. 프레임버퍼 경계는 `dumpInk`처럼 호출부에서
  막는다(`x + w > fb.width`면 건너뛴다). doc 주석에 design 결정 6의 표(칸마다
  무엇을 증명하나)를 줄여 적고, 왜 사각형을 다시 계산하지 않고 픽셀을
  되읽는지를 적는다 — `cursorMark`의 `px`를 그대로 찍으면 그것은 "칠하려던
  것"이지 "칠한 것"이 아니다(IS-M0 · SH-M2의 경고와 같은 자리).

## Task 4: `render/check.sh` — 검사 20~24

검사 19(PNG) 뒤, `# ── 음성 검사` 앞에 둔다. 앞 검사들의 기대값은 하나도
안 바뀐다.

손볼 곳:

- `type_text`에 `'[') keys+=(bracket_left) ;;`(확정 5).
- `report_failure`의 marker 목록에 `"terminal: cursor>"`. 실패했을 때
  `grep -a 'terminal: cursor>' "$LOG" | tail -n 5`도 찍는다.
- 헬퍼 셋 — `copy/check.sh`의 것과 같은 모양.

  ```bash
  last_frame() {
    awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
  }
  last_cursor() { grep -a 'terminal: cursor>' "$LOG" | tail -n 1 || true; }
  # 마지막 cursor> 줄이 패턴과 맞을 때까지 기다린다(15초). wait_for_screen과
  # 같은 이유로 고정 sleep을 안 쓴다.
  wait_for_cursor() {
    local pattern="$1" i
    for i in $(seq 1 150); do
      if grep -aqE -- "$pattern" <<<"$(last_cursor)"; then return 0; fi
      sleep 0.1
    done
    return 1
  }
  inverted_now() { last_frame | grep -acE 'terminal: style> [0-9]+,[0-9]+ fg=102030 ' || true; }
  ```

- 검사들. 모양을 바꾸는 명령은 전부 화면 지우기와 한 줄이다 —
  `type_text "printf '\\033[H\\033[2J\\033[N q'"` 뒤 `type_keys ret`.
  fish가 줄을 실행하고 맨 위에 새 프롬프트를 그린 프레임에서 모양이 바뀌고,
  그 프레임에는 프롬프트 한 줄과 커서뿐이라 `style>` 상한(확정 12)에 안
  닿는다. 대문자 `H` · `J`는 `type_text`가 이미 `shift-h` · `shift-j`로
  친다. 검사 20 앞에는 `printf '\\033[H\\033[2J'`만 한 번 친다.
- 검사 20~24 모두 마지막 프레임에 `more cell(s) not shown`이 없는 것을 먼저
  본다. 있으면 반전 셀 수가 뜻을 잃으므로 그 자리에서 실패로 끝낸다.

| 검사 | 친다 | 본다 |
|---|---|---|
| 20 | `printf '\033[H\033[2J'`(대조군 — 모양은 안 건드린다) | 마지막 프레임의 반전 셀이 정확히 1 · 그 좌표 `R,C`로 `last_cursor`가 `vt=block drawn=block row=R col=C cols=1 ink=0 box=0x0`. `cursor>`의 자리가 지금까지 믿어 온 반전 셀과 같다는 증명이고, "셸은 block으로 시작한다"(design 위험 1)의 판정이다 |
| 21 | `printf '\033[H\033[2J\033[6 q'` | `wait_for_cursor 'vt=bar drawn=bar '` · `ink=32 box=2x16` · `inverted_now`가 0 |
| 22 | `printf '\033[H\033[2J\033[4 q'` | `vt=underline drawn=underline ` · `ink=16 box=8x2` · `inverted_now`가 0 |
| 23 | `printf '\033[H\033[2J\033[5 q'` | `vt=bar drawn=bar ` · `ink=32 box=2x16`(깜빡임 번호도 같은 띠, 결정 2) |
| 24 | `printf '\033[H\033[2J\033[0 q'` | `vt=block drawn=block ` · `ink=0 box=0x0` · `inverted_now`가 1. 모양을 기본값으로 되돌려 둔다 — 이 뒤에 검사를 더하는 사람이 bar를 물려받지 않게 |

  21~23의 `ink`·`box`는 `wait_for_cursor`가 돌아온 뒤 `last_cursor` 한 줄에서
  `grep -oE 'ink=[0-9]+ box=[0-9]+x[0-9]+'`로 뽑아 문자열로 비교한다. 실패
  메시지에 그 줄 전체를 넣는다 — 세 층 중 어느 칸이 틀렸는지가 곧 진단이다
  (design 결정 6의 고장 표).

- 마지막 `echo "TR-M2 PASS: …"` 문장 끝에 ", and the cursor takes the shape
  DECSCUSR asks for"를 붙인다.

진입 검사 셋을 게이트 전에 대 본다(lessons "게이트를 돌리고 읽는 법"의
`ENTRY-OK` 명령, `X`를 `render`로).

## Task 5: 게이트

모두 컨테이너에서 한다. 캐시를 지울 일이 있으면 컨테이너 안에서 지운다.

1. 호스트 검사(수십 초):

   ```bash
   docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
     bash -c './prepare.sh && zig build test'
   ```

   Task 2의 순서(82 · 83이 먼저 막히고, Task 1 뒤에 82~92 초록)를 따른다.
2. `render/check.sh` 한 번. 새 검사의 `cursor>` 줄은 체인이 통과하면 사라지므로
   lessons "범용 명령"의 첫 블록으로 시리얼 로그를 꺼내 와 검사 20~24 자리의
   `cursor>` · `style>` 줄을 plan의 "실측한 것"에 옮긴다.
3. regression — 하나씩, 겹치지 않게(WP-M0 실측 8): `hangul/check.sh` ·
   `copy/check.sh` · `pane/check.sh`. 셋 다 셸 커서와 copy 커서의 반전을
   센다(확정 3). 판정이 안 바뀌어야 한다.
4. 반사실 둘. 각각 저장소 파일은 안 고치고 사본을 `-v`로 덮는다(lessons
   "범용 명령"). 돌리기 전에 사본에 편집이 실제로 들어갔는지 `diff`로 본다
   (lessons 실측 52).
   - A — 띠를 안 칠한다: `main.zig` 사본에서 `renderPane`의 `fillRect` 줄을
     지운다. 호스트 검사는 `main.zig`를 안 보므로 체인이 부팅까지 간다.
     기대: 검사 21이 `vt=bar drawn=bar … ink=0 box=0x0`으로 빨갛다.
   - C — 모양을 무시한다: `vt.zig` 사본에서 `askedShape`가 언제나 `.block`을
     돌려주게 한다. 이대로면 `zig build test`(체인이 부팅 전에 돈다)의 검사 83이
     먼저 죽는다(lessons 실측 52) — 그 빨강을 먼저 한 번 보고 적는다. 그다음
     `vt_test.zig` 사본에서 검사 83~92를 지운 것을 둘째 마운트로 주고 체인을
     돌린다. 기대: 검사 21의 `wait_for_cursor`가 15초를 다 쓰고 마지막 줄이
     `vt=block drawn=block`이다.
   반사실이 예상과 다른 검사에서 죽거나 통과하면 그대로 적는다 — WP-M1처럼
   plan의 구멍이 거기서 나온다.
5. 루트 게이트 3/3. 18체인, 약 1시간 5분(WP-M2 뒤 1시간 4분 30초)이다.
   `run_in_background`로 돌리고 `{ time …; }`으로 감싼다. 완료 알림이 오면
   `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 본다.

## Task 6: 문서

- 이 plan의 `Status:`와 맨 아래 "CU-M0이 실측한 것" 절(검사 20~24의 실제
  `cursor>` 줄 · 반사실 둘의 결과 · 루트 게이트 시간).
- design의 `Status:` — "CU-M0 끝, CU-M1 남음".
- `docs/guides/lessons.md` — "로그 문구는 두 곳에 중복된다"의 목록에
  `terminal: cursor>`, "핵심 파일"의 `vt.zig` 항목에 `shell_cursor` ·
  `cursorMark()`(반전과 띠를 같은 값이 정한다), `render/check.sh`의 검사가
  모양을 바꿨다가 `\033[0 q`로 되돌린다는 것.
- `HANDOFF.md` 맨 위 절 — CU를 열었고 M0이 끝났으며 M1(`vim.basic` ·
  `/etc/vim/vimrc` · stub `defaults.vim`)이 남았다는 것.
- 기억(`docs/decisions/project_cursor_shape.md`)과 `CLAUDE.md`의 완료 표는
  서브프로젝트를 닫을 때(CU-M1) 쓴다.

## CU-M0이 실측한 것

2026-10-04, devcontainer에서 쟀다. 시간은 `{ time docker run … ; }`의 값이고,
커널이 스탬프로 빌드를 건너뛴 증분 실행이다(GL-M1).

1. Task 1 전의 `vt.zig`로 돌린 `zig build test`는 컴파일 에러 하나로 막혔다. 다만
   막힌 자리가 plan이 적은 검사 83(`cursorMark`가 없다)이 아니라 그보다 앞의 파일
   스코프 헬퍼다. 검사들이 함께 쓰는 비교 함수가 `vt.CursorMark`를 인자 타입으로
   받기 때문이다.

   ```
   src/vt_test.zig:67:44: error: root source file struct 'vt' has no member named 'CursorMark'
   ```

   Task 1을 넣은 뒤에는 `./prepare.sh`가 0으로 끝났고 `zig build test`의 다섯
   실행 파일이 전부 `PASS`, `vt_test`의 82~92가 전부 `OK`다.

2. `render/check.sh` 한 번이 1분 36초에 통과했다(반사실 뒤 다시 돌린 판은 1분
   59초). plan이 어림한 6~7분은 커널 빌드를 포함한 값이다. 검사 20~24 자리의
   실제 줄은 다음과 같다. fish의 프롬프트가 `root@(none) ~# ` 열다섯 칸이라 커서가
   `0,15`에 있다.

   ```
   검사 20  terminal: style> 0,15 fg=102030 bg=FFFFFF
            terminal: pixel> 0,15 = FFFFFF
            terminal: cursor> vt=block drawn=block row=0 col=15 cols=1 ink=0 box=0x0
   검사 21  terminal: cursor> vt=bar drawn=bar row=0 col=15 cols=1 ink=32 box=2x16
   검사 22  terminal: cursor> vt=underline drawn=underline row=0 col=15 cols=1 ink=16 box=8x2
   검사 23  terminal: cursor> vt=bar drawn=bar row=0 col=15 cols=1 ink=32 box=2x16
   검사 24  terminal: style> 0,15 fg=102030 bg=FFFFFF
            terminal: cursor> vt=block drawn=block row=0 col=15 cols=1 ink=0 box=0x0
   ```

   검사 21~23의 마지막 프레임에는 `0,15`의 `style>` 줄이 아예 없다 — 반전되지
   않은 빈 칸이라 `cells()`가 안 내보낸다. 반전 셀 수가 0으로 나오는 것이 그
   결과다. 어느 프레임에도 `more cell(s) not shown`이 없었다.

3. 명령 하나마다 커서가 세 자리를 거친다. Enter를 치면 fish가 줄을 넘겨
   `row=1 col=0`, printf가 화면을 지우면 `row=0 col=0`, fish가 프롬프트를 그리면
   `row=0 col=15`다. 가운데 프레임도 새 모양을 이미 갖고 있어서(`vt=bar drawn=bar
   row=0 col=0 … ink=32`) 모양만 기다리면 프롬프트를 그리기 전의 프레임에서 판정할
   수 있다. 그래서 검사 21~24의 기다림 패턴에 검사 20의 `row=` `col=`을 넣었다
   (아래 "plan과 다르게 한 것" 2).

4. regression 셋이 전부 통과했다. 판정은 하나도 안 바뀌었다.

   | 체인 | 시간 | 끝 줄 |
   |---|---|---|
   | `hangul` | 1분 03초 | `HI check PASS` |
   | `copy` | 2분 31초 | `CM-M2 check PASS` |
   | `pane` | 32초 | `WP-M2 check PASS` |

5. 반사실 A(띠를 안 칠한다). `main.zig` 사본에서 `fillRect` 줄을 지우고
   `_ = cursor;`를 더했다 — Zig가 안 쓰는 인자를 컴파일 에러로 막기 때문이다.
   예상대로 검사 21에서 죽었다(1분 48초).

   ```
   FAIL: after CSI 6 SP q the renderer painted ink=0 box=0x0 (want ink=32 box=2x16): terminal: cursor> vt=bar drawn=bar row=0 col=15 cols=1 ink=0 box=0x0
   ```

   `vt=` · `drawn=`은 맞고 `ink=` · `box=`만 틀렸다. design 결정 6의 고장 표에서
   "`main.zig`가 띠를 안 칠한다"의 칸이다.

6. 반사실 C(모양을 무시한다). `vt.zig` 사본의 `askedShape` 첫 줄에
   `if (true) return .block;`을 넣었다. 그 사본만 주면 체인이 부팅 전의
   `zig build test`에서 죽는다. 82는 통과하고 83이 빨갛다.

   ```
   FAIL: 검사 83 bar
     got  .{ .row = 0, .col = 1, .asked = .block, .shape = .block, .cols = 1, .px = null }
     want .{ .row = 0, .col = 1, .asked = .bar, .shape = .bar, .cols = 1, .px = .{ .x = 8, .y = 0, .w = 2, .h = 16 } }
   FAIL: terminal host tests failed (input_test or vt_test)
   ```

   검사 83~92를 지운 `vt_test.zig` 사본을 둘째 마운트로 주자 부팅까지 갔고,
   예상대로 검사 21의 기다림이 15초를 다 쓰고 죽었다(1분 45초). 검사 20(대조군)은
   통과했다.

   ```
   FAIL: after CSI 6 SP q the cursor line never said vt=bar drawn=bar at 0,15: terminal: cursor> vt=block drawn=block row=0 col=15 cols=1 ink=0 box=0x0
   ```

   두 반사실 모두 예상과 다른 검사에서 죽지 않았고, plan의 구멍은 드러나지 않았다.

7. 루트 게이트 18체인 × 3이 전부 통과했다(2026-10-04). 1시간 4분 5초, `FAIL` 0줄.
   WP-M2 뒤의 1시간 4분 30초와 같은 자리다 — `render` 체인에 검사 다섯이 늘었지만
   화면을 지우고 `printf` 한 줄씩이라 시간에 안 보인다. lead가 서브에이전트의 구현을
   대조하며 고친 것은 둘이다. `vt.zig`에서 새 함수 넷이 `defaultFg`의 doc 주석
   한가운데에 들어가 주석이 엇갈린 것을 제자리로 돌렸고, `vt_test.zig`가 HEAD에서
   지키던 `zig fmt`를 새 검사가 깨고 있어 fmt를 적용했다(`vt.zig` · `main.zig`는
   HEAD부터 fmt 차이가 있던 파일이라 통째로 fmt하지 않았다 — ZU design 실측 2).

### plan과 다르게 한 것

1. 게이트의 `last_frame`이 마지막 `screen>`부터 파일 끝까지가 아니라, 마지막
   `cursor>` 줄에서 끝난 프레임이다. 렌더 도중에 읽으면 다음 프레임의 `screen>`만
   찍히고 `style>`가 아직일 수 있고, 그러면 반전 셀이 0으로 보인다. 검사 21~23은
   0을 기대하므로 그 경우 조용히 초록이 된다. `cursor>`는 `dumpStyles` 뒤에
   찍히므로 그 줄까지 온 프레임은 `style>`가 다 찍혀 있다.
2. 검사 21~24의 기다림 패턴에 검사 20이 찾은 `row=` `col=`을 넣었다(위 실측 3).
   그리고 기다림이 맞은 뒤 로그가 1초 동안 안 자랄 때까지 기다리는 `settle`을
   한 번 더 부르고 판정한다. 검사 20도 고정 sleep 대신 `settle` 뒤에 판정하고, 화면
   줄에 `printf`가 없는 것(지운 뒤의 프레임인 것)을 먼저 본다.
3. 검사 21~24는 한 함수(`cursor_shape_check`)를 부른다. 넷이 같은 모양이라서다.
4. `cursor>` 줄에 프레임버퍼 밖이면 ` (outside the framebuffer)`를 붙인다. plan은
   "건너뛴다"였는데, 조용히 건너뛰면 그 줄이 안 나와 "로그가 안 나온다"와 안
   갈린다. 그런 배치는 `cursorMark()`가 안 만든다.
5. `vt_test`에 파일 스코프 헬퍼 넷(`cuCellAt` · `cuInverted` · `cuMarkEql` ·
   `cuExpectMark`)을 두었다. 그래서 실측 1의 컴파일 에러가 검사 83이 아니라 헬퍼
   자리에서 났다.
