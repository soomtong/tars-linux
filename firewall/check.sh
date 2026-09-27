#!/usr/bin/env bash
# FW 체인. 방화벽이 켜진 기계가 들어오는 TCP를 가르는가를 본다.
#
# 부팅 하나다. 설정 디스크가 셋을 싣는다.
#   tars.conf           net=dhcp · firewall=on
#   nftables.d/allow.nft  tcp dport 7070 accept — 사람이 연 포트 하나
#   fwlisten.sh         게스트에서 리스너 둘(7070 · 7072)을 띄우고 센다
#
# 판정의 재료(어느 포트를 열었나)는 이 파일의 ALLOWED · BLOCKED이고, 판정 대상은
# 게스트 커널에 선 규칙이다. 둘을 같은 파일로 두지 않는다(LB 실측 17).
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
MONITOR_PORT=45474
ALLOWED_PORT=45475     # → 게스트 7070, allow.nft가 연다
BLOCKED_PORT=45476     # → 게스트 7072, 아무도 안 연다
GUEST_ALLOWED=7070
GUEST_BLOCKED=7072

DISK="${REPO_ROOT}/out/firewall.img"
LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$LOG"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  echo "--- markers ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: firewall" \
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

# ── 디스크 ───────────────────────────────────────────────────────────
# debugfs가 마운트 없이 ext2에 쓴다(project_seeding_a_config_disk).
mkdir -p "${REPO_ROOT}/out"
SEED="$(mktemp -d)"
printf 'net=dhcp\nfirewall=on\n' > "$SEED/tars.conf"
printf 'tcp dport %s accept\n' "$GUEST_ALLOWED" > "$SEED/allow.nft"
cat > "$SEED/fwlisten.sh" <<'EOF'
#!/bin/bash
# FW 체인이 심는다. 인자가 없으면 리스너 둘을 띄우고 센다. count면 7072가 아직
# 듣고 있는지만 센다. 판정 글자(fwm1-…=)는 출력에만 생기고 친 명령에는 없다.
# /proc/net/tcp는 포트를 16진수 넉 자로 적는다. 손으로 옮기지 않고 printf가
# 바꾼다 — FW-M0과 M1 첫 판이 7070을 1BAE로 잘못 옮겨 0을 셌다(실측 9 · 10).
listening() { grep -c ":$(printf '%04X' "$1") 00000000:0000 0A" /proc/net/tcp; }
if [ "${1:-}" = count ]; then
  echo "fwm1-still=$(listening 7072)"
  exit 0
fi
printf 'fwm1-tcp-a\n' | nc -l -p 7070 >/dev/null 2>&1 &
printf 'fwm1-tcp-c\n' | nc -l -p 7072 >/dev/null 2>&1 &
n=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  n=$(( $(listening 7070) + $(listening 7072) ))
  [ "$n" -ge 2 ] && break
  sleep 0.3
done
echo "fwm1-listen=$n"
EOF
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-fw "$DISK"
debugfs -w -R "write $SEED/tars.conf tars.conf" "$DISK" 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "mkdir nftables.d" "$DISK" 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "write $SEED/allow.nft nftables.d/allow.nft" "$DISK" 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "write $SEED/fwlisten.sh fwlisten.sh" "$DISK" 2>&1 | grep -v '^debugfs' || true
rm -rf "$SEED"

echo "=== boot: net=dhcp firewall=on, port ${GUEST_ALLOWED} opened in nftables.d ==="
qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${ALLOWED_PORT}-10.0.2.15:${GUEST_ALLOWED},hostfwd=tcp:127.0.0.1:${BLOCKED_PORT}-10.0.2.15:${GUEST_BLOCKED}" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

wait_for_log "terminal: screen>" 120 || fail "terminal never rendered a prompt"

# ── 검사 2: 설정이 firewall=on으로 읽혔나 ─────────────────────────────
grep -aE "tars-init: config shell=.* net=dhcp .* firewall=on" "$LOG" >/dev/null \
  || fail "the config disk did not turn the firewall on" "tars-init: config shell="
echo "the guest read net=dhcp and firewall=on off the config disk"

# ── 검사 3: 갈래 1로 섰나, 그리고 dhcpcd보다 먼저인가 ───────────────────
# 갈래 2 · 3의 줄이 있으면 그 자체로 빨갛다 — 이 부팅의 파일은 틀린 데가 없다.
# 순서는 줄 번호로 본다. design 결정 5의 "규칙이 서기 전에 주소가 붙는 틈이
# 없다"를 로그에서 읽는 방법이 이것이다.
FW_LINE="$(grep -an "tars-init: firewall up from /etc/tars/firewall.nft," "$LOG" | head -1 | cut -d: -f1)"
[ -n "$FW_LINE" ] || fail "init did not bring the firewall up from firewall.nft" "tars-init: firewall" "tars-init: nft"
DHCPCD_LINE="$(grep -an "tars-init: started dhcpcd (pid" "$LOG" | head -1 | cut -d: -f1)"
[ -n "$DHCPCD_LINE" ] || fail "init did not start dhcpcd"
[ "$FW_LINE" -lt "$DHCPCD_LINE" ] \
  || fail "dhcpcd started (line ${DHCPCD_LINE}) before the firewall was up (line ${FW_LINE})"
echo "the firewall came up from firewall.nft before dhcpcd started"

# ── 검사 4: drop 아래에서 lease를 받나 ─────────────────────────────────
# FW-M0 실측 5. 받는 것을 기본으로 버리는 기계가 DHCP의 답까지 버리면 여기서
# 멈춘다.
wait_for_log "eth0: leased 10\.0\.2\.15 " 60 \
  || fail "dhcpcd never leased an address under the firewall" ": leased" "dhcpcd"
echo "dhcpcd leased 10.0.2.15 under policy drop"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor"

# ── 검사 5: 게스트가 두 포트를 다 듣나 ─────────────────────────────────
# 이 검사가 있어야 아래 검사 7의 0바이트가 "방화벽이 버렸다"로 읽힌다. 없으면
# "게스트가 안 들었다"와 같은 모양이다.
echo "=== typing 'bash /config/fwlisten.sh' ==="
type_keys b a s h spc slash c o n f i g slash f w l i s t e n dot s h ret
wait_for_screen "fwm1-listen=2" \
  || fail "the guest did not put both ${GUEST_ALLOWED} and ${GUEST_BLOCKED} into LISTEN" "terminal: screen>"
echo "the guest listens on ${GUEST_ALLOWED} and ${GUEST_BLOCKED}"

# ── 검사 6: 연 포트에서 바이트가 오나 ──────────────────────────────────
# rc로 판정하지 않는다(IN 실측 4 — SLIRP은 누구에게나 connect를 준다). 판정은
# 읽은 글자다. fd 5인 이유는 net 체인과 같다(3이 monitor다).
GOT=""
for _ in $(seq 1 10); do
  if exec 5<>"/dev/tcp/127.0.0.1/${ALLOWED_PORT}"; then
    read -r -t 5 GOT <&5 || true
    exec 5<&-
    exec 5>&-
    [ "$GOT" = "fwm1-tcp-a" ] && break
  fi
  sleep 0.2
done
[ "$GOT" = "fwm1-tcp-a" ] \
  || fail "nothing came through the opened port ${GUEST_ALLOWED} (got: [${GOT}])" "terminal: screen>"
echo "the opened port ${GUEST_ALLOWED} let fwm1-tcp-a through"

# ── 검사 7: 안 연 포트에서는 안 오나 ───────────────────────────────────
# 이 체인의 가운데다. 게스트는 7072를 듣고 있는데(검사 5) 규칙이 SYN을 버린다.
# SLIRP은 체인 쪽 연결을 안 끊으므로 read가 타임아웃을 꽉 쓴다(FW-M0 실측 6 —
# 5초를 줬더니 5,012ms). 2초는 양성의 22ms와 멀고, 게이트가 세 번 도는 값이다.
#
# 붙는 것을 따로 본다. 안 보면 hostfwd가 사라진 날에도 초록이다(IN 검사 16과
# 같은 자리).
NEG_CONNECTED=0
NEG_GOT=""
if exec 5<>"/dev/tcp/127.0.0.1/${BLOCKED_PORT}"; then
  NEG_CONNECTED=1
  read -r -t 2 NEG_GOT <&5 || true
  exec 5<&-
  exec 5>&-
fi
[ "$NEG_CONNECTED" = "1" ] \
  || fail "the negative check could not even connect — the hostfwd port ${BLOCKED_PORT} is gone"
[ -z "$NEG_GOT" ] \
  || fail "the unopened port ${GUEST_BLOCKED} let something through (got: [${NEG_GOT}])" "tars-init: firewall"
echo "the unopened port ${GUEST_BLOCKED} let nothing through"

# ── 검사 8: 막힌 쪽 리스너가 아직 살아 있나 ────────────────────────────
# 한 번만 사는 리스너라(IN 결정 7) 연결을 받았으면 죽었다. 7072가 아직 LISTEN이면
# 게스트의 nc까지 연결이 한 번도 안 닿았다는 뜻이다 — 검사 7의 빈 값이 "nc가
# 아무것도 안 보냈다"가 아니라 "nc까지 안 왔다"라는 증거다.
echo "=== typing 'bash /config/fwlisten.sh count' ==="
type_keys b a s h spc slash c o n f i g slash f w l i s t e n dot s h spc c o u n t ret
wait_for_screen "fwm1-still=1" \
  || fail "the listener on ${GUEST_BLOCKED} is gone, so something reached it" "terminal: screen>"
echo "the listener on ${GUEST_BLOCKED} never saw a connection"

echo "system_powerdown" >&3
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

echo "FW chain PASS"
