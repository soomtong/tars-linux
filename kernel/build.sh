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

# GL-M1: make가 "할 일 없음"을 확인하는 데만 9.3초가 들고 olddefconfig가 1.3초를
# 더한다. 증분 회차 29초 중 13초가 그것이었고, 루트 게이트는 24회 치른다.
#
# 커널 소스는 tarball을 푼 뒤 불변이므로 이 빌드의 입력은 사실상 .config
# 하나다. 그래서 make의 판단을 여기서 대신한다 — mtime을 보는 것은 make가
# 쓰던 기준 그대로다.
#
# build.sh 자신도 비교 대상인 것이 중요하다. KERNEL_VERSION이 이 파일 안에
# 있어서, 커널 버전을 올리면 SRC_DIR이 바뀌고 새 소스를 받는데 build/는 옛
# 산출물을 그대로 갖고 있다. 이 파일을 함께 보지 않으면 **버전을 올린 뒤에도
# 낡은 bzImage로 부팅한다.**
#
# 틀렸을 때의 증상은 조용하지 않다 — 게이트가 낡은 커널로 부팅하고 판정이
# 흔들린다. 그것이 이 판정의 검출 수단이다.
# GL-M1: make가 "할 일 없음"을 확인하는 데만 9.3초가 들고 olddefconfig가 1.3초를
# 더한다. 증분 회차 29초 중 13초가 그것이었고, 루트 게이트는 24회 치른다.
#
# 커널 소스는 tarball을 푼 뒤 불변이므로 이 빌드의 입력은 .config와 이 파일
# 둘뿐이다. 그래서 그 둘의 해시를 산출물 옆에 적어 두고 대조한다.
#
# **mtime으로 판정하지 않는다.** 처음에는 bzImage가 .config보다 새것인지 보는
# 방식이었는데, .config의 mtime만 새것이 되면(git checkout, 편집했다 되돌리기)
# make가 내용이 같다고 판단해 bzImage를 갱신하지 않으므로 판정이 "빌드 필요"에
# **고착되어 영영 스킵되지 않는다.** GL-M0이 신선도 검사에서 겪은 것과 같은
# 병이다(docs/decisions/project_gate_latency.md).
#
# build.sh 자신이 해시에 들어가는 것이 중요하다. KERNEL_VERSION이 이 파일 안에
# 있어서, 커널 버전을 올리면 SRC_DIR이 바뀌고 새 소스를 받는데 build/는 옛
# 산출물을 그대로 갖고 있다. 이 파일을 함께 보지 않으면 **버전을 올린 뒤에도
# 낡은 bzImage로 부팅한다.**
#
# clean()이 kernel/build를 통째로 지우므로 스탬프도 함께 사라진다 — 게이트
# 첫 회차는 언제나 진짜로 빌드한다.
BZIMAGE=build/arch/x86/boot/bzImage
STAMP=build/.tars-build-stamp
BUILD_INPUTS="$(cat .config build.sh | sha256sum | cut -d' ' -f1)"
if [ -f "$BZIMAGE" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$BUILD_INPUTS" ]; then
  echo "kernel: bzImage matches .config and build.sh, skipping make"
  exit 0
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

# 빌드가 성공한 뒤에만 적는다. 중간에 죽으면 스탬프가 없어 다음 실행이 다시
# 빌드한다 — set -e가 그것을 보장한다.
echo "$BUILD_INPUTS" > "$STAMP"
