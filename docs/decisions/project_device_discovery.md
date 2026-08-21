---
name: project_device_discovery
description: "입력 장치를 번호가 아니라 성질로 찾는다 — sysfs capability 비트맵은 가장 높은 워드가 맨 앞이고 빈 상위 워드는 생략되므로 원하는 워드를 뒤에서부터 세어야 한다; EV_KEY는 1번이고 0번(EV_SYN)으로 착각하면 거의 모든 장치가 키보드로 보인다; 판정 기준은 이름이 아니라 KEY_ESC~KEY_D 범위(udev input_id와 같은 기준)라서 EV_KEY를 가진 전원 버튼이 걸러진다; 탐색 함수는 뿌리 경로를 인자로 받아 검사가 개발 기계의 /sys를 읽지 않게 한다; 탐색 실패는 부팅을 막지 않고 event0으로 떨어지는데 그 폴백이 게이트에 사각지대를 만들므로 'no keyboard found'가 없어야 한다는 둘째 검사로 닫는다; 결과 경로는 main()의 스택에 살고 supervise()가 noreturn이라는 성질에 수명을 의존한다"
metadata:
  node_type: memory
  type: project
---

2026-08-21 HD-M0에서 `terminal/src/main.zig`의 `/dev/input/event0` 상수를
없애며 확정한 것들이다. 코드는 `init/src/devices.zig`, 호스트 검사는
`init/src/devices_test.zig`, 게이트는 `terminal/check.sh`다.

## sysfs 비트맵은 뒤에서부터 세어야 한다

`/sys/class/input/eventN/device/capabilities/{ev,key}`가 내놓는 문자열은
`drivers/input/input.c`의 `input_print_bitmap`이 찍는다. 이 함수는 배열을
**거꾸로** 훑으면서 찍고, 비어 있는 상위 워드는 아예 건너뛴다. 결과가 둘이다.

1. **가장 높은 워드가 맨 앞이다.** `"1 0"`은 워드가 둘이고 뒤엣것이 0번
   워드이므로, 64번 비트가 서 있고 0번 비트는 비어 있다.
2. **워드 개수가 고정이 아니다.** 전원 버튼의 `ev`는 `"3"` 한 워드뿐이다.
   물어본 비트가 찍힌 워드 수를 넘어가면 그 비트는 "서 있지 않다"가 정답이다.

그래서 `bitSet`은 토큰을 한 번 세어 개수를 알아낸 다음 `count - 1 -
want_word`로 앞에서부터의 위치를 역산한다. 방향을 뒤집어 구현해도 대부분의
장치에서 그럴듯하게 동작하기 때문에, 호스트 검사가 `"1 0"` 하나로 방향을
정면으로 겨냥한다.

## `EV_KEY`는 1번이다 — 0번으로 착각하면 전부 통과한다

`include/uapi/linux/input-event-codes.h`에서 0번은 `EV_SYN`이고 `EV_KEY`는
1번이다. 설계 초안에 "비트 0"이라고 적었다가 plan을 쓰면서 고쳤다.

증상이 고약하다. `EV_SYN`은 거의 모든 입력 장치가 갖고 있어서, 0번으로 읽으면
`ev` 검사가 사실상 무조건 참이 된다. 그래도 `key` 비트맵 검사가 남아 있으므로
결과는 대체로 맞게 나오고, "`ev`를 보고 있다"는 착각만 남는다. 검사에
`looksLikeKeyboard("0", keyboard_key)`가 거짓이어야 한다는 줄을 둔 이유가
이것이다.

## 이름이 아니라 capability로 판정한다

기준은 `KEY_ESC`(1)부터 `KEY_D`(32)까지가 전부 서 있는가이고, udev의
`input_id`가 키보드를 분류할 때 쓰는 것과 같은 기준이다. 이 범위가 ESC·숫자
열·Q~D를 덮으므로 "완전한 키보드"만 통과한다.

이름을 안 쓰는 이유는 실 하드웨어 때문이다. USB 키보드는 제조사마다 다른
이름을 달고 나오므로 `"AT Translated Set 2 keyboard"` 같은 문자열에 기대면
QEMU 밖에서 곧바로 깨진다. **이름은 로그에만 쓴다** — 사람이 로그를 읽을 때
"왜 이것을 골랐나"를 알 수 있어야 하기 때문이고, 게이트도 이름까지 요구하지
않는다.

전원 버튼이 이 규칙의 시험대다. 전원 버튼도 `EV_KEY`를 갖고 있어서 `ev`만
보면 키보드와 구별되지 않는다. `KEY_POWER`(116) 하나만 가진 장치가
`KEY_ESC`~`KEY_D`를 채울 수 없다는 것이 유일한 구분선이다.

## 디렉터리를 순회하지 않고 `event0`부터 서른두 번 열어 본다

`/sys/class/input`을 열어 엔트리를 훑는 것이 자연스러워 보이지만, init에는
libc도 힙도 없다([[project_zig_c_uapi_rule]]). `getdents64`를 직접 다루면
버퍼 관리와 가변 길이 레코드 파싱이 따라 들어온다. 장치 번호는 0부터 촘촘히
붙으므로 `open`을 서른두 번 시도하는 편이 짧고 예측 가능하다. 없는 번호는
`ENOENT`로 즉시 돌아온다.

## 탐색 함수는 뿌리 경로를 인자로 받는다

`findKeyboard`와 `resolveKeyboard`가 `/sys/class/input`을 상수로 박지 않고
인자로 받는 이유는 **검사가 진짜 `/sys`를 읽으면 안 되기 때문이다.**
`devices_test`는 빌드 컨테이너 안에서 도는데, 그 안의 `/sys`는 개발 기계의
것이라 무엇이 꽂혀 있느냐에 따라 결과가 달라진다. 검사는
`/tmp/tars-devices-test` 아래에 장치 넷짜리 가짜 트리를 직접 만들고 그것만
읽는다.

`power_test`가 `reboot(2)`에 닿으면 안 된다는 규칙과 같은 계열이다
([[project_power_management]]). **호스트에서 도는 검사는 개발 기계의 상태를
읽지도 쓰지도 않아야 한다.**

가짜 트리의 배치가 검사의 내용이다. `event0`에 전원 버튼, `event1`에 AT
키보드, `event2`에 `BTN_LEFT`만 가진 마우스를 놓고 `event1`이 선택되는지
본다. 번호가 앞선 장치를 건너뛰었다는 것이 "번호가 아니라 성질로 골랐다"의
증거이고, HD-M1에서 ACPI를 켜면 실제로 이 배치가 된다.

## 폴백이 게이트에 사각지대를 만든다

탐색이 실패해도 부팅을 막지 않고 `event0`으로 떨어진다. 탐색기의 버그가
기계를 못 켜게 만드는 것이 가장 나쁜 결말이기 때문이다.

그런데 그 폴백이 게이트를 무력화한다. 실패한 경우에도 `resolveKeyboard`는
`tars-init: keyboard device /dev/input/event0 (...)`을 평소와 똑같은 모양으로
찍으므로, **그 한 줄만 grep하면 "탐색이 돌았다"와 "탐색이 실패했지만 운 좋게
답이 같다"가 구별되지 않는다.** `devices_test`를 돌리면 실패 경로에서 두 줄이
연달아 나오는 것을 눈으로 볼 수 있다.

```
tars-init: no keyboard found under /tmp/tars-devices-test/button, falling back to event0
tars-init: keyboard device /dev/input/event0 (Power Button)
```

닫는 방법은 검사를 하나 더 두는 것이다. `terminal/check.sh`가 `keyboard
device /dev/input/event`가 **있어야 한다**와 `no keyboard found`가 **없어야
한다**를 둘 다 요구한다. [[project_gate_chain_composition]]의 "게이트는 자기가
안 보는 것을 통과시킨다"가 폴백이라는 형태로 나타난 사례다.

## HD-M0은 자기가 옳다는 것을 증명하지 못한다

지금 게스트에서는 `event0`이 곧 AT 키보드다. 그래서 비트맵을 거꾸로 읽든
`ev`를 안 보든 **틀린 탐색기도 부팅 게이트를 통과한다.** 부팅으로 검사할 수
있는 것은 "탐색이 돌았다"까지이고, 그래서 무게중심이 호스트 검사에 있다.

옳다는 증명은 HD-M1이 한다. ACPI를 켜면 `Power Button`이 장치를 하나 더
등록해 번호가 밀리는데, 그런데도 TF·IP 체인이 통과하는 순간이 그 증명이다.
`keyboard device` 줄의 번호가 바뀌는 것으로 눈에도 보인다.

## 결과 경로의 수명은 `supervise()`가 `noreturn`이라는 데 기댄다

힙이 없으므로 탐색 결과는 `devices.Path`(고정 버퍼)에 담겨 `main()`의 스택에
산다. `argv`에는 그 버퍼를 가리키는 포인터가 들어간다. `supervise()`가 영영
반환하지 않으므로([[project_init_supervisor]]) 그 스택 프레임이 프로세스
수명 내내 살아 있고, 지금 `argv`에 들어가는 문자열 리터럴과 수명이 같아진다.

**나중에 누군가 `supervise`를 반환하게 만들면 이 포인터가 뜬다.** `Path`의
doc comment에 그 의존을 적어 둔 것이 유일한 방어다.

## `terminal`은 결정하지 않고 실행만 한다

PID 1이 sysfs를 훑어 경로를 정하고 `argv[4]`로 넘긴다. `terminal`은 그 값을
열 뿐 번호를 스스로 고르지 않는다. CP-M2가 설정 파서를 PID 1 한 벌로 둔 것과
같은 규칙이다([[project_config_persistence]]) — 하드웨어를 살펴 결정하는 일이
두 프로세스에 나뉘면 서로 다른 답을 얻을 수 있다.

손으로 실행할 때를 위한 기본값(`/dev/input/event0`)은 `terminal` 안에 남아
있지만, 그것은 인자가 없을 때만 쓰이는 값이라 게이트가 밟는 경로가 아니다.

**How to apply:** 새 장치 종류를 찾을 때는 (1) 이름이 아니라 capability로
판정하고, (2) 비트 번호를 `input-event-codes.h`에서 직접 확인하며(0번이
`EV_SYN`이라는 함정이 다른 상수에도 있다), (3) 부팅 없이 도는 호스트 검사를
먼저 쓰되 진짜 `/sys`를 읽지 않도록 뿌리 경로를 인자로 받고, (4) 실패해도
부팅을 막지 않는 폴백을 두었다면 게이트가 그 폴백을 구별할 수 있는지 반드시
따로 확인한다. 로그 문구를 바꾸면 `terminal/check.sh`의 같은 문자열도 함께
고친다(중복은 의도된 것이다).

관련: [[project_power_management]], [[project_gate_chain_composition]],
[[project_init_supervisor]], [[project_input_policy]],
[[project_config_persistence]], [[project_zig_c_uapi_rule]]
