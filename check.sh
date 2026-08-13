#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# 매 회차 전에 지우는 것은 "빌드 산출물"뿐이다.
#
# 지우면 안 되는 것들(전부 .gitignore 대상이라 눈에 안 띈다):
#   terminal/ghostty-src  GitHub tarball로 받아온 vendor 소스 트리
#   terminal/vendor       stb_truetype.h + 8x4x4 폰트 + libghostty-vt 산출물
#   terminal/zig-pkg      Zig 0.16의 프로젝트 로컬 패키지 캐시
# 이 셋은 네트워크가 있어야만 복구되므로, clean 대상에 넣으면 매 회차 수백
# MB를 다시 받고 오프라인에서는 아예 복구가 불가능하다.
#
# kms/target은 목록에서 빠졌다 — TF-M2 이후 kms를 빌드하는 체인이 없다
# (2026-08-12, TF-M4).
clean() {
  rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out
}

run_chain() {
  local name="$1"
  local script="$2"

  for i in 1 2 3; do
    echo "=== ${name} run ${i}/3 ==="
    clean
    if ! "$script"; then
      echo "${name} FAIL: run ${i}/3 failed"
      exit 1
    fi
    echo "=== ${name} run ${i}/3 PASSED ==="
  done

  echo "${name} PASS: 3/3 consecutive runs succeeded"
}

# BF 체인은 limine ISO 부팅 경로를, TF 체인은 부팅 이후의 전체 런타임
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. DF 체인(display/check.sh)은
# TF-M4에서 은퇴했다 — 이유는 그 파일 머리말 참고.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh

echo "TARS check PASS: all chains 3/3 consecutive runs succeeded"
