#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# DB-M0: 스물여덟번째 체인. TARS가 macOS 옆에 깔리는가(DB design "게이트").
# `tars-install <disk> --beside`가 남의 파티션을 한 바이트도 안 건드리고 가장 큰 빈 자리에
# TARS-BOOT · TARS-CONFIG · TARS-HOME을 덧붙이고, 그 디스크만으로 TARS가 뜨는가.
#
# 호스트가 "맥 디스크"를 굽는다(아래 make_mac). GPT, p1 FAT32 200MiB(이름 `EFI System Partition`,
# `EFI/APPLE`만), p2 APFS 타입 1GiB(정해진 무늬), 나머지는 빈 자리. 부팅 넷이 그 이미지를 잇달아 쓴다.
#   1  ISO + 맥 디스크 + 작은 맥 디스크 + 빈 디스크
#        목록이 macOS (APFS)와 빈 자리를 말한다 · 통째 설치의 계획이 macOS를 지운다고 말한다 ·
#        자리가 모자란 디스크와 빈 디스크의 --beside는 YES 전에 거절 · --beside --yes가 깐다
#   2  맥 디스크만      TARS-BOOT(p3)에서 떴고 설정은 p4 · 홈은 p5에서 붙였다. 마커를 쓴다
#   3  ISO + 맥 디스크  TARS installed · 갱신은 TARS-BOOT만 쓴다(p4는 그대로) · --beside --wipe
#   4  맥 디스크만      --beside --wipe 뒤 설정이 새것이다(마커가 없다), 여전히 p4 · p5
#   5  GUI 맥만         (DB-M1) 부팅 1이 /dev/nvme3n1p3에 깐 TARS로 떴고 설정은 p5 · 홈은 p6에서 붙였다
# 부팅 1에는 넷째 디스크 "GUI 맥"이 함께 꽂힌다(DB-M1) — 디스크 유틸리티로 나눈 맥이다. 빈 자리는 p2 뒤의
# 128MiB 틈뿐이고, p3이 FAT32 `TARS`, p4가 끝의 NTFS다. 목록의 파티션 줄, `--beside`의 안내, 거절 넷,
# `tars-install /dev/nvme3n1p3`이 이 디스크로 판정된다(판정 7~10).
# 부팅마다 끝나면 호스트가 p1 · p2의 바이트와 GPT 엔트리 1 · 2의 sha256을 처음 것과 비교한다 — 이
# 서브프로젝트의 심장이다(판정 2). 작은 디스크와 빈 디스크는 통째로 비교한다(판정 5).
#
# 콘솔 셸에 시리얼 FIFO로 명령을 넣는 것, kill로 끄는 것, -monitor가 없는 것은 install/check.sh와
# 같은 이유다(그 파일 머리). 헬퍼도 그 파일의 것을 그대로 옮겼다 — 한 체인 안에서만 쓰는 함수라
# gate_lib.sh로 올리지 않는다.

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
MAC="${WORK}/mac.img"
SMALL="${WORK}/small-mac.img"
BLANK="${WORK}/blank.img"
GUI="${WORK}/gui-mac.img"
# boot_guest가 첫 NVMe(nvme0n1)로 꽂는 디스크. 부팅 5만 GUI 맥이다.
FIRST="$MAC"

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

# ── 맥 디스크 ─────────────────────────────────────────────────────────
#
# make_mac <이미지> <크기>. 게이트 컨테이너(aarch64)에는 sfdisk가 없어서 GPT는 mac_gpt.pl이 손으로
# 쓴다 — 게스트의 sfdisk가 그 표를 받아 `--append`하는 것이 곧 그 GPT가 규격대로라는 증명이다.
# 크기는 MiB 정렬이다. p1은 LBA 2048(1MiB)부터 200MiB, p2는 201MiB부터 1GiB.
#
# 무늬를 채우는 이유. p1의 빈 클러스터와 p2가 0이면 0을 쓰는 사고(서명 지우기 · --wipe always)가 해시를
# 안 바꾼다. 그래서 p1은 150MiB 파일로 거의 채우고, p2는 1GiB 전부를 0 아닌 글자로 채운다.
export MTOOLS_SKIP_CHECK=1
make_mac() {
  local img="$1" size="$2"
  truncate -s "$size" "$img"
  perl ./mac_gpt.pl "$img" "efi:2048:411647:EFI System Partition" "apfs:411648:2508799:" \
    || { echo "FAIL: mac_gpt.pl could not write the GPT of ${img}"; exit 1; }
  if ! { mformat -i "${img}@@1M" -F -T 409600 -v EFI :: && mmd -i "${img}@@1M" ::/EFI ::/EFI/APPLE; }; then
    echo "FAIL: mtools could not make the Mac ESP on ${img}"; exit 1
  fi
  # `yes`는 head가 닫은 파이프에서 SIGPIPE로 끝난다. pipefail이면 그 141이 파이프의 값이 되어 set -e가
  # 체인을 말없이 끝내므로(DB-M0 첫 판) 이 두 줄만 pipefail을 끈 subshell에서 돈다.
  (set +o pipefail; yes tars-db-esp-filler | head -c 150M > "${WORK}/filler")
  mcopy -i "${img}@@1M" "${WORK}/filler" ::/EFI/APPLE/filler \
    || { echo "FAIL: mcopy could not fill the Mac ESP on ${img}"; exit 1; }
  rm -f "${WORK}/filler"
  (set +o pipefail; yes tars-db-apfs-pattern | head -c 1G | dd of="$img" bs=1M seek=201 conv=notrunc status=none)
}

# 19GiB. p1 + p2 뒤의 빈 자리가 약 17.8GiB라 최소(16GiB + 2MiB, disk.MIN_DISK_BYTES, TP부터)를 넘는다.
make_mac "$MAC" 19G
# 3GiB. 빈 자리가 약 1.8GiB — `--beside`가 거절해야 하는 맥이다(판정 5).
make_mac "$SMALL" 3G
truncate -s 64M "$BLANK"
echo "built a 19 GiB and a 3 GiB Mac disk (EFI 200 MiB, APFS 1 GiB) and a blank 64 MiB disk"

# DB-M1. 20GiB(TP 전에는 8GiB) "GUI 맥" — make_mac의 p1 · p2에, 디스크 유틸리티가 남기는 모양을 더한다. p2 뒤 128MiB 틈,
# p3 Basic Data FAT32 `TARS`(MiB 1353~20224), p4 Basic Data NTFS(MiB 20224~끝, 256MiB에 조금 모자란다). 표는
# mac_gpt.pl이 넷으로 다시 쓴다 — 엔트리 1 · 2의 바이트는 make_mac 때와 같다(고유 GUID가 자리에서 나온다).
# p4는 NTFS 부트 섹터의 앞(OEM 이름)과 55 AA, 그 뒤 무늬 — 설치가 p4를 건드리면 해시가 바뀐다.
make_gui_mac() {
  local img="$1"
  make_mac "$img" 20G
  perl ./mac_gpt.pl "$img" "efi:2048:411647:EFI System Partition" "apfs:411648:2508799:" \
    "basic:2770944:41418751:TARS" "basic:41418752:41943006:BOOTCAMP" \
    || { echo "FAIL: mac_gpt.pl could not write the GPT of ${img}"; exit 1; }
  mformat -i "${img}@@1353M" -F -T 38647808 -v TARS :: \
    || { echo "FAIL: mtools could not make the FAT32 TARS partition on ${img}"; exit 1; }
  (set +o pipefail; yes tars-db-ntfs-pattern | head -c 255M | dd of="$img" bs=1M seek=20224 conv=notrunc status=none)
  printf '\353\122\220NTFS    ' | dd of="$img" bs=1 seek=$((20224 * 1048576)) conv=notrunc status=none
  printf '\125\252' | dd of="$img" bs=1 seek=$((20224 * 1048576 + 510)) conv=notrunc status=none
}
make_gui_mac "$GUI"
echo "built a 20 GiB Mac disk partitioned as Disk Utility does (EFI, APFS, 128 MiB gap, FAT32 TARS, NTFS)"

# p1 · p2의 바이트와 GPT 엔트리 1 · 2(LBA 2의 앞 256바이트). sfdisk는 엔트리 3부터 덧붙이므로 LBA 2의
# 나머지와 헤더(LBA 1)는 바뀌는 것이 정상이다 — 그래서 엔트리 둘만 자른다.
mac_hashes() {
  local img="$1"
  printf 'p1 %s\n' "$(dd if="$img" bs=1M skip=1 count=200 status=none | sha256sum | cut -c1-64)"
  printf 'p2 %s\n' "$(dd if="$img" bs=1M skip=201 count=1024 status=none | sha256sum | cut -c1-64)"
  printf 'entries %s\n' "$(dd if="$img" bs=256 skip=4 count=1 status=none | sha256sum | cut -c1-64)"
}
whole_hash() { sha256sum "$1" | cut -c1-64; }

# GUI 맥에서 지정 설치가 안 건드려야 하는 것 — p1 · p2 · p4와 GPT 엔트리 1 · 2 · 4. 엔트리 3은 지워지고
# 3 · 5 · 6이 새로 생기는 것이 정상이다. 엔트리 n은 바이트 1024 + (n-1)×128이라 엔트리 4는 128 단위 11번째다.
gui_hashes() {
  local img="$1"
  mac_hashes "$img"
  printf 'p4 %s\n' "$(dd if="$img" bs=1M skip=20224 count=255 status=none | sha256sum | cut -c1-64)"
  printf 'entry4 %s\n' "$(dd if="$img" bs=128 skip=11 count=1 status=none | sha256sum | cut -c1-64)"
}

MAC_BEFORE="$(mac_hashes "$MAC")"
SMALL_BEFORE="$(whole_hash "$SMALL")"
BLANK_BEFORE="$(whole_hash "$BLANK")"
GUI_BEFORE="$(gui_hashes "$GUI")"

expect_gui_untouched() {
  local when="$1" now
  now="$(gui_hashes "$GUI")"
  if [ "$now" != "$GUI_BEFORE" ]; then
    echo "FAIL: ${when}: the GUI Mac's p1, p2, p4 or GPT entries 1, 2, 4 changed"
    echo "--- before ---"; echo "$GUI_BEFORE"
    echo "--- after ---"; echo "$now"
    exit 1
  fi
  echo "${when}: the GUI Mac's p1, p2, p4 and GPT entries 1, 2, 4 are byte for byte as built"
}

# 판정 2. 부팅이 끝날 때마다 부른다. 다르면 무엇이 달라졌는지 줄로 보인다.
expect_mac_untouched() {
  local when="$1" now
  now="$(mac_hashes "$MAC")"
  if [ "$now" != "$MAC_BEFORE" ]; then
    echo "FAIL: ${when}: the Mac partitions changed"
    echo "--- before ---"; echo "$MAC_BEFORE"
    echo "--- after ---"; echo "$now"
    exit 1
  fi
  echo "${when}: p1, p2 and GPT entries 1-2 are byte for byte as built ($(echo "$now" | sed -n 's/^p2 //p' | cut -c1-16)...)"
}

# 여기부터는 판정이 실패를 직접 다룬다. -e를 두면 아래의 대기 루프가 첫
# 불일치에서 체인을 말없이 끝낸다.
set +e

# install/check.sh의 clean · fail · boot_guest · stop_guest · send · wait_log 그대로다.
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
  # 어느 판정에서 멈췄든 맥의 바이트가 어떤지 함께 말한다. 설치기가 엉뚱한 노드를 포맷하면 단계 줄이 먼저
  # 빨개지는데, 그때도 "남의 파티션을 건드렸는가"가 가장 알고 싶은 것이다(plan의 mutation a2).
  if [ -n "$QEMU_PID" ]; then kill "$QEMU_PID" 2>/dev/null; wait "$QEMU_PID" 2>/dev/null; QEMU_PID=""; fi
  if [ "$(mac_hashes "$MAC")" != "$MAC_BEFORE" ]; then
    echo "FAIL: and the Mac partitions changed:"
    mac_hashes "$MAC"
  else
    echo "(the Mac partitions are still byte for byte as built)"
  fi
  exit 1
}

# boot_guest <이름> [qemu 인자...]. 맥 디스크가 늘 첫 NVMe(nvme0n1)다.
boot_guest() {
  local name="$1"; shift
  LOG="$(mktemp -t "dualboot-boot-${name}.XXXXXX")"   # install/check.sh와 같은 까닭(AL-M0)
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
    -drive file="$FIRST",if=none,id=mac,format=raw \
    -device nvme,drive=mac,serial=tarsmac \
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

LIST_END="tars-install <disk> --wipe  erase <disk> even if it has TARS, settings too"
CR=$(printf '\r')

wait_log() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if grep -aqF -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

# 정규식이 cleaned 로그의 줄 첫머리에 나타날 때까지. 타이핑한 명령의 에코에도 표지 글자가 있는 판정이 쓴다
# — 에코는 `sha256sum`으로 시작하므로 줄 첫머리의 표지 + 해시 64자리는 출력에만 있다.
wait_re() {
  local re="$1" limit="${2:-30}"
  for _ in $(seq 1 "$((limit * 10))"); do
    if clean | grep -aE -- "$re" >/dev/null; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

# 설치의 단계 줄이 나오는 때를 잰다. 줄을 차례로 기다리며 앞 줄에서 몇 초 걸렸는지 찍는다 —
# sfdisk · mkfs의 시간이 이 체인의 실측이다(plan 결과 절).
now_ms() { date +%s%3N; }
time_steps() {
  local limit="$1"; shift
  local prev t line
  prev="$(now_ms)"
  for line in "$@"; do
    wait_log "$line" "$limit" || return 1
    t="$(now_ms)"
    echo "  +$(( (t - prev) / 100 ))ds  ${line}"
    prev="$t"
  done
}

# ── 부팅 1: ISO + 맥 디스크 + 작은 맥 디스크 + 빈 디스크 ────────────────
echo "=== boot 1: the ISO, a Mac disk, a Mac disk with too little room and a blank disk ==="
boot_guest 1 -cdrom ../out/tars.iso \
  -drive file="$SMALL",if=none,id=small,format=raw \
  -device nvme,drive=small,serial=tarssmallmac \
  -drive file="$BLANK",if=none,id=blank,format=raw \
  -device nvme,drive=blank,serial=tarsblank \
  -drive file="$GUI",if=none,id=gui,format=raw \
  -device nvme,drive=gui,serial=tarsguimac

# 판정 1a. 목록이 GPT를 읽어 macOS와 빈 자리를 말한다(design 결정 9). 크기는 10진 버림이다 —
# 19GiB 디스크(20,401,094,656바이트, `20 GB`)의 빈 자리 17.8GiB는 19,115,540,480바이트라 `19 GB`, 3GiB 디스크의 1.8GiB는 `1 GB`.
send "tars-install"
wait_log "$LIST_END" || fail "tars-install with no arguments never finished its list" "tars-install"
if ! clean | grep -aE '^  /dev/nvme0n1 +20 GB .* internal +GPT: EFI, macOS \(APFS\); 19 GB free$' >/dev/null; then
  fail "the Mac disk was not listed with its EFI and APFS partitions and 19 GB free" "/dev/nvme0n1"
fi
if ! clean | grep -aE '^  /dev/nvme1n1 +3 GB .* internal +GPT: EFI, macOS \(APFS\); 1 GB free$' >/dev/null; then
  fail "the small Mac disk was not listed with 1 GB free" "/dev/nvme1n1"
fi
echo "the list reads the Mac disk as: $(clean | grep -aoE '^  /dev/nvme0n1 .*' | tail -1 | sed 's/.*internal *//')"

# 판정 1b. 통째 설치의 계획이 지울 것에 macOS를 이름으로 말한다(design 결정 9). 계정 질문 둘을 Enter로
# 넘기고 YES 대신 no — 아무것도 안 바꾼다(호스트가 부팅 끝에 해시로 본다).
send "tars-install /dev/nvme0n1"
wait_log "user name [tars]: " || fail "the whole-disk install never asked for the user name" "tars-install:"
send ""
wait_log "password [tars-linux]: " || fail "the whole-disk install never asked for the password" "tars-install:"
send ""
wait_log "type YES to continue: " || fail "the whole-disk install never asked for YES" "tars-install:"
send "no"
wait_log "tars-install: not confirmed; nothing was changed." || fail "'no' did not stop the whole-disk install" "tars-install:"
if ! grep -aqF "tars-install: /dev/nvme0n1 (20 GB, " "$LOG" \
  || ! clean | grep -aE 'will be erased\. it now holds: GPT: EFI, macOS \(APFS\); 19 GB free$' >/dev/null; then
  fail "the whole-disk plan did not say it erases macOS" "will be erased"
fi
echo "the whole-disk plan says it erases a disk holding macOS (APFS); answered no"

# 판정 5a. 자리가 모자란 맥 — YES를 묻기 전에 거절하고, macOS에서 자리를 내는 명령을 말한다(design 결정 3).
send "tars-install /dev/nvme1n1 --beside --yes; printf 'db-small-%s\n' done"
wait_log "db-small-done" 60 || fail "--beside on the small Mac disk never came back" "tars-install:" "db-small"
grep -aqF "tars-install: the largest free space on /dev/nvme1n1 is 1 GB; TARS needs more than 16 GiB; nothing was changed." "$LOG" \
  || fail "--beside on a Mac disk with 1 GB free was not refused by size" "tars-install:"
grep -aqF "tars-install: make room in macOS first: diskutil apfs resizeContainer disk0s2 <smaller size>" "$LOG" \
  || fail "the size refusal did not name the diskutil command" "tars-install:"
echo "--beside with 1 GB free is refused before YES and names diskutil apfs resizeContainer"

# 판정 5b. 빈 디스크(GPT가 아니다)의 --beside — 통째 설치를 쓰라고 말한다(design 결정 2).
send "tars-install /dev/nvme2n1 --beside --yes; printf 'db-blank-%s\n' done"
wait_log "db-blank-done" 60 || fail "--beside on the blank disk never came back" "tars-install:" "db-blank"
grep -aqF "tars-install: --beside needs a GPT disk; /dev/nvme2n1 holds blank. leave out --beside to give TARS the whole disk" "$LOG" \
  || fail "--beside on a blank disk was not refused" "tars-install:"
if grep -aE "tars-install: (adding the TARS partitions|writing the partition table)" "$LOG" >/dev/null; then
  fail "a refused --beside touched a partition table" "tars-install:"
fi
echo "--beside on a blank disk is refused before YES"

# 판정 1c. 설치. 단계마다 걸린 시간을 찍는다(ds = 0.1초). TCG에서 mke2fs가 4초 남짓이라(DI-M0 실측 8)
# 넉넉히 줄마다 120초를 준다.
send "tars-install /dev/nvme0n1 --beside --yes"
echo "install --beside, step by step:"
time_steps 120 \
  "keeps its partitions. it now holds: GPT: EFI, macOS (APFS); 19 GB free" \
  "tars-install: adding the TARS partitions to the partition table" \
  "tars-install: formatting /dev/nvme0n1p3 (FAT32, TARS-BOOT)" \
  "tars-install: formatting /dev/nvme0n1p4 (ext2, tars-config)" \
  "tars-install: formatting /dev/nvme0n1p5 (ext4, tars-home)" \
  "tars-install: made /home/tars" \
  "tars-install: done. remove the boot medium and reboot." \
  || fail "tars-install /dev/nvme0n1 --beside --yes did not go through its steps" \
       "tars-install:" "failed" "never appeared" "nothing was formatted"
for want in \
  "  TARS goes into the free space from MiB 1225 to MiB 19455; no other partition is touched" \
  "  p3  768 MiB  EFI System  FAT32  TARS-BOOT" \
  "  p4  256 MiB  Linux       ext2   tars-config" \
  "  p5     rest  Linux       ext4   tars-home"; do
  grep -aqF -- "$want" "$LOG" || fail "the --beside plan is missing: ${want}" "tars-install:"
done
if grep -aqF "tars-install: writing the partition table" "$LOG"; then
  fail "--beside wrote a whole new partition table" "tars-install:"
fi
echo "--beside put TARS-BOOT, TARS-CONFIG and TARS-HOME on p3, p4 and p5 in the free space"

# ── DB-M1: 디스크 유틸리티로 나눈 맥(nvme3n1) ──
# 판정 7. 목록이 GPT 디스크 밑에 파티션 줄을 달고, 받을 수 있는 FAT32에 명령을 붙인다. 디스크 줄의 글자는
# DB-M0 그대로다(Basic Data 둘은 `2 other`). 빈 자리는 128MiB 틈 = 134,217,728바이트라 `134 MB`.
# GUI 맥은 부팅 1 내내 꽂혀 있어 1a의 목록에도 줄이 있다 — 이 목록(설치 뒤의 nvme0n1을 담은 것)은 둘째 LIST_END로 기다린다.
send "tars-install"
for _ in $(seq 1 600); do
  [ "$(grep -acF -- "$LIST_END" "$LOG")" -ge 2 ] && break
  sleep 0.1
done
[ "$(grep -acF -- "$LIST_END" "$LOG")" -ge 2 ] || fail "the second list never finished" "tars-install"
for re in \
  '^  /dev/nvme3n1 +21 GB .* internal +GPT: EFI, macOS \(APFS\), 2 other; 134 MB free$' \
  '^    /dev/nvme3n1p1 +209 MB  EFI$' \
  '^    /dev/nvme3n1p2 +1 GB  macOS \(APFS\)$' \
  '^    /dev/nvme3n1p3 +19 GB  FAT32 "TARS"  <- tars-install /dev/nvme3n1p3 installs here$' \
  '^    /dev/nvme3n1p4 +268 MB  NTFS$' \
  '^    /dev/nvme0n1p2 +1 GB  macOS \(APFS\)$'; do
  clean | grep -aE -- "$re" >/dev/null || fail "the list is missing a line like: ${re}" "/dev/nvme3n1" "/dev/nvme0n1p"
done
if clean | grep -aE '^    /dev/nvme(0|1|2)n1p[0-9]+ .*installs here$' >/dev/null; then
  fail "the list offered a partition of a disk that has TARS or no FAT partition" "installs here"
fi
echo "the list shows the GUI Mac's four partitions and offers p3: $(clean | grep -aoE '^    /dev/nvme3n1p3 .*' | tail -1 | sed 's/^ *//')"

# 판정 8. 128MiB 틈뿐인 디스크의 --beside는 자리로 거절하고, 받을 수 있는 파티션을 말한다.
send "tars-install /dev/nvme3n1 --beside --yes; printf 'db-gui-beside-%s\n' done"
wait_log "db-gui-beside-done" 60 || fail "--beside on the GUI Mac never came back" "tars-install:" "db-gui-beside"
grep -aqF "tars-install: the largest free space on /dev/nvme3n1 is 134 MB; TARS needs more than 16 GiB; nothing was changed." "$LOG" \
  || fail "--beside on the GUI Mac was not refused by size" "tars-install:"
grep -aqF "tars-install: or install into the partition made for it: tars-install /dev/nvme3n1p3" "$LOG" \
  || fail "the size refusal did not point at /dev/nvme3n1p3" "tars-install:"
echo "--beside on the GUI Mac is refused by size and points at tars-install /dev/nvme3n1p3"

# 판정 10. 거절 다섯 — YES 전에, 디스크를 안 건드리고. 각 줄 뒤에 표지를 찍어 다음으로 넘어간다.
refuse() {
  local cmd="$1" want="$2" tag="$3"
  send "${cmd}; printf 'db-refuse-%s\n' ${tag}"
  wait_log "db-refuse-${tag}" 60 || fail "'${cmd}' never came back" "tars-install:"
  grep -aqF -- "$want" "$LOG" || fail "'${cmd}' was not refused with: ${want}" "tars-install:"
  echo "refused: ${cmd}"
}
refuse "tars-install /dev/nvme3n1p2 --yes" "tars-install: /dev/nvme3n1p2 is an APFS or HFS+ partition and may hold macOS; nothing was changed." apfs
refuse "tars-install /dev/nvme3n1p1 --yes" "tars-install: /dev/nvme3n1p1 is an EFI System partition the firmware boots from; nothing was changed" efi
refuse "tars-install /dev/nvme3n1p4 --yes" "tars-install: /dev/nvme3n1p4 holds NTFS (Windows or Boot Camp)" ntfs
refuse "tars-install /dev/nvme3n1p3 --beside --yes" "tars-install: /dev/nvme3n1p3 is a partition; tars-install /dev/nvme3n1p3 installs into it, without --beside or --wipe" flags
refuse "tars-install /dev/nvme0n1p2 --yes" "tars-install: /dev/nvme0n1 already has TARS partitions" installed
if grep -aqF "tars-install: deleting the partition" "$LOG"; then
  fail "a refused partition install deleted a partition" "tars-install: deleting"
fi

# 판정 9. 지정 설치. p3을 지우고, p2 뒤의 틈까지 붙인 MiB 1225~20224에 셋을 놓는다. sfdisk는 지운 3과 빈 5 · 6을
# 매긴다 — 번호가 띄어 있어도 이름으로 찾는다.
# 이 부팅의 둘째 설치라 `done.`은 1c가 이미 찍었다 — 그 줄을 기다리면 설치 도중에 끝난 것으로 읽혀 stop_guest가
# ESP 복사 중의 QEMU를 끈다(DB-M1 첫 판, 부팅 5가 UEFI Shell로 떨어졌다). 명령 뒤의 표지를 마지막으로 기다린다.
send "tars-install /dev/nvme3n1p3 --yes; printf 'db-take-%s\n' finished"
echo "install into /dev/nvme3n1p3, step by step:"
time_steps 120 \
  "tars-install: /dev/nvme3n1p3 (FAT32 \"TARS\", 19 GB) will be erased, the files on it too." \
  "tars-install: deleting the partition p3" \
  "tars-install: adding the TARS partitions to the partition table" \
  "tars-install: formatting /dev/nvme3n1p3 (FAT32, TARS-BOOT)" \
  "tars-install: formatting /dev/nvme3n1p5 (ext2, tars-config)" \
  "tars-install: formatting /dev/nvme3n1p6 (ext4, tars-home)" \
  "db-take-finished" \
  || fail "tars-install /dev/nvme3n1p3 --yes did not go through its steps" \
       "tars-install:" "failed" "never appeared" "nothing was formatted"
[ "$(grep -acF "tars-install: done. remove the boot medium and reboot." "$LOG")" -eq 2 ] \
  || fail "tars-install /dev/nvme3n1p3 --yes did not say done" "tars-install:" "failed"
for want in \
  "  TARS goes into /dev/nvme3n1p3 and the free space next to it, from MiB 1225 to MiB 20224; no other partition is touched" \
  "  p3  768 MiB  EFI System  FAT32  TARS-BOOT" \
  "  p5  256 MiB  Linux       ext2   tars-config" \
  "  p6     rest  Linux       ext4   tars-home"; do
  grep -aqF -- "$want" "$LOG" || fail "the partition install plan is missing: ${want}" "tars-install:"
done
echo "tars-install /dev/nvme3n1p3 put TARS on p3, p5 and p6 in MiB 1225-20224"

stop_guest

# 판정 2와 5. 설치 뒤의 첫 판정이 바이트다 — 목록의 `TARS installed`는 부팅 3이 본다. 이 순서라야 p2에
# 쓰는 사고가 다른 판정보다 먼저 이 줄에 걸린다(plan의 mutation a).
expect_mac_untouched "after boot 1 (--beside install)"
[ "$(whole_hash "$SMALL")" = "$SMALL_BEFORE" ] || { echo "FAIL: the refused small Mac disk changed"; exit 1; }
[ "$(whole_hash "$BLANK")" = "$BLANK_BEFORE" ] || { echo "FAIL: the refused blank disk changed"; exit 1; }
echo "the small Mac disk and the blank disk are byte for byte as built"
expect_gui_untouched "after boot 1 (install into /dev/nvme3n1p3)"

# ── 부팅 2: 맥 디스크만 ────────────────────────────────────────────────
echo "=== boot 2: the Mac disk alone ==="
boot_guest 2

# 판정 3. -cdrom이 없고, BOOTX64.EFI가 있는 FAT는 p3뿐이다(p1은 EFI/APPLE만). OVMF가 removable 경로를
# 파티션마다 찾아 p3에서 Limine을 띄웠고, 그 conf가 표지를 달았다. init은 첫 여덟 파티션 중에서 이름이
# 아니라 라벨로 p4 · p5를 골랐다 — 후보가 셋이면 여기서 `among 56 candidates`가 찍힌다.
if ! grep -aE "Kernel command line: .*tars\.installed( |${CR}|\$)" "$LOG" >/dev/null; then
  fail "the Mac disk did not boot TARS-BOOT with tars.installed" "Kernel command line"
fi
for want in \
  "tars-init: config storage /dev/nvme0n1p4 (label tars-config)" \
  "tars-init: mounted ext2 at /config" \
  "tars-init: loaded /config/tars.conf" \
  "tars-init: home storage /dev/nvme0n1p5 (label tars-home)" \
  "tars-init: user tars uid 1000 home /home/tars"; do
  grep -aqF -- "$want" "$LOG" || fail "boot 2 is missing: ${want}" \
    "tars-init: config storage" "tars-init: home storage" "tars-init: no disk labelled"
done
echo "booted from TARS-BOOT on p3; config from /dev/nvme0n1p4, home from /dev/nvme0n1p5"

send "echo kept > /config/db-marker && printf 'db-marker-%s\n' written"
wait_log "db-marker-written" || fail "could not write the marker onto p4" "db-marker"
echo "wrote /config/db-marker"

stop_guest
expect_mac_untouched "after boot 2 (TARS from the Mac disk)"

# ── 부팅 3: ISO + 설치된 맥 디스크 — 갱신, 그리고 --beside --wipe ────────
echo "=== boot 3: the ISO and the installed Mac disk: update, then --beside --wipe ==="
boot_guest 3 -cdrom ../out/tars.iso

# 판정 4. 갱신은 TARS-BOOT(p3)만 쓴다. p4는 게스트 안에서 해시로 본다 — 256MiB라 TCG에서도 몇 초다.
# p1 · p2는 부팅 끝에 호스트가 본다.
send "tars-install"
wait_log "$LIST_END" || fail "tars-install never finished its list" "tars-install"
clean | grep -aE '^  /dev/nvme0n1 +20 GB .* internal +TARS installed$' >/dev/null \
  || fail "the installed Mac disk was not listed as TARS installed" "/dev/nvme0n1"
send "sha256sum /dev/nvme0n1p4 | sed 's/^/db-p4-before /'"
wait_re '^db-p4-before [0-9a-f]{64}' 120 || fail "could not hash p4 before the update" "db-p4"
send "tars-install /dev/nvme0n1 --yes"
wait_log "tars-install: updated. remove the boot medium and reboot." 120 \
  || fail "the update of the Mac disk never said updated" "tars-install:" "failed"
for want in \
  "already has TARS. p3 will be updated, p4 (your settings) is kept." \
  "  p5 (tars-home) <- not opened" \
  "--beside --wipe erases the TARS partitions instead, your home too; --wipe alone erases the whole disk"; do
  grep -aqF -- "$want" "$LOG" || fail "the update plan is missing: ${want}" "tars-install:"
done
grep -aE "tars-install: p3 has [1-9][0-9]* bytes free" "$LOG" >/dev/null \
  || fail "the update did not read the free space of p3" "tars-install: p"
if grep -aE "tars-install: (writing the partition table|adding the TARS partitions|formatting)" "$LOG" >/dev/null; then
  fail "the update touched the partition table or formatted something" "tars-install:"
fi
send "sha256sum /dev/nvme0n1p4 | sed 's/^/db-p4-after /'"
wait_re '^db-p4-after [0-9a-f]{64}' 120 || fail "could not hash p4 after the update" "db-p4"
P4_BEFORE="$(clean | grep -aoE '^db-p4-before [0-9a-f]{64}' | tail -1 | cut -d' ' -f2)"
P4_AFTER="$(clean | grep -aoE '^db-p4-after [0-9a-f]{64}' | tail -1 | cut -d' ' -f2)"
if [ -z "$P4_BEFORE" ] || [ "$P4_BEFORE" != "$P4_AFTER" ]; then
  fail "p4 changed across the update ('${P4_BEFORE}' -> '${P4_AFTER}')" "db-p4"
fi
echo "the update wrote p3 only: p4 hashes the same (${P4_BEFORE:0:16}...) before and after"

# 판정 6. --beside --wipe는 TARS 이름의 셋만 지우고 그 자리에 다시 깐다(design 결정 7).
send "tars-install /dev/nvme0n1 --beside --wipe --yes"
echo "install --beside --wipe, step by step:"
time_steps 120 \
  "  the TARS partitions are erased first, your settings and home too: p3 p4 p5" \
  "tars-install: deleting the TARS partitions p3 p4 p5" \
  "tars-install: adding the TARS partitions to the partition table" \
  "tars-install: formatting /dev/nvme0n1p3 (FAT32, TARS-BOOT)" \
  "tars-install: formatting /dev/nvme0n1p5 (ext4, tars-home)" \
  "tars-install: done. remove the boot medium and reboot." \
  || fail "--beside --wipe did not go through its steps" "tars-install:" "failed" "nothing was formatted"
grep -aqF "keeps its partitions. it now holds: GPT: EFI, macOS (APFS), TARS; no free space" "$LOG" \
  || fail "the --beside --wipe plan did not describe the disk" "keeps its partitions"
echo "--beside --wipe deleted p3-p5 and laid them down again in the same place"

stop_guest
expect_mac_untouched "after boot 3 (update and --beside --wipe)"

# ── 부팅 4: 맥 디스크만, --beside --wipe 뒤 ─────────────────────────────
echo "=== boot 4: the Mac disk alone, after --beside --wipe ==="
boot_guest 4
for want in \
  "tars-init: config storage /dev/nvme0n1p4 (label tars-config)" \
  "tars-init: loaded /config/tars.conf" \
  "tars-init: home storage /dev/nvme0n1p5 (label tars-home)"; do
  grep -aqF -- "$want" "$LOG" || fail "boot 4 is missing: ${want}" \
    "tars-init: config storage" "tars-init: home storage" "tars-init: no disk labelled"
done
send "test -e /config/db-marker || printf 'db-marker-%s\n' gone"
wait_log "db-marker-gone" || fail "the marker survived --beside --wipe" "db-marker"
echo "after --beside --wipe the settings are fresh (no marker), still on p4 with home on p5"

stop_guest
expect_mac_untouched "after boot 4"

# ── 부팅 5: GUI 맥만 (DB-M1) ─────────────────────────────────────────────
# 판정 9의 끝. OVMF가 BOOTX64.EFI를 가진 p3에서 떴고, init이 첫 여덟 파티션 중 라벨로 p5 · p6을 골랐다.
echo "=== boot 5: the GUI Mac disk alone ==="
FIRST="$GUI"
boot_guest 5
if ! grep -aE "Kernel command line: .*tars\.installed( |${CR}|\$)" "$LOG" >/dev/null; then
  fail "the GUI Mac did not boot TARS-BOOT with tars.installed" "Kernel command line"
fi
for want in \
  "tars-init: config storage /dev/nvme0n1p5 (label tars-config)" \
  "tars-init: loaded /config/tars.conf" \
  "tars-init: home storage /dev/nvme0n1p6 (label tars-home)" \
  "tars-init: user tars uid 1000 home /home/tars"; do
  grep -aqF -- "$want" "$LOG" || fail "boot 5 is missing: ${want}" \
    "tars-init: config storage" "tars-init: home storage" "tars-init: no disk labelled"
done
echo "booted from TARS-BOOT on the GUI Mac's p3; config from p5, home from p6"
stop_guest
expect_gui_untouched "after boot 5"

echo "PASS"
exit 0
