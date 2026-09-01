#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# HI 체인 — 한글 입력.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Shift+Space를 누른다
#   → input.zig의 hangulLayer가 한/영을 켠다
#   → 두벌식 키가 자모가 되고 hangul.zig가 음절로 모은다
#   → 그 글자가 **PTY로 안 나가고** 커서 자리에 그려진다
#   → Backspace가 자모를 하나 뺀다
#   → Enter가 조합을 확정시켜 UTF-8 세 바이트와 CR을 **한 번에** 내보낸다
#   → **셸이 그 한글을 되울리고 실행한다**
#   → Shift+Space를 다시 누르면 영문으로 돌아온다
#
# **음성 검사가 이 체인의 값이다.** "한글이 조합된다"만 보면 조합 중인 자모가
# PTY로 새는지는 아무것도 증명되지 않는다 — 그리고 그것이 이 기능의 가장 흔한
# 실패 방식이다. 도구는 CM 체인과 같은 `terminal: key>` 줄 개수다. 그 줄은
# PTY로 바이트가 나갈 때만 찍히므로(main.zig의 `if (keys.bytes.len > 0)`)
# 개수가 안 늘어나는 것이 곧 "아무것도 안 나갔다"이다.
#
# **반전된 셀의 개수가 두 번째 도구다.** 한글은 두 칸이라(HI-M0 실측 3) 조합
# 중에는 커서가 두 칸을 반전한다. 하나만 반전되면 게스트 화면에서 글자의
# 오른쪽 절반이 어두운 바탕에 어두운 색으로 그려져 사라지는데, 로그만 보는
# 게이트가 그 사고를 잡는 길이 이 셀 개수다.
#
# grep에 -a를 붙이는 이유는 로그에 NUL이 한 바이트라도 섞이면 grep이 파일을
# binary로 취급해 "Binary file matches"만 뱉기 때문이다.
#
# 디스크를 물지 않는다. HI-M1의 한/영은 설정과 무관하다 — 자판과 전환 키가
# 설정으로 가는 것은 HI-M2·M3이고, 그때 이 체인에 2차 부팅이 붙는다.

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

# 한글 층의 분기 순서와 확정 목록은 전부 여기서 먼저 걸러진다 — 부팅 1.5초를
# 쓰기 전에 0.1초로 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (input_test, vt_test or hangul_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR, 45461=CM.
# 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에
# 명령을 보내지 않기 위해서다.
MONITOR_PORT=45462

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
    "terminal: hangul>" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- hangul lines ---"
  grep -a 'terminal: hangul>' "$LOG" | tail -n 20
  echo "--- key lines ---"
  grep -a 'terminal: key>' "$LOG" | tail -n 10
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# key> 줄이 지금까지 몇 개 찍혔는지. 음성 검사가 이 값의 변화를 본다.
key_lines() {
  grep -ac 'terminal: key>' "$LOG" || true
}

# 마지막 hangul> 줄에서 값 하나를 뽑는다. **언제나 마지막 줄을 본다** — 그
# 줄이 곧 지금의 상태다.
#
# **`tr -d '\r'`이 없으면 안 된다.** 시리얼 로그는 줄을 CRLF로 끝내는데
# `preedit=`은 줄 끝이라 `[^ ]+`가 CR까지 삼킨다. 증상이 지독하다 —
# `preedit=가, expected 가`처럼 **똑같아 보이는 값으로 실패한다.**
# `copy/check.sh`의 `copy_value`가 이 함정을 안 밟은 것은 `([0-9]+)`로 잡아
# 숫자에서 멈추기 때문이고, 우연이지 설계가 아니다.
hangul_field() {
  grep -a 'terminal: hangul>' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E "s/.*$1=([^ ]+).*/\1/"
}

# 마지막 프레임만 잘라낸다. main.zig가 한 프레임을 screen> 로 시작하므로
# (dumpScreen이 render 직후 첫 번째다) 마지막 screen> 부터 파일 끝까지가 곧
# 마지막 프레임이다. **누적으로 세면 "부팅 이후 몇 번 찍혔는가"가 된다.**
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

# 마지막 프레임에서 **반전된 셀**이 전부 몇 개인가.
#
# 기본 색은 fg=FFFFFF bg=102030이고(vt.zig의 init), 반전되면 정확히 뒤집힌
# 값이 된다. 이 화면에는 선택도 매치도 없으므로 반전된 셀은 커서뿐이고,
# 그래서 개수가 곧 "커서가 몇 칸을 먹었는가"다.
inverted_cells() {
  last_frame | grep -acE "terminal: style> [0-9]+,[0-9]+ fg=102030 bg=FFFFFF" || true
}

# 마지막 프레임의 화면 줄에서 그 문자열이 몇 번 나오는가.
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

# ── 검사 1: 대조군 — 한글이 꺼져 있으면 키가 PTY로 나간다 ──────────────
#
# **이 검사가 없으면 아래 음성 검사가 뜻을 잃는다.** 키가 원래부터 안 나가고
# 있었다면 "조합 중에 안 나간다"는 아무것도 증명하지 않는다.
echo "=== typing 'echo ' with hangul off ==="
BEFORE_ECHO="$(key_lines)"
type_keys e c h o spc
sleep 1
AFTER_ECHO="$(key_lines)"
if [ "$AFTER_ECHO" -le "$BEFORE_ECHO" ]; then
  report_failure "plain keys did not reach the PTY (key> lines ${BEFORE_ECHO} -> ${AFTER_ECHO})"
fi
if [ "$(screen_count 'echo')" -lt 1 ]; then
  report_failure "the shell never echoed 'echo'"
fi
echo "plain keys reach the PTY and the shell echoes them"

# 조합 중이 아닐 때 커서가 먹는 칸 수. 아래 검사 3이 이 값과 비교한다.
CURSOR_CELLS="$(inverted_cells)"
if [ "$CURSOR_CELLS" != "1" ]; then
  report_failure "expected exactly 1 inverted cell for the shell cursor, got ${CURSOR_CELLS}"
fi

# ── 검사 2: Shift+Space가 한/영을 켠다 ─────────────────────────────────
#
# **`hangul>` 줄이 나온다는 것 자체가 절반이다.** 그 줄은 `keys.hangul`이
# 참일 때만 찍히므로(main.zig), 줄이 없으면 `Action.hangul`이 `readKeys`까지
# 못 왔다는 뜻이다.
echo "=== sendkey shift-spc ==="
BEFORE_TOGGLE="$(key_lines)"
type_keys shift-spc
sleep 1
if ! grep -aq 'terminal: hangul>' "$LOG"; then
  report_failure "Shift+Space produced no hangul> line at all"
fi
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "Shift+Space left hangul on=${ON}, expected true"
fi
# **공백이 셸로 새면 안 된다.** 전환 키가 글자를 만들면 명령줄에 빈칸이
# 하나씩 늘어난다.
AFTER_TOGGLE="$(key_lines)"
if [ "$AFTER_TOGGLE" != "$BEFORE_TOGGLE" ]; then
  report_failure "Shift+Space leaked to the PTY (key> lines ${BEFORE_TOGGLE} -> ${AFTER_TOGGLE})"
fi
echo "Shift+Space turned hangul on and sent nothing to the shell"

# ── 검사 3: 두벌식이 조합되고, 그 글자는 PTY로 안 나간다 ───────────────
#
# `r`=ㄱ, `k`=ㅏ 라 `가`가 된다. 넷을 함께 본다.
#
#   1. `hangul> preedit=가`      — 조합 상태가 맞다
#   2. 마지막 프레임의 `screen>`에 `가`  — **화면에 실제로 그려졌다**
#   3. 반전된 셀이 **둘**        — 두 칸을 먹었다(HI-M0 실측 3)
#   4. `key>` 줄이 안 늘었다     — 음성 검사
#
# **1만 보면 "값은 맞는데 안 그렸다"를 못 잡고, 2만 보면 "그렸는데 값이
# 틀렸다"를 못 잡는다.** SP-M1의 실측 5가 같은 자리를 적어 두었다.
echo "=== typing 'rk' (가) ==="
type_keys r k
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "가" ]; then
  report_failure "typing 'rk' composed preedit=${PRE}, expected 가"
fi
if [ "$(screen_count '가')" -lt 1 ]; then
  report_failure "the composing syllable 가 was never drawn on screen"
fi
INV="$(inverted_cells)"
if [ "$INV" != "2" ]; then
  report_failure "the composing syllable took ${INV} inverted cell(s), expected 2"
fi
AFTER_JAMO="$(key_lines)"
if [ "$AFTER_JAMO" != "$AFTER_TOGGLE" ]; then
  report_failure "composing jamo leaked to the PTY (key> lines ${AFTER_TOGGLE} -> ${AFTER_JAMO})"
fi
echo "가 is composed, drawn across two cells, and nothing reached the shell"

# ── 검사 4: 받침이 붙는다 ──────────────────────────────────────────────
echo "=== typing 't' (갓) ==="
type_keys t
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "갓" ]; then
  report_failure "adding the final gave preedit=${PRE}, expected 갓"
fi
echo "the final attached: 가 -> 갓"

# ── 검사 5: Backspace가 자모를 하나 뺀다 ───────────────────────────────
#
# **음절을 통째로 지우지 않는 것이 요점이다**(design 결정 6). 그리고
# Backspace도 PTY로 안 나가야 한다 — 나가면 셸이 앞 글자를 하나 지운다.
echo "=== sendkey backspace ==="
type_keys backspace
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "가" ]; then
  report_failure "backspace gave preedit=${PRE}, expected 가"
fi
AFTER_BKSP="$(key_lines)"
if [ "$AFTER_BKSP" != "$AFTER_JAMO" ]; then
  report_failure "backspace while composing leaked to the PTY (key> lines ${AFTER_JAMO} -> ${AFTER_BKSP})"
fi
echo "backspace removed one jamo and sent nothing to the shell"

# ── 검사 6: Enter가 확정시키고 네 바이트가 한 번에 나간다 ──────────────
#
# **`key> 4 byte(s)`가 이 milestone의 결승선이다.** 확정된 음절의 UTF-8 세
# 바이트와 CR 하나가 **같은 write**로 나갔다는 뜻이고, 그것이 `readKeys`가
# 지키는 순서 계약(확정이 먼저)의 유일한 관측 가능한 증거다.
#
# 셋이 아니라 넷인 것에 뜻이 있다. 셋이면 CR이 빠진 것이고, 하나면 확정이
# 통째로 사라진 것이다.
echo "=== typing 't' then Enter ==="
type_keys t
sleep 1
type_keys ret
sleep 2
if ! grep -aq 'terminal: key> 4 byte(s)' "$LOG"; then
  report_failure "Enter did not send the committed syllable and CR as one 4-byte write"
fi
PRE="$(hangul_field preedit)"
if [ "$PRE" != "(none)" ]; then
  report_failure "Enter left preedit=${PRE}, expected (none)"
fi
echo "Enter committed 갓 and sent 3 UTF-8 bytes plus CR in one write"

# ── 검사 7: 셸이 그 한글을 되울리고 실행한다 ───────────────────────────
#
# 명령줄에 하나(`echo 갓`), 출력줄에 하나. **둘이라는 것이 왕복의 증거다** —
# 하나면 셸이 되울리기만 하고 실행은 안 된 것이고, 없으면 세 바이트가 셸에
# 도착하지 않았거나 깨진 것이다.
#
# 이 검사는 착수 전에 실측으로 확정했다. 게스트에 LANG도 LC_ALL도 없어서
# C 로케일의 fish가 UTF-8을 되울릴지 몰랐는데, HI-M1의 실측이 되울린다고
# 답했다.
if [ "$(screen_count '갓')" -lt 2 ]; then
  report_failure "the shell did not echo and run the committed syllable"
fi
echo "the shell echoed 갓 on the command line and printed it as output"

# ── 검사 8: 조합이 끝난 뒤 커서가 다시 한 칸이다 ───────────────────────
#
# 안 돌아오면 증상이 "커서가 항상 두 칸으로 뚱뚱하다"이고, 원인은 `preedit`을
# 안 지운 것이다. **검사 3의 값과 짝이어야 뜻이 선다.**
INV="$(inverted_cells)"
if [ "$INV" != "1" ]; then
  report_failure "after committing, the cursor takes ${INV} inverted cell(s), expected 1"
fi
echo "the cursor is back to one cell"

# ── 검사 9: Shift+Space가 한/영을 끈다 ─────────────────────────────────
echo "=== sendkey shift-spc again ==="
type_keys shift-spc
sleep 1
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "the second Shift+Space left hangul on=${ON}, expected false"
fi
echo "Shift+Space turned hangul off"

# ── 검사 10: 영문이 돌아온다 ───────────────────────────────────────────
#
# **대조군이 하나 더 필요한 이유가 있다.** 검사 1은 한글을 켜기 **전**을
# 봤으므로, 껐을 때 되돌아오는지는 아무것도 말하지 않는다 — 토글이 한
# 방향으로만 동작해도 검사 1과 9가 전부 통과한다.
echo "=== typing 'rk' with hangul off ==="
BEFORE_LATIN="$(key_lines)"
type_keys r k
sleep 1
AFTER_LATIN="$(key_lines)"
if [ "$AFTER_LATIN" -le "$BEFORE_LATIN" ]; then
  report_failure "latin keys did not reach the PTY after turning hangul off"
fi
if [ "$(screen_count 'rk')" -lt 1 ]; then
  report_failure "the shell never echoed 'rk' after turning hangul off"
fi
echo "latin input is back"

# ── 검사 11: 음절 셋을 이어 쳐도 앞 글자가 안 지워진다 ─────────────────
#
# **이 검사가 없어서 HI-M1이 사고를 안고 통과했다.** 위 검사들은 음절을
# **하나만** 확정시키는데, 그러면 게스트에 UTF-8 로케일이 없어도 통과한다 —
# 로케일이 없으면 셸이 우리가 보낸 세 바이트를 한 글자가 아니라 **세 글자로**
# 읽고 바이트마다 폭을 세는데(0x80~0x9F는 0칸, 0xA0 이상은 1칸), `갓`은
# EA B0 93이라 1+1+0 = 2가 되어 **깨진 계산이 우연히 맞는 답을 낸다.**
#
# 두 번째 음절부터 어긋난 폭이 쌓여서 셸이 커서를 두 칸짜리 글자의 가운데에
# 세우고, 거기에 다음 글자를 써서 앞 글자를 지운다. 증상은 `가나다`가
# **`가 다`**로 나타나는 것이다.
#
# `가나다`가 **둘** 나와야 한다 — 명령줄과 출력줄. 깨지면 명령줄이 `가 다`가
# 되므로 하나로 준다. **출력줄은 깨져도 멀쩡하다**(그쪽은 셸이 커서를
# 계산하지 않고 쭉 쓰기만 한다). 그래서 "둘"이 판정이고 "하나 이상"은 아니다.
echo "=== typing 'echo 가나다' ==="
type_keys ctrl-c
sleep 1
type_keys e c h o spc
type_keys shift-spc
type_keys r k s k e k
type_keys ret
sleep 2
if [ "$(screen_count '가나다')" -lt 2 ]; then
  report_failure "three syllables in a row got corrupted: the command line lost a character"
fi
echo "three syllables in a row survive on the command line"

echo "HI check PASS"
