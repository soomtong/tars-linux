#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LIMINE_BIN="limine-binary"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/boot/limine"
cp ../kernel/build/arch/x86/boot/bzImage "$STAGE/boot/bzImage"
cp ../kernel/initrd.cpio "$STAGE/boot/initrd.cpio"
cp limine.conf "$STAGE/boot/limine/limine.conf"
cp "$LIMINE_BIN/limine-bios.sys" "$STAGE/boot/limine/limine-bios.sys"
cp "$LIMINE_BIN/limine-bios-cd.bin" "$STAGE/boot/limine/limine-bios-cd.bin"

mkdir -p ../out
xorriso -as mkisofs -R -r -J \
        -b boot/limine/limine-bios-cd.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        "$STAGE" -o ../out/tars.iso

"$LIMINE_BIN/limine" bios-install ../out/tars.iso
