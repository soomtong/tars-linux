#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

STB_SHA="2c980bb59875b0d32144a71867fbdebb2f77cd20"
URL="https://raw.githubusercontent.com/nothings/stb/${STB_SHA}/stb_truetype.h"
DEST="vendor/stb_truetype.h"

if [ ! -f "$DEST" ]; then
  echo "Downloading ${URL}..."
  mkdir -p vendor
  curl -sSL -o "$DEST" "$URL"
fi
