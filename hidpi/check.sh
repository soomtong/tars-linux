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
#
# 판정의 도구가 셋이다.
#   kms: · terminal: grid 줄 — 무엇이 골라졌고 격자가 몇 칸인가.
#   screendump — QEMU가 내보낸 물리 화면이다. 논리 fb를 되읽는 덤프(`ink>` · `pixel>`)는
#                늘리기가 빠져도 맞으므로, 늘리기는 여기서만 보인다. perl로 2 × 2 블록이
#                고른지와 상자 하나의 잉크를 센다.
#   ink> 줄 — terminal이 폭 2칸 글자의 칸에서 논리 fb를 되읽어 센 잉크(main.zig의 dumpInk).
#             screendump의 같은 자리 × 2와 견주는 "논리 그림"이다.
#
# 부팅이 둘이다. 부팅 A는 디스크 없이(auto), 부팅 B는 display_scale=1을 적은 설정 디스크를
# 물린다. monitor 포트는 둘 다 45502다 — 부팅이 차례로 돌고 앞 QEMU를 거둔 뒤에 연다.
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

# 화면을 하나 뜬다. QEMU가 파일을 다 쓸 때까지 기다린다 — 크기가 헤더 + 픽셀이 되면 끝이다.
screendump() {
  local file="$1" want i
  want=$(( 3 * XRES * YRES ))
  rm -f "$file"
  echo "screendump ${file}" >&3
  for i in $(seq 1 100); do
    if [ -f "$file" ] && [ "$(stat -c %s "$file")" -gt "$want" ]; then return 0; fi
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

# 상자 하나에서 가장 많은 색(바탕)과 그것과 다른 픽셀의 수(잉크). `bg=RRGGBB ink=N`.
# terminal의 dumpInk가 칸의 바탕색과 다른 픽셀을 세는 것과 같은 셈이다 — 글자가 칸의 반을
# 넘게 덮지 않는 한 가장 많은 색이 곧 칸의 바탕이다.
ppm_ink() {
  perl -e '
    my ($f, $x0, $y0, $w, $h) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3;
    my (%n, @px);
    for my $y ($y0 .. $y0 + $h - 1) {
      for my $x ($x0 .. $x0 + $w - 1) { my $p = substr($d, $y * $row + $x * 3, 3); $n{$p}++; push @px, $p; }
    }
    my ($bg) = sort { $n{$b} <=> $n{$a} } keys %n;
    my $ink = grep { $_ ne $bg } @px;
    printf "bg=%s ink=%d\n", unpack("H6", $bg), $ink;' "$@"
}

# 부팅 하나. 인자가 있으면 그 디스크 이미지를 물린다.
boot() {
  local disk="${1:-}"
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

# ══ 부팅 A — 디스크 없음, display_scale=auto ════════════════════════════
echo "=== boot A: ${XRES}x${YRES}, display_scale=auto ==="
boot

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
echo "PASS: HS-M0 — auto picks 2 on ${XRES}x${YRES}, present upscales whole and partial frames, display_scale=1 and tars-config set win"
