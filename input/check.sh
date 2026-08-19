#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# IP 체인 — 키보드 입력 정책.
#
# IP-M2부터 부팅이 **두 번**이다.
#
#   1차 — 디스크 없이. /config mount가 실패하면 init이 기본값(fish, apple)로
#         폴백하므로 이 체인은 그 폴백 경로를 덤으로 밟는다. Ctrl+C · TERM ·
#         방향키 · Option/Cmd를 여기서 본다.
#   2차 — keyboard=pc가 이미 적힌 디스크를 물고. 같은 물리 키가 1차와
#         **반대로** 동작하는 것을 본다.
#
# 2차를 붙인 이유는 디스크가 없으면 설정이 영원히 apple이라 pc 경로를
# **구조적으로** 밟을 방법이 없기 때문이다 — 게이트가 못 보는 것은 게이트가
# 통과시킨다(docs/decisions/project_gate_chain_composition.md). DECCKM과
# 달리 이건 우리가 파일 한 줄로 켤 수 있으므로 켠다.
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

# 2차 부팅이 -drive에 넘길 이미지의 절대 경로를 만들 때 쓴다
# (config/check.sh와 같은 자리, 같은 이유).
REPO_ROOT="$(cd .. && pwd)"

LOG1="$(mktemp)"
LOG2="$(mktemp)"
# 아래 검사들은 전부 $LOG를 본다. 부팅이 둘이 되면서 이 변수가 "지금 보고
# 있는 로그"를 가리키게 했다 — 2차 부팅 앞에서 LOG="$LOG2" 한 줄만 놓으면
# 되고, report_failure는 언제나 현재 부팅의 로그를 보여준다.
LOG="$LOG1"
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
    "TERM" \
    "terminal: keyboard="; do
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

# 게스트를 띄우고 프롬프트가 그려질 때까지 기다린 뒤 monitor를 연결한다.
# $1 = 시리얼 로그, 나머지 = 추가 QEMU 인자(2차 부팅의 -drive).
#
# 함수로 뽑은 이유는 두 부팅이 같은 일을 하고 2차만 -drive가 붙기 때문이다.
#
# "terminal: screen>" 첫 줄이 곧 DRM 열기 + 폰트 래스터라이즈 + evdev 열기 +
# 셸 spawn + 첫 렌더가 전부 끝났다는 신호다. TF/CP 체인과 같은 신호를 쓴다.
start_guest() {
  local log="$1"; shift
  qemu-system-x86_64 \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -display none \
    -serial file:"$log" \
    -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
    -no-reboot "$@" &
  QEMU_PID=$!

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    report_failure "terminal never rendered a prompt; there was nothing to type into"
  fi
  sleep 1

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    report_failure "could not connect to QEMU monitor on port ${MONITOR_PORT}"
  fi
}

# monitor를 닫고 QEMU를 확실히 끝낸다. 2차 부팅이 같은 monitor 포트를 다시
# 열기 때문에 wait까지 한다 — 죽다 만 QEMU가 남아 있으면 2차의 sendkey가
# 어디로 가는지 알 수 없다.
stop_guest() {
  exec 3<&-
  exec 3>&-
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""
}

echo "=== boot 1/2: no disk, so the config falls back to its defaults ==="
start_guest "$LOG"

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

if [ "$ARROW_IGNORED" = "1" ]; then
  report_failure "the arrow keys did nothing: the line ran as 'echo abcX'"
fi
if [ "$ARROW_OK" != "1" ]; then
  report_failure "neither 'aXbc' nor 'abcX' appeared: the cursor went somewhere unexpected, or the escape sequence was wrong for this shell"
fi
echo "the arrow keys moved the cursor inside the line"

# ── 7) bash로 들어간다 (IP-M2) ────────────────────────────────────────
# 결정 8의 표는 readline과 zle의 문서로 확실하지만 fish는 자체 에디터라
# 기본 바인딩이 어긋날 수 있다(design doc 위험 2). 그래서 macOS 의미론
# 검사는 readline 지형에서 한다.
#
# 절대 경로인 이유는 PATH다. 커널의 envp_init은 HOME과 TERM 둘뿐이다
# (docs/decisions/project_guest_environment.md).
#
# --norc를 주는 이유는 다른 셸에 no-config 플래그를 주는 이유와 같다 —
# 프롬프트가 예측 가능해야 화면을 검사할 수 있다. initrd에 /.bashrc가
# 없어서 지금은 있으나 없으나 같지만, 생기는 날 조용히 달라지지 않는다.
echo "=== typing '/usr/bin/bash --norc' ==="
type_keys slash u s r slash b i n slash b a s h spc minus minus n o r c ret

# bash가 정말 떴는지. --norc로 뜬 bash의 기본 PS1은 `\s-\v\$`라 화면에
# `bash-5.2$` 같은 프롬프트가 그려진다. 방금 타이핑한 명령줄 행에는
# `bash `까지만 있고 `bash-`는 없으므로 이 패턴은 프롬프트만 잡는다.
#
# 시리얼 로그에도 bash 프롬프트가 있을 수 있지만(콘솔 셸), 패턴이
# `terminal: screen>`로 시작하므로 화면 덤프만 본다.
BASH_OK=0
for _ in $(seq 1 20); do
  if grep -q "terminal: screen>.*bash-" "$LOG"; then BASH_OK=1; break; fi
  sleep 1
done
if [ "$BASH_OK" != "1" ]; then
  report_failure "bash never drew a prompt inside the pty (is /usr/bin/bash in the initrd?)"
fi
echo "the pty shell is now bash (readline territory)"

# ── 8) Option+← = 단어 단위 왼쪽 이동 (design doc 결정 8) ──────────────
# `echo aa bb`를 친 뒤 Option+←로 단어 하나를 건너뛰고 X를 끼운다.
#
#   제대로 동작    → echo aa Xbb → 출력 행 "aa Xbb"
#   아무것도 안 감 → echo aa bbX → 출력 행 "aa bbX"
#   맨 ←가 샜다    → echo aa bXb → 출력 행 "aa bXb"
#
# 세 번째가 이 검사의 핵심이다. **IP-M1까지 Option+←는 실제로 맨 ←를
# 보내고 있었다** — Alt가 modifier로 추적되지도 않았기 때문이다. 그
# 상태와 구분되지 않으면 이 게이트는 아무것도 증명하지 않는다
# (docs/decisions/project_gate_chain_composition.md).
echo "=== typing 'echo aa bb', then alt-left X ==="
type_keys e c h o spc a a spc b b
type_keys alt-left
type_keys shift-x
type_keys ret

OPT_OK=0
OPT_NOTHING=0
OPT_PLAIN=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| aa Xbb" "$LOG"; then OPT_OK=1; break; fi
  if grep -q "terminal: screen>.*| aa bbX" "$LOG"; then OPT_NOTHING=1; break; fi
  if grep -q "terminal: screen>.*| aa bXb" "$LOG"; then OPT_PLAIN=1; break; fi
  sleep 1
done
if [ "$OPT_NOTHING" = "1" ]; then
  report_failure "alt-left produced nothing: the line ran as 'echo aa bbX'"
fi
if [ "$OPT_PLAIN" = "1" ]; then
  report_failure "alt-left leaked a bare arrow key: the line ran as 'echo aa bXb' (the chord dispatch did not intercept it)"
fi
if [ "$OPT_OK" != "1" ]; then
  report_failure "none of 'aa Xbb' / 'aa bbX' / 'aa bXb' appeared: the cursor went somewhere unexpected"
fi
echo "option+left moved the cursor by a word"

# 부수적이지만 결정적인 증거 하나. main.zig가 매 키마다 바이트 수를 찍는데,
# 이번 범위에서 **2바이트를 만드는 것은 Option 조합뿐**이다(맨 방향키는 3,
# 평문은 1). 그래서 이 한 줄이 "ESC b 경로를 실제로 밟았다"를 말한다.
if ! grep -q "terminal: key> 2 byte(s)" "$LOG"; then
  report_failure "the screen looks right but no 2-byte sequence was ever sent; something else moved the cursor"
fi

# ── 9) Cmd+← = 줄 처음으로 ────────────────────────────────────────────
# 방향을 뒤집어서 검사한다. 줄 처음에 `echo `를 끼워 넣어 그것이 명령이
# 되는 것을 본다 — 출력 행의 첫머리가 "cc dd"가 되려면 echo가 줄 **맨
# 앞**에 들어가는 수밖에 없으므로 성공 경로가 하나뿐이다.
#
#   제대로 동작 → echo cc dd → 출력 행 "cc dd"
#   실패        → cc ddecho  → bash: cc: command not found
echo "=== typing 'cc dd', then meta_l-left 'echo ' ==="
type_keys c c spc d d
type_keys meta_l-left
type_keys e c h o spc
type_keys ret

CMD_OK=0
CMD_FAILED=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| cc dd" "$LOG"; then CMD_OK=1; break; fi
  if grep -q "terminal: screen>.*command not found" "$LOG"; then CMD_FAILED=1; break; fi
  sleep 1
done
if [ "$CMD_FAILED" = "1" ]; then
  report_failure "meta_l-left did not reach the start of the line; bash tried to run 'cc' (does QEMU sendkey meta_l arrive as KEY_LEFTMETA?)"
fi
if [ "$CMD_OK" != "1" ]; then
  report_failure "'cc dd' never appeared as an output row after meta_l-left"
fi
echo "cmd+left jumped to the beginning of the line"

stop_guest

# design doc 위험 4의 관측. --no-config로 뜬 셸이 smkx를 보내지 않으면
# DECCKM은 계속 꺼져 있고 `ESC O` 경로는 게이트가 한 번도 밟지 않는다.
# 실패가 아니라 **어느 쪽이었는지 기록**이다 — 안 밟은 경로는 input_test가
# 덮는다(main.zig가 매 키마다 decckm=을 찍는다).
if grep -q "decckm=true" "$LOG"; then
  echo "DECCKM was on: this run exercised the ESC O form"
else
  echo "DECCKM stayed off: this run only exercised the ESC [ form (input_test covers the other)"
fi

# 디스크를 안 물었으므로 /config mount가 실패하고 설정은 전부 기본값이다.
# 이 줄이 그것을 못 박는다 — 2차 부팅의 keyboard=pc와 대조군이 된다.
if ! grep -q "tars-init: config shell=fish keyboard=apple" "$LOG"; then
  report_failure "the diskless boot did not fall back to the default config"
fi
if ! grep -q "terminal: keyboard=apple (swap_alt_meta=false)" "$LOG"; then
  report_failure "the terminal did not receive keyboard=apple on its argv"
fi

# 키가 아예 도달하지 않은 경우와 도달했지만 뜻이 틀린 경우를 구분한다.
# main.zig가 키를 PTY로 보낼 때마다 이 줄을 찍는다.
if ! grep -q "terminal: key>" "$LOG"; then
  report_failure "the terminal never forwarded a key to the PTY"
fi

if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "kernel panicked because PID 1 exited"
fi

echo "--- init log (boot 1) ---"
grep 'tars-init:' "$LOG" || true

# ══════════════════════════════════════════════════════ 2차 부팅 (keyboard=pc)
#
# 여기서 증명하는 것은 design doc 목표 5다 — /config/tars.conf의 한 줄이
# Alt와 Meta의 의미를 맞바꾼다. 1차 부팅은 디스크가 없어 설정이 언제나
# 기본값(apple)이라, 이 경로를 밟을 방법이 구조적으로 없었다
# (docs/decisions/project_gate_chain_composition.md의 "게이트가 구조적으로
# 밟을 수 없는 경로"). DECCKM과 달리 이건 **우리가 켤 수 있는 것**이므로
# 부팅을 하나 더 붙였다.
#
# 두 검사는 1차 부팅과 정확히 반대 모양이다.
#     alt-left     : 1차 = 단어 이동 → 2차 = 줄 처음
#     meta_l-left  : 1차 = 줄 처음   → 2차 = 단어 이동
# 둘 다 보는 이유는 "정말 교환인가"를 보기 위해서다. 한쪽만 보면 "Alt를
# Cmd로 바꿨을 뿐 Meta는 그대로"인 구현도 통과한다.
echo "=== boot 2/2: same kernel, a disk that says keyboard=pc ==="

if ! ./make_disk.sh; then
  echo "FAIL: input disk image build failed"
  exit 1
fi

LOG="$LOG2"
start_guest "$LOG" -drive file="${REPO_ROOT}/out/input.img",if=virtio,format=raw

# 설정이 파일 → PID 1 → argv → terminal로 흘렀는지를 로그 네 줄로 본다.
# 화면 검사가 실패했을 때 "설정이 안 왔다"와 "설정은 왔는데 뜻이 틀렸다"를
# 가르는 것이 이 넷이다.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG"; then
  report_failure "the second boot did not load /config/tars.conf (did the disk attach?)"
fi
if ! grep -q "tars-init: config shell=bash keyboard=pc" "$LOG"; then
  report_failure "the second boot did not parse both keys out of the config file"
fi
if ! grep -q "terminal: keyboard=pc (swap_alt_meta=true)" "$LOG"; then
  report_failure "the terminal did not receive keyboard=pc on its argv"
fi
if ! grep -q "terminal: spawned child pid .*(/usr/bin/bash)" "$LOG"; then
  report_failure "the pty shell is not bash on the second boot"
fi
echo "boot 2: the config on disk selected bash and a pc keyboard"

# ── 10) pc에서 alt-left는 Cmd 의미(줄 처음)다 ─────────────────────────
# 1차 부팅에서 이 키는 단어 이동이었다. 같은 물리 키가 반대로 동작하는
# 것이 곧 교환의 증거다.
#
#   swap 동작   → echo gg hh → 출력 행 "gg hh"
#   swap 안 됨  → gg echo hh → bash: gg: command not found
echo "=== typing 'gg hh', then alt-left 'echo ' ==="
type_keys g g spc h h
type_keys alt-left
type_keys e c h o spc
type_keys ret

PC_CMD_OK=0
PC_CMD_FAILED=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| gg hh" "$LOG"; then PC_CMD_OK=1; break; fi
  if grep -q "terminal: screen>.*command not found" "$LOG"; then PC_CMD_FAILED=1; break; fi
  sleep 1
done
if [ "$PC_CMD_FAILED" = "1" ]; then
  report_failure "alt-left still moved by a word on a pc keyboard; the swap did not happen"
fi
if [ "$PC_CMD_OK" != "1" ]; then
  report_failure "'gg hh' never appeared as an output row after alt-left"
fi
echo "on a pc keyboard, alt+left means beginning-of-line"

# ── 11) pc에서 meta_l-left는 Option 의미(단어 이동)다 ─────────────────
#   swap 동작   → echo ii Xjj → 출력 행 "ii Xjj"
#   swap 안 됨  → Xecho ii jj → bash: Xecho: command not found
#   맨 ←가 샜다 → echo ii jXj → 출력 행 "ii jXj"
echo "=== typing 'echo ii jj', then meta_l-left X ==="
type_keys e c h o spc i i spc j j
type_keys meta_l-left
type_keys shift-x
type_keys ret

PC_OPT_OK=0
PC_OPT_PLAIN=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| ii Xjj" "$LOG"; then PC_OPT_OK=1; break; fi
  if grep -q "terminal: screen>.*| ii jXj" "$LOG"; then PC_OPT_PLAIN=1; break; fi
  sleep 1
done

stop_guest

if [ "$PC_OPT_PLAIN" = "1" ]; then
  report_failure "meta_l-left leaked a bare arrow key on the second boot"
fi
if [ "$PC_OPT_OK" != "1" ]; then
  report_failure "meta_l-left did not move by a word on a pc keyboard; the swap is one-way, not a swap"
fi
echo "on a pc keyboard, meta+left means backward-word"

if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "kernel panicked because PID 1 exited on the second boot"
fi

echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG" || true

echo "PASS"
exit 0
