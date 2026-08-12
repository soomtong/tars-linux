#!/usr/bin/env bash
#
# initrd에 들어갈 terminal 바이너리와 그 vendor 입력을 준비한다.
# kernel/make_initrd.sh가 ../terminal/zig-out/bin/terminal 과
# ../terminal/vendor/fonts/Hanme_8x4x4.ttf 를 무조건 복사하므로, initrd를
# 만드는 체인은 어느 것이든 이 준비를 먼저 거쳐야 한다 — boot/check.sh와
# terminal/check.sh 둘 다 이 스크립트를 부른다.
set -euo pipefail

cd "$(dirname "$0")"

# 세 vendor 스크립트는 산출물이 이미 있으면 아무것도 하지 않는다.
# ghostty-src는 다운로드에 더해 lib-vt 빌드까지 하므로 트리가 없을 때만 부른다.
if [ ! -d ghostty-src ]; then
  ./vendor_libghostty_vt.sh
fi
./vendor_stb_truetype.sh
./vendor_fonts.sh

zig build
