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

# ARCH는 arch/x86 트리를 쓰라는 뜻일 뿐 컴파일러를 고르지 않는다. 컨테이너가
# arm64가 된 ZM-M3부터는 CROSS_COMPILE 접두사로 x86_64용 gcc를 명시해야 한다.
# arch/x86/boot의 실모드 코드가 -m32/-m16으로 빌드되므로 크로스 gcc도 32비트
# 코드 생성이 가능해야 한다(Dockerfile의 gcc-multilib-x86-64-linux-gnu).
MAKE_ARGS=(-C "$SRC_DIR" O=../../build ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu-)

make "${MAKE_ARGS[@]}" olddefconfig
make "${MAKE_ARGS[@]}" -j"$(nproc)" bzImage
