---
name: project_device_discovery
description: "입력 장치를 번호가 아니라 성질로 찾는다 — sysfs capability 비트맵은 가장 높은 워드가 맨 앞이고 빈 상위 워드는 생략되므로 원하는 워드를 뒤에서부터 세어야 한다; EV_KEY는 1번이고 0번(EV_SYN)으로 착각하면 거의 모든 장치가 키보드로 보인다; 판정 기준은 이름이 아니라 KEY_ESC~KEY_D 범위(udev input_id와 같은 기준)라서 EV_KEY를 가진 전원 버튼이 걸러진다; **역방향은 성립하지 않아서 AT 키보드도 KEY_POWER를 갖고 있고(1번 워드 0xfeffffdfffefffff의 52번 비트), 그래서 전원 버튼 판정에 '키보드가 아니다'를 더해야 한다 — 안 더해도 종료는 정상 동작하므로 게이트가 watching 개수를 세지 않으면 아무도 모른다**; 전원 버튼은 첫 하나가 아니라 후보를 전부 연다(상한 넷, QEMU에서는 실제로 하나); 탐색 함수는 뿌리 경로를 인자로 받아 검사가 개발 기계의 /sys를 읽지 않게 하되 open(2)은 /dev/input 고정이다; 탐색 실패는 부팅을 막지 않고 event0으로 떨어지는데 ACPI를 켠 뒤 그것은 전원 버튼을 키보드로 여는 것을 뜻하므로 'no keyboard found'가 없어야 한다는 둘째 검사로 닫는다; 결과 경로는 main()의 스택에 살고 supervise()가 noreturn이라는 성질에 수명을 의존한다"
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
   워드이므로, 64번 비트의 값이 1이고 0번 비트의 값은 0이다.
2. **워드 개수가 고정이 아니다.** 전원 버튼의 `ev`는 `"3"` 한 워드뿐이다.
   물어본 비트가 찍힌 워드 수를 넘어가면 그 비트의 값은 0이라고 답하는 것이
   맞다.

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

기준은 `KEY_ESC`(1)부터 `KEY_D`(32)까지의 비트가 전부 1인가이고, udev의
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

**반대 방향은 성립하지 않는다.** 그것이 HD-M2에서 드러났다 — 아래 절.

## 키보드도 `KEY_POWER`를 갖고 있다 (2026-08-22 HD-M2)

**이것이 HD-M2가 알아낸 가장 값진 사실이다.** design 결정 4는 전원 버튼
후보를 "`KEY_POWER`(116)의 비트가 1인 장치"로 정의했는데, 그대로 구현하면
**키보드가 딸려 들어온다.**

HD-M0이 실측해 `devices_test.zig`에 적어 둔 AT 키보드의 `key` 비트맵을 그
기준으로 읽으면 이렇다. 코드 번호를 64로 나눈 몫이 워드, 나머지가 그 워드
안에서의 비트 위치다.

| 키 | 코드 | 워드 | 비트 위치 | AT 키보드의 값 |
|---|---|---|---|---|
| `KEY_ESC` | 1 | 0 | 1 | 1 |
| `KEY_A` | 30 | 0 | 30 | 1 |
| **`KEY_POWER`** | **116** | **1** | **52** | **1** |
| `KEY_SLEEP` | 142 | 2 | 14 | 1 |

`KEY_POWER`를 예로 들면 116 = 64 + 52이므로 1번 워드의 52번 비트이고, 그 워드
`0xfeffffdfffefffff`에서 52번 비트의 값이 1이다. `atkbd`가 ACPI 확장 키
(전원·절전·깨우기)를 스캔코드 표에 갖고 있기 때문이며, 실 하드웨어의 USB
키보드도 대개 같다.

그래서 판정에 조건을 하나 더했다. `looksLikePowerButton`은 세 가지를 본다.

```
EV_KEY의 비트가 1이다  +  KEY_POWER의 비트가 1이다  +  키보드가 아니다
```

마지막 조건을 `looksLikeKeyboard`에 위임하는 것이 이득이다. 키보드 판정 범위를
나중에 넓히거나 좁혀도 "키보드로 뽑힌 장치는 절대 버튼으로 뽑히지 않는다"가
저절로 따라온다.

### 제외하지 않으면 무슨 일이 생기는가

1. PID 1이 키보드 fd를 열고 `poll` 목록에 넣는다. **글자 하나를 칠 때마다
   감독 루프가 깨어난다.** 게이트가 게스트에 0.3초 간격으로 타이핑하므로
   가정이 아니라 매 회차 일어나는 일이다.
2. 깨어나서 이벤트를 안 읽으면 큐가 남아 바쁜 루프가 된다
   ([[project_init_supervisor]]).
3. 키보드의 전원 키를 무엇으로 옮길지는 Input Policy의 몫인데
   ([[project_input_policy]]), 이 판정이 그 결정을 몰래 가져가게 된다.

### 이 실패는 조용하다 — 그래서 개수를 게이트가 요구한다

키보드가 딸려 들어와도 **전원 버튼은 여전히 정상 동작한다.** 종료가 되므로
게이트가 통과하고, 아무도 모른 채 굴러간다.

그래서 `device/check.sh`가 `tars-init: watching 1 power button`을 **개수까지**
요구한다. `keyboard device` 쪽이 번호를 요구하지 않는 것과 정반대로 보이지만
이유가 다르다 — 번호는 하드웨어 사정에 따라 달라지는 값이고, **개수는 우리
판정 로직의 결과**다. [[project_gate_chain_composition]]의 "게이트는 자기가 안
보는 것을 통과시킨다"가 여기서는 "숫자를 안 세면 숫자가 틀려도 통과한다"로
나타난다.

## 전원 버튼은 첫 번째 하나가 아니라 전부 연다 (HD-M2)

`findKeyboard`가 첫 번째를 찾고 즉시 반환하는 것과 달리
`findPowerButtons`는 끝까지 훑어 개수를 돌려준다. 상한은 `MAX_BUTTONS`(넷).

이유는 ACPI가 FADT의 고정 하드웨어 버튼과 DSDT가 선언한 장치를 **각각 등록할
수 있고**, 그중 어느 것이 실제로 우는지 밖에서 알 방법이 없기 때문이다. 하나만
골랐다가 틀리면 버튼이 조용히 죽는데, 그 침묵이 디버깅하기 가장 나쁜 증상이다.

**QEMU에서 실제로 열리는 것은 하나다**(HD-M1·HD-M2 실측). 그래도 구조를 남겨
두는 것은 실 하드웨어를 위한 것이다.

여는 쪽(`openPowerButtons`)은 `sys_root`를 주입받지만 **`/dev/input`은 상수로
박혀 있다.** 이 비대칭이 의도한 것이다 — `open(2)`은 호스트 검사가 시험할
대상이 아니고, 검사가 보는 것은 `findPowerButtons`까지다. fd는 `O_NONBLOCK`으로
열어야 `drainButton`이 `EAGAIN`으로 루프를 끝낼 수 있다.

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
한다**를 둘 다 요구한다. `device/check.sh`도 같은 쌍을 요구하고, 전원 버튼에
대해서도 같은 쌍(`power button ...` 있음 / `no power button found` 없음)을
둔다. [[project_gate_chain_composition]]의 "게이트는 자기가 안 보는 것을
통과시킨다"가 폴백이라는 형태로 나타난 사례다.

**폴백이 실제로 무엇을 여는지도 알아 둘 것.** ACPI를 켠 지금 `event0`은 전원
버튼이므로, 키보드 탐색이 실패하면 폴백은 **전원 버튼을 키보드로 연다.** 위
로그의 `(Power Button)`이 그것이다. design 결정 6이 "탐색기의 버그가 기계를 못
켜게 만드는 것이 가장 나쁜 결말"이라며 받아들인 결말이고, 위의 둘째 검사가
그것이 조용히 일어나는 것을 막는다.

## HD-M0은 자기가 옳다는 것을 증명하지 못했다 — HD-M1이 했다

HD-M0 시점의 게스트에서는 `event0`이 곧 AT 키보드였다. 그래서 비트맵을 거꾸로
읽든 `ev`를 안 보든 **틀린 탐색기도 부팅 게이트를 통과했다.** 부팅으로 검사할
수 있는 것은 "탐색이 돌았다"까지였고, 그래서 무게중심이 호스트 검사에 있었다.

증명은 HD-M1이 했다. ACPI가 `Power Button`을 `event0`에 등록해 키보드가
`event1`로 밀렸는데도 TF·IP 체인이 통과했고, `keyboard device` 줄의 번호가
바뀌는 것으로 눈에도 보였다([[project_power_management]]).

**그 증명이 관측으로만 남지 않게 붙박은 것이 `terminal/check.sh`의
`ACPI: button: Power Button` 검사다.** 커널에서 ACPI를 다시 끄면 입력 장치가
다시 하나가 되고, 그러면 TF 체인은 아무 불평 없이 통과한다 — 그 줄이 그
경로를 막는다.

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
`EV_SYN`이라는 함정이 다른 상수에도 있다), (3) **그 키를 다른 장치가 함께
갖고 있지는 않은지 실측 비트맵으로 확인하고**(`KEY_POWER`가 그랬다), (4) 부팅
없이 도는 호스트 검사를 먼저 쓰되 진짜 `/sys`를 읽지 않도록 뿌리 경로를
인자로 받고, (5) 실패해도 부팅을 막지 않는 폴백을 두었다면 게이트가 그 폴백을
구별할 수 있는지 반드시 따로 확인하며, (6) **판정이 틀려도 기능은 동작하는
경우라면 개수나 대상을 게이트가 직접 세게 한다.** 로그 문구를 바꾸면
`terminal/check.sh`와 `device/check.sh`의 같은 문자열도 함께 고친다(중복은
의도된 것이다).

관련: [[project_power_management]], [[project_gate_chain_composition]],
[[project_init_supervisor]], [[project_input_policy]],
[[project_config_persistence]], [[project_zig_c_uapi_rule]]
