# TARS Wayland Server — Design

접두사: WY

Date: 2026-11-19
Status: 확인 · 결정 · milestone까지 썼다(2026-11-19). 사용자 위임으로 Claude가 정했다. 다음은 WY-M0 plan.
브랜치 `app-layer-0-3`.

계기: App Layer의 2단(`docs/plans/2026-11-18-tars-app-layer-roadmap.md`). 사용자(2026-11-18):
"Cmd+1 = tars terminal, Cmd+2 = doom, Cmd+3 = 크로미움으로 서핑". 요구사항
`2026-11-18-tars-app-layer-requirements.md`의 R-WY-1~14 · R-KEY-2~7 · R-WIN-1~6 · 결정 1 · 2 · 3 · 5 · 6 · 10 · 11.

관련 문서: SW design(`2026-11-18-tars-strip-workspace-design.md` — app pane이 설 column과 viewport, 결정 3:
픽셀은 여기서 `Rect` 옆에 더한다) · FU design(전체 화면) · DY design(화면을 통째로 넘기는 길, 결정 2로 함께 산다) ·
PD design(포인터) · IS · HS design(배율).

## 한 줄 요약

terminal 프로세스 안에 libwayland-server를 띄우고, 그 이벤트 루프의 fd 하나를 지금 `poll` 배열에 더한다.
클라이언트의 toplevel은 strip의 column 하나(app pane)가 되고, 키 · 포인터는 지금 입력 파이프라인이 그 pane으로
보낸다. 셸 경로는 클라이언트가 없을 때 지금과 한 바이트도 다르지 않다.

## 확인 (2026-11-19, HEAD `f7c96bf`)

1 · 2 · 3은 서브에이전트(`wy-research`, Opus)가 버리는 dev 컨테이너에서 쟀다(scratch: 세션 scratchpad의
`wy-research/`). lead가 로그와 숫자를 읽었다. 4~7은 lead가 저장소를 읽었다.

### 1. zig-wayland는 Zig 0.17.1에서 그대로 선다(결정 10)

- `codeberg.org/ifreund/zig-wayland` 태그 v0.7.0(`fc7672f`, 2026-10-06)이 Zig 0.17 대응 뒤의 첫 태그다. v0.6.0은
  0.16용. `minimum_zig_version`은 둘 다 "0.16.0"이라 그 줄로는 못 가른다.
- 스캐너 한 번이 `client`와 `server` 두 네임스페이스를 함께 만든다. global마다 최대 버전을 적어야
  (`scanner.generate("wl_seat", 5)`) 그 인터페이스가 생성된다. xml은 경로를 직접 줄 수 있어(`Scanner.Options.
  wayland_xml` · `.wayland_protocols`) vendor한 xml로 pkg-config 없이 된다.
- 프로브: 서버(`addSocket("wayland-0")` · global 둘 · 이벤트 루프 fd를 `poll`에 넣고 깨면 `dispatch(0)` +
  `flushClients()`)와 클라이언트(registry · bind · roundtrip)가 zig-wayland 코드를 한 줄도 안 고치고 빌드 · 실행됐다.
  로드맵이 적은 poll 배열의 모양이 그대로 돈다. ReleaseSmall 약 131KB(arm64), 첫 빌드 약 50초.
- x86_64 cross 링크는 무버전 `libwayland-server.so`가 없어 실패한다(`libwayland-dev:amd64`에 있다). symlink 하나와
  `--search-prefix`로 통과했다(NEEDED `libwayland-server.so.0` · `libc.so.6`). 게스트에서 실행은 아직 안 했다.
- `Server.addSocketAuto`는 일부러 `wayland-0`을 건너뛴다. R-WY-3은 `wayland-0`이므로 `addSocket("wayland-0")`을 직접
  부른다. `WAYLAND_DISPLAY`가 없는 클라이언트도 `wayland-0`에 붙는다(실측).

### 2. libwayland는 작고 사슬을 안 끈다(R-ENV-1)

| 패키지(trixie, amd64) | 판 | .so 크기 | NEEDED |
|---|---|---|---|
| libwayland-server0 | 1.23.1-3 | 93,800 B | `libffi.so.8` · `libc.so.6` |
| libwayland-client0 | 1.23.1-3 | 77,192 B | `libffi.so.8` · `libc.so.6` |
| libffi8 | 3.4.8-2 | 47,576 B | `libc.so.6` |

libffi는 이미 initrd에 있다(Dockerfile 490행, curl · gnutls 사슬). 새로 드는 것은 `libwayland-server.so.0` 하나다.
서버가 terminal 안에 있으므로(R-WY-1) 그것은 terminal의 NEEDED가 되고, `make_initrd.sh`의 `copy_lib_deps`가 따라
싣는다 — 기준 A("TARS가 부른다")다. Dockerfile에 `libwayland-server0:amd64`를 더하면 된다. 클라이언트 라이브러리는
클라이언트(둠 · SDL3 · 테스트 클라이언트)가 사는 층을 따라간다.

### 3. 키맵은 텍스트 하나로 된다(R-WY-7)

- `xkbcli compile-keymap --rules evdev --model pc105 --layout us`(libxkbcommon-tools 1.7.0, xkb-data 2.42) → 64,754 B,
  키 419개. 인자 없는 기본값과 같고 `--model macintosh`와도 같다 — `keyboard=apple|pc` 교환은 서버 앞에서 끝난다.
- 클라이언트가 하는 대로(`xkb_keymap_new_from_string`, TEXT_V1) 읽어 성공했다. 흠 하나: 1.7.0이 26자를 넘는 keysym
  이름 둘(`XF86KbdInputAssistPrevgroup` · `…Nextgroup`)을 잘라 쓴다 — 그 두 키만 `NoSymbol`이 된다. 타자와 무관하다.
- modifier 비트(`wl_keyboard.modifiers`): Shift 0x1 · Lock 0x2 · Control 0x4 · Mod1(Alt) 0x8 · Mod2(NumLock) 0x10 ·
  Mod4(Super = Cmd) 0x40. group 0.
- 서버가 하는 일: `memfd_create` + 봉인(`F_SEAL_SHRINK | GROW | WRITE`)으로 한 fd를 여러 클라이언트에 준다(v7부터
  클라이언트는 `MAP_PRIVATE`). size는 NUL을 포함한다(weston · wlroots 관행, 64,755). 키는 evdev 코드 그대로(클라이언트가
  +8). `repeat_info`도 서버가 보낸다.

### 4. poll 배열에 칸 하나

`main.zig`의 `fds`는 uevent · 키보드 · 포인터 · PTY 구간 뒤에 고정 오프셋 꼬리가 있다(`pty_end + 0..4`: 받아쓰기
out · err, 양보 listen · guest, 링크 이벤트). LK가 링크 칸을 더한 것과 같은 모양으로 `pty_end + 5`가 Wayland 이벤트
루프의 fd다. 확인 1의 프로브가 이 모양(깨면 `dispatch(0)` + `flushClients()`)을 이미 돌렸다.

### 5. FU의 전체 화면은 App 하나의 것이고, FU 게이트는 workspace를 안 쓴다(결정 1)

`App.fullscreen: bool` 하나다(`setFullscreen`). `fullscreen/check.sh`(324줄)의 판정 여덟은 전부 workspace 하나에서
돈다 — `Cmd+T` · `Cmd+숫자`가 없다. 전체 화면을 workspace마다로 좁혀도 그 여덟은 그대로다. 바뀌는 것은 "workspace를
옮기면 chrome이 따라 바뀐다"는 새 동작뿐이고, 그것을 보는 검사는 아직 없다.

### 6. 표에 없는 Cmd 조합을 삼키면 바뀌는 `input_test`(결정 3)

`chord`는 표에 없는 조합에 null을 돌려주고 키는 modifier 없이 흘러간다(`input.zig:1281`의 주석). 그것을 단언하는
자리가 `input_test`에 있다 — `Cmd+Delete` → 맨 Delete(622행), `Cmd+C` → `c`(626행), "Cmd+Shift · Cmd+Option의 표에
없는 조합은 null"(748행 부근). `Cmd+Ctrl+←` → 0x01(2560행 부근)은 Cmd 표에 있는 키라 그대로다. 삼키기는 이 단언들을
"아무것도 안 나간다"로 바꾼다. 게이트 체인은 안 바뀐다 — 체인이 치는 Cmd 조합 열아홉 가지(`rg -o 'meta_l-…'
--glob '*/check.sh'`)는 전부 표에 있다(`Cmd+V` · `Cmd+←` · `Cmd+Backspace`는 바이트 표, `Cmd+5`는 없는 workspace 번호).

### 7. `$XDG_RUNTIME_DIR`은 지금 없다(R-WY-3)

저장소 어디에도 이 이름이 없다. terminal은 root로 돌고 셸만 자식에서 계정의 uid로 내려간다(`pty.zig:52-53`).
`/run/tars` 아래 소켓들도 root의 것이다. 그래서 terminal(root)이 `/run/user/<uid>`(0700, 그 사용자의 것)를 만들고
그 안에 `wayland-0`을 열고, 셸의 환경에 `XDG_RUNTIME_DIR` · `WAYLAND_DISPLAY=wayland-0`을 넣는 모양이 된다. 소켓의
주인도 그 사용자여야 셸에서 띄운 클라이언트가 붙는다.

### 8. 둠과 SDL3이 bind하는 global

- 둠: `doomgeneric`(`../tars-doom`)의 백엔드는 SDL2 · X11 · linuxvt · Windows 등이고 Wayland가 없다. WY-M0에서
  `doomgeneric_wayland.c`를 쓰면 bind는 우리가 정한다 — `wl_compositor` · `wl_shm` · `wl_seat`(`wl_keyboard`) ·
  `xdg_wm_base`. 잴 것이 없다.
- SDL3(trixie `libsdl3-0` 3.2.10, gpu 묶음과 같은 판): 기준 compositor 둘(weston 14 headless pixman, sway 1.10
  headless pixman)에서 `WAYLAND_DEBUG=1`로 쟀다. 작은 SDL 창(software renderer · window surface)과 저장소의
  `tars-gpu-demo`(고치지 않고) 모두 exit 0.
  - bind(상한은 SDL 소스): `wl_compositor` ≤6 · `wl_shm` 1 · `xdg_wm_base` ≤6 · `wl_output` ≤4 · `wl_seat` ≤9 ·
    `wl_data_device_manager` ≤3 · `wp_viewporter` · `zxdg_output_manager_v1`, 있으면 `zxdg_decoration_manager_v1` ·
    `wp_fractional_scale` · `zwp_text_input_manager_v3` · `wp_cursor_shape` · `xdg_activation` 등. `wl_subcompositor`는
    bind하지 않는다.
  - 없어도 뜬다: `wl_seat`(키를 못 받을 뿐), 장식 관리자(libdecor로 가고, 플러그인이 없으면 장식 없이), 나머지 확장 전부.
  - "software"도 EGL을 탄다. SDL 3.2.10의 Wayland 백엔드에는 framebuffer 경로가 없어 텍스처를 GPU renderer(opengles2)로
    올리고, 버퍼를 보내는 것은 Mesa다 — `wl_shm` ARGB8888, 셋을 돌려쓴다. EGL을 숨기면 둘 다 실패한다. 그래서 TARS에서
    SDL 앱은 Mesa(gpu 묶음의 llvmpipe 또는 GPU 드라이버)가 있어야 그린다. compositor는 EGL이 필요 없다.
  - 매 프레임 `wl_surface.frame` + `damage_buffer(전체)`, 모든 창 surface에 `wp_viewporter.set_destination`.
  - libdecor-0.so.0은 libSDL3의 NEEDED라 파일은 어차피 있어야 한다. 장식 관리자를 내면 SDL은 libdecor를 안 쓴다.

## 결정

사용자 위임("주요 결정은 너의 의견에 따를 테니까")으로 Claude가 정했다.

1. 자리. 서버는 terminal 안이다(R-WY-1). 코드는 `terminal/src/wl/`(서버 · 프로토콜 처리 · 합성)에 두고 `main.zig`는
   `poll`의 칸 하나 · 프레임의 합성 단계 · 입력의 갈래만 안다. 순수한 부분(키맵 비트 · 배율 산수 · 상태 기계)은 호스트
   검사로 뺀다(`layout.zig`와 같은 경계).
2. 바인딩은 zig-wayland v0.7.0(확인 1)을 `terminal/build.zig.zon`에 url + hash로 고정한다(`translate_c`와 같은 방식).
   프로토콜 xml은 vendor에 둔다 — `wayland.xml`(1.23.1) · `xdg-shell.xml` · `viewporter.xml`(wayland-protocols 1.44).
   pkg-config에 기대지 않는다. cross 링크는 Dockerfile에 `libwayland-dev:amd64`를 더해 무버전 `.so`를 얻는다
   (확인 1의 symlink는 버리는 우회였다).
3. 소켓과 환경(확인 7). terminal이 `/run/user/<uid>`(0700, 로그인 계정)를 만들고 `wayland-0`을 연 뒤 소켓과 lock의
   주인을 그 계정으로 바꾼다. 셸의 환경에 `XDG_RUNTIME_DIR` · `WAYLAND_DISPLAY=wayland-0`을 넣는다.
4. `poll`의 `pty_end + 5`가 이벤트 루프의 fd다(확인 4). 깨면 `dispatch(0)`, 바퀴 끝(그린 뒤)에 `flushClients()`.
5. 내는 global과 판(1단, M0): `wl_compositor` 4 · `wl_shm` 1(ARGB8888 · XRGB8888) · `wl_output` 4 · `wl_seat` 7(키보드만)
   · `xdg_wm_base` 5. 판은 구현한 요청이 다 되는 가장 낮은 것이다 — SDL은 `min(서버 판, 자기 상한)`을 쓴다(확인 8).
   `wp_viewporter`는 SDL의 2단(M2)에서 더한다.
6. 키맵(확인 3). `xkbcli compile-keymap`의 출력(us · evdev · pc105, 64,754 B)을 `terminal/vendor/keymap-us.xkb`로 두고
   만든 명령과 판을 파일 머리 대신 `build.zig`의 주석에 적는다(텍스트를 고치지 않는다). 봉인한 memfd 하나를 모든
   클라이언트에 준다. modifier는 Shift 0x1 · Caps 0x2 · Ctrl 0x4 · Alt(Option) 0x8 · Super(Cmd) 0x40. 키는 evdev 코드.
   `repeat_info`는 terminal의 반복 설정과 같은 값이다.
7. app pane(1단). toplevel 하나는 끝에 새 workspace를 받고 그 workspace는 chrome이 꺼져 있다(요구사항 결정 1 · 6 —
   "풀스크린 = 자기 workspace"). column으로 여는 것은 M2다. workspace가 아홉이면 `xdg_toplevel.close`로 거절한다
   (요구사항 결정 7). 클라이언트가 끝나면 그 workspace는 셸 workspace의 마지막 패널을 닫은 것과 같은 길로 사라진다.
8. FU의 전체 화면은 workspace마다의 값이 된다(확인 5, 요구사항 결정 1). 셸 workspace의 `Cmd+Ctrl+F`는 지금 동작
   그대로이고, workspace를 옮기면 그 workspace의 chrome 상태로 격자가 바뀐다. app workspace는 늘 chrome이 꺼져 있다.
9. 합성(1단). commit된 `wl_shm` 버퍼를 프레임버퍼에 CPU로 옮긴다 — 정수 배율 중 화면에 드는 가장 큰 것으로 가장 가까운
   픽셀을 늘리고 가운데에 둔다(배율을 모르는 클라이언트는 terminal처럼 늘린다 — 요구사항 결정 5). 둘레는 검정이다.
   damage를 보는 부분 blit은 M5(R-WY-10).
10. frame 콜백(R-WY-11). 그 commit을 담은 프레임을 화면에 낸 뒤 `done`을 보낸다. 보이지 않는 workspace의 클라이언트에는
    보내지 않는다 — 클라이언트가 스스로 멈춘다.
11. 입력. app workspace가 앞에 있으면 표(R-KEY-1)의 chord는 compositor가 먹고, 나머지 키는 그 클라이언트의
    `wl_keyboard`로 간다(바이트로 번역하지 않는다, R-KEY-3). 한/영 조합은 M4(text-input) 전까지 app pane에서 안 돈다 —
    키가 그대로 간다. 셸 pane에서 표에 없는 Cmd 조합은 삼킨다(요구사항 결정 3, 확인 6 — `input_test`의 단언 셋이
    바뀌고 체인은 안 바뀐다).
12. 셸 경로 보호(R-WY-2). 클라이언트 소켓은 libwayland의 non-blocking 그대로이고, 보낼 것이 넘치면 libwayland가 그
    클라이언트를 끊는다. `Cmd+Q`는 `xdg_toplevel.close`와 `xdg_wm_base.ping`을 함께 보내고, 2초 안에 pong도 끝도 없으면
    그 클라이언트의 pid(`wl_client_get_credentials`)에 SIGKILL을 보낸다.
13. 게이트의 클라이언트는 우리가 쓴다 — `tars-wl-test`(Zig, zig-wayland 클라이언트 바인딩). 정한 색으로 버퍼를 채우고
    받은 키 · modifier · configure를 표준 출력에 찍는다. initrd 기준 A("게이트 판정이 부른다", `tars-kms-fill`과 같은
    자리)로 들어가고 `libwayland-client.so.0`(77KB)이 따라온다. 둠은 별도 저장소의 GPL 바이너리라 devlayer 묶음으로
    싣는다(요구사항 결정 12).
14. SDL 앱은 Mesa가 있어야 그린다(확인 8). SDL을 보는 milestone(M2)의 게이트는 DY처럼 gpu 묶음을 얹은 부팅을 쓴다.

## Milestone

로드맵의 WY-M0을 둘로 나눈다. 서버 뼈대 · 키 · workspace · 보호만으로도 milestone 하나의 크기이고, 둠은 별도
저장소 · devlayer 묶음 · Freedoom이라는 다른 일이다. 뒤 번호가 하나씩 밀린다(로드맵을 고친다).

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| WY-M0 | 서버 뼈대(결정 1~6) · app workspace(7) · FU를 workspace마다로(8) · 합성(9) · frame(10) · 키(11) · 보호(12) · `tars-wl-test`(13). 새 체인 `wayland` | `tars-wl-test`의 색이 화면 좌표에, 친 키가 클라이언트 로그에, `Cmd+1` · `Cmd+2` 왕복, 셸에서 표에 없는 Cmd가 안 들어감, 클라이언트를 SIGSTOP해도 셸이 친 글자를 그림, `Cmd+Q` → 2초 → SIGKILL, 루트 게이트 |
| WY-M1 | `tars-doom`의 `doomgeneric_wayland.c` · devlayer 묶음 `doom`(Freedoom) | 둠 첫 맵의 좌표 색, 녹화 A |
| WY-M2 | `wl_pointer` · 클릭 포커스 · column으로 열기(SW와 만남) · 배율(결정 5) · `wp_viewporter` 등 SDL3의 2단 | SDL3 프로그램이 수정 없이 셸 오른쪽 column에 뜸(gpu 묶음 부팅), `hidpi` 체인에 app pane 검사 |
| WY-M3 | 클립보드 `wl_data_device` | 테스트 클라이언트와 셸 사이 양방향 붙여넣기 |
| WY-M4 | 한글 `text-input-v3` | 조합 · 확정, 두 번 찍히지 않음. 녹화 B |
| WY-M5 | `xdg-decoration` · 서버 쪽 장식 · `xdg_popup` · damage 부분 blit · 호환 모드 | popup 위치, 장식의 좌표 색, 호환 모드의 키 판정 |
