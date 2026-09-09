#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# RM-M0: 열번째 체인. 아홉 체인이 전부 QEMU의 기본 BIOS(SeaBIOS)로 뜨는데
# 실머신 노트북은 예외 없이 UEFI다. 이 체인은 **같은 ISO를 UEFI 펌웨어로**
# 부팅해서, 노트북에서 픽셀이 나올 경로가 실제로 서 있는지를 본다.
#
# 왜 -cdrom인가: 아홉 중 여덟은 -kernel로 커널을 직접 물려 limine을 통째로
# 건너뛴다. 그러면 부트로더도 UEFI도 안 지난다. 부트로더를 지나는 체인은
# boot/check.sh 하나뿐이었고 이것이 둘째다.
#
# 왜 virtio-gpu를 안 물리는가: 그것이 이 체인의 요점이다. 픽셀이 EFI GOP
# 프레임버퍼에서만 오고, 그것을 /dev/dri/card0으로 바꾸는 것이 simpledrm이다.
# 노트북에서도 정확히 이 경로다 — DRM_I915도 AMDGPU도 안 켰다(design 결정 3).

(cd ../kernel && ./build.sh)
(cd ../init && zig build)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
(cd ../boot && ./build.sh)
(cd ../boot && ./make_iso.sh)

# OVMF는 ovmf 패키지가 깔아 두는 미리 빌드된 EDK II다(devcontainer/Dockerfile).
# CODE는 읽기 전용으로 물려도 되지만 **VARS는 쓰기가 되어야 한다** — 펌웨어가
# NVRAM 변수에 부트 항목을 쓰는 자리라 읽기 전용이면 부팅할 것을 못 고른다.
# 그래서 매 실행마다 복사한다.
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
if [ ! -f "$OVMF_CODE" ]; then
  echo "FAIL: ${OVMF_CODE} not found; is the devcontainer image current?" >&2
  exit 1
fi

LOG="$(mktemp)"
VARS="$(mktemp)"
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$VARS"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# q35는 PCIe 기계다. RM-M1이 여기에 MSI와 USB와 NVMe를 얹으므로 M0에서부터
# q35로 시작한다 — 기계를 나중에 바꾸면 M1의 실패가 "기계 탓인가 장치 탓인가"로
# 갈리지 않는다.
qemu-system-x86_64 \
  -machine q35 \
  -m 512 \
  -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,unit=1,file="$VARS" \
  -cdrom ../out/tars.iso \
  -serial file:"$LOG" \
  -display none \
  -no-reboot &
QEMU_PID=$!

# 고정 timeout을 안 쓴다. OVMF의 펌웨어 초기화가 SeaBIOS보다 오래 걸리고
# 게이트의 부하가 회차마다 다르다. boot/check.sh가 쓰는 수법 그대로 —
# 배너가 나오면 즉시 끝내고 안 나오면 최대 120초 기다린다.
FOUND=0
WAITED=0
for _ in $(seq 1 120); do
  if grep -aq "Welcome to fish, the friendly interactive shell" "$LOG"; then
    FOUND=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done

# 배너 뒤에 터미널이 첫 프레임을 그리고 격자를 찍을 시간을 준다.
if [ "$FOUND" = "1" ]; then
  for _ in $(seq 1 30); do
    if grep -aq "terminal: grid " "$LOG"; then
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

cat "$LOG"

# limine이 시리얼에 쓰는 글자에는 **글자마다** 커서 이동 escape가 끼어 있다
# (`P` ESC[01;02H `A` ESC[01;03H `N` ...). 그래서 limine의 PANIC은 grep으로
# 아예 안 잡힌다 — 음성 확인에서 실제로 문맥 줄이 비어 나왔다. escape를 먼저
# 걷어내야 글자들이 도로 붙는다.
#
# 우리 쪽 줄(tars-init:, terminal:)에는 escape가 안 붙으므로 위의 판정들은
# 이 처리 없이도 맞는다. 걷어내기가 필요한 것은 **실패했을 때 부트로더가 한
# 말을 사람이 읽는 자리**뿐이다.
denoise() {
  sed -e 's/\x1b\[[0-9;=?]*[a-zA-Z]//g' "$LOG"
}

fail() {
  echo "FAIL: $1"
  shift
  for pattern in "$@"; do
    denoise | grep -a "$pattern" | head -3 | sed 's/^/  /'
  done
  exit 1
}

if [ "$FOUND" != "1" ]; then
  # 여기서 limine의 PANIC이 보인다. boot/limine.conf의 `serial: yes`가 없으면
  # 이 실패가 "조용한 timeout"으로만 보이고 원인까지 가는 길이 없다.
  fail "expected fish banner not found (waited ${WAITED}s)" "PANIC" "Kernel panic"
fi
echo "UEFI boot reached the fish banner after ~${WAITED}s"

# 판정 1. 펌웨어가 정말 UEFI다. 이 줄이 없으면 pflash 인자가 안 먹어서
# SeaBIOS로 떴다는 뜻이고, 그러면 이 체인이 boot/check.sh와 같은 것을 두 번
# 보는 것이 된다 — 초록인데 아무것도 새로 안 보는 최악의 실패다.
if ! grep -aq "efi: EFI v" "$LOG"; then
  fail "the kernel never reported an EFI firmware; it likely booted via SeaBIOS" \
    "Linux version" "BIOS"
fi
echo "firmware is UEFI ($(grep -a 'efi: EFI v' "$LOG" | head -1 | sed 's/.*efi: //'))"

# 판정 2. GOP 프레임버퍼가 KMS 장치가 됐다. SYSFB_SIMPLEFB가 screen_info에서
# simple-framebuffer 플랫폼 장치를 만들고 DRM_SIMPLEDRM이 거기에 붙는다.
# 둘 중 하나만 빠져도 이 줄이 없다.
if ! grep -aq "Initialized simpledrm" "$LOG"; then
  fail "simpledrm never bound to the EFI framebuffer" \
    "simple-framebuffer" "drm" "dri/card0"
fi

# 판정 3. terminal이 그 장치를 열고 격자를 정했다. 수를 정확히 못으로 박는
# 것에 뜻이 있다 — 이것이 "펌웨어가 잡아 둔 네이티브 모드를 그대로 쓴다"를
# 정면으로 보는 유일한 방법이다(design 결정 3). 실기에서는 이 자리가 패널의
# 네이티브 해상도가 된다.
#
# 1024x768(virtio-gpu 체인들의 값)이 아니라 1280x800인 것은 OVMF의 GOP
# 기본 모드이기 때문이다. **다른 체인의 격자 수를 베껴 오면 안 된다.**
WANT_GRID="terminal: grid 155x47 (fb 1280x800)"
if ! grep -aqF "$WANT_GRID" "$LOG"; then
  fail "want '${WANT_GRID}' but the terminal reported something else" \
    "terminal: grid" "Initialized simpledrm"
fi
echo "terminal drew on the GOP framebuffer at the firmware's native mode"

# card0이 있었으므로 감독자가 포기할 이유가 없다. boot/check.sh가 -vga none으로
# 보는 것의 반대편이고, 둘이 한 쌍이다.
if grep -aq "tars-init: giving up on terminal" "$LOG"; then
  fail "init gave up on the terminal even though simpledrm came up" \
    "tars-init: started terminal" "dri/card0"
fi

echo "PASS"
exit 0
