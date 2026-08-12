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
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

qemu-system-x86_64 \
  -cdrom ../out/tars.iso \
  -serial file:"$LOG" \
  -display none \
  -no-reboot &
QEMU_PID=$!

# limine이 ISO에서 53MB짜리 initrd를 읽어 커널에 넘기는 데만도 시간이 걸린다
# (TF-M2 이후 initrd에 42MB짜리 terminal 바이너리가 들어갔다). 에뮬레이션
# 환경에서는 더 느리다 — 고정 timeout 15초로는 커널이 첫 줄을 찍기도 전에
# 잘렸다. 배너가 나오면 즉시 끝내고, 안 나오면 최대 120초 기다린다.
FOUND=0
WAITED=0
for _ in $(seq 1 120); do
  if grep -q "Welcome to fish, the friendly interactive shell" "$LOG"; then
    FOUND=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done

cat "$LOG"

if [ "$FOUND" = "1" ]; then
  echo "Boot reached the fish banner after ~${WAITED}s"
  echo "PASS"
  exit 0
fi

echo "FAIL: expected fish banner not found (waited ${WAITED}s)"
exit 1
