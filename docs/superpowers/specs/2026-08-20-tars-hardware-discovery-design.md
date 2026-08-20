# TARS Hardware Discovery — Design

**Date:** 2026-08-20
**Status:** 설계 승인됨(2026-08-20). HD-M0 plan을 이어서 작성한다.

## 한 줄 요약

**장치를 번호가 아니라 성질로 찾고, 그 위에 ACPI를 올려 기계가 스스로
꺼지게 만든다.**

## 배경

Power Management(PM-M0~M1)가 2026-08-20에 끝나면서 진행 중인 서브프로젝트가
없어졌다. `HANDOFF.md`가 남긴 후보 셋 중 **evdev 장치 탐색**을 골랐고,
그 자리에서 **ACPI를 켜는 일까지 한 서브프로젝트로 묶기로** 정했다.

고른 이유는 셋이다.

1. **다른 무엇을 하든 언젠가 반드시 밟게 되는 지뢰다.**
   `docs/decisions/project_power_management.md`가 이미 "ACPI를 켜려면
   `terminal`의 `/dev/input/event0` 상수부터 고칠 것"이라고 경고해 두었다.
   ACPI 버튼 드라이버가 입력 장치를 먼저 등록하므로 키보드의 번호가 뒤로
   밀리고, 그러면 TF·IP 체인이 **조용히** 깨진다.
2. **PM이 못 끝낸 자리를 이어받는다.** PM은 `reboot(POWER_OFF)`이 HALT로
   강등되는 것을 확인하고 거기서 멈췄다. ACPI가 켜지면 그 강등이 사라지고,
   QEMU monitor의 `system_powerdown`(=전원 버튼)도 비로소 의미를 갖는다.
3. **실 하드웨어로 가는 길의 선행 조건이다.** 실제 기계에서 `event0`이
   키보드일 보장은 없다. USB 키보드는 제조사마다 다른 이름을 달고 나온다.

### 두 조각을 묶는 것이 왜 이득인가

순서를 뒤집으면 ACPI가 `event0`을 전원 버튼으로 바꿔 놓아 게이트가 사고를
당한다. 순서를 지키면 **같은 사건이 탐색기의 실전 시험**이 된다. 장치
번호가 밀렸는데도 TF·IP가 통과한다면, 그것이 탐색기가 옳다는 가장 강한
증거다. 같은 변화가 사고가 되느냐 증거가 되느냐를 순서 하나가 가른다.

## 출발 시점의 저장소 상태 (2026-08-20 실측)

- **입력 장치 경로가 상수로 박혀 있다.** `terminal/src/main.zig:24`의
  `const INPUT_DEVICE = "/dev/input/event0"`이고, `input.openDevice()`
  (`terminal/src/input.zig:417`)는 받은 경로를 `open`할 뿐 아무것도 살피지
  않는다.
- **ACPI가 통째로 꺼져 있다.** `kernel/.config:377`이
  `# CONFIG_ACPI is not set`, `:375`가 `# CONFIG_PM is not set`이다.
- **sysfs는 이미 마운트되어 있다.** `init/src/main.zig:332`가 `/sys`를
  붙인다. `:333`의 devtmpfs가 `/dev/input/eventN` 노드를 자동으로 만든다.
- **감독 루프는 `waitpid`로 블로킹한다.** `init/src/main.zig:262`의
  `linux.waitpid(-1, &status, 0)`이다. 여기에 fd를 하나 더 기다리게 하려면
  이 줄을 고쳐야 하는데, 이 줄은 PM-M0이 milestone 하나를 통째로 써서
  얻어낸 자리다.
- **자식 argv는 네 자리 고정 배열이다.** `init/src/main.zig:182`의
  `argv: [4:null]?[*:0]const u8`이고, `terminal` 쪽은 그 넷을 이미 다
  쓴다(`:365`).
- **PID 1이 결정하고 `terminal`은 실행만 한다는 관례가 이미 있다.**
  셸 경로·플래그·키보드 종류가 `argv[1..3]`으로 흘러간다
  (`terminal/src/main.zig:117-124`).
- **루트 게이트는 매 회차 커널을 새로 빌드한다.** `check.sh:15`의
  `clean()`이 `kernel/build`를 지운다. 체인 다섯 × 3회 = **커널 빌드 15회**.
- **monitor 포트는 45455~45458이 쓰이고 있다.** 45459가 비어 있다.

## 착수 전 조사로 확정한 사실 (2026-08-20)

게스트를 띄우지 않고 vendor된 커널 소스(`kernel/src/linux-6.18.42`)와 우리
설정 파일을 읽어서 확인한 것들이다. 다음 세션은 이 절을 다시 조사하지
않는다.

**1. `menuconfig ACPI`는 혼자 오지 않는다.**
`drivers/acpi/Kconfig:9-16`이 `select PNP`, `select NLS`, `select CRC32`,
`select FIRMWARE_TABLE`이고 `default y if X86`이다. 즉 지금 꺼져 있는 것은
우리가 `.config`에 명시적으로 꺼 놓았기 때문이며, 켜는 순간 다른 서브시스템
넷이 따라 들어온다. 이것이 빌드 시간 위험의 실체다.

**2. 전원 버튼 드라이버는 `ACPI_BUTTON`이고 조건이 이미 충족되어 있다.**
`drivers/acpi/Kconfig:185-188`이 `tristate "Button"`, `depends on INPUT`,
`default y`다. 우리 `.config`는 `CONFIG_INPUT=y`(`kernel/.config:958`)이므로
ACPI를 켜면 이 드라이버는 **가만두어도 따라 켜진다.**

**3. `default y`로 따라 켜질 것들이 많다.** `drivers/acpi/Kconfig`에서
`default y`인 항목은 `ACPI_AC`(:161), `ACPI_BATTERY`(:173),
`ACPI_FAN`(:238), `ACPI_SLEEP`(:109), `ACPI_SPCR_TABLE`(:88),
`ACPI_LPIT`(:104), `ACPI_TABLE_UPGRADE`(:375), `ACPI_PCC`(:557),
`ACPI_PRMT`(:592), `X86_PM_TIMER`(:609) 등이다. 최소 구성을 원하면
`.config`에 `# CONFIG_X is not set`을 **명시적으로** 적어야 하고, 그래도
의존 관계로 되살아나는 것이 있는지는 `olddefconfig` 결과로 확인한다.

**4. 커널에는 전원 버튼을 직접 처리하는 대안 드라이버가 있다.**
`ACPI_TINY_POWER_BUTTON`(`:198-220`)은 입력 계층을 거치지 않고 **커널이
init 프로세스에 직접 시그널을 보낸다.** 기본 시그널은 38(SIGRTMIN+4)이고
2(SIGINT)로 두면 Ctrl+Alt+Del을 흉내 낸다. `depends on !ACPI_BUTTON`이라
`ACPI_BUTTON`과 배타적이다. 채택하지 않았다 — 이유는 아래 "고려했으나
채택하지 않은 대안"에 적었다.

**5. 전원 버튼은 하나가 아닐 수 있다.** ACPI는 FADT의 고정 하드웨어 버튼과
DSDT가 선언한 장치를 각각 등록할 수 있고, 리눅스는 둘 다 `Power Button`이라는
이름의 입력 장치로 노출한다. 어느 쪽이 QEMU의 `system_powerdown`에 실제로
반응하는지는 **HD-M1에서 실측한다.**

**6. evdev의 ioctl은 우리 규칙에 걸린다.** `EVIOCGBIT`은 인자를 받는 C
매크로라서 `@cImport`로 넘어오지 않는다
(`docs/decisions/project_zig_c_uapi_rule.md`). sysfs 경로는 그냥 파일이라
이 벽을 정면으로 피해 간다.

## 목표 (이 서브프로젝트의 MVP)

QEMU monitor에서 `system_powerdown`을 보내면 게스트의 PID 1이 종료 순서를
밟고 `reboot(POWER_OFF)`을 부르며, **우리가 죽이지 않아도** QEMU가 스스로
끝난다. 지금 `power/check.sh`가 HALT에 멈춘 QEMU를 죽여 주고 있는데, 그
장치가 사라지는 것이 완료의 증거다.

## 비목표

- **실 하드웨어(USB) 부팅 검증.** 이 서브프로젝트는 그 선행 조건 하나를
  치울 뿐이다.
- **핫플러그.** 부팅 시점에 한 번 탐색하고 끝낸다. 장치가 도중에 꽂히거나
  빠지는 것을 다루지 않는다.
- **마우스·터치패드 등 다른 입력 장치.** 찾는 것은 키보드와 전원 버튼
  둘뿐이다.
- **절전/서스펜드.** ACPI를 켜지만 쓰는 것은 전원 버튼과 전원 차단뿐이다.
- **`kill -TERM 1` 경로 변경.** PM이 만든 것은 그대로 둔다.

## 결정

### 결정 1 — 탐색은 sysfs 파일 읽기로 한다

`/sys/class/input/eventN/`마다 `device/name`,
`device/capabilities/ev`, `device/capabilities/key`를 읽는다. ioctl을 쓰지
않는 이유는 조사 6번이다. 부수 효과가 하나 더 있는데, 파일 읽기라서 호스트
검사에서 가짜 트리로 시험할 수 있다는 것이다(결정 5).

### 결정 2 — 판정은 이름이 아니라 capability로 한다

- **키보드:** `ev`에 `EV_KEY`(**비트 1**. 0번은 `EV_SYN`이다)가 서 있고,
  `key` 비트맵에서
  `KEY_ESC`(1)부터 `KEY_D`(32)까지가 **전부** 서 있는 장치. 이것은 udev의
  `input_id`가 "완전한 키보드"를 가려낼 때 쓰는 것과 같은 기준이다. 그
  범위는 ESC·숫자 열·`Q`~`D`를 덮으므로, 전원 버튼처럼 키 몇 개만 가진
  장치는 절대 통과하지 못한다.
- **전원 버튼:** `key` 비트맵에 `KEY_POWER`(116)가 서 있는 장치.

이름 문자열(`AT Translated Set 2 keyboard`)을 매칭하지 않는 이유는 실
하드웨어다. USB 키보드는 제조사마다 다른 이름을 단다.

**비트맵의 방향이 이 코드에서 유일하게 미묘한 곳이다.** sysfs가 주는 것은
공백으로 나뉜 16진수 워드 목록이고 **가장 높은 워드가 맨 앞**에 온다.
`KEY_POWER`(116번)를 보려면 뒤에서 둘째 워드의 52번 비트를 봐야 한다.
호스트 검사의 주된 표적이 여기다.

### 결정 3 — 탐색기는 PID 1 안에 한 벌만 두고 결과를 argv로 넘긴다

`init/src/devices.zig`를 새로 만든다. `terminal`에는 탐색 코드를 두지 않고
키보드 장치 경로를 `argv[4]`로 받게 한다. `terminal/src/main.zig:24`의
상수는 사라진다.

이유는 이 저장소에 이미 있는 규칙이다 — **결정은 PID 1이 하고 `terminal`은
실행만 한다**(CP-M2). `init`과 `terminal`은 `build.zig`가 따로인 별개
프로젝트라 모듈을 공유하려면 디렉터리를 새로 만들어야 하는데, 이 규칙을
따르면 그 고민 자체가 사라진다. PID 1은 어차피 전원 버튼을 찾기 위해
탐색기가 필요하다.

파급 하나: `init/src/main.zig:182`의 `argv: [4:null]`이 다섯 자리로 늘어난다.
이 배열은 두 자식이 공유하므로 시리얼 셸 쪽 `null`도 하나 늘어난다.

### 결정 4 — 전원 버튼 후보는 전부 연다 (최대 넷)

조사 5번 때문이다. 하나만 골랐다가 틀리면 버튼이 **조용히** 죽는데, 그
침묵은 디버깅하기 가장 나쁜 종류의 증상이다. 넷은 넉넉한 상한이며, 실제로
몇 개가 열렸고 어느 것이 울렸는지는 로그로 남긴다.

키보드는 반대로 **첫 번째 것 하나만** 쓴다. 화면 하나에 셸 하나인 구조라
키보드가 여럿일 이유가 없고, 여럿이면 첫 번째가 곧 `event` 번호가 가장 작은
것이다.

### 결정 5 — 탐색 함수는 루트 경로를 인자로 받는다

`power_test`가 `reboot(2)`에 닿으면 안 되는 것과 같은 이유다. 호스트 검사는
개발 기계에서 도는데, 진짜 `/sys`를 읽으면 개발 기계의 키보드 사정에 따라
결과가 달라진다. 루트 경로를 주입받으면 `/tmp`에 가짜 트리를 만들어
키보드·전원 버튼·둘 다 아닌 장치를 구별하는지 볼 수 있다.

### 결정 6 — 탐색 실패는 부팅을 막지 않는다

키보드를 못 찾으면 `/dev/input/event0`을 그대로 넘기고 로그를 크게 남긴다.
전원 버튼을 못 찾으면 fd 없이 진행한다. CP가 정한 "깨진 설정으로 부팅이
막히지 않게"와 같은 정신이다. 탐색기의 버그가 부팅 자체를 못 하게 만드는
것이 가장 나쁜 결말이다.

### 결정 7 — 전원 버튼 fd는 PID 1이 직접 연다

대안 둘을 물리쳤다. `terminal`이 읽고 `kill(1, SIGTERM)`을 보내는 안은 가장
작지만, `terminal`이 죽어 있으면 전원 버튼도 죽는다 — BF 체인처럼
`/dev/dri/card0`이 없어 감독자가 포기한 상태가 정확히 그 경우다. 하필 다
망가졌을 때 눌러야 하는 것이 전원 버튼이다. 전용 자식 프로세스를 두는 안은
감독 루프를 안 건드리는 대신 바이너리가 하나 늘고 존재 이유를 계속 설명해야
한다.

전원은 PID 1의 고유 책임이고, 자식이 전부 포기 상태여도 버튼은 살아 있어야
한다.

### 결정 8 — 감독 루프를 poll 구조로 바꾸고 타임아웃 1초로 경합을 덮는다

`init/src/main.zig:262`의 `waitpid(-1, &status, 0)`이 다음으로 바뀐다.

1. `poll(전원 버튼 fd들, 1000ms)`
2. 깨어나면 버튼 이벤트를 읽어 `KEY_POWER`이면서 `value == 1`(누름)일
   때만 종료를 요청한다. 뗌(0)과 반복(2)은 버린다.
3. `waitpid(-1, &status, WNOHANG)`을 더 거둘 것이 없을 때까지 돌린다.

**타임아웃이 필요한 이유는 경합이다.** `waitpid(WNOHANG)`이 "없다"를 답한
뒤 `poll`이 잠들기 전까지의 틈에 `SIGCHLD`가 도착하면, 그 죽음을 알려 줄
것이 아무것도 없어 `poll`이 버튼을 누를 때까지 안 깨어난다. 1초 타임아웃이
그 틈을 덮는다.

`SIGCHLD` 핸들러를 새로 다는 길도 있지만 택하지 않는다. 그러면 `power.zig`의
`signal handlers installed (TERM, INT)` 로그와 그 문구를 grep하는 게이트까지
함께 흔들린다(`HANDOFF.md`의 "로그 문구는 두 곳에 중복된다"). 1초 지각은
사람이 못 느끼고, 이미 코드 곳곳에 1초 backoff가 있어 결도 맞는다.

버튼 fd가 하나도 없어도 이 구조는 그대로 성립한다 — fd 0개에 1초 타임아웃인
`poll`은 그냥 `sleep`이다. 결정 6의 폴백이 자연스럽게 받쳐진다.

### 결정 9 — 종료 요청은 기존 플래그 자리로 모은다

버튼을 보면 곧바로 `power.shutdown()`을 부르지 않는다. `power.zig`에 플래그를
세우는 함수를 하나 더 열어서, 루프 머리의
`if (power.take()) |action| power.shutdown(action);`(`main.zig:246`)이 그대로
처리하게 한다. 시그널로 오든 버튼으로 오든 종료가 시작되는 자리는 한 곳이어야
나중에 읽힌다.

### 결정 10 — ACPI는 최소로 켠다

`CONFIG_ACPI=y`와 `CONFIG_ACPI_BUTTON=y`가 목표이고, 조사 3번의 `default y`
목록은 `.config`에 명시적으로 꺼서 적는다. `CONFIG_PM`이 함께 켜질지는
`olddefconfig`의 결과로 확인한다 — `menuconfig ACPI`의 `select` 목록에는
없지만 하위 옵션이 끌어올 수 있다.

`CONFIG_ACPI_REDUCED_HARDWARE_ONLY`는 켜지 않는다. QEMU의 전원 버튼은 FADT의
고정 하드웨어 경로를 쓰기 때문이다.

### 결정 11 — 새 게이트 체인은 HD-M2에서만 만든다

- **HD-M0:** 새 체인 없음. 다섯 체인이 **하나도 안 바뀐 채로** 통과하는 것
  자체가 검사다. `terminal/check.sh`에 탐색 로그 한 줄을 요구하는 검사만
  더한다.
- **HD-M1:** `power/check.sh`에서 HALT에 멈춘 QEMU를 죽이는 부분을 빼고
  "스스로 끝났는가"를 요구한다. 체인 이름은 `PM-M1` 그대로 둔다 — 그 체인이
  보는 것은 여전히 PM의 동작이고, ACPI는 그 동작이 놓인 환경이 달라진
  것뿐이다.
- **HD-M2:** 새 체인 `device/check.sh`(`HD-M2`), monitor 포트 45459. 부팅
  → 탐색 로그 둘 → `system_powerdown` → 종료 순서 로그 → QEMU 자연 종료를
  본다. 총 부팅은 회차당 24회에서 **27회**가 된다.

## Milestone 계획

전체를 미리 상세 설계하지 않는다. 각 milestone의 plan은 그 시점에 새로 쓴다.

### HD-M0 — 탐색기

`init/src/devices.zig`와 `init/src/devices_test.zig`를 만든다. PID 1이 부팅
시점에 키보드를 찾아 경로를 `argv[4]`로 넘기고, `terminal`의 상수는 사라진다.
**ACPI는 아직 켜지 않는다.**

합격 기준이 특이하다 — 지금은 `event0`이 곧 키보드이므로, 탐색기가 옳다면
**아무 일도 안 일어난 것처럼 보여야** 한다. 다섯 체인이 그대로 통과하고,
로그에 `keyboard device /dev/input/event0`이 한 줄 는다. 게이트 파일 중
손대는 것은 그 한 줄을 요구하는 `terminal/check.sh`뿐이다.

### HD-M1 — ACPI

`kernel/.config`를 최소한으로 고친다. 여기서 두 가지가 동시에 관측된다.

1. 입력 장치 번호가 밀렸는데도 TF·IP 체인이 통과한다면 그것이 **M0가
   옳았다는 증명**이다.
2. `reboot(POWER_OFF)`이 HALT로 강등되지 않고 QEMU가 스스로 끝난다.

함께 실측할 것: 커널 빌드 시간 증가분, 어느 `Power Button` 장치가 등록되는지,
`Restarting system`(PM-M1의 재부팅 경로)이 그대로 유지되는지.

### HD-M2 — 전원 버튼

탐색기가 `KEY_POWER` 장치를 찾고, PID 1이 열고, 감독 루프가 `poll` 구조로
바뀐다. 새 체인 `device/check.sh`가 `system_powerdown`을 보내 완료선을
확인한다.

**가장 민감한 코드를 고치는 단계라 마지막에 둔다.** M0·M1이 전부 통과한
상태에서만 감독 루프에 손댄다.

## 고려했으나 채택하지 않은 대안

### `ACPI_TINY_POWER_BUTTON` (조사 4번)

커널이 입력 계층을 거치지 않고 init에 직접 시그널을 보낸다. 이것을 쓰면
HD-M2의 evdev 경로가 통째로 필요 없어진다. 그럼에도 채택하지 않는다.

1. **PM-M1이 `SIGINT`를 재시작에 이미 배정했다.** 이 드라이버를 시그널 2로
   설정하면 전원 버튼이 **재부팅**이 된다. 38(SIGRTMIN+4)로 두면 그 충돌은
   피하지만, 그러면 시그널 번호 하나가 커널 설정에 박히고 우리 코드에도
   같은 숫자가 박혀서 `HANDOFF.md`가 경고하는 "두 곳에 중복되는 문구"가
   하나 더 생긴다.
2. **`ACPI_BUTTON`과 배타적이다.** lid(덮개)와 sleep 버튼 경로를 영영 못
   쓴다. 노트북 실 하드웨어로 가는 방향과 어긋난다.
3. **정책이 커널로 들어간다.** "전원 버튼을 누르면 무엇을 할지"를 바꾸려면
   커널을 다시 빌드해야 한다. 설정은 `/config`에서 읽고 재부팅으로 반영한다는
   CP의 방향과 어긋난다.

### `terminal`이 전원 버튼을 읽는 안 / 전용 자식 프로세스 안

결정 7에 이유를 적었다.

### `signalfd`로 시그널까지 fd로 통합하는 안

`poll` 하나로 시그널과 버튼을 함께 기다릴 수 있어 경합이 원천적으로
사라진다. 그러나 PM-M0이 `SA_RESTART`를 끄고 `EINTR`로 깨어나는 구조를
공들여 얻어냈는데, 그것을 통째로 버리는 변경이 된다. 결정 8의 1초 타임아웃이
같은 문제를 훨씬 작은 변경으로 덮는다.

## 위험

**1. 커널 빌드 시간이 15배로 곱해진다.** 가장 큰 위험이다. `check.sh:15`의
`clean()`이 매 회차 `kernel/build`를 지우므로, ACPI가 빌드에 더하는 시간은
그대로 15배가 된다. HD-M1에서 숫자가 나온다. 게이트가 견디기 어려우면 그때
`clean()`에서 커널을 빼는 것을 **별도로** 논의한다. 미리 고치지 않는 이유는,
매 회차 깨끗이 빌드하는 것이 우연이 아니라 정책이고 숫자 없이 정책을 바꾸지
않기 때문이다.

**2. ACPI가 부팅 경로 전반을 바꾼다.** 재부팅이 i8042 리셋 대신 ACPI 리셋
레지스터로 갈 수 있고, 인터럽트 라우팅과 타이머도 달라진다. PM-M1이 얻어낸
`Restarting system` 관측이 유지되는지 HD-M1에서 반드시 확인한다.

**3. 어느 `Power Button`이 우는지 모른다.** 결정 4(후보를 전부 연다)가 이
위험에 대한 답이다.

**4. 가장 민감한 코드를 고친다.** 감독 루프는 PM-M0이 milestone 하나를
써서 얻은 자리다. HD-M2를 마지막에 두는 것이 이 위험에 대한 답이다.

**5. 비트맵의 워드 순서를 뒤집어 읽기 쉽다.** 결정 2에 적었고, 호스트
검사가 이것을 정면으로 겨냥한다.

## 참고

- 앞선 서브프로젝트: Boot Foundation(BF-M0~M4), Display Foundation,
  Terminal Foundation(TF-M0~M4), Zig Migration(ZM-M1~M3),
  Config Persistence(CP-M0~M2), Input Policy(IP-M0~M2),
  Power Management(PM-M0~M1)
- 관련 기억: `docs/decisions/project_power_management.md`,
  `project_zig_c_uapi_rule.md`, `project_init_supervisor.md`,
  `project_gate_chain_composition.md`, `project_config_persistence.md`
