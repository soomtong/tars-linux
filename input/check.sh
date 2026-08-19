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

# 호스트에서 도는 순수 로직 검사(config.zig의 parse). terminal/check.sh가
# input_test를 부팅 앞에서 돌리는 것과 같은 자리다 — 부팅 20초를 쓰기 전에
# 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
if ! (cd ../init && zig build test); then
  echo "FAIL: config_test failed"
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

# TERM=xterm이 진실이려면 그 terminfo가 게스트 안에 있어야 한다(design doc
# 결정 7). 없어도 부팅은 계속되고 셸은 기능을 덜 쓸 뿐이라 **조용한 실패**다 —
# 부팅해서 알아내는 것보다 여기서 cpio 목록을 보는 편이 싸고 정확하다.
#
# 파이프라인 대신 변수에 담아 case로 보는 이유는 이 스크립트의 pipefail이다.
# `... | grep -q`는 grep이 첫 매치에서 빠져나가며 앞단 cpio에 SIGPIPE를
# 일으키고, pipefail이 그것을 파이프라인 실패로 판정한다 — 파일이 있는데도
# FAIL이 난다.
INITRD_LIST="$(zcat ../kernel/initrd.cpio | cpio -t 2>/dev/null)"
case "$INITRD_LIST" in
  *usr/share/terminfo/x/xterm*) ;;
  *)
    echo "FAIL: xterm terminfo is missing from the initrd"
    echo "      (devcontainer/Dockerfile needs ncurses-base, and"
    echo "       kernel/make_initrd.sh needs to copy the file)"
    exit 1
    ;;
esac

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
    "terminal: key>" \
    "TERM"; do
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

# 판정을 여기서 한다(IP-M0에서는 QEMU를 죽인 뒤였다). 아래 검사들이 전부
# "프롬프트가 살아 있다"는 전제 위에 서 있으므로, 그 전제가 깨졌으면 더
# 진행할 이유가 없다. report_failure는 exit하고 QEMU는 trap의 cleanup이 거둔다.
if [ "$FOUND" != "1" ]; then
  report_failure "ctrl-c did not return the shell to a prompt (sleep survived, or the byte never arrived)"
fi
echo "ctrl-c killed the foreground child and the shell came back"

# ── 5) TERM이 xterm인지 (IP-M1, design doc 결정 7) ────────────────────
# sendkey는 문자가 아니라 **키**를 보내므로 대문자는 shift-로 조합한다.
# `$`는 shift-4다. 덕분에 이 줄은 Shift+문자 경로도 덤으로 한 번 더 밟는다.
#
# 출력 행(행 첫머리가 xterm인 것)을 본다. 방금 타이핑한 명령줄 행에도 TERM
# 이라는 글자가 있지만 그 행은 프롬프트와 echo로 시작한다.
echo "=== typing 'echo \$TERM' ==="
type_keys e c h o spc shift-4 shift-t shift-e shift-r shift-m ret

TERM_OK=0
for _ in $(seq 1 20); do
  if grep -q "terminal: screen>.*| xterm" "$LOG"; then TERM_OK=1; break; fi
  sleep 1
done
if [ "$TERM_OK" != "1" ]; then
  report_failure "the pty shell's TERM is not xterm (setenv before forkpty did not take effect)"
fi
echo "TERM is xterm inside the pty shell"

# ── 6) 방향키 (IP-M1의 본검사) ────────────────────────────────────────
# `echo abc`를 친 뒤 커서를 왼쪽으로 두 칸 옮기고 X를 끼운다.
#
#   방향키가 동작하면  → echo aXbc → 출력 행 "aXbc"
#   방향키가 무시되면  → echo abcX → 출력 행 "abcX"
#
# 그래서 **둘 다** 검사한다. 긍정 검사만으로는 "방향키가 통째로 무시됐다"를
# 구분할 수 없다 — 게이트는 자기가 안 보는 것을 통과시킨다
# (docs/decisions/project_gate_chain_composition.md).
#
# 방향키를 친 뒤 바로 화면을 보지 않고 Enter까지 가는 이유는, 편집 중인
# 명령줄 행은 프롬프트로 시작해서 "행 첫머리" 규칙을 쓸 수 없기 때문이다.
# 실행된 출력 행만이 깨끗한 증거다.
echo "=== typing 'echo abc', then left left X ==="
type_keys e c h o spc a b c
type_keys left left
type_keys shift-x
type_keys ret

ARROW_OK=0
ARROW_IGNORED=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| aXbc" "$LOG"; then ARROW_OK=1; break; fi
  if grep -q "terminal: screen>.*| abcX" "$LOG"; then ARROW_IGNORED=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

if [ "$ARROW_IGNORED" = "1" ]; then
  report_failure "the arrow keys did nothing: the line ran as 'echo abcX'"
fi
if [ "$ARROW_OK" != "1" ]; then
  report_failure "neither 'aXbc' nor 'abcX' appeared: the cursor went somewhere unexpected, or the escape sequence was wrong for this shell"
fi
echo "the arrow keys moved the cursor inside the line"

# design doc 위험 4의 관측. --no-config로 뜬 셸이 smkx를 보내지 않으면
# DECCKM은 계속 꺼져 있고 `ESC O` 경로는 게이트가 한 번도 밟지 않는다.
# 실패가 아니라 **어느 쪽이었는지 기록**이다 — 안 밟은 경로는 input_test가
# 덮는다(main.zig가 매 키마다 decckm=을 찍는다).
if grep -q "decckm=true" "$LOG"; then
  echo "DECCKM was on: this run exercised the ESC O form"
else
  echo "DECCKM stayed off: this run only exercised the ESC [ form (input_test covers the other)"
fi

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
