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

cp /usr/bin/fish "$WORKDIR/usr/bin/fish"
chmod 0755 "$WORKDIR/usr/bin/fish"

copy_lib_deps "$WORKDIR/init"
copy_lib_deps "$WORKDIR/usr/bin/fish"

(cd "$WORKDIR" && find . | cpio -o -H newc) > initrd.cpio
