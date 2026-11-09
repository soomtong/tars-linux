# TARS Fullscreen — Design

접두사: FU

Date: 2026-11-09
Status: 2판(단축키를 Cmd+Ctrl+F로 — 사용자 2026-11-09). 닫힘(2026-11-09). FU-M0 — 결정 4의 Ctrl 갈래는 "한 조합만 가로챈다"로 갔다(plan 결과 4). FU-M1 — 결정 7의 printf 둘은 `sh -c`와 `trap : INT`로 감쌌고 끄기 뒤에 화면 지우기를 붙였다(plan 결과 1 · 2).

계기: 사용자(2026-11-09, BB 데모 `demo-fakesteak-20261109`를 맥북 에어 실기에서 본 뒤): "Full screen mode 필요하겠다". 이어서 사용자가
정한 것(2026-11-09): 감추는 것은 여백과 상태 줄 둘 다, 켜는 길은 `Cmd+Ctrl+F`(macOS의 전체 화면 키, 사용자가 `Cmd+Shift+F`에서 고쳤다)와 `tars.conf`의 `fullscreen=on|off`, 납품 묶음은 xterm의
`CSI 10 ; Ps t`를 terminal이 직접 알아듣는 길. 순서는 manifest 포맷(MF, 닫힘) → 전체 화면 → 0.2.0이다.

관련 문서: HS design(`2026-11-04-tars-hidpi-scale-design.md` — 화면 키 하나가 init → argv → terminal로 가는 선례), WP design(패널 ·
`applyLayout`), IS design(상태 줄), BB design 결정 6(납품 묶음의 autorun 조각).

## 한 줄 요약

전체 화면은 격자 둘레 여백과 아래 상태 줄을 없애고 격자를 화면 끝까지 넓힌다. `Cmd+Ctrl+F`가 실행 중에 켜고 끄며(셸은 그대로),
`tars.conf`의 `fullscreen=`은 부팅 때의 시작 상태다. 패널 안의 프로그램은 xterm의 `CSI 10;1 t`(켜기) · `10;0 t`(끄기) · `10;2 t`(바꾸기)로
요청할 수 있고, 납품 묶음의 autorun 조각이 그것을 쓴다.

## 확인 (2026-11-09, HEAD `784a19e`)

1. 여백은 comptime 상수 `GRID_X` · `GRID_Y` = 20(`terminal/src/main.zig:43-44`), 코드에서 쓰는 줄 19(정의 둘 포함, 주석 줄 5는 빼고). 격자 크기는 `openScreen`이 한 번 정한다:
   `cols = (fb.width - 2*GRID_X) / CELL_W`, `rows = (fb.height - 2*GRID_Y) / ROW_HEIGHT`(`main.zig:3637-3638`). 1280×800(QEMU)이면 155×47,
   1366×768(맥북 에어 11")이면 165×45. 여백을 없애면 160×50 · 170×48.
2. 상태 줄은 격자 줄을 쓰지 않고 아래 여백 안에 그린다(`drawStatus` `main.zig:262-300`, `renderStatusBand` `:608`). 여백이 없으면 그릴 자리가
   없다. copy mode의 검색 입력(`drawPrompt` `:213`)은 패널의 마지막 줄 위에 덮어 그리므로 격자 안이다 — 전체 화면과 상관없다.
3. 실행 중 다시 배치하는 길이 이미 있다: `applyLayout(ws, whole)`(`main.zig:1715`)이 사각형이 바뀐 패널마다 `vt.Screen.resize`와 `pty.resize`를
   짝으로 부른다(분할 · 닫기가 쓴다). `self.whole`(`:3814`)을 바꾸고 워크스페이스마다 부르면 셸을 닫지 않고 격자가 커지고 준다.
4. 좌표를 격자로 바꾸는 쪽도 같은 상수를 쓴다: `paneOrigin`(`:1598`), 포인터의 셀 찾기(`:2591-2597`, `:3011-3012`), 상태 줄 · 띠.
5. 화면 키의 선례는 `display_scale`(HS-M0). 지나가는 자리: `shared/screen_args.zig`의 `Slot` · `Args` · `encode`, `init/src/config.zig`(파싱 ·
   기본 파일 · 로그), `init/src/reload.zig`의 `term` 갈래(바꾸면 `reload terminal`), `init/src/main.zig`(argv · reload 로그).
6. Cmd 분기(`chord`, `terminal/src/input.zig:1281`)는 Shift · Option 갈래만 따로 본다 — 표에 없는 조합은 null이고 Shift · Option 없는 표로
   떨어지지 않는다. Ctrl 갈래는 없어서 `Cmd+Ctrl+F`는 지금 Cmd 표(F 없음)에서 null이 되고 평소 번역으로 Ctrl+F(0x06)가 셸에 간다.
7. ghostty lib-vt의 XTWINOPS(`CSI … t`)는 8 · 14 · 16 · 18 · 19 · 21 · 22 · 23만 handler로 넘긴다(`terminal/ghostty-src/src/terminal/stream.zig`).
   10(전체 화면)은 경고만 찍고 버린다. 그러니 terminal이 lib-vt에 넣기 전에 직접 훑어야 한다. 패널 출력은 `pane.screen.feed(out)`(`main.zig:4538`)
   한 자리로 들어간다.
8. 기본 배경색은 `#102030`(`vt.zig:559`)으로 여백 색 `MARGIN_COLOR`와 같다.
9. 격자 크기를 보는 게이트는 `terminal: grid WxH (fb …)` 줄(`machine/check.sh:258` 등)과 render 체인의 `pixel>` 좌표다. 둘 다 여백 20px를
   전제한다 — 기본값이 꺼짐이면 그대로 맞다.

## 결정

1. 전체 화면이면 여백이 없고 상태 줄을 그리지 않는다. 격자는 `cols = fb.width / CELL_W`, `rows = fb.height / ROW_HEIGHT`. 나누어떨어지지 않고
   남는 픽셀(가로 < 8, 세로 < 16)은 둘레에 반씩 나눈다 — 격자를 가운데 둔다(1366이면 왼쪽 3 · 오른쪽 3). 남는 자리는 지금처럼
   `MARGIN_COLOR`로 칠한다. 기본 배경과 같아 이음매가 안 보이고, 검은 배경 프로그램에서는 몇 픽셀의 띠가 보인다. 그것은 받아들인다.
2. 여백은 상태가 된다. `GRID_X` · `GRID_Y`를 App의 값 하나(`origin`, 격자 왼쪽 위의 픽셀)로 바꾸고 쓰는 자리에 넘긴다. 꺼짐이면 (20, 20)이라
   지금과 픽셀까지 같다 — 기존 게이트(확인 9)는 손대지 않는다.
3. 켜고 끄기는 하나의 함수(`setFullscreen(on)`)다. `origin` · `cols` · `rows` · `whole`을 다시 셈하고, 모든 워크스페이스에 `applyLayout`을
   부르고, 다음 프레임을 통째로 그린다. 같은 상태로의 요청은 아무것도 안 한다. 바뀔 때마다 한 줄을 찍는다:
   `terminal: fullscreen> on grid 160x50 origin 0,0`(게이트와 사람이 같은 줄을 본다).
4. 길은 셋이고 모두 3의 함수를 부른다.
   - `Cmd+Ctrl+F`(PC 키보드는 `Alt+Ctrl+F`): 바꾸기. Cmd 분기에 Shift · Option과 같은 규칙의 Ctrl 갈래를 하나 두고 F 한 줄
     (`.pane = .fullscreen_toggle` 꼴). 표에 없는 `Cmd+Ctrl` 조합은 null — 평소 번역으로 흘러 지금과 같은 바이트가 나간다(input_test가 못 박는다).
   - `tars.conf`의 `fullscreen=on|off`(기본 `off`): 부팅 때의 시작 상태. 화면 키라 `reload terminal` 갈래다(확인 5). argv의 새 칸 하나.
     실행 중에 단축키로 바꾼 상태는 파일에 쓰지 않는다 — 파일은 사람이 고치는 것이다.
   - 패널 출력의 `CSI 10 ; Ps t`: Ps 0 끄기 · 1 켜기 · 2 바꾸기(xterm과 같은 뜻). 그 밖의 Ps와 다른 매개변수 수는 무시한다.
5. 시퀀스 훑기는 패널마다 작은 상태 기계다(`terminal/src/winops.zig`, 순수 · 호스트 검사). read 경계에서 잘린 시퀀스를 이어 읽는다.
   바이트를 바꾸지도 빼지도 않고 lib-vt에 그대로 넘긴다 — lib-vt는 지금처럼 버린다. 그러니 다른 시퀀스의 해석은 한 바이트도 안 바뀐다.
   어느 패널이든 요청할 수 있다. 전체 화면은 화면을 가리지 않고 넓힐 뿐이라 막을 이유가 없다.
6. 상태 줄이 안 보이는 동안 `status>` 로그 줄(상태 글자)은 그대로 찍는다 — 그것은 화면이 아니라 상태다. 띠의 잉크 수는 0이 된다.
7. 납품 묶음: fakesteak의 autorun 조각 둘(`devlayer/files/fakesteak/etc/`)이 실행 직전에 `printf '\033[10;1t'`, 끝난 뒤 `printf '\033[10;0t'`.
   Ctrl+C로 셸에 돌아오면 여백과 상태 줄이 돌아온다 — 기기를 고치러 온 사람이 상태 줄을 본다(BB 결정 5의 정신).
8. 배율(HS)과 겹친다. 배율이 1보다 크면 `fb`는 논리 크기이고, 전체 화면의 격자도 그 논리 크기로 센다. 따로 할 일이 없다.

## 비목표

- 전체 화면에서 상태를 잠깐 띄우는 것(한/영을 바꿀 때의 토스트 등). 필요하면 나중에 연다.
- 단축키로 바꾼 상태를 `tars.conf`에 기억하는 것.
- 패널이 요청하는 다른 XTWINOPS(창 이동 · 아이콘화 · 크기 바꾸기 `CSI 8 t`).
- 여백 크기를 고르는 키(`margin=N`). 켜짐과 꺼짐 둘뿐이다.

## 위험

1. 쓰는 자리 중 하나라도 상수를 그대로 쓰면 전체 화면에서만 어긋난다(포인터가 한 칸 밀리는 식). 상수를 지워서 컴파일러가 모든 자리를 찾게 한다.
2. 부분 갱신(DR-M2)은 지난 프레임과의 차이만 그린다. 켜고 끈 프레임은 반드시 통째여야 한다 — 옛 여백 자리에 지난 글자가 남는다.
3. 시퀀스 훑기가 바이트를 잘못 세면 다른 프로그램에서 전체 화면이 저절로 켜질 수 있다. 상태 기계의 단위 검사가 잘린 입력 · 비슷한 시퀀스
   (`CSI 10 t`, `CSI 1;10 t`, `CSI 10;1 q`)를 덮는다.

## Milestone

- FU-M0: 결정 1~4의 앞 둘(단축키 · `tars.conf`)과 6 · 8. 게이트는 체인 하나에 부팅 둘(`fullscreen=on`으로 띄워 `grid 160x50` · 상태 띠 잉크 0,
  꺼짐에서 단축키로 켜고 끄며 `fullscreen>` 줄 둘과 셸이 살아 있는지). 어느 체인에 붙일지는 plan이 정한다.
- FU-M1: 결정 4의 셋째 · 5 · 7. `winops` 단위 검사, 패널에서 `printf`로 켜고 끄는 부팅 하나, fakesteak 조각 · QEMU probe(BB-M1의 방식).
