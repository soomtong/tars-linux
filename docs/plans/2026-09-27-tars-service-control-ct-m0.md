# CT-M0 — 서비스 제어를 넣기 전에 다섯을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 커밋되는 코드를 한 줄도 안
> 고친다. 만드는 것은 `/tmp/ct/` 아래의 하네스와 probe 하나뿐이고, 저장소에
> 들어가는 것은 design의 실측 절과 이 plan이다. TDD 구조가 아니다 — SV-M0 ·
> FW-M0 plan과 같은 형식이다.

Goal: CT design의 M0 목록(SEQPACKET 소켓이 결정 2 · 3대로 도는가 · Zig std의 소켓
함수 모양 · sshd가 SIGTERM에 얼마 만에 죽는가 · 떠 있던 ssh 세션이 살아남는가)에
더해, 결정 4가 기대고 있는 가정 둘(셸 스크립트 서비스의 자식 · SIGTERM을 무시하는
서비스)을 부팅 하나로 답해서 M1이 코드를 쓸 때 남은 결정을 없앤다.

Architecture: 소켓 동작은 `/tmp/ct/probe.zig` 한 파일이 한 프로세스 안에서 listen과
connect 양쪽을 다 해 보며 잰다. 먼저 컨테이너(arm64 Linux)에서 돌리고, 같은 소스를
x86_64로 빌드해 설정 디스크에 실어 게스트에서 한 번 더 돌린다. 프로세스 쪽은 설정
디스크에 서비스 셋(sshd 링크 · `sleeper` · `stubborn`)을 두고, 콘솔 셸에 FIFO로
`bash /config/ctm0.sh <단계>`를 한 줄씩 친다. ssh 세션 생존은 컨테이너의 `ssh`가 긴
원격 명령을 걸어 둔 채 게스트에서 sshd를 죽여서 본다.

Tech Stack: Zig 0.16(`std.os.linux`의 raw syscall) · bash · `mkfs.ext2 -d` · `debugfs` ·
QEMU(`virtio-net-pci` + SLIRP `hostfwd`) · 게스트의 `pgrep` · `ps` · `kill` · 컨테이너의
`ssh`

---

## 무엇을 재는가

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | probe가 컴파일되나(Zig std의 `socket` · `bind` · `accept4` · `sendto` · `recvfrom` 모양), 소켓 파일의 모드, 빈 listen fd의 `poll`이 시한까지 자나 | 결정 2 · 확인 4 | Task 1 · `sock` |
| 2 | 메시지 경계(두 번 보낸 것이 `recv` 두 번), 64바이트를 넘는 요청의 모양(`MSG_TRUNC`), 1000바이트 답이 한 번에 가나, 닫힌 상대, 보내지 않는 상대에 200ms, `CLOEXEC`, 받는 쪽이 없을 때의 errno | 결정 3 · 결정 6 · 위험 1 · 2 | Task 1 · `sock` |
| 3 | sshd가 SIGTERM에 좀비가 되기까지 · PID 1이 거두기까지 몇 ms인가 | 결정 4 | `sshd` |
| 4 | sshd 리더에게만 보낸 SIGTERM, 프로세스 그룹에 보낸 SIGTERM 뒤에 떠 있던 ssh 세션이 살아남나 | 위험 3 | 하네스 `sess` · `sshd` · `sshdpg` |
| 5 | `sleep`을 자식으로 둔 셸 스크립트 서비스에 `kill(pid)` / `kill(-pgid)`를 보내면 자식이 어떻게 되나. SIGTERM을 무시하는 서비스가 3초 뒤에도 살아 있고 SIGKILL에 죽나 | 결정 4 · 위험 4 | `sleeper` · `stubborn` |
| 6 | 지금 감독자의 기준선 — sshd를 빨리 세 번 죽이면 포기되나(결정 4의 규칙 2가 막으려는 것) | 결정 4 | `giveup` |

부팅은 하나다(`net=dhcp`, `firewall`은 기본값인 꺼짐). 포트 하나. 컨테이너
`127.0.0.1:45522` → 게스트 `10.0.2.15:22`.

측정 5가 design에 없던 질문이다. 서비스는 `setsid`로 제 세션과 프로세스 그룹의
리더다(`detachService`). 템플릿 sshd는 `exec`로 셸을 지우므로 리더가 곧 sshd지만,
사람이 `exec` 없이 쓴 스크립트는 셸이 리더이고 진짜 일꾼은 그 자식이다. 셸에만
SIGTERM을 보내면 자식이 PID 1의 고아로 남을 수 있다. 그러면 `stop`이 멈춘 것처럼
보고하지만 일은 계속된다. `kill(pid)`와 `kill(-pgid)` 가운데 무엇을 쓸지를 이
측정이 정한다.

## Task 0 — `/tmp/ct/`를 만든다

- [ ] Step 1: 디렉터리를 비우고 만든다

```bash
rm -rf /tmp/ct && mkdir -p /tmp/ct/seed/ct /tmp/ct/seed/services.d /tmp/ct/seed/ssh && ls -la /tmp/ct
```

- [ ] Step 2: 작업 트리를 본다

```bash
git status --short
```

기대: 이 plan 한 줄만 있다.

## Task 1 — probe를 쓰고 컨테이너에서 돌린다 (측정 1 · 2)

- [ ] Step 1: `/tmp/ct/probe.zig`를 쓴다

```bash
cat > /tmp/ct/probe.zig <<'EOF'
//! CT-M0 probe. 저장소에 안 들어간다. SEQPACKET Unix 소켓이 CT design 결정 2 · 3이
//! 기대하는 대로 도는가를 한 프로세스 안에서 잰다 — listen 쪽과 connect 쪽을 다
//! 이 프로세스가 한다. connect는 backlog에 들어가는 순간 성공하므로 accept 전에
//! 보내 둘 수 있다.
const std = @import("std");
const linux = std.os.linux;

const PATH = "/run/tars/ct.sock";
const ALEN: linux.socklen_t = @sizeOf(linux.sockaddr.un);

fn err(rc: usize) u16 {
    return @intFromEnum(linux.errno(rc));
}

fn fdOf(rc: usize) i32 {
    return @intCast(@as(isize, @bitCast(rc)));
}

fn mark(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("sock " ++ fmt ++ "\n", args);
}

fn nowMs() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

fn addr() linux.sockaddr.un {
    var a: linux.sockaddr.un = .{ .path = [_]u8{0} ** 108 };
    @memcpy(a.path[0..PATH.len], PATH);
    return a;
}

fn client(tag: []const u8) i32 {
    const fd = fdOf(linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0));
    const a = addr();
    const rc = linux.connect(fd, &a, ALEN);
    mark("connect {s} fd={d} errno={d}", .{ tag, fd, err(rc) });
    return fd;
}

fn send(fd: i32, bytes: []const u8) usize {
    // NOSIGNAL: 닫힌 상대에게 보내면 SIGPIPE 대신 EPIPE를 받는다.
    return linux.sendto(fd, bytes.ptr, bytes.len, linux.MSG.NOSIGNAL, null, 0);
}

fn sendMark(tag: []const u8, fd: i32, bytes: []const u8) void {
    const rc = send(fd, bytes);
    if (err(rc) != 0) return mark("send {s} errno={d}", .{ tag, err(rc) });
    mark("send {s} n={d}", .{ tag, rc });
}

fn recvMark(tag: []const u8, fd: i32, buf: []u8, flags: u32) void {
    const rc = linux.recvfrom(fd, buf.ptr, buf.len, flags, null, null);
    if (err(rc) != 0) return mark("recv {s} errno={d}", .{ tag, err(rc) });
    const shown = buf[0..@min(rc, buf.len, 16)];
    mark("recv {s} n={d} head=[{s}]", .{ tag, rc, shown });
}

fn pollMark(tag: []const u8, fd: i32, ms: i32) void {
    var p = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const t0 = nowMs();
    const rc = linux.poll(&p, 1, ms);
    mark("poll {s} rc={d} errno={d} revents={d} ms={d}", .{
        tag, if (err(rc) == 0) rc else 0, err(rc), p[0].revents, nowMs() - t0,
    });
}

fn listFds() void {
    const pid = linux.fork();
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{ "/usr/bin/ls", "-l", "/proc/self/fd" };
        const envp = [_:null]?[*:0]const u8{};
        _ = linux.execve("/usr/bin/ls", &argv, &envp);
        linux.exit(127);
    }
    var status: u32 = 0;
    _ = linux.waitpid(@intCast(pid), &status, 0);
}

pub fn main(init: std.process.Init.Minimal) void {
    _ = init;

    // ── 1. 세운다 ──────────────────────────────────────────────────
    const mk = linux.mkdir("/run/tars", 0o755);
    _ = linux.unlink(PATH);
    const lfd = fdOf(linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0));
    const a = addr();
    const b = linux.bind(lfd, @ptrCast(&a), ALEN);
    const ch = linux.chmod(PATH, 0o600);
    const l = linux.listen(lfd, 4);
    var st: linux.Statx = undefined;
    _ = linux.statx(linux.AT.FDCWD, PATH, 0, .{ .TYPE = true, .MODE = true }, &st);
    mark("setup mkdir={d} fd={d} bind={d} chmod={d} listen={d} mode={o}", .{
        err(mk), lfd, err(b), err(ch), err(l), st.mode,
    });

    // ── 2. 아무도 없는 listen fd의 poll은 시한까지 잔다 ─────────────────
    pollMark("idle", lfd, 200);

    // ── 3. 경계 — 두 번 보낸 것이 recv 두 번으로 온다 ──────────────────
    const c1 = client("c1");
    sendMark("c1-first", c1, "stop sshd");
    sendMark("c1-second", c1, "second");
    pollMark("listen-ready", lfd, 200);
    const s1 = fdOf(linux.accept4(lfd, null, null, linux.SOCK.CLOEXEC));
    mark("accept s1={d}", .{s1});
    pollMark("s1-ready", s1, 200);
    var buf: [64]u8 = undefined;
    recvMark("first", s1, &buf, 0);
    recvMark("second", s1, &buf, 0);

    // ── 4. 64바이트를 넘는 요청 ─────────────────────────────────────
    const big = [_]u8{'x'} ** 100;
    sendMark("c1-big", c1, &big);
    recvMark("big-trunc", s1, &buf, linux.MSG.TRUNC);
    recvMark("after-big", s1, &buf, linux.MSG.DONTWAIT);

    // ── 5. 긴 답이 한 번에 간다 ─────────────────────────────────────
    const reply = [_]u8{'y'} ** 1000;
    sendMark("s1-reply", s1, &reply);
    var cbuf: [4096]u8 = undefined;
    recvMark("c1-reply", c1, &cbuf, 0);

    // ── 6. 상대가 닫으면 ───────────────────────────────────────────
    _ = linux.close(c1);
    recvMark("peer-closed", s1, &buf, 0);
    sendMark("to-closed", s1, "late");
    _ = linux.close(s1);

    // ── 7. 붙기만 하고 보내지 않는 상대 ────────────────────────────────
    const c2 = client("c2");
    pollMark("listen-ready2", lfd, 200);
    const s2 = fdOf(linux.accept4(lfd, null, null, linux.SOCK.CLOEXEC));
    pollMark("silent", s2, 200);
    _ = linux.close(c2);
    _ = linux.close(s2);

    // ── 8. CLOEXEC — leak만 exec 너머로 보여야 한다 ─────────────────────
    const leak = fdOf(linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET, 0));
    mark("cloexec listen={d} leak={d}", .{ lfd, leak });
    listFds();
    _ = linux.close(leak);

    // ── 9. 받는 쪽이 없을 때 ────────────────────────────────────────
    _ = linux.close(lfd);
    _ = client("closed-listener");
    _ = linux.unlink(PATH);
    _ = client("no-file");
    mark("done", .{});
}
EOF
```

- [ ] Step 2: 컨테이너에서 두 벌로 빌드한다

```bash
docker run --rm -v /tmp/ct:/tmp/ct -w /tmp/ct tars-devcontainer bash -c '
  zig build-exe probe.zig -O ReleaseSafe -femit-bin=probe-host 2>&1 | head -40
  zig build-exe probe.zig -O ReleaseSafe -target x86_64-linux-musl -femit-bin=seed/ct/probe 2>&1 | head -40
  ls -la probe-host seed/ct/probe; file seed/ct/probe'
```

기대: 두 파일이 생긴다. 컴파일 에러가 나면 그 문구를 적는다 — 측정 1의 절반이 "std의
모양이 plan이 짐작한 대로인가"다. 고친 자리와 고친 모양도 적는다(M1이 그대로 쓴다).

- [ ] Step 3: 컨테이너에서 돌린다

```bash
docker run --rm -v /tmp/ct:/tmp/ct tars-devcontainer /tmp/ct/probe-host 2>&1 | tee /tmp/ct/probe-host.txt
```

적을 것 — 각 줄의 값. 기대는 이렇다.

- `setup`: errno 전부 0(`mkdir`은 17일 수 있다), `mode=140600`(소켓 · 0600).
- `poll idle`: `rc=0`이고 `ms`가 200 안팎.
- `recv first n=9 head=[stop sshd]`, `recv second n=6` — 경계가 지켜진다.
- `recv big-trunc`: `n=100`이면 `MSG_TRUNC`가 원래 길이를 알려 준다. 그러면 M1이
  "64를 넘었다"를 가려서 `error: bad request`로 답할 수 있다. `n=64`면 넘친 것을 가릴
  수 없다 — 그때는 버퍼를 65로 잡고 65를 넘침으로 읽는다.
- `recv after-big errno=11`(EAGAIN) — 넘친 나머지는 버려졌다.
- `recv c1-reply n=1000`.
- `recv peer-closed n=0`, `send to-closed errno=32`(EPIPE)이고 프로세스가 산다.
- `poll silent rc=0 ms≈200`.
- `ls` 출력에서 `socket:[…]`이 `leak`의 번호에만 있다.
- `connect closed-listener errno=111`(ECONNREFUSED), `connect no-file errno=2`(ENOENT) —
  결정 6의 exit code 2("통로 없음")가 두 경우를 다 받아야 한다.

## Task 2 — 시드 · 게스트 스크립트 · 디스크

- [ ] Step 1: 시험용 서비스 둘과 `tars.conf`를 쓴다

```bash
cat > /tmp/ct/seed/services.d/sleeper <<'EOF'
#!/bin/sh
# CT-M0 측정 5. exec 없이 자식을 둔다 — 리더는 셸이고 일꾼은 sleep이다.
echo "sleeper: up $$"
sleep 100000
EOF
cat > /tmp/ct/seed/services.d/stubborn <<'EOF'
#!/bin/sh
# CT-M0 측정 5. SIGTERM을 무시한다. 무시 설정은 exec를 넘어 sleep에도 간다.
trap '' TERM
echo "stubborn: up $$"
while :; do sleep 1; done
EOF
chmod 755 /tmp/ct/seed/services.d/sleeper /tmp/ct/seed/services.d/stubborn
printf '# CT-M0.\nnet=dhcp\n' > /tmp/ct/seed/tars.conf
```

- [ ] Step 2: `/tmp/ct/seed/ctm0.sh`를 쓴다

```bash
cat > /tmp/ct/seed/ctm0.sh <<'EOF'
#!/bin/bash
# CT-M0. 게스트의 /config/ctm0.sh로 닿는다. 표지는 전부 "CTM0-<이름> ".
# 우리가 치는 줄은 "bash /config/ctm0.sh <단계>"뿐이라 그 에코에는 표지가 없다.
mark() { printf 'CTM0-%s %s\n' "$1" "$2"; }
ms() { echo $(( $(date +%s%N) / 1000000 )); }
leader() { pgrep -P 1 -x "$1" | head -1; }
state() { sed -n 's/^State:\s*\(.\).*/\1/p' "/proc/$1/status" 2>/dev/null || echo gone; }
procs() {  # $1 = 이름 패턴. pid · ppid · pgid · sid · 상태 · 이름
  ps -eo pid=,ppid=,pgid=,sid=,stat=,comm= | grep -E "$1" | while IFS= read -r l; do mark PS "$l"; done
}

# $1 = 리더 이름, $2 = kill의 대상 모양(pid|pgid). 좀비가 되기까지와 거둬지기까지를 잰다.
term_and_time() {
  local p t0 tz=- tg=- now target
  p=$(leader "$1"); [ -z "$p" ] && { mark ERR "no $1 under pid 1"; return; }
  target=$p; [ "$2" = pgid ] && target=-$p
  mark PID "$1 $p"
  t0=$(ms); kill -TERM -- "$target"
  for _ in $(seq 1 400); do
    now=$(state "$p")
    [ "$tz" = - ] && [ "$now" = Z -o "$now" = gone ] && tz=$(( $(ms) - t0 ))
    [ "$now" = gone ] && { tg=$(( $(ms) - t0 )); break; }
    sleep 0.01
  done
  mark TERM "$1 by=$2 zombie_ms=$tz reaped_ms=$tg"
  for _ in $(seq 1 30); do
    n=$(leader "$1"); [ -n "$n" ] && [ "$n" != "$p" ] && break; sleep 0.1
  done
  mark BACK "$1 old=$p new=$(leader "$1")"
}

case "$1" in
sock)
  /config/ct/probe 2>&1 | while IFS= read -r l; do mark P "$l"; done
  mark DONE sock
  ;;
sshd)   term_and_time sshd pid;  procs 'sshd'; mark DONE sshd ;;
sshdpg) term_and_time sshd pgid; procs 'sshd'; mark DONE sshdpg ;;
sleeper)
  procs 'sleep'
  term_and_time sleeper pid
  sleep 0.5; procs 'sleep'
  sleep 11   # 빨리 죽음 카운터를 비운다(FAST_EXIT_SECONDS 10)
  term_and_time sleeper pgid
  sleep 0.5; procs 'sleep'
  mark DONE sleeper
  ;;
stubborn)
  p=$(leader stubborn); mark PID "stubborn $p"
  kill -TERM "$p"; sleep 3
  mark ALIVE "after TERM+3s state=$(state "$p")"
  kill -KILL "$p"; sleep 0.5
  mark ALIVE "after KILL+0.5s state=$(state "$p")"
  procs 'stubborn|sleep'
  mark DONE stubborn
  ;;
giveup)
  # 넷인 이유 — 첫 라운드는 오래 산 sshd라 카운터를 0으로 되돌린다(실측 6).
  for i in 1 2 3 4; do
    p=$(leader sshd); mark PID "round $i sshd $p"
    [ -z "$p" ] && break
    kill -TERM "$p"
    for _ in $(seq 1 30); do n=$(leader sshd); [ -n "$n" ] && [ "$n" != "$p" ] && break; sleep 0.1; done
  done
  sleep 3
  mark AFTER "sshd=[$(leader sshd)]"
  mark DONE giveup
  ;;
*)
  mark USAGE "unknown phase"
  ;;
esac
EOF
chmod 755 /tmp/ct/seed/ctm0.sh
```

`term_and_time`가 좀비와 거둠을 따로 재는 이유 — 좀비가 되는 것은 sshd가 스스로
죽는 속도이고, `/proc/<pid>`가 사라지는 것은 PID 1이 `waitpid`를 부르는 속도다. PID 1은
SIGCHLD 핸들러가 없어 `poll`의 1초 시한에 깨어 거둔다(`POLL_TIMEOUT_MS`의 주석 3).
둘의 차이가 결정 6의 클라이언트가 5초 안에 `stopped`를 보리라는 가정의 근거다.

- [ ] Step 3: 클라이언트 키와 디스크를 굽는다

sshd 링크와 `/config/ssh`의 모양은 `service/check.sh`의 부팅 C와 같다. 소유자를
root로 맞추려고 시드를 컨테이너 안에서 복사해 `chown`한 뒤 굽는다(SV-M0 Task 3과 같은
이유 — StrictModes).

```bash
docker run --rm -v /tmp/ct:/tmp/ct tars-devcontainer bash -c '
  set -e
  cd /tmp/ct
  ssh-keygen -q -t ed25519 -N "" -C ctm0 -f good
  rm -rf /root/seed; cp -a seed /root/seed
  cp good.pub /root/seed/ssh/authorized_keys
  chown -R 0:0 /root/seed
  chmod 700 /root/seed/ssh; chmod 600 /root/seed/ssh/authorized_keys
  dd if=/dev/zero of=cfg.img bs=1M count=16 status=none
  mkfs.ext2 -F -q -m 0 -L tars-ct -d /root/seed cfg.img
  debugfs -w -R "symlink services.d/sshd /etc/tars/services/sshd" cfg.img
  debugfs -R "ls -l /" cfg.img 2>/dev/null
  debugfs -R "ls -l /services.d" cfg.img 2>/dev/null'
```

기대: `/`에 `tars.conf` · `ctm0.sh` · `ct` · `services.d` · `ssh`, `/services.d`에
`sleeper`(755) · `stubborn`(755) · `sshd`(링크).

## Task 3 — 하네스를 쓴다

- [ ] Step 1: `/tmp/ct/boot.sh`를 쓴다

```bash
cat > /tmp/ct/boot.sh <<'EOF'
#!/usr/bin/env bash
# CT-M0. 컨테이너 안에서 돈다.
set -uo pipefail
cd /workspace
LOG=/tmp/ct/guest.log
FIFO=/tmp/ct/guest.fifo
rm -f "$LOG" "$FIFO"; mkfifo "$FIFO"

(cd kernel && ./build.sh)       || { echo "CTM0: kernel build failed"; exit 1; }
(cd init && zig build)          || { echo "CTM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)   || { echo "CTM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "CTM0: initrd build failed"; exit 1; }

exec 4<>"$FIFO"
qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:45522-10.0.2.15:22" -device virtio-net-pci,netdev=n0 \
  -drive file=/tmp/ct/cfg.img,if=virtio,format=raw \
  -serial stdio \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU=$!
cleanup() { kill "$QEMU" 2>/dev/null; wait 2>/dev/null; exec 4>&-; rm -f "$FIFO"; }
trap cleanup EXIT

W=0
until grep -aq "Server listening on 0.0.0.0 port 22" "$LOG" 2>/dev/null; do
  sleep 1; W=$((W + 1))
  [ "$W" -ge 150 ] && { echo "CTM0: sshd never listened"; tail -40 "$LOG"; exit 1; }
done
echo "CTM0: sshd up after ${W}s"
sleep 12   # 부팅 때 뜬 서비스들이 FAST_EXIT_SECONDS를 넘기게 둔다

run() {  # 한 단계를 치고 그 단계의 DONE 표지가 하나 늘기를 기다린다
  local phase="$1" n
  n=$(grep -ac "CTM0-DONE $phase" "$LOG")
  printf 'bash /config/ctm0.sh %s\n' "$phase" >&4
  for _ in $(seq 1 90); do
    [ "$(grep -ac "CTM0-DONE $phase" "$LOG")" -gt "$n" ] && return 0
    sleep 1
  done
  echo "CTM0: $phase never answered"
}

SSHO=(-p 45522 -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/tmp/ct/known_hosts -o IdentitiesOnly=yes)

sess_start() {  # $1 = 이름. 8초짜리 원격 명령을 걸어 둔다
  timeout 40 ssh "${SSHO[@]}" -i /tmp/ct/good root@127.0.0.1 \
    'echo started; sleep 8; echo survived' > "/tmp/ct/sess-$1.out" 2>&1 &
  SESS=$!
  for _ in $(seq 1 20); do grep -q started "/tmp/ct/sess-$1.out" && break; sleep 0.5; done
}
sess_end() {
  wait "$SESS"; local rc=$?
  echo "CTM0-SESS $1 rc=$rc out=[$(tr '\n' ';' < "/tmp/ct/sess-$1.out")]"
}

run sock
run stubborn
run sleeper
sess_start leader; run sshd;   sess_end leader
sleep 12
sess_start group;  run sshdpg; sess_end group
sleep 12
run giveup
echo "=== done ==="
EOF
chmod +x /tmp/ct/boot.sh
```

`sleep 12`를 sshd 단계 사이에 두는 이유 — 되살아난 sshd가 10초를 못 채우고 다시
죽으면 빨리 죽음으로 세어진다. 측정 3 · 4가 측정 6(포기)과 섞이지 않게, 셋째 단계
`giveup`에서만 카운터가 차게 한다.

## Task 4 — 부팅 하나를 돌린다 (빌드가 끝나 있으면 약 3분)

- [ ] Step 1: 돌린다

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/ct:/tmp/ct -w /workspace \
  tars-devcontainer bash /tmp/ct/boot.sh > /tmp/ct/run.log 2>&1; echo "exit=$?"
grep -E '^CTM0|^===' /tmp/ct/run.log
grep -aoE "CTM0-[A-Z]+ .*" /tmp/ct/guest.log | tr -d '\r'
grep -aE "tars-init: .*(service|orphan)|sleeper:|stubborn:" /tmp/ct/guest.log | tr -d '\r'
```

적을 것 — 측정별로.

- 1 · 2: `CTM0-P sock …` 줄을 Task 1 Step 3의 컨테이너 값과 나란히 적는다. 다르면
  그 차이가 게스트 커널 설정 때문인지 본다.
- 3: `TERM sshd by=pid`의 `zombie_ms` · `reaped_ms`와 `BACK`. init 로그의 `service
  sshd killed (… signal 15 …)` 또는 `exited (… status …)` — sshd가 SIGTERM에 시그널로
  죽는지 exit하는지가 M1의 로그 문구를 정한다.
- 4: `SESS leader` · `SESS group`의 `out`에 `survived`가 있나. `PS` 줄에서
  `sshd-session`의 pgid · sid가 리더의 것과 같은가.
- 5: `sleeper` 단계의 `PS` — `by=pid` 뒤에 옛 `sleep`이 ppid 1로 남았나. `by=pgid`
  뒤에는 없나. `stubborn`의 `ALIVE` 둘(3초 뒤 살아 있음 · KILL 뒤 `Z`나 `gone`).
  KILL 뒤 `procs`에 옛 `sleep 1`이 ppid 1로 잠깐 남는지와 init 로그의 `reaped orphan`.
- 6: `giveup`의 `AFTER sshd=[]`와 init 로그의 `giving up on service sshd after 3 fast exits`.

- [ ] Step 2: 단계가 `never answered`면

`guest.log`의 끝 40줄을 본다. 콘솔 셸이 아직 앞 단계의 출력을 쓰고 있었거나 에코가
엉킨 것이다 — SV-M0 실측과 같은 방식으로 원인을 적고, `run` 사이에 `sleep 1`을 넣어
다시 돈다.

## Task 5 — 읽는 법과 판단

- 측정 1 · 2 — 기대대로면 결정 2 · 3이 그대로 선다. `MSG_TRUNC`의 모양이 M1의 "요청이
  너무 길다" 판정 방법을 정한다. `send`는 늘 `MSG_NOSIGNAL`로 한다 — PID 1은 커널이
  기본 동작이 종료인 시그널을 막아 주지만, 그것에 기대지 않는다.
- 측정 3 — `reaped_ms`가 1초 안팎이면 결정 6의 5초 기다림에 여유가 넉넉하다. 좀비까지가
  수백 ms를 넘으면 그 이유를 sshd 로그에서 찾아 적는다.
- 측정 4 — `SESS leader`가 살아남으면 위험 3은 닫힌다. `SESS group`까지 살아남으면
  sshd의 세션은 제 세션을 따로 잡는다는 뜻이고, `kill(-pgid)`를 골라도 ssh로 붙은
  사람이 `stop sshd`에 끊기지 않는다.
- 측정 5 — `by=pid`가 고아를 남기고 `by=pgid`가 안 남기면 결정 4를 "프로세스 그룹에
  보낸다"로 고친다(SIGTERM도 SIGKILL도). 그 판단은 이 실측을 근거로 design의 결정
  4에 적는다. `stubborn`이 3초 뒤에 살아 있으면 SIGKILL 경로가 필요하다는 것이 선다.
- 측정 6 — 포기가 재현되면 결정 4 규칙 2("hold 죽음을 세지 않는다")의 반사실이 무엇을
  볼지가 정해진다. M2의 반사실은 `restart` 셋으로 이 줄을 부른다.

## Task 6 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 "CT-M0이 실행으로 증명한 것" 절을 더한다

`docs/specs/2026-09-27-tars-service-control-design.md`의 "위험" 절 뒤에
SV design의 실측 절과 같은 모양으로 "실측 1 — …"부터 번호를 매겨 적는다. 로그 줄은
원문 그대로, 해석은 그 아래에 둔다. Task 5의 판단으로 결정이 바뀌면 그 결정 절도
고치고, 바뀐 까닭으로 실측 번호를 단다. `Status:` 줄을 "M0 끝났다"로 고친다.

- [ ] Step 2: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git add docs/specs/2026-09-27-tars-service-control-design.md \
        docs/plans/2026-09-27-tars-service-control-ct-m0.md
git commit -m "Measure CT-M0: seqpacket socket, sshd on SIGTERM, service groups"
```

기대: 저장소의 코드 파일이 목록에 없다.

## 이 milestone이 끝난 자리

커밋은 plan과 design(실측 절)뿐이다. 커널 · `init` · initrd · 체인은 그대로다.
다음은 CT-M1의 plan이고, 그 plan은 이 실측을 입력으로 쓴다.
