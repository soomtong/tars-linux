#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# HP-M0: 스물다섯째 체인. 설치기가 셋째 파티션 `tars-home`(ext4, 나머지 전부)을
# 만들고, 설치된 디스크로 뜬 init이 `/config`(ext2 · sync) 옆에 `/home`(ext4 ·
# async)을 붙이며, 재부팅을 넘어 홈의 파일이 남고, 남의 ext4는 라벨로 거르는가
# (HP design 결정 11 — 판정 1 · 2 · 3 · 5 · 6 · 7, HP-M1이 4 · 9 · 10을, HP-M2가 8(sudo)을, LT-M0이 8g(sudo의
# timestamp가 tty를 넘는다)와 11(사용자의 ping)을 더했다).
#
# 부팅 셋이 같은 NVMe 이미지를 잇달아 쓴다.
#   1  ISO + 빈 17GiB NVMe + 3GiB NVMe  홈 없는 부팅은 root(결정 3) · 3GiB는 거절(판정 7) · ext4 굽기 시간(실측 3) ·
#                                       질문 길로 hpuser를 설치(판정 9) · 배치(판정 1)
#   2  NVMe만                           p2와 p3(판정 2) · 마운트 옵션(판정 3) · 화면 셸이 hpuser다(판정 4) ·
#                                       계정 파일의 권한(판정 10) · 사용자로 마커를 쓴다 · 사용자로 막히는 것(실측 10) ·
#                                       sudo · try: sudo · passwd(판정 8a~8d) · 사용자의 ping(판정 11) ·
#                                       다른 tty의 sudo(판정 8g)
#   3  NVMe + 남의 ext4(debian-home)     마커 둘이 남았다(판정 5) · 남의 디스크는 홈이 아니다(판정 6) ·
#                                       바꾼 비밀번호가 재부팅을 넘었다(판정 8e)
#
# 모양은 install/check.sh의 것이다 — 시리얼 FIFO로 콘솔 셸에 한 줄씩 넣고 그
# 출력을 로그에서 읽는다. 시리얼 셸은 root로 남는다(HP-M1 plan 확정 1). 화면 셸은 키를
# 쳐서 보지 않고 그 pid의 /proc을 root가 읽는다 — uid · env · cwd · pty가 거기 다 있다.
# "사용자로 쓴다"는 setpriv(guest_tools 층 17)로 한다. 그래서 키를 안 보내고 monitor ·
# QMP가 없다. RP-M0의 예약 범위에서 이 체인 몫은 45497(monitor) · 45498(QMP)이고 지금은
# 둘 다 안 연다.
# QEMU는 kill로 끈다 — 전원 버튼이 아니다. 홈의 마커는 그래서 `sync`를 치고
# 쓴다(ext4는 async라 안 치면 다음 부팅에 없다 — 그것이 design 결정 1의 다른 면이다).

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

WORK="$(mktemp -d)"
DISK="${WORK}/target.img"
# 17GiB. 최소 16GiB + 2MiB(disk.MIN_DISK_BYTES, TP부터)가 들어가는 가장 작은 정수다.
truncate -s 17G "$DISK"
# 3GiB. HP 전에는 설치가 되던 크기라 이것의 거절이 새 최소값을 증명한다(판정 7).
SMALL="${WORK}/small.img"
truncate -s 3G "$SMALL"
# 남의 ext4. 라벨이 `tars-`로 시작하지 않는 디스크 전체 ext4다(판정 6).
FOREIGN="${WORK}/foreign.img"
truncate -s 64M "$FOREIGN"
mke2fs -q -F -t ext4 -L debian-home "$FOREIGN"

# mtools가 QEMU가 꺼진 사이 p1(FAT32)을 직접 연다(install/check.sh와 같다).
export MTOOLS_SKIP_CHECK=1
ESP_IMG="${DISK}@@1M"

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

fail() {
  echo "FAIL: $1"
  shift
  echo "--- context ---"
  local pattern
  for pattern in "$@"; do
    grep -aF -- "$pattern" "$LOG" | tail -5 || true
  done
  echo "--- serial log tail (cleaned) ---"
  clean | tail -40
  exit 1
}

# boot_guest <이름> [qemu 인자...]. 콘솔 셸이 뜰 때까지 기다린다.
boot_guest() {
  local name="$1"; shift
  LOG="$(mktemp -t "home-boot-${name}.XXXXXX")"
  FIFO="${WORK}/boot-${name}.fifo"
  local vars="${WORK}/vars-${name}.fd"
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
  rm -f "$FIFO"; mkfifo "$FIFO"
  exec 4<>"$FIFO"
  qemu-system-x86_64 \
    -machine q35,i8042=off \
    -nic none \
    -m "$GUEST_MEM" \
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

# HP-M2. 사용자(uid 1000)로 sh 한 줄을 친다. 인자는 작은따옴표를 안 담는다 — 게스트의 fish가
# 그 따옴표 안을 그대로 sh에 준다. 결과는 `echo "hp-s8-<이름>-$?"`로 찍고 `s8_code <이름>`이 읽는다.
as_user() { send "setpriv --reuid=1000 --regid=1000 --init-groups env HOME=/home/hpuser sh -c '$1'"; }
# 비밀번호를 파이프로 주는 sudo는 언제나 -k다. sudo는 한 번 확인하면 15분짜리 timestamp를 남기고 다음 판에서
# 묻지 않는다 — 그러면 파이프의 첫 줄(비밀번호)이 sudo가 아니라 명령에게 간다. HP-M2 첫 판들에서 passwd가
# hp-secret-1과 hp-secret-2를 비교해 "differ"라 했던 이유다. LT-M0부터 그 timestamp는 tty가 아니라 사용자 하나에
# 묶인다(timestamp_type=global) — 명령과 함께 준 -k는 timestamp를 안 읽고 안 남기므로 이 규칙은 그대로 맞다.
# timestamp를 일부러 남기는 것은 판정 8g 하나이고, 그래서 그것이 이 부팅의 sudo 가운데 맨 뒤다.
# hp-s8-<이름>-<숫자>의 숫자. 타이핑한 줄의 `-$?`는 숫자가 아니라 안 걸린다.
s8_wait() { wait_log_re "hp-s8-$1-[0-9]+" "${2:-60}" || fail "the step $1 never answered" "hp-s8-$1" "sudo:" "tars-config:"; }
s8_code() { grep -aoE "hp-s8-$1-[0-9]+" "$LOG" | tail -1 | sed 's/.*-//'; }

# 로그에 고정 문자열이 나타날 때까지 기다린다. 0이면 나왔다.
#
# 기다리는 글자는 타이핑한 줄에 없는 모양이어야 한다 — 콘솔 셸이 친 명령을
# 에코하므로 `hp-geo-`처럼 명령에 든 접두사로 기다리면 출력이 나오기 전에
# 에코에서 바로 돌아온다(project_gate_screen_echo). 그래서 printf의 `%s`가 숫자로
# 바뀐 완성형(`hp-geo-1572864-…`)이나 정규식(`hp-mkfs-[0-9]+-ms`)으로 기다린다.
wait_log() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if grep -aqF -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

# 같은 것, 정규식으로.
wait_log_re() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if grep -aqE -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

# ── 부팅 1: ISO + 빈 NVMe + 3GiB NVMe ──────────────────────────────────
echo "=== boot 1: the ISO, a blank 17 GiB NVMe and a 3 GiB NVMe ==="
boot_guest 1 -cdrom ../out/tars.iso \
  -drive file="$SMALL",if=none,id=small,format=raw \
  -device nvme,drive=small,serial=tarssmall

# 결정 3. ISO 부팅에는 /home이 없고 화면 셸은 root다.
if ! grep -aqF "tars-init: no tars-home disk, shell runs as root" "$LOG"; then
  fail "the ISO boot did not say its shell runs as root" "tars-init: no tars-home" "tars-init: user"
fi
echo "the ISO boot has no home and says the shell runs as root"

# 판정 8f(HP-M2). 사용자 없는 부팅의 root도 sudo가 된다 — root는 비밀번호를 안 묻고, pam_unix의
# account 단계가 initrd의 정적 /etc/shadow(root 한 줄)에서 root를 찾는다. hostname 경고도 없다(!fqdn).
# 실행하는 명령은 true가 아니라 id다 — 게스트에 /usr/bin/true가 없고 fish의 true는 내장이라 sudo가 못 찾는다.
send "sudo id -u 2>&1 | sed 's/^/hp-s8-isoroot: /'; printf 'hp-s8-isoroot-%s\n' done"
wait_log "hp-s8-isoroot-done" || fail "root's sudo on the ISO boot never answered" "hp-s8-isoroot" "sudo:"
grep -aqF "hp-s8-isoroot: 0" "$LOG" || fail "root's sudo fails on a boot without a user" "hp-s8-isoroot" "sudo:"
if grep -aqF "unable to resolve host" "$LOG"; then fail "sudo warns about the host name on the ISO boot" "unable to resolve host"; fi
echo "8f: root's sudo works on the ISO boot"

# 판정 7. 3GiB는 YES 전에 거절된다. formatSize는 10진 버림이라 3,221,225,472는
# `3 GB`다. 아무것도 안 썼다 — 파티션 테이블 줄이 없다.
send "tars-install /dev/nvme1n1 --yes; printf 'hp-small-%s\n' done"
wait_log "hp-small-done" \
  || fail "tars-install on the 3 GiB disk never came back to the shell" "tars-install:" "hp-small"
if ! grep -aqF "tars-install: /dev/nvme1n1 is 3 GB; TARS needs more than 16 GiB" "$LOG"; then
  fail "a 3 GiB disk was not refused by the new minimum" "tars-install:"
fi
if grep -aqF "tars-install: writing the partition table" "$LOG"; then
  fail "the 3 GiB disk was partitioned anyway" "tars-install:"
fi
echo "a 3 GiB disk is refused before YES (it was enough before HP)"

# 실측 3. 설치기와 같은 명령으로 3GiB를 ext4로 굽는 시간. initrd에 mke2fs.conf가
# 없어서 feature 목록은 내장 기본값이다 — 그 목록은 QEMU가 꺼진 뒤 호스트의
# dumpe2fs가 이 이미지에서 읽는다(위험 6).
send "sh -c 'T0=\$(date +%s%N); mke2fs -q -t ext4 -e remount-ro -L hp-scratch /dev/nvme1n1; T1=\$(date +%s%N); printf \"hp-mkfs-%s-ms\\n\" \$(( (T1-T0)/1000000 ))'"
wait_log_re "hp-mkfs-[0-9]+-ms" 120 \
  || fail "mke2fs -t ext4 on the 3 GiB disk never finished" "mke2fs" "hp-mkfs"
echo "mke2fs -t ext4 on 3 GiB took $(grep -aoE 'hp-mkfs-[0-9]+-ms' "$LOG" | head -1 | tr -dc 0-9) ms"

# 판정 9(HP-M1). 사람의 길 — --yes 없이 질문 셋에 답한다. 시리얼 콘솔은 tty라 비밀번호의
# echo 끄기까지 진짜로 지나간다. 기본값 길(--yes)은 install/check.sh가 지킨다.
#
# 프롬프트 글자는 타이핑한 줄에 없다(에코에서 돌아오지 않는다). 질문마다 그 프롬프트가
# 나타난 수를 센다 — 거절 뒤 같은 질문이 다시 나오는 것이 판정이다.
prompt_count() { grep -aoF -- "$1" "$LOG" | wc -l; }
wait_prompt() {
  local want="$1" n="$2"
  for _ in $(seq 1 600); do
    if [ "$(prompt_count "$want")" -ge "$n" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}
HP_PASSWORD="hp-secret-1"
send "tars-install /dev/nvme0n1"
wait_prompt "user name [tars]: " 1 || fail "tars-install never asked for the user name" "tars-install:" "user name"
send "root"
wait_log "tars-install: 'root' is not a user name" \
  || fail "the installer took root as a user name" "tars-install:" "user name"
wait_prompt "user name [tars]: " 2 || fail "the installer did not ask again after refusing root" "user name"
send "hpuser"
wait_prompt "password [tars-linux]: " 1 || fail "tars-install never asked for the password" "password"
# PW-M0. 한 글자 더 치고 Backspace(0x7f)로 지운다. 칸은 글자마다 `*`, Backspace에 `\b \b`를 찍는다(PW design 결정 5).
# 버퍼에서도 빠졌다는 증거는 8b다 — 그 sudo가 $HP_PASSWORD로 통한다.
send "${HP_PASSWORD}X"$'\x7f'
wait_log "  user  hpuser  (home /home/hpuser, password as typed)" \
  || fail "the plan does not show the account hpuser" "  user  " "tars-install:"
wait_prompt "type YES to continue: " 1 || fail "tars-install never asked for YES" "type YES"
send "YES"
if ! wait_log "tars-install: done. remove the boot medium and reboot." 180; then
  fail "tars-install did not say done" "tars-install:" "failed" "never appeared"
fi
if ! grep -aqF "tars-install: formatting /dev/nvme0n1p3 (ext4, tars-home)" "$LOG"; then
  fail "tars-install did not format p3 as ext4 tars-home" "tars-install: formatting"
fi
for want in "tars-install: wrote tars.conf (user=hpuser) and shadow" "tars-install: made /home/hpuser"; do
  grep -aqF "$want" "$LOG" || fail "missing: ${want}" "tars-install:"
done
# 비밀번호는 한 글자도 로그에 없다 — echo가 꺼졌고 설치기가 찍지 않는다.
if grep -aqF "$HP_PASSWORD" "$LOG"; then
  fail "the typed password shows up in the serial log" "$HP_PASSWORD"
fi
# PW-M0. 열두 글자(hp-secret-1X)에 `*` 열둘, Backspace에 `\b \b` 하나.
# init의 줄은 같은 UART에 쓴다 — TP-M2 루트 게이트에서 5초 뒤의 `tars-init: audio: no sound card …` 한 줄이 프롬프트와 별표
# 사이에 끼어 빨갰다(lessons의 TC-M3 덧붙임과 같은 모양). 끼어든 tars-init 온줄을 떼고 본다. 접두사는 그 하나로 좁다.
# 파일로 받는다 — `perl | grep -q`는 grep이 먼저 닫을 때 SIGPIPE가 pipefail로 올라온다.
perl -0pe 's/tars-init: [^\n]*\n//g' "$LOG" >"${LOG}.noinit"
grep -aqF "password [tars-linux]: ************"$'\b \b' "${LOG}.noinit" \
  || fail "the password prompt did not show a star per character and erase one on backspace" "password [tars-linux]"
echo "tars-install asked three questions, refused root, made hpuser; the password never reached the log"
echo "PW: the password prompt showed 12 stars and took one back on backspace"
# 실측 7. yescrypt 한 번(TCG).
grep -aoE 'password hashed \(yescrypt\) in [0-9]+ms' "$LOG" | head -1

# 판정 1. 배치. sysfs의 섹터 수가 sfdisk -l의 글자 폭보다 낫다. 1MiB 정렬에서
# p1은 2048부터 768MiB(1572864섹터), p2는 256MiB(524288섹터), p3는 1025MiB(2099200)부터.
send "printf 'hp-geo-%s-%s-%s\n' \$(cat /sys/block/nvme0n1/nvme0n1p1/size) \$(cat /sys/block/nvme0n1/nvme0n1p2/size) \$(cat /sys/block/nvme0n1/nvme0n1p3/start)"
wait_log "hp-geo-1572864-524288-2099200" \
  || fail "the layout is not 768 MiB + 256 MiB + rest (or sysfs did not answer)" "hp-geo-" "nvme0n1p"
echo "p1 is 768 MiB, p2 is 256 MiB, p3 starts at 1025 MiB"

stop_guest

# 실측 2 · 3(호스트). ESP의 빈 자리와, 게스트의 mke2fs가 켠 ext4 feature.
echo "esp: $(mdir -i "$ESP_IMG" ::/ | grep -aoE '[0-9 ]+ bytes free' | tr -s ' ')"
echo "ext4 features (guest mke2fs, no mke2fs.conf): $(dumpe2fs -h "$SMALL" 2>/dev/null | grep -aE '^Filesystem features' | cut -d: -f2 | tr -s ' ')"
echo "ext4 errors behavior: $(dumpe2fs -h "$SMALL" 2>/dev/null | grep -aE '^Errors behavior' | cut -d: -f2 | tr -s ' ')"

# ── 부팅 2: NVMe만 ─────────────────────────────────────────────────────
echo "=== boot 2: the NVMe alone ==="
# 사운드 카드 하나(AU 체인과 같은 HDA, 소리는 버린다). 실측 10이 /dev/snd의 권한과 사용자의
# aplay를 본다 — 카드가 없으면 /dev/snd가 없어서 잴 것이 없다.
boot_guest 2 -audiodev none,id=snd0 -device ich9-intel-hda -device hda-micro,audiodev=snd0

# 판정 2. 설정은 p2, 홈은 p3. 둘 다 라벨로 잡혔고 붙었다.
for want in \
  "tars-init: config storage /dev/nvme0n1p2 (label tars-config)" \
  "tars-init: mounted ext2 at /config" \
  "tars-init: home storage /dev/nvme0n1p3 (label tars-home)" \
  "tars-init: mounted ext4 at /home"; do
  if ! grep -aqF "$want" "$LOG"; then
    fail "missing: ${want}" "tars-init: config storage" "tars-init: home storage" "tars-init: no disk labelled" "tars-init: failed to mount"
  fi
done
echo "init found tars-config on p2 and tars-home on p3 and mounted both"

# 판정 3. /home은 ext4이고 async다 — sync가 없다. superblock의 errors=remount-ro와
# 기본 저널 모드 data=ordered가 커널의 눈에 보인다.
send "grep ' /home ' /proc/mounts | sed 's/^/hp-mounts: /'"
wait_log "hp-mounts: /dev/nvme0n1p3 /home ext4 rw,nosuid,nodev,relatime" \
  || fail "/home is not mounted as ext4 rw,nosuid,nodev,relatime (or not at all)" "hp-mounts:" "/home"
if grep -aE "hp-mounts: /dev" "$LOG" | grep -a "sync" >/dev/null; then
  fail "/home is mounted sync; the home partition must be async" "hp-mounts:"
fi
send "sed 's/^/hp-opts: /' /proc/fs/ext4/nvme0n1p3/options"
for want in "hp-opts: errors=remount-ro" "hp-opts: data=ordered"; do
  wait_log "$want" 10 \
    || fail "missing ext4 option: ${want#hp-opts: }" "hp-opts:" "/proc/fs/ext4"
done
echo "/home is ext4, async, errors=remount-ro, data=ordered"

# 마커. 판정 5가 다음 부팅에서 본다. ext4는 async라 sync를 친다.
send "echo hp-m0 > /home/hp-marker && sync && printf 'hp-marker-%s\n' written"
wait_log "hp-marker-written" \
  || fail "could not write the marker onto /home" "hp-marker"
echo "wrote /home/hp-marker"

# 판정 4(HP-M1). 화면 셸이 hpuser다. init의 줄 둘과 terminal의 줄이 있고, 그 셸 pid의
# /proc이 uid · gid · 보조 그룹 · env · cwd · pty를 말한다.
for want in \
  "tars-init: user hpuser uid 1000 home /home/hpuser" \
  "tars-init: hpuser is in /etc/passwd, /etc/group and /etc/shadow"; do
  grep -aqF "$want" "$LOG" || fail "missing: ${want}" "tars-init: user" "tars-init: account" "tars-init: no "
done
wait_log_re "terminal: spawned child pid [0-9]+ \(.*\) as hpuser" 60 \
  || fail "terminal did not spawn its shell as hpuser" "terminal: spawned" "cannot drop"
SPID="$(grep -aoE 'terminal: spawned child pid [0-9]+ \(.*\) as hpuser' "$LOG" | head -1 | awk '{print $5}')"
echo "the screen shell is pid ${SPID}, spawned as hpuser"

send "printf 'hp-ids-%s-%s-%s\n' \"\$(awk '/^Uid:/{print \$2\"/\"\$3\"/\"\$4\"/\"\$5}' /proc/${SPID}/status)\" \"\$(awk '/^Gid:/{print \$2\"/\"\$3}' /proc/${SPID}/status)\" \"\$(awk '/^Groups:/{print \$2\",\"\$3}' /proc/${SPID}/status)\""
wait_log "hp-ids-1000/1000/1000/1000-1000/1000-27,29" \
  || fail "the screen shell is not uid 1000 / gid 1000 / groups 27,29 (sudo, audio)" "hp-ids-"
send "printf 'hp-cwd-%s\n' \"\$(readlink /proc/${SPID}/cwd)\""
wait_log "hp-cwd-/home/hpuser" || fail "the screen shell did not start in /home/hpuser" "hp-cwd-"
send "stat -c 'hp-pty-%U-%G-%a' \"\$(readlink /proc/${SPID}/fd/0)\""
wait_log "hp-pty-hpuser-tty-620" || fail "the screen shell's pty is not hpuser:tty 620" "hp-pty-"
send "tr '\\0' '\\n' < /proc/${SPID}/environ | grep -E '^(HOME|USER|LOGNAME|SHELL|XDG_DATA_HOME|HISTFILE)=' | sed 's/^/hp-env: /'; printf 'hp-env-%s\n' end"
wait_log "hp-env-end" || fail "could not read the screen shell's environ" "hp-env"
for want in "hp-env: HOME=/home/hpuser" "hp-env: USER=hpuser" "hp-env: LOGNAME=hpuser" "hp-env: SHELL=/usr/bin/fish"; do
  grep -aqF "$want" "$LOG" || fail "the screen shell's env lacks ${want#hp-env: }" "hp-env:"
done
if grep -aqF "hp-env: XDG_DATA_HOME=" "$LOG"; then
  fail "the screen shell still has XDG_DATA_HOME (root's /config/xdg)" "hp-env:"
fi
echo "screen shell: uid/gid 1000, groups 27,29 (sudo, audio), cwd /home/hpuser, pty hpuser:tty 620, HOME/USER/LOGNAME/SHELL its own, no XDG_DATA_HOME"

# 판정 10(HP-M1). 계정 파일과 홈의 권한. shadow 둘은 root 600, 홈은 700, seed 다섯은 사용자의 것.
send "cd /home/hpuser && stat -c 'hp-perm %n %U %G %a' /etc/shadow /config/shadow /home/hpuser .bashrc .zshrc .config/fish/config.fish .gitconfig .vimrc; cd /; printf 'hp-perm-%s\n' end"
wait_log "hp-perm-end" || fail "stat of the account files never finished" "hp-perm"
for want in \
  "hp-perm /etc/shadow root root 600" \
  "hp-perm /config/shadow root root 600" \
  "hp-perm /home/hpuser hpuser hpuser 700" \
  "hp-perm .bashrc hpuser hpuser 644" \
  "hp-perm .zshrc hpuser hpuser 644" \
  "hp-perm .config/fish/config.fish hpuser hpuser 644" \
  "hp-perm .gitconfig hpuser hpuser 644" \
  "hp-perm .vimrc hpuser hpuser 644"; do
  grep -aqF "$want" "$LOG" || fail "missing: ${want}" "hp-perm"
done
send "grep -E '^(tty|sudo|audio|hpuser):' /etc/group | sed 's/^/hp-group: /'; sed -n 2p /etc/shadow | cut -c1-10 | sed 's/^/hp-shadow: /'; printf 'hp-group-%s\n' end"
wait_log "hp-group-end" || fail "could not read /etc/group" "hp-group"
for want in "hp-group: tty:x:5:" "hp-group: sudo:x:27:hpuser" "hp-group: audio:x:29:hpuser" "hp-group: hpuser:x:1000:" "hp-shadow: hpuser:\$y\$"; do
  grep -aqF "$want" "$LOG" || fail "missing: ${want}" "hp-group:" "hp-shadow:"
done
echo "shadow is root 600 in /etc and /config with a yescrypt hash, the home is hpuser 700 with five seeds, sudo and audio list hpuser"

# 사용자로 마커. 판정 5가 다음 부팅에서 주인까지 본다.
send "setpriv --reuid=1000 --regid=1000 --init-groups sh -c 'echo hp-m1 > /home/hpuser/hp-marker' && sync && stat -c 'hp-owner-%U' /home/hpuser/hp-marker"
wait_log "hp-owner-hpuser" || fail "hpuser could not write into its own home" "hp-owner" "setpriv"
echo "hpuser wrote /home/hpuser/hp-marker"

# 실측 10(위험 10). 사용자로 쳐서 무엇이 막히나 — 판정이 아니라 기록이다. 0이 됐다.
# 콘솔 셸은 fish다 — for · do · done이 없다. 그래서 반복은 여기(bash)서 돌리고 게스트에는
# 명령마다 한 줄을 보낸다. 사용자 쪽 sh가 결과 줄까지 찍으므로 `$?`는 sh의 것이다.
# HP-M1 Task 5: init이 /dev/snd를 root:audio 660으로 바꾼다. 그 줄을 먼저 기다린다.
wait_log_re "tars-init: audio: [0-9]+ nodes in /dev/snd are root:audio 660 \(0 refused\)" 30 \
  || fail "init did not open /dev/snd to the audio group" "tars-init: audio"
for c in 'amixer -c 0' 'aplay -l' 'dmesg' 'git config --global hp.try 1' \
         'tars-config get shell' 'ls /config' 'cat /config/shadow'; do
  send "setpriv --reuid=1000 --regid=1000 --init-groups env HOME=/home/hpuser sh -c '${c} >/dev/null 2>&1; echo \"hp-try: ${c} -> \$?\"'"
done
send "stat -c 'hp-dev: %n %U %G %a' /dev/snd/*; printf 'hp-sys: dmesg_restrict=%s ping_group_range=%s\n' \"\$(cat /proc/sys/kernel/dmesg_restrict)\" \"\$(tr '\\t' ' ' < /proc/sys/net/ipv4/ping_group_range)\"; printf 'hp-try-%s\n' end"
wait_log "hp-try-end" 60 || fail "the as-the-user tries never finished" "hp-try"
echo "--- as hpuser (0 = allowed) ---"
# 줄 머리에 프롬프트의 escape가 붙으므로 머리에 묶지 않고 그 조각만 뽑는다.
clean | grep -aoE '(hp-try: [^>]+ -> [0-9]+|hp-dev: .*|hp-sys: dmesg.*)$' | grep -av 'printf' | sed 's/^/  /'
# 판정(위험 10, HP-M1). 사용자가 카드의 제어 장치를 연다 — 0600 root였으면 1이다. 노드는
# 그룹 audio의 rw다. 나머지 줄은 기록이고 design 실측 10에 적는다.
grep -aqE "hp-try: amixer -c 0 -> 0" "$LOG" || fail "hpuser cannot open the sound card" "hp-try: amixer" "hp-dev:"
# stat인 이유: 게스트의 ls는 eza 별칭이고 eza -l은 그룹 칸을 안 찍는다.
grep -aqF "hp-dev: /dev/snd/controlC0 root audio 660" "$LOG" \
  || fail "/dev/snd/controlC0 is not root:audio 660" "hp-dev:"
echo "the sound nodes are root:audio 660 and hpuser opens the card"

# 판정 11(LT-M0). 사용자가 ping을 친다. initrd의 ping에는 Debian이 붙이는 file capability가 없어(cpio는 xattr을 안
# 싣는다) raw 소켓을 못 연다 — init이 부팅에 ping_group_range를 모든 그룹으로 열어서 ICMP datagram 소켓으로 간다
# (LT design 결정 1). 위 실측 10의 hp-sys 줄이 그 값을 기록하고, 여기서는 실제로 한 번 갔다 오는가를 본다.
as_user 'ping -c 1 -W 2 127.0.0.1 >/dev/null 2>&1; echo "hp-ping-$?"'
wait_log_re "hp-ping-[0-9]+" 30 || fail "hpuser's ping never answered" "hp-ping" "ping:"
grep -aqF "hp-ping-0" "$LOG" || fail "hpuser cannot ping 127.0.0.1 (ping_group_range?)" "hp-ping" "hp-sys:" "tars-init: cannot open ping"
echo "11: hpuser pings 127.0.0.1 without a capability"

# ── 판정 8(HP-M2): sudo ──────────────────────────────────────────────────
# 8a. 파일. sudo는 setuid root이고 sudoers는 root 440이다 — 아니면 sudo가 스스로 거절한다.
send "stat -c 'hp-s8a %n %u:%g %a' /usr/bin/sudo /etc/sudoers /etc/pam.d/sudo /usr/libexec/sudo/sudoers.so /usr/libexec/sudo/libsudo_util.so.0; printf 'hp-s8a-%s\n' end"
wait_log "hp-s8a-end" || fail "stat of the sudo files never finished" "hp-s8a"
for want in \
  "hp-s8a /usr/bin/sudo 0:0 4755" \
  "hp-s8a /etc/sudoers 0:0 440" \
  "hp-s8a /etc/pam.d/sudo 0:0 644" \
  "hp-s8a /usr/libexec/sudo/sudoers.so 0:0 644" \
  "hp-s8a /usr/libexec/sudo/libsudo_util.so.0 0:0"; do
  grep -aqF "$want" "$LOG" || fail "missing: ${want}" "hp-s8a"
done
echo "8a: sudo is setuid root, sudoers is root 440, the plugin and PAM file are in place"
# PW-M0 결정 9. sudo의 비밀번호 칸도 `*`를 찍는다. 게이트는 sudo에 파이프(-S)로만 주므로 모양은 실기가 본다.
send "grep -c '^Defaults pwfeedback\$' /etc/sudoers | sed 's/^/hp-s8a-pwfeedback-/'"
wait_log "hp-s8a-pwfeedback-1" || fail "/etc/sudoers has no Defaults pwfeedback line" "hp-s8a-pwfeedback"
echo "8a: sudoers has Defaults pwfeedback"

# 8b. 비밀번호 없이는 안 되고, 틀린 것도 안 되고, 설치 때 정한 것은 된다. 측정 13은 마지막 것의 시간이다.
# 실패의 이유까지 본다 — 명령을 못 찾아도 0이 아니므로 종료 코드만으로는 "비밀번호가 필요하다"가 아니다.
as_user 'sudo -n id -u 2>&1 | sed "s/^/hp-s8-nopw: /"; echo "hp-s8-nopw-$?"'
s8_wait nopw
grep -aqF "hp-s8-nopw: sudo: a password is required" "$LOG" || fail "sudo -n did not ask for a password" "hp-s8-nopw"
if grep -aqF "hp-s8-nopw: 0" "$LOG"; then fail "sudo -n id worked without a password" "hp-s8-nopw"; fi
as_user 'printf "wrong\n" | sudo -S -k id -u >/dev/null 2>&1; echo "hp-s8-wrong-$?"'
s8_wait wrong
[ "$(s8_code wrong)" != 0 ] || fail "sudo took a wrong password" "hp-s8-wrong"
# -p "": -S의 프롬프트는 개행 없이 stderr에 가서 2>&1이면 id의 0과 한 줄이 된다 — 비운다.
# shellcheck disable=SC2016 # 펼치는 것은 게스트의 sh다
as_user 't0=$(date +%s%N); printf "hp-secret-1\n" | sudo -S -k -p "" id -u 2>&1 | sed "s/^/hp-s8-uid-/"; echo "hp-s8-ms-$(( ($(date +%s%N) - t0) / 1000000 ))"; echo "hp-s8-right-$?"'
s8_wait right
wait_log "hp-s8-uid-0" 5 || fail "sudo with the install-time password did not run as uid 0" "hp-s8-uid-" "sudo:"
echo "8b: sudo -n refuses, a wrong password is refused, hp-secret-1 runs id -u as 0 in $(s8_code ms)ms (TCG)"
# 측정 14. sudo가 사용자에게 찍는 줄(경고가 섞이는가).
as_user 'printf "hp-secret-1\n" | sudo -S -k id -u 2>&1 | sed "s/^/hp-s8-said: /"; echo "hp-s8-said-$?"'
s8_wait said
echo "--- what sudo said ---"
clean | grep -aoE 'hp-s8-said: .*$' | grep -av 'sed ' | sed 's/^/  /'
# hostname이 `(none)`이라 sudo마다 찍히던 경고. sudoers의 !fqdn이 없앤다(HP-M2 실측).
if grep -aqF "unable to resolve host" "$LOG"; then
  fail "sudo still warns about the host name" "unable to resolve host"
fi

# 8c. 사용자의 쓰기는 try: sudo로 바뀌고 파일은 그대로다. sudo로는 된다. 값은 seed와 다른 것이어야
# 쓰기까지 간다(seed는 ntp=off — 같으면 안 쓴다).
# 게스트에 sha256sum이 없다 — root가 사본을 떠 두고 뒤에서 cmp로 본다.
send "cp /config/tars.conf /tmp/hp-conf.before; printf 'hp-s8-copied-%s\n' conf"
wait_log "hp-s8-copied-conf" || fail "could not copy tars.conf" "hp-s8-copied"
as_user 'tars-config set ntp=dhcp; echo "hp-s8-set-$?"'
s8_wait set
[ "$(s8_code set)" = 77 ] || fail "tars-config set as the user exited $(s8_code set), want 77" "hp-s8-set" "tars-config:"
grep -aqF "tars-config: permission denied; try: sudo tars-config set ntp=dhcp" "$LOG" \
  || fail "tars-config set as the user did not say try: sudo" "tars-config:"
as_user 'tars-config reload; echo "hp-s8-reload-$?"'
s8_wait reload
[ "$(s8_code reload)" = 77 ] || fail "tars-config reload as the user exited $(s8_code reload), want 77" "hp-s8-reload" "tars-config:"
grep -aqF "tars-config: permission denied; try: sudo tars-config reload" "$LOG" \
  || fail "tars-config reload as the user did not say try: sudo" "tars-config:"
# 비밀을 묻는 앞문은 묻기 전에 거절한다(2026-11-05 Air 실기 — Wi-Fi 비밀번호를 받은 뒤에야 거절해서, 사람이 이어지는
# sudo의 비밀번호 칸에 Wi-Fi 비밀번호를 넣었다). stdin을 닫아 두므로, 묻는다면 `passphrase for` 줄이 찍힌다.
as_user 'tars-config wifi hp-net < /dev/null; echo "hp-s8-wifi-$?"'
s8_wait wifi
[ "$(s8_code wifi)" = 77 ] || fail "tars-config wifi as the user exited $(s8_code wifi), want 77" "hp-s8-wifi" "tars-config:"
grep -aqF "tars-config: permission denied; try: sudo tars-config wifi hp-net" "$LOG" \
  || fail "tars-config wifi as the user did not say try: sudo" "tars-config:"
if grep -aqF "passphrase for hp-net" "$LOG"; then
  fail "tars-config wifi asked for the passphrase before refusing the user" "passphrase for"
fi
as_user 'tars-service status; echo "hp-s8-svc-$?"'
s8_wait svc
[ "$(s8_code svc)" = 77 ] || fail "tars-service status as the user exited $(s8_code svc), want 77" "hp-s8-svc" "tars-service:"
grep -aqF "tars-service: permission denied; try: sudo tars-service status" "$LOG" \
  || fail "tars-service as the user did not say try: sudo" "tars-service:"
send "cmp -s /config/tars.conf /tmp/hp-conf.before; printf 'hp-s8-confsame-%s\n' \$status"
wait_log_re "hp-s8-confsame-[0-9]+" || fail "could not compare tars.conf" "hp-s8-confsame"
grep -aqF "hp-s8-confsame-0" "$LOG" || fail "tars.conf changed under a refused set" "hp-s8-confsame"
as_user 'printf "hp-secret-1\n" | sudo -S -k tars-config set ntp=dhcp >/dev/null 2>&1; echo "hp-s8-sudoset-$?"'
s8_wait sudoset
[ "$(s8_code sudoset)" = 0 ] || fail "sudo tars-config set exited $(s8_code sudoset)" "hp-s8-sudoset" "tars-config:"
send "grep -c '^ntp=dhcp' /config/tars.conf | sed 's/^/hp-s8-ntp-/'"
wait_log "hp-s8-ntp-1" || fail "sudo tars-config set did not write ntp=dhcp" "hp-s8-ntp"
send "tars-config reset ntp >/dev/null; printf 'hp-s8-reset-%s\n' done"
wait_log "hp-s8-reset-done" || fail "root could not put ntp back" "hp-s8-reset"
echo "8c: the user's set · reload · wifi (before asking) · tars-service say try: sudo (77) and leave tars.conf alone; sudo tars-config set writes"

# 8d. passwd. 사용자로는 try: sudo, 두 값이 다르면 아무것도 안 바뀐다, 같으면 새 값이 다음 sudo부터다.
as_user 'tars-config passwd; echo "hp-s8-pwuser-$?"'
s8_wait pwuser
[ "$(s8_code pwuser)" = 77 ] || fail "tars-config passwd as the user exited $(s8_code pwuser), want 77" "hp-s8-pwuser" "tars-config:"
grep -aqF "tars-config: permission denied; try: sudo tars-config passwd" "$LOG" \
  || fail "tars-config passwd as the user did not say try: sudo" "tars-config:"
send "cp /config/shadow /tmp/hp-shadow.before; printf 'hp-s8-copied-%s\n' shadow"
wait_log "hp-s8-copied-shadow" || fail "could not copy /config/shadow" "hp-s8-copied"
as_user 'printf "hp-secret-1\nhp-x\nhp-y\n" | sudo -S -k tars-config passwd; echo "hp-s8-pwdiff-$?"'
s8_wait pwdiff
grep -aqF "tars-config: the two passwords differ; nothing was changed" "$LOG" \
  || fail "passwd with two different values did not say they differ" "tars-config:" "hp-s8-pwdiff"
send "cmp -s /config/shadow /tmp/hp-shadow.before; printf 'hp-s8-shadowsame-%s\n' \$status"
wait_log_re "hp-s8-shadowsame-[0-9]+" || fail "could not compare /config/shadow" "hp-s8-shadowsame"
grep -aqF "hp-s8-shadowsame-0" "$LOG" || fail "/config/shadow changed although the two passwords differed" "hp-s8-shadowsame"
as_user 'printf "hp-secret-1\nhp-secret-2\nhp-secret-2\n" | sudo -S -k tars-config passwd; echo "hp-s8-pwok-$?"'
s8_wait pwok
[ "$(s8_code pwok)" = 0 ] || fail "sudo tars-config passwd exited $(s8_code pwok)" "hp-s8-pwok" "tars-config:" "sudo:"
grep -aqF "password changed for hpuser; sudo asks for the new one from now on" "$LOG" \
  || fail "passwd did not say it changed the password" "tars-config:" "password changed"
as_user 'printf "hp-secret-1\n" | sudo -S -k id -u >/dev/null 2>&1; echo "hp-s8-old-$?"'
s8_wait old
[ "$(s8_code old)" != 0 ] || fail "the old password still works after passwd" "hp-s8-old"
as_user 'printf "hp-secret-2\n" | sudo -S -k id -u >/dev/null 2>&1; echo "hp-s8-new-$?"'
s8_wait new
[ "$(s8_code new)" = 0 ] || fail "the new password does not work right after passwd" "hp-s8-new"
send "stat -c 'hp-s8d %n %U %a' /config/shadow /etc/shadow; sync; printf 'hp-s8d-%s\n' end"
wait_log "hp-s8d-end" || fail "stat of the shadows never finished" "hp-s8d"
for want in "hp-s8d /config/shadow root 600" "hp-s8d /etc/shadow root 600"; do
  grep -aqF "$want" "$LOG" || fail "missing: ${want}" "hp-s8d"
done
echo "8d: passwd refuses the user and two different values, takes hp-secret-2 now; both shadows stay root 600"

# RB-M0. 사용자로 치면 기계는 안 꺼지고 77과 try: sudo — tars-config의 8c와 같은 꼴이다. 인자가 틀리면 권한보다
# 먼저 64다(RB 판정). 이어지는 stop_guest가 기계가 살아 있다는 증거다.
as_user 'reboot; echo "hp-rb-reboot-$?"; poweroff; echo "hp-rb-poweroff-$?"; shutdown -r now; echo "hp-rb-shutdown-$?"; shutdown +5; echo "hp-rb-usage-$?"'
wait_log_re "hp-rb-usage-[0-9]+" 30 || fail "the power commands as the user never answered" "hp-rb-" "reboot:" "shutdown:"
for want in "hp-rb-reboot-77" "hp-rb-poweroff-77" "hp-rb-shutdown-77" "hp-rb-usage-64" \
  "reboot: permission denied; try: sudo reboot" \
  "poweroff: permission denied; try: sudo poweroff" \
  "shutdown: permission denied; try: sudo shutdown -r now" \
  "usage: shutdown [-r | -h | -P] [now]"; do
  grep -aqF "$want" "$LOG" || fail "missing: ${want}" "hp-rb-" "reboot:" "poweroff:" "shutdown:"
done
if grep -aqF "tars-init: shutdown requested" "$LOG"; then
  fail "a power command as the user reached PID 1" "tars-init: shutdown"
fi
echo "RB: reboot, poweroff and shutdown -r as the user say try: sudo and exit 77; shutdown +5 is a usage error"

# 판정 8g(LT-M0). 한 tty에서 확인한 sudo가 다른 tty에서 다시 묻지 않는다(LT design 결정 5, sudoers의
# timestamp_type=global). 화면의 패널마다 pty가 달라 tty 단위였던 HP-M2까지는 패널마다 비밀번호를 물었다.
#
# 두 tty는 이렇게 만든다. 하나는 시리얼 콘솔(ttyS0) — as_user가 거기서 `sudo -v`로 확인만 하고 timestamp를 남긴다.
# 다른 하나는 sudo가 만드는 pty다 — root가 `sudo -u hpuser`로 부르면 sudo는 명령을 새 pty에서 돌린다(sudo 1.9.14부터
# use_pty가 기본값이다). 그 안의 `sudo -n`은 비밀번호를 못 받으므로, timestamp가 tty를 넘을 때만 0이다. 기본(tty)이면
# `sudo: a password is required`다. 그 pty가 정말 ttyS0이 아닌지는 같은 줄에서 `ps -o tty=`로 찍어 본다 — use_pty가
# 꺼지면 둘 다 ttyS0이 되어 이 판정이 아무것도 안 본 채 초록이 되므로, 그 경우를 따로 빨갛게 한다.
#
# 이 부팅의 sudo 가운데 맨 뒤다. 위의 판정들은 -k로 timestamp를 안 읽지만, 8b의 `sudo -n`처럼 -k 없이 묻는 줄이
# 이 뒤에 오면 이 timestamp가 그 답을 바꾼다. 비밀번호는 8d가 바꾼 hp-secret-2다.
as_user 'printf "hp-secret-2\n" | sudo -S -v -p ""; echo "hp-s8-validate-$?"'
s8_wait validate
[ "$(s8_code validate)" = 0 ] || fail "sudo -v with hp-secret-2 exited $(s8_code validate)" "hp-s8-validate" "sudo:"
send "sudo -u hpuser sh -c 'printf \"hp-s8g-tty-%s\\n\" \"\$(ps -o tty= -p \$\$)\"; sudo -n id -u 2>&1 | sed \"s/^/hp-s8g: /\"'; printf 'hp-s8g-%s\n' end"
wait_log "hp-s8g-end" 30 || fail "the sudo from another tty never answered" "hp-s8g" "sudo:"
wait_log_re "hp-s8g-tty-pts/[0-9]+" 5 || fail "the inner sudo did not run on a pty of its own (use_pty off?)" "hp-s8g-tty"
grep -aqF "hp-s8g: 0" "$LOG" || fail "sudo on another tty asked again after sudo -v on the console (timestamp_type=global?)" "hp-s8g" "sudo:"
echo "8g: after sudo -v on ttyS0, sudo -n on $(grep -aoE 'hp-s8g-tty-pts/[0-9]+' "$LOG" | tail -1 | sed 's/hp-s8g-tty-//') ran as uid 0 without asking"

stop_guest

# ── 부팅 3: NVMe + 남의 ext4 ────────────────────────────────────────────
echo "=== boot 3: the NVMe and a foreign ext4 disk labelled debian-home ==="
boot_guest 3 \
  -drive file="$FOREIGN",if=none,id=foreign,format=raw \
  -device nvme,drive=foreign,serial=debianhome

# 판정 5. 마커가 재부팅을 넘었다.
send "printf 'hp-read-%s\n' \"\$(cat /home/hp-marker)\""
wait_log "hp-read-hp-m0" \
  || fail "the marker on /home did not survive the reboot (or could not be read)" "hp-read-" "hp-marker"
send "stat -c 'hp-kept-%U' /home/hpuser/hp-marker && printf 'hp-kept-text-%s\n' \"\$(cat /home/hpuser/hp-marker)\""
wait_log "hp-kept-text-hp-m1" || fail "hpuser's marker did not survive the reboot" "hp-kept"
grep -aqF "hp-kept-hpuser" "$LOG" || fail "hpuser's marker came back with another owner" "hp-kept"
echo "/home/hp-marker and /home/hpuser/hp-marker (still hpuser's) survived the reboot"

# 판정 6. 남의 ext4는 홈도 설정도 아니다. 후보 순서가 디스크 전체 → 파티션이라
# nvme1n1이 p3보다 먼저 읽히는데 라벨이 걸렀다(design 위험 5).
if ! grep -aqF "tars-init: home storage /dev/nvme0n1p3 (label tars-home)" "$LOG"; then
  fail "with a foreign ext4 present init did not pick p3 as home" "tars-init: home storage" "tars-init: no disk labelled"
fi
if grep -aqF "storage /dev/nvme1n1 " "$LOG"; then
  fail "init took the foreign debian-home disk as ours" "storage /dev/nvme1n1"
fi
if ! grep -aqF "tars-init: config storage /dev/nvme0n1p2 (label tars-config)" "$LOG"; then
  fail "with a foreign ext4 present init did not pick p2 as config" "tars-init: config storage"
fi
echo "the foreign debian-home ext4 was left alone; home is still p3 and config is still p2"

# 판정 8e(HP-M2). passwd가 바꾼 값이 /config/shadow로 재부팅을 넘었다 — init이 그것으로 /etc/shadow를 지었다.
as_user 'printf "hp-secret-2\n" | sudo -S -k id -u 2>/dev/null | sed "s/^/hp-s8-boot3-uid-/"; echo "hp-s8-boot3-$?"'
s8_wait boot3
wait_log "hp-s8-boot3-uid-0" 5 || fail "after the reboot sudo does not take hp-secret-2" "hp-s8-boot3" "sudo:"
echo "8e: hp-secret-2 still opens sudo after the reboot"

stop_guest

echo "PASS"
exit 0
