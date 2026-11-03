#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# PM-M0: 스물여섯째 체인. 사용자가 화면 셸에서 공식 Homebrew install.sh를 그대로 치면 끝까지
# 가는가(PM design 결정 2 · 3 · 6). 바깥 망에 기대는 첫 체인이다(design 확인 6 · 위험 1) — QEMU를
# 띄우기 전에 컨테이너에서 github.com과 ghcr.io를 한 번 치고, 안 닿으면 그 이름으로 빨개진다.
#
# 부팅 둘이 같은 NVMe 이미지를 잇달아 쓴다.
#   1  ISO + 빈 8GiB NVMe   tars-install --yes(기본 계정 tars · tars-linux)
#   2  NVMe + SLIRP NIC     net=dhcp · /bin 링크(P1) · 도구와 git https(P2) · 사용자로 install.sh(P3) ·
#                           prefix와 brew --version(P4) · brew config와 portable-ruby(P5) · 측정 2~7
#
# 모양은 home/check.sh의 것이다 — 시리얼 FIFO로 root 콘솔 셸에 한 줄씩 넣고 그 출력을 로그에서
# 읽는다. "사용자로"는 setpriv로 한다. install.sh의 NONINTERACTIVE 길은 `sudo -n -l mkdir`만
# 보므로 같은 tty(시리얼 콘솔)에서 먼저 `sudo -S -k -v`로 timestamp를 만든다. install.sh가
# ${USER}로 chown하므로 USER · HOME · LOGNAME을 함께 준다. 사용자의 길과 다른 환경 변수는
# NONINTERACTIVE와 HOMEBREW_NO_ANALYTICS(게이트가 Homebrew 통계를 더럽히지 않게) 둘이다.
# monitor · QMP가 없어 포트를 안 쓴다.

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

INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
PREFIX="/home/linuxbrew/.linuxbrew"

WORK="$(mktemp -d)"

# ── 사전 확인: 바깥 망(design 결정 6) ──────────────────────────────────
# 초록으로 건너뛰지 않는다. 사용자가 고른 것이 "실제 망으로 끝까지"다. 이 줄로 빨개지면 우리
# 코드가 아니라 망이다.
for url in https://github.com https://ghcr.io "$INSTALL_URL"; do
  if ! curl -fsS -o /dev/null --max-time 20 "$url"; then
    echo "FAIL: pm: external network unavailable (${url})"
    rm -rf "$WORK"
    exit 1
  fi
done
curl -fsSL --max-time 30 -o "${WORK}/install.sh" "$INSTALL_URL"
echo "pm: install.sh sha256 $(sha256sum "${WORK}/install.sh" | cut -c1-64) ($(wc -l < "${WORK}/install.sh") lines)"

DISK="${WORK}/target.img"
# 8GiB. /home이 약 7GiB라 Homebrew가 차지하는 양(측정 5)이 최소 디스크의 /home(약 3GiB)에
# 들어가는지와 섞이지 않는다. 측정 5가 3GiB 안이면 M1에서 줄인다.
truncate -s 8G "$DISK"

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

# 꼬리에 Homebrew의 말(==> · Error: · Warning:)과 sudo · curl · git의 말을 언제나 더한다 — 빨개지면
# 저쪽이 무엇이라 했는지가 그대로 보이게.
fail() {
  echo "FAIL: $1"
  shift
  echo "--- context ---"
  local pattern
  for pattern in "$@" "==>" "Error:" "Warning:" "sudo:" "curl:" "git:" "fatal:"; do
    grep -aF -- "$pattern" "$LOG" | tail -5 || true
  done
  echo "--- serial log tail (cleaned) ---"
  clean | tail -60
  exit 1
}

# boot_guest <이름> [qemu 인자...]. 콘솔 셸이 뜰 때까지 기다린다.
boot_guest() {
  local name="$1"; shift
  LOG="$(mktemp -t "pm-boot-${name}.XXXXXX")"
  FIFO="${WORK}/boot-${name}.fifo"
  local vars="${WORK}/vars-${name}.fd"
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
  rm -f "$FIFO"; mkfifo "$FIFO"
  exec 4<>"$FIFO"
  # -cpu max: 이 체인만 기본 CPU 모델(TCG의 qemu64)을 안 쓴다. qemu64에는 SSSE3가 없고 Homebrew는
  # x86_64 Linux에서 SSSE3를 요구한다 — PM-M0 둘째 판이 install.sh의 마지막 `brew update`에서
  # `Error: Homebrew's x86_64 support on Linux requires a CPU with SSSE3 support!`로 멈췄다. 실기의
  # x86-64는 Core 2(2006) 이후 전부 SSSE3가 있어 사용자의 길에는 없는 막힘이다.
  # -m 1024: 이 체인만 GUEST_MEM(512)을 안 쓴다(PM-M0 plan Task 4의 규칙 — OOM이 나면 이 체인만).
  # 여섯째 판에서 brew update의 portable-ruby가 anon-rss 151,664kB에서 OOM으로 죽었다 — 그때
  # unevictable이 278,368kB(RAM에 풀린 initrd)라 512MB에서는 200MB 남짓이 남는다(측정 4).
  qemu-system-x86_64 \
    -machine q35,i8042=off \
    -cpu max \
    -m 1024 \
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

# 사용자 tars(uid 1000)로 bash 한 줄을 친다. 인자는 작은따옴표를 안 담는다 — 콘솔의 fish가
# 그 따옴표 안을 그대로 bash에 준다(home/check.sh의 as_user와 같은 규칙). LANG은 주지 않는다 —
# init이 모든 자식에게 LANG=C.UTF-8을 준다(PM-M0, environ.zig의 LANG_ENTRY). 여기서 주면 그 사실을
# 체인이 못 본다. 다섯째 판까지는 시리얼 셸의 fish가 스스로 LC_CTYPE=en_US.UTF-8(데이터 없음)을
# export했고, 그것이 LANG보다 우선해서 여기 LANG을 줘도 로케일이 깨졌다.
as_tars() {
  send "setpriv --reuid=1000 --regid=1000 --init-groups env HOME=/home/tars USER=tars LOGNAME=tars HOMEBREW_NO_ANALYTICS=1 PATH=/usr/bin:/bin bash -c '$1'"
}

# 로그에 고정 문자열 / 정규식이 나타날 때까지 기다린다. 0이면 나왔다. 기다리는 글자는 타이핑한
# 줄의 에코에 없는 모양이어야 한다(project_gate_screen_echo) — 그래서 sed가 붙이는 접두사 뒤의
# 값까지 넣어 기다리거나, 숫자 자리를 정규식으로 기다린다.
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

CHAIN_T0=$(date +%s)

# ── 부팅 1: ISO + 빈 8GiB NVMe ─────────────────────────────────────────
echo "=== boot 1: the ISO and a blank 8 GiB NVMe ==="
# -netdev만 있고 NIC 장치가 없다 — QEMU는 이때 기본 NIC를 안 붙인다(nic 체인 실측 5). 설치에 망은 필요 없다.
boot_guest 1 -cdrom ../out/tars.iso
send "tars-install /dev/nvme0n1 --yes"
if ! wait_log "tars-install: done. remove the boot medium and reboot." 240; then
  fail "tars-install did not say done" "tars-install:" "failed"
fi
grep -aqF "tars-install: made /home/tars" "$LOG" || fail "tars-install did not make /home/tars" "tars-install:"
echo "tars-install put TARS and the account tars on the 8 GiB disk"
stop_guest

# ── 부팅 2: NVMe + SLIRP NIC ───────────────────────────────────────────
echo "=== boot 2: the NVMe with a user-mode NIC ==="
boot_guest 2 -device virtio-net-pci,netdev=n0
grep -aqF "tars-init: mounted ext4 at /home" "$LOG" || fail "/home is not mounted" "tars-init: home" "tars-init: failed"

# 설치 직후의 net은 off다(config.zig의 기본값). 사용자도 이 두 줄로 망을 켠다.
send "tars-config set net=dhcp; and tars-config reload"
wait_log_re "eth0: leased 10\.0\.2\.15 " 90 || fail "dhcpcd never leased an address" ": leased" "dhcpcd" "tars-init: reload"
echo "net=dhcp: eth0 leased 10.0.2.15"

# ── P1: /bin은 usr/bin으로의 링크다(결정 2) ─────────────────────────────
send "readlink /bin | sed 's/^/pm-p1-bin=/'"
wait_log "pm-p1-bin=usr/bin" 10 || fail "/bin is not a link to usr/bin" "pm-p1-bin"
send "readlink -f /bin/sh | sed 's/^/pm-p1-sh=/'"
wait_log "pm-p1-sh=/usr/bin/bash" 10 || fail "/bin/sh does not resolve to bash" "pm-p1-sh"
for t in mkdir chmod chown chgrp touch; do
  send "/bin/${t} --version | head -1 | sed 's/^/pm-p1-${t}=/'"
  wait_log "pm-p1-${t}=${t} (GNU coreutils)" 10 || fail "/bin/${t} does not run" "pm-p1-${t}"
done
echo "P1: /bin -> usr/bin, /bin/sh is bash, install.sh's five /bin tools answer"

# ── P2: 도구와 git의 https(결정 3) ─────────────────────────────────────
send "ldd --version | head -1 | sed 's/^/pm-p2-ldd=/'"
wait_log_re "pm-p2-ldd=ldd .*2\.41" 10 || fail "ldd does not report glibc 2.41" "pm-p2-ldd"
send "tar --version | head -1 | sed 's/^/pm-p2-tar=/'"
wait_log "pm-p2-tar=tar (GNU tar)" 10 || fail "tar does not run" "pm-p2-tar"
send "gzip --version | head -1 | sed 's/^/pm-p2-gzip=/'"
wait_log_re "pm-p2-gzip=gzip [0-9]" 10 || fail "gzip does not run" "pm-p2-gzip"
send "install --version | head -1 | sed 's/^/pm-p2-install=/'"
wait_log "pm-p2-install=install (GNU coreutils)" 10 || fail "install does not run" "pm-p2-install"
send "mktemp | sed 's/^/pm-p2-mktemp=/'"
wait_log "pm-p2-mktemp=/tmp/tmp." 10 || fail "mktemp does not run" "pm-p2-mktemp"
as_tars 'git ls-remote https://github.com/Homebrew/brew HEAD 2>&1 | sed "s/^/pm-p2-git=/"'
wait_log_re "pm-p2-git=[0-9a-f]{40}" 60 || fail "git cannot read https://github.com/Homebrew/brew" "pm-p2-git"
# PM-M0 셋째 · 넷째 판이 더한 셋. brew의 os.sh가 PRETTY_NAME을 읽고, setup-locale이 `locale charmap`을
# 보고, portable-ruby가 libdl.so.2를 부른다(make_initrd.sh의 GLIBC_LIBS).
send "sh -c '. /etc/os-release; echo pm-p2-os=\$PRETTY_NAME'"
wait_log_re "pm-p2-os=TARS [0-9]" 10 || fail "/etc/os-release does not name TARS" "pm-p2-os"
grep -aqF "tars-init: env PATH=/usr/bin:/bin XDG_DATA_HOME=/config/xdg TZ=" "$LOG" && grep -aqE "tars-init: env .* LANG=C\.UTF-8" "$LOG" \
  || fail "init did not put LANG=C.UTF-8 in the env block" "tars-init: env"
as_tars 'env | grep -E "^(LANG|LC_)" | sed "s/^/pm-p2-locvar=/"; locale charmap 2>&1 | sed "s/^/pm-p2-charmap=/"'
wait_log "pm-p2-charmap=UTF-8" 10 || fail "locale charmap is not UTF-8 for tars" "pm-p2-charmap" "pm-p2-locvar"
if grep -aqF "pm-p2-locvar=LC_" "$LOG"; then fail "an LC_ variable leaked into the user's env" "pm-p2-locvar"; fi
send "ls /lib/x86_64-linux-gnu/libdl.so.2 /lib/x86_64-linux-gnu/libmvec.so.1 | wc -l | sed 's/^/pm-p2-glibc=/'"
wait_log "pm-p2-glibc=2" 10 || fail "the glibc compat libraries are missing" "pm-p2-glibc"
echo "P2: ldd reports 2.41; tar, gzip, install, mktemp run; tars reads Homebrew/brew over https with git;"
echo "    os-release names TARS, locale charmap is UTF-8, libdl and libmvec are there"

# ── 측정 4: MemAvailable 표본(5초마다) ──────────────────────────────────
send "bash -c 'while :; do grep MemAvailable /proc/meminfo; sleep 5; done' &"

# ── P3: 사용자로 install.sh(사용자 결정 2, 결정 6) ─────────────────────
# `sudo -k` 따로, 그 다음 `sudo -S -v`. -k를 먼저 혼자 치는 이유는 HP-M2의 함정이다 — timestamp가
# 남아 있으면 sudo가 비밀번호를 안 읽고 파이프의 첫 줄이 다음 명령에게 간다. 한 번에 `sudo -S -k -v`로
# 치면 안 된다: -k를 다른 옵션과 함께 쓰면 비밀번호는 묻되 timestamp를 남기지 않는다(sudo(8)
# "will not update the user's cached credentials"). PM-M0 첫 판이 그렇게 빨갰다 — sudo는 rc 0이었는데
# install.sh의 `sudo -n -l mkdir`이 실패해 "Insufficient permissions to install Homebrew"였다.
# -v가 이 tty에 남긴 timestamp를 install.sh의 `sudo -n`이 쓴다. pm-sudo-n은 그 조건을 install.sh
# 직전에 직접 본다. 게스트가 받는 install.sh는 위에서 sha256을 찍은 것과 같다고 가정한다.
echo "=== typing install.sh as tars (this is the long part; the limit is 1800s) ==="
T_INSTALL0=$(date +%s)
as_tars 'sudo -k; printf "%s\n" tars-linux | sudo -S -v 2>/dev/null; echo "pm-sudo-rc-$?"; sudo -n -l mkdir >/dev/null 2>&1; echo "pm-sudo-n-rc-$?"; curl -fsSL -o /tmp/pm-install.sh '"$INSTALL_URL"' && NONINTERACTIVE=1 bash /tmp/pm-install.sh; echo "pm-install-rc-$?"'
wait_log_re "pm-sudo-rc-[0-9]+" 30 || fail "sudo -v never answered" "pm-sudo-rc"
[ "$(last_num 'pm-sudo-rc-[0-9]+')" = 0 ] || fail "tars could not refresh sudo with tars-linux" "pm-sudo-rc"
wait_log_re "pm-sudo-n-rc-[0-9]+" 30 || fail "sudo -n -l never answered" "pm-sudo-n-rc"
[ "$(last_num 'pm-sudo-n-rc-[0-9]+')" = 0 ] || fail "sudo -v left no timestamp that sudo -n can use" "pm-sudo-n-rc"
wait_log_re "pm-install-rc-[0-9]+" 1800 || fail "install.sh did not finish in 1800s" "pm-install"
T_INSTALL1=$(date +%s)
[ "$(last_num 'pm-install-rc-[0-9]+')" = 0 ] || fail "install.sh failed" "pm-install-rc"
grep -aqF "Installation successful!" "$LOG" || fail "install.sh did not say Installation successful!" "Installation"
echo "P3: install.sh finished as tars in $((T_INSTALL1 - T_INSTALL0))s and said Installation successful!"

# ── P4: prefix의 주인과 brew --version ──────────────────────────────────
send "stat -c 'pm-p4-owner=%U:%G' ${PREFIX}"
wait_log "pm-p4-owner=tars:tars" 10 || fail "${PREFIX} does not belong to tars" "pm-p4-owner"
as_tars "${PREFIX}/bin/brew --version 2>&1 | head -1 | sed \"s/^/pm-p4-ver=/\""
wait_log_re "pm-p4-ver=Homebrew [0-9]" 60 || fail "brew --version does not answer" "pm-p4-ver"
grep -aoE "pm-p4-ver=Homebrew [^ ]+" "$LOG" | tail -1 | sed 's/^pm-p4-ver=/pm: /'
echo "P4: ${PREFIX} belongs to tars and brew --version answers"

# ── P5: brew config가 portable-ruby를 받고 답한다(측정 3) ───────────────
T_CFG0=$(date +%s)
as_tars "${PREFIX}/bin/brew config 2>&1 | sed \"s/^/pm-cfg: /\"; echo \"pm-p5-rc-\${PIPESTATUS[0]}\""
wait_log_re "pm-p5-rc-[0-9]+" 900 || fail "brew config did not finish in 900s" "pm-cfg"
T_CFG1=$(date +%s)
[ "$(last_num 'pm-p5-rc-[0-9]+')" = 0 ] || fail "brew config failed" "pm-cfg" "pm-p5-rc"
grep -aqF "pm-cfg: HOMEBREW_PREFIX: ${PREFIX}" "$LOG" || fail "brew config does not show the prefix" "pm-cfg: HOMEBREW_PREFIX"
grep -aqE "pm-cfg: Homebrew Ruby: .*portable-ruby" "$LOG" || fail "brew config does not run on portable-ruby" "pm-cfg: Homebrew Ruby"
echo "P5: brew config answered in $((T_CFG1 - T_CFG0))s on portable-ruby"

# ── P6: brew가 TARS에 대해 불평하지 않는다 ─────────────────────────────
# 셋째 판까지 brew를 칠 때마다 나던 두 경고(os-release 없음, en_US.UTF-8 setlocale)가 없다.
if clean | grep -aE 'setlocale: .*cannot change locale|/etc/os-release: No such file' >/dev/null; then
  fail "brew still warns about the locale or os-release" "setlocale" "os-release"
fi
grep -aqE "pm-cfg: OS: .*TARS" "$LOG" || fail "brew config does not name TARS as the OS" "pm-cfg: OS"
echo "P6: no locale or os-release warnings; brew config names TARS"

# ── 측정 4 · 5 · 6 · 7 ──────────────────────────────────────────────────
send "dmesg | grep -c 'Out of memory' | sed 's/^/pm-m4-oom=/'"
wait_log_re "pm-m4-oom=[0-9]+" 10
send "du -sk ${PREFIX} /home/tars/.cache/Homebrew 2>/dev/null | sed 's/^/pm-m5-du /'; df -k /home | tail -1 | sed 's/^/pm-m5-df /'; printf 'pm-m5-%s\n' end"
wait_log "pm-m5-end" 60
MEM_MIN="$(grep -aoE 'MemAvailable: +[0-9]+' "$LOG" | grep -oE '[0-9]+' | sort -n | head -1)"
echo "pm: measure 2: install.sh $((T_INSTALL1 - T_INSTALL0))s"
echo "pm: measure 3: brew config $((T_CFG1 - T_CFG0))s"
echo "pm: measure 4: MemAvailable min ${MEM_MIN:-?} kB, OOM lines $(last_num 'pm-m4-oom=[0-9]+')"
clean | grep -aE '^pm-m5-(du|df) ' | sed 's/^/pm: measure 5: /'
echo "pm: measure 6: lines naming (none): $(clean | grep -acF '(none)'); the distinct ones that are not a prompt:"
clean | grep -aF '(none)' | grep -avE '@\(none\) ' | sort -u | head -10 | sed 's/^/pm:   /'
# design 실측에 적을 값 — brew config의 전체 출력(게스트 로그는 체인이 끝나면 지워진다).
clean | grep -a '^pm-cfg: ' | sort -u | sed 's/^pm-cfg: /pm: config: /'
echo "pm: measure 7: lines about a missing file command: $(clean | grep -acE 'file: (command )?not found|No such file or directory.*\bfile\b')"

stop_guest

echo "pm: measure 8: chain $(( $(date +%s) - CHAIN_T0 ))s after the build"
echo "PASS"
exit 0
