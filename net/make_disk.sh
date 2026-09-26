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
#
# TS-M1이 이미지를 둘로 늘렸다. 검사 1~16이 쓰는 것과 부팅 A가 쓰는 것이
# 따로다 — 한 디스크에 ntp= 를 더하면 그 열여섯이 전부 시계가 2031년인
# 게스트에서 돌게 되고, 열여섯 중 하나가 깨지는 날 원인이 "받는 길"인지
# "시계"인지 안 갈린다.
SIZE=16M

# TS-M1. 부팅 A가 물을 주소를 체인이 정해서 넘긴다. 기본값을 두는 이유는
# 이 스크립트를 손으로 돌리는 사람 때문이고, 게이트는 언제나 넘긴다 —
# 그래야 이 주소를 아는 자리가 net/check.sh 한 곳이다.
NTP_SERVER="${1:-10.0.2.2}"

# TS-M3. 부팅 A가 쓰는 시간대. 첫째 인자와 같은 이유로 체인이 넘긴다 —
# 이 이름을 아는 자리가 net/check.sh 한 곳이어야 검사 24의 기대값과 안
# 어긋난다.
TZ_NAME="${2:-Asia/Seoul}"

mkdir -p ../out

# 이미지 하나를 굽는다. 인자가 (경로, 라벨, tars.conf 내용)이다.
bake() {
  local img="$1" label="$2" body="$3"
  local conf
  conf="$(mktemp)"
  printf '%s' "$body" > "$conf"

  rm -f "$img"
  truncate -s "$SIZE" "$img"
  mkfs.ext2 -F -q -m 0 -L "$label" "$img"
  debugfs -w -R "write ${conf} tars.conf" "$img" 2>&1 | grep -v '^debugfs' || true
  rm -f "$conf"

  echo "make_disk: created ${img} (${SIZE}, ext2, label ${label})"
}

# 검사 1~16이 쓰는 디스크. 한 줄만 적는다 — 나머지 일곱 키는 기본값이고,
# 그래서 이 부팅의 셸이 fish이며 체인의 화면 좌표가 다른 체인들과 같다.
#
# init이 이 파일을 읽으면 save()를 안 부른다 — load가 null이 아니기
# 때문이다. 즉 이 디스크의 tars.conf는 부팅 뒤에도 이 한 줄 그대로다.
bake ../out/net.img tars-net 'net=dhcp
'

# TS-M1. 부팅 A가 쓰는 디스크. 위의 것과 다른 것이 ntp 한 줄이었고 TS-M3이
# timezone 한 줄을 더했다 — 시계를 뛰는 부팅에서 그 시각을 사람이 읽는
# 모양으로 보는 것까지가 한 부팅의 일이다. net.img와 아래 net-ntp-dhcp.img는
# 기본값(UTC)으로 남는다 — "이 키를 안 적은 기계"가 게이트 안에 있어야 한다.
#
# 라벨을 tars-ntp로 다르게 두는 이유는 진단이다. 두 디스크가 같은 라벨이면
# 엉뚱한 이미지를 물린 회차에 게스트 로그가 똑같이 생긴다.
bake ../out/net-ntp.img tars-ntp "net=dhcp
ntp=${NTP_SERVER}
timezone=${TZ_NAME}
"

# TS-M2. 부팅 B가 쓰는 디스크. 부팅 A와 다른 것은 ntp의 값 하나다 — 주소가
# 설정에 없고 initrd에 심은 /run/tars/ntp_servers에서 온다.
#
# 이 디스크가 증명하는 문장이 부팅 A와 다르다. 저쪽은 "우리가 적은 주소에
# 묻는다"이고 이쪽은 "DHCP가 알려 준 주소를 읽어서 묻는다"이다. 값이 같은
# 코드를 두 번 도는 것이 아니라 clock.zig의 갈래 둘 중 안 밟힌 쪽을 밟는다.
#
# 라벨이 셋 다 다르다. 같은 라벨이면 엉뚱한 이미지를 물린 회차의 게스트
# 로그가 똑같이 생긴다.
bake ../out/net-ntp-dhcp.img tars-ntp-dhcp 'net=dhcp
ntp=dhcp
'

# TD-M2. 부팅 C · D가 이어받는 디스크. 부팅 C의 chronyd가 끌 때 여기에
# chrony.drift를 쓰고, 부팅 D의 chronyd가 그것을 읽는다 — 체인은 두 부팅
# 사이에 이 이미지를 다시 굽지 않는다.
#
# chrony.d/gate.conf가 폴링을 0.25초로 줄인다(TD design 결정 8). init이 쓰는
# 설정의 server 줄과 주소가 같고, confdir가 맨 앞이라 이쪽이 이긴다(TD-M0
# 실측 9). 사람이 같은 자리에 `pool pool.ntp.org iburst`를 적는 것과 같은 길이다.
bake ../out/net-drift.img tars-drift "net=dhcp
ntp=${NTP_SERVER}
"
GATE_CONF="$(mktemp)"
printf 'server %s iburst minpoll -2 maxpoll -2\n' "$NTP_SERVER" > "$GATE_CONF"
debugfs -w -R "mkdir chrony.d" ../out/net-drift.img 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "write ${GATE_CONF} chrony.d/gate.conf" ../out/net-drift.img 2>&1 | grep -v -e '^debugfs' -e '^Allocated inode' || true
rm -f "$GATE_CONF"
echo "make_disk: planted chrony.d/gate.conf in ../out/net-drift.img"
