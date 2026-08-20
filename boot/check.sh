#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

(cd ../kernel && ./build.sh)
(cd ../init && zig build)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
./build.sh
./make_iso.sh

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

qemu-system-x86_64 \
  -cdrom ../out/tars.iso \
  -serial file:"$LOG" \
  -display none \
  -no-reboot &
QEMU_PID=$!

# limine이 ISO에서 53MB짜리 initrd를 읽어 커널에 넘기는 데만도 시간이 걸린다
# (TF-M2 이후 initrd에 42MB짜리 terminal 바이너리가 들어갔다). 에뮬레이션
# 환경에서는 더 느리다 — 고정 timeout 15초로는 커널이 첫 줄을 찍기도 전에
# 잘렸다. 배너가 나오면 즉시 끝내고, 안 나오면 최대 120초 기다린다.
FOUND=0
WAITED=0
for _ in $(seq 1 120); do
  if grep -q "Welcome to fish, the friendly interactive shell" "$LOG"; then
    FOUND=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done

GAVE_UP=0
if [ "$FOUND" = "1" ]; then
  for _ in $(seq 1 30); do
    if grep -q "tars-init: giving up on terminal" "$LOG"; then
      GAVE_UP=1
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

cat "$LOG"

if [ "$FOUND" = "1" ]; then
  echo "Boot reached the fish banner after ~${WAITED}s"
  for marker in \
    "tars-init: mounted proc at /proc" \
    "tars-init: mounted sysfs at /sys" \
    "tars-init: mounted devtmpfs at /dev" \
    "tars-init: mounted devpts at /dev/pts"; do
    if ! grep -q "$marker" "$LOG"; then
      echo "FAIL: init did not report '${marker}'"
      exit 1
    fi
  done
  echo "init mounted all four filesystems"

  # 감독 루프의 포기 경로. 이 줄이 없으면 init이 아직도 /terminal을 되살리고
  # 있다는 뜻이다.
  if [ "$GAVE_UP" != "1" ]; then
    echo "FAIL: init never gave up on the terminal"
    exit 1
  fi

  # "포기했다"는 줄 하나만으로는 그 뒤에도 계속 재시작하는 구현을 못 거른다.
  # 개수가 정책 그 자체다 — 처음 뜨고, 두 번 재시작하고, 세 번째 빠른 종료에서
  # 포기한다(main.zig의 MAX_FAST_RESTARTS = 3).
  #
  # grep -c는 매치가 0이면 종료 코드 1을 내는데 이 스크립트는 set -e라 그
  # 자리에서 죽는다. || true로 받아서 "0회였다"가 아래 판정까지 오게 한다.
  STARTS="$(grep -c "tars-init: started terminal" "$LOG" || true)"
  if [ "$STARTS" != "3" ]; then
    echo "FAIL: init started the terminal ${STARTS} times, want exactly 3"
    exit 1
  fi
  echo "init restarted the terminal twice and then gave up (started ${STARTS} times)"

  if grep -q "Attempted to kill init" "$LOG"; then
    echo "FAIL: kernel panicked because PID 1 exited"
    exit 1
  fi
  echo "PASS"
  exit 0
fi

echo "FAIL: expected fish banner not found (waited ${WAITED}s)"
exit 1
