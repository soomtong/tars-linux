#!/usr/bin/env bash
# WY-M0: zig-wayland의 스캐너가 읽는 프로토콜 xml 셋을 vendor/wayland/에 받는다(WY design 결정 2 —
# pkg-config에 기대지 않는다). 모양은 vendor_stb_*.sh와 같다 — 태그 고정 URL, 파일의 sha256, 있으면 안 받는다.
#
#   wayland.xml     libwayland 1.23.1(trixie libwayland-dev 1.23.1-3과 같은 판)
#   xdg-shell.xml   wayland-protocols 1.44(trixie wayland-protocols 1.44-1과 같은 판)
#   viewporter.xml  wayland-protocols 1.44 — M2(SDL3의 2단)가 generate한다. 지금은 받기만 한다
#
# sha256은 태그의 raw 파일과 Debian 패키지가 까는 파일(/usr/share/wayland/wayland.xml ·
# /usr/share/wayland-protocols/stable/…)을 따로 재어 같은 값이었다(2026-11-19). 판을 올릴 때 함께 고친다.
set -euo pipefail

cd "$(dirname "$0")" || exit 1

WAYLAND_TAG="1.23.1"
PROTOCOLS_TAG="1.44"
DIR="vendor/wayland"

# fetch <url> <파일 이름> <sha256> — vendor_stb_truetype.sh와 같은 .tmp → 대조 → mv 순서다.
fetch() {
  local url="$1" dest="${DIR}/$2" sum="$3"
  if [ ! -f "$dest" ]; then
    echo "Downloading ${url}..."
    mkdir -p "$DIR"
    curl -sSL -o "${dest}.tmp" "$url"
    echo "${sum}  ${dest}.tmp" | sha256sum -c -
    mv "${dest}.tmp" "$dest"
  fi
}

fetch "https://gitlab.freedesktop.org/wayland/wayland/-/raw/${WAYLAND_TAG}/protocol/wayland.xml" \
  wayland.xml 0c371e9c31f8178008a7ddecf431cbe12ec4b29ef7714803ecd3e20af925e7ed
fetch "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/raw/${PROTOCOLS_TAG}/stable/xdg-shell/xdg-shell.xml" \
  xdg-shell.xml 9d9e27038ca722f159a361293f8c6cd270dab907ab52de5b8ecfbb8d6b9651c2
fetch "https://gitlab.freedesktop.org/wayland/wayland-protocols/-/raw/${PROTOCOLS_TAG}/stable/viewporter/viewporter.xml" \
  viewporter.xml dcb12279a03746301fe490aaed4b38a403485a925abfce2ccfceb644e104fe71
