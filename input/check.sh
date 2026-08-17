#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# IP 체인 — 키보드 입력 정책.
#
# CP 체인과 달리 부팅은 **한 번**이다. 증명할 것이 전부 한 세션 안에 있다.
# 디스크도 물리지 않는다: /config mount가 실패하면 init이 fish로 폴백하므로
# (CP design doc "설정 하나로 부팅이 막히지 않게 하는 네 장치"), 이 체인은
# 그 폴백 경로를 덤으로 한 번 더 밟는다.
#
# 이 게이트가 증명하는 사슬 전체:
#   sendkey ctrl-c → QEMU 스캔코드 → 커널 atkbd → evdev(KEY_LEFTCTRL, KEY_C)
#   → terminal/src/input.zig가 0x03을 만든다 → pty write → 커널 line
#   discipline이 ISIG/VINTR을 보고 foreground process group에 SIGINT
#   → 자식이 죽고 셸이 프롬프트로 돌아온다
# 우리 코드가 책임지는 것은 가운데 한 칸뿐이고, 나머지는 이미 갖춰져 있다는
# 것까지 함께 확인된다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사를 부팅보다 먼저 돌린다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: input_test failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# BF/TF는 45455, CP는 45456. 죽다 만 QEMU에 엉뚱한 키를 보내지 않으려고
# 체인마다 포트를 나눈다.
MONITOR_PORT=45457

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# sendkey가 보내는 것은 문자가 아니라 **키**다. modifier는 `-`로 붙인다
# (ctrl-c는 Ctrl을 누른 채 c를 누르는 것). 게스트 쪽에서 evdev 이벤트를
# 다시 바이트로 바꾸는 것은 우리 코드(terminal/src/input.zig)이므로, 이
# 게이트는 QEMU의 스캔코드 변환과 우리 keymap 두 겹을 함께 검사한다.
type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

report_failure() {
  local msg="$1"
  echo "FAIL: ${msg}"
  echo "--- markers ---"
  local marker
  for marker in \
    "tars-init: started terminal" \
    "terminal: opened /dev/input/event0" \
    "terminal: spawned child pid" \
    "terminal: screen>" \
    "terminal: key>"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- last screen dumps ---"
  grep "terminal: screen>" "$LOG" | tail -n 5
  echo "--- tail ---"
  tail -n 60 "$LOG"
  exit 1
}

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

# "terminal: screen>" 첫 줄이 곧 DRM 열기 + 폰트 래스터라이즈 + evdev 열기 +
# 셸 spawn + 첫 렌더가 전부 끝났다는 신호다. TF/CP 체인과 같은 신호를 쓴다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
if [ "$READY" != "1" ]; then
  report_failure "terminal never rendered a prompt; there was nothing to type into"
fi
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
if [ "$CONNECTED" != "1" ]; then
  report_failure "could not connect to QEMU monitor on port ${MONITOR_PORT}"
fi

# ── 1) 죽일 자식을 하나 띄운다 ─────────────────────────────────────────
# `sleep 100 &`가 아니라 foreground로 띄운다. SIGINT는 **foreground process
# group**에만 가기 때문이다 — 그게 이 검사의 요점이다.
#
# 절대 경로로 치는 이유는 PATH다. 커널의 envp_init은 HOME과 TERM 두 개뿐이고
# (init/src/main.zig:307이 그 환경을 그대로 자식에게 넘긴다), --no-config로
# 뜬 fish가 PATH를 채워준다는 보장이 없다. 이 게이트가 증명하려는 것은 PATH
# 탐색이 아니므로 무관한 변수를 없앤다.
echo "=== typing '/usr/bin/sleep 100' ==="
type_keys slash u s r slash b i n slash s l e e p spc 1 0 0 ret
sleep 2

# ── 2) 그 자식이 정말로 셸을 막고 있는지 확인한다 ──────────────────────
# 이 검사가 없으면 게이트가 헛되게 통과할 수 있다. sleep 실행이 실패하면
# 프롬프트가 곧바로 돌아오고, 그 상태에서 Ctrl+C는 아무 일도 하지 않으며,
# 뒤의 `echo ctrlcok`은 당연히 성공한다 — 아무것도 증명하지 않은 PASS다.
#
# sleep이 foreground에 있으면 셸은 입력을 읽지 못한다. 그래서 이 줄은 tty
# 입력 큐에 쌓이기만 하고 실행되지 않아야 한다. 화면에는 line discipline의
# 에코로 "echo notdead" 행만 보이고, 출력 행(행 첫머리가 notdead인 것)은
# 없어야 한다.
#
# 쌓인 입력이 뒤의 검사를 오염시키지 않는 이유는 termios다: NOFLSH가 꺼져
# 있는 기본 상태에서 VINTR은 입력 큐를 비운다.
echo "=== typing 'echo notdead' (must NOT run) ==="
type_keys e c h o spc n o t d e a d ret
sleep 2

if grep -q "terminal: screen>.*| notdead" "$LOG"; then
  report_failure "the shell was still reading input, so /usr/bin/sleep never took the foreground (nothing for ctrl-c to kill)"
fi
echo "the foreground child is blocking the shell"

# ── 3) Ctrl+C ─────────────────────────────────────────────────────────
echo "=== sending ctrl-c ==="
echo "sendkey ctrl-c" >&3
sleep 1

# ── 4) 셸이 살아 돌아왔는지 확인 ──────────────────────────────────────
# sleep이 죽었으면 프롬프트가 돌아왔고, 이 명령이 실행되어 출력이 나온다.
#
# dumpScreen은 화면 전체를 한 줄에 찍고 행을 " | "로 나눈다(main.zig:55).
# vt.zig의 cells()가 빈 칸(codepoint 0)을 건너뛰므로 행의 첫머리는 그 행의
# 실제 첫 글자다 — 그래서 **행의 첫머리가 ctrlcok인 것**이 명령의 출력이다.
# 방금 타이핑한 명령줄 행에도 ctrlcok가 들어 있지만 그 행은 프롬프트와
# echo로 시작한다.
echo "=== typing 'echo ctrlcok' ==="
type_keys e c h o spc c t r l c o k ret

FOUND=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| ctrlcok" "$LOG"; then FOUND=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

if [ "$FOUND" != "1" ]; then
  report_failure "ctrl-c did not return the shell to a prompt (sleep survived, or the byte never arrived)"
fi
echo "ctrl-c killed the foreground child and the shell came back"

# 키가 아예 도달하지 않은 경우와 도달했지만 뜻이 틀린 경우를 구분한다.
# main.zig가 키를 PTY로 보낼 때마다 이 줄을 찍는다.
if ! grep -q "terminal: key>" "$LOG"; then
  report_failure "the terminal never forwarded a key to the PTY"
fi

if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "kernel panicked because PID 1 exited"
fi

echo "--- init log ---"
grep 'tars-init:' "$LOG" || true

echo "PASS"
exit 0
