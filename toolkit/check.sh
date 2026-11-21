#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# TK 체인 — TARS 툴킷(`toolkit/`, TK design)과 그 시험 앱 `tars-tk-demo`. 서른여섯번째 체인.
#
# 이 게이트가 증명하는 사슬(TK-M0 plan 확정 6의 판정 1~6, TK-M1 plan 확정 10의 판정 7~9 — 7~9는 5와 6 사이에 돈다, TK-M2 plan 확정 15의
# 판정 10~14 — 9 뒤 같은 부팅에서 둘째 데모 `--list 100000`, TK-M3 plan 확정 15의 판정 15~18 — 14 뒤 같은 부팅에서 `tars-files`):
#   셸에서 띄운 tars-tk-demo가 tars_menu_manager_v1을 bind하고(원래 모드) 셸 오른쪽 column이 되어 pane 크기(616 × 752)의
#   configure를 받는다
#   → 그 크기로 버퍼를 만들어 바탕 · 둥근 사각형(z2d) · 글자(stb_truetype, Pretendard 13 · 14 px)를 그린다 — screendump의
#     좌표 색: 사각형 안은 TK_ACCENT, 둥근 모서리 바깥은 TK_BG, 모서리 대각선에 안티에일리어스 중간값
#   → "안녕" 상자 안에 글자 픽셀이 있고 그중 중간값이 있다(안티에일리어스 글자). 결정 4의 사람 판정용 1배 PNG를 로그 폴더에
#   → Cmd+R(폭 preset)의 새 configure(1240 × 752)에 다시 그려 사각형이 새 폭의 가운데로 옮겨 간다
#   → 바뀐 것이 없으면 commit하지 않는다 — idle 동안 서버의 commit 줄이 늘지 않는다
#   → space가 면의 불투명도를 0 → 1로 3초 동안(linear) 옮긴다: 도중의 screendump에서 면의 색이 바탕과 끝 색 사이, 끝난 뒤 끝 색(7)
#   → 그 프레임마다 서버는 면의 사각형만 옮긴다 — `wl> blit`의 부분 줄이 다 면의 64 × 32(8)
#   → Cmd+Q가 close를 보내 데모가 스스로 끝나고 셸이 전체 폭을 되찾는다(6)
#   → 데모 로그: 그린 수 = commit 수 = 2 + 애니메이션 프레임 수 — 애니메이션이 끝난 뒤 2초 동안 그림도 commit도 없었다(9)
#   → 둘째 데모(리스트 둘): `↓` 열 번 뒤 list1의 행 10이 강조(TK_SELECTION), 행 0 · 9 · 11은 바탕, 부분 blit은 통째가 아니다(10)
#   → `End`: 10만 행의 맨 아래 행이 강조, 막대가 바닥(11)
#   → `Home` 뒤 행 4를 클릭하면 그 행이 강조, 휠 아래 한 칸이 axis v=10 → 오프셋 72(12)
#   → `Tab`이 list2로 포커스를 옮겨 list1의 강조가 흐린 색(TK_SELECTION_INACTIVE), list2의 행 0이 강조, `↓`가 list2를 움직이고
#     `Shift+Tab`이 돌아온다(13)
#   → `sendkey down 1000`(1초 누름)에 클라이언트 반복이 3번 이상 나고 선택이 그만큼 내려간다(14)
#   → 둘째 데모 로그: `tk> list` · `hit` · `scroll` · `focus` 줄이 위 판정과 맞고, 그린 수 = commit 수
#   → 셋째 앱 `tars-files /tmp/tkf`(TK-M3 plan 확정 15): 첫 열이 a/ z/ m.txt(디렉터리 먼저, 숨김 .h 없음), 디렉터리에 `›`, 열 · 분할
#     구분선과 미리보기 판(15)
#   → `→ → ←`: 열 셋, 포커스는 둘째 열(TK_SELECTION), 셋째 열의 선택은 흐린 색, 가로 스크롤 한 열(16 — design의 끝나는 조건)
#   → 셸에서 `mkdir /tmp/tkf/a/0` 뒤 돌아오면 다시 읽고 선택 b가 행 1로 따라간다, 셋째 열은 남는다(17)
#   → `touch (seq 1 N)`의 큰 디렉터리가 조각 여럿으로 들어오고 끝나기 전에 항목이 그려진다(18)
#   → tars-files 로그: `files` · `load` · `column` · `columns` · `focus` · `refresh` 줄이 위와 맞고, 그린 수 = commit 수
#
# 부팅 하나, NIC 없음, 디스크 없음 — 셸은 root(fish), 소켓은 `/run/user/0`. 키보드는 QEMU의 PS/2라 pc로 읽혀 Cmd가 Alt
# 자리다(wayland 체인과 같다). USB 마우스 하나(TK-M2 — 판정 12의 클릭 · 휠). HMP `mouse_move` · `mouse_button`이 그 장치로 가고 포인터는
# 화면 가운데(640, 400 — 셸과 column 사이 구분선)에서 시작한다. 첫 움직임 전에는 화살표를 안 그리므로 판정 1~9의 덤프는 마우스가 없던 때와 같다. monitor 포트는 45509 — 예약 범위(RP-M0)에서 45508(wayland) 다음이다(TK design 결정 12).
#
# 화면 1280 × 800. 셸 하나 옆에 열린 app column은 x 644..1259 · y 20..771(616 × 752)이다(셸 0..635, 구분선 636..643).
# 둘째 데모(리스트 화면, 같은 616 × 752 column): list1 x 644..1059 · list2 x 1060..1259, 행 i는 y 20 + 24 × i − 오프셋부터 24줄, 레이블은 행 왼쪽
# 16부터(list1 x 660..), 막대는 리스트마다 오른쪽 6 px(list1 x 1054..1059). 판정 상자는 레이블과 막대를 피해 list1은 x 900..1039, list2는
# x 1190..1249다. 클릭은 (700, 128)이라 화살표(그 자리에서 오른쪽 아래)가 상자에 안 걸린다.
# 데모의 자리는 `toolkit/src/demo.zig` 머리의 논리 픽셀이다 — 사각형은 폭 320 · 높이 96 · 위 24 · 가운데 정렬이라 616 폭에서
# 화면 x 792..1111 · y 44..139, 1240 폭(x 20부터)에서 x 480..799다. "안녕"은 사각형 가운데(952, 92) 언저리다. 면(64 × 32, 세로 스택의
# 셋째 — 데모 머리 주석)은 1240 폭에서 x 20 + 588 = 608..671 · y 20 + 308 = 328..359, 가운데 (640, 344)다.
#
# `tk>` 줄은 데모가 끝난 뒤 셸에서 `cat /tmp/tk.log > /dev/console`로 시리얼에 꺼낸다(TK-M1 plan 확정 10). 데모가 떠 있는 동안 친
# 글자는 포커스를 쥔 데모로 가고, 체인의 `type_text`는 대문자를 못 쳐 `/dev/ttyS0`이 안 된다(TK-M1 단계 A 보고).
#
# 툴킷은 logline을 쓰지 않는다 — `tk>` 줄은 데모의 표준 출력(`/tmp/tk.log`)이고 시리얼에 안 간다. 그래서 루트 check.sh의
# `LOGLINE_DIRS`(게스트 코드의 std.debug.print 금지)에 toolkit/src를 넣지 않았다. 데모의 `say`는 bufPrint 뒤 write 하나라
# 그 규칙이 막으려던 64바이트 쪼개기가 없다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# prepare.sh가 끝에서 toolkit의 `zig build`를 부른다(TK design 결정 1).
if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 둥근 사각형 · 글자 상자의 픽셀 표(tk_test — 메모리 판)는 여기서 먼저 걸러진다.
if ! (cd ../toolkit && zig build test); then
  echo "FAIL: toolkit host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45509
REPO_ROOT="$(cd .. && pwd)"
XRES=1280
YRES=800

# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로 넘긴다.
SCREENS_DIR="${REPO_ROOT}/out/tk"
mkdir -p "$SCREENS_DIR"
# 결정 4의 사람 판정용 PNG는 이 회차의 로그 폴더에 남는다(make check · 루트 게이트가 TMPDIR을 그 폴더로 준다).
JUDGE_DIR="${TMPDIR:-/tmp}"

# 테마의 앱 색(shared/theme.zig — TK_BG · TK_ACCENT · TK_TEXT). 소문자 hex는 ppm_ink의 출력 모양이다.
TK_BG=202c3c
TK_ACCENT=3c78d8
TK_TEXT=f4f6f8
# 둘째 데모의 색 — 흐린 선택(TK_SELECTION_INACTIVE) · 막대(TK_TEXT_DIM).
TK_INACTIVE=465a78
TK_DIM=98a4b4
# 셋째 앱(tars-files)의 색 — 구분선(TK_SEPARATOR) · 미리보기 판(TK_SURFACE).
TK_SEP=34425a
TK_SURF=2a3850
# 판정 18의 큰 디렉터리 항목 수(TK-M3 — 게스트에서 `touch (seq 1 N)`이 체인 시간을 크게 늘리지 않는 수).
FILES_N=10000
# 면 애니메이션의 길이(ms) — 도중의 screendump가 TCG의 지연에도 끝 색에 닿지 않을 만큼 길게, linear로(TK-M1 plan 확정 9).
ANIM_MS=3000

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

source ../gate_lib.sh

report_failure() {
  echo "FAIL: $1"
  echo "--- wl> and pane> lines ---"
  tlog | grep -aE 'terminal: (wl|pane)> ' | tr -d '\r' | tail -n 40
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 15초.
wait_for_log() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if tlog | grep -aE -- "$pattern" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

count_log() {
  tlog | grep -acE -- "$1"
}

# 글자열을 sendkey 이름으로 친다(wayland 체인과 같은 표).
type_text() {
  local text="$1" i ch keys=()
  for (( i = 0; i < ${#text}; i++ )); do
    ch="${text:i:1}"
    case "$ch" in
      ' ') keys+=(spc) ;;
      -) keys+=(minus) ;;
      /) keys+=(slash) ;;
      .) keys+=(dot) ;;
      '>') keys+=(shift-dot) ;;
      '&') keys+=(shift-7) ;;
      '(') keys+=(shift-9) ;;
      ')') keys+=(shift-0) ;;
      *) keys+=("$ch") ;;
    esac
  done
  type_keys "${keys[@]}"
}

# 셈이 N이 될 때까지 기다린다. 15초.
wait_for_count() {
  local pattern="$1" want="$2" i n
  for i in $(seq 1 150); do
    n="$(count_log "$pattern")"
    if [ "$n" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# HMP 한 줄(마우스 · 누름 시간을 준 sendkey).
hmp() {
  echo "$1" >&3
  sleep 0.05
}

last_at() {
  tlog | grep -a 'terminal: pointer> at ' | tail -n 1 | tr -d '\r' | from_terminal
}

wait_for_at() {
  local pattern="$1" i line
  for i in $(seq 1 150); do
    line="$(last_at)"
    if grep -aE -- "$pattern" <<<"$line" > /dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 포인터를 (X, Y)로 — wayland 체인의 move_to와 같다. 첫 움직임 전에는 at 줄이 없으므로 가운데(640, 400)에서 시작한다.
move_to() {
  local tx="$1" ty="$2" line cx=640 cy=400 dx dy sx sy
  line="$(last_at)"
  if [ -n "$line" ]; then
    cx="$(sed -E 's/.* x=([0-9]+) .*/\1/' <<<"$line")"
    cy="$(sed -E 's/.* y=([0-9]+) .*/\1/' <<<"$line")"
  fi
  dx=$((tx - cx))
  dy=$((ty - cy))
  while [ "$dx" -ne 0 ] || [ "$dy" -ne 0 ]; do
    sx=$dx; [ "$sx" -gt 100 ] && sx=100; [ "$sx" -lt -100 ] && sx=-100
    sy=$dy; [ "$sy" -gt 100 ] && sy=100; [ "$sy" -lt -100 ] && sy=-100
    hmp "mouse_move $sx $sy"
    dx=$((dx - sx))
    dy=$((dy - sy))
  done
  wait_for_at "^terminal: pointer> at x=${tx} y=${ty} "
}

# 상자 하나가 한 색인가(`bg=색 ink=0`). 이름 · 덤프 · 상자 · 색.
want_box() {
  local what="$1" shot="$2" x="$3" y="$4" w="$5" h="$6" colour="$7" got
  got="$(ppm_ink "$shot" "$x" "$y" "$w" "$h")"
  [ "$got" = "bg=${colour} ink=0" ] || report_failure "${what}: (${x},${y} ${w}x${h}) is not ${colour} (${got})"
}

# 픽셀 하나의 색(RRGGBB, 소문자).
ppm_px() {
  local got
  got="$(ppm_ink "$1" "$2" "$3" 1 1)"
  got="${got#bg=}"
  echo "${got%% *}"
}

# 상자 안에서 두 색 어느 것도 아닌 픽셀의 수 — 안티에일리어스의 중간값.
ppm_other() {
  perl -e '
    my ($f, $x0, $y0, $w, $h, $a, $b) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3; my $n = 0;
    for my $y ($y0 .. $y0 + $h - 1) {
      for my $x ($x0 .. $x0 + $w - 1) {
        my $p = unpack("H6", substr($d, $y * $row + $x * 3, 3));
        $n++ if $p ne $a && $p ne $b;
      }
    }
    print "$n\n";' "$@"
}

echo "=== boot: ${XRES}x${YRES}, no disk (root shell), PS/2 keyboard read as pc (Cmd = alt), a USB mouse ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci,xres=${XRES},yres=${YRES} \
  -display none \
  -usb -device usb-mouse,id=tkmouse \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

ready=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOG" >/dev/null; then ready=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$ready" = "1" ] || report_failure "terminal never rendered a prompt"
wait_for_screen 'root@tars ~#' || report_failure "the shell prompt never showed up"
sleep 1

connected=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
  sleep 0.5
done
[ "$connected" = "1" ] || report_failure "could not connect to the QEMU monitor on port ${MONITOR_PORT}"

tlog | grep -a 'terminal: keyboard> open .* kind=pc' >/dev/null ||
  report_failure "the PS/2 keyboard was not read as pc — this chain's Cmd (alt) would be wrong"

# ── 판정 1: 원래 모드 · column · pane 크기의 configure ─────────────────────
echo "=== (1) tars-tk-demo binds tars_menu_manager_v1 and opens as a column right of the shell ==="
type_text "tars-tk-demo --anim-ms ${ANIM_MS} --easing linear > /tmp/tk.log &"
type_keys ret
wait_for_log 'terminal: wl> keys pid=[0-9]+ native' ||
  report_failure "(1) the demo did not bind tars_menu_manager_v1 (no 'wl> keys pid=N native')"
wait_for_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1' || report_failure "(1) no 'wl> column id=… slot=1 ws=1'"
ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
wait_for_log "terminal: wl> configure id=${ID} w=616 h=752 act=1" ||
  report_failure "(1) no 'wl> configure id=${ID} w=616 h=752 act=1' (the right half, focused)"
wait_for_log "terminal: wl> commit id=${ID} buf=616x752 " ||
  report_failure "(1) the demo never committed a 616x752 buffer"
echo "(1): native mode, column id=${ID}, 616x752, a 616x752 buffer committed"

# ── 판정 2: 둥근 사각형의 좌표 색 ─────────────────────────────────────────
echo "=== (2) the rounded rectangle: inside, outside the corner, the antialiased diagonal ==="
sleep 1
SHOT2="${SCREENS_DIR}/demo-616.ppm"
screendump "$SHOT2" || report_failure "(2) screendump did not write ${SHOT2}"
# 사각형 안 — "안녕"(가운데)을 피해 왼쪽 아래.
got="$(ppm_ink "$SHOT2" 810 100 16 16)"
[ "$got" = "bg=${TK_ACCENT} ink=0" ] || report_failure "(2) inside the rectangle (810,100) is not TK_ACCENT (${got})"
# 창 바탕 — 사각형 아래, 표본 글자보다 아래.
got="$(ppm_ink "$SHOT2" 700 500 32 32)"
[ "$got" = "bg=${TK_BG} ink=0" ] || report_failure "(2) the window background (700,500) is not TK_BG (${got})"
# 둥근 모서리: 사각형의 왼쪽 위 꼭짓점 (792,44)은 바깥(바탕)이고, 대각선 (792+k, 44+k)에 중간값이 있다.
got="$(ppm_px "$SHOT2" 792 44)"
[ "$got" = "$TK_BG" ] || report_failure "(2) the corner point (792,44) is not TK_BG (${got}) — the corner is not rounded"
mid=0
for k in $(seq 0 11); do
  got="$(ppm_px "$SHOT2" $((792 + k)) $((44 + k)))"
  if [ "$got" != "$TK_BG" ] && [ "$got" != "$TK_ACCENT" ]; then mid=$((mid + 1)); fi
done
[ "$mid" -ge 1 ] || report_failure "(2) no antialiased pixel on the corner diagonal (792..803, 44..55)"
echo "(2): ${TK_ACCENT} inside, ${TK_BG} outside the corner, ${mid} antialiased pixel(s) on the diagonal"

# ── 판정 3: "안녕"의 글자 픽셀 · 결정 4의 PNG ──────────────────────────────
echo "=== (3) the glyphs of 안녕 are inked and antialiased ==="
got="$(ppm_ink "$SHOT2" 932 80 40 24)"
case "$got" in
  "bg=${TK_ACCENT} ink=0") report_failure "(3) no ink in the 안녕 box (932,80 40x24)" ;;
  "bg=${TK_ACCENT} ink="*) ;;
  *) report_failure "(3) the 안녕 box is not on TK_ACCENT (${got})" ;;
esac
other="$(ppm_other "$SHOT2" 932 80 40 24 "$TK_ACCENT" "$TK_TEXT")"
[ "$other" -gt 0 ] || report_failure "(3) the 안녕 glyphs have no antialiased pixel (only ${TK_ACCENT} and ${TK_TEXT})"
# 결정 4의 사람 판정용 — 창 위쪽(사각형과 13 · 14 px 표본 여덟 줄)을 1배로.
convert "$SHOT2" -crop 616x320+644+20 +repage "${JUDGE_DIR}/tk-text-1x.png" ||
  report_failure "(3) could not write ${JUDGE_DIR}/tk-text-1x.png"
echo "(3): 안녕 is inked (${got}), ${other} antialiased pixel(s); the 1x sample is ${JUDGE_DIR}/tk-text-1x.png"

# ── 판정 4: Cmd+R → 새 configure → 다시 그림 ─────────────────────────────
echo "=== (4) Cmd+R widens the column; the demo redraws at 1240x752 ==="
type_keys alt-r
wait_for_log "terminal: wl> configure id=${ID} w=1240 h=752 act=1" ||
  report_failure "(4) Cmd+R sent no 'wl> configure id=${ID} w=1240 h=752 act=1'"
wait_for_log "terminal: wl> commit id=${ID} buf=1240x752 " ||
  report_failure "(4) the demo did not commit a 1240x752 buffer after Cmd+R"
sleep 1
SHOT4="${SCREENS_DIR}/demo-1240.ppm"
screendump "$SHOT4" || report_failure "(4) screendump did not write ${SHOT4}"
got="$(ppm_ink "$SHOT4" 500 100 16 16)"
[ "$got" = "bg=${TK_ACCENT} ink=0" ] || report_failure "(4) the moved rectangle is not at (500,100) (${got})"
got="$(ppm_ink "$SHOT4" 810 100 16 16)"
[ "$got" = "bg=${TK_BG} ink=0" ] || report_failure "(4) the old place (810,100) still shows the rectangle (${got})"
got="$(ppm_px "$SHOT4" 480 44)"
[ "$got" = "$TK_BG" ] || report_failure "(4) the new corner point (480,44) is not TK_BG (${got})"
echo "(4): the rectangle moved to the middle of the 1240 column (x 480..799)"

# ── 판정 5: idle에서 commit 0 ──────────────────────────────────────────
echo "=== (5) nothing changes, nothing is committed ==="
# 서버는 `wl> commit` 줄을 버퍼 크기나 놓는 자리가 바뀔 때만 찍는다(server.zig의 `logCommit`) — 그래서 이 셈은 보조다. 결정적인
# 증거는 판정 6의 데모 로그 셈(commit 수 = draw 수 = 2)이다.
N1="$(count_log "terminal: wl> commit id=${ID} ")"
sleep 2
N2="$(count_log "terminal: wl> commit id=${ID} ")"
[ "$N1" = "$N2" ] || report_failure "(5) the server logged commits while the demo was idle (${N1} -> ${N2})"
echo "(5): the server's commit lines stayed at ${N1} for 2 s"

# ── 판정 7: space → 면의 불투명도 애니메이션, 덤프 둘의 색 ───────────────────────
echo "=== (7) space animates the face's opacity 0 -> 1 over ${ANIM_MS} ms (linear) ==="
FACE_BLIT="terminal: wl> blit id=${ID} x=608 y=328 w=64 h=32 "
type_keys spc
# 애니메이션의 첫 프레임이 서버에 닿은 줄(부분 blit) — 데모 로그는 게스트 /tmp라 지금 못 본다. 1초 더 기다리면 1/3쯤이다.
wait_for_log "$FACE_BLIT" || report_failure "(7) no partial blit of the face (no '${FACE_BLIT}') after space"
sleep 1
SHOT7A="${SCREENS_DIR}/demo-anim-mid.ppm"
screendump "$SHOT7A" || report_failure "(7) screendump did not write ${SHOT7A}"
mid_px="$(ppm_px "$SHOT7A" 640 344)"
# 세 채널이 다 바탕(20 2c 3c)과 끝 색(f4 f6 f8) 사이에 있어야 한다(같으면 안 된다).
between() {
  local p="$1" a="$2" b="$3" k pv av bv
  for k in 0 2 4; do
    pv=$((16#${p:k:2})); av=$((16#${a:k:2})); bv=$((16#${b:k:2}))
    [ "$pv" -gt "$av" ] && [ "$pv" -lt "$bv" ] || return 1
  done
}
between "$mid_px" "$TK_BG" "$TK_TEXT" ||
  report_failure "(7) the face's centre (640,344) mid-animation is ${mid_px}, not strictly between ${TK_BG} and ${TK_TEXT}"
sleep "$(( ANIM_MS / 1000 + 2 ))"
SHOT7B="${SCREENS_DIR}/demo-anim-end.ppm"
screendump "$SHOT7B" || report_failure "(7) screendump did not write ${SHOT7B}"
got="$(ppm_ink "$SHOT7B" 612 332 56 24)"
[ "$got" = "bg=${TK_TEXT} ink=0" ] || report_failure "(7) after the animation the face (612,332 56x24) is not ${TK_TEXT} (${got})"
echo "(7): mid-animation ${mid_px} (between ${TK_BG} and ${TK_TEXT}), after ${ANIM_MS} ms the face is ${TK_TEXT}"

# ── 판정 8: 애니메이션 프레임의 서버 blit은 면의 사각형뿐 ────────────────────────
echo "=== (8) every animation frame moved only the face's rectangle on the server ==="
# 이 창의 blit 줄: 통째 둘(616 첫 그림 · 1240 Cmd+R — 서버가 통째 줄을 둘까지만 찍는다)과 부분. 부분 줄은 다 면의 사각형이어야 한다.
BLITS="$(tlog | grep -aE "terminal: wl> blit id=${ID} " | tr -d '\r')"
PARTS="$(printf '%s\n' "$BLITS" | grep -avE ' w=(616|1240) h=752 ' | grep -ac .)"
FACES="$(printf '%s\n' "$BLITS" | grep -acF "$FACE_BLIT")"
[ "$PARTS" -ge 3 ] || report_failure "(8) only ${PARTS} partial blit line(s) for window ${ID}"
[ "$PARTS" = "$FACES" ] || report_failure "(8) ${PARTS} partial blits but only ${FACES} are the face's 64x32 — something else was damaged"
echo "(8): ${FACES} partial blit(s), all x=608 y=328 w=64 h=32 (the server's line cap is 16)"
# 애니메이션이 끝난 뒤의 idle — 판정 9가 데모 로그로 센다. 여기서는 2초를 둔다.
sleep 2

# ── 판정 6: Cmd+Q → 데모가 끝나고 셸이 전체 폭 ─────────────────────────────
echo "=== (6) Cmd+Q closes the demo and the shell takes the whole width ==="
# 셸 하나의 pane 줄은 부팅 때도 찍혔다 — "있는가"가 아니라 "늘었는가"를 본다.
WHOLE='terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 '
W1="$(count_log "$WHOLE")"
type_keys alt-q
wait_for_log "terminal: wl> close id=${ID}" || report_failure "(6) Cmd+Q sent no 'wl> close id=${ID}'"
wait_for_log "terminal: wl> unmap id=${ID} ws=1 slot=1" || report_failure "(6) the slot was not removed"
whole=0
for _ in $(seq 1 150); do
  W2="$(count_log "$WHOLE")"
  if [ "$W2" -gt "$W1" ]; then whole=1; break; fi
  sleep 0.1
done
[ "$whole" = 1 ] || report_failure "(6) the shell did not take the whole width back (no new '${WHOLE}')"
sleep 2.5
KILLS="$(count_log 'terminal: wl> kill ')"
[ "$KILLS" -eq 0 ] || report_failure "(6) the demo was killed (wl> kill lines ${KILLS}) — it should end by itself on close"
echo "(6): Cmd+Q ended the demo by itself and the shell has the whole width"

# ── 판정 9: 데모 로그 — 그린 수 = commit 수 = 2 + 애니메이션 프레임 ──────────────
echo "=== (9) the demo's log: draws = commits = 2 + animation frames (nothing while idle) ==="
# 데모의 줄을 시리얼로 꺼낸다(측정 · N). 셸에 /dev/console을 쓰고, 시리얼에서는 줄 머리 `tk> `로 고른다.
type_text 'cat /tmp/tk.log > /dev/console'
type_keys ret
# `tlog`는 terminal의 쪼개진 줄을 잇는 것이라 그 사이에 낀 다른 줄을 옮길 수 있다 — 여기는 원시 시리얼을 본다.
got_end=0
for _ in $(seq 1 150); do
  if tr -d '\r' < "$LOG" | grep -aE '^tk> anim end prop=opacity frames=[0-9]+ ' > /dev/null; then got_end=1; break; fi
  sleep 0.1
done
[ "$got_end" = 1 ] || report_failure "(9) no 'tk> anim end prop=opacity frames=N' line came out on the serial"
TKLINES="$(tr -d '\r' < "$LOG" | grep -a '^tk> ')"
N="$(printf '%s\n' "$TKLINES" | grep -aoE '^tk> anim end prop=opacity frames=[0-9]+' | tail -n 1 | sed 's/.*frames=//')"
printf '%s\n' "$TKLINES" | grep -aE "^tk> anim start prop=opacity dur=${ANIM_MS}\$" > /dev/null ||
  report_failure "(9) no 'tk> anim start prop=opacity dur=${ANIM_MS}' line"
# 셈(화면): commit · draw · native · close · 616 폭 줄(configure · 첫 그림) · 1240 폭 줄(configure · Cmd+R 그림 · 애니메이션 N) · anim end ·
# 데모 로그의 줄 수. 첫 그림 · Cmd+R 그림 둘에 애니메이션의 tick마다 그림 하나(창 층은 그릴 수 있을 때만 tick을 부른다)라 draw = 2 + N이고,
# commit이 draw와 같다는 것이 "바뀐 것이 없으면 commit하지 않는다"의 클라이언트 쪽 증거다 — 판정 2~5와 애니메이션 뒤 2초 동안 데모는 떠 있었다.
D=$(( 2 + N ))
type_text 'echo tk-(grep -c tk..commit /tmp/tk.log)-(grep -c tk..draw /tmp/tk.log)-(grep -c tk..native /tmp/tk.log)-(grep -c tk..close /tmp/tk.log)-(grep -c w.616.h.752 /tmp/tk.log)-(grep -c w.1240.h.752 /tmp/tk.log)-(grep -c anim.end /tmp/tk.log)-(grep -c tk.. /tmp/tk.log)'
type_keys ret
WANT="tk-${D}-${D}-1-1-2-${D}-1-"
wait_for_screen "$WANT" ||
  report_failure "(9) the demo's log is not ${D} commits, ${D} draws (2 + ${N} animation frames), native, close, two 616 lines, ${D} 1240 lines, one anim end"
TOTAL="$(joined_screen_dump | grep -aoE "${WANT}[0-9]+" | tail -n 1 | sed 's/.*-//')"
SERIAL_TK="$(printf '%s\n' "$TKLINES" | grep -ac .)"
echo "(9): ${N} animation frame(s); ${D} draws = ${D} commits; the log's ${TOTAL:-?} lines came out as ${SERIAL_TK} whole 'tk> ' lines on the serial"
# 측정(참고 — 판정 아님, measurements 108): 통째 그림 줄과 애니메이션 줄, 부분 그림 · 부분 blit의 us 요약(최소 · 중앙 · 최대).
us_summary() {
  sed -n 's/.* us=\([0-9]*\).*/\1/p' | sort -n | awk '{a[NR]=$1} END {if (NR) printf "n=%d min=%d median=%d max=%d", NR, a[1], a[int((NR+1)/2)], a[NR]; else printf "n=0"}'
}
echo "--- reference: whole draws and the animation ---"
printf '%s\n' "$TKLINES" | grep -aE '^tk> (draw .* age=0|anim )'
echo "reference: partial draws (age 2, 64x32) $(printf '%s\n' "$TKLINES" | grep -aE '^tk> draw .* age=2$' | us_summary)"
echo "reference: whole blits $(printf '%s\n' "$BLITS" | grep -aE ' w=(616|1240) h=752 ' | sed 's/.*blit id=[0-9]* //' | tr '\n' ' ')"
echo "reference: partial blits (64x32) $(printf '%s\n' "$BLITS" | grep -aF "$FACE_BLIT" | us_summary)"

# ══ 둘째 데모 — 리스트 화면(TK-M2) ══════════════════════════════════════
#
# 판정 9 뒤 셸(전체 폭, 포커스)에서 띄운다. 새 column은 판정 1과 같은 616 × 752 자리다. 데모 로그(`/tmp/tk2.log`)는 끝에 꺼낸다.
echo "=== (10) tars-tk-demo --list 100000: ten downs move list1's highlight to row 10 ==="
type_text 'tars-tk-demo --list 100000 > /tmp/tk2.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' 2 || report_failure "(10) the list demo did not open a second column"
ID2="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
[ "$ID2" != "$ID" ] || report_failure "(10) the list demo's column id is the first demo's (${ID})"
wait_for_log "terminal: wl> configure id=${ID2} w=616 h=752 act=1" || report_failure "(10) no 'wl> configure id=${ID2} w=616 h=752 act=1'"
wait_for_log "terminal: wl> commit id=${ID2} buf=616x752 " || report_failure "(10) the list demo never committed a 616x752 buffer"
sleep 1.5
SHOT10A="${SCREENS_DIR}/list-first.ppm"
screendump "$SHOT10A" || report_failure "(10) screendump did not write ${SHOT10A}"
want_box "(10) list1 row 0 at start" "$SHOT10A" 900 22 140 20 "$TK_ACCENT"
want_box "(10) list2 row 0 at start (not focused)" "$SHOT10A" 1190 22 60 20 "$TK_INACTIVE"
DOWN="terminal: wl> key code=108 state=1 to=${ID2}"
for _ in $(seq 1 10); do type_keys down; done
wait_for_count "$DOWN" 10 || report_failure "(10) the server did not send ten downs ($(count_log "$DOWN"))"
sleep 1
SHOT10="${SCREENS_DIR}/list-down10.ppm"
screendump "$SHOT10" || report_failure "(10) screendump did not write ${SHOT10}"
want_box "(10) list1 row 10 (y 260..283)" "$SHOT10" 900 262 140 20 "$TK_ACCENT"
got="$(ppm_ink "$SHOT10" 660 262 140 20)"
case "$got" in
  "bg=${TK_ACCENT} ink=0") report_failure "(10) row 10's label box (660,262 140x20) has no ink" ;;
  "bg=${TK_ACCENT} ink="*) ;;
  *) report_failure "(10) row 10's label box is not on ${TK_ACCENT} (${got})" ;;
esac
want_box "(10) list1 row 0 after the downs" "$SHOT10" 900 22 140 20 "$TK_BG"
want_box "(10) list1 row 9" "$SHOT10" 900 238 140 20 "$TK_BG"
want_box "(10) list1 row 11" "$SHOT10" 900 286 140 20 "$TK_BG"
# 이 창의 blit 줄: 첫 통째 하나 뒤는 다 부분이어야 한다(스크롤이 없었다 — 강조의 이동만).
BLITS2="$(tlog | grep -aE "terminal: wl> blit id=${ID2} " | tr -d '\r')"
PARTS2="$(printf '%s\n' "$BLITS2" | tail -n +2 | grep -ac .)"
WHOLES2="$(printf '%s\n' "$BLITS2" | tail -n +2 | grep -acE ' w=616 h=752 ')"
[ "$PARTS2" -ge 1 ] && [ "$WHOLES2" -eq 0 ] ||
  report_failure "(10) after the first blit ${PARTS2} blit line(s), ${WHOLES2} of them whole — the downs should blit only parts"
echo "(10): ten downs reached window ${ID2}; row 10 is ${TK_ACCENT} with its label, rows 0 9 11 are ${TK_BG}; ${PARTS2} partial blit(s), none whole"

# ── 판정 11: End → 맨 아래 행 · 막대 ───────────────────────────────────────
echo "=== (11) End selects the last of 100000 rows and the bar sits at the bottom ==="
type_keys end
wait_for_count "terminal: wl> key code=107 state=1 to=${ID2}" 1 || report_failure "(11) End did not reach the window"
sleep 1
SHOT11="${SCREENS_DIR}/list-end.ppm"
screendump "$SHOT11" || report_failure "(11) screendump did not write ${SHOT11}"
want_box "(11) the last row (y 748..771)" "$SHOT11" 900 750 140 20 "$TK_ACCENT"
want_box "(11) the row above the last" "$SHOT11" 900 726 140 20 "$TK_BG"
want_box "(11) the scroll bar at the bottom" "$SHOT11" 1055 756 4 10 "$TK_DIM"
want_box "(11) no scroll bar at the top" "$SHOT11" 1054 22 6 40 "$TK_BG"
echo "(11): the last row is ${TK_ACCENT}, the bar (${TK_DIM}) is at the bottom"

# ── 판정 12: Home → 행 4 클릭 · 휠 ──────────────────────────────────────
echo "=== (12) Home, a click on row 4 selects it, one wheel notch down is axis v=10 ==="
type_keys home
wait_for_count "terminal: wl> key code=102 state=1 to=${ID2}" 1 || report_failure "(12) Home did not reach the window"
tlog | grep -a 'terminal: pointer> open ' > /dev/null || report_failure "(12) terminal did not open the USB mouse"
move_to 700 128 || report_failure "(12) the pointer did not reach 700,128 (last at: $(last_at))"
wait_for_log "terminal: wl> pointer enter id=${ID2}" || report_failure "(12) no 'wl> pointer enter id=${ID2}'"
hmp "mouse_button 1"
wait_for_log "terminal: wl> button id=${ID2} code=272 state=1" || report_failure "(12) the press did not reach the window"
hmp "mouse_button 0"
wait_for_log "terminal: wl> button id=${ID2} code=272 state=0" || report_failure "(12) the release did not reach the window"
sleep 1
SHOT12="${SCREENS_DIR}/list-click.ppm"
screendump "$SHOT12" || report_failure "(12) screendump did not write ${SHOT12}"
want_box "(12) the clicked row 4 (y 116..139)" "$SHOT12" 900 118 140 20 "$TK_ACCENT"
want_box "(12) row 0 after the click" "$SHOT12" 900 22 140 20 "$TK_BG"
hmp "mouse_move 0 0 -1"
wait_for_log "terminal: wl> axis id=${ID2} v=10" || report_failure "(12) one notch down did not reach the window as axis 10"
sleep 1
SHOT12B="${SCREENS_DIR}/list-wheel.ppm"
screendump "$SHOT12B" || report_failure "(12) screendump did not write ${SHOT12B}"
# 오프셋 72(세 행) — 행 4는 y 20 + 96 − 72 = 44..67로 올라왔다.
want_box "(12) row 4 after the wheel (y 44..67)" "$SHOT12B" 900 46 140 20 "$TK_ACCENT"
want_box "(12) the old place of row 4 after the wheel" "$SHOT12B" 900 118 140 20 "$TK_BG"
echo "(12): the click selected row 4, the wheel scrolled three rows (row 4 now at y 44)"

# ── 판정 13: Tab · Shift+Tab ──────────────────────────────────────────
echo "=== (13) Tab moves the focus to list2, Shift+Tab back ==="
type_keys tab
sleep 1
SHOT13="${SCREENS_DIR}/list-tab.ppm"
screendump "$SHOT13" || report_failure "(13) screendump did not write ${SHOT13}"
want_box "(13) list1 row 4 dims after Tab" "$SHOT13" 900 46 140 20 "$TK_INACTIVE"
want_box "(13) list2 row 0 is the focused selection" "$SHOT13" 1190 22 60 20 "$TK_ACCENT"
type_keys down
sleep 1
SHOT13B="${SCREENS_DIR}/list-tab-down.ppm"
screendump "$SHOT13B" || report_failure "(13) screendump did not write ${SHOT13B}"
want_box "(13) list2 row 1 after a down" "$SHOT13B" 1190 46 60 20 "$TK_ACCENT"
want_box "(13) list2 row 0 after a down" "$SHOT13B" 1190 22 60 20 "$TK_BG"
want_box "(13) list1 row 4 stays dim" "$SHOT13B" 900 46 140 20 "$TK_INACTIVE"
type_keys shift-tab
sleep 1
SHOT13C="${SCREENS_DIR}/list-shift-tab.ppm"
screendump "$SHOT13C" || report_failure "(13) screendump did not write ${SHOT13C}"
want_box "(13) list1 row 4 is focused again" "$SHOT13C" 900 46 140 20 "$TK_ACCENT"
want_box "(13) list2 row 1 dims" "$SHOT13C" 1190 46 60 20 "$TK_INACTIVE"
echo "(13): Tab focused list2 (${TK_ACCENT}) and dimmed list1 (${TK_INACTIVE}), down moved list2, Shift+Tab came back"

# ── 판정 14: 키 반복 ─────────────────────────────────────────────────
echo "=== (14) holding down for 1 s repeats on the client ==="
UPS="terminal: wl> key code=108 state=0 to=${ID2}"
U1="$(count_log "$UPS")"
hmp "sendkey down 1000"
wait_for_count "$UPS" $((U1 + 1)) || report_failure "(14) the held down was never released"
sleep 1
echo "(14): the held down was released (the repeat count is read from the demo's log below)"

# ── 둘째 데모를 닫고 로그를 꺼낸다 ─────────────────────────────────────────
type_keys alt-q
wait_for_log "terminal: wl> close id=${ID2}" || report_failure "Cmd+Q sent no 'wl> close id=${ID2}' to the list demo"
wait_for_log "terminal: wl> unmap id=${ID2} ws=1 slot=1" || report_failure "the list demo's slot was not removed"
sleep 2
type_text 'echo tk2begin > /dev/console'
type_keys ret
type_text 'cat /tmp/tk2.log > /dev/console'
type_keys ret
got_rss=0
for _ in $(seq 1 150); do
  if tr -d '\r' < "$LOG" | sed -n '/^tk2begin$/,$p' | grep -aE '^tk> rss vmrss_kb=[0-9]+ ' > /dev/null; then got_rss=1; break; fi
  sleep 0.1
done
[ "$got_rss" = 1 ] || report_failure "the list demo's log did not come out on the serial (no 'tk> rss' after 'tk2begin')"
TK2="$(tr -d '\r' < "$LOG" | sed -n '/^tk2begin$/,$p' | grep -a '^tk> ')"
has() {
  printf '%s\n' "$TK2" | grep -aE -- "$1" > /dev/null || report_failure "$2: no '$1' in the list demo's log"
}
has '^tk> focus view=list1$' "(10)"
has '^tk> list view=list1 sel=10 first=0 offset=0$' "(10)"
has '^tk> list view=list1 sel=99999 first=99968 offset=2399248$' "(11)"
has '^tk> list view=list1 sel=0 first=0 offset=0$' "(12)"
has '^tk> hit x=56 y=108 view=list1$' "(12)"
has '^tk> list view=list1 sel=4 first=0 offset=0$' "(12)"
has '^tk> scroll view=list1 offset=72 by=wheel$' "(12)"
has '^tk> focus view=list2$' "(13)"
has '^tk> list view=list2 sel=1 first=0 offset=0$' "(13)"
REPEATS="$(printf '%s\n' "$TK2" | grep -acE '^tk> key code=108 state=1 repeat=1$')"
[ "$REPEATS" -ge 3 ] || report_failure "(14) only ${REPEATS} repeat(s) while down was held for 1 s"
LAST1="$(printf '%s\n' "$TK2" | grep -aE '^tk> list view=list1 ' | tail -n 1)"
[ "$LAST1" = "tk> list view=list1 sel=$((5 + REPEATS)) first=3 offset=72" ] ||
  report_failure "(14) after 1 press + ${REPEATS} repeats from row 4 list1 should be at row $((5 + REPEATS)) (last line: ${LAST1})"
DRAWS2="$(printf '%s\n' "$TK2" | grep -acE '^tk> draw ')"
COMMITS2="$(printf '%s\n' "$TK2" | grep -acE '^tk> commit$')"
[ "$DRAWS2" -eq "$COMMITS2" ] || report_failure "the list demo drew ${DRAWS2} times but committed ${COMMITS2}"
echo "(14): ${REPEATS} client repeat(s) in 1 s, list1 went from row 4 to row $((5 + REPEATS))"
echo "(10-14 log): focus · list · hit · scroll lines match; ${DRAWS2} draws = ${COMMITS2} commits"
# 측정(참고 — 판정 아님, measurements 109).
echo "--- reference: the list demo ---"
printf '%s\n' "$TK2" | grep -aE '^tk> (draw .* age=0|rss )'
echo "reference: whole-list draws (416x752, scroll) $(printf '%s\n' "$TK2" | grep -aE '^tk> draw .* dirty=0,0,416,752 ' | us_summary)"
echo "reference: partial draws (h <= 48, highlight) $(printf '%s\n' "$TK2" | grep -aE '^tk> draw .* dirty=[0-9]+,[0-9]+,[0-9]+,([1-9]|[1-3][0-9]|4[0-8]) ' | us_summary)"
echo "reference: draws while down was held $(printf '%s\n' "$TK2" | awk '/repeat=1$/ {if (!s) s=NR; e=NR} {l[NR]=$0} END {n=0; for (i=s; i<=e; i++) if (l[i] ~ /^tk> draw /) n++; print "n=" n " between the first and last repeat"}')"
# 서버는 창마다 blit 줄을 처음 16줄만 찍는다 — 여기 보이는 것은 첫 통째와 `↓`의 강조 이동이다(스크롤 프레임의 blit은 measurements 109).
echo "reference: list demo blits $(printf '%s\n' "$BLITS2" | sed 's/.*blit id=[0-9]* //' | tr '\n' ' ')"

# ══ 셋째 앱 — tars-files(TK-M3) ═══════════════════════════════════════
#
# 판정 14 뒤 셸(전체 폭, 포커스)에서 트리를 만들고 띄운다. 새 column은 판정 1과 같은 616 × 752 자리(x 644..1259 · y 20..771)다.
# 분할 뷰: column view x 644..1058(415) · 구분선 1059 · 미리보기 1060..1259. 열 i는 화면 x 644 + i × 201 − 가로 스크롤부터 폭 200,
# 오른쪽 1 px 구분선. 행 i는 y 20 + 24 × i부터 24줄, 이름은 열 왼쪽 16부터, 디렉터리의 `›`는 열 오른쪽 끝 10 px 앞(열 x 185..190 언저리).
# 판정 상자는 이름(열 x 16..40) · `›` · 판정 12가 남긴 화살표((700, 128)에서 오른쪽 아래)를 피해 열 x 56..156 · 행 y +2..+21이다.
echo "=== (15) tars-files /tmp/tkf: the first column, directories first, hidden names out ==="
type_text 'mkdir -p /tmp/tkf/a/b/c /tmp/tkf/z'
type_keys ret
type_text 'touch /tmp/tkf/m.txt /tmp/tkf/.h /tmp/tkf/a/b/x.txt'
type_keys ret
type_text 'tars-files /tmp/tkf > /tmp/tk3.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' 3 || report_failure "(15) tars-files did not open a third column"
ID3="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
wait_for_log "terminal: wl> configure id=${ID3} w=616 h=752 act=1" || report_failure "(15) no 'wl> configure id=${ID3} w=616 h=752 act=1'"
wait_for_log "terminal: wl> commit id=${ID3} buf=616x752 " || report_failure "(15) tars-files never committed a 616x752 buffer"
sleep 1.5
SHOT15="${SCREENS_DIR}/files-first.ppm"
screendump "$SHOT15" || report_failure "(15) screendump did not write ${SHOT15}"
want_box "(15) col0 row 0 (a) is the focused selection" "$SHOT15" 700 22 100 20 "$TK_ACCENT"
want_box "(15) col0 row 1 (z)" "$SHOT15" 700 46 100 20 "$TK_BG"
want_box "(15) col0 row 2 (m.txt)" "$SHOT15" 700 70 100 20 "$TK_BG"
want_box "(15) col0 row 3 is empty (.h is hidden)" "$SHOT15" 650 94 180 20 "$TK_BG"
for r in 0 1 2; do
  y=$((22 + 24 * r))
  got="$(ppm_ink "$SHOT15" 658 "$y" 34 20)"
  case "$got" in
    *" ink=0") report_failure "(15) col0 row ${r}'s name box (658,${y} 34x20) has no ink (${got})" ;;
  esac
done
got="$(ppm_ink "$SHOT15" 822 46 16 20)"
case "$got" in
  "bg=${TK_BG} ink=0") report_failure "(15) no › on the directory z (822,46 16x20)" ;;
  "bg=${TK_BG} ink="*) ;;
  *) report_failure "(15) the › box of z is not on ${TK_BG} (${got})" ;;
esac
want_box "(15) no › on the file m.txt" "$SHOT15" 822 70 16 20 "$TK_BG"
want_box "(15) the column separator (x 844)" "$SHOT15" 844 100 1 600 "$TK_SEP"
want_box "(15) the split separator (x 1059)" "$SHOT15" 1059 100 1 600 "$TK_SEP"
want_box "(15) the preview pane" "$SHOT15" 1100 400 140 300 "$TK_SURF"
echo "(15): col0 shows a/ z/ m.txt (a selected, .h hidden), a › on the directories, the separators and the preview pane"

echo "=== (16) -> -> <-: three columns, the focus on the second ==="
RIGHTS="terminal: wl> key code=106 state=1 to=${ID3}"
type_keys right
wait_for_count "$RIGHTS" 1 || report_failure "(16) the first right did not reach tars-files"
sleep 1
type_keys right
wait_for_count "$RIGHTS" 2 || report_failure "(16) the second right did not reach tars-files"
sleep 1
type_keys left
wait_for_count "terminal: wl> key code=105 state=1 to=${ID3}" 1 || report_failure "(16) the left did not reach tars-files"
sleep 1.5
SHOT16="${SCREENS_DIR}/files-columns.ppm"
screendump "$SHOT16" || report_failure "(16) screendump did not write ${SHOT16}"
# scroll 201: 둘째 열(a) x 644..843 · 구분선 844 · 셋째 열(b) x 845..1044 · 구분선 1045 · 바탕 1046..1058.
want_box "(16) col1 row 0 (b) is the focused selection" "$SHOT16" 700 22 100 20 "$TK_ACCENT"
want_box "(16) col2 row 0 (c) is the unfocused selection" "$SHOT16" 901 22 100 20 "$TK_INACTIVE"
want_box "(16) col2 row 1 (x.txt)" "$SHOT16" 901 46 100 20 "$TK_BG"
want_box "(16) the separator between col1 and col2 (x 844)" "$SHOT16" 844 100 1 600 "$TK_SEP"
want_box "(16) the separator after col2 (x 1045)" "$SHOT16" 1045 100 1 600 "$TK_SEP"
want_box "(16) the background right of col2" "$SHOT16" 1047 100 10 600 "$TK_BG"
echo "(16): col1 (a) holds the focus (${TK_ACCENT}), col2 (b) keeps its selection dimmed (${TK_INACTIVE}), scrolled one column"

echo "=== (17) a new entry above the selection while away: the selection follows the name ==="
type_keys alt-bracket_left
wait_for_log "terminal: wl> configure id=${ID3} w=616 h=752 act=0" || report_failure "(17) Cmd+[ did not take the focus away from tars-files"
type_text 'mkdir /tmp/tkf/a/0'
type_keys ret
sleep 1
type_keys alt-bracket_right
wait_for_count "terminal: wl> configure id=${ID3} w=616 h=752 act=1" 2 || report_failure "(17) Cmd+] did not give the focus back to tars-files"
sleep 2
SHOT17="${SCREENS_DIR}/files-refresh.ppm"
screendump "$SHOT17" || report_failure "(17) screendump did not write ${SHOT17}"
want_box "(17) col1 row 1 (b, moved down) is the focused selection" "$SHOT17" 700 46 100 20 "$TK_ACCENT"
want_box "(17) col1 row 0 (the new 0)" "$SHOT17" 700 22 100 20 "$TK_BG"
got="$(ppm_ink "$SHOT17" 658 22 34 20)"
case "$got" in *" ink=0") report_failure "(17) col1 row 0's name box has no ink — the new entry is not drawn (${got})" ;; esac
want_box "(17) col2 (b) stays with its selection" "$SHOT17" 901 22 100 20 "$TK_INACTIVE"
echo "(17): after mkdir a/0 the column re-read on focus, b moved to row 1 and stayed selected, col2 stayed"

type_keys alt-q
wait_for_log "terminal: wl> close id=${ID3}" || report_failure "Cmd+Q sent no 'wl> close id=${ID3}' to tars-files"
wait_for_log "terminal: wl> unmap id=${ID3} ws=1 slot=1" || report_failure "tars-files' slot was not removed"
sleep 1

echo "=== (18) a ${FILES_N}-entry directory streams in ==="
type_text 'mkdir /tmp/tkb'
type_keys ret
type_text 'cd /tmp/tkb'
type_keys ret
type_text "touch (seq 1 ${FILES_N})"
type_keys ret
type_text 'cd'
type_keys ret
type_text 'echo tkb-(count (ls /tmp/tkb))'
type_keys ret
wait_for_screen "tkb-${FILES_N}" || report_failure "(18) the shell did not make ${FILES_N} files in /tmp/tkb"
type_text 'tars-files /tmp/tkb > /tmp/tk4.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' 4 || report_failure "(18) tars-files did not open a fourth column"
ID4="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
wait_for_log "terminal: wl> commit id=${ID4} buf=616x752 " || report_failure "(18) tars-files never committed a 616x752 buffer"
sleep 3
SHOT18="${SCREENS_DIR}/files-big.ppm"
screendump "$SHOT18" || report_failure "(18) screendump did not write ${SHOT18}"
want_box "(18) row 0 (1) is the selection" "$SHOT18" 700 22 100 20 "$TK_ACCENT"
got="$(ppm_ink "$SHOT18" 658 22 34 20)"
case "$got" in *" ink=0") report_failure "(18) row 0's name box has no ink (${got})" ;; esac
type_keys alt-q
wait_for_log "terminal: wl> close id=${ID4}" || report_failure "Cmd+Q sent no 'wl> close id=${ID4}' to tars-files"
wait_for_log "terminal: wl> unmap id=${ID4} ws=1 slot=1" || report_failure "tars-files' second slot was not removed"
sleep 2

# ── tars-files의 로그를 꺼낸다 ───────────────────────────────────────────
type_text 'echo tk3begin > /dev/console'
type_keys ret
type_text 'cat /tmp/tk3.log /tmp/tk4.log > /dev/console'
type_keys ret
got_rss=0
for _ in $(seq 1 150); do
  if [ "$(tr -d '\r' < "$LOG" | sed -n '/^tk3begin$/,$p' | grep -acE '^tk> rss vmrss_kb=[0-9]+ ')" -ge 2 ]; then got_rss=1; break; fi
  sleep 0.1
done
[ "$got_rss" = 1 ] || report_failure "tars-files' logs did not come out on the serial (fewer than two 'tk> rss' after 'tk3begin')"
TK3="$(tr -d '\r' < "$LOG" | sed -n '/^tk3begin$/,$p' | grep -a '^tk> ')"
TK3A="$(printf '%s\n' "$TK3" | awk '/^tk> files path=\/tmp\/tkb$/ {exit} {print}')"
TK3B="$(printf '%s\n' "$TK3" | sed -n '/^tk> files path=\/tmp\/tkb$/,$p')"
has3() {
  printf '%s\n' "$TK3A" | grep -aE -- "$1" > /dev/null || report_failure "$2: no '$1' in tars-files' log"
}
has3 '^tk> files path=/tmp/tkf$' "(15)"
has3 '^tk> load path=/tmp/tkf n=3 chunks=1 .* state=done$' "(15)"
has3 '^tk> column i=0 path=/tmp/tkf count=3 sel=0 name=a$' "(15)"
has3 '^tk> focus view=col0$' "(15)"
has3 '^tk> columns n=2 focus=1 scroll=0$' "(16)"
has3 '^tk> load path=/tmp/tkf/a n=1 chunks=1 .* state=done$' "(16)"
has3 '^tk> columns n=3 focus=2 scroll=201$' "(16)"
has3 '^tk> load path=/tmp/tkf/a/b n=2 chunks=1 .* state=done$' "(16)"
has3 '^tk> columns n=3 focus=1 scroll=201$' "(16)"
has3 '^tk> focus view=col1$' "(16)"
has3 '^tk> refresh path=/tmp/tkf/a name=b before=0 after=1$' "(17)"
has3 '^tk> refresh path=/tmp/tkf name=a before=0 after=0$' "(17)"
has3 '^tk> refresh path=/tmp/tkf/a/b name=c before=0 after=0$' "(17)"
D3="$(printf '%s\n' "$TK3A" | grep -acE '^tk> draw ')"
C3="$(printf '%s\n' "$TK3A" | grep -acE '^tk> commit$')"
[ "$D3" -eq "$C3" ] || report_failure "tars-files drew ${D3} times but committed ${C3}"
LOAD18="$(printf '%s\n' "$TK3B" | grep -aE "^tk> load path=/tmp/tkb n=${FILES_N} chunks=[0-9]+ .* state=done\$" | tail -n 1)"
[ -n "$LOAD18" ] || report_failure "(18) no 'tk> load path=/tmp/tkb n=${FILES_N} … state=done'"
CHUNKS18="$(sed -E 's/.* chunks=([0-9]+) .*/\1/' <<<"$LOAD18")"
FIRST18="$(sed -E 's/.* first_us=([0-9]+) .*/\1/' <<<"$LOAD18")"
PAINT18="$(sed -E 's/.* paint_us=([0-9]+) .*/\1/' <<<"$LOAD18")"
ALL18="$(sed -E 's/.* all_us=([0-9]+) .*/\1/' <<<"$LOAD18")"
[ "$CHUNKS18" -gt 1 ] || report_failure "(18) ${FILES_N} entries came in ${CHUNKS18} chunk(s) — not streamed"
[ "$PAINT18" -gt 0 ] && [ "$PAINT18" -lt "$ALL18" ] ||
  report_failure "(18) no frame showed entries before the load ended (paint_us=${PAINT18} all_us=${ALL18})"
printf '%s\n' "$TK3B" | grep -aE "^tk> column i=0 path=/tmp/tkb count=${FILES_N} sel=0 name=1\$" > /dev/null ||
  report_failure "(18) the first column did not end at count=${FILES_N} with row 0 = 1"
echo "(15-17 log): files · load · column · columns · focus · refresh lines match; ${D3} draws = ${C3} commits"
echo "(18): ${FILES_N} entries in ${CHUNKS18} chunks, first chunk at ${FIRST18} us, first painted at ${PAINT18} us, all at ${ALL18} us"
# 측정(참고 — 판정 아님, measurements 110).
echo "--- reference: tars-files ---"
printf '%s\n' "$TK3" | grep -aE '^tk> (load |rss |columns )'
echo "reference: tars-files draws $(printf '%s\n' "$TK3A" | grep -aE '^tk> draw ' | us_summary)"
printf '%s\n' "$TK3A" | grep -aE '^tk> (draw|columns|refresh) '

# ── render verify ─────────────────────────────────────────────────────
MISMATCH="$(count_log 'terminal: verify> mismatch')"
[ "$MISMATCH" -eq 0 ] || report_failure "render verify mismatch lines: ${MISMATCH}"

echo "PASS: TK-M3 — tars-tk-demo binds tars_menu_v1 (native), opens as a 616x752 column, draws a rounded rectangle (z2d) with antialiased corners and antialiased Pretendard text, redraws centred at 1240x752 on Cmd+R, animates a face's opacity (mid colour between, end colour after) with only the face's rectangle blitted, commits only when it draws (2 + ${N} draws and commits, none while idle), and ends by itself on Cmd+Q; tars-tk-demo --list 100000 moves list1's highlight to row 10 after ten downs, End shows the last row and the bar at the bottom, a click selects row 4 and the wheel scrolls three rows, Tab and Shift+Tab move the focus between the lists, and holding down repeats ${REPEATS} time(s) on the client; tars-files lists /tmp/tkf with directories first and hidden names out, -> -> <- leaves three columns with the focus on the second (scroll 201), re-reads on focus and keeps b selected after a/0 appears, and streams ${FILES_N} entries in ${CHUNKS18} chunks (painted at ${PAINT18} us of ${ALL18} us)"
