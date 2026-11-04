#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

# IP 체인 부팅 셋의 설정 디스크(KK-M0부터 셋 — KK design 결정 7).
#
#   ./make_disk.sh auto <kk-apple 경로>  1차. keyboard= 줄이 없다 — 기본값이 고른다.
#                                         Apple 대역 키보드 도구를 kk/kk-apple로 싣는다.
#   ./make_disk.sh pc                     2차. keyboard=pc
#   ./make_disk.sh apple                  3차. keyboard=apple
#
# 이미지는 ../out/input-<종류>.img, 라벨은 tars-input-<종류>(ext2 라벨은 16자까지).
#
# CP의 make_disk.sh와 다른 점은 빈 파일시스템이 아니라 내용이 든 것을
# 굽는다는 것뿐이다. CP는 "빈 디스크로 첫 부팅 → init이 seed를 심는다 →
# 사람이 게스트 안에서 고친다 → 다시 부팅해서 읽는다"를 증명해야 해서 그
# 네 단계를 다 밟아야 했지만, IP가 증명할 것은 "이 값이 키 해석을 바꾸는가"
# 하나다. 이미 든 파일을 읽기만 하면 되므로 부팅 한 번과 sendkey 25개로 끝난다.
#
# mkfs.ext2의 -d는 디렉터리 하나를 파일시스템 루트로 채워 넣는다
# (e2fsprogs 1.43+). 이것이 없었다면 CP처럼 부팅해서 타이핑하는 수밖에
# 없었고, 이 체인이 부팅 셋을 써야 했다.
SIZE=16M
KIND="${1:-}"
IMG="../out/input-${KIND}.img"

mkdir -p ../out
rm -f "$IMG"

# 매 회차 새로 굽는다. 이전 회차의 이미지가 남아 있으면 "설정이 정말 이
# 파일에서 왔는가"가 흐려진다 — CP가 같은 이유로 매번 새로 굽는다.
SEED="$(mktemp -d)"
case "$KIND" in
  auto)
    TOOL="${2:?make_disk: auto needs the kk-apple path}"
    cat > "$SEED/tars.conf" <<'EOF'
# IP 체인 1차 부팅의 설정(KK-M0). keyboard= 줄이 없다 — 기본값이 고른다.
#
# shell=fish — 지금까지의 1차와 같은 셸. 판정 7이 bash --norc로 들어간다.
shell=fish
EOF
    mkdir -p "$SEED/kk"
    cp "$TOOL" "$SEED/kk/kk-apple"
    chmod 0755 "$SEED/kk/kk-apple"
    ;;
  pc)
    cat > "$SEED/tars.conf" <<'EOF'
# IP 체인이 미리 심어 두는 설정. 게스트는 이 파일을 읽기만 한다.
#
# shell=bash  — PTY 셸을 처음부터 readline 지형으로 띄운다. design doc
#               위험 2가 "fish 바인딩은 미검증이니 bash에서 검사하라"고 했다.
# keyboard=pc — 이 한 줄이 Alt와 Meta를 맞바꾼다(design doc 결정 9).
shell=bash
keyboard=pc
EOF
    ;;
  apple)
    cat > "$SEED/tars.conf" <<'EOF'
# IP 체인 3차 부팅의 설정(KK-M0). 값을 적었으므로 기본값과 상관없이 Apple이다.
shell=bash
keyboard=apple
EOF
    ;;
  *)
    echo "usage: make_disk.sh auto <kk-apple> | pc | apple" >&2
    rm -rf "$SEED"
    exit 2
    ;;
esac

truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L "tars-input-${KIND}" -d "$SEED" "$IMG"
rm -rf "$SEED"

echo "make_disk: created ${IMG} (${SIZE}, ext2, ${KIND})"
