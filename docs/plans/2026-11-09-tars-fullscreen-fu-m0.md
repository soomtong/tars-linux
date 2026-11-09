# FU-M0 — 전체 화면: Cmd+Ctrl+F와 tars.conf의 fullscreen=

Date: 2026-11-09
Design: `docs/specs/2026-11-09-tars-fullscreen-design.md`(2판, 결정 1~4의 앞 둘 · 6 · 8)
Status: 착수 전

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

- `GRID_X` · `GRID_Y`를 지우고 이미 있는 `Origin`(`main.zig:1592`, `paneOrigin`의 반환형)을 격자 원점으로도 쓴다. App 필드 `origin`,
  상수 `MARGIN: Origin = .{ .x = 20, .y = 20 }`. 상수를 지웠으므로 컴파일러가 확인 1의 자리를 모두 찾는다.
- `Status`에 `origin`과 `hidden: bool`을 더한다. `grid_bottom`은 `st.origin.y + rows * ROW_HEIGHT`.
- `drawRun` · `paneOrigin` · `cellAt` · `gridCellClamped`는 origin을 인자로.
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

(구현 뒤 적는다)
