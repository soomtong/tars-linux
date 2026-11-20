#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# HS 체인 — HiDPI 배율(HS-M0). 스물여덟번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   QEMU가 virtio-gpu를 2880 × 1800으로 물린다(xres · yres, MacBook Pro Retina 15"의 패널)
#   → terminal이 dumb 버퍼를 그 크기로 잡고, display_scale=auto가 배율 2를 고른다
#     (`kms: scale 2 (2880x1800 -> 1440x900)`)
#   → 격자 · 포인터 · 상태 줄이 논리 1440 × 900으로 정해진다(`terminal: grid 175x53`)
#   → 렌더러는 HS 전처럼 논리 그림자에 그리고, present가 바뀐 사각형만 2배로 늘려
#     dumb 버퍼에 옮긴 뒤 2배 clip으로 DIRTYFB한다
#   → QEMU의 screendump가 2880 × 1800이고 그 픽셀이 전부 2 × 2 블록이다
#   → 키를 친 뒤의 부분 프레임(바뀐 행만)도 물리 화면에 닿는다 — 한글 한 글자의 잉크가
#     terminal이 논리 fb에서 센 수(`ink>`)의 정확히 네 배다
#   → 설정 디스크의 display_scale=1이 auto를 이긴다(부팅 B, 같은 화면에서 `scale 1`과
#     355열), 그리고 `tars-config set display_scale=2` · `reload terminal`이 다시 뜬
#     terminal에서 배율 2를 고른다
#   → (WY-M3) Wayland 창이 배율을 안다. 서버가 `preferred_buffer_scale 2` · `wl_output` 물리
#     mode + scale 2를 알리고, `set_buffer_scale 2`로 2배 버퍼를 보낸 창(tars-wl-test
#     `--buffer-scale 2 --checker`)은 그림자를 거치지 않고 present 단계에서 물리 버퍼에 1:1로
#     놓인다 — 그 사각형이 물리 1픽셀 바둑판이다. 셸의 부분 프레임 · 통째 프레임 · 창 위의
#     화살표가 그 그림을 덮지 않는다. 배율을 안 쓰는 창(`--buffer-scale 1`)은 HS의 늘린 길
#     그대로 2 × 2 블록 바둑판이다. 배율 1(부팅 B)에서는 서버가 1을 알린다
#
# 판정의 도구가 넷이다.
#   kms: · terminal: grid 줄 — 무엇이 골라졌고 격자가 몇 칸인가.
#   screendump — QEMU가 내보낸 물리 화면이다. 논리 fb를 되읽는 덤프(`ink>` · `pixel>`)는
#                늘리기가 빠져도 맞으므로, 늘리기는 여기서만 보인다. perl로 2 × 2 블록이
#                고른지와 상자 하나의 잉크를 센다.
#   ink> 줄 — terminal이 폭 2칸 글자의 칸에서 논리 fb를 되읽어 센 잉크(main.zig의 dumpInk).
#             screendump의 같은 자리 × 2와 견주는 "논리 그림"이다.
#   ppm_checker — (WY-M3) 사각형이 b물리 픽셀 바둑판인지. 왼쪽 위 칸(버퍼 (0, 0), 짝)이 흰색,
#             홀이 창의 색이다(tars-wl-test `--checker`). 1이면 1:1, 2면 늘린 길이다. 블록 검사만으로는
#             "1:1인가"를 못 가른다 — 한 색이나 흐린 그림도 블록이 아닐 수 있다. 창의 사각형은 `pane>`
#             줄(칸)에서 셈한다 — 물리 = 2 × (20 + 칸 × 8 · 16).
#
# 부팅이 둘이다. 부팅 A는 디스크 없이(auto) USB 마우스 하나를 물리고(WY-M3 판정 7c — 움직이기 전에는
# 화살표가 없어 판정 1~3은 그대로다), 부팅 B는 display_scale=1을 적은 설정 디스크를 물린다. monitor 포트는 둘 다 45502다 — 부팅이 차례로 돌고 앞 QEMU를 거둔 뒤에 연다.
# 예약 범위(RP-M0)에서 PS-M0의 45501 다음 빈 자리다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# display_scale의 파싱 · 견본 · tars-config set의 거절(`4` · `1.5`)은 여기서 먼저 걸러진다
# (config_test · config_edit_test · screen_args_test).
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 배율 고르기의 표와 늘리기의 블록은 여기서 먼저 걸러진다(scale_test).
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45502
REPO_ROOT="$(cd .. && pwd)"

# 게이트의 화면. MacBook Pro Retina 15"(MacBookPro11,x)의 네이티브 해상도다.
XRES=2880
YRES=1800

# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로 넘긴다.
# out/은 .gitignore 대상이고 루트 check.sh의 clean()이 지운다.
SCREENS_DIR="${REPO_ROOT}/out/hs"
mkdir -p "$SCREENS_DIR"
BEFORE="${SCREENS_DIR}/before.ppm"
AFTER="${SCREENS_DIR}/after.ppm"
ONE="${SCREENS_DIR}/scale1.ppm"
rm -f "$BEFORE" "$AFTER" "$ONE"

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
  echo "--- kms and grid lines ---"
  tlog | grep -aE '^kms: |terminal: grid |tars-init: config shell=|tars-init: reload terminal' | tr -d '\r'
  echo "--- last ink lines ---"
  tlog | grep -a 'terminal: ink>' | tr -d '\r' | tail -n 5
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 15초(pointer/check.sh와 같다).
wait_for_log() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if tlog | grep -aE -- "$pattern" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# P6 하나의 크기. `WxH`.
ppm_size() {
  perl -e '
    open(my $fh, "<:raw", $ARGV[0]) or die "$ARGV[0]: $!\n";
    read($fh, my $head, 32);
    $head =~ /\AP6\s+(\d+)\s+(\d+)\s/ or die "$ARGV[0]: not a P6 ppm\n";
    print "$1x$2\n";' "$1"
}

# 사각형 [x0, x1) × [y0, y1)을 s × s 블록으로 나눠 고르지 않은 것을 센다. 블록 하나가 아니라
# 어긋남 하나를 센다 — 블록의 첫 행과 다른 행 하나, 블록의 첫 픽셀과 다른 픽셀 하나가 각각 1이다.
# 0이면 그 사각형이 s배로 늘린 그림이다. 사각형의 끝은 s의 배수여야 한다.
ppm_blocks() {
  perl -e '
    my ($f, $s, $x0, $y0, $x1, $y1) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3;
    my $len = ($x1 - $x0) * 3;
    my $bad = 0;
    for (my $y = $y0; $y < $y1; $y += $s) {
      my $base = substr($d, $y * $row + $x0 * 3, $len);
      for my $k (1 .. $s - 1) { $bad++ if substr($d, ($y + $k) * $row + $x0 * 3, $len) ne $base; }
      my @px = unpack("(a3)*", $base);
      for (my $i = 0; $i < @px; $i += $s) {
        for my $k (1 .. $s - 1) { $bad++ if $px[$i + $k] ne $px[$i]; }
      }
    }
    print "$bad\n";' "$@"
}

# 부팅 하나. 첫 인자가 비어 있지 않으면 그 디스크 이미지를 물린다. 나머지 인자는 QEMU에 그대로 간다(USB 마우스).
boot() {
  local disk="${1:-}"
  [ "$#" -gt 0 ] && shift
  local drive=()
  # 콤마는 QEMU -drive 값의 구분자다 — 배열 원소 둘이 아니라 하나다.
  # shellcheck disable=SC2054
  [ -n "$disk" ] && drive=(-drive file="$disk",if=virtio,format=raw)
  LOG="$(mktemp)"
  qemu-system-x86_64 \
    -nic none \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci,xres=${XRES},yres=${YRES} \
    -display none \
    "${drive[@]}" \
    "$@" \
    -serial file:"$LOG" \
    -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
    -no-reboot &
  QEMU_PID=$!

  local ready=0
  for _ in $(seq 1 120); do
    if grep -a "terminal: screen>" "$LOG" >/dev/null; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  [ "$ready" = "1" ] || report_failure "terminal never rendered a prompt"
  wait_for_screen 'root@tars ~#' ||
    report_failure "the shell prompt never showed up"
  # 첫 프레임의 present가 끝나도록 한 박자 준다(terminal/check.sh와 같다).
  sleep 1

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  [ "$connected" = "1" ] || report_failure "could not connect to the QEMU monitor on port ${MONITOR_PORT}"
}

stop_boot() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
}

# ── WY-M3의 도구 ─────────────────────────────────────────────────────

# 글자열을 sendkey 이름으로 친다(wayland 체인과 같다 — 소문자 · 대문자 · 숫자 · 공백 · `-` · `/` · `.` · `>` · `&`만).
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
      [A-Z]) keys+=("shift-${ch,,}") ;;
      *) keys+=("$ch") ;;
    esac
  done
  type_keys "${keys[@]}"
}

# 사각형 [x0, x1) × [y0, y1)이 b물리 픽셀 바둑판인가 — 바둑판과 다른 픽셀 수. 왼쪽 위 칸(짝)은 흰색, 홀은 `color`(RRGGBB)다.
# 한 색 화면이면 반이 어긋난다.
ppm_checker() {
  perl -e '
    my ($f, $b, $color, $x0, $y0, $x1, $y1) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3;
    my @want = (pack("H6", "ffffff"), pack("H6", $color));
    my $bad = 0;
    for my $y ($y0 .. $y1 - 1) {
      my $line = substr($d, $y * $row, $row);
      my $py = int(($y - $y0) / $b);
      for my $x ($x0 .. $x1 - 1) {
        $bad++ if substr($line, $x * 3, 3) ne $want[(int(($x - $x0) / $b) + $py) & 1];
      }
    }
    print "$bad\n";' "$@"
}

# 상자 하나에서 화살표 색(POINTER_FILL fcfcf4 · POINTER_EDGE 040810) 픽셀 수.
ppm_arrow() {
  perl -e '
    my ($f, $x0, $y0, $w, $h) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3; my $n = 0;
    for my $y ($y0 .. $y0 + $h - 1) { for my $x ($x0 .. $x0 + $w - 1) {
      my $p = unpack("H6", substr($d, $y * $row + $x * 3, 3)); $n++ if $p eq "fcfcf4" or $p eq "040810"; } }
    print "$n\n";' "$@"
}

# 창 `id`의 마지막 `pane>` 사각형(칸)을 물리 픽셀 `X0 Y0 X1 Y1`로. 논리 = 20 + 칸 × 8 · 16, 물리 = × 2.
app_rect() {
  local line c r w h
  line="$(tlog | grep -aoE "terminal: pane> [^|]*app id=$1 rect=[0-9]+,[0-9]+ [0-9]+x[0-9]+" | tail -n 1)"
  [ -n "$line" ] || return 1
  read -r c r w h < <(sed -E 's/.*rect=([0-9]+),([0-9]+) ([0-9]+)x([0-9]+)$/\1 \2 \3 \4/' <<<"$line")
  echo "$(( 2 * (20 + c * 8) )) $(( 2 * (20 + r * 16) )) $(( 2 * (20 + (c + w) * 8) )) $(( 2 * (20 + (r + h) * 16) ))"
}

# 패턴(ERE)이 로그에 `want`번 이상 나올 때까지 15초.
wait_for_count() {
  local pattern="$1" want="$2" i n
  for i in $(seq 1 150); do
    # 셈을 먼저 변수로 받는다 — 같은 줄의 `-ge`를 루트 check.sh의 조기 종료 grep 검사가 `-q`로 읽지 않게(wayland 체인과 같다).
    n="$(tlog | grep -acE -- "$pattern")"
    if [ "$n" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

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
    if grep -aqE -- "$pattern" <<<"$line"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 포인터를 논리 (X, Y)로 — wayland 체인의 move_to와 같다. 첫 움직임 전에는 at 줄이 없으므로 논리 화면 가운데(720, 450)에서 시작한다.
move_to() {
  local tx="$1" ty="$2" line cx=720 cy=450 dx dy sx sy
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

# 창의 색(tars-wl-test `--color`). 바둑판의 홀 칸이다.
WL_COLOR=3366cc

# ══ 부팅 A — 디스크 없음, display_scale=auto ════════════════════════════
echo "=== boot A: ${XRES}x${YRES}, display_scale=auto, a USB mouse ==="
boot "" -usb -device usb-mouse,id=hsmouse

# ── 판정 1: auto가 배율 2를 골랐고 격자가 논리 1440 × 900의 것이다 ─────────
#
# 커넥터의 모드가 먼저다 — QEMU가 xres · yres를 안 받았으면 1280 × 800이고, 그때 scale 1은
# 맞는 답이지만 이 체인이 보려는 것이 아니다. 격자는 (1440 - 2 × 20) / 8 = 175열,
# (900 - 2 × 20) / 16 = 53행이다(GRID_X · GRID_Y · CELL_W · ROW_HEIGHT는 HS 전과 같다).
echo "=== boot A (1): auto picks scale 2 and the grid is 1440x900's ==="
tlog | grep -aE "^kms: connector [0-9]+ connected, mode ${XRES}x${YRES}" >/dev/null ||
  report_failure "boot A: the connector did not come up at ${XRES}x${YRES}"
tlog | grep -a 'kms: scale 2 (2880x1800 -> 1440x900)' >/dev/null ||
  report_failure "boot A: no 'kms: scale 2 (2880x1800 -> 1440x900)'"
tlog | grep -a 'terminal: grid 175x53 (fb 1440x900)' >/dev/null ||
  report_failure "boot A: no 'terminal: grid 175x53 (fb 1440x900)'"
tlog | grep -aE 'tars-init: config shell=.* display_scale=auto' >/dev/null ||
  report_failure "boot A: the tars-init: config line does not carry display_scale=auto"

# ── 판정 2: 물리 화면이 2880 × 1800이고 전부 2 × 2 블록이며 글자가 있다 ──────
#
# 블록은 화면 전체를 본다 — 첫 프레임은 clip 없는 present(통째)라 늘리기가 화면 전체를 옮긴
# 것이다. 늘리기가 빠지면 화면이 검고 블록은 고르다(0) — 그래서 잉크를 함께 본다. 프롬프트
# `root@tars ~#`(12칸, LT-M0 전에는 `root@(none) ~#` 14칸 — 상자는 그대로 둔다)는 논리 (20, 20)부터 한 행이고 물리로는 (40, 40)부터 224 × 32다.
echo "=== boot A (2): the screendump is ${XRES}x${YRES} in 2x2 blocks with the prompt drawn ==="
screendump "$BEFORE" || report_failure "boot A: screendump did not write ${BEFORE}"
SIZE="$(ppm_size "$BEFORE")"
[ "$SIZE" = "${XRES}x${YRES}" ] ||
  report_failure "boot A: the screendump is ${SIZE}, expected ${XRES}x${YRES}"
BAD="$(ppm_blocks "$BEFORE" 2 0 0 "$XRES" "$YRES")"
[ "$BAD" = "0" ] ||
  report_failure "boot A: ${BAD} mismatch(es) inside 2x2 blocks of the first frame (expected 0)"
PROMPT_INK="$(ppm_ink "$BEFORE" 40 40 224 32)"
PROMPT_N="${PROMPT_INK##*ink=}"
[ "$PROMPT_N" -gt 0 ] ||
  report_failure "boot A: the prompt row has no ink on the physical screen (${PROMPT_INK})"
echo "boot A: ${SIZE}, 0 block mismatches, prompt row ${PROMPT_INK}"

# ── 판정 3: 키를 친 뒤의 부분 프레임이 물리 화면에 닿는다 ─────────────────
#
# `echo 한`는 fish가 한 글자 `한`(U+D55C)으로 바꿔 둘째 행에 찍는다. 이 프레임은 통째가
# 아니다 — 첫 프레임 · 워크스페이스 전환 · 트리 변경이 아니므로 바뀐 행만 칠하고 그 행의
# clip으로 present한다(DR-M2). 그래서 이 글자가 물리 화면에 있으면 부분 present가 clip을 늘려
# 옮긴 것이다. 폭 2칸 글자라 terminal이 `ink> R,C U+D55C left=L right=R`로 논리 fb에서 센
# 잉크를 찍는다 — 물리 상자(칸 둘 × 2 = 32 × 32)의 잉크는 정확히 그 네 배여야 한다.
echo "=== boot A (3): a typed line reaches the physical screen through a partial present ==="
type_keys e c h o spc backslash u d 5 5 c ret
wait_for_log 'terminal: ink> [0-9]+,[0-9]+ U\+D55C left=[0-9]+ right=[0-9]+' ||
  report_failure "boot A: terminal never drew U+D55C (no ink> line)"
wait_for_screen '한.*root@tars ~#' ||
  report_failure "boot A: the shell did not print U+D55C and come back to the prompt"
sleep 1
INK_LINE="$(tlog | grep -a 'terminal: ink> [0-9]*,[0-9]* U+D55C ' | tail -n 1 | tr -d '\r' | from_terminal)"
read -r INK_ROW INK_COL INK_L INK_R < <(sed -E 's/^terminal: ink> ([0-9]+),([0-9]+) U\+D55C left=([0-9]+) right=([0-9]+).*/\1 \2 \3 \4/' <<<"$INK_LINE")
LOGICAL=$(( INK_L + INK_R ))
[ "$LOGICAL" -gt 0 ] || report_failure "boot A: terminal counted no ink for U+D55C (${INK_LINE})"
screendump "$AFTER" || report_failure "boot A: screendump did not write ${AFTER}"
BX=$(( 2 * (20 + INK_COL * 8) ))
BY=$(( 2 * (20 + INK_ROW * 16) ))
CELL_INK="$(ppm_ink "$AFTER" "$BX" "$BY" 32 32)"
PHYS="${CELL_INK##*ink=}"
echo "boot A: ${INK_LINE} -> physical (${BX},${BY}) 32x32 ${CELL_INK}"
[ "$PHYS" -eq $(( 4 * LOGICAL )) ] ||
  report_failure "boot A: U+D55C has ${PHYS} ink pixels on the physical screen, expected 4 x ${LOGICAL} = $(( 4 * LOGICAL ))"
BAD="$(ppm_blocks "$AFTER" 2 0 0 "$XRES" "$YRES")"
[ "$BAD" = "0" ] ||
  report_failure "boot A: ${BAD} mismatch(es) inside 2x2 blocks after typing (expected 0)"
echo "boot A: the partial frame is on the physical screen, 4 x ${LOGICAL} ink, 0 block mismatches"

# ── 판정 6: buffer_scale 2 창이 물리 화면에 1:1로 놓인다(WY-M3) ─────────────
#
# 셸에서 창 모드로 띄우면 셸 오른쪽 column이 된다(WY-M2). 서버의 configure는 논리 크기이고(`w` · `h`), 클라이언트는
# `--follow-size`로 그 크기 × 2 버퍼를 보내며 `set_buffer_scale 2`다 — commit 줄의 `scale=1`(놓는 배수, surface 크기 = 논리
# 크기)과 끝의 `bs=2`. 그 사각형(`pane>` 줄)이 물리 1픽셀 바둑판이면 그림자를 거치지 않았다(거치면 솎인 한 색이다 —
# 단계 A의 화면). 2 × 2 블록 검사는 0이 아니어야 한다(늘린 그림이 아니다).
echo "=== boot A (6): a buffer-scale-2 window is drawn 1:1 on the physical screen ==="
type_text "tars-wl-test --buffer-scale 2 --checker --follow-size --color ${WL_COLOR^^} > /tmp/hs6.log &"
type_keys ret
wait_for_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1' || report_failure "(6) the window did not open as a column (no 'wl> column … slot=1 ws=1')"
ID6="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
wait_for_log "terminal: wl> configure id=${ID6} w=[0-9]+ h=[0-9]+ act=1" || report_failure "(6) no configure for the window"
read -r CW CH < <(tlog | grep -aoE "terminal: wl> configure id=${ID6} w=[0-9]+ h=[0-9]+" | tail -n 1 | sed -E 's/.* w=([0-9]+) h=([0-9]+)$/\1 \2/')
wait_for_log "terminal: wl> commit id=${ID6} buf=$(( 2 * CW ))x$(( 2 * CH )) scale=1 at=0,0 bs=2" ||
  report_failure "(6) no 'wl> commit id=${ID6} buf=$(( 2 * CW ))x$(( 2 * CH )) scale=1 at=0,0 bs=2' (configure ${CW}x${CH})"
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${ID6} " || report_failure "(6) the pane> line does not show the window as slot 1"
read -r X0 Y0 X1 Y1 < <(app_rect "$ID6") || report_failure "(6) could not read the window's rectangle"
sleep 1
SHOT6="${SCREENS_DIR}/bs2.ppm"
screendump "$SHOT6" || report_failure "(6) screendump did not write ${SHOT6}"
BAD="$(ppm_checker "$SHOT6" 1 "$WL_COLOR" "$X0" "$Y0" "$X1" "$Y1")"
[ "$BAD" = "0" ] || report_failure "(6) the window (${X0},${Y0})-(${X1},${Y1}) is not a 1-pixel checkerboard (${BAD} pixels off)"
BLK="$(ppm_blocks "$SHOT6" 2 "$X0" "$Y0" "$X1" "$Y1")"
[ "$BLK" -gt 0 ] || report_failure "(6) the window looks like 2x2 blocks (0 mismatches) — it went through the shadow"
echo "(6): configure ${CW}x${CH}, buffer $(( 2 * CW ))x$(( 2 * CH )) bs=2, (${X0},${Y0})-(${X1},${Y1}) is a 1-pixel checkerboard, ${BLK} 2x2 mismatches"

# ── 판정 7: 셸의 프레임과 화살표가 그 그림을 덮지 않는다 ─────────────────────
#
# (a) 셸에 포커스(Cmd+[)를 주고 창의 로그를 친다 — 셸의 부분 프레임(바뀐 행만 늘린다). 클라이언트가 받은 배율 줄 셋이
#     화면에 나오고, 창은 그대로 1:1이며 셸 쪽(창 왼쪽 띠 전부)은 2 × 2 블록이다.
echo "=== boot A (7a): a partial shell frame leaves the window 1:1 ==="
type_keys alt-bracket_left
wait_for_log 'terminal: pane> ws=1/1 panes=2 focus=0 ' || report_failure "(7a) Cmd+[ did not focus the shell"
type_text 'cat /tmp/hs6.log'
type_keys ret
wait_for_screen 'wl-test> preferred scale=2' || report_failure "(7a) the client never got 'preferred scale=2'"
wait_for_screen 'wl-test> output mode=2880x1800 scale=2' || report_failure "(7a) the client never got 'output mode=2880x1800 scale=2'"
wait_for_screen 'wl-test> surface on output' || report_failure "(7a) the client never got wl_surface.enter"
sleep 1
SHOT7A="${SCREENS_DIR}/bs2-shell.ppm"
screendump "$SHOT7A" || report_failure "(7a) screendump did not write ${SHOT7A}"
BAD="$(ppm_checker "$SHOT7A" 1 "$WL_COLOR" "$X0" "$Y0" "$X1" "$Y1")"
[ "$BAD" = "0" ] || report_failure "(7a) after a partial shell frame the window is not 1:1 any more (${BAD} pixels off)"
BLK="$(ppm_blocks "$SHOT7A" 2 0 0 "$X0" "$YRES")"
[ "$BLK" = "0" ] || report_failure "(7a) the shell side has ${BLK} 2x2 mismatches (expected 0)"
echo "(7a): preferred 2 · output 2880x1800 scale 2 · surface enter reached the client, the window stayed 1:1, the shell side is 2x2 blocks"

# (b) 창에 포커스(Cmd+])를 돌려주고 Cmd+R — column이 화면 폭이 되는 통째 프레임, 새 configure, 클라이언트의 새 버퍼.
echo "=== boot A (7b): a whole frame (Cmd+R) and a new buffer stay 1:1 ==="
type_keys alt-bracket_right
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${ID6} " || report_failure "(7b) Cmd+] did not focus the window"
type_keys alt-r
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${ID6} rect=0,0 175x53 " ||
  report_failure "(7b) Cmd+R did not widen the window's column to the whole grid"
wait_for_log "terminal: wl> configure id=${ID6} w=1400 h=848 act=1" || report_failure "(7b) no 'wl> configure id=${ID6} w=1400 h=848 act=1'"
wait_for_log "terminal: wl> commit id=${ID6} buf=2800x1696 scale=1 at=0,0 bs=2" || report_failure "(7b) no 'wl> commit id=${ID6} buf=2800x1696 scale=1 at=0,0 bs=2'"
read -r X0 Y0 X1 Y1 < <(app_rect "$ID6") || report_failure "(7b) could not read the window's rectangle"
sleep 1
SHOT7B="${SCREENS_DIR}/bs2-wide.ppm"
screendump "$SHOT7B" || report_failure "(7b) screendump did not write ${SHOT7B}"
BAD="$(ppm_checker "$SHOT7B" 1 "$WL_COLOR" "$X0" "$Y0" "$X1" "$Y1")"
[ "$BAD" = "0" ] || report_failure "(7b) the widened window (${X0},${Y0})-(${X1},${Y1}) is not 1:1 (${BAD} pixels off)"
echo "(7b): Cmd+R gave 1400x848, the new 2800x1696 buffer fills (${X0},${Y0})-(${X1},${Y1}) 1:1"

# (c) 포인터를 창 위로 옮긴다. 화살표(커서를 숨기지 않은 창)는 terminal이 그리고, 화살표만 옮기는 바퀴는 그 상자만 늘린다 —
#     물리 합성이 그 상자를 창에서 다시 옮기고 화살표의 불투명 픽셀만 다시 찍는다. 그래서 화살표 상자(논리 12 × 19 → 물리
#     24 × 38)에 화살표 색이 4 × 118 픽셀이고, 상자 밖 창(상자 위의 띠 · 왼쪽 띠)은 1:1 그대로다. 한 번 더 옮긴 뒤 옛 상자
#     자리가 다시 1:1이다(흐린 조각이 안 남는다).
echo "=== boot A (7c): the arrow over the window, and where it was ==="
tlog | grep -a 'terminal: pointer> open ' >/dev/null || report_failure "(7c) terminal did not open the USB mouse"
move_to 700 400 || report_failure "(7c) the pointer did not reach 700,400 (last at: $(last_at))"
wait_for_log "terminal: wl> pointer enter id=${ID6}" || report_failure "(7c) no 'wl> pointer enter id=${ID6}'"
sleep 1
SHOT7C="${SCREENS_DIR}/bs2-arrow.ppm"
screendump "$SHOT7C" || report_failure "(7c) screendump did not write ${SHOT7C}"
ARROW_PX="$(ppm_arrow "$SHOT7C" 1400 800 24 38)"
[ "$ARROW_PX" = "472" ] || report_failure "(7c) the arrow box at physical 1400,800 has ${ARROW_PX} arrow pixels (expected 4 x 118 = 472)"
BAD="$(ppm_checker "$SHOT7C" 1 "$WL_COLOR" "$X0" "$Y0" "$X1" 800)"
[ "$BAD" = "0" ] || report_failure "(7c) the window above the arrow is not 1:1 (${BAD} pixels off)"
BAD="$(ppm_checker "$SHOT7C" 1 "$WL_COLOR" "$X0" 800 1400 "$Y1")"
[ "$BAD" = "0" ] || report_failure "(7c) the window left of the arrow is not 1:1 (${BAD} pixels off)"
move_to 900 600 || report_failure "(7c) the pointer did not reach 900,600"
sleep 1
SHOT7D="${SCREENS_DIR}/bs2-arrow-moved.ppm"
screendump "$SHOT7D" || report_failure "(7c) screendump did not write ${SHOT7D}"
BAD="$(ppm_checker "$SHOT7D" 1 "$WL_COLOR" "$X0" "$Y0" "$X1" 1200)"
[ "$BAD" = "0" ] || report_failure "(7c) after the arrow moved on, the window above it is not 1:1 (${BAD} pixels off — a blurred patch stayed)"
echo "(7c): the arrow has 472 arrow pixels over the window, the window around it and where it was is 1:1"

# (d) 닫고 `--buffer-scale 1`로 다시 — 배율을 안 쓰는 창은 HS의 늘린 길이다: 2물리 픽셀 바둑판이고 2 × 2 블록이다. 서버의
#     선호는 그대로 2다(클라이언트가 1을 골랐다). 포인터는 창 밖(셸 쪽이 아니라 아래 상태 줄)으로 옮겨 상자에서 뺀다.
echo "=== boot A (7d): a buffer-scale-1 window is the upscaled path ==="
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${ID6} ws=1 slot=1" || report_failure "(7d) Cmd+Q did not close the window"
move_to 700 890 || report_failure "(7d) the pointer did not reach 700,890"
type_text "tars-wl-test --buffer-scale 1 --checker --follow-size --color ${WL_COLOR^^} > /tmp/hs7.log &"
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' 2 || report_failure "(7d) the second window did not open as a column"
ID7="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
read -r CW CH < <(tlog | grep -aoE "terminal: wl> configure id=${ID7} w=[0-9]+ h=[0-9]+" | tail -n 1 | sed -E 's/.* w=([0-9]+) h=([0-9]+)$/\1 \2/')
wait_for_log "terminal: wl> commit id=${ID7} buf=${CW}x${CH} scale=1 at=0,0" ||
  report_failure "(7d) no 'wl> commit id=${ID7} buf=${CW}x${CH} scale=1 at=0,0' without bs="
if tlog | grep -aE "terminal: wl> commit id=${ID7} .* bs=" >/dev/null; then
  report_failure "(7d) the buffer-scale-1 window's commit line carries bs="
fi
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${ID7} " || report_failure "(7d) the pane> line does not show the window"
read -r X0 Y0 X1 Y1 < <(app_rect "$ID7") || report_failure "(7d) could not read the window's rectangle"
sleep 1
SHOT7E="${SCREENS_DIR}/bs1.ppm"
screendump "$SHOT7E" || report_failure "(7d) screendump did not write ${SHOT7E}"
BAD="$(ppm_checker "$SHOT7E" 2 "$WL_COLOR" "$X0" "$Y0" "$X1" "$Y1")"
[ "$BAD" = "0" ] || report_failure "(7d) the buffer-scale-1 window is not a 2-pixel checkerboard (${BAD} pixels off)"
BLK="$(ppm_blocks "$SHOT7E" 2 "$X0" "$Y0" "$X1" "$Y1")"
[ "$BLK" = "0" ] || report_failure "(7d) the buffer-scale-1 window has ${BLK} 2x2 mismatches (expected 0)"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${ID7} ws=1 slot=1" || report_failure "(7d) Cmd+Q did not close the second window"
echo "(7d): configure ${CW}x${CH}, buffer ${CW}x${CH} without bs=, (${X0},${Y0})-(${X1},${Y1}) is a 2-pixel checkerboard in 2x2 blocks"
tlog | grep -aoE 'terminal: wl> (frame full|phys arrow) [^|]*' | tr -d '\r' | sed 's/^/measure: /'

stop_boot

# ══ 부팅 B — display_scale=1이 auto를 이긴다 ═══════════════════════════
#
# 같은 2880 × 1800에서 설정이 1을 강제한다. 그러면 HS 전과 같은 길이다 — 그림자 없이 dumb
# 버퍼에 바로 그린다. 격자는 (2880 - 40) / 8 = 355열, (1800 - 40) / 16 = 110행이다.
SEED="$(mktemp -d)"
printf 'shell=fish\ndisplay_scale=1\n' > "$SEED/tars.conf"
DISK="${REPO_ROOT}/out/hs-settings.img"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-hs -d "$SEED" "$DISK"
rm -rf "$SEED"

echo "=== boot B: ${XRES}x${YRES}, display_scale=1 on the settings disk ==="
boot "$DISK"

# ── 판정 4: 설정이 닿았고 배율 1, 격자 355 × 110 ───────────────────────
echo "=== boot B (4): display_scale=1 wins over auto ==="
grep -a 'tars-init: loaded /config/tars.conf' "$LOG" >/dev/null ||
  report_failure "boot B: the settings disk was not loaded (no 'tars-init: loaded /config/tars.conf')"
tlog | grep -aE 'tars-init: config shell=.* display_scale=1' >/dev/null ||
  report_failure "boot B: the tars-init: config line does not carry display_scale=1"
tlog | grep -a 'kms: scale 1 (2880x1800 -> 2880x1800)' >/dev/null ||
  report_failure "boot B: no 'kms: scale 1 (2880x1800 -> 2880x1800)'"
tlog | grep -a 'terminal: grid 355x110 (fb 2880x1800)' >/dev/null ||
  report_failure "boot B: no 'terminal: grid 355x110 (fb 2880x1800)'"

# 배율 1의 글자는 늘린 것이 아니다 — 프롬프트 행(논리 = 물리 (20, 20)부터 112 × 16)이
# 2 × 2 블록이 아니어야 한다. 부팅 A의 판정 2가 "블록이 고르다"를 보므로, 같은 셈이 여기서
# 0이 아닌 것이 그 셈이 늘리기를 실제로 가른다는 증거다.
screendump "$ONE" || report_failure "boot B: screendump did not write ${ONE}"
BAD="$(ppm_blocks "$ONE" 2 20 20 132 36)"
[ "$BAD" -gt 0 ] ||
  report_failure "boot B: the scale-1 prompt row looks like 2x2 blocks (0 mismatches)"
echo "boot B: scale 1, grid 355x110, the prompt row has ${BAD} 2x2 mismatches (drawn at 1x)"

# ── 판정 8: 배율 1에서 서버는 1을 알린다(WY-M3) ───────────────────────────
#
# 같은 2880 × 1800이지만 배율 1이다 — `preferred scale=1`, `wl_output`은 물리 그대로에 scale 1, commit 줄에 `bs=`가 없다.
# 판정 5의 reload가 terminal(과 소켓)을 다시 띄우므로 그 전에 닫는다.
echo "=== boot B (8): at scale 1 the server says 1 ==="
type_text "tars-wl-test --checker --follow-size --color ${WL_COLOR^^} > /tmp/hs8.log &"
type_keys ret
wait_for_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1' || report_failure "(8) the window did not open as a column"
ID8="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
wait_for_log "terminal: wl> commit id=${ID8} buf=[0-9]+x[0-9]+ scale=1 at=0,0" || report_failure "(8) no commit line for the window"
if tlog | grep -aE "terminal: wl> commit id=${ID8} .* bs=" >/dev/null; then
  report_failure "(8) the commit line carries bs= at scale 1"
fi
type_keys alt-bracket_left
wait_for_log 'terminal: pane> ws=1/1 panes=2 focus=0 ' || report_failure "(8) Cmd+[ did not focus the shell"
type_text 'cat /tmp/hs8.log'
type_keys ret
wait_for_screen 'wl-test> preferred scale=1' || report_failure "(8) the client never got 'preferred scale=1'"
wait_for_screen 'wl-test> output mode=2880x1800 scale=1' || report_failure "(8) the client never got 'output mode=2880x1800 scale=1'"
type_keys alt-bracket_right
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${ID8} " || report_failure "(8) Cmd+] did not focus the window"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${ID8} ws=1 slot=1" || report_failure "(8) Cmd+Q did not close the window"
wait_for_log 'terminal: pane> ws=1/1 panes=1 focus=0 ' || report_failure "(8) the shell did not take the whole width back"
echo "(8): preferred 1 and output 2880x1800 scale 1 reached the client, no bs= on the commit line"

# ── 판정 5: tars-config set · reload terminal이 배율을 바꾼다 ─────────────
#
# design 결정 4. set이 /config/tars.conf의 한 줄을 고치고, reload terminal이 terminal을 다시
# 띄운다 — 새 terminal이 화면을 다시 열며 배율 2를 고른다. init의 reload 줄이 그 값을 싣는다.
echo "=== boot B (5): tars-config set display_scale=2 and reload terminal pick scale 2 ==="
type_keys t a r s minus c o n f i g spc s e t spc d i s p l a y shift-minus s c a l e equal 2 ret
wait_for_screen 'display_scale: 1 -> 2' ||
  report_failure "boot B: tars-config set display_scale=2 did not answer 'display_scale: 1 -> 2'"
# init이 파일을 다시 읽어야 reload terminal이 새 값을 싣는다(pointer 체인 부팅 C와 같은 순서). 화면
# 글자가 아니라 init의 줄을 기다린다 — set의 답과 reload의 답이 같은 글자로 시작한다.
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_log 'tars-init: reload of /config/tars.conf' ||
  report_failure "boot B: tars-config reload never reached init (no 'tars-init: reload of /config/tars.conf')"
type_keys t a r s minus c o n f i g spc r e l o a d spc t e r m i n a l ret
wait_for_log 'tars-init: reload terminal: pid [0-9]+, .* display_scale=2' ||
  report_failure "boot B: init's reload terminal line does not carry display_scale=2"
wait_for_log 'kms: scale 2 \(2880x1800 -> 1440x900\)' ||
  report_failure "boot B: the restarted terminal did not pick scale 2"
wait_for_log 'terminal: grid 175x53 \(fb 1440x900\)' ||
  report_failure "boot B: the restarted terminal's grid is not 175x53"
wait_for_screen 'root@tars ~#' ||
  report_failure "boot B: the restarted terminal never showed a prompt"
echo "boot B: reload terminal brought the screen back at scale 2"

stop_boot
echo "PASS: HS-M0 · WY-M3 — auto picks 2 on ${XRES}x${YRES}, present upscales whole and partial frames, a buffer-scale-2 Wayland window is drawn 1:1 through shell frames and the arrow while a buffer-scale-1 window is upscaled, display_scale=1 and tars-config set win and the server says 1"
