#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo | cpio -o -H newc > initrd.cpio
