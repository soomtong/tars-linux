# WY-M2 — app이 strip의 column으로, 그리고 포인터

Date: 2026-11-20
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(결정 19~26)
Status: 끝(2026-11-20). 브랜치 `app-layer-0-3`.

## 확인(조사 `wy-impl`, 세션 scratchpad `wy-m2/research.md` — SDL 3.2.10 · Mesa 25.0.7을 `apt-get source`로)

- SDL3의 드라이버 순서는 fifo가 있을 때의 Wayland → X11 → Wayland(fallback) → … → KMSDRM(`SDL_video.c:86-93`). 필수 global은
  `wl_compositor` · `xdg_wm_base` · `wl_shm`(Mesa swrast) · `wl_output`(없으면 디스플레이 0개). 나머지는 없어도 뜬다.
- SDL3 Wayland에는 framebuffer 길이 없다 — 늘 EGL이다. Mesa는 dmabuf · `wl_drm`이 없으면 zink(Vulkan 없음 — 실패) → swrast로 떨어져
  `wl_shm`(ARGB/XRGB8888)에 그린다(`platform_wayland.c:3113-3119 · 2862-2876`, `eglapi.c:700-722`) — design 결정 26.
- 장식 관리자가 없으면 libdecor(gpu 묶음에 플러그인 없음)가 fallback으로 산다 — 우리 서버에서 증명 안 됨 → 결정 25.
- 커서: `wp_cursor_shape`가 없으면 libwayland-cursor 내장 커서 surface로 `set_cursor`, `SDL_HideCursor`는 `set_cursor(NULL)`.
- `wl_pointer` 판 5~7 이벤트: frame · axis_source · axis_stop · axis_discrete.
- RESIZABLE이 아닌 SDL 창은 configure 크기를 무시하고 자기 크기 버퍼를 낸다(`SDL_waylandwindow.c:763-890`).
- `ShellWs.panes[...]`를 직접 여는 자리 32줄, `*Pane`을 받는 함수 약 15(바뀌지 않는다). `layout.Strip`은 slot 번호만 안다 — 고칠 것 없다.
- 포인터: `wirePointer`가 app workspace면 돌아간다(`main.zig:5363-5365`). PD-M4의 `pointer.Grab` · `.child` · `gesture.handOff`가
  클릭 포커스의 뼈대다. 서버의 seat capabilities는 keyboard뿐(`wl/server.zig:537-541`).
- `tars-gpu-demo`는 kmsdrm을 못박지 않고 `SDL_WINDOW_FULLSCREEN`으로 연다 — column을 보려면 창 모드 인자가 필요하다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `wy-impl`(Opus)에 세 단계로. lead는 plan · 대조 · 게이트 · commit. 서브에이전트는 commit하지 않는다.

- 단계 A — slot union(동작 변화 0). 할 일 1. 판정: 호스트 검사, 체인 `pane` · `pointer` · `fullscreen` · `wayland` · `dictation`의 판정 diff 0.
- 단계 B — column으로 열기 · configure · 합성 · verify 건너뛰기 · decoration. 할 일 2 · 3.
- 단계 C — `wl_pointer` · 클릭 포커스 · 커서 숨김 · `tars-wl-test` 포인터 줄 · `tars-gpu-demo --window` · 체인. 할 일 4 · 5 · 6.

## 착수 전에 확정한 것

1. `Slot = union(enum) { shell: Pane, app: AppPane }`, `AppPane = { toplevel: u32 }`(사각형은 strip이 안다). `Slot.shell()` · `?*Pane`
   하나로 32줄이 셸 갈래를 고른다. app 갈래가 필요한 자리(키 · 그리기 · 포인터 · 닫기 · 덤프)는 단계 B · C가 채운다 — 단계 A는
   app slot이 생기지 않으므로 `.app => unreachable`이 아니라 컴파일러가 강제하는 빈 갈래(아무것도 안 함)와 주석 "단계 B".
2. 덤프: `pane>` 줄에 app slot은 `slot=<n> app id=<toplevel>`(셸 slot의 줄 모양은 그대로 — 체인이 본다).
3. 여는 자리(결정 21). 서버의 `.toplevel` 일에 "첫 commit 전에 `set_fullscreen`을 받았는가"를 싣는다 — 지금은 toplevel을 만들 때 일이
   나오므로, 일을 첫 commit(configure ack 전 빈 commit)까지 미루거나 `set_fullscreen`이 그 사이에 오면 기록한다. 어느 쪽인지 단계 B가
   읽고 정해 보고한다.
4. configure(결정 22): pane 픽셀(`cols * CELL_W`, `rows * CELL_H`)과 states `activated`(포커스 slot일 때) · `tiled_left/right/top/bottom`
   (toplevel 판 2+). `applyLayout`에서 크기가 바뀐 app slot에 다시 보낸다. 포커스가 바뀌면 `activated`만 바뀐 configure.
5. 합성(결정 23): 셸 프레임의 app slot 사각형을 검정으로 채우고 `fit`(pane 크기 기준)으로 옮긴다. 셸 그림의 clip 목록에 app 사각형을
   더한다. frame `done`은 그 프레임을 낸 뒤(결정 10 그대로). viewport 밖 column의 app에는 `done`을 안 보낸다.
6. verify는 app slot을 건너뛴다(`compareLists`).
7. decoration(결정 25): global `zxdg_decoration_manager_v1` 1, `get_toplevel_decoration` → `configure(server_side)`, `set_mode` ·
   `unset_mode`에도 `server_side`. vendor xml(`xdg-decoration-unstable-v1.xml`, wayland-protocols 1.44)을 `terminal/vendor/wayland/`에.
8. 포인터(결정 24): seat capabilities에 pointer. `pointer.Pane`에 app — `ownerOf`는 늘 `.child`. `reportTo`가 slot이 app이면 서버의
   `pointerMotion` · `pointerButton` · `pointerAxis`(surface 좌표 = (x − pane 원점 − fit.x) / fit.k, `wl_fixed`). enter · leave는 포인터 아래
   slot이 바뀔 때(버튼을 쥔 동안은 미룸). 버튼은 evdev `BTN_*` 그대로. 휠은 `axis(vertical, 10.0 × n)` + `axis_discrete(n)` + `frame`.
   app workspace(자기 workspace의 창)에도 같은 길 — `wirePointer`의 `asShell() orelse return`을 app 갈래로.
9. 클릭 포커스: `gesture.handOff`가 포커스를 app slot으로 옮기면 `syncFocus`가 그 창에 `wl_keyboard.enter`(키보드 포커스 = 포커스 slot이
   app일 때 그 창). 셸 pane 클릭이면 app은 `leave`.
10. 커서: `set_cursor(NULL)`을 받은 클라이언트의 surface 위에서는 화살표를 그리지 않는다. 그 밖의 `set_cursor`는 화살표 그대로.
11. 로그: `wl> column id=<n> slot=<s> ws=<k>`(column으로 열림) · `wl> configure id=<n> w=<w> h=<h> act=<0|1>` · `wl> pointer enter id=` ·
    `wl> pointer leave id=` · `wl> button id=<n> code=<BTN> state=<0|1>` · `wl> axis id=<n> v=<n>` · `wl> cursor id=<n> hidden=<0|1>`.
12. `tars-wl-test`: `--window`가 기본(지금도 fullscreen을 안 부른다 — 확인), `--fullscreen`이면 `set_fullscreen`. 포인터 줄
    `wl-test> pointer enter x= y=` · `motion x= y=`(처음 다섯) · `button code= state=` · `axis v=` · `leave`, `configure`에 states.
    `--hide-cursor`면 enter 때 `set_cursor(NULL)`.
13. `tars-gpu-demo --window WxH`: `SDL_WINDOW_RESIZABLE`로 창 모드(FULLSCREEN 대신), 키 · 단계 줄은 그대로. SDL 코드에 Wayland 전용 줄을
    더하지 않는다.
14. 둠(`set_fullscreen`)은 자기 workspace 그대로 — wayland 체인 부팅 2가 고치지 않고 통과하는 것이 회귀 검사다. 둠과 `tars-wl-test`의
    부팅 1 판정 중 "새 workspace(ws=2)"를 보는 것은 `--fullscreen`을 붙여 그대로 둔다.

## 체인

wayland 부팅 1(tars-wl-test, 판정 16~22를 더함):

16. `tars-wl-test --color 3366CC &`(fullscreen 없이) → `wl> column id=… slot=… ws=1`, `pane> ws=1/1` 줄의 slot 둘, 셸이 왼쪽 반 · 창이
    오른쪽 반(screendump: 오른쪽 반 가운데 상자 `3366cc`, 왼쪽 반에 프롬프트). `wl-test> configure w=… h=…`가 pane 픽셀 크기.
17. `Cmd+R`(폭 preset) → 새 `wl> configure` · `wl-test> configure`가 새 폭.
18. 포인터: `mouse_move`로 창 위 → `wl-test> pointer enter`, `mouse_button 1` → `wl-test> button code=272 state=1` · `wl> button`,
    그리고 키보드 포커스가 창으로(`wl-test> key code=30`이 `sendkey a`로).
19. 셸 pane 클릭 → `wl-test> leave`(키보드) · 셸에 `echo back`이 그려진다.
20. 휠 → `wl-test> axis v=…`.
21. `--hide-cursor`로 띄운 창 위에서 화살표가 없다(screendump의 포인터 자리 색이 창 색).
22. 창 slot의 `Cmd+Q` → 닫히고 column이 당겨진다(`pane>` slot 하나, 셸이 전체 폭).

display 부팅 3(base · gpu, 판정 16a~16d를 더함):

16a. `tars-gpu-demo --window 640x400 > /tmp/w.log &` → `video wayland` 줄, `wl> column`, 오른쪽 column 안이 1초 사이 바뀐다(llvmpipe).
16b. 그 column 클릭 → `sendkey x` → `/tmp/w.log`에 `key X`. 셸 pane 클릭 → `echo dy-back`이 그려진다.
16c. 셸 프레임의 verify mismatch 0(app slot 건너뛰기).
16d. `Cmd+Q` → 데모가 끝나고 column이 당겨진다.

## 할 일

1. (A) slot union · `Slot.shell()` · 32줄 · 덤프 모양(app은 아직 안 생김). 체인 다섯 판정 diff 0.
2. (B) 여는 자리 · configure · 합성 · verify 건너뛰기 · 키 갈래(포커스 slot이 app이면 `readKeyboardApp` 길) · 닫기(`Cmd+Q` · 클라이언트 끝 →
   slot 닫기와 같은 길).
3. (B) decoration manager · vendor xml.
4. (C) `wl_pointer` · enter/leave · 클릭 포커스 · 휠 · 커서 숨김.
5. (C) `tars-wl-test`의 인자 · 줄, `tars-gpu-demo --window`.
6. (C) wayland 판정 16~22, display 판정 16a~16d, 도움말(`docs/help/desk.md` — 앱이 오른쪽 column으로, 클릭 포커스).
7. lead: 체인 · verify grep · 루트 게이트.

## 판정

- 호스트 검사, 체인 wayland · display PASS, 루트 게이트 35/35, verify mismatch 0.

## 결과

구현은 `wy-impl`(Herdr, Opus), lead는 대조 · 게이트 · commit.

1. 단계 A `04c2897`: `Slot` union. 고르는 함수는 `Slot.asPane()` — Zig 0.17.1이 필드 `shell`과 같은 이름의 선언을 거절해 plan의
   `Slot.shell()`을 못 썼다. 다섯 체인 + terminal의 `pane>` 줄이 HEAD와 diff 0(`screen>`은 치는 중 프레임 · 자동 제안 같은 타이밍 차이만).
2. 단계 B `ee8557c`: 서버의 `toplevel` 일을 첫 commit으로 미뤘다 — xdg-shell 순서상 `set_fullscreen`은 역할과 첫 commit 사이에 온다(둠).
   configure는 `applyLayout`에서가 아니라 바퀴마다 `syncColumns`가 모든 app slot에 크기를 알리고 서버가 같은 값을 거른다(부르는 자리가
   열 곳 가까이라 한 길로). verify는 보이는 창 사각형을 실제 fb에서 그림자로 복사해 비교에서 뺀다. 포커스 slot이 창인 셸 프레임은
   `screen>` 덤프가 없다 — 체인은 셸 글자를 볼 때 포커스를 셸에 둔다. 덤프 줄 `pane> … slot=<n> app id=<t> rect=…`.
3. 단계 C `939ffad`: `wl_pointer`(enter · leave · motion · button · axis · frame, 버튼 grab 동안 leave 미룸), 클릭 포커스는 PD-M4의
   `Grab` → `handOff` 길 그대로, `set_cursor(NULL)`이면 화살표를 안 그림. 자기 workspace 창에도 `wireAppPointer`로 포인터.
   `tars-gpu-demo --window WxH`(`SDL_WINDOW_RESIZABLE`).
4. SDL3 실측: SDL은 렌더러가 GL 창을 바라 창을 한 번 만들었다 지우고 다시 짓는다(`column id=1` → `unmap` → `column id=2`) — 오른쪽이 한 번
   깜빡인다. configure를 따라 `616x752` 버퍼를 냈다. llvmpipe → `wl_shm`, QEMU TCG에서 1.5~4.6 fps(KMSDRM 판정 13은 2.2).
5. 판정 순서는 16 · 18~21 · 17 · 22 — 17(`Cmd+R` 전체 폭)이 셸을 화면 밖으로 밀어 클릭 판정을 앞에 뒀다. 체인 둘(wayland 부팅 1 ·
   display 부팅 3)에 USB 마우스를 붙였다. display 16a는 처음에 "검정 → 색"으로도 통과하는 약한 판정이었다 — 두 장 모두 검정이 아니고
   `wl> commit … buf=616x752`가 있어야 하는 것으로 조였다.
6. 체인 단독 PASS: wayland 373초 · display 464초 · pointer · pane · fullscreen · hidpi, verify mismatch 0. 루트 게이트 35/35 첫 판
   PASS(prebuild 351초 + lanes 1,560초, `out/gate-logs/20261119-190930`, 잘린 줄 0). WY-M2 체인 96초.

남은 걱정: (1) SDL의 창 다시 짓기 깜빡임 — 첫 commit 뒤 한 바퀴 기다려 자리를 정하면 줄일 수 있다. (2) vsync SDL 창은 숨은 동안 `done`을
못 받아 swap에서 멈추고 ping에도 못 답할 수 있다 — 숨은 창의 `Cmd+Q`는 SIGKILL이 된다(체인은 보이는 창만 본다). (3) 커서 이미지 합성 없음.
