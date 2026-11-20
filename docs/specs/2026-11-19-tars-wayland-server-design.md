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

구현(단계 C)에서 고친 단언은 셋이 아니라 여섯이었다 — 위 셋에 copy mode 검사 10의 모드 밖 `Cmd+C`(937행) · 검사 62의
`Cmd+0`(1852행) · 검사 84의 `Cmd+Option+D`(1888행)가 더해진다. 모두 "표 밖 Cmd → 원래 키"를 단언하던 같은 성질이다.

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
    표의 chord 중 `Cmd+W` · `Cmd+T`는 app에서 앱의 것이다(요구사항 결정 3 — 브라우저의 탭 닫기 · 새 탭, WY-M0 결과 3).
12. 셸 경로 보호(R-WY-2). 클라이언트 소켓은 libwayland의 non-blocking 그대로이고, 보낼 것이 넘치면 libwayland가 그
    클라이언트를 끊는다. `Cmd+Q`는 `xdg_toplevel.close`와 `xdg_wm_base.ping`을 함께 보내고, 2초 안에 pong도 끝도 없으면
    그 클라이언트의 pid(`wl_client_get_credentials`)에 SIGKILL을 보낸다.
13. 게이트의 클라이언트는 우리가 쓴다 — `tars-wl-test`(Zig, zig-wayland 클라이언트 바인딩). 정한 색으로 버퍼를 채우고
    받은 키 · modifier · configure를 표준 출력에 찍는다. initrd 기준 A("게이트 판정이 부른다", `tars-kms-fill`과 같은
    자리)로 들어가고 `libwayland-client.so.0`(77KB)이 따라온다. 둠은 별도 저장소의 GPL 바이너리라 devlayer 묶음으로
    싣는다(요구사항 결정 12).
14. SDL 앱은 Mesa가 있어야 그린다(확인 8). SDL을 보는 milestone(M2)의 게이트는 DY처럼 gpu 묶음을 얹은 부팅을 쓴다.
15. `Workspace`는 `kind: union(enum) { shell: ShellWs, app: AppWs }`다(WY-M0 단계 B의 읽기 보고, 2026-11-19). `ShellWs`는
    지금의 `{ strip, panes, focus }`에 FU의 `fullscreen`을 더한 것, `AppWs`는 toplevel id다. 이유: `.?`로 null을 푸는
    자리 여섯(덤프 · 포인터 cancel · 키 · 닫기 · 받아쓰기 · 그리기)이 app workspace에서 panic할 것을 컴파일 오류로 바꾼다.
    `layout.Strip`에 pane 0개라는 새 상태가 필요 없고, "app은 늘 chrome 없음"이 타입에 선다. 입구 약 22곳만 고친다.
16. 마지막 셸 pane이 끝나도 app workspace가 남아 있으면 terminal은 산다. 셸도 app도 없을 때만 지금처럼 끝난다(pane 체인
    9b는 그대로). 셸을 닫았다고 둠이 함께 죽지 않는다.
17. app 프레임은 render verify를 하지 않는다 — 그림자는 셸 화면만 흉내 낸다. 셸 프레임의 `verify>` 줄은 그대로라 루트
    게이트의 "verify 줄이 있다"는 선다. workspace를 옮기는 자리 넷은 `enterWorkspace(i)` 하나를 불러 격자(FU의
    workspace마다 값)를 다시 세운다.
18. `tars-fullscreen`은 exec 전에 `WAYLAND_DISPLAY` · `XDG_RUNTIME_DIR`을 뺀다(WY-M0 루트 게이트, 2026-11-19 — 앞의 것만
    빼면 libwayland가 `$XDG_RUNTIME_DIR/wayland-0`을 기본으로 찾아 그래도 붙었다). 그 문으로 띄우는 명령은
    KMS에 직접 그리고, 양보한 동안 compositor는 그리지 않는다. 결정 3이 셸에 `WAYLAND_DISPLAY`를 준 뒤 SDL3(`tars-gpu-demo`)가
    kmsdrm 대신 Wayland를 골라 우리 서버의 창이 됐다 — DY 판정 12a(자동 실행 데모가 그린다)가 빨갰다. 데모 쪽에서 드라이버를
    못박는 대신 문 쪽에서 고치는 것은, `tars-fullscreen`을 거치는 모든 프로그램이 같은 처지이기 때문이다.

WY-M2를 열며(2026-11-20, 조사 `wy-impl` — SDL 3.2.10 · Mesa 25.0.7 소스, 근거는 plan WY-M2의 확인 절):

19. 로드맵의 WY-M2를 둘로 자른다 — WY-M2는 column과 포인터, WY-M3(새)은 배율(결정 5). 둘은 서로 기대지 않는다: SDL3는 배율
    없이도 논리 크기 버퍼로 column에 선다. 뒤 번호(클립보드 · 한글 · 장식)가 하나씩 밀린다.
20. app은 strip의 slot이다 — `ShellWs.panes`의 칸이 `Slot = union(enum) { shell: Pane, app: AppPane }`이 된다. strip의 규칙(한도 8 ·
    column당 3 · 이웃 · viewport · `Cmd+R` · 닫히면 당겨짐)이 app에 그대로 온다. 결정 15의 "null을 푸는 자리를 컴파일 오류로"가
    slot 단으로 내려온다. 별도 목록(셸 목록 + app 목록)은 둘이 어긋나는 panic 길을 다시 열어 버렸다. `AppWs`(자기 workspace의 창)는
    그대로 둔다 — 합치기는 WY-M0 · M1의 길을 다시 여는 일이라 이 milestone 밖이다.
21. 어디에 여는가: 첫 commit 전에 `set_fullscreen`을 보낸 창은 지금처럼 자기 workspace(결정 7, 둠). 아니면 앞이 셸 workspace일 때
    포커스 column 오른쪽에 새 column(R-WIN-1), 앞이 app workspace면 자기 workspace. 자리가 없으면(slot 8) `close`로 거절.
    app slot은 strip에서 여느 slot이다 — 그 위의 `Cmd+D`는 오른쪽에 셸 column, `Cmd+Shift+D`는 그 column 아래에 셸.
22. app slot의 configure는 pane 픽셀 크기와 `activated` · `tiled_*`(판 2+)다. 크기가 바뀌는 자리는 `applyLayout` 하나라 거기서
    다시 보낸다. 다른 크기의 버퍼(RESIZABLE이 아닌 SDL 창)는 `fit`으로 pane 안 가운데에 정수 배로(1보다 크면 자른다).
23. app slot은 셸 프레임 안에서 그 사각형만 칠하고(같은 clip 목록), render verify는 app slot을 건너뛴다(결정 17의 연장).
24. `wl_pointer`(seat 7 그대로): PD-M4의 `.child` 길을 탄다 — app slot은 늘 `.child`, 첫 누름이 포커스를 옮긴다(클릭 포커스,
    R-WIN-6). surface 좌표는 `fit`을 거꾸로. 휠은 `axis` + `axis_discrete` + `frame`. 버튼을 쥔 동안은 leave를 미룬다(implicit grab).
    화살표는 terminal이 계속 그리고 `set_cursor(NULL)`일 때만 그 surface 위에서 숨긴다. 커서 surface의 그림은 합성하지 않는다.
25. `zxdg_decoration_manager_v1`을 내고 늘 `server_side`로 답한다(그리는 것은 M5). 없으면 SDL3가 libdecor fallback을 타는데 그 길은
    우리 서버에서 증명된 적이 없다.
26. Wayland 위의 SDL 앱은 GPU가 아니라 llvmpipe(CPU)로 `wl_shm`에 그린다 — Mesa의 EGL Wayland drm 길은 `zwp_linux_dmabuf_v1`나
    `wl_drm`을 요구하고 없으면 swrast로 떨어진다(실기 i915에서도). GPU가 필요한 프로그램은 DY 길(`tars-fullscreen`)이다. dmabuf는 위험으로 남긴다.

WY-M3을 열며(2026-11-20, 조사 `wy-m3` — HEAD `593cb94`의 코드와 vendored `wayland.xml`, 근거는 plan WY-M3의 확인 절):

27. 배율을 알리는 길: `wl_compositor`를 판 6으로 올리고, 판 6 이상의 surface에만 만든 직후 `preferred_buffer_scale(S)`를 보낸다
    (S = HS 배율, 배율 1에서도 1). 판 4로 bind한 클라이언트(둠)에는 판 6 이벤트를 보내지 않는다 — libwayland가 막아 주는지에 기대지
    않는다. `wl_output`은 판 4 그대로, `mode`는 물리 크기(xml: "physical hardware units"), `scale`은 S. 창이 처음 보일 때 그 클라이언트의
    output마다 `wl_surface.enter`를 보내고 leave는 보내지 않는다(출력이 하나뿐 — xml이 허락한다). configure 크기는 논리 그대로다.
    배율은 terminal 수명 동안 고정이라(바꾸는 길은 `reload terminal`) preferred를 다시 보낼 일은 없다.
28. `set_buffer_scale`은 xml 그대로 받는다 — double-buffered(commit에서 확정), 0 이하는 `invalid_scale`, 버퍼가 그 배수가 아니면
    `invalid_size`로 끊는다. 느슨하게 받을 까닭이 우리 쪽 클라이언트에 없다. surface 판 5+의 `offset`은 받아서 버리고, attach의 0이 아닌
    x · y는 `invalid_offset`이다(놓는 자리는 서버가 정한다).
29. 창의 크기는 surface 크기(버퍼 ÷ buffer_scale)다. `fit` · `last_fit` · 포인터의 surface 좌표가 모두 이 단위라 포인터 길은 바뀌지 않는다.
    로그의 `scale=`은 지금처럼 `fit`의 늘림 배수이고(체인 패턴이 본다) buffer_scale은 1이 아닐 때만 끝에 ` bs=N`으로 붙인다.
30. 물리 합성(요구사항 결정 5): `drm.present`를 `stage`(그림자 → 물리로 늘리기)와 `flush`(DIRTYFB)로 나누고, buffer_scale > 1인 창은
    그 사이에서 물리 dumb 버퍼에 직접 옮긴다(`fit` × S — bs == S면 1:1). 순서가 반대면 같은 프레임의 늘리기가 창을 덮는다. 그림자에도
    논리 복사본(솎은 것)을 계속 둔다 — 화살표의 `saved` · verify · 덤프가 그림자를 읽고, 다시 합성이 빠진 자리가 검게 뚫리지 않는다.
    clip이 그 창 사각형과 겹치는 모든 present(화살표만 옮기는 바퀴 포함)에서 겹친 부분만 다시 옮기고, 화살표는 그 위에 마스크로 다시
    찍는다. 배율 1 화면에서는 `stage`가 아무것도 안 하고 물리 합성도 없다 — "배율 1은 지금과 같은 길".
31. `wp_viewporter`와 fractional scale은 내지 않는다. 이번 클라이언트(`tars-wl-test` · 둠 · `tars-gpu-demo --window`) 중 쓰는 것이 없고,
    SDL3는 HIGH_PIXEL_DENSITY가 아닌 창에서 늘 논리 크기 버퍼다. 내면 `fit` · 포인터 · 물리 합성 식마다 갈래가 는다.

WY-M4를 열며(2026-11-20, 조사 `wy-m4` — HEAD `34c721d`, SDL 3.2.10 소스, 근거는 plan WY-M4의 확인 절):

32. 클립보드는 `wl_data_device_manager` 판 2다(결정 5 — 판 3의 새 요청은 전부 drag-and-drop 액션). drag-and-drop은 범위 밖이다 —
    `start_drag`는 받기만 하고 source에 곧바로 `cancelled`. primary selection은 내지 않는다(R-WY-8 "클립보드는 하나", macOS 손 모델).
33. 앱 → 셸은 즉시 받는다. `set_selection`을 받아들이면 그 자리에서 mime을 고르고 파이프로 `send`를 보내 서버 사본으로 읽고, 다 읽으면
    `clipboard.zig`에 넣는다(`clip>` 줄 그대로). 셸 쪽 붙여넣기는 동기로 남고, 앱이 끝나도 붙는다. 지연 받기는 셸의 `Cmd+V` · 검색창
    붙여넣기를 비동기로 만든다. 받는 한도는 1 MiB · 2초(넘으면 버리고 클립보드는 그대로). 파이프 · 기한은 서버의 epoll(`addFd` · `addTimer`)에 싣는다.
34. 셸 → 앱: 셸의 복사(copy mode `y` · 포인터 뗌)가 서버 사본을 바꾸고, 옛 source에 `cancelled`, 키보드 포커스 클라이언트에 새 offer와
    `selection`. `selection`은 키보드 `enter` 바로 앞에 보낸다(xml). `receive`는 요청 처리기 안에서 곧바로 쓴다 — SDL은 14 ms만 기다린다.
    다 못 쓰면 남은 것을 writable에 이어 쓴다(같은 한도). 내는 mime은 `text/plain;charset=utf-8` · `text/plain` · `UTF8_STRING` · `TEXT`,
    받을 때의 우선순위도 이 순서(`UTF8_STRING`이 둘째). 인코딩은 검사하지 않는다(셸 클립보드처럼 바이트).
35. terminal은 SIGPIPE를 무시하고 `pty.spawn`의 자식에서 기본으로 되돌린다 — 읽기 끝을 닫은 클라이언트에 쓰다가 terminal(셸 전부)이 죽지 않게.
36. `set_selection`의 serial 값은 보지 않는다. 받아들이는 조건은 "지금 또는 가장 최근에 키보드 포커스를 가졌던 클라이언트" — SDL은 serial 0을
    보내는 길이 있고, `Cmd+C` 바로 뒤의 workspace 전환은 `leave`가 먼저 갈 수 있다. 포커스를 가져 본 적 없는 클라이언트는 버린다.
37. `clipboard=pane`이면 Wayland 쪽을 셸과 잇지 않는다(서버 사본은 클라이언트끼리만). `shared`(기본)에서만 양방향이다. app pane의 `Cmd+V`는
    Super+V로 가므로 SDL · GTK 앱의 붙여넣기 키는 WY-M6 호환 모드까지 기다린다 — 이번 끝나는 조건은 `tars-wl-test`와 셸이다.

WY-M5를 열며(2026-11-20, 조사 `wy-m5` — HEAD `1cb942a`, wayland-protocols 1.44의 text-input xml, SDL 3.2.10 소스, 근거는 plan WY-M5의 확인 절):

38. IME는 `zwp_text_input_manager_v3` 1 하나다. `zwp_input_method_v2`(외부 IME)는 안 낸다 — R-WY-9가 IME를 TARS 오토마타 하나로 정했다.
    text-input v1 · v2도 지금은 안 낸다 — Chromium이 v3로 서는지는 CR design에서 잰다(요구사항 위험 6). 상태 요청(surrounding · content_type ·
    cursor_rectangle · change_cause)은 받기만 한다 — 오토마타가 앞뒤 글자를 안 보고 후보 창이 없다. content_type은 로그 한 줄.
39. 오토마타 · 한/영 상태 · 조합 버퍼는 `input.State` 하나다(R-KEY-6 "상태는 compositor의 것"). 서버는 오토마타를 모른다 — "포커스 창의
    text_input이 켜졌나"(`imeActive`)를 알려 주고 commit/preedit을 받아 보내는(`imeSend`) 관이다. 서버가 자기 음절을 들면 셸과 앱의 한/영이 둘로 갈린다.
40. app 쪽 한글 층은 text_input을 enable한 창에서만 돈다(R-KEY-6의 "app pane에서도 같다"를 이렇게 읽는다). 켜지 않은 창(둠 · `tars-wl-test` 기본)은
    키 길이 WY-M4와 한 바이트도 다르지 않다 — 둠의 Ctrl(쏘기) tap이 한/영을 뒤집으면 안 된다. 켠 창에서는 셸의 `hangulLayer` 갈래를 그대로 쓴다.
41. IME가 먹은 키는 `wl_keyboard`로 보내지 않는다 — xml은 말이 없지만 SDL3는 켜진 동안 받은 키마다 글자를 만들어, 둘 다 보내면 두 번 찍힌다.
    확정은 그 뒤의 키보다 먼저 간다(`commit_string` → `done` → 키). 한 `done`에 확정과 다음 조합을 같이 싣는다.
42. 포커스를 잃으면 조합을 확정한다(버리지 않는다 — 셸의 `.cancel`과 같다). 앱 조합의 자리는 키보드 포커스를 옮기는 단 하나의 길
    `focusTo` — 옛 창에 `commit_string` + 빈 preedit + `done`, 그다음 text_input `leave` · 키보드 `leave`. 창이 닫혀 잃으면 버린다.
    조합의 주인(셸 · 앱)은 `input.State`에 둔다. 셸 조합은 바퀴 끝에서는 옛 셸 pane을 모르므로 포커스를 바꾸는 자리가 먼저 그 PTY에 확정한다
    (키 chord · 포인터 `.cancel`은 전부터, 새 창 `openApp`은 WY-M5 단계 B가 더함). `focusTo`에 남은 셸 조합은 받을 셸이 없는 것이라 버린다. 수정키 tap 상태는 키보드 포커스가 셸 ↔ 앱으로 바뀔 때 리셋한다(앱에서 누른 Ctrl을 셸에서 뗀 것이 tap이 되지 않게).
43. text_input의 `enter` · `leave`는 키보드 포커스를 따른다. 순서는 `selection` → text_input `enter` → 키보드 `enter`. "켜졌나"는 포커스 surface가
    맞으면 참이다 — SDL처럼 키보드 `enter`에 enable하는 클라이언트도, text_input `enter`에 enable하는 클라이언트도 받힌다.

WY-M6을 열며(2026-11-20, 조사 `wy-m6` — HEAD `e654a8e`, SDL 3.2.10 · 둠 소스, 근거는 plan WY-M6의 확인 절):

44. 옛 WY-M6을 둘로 자른다(결정 19와 같은 까닭). WY-M6은 호환 모드 · damage — TK가 바로 쓴다(R-KIT-1 · R-CA-2). WY-M7(새)은 popup · 장식 —
    CR만 쓰고(툴킷은 popup · 장식을 안 쓴다, 요구사항 결정 9 · R-TKW-2 · 3) 최소 집합은 Chromium이 실제로 보내는 것을 CR-M0이 잰 뒤에 고른다.
    로드맵 순서는 WY-M6 → TK → CR-M0 → WY-M7 → CR-M1(로드맵 4판).
45. 호환 모드(요구사항 결정 3)는 서버 한 자리다 — 포커스 클라이언트가 호환이면 `wl_keyboard.modifiers`의 depressed에서 Super(0x40)를 지우고
    Ctrl(0x4)을 켠다(`key`의 modifiers · `enterKeyboard`). 키 코드는 바꾸지 않는다 — 둠에서 Cmd가 쏘지 않고 `Held`의 짝이 맞는다. `input.zig` ·
    `main.zig`의 키 길(표 · 한글 층)은 그대로다. 표의 chord는 이미 compositor가 먹었으므로 "표에 없는 Cmd 조합 전부"와 같다.
46. 원래 모드의 문 `tars_menu_v1`의 뼈대를 WY-M6이 세운다 — 저장소 안 xml(vendor 밖), 판 1, 요청은 `destroy` 하나. bind한 클라이언트는 원래 모드(Super).
    TK-M5가 같은 인터페이스에 메뉴 요청을 더한다. 이 문이 없으면 TK-M0~M4의 앱이 전부 호환 모드라 `Cmd+A` ≠ `Ctrl+A`(R-KIT-6)가 깨진다.
    켜는 다른 길(설정 키 · 앱 목록)은 두지 않는다.
47. damage(R-WY-10): surface마다 pending → commit에서 누적하는 합집합 사각형 하나(버퍼 좌표, `damage`는 × buffer_scale). 화면에는 그 사각형만
    옮기고 clip에 넣는다(둘레 검정 칠하기 없음). 통째로 되돌아가는 조건은 버퍼 크기 · buffer_scale · `fit` 바뀜, 첫 그림, 통째 프레임, 앞 창이 바뀜 —
    지금 "둘레를 다시 검정으로"를 정하는 자리와 같다. 물리 합성은 clip을 따라 저절로 작아진다. 사각형 목록은 숫자가 바랄 때.

## Milestone

로드맵의 WY-M0을 둘로 나눈다. 서버 뼈대 · 키 · workspace · 보호만으로도 milestone 하나의 크기이고, 둠은 별도
저장소 · devlayer 묶음 · Freedoom이라는 다른 일이다. 뒤 번호가 하나씩 밀린다(로드맵을 고친다).

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| WY-M0 | 서버 뼈대(결정 1~6) · app workspace(7) · FU를 workspace마다로(8) · 합성(9) · frame(10) · 키(11) · 보호(12) · `tars-wl-test`(13). 새 체인 `wayland` | `tars-wl-test`의 색이 화면 좌표에, 친 키가 클라이언트 로그에, `Cmd+1` · `Cmd+2` 왕복, 셸에서 표에 없는 Cmd가 안 들어감, 클라이언트를 SIGSTOP해도 셸이 친 글자를 그림, `Cmd+Q` → 2초 → SIGKILL, 루트 게이트 |
| WY-M1 | `tars-doom`의 `doomgeneric_wayland.c` · devlayer 묶음 `doom`(Freedoom) | 둠 첫 맵의 좌표 색, 녹화 A |
| WY-M2 | app이 strip의 column(결정 20~23) · `wl_pointer` · 클릭 포커스(24) · decoration server_side(25) · `tars-gpu-demo --window` | SDL3 프로그램이 수정 없이 셸 오른쪽 column에 뜸(gpu 묶음 부팅), `tars-wl-test`의 포인터 · 클릭 포커스 · `Cmd+R` configure |
| WY-M3 | 배율(결정 5 · 27~31) — `wl_output` 물리 mode + scale, `wl_compositor` 6 · `preferred_buffer_scale`, `set_buffer_scale`, present 단계의 물리 합성. viewporter는 안 냄 | `hidpi` 체인에 app pane 검사(`tars-wl-test --buffer-scale` · `--checker`, 물리 1픽셀 바둑판) |
| WY-M4 | 클립보드 `wl_data_device_manager` 2(결정 32~37) — 즉시 받기, 포커스 앞 selection, SIGPIPE | 테스트 클라이언트와 셸 사이 양방향 붙여넣기(wayland 판정 23 · 24) |
| WY-M5 | 한글 `text-input-v3`(결정 38~43) — 오토마타 하나, 켠 창에서만, 먹은 키는 안 보냄, 포커스를 잃으면 확정 | 조합 · 확정, 두 번 찍히지 않음(wayland 판정 26~28). 녹화 B |
| WY-M6 | 호환 모드(결정 45) · `tars_menu_v1` 뼈대(46) · damage 부분 blit(47) | 호환 창 `mods depressed=0x4` · 원래 창 `0x40`, 부분 `wl> blit` 줄과 좌표 색(wayland 판정 29 · 30) |
| WY-M7 | `xdg_popup` · `xdg_positioner`(slide) · 서버 쪽 장식(포커스 테두리 · 빈 칸 이름) — CR-M0 실측 뒤(결정 44) | popup 위치 · grab · 포커스 잃음, 장식의 좌표 색 |
