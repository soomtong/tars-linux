# FW-M0 — 방화벽을 넣기 전에 여덟을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 커밋되는 코드를 한 줄도 안
> 고친다. 만드는 것은 `/tmp/fw/` 아래의 하네스뿐이고, 저장소에 들어가는 것은
> design의 실측 절 · 확인 6 · 위험 6과 이 plan이다. `kernel/.config`는 측정하는
> 동안만 작업 트리에서 바뀌고 Task 7에서 되돌린다. TDD 구조가 아니다 — LB-M0 ·
> WN-M0 plan과 같은 형식이다.

Goal: FW design의 M0 목록(커널 옵션 · `nft` 비용 · 빈 include · `policy drop` 아래의
DHCP와 나가는 UDP · 받는 TCP · UDP의 판정 모양 · 문법 오류의 원자성)을 부팅 하나로
답해서, M1 · M2가 코드를 쓸 때 남은 결정을 없앤다.

Architecture: 작업 트리의 `kernel/.config`에 `scripts/config`로 netfilter 최소
집합을 켜고 빌드한다. `nft`와 그 라이브러리 · 규칙 파일 · 게스트 스크립트
`fwm0.sh`를 ext2 설정 디스크(`-L tars-fw`)에 실어 `/config/`로 닿게 한다. 콘솔
셸에는 FIFO로 `bash /config/fwm0.sh <단계>`를 한 줄씩 친다. 바깥에서 붙는 쪽은
컨테이너 안의 하네스(bash `/dev/tcp` · `/dev/udp`)와 perl echo 하나다. 규칙을 올리는
것도 게스트 안에서 손으로 한다 — M1이 `init`에 넣을 일을 먼저 손으로 해 본다.

Tech Stack: bash · `scripts/config` · QEMU(`virtio-net-pci` + SLIRP `hostfwd`) ·
`apt-get download nftables:amd64 libnftables1:amd64 …` · 게스트의 `nc.traditional` ·
`ip` · `dhcpcd` · 컨테이너의 perl · 기존 빌드 스크립트 넷

---

## 무엇을 재는가

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | `olddefconfig`가 끌고 들어오는 심볼, tristate가 `y`로 해소되나 | 확인 6 · 위험 2 | Task 1 |
| 2 | `nft`의 바이트와 재귀 `DT_NEEDED`, 그중 initrd에 없는 것 | 위험 3 | Task 2 |
| 3 | 기본 규칙이 이 커널에 올라가나(`Operation not supported`가 없나) | 결정 3 · 위험 2 | `load` |
| 4 | include glob이 디렉터리 없음 · 빈 디렉터리일 때 에러인가 | 결정 4 | `glob` |
| 5 | `policy drop` 아래에서 DHCP를 처음부터 다시 받나, 나가는 UDP · TCP의 답이 오나 | 위험 1 · 결정 3 | `dhcp` · `out` |
| 6 | 받는 TCP — 연 포트는 바이트, 안 연 포트는 0바이트이고 그 모양(시간 · 에러) | 결정 6 · 확인 5 | 하네스 `probe` |
| 7 | 받는 UDP — 연 포트는 게스트에 글자가 닿고, 안 연 포트는 안 닿는다 | 결정 6 · 위험 4 | 하네스 `probe` + `report` |
| 8 | 문법 오류 파일이 있으면 `nft -f`의 rc · stderr, 앞에 있던 규칙이 그대로인가(원자성) | 결정 5 | `bad` |

부팅은 하나다(`net=dhcp`, `virtio-net-pci` + SLIRP). 규칙을 올리기 전(`pre`)과
후(`post`)에 같은 `probe`를 한 번씩 해서 측정 6 · 7의 양성과 음성을 한 부팅 안에서
대조한다. `pre`에서는 넷 다 닿아야 한다 — 닿지 않으면 음성의 원인이 방화벽이
아니라 하네스다.

포트 넷. 컨테이너 쪽과 게스트 쪽 번호를 다르게 둔다 — 로그에서 어느 쪽 이야기인지
숫자만 보고 갈린다.

| 이름 | 컨테이너 `127.0.0.1` | 게스트 `10.0.2.15` | 규칙 |
|---|---|---|---|
| TCP A | 45470 | 7070 | 연다 |
| UDP B | 45471 | 7071 | 연다 |
| TCP C | 45472 | 7072 | 안 연다 |
| UDP D | 45473 | 7073 | 안 연다 |

## Task 0 — `/tmp/fw/`를 만든다

- [ ] Step 1: 디렉터리를 비우고 만든다

```bash
rm -rf /tmp/fw && mkdir -p /tmp/fw/seed/fw/lib /tmp/fw/seed/nftables.d && ls -la /tmp/fw
```

- [ ] Step 2: 작업 트리를 본다

```bash
git status --short
```

기대: design 한 줄(`M docs/superpowers/specs/2026-09-27-tars-firewall-design.md` —
확인 6 · 위험 6)과 이 plan만 있다. `kernel/.config`가 이미 바뀌어 있으면 Task 7의
되돌리기가 남의 변경까지 지우므로 멈추고 본다.

## Task 1 — 커널 옵션을 켜고 해소된 것을 본다 (측정 1)

- [ ] Step 1: `scripts/config`로 켠다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer \
  bash -c 'S=src/linux-6.18.42/scripts/config
    $S --file .config -e NETFILTER -e NF_TABLES -e NF_TABLES_IPV4 \
       -e NF_CONNTRACK -e NFT_CT
    grep -E "^(# )?CONFIG_(NETFILTER|NF_TABLES|NF_TABLES_IPV4|NF_CONNTRACK|NFT_CT)[= ]" .config'
cp kernel/.config /tmp/fw/config.edited
```

기대: 다섯 줄이 `=y`. `NETFILTER_ADVANCED`는 안 켠다 — 켜면 질문이 수십 개
늘고, 안 켜도 위 다섯이 선택 가능하다(Kconfig에서 확인했다).

- [ ] Step 2: 빌드하고 해소된 `.config`를 비교한다 (약 5~10분, 커널 전체 재빌드)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer \
  bash -c './build.sh 2>&1 | tail -3'
cp kernel/build/.config /tmp/fw/config.resolved
diff <(git show HEAD:kernel/.config | grep '^CONFIG_' | sort) \
     <(grep '^CONFIG_' /tmp/fw/config.resolved | sort) > /tmp/fw/config.diff
cat /tmp/fw/config.diff; wc -l /tmp/fw/config.diff
diff <(grep '^CONFIG_' /tmp/fw/config.edited | sort) \
     <(grep '^CONFIG_' /tmp/fw/config.resolved | sort) | head -40
ls -la kernel/build/arch/x86/boot/bzImage
```

적을 것 — `config.diff`의 `>` 줄 전부(켠 다섯 외에 끌려온 것: `NETFILTER_NETLINK` ·
`NF_DEFRAG_IPV4` 등), `=m`이 하나라도 있나, 편집본과 해소본이 갈린 줄, bzImage 크기의
변화(`git stash` 없이 HEAD 크기는 WN · LB 실측의 값을 인용한다). 갈린 줄이 있으면
M1이 커밋할 `.config`를 해소본으로 할지를 이 목록이 정한다(WN-M0과 같은 판단).

## Task 2 — `nft`를 꺼내고 비용을 잰다 (측정 2)

- [ ] Step 1: 패키지를 받아 풀고 재귀 `NEEDED`를 따라간다

```bash
docker run --rm -v /tmp/fw:/tmp/fw tars-devcontainer bash -c '
  set -e
  cd /tmp/fw
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get download nftables:amd64 libnftables1:amd64 >/dev/null
  for d in *.deb; do dpkg -x "$d" pkg; dpkg-deb -f "$d" Package Version Depends; echo; done
  SYS=/usr/local/amd64-sysroot
  nft=$(find pkg -path "*sbin/nft" | head -1); echo "FWM0-NFT $nft $(stat -c %s "$nft")"
  # 재귀 NEEDED. pkg 안에 있으면 pkg의 것, 아니면 sysroot의 것을 본다.
  todo="$nft"; seen=""
  while [ -n "$todo" ]; do
    f=${todo%% *}; todo=${todo#"$f"}; todo=${todo# }
    for n in $(readelf -d "$f" | sed -n "s/.*Shared library: \[\(.*\)\]/\1/p"); do
      case " $seen " in *" $n "*) continue ;; esac
      seen="$seen $n"
      p=$(find pkg -name "$n" | head -1)
      [ -z "$p" ] && p=$(find $SYS/lib $SYS/usr/lib -name "$n" 2>/dev/null | head -1)
      [ -z "$p" ] && { echo "FWM0-NEED $n MISSING"; continue; }
      r=$(readlink -f "$p"); echo "FWM0-NEED $n $(stat -c %s "$r") $r"
      todo="$todo $r"
      cp -L "$p" /tmp/fw/seed/fw/lib/"$n"
    done
  done
  cp "$nft" /tmp/fw/seed/fw/nft'
ls -la /tmp/fw/seed/fw /tmp/fw/seed/fw/lib
```

기대: `nft`와 `libnftables.so.1`이 `pkg`에서, 나머지(`libnftnl` · `libmnl` · `libjansson` ·
`libgmp` · `libedit` · `libxtables` 후보)가 sysroot에서 온다. `MISSING`이 있으면 그
패키지를 `apt-get download` 목록에 더해 다시 한다. 게스트에서 돌릴 때는 전부
`LD_LIBRARY_PATH`로 준다 — initrd에 무엇이 있든 이 측정은 흔들리지 않는다.

`libc.so.6`까지 `seed/fw/lib`에 복사되지만 게스트 스크립트가 그것을 안 쓰게
`LD_LIBRARY_PATH` 앞에 두지 않는다(Task 3의 `nftx`). 게스트 libc와 같은 파일이라
무해하지만, 측정은 "initrd의 libc로 도는가"여야 한다.

- [ ] Step 2: `NEEDED` 중 initrd에 이미 있는 것을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build >/dev/null && cd ../terminal && ./prepare.sh >/dev/null &&
  cd ../kernel && ./make_initrd.sh >/dev/null &&
  cpio -t < initrd.cpio 2>/dev/null | grep -E "lib(nft|mnl|jansson|gmp|edit|xtables|c)\." | sort'
ls /tmp/fw/seed/fw/lib
```

적을 것 — 두 목록의 차. 없는 것의 바이트 합이 M1이 initrd에 더할 무게다. 합이
initrd 전체의 몇 %인지도 적는다(`ls -la kernel/initrd.cpio`).

## Task 3 — 규칙 파일 · 게스트 스크립트 · 디스크

- [ ] Step 1: 규칙 파일 셋을 쓴다

```bash
cat > /tmp/fw/seed/fw/base.nft <<'EOF'
# FW-M0. design 결정 3의 기본 규칙 그대로(include 포함).
flush ruleset
table ip tars {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ct state invalid drop
    include "/tmp/nftables.d/*.nft"
  }
}
EOF
cat > /tmp/fw/seed/nftables.d/allow.nft <<'EOF'
tcp dport 7070 accept
udp dport 7071 accept
EOF
printf 'tcp dport 7072 acept\n' > /tmp/fw/seed/fw/bad.nft
```

include가 `/config/nftables.d`가 아니라 `/tmp/nftables.d`를 보는 이유 — 측정 4는
디렉터리가 없을 때 · 비었을 때 · 파일이 있을 때를 차례로 만들어야 하는데 `/config`의
내용을 게스트에서 바꾸면 디스크가 오염된다. 경로만 다르고 nft가 하는 일은 같다.

`flush ruleset`을 맨 위에 두는 것은 같은 파일을 여러 번 올려도 표가 겹치지 않게
하려는 것이다. M1의 기본 규칙에도 필요한지는 측정 8(원자성)의 결과와 함께 본다.

- [ ] Step 2: `/tmp/fw/seed/fwm0.sh`를 쓴다

```bash
cat > /tmp/fw/seed/fwm0.sh <<'EOF'
#!/bin/bash
# FW-M0. 게스트의 /config/fwm0.sh로 닿는다. 표지는 전부 "FWM0-<이름> ".
# 우리가 치는 줄은 "bash /config/fwm0.sh <단계>"뿐이라 그 에코에는 표지가 없다.
mark() { printf 'FWM0-%s %s\n' "$1" "$2"; }

# 게스트에 timeout이 없다(LB-M0 실측 9). 명령을 배경에서 돌리고 $1초 뒤에 죽인다.
tmo() {
  local t="$1"; shift
  "$@" & local p=$!
  ( sleep "$t"; kill "$p" 2>/dev/null ) >/dev/null 2>&1 & local k=$!
  wait "$p"; local rc=$?
  kill "$k" 2>/dev/null; wait "$k" 2>/dev/null
  return "$rc"
}

# /config가 noexec일 수 있어 tmpfs로 옮겨 돈다(LB-M0과 같다).
[ -x /tmp/fw/nft ] || { cp -r /config/fw /tmp/fw; chmod 755 /tmp/fw/nft; }
nftx() { LD_LIBRARY_PATH=/tmp/fw/lib-nolibc /tmp/fw/nft "$@"; }
if [ ! -d /tmp/fw/lib-nolibc ]; then
  mkdir -p /tmp/fw/lib-nolibc
  for f in /tmp/fw/lib/*; do
    case "$(basename "$f")" in libc.so.*|ld-linux*) ;; *) cp "$f" /tmp/fw/lib-nolibc/ ;; esac
  done
fi

load() {  # $1 = 파일. rc와 stderr를 한 줄로
  local err rc
  err=$(nftx -f "$1" 2>&1); rc=$?
  mark LOAD "file=$1 rc=$rc err=[$(echo "$err" | tr '\n' ';')]"
}

ruleset() { mark RULES "$(nftx list ruleset 2>&1 | tr '\n' ';' | tr -s ' ')"; }

# 넷을 새로 띄운다. TCP 둘은 연결이 오면 표지 글자를 보내고, UDP 둘은 받은 것을
# 파일에 적는다. stdin을 끊는 것은 IN-M2가 배운 것이다(fish가 job을 멈춘다).
listen() {
  # 게스트에 pkill이 없다. 앞 회차가 띄운 nc의 pid를 파일에서 읽어 죽인다.
  [ -f /tmp/fwm0.pids ] && kill $(cat /tmp/fwm0.pids) 2>/dev/null; sleep 0.3
  rm -f /tmp/fwm0.udp7071 /tmp/fwm0.udp7073 /tmp/fwm0.pids
  printf 'FWM0TCPA\n' | nc -l -p 7070 >/dev/null 2>&1 & echo $! >> /tmp/fwm0.pids
  printf 'FWM0TCPC\n' | nc -l -p 7072 >/dev/null 2>&1 & echo $! >> /tmp/fwm0.pids
  nc -u -l -p 7071 < /dev/null > /tmp/fwm0.udp7071 2>&1 & echo $! >> /tmp/fwm0.pids
  nc -u -l -p 7073 < /dev/null > /tmp/fwm0.udp7073 2>&1 & echo $! >> /tmp/fwm0.pids
  disown -a
  sleep 0.5
  mark LISTEN "$(grep -cE ':(1BAE|1BB0) ' /proc/net/tcp) tcp, $(grep -cE ':(1BAF|1BB1) ' /proc/net/udp) udp"
}

report() {  # 하네스가 UDP를 보낸 뒤에 친다. 글자는 파일에서 꺼내 표지 뒤에 둔다
  mark UDPB "[$(tr -d '\n' < /tmp/fwm0.udp7071 2>/dev/null)]"
  mark UDPD "[$(tr -d '\n' < /tmp/fwm0.udp7073 2>/dev/null)]"
  mark COUNTERS "$(cat /proc/net/snmp | grep -A1 '^Udp:' | tail -1)"
}

case "$1" in
pre)
  mark ADDR "$(ip -o -4 addr show | tr '\n' ';')"
  listen
  mark DONE pre
  ;;
report)
  report
  mark DONE report
  ;;
glob)
  # 측정 4. 디렉터리 없음 → 빈 디렉터리 → 파일 하나. 매번 표 전체를 다시 올린다.
  rm -rf /tmp/nftables.d
  load /tmp/fw/base.nft; ruleset
  mkdir -p /tmp/nftables.d
  load /tmp/fw/base.nft; ruleset
  mark DONE glob
  ;;
load)
  # 측정 3 · 6 · 7의 post 준비. allow.nft를 넣고 올린다.
  mkdir -p /tmp/nftables.d; cp /config/nftables.d/allow.nft /tmp/nftables.d/
  load /tmp/fw/base.nft; ruleset
  listen
  mark DONE load
  ;;
out)
  # 측정 5의 절반. 나가는 UDP · TCP의 답. 상대는 컨테이너의 perl echo(10.0.2.2).
  got=$(echo FWM0OUTU | tmo 4 nc -u -q 2 10.0.2.2 45480 2>&1); mark OUTUDP "rc=$? got=[$got]"
  got=$(echo FWM0OUTT | tmo 4 nc -q 2 10.0.2.2 45481 2>&1); mark OUTTCP "rc=$? got=[$got]"
  mark DONE out
  ;;
dhcp)
  # 측정 5의 나머지. 지금 manager를 멈추고 주소를 비운 뒤 처음부터 다시 받는다.
  dhcpcd -x >/dev/null 2>&1; sleep 1
  ip addr flush dev eth0; mark FLUSHED "$(ip -o -4 addr show dev eth0 | wc -l)"
  s=$(date +%s)
  out=$(tmo 40 dhcpcd -1 -4 eth0 2>&1); rc=$?
  mark DHCP "rc=$rc secs=$(( $(date +%s) - s )) addr=[$(ip -o -4 addr show dev eth0 | awk '{print $4}')]"
  mark DHCPLOG "$(echo "$out" | tail -5 | tr '\n' ';')"
  mark DONE dhcp
  ;;
bad)
  # 측정 8. 좋은 규칙이 선 상태에서 문법 오류 파일을 include에 넣고 다시 올린다.
  cp /tmp/fw/bad.nft /tmp/nftables.d/bad.nft
  load /tmp/fw/base.nft; ruleset
  rm -f /tmp/nftables.d/bad.nft
  mark DONE bad
  ;;
*)
  mark USAGE "unknown phase"
  ;;
esac
EOF
chmod 755 /tmp/fw/seed/fwm0.sh
```

`LISTEN`의 16진수는 7070~7073이다(`0x1BAE`~`0x1BB1`). `report`가 UDP 카운터를 같이
내는 이유 — UDP D가 안 닿았을 때 "커널이 받았는데 버렸다"와 "아예 안 왔다"를
`InDatagrams`로 가를 수는 없지만(방화벽은 UDP 층 앞에서 버린다) `pre`와 `post`의
차이로 방화벽이 버린 것이 카운터에 안 잡힌다는 것은 보인다.

`dhcp`는 `load` 뒤에 친다. 첫 lease는 규칙이 없을 때 받았으므로, 규칙 아래에서
DISCOVER부터 다시 하는 것이 위험 1의 질문이다.

- [ ] Step 3: perl echo를 쓴다

```bash
cat > /tmp/fw/echo.pl <<'EOF'
#!/usr/bin/perl
# FW-M0. 컨테이너에서 UDP 45480 · TCP 45481을 듣고 받은 줄 앞에 ECHO-를 붙여 돌려준다.
use strict; use warnings; use IO::Socket::INET; use IO::Select;
my $u = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 45480, Proto => 'udp') or die "udp: $!";
my $t = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 45481, Proto => 'tcp', Listen => 5, ReuseAddr => 1) or die "tcp: $!";
my $s = IO::Select->new($u, $t);
$| = 1; print "echo up\n";
while (my @r = $s->can_read) {
  for my $h (@r) {
    if ($h == $u) { my $m; my $from = $u->recv($m, 512); chomp $m; print "udp [$m]\n"; $u->send("ECHO-$m\n", 0, $from); }
    else { my $c = $t->accept; my $m = <$c> // ''; chomp $m; print "tcp [$m]\n"; print $c "ECHO-$m\n"; close $c; }
  }
}
EOF
```

SLIRP은 게스트가 `10.0.2.2`로 보낸 것을 컨테이너의 `127.0.0.1`로 넘긴다(TS-M0 실측 2 ·
IN). 그래서 echo는 `127.0.0.1`에 묶어도 게스트가 닿는다.

- [ ] Step 4: 디스크를 굽는다

```bash
printf '# FW-M0.\nhangul_layout=sebeol_3p3\nnet=dhcp\n' > /tmp/fw/seed/tars.conf
docker run --rm -v /tmp/fw:/tmp/fw tars-devcontainer bash -c '
  dd if=/dev/zero of=/tmp/fw/cfg.img bs=1M count=32 status=none
  mkfs.ext2 -F -q -m 0 -L tars-fw -d /tmp/fw/seed /tmp/fw/cfg.img
  debugfs -R "ls -l /" /tmp/fw/cfg.img 2>/dev/null
  debugfs -R "ls -l /fw" /tmp/fw/cfg.img 2>/dev/null | head'
```

기대: `/`에 `tars.conf` · `fwm0.sh` · `fw` · `nftables.d`, `/fw`에 `nft` · `base.nft` ·
`bad.nft` · `lib`. 라이브러리 합이 16MB를 넘을 수 있어 32MB로 굽는다.

## Task 4 — 하네스를 쓴다

- [ ] Step 1: `/tmp/fw/boot.sh`를 쓴다

```bash
cat > /tmp/fw/boot.sh <<'EOF'
#!/usr/bin/env bash
# FW-M0. 컨테이너 안에서 돈다.
set -uo pipefail
cd /workspace
LOG=/tmp/fw/guest.log
FIFO=/tmp/fw/guest.fifo
rm -f "$LOG" "$FIFO"; mkfifo "$FIFO"

(cd kernel && ./build.sh)       || { echo "FWM0: kernel build failed"; exit 1; }
(cd init && zig build)          || { echo "FWM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)   || { echo "FWM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "FWM0: initrd build failed"; exit 1; }

perl /tmp/fw/echo.pl > /tmp/fw/echo.log 2>&1 &
ECHO=$!

G=10.0.2.15
FWD="hostfwd=tcp:127.0.0.1:45470-$G:7070,hostfwd=udp:127.0.0.1:45471-$G:7071"
FWD="$FWD,hostfwd=tcp:127.0.0.1:45472-$G:7072,hostfwd=udp:127.0.0.1:45473-$G:7073"

exec 4<>"$FIFO"
qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -netdev "user,id=n0,$FWD" -device virtio-net-pci,netdev=n0 \
  -drive file=/tmp/fw/cfg.img,if=virtio,format=raw \
  -serial stdio \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU=$!
cleanup() { kill "$QEMU" "$ECHO" 2>/dev/null; wait 2>/dev/null; exec 4>&-; rm -f "$FIFO"; }
trap cleanup EXIT

W=0
until grep -aq "started console shell" "$LOG" 2>/dev/null; do
  sleep 1; W=$((W + 1))
  [ "$W" -ge 120 ] && { echo "FWM0: console shell never started"; tail -40 "$LOG"; exit 1; }
done
echo "FWM0: console shell up after ${W}s"
T0=$SECONDS
until grep -aqE "leased [0-9.]+ for" "$LOG"; do
  sleep 1; [ $((SECONDS - T0)) -ge 40 ] && { echo "FWM0: no lease in 40s"; break; }
done
sleep 2

run() {  # 한 단계를 치고 그 단계의 DONE 표지가 하나 늘기를 기다린다
  local phase="$1" n
  n=$(grep -ac "FWM0-DONE $phase" "$LOG")
  printf 'bash /config/fwm0.sh %s\n' "$phase" >&4
  for _ in $(seq 1 90); do
    [ "$(grep -ac "FWM0-DONE $phase" "$LOG")" -gt "$n" ] && return 0
    sleep 1
  done
  echo "FWM0: $phase never answered"
}

probe() {  # $1 = pre | post. TCP 둘은 읽은 바이트와 걸린 시간, UDP 둘은 보내기만 한다
  local tag="$1" port got s rc
  for port in 45470 45472; do
    got=""; s=$(date +%s%N)
    if exec 5<>"/dev/tcp/127.0.0.1/$port"; then
      read -r -t 5 got <&5; rc=$?
      exec 5>&- 5<&-
      echo "FWM0-PROBE $tag tcp $port connected rc=$rc bytes=${#got} got=[$got] ms=$(( ($(date +%s%N) - s) / 1000000 ))"
    else
      echo "FWM0-PROBE $tag tcp $port refused"
    fi
  done
  for port in 45471 45473; do
    printf 'FWM0UDP%s%s\n' "$tag" "$port" > "/dev/udp/127.0.0.1/$port"
    echo "FWM0-PROBE $tag udp $port sent rc=$?"
  done
  sleep 1
}

run pre
probe pre
run report
run glob
run load
probe post
run report
run out
run dhcp
run out
run bad
echo "=== done ==="
EOF
chmod +x /tmp/fw/boot.sh
```

UDP 표지 글자(`FWM0UDPpost45471`)는 하네스가 컨테이너에서 보내므로 게스트 화면에는
`report`의 `FWM0-UDPB [...]` 안에서만 나온다 — 게스트에 친 명령에는 없다
(`project_gate_screen_echo`).

`out`을 `dhcp` 앞뒤로 두 번 치는 이유 — 앞은 첫 lease(규칙 없이 받은 것) 위에서의
나가는 길이고, 뒤는 규칙 아래에서 새로 받은 lease 위에서의 나가는 길이다.

## Task 5 — 부팅 하나를 돌린다 (빌드가 끝나 있으면 약 2분)

- [ ] Step 1: 돌린다

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/fw:/tmp/fw -w /workspace \
  tars-devcontainer bash /tmp/fw/boot.sh > /tmp/fw/run.log 2>&1; echo "exit=$?"
grep -E '^FWM0|^===' /tmp/fw/run.log
grep -aoE "FWM0-[A-Z]+ .*" /tmp/fw/guest.log | tr -d '\r'
cat /tmp/fw/echo.log
grep -aE "tars-init: (config|net|started dhcpcd)|leased|nf_tables|netfilter" /tmp/fw/guest.log | head -20
```

적을 것 — 측정별로.

- 3: `load`의 `LOAD rc`와 `err`, `RULES`에 `policy drop`과 include로 들어온 두 줄이
  펼쳐져 있나.
- 4: `glob`의 두 `LOAD` — 디렉터리 없음 · 빈 디렉터리 각각의 rc와 `err`.
- 5: 첫 `out`의 `OUTUDP` · `OUTTCP`, `DHCP`의 rc · 초 · 주소, `DHCPLOG`, 둘째 `out`.
  `echo.log`에 udp · tcp 줄이 각각 몇 개인가.
- 6: `pre`와 `post`의 TCP 두 줄 — `bytes` · `rc` · `ms`. `post`의 45472가 `connected
  bytes=0`이고 `ms`가 5000 근처인지(읽기 타임아웃) 더 빠른지(SLIRP이 끊었다).
- 7: 두 번의 `report` — `UDPB` · `UDPD`의 글자와 `COUNTERS`.
- 8: `bad`의 `LOAD` rc · `err`(몇 행 · 무슨 말), 그 뒤 `RULES`가 `load` 때와
  같은가(원자성). 같지 않으면 표가 통째로 사라졌는지 반쯤 섰는지를 적는다.

- [ ] Step 2: 측정 3에서 `Operation not supported`가 나오면

`err`가 가리키는 표현식(예: `ct`)에 해당하는 옵션을 Task 1 Step 1의 `-e` 목록에
더하고 Task 1 Step 2부터 다시 한다. 더한 옵션은 design 위험 2의 실측으로 적는다.

## Task 6 — 읽는 법과 판단

- 측정 1 — `=m`이 하나도 없고 끌려온 것이 `NETFILTER_NETLINK` · `NF_DEFRAG_IPV4` 같은
  예상한 것뿐이다 → M1은 Task 1의 다섯을 그대로 켠다. 뜻밖의 큰 것(예: `NETFILTER_XTABLES`
  계열)이 끌려오면 사용자에게 알린다.
- 측정 2 — 없는 라이브러리의 합이 1MB 안팎이면 M1이 그대로 넣는다. 훨씬 크면(예:
  `libgmp` · `libxtables`가 큰 몫) design 위험 3대로 사용자에게 먼저 알린다.
- 측정 3 — `rc=0`이면 결정 3의 기본 규칙이 그대로 M1의 파일이다.
- 측정 4 — 디렉터리 없음이 에러이면, M1의 `init`은 `nft`를 부르기 전에
  `/config/nftables.d`가 없으면 기본 규칙 전용 파일로 가거나, initrd에 빈 디렉터리
  자리를 두는 식으로 피해야 한다. 둘 중 무엇인지는 M1 plan이 정한다.
- 측정 5 — `DHCP rc=0`이고 주소가 같다 → 위험 1이 닫힌다(dhcpcd는 raw socket이라
  hook 앞이다). `rc`가 0이 아니거나 40초를 채웠으면 design 위험 1의 처방(67→68 허용
  한 줄)을 `load`에 더해 이 부팅을 한 번 더 돌려 확인한다.
- 측정 6 — M1 체인의 TCP 음성 판정이 `bytes=0`인지, 그리고 읽기 타임아웃을 몇 초로
  둘지가 여기서 정해진다.
- 측정 7 — `post`의 `UDPB`에 글자가 있고 `UDPD`가 비었으면 M2의 UDP 판정은 이
  모양(게스트가 파일에 받고 표지로 화면에 낸다)이다.
- 측정 8 — `rc`가 0이 아니고 `RULES`가 `load` 때와 같으면 `nft -f`는 원자적이다.
  그러면 결정 5의 갈래 2는 "앞의 규칙이 그대로다"가 아니라 "아무 규칙도 없다"(부팅
  첫 회라 앞이 없다)이므로 기본 규칙 전용 파일을 다시 올리는 설계가 맞다. 원자적이지
  않으면 결정 5를 다시 연다.

## Task 7 — `.config`를 되돌리고 design에 실측을 적고 커밋한다

- [ ] Step 1: 커널 설정을 되돌린다

```bash
git checkout kernel/.config
git status --short
```

기대: design과 이 plan만 남는다. `kernel/build/`는 추적 대상이 아니라 다음 빌드의
스탬프가 `.config` 해시로 다시 빌드한다(`kernel/build.sh`).

- [ ] Step 2: design에 "FW-M0이 실행으로 증명한 것" 절을 더한다

`docs/superpowers/specs/2026-09-27-tars-firewall-design.md`의 "위험" 절 뒤에 LB design의
실측 절과 같은 모양으로 "실측 1 — …"부터 번호를 매겨 적는다. 로그 줄은 원문 그대로,
해석은 그 아래에 둔다. Task 6의 판단과 M1이 넘겨받을 것도 적는다. `Status:` 줄을
"M0 끝났다"로 고친다.

- [ ] Step 3: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git add docs/superpowers/specs/2026-09-27-tars-firewall-design.md \
        docs/superpowers/plans/2026-09-27-tars-firewall-fw-m0.md
git commit -m "Measure FW-M0: netfilter options, nft cost, and what drop lets through"
```

기대: 저장소의 코드 파일이 목록에 없다.

## 이 milestone이 끝난 자리

커밋은 plan과 design(확인 6 · 위험 6 · 실측 절)뿐이다. 커널 · `init` · initrd · 체인은
그대로다. 다음은 FW-M1의 plan이고, 그 plan은 이 실측을 입력으로 쓴다.
