#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

KERNEL_VERSION="6.18.42"
KERNEL_MAJOR="6.x"
TARBALL="linux-${KERNEL_VERSION}.tar.xz"
URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}/${TARBALL}"
SRC_DIR="src/linux-${KERNEL_VERSION}"

if [ ! -d "$SRC_DIR" ]; then
  echo "Downloading ${URL}..."
  mkdir -p src
  curl -sSL -o "src/${TARBALL}" "$URL"
  tar -C src -xf "src/${TARBALL}"
  rm "src/${TARBALL}"
fi

mkdir -p build
cp .config build/.config

MAKE_ARGS=(-C "$SRC_DIR" O=../../build ARCH=x86_64)

make "${MAKE_ARGS[@]}" olddefconfig
make "${MAKE_ARGS[@]}" -j"$(nproc)" bzImage
