#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# HI 체인용 설정 디스크.
#
# **이 체인이 디스크를 물게 된 이유가 HI-M2다.** HI-M1까지는 자판이 하나라
# 설정과 무관했는데, 이제 `hangul_layout`이 자판을 고른다. 그 값이 설정
# 파일에서 init의 argv를 거쳐 terminal의 조합기까지 닿는 길은 **호스트 검사가
# 절대 못 본다** — `config_test`는 파싱까지만, `hangul_test`는 자판 표만 본다.
#
# **부팅을 하나 더 붙이지 않고 있는 부팅에 디스크를 물린다**(design 결정 14).
# IP가 같은 이유로 같은 방법을 쓴다 — `mkfs.ext2`의 `-d`가 디렉터리 하나를
# 파일시스템 루트로 채워 넣으므로(e2fsprogs 1.43+) 게스트 안에서 타이핑해서
# 심을 필요가 없다. 설정을 쓰고 다시 읽는 왕복은 CP 체인이 이미 본다.
#
# **심는 값이 기본값과 달라야 한다.** 기본값은 shin_pcs이고 여기 심는 것은
# sebeol_3p3다 — 같은 값을 심으면 설정을 통째로 무시하는 코드도 초록이 뜬다.
SIZE=16M
IMG=../out/hangul.img

mkdir -p ../out
rm -f "$IMG"

# 매 회차 새로 굽는다. 이전 회차의 이미지가 남아 있으면 "설정이 정말 이
# 파일에서 왔는가"가 흐려진다 — CP와 IP가 같은 이유로 매번 새로 굽는다.
SEED="$(mktemp -d)"
cat > "$SEED/tars.conf" <<'EOF'
# HI 체인이 미리 심어 두는 설정. 게스트는 이 파일을 읽기만 한다.
#
# hangul_layout=sebeol_3p3 — **기본값(shin_pcs)이 아닌 것이 요점이다.**
#                            이 한 줄이 조합기를 갈아 끼운다.
hangul_layout=sebeol_3p3
EOF

truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-hangul -d "$SEED" "$IMG"
rm -rf "$SEED"

echo "make_disk: created ${IMG} (${SIZE}, ext2, hangul_layout=sebeol_3p3)"
