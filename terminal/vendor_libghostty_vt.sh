#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

GHOSTTY_SHA="2602886144c7e95099c9e2ba07f181c69e7276f3"
SRC_DIR="ghostty-src"
URL="https://github.com/ghostty-org/ghostty/archive/${GHOSTTY_SHA}.tar.gz"

if [ ! -d "$SRC_DIR" ]; then
  echo "Downloading ${URL}..."
  curl -sSL -o ghostty-src.tar.gz "$URL"
  mkdir -p "$SRC_DIR"
  tar -xzf ghostty-src.tar.gz -C "$SRC_DIR" --strip-components=1
  rm ghostty-src.tar.gz
fi

# CC-M0(2026-08-31): 여기에 있던 `zig build -Demit-lib-vt` 한 줄을 뺐다.
#
# 그 줄은 vendor/libghostty-vt/ 아래에 x86_64용 C 라이브러리 98MB를 만들었는데,
# **그것을 읽는 자리가 terminal/sanity/libghostty_vt_main.c 하나뿐이었고** 그
# 도구를 같은 milestone에서 지웠다. 우리 빌드가 쓰는 것은 이 라이브러리가
# 아니라 ghostty-src를 Zig 패키지로 잡은 쪽이다 — build.zig.zon의
# `.ghostty = .{ .path = "ghostty-src" }`와 build.zig의
# `ghostty_dep.module("ghostty-vt")`다.
#
# 그 도구는 이 컨테이너에서 링크조차 되지 않았다(arm64에서 x86_64 .so를
# 링크할 수 없다). 그리고 도구가 증명하려던 것은 게이트가 매번 증명한다 —
# vt_test가 같은 라이브러리로 호스트에서 화면을 만든다.
#
# 그래서 이 스크립트가 하는 일은 이제 소스 트리를 받아 두는 것 하나다.
# 이름을 안 바꾼 이유는 부르는 자리가 둘이기 때문이다 — prepare.sh:14와
# check.sh의 BUILD_STEPS가 보는 ./prepare.sh.
