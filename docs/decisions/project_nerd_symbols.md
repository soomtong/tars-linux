---
name: project_nerd_symbols
description: "NS(2026-11-08): Powerline E0B0~E0B3을 폰트 없이 sprite.zig이 8x16으로 그린다 — font.find()가 stb보다 먼저 묻는다. 나머지 Powerline · 아이콘 · 폭 규칙은 carryover. render 체인에 색 셀을 더할 때의 함정 넷(style 덤프 상한 · autosuggestion · grep -q SIGPIPE · 스크롤백)"
metadata:
  node_type: memory
  type: project
---

NS-M0(2026-11-08)이 섰다. design `docs/specs/2026-11-08-tars-nerd-symbols-design.md`, plan `docs/plans/2026-11-08-tars-nerd-symbols-ns-m0.md`.
계기는 TP-M12에서 omp가 띄운 `Tip: Please use nerdfont`이고, 조사는 carryover "Nerd Font 기호"에 있다.

## 무엇이 섰나

- `terminal/src/sprite.zig` — Powerline 넷(E0B0 · E0B1 · E0B2 · E0B3)을 comptime 상수 8x16 비트맵으로. 값은 0 · 255뿐(문턱값 렌더링,
  TR design 결정 4와 겨루지 않는다). 채운 삼각형은 픽셀 가운데 기준 행 폭 1..8,8..1(72픽셀), 선 화살표는 그 행의 가장 오른쪽 한 픽셀
  (16픽셀), 왼쪽 둘은 좌우 뒤집기.
- `font.Cache.find()`가 캐시 다음, stb보다 먼저 `sprite.lookup`을 본다 — 나중에 fallback 폰트가 들어와도 코드로 그린 것이 이긴다.
  `Glyph.bitmap`은 `?[*]const u8`, sprite는 `bitmap_bytes`에 안 센다.
- 렌더러 · vt · 폭 계약은 그대로. vt는 PUA를 1칸으로 센다(East Asian Width A) — render 검사 36이 본다.

## 다음에 더할 때

나머지 Powerline(둥근 E0B4~E0B7 · 사선 E0B8~E0BF · E0D2 · E0D4)은 `sprite.lookup`의 switch에 줄을 더하고 font_test 7절 표에 행 폭을
더하는 일이다. 아이콘은 fallback 폰트(Cozette 측정이 먼저)와 폭 규칙이 함께라 design 결정감이다 — carryover.

## render 체인에 색 셀을 더할 때의 함정 (NS-M0에서 다섯 번 빨갰다)

1. `style>` 덤프는 프레임당 96셀. fish가 따옴표 문자열을 노랗게(`F0C674`) 칠해 printf 명령 줄 셋이면 차고, 체인 끝의 음성 검사가
   이미지 구간 앞에서 잘린 덤프를 빨강으로 본다.
2. fish autosuggestion이 history의 긴 명령을 회색으로 붙여 그 셀도 덤프에 든다 — `builtin printf`처럼 history에 없는 머리로 친다.
3. `tlog | grep -q`는 pipefail 아래서 매치가 있어도 실패할 수 있다(grep이 먼저 끝나 perl이 SIGPIPE) — 결과를 변수에 담고 grep한다.
4. `\033[2J`가 지운 줄은 스크롤백에 남는다 — 앞자리에 둔 검사의 색 줄이 뒤의 shift-home 프레임에서 덤프를 넘친다. 그래서 NS 검사는
   체인 끝(이미지 구간 안)에 있다.
