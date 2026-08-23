#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# GNU Unifont. 문턱값 렌더링(design 결정 4)에 쓸 수 있는 비트맵 폰트다 —
# unitsPerEm이 64라 16px에서 scale이 정확히 0.25이고, coverage가 0 아니면
# 255뿐이라 게이트가 픽셀을 상수와 비교할 수 있다. 아웃라인 폰트는 16px에서
# 잉크의 90% 넘게가 중간값이라 문턱값으로 자르면 획이 끊긴다.
# 후보를 전부 재서 비교한 것은 docs/decisions/project_font_selection.md.
#
# **버전을 고정한다.** font_test.zig의 기대값 표가 이 버전을 실측한 값이라
# 버전을 올리면 그 표를 다시 재야 한다. sha256을 확인하는 이유도 같다 —
# 다른 파일이 조용히 들어오면 표가 통째로 틀어지는데, 그때 나는 실패는
# "글자가 좀 이상하다"라서 원인까지 도달하기가 어렵다.
UNIFONT_VERSION="17.0.03"
URL="https://ftp.gnu.org/gnu/unifont/unifont-${UNIFONT_VERSION}/unifont-${UNIFONT_VERSION}.otf"
SHA256="26071c5a97533cefdcbc6b0645e7ee279413049079f09f592b26916ca6c21bf5"

# 파일 이름에는 버전을 넣지 않는다. 이 경로를 읽는 곳이 다섯 군데라
# (make_initrd.sh · main.zig · font_test.zig · stb_truetype_main.c ·
# prepare.sh의 주석) 이름에 버전을 박으면 올릴 때마다 전부 고쳐야 한다.
FONT_FILE="vendor/fonts/unifont.otf"

if [ ! -f "$FONT_FILE" ]; then
  echo "Downloading ${URL}..."
  mkdir -p vendor/fonts
  curl -sSL -o "${FONT_FILE}.tmp" "$URL"
  if ! echo "${SHA256}  ${FONT_FILE}.tmp" | sha256sum -c --status -; then
    echo "FAIL: 내려받은 파일의 sha256이 기대값과 다르다" >&2
    echo "  URL:  ${URL}" >&2
    echo "  기대: ${SHA256}" >&2
    echo "  실제: $(sha256sum < "${FONT_FILE}.tmp" | cut -d' ' -f1)" >&2
    rm -f "${FONT_FILE}.tmp"
    exit 1
  fi
  mv "${FONT_FILE}.tmp" "$FONT_FILE"
fi
