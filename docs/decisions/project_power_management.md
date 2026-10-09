---
name: project_power_management
description: "게스트 전원 관리(PM-M0 · M1, HD-M1 · M2, 2026-08-19~22). 종료를 시작하는 경로는 셋(SIGTERM · Ctrl+Alt+Del · ACPI 전원 버튼)이고 실제 종료는 감독 루프 머리의 take() 한 곳에서만 시작된다. 함정 — PID 1의 시그널은 핸들러가 없으면 커널이 조용히 버린다 · SA_RESTART를 켜면 플래그를 세워도 루프가 안 깨어난다 · 커널의 C_A_D 기본값이 1이라 구현 없이도 재부팅이 일어나 게이트가 우리 로그를 봐야 한다 · 전원 차단은 ACPI_SLEEP이 아니라 ACPI_SYSTEM_POWER_STATES_SUPPORT에 매달려 있다"
metadata:
  node_type: memory
  type: project
---

PM-M0(끄기) · PM-M1(되살리기, 2026-08-19 · 20)과 HD-M1 · M2(ACPI · 전원 버튼,
2026-08-21 · 22)가 확정한 것이다. 코드는 `init/src/power.zig`, 게이트는
`power/check.sh`와 `device/check.sh`다. milestone별 경과와 게이트 시간은
2026-10-10에 지웠다(커밋 이력에 있다). 종료 순서의 시그널과 지연은 뒤의
[[project_shutdown_signals]] · [[project_shutdown_latency]]가 바꿨고, 아래는 그
뒤에도 유효한 것만이다.

## 전원 차단은 `SUSPEND`와 무관하다 — `ACPI_SYSTEM_POWER_STATES_SUPPORT`에 매달린다

ACPI를 켜기 전에는 `reboot(POWER_OFF)`이 HALT로 강등됐다(`Power off not
available: System halted instead`). HD-M1이 `CONFIG_SUSPEND`를 끈 채로 ACPI를
켰고 그래도 전원이 끊긴다 — 커널이 그 둘을 갈라 두었기 때문이다.

```
drivers/acpi/Makefile   acpi-$(CONFIG_ACPI_SYSTEM_POWER_STATES_SUPPORT) += sleep.o
                        acpi-$(CONFIG_ACPI_SLEEP)                       += proc.o
```

`acpi_sleep_init()`이 `SYS_OFF_MODE_POWER_OFF`에 `acpi_power_off`를 등록하는
자리는 `#ifdef CONFIG_ACPI_SLEEP` 바깥이고 조건은 런타임의 S5 지원 하나다.
부팅 로그의 `ACPI: PM: (supports S0 S5)`가 그 증거다 — S3이 없는 것이
`SUSPEND`를 끈 결과이고 S5가 남은 것이 원한 결과다. 커널 설정에서 ACPI를
줄이자는 제안이 나오면 이 심볼이 꺼지지 않는지부터 본다. 꺼지면 전원 차단이
조용히 HALT로 돌아간다. `reboot(RESTART)`은 원래부터 강등되지 않았다.

ACPI는 `Power Button`을 입력 장치 `event0`으로 등록해 키보드를 `event1`로
민다. 그 전에 `terminal`이 `/dev/input/event0`을 상수로 박고 있었으면 TF · IP
체인이 "컴파일도 부팅도 되는데 타이핑만 안 먹는" 상태로 깨졌을 것이다 —
HD-M0의 탐색기([[project_device_discovery]])를 먼저 세운 순서가 같은 사건을
사고가 아니라 증거로 만들었다. QEMU의 전원 버튼은 하나뿐이다(FADT의 고정
하드웨어 `PWRF`만 나온다).

## 종료를 시작하는 경로는 셋이고 자리는 하나다

```
kill -TERM 1          → SIGTERM → onSignal  ─┐
Ctrl+Alt+Del          → SIGINT  → onSignal  ─┼→ power.request(action)  (원자적 저장 하나)
QEMU system_powerdown → ACPI → evdev        ─┘        ↓
   → PID 1의 poll이 깨어남 → devices.drainButton      pending 플래그
                                                      ↓
                            감독 루프 머리의 power.take() → shutdown(action)
```

버튼을 보고 곧바로 `shutdown()`을 부르지 않는다(design 결정 9). 종료가
시작되는 자리가 한 곳이어야 읽히고, 우회 경로에는 루프 머리의 순서 보장
(자식을 띄우기 전에 종료를 본다)이 없어 종료 중에 자식이 되살아날 여지가
생긴다. `request()`는 원자적 저장 하나뿐이라 시그널 핸들러에서 불러도
안전하고, 그래서 "플래그를 세우는 방법"이 코드에 한 벌만 있다.
`shutdown()`이 `noreturn`인 것도 같은 사고를 타입으로 막기 위해서다.

게이트는 셋을 각각 본다 — `power/check.sh`가 SIGTERM과 SIGINT를,
`device/check.sh`가 전원 버튼을. 뒤 절반(시그널 살포 → 수거 → `sync` →
`reboot(2)`)은 셋이 공유하지만 앞 절반이 달라 어느 하나가 깨져도 나머지가
통과한다.

## PID 1의 시그널은 핸들러가 없으면 관측되지 않는다

커널은 PID 1에 대해 "핸들러 없는 시그널"을 무시한다(기본 동작이 곧 패닉이라
커널이 막아 둔 것). 그래서 `power.install()` 전의 `kill -TERM 1`은 에러조차
없다 — 셸은 성공을 받고 새 프롬프트를 그린다. 부재를 눈에 보이게 하는 것이
`power_test`다. 같은 코드를 호스트 프로세스에서 돌리면 그 보호가 없어 시그널
15로 죽는다. 게스트에서 완전히 조용한 실패가 호스트에서는 0.1초에 판정된다.

## `SA_RESTART`를 켜면 플래그를 세워도 아무 일이 안 일어난다

`sigaction`의 `.flags = 0`은 필수다. 감독 루프는 거의 항상 `poll`에 잠들어
있고([[project_init_supervisor]]) `SA_RESTART`를 켜면 커널이 그 시스템 콜을
안에서 재시작하므로 핸들러가 플래그를 세워도 루프 머리로 영영 못 돌아온다 —
로그도 에러도 없이 종료가 안 일어난다. 끄면 `EINTR`로 깨어나고 `main.zig`의
`INTR` 분기가 루프 머리로 보낸다. 요청 확인은 자식을 다시 띄우기 전이어야
한다 — 뒤집히면 "안 떠 있는 자식을 띄운다"는 감독 규칙이 방금 죽인 셸을
되살린다.

## 셸마다 `SIGTERM`에 다르게 반응한다 — 게이트는 "모두 죽었다"만 요구한다

대화형 bash · zsh는 `SIGTERM`을 무시하고 fish는 죽는다. HD-M2 전까지 이
자리에 "셋 다 무시한다"고 적혀 있었다 — 종료를 시키는 체인이 bash로 뜨는
하나뿐이라 fish로 종료해 본 적이 없었고, 디스크를 안 무는 `device/check.sh`가
처음 밟았다. 둘만 확인하고 "대화형 셸"로 묶어 쓴 일반화였다.

그래서 게이트는 어떤 시그널에 죽었는지를 요구하지도 금지하지도 않고
`every child is gone`만 요구한다. 지금의 순서(`TERMINATION_SIGNALS = TERM ·
HUP`, 유예 뒤 `SIGKILL`)와 `grace period expired`가 실패인 이유는
[[project_shutdown_signals]] · [[project_shutdown_latency]]에 있다.

`kill(-1, sig)`이 자식 목록 순회를 대신한다. 리눅스가 PID 1 자신을 대상에서
빼 주므로 자기를 죽일 위험 없이 손자까지 닿는다 — `terminal`이 죽으면 PTY
안의 셸이 PID 1로 재부모화되어 우리 자식이 되므로 `reapAll()`을 두 라운드로
도는 구조가 그것을 거둔다.

## 커널의 `C_A_D` 기본값이 1이라 게이트가 통과할 뻔했다

`kernel/reboot.c`의 `static int C_A_D = 1;` 때문에 `CAD_OFF`를 한 줄도 안 쓴
상태에서도 Ctrl+Alt+Del은 커널이 PID 1을 건너뛰고 기계를 리셋한다. 게스트는
다시 뜨고 설정을 읽고 셸을 띄우며 `Restarting system`까지 찍는다 — "재부팅했다"
마커 셋이 구현 0줄에서 전부 통과했다(PM-M1에서 실제로 관측). 가르는 유일한
증거는 우리 로그(`ctrl-alt-del now arrives as SIGINT` · `shutdown requested
(action restart)` · `calling reboot(RESTART)`)다.
[[project_gate_chain_composition]]의 "게이트는 자기가 안 보는 것을
통과시킨다"가 가장 선명한 사례다. `C_A_D`는 커널 변수라 재부팅하면 1로
돌아가고 새 PID 1이 매번 다시 빼앗는다.

## `disableCtrlAltDel()`을 `install()`과 합치지 않는다

`reboot(MAGIC1, MAGIC2, CAD_OFF, NULL)`은 재부팅하지 않고 `C_A_D`만 바꾸는
설정 호출이다. 이유는 코드에 안 보인다 — `power_test`가 `install()`을 부르고
그 검사는 Docker 컨테이너에서 도는데, 컨테이너에 `CAP_SYS_BOOT`이 있으면 그
호출이 개발 기계의 커널 `C_A_D`를 바꾼다. 규칙: `power_test`가 부르는 함수
중에 `reboot(2)`를 부르는 것이 하나도 없어야 한다. 합치자는 리팩터링은
자연스러워 보여 언제든 다시 제안된다. 부르는 순서는 `install()` 다음이다.

## 게이트의 통과 조건은 로그 문자열이 아니라 QEMU 프로세스의 소멸이다

ACPI가 전원을 끊으므로 `power/check.sh` 부팅 1은 QEMU가 스스로 사라지는 것을
본다. 그 대가로 검사 셋이 함께 필요하다 — `-no-reboot`(리셋 고리 방지)이
게스트의 리셋에도 QEMU를 끝내므로 `Restarting system`이 없어야 한다는 음성
검사로 둘을 가르고, `reboot: Power down`을 요구해 커널이 어디까지 갔는지
보며, 패닉 검사(`Attempted to kill init`)는 실패에 이름을 붙이는 용도로
남긴다.

`power` 체인의 디스크는 `shell=bash`다(`power/make_disk.sh`) — `kill` 빌트인이
확실한 셸로 띄운다. 게스트에 `kill` 바이너리는 UT가 넣었다.

## How to apply

전원 코드를 건드릴 때 (1) 새 시그널은 `power_test`에 호스트 검사를 먼저
더해 부팅 없이 판정되게 하고, (2) 로그 문구를 바꾸면 `power/check.sh` ·
`device/check.sh`의 같은 문자열도 고치며(중복은 의도된 것), (3) 게이트가 "왜
멈췄는지"까지 보는지 확인하고, (4) 호스트 검사가 `reboot(2)`에 닿는 경로가
생기지 않았는지 본다.

관련: [[project_init_supervisor]], [[project_gate_chain_composition]],
[[project_device_discovery]], [[project_kernel_config]],
[[project_shutdown_signals]], [[project_shutdown_latency]],
[[project_daemon_supervision]], [[project_service_control]]
