#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

copy_lib_deps() {
  local bin="$1"
  local lib
  for lib in $(ldd "$bin" | grep -oE '/[^ ]+\.so[0-9.]*'); do
    mkdir -p "$WORKDIR$(dirname "$lib")"
    cp -n "$lib" "$WORKDIR$lib"
  done
}

mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev"

cp ../init/target/release/tars-init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

# Debug 빌드의 terminal은 42MB인데 대부분이 디버그 심볼이다. initrd가 커지면
# BF 체인(limine이 BIOS INT13h로 ISO에서 읽는 경로)이 부팅조차 못 한다.
# initrd에 들어가는 복사본만 strip한다 — 컴파일 결과는 그대로고, 로컬
# zig-out/bin/terminal은 디버깅용으로 심볼을 유지한다.
cp ../terminal/zig-out/bin/terminal "$WORKDIR/terminal"
strip "$WORKDIR/terminal"
chmod 0755 "$WORKDIR/terminal"

mkdir -p "$WORKDIR/vendor/fonts"
cp ../terminal/vendor/fonts/Hanme_8x4x4.ttf "$WORKDIR/vendor/fonts/Hanme_8x4x4.ttf"

cp /usr/bin/fish "$WORKDIR/usr/bin/fish"
chmod 0755 "$WORKDIR/usr/bin/fish"

cp /usr/bin/cat "$WORKDIR/usr/bin/cat"
chmod 0755 "$WORKDIR/usr/bin/cat"

cp /usr/bin/uname "$WORKDIR/usr/bin/uname"
cp /usr/bin/mkdir "$WORKDIR/usr/bin/mkdir"
chmod 0755 "$WORKDIR/usr/bin/uname" "$WORKDIR/usr/bin/mkdir"

copy_lib_deps "$WORKDIR/init"
copy_lib_deps "$WORKDIR/terminal"
copy_lib_deps "$WORKDIR/usr/bin/fish"
copy_lib_deps "$WORKDIR/usr/bin/cat"
copy_lib_deps "$WORKDIR/usr/bin/uname"
copy_lib_deps "$WORKDIR/usr/bin/mkdir"

mkdir -p "$WORKDIR/usr/share/fish"
cp -r /usr/share/fish/functions "$WORKDIR/usr/share/fish/"
cp /usr/share/fish/config.fish "$WORKDIR/usr/share/fish/"
cp /usr/share/fish/__fish_build_paths.fish "$WORKDIR/usr/share/fish/"

# gzip으로 압축해 둔다. 커널은 initramfs의 magic을 보고 알아서 푼다
# (CONFIG_RD_GZIP=y). 파일명은 initrd.cpio 그대로 유지한다 — limine.conf와
# 세 check 스크립트가 이 이름을 참조하기 때문이다. 53MB → strip 19.8MB →
# gzip 6.5MB.
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -9 > initrd.cpio
