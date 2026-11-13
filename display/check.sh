#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# DY 체인 — 화면 양보(DY-M0). 서른넷째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   init이 /dev/dri의 노드를 root:video 660으로 열고(`tars-init: display: 2 nodes …`) 화면 셸은 video(44)의 구성원이다
#   → terminal이 /run/tars/display.sock(root:video 660)을 듣는다 · card0의 fd는 셸로 새지 않는다(CLOEXEC)
#   → 사용자가 `tars-fullscreen tars-kms-fill cc6666 6`을 치면 terminal이 DROP_MASTER(`display> yield pid N`)하고
#     tars-kms-fill(uid 1000)이 card0을 스스로 열어 master가 되어 화면 전체를 한 색으로 칠한다(screendump)
#   → 프로그램이 끝나면 연결이 닫히고 terminal이 SET_MASTER + modeset(`display> reclaim`) · 통째로 다시 그린다
#   그리고 양보 중의 출력이 vt에 쌓여 복귀 뒤 보이고, SIGKILL로 죽은 프로그램에서도 돌아오고, 둘째 요청은
#   `busy`로 1이며, 그 내내 terminal은 한 번도 죽지 않는다(`tars-init: restarting` 없음 — DY design 결정 1의 까닭).
#
# 셸은 사용자 dyuser(uid 1000)다 — 설정 디스크의 user=와 tars-home 라벨의 ext4 디스크가 함께 있어야 init이
# root 대신 사용자로 띄운다(`pickUser`). 양보의 요점이 "사용자의 프로그램이 화면을 잡는다"라서다.
#
# 화면은 virtio-gpu 1280 × 800(fullscreen 체인과 같다 — card0 + renderD128이라 노드가 둘). monitor 포트는 45507 —
# 예약 범위(RP-M0)에서 cursor의 45506 다음 빈 자리다. 회차당 부팅 1회.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# video 그룹의 짝(account_test · login_test)은 여기서 먼저 걸러진다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 양보의 상태 규칙(yield_test — busy · waiting · refused)은 여기서 먼저 걸러진다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45507
REPO_ROOT="$(cd .. && pwd)"
XRES=1280
YRES=800
USER_NAME=dyuser

# screendump는 QEMU 프로세스의 작업 디렉터리를 기준으로 삼으므로 절대 경로로 넘긴다.
# out/은 .gitignore 대상이고 루트 check.sh의 clean()이 지운다.
SCREENS_DIR="${REPO_ROOT}/out/dy"
mkdir -p "$SCREENS_DIR"
SHOT="${SCREENS_DIR}/shot.ppm"

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
  echo "--- display, user and restart lines ---"
  tlog | grep -aE 'terminal: display> |tars-init: display: |tars-init: user |tars-init: restarting|terminal: spawned' | tr -d '\r'
  echo "--- last screen lines ---"
  joined_screen_dump | tail -n 3
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

# 패턴에 맞는 로그 줄이 `want`개가 될 때까지 기다린다(fullscreen/check.sh와 같다). 같은 `display>` 줄이 이
# 부팅에 여러 번 찍히므로 "있는가"가 아니라 "늘었는가"를 본다.
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

# 글자 한 줄을 키로 친다(끝에 Enter). 이 체인이 쓰는 글자만 안다 — 모르는 글자는 그 자리에서 실패한다.
type_line() {
  local s="$1" i ch keys=()
  for (( i = 0; i < ${#s}; i++ )); do
    ch="${s:i:1}"
    case "$ch" in
      [a-z0-9]) keys+=("$ch") ;;
      [A-Z]) keys+=("shift-${ch,,}") ;;
      ' ') keys+=(spc) ;;
      -) keys+=(minus) ;;
      _) keys+=(shift-minus) ;;
      /) keys+=(slash) ;;
      .) keys+=(dot) ;;
      =) keys+=(equal) ;;
      +) keys+=(shift-equal) ;;
      ';') keys+=(semicolon) ;;
      '*') keys+=(shift-8) ;;
      '(') keys+=(shift-9) ;;
      ')') keys+=(shift-0) ;;
      '$') keys+=(shift-4) ;;
      '%') keys+=(shift-5) ;;
      '&') keys+=(shift-7) ;;
      '|') keys+=(shift-backslash) ;;
      *) report_failure "type_line does not know the character '${ch}'" ;;
    esac
  done
  keys+=(ret)
  type_keys "${keys[@]}"
}

# 상자 하나의 바탕색(`ppm_ink`의 bg=). 마지막 SHOT을 읽는다.
bg_of() {
  local r
  r="$(ppm_ink "$SHOT" "$@")"
  r="${r#bg=}"
  echo "${r%% *}"
}

# 가운데와 네 귀퉁이(각 32 × 32)의 바탕색이 모두 $1인가. 아니면 무엇이었는지 찍는다.
whole_screen_is() {
  local want="$1" got=""
  got="$(bg_of 624 384 32 32) $(bg_of 0 0 32 32) $(bg_of $((XRES - 32)) 0 32 32) $(bg_of 0 $((YRES - 32)) 32 32) $(bg_of $((XRES - 32)) $((YRES - 32)) 32 32)"
  LAST_BGS="$got"
  [ "$got" = "$want $want $want $want $want" ]
}

# 화면 전체가 $1이 될 때까지 screendump를 다시 뜬다. 8초.
wait_for_color() {
  local want="$1" i
  for i in $(seq 1 16); do
    screendump "$SHOT" || return 1
    if whole_screen_is "$want"; then return 0; fi
    sleep 0.5
  done
  return 1
}

# 설정 디스크(ext2) 하나와 홈 디스크(ext4, 라벨 tars-home) 하나.
CONFIG_IMG="${REPO_ROOT}/out/dy-config.img"
HOME_IMG="${REPO_ROOT}/out/dy-home.img"
seed="$(mktemp -d)"
printf '%s\n' 'shell=fish' "user=${USER_NAME}" > "$seed/tars.conf"
rm -f "$CONFIG_IMG" "$HOME_IMG"
truncate -s 16M "$CONFIG_IMG"
mkfs.ext2 -F -q -m 0 -L tars-dy -d "$seed" "$CONFIG_IMG"
rm -rf "$seed"
truncate -s 64M "$HOME_IMG"
mkfs.ext4 -F -q -L tars-home "$HOME_IMG"

echo "=== boot: ${XRES}x${YRES} virtio-gpu, the screen shell is ${USER_NAME} ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci,xres=${XRES},yres=${YRES} \
  -display none \
  -drive file="$CONFIG_IMG",if=virtio,format=raw \
  -drive file="$HOME_IMG",if=virtio,format=raw \
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
wait_for_screen "${USER_NAME}@tars" ||
  report_failure "the ${USER_NAME} prompt never showed up"
sleep 1

connected=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
  sleep 0.5
done
[ "$connected" = "1" ] || report_failure "could not connect to the QEMU monitor on port ${MONITOR_PORT}"

YIELD='terminal: display> yield pid [0-9]+'
RECLAIM='terminal: display> reclaim'

# ── 판정 1: 문 — 노드 · 그룹 · socket · 새지 않는 fd ─────────────────────
echo "=== (1) the door: /dev/dri and the socket are root:video 660, the shell is in video, card0 does not leak ==="
tlog | grep -aE 'tars-init: user dyuser uid 1000' >/dev/null ||
  report_failure "the screen shell is not dyuser (no 'tars-init: user dyuser uid 1000')"
tlog | grep -aE 'tars-init: display: 2 nodes in /dev/dri are root:video 660 \(0 refused\)' >/dev/null ||
  report_failure "init did not open card0 and renderD128 to video"
tlog | grep -a 'terminal: display> listening on /run/tars/display.sock' >/dev/null ||
  report_failure "terminal is not listening on /run/tars/display.sock"
type_line 'id'
wait_for_screen 'uid=1000\(dyuser\).*44\(video\)' ||
  report_failure "id does not show 44(video)"
type_line 'stat -c d1-%A-%U-%G /dev/dri/card0 /run/tars/display.sock'
wait_for_screen 'd1-crw-rw-----root-video' ||
  report_failure "card0 is not crw-rw---- root video"
wait_for_screen 'd1-srw-rw-----root-video' ||
  report_failure "display.sock is not srw-rw---- root video"
# fish의 glob이 자기 fd를 펼치고 readlink가 그 끝을 읽는다. 셸이 card0을 물려받았으면 1이다(DY-M0 전에는 그랬다).
type_line 'echo d2-(readlink /proc/self/fd/* | grep -c dri)'
wait_for_screen 'd2-0' ||
  report_failure "the shell holds a /dev/dri fd — terminal's card0 leaks into panes"
echo "(1) 2 nodes root:video 660, uid 1000 in video, the socket root:video 660, no card0 fd in the shell"

# ── 판정 2: 양보 — 화면 전체가 한 색 ─────────────────────────────────────
echo "=== (2) tars-fullscreen tars-kms-fill cc6666 6 paints the whole screen ==="
type_line 'tars-fullscreen tars-kms-fill cc6666 6'
wait_for_count "$YIELD" 1 ||
  report_failure "(2) no 'terminal: display> yield pid N'"
wait_for_color cc6666 ||
  report_failure "(2) the screen never became cc6666 (centre and corners: ${LAST_BGS})"
echo "(2) yielded; centre and four corners are cc6666"

# ── 판정 3: 복귀 — 색이 사라지고 셸이 돌아온다 ──────────────────────────
echo "=== (3) the program ends and the console comes back ==="
wait_for_count "$RECLAIM" 1 ||
  report_failure "(3) no 'terminal: display> reclaim' after the program ended"
# 양보 중에 tars-kms-fill이 stderr(패널)에 쓴 줄이 vt에 쌓였다가 복귀의 통째 그리기에 보인다.
wait_for_screen 'tars-kms-fill: setcrtc ok' ||
  report_failure "(3) the program's 'setcrtc ok' line is not on the screen after reclaim"
type_line 'echo d3-(math 1+2)'
wait_for_screen 'd3-3' ||
  report_failure "(3) the shell does not answer after reclaim"
screendump "$SHOT" || report_failure "(3) screendump did not write ${SHOT}"
if whole_screen_is cc6666 || [ "$(bg_of 624 384 32 32)" = cc6666 ]; then
  report_failure "(3) cc6666 is still on the screen after reclaim (${LAST_BGS})"
fi
echo "(3) reclaimed; the program's output and the shell are back, no cc6666 left"

# ── 판정 4: 양보 중의 출력이 남는다 ──────────────────────────────────────
echo "=== (4) output written while yielded shows after reclaim ==="
type_line 'tars-fullscreen tars-kms-fill 6666cc 3; echo back-(math 40+2)'
wait_for_count "$YIELD" 2 ||
  report_failure "(4) no second 'display> yield'"
wait_for_count "$RECLAIM" 2 ||
  report_failure "(4) no second 'display> reclaim'"
wait_for_screen 'back-42' ||
  report_failure "(4) 'back-42', echoed after the program, is not on the screen"
echo "(4) the echo after the program shows"

# ── 판정 5 · 6: SIGKILL에서 돌아오고, 그 사이의 둘째 요청은 busy ────────────
echo "=== (5) a second request while yielded is busy, (6) SIGKILL still gives the screen back ==="
type_line 'tars-fullscreen tars-kms-fill 66cc66 0 &'
wait_for_count "$YIELD" 3 ||
  report_failure "(5) no third 'display> yield' for the background program"
wait_for_color 66cc66 ||
  report_failure "(5) the screen never became 66cc66 (${LAST_BGS})"
# shellcheck disable=SC2016 # 게스트의 fish가 펼칠 글자다 — 여기서 펼치면 안 된다.
type_line 'tars-fullscreen true; echo rc=$status'
wait_for_log 'terminal: display> busy pid [0-9]+' ||
  report_failure "(5) no 'terminal: display> busy pid N' for the second request"
# shellcheck disable=SC2016 # 위와 같다. $last_pid는 fish의 마지막 백그라운드 job이다.
type_line 'kill -9 $last_pid'
wait_for_count "$RECLAIM" 3 ||
  report_failure "(6) no 'display> reclaim' after SIGKILL"
wait_for_screen 'rc=1' ||
  report_failure "(5) tars-fullscreen did not exit 1 on busy"
wait_for_screen 'tars-fullscreen: the screen is in use by another program' ||
  report_failure "(5) tars-fullscreen did not say why"
type_line 'echo d6-(math 2+4)'
wait_for_screen 'd6-6' ||
  report_failure "(6) the shell does not answer after the SIGKILL reclaim"
echo "(5) busy and rc=1 for the second request, (6) reclaimed after SIGKILL"

# ── 판정 7: terminal은 한 번도 죽지 않았다 ───────────────────────────────
echo "=== (7) terminal never restarted ==="
if tlog | grep -aE 'tars-init: restarting' >/dev/null; then
  report_failure "(7) terminal restarted during the run"
fi
if tlog | grep -aE 'terminal: display> (waiting for master|refused|no socket|modeset after reclaim failed)' >/dev/null; then
  report_failure "(7) an unexpected display> line"
fi
[ "$(count_log "$YIELD")" -eq 3 ] && [ "$(count_log "$RECLAIM")" -eq 3 ] ||
  report_failure "(7) yields $(count_log "$YIELD") and reclaims $(count_log "$RECLAIM"), want 3 and 3"
echo "(7) three yields, three reclaims, one busy, no restart"

exec 3<&- 2>/dev/null
exec 3>&- 2>/dev/null
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""
echo "PASS: DY-M0 — init opens /dev/dri to video, terminal yields the screen over /run/tars/display.sock, a uid-1000 program paints it through its own card0, and terminal takes it back when the program ends, dies or is SIGKILLed, with a second request answered busy"
