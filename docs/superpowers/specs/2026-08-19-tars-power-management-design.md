# TARS Power Management — Design

**Date:** 2026-08-19
**Status:** 설계 승인됨(2026-08-19). PM-M0 plan을 이어서 작성한다.

## 배경

Input Policy(IP-M0~M2)가 2026-08-19에 끝나면서 진행 중인 서브프로젝트가
없어졌다. 후보 넷(터미널 완성도 / 전원 관리 / CJK 입력기 / 기타) 중
**전원 관리(Power Management)** 를 다음으로 골랐다.

고른 이유는 두 가지다.

1. **작다.** 새 장치도, 새 외부 의존도, 새 커널 옵션도 필요 없다. 이미 있는
   감독 루프에 시그널 처리를 달고 시스템 콜 하나를 부르는 일이다.
2. **비어 있는 정상 경로를 채운다.** Config Persistence가 정한 정책은
   "설정을 고치고 **재부팅**해야 반영된다"인데, 지금 TARS에는 **게스트
   안에서 재부팅할 방법이 없다.** 설정 저장소를 만들어 놓고도 그것을 쓰는
   길이 끊겨 있는 상태다.

### 출발 시점의 저장소 상태 (2026-08-19 실측)

- **PID 1에 시그널 처리가 전혀 없다.** `init/src/main.zig` 전체에
  `sigaction` 호출이 0개다.
- **게스트를 끄는 방법은 호스트에서 QEMU 프로세스를 죽이는 것뿐이다.**
  네 체인의 `check.sh`가 전부 그렇게 한다.
- **감독 루프는 이미 `EINTR`을 올바르게 처리한다.** `main.zig:257`의
  `if (e == .INTR) continue;`가 그 자리다. 시그널 핸들러를 달면 `:255`의
  `waitpid`가 그리로 깨어난다.
- **네 체인 전부 QEMU에 `-no-reboot`을 준다.** 게스트가 재부팅하면 QEMU가
  다시 뜨지 않고 종료한다.
- **게스트에 `kill` 바이너리는 없지만 셸 셋(fish, bash, zsh)이 전부 `kill`
  빌트인을 가지고 있다.** 따라서 `kill -TERM 1`은 게스트 셸에서 칠 수 있고,
  CP·IP가 쓰는 monitor `sendkey` 타이핑이 그대로 재사용된다.

## 착수 전 조사로 확정한 사실 (2026-08-19)

게스트를 띄우지 않고 커널 소스와 Zig 표준 라이브러리 소스, 그리고 우리
커널 설정 파일을 읽어서 확인한 것들이다. HANDOFF가 "미확인"으로 남긴 항목
둘이 여기서 뒤집혔으므로, 다음 세션은 이 절을 다시 조사하지 않는다.

**1. PID 1에게 보낸 시그널은 지금 전부 버려진다.** 커널은 PID 1에 대해
"핸들러가 설치되지 않은 시그널"을 무시한다. 기본 동작(종료)이 PID 1에
적용되면 곧바로 커널 패닉이 되기 때문이다. 즉 `kill -TERM 1`은 현재
**아무 일도 하지 않으며**, `sigaction`을 다는 작업이 곧 전원 관리 기능
그 자체다.

**2. `reboot(2)`는 Zig 표준 라이브러리에 그대로 있다.**
`std/os/linux.zig:1736`의 `pub fn reboot(magic, magic2, cmd, arg)`이고,
명령 상수는 `:1690`의 `LINUX_REBOOT.CMD` enum에 전부 들어 있다. 우리가 쓸
호출은 `linux.reboot(.MAGIC1, .MAGIC2, .RESTART, null)` 형태다. 필요한
나머지도 다 있다: `kill`(`:1750`), `sync`(`:2783`),
`sigaction`(`:2180`), `Sigaction`(`:6025`), `sigemptyset`(`:2257`).

**3. Zig의 `sigaction`은 `SA_RESTORER`를 내부에서 붙여 준다**
(`std/os/linux.zig:2200` 부근). libc 없이 `rt_sigaction`을 직접 부를 때
가장 흔히 틀리는 자리인데, 우리가 신경 쓸 것이 없다.

**4. 우리 커널은 ACPI가 통째로 꺼져 있다.** `kernel/.config:377`이
`# CONFIG_ACPI is not set`, `:375`가 `# CONFIG_PM is not set`이다. 결과가
셋이고, 이것이 이 설계에서 가장 중요한 제약이다.

- QEMU monitor의 `system_powerdown`은 **게스트에서 아무 일도 일으키지
  않는다.** ACPI 이벤트를 받을 드라이버가 없다. 이 경로는 쓸 수 없다.
- `reboot(POWER_OFF)`은 **커널이 스스로 `HALT`로 강등한다.**
  `kernel/reboot.c:760`의 `poweroff_fallback_to_halt = true;`가 그 자리이고,
  그때 `:321`이 `Power off not available: System halted instead`를 찍는다.
  전원이 꺼지는 것이 아니라 CPU가 멈추고, QEMU 프로세스는 호스트에 남는다.
- `reboot(RESTART)`은 ACPI 없이도 동작하며 `:294`가 `Restarting system`을
  찍는다. `-no-reboot`이 걸린 QEMU는 이때 스스로 종료한다.

**ACPI를 켜는 선택지는 이번에 쓰지 않는다.** 커널을 다시 빌드하는 비용보다
위험한 것이 따로 있다. ACPI는 "Power Button" 입력 장치를 하나 더 등록하는데,
`terminal/src/main.zig:24`가 `/dev/input/event0`을 상수로 박아 두고 있어서
키보드가 `event1`로 밀리면 TF와 IP 두 체인이 조용히 깨진다. 진짜 전원 차단이
필요해지면 그때 별도 milestone으로 다룬다.

**5. Ctrl+Alt+Del은 지금 커널이 우리를 건너뛰고 직접 재부팅한다.**
`kernel/reboot.c:26`의 `static int C_A_D = 1;`이 기본값이고, `:828`의
`ctrl_alt_del()`이 그 값에 따라 갈린다. 1이면 커널이 즉시 재부팅하고,
0이면 **PID 1에게 `SIGINT`를 보낸다.** 0으로 바꾸는 방법은
`reboot(CAD_OFF)` 호출 하나다.

**6. 커널이 sync를 대신 해 주지 않는다.** `kernel/reboot.c:726`의 주석이
"reboot doesn't sync: do that yourself before calling this"라고 직접 적어
두었다.

## 목표 (MVP)

부팅한 TARS에서 다음이 전부 동작한다.

1. **게스트 안에서 끈다** — 화면 터미널에 `kill -TERM 1`을 치면 시스템이
   멈춘다.
2. **게스트 안에서 재부팅한다** — `kill -INT 1` 또는 Ctrl+Alt+Del로 시스템이
   다시 시작한다.
3. **끄는 것이 난폭하지 않다** — 자식들에게 먼저 `SIGTERM`을 보내고, 유예
   시간을 준 뒤에 `SIGKILL`하고, 디스크를 내려쓴 다음에 시스템 콜을 부른다.
4. **재부팅이 CP의 정책을 완성한다** — 설정을 고치고 게스트 안에서
   재부팅하면 새 설정으로 다시 뜬다.
5. **감독 루프의 포기 경로가 게이트에 보인다** — 지금까지 한 번도 관측되지
   않은 재시작·포기 경로를 BF 게이트가 본다.

그리고 이 다섯이 **게이트로 증명된다.** 사람이 로그를 눈으로 읽어서
판정하지 않는다.

## 비목표

- **진짜 전원 차단(ACPI).** 위 4번의 이유로 이번 범위 밖이다.
- **`system_powerdown` 지원.** 같은 이유로 동작할 수 없다.
- **게스트용 새 명령(`tars-power`, `tars-config`).** 셸의 `kill` 빌트인과
  Ctrl+Alt+Del로 충분하다. `tars-config`는 이월 숙제로 그대로 둔다.
- **런레벨·서비스 의존성 같은 init 시스템 일반론.** 감독 대상이 둘뿐인
  지금 구조에 필요 없다.
- **`SIGHUP`으로 설정 다시 읽기.** CP가 "고치고 재부팅해야 반영된다"를
  일부러 고른 정책이므로, 그 정책을 흐리는 기능을 여기서 만들지 않는다.

## 결정

### 1. 시그널은 둘이고, 의미는 sysvinit 관례를 따른다

| 시그널 | 하는 일 | 오는 길 |
|---|---|---|
| `SIGTERM` | 끄기(`reboot(POWER_OFF)`) | 게스트 셸의 `kill -TERM 1` |
| `SIGINT` | 재시작(`reboot(RESTART)`) | 게스트 셸의 `kill -INT 1`, Ctrl+Alt+Del |

이 짝이 자연스러운 이유는 커널 쪽에 있다. `reboot(CAD_OFF)` 이후
Ctrl+Alt+Del이 PID 1에게 `SIGINT`로 도착하므로, 재시작을 `SIGINT`에 걸어
두면 키보드 경로와 명령 경로가 같은 코드로 합쳐진다. 시그널을 더 늘리지
않는다(`SIGUSR1`/`SIGUSR2`를 쓰는 init도 있지만 우리에게 구분할 동작이
없다).

### 2. 핸들러는 플래그만 세우고 즉시 돌아온다

시그널 핸들러 안에서는 재진입 안전하지 않은 함수를 부를 수 없다. TARS의
로그는 전부 `std.debug.print`인데 그것이 바로 부르면 안 되는 종류다. 그래서
핸들러가 하는 일은 다음 한 줄뿐이고, 로그는 깨어난 감독 루프가 찍는다.

```
핸들러:    pending = .power_off | .restart
루프 머리:  pending이 있으면 → shutdown(action)   (noreturn)
```

플래그는 원자적으로 읽고 쓴다. 값은 두 가지 동작을 구분하는 작은 정수
하나이고, 그 이상을 핸들러에서 만지지 않는다.

### 3. `SA_RESTART`를 켜지 않는다

켜면 커널이 `waitpid`를 안에서 자동 재시작하기 때문에 감독 루프가 루프
머리로 영영 돌아오지 못하고, 플래그를 세워도 아무 일도 일어나지 않는다.
지금 코드의 `main.zig:257`이 이미 `EINTR`을 `continue`로 받고 있으므로,
**감독 루프의 기존 코드는 한 줄도 고치지 않는다.** 루프 머리에 검사 하나가
추가될 뿐이다.

### 4. 부팅 초기에 `reboot(CAD_OFF)`를 부른다

부르지 않으면 Ctrl+Alt+Del이 눌리는 순간 커널이 즉시 재부팅한다. 자식을
정리할 기회도, 디스크를 내려쓸 기회도 없다. 시스템 콜 한 번으로 그 키가
우리 종료 순서를 타게 만들 수 있으므로 부르지 않을 이유가 없다.

이 호출은 mount 직후, 자식을 띄우기 전에 한다. 실패해도 부팅은 계속한다
(설정 하나 때문에 부팅이 막히면 안 된다는 CP의 원칙과 같은 자리다). 다만
실패하면 로그 한 줄을 남긴다.

### 5. 끄기는 `HALT`가 아니라 `POWER_OFF`를 부른다

ACPI가 없는 지금은 커널이 알아서 `HALT`로 강등하므로 겉보기 동작은 같다.
그래도 `POWER_OFF`를 부르는 편이 나은 이유가 둘이다.

- 나중에 ACPI가 켜지면 **코드를 고치지 않아도** 진짜로 전원이 꺼진다.
- 지금은 커널이 찍는 `Power off not available: System halted instead` 한 줄이
  "왜 QEMU가 안 죽었는가"를 로그가 스스로 설명해 준다. 우리가 주석으로
  적어 두는 것보다 낫다.

### 6. 종료 순서는 다섯 단계다

1. `kill(-1, SIGTERM)`. PID 1이 부르는 `-1`은 자기를 제외한 **모든
   프로세스**를 뜻한다. 감독 대상 둘뿐 아니라 PTY 안에서 도는 셸까지 한 번에
   닿으므로, 자식 목록을 따로 순회할 필요가 없다.
2. 최대 3초 유예. `waitpid(-1, WNOHANG)`으로 거두면서 기다리고, 남은 자식이
   없어지면 즉시 다음으로 간다. 3초로 잡은 근거는 감독 루프의 재시작
   backoff가 1초라는 것이다. 우리 자식은 셸과 터미널뿐이라 정리에 그보다
   오래 걸릴 일이 없다.
3. 남은 것이 있으면 `kill(-1, SIGKILL)`.
4. `sync()`. 위 조사 6번대로 커널이 대신 해 주지 않는다. `/config`가
   `MS_SYNCHRONOUS`라 그 파일시스템만 보면 필요 없지만, 시스템 콜 한 번이고
   다른 파일시스템에는 그 보장이 없다.
5. `reboot(...)`.

**이 순서를 도는 동안에는 자식을 다시 띄우지 않는다.** 감독 루프의 "안 떠
있으면 띄운다" 규칙이 종료 중에 그대로 살아 있으면, `SIGTERM`으로 죽인 셸을
루프가 곧바로 되살린다. `shutdown()`이 감독 루프로 돌아가지 않는
`noreturn` 함수인 것이 이 문제를 구조적으로 막는다.

`reboot()`이 돌아오는 경우(권한 실패 등)도 `noreturn` 계약을 지켜야 하므로,
로그를 남기고 그 자리에서 영원히 대기한다. PID 1의 반환은 곧 커널 패닉이다.

### 7. 게스트에서 부르는 수단은 만들지 않고 있는 것을 쓴다

`kill`은 셸 셋이 전부 빌트인으로 가지고 있고, Ctrl+Alt+Del은 QEMU monitor의
`sendkey ctrl-alt-delete` 한 줄이다. 새 바이너리를 initrd에 넣으면 빌드
대상과 initrd 크기가 함께 늘어나는데, 그만한 값을 하지 않는다.

### 8. 게이트는 새 체인 `power/check.sh`이고 회차당 부팅이 둘이다

기존 체인에 얹지 않는 이유는 두 부팅의 QEMU 옵션이 서로 다르기 때문이다.
한쪽은 `-no-reboot`을 빼야 하고 다른 쪽은 유지해야 한다.

**부팅 A(재시작 경로, `-no-reboot`을 뺀다).** 디스크를 물고 뜬 뒤 CP와 같은
방식으로 `echo shell=zsh > /config/tars.conf`를 타이핑하고, monitor로
`sendkey ctrl-alt-delete`를 보낸다. 그리고 **같은 로그 파일 안에서** 다음을
본다.

- `tars-init: starting as PID 1`이 **두 번째로** 나타난다(재부팅이 실제로
  일어났다).
- 그 뒤에 `tars-init: config shell=zsh`가 있다(바뀐 설정을 읽었다).
- 그 뒤에 `started console shell (pid N, /usr/bin/zsh)`가 있다(설정이 실제
  동작이 됐다).

부팅 하나가 "Ctrl+Alt+Del이 SIGINT로 왔다 → 정리하고 껐다 → 커널이 다시
떴다 → 바뀐 설정을 읽었다"를 한 로그로 증명한다. CP가 QEMU 두 번으로 나눠서
보던 것을, 이번에는 사람이 개입하지 않는 정상 경로로 닫는 셈이다.

**부팅 B(종료 경로, `-no-reboot`을 유지한다).** `kill -TERM 1`을 타이핑하고
`Power off not available: System halted instead`를 본다. 함께 거는 음성
검사는 `Attempted to kill init`이 **없어야 한다**는 것이다. 이것이 필요한
이유는 성공 조건이 두 경로로 성립할 수 있기 때문이다. 시그널 처리가
잘못되어 PID 1이 그냥 죽어도 커널이 패닉하면서 시스템은 멈추는데, 그 상태와
정상 종료를 로그 한 줄로는 구분할 수 없다.

부팅 B는 QEMU가 스스로 끝나지 않는다(위 조사 4번). 게이트가 마커를 본 뒤
평소처럼 죽인다.

### 9. BF 게이트의 사각지대를 함께 닫는다

`boot/check.sh`는 fish 배너를 보자마자 QEMU를 죽이므로 감독 루프의
**재시작·포기 경로를 한 번도 관측한 적이 없다.** `given_up`이 깨져서 무한
재시작이 나도 BF는 통과한다. BF 체인은 GPU가 없어서 `/terminal`이 매번 죽는
구성이라, 그 경로를 **이미 매 회차 밟고 있으면서 보지 않고 있을 뿐이다.**

배너 뒤에 다음 셋을 더 본다.

- `tars-init: giving up on terminal`이 나타난다.
- `tars-init: started terminal` 줄이 **정확히 세 개**다.
- `Attempted to kill init`이 없다.

개수를 세는 이유는 "포기했다는 줄이 찍혔다"만으로는 그 뒤에도 계속
재시작하는 구현을 걸러내지 못하기 때문이다. 세 개인 근거는 정책 자체다.
처음 뜨고, 죽고, 두 번 재시작한 뒤 세 번째 빠른 종료에서 포기한다
(`MAX_FAST_RESTARTS = 3`).

이 검사를 PM에서 하는 이유는 시점이다. 감독 루프에 시그널 처리를 넣는
작업이 바로 그 루프를 건드리므로, 지금이 그 루프의 관측되지 않던 경로에
검사를 다는 자리다.

## 무엇이 어디서 증명되는가

| 목표 | 게이트가 보는 것 | 자리 |
|---|---|---|
| 1 | `kill -TERM 1` → `Power off not available: System halted instead`. 음성 검사는 `Attempted to kill init` 부재 | PM-M0, 부팅 B |
| 2 | `sendkey ctrl-alt-delete` → 같은 로그에 `starting as PID 1`이 두 번째로 등장 | PM-M1, 부팅 A |
| 3 | 종료 순서의 로그 넉 줄(요청 접수, SIGTERM 발송, 자식 수거, sync 완료) | PM-M0, 부팅 B |
| 4 | 재부팅 뒤 `config shell=zsh` + `started console shell (pid N, /usr/bin/zsh)` | PM-M1, 부팅 A |
| 5 | `giving up on terminal` + `started terminal` 줄이 정확히 셋 | PM-M1, BF 체인 |

## Milestone 계획

**PM-M0 (끄기).** 시그널 처리, 종료 순서, `POWER_OFF`. 새 체인
`power/check.sh`를 만들고 부팅 B 하나만 넣는다. 이 milestone이 끝나면
"게스트 안에서 시스템을 끌 수 있다"가 참이 된다.

**PM-M1 (되살리기).** `RESTART`, `reboot(CAD_OFF)`, Ctrl+Alt+Del, 부팅 A,
그리고 BF 게이트의 사각지대. 이 milestone이 끝나면 CP의 정책이 정상
경로로 완성된다.

PM-M1의 plan은 PM-M0이 끝난 시점에 새로 쓴다.

## 비용

루트 게이트의 회차당 부팅 횟수가 **18회에서 24회로** 늘고(체인당 3회 반복 ×
부팅 2회), 총 시간은 22분 20초에서 25분 안팎이 될 것으로 본다. 비싼 쪽은
부팅(약 4초)이 아니라 부팅 A의 타이핑이다(글자당 0.3초).

BF 게이트는 배너 뒤에 포기 로그를 기다리는 만큼 회차당 몇 초가 늘어난다.
재시작 backoff가 1초이므로 최대 3초 남짓이다.

## 위험과 대응

**부팅 A가 무한 재부팅 고리에 빠지는 경우.** `-no-reboot`을 뺐으므로 원리적
가능성이 있다. 대응은 게이트 쪽이다. 마커 폴링에 상한을 두고, 상한을 넘기면
QEMU를 죽이고 실패로 판정한다. `starting as PID 1`의 등장 횟수가 셋 이상이면
그 자체를 실패로 본다.

**`kill(-1, ...)`이 자기 자신에게도 갈까 하는 걱정.** 리눅스는 `-1`에서
호출자를 제외한다. PID 1이 자기에게 `SIGTERM`을 보내는 일은 일어나지 않는다.

**타이핑이 프롬프트에 닿기 전에 보내지는 경우.** CP·IP가 이미 겪은 문제이며
대응도 같다. `terminal: screen>` 첫 줄을 기다린 뒤에 친다.

## 참고

- 이 서브프로젝트가 얹히는 구조: `docs/decisions/project_init_supervisor.md`
- 재부팅이 완성하는 정책: `docs/decisions/project_config_persistence.md`
- 게이트 설계 원칙(음성 검사, 사각지대):
  `docs/decisions/project_gate_chain_composition.md`
- 타이핑 게이트의 본보기: `config/check.sh`, `input/check.sh`
