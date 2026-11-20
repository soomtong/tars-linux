#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# TK 체인 — TARS 툴킷(`toolkit/`, TK design)과 그 시험 앱 `tars-tk-demo`. 서른여섯번째 체인.
#
# 이 게이트가 증명하는 사슬(TK-M0 plan 확정 6의 판정 1~6, TK-M1 plan 확정 10의 판정 7~9 — 7~9는 5와 6 사이에 돈다):
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
#
# 부팅 하나, NIC 없음, 디스크 없음 — 셸은 root(fish), 소켓은 `/run/user/0`. 키보드는 QEMU의 PS/2라 pc로 읽혀 Cmd가 Alt
# 자리다(wayland 체인과 같다). monitor 포트는 45509 — 예약 범위(RP-M0)에서 45508(wayland) 다음이다(TK design 결정 12).
#
# 화면 1280 × 800. 셸 하나 옆에 열린 app column은 x 644..1259 · y 20..771(616 × 752)이다(셸 0..635, 구분선 636..643).
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

echo "=== boot: ${XRES}x${YRES}, no disk (root shell), PS/2 keyboard read as pc (Cmd = alt) ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci,xres=${XRES},yres=${YRES} \
  -display none \
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

# ── render verify ─────────────────────────────────────────────────────
MISMATCH="$(count_log 'terminal: verify> mismatch')"
[ "$MISMATCH" -eq 0 ] || report_failure "render verify mismatch lines: ${MISMATCH}"

echo "PASS: TK-M1 — tars-tk-demo binds tars_menu_v1 (native), opens as a 616x752 column, draws a rounded rectangle (z2d) with antialiased corners and antialiased Pretendard text, redraws centred at 1240x752 on Cmd+R, animates a face's opacity (mid colour between, end colour after) with only the face's rectangle blitted, commits only when it draws (2 + ${N} draws and commits, none while idle), and ends by itself on Cmd+Q"
