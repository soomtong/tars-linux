#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# PM 체인용 설정 디스크.
#
# 이 디스크가 하는 일은 하나뿐이다 — **PTY 셸을 bash로 띄우는 것**.
# kill은 initrd에 바이너리로 들어 있지 않고(make_initrd.sh가 넣는 것은
# 셸 셋과 cat/uname/mkdir/sleep뿐이다), bash와 zsh는 kill을 빌트인으로
# 가지고 있지만 기본값인 fish는 확인되지 않았다. 게이트가 "명령을 못
# 찾았다"로 죽으면 그 실패는 시그널 처리의 실패와 구분되지 않는다.
#
# IP-M2가 연 길을 그대로 쓴다: mkfs.ext2 -d로 **내용이 이미 든** 이미지를
# 구우면 게스트에 한 글자도 치지 않고 셸을 고를 수 있다.
SIZE=16M
IMG=../out/power.img

mkdir -p ../out
rm -f "$IMG"

# 매 회차 새로 굽는다. 이전 회차의 이미지가 남아 있으면 "이 설정이 정말
# 이 파일에서 왔는가"가 흐려진다.
SEED="$(mktemp -d)"
cat > "$SEED/tars.conf" <<'EOF'
# PM 체인이 미리 심어 두는 설정.
#
# shell=bash — kill 빌트인이 확실히 있는 셸로 띄운다. 게이트는 이 셸에
#              `kill -TERM 1`을 타이핑한다.
shell=bash
EOF

truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-power -d "$SEED" "$IMG"
rm -rf "$SEED"

echo "make_disk: created ${IMG} (${SIZE}, ext2, shell=bash)"
