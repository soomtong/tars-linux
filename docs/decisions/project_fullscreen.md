---
name: project_fullscreen
description: "전체 화면(FU-M0~M1, 2026-11-09): 여백과 상태 줄을 없앤다. Cmd+Ctrl+F · tars.conf fullscreen= · 패널의 CSI 10;Ps t. 납품 조각은 sh -c + trap : INT로 감싼다"
metadata:
  type: project
---

# Fullscreen (FU)

사용자(2026-11-09, BB 데모를 맥북 에어 실기에서 본 뒤): "Full screen mode 필요하겠다". design `docs/specs/2026-11-09-tars-fullscreen-design.md`,
plan `docs/plans/2026-11-09-tars-fullscreen-fu-m0.md` · `-fu-m1.md`.

- 격자 원점은 파일 수준 `grid_origin`(상수 `GRID_X` · `GRID_Y`는 없다), 자리 셈은 `terminal/src/geometry.zig`. 켜고 끄기는 `setFullscreen` 하나로 모인다.
- 패널 출력의 `CSI 10;Ps t`는 `terminal/src/winops.zig`가 lib-vt 앞에서 훑는다(lib-vt는 10을 버린다). `readPanes`는 요청을 접어 두고 루프 뒤에 한 번 적용한다.
- 납품 프로그램을 전체 화면으로 감싸는 조각은 `sh -c 'trap : INT; printf "\033[10;1t"; <prog>; printf "\033[10;0t\033[H\033[2J\033[3J"'` 모양이다.
  그냥 세 줄로 쓰면 Ctrl+C(SIGINT)로 죽은 전경 job 뒤의 명령을 대화형 셸이 취소해 화면이 전체 화면에 갇힌다. 끝의 지우기는 열 수가 줄 때 다시
  접힌 잔상을 치운다(FU-M1 plan 결과 1 · 2).
- 단축키로 바꾼 상태는 `tars.conf`에 쓰지 않는다. 전체 화면에서는 상태를 띄우는 토스트가 없다(design 비목표).

관련: [[project_minimal_iso]] · [[project_hidpi_scale]]
