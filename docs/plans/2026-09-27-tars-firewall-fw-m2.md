# FW-M2 — UDP · 포트 여럿 · 틀린 파일, 그리고 FW를 닫는다

> 이 plan을 실행하는 사람에게: 체크박스(`- [ ]`)를 따라 Task 순서대로 간다.
> 편집 뒤에는 `git diff --stat`으로 더한 줄과 지운 줄을 따로 세고, 지우는 편집은
> `git diff | grep '^-'`로 의도한 줄만 지워졌는지 본다. 이 plan의 편집은 전부
> 체인 · 문서다 — `init` · 커널 · initrd는 M1 그대로다.

Goal: `firewall/check.sh`가 부팅 둘로 design 결정 6의 나머지를 판정한다 — UDP도 연
것만 닿는다, 파일 둘에 나눠 연 포트가 다 열린다, 사람의 파일이 틀려도 닫힌 채로
부팅이 끝난다(갈래 2). 그리고 가이드 · 루트 게이트 · 완료 표시로 FW를 닫는다.

Architecture: 체인의 부팅 A가 리스너 다섯(TCP 7070 · 7072 · 7074, UDP 7071 · 7073)을
띄운다. 연 것은 `allow.nft`(TCP 7070 · UDP 7071)와 `second.nft`(TCP 7074) 둘에
나뉜다. 부팅 B는 같은 디스크에 `broken.nft`(문법 오류)를 더한다. 게스트 쪽 판정
도구는 설정 디스크의 `fwlisten.sh` 하나이고, 판정 글자는 전부 그 스크립트의 출력에만
생긴다.

Tech Stack: bash · QEMU(`hostfwd` tcp · udp) · bash `/dev/tcp` · `/dev/udp` · 게스트
`nc.traditional` · `/proc/net/tcp` · `/proc/net/udp` · 기존 `gate_lib.sh`

---

## 판정의 모양

| 포트(게스트) | 컨테이너 | 여는 파일 | 부팅 A | 부팅 B |
|---|---|---|---|---|
| TCP 7070 | 45475 | `allow.nft` | 바이트가 온다 | 0바이트, 리스너가 산다 |
| TCP 7072 | 45476 | 없음 | 0바이트, 리스너가 산다 | (안 본다) |
| UDP 7071 | 45477 | `allow.nft` | 글자가 닿는다 | (안 본다) |
| UDP 7073 | 45478 | 없음 | 안 닿고, 리스너가 아직 아무와도 안 이어졌다 | (안 본다) |
| TCP 7074 | 45479 | `second.nft` | 바이트가 온다 | (안 본다) |

monitor는 부팅 A가 45474(M1과 같다), 부팅 B가 45480이다.

"리스너가 산다"의 근거. TCP는 한 번만 사는 리스너라(IN 결정 7) 연결을 받으면
죽는다 — LISTEN이 남아 있으면 연결이 게스트의 nc까지 안 왔다. UDP의 `nc -u -l`은 첫
데이터그램을 받으면 보낸 쪽에 connect해서 `/proc/net/udp`의 상대 주소가
`00000000:0000`에서 바뀐다 — 그대로면 아무것도 안 왔다. 둘 다 "빈 값"이 "게스트
프로그램이 조용했다"가 아니라 "커널이 넘겨주지 않았다"라는 증거다.

부팅 B에서 7070만 보는 이유. 갈래 2의 요점은 "사람의 파일 전부가 무시되고 기본
규칙만 섰다"이고, `allow.nft` 자체는 틀린 데가 없는데도 막힌다는 것이 그 증거다.

## Task 0 — 출발점

- [ ] Step 1

```bash
git status --short
git log --oneline -1
```

기대: 이 plan만 `??`(또는 plan의 커밋이 HEAD).

## Task 1 — 체인을 부팅 둘로 다시 쓴다

- [ ] Step 1: `firewall/check.sh`를 통째로 이 내용으로 바꾼다

M1의 검사 여덟은 부팅 A의 검사 1~5 · 6 · 8 · 11이 그대로 이어받는다(번호만 바뀐다).

```bash
#!/usr/bin/env bash
# FW 체인. 방화벽이 켜진 기계가 들어오는 것을 가르는가를 본다.
#
# 부팅 둘이다. 설정 디스크가 싣는 것.
#   tars.conf               net=dhcp · firewall=on
#   nftables.d/allow.nft    tcp dport 7070 · udp dport 7071 — 사람이 연 둘
#   nftables.d/second.nft   tcp dport 7074 — 다른 파일에 연 하나(include glob)
#   nftables.d/broken.nft   문법 오류 한 줄 — 부팅 B에만
#   fwlisten.sh             게스트에서 리스너 다섯을 띄우고 센다
#
# 판정의 재료(어느 포트를 열었나)는 이 파일의 변수이고, 판정 대상은 게스트
# 커널에 선 규칙이다. 둘을 같은 파일로 두지 않는다(LB 실측 17).
#
# 우리 코드는 init/src/firewall.zig의 배관뿐이다. 받고 버리는 것은 커널의
# nf_tables이고 규칙을 넣는 것은 nft다(design 결정 2).
set -uo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd .. && pwd)"

source ../gate_lib.sh

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 포트. 45455~45473은 앞의 체인들이 쓴다(monitor 대역 · IN · TS · TD · WN).
MONITOR_PORT_A=45474
MONITOR_PORT_B=45480
TCP_OPEN_PORT=45475    # → 게스트 7070, allow.nft가 연다
TCP_SHUT_PORT=45476    # → 게스트 7072, 아무도 안 연다
UDP_OPEN_PORT=45477    # → 게스트 7071, allow.nft가 연다
UDP_SHUT_PORT=45478    # → 게스트 7073, 아무도 안 연다
TCP_SECOND_PORT=45479  # → 게스트 7074, second.nft가 연다
G=10.0.2.15
HOSTFWD="hostfwd=tcp:127.0.0.1:${TCP_OPEN_PORT}-${G}:7070"
HOSTFWD="${HOSTFWD},hostfwd=tcp:127.0.0.1:${TCP_SHUT_PORT}-${G}:7072"
HOSTFWD="${HOSTFWD},hostfwd=udp:127.0.0.1:${UDP_OPEN_PORT}-${G}:7071"
HOSTFWD="${HOSTFWD},hostfwd=udp:127.0.0.1:${UDP_SHUT_PORT}-${G}:7073"
HOSTFWD="${HOSTFWD},hostfwd=tcp:127.0.0.1:${TCP_SECOND_PORT}-${G}:7074"

DISK_A="${REPO_ROOT}/out/firewall-a.img"
DISK_B="${REPO_ROOT}/out/firewall-b.img"
LOG_A="$(mktemp)"
LOG_B="$(mktemp)"
LOG="$LOG_A"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_A" "$LOG_B"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: firewall" \
    "tars-init: nft" \
    "tars-init: started dhcpcd (pid" \
    ": leased" \
    "tars-init: started console shell" \
    "terminal: screen>"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  local pattern
  for pattern in "$@"; do
    grep -a "$pattern" "$LOG" | head -3 | sed 's/^/  /' || true
  done
  echo "--- last screen lines ---"
  grep -a "terminal: screen>" "$LOG" | tail -n 5 || true
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

wait_for_log() {
  local pattern="$1" seconds="$2" i
  for i in $(seq 1 "$seconds"); do
    if grep -aE "$pattern" "$LOG" >/dev/null; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 1
  done
  return 1
}

# $1 = monitor 포트, $2 = 디스크. LOG가 가리키는 파일에 시리얼을 쓴다.
boot_guest() {
  qemu-system-x86_64 \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -display none \
    -netdev "user,id=n0,${HOSTFWD}" \
    -device virtio-net-pci,netdev=n0 \
    -drive file="$2",if=virtio,format=raw \
    -serial file:"$LOG" \
    -monitor tcp:127.0.0.1:$1,server,nowait \
    -no-reboot &
  QEMU_PID=$!

  wait_for_log "terminal: screen>" 120 || fail "terminal never rendered a prompt"

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/$1"; then connected=1; break; fi
    sleep 0.5
  done
  [ "$connected" = "1" ] || fail "could not connect to the QEMU monitor"
}

stop_guest() {
  echo "system_powerdown" >&3
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
  exec 3<&-
  exec 3>&-
}

# $1 = 컨테이너 포트. 한 줄을 읽어 TCP_GOT에 둔다. 붙지 못하면 TCP_CONNECTED=0.
# fd 5인 이유는 net 체인과 같다(3이 monitor다). 판정은 rc가 아니라 읽은 글자다 —
# SLIRP은 누구에게나 connect를 준다(IN 실측 4).
tcp_read() {
  TCP_CONNECTED=0
  TCP_GOT=""
  if exec 5<>"/dev/tcp/127.0.0.1/$1"; then
    TCP_CONNECTED=1
    read -r -t "$2" TCP_GOT <&5 || true
    exec 5<&-
    exec 5>&-
  fi
}

# 양성 TCP. 리스너가 bind를 끝내기 전에 붙는 날을 위해 열 번까지 다시 본다.
expect_tcp_bytes() {
  local port="$1" want="$2" guest="$3"
  for _ in $(seq 1 10); do
    tcp_read "$port" 5
    [ "$TCP_GOT" = "$want" ] && break
    sleep 0.2
  done
  [ "$TCP_GOT" = "$want" ] \
    || fail "nothing came through the opened port ${guest} (got: [${TCP_GOT}])" "tars-init: firewall"
  echo "the opened port ${guest} let ${want} through"
}

# 음성 TCP. 규칙이 SYN을 버리면 SLIRP은 체인 쪽 연결을 안 끊어서 read가 타임아웃을
# 꽉 쓴다(FW-M0 실측 6). 2초는 양성의 22ms와 멀다. 붙는 것을 따로 본다 — 안 보면
# hostfwd가 사라진 날에도 초록이다(IN 검사 16과 같은 자리).
expect_tcp_nothing() {
  local port="$1" guest="$2"
  tcp_read "$port" 2
  [ "$TCP_CONNECTED" = "1" ] \
    || fail "the negative check could not even connect — the hostfwd port ${port} is gone"
  [ -z "$TCP_GOT" ] \
    || fail "the unopened port ${guest} let something through (got: [${TCP_GOT}])" "tars-init: firewall"
  echo "the port ${guest} let nothing through"
}

# 게스트에 `bash /config/fwlisten.sh <인자>`를 친다. 인자는 type_keys의 키 이름들.
type_fwlisten() {
  type_keys b a s h spc slash c o n f i g slash f w l i s t e n dot s h "$@" ret
}

# 방화벽이 섰고, 어느 갈래였고, dhcpcd보다 먼저였나. $1 = 기대하는 규칙 파일.
# 순서는 줄 번호로 본다 — design 결정 5의 "규칙이 서기 전에 주소가 붙는 틈이
# 없다"를 로그에서 읽는 방법이다.
expect_firewall_before_dhcpcd() {
  local file="$1" fw_line dhcpcd_line
  fw_line="$(grep -an "tars-init: firewall up from ${file}" "$LOG" | head -1 | cut -d: -f1)"
  [ -n "$fw_line" ] || fail "init did not bring the firewall up from ${file}" "tars-init: firewall" "tars-init: nft"
  dhcpcd_line="$(grep -an "tars-init: started dhcpcd (pid" "$LOG" | head -1 | cut -d: -f1)"
  [ -n "$dhcpcd_line" ] || fail "init did not start dhcpcd"
  [ "$fw_line" -lt "$dhcpcd_line" ] \
    || fail "dhcpcd started (line ${dhcpcd_line}) before the firewall was up (line ${fw_line})"
  echo "the firewall came up from ${file} before dhcpcd started"
}

# ── 검사 1: 커널에 netfilter 다섯이 있나 ────────────────────────────────
# 부팅 전에 0.01초로 잡는다. 하나라도 빠지면 nft가 기본 규칙을 못 올리고
# init은 갈래 3(열린 채)으로 떨어진다 — 아래 검사 3이 빨갛지만 원인이 멀다.
CONFIG=../kernel/.config
for sym in NETFILTER NF_TABLES NF_TABLES_IPV4 NF_CONNTRACK NFT_CT; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
echo "the kernel carries the five netfilter options"

# ── 디스크 둘 ────────────────────────────────────────────────────────
# debugfs가 마운트 없이 ext2에 쓴다(project_seeding_a_config_disk). B는 A에
# broken.nft 하나를 더한 것이다.
mkdir -p "${REPO_ROOT}/out"
SEED="$(mktemp -d)"
printf 'net=dhcp\nfirewall=on\n' > "$SEED/tars.conf"
printf 'tcp dport 7070 accept\nudp dport 7071 accept\n' > "$SEED/allow.nft"
printf 'tcp dport 7074 accept\n' > "$SEED/second.nft"
printf 'tcp dport 7075 acept\n' > "$SEED/broken.nft"
cat > "$SEED/fwlisten.sh" <<'EOF'
#!/bin/bash
# FW 체인이 심는다. 판정 글자(fwm2-…=)는 출력에만 생기고 친 명령에는 없다.
#   (인자 없음)       리스너 다섯을 띄우고 LISTEN · 대기 중인 수를 센다
#   report           UDP 둘이 받은 것을 낸다
#   count tcp|udp N  그 포트의 리스너가 아직 아무와도 안 이어졌는지 센다
#
# /proc/net/tcp · udp는 포트를 16진수 넉 자로 적는다. 손으로 옮기지 않고
# printf가 바꾼다(FW design 실측 10). 상대 주소 00000000:0000이 "아직 아무와도
# 안 이어졌다"이고, 상태는 TCP LISTEN이 0A, 대기 중인 UDP가 07이다. nc -u -l은
# 첫 데이터그램을 받으면 보낸 쪽에 connect해서 상대 주소가 바뀐다.
tcp() { grep -c ":$(printf '%04X' "$1") 00000000:0000 0A" /proc/net/tcp; }
udp() { grep -c ":$(printf '%04X' "$1") 00000000:0000 07" /proc/net/udp; }
case "${1:-}" in
count)
  echo "fwm2-$2-$3=$("$2" "$3")"
  ;;
report)
  echo "fwm2-udp-open=[$(tr -d '\n' < /tmp/fwm2.7071 2>/dev/null)]"
  echo "fwm2-udp-shut=[$(tr -d '\n' < /tmp/fwm2.7073 2>/dev/null)]"
  ;;
*)
  for p in 7070 7072 7074; do
    printf 'fwm2-tcp-%s-ok\n' "$p" | nc -l -p "$p" >/dev/null 2>&1 &
  done
  for p in 7071 7073; do
    nc -u -l -p "$p" < /dev/null > "/tmp/fwm2.$p" 2>&1 &
  done
  t=0; u=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    t=$(( $(tcp 7070) + $(tcp 7072) + $(tcp 7074) ))
    u=$(( $(udp 7071) + $(udp 7073) ))
    [ "$t" -ge 3 ] && [ "$u" -ge 2 ] && break
    sleep 0.3
  done
  echo "fwm2-listen=${t}/${u}"
  ;;
esac
EOF
for B in A B; do
  D="${REPO_ROOT}/out/firewall-$(echo "$B" | tr AB ab).img"
  rm -f "$D"
  truncate -s 16M "$D"
  mkfs.ext2 -F -q -m 0 -L tars-fw "$D"
  debugfs -w -R "write $SEED/tars.conf tars.conf" "$D" 2>&1 | grep -v '^debugfs' || true
  debugfs -w -R "write $SEED/fwlisten.sh fwlisten.sh" "$D" 2>&1 | grep -v '^debugfs' || true
  debugfs -w -R "mkdir nftables.d" "$D" 2>&1 | grep -v '^debugfs' || true
  debugfs -w -R "write $SEED/allow.nft nftables.d/allow.nft" "$D" 2>&1 | grep -v '^debugfs' || true
  debugfs -w -R "write $SEED/second.nft nftables.d/second.nft" "$D" 2>&1 | grep -v '^debugfs' || true
  if [ "$B" = B ]; then
    debugfs -w -R "write $SEED/broken.nft nftables.d/broken.nft" "$D" 2>&1 | grep -v '^debugfs' || true
  fi
done
rm -rf "$SEED"

echo "=== boot A: net=dhcp firewall=on, allow.nft and second.nft ==="
LOG="$LOG_A"
boot_guest "$MONITOR_PORT_A" "$DISK_A"

# ── 검사 2: 설정이 firewall=on으로 읽혔나 ─────────────────────────────
grep -aE "tars-init: config shell=.* net=dhcp .* firewall=on" "$LOG" >/dev/null \
  || fail "the config disk did not turn the firewall on" "tars-init: config shell="
echo "the guest read net=dhcp and firewall=on off the config disk"

# ── 검사 3: 갈래 1로 섰나, 그리고 dhcpcd보다 먼저인가 ───────────────────
# 이 부팅의 파일은 틀린 데가 없으므로 nft가 한 번도 실패하면 안 된다.
expect_firewall_before_dhcpcd /etc/tars/firewall.nft
if grep -a "tars-init: nft -f" "$LOG" >/dev/null; then
  fail "nft failed on a boot whose files are all valid" "tars-init: nft -f" "Error:"
fi

# ── 검사 4: drop 아래에서 lease를 받나 ─────────────────────────────────
# FW-M0 실측 5. 받는 것을 기본으로 버리는 기계가 DHCP의 답까지 버리면 여기서
# 멈춘다.
wait_for_log "eth0: leased 10\.0\.2\.15 " 60 \
  || fail "dhcpcd never leased an address under the firewall" ": leased" "dhcpcd"
echo "dhcpcd leased 10.0.2.15 under policy drop"

# ── 검사 5: 게스트가 다섯을 다 듣나 ────────────────────────────────────
# 이 검사가 있어야 아래 음성 검사들의 빈 값이 "방화벽이 버렸다"로 읽힌다.
echo "=== typing 'bash /config/fwlisten.sh' ==="
type_fwlisten
wait_for_screen "fwm2-listen=3/2" \
  || fail "the guest did not put all five ports into LISTEN" "terminal: screen>"
echo "the guest listens on tcp 7070 7072 7074 and udp 7071 7073"

# ── 검사 6 · 7: 연 TCP 둘 — 파일이 다른 둘 ─────────────────────────────
# 7074는 second.nft가 연다. include glob이 파일 하나에서 멈추지 않는다는 증거다.
expect_tcp_bytes "$TCP_OPEN_PORT" fwm2-tcp-7070-ok 7070
expect_tcp_bytes "$TCP_SECOND_PORT" fwm2-tcp-7074-ok 7074

# ── 검사 8: 안 연 TCP ──────────────────────────────────────────────────
expect_tcp_nothing "$TCP_SHUT_PORT" 7072

# ── 검사 9 · 10: UDP 둘 ────────────────────────────────────────────────
# UDP는 연결이 없어 체인이 읽을 바이트가 없다. 체인이 보내고, 게스트가 받은 것을
# 화면에 낸다(FW-M0 실측 7). 판정 글자는 체인이 보낸 것이라 친 명령에 없다.
# 닫힌 쪽은 열린 쪽과 같은 report 안에서 본다 — 열린 쪽이 닿은 뒤라 "아직 안
# 왔다"가 아니다.
printf 'fwm2-dgram-open\n' > "/dev/udp/127.0.0.1/${UDP_OPEN_PORT}" \
  || fail "could not send to the udp hostfwd port ${UDP_OPEN_PORT}"
printf 'fwm2-dgram-shut\n' > "/dev/udp/127.0.0.1/${UDP_SHUT_PORT}" \
  || fail "could not send to the udp hostfwd port ${UDP_SHUT_PORT}"
sleep 1
echo "=== typing 'bash /config/fwlisten.sh report' ==="
type_fwlisten spc r e p o r t
wait_for_screen "fwm2-udp-open=\[fwm2-dgram-open\]" \
  || fail "the opened udp port 7071 did not get the datagram" "terminal: screen>"
echo "the opened udp port 7071 got fwm2-dgram-open"
wait_for_screen "fwm2-udp-shut=\[\]" \
  || fail "the unopened udp port 7073 got something" "terminal: screen>"
echo "the unopened udp port 7073 got nothing"

# ── 검사 11 · 12: 막힌 쪽 리스너 둘이 아직 아무와도 안 이어졌나 ─────────
# 검사 8 · 10의 빈 값이 "게스트 프로그램이 조용했다"가 아니라 "커널이 안
# 넘겼다"라는 증거다(위 판정의 모양 절).
echo "=== typing 'bash /config/fwlisten.sh count tcp 7072' ==="
type_fwlisten spc c o u n t spc t c p spc 7 0 7 2
wait_for_screen "fwm2-tcp-7072=1" \
  || fail "the listener on tcp 7072 is gone, so something reached it" "terminal: screen>"
echo "the listener on tcp 7072 never saw a connection"
echo "=== typing 'bash /config/fwlisten.sh count udp 7073' ==="
type_fwlisten spc c o u n t spc u d p spc 7 0 7 3
wait_for_screen "fwm2-udp-7073=1" \
  || fail "the listener on udp 7073 got connected, so a datagram reached it" "terminal: screen>"
echo "the listener on udp 7073 never saw a datagram"

stop_guest

echo "=== boot B: the same disk plus a broken nftables.d/broken.nft ==="
LOG="$LOG_B"
boot_guest "$MONITOR_PORT_B" "$DISK_B"

# ── 검사 13: 사람의 파일이 틀려서 첫 nft가 실패했고, 그 이유가 콘솔에 있나 ──
# nft의 stderr는 init의 fd 2(콘솔)로 그대로 간다. 파일 · 행을 짚는 줄이 있어야
# 사람이 고칠 자리를 안다(FW-M0 실측 8).
grep -a "tars-init: nft -f /etc/tars/firewall.nft exited 1" "$LOG" >/dev/null \
  || fail "the first nft did not fail on the broken file" "tars-init: nft" "tars-init: firewall"
grep -a "/config/nftables.d/broken.nft:1:" "$LOG" >/dev/null \
  || fail "nft's error naming broken.nft never reached the console" "Error:" "broken.nft"
echo "nft refused firewall.nft and named broken.nft line 1 on the console"

# ── 검사 14: 갈래 2로 섰나 ─────────────────────────────────────────────
expect_firewall_before_dhcpcd /etc/tars/firewall-base.nft
if grep -a "tars-init: firewall NOT up" "$LOG" >/dev/null; then
  fail "init fell through to the open branch" "tars-init: firewall"
fi

# ── 검사 15: 부팅은 평소대로 끝났다 ─────────────────────────────────────
# 셸 프롬프트는 boot_guest가 이미 봤다. lease까지 받으면 틀린 파일 하나가 기계를
# 네트워크에서 떼어 놓지 않았다는 뜻이다(feedback_boot_never_blocks).
wait_for_log "eth0: leased 10\.0\.2\.15 " 60 \
  || fail "dhcpcd never leased an address after the fallback" ": leased" "dhcpcd"
echo "the boot finished and dhcpcd leased 10.0.2.15 behind the base rules"

# ── 검사 16 · 17: allow.nft가 연 7070도 이제 닫혀 있나 ──────────────────
# allow.nft는 틀린 데가 없다. 그래도 막히는 것이 "사람의 파일 전부를 무시했다"의
# 증거다 — nft -f가 원자적이라 한 파일만 빼고 올리는 일은 없다(실측 8).
echo "=== typing 'bash /config/fwlisten.sh' ==="
type_fwlisten
wait_for_screen "fwm2-listen=3/2" \
  || fail "the guest did not put all five ports into LISTEN" "terminal: screen>"
expect_tcp_nothing "$TCP_OPEN_PORT" 7070
echo "=== typing 'bash /config/fwlisten.sh count tcp 7070' ==="
type_fwlisten spc c o u n t spc t c p spc 7 0 7 0
wait_for_screen "fwm2-tcp-7070=1" \
  || fail "the listener on tcp 7070 is gone, so the fallback let something reach it" "terminal: screen>"
echo "with broken.nft present even allow.nft's 7070 stays shut"

stop_guest

echo "FW chain PASS"
```

- [ ] Step 2: 문법과 진입 검사

```bash
bash -n firewall/check.sh && echo syntax-ok
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./firewall/check.sh && require_no_early_exit_pipe ./firewall/check.sh &&
  require_explicit_nic ./firewall/check.sh && echo ENTRY-OK'
```

`require_explicit_nic`는 `qemu-system-x86_64` 호출의 이어진 줄들에 `-netdev`가 있는지
본다. `boot_guest` 안의 호출도 같은 규칙을 지난다.

- [ ] Step 3: `check.sh`의 `CHAINS` 이름표를 바꾼다

```bash
sd -F '"FW-M1:./firewall/check.sh"' '"FW-M2:./firewall/check.sh"' check.sh
git diff check.sh
```

- [ ] Step 4: 체인을 돌린다 (약 1분)

```bash
S=$SECONDS; docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./firewall/check.sh > /tmp/fw-chain.log 2>&1; echo "exit=$? secs=$((SECONDS-S))"
grep -E "^(FAIL|the |dhcpcd|nft|with|FW chain|=== )" /tmp/fw-chain.log
```

기대: `exit=0`, 검사 17개의 초록 줄과 `FW chain PASS`.

## Task 2 — mutation 둘 (각 약 1분, 커밋하지 않는다)

- [ ] Step 1: `allow.nft`에서 UDP 줄을 빼면 검사 9가 빨갛다

```bash
cp firewall/check.sh /tmp/fw-check.keep
sd -F "printf 'tcp dport 7070 accept\nudp dport 7071 accept\n'" "printf 'tcp dport 7070 accept\n'" firewall/check.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./firewall/check.sh 2>&1 | grep -E "^(FAIL|FW chain)"
cp /tmp/fw-check.keep firewall/check.sh
```

기대: `FAIL: the opened udp port 7071 did not get the datagram`. 앞의 TCP 검사들은
초록이다 — UDP 판정이 TCP 규칙에 기대지 않는다는 증거다.

- [ ] Step 2: 갈래 2를 없애면 부팅 B가 빨갛다

```bash
cp init/src/firewall.zig /tmp/fw-firewall.keep
sd -F 'if (load(BASE_PATH, envp)) {' 'if (false and load(BASE_PATH, envp)) {' init/src/firewall.zig
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./firewall/check.sh 2>&1 | grep -E "^(FAIL|FW chain|nft refused)"
cp /tmp/fw-firewall.keep init/src/firewall.zig
cmp firewall/check.sh /tmp/fw-check.keep && cmp init/src/firewall.zig /tmp/fw-firewall.keep && echo restored
```

기대: `nft refused …`는 초록이고(검사 13) 그 뒤
`FAIL: init did not bring the firewall up from /etc/tars/firewall-base.nft`. 이 mutation의
기계는 갈래 3(열린 채)이다 — 검사 14가 없으면 게이트가 그것을 못 본다.

## Task 3 — 사용자 가이드

- [ ] Step 1: `docs/guides/running-tars.md`의 `### 무엇을 기대하고 무엇을 기대하지 않는가` 앞에 절을 넣는다

````markdown
### 방화벽 — 받을 포트만 연다

`tars.conf`에 `firewall=on`을 적으면 들어오는 연결을 기본으로 버린다. 기본값은
`off`이고, 그때는 게스트가 연 포트를 누구에게나 받는다.

켜진 기계가 받는 것은 셋뿐이다 — 기계 안(`lo`), 이 기계가 먼저 건 연결의 답(DHCP ·
DNS · NTP · `curl`), 그리고 당신이 연 포트. 여는 것은 `/config/nftables.d/` 아래
`.nft` 파일에 nftables 문법으로 한 줄씩 적는다. 파일은 몇 개로 나눠도 된다.

```
# /config/nftables.d/web.nft
tcp dport 8080 accept
udp dport 5353 accept
ip saddr 192.168.0.0/24 tcp dport 22 accept
```

`init`은 네트워크를 올리기 전에 `nft -f /etc/tars/firewall.nft`를 돌리고, 그 파일이
위 디렉터리를 include한다. 고친 것은 재부팅하거나 셸에서 같은 명령을 치면
반영된다. 지금 선 규칙은 `nft list ruleset`으로 본다.

파일이 틀리면 부팅은 막히지 않고 닫힌 채로 끝난다. nft는 규칙을 전부 올리거나
하나도 안 올리므로, 당신의 파일 전부가 빠지고 기본 규칙만 선다 — 틀린 파일 옆의
멀쩡한 파일도 함께 빠진다. 콘솔에 이런 줄이 남는다.

```
/config/nftables.d/web.nft:1:21-21: Error: syntax error, unexpected newline
tars-init: nft -f /etc/tars/firewall.nft exited 1
tars-init: firewall up from /etc/tars/firewall-base.nft without /config/nftables.d (nft said why above)
```

IPv4만 거른다. 커널에 IPv6가 없어서 지금은 구멍이 아니지만, IPv6가 들어오는 날
규칙의 표도 바뀌어야 한다(FW design 위험 6). 나가는 방향은 거르지 않는다.
````

- [ ] Step 2: 같은 파일의 "이 저장소의 어떤 게이트도 실기 부팅을 검증하지 않는다. 열세
  체인이 전부" 문장의 "열세"를 "열다섯"으로 고친다

```bash
sd -F '열세 체인이 전부' '열다섯 체인이 전부' docs/guides/running-tars.md
git diff --stat docs/guides/running-tars.md
git diff docs/guides/running-tars.md | grep '^-[^-]'
```

기대: 지운 줄은 그 한 줄뿐이다.

## Task 4 — 루트 게이트 (약 45~50분)

- [ ] Step 1: 배경에서 돌린다

```bash
S=$(date +%s); docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/fw-gate.log 2>&1; echo "exit=$? secs=$(( $(date +%s) - S ))"
```

완료 알림이 실행 직후에 오는 일이 있었다(HANDOFF). 알림이 오면
`pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 본다.

- [ ] Step 2: 결과를 본다

```bash
grep -E "PASS|FAIL" /tmp/fw-gate.log | tail -20
grep -c "^FAIL" /tmp/fw-gate.log
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`, `FW-M2 PASS`,
`FAIL`로 시작하는 줄 0.

## Task 5 — FW를 닫는다

- [ ] Step 1: design — "FW-M2가 실행으로 증명한 것"(실측 15~)과 `Status: 끝났다(날짜) —
  M0~M2, 실측 1~N. 열다섯번째 체인 firewall/check.sh(부팅 둘, 검사 열일곱)`.
- [ ] Step 2: `docs/decisions/project_firewall.md`를 새로 쓰고 `MEMORY.md`의 프로젝트 목록
  끝에 한 줄. 다음 사람이 알아야 할 것 — 기본 off · 켜면 닫힘 · `nftables.d` · `nft -f`의
  원자성과 갈래 2 · `table ip`와 IPv6 · 막힌 TCP는 SLIRP이 안 끊는다 · 16진수는 printf ·
  UDP 리스너의 "아직 안 이어졌다".
- [ ] Step 3: `CLAUDE.md`의 완료 표 끝에 한 줄.

```markdown
| Firewall (FW-M0~M2) | 2026-09-27 | `tars.conf`의 `firewall=on`이 들어오는 것을 기본으로 버리고, 사람은 `/config/nftables.d/*.nft`에 연다. `init`은 `net.bringUp` 앞에서 `nft -f`를 기다리고, 사람의 파일이 틀리면 기본 규칙만 올린다. 열다섯번째 체인 `firewall/check.sh` |
```

- [ ] Step 4: `HANDOFF.md` 맨 위를 "FW가 닫혔다 · 다음은 새 서브프로젝트를 고른다"로.
- [ ] Step 5: 커밋

```bash
git status --short
git diff --stat
git diff | grep '^-[^-]'
git add firewall/check.sh check.sh docs/guides/running-tars.md \
        docs/specs/2026-09-27-tars-firewall-design.md \
        docs/plans/2026-09-27-tars-firewall-fw-m2.md \
        docs/decisions/project_firewall.md MEMORY.md CLAUDE.md HANDOFF.md
git status --short
git commit -m "Close FW-M2: udp, ports across files and the broken-file boot"
```

## 이 milestone이 끝난 자리

FW가 닫힌다. 남은 후보는 HANDOFF의 목록(패키지 매니저 · 부팅 때 뜨는 서비스 · IPv6)이다.
IPv6를 고르면 design 위험 6이 첫 확인이다.
