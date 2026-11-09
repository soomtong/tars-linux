#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# FU 체인 — 전체 화면(FU-M0 · FU-M1). 서른두번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   설정 디스크의 fullscreen=on → init이 읽어(`tars-init: config … fullscreen=on`) terminal의 argv 14번 칸으로
#   → terminal이 첫 프레임부터 여백 없이 격자를 화면 끝까지 둔다(`grid 160x50 (fb 1280x800)`, `fullscreen> on`)
#   → 상태 띠를 안 그린다(`status> ink fg=0 (fullscreen)`) — 프롬프트가 화면의 (0, 0)부터 찍힌다(screendump)
#   → 셸이 그 크기를 안다(fish의 $LINES $COLUMNS = 50 160)
#   그리고 여백 있는 부팅에서 Cmd+Ctrl+F가 실행 중에 켜고 끈다 — 셸이 SIGWINCH로 새 크기를 알고(47 155 → 50 160
#   → 47 155), 셸은 닫히지 않는다(켜기 전에 세운 변수가 끈 뒤에도 있다). 같은 셸이 printf로 내보낸 xterm의
#   `CSI 10;1 t`가 켜고 `CSI 10;2 t`가 끈다 — 비슷한 `CSI 10 t` · `CSI 1;10 t`는 아무것도 안 바꾼다(FU-M1).
#   마지막으로 tars-config set · reload terminal이 다시 뜬 terminal을 전체 화면으로 띄운다.
#
# 화면은 1280 × 800(게이트의 다른 체인과 같다). 여백이 있으면 (1280 - 40) / 8 = 155열, (800 - 40) / 16 = 47행,
# 전체 화면이면 160 × 50이고 남는 픽셀이 없어 원점이 (0, 0)이다.
#
# 부팅이 둘이다. 둘 다 keyboard=apple을 적은 설정 디스크를 물린다 — QEMU의 키보드는 PC라 그대로면 Cmd가
# Alt 자리다. apple이면 meta_l이 Cmd다(gate_lib.sh의 apple_disk와 같은 이유). monitor 포트는 45505 —
# 예약 범위(RP-M0)에서 devtools의 45504 다음 빈 자리다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# fullscreen의 파싱 · 견본 · tars-config set의 거절(`yes`) · argv 칸은 여기서 먼저 걸러진다
# (config_test · config_edit_test · reload_test · screen_args_test).
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 격자 자리 셈 · 사각형 자르기(geometry_test)와 Cmd+Ctrl+F(input_test)는 여기서 먼저 걸러진다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45505
REPO_ROOT="$(cd .. && pwd)"
XRES=1280
YRES=800

# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로 넘긴다.
# out/은 .gitignore 대상이고 루트 check.sh의 clean()이 지운다.
SCREENS_DIR="${REPO_ROOT}/out/fu"
mkdir -p "$SCREENS_DIR"
FULL="${SCREENS_DIR}/full.ppm"
rm -f "$FULL"

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
  echo "--- grid, fullscreen and config lines ---"
  tlog | grep -aE 'terminal: grid |terminal: fullscreen> |tars-init: config shell=|tars-init: reload terminal' | tr -d '\r'
  echo "--- status ink lines ---"
  tlog | grep -a 'terminal: status> ink' | tr -d '\r' | tail -n 3
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 15초(hidpi/check.sh와 같다).
wait_for_log() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if tlog | grep -aE -- "$pattern" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 패턴에 맞는 로그 줄이 `want`개가 될 때까지 기다린다(FU-M1). 같은 `fullscreen>` 줄이 이 부팅에 여러 번
# 찍히므로 "있는가"가 아니라 "늘었는가"를 본다.
wait_for_count() {
  local pattern="$1" want="$2" i
  for i in $(seq 1 150); do
    if [ "$(tlog | grep -acE -- "$pattern")" -eq "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# fish에서 `printf '\033[<args>'`를 친다(FU-M1). 화면의 셸이 그 바이트를 패널 출력으로 내보낸다 — 프로그램이
# 시퀀스를 보내는 것과 같은 길이다. `args`는 키 이름의 목록(`1 0 semicolon 1 t`).
print_csi() {
  type_keys p r i n t f spc apostrophe backslash 0 3 3 bracket_left "$@" apostrophe ret
}

# 화면을 하나 뜬다. QEMU가 파일을 다 쓸 때까지 기다린다(hidpi/check.sh와 같다).
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

# 상자 하나에서 가장 많은 색(바탕)과 그것과 다른 픽셀의 수(잉크). `bg=RRGGBB ink=N`(hidpi/check.sh와 같다).
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

# 설정 디스크 하나. $1 = 이미지 경로, $2 = 라벨, 나머지 = tars.conf의 줄.
settings_disk() {
  local img="$1" label="$2" seed
  shift 2
  seed="$(mktemp -d)"
  printf '%s\n' "$@" > "$seed/tars.conf"
  rm -f "$img"
  truncate -s 16M "$img"
  mkfs.ext2 -F -q -m 0 -L "$label" -d "$seed" "$img"
  rm -rf "$seed"
}

# 부팅 하나. $1 = 설정 디스크.
boot() {
  local disk="$1"
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
    -drive file="$disk",if=virtio,format=raw \
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
  wait_for_screen 'root@\(none\) ~#' ||
    report_failure "the shell prompt never showed up"
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

# 셸에 창 크기를 묻는다. initrd에는 stty가 없다 — fish가 들고 있는 $LINES · $COLUMNS를 찍는다. fish는
# SIGWINCH를 받으면 그 둘을 고치므로, 이것은 pty의 창 크기가 셸에 닿았는가를 본다. 줄마다 머리표($1)를
# 달아 앞서 찍힌 같은 크기와 섞이지 않게 한다 — `echo b1-$LINES-$COLUMNS`는 `b1-47-155`를 찍고, 화면에
# 남은 명령 줄에는 `$`가 있어 그 글자와 안 맞는다.
ask_size() {
  local tag="$1" i
  local keys=(e c h o spc)
  for (( i = 0; i < ${#tag}; i++ )); do keys+=("${tag:i:1}"); done
  keys+=(minus shift-4 shift-l shift-i shift-n shift-e shift-s minus shift-4 shift-c shift-o shift-l shift-u shift-m shift-n shift-s ret)
  type_keys "${keys[@]}"
}

# ══ 부팅 A — fullscreen=on으로 시작한다 ════════════════════════════════
DISK_A="${REPO_ROOT}/out/fu-on.img"
settings_disk "$DISK_A" tars-fu-a 'shell=fish' 'keyboard=apple' 'fullscreen=on'
echo "=== boot A: ${XRES}x${YRES}, fullscreen=on on the settings disk ==="
boot "$DISK_A"

# ── 판정 1: 설정이 닿았고 첫 프레임부터 160 × 50 ──────────────────────────
echo "=== boot A (1): the first frame is already fullscreen ==="
grep -a 'tars-init: loaded /config/tars.conf' "$LOG" >/dev/null ||
  report_failure "boot A: the settings disk was not loaded (no 'tars-init: loaded /config/tars.conf')"
tlog | grep -aE 'tars-init: config shell=.* fullscreen=on' >/dev/null ||
  report_failure "boot A: the tars-init: config line does not carry fullscreen=on"
tlog | grep -a 'terminal: grid 160x50 (fb 1280x800)' >/dev/null ||
  report_failure "boot A: no 'terminal: grid 160x50 (fb 1280x800)'"
tlog | grep -a 'terminal: fullscreen> on grid 160x50 origin 0,0' >/dev/null ||
  report_failure "boot A: no 'terminal: fullscreen> on grid 160x50 origin 0,0'"
tlog | grep -a 'terminal: status> ink fg=0 (fullscreen)' >/dev/null ||
  report_failure "boot A: the status line was not hidden (no 'status> ink fg=0 (fullscreen)')"

# ── 판정 2: 프롬프트가 화면의 (0, 0)부터 찍혔다 ──────────────────────────
#
# 여백이 있으면 (0, 0) ~ (20, 20)은 여백 색 한 가지라 잉크가 0이다. 프롬프트 `root@(none) ~#`(14칸)의
# 첫 행이 (0, 0)부터 112 × 16이면 여백이 없다는 것이다.
echo "=== boot A (2): the prompt starts at the top-left pixel ==="
screendump "$FULL" || report_failure "boot A: screendump did not write ${FULL}"
CORNER="$(ppm_ink "$FULL" 0 0 112 16)"
[ "${CORNER##*ink=}" -gt 0 ] ||
  report_failure "boot A: no ink at (0,0) 112x16 — the prompt is not at the corner (${CORNER})"
echo "boot A: (0,0) 112x16 ${CORNER}"

# ── 판정 3: 셸이 그 크기를 안다 ──────────────────────────────────────────
echo "=== boot A (3): the shell sees LINES 50 COLUMNS 160 ==="
ask_size a1
wait_for_screen 'a1-50-160' ||
  report_failure "boot A: LINES COLUMNS is not 50 160 in the shell"
echo "boot A: the shell sees 50 rows and 160 columns"

stop_boot

# ══ 부팅 B — 여백으로 시작해 Cmd+Ctrl+F로 켜고 끈다 ═════════════════════
DISK_B="${REPO_ROOT}/out/fu-off.img"
settings_disk "$DISK_B" tars-fu-b 'shell=fish' 'keyboard=apple'
echo "=== boot B: ${XRES}x${YRES}, no fullscreen key ==="
boot "$DISK_B"

# ── 판정 4: 여백 있는 시작 — FU 전과 같다 ────────────────────────────────
echo "=== boot B (4): the grid is 155x47 and no fullscreen line ==="
tlog | grep -aE 'tars-init: config shell=.* fullscreen=off' >/dev/null ||
  report_failure "boot B: the tars-init: config line does not carry fullscreen=off"
tlog | grep -a 'terminal: grid 155x47 (fb 1280x800)' >/dev/null ||
  report_failure "boot B: no 'terminal: grid 155x47 (fb 1280x800)'"
if tlog | grep -a 'terminal: fullscreen> ' >/dev/null; then
  report_failure "boot B: a fullscreen> line before any key"
fi
type_keys s e t spc f u shift-minus m a r k spc 7 ret
ask_size b1
wait_for_screen 'b1-47-155' ||
  report_failure "boot B: LINES COLUMNS is not 47 155 before the key"

# ── 판정 5: Cmd+Ctrl+F가 켜고, 셸이 새 크기를 안다 ─────────────────────────
echo "=== boot B (5): Cmd+Ctrl+F turns it on ==="
type_keys meta_l-ctrl-f
wait_for_log 'terminal: fullscreen> on grid 160x50 origin 0,0' ||
  report_failure "boot B: Cmd+Ctrl+F did not turn fullscreen on"
ask_size b2
wait_for_screen 'b2-50-160' ||
  report_failure "boot B: LINES COLUMNS is not 50 160 after Cmd+Ctrl+F"

# ── 판정 6: 다시 누르면 끄고, 같은 셸이다 ─────────────────────────────────
echo "=== boot B (6): Cmd+Ctrl+F again turns it off, same shell ==="
type_keys meta_l-ctrl-f
wait_for_log 'terminal: fullscreen> off grid 155x47 origin 20,20' ||
  report_failure "boot B: the second Cmd+Ctrl+F did not turn fullscreen off"
ask_size b3
wait_for_screen 'b3-47-155' ||
  report_failure "boot B: LINES COLUMNS is not 47 155 after turning it off"
type_keys e c h o spc m a r k shift-4 f u shift-minus m a r k ret
wait_for_screen 'mark7' ||
  report_failure "boot B: the shell variable set before the key is gone — the shell was replaced"
echo "boot B: 47x155 -> 50x160 -> 47x155 in one shell"

# ── 판정 7: 패널의 CSI 10 ; Ps t가 켜고 끄고, 비슷한 시퀀스는 무시한다(FU-M1) ─────
#
# 지금까지 on · off 줄이 하나씩이다. 시퀀스가 켜면 on이 둘(줄은 모두 셋), 비슷한 것 둘 뒤에도 셋 그대로, 바꾸기(2)가 끄면 off가 둘.
echo "=== boot B (7): CSI 10;1 t turns it on, look-alikes do nothing, CSI 10;2 t toggles it off ==="
FS_ON='terminal: fullscreen> on grid 160x50 origin 0,0'
FS_OFF='terminal: fullscreen> off grid 155x47 origin 20,20'
print_csi 1 0 semicolon 1 t
wait_for_count "$FS_ON" 2 ||
  report_failure "boot B: printf CSI 10;1 t did not turn fullscreen on (want a second '${FS_ON}')"
ask_size w1
wait_for_screen 'w1-50-160' ||
  report_failure "boot B: LINES COLUMNS is not 50 160 after CSI 10;1 t"
# `CSI 10 t`(칸 하나) · `CSI 1;10 t`(첫 칸이 1)는 lib-vt만 보고 버린다. 셋째 `ask_size`가 찍힐 때면 앞의 출력은
# 이미 읽혔다 — 그때 줄 수가 그대로면 무시된 것이다.
print_csi 1 0 t
print_csi 1 semicolon 1 0 t
ask_size w2
wait_for_screen 'w2-50-160' ||
  report_failure "boot B: LINES COLUMNS is not 50 160 after the look-alike sequences"
[ "$(tlog | grep -acE -- 'terminal: fullscreen> ')" -eq 3 ] ||
  report_failure "boot B: a look-alike sequence changed fullscreen ($(tlog | grep -ac 'terminal: fullscreen> ') fullscreen> lines, want 3)"
print_csi 1 0 semicolon 2 t
wait_for_count "$FS_OFF" 2 ||
  report_failure "boot B: printf CSI 10;2 t did not toggle fullscreen off (want a second '${FS_OFF}')"
ask_size w3
wait_for_screen 'w3-47-155' ||
  report_failure "boot B: LINES COLUMNS is not 47 155 after CSI 10;2 t"
echo "boot B: CSI 10;1 t on, CSI 10 t and 1;10 t ignored, CSI 10;2 t off"

# ── 판정 8: tars-config set · reload terminal이 전체 화면으로 다시 띄운다 ────
echo "=== boot B (8): tars-config set fullscreen=on and reload terminal ==="
type_keys t a r s minus c o n f i g spc s e t spc f u l l s c r e e n equal o n ret
wait_for_screen 'fullscreen: off .*-> on' ||
  report_failure "boot B: tars-config set fullscreen=on did not answer 'fullscreen: off (default) -> on'"
type_keys t a r s minus c o n f i g spc r e l o a d ret
wait_for_log 'tars-init: reload of /config/tars.conf' ||
  report_failure "boot B: tars-config reload never reached init"
type_keys t a r s minus c o n f i g spc r e l o a d spc t e r m i n a l ret
wait_for_log 'tars-init: reload terminal: pid [0-9]+, .* fullscreen=on' ||
  report_failure "boot B: init's reload terminal line does not carry fullscreen=on"
wait_for_log 'terminal: grid 160x50 \(fb 1280x800\)' ||
  report_failure "boot B: the restarted terminal's grid is not 160x50"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "boot B: the restarted terminal never showed a prompt"
echo "boot B: reload terminal brought the screen back fullscreen"

stop_boot
echo "PASS: FU-M1 — fullscreen=on starts at 160x50 with no margin or status line, Cmd+Ctrl+F switches it live in the same shell, tars-config set and reload terminal carry it, a pane's CSI 10;Ps t switches it (FU-M1)"
