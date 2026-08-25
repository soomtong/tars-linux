#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# CM 체인 — copy mode.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Cmd+Shift+C를 누른다
#   → evdev가 KEY_LEFTMETA·KEY_LEFTSHIFT·KEY_C를 올린다
#   → input.zig의 chord()가 그것을 .copy = .enter로 바꾸고 모드를 연다
#   → main.zig가 vt.zig의 copy 커서를 만들고 copy> 줄을 찍는다
#   → 모드 안에서 친 키가 **PTY로 나가지 않는다**
#   → Esc로 나오면 다시 나간다
#
# **음성 검사가 이 체인의 값이다.** "모드에 들어갔다"만 보면 키를 삼키는지
# 아닌지는 아무것도 증명되지 않는다 — 그리고 키가 새는 것이 이 기능의 가장
# 흔한 실패 방식이다.
#
# 음성 검사의 도구는 `terminal: key>` 줄이다. 그 줄은 PTY로 바이트가 나갈
# 때만 찍히므로(main.zig의 `if (keys.bytes.len > 0)`), 줄 개수가 안 늘어나는
# 것이 곧 "아무것도 안 나갔다"이다. 화면 내용만 보는 것보다 정확하다.
#
# grep에 -a를 붙이는 이유는 로그에 NUL이 한 바이트라도 섞이면 grep이 파일을
# binary로 취급해 "Binary file matches"만 뱉기 때문이다.
#
# 디스크를 물지 않는다. copy mode는 설정과 무관하다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 모드 분기와 copy 커서는 전부 여기서 먼저 걸러진다 — 부팅 1.5초를 쓰기 전에
# 0.1초로 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (input_test or vt_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR. 겹치지 않는
# 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지
# 않기 위해서다.
MONITOR_PORT=45461

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
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
    "terminal: screen>" \
    "terminal: copy>" \
    "terminal: clip>" \
    "terminal: scroll>" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- copy lines ---"
  grep -a 'terminal: copy>' "$LOG" | tail -n 20
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

# key> 줄이 지금까지 몇 개 찍혔는지. 음성 검사가 이 값의 변화를 본다.
key_lines() {
  grep -ac 'terminal: key>' "$LOG" || true
}

# copy> 줄에서 값 하나를 뽑는다. **언제나 마지막 줄을 본다** — 마지막 줄이
# 곧 지금의 상태다.
copy_value() {
  grep -a 'terminal: copy>' "$LOG" | tail -n 1 |
    sed -E "s/.*$1=([0-9]+).*/\1/"
}

# 마지막 프레임만 잘라낸다.
#
# **누적으로 세면 안 되는 이유**가 있다. style> 줄은 매 프레임 다시 찍히므로,
# 로그 전체에서 세면 "지금 화면이 어떻게 생겼는가"가 아니라 "부팅 이후 몇 번
# 찍혔는가"가 된다. main.zig가 한 프레임을 screen> 로 시작하므로(dumpScreen이
# render 직후 첫 번째다) 마지막 screen> 부터 파일 끝까지가 곧 마지막 프레임이다.
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

# 마지막 프레임에서 그 행의 **반전된 셀**이 몇 개인가.
#
# 기본 색은 fg=FFFFFF bg=102030이고(vt.zig의 init), 반전되면 정확히 뒤집힌
# 값이 된다. 선택도 커서도 "색 둘을 맞바꾼다"는 같은 연산이므로 둘 다 이
# 모양으로 나타난다 — 그래서 선택 **전후**를 비교해야 뜻이 생긴다.
inverted_cells() {
  last_frame | grep -acE "terminal: style> $1,[0-9]+ fg=102030 bg=FFFFFF" || true
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

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 스크롤백을 만든다 ───────────────────────────────────────────────────
#
# `seq 200`. 게스트에 seq 바이너리는 없지만 fish가 seq를 함수로 갖고 있고
# (make_initrd.sh가 fish의 functions 디렉터리를 통째로 복사한다) PATH가 비어
# 있어도 동작한다 — render/check.sh가 쓰는 것과 같은 방법이다.
#
# history가 필요한 이유는 검사 4(커서가 화면 끝에서 뷰포트를 민다) 때문이다.
echo "=== typing 'seq 200' ==="
type_keys s e q spc 2 0 0 ret
sleep 3

# ── 검사 1: 대조군 — 모드 밖에서는 키가 PTY로 나간다 ───────────────────
#
# **이 검사가 없으면 아래 음성 검사가 뜻을 잃는다.** 키가 원래부터 안 나가고
# 있었다면 "모드가 삼켰다"를 증명하지 못한다.
BEFORE_CONTROL="$(key_lines)"
type_keys z
sleep 1
AFTER_CONTROL="$(key_lines)"
if [ "$AFTER_CONTROL" -le "$BEFORE_CONTROL" ]; then
  report_failure "typing outside copy mode did not reach the PTY (key> stayed at ${BEFORE_CONTROL})"
fi
echo "control: a keystroke outside copy mode reached the PTY (${BEFORE_CONTROL} -> ${AFTER_CONTROL})"

# 친 글자를 지운다. 뒤의 검사들이 깨끗한 입력줄을 보게 한다.
type_keys backspace
sleep 1

# ── 모드에 들어간다 ─────────────────────────────────────────────────────
#
# QEMU monitor의 조합 키는 `-`로 잇는다. meta_l이 Cmd, shift가 Shift다.
# **세 키 조합이 게스트까지 도착하는지가 design 위험 4다** — 실패하면 아래
# 검사 2가 걸리고, 그때는 진입키를 두 키 조합으로 바꾼다.
echo "=== entering copy mode (Cmd+Shift+C) ==="
type_keys meta_l-shift-c
sleep 2

# ── 검사 2: 모드에 들어갔는가 ───────────────────────────────────────────
ENTER_LINE="$(grep -aE 'terminal: copy> enter row=[0-9]+ col=[0-9]+' "$LOG" | tail -n 1)"
if [ -z "$ENTER_LINE" ]; then
  report_failure "Cmd+Shift+C did not open copy mode (no 'copy> enter' line)"
fi
echo "entered copy mode: ${ENTER_LINE}"

# ── 검사 3: 음성 검사 — 모드 안에서 친 키가 PTY로 안 샌다 ──────────────
#
# **이 체인에서 CM-M0이 더하는 가장 값진 검사다.** q w e r t는 copy mode의
# 명령이 아니므로 전부 삼켜져야 하고, Enter도 마찬가지다.
#
# 두 겹으로 본다. (1) key> 줄이 안 늘어난다 = PTY로 바이트가 안 나갔다.
# (2) 화면에 qwert가 없다 = 셸이 그것을 되울리지 않았다. 앞의 것이 정확하고
# 뒤의 것은 사람이 로그를 볼 때 이해하기 쉽다.
BEFORE_LEAK="$(key_lines)"
echo "=== typing 'qwert' and Enter inside copy mode (should be swallowed) ==="
type_keys q w e r t ret
sleep 2
AFTER_LEAK="$(key_lines)"
if [ "$AFTER_LEAK" -ne "$BEFORE_LEAK" ]; then
  report_failure "keys leaked to the PTY inside copy mode (key> ${BEFORE_LEAK} -> ${AFTER_LEAK})"
fi
if grep -aq 'terminal: screen>.*qwert' "$LOG"; then
  report_failure "the shell echoed 'qwert' — copy mode did not swallow the keys"
fi
echo "copy mode swallowed every key (key> stayed at ${AFTER_LEAK})"

# ── 검사 4: 커서가 움직이고, 화면 끝에서는 뷰포트가 대신 움직인다 ──────
#
# **커서는 셸 커서 자리에서 시작하고, 셸 프롬프트는 맨 아랫줄에 있다.**
# 그래서 첫 이동으로 j를 쓸 수 없다 — 커서가 이미 max_y이고 뷰포트도 바닥
# 이라 아무 데도 못 간다(2026-08-24에 이 게이트가 실제로 그렇게 걸렸다).
# 먼저 k로 한 줄 올라가고, 그다음 j로 되돌아온다. 위아래 둘 다 정확한 값을
# 요구하므로 "움직이기만 하면 통과"가 되지 않는다.
ROW_START="$(copy_value row)"
type_keys k
sleep 1
ROW_UP="$(copy_value row)"
if [ "$ROW_UP" -ne "$((ROW_START - 1))" ]; then
  report_failure "k moved the cursor from row ${ROW_START} to ${ROW_UP} (expected $((ROW_START - 1)))"
fi
echo "k moved the copy cursor ${ROW_START} -> ${ROW_UP}"

type_keys j
sleep 1
ROW_DOWN="$(copy_value row)"
if [ "$ROW_DOWN" -ne "$ROW_START" ]; then
  report_failure "j moved the cursor from row ${ROW_UP} to ${ROW_DOWN} (expected ${ROW_START})"
fi
echo "j moved the copy cursor back ${ROW_UP} -> ${ROW_DOWN}"

COL_BEFORE="$(copy_value col)"
type_keys l
sleep 1
COL_AFTER="$(copy_value col)"
if [ "$COL_AFTER" -ne "$((COL_BEFORE + 1))" ]; then
  report_failure "l moved the cursor from col ${COL_BEFORE} to ${COL_AFTER} (expected $((COL_BEFORE + 1)))"
fi
echo "l moved the copy cursor ${COL_BEFORE} -> ${COL_AFTER}"

# ── 검사 5: 맨 위에 닿으면 뷰포트가 올라간다 ───────────────────────────
#
# 커서를 맨 윗줄까지 올리고(화면이 47줄이라 46번이 필요하다) 한참 더 올린다.
# 그러면 커서는 row=0에 남고 scroll> offset이 줄어야 한다. 80번을 보내는
# 것은 0.05초 간격에서 게스트가 몇 개를 놓쳐도 닿게 하기 위한 여유다.
SCROLL_BEFORE="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
  sed -E 's/.*offset=([0-9]+).*/\1/')"
echo "=== pushing the cursor to the top of the viewport ==="
for _ in $(seq 1 80); do
  echo "sendkey k" >&3
  sleep 0.05
done
sleep 2
SCROLL_AFTER="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
  sed -E 's/.*offset=([0-9]+).*/\1/')"
ROW_TOP="$(copy_value row)"
if [ "$ROW_TOP" -ne 0 ]; then
  report_failure "the cursor stopped at row ${ROW_TOP} instead of reaching row 0"
fi
if [ "$SCROLL_AFTER" -ge "$SCROLL_BEFORE" ]; then
  report_failure "the viewport did not follow the cursor up (offset ${SCROLL_BEFORE} -> ${SCROLL_AFTER})"
fi
echo "the viewport followed the cursor up (offset ${SCROLL_BEFORE} -> ${SCROLL_AFTER})"

# ── 검사 6: Esc로 나오고, 나온 뒤에는 다시 PTY로 나간다 ────────────────
#
# **이 대조군이 없으면 "영영 못 나온다"도 통과한다.**
echo "=== leaving copy mode (Esc) ==="
type_keys esc
sleep 2
if ! grep -aq 'terminal: copy> exit' "$LOG"; then
  report_failure "Esc did not leave copy mode (no 'copy> exit' line)"
fi

BEFORE_AGAIN="$(key_lines)"
type_keys z
sleep 1
AFTER_AGAIN="$(key_lines)"
if [ "$AFTER_AGAIN" -le "$BEFORE_AGAIN" ]; then
  report_failure "keys stopped reaching the PTY after leaving copy mode (key> stayed at ${BEFORE_AGAIN})"
fi
echo "keys reach the PTY again after leaving copy mode (${BEFORE_AGAIN} -> ${AFTER_AGAIN})"

# ── 검사 7: 복사할 줄을 만든다 ─────────────────────────────────────────
#
# 검사 6이 친 z가 입력줄에 남아 있다. 지우고 시작한다.
type_keys backspace
sleep 1

# 복사 대상을 `echo echo PASTED`의 **출력 줄**로 만드는 것이 요령이다
# (design 결정 7). sendkey로 따옴표를 치지 않아도 되고, 화면에 그 글자만
# 있는 줄이 하나 생긴다. 대문자는 shift-를 붙인다.
echo "=== typing 'echo echo PASTED' ==="
type_keys e c h o spc e c h o spc shift-p shift-a shift-s shift-t shift-e shift-d ret
sleep 3

# screen> 은 행 사이를 ' | '로 구분하므로(main.zig의 dumpScreen), "어떤 줄에
# 그 글자만 있다"는 '| echo PASTED |'로 쓸 수 있다.
if ! grep -aqF '| echo PASTED |' "$LOG"; then
  report_failure "the shell did not produce a line containing only 'echo PASTED'"
fi
echo "the output line is on the screen"

# ── 검사 8: 줄을 잡으면 그 줄이 반전되어 보인다 ────────────────────────
echo "=== entering copy mode again ==="
type_keys meta_l-shift-c
sleep 2
ROW_ENTER="$(copy_value row)"

# 출력 줄은 프롬프트 바로 위다. **커서는 언제나 맨 아랫줄(프롬프트)에서
# 시작하므로 위로 한 칸이 그 줄이다**(CM-M0 실측).
type_keys k
sleep 1
ROW_TARGET="$(copy_value row)"
if [ "$ROW_TARGET" -ne "$((ROW_ENTER - 1))" ]; then
  report_failure "k moved the cursor from row ${ROW_ENTER} to ${ROW_TARGET} (expected $((ROW_ENTER - 1)))"
fi

# 대조군. **선택하기 전에 그 줄에서 반전된 셀은 copy 커서 하나뿐이다.**
# 이것이 없으면 아래 검사가 "원래부터 색이 있었다"로도 통과한다.
BEFORE_SEL="$(inverted_cells "$ROW_TARGET")"
if [ "$BEFORE_SEL" -ne 1 ]; then
  report_failure "row ${ROW_TARGET} had ${BEFORE_SEL} inverted cell(s) before selecting (expected exactly 1: the copy cursor)"
fi

echo "=== selecting the line (V) ==="
type_keys shift-v
sleep 2
if ! grep -aqE "terminal: copy> select_line row=${ROW_TARGET} col=[0-9]+" "$LOG"; then
  report_failure "V did not produce a 'copy> select_line' line for row ${ROW_TARGET}"
fi

# `echo PASTED`는 11자다. 거기에 커서 셀이 하나 더 있다 — 커서는 col 11에
# 있고 선택은 col 0..10이라 겹치지 않기 때문이다. 겹쳤다면 두 번 뒤집혀
# 상쇄되므로 11이 된다. 그래서 하한을 11로 둔다.
AFTER_SEL="$(inverted_cells "$ROW_TARGET")"
if [ "$AFTER_SEL" -lt 11 ]; then
  report_failure "row ${ROW_TARGET} has ${AFTER_SEL} inverted cell(s) after V (expected at least 11)"
fi
echo "the selection reached the renderer (row ${ROW_TARGET}: ${BEFORE_SEL} -> ${AFTER_SEL} inverted cells)"

# ── 검사 9: y가 그 글자를 클립보드에 담고 모드를 닫는다 ────────────────
echo "=== yanking (y) ==="
type_keys y
sleep 2

# len과 text를 **한 줄에서 함께** 본다. text만 보면 뒤에 뭐가 더 붙어도
# 통과하고, len만 보면 다른 11자여도 통과한다.
if ! grep -aq 'terminal: clip> len=11 text=echo PASTED' "$LOG"; then
  report_failure "y did not put 'echo PASTED' on the clipboard"
fi
if ! grep -aq 'terminal: copy> yank' "$LOG"; then
  report_failure "no 'copy> yank' line — the yank command never reached main.zig"
fi
echo "the clipboard holds the output line"

# 대조군. **이것이 없으면 "복사는 했는데 모드에 갇혀 있다"가 통과한다.**
# key> 줄은 PTY로 바이트가 나갈 때만 찍히므로, 그것이 늘어나는 것이 곧
# "모드가 닫혔다"이다.
BEFORE_YANK_EXIT="$(key_lines)"
type_keys z
sleep 1
AFTER_YANK_EXIT="$(key_lines)"
if [ "$AFTER_YANK_EXIT" -le "$BEFORE_YANK_EXIT" ]; then
  report_failure "keys stopped reaching the PTY after y (key> stayed at ${BEFORE_YANK_EXIT})"
fi
echo "keys reach the PTY again after y (${BEFORE_YANK_EXIT} -> ${AFTER_YANK_EXIT})"

type_keys backspace
sleep 1

# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
#
# grep -qP '\x00'은 GNU grep 3.11에서 매치되지 않으므로 바이트 수를 센다.
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "CM-M1 check PASS"
