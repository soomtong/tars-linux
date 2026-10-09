---
name: project_device_discovery
description: "입력 장치를 번호가 아니라 capability로 찾는다(HD-M0~M2, RM-M3). sysfs 비트맵은 높은 워드가 앞이고 빈 상위 워드는 생략된다 · EV_KEY는 0번이 아니라 1번 · 키보드도 KEY_POWER를 갖고 있어 전원 버튼 판정에 '키보드가 아니다'를 더한다 · 폴백(event0)이 게이트에 사각지대를 만들어 '못 찾았다' 음성 검사로 닫는다 · USB 키보드는 비동기 열거라 3초까지 다시 본다"
metadata:
  node_type: memory
  type: project
---

HD-M0(2026-08-21)이 `terminal`의 `/dev/input/event0` 상수를 없애며 세웠고
HD-M2와 RM-M3이 더했다. 코드는 `init/src/devices.zig`, 호스트 검사는
`init/src/devices_test.zig`, 게이트는 `terminal/check.sh` · `device/check.sh`다.
milestone별 경과와 게이트 시간은 2026-10-10에 지웠다(커밋 이력에 있다).
키보드와 전원 버튼은 PID 1이 이 방식으로 찾고, 마우스 · 터치패드는 뒤의
PD가 `terminal`이 uevent로 찾게 했다([[project_pointer_devices]]) — 여기는
PID 1 쪽이다.

## sysfs 비트맵은 뒤에서부터 세어야 한다

`/sys/class/input/eventN/device/capabilities/{ev,key}`는 `input_print_bitmap`이
배열을 거꾸로 훑으며 찍고 빈 상위 워드는 건너뛴다. 그래서 가장 높은 워드가
맨 앞이고(`"1 0"`은 64번 비트가 1, 0번 비트가 0) 워드 개수가 고정이 아니다
(전원 버튼의 `ev`는 `"3"` 한 워드). `bitSet`은 토큰을 세어 `count - 1 -
want_word`로 역산하고, 물어본 비트가 찍힌 워드 수를 넘으면 0이다. 방향을
뒤집어 구현해도 대부분의 장치에서 그럴듯하게 동작하므로 호스트 검사가
`"1 0"` 하나로 방향을 정면으로 겨냥한다.

## `EV_KEY`는 1번이다 — 0번으로 착각하면 전부 통과한다

`input-event-codes.h`에서 0번은 `EV_SYN`이다. 거의 모든 입력 장치가 갖고
있어 0번으로 읽으면 `ev` 검사가 무조건 참이 되는데, `key` 검사가 남아 있어
결과는 대체로 맞게 나오고 "`ev`를 보고 있다"는 착각만 남는다. 검사에
`looksLikeKeyboard("0", keyboard_key)`가 거짓이어야 한다는 줄을 둔 이유다.
같은 함정이 다른 상수에도 있다 — 비트 번호는 헤더에서 직접 확인한다.

## 이름이 아니라 capability로 판정한다

키보드는 `KEY_ESC`(1)~`KEY_D`(32)의 비트가 전부 1인가로(udev `input_id`와 같은
기준). USB 키보드는 제조사마다 이름이 달라 문자열에 기대면 QEMU 밖에서
깨진다. 이름은 로그에만 쓴다.

전원 버튼은 `EV_KEY` + `KEY_POWER`(116) + 키보드가 아니다. 셋째 조건이 HD-M2가
알아낸 것이다 — AT 키보드의 `key` 1번 워드 `0xfeffffdfffefffff`의 52번
비트(116 = 64 + 52)가 1이라 키보드도 `KEY_POWER`를 갖는다(`atkbd`가 ACPI
확장 키를 스캔코드 표에 갖고 있고 USB 키보드도 대개 같다). 키보드 판정에
위임하면 그 범위를 나중에 바꿔도 "키보드로 뽑힌 장치는 버튼으로 안 뽑힌다"가
따라온다.

제외하지 않으면 PID 1이 키보드 fd를 `poll`에 넣어 글자마다 감독 루프가
깨어나고, 안 읽으면 바쁜 루프가 되며([[project_init_supervisor]]), 전원 키를
무엇으로 옮길지라는 Input Policy의 결정([[project_input_policy]])을 몰래
가져간다. 그런데도 종료는 정상 동작하므로 이 실패는 조용하다 — 그래서
`device/check.sh`가 `watching 1 power button`을 개수까지 요구한다. 번호는
하드웨어 사정이라 요구하지 않고 개수는 우리 판정의 결과라 요구한다.

## 전원 버튼은 전부 연다, 키보드는 첫 하나

ACPI가 FADT의 고정 하드웨어 버튼과 DSDT의 장치를 각각 등록할 수 있고 어느
것이 우는지 밖에서 모르므로 `findPowerButtons`는 끝까지 훑는다(상한
`MAX_BUTTONS` = 4, QEMU에서는 하나). fd는 `O_NONBLOCK`으로 열어야
`drainButton`이 `EAGAIN`으로 끝난다. 디렉터리를 순회하지 않고 `event0`부터
서른두 번 열어 보는 것은 init에 libc도 힙도 없어서다
([[project_zig_c_uapi_rule]]) — 없는 번호는 `ENOENT`로 즉시 돌아온다.

## 탐색 함수는 뿌리 경로를 인자로 받는다 — 검사가 진짜 `/sys`를 읽지 않게

`devices_test`는 빌드 컨테이너에서 돌고 그 `/sys`는 개발 기계의 것이다.
검사는 `/tmp/tars-devices-test` 아래 가짜 트리(`event0` 전원 버튼 · `event1`
AT 키보드 · `event2` `BTN_LEFT`뿐인 마우스)를 만들어 `event1`이 뽑히는지
본다. `open(2)`은 `/dev/input` 고정이다 — 호스트 검사가 시험할 대상이
아니다. `power_test`가 `reboot(2)`에 닿으면 안 된다는 규칙과 같은 계열이다
([[project_power_management]]).

## 폴백이 게이트에 사각지대를 만든다

탐색이 실패해도 부팅을 막지 않고 `event0`으로 떨어진다(design 결정 6 —
탐색기의 버그가 기계를 못 켜게 만드는 것이 가장 나쁜 결말). 그런데 실패
경로도 `keyboard device /dev/input/event0 (...)`을 평소와 같은 모양으로
찍으므로 그 한 줄만 보면 "탐색이 돌았다"와 "실패했지만 답이 같다"가
안 갈린다. 그리고 ACPI를 켠 지금 `event0`은 전원 버튼이라 폴백은 전원
버튼을 키보드로 연다.

닫는 방법은 쌍이다. `terminal/check.sh` · `device/check.sh`가 `keyboard
device /dev/input/event`가 있어야 한다와 `no keyboard found`가 없어야 한다를
둘 다 요구하고, 전원 버튼도 같은 쌍이다. `terminal/check.sh`의 `ACPI:
button: Power Button` 검사는 "번호가 밀려도 찾는다"는 증명이 관측으로만 남지
않게 붙박은 것이다 — ACPI를 다시 끄면 입력 장치가 하나가 되어 틀린
탐색기도 통과한다. HD-M0 시점에는 `event0`이 곧 키보드라 비트맵을 거꾸로
읽어도 부팅 게이트를 통과했고, 그래서 무게중심이 호스트 검사에 있다.

## 탐색은 버그 없이도 실패한다 — 장치가 아직 없을 수 있다 (RM-M3)

USB 키보드는 비동기로 열거된다. PID 1이 훑는 시점에 아직 없으면 탐색기는
정확하게 "없다"고 답하고 전원 버튼으로 떨어진다. QEMU에서는 스무 번에 한
번쯤이지만 허브 둘을 거친 키보드는 1.7초라 실기에서는 이쪽이 정상이다.
처방은 `findKeyboardWaiting` — 25ms 간격으로 `KEYBOARD_WAIT_MS`(3초)까지
다시 보고, 상한이 끝나면 예전대로 떨어진다(결정 6을 안 어긴다).

| 실수 | 검사 | 왜 위험한가 |
|---|---|---|
| 묻기 전에 자기 | `SleptBeforeLooking` | 모든 부팅이 느려지고 증상이 "좀 느리다"뿐이라 아무도 못 잡는다 |
| 기다림이 없음 | `GaveUpTooEarly` | 고친 줄 알았는데 안 고쳤다 |

게이트가 초록인 것이 고침의 증거가 아니었다 — 넣고 6/6 통과인데 `keyboard
showed up after` 줄이 한 번도 안 나왔다. `init`이 커지며 훑는 시점이 밀려
우연히 경합을 피한 것이고, 열거를 늦추고 나서야 고침이 도는 것을 봤다.

## 결과 경로의 수명과 결정의 자리

힙이 없으므로 탐색 결과는 `devices.Path`(고정 버퍼)로 `main()`의 스택에 살고
`argv`에 그 포인터가 들어간다. `supervise()`가 `noreturn`이라 그 프레임이
프로세스 수명 내내 산다 — 누군가 `supervise`를 반환하게 만들면 이 포인터가
뜬다(`Path`의 doc comment가 유일한 방어). `terminal`은 `argv[4]`를 열 뿐
번호를 스스로 고르지 않는다 — 하드웨어를 살펴 결정하는 일이 두 프로세스에
나뉘면 다른 답을 얻는다([[project_config_persistence]]와 같은 규칙).
`terminal` 안의 기본값 `/dev/input/event0`은 인자가 없을 때만 쓰이는 값이라
게이트가 밟는 경로가 아니다.

## How to apply

새 장치 종류를 찾을 때 (1) 이름이 아니라 capability로, (2) 비트 번호는
`input-event-codes.h`에서 직접, (3) 그 키를 다른 장치가 함께 갖고 있지 않은지
실측 비트맵으로, (4) 호스트 검사를 먼저 쓰되 뿌리 경로를 인자로, (5) 폴백을
두었다면 게이트가 그 폴백을 구별하는지 따로, (6) 판정이 틀려도 기능은 도는
경우라면 개수나 대상을 게이트가 직접 세게. 로그 문구를 바꾸면 두 체인의 같은
문자열도 고친다(중복은 의도된 것).

관련: [[project_power_management]], [[project_gate_chain_composition]],
[[project_init_supervisor]], [[project_input_policy]],
[[project_config_persistence]], [[project_zig_c_uapi_rule]],
[[project_pointer_devices]], [[project_real_machine]]
