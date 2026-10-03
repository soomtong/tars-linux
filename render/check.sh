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
# 두 겹으로 보는 것이 이 체인의 값이다(design 결정 7). style> 만 보면
# 파서가 옳고 렌더러가 틀렸을 때 통과한다 — HD-M2가 잡은 "조용한 실패"와
# 같은 종류의 구멍이다.
#
# 검사에 배경색 칠한 공백을 쓰는 이유는 셀 전체가 배경색이라 어느 픽셀을
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
    "terminal: ink>" \
    "terminal: font>" \
    "terminal: scroll>" \
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

source ../gate_lib.sh

qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
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
# 이 체인에서 가장 값진 검사다. 위의 검사만 있으면 파서가 옳고 렌더러가
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
# 커서는 그 셀의 색 둘을 맞바꾼 셀이다. 표식은 `fg`가 기본 배경색
# (102030)이라는 것이고 `bg`는 그 글자가 원래 갖고 있던 전경색이다.
# 이 검사가 없으면 커서가 조용히 사라져도 아무도 모른다(vt_test는 호스트에서만
# 본다).
#
# `bg=FFFFFF`로 박아 두었던 것을 SC-M0이 고쳤다 — 자세히는
# `hangul/check.sh`의 `inverted_cells`에 있다. 셸이 색을 쓰기 시작하면 커서
# 아래 글자의 전경색이 기본값이 아닐 수 있고, 그러면 커서가 멀쩡히 있는데도
# 이 검사가 못 본다.
if ! grep -aqE "terminal: style> [0-9]+,[0-9]+ fg=102030 bg=[0-9A-F]{6}" "$LOG"; then
  report_failure "no inverted cell on screen, so the cursor was never drawn"
fi
echo "the cursor is on screen as an inverted cell"

# ── 한글을 만든다 (TR-M1) ──────────────────────────────────────────────
#
# printf '\xed\x95\x9c\033[41m \033[0m\n'
#
# \xed\x95\x9c 가 '한'의 UTF-8 세 바이트다. QEMU monitor의 sendkey는 ASCII만
# 칠 수 있으므로 한글을 직접 못 친다 — 셸의 printf가 바이트를 만들어 주는
# 것이 유일한 길이다.
#
# 한글 바로 뒤에 배경색 칠한 공백을 붙이는 이유가 요점이다. 그 공백의
# style> 줄이 좌표를 주므로, 게이트가 한글 셀의 열 번호에 2를 더한 값과
# 비교할 수 있다 — 이것이 "다음 글자가 겹치지 않는다"의 파서 쪽 증거이고,
# 아래 ink> 검사가 렌더러 쪽 증거다. 둘이 따로 틀릴 수 있다.
echo "=== typing printf '\\xed\\x95\\x9c\\033[41m \\033[0m\\n' ==="
type_keys p r i n t f spc apostrophe \
  backslash x e d backslash x 9 5 backslash x 9 c \
  backslash 0 3 3 bracket_left 4 1 m \
  spc \
  backslash 0 3 3 bracket_left 0 m \
  backslash n \
  apostrophe ret
sleep 3

# ── 검사 4: 파서가 '한'을 조립했는가 ───────────────────────────────────
#
# UTF-8 세 바이트가 코드포인트 하나로 합쳐졌다는 뜻이다. 여기서 실패하면
# 셸의 printf가 \x를 해석하지 않은 것일 수 있다 — 그 경우 8진수
# (\355\225\234)로 바꾼다.
if ! grep -aq 'terminal: screen>.*한' "$LOG"; then
  echo "FAIL: '한' never showed up on screen"
  echo "--- what the screen actually held ---"
  grep -a "terminal: screen>" "$LOG" | tail -n 5
  report_failure "the shell's printf did not produce the UTF-8 bytes for U+D55C"
fi
echo "the parser assembled U+D55C from three UTF-8 bytes"

# ── 검사 5: 렌더러가 두 칸에 걸쳐 찍었는가 ─────────────────────────────
#
# 이 체인에서 TR-M1이 더하는 가장 값진 검사다. left만 있고 right가 0이면
# 글자가 반쪽만 그려진 것인데, 셀 하나만 보는 검사로는 그것을 못 잡는다.
INK_LINE="$(grep -aE 'terminal: ink> [0-9]+,[0-9]+ U\+D55C left=[0-9]+ right=[0-9]+' "$LOG" | tail -n 1)"
if [ -z "$INK_LINE" ]; then
  report_failure "no ink line for U+D55C, so the renderer never treated it as a wide glyph"
fi
echo "ink line: ${INK_LINE}"

INK_LEFT="$(echo "$INK_LINE" | sed -E 's/.*left=([0-9]+).*/\1/')"
INK_RIGHT="$(echo "$INK_LINE" | sed -E 's/.*right=([0-9]+).*/\1/')"
if [ "$INK_LEFT" -eq 0 ] || [ "$INK_RIGHT" -eq 0 ]; then
  report_failure "U+D55C has ink on only one half (left=${INK_LEFT} right=${INK_RIGHT}), so it was drawn as a narrow glyph"
fi
echo "the glyph really covers both cells (left=${INK_LEFT} right=${INK_RIGHT})"

# ── 검사 6: 다음 글자가 두 칸 뒤에 있는가 ──────────────────────────────
#
# 한글 셀의 열 번호에 2를 더한 자리에 빨강 공백이 있어야 한다. 1이면
# 겹친 것이고, 3이면 한 칸을 버린 것이다.
HAN_ROW="$(echo "$INK_LINE" | sed -E 's/.*ink> ([0-9]+),[0-9]+ .*/\1/')"
HAN_COL="$(echo "$INK_LINE" | sed -E 's/.*ink> [0-9]+,([0-9]+) .*/\1/')"
WANT_COL=$((HAN_COL + 2))
if ! grep -aq "terminal: style> ${HAN_ROW},${WANT_COL} fg=[0-9A-F]* bg=CC6666" "$LOG"; then
  echo "FAIL: expected the red space at ${HAN_ROW},${WANT_COL} (right after a 2-cell glyph)"
  echo "--- style lines on that row ---"
  grep -aE "terminal: style> ${HAN_ROW},[0-9]+ " "$LOG" | tail -n 10
  report_failure "the character after U+D55C is not two columns away, so the wide cell was mis-counted"
fi
echo "the next character sits two columns after U+D55C"

# ── 검사 7: 캐시가 자랐고 크기가 말이 되는가 ───────────────────────────
#
# design 위험 3이 "128MB 게스트라 실측한다"고 남긴 자리다. 최악의 경우
# (한글 전체 = 2.06MB)는 font_test가 호스트에서 이미 재고, 여기서 보는 것은
# 실사용량이다. 1MB를 넘으면 무언가 예상과 다르다 — 화면에 나오는 글자는
# 수십 자이고 한 자가 평균 193바이트다.
FONT_LINE="$(grep -a 'terminal: font>' "$LOG" | tail -n 1)"
if [ -z "$FONT_LINE" ]; then
  report_failure "the font cache never reported its size"
fi
echo "font cache: ${FONT_LINE}"
FONT_BYTES="$(echo "$FONT_LINE" | sed -E 's/.*cached, ([0-9]+) bitmap bytes.*/\1/')"
if [ "$FONT_BYTES" -gt 1048576 ]; then
  report_failure "the glyph cache grew past 1MB (${FONT_BYTES} bytes) on a 128MB guest"
fi
echo "the glyph cache is ${FONT_BYTES} bytes, well inside the guest's memory"

# ── 스크롤백을 만든다 (TR-M2) ──────────────────────────────────────────
#
# `seq 200`. 게스트에 seq 바이너리는 없지만 fish가 seq를 함수로 갖고 있고
# (/usr/share/fish/functions/seq.fish, make_initrd.sh가 디렉터리째 복사한다)
# PATH가 비어 있어도 동작한다. 8타로 끝나는 것도 이유다.
#
# 200줄인 이유는 history가 한 화면(47줄)보다 넉넉히 커야 .top과 page_up이
# 서로 다른 자리로 가기 때문이다. 60줄이면 한 번의 page_up이 맨 위에 닿아
# 버려서 두 키를 구분할 수 없다. 1000줄 한도에는 한참 못 미치므로 게이트에서
# 가지치기가 일어나지 않는다 — 그래야 아래 검사들이 행 번호에 기대도 된다.
#
# 화면 내용은 `| 1 |`이 한 줄 전체와 일치한다는 성질로 본다. dumpScreen이
# 행 사이에 " | "를 넣으므로 숫자 하나뿐인 줄은 이 형태로만 나타나고, 10이나
# 21에는 걸리지 않는다. 첫 행에는 앞쪽 구분자가 없으므로 `screen> 1 |` 형태도
# 함께 본다.
echo "=== typing 'seq 200' ==="
type_keys s e q spc 2 0 0 ret
sleep 4

# scroll> 줄에서 값 하나를 뽑는다. 아래에서 여러 번 쓰므로 함수로 둔다.
# 언제나 마지막 줄을 본다 — 이 로그는 매 프레임 찍히므로 마지막 줄이 곧
# 지금의 상태다.
scroll_field() {
  grep -a 'terminal: scroll>' "$LOG" | tail -n 1 | sed -E "s/.*$1=([0-9]+).*/\1/"
}

# 지금 화면에 밀려난 첫 줄이 있는지 본다. 있으면 0, 없으면 1을 돌려준다.
#
# 파이프라인 끝에 `grep -q`를 두지 않고 변수에 담아 case로 보는 이유는 이
# 스크립트의 pipefail이다. `... | grep -q`는 grep이 첫 매치에서 빠져나가며
# 앞단에 SIGPIPE를 일으키고, pipefail이 그것을 파이프라인 실패로 판정한다 —
# input/check.sh가 initrd 목록에서 이미 한 번 데인 함정이다.
line_one_on_screen() {
  local last
  last="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"
  case "$last" in
    *"screen> 1 |"* | *"| 1 |"* | *"| 1") return 0 ;;
    *) return 1 ;;
  esac
}

# ── 검사 8: 스크롤백이 쌓였고 지금은 바닥이다 ──────────────────────────
SCROLL_LINE="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1)"
if [ -z "$SCROLL_LINE" ]; then
  report_failure "the terminal never reported a scroll position"
fi
echo "scroll line: ${SCROLL_LINE}"
TOTAL="$(scroll_field total)"
BOTTOM_OFFSET="$(scroll_field offset)"
LEN="$(scroll_field len)"
if [ "$((TOTAL - LEN))" -lt "$LEN" ]; then
  report_failure "only $((TOTAL - LEN)) rows scrolled off, which is less than one screen (${LEN}) -- the scrollback limit may not be in effect"
fi
if [ "$BOTTOM_OFFSET" -ne "$((TOTAL - LEN))" ]; then
  report_failure "the viewport is not at the bottom after output (offset=${BOTTOM_OFFSET}, expected $((TOTAL - LEN)))"
fi
echo "$((TOTAL - LEN)) rows of history exist and the viewport sits at the bottom"

# ── 검사 9: 밀려난 줄은 지금 화면에 없다 ───────────────────────────────
#
# 이 음성 검사가 없으면 검사 12가 뜻을 잃는다 — 처음부터 화면에 있었다면
# "스크롤해서 보였다"를 증명하지 못한다.
if line_one_on_screen; then
  echo "FAIL: line '1' is still on screen before scrolling"
  echo "--- the screen ---"
  grep -a 'terminal: screen>' "$LOG" | tail -n 1
  report_failure "200 lines did not push the first line off a ${LEN}-row screen"
fi
echo "line '1' has scrolled off the screen"

BOTTOM_SCREEN="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"

# ── 한 화면 올라간다 ───────────────────────────────────────────────────
#
# QEMU monitor의 키 이름은 pgup/pgdn/home/end이고 shift- 접두사를 붙인다.
echo "=== sendkey shift-pgup ==="
type_keys shift-pgup
sleep 2

# ── 검사 10: 뷰포트가 정확히 한 화면 올라갔는가 ────────────────────────
#
# 정확한 값을 요구하는 이유는 "움직이기만 하면 통과"가 되지 않게 하려는
# 것이다. rows 대신 1이나 다른 수를 넘기는 실수가 여기서 드러난다.
UP_OFFSET="$(scroll_field offset)"
if [ "$UP_OFFSET" -ne "$((BOTTOM_OFFSET - LEN))" ]; then
  report_failure "shift-pgup moved the viewport to offset=${UP_OFFSET}, expected $((BOTTOM_OFFSET - LEN)) (one screen of ${LEN} rows)"
fi
echo "the viewport moved up exactly one screen (offset ${BOTTOM_OFFSET} -> ${UP_OFFSET})"

# ── 검사 11: 화면도 함께 바뀌었는가 ────────────────────────────────────
#
# 위치 숫자만 보면 뷰포트는 움직였는데 화면은 그대로인 상태를 못 잡는다.
# 렌더를 키 쪽으로 열지 않았을 때가 정확히 그 상태다(TR-M2의 구조 변경).
UP_SCREEN="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"
if [ "$UP_SCREEN" = "$BOTTOM_SCREEN" ]; then
  echo "FAIL: the viewport moved but the screen dump is identical"
  echo "--- the screen ---"
  echo "$UP_SCREEN"
  report_failure "the renderer did not follow the viewport, so nothing was redrawn on a key"
fi
echo "the rendered frame followed the viewport"

# ── 맨 위로 간다 ───────────────────────────────────────────────────────
echo "=== sendkey shift-home ==="
type_keys shift-home
sleep 2

# ── 검사 12: 맨 위에서 밀려났던 줄이 보이는가 ──────────────────────────
#
# 이 체인에서 TR-M2가 더하는 가장 값진 검사다. 위치와 내용을 한 번에
# 본다 — offset이 0이고, 검사 9에서 없다고 확인한 바로 그 줄이 화면에 있다.
TOP_OFFSET="$(scroll_field offset)"
if [ "$TOP_OFFSET" -ne 0 ]; then
  report_failure "shift-home left the viewport at offset=${TOP_OFFSET}, expected 0"
fi
if ! line_one_on_screen; then
  echo "FAIL: at the top of the scrollback but line '1' is not on screen"
  echo "--- the screen ---"
  grep -a 'terminal: screen>' "$LOG" | tail -n 1
  report_failure "the viewport reached the top but the scrollback did not hold the first line"
fi
echo "at the top of the scrollback, the line that had scrolled off is on screen"

# ── 맨 아래로 돌아온다 ─────────────────────────────────────────────────
echo "=== sendkey shift-end ==="
type_keys shift-end
sleep 2

# ── 검사 13: 바닥으로 돌아왔는가 ───────────────────────────────────────
END_OFFSET="$(scroll_field offset)"
if [ "$END_OFFSET" -ne "$((TOTAL - LEN))" ]; then
  report_failure "shift-end left the viewport at offset=${END_OFFSET}, expected $((TOTAL - LEN))"
fi
if line_one_on_screen; then
  report_failure "back at the bottom but line '1' is still on screen"
fi
echo "shift-end brought the viewport back to the bottom"

# ── 출력이 오면 저절로 내려온다 (design 결정 13) ───────────────────────
#
# 올라간 상태에서 글자 하나를 친다. 셸이 그것을 되울려 보내므로 PTY 출력이
# 도착하고, 그때 우리가 scrollToBottom()을 불러야 한다. 라이브러리는 이
# 일을 해 주지 않는다 — vt_test가 호스트에서 그 사실을 못 박고 있고,
# 여기서는 우리 코드가 그것을 메웠는지를 본다.
echo "=== sendkey shift-pgup, then a plain key ==="
type_keys shift-pgup
sleep 2
AWAY_OFFSET="$(scroll_field offset)"
if [ "$AWAY_OFFSET" -eq "$((TOTAL - LEN))" ]; then
  report_failure "could not scroll away from the bottom before testing the snap-back"
fi
type_keys x
sleep 2

# ── 검사 14: 새 출력이 뷰포트를 바닥으로 데려왔는가 ────────────────────
SNAP_OFFSET="$(scroll_field offset)"
SNAP_TOTAL="$(scroll_field total)"
if [ "$SNAP_OFFSET" -ne "$((SNAP_TOTAL - LEN))" ]; then
  report_failure "output arrived while scrolled up (offset=${AWAY_OFFSET}) but the viewport stayed at offset=${SNAP_OFFSET} instead of $((SNAP_TOTAL - LEN))"
fi
echo "output snapped the viewport back to the bottom (offset ${AWAY_OFFSET} -> ${SNAP_OFFSET})"

# 친 글자를 지운다. 뒤에 오는 음성 검사들이 깨끗한 화면을 보게 한다.
type_keys backspace
sleep 1

# ── kitty 이미지 — TG-M2 ────────────────────────────────────────────────
#
# 셸이 printf로 이미지 둘을 보낸다.
#
#   1. 2×2 RGB(빨강 · 초록 · 파랑 · 흰색)를 c=4,r=2로 → 32×32, 사분면마다 한 색
#   2. 반투명 흰색(a=0x80) 1×1 RGBA를 c=2,r=1로 → 16×16, 바탕 102030 위에서 889098
#
# 끝의 `ESC \`를 `\033\134`로 쓴다. 이 부팅의 셸은 fish(설정 디스크가 없다)이고
# fish는 작은따옴표 안에서도 `\\`를 `\` 하나로 바꾼다 — 8진수면 printf만
# 해석한다. `q=2`는 답을 끈다. 답이 나가면 셸의 입력 줄에 글자가 찍힌다
# (TG 실측 3).
#
# 문자 하나를 sendkey 이름 하나로 바꾼다. 이 체인에서만 쓰므로 여기 둔다.
type_text() {
  local s="$1" ch keys=() i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
      [a-z0-9]) keys+=("$ch") ;;
      [A-Z]) keys+=("shift-${ch,,}") ;;
      ' ') keys+=(spc) ;;
      "'") keys+=(apostrophe) ;;
      '\') keys+=(backslash) ;;
      '_') keys+=(shift-minus) ;;
      '=') keys+=(equal) ;;
      ',') keys+=(comma) ;;
      ';') keys+=(semicolon) ;;
      '/') keys+=(slash) ;;
      '-') keys+=(minus) ;;
      *) report_failure "type_text has no key for '${ch}'" ;;
    esac
  done
  type_keys "${keys[@]}"
}

# 이 앞까지의 로그 크기. 아래 style 상한 음성 검사가 이 앞만 본다 — 이미지
# 명령 줄은 fish가 문자열 전체에 구문 강조 색(F0C674)을 입혀 16셀 상한을
# 넘긴다(TG-M2에서 처음 봤다). 그 검사가 지키는 것은 검사 1~14가 읽은
# 덤프이고, 이미지 검사는 style> 줄을 안 읽는다.
IMG_LOG_START="$(wc -c < "$LOG")"
IMG1_PAYLOAD='/wAAAP8AAAD/////'
echo "=== typing two kitty image commands ==="
type_text "printf '\\033_Ga=T,f=24,s=2,v=2,i=1,c=4,r=2,q=2;${IMG1_PAYLOAD}\\033\\134\\n'"
type_keys ret
sleep 3
type_text "printf '\\033_Ga=T,f=32,s=1,v=1,i=2,c=2,r=1,q=2;////gA==\\033\\134\\n'"
type_keys ret
sleep 3

# ── 검사 15: vt.zig가 셀 크기를 알고 사각형을 냈는가 ───────────────────
#
# 셀 크기가 비어 있으면 c=4,r=2가 0×0이 된다(TG 실측 2).
if ! grep -aqE 'terminal: image> id=1 layer=above_text dst=[0-9]+,[0-9]+ 32x32 src=0,0 2x2 ' "$LOG"; then
  grep -a 'terminal: image>' "$LOG" | tail -n 5
  report_failure "no 32x32 image> line for image 1 (did vt.zig get the cell pixel size?)"
fi
echo "image 1 was placed as a 32x32 rectangle"

# ── 검사 16: 렌더러가 사분면을 정확히 칠했는가 ─────────────────────────
#
# 사분면 중심 픽셀을 프레임버퍼에서 되읽은 값이다. 최근접 이웃이라 배율 16에서
# 경계가 정확히 떨어진다(image_test 검사 1이 호스트에서 같은 것을 본다).
if ! grep -aq 'terminal: imgpx> id=1 tl=FF0000 tr=00FF00 bl=0000FF br=FFFFFF' "$LOG"; then
  grep -a 'terminal: imgpx> id=1' "$LOG" | tail -n 5
  report_failure "image 1 did not reach the framebuffer as red/green/blue/white quadrants"
fi
echo "image 1 reached the framebuffer: red, green, blue, white"

# ── 검사 17: 알파 합성 ──────────────────────────────────────────────────
#
# 889098은 (s·a + d·(255−a) + 127)/255를 채널마다 미리 셈한 값이다.
if ! grep -aq 'terminal: imgpx> id=2 tl=889098 tr=889098 bl=889098 br=889098' "$LOG"; then
  grep -a 'terminal: imgpx> id=2' "$LOG" | tail -n 5
  report_failure "image 2 was not alpha-blended to 889098 over the background"
fi
echo "image 2 was alpha-blended to 889098"

# ── 검사 18: 명령이 글자로 새어 나오지 않았다 ──────────────────────────
#
# 화면에는 친 명령 줄이 되울려 찍히므로 "_G가 없다"로는 볼 수 없다
# (project_gate_screen_echo). 대신 페이로드를 센다 — 마지막 화면에서 정확히
# 한 번(되울린 명령 줄)이어야 한다. 파서가 명령을 삼키지 못했다면 출력으로
# 한 번 더 찍혀 둘이 된다.
LAST_SCREEN="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"
PAYLOAD_SEEN="$(grep -o -- "$IMG1_PAYLOAD" <<<"$LAST_SCREEN" | wc -l)"
if [ "$PAYLOAD_SEEN" -ne 1 ]; then
  echo "$LAST_SCREEN"
  report_failure "the image payload appears ${PAYLOAD_SEEN} time(s) on screen (1 expected: the echoed command)"
fi
echo "the image command did not leak onto the screen as text"

# ── 음성 검사 ──────────────────────────────────────────────────────────

# 화면 덤프에 NUL이 섞이면 안 된다. 빈 셀이 결과에 들어오기 시작했으므로
# (design 결정 3) dumpScreen이 그것을 안 거르면 utf8Encode(0)이 NUL을 만든다.
#
# `grep -qP '\x00'`을 쓰지 않는다. GNU grep 3.11에서 그것은 NUL이 든 파일에도
# 매치되지 않는다 — 그대로 뒀으면 항상 통과하는 가짜 검사가 된다
# (plan을 쓰면서 컨테이너에서 확인했다). 바이트 수를 세는 쪽은 확실하다.
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "a NUL byte leaked into the log (dumpScreen did not skip empty cells)"
fi
echo "no NUL bytes in the log"

# 상한에 걸렸다면 게이트가 보는 셀이 잘려나갔을 수 있다. 지금 화면에서
# 16셀을 넘길 일은 없으므로, 넘겼다면 무언가 예상과 다르다. 이미지 구간
# 앞(`IMG_LOG_START`)만 본다 — 이유는 그 변수 자리에 있다.
if grep -aq "terminal: style> .* more cell(s) not shown" <<<"$(head -c "$IMG_LOG_START" "$LOG")"; then
  report_failure "the style dump hit its limit, so the gate may be reading a truncated view"
fi

if grep -aq "Attempted to kill init" "$LOG"; then
  report_failure "init died"
fi

echo "--- style/pixel lines ---"
grep -aE 'terminal: (style|pixel)>' "$LOG" | tail -n 20
echo "--- ink lines ---"
grep -a 'terminal: ink>' "$LOG" | tail -n 10
echo "--- scroll lines ---"
grep -a 'terminal: scroll>' "$LOG" | tail -n 10
echo "TR-M2 PASS: colors reach the framebuffer, Hangul covers both of its cells, the viewport scrolls and comes back, and kitty images reach the framebuffer"
