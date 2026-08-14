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
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. 한때 있던 DF 체인
# (display/check.sh)과 kernel/check.sh는 ZM-M2에서 파일까지 지웠다 — 은퇴
# 사유는 docs/decisions/project_gate_chain_composition.md 참고.
#
# CP 체인은 영속 저장소를 본다. 세 체인 중 유일하게 -drive로 디스크를 물고
# 부팅하며, 나머지 둘은 디스크 없이 부팅해도 통과해야 한다는 것 자체가
# 검사 대상이다(설정 저장소가 없다고 부팅이 막히면 안 된다).
#
# CP-M1부터 이 체인만 회차당 QEMU를 **두 번** 띄운다. 영속성은 한 번의
# 부팅으로 증명할 수 없기 때문이다 — 1차가 쓴 파일을 2차가 읽는다. 그래서
# 루트 게이트 한 번의 총 부팅 횟수는 9회가 아니라 12회다.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M1" ./config/check.sh

echo "TARS check PASS: all chains 3/3 consecutive runs succeeded"
