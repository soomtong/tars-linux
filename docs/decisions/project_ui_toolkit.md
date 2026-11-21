---
name: project_ui_toolkit
description: TARS UI 툴킷(TK-M0~M6, 2026-11-20~22, 브랜치 app-layer-0-3)이 끝났다 — `toolkit/`의 라이브러리 `tk`와 첫 앱 `tars-files`, 서버 쪽 메뉴 바. 다시 겪지 않을 함정 여섯과 남긴 것
metadata:
  type: project
---

App Layer(0.3)의 3단. design `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 1~17), plan `docs/plans/2026-11-20…22-tars-ui-toolkit-tk-m0..m6.md`.
결정은 위임받아 Claude가 정했다([[project_app_layer_vision]]). 구현은 milestone마다 새 Herdr 서브에이전트(Opus), lead는 plan · 대조 · 게이트 · commit
([[feedback_herdr_subagents]]).

무엇이 섰나: `toolkit/`(별도 build, `terminal/prepare.sh`가 부른다) — 창 층 → CG → CA → kit 네 층이 각각 build 모듈이고 층 밖 순수 값 모듈
(`geom` · `input` · `menu` · `tokens`)이 있다. 첫 앱 `tars-files`(`toolkit/src/files/`). 서버 쪽은 `tars_menu_v1` 판 2와 위 여백 20 px 안의 메뉴 바
(`terminal/src/menubar.zig`). 체인 `toolkit` 판정 1~34, wayland 31~36, hidpi 7b2.

다시 겪지 않을 것:

- 층 경계는 build 모듈로 드러낸다 — 위 층 파일을 경로로 import하면 같은 파일이 두 모듈에 들어 컴파일이 막는다. 순수한 부분(`age` · `repeat` · `ime` · `clip` ·
  `model` · `search` · `menu`)은 시각 · 소스를 인자로 받게 해 호스트 검사가 Wayland 없이 돈다.
- 서버가 화면에 그리는 것을 더하면 verify의 그림자 프레임도 같은 함수로 같은 순서에 그려야 한다 — 실제 화면에만 그리면 모든 체인이 빨개진다. 메뉴 바는
  `renderBarBand` 하나를 둘이 지나고, 드롭다운은 그림자가 app slot을 복사한 뒤에 그린다. bs 2 창 위는 `presentComposed`가 다시 늘려야 한다.
- 열린 메뉴는 앱이 모델을 다시 commit하면 닫힌다 — 그래서 비활성 비트는 입력 이벤트 뒤에만 다시 셈하고 ime · idle에서는 안 셈한다(서버가 메뉴를 열며 조합을
  확정해 보내는 `ime` 하나가 막 연 메뉴를 닫았다).
- 영문 글자는 text-input을 켠 창에서도 `wl_keyboard`로 온다(한글만 `commit_string`) — 글자 키 표가 꼭 필요하고 서버 키맵 파일과 호스트 검사로 대조한다.
- idle 조각의 순서가 판정을 바꾼다 — 미리보기를 디렉터리 조각보다 먼저 돌리자 1만 항목 스트리밍 판정이 깨졌다(0행이 바뀔 때마다 읽기가 끼었다).
- 체인 판정이 첫 판에 빨개진 넷 가운데 셋은 판정 스크립트의 셈 실수였다(한글을 켜기 전의 키까지 셈, 앞 판정의 줄까지 셈, 오프셋 72의 `first`) — 줄 수를
  셀 때는 "언제부터"와 패턴을 기다림과 같은 글로 맞춘다. 파이프 끝 `grep -q`는 루트 게이트 입구 검사가 잡는다.

남긴 것: 녹화 C(사람 녹화 — 녹화 A · B와 함께), 레이블 · 버튼 · 스크롤 뷰 위젯, 앱 안 팝업 레이어, 격리 구현(R-FM-7 — 원칙만), TCG에서 스크롤 한 프레임이
16 ms를 넘는 것(네이티브 0.45 ms). 전부 `docs/guides/carryover.md`의 TK 절 여섯에 있다. 실측은 `measurements.md` 108~114.

곁에서 고친 것: install 체인 부팅 7의 `usb-storage.delay_use` 4 → 5(2026-11-22, initrd가 128 MB로 커지며 여유가 얇아져 게이트 부하에 창이 닫혔다 — 약 145 MB에서
다시 본다).

관련: [[project_strip_workspace]] · [[project_branch_lines]]
