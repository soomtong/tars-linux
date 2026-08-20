#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# PM 체인 — 전원 관리.
#
# 이 게이트가 증명하는 사슬 전체:
#   sendkey k,i,l,l,... → 커널 atkbd → evdev → terminal/src/input.zig가
#   바이트를 만든다 → pty write → bash가 kill 빌트인을 실행한다
#   → 커널이 PID 1에게 SIGTERM을 배달한다(핸들러가 있을 때만!)
#   → init/src/power.zig가 자식을 정리하고 reboot(2)를 부른다
#   → 커널이 시스템을 멈춘다
#
# 마지막 칸을 게이트가 어떻게 보는가가 이 체인의 성격을 정한다. 우리 커널은
# ACPI가 꺼져 있어서(kernel/.config:377) reboot(POWER_OFF)이 HALT로 강등되고,
# 그때 커널이 찍는 줄이 아래 HALT_MARKER다. QEMU는 이 경우 스스로 끝나지
# 않으므로 -no-reboot을 그대로 두고 게이트가 죽인다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사 둘(config.zig의 parse, power.zig의 시그널
# 플래그). 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../terminal && zig build test); then
  echo "FAIL: input_test failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP. 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가
# 남았을 때 엉뚱한 게스트에 키를 보내지 않기 위해서다.
MONITOR_PORT=45458

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "tars-init: mounted ext2 at /config" \
    "tars-init: config shell=bash" \
    "tars-init: signal handlers installed" \
    "terminal: screen>" \
    "tars-init: shutdown requested" \
    "tars-init: sent SIGTERM to every process" \
    "tars-init: every child is gone" \
    "tars-init: filesystems synced" \
    "tars-init: calling reboot" \
    "Power off not available"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

# 게스트 셸에 한 글자씩 타이핑한다. CP·IP와 같은 함수다 — sendkey가 보내는
# 것은 문자가 아니라 **키**이므로, 대문자는 shift-를 붙여야 한다.
type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

# kill -TERM 1
KILL_KEYS=(k i l l spc minus shift-t shift-e shift-r shift-m spc 1 ret)

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="${REPO_ROOT}/out/power.img",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

# "terminal: screen>" 첫 줄이 곧 DRM 열기 + 폰트 래스터라이즈 + evdev 열기 +
# 셸 spawn + 첫 렌더가 전부 끝났다는 신호다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

# 디스크가 정말 읽혔는지 먼저 본다. 이 줄이 없으면 셸은 fish이고, 그러면
# 아래 타이핑은 kill을 못 찾아서 실패한다 — 그 실패를 시그널 처리의 실패로
# 오진하지 않도록 여기서 갈라둔다.
grep -q "tars-init: config shell=bash" "$LOG" \
  || report_failure "the config disk was not read; the shell is not bash"

# bash가 정말 떴는지. --norc로 뜬 bash의 기본 PS1은 `\s-\v\$`라 화면에
# `bash-5.2$` 같은 프롬프트가 그려진다.
BASH_OK=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*bash-" "$LOG"; then BASH_OK=1; break; fi
  sleep 1
done
[ "$BASH_OK" = "1" ] || report_failure "the PTY shell never showed a bash prompt"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

echo "=== typing 'kill -TERM 1' into the guest ==="
type_keys "${KILL_KEYS[@]}"

# 종료 순서가 도는 데 걸리는 시간은 유예 3초가 지배한다. 대화형 셸은
# SIGTERM을 무시하므로(POSIX), 셸 둘은 그 3초가 지난 뒤 SIGKILL로 죽는다.
HALT_MARKER="Power off not available: System halted instead"
DONE=0
for _ in $(seq 1 30); do
  if grep -q "$HALT_MARKER" "$LOG"; then DONE=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

[ "$DONE" = "1" ] || report_failure "the guest never halted after kill -TERM 1"

# 여기서부터는 "어떻게 멈췄는가"를 따진다. 위의 HALT_MARKER 하나만 보면
# 시스템이 멈춘 것은 알 수 있지만 **왜** 멈췄는지는 알 수 없다.
for marker in \
  "tars-init: signal handlers installed (TERM, INT)" \
  "tars-init: shutdown requested (action power_off)" \
  "tars-init: sent SIGTERM to every process" \
  "tars-init: every child is gone" \
  "tars-init: filesystems synced" \
  "tars-init: calling reboot(POWER_OFF)"; do
  grep -q "$marker" "$LOG" || report_failure "missing shutdown log line: ${marker}"
done

# 음성 검사 1 — PID 1이 죽어서 커널이 패닉한 것이 아니어야 한다. 시그널
# 처리가 잘못되면 시스템은 어차피 멈추므로, 이 검사가 없으면 위의
# HALT_MARKER는 두 가지 이유로 성립할 수 있다.
if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "the kernel panicked instead of shutting down cleanly"
fi

# 음성 검사 2 — 종료 중에 감독 루프가 자식을 되살리면 안 된다. 되살리면
# 이 줄이 둘 이상이 된다.
STARTED="$(grep -c "tars-init: started console shell" "$LOG")"
if [ "$STARTED" != "1" ]; then
  report_failure "the supervisor restarted the console shell during shutdown (started ${STARTED} times)"
fi

# 관측만 하는 줄. 셸이 SIGTERM을 무시하는 것이 정상이므로 이 줄이 나오는
# 것은 실패가 아니다. 어느 경로였는지 사람이 알 수 있게 남긴다.
if grep -q "tars-init: grace period expired" "$LOG"; then
  echo "note: the grace period expired and SIGKILL finished the job (this is the normal path)"
else
  echo "note: every child died from SIGTERM alone"
fi

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

echo "PM-M0 PASS: the guest shut itself down from a shell command"
