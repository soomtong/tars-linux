# TARS Battery Status — Design

Date: 2026-10-08
Status: design을 썼다(구현 전). BS-M0 · BS-M1의 plan은 milestone마다 그 시점에 쓴다.

사용자의 요청 한 줄에서 시작한다(2026-10-08).

> 노트북인 경우 배터리 잔량 표시.

## 한 줄 요약

배터리가 있는 기계에서는 상태 줄의 오른쪽 끝에 폭 4의 잔량 칸이 뜬다. 충전 중인지 · 낮은지는 색이 말한다. 배터리가 없는
기계에서는 화면이 한 픽셀도 안 바뀌고 terminal은 지금처럼 이벤트가 없으면 깨지 않는다.

```
  EN  신세벌 PCS  쿼티  CAPS                                              85%   ← 방전 중(회색)
  EN  신세벌 PCS  쿼티  CAPS  W2  COPY                                    85%   ← 꼬리 칸이 붙어도 그 자리다
  EN  신세벌 PCS  쿼티  CAPS                                             100%   ← 어댑터가 꽂혔다(초록)
  EN  신세벌 PCS  쿼티  CAPS                                              12%   ← 15% 이하이고 방전 중(빨강)
  EN  신세벌 PCS  쿼티  CAPS                                                    ← 배터리가 없다
```

## 배경

상태 줄(IS, 2026-09-09)은 "지금 켜져 있는 것을 잊었다"를 푸는 자리이고, 지금까지 그 줄에 오른 것은 전부 terminal 안의 상태다
(한/영 · 자판 · 대문자 잠금 · 워크스페이스 · copy mode · 받아쓰기). 배터리는 처음으로 terminal 밖, 커널이 아는 기계의 상태다.

커널 쪽은 이미 준비되어 있다. RM-M3(2026-09-10)이 노트북 ACPI 다섯을 켜면서 `CONFIG_ACPI_BATTERY=y` · `CONFIG_ACPI_AC=y`가
들어왔고(`docs/decisions/project_real_machine.md`의 "노트북 ACPI 다섯" 절) `CONFIG_POWER_SUPPLY=y`다. 실기 노트북이면
`/sys/class/power_supply/BAT0/`(이름은 기계마다 다르다)에 파일이 있다. 그런데 QEMU에는 배터리가 없어서 RM은 이것을
"게이트가 못 보는 것"으로 남겼다. 이번 서브프로젝트의 절반은 그 칸을 게이트가 보게 만드는 일이다.

milestone은 둘(BS-M0 · BS-M1)이다. 크기는 Copy Indicator(CI)보다 크고 Escape Latin(EL)과 비슷하다 — 칸 하나를 더하는 일 위에
커널 설정 한 줄, 갱신 길 하나(poll timeout), 새 체인 하나가 얹힌다.

## 착수 전에 확인한 것

2026-10-08, HEAD `fbffcd5`. lead가 보낸 전제를 저장소 안의 커널 소스(`kernel/src/linux-6.18.42/`)와 코드로 다시 읽었다.
바로잡은 것이 다섯이다.

1. sysfs 파일의 모양 — 맞다. `power_supply_sysfs.c`의 표가 `status`를 `Unknown` · `Charging` · `Discharging` ·
   `Not charging` · `Full`로 쓰고, `capacity`는 정수와 줄바꿈이다. `scope` 파일(`System` · `Device`)도 있다.
2. test_power의 파라미터 — 바로잡았다. `battery_present`는 `0` · `1`이 아니라 `false` · `true`를 받는다.
   `param_set_battery_present`가 `map_present`(`"false"` · `"true"`)에서 `strncasecmp`로 찾고, 못 찾으면 값을 안 바꾼다
   (`map_get_value`의 `def_val`). 그래서 `test_power.battery_present=0`은 아무 일도 안 하고 배터리가 있는 채로 남는다.
   `battery_status`는 `charging` · `discharging` · `not-charging` · `full`이고 `battery_capacity`만 정수다.
3. 장치 이름 — 바로잡았다. `test_ac` · `test_battery` · `test_usb`, 전부 소문자다. `test_ac`는 `Mains`, `test_usb`는
   `USB` 형이고 둘 다 기본값이 online이다(`ac_online = 1` · `usb_online = 1`).
4. 파라미터를 쓰면 uevent가 나간다 — 맞지만 하나가 다르다. `param_set_battery_present`는
   `test_power_supplies[TEST_AC]`에 `power_supply_changed()`를 부른다. 배터리를 켜고 끄는 uevent는
   `POWER_SUPPLY_NAME=test_battery`가 아니라 `test_ac`에서 온다. 그래서 terminal은 이름이 아니라 `SUBSYSTEM=power_supply`만
   보고 다시 훑어야 한다(결정 7). 읽기 쪽도 틀려 있다 — getter 넷(status · health · present · technology)이 `map_ac_online`으로
   글자를 찾아서, `/sys/module/test_power/parameters/battery_present`를 읽으면 `on` · `off`가, `battery_status`를 읽으면 대개
   `unknown`이 나온다. 게이트는 파라미터 파일을 되읽어 판정하지 않는다.
5. "sysfs 파일 둘을 읽는 비용은 없다" — 바로잡았다. test_power는 그렇지만 ACPI 배터리는 `status`를 읽을 때마다
   `acpi_battery_get_state`가 `_BST`를 평가한다(EC 왕복). `cache_time`(기본 1000ms) 안의 둘째 읽기는 캐시를 쓰므로 `status`와
   `capacity`를 잇달아 읽으면 평가는 한 번이다. 작지만 0은 아니고, 결정 8의 주기를 정하는 근거가 된다.
6. ACPI 배터리가 빠지면 — 새로 안 것. `acpi_battery_update`가 `!present`이면 `sysfs_remove_battery`로 power_supply를 아예
   지운다. 실기에서 `present=0`인 배터리 디렉터리는 거의 안 보이고, 그 걸러내기는 주로 test_power를 위한 것이다. 반대로
   ACPI는 `capacity`를 아예 안 내는 배터리가 있다(`full_cap_broken`이면 속성 표에서 빠진다) — 결정 4의 `?%`가 그 자리다.
7. test_power가 실기에 남기는 것 — 새로 안 것. 결정 9가 이것 때문에 끄는 겹을 하나 더 둔다. 내장된 test_power는 실기에서도
   power_supply 셋을 등록한다. `test_ac`가 online이면 `power_supply_is_system_supplied()`가 언제나 참이 되고, ACPI 배터리는
   방전 중에 `rate_now == 0`이면 그 값으로 `Discharging` 대신 `Not charging`을 낸다(`acpi_battery_handle_discharging`).
   `ac_online`을 꺼도 그 함수가 `test_battery`에 `SCOPE`를 물을 때 test_power의 `default` 갈래가
   `pr_info("... some properties deliberately report errors.")`를 찍으므로, 방전 중 `status`를 읽을 때마다 커널 로그가 한 줄씩
   쌓인다. 그리고 `CONFIG_THERMAL=y`라서 `test_battery`가 trip 없는 thermal zone 하나를 등록한다(trip이 없어 아무 일도 안 한다).
8. `CONFIG_MODULES`가 꺼져 있다 — 맞다(`# CONFIG_MODULES is not set`). 그래도 내장 모듈의 파라미터는
   `/sys/module/test_power/parameters/`에 0644로 생긴다. `kernel/params.c`의 `param_sysfs_builtin`은 `CONFIG_SYSFS` 아래에
   있고 `CONFIG_MODULES`를 안 본다.
9. 내장 cmdline과 QEMU `-append`의 순서 — 맞다. `arch/x86/kernel/setup.c`가 `CMDLINE_OVERRIDE`가 아니면 내장 문자열 뒤에
   부트로더의 것을 붙인다. 같은 파라미터는 뒤의 것이 이긴다 — wifi 체인이 `mac80211_hwsim.radios=3`으로 내장 `0`을 덮는
   것과 같은 길이다.

10. QEMU에 배터리 장치가 없다 — 설계를 쓸 때는 OrbStack이 꺼져 있어 못 봤고, lead가 같은 날 확인했다. 컨테이너의
    QEMU 10.0.13에서 `qemu-system-x86_64 -device help | grep -i -E "batt|power"`가 한 줄도 안 낸다. RM design의 표("ACPI
    객체가 없다")와 같고, 그래서 결정 9의 test_power 말고는 게이트가 배터리를 만들 길이 없다.

## 목표

1. 배터리가 있는 기계에서 상태 줄에 잔량이 뜨고, 충전 중 · 낮음이 색으로 갈린다.
2. 키를 안 쳐도 값이 바뀐다 — 어댑터를 꽂거나 뺄 때는 곧바로, 방전 중의 잔량은 늦어도 1분 안에.
3. 배터리가 없는 기계(데스크톱 · QEMU 게이트의 기본 부팅)에서는 화면이 한 픽셀도 안 바뀌고, poll은 지금처럼 무한 대기다.
4. 게이트가 칸이 뜨는 것 · 바뀌는 것 · 사라지는 것 · 색을 본다.

## 결정

### 결정 1 — "노트북인 경우"는 보여 줄 배터리가 있는 경우다. DMI chassis는 안 본다

`/sys/class/power_supply/` 아래에서 세 조건을 다 만족하는 장치가 하나 이상 있으면 칸이 뜬다.

| 파일 | 조건 | 왜 |
|---|---|---|
| `type` | `Battery` | `Mains` · `USB`는 어댑터다 |
| `present` | `0`이 아니다(파일이 없으면 있는 것으로 본다) | test_power의 꺼진 배터리를 거른다(결정 9). ACPI는 빠진 배터리를 아예 지우므로 실기에서는 거의 안 걸린다 |
| `scope` | `Device`가 아니다(파일이 없으면 통과) | 무선 마우스 · 블루투스 헤드셋의 배터리가 `Device`다. 커널의 `__power_supply_is_system_supplied`도 같은 값으로 거른다. 지금 커널은 `HID_BATTERY_STRENGTH`가 꺼져 있어 그런 장치가 없지만, 켜지는 날 마우스 잔량이 노트북 잔량 자리에 뜨면 안 된다 |

DMI chassis type(`/sys/class/dmi/id/chassis_type`)을 안 쓰는 이유는 셋이다. 첫째, 요청이 말하는 것은 "노트북이라는 분류"가
아니라 "보여 줄 잔량"이다 — 배터리를 뺀 노트북에는 보여 줄 것이 없고, 배터리가 붙은 미니 PC에는 있다. 둘째, firmware가
적는 값이라 틀린 기계가 흔하다(컨버터블 · 태블릿이 `Notebook`이 아닌 번호를 쓰고, 일부 노트북은 `Other`를 쓴다). 셋째, 배터리
유무로 판정하면 게이트가 test_power 하나로 두 갈래를 다 만든다. chassis로 판정하면 QEMU가 내는 값(`Other`)을 바꿀 길이 없어
"노트북" 갈래를 게이트가 영영 못 밟는다.

### 결정 2 — 배터리가 둘이면 이름순 첫째 하나만 보인다

ThinkPad의 내장 + 교체형처럼 `BAT0` · `BAT1`이 함께 있으면 이름순 첫째(`BAT0`)를 보인다. 합산은 비목표 2다.

합산이 맞는 길이기는 하다 — 퍼센트는 평균을 내면 안 되고 `energy_now` · `energy_full`(전원 단위가 mA인 배터리는
`charge_now` · `charge_full`)을 더해 나눠야 한다. 그런데 그 길은 파일 넷과 단위 두 갈래를 더하고, test_power는 배터리를 하나만
만들어서 게이트가 그 갈래를 못 밟는다. 배터리가 둘인 노트북은 지금 드물다(교체형 외장 배터리를 단 ThinkPad 계열은 2019년
무렵에 끝났다). 그래서 단순한 쪽을 고르고, 몇 개를 봤는지는 로그의 `seen=`(결정 10)이 말하게 한다. 사람이 그 기계를 쓰게 되면
`battery.zig`의 순수 함수 하나(`pick`)를 넓히는 일이다.

### 결정 3 — 읽는 파일은 `status`와 `capacity` 둘이다. 충전 여부는 어댑터가 아니라 배터리의 `status`가 말한다

어댑터의 `online`(ACPI `AC` · `ADP1`)을 안 읽는다. USB-C 충전기는 `Mains`가 아니라 UCSI의 `USB` 형 장치로 보이는 기계가 있고,
어댑터가 꽂혀 있어도 충전 한도(예: 80%) 때문에 배터리가 충전을 안 하는 기계가 있다. 배터리의 `status`는 그 둘을 이미 해석한
값이다 — `Charging` · `Full` · `Not charging`이 "어댑터가 꽂혔다"를, `Discharging`이 "배터리로 돈다"를 말한다.

`capacity`가 0~100 밖이면 그 끝으로 자른다. 정수가 아니거나 읽기가 실패하면 "모른다"이고 칸은 `?%`다(결정 4).
`status`를 못 읽으면 `Unknown`으로 본다.

### 결정 4 — 칸의 글자는 폭 4의 ASCII다 — `100%` · ` 85%` · `  5%` · `  ?%`

숫자를 오른쪽에 붙이고 앞을 공백으로 채운다. 잔량이 85에서 9로 내려가도 `%`의 자리가 안 움직인다. IS 결정 2(자리 고정)와
같은 규율이다.

ASCII만 쓴다. 상태 줄의 기존 칸이 전부 ASCII와 한글이고, 폰트가 unifont라 배터리 기호(U+1F50B)의 글리프가 없다. 그리고
게이트는 `status>` 줄의 바이트를 글자 그대로 비교한다 — 기호를 쓰면 그 바이트가 판정 문자열에 들어간다.

`BAT` 같은 머리글자를 안 붙인다. 상태 줄 오른쪽 끝의 `85%`가 무엇인지 헷갈릴 다른 값(음량 · 밝기)이 이 기계에는 없다.
잔량을 모를 때 `?%`인 것은 워크스페이스 칸이 범위 밖 번호에 `?`를 쓰는 것(`status.statusText`)과 같은 처리다 — 칸의 길이를
지키고, 사람에게 "배터리는 있는데 값을 못 읽었다"를 말한다.

### 결정 5 — 상태는 색 셋이다. 색은 전부 새 상수다

| 갈래 | 조건 | 색 |
|---|---|---|
| `plugged` | `status`가 `Charging` · `Full` · `Not charging` | `STATUS_BAT_PLUG` = `0x0060C070`(초록) |
| `low` | `plugged`가 아니고 잔량이 15 이하 | `STATUS_BAT_LOW` = `0x00E05040`(빨강) |
| `normal` | 나머지(`Discharging` · `Unknown`, 잔량을 모름) | `STATUS_BAT` = `0x00909AA0`(회색) |

IS 결정 3이 `CAPS`를 글자가 아니라 색으로 가른 것과 같은 규율이다. `CHG` · `+` 같은 글자를 붙이면 칸의 폭이 상태마다
달라지거나 폭 5가 된다.

`Full`과 `Not charging`을 `Charging`과 같은 색으로 묶는다. 사람이 이 칸에서 알고 싶은 것은 "어댑터를 뽑아도 되는가 · 꽂아야
하는가"이고, 그 셋은 전부 꽂혀 있다는 뜻이다. 가득 찬 것은 `100%`가 따로 말한다. 꽂혀 있는 동안에는 잔량이 낮아도 `low`가
아니다 — 위험이 줄어드는 중이다.

문턱 15는 "곧 꽂아야 한다"를 말할 만큼 이르고, 방전 대부분의 시간 동안 빨강이 안 보일 만큼 낮은 값이다. 설정으로 빼지
않는다(비목표 5).

색이 전부 새것인 이유는 CI 결정 3과 같다. `dumpStatus`가 띠 전체에서 색마다 픽셀을 세고 그 수를 "그 칸의 값"으로 읽는데,
그 전제는 그 색이 여백 안에서 그 칸에만 쓰인다는 것이다. `normal`의 회색도 `STATUS_FG`(`0x808890`)를 재사용하지 않는다 —
재사용하면 배터리가 있는 부팅에서 `ink fg=` 기준값(hangul 체인의 383 · 381)이 바뀌고, 배터리 칸이 그려졌는지를 따로 셀 길이
없다. 눈에는 `STATUS_FG`와 거의 같은 회색이고 값만 다르다. 셋 다 기존 색(여백 `0x102030` · `STATUS_*` 다섯 · 구분선 ·
매치 색 둘 · 커서 · 화살표 둘)과 겹치지 않는다.

### 결정 6 — 자리는 상태 줄의 오른쪽 끝이고, 격자의 오른쪽 끝에 맞춘다. `status.zig`는 안 고친다

lead는 `CAPS` 뒤 꼬리의 어딘가를 권했다. 꼬리 대신 오른쪽 끝을 고른다.

| 후보 | 왜 아닌가 |
|---|---|
| `CAPS` 바로 뒤 | 배터리가 있는 기계에서 `W2` · `COPY` · 받아쓰기가 여섯 칸 밀린다. `drawStatus`가 꼬리에서 물러나는 산수에 넷째 길이가 들어가고, 그 산수가 틀리면 색이 한 칸 밀린다(CI 위험 2) |
| 꼬리의 맨 끝(받아쓰기 뒤) | 받아쓰기 칸은 길이가 변해서 맨 끝에 있다(`status.zig`의 주석). 그 뒤에 두면 `REC` → `PASSWORD`마다 배터리가 움직인다 |
| 오른쪽 끝 | 고른 것 |

오른쪽 끝이면 배터리 칸은 왼쪽 문자열과 아무 데서도 안 만난다.

- `status.statusText`와 `MAX_LEN`이 그대로다. 꼬리 산수(`dict_len` · `copy_len` · `ws_len`)에 아무것도 안 더해지므로, 그
  산수가 틀려서 색이 밀리는 사고의 자리가 늘지 않는다.
- `status> text=`가 그대로다. 그 줄을 글자 그대로 비교하는 판정(hangul · copy · pane · dictation 체인의 것)이 배터리가
  있는 기계에서도 같은 값을 본다. 배터리 칸은 따로 있는 줄이 말한다(결정 10).
- 화면에서 자리가 절대 위치로 고정된다. 왼쪽 칸들이 붙고 떨어져도 안 움직인다.

x는 `GRID_X + (cols - 4) * CELL_W`다. `cols`는 `main.zig`가 시작할 때 구하는 격자 전체의 폭(`(fb.width - 2 * GRID_X) / CELL_W`)이고,
그래서 `%`의 오른쪽 끝이 격자의 오른쪽 끝(1280×800이면 x=1260)과 같다 — 왼쪽 끝이 `GRID_X`인 것과 짝이다. `Status`
구조체에 `cols`와 배터리 칸 하나(`?battery.Cell`)가 더해진다. 왼쪽 문자열의 끝 col이 배터리 칸의 시작 col에서 `GAP`만큼 안
떨어져 있으면 배터리를 안 그린다(겹쳐 그리지 않는다). 지금 가장 긴 왼쪽 줄은 약 50칸이고 1024픽셀 화면의 격자도 123칸이라
실제로 닿을 일은 없지만, `setPixel`에 범위 검사가 없는 저장소에서 겹침을 산수로 막는 자리는 있어야 한다.

### 결정 7 — 순수 층은 `battery.zig`이고, 시스템 콜은 `main.zig`의 배터리 절에 있다

`status.zig` · `pointer.zig` · `dictation.zig`와 같은 모양이다. `battery.zig`는 파일 내용(바이트)을 받아 값을 돌려주고, 파일을 여는
것은 `main.zig`다. `battery_test`가 호스트에서 본다(`build.zig`에 `status_test`와 같은 자리로 등록).

| 함수 | 하는 일 |
|---|---|
| `parseStatus(bytes) Status` | 다섯 글자 → enum(줄바꿈을 떼고 비교, 모르는 글자는 `unknown`) |
| `parseCapacity(bytes) ?u8` | 정수 → 0~100으로 자른 값, 정수가 아니면 null |
| `counts(type, present, scope) bool` | 결정 1의 세 조건 |
| `pick(names) ?name` | 결정 1을 통과한 이름 중 이름순 첫째(결정 2) |
| `class(status, capacity) Class` | 결정 5의 표(`plugged` · `low` · `normal`) |
| `cellText(capacity, buf) []const u8` | 결정 4의 넉 자 |
| `ueventIsPowerSupply(msg) bool` | datagram 하나가 `SUBSYSTEM=power_supply`인가(`ACTION`은 안 본다 — add · remove · change 전부 다시 훑는다) |
| `pollTimeout(now_ms, due_ms: ?i64) c_int` | 결정 8의 timeout. `due`가 null이면 `-1` |

`ueventIsPowerSupply`가 이름도 `ACTION`도 안 보는 이유는 확인한 것 4와 6이다. test_power의 배터리 켜기는 `test_ac`에서 오고,
ACPI 배터리를 갈아 끼우면 `add` · `remove`가 온다. 어느 것이든 다시 훑는 비용은 디렉터리 하나에 장치 몇이다.

### 결정 8 — 갱신은 처음 훑기 · uevent · 60초 주기 셋이고, 배터리가 없으면 timeout은 `-1`이다

| 길 | 언제 | 무엇을 |
|---|---|---|
| 처음 훑기 | 첫 프레임 전(포인터의 `scanPointers` 옆) | 디렉터리를 훑어 고르고 값을 읽는다. 첫 `status>` 줄에 배터리가 이미 있어야 한다 |
| uevent | `drainUevents`가 `SUBSYSTEM=power_supply`를 하나라도 봤거나 `ENOBUFS`였다 | 다시 훑고 읽는다. 주기의 기한을 지금 + 60초로 미룬다 |
| 주기 | 고른 배터리가 있고 기한이 지났다 | 고른 배터리의 두 파일만 읽는다. 읽기가 `ENOENT` · `ENODEV`로 실패하면(빠졌는데 uevent를 놓쳤다) 다시 훑는다 |

uevent가 먼저인 이유: 어댑터를 꽂고 빼는 것은 ACPI가 notify로 알리고(`acpi_battery_notify` → `power_supply_changed`) 사람이 곧바로
화면을 본다. 주기가 따로 있는 이유: 방전 중의 잔량 변화를 firmware가 알리는지는 기계마다 다르다. ACPI에는 잔량 알림을 보내는
의무가 없고, 커널의 ACPI 배터리 드라이버는 스스로 polling하지 않는다.

주기는 60초다. 칸이 정수 퍼센트라서 보통의 방전(1%에 1~3분)에서 60초는 많아야 1%의 늦음이다. 30초로 줄이면 늦음이 반이
되지만 깨는 횟수와 `_BST` 평가(확인한 것 5)가 두 배가 된다. 60초면 한 시간에 60번 깬다.

timeout의 계산. 바퀴마다 `poll` 앞에서 `battery.pollTimeout(now, due)`를 부른다. 고른 배터리가 없으면 `due`가 null이고 답은
`-1` — 배터리가 없는 기계는 지금과 똑같이 이벤트가 없으면 CPU를 전혀 안 쓴다. 있으면 `max(0, due - now)`이고 `c_int`
범위로 자른다. `poll`이 0으로 돌아왔든 키 때문에 돌아왔든, `poll` 뒤에 `now >= due`일 때만 읽는다 — 키를 칠 때마다 읽지 않는다.
시계는 단조 시계(Zig `std.Io`의 `.awake`, 렌더 시간을 재는 것과 같은 것)다. 커널에 `SUSPEND`가 없어서 잠든 동안의 시간은 따질
일이 없다.

다시 그리기는 값이 바뀌었을 때만이다. 처음 훑기 · uevent · 주기가 고른 이름 · 칸의 글자 · 갈래 중 하나라도 바꿨을 때만
`needs_redraw`를 켠다. 이것이 모든 체인에 걸리는 조건이다 — test_power가 내장된 커널은 부팅마다 power_supply 셋을 등록하며
`change` uevent를 하나씩 보낸다(`power_supply_deferred_register_work`). 그것은 initcall 단계라 대개 terminal이 소켓을 열기
전에 지나가지만, 다른 power_supply uevent(실기의 ACPI notify, 게스트에서 누가 `uevent` 파일에 쓴 것)는 언제든 온다. 값이
그대로인데 다시 그리면 배터리가 없는 체인에도 `screen>` 프레임이 하나 더 생긴다.

uevent 소켓은 새로 안 연다. PD-M0이 연 소켓(그룹 1)이 이미 모든 uevent를 받고 `drainUevents`가 `input`만 골라 쓰고 있다.
`drainUevents`가 "power_supply를 봤다"를 돌려주게 넓힌다. 소켓 열기가 실패한 부팅(`uevent_fd = -1`)에서는 처음 훑기와 주기만
남는다 — 배터리를 갈아 끼운 것은 그 배터리를 다시 읽다 실패할 때 알게 되고, 부팅 뒤에 처음 생긴 배터리는 못 본다.
포인터의 핫플러그가 그때 잃는 것과 같은 종류다.

### 결정 9 — 게이트용 가짜 배터리는 test_power이고, 실기에서는 두 겹으로 끈다

`CONFIG_TEST_POWER=y`(내장)를 켠다. 모듈이 없으므로 내장 말고는 길이 없고, `CONFIG_MODULES`를 켜는 것은 서브프로젝트 하나
크기다.

끄는 겹이 둘이다.

| 겹 | 자리 | 무엇을 끄나 | 누구에게 |
|---|---|---|---|
| 1 | 내장 cmdline `CONFIG_CMDLINE="mac80211_hwsim.radios=0 test_power.battery_present=false"` | 배터리의 `present`만 | 모든 부팅. QEMU `-kernel` 게이트가 이 상태로 뜨고, terminal은 결정 1로 `test_battery`를 안 센다 |
| 2 | `boot/limine.conf`의 `cmdline:`에 `initcall_blacklist=test_power_init` | test_power 전부(등록 자체를 안 한다) | limine으로 뜨는 부팅 — USB로 뜬 실기와, `disk.espConf`가 이 줄을 베껴 쓰는 설치된 실기 |

겹 1만으로도 칸은 안 뜬다. 겹 2가 더 있는 이유는 확인한 것 7이다 — 실기에 `test_ac`가 online으로 남으면 ACPI 배터리의
`Discharging`이 `Not charging`으로 바뀌는 자리가 생기고(그러면 우리 칸이 초록이 된다), 꺼 두어도 방전 중 `status`를 읽을 때마다
커널 로그가 한 줄씩 쌓인다. 등록 자체를 막으면 둘 다 없다. `initcall_blacklist`는 `CONFIG_KALLSYMS=y`가 있어야 이름을
맞추는데 지금 켜져 있다(`init/main.c`의 `initcall_blacklisted`). 겹 2를 내장 cmdline에 안 두는 이유는, 블랙리스트는 뒤에 붙인
파라미터로 지울 수 없어서 게이트가 test_power를 다시 켤 길이 없어지기 때문이다.

내장 cmdline의 값은 반드시 `false`다(확인한 것 2). `0`이면 조용히 무시되어 모든 부팅에 50%짜리 배터리가 뜬다 — 그 사고는
hangul 체인의 `text=` 비교가 아니라(배터리 칸은 그 줄에 없다, 결정 6) battery 체인의 검사 A1이 잡는다.

`wifi/check.sh`의 검사 1은 지금 `grep -x 'CONFIG_CMDLINE="mac80211_hwsim.radios=0"'`로 줄 전체를 본다. 줄 전체를 두 체인이
각자 글자 그대로 적으면, 다음에 셋째 파라미터를 더하는 사람이 두 체인을 함께 고쳐야 한다. 그래서 두 체인 모두 자기 낱말
하나가 그 줄에 낱말로 있는지만 본다.

```bash
grep -E '^CONFIG_CMDLINE="([^"]* )?mac80211_hwsim\.radios=0( [^"]*)?"$' "$CONFIG"     # wifi
grep -E '^CONFIG_CMDLINE="([^"]* )?test_power\.battery_present=false( [^"]*)?"$' "$CONFIG"   # battery
```

`.config`는 `olddefconfig`의 고정점으로 되접는다(`docs/decisions/project_kernel_config.md`). `TEST_POWER`는 의존이 `POWER_SUPPLY`
하나라 딸려 오는 기호가 없을 것으로 보지만, 되접기 diff가 그것을 확정한다.

### 결정 10 — 로그는 `battery>` 줄 둘과 `status> battery` 줄 하나다

| 줄 | 언제 | 모양 |
|---|---|---|
| 훑기 | 처음 훑기, 그리고 다시 훑은 결과가 지난번과 다를 때 | `terminal: battery> scan seen=1 present=0 pick=none` |
| 값 | 고른 배터리의 `capacity` · `status`가 바뀔 때 | `terminal: battery> read test_battery capacity=50 status=Discharging class=normal` |
| 칸 | `dumpStatus`가 찍을 때(값이 바뀔 때) — 배터리가 없어도 찍는다 | `terminal: status> battery cell=" 50%" ink norm=N plug=M low=K` · 없으면 `cell=none` |

`seen`은 `type=Battery`인 장치의 수, `present`는 그중 결정 1을 통과한 수다. 이 두 수가 부팅의 종류를 가른다 — QEMU `-kernel`
부팅은 `seen=1 present=0`(test_power가 있고 꺼져 있다), limine 부팅은 `seen=0`(겹 2가 등록을 막았다), 배터리를 켠 부팅은
`seen=1 present=1`이다. machine 체인이 이 차이로 겹 2를 본다(결정 11).

`capacity`를 못 읽으면 `capacity=?`, 시스템 콜이 실패한 훑기는 `terminal: battery> scan failed error=…`이다. 머리는 PD의
`terminal: pointer>`와 같은 모양이고, 전부 `logline.print` 한 번이다(AL).

칸 줄은 `caps ink`와 같은 이유로 색 셋을 한 줄에 함께 찍는다 — 하나만 보면 "안 그렸다"와 "다른 색으로 그렸다"가 안 갈린다.
x 범위는 안 잰다. 세 색이 여백에서 이 칸에만 쓰이므로 띠 전체를 세도 답이 같다(IS-M1의 이유 그대로). `cell=`의 값을 따옴표로
감싸는 것은 앞의 공백이 값이기 때문이다.

`dumpStatus`의 메모가 넓어진다. 지금은 `text`와 `caps`를 기억하는데, 배터리 칸의 글자와 갈래도 기억해야 한다. 잔량이 그대로인
채 어댑터를 꽂으면 글자(` 50%`)는 안 바뀌고 색만 바뀌는데, 메모가 글자만 보면 새 줄이 안 찍힌다 — IS-M1이 `CAPS`에서 겪은 것과
같은 구멍이고 게이트 검사 A4가 그 자리를 본다.

### 결정 11 — 게이트는 새 체인 `battery/check.sh` 하나와 machine 체인의 판정 하나다

새 체인을 고르는 이유. 기존 체인에 얹는 쪽(hangul · pane)은 부팅을 하나 아끼지만 셋을 잃는다. 커널 설정 검사(wifi 검사 1의
자리)가 기능과 떨어진다. 배터리를 켜는 부팅과 안 켜는 부팅(WL 기억의 "파라미터를 안 준 부팅을 반드시 하나 둔다")을 남의
설정 디스크 위에서 짜야 한다. 빨개졌을 때 입력 체인의 실패인지 배터리의 실패인지 한 번 더 갈라야 한다. 새 하드웨어 영역마다
체인 하나를 둔 선례(pointer · audio · wifi)를 따른다. 스물두번째 체인이고 `CHAINS`에는 `"BS-M1:./battery/check.sh"`, monitor는
45494다(새 체인은 45494부터, `docs/guides/lessons.md`). 설정 디스크는 없다. QEMU 호출은 `-nic none`이다(`require_explicit_nic`).

검사 0(부팅 없음) — `kernel/.config`에 `CONFIG_TEST_POWER=y` · `CONFIG_ACPI_BATTERY=y` · `CONFIG_POWER_SUPPLY=y`가 있고, 결정 9의
cmdline 낱말이 있고, `boot/limine.conf`의 `cmdline:` 줄에 `initcall_blacklist=test_power_init`가 있다.

부팅 A — `-append "console=ttyS0"`(내장 cmdline 그대로, 배터리 꺼짐), monitor 45494.

| 검사 | 하는 것 | 본다 |
|---|---|---|
| A1 | 키 없음 | `battery> scan seen=1 present=0 pick=none` · 마지막 `status> text=`가 `EN  신세벌 PCS  쿼티  CAPS` · `status> battery cell=none ink norm=0 plug=0 low=0` |
| A2 | `cd /sys/module/test_power/parameters` · `echo true > battery_present` | `scan … present=1 pick=test_battery` · `cell=" 50%"` · `norm>0 plug=0 low=0` · `status> text=`는 A1과 같다 |
| A3 | bash에서 `( sleep 2; echo 10 > battery_capacity ) &`를 치고 프롬프트가 돌아온 뒤 키를 더 안 친다 | 키도 PTY 출력도 없이 새 칸 줄 `cell="  10%"` · `low>0 norm=0` |
| A4 | `echo charging > battery_status` | `cell="  10%"`(글자 그대로) · `plug>0 low=0` — 글자가 같은데 줄이 새로 찍혔다 |
| A5 | `echo false > battery_present` | `scan … present=0 pick=none` · `cell=none` · 세 수 0 · `status> text=`가 A1과 같다 |

A2는 uevent가 `test_ac`에서 와도 다시 훑는다는 것(확인한 것 4)을, A3은 키 없이 다시 그린다는 것(목표 2)과 `low`를, A4는 결정 10의
메모를, A5는 A2와 짝으로 "영영 붙어 있는" 코드를 막는다(IS-M1 plan 확정 7). A3에 bash를 쓰는 이유는 bash가 배경 작업이 끝난
것을 다음 프롬프트에서야 알리기 때문이다(`set -b`가 꺼져 있다) — 끝나는 순간 PTY에 글자를 쓰는 셸이면 그 출력이 다시 그리기를
부르고, 판정의 성공 경로가 둘이 된다(`project_gate_chain_composition`의 "성공 조건이 다른 이유로도 성립하면"). bash는 게스트에
있다(`kernel/guest_tools.sh`, input 체인이 `/usr/bin/bash --norc`를 친다). 정확한 명령과 기다리는 줄은 plan이 정한다.

부팅 B — `-append "console=ttyS0 test_power.battery_present=true test_power.battery_status=full test_power.battery_capacity=100"`,
monitor 없음. 키를 안 친다.

| 검사 | 본다 |
|---|---|
| B1 | 첫 `status> battery` 줄이 이미 `cell="100%"` · `plug>0 norm=0 low=0`이다 — 처음 훑기가 첫 프레임 전에 돌았다. `-append`가 내장 `false`를 덮었다(확인한 것 9) |

machine 체인(ISO를 limine으로 띄운다)에 판정 하나 — `terminal: battery> scan seen=0`. 겹 2가 실제로 test_power의 등록을
막았다는 것이고, 블랙리스트의 이름이 틀리면(컴파일러가 함수 이름을 바꾸는 등) `seen=1`로 빨개진다.

배터리가 없는 쪽의 음성은 따로 안 만든다. 스물한 체인 전부가 이미 `seen=1 present=0`으로 뜨고, `status> text=`를 비교하는 체인은
그 줄이 그대로인지를, hangul 체인의 `ink fg=383` · `caps ink off=87`은 픽셀이 그대로인지를 본다. 값이 그대로인 uevent가 다시
그리기를 부르지 않는다는 것(결정 8)은 `battery_test`가 순수 층에서 보고, 게이트에서는 pointer 체인처럼 `screen>` 줄을 세는
판정이 간접으로 본다.

주기 경로는 게이트가 안 본다. test_power의 모든 setter가 uevent를 부르므로 "uevent 없이 바뀐 값"을 게스트 안에서 만들 길이
없고, 만들 수 있다 해도 60초를 기다리는 것은 회차마다 1분이다. 대신 `battery.pollTimeout`이 순수 함수라 `battery_test`가 기한
전 · 기한 · 기한 뒤 · 배터리 없음(-1) · `c_int` 넘침을 호스트에서 본다. IP-M1의 처방("바깥 상태를 주입 가능한 값으로")과 같다.
plan의 mutation 한 회전이 uevent 처리를 끈 판에서 A2가 빨개지는 것을 보면, 남는 길이 주기뿐일 때 60초 안에 값이 오는지도 한 번
잰다(게이트가 아니라 실측이다).

### 결정 12 — 구현은 milestone 둘이고, 커널과 순수 층이 먼저다

| | 무엇 | 화면 |
|---|---|---|
| BS-M0 | `battery.zig` · `battery_test.zig` · `build.zig`, 커널 `TEST_POWER` · 내장 cmdline, `boot/limine.conf`, `wifi/check.sh`의 grep | 안 바뀐다 — terminal이 아직 배터리를 안 읽는다 |
| BS-M1 | `main.zig` 배선(처음 훑기 · uevent · 주기 · `Status` · `drawStatus` · `dumpStatus`), `battery/check.sh`, `check.sh`의 `CHAINS`, machine 체인의 판정 | 칸이 뜬다 |

M0이 화면을 안 바꾸므로 M0의 루트 게이트는 "test_power가 내장된 커널이 기존 스물한 체인을 아무것도 안 바꾼다"를 따로 증명한다.
M1에서 체인 하나가 빨개지면 커널이 아니라 terminal을 의심하면 된다 — IS가 M0 · M1을 그렇게 가른 값과 같다
(`docs/decisions/project_input_status.md`의 "milestone을 둘로 가른 이유").

## Milestone

### BS-M0 — 가짜 배터리와 순수 층

범위: `terminal/src/battery.zig` · `battery_test.zig` · `terminal/build.zig`(검사 등록), `kernel/.config`(`TEST_POWER=y`, cmdline —
되접어 고정점), `boot/limine.conf`, `wifi/check.sh` 검사 1의 grep.

끝 조건.

1. `battery_test`가 호스트에서 초록이다. 결정 7의 표 여덟 함수를 전부 본다. 특히 `parseStatus`의 다섯 글자와 모르는 글자,
   `parseCapacity`의 `100\n` · `0` · `105` · `-3` · 빈 값 · 글자, `class`의 경계(15는 `low` · 16은 `normal` · `Charging`의 5는
   `plugged`), `cellText`의 넉 자 넷, `pollTimeout`의 다섯 경우.
2. `build.zig`의 `dependOn` 목록이 `git diff`로 한 줄 더한 것만 보인다(IS-M0 실측 4의 사고 — 같은 모양의 줄이 여럿인 자리).
3. `kernel/.config`의 되접기 diff가 비어 있다. 늘어난 기호를 diff로 센다.
4. 사본의 실측 셋 — QEMU `-kernel` 부팅에서 `/sys/class/power_supply/test_battery/present`가 `0`, ISO 부팅에서
   `/sys/class/power_supply/`가 비었다, `-append test_power.battery_present=true`에서 `present`가 `1`. 그리고 QEMU에 ACPI 배터리
   장치가 없다는 것을 컨테이너에서 한 줄로 본다(확인 못 한 것).
5. 루트 게이트 21체인이 초록이다(커널이 바뀌었으므로 전부).

### BS-M1 — 칸이 뜨고 바뀐다

범위: `terminal/src/main.zig`(배터리 절 · `drainUevents` · poll timeout · `Status` · `drawStatus` · `dumpStatus` · 색 상수 셋),
`battery/check.sh`(새 체인), `check.sh`의 `CHAINS`, `machine/check.sh`의 판정 하나.

끝 조건.

1. battery 체인이 초록이다(검사 0 · A1~A5 · B1).
2. machine 체인의 `seen=0` 판정이 초록이다.
3. mutation 셋이 겨냥한 검사에서 빨개진다 — `present` 거르기를 지운 판(A1), `drainUevents`가 power_supply를 안 알리는 판(A2),
   메모에서 갈래를 뺀 판(A4).
4. 진입 검사 셋(`require_build_steps` · `require_no_early_exit_pipe` · `require_explicit_nic`)을 새 체인이 통과한다.
5. 루트 게이트 22체인이 초록이다. hangul 체인의 `ink fg=383` · `caps ink off=87`이 착수 전과 같다.

## 위험

1. 실기의 ACPI 배터리를 게이트가 안 본다. 게이트가 보는 것은 test_power가 내는 sysfs 글자이고, ACPI는 같은 sysfs 코드
   (`power_supply_sysfs.c`)를 지나므로 글자의 모양은 같다. 다른 것은 값의 성질이다 — `capacity`가 없는 배터리, 꽂은 직후 잠깐
   `Unknown`, 잔량 알림을 안 보내는 firmware. 앞의 둘은 결정 3 · 5가 받고(`?%` · `normal`), 셋째는 결정 8의 주기가 받는다.
   요청한 사람의 노트북에서 한 번 보는 것이 남는다 — `running-tars.md`에 "칸이 안 뜨면 `cat /sys/class/power_supply/*/type`"을
   적는다.
2. limine을 안 거치는 부팅에서 test_power가 살아 있다. 다른 부트로더로 실기를 띄우면 겹 2가 없다. 칸은 여전히 안 틀리지만(겹 1)
   확인한 것 7의 두 부작용 — 꽂힌 적 없는 `test_ac`가 online이라 방전 중 `rate_now == 0`인 순간에 ACPI 배터리가 `Not charging`으로
   읽히고 칸이 초록이 되는 것, 그리고 방전 중 읽을 때마다 쌓이는 커널 로그 한 줄 — 이 돌아온다. 지금 TARS의 실기 부팅 길은
   USB ISO와 설치된 ESP 둘이고 둘 다 limine이다.
3. 블랙리스트 이름이 조용히 안 맞을 수 있다. `initcall_blacklist`는 맞는 이름이 없어도 아무 말을 안 한다(`pr_debug`뿐이다).
   machine 체인의 `seen=0`이 그것을 잡는 유일한 자리다.
4. 색만으로 충전 · 낮음을 가른다. 적록 색약이면 `plugged`(초록)와 `low`(빨강)가 비슷하게 보일 수 있다. 밝기를 다르게 골랐고
   (초록이 밝고 빨강이 어둡다) 숫자가 함께 있어서 `12%`를 보고 낮다는 것은 안다. 글자로 가르는 쪽은 결정 5가 버렸다.
5. 배터리가 있는 기계에서는 1분마다 깬다. 깨서 하는 일은 파일 둘을 읽는 것이고, 값이 바뀌었을 때만 다시 그린다. 다시 그리는
   한 프레임이 약 21밀리초다(RC-M0). 1%가 바뀌는 데 보통 몇 분이 걸리므로 그리는 횟수는 한 시간에 수십 번이다.
6. 값이 그대로인 power_supply uevent가 다시 그리기를 부르면(결정 8) 배터리가 없는 체인의 프레임 수가 는다. `screen>` 줄을
   세는 판정(pointer 체인)이 잡을 수 있지만, 잡히는 자리가 배터리와 먼 체인이라 원인을 찾기 어렵다 — plan은 M1의 첫 체인
   회전을 battery 다음에 pointer · render로 돌려 이것을 먼저 본다.
7. 포인터 화살표가 칸 위에 있으면 픽셀 수가 줄어든다. 기존 칸들과 같은 성질이다. battery 체인은 마우스를 안 움직이므로
   화살표가 안 보인다(PD design 결정 4의 조건 2).

## 비목표

1. 남은 시간 표시(`time_to_empty`). firmware마다 값의 질이 크게 다르고 칸의 폭이 늘어난다.
2. 배터리 둘의 합산(결정 2).
3. 어댑터만 따로 보이는 칸, 그리고 배터리 없는 기계에서 "AC" 표시.
4. 낮을 때의 그 밖의 대응 — 소리, 깜빡임, 임계에서 스스로 끄기(전원 관리는 PM의 영역이다).
5. 문턱 · 주기 · 색을 `tars.conf`로 빼기, 칸을 끄는 키. 배터리가 없는 기계에는 이미 아무것도 안 뜬다.
6. 주변기기 배터리(`scope=Device`) 보이기(결정 1).
7. 주기 경로를 게이트로 보기(결정 11).
8. DMI chassis로 노트북을 가르기(결정 1).
9. `CONFIG_MODULES`를 켜서 test_power를 게이트에서만 싣기.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`를 `끝났다(날짜, BS-M0 · M1)`로 고친다.
- `CLAUDE.md`의 완료 표에 한 줄.
- `docs/decisions/project_battery_status.md`를 만들고 `MEMORY.md`에 한 줄. 담을 것 — test_power의 함정 셋(값은 `true`/`false`,
  `present`의 uevent는 `test_ac`에서 온다, getter가 엉뚱한 표를 쓴다), 실기에서 두 겹으로 끄는 이유, 오른쪽 끝을 고른 이유, 메모에
  갈래를 넣은 이유.
- `docs/decisions/project_wireless.md`의 "게이트 전용 커널 드라이버" 문단에 test_power가 둘째 사례이고 cmdline 검사를 낱말
  단위로 바꿨다는 것.
- `docs/decisions/project_real_machine.md`의 "못 본다" 표에서 `ACPI_BATTERY`의 칸 — sysfs 경로는 이제 test_power로 본다.
- `docs/guides/lessons.md` — 포트 45494, 체인 목록, "핵심 파일"에 `battery.zig`.
- `docs/guides/running-tars.md` — 상태 줄 절에 배터리 칸과 색 셋.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-09-02-tars-input-status-design.md` — 상태 줄의 자리 · 색 · 검증 구조(결정 2 · 3 · 5 · 9)
- `docs/specs/2026-10-03-tars-copy-indicator-design.md` — 칸마다 전용 색(결정 3), `text=`와 `ink`의 짝(결정 6)
- `docs/specs/2026-10-06-tars-voice-dictation-design.md` — 받아쓰기 칸이 꼬리의 맨 끝인 이유(결정 11의 M1 문단)
- `docs/specs/2026-09-28-tars-wireless-design.md` · `docs/decisions/project_wireless.md` — 내장 cmdline으로 게이트 전용 드라이버를 끄는 선례
- `docs/decisions/project_kernel_config.md` — `.config` 되접기
- `docs/decisions/project_gate_chain_composition.md` — 음성 검사와 성공 경로가 하나인지
- `kernel/src/linux-6.18.42/drivers/power/supply/test_power.c` · `drivers/acpi/battery.c` · `drivers/power/supply/power_supply_core.c` · `init/main.c`의 `initcall_blacklist`
