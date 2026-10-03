---
name: project_terminal_graphics
description: "자식이 kitty graphics로 보낸 이미지를 우리 렌더러가 그린다(TG-M0~M3, 2026-10-03). 해석과 저장은 ghostty vt가 하고, 우리 몫은 셀 픽셀 크기 알리기 · placement를 픽셀 사각형으로 바꾸기(vt.zig) · 그리기(image.zig) · PNG 디코더(png.zig, stb_image)다. 게이트는 render 체인의 같은 부팅이 사분면 픽셀로 본다"
metadata:
  type: project
---

# 터미널 그래픽 (TG)

design은 `docs/specs/2026-10-03-tars-terminal-graphics-design.md`(결정 7 · 위험 3 ·
실측 1~8). 2026-10-03에 사용자가 후보 넷(터미널 그래픽 · USB 동글 층 B · IPv6 · 패키지
매니저) 중 이것을 골랐다. [[project_termium_survey]]가 남긴 후보다.

무엇이 섰나.

- `vt.zig` — `Screen.init`이 `CellPx`를 받아 `term.width_px` · `height_px`를 채우고
  `sys.decode_png`에 `png.decode`를 넣는다. `images(out)`이 보이는 placement를 z 순으로
  `ImagePlacement`(층 · 형식 · 바이트 · 원본 사각형 · 격자 기준 목적지)로 낸다.
- `image.zig` — 순수 모듈. 최근접 이웃 · 격자 자르기 · 알파 합성. 대상이 `anytype`이라
  `image_test`가 `u32` 배열로 같은 코드를 본다.
- `png.zig` + `stb_image_impl.c` — PNG만. 풀기 전에 머리를 읽어 RGBA 10MB를 넘으면 거절한다.
- `main.zig` — `render()`가 층 셋을 끼워 그리고 `image>` · `imgpx>` 두 겹 덤프를 찍는다.
- `render/check.sh` 검사 15~19, `vt_test` 65~77, `image_test` 1~6.

배운 것.

- 셀 픽셀 크기가 0이면 이미지가 저장만 되고 안 놓인다. 커서 이동이 전송 순간에 정해지므로
  첫 `feed` 전에 채워야 한다 — 그래서 setter가 아니라 `init`의 인자다(실측 2).
- lib 빌드의 저장 한도는 `ImageStorage`의 필드 기본값(320MB)이 아니라
  `Terminal.Options.kitty_image_storage_limit`의 10MB다(실측 1). 소스의 기본값을 읽고 짐작하면
  틀린다 — 실행해서 봤다.
- `RenderState`는 이미지를 안 담는다. 정답지는 ghostty 앱 렌더러보다 라이브러리 C API의
  `placement_render_info`가 작고 정확하다(`c/kitty_graphics.zig`). 다만 C 래퍼를 받거나
  `pub`이 아니라 Zig에서 못 불러 옮겨 적었다.
- 질의 답은 TQ의 `write_pty` 길로 저절로 나간다. 답은 id와 고정 메시지뿐이라 입력 주입
  경로가 아니다(실측 3). 게이트의 명령은 `q=2`로 답을 끈다.
- 화면 가득한 이미지는 게이트(TCG)에서 프레임을 9.6 → 69.7ms로 늘린다. 픽셀마다 나눗셈
  둘이 원인으로 보이고 안 고쳤다(실측 7, lessons의 이월 숙제).

게이트가 못 보는 것: 실기의 프레임 비용, 애니메이션 · 파일 전송 · Unicode placeholder
(비목표). `below_bg` 층과 투명 배경 규칙은 호스트 검사도 부팅 검사도 없다 — 코드만 있다.

남의 것을 쓸지 짤지는 [[project_write_or_reuse]]의 기준으로 정했다. 프로토콜 해석은 쓰고,
그리기는 짰다.
