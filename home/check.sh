#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# HP-M0: 스물다섯째 체인. 설치기가 셋째 파티션 `tars-home`(ext4, 나머지 전부)을
# 만들고, 설치된 디스크로 뜬 init이 `/config`(ext2 · sync) 옆에 `/home`(ext4 ·
# async)을 붙이며, 재부팅을 넘어 홈의 파일이 남고, 남의 ext4는 라벨로 거르는가
# (HP design 결정 11 — 판정 1 · 2 · 3 · 5 · 6 · 7. 판정 4 · 8은 M1 · M2).
#
# 부팅 셋이 같은 NVMe 이미지를 잇달아 쓴다.
#   1  ISO + 빈 5GiB NVMe + 3GiB NVMe   3GiB는 거절(판정 7) · 그 위에 ext4 굽기 시간(실측 3) · 설치 · 배치(판정 1)
#   2  NVMe만                           init이 p2와 p3를 잡는다(판정 2) · 마운트 옵션(판정 3) · 홈에 마커를 쓴다
#   3  NVMe + 남의 ext4(debian-home)     마커가 남았다(판정 5) · 남의 디스크는 홈이 아니다(판정 6)
#
# 모양은 install/check.sh의 것이다 — 시리얼 FIFO로 콘솔 셸에 한 줄씩 넣고 그
# 출력을 로그에서 읽는다. 키를 안 보내므로 monitor · QMP가 없다. RP-M0의 예약
# 범위에서 이 체인 몫은 45497(monitor) · 45498(QMP)이고 지금은 둘 다 안 연다.
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
# 5GiB. 최소 4GiB + 2MiB(disk.MIN_DISK_BYTES)가 들어가는 가장 작은 정수다.
truncate -s 5G "$DISK"
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
echo "=== boot 1: the ISO, a blank 5 GiB NVMe and a 3 GiB NVMe ==="
boot_guest 1 -cdrom ../out/tars.iso \
  -drive file="$SMALL",if=none,id=small,format=raw \
  -device nvme,drive=small,serial=tarssmall

# 판정 7. 3GiB는 YES 전에 거절된다. formatSize는 10진 버림이라 3,221,225,472는
# `3 GB`다. 아무것도 안 썼다 — 파티션 테이블 줄이 없다.
send "tars-install /dev/nvme1n1 --yes; printf 'hp-small-%s\n' done"
wait_log "hp-small-done" \
  || fail "tars-install on the 3 GiB disk never came back to the shell" "tars-install:" "hp-small"
if ! grep -aqF "tars-install: /dev/nvme1n1 is 3 GB; TARS needs more than 4 GiB" "$LOG"; then
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

# 설치. mke2fs가 하나 더 늘었다.
send "sh -c 'T0=\$(date +%s%N); tars-install /dev/nvme0n1 --yes; T1=\$(date +%s%N); printf \"hp-install-%s-ms\\n\" \$(( (T1-T0)/1000000 ))'"
if ! wait_log_re "hp-install-[0-9]+-ms" 180; then
  fail "tars-install /dev/nvme0n1 --yes never came back" "tars-install:" "failed" "never appeared"
fi
if ! grep -aqF "tars-install: done. remove the boot medium and reboot." "$LOG"; then
  fail "tars-install did not say done" "tars-install:"
fi
if ! grep -aqF "tars-install: formatting /dev/nvme0n1p3 (ext4, tars-home)" "$LOG"; then
  fail "tars-install did not format p3 as ext4 tars-home" "tars-install: formatting"
fi
echo "tars-install wrote the disk in $(grep -aoE 'hp-install-[0-9]+-ms' "$LOG" | head -1 | tr -dc 0-9) ms, p3 formatted as ext4 tars-home"

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
boot_guest 2

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
echo "/home/hp-marker survived the reboot"

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

stop_guest

echo "PASS"
exit 0
