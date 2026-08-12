#!/usr/bin/env bash
#
# [은퇴됨 — 2026-08-12, TF-M4]
#
# 이 스크립트는 부팅 후 화면 (10,10) 픽셀이 kms 바이너리가 칠한 빨강
# (#FF0000)인지 검사한다. TF-M2에서 kernel/make_initrd.sh가 initrd에 kms 대신
# terminal을 넣도록 바뀌었고 init/src/main.rs도 /terminal을 fork하므로,
# 부팅된 시스템에는 이제 kms가 존재하지 않는다 — 이 검사는 실행하면 반드시
# FAIL한다.
#
# 되살리려면 커널 cmdline으로 kms/terminal 중 무엇을 띄울지 고르는 부팅 모드
# 스위치가 필요한데, 이 스크립트가 검증하던 DRM/KMS present 경로는
# terminal/check.sh가 매 회차 실제로 픽셀을 띄우며 이미 검증한다. 그래서 루트
# check.sh의 체인 목록에서 빠졌다(TF-M4 plan Architecture 1번 참고).
#
# 파일과 kms/ 크레이트를 남겨두는 것은 Rust로 쓴 DRM 참조 구현으로서의
# 가치 때문이다. 실행하지 말 것.
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
