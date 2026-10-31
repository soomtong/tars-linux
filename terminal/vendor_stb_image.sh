#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

STB_SHA="2c980bb59875b0d32144a71867fbdebb2f77cd20"
URL="https://raw.githubusercontent.com/nothings/stb/${STB_SHA}/stb_image.h"
DEST="vendor/stb_image.h"
# 파일의 sha256(VS-M0). 커밋 고정 blob이라 공식 해시가 없다 — 두 번 받아 같은 값(VS design 확인 2).
# STB_SHA를 올릴 때 함께 고친다.
STB_SHA256="594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3"

if [ ! -f "$DEST" ]; then
  echo "Downloading ${URL}..."
  mkdir -p vendor
  # DEST 자체가 "이미 있으면 안 받는다"의 검사 대상이라 .tmp로 받아 대조한 뒤 옮긴다 — FAILED로 멈추면
  # DEST가 없는 채라 다음 실행이 다시 받는다(vendor_firmware.sh의 fetch()와 같은 이유, VS-M0 mutation이 잡았다).
  curl -sSL -o "${DEST}.tmp" "$URL"
  echo "${STB_SHA256}  ${DEST}.tmp" | sha256sum -c -
  mv "${DEST}.tmp" "$DEST"
fi
