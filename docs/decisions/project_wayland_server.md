---
name: project_wayland_server
description: TARS Wayland 서버(WY-M0~M7, 2026-11-19~22, 브랜치 app-layer-0-3)가 끝났다 — terminal 안의 서버에 둠 · SDL3 · tars-files · Chromium이 수정 없이 뜬다. 다시 겪지 않을 함정 일곱과 남긴 것
metadata:
  type: project
---

App Layer(0.3)의 2단. design `docs/specs/2026-11-19-tars-wayland-server-design.md`(결정 1~55), plan `docs/plans/2026-11-19…22-tars-wayland-server-wy-m0..m7.md`.
결정은 위임받아 Claude가 정했다([[project_app_layer_vision]]). 구현은 milestone마다 Herdr 서브에이전트(Opus), lead는 plan · 대조 · 게이트 · commit
([[feedback_herdr_subagents]]).

무엇이 섰나: `terminal/src/wl/server.zig`(libwayland를 terminal의 poll 바퀴에 한 칸으로)와 순수 모듈 `wl_logic.zig`(호스트 검사). 창은 셸 오른쪽 column이나
자기 workspace(첫 commit 전의 `set_fullscreen`)에 뜬다. 키(evdev 코드 + R-KEY-1 표) · 포인터((창, surface) 단위) · 배율(물리 1:1) · 클립보드 양방향 ·
한글 text-input-v3 · 호환 모드(Cmd → Ctrl) · damage 부분 blit · subsurface · window geometry · popup(column 밖 합성). 체인 `wayland` 판정 1~44, hidpi 6~10,
browser 3a · 3b. 테스트 클라이언트 `tars-wl-test`(옵션마다 장면 하나).

다시 겪지 않을 것:

- 셸이 `WAYLAND_DISPLAY`를 물려주면 SDL3 KMSDRM 데모까지 우리 서버에 붙는다(DY 12a 빨강) — `tars-fullscreen`은 exec 전에 `WAYLAND_DISPLAY` · `XDG_RUNTIME_DIR`
  둘 다 뺀다(하나만 빼면 libwayland가 기본 `wayland-0`을 찾는다, 결정 18).
- 서버가 화면에 그리는 것은 verify 그림자가 흉내 내지 않는다 — app slot · popup이 덮은 자리는 실제 fb에서 그림자로 복사해 비교에서 뺀다. 셸 pane을 덮었다
  비키는 것(popup)은 밑을 따로 들지 않고 그 동안 프레임을 통째로 한다(부분 프레임은 다시 칠하지 않은 clip에서 반투명이 두 번 섞인다).
- 클라이언트가 끝날 때 자원이 사라지는 순서를 믿지 않는다 — surface가 창보다 먼저 사라져 `gone` 줄 · text-input의 창을 못 찾았다. 약한 참조(`top` · `to`)를
  객체에 담고 사라지는 쪽이 null로 만든다.
- 클립보드 파이프: 읽기 끝만 비블록(`pipe2`의 O_NONBLOCK은 클라이언트의 쓰기 끝까지 비블록으로 만든다), terminal은 SIGPIPE를 무시하되 셸 자식에게는 되돌린다.
- libwayland는 판(version)을 안 막는다 — 판 6에만 있는 이벤트(`preferred_buffer_scale`)는 bind한 판을 보고 보낸다. Chromium은 `wl_compositor` 4라 `wl_output.scale`로 안다.
- 진짜 클라이언트의 요구는 재기 전에는 모른다: SDL3은 software여도 EGL 창을 바란다, Chromium은 `wl_subcompositor`가 없으면 주소창 한 글자에 죽는다,
  Chromium은 `set_opaque_region(nil)`을 보낸다(불투명 영역 최적화를 못 쓴다 — 대신 1:1 섞기 길). milestone 앞에 조사 에이전트가 시제품으로 재고 plan의 확인 절에 적는다.
- 체인 판정의 첫 판 빨강은 거의 판정 쪽이었다 — 한글이 켜진 채 친 명령, 화살표가 걸린 상자, 비동기 포커스를 안 기다린 키. 판정 앞에서 한글을 끄고,
  상자는 화살표(12 × 19)를 피하고, 클라이언트의 상태 줄(`ti enable`)을 기다린 뒤 친다.

남긴 것: 녹화 A · B(사람), 서버 쪽 장식(포커스 테두리), popup 동안의 통째 프레임 · 배율 2에서 셸 위 popup의 흐림, popup 키보드 포커스, 커서 surface 합성,
매핑 뒤 `set_fullscreen`(F11)과 앱의 `Cmd+Ctrl+F`(요구사항 결정 1 · 6 — CR-M2가 한다). 전부 `docs/guides/carryover.md`의 WY 절 둘에 있다. 실측은 `measurements.md` 107 · 116 · 117.
