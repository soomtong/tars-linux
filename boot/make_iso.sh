#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

LIMINE_BIN="limine-binary"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/boot/limine" "$STAGE/EFI/BOOT"
cp ../kernel/build/arch/x86/boot/bzImage "$STAGE/boot/bzImage"
cp ../kernel/initrd.cpio "$STAGE/boot/initrd.cpio"
cp limine.conf "$STAGE/boot/limine/limine.conf"
cp "$LIMINE_BIN/limine-bios.sys" "$STAGE/boot/limine/limine-bios.sys"
cp "$LIMINE_BIN/limine-bios-cd.bin" "$STAGE/boot/limine/limine-bios-cd.bin"

# RM-M0: ISO 하나가 BIOS와 UEFI를 둘 다 태운다. El Torito 부트 카탈로그는
# 항목 둘을 담을 수 있고(BIOS는 -b, UEFI는 --efi-boot) 펌웨어가 자기 것을
# 고른다. boot/check.sh는 SeaBIOS로, machine/check.sh는 OVMF로 같은
# 바이트를 부팅한다 — 그것이 두 ISO로 나누지 않은 이유다.
#
# 아래 두 파일은 서로 다른 경로다.
#   limine-uefi-cd.bin        El Torito가 가리키는 FAT 이미지. 광학 매체 부팅
#   EFI/BOOT/BOOTX64.EFI      이 ISO를 USB에 dd로 쓴 뒤 펌웨어가 파일로 찾는 것
# 실기에 꽂는 것은 후자 경로이므로 둘 다 필요하다.
#
# 둘 다 BF-M0이 커밋한 limine 배포 tarball에 처음부터 들어 있었다. 그때는
# BIOS 파일 둘만 썼다.
cp "$LIMINE_BIN/limine-uefi-cd.bin" "$STAGE/boot/limine/limine-uefi-cd.bin"
cp "$LIMINE_BIN/BOOTX64.EFI" "$STAGE/EFI/BOOT/BOOTX64.EFI"

# 2026-11-05(사용자 요청). Apple 부팅 선택 화면(Option)이 "EFI Boot" 대신 "TARS Linux"로 보이게 하는 그림 둘
# (boot/make_disk_label.sh가 macOS의 bless로 만든다). 펌웨어는 BOOTX64.EFI 옆의 `.disk_label` · `.disk_label_2x`를 읽고
# FAT 볼륨 라벨은 안 본다. 두 자리에 넣는다.
#   EFI/BOOT/                  tars-install이 TARS-BOOT로 옮기는 원본(disk.BOOT_FILES)
#   limine-uefi-cd.bin 안      USB에 dd한 ISO를 펌웨어가 여는 FAT 이미지(El Torito). 1.4MB가 비어 있다
cp disk_label "$STAGE/EFI/BOOT/.disk_label"
cp disk_label_2x "$STAGE/EFI/BOOT/.disk_label_2x"
MTOOLS_SKIP_CHECK=1 mcopy -o -i "$STAGE/boot/limine/limine-uefi-cd.bin" disk_label ::/EFI/BOOT/.disk_label
MTOOLS_SKIP_CHECK=1 mcopy -o -i "$STAGE/boot/limine/limine-uefi-cd.bin" disk_label_2x ::/EFI/BOOT/.disk_label_2x

mkdir -p ../out
# --protective-msdos-label은 대시 둘이다. 하나로 쓰면 xorriso가
# `Unrecognized option`으로 죽는다 — 스파이크에서 한 번 밟았다. 이 옵션이
# 붙어야 펌웨어가 하이브리드 이미지를 MBR/GPT 혼동 없이 읽는다.
#
# DI-M1: -V TARS. 기본값은 ISOIMAGE였다(DI-M0 실측 6). tars-install은 이름이
# 아니라 boot/limine/limine.conf의 존재로 매체를 알아보지만(DI design 결정 4)
# 목록 머리 줄에 이 이름을 찍고, install 체인이 그 줄로 이 옵션을 본다.
xorriso -as mkisofs -R -r -J -V TARS \
        -b boot/limine/limine-bios-cd.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        --efi-boot boot/limine/limine-uefi-cd.bin \
        -efi-boot-part --efi-boot-image \
        --protective-msdos-label \
        "$STAGE" -o ../out/tars.iso

# UEFI를 더하는 것이 BIOS 경로를 빼앗지 않는다. limine의 stage 2가 여전히
# MBR에 들어가야 SeaBIOS가 부팅한다.
"$LIMINE_BIN/limine" bios-install ../out/tars.iso
