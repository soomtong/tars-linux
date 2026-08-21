---
name: project_power_management
description: "게스트 전원 관리 — 2026-08-21 HD-M1에서 ACPI를 켜서 reboot(POWER_OFF)의 HALT 강등이 사라졌고 QEMU가 스스로 끝난다(RESTART는 원래부터 강등되지 않았다); 전원 차단은 CONFIG_ACPI_SLEEP이 아니라 ACPI_SYSTEM_POWER_STATES_SUPPORT에 매달려 있어서 SUSPEND를 끈 채로도 산다; ACPI가 Power Button을 event0에 등록해 키보드가 event1로 밀리는데 HD-M0의 탐색기가 그것을 견딘다; power 게이트 부팅 1의 통과 조건이 로그 문자열이 아니라 QEMU 프로세스의 소멸이고 -no-reboot 때문에 Restarting system 음성 검사가 함께 필요하다; PID 1에게 온 시그널은 핸들러가 없으면 커널이 조용히 버려서 부재가 관측되지 않는다(호스트에서 같은 코드를 돌리면 프로세스 죽음으로 드러난다); SA_RESTART를 켜면 플래그를 세워도 감독 루프가 깨어나지 못한다; 대화형 셸은 SIGTERM을 무시하므로 SIGKILL은 정상 경로이고 게이트는 유예 만료가 아니라 every child is gone을 요구한다; terminal이 죽으면 PTY 안의 셸이 PID 1로 재부모화된다; 커널의 C_A_D 기본값이 1이라 Ctrl+Alt+Del은 구현 없이도 재부팅을 일으키므로 게이트가 '우리를 거쳤는지'를 따로 봐야 하고, 그 CAD_OFF 호출은 호스트 검사가 reboot(2)에 닿지 않도록 install()과 분리한다"
metadata:
  node_type: memory
  type: project
---

2026-08-19 PM-M0에서 게스트 안에서 시스템을 끄는 경로를 만들며 확정한
것들이고, 2026-08-20 PM-M1에서 되살리는 경로를 만들며 두 절을 더했다. 코드는
`init/src/power.zig`, 게이트는 `power/check.sh`다.

## 커널에 ACPI가 켜져 있다 (2026-08-21 HD-M1)

PM-M0·PM-M1을 쓸 때 이 자리에는 "ACPI가 없어서 `reboot(POWER_OFF)`이 HALT로
강등된다"가 적혀 있었고, 그 제약이 이 문서에서 가장 오래 살아남을 것이라고
적어 두었다. **HD-M1이 그것을 지웠다.** 지금 사실은 이렇다.

1. `reboot(POWER_OFF)`은 **강등되지 않는다.** 커널이 `reboot: Power down`을
   찍고(`kernel/reboot.c:711`) `acpi_enter_sleep_state(S5)`로 전원을 끊으므로
   **QEMU가 우리 도움 없이 사라진다.** `Power off not available: System halted
   instead`(`:321`)는 이제 **나오면 안 되는 줄**이다.
2. QEMU monitor의 `system_powerdown`이 비로소 의미를 갖는다. 다만 아직
   **받는 쪽이 없다** — 전원 버튼 evdev를 여는 일은 HD-M2의 몫이다.
3. `reboot(RESTART)`은 원래부터 강등되지 않았고, ACPI를 켠 뒤에도 그대로다.
   인터럽트 라우팅이 IOAPIC으로 바뀌고 PCI IRQ가 ACPI 링크를 지나게 됐는데도
   `Restarting system`과 재부팅 뒤의 설정 반영이 전부 유지된다(PM 체인 부팅 2).

### 전원 차단이 `SUSPEND`와 무관하다는 것이 핵심이다

우리는 `CONFIG_SUSPEND`를 끈 채로 ACPI를 켰다. 그러면 `ACPI_SLEEP`이 꺼지는데,
만약 전원 차단 코드가 그 심볼에 매달려 있었다면 **ACPI를 켜고도 강등이 그대로
남았을 것이다.** 커널은 그 둘을 갈라 두었다.

```
drivers/acpi/Makefile:34   acpi-$(CONFIG_ACPI_SYSTEM_POWER_STATES_SUPPORT) += sleep.o
drivers/acpi/Makefile:36   acpi-$(CONFIG_ACPI_SLEEP)                       += proc.o
```

그리고 `sleep.c:1099`의 `acpi_sleep_init()`이 `SYS_OFF_MODE_POWER_OFF`에
`acpi_power_off`를 등록하는 자리(`:1120`)는 `#ifdef CONFIG_ACPI_SLEEP` 블록
**바깥**이다. 조건은 런타임의 `acpi_sleep_state_supported(ACPI_STATE_S5)`
하나이고, 부팅 로그의 **`ACPI: PM: (supports S0 S5)`**가 그것이 참이라는
증거다. 이 줄에 S3이 없는 것이 `SUSPEND`를 끈 결과이고, 그런데도 S5가 남아
있는 것이 우리가 원한 결과다.

### 켜기 전에 `event0` 상수를 먼저 고쳐야 했던 이유 (이행 완료)

ACPI는 `Power Button`을 **입력 장치로 등록한다.** 예전에
`terminal/src/main.zig:24`가 `/dev/input/event0`을 상수로 박고 있었으므로,
순서를 지키지 않았다면 TF·IP 두 체인이 "컴파일도 부팅도 성공하는데 타이핑만
안 먹는" 상태로 조용히 깨졌을 것이다.

HD-M0이 그 상수를 없앴고([[project_device_discovery]]), HD-M1에서 실물로
확인됐다.

```
input: Power Button as /devices/LNXSYSTM:00/LNXPWRBN:00/input/input0
ACPI: button: Power Button [PWRF]
input: AT Translated Set 2 keyboard as /devices/platform/i8042/serio0/input/input1
tars-init: keyboard device /dev/input/event1 (AT Translated Set 2 keyboard)
```

**번호가 밀렸는데도 TF·IP 체인이 통과하는 것이 탐색기가 옳다는 증명이었다.**
같은 사건이 순서 하나에 따라 사고가 되느냐 증거가 되느냐로 갈렸다.

덤으로 알게 된 사실 하나: **`Power Button`은 하나뿐이다.** 설계 단계에서는
FADT의 고정 하드웨어 버튼(`PWRF`)과 DSDT가 선언한 장치(`PWRB`)가 각각 등록될
수 있다고 보았는데, QEMU는 고정 하드웨어 쪽만 내놓는다. HD-M2가 "후보를 전부
연다"를 구현할 때 실제로 열릴 것은 하나다.

### 게이트의 통과 조건이 바뀌었다

`power/check.sh` 부팅 1은 이제 **로그의 문자열이 아니라 QEMU 프로세스의
소멸**을 본다. 우리가 죽여 주던 세 줄(`kill`/`wait`/`QEMU_PID=""`)이 사라진
것 자체가 완료의 증거다. 다만 그 대가로 검사 셋이 함께 필요하다.

- **`-no-reboot`을 그대로 두었다.** 회차당 세 번 도는 게이트가 리셋 고리에
  빠지는 것을 막아 주기 때문이다. 그런데 이 옵션은 게스트가 **리셋**을 걸어도
  QEMU를 끝내므로, "사라졌다"가 두 가지 이유로 성립하게 된다. 그래서
  `Restarting system`이 **없어야 한다**는 음성 검사로 둘을 가른다.
- `reboot: Power down`을 **요구한다.** 프로세스가 사라졌다는 사실만으로는
  커널이 어디까지 갔는지 알 수 없다.
- 패닉 검사(`Attempted to kill init`)는 역할이 바뀌었다. 예전에는 성공과
  패닉을 가르는 유일한 장치였는데, 이제는 패닉이 나도 기계가 꺼지지 않아
  프로세스 소멸 검사가 먼저 실패한다. 남겨 둔 이유는 실패에 이름을 붙여
  주기 위해서다.

켠 방법과 무엇이 따라 들어왔는지는 [[project_kernel_config]]에 있다.

## PID 1의 시그널은 핸들러가 없으면 **관측되지 않는다**

커널은 PID 1에 대해 "핸들러 없는 시그널"을 무시한다. 기본 동작(프로세스
종료)이 PID 1에 적용되면 곧바로 커널 패닉이 되기 때문에 커널이 미리 막아
놓은 것이다. 그래서 `power.install()` 이전의 `kill -TERM 1`은 **에러조차
남기지 않는다** — 셸은 성공을 받고 새 프롬프트를 그린다.

부재를 눈에 보이게 만드는 방법이 `power_test`다. **같은 코드를 호스트
프로세스에서 돌리면** 커널의 그 보호가 없으므로 기본 동작이 그대로 일어나
프로세스가 시그널 15로 죽는다. 게스트에서 완전히 조용한 실패가 호스트에서는
0.1초 만에 판정되는 실패가 된다. 부팅 20초를 쓰기 전에 잡는다는
[[project_gate_chain_composition]]의 원칙이 여기서도 그대로 적용된다.

## `SA_RESTART`를 켜면 플래그를 세워도 아무 일이 안 일어난다

`sigaction`의 `.flags = 0`은 취향이 아니라 필수다. 감독 루프는 거의 항상
`waitpid(-1, &status, 0)` 안에 잠들어 있다([[project_init_supervisor]]).
`SA_RESTART`를 켜면 커널이 그 시스템 콜을 **안에서 자동 재시작**하므로,
핸들러가 플래그를 세워도 루프 머리로 영영 돌아오지 못한다. 로그도 에러도
없이 종료가 일어나지 않는 상태다.

끄면 `waitpid`가 `EINTR`로 깨어나고, `main.zig`에 원래 있던
`if (e == .INTR) continue;`가 흐름을 루프 머리로 돌려보낸다. **감독 루프의
기존 코드를 한 줄도 고치지 않고 결선이 끝난 이유가 이것이다.**

그리고 요청 확인은 **자식을 다시 띄우기 전에** 해야 한다. 순서가 뒤집히면
"안 떠 있는 자식을 띄운다"는 감독 규칙이 방금 죽인 셸을 되살린다.
`shutdown()`을 `noreturn`으로 둔 것도 같은 사고를 타입으로 막기 위해서다.

## 대화형 셸은 `SIGTERM`을 무시한다 — `SIGKILL`은 정상 경로다

POSIX가 그렇게 정해 두었다. 로그인 셸이 지나가는 `kill`에 죽으면 곤란하기
때문이다. bash·zsh·fish 전부 해당한다.

그래서 종료 순서에서 1단계(`SIGTERM`)에 죽는 것은 `/terminal`뿐이고, 셸은
유예가 끝난 뒤 `SIGKILL`로 죽는다. **`grace period expired`는 버그 신호가
아니라 매번 나오는 줄이다.** 게이트가 그것을 실패로 보면 안 되고, 대신
마지막에 `every child is gone`이 나오는 것을 요구해야 한다. 유예 뒤에도
자식이 남아 있으면 `SIGKILL`이 안 먹었다는 뜻이고 그건 진짜 실패다.

이것도 [[project_gate_chain_composition]]의 "성공 경로가 둘이면 아무것도
증명하지 않는다"와 같은 계열이다. 시스템은 어느 쪽이든 멈추므로, 커널의
HALT 메시지 하나만 보면 "정리하고 껐다"와 "정리 못 하고 껐다"가 구분되지
않는다.

## `terminal`이 죽으면 PTY 안의 셸이 PID 1의 자식이 된다

원래 손자였던 프로세스가 부모를 잃고 **재부모화**되어 우리 자식 목록에
들어온다. 그 셸은 대화형이라 `SIGTERM`을 무시하므로, `reapAll()`을 두 번
부르는 구조(`SIGTERM` 라운드 → `SIGKILL` 라운드)가 그것을 거두는 유일한
장치다.

관련해서 `kill(-1, sig)`이 자식 목록 순회를 대신한다. `-1`은 "호출자를
제외한 모든 프로세스"이고, 리눅스가 PID 1 자신을 대상에서 빼주므로 자기를
죽일 위험 없이 손자까지 한 번에 닿는다.

## 게스트에 `kill` 바이너리는 없다

`kernel/make_initrd.sh`가 넣는 것은 셸 셋(fish·bash·zsh)과
`cat`·`uname`·`mkdir`·`sleep`뿐이다. bash와 zsh는 `kill`을 빌트인으로
가지고 있지만 **기본 셸인 fish는 확인되지 않았다.** 그래서 PM 게이트는
`mkfs.ext2 -d`로 `shell=bash`가 이미 적힌 디스크를 굽는다([[project_input_policy]]의
IP-M2가 연 길). 게스트에 한 글자도 타이핑하지 않고 셸을 고를 수 있다.

## `disableCtrlAltDel()`을 `install()`과 합치지 않는다 (2026-08-20 PM-M1)

`reboot(MAGIC1, MAGIC2, CAD_OFF, NULL)`은 재부팅하지 않고 커널의 `C_A_D`를
0으로 바꾸고 돌아오는 설정 호출이다. 그것을 부르는 자리는 `main.zig`가
`power.install()` 바로 다음에 부르는 `power.disableCtrlAltDel()` **하나뿐이고,
`install()` 안으로 합치지 않는다.**

이유는 코드를 읽어서는 보이지 않는다. `power_test`가 `install()`을 부르고, 그
검사는 Docker 컨테이너 안에서 돈다. 컨테이너에 `CAP_SYS_BOOT`이 있으면 그
호출이 **개발 기계의 커널** `C_A_D`를 바꾼다. 저장소의 검사가 호스트 설정을
건드리는 일이고, 그래서 규칙은 이렇게 적어 둔다 — **`power_test`가 부르는
함수 중에 `reboot(2)`를 부르는 것이 하나도 없어야 한다.** 두 함수를 합치자는
리팩터링은 자연스러워 보이므로 언제든 다시 제안될 수 있다.

부르는 순서는 `install()` **다음**이다. 뒤집히면 그 사이의 짧은 창에 눌린
Ctrl+Alt+Del이 핸들러 없는 `SIGINT`로 도착한다(PID 1이라 커널이 버려 주므로
사고는 안 나지만, 키를 빼앗기 전에 받을 준비를 끝내는 편이 읽기에 맞다).

## 커널의 `C_A_D` 기본값이 1이라 게이트가 통과할 뻔했다 (2026-08-20 PM-M1)

`kernel/reboot.c:26`의 `static int C_A_D = 1;` 때문에, `CAD_OFF`를 한 줄도
안 쓴 상태에서도 Ctrl+Alt+Del을 누르면 `ctrl_alt_del()`이 `schedule_work`로
재부팅을 걸어(`:832`) **PID 1을 건너뛰고** 기계를 리셋한다. 게스트는 다시
뜨고, 새 설정을 읽고, 셸을 띄운다. 커널이 `Restarting system`까지 찍는다.

그래서 "재부팅했다"를 보는 마커 셋은 구현이 하나도 없는 상태에서 전부
통과했다(PM-M1 Task 2에서 실제로 관측했다). 그 둘을 가르는 유일한 증거는
**우리 로그**다 — `ctrl-alt-del now arrives as SIGINT` ·
`shutdown requested (action restart)` · `calling reboot(RESTART)`. 커널이 찍는
`Restarting system`은 양쪽 모두에서 나오므로 혼자서는 아무것도 증명하지
못한다. [[project_gate_chain_composition]]의 "게이트는 자기가 안 보는 것을
통과시킨다"가 가장 선명하게 드러난 사례다.

`C_A_D`는 커널 변수라 재부팅하면 1로 돌아간다. 새로 뜬 PID 1이 매번 다시
빼앗으므로 재부팅을 반복해도 성질이 유지된다.

**How to apply:** 전원 관련 코드를 건드릴 때는 (1) 새 시그널을 다루면
`power_test`에 호스트 검사를 먼저 더해서 부팅 없이 판정되게 하고, (2) 로그
문구를 바꾸면 `power/check.sh`의 같은 문자열도 함께 고치며(중복은 의도된
것이다), (3) 게이트가 "왜 멈췄는지"까지 보는지 확인하고, (4) 호스트에서 도는
검사가 `reboot(2)`에 닿는 경로가 생기지 않았는지 본다. 커널 설정에서 ACPI를
줄이자는 제안이 나오면 `ACPI_SYSTEM_POWER_STATES_SUPPORT`가 꺼지지 않는지부터
확인한다 — 그것이 꺼지면 전원 차단이 조용히 HALT로 돌아간다.

관련: [[project_init_supervisor]], [[project_gate_chain_composition]],
[[project_config_persistence]], [[project_input_policy]],
[[project_device_discovery]], [[project_kernel_config]]
