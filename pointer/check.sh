#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# PD 체인 — 포인터 장치(PD-M0~M4). 열아홉번째 체인.
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
#   → 다른 패널을 누르면 포커스가 그리로 간다. 여백 · 구분선은 아무 일도 없다(PD-M2)
#   → 글자 위를 누르고 끌면 copy mode의 선택이 늘어나고, 떼면 클립보드에
#     들어간다. 입력 모드도 함께 돌아와 그다음 친 글자가 셸에 간다(PD-M2)
#   → 커널에 노트북 터치패드의 세 경로(PS/2 · SMBus · I2C-HID)와 uinput이
#     켜져 있고 드라이버가 등록됐다(PD-M3, 부팅 전과 부팅 B)
#   → psmouse가 QEMU의 PS/2 마우스를 잡고 terminal이 그것을 마우스로 연다(부팅 B)
#   → 설정 디스크의 tp-replay가 uinput으로 터치패드를 만들면 terminal이 터치패드로
#     열고, 한 손가락 이동 · 탭 · 두 손가락 세로가 포인터 이동 · 클릭 · 휠이 된다
#     (부팅 B)
#   → 자식이 마우스 모드를 켜면 누름 · 끎 · 뗌 · 휠이 우리 선택 대신 그 자식의
#     PTY에 보고로 간다. Shift를 누르면 우리 것이고, 대체 화면의 휠은 화살표
#     키가 된다. vim이 시스템 vimrc의 mouse=a로 클릭을 받는다(PD-M4, 부팅 B)
#
# 부팅이 둘이다. 부팅 A(PD-M0~M2)는 USB 마우스 하나만 보도록 커널 cmdline에
# i8042.noaux를 준다 — PD-M3부터 커널이 PS/2 마우스를 알아서, 그것이 없으면
# 검사 1의 "정확히 하나"와 검사 9의 둘째("마지막 장치가 빠지면 숨는다")가 PS/2
# 마우스 때문에 성립하지 않는다(PD-M3 plan 확정 9). 부팅 B(PD-M3)는 cmdline을
# 그대로 두고 설정 디스크를 물린다.
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
#   scroll> 줄 — 휠이 움직인 뷰포트(검사 11 · 12 · 16의 둘째).
#   press · release 줄과 copy> · clip> · pane> 줄 — 누름이 어느 잎의 어느 칸에
#                닿았는지, 선택이 어디서 어디까지인지, 클립보드에 무엇이
#                들어갔는지, 포커스가 어디인지(검사 13~18). copy> · clip>은
#                키보드의 copy mode가 찍는 것과 같은 줄이라 copy 체인의 수법을
#                그대로 쓴다.
#   report 줄과 프로브의 화면 줄 — terminal이 자식에게 보낸 바이트(report 줄,
#                cat -v 모양)와 자식이 실제로 읽은 바이트(설정 디스크의
#                /config/pd/mouse가 cat -v로 찍은 화면 줄)를 같은 글자로 본다
#                (검사 26~32).
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

# 열여덟 체인이 45455~45487을 쓴다. 45489는 부팅 B의 몫이다(design 결정 10).
MONITOR_PORT=45488
MONITOR_PORT_B=45489

REPO_ROOT="$(cd .. && pwd)"

# 부팅 B의 되감기 도구(PD-M3). 제품이 아니라 게이트 전용이라 initrd가 아니라
# 설정 디스크에 싣는다(design 결정 10, wifi 체인의 hostapd와 같은 이유). 산출물과
# 캐시를 out/ 아래에 두므로 .gitignore도 clean()도 고칠 일이 없다.
REPLAY_OUT="${REPO_ROOT}/out/pd-replay"
if ! (cd replay && zig build --prefix "$REPLAY_OUT" --cache-dir "${REPLAY_OUT}/cache"); then
  echo "FAIL: tp-replay build failed"
  exit 1
fi
REPLAY="${REPLAY_OUT}/bin/tp-replay"
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
    "terminal: pointer> press" \
    "terminal: pointer> release" \
    "terminal: clip> len=" \
    "terminal: pane> ws=1/1 panes=2" \
    "terminal: pointer> uevent failed" \
    "terminal: pointer> scan failed" \
    "kind=touchpad" \
    "tp-replay:" \
    "terminal: pointer> report" \
    "pd-mouse-ready" \
    "pd-mouse-got"; do
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

# ── PD-M2의 도구 ──────────────────────────────────────────────────────

# 마지막 press · release 줄.
last_press() {
  grep -a 'terminal: pointer> press ' "$LOG" | tail -n 1 | tr -d '\r'
}

last_release() {
  grep -a 'terminal: pointer> release ' "$LOG" | tail -n 1 | tr -d '\r'
}

# copy> 줄 중 동사가 맞는 것의 개수(`enter` · `point` · `exit` · `yank`).
copy_lines() {
  grep -ac "terminal: copy> $1" "$LOG" || true
}

# 클립보드에 넣은 횟수와 마지막 줄. 붙여넣기 줄(`clip> paste`)은 안 센다.
clip_lines() {
  grep -ac 'terminal: clip> len=' "$LOG" || true
}

last_clip() {
  grep -a 'terminal: clip> len=' "$LOG" | tail -n 1 | tr -d '\r'
}

# 12바이트 붙여넣기의 횟수(검사 15의 둘째). 클립보드는 pd-drag-word다.
paste_lines() {
  grep -ac 'terminal: clip> paste len=12 ' "$LOG" || true
}

# 마지막 배치 줄과 그 개수(pane/check.sh의 last_pane_line과 같다).
last_pane_line() {
  grep -a 'terminal: pane> ws=' "$LOG" | tail -n 1 | tr -d '\r'
}

pane_lines() {
  grep -ac 'terminal: pane> ws=' "$LOG" || true
}

# 마지막 배치 줄이 패턴(ERE)에 맞을 때까지 기다린다. 15초.
wait_for_pane() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if grep -aqE -- "$pattern" <<<"$(last_pane_line)"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 마지막 상태 줄의 글자(copy/check.sh의 status_text와 같다).
status_text() {
  grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*text=//'
}

# 상태 줄 꼬리가 `  COPY`가 될 때까지(인자 on) 또는 아닐 때까지(off) 기다린다.
wait_for_status_copy() {
  local want="$1" i text
  for i in $(seq 1 150); do
    text="$(status_text)"
    case "$text" in
      *"  COPY") [ "$want" = on ] && return 0 ;;
      *) [ "$want" = off ] && return 0 ;;
    esac
    sleep 0.1
  done
  return 1
}

# 마지막 프레임(마지막 screen>부터 끝까지, copy/check.sh의 last_frame과 같다).
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

# 마지막 screen> 줄에서 글자가 정확히 $1인 행의 번호(0부터). 여럿이면 가장
# 아래 것, 없으면 -1이다. screen>은 포커스 패널의 행을 ' | '로 잇고(main.zig의
# dumpScreen) 행이 바뀔 때마다 구분자가 하나씩 붙으므로 구간의 번호가 곧 행
# 번호다. 행은 패널 안의 상대 행이다 — 세로 분할의 두 패널은 격자의 0행에서
# 시작하므로 격자의 행과 같다.
screen_row() {
  grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' |
    WANT="$1" perl -ne 's/^.*?terminal: screen> //; chomp; my @r = split / \| /, $_, -1;
      my $i = -1; for my $k (0 .. $#r) { $i = $k if $r[$k] eq $ENV{WANT} } print "$i\n";'
}

# 포인터를 (X, Y)로 옮긴다. 마지막 at 줄의 자리에서 상대 이동을 100 이하씩
# 나눠 보내고 그 자리의 at 줄을 기다린다. 버튼을 누른 채 부르면 그것이 곧
# 끌기다 — 나눈 이동마다 선택 끝이 따라온다.
move_to() {
  local tx="$1" ty="$2" line cx cy dx dy sx sy
  line="$(last_at)"
  cx="$(sed -E 's/.* x=([0-9]+) .*/\1/' <<<"$line")"
  cy="$(sed -E 's/.* y=([0-9]+) .*/\1/' <<<"$line")"
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

# 왼쪽 버튼을 누른다 · 뗀다. 그 줄(press · release)이 하나 늘 때까지 기다린다.
#
# 누름의 일(포커스 옮김 · copy mode 닫기)은 그 줄을 찍은 회차 안에서 끝나고,
# 화면이 바뀌었으면 같은 회차 끝에 프레임(pane> 등)이 찍힌다. 그래서 뗌의 줄이
# 보이면 누름 회차의 프레임은 이미 로그에 있다.
button_down() {
  local n
  n="$(pointer_count 'press ')"
  hmp "mouse_button 1"
  wait_for_count pointer_count 'press ' "$((n + 1))"
}

button_up() {
  local n
  n="$(pointer_count 'release ')"
  hmp "mouse_button 0"
  wait_for_count pointer_count 'release ' "$((n + 1))"
}

# 격자 칸의 왼쪽 위 끝 픽셀(PD design 결정 5). 격자는 (20, 20)에서 시작하고
# 칸은 8 × 16이다(main.zig의 GRID_X · GRID_Y · CELL_W · ROW_HEIGHT). 오른쪽 아래
# 끝 픽셀은 여기에 7 · 15를 더한다.
cell_x() { echo $((20 + 8 * $1)); }
cell_y() { echo $((20 + 16 * $1)); }

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

# ── 검사 19: 커널이 노트북 터치패드의 세 경로를 안다 (부팅 없음) ────────
#
# QEMU에는 터치패드가 없다(design 실측 7). 그래서 실칩 드라이버는 세 겹으로
# 본다(design 결정 9) — 여기서 심볼과 커널의 장치 표(modinfo alias)를, 부팅 B에서
# 드라이버가 실제로 등록됐는지를. 심볼은 켜졌는데 의존 관계로 빌드에서 빠진
# 경우를 셋째 겹이 잡는다. 켜지 않기로 한 것(Apple 쪽 · mousedev)도 본다.
CONFIG=../kernel/.config
for sym in INPUT_MOUSE MOUSE_PS2 MOUSE_PS2_SYNAPTICS MOUSE_PS2_SYNAPTICS_SMBUS MOUSE_PS2_ELANTECH \
  MOUSE_PS2_ELANTECH_SMBUS MOUSE_PS2_ALPS MOUSE_PS2_FOCALTECH MOUSE_PS2_TRACKPOINT \
  RMI4_CORE RMI4_SMB RMI4_F03 RMI4_F11 RMI4_F12 RMI4_F30 RMI4_F3A I2C_I801 \
  MOUSE_ELAN_I2C MOUSE_ELAN_I2C_I2C MOUSE_ELAN_I2C_SMBUS \
  I2C_HID_ACPI HID_MULTITOUCH I2C_DESIGNWARE_CORE I2C_DESIGNWARE_PLATFORM \
  MFD_INTEL_LPSS_PCI MFD_INTEL_LPSS_ACPI X86_INTEL_LPSS X86_AMD_PLATFORM_DEVICE \
  PINCTRL_AMD PINCTRL_INTEL_PLATFORM PINCTRL_SUNRISEPOINT PINCTRL_CANNONLAKE PINCTRL_ICELAKE \
  PINCTRL_TIGERLAKE PINCTRL_ALDERLAKE PINCTRL_METEORLAKE PINCTRL_JASPERLAKE PINCTRL_GEMINILAKE \
  PINCTRL_BROXTON PINCTRL_BAYTRAIL PINCTRL_CHERRYVIEW PINCTRL_LYNXPOINT \
  INTEL_THC_HID INTEL_QUICKI2C INPUT_MISC INPUT_UINPUT; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
for sym in HID_APPLE HID_MAGICMOUSE MOUSE_BCM5974 KEYBOARD_APPLESPI INPUT_MOUSEDEV; do
  if grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is =y in kernel/.config, PD design 결정 9 leaves it off"
    exit 1
  fi
done
# 커널이 장치 ID를 드라이버에 잇는 표. 경로마다 대표 하나다(PD-M3 plan 확정 4가
# modules.builtin.modinfo에서 뽑은 글자). modinfo는 NUL로 나뉜 파일이다.
MODINFO=../kernel/build/modules.builtin.modinfo
for alias in i2c_hid_acpi.alias=acpi*:PNP0C50:* hid_multitouch.alias=hid:b*g0004v*p* \
  elan_i2c.alias=acpi*:ELAN0000:* rmi_smbus.alias=i2c:rmi4_smbus \
  intel_lpss_pci.alias=pci:v00008086d00009D60sv*sd*bc*sc*i* pinctrl_tigerlake.alias=acpi*:INT34C5:* \
  pinctrl_amd.alias=acpi*:AMD0030:* intel_quicki2c.alias=pci:v00008086d0000A848sv*sd*bc*sc*i*; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -xF "$alias" >/dev/null; then
    echo "FAIL: the kernel has no '${alias}' entry in modules.builtin.modinfo"
    exit 1
  fi
done
echo "the kernel carries the PS/2, SMBus and I2C-HID touchpad paths and uinput, and no Apple input drivers"

# 부팅 A — USB 마우스 하나(PD-M0~M2). i8042.noaux가 PS/2 마우스 포트를 끈다 —
# 위의 머리 주석과 PD-M3 plan 확정 9. 검사 1의 "정확히 하나"가 그것이 먹혔다는 것도
# 함께 본다(PS/2 마우스가 생기면 open이 둘이다).
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0 i8042.noaux" \
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

# ── PD-M2: 누름 · 끎 · 뗌 ──────────────────────────────────────────────
#
# 패널을 둘로 가르고 시작한다. 0 | 1이고 왼쪽은 0,0 77x47, 구분선이 77열,
# 오른쪽은 78,0 77x47이다(WP). 칸의 픽셀은 cell_x · cell_y로 셈한다 — 77열은
# x 636~643, 76열은 628~635, 78열은 644~651이다. 행 10은 y 180~195다.
#
# 포커스는 새 패널(1)에 있다. 검사 14를 먼저 하는 이유는 mutation 1이다 — hit이
# 구분선 칸을 왼쪽 잎에 넣으면 포커스가 0으로 간다. 포커스가 이미 0이면 그
# 고장이 안 보인다.
echo "=== Cmd+D: two panes for the click checks ==="
type_keys meta_l-d
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "Cmd+D did not give 'panes=2 focus=1 rect=78,0 77x47' (last pane> line: '$(last_pane_line)')"
CLIPS_BEFORE="$(clip_lines)"
ENTERS_BEFORE="$(copy_lines enter)"

# ── 검사 14: 구분선 칸을 누르면 아무 일도 없다 ────────────────────────
#
# 구분선 칸은 어느 잎의 사각형에도 안 든다(layout.Tree.hit의 null). 칸의 왼쪽
# 위 끝 픽셀과 오른쪽 아래 끝 픽셀을 둘 다 누른다 — 픽셀 → 칸 변환이 한 칸
# 어긋나면 한쪽 끝이 이웃 패널의 칸이 된다(PD design 결정 5). 포커스도
# 안 바뀌고 pane> 줄도 안 는다.
echo "=== a press on the separator does nothing ==="
PANES_N="$(pane_lines)"
for spot in "$(cell_x 77) $(cell_y 10)" "$(( $(cell_x 77) + 7 )) $(( $(cell_y 10) + 15 ))"; do
  read -r SX SY <<<"$spot"
  move_to "$SX" "$SY" ||
    report_failure "the pointer did not reach ${SX},${SY} (last at: '$(last_at)')"
  button_down || report_failure "mouse_button 1 at ${SX},${SY} printed no 'pointer> press' line"
  [ "$(last_press)" = "terminal: pointer> press none" ] ||
    report_failure "a press on the separator pixel ${SX},${SY} printed '$(last_press)', expected 'pointer> press none'"
  button_up || report_failure "mouse_button 0 at ${SX},${SY} printed no 'pointer> release' line"
  [ "$(last_release)" = "terminal: pointer> release drag=0" ] ||
    report_failure "the release on the separator printed '$(last_release)', expected 'release drag=0'"
done
[ "$(pane_lines)" -eq "$PANES_N" ] ||
  report_failure "a press on the separator changed the panes (pane> ${PANES_N} -> $(pane_lines) lines, last: '$(last_pane_line)')"
echo "separator: two presses, $(last_pane_line)"

# ── 검사 13: 다른 패널을 누르면 포커스가 그리로 간다 ───────────────────
#
# 왼쪽 패널의 마지막 열(76) 칸의 오른쪽 아래 끝 픽셀(635, 195), 그다음 오른쪽
# 패널의 첫 열(78) 칸의 왼쪽 위 끝 픽셀(644, 180). 구분선을 사이에 둔 두 픽셀이
# 서로 다른 잎의 경계 칸이 된다. 클릭이라 클립보드도 copy mode도 안 움직인다.
echo "=== a press on another pane moves the focus there ==="
move_to "$(( $(cell_x 76) + 7 ))" "$(( $(cell_y 10) + 15 ))" ||
  report_failure "the pointer did not reach the left pane's last cell (last at: '$(last_at)')"
button_down || report_failure "mouse_button 1 on the left pane printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=10 col=76" ] ||
  report_failure "a press on pixel 635,195 printed '$(last_press)', expected 'press leaf=0 row=10 col=76'"
button_up || report_failure "mouse_button 0 on the left pane printed no 'pointer> release' line"
[ "$(last_release)" = "terminal: pointer> release drag=0" ] ||
  report_failure "the click on the left pane released as '$(last_release)', expected 'release drag=0'"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' ||
  report_failure "a click on the left pane did not move the focus (last pane> line: '$(last_pane_line)')"
echo "focus left: $(last_pane_line)"

move_to "$(cell_x 78)" "$(cell_y 10)" ||
  report_failure "the pointer did not reach the right pane's first cell (last at: '$(last_at)')"
button_down || report_failure "mouse_button 1 on the right pane printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=1 row=10 col=0" ] ||
  report_failure "a press on pixel 644,180 printed '$(last_press)', expected 'press leaf=1 row=10 col=0'"
button_up || report_failure "mouse_button 0 on the right pane printed no 'pointer> release' line"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "a click on the right pane did not move the focus back (last pane> line: '$(last_pane_line)')"
[ "$(clip_lines)" -eq "$CLIPS_BEFORE" ] ||
  report_failure "a click put something on the clipboard: '$(last_clip)'"
[ "$(copy_lines enter)" -eq "$ENTERS_BEFORE" ] ||
  report_failure "a click entered copy mode (copy> enter ${ENTERS_BEFORE} -> $(copy_lines enter))"
echo "focus right: $(last_pane_line)"

# ── 검사 15: 글자 위를 누르고 끌어 떼면 그 글자가 클립보드에 들어간다 ──
#
# 오른쪽 패널(포커스)에 pd-drag-word를 찍고 그 줄의 0열을 누른다. 누름에서는
# copy mode에 안 들어간다(design 결정 6). 0.5초를 기다려 copy> enter가 안 는
# 것을 본다 — 누름의 일은 press 줄과 같은 회차에 끝나므로 그 사이에 찍혔다면
# 이미 로그에 있다.
#
# 11열(d) 칸의 오른쪽 아래 끝 픽셀로 한 번에 끈다. 첫 칸 이동에 들어가므로
# copy> enter(누른 칸)와 copy> point(지금 칸)가 함께 찍히고, 상태 줄 꼬리에
# COPY가 뜬다. 떼면 clip> 줄이 키보드의 y와 같은 모양으로 찍힌다.
#
# 판정은 clip> 줄이라 화면 에코와 상관없다(project_gate_screen_echo).
echo "=== press, drag, release copies the word ==="
type_keys e c h o spc p d minus d r a g minus w o r d ret
wait_for_screen '\| pd-drag-word \|' ||
  report_failure "the right pane's shell did not print pd-drag-word"
ROW="$(screen_row pd-drag-word)"
[ "$ROW" -ge 0 ] ||
  report_failure "pd-drag-word is not a row of its own on the last screen: $(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"
PX="$(cell_x 78)"
PY="$(cell_y "$ROW")"
move_to "$PX" "$PY" ||
  report_failure "the pointer did not reach the p of pd-drag-word at ${PX},${PY} (last at: '$(last_at)')"
ENTERS="$(copy_lines enter)"
CLIPS="$(clip_lines)"
button_down || report_failure "mouse_button 1 on pd-drag-word printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=1 row=${ROW} col=0" ] ||
  report_failure "the press on pd-drag-word printed '$(last_press)', expected 'press leaf=1 row=${ROW} col=0'"
sleep 0.5
[ "$(copy_lines enter)" -eq "$ENTERS" ] ||
  report_failure "the press alone entered copy mode; it must wait for the first move to another cell"
hmp "mouse_move 95 15"
wait_for_count copy_lines enter "$((ENTERS + 1))" ||
  report_failure "dragging to the next cells did not enter copy mode (no new 'copy> enter')"
wait_for_log "terminal: copy> point row=${ROW} col=11" ||
  report_failure "the drag did not move the selection end to row ${ROW} col 11 (last copy> line: '$(grep -a 'terminal: copy>' "$LOG" | tail -n 1 | tr -d '\r')')"
[ "$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')" = "terminal: copy> enter row=${ROW} col=0" ] ||
  report_failure "the drag entered copy mode at '$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')', expected the pressed cell row=${ROW} col=0"
wait_for_status_copy on ||
  report_failure "while dragging the status line reads '$(status_text)', expected it to end with '  COPY'"
button_up || report_failure "mouse_button 0 after the drag printed no 'pointer> release' line"
[ "$(last_release)" = "terminal: pointer> release drag=1" ] ||
  report_failure "the release after the drag printed '$(last_release)', expected 'release drag=1'"
wait_for_count clip_lines '' "$((CLIPS + 1))" ||
  report_failure "the release after the drag put nothing on the clipboard (no new 'clip> len=' line)"
[ "$(last_clip)" = "terminal: clip> len=12 text=pd-drag-word" ] ||
  report_failure "the drag copied '$(last_clip)', expected 'clip> len=12 text=pd-drag-word'"
wait_for_status_copy off ||
  report_failure "after the release the status line still reads '$(status_text)'; the release leaves copy mode"
echo "dragged: $(last_clip)"

# ── 검사 18: 끌어 복사한 직후 친 글자가 셸에 간다 ──────────────────────
#
# 모드의 두 사본(input.State.mode와 vt.Screen.copy_cursor)이 함께 돌아왔다는
# 것이다. 화면 쪽만 돌아오면 입력 모드가 copy에 남아 이 글자들이 copy 표에
# 삼켜진다(mutation 3). 출력 줄만 보는 패턴이라 친 명령줄과 안 겹친다.
echo "=== typing right after a drag copy reaches the shell ==="
type_keys e c h o spc p d minus a f t e r minus d r a g ret
wait_for_screen '\| pd-after-drag \|' ||
  report_failure "the keys typed right after the drag copy never reached the shell (no 'pd-after-drag' output line); the input mode must come back to normal with the screen"
echo "typed after the drag: pd-after-drag"

# ── 검사 15의 둘째: 끌어 넣은 클립보드를 Cmd+V로 붙인다 ────────────────
#
# 클립보드가 셸까지 왕복한다. 붙일 자리 앞에 got-을 쳐 두므로 출력 줄은
# got-pd-drag-word 하나뿐이다 — 명령줄(echo got-pd-drag-word)과 안 겹친다.
echo "=== Cmd+V pastes what the drag copied ==="
PASTES="$(paste_lines)"
type_keys e c h o spc g o t minus
type_keys meta_l-v
wait_for_count paste_lines '' "$((PASTES + 1))" ||
  report_failure "Cmd+V did not write the 12-byte clipboard (no new 'clip> paste len=12' line)"
type_keys ret
wait_for_screen '\| got-pd-drag-word \|' ||
  report_failure "the pasted word never ran in the shell (no 'got-pd-drag-word' output line)"
echo "pasted: got-pd-drag-word"

# ── 검사 17: 키보드 copy mode 중 클릭은 복사 없이 모드를 닫는다 ─────────
#
# 선택의 주인은 한 번에 하나다(design 결정 6의 표). 누름이 그 패널의 copy
# mode를 닫고(copy> exit) 입력 모드를 normal로 되돌린다 — 그다음 친 글자가
# 셸에 온다. 클립보드는 그대로다.
#
# 둘째는 검색 프롬프트가 열린 채다. copyExit이 findCancel까지 하므로 프롬프트도
# 닫히고, 입력 모드가 find에서 normal로 온다. 안 오면 친 글자가 검색어로 간다.
echo "=== a click in keyboard copy mode leaves it without copying ==="
CLIPS="$(clip_lines)"
ENTERS="$(copy_lines enter)"
EXITS="$(copy_lines exit)"
type_keys meta_l-shift-c
wait_for_count copy_lines enter "$((ENTERS + 1))" ||
  report_failure "Cmd+Shift+C did not enter copy mode (no new 'copy> enter')"
button_down || report_failure "mouse_button 1 in keyboard copy mode printed no 'pointer> press' line"
wait_for_count copy_lines exit "$((EXITS + 1))" ||
  report_failure "a click on a pane in keyboard copy mode did not leave copy mode (no new 'copy> exit')"
button_up || report_failure "mouse_button 0 in keyboard copy mode printed no 'pointer> release' line"
[ "$(clip_lines)" -eq "$CLIPS" ] ||
  report_failure "a click that left keyboard copy mode copied '$(last_clip)'; it must close the mode without copying"
type_keys e c h o spc p d minus c l i c k minus o u t ret
wait_for_screen '\| pd-click-out \|' ||
  report_failure "after the click left copy mode the typed keys never reached the shell (no 'pd-click-out' output line)"
echo "copy mode click: closed without copying, typing reaches the shell"

echo "=== a click with the find prompt open closes the prompt and the mode ==="
ENTERS="$(copy_lines enter)"
EXITS="$(copy_lines exit)"
type_keys meta_l-shift-c
wait_for_count copy_lines enter "$((ENTERS + 1))" ||
  report_failure "Cmd+Shift+C did not enter copy mode the second time"
type_keys slash
wait_for_log 'terminal: find> open' ||
  report_failure "/ did not open the find prompt (no 'find> open')"
type_keys q
wait_for_log 'terminal: find> type needle=q len=1' ||
  report_failure "q did not reach the find prompt (no 'find> type needle=q len=1')"
button_down || report_failure "mouse_button 1 with the find prompt open printed no 'pointer> press' line"
wait_for_count copy_lines exit "$((EXITS + 1))" ||
  report_failure "a click with the find prompt open did not leave copy mode (no new 'copy> exit')"
button_up || report_failure "mouse_button 0 with the find prompt open printed no 'pointer> release' line"
type_keys e c h o spc p d minus f i n d minus o u t ret
wait_for_screen '\| pd-find-out \|' ||
  report_failure "after the click closed the find prompt the typed keys never reached the shell (no 'pd-find-out' output line); the input mode stayed in find"
[ "$(last_frame | grep -ac 'terminal: find> overlay' || true)" -eq 0 ] ||
  report_failure "the find prompt is still drawn after the click: $(last_frame | grep -a 'terminal: find> overlay' | tr -d '\r')"
echo "find prompt click: closed, typing reaches the shell"

# ── 검사 16: 이웃 패널 위까지 끌어도 누른 패널의 마지막 열에서 멈춘다 ──
#
# 왼쪽 패널로 포커스를 옮기고 seq -s , 40을 친다. 출력은 110자라 77칸에서
# 접히고, 첫 줄이 정확히 1,2,…,28,29(77자)다 — 그 줄의 마지막 글자가 76열이다.
# 그 줄의 0열을 누르고 오른쪽 패널(x 720 = 87열) 위까지 끈다. 끄는 칸이 누른
# 패널로 잘리면 선택 끝이 76열이라 77자가 다 들어간다. 안 잘리면(mutation 4)
# 오른쪽 패널의 상대 칸(9열)이 왼쪽 패널에 적용돼 1,2,3,4,5, 열 자만 들어간다.
#
# 줄 끝 공백 트림 때문에 줄이 짧으면 76열에서 끝났는지가 안 보인다. 그래서
# 마지막 열까지 글자가 찬 줄을 쓴다.
echo "=== dragging over the neighbor pane stops at the pressed pane's last column ==="
move_to "$(cell_x 40)" "$(cell_y 20)" ||
  report_failure "the pointer did not reach the left pane (last at: '$(last_at)')"
button_down || report_failure "mouse_button 1 on the left pane printed no 'pointer> press' line"
button_up || report_failure "mouse_button 0 on the left pane printed no 'pointer> release' line"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' ||
  report_failure "a click on the left pane did not move the focus (last pane> line: '$(last_pane_line)')"
LONG="$(seq -s , 29)"
type_keys s e q spc minus s spc comma spc 4 0 ret
wait_for_screen "\\| ${LONG} \\|" ||
  report_failure "seq -s , 40 did not fold into a 77-column row '${LONG}'"
ROW="$(screen_row "$LONG")"
[ "$ROW" -ge 0 ] || report_failure "the 77-column row is not on the last screen"
PY="$(cell_y "$ROW")"
move_to "$(cell_x 0)" "$PY" ||
  report_failure "the pointer did not reach the start of the long row (last at: '$(last_at)')"
CLIPS="$(clip_lines)"
button_down || report_failure "mouse_button 1 on the long row printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=${ROW} col=0" ] ||
  report_failure "the press on the long row printed '$(last_press)', expected 'press leaf=0 row=${ROW} col=0'"
move_to 720 "$PY" ||
  report_failure "the drag did not reach x=720 over the right pane (last at: '$(last_at)')"
wait_for_log "terminal: copy> point row=${ROW} col=76" ||
  report_failure "over the right pane the selection end is '$(grep -a 'terminal: copy> point' "$LOG" | tail -n 1 | tr -d '\r')', expected row=${ROW} col=76 (the pressed pane's last column)"
button_up || report_failure "mouse_button 0 over the right pane printed no 'pointer> release' line"
wait_for_count clip_lines '' "$((CLIPS + 1))" ||
  report_failure "the release over the right pane put nothing on the clipboard"
[ "$(last_clip)" = "terminal: clip> len=77 text=${LONG}" ] ||
  report_failure "dragging over the neighbor copied '$(last_clip)', expected the whole 77-column row (len=77 text=${LONG})"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 ' ||
  report_failure "dragging over the right pane moved the focus (last pane> line: '$(last_pane_line)')"
echo "clamped drag: $(last_clip)"

# ── 검사 16의 둘째: 누른 채 굴린 휠은 누른 패널을 움직이고 선택 끝을 맞춘다 ──
#
# design 결정 7의 "끄는 중" 행. seq 120 160을 찍고 150의 0열을 누른 채(끌지
# 않고) 휠을 앞으로 한 눈금 민다. 선택이 먼저 시작되고(앵커가 150에 붙는다)
# 그다음 뷰포트가 세 줄 올라가며, 선택 끝은 같은 뷰포트 칸 — 이제 147 — 으로
# 다시 맞춰진다. 떼면 147부터 150의 첫 글자까지 열세 바이트다.
#
# 순서가 뒤집히면(스크롤 뒤에 선택 시작) 앵커가 147에 붙어 한 글자짜리
# 선택이 된다. 그것은 pointer_test 검사 22가 부팅 전에 잡는다.
echo "=== a wheel notch while pressed scrolls the pressed pane and moves the end ==="
type_keys s e q spc 1 2 0 spc 1 6 0 ret
wait_for_screen '\| 160 \| root@\(none\) ~#' ||
  report_failure "seq 120 160 did not finish (no '| 160 | root@(none) ~#' on the screen)"
ROW="$(screen_row 150)"
[ "$ROW" -ge 3 ] || report_failure "150 is not on the last screen with three rows above it (row ${ROW})"
move_to "$(cell_x 0)" "$(cell_y "$ROW")" ||
  report_failure "the pointer did not reach 150 (last at: '$(last_at)')"
OFF_A="$(scroll_field offset)"
CLIPS="$(clip_lines)"
button_down || report_failure "mouse_button 1 on 150 printed no 'pointer> press' line"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=${ROW} col=0" ] ||
  report_failure "the press on 150 printed '$(last_press)', expected 'press leaf=0 row=${ROW} col=0'"
ATS="$(pointer_count 'at ')"
hmp "mouse_move 0 0 1"
wait_for_count pointer_count 'at ' "$((ATS + 1))" ||
  report_failure "a wheel notch while pressed printed no at line"
OFF_B="$(scroll_field offset)"
[ "$OFF_B" -eq "$((OFF_A - 3))" ] ||
  report_failure "a wheel notch while pressed moved the pressed pane from offset ${OFF_A} to ${OFF_B}, expected $((OFF_A - 3))"
[ "$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')" = "terminal: copy> enter row=${ROW} col=0" ] ||
  report_failure "the wheel while pressed did not start the selection at the pressed cell (last copy> enter: '$(grep -a 'terminal: copy> enter' "$LOG" | tail -n 1 | tr -d '\r')')"
button_up || report_failure "mouse_button 0 after the wheel printed no 'pointer> release' line"
wait_for_count clip_lines '' "$((CLIPS + 1))" ||
  report_failure "the release after the wheel put nothing on the clipboard"
[ "$(last_clip)" = "terminal: clip> len=13 text=147" ] ||
  report_failure "the wheel drag copied '$(last_clip)', expected 'clip> len=13 text=147' (147 to the first byte of 150)"
echo "wheel while pressed: offset ${OFF_A} -> ${OFF_B}, $(last_clip)"

# 마지막 검사(부팅 마우스를 뺀다)는 M1의 자리(679, 0)를 본다. 그리로 되돌린다.
# 움직이면 화살표가 다시 보이므로, 뺄 때 숨는 at 줄이 찍힌다.
move_to 679 0 ||
  report_failure "the pointer did not get back to 679,0 (last at: '$(last_at)')"

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
# NUL만 세어 한 번에 읽는다(AL-M1). 예전에는 파일을 두 번 읽어(NUL을 뺀 길이 · 전체 길이)
# 견줬는데, QEMU가 아직 돌며 terminal의 dump를 쓰는 동안이라 두 번 사이에 로그가 자라
# NUL이 없어도 거짓으로 빨갰다(AL-M1 사본의 pointer 부팅 B).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "pointer> lines:"
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'

# ══ 부팅 B: PS/2 마우스와 uinput 터치패드 (PD-M3) ═══════════════════════
#
# 부팅 A를 끄고 설정 디스크 하나를 물려 다시 뜬다. cmdline은 기본 그대로라
# psmouse가 QEMU pc의 PS/2 마우스를 잡는다(design 실측 4). 디스크에는 되감기
# 도구와 드라이버 목록 스크립트가 있다. 라벨 접두사 tars-가 init이 설정
# 디스크를 알아보는 표지다(RM-M2).
exec 3<&- 2>/dev/null
exec 3>&- 2>/dev/null
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

# 검사 19의 둘째 겹 — 게스트에서 드라이버가 실제로 등록됐는가. 없는 것만 한 줄씩
# 찍고 마지막에 개수를 찍는다. 화면 한 장에 들어가야 screen> 줄로 판정할 수 있어서
# 있는 것은 안 찍는다. 이름은 PD-M3 plan 확정 4가 커널 소스에서 뽑았다.
SEED="$(mktemp -d)"
mkdir -p "$SEED/pd"
printf 'shell=fish\n' > "$SEED/tars.conf"
cp "$REPLAY" "$SEED/pd/tp-replay"
chmod 0755 "$SEED/pd/tp-replay"
cat > "$SEED/pd/drivers" <<'DRIVERS'
#!/usr/bin/bash
n=0
ok=0
for d in /sys/bus/serio/drivers/psmouse /sys/bus/hid/drivers/hid-multitouch \
    /sys/bus/i2c/drivers/i2c_hid_acpi /sys/bus/i2c/drivers/elan_i2c /sys/bus/i2c/drivers/rmi4_smbus \
    /sys/bus/rmi4/drivers/rmi4_physical /sys/bus/pci/drivers/i801_smbus /sys/bus/pci/drivers/intel-lpss \
    /sys/bus/platform/drivers/i2c_designware /sys/bus/platform/drivers/amd_gpio \
    /sys/bus/platform/drivers/tigerlake-pinctrl /sys/bus/pci/drivers/intel_quicki2c; do
  n=$((n + 1))
  if [ -e "$d" ]; then ok=$((ok + 1)); else echo "pd-drv-no $d"; fi
done
n=$((n + 1))
if [ -c /dev/uinput ]; then ok=$((ok + 1)); else echo "pd-drv-no /dev/uinput"; fi
echo "pd-drivers ${ok}/${n}"
DRIVERS
chmod 0755 "$SEED/pd/drivers"
# PD-M4의 프로브. 마우스 모드를 켜고, terminal이 보낸 보고를 정해진 바이트 수만큼
# 읽어 cat -v로 찍는다. 이스케이프 바이트는 게이트가 타이핑으로 만들 수 없어서
# (lessons 실측 53, tq-probe와 같은 이유) 파일로 싣는다.
#
#   /config/pd/mouse <표지> <바이트 수> <초> <DECSET 번호…>
#
# 표지는 화면 줄을 이 호출의 것으로 가른다 — 친 명령줄(pd/mouse)과 판정 글자
# (pd-mouse-ready-표지 · pd-mouse-got-표지)가 안 겹친다(project_gate_screen_echo).
# 켜기 · 읽기 · 끄기가 한 프로세스 안에 있어야 한다. 보고는 pty의 입력이고,
# 프롬프트로 돌아온 셸이 먼저 읽으면 그 셸의 키가 된다(tq-probe와 같다).
# read -N은 정해진 글자 수를 읽고 -s가 에코를 끈다. 시간이 다 되면 그때까지
# 읽은 것을 남긴다 — 보고가 없으면 0이다. 게스트에 stty가 없어서 bash의 read가
# 터미널을 raw로 바꾸는 유일한 길이다.
cat > "$SEED/pd/mouse" <<'MOUSE'
#!/usr/bin/bash
tag=$1 len=$2 secs=$3
shift 3
for m in "$@"; do printf '\033[?%sh' "$m"; done
echo "pd-mouse-ready-${tag}"
IFS= read -rs -N "$len" -t "$secs" got
for m in "$@"; do printf '\033[?%sl' "$m"; done
printf 'pd-mouse-got-%s %d [%s]\n' "$tag" "${#got}" "$(printf '%s' "$got" | cat -v)"
MOUSE
chmod 0755 "$SEED/pd/mouse"
# vim이 클릭을 받는지 볼 파일(검사 31). 서른 줄이라 한 화면에 다 든다.
for i in $(seq -w 1 30); do echo "pd-line-${i}"; done > "$SEED/pd/lines"
DISK_B="${REPO_ROOT}/out/pd-touchpad.img"
rm -f "$DISK_B"
truncate -s 16M "$DISK_B"
mkfs.ext2 -F -q -m 0 -L tars-pd -d "$SEED" "$DISK_B"
rm -rf "$SEED"

LOG_A="$LOG"
LOG="$(mktemp)"
echo "=== boot B: the PS/2 mouse and a uinput touchpad ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK_B",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT_B},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "boot B: terminal never rendered a prompt"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "boot B: the shell prompt never showed up"
grep -a 'tars-init: mounted ext2 at /config' "$LOG" >/dev/null ||
  report_failure "boot B: the config disk was not mounted at /config"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT_B}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "boot B: could not connect to the QEMU monitor"

# ── 검사 20: psmouse가 PS/2 마우스를 잡고 terminal이 마우스로 연다 ────────
#
# 커널 줄과 terminal 줄을 따로 본다. 커널 줄이 없으면 psmouse가 i8042 AUX를 못
# 잡은 것이고(MOUSE_PS2가 빠졌거나 i8042가 AUX를 안 열었다), 커널 줄만 있으면
# terminal의 분류나 핫플러그가 틀린 것이다. psmouse의 탐지는 비동기라서 terminal보다
# 늦게 끝날 수 있다 — 그러면 처음 훑기가 아니라 uevent가 연다. 어느 쪽이든 같은 줄이다.
# synaptics 프로토콜은 QEMU에 없으므로 이 부팅이 보는 것은 "psmouse가 i8042 AUX를
# 잡는다"까지다(design 결정 9).
echo "=== boot B: psmouse registers the PS/2 mouse and terminal opens it ==="
PS2_NAME='ImExPS/2 Generic Explorer Mouse'
wait_for_log "input: ${PS2_NAME} as /devices/platform/i8042/serio1/input/input[0-9]+" ||
  report_failure "psmouse never registered the PS/2 mouse (no 'input: ${PS2_NAME} as …/i8042/serio1/…')"
wait_for_log "terminal: pointer> open /dev/input/event[0-9]+ kind=mouse shown=0 name=${PS2_NAME}" ||
  report_failure "the kernel registered the PS/2 mouse but terminal never opened it as kind=mouse"
PS2_PATH="$(grep -a "terminal: pointer> open .* name=${PS2_NAME}" "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*open ([^ ]+) .*/\1/')"
echo "ps/2 mouse: ${PS2_PATH}"

# ── 검사 19의 둘째: 드라이버가 게스트에 등록됐다 ──────────────────────────
echo "=== boot B: the touchpad drivers are registered ==="
type_keys slash c o n f i g slash p d slash d r i v e r s ret
wait_for_screen '\| pd-drivers [0-9]+/[0-9]+ \|' ||
  report_failure "the driver list script printed no summary"
DRV_LINE="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' | grep -oE 'pd-drivers [0-9]+/[0-9]+' | tail -n 1)"
DRV_MISSING="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' | grep -oE 'pd-drv-no [^ |]+' | sort -u | tr '\n' ' ')"
[ "$DRV_LINE" = "pd-drivers 13/13" ] ||
  report_failure "the guest is missing touchpad drivers: '${DRV_LINE}' ${DRV_MISSING}"
echo "drivers: ${DRV_LINE}"

# 스크롤백을 만들어 둔다(검사 24). 도구는 패널 안에서 돌고 찍지 않으므로 그동안
# 이 스크롤백이 그대로다.
type_keys s e q spc 2 0 0 ret
wait_for_screen '\| 200 \| root@\(none\) ~#' ||
  report_failure "boot B: seq 200 did not finish"

# ── 검사 21: 도구가 만든 터치패드를 터치패드로 연다 ─────────────────────
#
# 부팅 뒤에 생긴 장치라 uevent가 알리고(PD-M0의 배관), classify가 INPUT_PROP_POINTER와
# ABS_MT로 터치패드라 하고, EVIOCGABS로 읽은 축이 open 줄에 찍힌다. 축은 도구가
# 만든 그대로다 — 가로 0..1000 · 세로 0..600, resolution 10 · 12, 칸 둘.
echo "=== boot B: tp-replay makes a touchpad and terminal opens it ==="
type_keys slash c o n f i g slash p d slash t p minus r e p l a y ret
wait_for_log 'terminal: pointer> (open|skip) /dev/input/event[0-9]+ kind=touchpad.* name=TARS Replay Touchpad' ||
  report_failure "terminal never saw the replay touchpad (no 'pointer> open … kind=touchpad … name=TARS Replay Touchpad')"
TP_LINE="$(grep -a 'name=TARS Replay Touchpad' "$LOG" | grep -a 'terminal: pointer> ' | tail -n 1 | tr -d '\r')"
case "$TP_LINE" in
  *"> open /dev/input/event"*" kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad") ;;
  *) report_failure "the replay touchpad came out as '${TP_LINE}', expected 'open … kind=touchpad slots=2 x=0..1000 y=0..600 res=10,12 shown=0 name=TARS Replay Touchpad'" ;;
esac
TP_PATH="$(sed -E 's/.*open ([^ ]+) .*/\1/' <<<"$TP_LINE")"
echo "touchpad: ${TP_LINE}"

# 명령 한 줄을 도구의 stdin에 친다. 친 글자는 키라서 화살표를 숨기지만(보이는
# 조건 3), 다음 손가락 이동이 다시 보이게 한다.
replay() {
  local word keys=()
  for word in $1; do
    [ "${#keys[@]}" -gt 0 ] && keys+=(spc)
    keys+=($(sed -e 's/./& /g' -e 's/-/minus/g' <<<"$word"))
  done
  type_keys "${keys[@]}" ret
}

# ── 검사 22: 한 손가락 이동이 배율대로 포인터를 옮긴다 ───────────────────
#
# 출발은 가운데(640, 400)다. 가로 100단위는 128픽셀이다 — 패드 가로 1000이 화면
# 가로 1280이다. 세로 60단위는 64픽셀이다 — 세로 resolution이 12라서 같은 mm당
# 픽셀로 맞추면 단위당 1.28 × 10 / 12다. resolution을 안 보고 가로와 같은 단위당
# 픽셀을 쓰면 76이 된다(mutation 4). 이동은 탭이 아니다 — press 줄이 없다.
echo "=== boot B: one finger moves the pointer by the pad's scale ==="
replay "move 100 0"
wait_for_at "^terminal: pointer> at x=768 y=400 buttons=0 wheel=0 shown=1 ink=${ARROW_INK}\$" ||
  report_failure "after 'move 100 0' the last at line is '$(last_at)', expected 'at x=768 y=400 … shown=1 ink=${ARROW_INK}' (100 of 1000 units is 128 of 1280 pixels)"
replay "move 0 60"
wait_for_at '^terminal: pointer> at x=768 y=464 ' ||
  report_failure "after 'move 0 60' the last at line is '$(last_at)', expected x=768 y=464 (60 units at resolution 12 against 10 is 64 pixels)"
[ "$(pointer_count 'press ')" -eq 0 ] ||
  report_failure "a one-finger move pressed a button: $(last_press)"
echo "moved: $(last_at)"

# ── 검사 23: 탭은 클릭이고, 긴 누름은 아무것도 아니다 ─────────────────────
#
# 탭(40ms)은 press · release 한 쌍이다. 768, 464는 27행 93열의 칸이다. 긴 누름(500ms)은
# 아무것도 안 낸다. 그것을 "아직 안 왔다"와 가르려고 뒤에 이동을 하나 보낸다 —
# 같은 장치의 이벤트는 순서대로 읽히므로 그 이동의 at 줄이 보이면 긴 누름은 이미
# 디코더를 지났다. 탭의 시간 조건이 빠지면 여기서 press가 하나 더 는다(mutation 1).
# 그 이동은 40단위다. 탭이 움직여도 되는 거리가 가로 20단위(축의 2%)라서 그보다
# 짧고 빠른 이동은 그 자체가 탭이 된다 — 10단위로 했을 때 실제로 클릭이 났다.
echo "=== boot B: a tap clicks, a hold does nothing ==="
replay "tap"
wait_for_count pointer_count 'release ' 1 ||
  report_failure "a tap printed no 'pointer> release' line (last press: '$(last_press)')"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=27 col=93" ] ||
  report_failure "the tap pressed '$(last_press)', expected 'press leaf=0 row=27 col=93'"
[ "$(last_release)" = "terminal: pointer> release drag=0" ] ||
  report_failure "the tap released '$(last_release)', expected 'release drag=0'"
replay "hold"
replay "move 40 0"
wait_for_at '^terminal: pointer> at x=819 y=464 ' ||
  report_failure "after 'hold' and 'move 40 0' the last at line is '$(last_at)', expected x=819 y=464"
[ "$(pointer_count 'press ')" -eq 1 ] ||
  report_failure "a 500ms hold clicked (press lines: $(pointer_count 'press '), last '$(last_press)'); a tap must be shorter than 180ms"
echo "tap: $(last_press) / $(last_release), hold: nothing"

# ── 검사 24: 두 손가락 세로는 휠이고, 포인터는 안 움직인다 ────────────────
#
# 90단위는 96픽셀이고 휠 한 눈금이 3줄 × 16픽셀이라 두 눈금, 여섯 줄이다. 손가락을
# 아래로 밀면 휠을 앞으로 민 것과 같다 — 위의 글이 보이도록 offset이 준다. 패널은
# 바닥에 있었으므로(친 글자의 에코가 내린다) offset은 total - len - 6이 된다.
# 두 손가락을 이동으로 보내면 at의 y가 바뀌고 offset은 그대로다(mutation 2).
echo "=== boot B: two fingers scroll the pane under the pointer ==="
ATS="$(pointer_count 'at ')"
replay "scroll 90"
SCROLLED=0
for _ in $(seq 1 150); do
  LINE="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 | tr -d '\r')"
  T="$(sed -E 's/.*total=([0-9]+).*/\1/' <<<"$LINE")"
  O="$(sed -E 's/.*offset=([0-9]+).*/\1/' <<<"$LINE")"
  L="$(sed -E 's/.*len=([0-9]+).*/\1/' <<<"$LINE")"
  if [ "$((T - L - O))" -eq 6 ]; then SCROLLED=1; break; fi
  sleep 0.1
done
[ "$SCROLLED" = "1" ] ||
  report_failure "two fingers 90 units down left the viewport at '${LINE}', expected six rows above the bottom"
NEW_ATS="$(grep -a 'terminal: pointer> at ' "$LOG" | tail -n "+$((ATS + 1))" | tr -d '\r')"
grep -avE ' x=819 y=464 ' <<<"$NEW_ATS" >/dev/null &&
  report_failure "two fingers moved the pointer: $(grep -avE ' x=819 y=464 ' <<<"$NEW_ATS" | sed -n 1p)"
WHEEL=0
while read -r w; do WHEEL=$((WHEEL + w)); done < <(sed -nE 's/.* wheel=(-?[0-9]+) .*/\1/p' <<<"$NEW_ATS")
[ "$WHEEL" = "2" ] ||
  report_failure "two fingers 90 units down added up to wheel=${WHEEL} on the at lines, expected 2"
echo "scrolled: ${LINE}, wheel ${WHEEL}"

# ── 검사 25: 도구가 끝나면 터치패드를 닫는다 ─────────────────────────────
#
# quit이 UI_DEV_DESTROY로 장치를 없앤다. 그 fd가 POLLHUP을 올리고 terminal이 닫는다.
# PS/2 마우스는 그대로 열려 있다. 그 뒤에 친 echo가 오면 poll이 막히지 않은 것이다.
echo "=== boot B: quitting the tool closes the touchpad ==="
replay "quit"
wait_for_log "terminal: pointer> close ${TP_PATH}" ||
  report_failure "the replay touchpad was never closed (no 'pointer> close ${TP_PATH}')"
[ "$(pointer_count 'close ')" -eq 1 ] ||
  report_failure "expected one 'pointer> close' in boot B, got $(pointer_count 'close ')"
type_keys e c h o spc p d minus t p minus g o n e ret
wait_for_screen '\| pd-tp-gone \|' ||
  report_failure "the shell did not answer after the touchpad went away"
echo "closed: $(grep -a 'terminal: pointer> close ' "$LOG" | tail -n 1 | tr -d '\r')"

# ══ PD-M4: 마우스 보고 (부팅 B) ══════════════════════════════════════════
#
# 자식이 마우스 모드를 켜면 누름 · 끎 · 뗌 · 휠이 그 자식의 PTY에 보고로 간다
# (design 결정 12). 판정은 둘을 같은 글자로 맞춘다 — terminal이 보낸 것(report
# 줄)과 자식이 읽은 것(/config/pd/mouse가 찍은 화면 줄). report 줄만 보면 PTY에
# 안 쓴 고장이 안 보이고, 화면 줄만 보면 어느 패널에 보냈는지가 안 보인다.
#
# 포인터는 PS/2 마우스로 움직인다. 부팅 B의 HMP 대상은 그것 하나이고 이동이
# 1:1이다(PD-M4 plan 확정 7). 터치패드가 닫힌 뒤라 at 줄의 자리가 그대로 이어진다.
#
# 누르는 칸은 1행 10열이고 끄는 칸은 1행 12열이다. 칸의 가운데 픽셀(+3, +7)을
# 쓴다 — 칸 경계는 vt_test 검사 103이 본다. 1행에 무엇이 있든 상관없다. 보고는
# 글자를 안 보고, 프로브가 도는 동안 셸은 그 줄을 안 다시 그린다.

# ── PD-M4의 도구 ──────────────────────────────────────────────────────

# report 줄의 개수와 마지막 줄.
report_count() {
  grep -ac 'terminal: pointer> report ' "$LOG" || true
}

last_report() {
  grep -a 'terminal: pointer> report ' "$LOG" | tail -n 1 | tr -d '\r'
}

# 글자열 하나를 sendkey 이름으로 바꿔 치고 Enter를 친다. 영소문자 · 숫자 ·
# 공백 · / · - 만 쓴다.
type_cmd() {
  local s="$1" keys=() ch i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
      ' ') keys+=(spc) ;;
      /) keys+=(slash) ;;
      -) keys+=(minus) ;;
      *) keys+=("$ch") ;;
    esac
  done
  type_keys "${keys[@]}" ret
}

# 화면 줄에 글자 그대로($1)가 나타날 때까지 기다린다. 15초. 프로브의 줄에는
# ERE의 특수 문자(^ [ ])가 가득해서 wait_for_screen에 못 넘긴다.
wait_for_screen_text() {
  local text="$1" i
  for i in $(seq 1 150); do
    if grep -aqF -- "$text" <<<"$(grep -a 'terminal: screen>' "$LOG")"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 화면 줄 중 N번째 뒤의 것에 패턴(ERE)이 나타날 때까지 기다린다. 15초.
# wait_for_screen은 로그 전체를 보므로 옛 화면에 바로 맞는 자리에 쓴다.
wait_for_new_screen() {
  local n="$1" pattern="$2" i
  for i in $(seq 1 150); do
    if grep -aqE -- "$pattern" <<<"$(grep -a 'terminal: screen>' "$LOG" | tail -n "+$((n + 1))")"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 프로브를 띄우고 모드가 켜질 때까지 기다린다. 인자는 표지 · 바이트 수 · 초 ·
# DECSET 번호들이다. ready 줄은 모드를 켠 printf 뒤에 찍히므로, 그 줄을 그린
# 프레임이 보이면 terminal은 모드 바이트를 이미 먹었다.
probe_start() {
  type_cmd "/config/pd/mouse $*"
  wait_for_screen_text "pd-mouse-ready-$1"
}

# 프로브가 찍은 결과 줄(마지막 screen>에서 pd-mouse-got-표지로 시작하는 행).
# 나올 때까지 기다린 뒤 그 행을 낸다. 20초 — 프로브가 시간이 다 되어 끝나는
# 검사(29)가 있다.
probe_result() {
  local tag="$1" i
  for i in $(seq 1 200); do
    if grep -aqF -- "pd-mouse-got-${tag} " <<<"$(grep -a 'terminal: screen>' "$LOG")"; then break; fi
    sleep 0.1
  done
  grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' |
    TAG="$tag" perl -ne 's/^.*?terminal: screen> //; chomp;
      for my $r (split / \| /, $_, -1) { print "$r\n" if index($r, "pd-mouse-got-$ENV{TAG} ") == 0 }' | tail -n 1
}

# HMP mouse_button 하나를 보내고 report 줄이 하나 늘 때까지 기다린다.
report_button() {
  local n
  n="$(report_count)"
  hmp "mouse_button $1"
  wait_for_count report_count '' "$((n + 1))"
}

CX=$(( $(cell_x 10) + 3 ))
CY=$(( $(cell_y 1) + 7 ))
DX=$(( $(cell_x 12) + 3 ))

# ── 검사 26: 모드 1000은 누름과 뗌만 받는다 ───────────────────────────
#
# 1000 · 1006(SGR)을 켜고 10열을 눌러 12열까지 끌어 뗀다. 자식이 받는 것은
# 누름(ESC[<0;11;2M)과 뗌(ESC[<0;13;2m)이고 끎은 없다 — 좌표는 1부터 세고 뗌은
# 소문자 m이다. 우리 제스처는 안 돈다(press 줄 · copy> enter가 안 는다).
# 모드를 무시하고 언제나 우리 것으로 다루면(mutation 1) report 줄이 안 나온다.
echo "=== boot B: mode 1000 gets the press and the release, not the drag ==="
move_to "$CX" "$CY" || report_failure "the PS/2 mouse did not bring the pointer to ${CX},${CY} (last at: '$(last_at)')"
PRESSES_BEFORE="$(pointer_count 'press ')"
ENTERS_BEFORE="$(copy_lines enter)"
REPORTS_BEFORE="$(report_count)"
probe_start a 20 8 1000 1006 || report_failure "the probe never printed pd-mouse-ready-a"
report_button 1 || report_failure "a press in a pane with mode 1000 printed no 'pointer> report' line (last press: '$(last_press)')"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<0;11;2M' ] ||
  report_failure "the press was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<0;11;2M'"
move_to "$DX" "$CY" || report_failure "the drag did not reach ${DX},${CY} (last at: '$(last_at)')"
report_button 0 || report_failure "the release in mode 1000 printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<0;13;2m' ] ||
  report_failure "the release was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<0;13;2m'"
GOT="$(probe_result a)"
[ "$GOT" = 'pd-mouse-got-a 20 [^[[<0;11;2M^[[<0;13;2m]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-a 20 [^[[<0;11;2M^[[<0;13;2m]'"
[ "$(report_count)" -eq "$((REPORTS_BEFORE + 2))" ] ||
  report_failure "mode 1000 reported more than the press and the release ($((REPORTS_BEFORE)) -> $(report_count), last '$(last_report)')"
[ "$(pointer_count 'press ')" -eq "$PRESSES_BEFORE" ] && [ "$(copy_lines enter)" -eq "$ENTERS_BEFORE" ] ||
  report_failure "a reported press also ran our gesture (press lines ${PRESSES_BEFORE} -> $(pointer_count 'press '), copy> enter ${ENTERS_BEFORE} -> $(copy_lines enter))"
echo "1000: ${GOT}"

# ── 검사 27: 모드 1002는 누른 채 움직임도 받는다 ───────────────────────
#
# 같은 손동작에 끎 하나가 더해진다. 끎은 버튼 0에 32를 더한 32다. 끄는 보고에
# 버튼을 안 실으면 인코더가 1002에서 그것을 버린다.
echo "=== boot B: mode 1002 also gets the drag ==="
move_to "$CX" "$CY" || report_failure "the pointer did not come back to ${CX},${CY} (last at: '$(last_at)')"
probe_start b 31 8 1002 1006 || report_failure "the probe never printed pd-mouse-ready-b"
report_button 1 || report_failure "a press in mode 1002 printed no 'pointer> report' line"
N="$(report_count)"
move_to "$DX" "$CY" || report_failure "the drag did not reach ${DX},${CY} (last at: '$(last_at)')"
wait_for_count report_count '' "$((N + 1))" ||
  report_failure "a drag in mode 1002 printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<32;13;2M' ] ||
  report_failure "the drag was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<32;13;2M'"
report_button 0 || report_failure "the release in mode 1002 printed no 'pointer> report' line"
GOT="$(probe_result b)"
[ "$GOT" = 'pd-mouse-got-b 31 [^[[<0;11;2M^[[<32;13;2M^[[<0;13;2m]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-b 31 [^[[<0;11;2M^[[<32;13;2M^[[<0;13;2m]'"
echo "1002: ${GOT}"

# ── 검사 28: 마우스를 원하는 패널의 휠은 버튼 4 · 5다 ─────────────────
#
# 포인터는 12열에 있다. 위로 한 눈금 · 아래로 한 눈금이 64 · 65이고, 우리
# 스크롤백은 안 움직인다. scroll> 줄은 프로브의 출력으로도 찍히므로 줄 수가 아니라
# 값을 본다 — 이 검사 동안 찍힌 scroll> 줄이 전부 바닥(offset = total - len)이다.
echo "=== boot B: the wheel over a pane in mode 1000 is buttons 4 and 5 ==="
SCROLLS_N="$(grep -ac 'terminal: scroll>' "$LOG" || true)"
probe_start c 22 8 1000 1006 || report_failure "the probe never printed pd-mouse-ready-c"
N="$(report_count)"
hmp "mouse_move 0 0 1"
wait_for_count report_count '' "$((N + 1))" || report_failure "a wheel notch up in mode 1000 printed no 'pointer> report' line"
hmp "mouse_move 0 0 -1"
wait_for_count report_count '' "$((N + 2))" || report_failure "a wheel notch down in mode 1000 printed no 'pointer> report' line"
GOT="$(probe_result c)"
[ "$GOT" = 'pd-mouse-got-c 22 [^[[<64;13;2M^[[<65;13;2M]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-c 22 [^[[<64;13;2M^[[<65;13;2M]'"
LIFTED="$(grep -a 'terminal: scroll>' "$LOG" | tail -n "+$((SCROLLS_N + 1))" | tr -d '\r' |
  perl -ne 'print if /total=(\d+) offset=(\d+) len=(\d+)/ and $1 - $3 != $2')"
[ -z "$LIFTED" ] ||
  report_failure "a reported wheel also moved our scrollback: $(sed -n 1p <<<"$LIFTED")"
echo "wheel: ${GOT}"

# ── 검사 29: Shift를 누르면 자식이 원해도 우리 선택이다 ──────────────────
#
# 프로브의 ready 줄(pd-mouse-ready-s)의 0열에서 7열까지 Shift를 누른 채 끈다.
# 우리 제스처가 돌아 pd-mouse 여덟 글자가 클립보드에 들어가고, 자식은 아무것도
# 못 받는다 — 프로브가 6초를 기다려 0을 찍는다. Shift를 안 보면(mutation 2)
# 자식이 그 누름을 받고 클립보드는 그대로다.
#
# HMP sendkey의 마지막 수는 누르고 있는 시간(ms)이다. QEMU는 키를 뗄 때까지 다음
# 키를 큐에 두지만 마우스는 큐를 안 거친다 — 그 3초 안에 누르고 끌고 뗀다. 뒤의
# type_keys는 그 큐 뒤에 서므로 Shift가 떨어진 다음에 간다.
echo "=== boot B: Shift takes the drag back from a child that wants the mouse ==="
CLIPS_BEFORE="$(clip_lines)"
REPORTS_BEFORE="$(report_count)"
probe_start s 10 6 1000 1006 || report_failure "the probe never printed pd-mouse-ready-s"
ROW="$(screen_row pd-mouse-ready-s)"
[ "$ROW" -ge 0 ] || report_failure "no screen row is exactly pd-mouse-ready-s"
move_to "$(( $(cell_x 0) + 3 ))" "$(( $(cell_y "$ROW") + 7 ))" ||
  report_failure "the pointer did not reach the ready line (last at: '$(last_at)')"
echo "sendkey shift 3000" >&3
sleep 0.3
button_down || report_failure "a Shift-press in mode 1000 printed no 'pointer> press' line (last report: '$(last_report)')"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=${ROW} col=0" ] ||
  report_failure "the Shift-press printed '$(last_press)', expected 'press leaf=0 row=${ROW} col=0'"
move_to "$(( $(cell_x 7) + 3 ))" "$(( $(cell_y "$ROW") + 7 ))" ||
  report_failure "the Shift-drag did not reach column 7 (last at: '$(last_at)')"
button_up || report_failure "the Shift-release printed no 'pointer> release' line"
wait_for_count clip_lines '' "$((CLIPS_BEFORE + 1))" ||
  report_failure "a Shift-drag over a child in mode 1000 put nothing on the clipboard (last report: '$(last_report)')"
[ "$(last_clip)" = "terminal: clip> len=8 text=pd-mouse" ] ||
  report_failure "the Shift-drag copied '$(last_clip)', expected 'clip> len=8 text=pd-mouse'"
GOT="$(probe_result s)"
[ "$GOT" = 'pd-mouse-got-s 0 []' ] ||
  report_failure "the child read '${GOT}' during a Shift-drag, expected 'pd-mouse-got-s 0 []'"
[ "$(report_count)" -eq "$REPORTS_BEFORE" ] ||
  report_failure "a Shift-drag was reported to the child: '$(last_report)'"
echo "shift: $(last_clip), ${GOT}"

# ── 검사 30: 대체 화면의 휠은 화살표 키다(모드 1007) ────────────────────
#
# 프로브가 1049로 대체 화면에 들어간다. 마우스 모드는 안 켠다. 1007은 기본이
# 켜짐이라 휠 위로 한 눈금이 ESC[A 세 번이다(WHEEL_ROWS). report 줄은 n=3으로
# 한 줄이다. 1007을 안 보면(mutation 4) 우리 스크롤이 되고 대체 화면에는
# 스크롤백이 없어 아무 일도 없다 — 프로브는 0을 찍는다.
echo "=== boot B: the wheel on the alternate screen is arrow keys ==="
probe_start k 9 8 1049 || report_failure "the probe never printed pd-mouse-ready-k"
N="$(report_count)"
hmp "mouse_move 0 0 1"
wait_for_count report_count '' "$((N + 1))" ||
  report_failure "a wheel notch on the alternate screen printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=3 text=^[[A' ] ||
  report_failure "the wheel on the alternate screen was sent as '$(last_report)', expected 'report leaf=0 n=3 text=^[[A'"
GOT="$(probe_result k)"
[ "$GOT" = 'pd-mouse-got-k 9 [^[[A^[[A^[[A]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-k 9 [^[[A^[[A^[[A]'"
echo "alternate: ${GOT}"

# ── 검사 31: vim이 시스템 vimrc의 mouse=a로 클릭을 받는다 ───────────────
#
# 서른 줄 파일을 열고 4행 9열을 누른다. 줄 번호 칸이 넷(numberwidth)이라 9열은
# 글자로 5열이고 4행은 5번째 줄이다 — vim의 상태 줄 위치가 1:1에서 5:6이 된다.
# 이 검사가 vimrc의 두 줄(mouse=a · ttymouse=sgr)과 실제 프로그램을 본다.
# vim이 무슨 모드를 켜는지(1000이냐 1002냐)는 안 본다. report 줄의 SGR 모양만
# 본다.
echo "=== boot B: vim takes a click through mouse=a ==="
type_cmd "vim /config/pd/lines"
wait_for_screen 'unix  1:1 ' || report_failure "vim did not open /config/pd/lines at 1:1"
move_to "$(( $(cell_x 9) + 3 ))" "$(( $(cell_y 4) + 7 ))" ||
  report_failure "the pointer did not reach row 4 column 9 (last at: '$(last_at)')"
report_button 1 || report_failure "vim did not turn on mouse reporting (a press printed no 'pointer> report' line, last press: '$(last_press)')"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<0;10;5M' ] ||
  report_failure "the press in vim was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<0;10;5M' (ttymouse=sgr)"
report_button 0 || report_failure "the release in vim printed no 'pointer> report' line"
wait_for_screen 'unix  5:6 ' || report_failure "vim did not move its cursor to 5:6 after the click"
# vim이 끝나기 전에 친 글자는 vim이 먹는다. 주 화면이 돌아와 vim을 친 명령줄이
# 다시 보이면 끝난 것이다 — 그 줄은 vim이 도는 동안(대체 화면)에는 안 보인다.
SCREENS_N="$(screen_lines)"
type_keys shift-semicolon q ret
wait_for_new_screen "$SCREENS_N" '\| root@\(none\) ~# vim /config/pd/lines \|' ||
  report_failure "vim did not quit back to the shell after :q"
echo "vim: clicked to 5:6"

# ── 검사 32: 포커스가 아닌 패널을 누르면 포커스가 옮겨 간 뒤 그 패널이 받는다 ──
#
# Cmd+D로 가르면 포커스가 새 패널(1)에 있다. 거기서 프로브를 띄우고 Cmd+[로
# 포커스를 0에 돌린 뒤, 1의 1행 2열(격자 80열)을 누르고 뗀다. 포커스가 1로
# 옮겨 가고(tmux의 기본과 같다), 보고의 좌표는 그 패널 안의 칸 3;2다. 격자의
# 원점으로 재면(mutation 3) 80열이 77열 패널의 오른쪽 밖이 되고, 인코더가 밖에서의
# 누름을 버려 report 줄이 안 나온다.
echo "=== boot B: a press on another pane moves the focus, then reports to it ==="
SCREENS_N="$(screen_lines)"
type_keys meta_l-d
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "Cmd+D did not give 'panes=2 focus=1 rect=78,0 77x47' (last pane> line: '$(last_pane_line)')"
# 새 셸의 프롬프트가 그 패널의 첫 줄에 보일 때까지. 그 전에 친 글자는 fish가
# 시작하며 버릴 수 있다. wait_for_screen은 로그 전체를 보므로 옛 프롬프트에
# 맞는다 — Cmd+D 뒤의 screen> 줄만 본다.
wait_for_new_screen "$SCREENS_N" 'terminal: screen> root@\(none\) ~#' ||
  report_failure "the new pane never showed a prompt on its first row"
probe_start p 18 10 1000 1006 || report_failure "the probe never printed pd-mouse-ready-p in the right pane"
type_keys meta_l-bracket_left
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' ||
  report_failure "Cmd+[ did not move the focus to the left pane (last pane> line: '$(last_pane_line)')"
move_to "$(( $(cell_x 80) + 3 ))" "$CY" ||
  report_failure "the pointer did not reach the right pane's row 1 column 2 (last at: '$(last_at)')"
report_button 1 || report_failure "a press on the unfocused pane with mode 1000 printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=1 n=1 text=^[[<0;3;2M' ] ||
  report_failure "the press was reported as '$(last_report)', expected 'report leaf=1 n=1 text=^[[<0;3;2M' (cells count from the pane, not the grid)"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "the press did not move the focus to the right pane (last pane> line: '$(last_pane_line)')"
report_button 0 || report_failure "the release on the right pane printed no 'pointer> report' line"
GOT="$(probe_result p)"
[ "$GOT" = 'pd-mouse-got-p 18 [^[[<0;3;2M^[[<0;3;2m]' ] ||
  report_failure "the child in the right pane read '${GOT}', expected 'pd-mouse-got-p 18 [^[[<0;3;2M^[[<0;3;2m]'"
echo "panes: ${GOT}, $(last_pane_line)"

# NUL만 세어 한 번에 읽는다(AL-M1). 예전에는 파일을 두 번 읽어(NUL을 뺀 길이 · 전체 길이)
# 견줬는데, QEMU가 아직 돌며 terminal의 dump를 쓰는 동안이라 두 번 사이에 로그가 자라
# NUL이 없어도 거짓으로 빨갰다(AL-M1 사본의 pointer 부팅 B).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "the boot B serial log contains NUL bytes"
fi

echo "boot B pointer> lines:"
grep -a 'terminal: pointer>' "$LOG" | tr -d '\r'
echo "PD-M4 check PASS"
