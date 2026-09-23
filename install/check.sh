#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# DI-M1: 열세번째 체인. ISO로 부팅한 기계가 자기를 내장 디스크에 설치하고,
# 그 디스크만으로 다시 뜨는가(DI design 결정 9).
#
# 부팅 둘이 같은 NVMe 이미지를 잇달아 쓴다.
#   1  ISO + 빈 NVMe   tars-install의 목록 · 거절 · 설치
#   2  NVMe만          -cdrom 없이 뜨고 init이 p2를 설정 디스크로 잡는다
# 설치를 넘어 설정이 남는 것(부팅 3)은 DI-M2가 더한다.
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
boot_guest 1 -cdrom ../out/tars.iso

# 판정 1. 목록. 쓰는 법의 마지막 줄이 목록의 끝이다.
send "tars-install"
wait_log "tars-install <disk> --yes  same, without asking" \
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
# 것을 이 줄이 본다.
send "tars-install"
wait_log "tars-install <disk> --yes  same, without asking" \
  || fail "tars-install never finished its list on the installed machine" "tars-install"
if ! grep -aqF "tars-install: no boot medium found" "$LOG"; then
  fail "on the installed machine tars-install still claimed a boot medium" \
    "tars-install: boot medium"
fi
echo "on the installed machine there is no boot medium to install from"

stop_guest

echo "PASS"
exit 0
