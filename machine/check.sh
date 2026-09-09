#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# RM-M0: 열번째 체인. 아홉 체인이 전부 QEMU의 기본 BIOS(SeaBIOS)로 뜨는데
# 실머신 노트북은 예외 없이 UEFI다. 이 체인은 **같은 ISO를 UEFI 펌웨어로**
# 부팅해서, 노트북에서 픽셀이 나올 경로가 실제로 서 있는지를 본다.
#
# 왜 -cdrom인가: 아홉 중 여덟은 -kernel로 커널을 직접 물려 limine을 통째로
# 건너뛴다. 그러면 부트로더도 UEFI도 안 지난다. 부트로더를 지나는 체인은
# boot/check.sh 하나뿐이었고 이것이 둘째다.
#
# 왜 virtio-gpu를 안 물리는가: 그것이 이 체인의 요점이다. 픽셀이 EFI GOP
# 프레임버퍼에서만 오고, 그것을 /dev/dri/card0으로 바꾸는 것이 simpledrm이다.
# 노트북에서도 정확히 이 경로다 — DRM_I915도 AMDGPU도 안 켰다(design 결정 3).

(cd ../kernel && ./build.sh)
(cd ../init && zig build)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
(cd ../boot && ./build.sh)
(cd ../boot && ./make_iso.sh)

# OVMF는 ovmf 패키지가 깔아 두는 미리 빌드된 EDK II다(devcontainer/Dockerfile).
# CODE는 읽기 전용으로 물려도 되지만 **VARS는 쓰기가 되어야 한다** — 펌웨어가
# NVRAM 변수에 부트 항목을 쓰는 자리라 읽기 전용이면 부팅할 것을 못 고른다.
# 그래서 매 실행마다 복사한다.
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
if [ ! -f "$OVMF_CODE" ]; then
  echo "FAIL: ${OVMF_CODE} not found; is the devcontainer image current?" >&2
  exit 1
fi

LOG="$(mktemp)"
VARS="$(mktemp)"
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$VARS"

# RM-M1: NVMe로 물릴 디스크. **이 milestone은 이것을 마운트하지 않는다** —
# init이 /dev/vda를 하드코딩하고 있어서(init/src/main.zig:65) 못 찾는다.
# 여기서 보는 것은 "커널이 NVMe 컨트롤러를 잡는다"까지이고, 그 위에 파일을
# 두고 읽는 것은 RM-M2다.
DISK="$(mktemp)"
dd if=/dev/zero of="$DISK" bs=1M count=8 status=none
mkfs.ext2 -q -F "$DISK"

MONITOR_PORT=45471
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# q35는 PCIe 기계다. 그래서 장치들이 legacy INTx가 아니라 MSI로 인터럽트를
# 받고, 커널이 그것을 협상한 증거가 _OSC 줄에 남는다.
#
# **i8042=off가 이 체인의 핵심이다**(RM-M1, design 결정 7). PS/2 컨트롤러를
# 남겨 두면 init이 capability로 첫 키보드를 고를 때 그쪽을 잡아서, usb-kbd가
# 있으나 없으나 게이트가 초록이다 — **USB 경로가 아예 안 밟힌다.** 끄고 나면
# 이 게스트에 키보드가 USB 하나뿐이라 판정이 진짜가 된다.
# IS-M1 실측 4와 같은 종류다: 같은 것을 두 층이 지킬 때 위층을 확인하려면
# 아래층을 먼저 꺼야 한다.
qemu-system-x86_64 \
  -machine q35,i8042=off \
  -m 512 \
  -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,unit=1,file="$VARS" \
  -cdrom ../out/tars.iso \
  -device qemu-xhci,id=xhci \
  -device usb-kbd,bus=xhci.0 \
  -drive file="$DISK",if=none,id=cfg,format=raw \
  -device nvme,drive=cfg,serial=tarscfg \
  -serial file:"$LOG" \
  -display none \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

# 고정 timeout을 안 쓴다. OVMF의 펌웨어 초기화가 SeaBIOS보다 오래 걸리고
# 게이트의 부하가 회차마다 다르다. boot/check.sh가 쓰는 수법 그대로 —
# 배너가 나오면 즉시 끝내고 안 나오면 최대 120초 기다린다.
FOUND=0
WAITED=0
for _ in $(seq 1 120); do
  if grep -aq "Welcome to fish, the friendly interactive shell" "$LOG"; then
    FOUND=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done

# 배너 뒤에 터미널이 첫 프레임을 그리고 격자를 찍을 시간을 준다.
if [ "$FOUND" = "1" ]; then
  for _ in $(seq 1 30); do
    if grep -aq "terminal: grid " "$LOG"; then
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

cat "$LOG"

# limine이 시리얼에 쓰는 글자에는 **글자마다** 커서 이동 escape가 끼어 있다
# (`P` ESC[01;02H `A` ESC[01;03H `N` ...). 그래서 limine의 PANIC은 grep으로
# 아예 안 잡힌다 — 음성 확인에서 실제로 문맥 줄이 비어 나왔다. escape를 먼저
# 걷어내야 글자들이 도로 붙는다.
#
# 우리 쪽 줄(tars-init:, terminal:)에는 escape가 안 붙으므로 위의 판정들은
# 이 처리 없이도 맞는다. 걷어내기가 필요한 것은 **실패했을 때 부트로더가 한
# 말을 사람이 읽는 자리**뿐이다.
denoise() {
  sed -e 's/\x1b\[[0-9;=?]*[a-zA-Z]//g' "$LOG"
}

fail() {
  echo "FAIL: $1"
  shift
  for pattern in "$@"; do
    denoise | grep -a "$pattern" | head -3 | sed 's/^/  /'
  done
  exit 1
}

if [ "$FOUND" != "1" ]; then
  # 여기서 limine의 PANIC이 보인다. boot/limine.conf의 `serial: yes`가 없으면
  # 이 실패가 "조용한 timeout"으로만 보이고 원인까지 가는 길이 없다.
  fail "expected fish banner not found (waited ${WAITED}s)" "PANIC" "Kernel panic"
fi
echo "UEFI boot reached the fish banner after ~${WAITED}s"

# 판정 1. 펌웨어가 정말 UEFI다. 이 줄이 없으면 pflash 인자가 안 먹어서
# SeaBIOS로 떴다는 뜻이고, 그러면 이 체인이 boot/check.sh와 같은 것을 두 번
# 보는 것이 된다 — 초록인데 아무것도 새로 안 보는 최악의 실패다.
if ! grep -aq "efi: EFI v" "$LOG"; then
  fail "the kernel never reported an EFI firmware; it likely booted via SeaBIOS" \
    "Linux version" "BIOS"
fi
echo "firmware is UEFI ($(grep -a 'efi: EFI v' "$LOG" | head -1 | sed 's/.*efi: //'))"

# 판정 2. GOP 프레임버퍼가 KMS 장치가 됐다. SYSFB_SIMPLEFB가 screen_info에서
# simple-framebuffer 플랫폼 장치를 만들고 DRM_SIMPLEDRM이 거기에 붙는다.
# 둘 중 하나만 빠져도 이 줄이 없다.
if ! grep -aq "Initialized simpledrm" "$LOG"; then
  fail "simpledrm never bound to the EFI framebuffer" \
    "simple-framebuffer" "drm" "dri/card0"
fi

# 판정 3. terminal이 그 장치를 열고 격자를 정했다. 수를 정확히 못으로 박는
# 것에 뜻이 있다 — 이것이 "펌웨어가 잡아 둔 네이티브 모드를 그대로 쓴다"를
# 정면으로 보는 유일한 방법이다(design 결정 3). 실기에서는 이 자리가 패널의
# 네이티브 해상도가 된다.
#
# 1024x768(virtio-gpu 체인들의 값)이 아니라 1280x800인 것은 OVMF의 GOP
# 기본 모드이기 때문이다. **다른 체인의 격자 수를 베껴 오면 안 된다.**
WANT_GRID="terminal: grid 155x47 (fb 1280x800)"
if ! grep -aqF "$WANT_GRID" "$LOG"; then
  fail "want '${WANT_GRID}' but the terminal reported something else" \
    "terminal: grid" "Initialized simpledrm"
fi
echo "terminal drew on the GOP framebuffer at the firmware's native mode"

# card0이 있었으므로 감독자가 포기할 이유가 없다. boot/check.sh가 -vga none으로
# 보는 것의 반대편이고, 둘이 한 쌍이다.
if grep -aq "tars-init: giving up on terminal" "$LOG"; then
  fail "init gave up on the terminal even though simpledrm came up" \
    "tars-init: started terminal" "dri/card0"
fi

# ── RM-M1: 노트북 장치 넷 ──────────────────────────────────────────────

# 판정 4. PCIe가 MSI를 협상했다. q35의 _OSC 협상 결과에 MSI가 들어 있어야
# 장치들이 legacy INTx 대신 MSI로 인터럽트를 받는다. CONFIG_PCI_MSI가
# 꺼져 있으면 커널이 그 비트를 아예 요청하지 않는다.
if ! grep -a "_OSC: OS supports" "$LOG" | grep -aq "MSI"; then
  fail "the kernel never negotiated MSI with the PCIe host bridge" \
    "_OSC" "PCI"
fi
echo "PCIe negotiated MSI"

# 판정 5. xHCI 컨트롤러가 붙었다.
if ! grep -aq "xHCI Host Controller" "$LOG"; then
  fail "the xHCI controller never came up" "xhci" "usb"
fi

# 판정 6. **이 milestone의 심장이다.** HID가 evdev까지 왔고, init이 고른
# 키보드가 USB다. i8042=off이므로 PS/2가 없고, 그래서 이 줄이 "USB 경로가
# 통째로 서 있다"를 말한다 — 커널의 HID 층 · evdev · init의 capability 탐색이
# 한 줄에 다 걸려 있다.
if ! grep -a "tars-init: keyboard device" "$LOG" | grep -aq "USB Keyboard"; then
  fail "init did not pick the USB keyboard (is i8042 still on? did USB_HID build?)" \
    "tars-init: keyboard device" "input: " "hid-generic"
fi
echo "init picked the USB keyboard with no PS/2 in the machine"

# 판정 7. NVMe 컨트롤러를 잡았다. 마운트는 안 한다 — init이 /dev/vda를
# 하드코딩하고 있어서 못 읽는다(RM-M2가 그것을 넓힌다).
if ! grep -aq "nvme nvme0: pci function" "$LOG"; then
  fail "the NVMe controller never came up" "nvme" "pci"
fi
echo "the NVMe controller came up"

# ── 그리고 실제로 친다 ─────────────────────────────────────────────────
#
# "장치가 보인다"와 "키가 화면에 닿는다"는 다른 일이다. 앞의 판정 여섯은
# 전부 커널이 만든 줄이거나 init이 연 결과이고, 여기부터가 **USB 키보드로
# 친 글자가 PTY를 지나 격자에 그려지는가**다. CM·HI·SH의 체인이 전부
# 이렇게 판정한다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor" "terminal: grid"

echo "=== typing 'usb' on the USB keyboard ==="
for k in u s b; do
  echo "sendkey $k" >&3
  sleep 0.4
done
sleep 2

# 마지막 프레임의 화면 줄에 그 세 글자가 있어야 한다. 셸의 입력줄에 에코된다.
if ! grep -a "terminal: screen>" "$LOG" | tail -20 | grep -aq "usb"; then
  fail "keys typed on the USB keyboard never reached the grid" \
    "terminal: screen>" "terminal: key>"
fi
echo "keys from the USB keyboard reached the grid"

echo "PASS"
exit 0
