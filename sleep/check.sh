#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# LP 체인 — 절전(LP-M1). 서른번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   시리얼 셸의 /usr/bin/suspend → PID 1에 SIGUSR1(RB의 shutdown 스크립트, 이름 suspend)
#   → 감독 루프의 take()가 .sleep을 꺼내 power.sleep()으로 간다(끄는 길이 아니다)
#   → sync → /sys/power/mem_sleep에 deep → /sys/power/state에 mem → 커널이 S3로 든다
#   → QEMU가 suspended가 된다(QMP query-status) — 꺼진 것도 리셋된 것도 아니다
#   → QMP system_wakeup → 커널이 깨어난다 → PID 1의 write가 돌아와 `resumed after Nms`
#   → 시리얼 셸이 다시 답하고 terminal이 살아 있다
#
# 뚜껑은 QEMU에 없다. 뚜껑이 닫혔을 때 PID 1이 고르는 장치와 닫힘만 세는 읽기는
# devices_test가 가짜 sysfs와 pipe로 본다(9a · 10). 둘은 감독 루프에서 같은
# power.request(.sleep)으로 만나므로, 이 체인이 보는 뒤쪽 길이 뚜껑에도 그대로다.
#
# 디스크가 없는 부팅이라 셸은 fish(root)다. fish · bash · zsh에는 내장 `suspend`가 있어
# 이름만 치면 셸 자신이 멈춘다 — 그래서 전체 경로를 친다(사람은 `sudo suspend`, sudo가
# 경로로 찾는다). QMP 포트는 예약 범위(RP-M0)에서 HS의 45502 다음 빈 자리다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 뚜껑 장치 고르기 · 닫힘만 세기 · SIGUSR1 → sleep은 여기서 먼저 걸러진다(devices_test · power_test).
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

source ../gate_lib.sh

QMP_PORT=45503
WORK="$(mktemp -d)"
LOG="${WORK}/serial.log"
FIFO="${WORK}/serial.fifo"
QEMU_PID=""

# shellcheck disable=SC2329 # trap cleanup EXIT이 부른다
cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  exec 3>&- 2>/dev/null || true
  exec 4>&- 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  echo "--- context ---"
  local pattern
  for pattern in "$@"; do
    grep -aF -- "$pattern" "$LOG" | tail -5 || true
  done
  echo "--- serial log tail ---"
  tail -n 60 "$LOG" | tr -d '\r'
  exit 1
}

wait_log() {
  local want="$1" limit="${2:-30}"
  for _ in $(seq 1 $((limit * 2))); do
    grep -aqF -- "$want" "$LOG" && return 0
    sleep 0.5
  done
  return 1
}

send() { printf '%s\n' "$1" >&4; }

# QMP 명령 하나를 보내고 그 답 줄을 REPLY에 남긴다. 비동기 이벤트(`{"event": …}`)가 끼어 오므로
# `return` · `error`가 든 줄까지 읽는다(keyboard 체인의 qmp와 같은 모양).
REPLY=""
qmp() {
  echo "$1" >&3
  for _ in $(seq 1 20); do
    REPLY=""
    read -r -t 5 REPLY <&3 || break
    case "$REPLY" in
      *'"return"'*) return 0 ;;
      *'"error"'*) break ;;
    esac
  done
  fail "QMP said: ${REPLY:-nothing} to $1" "tars-init:"
}

# ICH9-LPC.disable_s3=0이 S3를 펌웨어 표(_S3)에 내놓는다. 빠지면 /sys/power/mem_sleep에 deep이
# 없어 s2idle로 자고, 아래 판정 1이 빨개진다.
rm -f "$FIFO"; mkfifo "$FIFO"
exec 4<>"$FIFO"
qemu-system-x86_64 \
  -machine q35 \
  -global ICH9-LPC.disable_s3=0 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial stdio \
  -monitor none \
  -qmp tcp:127.0.0.1:${QMP_PORT},server,nowait \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU_PID=$!

wait_log "tars-init: started console shell" 120 || fail "the console shell never started" "tars-init:" "PANIC"
wait_log "terminal: screen>" 60 || fail "terminal never rendered a screen" "terminal:"
grep -aqF "tars-init: SIGUSR1 suspends" "$LOG" || fail "PID 1 never installed the SIGUSR1 handler" "tars-init: signal"
sleep 3

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${QMP_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = 1 ] || fail "could not connect to QMP" "tars-init:"
read -r -t 5 REPLY <&3 || fail "QMP never greeted" "tars-init:"
qmp '{"execute":"qmp_capabilities"}'

echo "=== typing /usr/bin/suspend into the serial shell ==="
send "/usr/bin/suspend"

# 판정 1. PID 1이 deep을 골랐고 커널이 S3로 들었다.
wait_log "tars-init: suspend (deep)" 20 || fail "PID 1 did not suspend with deep" "tars-init: suspend" "mem_sleep"
wait_log "PM: suspend entry (deep)" 20 || fail "the kernel never entered deep suspend" "PM:" "tars-init: suspend"

# 판정 2. QEMU가 suspended다 — 꺼진 것(QEMU가 사라진다)도 리셋도 아니다.
STATUS=""
for _ in $(seq 1 40); do
  qmp '{"execute":"query-status"}'
  case "$REPLY" in *'"suspended"'*) STATUS=suspended; break ;; esac
  kill -0 "$QEMU_PID" 2>/dev/null || fail "QEMU went away instead of suspending" "tars-init:" "reboot"
  sleep 0.5
done
[ "$STATUS" = suspended ] || fail "QEMU never reported suspended (last: ${REPLY})" "PM:" "tars-init: suspend"
echo "1-2: PID 1 chose deep, the kernel entered S3 and QEMU is suspended"

# 판정 3. 깨운다. 2초를 재워 둔 것이 BOOTTIME으로 보여야 한다 — MONOTONIC이면 0에 가깝다.
sleep 2
qmp '{"execute":"system_wakeup"}'
wait_log "tars-init: resumed after" 30 || fail "PID 1 never came back from suspend" "PM:" "tars-init:" "ACPI"
grep -aqF "PM: suspend exit" "$LOG" || fail "the kernel never reported suspend exit" "PM:"
SLEPT="$(grep -aoE 'tars-init: resumed after [0-9]+ms' "$LOG" | tail -1 | grep -oE '[0-9]+')"
[ "${SLEPT:-0}" -ge 1000 ] || fail "PID 1 measured ${SLEPT:-?}ms asleep for a 2s sleep; is the clock BOOTTIME?" "tars-init: resumed"
echo "3: woke up; PID 1 measured ${SLEPT}ms asleep"

# 판정 4. 시리얼 셸이 다시 답한다. 친 글자에는 lp-42가 없다 — 나오면 셸이 printf를 실행한 것이다.
send "printf 'lp-%s\\n' 42"
wait_log "lp-42" 20 || fail "the serial shell did not answer after waking up" "lp-" "tars-init:"
# 판정 5. terminal이 살아 있다(QEMU는 깨울 때 장치를 리셋한다 — virtio-gpu 위의 terminal이 버텼는가).
send "pgrep -x terminal >/dev/null && printf 'lp-term-%s\\n' alive"
wait_log "lp-term-alive" 20 || fail "terminal is gone after waking up" "terminal:" "tars-init: terminal"
echo "4-5: the serial shell answers and terminal is alive after waking up"

# 음성 검사 — 잠이 실패하거나 PID 1이 죽으면 안 된다.
if grep -aqF "tars-init: suspend failed" "$LOG"; then fail "the write to /sys/power/state failed" "tars-init: suspend"; fi
if grep -aqF "Attempted to kill init" "$LOG"; then fail "PID 1 died" "Kernel panic"; fi
if grep -aqF "tars-init: shutdown requested" "$LOG"; then fail "suspend took the shutdown road" "tars-init: shutdown"; fi

echo "PASS"
