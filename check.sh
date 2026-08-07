#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

clean() {
  rm -rf kernel/build init/target kms/target out
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

run_chain "BF-M4" ./boot/check.sh
run_chain "DF-M3" ./display/check.sh

echo "TARS check PASS: all chains 3/3 consecutive runs succeeded"
