# DS-M0 — 두 데몬을 감독 목록에 넣기 전에 여섯을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 커밋되는 코드를 한 줄도 안
> 고친다. 만드는 것은 `/tmp/ds/` 아래의 하네스와 게스트 스크립트뿐이고, 저장소에
> 들어가는 것은 design의 실측 절과 이 plan이다. TDD 구조가 아니다 — CT-M0 plan과
> 같은 형식이다.

Goal: DS design의 M0 목록(dhcpcd `-B`의 동작 · 늦게 꽂힌 동글 · SIGTERM · chrony의
`sourcedir`와 `reload sources` · chronyd보다 먼저 쓰인 `.sources`)을 부팅 둘로 답해서,
M1이 결정 2 · 3을 그대로 쓸지 고칠지를 정한다.

Architecture: `tars.conf`가 `net=off`인 디스크로 뜬다. 그러면 `init`은 dhcpcd도
chronyd도 안 띄운다(`net.bringUp` · `clock.start`의 `off` 갈래). 그 게스트의 콘솔
셸에 FIFO로 `bash /config/dsm0.sh <단계>`를 치고, 스크립트가 두 데몬을 M1이 띄울
모양 그대로 손으로 띄운다 — `setsid` · stdin은 `/dev/null` · 출력은 `/dev/console` ·
`exec`로 pid를 지킨다(`detachService`와 같다). 부팅 A는 virtio-net과 컨테이너의
NTP stub, 부팅 B는 NIC 없는 q35에 monitor로 usb-net을 꽂는다(`nic/check.sh` 부팅 B와
같다).

Tech Stack: Zig 0.16(`detach` 하나) · bash · `mkfs.ext2 -d` · QEMU(`virtio-net-pci` · q35 + `qemu-xhci` +
`usb-net` · monitor) · `net/ntp_stub.pl` · 게스트의 `dhcpcd` · `chronyd` · `chronyc` ·
`ps` · `ip`

---

## 무엇을 재는가

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | `-B`의 dhcpcd가 쥔 pid 그대로 살아서 lease를 받나. 그 pid 아래 프로세스(privsep)가 몇이고 pgid · sid가 무엇인가 | 결정 2 · 위험 1 | A `dh` |
| 2 | `-j` 없이 stderr를 콘솔로 줄 때 `leased` 줄이 콘솔에 오나. `-j /dev/console`을 더하면 줄이 두 번 오나 | 결정 2 | A `dh` · `dhj` |
| 3 | 그룹에 보낸 SIGTERM에 dhcpcd가 몇 ms에 죽나. 남는 프로세스가 있나. 주소가 빠지나. 곧바로 다시 띄우면 lease까지 몇 ms인가 | 결정 1 · 결정 2 | A `dh` |
| 4 | `sourcedir`만 있는 설정으로 chronyd가 서버 0개로 뜨나. 디렉터리가 없어도 뜨나. `chronyc reload sources`가 `cmdport 0`에서 unix 소켓으로 닿나. reload부터 2031년까지 몇 ms인가 | 결정 3 · 위험 2 | A `ch` |
| 5 | chronyd가 뜨기 전에 쓰인 `.sources`를 읽나. 그때 2031년까지 몇 ms인가. chronyd가 없을 때 `chronyc reload sources`의 rc와 문구 | 결정 3 · 위험 2 | A `ch2` |
| 6 | NIC 없이 뜬 `-B` dhcpcd가 나중에 꽂힌 usb-net을 같은 pid로 잡나 | 위험 1 | B `usb` |

부팅 A가 `fd` 단계에서 콘솔 셸의 fd 목록을 한 번 찍는다. CT design 실측 7(버튼 fd가
샌다)의 기준선이고 결정 6의 반사실이 비교할 값이다.

기준값. TD design 실측 13이 지금 경로(설정에 `server`가 처음부터 있다)의 점프 시간을
갖고 있다. 측정 4 · 5의 ms를 그 값과 나란히 적는다.

## Task 0 — `/tmp/ds/`를 만든다

- [ ] Step 1: 디렉터리를 비우고 만든다

```bash
rm -rf /tmp/ds && mkdir -p /tmp/ds/seed && ls -la /tmp/ds
```

- [ ] Step 2: 작업 트리를 본다

```bash
git status --short
```

기대: 이 plan 한 줄만 있다.

## Task 1 — 게스트 스크립트와 디스크

- [ ] Step 0: `/tmp/ds/detach.zig`를 쓰고 x86_64로 빌드한다

```bash
cat > /tmp/ds/detach.zig <<'EOF'
//! DS-M0 하네스. 저장소에 안 들어간다. 게스트에 setsid가 없어서 만든다.
//! detach <pid 파일> <절대 경로> [인자…] — 새 세션을 만들고, stdin을 /dev/null로
//! 바꾸고, 제 pid를 파일에 적고, execve한다. init의 detachService와 같은 모양이다.
const std = @import("std");
const linux = std.os.linux;

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len < 3) return 2;
    if (@as(isize, @bitCast(linux.setsid())) < 0) return 3;
    const nul = linux.open("/dev/null", .{ .ACCMODE = .RDONLY }, 0);
    _ = linux.dup2(@intCast(nul), 0);
    const pf = linux.open(argv[1], .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    var buf: [16]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}\n", .{linux.getpid()}) catch return 4;
    _ = linux.write(@intCast(pf), text.ptr, text.len);
    _ = linux.close(@intCast(pf));
    const rc = linux.execve(argv[2], @ptrCast(argv[2..].ptr), @ptrCast(init.environ.block.slice.ptr));
    std.debug.print("detach: execve {s} errno {d}\n", .{ argv[2], @intFromEnum(linux.errno(rc)) });
    return 127;
}
EOF
docker run --rm -v /tmp/ds:/tmp/ds -w /tmp/ds tars-devcontainer \
  zig build-exe detach.zig -O ReleaseSafe -target x86_64-linux-musl -femit-bin=seed/detach
ls -la /tmp/ds/seed/detach
```

plan을 쓰면서 한 번 컴파일해 봤다. `init.environ.block`은 포인터가 아니라
`PosixBlock`이고 `.slice.ptr`이 envp다(Zig 0.16).

- [ ] Step 1: `tars.conf`를 쓴다

```bash
printf '# DS-M0. init이 dhcpcd와 chronyd를 안 띄우게 한다.\nnet=off\n' > /tmp/ds/seed/tars.conf
```

- [ ] Step 2: `/tmp/ds/seed/dsm0.sh`를 쓴다

```bash
cat > /tmp/ds/seed/dsm0.sh <<'EOF'
#!/bin/bash
# DS-M0. 게스트의 /config/dsm0.sh로 닿는다. 표지는 전부 "DSM0-<이름> ".
# 우리가 치는 줄은 "bash /config/dsm0.sh <단계>"뿐이라 그 에코에는 표지가 없다.
mark() { printf 'DSM0-%s %s\n' "$1" "$2"; }
ms() { echo $(( $(date +%s%N) / 1000000 )); }
state() { sed -n 's/^State:\s*\(.\).*/\1/p' "/proc/$1/status" 2>/dev/null || echo gone; }
procs() {  # $1 = 이름 패턴. pid · ppid · pgid · sid · 상태 · 이름 · 인자
  ps -eo pid=,ppid=,pgid=,sid=,stat=,args= | grep -E "$1" | grep -v grep \
    | while IFS= read -r l; do mark PS "$l"; done
}
addr() { ip -4 -o addr show "$1" 2>/dev/null | awk '{print $4}'; }

# M1의 detachService와 같은 모양으로 띄운다 — 새 세션, stdin은 /dev/null,
# 출력은 콘솔. detach가 자기 pid를 적고 exec하므로 적힌 pid가 곧 데몬이다.
# $1 = pid 파일, $2 = 절대 경로, 나머지 = 인자.
launch() {
  local pf="$1"; shift
  rm -f "$pf"
  /config/detach "$pf" "$@" >/dev/console 2>&1 &
  for _ in $(seq 1 50); do [ -s "$pf" ] && break; sleep 0.1; done
  cat "$pf"
}

# $1 = 인터페이스, $2 = 시한(초). 주소가 붙은 ms를 찍는다. 못 받으면 -.
wait_lease() {
  local t0 i
  t0=$(ms)
  for i in $(seq 1 $(( $2 * 10 ))); do
    [ -n "$(addr "$1")" ] && { echo $(( $(ms) - t0 )); return; }
    sleep 0.1
  done
  echo -
}

# $1 = pid. 그룹에 SIGTERM을 보내고 좀비(또는 사라짐)까지 ms를 찍는다.
term_group() {
  local p="$1" t0 tz=-
  t0=$(ms); kill -TERM -- "-$p"
  for _ in $(seq 1 300); do
    case "$(state "$p")" in Z|gone) tz=$(( $(ms) - t0 )); break ;; esac
    sleep 0.01
  done
  echo "$tz"
}

# $1 = 기다릴 해. date +%Y가 그 해가 되는 ms를 찍는다. 벽시계가 뛰는 것을
# 재므로 벽시계로 재면 뛴 폭이 더해진다 — 단조 시계(/proc/uptime)로 잰다.
up_ms() { local u; read -r u _ < /proc/uptime; echo $(( ${u%.*} * 1000 + 10#${u#*.} * 10 )); }
wait_year() {
  local t0 i
  t0=$(up_ms)
  for i in $(seq 1 600); do
    [ "$(date -u +%Y)" = "$1" ] && { echo $(( $(up_ms) - t0 )); return; }
    sleep 0.1
  done
  echo -
}

CONF=/run/tars/dsm0-chrony.conf
SRC=/run/tars/chrony.sources

case "$1" in
fd)
  ls -l "/proc/$$/fd" | while IFS= read -r l; do mark FD "$l"; done
  mark DONE fd
  ;;
dh)
  # 측정 1 · 2 · 3. -j 없이 띄운다.
  p=$(launch /run/dsm0-dh.pid /usr/bin/dhcpcd -B -o ntp_servers); mark PID "dhcpcd $p"
  mark LEASE "first ms=$(wait_lease eth0 60) addr=$(addr eth0)"
  sleep 2
  mark ALIVE "pid $p state=$(state "$p")"
  procs 'dhcpcd'
  mark TERM "ms=$(term_group "$p")"
  sleep 1
  procs 'dhcpcd'
  mark ADDR "after TERM addr=[$(addr eth0)]"
  p=$(launch /run/dsm0-dh.pid /usr/bin/dhcpcd -B -o ntp_servers); mark PID "dhcpcd again $p"
  mark LEASE "again ms=$(wait_lease eth0 60) addr=$(addr eth0)"
  mark TERM "again ms=$(term_group "$p")"
  sleep 1
  mark DONE dh
  ;;
dhj)
  # 측정 2의 대조. init이 지금 주는 -j를 더한다.
  p=$(launch /run/dsm0-dh.pid /usr/bin/dhcpcd -B -j /dev/console -o ntp_servers); mark PID "dhcpcd -j $p"
  mark LEASE "ms=$(wait_lease eth0 60) addr=$(addr eth0)"
  sleep 2
  mark TERM "ms=$(term_group "$p")"
  sleep 1
  mark DONE dhj
  ;;
ch)
  # 측정 4. 먼저 주소를 받아 둔다 — chronyd가 물으려면 길이 있어야 한다.
  p=$(launch /run/dsm0-dh.pid /usr/bin/dhcpcd -B -o ntp_servers); mark PID "dhcpcd $p"
  mark LEASE "ms=$(wait_lease eth0 60)"
  mkdir -p /run/tars
  rm -rf "$SRC"
  printf 'sourcedir %s\nmakestep 1 3\ncmdport 0\n' "$SRC" > "$CONF"
  mark YEAR "before $(date -u +%Y)"
  # 디렉터리가 아직 없다 — init은 hook보다 먼저 설정을 쓴다.
  c=$(launch /run/dsm0-ch.pid /usr/bin/chronyd -d -u root -f "$CONF"); mark PID "chronyd $c"
  sleep 3
  mark ALIVE "chronyd no-dir state=$(state "$c")"
  chronyc -n sources 2>&1 | while IFS= read -r l; do mark SRCS0 "$l"; done
  ls -la /run/chrony 2>&1 | while IFS= read -r l; do mark RUNDIR "$l"; done
  # hook이 할 일을 손으로 한다 — 파일을 먼저 쓰고 reload를 나중에 부른다.
  mkdir -p "$SRC"
  printf 'server 10.0.2.2 iburst\n' > "$SRC/dhcp.sources"
  t0=$(ms)
  out=$(chronyc reload sources 2>&1); rc=$?
  mark RELOAD "rc=$rc ms=$(( $(ms) - t0 )) out=[$out]"
  mark JUMP "after reload ms=$(wait_year 2031)"
  chronyc -n sources 2>&1 | while IFS= read -r l; do mark SRCS1 "$l"; done
  mark DONE ch
  ;;
ch2)
  # 측정 5. chronyd를 죽이고 시계를 되돌린 뒤, 파일이 이미 있는 채로 다시 띄운다.
  c=$(cat /run/dsm0-ch.pid)
  mark TERM "chronyd ms=$(term_group "$c")"
  sleep 1
  out=$(chronyc reload sources 2>&1); rc=$?
  mark RELOAD "no chronyd rc=$rc out=[$out]"
  date -u -s @1000000000 >/dev/null
  mark YEAR "rewound $(date -u +%Y)"
  c=$(launch /run/dsm0-ch.pid /usr/bin/chronyd -d -u root -f "$CONF"); mark PID "chronyd again $c"
  mark JUMP "pre-written ms=$(wait_year 2031)"
  chronyc -n sources 2>&1 | while IFS= read -r l; do mark SRCS2 "$l"; done
  mark DONE ch2
  ;;
usb)
  # 측정 6. 부팅 B. 인터페이스가 없는 채로 띄우고 하네스가 동글을 꽂기를 기다린다.
  p=$(launch /run/dsm0-dh.pid /usr/bin/dhcpcd -B -o ntp_servers); mark PID "dhcpcd $p"
  sleep 3
  mark ALIVE "no-nic state=$(state "$p")"
  mark READY "plug now"
  mark LEASE "usb0 ms=$(wait_lease usb0 90) addr=$(addr usb0)"
  mark ALIVE "after plug pid $p state=$(state "$p") now=[$(pgrep -x dhcpcd | tr '\n' ' ')]"
  mark DONE usb
  ;;
*)
  mark USAGE "unknown phase"
  ;;
esac
EOF
chmod 755 /tmp/ds/seed/dsm0.sh
```

`launch`가 `detach`를 쓰는 이유. 게스트에 `setsid`가 없다(`guest_tools.sh`에도
initrd에도 없다). 비대화형 bash의 `&`는 새 프로세스 그룹을 안 만들어서 `detach`의
`setsid()`가 곧바로 성공한다. `detach`가 pid를 적고 `execve`하므로 적힌 pid가 데몬
자신이고, 그 pid가 곧 세션 · 그룹 번호다 — M1에서 PID 1이 쥘 값과 같은 모양이다.

- [ ] Step 3: 디스크를 굽는다

```bash
docker run --rm -v /tmp/ds:/tmp/ds tars-devcontainer bash -c '
  set -e
  cd /tmp/ds
  dd if=/dev/zero of=cfg.img bs=1M count=16 status=none
  mkfs.ext2 -F -q -m 0 -L tars-ds -d seed cfg.img
  debugfs -R "ls -l /" cfg.img 2>/dev/null'
```

기대: `/`에 `tars.conf` · `dsm0.sh`(755) · `detach`(755).

## Task 2 — 하네스를 쓴다

- [ ] Step 1: `/tmp/ds/boot.sh`를 쓴다

```bash
cat > /tmp/ds/boot.sh <<'EOF'
#!/usr/bin/env bash
# DS-M0. 컨테이너 안에서 돈다. $1 = A(virtio-net + NTP stub) | B(q35, NIC 없음 + usb-net)
set -uo pipefail
cd /workspace
WHICH="$1"
LOG=/tmp/ds/guest-$WHICH.log
FIFO=/tmp/ds/guest.fifo
MON=45530
rm -f "$LOG" "$FIFO"; mkfifo "$FIFO"

if [ "$WHICH" = A ]; then
  (cd kernel && ./build.sh)       || { echo "DSM0: kernel build failed"; exit 1; }
  (cd init && zig build)          || { echo "DSM0: init build failed"; exit 1; }
  (cd terminal && ./prepare.sh)   || { echo "DSM0: terminal build failed"; exit 1; }
  (cd kernel && ./make_initrd.sh) || { echo "DSM0: initrd build failed"; exit 1; }
  perl net/ntp_stub.pl 123 1930367167 0 > /tmp/ds/stub.log 2>&1 &
  STUB=$!
  NET=(-netdev user,id=n0 -device virtio-net-pci,netdev=n0)
else
  STUB=
  NET=(-machine q35 -netdev user,id=n1 -device qemu-xhci,id=xhci)
fi

exec 4<>"$FIFO"
qemu-system-x86_64 \
  "${NET[@]}" \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -drive file=/tmp/ds/cfg.img,if=virtio,format=raw \
  -monitor tcp:127.0.0.1:${MON},server,nowait \
  -serial stdio \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU=$!
cleanup() {
  kill "$QEMU" 2>/dev/null; [ -n "$STUB" ] && kill "$STUB" 2>/dev/null
  wait 2>/dev/null; exec 4>&-; rm -f "$FIFO"
}
trap cleanup EXIT

W=0
until grep -aq "terminal: screen>" "$LOG" 2>/dev/null; do
  sleep 1; W=$((W + 1))
  [ "$W" -ge 150 ] && { echo "DSM0: guest never reached a prompt"; tail -40 "$LOG"; exit 1; }
done
echo "DSM0: prompt after ${W}s"
sleep 3

run() {  # 한 단계를 치고 그 단계의 DONE 표지가 하나 늘기를 기다린다
  local phase="$1" n
  n=$(grep -ac "DSM0-DONE $phase" "$LOG")
  printf 'bash /config/dsm0.sh %s\n' "$phase" >&4
  for _ in $(seq 1 180); do
    [ "$(grep -ac "DSM0-DONE $phase" "$LOG")" -gt "$n" ] && return 0
    sleep 1
  done
  echo "DSM0: $phase never answered"
}

if [ "$WHICH" = A ]; then
  run fd
  run dh
  run dhj
  run ch
  run ch2
else
  printf 'bash /config/dsm0.sh usb\n' >&4
  for _ in $(seq 1 60); do grep -aq "DSM0-READY" "$LOG" && break; sleep 1; done
  exec 3<>"/dev/tcp/127.0.0.1/${MON}"
  echo "device_add usb-net,netdev=n1,bus=xhci.0,id=u1" >&3
  sleep 0.3; exec 3<&- 3>&-
  echo "DSM0: plugged usb-net"
  for _ in $(seq 1 120); do grep -aq "DSM0-DONE usb" "$LOG" && break; sleep 1; done
fi
echo "=== done $WHICH ==="
EOF
chmod +x /tmp/ds/boot.sh
```

부팅 A만 빌드한다. 부팅 B는 A가 만든 산출물을 그대로 쓴다.

## Task 3 — 부팅 A를 돌린다 (빌드가 끝나 있으면 약 4분)

- [ ] Step 1: 돌린다

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/ds:/tmp/ds -w /workspace \
  tars-devcontainer bash /tmp/ds/boot.sh A > /tmp/ds/run-A.log 2>&1; echo "exit=$?"
grep -E '^DSM0|^===' /tmp/ds/run-A.log
grep -aoE "DSM0-[A-Z0-9]+ .*" /tmp/ds/guest-A.log | tr -d '\r'
grep -aE "dhcpcd|chronyd|leased|reaped orphan" /tmp/ds/guest-A.log | grep -av DSM0 | tr -d '\r'
grep -c "answer #" /tmp/ds/stub.log
```

적을 것 — 측정별로.

- 1: `dh`의 `ALIVE` 상태가 `S`인가(배경으로 안 갔다). `PS` 줄의 dhcpcd 프로세스 수와
  각각의 ppid · pgid · sid. 전부 pgid = `PID`의 값이면 그룹 시그널 하나가 다 닿는다.
- 2: `dh`의 구간(`DSM0-PID dhcpcd`부터 `DSM0-DONE dh`까지)에 `leased` 줄이 있나.
  `dhj` 구간에서 그 줄이 몇 번 나오나.
- 3: `TERM ms`, TERM 뒤 `PS`가 비었나, `ADDR`가 비었나, `LEASE again ms`. init 로그의
  `reaped orphan`(스크립트가 끝난 뒤 죽은 것만 거기로 간다).
- 4: `ALIVE chronyd no-dir`가 `S`인가. `SRCS0`이 서버 0개인가. `RUNDIR`에 `chronyd.sock`이
  있나. `RELOAD rc=0`인가. `JUMP after reload ms`.
- 5: `RELOAD no chronyd`의 rc와 문구. `JUMP pre-written ms`. `SRCS2`에 `10.0.2.2`가 있나.
- 기준선: `FD` 줄에 `/dev/input/event*`가 있나.

- [ ] Step 2: 단계가 `never answered`면

`guest-A.log`의 끝 40줄을 본다. 앞 단계가 남긴 dhcpcd나 chronyd가 콘솔에 쓰는 줄이
에코와 엉켰을 수 있다. 원인을 적고, 필요하면 `run` 사이에 `sleep 2`를 넣어 다시 돈다.

## Task 4 — 부팅 B를 돌린다 (약 3분)

- [ ] Step 1: 돌린다

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/ds:/tmp/ds -w /workspace \
  tars-devcontainer bash /tmp/ds/boot.sh B > /tmp/ds/run-B.log 2>&1; echo "exit=$?"
grep -E '^DSM0|^===' /tmp/ds/run-B.log
grep -aoE "DSM0-[A-Z0-9]+ .*" /tmp/ds/guest-B.log | tr -d '\r'
grep -aE "dhcpcd|usb0|cdc_ether|no valid interfaces" /tmp/ds/guest-B.log | grep -av DSM0 | tr -d '\r'
```

적을 것 — `ALIVE no-nic`가 `S`인가(인터페이스가 없어도 안 끝났다), `cdc_ether … usb0:
register`, `LEASE usb0 ms`, `ALIVE after plug`의 pid가 처음 pid와 같고 `now`에 그 pid
하나뿐인가.

## Task 5 — 읽는 법과 판단

- 측정 1 · 3 — 쥔 pid가 살아 있고 lease가 오면 결정 2가 선다. privsep 자식이 같은
  pgid면 CT의 그룹 시그널로 충분하다. TERM 뒤에 dhcpcd가 남으면 결정 1에 무엇을
  더할지 여기서 적는다. 주소가 빠지면 "dhcpcd를 재시작하면 잠깐 주소가 없다"를
  design 비목표 3에 적는다.
- 측정 2 — `-j` 없이 `leased`가 콘솔에 오면 M1이 `-j`를 뺄지 정한다. 체인이
  `[pid]: ` 줄머리를 grep하는 자리(nic 체인 검사 6 · 8)가 있으므로, 빼면 그 자리를
  함께 고쳐야 한다. 두 번 나오는 것이 싫다는 이유만으로는 안 뺀다.
- 측정 4 — 디렉터리가 없어도 chronyd가 살면 `init`은 설정만 쓰고 디렉터리를 안 만든다.
  죽으면 `init`이 설정을 쓸 때 디렉터리도 만든다(결정 3에 적는다). reload가 unix
  소켓으로 닿으면 hook의 `chronyc` 한 줄이 선다. `JUMP` ms를 TD 실측 13과 비교한다.
- 측정 5 — 먼저 쓰인 파일을 읽으면 위험 2와 "chronyd 재시작 뒤에도 서버를 안다"가
  닫힌다. chronyd가 없을 때의 rc가 0이 아니면 hook은 그 rc를 무시해야 한다 —
  dhcpcd-run-hooks가 hook의 실패를 어떻게 다루는지도 적는다.
- 측정 6 — 같은 pid로 usb0을 잡으면 위험 1이 닫힌다. 못 잡으면 결정 2를 다시 연다 —
  이때는 M1로 가지 않고 사용자와 design을 다시 본다.

## Task 6 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 "DS-M0이 실행으로 증명한 것" 절을 더한다

`docs/specs/2026-09-27-tars-daemon-supervision-design.md`의 "위험" 절 뒤에
CT design의 실측 절과 같은 모양으로 "실측 1 — …"부터 번호를 매겨 적는다. 로그 줄은
원문 그대로, 해석은 그 아래에 둔다. Task 5의 판단으로 결정이 바뀌면 그 결정 절도
고치고 바뀐 까닭으로 실측 번호를 단다. 끝에 "M0이 M1에 넘기는 것"을 둔다. `Status:`
줄을 "M0 끝났다"로 고친다.

- [ ] Step 2: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git add docs/specs/2026-09-27-tars-daemon-supervision-design.md \
        docs/plans/2026-09-27-tars-daemon-supervision-ds-m0.md
git commit -m "Measure DS-M0: dhcpcd -B, chrony sourcedir, late usb dongle"
```

기대: 저장소의 코드 파일이 목록에 없다.

## 이 milestone이 끝난 자리

커밋은 plan과 design(실측 절)뿐이다. 커널 · `init` · initrd · 체인은 그대로다.
다음은 DS-M1의 plan이고, 그 plan은 이 실측을 입력으로 쓴다.
