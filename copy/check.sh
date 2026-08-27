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
#   → V로 잡은 줄이 화면에서 반전되고 y가 그 글자를 클립보드로 옮긴다
#   → Cmd+V가 그 글자를 셸에 써 넣고, Enter를 치면 셸이 그것을 실행한다
#   → **복사한 글자가 실행 결과로 화면에 다시 나타난다**
#   → Esc로 나오면 다시 나간다
#
# **마지막 줄이 CM-M2가 더하는 값이다.** 클립보드에 글자가 담겼다는 것까지는
# CM-M1이 로그로 증명했지만, 그것이 셸에 닿는다는 것은 왕복으로만 증명된다.
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

# scroll> 줄에서 값 하나를 뽑는다. copy_value와 같은 모양이고, **언제나 마지막
# 줄을 본다** — 그 줄이 곧 지금의 뷰포트 위치다.
scroll_field() {
  grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
    sed -E "s/.*$1=([0-9]+).*/\1/"
}

# 마지막 프레임의 화면 줄에서 그 문자열이 몇 번 나오는가.
#
# **누적으로 세면 안 된다.** screen> 줄은 매 프레임 다시 찍히므로 로그 전체에서
# 세면 "부팅 이후 몇 번 찍혔는가"가 된다. last_frame이 그것을 막는다.
#
# grep -o는 겹치는 매치를 세지 않는다. 아래 검사들이 세는 두 문자열은 화면에서
# 서로 떨어져 나타나므로(사이에 프롬프트 줄이 있다) 문제가 되지 않는다.
screen_count() {
  last_frame | grep -a 'terminal: screen>' | grep -oaF "$1" | wc -l
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
SCROLL_BEFORE="$(scroll_field offset)"
echo "=== pushing the cursor to the top of the viewport ==="
for _ in $(seq 1 80); do
  echo "sendkey k" >&3
  sleep 0.05
done
sleep 2
SCROLL_AFTER="$(scroll_field offset)"
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

# ── 검사 10: 대조군 — 붙여넣기 전에는 그 줄이 어디에도 없다 ────────────
#
# **이것이 없으면 아래 검사 12가 "원래부터 화면에 있었다"로도 통과한다**
# (design 결정 7의 시나리오 6). IP-M0이 sleep에서 데인 것과 같은 병이고,
# project_gate_chain_composition이 "성공 경로가 하나뿐인가"를 물으라고 적어
# 둔 자리다.
#
# screen> 은 행 사이를 ' | '로 구분하므로 '| PASTED |'는 **그 글자만 있는 줄**을
# 뜻한다. 검사 7이 만든 '| echo PASTED |'와는 겹치지 않는다 — 거기서 PASTED
# 앞에 오는 것은 '| '가 아니라 'o '다.
#
# 마지막 프레임이 아니라 **로그 전체**를 보는 것이 일부러다. "지금 화면에
# 없다"보다 "지금까지 한 번도 없었다"가 더 강한 대조군이다.
if grep -aqF '| PASTED |' "$LOG"; then
  report_failure "a line containing only 'PASTED' was on the screen before any paste"
fi
echo "control: nothing has printed 'PASTED' on a line of its own yet"

# ── 검사 11: Cmd+V가 클립보드를 셸의 입력줄에 써 넣는다 ────────────────
#
# 붙여넣기는 화면에 **입력줄의 에코**로 나타난다. 그것을 'echo PASTED'의
# 등장 횟수로 세는데, **절대값을 쓸 수 없다** — 붙여넣기 전에 이미 둘이다.
# 검사 7이 친 명령줄 'echo echo PASTED'가 부분 문자열로 걸리고, 그 출력줄이
# 하나 더 있기 때문이다. 그래서 전후 차이를 본다.
#
# key> 줄은 여기서 쓸 수 없다. 붙여넣기는 pty.write를 직접 부르지
# keys.bytes를 거치지 않으므로 그 줄을 만들지 않는다.
ECHOES_BEFORE="$(screen_count 'echo PASTED')"
echo "=== pasting (Cmd+V) ==="
type_keys meta_l-v
sleep 3

if ! grep -aq 'terminal: clip> paste len=11' "$LOG"; then
  report_failure "Cmd+V did not write the 11-byte clipboard to the PTY"
fi
ECHOES_AFTER="$(screen_count 'echo PASTED')"
if [ "$ECHOES_AFTER" -le "$ECHOES_BEFORE" ]; then
  report_failure "the pasted text never showed up on screen ('echo PASTED' stayed at ${ECHOES_BEFORE})"
fi
echo "the clipboard reached the shell (echoes ${ECHOES_BEFORE} -> ${ECHOES_AFTER})"

# ── 검사 12: 판정 — 왕복이 닫힌다 ──────────────────────────────────────
#
# 붙여넣은 것이 실행되면 'PASTED'만 있는 줄이 새로 생긴다. 검사 10과 짝을
# 이루는 자리이고, **이 체인 전체가 증명하려는 한 문장이 여기서 참이 된다** —
# 화면에서 잡은 글자가 클립보드를 거쳐 셸까지 돌아왔다.
echo "=== running the pasted command (Enter) ==="
type_keys ret
sleep 3
if ! grep -aqF '| PASTED |' "$LOG"; then
  report_failure "the pasted command did not produce a line containing only 'PASTED'"
fi
echo "the round trip closed: a yanked line came back as the shell's output"

# ── 검사 13: copy mode 중에는 뷰포트가 출력을 따라가지 않는다 ──────────
#
# **CM-M0이 넣어 두고 아무도 밟은 적 없는 분기다**(main.zig의
# `if (!screen.copyActive()) screen.scrollToBottom();`). 모드 안에서는 셸에
# 아무것도 보낼 수 없어 출력을 만들 방법이 없었는데, 붙여넣기가 그 방법이 된다.
#
# 억제를 보려면 뷰포트가 **바닥이 아니어야 한다.** 바닥에 있으면
# scrollToBottom이 원래 아무 일도 안 하므로 억제했는지 안 했는지 구분되지
# 않는다. 그래서 먼저 위로 올린다.
echo "=== entering copy mode and scrolling up ==="
type_keys meta_l-shift-c
sleep 2
OFFSET_BOTTOM="$(scroll_field offset)"

# 커서를 맨 윗줄까지 올리고(화면이 47줄이라 46번) 한참 더 올린다. 80번을
# 0.05초 간격으로 보내도 하나도 안 떨어지는 것은 CM-M0이 실측했다.
for _ in $(seq 1 80); do
  echo "sendkey k" >&3
  sleep 0.05
done
sleep 2
OFFSET_UP="$(scroll_field offset)"
if [ "$OFFSET_UP" -ge "$OFFSET_BOTTOM" ]; then
  report_failure "the viewport did not scroll up before the paste (offset ${OFFSET_BOTTOM} -> ${OFFSET_UP})"
fi

echo "=== pasting inside copy mode ==="
PASTES_BEFORE="$(grep -ac 'terminal: clip> paste len=11' "$LOG" || true)"
type_keys meta_l-v
sleep 3
PASTES_AFTER="$(grep -ac 'terminal: clip> paste len=11' "$LOG" || true)"
if [ "$PASTES_AFTER" -le "$PASTES_BEFORE" ]; then
  report_failure "Cmd+V did nothing inside copy mode (clip> paste count stayed at ${PASTES_BEFORE})"
fi

# **모드가 안 닫혔다.** 붙여넣기는 y와 달리 모드를 건드리지 않는다. dumpCopy가
# 좌표를 찍는 것이 곧 copy 커서가 살아 있다는 뜻이다 — 모드 밖이었다면 좌표
# 없이 'copy> paste'만 찍힌다.
if ! grep -aqE 'terminal: copy> paste row=[0-9]+ col=[0-9]+' "$LOG"; then
  report_failure "the paste inside copy mode did not keep the copy cursor alive"
fi

# **판정.** 셸이 붙여넣은 글자를 되울렸는데도 뷰포트가 그대로다.
OFFSET_AFTER="$(scroll_field offset)"
if [ "$OFFSET_AFTER" -ne "$OFFSET_UP" ]; then
  report_failure "output that arrived during copy mode moved the viewport (offset ${OFFSET_UP} -> ${OFFSET_AFTER})"
fi
echo "copy mode held the viewport still while output arrived (offset stayed at ${OFFSET_UP})"

# 대조군. **이것이 없으면 "scrollToBottom이 아예 안 불린다"도 통과한다.**
# 모드를 나가고 Enter를 치면 셸이 붙여넣은 명령을 실행하고, 그 출력이 도착할
# 때는 억제가 풀려 있으므로 뷰포트가 바닥으로 돌아와야 한다.
#
# "바닥에 있다"는 offset == total - len이다(vt.zig의 scrollbar 주석).
echo "=== leaving copy mode and running the pasted command ==="
type_keys esc
sleep 1
type_keys ret
sleep 3
TOTAL_END="$(scroll_field total)"
OFFSET_END="$(scroll_field offset)"
LEN_END="$(scroll_field len)"
if [ "$OFFSET_END" -ne "$((TOTAL_END - LEN_END))" ]; then
  report_failure "the viewport did not return to the bottom after leaving copy mode (offset ${OFFSET_END}, expected $((TOTAL_END - LEN_END)))"
fi
echo "the viewport followed the output again once copy mode was closed (offset ${OFFSET_END})"

# 붙여넣은 명령이 정말로 셸까지 갔다는 것은, 그것이 **두 번째** 출력줄을
# 만드는 것으로 증명된다. Enter 하나만으로도 새 프롬프트가 생기며 뷰포트는
# 바닥으로 돌아오므로, 위 검사만으로는 "붙여넣기는 실패했는데 Enter만 먹었다"가
# 걸러지지 않는다.
PASTED_ROWS="$(screen_count '| PASTED |')"
if [ "$PASTED_ROWS" -lt 2 ]; then
  report_failure "expected two rows containing only 'PASTED' but found ${PASTED_ROWS}"
fi
echo "the paste inside copy mode reached the shell too (${PASTED_ROWS} 'PASTED' rows)"

# ── 검사 14: 단어 단위 이동 (CN-M0) ────────────────────────────────────
#
# **게이트가 보는 것은 둘뿐이다**(CN-M0 plan 결정 3): 키가 게스트까지 도달해
# 커서가 단어 단위로 움직였다는 것과, 그 키가 PTY로 안 샜다는 것이다. 선택이
# 함께 넓어지는 것은 vt_test가 정확한 문자열로 본다 — 여기서 왕복을 보려면
# 기대 문자열을 미리 정확히 적어야 하는데 그 값은 호스트 검사로만 확정된다.
#
# 대상 줄을 새로 만든다. 화면에 이미 있는 줄들은 프롬프트가 섞여 있어서 col
# 값을 미리 셀 수 없다.
#
#   col:  0....4 5 6...9 10 11...15
#         alpha  _ beta  _  gamma
echo "=== typing 'echo alpha beta gamma' ==="
type_keys e c h o spc a l p h a spc b e t a spc g a m m a ret
sleep 3

if ! grep -aqF '| alpha beta gamma |' "$LOG"; then
  report_failure "the shell did not produce a line containing only 'alpha beta gamma'"
fi

echo "=== entering copy mode for the word motions ==="
type_keys meta_l-shift-c
sleep 2

# 출력줄은 프롬프트 바로 위다(CM-M0 실측: 커서는 언제나 맨 아랫줄에서 시작).
type_keys k
sleep 1

# **커서를 col 0으로 확실히 보낸다.** copyMove의 좌우는 줄을 넘나들지 않고
# x를 0에서 멈추므로(vt.zig), h를 충분히 많이 누르면 반드시 col 0이다.
# 프롬프트 길이에 기대지 않는 것이 요점이다 — 그 길이는 fish가 정한다.
for _ in $(seq 1 40); do
  echo "sendkey h" >&3
  sleep 0.05
done
sleep 2
COL_HOME="$(copy_value col)"
if [ "$COL_HOME" -ne 0 ]; then
  report_failure "h did not reach column 0 (col ${COL_HOME})"
fi
ROW_WORD="$(copy_value row)"

# 음성 검사의 기준선. w와 b는 PTY로 나가면 안 된다.
KEYS_BEFORE_WORD="$(key_lines)"

# **판정 1.** w가 공백을 건너뛰어 'beta'의 b(col 6)로 간다. 건너뛰기가 없으면
# 여기서 5가 나온다.
type_keys w
sleep 1
COL_W1="$(copy_value col)"
if [ "$COL_W1" -ne 6 ]; then
  report_failure "w landed at col ${COL_W1} (expected 6, the 'b' of beta)"
fi

# **판정 2.** 한 번 더 누르면 'gamma'의 g(col 11)다.
type_keys w
sleep 1
COL_W2="$(copy_value col)"
if [ "$COL_W2" -ne 11 ]; then
  report_failure "the second w landed at col ${COL_W2} (expected 11)"
fi

# **판정 3.** b가 그것을 정확히 되돌린다.
type_keys b
sleep 1
COL_B1="$(copy_value col)"
if [ "$COL_B1" -ne 6 ]; then
  report_failure "b landed at col ${COL_B1} (expected 6)"
fi

# **판정 4.** 줄을 안 넘었다. 단어 이동은 줄 안의 일이다.
ROW_AFTER_WORD="$(copy_value row)"
if [ "$ROW_AFTER_WORD" -ne "$ROW_WORD" ]; then
  report_failure "the word motions changed rows (${ROW_WORD} -> ${ROW_AFTER_WORD})"
fi

# **판정 5(음성).** 셋 다 PTY로 안 나갔다. 모드 안에서 친 w가 셸에 도착하면
# 입력줄이 더럽혀지고, 그것이 이 기능의 가장 흔한 실패 방식이다.
KEYS_AFTER_WORD="$(key_lines)"
if [ "$KEYS_AFTER_WORD" -ne "$KEYS_BEFORE_WORD" ]; then
  report_failure "the word motions leaked to the PTY (key> ${KEYS_BEFORE_WORD} -> ${KEYS_AFTER_WORD})"
fi
echo "word motions moved the cursor 0 -> 6 -> 11 -> 6 without leaking to the PTY"

type_keys esc
sleep 1

# ── 검사 15: 스크롤백 검색 (CN-M1) ─────────────────────────────────────
#
# **design이 정한 완료 조건을 그대로 밟는다**: `/`로 스크롤백 위쪽의 글자를
# 찾아 커서가 그리로 옮겨진 것을 보고, 그 자리에서 V·y로 잡은 줄이 clip>에
# 나온다.
#
# 표적을 둘 만든다. 하나면 n이 "옮겼다"와 "감겼다"를 못 가른다.
#
# **needle이 소문자인 것은 QEMU의 제약이다.** `sendkey`가 받는 이름은 QKeyCode
# 이고 그것들이 전부 소문자다 — `sendkey F`는 없는 이름이라 QEMU가 조용히
# 버린다(체인은 monitor의 응답을 안 읽으므로 에러도 안 보인다). 대문자를
# 치려면 `shift-f`처럼 앞에 붙여야 하고, 그것은 여섯 글자에 여섯 번이다.
echo "=== planting two search targets ==="
type_keys e c h o spc f i n d m e ret
sleep 2
type_keys s e q spc 1 0 0 ret
sleep 4
type_keys e c h o spc f i n d m e ret
sleep 2
type_keys s e q spc 1 0 0 ret
sleep 4

# 표적이 스크롤백으로 밀려 **화면에서 사라졌는지** 확인한다. 화면에 남아
# 있으면 이 검사는 "검색"이 아니라 "화면 안에서 커서 옮기기"가 된다.
#
# **이 검사 하나만으로는 "밀려났다"와 "애초에 안 쳐졌다"를 못 가른다.** 처음
# 돌렸을 때 대문자가 통째로 버려져 `echo `만 쳐졌는데도 여기를 통과했다.
# 아래 `needle=` 검사가 그것을 잡는다.
if [ "$(screen_count 'findme')" -ne 0 ]; then
  report_failure "findme is still on screen; the search would not exercise scrollback"
fi

echo "=== searching backwards for findme ==="
type_keys meta_l-shift-c
sleep 2

FIND_BEFORE="$(key_lines)"

# `/` 를 열고 needle을 친다. **프롬프트가 화면에 나타나는지는 find> 줄로 본다** —
# 오버레이는 cells()에 안 섞이므로 screen> 에는 영영 안 나온다(design 결정 7).
type_keys slash
sleep 1
if ! grep -aq 'terminal: find> open' "$LOG"; then
  report_failure "/ did not open the find prompt"
fi

type_keys f i n d m e
sleep 1
if ! grep -aq 'terminal: find> type needle=findme len=6' "$LOG"; then
  echo "--- find> lines so far ---"
  grep -a 'terminal: find>' "$LOG" | tail -n 8
  report_failure "the prompt did not accumulate 'findme'"
fi

type_keys ret
sleep 3

SUBMIT="$(grep -a 'terminal: find> submit' "$LOG" | tail -n 1)"
# **넷인 것에 산수가 있다.** `echo findme` 한 번이 스크롤백에 두 줄을 남긴다 —
# 셸이 되비춘 명령줄 `@(none) ~# echo findme`와 출력줄 `findme`다. 표적이
# 둘이므로 2 × 2 = 4다. **plan은 이것을 2로 적었고 그것이 틀렸다.**
#
# 넷이어도 검사의 뜻은 그대로다: `/`는 가장 최근 매치인 표적 2의 **출력줄**로
# 가고, 그 줄은 글자가 `findme`뿐이라 아래의 줄 단위 yank가 정확히 여섯 자를
# 준다. `n`은 그 위의 명령줄로 올라간다.
case "$SUBMIT" in
  *"matches=4"*) ;;
  *) report_failure "expected four matches, got: ${SUBMIT}" ;;
esac
case "$SUBMIT" in
  *"moved=true"*) ;;
  *) report_failure "the search found matches but did not move the cursor: ${SUBMIT}" ;;
esac
# design 결정 5의 실측이다. **판정하지 않고 기록만 한다** — 값을 놓고 무엇을
# 할지는 사람이 정한다.
echo "search over the full scrollback: ${SUBMIT}"

# **판정(음성).** 프롬프트에 친 여섯 글자와 `/`·Enter가 PTY로 안 나갔다.
# 이것이 이 기능의 가장 흔한 실패 방식이다 — 검색어가 셸의 입력줄에 도착한다.
FIND_AFTER="$(key_lines)"
if [ "$FIND_AFTER" -ne "$FIND_BEFORE" ]; then
  report_failure "the find prompt leaked to the PTY (key> ${FIND_BEFORE} -> ${FIND_AFTER})"
fi

# **판정.** 커서가 선 줄을 줄 단위로 잡아 복사하면 findme가 나온다.
#
# 여섯 자가 나오는 것이 곧 "출력줄에 섰다"의 증거다. 명령줄에 섰다면
# `@(none) ~# echo findme`가 통째로 나와 len이 훨씬 크다.
type_keys shift-v
sleep 1
type_keys y
sleep 2
if ! grep -aq 'terminal: clip> len=6 text=findme' "$LOG"; then
  echo "--- clip> lines ---"
  grep -a 'terminal: clip>' "$LOG" | tail -n 5
  report_failure "the yanked line was not 'findme'"
fi
echo "the search reached scrollback and the yanked line was findme"

# **판정.** n이 더 위의 매치로 간다. y가 모드를 닫았으므로 다시 들어간다 —
# 그런데 copyExit이 검색 상태를 버렸으므로(design 결정 10) 검색부터 다시 한다.
# **그 버림이 곧 이 판정의 대상이다.**
echo "=== n walks to the older match ==="
type_keys meta_l-shift-c
sleep 2
type_keys slash f i n d m e ret
sleep 3

# **절대 행으로 센다.** `copy> row=`은 뷰포트 안의 행이고, 매치가 화면 밖이면
# `copyPlace`가 그 pin을 뷰포트의 맨 위로 올리므로(CN-M0) 언제나 0이다 —
# 그 값만 찍으면 "0에서 0으로 갔다"가 되어 안 움직인 것처럼 읽힌다.
# `scroll> offset`을 더하면 스크롤백 전체에서의 자리가 된다.
ROW_FIRST=$(( $(scroll_field offset) + $(copy_value row) ))
type_keys n
sleep 2
if ! grep -aq 'terminal: find> next moved=true' "$LOG"; then
  grep -a 'terminal: find> next' "$LOG" | tail -n 3
  report_failure "n did not move to another match"
fi
ROW_SECOND=$(( $(scroll_field offset) + $(copy_value row) ))
# **판정.** n은 과거 방향으로 간다(design 결정 4). 같거나 커지면 방향이
# 뒤집혔거나 안 움직인 것이고, moved=true만으로는 그것을 못 가른다.
if [ "$ROW_SECOND" -ge "$ROW_FIRST" ]; then
  report_failure "n went down or stayed (row ${ROW_FIRST} -> ${ROW_SECOND}), expected up"
fi
echo "n moved the cursor up the scrollback (row ${ROW_FIRST} -> ${ROW_SECOND})"

type_keys esc
sleep 1

# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
#
# grep -qP '\x00'은 GNU grep 3.11에서 매치되지 않으므로 바이트 수를 센다.
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "CM-M2 check PASS"
