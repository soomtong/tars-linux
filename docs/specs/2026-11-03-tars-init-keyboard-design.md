# TARS Init Keyboard — Design

접두사: IK

Status: 끝남(2026-11-03). IK-M0 — 루트 게이트 `RUNS=3` 27/27 × 3, 키보드 없는 부팅이 3.33초 빨라졌다(실측 1).

관련 문서: `2026-11-02-tars-keyboard-hotplug-design.md`(KH. terminal이 키보드를 스스로 찾고 꽂고 빼는 것을 따라간다 — 비목표 2가
이 설계로 넘긴 자리) · `2026-08-20-tars-hardware-discovery-design.md`(HD. init의 키보드 탐색과 argv의 장치 칸이 생긴 곳) ·
`docs/decisions/project_keyboard_hotplug.md` · `docs/guides/carryover.md`의 KH 절 첫 항목.

## 한 줄 요약

KH 뒤로 아무도 쓰지 않는 PID 1의 키보드 고르기 · 3초 기다림과 terminal argv의 `device_path` 칸을 걷는다. 키보드 없이 뜨는
부팅이 약 3초 빨라지고, "입력 장치는 terminal이 고른다"는 KH의 규칙이 코드에도 그대로 남는다.

## 왜 지금인가

KH 결정 1이 키보드 고르기를 terminal로 옮겼다. 핫플러그를 하려면 장치를 계속 지켜보는 프로세스가 장치를 골라야 하고, 그것은
terminal이다. 그 뒤로 terminal은 argv의 장치 칸을 읽기만 하고 열지 않는다(`terminal/src/main.zig`의 `readArgs` 주석). 그런데 init은
여전히 키보드를 고르고, 못 찾으면 3초를 기다린 뒤 전원 버튼(`event0`)을 "키보드"로 넘긴다(KH 실측 3 — 3.07초). 체인 넷이 그
로그 줄을 판정으로 보고 있어서 KH가 범위를 지키려고 남겼다(KH 비목표 2). 사용자가 MI 다음으로 이것을 골랐다(2026-11-03).

## 사용자가 정한 것 (2026-11-03)

1. argv의 `device_path` 칸은 뺀다. 칸 번호가 당겨지고 `ARGC`가 10에서 9가 된다. 자리표 글자로 남기지 않는다 — 뜻 없는 칸을
   계약에 두지 않는다.
2. 체인 넷의 판정은 terminal의 `keyboard> open /dev/input/eventN name=…` 줄로 옮긴다. 그리고 init이 키보드 줄을 더는 안
   찍는다는 음성 검사를 더해 걷어 낸 것을 붙박는다.

## 착수 전에 아는 것 (2026-11-03에 코드에서 확인, `273298d`)

### 확인 1 — init에서 걷을 것과 남길 것

걷는다: `init/src/devices.zig`의 `findKeyboard` · `findKeyboardWaiting` · `resolveKeyboard` · `resolveKeyboardWaiting` ·
`KEYBOARD_WAIT_MS`(3000) · `KEYBOARD_POLL_MS`(25) · `sleepMillis`, `init/src/main.zig`의 `Boot.keyboard_path`와
`probeDevices`의 호출 한 줄, `devices_test.zig`의 해당 검사(`findKeyboard` 둘 · 떨어지기 · 기다림 둘).

남긴다: `looksLikeKeyboard`(전원 버튼 판정 `looksLikePowerButton`이 "키보드가 아니다"를 본다 — QEMU의 AT 키보드도 `KEY_POWER`를
가진다), `bitSet`, `Path` · `devicePath` · `readAttr` · `readFile`(`openPowerButtons`가 쓴다). 전원 버튼 탐색은 그대로다.

주석에서 이 이름들을 인용하는 자리: `storage.zig`(두 곳 — 순수/콜의 선, "먼저 훑고 자는" 함정), `environ.zig` · `services.zig`
(`keyboard_path`와 같은 근거), `openPowerButtons`의 "resolveKeyboard와 같은 이유", `terminal/src/pointer.zig`의 "init의
`devices.looksLikeKeyboard`와 기준이 같다"(이것은 남으므로 그대로).

### 확인 2 — argv의 장치 칸

`shared/screen_args.zig`의 `Slot.device = 4`, `Args.device_path`, `default_device_path`(`/dev/input/event0`), `encode` · `decode`의 한
줄씩. init은 부팅에서 `keyboard_path.cstr()`를 넣고, `reload terminal`(SA-M1)은 `decode`로 꺼낸 값을 그대로 다시 넣는다. terminal은
`readArgs`에서 `decode`할 뿐 이 필드를 안 쓴다. execve의 argv는 첫 null에서 끝나므로 칸을 null로 비울 수는 없다.

`ARGC`를 쓰는 상수가 terminal 말고 다섯이다 — `clock.CHRONYD_ARGV` · `net.DHCPCD_ARGV` · `wifi.WIFI_ARGV` ·
`bluetooth.DBUS_ARGV` · `BLUETOOTHD_ARGV`. 길이를 손으로 맞춘 배열 리터럴이라 `ARGC`가 줄면 컴파일이 막힌다 — 빠뜨릴 수 없다.
init의 탈출로(`TERMINAL_FLAG_SLOT`)는 `Slot.flag`(2번)라 안 움직인다.

### 확인 3 — 판정 줄을 보는 체인은 넷이다

| 체인 | 지금 | 
|---|---|
| `device/check.sh` | `tars-init: keyboard device /dev/input/event` 있음, `no keyboard found` 없음(진입 목록에도 이름이 있다) |
| `terminal/check.sh` | 같음 |
| `machine/check.sh` | init 줄에 `USB Keyboard`(i8042=off라 "USB 경로가 통째로 섰다"의 증거) |
| `keyboard/check.sh` | 키보드 없는 부팅에서 `no keyboard found`가 있어야 한다(판정 1) |

terminal 쪽 줄은 이미 있다 — `terminal: keyboard> open {path} name={name}` · `keyboard> none` · `skip` · `close`(KH). `input` ·
`terminal` 체인은 이미 `keyboard> open /dev/input/event`를 기다린다. `docs/guides/lessons.md`의 로그 줄 목록에도 init의 두 줄이 있다.

### 확인 4 — 3초는 어디에 있나

PID 1이 `probeDevices`에서 키보드를 찾고, 없으면 25ms 간격으로 3000ms까지 다시 훑은 뒤 terminal을 띄운다. 키보드가 있는 부팅은
첫 훑기에서 찾으므로 비용이 거의 없고, 키보드가 PID 1보다 늦게 잡히는 부팅(RM-M3 — QEMU USB 키보드 0.88~0.93초)은 그만큼,
키보드가 없는 부팅은 3초 전부를 낸다. 시리얼 로그에서 시각이 붙은 것은 커널 줄뿐이다(`[    4.037508] Run /init as init process`).
init의 줄에는 시각이 없고, 이 줄을 보는 체인 넷 가운데 콘솔에 명령을 넣을 수 있는 것도 없다(`device` · `keyboard`는
`-serial file:`).

## 결정

### 결정 1 — init은 키보드를 고르지도 기다리지도 않는다

`probeDevices`는 DRM 로그와 전원 버튼만 한다. 로그 줄 `tars-init: keyboard device …` · `no keyboard found …` · `keyboard showed up
after …`이 없어진다. HD design 결정 6("못 찾아도 부팅을 막지 않는다")은 대상이 사라져 닫힌다.

### 결정 2 — `Slot.device`를 빼고 `ARGC`는 9다(사용자 결정 1)

`hangul` 5→4 · `latin` 6→5 · `toggles` 7→6 · `clipboard` 8→7 · `user` 9→8. `Args.device_path`와 `default_device_path`를 지운다.
`Args`에 기본값이 없으므로 init이 필드를 남겨 두면 컴파일이 막힌다(SA-M1의 설계가 이 변경을 지킨다). terminal과 init은 같은
`shared/` 파일을 함께 컴파일하므로 한쪽만 바뀌는 일은 없다 — 둘은 언제나 같은 initrd에 실린다.

### 결정 3 — 체인 넷의 판정(사용자 결정 2)

- `device` · `terminal`: `terminal: keyboard> open /dev/input/event[0-9]+ name=` 있음. 그리고 `tars-init: keyboard device` ·
  `tars-init: no keyboard found` 둘 다 없음.
- `machine`: `terminal: keyboard> open … name=…USB Keyboard` 있음(i8042=off의 뜻은 그대로). init 줄의 음성 검사.
- `keyboard`: 판정 1에서 `no keyboard found`의 요구를 빼고 그 줄이 없음을 본다. `keyboard> none`은 그대로.
- `lessons.md`의 로그 줄 목록에서 init의 두 줄을 지우고 terminal의 `keyboard> open`을 그 자리에.

### 결정 4 — 3초가 사라진 것을 한 번 재서 적는다(게이트에 넣지 않는다)

M0의 바꾸기 전과 뒤에 일회용 측정을 돌린다. QEMU를 키보드 없이(`keyboard` 체인과 같은 `i8042=off`, USB 키보드 없음) 띄우고 호스트가
시리얼 로그를 0.05초 간격으로 보며 `Run /init`과 `tars-init: started terminal`이 나타난 시각을 적는다. 그 차가 "PID 1이 시작해 terminal을
띄우기까지"다. USB 키보드를 단 부팅도 같은 방법으로 재서 대조한다. 체인에 측정 줄을 영구히 두지 않는 이유는 TCG의 부팅 시간이
흔들려 판정할 수 없고, 콘솔 없는 체인에서는 시각을 얻을 길이 호스트의 관찰뿐이기 때문이다.

## 위험

### 위험 1 — terminal이 키보드보다 먼저 뜨는 부팅이 생긴다

지금은 PID 1이 늦게 잡히는 USB 키보드를 기다려 주므로 terminal은 언제나 키보드가 있는 상태에서 뜬다. 걷으면 terminal이 먼저 뜨고
uevent로 나중에 연다(KH의 길, `keyboard` 체인이 판정 2로 본다). 동작은 맞지만, 프롬프트가 그려지자마자 monitor로 키를 치는 체인은
키보드가 열리기 전의 글자를 잃을 수 있다. QEMU의 USB 키보드는 0.9초쯤 잡히고 TCG의 fish 프롬프트는 그보다 늦으므로 드물 것으로
본다. M0는 루트 게이트를 `RUNS=3`으로 돌려 흔들림을 찾는다. 나오면 그 체인이 `keyboard> open`을 기다린 뒤 치게 한다(`input` ·
`terminal` 체인이 이미 그렇다).

### 위험 2 — 실기에서 terminal의 첫 훑기와 USB 열거의 경합

위험 1과 같은 길의 실기 쪽이다. KH가 uevent로 이미 덮었다(`keyboard> open`이 부팅 뒤에도 뜬다). 새로 생기는 것은 없다.

## 비목표

1. 장치별 수정키 · 키보드마다 다른 `keyboard=`(KH 비목표 1 · 5, `carryover.md`의 KH 절) — 이 설계는 걷기만 한다.
2. 전원 버튼 탐색을 terminal로 옮기는 것. 전원 버튼은 PID 1이 기계를 끄는 데 쓰므로 PID 1의 것이다.
3. 포인터 · 키보드 판정의 두 벌(`init devices.looksLikeKeyboard` · `terminal pointer.looksLikeKeyboard`)을 `shared/`로 합치는 것.
   init 쪽은 sysfs 글자를, terminal 쪽은 ioctl 비트를 읽어 입력이 다르다.

## Milestone

- IK-M0: 결정 1~4 전부. init · `shared/screen_args.zig` · 서비스 argv 상수 다섯 · 체인 넷 · `lessons.md`. 바꾸기 전과 뒤의
  `Run /init` → `started terminal` 시간(결정 4), 루트 게이트 `RUNS=3`.

milestone은 하나다. 걷는 일이라 나눌 단계가 없다.

## 실측 (M0, 2026-11-03)

### 실측 0 — 바꾸기 전, `Run /init` → `started terminal`(결정 4, Task 0)

`273298d`의 빌드, 컨테이너의 TCG, `.ik-measure.sh`(저장소 뿌리, 추적 안 함 — Task 4가 같은 것을 다시 돌린 뒤 지운다). 호스트가
시리얼 로그를 0.05초마다 본 값이다.

| 부팅 | 세 번 | init의 키보드 줄 | terminal |
|---|---|---|---|
| A 키보드 없음 | 3.39 · 3.40 · 3.37초 | `no keyboard found …` → `keyboard device /dev/input/event0 (Power Button)` | `keyboard> none` |
| B USB 키보드 | 0.06 · 0.00 · 0.06초 | `keyboard device /dev/input/event1 (QEMU QEMU USB Keyboard)` | `keyboard> open` |

A의 3.4초 가운데 3.0초가 기다림이다. B는 세 번 모두 init의 첫 훑기에서 찾았다 — 이 기계에서 USB 키보드는 PID 1보다 먼저 잡힌다
(위험 1이 게이트에서 드물 것이라는 근거). 커널의 `Run /init`은 두 부팅 모두 4.0초 언저리.

### 실측 1 — 바꾼 뒤, 같은 측정(Task 4)

IK-M0의 작업 트리(커밋 전), 같은 스크립트 · 같은 기계.

| 부팅 | 세 번 | init의 키보드 줄 | terminal |
|---|---|---|---|
| A 키보드 없음 | 0.05 · 0.06 · 0.06초 | 없음 | `keyboard> none` |
| B USB 키보드 | 0.06 · 0.05 · 0.06초 | 없음 | `keyboard> open` |

키보드 없는 부팅이 약 3.33초 줄었다 — 기다림 3.0초에 sysfs 훑기 120번(25ms 간격의 잠과 훑기)을 더한 것이다. B는 그대로다. 예전에도
첫 훑기에서 찾아 기다림이 없었으므로, 지운 코드가 키보드 있는 부팅에 주던 비용은 훑기 한 번(측정 해상도 0.05초 아래)뿐이었다.
커널의 `Run /init`은 3.96~4.12초로 실측 0과 같다 — 줄어든 것은 PID 1 안의 시간이다.

### 실측 2 — 체인 넷(Task 4)

한 번씩, 컨테이너에서: device 159초 · terminal 162초 · machine 150초 · keyboard 169초, 넷 다 초록. machine의 판정 6은
`terminal: keyboard> open /dev/input/event1 name=QEMU QEMU USB Keyboard`(event0은 전원 버튼)로 섰고, 그 뒤의 타이핑까지 갔다 —
terminal이 init보다 먼저 떠도 fish 배너를 기다리는 동안 USB 키보드는 이미 열려 있었다(위험 1이 이 회차에는 안 나왔다).

컴파일러가 plan에 없던 `ARGC` 길이 배열 리터럴 둘을 짚었다 — `main.zig`의 서비스 하나의 argv(`placeService` 근처)와 콘솔 셸의
argv. plan 확인의 "서비스 argv 상수 다섯"은 이름 붙은 상수만 센 것이었다.

### 실측 3 — 루트 게이트 `RUNS=3`(Task 5, 위험 1)

27 체인 × 3 = 81번 전부 초록, cut log lines 전부 0. prebuild 355초 + lanes 1821초(약 36분). 판정을 바꾼 넷(`HD-M2` device ·
`CM-M2` terminal · `RM-M1` machine · `KH-M2` keyboard)도 3/3. 위험 1(terminal이 키보드보다 먼저 떠 프롬프트 직후 친 글자를 잃는다)은
81번 중 한 번도 안 나왔다 — 실측 0의 B대로 QEMU의 USB 키보드는 PID 1보다 먼저 열거되므로, 체인을 `keyboard> open` 대기로 고칠
일이 없었다. 로그는 `out/gate-logs/20261103-141238`.
