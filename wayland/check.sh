#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# WY 체인 — terminal 안의 Wayland 서버(WY-M0). 서른다섯번째 체인.
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
# 부팅 하나, NIC 없음, 디스크 없음(plan). 디스크가 없으니 셸은 root(fish)이고 소켓은 `/run/user/0`이다. 키보드는 QEMU의
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

# 글자열을 sendkey 이름으로 친다(소문자 · 숫자 · 공백 · `-` · `/` · `.` · `>` · `$` · `&`만).
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
      _) keys+=(shift-minus) ;;
      [A-Z]) keys+=("shift-${ch,,}") ;;
      *) keys+=("$ch") ;;
    esac
  done
  type_keys "${keys[@]}"
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
echo "=== (2) tars-wl-test opens workspace 2, its colour scaled 4x in the middle ==="
type_text 'tars-wl-test --color 3366CC --size 300x200 > /tmp/wl.log &'
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
type_text 'tars-wl-test --ignore-close --color 3366CC --size 300x200 > /tmp/wl2.log &'
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

# ── 판정 9: render verify ───────────────────────────────────────────────
#
# 루트 게이트는 모든 체인의 로그에서 `verify>` 줄을 본다(check.sh의 check_verify_lines). 단독 실행(`make check`)에도
# 있으면 여기서 먼저 본다 — app 프레임은 verify를 안 하지만(design 결정 17) 그 뒤의 셸 프레임은 한다.
echo "=== (9) no render verify mismatch ==="
if tlog | grep -a 'terminal: verify> mismatch' >/dev/null; then
  report_failure "render verify saw a mismatch"
fi
echo "(9): verify lines $(count_log 'terminal: verify> '), no mismatch"

exec 3<&- 2>/dev/null
exec 3>&- 2>/dev/null
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""
echo "PASS: WY-M0 — the shell has WAYLAND_DISPLAY, tars-wl-test becomes workspace 2 drawn 4x in the middle, its keys go to it as evdev codes, Cmd+1 · Cmd+2 go back and forth, Cmd+C · Cmd+Q type nothing in the shell, a stopped client does not stop the shell, Cmd+Q closes and a client that ignores close is killed after 2 s"