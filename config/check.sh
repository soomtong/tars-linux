#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# 빌드 순서는 TF 체인과 같다(kernel → init → terminal → initrd).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 디스크는 매 회차 새로 굽는다. 남은 이미지를 재사용하면 "빈 디스크로 첫
# 부팅"이라는 전제가 무너지고, CP-M1이 검증할 seeding 경로가 두 번 다시
# 실행되지 않은 채 게이트가 자기를 속이게 된다.
if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# TF 체인과 같은 인자에 -drive 하나가 더 붙었다.
#   if=virtio  → QEMU가 virtio-blk-pci 장치를 만들어 붙인다. 게스트에서는
#                /dev/vda로 보인다(파티션이 없으므로 vda1은 없다).
#   format=raw → 이미지가 qcow2가 아니라 날 것이라고 못박는다. 안 적으면
#                QEMU가 내용을 보고 추측하며 경고를 낸다.
qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="${REPO_ROOT}/out/config.img",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!

# 고정 sleep 대신 로그 폴링. 마운트 성공 줄이 나오면 즉시 끝낸다.
MOUNTED=0
for _ in $(seq 1 120); do
  if grep -q "tars-init: mounted ext2 at /config" "$LOG"; then
    MOUNTED=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [ "$MOUNTED" != "1" ]; then
  echo "FAIL: init did not mount the config disk"
  echo "--- markers ---"
  for marker in \
    "virtio_blk" \
    "tars-init: mounted devtmpfs at /dev" \
    "tars-init: mounted ext2 at /config" \
    "tars-init: failed to mount ext2 at /config"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  tail -n 60 "$LOG"
  exit 1
fi
echo "init mounted the config disk at /config"

# 커널이 디스크를 인식했는지도 따로 본다. 마운트가 됐다면 당연히 됐겠지만,
# 실패했을 때 "드라이버가 없다"와 "파일시스템이 안 맞는다"를 가르는 줄이다.
if ! grep -q "\[vda\]" "$LOG"; then
  echo "FAIL: kernel never reported a [vda] block device"
  tail -n 60 "$LOG"
  exit 1
fi
echo "kernel probed the virtio-blk device as vda"

if grep -q "Attempted to kill init" "$LOG"; then
  echo "FAIL: kernel panicked because PID 1 exited"
  tail -n 60 "$LOG"
  exit 1
fi

# 성공해도 시리얼 로그의 init 줄은 남긴다. TF 체인이 "--- init log ---"를
# 찍는 것과 같은 이유다 — 루트 게이트가 만드는 통합 로그에서 이 체인이 무엇을
# 봤는지 나중에 확인할 수 있어야 한다. 안 찍으면 통합 로그에는 요약 세 줄만
# 남고 부팅 9회 중 3회는 흔적이 없다(CP-M0 실측).
echo "--- init log ---"
grep 'tars-init:' "$LOG" || true

echo "PASS"
exit 0
