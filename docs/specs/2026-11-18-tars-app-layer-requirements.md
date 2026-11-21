# TARS App Layer — Vision & Requirements

Date: 2026-11-18
Status: 1판. 초안 둘(2026-10-29 strip · Wayland, 2026-10-30 UI 툴킷 — 저장소 밖)을
2026-11-18의 검토로 고쳐 하나로 합쳤다. 초안 둘은 이 문서가 대체한다.
작업 순서는 `docs/plans/2026-11-18-tars-app-layer-roadmap.md`.
서브프로젝트마다의 design doc과 milestone plan은 이 문서를 근거로 따로 쓴다.

계기: 사용자(2026-10-28): "niri 스타일 strip + 1 level 위/아래 분할", "둠은
돌아가야지", "Cmd+1 = tars terminal, Cmd+2 = doom, Cmd+3 = 크로미움으로 서핑",
"계층은 workspace > column > pane". 같은 날 "크로미움 포크 브라우저와 macOS
기본 앱 수준의 번들, UI/UX는 macOS 전통". 2026-10-30: "Cocoa/Quartz 프레임워크
같은 툴킷이 필요하지", "Strata처럼 파일 관리자를 만든다". 2026-11-18(검토 뒤):
"하나의 마일스톤으로 잡기는 어렵고 커다란 비전으로 목표를 잡고 진행해보자.
주요 결정은 너의 의견에 따를 테니까."

결정의 출처: 이 문서의 "결정" 절은 사용자가 위임한 것을 Claude가 정했다.
사용자가 뒤집을 수 있고, 뒤집으면 그 결정에 날짜를 붙여 고친다.

## 비전

TARS는 콘솔이 기본인 기계다. 여기에 셸이 아닌 프로그램이 같은 화면 · 같은 키
정책 아래 사는 층을 더한다. 끝에 서는 것은 넷이다.

1. strip 워크스페이스 — 이진 분할 트리 대신 가로 strip. 깊이가 1이라 다섯 번
   갈라도 셀이 2행으로 줄지 않는다.
2. Wayland 서버 — TARS terminal이 compositor가 되어 둠 · SDL 게임 · Chromium을
   workspace · column · pane 계층 안에 띄운다.
3. TARS 툴킷 — Cocoa/Quartz를 층으로 나눈 것. 모양을 정하는 층을 TARS가
   소유해 모든 앱이 같아 보인다. 첫 앱은 column view 파일 관리자.
4. Chromium — 업스트림 빌드가 수정 없이 뜨고 한글을 치고 셸과 복사 · 붙여넣기를
   주고받는다.

~~~
workspace (Cmd+1..9)
└── column   가로 strip 위에 왼쪽→오른쪽. 폭을 가진다
    └── pane   column 안에 위→아래. 1단계뿐. 셸(PTY) 또는 app(Wayland toplevel)

AppKit 층   만든다 (Zig)   위젯 · responder chain · 메뉴 · 텍스트 편집 · 포커스
CA 층       만든다 (Zig)   레이어 트리 · 더티 영역 · 애니메이션 · 테마 토큰
CG 층       가져온다        z2d (경로 · 채우기) + 글리프 래스터(결정 4)
창 층       가져온다        zig-wayland → wl_shm
compositor  TARS terminal  evdev · Cmd 정책 · 한글 오토마타 · 클립보드 · 합성
~~~

바뀌지 않는 것: 셸까지 가는 경로(evdev → terminal → PTY)에는 Wayland가 들어가지
않는다. TARS가 피하려던 것은 Wayland가 아니라 compositor · 터미널 · 셸 · IME에
흩어진 설정이었고, TARS가 유일한 compositor인 한 Cmd 정책은 한 곳의 것이다.

## 보이는 목표 — 녹화 넷

하나의 milestone이 아니라 네 번의 녹화로 끝을 잰다. 방식은 지금 것(QEMU
`sendkey` + `screendump`).

- 녹화 A(둠): 부팅 → `Cmd+1`의 셸에서 둠 실행 → 둠이 풀스크린을 요청해 다음
  workspace를 받는다 → 화살표로 움직이고 Ctrl로 쏜다 → `Cmd+1` · `Cmd+2` 왕복.
- 녹화 B(strip + 남의 클라이언트): 셸 column 넷을 만들어 strip이 viewport를
  넘는다 → SDL3 창이 풀스크린 없이 셸 오른쪽 column으로 열린다 → 셸에서 복사한
  글을 테스트 클라이언트에 붙이고 한글을 친다.
- 녹화 C(파일 관리자): `tars-files`가 셸 오른쪽 column에 뜬다 → Miller column을
  방향키로 다닌다 → `Cmd+L`에 한글 경로(조합 중 밑줄) → `Cmd+K` 검색 →
  `Cmd+C`한 경로를 셸에 `Cmd+V` → 메뉴 바에 File · Edit · View · Go → 선택
  강조가 짧게 움직인다.
- 녹화 D(서핑): Chromium이 column으로 열린다 → `Cmd+Ctrl+F`로 자기 workspace →
  페이지를 열고 URL을 복사해 셸에 붙인다(반대도) → 주소창에 한글.

## 초안 뒤에 바뀐 사실 (2026-11-18 확인, HEAD `85a8107`)

초안은 10월 말의 저장소를 전제했다. 그 뒤 선 것 다섯이 요구사항을 바꾼다.

1. FU(2026-11-09)가 `Cmd+Ctrl+F` · `fullscreen=` · `CSI 10 ; Ps t`를 "여백과
   상태 줄을 감춘다"로 쓴다(`2026-11-09-tars-fullscreen-design.md`).
2. DY(2026-11-14)가 `tars-fullscreen <명령>`으로 DRM master를 양보한다. SDL3
   KMSDRM 프로그램은 이미 돈다. 양보 중 앱은 evdev를 직접 읽고 Cmd 정책은
   닿지 않는다. 탈출은 `Ctrl+Cmd+Backspace`.
3. HS(2026-11-05)가 `display_scale`을 세웠다. terminal은 논리 해상도의 그림자
   버퍼에 그리고 present가 정수배로 늘린다(`scale.zig`).
4. terminal의 글리프는 FreeType이 아니라 stb_truetype이고, unifont를 16px에
   안티앨리어싱 없이 굽는다(`terminal/src/font.zig`).
5. 커널에 `CONFIG_USER_NS` · `CONFIG_SECCOMP`가 켜졌다(`kernel/.config:195` ·
   `:620`). `project_termium_survey`가 적은 Chromium의 벽 가운데 커널 쪽은
   없어졌고 "어느 uid로 띄우는가"가 남았다.

그대로인 것: workspace는 아홉(`MAX_WORKSPACES`), 번호는 자리다(둘째를 닫으면
셋째가 둘째가 된다 — WP design). workspace당 pane은 여덟(`layout.MAX_LEAVES`).
main loop는 `poll` 하나다(`main.zig`). 표에 없는 Cmd 조합은 `chord`가 null을
돌려주고 원래 키가 PTY로 간다(`input.zig`).

## 결정

### 결정 1 — 풀스크린은 한 뜻이다: chrome이 꺼진 화면

chrome은 여백 · 상태 줄 · 메뉴 바 · 서버 쪽 장식이다. 셸 pane에서 `Cmd+Ctrl+F`는
FU의 지금 동작 그대로다. app pane의 풀스크린(`set_fullscreen` 요청 또는
`Cmd+Ctrl+F`)은 그 pane을 chrome이 꺼진 자기 workspace로 옮긴다 — macOS에서
풀스크린 창이 자기 Space를 받는 것과 같다. FU의 상태가 지금 화면 전체의 것인지
workspace마다의 것으로 좁힐지는 WY design이 FU 게이트를 읽고 정한다.

### 결정 2 — DY와 Wayland는 둘 다 산다

DY는 화면을 통째로 넘기는 길이다(GPU를 직접 쓰는 프로그램, 키오스크 납품, Cmd
정책 밖). Wayland는 Cmd 정책 안에서 사는 앱의 길이다. 둠의 논거는 "둠을
돌린다"가 아니라 "둠이 `Cmd+1`과 함께 산다"다. GPU 합성이 선 뒤에도 DY를 없애지
않는다.

### 결정 3 — Cmd는 표에 있는 것만 compositor가 소비한다

- 표(R-KEY-1)의 chord는 어떤 pane에도 가지 않는다.
- 표에 없는 Cmd 조합: 셸 pane에서는 삼킨다(지금은 원래 키가 간다 — `Cmd+C`가
  `c`를 치는 것을 없앤다. "Cmd는 PTY에 가지 않는다"가 문장 그대로 참이 된다).
- app pane에서는 Super modifier와 함께 그대로 보낸다. TARS 툴킷은 Cmd를 Cmd로
  받는다 — `Cmd+A`(전체 선택)와 `Ctrl+A`(줄 처음)가 구별된다.
- Super를 모르는 클라이언트(업스트림 Chromium)에는 호환 모드를 건다: 표에 없는
  Cmd 조합 전부를 `Ctrl+같은 키`로 바꿔 보낸다. 나열한 집합이 아니라 전부다.
  모드는 클라이언트마다이고, `tars_menu_v1`을 bind한 클라이언트는 원래 모드,
  아니면 호환 모드다.
- `Cmd+W` · `Cmd+T`는 셸 pane에서는 지금 뜻(pane 닫기 · 새 workspace), app
  pane에서는 앱의 것이다(위 규칙대로 Super 또는 Ctrl로 간다). app을 끝내는 키는
  `Cmd+Q` → `xdg_toplevel.close`이고 표에 넣는다. 셸 pane의 `Cmd+Q`는 삼킨다.

### 결정 4 — 글리프는 stb_truetype으로 시작하고 FreeType은 조건부다

이미 vendor에 있고 새 의존성이 없다. CG 층의 글리프 인터페이스 뒤에 두어 바꿔
끼울 수 있게 한다. TK-M0에서 배율 1의 13~14px 한글이 읽을 만한지 화면 덤프로
보고, 아니면 FreeType(힌팅)으로 바꾼다. 판정은 TK-M0 plan의 결과 절에 남긴다.

### 결정 5 — app pane은 물리 해상도로 그린다

`wl_output.scale`로 `display_scale`을 알리고, `set_buffer_scale`을 쓴
클라이언트의 버퍼는 그림자 버퍼를 거치지 않고 present 단계에서 물리
프레임버퍼에 합성한다. 배율을 안 쓰는 클라이언트(둠)는 terminal처럼 늘린다.
배율 1은 지금과 같은 길이다.

### 결정 6 — workspace 번호는 자리 그대로다

풀스크린 app은 끝에 더해진 workspace를 받는다("비어 있는 번호"는 없다). 아홉이
다 찼으면 풀스크린을 거절하고 제자리에서 column 폭만 최대로 한다. 풀스크린을
풀면 돌아갈 자리는 번호가 아니라 workspace의 정체로 기억한다. 그 workspace가
없어졌으면 포커스 workspace의 오른쪽 끝.

### 결정 7 — 한도: column당 pane 3, workspace당 pane 8

`MAX_LEAVES = 8`은 그대로 workspace의 pane 한도이고 app pane도 slot을 쓴다.
한도를 넘는 `Cmd+D` · `Cmd+Shift+D`는 아무 일도 하지 않는다. 한도를 넘는 새
toplevel은 끝에 새 workspace로 열고, 그것도 안 되면 닫는다(`xdg_toplevel.close`).

### 결정 8 — 앱은 로그인한 사용자의 uid로 돈다

Chromium을 root에 `--no-sandbox`로 띄우지 않는다. CR design의 첫 확인이 "지금
TARS의 사용자 모양에서 어느 uid로 뜨는가"이고, 모자라면 사용자 계정이 CR보다
먼저다.

### 결정 9 — 메뉴 바는 compositor가 그린다

화면 위 한 줄. 포커스 pane의 앱이 `tars_menu_v1`으로 모델을 보내고, compositor가
바와 펼친 메뉴를 둘 다 그리며, 고른 항목을 같은 프로토콜로 앱에 돌려준다. 툴킷은
`xdg_popup`을 쓰지 않는다. 키보드만으로 열 수 있어야 한다(키는 TK design).
풀스크린에서는 감춘다. 모델이 없는 앱은 이름만 보인다.

### 결정 10 — 서버와 클라이언트 둘 다 zig-wayland

같은 스캐너가 양쪽 바인딩을 만든다. Zig 0.17.1에서 빌드되는지가 WY-M0의 첫
확인이고, 안 되면 `wayland-scanner`의 C 코드를 vendor에 두고 Zig에서 부른다.
어느 쪽이든 `libwayland-server`(와 libffi)는 Debian trixie의 것을 링크한다.

### 결정 11 — 포인터는 처음부터 있다

PD가 이미 마우스와 터치패드를 다룬다. 클릭은 그 pane에 포커스를 주고, app
pane에는 `wl_pointer`의 enter · leave · motion · button · axis가 간다. 툴킷은
키보드가 먼저지만 클릭 선택과 휠 스크롤은 한다.

### 결정 12 — 이름과 자리

| 것 | 접두사 | 자리 | 게이트 체인 |
|---|---|---|---|
| strip 워크스페이스 | SW | `terminal/src/layout.zig` 등 | 지금 `pane/check.sh`를 키운다 |
| Wayland 서버 | WY | `terminal/src/` | 새 `wayland/check.sh` |
| 툴킷과 첫 앱 | TK | `toolkit/`(첫 앱은 `toolkit/src/files/` — TK design 결정 14가 고침) | 새 `toolkit/check.sh` |
| Chromium | CR | devlayer 묶음 | 새 `browser/check.sh` |

`WL`은 wifi가 쓰므로 Wayland는 `WY`다. 둠 포트는 GPL이라 TARS 저장소 밖의
별도 저장소 `tars-doom`(https://github.com/soomtong/tars-doom — `ozkl/doomgeneric`의
fork, 2026-11-18)이고 devlayer 묶음으로 얹는다. 첫 앱의 이름은
`tars-files`. 번들 앱은 목록으로 관리하고 사이트에 적는다.

### 결정 13 — 남은 값

column 폭 preset은 80셀 · 120셀 · viewport 절반 · viewport 전체. 이미지 디코더
입력 상한 16MiB · 8192px. 선택 강조 애니메이션 120ms ease-out. 비례폭 글꼴은
한글을 포함한 OFL 글꼴 하나(고르는 것은 TK-M0 plan — 크기와 라이선스를 재서).
app pane에서 `Cmd+Shift+C`(copy mode)는 아무 일도 하지 않는다.

## 요구사항

번호는 R-{영역}-{n}. 초안의 번호를 되도록 살렸고, 바뀐 것은 "(고침)", 새 것은
"(새)"로 표시한다.

### SW — strip 레이아웃

- R-SW-1 workspace의 레이아웃은 column 목록이다. column 안은 pane 목록이고 그
  아래 단계는 없다.
- R-SW-2 (고침, SW design 결정 가 · 3) column 폭의 단위는 픽셀(논리)이다. 셸
  column은 셀 폭의 배수로 맞추고 app column은 `xdg_toplevel.configure`로 준 크기를
  쓴다. SW에서는 셀 그대로 두고 픽셀은 WY-M0에서 더한다.
- R-SW-3 (고침, SW design 결정 나 · 11) 새 column은 직전 포커스 column의 폭을
  물려받는다. 단 포커스 column이 viewport 전체 폭이면 반으로 가른다(첫 `Cmd+D`는
  지금처럼 77 | 77). 물려받기는 viewport와 함께 SW-M2에서 선다.
- R-SW-4 (고침) 한도는 결정 7.
- R-SW-5 viewport는 포커스 column이 보이도록 최소한만 움직인다. 가운데 정렬은
  하지 않는다.
- R-SW-6 column은 전부 보이거나 전부 안 보인다. scroll은 column 경계에만
  맞춘다. viewport 오른쪽의 빈 공간에는 다음 column의 제목만 그린다(제목은
  SW-M3, SW design 결정 17).
- R-SW-7 pane slot 번호(0..7)는 column을 끼우고 빼도 바뀌지 않는다.
- R-SW-8 `layout.zig`는 순수 함수로 남는다. 입력 (strip, viewport 크기, scroll),
  출력 pane마다 사각형. 호스트 테스트가 먼저다.
- R-SW-9 (고침, SW design 결정 16) 상태 줄에 `3/7`(포커스 column / 전체) 칸. 화면 밖
  column이 있을 때만(column 셋 이상).
- R-SW-10 크기 바꾸기는 `Screen.resize` + `pty.resize` 그대로. 영향받는 셸
  pane의 copy mode는 닫는다.

### KEY — 키

- R-KEY-1 (고침) 아래가 compositor가 소비하는 키 전부다.

| 키 | 동작 | 비고 |
|---|---|---|
| `Cmd+1`~`9` | workspace | 그대로 |
| `Cmd+T` | 새 workspace | 셸 pane에서. app pane에서는 앱의 것 |
| `Cmd+D` | 포커스 column 오른쪽에 새 column(셸) | 뜻 변경 |
| `Cmd+Shift+D` | 포커스 pane 아래에 새 pane(셸) | 뜻 변경 |
| `Cmd+W` | 셸 pane에 SIGHUP | app pane에서는 앱의 것 |
| `Cmd+Q` | app pane: `xdg_toplevel.close` | 새 키. 셸 pane에서는 삼킨다 |
| `Cmd+[` `]` | column 순서, column 안은 위→아래 | 뜻 변경 |
| `Cmd+Opt+←` `→` | 이웃 column의 같은 높이 pane | 뜻 변경 |
| `Cmd+Opt+↑` `↓` | 같은 column 안 위 · 아래 pane | 뜻 변경 |
| `Cmd+R` | column 폭 preset 순환 | 새 키 |
| `Cmd+Ctrl+F` | 풀스크린 | FU의 키. 결정 1 |
| `Ctrl+Cmd+Backspace` | DY 탈출 | 그대로 |
| `Cmd+Shift+/` | 포커스 창의 메뉴 바 열기 | 새 키(TK design 결정 16). 모델이 없는 창 · 셸 pane에서는 삼킨다 |

  copy mode · 클립보드 · 한/영의 키는 지금 design의 것 그대로이고 이 표에 다시
  적지 않는다.
- R-KEY-2 (고침) 표의 chord는 어떤 pane에도 가지 않는다. 삼킨 누름의 뗌도
  삼킨다. Wayland의 repeat는 클라이언트가 하므로(`repeat_info`) compositor는
  repeat를 보내지 않을 뿐이다.
- R-KEY-3 Ctrl · Opt · 수식 없는 키는 app pane에 `wl_keyboard`의 키 코드와
  modifier 상태로 간다. 바이트로 번역하지 않는다. 클라이언트가 보는 Opt는 Alt.
- R-KEY-4 (고침) 표에 없는 Cmd 조합은 결정 3.
- R-KEY-5 (고침) `Cmd+W` · `Cmd+T` · `Cmd+Q`는 결정 3.
- R-KEY-6 한/영 전환 키와 `esc_latin`은 app pane에서도 같다. 상태는
  compositor의 것이고 셸 pane에는 바이트로, app pane에는 `text-input-v3`로
  나간다. 한글 모드에서 글자 키는 `wl_keyboard`로 보내지 않는다.
- R-KEY-7 (새) 포커스가 pane을 떠날 때 눌려 있던 키는 `wl_keyboard.leave`로
  정리한다. 돌아올 때 `enter`의 눌린 키 목록은 비운다.

### WIN — 창 배치

- R-WIN-1 새 toplevel은 포커스 workspace의 포커스 column 오른쪽에 새 column으로
  열린다.
- R-WIN-2 (고침) 풀스크린은 결정 1 · 6.
- R-WIN-3 (고침) 풀스크린을 풀 때 돌아갈 자리는 결정 6.
- R-WIN-4 (고침) 자리가 없을 때는 결정 6 · 7.
- R-WIN-5 toplevel이 닫혀 column이 비면 column이 사라지고 strip이 당겨진다.
  workspace가 비면 workspace도 사라진다.
- R-WIN-6 포커스는 하나다. 키보드는 포커스 pane에만 간다. 클릭은 포커스를
  옮긴다(결정 11).

### WY — Wayland 서버

- R-WY-1 서버는 TARS terminal 프로세스 안에 있다. 입력 파이프라인과 렌더 루프가
  그대로 compositor의 것이다.
- R-WY-2 (새) 셸 경로 보호. 느리거나 멈추거나 죽은 클라이언트가 main loop를
  막지 않는다 — 클라이언트 소켓은 non-blocking이고, 보낼 것이 쌓인 클라이언트는
  끊는다. 응답 없는 클라이언트는 `xdg_wm_base.ping`으로 가려 `Cmd+Q`가 SIGKILL로
  끝낼 수 있다. 클라이언트가 하나도 없을 때 terminal의 동작은 지금과 같다.
- R-WY-3 (새) 소켓은 `$XDG_RUNTIME_DIR/wayland-0`. 그 디렉터리와 권한은 로그인한
  사용자의 것이다(결정 8).
- R-WY-4 프로토콜 1단: `wl_compositor` · `wl_surface` · `wl_shm` · `wl_seat`
  (`wl_keyboard`) · `wl_output` · `xdg_wm_base` · `xdg_surface` · `xdg_toplevel`.
  둠이 뜬다.
- R-WY-5 2단: `wl_pointer` · 그 밖에 SDL3이 실제로 bind하는 것. 목록은 기억이
  아니라 실측으로 정한다 — 기존 compositor에서 `WAYLAND_DEBUG=1`로 잰다.
- R-WY-6 3단: `wl_data_device_manager`(클립보드) · `zwp_text_input_v3`(한글) ·
  `xdg-decoration` · `xdg_popup`. Chromium이 실제로 요구하는 것(`wl_subcompositor`
  · text-input의 버전 등)도 같은 방법으로 재서 CR design에 적는다.
- R-WY-7 (고침) 키맵. 서버에는 xkbcommon을 넣지 않는다. 미리 만든 키맵 텍스트를
  vendor에 두고 fd로 주며, `wl_keyboard.modifiers`의 비트는 서버가 직접 채운다.
  `keyboard=apple|pc` 교환은 그 앞에서 끝나 있다.
- R-WY-8 클립보드는 하나다. `clipboard.zig`의 내용을 `wl_data_source`로
  내보내고 클라이언트의 selection을 `clipboard.zig`로 받는다.
- R-WY-9 한글 오토마타가 app pane의 IME다. 조합 중은 `preedit_string`, 확정은
  `commit_string`. app pane 위에 조합 글자를 직접 그리지 않는다.
- R-WY-10 합성은 CPU다. `wl_surface.damage`를 받아 바뀐 영역만 blit한다.
  풀스크린 pane의 직접 scanout은 할 수 있는 드라이버에서만.
- R-WY-11 `wl_surface.frame` 콜백은 compositor의 프레임 주기에 맞춘다.
- R-WY-12 장식은 서버가 그린다. 클라이언트 쪽 장식을 고집하는 클라이언트는
  장식 없이 그린다.
- R-WY-13 (새) 배율은 결정 5.
- R-WY-14 popup은 pane 사각형 안에서 부모 기준으로 그리고, 밖으로 나가면 안으로
  민다.

### TK — 툴킷

층과 경계

- R-ARCH-1 네 층(창 · CG · CA · AppKit)은 각각 Zig 모듈이고 위 층만 아래 층을
  안다.
- R-ARCH-2 CA 층은 렌더 백엔드 인터페이스(`fill_rect` · `fill_path` ·
  `draw_glyphs` · `draw_image` · `clip` · `transform`) 위에 선다. 레이어 트리
  코드에 픽셀 포인터가 나타나지 않는다. GPU 백엔드는 같은 인터페이스 아래에
  나중에.
- R-ARCH-3 툴킷은 라이브러리다. 앱 하나가 Wayland 클라이언트 하나다.
- R-ARCH-4 호스트에서 Wayland 없이 레이어 트리 · 레이아웃 · responder · 텍스트
  편집을 검사할 수 있다(렌더 백엔드를 메모리 버퍼로).
- R-ARCH-5 (고침) terminal과 나누는 것은 코드다 — 글리프 래스터와 테마 색.
  프로세스가 다르므로 아틀라스는 각자 든다. 한글 오토마타는 나누지 않는다
  (툴킷은 `commit_string`만 받는다).
- R-ARCH-6 (새) 테마 값이 앱에 닿는 길을 TK design이 정한다(빌드 때 같은 파일 ·
  실행 때 파일 · 프로토콜 가운데).

창 · 그리기 · 텍스트

- R-TKW-1 `wl_shm` 버퍼 둘로 더블 버퍼링. `frame` 콜백에 맞춰 그리고 바뀐 것이
  없으면 commit하지 않는다.
- R-TKW-2 `configure`로 받은 크기가 루트 레이어의 크기다. 최소 크기만 알린다.
  장식은 요청하지 않는다.
- R-TKW-3 (고침) 팝업(드롭다운 · 툴팁 · 문맥 메뉴)은 자기 surface 안의
  레이어다. 메뉴 바의 메뉴는 compositor가 그린다(결정 9).
- R-TKW-4 (새) `wl_output.scale`을 받아 물리 해상도로 그리고 `set_buffer_scale`을
  쓴다.
- R-CG-1 2D 래스터는 z2d. 선 · 그림자는 그 위에 쓴다. 그림자는 둥근 사각형의
  9-slice까지.
- R-CG-2 (고침) 글리프는 결정 4.
- R-CG-3 이미지는 PNG · JPEG. 상한은 결정 13. terminal에 이미 있는 디코더
  (`png.zig` · stb_image)를 나눌 수 있는지 TK design이 본다.
- R-TXT-1 비례폭 레이아웃. 줄 나누기(공백 · 한글은 글자 단위), 가운데 생략.
- R-TXT-2 커서 위치 ↔ 픽셀 위치 양방향.
- R-TXT-3 preedit은 밑줄. commit되면 본문.
- R-TXT-4 셰이핑은 없다. `shape(run) → glyphs` 자리만 비워 둔다.

레이어 트리

- R-CA-1 유지 모드. 레이어는 위치 · 크기 · 변환 · 클립 · 불투명도 · 배경 ·
  모서리 반지름 · 자식 목록.
- R-CA-2 더티 추적. 바뀐 레이어의 이전 · 이후 사각형만 다시 그리고
  `damage_buffer`로 보낸다.
- R-CA-3 애니메이션은 속성 보간(위치 · 크기 · 불투명도 · 색).
- R-CA-4 레이아웃은 스택 · 패딩 · 정렬 · 고정/신축. 제약식 없음.
- R-CA-5 테마 토큰 한 벌(색 · 간격 · 반지름 · 글꼴 크기).
- R-CA-6 hit-test.

위젯

- R-KIT-1 (고침) responder chain. 포커스된 뷰가 키를 받고 안 받으면 부모로.
  Cmd 조합도 온다(Super — 결정 3). 표의 chord만 안 온다.
- R-KIT-2 포커스 이동은 `Tab` · `Shift+Tab`과 위젯이 정한 방향키.
- R-KIT-3 첫 앱의 위젯 여덟: 레이블 · 버튼 · 리스트 · column view · 스크롤 뷰 ·
  분할 뷰 · 텍스트 필드 · 메뉴 모델.
- R-KIT-4 리스트는 가상화. 10만 항목에서 프레임을 떨어뜨리지 않는다.
- R-KIT-5 column view는 리스트의 가로 스택.
- R-KIT-6 텍스트 필드. 한 줄 · 커서 · 선택 · 되돌리기 한 단계 · preedit ·
  `Ctrl+A`/`Ctrl+E` · `Opt+←`/`→` · `Cmd+A`(전체 선택) · `Cmd+C`/`X`/`V`.
- R-KIT-7 메뉴 모델. 항목 · 구분선 · 단축키 · 비활성. 앱은 모델만 선언한다.
- R-KIT-8 (고침) 메뉴 바는 결정 9.
- R-KIT-9 단축키의 정의는 메뉴 모델 하나다.

첫 앱 — `tars-files`

- R-FM-1 Miller column 탐색. 오른쪽 끝은 미리보기.
- R-FM-2 키는 Strata의 `docs/keyboard-navigation.md`를 따르되 Ctrl을 Cmd로
  읽는다. `Cmd+L` 경로 · `Cmd+K` 검색 · `Cmd+F` 필터 · `Space` 미리보기 ·
  `Cmd+C` 경로 복사.
- R-FM-3 디렉터리 로딩은 취소 가능하고 스트리밍이다.
- R-FM-4 검색은 이름 · 경로의 fuzzy. 상위 100개, 10초 · 20만 항목 상한.
- R-FM-5 미리보기는 텍스트(1MiB) · PNG · JPEG. 그 외는 아이콘.
- R-FM-6 선택 · 포커스 · 스크롤은 디렉터리 갱신에도 유지된다.
- R-FM-7 믿을 수 없는 파서의 격리는 원칙만 적고 구현은 뒤로.
- R-FM-8 파일 조작은 경로 복사뿐.

### CR — Chromium

- R-CR-1 업스트림 빌드가 수정 없이 뜬다. 포크는 뜬 뒤의 일이다.
- R-CR-2 설치된 디스크에서 돈다. initrd에 들어가지 않는다. QEMU 메모리 2~4GB.
- R-CR-3 GPU 없이 소프트웨어 합성으로 `wl_shm` 버퍼를 보낸다. 느려도 된다.
- R-CR-4 (고침) uid는 결정 8. sandbox를 끄지 않는다.
- R-CR-5 서핑 데모는 `net`이 켜진 `tars.conf`. 기본은 꺼짐 그대로.
- R-CR-6 서버 쪽 장식을 따르고, 테마를 받을 수 있으면 TARS 테마.

### ENV

- R-ENV-1 둠까지는 지금 QEMU 설정(simpledrm · 1GB)에서 돈다. `libwayland-server`
  와 libffi가 initrd에 드는 것은 `initrd-criteria.md`와 대조해 WY design에 적는다.
- R-ENV-2 WAD는 Freedoom. 둠 엔진(GPL)은 별도 바이너리.
- R-ENV-3 GPU 단계(dma-buf)는 이 문서 밖이지만 strip과 서버 설계가 막지 않는다.

## 비목표

- 셸 경로에 Wayland를 넣는 것.
- GTK · Qt 앱의 보장. 프로토콜상 뜰 수는 있다. 번들은 TARS가 고른다 — 기술
  장벽이 아니라 정책이므로 사이트에 정책으로 적는다.
- dma-buf · GPU 합성 · GPU 렌더 백엔드.
- Chromium 포크의 내용(브랜딩 · 기본 설정 · Super 바인딩).
- pane을 column 사이로 옮기기, column 부분 노출.
- 범용 키바인딩 엔진, CapsLock 재배치, CSI u.
- HarfBuzz · 접근성 · 제약식 레이아웃 · Odin용 C ABI.
- 파일 관리자의 Icons · List 모드, 이동 · 삭제 · 이름 바꾸기, 장치 · 휴지통.
- 설정 앱 · HIG 문서.

## 위험

1. CPU 합성의 상한. 1080p 한 장이 8MB다. damage(R-WY-10)와 더티 추적(R-CA-2)이
   없으면 Chromium과 스크롤이 프레임을 떨어뜨린다. WY-M0과 TK-M1에서 재서
   `measurements.md`에 남긴다.
2. terminal 프로세스가 커진다. 서버가 같은 프로세스라 서버의 버그가 셸을
   죽인다. R-WY-2를 게이트로 지킨다(클라이언트를 SIGSTOP · SIGKILL한 뒤 셸이
   사는가).
3. strip 전환이 지금 게이트를 건드린다. `pane/check.sh`와 FU · PD의 검사 가운데
   트리 전용을 먼저 분류한다. SW-M0은 "눈에 보이는 변화 0"이다.
4. 한/영과 키맵의 겹침. 한글 모드에서 글자 키가 `wl_keyboard`와 `text-input`
   양쪽으로 나가면 두 번 찍힌다(R-KEY-6).
5. 텍스트 편집이 툴킷에서 가장 크다. 표시 → 편집으로 갈라 plan을 짠다.
6. Chromium의 요구는 재기 전에는 모른다. text-input-v3 지원, `wl_subcompositor`,
   실행 때 의존(글꼴 · fontconfig · dbus · `/dev/shm`). 녹화 D의 한글이 여기에
   달렸다. CR design의 확인 절이 먼저다.
7. 가져오는 것의 Zig 판. z2d와 zig-wayland가 0.17.1을 따라오는지. ghostty를
   SHA로 따라가는 규칙(ZU design)을 그대로 쓴다.
8. 라이선스. z2d MPL-2.0, zig-wayland MIT, Strata 설계 참고 MIT, 둠 GPL(별도
   저장소). `THIRD_PARTY` 고지.
9. 범위. 넷 가운데 어느 하나도 작지 않다. 녹화 넷이 각각 그 자체로 끝이
   되도록 순서를 잡았다 — 어디서 멈춰도 선 것이 남는다.

## 관련

- `docs/specs/2026-10-03-tars-workspace-panes-design.md` — 지금 트리. SW가
  대체한다. 결정 1 · 3 · 4 · 5 · 6 · 7은 그대로 산다.
- `docs/specs/2026-08-15-tars-input-policy-design.md` — Cmd/Ctrl/Opt 정책.
  결정 3이 넓힌다.
- `docs/specs/2026-11-09-tars-fullscreen-design.md` — 결정 1.
- `docs/specs/2026-11-12-tars-display-yield-design.md` — 결정 2.
- `docs/specs/2026-11-04-tars-hidpi-scale-design.md` — 결정 5.
- `docs/decisions/project_hangul_input.md` · `project_escape_latin.md` ·
  `project_clipboard_scope.md` · `project_paste_ergonomics.md`.
- `docs/decisions/project_termium_survey.md` — Chromium의 벽(결정 8).
- `docs/decisions/project_motion_graphics_survey.md` — 그 조사가 추천한 "TARS
  고유 선언형 층"이 설 자리가 CA 층이다.
- lgse/strata — https://github.com/lgse/strata (MIT). 설계 참고.
- z2d — https://github.com/vancluever/z2d (MPL-2.0). zig-wayland —
  https://codeberg.org/ifreund/zig-wayland (MIT).
- 기각한 툴킷 후보: LVGL(임베디드 모양 · 텍스트) · Slint(Rust · DSL · 라이선스) ·
  GPUI(CPU 경로 없음) · dvui(즉시 모드) · EFL(크기).
- Scott Jenson, "Are we really going to use the same desktop UX forever?" —
  strip의 공간 기억 근거.
