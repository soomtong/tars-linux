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

mkdir -p zig-out

if ! (cd . && zig build-exe src/main.zig src/stb_truetype_impl.c -I vendor -lc -lm -mcpu=baseline -femit-bin=zig-out/terminal); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45455
SCREENSHOT="$(mktemp /tmp/tf-m1-XXXXXX.ppm)"
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

sleep 30
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
  CONVERT=(magick)
else
  IDENTIFY=(identify)
  CONVERT=(convert)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$SCREENSHOT" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${SCREENSHOT}: ${DIMENSIONS}"
  exit 1
}
echo "Captured screendump: ${SCREENSHOT} (${DIMENSIONS})"

PIXEL=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 1x1+5+5 +repage txt:- 2>&1) || {
  echo "FAIL: ImageMagick could not extract pixel at (5,5): ${PIXEL}"
  exit 1
}
echo "Pixel at (5,5): ${PIXEL}"

if ! echo "$PIXEL" | grep -qi '#102030'; then
  echo "FAIL: expected background (#102030) at (5,5), got: ${PIXEL}"
  tail -n 60 "$LOG"
  exit 1
fi

UNIQUE_COLORS=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 72x16+20+20 +repage \
  -format "%k" info: 2>&1) || {
  echo "FAIL: ImageMagick could not count colors in glyph region: ${UNIQUE_COLORS}"
  exit 1
}
echo "Unique colors in glyph region (20,20)-(92,36): ${UNIQUE_COLORS}"

if [ "$UNIQUE_COLORS" -lt 2 ]; then
  echo "FAIL: glyph region has only ${UNIQUE_COLORS} unique color(s), expected >= 2 (background + text)"
  tail -n 60 "$LOG"
  exit 1
fi

echo "PASS"
exit 0
