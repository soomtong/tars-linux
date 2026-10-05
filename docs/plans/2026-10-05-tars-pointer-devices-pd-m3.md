# PD-M3 — 노트북 터치패드: 커널의 세 경로, 번역 층, uinput으로 되감는 부팅 B

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-pointer-devices-design.md`
Status: 끝났다(2026-10-05). 실측은 맨 아래 "PD-M3이 실측한 것" 절에 있다. 이것으로 PD가 닫혔다 — design "닫을 때"는 lead가 같은 날 했다.

## 누가 무엇을 하나

design 결정 11. Task 0~8은 구현 서브에이전트(Opus)가 main 작업 트리에서 직접 편집한다. Task 1-0(되접기 commit)과
Task 9(루트 게이트 2회 · 실측 절 · commit · 닫기)는 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` ·
`git diff | rg '^-'` · 각 Task의 명령 출력을 그대로 보고한다. mutation(Task 8)도 구현자가 돌린다. 이 plan의 "확정한 것"
절과 "실측한 것" 절은 구현자가 고치지 않는다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/pdm3/new/`)에 먼저 넣었고, 아래의 새 파일 본문과 `old_string` ·
`new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/pdm3/render.py`). 기준 사본은 `/tmp/run/pdm3/base/`다. 구현자는
코드를 새로 짓지 않는다. 새 파일은 사본을 `cp`하고, 편집은 Edit 도구에 글자 그대로 넣고, 각 Task 끝에서 사본과 `diff`해
같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다. plan의 글자와 사본이 서로 다르다고 보이면 고치지
말고 그 자리를 보고한다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `kernel/.config` | 터치패드의 세 경로와 uinput(확정 4) — `scripts/config`로 적고 `olddefconfig`로 되접는다 | +261 −16 |
| `terminal/src/touchpad.zig` | 새 파일 — 상태 기계 `Touchpad` · `Setup` · `Axis` · `Screen` · `Frames` · `modeOf` | +431 |
| `terminal/src/touchpad_test.zig` | 새 파일 — 검사 1~10 | +440 |
| `terminal/build.zig` | `touchpad_test` 등록 | +17 |
| `terminal/src/main.zig` | 편집 아홉 — import · `PointerDev.decoder` · `PointerDev.feed` · `touchpad_screen` · `tryOpenPointer`의 갈래 · `readPad` · `readAbs` · `drainPointer`의 `Frames` 루프 · 처음 훑기 앞의 화면 값 | +103 −16 |
| `pointer/replay/build.zig` | 새 파일 — 되감기 도구의 빌드(x86_64-linux-musl, 정적) | +26 |
| `pointer/replay/main.zig` | 새 파일 — `tp-replay`(uinput 터치패드와 명령 다섯) | +330 |
| `pointer/check.sh` | 편집 일곱 — 머리 주석 · 도구 빌드와 포트 · 표식 · 검사 19와 부팅 A의 `i8042.noaux` · 부팅 B와 검사 20~25 | +311 −5 |
| `check.sh` | 체인 설명 문단과 `CHAINS`의 `"PD-M2:…"` → `"PD-M3:…"` | +5 −2 |
| `install/check.sh` | 조건부(Task 7-3) — 부팅 7의 기다림이 500ms 아래일 때만 `delay_use` 3 → 4와 주석 둘 | +9 −3 |

`pointer.zig`는 안 고친다 — 공통 출력(`Frame` · `Buttons`)과 분류(`classify`)가 PD-M0부터 터치패드를 이미 안다.
`.gitignore`와 루트 `check.sh`의 `clean()`도 안 고친다 — 되감기 도구의 산출물과 캐시를 `out/` 아래에 둔다(확정 7).

`docs/guides/lessons.md` · design `Status:` · `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md`는 구현자가 안 고친다. 이 milestone이
서브프로젝트를 닫으므로 lead가 Task 9-5에서 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드 · 테스트 · 체인은 언제나 컨테이너에서 한다 — 호스트
`PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다. 구현자의 측정용 파일은 `/tmp/run/pdm3/impl/` 아래에 둔다.
`/tmp/run/pdm3/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(PD-M1 plan
확정 11 · PD-M2 구현 중 lead 실측). 컨테이너는 언제나 하나씩 돌린다. 이 milestone은 커널을 다시 빌드하므로 그 한 판이
특히 무겁다.

## 이 milestone이 끝나면

- 커널이 노트북 터치패드의 세 경로를 안다. PS/2(psmouse — Synaptics · Elantech · ALPS · Focaltech · TrackPoint), SMBus(RMI4 ·
  Elan), I2C-HID(hid-multitouch와 그 밑의 LPSS · DesignWare I2C · pinctrl, AMD 쪽, Intel THC의 QuickI2C)다. 게이트는 그것을
  심볼 · 커널의 장치 표 · 게스트의 드라이버 등록 셋으로 본다(design 결정 9).
- QEMU pc의 모든 체인에 PS/2 마우스가 하나 생기고 terminal이 그것을 `kind=mouse`로 연다. 화면은 안 바뀐다 — 움직이기
  전에는 화살표를 안 그린다(design 결정 4의 보이는 조건 2).
- terminal이 터치패드를 연다. 한 손가락으로 밀면 포인터가 움직이고(패드 가로 전체 = 화면 가로 전체), 짧게 두드리면
  왼쪽 클릭이고(180ms · 축 범위의 2%), 두 손가락을 세로로 밀면 휠이다(손가락을 따라 내용이 움직이는 쪽). clickpad의
  물리 버튼은 그대로 통과하고, 누른 채 다른 손가락으로 끌 수 있다. 그 아래(`Pointer` · `Gesture` · 화살표 · 드래그
  선택)는 PD-M0~M2 그대로다.
- 게이트 전용 되감기 도구 `tp-replay`(`pointer/replay/`)가 `/dev/uinput`으로 터치패드를 만들어 그 손동작을 되감는다.
  `pointer/check.sh`가 부팅 둘이 되고 검사 19~25가 더해진다. 호스트 검사 `touchpad_test`가 는다. 체인 수는 그대로
  열아홉이다.
- 이 milestone이 끝나면 사용자의 요청 2(터치패드)가 QEMU 안에서 볼 수 있는 데까지 끝나고 PD 서브프로젝트가 닫힌다.
  실기 확인(로그의 `kind=` · 출발값 셋 · 스크롤 방향)은 그 뒤 사람이 한다.

로그 줄(정본 — `main.zig`와 `pointer/check.sh`가 이 글자를 쓴다). 새 모양은 터치패드의 `open` 줄 하나다. 마우스의 `open`
줄과 나머지는 PD-M2 그대로다.

```
terminal: pointer> open /dev/input/event4 kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad
terminal: pointer> skip /dev/input/event4 kind=touchpad error=axes name=…
terminal: pointer> open /dev/input/event2 kind=mouse shown=0 name=ImExPS/2 Generic Explorer Mouse
```

`slots`는 따라가는 접촉 칸의 수(`ABS_MT_SLOT`의 max + 1, 다섯에서 자른다)이고, `x` · `y`는 축의 min..max, `res`는 가로 ·
세로의 단위/mm다. 단일 터치 장치는 `slots=1`이다. `error=axes`는 분류는 터치패드인데 축을 못 읽었다는 뜻이고 정상
부팅에는 안 나온다. 실기에서 배율이 손에 안 맞으면 이 줄이 첫 단서다.

## 착수 전에 확정한 것

2026-10-05에 이 plan을 쓰며 코드와 커널 소스(`kernel/src/linux-6.18.42/`)를 읽어 정했고, VM이 빈 뒤 저장소 사본(`/tmp/run/pdm3/repo/`)에서 쟀다. 저장소의 작업 트리는 한 글자도 안 바뀌었다.

1. `touchpad.zig`의 상태 기계. 순수하다 — 시스템 콜이 없고 `pointer.zig` 하나만 import한다. 입력은 이벤트 하나와 그
   시각(`ev.time`을 마이크로초로)이고, 출력은 `Frames`(`Frame` 0~2개)다. 디코더는 `SYN_REPORT`에서만 판단한다.

   | 상태 | 무엇을 든다 | 어디서 바뀐다 |
   |---|---|---|
   | 접촉 칸(최대 5) | tracking id(-1이면 빔) · 마지막으로 알려진 자리 · 직전 `SYN_REPORT`의 자리 · 이번 묶음에 새로 닿았나 · 닿은 순번 | `ABS_MT_SLOT` · `ABS_MT_TRACKING_ID` · `ABS_MT_POSITION_X/Y`(단일 터치면 `ABS_X/Y`와 `BTN_TOUCH`) |
   | 손가락 수 | `BTN_TOOL_FINGER` ~ `QUINTTAP` 중 눌린 것 | `EV_KEY` |
   | 물리 버튼 | `BTN_LEFT` · `RIGHT` · `MIDDLE` | `EV_KEY` |
   | 세션 | 손가락이 0에서 늘어난 뒤 다시 0이 될 때까지. 탭 후보인가 · 시작 시각 · 시작 자리 · 시작한 접촉 | `SYN_REPORT` |
   | 나머지 | 픽셀로 바꾸고 남은 것(가로 · 세로 · 스크롤) | `SYN_REPORT` |

   `SYN_REPORT` 하나의 판단은 이렇다. 손가락 수는 "차 있는 칸의 수"와 "`BTN_TOOL_*`가 말하는 수" 중 큰 것이다(칸보다
   손가락을 더 세는 장치가 있다 — design 결정 8). 포인터를 움직일 접촉은 차 있는 칸 중 가장 늦게 닿은 것이다.

   | 조건(위에서부터) | 하는 일 |
   |---|---|
   | 물리 버튼이 눌렸다 | 가장 늦게 닿은 접촉의 변화량으로 이동. 스크롤로 안 간다 — 엄지로 누르고 검지로 끄는 동작 |
   | 손가락 하나 | 그 접촉의 변화량으로 이동 |
   | 손가락 둘 | 변화량이 있는 접촉들의 세로 변화 평균을 픽셀로 모아 휠 눈금으로. 이동은 없다 |
   | 그 밖(0 · 셋 이상) | 아무것도 안 한다. 셋 이상은 비목표 6이다 |

   새로 닿은 접촉은 그 묶음에 변화량을 안 낸다(직전 자리가 없다). 커널의 입력 core는 같은 값을 다시 보내지 않으므로
   손가락이 떨어졌다 같은 y에 다시 닿으면 y 이벤트가 안 온다 — 그래서 칸이 비어도 마지막 자리를 지우지 않는다(되감기
   도구의 `move 0 60`이 정확히 그 모양이고 `touchpad_test` 검사 2가 본다).

   탭은 세션이 끝나는 묶음에서 가린다. 세션 내내 손가락이 하나였고, 물리 버튼이 안 눌렸고, 시작한 접촉이 그대로이고
   그 접촉이 시작 자리에서 축 범위의 2%(가로 · 세로 각각) 안에 머물렀고, 길이가 180ms보다 짧으면 `Frame` 둘을 낸다 —
   왼쪽 버튼이 선 것과 버튼이 원래대로인 것. `Pointer.apply`가 그 둘을 차례로 받아 눌림 하나와 뗌 하나를 내므로 그 아래는
   마우스 클릭과 구별하지 않는다. 그 사이의 작은 움직임은 포인터를 그대로 움직인다.

   `Frame`은 무언가 바뀐 묶음에서만 낸다(이동 · 휠이 0이 아니거나 버튼이 직전에 낸 것과 다르다). 마우스 디코더는
   `SYN_REPORT`마다 내지만, 터치패드는 손가락만 대고 있는 묶음이 많아 그대로 내면 `at` 줄이 그만큼 는다.

   `SYN_DROPPED`를 받으면 다음 `SYN_REPORT`까지 버리고, 그 `SYN_REPORT`에서 모든 칸 · 손가락 수 · 물리 버튼을 비운다.
   직전에 낸 버튼이 눌린 채였으면 버튼을 놓는 `Frame` 하나를 낸다 — 버린 구간에 뗌이 있었으면 영영 눌린 채가 된다.
   아직 닿아 있는 손가락은 떨어졌다 다시 닿을 때까지 무시된다(`EVIOCGMTSLOTS`로 다시 맞추지 않는다, design 결정 8).

   단일 터치 장치(`ABS_MT_SLOT`이 없고 `ABS_X` · `ABS_Y`가 있다)는 칸 하나로 읽는다 — `BTN_TOUCH`나 `BTN_TOOL_*`가 서
   있으면 닿았다. MT 위치는 있는데 칸도 `ABS_X`도 없는 장치(프로토콜 A의 일부)는 `modeOf`가 null을 내고 `main.zig`가
   열지 않는다. 커널의 노트북 터치패드 드라이버는 전부 프로토콜 B다.

2. 상수와 배율. 셋 다 design 결정 8의 출발값이고, 실기에서 손으로 본 뒤 고친다(design 위험 3). 고치면 `touchpad_test`의
   기대값도 함께 고친다.

   | 상수 | 값 | 뜻 |
   |---|---|---|
   | `TAP_US` | 180000 | 탭으로 치는 접촉의 최대 길이. 179ms는 탭이고 180ms는 아니다(`touchpad_test` 검사 3) |
   | `TAP_SLOP_PERCENT` | 2 | 탭이 움직여도 되는 거리. 축 범위의 2%이고 그 값까지는 탭이다 |
   | 가로 배율 | 화면 가로 / 패드 가로 범위 | "패드 가로 전체 = 프레임버퍼 가로 전체" |
   | 세로 배율 | 가로 배율 × 가로 res / 세로 res | 두 축의 resolution이 다 있으면 같은 mm당 픽셀. 하나라도 0이면 가로와 같은 단위당 픽셀 |
   | 휠 눈금 | `WHEEL_ROWS` × `ROW_HEIGHT` = 48픽셀 | 두 손가락이 이만큼 움직이면 한 눈금(세 줄) |

   세로를 화면 세로에 맞추지 않는 이유. 패드는 대개 화면보다 가로가 길어서(1000 × 600 대 1280 × 800) 세로를 화면 세로에
   맞추면 같은 손가락 거리가 가로와 세로에서 다른 픽셀이 된다 — 대각선으로 밀면 화살표가 비스듬히 휜다. resolution이
   없는 장치는 단위가 정사각형이라고 본다. design은 resolution이 있는 경우만 적었다. 이것과 아래의 휠 눈금은 lead가
   정했다(2026-10-05).

   휠 눈금은 design의 "`ROW_HEIGHT`마다 한 줄"을 "`3 × ROW_HEIGHT`마다 한 눈금(세 줄)"으로 바꾼 것이다. `Frame.wheel`은
   눈금이고 `main.zig`가 눈금마다 `WHEEL_ROWS`(3)줄을 민다(PD-M1). 손가락 16픽셀마다 한 눈금을 내면 손가락보다 글자가 세
   배 빨리 간다. 줄 단위 스크롤을 `Frame`에 따로 싣는 안은 버렸다 — `Frame`과 PD-M1 · M2의 휠 배선(포인터 아래 패널 ·
   누른 채의 휠)을 다시 열어야 한다. 손가락과 글자는 평균으로 같은 거리를 가고, 글자가 세 줄씩 끊겨 움직인다.

   픽셀로 바꾼 나머지는 다음 묶음에 넘긴다. 10단위(12.8픽셀)씩 열 번 민 것과 100단위를 한 번 민 것이 같은 128픽셀이다.

3. `main.zig`의 배선. 편집 아홉이고, `PointerDev` · `tryOpenPointer` · `drainPointer`의 `feed` 자리 · `scanPointers` 앞에 건다.

   - `PointerDev.mouse`(마우스 디코더)를 `decoder`로 바꾼다. 태그가 `pointer.Kind`인 union이다 — `mouse` · `touchpad` ·
     `none`. `none`은 쓰지 않지만 `Kind`의 갈래를 그대로 두어 `classify`와 칸이 같은 이름을 쓴다. `PointerDev.feed`가 이벤트
     하나를 디코더에 먹이고 `touchpad.Frames`를 돌려준다. 마우스는 `?Frame`을 0개 또는 1개로 감싼다.
   - `tryOpenPointer`가 `kind == .none`만 건너뛴다. 터치패드면 `readPad`가 `EVIOCGABS`로 축을 읽는다 — MT면
     `ABS_MT_POSITION_X` · `Y` · `ABS_MT_SLOT`(max + 1이 칸 수, value가 지금 칸), 단일 터치면 `ABS_X` · `Y`. 하나라도
     실패하면 `skip … kind=touchpad error=axes`다. `open` 줄은 위의 정본이다.
   - 배율에 쓰는 화면 값은 파일 하나의 `var touchpad_screen`이다. `pointer_drawn`과 같은 이유다 — 장치를 여는 자리(처음
     훑기 · uevent)가 여럿이라 인자로 나르면 `scanPointers` · `drainUevents`의 시그니처가 함께 바뀐다. 프레임버퍼를 연 뒤
     처음 훑기 바로 앞에서 정한다.
   - `drainPointer`가 이벤트마다 `Frame` 여럿을 차례로 `Pointer.apply`에 넣는다. 탭의 누름과 뗌이 한 이벤트에서 나오므로
     PD-M2가 만든 전이 칸(`edges`)에 둘이 순서대로 담긴다 — 그래서 탭이 `Gesture`에서 클릭(`press` · `release drag=0`)이
     된다.

   편집 E8(`drainPointer`)의 `old_string`은 PD-M2가 더한 전이 칸의 줄들을 문맥으로 문다. 루프 본문을 한 단계 안으로
   들이기 때문이다. 나머지 여덟은 PD-M2가 안 건드린 자리다. 앵커는 PD-M2 commit 뒤의 트리에서 다시 확인했다(확정 11).

4. 커널 심볼. design 결정 9의 세 경로를 Kconfig에서 하나씩 확인했다. design의 목록에서 고친 것이 넷이고, 넷 다 lead가
   정했다(2026-10-05).

   - `MOUSE_PS2_ELANTECH`는 기본값이 없다(`drivers/input/mouse/Kconfig` — `default` 줄이 없고 도움말이 "If unsure, say
     N"이다). design은 "하위 프로토콜은 기본값으로 따라온다"였다. 명시로 켠다. `MOUSE_PS2_ELANTECH_SMBUS`는 그것에
     기대므로 같이 따라온다.
   - RMI4의 하위 기능(`F03` · `F11` · `F12` · `F30` · `F3A`)도 기본값이 없다. design은 `F11` · `F12` · `F30`이었고 둘을
     더했다. `F03`은 Synaptics 패드 뒤에 붙은 TrackPoint를 RMI4 위로 넘긴다 — 없으면 SMBus로 넘어간 ThinkPad에서
     TrackPoint가 죽는다. `F3A`는 근래 clickpad의 버튼이다.
   - AMD 노트북의 I2C 컨트롤러(`AMDI0010`)는 `X86_AMD_PLATFORM_DEVICE`가 클록을 세워야 DesignWare 드라이버가 붙는다
     (`arch/x86/Kconfig`의 도움말 — "I2C and UART depend on COMMON_CLK to set clock"). design 목록에 없었다. Haswell ·
     Broadwell · Baytrail 세대의 LPSS는 `MFD_INTEL_LPSS_*`가 아니라 `X86_INTEL_LPSS`(acpi_lpss)가 맡는다. 둘 다 더했다.
   - Intel THC는 6.18에 있다(`drivers/hid/intel-thc-hid/`). QuickI2C의 PCI 표가 Lunar Lake · Panther Lake · Wildcat Lake
     (`0xA848` · `0xE348` · `0xE448` · `0x4D48` 등)다. 그 세대의 터치패드는 BIOS 설정에 따라 THC 아래로 갈 수 있어서
     `INTEL_THC_HID` · `INTEL_QUICKI2C`를 켠다. QuickSPI(HID over SPI)는 안 켠다 — 그 세대의 SPI 장치는 대개
     터치스크린이고, 우리는 터치스크린을 안 연다(비목표 4). 다시 열 조건은 SPI로 붙은 터치패드를 가진 노트북이다.

   켜는 것(`scripts/config -e`로 적는 것). 오른쪽 열은 `olddefconfig`가 기본값이나 `select`로 함께 켜는 것이다.

   | 경로 | 적는 심볼 | 따라오는 것 |
   |---|---|---|
   | PS/2 | `INPUT_MOUSE` · `MOUSE_PS2` · `MOUSE_PS2_ELANTECH` | `MOUSE_PS2_ALPS` · `BYD` · `LOGIPS2PP` · `SYNAPTICS` · `SYNAPTICS_SMBUS` · `CYPRESS` · `LIFEBOOK` · `TRACKPOINT` · `FOCALTECH` · `ELANTECH_SMBUS` · `SMBUS` |
   | SMBus | `I2C_I801` · `RMI4_CORE` · `RMI4_SMB` · `RMI4_F03` · `RMI4_F11` · `RMI4_F12` · `RMI4_F30` · `RMI4_F3A` · `MOUSE_ELAN_I2C` · `MOUSE_ELAN_I2C_SMBUS` | `I2C_SMBUS` · `P2SB` · `RMI4_F03_SERIO` · `RMI4_2D_SENSOR` · `MOUSE_ELAN_I2C_I2C` |
   | I2C-HID | `I2C_HID_ACPI` · `HID_MULTITOUCH` · `I2C_DESIGNWARE_CORE` · `MFD_INTEL_LPSS_PCI` · `MFD_INTEL_LPSS_ACPI` · `X86_INTEL_LPSS` · `X86_AMD_PLATFORM_DEVICE` · `COMMON_CLK` · `PINCTRL` · `GPIOLIB` · `PINCTRL_AMD` · `PINCTRL_INTEL_PLATFORM` · `PINCTRL_SUNRISEPOINT` · `CANNONLAKE` · `ICELAKE` · `TIGERLAKE` · `ALDERLAKE` · `METEORLAKE` · `JASPERLAKE` · `GEMINILAKE` · `BROXTON` · `BAYTRAIL` · `CHERRYVIEW` · `LYNXPOINT` · `INTEL_THC_HID` · `INTEL_QUICKI2C` | `I2C_HID_CORE` · `I2C_DESIGNWARE_PLATFORM` · `MFD_INTEL_LPSS` · `MFD_CORE` · `PINCTRL_INTEL` · `GPIOLIB_IRQCHIP` · `GPIO_ACPI` · `IOSF_MBI` |
   | 게이트 | `INPUT_MISC` · `INPUT_UINPUT` | — |

   pinctrl은 노트북에 쓰이는 세대만 골랐다. Skylake · Kaby Lake(SPT) · Coffee · Comet · Whiskey Lake(CNL) · Ice Lake · Tiger ·
   Alder P/U · Raptor P/U(TGL) · Alder · Raptor HX(ADL) · Meteor · Arrow Lake(MTL) · Lunar · Panther Lake(PLATFORM) · Jasper ·
   Gemini · Apollo Lake(BXT) · Baytrail · Cherry Trail · Haswell · Broadwell(LPT)이다. 서버 · 데스크톱 전용(Cedar Fork ·
   Denverton · Emmitsburg · Lewisburg · Meteor Point)은 안 켠다. I2C-HID 터치패드의 인터럽트가 GPIO라서 그 세대의
   pinctrl이 없으면 노드는 생겨도 손가락이 안 읽힌다.

   켜지 않는 것은 design 결정 9 그대로다 — `HID_APPLE` · `HID_MAGICMOUSE` · `MOUSE_BCM5974` · `KEYBOARD_APPLESPI` ·
   `INPUT_MOUSEDEV`. 덧붙여 `HID_RMI`도 안 켠다. 켜면 hid-core가 Synaptics의 I2C-HID 패드를 RMI 그룹으로 분류해
   hid-multitouch 대신 hid-rmi로 보내고, 그 경로는 우리가 게이트로 볼 길이 없다. 안 켜면 그 패드도 hid-multitouch가
   PTP로 받는다. `I2C_PIIX4`(AMD의 SMBus)도 안 켠다 — QEMU pc의 PIIX4가 그 장치라 모든 pc 체인에서 probe가 돌고, AMD의
   Elan SMBus 패드는 대개 I2C-HID로도 열거된다. 실기에서 필요하면 그때 켠다. 둘 다 lead가 정했다(2026-10-05).

   세 겹 검증의 글자(`pointer/check.sh` 검사 19).

   - 심볼 — 위 표의 "적는 심볼"과 따라오는 것 일부가 `kernel/.config`에서 `=y`이고, 켜지 않는 다섯이 `=y`가 아니다.
   - 커널의 장치 표 — `modules.builtin.modinfo`의 alias 여덟. 사본의 `modules.builtin.modinfo`에서 여덟 다 그 글자 그대로 있었다. psmouse는 뺐다 — 소스의 serio 표는 둘(`SERIO_8042` · `SERIO_PS_PSTHRU`)인데 modinfo에는 마지막 것 하나(`psmouse.alias=serio:ty05pr*id*ex*`)만 남아서 판정 글자로 믿기 어렵다. 대신 I2C-HID 경로의 pinctrl(`pinctrl_tigerlake.alias=acpi*:INT34C5:*`)을 넣었다. psmouse는 부팅 B의 검사 20과 드라이버 목록이 직접 본다.
   - 드라이버 등록 — 게스트의 `/sys/bus/*/drivers/` 아래 열둘과 `/dev/uinput`. 사본의 부팅 B에서 `pd-drivers 13/13`이었다.

   드라이버 이름은 소스의 `.name`에서 뽑았다. `psmouse`(serio) · `hid-multitouch`(hid) · `i2c_hid_acpi` · `elan_i2c` ·
   `rmi4_smbus`(i2c) · `rmi4_physical`(rmi4 버스) · `i801_smbus` · `intel-lpss` · `intel_quicki2c`(pci) · `i2c_designware` ·
   `amd_gpio` · `tigerlake-pinctrl`(platform)이다.

5. 되접기. `kernel/.config`는 지금 `olddefconfig`의 출력과 PD와 무관한 줄들이 다르다(PD-M0 plan 확정 7 — 머리 주석과
   UW가 켠 USB 무선 심볼이 `select`로 끌어온 것). 이 milestone은 커널을 바꾸므로 어차피 되접는다. 규칙
   (`project_kernel_config`)대로 정규화와 의도한 변경을 다른 commit으로 나눈다 — lead가 PD-M2 commit 뒤에 되접기만 따로
   commit하고, 구현자는 Task 1-0에서 그것이 들어갔는지 확인만 한다. 구현자의 diff는 터치패드 심볼과 그것이 끌어온
   줄만이다. lead가 정했다(2026-10-05). lead의 되접기 commit `1ecb973`은 머리 주석 두 줄과 UW가 `select`로 끌어온 USB 무선 심볼 여덟(`MT76_USB` · `MT792x_USB` · `RTW88_USB` · `RTW88_88XXA` · `RTW88_8821A` · `RTW88_8812A` · `RTW88_8814A` · `RTW89_USB`)이다. 그 뒤 HEAD의 `.config`와 `build/.config`는 같다.

6. 크기와 시간, 그리고 `install` 부팅 7. PD-M0에서 커널 한 줄(`INOTIFY_USER`가 끌어온 `FSNOTIFY`)이 initramfs 풀기를
   TCG에서 1.2초 늦춰 무관한 `install` 체인의 부팅 7을 빨갛게 했다(PD-M0 plan 확정 7). 이 milestone은 커널을 그보다 훨씬
   많이 바꾸므로 같은 위험을 정면으로 본다. 부팅 7은 q35에 `usb-storage.delay_use=3`이고, init이 디스크보다 먼저 도착해
   기다리는 것을 본다 — 지금 그 기다림이 800~1100ms다. 커널 변경이 `Run /init`을 그만큼 늦추면 기다림이 없어지고 판정
   17이 빨개진다. q35라서 `I2C_I801`이 실제로 ICH9의 SMBus를 probe한다는 것도 이 부팅에서만 생기는 일이다.

   잰 것과 그 결과다. 저장소 사본에서 HEAD 커널과 이 plan의 커널을 render 체인과 같은 QEMU 호출로 세 번씩 띄웠고, `install` 체인을 두 번씩 돌렸다.

   | 무엇 | 바꾸기 전(HEAD) | 바꾼 뒤 |
   |---|---|---|
   | bzImage | 7,435,264바이트 | 7,758,848바이트(+323,584, 4.4%) |
   | 커널 증분 빌드 | — | 104초, 되접은 뒤 재빌드 8초 |
   | `Unpacking initramfs`(커널 시각) | 0.42초 | 0.43초 |
   | `Run /init` | 3.00 · 3.02 · 3.06초 | 3.84 · 3.85 · 3.88초 |
   | 첫 `screen>`(QEMU 시작부터) | 4.1 · 4.1 · 4.2초 | 4.8 · 4.8 · 4.9초 |
   | psmouse의 `input: ImExPS/2 Generic Explorer Mouse` | 없다 | 0.97~0.98초 |
   | `install` 부팅 7의 `init waited` | 900 · 900ms | 100 · 100ms |
   | 같은 커널, 부팅 7만 `delay_use=4` | — | 1100 · 1100ms |

   `Run /init`이 0.84초 늦다. 늦어진 것은 initramfs 풀기 하나다 — 초기화 함수는 두 커널 다 1초 전에 끝나고
   (`initcall_debug`로 본 새 드라이버의 초기화는 전부 5ms 아래), 그 뒤 `Freeing initrd memory`까지 풀기만 남는다.
   psmouse도 아니었다 — `i8042.noaux`(PS/2 탐지를 끈다)와 `psmouse.proto=exps`(탐지를 줄인다)로 띄워도 3.84~3.87초였다.

   원인은 코드의 자리다. 풀기의 대부분은 gzip의 `inflate_fast`(0x810바이트)이고, HEAD에서는 그 함수가 한 페이지 안
   (페이지 안 자리 0x740)에 있는데 이 plan의 커널에서는 0xec0에서 시작해 페이지 경계를 넘는다. 드라이버의 `.cold` 코드가
   본문 앞에 모여 본문이 페이지 단위로 밀리고, 그 위에 arch의 `iosf_mbi`(`X86_INTEL_LPSS` 등이 끌어온다)와 lib의
   `check_signature`(`I2C_I801`이 끌어온다)가 0x780을 더 민 결과다. QEMU TCG는 서로 다른 게스트 페이지에 걸친 번역
   블록을 직접 잇지 못하므로 뜨거운 루프가 경계를 넘으면 느려진다. 확인 실험 둘이 있다. HEAD 설정에 `X86_INTEL_LPSS`
   하나만 켠 커널(입력 코드는 하나도 안 바뀐다)은 `inflate_fast`가 0xe80에서 경계를 넘고 `Run /init`이 4.12~4.16초였다.
   HEAD 설정에 uinput만 켠 커널은 `inflate_fast`가 안 움직였고 3.01~3.06초였다. 무리를 빼는 bisect(pinctrl · LPSS ·
   클록 무리를 뺀 판 3.85초, 마우스 · RMI4 · I801 무리를 뺀 판 4.18초)가 드라이버로는 안 갈리던 이유도 이것이다.

   그러므로 이 늦어짐은 게이트(TCG)의 것이고 실기와는 무관하다. 그리고 코드의 자리에 달려 있어서, 뒤의 어느 커널
   변경이든 다시 움직일 수 있다. PD-M0의 `FSNOTIFY`(풀기 1.2초)도 같은 것이었을 수 있다 — 그때는 `System.map`을 안 봤다.

   여유가 줄었을 때의 후보 셋을 비교했다. lead가 정했다(2026-10-05) — 바꾼 뒤 부팅 7의 기다림이 500ms 아래면 (a)를 이
   milestone에 넣는다. 고칠 자리는 `install/check.sh`의 세 곳(머리 주석의 부팅 표 · 부팅 7의 주석 · `boot_kernel_usb 7`의
   cmdline과 그 앞 echo)이고 Task 7-3에 글자가 있다. 500ms 이상이면 안 고친다.

   | 후보 | 무엇 | 비용 |
   |---|---|---|
   | (a) 부팅 7의 `usb-storage.delay_use`를 3에서 4로 | 디스크가 1초 늦게 보인다. 기다림이 약 1초 늘고, init의 상한(`CONFIG_WAIT_MS` 5000)과는 여전히 2초 넘게 떨어진다 | DC 체인의 숫자 하나와 주석. 그 체인이 보는 것(init이 늦은 디스크를 기다려 잡는다)은 그대로다 |
   | (b) 심볼을 덜 켜서 `inflate_fast`를 페이지 안으로 되돌린다 | 늦어짐이 사라진다 | 실기의 범위가 준다. 그리고 우연에 기대는 고정이다 — 다음에 어느 서브프로젝트가 커널을 바꾸든 다시 움직인다 |
   | (c) psmouse의 프로토콜 탐지를 줄인다(`psmouse.proto=imps` 등) | — | 원인이 아니었다(위 표). 실기에서 Synaptics · Elantech를 못 잡는다. 안 된다 |

   (a)를 고른 이유. PD-M0 때는 커널 한 줄을 되돌리는 것이 답이었지만 이번에는 커널 변경이 이 milestone의 본론이다.
   그리고 늦어짐이 드라이버가 아니라 코드의 자리에서 오므로 (b)는 고쳐도 다시 깨진다. (a)는 창을 1초 벌려 자리가 다시
   움직여도 견딘다 — 사본에서 4초로 두 번 돌려 1100ms였다.
   design 위험 7(psmouse가 실기에서 부팅을 늦추는가)은 QEMU의 시간만 위 표에 있다. 실기의 것은 running-tars.md의 실기
   항목으로 남긴다.

7. 되감기 도구 `tp-replay`. design 결정 10의 모양을 따르되 셋을 정했다.

   - 자리와 빌드. `pointer/replay/`에 `build.zig`와 `main.zig` 둘이다. 제품 빌드(`init/build.zig` · `terminal/build.zig`)에
     붙이지 않는다 — 붙이면 모든 체인이 게이트 전용 도구를 빌드하고, `make_initrd.sh`가 싣는 것과 헷갈린다. 타깃 ·
     모드는 init과 같다(x86_64-linux-musl, ReleaseSafe, libc 없음, 정적). 체인이 `zig build --prefix out/pd-replay
     --cache-dir out/pd-replay/cache`로 빌드한다 — 산출물과 캐시가 `out/` 아래라서 `.gitignore`와 `clean()`을 안 고친다.
     사본에서 `pointer/replay/` 안에 아무것도 안 생겼다. 산출물은 정적 ELF 하나(3,209,752바이트, `with debug_info, not stripped`)다.
   - uinput 값. `UI_DEV_SETUP` 등은 번역을 안 쓰고 상수로 적는다(이 도구는 translate-c 패키지에 기대지 않는다).
     `_IOW('U', nr, T)`를 손으로 셈한 값이고 구조체 크기를 `comptime`으로 assert한다. 컨테이너의 `/usr/include/linux/uinput.h`를 gcc로 컴파일해 찍은 값이 여덟 다 같았다(`UI_DEV_CREATE=0x5501` · `UI_DEV_DESTROY=0x5502` · `UI_DEV_SETUP=0x405c5503` · `UI_ABS_SETUP=0x401c5504` · `UI_SET_EVBIT=0x40045564` · `UI_SET_KEYBIT=0x40045565` · `UI_SET_ABSBIT=0x40045567` · `UI_SET_PROPBIT=0x4004556e`). 구조체 크기도 92 · 28로 같다.
   - 장치. `INPUT_PROP_POINTER` · `BUTTONPAD`, `BTN_LEFT` · `BTN_TOUCH` · `BTN_TOOL_FINGER` · `DOUBLETAP` · `TRIPLETAP`,
     MT 두 칸, 축 0~1000(res 10) · 0~600(res 12). design은 resolution 10 하나였는데 세로를 12로 바꿨다 — 두 축이 같으면
     "세로를 같은 mm당 픽셀로 맞춘다"와 "세로도 가로와 같은 단위당 픽셀"이 같은 숫자를 내서, 그 갈래를 체인이 못 본다.
     12면 세로 60단위가 64픽셀(맞춘 것)이고 76픽셀(안 맞춘 것)이다. lead가 정했다(2026-10-05). 이름은 `TARS Replay Touchpad`다. 커널의 터치패드
     드라이버처럼 포인터 흉내(`ABS_X` · `ABS_Y`)와 `BTN_TOUCH` · `BTN_TOOL_*`를 함께 낸다.

   명령을 넣는 법. services.d로 띄우는 안(wifi 체인의 `services.d/ap`)과 비교했다.

   | 안 | 왜 아닌가 / 왜 이것인가 |
   |---|---|
   | services.d에 두고 디스크의 명령 파일을 읽는다 | 도구가 부팅 중 언제 돌지를 게이트가 못 정한다. 명령 하나를 보내고 그 결과 줄을 기다리는 순서가 깨진다. 그리고 init이 끝난 서비스를 다시 띄운다(SV 감독) |
   | 셸에서 `/config/pd/tp-replay < /config/pd/script`로 한 번에 | 순서는 지키지만 명령 사이의 판정을 게이트가 못 끼운다. 긴 누름(아무것도 안 낸다)을 "아직 안 왔다"와 가를 수 없다 |
   | 셸에서 `/config/pd/tp-replay`를 친 뒤 명령을 한 줄씩 친다 | 고른다. design이 적은 모양이다. 명령마다 그 결과 줄(`at` · `press` · `scroll>` · `close`)을 기다린다. 친 글자는 PTY로 가므로 화살표를 숨기지만(보이는 조건 3) 다음 손가락 이동이 다시 보이게 한다 |

   도구는 명령을 마친 뒤 아무것도 안 찍는다. 출력이 패널에 오면 그 패널이 바닥으로 돌아가 스크롤 검사가 흔들린다.
   처음 한 번 `tp-replay: ready`만 찍는다(장치를 만든 직후라 스크롤 전이다).

   시각. 커널은 uinput이 쓴 묶음마다 주입하는 순간의 시각을 찍는다 — 도구가 쓴 `input_event.time`은 버려진다. 그래서
   탭의 길이는 도구가 자는 시간(40ms · 500ms)이 정하고, terminal이 늦게 읽어도 판정이 안 흔들린다. TCG에서 잠이 길어져도
   40ms가 180ms에 닿으려면 140ms가 늘어야 한다.

8. 부팅 B와 검사 19~25. 포트는 45489(design 결정 10), `-nic none`, 설정 디스크 하나(라벨 `tars-pd`, 16MB ext2). 디스크에는
   `tars.conf`(`shell=fish`), `pd/tp-replay`, `pd/drivers`(검사 19의 둘째를 하는 bash 스크립트)가 있다. `pd/drivers`는 없는
   드라이버만 한 줄씩 찍고 마지막에 `pd-drivers 13/13`을 찍는다 — 있는 것까지 찍으면 화면 한 장을 넘어 `screen>` 줄로
   판정할 수 없다. 명령줄을 sendkey로 치면 글자마다 프레임이 하나씩 그려져서, 경로 열둘을 셸에 직접 치는 것보다 디스크에
   스크립트를 두는 편이 빠르다.

   | 순서 | 검사 | 친다 | 본다 |
   |---|---|---|---|
   | 0 | 19 | (부팅 전) | `kernel/.config`의 심볼 46개가 `=y` · 다섯이 `=y`가 아님 · modinfo alias 여덟 |
   | 1 | 20 | (부팅 B) | 커널 `input: ImExPS/2 Generic Explorer Mouse as /devices/platform/i8042/serio1/input/inputN` · `open … kind=mouse shown=0 name=ImExPS/2 Generic Explorer Mouse` |
   | 2 | 19의 둘째 | `/config/pd/drivers` | 화면에 `pd-drivers 13/13` |
   | 3 | — | `seq 200` | 스크롤백(검사 24의 재료) |
   | 4 | 21 | `/config/pd/tp-replay` | `open … kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad` |
   | 5 | 22 | `move 100 0` · `move 0 60` | `at x=768 y=400 … shown=1 ink=118` · `at x=768 y=464` · `press` 줄 0 |
   | 6 | 23 | `tap` · `hold` · `move 40 0` | `press leaf=0 row=27 col=93` · `release drag=0` · 뒤의 `at x=819 y=464`까지 `press`가 하나뿐 |
   | 7 | 24 | `scroll 90` | 마지막 `scroll>`에서 total − len − offset = 6 · 그 뒤 `at` 줄이 전부 x=819 y=464 · `wheel=`의 합 2 |
   | 8 | 25 | `quit` · `echo pd-tp-gone` | `close <터치패드 경로>` · `close` 줄 하나(PS/2는 열린 채) · 화면에 `pd-tp-gone` |

   좌표의 셈. 출발은 가운데(640, 400)다. 가로 100단위 × 1.28 = 128 → x 768. 세로 60단위 × 1.28 × 10 / 12 = 64 → y 464.
   (768, 464)는 격자 칸 (768 − 20) / 8 = 93열, (464 − 20) / 16 = 27행이다. `move 40 0`은 51.2픽셀이고 앞의 이동이
   나머지 없이 끝났으므로 51 → x 819. 두 손가락 90단위 × 16/15 = 96픽셀 = 눈금 둘 = 여섯 줄.

   긴 누름의 판정. 긴 누름은 아무것도 안 내므로 "아직 안 왔다"와 갈라야 한다. 뒤에 `move 40 0`을 보내 그 `at` 줄을
   기다린다 — 같은 장치의 이벤트는 순서대로 읽히므로 그 줄이 보이면 긴 누름은 이미 디코더를 지났다. 그때 `press`가
   하나(탭의 것)뿐이면 된다. 뒤따르는 이동이 40단위인 이유가 있다. 처음 판은 `move 10 0`이었는데 사본의 체인에서 그
   이동이 클릭이 됐다 — 10단위를 16ms에 민 것은 탭의 조건(2% = 가로 20단위, 180ms)을 다 채운다. 디코더가 맞게 한
   것이고 시나리오가 틀렸다. 40단위는 탭의 거리를 넘는다.

   스크롤의 판정. 패널은 친 글자의 에코로 바닥에 있다가 휠로 올라간다. 바닥일 때 offset = total − len이므로, 손가락 90단위
   뒤의 `scroll>`에서 total − len − offset이 6이면 여섯 줄 위다. offset의 전후를 비교하지 않는 이유는 `scroll 90`의 Enter가
   줄을 하나 더해 바닥이 움직이기 때문이다.

   게이트가 안 보는 것. 실제 드라이버(hid-multitouch · psmouse synaptics · RMI4)가 내는 이벤트의 모양 — 그것은 세 겹 검증과
   실기의 몫이다(design 결정 10의 표). 물리 버튼을 누른 채 끄는 것과 `SYN_DROPPED`, 단일 터치 장치는 `touchpad_test`만 본다.

9. 부팅 A에 `i8042.noaux`. design 결정 9가 적은 부작용("모든 pc 체인에 PS/2 마우스가 생기고 `open` 줄이 하나 는다")이
   `pointer` 체인 자신에게는 판정을 깨는 변화다. 검사 1은 "부팅 때 `open`이 정확히 하나"이고, 검사 6은 `open`이 둘이 될
   때까지 기다리며(PS/2가 있으면 꽂기 전에 이미 둘이라 거짓 초록), 검사 9의 둘째는 "마지막 장치가 빠지면 숨는다"인데
   PS/2 마우스는 HMP로 뺄 수 없다.

   | 안 | 왜 아닌가 / 왜 이것인가 |
   |---|---|
   | 부팅 A의 cmdline에 `i8042.noaux` | 고른다. i8042가 AUX 포트를 안 만들어 psmouse가 잡을 것이 없다. 키보드 포트는 그대로다. PD-M0~M2의 검사가 한 글자도 안 바뀌고, 검사 1의 "정확히 하나"가 그 옵션이 먹혔다는 것까지 본다. 검사 20은 부팅 B로 간다 — 부팅 B는 cmdline이 기본이다 |
   | 검사 1 · 6을 이름으로 세고 검사 9의 둘째를 부팅 B로 옮긴다 | design의 "검사 20은 부팅 A"를 지킨다. 그러나 세 검사의 판정 글자를 바꿔야 하고, 검사 6의 거짓 초록처럼 바꾼 줄이 조용히 약해지는 자리가 생긴다. 부팅 B에서 "마지막 장치"가 되려면 거기서도 PS/2를 꺼야 해서 결국 같은 옵션이 들어간다 |

   lead가 정했다(2026-10-05). 다른 체인(render · copy · pane 등)은 그대로다 — 그 체인들이 "PS/2 마우스가 있어도 화면이 한 픽셀도 안 바뀐다"를 덤으로
   본다(design "검증"의 "M3 뒤에는 같은 판정을 한 번 더 본다").

10. mutation 넷. design 결정 10의 M3 셋 중 둘을 그대로 쓰고, 하나를 바꾸고, 하나를 더했다. 넣는 법은 PD-M2 plan 확정 11과
    같다 — 저장소 파일은 안 고치고, 사본을 `-v`로 그 파일 자리에 덮는다. 같은 `docker run` 안에서 `terminal/.zig-cache` ·
    `terminal/zig-out`을 지우고, 덮인 사본이 쓰였는지 `grep -c`로 mutation 글자를 센다.

    | mutation | 심는 고장 | 고치는 줄 | 빨개지는 자리 |
    |---|---|---|---|
    | 1 | 탭의 시간 조건을 뺀다 | `touchpad.zig` `return self.tap_ok and !pressing and t_us - self.tap_start_us < TAP_US;` → `return self.tap_ok and !pressing;` | `touchpad_test` 검사 3이 부팅 전에. 그것을 끈 사본 체인에서는 검사 23 — 긴 누름이 클릭이 된다 |
    | 2 | 두 손가락을 이동으로 보낸다 | `touchpad.zig` `if (pressing or fingers == 1) {` → `if (pressing or fingers >= 1) {` | `touchpad_test` 검사 5가 부팅 전에. 끈 사본 체인에서는 검사 24 — 포인터가 움직이고 offset은 그대로다 |
    | 3 | 터치패드 갈래를 디코더에 잇지 않는다 | `main.zig` `if (kind == .none) {` → `if (kind != .mouse) {` | 검사 21 — `skip … kind=touchpad` |
    | 4 | 세로를 같은 mm당 픽셀로 맞추지 않는다 | `touchpad.zig` `if (x.res > 0 and y.res > 0) return` → `if (x.res < 0 and y.res > 0) return` | `touchpad_test` 검사 2가 부팅 전에. 끈 사본 체인에서는 검사 22 — `y=476` |

    design의 셋째("`INPUT_PROP_POINTER`를 안 본다 → 검사 21")를 바꾼 이유. `classify`는 `INPUT_PROP_POINTER` 또는
    `BTN_TOOL_FINGER`가 있으면 터치패드라 한다. 되감기 도구는 진짜 터치패드처럼 둘 다 내므로 그 고장을 심어도 `BTN_TOOL_FINGER`
    쪽으로 터치패드가 되어 검사 21이 초록이다 — 실제 노트북 드라이버(`input_mt_init_slots(INPUT_MT_POINTER)`)도 둘 다 내므로
    제품에서도 드러나지 않는 고장이다. 도구에서 `BTN_TOOL_FINGER`를 빼면 잡히지만 그러면 도구가 진짜 패드와 달라진다. 그
    대신 터치패드를 여는 배선 자체를 끊는 고장(3)을 심는다. 분류 표는 `pointer_test` 검사 4가 이미 본다. 바꾼 것과 넷째를
    더한 것은 lead가 정했다(2026-10-05).

    mutation 1 · 2 · 4는 `touchpad.zig`를 바꾸므로 체인이 부팅 전에 돌리는 `zig build test`(`touchpad_test`)가 먼저 잡는다.
    체인의 판정은 그 한 단계만 끈 사본 체인으로 따로 본다(PD-M0 · M2와 같다).

11. 사본에서 돌려 본 것. VM이 빈 뒤 저장소를 `/tmp/run/pdm3/repo/`로 통째로 복사하고(`.git` · zig 캐시 · `out` 제외) 이 plan의 편집을
    넣어 거기서 돌렸다. 저장소의 작업 트리는 한 글자도 안 바뀌었다. 컨테이너는 하나씩 돌렸고 `Killed`는 없었다.

    | 무엇 | 결과 |
    |---|---|
    | 앵커(`anchors.py pre`) | `1ecb973`의 작업 트리에서 `pre: 20 edits, 0 bad`. Task 7-3의 셋(`anchors_cond.json`)도 하나씩 맞는다 |
    | 커널 | 확정 4 · 6의 표. `olddefconfig`가 더한 것은 적은 41개와 표의 "따라오는 것" 그리고 `REGMAP` · `GPIO_CDEV` · `GPIO_CDEV_V1` · `GPIOLIB_FASTPATH_LIMIT=512` · `SERIAL_MCTRL_GPIO`(8250이 GPIO 모뎀 제어선을 쓰는 도우미 — `GPIOLIB`를 켜면 따라온다) · `CHECK_SIGNATURE` · `HAVE_CLK` · `HAVE_CLK_PREPARE` · `PINMUX` · `PINCONF` · `GENERIC_PINCONF`다. `FSNOTIFY`는 없다. 켜지 않기로 한 일곱은 `=y`가 아니다 |
    | `zig build test` | `exit=0`. `touchpad_test` OK 34, `pointer_test` OK 107(PD-M2 그대로). `all checks passed` 넷과 `PASS` 다섯 |
    | `zig build` | `exit=0` |
    | `zig fmt --check` | 새 파일 넷과 `build.zig`는 깨끗하다. `main.zig`는 고치기 전부터 fmt와 6줄 다르고, 고친 뒤도 6줄이다(이 plan이 더한 줄에서 생긴 차이는 0) |
    | 진입 검사 셋 | `ENTRY-OK`, `bash -n` 둘 통과 |
    | 체인 `pointer` | 처음 판은 검사 23에서 빨갰다 — 확정 8의 "긴 누름의 판정"(`move 10 0`이 탭이었다). 고친 뒤 `PD-M3 check PASS` 두 판, 51초 · 51초(캐시가 따뜻했다) |
    | regression | `render` 1분 50초 · `copy` 2분 52초 · `pane` 33초 · `machine` 20초 다 PASS. `install`은 위 표(1분 45초씩) |
    | mutation 1~4 | 넷 다 Task 8의 표의 자리와 문구 그대로 빨갰다 |

12. 루트 게이트는 2회다(`feedback_gate_runs`). 판정은 `PASS: 2/2` × 19와 `PD-M3 check PASS` 둘이다.

## lead가 정한 것(2026-10-05)

1. 부팅 7의 여유(확정 6). 바꾼 뒤의 기다림이 500ms 아래면 `usb-storage.delay_use`를 3에서 4로 올린다(Task 7-3).
2. Intel THC(확정 4). QuickI2C만 켠다. QuickSPI는 비목표이고, 다시 열 조건은 SPI로 붙은 터치패드를 가진 노트북이다.
3. 되접기(확정 5). lead가 PD-M2 commit 뒤 별도 commit으로 한다. Task 1-0은 그것을 확인하는 단계다.
4. 부팅 A의 `i8042.noaux`(확정 9). 검사 20은 부팅 B에 있다.
5. design에서 바꾼 것("design과 다르게 적은 것")을 받는다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -4
   ```

   기대: `git status`는 이 plan 파일(`??` 또는 commit됐으면 0줄)과 lead가 고치는 중일 수 있는 `HANDOFF.md`뿐이다. 맨 위
   commit이 되접기(`1ecb973 Fold the built kernel config back: …`)이고 그 아래가 `e937b92 PD-M2: …`다.

3. 편집의 앵커가 지금 파일에 맞는지 본다(확정 11).

   ```bash
   python3 /tmp/run/pdm3/anchors.py pre "$PWD"
   ```

   기대: `pre: 20 edits, 0 bad`. 하나라도 `bad`면 그 줄을 보고하고 멈춘다.

4. 호스트 검사와 커널의 지금 값을 본다.

   ```bash
   mkdir -p /tmp/run/pdm3/impl
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
     (cd terminal && zig build test > /tmp/t.out 2>&1); echo "exit=$?"
     grep -a -c "^pointer_test: .* OK$" /tmp/t.out
     grep -a -E "all checks passed|^PASS$|FAIL" /tmp/t.out
     (cd kernel && ./build.sh > /tmp/k.out 2>&1); echo "kernel exit=$?"; tail -1 /tmp/k.out
     stat -c %s kernel/build/arch/x86/boot/bzImage
     diff kernel/.config kernel/build/.config && echo CONFIG-SAME'
   ```

   기대: `exit=0`, `pointer_test` OK 107, `all checks passed` 셋과 `PASS` 다섯, `FAIL` 0줄. 커널은 `skipping make`이거나
   (스탬프가 없으면) 빌드한 뒤 `kernel exit=0`. bzImage 7,435,264바이트, `CONFIG-SAME`(되접기가 들어갔다).

## Task 1: 커널 config

### 1-0. 되접기가 들어갔는지 본다

되접기는 lead가 PD-M2 commit(`e937b92`) 뒤 별도 commit `1ecb973`(`Fold the built kernel config back: the USB wireless
selects UW pulled in`)으로 이미 했다(확정 5).
구현자는 확인만 한다. Task 0-4의 `CONFIG-SAME`이 그 판정이고, 여기서는 commit을 본다.

```bash
git log --oneline -3 -- kernel/.config
git show --stat HEAD -- kernel/.config | tail -2
```

기대: 맨 위가 `1ecb973 Fold the built kernel config back: …`이다. 그 commit은 `kernel/.config`의 열 줄(머리 주석 둘 · USB 무선 심볼 여덟)이다. 그 commit이 없거나 Task 0-4에서
`CONFIG-SAME`이 안 나왔으면 멈추고 보고한다 — 되접기 없이 Task 1-1을 하면 터치패드와 무관한 줄이 이 milestone의 diff에
섞인다.

### 1-1. 심볼을 적는다

커널 소스의 `scripts/config`로 적는다. 손으로 고치면 `# CONFIG_X is not set` 줄과 새로 적는 줄이 섞여 빠뜨리기 쉽다.
줄 자체가 없는 심볼(`INPUT_MOUSE`가 꺼져 있어 `MOUSE_PS2` 줄이 없다)은 파일 끝에 붙고, `olddefconfig`가 제자리로 옮긴다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm3:/tmp/run/pdm3 -w /workspace tars-devcontainer bash -c '
  kernel/src/linux-6.18.42/scripts/config --file kernel/.config \
    -e INPUT_MOUSE -e MOUSE_PS2 -e MOUSE_PS2_ELANTECH -e I2C_I801 -e RMI4_CORE -e RMI4_SMB -e RMI4_F03 \
    -e RMI4_F11 -e RMI4_F12 -e RMI4_F30 -e RMI4_F3A -e MOUSE_ELAN_I2C -e MOUSE_ELAN_I2C_SMBUS -e I2C_HID_ACPI \
    -e HID_MULTITOUCH -e I2C_DESIGNWARE_CORE -e MFD_INTEL_LPSS_PCI -e MFD_INTEL_LPSS_ACPI -e X86_INTEL_LPSS \
    -e X86_AMD_PLATFORM_DEVICE -e COMMON_CLK -e PINCTRL -e GPIOLIB -e PINCTRL_AMD -e PINCTRL_INTEL_PLATFORM \
    -e PINCTRL_SUNRISEPOINT -e PINCTRL_CANNONLAKE -e PINCTRL_ICELAKE -e PINCTRL_TIGERLAKE -e PINCTRL_ALDERLAKE \
    -e PINCTRL_METEORLAKE -e PINCTRL_JASPERLAKE -e PINCTRL_GEMINILAKE -e PINCTRL_BROXTON -e PINCTRL_BAYTRAIL \
    -e PINCTRL_CHERRYVIEW -e PINCTRL_LYNXPOINT -e INTEL_THC_HID -e INTEL_QUICKI2C -e INPUT_MISC \
    -e INPUT_UINPUT
  { time (cd kernel && ./build.sh > /tmp/run/pdm3/impl/kbuild.log 2>&1); } 2> /tmp/run/pdm3/impl/kbuild.time
  echo "build exit=$?"; tail -3 /tmp/run/pdm3/impl/kbuild.time
  cp kernel/build/.config kernel/.config
  (cd kernel && ./build.sh > /tmp/run/pdm3/impl/kbuild2.log 2>&1); echo "rebuild exit=$?"
  diff kernel/.config kernel/build/.config && echo FOLDED
  stat -c %s kernel/build/arch/x86/boot/bzImage'
```

커널 증분 빌드가 이 milestone에서 가장 무겁다 — 약 1분 44초(사본에서 104초, 되접은 뒤 재빌드 8초)다.
Bash 도구의 10분 상한에 가까우면 `run_in_background`로 돌린다.

기대: `build exit=0`, `rebuild exit=0`, `FOLDED`, bzImage 7,758,848바이트.

### 1-2. 확인

```bash
git diff --stat kernel/.config
git diff kernel/.config | rg '^-[^-]'
for s in INPUT_MOUSE MOUSE_PS2 MOUSE_PS2_SYNAPTICS MOUSE_PS2_SYNAPTICS_SMBUS MOUSE_PS2_ELANTECH MOUSE_PS2_ELANTECH_SMBUS MOUSE_PS2_ALPS MOUSE_PS2_FOCALTECH MOUSE_PS2_TRACKPOINT RMI4_CORE RMI4_SMB RMI4_F03 RMI4_F11 RMI4_F12 RMI4_F30 RMI4_F3A I2C_I801 MOUSE_ELAN_I2C MOUSE_ELAN_I2C_I2C MOUSE_ELAN_I2C_SMBUS I2C_HID_ACPI HID_MULTITOUCH I2C_DESIGNWARE_CORE I2C_DESIGNWARE_PLATFORM MFD_INTEL_LPSS_PCI MFD_INTEL_LPSS_ACPI X86_INTEL_LPSS X86_AMD_PLATFORM_DEVICE PINCTRL_AMD PINCTRL_INTEL_PLATFORM PINCTRL_SUNRISEPOINT PINCTRL_CANNONLAKE PINCTRL_ICELAKE PINCTRL_TIGERLAKE PINCTRL_ALDERLAKE PINCTRL_METEORLAKE PINCTRL_JASPERLAKE PINCTRL_GEMINILAKE PINCTRL_BROXTON PINCTRL_BAYTRAIL PINCTRL_CHERRYVIEW PINCTRL_LYNXPOINT INTEL_THC_HID INTEL_QUICKI2C INPUT_MISC INPUT_UINPUT; do rg -x "CONFIG_${s}=y" kernel/.config > /dev/null || echo "MISSING $s"; done
for s in HID_APPLE HID_MAGICMOUSE MOUSE_BCM5974 KEYBOARD_APPLESPI INPUT_MOUSEDEV HID_RMI I2C_PIIX4; do rg -x "CONFIG_${s}=y" kernel/.config && echo "ON $s"; done
diff kernel/.config /tmp/run/pdm3/new/kernel/.config && echo SAME
```

기대: `1 file changed, 261 insertions(+), 16 deletions(-)`(사본의 `diff`로 센 수 — 더한 줄 261 · 지운 줄 16). `rg '^-[^-]'`의 줄은 `# CONFIG_X is not set` 꼴뿐이다(켠 심볼의 옛 줄). `MISSING`과 `ON`은 0줄, `SAME`.

## Task 2: `terminal/src/touchpad.zig` — 새 파일

확정 1 · 2의 상태 기계와 상수다. 사본을 그대로 옮긴다.

```bash
cp /tmp/run/pdm3/new/terminal/src/touchpad.zig terminal/src/touchpad.zig
```

본문(읽고 대조하는 용도 — `cp`한 파일과 이 블록은 같은 바이트다):

```zig
//! 터치패드 하나의 raw `input_event`를 `pointer.Frame`으로 바꾸는 순수한 층
//! (PD design 결정 8).
//!
//! 시스템 콜이 없다. 장치를 열고 축 정보를 ioctl로 읽는 것은 `main.zig`이고,
//! 이 파일은 그 값과 이벤트를 받아 판단만 한다 — 그래서 `touchpad_test`가
//! 부팅 없이 같은 판단을 본다. 출력이 마우스 디코더(`pointer.Mouse`)와 같은
//! `Frame`이라서 그 아래(`Pointer` · `Gesture`)는 터치패드를 모른다.
//!
//! 하는 것은 넷이다. 한 손가락은 이동, 짧게 두드리면 왼쪽 클릭, 두 손가락을
//! 세로로 밀면 휠, 물리 버튼은 그대로 통과. 안 하는 것은 design 비목표 6이다
//! (가속 · 손바닥 거부 · 가장자리 스크롤 · 세 손가락 · 관성 · 두 손가락 탭 등).
const std = @import("std");
const pointer = @import("pointer.zig");
const c = pointer.c;

/// 따라가는 접촉 칸의 수. 장치가 더 많은 칸을 알려도 여기서 자른다 — 이동과
/// 두 손가락 스크롤에는 둘이면 되고, 손가락 수는 `BTN_TOOL_*`가 따로 센다.
pub const MAX_SLOTS = 5;

/// 탭으로 치는 접촉의 최대 길이(마이크로초). design 결정 8의 출발값 180ms다.
/// 실기 없이 정한 값이라 사람이 손으로 본 뒤 고친다(design 위험 3) — 고치면
/// `touchpad_test`의 탭 검사도 함께 고친다.
pub const TAP_US: i64 = 180_000;

/// 탭이 움직여도 되는 거리. 축 범위의 2%다(design 결정 8의 출발값).
pub const TAP_SLOP_PERCENT: i64 = 2;

/// `EVIOCGABS`가 돌려준 축 하나(`struct input_absinfo`의 셋).
pub const Axis = struct {
    min: i32,
    max: i32,
    /// 단위/mm. 0이면 장치가 안 알려 준 것이다.
    res: i32 = 0,

    fn range(self: Axis) i64 {
        const r = @as(i64, self.max) - self.min;
        return if (r > 0) r else 1;
    }

    fn slop(self: Axis) i64 {
        return @divTrunc(self.range() * TAP_SLOP_PERCENT, 100);
    }
};

/// 접촉을 어디서 읽나. `mt`는 MT 프로토콜 B(`ABS_MT_SLOT`의 칸마다),
/// `st`는 단일 터치(`ABS_X` · `ABS_Y`와 `BTN_TOUCH` 하나)다.
pub const Mode = enum { mt, st };

/// 이 장치를 어느 방식으로 읽을지 고른다. 둘 다 안 되면 null이다 — `main.zig`가
/// 그 장치를 열지 않는다.
///
/// MT인데 `ABS_MT_SLOT`이 없는 장치(프로토콜 A)는 `ABS_X` · `ABS_Y`가 있으면
/// 단일 터치로 읽는다. 커널의 노트북 터치패드 드라이버(hid-multitouch · psmouse ·
/// RMI4)는 전부 프로토콜 B라서 이 갈래는 옛 장치의 대비다.
pub fn modeOf(caps: *const pointer.Caps) ?Mode {
    const has = pointer.bitSet;
    if (has(&caps.abs, c.ABS_MT_SLOT) and has(&caps.abs, c.ABS_MT_POSITION_X) and
        has(&caps.abs, c.ABS_MT_POSITION_Y)) return .mt;
    if (has(&caps.abs, c.ABS_X) and has(&caps.abs, c.ABS_Y)) return .st;
    return null;
}

/// 장치를 열 때 한 번 읽는 값. `main.zig`가 `EVIOCGABS`로 채운다.
pub const Setup = struct {
    mode: Mode,
    /// `mt`면 `ABS_MT_POSITION_X/Y`, `st`면 `ABS_X/Y`의 축.
    x: Axis,
    y: Axis,
    /// 접촉 칸의 수(`ABS_MT_SLOT`의 max + 1). `st`면 1이다.
    slots: usize = 1,
    /// 열 때의 `ABS_MT_SLOT` 값. 커널은 칸이 바뀔 때만 그 이벤트를 보낸다.
    slot: usize = 0,
};

/// 화면 쪽 값 둘. 패드의 단위를 픽셀로 바꾸고 스크롤을 눈금으로 바꾼다.
pub const Screen = struct {
    /// 프레임버퍼의 가로 픽셀. 패드 가로 전체가 이것이 된다(design 결정 8).
    w: u32,
    /// 휠 한 눈금으로 칠 손가락 이동(픽셀). `main.zig`가 `WHEEL_ROWS ×
    /// ROW_HEIGHT`를 넘긴다 — 한 눈금이 세 줄이므로 손가락과 글자가 같은
    /// 거리를 간다.
    notch_px: u32,
};

/// 이벤트 하나에 디코더가 내는 `Frame`들. 대개 0개이고, `SYN_REPORT`에 하나,
/// 탭이 끝난 `SYN_REPORT`에만 둘(누름 · 뗌)이다.
pub const Frames = struct {
    buf: [2]pointer.Frame = undefined,
    len: usize = 0,

    pub fn one(f: pointer.Frame) Frames {
        var out: Frames = .{};
        out.push(f);
        return out;
    }

    fn push(self: *Frames, f: pointer.Frame) void {
        self.buf[self.len] = f;
        self.len += 1;
    }

    pub fn slice(self: *const Frames) []const pointer.Frame {
        return self.buf[0..self.len];
    }
};

/// 접촉 칸 하나.
const Contact = struct {
    /// tracking id. -1이면 칸이 비었다.
    id: i32 = -1,
    /// 커널이 마지막으로 알린 자리. 커널의 입력 core는 같은 값을 다시 보내지
    /// 않으므로 손가락이 떨어졌다 같은 x에 다시 닿으면 x 이벤트가 안 온다 —
    /// 그래서 칸이 비어도 지우지 않는다.
    x: i32 = 0,
    y: i32 = 0,
    /// 직전 `SYN_REPORT` 때의 자리. 그때 닿아 있지 않았으면 null이다.
    prev: ?[2]i32 = null,
    /// 이번 묶음에서 새 tracking id를 받았다. 이 묶음은 변화량을 안 낸다.
    fresh: bool = false,
    /// 몇 번째로 닿은 접촉인가. 클수록 늦게 닿았다.
    order: u32 = 0,
};

pub const Touchpad = struct {
    setup: Setup,
    screen: Screen,
    contacts: [MAX_SLOTS]Contact = @splat(.{}),
    /// 지금 고른 칸(`ABS_MT_SLOT`). 범위 밖이면 그 칸의 이벤트를 버린다.
    slot: usize = 0,
    /// `BTN_TOOL_FINGER`(비트 0) ~ `BTN_TOOL_QUINTTAP`(비트 4) 중 눌린 것.
    tool_bits: u8 = 0,
    /// `BTN_TOUCH`. 단일 터치 모드의 접촉이다.
    touch: bool = false,
    /// 물리 버튼(clickpad의 `BTN_LEFT` 등). 그대로 통과한다.
    held: pointer.Buttons = .{},
    /// 마지막으로 낸 `Frame`의 버튼. 버튼만 바뀐 묶음도 `Frame`을 내려고 든다.
    sent: pointer.Buttons = .{},
    /// `SYN_DROPPED`를 받았다. 다음 `SYN_REPORT`까지 버린다.
    dropping: bool = false,
    /// 접촉에 붙이는 순번(`Contact.order`).
    touches: u32 = 0,
    /// 픽셀로 바꾸고 남은 나머지. 작은 이동이 버려지지 않게 다음 묶음에 넘긴다.
    rem_x: i64 = 0,
    rem_y: i64 = 0,
    /// 두 손가락 스크롤 중인가와, 눈금이 되기 전의 픽셀.
    scrolling: bool = false,
    scroll_rem: i64 = 0,
    scroll_px: i64 = 0,
    /// 손가락이 0에서 늘어난 뒤 다시 0이 될 때까지가 한 세션이다. 탭인지는
    /// 세션이 끝날 때 가린다.
    session: bool = false,
    tap_ok: bool = false,
    tap_order: u32 = 0,
    tap_start_us: i64 = 0,
    tap_x: i32 = 0,
    tap_y: i32 = 0,

    pub fn init(setup: Setup, screen: Screen) Touchpad {
        var s = setup;
        s.slots = @min(@max(s.slots, 1), MAX_SLOTS);
        if (s.mode == .st) s.slots = 1;
        return .{ .setup = s, .screen = screen, .slot = s.slot };
    }

    /// 이벤트 하나를 먹인다. `t_us`는 그 이벤트의 시각(`ev.time`)이다 — 커널이
    /// 묶음마다 찍으므로 terminal이 늦게 읽어도 탭의 길이가 안 흔들린다.
    pub fn feed(self: *Touchpad, ev_type: u16, code: u16, value: i32, t_us: i64) Frames {
        if (ev_type == c.EV_SYN) {
            if (code == c.SYN_DROPPED) {
                self.dropping = true;
                return .{};
            }
            if (code != c.SYN_REPORT) return .{};
            if (self.dropping) {
                self.dropping = false;
                return self.resync();
            }
            return self.report(t_us);
        }
        if (self.dropping) return .{};
        switch (ev_type) {
            c.EV_ABS => self.abs(code, value),
            c.EV_KEY => self.key(code, value),
            // `EV_MSC`(`MSC_TIMESTAMP` 등)와 그 밖은 버린다.
            else => {},
        }
        return .{};
    }

    fn current(self: *Touchpad) ?*Contact {
        if (self.slot >= self.setup.slots) return null;
        return &self.contacts[self.slot];
    }

    fn abs(self: *Touchpad, code: u16, value: i32) void {
        switch (self.setup.mode) {
            .mt => switch (code) {
                c.ABS_MT_SLOT => self.slot = if (value >= 0) @intCast(value) else MAX_SLOTS,
                c.ABS_MT_TRACKING_ID => if (self.current()) |k| {
                    if (value < 0) {
                        k.id = -1;
                    } else if (k.id != value) {
                        k.id = value;
                        k.fresh = true;
                        self.touches += 1;
                        k.order = self.touches;
                    }
                },
                c.ABS_MT_POSITION_X => if (self.current()) |k| {
                    k.x = value;
                },
                c.ABS_MT_POSITION_Y => if (self.current()) |k| {
                    k.y = value;
                },
                // MT 장치가 함께 내는 `ABS_X` · `ABS_Y`(포인터 흉내)는 버린다.
                else => {},
            },
            .st => switch (code) {
                c.ABS_X => self.contacts[0].x = value,
                c.ABS_Y => self.contacts[0].y = value,
                else => {},
            },
        }
    }

    fn key(self: *Touchpad, code: u16, value: i32) void {
        const on = value != 0;
        const tool: ?u3 = switch (code) {
            c.BTN_TOOL_FINGER => 0,
            c.BTN_TOOL_DOUBLETAP => 1,
            c.BTN_TOOL_TRIPLETAP => 2,
            c.BTN_TOOL_QUADTAP => 3,
            c.BTN_TOOL_QUINTTAP => 4,
            else => null,
        };
        if (tool) |bit| {
            const mask = @as(u8, 1) << bit;
            self.tool_bits = if (on) self.tool_bits | mask else self.tool_bits & ~mask;
            return;
        }
        switch (code) {
            c.BTN_LEFT => self.held.left = on,
            c.BTN_RIGHT => self.held.right = on,
            c.BTN_MIDDLE => self.held.middle = on,
            c.BTN_TOUCH => self.touch = on,
            else => {},
        }
    }

    /// `BTN_TOOL_*`가 말하는 손가락 수. 칸보다 손가락을 더 세는 장치가 있어서
    /// 따로 든다(design 결정 8).
    fn toolFingers(self: *const Touchpad) usize {
        if (self.tool_bits == 0) return 0;
        return 8 - @as(usize, @clz(self.tool_bits));
    }

    /// 단일 터치 모드의 칸 0을 `BTN_TOUCH`(또는 `BTN_TOOL_*`)로 열고 닫는다.
    fn stContact(self: *Touchpad) void {
        const k = &self.contacts[0];
        const down = self.touch or self.tool_bits != 0;
        if (down and k.id < 0) {
            k.id = 0;
            k.fresh = true;
            self.touches += 1;
            k.order = self.touches;
        } else if (!down) {
            k.id = -1;
        }
    }

    /// `SYN_REPORT` 하나 — 모은 상태를 `Frame`으로 바꾼다.
    fn report(self: *Touchpad, t_us: i64) Frames {
        if (self.setup.mode == .st) self.stContact();

        var active: usize = 0;
        // 포인터를 움직일 접촉은 가장 늦게 닿은 것이다. 엄지로 버튼을 누른 채
        // 검지로 끄는 동작에서 검지가 그것이다(design 결정 8의 물리 버튼 줄).
        var point: ?*Contact = null;
        for (self.contacts[0..self.setup.slots]) |*k| {
            if (k.id < 0) continue;
            active += 1;
            if (point == null or k.order > point.?.order) point = k;
        }
        const fingers = @max(active, self.toolFingers());
        const pressing = self.held.bits() != 0;

        var f: pointer.Frame = .{ .buttons = self.held };
        if (pressing or fingers == 1) {
            self.scrolling = false;
            if (point) |p| {
                if (!p.fresh) {
                    if (p.prev) |q| {
                        f.dx = scale(p.x - q[0], self.screen.w, self.setup.x.range(), &self.rem_x);
                        const yd = self.yRatio();
                        f.dy = scale(p.y - q[1], yd[0], yd[1], &self.rem_y);
                    }
                }
            }
        } else if (fingers == 2) {
            f.wheel = self.scroll();
        } else {
            // 손가락이 없거나 셋 이상이다. 셋 이상은 비목표 6이다.
            self.scrolling = false;
        }

        const tap = self.tapStep(fingers, pressing, point, t_us);

        for (self.contacts[0..self.setup.slots]) |*k| {
            k.prev = if (k.id >= 0) .{ k.x, k.y } else null;
            k.fresh = false;
        }

        var out: Frames = .{};
        if (tap) {
            // 누름과 뗌을 한 쌍으로 낸다(design 결정 8). 둘 다 같은 자리라서
            // `Pointer.apply`가 눌림 하나와 뗌 하나를 차례로 낸다 — 클릭이다.
            var down = f;
            down.buttons.left = true;
            out.push(down);
            out.push(.{ .buttons = self.held });
            self.sent = self.held;
            return out;
        }
        if (f.dx != 0 or f.dy != 0 or f.wheel != 0 or f.buttons.bits() != self.sent.bits()) {
            out.push(f);
            self.sent = f.buttons;
        }
        return out;
    }

    /// 세로의 픽셀/단위를 분수(분자, 분모)로. 두 축의 resolution이 다 있으면
    /// 가로와 같은 mm당 픽셀이 되게 맞추고, 없으면 가로와 같은 단위당 픽셀을
    /// 쓴다(design 결정 8). 패드 세로를 화면 세로에 맞추지 않는다 — 그러면 같은
    /// 손가락 거리가 가로와 세로에서 다른 픽셀이 된다.
    fn yRatio(self: *const Touchpad) [2]i64 {
        const x = self.setup.x;
        const y = self.setup.y;
        const w: i64 = self.screen.w;
        if (x.res > 0 and y.res > 0) return .{ w * x.res, x.range() * y.res };
        return .{ w, x.range() };
    }

    /// 두 손가락의 평균 세로 변화를 픽셀로 모아 눈금을 낸다. 손가락을 아래로
    /// 밀면 내용도 아래로 간다(macOS 트랙패드 기본) — 휠을 앞으로 민 것(양수,
    /// 위의 글을 보이게 한다)과 같은 쪽이다.
    fn scroll(self: *Touchpad) i32 {
        if (!self.scrolling) {
            self.scrolling = true;
            self.scroll_rem = 0;
            self.scroll_px = 0;
        }
        var sum: i64 = 0;
        var n: i64 = 0;
        for (self.contacts[0..self.setup.slots]) |*k| {
            if (k.id < 0 or k.fresh) continue;
            const q = k.prev orelse continue;
            sum += @as(i64, k.y) - q[1];
            n += 1;
        }
        if (n == 0) return 0;
        const yd = self.yRatio();
        self.scroll_px += scale(@divTrunc(sum, n), yd[0], yd[1], &self.scroll_rem);
        const notch: i64 = @max(self.screen.notch_px, 1);
        const notches = @divTrunc(self.scroll_px, notch);
        self.scroll_px -= notches * notch;
        return @intCast(notches);
    }

    /// 탭인지 가린다. 세션(손가락이 0에서 늘어난 뒤 다시 0이 될 때까지)이
    /// 한 손가락뿐이었고, 버튼이 안 눌렸고, 같은 접촉이 축 범위의 2% 안에
    /// 머물렀고, `TAP_US`보다 짧았으면 끝나는 묶음에서 참이다.
    fn tapStep(self: *Touchpad, fingers: usize, pressing: bool, point: ?*const Contact, t_us: i64) bool {
        if (fingers > 0 and !self.session) {
            self.session = true;
            self.tap_ok = !pressing and fingers == 1 and point != null;
            self.tap_start_us = t_us;
            if (point) |p| {
                self.tap_order = p.order;
                self.tap_x = p.x;
                self.tap_y = p.y;
            }
            return false;
        }
        if (fingers > 0) {
            if (fingers > 1 or pressing) self.tap_ok = false;
            if (point) |p| {
                if (p.order != self.tap_order or
                    far(p.x, self.tap_x, self.setup.x.slop()) or
                    far(p.y, self.tap_y, self.setup.y.slop())) self.tap_ok = false;
            }
            return false;
        }
        if (!self.session) return false;
        self.session = false;
        return self.tap_ok and !pressing and t_us - self.tap_start_us < TAP_US;
    }

    /// `SYN_DROPPED` 뒤 첫 `SYN_REPORT`. 모든 접촉과 버튼을 뗀 것으로 하고 새로
    /// 센다(design 결정 8). `EVIOCGMTSLOTS`로 다시 맞추지 않는다 — 아직 닿아
    /// 있는 손가락은 떨어졌다 다시 닿을 때까지 무시된다. 버튼을 눌린 채로 두면
    /// 버린 구간의 뗌을 잃었을 때 영영 눌린 채가 되므로 놓는다.
    fn resync(self: *Touchpad) Frames {
        for (&self.contacts) |*k| {
            k.id = -1;
            k.prev = null;
            k.fresh = false;
        }
        self.tool_bits = 0;
        self.touch = false;
        self.held = .{};
        self.session = false;
        self.scrolling = false;
        if (self.sent.bits() == 0) return .{};
        self.sent = .{};
        return Frames.one(.{});
    }
};

/// `du` 단위를 `num / den` 배율로 픽셀로 바꾼다. 나머지는 `rem`에 남겨 다음에
/// 더한다 — 10단위씩 열 번 민 것과 100단위를 한 번 민 것이 같은 픽셀이 된다.
fn scale(du: i64, num: i64, den: i64, rem: *i64) i32 {
    const t = du * num + rem.*;
    const q = @divTrunc(t, den);
    rem.* = t - q * den;
    return @intCast(std.math.clamp(q, std.math.minInt(i32), std.math.maxInt(i32)));
}

fn far(a: i32, b: i32, lim: i64) bool {
    const d = @as(i64, a) - b;
    return d > lim or d < -lim;
}
```

## Task 3: `terminal/src/touchpad_test.zig` · `terminal/build.zig`

### 3-1. `touchpad_test.zig` — 새 파일

```bash
cp /tmp/run/pdm3/new/terminal/src/touchpad_test.zig terminal/src/touchpad_test.zig
```

```zig
const std = @import("std");
const pointer = @import("pointer.zig");
const touchpad = @import("touchpad.zig");
const c = pointer.c;

/// 게이트의 되감기 도구(`pointer/replay/`)가 만드는 패드와 같은 축이다. 세로의
/// resolution이 가로와 달라서 "세로를 같은 mm당 픽셀로 맞춘다"가 숫자로 보인다 —
/// 가로는 1280 / 1000 = 1.28픽셀/단위, 세로는 1.28 × 10 / 12 = 16/15픽셀/단위.
const PAD: touchpad.Setup = .{
    .mode = .mt,
    .x = .{ .min = 0, .max = 1000, .res = 10 },
    .y = .{ .min = 0, .max = 600, .res = 12 },
    .slots = 2,
};

/// 게이트 프레임버퍼의 가로와, `main.zig`가 넘기는 눈금(`WHEEL_ROWS` 3 ×
/// `ROW_HEIGHT` 16).
const SCREEN: touchpad.Screen = .{ .w = 1280, .notch_px = 48 };

/// 디코더 하나와 시계 하나. 낸 `Frame`을 다 모아 둔다.
const Pad = struct {
    tp: touchpad.Touchpad,
    t_us: i64 = 1_000_000,
    frames: [64]pointer.Frame = undefined,
    n: usize = 0,

    fn init(setup: touchpad.Setup) Pad {
        return .{ .tp = touchpad.Touchpad.init(setup, SCREEN) };
    }

    fn ev(self: *Pad, ev_type: anytype, code: anytype, value: i32) void {
        const out = self.tp.feed(@intCast(ev_type), @intCast(code), value, self.t_us);
        for (out.slice()) |f| {
            self.frames[self.n] = f;
            self.n += 1;
        }
    }

    fn syn(self: *Pad) void {
        self.ev(c.EV_SYN, c.SYN_REPORT, 0);
    }

    fn wait(self: *Pad, ms: i64) void {
        self.t_us += ms * 1000;
    }

    /// 칸 `slot`에 새 접촉. 자리를 함께 알린다.
    fn down(self: *Pad, slot: i32, id: i32, x: i32, y: i32) void {
        self.ev(c.EV_ABS, c.ABS_MT_SLOT, slot);
        self.ev(c.EV_ABS, c.ABS_MT_TRACKING_ID, id);
        self.ev(c.EV_ABS, c.ABS_MT_POSITION_X, x);
        self.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
    }

    fn up(self: *Pad, slot: i32) void {
        self.ev(c.EV_ABS, c.ABS_MT_SLOT, slot);
        self.ev(c.EV_ABS, c.ABS_MT_TRACKING_ID, -1);
    }

    fn sumDx(self: *const Pad) i32 {
        var s: i32 = 0;
        for (self.frames[0..self.n]) |f| s += f.dx;
        return s;
    }

    fn sumDy(self: *const Pad) i32 {
        var s: i32 = 0;
        for (self.frames[0..self.n]) |f| s += f.dy;
        return s;
    }

    fn sumWheel(self: *const Pad) i32 {
        var s: i32 = 0;
        for (self.frames[0..self.n]) |f| s += f.wheel;
        return s;
    }

    /// 왼쪽 버튼이 선 `Frame`의 수. 물리 버튼을 안 쓰는 검사에서는 탭의 수다.
    fn lefts(self: *const Pad) usize {
        var k: usize = 0;
        for (self.frames[0..self.n]) |f| {
            if (f.buttons.left) k += 1;
        }
        return k;
    }

    fn moved(self: *const Pad) bool {
        for (self.frames[0..self.n]) |f| {
            if (f.dx != 0 or f.dy != 0) return true;
        }
        return false;
    }

    fn clear(self: *Pad) void {
        self.n = 0;
    }
};

/// ioctl 비트맵의 비트 `n`을 세운다(낮은 번호부터, `pointer.bitSet`의 짝).
fn setBit(map: []u8, n: usize) void {
    map[n / 8] |= @as(u8, 1) << @intCast(n % 8);
}

fn expectTrue(what: []const u8, ok: bool) !void {
    if (ok) {
        std.debug.print("touchpad_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s}\n", .{what});
    return error.CheckFailed;
}

fn expectInt(what: []const u8, got: i64, want: i64) !void {
    if (got == want) {
        std.debug.print("touchpad_test: {s} = {d} OK\n", .{ what, got });
        return;
    }
    std.debug.print("FAIL: {s} = {d}, want {d}\n", .{ what, got, want });
    return error.WrongNumber;
}

fn expectFrames(what: []const u8, p: *const Pad, want: []const pointer.Frame) !void {
    const got = p.frames[0..p.n];
    if (got.len == want.len) {
        var same = true;
        for (got, want) |g, w| {
            if (!std.meta.eql(g, w)) same = false;
        }
        if (same) {
            std.debug.print("touchpad_test: {s} OK\n", .{what});
            return;
        }
    }
    std.debug.print("FAIL: {s}: got {any}, want {any}\n", .{ what, got, want });
    return error.WrongFrames;
}

/// 한 손가락을 (500, 300)에 대고 `steps`번 (dx, dy)씩 민 뒤 뗀다. 한 번에
/// `step_ms`씩 흐른다. 되감기 도구의 `move`와 같은 모양이다.
fn swipe(p: *Pad, id: i32, steps: usize, dx: i32, dy: i32, step_ms: i64) void {
    p.down(0, id, 500, 300);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
    p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
    p.syn();
    var x: i32 = 500;
    var y: i32 = 300;
    for (0..steps) |_| {
        p.wait(step_ms);
        x += dx;
        y += dy;
        if (dx != 0) p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, x);
        if (dy != 0) p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
        p.syn();
    }
    p.wait(step_ms);
    p.up(0);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
    p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
    p.syn();
}

/// 두 손가락을 (400, 300) · (600, 300)에 대고 `steps`번 세로로 `dy`씩 민 뒤
/// 함께 뗀다. 되감기 도구의 `scroll`과 같은 모양이다.
fn twoFinger(p: *Pad, steps: usize, dy: i32) void {
    p.down(0, 10, 400, 300);
    p.down(1, 11, 600, 300);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
    p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 1);
    p.syn();
    var y: i32 = 300;
    for (0..steps) |_| {
        p.wait(8);
        y += dy;
        p.ev(c.EV_ABS, c.ABS_MT_SLOT, 0);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
        p.ev(c.EV_ABS, c.ABS_MT_SLOT, 1);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
        p.syn();
    }
    p.wait(8);
    p.up(0);
    p.up(1);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
    p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 0);
    p.syn();
}

/// 터치패드 디코더를 본다. 부팅도 fd도 안 쓴다(PD design 결정 3). 게이트의
/// 부팅 B가 같은 시나리오를 uinput으로 보고, 빨개졌을 때 이 검사가 "디코더냐
/// 배관이냐"를 가른다.
pub fn main() !void {
    // ── 검사 1: 어느 방식으로 읽나 ─────────────────────────────────────
    {
        var mt: pointer.Caps = .{};
        setBit(&mt.abs, c.ABS_MT_SLOT);
        setBit(&mt.abs, c.ABS_MT_POSITION_X);
        setBit(&mt.abs, c.ABS_MT_POSITION_Y);
        try expectTrue("MT slots and positions read as protocol B", touchpad.modeOf(&mt) == .mt);
        var st: pointer.Caps = .{};
        setBit(&st.abs, c.ABS_X);
        setBit(&st.abs, c.ABS_Y);
        try expectTrue("ABS_X and ABS_Y alone read as single touch", touchpad.modeOf(&st) == .st);
        var a: pointer.Caps = .{};
        setBit(&a.abs, c.ABS_MT_POSITION_X);
        setBit(&a.abs, c.ABS_MT_POSITION_Y);
        try expectTrue("MT positions without a slot and without ABS_X are not read", touchpad.modeOf(&a) == null);
    }

    // ── 검사 2: 한 손가락 이동의 배율 ───────────────────────────────────
    //
    // 가로 100단위(10단위씩 열 번)가 128픽셀이다 — 패드 가로 1000이 화면 가로
    // 1280이다. 10단위는 12.8픽셀이라 나머지를 넘겨야 합이 맞는다. 많이 움직였으니
    // 짧아도 탭이 아니다.
    {
        var p = Pad.init(PAD);
        swipe(&p, 1, 10, 10, 0, 8);
        try expectInt("one finger, 100 units across: dx", p.sumDx(), 128);
        try expectInt("one finger, 100 units across: dy", p.sumDy(), 0);
        try expectInt("a swipe of 100 units in 88ms is no tap", @intCast(p.lefts()), 0);

        // 세로 60단위는 64픽셀이다(16/15 배). 다시 닿은 손가락은 x만 알린다 —
        // 커널은 바뀐 값만 보내고 y는 직전 접촉의 300 그대로다. 디코더가 칸의
        // 옛 y를 지웠다면 여기서 튄다.
        p.clear();
        p.down(0, 2, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        try expectInt("a new contact moves nothing on its first report", @intCast(p.n), 0);
        var y: i32 = 300;
        for (0..6) |_| {
            p.wait(8);
            y += 10;
            p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
            p.syn();
        }
        try expectInt("one finger, 60 units down: dy (y follows the mm of x)", p.sumDy(), 64);
        try expectInt("one finger, 60 units down: dx", p.sumDx(), 0);
    }

    // ── 검사 3: 탭은 클릭이고, 긴 누름은 아무것도 아니다 ───────────────
    {
        var p = Pad.init(PAD);
        swipe(&p, 3, 0, 0, 0, 40);
        try expectFrames("a 40ms tap is a press and a release", &p, &.{
            .{ .buttons = .{ .left = true } },
            .{},
        });

        p.clear();
        swipe(&p, 4, 0, 0, 0, 500);
        try expectInt("a 500ms hold gives no frame", @intCast(p.n), 0);

        // 경계. 179ms는 탭이고 180ms는 아니다.
        p.clear();
        swipe(&p, 5, 0, 0, 0, 179);
        try expectInt("a 179ms touch is a tap", @intCast(p.lefts()), 1);
        p.clear();
        swipe(&p, 6, 0, 0, 0, 180);
        try expectInt("a 180ms touch is no tap", @intCast(p.lefts()), 0);
    }

    // ── 검사 4: 짧아도 많이 움직인 탭은 클릭이 아니다 ─────────────────
    //
    // 축 범위의 2%는 가로 20단위, 세로 12단위다. 20까지는 탭이고 21부터 아니다.
    {
        var p = Pad.init(PAD);
        swipe(&p, 7, 2, 10, 0, 8);
        try expectInt("a quick touch that drifts 20 units is still a tap", @intCast(p.lefts()), 1);
        try expectTrue("the drift still moved the pointer", p.moved());
        p.clear();
        swipe(&p, 8, 3, 7, 0, 8);
        try expectInt("a quick touch that drifts 21 units is no tap", @intCast(p.lefts()), 0);
        p.clear();
        swipe(&p, 9, 1, 0, 13, 8);
        try expectInt("a quick touch that drifts 13 units down is no tap", @intCast(p.lefts()), 0);
    }

    // ── 검사 5: 두 손가락 세로는 휠이고, 포인터는 안 움직인다 ───────────
    //
    // 90단위는 96픽셀이고 눈금은 48픽셀이라 둘이다. 손가락을 아래로 밀면 양수 —
    // 휠을 앞으로 민 것과 같은 쪽이다(내용이 손가락을 따라 내려간다).
    {
        var p = Pad.init(PAD);
        twoFinger(&p, 6, 15);
        try expectInt("two fingers, 90 units down: wheel", p.sumWheel(), 2);
        try expectTrue("two fingers never move the pointer", !p.moved());
        try expectInt("two fingers are no tap", @intCast(p.lefts()), 0);
        p.clear();
        twoFinger(&p, 6, -15);
        try expectInt("two fingers, 90 units up: wheel", p.sumWheel(), -2);

        // 칸은 하나만 찼는데 BTN_TOOL_DOUBLETAP이 둘이라고 하는 장치. 손가락 수는
        // 둘이고, 있는 접촉 하나의 변화로 스크롤한다.
        p.clear();
        p.down(0, 12, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 1);
        p.syn();
        var y: i32 = 300;
        for (0..6) |_| {
            p.wait(8);
            y += 15;
            p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
            p.syn();
        }
        try expectInt("DOUBLETAP with one slot filled still scrolls", p.sumWheel(), 2);
        try expectTrue("and does not move the pointer", !p.moved());
    }

    // ── 검사 6: 버튼을 누른 채 두 손가락이면 늦게 닿은 손가락이 끈다 ────
    //
    // 엄지(칸 0)로 clickpad를 누르고 검지(칸 1)로 끈다(design 결정 8). 스크롤로
    // 안 가고, 버튼은 그대로 통과한다.
    {
        var p = Pad.init(PAD);
        p.down(0, 20, 300, 500);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        p.wait(8);
        p.ev(c.EV_KEY, c.BTN_LEFT, 1);
        p.syn();
        try expectFrames("the physical button passes through", &p, &.{.{ .buttons = .{ .left = true } }});
        p.clear();
        p.wait(8);
        p.down(1, 21, 600, 300);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 1);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_SLOT, 1);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 650);
        p.syn();
        try expectFrames("the later finger drags with the button held", &p, &.{
            .{ .dx = 64, .buttons = .{ .left = true } },
        });
        p.clear();
        p.wait(8);
        p.ev(c.EV_KEY, c.BTN_LEFT, 0);
        p.syn();
        p.wait(8);
        p.up(0);
        p.up(1);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 0);
        p.syn();
        try expectFrames("letting go releases the button and is no tap", &p, &.{.{}});
    }

    // ── 검사 7: SYN_DROPPED 뒤에는 모두 뗀 것으로 하고 새로 센다 ─────────
    {
        var p = Pad.init(PAD);
        p.down(0, 30, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.ev(c.EV_KEY, c.BTN_LEFT, 1);
        p.syn();
        p.clear();
        p.ev(c.EV_SYN, c.SYN_DROPPED, 0);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 900);
        p.ev(c.EV_KEY, c.BTN_LEFT, 0);
        p.syn();
        try expectFrames("the report after SYN_DROPPED releases the held button", &p, &.{.{}});
        p.clear();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 950);
        p.syn();
        try expectInt("a finger still down from before the drop moves nothing", @intCast(p.n), 0);
        p.wait(8);
        p.up(0);
        p.syn();
        p.wait(8);
        p.down(0, 31, 500, 300);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 550);
        p.syn();
        try expectFrames("a new contact after the drop moves again", &p, &.{.{ .dx = 64 }});
    }

    // ── 검사 8: 두 손가락 탭은 클릭이 아니다(비목표 6) ──────────────────
    {
        var p = Pad.init(PAD);
        twoFinger(&p, 0, 0);
        try expectInt("a quick two-finger touch gives no frame", @intCast(p.n), 0);
    }

    // ── 검사 9: 단일 터치 장치 ──────────────────────────────────────────
    //
    // `ABS_X` · `ABS_Y`와 `BTN_TOUCH`만 있다. 칸 0 하나로 이동과 탭이 된다.
    {
        var st = PAD;
        st.mode = .st;
        var p = Pad.init(st);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.ev(c.EV_ABS, c.ABS_X, 500);
        p.ev(c.EV_ABS, c.ABS_Y, 300);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_X, 550);
        p.syn();
        p.wait(8);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
        p.syn();
        try expectFrames("single touch: 50 units across, then no tap", &p, &.{.{ .dx = 64 }});
        p.clear();
        p.wait(100);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        p.wait(40);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
        p.syn();
        try expectInt("single touch: a 40ms touch is a tap", @intCast(p.lefts()), 1);
    }

    // ── 검사 10: 범위 밖의 칸은 버린다 ──────────────────────────────────
    {
        var p = Pad.init(PAD);
        p.down(7, 40, 100, 100);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 300);
        p.syn();
        try expectInt("events for slot 7 of a two-slot pad are dropped", @intCast(p.n), 0);
        p.down(0, 41, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 550);
        p.syn();
        try expectFrames("slot 0 still works after a stray slot", &p, &.{.{ .dx = 64 }});
    }

    std.debug.print("touchpad_test: all checks passed\n", .{});
}
```

### 3-2. `build.zig` — 등록

`pointer_test`와 같은 모양이다. 편집 둘.

편집 1 — `old_string`(기준 파일 301줄부터):

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

`new_string`:

```zig
    // touchpad_test도 호스트에서 돈다(PD-M3). `pointer_test`와 같은 자리다 —
    // `touchpad.zig`가 `pointer.zig`를 통해 `c_input`을 쓰므로 libc가 따라온다.
    // 슬롯 · 배율 · 탭 · 두 손가락 스크롤의 판단만 보고 fd는 안 연다.
    const touchpad_test_mod = b.createModule(.{
        .root_source_file = b.path("src/touchpad_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    touchpad_test_mod.link_libc = true;
    touchpad_test_mod.addImport("c_input", c_input_host.mod);
    const touchpad_test = b.addExecutable(.{
        .name = "touchpad_test",
        .root_module = touchpad_test_mod,
    });
    b.installArtifact(touchpad_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

편집 2 — `old_string`(기준 파일 316줄부터):

```zig
    test_step.dependOn(&b.addRunArtifact(pointer_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(pointer_test).step);
    test_step.dependOn(&b.addRunArtifact(touchpad_test).step);
```

### 3-3. 확인

```bash
diff terminal/src/touchpad.zig /tmp/run/pdm3/new/terminal/src/touchpad.zig && echo SAME-tp
diff terminal/src/touchpad_test.zig /tmp/run/pdm3/new/terminal/src/touchpad_test.zig && echo SAME-tpt
diff terminal/build.zig /tmp/run/pdm3/new/terminal/build.zig && echo SAME-build
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -c "^touchpad_test: .* OK$" /tmp/t.out
  grep -a -E "^touchpad_test: all checks passed|^FAIL" /tmp/t.out'
```

기대: `SAME` 셋, `exit=0`, OK 34, `touchpad_test: all checks passed`. `FAIL` 0줄.

## Task 4: `terminal/src/main.zig` — 편집 아홉

확정 3의 배선이다. 순서대로 넣는다.

E1 — `old_string`(기준 파일 10줄부터):

```zig
const status = @import("status.zig");
```

`new_string`:

```zig
const status = @import("status.zig");
const touchpad = @import("touchpad.zig");
```

E2 — `old_string`(기준 파일 1456줄부터):

```zig
    mouse: pointer.Mouse = .{},
```

`new_string`:

```zig
    /// 분류가 고른 디코더(PD-M3). 둘의 출력이 같은 `Frame`이라 이 칸 아래의
    /// `Pointer` · `Gesture`는 어느 쪽인지 모른다(design 결정 8).
    decoder: union(pointer.Kind) {
        mouse: pointer.Mouse,
        touchpad: touchpad.Touchpad,
        none: void,
    },
```

E3 — `old_string`(기준 파일 1459줄부터):

```zig
        return self.path[0..self.path_len];
    }
};
```

`new_string`:

```zig
        return self.path[0..self.path_len];
    }

    /// 이벤트 하나를 디코더에 먹인다. 마우스는 `SYN_REPORT`에 `Frame` 하나,
    /// 터치패드는 탭이 끝난 `SYN_REPORT`에만 둘(누름 · 뗌)이다.
    fn feed(self: *PointerDev, ev: *align(1) const pointer.c.struct_input_event) touchpad.Frames {
        return switch (self.decoder) {
            .mouse => |*m| if (m.feed(ev.type, ev.code, ev.value)) |f| touchpad.Frames.one(f) else touchpad.Frames{},
            .touchpad => |*t| t.feed(ev.type, ev.code, ev.value, @as(i64, ev.time.tv_sec) * 1_000_000 + @as(i64, ev.time.tv_usec)),
            .none => touchpad.Frames{},
        };
    }
};

/// 터치패드 디코더가 쓰는 화면 값(PD-M3). 프레임버퍼를 연 뒤 처음 훑기 전에
/// 한 번 정한다. `pointer_drawn`과 같은 이유로 파일 하나의 값이다 — 장치를
/// 여는 자리(처음 훑기 · 핫플러그)가 여럿이라 인자로 나르지 않는다.
var touchpad_screen: touchpad.Screen = .{ .w = 1, .notch_px = 1 };
```

E4 — `old_string`(기준 파일 1570줄부터):

```zig
/// PD-M0은 마우스만 연다. 분류가 `touchpad`를 내도 `skip`이다 — 터치패드
/// 디코더는 PD-M3이 더한다.
```

`new_string`:

```zig
/// 터치패드면 축 범위를 `EVIOCGABS`로 읽어 디코더를 만들고(PD-M3), `open`
/// 줄에 칸 수 · 축 · resolution을 함께 찍는다. 실기에서 배율이 손에 안 맞을 때
/// 그 줄이 첫 단서다(design "실기에서 같은 코드로 가는가").
```

E5 — `old_string`(기준 파일 1596줄부터):

```zig
    if (kind != .mouse) {
        std.debug.print("terminal: pointer> skip {s} kind={s} name={s}\n", .{ path, @tagName(kind), dev_name });
        _ = std.c.close(fd);
        return;
```

`new_string`:

```zig
    if (kind == .none) {
        std.debug.print("terminal: pointer> skip {s} kind={s} name={s}\n", .{ path, @tagName(kind), dev_name });
        _ = std.c.close(fd);
        return;
    }
    var pad: ?touchpad.Setup = null;
    if (kind == .touchpad) {
        pad = readPad(fd, &caps) orelse {
            std.debug.print("terminal: pointer> skip {s} kind=touchpad error=axes name={s}\n", .{ path, dev_name });
            _ = std.c.close(fd);
            return;
        };
```

E6 — `old_string`(기준 파일 1608줄부터):

```zig
    devs[free] = .{ .fd = fd, .path = undefined, .path_len = path.len };
```

`new_string`:

```zig
    devs[free] = .{
        .fd = fd,
        .path = undefined,
        .path_len = path.len,
        .decoder = if (pad) |setup| .{ .touchpad = touchpad.Touchpad.init(setup, touchpad_screen) } else .{ .mouse = .{} },
    };
```

E7 — `old_string`(기준 파일 1613줄부터):

```zig
    std.debug.print("terminal: pointer> open {s} kind=mouse shown={d} name={s}\n", .{ path, @intFromBool(pointer_drawn), dev_name });
```

`new_string`:

```zig
    if (pad) |setup| {
        std.debug.print("terminal: pointer> open {s} kind=touchpad slots={d} x={d}..{d} y={d}..{d} res={d},{d} shown={d} name={s}\n", .{
            path,        setup.slots, setup.x.min,                 setup.x.max, setup.y.min, setup.y.max,
            setup.x.res, setup.y.res, @intFromBool(pointer_drawn), dev_name,
        });
    } else {
        std.debug.print("terminal: pointer> open {s} kind=mouse shown={d} name={s}\n", .{ path, @intFromBool(pointer_drawn), dev_name });
    }
}

/// 터치패드의 축 범위를 읽는다(PD-M3). MT 프로토콜 B면 `ABS_MT_POSITION_X/Y`와
/// `ABS_MT_SLOT`(max + 1이 칸 수, value가 지금 칸), 아니면 `ABS_X/Y`다. 하나라도
/// 실패하거나 읽을 축이 없으면 null이다 — 배율을 모르는 패드는 열지 않는다.
fn readPad(fd: c_int, caps: *const pointer.Caps) ?touchpad.Setup {
    const mode = touchpad.modeOf(caps) orelse return null;
    return switch (mode) {
        .mt => blk: {
            const x = readAbs(fd, pointer.c.ABS_MT_POSITION_X) orelse return null;
            const y = readAbs(fd, pointer.c.ABS_MT_POSITION_Y) orelse return null;
            const s = readAbs(fd, pointer.c.ABS_MT_SLOT) orelse return null;
            break :blk .{
                .mode = .mt,
                .x = .{ .min = x.minimum, .max = x.maximum, .res = x.resolution },
                .y = .{ .min = y.minimum, .max = y.maximum, .res = y.resolution },
                .slots = @intCast(@min(@max(s.maximum, 0), touchpad.MAX_SLOTS - 1) + 1),
                .slot = @intCast(@max(s.value, 0)),
            };
        },
        .st => blk: {
            const x = readAbs(fd, pointer.c.ABS_X) orelse return null;
            const y = readAbs(fd, pointer.c.ABS_Y) orelse return null;
            break :blk .{
                .mode = .st,
                .x = .{ .min = x.minimum, .max = x.maximum, .res = x.resolution },
                .y = .{ .min = y.minimum, .max = y.maximum, .res = y.resolution },
            };
        },
    };
}

fn readAbs(fd: c_int, comptime code: u16) ?pointer.c.struct_input_absinfo {
    var info: pointer.c.struct_input_absinfo = undefined;
    if (ioctl(fd, pointer.eviocgabs(code), &info) < 0) return null;
    return info;
```

E8 — `old_string`(기준 파일 1675줄부터):

```zig
            const frame = dev.mouse.feed(ev.type, ev.code, ev.value) orelse continue;
            const e = state.apply(slot, frame);
            round.frames += 1;
            round.wheel +|= e.wheel;
            if (e.moved or e.pressed.bits() != 0) round.woke = true;
            // 왼쪽 버튼의 전이는 그 순간의 자리와 함께 순서대로 담는다(PD-M2).
            // 한 회차에 누르고 끌고 떼는 보고가 다 들어와도 순서가 남는다.
            if ((e.pressed.left or e.released.left) and round.edge_count < MAX_EDGES) {
                round.edges[round.edge_count] = .{ .down = e.pressed.left, .x = state.x, .y = state.y };
                round.edge_count += 1;
```

`new_string`:

```zig
            // 터치패드의 탭은 한 이벤트에 `Frame` 둘(누름 · 뗌)이다(PD-M3).
            // 둘 다 아래를 차례로 지나므로 전이 칸에 누름과 뗌이 함께 담긴다.
            const frames = dev.feed(ev);
            for (frames.slice()) |frame| {
                const e = state.apply(slot, frame);
                round.frames += 1;
                round.wheel +|= e.wheel;
                if (e.moved or e.pressed.bits() != 0) round.woke = true;
                // 왼쪽 버튼의 전이는 그 순간의 자리와 함께 순서대로 담는다(PD-M2).
                // 한 회차에 누르고 끌고 떼는 보고가 다 들어와도 순서가 남는다.
                if ((e.pressed.left or e.released.left) and round.edge_count < MAX_EDGES) {
                    round.edges[round.edge_count] = .{ .down = e.pressed.left, .x = state.x, .y = state.y };
                    round.edge_count += 1;
                }
```

E9 — `old_string`(기준 파일 2159줄부터):

```zig
    scanPointers(init.io, &pointer_devs);
```

`new_string`:

```zig
    // 터치패드의 배율과 휠 눈금(PD-M3). 패드 가로 전체가 프레임버퍼 가로이고,
    // 두 손가락이 휠 한 눈금의 줄 수만큼 움직이면 한 눈금이다 — 손가락과 글자가
    // 같은 거리를 간다. 처음 훑기보다 먼저 정해야 부팅 때 있던 패드도 이 값을 쓴다.
    touchpad_screen = .{ .w = fb.width, .notch_px = ROW_HEIGHT * @as(u32, @intCast(WHEEL_ROWS)) };
    scanPointers(init.io, &pointer_devs);
```

### 4-10. 확인

```bash
diff terminal/src/main.zig /tmp/run/pdm3/new/terminal/src/main.zig && echo SAME-main
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | rg '^-[^-]'
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  ./prepare.sh > /tmp/p.out 2>&1; echo "prepare exit=$?"; tail -2 /tmp/p.out'
```

기대: `SAME-main`, `1 file changed, 103 insertions(+), 16 deletions(-)`, 지운 줄은 아래 16줄이 전부다. `prepare exit=0`.

```
-    mouse: pointer.Mouse = .{},
-/// PD-M0은 마우스만 연다. 분류가 `touchpad`를 내도 `skip`이다 — 터치패드
-/// 디코더는 PD-M3이 더한다.
-    if (kind != .mouse) {
-    devs[free] = .{ .fd = fd, .path = undefined, .path_len = path.len };
-    std.debug.print("terminal: pointer> open {s} kind=mouse shown={d} name={s}\n", .{ path, @intFromBool(pointer_drawn), dev_name });
-            const frame = dev.mouse.feed(ev.type, ev.code, ev.value) orelse continue;
-            const e = state.apply(slot, frame);
-            round.frames += 1;
-            round.wheel +|= e.wheel;
-            if (e.moved or e.pressed.bits() != 0) round.woke = true;
-            // 왼쪽 버튼의 전이는 그 순간의 자리와 함께 순서대로 담는다(PD-M2).
-            // 한 회차에 누르고 끌고 떼는 보고가 다 들어와도 순서가 남는다.
-            if ((e.pressed.left or e.released.left) and round.edge_count < MAX_EDGES) {
-                round.edges[round.edge_count] = .{ .down = e.pressed.left, .x = state.x, .y = state.y };
-                round.edge_count += 1;
```

## Task 5: `pointer/replay/` — 새 파일 둘

확정 7의 도구다.

```bash
mkdir -p pointer/replay
cp /tmp/run/pdm3/new/pointer/replay/build.zig /tmp/run/pdm3/new/pointer/replay/main.zig pointer/replay/
```

`pointer/replay/build.zig`:

```zig
const std = @import("std");

// PD-M3: 게이트 전용 되감기 도구. 제품 initrd에는 안 들어간다 — pointer 체인이
// 빌드해 부팅 B의 설정 디스크에 싣는다(PD design 결정 10).
//
// 타깃 · 모드 · libc 없음은 init/build.zig와 같다. 게스트는 언제나 x86_64이고,
// libc를 링크하지 않으면 정적 바이너리라 디스크에 .so를 함께 실을 일이 없다.
pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
        .cpu_model = .baseline,
    });
    const mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const exe = b.addExecutable(.{
        .name = "tp-replay",
        .root_module = mod,
    });
    b.installArtifact(exe);
}
```

`pointer/replay/main.zig`:

```zig
//! PD-M3의 게이트 전용 되감기 도구 `tp-replay`(PD design 결정 10).
//!
//! `/dev/uinput`으로 가짜 터치패드 하나를 만들고, stdin에서 한 줄씩 명령을 받아
//! 그 손동작의 이벤트를 쓴다. 커널의 입력 core가 진짜 드라이버의 이벤트와 같은
//! 길로 evdev 노드에 내보내므로, terminal은 이 장치를 부팅 뒤에 꽂힌 터치패드로
//! 본다 — uevent로 알고, ioctl로 분류하고, 축 범위를 읽고, 디코더에 먹인다.
//!
//!   move DX DY   한 손가락을 패드 가운데에 대고 (DX, DY) 단위만큼 10단위씩
//!                8ms 간격으로 민 뒤 뗀다
//!   tap          가운데에 40ms 대었다 뗀다
//!   hold         가운데에 500ms 대었다 뗀다
//!   scroll DY    두 손가락을 대고 함께 세로로 DY 단위만큼 15단위씩 민 뒤 뗀다
//!   quit         장치를 없애고 끝난다(stdin이 끝나도 같다)
//!
//! 이벤트의 시각은 커널이 주입하는 순간에 찍으므로 탭의 길이는 이 도구가 자는
//! 시간이 정한다. 명령을 마친 뒤에는 아무것도 찍지 않는다 — 출력이 패널에 오면
//! 그 패널이 바닥으로 돌아가 스크롤 검사가 흔들린다.
//!
//! 제품 initrd에는 없다. pointer 체인이 빌드해 설정 디스크의 `pd/tp-replay`로
//! 싣고 게스트 셸에서 친다.
const std = @import("std");
const linux = std.os.linux;

// linux/uinput.h의 요청 번호. `_IOW('U', nr, T)`는 (1 << 30) | (sizeof T << 16) |
// ('U' << 8) | nr이다. 번역(translate-c)을 안 쓰는 이유는 이 도구가 init처럼 libc
// 없이 빌드되고 번역 패키지에 기대지 않아서다. 값은 PD-M3 plan 확정 7이 컨테이너의
// 헤더를 C로 컴파일해 대조했다.
const UI_DEV_CREATE: u32 = 0x5501;
const UI_DEV_DESTROY: u32 = 0x5502;
const UI_DEV_SETUP: u32 = 0x405c5503;
const UI_ABS_SETUP: u32 = 0x401c5504;
const UI_SET_EVBIT: u32 = 0x40045564;
const UI_SET_KEYBIT: u32 = 0x40045565;
const UI_SET_ABSBIT: u32 = 0x40045567;
const UI_SET_PROPBIT: u32 = 0x4004556e;

// linux/input-event-codes.h · linux/input.h의 값.
const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const EV_ABS: u16 = 0x03;
const SYN_REPORT: u16 = 0;
const BTN_LEFT: u16 = 0x110;
const BTN_TOOL_FINGER: u16 = 0x145;
const BTN_TOUCH: u16 = 0x14a;
const BTN_TOOL_DOUBLETAP: u16 = 0x14d;
const BTN_TOOL_TRIPLETAP: u16 = 0x14e;
const ABS_X: u16 = 0x00;
const ABS_Y: u16 = 0x01;
const ABS_MT_SLOT: u16 = 0x2f;
const ABS_MT_POSITION_X: u16 = 0x35;
const ABS_MT_POSITION_Y: u16 = 0x36;
const ABS_MT_TRACKING_ID: u16 = 0x39;
const INPUT_PROP_POINTER: u16 = 0x00;
const INPUT_PROP_BUTTONPAD: u16 = 0x02;
const BUS_VIRTUAL: u16 = 0x06;

const InputId = extern struct { bustype: u16, vendor: u16, product: u16, version: u16 };
const DevSetup = extern struct { id: InputId, name: [80]u8, ff_effects_max: u32 };
const AbsInfo = extern struct { value: i32 = 0, minimum: i32, maximum: i32, fuzz: i32 = 0, flat: i32 = 0, resolution: i32 = 0 };
const AbsSetup = extern struct { code: u16, absinfo: AbsInfo };
/// `struct input_event`. x86_64에서 시각은 `long` 둘이다. uinput은 쓰는 쪽의
/// 시각을 버리고 커널이 다시 찍는다.
const Event = extern struct { sec: i64 = 0, usec: i64 = 0, type: u16, code: u16, value: i32 };

comptime {
    std.debug.assert(@sizeOf(DevSetup) == 92);
    std.debug.assert(@sizeOf(AbsSetup) == 28);
    std.debug.assert(@sizeOf(Event) == 24);
}

/// 패드의 축. `touchpad_test`의 `PAD`와 같다 — 세로의 resolution이 가로와 달라서
/// terminal이 세로를 같은 mm당 픽셀로 맞추는지가 좌표로 보인다.
const PAD_W = 1000;
const PAD_H = 600;
const RES_X = 10;
const RES_Y = 12;
const CX = 500;
const CY = 300;
const NAME = "TARS Replay Touchpad";

const STEP_MS: u64 = 8;
const MOVE_STEP: i32 = 10;
const SCROLL_STEP: i32 = 15;
const TAP_MS: u64 = 40;
const HOLD_MS: u64 = 500;

fn writeAll(fd: i32, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        switch (linux.errno(n)) {
            .SUCCESS => off += n,
            .INTR => continue,
            else => return false,
        }
    }
    return true;
}

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tp-replay: " ++ fmt ++ "\n", args) catch return;
    _ = writeAll(2, text);
}

fn sleepMs(ms: u64) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

fn ioctl(fd: i32, request: u32, arg: usize) bool {
    return linux.errno(linux.ioctl(fd, request, arg)) == .SUCCESS;
}

/// 한 묶음(`SYN_REPORT`까지)의 이벤트를 모아 한 번에 쓴다.
const Batch = struct {
    evs: [24]Event = undefined,
    n: usize = 0,

    fn add(self: *Batch, ev_type: u16, code: u16, value: i32) void {
        self.evs[self.n] = .{ .type = ev_type, .code = code, .value = value };
        self.n += 1;
    }

    fn send(self: *Batch, fd: i32) bool {
        self.add(EV_SYN, SYN_REPORT, 0);
        const bytes = std.mem.sliceAsBytes(self.evs[0..self.n]);
        self.n = 0;
        return writeAll(fd, bytes);
    }
};

const Pad = struct {
    fd: i32,
    next_id: i32 = 1,

    fn create() ?Pad {
        const rc = linux.open("/dev/uinput", .{ .ACCMODE = .WRONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
        if (linux.errno(rc) != .SUCCESS) {
            say("cannot open /dev/uinput (errno {d})", .{@intFromEnum(linux.errno(rc))});
            return null;
        }
        const fd: i32 = @intCast(rc);
        var ok = ioctl(fd, UI_SET_EVBIT, EV_KEY) and ioctl(fd, UI_SET_EVBIT, EV_ABS);
        for ([_]u16{ BTN_LEFT, BTN_TOOL_FINGER, BTN_TOUCH, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP }) |k| {
            ok = ok and ioctl(fd, UI_SET_KEYBIT, k);
        }
        for ([_]u16{ INPUT_PROP_POINTER, INPUT_PROP_BUTTONPAD }) |p| {
            ok = ok and ioctl(fd, UI_SET_PROPBIT, p);
        }
        const axes = [_]AbsSetup{
            .{ .code = ABS_X, .absinfo = .{ .minimum = 0, .maximum = PAD_W, .resolution = RES_X } },
            .{ .code = ABS_Y, .absinfo = .{ .minimum = 0, .maximum = PAD_H, .resolution = RES_Y } },
            .{ .code = ABS_MT_SLOT, .absinfo = .{ .minimum = 0, .maximum = 1 } },
            .{ .code = ABS_MT_POSITION_X, .absinfo = .{ .minimum = 0, .maximum = PAD_W, .resolution = RES_X } },
            .{ .code = ABS_MT_POSITION_Y, .absinfo = .{ .minimum = 0, .maximum = PAD_H, .resolution = RES_Y } },
            .{ .code = ABS_MT_TRACKING_ID, .absinfo = .{ .minimum = 0, .maximum = 65535 } },
        };
        for (&axes) |*a| {
            ok = ok and ioctl(fd, UI_SET_ABSBIT, a.code) and ioctl(fd, UI_ABS_SETUP, @intFromPtr(a));
        }
        var setup: DevSetup = .{
            .id = .{ .bustype = BUS_VIRTUAL, .vendor = 0x7a35, .product = 0x0003, .version = 1 },
            .name = @splat(0),
            .ff_effects_max = 0,
        };
        @memcpy(setup.name[0..NAME.len], NAME);
        ok = ok and ioctl(fd, UI_DEV_SETUP, @intFromPtr(&setup)) and ioctl(fd, UI_DEV_CREATE, 0);
        if (!ok) {
            say("uinput setup failed", .{});
            _ = linux.close(fd);
            return null;
        }
        return .{ .fd = fd };
    }

    fn destroy(self: *Pad) void {
        _ = ioctl(self.fd, UI_DEV_DESTROY, 0);
        _ = linux.close(self.fd);
    }

    fn id(self: *Pad) i32 {
        const v = self.next_id;
        self.next_id = if (v >= 65535) 1 else v + 1;
        return v;
    }

    /// 한 손가락을 (x, y)에 댄다. 커널의 터치패드 드라이버처럼 포인터 흉내
    /// (`ABS_X` · `ABS_Y`)와 `BTN_TOUCH` · `BTN_TOOL_FINGER`를 함께 낸다.
    fn touch1(self: *Pad, x: i32, y: i32) bool {
        var b: Batch = .{};
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, self.id());
        b.add(EV_ABS, ABS_MT_POSITION_X, x);
        b.add(EV_ABS, ABS_MT_POSITION_Y, y);
        b.add(EV_ABS, ABS_X, x);
        b.add(EV_ABS, ABS_Y, y);
        b.add(EV_KEY, BTN_TOUCH, 1);
        b.add(EV_KEY, BTN_TOOL_FINGER, 1);
        return b.send(self.fd);
    }

    fn lift1(self: *Pad) bool {
        var b: Batch = .{};
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, -1);
        b.add(EV_KEY, BTN_TOUCH, 0);
        b.add(EV_KEY, BTN_TOOL_FINGER, 0);
        return b.send(self.fd);
    }

    fn move(self: *Pad, dx: i32, dy: i32) bool {
        if (!self.touch1(CX, CY)) return false;
        const steps: i32 = @max(1, @divTrunc(@max(abs(dx), abs(dy)) + MOVE_STEP - 1, MOVE_STEP));
        var i: i32 = 1;
        while (i <= steps) : (i += 1) {
            sleepMs(STEP_MS);
            const x = CX + @divTrunc(dx * i, steps);
            const y = CY + @divTrunc(dy * i, steps);
            var b: Batch = .{};
            b.add(EV_ABS, ABS_MT_POSITION_X, x);
            b.add(EV_ABS, ABS_MT_POSITION_Y, y);
            b.add(EV_ABS, ABS_X, x);
            b.add(EV_ABS, ABS_Y, y);
            if (!b.send(self.fd)) return false;
        }
        sleepMs(STEP_MS);
        return self.lift1();
    }

    fn press(self: *Pad, ms: u64) bool {
        if (!self.touch1(CX, CY)) return false;
        sleepMs(ms);
        return self.lift1();
    }

    fn scroll(self: *Pad, dy: i32) bool {
        const x0 = CX - 100;
        const x1 = CX + 100;
        var b: Batch = .{};
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, self.id());
        b.add(EV_ABS, ABS_MT_POSITION_X, x0);
        b.add(EV_ABS, ABS_MT_POSITION_Y, CY);
        b.add(EV_ABS, ABS_MT_SLOT, 1);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, self.id());
        b.add(EV_ABS, ABS_MT_POSITION_X, x1);
        b.add(EV_ABS, ABS_MT_POSITION_Y, CY);
        b.add(EV_ABS, ABS_X, x0);
        b.add(EV_ABS, ABS_Y, CY);
        b.add(EV_KEY, BTN_TOUCH, 1);
        b.add(EV_KEY, BTN_TOOL_DOUBLETAP, 1);
        if (!b.send(self.fd)) return false;
        const steps: i32 = @max(1, @divTrunc(abs(dy) + SCROLL_STEP - 1, SCROLL_STEP));
        var i: i32 = 1;
        while (i <= steps) : (i += 1) {
            sleepMs(STEP_MS);
            const y = CY + @divTrunc(dy * i, steps);
            b.add(EV_ABS, ABS_MT_SLOT, 0);
            b.add(EV_ABS, ABS_MT_POSITION_Y, y);
            b.add(EV_ABS, ABS_MT_SLOT, 1);
            b.add(EV_ABS, ABS_MT_POSITION_Y, y);
            b.add(EV_ABS, ABS_Y, y);
            if (!b.send(self.fd)) return false;
        }
        sleepMs(STEP_MS);
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, -1);
        b.add(EV_ABS, ABS_MT_SLOT, 1);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, -1);
        b.add(EV_KEY, BTN_TOUCH, 0);
        b.add(EV_KEY, BTN_TOOL_DOUBLETAP, 0);
        return b.send(self.fd);
    }
};

fn abs(v: i32) i32 {
    return if (v < 0) -v else v;
}

/// 한 줄을 실행한다. 끝내야 하면 false다.
fn run(pad: *Pad, line: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    const verb = it.next() orelse return true;
    const a = if (it.next()) |t| std.fmt.parseInt(i32, t, 10) catch null else null;
    const b = if (it.next()) |t| std.fmt.parseInt(i32, t, 10) catch null else null;
    const ok = if (std.mem.eql(u8, verb, "move"))
        pad.move(a orelse 0, b orelse 0)
    else if (std.mem.eql(u8, verb, "tap"))
        pad.press(TAP_MS)
    else if (std.mem.eql(u8, verb, "hold"))
        pad.press(HOLD_MS)
    else if (std.mem.eql(u8, verb, "scroll"))
        pad.scroll(a orelse 0)
    else if (std.mem.eql(u8, verb, "quit"))
        return false
    else blk: {
        say("unknown command '{s}'", .{verb});
        break :blk true;
    };
    if (!ok) say("writing to /dev/uinput failed during '{s}'", .{verb});
    return ok;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    _ = init;
    var pad = Pad.create() orelse return 1;
    defer pad.destroy();
    _ = writeAll(1, "tp-replay: ready\n");

    var buf: [512]u8 = undefined;
    var len: usize = 0;
    while (true) {
        if (len == buf.len) len = 0; // 줄이 너무 길면 버린다
        const n = linux.read(0, buf[len..].ptr, buf.len - len);
        switch (linux.errno(n)) {
            .SUCCESS => {},
            .INTR => continue,
            else => return 1,
        }
        if (n == 0) return 0;
        len += n;
        while (std.mem.indexOfScalar(u8, buf[0..len], '\n')) |nl| {
            const keep = run(&pad, buf[0..nl]);
            std.mem.copyForwards(u8, buf[0 .. len - nl - 1], buf[nl + 1 .. len]);
            len -= nl + 1;
            if (!keep) return 0;
        }
    }
}
```

확인.

```bash
diff -r pointer/replay /tmp/run/pdm3/new/pointer/replay && echo SAME-replay
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd pointer/replay && zig build --prefix /workspace/out/pd-replay --cache-dir /workspace/out/pd-replay/cache; echo "exit=$?"
  file /workspace/out/pd-replay/bin/tp-replay
  ls pointer/replay 2>/dev/null || ls'
git status --short pointer/
```

기대: `SAME-replay`, `exit=0`, `ELF 64-bit LSB executable, x86-64, … statically linked`, `pointer/replay`에 `build.zig` ·
`main.zig` 둘만 있다(캐시 디렉터리가 안 생겼다). `git status`는 `?? pointer/replay/`와 `M pointer/check.sh`(Task 6 뒤)다.

## Task 6: `pointer/check.sh` · `check.sh`

### 6-1. `pointer/check.sh` — 편집 일곱

머리 주석 둘 · 도구 빌드와 포트 · 표식 · 검사 19와 부팅 A의 `i8042.noaux` · 부팅 B 전체다.

편집 1 — `old_string`(기준 파일 6줄부터):

```bash
# PD 체인 — 포인터 장치(PD-M0~M2). 열아홉번째 체인.
```

`new_string`:

```bash
# PD 체인 — 포인터 장치(PD-M0~M3). 열아홉번째 체인.
```

편집 2 — `old_string`(기준 파일 22줄부터):

```bash
#     들어간다. 입력 모드도 함께 돌아와 그다음 친 글자가 셸에 간다(PD-M2)
```

`new_string`:

```bash
#     들어간다. 입력 모드도 함께 돌아와 그다음 친 글자가 셸에 간다(PD-M2)
#   → 커널에 노트북 터치패드의 세 경로(PS/2 · SMBus · I2C-HID)와 uinput이
#     켜져 있고 드라이버가 등록됐다(PD-M3, 부팅 전과 부팅 B)
#   → psmouse가 QEMU의 PS/2 마우스를 잡고 terminal이 그것을 마우스로 연다(부팅 B)
#   → 설정 디스크의 tp-replay가 uinput으로 터치패드를 만들면 terminal이 터치패드로
#     열고, 한 손가락 이동 · 탭 · 두 손가락 세로가 포인터 이동 · 클릭 · 휠이 된다
#     (부팅 B)
#
# 부팅이 둘이다. 부팅 A(PD-M0~M2)는 USB 마우스 하나만 보도록 커널 cmdline에
# i8042.noaux를 준다 — PD-M3부터 커널이 PS/2 마우스를 알아서, 그것이 없으면
# 검사 1의 "정확히 하나"와 검사 9의 둘째("마지막 장치가 빠지면 숨는다")가 PS/2
# 마우스 때문에 성립하지 않는다(PD-M3 plan 확정 9). 부팅 B(PD-M3)는 cmdline을
# 그대로 두고 설정 디스크를 물린다.
```

편집 3 — `old_string`(기준 파일 89줄부터):

```bash
# 열여덟 체인이 45455~45487을 쓴다. 45489는 PD-M3의 부팅 B 몫이다(design 결정 10).
MONITOR_PORT=45488

REPO_ROOT="$(cd .. && pwd)"
```

`new_string`:

```bash
# 열여덟 체인이 45455~45487을 쓴다. 45489는 부팅 B의 몫이다(design 결정 10).
MONITOR_PORT=45488
MONITOR_PORT_B=45489

REPO_ROOT="$(cd .. && pwd)"

# 부팅 B의 되감기 도구(PD-M3). 제품이 아니라 게이트 전용이라 initrd가 아니라
# 설정 디스크에 싣는다(design 결정 10, wifi 체인의 hostapd와 같은 이유). 산출물과
# 캐시를 out/ 아래에 두므로 .gitignore도 clean()도 고칠 일이 없다.
REPLAY_OUT="${REPO_ROOT}/out/pd-replay"
if ! (cd replay && zig build --prefix "$REPLAY_OUT" --cache-dir "${REPLAY_OUT}/cache"); then
  echo "FAIL: tp-replay build failed"
  exit 1
fi
REPLAY="${REPLAY_OUT}/bin/tp-replay"
```

편집 4 — `old_string`(기준 파일 139줄부터):

```bash
    "terminal: pointer> scan failed"; do
```

`new_string`:

```bash
    "terminal: pointer> scan failed" \
    "kind=touchpad" \
    "tp-replay:"; do
```

편집 5 — `old_string`(기준 파일 405줄부터):

```bash
qemu-system-x86_64 \
```

`new_string`:

```bash
# ── 검사 19: 커널이 노트북 터치패드의 세 경로를 안다 (부팅 없음) ────────
#
# QEMU에는 터치패드가 없다(design 실측 7). 그래서 실칩 드라이버는 세 겹으로
# 본다(design 결정 9) — 여기서 심볼과 커널의 장치 표(modinfo alias)를, 부팅 B에서
# 드라이버가 실제로 등록됐는지를. 심볼은 켜졌는데 의존 관계로 빌드에서 빠진
# 경우를 셋째 겹이 잡는다. 켜지 않기로 한 것(Apple 쪽 · mousedev)도 본다.
CONFIG=../kernel/.config
for sym in INPUT_MOUSE MOUSE_PS2 MOUSE_PS2_SYNAPTICS MOUSE_PS2_SYNAPTICS_SMBUS MOUSE_PS2_ELANTECH \
  MOUSE_PS2_ELANTECH_SMBUS MOUSE_PS2_ALPS MOUSE_PS2_FOCALTECH MOUSE_PS2_TRACKPOINT \
  RMI4_CORE RMI4_SMB RMI4_F03 RMI4_F11 RMI4_F12 RMI4_F30 RMI4_F3A I2C_I801 \
  MOUSE_ELAN_I2C MOUSE_ELAN_I2C_I2C MOUSE_ELAN_I2C_SMBUS \
  I2C_HID_ACPI HID_MULTITOUCH I2C_DESIGNWARE_CORE I2C_DESIGNWARE_PLATFORM \
  MFD_INTEL_LPSS_PCI MFD_INTEL_LPSS_ACPI X86_INTEL_LPSS X86_AMD_PLATFORM_DEVICE \
  PINCTRL_AMD PINCTRL_INTEL_PLATFORM PINCTRL_SUNRISEPOINT PINCTRL_CANNONLAKE PINCTRL_ICELAKE \
  PINCTRL_TIGERLAKE PINCTRL_ALDERLAKE PINCTRL_METEORLAKE PINCTRL_JASPERLAKE PINCTRL_GEMINILAKE \
  PINCTRL_BROXTON PINCTRL_BAYTRAIL PINCTRL_CHERRYVIEW PINCTRL_LYNXPOINT \
  INTEL_THC_HID INTEL_QUICKI2C INPUT_MISC INPUT_UINPUT; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
for sym in HID_APPLE HID_MAGICMOUSE MOUSE_BCM5974 KEYBOARD_APPLESPI INPUT_MOUSEDEV; do
  if grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is =y in kernel/.config, PD design 결정 9 leaves it off"
    exit 1
  fi
done
# 커널이 장치 ID를 드라이버에 잇는 표. 경로마다 대표 하나다(PD-M3 plan 확정 4가
# modules.builtin.modinfo에서 뽑은 글자). modinfo는 NUL로 나뉜 파일이다.
MODINFO=../kernel/build/modules.builtin.modinfo
for alias in i2c_hid_acpi.alias=acpi*:PNP0C50:* hid_multitouch.alias=hid:b*g0004v*p* \
  elan_i2c.alias=acpi*:ELAN0000:* rmi_smbus.alias=i2c:rmi4_smbus \
  intel_lpss_pci.alias=pci:v00008086d00009D60sv*sd*bc*sc*i* pinctrl_tigerlake.alias=acpi*:INT34C5:* \
  pinctrl_amd.alias=acpi*:AMD0030:* intel_quicki2c.alias=pci:v00008086d0000A848sv*sd*bc*sc*i*; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -xF "$alias" >/dev/null; then
    echo "FAIL: the kernel has no '${alias}' entry in modules.builtin.modinfo"
    exit 1
  fi
done
echo "the kernel carries the PS/2, SMBus and I2C-HID touchpad paths and uinput, and no Apple input drivers"

# 부팅 A — USB 마우스 하나(PD-M0~M2). i8042.noaux가 PS/2 마우스 포트를 끈다 —
# 위의 머리 주석과 PD-M3 plan 확정 9. 검사 1의 "정확히 하나"가 그것이 먹혔다는 것도
# 함께 본다(PS/2 마우스가 생기면 open이 둘이다).
qemu-system-x86_64 \
```

편집 6 — `old_string`(기준 파일 410줄부터):

```bash
  -append "console=ttyS0" \
```

`new_string`:

```bash
  -append "console=ttyS0 i8042.noaux" \
```

편집 7 — `old_string`(기준 파일 1029줄부터):

```bash
echo "PD-M2 check PASS"
```

`new_string`:

```bash

# ══ 부팅 B: PS/2 마우스와 uinput 터치패드 (PD-M3) ═══════════════════════
#
# 부팅 A를 끄고 설정 디스크 하나를 물려 다시 뜬다. cmdline은 기본 그대로라
# psmouse가 QEMU pc의 PS/2 마우스를 잡는다(design 실측 4). 디스크에는 되감기
# 도구와 드라이버 목록 스크립트가 있다. 라벨 접두사 tars-가 init이 설정
# 디스크를 알아보는 표지다(RM-M2).
exec 3<&- 2>/dev/null
exec 3>&- 2>/dev/null
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

# 검사 19의 둘째 겹 — 게스트에서 드라이버가 실제로 등록됐는가. 없는 것만 한 줄씩
# 찍고 마지막에 개수를 찍는다. 화면 한 장에 들어가야 screen> 줄로 판정할 수 있어서
# 있는 것은 안 찍는다. 이름은 PD-M3 plan 확정 4가 커널 소스에서 뽑았다.
SEED="$(mktemp -d)"
mkdir -p "$SEED/pd"
printf 'shell=fish\n' > "$SEED/tars.conf"
cp "$REPLAY" "$SEED/pd/tp-replay"
chmod 0755 "$SEED/pd/tp-replay"
cat > "$SEED/pd/drivers" <<'DRIVERS'
#!/usr/bin/bash
n=0
ok=0
for d in /sys/bus/serio/drivers/psmouse /sys/bus/hid/drivers/hid-multitouch \
    /sys/bus/i2c/drivers/i2c_hid_acpi /sys/bus/i2c/drivers/elan_i2c /sys/bus/i2c/drivers/rmi4_smbus \
    /sys/bus/rmi4/drivers/rmi4_physical /sys/bus/pci/drivers/i801_smbus /sys/bus/pci/drivers/intel-lpss \
    /sys/bus/platform/drivers/i2c_designware /sys/bus/platform/drivers/amd_gpio \
    /sys/bus/platform/drivers/tigerlake-pinctrl /sys/bus/pci/drivers/intel_quicki2c; do
  n=$((n + 1))
  if [ -e "$d" ]; then ok=$((ok + 1)); else echo "pd-drv-no $d"; fi
done
n=$((n + 1))
if [ -c /dev/uinput ]; then ok=$((ok + 1)); else echo "pd-drv-no /dev/uinput"; fi
echo "pd-drivers ${ok}/${n}"
DRIVERS
chmod 0755 "$SEED/pd/drivers"
DISK_B="${REPO_ROOT}/out/pd-touchpad.img"
rm -f "$DISK_B"
truncate -s 16M "$DISK_B"
mkfs.ext2 -F -q -m 0 -L tars-pd -d "$SEED" "$DISK_B"
rm -rf "$SEED"

LOG_A="$LOG"
LOG="$(mktemp)"
echo "=== boot B: the PS/2 mouse and a uinput touchpad ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK_B",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT_B},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "boot B: terminal never rendered a prompt"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "boot B: the shell prompt never showed up"
grep -a 'tars-init: mounted ext2 at /config' "$LOG" >/dev/null ||
  report_failure "boot B: the config disk was not mounted at /config"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT_B}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "boot B: could not connect to the QEMU monitor"

# ── 검사 20: psmouse가 PS/2 마우스를 잡고 terminal이 마우스로 연다 ────────
#
# 커널 줄과 terminal 줄을 따로 본다. 커널 줄이 없으면 psmouse가 i8042 AUX를 못
# 잡은 것이고(MOUSE_PS2가 빠졌거나 i8042가 AUX를 안 열었다), 커널 줄만 있으면
# terminal의 분류나 핫플러그가 틀린 것이다. psmouse의 탐지는 비동기라서 terminal보다
# 늦게 끝날 수 있다 — 그러면 처음 훑기가 아니라 uevent가 연다. 어느 쪽이든 같은 줄이다.
# synaptics 프로토콜은 QEMU에 없으므로 이 부팅이 보는 것은 "psmouse가 i8042 AUX를
# 잡는다"까지다(design 결정 9).
echo "=== boot B: psmouse registers the PS/2 mouse and terminal opens it ==="
PS2_NAME='ImExPS/2 Generic Explorer Mouse'
wait_for_log "input: ${PS2_NAME} as /devices/platform/i8042/serio1/input/input[0-9]+" ||
  report_failure "psmouse never registered the PS/2 mouse (no 'input: ${PS2_NAME} as …/i8042/serio1/…')"
wait_for_log "terminal: pointer> open /dev/input/event[0-9]+ kind=mouse shown=0 name=${PS2_NAME}" ||
  report_failure "the kernel registered the PS/2 mouse but terminal never opened it as kind=mouse"
PS2_PATH="$(grep -a "terminal: pointer> open .* name=${PS2_NAME}" "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*open ([^ ]+) .*/\1/')"
echo "ps/2 mouse: ${PS2_PATH}"

# ── 검사 19의 둘째: 드라이버가 게스트에 등록됐다 ──────────────────────────
echo "=== boot B: the touchpad drivers are registered ==="
type_keys slash c o n f i g slash p d slash d r i v e r s ret
wait_for_screen '\| pd-drivers [0-9]+/[0-9]+ \|' ||
  report_failure "the driver list script printed no summary"
DRV_LINE="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' | grep -oE 'pd-drivers [0-9]+/[0-9]+' | tail -n 1)"
DRV_MISSING="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' | grep -oE 'pd-drv-no [^ |]+' | sort -u | tr '\n' ' ')"
[ "$DRV_LINE" = "pd-drivers 13/13" ] ||
  report_failure "the guest is missing touchpad drivers: '${DRV_LINE}' ${DRV_MISSING}"
echo "drivers: ${DRV_LINE}"

# 스크롤백을 만들어 둔다(검사 24). 도구는 패널 안에서 돌고 찍지 않으므로 그동안
# 이 스크롤백이 그대로다.
type_keys s e q spc 2 0 0 ret
wait_for_screen '\| 200 \| root@\(none\) ~#' ||
  report_failure "boot B: seq 200 did not finish"

# ── 검사 21: 도구가 만든 터치패드를 터치패드로 연다 ─────────────────────
#
# 부팅 뒤에 생긴 장치라 uevent가 알리고(PD-M0의 배관), classify가 INPUT_PROP_POINTER와
# ABS_MT로 터치패드라 하고, EVIOCGABS로 읽은 축이 open 줄에 찍힌다. 축은 도구가
# 만든 그대로다 — 가로 0..1000 · 세로 0..600, resolution 10 · 12, 칸 둘.
echo "=== boot B: tp-replay makes a touchpad and terminal opens it ==="
type_keys slash c o n f i g slash p d slash t p minus r e p l a y ret
wait_for_log 'terminal: pointer> (open|skip) /dev/input/event[0-9]+ kind=touchpad.* name=TARS Replay Touchpad' ||
  report_failure "terminal never saw the replay touchpad (no 'pointer> open … kind=touchpad … name=TARS Replay Touchpad')"
TP_LINE="$(grep -a 'name=TARS Replay Touchpad' "$LOG" | grep -a 'terminal: pointer> ' | tail -n 1 | tr -d '\r')"
case "$TP_LINE" in
  *"> open /dev/input/event"*" kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad") ;;
  *) report_failure "the replay touchpad came out as '${TP_LINE}', expected 'open … kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad'" ;;
esac
TP_PATH="$(sed -E 's/.*open ([^ ]+) .*/\1/' <<<"$TP_LINE")"
echo "touchpad: ${TP_LINE}"

# 명령 한 줄을 도구의 stdin에 친다. 친 글자는 키라서 화살표를 숨기지만(보이는
# 조건 3), 다음 손가락 이동이 다시 보이게 한다.
replay() {
  local word keys=()
  for word in $1; do
    [ "${#keys[@]}" -gt 0 ] && keys+=(spc)
    keys+=($(sed -e 's/./& /g' -e 's/-/minus/g' <<<"$word"))
  done
  type_keys "${keys[@]}" ret
}

# ── 검사 22: 한 손가락 이동이 배율대로 포인터를 옮긴다 ───────────────────
#
# 출발은 가운데(640, 400)다. 가로 100단위는 128픽셀이다 — 패드 가로 1000이 화면
# 가로 1280이다. 세로 60단위는 64픽셀이다 — 세로 resolution이 12라서 같은 mm당
# 픽셀로 맞추면 단위당 1.28 × 10 / 12다. resolution을 안 보고 가로와 같은 단위당
# 픽셀을 쓰면 76이 된다(mutation 4). 이동은 탭이 아니다 — press 줄이 없다.
echo "=== boot B: one finger moves the pointer by the pad's scale ==="
replay "move 100 0"
wait_for_at "^terminal: pointer> at x=768 y=400 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'move 100 0' the last at line is '$(last_at)', expected 'at x=768 y=400 … shown=1 ink=${ARROW_INK}' (100 of 1000 units is 128 of 1280 pixels)"
replay "move 0 60"
wait_for_at '^terminal: pointer> at x=768 y=464 ' ||
  report_failure "after 'move 0 60' the last at line is '$(last_at)', expected x=768 y=464 (60 units at resolution 12 against 10 is 64 pixels)"
[ "$(pointer_count 'press ')" -eq 0 ] ||
  report_failure "a one-finger move pressed a button: $(last_press)"
echo "moved: $(last_at)"

# ── 검사 23: 탭은 클릭이고, 긴 누름은 아무것도 아니다 ─────────────────────
#
# 탭(40ms)은 press · release 한 쌍이다. 768, 464는 27행 93열의 칸이다. 긴 누름(500ms)은
# 아무것도 안 낸다. 그것을 "아직 안 왔다"와 가르려고 뒤에 이동을 하나 보낸다 —
# 같은 장치의 이벤트는 순서대로 읽히므로 그 이동의 at 줄이 보이면 긴 누름은 이미
# 디코더를 지났다. 탭의 시간 조건이 빠지면 여기서 press가 하나 더 는다(mutation 1).
# 그 이동은 40단위다. 탭이 움직여도 되는 거리가 가로 20단위(축의 2%)라서 그보다
# 짧고 빠른 이동은 그 자체가 탭이 된다 — 10단위로 했을 때 실제로 클릭이 났다.
echo "=== boot B: a tap clicks, a hold does nothing ==="
replay "tap"
wait_for_count pointer_count 'release ' 1 ||
  report_failure "a tap printed no 'pointer> release' line (last press: '$(last_press)')"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=27 col=93" ] ||
  report_failure "the tap pressed '$(last_press)', expected 'press leaf=0 row=27 col=93'"
[ "$(last_release)" = "terminal: pointer> release drag=0" ] ||
  report_failure "the tap released '$(last_release)', expected 'release drag=0'"
replay "hold"
replay "move 40 0"
wait_for_at '^terminal: pointer> at x=819 y=464 ' ||
  report_failure "after 'hold' and 'move 40 0' the last at line is '$(last_at)', expected x=819 y=464"
[ "$(pointer_count 'press ')" -eq 1 ] ||
  report_failure "a 500ms hold clicked (press lines: $(pointer_count 'press '), last '$(last_press)'); a tap must be shorter than 180ms"
echo "tap: $(last_press) / $(last_release), hold: nothing"

# ── 검사 24: 두 손가락 세로는 휠이고, 포인터는 안 움직인다 ────────────────
#
# 90단위는 96픽셀이고 휠 한 눈금이 3줄 × 16픽셀이라 두 눈금, 여섯 줄이다. 손가락을
# 아래로 밀면 휠을 앞으로 민 것과 같다 — 위의 글이 보이도록 offset이 준다. 패널은
# 바닥에 있었으므로(친 글자의 에코가 내린다) offset은 total - len - 6이 된다.
# 두 손가락을 이동으로 보내면 at의 y가 바뀌고 offset은 그대로다(mutation 2).
echo "=== boot B: two fingers scroll the pane under the pointer ==="
ATS="$(pointer_count 'at ')"
replay "scroll 90"
SCROLLED=0
for _ in $(seq 1 150); do
  LINE="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 | tr -d '\r')"
  T="$(sed -E 's/.*total=([0-9]+).*/\1/' <<<"$LINE")"
  O="$(sed -E 's/.*offset=([0-9]+).*/\1/' <<<"$LINE")"
  L="$(sed -E 's/.*len=([0-9]+).*/\1/' <<<"$LINE")"
  if [ "$((T - L - O))" -eq 6 ]; then SCROLLED=1; break; fi
  sleep 0.1
done
[ "$SCROLLED" = "1" ] ||
  report_failure "two fingers 90 units down left the viewport at '${LINE}', expected six rows above the bottom"
NEW_ATS="$(grep -a 'terminal: pointer> at ' "$LOG" | tail -n "+$((ATS + 1))" | tr -d '\r')"
grep -avE ' x=819 y=464 ' <<<"$NEW_ATS" >/dev/null &&
  report_failure "two fingers moved the pointer: $(grep -avE ' x=819 y=464 ' <<<"$NEW_ATS" | sed -n 1p)"
WHEEL=0
while read -r w; do WHEEL=$((WHEEL + w)); done < <(sed -nE 's/.* wheel=(-?[0-9]+) .*/\1/p' <<<"$NEW_ATS")
[ "$WHEEL" = "2" ] ||
  report_failure "two fingers 90 units down added up to wheel=${WHEEL} on the at lines, expected 2"
echo "scrolled: ${LINE}, wheel ${WHEEL}"

# ── 검사 25: 도구가 끝나면 터치패드를 닫는다 ─────────────────────────────
#
# quit이 UI_DEV_DESTROY로 장치를 없앤다. 그 fd가 POLLHUP을 올리고 terminal이 닫는다.
# PS/2 마우스는 그대로 열려 있다. 그 뒤에 친 echo가 오면 poll이 막히지 않은 것이다.
echo "=== boot B: quitting the tool closes the touchpad ==="
replay "quit"
wait_for_log "terminal: pointer> close ${TP_PATH}" ||
  report_failure "the replay touchpad was never closed (no 'pointer> close ${TP_PATH}')"
[ "$(pointer_count 'close ')" -eq 1 ] ||
  report_failure "expected one 'pointer> close' in boot B, got $(pointer_count 'close ')"
type_keys e c h o spc p d minus t p minus g o n e ret
wait_for_screen '\| pd-tp-gone \|' ||
  report_failure "the shell did not answer after the touchpad went away"
echo "closed: $(grep -a 'terminal: pointer> close ' "$LOG" | tail -n 1 | tr -d '\r')"

if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the boot B serial log contains NUL bytes"
fi

echo "boot B pointer> lines:"
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'
rm -f "$LOG_A" "$LOG"
echo "PD-M3 check PASS"
```

### 6-2. `check.sh` — 문단과 `CHAINS`

편집 1 — `old_string`(기준 파일 326줄부터):

```bash
# 회차당 부팅 1회.
```

`new_string`:

```bash
# PD-M3이 부팅 하나를 더했다 — 설정 디스크의 tp-replay가 uinput으로 터치패드를
# 만들어 이동 · 탭 · 두 손가락 스크롤을 되감고, 같은 부팅에서 psmouse가 QEMU의
# PS/2 마우스를 잡는다. 부팅 전에 커널의 터치패드 심볼과 장치 표를 본다.
# 회차당 부팅 2회.
```

편집 2 — `old_string`(기준 파일 349줄부터):

```bash
  "PD-M2:./pointer/check.sh"
```

`new_string`:

```bash
  "PD-M3:./pointer/check.sh"
```

### 6-3. 확인

```bash
bash -n pointer/check.sh && echo SYNTAX-OK
bash -n check.sh && echo ROOT-SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./pointer/check.sh && require_no_early_exit_pipe ./pointer/check.sh &&
  require_explicit_nic ./pointer/check.sh && require_no_early_exit_pipe ./check.sh && echo ENTRY-OK'
diff pointer/check.sh /tmp/run/pdm3/new/pointer/check.sh && echo SAME
diff check.sh /tmp/run/pdm3/new/check.sh && echo SAME-root
python3 /tmp/run/pdm3/anchors.py post "$PWD"
```

기대: `SYNTAX-OK` · `ROOT-SYNTAX-OK` · `ENTRY-OK` · `SAME` · `SAME-root` · `post: 20 edits, 0 bad`.

## Task 7: 체인 한 번과 regression

체인은 하나씩 돈다. 전부 같은 `kernel/initrd.cpio`를 다시 만들고, VM의 메모리가 4GB다.

### 7-1. `pointer` 체인

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm3:/tmp/run/pdm3 -w /workspace tars-devcontainer bash -c '
    bash pointer/check.sh > /tmp/run/pdm3/impl/pointer.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rg -a -n '^===|^FAIL|^the kernel carries|^ps/2|^drivers|^touchpad|^moved|^tap|^scrolled|^closed|PD-M3 check' /tmp/run/pdm3/impl/pointer.log
```

기대: `exit=0`. 첫 `rg`는 PD-M2의 줄(PD-M2 plan Task 6-1) 앞에 검사 19의 줄 하나가, 뒤에 부팅 B의 줄들이 오고
`PD-M3 check PASS`로 끝난다. 사본의 판이 찍은 부팅 B의 줄은 이렇다.

```
=== boot B: the PS/2 mouse and a uinput touchpad ===
=== boot B: psmouse registers the PS/2 mouse and terminal opens it ===
ps/2 mouse: /dev/input/event2
=== boot B: the touchpad drivers are registered ===
drivers: pd-drivers 13/13
=== boot B: tp-replay makes a touchpad and terminal opens it ===
touchpad: terminal: pointer> open /dev/input/event3 kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad
=== boot B: one finger moves the pointer by the pad's scale ===
moved: terminal: pointer> at x=768 y=464 buttons=0 wheel=0 shown=1 ink=118
=== boot B: a tap clicks, a hold does nothing ===
tap: terminal: pointer> press leaf=0 row=27 col=93 / terminal: pointer> release drag=0, hold: nothing
=== boot B: two fingers scroll the pane under the pointer ===
scrolled: terminal: scroll> total=212 offset=159 len=47, wheel 2
=== boot B: quitting the tool closes the touchpad ===
closed: terminal: pointer> close /dev/input/event3
```

`total`과 `offset`은 그 회차의 값이고 판정은 total − len − offset = 6만 본다. 체인 끝의 `boot B pointer> lines:` 목록은 이랬다 — 휠 두 눈금이 회차 둘에 하나씩 나뉘어 왔다.

```
terminal: pointer> open /dev/input/event2 kind=mouse shown=0 name=ImExPS/2 Generic Explorer Mouse
terminal: pointer> skip /dev/input/event1 kind=none name=AT Translated Set 2 keyboard
terminal: pointer> skip /dev/input/event0 kind=none name=Power Button
terminal: pointer> open /dev/input/event3 kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad
terminal: pointer> at x=652 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=665 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=678 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=691 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=704 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=716 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=729 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=742 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=755 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=400 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=400 buttons=0 wheel=0 shown=0 ink=0
terminal: pointer> at x=768 y=410 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=421 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=432 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=442 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=453 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=464 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=464 buttons=0 wheel=0 shown=0 ink=0
terminal: pointer> press leaf=0 row=27 col=93
terminal: pointer> release drag=0
terminal: pointer> at x=768 y=464 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=768 y=464 buttons=0 wheel=0 shown=0 ink=0
terminal: pointer> at x=780 y=464 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=793 y=464 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=806 y=464 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=819 y=464 buttons=0 wheel=0 shown=1 ink=118
terminal: pointer> at x=819 y=464 buttons=0 wheel=0 shown=0 ink=0
terminal: pointer> at x=819 y=464 buttons=0 wheel=1 shown=0 ink=0
terminal: pointer> at x=819 y=464 buttons=0 wheel=1 shown=0 ink=0
terminal: pointer> close /dev/input/event3
PD-M3 check PASS
```

### 7-2. regression

`render` · `copy` · `pane`은 PS/2 마우스가 생긴 부팅에서 픽셀 · 글자 판정이 그대로인지 본다(design "검증"). `install`은
부팅 7의 여유를 본다(확정 6). `machine`은 q35에서 `I2C_I801`이 ICH9 SMBus를 잡는 부팅이다. 넷 다 이 milestone의 코드가
닿는 자리가 없고 커널만 바뀌었다.

```bash
for ch in render copy pane install machine; do
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm3:/tmp/run/pdm3 -w /workspace tars-devcontainer bash -c "
      bash $ch/check.sh > /tmp/run/pdm3/impl/$ch.log 2>&1; echo exit=\$?" ; } 2>&1 | tail -4
  rg -a 'check PASS|^TR-M2 PASS|^FAIL|init waited' /tmp/run/pdm3/impl/$ch.log | cut -c1-80
done
```

Bash 도구의 10분 상한 때문에 체인을 하나씩 부른다(합 약 7분 20초 — render 1분 50초 · copy 2분 52초 · pane 33초 · install 1분 45초 · machine 20초).

기대: 다섯 다 `exit=0`. `install`은 `init waited NNNms for the late USB disk and mounted its p2`이고 NNN을 보고한다 —
확정 6의 표와 비교한다. 사본에서는 두 번 다 100ms였다. NNN이 500 아래거나 `install`이 판정 17(`init did not have to
wait for the late USB disk`)에서 빨개지면 Task 7-3을 한다(사본의 값으로는 한다). 500 이상이면 Task 7-3을 건너뛰고 그
값을 보고한다.

### 7-3. 부팅 7의 `delay_use`를 4로(조건부)

lead가 정했다(2026-10-05, 확정 6). Task 7-2의 기다림이 500ms 아래일 때만 한다. `install/check.sh`의 편집 셋이다.
사본에서 조건이 맞았다 — 부팅 7의 기다림이 두 번 다 100ms였다(확정 6). 편집의 글자는 사본 `/tmp/run/pdm3/cond/install/check.sh`에서 뽑았다.

편집 1 — `old_string`(기준 파일 17줄부터):

```bash
#   7  같은 디스크를 USB로  -kernel · delay_use=3. init이 늦은 p2를 기다려 잡는다(DC-M1)
```

`new_string`:

```bash
#   7  같은 디스크를 USB로  -kernel · delay_use=4. init이 늦은 p2를 기다려 잡는다(DC-M1)
```

편집 2 — `old_string`(기준 파일 453줄부터):

```bash
# 왜 -kernel인가. cmdline에 delay_use를 넣을 자리가 필요하고, tars.installed도
```

`new_string`:

```bash
# PD-M3이 4초로 올렸다. 커널에 노트북 터치패드의 드라이버가 들어가며 코드 배치가
# 밀렸고, initramfs를 푸는 inflate_fast가 페이지 경계에 걸려 TCG에서 풀기가 0.8초
# 늦어졌다. 3초의 기다림이 900ms에서 100ms로 줄었다(PD-M3 plan 확정 6). 이 늦어짐은
# 코드의 자리에 달려 있어서 뒤의 커널 변경이 또 움직일 수 있다 — 그래서 1초를 더
# 벌린다. 4초도 init의 상한(storage.zig의 CONFIG_WAIT_MS 5000)과는 2초 넘게 떨어져 있다.
#
# 왜 -kernel인가. cmdline에 delay_use를 넣을 자리가 필요하고, tars.installed도
```

편집 3 — `old_string`(기준 파일 492줄부터):

```bash
echo "=== boot 7: the installed disk over USB, three seconds late ==="
boot_kernel_usb 7 "console=ttyS0 tars.installed usb-storage.delay_use=3"
```

`new_string`:

```bash
echo "=== boot 7: the installed disk over USB, four seconds late ==="
boot_kernel_usb 7 "console=ttyS0 tars.installed usb-storage.delay_use=4"
```

확인하고 그 체인만 다시 돈다.

```bash
diff install/check.sh /tmp/run/pdm3/cond/install/check.sh && echo SAME-install
bash -n install/check.sh && echo SYNTAX-OK
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm3:/tmp/run/pdm3 -w /workspace tars-devcontainer bash -c "
    bash install/check.sh > /tmp/run/pdm3/impl/install2.log 2>&1; echo exit=\$?" ; } 2>&1 | tail -4
rg -a 'check PASS|^FAIL|init waited' /tmp/run/pdm3/impl/install2.log
```

기대: `SAME-install` · `SYNTAX-OK` · `exit=0`, `init waited`가 약 1초 늘어 있다(사본에서 두 번 다 1100ms). 그 값을 보고한다.

## Task 8: mutation 넷

확정 10의 표다. 사본은 `/tmp/run/pdm3/impl/mut/`에 만든다. 돌리기 전에 `diff`로 편집이 정확히 한 줄 들어갔는지 본다 —
`sd -F`가 빗나가도 에러가 없다. 한 줄이 아니면 돌리지 말고 보고한다.

### 8-0. 사본을 만든다

```bash
M=/tmp/run/pdm3/impl/mut; mkdir -p $M
cp terminal/src/touchpad.zig $M/touchpad_m1.zig
cp terminal/src/touchpad.zig $M/touchpad_m2.zig
cp terminal/src/main.zig $M/main_m3.zig
cp terminal/src/touchpad.zig $M/touchpad_m4.zig
cp pointer/check.sh $M/pointer_notest.sh
sd -F 'return self.tap_ok and !pressing and t_us - self.tap_start_us < TAP_US;' 'return self.tap_ok and !pressing;' $M/touchpad_m1.zig
sd -F 'if (pressing or fingers == 1) {' 'if (pressing or fingers >= 1) {' $M/touchpad_m2.zig
sd -F 'if (kind == .none) {' 'if (kind != .mouse) {' $M/main_m3.zig
sd -F 'if (x.res > 0 and y.res > 0) return' 'if (x.res < 0 and y.res > 0) return' $M/touchpad_m4.zig
sd -F 'if ! (cd ../terminal && zig build test); then' 'if false; then' $M/pointer_notest.sh
chmod +x $M/pointer_notest.sh
bash -c 'M=/tmp/run/pdm3/impl/mut
for p in "touchpad.zig touchpad_m1.zig" "touchpad.zig touchpad_m2.zig" "main.zig main_m3.zig" "touchpad.zig touchpad_m4.zig"; do
  set -- $p; echo "== $2"; diff terminal/src/$1 $M/$2
done
echo "== pointer_notest.sh"; diff pointer/check.sh $M/pointer_notest.sh'
```

기대: 다섯 `diff`가 각각 한 줄의 차이다. mutation 1은 `t_us`를 세션 시작에서 여전히 쓰므로 안 쓰는 인자 에러가 안 난다.

### 8-1. mutation 1 · 2 · 4 — 먼저 `touchpad_test`

```bash
for m in 1 2 4; do
  docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm3/impl/mut/touchpad_m$m.zig:/workspace/terminal/src/touchpad.zig:ro \
    -w /workspace/terminal tars-devcontainer bash -c '
    rm -rf .zig-cache zig-out
    zig build test > /tmp/t.out 2>&1; echo "exit=$?"
    grep -a -E "^FAIL" /tmp/t.out | head -2'
done
```

기대(확정 11에서 본 그대로): 셋 다 `exit=1`. mutation 1은 `FAIL: a 500ms hold gives no frame = 2, want 0`, 2는 `FAIL: two fingers, 90 units down: wheel = 0, want 2`, 4는 `FAIL: one finger, 60 units down: dy (y follows the mm of x) = 76, want 64`.

### 8-2. 체인 넷

mutation 1 · 2 · 4는 `zig build test`를 건너뛴 사본 체인으로, 3은 그대로의 체인으로 돌린다. `-e m=$m`으로 번호를 컨테이너에
넘긴다(PE-M1 실측 5).

```bash
M=/tmp/run/pdm3/impl/mut
run_mut() {  # 번호, 덮을 -v 인자들
  local m="$1"; shift
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm3:/tmp/run/pdm3 "$@" -e m="$m" \
      -w /workspace tars-devcontainer bash -c '
    echo "mounted: tp=$(grep -c -E "return self.tap_ok and !pressing;|fingers >= 1\) \{|x.res < 0 and" terminal/src/touchpad.zig) main=$(grep -c "if (kind != .mouse) {" terminal/src/main.zig) notest=$(grep -c "^if false; then" pointer/check.sh)"
    rm -rf terminal/.zig-cache terminal/zig-out
    bash pointer/check.sh > /tmp/run/pdm3/impl/mut/m$m.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -5
  rg -a -n '^===|^FAIL' $M/m$m.log | tail -3
}
run_mut 1 -v $M/touchpad_m1.zig:/workspace/terminal/src/touchpad.zig:ro -v $M/pointer_notest.sh:/workspace/pointer/check.sh:ro
run_mut 2 -v $M/touchpad_m2.zig:/workspace/terminal/src/touchpad.zig:ro -v $M/pointer_notest.sh:/workspace/pointer/check.sh:ro
run_mut 3 -v $M/main_m3.zig:/workspace/terminal/src/main.zig:ro
run_mut 4 -v $M/touchpad_m4.zig:/workspace/terminal/src/touchpad.zig:ro -v $M/pointer_notest.sh:/workspace/pointer/check.sh:ro
```

함수 정의가 zsh에서 문제가 되면 `bash -c '…'`로 감싸 친다. `run_mut`을 한 번에 하나씩 부른다. 로그에 `Killed`가 보이고
`FAIL: terminal build failed`로 끝나면 mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지 보고 그 판만 다시 돈다.

기대(확정 11에서 본 그대로).

| mutation | `mounted:` | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|---|
| 1 탭의 시간 조건 | `tp=1 main=0 notest=1` | 검사 23의 긴 누름 | `FAIL: a 500ms hold clicked (press lines: 2, last 'terminal: pointer> press leaf=0 row=27 col=93'); a tap must be shorter than 180ms` — 1분 55초 |
| 2 두 손가락 → 이동 | `tp=1 main=0 notest=1` | 검사 24 | `FAIL: two fingers 90 units down left the viewport at 'terminal: scroll> total=212 offset=165 len=47', expected six rows above the bottom` — 2분 10초 |
| 3 터치패드를 안 연다 | `tp=0 main=1 notest=0` | 검사 21 | `FAIL: the replay touchpad came out as 'terminal: pointer> skip /dev/input/event3 kind=touchpad name=TARS Replay Touchpad', expected 'open … kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad'` — 1분 59초 |
| 4 세로 배율 | `tp=1 main=0 notest=1` | 검사 22의 둘째 이동 | `FAIL: after 'move 0 60' the last at line is 'terminal: pointer> at x=768 y=476 buttons=0 wheel=0 shown=1 ink=118', expected x=768 y=464 (60 units at resolution 12 against 10 is 64 pixels)` — 2분 8초 |

mutation이 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 바이너리를 의심한다
(`project_zig_out_staleness` — 캐시 삭제가 같은 `docker run` 안에 있었는지, `mounted:`가 1이었는지).

### 8-3. 되돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf terminal/.zig-cache terminal/zig-out
  (cd terminal && ./prepare.sh > /tmp/p.out 2>&1 && zig build test > /tmp/t.out 2>&1); echo "exit=$?"
  grep -a -c "^touchpad_test: .* OK$" /tmp/t.out
  (cd kernel && ./make_initrd.sh > /tmp/i.out 2>&1); echo "initrd exit=$?"'
git status --short
```

기대: `exit=0`, `touchpad_test` OK 34, `initrd exit=0`. `git status`는 `M` 다섯(`check.sh` · `kernel/.config` ·
`pointer/check.sh` · `terminal/build.zig` · `terminal/src/main.zig`)과 `??` 셋(`pointer/replay/` ·
`terminal/src/touchpad.zig` · `terminal/src/touchpad_test.zig`), plan이 commit 전이면 `??` 하나 더다. Task 7-3을 했으면
`M install/check.sh`가 하나 더 있다. 다른 것이 보이면
(특히 `-v`로 없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 8-4. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체).
- Task 0의 출력, Task 1의 시간 · 크기 · `FOLDED`.
- Task 2~6의 확인 출력(`SAME` · OK 줄 수 · `ENTRY-OK` · `anchors.py`).
- Task 7의 `exit=` · `real` · `rg` 출력과 `install`의 `init waited` 값.
- Task 8의 `diff` 다섯 · `mounted:` · `exit=` · `real` · `FAIL` 줄, 8-3의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 9: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고(새 파일 넷은 `Read`), Task 7의 로그를 대조한다.
2. 루트 게이트 2회, 열아홉 체인 × 2다. 판정은 `PASS: 2/2` × 19와 `PD-M3 check PASS` 둘이다. 이 milestone은 커널을
   바꾸므로 게이트의 첫 체인이 커널 전체 빌드를 치른다(`clean()`이 `kernel/build`를 지운다) — 그 시간이 확정 6의 표에 없는
   유일한 증가다. PD-M2의 게이트 시간에 `pointer` 체인의 부팅 B 한 판(약 15초(따뜻한 캐시에서 PD-M2의 체인이 37초, PD-M3이 51초))을 두 번 더한 것으로 본다.
   `run_in_background`로 돌리고 `{ time …; }`로 감싼다. 다른 컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_pd3.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_pd3.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 2/2' /tmp/gate_pd3.log`가 19, `rg -c 'PD-M3 check PASS' /tmp/gate_pd3.log`가 2여야 한다. `install`의 부팅 7
   값도 `rg 'init waited' /tmp/gate_pd3.log`로 본다.
3. 실측 절 채우기.
4. commit. 넣는 것은 `kernel/.config` · `terminal/src/touchpad.zig` · `terminal/src/touchpad_test.zig` · `terminal/build.zig` ·
   `terminal/src/main.zig` · `pointer/replay/build.zig` · `pointer/replay/main.zig` · `pointer/check.sh` · `check.sh` · 이 plan이고,
   Task 7-3을 했으면 `install/check.sh`도 넣는다.
   `git add`는 경로를 하나씩 지정한다(`pointer/replay/`를 통째로 넣지 않는다 — 캐시가 생겼을 수 있다).
5. 닫기. 아래 "닫을 때"의 목록이다. 서브프로젝트를 닫는 commit은 PD-M3 commit과 따로 만든다.

## 닫을 때

design "닫을 때(lead의 몫)"의 목록에 이 plan이 알게 된 것을 붙였다.

1. design의 `Status:`를 `끝났다(날짜)`로 고친다. 결정마다 한 줄씩 덧붙인다 — 결정 1의 inotify가 netlink uevent로 바뀐
   것(PD-M0) · ioctl 번호를 번역된 매크로로 부르는 것(PD-M0) · 위험 8이 풀린 것(PD-M0) · 결정 8의 휠 눈금이 "3 ×
   `ROW_HEIGHT`마다 한 눈금"인 것과 resolution이 없을 때의 세로 배율(확정 2) · 결정 9의 심볼 목록에서 고친 넷(확정 4) ·
   결정 10의 검사 20이 부팅 B로 간 것과 부팅 A의 `i8042.noaux`(확정 9) · 되감기 도구의 세로 resolution 12(확정 7) · M3의
   mutation 셋째를 바꾼 것(확정 10).
2. `CLAUDE.md`의 완료 표에 한 줄. 끝난 날 · "무엇이 섰나" 칸(마우스와 터치패드가 화살표 하나를 움직이고, 끌면 copy mode의
   선택, 떼면 클립보드. 터치패드는 탭 · 두 손가락 스크롤. 열아홉번째 체인 `pointer/check.sh`, 부팅 둘).
3. `docs/decisions/project_pointer_devices.md`를 만들고 `MEMORY.md`에 한 줄. 담을 것 — 층 셋(디코더 · `Pointer`/`Gesture` ·
   `main.zig`), uevent를 고른 이유와 inotify가 `install`을 깬 일, save-under와 보이는 조건 셋, 모드의 두 사본, 터치패드의
   출발값 셋과 그것을 고칠 때 함께 고칠 곳, PS/2가 모든 pc 체인에 생긴 것과 부팅 A의 `i8042.noaux`, 부팅 7의 여유.
4. 다시 연 결정에 한 줄씩. HD design 결정 3과 비목표(핫플러그 · 마우스), WP design 비목표("드래그 · 마우스"), CM design
   비목표("마우스"), IP design 비목표, TF design 비목표. 각각 "PD가 이것을 바꿨다"와 `[[project_pointer_devices]]`.
5. `docs/guides/running-tars.md`. "안 되는 것" 표의 터치패드 줄(`커널에 드라이버는 있지만 terminal이 포인터를 안 읽는다` —
   design 실측 6이 틀렸다고 한 줄)을 고치고, 실기 절에 볼 것 넷을 둔다 — `pointer> open` 줄의 `kind=`와 축 · 출발값
   셋(180ms · 2% · 배율)이 손에 맞는가 · 두 손가락 스크롤의 방향 · psmouse의 탐지가 부팅을 늦추는가(design 위험 7).
6. `docs/guides/lessons.md`. 포트 목록(45488 · 45489)과 "새 체인은 45490부터", 핵심 파일 지도에 `pointer.zig` ·
   `touchpad.zig` · `pointer/replay/`, 이월 숙제에 design 위험 2 · 5와 비목표 1(마우스 보고). 그리고 이 서브프로젝트가 배운
   것 둘 — "커널 config 한 줄이 무관한 체인의 타이밍 창을 닫을 수 있다(`install` 부팅 7은 initramfs 풀기에 민감하다)"와
   "게이트 전용 실행 파일은 체인이 `out/` 아래로 빌드해 설정 디스크에 싣는다(`.gitignore` · `clean()`을 안 건드린다)".
   mutation이 제품에서도 안 드러나는 고장일 때(확정 10) 바꾸는 요령도 한 줄. 그리고 확정 6의 발견 — TCG에서는
   initramfs를 푸는 `inflate_fast`가 게스트 페이지 경계에 걸리면 풀기가 0.8~1.1초 늦어지고, 그 자리는 앞쪽 코드의 크기로
   정해진다. PD-M0의 `FSNOTIFY`도 같은 것이었을 수 있다(그때 `System.map`을 안 봤다 — 재지 않았다). 커널을 바꾼 milestone은
   `Run /init` 시각과 `inflate_fast`의 페이지 안 자리를 함께 적는다.
7. `HANDOFF.md`.

## design과 다르게 적은 것

아래는 전부 lead가 정했다(2026-10-05).

1. 휠 눈금이 "`ROW_HEIGHT`마다 한 줄"이 아니라 "`3 × ROW_HEIGHT`마다 한 눈금(세 줄)"이다(확정 2). resolution이 없을 때
   세로는 가로와 같은 단위당 픽셀이다(design은 그 경우를 안 적었다).
2. 커널 심볼에서 넷을 고쳤다 — `MOUSE_PS2_ELANTECH`는 기본값이 없어 명시로 켜고, RMI4에 `F03` · `F3A`를 더하고, AMD ·
   옛 Intel의 I2C를 위해 `X86_AMD_PLATFORM_DEVICE` · `X86_INTEL_LPSS`를 더하고, Intel THC의 QuickI2C를 켠다(확정 4).
   `HID_RMI` · `I2C_PIIX4`를 일부러 안 켠다.
3. 검사 20이 부팅 A가 아니라 부팅 B에 있고, 부팅 A의 cmdline에 `i8042.noaux`가 들어간다(확정 9).
4. 되감기 도구의 세로 resolution이 12다(design은 10). 명령은 design의 다섯 그대로다(확정 7).
5. M3 mutation의 셋째("`INPUT_PROP_POINTER`를 안 본다")가 "터치패드 갈래를 디코더에 잇지 않는다"로 바뀌었고, 넷째(세로
   배율)를 더했다(확정 10).
6. 검사 19의 둘째 겹(게스트의 드라이버 목록)을 셸에 직접 치지 않고 설정 디스크의 스크립트로 친다(확정 8).
7. 터치패드의 `open` 줄에 칸 수 · 축 · resolution이 붙는다(로그 줄 정본).
8. Intel THC는 QuickI2C만 켜고 QuickSPI는 비목표다(확정 4).
9. 되접기가 PD-M3 commit과 별도인 lead의 commit이다(확정 5). 부팅 7의 기다림이 500ms 아래면 `install` 체인의
   `delay_use`가 3에서 4가 된다(확정 6 · Task 7-3).

## 이 milestone에서 안 하는 것

- 실제 드라이버가 내는 이벤트 모양의 게이트(hid-multitouch의 PTP 모드 전환 · RMI4 SMBus로 넘어가기 · LPSS · pinctrl의 GPIO
  인터럽트). 세 겹 검증은 "켜졌고 등록됐다"까지만 말한다(design 위험 4).
- 출발값 셋의 실측과 조정(design 위험 3). 실기에서 사람이 한다.
- 가속 · 손바닥 거부 · 치는 동안 끄기 · 가장자리 스크롤 · 세 손가락 · 집기 · 관성 · 두 손가락 탭 오른쪽 클릭 · 탭 뒤 끌기 ·
  `INPUT_PROP_SEMI_MT` 보정(비목표 6). `tars.conf` 항목(비목표 7).
- Apple 트랙패드와 `HID_APPLE`(비목표 10). 절대 좌표 장치 · 터치스크린(비목표 4).
- Intel THC의 QuickSPI(HID over SPI). 다시 열 조건은 SPI로 붙은 터치패드를 가진 노트북이다(lead가 정했다, 2026-10-05).
- 마우스 보고(비목표 1). 서브프로젝트를 닫은 뒤 다음 후보의 첫째다.

## PD-M3이 실측한 것

구현 전에 사본에서 잰 것은 "착수 전에 확정한 것"에 있다. 구현은 Opus 서브에이전트가 2026-10-05에 plan 그대로 했다 —
새 파일 넷은 plan 코드 블록과 바이트까지 같음을 대조한 뒤 넣었고, `build.zig` · `main.zig`는 Edit로, 체인의 긴 편집은
plan 본문에서 뽑아 정확 치환(각 1회)으로 넣었다. `anchors.py post` 20 edits, 0 bad. lead가 파일 전부를 planner의 사본
(`/tmp/run/pdm3/new` · `cond`)과 `cmp`해 같음을 봤고, `kernel/.config`에서 지운 16줄은 전부 `# … is not set` 꼴이었다.

1. 커널. 증분 빌드 1분 54초(plan 104초), bzImage 7,435,264 → 7,758,848바이트(+323,584), `.config` +261 −16, 되접은 뒤
   `CONFIG-SAME`. 금지 심볼 일곱은 전부 `=y`가 아니다.
2. 호스트 검사. `touchpad_test` OK 34 · `pointer_test` OK 107, `zig build` · `zig build test` exit 0. `tp-replay`는
   x86_64 정적 ELF.
3. `pointer` 체인 51.8초, `PD-M3 check PASS`. 부팅 B — `open /dev/input/event3 kind=touchpad slots=2 x=0..1000 y=0..600
   res=10,12 shown=0 name=TARS Replay Touchpad` · 한 손가락 `x=768 y=464 ink=118` · 탭 `press` · `release drag=0`, 긴 누름
   아무것도 없음 · 두 손가락 `scroll> … offset=159`(휠 2) · `close`. 부팅 A의 psmouse는 `i8042.noaux`로 없고, 검사 19
   (심볼 · `/sys/bus/*/drivers` 13/13 · modinfo alias)와 검사 20(부팅 B의 `ImExPS/2 Generic Explorer Mouse`)이 초록.
4. regression — `render` 1분 48초 · `copy` 2분 53초 · `pane` 34초 · `machine` 20초 PASS. `install`은 `delay_use=3`에서
   부팅 7이 빨갰다(기다림 0ms, plan 측정은 100ms) — Task 7-3의 조건(500ms 아래)에 걸려 `delay_use=4`로 고쳤고 다시
   돌리니 `init waited 900ms`(plan 1100ms)로 PASS, 1분 51초.
5. `Run /init` 4.00~4.17초(plan 3.84~3.88초, 세 판), 첫 `screen>` 5.0~5.3초, `inflate_fast`는 System.map에서 plan과 같은
   자리 `…0ec0`(페이지 경계를 넘는다). 차이 0.15~0.3초는 호스트 흔들림으로 본다 — install 부팅 7의 수치도 같은 방향으로
   200ms 밀려 있다. `machine` 체인(q35)의 `Run /init`은 4.38초.
6. mutation 넷 전부 빨감(1 · 2 · 4는 `touchpad_test`가 부팅 전에 먼저). `Killed` 0번.

   | mutation | 체인에서 잡은 자리 | 문구 | 시간 |
   |---|---|---|---|
   | 1 탭의 시간 조건을 뺀다 | 검사 23 | `a 500ms hold clicked (press lines: 2 …); a tap must be shorter than 180ms` | 1분 54초 |
   | 2 두 손가락을 이동으로 보낸다 | 검사 24 | `two fingers 90 units down left the viewport at '… offset=165 …', expected six rows above the bottom` | 2분 13초 |
   | 3 터치패드를 디코더에 잇지 않는다 | 검사 21 | `the replay touchpad came out as '… skip … kind=touchpad …', expected 'open … kind=touchpad slots=2 …'` | 1분 56초 |
   | 4 세로 배율의 resolution 보정을 뺀다 | 검사 22 | `after 'move 0 60' the last at line is '… x=768 y=476 …', expected x=768 y=464` | 2분 15초 |

7. plan의 기대와 다른 것 — Task 0-4의 커널 단계가 `skipping make`가 아니라 변경 없는 make였다 · 증분 빌드 1분 54초 ·
   부팅 7의 기다림 0/900ms(plan 100/1100) · `Run /init` +0.15~0.3초 · `run_mut`의 `tail -5`(여섯 줄이라 `tail -6`) ·
   `machine` 체인의 PASS 줄은 `PASS` 단독이라 plan의 `rg` 패턴에 안 잡힌다.
8. 루트 게이트(2회): 열아홉 체인 2/2, `PD-M3 check PASS` 둘, `FAIL` 0줄, 49분 29초(2026-10-05, docker 작업 없이 단독, 첫
   체인이 커널 전체 빌드를 치렀다). `install` 부팅 7은 `delay_use=4`에서 `init waited 1100ms` · `1200ms`. PD-M2의 47분 46초에서
   1분 43초가 늘었다 — 커널 전체 빌드와 부팅마다 약 0.8초(실측 5 · design 위험 7의 덧붙임).
