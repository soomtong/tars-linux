---
name: project_app_layer_vision
description: strip 워크스페이스 · Wayland 서버 · TARS 툴킷(첫 앱 tars-files) · Chromium을 한 milestone이 아니라 비전으로 잡았다(2026-11-18). 요구사항과 로드맵만 섰고 코드는 0줄. 주요 결정 열셋은 사용자가 Claude에게 위임했다. 접두사 SW · WY · TK · CR(WL은 wifi의 것), 끝은 녹화 넷
metadata:
  type: project
---

계기: 사용자가 10월 말에 쓴 요구사항 초안 둘(strip · Wayland 앱 층, UI 툴킷 — 저장소 밖)을 2026-11-18에 검토하게 했고, 검토 뒤
"하나의 마일스톤으로 잡기는 어렵고 커다란 비전으로 목표를 잡고 진행해보자. 주요 결정은 너의 의견에 따를 테니까 새로운 요구사항
문서를 작성하고 작업 계획을 수립해보자"고 했다.

문서: 요구사항 `docs/specs/2026-11-18-tars-app-layer-requirements.md`, 순서 `docs/plans/2026-11-18-tars-app-layer-roadmap.md`.
초안 둘은 이 둘이 대체한다.

## 위임

요구사항 문서의 "결정" 절 열셋은 Claude가 정했다. 사용자가 뒤집을 수 있다 — 뒤집으면 그 결정에 날짜를 붙여 고친다. 서브프로젝트의
design doc에서 새로 생기는 결정도 같은 위임 아래 추천안으로 가되, 사용자가 치는 키가 바뀌는 것은 보고에 따로 적는다(Claude의 해석).

## 초안이 틀렸던 자리 — 다시 틀리지 않게

초안은 10월 말의 저장소를 전제했고 3주 사이에 다섯이 바뀌었다. 요구사항을 쓸 때 저장소와 대조하지 않으면 같은 일이 난다.

- `Cmd+Ctrl+F`는 FU의 키다(새 키가 아니다)
- DY로 SDL3 KMSDRM 프로그램은 이미 돈다 — 둠의 논거는 "Cmd 정책 아래에서 산다"다
- terminal의 글리프는 FreeType이 아니라 stb_truetype + unifont 16px(안티앨리어싱 없음)
- HS의 `display_scale` — app pane이 그림자 버퍼를 거치면 뭉개진다
- 접두사 `WL`은 wifi 체인의 것

## 결정 가운데 초안과 다른 것

- 표에 없는 Cmd 조합: 셸 pane은 삼키고, app pane은 Super로 보낸다. `Ctrl` 변환은 `tars_menu_v1`을 bind하지 않은 클라이언트에만
  거는 호환 모드다. 초안의 "정해진 집합을 Ctrl로"는 툴킷 텍스트 필드의 `Ctrl+A`(줄 처음)와 `Cmd+A`(전체 선택)를 구별 못 하게 한다
- 메뉴 바와 펼친 메뉴를 둘 다 compositor가 그린다. 프로토콜은 양방향
- 풀스크린은 한 뜻(chrome이 꺼진 화면)이고 app pane만 자기 workspace로 옮겨 간다

## 다음

SW design doc의 확인 절(`pane/check.sh` · `layout_test` 검사의 분류)부터. Chromium과 SDL3이 요구하는 프로토콜은 기억으로 쓰지 않고
`WAYLAND_DEBUG=1`로 잰다.

관련: [[project_termium_survey]] · [[project_motion_graphics_survey]] · [[project_hangul_input]] · [[project_clipboard_scope]]
