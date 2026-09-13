#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# NW-M2. config/make_disk.sh와 다른 점이 둘이다 — 라벨이 tars-net이고,
# 빈 디스크가 아니라 tars.conf를 미리 담아 굽는다.
#
# 미리 담는 방법이 debugfs다. 마운트도 loop 장치도 특권도 필요 없다 —
# 이미지 파일을 파일로 읽고 쓸 뿐이다. 그래서 이 게이트가 아무 특권 없이
# 도는 성질을 안 버린다(design 결정 4가 tap을 버린 것과 같은 기준이다).
# debugfs는 mkfs.ext2와 같은 패키지(e2fsprogs)라 따로 받을 것도 없다.
#
# 이것이 design이 M2에 남긴 갈림을 없앤다. cmdline으로 주면 부팅 하나로
# 끝나지만 tars.conf의 키를 게이트가 한 번도 안 읽고, 게스트에서 타이핑으로
# 쓰면 tars.conf를 읽지만 부팅이 둘이 된다. 이쪽은 둘 다 갖는다.
#
# 라벨 접두사가 tars- 여야 한다. init/src/storage.zig의 LABEL_PREFIX가
# 그것이고(RM-M2), 정확히 하나로 박지 않은 이유가 게이트 디스크가 여럿이기
# 때문이다.
SIZE=16M
IMG=../out/net.img
CONF="$(mktemp)"
trap 'rm -f "$CONF"' EXIT

mkdir -p ../out
rm -f "$IMG"
truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-net "$IMG"

# 한 줄만 적는다. 나머지 여섯 키는 기본값이고, 그래서 이 부팅의 셸이
# fish이며 체인의 화면 좌표가 다른 체인들과 같다.
#
# init이 이 파일을 읽으면 save()를 안 부른다 — load가 null이 아니기
# 때문이다. 즉 이 디스크의 tars.conf는 부팅 뒤에도 이 한 줄 그대로다.
printf 'net=dhcp\n' > "$CONF"
debugfs -w -R "write ${CONF} tars.conf" "$IMG" 2>&1 | grep -v '^debugfs' || true

echo "make_disk: created ${IMG} (${SIZE}, ext2, label tars-net, net=dhcp)"
