#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

clean() {
  rm -rf kernel/build init/target out
}

for i in 1 2 3; do
  echo "=== BF-M4 run ${i}/3 ==="
  clean
  if ! ./boot/check.sh; then
    echo "BF-M4 FAIL: run ${i}/3 failed"
    exit 1
  fi
  echo "=== BF-M4 run ${i}/3 PASSED ==="
done

echo "BF-M4 PASS: 3/3 consecutive runs succeeded"
