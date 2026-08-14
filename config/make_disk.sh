#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# 설정 저장소용 디스크. 16MB면 텍스트 설정 파일 수십 개에 과분하다 —
# 크기를 키울 이유가 생기면 그때 늘린다(이미지는 매번 새로 굽는다).
SIZE=16M
IMG=../out/config.img

mkdir -p ../out
rm -f "$IMG"

# truncate가 만드는 것은 sparse 파일이다. 16MB를 선언하지만 실제로 디스크를
# 차지하는 것은 쓴 만큼뿐이다. QEMU에게는 그냥 16MB 블록 장치로 보인다.
truncate -s "$SIZE" "$IMG"

# -F  : 블록 장치가 아니라 일반 파일이므로 강제한다
# -q  : 조용히
# -m 0: root 예약 블록 0%. 기본 5%는 시스템 디스크가 꽉 찼을 때 root가
#       복구할 여지를 남기는 장치인데, 설정 파일만 담는 16MB 디스크에서는
#       의미가 없다.
# -L  : 레이블. 나중에 dumpe2fs/blkid로 이게 뭐였는지 알아보기 위함.
#
# ext2를 고른 이유(저널 없음, 유닉스 퍼미션 있음)는 design doc의
# "1. virtio-blk + ext2" 참고. 파티션 테이블 없이 디스크 전체가 곧
# 파일시스템이다 — 그래서 게스트가 볼 이름도 /dev/vda1이 아니라 /dev/vda다.
mkfs.ext2 -F -q -m 0 -L tars-config "$IMG"

echo "make_disk: created ${IMG} (${SIZE}, ext2)"
