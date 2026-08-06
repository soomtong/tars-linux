#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LIMINE_TAG="v12.5.2"
DIR="limine-binary"
URL="https://github.com/limine-bootloader/limine/releases/download/${LIMINE_TAG}/limine-binary.tar.gz"

if [ ! -d "$DIR" ]; then
  echo "Downloading ${URL}..."
  curl -sSL -o limine-binary.tar.gz "$URL"
  tar xzf limine-binary.tar.gz
  rm limine-binary.tar.gz
fi

make -C "$DIR"
