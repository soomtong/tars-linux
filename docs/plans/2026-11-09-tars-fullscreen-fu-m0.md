# FU-M0 — 전체 화면: Cmd+Ctrl+F와 tars.conf의 fullscreen=

Date: 2026-11-09
Design: `docs/specs/2026-11-09-tars-fullscreen-design.md`(2판, 결정 1~4의 앞 둘 · 6 · 8)
Status: 끝났다(2026-11-09)

## 착수 전에 확정한 것

plan을 쓰며 읽은 것(HEAD `52ac714`).

1. `GRID_X` · `GRID_Y`를 쓰는 코드 줄(정의 둘 빼고 17): `drawStatus` · `renderStatusBand` · `paintBand` · `dumpStatus`의 `grid_bottom`(4),
   `drawRun`의 x(2), `paneOrigin`(2), `cellAt`(3, `main.zig:2595-2597`), `gridCellClamped`(2, `:3011-3012`), `openScreen`의 cols · rows(2),
   `verifyClips` 둘의 `.top`(2, `:4868` · `:4958`). 모두 자유 함수이거나 App 메서드다. 자유 함수는 `Status`나 인자로 받는다.
2. 상태 띠는 `renderStatusBand`가 격자 아래를 `MARGIN_COLOR`로 지우고 `drawStatus`를 부른다. `drawStatus`는 아래 여백이 16px보다 좁으면
   이미 아무것도 안 그린다(`main.zig:289`) — 전체 화면에서는 그 자리를 명시적으로 끈다(설계 결정 1 · 6, 남는 픽셀이 16을 넘는 화면은 없지만
   기대지 않는다).
3. `Cmd` 분기(`input.zig:1281` `chord`)에 Shift · Option 갈래가 있고 Ctrl 갈래는 없다. 패널 동작 enum은 `input.zig:373` `Pane`.
4. 화면 키의 길: `shared/screen_args.zig` `Slot`(지금 13까지, `ARGC = 14`) · `Args` · `encode` · `decode`, `init/src/config.zig`(파싱 · 견본 ·
   필드), `init/src/reload.zig` `groupOf`의 `term` 목록, `init/src/main.zig`의 부팅 로그(`:1320`) · reload 로그(`:734`) · argv(`:1547`) · 갱신(`:719`).
   on/off 값의 선례는 `esc_latin`(`config.zig:867` `EscLatin`).
5. 게이트 선례: `hidpi/check.sh`(화면 크기 · screendump), `pane/check.sh`의 `apple_disk`(`keyboard=apple` 디스크로 `meta_l` = Cmd, `gate_lib.sh:323`).
   QEMU 화면 1280×800 — 꺼짐 155×47, 켜짐 160×50(남는 픽셀 0). monitor 포트 45505(예약 범위 45455-45599, 45504까지 쓰였다).

## Task 1 — 여백을 상태로(동작 변화 없음)

- `GRID_X` · `GRID_Y`를 지우고 파일 수준 `var grid_origin: Origin = MARGIN`(`MARGIN` = 20,20)으로. `Origin`은 이미 있는 것(`main.zig:1592`).
  (구현하며 고침) 처음 적은 "`Status` 필드 · 인자로 나르기"는 `paneOrigin`을 부르는 자유 함수 13곳의 서명을 줄줄이 바꾼다. 같은 이유로
  파일 수준 값인 선례(`touchpad_screen`, "여는 자리가 여럿이라 인자로 나르지 않는다")가 있고 terminal에는 스레드가 없다. 그래서 17곳은
  이름만 바뀌고 서명은 그대로다. 상수가 사라졌으므로 빠뜨린 자리는 여전히 컴파일러가 찾는다. 상태 띠를 감추는 표시는 `Status.hidden`.
- (구현하며 찾음) `drm.Framebuffer.fillRect`가 화면 경계에서 자른다. 마지막 열의 폭 2 preedit은 커서 사각형(`main.zig:513` · `:575`)과
  `drawPrompt`의 조합 글자(`:254`)를 격자 오른쪽으로 반 칸 내미는데, 지금은 20px 여백이 받아 주고 전체 화면(1280이면 오른쪽 0px)에서는
  다음 픽셀 줄을 덮어쓰거나 맨 아래 줄에서 버퍼 밖에 쓴다. `drawGlyph`는 이미 자른다 — 부르는 쪽마다 검사를 흩지 않고 칠하는 함수 하나에서 자른다.
- `openScreen`이 `geometry(fb, fullscreen) → { origin, cols, rows }`(순수 함수, 아래 Task 4가 검사)로 정한다. 이 Task에서는 늘 꺼짐.
- 판정: `zig build` · `zig build test`, 그리고 render · pane · hidpi 체인(픽셀까지 지금과 같아야 한다).

## Task 2 — setFullscreen

- `fn setFullscreen(self, on)`: 같으면 반환. `geometry`로 다시 셈 → `self.cols` · `rows` · `origin` · `whole` → 모든 워크스페이스에 `applyLayout`
  → 프레임을 통째로(부분 갱신의 기준을 버린다 — 설계 위험 2) → `terminal: fullscreen> on grid 160x50 origin 0,0`.
- 상태 띠: `Status.hidden = self.fullscreen`이면 `renderStatusBand`가 그리지 않는다. 남는 둘레는 통째 프레임의 `fill(MARGIN_COLOR)`이 칠한다.
  `status>` 줄은 그대로 찍는다(설계 결정 6).
- 포인터: `cellAt` · `gridCellClamped`가 origin을 받으므로 따로 할 일이 없다. 화살표는 화면 픽셀 좌표라 그대로.

## Task 3 — 켜는 길 둘

- input: `Pane`에 `fullscreen_toggle`. `chord`의 Meta 분기에서 Shift · Option 갈래 옆에 Ctrl 갈래 — `KEY_F`만, 나머지 null(설계 결정 4).
  copy mode 안에서는 copy 분기가 먼저라 닿지 않는다(다른 패널 명령과 같다).
- `shared/screen_args.zig`: `Fullscreen = enum { off, on }`(+`arg()`), `Slot.fullscreen = 14`, `ARGC = 15`, `Args.fullscreen`, encode · decode.
- init: `config.zig` 필드 `fullscreen: Fullscreen = .off`, 파싱(모르는 값은 로그와 함께 그대로), 견본에 두 줄(`# fullscreen: off | on` · `fullscreen=off`),
  부팅 로그 · reload 로그 끝에 `fullscreen=`, `reload.zig`의 `term` 목록, `main.zig`의 argv · 갱신.
- terminal: argv의 값으로 `openScreen` 뒤 첫 프레임 전에 상태를 정한다(켜짐이면 처음부터 전체 화면 — 꺼진 프레임을 한 번 그리지 않는다).
- 안내: `docs/help/desk.md`의 단축키 표에 한 줄, 설정 절에 `fullscreen=on`과 `reload terminal`. `docs/help/config.md`의 화면 쪽 키 목록.

## Task 4 — 단위 검사

- `terminal/src/main.zig`의 `geometry`를 순수 함수로 두기 어려우면 새 파일 `terminal/src/geometry.zig` + `geometry_test.zig`(`zig build test`):
  1280×800 꺼짐 (20,20) 155×47 · 켜짐 (0,0) 160×50, 1366×768 꺼짐 165×45 · 켜짐 (3,0) 170×48, 1440×900(배율 2의 논리) 켜짐 (0,2) 180×56.
- `input_test`: `Cmd+Ctrl+F` → `fullscreen_toggle`, `Cmd+Ctrl+A`가 이 변경 전과 같은 결과(설계 결정 4의 "지금과 같은 바이트" — 먼저 HEAD에서 무엇이
  나오는지 재서 기대값으로 적는다), copy mode 안의 `Cmd+Ctrl+F`.
- `config_test` · `config_edit_test` · `screen_args_test` · `reload_test`: 새 키의 파싱 · 거절(`fullscreen=yes`) · 왕복 · 갈래.

## Task 5 — 게이트 `fullscreen/check.sh`(체인 FU-M0)

부팅 둘, monitor 45505, 화면 1280×800.

- 부팅 A: 설정 디스크 `keyboard=apple` + `fullscreen=on`. `tars-init: config … fullscreen=on`, `terminal: grid 160x50 (fb 1280x800)`, `fullscreen> on`
  한 줄. 셸에서 `stty size` → `50 160`. screendump의 맨 위 왼쪽 8×16 상자에 프롬프트의 잉크가 있다(여백이 없다), 상태 띠 잉크 0.
- 부팅 B: 설정 디스크 `keyboard=apple`만. `grid 155x47` → `type_keys meta_l-ctrl-f` → `fullscreen> on grid 160x50 origin 0,0` → `stty size` `50 160`
  → 다시 `meta_l-ctrl-f` → `fullscreen> off grid 155x47 origin 20,20` → `stty size` `47 155`. 셸의 pid가 처음과 같다(셸을 닫지 않았다).
  그리고 `tars-config set fullscreen=on` · `reload terminal` 뒤 새 terminal이 `grid 160x50`.
- `check.sh`의 `CHAINS`에 `"FU-M0:./fullscreen/check.sh"`.
- 판정: 체인 단독 2회, 그다음 루트 게이트(render · pane · hidpi가 Task 1의 판정이다).

## 비목표

design의 비목표, 그리고 FU-M1의 것(시퀀스 · fakesteak 조각).

## 결과

lead 직접. FU 체인 단독 2회 PASS(2분 49초 · 2분 52초), 루트 게이트 32/32(prebuild 357초 + lanes 1,505초, 33분 18초, 잘린 줄 0,
`out/gate-logs/20261109-081300`). render · pane · hidpi가 그 안에서 지났다 — Task 1의 "꺼짐이면 픽셀까지 지금과 같다".

plan과 다른 자리(구현하며 정한 것):

1. 원점은 `Status` · 인자가 아니라 파일 수준 `var grid_origin`(Task 1에 고쳐 적었다, 선례 `touchpad_screen`). 17곳은 이름만 바뀌었다.
2. `drm.Framebuffer.fillRect`가 화면 경계에서 자른다(`geometry.clip`). 마지막 열의 폭 2 커서 · 조합 글자가 격자 오른쪽으로 반 칸 나가는데,
   전체 화면(1280이면 오른쪽 여백 0)에서는 다음 픽셀 줄이나 버퍼 밖에 쓴다. FU 전에는 20px 여백이 받아 줬다.
3. 격자 크기로 부팅 때 한 번 잡던 버퍼 넷(`screen_line_buf` · `dirty_rows` · verify의 `cell_buf` · `starts_buf`)을 전체 화면 크기(`App.cap`)로
   잡는다. 그대로면 켜는 순간 155×47의 버퍼에 160×50을 쓴다. 넷 다 `[0..rows]`로 잘라 쓰거나 용량으로만 써서 크게 잡아도 뜻이 같다.
4. `Cmd+Ctrl+F`는 Shift · Option 같은 갈래가 아니라 그 한 조합만 가로챈다. 갈래로 두면 지금 Cmd 표로 가는 `Cmd+Ctrl+←`(0x01) 같은
   조합이 null로 바뀐다 — design 2판 결정 4의 "지금과 같은 바이트"는 갈래를 두면 틀린 말이었다. input_test가 0x01 · Ctrl+F의 0x06을 못 박는다.
5. ARGC 14 → 15에 손으로 14칸 적은 argv 배열 일곱이 걸렸다(init `main.zig` 둘, `WIFI` · `DBUS` · `BLUETOOTHD` · `DHCPCD` · `CHRONYD`).
   컨테이너의 `zig build test`는 init 실행 파일을 안 지어 못 봤고 `make quick`의 크로스 빌드가 잡았다.
6. 셸이 아는 창 크기는 `stty size`가 아니라 fish의 `$LINES` · `$COLUMNS` — initrd에 stty가 없다(체인 1회차가 `Unknown command: stty`로 빨갰다).
   `tars-config set`의 답은 키가 파일에 없으면 `fullscreen: off (default) -> on`(2회차가 패턴에서 빨갰다).
7. 상태 띠를 감추는 검사는 `renderStatusBand` 한 곳 — 실제 경로(`paintBand`)와 verify의 그림자(`renderOverlay`)가 함께 지난다.

남는 것: FU-M1(패널의 `CSI 10 ; Ps t` · fakesteak 조각 · probe).
