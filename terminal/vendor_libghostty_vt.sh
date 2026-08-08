#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

GHOSTTY_SHA="2602886144c7e95099c9e2ba07f181c69e7276f3"
SRC_DIR="ghostty-src"
URL="https://github.com/ghostty-org/ghostty/archive/${GHOSTTY_SHA}.tar.gz"

if [ ! -d "$SRC_DIR" ]; then
  echo "Downloading ${URL}..."
  curl -sSL -o ghostty-src.tar.gz "$URL"
  mkdir -p "$SRC_DIR"
  tar -xzf ghostty-src.tar.gz -C "$SRC_DIR" --strip-components=1
  rm ghostty-src.tar.gz
fi

mkdir -p vendor
(cd "$SRC_DIR" && zig build -Demit-lib-vt -Dtarget=x86_64-linux-gnu \
    --prefix ../vendor/libghostty-vt)
