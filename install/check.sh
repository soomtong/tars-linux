#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# DI-M1 · M2: 열세번째 체인. ISO로 부팅한 기계가 자기를 내장 디스크에
# 설치하고, 그 디스크만으로 다시 뜨고, 새 ISO로 갱신해도 설정이 남는가
# (DI design 결정 9).
#
# 부팅 여섯이 같은 NVMe 이미지를 잇달아 쓴다.
#   1  ISO + 빈 NVMe       tars-install의 목록 · 거절 · 설치
#   2  NVMe만              -cdrom 없이 뜨고 init이 p2를 잡는다. 마커를 쓴다
#   3  ISO + 설치된 NVMe   init이 p2를 안 잡는다 · TARS installed · 갱신
#   4  NVMe만              갱신을 넘어 마커가 남았다
#   5  ISO + 설치된 NVMe   --wipe로 통째로 다시 설치
#   6  NVMe만              마커가 사라졌고 설정이 첫 부팅처럼 새로 깔린다
#   7  같은 디스크를 USB로  -kernel · delay_use=3. init이 늦은 p2를 기다려 잡는다(DC-M1)
#
# 왜 sendkey가 아니라 시리얼 FIFO인가. 다른 체인들은 terminal의 화면
# 줄(`terminal: screen>`)로 판정하는데 이 체인이 볼 것은 tars-install이
# 찍는 여러 줄의 목록이다. 콘솔 셸(ttyS0)에 FIFO로 한 줄씩 넣으면 그 출력이
# 시리얼 로그에 그대로 남는다. DI-M0 하네스가 이 모양으로 부팅 셋을 돌렸다.
# 그래서 USB 키보드는 물려만 둔다 — machine 체인과 같은 기계를 만들기 위해서다.
#
# 왜 -monitor가 없는가. 이 체인은 키를 안 보낸다. 그리고 QEMU를 kill로 끈다 —
# 전원 버튼이 아니다. tars-install이 done 전에 sync와 umount를 이미 했다는
# 것(design 위험 3)을 부팅 2가 증명하려면 끄는 쪽이 친절하면 안 된다.

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
# 2GiB. 배치(256MiB + 1GiB)가 들어가고 나머지가 비는 가장 작은 정수다.
# truncate라 호스트 디스크를 실제로는 거의 안 쓴다.
truncate -s 2G "$DISK"

QEMU_PID=""
LOG=""
FIFO=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  exec 4>&- 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# 여기부터는 판정이 실패를 직접 다룬다. -e를 두면 아래의 대기 루프가 첫
# 불일치에서 체인을 말없이 끝낸다.
set +e

# limine의 글자마다 섞인 커서 이동과 fish의 색 escape를 걷고 \r을 줄바꿈으로.
# 행 첫머리에 기대는 판정(목록의 `  /dev/nvme0n1`)은 이것을 거친 파일로 한다.
# 타이핑한 명령줄의 에코에도 `/dev/nvme0n1`이 있으므로 행 첫머리의 공백 둘이
# 출력과 에코를 가른다(project_gate_screen_echo와 같은 종류).
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
# 고정 timeout을 안 쓰는 이유는 machine 체인과 같다 — OVMF 초기화가 느리고
# 게이트의 부하가 회차마다 다르다.
boot_guest() {
  local name="$1"; shift
  LOG="${WORK}/boot-${name}.log"
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
  # fish가 프롬프트를 그릴 시간. 그 전에 넣은 줄도 tty가 들고 있다가
  # 넘겨주지만, DI-M0 하네스가 3초로 부팅 셋을 문제없이 돌렸다.
  sleep 3
}

stop_guest() {
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""
  exec 4>&-
  rm -f "$FIFO"
}

# 콘솔 셸에 한 줄.
send() { printf '%s\n' "$1" >&4; }

# tars-install 목록의 마지막 줄(install.zig의 printUsage). 목록이 끝났다는 표지다.
LIST_END="tars-install <disk> --wipe  erase <disk> even if it has TARS, settings too"

# 판정 9 · 13이 보는 raw $LOG는 줄마다 \r\n으로 끝난다(clean은 화면 판정에만
# 쓴다). GNU grep -E는 패턴 안의 \r을 캐리지리턴으로 안 풀어 주므로, 토큰
# 경계 정규식의 "끝"은 $가 아니라 실제 문자로 넣는다.
CR=$(printf '\r')

# 로그에 고정 문자열이 나타날 때까지 기다린다. 0이면 나왔다.
wait_log() {
  local want="$1" limit="${2:-30}" i
  for i in $(seq 1 "$((limit * 10))"); do
    if grep -aqF -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

# ── 부팅 1: ISO + 빈 NVMe ──────────────────────────────────────────────
echo "=== boot 1: the ISO and a blank NVMe ==="
# 둘째 NVMe는 DC-M2의 임시 디스크다. 논리 섹터가 4096바이트(4Kn)이고 판정
# 4a~4c만 쓴다. 설치 대상(nvme0n1)과 따로 둬서, 옛 코드가 YES를 잘못 읽어도
# 지워지는 것이 이것뿐이게 한다. 64MiB라 배치가 안 들어가 sfdisk에서 멈춘다.
SCRATCH="${WORK}/scratch-4kn.img"
truncate -s 64M "$SCRATCH"
boot_guest 1 -cdrom ../out/tars.iso \
  -drive file="$SCRATCH",if=none,id=scratch,format=raw \
  -device nvme,drive=scratch,serial=tarsscratch,logical_block_size=4096,physical_block_size=4096

# 판정 1. 목록. 쓰는 법의 마지막 줄이 목록의 끝이다.
send "tars-install"
wait_log "$LIST_END" \
  || fail "tars-install with no arguments never finished its list" "tars-install"

# 판정 2. 매체를 찾았고 이름이 TARS다. 이 한 줄이 셋을 본다 — sr0을 앞머리로
# ISO9660으로 읽었다 · 붙여서 limine.conf를 찾았다 · make_iso.sh의 -V TARS.
if ! grep -aqF "tars-install: boot medium /dev/sr0 (iso9660 TARS," "$LOG"; then
  fail "the boot medium was not found as /dev/sr0 labelled TARS" \
    "tars-install: boot medium" "tars-install: no boot medium"
fi
echo "the boot medium is /dev/sr0, volume TARS"

# 판정 3. 빈 NVMe가 목록에 blank로 보인다.
if ! clean | grep -aE '^  /dev/nvme0n1 +[0-9]+ GB .* internal +blank$' >/dev/null; then
  fail "the blank NVMe was not listed as an internal blank disk" "/dev/nvme0n1"
fi
echo "the blank NVMe is listed as internal, blank"

# 판정 4. YES가 아니면 아무것도 안 한다. 디스크를 통째로 지우는 명령의
# 문지기이고, 게이트가 늘 --yes로 치므로 이 자리가 아니면 영영 안 밟힌다.
send "tars-install /dev/nvme0n1"
wait_log "type YES to continue: " \
  || fail "tars-install never asked for YES" "tars-install:"
send "no"
wait_log "tars-install: not confirmed; nothing was changed." \
  || fail "answering 'no' did not stop tars-install" "tars-install:"
# 그리고 정말로 안 건드렸다. 목록을 한 번 더 찍어 blank가 둘이 됐는지 센다.
send "tars-install"
for _ in $(seq 1 300); do
  [ "$(clean | grep -acE '^  /dev/nvme0n1 .* blank$')" -ge 2 ] && break
  sleep 0.1
done
if [ "$(clean | grep -acE '^  /dev/nvme0n1 .* blank$')" -lt 2 ]; then
  fail "after 'no', the NVMe was no longer blank" "/dev/nvme0n1"
fi
echo "answering 'no' left the disk blank"

# 판정 4a (DC-M2). 4Kn 디스크의 GPT. 헤더가 512가 아니라 4096에 있어서 전에는
# 보호 MBR만 보여 `foreign (mbr)`로 읽혔다 — 설치된 4Kn 디스크가 TARS installed로
# 안 보여 갱신 대신 새 설치로 갈 자리다. GPT는 게스트의 진짜 sfdisk가 만든다.
send "echo dc-lbs-\$(cat /sys/block/nvme1n1/queue/logical_block_size)"
wait_log "dc-lbs-4096" \
  || fail "the scratch NVMe is not 4Kn; QEMU ignored logical_block_size" "dc-lbs-"
send "printf 'label: gpt\n' | sfdisk -q /dev/nvme1n1 && printf 'dc-4kn-%s\n' labelled"
wait_log "dc-4kn-labelled" \
  || fail "sfdisk could not label the 4Kn scratch disk" "sfdisk" "dc-4kn"
send "tars-install"
for _ in $(seq 1 300); do
  clean | grep -aE '^  /dev/nvme1n1 .* foreign \(gpt\)$' >/dev/null && break
  sleep 0.1
done
if ! clean | grep -aE '^  /dev/nvme1n1 .* foreign \(gpt\)$' >/dev/null; then
  fail "a GPT on a 4Kn disk was not listed as foreign (gpt)" "/dev/nvme1n1"
fi
echo "a GPT on a 4096-byte-sector disk reads as gpt"

# 판정 4b (DC-M2). YES를 줄로 읽는다. 파이프로 `YES`와 ` please\n`를 1초 사이를
# 두고 보내면, read 한 번으로 받던 전 코드는 `YES`만 보고 확인으로 읽었다.
# 지금은 `YES please`를 다 모아 거절한다. not confirmed가 판정 4에 이어 둘째다.
send "sh -c '(printf YES; sleep 1; printf \" please\\n\") | tars-install /dev/nvme1n1'; printf 'dc-split-%s\n' done"
wait_log "dc-split-done" 30 \
  || fail "the split YES never came back to the shell" "tars-install:" "dc-split"
if [ "$(grep -acF "tars-install: not confirmed; nothing was changed." "$LOG")" -lt 2 ]; then
  fail "'YES' then ' please' arriving apart was taken as YES" \
    "tars-install:" "writing the partition table"
fi
echo "a YES split across two writes is read as the whole line, and refused"

# 판정 4c (DC-M2). 넘치는 에러 줄은 잘려서라도 나온다. 600글자 디스크 이름의
# `is not a disk` 줄은 512바이트 버퍼를 넘어서, 전에는 통째로 사라지고 종료
# 코드만 남았다. 타이핑한 줄의 에코는 `tars-install /dev/`(콜론 없음)라 안 섞인다.
LONG="$(printf 'x%.0s' $(seq 1 600))"
send "tars-install /dev/${LONG}; printf 'dc-long-%s\n' done"
wait_log "dc-long-done" \
  || fail "the long argument never came back to the shell" "dc-long"
if ! clean | grep -aE '^tars-install: /dev/x+\.\.\.$' >/dev/null; then
  fail "the error for a 600-character argument was not printed, clipped" "tars-install: /dev/x"
fi
echo "an error line longer than its buffer is printed clipped, not dropped"

# 판정 5. 설치. mke2fs가 4초, sfdisk가 3.5초(DI-M0 실측 8)라 TCG에서
# 넉넉히 120초를 준다.
send "tars-install /dev/nvme0n1 --yes"
if ! wait_log "tars-install: done. remove the boot medium and reboot." 120; then
  fail "tars-install /dev/nvme0n1 --yes never said done" \
    "tars-install:" "failed" "never appeared"
fi
# 넷이 다 갔다. 크기까지는 안 본다 — 부팅 2가 커널과 initrd를 실제로 읽는다.
for f in boot/bzImage boot/initrd.cpio boot/limine/limine.conf EFI/BOOT/BOOTX64.EFI; do
  if ! clean | grep -aE "^  ${f} [0-9]+ bytes$" >/dev/null; then
    fail "tars-install did not report copying ${f}" "tars-install: copying"
  fi
done
echo "tars-install wrote the disk and copied the four boot files"

stop_guest

# ── 부팅 2: NVMe만 ─────────────────────────────────────────────────────
echo "=== boot 2: the NVMe alone ==="
boot_guest 2

# 판정 6. 이 milestone의 심장이다. -cdrom이 없으니 ESP 말고는 뜰 곳이 없고,
# init이 설정 디스크를 디스크 전체가 아니라 p2에서 라벨로 찾았다 —
# storage.zig의 파티션 후보(DI design 결정 6)가 이 한 줄에 걸려 있다.
WANT_DISK="tars-init: config storage /dev/nvme0n1p2 (label tars-config)"
if ! grep -aqF "$WANT_DISK" "$LOG"; then
  fail "init did not pick p2 of the installed NVMe as its config disk" \
    "tars-init: config storage" "tars-init: no disk labelled"
fi
echo "booted without the ISO; init found its config on /dev/nvme0n1p2"

# 판정 7. 붙었고, 빈 p2에 첫 부팅의 씨앗을 심었다. mke2fs가 만든 것이 init이
# 쓸 수 있는 ext2라는 것까지다.
if ! grep -aq "tars-init: mounted ext2 at /config" "$LOG"; then
  fail "p2 was picked but never mounted" "tars-init: failed to mount"
fi
if ! grep -aq "tars-init: created /config/tars.conf" "$LOG"; then
  fail "the fresh config partition did not get its first-boot tars.conf" \
    "tars-init: loaded /config" "tars-init: created"
fi
echo "the config partition mounted and took the first-boot seed"

# 판정 8. 설치된 기계에서 tars-install은 매체가 없다고 말한다(design 결정 4).
# QEMU가 빈 sr0을 붙여 두므로(DI-M0 실측 9) 노드가 있어도 매체가 아니라는
# 것을 이 줄이 본다. 그리고 자기 디스크를 TARS installed로 읽는다 — p1을
# 붙여 bzImage를 보는 isInstalled가 진짜 FAT32에서 도는 첫 자리다.
send "tars-install"
wait_log "$LIST_END" \
  || fail "tars-install never finished its list on the installed machine" "tars-install"
if ! grep -aqF "tars-install: no boot medium found" "$LOG"; then
  fail "on the installed machine tars-install still claimed a boot medium" \
    "tars-install: boot medium"
fi
if ! clean | grep -aE '^  /dev/nvme0n1 +[0-9]+ GB .* internal +TARS installed$' >/dev/null; then
  fail "the installed NVMe was not listed as TARS installed" "/dev/nvme0n1"
fi
echo "on the installed machine there is no boot medium, and the disk reads as TARS installed"

# 판정 9. 이 부팅이 표지를 달고 떴다. tars-install이 ESP의 limine.conf에
# 붙인 것이다(disk.espConf). 커널이 부팅 때 cmdline을 찍는 줄로 본다 —
# 타이핑한 명령의 에코가 섞일 일이 없다.
if ! grep -aE "Kernel command line: .*tars\.installed( |${CR}|\$)" "$LOG" >/dev/null; then
  fail "the installed disk did not boot with tars.installed on its command line" \
    "Kernel command line"
fi
echo "the installed disk booted with tars.installed"

# 마커. 부팅 4가 이것이 갱신을 넘었는지, 부팅 6이 --wipe로 사라졌는지 본다.
# 출력(di-marker-written)이 타이핑한 줄에 없는 모양이라 에코와 안 섞인다.
send "echo kept > /config/di-marker && printf 'di-marker-%s\n' written"
wait_log "di-marker-written" \
  || fail "could not write the marker onto the config partition" "di-marker"
echo "wrote /config/di-marker"

stop_guest

# ── 부팅 3: ISO + 설치된 NVMe ──────────────────────────────────────────
echo "=== boot 3: the ISO and the installed NVMe ==="
boot_guest 3 -cdrom ../out/tars.iso

# 판정 10. ISO로 뜬 부팅은 파티션을 안 본다. 표지가 없어서다 — 설치된 p2를
# /config에 붙이면 --wipe가 "in use"로 막힌다(DI-M2 plan의 "정한 것" 1).
# 14는 storage.DISKS의 길이, 디스크 전체의 수다. 42면 파티션까지 봤다는 뜻이다.
if ! grep -aqF "tars-init: no disk labelled tars-* among 14 candidates" "$LOG"; then
  fail "booting the ISO, init looked at partitions or picked the installed p2" \
    "tars-init: config storage" "tars-init: no disk labelled"
fi
echo "booted from the ISO, init left the installed p2 alone"

# 판정 11. 목록이 설치된 디스크를 알아본다.
send "tars-install"
wait_log "$LIST_END" \
  || fail "tars-install never finished its list next to an installed disk" "tars-install"
if ! clean | grep -aE '^  /dev/nvme0n1 +[0-9]+ GB .* internal +TARS installed$' >/dev/null; then
  fail "the installed NVMe was not listed as TARS installed" "/dev/nvme0n1"
fi
echo "the installed NVMe is listed as TARS installed"

# 판정 12. 갱신. 계획 문구가 update이고 updated로 끝난다(design 결정 8).
send "tars-install /dev/nvme0n1 --yes"
if ! wait_log "tars-install: updated. remove the boot medium and reboot." 120; then
  fail "updating the installed NVMe never said updated" \
    "tars-install:" "failed"
fi
if ! grep -aqF "already has TARS. p1 will be updated, p2 (your settings) is kept." "$LOG"; then
  fail "the update did not say it keeps p2" "tars-install:"
fi
# "파티션도 다시 나누고 updated도 찍는" 퇴행 하나를 막는다. p2를 안 건드렸다는 증명은 판정 14다.
if grep -aqF "tars-install: writing the partition table" "$LOG"; then
  fail "the update repartitioned the disk" "tars-install:"
fi
# 넷을 다 다시 썼다. 이것이 없으면 아무것도 안 쓰는 갱신도 부팅 4를 지난다 —
# 부팅 1이 쓴 ESP가 그대로 뜨기 때문이다. 로그가 부팅 3의 것이라 부팅 1의
# 복사 줄은 안 섞인다.
for f in boot/bzImage boot/initrd.cpio boot/limine/limine.conf EFI/BOOT/BOOTX64.EFI; do
  if ! clean | grep -aE "^  ${f} [0-9]+ bytes$" >/dev/null; then
    fail "the update did not copy ${f}" "tars-install: copying"
  fi
done
echo "the update rewrote p1 only"

stop_guest

# ── 부팅 4: NVMe만, 갱신 뒤 ────────────────────────────────────────────
echo "=== boot 4: the NVMe alone, after the update ==="
boot_guest 4

# 판정 13. 갱신한 ESP로 떴고(표지가 다시 붙었다) p2를 다시 잡았으며,
# 그 p2는 새것이 아니다 — 씨앗을 다시 깔지 않고 읽었다.
if ! grep -aE "Kernel command line: .*tars\.installed( |${CR}|\$)" "$LOG" >/dev/null; then
  fail "after the update the disk booted without tars.installed" \
    "Kernel command line"
fi
if ! grep -aqF "$WANT_DISK" "$LOG"; then
  fail "after the update init did not pick p2" \
    "tars-init: config storage" "tars-init: no disk labelled"
fi
if ! grep -aq "tars-init: loaded /config/tars.conf" "$LOG"; then
  fail "after the update tars.conf was not the one from before" \
    "tars-init: loaded /config" "tars-init: created"
fi

# 판정 14. 이 milestone의 심장이다 — 마커가 갱신을 넘었다.
send "printf 'di-marker:'; cat /config/di-marker"
wait_log "di-marker:kept" \
  || fail "the marker did not survive the update" "di-marker"
echo "the marker survived the update"

stop_guest

# ── 부팅 5: ISO + 설치된 NVMe, --wipe ──────────────────────────────────
echo "=== boot 5: the ISO and the installed NVMe, --wipe ==="
boot_guest 5 -cdrom ../out/tars.iso

# 판정 15. --wipe는 갱신 대신 통째로 지운다. 부팅 3이 p2를 안 붙인 것이
# 여기서 쓰인다 — 붙였으면 sfdisk가 "in use"로 거부한다.
send "tars-install /dev/nvme0n1 --wipe --yes"
if ! wait_log "tars-install: done. remove the boot medium and reboot." 120; then
  fail "tars-install /dev/nvme0n1 --wipe --yes never said done" \
    "tars-install:" "failed" "in use"
fi
if ! grep -aqF "the settings now on p2 are erased too" "$LOG"; then
  fail "--wipe did not warn that it erases the settings" "tars-install:"
fi
echo "--wipe reinstalled the disk"

stop_guest

# ── 부팅 6: NVMe만, --wipe 뒤 ──────────────────────────────────────────
echo "=== boot 6: the NVMe alone, after --wipe ==="
boot_guest 6

# 판정 16. 새 p2다. 씨앗이 다시 깔렸고 마커가 없다.
if ! grep -aqF "$WANT_DISK" "$LOG"; then
  fail "after --wipe init did not pick p2" \
    "tars-init: config storage" "tars-init: no disk labelled"
fi
if ! grep -aq "tars-init: created /config/tars.conf" "$LOG"; then
  fail "after --wipe the config partition was not fresh" \
    "tars-init: loaded /config" "tars-init: created"
fi
send "test -e /config/di-marker || printf 'di-marker-%s\n' gone"
wait_log "di-marker-gone" \
  || fail "the marker survived --wipe" "di-marker"
echo "--wipe left a fresh config partition"

stop_guest

# ── 부팅 7: 설치된 디스크를 USB로, 늦게 (DC-M1) ────────────────────────
#
# 커널은 PID 1을 띄우기 전에 디스크를 기다려 주지 않는다(DC 확인 2). 그런데
# 게이트에서는 그 틈이 안 보인다 — TCG 위에서 42MB initramfs를 푸는 1.7초
# 동안 NVMe가 다 붙어 버린다(DC-M0 실측 2). 그래서 틈을 일부러 벌린다.
# usb-storage는 장치를 붙이고 delay_use만큼 쉰 뒤에 SCSI 스캔을 하므로, 3초를
# 주면 sda2가 init이 처음 훑은 뒤에 생긴다(DC-M0 실측 1: 1.72초 뒤).
#
# 왜 -kernel인가. cmdline에 delay_use를 넣을 자리가 필요하고, tars.installed도
# ESP의 limine.conf가 아니라 여기서 준다. init이 보는 것은 /proc/cmdline의
# 토큰뿐이라 어디서 왔는지는 모른다. 디스크는 부팅 6이 --wipe로 막 만든 그것이다.
boot_kernel_usb() {
  local name="$1" cmdline="$2"
  LOG="${WORK}/boot-${name}.log"
  FIFO="${WORK}/boot-${name}.fifo"
  rm -f "$FIFO"; mkfifo "$FIFO"
  exec 4<>"$FIFO"
  qemu-system-x86_64 \
    -machine q35 \
    -nic none \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "$cmdline" \
    -device qemu-xhci,id=xhci \
    -drive file="$DISK",if=none,id=late,format=raw \
    -device usb-storage,bus=xhci.0,drive=late \
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
      "PANIC" "tars-init"
  fi
  echo "boot ${name}: console shell up after ${waited}s"
}

echo "=== boot 7: the installed disk over USB, three seconds late ==="
boot_kernel_usb 7 "console=ttyS0 tars.installed usb-storage.delay_use=3"

# 판정 17. 이 milestone의 심장이다. init이 처음 훑었을 때 sda2는 없었고, 기다려서
# 잡았다. appeared after가 없으면 기다림 없이 잡은 것이라 틈이 안 벌어진
# 판이고(판정이 아무것도 증명 안 한다), config storage가 없으면 기다림이 없거나
# 너무 짧다 — 기다림을 뺀 init은 여기서 among 42 candidates를 찍는다.
if ! grep -aqF "tars-init: config storage appeared after" "$LOG"; then
  fail "init did not have to wait for the late USB disk, or never found it" \
    "tars-init: config storage" "tars-init: waited" "tars-init: no disk labelled" "sda: sda1"
fi
if ! grep -aqF "tars-init: config storage /dev/sda2 (label tars-config)" "$LOG"; then
  fail "init waited but did not pick p2 of the late USB disk" \
    "tars-init: config storage" "tars-init: no disk labelled"
fi
if ! grep -aq "tars-init: mounted ext2 at /config" "$LOG"; then
  fail "the late config partition was picked but never mounted" "tars-init: failed to mount"
fi
echo "init waited $(grep -aoE 'appeared after [0-9]+ms' "$LOG" | head -1 | sed 's/appeared after //') for the late USB disk and mounted its p2"

stop_guest

echo "PASS"
exit 0
