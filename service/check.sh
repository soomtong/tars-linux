#!/usr/bin/env bash
# SV 체인. init이 /config/services.d의 실행 파일을 읽어 띄우고 감독하는가를 본다.
#
# 부팅 셋이다. 부팅 A의 설정 디스크가 싣는 것.
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
# 부팅 B · C는 다른 디스크 하나를 같이 쓴다(SV-M2). 사람이 할 일 둘 — 템플릿으로 가는
# 링크 services.d/sshd와 공개 키 ssh/authorized_keys — 과 tars.conf의 net=dhcp ·
# shell=zsh · firewall=on. B는 ssh.nft 없이 떠서 방화벽이 22를 막는 것과 첫 부팅의
# 호스트 키를, C는 ssh.nft를 더한 같은 디스크로 떠서 키가 그대로인 것과 로그인된
# 세션이 콘솔과 같은 것을 본다.
#
# 부팅 D(CT-M2)는 C 뒤의 같은 디스크에 서비스 셋(sleeper · stubborn · flaky)을 더해
# 뜨고, ssh ControlMaster 연결 하나 위로 tars-service를 친다. 그 연결은 제 세션을 가진
# sshd-session이 들고 있어 sshd를 멈춰도 산다(CT-M0 실측 4) — stop sshd 뒤에 같은
# 연결로 start sshd를 친다.
#
# 우리 코드는 init/src/services.zig(고르기) · main.zig의 감독 루프(띄우기)와
# init/src/control.zig · service_cli.zig(멈추고 다시 띄우기)다.
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

# ── 부팅 B · C: sshd ──────────────────────────────────────────────────
MONITOR_PORT_B=45483
MONITOR_PORT_C=45484
SSH_PORT=45485     # → 게스트 22
SSH_DISK="${REPO_ROOT}/out/service-ssh.img"
KEYS="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N '' -C sv-good -f "$KEYS/good"
ssh-keygen -q -t ed25519 -N '' -C sv-bad -f "$KEYS/bad"
SSHO=(-p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes
      -o StrictHostKeyChecking=no -o UserKnownHostsFile="$KEYS/known_hosts")

# 사람이 할 일 둘을 그대로 한다 — 링크 하나와 공개 키 하나. authorized_keys의
# 모드는 debugfs write가 원본을 따르므로 여기서 600으로 둔다(SV-M0 실측 2).
SEED="$(mktemp -d)"
printf 'net=dhcp\nshell=zsh\nfirewall=on\n' > "$SEED/tars.conf"
cp "$KEYS/good.pub" "$SEED/authorized_keys"; chmod 600 "$SEED/authorized_keys"
printf 'tcp dport 22 accept\n' > "$SEED/ssh.nft"
rm -f "$SSH_DISK"; truncate -s 16M "$SSH_DISK"
mkfs.ext2 -F -q -m 0 -L tars-sv "$SSH_DISK"
sdbg() { debugfs -w -R "$1" "$SSH_DISK" 2>&1 | grep -v '^debugfs' || true; }
sdbg "write $SEED/tars.conf tars.conf"
sdbg "mkdir services.d"
sdbg "symlink services.d/sshd /etc/tars/services/sshd"
sdbg "mkdir ssh"
sdbg "sif ssh mode 040700"
sdbg "write $SEED/authorized_keys ssh/authorized_keys"
sdbg "mkdir nftables.d"

boot_ssh() {  # $1 = monitor 포트
  qemu-system-x86_64 \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -display none \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-10.0.2.15:22" \
    -device virtio-net-pci,netdev=n0 \
    -drive file="$SSH_DISK",if=virtio,format=raw \
    -serial file:"$LOG" \
    -monitor tcp:127.0.0.1:$1,server,nowait \
    -no-reboot &
  QEMU_PID=$!
  wait_for_log "terminal: screen>" 120 || fail "terminal never rendered a prompt"
  local ok=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/$1"; then ok=1; break; fi
    sleep 0.5
  done
  [ "$ok" = "1" ] || fail "could not connect to the QEMU monitor"
  wait_for_log "eth0: leased 10\.0\.2\.15 " 60 || fail "dhcpcd never leased an address" ": leased"
}

stop_ssh() {
  echo "system_powerdown" >&3
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
  exec 3<&-
  exec 3>&-
}

echo "=== boot B: sshd linked, firewall=on without ssh.nft ==="
rm -f "$LOG"   # 부팅 A의 로그. cleanup은 마지막 LOG 하나만 지운다
LOG="$(mktemp)"
boot_ssh "$MONITOR_PORT_B"

# ── 검사 9: init이 로그인 셸과 ssh env를 썼다 ───────────────────────────
grep -a "tars-init: login shell /usr/bin/zsh, ssh env in /etc/ssh/sshd_config.d/tars-env.conf" "$LOG" >/dev/null \
  || fail "init did not write the login shell and the ssh env" "tars-init: login shell"
echo "init set root's shell to zsh and wrote sshd's env"

# ── 검사 10: 링크 하나로 sshd가 떴고, 첫 부팅이라 키를 구웠다 ──────────────
wait_for_log "Server listening on 0\.0\.0\.0 port 22\." 30 \
  || fail "sshd never listened" "service sshd" "sshd:"
grep -a "sshd: generated a host key in /config/ssh" "$LOG" >/dev/null \
  || fail "the template did not generate a host key on the first boot" "sshd:"
FP_B="$(grep -aoE "sshd: host key 256 SHA256:[A-Za-z0-9+/]+" "$LOG" | head -1 | sed 's/.*SHA256:/SHA256:/')"
[ -n "$FP_B" ] || fail "the template did not print the host key" "sshd:"
echo "the linked template started sshd and generated ${FP_B}"

# ── 검사 11: 방화벽이 22를 막는다 ────────────────────────────────────────
# ssh.nft가 없으므로 등록한 키로도 아무것도 안 온다. SLIRP은 막힌 연결을 안 끊으므로
# (FW-M0 실측 6) ssh는 배너를 기다리다 ConnectTimeout에 걸린다.
if timeout 15 ssh "${SSHO[@]}" -i "$KEYS/good" root@127.0.0.1 true >/dev/null 2>&1; then
  fail "firewall=on without ssh.nft still let an ssh login through"
fi
echo "with firewall=on and no ssh.nft, port 22 stayed shut"
stop_ssh
B_LOG="$LOG"

sdbg "write $SEED/ssh.nft nftables.d/ssh.nft"
rm -rf "$SEED"

echo "=== boot C: the same disk plus nftables.d/ssh.nft ==="
LOG="$(mktemp)"
boot_ssh "$MONITOR_PORT_C"
wait_for_log "Server listening on 0\.0\.0\.0 port 22\." 30 || fail "sshd never listened" "sshd:"

# ── 검사 12: 키를 다시 안 구웠고 지문이 같다 ────────────────────────────
if grep -a "sshd: generated a host key" "$LOG" >/dev/null; then
  fail "the host key was generated again on the second boot" "sshd:"
fi
FP_C="$(grep -aoE "sshd: host key 256 SHA256:[A-Za-z0-9+/]+" "$LOG" | head -1 | sed 's/.*SHA256:/SHA256:/')"
[ "$FP_C" = "$FP_B" ] || fail "the host key changed across boots (${FP_B} -> ${FP_C})" "sshd:"
SCAN="$(ssh-keyscan -p "$SSH_PORT" -t ed25519 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print $2}')"
[ "$SCAN" = "$FP_B" ] || fail "ssh-keyscan saw ${SCAN}, the guest printed ${FP_B}"
echo "the host key survived the reboot and is what the client sees"

# ── 검사 13: 등록한 키로 로그인되고 세션이 콘솔과 같다 ──────────────────────
GOT="$(ssh "${SSHO[@]}" -i "$KEYS/good" root@127.0.0.1 \
  'printf "sv-ssh %s|%s|%s|%s\n" "$0" "$SHELL" "$PATH" "$HISTFILE"' 2>/dev/null)"
[ "$GOT" = "sv-ssh zsh|/usr/bin/zsh|/usr/bin:/bin|/config/zsh_history" ] \
  || fail "the ssh session does not match the console (got: [${GOT}])" "sshd" "Accepted"
echo "a registered key logged in to zsh with init's PATH and history"

# ── 검사 14: 모르는 키는 거절된다 ─────────────────────────────────────────
ssh "${SSHO[@]}" -i "$KEYS/bad" root@127.0.0.1 true >/dev/null 2>&1
RC=$?
[ "$RC" = "255" ] || fail "an unregistered key got rc ${RC}, want 255"
echo "an unregistered key was refused"

# ── 검사 15: Ghostty의 TERM에서 less가 안 멈춘다 ──────────────────────────
OUT="$(TERM=xterm-ghostty timeout 15 ssh "${SSHO[@]}" -i "$KEYS/good" -tt root@127.0.0.1 \
  'echo x | less -FX; echo "sv-less-rc=$?"' 2>&1 < /dev/null | tr -d '\r')"
case "$OUT" in
  *"not fully functional"*) fail "less still warns under TERM=xterm-ghostty" ;;
  *"sv-less-rc=0"*) ;;
  *) fail "less under TERM=xterm-ghostty did not finish (got: [${OUT}])" ;;
esac
echo "less ran under TERM=xterm-ghostty without a warning"
stop_ssh

# ── 부팅 D: tars-service (CT-M2) ─────────────────────────────────────
MONITOR_PORT_D=45486
DSEED="$(mktemp -d)"
cat > "$DSEED/sleeper" <<'EOF'
#!/bin/sh
# exec 없이 sleep을 자식으로 둔다. 리더에게만 보내면 sleep이 고아로 남는다(CT-M0 실측 5).
sleep 100000
EOF
cat > "$DSEED/stubborn" <<'EOF'
#!/bin/sh
# SIGTERM을 무시한다. 무시는 exec를 넘어 sleep에도 간다.
trap '' TERM
while :; do sleep 1; done
EOF
cat > "$DSEED/flaky" <<'EOF'
#!/bin/sh
# 표지 파일이 없으면 곧바로 죽는다 — 셋 뜨고 포기된다. 사람이 만든 뒤 start하면 산다.
[ -e /run/flaky-ok ] || exit 3
exec sleep 100000
EOF
chmod 755 "$DSEED/sleeper" "$DSEED/stubborn" "$DSEED/flaky"
for s in sleeper stubborn flaky; do sdbg "write $DSEED/$s services.d/$s"; done
rm -rf "$DSEED"

echo "=== boot D: the same disk plus sleeper, stubborn and flaky; tars-service over ssh ==="
LOG="$(mktemp)"
boot_ssh "$MONITOR_PORT_D"
wait_for_log "Server listening on 0\.0\.0\.0 port 22\." 30 || fail "sshd never listened" "sshd:"

CTL="$KEYS/ctl"
ssh "${SSHO[@]}" -i "$KEYS/good" -o ControlMaster=yes -o ControlPath="$CTL" -o ControlPersist=yes \
  -fN root@127.0.0.1 || fail "could not open the ssh control connection" "sshd"
# 연결 위로 tars-service를 친다. 출력은 OUT, 종료 코드는 RC. 인자는 원격 셸이 가른다 —
# 공백 든 이름은 따옴표째 넘긴다.
ts() {
  OUT="$(ssh "${SSHO[@]}" -o ControlPath="$CTL" root@127.0.0.1 "tars-service $*" 2>&1)"
  RC=$?
}
on_guest() { ssh "${SSHO[@]}" -o ControlPath="$CTL" root@127.0.0.1 "$@" 2>/dev/null; }
fresh_ssh() { ssh "${SSHO[@]}" -i "$KEYS/good" -o ControlPath=none root@127.0.0.1 true >/dev/null 2>&1; }
# 마지막 줄(클라이언트가 기다린 끝의 status 한 줄)의 pid.
last_pid() { tail -1 <<<"$OUT" | sed -nE 's/.* pid ([0-9]+).*/\1/p'; }

# ── 검사 16: 통로가 섰다 ─────────────────────────────────────────────────
grep -a "tars-init: control socket /run/tars/init.sock" "$LOG" >/dev/null \
  || fail "init did not open the control socket" "control"
echo "init opened /run/tars/init.sock"

# ── 검사 17: status가 전부를 보인다 ──────────────────────────────────────
wait_for_log "tars-init: giving up on service flaky after 3 fast exits" 30 \
  || fail "flaky was never given up on" "flaky"
ts status
[ "$RC" = "0" ] || fail "status gave rc ${RC} (${OUT})"
for want in '^terminal +running +pid [0-9]+' '^console shell +running +pid [0-9]+' \
            '^service flaky +given up$' '^service sleeper +running +pid [0-9]+' \
            '^service sshd +running +pid [0-9]+' '^service stubborn +running +pid [0-9]+'; do
  grep -qE "$want" <<<"$OUT" || fail "status has no line like /${want}/ (got: [${OUT}])"
done
echo "status showed the terminal, the console shell and four services, flaky given up"

# ── 검사 18: stop이 그룹을 멈춘다 ────────────────────────────────────────
ts stop sleeper
[ "$RC" = "0" ] || fail "stop sleeper gave rc ${RC} (${OUT})" "sleeper"
tail -1 <<<"$OUT" | grep -E '^service sleeper +stopped$' >/dev/null || fail "stop sleeper did not end stopped (${OUT})"
ORPHANS="$(on_guest 'ps -eo ppid=,comm=' | grep -cE '^ *1 sleep$')"
[ "$ORPHANS" = "0" ] || fail "stop sleeper left ${ORPHANS} sleep under pid 1" "sleeper"
grep -a "tars-init: service sleeper stopped on request" "$LOG" >/dev/null \
  || fail "init did not log the stop" "sleeper"
echo "stop sleeper ended stopped and took its child sleep with it"

# ── 검사 19: 멈춘 것은 되살아나지 않는다 ───────────────────────────────────
sleep 3
ts status sleeper
grep -qE '^service sleeper +stopped$' <<<"$OUT" || fail "sleeper did not stay stopped (${OUT})" "sleeper"
N="$(grep -ac "tars-init: started service sleeper " "$LOG")"
[ "$N" = "1" ] || fail "sleeper started ${N} times, want 1" "sleeper"
echo "sleeper stayed stopped"

# ── 검사 20: start가 다시 띄운다 ────────────────────────────────────────
ts start sleeper
[ "$RC" = "0" ] || fail "start sleeper gave rc ${RC} (${OUT})" "sleeper"
tail -1 <<<"$OUT" | grep -E '^service sleeper +running +pid [0-9]+$' >/dev/null || fail "start sleeper did not end running (${OUT})"
echo "start sleeper brought it back"

# ── 검사 21: restart는 빨리 죽음으로 세지 않는다 ──────────────────────────
# 넷이다 — 셋이면 세는 쪽으로 틀려도 포기 직전에서 멈춘다(CT-M0 실측 6).
PREV=""
for i in 1 2 3 4; do
  ts restart sshd
  [ "$RC" = "0" ] || fail "restart sshd #${i} gave rc ${RC} (${OUT})" "sshd"
  P="$(last_pid)"
  [ -n "$P" ] && [ "$P" != "$PREV" ] || fail "restart sshd #${i} did not change the pid (${OUT})" "sshd"
  PREV="$P"
done
if grep -a "tars-init: giving up on service sshd" "$LOG" >/dev/null; then
  fail "four restarts made init give up on sshd" "sshd"
fi
N="$(grep -ac "tars-init: restarting service sshd on request" "$LOG")"
[ "$N" = "4" ] || fail "init logged ${N} requested restarts of sshd, want 4" "sshd"
echo "four restarts of sshd, four new pids, no giving up"

# ── 검사 22: sshd를 멈추면 새 ssh가 거절되고, 열어 둔 연결로 되살린다 ─────────
ts stop sshd
[ "$RC" = "0" ] || fail "stop sshd gave rc ${RC} (${OUT})" "sshd"
fresh_ssh && fail "a new ssh got in while sshd was stopped"
ts start sshd
[ "$RC" = "0" ] || fail "start sshd over the kept connection gave rc ${RC} (${OUT})" "sshd"
ok=0
for _ in $(seq 1 10); do
  if fresh_ssh; then ok=1; break; fi
  sleep 0.5
done
[ "$ok" = "1" ] || fail "a new ssh did not get in after start sshd" "sshd"
echo "stop sshd shut new logins out, the kept connection started it again"

# ── 검사 23: SIGTERM을 무시하면 유예 뒤 SIGKILL ───────────────────────────
ts stop stubborn
[ "$RC" = "0" ] || fail "stop stubborn gave rc ${RC} (${OUT})" "stubborn"
tail -1 <<<"$OUT" | grep -E '^service stubborn +stopped$' >/dev/null || fail "stop stubborn did not end stopped (${OUT})"
grep -aE "tars-init: service stubborn outlived SIGTERM by 3s, sent SIGKILL to group [0-9]+" "$LOG" >/dev/null \
  || fail "init did not send SIGKILL to stubborn" "stubborn"
echo "stubborn ignored SIGTERM and was stopped by SIGKILL"

# ── 검사 24: 포기된 것도 start로 되살린다 ─────────────────────────────────
on_guest 'touch /run/flaky-ok'
ts start flaky
[ "$RC" = "0" ] || fail "start flaky gave rc ${RC} (${OUT})" "flaky"
tail -1 <<<"$OUT" | grep -E '^service flaky +running +pid [0-9]+$' >/dev/null || fail "start flaky did not end running (${OUT})"
echo "start flaky revived a given-up service"

# ── 검사 25: 거절 다섯 ─────────────────────────────────────────────────
LONG="$(printf 'x%.0s' $(seq 1 70))"
expect_refused() {  # $1 = 인자, $2 = 원하는 rc, $3 = 원하는 첫 줄
  ts "$1"
  [ "$RC" = "$2" ] || fail "tars-service $1 gave rc ${RC}, want $2 (${OUT})"
  [ "$(head -1 <<<"$OUT")" = "$3" ] || fail "tars-service $1 said [$(head -1 <<<"$OUT")], want [$3]"
}
expect_refused "stop nope" 1 "error: no service named nope"
expect_refused "stop terminal" 1 "error: no service named terminal"
expect_refused "stop 'a b'" 1 "error: bad request"
expect_refused "stop ${LONG}" 1 "error: request of 75 bytes, at most 64"
expect_refused "bogus" 64 "usage: tars-service status [NAME]"
echo "unknown names, the terminal, a bad request, a long request and bad usage were refused"

# ── 검사 26: 통로의 fd가 서비스로 새지 않는다 ──────────────────────────────
FDS="$(on_guest 'ls -l /proc/$(pgrep -x sleep -P $(pgrep -x sleeper))/fd')"
[ -n "$FDS" ] || fail "could not list the fds of sleeper's sleep"
grep -q "socket:" <<<"$FDS" && fail "sleeper's sleep holds a socket (${FDS})"
echo "sleeper's child holds no socket from init"

ssh -o ControlPath="$CTL" -O exit root@127.0.0.1 2>/dev/null || true
stop_ssh
rm -f "$LOG"
rm -f "$B_LOG"
rm -rf "$KEYS"

echo "SV chain PASS"
