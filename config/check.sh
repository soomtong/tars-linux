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
# 부팅"이라는 전제가 무너지고, 아래 1차 부팅이 검증할 seeding 경로가 두 번
# 다시 실행되지 않은 채 게이트가 자기를 속이게 된다.
#
# 반대로 **두 부팅 사이에서는 절대 다시 부르지 않는다.** 그게 이 milestone의
# 검증 그 자체다 — 1차가 쓴 것을 2차가 읽어야 한다.
if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

LOG1="$(mktemp)"
LOG2="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# 부팅 한 번. $1 = 시리얼 로그 파일, $2 = 기다릴 마커.
#
# QEMU 인자는 CP-M0와 같다(TF 체인 + -drive). 두 부팅이 **같은 이미지 파일**을
# 가리키는 것이 핵심이고, 그래서 이 함수는 이미지 경로를 인자로 받지 않는다.
boot_once() {
  local log="$1"
  local marker="$2"

  qemu-system-x86_64 \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -drive file="${REPO_ROOT}/out/config.img",if=virtio,format=raw \
    -display none \
    -serial file:"$log" \
    -no-reboot &
  QEMU_PID=$!

  # 고정 sleep 대신 로그 폴링. 마커가 나오면 즉시 끝낸다.
  local found=0
  for _ in $(seq 1 120); do
    if grep -q "$marker" "$log"; then
      found=1
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  # 마커를 봤든 못 봤든 여기서 QEMU를 확실히 끝낸다. wait까지 하는 이유는
  # 다음 부팅이 **같은 디스크 이미지**를 열기 때문이다 — 두 QEMU가 같은
  # 이미지를 동시에 쓰면 파일시스템이 깨지고, 그 실패는 이 milestone이
  # 검증하려는 것과 구분이 안 되는 모양으로 나타난다.
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""

  [ "$found" = "1" ]
}

# 실패했을 때 "어디까지 갔는가"를 보여준다. 마커 하나하나가 부팅의 단계다.
report_failure() {
  local log="$1"
  local msg="$2"
  echo "FAIL: ${msg}"
  echo "--- markers ---"
  local marker
  for marker in \
    "\[vda\]" \
    "tars-init: mounted ext2 at /config" \
    "tars-init: failed to mount ext2 at /config" \
    "tars-init: created /config/tars.conf" \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: config shell="; do
    if grep -q "$marker" "$log"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- tail ---"
  tail -n 60 "$log"
  exit 1
}

# ---------------------------------------------------------------- 1차 부팅
# 빈 디스크. init이 /config/tars.conf를 만들어야 한다.
echo "=== boot 1/2: empty disk, init should seed the config file ==="
if ! boot_once "$LOG1" "tars-init: created /config/tars.conf"; then
  report_failure "$LOG1" "first boot did not create /config/tars.conf"
fi

if ! grep -q "\[vda\]" "$LOG1"; then
  report_failure "$LOG1" "kernel never reported a [vda] block device on the first boot"
fi

# 빈 디스크였는데 loaded가 나왔다면 make_disk.sh가 안 돌았거나 이전 회차의
# 이미지가 남아 있는 것이다. 그 상태로는 seeding 경로가 검증되지 않는다.
if grep -q "tars-init: loaded /config/tars.conf" "$LOG1"; then
  report_failure "$LOG1" "first boot loaded an existing config; the disk was not empty"
fi

if grep -q "Attempted to kill init" "$LOG1"; then
  report_failure "$LOG1" "kernel panicked because PID 1 exited on the first boot"
fi
echo "boot 1: init seeded /config/tars.conf on a fresh disk"

# ---------------------------------------------------------------- 2차 부팅
# 같은 이미지를 그대로 다시 물린다. make_disk.sh를 부르지 않는다.
#
# 1차 부팅은 언마운트 없이 죽었으므로 ext2 슈퍼블록이 "not clean" 상태다.
# 리눅스 ext2는 그래도 마운트해 주고 경고만 찍는다(EXT2-fs ... mounting
# unchecked fs). 그 경고가 보이는 것이 정상이다.
echo "=== boot 2/2: same image, init should load what boot 1 wrote ==="
if ! boot_once "$LOG2" "tars-init: loaded /config/tars.conf"; then
  report_failure "$LOG2" "second boot did not load /config/tars.conf"
fi

# **이 검사가 이 게이트의 핵심이다.** 2차에서 또 created가 나왔다면 1차가 쓴
# 파일이 살아남지 못한 것이다(동기 마운트가 안 먹었거나, 이미지를 다시
# 구웠거나, 두 부팅이 서로 다른 이미지를 봤거나).
if grep -q "tars-init: created /config/tars.conf" "$LOG2"; then
  report_failure "$LOG2" "second boot re-created the config file; nothing persisted"
fi

# 파일을 열었다는 것과 내용이 파싱됐다는 것은 다르다. 기본 씨앗은 fish다.
if ! grep -q "tars-init: config shell=fish" "$LOG2"; then
  report_failure "$LOG2" "second boot did not parse shell=fish out of the config file"
fi

if grep -q "Attempted to kill init" "$LOG2"; then
  report_failure "$LOG2" "kernel panicked because PID 1 exited on the second boot"
fi
echo "boot 2: init loaded the config written by boot 1 (shell=fish)"

# 정보성. ext2가 "not clean"이라고 말하는 것은 예상된 결과이므로 실패로 보지
# 않되, 보이면 남긴다.
if grep -q "mounting unchecked fs" "$LOG2"; then
  echo "note: ext2 reported an unclean superblock on boot 2 (expected: boot 1 was killed)"
fi

# 성공해도 시리얼 로그의 init 줄은 남긴다. TF 체인이 "--- init log ---"를
# 찍는 것과 같은 이유다 — 루트 게이트가 만드는 통합 로그에서 이 체인이 무엇을
# 봤는지 나중에 확인할 수 있어야 한다(CP-M0에서 이걸 빼먹어 부팅 3회가 통합
# 로그에 없었다).
echo "--- init log (boot 1) ---"
grep 'tars-init:' "$LOG1" || true
echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG2" || true

echo "PASS"
exit 0
