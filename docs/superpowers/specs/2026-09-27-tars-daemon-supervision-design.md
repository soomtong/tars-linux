# TARS Daemon Supervision — Design

접두사: DS

Status: 설계(2026-09-27). M0 전.

관련 문서: `2026-09-27-tars-boot-services-design.md`(SV. 이 사이클이 그 비목표 5를
목표로 옮긴다) · `2026-09-27-tars-service-control-design.md`(CT. `tars-service`와 그
실측 7) · `2026-09-26-tars-time-discipline-design.md`(TD. chronyd를 띄우는 배관) ·
`2026-09-26-tars-wired-nic-design.md`(WN. dhcpcd의 manager mode) ·
`docs/decisions/project_boot_services.md` · `docs/decisions/project_service_control.md` ·
`docs/decisions/project_time_discipline.md` · `docs/decisions/feedback_boot_never_blocks.md`.

## 한 줄 요약

dhcpcd와 chronyd가 PID 1의 감독 목록에 들어간다. 죽으면 다시 뜨고, 사람은
`tars-service status dhcpcd` · `tars-service restart chronyd`로 둘을 다룬다. 그러려고
dhcpcd는 배경으로 안 가고(`-B`), chronyd 앞에서 서버 파일을 30초 기다리던 우리 코드는
사라진다 — 서버는 chrony의 `sourcedir`로 나중에 들어온다. 덤으로 전원 버튼 fd에
`CLOEXEC`를 붙인다.

## 왜 지금인가

SV가 감독 목록을 서비스로 넓혔고 CT가 그 목록을 사람이 다루는 길을 냈다. 그런데
부팅 때부터 떠 있는 데몬 둘은 여전히 목록 밖이다. 2026-09-27에 사용자가 후보
(패키지 매니저 · IPv6 · dhcpcd/chronyd 감독 · 버튼 fd `CLOEXEC`) 중 이것을 골랐고,
chronyd의 기다림을 `sourcedir`로 없애는 접근(아래 결정 3)을 골랐다.

## 착수 전에 읽은 것 — 부팅은 한 번도 안 했다

### 확인 1 — dhcpcd는 스스로 갈라져서 PID 1이 pid를 못 쥔다

`net.zig`의 `startDhcpcd`는 fork · execve하고 잊는다. 인터페이스 이름 없이 manager
mode로 돌아서 lease 전에 배경으로 간다(WN design 실측 12). 원래 자식은 죽고 손자가
PID 1에 재부모화된다. 손자가 죽으면 `reaped orphan`으로 거둬질 뿐 다시 안 뜬다.
갈라지는 데몬을 감독하면 PID 1이 기억한 pid가 곧바로 틀린 값이 된다.

### 확인 2 — chronyd는 안 갈라지지만 execve 앞에 우리 코드가 있다

`clock.zig`의 `start`는 `-d`로 띄워 갈라지지 않는다. 그러나 `ntp=dhcp`이면 자식이
execve 전에 dhcpcd hook이 쓴 `/run/tars/ntp_servers`를 최대 30초 기다리고
(`waitForServerFile`), 설정 파일을 쓴 뒤 exec한다. 감독 목록의 `Child`는 path와
argv만 들고 있어서 이 앞부분이 들어갈 자리가 없다.

### 확인 3 — 그대로 넣으면 게이트에서 30초 루프가 된다

SLIRP는 option 42를 영영 안 준다(TS 확인 5). `ntp=dhcp` 부팅의 chronyd 자식은 30초
기다리다 `exit(0)`한다. 감독 목록에 그대로 넣으면 30초마다 다시 뜬다.

### 확인 4 — chrony 4.6.1에 `sourcedir`와 `reload sources`가 있고 `chronyc`가 게스트에 있다

TD 확인 4가 버전을 쟀다(4.6.1). `sourcedir`는 4.0부터다. `chronyc`는 TD 결정 9로
이미 실렸다(`kernel/guest_tools.sh`).

### 확인 5 — CT의 규칙은 `Kind.service`면 그대로 적용된다

`findService`와 `answer`는 `kind == .service`와 label의 `service ` 접두사로 서비스를
가린다. 그룹 시그널 · 빨리 죽음 셋에 포기 · 요청한 죽음은 안 셈이 전부 `Child`의
칸과 `control.zig`에 있고 서비스의 출처(`services.d`인가)를 묻지 않는다.

### 확인 6 — 버튼 fd가 샌다(CT design 실측 7)

`devices.zig`가 `/dev/input/event*`를 `CLOEXEC` 없이 연다. 콘솔 셸과 서비스와 그
자식이 물려받는다. 읽기 전용이라 해는 작다.

## 결정

### 결정 1 — 두 데몬은 `Kind.service`로 목록의 앞 두 칸이 된다

`children`은 `terminal · console shell · dhcpcd · chronyd · services.d의 여덟`이다.
label은 `service dhcpcd` · `service chronyd`다. 새 `Kind`를 만들지 않는다 — 만들면
CT의 규칙이 서비스를 가리는 자리마다 갈래가 는다. `detachService`(setsid · stdin을
`/dev/null`)는 두 데몬에게도 맞다.

목록에 넣는 조건은 지금 fork하던 조건과 같다. `net=off`면 둘 다 안 넣고, `ntp=off`면
chronyd를 안 넣는다. 안 넣은 이유는 지금처럼 로그 한 줄을 남긴다 — 침묵은 "안
켰다"와 "켜려다 실패했다"를 못 가른다.

### 결정 2 — dhcpcd에 `-B`를 붙인다

argv는 `dhcpcd -B -j /dev/console -o ntp_servers`다. 배경으로 안 가므로 PID 1이 쥔
pid가 곧 dhcpcd다. `-j`와 `-o`의 근거(WN 실측 12 · 13, TS-M0 실측 8)는 그대로다.
`-j`의 뜻이 약간 바뀐다 — 배경으로 안 가도 syslog로 가는 줄을 콘솔로 받으려면
필요한지를 M0이 잰다.

### 결정 3 — chronyd 앞의 기다림을 없앤다. 서버는 `sourcedir`로 나중에 온다

`init`은 부팅 때 설정 파일을 곧바로 쓴다. 기다리지 않으므로 부모에서 써도 부팅을
안 막는다.

- `ntp=<주소>` — 지금처럼 `server <주소> iburst`.
- `ntp=dhcp` — `sourcedir /run/tars/chrony.sources`. chronyd는 서버 0개로 떠서 기다린다.

hook `30-tars-ntp`는 `$new_ntp_servers`의 첫 주소로 `/run/tars/chrony.sources/dhcp.sources`에
`server <ip> iburst` 줄을 쓰고 `chronyc reload sources`를 부른다. chronyd가 아직
없으면 `chronyc`가 실패하는데 그것은 무시한다 — chronyd가 뜰 때 그 디렉터리를 읽는다.
chronyd가 재시작돼도 같은 이유로 서버를 다시 안다.

`clock.zig`의 `waitForServerFile` · `parseServerFile` · `FILE_WAIT_*` · `SERVER_FILE`과
그것을 보는 `clock_test`의 검사를 지운다. 확인 3의 루프가 이것으로 없어진다. `/config`의
`chrony.d` · drift(TD 결정 5 · 8)는 그대로다.

### 결정 4 — 두 데몬은 `supervise()`의 첫 바퀴에 뜬다

`net.bringUp` · `clock.start`는 fork하지 않고 `Child`를 채워 돌려준다(또는 넣지 않는
이유를 찍는다). 방화벽이 dhcpcd보다 앞이어야 한다는 제약(FW 결정)은 그대로 선다 —
`firewall.up`은 동기라 supervise 전에 끝난다. 서비스가 `clock.start` 뒤라는 SV 결정 4의
순서는 배열 순서가 지킨다.

### 결정 5 — `services.d`의 같은 이름은 건너뛴다

`services.d`에 `dhcpcd`나 `chronyd`가 있으면 그 파일을 안 띄우고 한 줄을 남긴다.
이름이 겹치면 `tars-service`가 무엇을 가리키는지 모호해진다.

### 결정 6 — 버튼 fd를 `CLOEXEC`로 연다

`devices.zig`의 open에 `.CLOEXEC = true` 한 칸이다. 판정은 서비스의
`/proc/<pid>/fd`에 `event` 장치가 없는 것이다.

### 결정 7 — 게이트는 새 체인 없이 `net/check.sh`와 `service/check.sh`에 더한다

- `net/check.sh` — dhcpcd의 그룹을 죽이면 다른 pid로 다시 뜬다. `tars-service restart
  chronyd` 뒤에 동기화가 다시 선다. `ntp=dhcp` 부팅(SLIRP, option 42 없음)에서 chronyd가
  재시작 없이 살아 있다(음성). 옛 로그 줄(`started dhcpcd (pid N), it picks the
  interface` · `chronyd will ask …`)을 grep하던 검사는 새 줄로 바꾼다.
- 호스트 검사 — hook이 `.sources` 파일을 쓴다(TS-M2의 hook 검사 자리).
- `service/check.sh` — `status`에 두 데몬이 나온다. 버튼 fd가 서비스에 안 샌다.
- 반사실 — `-B`를 빼면 pid가 어긋난다. `CLOEXEC`를 빼면 fd가 샌다.

어느 검사가 어느 부팅에 붙는지는 M2 plan이 체인을 읽고 정한다.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- DS-M0 — 실측, 코드 0줄. 게스트에서 손으로 잰다. manager mode에 `-B`를 붙여도
  인터페이스를 고르고 로그가 콘솔로 오는가, SIGTERM에 곧 죽는가. `chronyc reload
  sources`가 root에서 unix 소켓으로 닿는가, reload 뒤 `iburst` 점프가 지금과 비슷한
  시간에 오는가. chronyd가 뜨기 전에 쓰인 `.sources`를 읽는가.
- DS-M1 — `init`(결정 1~6)과 hook, 호스트 검사.
- DS-M2 — 체인 · 반사실 · 가이드 · 루트 게이트 · 닫기.

## 비목표

1. `nft -f`를 감독하는 것. 한 번 돌고 끝나는 일이다.
2. 서비스 사이의 의존. dhcpcd가 재시작돼도 chronyd는 그대로다(SV 비목표 2와 같다).
3. dhcpcd 재시작 때 lease를 이어받는 것. dhcpcd의 일이다.
4. option 42의 서버가 여럿일 때 전부 쓰는 것. 지금처럼 첫 주소 하나다.
5. 실기 LAN에서의 판정. 게이트는 SLIRP 안에서 닫힌다.

## 위험

### 위험 1 — `-B`가 manager mode의 동작을 바꾼다

배경으로 가는 것 외에 무엇이 바뀌는지 모른다. 늦게 꽂힌 USB 동글을 잡는 것(WN
실측 14)이 그대로인지가 가장 크다. M0이 잰다. 안 되면 결정 2를 다시 연다.

### 위험 2 — hook과 chronyd의 경합

hook이 `.sources`를 쓰고 `chronyc`를 부르는 사이에 chronyd가 뜨면, chronyd가 파일을
읽었는지 reload가 닿았는지 둘 중 하나는 돼야 한다. 파일을 먼저 쓰고 reload를 나중에
부르는 순서가 그것을 보장한다고 짐작한다. M0이 chronyd보다 먼저 쓰인 파일을 읽는지를 잰다.

### 위험 3 — 로그 줄이 바뀌어 체인 여럿이 흔들린다

옛 줄(`started dhcpcd` · `chronyd will ask` · `clock child`)을 보는 파일이 넷이다 —
`net/check.sh` · `nic/check.sh` · `firewall/check.sh` · 루트 `check.sh`(2026-09-27에
grep했다). M1이 자리마다 무엇을 판정하는지 읽고 새 줄로 바꾼다.

### 위험 4 — 감독이 "살아 있다"만 증명한다

다시 뜬 dhcpcd가 주소를 다시 받는지, 다시 뜬 chronyd가 시계를 다시 맞추는지는
따로 판정해야 한다. 결정 7의 검사가 pid만 보면 이 사이클이 증명하는 것보다 넓게
읽힌다.
