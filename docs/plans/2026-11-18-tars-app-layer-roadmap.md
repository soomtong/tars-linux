# TARS App Layer — Roadmap

Date: 2026-11-18
Status: 3판(2판: SW design 결정에 맞춰 SW 표와 WY-M0의 전제. 3판: WY design이 WY-M0을 둘로 나눠 WY 번호가 밀렸다). 근거는 `docs/specs/2026-11-18-tars-app-layer-requirements.md`.

이 문서는 순서와 끝나는 조건만 적는다. milestone의 상세는 적지 않는다 —
서브프로젝트를 시작할 때 그 design doc을 쓰고, milestone마다 plan을 쓴다
(CLAUDE.md "Milestone 단위 작업"). 앞 단계에서 잰 것이 뒤 단계의 결정을 바꾸면
이 표를 고친다.

## 원칙

1. 녹화 넷(A 둠 · B strip과 남의 클라이언트 · C 파일 관리자 · D 서핑)이 각각
   끝이다. 어디서 멈춰도 선 것이 남는다.
2. 서브프로젝트마다 design doc의 "확인" 절이 먼저다. 기억이나 초안의 전제가
   아니라 그날의 저장소와 실측으로 쓴다.
3. 루트 게이트는 milestone마다 초록이어야 한다. 구조를 바꾸는 milestone은 "눈에
   보이는 변화 0"으로 먼저 간다(SW-M0, TK-M0의 공유 모듈).
4. 셸이 먼저다. 클라이언트가 없을 때 terminal은 지금과 같다(R-WY-2).

## 순서

~~~
SW-M0 ─ SW-M1 ─ SW-M2 ─ SW-M3
   └─ WY-M0 ─ WY-M1 ─ WY-M2 ─ WY-M3 ─ WY-M4 ─ WY-M5 ─ WY-M6
               (녹화 A)                  (녹화 B는 WY-M5 뒤)
                                                              └─ TK-M0 ─ TK-M1 ─ TK-M2 ─ TK-M3 ─ TK-M4 ─ TK-M5 (녹화 C)
                                                              └─ CR-M0 ─ WY-M7 ─ CR-M1 ─ CR-M2 (녹화 D)
~~~

한 번에 한 줄씩 한다. 권장 순서는 SW-M0~M3(끝, 2026-11-19) → WY-M0 → WY-M1(녹화 A)
→ WY-M2~M5(녹화 B) → WY-M6 → TK-M0~M5(녹화 C) → CR-M0 → WY-M7 → CR-M1~M2(녹화 D). TK와 CR은 서로 독립이라
바꿔도 된다. 4판(2026-11-20, WY design 결정 44): 옛 WY-M6을 둘로 — WY-M6(호환 모드 · damage)은 TK 앞, WY-M7(popup · 장식)은
Chromium이 실제로 쓰는 것을 CR-M0이 잰 뒤.

## 1단 — SW: strip 워크스페이스

design doc: `tars-strip-workspace-design.md`(접두사 SW). 체인은 `pane/check.sh`를
키운다.

끝났다(2026-11-19). M0 `8620c93` · M1 `ea861b1` · M2 `4d491ab` · M3 `4ae701a`. 표의 M2 · M3은 design 결정 13~26으로 바뀐 뒤의 것이다.

확인 절에 넣을 것

- `pane/check.sh` · `layout_test`의 검사를 "strip에서도 뜻이 같다 / 트리 전용"
  으로 분류한 표
- FU · PD · copy mode가 `layout.Tree`의 무엇을 부르는가(`hit` · `neighbor` ·
  `separators` · `heir`)
- 상태 줄에 `3/7` 칸이 들어갈 자리(SB · LK가 쓴 칸과의 순서)

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| SW-M0 | tree → strip. 폭 · 높이를 고르게 나누고, 게이트의 세 모양(패널 하나 · `0 \| 1` · `0 \| (1 / 2)`)을 같은 숫자로 | 지금 `pane` · `pointer` · `dictation` 체인이 고치지 않고 통과, `layout_test`(고친 판) |
| SW-M1 | column당 3 한도 | 덤프의 사각형 판정, 한도에서 아무 일도 없음 |
| SW-M2 | viewport 밖 column. scroll · 물려받기 · `3/7` | column 넷 뒤 `Cmd+Opt+←`로 덤프의 원점이 바뀜 |
| SW-M3 | 폭 preset `Cmd+R`. 셸 column의 셀 배수 맞춤 · 오른쪽 빈 공간의 제목 | preset 순환의 `grid` 줄 |

요구사항: R-SW-1~10, R-KEY-1의 뜻이 바뀐 줄, 결정 7 · 13.

## 2단 — WY: Wayland 서버

design doc: `tars-wayland-server-design.md`(접두사 WY). 새 체인
`wayland/check.sh`.

확인 절에 넣을 것

- zig-wayland가 Zig 0.17.1에서 서버 · 클라이언트 바인딩을 만드는가(결정 10)
- Debian trixie의 `libwayland-server` · libffi의 크기와 NEEDED, initrd 기준과의
  대조(R-ENV-1)
- `wl_event_loop_get_fd`를 지금 `poll` 배열에 넣는 프로브 — 깨어나면
  `wl_event_loop_dispatch(loop, 0)`과 `wl_display_flush_clients`
- FU의 전체 화면 상태를 workspace마다로 좁힐 때 FU 게이트의 어느 검사가
  바뀌는가(결정 1)
- `chord`에서 표에 없는 Cmd 조합을 삼키면 `input_test`의 어느 검사가 바뀌는가
  (결정 3)
- doomgeneric과 SDL3이 bind하는 global 목록(`WAYLAND_DEBUG=1`, 컨테이너의
  headless 기준 compositor에서)
- 키맵 텍스트를 만드는 명령과 vendor에 두는 방식(R-WY-7)
- `$XDG_RUNTIME_DIR`가 지금 TARS에서 어떻게 서는가(R-WY-3)

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| WY-M0 | 서버 뼈대 · `wl_shm` · `wl_keyboard`(키맵) · `xdg_toplevel` · 풀스크린 = 자기 workspace · 셸 pane의 Cmd 삼킴 · 셸 경로 보호 · 테스트 클라이언트 | 테스트 클라이언트의 좌표 색, `Cmd+1`/`Cmd+2` 왕복, 클라이언트를 SIGSTOP · SIGKILL해도 셸이 삶 |
| WY-M1 | `tars-doom`(별도 저장소) · devlayer 묶음 | 둠 첫 맵의 좌표 색. 녹화 A |
| WY-M2 | `wl_pointer` · 클릭 포커스 · column으로 열기 · 실측한 SDL3의 요구 | SDL3 프로그램이 수정 없이 셸 오른쪽 column에 뜸 |
| WY-M3 | 배율(결정 5) | `hidpi` 체인에 app pane 검사 |
| WY-M4 | 클립보드 `wl_data_device` | 테스트 클라이언트와 셸 사이 양방향 붙여넣기 |
| WY-M5 | 한글 `text-input-v3` | 테스트 클라이언트에 조합 · 확정, 두 번 찍히지 않음. 녹화 B |
| WY-M6 | 호환 모드(Cmd → Ctrl) · 원래 모드의 문 `tars_menu_v1` 뼈대 · damage로 부분 blit | 호환 모드의 키 판정, 부분 blit 줄과 좌표 색 |
| WY-M7 | `xdg_popup` · `xdg_positioner` · 서버 쪽 장식(포커스 테두리 · 빈 칸 이름) — CR-M0의 실측 뒤 | 테스트 클라이언트의 popup 위치 · grab, 장식의 좌표 색 |

2판(2026-11-19): WY design이 1판의 WY-M0을 서버(M0)와 둠(M1)으로 나눴다. 뒤 번호가 하나씩 밀렸다.
3판(2026-11-20): WY design 결정 19가 WY-M2를 column · 포인터(M2)와 배율(M3)로 나눴다. 뒤 번호가 다시 하나씩 밀렸다.

WY-M0은 SW-M0 뒤다 — 사각형을 내는 자리(`layout.Strip`)가 먼저 서야 한다. 픽셀
크기는 WY-M0이 `Rect` 옆에 더한다(SW design 결정 3, 고침: 1판은 "픽셀 폭이 먼저
서야 한다"였다). WY-M2의 "column으로 열기"는 SW-M2 뒤다(SW는 끝났다).

요구사항: R-WY-1~14, R-KEY-2~7, R-WIN-1~6, 결정 1 · 2 · 3 · 5 · 6 · 10 · 11.

한글 입력 design doc을 WY-M5에서 다시 열어 "상태는 compositor의 것"으로 넓힌다.

## 3단 — TK: 툴킷과 `tars-files`

design doc: `tars-ui-toolkit-design.md`(접두사 TK). 새 체인 `toolkit/check.sh`.
전제는 WY-M2. 텍스트 필드(TK-M4)는 WY-M3 · M4가 있어야 한다.

확인 절에 넣을 것

- z2d가 Zig 0.17.1에서 빌드되는가, 둥근 사각형 한 장의 시간
- stb_truetype으로 구운 비례폭 한글 13~14px의 화면 덤프(결정 4의 판정)
- 한글을 포함한 OFL 비례폭 글꼴 후보의 크기와 라이선스
- terminal에서 공유 모듈로 뽑을 것(글리프 래스터 · 테마 색 · 디코더)이 지금 어느
  파일에 어떻게 박혀 있는가
- 테마 값이 앱에 닿는 길(R-ARCH-6)
- 메뉴 바가 상태 줄 · FU · 격자 크기와 어떻게 사는가(결정 9)

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| TK-M0 | 공유 모듈 뽑기(변화 0) · 창 층 · z2d · 글자 | 루트 게이트 그대로 초록. 테스트 앱이 column에 둥근 사각형과 "안녕"을 그리고 `Cmd+R`에 따라 다시 그림 |
| TK-M1 | 레이어 트리 · 더티 · 애니메이션 · 스택 레이아웃 · 토큰 | 덤프 둘의 색 차이로 불투명도 애니메이션. 더티 측정값을 `measurements.md`에 |
| TK-M2 | responder · 포커스 · 가상화 리스트 · 스크롤 | `↓` 열 번 뒤 강조 위치. 10만 행 호스트 검사 |
| TK-M3 | column view · 분할 뷰 · `tars-files` 뼈대(로딩 · 안정 선택) | `→` `→` `←` 뒤 열 셋과 포커스 |
| TK-M4 | 비례폭 텍스트 · 텍스트 필드 · text-input · 검색. 표시 → 편집 둘로 가른다 | 한글 `sendkey` → preedit 밑줄 → commit |
| TK-M5 | `tars_menu_v1` · 메뉴 바 · 단축키 · 미리보기 | 메뉴 바의 좌표 판정. 녹화 C |

요구사항: R-ARCH · R-TKW · R-CG · R-TXT · R-CA · R-KIT · R-FM, 결정 4 · 9 · 13.

## 4단 — CR: Chromium

design doc: `tars-chromium-design.md`(접두사 CR). 새 체인 `browser/check.sh`.
전제는 WY-M5.

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| CR-M0 | 재기만 한다. 어느 빌드(Debian trixie의 `chromium` 대 업스트림 스냅샷) · 실행 때 의존 · bind하는 global · text-input 버전 · uid와 sandbox | design doc의 확인 절. 모자란 것이 있으면 WY나 사용자 계정으로 되돌아간다 |
| CR-M1 | devlayer 묶음 · 첫 화면 | Chromium 첫 화면의 좌표 색 |
| CR-M2 | 클립보드 · 한글 · `net` | 녹화 D |

요구사항: R-CR-1~6, 결정 3(호환 모드) · 8.

## 그다음 (이 로드맵 밖)

dma-buf · GPU 합성 · 직접 scanout → GPU 렌더 백엔드 → Chromium 포크 → HIG
문서 → 설정 앱 → HarfBuzz → 접근성 → Odin용 C ABI → 파일 관리자의 나머지
모드와 조작. 모션 그래픽 층(`project_motion_graphics_survey`)은 CA 층이 선 뒤에
다시 연다.

## 서브프로젝트를 끝낼 때

CLAUDE.md의 "서브프로젝트를 끝내면 함께 고칠 것" 그대로다. 이 로드맵에서 더하는
것은 둘이다.

- 이 문서의 표에 끝난 날을 적는다.
- 사용자가 치는 키가 바뀌는 단계(SW-M0~M3, WY-M0, WY-M5, TK-M5)는
  `docs/help/*.md`를 함께 고친다.

## 첫걸음

SW design doc의 확인 절 — `pane/check.sh`와 `layout_test`의 검사 분류. 코드는
그 뒤다.
