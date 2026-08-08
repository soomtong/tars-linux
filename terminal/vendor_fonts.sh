#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

FONTS_TAG="v0.0.7"
URL="https://github.com/iolo/8x4x4-fonts/releases/download/${FONTS_TAG}/8x4x4-fonts-all.zip"
FONT_FILE="vendor/fonts/Hanme_8x4x4.ttf"

if [ ! -f "$FONT_FILE" ]; then
  echo "Downloading ${URL}..."
  mkdir -p vendor/fonts
  curl -sSL -o /tmp/8x4x4-fonts-all.zip "$URL"
  unzip -p /tmp/8x4x4-fonts-all.zip Hanme_8x4x4.ttf > "$FONT_FILE"
  rm /tmp/8x4x4-fonts-all.zip
fi
