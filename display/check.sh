#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && cargo build --release); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../kms && cargo build --release); then
  echo "FAIL: kms build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45454
SCREENSHOT="$(mktemp /tmp/df-m0-XXXXXX.ppm)"
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
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

MONITOR_READY=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then
    MONITOR_READY=1
    break
  fi
  sleep 0.5
done

if [ "$MONITOR_READY" != "1" ]; then
  echo "FAIL: could not connect to QEMU monitor on port ${MONITOR_PORT}"
  cat "$LOG"
  exit 1
fi

# virtio-gpu가 기본 scanout을 초기화할 시간을 준다(경험적으로 선택한 값 —
# Step 3에서 FAIL이면 가장 먼저 늘려볼 값).
sleep 5
echo "screendump ${SCREENSHOT}" >&3
sleep 1
exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$SCREENSHOT" ]; then
  echo "FAIL: screendump did not produce a file at ${SCREENSHOT}"
  cat "$LOG"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IDENTIFY=(magick identify)
else
  IDENTIFY=(identify)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$SCREENSHOT" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${SCREENSHOT}: ${DIMENSIONS}"
  exit 1
}

echo "Captured screendump: ${SCREENSHOT} (${DIMENSIONS})"

if [[ ! "$DIMENSIONS" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "FAIL: unexpected ImageMagick output: ${DIMENSIONS}"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  CONVERT=(magick)
else
  CONVERT=(convert)
fi

PIXEL=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 1x1+10+10 +repage txt:- 2>&1) || {
  echo "FAIL: ImageMagick could not extract pixel at (10,10): ${PIXEL}"
  exit 1
}

echo "Pixel at (10,10): ${PIXEL}"

if echo "$PIXEL" | grep -qi '#FF0000'; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected red (#FF0000) at (10,10), got: ${PIXEL}"
exit 1
