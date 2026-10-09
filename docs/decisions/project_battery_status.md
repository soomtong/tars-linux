---
name: project_battery_status
description: 상태 줄 오른쪽 끝의 배터리 잔량 칸을 만든 서브프로젝트 Battery Status(BS-M0 · M1, 2026-10-09). 폭 4 · 색 셋 · 배터리가 없으면 한 픽셀도 안 바뀐다. 게이트의 가짜 배터리는 커널 내장 test_power이고 함정이 셋이다 — 파라미터 값은 true/false(0은 조용히 무시), 배터리를 켜는 uevent는 test_ac에서 온다, getter가 엉뚱한 표를 써서 되읽으면 on/off다. 실기에서는 내장 cmdline과 limine의 initcall_blacklist 두 겹으로 끈다
metadata:
  type: project
---

Battery Status(BS)는 사용자의 요청 한 줄("노트북인 경우 배터리 잔량 표시", 2026-10-08)에서 시작했다. design은
`docs/specs/2026-10-08-tars-battery-status-design.md`(결정 12 · 확인한 것 10), plan은
`docs/plans/2026-10-08-tars-battery-status-bs-m0.md`(커널 · 순수 층) · `-bs-m1.md`(`main.zig` 배선 · 새 체인)이고 각 plan의 "착수 전에
확정한 것" 절이 design과 달라진 자리다. 설계 · plan 셋은 Opus, 구현 둘은 Sonnet 서브에이전트가 했다. plan의 코드를 고친 곳은 0이고
기대 글자를 고친 곳이 1이다(아래 "교훈").

## test_power의 함정 — 다시 조사하지 말 것

QEMU 10.0.13에는 배터리 장치가 없다(`-device help`에 `batt` · `power`가 0줄). 그래서 게이트의 배터리는 커널 내장
`CONFIG_TEST_POWER=y`가 만드는 `test_ac` · `test_battery` · `test_usb` 셋이고, 그 드라이버에 함정이 셋 있다.

1. 파라미터 값은 `true` · `false`다. `test_power.battery_present=0`은 `map_present`에서 못 찾아 조용히 무시되고, 배터리가 켜진 채
   남는다. 내장 cmdline이 `0`이었으면 모든 부팅에 50%짜리 배터리가 떴을 것이다. battery 체인 검사 A1이 그 자리를 본다.
2. `battery_present`를 쓰면 uevent가 `test_battery`가 아니라 `test_ac`에서 온다(`param_set_battery_present`가
   `test_power_supplies[TEST_AC]`에 `power_supply_changed`를 부른다). 그래서 terminal은 장치 이름도 `ACTION`도 안 보고
   `SUBSYSTEM=power_supply`만 보고 다시 훑는다(`battery.ueventIsPowerSupply`). 이름을 보는 코드는 검사 A2에서 빨개진다.
3. getter 넷(status · health · present · technology)이 `map_ac_online` 표로 글자를 찾는다. 그래서
   `/sys/module/test_power/parameters/battery_present`를 되읽으면 `on` · `off`가 나온다. 게이트는 파라미터 파일을 되읽어 판정하지
   않고 `/sys/class/power_supply/`와 terminal의 줄로 본다.

## 실기에서 두 겹으로 끄는 이유

| 겹 | 자리 | 끄는 것 |
|---|---|---|
| 1 | 내장 cmdline `mac80211_hwsim.radios=0 test_power.battery_present=false` | 배터리의 `present`만. 모든 부팅에 걸린다 |
| 2 | `boot/limine.conf`의 `cmdline:`에 `initcall_blacklist=test_power_init` | test_power의 등록 자체. limine으로 뜨는 부팅(USB ISO · 설치된 ESP)에 걸린다 |

겹 1만으로도 칸은 안 뜬다. 겹 2가 있는 이유는 test_power가 실기에 남기는 부작용 둘이다. `test_ac`가 online이면
`power_supply_is_system_supplied()`가 언제나 참이라, ACPI 배터리가 방전 중 `rate_now == 0`인 순간에 `Discharging` 대신
`Not charging`을 낸다 — 우리 칸이 초록이 된다. 그리고 ACPI가 `test_battery`에 `SCOPE`를 물을 때마다 test_power의 `default`
갈래가 `deliberately report errors` 줄을 커널 로그에 쌓는다. 블랙리스트를 내장 cmdline에 안 두는 것은 뒤에 붙인 파라미터로
지울 수 없어서 게이트가 test_power를 다시 켤 길이 없어지기 때문이다.

블랙리스트는 이름이 틀려도 `pr_debug`만 찍는다. 그것을 잡는 자리는 `machine` 체인 판정 14
(`battery> scan seen=0 present=0 pick=none`) 하나뿐이다. `-kernel`로 뜨는 다른 체인은 전부 `seen=1 present=0`이다.

## ACPI 배터리에서 갈리는 것

- ACPI는 빠진 배터리를 power_supply째 지운다(`sysfs_remove_battery`). `present=0`인 디렉터리를 거르는 것은 주로 test_power를
  위한 것이다.
- ACPI에는 `capacity` 파일이 아예 없는 배터리가 있다(`full_cap_broken`). 그래서 `capacity`의 `ENOENT`는 "빠졌다"가 아니고 칸은
  `  ?%`다(M1 plan 확정 4). `ENOENT`를 빠짐으로 보면 칸이 영영 안 뜨고 주기마다 다시 훑는다. 빠짐은 `status`의 `ENOENT` ·
  `ENODEV`이거나 `capacity`의 `ENODEV`다.
- ACPI는 `status`를 읽을 때마다 `_BST`를 평가한다(EC 왕복, `cache_time` 1000ms). 주기를 60초로 둔 근거 하나다.

## 결정

- 자리는 상태 줄의 오른쪽 끝(col `cols - 4`)이다(design 결정 6). 꼬리에 붙이면 `W2` · `COPY` · 받아쓰기 칸이 밀리고, 꼬리 산수에
  넷째 길이가 들어가 색이 밀리는 사고의 자리가 는다. 오른쪽 끝이면 `status.zig`와 `status> text=`가 그대로라, 그 줄을 글자 그대로
  비교하는 체인 넷이 배터리가 있는 기계에서도 같은 값을 본다. 왼쪽 문자열과 `GAP`만큼 안 떨어지면 안 그린다.
- 색 셋은 전부 새 상수다(`STATUS_BAT` · `STATUS_BAT_PLUG` · `STATUS_BAT_LOW`). 회색도 `STATUS_FG`를 재사용하지 않는다 —
  [[project_copy_indicator]]와 같은 이유로, 띠 전체를 센 픽셀 수를 그 칸의 값으로 읽으려면 그 색이 그 칸에만 쓰여야 한다.
- `dumpStatus`의 메모가 칸의 글자와 갈래를 함께 기억한다. 잔량 10인 채 충전이 시작되면 글자 ` 10%`는 그대로이고 색만 바뀐다.
  글자만 보면 새 줄이 안 찍힌다 — IS-M1이 `CAPS`에서 겪은 구멍이다. 검사 A4가 본다.
- 다시 그릴지와 메모의 비교를 일부러 다른 함수로 했다(M1 plan 확정 8). 다시 그리기는 `std.meta.eql`, 메모는 `sameBatteryCell`이다.
  같은 함수를 쓰면 mutation m3(갈래를 뺀다)가 다시 그리기도 막아, A4가 빨개졌을 때 메모 때문인지 안 그려서인지가 안 갈린다.
- 처음 훑기는 `needs_redraw`를 안 켠다(M1 plan 확정 7). 켜면 셸보다 먼저 빈 프레임이 하나 그려져 스물한 체인 전부의
  `screen>` 줄 수가 하나씩 는다. 처음 훑기가 첫 프레임 앞이라 첫 프레임에 칸이 이미 있다(검사 B1).
- 검사 A3은 로그를 다 받은 뒤 거꾸로 읽는다(M1 plan 확정 14). 칸을 그린 프레임의 `screen>`이 바로 앞 프레임과 글자까지 같고
  그 사이에 `key>` 줄이 없으면 "키도 PTY 출력도 없이 다시 그렸다"이다. 이렇게 하면 게이트가 "프롬프트가 다 그려진 순간"을 맞혀
  기준을 잡을 필요가 없다. 셸은 bash다 — 배경 작업이 끝난 것을 다음 프롬프트에서야 알려서 성공 경로가 uevent 하나다.
- 배터리가 둘이면 이름순 첫째만 보인다. 합산(`energy_*` · `charge_*`)은 게이트가 못 밟는 갈래라 안 했다.

## 실측

| 무엇 | 값 |
|---|---|
| 칸의 픽셀 | ` 50%` norm 73 · ` 10%` low 66 · ` 10%` plug 66(A4 — 같은 넉 자를 색만 바꿨다) · `100%` plug 90 |
| A3 | `same=1 keys=0` |
| A5의 줄 수 | `scan` 셋 · `read` 셋(결과가 바뀔 때만 찍힌다) |
| mutation 셋 | `present` 거르기를 지운 판 → A1, `drainUevents`가 power_supply를 안 알리는 판 → A2, 메모에서 갈래를 뺀 판 → A4 |
| 주기 경로 | uevent를 끈 판에서 잔량을 쓴 뒤 칸이 바뀌기까지 40.2초(60초 안) |
| hangul 기준값 | `383 pixel(s) of text and a dim CAPS (off=87)` 그대로 |
| BS-M0 루트 게이트 | 21체인 2/2, 57분 20초(dictation 체인의 간헐 하나는 그 체인만 두 번 다시 돌려 초록) |
| BS-M1 루트 게이트 | 22체인 전부 `PASS: 2/2`, 1시간 00분 18초, `skipping make` 43, 44회차 전부 `A=0 B=0 C=0`, hangul `383 … (off=87)` 두 번, 빨간 줄 0 |

## 교훈 — 폭 고정 칸의 기대 글자는 검사 출력에서 베낀다

plan과 design 결정 11의 표가 잔량 10의 칸을 `  10%`(다섯 자)로 적었다. 칸은 `CELL_LEN` 넉 자라 실제는 ` 10%`이고 공백 둘은
`  5%`뿐이다. 코드는 맞았고 첫 battery 체인이 A3에서 빨갰다. 앞 공백의 개수는 사람이 눈으로 세면 틀리는 값이다. 게이트의 기대
글자는 `battery_test`의 `cellText` 검사가 찍은 값이나 실측 줄에서 베낀다.

## 남긴 것

- 실기 노트북에서 한 번 보는 것 — `docs/guides/lessons.md`의 "이월 숙제" BS 항목.
- 주기 경로(60초)는 게이트가 안 본다. `battery.pollTimeout`을 `battery_test`가 호스트에서 보고, 위의 40.2초가 한 번의 실측이다.

관련: [[project_input_status]] · [[project_copy_indicator]] · [[project_wireless]](게이트 전용 커널 드라이버의 첫 사례) ·
[[project_real_machine]] · [[project_pointer_devices]](uevent 소켓) · [[project_kernel_config]] · [[project_gate_chain_composition]]
