# TARS Nerd Symbols — Design

접두사: NS

Date: 2026-11-08
Status: 초안 — NS-M0(Powerline 넷을 코드로 그린다) 설계 중.

계기: TP-M12에서 omp의 첫 화면이 `Tip: Please use nerdfont`를 띄웠다(TP-M12 plan 확인 4). 다른 세션의 조사가 carryover "Nerd Font
기호" 항목에 남았고, 사용자가 그 가운데 "Powerline을 렌더러가 직접 그리기"부터, 그것도 넷으로 좁게 시작하기로 했다(2026-11-08:
"넷으로 좁게 시작하자").

관련 문서: TR design(`2026-08-23-tars-terminal-rendering-design.md`) 결정 4(문턱값 · 알파 블렌딩 없음) · 결정 7(`style>` · `pixel>`),
FR design(폰트를 저장소 안에), `docs/decisions/project_font_selection.md`, `docs/guides/carryover.md`의 "Nerd Font 기호".

## 한 줄 요약

Powerline 기호 넷(U+E0B0 · E0B1 · E0B2 · E0B3 — 채운 삼각형 둘과 선 화살표 둘)을 폰트 없이 코드로 만든 8x16 비트맵으로 그린다.
`font.Cache.find()`가 이 넷을 받으면 stb를 부르지 않고 미리 만든 비트맵을 돌려준다. 렌더러 · vt · 폭 계약 · initrd는 그대로다.

## 확인 (2026-11-08, HEAD `d2405c6`)

1. 지금 화면의 모양. unifont 17.0.03에는 이 넷이 없다 — `stbtt_FindGlyphIndex`가 0이고, stb는 gid 0(`.notdef`)의 6x11 상자를 굽는다
   (carryover의 실측). 그래서 프롬프트의 구분 삼각형 자리마다 상자가 찍힌다.
2. 글자가 화면에 닿는 길은 하나다. 격자(`renderPane` · `renderRows`), 프롬프트(`drawPrompt` · `drawRun`), 상태 줄 모두 `cache.find(cp)`로
   `font.Glyph`를 얻고 `drawGlyph`가 `bitmap`을 문턱값(`> 127`)으로 찍는다. `drawGlyph`는 비트맵이 어디서 왔는지 모른다 — 너비 · 높이 ·
   오프셋 · 바이트만 본다.
3. 칸의 위치는 vt가 정한다(`col * CELL_W`). 폭을 글리프에서 읽는 자리도 있다 — `drawPrompt`의 `glyph.cell_width / CELL_W`, `dumpInk`의
   `cell_width <= CELL_W` 거르기. 그러니 기호의 `cell_width`가 8이어야 이 자리들이 1칸으로 본다.
4. `Glyph.bitmap`은 `?[*]u8`이고, 읽는 자리는 `drawGlyph`(`main.zig`)와 `font_test`의 null 검사 둘뿐이다. 쓰는 자리는 없다.
5. HiDPI(HS-M0)는 논리 버퍼를 통째로 정수배로 늘린다(`scale.zig`). 글자는 언제나 8x16 논리 셀에 그려지므로 기호도 8x16 하나면 된다.
6. 셀 가운데 픽셀을 되읽는 `pixel>` 줄은 render 체인(TR-M2)만 본다. 기본색이 아닌 셀마다 찍힌다.

## 결정

1. 넷만 한다: E0B0(오른쪽을 향한 채운 삼각형) · E0B1(오른쪽 선 화살표) · E0B2(왼쪽 채운 삼각형) · E0B3(왼쪽 선 화살표).
   둥근 모양(E0B4~E0B7) · 사선(E0B8~E0BF) · E0D2 · E0D4 · git branch(E0A0)는 비목표 1. 이 넷으로 비트맵을 만드는 길과 게이트의
   모양이 서면, 나머지는 표에 줄을 더하는 일이다.
2. 자리는 새 파일 `terminal/src/sprite.zig`. 시스템 콜도 로그도 없는 순수한 모듈이고(`scale.zig`과 같은 선), 코드포인트 하나를 받아
   비트맵이 있으면 돌려준다. `font.Cache.find()`가 캐시를 본 다음, stb보다 먼저 이것을 묻는다. 폰트보다 앞이라는 것이 요점이다 —
   나중에 이 코드포인트를 가진 fallback 폰트가 들어와도 코드로 그린 것이 이긴다(ghostty도 sprite를 폰트보다 먼저 본다).
3. 비트맵은 comptime에 만든 상수 배열이다(넷 × 128바이트). malloc이 없고, 풀 것도 없다. `Glyph.bitmap`의 형을 `?[*]const u8`로 바꾼다 —
   확인 4대로 읽기만 하므로 고칠 자리는 형 하나다. stb가 준 포인터는 const로 그대로 들어간다.
   `bitmap_bytes`(TR design 위험 3의 창구 — stb가 잡은 메모리)에는 더하지 않는다. 바이너리 안의 상수이기 때문이다.
4. 글리프의 값: `width` 8, `height` 16, `cell_width` 8, `x_offset` 0, `y_offset` 0. 셀을 꽉 채운다 — 옆 칸의 같은 색 배경과 틈 없이
   이어져야 Powerline이 하나의 띠로 보인다.
5. 픽셀 규칙: 값은 0 아니면 255(결정 4의 문턱값과 겨루지 않는다). 채운 삼각형은 "픽셀의 가운데가 삼각형 안"이면 255다. E0B0의
   삼각형은 꼭짓점이 (0,0) · (8,8) · (0,16)이고, 행 y에서 `x + 0.5 ≤ 8 - |y + 0.5 - 8|`인 x를 칠한다 — 행마다 위에서부터
   1 · 2 · … · 8 · 8 · … · 2 · 1, 합 72픽셀이다. 가운데 두 행(7 · 8)이 셀 폭 8을 꽉 채워 다음 칸에 붙는다.
6. 선 화살표 E0B1은 E0B0의 각 행에서 가장 오른쪽 픽셀 하나다 — 열 0 · 1 · … · 7 · 7 · … · 1 · 0, 16픽셀, 두께 1. ghostty는 이것을
   `box_thickness`의 light로 그리는데 8x16 셀에서는 1픽셀이고, 행마다 하나라 대각선이 끊기지 않는다.
7. E0B2 · E0B3은 E0B0 · E0B1의 좌우 뒤집기다(`x → 7 - x`). 코드에서도 뒤집기로 만들어, 넷의 모양이 두 정의에서 나온다.

## 판정

- `font_test`(호스트): 넷 각각 `width` 8 · `height` 16 · `cell_width` 8 · 오프셋 0, 행마다 칠한 픽셀 수(결정 5 · 6의 수열)와 합(72 · 16),
  E0B2 · E0B3이 E0B0 · E0B1을 뒤집은 것과 바이트가 같은지, 값이 0 · 255뿐인지. 두 번 찾아도 캐시가 한 번만 늘고, `bitmap_bytes`는
  늘지 않는다.
- render 체인(부팅): 색을 준 E0B0 · E0B2를 한 줄에 찍고, 그 셀의 `pixel>`(셀 가운데 (4, 8) — 결정 5대로 칠해지는 자리)이 글자색이다.
  지금은 `.notdef` 상자의 속이라 배경색이 나온다 — 고치기 전에 이 검사가 빨갛다는 것을 먼저 본다.
- 선 화살표(E0B1 · E0B3)는 셀 가운데가 비어 `pixel>`로 못 본다. 모양은 `font_test`가 바이트로 지킨다.
- verify 모드(DR)의 그림자 비교는 같은 `drawGlyph`를 타므로 따로 할 일이 없다 — 루트 게이트가 `ok`를 보면 된다.

## 비목표

1. 결정 1의 나머지 Powerline 기호. 같은 표에 줄을 더하는 다음 milestone 후보다.
2. 아이콘(Devicons · Font Awesome · Octicons · MDI) — fallback 폰트가 필요하다. carryover의 "정할 것 (2)"이고, Cozette를 재는 일은
   GitHub 릴리스가 받히는 날에 한다.
3. 폭 규칙("다음 칸이 공백이면 2칸") — 아이콘을 실을 때 정한다(carryover "정할 것 (3)"). Powerline은 1칸이 맞다.
4. 박스 드로잉 · 블록 · 점자를 코드로 그리기. unifont가 이미 픽셀 격자로 갖고 있다.

## 위험

1. 프롬프트 테마가 기대하는 모양은 셀 높이 전체의 삼각형이다. unifont의 글자와 달리 셀을 꽉 채우므로 위아래 줄의 기호가 틈 없이
   맞닿는다 — 다른 터미널도 그렇다. 거슬리는 것은 실기에서 본다.
2. 셀 크기 8x16이 바뀌면(폰트 교체 · 다른 셀 크기) 비트맵도 바뀌어야 한다. `sprite.zig`이 `main.zig`의 `CELL_W` · `ROW_HEIGHT`와 같은
   값을 쓴다는 것을 comptime 단언으로 묶는다(`pointer.zig`의 `MULTI_CLICK_PX`와 같은 방식).
3. vt가 이 넷을 1칸으로 세는지는 libghostty-vt의 폭 표에 달렸다(PUA는 1칸으로 알려져 있다). M0 plan의 착수 전 확인에서 render 체인의
   `cell` 줄로 본다.

## Milestone

- NS-M0 — 결정 일곱. lead가 직접.
