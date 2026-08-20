---
name: project_power_management
description: "게스트 전원 관리 — 커널에 ACPI가 없어서 reboot(POWER_OFF)이 HALT로 강등되고 QEMU가 스스로 끝나지 않는다(RESTART는 강등되지 않는다); ACPI를 켜면 Power Button이 입력 장치를 하나 더 등록해 /dev/input/event0을 상수로 박은 terminal이 깨지므로 켜기 전에 그 상수부터 고칠 것; PID 1에게 온 시그널은 핸들러가 없으면 커널이 조용히 버려서 부재가 관측되지 않는다(호스트에서 같은 코드를 돌리면 프로세스 죽음으로 드러난다); SA_RESTART를 켜면 플래그를 세워도 감독 루프가 깨어나지 못한다; 대화형 셸은 SIGTERM을 무시하므로 SIGKILL은 정상 경로이고 게이트는 유예 만료가 아니라 every child is gone을 요구한다; terminal이 죽으면 PTY 안의 셸이 PID 1로 재부모화된다; 커널의 C_A_D 기본값이 1이라 Ctrl+Alt+Del은 구현 없이도 재부팅을 일으키므로 게이트가 '우리를 거쳤는지'를 따로 봐야 하고, 그 CAD_OFF 호출은 호스트 검사가 reboot(2)에 닿지 않도록 install()과 분리한다"
metadata:
  node_type: memory
  type: project
---

2026-08-19 PM-M0에서 게스트 안에서 시스템을 끄는 경로를 만들며 확정한
것들이고, 2026-08-20 PM-M1에서 되살리는 경로를 만들며 두 절을 더했다. 코드는
`init/src/power.zig`, 게이트는 `power/check.sh`다.

## 커널에 ACPI가 없다 — 켜기 전에 `event0` 상수부터 고칠 것

**이것이 이 문서에서 가장 오래 살아남을 제약이다.**

우리 커널은 ACPI가 통째로 꺼져 있다(`kernel/.config:377`, `:375`). 결과가
셋이다.

1. `reboot(POWER_OFF)`을 부르면 커널이 스스로 HALT로 강등하고
   (`kernel/src/linux-6.18.42/kernel/reboot.c:760`)
   `Power off not available: System halted instead`를 찍는다(`:321`).
   진짜 전원 차단은 일어나지 않으므로 **QEMU가 스스로 끝나지 않는다** —
   게이트는 `-no-reboot`을 그대로 두고 그 문자열을 종료 신호로 삼은 뒤
   호스트에서 QEMU를 죽인다.
2. QEMU monitor의 `system_powerdown`은 게스트에서 아무 일도 일으키지
   못한다. ACPI 이벤트를 받을 쪽이 없기 때문이다.
3. `reboot(RESTART)`은 ACPI 없이도 정상 동작한다. PM-M1의 재시작이 이쪽
   길을 쓰는 이유다.

**그래서 "ACPI를 켜면 되지 않나"가 자연스럽게 떠오르는데, 켜기 전에 반드시
먼저 할 일이 있다.** ACPI는 "Power Button"을 **입력 장치로 등록한다.**
`/dev/input/event0`이 그것이 되면 키보드는 `event1`로 밀린다. 그런데
`terminal/src/main.zig:24`가 `/dev/input/event0`을 상수로 박아 두고 있어서,
**TF와 IP 두 체인이 키 입력을 영원히 못 받는 상태로 조용히 깨진다.** 컴파일도
부팅도 성공하고 화면도 그려지므로, 증상은 "타이핑이 안 먹는다" 하나뿐이다.

순서는 이렇다: (1) `terminal`이 evdev 장치를 이름이나 capability로 찾도록
고치고 게이트로 확인한다 → (2) 그 다음에 ACPI를 켠다. 반대로 하면 원인이
두 겹으로 겹친다. PM-M0은 ACPI 없이 할 수 있는 일이 전부였으므로 이 순서를
밟지 않았고, 필요해지면 별도 milestone으로 다룬다.

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
검사가 `reboot(2)`에 닿는 경로가 생기지 않았는지 본다. ACPI를 켜자는
제안이 나오면 `terminal`의 `/dev/input/event0` 상수를 먼저 고쳤는지부터
묻는다.

관련: [[project_init_supervisor]], [[project_gate_chain_composition]],
[[project_config_persistence]], [[project_input_policy]]
