# TARS Service Control — Design

접두사: CT

Status: M0 끝났다(2026-09-27) — 실측 1~7. 결정 4를 "그룹에 보낸다"로 고쳤다.

관련 문서: `2026-09-27-tars-boot-services-design.md`(SV. 이 사이클이 그 비목표 4를
목표로 옮긴다) · `2026-09-13-tars-shutdown-latency-design.md`(SL. 종료 유예와
시그널) · `docs/decisions/project_init_supervisor.md` ·
`docs/decisions/project_boot_services.md` ·
`docs/decisions/feedback_boot_never_blocks.md`.

## 한 줄 요약

사람이 콘솔(또는 ssh)에서 `tars-service stop sshd`를 치면 PID 1이 그 서비스를
멈추고 되살리지 않는다. `start` · `restart` · `status`가 함께 선다. 명령은 Unix
소켓 `/run/tars/init.sock`을 거쳐 PID 1에게 가고, PID 1은 기다리지 않고 곧바로
답한다.

## 왜 지금인가

SV가 서비스를 띄우고 감독하는 것까지 세웠다. 떠 있는 서비스를 사람이 다루는 길은
없다. 2026-09-27에 사용자가 후보(패키지 매니저 · IPv6 · 서비스 제어 명령 ·
dhcpcd/chronyd 감독) 중 이것을 골랐고, 동사를 넷(`status` · `stop` · `start` ·
`restart`)으로 정했다. 통로는 소켓(아래 결정 2)으로 사용자가 확인했다.

## 착수 전에 읽은 것 — 부팅은 한 번도 안 했다

### 확인 1 — 다시 띄우기는 이미 반쯤 된다

콘솔에서 `kill <sshd pid>`를 치면 `supervise()`의 `waitpid(-1, WNOHANG)`가 그
죽음을 거두고 `restarting service sshd in 1s`를 찍고 다음 바퀴에 띄운다. 다만
사람이 pid를 찾아야 하고, 10초 안에 세 번이면 "빨리 죽었다"로 세어져 포기된다
(`FAST_EXIT_SECONDS` · `MAX_FAST_RESTARTS`).

### 확인 2 — 멈추기와 포기에서 되살리기는 길이 없다

죽이면 감독자가 되살린다. `given_up = true`가 된 자식은 다음 부팅까지 그대로다.
PID 1에게 "이것은 두어라"를 말할 입력이 없다.

### 확인 3 — PID 1이 바깥에서 받는 입력은 둘이다

시그널 둘(TERM · INT, `power.zig`)과 전원 버튼 fd(`supervise()`의 `poll`)다.
시그널 핸들러는 정수 하나만 남기고, 잠드는 자리는 `poll` 하나다. 세 번째 입력은
그 `poll`에 fd 하나를 더하는 모양이 가장 적게 바꾼다.

### 확인 4 — AF_UNIX와 `/run`이 이미 있다

`kernel/build/.config`에 `CONFIG_UNIX=y`다. initrd에 `/run`이 있다
(`make_initrd.sh:210`). initramfs라 쓸 수 있고 부팅마다 새로 선다.

### 확인 5 — 따로 도는 Zig 바이너리의 선례가 있다

`tars-install`이 `init/build.zig`의 두 번째 실행 파일로 빌드되어
`/usr/bin/tars-install`에 실린다(`make_initrd.sh:100`).

## 결정

### 결정 1 — 동사는 넷이고 전부 런타임에만 유효하다

`status` · `status NAME` · `stop NAME` · `start NAME` · `restart NAME`. 다음 부팅은
`services.d`대로 다시 시작한다. 영영 끄려면 사람이 링크를 지운다(SV 결정 6).

### 결정 2 — 통로는 `SOCK_SEQPACKET` Unix 소켓이다

`/run/tars/init.sock`, 권한 0600, `NONBLOCK | CLOEXEC`. 버린 대안 둘:

- 제어 파일(runit 식). 답이 없다 — 오타 난 이름이 조용히 무시되고, status를 PID 1이
  파일로 옮겨 적는 순간부터 낡는다.
- 시그널 + 요청 파일. 두 요청이 겹치면 경합이고 답은 여전히 파일이다.

SEQPACKET을 고르는 이유는 메시지 경계다. 요청 하나가 `recv` 한 번에 오므로 PID 1이
줄 끝을 찾으며 여러 번 읽을 일이 없다.

### 결정 3 — PID 1은 한 연결에 200ms 이상 붙잡히지 않는다

listen fd는 `supervise()`의 `poll` 배열에서 버튼 fd들 뒤에 붙는다. 깨어나면
`accept4` → 그 fd를 최대 200ms `poll` → `recv` 한 번(상한 64바이트) → 처리 →
`send` 한 번(`MSG_DONTWAIT`) → `close`. 한 바퀴에 한 연결이다. 클라이언트가 보내지
않고 멈춰 있어도 PID 1의 지각은 200ms가 상한이다.

소켓을 못 만들면 로그 한 줄을 남기고 통로 없이 부팅한다(feedback_boot_never_blocks).
`poll` 배열에서 그 자리를 빼면 된다.

### 결정 4 — `Child`에 칸 둘을 더한다: `hold`와 `kill_at`

- `hold: enum { none, stop, restart }` — 사람이 요청한 것.
- `kill_at: isize` — SIGTERM을 보낸 시각 + 유예 3초. 0이면 없다.

감독 루프 규칙이 넷 바뀐다.

1. 띄우는 조건이 `pid < 0 and !given_up and hold != .stop`이 된다.
2. 거둔 자식에게 `hold`가 서 있으면 그 죽음은 빨리 죽음으로 세지 않는다 — 세면
   `restart` 셋에 포기된다. `.restart`면 `.none`으로 돌리고 다음 바퀴에 띄운다.
   `.stop`이면 그대로 둔다. 어느 쪽이든 `kill_at = 0`.
3. 매 바퀴 `kill_at`이 지난 자식에게 SIGKILL을 보낸다.
4. `start`는 `hold = .none` · `given_up = false` · `fast_restarts = 0`.

PID 1은 멈추기를 기다리지 않는다. SIGTERM을 보내고 곧바로 `stopping ...`을 답하고
루프로 돌아간다. 3초를 막혀 있으면 그동안 전원 버튼도 다른 자식의 죽음도 못 본다.

시그널은 SIGTERM 하나다. SL이 SIGHUP을 더한 이유는 대화형 셸이었고, 서비스는
데몬이다. sshd는 SIGTERM에 22ms 안에 죽었다(실측 3).

SIGTERM과 SIGKILL은 리더 하나가 아니라 프로세스 그룹에 보낸다(`kill(-pid)`, M0에서
고쳤다). 서비스는 `setsid`로 제 그룹의 리더라 그룹 번호가 곧 pid다. `exec` 없이 쓴
스크립트에 `kill(pid)`만 보내면 셸만 죽고 일꾼은 PID 1의 고아로 남는다(실측 5). ssh
세션은 제 세션을 따로 잡아서 그룹에 보내도 안 끊긴다(실측 4).

### 결정 5 — 대상: status는 전부, 바꾸는 동사는 서비스만

`status`는 terminal · 콘솔 셸까지 보인다. `stop` · `start` · `restart`는 서비스만
받는다 — 콘솔 셸을 멈추면 사람이 명령을 칠 자리가 사라진다. NAME은 서비스
이름(`sshd`)이고 `services.Entry`가 이름을 따로 든다.

답 모양:

```
terminal        running   pid 45   up 120s
console shell   running   pid 46   up 120s
service sshd    running   pid 51   up 118s
service broken  given up
service web     stopped
```

오류는 `error: ` 로 시작하는 한 줄이다(`error: no service named foo` ·
`error: console shell is not a service` · `error: bad request`).

### 결정 6 — 클라이언트 `tars-service`가 기다림을 진다

`init/build.zig`의 세 번째 실행 파일, `/usr/bin/tars-service`. 요청을 보내고 답을
찍고 exit code로 가른다(0 성공 · 1 PID 1이 거절 · 2 통로 없음 · 3 시한 초과).
`stop` · `restart`는 PID 1이 즉시 답한 뒤, 클라이언트가 `status NAME`을 0.2초
간격으로 다시 물어 원하는 상태(`stopped` / 다른 pid로 `running`)가 될 때까지 최대
5초 기다린다.

### 결정 7 — 요청 해석과 답 짓기는 시스템 콜 없는 함수다

`init/src/control.zig`의 `parseRequest` · `formatStatus`는 바이트를 받고 바이트를
낸다. `services_test.zig`처럼 호스트에서 `control_test.zig`가 검사한다. 소켓을 여는
부분만 게스트에서 본다.

### 결정 8 — 게이트는 새 체인 없이 `service/check.sh`에 부팅 하나를 더한다

콘솔에서 `tars-service`를 쳐서 본다: status에 sshd running · stop 뒤 ssh 실패와
5초 뒤에도 안 되살아남 · start 뒤 ssh 성공 · restart 뒤 pid가 바뀜과 세 번 연달아도
포기 안 됨 · 일부러 죽는 서비스가 given up 뒤 start로 다시 뜸 · SIGTERM을 무시하는
서비스가 3초 유예 뒤 SIGKILL로 멈춤. 음성 셋 — 없는 이름 ·
콘솔 셸 stop · 망가진 요청. 반사실 둘 — "hold 죽음을 세지 않기"를 뺀다 · "띄우는
조건의 hold"를 뺀다.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- CT-M0 — 실측, 코드 0줄. 게스트에서 SEQPACKET 소켓이 되는가. Zig std의 `socket` ·
  `bind` · `accept4` 모양. sshd가 SIGTERM에 몇 초에 죽는가. sshd를 멈춘 뒤 떠 있던 ssh
  세션이 살아남는가.
- CT-M1 — `control.zig` · `Child` 확장 · `tars-service` · 호스트 검사.
- CT-M2 — `service/check.sh` 부팅 · 반사실 · 가이드.

## 비목표

1. 멈춤의 영속. 다음 부팅은 `services.d`대로다.
2. 핫 리로드. 부팅 뒤 `services.d`에 더한 것은 `start`로도 안 뜬다(SV 비목표 1).
3. dhcpcd · chronyd의 제어(SV 비목표 5).
4. 서비스 로그 보기(SV 비목표 3).
5. root 아닌 호출자 가리기(`SO_PEERCRED`). 사용자는 root 하나라 0600으로 족하다.

## 위험

### 위험 1 — PID 1이 남이 보낸 바이트를 읽는다

처음이다. 상한 64바이트 · 한 번 `recv` · 200ms 시한 · 해석은 호스트 검사를 받는
순수 함수. 해석이 틀려도 결과는 `error: bad request`여야 하고 PID 1이 죽으면 커널
패닉이다 — 음성 검사가 그것을 본다.

### 위험 2 — 소켓 fd가 자식에게 샌다

`CLOEXEC`를 빼먹으면 sshd가 listen fd를 물려받는다. 해는 작지만 `ls -l
/proc/<sshd>/fd`로 M1이 확인한다.

### 위험 3 — stop 뒤 sshd의 세션까지 죽을 수 있다

서비스는 `setsid`로 제 세션의 리더다. 우리는 `kill(pid)`로 리더 하나에만 보낸다.
sshd 세션이 제 세션을 따로 잡으면 살아남는다. M0이 확인하고, 안 살아남으면
사람에게 알릴 것인지 M1에서 정한다.

### 위험 4 — 이 사이클이 증명하는 것보다 넓게 읽힌다

게이트는 서비스 셋(sshd · 일부러 죽는 것 · SIGTERM을 무시하는 것)으로만 본다.
여러 서비스에 동시에 요청이 몰리는 경우나 오래 도는 서비스의 `up` 초는 보지 않는다.

## CT-M0이 실행으로 증명한 것

plan은 `plans/2026-09-27-tars-service-control-ct-m0.md`다. 코드는 0줄이고, 만든 것은
`/tmp/ct/`의 probe 하나(`probe.zig`)와 하네스뿐이다. 부팅은 둘이다 — 전부를 한 번,
측정 6을 고쳐서 한 번.

### 실측 1 — Zig 0.16 std의 소켓 함수가 plan의 짐작대로다

`probe.zig`가 첫 컴파일에 두 벌(컨테이너 arm64 · 게스트 `x86_64-linux-musl`)로 섰다. M1이
그대로 쓸 모양:

```zig
linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0)
linux.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un))   // addr: linux.sockaddr.un
linux.accept4(lfd, null, null, linux.SOCK.CLOEXEC)
linux.recvfrom(fd, buf.ptr, buf.len, linux.MSG.TRUNC, null, null)
linux.sendto(fd, bytes.ptr, bytes.len, linux.MSG.NOSIGNAL, null, 0)
```

전부 `usize`를 돌려주는 raw syscall이라 `init`의 `failed()`가 그대로 받는다.

### 실측 2 — SEQPACKET이 결정 2 · 3이 기대한 대로 돈다. 컨테이너와 게스트가 같다

```
sock setup mkdir=0 fd=4 bind=0 chmod=0 listen=0 mode=140600
sock poll idle rc=0 errno=0 revents=0 ms=201
sock recv first n=9 head=[stop sshd]
sock recv second n=6 head=[second]
sock recv big-trunc n=100 head=[xxxxxxxxxxxxxxxx]
sock recv after-big errno=11
sock recv c1-reply n=1000 head=[yyyyyyyyyyyyyyyy]
sock recv peer-closed n=0 head=[]
sock send to-closed errno=32
sock poll silent rc=0 errno=0 revents=0 ms=202
sock connect closed-listener fd=4 errno=111
sock connect no-file fd=5 errno=2
```

- 경계가 지켜진다. 두 번 보낸 것이 `recv` 두 번으로 온다.
- `MSG_TRUNC`를 주면 64바이트 버퍼로도 원래 길이(100)가 돌아오고, 넘친 나머지는
  버려진다(다음 `recv`가 EAGAIN). M1은 `n > 64`를 `error: bad request`로 읽는다.
- 1000바이트 답이 `recv` 한 번에 간다. status 한 벌(자식 열 줄)이 넉넉히 든다.
- 보내지 않는 상대는 200ms 시한에 끝난다(`ms=202`).
- 닫힌 상대에게 `MSG_NOSIGNAL`로 보내면 EPIPE(32)이고 프로세스는 산다.
- 받는 쪽이 없으면 두 가지다 — 소켓 파일은 있고 listen이 없으면 ECONNREFUSED(111),
  파일이 없으면 ENOENT(2). 결정 6의 exit code 2가 둘을 다 받는다.

### 실측 3 — sshd는 SIGTERM에 22ms에 죽고, PID 1이 거두기까지는 1초 안이다

```
CTM0-TERM sshd by=pid zombie_ms=22 reaped_ms=162
CTM0-TERM sshd by=pgid zombie_ms=21 reaped_ms=769
tars-init: service sshd exited (pid 38, status 0, lived 36s)
tars-init: service sshd killed (pid 756, signal 15, lived 1s)
```

좀비까지가 sshd의 몫(20ms대)이고, 거두기까지가 PID 1의 몫이다(162 · 317 · 769 · 781ms).
PID 1은 SIGCHLD에 깨지 않고 `poll`의 1초 시한에 깨어 거두므로(`POLL_TIMEOUT_MS`의 주석
3) 거둠은 1초 안의 어디든 된다. 결정 6의 5초 기다림에 여유가 넉넉하다.

sshd의 죽음이 두 모양으로 찍힌다. 오래 산 sshd는 SIGTERM을 받아 `status 0`으로 나가고,
뜬 지 1초인 것은 `signal 15`로 죽는다 — 템플릿 스크립트가 아직 `ssh-keygen -l`을 돌리는
중이거나 sshd가 핸들러를 달기 전이다. M1의 로그와 게이트는 둘 다를 "멈췄다"로 받아야
한다.

### 실측 4 — 떠 있던 ssh 세션은 리더에 보내도 그룹에 보내도 살아남는다

```
CTM0-SESS leader rc=0 out=[...;started;survived;]
CTM0-SESS group rc=0 out=[started;survived;]
CTM0-PS   406     1   406   406 Ss   sshd-session
CTM0-PS   481     1   481   481 Ss   sshd
tars-init: reaped orphan pid 406
```

`sshd-session`은 pgid · sid가 제 pid다 — sshd가 연결마다 `setsid`한다. 그래서 sshd의
그룹에 보낸 SIGTERM이 세션에 닿지 않는다. sshd가 죽으면 세션은 PID 1의 자식이 되고,
세션이 끝나면 PID 1이 `reaped orphan`으로 거둔다. 위험 3은 닫혔다 — `stop sshd`는 ssh로
붙어 있는 사람을 안 끊는다.

### 실측 5 — `exec` 없는 스크립트는 `kill(pid)`로 고아를 남긴다. 그룹에 보내면 안 남는다

```
CTM0-PS    37     1    37    37 Ss   sleeper
CTM0-PS    40    37    37    37 S    sleep
CTM0-TERM sleeper by=pid zombie_ms=20 reaped_ms=781
CTM0-PS    40     1    37    37 S    sleep          ← 셸만 죽고 sleep이 ppid 1로 남았다
CTM0-TERM sleeper by=pgid zombie_ms=21 reaped_ms=317
tars-init: reaped orphan pid 288                    ← 그룹에 보내니 sleep도 함께 죽었다
```

pid 40은 측정이 끝날 때까지 남아 있었다. `stop`이 "멈췄다"를 답하고 일은 계속되는
모양이다. 결정 4를 "그룹에 보낸다"로 고친 근거다.

SIGTERM을 무시하는 서비스:

```
CTM0-ALIVE after TERM+3s state=S
CTM0-ALIVE after KILL+0.5s state=Z
CTM0-PS   131     1    39    39 Z    sleep
tars-init: service stubborn killed (pid 39, signal 9, lived 19s)
tars-init: reaped orphan pid 131
```

3초 뒤에도 살아 있고 SIGKILL에 죽는다. 결정 4의 `kill_at`이 필요하다는 것이 섰다. 여기서도
리더에만 보낸 SIGKILL이 자식 `sleep`을 고아로 남겼다(이번에는 곧 끝나는 `sleep 1`이라
바로 거둬졌다). SIGKILL도 그룹에 보낸다.

### 실측 6 — 지금 감독자는 빨리 셋 죽이면 포기한다

```
tars-init: service sshd exited (pid 38, status 0, lived 15s)
tars-init: service sshd exited (pid 172, status 0, lived 1s)
tars-init: service sshd killed (pid 235, signal 15, lived 1s)
tars-init: service sshd killed (pid 301, signal 15, lived 1s)
tars-init: giving up on service sshd after 3 fast exits
CTM0-AFTER sshd=[]
```

첫 부팅의 하네스는 세 번만 죽였는데 첫 번째가 오래 산 sshd라 카운터를 0으로 되돌렸다 —
빨리 죽음이 둘에서 멈췄다. 라운드를 넷으로 고친 두 번째 부팅에서 재현됐다. 결정 4 규칙
2가 막으려는 것이 이 줄이고, M2의 반사실은 `restart` 넷으로 이 줄을 부른다.

### 실측 7 — 부수 발견: 전원 버튼 fd가 콘솔 셸의 자식에게 샌다

```
CTM0-P lr-x------ 1 root root 64 Sep 27 09:00 3 -> /dev/input/event0
```

게스트에서 probe가 exec한 `ls`의 fd 3이 `/dev/input/event0`이다. 컨테이너에서는 없던
줄이다. PID 1이 연 버튼 fd에 `CLOEXEC`가 없어 콘솔 셸과 그 자식들, 서비스까지 물려받는다.
CT의 범위 밖이고 해도 작다(읽기 전용). 우리 listen fd는 `CLOEXEC`로 이 길을 밟지 않는다
(같은 줄의 fd 4가 probe의 listen fd가 아니라 `ls`의 디렉터리 fd다). 이월 숙제로 적는다.

### M0이 M1에 넘기는 것

- 결정 4가 바뀌었다 — SIGTERM · SIGKILL을 `kill(-pid)`로 그룹에 보낸다.
- 요청 길이 판정은 `MSG_TRUNC`의 반환값으로 한다. 답은 `MSG_NOSIGNAL`로 보낸다.
- sshd의 멈춤은 `exited status 0`과 `killed signal 15` 두 모양이다.
- 거둠은 1초 안이다. 클라이언트의 5초 기다림은 그대로 둔다.
