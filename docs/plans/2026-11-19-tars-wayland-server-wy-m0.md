# WY-M0 — terminal 안의 Wayland 서버

Date: 2026-11-19
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(확인 1~8, 결정 1~14)
Status: plan. 브랜치 `app-layer-0-3`.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트(Opus)에 세 단계로 맡긴다. 단계마다 lead가 diff를 대조하고 단계의 판정을 돌린 뒤 다음을
넘긴다. lead는 plan · 대조 · 게이트 · commit. 서브에이전트는 commit하지 않는다.

- 단계 A — 빌드와 테스트 클라이언트(동작 변화 0). 할 일 1 · 2.
- 단계 B — 서버와 app workspace. 할 일 3 · 4 · 5. 시작 전에 `Workspace`를 어떻게 바꿀지 읽기만 하고 보고한다(확정 6).
- 단계 C — 입력 · 보호 · 체인. 할 일 6 · 7 · 8.

## 이 milestone이 끝나면

- 셸에서 `tars-wl-test`를 띄우면 끝에 새 workspace가 생기고, chrome 없는 화면 가운데에 그 클라이언트의 색 버퍼가 정수
  배율로 늘어나 보인다. `Cmd+1` · `Cmd+2`로 셸과 오간다.
- 그 workspace에서 친 키는 클라이언트의 `wl_keyboard`로 간다(Cmd 표의 chord는 compositor가 먹는다).
- 셸 pane에서 표에 없는 Cmd 조합은 아무것도 안 친다(`Cmd+C`가 `c`를 치지 않는다).
- 클라이언트가 멈춰도(SIGSTOP) 셸은 친 글자를 그린다. `Cmd+Q`는 close를 보내고 2초 안에 안 끝나면 SIGKILL한다.
- 클라이언트가 없을 때 terminal은 지금과 같다 — 기존 체인 34개가 고치지 않고 통과한다(`input_test`의 단언 셋은 바뀐다).

## 착수 전에 확정한 것

1. 의존(결정 2). `terminal/build.zig.zon`에 zig-wayland v0.7.0(`fc7672f`)을 url + hash로. `zig fetch`로 hash를 얻는다.
   vendor: `terminal/vendor/wayland/wayland.xml`(libwayland 1.23.1) · `xdg-shell.xml` · `viewporter.xml`(wayland-protocols
   1.44) — 판과 출처를 `terminal/vendor/wayland/README`가 아니라 `build.zig`의 주석에 적는다(다른 vendor 파일과 같은 방식인지
   먼저 보고 따른다). 스캐너 generate: `wl_compositor` 4 · `wl_shm` 1 · `wl_output` 4 · `wl_seat` 7 · `xdg_wm_base` 5
   (결정 5).
2. Dockerfile: `libwayland-dev:amd64`(무버전 `.so` · 헤더)와 `libwayland-server0:amd64` · `libwayland-client0:amd64`. 이미지를
   다시 만드는 시간이 길면 알린다. initrd는 `make_initrd.sh`의 `copy_lib_deps`가 NEEDED를 따라 싣는다(확인 2) —
   `libwayland-server.so.0` · `libwayland-client.so.0`이 실리는지 `bsdtar -tf`나 `cpio -it`로 본다.
3. `tars-wl-test`(결정 13)는 terminal의 build에서 나온다(같은 스캐너를 쓴다). `make_initrd.sh`가 `/usr/bin`에 둔다
   (`tars-kms-fill`과 같은 모양, 178행). 하는 일:
   - `tars-wl-test [--color RRGGBB] [--size WxH]` — xdg_toplevel 하나, 기본 320x200, 한 색으로 채운 ARGB8888(알파 FF)
     `wl_shm` 버퍼. configure를 받으면 ack하고 다시 그린다.
   - 표준 출력에 한 줄씩: `wl-test> configure w=… h=…` · `wl-test> keymap size=…` · `wl-test> key code=<evdev> state=<0|1>` ·
     `wl-test> mods depressed=0x…` · `wl-test> close` · `wl-test> frame n=…`(처음 열 번만). `close`를 받으면 끝난다.
   - `--ignore-close`이면 close를 무시하고 ping에 답하지 않는다(확정 11의 판정용). SIGSTOP은 체인이 한다.
4. 서버의 자리(결정 1 · 3 · 4). `terminal/src/wl/`에 서버 상태(`wl.Server`, global들, 클라이언트 · surface · toplevel 목록).
   순수 부분(modifier 비트 · 배율과 가운데 산수 · toplevel 상태 기계)은 `wl_logic.zig` 같은 순수 파일과 호스트 검사로 뺀다.
   소켓: `/run/user/<uid>`(0700, 계정의 것) → `addSocket("wayland-0")` → 소켓 · `.lock`의 주인을 계정으로. 계정이 없으면
   (root 셸 부팅) `/run/user/0`. 셸 자식의 환경에 `XDG_RUNTIME_DIR` · `WAYLAND_DISPLAY=wayland-0`.
   서버를 못 띄우면 `wl> off reason=…` 한 줄을 찍고 terminal은 지금처럼 돈다.
5. 로그(체인이 본다): `wl> listen path=/run/user/<uid>/wayland-0` · `wl> client pid=<n>` · `wl> toplevel id=<n> ws=<k>` ·
   `wl> commit id=<n> buf=<w>x<h> scale=<s> at=<x>,<y>`(크기나 자리가 바뀔 때만) · `wl> key code=<n> state=<0|1> to=<id>` ·
   `wl> close id=<n>` · `wl> ping id=<n>` · `wl> kill pid=<n>` · `wl> gone pid=<n>`.
6. `Workspace`의 모양은 단계 B의 첫 일로 정한다. 서브에이전트가 `main.zig`에서 `strip` · `panes` · `focus`를 읽는 자리
   (lead가 센 것 약 82곳)를 갈래로 나눠 두 안을 낸다 — (가) `Workspace`에 `app: ?u32`(toplevel id)를 더하고 app workspace는
   pane이 0인 strip을 갖는다, (나) `kind: union(enum) { shell, app }`. 각 안에서 고칠 자리 수와 위험(pane이 0인 strip에
   `panes[focus].?`가 닿는 자리)을 보고하고, lead가 고른다.
7. FU를 workspace마다로(결정 8). `App.fullscreen`을 `Workspace.fullscreen`으로 옮기고, workspace를 옮길 때 격자가 그
   workspace의 값으로 다시 선다. FU 체인의 판정 여덟은 workspace 하나라 그대로다(확인 5). app workspace는 늘 chrome 없음.
8. 합성(결정 9). app workspace가 앞이면 그 프레임은 검정으로 채우고 toplevel의 버퍼를 `k = min(fbW / w, fbH / h)`(1 이상)
   배 가장 가까운 픽셀로 늘려 가운데(`((fbW - kw)/2, (fbH - kh)/2)`)에 옮긴다. `wl_shm`의 ARGB8888 · XRGB8888 둘만 받는다.
   버퍼는 commit 때 복사하지 않고 그릴 때 읽은 뒤 `release`한다.
9. frame 콜백(결정 10). 그 commit을 담은 프레임을 `present`한 뒤 `done(ms)`. 앞이 아닌 workspace의 toplevel에는 안 보낸다.
10. 입력(결정 11). app workspace가 앞이면: `chord`가 표의 것(workspace 번호 · `Cmd+T` · `Cmd+Ctrl+F` · `Cmd+Q` 등)이면
    compositor가 먹는다. 아니면 `wl_keyboard.key`(evdev 코드)와 바뀐 modifier(`modifiers`)를 보낸다. Cmd는 Super(0x40)다.
    포커스가 들어갈 때 `enter`(눌린 키 목록 빈 배열), 나갈 때 `leave`. 셸 pane에서 표에 없는 Cmd 조합은 삼킨다 —
    `input_test` 622 · 626행과 748행 부근의 단언을 "빈 바이트"로 고친다(이유를 주석에).
11. `Cmd+Q`(결정 12). R-KEY-1 표에 넣는다. app workspace에서: `xdg_toplevel.close` + `xdg_wm_base.ping`, 2초 타이머. pong이나
    끝이 오면 타이머를 버린다. 2초가 지나면 `wl_client_get_credentials`의 pid에 SIGKILL. 셸 pane의 `Cmd+Q`는 삼킨다.
    타이머는 `poll`의 시간 제한으로 건다(지금 바퀴의 다른 타이머와 같은 방법을 따른다).
12. workspace가 아홉이면 새 toplevel에 `close`를 보내고 `wl> toplevel refused` 한 줄.

## 새 체인 `wayland`

`wayland/check.sh`, `check.sh`의 `CHAINS`에 더한다. 부팅 하나(`-nic none`, 디스크 없음). 판정:

1. `wl> listen path=/run/user/…/wayland-0`. 셸의 `echo $WAYLAND_DISPLAY $XDG_RUNTIME_DIR`.
2. 셸에서 `tars-wl-test --color 3366CC > /tmp/wl.log &` → `wl> client` · `wl> toplevel id=… ws=2` · `pane>`(또는 바뀐 덤프)가
   `ws=2/2`. screendump의 화면 가운데 픽셀이 `3366CC`, 네 모서리가 검정(DY의 `screendump` · `ppm_ink`를 쓴다).
3. 키: `sendkey a` → `wl> key code=30 state=1 to=…`. 그 뒤 `Cmd+1`(셸로) → `cat /tmp/wl.log`에 `wl-test> key code=30 state=1`.
4. `Cmd+2` → 다시 클라이언트 화면(가운데 색). `Cmd+1` → 셸(`pane>` 줄).
5. 셸에서 `Cmd+C` · `Cmd+Q`가 아무것도 안 친다(`$` 뒤의 `screen>` 줄이 그대로).
6. 보호: 셸에서 `kill -STOP <pid>` → 셸에 `echo alive`가 그려진다. `kill -CONT`.
7. `Cmd+2` → `Cmd+Q` → `wl-test> close` · `wl> gone`, workspace가 사라진다(`ws=1/1`).
8. `tars-wl-test --ignore-close &` → `Cmd+Q` → `wl> ping` → 2초 뒤 `wl> kill pid=…` · `wl> gone`.
9. NUL 음성 · `verify> mismatch` 0(루트 게이트가 본다 — 체인 뒤 lead가 `grep … 'terminal: verify>'`로도 본다).

## 할 일

1. (A) 의존 · vendor xml · Dockerfile · 스캐너. terminal이 링크만 하고(서버는 아직 안 띄움) 기존 동작 그대로.
2. (A) `tars-wl-test`, initrd에 싣기. 판정: 컨테이너 빌드, initrd 목록, 기존 체인 하나(`terminal`)가 그대로.
3. (B) `Workspace` 모양 보고(확정 6) → lead가 고름.
4. (B) 서버 · 소켓 · global · surface · xdg · 합성 · frame · app workspace · FU를 workspace마다로.
5. (B) 순수 부분의 호스트 검사.
6. (C) 입력 갈래 · 키맵 · Cmd 삼킴(`input_test`).
7. (C) `Cmd+Q` · ping · SIGKILL.
8. (C) 체인 `wayland`, `CHAINS`, 도움말(`docs/help/desk.md`에 `Cmd+Q`와 "셸에서 Cmd+글자는 아무것도 안 친다").
9. lead: 체인 `wayland` · `fullscreen` · `pane` · `terminal` · `hangul`, verify 줄 grep, 루트 게이트(35체인).

## 판정

- 호스트 검사 통과, 체인 `wayland`(새) PASS, 기존 34 PASS, 루트 게이트 35/35, verify mismatch 0.

## 결과

(구현 뒤에 쓴다.)
