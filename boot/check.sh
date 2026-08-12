#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

(cd ../kernel && ./build.sh)
(cd ../init && cargo build --release)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
./build.sh
./make_iso.sh

LOG="$(mktemp)"
timeout 15 qemu-system-x86_64 \
  -cdrom ../out/tars.iso \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "Welcome to fish, the friendly interactive shell" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected fish banner not found"
exit 1
