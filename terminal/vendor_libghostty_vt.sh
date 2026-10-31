#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")" || exit 1

GHOSTTY_SHA="3d07ef9e28c4af05065b9e2e546b8ac8f9b62df0"
SRC_DIR="ghostty-src"
URL="https://github.com/ghostty-org/ghostty/archive/${GHOSTTY_SHA}.tar.gz"
# tarball의 sha256(VS-M0). GitHub archive에는 공식 해시가 없다 — 두 번 받아 같은 값이고, 푼 것이
# 그때까지 게이트가 쓰던 트리와 diff 0줄이었다(VS design 확인 2 · 3). FAILED가 나면 재실행으로
# 안 풀린다 — 새 tarball을 풀어 지난 트리와 diff -rq를 보고 같은 커밋이면 이 값을 고친다.
# 커밋(GHOSTTY_SHA)을 올릴 때도 함께 고친다.
GHOSTTY_SHA256="3949e4bf93f345c7729faecac6b9916aeb5a2b745de5671a7fe8d4725040046c"

if [ ! -d "$SRC_DIR" ]; then
  echo "Downloading ${URL}..."
  curl -sSL -o ghostty-src.tar.gz "$URL"
  echo "${GHOSTTY_SHA256}  ghostty-src.tar.gz" | sha256sum -c -
  mkdir -p "$SRC_DIR"
  tar -xzf ghostty-src.tar.gz -C "$SRC_DIR" --strip-components=1
  rm ghostty-src.tar.gz
fi

# CC-M0(2026-08-31): 여기에 있던 `zig build -Demit-lib-vt` 한 줄을 뺐다.
#
# 그 줄은 vendor/libghostty-vt/ 아래에 x86_64용 C 라이브러리 98MB를 만들었는데,
# 그것을 읽는 자리가 terminal/sanity/libghostty_vt_main.c 하나뿐이었고 그
# 도구를 같은 milestone에서 지웠다. 우리 빌드가 쓰는 것은 이 라이브러리가
# 아니라 ghostty-src를 Zig 패키지로 잡은 쪽이다 — build.zig.zon의
# `.ghostty = .{ .path = "ghostty-src" }`와 build.zig의
# `ghostty_dep.module("ghostty-vt")`다.
#
# 그 도구는 이 컨테이너에서 링크조차 되지 않았다(arm64에서 x86_64 .so를
# 링크할 수 없다). 그리고 도구가 증명하려던 것은 게이트가 매번 증명한다 —
# vt_test가 같은 라이브러리로 호스트에서 화면을 만든다.
#
# 그래서 이 스크립트가 하는 일은 이제 소스 트리를 받아 대조해 두는 것 하나다.
# 이름을 안 바꾼 이유는 부르는 자리가 둘이기 때문이다 — prepare.sh:14와
# check.sh의 BUILD_STEPS가 보는 ./prepare.sh.
