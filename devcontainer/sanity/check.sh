#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
make

LOG="$(mktemp)"
timeout 5 qemu-system-x86_64 \
  -kernel sanity.elf \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "tars: sanity check ok" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected marker not found"
exit 1

#
#작성 후 실행 권한도 추가해주세요.
#
# chmod +x devcontainer/sanity/check.sh
#
