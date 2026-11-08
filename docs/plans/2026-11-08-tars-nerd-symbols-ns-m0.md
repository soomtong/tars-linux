# NS-M0 — Powerline 넷을 코드로 그린다

Date: 2026-11-08
Design: `docs/specs/2026-11-08-tars-nerd-symbols-design.md`
Status: 초안

## 착수 전에 확정한 것

design의 확인 1~6에 더해, plan을 쓰며 읽은 것(HEAD `f6b1eb2`).

1. vt의 폭(design 위험 3). libghostty-vt의 `codepointWidth`(`terminal/ghostty-src/src/unicode/main.zig`)는 uucode 표의 `.width`를 그대로
   돌려주고, 2는 East Asian Wide · Fullwidth와 regional indicator뿐이다. PUA(U+E000~F8FF)는 East Asian Width가 A(모호)라 1이다. 부팅에서는
   아래 Task 2의 검사 9가 다음 글자의 열로 다시 본다.
2. `sprite.zig`은 `font.zig`가 상대 경로로 `@import`한다. 같은 디렉터리의 파일이라 `build.zig`의 모듈을 안 건드린다 — 호스트의 `font_test`도
   게스트의 terminal도 `font.zig`를 통해 함께 받는다.
3. `CELL_W` · `ROW_HEIGHT`와 묶는 자리는 `main.zig`에 이미 있다 — `std.debug.assert(pointer.MULTI_CLICK_PX == CELL_W)`. 같은 줄에
   `sprite.W` · `sprite.H`를 더한다.
4. render 체인의 색 검사(검사 1 · 2)가 쓰는 모양: `printf`로 SGR과 바이트를 만들고(`\x`는 fish · bash 빌트인 둘 다 받는다 — 검사 4의 '한'),
   `style> R,C fg= bg=`로 좌표를 얻고 `pixel> R,C = RRGGBB`(셀 가운데 (4, 8))를 대조한다. `style>`는 기본색이 아닌 셀만, 프레임마다 96셀까지
   찍는다(`STYLE_DUMP_LIMIT`).
5. UTF-8: U+E0B0 = `EE 82 B0`, U+E0B2 = `EE 82 B2`.

## Task 1 — `sprite.zig` · `font.zig` · `font_test`

더하는 것: `terminal/src/sprite.zig`.

- `pub const W = 8; pub const H = 16;`
- `pub fn lookup(cp: u32) ?[]const u8` — 넷이면 W*H바이트, 아니면 null.
- 비트맵 넷은 comptime에 만든다. `fill(row)` = design 결정 5의 행 폭, E0B0은 행 y에서 `x < fill(y)`, E0B1은 `x == fill(y) - 1`,
  E0B2 · E0B3은 `x → W - 1 - x`(결정 7). 값은 0 · 255.
- 머리 주석: 왜 폰트가 아니라 코드인가(unifont에 없음, 아웃라인 폰트는 결정 4와 겨룬다 — design), 폰트보다 먼저 묻는 이유(결정 2).

고치는 것: `terminal/src/font.zig`.

- `Glyph.bitmap`을 `?[*]const u8`로(결정 3). 필드 doc comment에 "sprite의 상수일 수 있다"를 한 줄.
- `find()`에서 캐시를 본 다음 `sprite.lookup(codepoint)`이 있으면 `width` 8 · `height` 16 · `cell_width` 8 · 오프셋 0으로 넣고 돌려준다.
  `bitmap_bytes`는 안 더한다.

고치는 것: `terminal/src/main.zig` — 확정 3의 assert 한 줄과 `sprite` import. `drawGlyph`는 바뀌지 않는다(읽기만 한다).

고치는 것: `terminal/src/font_test.zig` — 새 절 "7. Powerline 넷은 코드로 그린다".

- 넷 각각 `w`/`h`/`cell_width`/오프셋, 행마다 255의 수(채운 것 1..8,8..1 · 선은 행마다 1), 합 72 · 16.
- 선의 열: E0B1 행 y의 255가 `fill(y) - 1`에 있다 — 열 수열 0..7,7..0을 표로 적는다(코드의 식을 다시 쓰지 않는다).
- 0 · 255 말고 다른 값이 없다. E0B2[y][x] == E0B0[y][7 - x], E0B3도 같다.
- `bitmap_bytes`가 넷을 찾은 앞뒤로 같고, 다시 찾아도 `count()`가 안 는다.
- 고치기 전에 이 절이 빨간 것을 먼저 본다 — 지금은 `.notdef` 6x11이 나온다.

확인: 컨테이너에서 `cd terminal && zig build test`(`font_test`가 그 안이다 — `terminal/check.sh`가 부팅 전에 부르는 것과 같다),
그다음 `make check CHAIN=terminal`과 `make quick`.

## Task 2 — render 체인 검사 8 · 9

`render/check.sh`의 한글 검사(4~7) 뒤에 둔다 — 화면에 색 셀이 적을 때라 `style>`가 96셀 상한에 안 닿는다.

```
printf '\033[31m\xee\x82\xb0\xee\x82\xb2\033[41m \033[0m\n'
```

- 빨강 글자(palette 1 = `CC6666`)로 E0B0 · E0B2, 그 뒤 빨강 배경 공백 하나.
- 검사 8: 빨강 배경 공백의 `style> R,C … bg=CC6666`에서 좌표를 얻고, `R,C-2`와 `R,C-1`의 `pixel>`이 둘 다 `CC6666`이다 — 셀 가운데가
  칠해졌다(design 판정). 지금의 `.notdef` 상자는 속이 비어 배경(`102030`)이 나온다 — 고치기 전에 빨간 것을 먼저 본다.
- 검사 9: `R,C-2` · `R,C-1`에 `style> … fg=CC6666`이 있다 — 기호가 한 칸씩이고(확정 1) 빨강 공백이 바로 두 칸 뒤다.
- 검사 1의 `grep … bg=CC6666 | tail -n 1`이 이 줄에 끌려가지 않는지 본다 — 검사 1은 앞에서 이미 끝났으므로 순서로 갈린다.
  검사 8은 자기 printf 뒤의 로그(`tlog`의 시작 오프셋)에서만 찾는다.

확인: `make check CHAIN=render` — 고치기 전(Task 1 없이) 빨강, 고친 뒤 초록.

## Task 3 — 루트 게이트 · 닫기

- 루트 게이트(약 30분). verify 모드의 그림자 비교가 `ok`인지(design 판정).
- design `Status:` · `completed.md` · `gh-pages` `data.js` · `docs/decisions/` 기억 · `MEMORY.md` · `HANDOFF.md`. carryover "Nerd Font
  기호" 항목의 (1)에 NS-M0이 넷을 했다고 적고, 나머지 Powerline · 아이콘 · 폭 규칙은 남긴다.
- `docs/help/*.md`: 사용자가 치는 것이 안 바뀌므로 고칠 것이 없다.

## 비목표

design 비목표 1~4 그대로.

## 위험

1. render 체인의 `printf`가 fish에서 `\x`를 바이트로 안 만들면 기호가 안 찍힌다 — 검사 4가 같은 길을 이미 지나므로 낮다.
2. `?[*]const u8`로 바꾸면 stb가 준 포인터를 넣는 자리에서 형 변환이 필요할 수 있다 — `[*c]u8` → `[*]const u8`은 암시적으로 되는지 컴파일로
   본다.

## 결과

### Task 1

- Red 먼저: 7절만 넣고 `zig build test` — `FAIL: U+E0B0 6x11 cell_width=8 x_offset=1 y_offset=3`(`.notdef`). 1~6절은 그대로 초록.
- `sprite.zig`의 첫 컴파일이 `[_]u8{0} ** (W * H)`에서 막혔다 — 0.17은 `**`를 안 받는다(`binary operator '*' has whitespace on one side`).
  `@splat(0)`로. 사용자 지시로 기억(`project_zig_upgrade.md`)의 대체 표에 더했다.
- `main.zig` 머리의 `const sprite = @import(...)`는 포인터 화살표의 매개변수 `sprite: *pointer.Sprite` 둘과 이름이 부딪혀(shadow) 게스트 빌드가
  막혔다 — 호스트 `zig build test`는 `main.zig`를 안 컴파일해 못 봤다. 단언 안에서 `glyph_sprite`로 import한다.
- 위험 2(`[*c]u8` → `?[*]const u8`)는 암시적으로 됐다 — 형 변환 줄 없음.
- 초록: `font_test: Powerline E0B0~E0B3이 8x16 코드 비트맵이다 (잉크 72 · 16 · 72 · 16) OK`, `make check CHAIN=terminal` PASS(3분 2초).

### Task 2

plan과 달라진 것: 검사 번호는 36 · 37(체인에 35까지 있었다), 자리는 한글 검사 뒤가 아니라 체인 끝(검사 32 뒤, 음성 검사 앞), 지우기 명령을
따로 먼저 친다, 둘 다 `builtin printf`다. 확정 4의 "style>가 96셀 상한에 안 닿는다"가 틀렸다 — 셸(fish)이 따옴표 문자열을 노랗게
(`F0C674`) 칠하고 그 셀이 상한을 먹는다. 실행마다 배운 것:

1. 한글 검사 뒤, 지우기 없음 — 앞 printf 줄 셋의 노란 셀에 밀려 기호 줄이 덤프에 안 나왔다(`34 more cell(s) not shown`). 검사 36이 3행(한글
   줄)의 빨강 공백을 잡고 빨갰다.
2. 같은 줄 맨 앞에 `\033[H\033[2J` — 기호 줄은 0행에 섰고 red(sprite 없이)는 기대대로 검사 37이 `pixel> 0,0 = 102030`. 그런데 sprite를 넣은
   초록 판에서 음성 검사 "the style dump hit its limit"(이미지 구간 앞만 본다)이 빨갰다 — 긴 printf를 치는 동안의 프레임이다(지우기는 Enter 뒤).
3. 짧은 지우기 줄을 먼저 — 그 줄을 치는 동안 fish autosuggestion이 history의 긴 한글 printf를 회색으로 붙여 `12 more cell(s)`. `builtin`을
   앞에 붙였다(`b`로 시작하는 history가 없다).
4. 검사 36이 줄이 있는데도 빨갰다 — `pl_tlog | grep -q`에서 grep이 먼저 끝나 perl이 SIGPIPE로 죽고 pipefail이 실패로 셌다. `tlog` 결과를
   변수에 한 번 담는다.
5. 덤프 상한이 검사 12(shift-home)의 프레임에서 다시 넘쳤다 — `2J`가 지운 줄은 스크롤백에 남고, 맨 위가 노란 명령 줄 다섯이 됐다. 블록을
   체인 끝으로 옮겼다 — 이미지 구간 안이라 음성 검사가 안 보고, 뒤에 스크롤백을 보는 검사가 없다.

- Red(Task 1 코드를 stash로 뺀 판, 2번 모양): 검사 36 초록(`style> 0,2 … bg=CC6666`, 기호 둘이 0 · 1열) — 확정 1대로 1칸. 검사 37 빨강
  `pixel> 0,0 = 102030`.
- 초록(최종 모양): `red space after the symbols: terminal: style> 1,2 fg=CC6666 bg=CC6666`, `pixel> 1,0 = CC6666` · `pixel> 1,1 = CC6666`,
  체인 PASS. `make quick` PASS.
