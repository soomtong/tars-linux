# TARS Daemon Supervision — Design

접두사: DS

Status: M1 끝났다(2026-09-27) — 실측 1~10. 두 데몬이 감독 목록에 있고 이웃 체인 넷이 초록이다. 새 판정은 M2.

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
3. dhcpcd 재시작 때 lease를 이어받는 것. dhcpcd의 일이다. SIGTERM을 받은 dhcpcd는 주소와
   경로를 지우고 죽으므로, 재시작하면 약 6초 동안 주소가 없다(실측 3).
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

### 위험 5 — 그룹 SIGTERM이 돌고 있던 hook을 끊는다 (실측 4)

`tars-service stop dhcpcd`가 hook 중간에 오면 `/etc/resolv.conf`나 `.sources`가 반쯤
쓰인 채 남을 수 있다. 다음 lease가 다시 쓴다. 전원 종료도 이미 같은 일을 하므로 이
사이클은 막지 않는다.

## DS-M0이 실행으로 증명한 것

2026-09-27. 부팅 둘(A: virtio-net + 컨테이너의 NTP stub, B: NIC 없는 q35 + monitor로
꽂은 usb-net), 둘 다 `net=off` 디스크라 `init`은 두 데몬을 안 띄웠다. 콘솔 셸에서
M1이 띄울 모양 그대로 손으로 띄웠다 — 새 세션 · stdin `/dev/null` · 출력
`/dev/console` · 적힌 pid가 곧 데몬. 게스트에 `setsid`가 없어서 하네스가 Zig 도구
`detach`(setsid → pid 파일 → execve)를 디스크에 실었다. 코드는 0줄이다. plan은
`plans/2026-09-27-tars-daemon-supervision-ds-m0.md`.

### 실측 1 — `-B`의 dhcpcd는 쥔 pid 그대로 lease를 받고, 프로세스는 하나다

    DSM0-PID dhcpcd 71
    DSM0-LEASE first ms=8007 addr=10.0.2.15/24
    DSM0-ALIVE pid 71 state=S
    DSM0-PS    73     1    73    73 Ss   dhcpcd: [manager] [ip4]

(`PS` 줄은 첫 번째 부팅 A의 것이다. 두 번 돌린 까닭은 실측 4에 있다.)

배경으로 안 갔다. pid · pgid · sid가 같은 하나의 프로세스다. privsep 자식이 없는
까닭은 dhcpcd가 스스로 말한다 — `no such user dhcpcd`. 게스트에 `dhcpcd` 사용자가
없어서 privsep 없이 돈다. 결정 2가 선다.

(ppid가 1인 것은 하네스 탓이다. `$(launch …)`의 부 셸이 먼저 끝나서 PID 1에
재부모화됐다. M1에서는 PID 1이 직접 fork하므로 처음부터 자식이다.)

### 실측 2 — stderr만으로 모든 줄이 콘솔에 온다. `-j`는 같은 줄을 한 벌 더 찍는다

`-j` 없이(`dh` 단계) `eth0: leased 10.0.2.15 for 86400 seconds`가 줄머리 없이 한
번 나왔다. `-j /dev/console`을 더하면(`dhj` 단계) 모든 줄이 두 번 나온다.

    eth0: leased 10.0.2.15 for 86400 seconds
    Sep 27 11:21:29 [590]: eth0: leased 10.0.2.15 for 86400 seconds

WN-M2가 `-j`를 더한 까닭(배경으로 간 뒤의 로그가 syslog로 사라진다)은 `-B`에서는
없다. 그러나 `-j`의 줄머리 `[pid]`는 `nic/check.sh` 검사 6 · 8이 "같은 dhcpcd가
동글을 잡았다"를 가르는 근거다. 두 번 나오는 것이 싫다는 이유만으로는 안 뺀다 —
결정 2의 argv에 `-j`를 그대로 둔다.

### 실측 3 — 그룹 SIGTERM에 100~150ms에 죽고, 주소를 지우고 간다. 다시 띄우면 약 6초에 lease

    DSM0-TERM ms=136
    DSM0-ADDR after TERM addr=[]
    DSM0-PID dhcpcd again 377
    DSM0-LEASE again ms=6019 addr=10.0.2.15/24
    DSM0-TERM again ms=108

죽기 전에 `eth0: removing interface` · `deleting route` · `deleting default route`를
찍는다. 다시 뜬 dhcpcd는 `rebinding lease of 10.0.2.15`로 같은 주소를 받는다. 처음
lease(8초)보다 2초쯤 빠른 것은 carrier를 기다리지 않아서다. 비목표 3에 "재시작하면
약 6초 동안 주소가 없다"를 적었다.

### 실측 4 — 그룹 SIGTERM은 돌고 있던 hook도 맞힌다

두 번째 TERM 직전에 이 줄이 나오고 고아 둘이 거둬진다.

    script_status: /usr/lib/dhcpcd/dhcpcd-run-hooks: Terminated
    tars-init: reaped orphan pid 377
    tars-init: reaped orphan pid 567
    tars-init: reaped orphan pid 568

lease 직후 dhcpcd가 부른 `dhcpcd-run-hooks`(와 그 자식)가 같은 프로세스 그룹에
있어서 함께 죽었다. 해는 작다 — 다음 dhcpcd가 lease를 받으면 hook이 처음부터 다시
돈다. 전원 종료의 `kill(-1)`도 이미 같은 일을 한다. 결정은 안 바꾸고 위험 5로 적는다.

이 실측 때문에 부팅 A를 두 번 돌린 것은 아니다. 첫 판의 `JUMP ms`가
`139859115864`처럼 쓸 수 없는 값이었다 — 하네스가 벽시계로 쟀는데 그 벽시계가
2031년으로 뛰었다. `/proc/uptime`으로 재도록 고치고 부팅 A를 다시 돌렸다. 위의
값은 둘째 판의 것이고, 실측 1~3의 값은 두 판이 100ms 안팎으로 같았다.

### 실측 5 — `sourcedir`와 `reload sources`가 결정 3대로 돈다. chronyd가 없으면 `chronyc`는 rc 1이다

디렉터리가 없는 `sourcedir`로 뜬 chronyd는 아무 말 없이 살아 있다. 서버는 0개다.

    DSM0-ALIVE chronyd no-dir state=S
    DSM0-RUNDIR srwxr-xr-x 1 root root 0 Sep 27 11:21 chronyd.sock

`cmdport 0`이어도 `chronyc`는 `/run/chrony/chronyd.sock`으로 닿는다. hook이 할 일을
손으로 했다 — 파일을 먼저 쓰고 reload를 나중에.

    DSM0-RELOAD rc=0 ms=16 out=[200 OK]
    DSM0-JUMP after reload ms=4310
    DSM0-SRCS1 ^* 10.0.2.2                      1   6     7     0    +28us[-38850h] +/-  649us

chronyd를 그룹 SIGTERM으로 죽이면(23ms) `chronyc`는 이렇게 답한다.

    DSM0-RELOAD no chronyd rc=1 out=[506 Cannot talk to daemon]

hook은 dhcpcd-run-hooks가 source하므로 이 rc가 hook 스크립트의 끝 rc가 될 수 있다.
M1의 hook은 `chronyc reload sources >/dev/null 2>&1 || true`로 쓴다. `init`은
디렉터리를 만들 필요가 없다 — 없어도 chronyd가 살고, hook이 `mkdir -p`한다.

### 실측 6 — chronyd는 먼저 쓰인 `.sources`를 뜰 때 읽는다

시계를 2001년으로 되돌리고 파일이 있는 채로 chronyd를 다시 띄웠다.

    DSM0-YEAR rewound 2001
    DSM0-JUMP pre-written ms=4410
    DSM0-SRCS2 ^* 10.0.2.2                      1   6     7     1    -18us[-10768d] +/-  376us

위험 2가 닫힌다. chronyd가 재시작돼도 서버를 다시 안다. 점프까지의 시간(reload 뒤
4.3초 · 뜬 뒤 4.4초)은 TD 실측 13의 "뜬 지 5초"와 같은 크기다 — `iburst`의 2초 간격
응답을 모으는 시간이고, 서버가 어느 길로 왔는지와 무관하다.

### 실측 7 — 부팅 B: NIC 없이 뜬 `-B` dhcpcd가 나중에 꽂은 동글을 같은 pid로 잡는다

    DSM0-PID dhcpcd 79
    DSM0-ALIVE no-nic state=S
    [   11.000432] cdc_ether 1-1:1.0 usb0: register 'cdc_ether' at usb-0000:00:01.0-1, CDC Ethernet Device, 52:54:00:12:34:56
    usb0: leased 10.0.2.15 for 86400 seconds
    DSM0-ALIVE after plug pid 79 state=S now=[79 ]

`no valid interfaces found`를 찍고 끝나지 않고 기다리다가 usb0을 잡았다(꽂은 뒤
lease까지 10.6초, 준비 표지부터 잰 값이다). 위험 1이 닫힌다 — `-B`는 WN 실측 14의
성질을 안 바꾼다.

### 덤 — 버튼 fd의 기준선

    DSM0-FD lr-x------ 1 root root 64 Sep 27 11:21 3 -> /dev/input/event0

콘솔 셸이 부른 `bash`의 fd 3이 전원 버튼 장치다. CT 실측 7과 같다. 결정 6의 반사실이
이 줄의 유무를 본다.

### M0이 M1에 넘기는 것

- 결정 1~6은 그대로다. dhcpcd argv는 `-B -j /dev/console -o ntp_servers`(실측 1 · 2).
- chronyd 설정의 `ntp=dhcp` 갈래는 `sourcedir /run/tars/chrony.sources` 한 줄이고,
  `init`은 그 디렉터리를 안 만든다(실측 5).
- hook은 `mkdir -p` → `dhcp.sources` 쓰기 → `chronyc reload sources >/dev/null 2>&1 || true`
  순서다(실측 5 · 6).
- 체인이 "다시 받았다"를 볼 때 기다릴 크기 — dhcpcd 재시작 뒤 lease 약 6초, chronyd
  점프 약 4.5초(실측 3 · 6).

## DS-M1이 실행으로 증명한 것

2026-09-27. plan은 `plans/2026-09-27-tars-daemon-supervision-ds-m1.md`. 커밋 셋 —
`5ecad6c`(예약 이름) · `ffa1d2e`(버튼 fd `CLOEXEC`) · `3f56ff9`(본체: `init` · hook ·
체인). 본체는 12파일, 254줄 더하고 397줄 지웠다. 지운 쪽이 많은 것은 `clock.zig`의
기다림 코드와 `parseServerFile` 검사다.

### 실측 8 — 호스트 검사가 먼저 빨갛고 구현 뒤에 초록이다

`services_test`는 `no member named 'DHCPCD'`로, `clock_test`는 `expected type '[4]u8',
found '?[4]u8'`로 먼저 빨갰다. 구현 뒤에 두 검사의 요약 줄이 새로 나온다.

    services_test: names — dot means hidden, 32 bytes is the limit, dhcpcd and chronyd are init's
    clock_test: with ntp=dhcp chronyd starts with no server and reads the directory dhcpcd writes into

첫 초록 시도는 `file contents changed during update`로 멈췄다. 편집 직후의 파일을
빌드가 읽은 것이고 코드와 무관하다 — 다시 돌리니 초록이었다.

### 실측 9 — 이웃 체인 넷이 첫 판에 초록이다

    net exit=0 fails=0 secs=118
    nic exit=0 fails=0 secs=32
    firewall exit=0 fails=0 secs=45
    service exit=0 fails=0 secs=69

새 글자로 선 판정 — `the dhcpcd hook writes the first ntp server as a chrony source and
nothing else`(호스트 hook 검사) · `chronyd read 192.0.2.1 out of the planted
chrony.sources`(net 검사 21, 화면의 `chronyc -n sources`) · `the firewall came up from
… before dhcpcd started`(FW 결정 5의 순서) · `the same dhcpcd (pid 48) caught usb0`(nic,
M0 실측 7이 게이트 안에서 재현됐다).

### 실측 10 — 부팅마다 두 데몬이 한 번씩 뜨고, `ntp=dhcp`에서도 재시작이 없다

net 체인을 한 `docker run` 안에서 다시 돌려 게스트 로그 다섯을 읽었다.

    tars-init: dhcpcd joins the services, it picks the interface
    tars-init: chronyd will ask whoever dhcpcd names in /run/tars/chrony.sources
    tars-init: started service dhcpcd (pid 37, /usr/bin/dhcpcd)
    tars-init: started service chronyd (pid 38, /usr/bin/chronyd)

다섯 부팅 어디에도 `restarting` · `giving up`이 없다. `ntp=10.0.2.2` 부팅 셋은
`chronyd will ask 10.0.2.2 (/run/tars/chrony.conf)`가 글자 그대로라 검사 18이 안
바뀌었다. `ntp=off` 부팅은 chronyd 칸 없이 `started service dhcpcd` 하나다. 확인 3의
30초 루프가 없어진 것은 위의 `ntp=dhcp` 부팅이 말한다 — 게이트는 이것을 아직 판정하지
않는다(M2).

### M1이 M2에 넘기는 것

- 게이트가 아직 안 보는 성질 넷 — 죽이면 다른 pid로 다시 뜬다(dhcpcd는 주소를 약 6초에
  다시 받는다, 실측 3) · `tars-service restart chronyd` 뒤 시계가 다시 맞는다 ·
  `ntp=dhcp`에서 chronyd가 재시작 없이 산다(실측 10을 판정으로) · 버튼 fd가 서비스에 안
  샌다(결정 6).
- `status` 표에 두 줄이 늘었다. service 체인은 흔들리지 않았다 — 그 체인의 설정 디스크가
  `net`을 안 켜는지, 켜는데 표를 줄 수로 안 세는지를 M2 plan이 읽고 적는다.
- 반사실 둘(`-B` 빼기 · `CLOEXEC` 빼기)과 가이드 · 루트 게이트.
