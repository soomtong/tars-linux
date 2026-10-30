#!/usr/bin/env bash
#
# initrd에 들어갈 terminal 바이너리와 그 vendor 입력을 준비한다.
# kernel/make_initrd.sh가 ../terminal/zig-out/bin/terminal 과
# ../terminal/vendor/fonts/unifont.otf 를 무조건 복사하므로, initrd를
# 만드는 체인은 어느 것이든 이 준비를 먼저 거쳐야 한다 — boot/check.sh와
# terminal/check.sh 둘 다 이 스크립트를 부른다. 폰트는 받지 않는다 —
# 저장소에 커밋돼 있다(vendor/fonts/README, FR-M0).
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# vendor 스크립트들은 산출물이 이미 있으면 아무것도 하지 않는다.
# ghostty-src는 다운로드에 더해 lib-vt 빌드까지 하므로 트리가 없을 때만 부른다.
if [ ! -d ghostty-src ]; then
  ./vendor_libghostty_vt.sh
fi
./vendor_stb_truetype.sh
./vendor_stb_image.sh

zig build
