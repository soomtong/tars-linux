#!/usr/bin/env bash
# SV 체인. init이 /config/services.d의 실행 파일을 읽어 띄우고 감독하는가를 본다.
#
# 부팅 하나다. 설정 디스크가 싣는 것.
#   tars.conf                   net=dhcp — a-greet에 바깥에서 붙으려고
#   services.d/a-greet          붙는 사람에게 자기 $0과 PATH를 한 줄 보낸다
#   services.d/b-die            곧바로 죽는다 — 셋 뜨고 포기된다
#   services.d/c-noexec         실행 비트가 없다 — 사전 확인이 뺀다
#   services.d/d-link           → /config/linked.sh. 세션과 stdin을 콘솔에 적고 잔다
#   services.d/.hidden          숨긴 이름 — 조용히 무시된다
#
# services.d에 쓰는 순서를 이름의 역순으로 둔다. ext2의 getdents는 대개 만든
# 순서라, init이 정렬을 안 하면 시작 순서 검사가 빨갛다.
#
# 우리 코드는 init/src/services.zig(고르기)와 main.zig의 감독 루프(띄우기)다.
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

# services_test가 부팅 전에 0.1초로 고르기를 본다 — 여덟 한도와 끊어진 링크는
# 부팅으로 재기에 비싸다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
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

# 포트. 45474~45480은 FW가 쓴다.
MONITOR_PORT=45481
GREET_PORT=45482   # → 게스트 7000, a-greet가 듣는다
HOSTFWD="hostfwd=tcp:127.0.0.1:${GREET_PORT}-10.0.2.15:7000"

DISK="${REPO_ROOT}/out/service.img"
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
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "services from /config/services.d" \
    "tars-init: started console shell" \
    "tars-init: started service" \
    ": leased" \
    "terminal: screen>"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  local pattern
  for pattern in "$@"; do
    grep -a "$pattern" "$LOG" | head -5 | sed 's/^/  /' || true
  done
  echo "--- tars-init lines ---"
  grep -a "tars-init:" "$LOG" | tail -n 30 || true
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
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

# 패턴의 첫 줄 번호. 없으면 빈 값.
line_of() {
  grep -anE "$1" "$LOG" | head -1 | cut -d: -f1
}

# ── 디스크 ────────────────────────────────────────────────────────────
# debugfs의 write는 원본의 모드를 따른다(SV-M0 실측 2) — 실행 비트는 호스트의
# chmod가 정한다. 링크는 debugfs의 symlink다.
mkdir -p "${REPO_ROOT}/out"
SEED="$(mktemp -d)"
printf 'net=dhcp\n' > "$SEED/tars.conf"
cat > "$SEED/a-greet" <<'EOF'
#!/bin/sh
# 판정 글자(sv-greet)는 붙은 쪽이 읽는 바이트에만 있다. 매 연결마다 한 줄.
while true; do
  printf 'sv-greet %s %s\n' "$0" "$PATH" | nc -l -p 7000 > /dev/null 2>&1
done
EOF
printf '#!/bin/sh\nexit 3\n' > "$SEED/b-die"
printf '#!/bin/sh\necho sv-noexec-ran\n' > "$SEED/c-noexec"
printf '#!/bin/sh\necho sv-hidden-ran\n' > "$SEED/hidden"
cat > "$SEED/linked.sh" <<'EOF'
#!/bin/sh
# d-link로 불린다. shebang이 /bin/bash면 execve가 ENOENT다 — 게스트의 /bin에는
# sh 하나만 산다(make_initrd.sh:81, SV-M1 첫 실행이 그렇게 빨갛다).
# $0이 링크의 경로다(SV-M0 실측 3). stdin이 /dev/null이면 read가
# 곧바로 EOF(rc 1)이고, 콘솔이면 1초를 채우고 142 언저리다. sid가 pid와 같으면
# setsid가 됐다.
read -r -t 1 _; rc=$?
printf 'sv-linked %s sid=%s pid=%s stdin-rc=%s\n' "$0" "$(ps -o sid= -p $$ | tr -d ' ')" "$$" "$rc"
exec sleep 100000
EOF
chmod 755 "$SEED/a-greet" "$SEED/b-die" "$SEED/hidden" "$SEED/linked.sh"
chmod 644 "$SEED/c-noexec"

rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-sv "$DISK"
dbg() { debugfs -w -R "$1" "$DISK" 2>&1 | grep -v '^debugfs' || true; }
dbg "write $SEED/tars.conf tars.conf"
dbg "write $SEED/linked.sh linked.sh"
dbg "mkdir services.d"
dbg "write $SEED/hidden services.d/.hidden"
dbg "symlink services.d/d-link /config/linked.sh"
dbg "write $SEED/c-noexec services.d/c-noexec"
dbg "write $SEED/b-die services.d/b-die"
dbg "write $SEED/a-greet services.d/a-greet"
rm -rf "$SEED"

echo "=== boot: net=dhcp, services.d with a-greet b-die c-noexec d-link .hidden ==="
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
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

wait_for_log "terminal: screen>" 120 || fail "terminal never rendered a prompt"
connected=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
  sleep 0.5
done
[ "$connected" = "1" ] || fail "could not connect to the QEMU monitor"

# ── 검사 1: 셋을 골랐다 ────────────────────────────────────────────────
# a-greet · b-die · d-link. c-noexec는 사전 확인이, .hidden은 이름이 뺐다.
grep -a "tars-init: 3 services from /config/services.d" "$LOG" >/dev/null \
  || fail "init did not pick exactly three services" "services from" "tars-init: service"
echo "init picked three services from /config/services.d"

# ── 검사 2: 실행 비트 없는 것은 한 줄로 빠졌고 한 번도 안 떴다 ──────────────
grep -a "tars-init: service c-noexec is not an executable file, skipped" "$LOG" >/dev/null \
  || fail "c-noexec was not skipped by the pre-check" "c-noexec"
if grep -a "started service c-noexec" "$LOG" >/dev/null; then
  fail "c-noexec was started despite having no execute bit" "c-noexec"
fi
echo "c-noexec was skipped before it could fail"

# ── 검사 3: 숨긴 이름은 흔적이 없다 ─────────────────────────────────────
if grep -aE "service \.hidden|sv-hidden-ran" "$LOG" >/dev/null; then
  fail ".hidden was looked at" ".hidden" "sv-hidden-ran"
fi
echo ".hidden left no trace"

# ── 검사 4: 이름순으로, 콘솔 셸 뒤에 떴다 ──────────────────────────────
# 디스크에는 역순으로 썼다. 정렬이 빠지면 여기가 빨갛다.
SHELL_LINE="$(line_of 'tars-init: started console shell')"
A_LINE="$(line_of 'tars-init: started service a-greet \(pid [0-9]+, /config/services.d/a-greet\)')"
B_LINE="$(line_of 'tars-init: started service b-die ')"
D_LINE="$(line_of 'tars-init: started service d-link ')"
[ -n "$SHELL_LINE" ] && [ -n "$A_LINE" ] && [ -n "$B_LINE" ] && [ -n "$D_LINE" ] \
  || fail "a start line is missing (shell=${SHELL_LINE} a=${A_LINE} b=${B_LINE} d=${D_LINE})" "tars-init: started"
[ "$SHELL_LINE" -lt "$A_LINE" ] && [ "$A_LINE" -lt "$B_LINE" ] && [ "$B_LINE" -lt "$D_LINE" ] \
  || fail "services did not start in name order after the console shell (shell=${SHELL_LINE} a=${A_LINE} b=${B_LINE} d=${D_LINE})" "tars-init: started"
echo "a-greet, b-die, d-link started in name order after the console shell"

# ── 검사 5: 곧바로 죽는 서비스는 셋 뜨고 포기된다 ────────────────────────
# 셋이라는 수가 MAX_FAST_RESTARTS 정책이다 — boot 체인이 terminal에 대해 세는
# 것과 같은 수다.
wait_for_log "tars-init: giving up on service b-die after 3 fast exits" 30 \
  || fail "b-die was never given up on" "b-die"
B_STARTS="$(grep -ac "tars-init: started service b-die " "$LOG" || true)"
[ "$B_STARTS" = "3" ] || fail "b-die started ${B_STARTS} times, want 3" "b-die"
echo "b-die started three times and was given up on"

# ── 검사 6: 링크로 켠 서비스가 제 세션에 있고 stdin이 끊겨 있다 ──────────────
wait_for_log "sv-linked /config/services.d/d-link sid=" 30 \
  || fail "d-link never reported" "d-link" "sv-linked"
LINKED="$(grep -aoE "sv-linked /config/services.d/d-link sid=[0-9]+ pid=[0-9]+ stdin-rc=[0-9]+" "$LOG" | head -1)"
SID="$(sed -E 's/.* sid=([0-9]+) .*/\1/' <<<"$LINKED")"
PID="$(sed -E 's/.* pid=([0-9]+) .*/\1/' <<<"$LINKED")"
RC="$(sed -E 's/.* stdin-rc=([0-9]+)$/\1/' <<<"$LINKED")"
[ "$SID" = "$PID" ] || fail "d-link is not its own session leader (${LINKED})" "sv-linked"
[ "$RC" = "1" ] || fail "d-link's stdin is not /dev/null (${LINKED})" "sv-linked"
echo "d-link ran through its link, leads its own session and reads EOF on stdin"

# ── 검사 7: 서비스가 init의 env를 받고 바깥에서 닿는다 ─────────────────────
# PATH가 init의 것(/usr/bin:/bin)이면 envp가 서비스까지 왔다.
wait_for_log "eth0: leased 10\.0\.2\.15 " 60 \
  || fail "dhcpcd never leased an address" ": leased" "dhcpcd"
GOT=""
for _ in $(seq 1 20); do
  if exec 5<>"/dev/tcp/127.0.0.1/${GREET_PORT}"; then
    read -r -t 5 GOT <&5 || true
    exec 5<&-
    exec 5>&-
  fi
  [ -n "$GOT" ] && break
  sleep 0.5
done
[ "$GOT" = "sv-greet /config/services.d/a-greet /usr/bin:/bin" ] \
  || fail "a-greet did not answer as expected (got: [${GOT}])" "a-greet"
echo "a-greet answered from outside with init's PATH"

# ── 검사 8: 살아 있는 서비스 둘은 한 번도 안 죽었고, 콘솔 셸도 그대로다 ───────
for who in "service a-greet" "service d-link" "console shell"; do
  if grep -aE "tars-init: ${who} (exited|killed)" "$LOG" >/dev/null; then
    fail "${who} died during the boot" "tars-init: ${who}"
  fi
done
echo "a-greet, d-link and the console shell stayed up"

echo "system_powerdown" >&3
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""
exec 3<&-
exec 3>&-

echo "SV chain PASS"
