#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

WORKDIR="$(mktemp -d)"
touch "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"
(cd "$WORKDIR" && echo init | cpio -o -H newc) > initrd.cpio
rm -rf "$WORKDIR"
