#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./build.sh
./make_initrd.sh

LOG="$(mktemp)"
timeout 15 qemu-system-x86_64 \
  -kernel build/arch/x86/boot/bzImage \
  -initrd initrd.cpio \
  -append "console=ttyS0" \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "Kernel panic - not syncing: No working init found" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected panic message not found"
exit 1
