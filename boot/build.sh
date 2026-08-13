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

# -B로 매번 다시 만든다. limine 배포 tarball에는 limine.c와 함께 빌드된
# 실행 파일이 들어 있고 make는 그게 소스보다 새것이면 손대지 않는데, 그
# 실행 파일은 "호스트에서 도는 도구"라 호스트 아키텍처가 바뀌면 못 쓴다.
# ZM-M3에서 실제로 이걸 밟았다 — arm64 컨테이너가 옛 amd64 컨테이너가 남긴
# limine을 실행하려다 binfmt_misc가 qemu-user로 넘겨 로더를 못 찾고 죽었다.
# limine-binary/는 clean() 대상이 아니라 저 산출물이 계속 살아남는다.
make -C "$DIR" -B
