#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# MI-M0: 스물일곱째 체인. 사용자가 화면 셸에서 공식 `curl https://mise.run | sh`를 치고
# `mise use -g node@lts`로 node를 받으면 그 node가 도는가(MI design 결정 1 · 2). PM 체인 다음으로 바깥
# 망에 기대는 둘째 체인이다(위험 1) — QEMU를 띄우기 전에 컨테이너에서 mise.run · mise.jdx.dev ·
# github.com · nodejs.org를 한 번 치고, 안 닿으면 그 이름으로 빨개진다.
#
# 부팅 둘이 같은 NVMe 이미지를 잇달아 쓴다.
#   1  ISO + 빈 최소 NVMe   tars-install --yes(기본 계정 tars · tars-linux)
#   2  NVMe + SLIRP NIC     net=dhcp · 사용자로 mise.run(M1) · mise --version(M2) · mise use -g node@lts(M3) ·
#                           node의 ldd와 node -p(M4) · activate 후보 셋의 시간(M5) · mise doctor · 측정
#
# 모양은 pm/check.sh의 것이다 — 시리얼 FIFO로 root 콘솔 셸에 한 줄씩 넣고 그 출력을 로그에서 읽는다.
# "사용자로"는 setpriv로 한다. PM과 다른 점: sudo가 없다(mise는 홈에만 쓴다), 부팅 3(화면)이 없다
# (activate와 재부팅 뒤 화면 셸은 MI-M1), 포트를 안 쓴다.
#
# 시간은 게스트 안에서 `date +%s%N`의 차로 잰다(mi-ms-<이름>=<밀리초>). 시리얼을 오가는 지연이 숫자에
# 안 섞인다.

(cd ../kernel && ./build.sh)
(cd ../init && zig build)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
(cd ../boot && ./build.sh)
(cd ../boot && ./make_iso.sh)

source ../gate_lib.sh

OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
if [ ! -f "$OVMF_CODE" ]; then
  echo "FAIL: ${OVMF_CODE} not found; is the devcontainer image current?" >&2
  exit 1
fi

INSTALL_URL="https://mise.run"
MISE="/home/tars/.local/bin/mise"

WORK="$(mktemp -d)"

# ── 사전 확인: 바깥 망(design 결정 2) ──────────────────────────────────
# 초록으로 건너뛰지 않는다(PM과 같다). 이 줄로 빨개지면 우리 코드가 아니라 망이다.
for url in "$INSTALL_URL" https://mise.jdx.dev https://github.com https://nodejs.org/dist/index.json; do
  if ! curl -fsS -o /dev/null --max-time 20 "$url"; then
    echo "FAIL: mise: external network unavailable (${url})"
    rm -rf "$WORK"
    exit 1
  fi
done
curl -fsSL --max-time 30 -o "${WORK}/install.sh" "$INSTALL_URL"
echo "mise: mise.run sha256 $(sha256sum "${WORK}/install.sh" | cut -c1-64) ($(wc -l < "${WORK}/install.sh") lines)"

DISK="${WORK}/target.img"
# tars-install의 최소 디스크(init/src/disk.zig의 MIN_DISK_BYTES = 4 GiB + 2 MiB). mise와 node가 /home
# (약 3GiB)에 들어가는지를 측정 3이 본다.
truncate -s 4098M "$DISK"

# -cpu는 다른 체인과 같은 TCG 기본 모델 qemu64다. PM 체인은 Homebrew의 SSSE3 요구 때문에 max지만,
# mise.run · mise · node 26은 qemu64에서 끝까지 돌았다(MI-M0 측정 11). -m은 1024다 — 512에서는 mise.run이
# /tmp(tmpfs)에 tarball과 푼 바이너리(약 230MB)를 잠깐 함께 두어, RAM에 풀린 initrd와 합쳐 기계가
# 굳었다(측정 11, MemAvailable 2,236kB에서 멈춤). 두 값은 MI_CPU · MI_MEM으로 바꿔 돌릴 수 있다.
MI_CPU="${MI_CPU:-qemu64}"
MI_MEM="${MI_MEM:-1024}"
echo "mise: qemu -cpu ${MI_CPU} -m ${MI_MEM}"

QEMU_PID=""
LOG=""
FIFO=""

# shellcheck disable=SC2329 # trap cleanup EXIT이 부른다
cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  exec 4>&- 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# 여기부터는 판정이 실패를 직접 다룬다.
set +e

clean() {
  perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
            s/\e[()][AB0]//g; s/\r/\n/g' "$LOG"
}

# 꼬리에 mise · curl의 말을 언제나 더한다 — 빨개지면 저쪽이 무엇이라 했는지가 그대로 보이게.
fail() {
  echo "FAIL: $1"
  shift
  echo "--- context ---"
  local pattern
  for pattern in "$@" "mise ERROR" "mise WARN" "mise: " "curl:" "Error" "not found"; do
    grep -aF -- "$pattern" "$LOG" | tail -5 || true
  done
  echo "--- serial log tail (cleaned) ---"
  clean | tail -60
  exit 1
}

# boot_guest <이름> [qemu 인자...]. 콘솔 셸이 뜰 때까지 기다린다.
boot_guest() {
  local name="$1"; shift
  LOG="$(mktemp -t "mise-boot-${name}.XXXXXX")"
  FIFO="${WORK}/boot-${name}.fifo"
  local vars="${WORK}/vars-${name}.fd"
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
  rm -f "$FIFO"; mkfifo "$FIFO"
  exec 4<>"$FIFO"
  qemu-system-x86_64 \
    -machine q35,i8042=off \
    -cpu "$MI_CPU" \
    -m "$MI_MEM" \
    -netdev user,id=n0 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$vars" \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -drive file="$DISK",if=none,id=target,format=raw \
    -device nvme,drive=target,serial=tarstarget \
    "$@" \
    -serial stdio \
    -monitor none \
    -display none \
    -no-reboot \
    < "$FIFO" > "$LOG" 2>&1 &
  QEMU_PID=$!

  local waited=0
  while [ "$waited" -lt 180 ]; do
    if grep -aq "tars-init: started console shell" "$LOG"; then break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1; waited=$((waited + 1))
  done
  if ! grep -aq "tars-init: started console shell" "$LOG"; then
    fail "boot ${name}: the console shell never started (${waited}s)" \
      "PANIC" "efi: EFI" "tars-init"
  fi
  echo "boot ${name}: console shell up after ${waited}s"
  sleep 3
}

stop_guest() {
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""
  exec 4>&-
  rm -f "$FIFO"
}

send() { printf '%s\n' "$1" >&4; }

# 사용자 tars(uid 1000)로 bash 한 줄을 친다. 인자는 작은따옴표를 안 담는다 — 콘솔의 fish가 그
# 따옴표 안을 그대로 bash에 준다(home/check.sh의 as_user와 같은 규칙). fish의 작은따옴표 안에서
# 특별한 것은 \\와 \'뿐이라 $ · $(…) · $((…))는 bash가 펼친다. 사용자의 길과 다른 환경 변수는 없다.
#
# XDG_DATA_HOME을 뺀다. 콘솔 셸은 init의 환경(XDG_DATA_HOME=/config/xdg, root의 자리)을 그대로 갖고,
# 화면 셸은 terminal의 buildAccount가 이 변수를 빼고 띄운다(HP, home/check.sh가 판정). 빼지 않으면
# mise가 node를 /config/xdg/mise에 깔려다 Permission denied로 멈춘다 — MI-M0 첫 판이 그랬다. 사용자의
# 길에는 없는 막힘이다.
as_tars() {
  send "setpriv --reuid=1000 --regid=1000 --init-groups env -u XDG_DATA_HOME HOME=/home/tars USER=tars LOGNAME=tars PATH=/usr/bin:/bin bash -c '$1'"
}

# 로그에 고정 문자열 / 정규식이 나타날 때까지 기다린다. 0이면 나왔다. 기다리는 글자는 타이핑한
# 줄의 에코에 없는 모양이어야 한다(project_gate_screen_echo) — 그래서 접두사 뒤의 값까지 넣어
# 기다리거나, 숫자 자리를 정규식으로 기다린다.
wait_log() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if grep -aqF -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

wait_log_re() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if grep -aqE -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

# 정규식에 맞는 마지막 줄의 마지막 수.
last_num() { grep -aoE -- "$1" "$LOG" | tail -1 | grep -oE '[0-9]+' | tail -1; }

# 게스트에서 잰 밀리초(mi-ms-<이름>=N)의 마지막 값.
ms_of() { last_num "mi-ms-$1=[0-9]+"; }

CHAIN_T0=$(date +%s)

# ── 부팅 1: ISO + 빈 최소 NVMe ─────────────────────────────────────────
echo "=== boot 1: the ISO and a blank minimum-size NVMe (4 GiB + 2 MiB) ==="
# -netdev만 있고 NIC 장치가 없다 — QEMU는 이때 기본 NIC를 안 붙인다(nic 체인 실측 5).
boot_guest 1 -cdrom ../out/tars.iso
send "tars-install /dev/nvme0n1 --yes"
if ! wait_log "tars-install: done. remove the boot medium and reboot." 240; then
  fail "tars-install did not say done" "tars-install:" "failed"
fi
grep -aqF "tars-install: made /home/tars" "$LOG" || fail "tars-install did not make /home/tars" "tars-install:"
echo "tars-install put TARS and the account tars on the minimum-size disk"
stop_guest

# ── 부팅 2: NVMe + SLIRP NIC ───────────────────────────────────────────
echo "=== boot 2: the NVMe with a user-mode NIC ==="
boot_guest 2 -device virtio-net-pci,netdev=n0
grep -aqF "tars-init: mounted ext4 at /home" "$LOG" || fail "/home is not mounted" "tars-init: home" "tars-init: failed"

send "tars-config set net=dhcp; and tars-config reload"
wait_log_re "eth0: leased 10\.0\.2\.15 " 90 || fail "dhcpcd never leased an address" ": leased" "dhcpcd" "tars-init: reload"
echo "net=dhcp: eth0 leased 10.0.2.15"

# ── 측정 6: MemAvailable 표본(5초마다) ──────────────────────────────────
send "bash -c 'while :; do grep MemAvailable /proc/meminfo; sleep 5; done' &"

# ── M1: 사용자로 mise.run(사용자 결정 2, 측정 1) ────────────────────────
# 사용자는 `curl https://mise.run | sh`를 친다. 체인은 파일에 받아 sh로 돌린다 — 같은 스크립트이고, 위에서
# sha256을 찍은 것과 같다고 가정한다. MISE_DEBUG=1은 스크립트의 debug 줄(받은 tarball의 이름)을 낸다.
echo "=== typing mise.run as tars ==="
as_tars 's=$(date +%s%N); curl -fsSL -o /tmp/mi-install.sh '"$INSTALL_URL"' && MISE_DEBUG=1 sh /tmp/mi-install.sh 2>&1 | sed "s/^/mi-inst: /"; r=${PIPESTATUS[0]}; e=$(date +%s%N); echo "mi-ms-install=$(((e-s)/1000000))"; echo "mi-install-rc-$r"'
wait_log_re "mi-install-rc-[0-9]+" 600 || fail "mise.run did not finish in 600s" "mi-inst"
[ "$(last_num 'mi-install-rc-[0-9]+')" = 0 ] || fail "mise.run failed" "mi-inst" "mi-install-rc"
grep -aqF "mise: installed successfully to ${MISE}" "$LOG" || fail "mise.run did not say installed successfully" "mi-inst"
echo "M1: mise.run installed ${MISE} as tars in $(ms_of install)ms"

# ── M2: mise --version, 처음과 두 번째(측정 2) ──────────────────────────
for n in 1 2; do
  as_tars 's=$(date +%s%N); '"$MISE"' --version 2>&1 | sed "s/^/mi-ver'"$n"'=/"; e=$(date +%s%N); echo "mi-ms-ver'"$n"'=$(((e-s)/1000000))"'
  wait_log_re "mi-ms-ver${n}=[0-9]+" 120 || fail "mise --version (${n}) never answered" "mi-ver${n}"
done
grep -aqE "mi-ver1=20[0-9]{2}\.[0-9]+\.[0-9]+" "$LOG" || fail "mise --version does not print a version" "mi-ver1"
echo "M2: mise --version answers ($(ms_of ver1)ms cold, $(ms_of ver2)ms warm)"

# ── M3: mise use -g node@lts(사용자 결정 3, 측정 3 · 5 · 7) ─────────────
# MISE_DEBUG=1로 gpg 검증의 줄을 본다(design 확인 2). 출력이 길어도 접두사로 모은다.
echo "=== mise use -g node@lts (download and unpack node) ==="
as_tars 's=$(date +%s%N); MISE_DEBUG=1 '"$MISE"' use -g node@lts 2>&1 | sed "s/^/mi-use: /"; r=${PIPESTATUS[0]}; e=$(date +%s%N); echo "mi-ms-use=$(((e-s)/1000000))"; echo "mi-use-rc-$r"'
wait_log_re "mi-use-rc-[0-9]+" 1200 || fail "mise use -g node@lts did not finish in 1200s" "mi-use"
[ "$(last_num 'mi-use-rc-[0-9]+')" = 0 ] || fail "mise use -g node@lts failed" "mi-use" "mi-use-rc" "gpg"
send "grep -c node /home/tars/.config/mise/config.toml | sed 's/^/mi-m3-config=/'"
wait_log_re "mi-m3-config=[0-9]+" 10
[ "$(last_num 'mi-m3-config=[0-9]+')" -ge 1 ] 2>/dev/null || fail "the global mise config does not name node" "mi-m3-config"
echo "M3: mise use -g node@lts finished in $(ms_of use)ms and the global config names node"

# ── M4: node가 돈다(위험 2, 측정 4) ─────────────────────────────────────
# ldd의 not found 줄을 센다. 0이어야 한다.
as_tars 'n=$('"$MISE"' which node); echo "mi-m4-node=$n"; ldd "$n" 2>&1 | sed "s/^/mi-ldd: /"; ldd "$n" 2>&1 | grep -c "not found" | sed "s/^/mi-m4-missing=/"'
wait_log_re "mi-m4-missing=[0-9]+" 60 || fail "ldd on node never answered" "mi-m4-node" "mi-ldd"
[ "$(last_num 'mi-m4-missing=[0-9]+')" = 0 ] || fail "node needs a library the image does not have" "mi-ldd" "not found"
as_tars '"$('"$MISE"' which node)" --version 2>&1 | sed "s/^/mi-m4-ver=/"'
wait_log_re "mi-m4-ver=v[0-9]+\." 120 || fail "node --version did not answer" "mi-m4-ver"
as_tars 's=$(date +%s%N); '"$MISE"' exec -- node -p "[process.versions.v8, 6*7].join(String.fromCharCode(32))" 2>&1 | sed "s/^/mi-m4-js=/"; e=$(date +%s%N); echo "mi-ms-js=$(((e-s)/1000000))"'
wait_log_re "mi-m4-js=[0-9.]+-?[a-z0-9.]* 42" 180 || fail "mise exec -- node -p did not print 42" "mi-m4-js"
echo "M4: node has every library, $(grep -aoE 'mi-m4-ver=v[^ ]+' "$LOG" | tail -1 | cut -d= -f2) runs and mise exec -- node -p says 42 ($(ms_of js)ms)"

# ── M5: activate 후보 셋의 시간(design 결정 3, 측정 8) ──────────────────
# 값의 판정은 M1의 일이다. 여기서는 숫자가 나오는지만 본다.
as_tars 's=$(date +%s%N); '"$MISE"' hook-env -s bash >/dev/null 2>&1; e=$(date +%s%N); echo "mi-ms-hookenv=$(((e-s)/1000000))"'
wait_log_re "mi-ms-hookenv=[0-9]+" 60 || fail "mise hook-env never finished" "mi-ms-hookenv"
as_tars ''"$MISE"' reshim 2>&1 | sed "s/^/mi-reshim: /"; s=$(date +%s%N); /home/tars/.local/share/mise/shims/node --version 2>&1 | sed "s/^/mi-m5-shim=/"; e=$(date +%s%N); echo "mi-ms-shim=$(((e-s)/1000000))"'
wait_log_re "mi-ms-shim=[0-9]+" 120 || fail "the node shim never answered" "mi-reshim" "mi-m5-shim"
grep -aqE "mi-m5-shim=v[0-9]+\." "$LOG" || fail "the node shim did not print a version" "mi-m5-shim" "mi-reshim"
as_tars 'n=$('"$MISE"' which node); s=$(date +%s%N); "$n" --version >/dev/null 2>&1; e=$(date +%s%N); echo "mi-ms-direct=$(((e-s)/1000000))"'
wait_log_re "mi-ms-direct=[0-9]+" 60 || fail "node by path never answered" "mi-ms-direct"
echo "M5: hook-env $(ms_of hookenv)ms, node through the shim $(ms_of shim)ms, node by path $(ms_of direct)ms"

# ── 측정 9: mise doctor — 판정하지 않고 적는다 ─────────────────────────
as_tars ''"$MISE"' doctor 2>&1 | sed "s/^/mi-doc: /"; echo "mi-doc-rc-${PIPESTATUS[0]}"'
wait_log_re "mi-doc-rc-[0-9]+" 120 || echo "mise: mise doctor did not finish in 120s (not judged)"

# ── 측정 3 · 6 · 7 ──────────────────────────────────────────────────────
send "dmesg | grep -c 'Out of memory' | sed 's/^/mi-oom=/'"
wait_log_re "mi-oom=[0-9]+" 10
[ "$(last_num 'mi-oom=[0-9]+')" = 0 ] || fail "the guest ran out of memory" "Out of memory" "Killed process"
send "du -sk ${MISE} /home/tars/.local/share/mise /home/tars/.cache/mise /tmp 2>/dev/null | sed 's/^/mi-du /'; df -k /home | tail -1 | sed 's/^/mi-df /'; printf 'mi-%s\n' end"
wait_log "mi-end" 60
MEM_MIN="$(grep -aoE 'MemAvailable: +[0-9]+' "$LOG" | grep -oE '[0-9]+' | sort -n | head -1)"

echo "mise: measure 1: mise.run $(ms_of install)ms; tarball: $(clean | grep -aoE 'mise-v[0-9.]+-linux-[a-z0-9-]+\.tar\.(gz|zst)' | sort -u | head -2 | tr '\n' ' ')"
echo "mise: measure 1: fell back to GitHub: $(clean | grep -acF 'trying GitHub Releases')"
echo "mise: measure 2: mise --version $(ms_of ver1)ms cold, $(ms_of ver2)ms warm; $(grep -aoE 'mi-ver1=[^ ]+' "$LOG" | tail -1)"
echo "mise: measure 3: mise use -g node@lts $(ms_of use)ms"
clean | grep -aE '^mi-(du|df) ' | sed 's/^/mise: measure 3: /'
echo "mise: measure 4: node -p $(ms_of js)ms; ldd:"
clean | grep -a '^mi-ldd: ' | sort -u | sed 's/^mi-ldd: /mise:   /'
# 게스트에 gpg 명령이 없다. mise는 SHASUMS256.txt.sig를 스스로 읽고(MI-M0 둘째 판에서 서명 패킷의
# 덤프 IssuerFingerprint · SignatureCreationTime이 찍힌 뒤 checksum 단계로 갔다), 바깥 gpg를 찾다 실패하면
# 그 줄이 여기 나온다.
echo "mise: measure 5: signature lines in mise use: $(clean | grep -a '^mi-use: ' | grep -acE 'IssuerFingerprint|SignatureCreationTime'), gpg lines:"
clean | grep -a '^mi-use: ' | grep -ai 'gpg' | sort -u | head -15 | sed 's/^mi-use: /mise:   /'
echo "mise: measure 6: MemAvailable min ${MEM_MIN:-?} kB"
echo "mise: measure 8: hook-env $(ms_of hookenv)ms, shim $(ms_of shim)ms, direct $(ms_of direct)ms"
echo "mise: measure 9: mise doctor rc $(last_num 'mi-doc-rc-[0-9]+'); its output:"
# 앞부분(version · dirs · toolset)과 끝의 problems를 따로 찍는다 — backends 목록이 길어 한 번에 자르면
# problems가 잘린다(둘째 판).
clean | grep -a '^mi-doc: ' | head -30 | sed 's/^mi-doc: /mise:   /'
clean | grep -a '^mi-doc: ' | sed -n '/problems\{0,1\} found/,$p' | sed 's/^mi-doc: /mise:   /'
echo "mise: mise use output (no DEBUG lines):"
clean | grep -a '^mi-use: ' | grep -av 'DEBUG' | head -40 | sed 's/^mi-use: /mise:   /'

stop_guest

echo "mise: measure 10: chain $(( $(date +%s) - CHAIN_T0 ))s after the build"
echo "PASS"
exit 0
