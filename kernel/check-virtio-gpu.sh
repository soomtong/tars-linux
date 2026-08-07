#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LOG="$(mktemp)"
timeout 15 qemu-system-x86_64 \
  -kernel build/arch/x86/boot/bzImage \
  -initrd initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "tars-init: /dev/dri/card0 exists" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: /dev/dri/card0 was not found by tars-init"
exit 1
