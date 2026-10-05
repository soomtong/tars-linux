#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# PD 체인 — 포인터 장치(PD-M0 · M1). 열아홉번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   QEMU가 USB 마우스를 하나 붙인 채 뜬다(-usb -device usb-mouse)
#   → terminal이 uevent netlink 소켓을 열고 /dev/input을 훑는다
#   → 연 fd에 ioctl로 성질을 묻고 pointer.zig의 classify가 마우스만 고른다
#   → HMP mouse_move · mouse_button이 USB HID 보고가 되고 evdev 이벤트가 된다
#   → Mouse 디코더가 SYN_REPORT마다 Frame을 내고 Pointer가 좌표를 clamp한다
#   → poll 회차마다 `pointer> at` 한 줄
#   → 부팅 뒤에 device_add로 꽂은 둘째 마우스를 커널 uevent가 알리고 terminal이 연다
#   → device_del로 뽑으면 그 fd가 POLLHUP을 올리고 terminal이 닫는다
#   → 움직이면 화살표가 따라온다. 움직임만 있는 회차는 화면 전체를 다시
#     그리지 않고 화살표 자리만 고친다(save-under, PD-M1)
#   → 키를 치면 숨고, 휠은 포인터 아래 패널을 세 줄씩 움직인다(PD-M1)
#
# copy · pane 체인에 끼우지 않은 이유는 PD design 결정 10이다. 그 체인들의
# 판정은 포인터가 없는 화면을 전제하고, 이 체인은 PD-M1부터 화살표가 보이는
# 프레임을 일부러 만든다.
#
# 판정의 도구가 셋이다.
#   pointer> 줄 — open · skip · close · at(main.zig). 좌표는 게이트
#                프레임버퍼 1280 × 800에서 나온다. 출발은 가운데(640, 400)다.
#                at 줄의 ink는 terminal이 직전 자리와 지금 자리의 화살표 사각형
#                둘에서 되읽은 화살표 색 픽셀 수다. 다 보이면 118이다.
#   screendump — QEMU가 내보낸 화면이다. at 줄은 terminal이 프레임버퍼에서
#                되읽은 것이라 present가 빠져도 맞는다. 여기는 present가
#                있어야 바뀐다. perl로 화살표 색을 세거나 두 장을 비교한다.
#   scroll> 줄 — 휠이 움직인 뷰포트(검사 11 · 12).
#
# HMP의 대상 마우스. info mice의 별표가 HMP mouse_move가 가는 장치다.
# device_add로 꽂은 마우스가 대상이 되고 device_del 뒤에는 원래 마우스로
# 돌아온다(PD-M0 plan 확정 1). 검사 6이 그것을 쓴다 — 꽂은 뒤의 움직임은 새
# 장치로만 오므로 "새 fd를 읽는다"가 at 줄로 보인다.
#
# 이동은 한 번에 100 이하로 민다. QEMU는 127을 넘는 이동을 보고 여럿으로
# 쪼개 보내므로(plan 확정 2) 큰 수도 합은 같지만, 보고 하나가 명령 하나인
# 편이 로그를 읽기 쉽다.
#
# 디스크를 물지 않는다. 포인터는 설정과 무관하다.
#
# 화살표가 보이는 동안 terminal의 덤프(style> · pixel> · cursor>)는 화살표
# 픽셀을 읽는다(PD design 위험 6). 이 체인은 그 덤프로 판정하지 않는다.

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

# 분류 · 디코더 · clamp는 여기서 먼저 걸러진다(pointer_test) — 부팅 전에
# 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 열여덟 체인이 45455~45487을 쓴다. 45489는 PD-M3의 부팅 B 몫이다(design 결정 10).
MONITOR_PORT=45488

REPO_ROOT="$(cd .. && pwd)"
# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로
# 넘긴다. out/은 .gitignore 대상이고 루트 check.sh의 clean()이 지운다
# (terminal/check.sh와 같은 자리).
SCREENS_DIR="${REPO_ROOT}/out/pd"
mkdir -p "$SCREENS_DIR"
BEFORE="${SCREENS_DIR}/before.ppm"
MOVED="${SCREENS_DIR}/moved.ppm"
HIDDEN="${SCREENS_DIR}/hidden.ppm"
GONE="${SCREENS_DIR}/gone.ppm"
rm -f "$BEFORE" "$MOVED" "$HIDDEN" "$GONE"

# 화살표가 다 보일 때의 ink. pointer.zig의 ARROW_INK와 같은 수다(테두리 49 +
# 안쪽 69). 모양을 고치면 함께 고친다 — pointer_test가 그 상수를 먼저 본다.
ARROW_INK=118

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
    "input: QEMU QEMU USB Mouse" \
    "terminal: screen>" \
    "terminal: pointer> open" \
    "terminal: pointer> skip" \
    "terminal: pointer> at" \
    "terminal: pointer> close" \
    "terminal: scroll>" \
    "terminal: copy> enter" \
    "terminal: pointer> uevent failed" \
    "terminal: pointer> scan failed"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- kernel mouse lines ---"
  grep -aE 'input: QEMU QEMU USB Mouse|USB disconnect' "$LOG" | tr -d '\r'
  echo "--- pointer lines ---"
  grep -a 'terminal: pointer>' "$LOG" | tr -d '\r' | tail -n 30
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# pointer> 줄 중 접두가 맞는 것의 개수. 인자는 `open ` · `close ` · `at `처럼
# 동사와 공백이다.
pointer_count() {
  grep -ac "terminal: pointer> $1" "$LOG" || true
}

# 마지막 at 줄. 값이 줄 끝까지 가므로 \r를 지운다(HI-M1 실측 4).
last_at() {
  grep -a 'terminal: pointer> at ' "$LOG" | tail -n 1 | tr -d '\r'
}

# 커널이 만든 USB 마우스 입력 장치의 수. 검사 6이 "QEMU · 커널이 둘째
# 마우스를 안 만들었다"와 "terminal이 그것을 안 열었다"를 가르는 데 쓴다.
kernel_mice() {
  grep -ac 'input: QEMU QEMU USB Mouse as' "$LOG" || true
}

screen_lines() {
  grep -ac 'terminal: screen>' "$LOG" || true
}

# 마지막 scroll> 줄의 값 하나(copy/check.sh의 scroll_field와 같다).
scroll_field() {
  grep -a 'terminal: scroll>' "$LOG" | tail -n 1 | tr -d '\r' | sed -E "s/.*$1=([0-9]+).*/\1/"
}

# screendump(P6) 하나에서 화살표 색(POINTER_FILL FCFCF4 · POINTER_EDGE 040810)인
# 픽셀의 수.
ppm_arrow() {
  perl -e '
    open(my $fh, "<:raw", $ARGV[0]) or die "$ARGV[0]: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+\d+\s+\d+\s+\d+\s//s or die "$ARGV[0]: not a P6 ppm\n";
    my $n = 0;
    for my $p (unpack("(a3)*", $d)) { $n++ if $p eq "\xFC\xFC\xF4" or $p eq "\x04\x08\x10"; }
    print "$n\n";' "$1"
}

# 두 screendump의 차이를 한 줄로 낸다.
#   n=다른 픽셀 수 box=x0,y0 x1,y1(그 경계 사각형, 양 끝 포함) other=둘째 장에서
#   화살표 색이 아닌 것의 수
# 같으면 n=0 box=-1,-1 -1,-1 other=0이다.
ppm_diff() {
  perl -e '
    sub load {
      open(my $fh, "<:raw", $_[0]) or die "$_[0]: $!\n";
      local $/; my $d = <$fh>;
      $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$_[0]: not a P6 ppm\n";
      return ($1, $d);
    }
    my ($w, $a) = load($ARGV[0]);
    my (undef, $b) = load($ARGV[1]);
    die "the two screendumps differ in size\n" if length($a) != length($b);
    my ($n, $other, $x0, $y0, $x1, $y1) = (0, 0, -1, -1, -1, -1);
    for (my $i = 0; $i < length($a); $i += 3) {
      my $q = substr($b, $i, 3);
      next if substr($a, $i, 3) eq $q;
      my $x = ($i / 3) % $w;
      my $y = int($i / 3 / $w);
      $x0 = $x if $x0 < 0 or $x < $x0;
      $x1 = $x if $x > $x1;
      $y0 = $y if $y0 < 0;
      $y1 = $y;
      $n++;
      $other++ unless $q eq "\xFC\xFC\xF4" or $q eq "\x04\x08\x10";
    }
    print "n=$n box=$x0,$y0 $x1,$y1 other=$other\n";' "$1" "$2"
}

# 마지막 at 줄이 패턴(ERE)에 맞을 때까지 기다린다. 있으면 0, 15초가 지나면 1.
# gate_lib.sh의 wait_for_screen과 같은 이유로 고정 sleep을 안 쓴다.
wait_for_at() {
  local pattern="$1" i line
  for i in $(seq 1 150); do
    line="$(last_at)"
    if grep -aqE -- "$pattern" <<<"$line"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 15초.
wait_for_log() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if grep -aE -- "$pattern" "$LOG" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 어떤 함수가 돌려주는 수가 기준 이상이 될 때까지 기다린다. 15초.
wait_for_count() {
  local fn="$1" arg="$2" want="$3" i
  for i in $(seq 1 150); do
    if [ "$("$fn" "$arg")" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# HMP 명령 하나. 키와 달리 로그가 자라기를 기다리지 않는다 — 결과는 부르는
# 쪽이 wait_for_at으로 본다.
hmp() {
  echo "$1" >&3
  sleep 0.05
}

# screendump 하나를 뜨고 파일이 생길 때까지 기다린다. 10초.
screendump() {
  local out="$1" i
  echo "screendump ${out}" >&3
  for i in $(seq 1 100); do
    if [ -s "$out" ]; then sleep 0.2; return 0; fi
    sleep 0.1
  done
  return 1
}

qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -usb -device usb-mouse,id=pdboot \
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
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "the shell prompt never showed up"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 검사 1: 부팅 때의 USB 마우스를 열고, 키보드와 전원 버튼은 건너뛴다 ──
#
# 마우스는 terminal보다 먼저 생긴다(plan 확정 3) — 처음 훑기가 연다. 늦게
# 생겨도 uevent가 연다. 어느 쪽이든 같은 줄이다.
#
# "정확히 하나"가 이 검사의 본체다. classify가 EV_KEY만 보면 전원 버튼과
# 키보드도 열려 셋이 된다(mutation 1).
echo "=== boot: the USB mouse is open, the keyboard and the power button are not ==="
wait_for_log 'terminal: pointer> open /dev/input/event[0-9]+ kind=mouse shown=0 name=QEMU QEMU USB Mouse' ||
  report_failure "terminal never opened the USB mouse (no 'pointer> open … kind=mouse shown=0 name=QEMU QEMU USB Mouse')"
OPENS="$(pointer_count 'open ')"
[ "$OPENS" -eq 1 ] ||
  report_failure "expected exactly one 'pointer> open' at boot, got ${OPENS}"
grep -aE 'terminal: pointer> skip /dev/input/event[0-9]+ kind=none name=AT Translated Set 2 keyboard' "$LOG" >/dev/null ||
  report_failure "the AT keyboard was not skipped as kind=none"
grep -aE 'terminal: pointer> skip /dev/input/event[0-9]+ kind=none name=Power Button' "$LOG" >/dev/null ||
  report_failure "the power button was not skipped as kind=none"
[ "$(pointer_count 'close ')" -eq 0 ] ||
  report_failure "a pointer device was closed before anything was unplugged"
[ "$(pointer_count 'at ')" -eq 0 ] ||
  report_failure "an 'at' line showed up before the mouse moved: $(last_at)"
MOUSE_PATH="$(grep -a 'terminal: pointer> open ' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*open ([^ ]+) .*/\1/')"
echo "boot mouse: ${MOUSE_PATH}"

# ── 검사 7: 움직이기 전에는 화살표가 없다 ─────────────────────────────
#
# 보이는 조건 2(PD design 결정 4). 장치가 열려 있어도 움직이거나 누르기
# 전에는 안 그린다. 그래서 포인터 장치를 가진 체인도 사람이 손대기 전의
# 화면은 포인터 없는 부팅과 같다. 처음부터 그리면(mutation 1) 첫 프레임이
# 가운데(640, 400)에 화살표를 얹고 여기서 그 픽셀이 세어진다.
#
# pane> 줄이 포인터 없는 부팅의 그것과 글자까지 같은 것도 본다 — 그 값은
# pane/check.sh 검사 1과 PD-M0 plan 확정 3이 본 것이다.
echo "=== before any move: no arrow on the screen ==="
SCREENS_BEFORE_MOVES="$(screen_lines)"
screendump "$BEFORE" || report_failure "screendump did not write ${BEFORE}"
PIX="$(ppm_arrow "$BEFORE")"
[ "$PIX" -eq 0 ] ||
  report_failure "the screen has ${PIX} arrow-colored pixels before the mouse moved; the arrow must wait for the first move"
PANE_LINE="$(grep -a 'terminal: pane> ws=' "$LOG" | tail -n 1 | tr -d '\r')"
[ "$PANE_LINE" = "terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 sep ink=0" ] ||
  report_failure "the pane> line is '${PANE_LINE}', not the one a boot without a mouse prints"
echo "no arrow yet: ${PIX} arrow pixels on the screen"

# ── 검사 2 · 8: 움직이면 화살표가 나타나고, 옛 자리는 깨끗하다 ─────────
#
# 출발이 가운데(640, 400)라서 10, 5를 밀면 650, 405다. 첫 움직임에 화살표가
# 다 보인다 — ink가 118이다.
#
# 둘째 움직임은 50, 50이다. 화살표가 19픽셀 높이라 두 사각형이 안 겹친다.
# save-under가 옛 자리를 되돌리지 않으면(mutation 2) 옛 화살표가 남아 ink가
# 236이 된다. 그리고 screendump로 같은 것을 한 번 더 본다 — 움직이기 전
# 화면과 다른 픽셀이 정확히 화살표 118개이고, 전부 700,455의 12 × 19 안이다.
# at 줄은 terminal의 되읽기라 present가 빠져도 맞지만, screendump는 present가
# 있어야 바뀐다.
echo "=== mouse_move 10 5: the arrow shows up ==="
hmp "mouse_move 10 5"
wait_for_at "^terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'mouse_move 10 5' the last at line is '$(last_at)', expected 'at x=650 y=405 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}' (start 640,400)"
echo "moved: $(last_at)"

echo "=== mouse_move 50 50: the old spot is clean ==="
hmp "mouse_move 50 50"
wait_for_at '^terminal: pointer> at x=700 y=455 ' ||
  report_failure "after 'mouse_move 50 50' the last at line is '$(last_at)', expected x=700 y=455"
[ "$(last_at)" = "terminal: pointer> at x=700 y=455 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "after the second move the at line is '$(last_at)'; ink must stay ${ARROW_INK} (more means the old arrow was left behind)"
screendump "$MOVED" || report_failure "screendump did not write ${MOVED}"
DIFF="$(ppm_diff "$BEFORE" "$MOVED")"
[ "$DIFF" = "n=${ARROW_INK} box=700,455 711,473 other=0" ] ||
  report_failure "the screen after two moves differs from the one before them by '${DIFF}', expected 'n=${ARROW_INK} box=700,455 711,473 other=0' (the arrow alone, at 700,455)"
echo "moved again: $(last_at)"
echo "screen diff: ${DIFF}"

# ── 검사 3: 버튼 ──────────────────────────────────────────────────────
#
# HMP mouse_button의 비트(1 왼쪽)가 buttons=의 비트와 같다. 누름 뒤 뗌까지 본다 —
# 누름만 보면 "버튼이 영영 눌린 채"도 통과한다. 자리가 안 바뀌므로 화살표는
# 그대로다.
echo "=== mouse_button 1, then 0 ==="
hmp "mouse_button 1"
wait_for_at "^terminal: pointer> at x=700 y=455 buttons=1 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'mouse_button 1' the last at line is '$(last_at)', expected buttons=1 at 700,455 with the arrow shown"
hmp "mouse_button 0"
wait_for_at "^terminal: pointer> at x=700 y=455 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'mouse_button 0' the last at line is '$(last_at)', expected buttons=0"
echo "button: pressed and released"

# ── 검사 5 · 10: 좌표는 화면 밖으로 안 나가고, 화살표는 가장자리에서 잘린다 ──
#
# 왼쪽 위로 800씩 밀면 0, 0에 붙는다. 화살표는 오른쪽 아래로 뻗으므로 다
# 보인다. 오른쪽 아래로 1300씩 밀면 1279, 799다. 그 자리에서는 hotspot 한
# 픽셀만 화면 안에 남는다 — ink=1이다. 자르기가 없으면 프레임버퍼 밖에 써서
# 게스트가 죽는다(setPixel에 범위 검사가 없다).
echo "=== clamp to the top left and the bottom right ==="
for _ in $(seq 1 8); do hmp "mouse_move -100 -100"; done
wait_for_at "^terminal: pointer> at x=0 y=0 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after eight 'mouse_move -100 -100' the last at line is '$(last_at)', expected x=0 y=0 with the whole arrow"
for _ in $(seq 1 13); do hmp "mouse_move 100 100"; done
wait_for_at '^terminal: pointer> at x=1279 y=799 ' ||
  report_failure "after thirteen 'mouse_move 100 100' the last at line is '$(last_at)', expected x=1279 y=799"
[ "$(last_at)" = "terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1" ] ||
  report_failure "at the bottom right corner the at line is '$(last_at)'; only the tip pixel fits, so ink must be 1"
echo "clamped: $(last_at)"

# ── 검사 7의 둘째: 움직임만으로는 화면 전체를 다시 그리지 않는다 ───────
#
# 여기까지 포인터만 움직였다. save-under는 화살표 자리만 고치고 present한다
# (PD design 결정 4). 화면 전체를 다시 그리면 screen> 줄이 는다.
echo "=== moves alone do not render a frame ==="
[ "$(screen_lines)" -eq "$SCREENS_BEFORE_MOVES" ] ||
  report_failure "pointer moves made the terminal render whole frames (screen> ${SCREENS_BEFORE_MOVES} -> $(screen_lines)); a move alone must only touch the arrow"
echo "no frame: screen> stayed at ${SCREENS_BEFORE_MOVES} across $(pointer_count 'at ') at lines"

# ── 검사 6: 부팅 뒤에 꽂고 뺀다 ───────────────────────────────────────
#
# 꽂으면 커널 uevent(`add` · `DEVNAME=input/event3`)가 오고 terminal이 둘째
# open을 찍는다. 화살표가 오른쪽 아래 끝에 보이는 중이라 그 줄은 shown=1이다.
# 커널 줄을 함께 세는 것은 "QEMU · 커널이 마우스를 안 만들었다"와 "terminal이
# 안 열었다"를 가르기 위해서다.
#
# 빼면 그 fd가 POLLHUP · POLLERR을 올리고 terminal이 close를 찍는다. 마우스가
# 하나 남으므로 화살표는 그대로다.
echo "=== device_add, then device_del ==="
KERNEL_MICE="$(kernel_mice)"
hmp "device_add usb-mouse,id=pdhot"
if ! wait_for_count pointer_count 'open ' 2; then
  if [ "$(kernel_mice)" -le "$KERNEL_MICE" ]; then
    report_failure "device_add did not give the guest a second USB mouse (kernel 'input:' lines stayed at ${KERNEL_MICE})"
  fi
  report_failure "the kernel registered a second mouse but terminal never opened it (no second 'pointer> open')"
fi
NEW_LINE="$(grep -a 'terminal: pointer> open ' "$LOG" | tail -n 1 | tr -d '\r')"
NEW_PATH="$(sed -E 's/.*open ([^ ]+) .*/\1/' <<<"$NEW_LINE")"
case "$NEW_LINE" in
  *" kind=mouse shown=1 name=QEMU QEMU USB Mouse") ;;
  *) report_failure "the hotplugged device opened as '${NEW_LINE}', expected kind=mouse shown=1 (the arrow is on the screen)" ;;
esac
[ "$NEW_PATH" != "$MOUSE_PATH" ] ||
  report_failure "the hotplugged mouse reused the open path ${MOUSE_PATH}"
echo "plugged: ${NEW_LINE}"

# HMP의 대상이 새 마우스로 갔다(PD-M0 plan 확정 1). 이 움직임은 새 fd로만
# 온다. 1269, 789에서는 화살표의 왼쪽 위 11 × 11만 화면 안이다 — 66픽셀이다.
hmp "mouse_move -10 -10"
wait_for_at '^terminal: pointer> at x=1269 y=789 ' ||
  report_failure "a move on the hotplugged mouse never reached the pointer (last at: '$(last_at)')"
[ "$(last_at)" = "terminal: pointer> at x=1269 y=789 buttons=0 wheel=0 shown=1 ink=66" ] ||
  report_failure "at 1269,789 the at line is '$(last_at)'; the arrow's top left 11 x 11 holds 66 arrow pixels"

hmp "device_del pdhot"
wait_for_log "terminal: pointer> close ${NEW_PATH}" ||
  report_failure "the unplugged mouse was never closed (no 'pointer> close ${NEW_PATH}')"
[ "$(pointer_count 'close ')" -eq 1 ] ||
  report_failure "expected one 'pointer> close', got $(pointer_count 'close ')"
echo "unplugged: $(grep -a 'terminal: pointer> close ' "$LOG" | tail -n 1 | tr -d '\r')"

# 대상이 원래 마우스로 돌아왔다. 그 fd가 아직 열려 있고 읽힌다.
hmp "mouse_move 10 10"
wait_for_at "^terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1\$" ||
  report_failure "the boot mouse stopped moving the pointer after the unplug (last at: '$(last_at)')"

# ── 검사 9: 키를 치면 화살표가 숨는다 ─────────────────────────────────
#
# 보이는 조건 3(PD design 결정 4). PTY로 바이트가 나간 회차에 숨는다. 그
# 회차에는 포인터 이벤트가 없지만 숨은 회차라서 at 줄이 한 번 찍힌다
# (main.zig의 dumpPointerAt). ink=0은 옛 자리를 되돌렸다는 뜻이다.
#
# 패널 가운데쯤(679, 499)으로 옮긴 뒤 친다. echo의 출력이 오는 것은 빠진
# 장치 뒤에도 키보드와 PTY가 돈다는 것이기도 하다(검사 6의 마지막 확인).
echo "=== typing hides the arrow ==="
for _ in $(seq 1 6); do hmp "mouse_move -100 -50"; done
wait_for_at "^terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after six 'mouse_move -100 -50' the last at line is '$(last_at)', expected x=679 y=499 with the whole arrow"
ATS="$(pointer_count 'at ')"
type_keys e c h o spc p d minus h i d e minus o k ret
wait_for_screen '\| pd-hide-ok \|' ||
  report_failure "the shell stopped answering after the unplug (no 'pd-hide-ok' output line)"
[ "$(last_at)" = "terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=0 ink=0" ] ||
  report_failure "after typing the last at line is '$(last_at)', expected 'at x=679 y=499 buttons=0 wheel=0 shown=0 ink=0'"
[ "$(pointer_count 'at ')" -eq "$((ATS + 1))" ] ||
  report_failure "typing printed $(( $(pointer_count 'at ') - ATS )) at lines, expected exactly one (the round that hid the arrow)"
screendump "$HIDDEN" || report_failure "screendump did not write ${HIDDEN}"
PIX="$(ppm_arrow "$HIDDEN")"
[ "$PIX" -eq 0 ] ||
  report_failure "the screen still has ${PIX} arrow-colored pixels after typing"
echo "hidden: $(last_at)"

hmp "mouse_move 1 1"
wait_for_at "^terminal: pointer> at x=680 y=500 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "the next move did not bring the arrow back (last at: '$(last_at)')"
echo "shown again: $(last_at)"

# ── 검사 11: 휠은 포인터 아래 패널을 세 줄씩 움직인다 ──────────────────
#
# seq 200으로 스크롤백을 만든다. 바닥에 있으므로 offset은 total - len이다.
# 휠을 앞으로 한 눈금 밀면(REL_WHEEL +1) 위로 세 줄 — offset이 3 준다. 뒤로
# 한 눈금이면 되돌아온다. 휠 부호를 뒤집으면(mutation 3) 바닥에서 아래로
# 가려 하므로 offset이 그대로다. REL_WHEEL_HI_RES도 세면(mutation 4) 한
# 눈금이 120을 넘게 더해져 맨 위까지 간다.
#
# 뷰포트가 바뀌므로 그 회차는 화면 전체를 다시 그린다. at 줄은 덤프들
# 뒤에 찍히므로, 새 at 줄이 보이면 같은 프레임의 scroll> 줄은 이미 있다.
echo "=== wheel over the pane ==="
type_keys s e q spc 2 0 0 ret
wait_for_screen '\| 200 \| root@\(none\) ~#' ||
  report_failure "seq 200 did not finish (no '| 200 | root@(none) ~#' on the screen)"
sleep 1
hmp "mouse_move -1 -1"
wait_for_at "^terminal: pointer> at x=679 y=499 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "the move after seq 200 did not show the arrow (last at: '$(last_at)')"
OFF0="$(scroll_field offset)"
[ "$OFF0" -ge 3 ] ||
  report_failure "seq 200 left no scrollback to wheel through (scroll> offset=${OFF0})"

ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch up printed no at line (last at: '$(last_at)')"
OFF1="$(scroll_field offset)"
[ "$OFF1" -eq "$((OFF0 - 3))" ] ||
  report_failure "one wheel notch up moved the viewport from offset ${OFF0} to ${OFF1}, expected $((OFF0 - 3))"
[ "$(last_at)" = "terminal: pointer> at x=679 y=499 buttons=0 wheel=1 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "after a wheel notch up the at line is '$(last_at)', expected wheel=1 with the arrow redrawn on the new frame"

ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 -1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch down printed no at line (last at: '$(last_at)')"
OFF2="$(scroll_field offset)"
[ "$OFF2" -eq "$OFF0" ] ||
  report_failure "one wheel notch down moved the viewport from offset ${OFF1} to ${OFF2}, expected back to ${OFF0}"
[ "$(last_at)" = "terminal: pointer> at x=679 y=499 buttons=0 wheel=-1 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "after a wheel notch down the at line is '$(last_at)', expected wheel=-1"
echo "wheel: offset ${OFF0} -> ${OFF1} -> ${OFF2}"

# ── 검사 11의 둘째: 키보드 copy mode인 패널에서는 휠을 무시한다 ─────────
#
# copy 커서는 뷰포트 좌표다(PD design 결정 7). 밖에서 뷰포트를 밀면 커서가
# 다른 글자를 가리키는데 선택은 안 따라온다. 그래서 그 패널은 안 움직인다 —
# offset이 그대로이고 화면을 다시 그리지도 않는다. 새 at 줄이 보이면 그
# 회차의 프레임(있었다면)은 이미 찍혔다.
echo "=== wheel in keyboard copy mode is ignored ==="
type_keys meta_l-shift-c
wait_for_log 'terminal: copy> enter' ||
  report_failure "Cmd+Shift+C did not enter copy mode (no 'copy> enter')"
sleep 1
OFF_C="$(scroll_field offset)"
SCREENS_C="$(screen_lines)"
ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch in copy mode printed no at line (last at: '$(last_at)')"
[ "$(scroll_field offset)" -eq "$OFF_C" ] ||
  report_failure "the wheel moved a pane in keyboard copy mode (offset ${OFF_C} -> $(scroll_field offset))"
[ "$(screen_lines)" -eq "$SCREENS_C" ] ||
  report_failure "the wheel in keyboard copy mode rendered a frame (screen> ${SCREENS_C} -> $(screen_lines))"
type_keys esc
wait_for_log 'terminal: copy> exit' ||
  report_failure "Esc did not leave copy mode (no 'copy> exit')"
echo "copy mode: offset stayed at ${OFF_C}"

# ── 검사 12: 여백 위의 휠은 아무 일도 안 한다 ─────────────────────────
#
# 위 여백(y < 20)으로 옮긴다. 그 픽셀은 어느 격자 칸도 아니라(gridCell이
# null) 휠이 갈 패널이 없다. offset도 screen> 줄 수도 그대로다. 스크롤백이
# 있고 바닥이라 잘못 움직이면 offset이 준다.
echo "=== wheel over the margin does nothing ==="
for _ in $(seq 1 5); do hmp "mouse_move 0 -100"; done
wait_for_at "^terminal: pointer> at x=679 y=0 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after five 'mouse_move 0 -100' the last at line is '$(last_at)', expected x=679 y=0"
OFF_M="$(scroll_field offset)"
SCREENS_M="$(screen_lines)"
ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch over the margin printed no at line (last at: '$(last_at)')"
[ "$(last_at)" = "terminal: pointer> at x=679 y=0 buttons=0 wheel=1 shown=1 ink=${ARROW_INK}" ] ||
  report_failure "over the margin the at line is '$(last_at)', expected wheel=1 at 679,0"
[ "$(scroll_field offset)" -eq "$OFF_M" ] ||
  report_failure "a wheel notch over the margin moved the viewport (offset ${OFF_M} -> $(scroll_field offset))"
[ "$(screen_lines)" -eq "$SCREENS_M" ] ||
  report_failure "a wheel notch over the margin rendered a frame (screen> ${SCREENS_M} -> $(screen_lines))"
echo "margin: offset stayed at ${OFF_M}"

# ── 검사 9의 둘째: 마지막 장치가 빠지면 숨는다 ────────────────────────
#
# 보이는 조건 1. 부팅 마우스를 뺀다. 그 회차에는 포인터 이벤트가 없지만
# 숨은 회차라서 at 줄이 한 번 찍힌다.
echo "=== the last mouse goes away ==="
hmp "device_del pdboot"
wait_for_log "terminal: pointer> close ${MOUSE_PATH}" ||
  report_failure "the boot mouse was never closed (no 'pointer> close ${MOUSE_PATH}')"
wait_for_at "^terminal: pointer> at x=679 y=0 buttons=0 wheel=0 shown=0 ink=0\$" ||
  report_failure "after the last mouse went away the last at line is '$(last_at)', expected shown=0 ink=0"
screendump "$GONE" || report_failure "screendump did not write ${GONE}"
PIX="$(ppm_arrow "$GONE")"
[ "$PIX" -eq 0 ] ||
  report_failure "the screen still has ${PIX} arrow-colored pixels after the last mouse went away"
echo "gone: $(last_at)"

# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "pointer> lines:"
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'
echo "PD-M1 check PASS"
