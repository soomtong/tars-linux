#!/usr/bin/env bash
# Apple 부팅 선택 화면(전원을 켤 때 Option)이 TARS-BOOT를 "EFI Boot" 대신 "TARS Linux"로 보이게 하는 그림 둘을 만든다.
# 펌웨어는 BOOTX64.EFI 옆의 `.disk_label`(1배) · `.disk_label_2x`(Retina)를 읽는다 — 글자가 아니라 Apple 고유의
# 흑백 그림이라(머리 5바이트: 판 1 · 너비 · 높이, 그 뒤 픽셀) macOS의 `bless --label`이 그린다.
#
# macOS에서 한 번 돌리고 결과를 커밋한다(boot/disk_label · boot/disk_label_2x). 게이트 컨테이너에는 bless가 없다.
# root가 필요 없다 — 빈 FAT 이미지를 붙여 그 안에서 만든다. make_iso.sh가 두 파일을 ISO의 EFI/BOOT로, tars-install이
# 그것을 TARS-BOOT로 옮긴다(disk.BOOT_FILES).
set -euo pipefail
cd "$(dirname "$0")" || exit 1
LABEL="${1:-TARS Linux}"
WORK="$(mktemp -d)"
trap 'hdiutil detach -quiet "$WORK/mnt" 2>/dev/null || true; rm -rf "$WORK"' EXIT
hdiutil create -quiet -size 8m -fs MS-DOS -volname TARSLBL -layout NONE "$WORK/lbl.dmg"
hdiutil attach -quiet -mountpoint "$WORK/mnt" "$WORK/lbl.dmg"
mkdir -p "$WORK/mnt/EFI/BOOT"
touch "$WORK/mnt/EFI/BOOT/BOOTX64.EFI"
bless --folder "$WORK/mnt/EFI/BOOT" --label "$LABEL"
cp "$WORK/mnt/EFI/BOOT/.disk_label" disk_label
cp "$WORK/mnt/EFI/BOOT/.disk_label_2x" disk_label_2x
echo "wrote boot/disk_label and boot/disk_label_2x for \"${LABEL}\""
