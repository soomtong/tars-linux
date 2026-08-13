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

cp ../init/zig-out/bin/init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

# terminal은 Debug 빌드라 42MB이고 대부분이 디버그 심볼이다. strip하면
# initrd가 6.5MB까지 줄지만(부팅 25초 → 34초 차이), 심볼을 남긴다 —
# strip한 바이너리에서는 QEMU 안의 에러 트레이스가 원리적으로 복구
# 불가능해지기 때문이다. 단, 심볼이 있다고 트레이스가 바로 읽히지는
# 않았다(2026-08-12 TF-M4 실측: strip 버전은 `???` 주소 두 줄, 심볼 버전은
# 트레이스 자체가 없었다 — 원인 미규명). 크기는 아래 gzip으로 처리한다.
cp ../terminal/zig-out/bin/terminal "$WORKDIR/terminal"
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

# init은 libc를 링크하지 않는 정적 바이너리라 copy_lib_deps가 필요 없다
# (ZM-M1). 나머지는 전부 glibc 동적 링크다.
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
# 세 check 스크립트가 이 이름을 참조하기 때문이다. 압축이 필요한 이유는 BF
# 체인인데, limine이 BIOS INT13h로 ISO에서 읽는 경로가 에뮬레이션에서
# 극단적으로 느려 53MB에서는 부팅조차 못 했다. 53MB → gzip 11.8MB.
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -9 > initrd.cpio
