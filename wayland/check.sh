#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# WY 체인 — terminal 안의 Wayland 서버(WY-M0)와 그 위의 둠(WY-M1). 서른다섯번째 체인.
#
# 이 게이트가 증명하는 사슬 전체(WY-M0 plan "새 체인 `wayland`"의 판정 1~9):
#   terminal이 `/run/user/<uid>/wayland-0`을 열고 셸에 `WAYLAND_DISPLAY` · `XDG_RUNTIME_DIR`을 준다
#   → 셸에서 띄운 tars-wl-test의 toplevel이 끝에 새 workspace(ws=2)를 받고, 그 색 버퍼가 정수 배율로 화면 가운데에
#     늘어나 보인다(둘레는 검정 — screendump)
#   → 그 workspace에서 친 키가 클라이언트의 wl_keyboard로 간다(evdev 코드 그대로). Cmd+1 · Cmd+2는 compositor가 먹는다
#   → 셸에서 표에 없는 Cmd 조합(Cmd+C · Cmd+Q)은 아무것도 안 친다
#   → 클라이언트를 SIGSTOP해도 셸은 친 글자를 그린다(R-WY-2)
#   → Cmd+Q가 close를 보내 클라이언트가 끝나고 workspace가 사라진다. close를 무시하는 클라이언트는 ping에도 답이 없어
#     2초 뒤 SIGKILL로 끝난다
#
# WY-M1: 부팅 2가 홈 디스크에 doom 묶음(tars-doom + Freedoom Phase 1)을 얹고 판정 10~15를 본다 — 셸에서 띄운 tars-doom이
#   320x200을 4배로 화면 가득(at=0,0) 그리고, 상태 줄의 멈춘 상자가 실측 색이며, Ctrl(evdev 29)이 권총을 쏴 탄약 숫자가 바뀌고,
#   Cmd+1 뒤의 셸이 답하고 Cmd+2로 돌아오며, Cmd+Q에 둠이 스스로 끝난다(pong · close를 포트가 받는다 — SIGKILL 없음).
#
# WY-M2(단계 C): 판정 18~21 — USB 마우스로 창 위 enter · 누름(272)이 창에 가고 클릭이 포커스를 옮기며, 셸을 누르면
#   pointer leave와 키보드 포커스가 돌아오고, 휠은 axis -10, 커서를 숨긴 창(`--hide-cursor`) 위에는 화살표가 없다.
# WY-M4: 판정 23~25(22 뒤 · 9 앞, 셸만 남은 자리) — 셸의 copy mode 복사가 창의 포커스에 offer로 가고 창의 Cmd+V가 받는다,
#   창의 Cmd+C가 셸 클립보드(`clip>`)에 들어가고 창을 닫은 뒤에도 셸의 Cmd+V로 붙는다, 읽기 끝을 닫은 파이프로 receive해도
#   terminal은 SIGPIPE로 안 죽고 셸의 `seq | head`는 여전히 SIGPIPE(141)로 끝난다.
# WY-M5: 판정 26~28(25 뒤 · 9 앞) — text input을 켠 창에서 Shift+Space가 한/영이고 `m f s`가 preedit `한`, `k`가 `한`을 확정하며
#   먹은 키는 `wl_keyboard`로 안 가고 확정이 그 뒤의 키보다 먼저 간다, 포커스를 잃으면(Cmd+[ · 셸 클릭) 조합을 그 창에 확정한다,
#   켜지 않은 창은 한글이 켜져 있어도 지금처럼 키를 받는다.
# WY-M6: 판정 29(28 뒤 · 9 앞) — `tars_menu_v1`을 bind하지 않은 창(호환 모드)은 Cmd+V를 Ctrl(0x4)+V로 받고 Cmd+1은 여전히
#   compositor의 것이다, `--native`로 bind한 창(원래 모드)은 Cmd를 Super(0x40)로 받는다. 판정 30(29 뒤 · 9 앞) — `--damage` 창의
#   32 × 32 상자만 바뀐 commit은 서버가 그 화면 사각형만 옮기고(`wl> blit … w=32 h=32`) 상자 넷과 둘레가 화면에 맞다.
# TK-M5: 판정 31(30 뒤 · 9 앞) — `tars_menu_v1` 판 2로 bind한 창(`--menu`)의 메뉴 모델이 서버에 닿고(`wl> menu … menus=2 items=5`)
#   창의 title · app_id를 서버가 담는다(`wl> title`). 단계 B: 그 창이 포커스면 위 여백의 바에 이름과 제목(`menu> bar` 줄과 좌표의
#   잉크), 셸로 옮기면 바가 빈다. 판정 35(31 뒤 · 9 앞) — 모델이 없는 창(호환)은 이름만.
# WY-M2(단계 B): 창 모드로 띄운 창은 셸 오른쪽 column이 된다(판정 16 · 17 · 22) — `wl> column`, pane 픽셀 크기의 configure
#   (activated · tiled), 포커스 slot이 창이면 키가 그 창으로, Cmd+[로 셸에 오면 activated를 잃고 keyboard leave, Cmd+R의 새
#   configure, Cmd+Q에 slot이 닫히고 셸이 전체 폭을 되찾는다. 자기 workspace를 보는 판정 2~8은 `--fullscreen`으로 띄운다.
#
# 부팅 1은 NIC 없음, 디스크 없음(plan). 디스크가 없으니 셸은 root(fish)이고 소켓은 `/run/user/0`이다. 키보드는 QEMU의
# PS/2라 기본값(auto)이 pc로 읽는다 — Cmd가 Alt 자리다(`keyboard=pc`의 맞바꿈, KK design 결정 3). 그래서 이 체인의
# Cmd는 `alt-`다(input 체인 판정 10 · 12와 같은 모양). monitor 포트는 45508 — 예약 범위(RP-M0)에서 45507 다음 빈 자리다.
#
# 화면은 1280 × 800. tars-wl-test의 기본 320x200은 4배로 화면을 꽉 채워 둘레가 없다(wl_logic_test의 첫 줄) — 그래서
# 300x200을 준다. 4배 1200 × 800이 x=40에 서고 좌우 40픽셀이 검정이다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 배율 · 옮기기 · configure 순서 · 수정키 비트 · 보낸 누름 · 2초 기한(wl_logic_test)과 app 키 경로 · 셸의 Cmd 삼킴
# (input_test)은 여기서 먼저 걸러진다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45508
REPO_ROOT="$(cd .. && pwd)"
XRES=1280
YRES=800

# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로 넘긴다.
# out/은 .gitignore 대상이고 루트 check.sh의 clean()이 지운다.
SCREENS_DIR="${REPO_ROOT}/out/wy"
mkdir -p "$SCREENS_DIR"

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

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 15초(fullscreen/check.sh와 같다).
wait_for_log() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if tlog | grep -aE -- "$pattern" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 패턴에 맞는 로그 줄이 `want`개가 될 때까지 기다린다. `pane>` 줄은 바뀐 프레임마다 찍혀 같은 줄이 여러 번 온다 —
# "있는가"가 아니라 "늘었는가"를 본다.
wait_for_count() {
  local pattern="$1" want="$2" i n
  for i in $(seq 1 150); do
    # 셈을 먼저 변수로 받는다 — 같은 줄의 `-eq`를 check.sh의 조기 종료 grep 검사(`-…q`)가 `-q`로 읽는다.
    n="$(tlog | grep -acE -- "$pattern")"
    if [ "$n" -eq "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

count_log() {
  tlog | grep -acE -- "$1"
}

# 글자열을 sendkey 이름으로 친다(소문자 · 숫자 · 공백 · `-` · `/` · `.` · `>` · `$` · `&` · `(` · `)`만).
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
      '$') keys+=(shift-4) ;;
      '&') keys+=(shift-7) ;;
      '(') keys+=(shift-9) ;;
      ')') keys+=(shift-0) ;;
      _) keys+=(shift-minus) ;;
      '|') keys+=(shift-backslash) ;;
      [A-Z]) keys+=("shift-${ch,,}") ;;
      *) keys+=("$ch") ;;
    esac
  done
  type_keys "${keys[@]}"
}

# 상자 안에서 한 색(RRGGBB, 소문자)인 픽셀의 수(TK-M5) — 메뉴 바의 이름 · 제목 글자가 그 칸에만 있는지 센다.
ppm_count() {
  perl -e '
    my ($f, $x0, $y0, $w, $h, $c) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3; my $n = 0;
    for my $y ($y0 .. $y0 + $h - 1) {
      for my $x ($x0 .. $x0 + $w - 1) { $n++ if unpack("H6", substr($d, $y * $row + $x * 3, 3)) eq $c; }
    }
    print "$n\n";' "$@"
}

# 마지막 `menu> bar ink` 줄의 칸 하나(`name` · `fg` · `other`).
bar_ink() {
  tlog | tr -d '\r' | grep -a 'terminal: menu> bar ink ' | tail -n 1 | sed -E "s/.* $1=([0-9]+).*/\1/"
}

# 화면 한 장과 상자 다섯 — 창 안 둘(가운데 위아래)과 네 모서리. 창은 x 40..1239 전체 높이다. 가운데 바로 위는 화살표
# (포인터)가 설 수 있는 자리라 피한다.
check_app_screen() {
  local tag="$1" file at got
  file="${SCREENS_DIR}/${tag}.ppm"
  screendump "$file" || report_failure "${tag}: screendump did not write ${file}"
  for at in "400 300" "840 500"; do
    # shellcheck disable=SC2086
    got="$(ppm_ink "$file" $at 16 16)"
    [ "$got" = "bg=3366cc ink=0" ] ||
      report_failure "${tag}: the client's colour is not inside the window at ${at} (${got}, want bg=3366cc ink=0)"
  done
  for at in "0 0" "1272 0" "0 792" "1272 792"; do
    # shellcheck disable=SC2086
    got="$(ppm_ink "$file" $at 8 8)"
    [ "$got" = "bg=000000 ink=0" ] ||
      report_failure "${tag}: the corner at ${at} is not black (${got}) — the window is not centred at scale 4"
  done
  echo "${tag}: 3366cc inside the window, the four corners black"
}

# 부팅 하나. 인자는 QEMU에 더할 것(부팅 2의 홈 디스크). 셸은 두 부팅 다 root다 — 부팅 2도 설정 디스크가 없어 user=가
# 없다(`no user= …, shell runs as root`). 홈 디스크만으로 init은 /home을 붙이고 묶음을 얹는다.
boot() {
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
  wait_for_screen 'root@tars ~#' || report_failure "the shell prompt never showed up"
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

# ══ 부팅 1 — 디스크 없음, tars-wl-test ═══════════════════════════════════
#
# WY-M2 단계 C: USB 마우스 하나(판정 18~21). HMP의 mouse_move · mouse_button이 그 장치로 간다(pointer 체인과 같은
# 모양 — `info mice`의 대상은 마지막에 꽂은 마우스다). 포인터는 화면 가운데(640, 400)에서 시작하고 움직이기 전에는
# 화살표가 안 보이므로, 판정 2~17의 screendump는 마우스가 없던 때와 같다.
echo "=== boot 1: ${XRES}x${YRES}, no disk (root shell), PS/2 keyboard read as pc (Cmd = alt), a USB mouse ==="
boot -usb -device usb-mouse,id=wymouse

tlog | grep -a 'terminal: keyboard> open .* kind=pc' >/dev/null ||
  report_failure "the PS/2 keyboard was not read as pc — this chain's Cmd (alt) would be wrong"

# ── 판정 1: 소켓과 셸의 환경 ─────────────────────────────────────────────
echo "=== (1) wl> listen and the shell's WAYLAND_DISPLAY XDG_RUNTIME_DIR ==="
wait_for_log 'terminal: wl> listen path=/run/user/0/wayland-0' ||
  report_failure "no 'terminal: wl> listen path=/run/user/0/wayland-0'"
if tlog | grep -a 'terminal: wl> off' >/dev/null; then
  report_failure "the server reported 'wl> off'"
fi
# 화면의 명령 줄에는 `$`가 있어 출력 줄과 안 겹친다.
# 게스트의 셸이 펼칠 글자다 — 여기서 펼치면 안 된다.
# shellcheck disable=SC2016
type_text 'echo w1 $WAYLAND_DISPLAY $XDG_RUNTIME_DIR'
type_keys ret
wait_for_screen 'w1 wayland-0 /run/user/0' ||
  report_failure "the shell does not see WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/0"
echo "(1): the socket is /run/user/0/wayland-0 and the shell knows it"

# ── 판정 2: 클라이언트가 workspace 2가 되고 그 색이 가운데에 ─────────────────
# WY-M2: 창 모드의 창은 셸 오른쪽 column이 된다. 자기 workspace(ws=2)를 보는 판정 2~8은 `--fullscreen`을 붙인다(plan 확정 14).
echo "=== (2) tars-wl-test --fullscreen opens workspace 2, its colour scaled 4x in the middle ==="
type_text 'tars-wl-test --fullscreen --color 3366CC --size 300x200 > /tmp/wl.log &'
type_keys ret
wait_for_log 'terminal: wl> client pid=[0-9]+' || report_failure "no 'wl> client' line"
wait_for_log 'terminal: wl> toplevel id=1 ws=2' || report_failure "no 'wl> toplevel id=1 ws=2'"
wait_for_log 'terminal: wl> commit id=1 buf=300x200 scale=4 at=40,0' ||
  report_failure "no 'wl> commit id=1 buf=300x200 scale=4 at=40,0'"
wait_for_count 'terminal: pane> ws=2/2 app id=1' 1 ||
  report_failure "the app workspace never came to the front (no 'pane> ws=2/2 app id=1')"
CLIENT_PID="$(tlog | grep -aoE 'terminal: wl> client pid=[0-9]+' | tail -n 1 | sed 's/.*pid=//')"
[ -n "$CLIENT_PID" ] || report_failure "could not read the client's pid"
sleep 0.5
check_app_screen app-first

# ── 판정 3: 키가 클라이언트로 간다 ───────────────────────────────────────
echo "=== (3) a goes to the client as evdev 30, Cmd+1 goes back to the shell ==="
type_keys a
wait_for_log 'terminal: wl> key code=30 state=1 to=1' || report_failure "no 'wl> key code=30 state=1 to=1'"
wait_for_log 'terminal: wl> key code=30 state=0 to=1' || report_failure "no 'wl> key code=30 state=0 to=1'"
# 셸에 아무것도 안 갔다 — app이 앞인 동안 `key>`(PTY로 바이트) 줄이 없다.
KEY_LINES="$(count_log 'terminal: key> ')"
type_keys alt-1
wait_for_log 'terminal: pane> ws=1/2 panes=1 ' || report_failure "Cmd+1 did not bring the shell back (no 'pane> ws=1/2')"
NOW_KEY_LINES="$(count_log 'terminal: key> ')"
[ "$NOW_KEY_LINES" -eq "$KEY_LINES" ] ||
  report_failure "a key typed on the app workspace reached the shell (key> lines ${KEY_LINES} -> ${NOW_KEY_LINES})"
if tlog | grep -aE 'terminal: wl> key code=2 state=1' >/dev/null; then
  report_failure "Cmd+1's 1 reached the client — the compositor should have eaten it"
fi
type_text 'cat /tmp/wl.log'
type_keys ret
wait_for_screen 'wl-test> key code=30 state=1' ||
  report_failure "the client's log has no 'wl-test> key code=30 state=1'"
wait_for_screen 'wl-test> keymap size=64755' ||
  report_failure "the client's log has no 'wl-test> keymap size=64755'"
echo "(3): a reached the client as 30, the keymap is 64,755 bytes, Cmd+1 stayed with the compositor"

# ── 판정 4: Cmd+2 · Cmd+1 왕복 ──────────────────────────────────────────
echo "=== (4) Cmd+2 shows the client again, Cmd+1 the shell ==="
type_keys alt-2
wait_for_count 'terminal: pane> ws=2/2 app id=1' 2 || report_failure "Cmd+2 did not bring the app back"
sleep 0.5
check_app_screen app-again
SHELL_FRONT="$(count_log 'terminal: pane> ws=1/2 panes=1 ')"
type_keys alt-1
wait_for_count 'terminal: pane> ws=1/2 panes=1 ' $((SHELL_FRONT + 1)) || report_failure "the second Cmd+1 did not bring the shell back"
echo "(4): Cmd+2 and Cmd+1 go back and forth"

# ── 판정 5: 셸에서 Cmd+C · Cmd+Q는 아무것도 안 친다 ─────────────────────────
#
# `echo wy5-` 뒤에 Cmd+C · Cmd+Q, 그리고 `$status`. 둘이 글자를 쳤으면 출력이 `wy5-cq0`이다. 명령 줄에는 `$`가 남아
# 출력 `wy5-0`과 안 겹친다. Cmd+Q가 셸에서 close를 보내지 않는 것도 본다.
echo "=== (5) Cmd+C and Cmd+Q type nothing in the shell ==="
CLOSE_LINES="$(count_log 'terminal: wl> close ')"
type_text 'echo wy5-'
type_keys alt-c alt-q
# 게스트의 셸이 펼칠 글자다 — 여기서 펼치면 안 된다.
# shellcheck disable=SC2016
type_text '$status'
type_keys ret
wait_for_screen 'wy5-0' || report_failure "Cmd+C or Cmd+Q typed something in the shell (no 'wy5-0')"
NOW_CLOSE_LINES="$(count_log 'terminal: wl> close ')"
[ "$NOW_CLOSE_LINES" -eq "$CLOSE_LINES" ] || report_failure "Cmd+Q in the shell sent a close"
echo "(5): the shell got neither c nor q"

# ── 판정 6: 클라이언트가 멈춰도 셸은 그린다 ───────────────────────────────
echo "=== (6) SIGSTOP the client, the shell still draws ==="
type_text "kill -STOP ${CLIENT_PID}"
type_keys ret
# 게스트의 셸이 펼칠 글자다 — 여기서 펼치면 안 된다.
# shellcheck disable=SC2016
type_text 'echo alive-$status'
type_keys ret
wait_for_screen 'alive-0' || report_failure "the shell did not draw 'alive-0' while the client was stopped"
type_text "kill -CONT ${CLIENT_PID}"
type_keys ret
echo "(6): the shell drew while the client was stopped"

# ── 판정 7: Cmd+Q가 닫는다 ──────────────────────────────────────────────
echo "=== (7) Cmd+2, Cmd+Q: the client gets close and goes, the workspace goes ==="
# 부팅의 첫 프레임이 이미 `pane> ws=1/1`을 찍었다 — 늘어난 것을 센다.
SHELL_ALONE="$(count_log 'terminal: pane> ws=1/1 panes=1 ')"
type_keys alt-2
wait_for_count 'terminal: pane> ws=2/2 app id=1' 3 || report_failure "Cmd+2 did not bring the app back before Cmd+Q"
type_keys alt-q
wait_for_log 'terminal: wl> close id=1' || report_failure "Cmd+Q sent no 'wl> close id=1'"
wait_for_log 'terminal: wl> ping id=1' || report_failure "Cmd+Q sent no 'wl> ping id=1'"
wait_for_log "terminal: wl> gone pid=${CLIENT_PID}" || report_failure "the client never went (no 'wl> gone pid=${CLIENT_PID}')"
wait_for_log 'terminal: wl> unmap id=1 ws=2' || report_failure "the workspace was not removed (no 'wl> unmap id=1 ws=2')"
wait_for_count 'terminal: pane> ws=1/1 panes=1 ' $((SHELL_ALONE + 1)) ||
  report_failure "the shell is not the only workspace after Cmd+Q (no new 'pane> ws=1/1')"
# 닫힌 클라이언트는 스스로 끝났다 — SIGKILL이 아니다. 기한은 pong이나 끝으로 버려졌다.
sleep 2.5
if tlog | grep -a 'terminal: wl> kill ' >/dev/null; then
  report_failure "the client that closed itself was killed anyway"
fi
type_text 'cat /tmp/wl.log'
type_keys ret
wait_for_screen 'wl-test> close' || report_failure "the client's log has no 'wl-test> close'"
echo "(7): close reached the client, it left by itself, the workspace is gone"

# ── 판정 8: close를 무시하는 클라이언트는 2초 뒤 SIGKILL ─────────────────────
echo "=== (8) tars-wl-test --ignore-close, Cmd+Q, 2 s, SIGKILL ==="
type_text 'tars-wl-test --fullscreen --ignore-close --color 3366CC --size 300x200 > /tmp/wl2.log &'
type_keys ret
wait_for_log 'terminal: wl> toplevel id=2 ws=2' || report_failure "the second client got no workspace (no 'wl> toplevel id=2 ws=2')"
wait_for_count 'terminal: pane> ws=2/2 app id=2' 1 || report_failure "the second client did not come to the front"
STUCK_PID="$(tlog | grep -aoE 'terminal: wl> client pid=[0-9]+' | tail -n 1 | sed 's/.*pid=//')"
if [ -z "$STUCK_PID" ] || [ "$STUCK_PID" = "$CLIENT_PID" ]; then
  report_failure "could not read the second client's pid"
fi
SHELL_ALONE="$(count_log 'terminal: pane> ws=1/1 panes=1 ')"
type_keys alt-q
wait_for_log 'terminal: wl> ping id=2' || report_failure "Cmd+Q sent no 'wl> ping id=2'"
T_PING="$(date +%s%N)"
wait_for_log "terminal: wl> kill pid=${STUCK_PID}" || report_failure "no 'wl> kill pid=${STUCK_PID}' after the ping"
T_KILL="$(date +%s%N)"
WAITED_MS=$(( (T_KILL - T_PING) / 1000000 ))
# 2초가 기한이다. 이 셸은 0.1초마다 로그를 보므로 잰 값은 실제보다 조금 늦고, 아래 1500은 너무 이른 SIGKILL을 본다.
if [ "$WAITED_MS" -lt 1500 ] || [ "$WAITED_MS" -gt 4000 ]; then
  report_failure "the SIGKILL came ${WAITED_MS} ms after the ping, want about 2000"
fi
wait_for_log "terminal: wl> gone pid=${STUCK_PID}" || report_failure "the killed client never went"
wait_for_log 'terminal: wl> unmap id=2 ws=2' || report_failure "the killed client's workspace was not removed"
wait_for_count 'terminal: pane> ws=1/1 panes=1 ' $((SHELL_ALONE + 1)) || report_failure "the shell did not come back after the SIGKILL"
type_text 'cat /tmp/wl2.log'
type_keys ret
wait_for_screen 'wl-test> close' || report_failure "the ignoring client's log has no 'wl-test> close'"
echo "(8): the client that ignored close was killed ${WAITED_MS} ms after the ping"

# ── 판정 16: 창 모드의 창은 셸 오른쪽 column이다(WY-M2) ──────────────────
#
# 셸 하나(ws=1/1)에서 `--follow-size`로 띄운다 — configure의 크기를 따라 column을 3366CC로 채운다. 화면은 여백 20 · 격자
# 155 × 47(셀 8 × 16)이고 두 column이 반씩이다: 셸 0..76열, 구분선 77열, 창 78..154열. 창의 사각형은 x 20 + 78 × 8 = 644,
# y 20, 77 × 8 = 616 × 47 × 16 = 752다. 포커스는 새 column으로 가고(Cmd+D와 같은 길) 키는 그 창의 것이다.
# 이 판정은 포커스를 키로 옮긴다 — Cmd+[ · Cmd+](이 체인의 Cmd는 alt). 포인터는 판정 18~21.
echo "=== (16) a windowed tars-wl-test opens as a column right of the shell ==="
# `--hide-cursor` — 판정 21이 이 창 위에서 화살표가 없는 것을 본다(창이 enter마다 set_cursor(NULL)).
type_text 'tars-wl-test --follow-size --hide-cursor --color 3366CC > /tmp/wl3.log &'
type_keys ret
wait_for_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1' || report_failure "(16) no 'wl> column id=… slot=1 ws=1'"
COL_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+' | tail -n 1 | sed 's/.*id=//')"
wait_for_log "terminal: wl> configure id=${COL_ID} w=616 h=752 act=1" ||
  report_failure "(16) no 'wl> configure id=${COL_ID} w=616 h=752 act=1' (the right half, focused)"
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${COL_ID} rect=78,0 77x47 " ||
  report_failure "(16) the pane> line does not show the window as slot 1 on the right half"
if tlog | grep -aE "terminal: wl> toplevel id=${COL_ID} " >/dev/null; then
  report_failure "(16) the windowed client got its own workspace"
fi
# 키가 창으로 간다 — 포커스 slot이 창이다.
type_keys a
wait_for_log "terminal: wl> key code=30 state=1 to=${COL_ID}" || report_failure "(16) a did not reach the focused column window"
# 셸로 포커스를 옮긴다 — 창은 activated를 잃고 키보드 leave를 받는다.
type_keys alt-bracket_left
wait_for_log "terminal: wl> configure id=${COL_ID} w=616 h=752 act=0" || report_failure "(16) Cmd+[ did not take activated away"
wait_for_log 'terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' || report_failure "(16) Cmd+[ did not focus the shell on the left half"
sleep 0.5
SHOT16="${SCREENS_DIR}/column.ppm"
screendump "$SHOT16" || report_failure "(16) screendump did not write ${SHOT16}"
for at in "900 300" "1100 600"; do
  # shellcheck disable=SC2086
  got="$(ppm_ink "$SHOT16" $at 32 32)"
  [ "$got" = "bg=3366cc ink=0" ] || report_failure "(16) the right column at ${at} is not the window's colour (${got})"
done
# 왼쪽 반 첫 행(프롬프트)에 글자가 있다.
# shellcheck disable=SC2086
got="$(ppm_ink "$SHOT16" 20 20 160 16)"
case "$got" in
  *" ink=0") report_failure "(16) the left half has no prompt on its first row (${got})" ;;
esac
type_text 'cat /tmp/wl3.log'
type_keys ret
wait_for_screen 'wl-test> configure w=616 h=752 states=4,5,6,7,8' ||
  report_failure "(16) the client did not get 616x752 with activated and the four tiled states"
# enter · leave · a의 누름과 뗌은 앞 클라이언트의 로그(판정 3)에도 있어 화면 글자로는 못 가른다 — 이 로그의 줄 수를 센다.
# `type_text`에 `=`가 없어 정규식의 `.`로 그 자리를 맞춘다.
type_text 'echo c16-(grep -c enter /tmp/wl3.log)-(grep -c leave /tmp/wl3.log)-(grep -c code.30 /tmp/wl3.log)'
type_keys ret
wait_for_screen 'c16-1-1-2' || report_failure "(16) the client's log does not have one enter, one leave and a's press and release"
echo "(16): the window is slot 1 on the right half (616x752, tiled), took a, and left when Cmd+[ focused the shell"

# ── 포인터(WY-M2 단계 C) ────────────────────────────────────────────────
#
# 판정 16 끝에 키보드 포커스는 셸(왼쪽)이고 창은 오른쪽 column(x 644..1259, y 20..771)이다. 창 가운데 (952, 396)은
# surface 좌표 (308, 376)이다(1배로 채웠다). 움직임은 100씩 나눠 보내므로 한 회차에 여럿이 모일 수 있다 — enter의 좌표는
# 회차마다 다르고, 마지막 자리(308, 376)는 enter나 motion 줄(처음 다섯) 중 하나에 있다.

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

# 포인터를 (X, Y)로 — pointer 체인의 move_to와 같다. 첫 움직임 전에는 at 줄이 없으므로 가운데(640, 400)에서 시작한다.
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

# ── 판정 18: 창 위의 포인터 · 누름 — enter, button, 그리고 클릭이 포커스를 옮긴다 ─────────
echo "=== (18) the pointer enters the window, a click focuses it and its keys go there ==="
tlog | grep -a 'terminal: pointer> open ' >/dev/null || report_failure "(18) terminal did not open the USB mouse"
move_to 952 396 || report_failure "(18) the pointer did not reach 952,396 (last at: $(last_at))"
wait_for_log "terminal: wl> pointer enter id=${COL_ID}" || report_failure "(18) no 'wl> pointer enter id=${COL_ID}'"
hmp "mouse_button 1"
wait_for_log "terminal: wl> button id=${COL_ID} code=272 state=1" || report_failure "(18) the press did not reach the window"
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${COL_ID} " || report_failure "(18) the click did not focus the window's slot"
wait_for_count "terminal: wl> configure id=${COL_ID} w=616 h=752 act=1" 2 || report_failure "(18) the click did not give the window activated"
hmp "mouse_button 0"
wait_for_log "terminal: wl> button id=${COL_ID} code=272 state=0" || report_failure "(18) the release did not reach the window"
type_keys b
wait_for_log "terminal: wl> key code=48 state=1 to=${COL_ID}" || report_failure "(18) after the click b did not go to the window"
echo "(18): the pointer entered the window, the click reached it as 272 and focused its slot, b went to it"

# ── 판정 19: 셸 pane을 누르면 창은 pointer leave와 키보드 leave, 셸이 다시 받는다 ─────────
echo "=== (19) a click on the shell takes the pointer and the keyboard back ==="
move_to 200 200 || report_failure "(19) the pointer did not reach 200,200"
wait_for_log "terminal: wl> pointer leave id=${COL_ID}" || report_failure "(19) no 'wl> pointer leave id=${COL_ID}'"
hmp "mouse_button 1"
hmp "mouse_button 0"
wait_for_count "terminal: wl> configure id=${COL_ID} w=616 h=752 act=0" 2 || report_failure "(19) the click on the shell did not take activated away"
wait_for_count 'terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' 2 || report_failure "(19) the click did not focus the shell"
# 셸 pane 위의 누름은 창에 안 갔다.
[ "$(count_log "terminal: wl> button id=${COL_ID} ")" -eq 2 ] || report_failure "(19) a press on the shell reached the window"
type_text 'echo back'
type_keys ret
wait_for_screen '^back$|\| back( \||$)' || report_failure "(19) the shell did not draw 'back' after the click"
echo "(19): the window got pointer leave, the click focused the shell and it answered"

# ── 판정 20: 창 위의 휠은 axis — 포커스는 안 바뀐다 ───────────────────────
echo "=== (20) the wheel over the window is an axis event ==="
move_to 952 396 || report_failure "(20) the pointer did not come back to 952,396"
wait_for_count "terminal: wl> pointer enter id=${COL_ID}" 2 || report_failure "(20) no second pointer enter"
hmp "mouse_move 0 0 1"
wait_for_log "terminal: wl> axis id=${COL_ID} v=-10" || report_failure "(20) the wheel did not reach the window as axis -10"
echo "(20): one notch up reached the window as axis -10"

# ── 판정 21: 커서를 숨긴 창 위에는 화살표가 없다 ──────────────────────────
#
# 창이 enter마다 set_cursor(NULL)을 보냈다(`--hide-cursor`). 포인터는 (952, 396)에 있다 — 화살표(그리면 그 자리에서
# 오른쪽 아래로)가 있을 상자가 창 색 하나다.
echo "=== (21) no arrow over a window that hid its cursor ==="
wait_for_log "terminal: wl> cursor id=${COL_ID} hidden=1" || report_failure "(21) no 'wl> cursor id=${COL_ID} hidden=1'"
sleep 0.5
SHOT21="${SCREENS_DIR}/hidden-arrow.ppm"
screendump "$SHOT21" || report_failure "(21) screendump did not write ${SHOT21}"
got="$(ppm_ink "$SHOT21" 952 396 16 24)"
[ "$got" = "bg=3366cc ink=0" ] || report_failure "(21) the box under the pointer is not just the window's colour (${got}) — the arrow is drawn"
echo "(21): the arrow is not drawn over the window that hid its cursor"
# 클라이언트가 본 포인터 줄(이 로그의 수를 센다 — 판정 3의 화면 글자와 안 섞이게). 키보드 포커스는 판정 19부터 셸이다
# (휠은 포커스를 안 옮긴다).
type_text 'echo c21-(grep -c pointer.enter /tmp/wl3.log)-(grep -c pointer.leave /tmp/wl3.log)-(grep -c code.272 /tmp/wl3.log)-(grep -c axis.v.-10 /tmp/wl3.log)-(grep -c x.308.y.376 /tmp/wl3.log)'
type_keys ret
wait_for_screen 'c21-2-1-2-1-[1-9]' || report_failure "(21) the client's log does not have two pointer enters, one leave, a press and release, the axis and 308,376"

# ── 판정 17: Cmd+R로 폭이 바뀌면 configure가 다시 간다 ─────────────────────
#
# 창 column에 포커스를 두고 Cmd+R — half 다음은 full(SW-M3의 순환)이라 창이 격자 전체 폭 155 × 8 = 1240이 된다.
echo "=== (17) Cmd+R on the window's column sends a new configure ==="
type_keys alt-bracket_right
wait_for_log "terminal: wl> configure id=${COL_ID} w=616 h=752 act=1" || report_failure "(17) Cmd+] did not give activated back"
type_keys alt-r
wait_for_log "terminal: wl> configure id=${COL_ID} w=1240 h=752 act=1" ||
  report_failure "(17) Cmd+R did not send 'wl> configure id=${COL_ID} w=1240 h=752 act=1'"
wait_for_log "terminal: pane> ws=1/1 panes=2 focus=1 slot=1 app id=${COL_ID} rect=0,0 155x47 " ||
  report_failure "(17) the pane> line did not follow the full-width column"
echo "(17): Cmd+R widened the window's column to 1240 and the client was told"

# ── 판정 22: 창 slot의 Cmd+Q — 닫히고 column이 당겨진다 ─────────────────────
echo "=== (22) Cmd+Q on the window's slot closes it and the shell takes the whole width ==="
type_keys alt-q
wait_for_log "terminal: wl> close id=${COL_ID}" || report_failure "(22) Cmd+Q sent no 'wl> close id=${COL_ID}'"
wait_for_log "terminal: wl> unmap id=${COL_ID} ws=1 slot=1" || report_failure "(22) the slot was not removed"
wait_for_log 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 ' || report_failure "(22) the shell did not take the whole width back"
# 판정 8의 SIGKILL 한 줄 말고는 없어야 한다 — 이 창은 close에 스스로 끝났다.
sleep 2.5
KILLS="$(count_log 'terminal: wl> kill ')"
[ "$KILLS" -eq 1 ] || report_failure "(22) the closed column window was killed (wl> kill lines ${KILLS}, want the one from (8))"
type_text 'echo c22-(grep -c w.1240 /tmp/wl3.log)-(grep -c close /tmp/wl3.log)'
type_keys ret
wait_for_screen 'c22-1-1' || report_failure "(22) the client's log does not have the 1240 configure and the close"
echo "(22): Cmd+Q closed the window, its column went and the shell is whole again"

# ── 판정 23: 셸 → 앱 — 셸에서 복사한 것을 창이 붙인다(WY-M4) ─────────────────
# 셸만 남은 자리다(판정 22 끝). 출력 줄 `wy23-clip`을 copy mode(`Cmd+Shift+C` · `k` · `Shift+V` · `y`)로 잡는다 — 친 줄
# `echo wy23-clip`과 갈리는 것은 화면 덤프에서 출력 줄만 ` | `로 시작해서다. 창은 `--paste --copy`로 띄워 판정 24까지 쓴다.
echo "=== (23) a copy in the shell is offered to the window and pasted there ==="
type_text 'echo wy23-clip'
type_keys ret
wait_for_screen '\| wy23-clip( \||$)' || report_failure "(23) the shell did not print wy23-clip"
type_keys alt-shift-c
type_keys k shift-v y
wait_for_log 'terminal: clip> len=9 text=wy23-clip' || report_failure "(23) copy mode did not copy wy23-clip (no 'clip> len=9 text=wy23-clip')"
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size --paste --copy wy24-app > /tmp/wl4.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(23) the clipboard client did not open as a column"
CLIP_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
# 포커스를 받을 때 키보드 `enter` 바로 앞에서 offer가 간다(design 결정 34).
wait_for_log "terminal: wl> offer to=${CLIP_ID} len=9" || report_failure "(23) the window got no offer of the shell's copy (no 'wl> offer to=${CLIP_ID} len=9')"
type_keys alt-v
wait_for_log "terminal: wl> receive to=${CLIP_ID} mime=text/plain;charset=utf-8 len=9 first=9" ||
  report_failure "(23) Cmd+V in the window did not receive the 9 bytes in the request handler"
echo "(23): wy23-clip was offered to window ${CLIP_ID} on focus and written in one go on its receive"

# ── 판정 24: 앱 → 셸 — 창에서 복사한 것을 셸이 붙인다, 창이 끝난 뒤에도(WY-M4) ─────────
echo "=== (24) a copy in the window reaches the shell's clipboard, and pastes after the window is gone ==="
type_keys alt-c
wait_for_log "terminal: wl> selection from=${CLIP_ID} mime=text/plain;charset=utf-8" ||
  report_failure "(24) Cmd+C in the window set no selection (no 'wl> selection from=${CLIP_ID} mime=text/plain;charset=utf-8')"
wait_for_log 'terminal: clip> len=8 text=wy24-app' || report_failure "(24) the window's copy did not reach the shell's clipboard"
# 사본이 바뀌면 포커스 클라이언트에도 새 offer다(그 source 자신).
wait_for_log "terminal: wl> offer to=${CLIP_ID} len=8" || report_failure "(24) the window was not offered the new selection"
WHOLE="$(count_log 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 ')"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${CLIP_ID} ws=1 slot=1" || report_failure "(24) Cmd+Q did not close the clipboard window"
wait_for_count 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 ' $((WHOLE + 1)) || report_failure "(24) the shell did not take the whole width back"
type_text 'echo '
type_keys alt-v
wait_for_log 'terminal: clip> paste len=8 bracketed=1' || report_failure "(24) Cmd+V in the shell did not paste the 8 bytes"
type_keys ret
wait_for_screen '\| wy24-app( \||$)' || report_failure "(24) the shell did not print wy24-app on its own line"
# 클라이언트가 본 것: 판정 23의 붙여넣기 하나, 서버의 send 하나, offer 둘(포커스 · 자기 복사 뒤).
type_text 'echo c24-(grep -c paste.len.9.text.wy23-clip /tmp/wl4.log)-(grep -c send.mime /tmp/wl4.log)-(grep -c offer.mimes /tmp/wl4.log)'
type_keys ret
wait_for_screen '\| c24-1-1-2' || report_failure "(24) the client's log does not have the paste of wy23-clip, one send and two offers"
echo "(24): wy24-app went from the window to the shell's clipboard and pasted after the window closed"

# ── 판정 25: SIGPIPE — terminal은 안 죽고 셸의 자식은 전과 같다(WY-M4, design 결정 35) ─────
# (가) 읽기 끝을 먼저 닫은 파이프로 receive하는 창(`--paste-drop`). 서버의 쓰기는 반드시 EPIPE다 — SIGPIPE가 기본 처분이면
# terminal(셸 전부)이 여기서 죽어 `receive closed` 줄이 안 나온다.
echo "=== (25) a receive on a closed pipe does not kill terminal, and the shell's children still die of SIGPIPE ==="
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size --paste-drop > /tmp/wl5.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(25) the drop client did not open as a column"
DROP_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
wait_for_log "terminal: wl> offer to=${DROP_ID} len=8" || report_failure "(25) the drop client got no offer"
type_keys alt-v
wait_for_log "terminal: wl> receive closed to=${DROP_ID}" || report_failure "(25) no 'wl> receive closed to=${DROP_ID}' — did terminal die of SIGPIPE?"
WHOLE="$(count_log 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 ')"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${DROP_ID} ws=1 slot=1" || report_failure "(25) Cmd+Q did not close the drop client"
wait_for_count 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 155x47 ' $((WHOLE + 1)) || report_failure "(25) the shell did not take the whole width back"
# (나) 셸의 자식에게는 기본으로 되돌렸다(`pty.spawn`). seq가 SIGPIPE로 끝나면 fish는 141이다 — 무시가 새어 들어갔으면
# seq는 EPIPE를 만나 "write error"를 내고 1로 끝난다.
type_text 'seq 1000000 | head -n1'
type_keys ret
# 게스트의 fish가 펼칠 글자다 — 여기서 펼치면 안 된다.
# shellcheck disable=SC2016
type_text 'echo p25-$pipestatus'
type_keys ret
wait_for_screen 'p25-141 p25-0' || report_failure "(25) seq in a pipe did not die of SIGPIPE (want p25-141 p25-0)"
echo "(25): terminal survived an EPIPE on the clipboard pipe, and the shell's seq | head still ends by SIGPIPE (141)"

# ── 판정 26: 텍스트 입력을 켠 창의 조합 · 확정, 같은 키가 두 번 안 간다(WY-M5) ─────────────
# 셸만 남은 자리다(판정 25 끝). 디스크가 없으니 자판은 신세벌 PCS다(`hangul layout=shin_pcs` — 단계 A 실측 3). `m f s` = 한,
# 다음 `k`(초성 ㄱ)가 `한`을 확정하고 `ㄱ`, Space는 `ㄱ`을 확정한 뒤 키로 간다. 먹은 키(m f s k)는 서버의 `wl> key` 줄에 없다
# (design 결정 41). 한/영은 창 안에서 친 Shift+Space다 — 켠 창에서는 셸과 같은 전환 키가 돈다(결정 40).
echo "=== (26) a window with text input composes and commits, and the eaten keys are not sent ==="
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size --text-input > /tmp/wl6.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(26) the text-input client did not open as a column"
TI_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
# 단계 A의 넘길 것 — enable을 기다린 뒤에 전환한다(그 전의 키는 켜지 않은 창의 길로 간다).
wait_for_log "terminal: wl> ti enable to=${TI_ID}([^0-9]|$)" || report_failure "(26) the window did not enable its text input (no 'wl> ti enable to=${TI_ID}')"
ONS="$(count_log 'terminal: hangul> on=true')"
type_keys shift-spc
wait_for_count 'terminal: hangul> on=true' $((ONS + 1)) || report_failure "(26) Shift+Space in the window did not turn hangul on"
[ "$(count_log "terminal: wl> key code=57 state=1 to=${TI_ID}([^0-9]|$)")" -eq 0 ] || report_failure "(26) the Space of Shift+Space reached the window"
type_keys m f s
wait_for_log "terminal: wl> ime to=${TI_ID} commit=\(none\) preedit=한" || report_failure "(26) m f s did not compose 한 (no 'wl> ime to=${TI_ID} commit=(none) preedit=한')"
wait_for_log 'terminal: hangul> on=true preedit=한' || report_failure "(26) no 'hangul> on=true preedit=한'"
type_keys k
wait_for_log "terminal: wl> ime to=${TI_ID} commit=한 preedit=ㄱ" || report_failure "(26) k did not commit 한 and start ㄱ"
type_keys spc
wait_for_log "terminal: wl> key code=57 state=1 to=${TI_ID}([^0-9]|$)" || report_failure "(26) the Space after ㄱ did not reach the window"
# 확정이 키보다 먼저다 — 그 창의 ime · key 줄에서 `commit=ㄱ` 바로 다음 줄이 Space의 누름이다.
NEXT="$(tlog | tr -d '\r' | grep -aE "terminal: wl> (ime|key) .*to=${TI_ID}( |$)" | grep -aA1 'commit=ㄱ preedit=(none)$' | tail -n 1)"
[ "$NEXT" = "terminal: wl> key code=57 state=1 to=${TI_ID}" ] || report_failure "(26) after the commit of ㄱ came '${NEXT}', want the Space press"
EATEN="$(count_log "terminal: wl> key code=(50|33|31|37) state=1 to=${TI_ID}([^0-9]|$)")"
[ "$EATEN" -eq 0 ] || report_failure "(26) ${EATEN} eaten key press(es) (m f s k) also went to the window as keys"
echo "(26): 한 composed as preedit, committed by k with ㄱ next, ㄱ committed before the Space key, no jamo key reached the window"

# ── 판정 27: 포커스를 잃으면 조합을 확정한다 — chord 길과 클릭 길(WY-M5, design 결정 42) ─────────
# (가) `m f`(하) 뒤의 Cmd+[ — 한글 층의 Cmd 갈래가 chord보다 먼저 확정한다. (나) 다시 창으로 와서 `m`(ㅎ) 뒤에 셸을 누른다 —
# 포인터는 키가 아니므로 바퀴 끝의 `focusTo`가 옛 창에 확정한다. 둘 다 text_input `leave` · 키보드 `leave` 앞이다(클라이언트 로그).
echo "=== (27) losing the focus commits the composition, by Cmd+[ and by a click on the shell ==="
type_keys m f
wait_for_log "terminal: wl> ime to=${TI_ID} commit=\(none\) preedit=하" || report_failure "(27) m f did not compose 하"
type_keys alt-bracket_left
wait_for_log "terminal: wl> ime to=${TI_ID} commit=하 preedit=\(none\)" || report_failure "(27) Cmd+[ did not commit 하 to the window"
type_keys alt-bracket_right
wait_for_count "terminal: wl> ti enable to=${TI_ID}([^0-9]|$)" 2 || report_failure "(27) the window did not enable its text input again"
type_keys m
wait_for_log "terminal: wl> ime to=${TI_ID} commit=\(none\) preedit=ㅎ" || report_failure "(27) m did not compose ㅎ"
move_to 200 200 || report_failure "(27) the pointer did not reach 200,200"
hmp "mouse_button 1"
hmp "mouse_button 0"
wait_for_log "terminal: wl> ime to=${TI_ID} commit=ㅎ preedit=\(none\)" || report_failure "(27) the click on the shell did not commit ㅎ to the window"
wait_for_log 'terminal: hangul> on=true preedit=\(none\)' || report_failure "(27) the composition did not end"
# 셸에서 끈다(셸의 Shift+Space) — 아래 명령 줄은 영문이어야 한다.
OFFS="$(count_log 'terminal: hangul> on=false')"
type_keys shift-spc
wait_for_count 'terminal: hangul> on=false' $((OFFS + 1)) || report_failure "(27) Shift+Space in the shell did not turn hangul off"
# 클라이언트가 본 것: 확정 넷(한 · ㄱ · 하 · ㅎ), 먹은 키 m(50)의 누름 0, serial이 안 맞은 done 0, 그리고 `ti leave` 둘이 저마다
# 확정 바로 뒤(-B3: commit · preedit · done)이고 키보드 `leave` 바로 앞이다. `ti enter`에도 `enter`가 들어 있어 낱말로 세지 않는다.
type_text 'echo c27-(grep -c commit.text /tmp/wl6.log)-(grep -c key.code.50.state.1 /tmp/wl6.log)-(grep -c match.0 /tmp/wl6.log)-(grep -B3 ti.leave /tmp/wl6.log | grep -c commit.text)-(grep -A1 ti.leave /tmp/wl6.log | grep -cx wl-test..leave)'
type_keys ret
wait_for_screen '\| c27-4-0-0-2-2' || report_failure "(27) the client's log is not commits 4, key 50 presses 0, mismatched done 0, commit before ti leave 2, keyboard leave after ti leave 2"
type_keys alt-bracket_right
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${TI_ID} ws=1 slot=1" || report_failure "(27) Cmd+Q did not close the text-input window"
echo "(27): Cmd+[ and a click on the shell both committed the composition to the window before its leave"

# ── 판정 28: 텍스트 입력을 켜지 않은 창은 지금처럼 키다(WY-M5, design 결정 40) ─────────────────
# 한글은 셸에서 켠다 — 켜지 않은 창에서는 전환 키도 안 돈다(둠의 Ctrl tap이 한/영을 뒤집으면 안 된다). 그 창에서 `m`은 evdev 50의
# 누름으로 가고 `wl> ime`는 하나도 없다. Shift+Space도 그 창에는 그냥 키(Space 57)다.
echo "=== (28) a window without text input still gets keys, with hangul on ==="
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size > /tmp/wl7.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(28) the plain client did not open as a column"
PLAIN_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
type_keys alt-bracket_left
wait_for_log "terminal: wl> configure id=${PLAIN_ID} w=[0-9]+ h=[0-9]+ act=0" || report_failure "(28) Cmd+[ did not take the keys from the plain window"
ONS="$(count_log 'terminal: hangul> on=true')"
type_keys shift-spc
wait_for_count 'terminal: hangul> on=true' $((ONS + 1)) || report_failure "(28) Shift+Space in the shell did not turn hangul on"
ACTS="$(count_log "terminal: wl> configure id=${PLAIN_ID} w=[0-9]+ h=[0-9]+ act=1")"
type_keys alt-bracket_right
wait_for_count "terminal: wl> configure id=${PLAIN_ID} w=[0-9]+ h=[0-9]+ act=1" $((ACTS + 1)) || report_failure "(28) Cmd+] did not focus the plain window"
HANGULS="$(count_log 'terminal: hangul> on=')"
type_keys m shift-spc
wait_for_log "terminal: wl> key code=50 state=1 to=${PLAIN_ID}([^0-9]|$)" || report_failure "(28) m did not reach the plain window as a key"
wait_for_log "terminal: wl> key code=57 state=1 to=${PLAIN_ID}([^0-9]|$)" || report_failure "(28) Shift+Space did not reach the plain window as keys"
[ "$(count_log "terminal: wl> key code=50 state=1 to=${PLAIN_ID}([^0-9]|$)")" -eq 1 ] || report_failure "(28) m reached the plain window more than once"
[ "$(count_log "terminal: wl> ime to=${PLAIN_ID} ")" -eq 0 ] || report_failure "(28) the plain window got an ime line"
# 켜지 않은 창의 키 길은 한글 층을 안 지난다 — `hangul>` 줄이 하나도 안 는다(Shift+Space도 한/영이 아니다).
[ "$(count_log 'terminal: hangul> on=')" -eq "$HANGULS" ] || report_failure "(28) the hangul state changed in the plain window"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${PLAIN_ID} ws=1 slot=1" || report_failure "(28) Cmd+Q did not close the plain window"
OFFS="$(count_log 'terminal: hangul> on=false')"
type_keys shift-spc
wait_for_count 'terminal: hangul> on=false' $((OFFS + 1)) || report_failure "(28) Shift+Space in the shell did not turn hangul off"
echo "(28): with hangul on, the plain window got m and Shift+Space as keys and no ime"

# ── 판정 29: 호환 모드 — Cmd가 Ctrl로 보인다, `tars_menu_v1`을 bind한 창은 Super(WY-M6, design 결정 45 · 46) ─────────
# 셸만 남은 자리다(판정 28 끝). (가) 기본 창(호환)에 Cmd+V(`alt-v`) — 키는 47 그대로 가고 클라이언트가 받는 수정키는 Ctrl(0x4)이지
# Super(0x40)가 아니다. (다) 같은 창에서 Cmd+1은 여전히 표의 chord라 키 2가 창에 안 간다. (나) `--native` 창(원래 모드)은 Cmd+V를
# Super(0x40)로 받고 서버가 `wl> keys pid=N native` · `wl> keys to=ID mode=native`를 찍는다. 클라이언트 줄은 `grep -w`로 센다 —
# `0x4`가 `0x40`에 걸리지 않는다(셸에서 `$` 없이 쓰려는 것). `=`는 `type_text`가 못 치므로 `.`이다(판정 24 · 27과 같다).
echo "=== (29) compat mode: Cmd reaches a plain window as Ctrl, a native window as Super ==="
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size > /tmp/wl8.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(29) the compat client did not open as a column"
COMPAT_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
wait_for_log "terminal: wl> configure id=${COMPAT_ID} w=[0-9]+ h=[0-9]+ act=1" || report_failure "(29) the compat window did not get the keys"
# Cmd+1을 먼저 친다 — 키는 차례로 처리되므로 뒤의 Cmd+V(47)가 창에 닿은 때에는 Cmd+1의 1(evdev 2)도 갔다면 이미 갔다.
type_keys alt-1 alt-v
wait_for_log "terminal: wl> key code=47 state=1 to=${COMPAT_ID}([^0-9]|$)" || report_failure "(29) Cmd+V did not reach the compat window as 47"
[ "$(count_log "terminal: wl> key code=2 state=1 to=${COMPAT_ID}([^0-9]|$)")" -eq 0 ] || report_failure "(29) Cmd+1 reached the compat window — the table chord must stay with the compositor"
[ "$(count_log 'terminal: wl> keys pid=[0-9]+ native')" -eq 0 ] || report_failure "(29) a client without tars_menu_v1 was taken as native"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${COMPAT_ID} ws=1 slot=1" || report_failure "(29) Cmd+Q did not close the compat window"
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size --native > /tmp/wl9.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(29) the native client did not open as a column"
NATIVE_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
wait_for_log 'terminal: wl> keys pid=[0-9]+ native' || report_failure "(29) no 'wl> keys pid=N native' for the client that bound tars_menu_v1"
wait_for_log "terminal: wl> keys to=${NATIVE_ID} mode=native" || report_failure "(29) no 'wl> keys to=${NATIVE_ID} mode=native' when it got the keys"
type_keys alt-v
wait_for_log "terminal: wl> key code=47 state=1 to=${NATIVE_ID}([^0-9]|$)" || report_failure "(29) Cmd+V did not reach the native window as 47"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${NATIVE_ID} ws=1 slot=1" || report_failure "(29) Cmd+Q did not close the native window"
# 클라이언트가 본 것: 호환 창은 Ctrl 1번 이상 · Super 0, 원래 창은 Super 1번 이상 · Ctrl 0, 그리고 `native` 한 줄.
type_text 'echo c29-(grep -cw depressed.0x4 /tmp/wl8.log)-(grep -cw depressed.0x40 /tmp/wl8.log)-(grep -cw depressed.0x40 /tmp/wl9.log)-(grep -cw depressed.0x4 /tmp/wl9.log)-(grep -cx wl-test..native /tmp/wl9.log)'
type_keys ret
wait_for_screen '\| c29-[1-9]-0-[1-9]-0-1' || report_failure "(29) the clients' logs do not show Ctrl in the compat window and Super in the native one"
echo "(29): Cmd+V reached the compat window as Ctrl+V and the native window as Super+V, Cmd+1 stayed with the compositor"

# ── 판정 30: damage — 바뀐 상자만 옮긴다(WY-M6 단계 B, design 결정 47) ─────────────────────────
# 셸만 남은 자리다(판정 29 끝). `--damage` 창은 판정 16과 같은 자리(x 644 · y 20, 616 × 752)에 3366CC로 서고, 첫 그림 뒤에는 32 × 32
# 상자만 다시 그려 그 자리만 damage로 알린다(tars-wl-test 머리). 걸음 3~10은 상자 A(창의 0,0)만이라 서버는 화면 (644, 20)의 32 × 32만
# 옮긴다 — `wl> blit id=ID x=644 y=20 w=32 h=32` 여덟 줄. 그다음 screendump: A는 마지막 색 00FF00, B(64,0) · C(0,64) · D(64,64)는 흰색,
# 상자 밖은 3366CC. 둘레 검정 칠하기가 없는 부분 길이 clip 밖을 건드리면 판정 9(verify의 clip 판정)가 빨개진다.
echo "=== (30) damage: only the changed boxes are copied ==="
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size --damage --color 3366CC > /tmp/wl10.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(30) the damage client did not open as a column"
DMG_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
wait_for_count "terminal: wl> blit id=${DMG_ID} x=644 y=20 w=32 h=32 " 8 ||
  report_failure "(30) fewer than eight partial blits of box A (no 8 x 'wl> blit id=${DMG_ID} x=644 y=20 w=32 h=32')"
wait_for_log 'terminal: wl> frame part us=[0-9]+ px=0([^0-9]|$)' || report_failure "(30) no 'wl> frame part' line for a frame with a partial blit"
sleep 0.5
SHOT30="${SCREENS_DIR}/damage.ppm"
screendump "$SHOT30" || report_failure "(30) screendump did not write ${SHOT30}"
for spot in "648 24 00ff00 A" "712 24 ffffff B" "648 88 ffffff C" "712 88 ffffff D" "900 300 3366cc outside"; do
  read -r sx sy want name <<<"$spot"
  got="$(ppm_ink "$SHOT30" "$sx" "$sy" 24 24)"
  [ "$got" = "bg=${want} ink=0" ] || report_failure "(30) box ${name} at ${sx},${sy} is not ${want} (${got})"
done
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${DMG_ID} ws=1 slot=1" || report_failure "(30) Cmd+Q did not close the damage window"
# 클라이언트가 한 것: 걸음 열 줄과 몰아친 commit 둘(버퍼가 모자라 하나로 그친 적이 없다).
type_text 'echo c30-(grep -c damage.step /tmp/wl10.log)-(grep -c burst.2 /tmp/wl10.log)'
type_keys ret
wait_for_screen '\| c30-10-1' || report_failure "(30) the client's log does not have ten damage steps with a two-commit burst"
echo "(30): box A was copied alone eight times, all four boxes and the window around them are on screen"

# ── 판정 31: 메뉴 모델 — 판 2의 `get_menu`와 title · app_id(TK-M5 단계 A, plan 확정 3 · 4 · 13 · 14) ─────────────────────
# 셸만 남은 자리다(판정 30 끝). 단계 A는 그리기가 없다 — 이 판정은 줄만 본다(바의 화면은 단계 B가 같은 번호에 더한다). `--menu` 창은 판 2로
# bind하고(원래 모드 — `native`) 첫 commit 전에 고정 모델(File 셋 · Edit 둘, 구분선 포함 다섯 칸)을 commit한다 — 서버가
# `wl> menu id=ID menus=2 items=5`, 그리고 set_title · set_app_id를 담아 `wl> title id=ID app_id=tars-wl-test title=tars-wl-test`.
# 실측 8: 그 창에 Cmd+Shift+/(`alt-shift-slash`)를 친다 — 단계 A에는 여는 키가 없으므로 표 밖 Cmd 조합이라 창에 Super+Shift로
# 간다(evdev 53, 클라이언트의 수정키 0x41). 줄 수만 찍고 판정하지 않는다(단계 C에서 서버가 먹는 키가 된다).
echo "=== (31) menu model: a version 2 client's model and the window's name reach the server ==="
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
NATIVES="$(count_log 'terminal: wl> keys pid=[0-9]+ native')"
type_text 'tars-wl-test --follow-size --menu > /tmp/wl11.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(31) the menu client did not open as a column"
MENU_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
wait_for_count 'terminal: wl> keys pid=[0-9]+ native' $((NATIVES + 1)) || report_failure "(31) the menu client did not come in native mode"
wait_for_log "terminal: wl> menu id=${MENU_ID} menus=2 items=5([^0-9]|$)" || report_failure "(31) no 'wl> menu id=${MENU_ID} menus=2 items=5'"
wait_for_log "terminal: wl> title id=${MENU_ID} app_id=tars-wl-test title=tars-wl-test" ||
  report_failure "(31) no 'wl> title id=${MENU_ID} app_id=tars-wl-test title=tars-wl-test'"
wait_for_log "terminal: wl> configure id=${MENU_ID} w=[0-9]+ h=[0-9]+ act=1" || report_failure "(31) the menu window did not get the keys"
# 단계 B — 화면. 포커스 창의 바: 이름 `tars-wl-test`(12칸)는 x 20부터 96 px, 두 칸 띄고 `File`(4칸) x 132, 두 칸 띄고 `Edit` x 180(menubar_test의 셈과
# 같은 좌표). 글자 줄은 y 2..18. 이름 칸의 MENU_NAME(e8d8b0) 수 = 덤프의 `name=`, File · Edit 칸의 MENU_FG(d0d8e0) 합 = 덤프의 `fg=`, 그리고 위 띠
# 전체(1280 × 20)의 두 색 수가 그 칸들의 수와 같다(다른 자리에 글자가 없다).
wait_for_log "terminal: menu> bar id=${MENU_ID} name=tars-wl-test titles=File,Edit" ||
  report_failure "(31) no 'menu> bar id=${MENU_ID} name=tars-wl-test titles=File,Edit'"
sleep 0.5
SHOT31="${SCREENS_DIR}/menu-bar.ppm"
screendump "$SHOT31" || report_failure "(31) screendump did not write ${SHOT31}"
B_NAME="$(bar_ink name)"
B_FG="$(bar_ink fg)"
S_NAME="$(ppm_count "$SHOT31" 20 2 96 16 e8d8b0)"
S_FILE="$(ppm_count "$SHOT31" 132 2 32 16 d0d8e0)"
S_EDIT="$(ppm_count "$SHOT31" 180 2 32 16 d0d8e0)"
A_NAME="$(ppm_count "$SHOT31" 0 0 1280 20 e8d8b0)"
A_FG="$(ppm_count "$SHOT31" 0 0 1280 20 d0d8e0)"
echo "(31) bar ink: dump name=${B_NAME} fg=${B_FG}; screen name box ${S_NAME}, File ${S_FILE}, Edit ${S_EDIT}; band name ${A_NAME} fg ${A_FG}"
[ "${S_NAME:-0}" -gt 0 ] && [ "$S_NAME" = "$B_NAME" ] && [ "$A_NAME" = "$S_NAME" ] ||
  report_failure "(31) the name's ink is not in its box at x 20 (box ${S_NAME}, dump ${B_NAME}, band ${A_NAME})"
[ "${S_FILE:-0}" -gt 0 ] && [ "${S_EDIT:-0}" -gt 0 ] && [ "$((S_FILE + S_EDIT))" = "$B_FG" ] && [ "$A_FG" = "$B_FG" ] ||
  report_failure "(31) the titles' ink is not at x 132 and 180 (File ${S_FILE}, Edit ${S_EDIT}, dump ${B_FG}, band ${A_FG})"
# 셸로 포커스를 옮기면(Cmd+[ — strip이 그대로라 부분 프레임) 바가 빈다: `menu> bar empty`, 위 띠가 MARGIN_COLOR(102030) 한 가지.
EMPTIES="$(count_log 'terminal: menu> bar empty')"
type_keys alt-bracket_left
wait_for_count 'terminal: menu> bar empty' $((EMPTIES + 1)) || report_failure "(31) Cmd+[ to the shell did not empty the bar"
sleep 0.5
SHOT31E="${SCREENS_DIR}/menu-bar-empty.ppm"
screendump "$SHOT31E" || report_failure "(31) screendump did not write ${SHOT31E}"
got="$(ppm_ink "$SHOT31E" 0 0 1280 20)"
[ "$got" = "bg=102030 ink=0" ] || report_failure "(31) with the shell focused the top band is not one colour 102030 (${got})"
[ "$(bar_ink name)-$(bar_ink fg)" = "0-0" ] || report_failure "(31) the empty bar's dump is not name=0 fg=0"
echo "(31) shell focused: menu> bar empty, top band ${got}"
type_keys alt-bracket_right
wait_for_log "terminal: wl> configure id=${MENU_ID} w=[0-9]+ h=[0-9]+ act=1" || report_failure "(31) Cmd+] did not give the keys back to the menu window"
wait_for_count "terminal: menu> bar id=${MENU_ID} name=tars-wl-test titles=File,Edit" 2 || report_failure "(31) Cmd+] did not bring the bar back"
type_keys alt-shift-slash
wait_for_log "terminal: wl> key code=53 state=1 to=${MENU_ID}([^0-9]|$)" > /dev/null || true
echo "(31) measurement 8: Cmd+Shift+/ reached the window as code 53 $(count_log "terminal: wl> key code=53 state=1 to=${MENU_ID}([^0-9]|$)") time(s)"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${MENU_ID} ws=1 slot=1" || report_failure "(31) Cmd+Q did not close the menu window"
# 클라이언트가 본 것: `native` 하나, 모델을 보낸 줄 하나, 그리고 실측 8의 Super+Shift(0x41) 수.
type_text 'echo c31-(grep -cx wl-test..native /tmp/wl11.log)-(grep -c menu.sent.menus.2.items.5 /tmp/wl11.log)-(grep -cw depressed.0x41 /tmp/wl11.log)'
type_keys ret
wait_for_screen '\| c31-1-1-[0-9]+' || report_failure "(31) the client's log does not have one native line and one sent model"
echo "(31): the version 2 client's model (2 menus, 5 entries) and its name reached the server; client log $(tlog | grep -aoE 'c31-[0-9]+-[0-9]+-[0-9]+' | tail -n 1)"

# ── 판정 35: 이름만 — 메뉴 모델이 없는 창(TK-M5 단계 B, plan 확정 2 · 15) ──────────────────────────────────────────
# 셸만 남은 자리다(판정 31 끝). 기본 창(호환 모드 — tars_menu_v1을 bind하지 않는다)은 모델이 없어 바에 이름만: `menu> bar id=ID name=tars-wl-test
# titles=-`, 위 띠에 MENU_NAME 잉크가 이름 칸(x 20, 96 px)에만 있고 MENU_FG는 0. 여는 키가 아무 일도 안 하는 것은 단계 C가 본다.
echo "=== (35) a window without a menu model shows only its name ==="
COLS="$(count_log 'terminal: wl> column id=[0-9]+ slot=1 ws=1')"
type_text 'tars-wl-test --follow-size > /tmp/wl12.log &'
type_keys ret
wait_for_count 'terminal: wl> column id=[0-9]+ slot=1 ws=1' $((COLS + 1)) || report_failure "(35) the compat client did not open as a column"
NAME_ID="$(tlog | grep -aoE 'terminal: wl> column id=[0-9]+ slot=1 ws=1' | tail -n 1 | sed -E 's/.*id=([0-9]+).*/\1/')"
wait_for_log "terminal: menu> bar id=${NAME_ID} name=tars-wl-test titles=-" || report_failure "(35) no 'menu> bar id=${NAME_ID} name=tars-wl-test titles=-'"
sleep 0.5
SHOT35="${SCREENS_DIR}/menu-name-only.ppm"
screendump "$SHOT35" || report_failure "(35) screendump did not write ${SHOT35}"
S_NAME="$(ppm_count "$SHOT35" 20 2 96 16 e8d8b0)"
A_NAME="$(ppm_count "$SHOT35" 0 0 1280 20 e8d8b0)"
A_FG="$(ppm_count "$SHOT35" 0 0 1280 20 d0d8e0)"
echo "(35) dump name=$(bar_ink name) fg=$(bar_ink fg); screen name box ${S_NAME}, band name ${A_NAME} fg ${A_FG}"
[ "${S_NAME:-0}" -gt 0 ] && [ "$S_NAME" = "$(bar_ink name)" ] && [ "$A_NAME" = "$S_NAME" ] && [ "$A_FG" = "0" ] && [ "$(bar_ink fg)" = "0" ] ||
  report_failure "(35) the name-only bar is not the name's ink alone (box ${S_NAME}, band ${A_NAME}, fg ${A_FG})"
type_keys alt-q
wait_for_log "terminal: wl> unmap id=${NAME_ID} ws=1 slot=1" || report_failure "(35) Cmd+Q did not close the compat window"
echo "(35): the compat window's bar is its name alone"

# ── 판정 9: render verify ───────────────────────────────────────────────
#
# 루트 게이트는 모든 체인의 로그에서 `verify>` 줄을 본다(check.sh의 check_verify_lines). 단독 실행(`make check`)에도
# 있으면 여기서 먼저 본다 — app 프레임은 verify를 안 하지만(design 결정 17) 그 뒤의 셸 프레임은 한다.
echo "=== (9) no render verify mismatch ==="
if tlog | grep -a 'terminal: verify> mismatch' >/dev/null; then
  report_failure "render verify saw a mismatch"
fi
echo "(9): verify lines $(count_log 'terminal: verify> '), no mismatch"

# 이미지의 판 — 부팅 2의 묶음 version 파일이 이것과 같아야 init이 얹는다(display 체인 판정 9와 같은 줄).
IMAGE_VER="$(grep -aoE 'tars-init: starting as PID 1 \(TARS [^)]+\)' "$LOG" | head -1 | sed -E 's/.*TARS ([^)]+)\)/\1/')"
[ -n "$IMAGE_VER" ] || report_failure "no 'starting as PID 1 (TARS …)' line to read the image version from"
stop_boot

# ══ 부팅 2 — 홈 디스크에 doom 묶음, tars-doom(WY-M1) ═══════════════════════
#
# 묶음은 make dev-layers가 구운 것이다(make check CHAIN=wayland와 make gate가 먼저 부른다). doom은 standalone이라
# base 없이 얹힌다(initrd의 glibc · libwayland-client만 쓴다). init은 /home/.tars/layers의 version이 이미지와 같을 때만 얹는다.
# 모양은 display 체인의 부팅 3이다. 설정 디스크가 없으니 셸은 root이고 키보드는 부팅 1처럼 pc(Cmd = alt)다.
#
# 둠은 `-warp 1 1 -skill 1 -nomonsters`로 띄운다 — 타이틀 4.9초 뒤의 데모 순환을 건너 E1M1에서 바로 선다(결정적인 시작).
# 엔진은 320x200을 그리고 서버가 4배로 늘려 1280 × 800을 꽉 채운다(at=0,0). 상태 줄은 엔진의 y 168..199, 화면의 y 672..799다.
[ -f ../devlayer/build/doom.sqfs ] || report_failure "no devlayer/build/doom.sqfs — run make dev-layers"
HOME_IMG="${REPO_ROOT}/out/wy-home.img"
LAYER_SEED="$(mktemp -d)"
mkdir -p "$LAYER_SEED/.tars/layers"
cp ../devlayer/build/doom.sqfs "$LAYER_SEED/.tars/layers/"
echo "$IMAGE_VER" > "$LAYER_SEED/.tars/layers/version"
rm -f "$HOME_IMG"
truncate -s $(( $(du -sm "$LAYER_SEED" | cut -f1) + 128 ))M "$HOME_IMG"
mkfs.ext4 -F -q -L tars-home -d "$LAYER_SEED" "$HOME_IMG"
rm -rf "$LAYER_SEED"
echo "=== boot 2: root with the doom bundle on the home disk (version ${IMAGE_VER}) ==="
boot -drive file="$HOME_IMG",if=virtio,format=raw

SHOT="${SCREENS_DIR}/doom.ppm"

# 상자 하나의 픽셀 전부의 sha1(앞 12자). ppm_ink(가장 많은 색 + 다른 픽셀 수)는 숫자 50과 49를 못 가를 수 있어서다.
box_sum() {
  perl -MDigest::SHA=sha1_hex -e '
    my ($f, $x0, $y0, $w, $h) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3; my $s = "";
    for my $y ($y0 .. $y0 + $h - 1) { $s .= substr($d, $y * $row + $x0 * 3, $w * 3) }
    print substr(sha1_hex($s), 0, 12), "\n";' "$SHOT" "$@"
}

# 상태 줄의 멈춘 상자(판정 11) — 글자판 "HEALTH"(엔진 x 54..94 · y 190..197, 4배). 얼굴(x 143..176)과 숫자를 피한 자리라
# 게임이 돌아도 안 바뀐다. 값은 첫 실측 screendump(2026-11-20, Freedoom 0.13.0의 STBAR)로 정했다 — 다섯 장이 같았다.
STBAR_BOX="216 760 160 32"
STBAR_WANT="bg=1c1c1c ink=4336"
# 탄약 숫자 칸 — 엔진의 ST_AMMOX 44(오른쪽 끝) · ST_AMMOY 171, 큰 숫자 셋(14 × 16)이 x 2..44에 선다. 4배로 x 8..183, y 684..747.
AMMO_BOX=(8 684 176 64)

check_stbar() {
  local tag="$1" a b
  screendump "$SHOT" || report_failure "${tag}: screendump did not write ${SHOT}"
  cp "$SHOT" "${SCREENS_DIR}/${tag}-1.ppm"
  # shellcheck disable=SC2086
  a="$(ppm_ink "$SHOT" $STBAR_BOX)"
  sleep 1
  screendump "$SHOT" || report_failure "${tag}: screendump did not write ${SHOT}"
  cp "$SHOT" "${SCREENS_DIR}/${tag}-2.ppm"
  # shellcheck disable=SC2086
  b="$(ppm_ink "$SHOT" $STBAR_BOX)"
  [ "$a" = "$b" ] || report_failure "${tag}: the status bar box at ${STBAR_BOX} changed in a second (${a} -> ${b})"
  [ "$a" = "$STBAR_WANT" ] || report_failure "${tag}: the status bar box at ${STBAR_BOX} is ${a}, want ${STBAR_WANT}"
  echo "${tag}: the status bar box at ${STBAR_BOX} is ${a} in two shots a second apart"
}

# ── 판정 10: 묶음 · toplevel · 4배 ─────────────────────────────────────
echo "=== (10) the doom bundle is laid over /usr, tars-doom opens workspace 2 at 320x200 scale 4 ==="
wait_for_log 'tars-init: overlay /usr from 1 layers in [0-9]+ms' ||
  report_failure "(10) init did not lay the doom bundle over /usr"
type_text 'tars-doom -warp 1 1 -skill 1 -nomonsters > /tmp/doom.log &'
type_keys ret
wait_for_log 'terminal: wl> client pid=[0-9]+' || report_failure "(10) no 'wl> client' line"
DOOM_PID="$(tlog | grep -aoE 'terminal: wl> client pid=[0-9]+' | tail -n 1 | sed 's/.*pid=//')"
wait_for_log 'terminal: wl> toplevel id=1 ws=2' || report_failure "(10) no 'wl> toplevel id=1 ws=2'"
wait_for_log 'terminal: wl> commit id=1 buf=320x200 scale=4 at=0,0' ||
  report_failure "(10) no 'wl> commit id=1 buf=320x200 scale=4 at=0,0'"
wait_for_count 'terminal: pane> ws=2/2 app id=1' 1 || report_failure "(10) doom's workspace never came to the front"
echo "(10): overlay from 1 layer, doom (pid ${DOOM_PID}) is workspace 2, 320x200 at scale 4 from 0,0"

# ── 판정 11: 상태 줄의 멈춘 상자 ─────────────────────────────────────────
echo "=== (11) a still box of the status bar ==="
# E1M1에 들어서는 wipe(약 1초)가 끝나기를 기다린다.
sleep 3
check_stbar doom-first

# ── 판정 12: Ctrl이 쏜다 ───────────────────────────────────────────────
#
# sendkey의 기본 누름은 짧아 누름과 뗌이 엔진의 한 tic 안에 들 수 있다 — 그러면 G_BuildTiccmd가 쥔 것을 못 본다. 0.3초 쥔다.
echo "=== (12) Ctrl goes to doom as evdev 29 and the pistol fires (the ammo digits change) ==="
AMMO_BEFORE="$(box_sum "${AMMO_BOX[@]}")"
echo "sendkey ctrl 300" >&3
wait_for_log 'terminal: wl> key code=29 state=1 to=1' || report_failure "(12) no 'wl> key code=29 state=1 to=1'"
wait_for_log 'terminal: wl> key code=29 state=0 to=1' || report_failure "(12) no 'wl> key code=29 state=0 to=1'"
AMMO_AFTER=""
for _ in $(seq 1 20); do
  sleep 0.5
  screendump "$SHOT" || report_failure "(12) screendump did not write ${SHOT}"
  AMMO_AFTER="$(box_sum "${AMMO_BOX[@]}")"
  [ "$AMMO_AFTER" != "$AMMO_BEFORE" ] && break
done
cp "$SHOT" "${SCREENS_DIR}/doom-fired.ppm"
[ "$AMMO_AFTER" != "$AMMO_BEFORE" ] ||
  report_failure "(12) the ammo digits at ${AMMO_BOX[*]} did not change after Ctrl (${AMMO_BEFORE})"
echo "(12): Ctrl reached doom as 29, the ammo digits changed (${AMMO_BEFORE} -> ${AMMO_AFTER})"

# ── 판정 13: Cmd+1 · Cmd+2 ─────────────────────────────────────────────
echo "=== (13) Cmd+1 shows the shell, it answers, Cmd+2 shows doom again ==="
SHELL_FRONT="$(count_log 'terminal: pane> ws=1/2 panes=1 ')"
type_keys alt-1
wait_for_count 'terminal: pane> ws=1/2 panes=1 ' $((SHELL_FRONT + 1)) || report_failure "(13) Cmd+1 did not bring the shell back"
# 게스트의 셸이 펼칠 글자다 — 여기서 펼치면 안 된다.
# shellcheck disable=SC2016
type_text 'echo alive-$status'
type_keys ret
wait_for_screen 'alive-0' || report_failure "(13) the shell did not answer while doom ran behind it"
type_keys alt-2
wait_for_count 'terminal: pane> ws=2/2 app id=1' 2 || report_failure "(13) Cmd+2 did not bring doom back"
sleep 1
check_stbar doom-again
echo "(13): the shell answered behind doom, Cmd+2 brought doom back with the same status bar box"

# ── 판정 14: Cmd+Q — 둠이 스스로 끝난다 ─────────────────────────────────
echo "=== (14) Cmd+Q: doom gets close and exits by itself, no SIGKILL ==="
SHELL_ALONE="$(count_log 'terminal: pane> ws=1/1 panes=1 ')"
type_keys alt-q
wait_for_log 'terminal: wl> close id=1' || report_failure "(14) Cmd+Q sent no 'wl> close id=1'"
wait_for_log "terminal: wl> gone pid=${DOOM_PID}" || report_failure "(14) doom never went (no 'wl> gone pid=${DOOM_PID}')"
wait_for_log 'terminal: wl> unmap id=1 ws=2' || report_failure "(14) doom's workspace was not removed"
wait_for_count 'terminal: pane> ws=1/1 panes=1 ' $((SHELL_ALONE + 1)) || report_failure "(14) the shell is not alone after Cmd+Q"
sleep 2.5
if tlog | grep -a 'terminal: wl> kill ' >/dev/null; then
  report_failure "(14) doom was killed — it should have answered the ping and left on close"
fi
echo "(14): doom left on close by itself, its workspace is gone"

# ── 판정 15: 키 줄의 수 · render verify ──────────────────────────────────
echo "=== (15) wl> key lines, no render verify mismatch ==="
if tlog | grep -a 'terminal: verify> mismatch' >/dev/null; then
  report_failure "(15) render verify saw a mismatch"
fi
echo "(15): wl> key lines $(count_log 'terminal: wl> key '), verify lines $(count_log 'terminal: verify> '), no mismatch"
stop_boot

echo "PASS: WY-M0 · WY-M1 · WY-M2 · WY-M4 · WY-M5 · WY-M6 — a window without tars_menu_v1 gets Cmd as Ctrl and one that binds it gets Cmd as Super, a commit that damages a 32x32 box is copied as that box alone; in a window with text input Hangul composes as preedit and commits before the next key, the eaten keys are not sent, losing the focus commits the composition, a window without text input still gets keys; a copy in the shell is pasted in a window and a copy in a window is pasted in the shell even after it closes, an EPIPE on the clipboard pipe does not kill terminal and the shell's children still die of SIGPIPE; a window without fullscreen opens as a column right of the shell and follows its size (Cmd+R), a click gives it the keys and the pointer, a hidden cursor is not drawn; the shell has WAYLAND_DISPLAY, tars-wl-test becomes workspace 2 drawn 4x in the middle, its keys go to it as evdev codes, Cmd+1 · Cmd+2 go back and forth, Cmd+C · Cmd+Q type nothing in the shell, a stopped client does not stop the shell, Cmd+Q closes and a client that ignores close is killed after 2 s; with the doom bundle tars-doom fills the screen at 4x, fires on Ctrl, waits behind the shell and leaves by itself on Cmd+Q"
