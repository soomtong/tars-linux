#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# TR 체인 — 색상 렌더링.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트 셸에 printf '\033[41m \033[0m' 를 타이핑한다
#   → 셸이 그 바이트를 PTY로 뱉는다
#   → libghostty-vt가 SGR 41을 파싱해 셀에 style_id를 붙인다
#   → vt.zig가 Style.bg()로 팔레트 1번(#CC6666)을 뽑아 CellGlyph.bg에 담는다
#   → main.zig가 그 색으로 셀 배경을 칠한다
#   → 프레임버퍼에서 그 픽셀을 되읽어 같은 값이 나온다
#
# **두 겹으로 보는 것이 이 체인의 값이다**(design 결정 7). style> 만 보면
# 파서가 옳고 렌더러가 틀렸을 때 통과한다 — HD-M2가 잡은 "조용한 실패"와
# 같은 종류의 구멍이다.
#
# 검사에 배경색 칠한 **공백**을 쓰는 이유는 셀 전체가 배경색이라 어느 픽셀을
# 읽어도 같기 때문이다. 글자가 있는 셀은 중앙 픽셀이 글리프의 획일 수 있다.
#
# grep에 -a를 붙이는 이유는 로그에 NUL이 한 바이트라도 섞이면 grep이 파일을
# binary로 취급해 "Binary file matches"만 뱉기 때문이다. 그러면 아래 좌표
# 파싱이 엉뚱하게 깨진다. NUL 음성 검사는 이 스크립트 뒤쪽에 있어서 그때는
# 이미 늦다 — 실제로 TR-M0을 만드는 도중에 이것 때문에 조사가 한 번 막혔다.
#
# 디스크를 물지 않는다. 색은 설정과 무관하다.

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

# TR-M0부터 이 step이 vt_test까지 돌린다. 색 해석은 전부 여기서 먼저
# 걸러진다 — 부팅 1.5초를 쓰기 전에 0.1초로 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (input_test or vt_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD. 겹치지 않는 번호를 쓰는
# 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45460

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
    "terminal: style>" \
    "terminal: pixel>" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- style/pixel lines ---"
  grep -aE 'terminal: (style|pixel)>' "$LOG" | tail -n 40
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

# ── 색을 만든다 ─────────────────────────────────────────────────────────
#
# printf '\033[41m \033[0m\n'
#
# printf는 fish와 bash 양쪽의 빌트인이라 PATH가 비어 있어도 된다
# (project_guest_environment). \e가 아니라 \033을 쓰는 것은 셸마다 \e 지원이
# 갈리기 때문이다.
echo "=== typing printf '\\033[41m \\033[0m\\n' ==="
type_keys p r i n t f spc apostrophe \
  backslash 0 3 3 bracket_left 4 1 m \
  spc \
  backslash 0 3 3 bracket_left 0 m \
  backslash n \
  apostrophe ret
sleep 3

# ── 검사 1: 파서가 빨강 배경을 봤는가 ──────────────────────────────────
#
# 팔레트 1번이 #CC6666이다. xterm 고전값(#CD0000)이 아니라는 것이 요점이다 —
# 2026-08-23에 컨테이너에서 직접 재서 확인했다.
STYLE_LINE="$(grep -aE 'terminal: style> [0-9]+,[0-9]+ fg=[0-9A-F]{6} bg=CC6666' "$LOG" | tail -n 1)"
if [ -z "$STYLE_LINE" ]; then
  report_failure "the parser never reported a red background (SGR 41 -> palette[1] = CC6666)"
fi
echo "parser saw the red background: ${STYLE_LINE}"

# 그 셀의 좌표를 뽑는다. 행·열을 게이트에 하드코딩하지 않는 이유는 프롬프트의
# 길이에 따라 출력 줄의 위치가 달라지기 때문이다.
CELL="$(echo "$STYLE_LINE" | sed -E 's/.*style> ([0-9]+,[0-9]+) .*/\1/')"

# ── 검사 2: 렌더러가 그 색을 픽셀로 옮겼는가 ───────────────────────────
#
# **이 체인에서 가장 값진 검사다.** 위의 검사만 있으면 파서가 옳고 렌더러가
# 틀렸을 때 게이트가 통과한다.
if ! grep -aq "terminal: pixel> ${CELL} = CC6666" "$LOG"; then
  echo "FAIL: the parser said CC6666 at ${CELL} but the framebuffer says otherwise"
  echo "--- what the framebuffer actually held ---"
  grep -a "terminal: pixel> ${CELL} =" "$LOG" | tail -n 5
  report_failure "renderer did not paint the background color the parser resolved"
fi
echo "the framebuffer really holds CC6666 at ${CELL}"

# ── 검사 3: 커서가 그려지는가 ──────────────────────────────────────────
#
# 커서는 기본 색을 맞바꾼 셀이다 — fg=102030 bg=FFFFFF. 이 검사가 없으면
# 커서가 조용히 사라져도 아무도 모른다(vt_test는 호스트에서만 본다).
if ! grep -aq "terminal: style> [0-9]*,[0-9]* fg=102030 bg=FFFFFF" "$LOG"; then
  report_failure "no inverted cell on screen, so the cursor was never drawn"
fi
echo "the cursor is on screen as an inverted cell"

# ── 음성 검사 ──────────────────────────────────────────────────────────

# 화면 덤프에 NUL이 섞이면 안 된다. 빈 셀이 결과에 들어오기 시작했으므로
# (design 결정 3) dumpScreen이 그것을 안 거르면 utf8Encode(0)이 NUL을 만든다.
#
# `grep -qP '\x00'`을 쓰지 않는다. GNU grep 3.11에서 그것은 NUL이 든 파일에도
# **매치되지 않는다** — 그대로 뒀으면 항상 통과하는 가짜 검사가 된다
# (plan을 쓰면서 컨테이너에서 확인했다). 바이트 수를 세는 쪽은 확실하다.
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "a NUL byte leaked into the log (dumpScreen did not skip empty cells)"
fi
echo "no NUL bytes in the log"

# 상한에 걸렸다면 게이트가 보는 셀이 잘려나갔을 수 있다. 지금 화면에서
# 16셀을 넘길 일은 없으므로, 넘겼다면 무언가 예상과 다르다.
if grep -aq "terminal: style> .* more cell(s) not shown" "$LOG"; then
  report_failure "the style dump hit its limit, so the gate may be reading a truncated view"
fi

if grep -aq "Attempted to kill init" "$LOG"; then
  report_failure "init died"
fi

echo "--- style/pixel lines ---"
grep -aE 'terminal: (style|pixel)>' "$LOG" | tail -n 20
echo "TR-M0 PASS: the color the parser resolved is the color in the framebuffer"
