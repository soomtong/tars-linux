#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# DY 체인 — 화면 양보(DY-M0 · DY-M1). 서른넷째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   init이 /dev/dri의 노드를 root:video 660으로 열고(`tars-init: display: 2 nodes …`) 화면 셸은 video(44)의 구성원이다
#   → terminal이 /run/tars/display.sock(root:video 660)을 듣는다 · card0의 fd는 셸로 새지 않는다(CLOEXEC)
#   → 사용자가 `tars-fullscreen tars-kms-fill cc6666 6`을 치면 terminal이 DROP_MASTER(`display> yield pid N`)하고
#     tars-kms-fill(uid 1000)이 card0을 스스로 열어 master가 되어 화면 전체를 한 색으로 칠한다(screendump)
#   → 프로그램이 끝나면 연결이 닫히고 terminal이 SET_MASTER + modeset(`display> reclaim`) · 통째로 다시 그린다
#   그리고 양보 중의 출력이 vt에 쌓여 복귀 뒤 보이고, SIGKILL로 죽은 프로그램에서도 돌아오고, 둘째 요청은
#   `busy`로 1이며, 그 내내 terminal은 한 번도 죽지 않는다(`tars-init: restarting` 없음 — DY design 결정 1의 까닭).
#   DY-M1: 양보 동안 키는 앱의 것이다 — 평소 root인 /dev/input/event*가 그동안만 손님의 uid 것이 되고(결정 8a) 친 키가
#   셸에 안 들어가며, Ctrl+Cmd+Backspace가 SIGTERM · 2초 뒤 SIGKILL로 멈춘 앱에서 돌아온다(결정 8b). 부팅 2(root 셸)는
#   양보 중에 terminal이 다시 떠도 죽지 않고 기다리다가 앱이 죽으면 되찾는 것을 본다(결정 11).
#   DY-M2: 부팅 3은 홈 디스크의 .tars/layers에 base · gpu 묶음을 얹고 `tars-fullscreen tars-gpu-demo`가 SDL3(KMSDRM) +
#   OpenGL ES(Mesa)로 화면을 그리며 키를 udevd 없이 받는 것을 본다(결정 10, M2 plan 확인 3). 묶음이 없는 부팅 2에서는
#   데모가 이유를 말하고 1로 끝난다.
#   DY-M3: 부팅 3처럼 얹힌 묶음이 base · gpu 둘뿐이면(GPU 데모 판) 첫 패널이 데모를 스스로 화면 가득 띄우고 Esc로 셸에 돌아온다.
#
# 셸은 사용자 dyuser(uid 1000)다 — 설정 디스크의 user=와 tars-home 라벨의 ext4 디스크가 함께 있어야 init이
# root 대신 사용자로 띄운다(`pickUser`). 양보의 요점이 "사용자의 프로그램이 화면을 잡는다"라서다.
#
# 화면은 virtio-gpu 1280 × 800(fullscreen 체인과 같다 — card0 + renderD128이라 노드가 둘). monitor 포트는 45507 —
# 예약 범위(RP-M0)에서 cursor의 45506 다음 빈 자리다. 회차당 부팅 3회. 설정 디스크에 keyboard=apple — QEMU의 키보드는
# PC라 그대로면 Cmd가 Alt 자리다(gate_lib.sh의 apple_disk와 같은 이유). 탈출 조합은 `ctrl-meta_l-backspace`로 보낸다.

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
      ':') keys+=(shift-semicolon) ;;
      '*') keys+=(shift-8) ;;
      '(') keys+=(shift-9) ;;
      ')') keys+=(shift-0) ;;
      '$') keys+=(shift-4) ;;
      '%') keys+=(shift-5) ;;
      '&') keys+=(shift-7) ;;
      '|') keys+=(shift-backslash) ;;
      "'") keys+=(apostrophe) ;;
      '"') keys+=(shift-apostrophe) ;;
      '>') keys+=(shift-dot) ;;
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

# 설정 디스크(ext2) 하나. 홈 디스크(ext4, 라벨 tars-home)를 함께 물리면 셸이 user=의 사용자로 뜬다(`pickUser`).
make_disks() {
  local seed
  seed="$(mktemp -d)"
  printf '%s\n' "$@" > "$seed/tars.conf"
  rm -f "$CONFIG_IMG" "$HOME_IMG"
  truncate -s 16M "$CONFIG_IMG"
  mkfs.ext2 -F -q -m 0 -L tars-dy -d "$seed" "$CONFIG_IMG"
  rm -rf "$seed"
  truncate -s 64M "$HOME_IMG"
  mkfs.ext4 -F -q -L tars-home "$HOME_IMG"
}

# 부팅 하나. $1 = 프롬프트의 머리, 나머지 = QEMU에 더할 -drive 인자.
boot() {
  local prompt="$1"
  shift
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

  # --autorun(DY-M3): 첫 패널이 데모를 스스로 띄우는 부팅이다. 양보가 terminal의 첫 화면 찍기보다 먼저라 `screen>` 줄도
  # 프롬프트도 데모가 끝난 뒤에야 온다 — 그래서 yield 줄을 기다리고, 프롬프트는 판정 12a가 Esc 뒤에 본다.
  local ready=0 want="terminal: screen>"
  [ "$prompt" = "--autorun" ] && want="terminal: display> yield pid"
  for _ in $(seq 1 120); do
    if grep -a "$want" "$LOG" >/dev/null; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$prompt" = "--autorun" ]; then
    [ "$ready" = "1" ] || report_failure "the first panel never asked for the screen (no 'display> yield')"
  else
    [ "$ready" = "1" ] || report_failure "terminal never rendered a prompt"
    wait_for_screen "${prompt}@tars" ||
      report_failure "the ${prompt} prompt never showed up"
  fi
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

CONFIG_IMG="${REPO_ROOT}/out/dy-config.img"
HOME_IMG="${REPO_ROOT}/out/dy-home.img"
YIELD='terminal: display> yield pid [0-9]+'
RECLAIM='terminal: display> reclaim'
SIGTERM_LINE='terminal: display> escape pid [0-9]+ \(SIGTERM\)'
SIGKILL_LINE='terminal: display> escape pid [0-9]+ \(SIGKILL\)'
HANDED='terminal: display> inputs [0-9]+ to uid 1000 \(0 refused\)'
TAKEN='terminal: display> inputs [0-9]+ back to root \(0 refused\)'

# ══ 부팅 1 — 사용자 dyuser ══════════════════════════════════════════════
make_disks 'shell=fish' 'keyboard=apple' "user=${USER_NAME}"
echo "=== boot 1: ${XRES}x${YRES} virtio-gpu, the screen shell is ${USER_NAME} ==="
boot "$USER_NAME" -drive file="$CONFIG_IMG",if=virtio,format=raw -drive file="$HOME_IMG",if=virtio,format=raw

# ── 판정 1: 문 — 노드 · 그룹 · socket · 새지 않는 fd · 평소의 키보드 ─────────
echo "=== (1) the door: /dev/dri and the socket are root:video 660, the shell is in video, card0 does not leak, inputs are root's ==="
tlog | grep -aE 'tars-init: user dyuser uid 1000' >/dev/null ||
  report_failure "the screen shell is not dyuser (no 'tars-init: user dyuser uid 1000')"
tlog | grep -aE 'tars-init: display: 2 nodes in /dev/dri are root:video 660 \(0 refused\)' >/dev/null ||
  report_failure "init did not open card0 and renderD128 to video"
tlog | grep -a 'terminal: display> listening on /run/tars/display.sock' >/dev/null ||
  report_failure "terminal is not listening on /run/tars/display.sock"
wait_for_count "$TAKEN" 1 ||
  report_failure "terminal did not put /dev/input back to root when it started"
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
# 평소의 키는 root만 읽는다(결정 8a) — root가 아닌 event 노드의 수.
type_line 'echo d0-(stat -c %U /dev/input/event* | grep -vc root)'
wait_for_screen 'd0-0' ||
  report_failure "an /dev/input/event node is not root's before any yield"
echo "(1) 2 nodes root:video 660, uid 1000 in video, the socket root:video 660, no card0 fd in the shell, every input node root's"

# ── 판정 2: 양보 — 화면 전체가 한 색 ─────────────────────────────────────
echo "=== (2) tars-fullscreen tars-kms-fill cc6666 6 paints the whole screen ==="
type_line 'tars-fullscreen tars-kms-fill cc6666 6'
wait_for_count "$YIELD" 1 ||
  report_failure "(2) no 'terminal: display> yield pid N'"
wait_for_count "$HANDED" 1 ||
  report_failure "(2) the inputs were not handed to uid 1000"
wait_for_color cc6666 ||
  report_failure "(2) the screen never became cc6666 (centre and corners: ${LAST_BGS})"
echo "(2) yielded; inputs to uid 1000; centre and four corners are cc6666"

# ── 판정 3: 복귀 — 색이 사라지고 셸이 돌아온다 ──────────────────────────
echo "=== (3) the program ends and the console comes back ==="
wait_for_count "$RECLAIM" 1 ||
  report_failure "(3) no 'terminal: display> reclaim' after the program ended"
wait_for_count "$TAKEN" 2 ||
  report_failure "(3) the inputs were not taken back"
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
echo "(3) reclaimed; inputs back to root; the program's output and the shell are back, no cc6666 left"

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

# ── 판정 5: 둘째 요청은 busy ─────────────────────────────────────────────
# 양보 중에는 키가 셸에 안 들어간다(DY-M1) — 둘째 요청은 양보 전에 한 줄로 쳐 둔다.
echo "=== (5) a second request while yielded is busy ==="
# shellcheck disable=SC2016 # 게스트의 fish가 펼칠 글자다 — 여기서 펼치면 안 된다.
type_line 'tars-fullscreen tars-kms-fill 66cc66 4 & sleep 2; tars-fullscreen true; echo rc=$status'
wait_for_count "$YIELD" 3 ||
  report_failure "(5) no third 'display> yield' for the background program"
wait_for_log 'terminal: display> busy pid [0-9]+' ||
  report_failure "(5) no 'terminal: display> busy pid N' for the second request"
wait_for_count "$RECLAIM" 3 ||
  report_failure "(5) no third 'display> reclaim'"
wait_for_screen 'rc=1' ||
  report_failure "(5) tars-fullscreen did not exit 1 on busy"
wait_for_screen 'tars-fullscreen: the screen is in use by another program' ||
  report_failure "(5) tars-fullscreen did not say why"
echo "(5) busy and rc=1 for the second request"

# ── 판정 6: 키는 앱의 것이다 ─────────────────────────────────────────────
echo "=== (6) keys typed while yielded reach the program, not the shell ==="
type_line 'tars-fullscreen tars-kms-fill cc66cc 0 --keys'
wait_for_count "$YIELD" 4 ||
  report_failure "(6) no fourth 'display> yield'"
wait_for_count "$HANDED" 4 ||
  report_failure "(6) the inputs were not handed to uid 1000"
wait_for_color cc66cc ||
  report_failure "(6) the screen never became cc66cc (${LAST_BGS})"
type_keys x y z esc
wait_for_count "$RECLAIM" 4 ||
  report_failure "(6) Esc did not end the program (no fourth 'display> reclaim')"
wait_for_screen 'tars-kms-fill: input event[0-9]+ ok' ||
  report_failure "(6) the program (uid 1000) could not open an input node while yielded"
wait_for_screen 'tars-kms-fill: esc after 3 keys' ||
  report_failure "(6) the program did not see x y z and Esc"
# 셸이 x y z를 받았으면 이 줄은 `xyzecho …`가 되어 k1-7을 안 찍는다.
type_line 'echo k1-(math 3+4)'
wait_for_screen 'k1-7' ||
  report_failure "(6) the keys typed while yielded leaked into the shell"
type_line 'echo d4-(stat -c %U /dev/input/event* | grep -vc root)'
wait_for_screen 'd4-0' ||
  report_failure "(6) an /dev/input/event node is still not root's after reclaim"
echo "(6) the program opened the inputs, saw x y z and Esc; the shell got nothing; inputs are root's again"

# ── 판정 7: 탈출 — SIGTERM을 무시하는 앱은 2초 뒤 SIGKILL ─────────────────
echo "=== (7) Ctrl+Cmd+Backspace: SIGTERM, then SIGKILL after 2s for a program that ignores it ==="
type_line "sh -c 'trap \"\" TERM; exec tars-fullscreen tars-kms-fill 66cc66 0'"
wait_for_count "$YIELD" 5 ||
  report_failure "(7) no fifth 'display> yield'"
wait_for_color 66cc66 ||
  report_failure "(7) the screen never became 66cc66 (${LAST_BGS})"
type_keys ctrl-meta_l-backspace
wait_for_count "$SIGTERM_LINE" 1 ||
  report_failure "(7) the chord did not send SIGTERM"
wait_for_count "$SIGKILL_LINE" 1 ||
  report_failure "(7) no SIGKILL after the deadline"
wait_for_count "$RECLAIM" 5 ||
  report_failure "(7) no fifth 'display> reclaim' after SIGKILL"
type_line 'echo d7-(math 3+4)'
wait_for_screen 'd7-7' ||
  report_failure "(7) the shell does not answer after the chord"
echo "(7) the chord sent SIGTERM, then SIGKILL; reclaimed"

# ── 판정 8: 탈출 — SIGTERM으로 끝나는 앱에는 SIGKILL이 없다 ─────────────
echo "=== (8) Ctrl+Cmd+Backspace on a program that obeys SIGTERM ==="
type_line 'tars-fullscreen tars-kms-fill 6666cc 0'
wait_for_count "$YIELD" 6 ||
  report_failure "(8) no sixth 'display> yield'"
wait_for_color 6666cc ||
  report_failure "(8) the screen never became 6666cc (${LAST_BGS})"
type_keys ctrl-meta_l-backspace
wait_for_count "$SIGTERM_LINE" 2 ||
  report_failure "(8) the chord did not send SIGTERM"
wait_for_count "$RECLAIM" 6 ||
  report_failure "(8) no sixth 'display> reclaim'"
type_line 'echo d8-(math 4+4)'
wait_for_screen 'd8-8' ||
  report_failure "(8) the shell does not answer after the chord"
[ "$(count_log "$SIGKILL_LINE")" -eq 1 ] ||
  report_failure "(8) a SIGKILL went to a program that ended on SIGTERM"
echo "(8) SIGTERM was enough; no SIGKILL"

# ── 판정 9: terminal은 한 번도 죽지 않았다 ───────────────────────────────
echo "=== (9) terminal never restarted ==="
if tlog | grep -aE 'tars-init: restarting' >/dev/null; then
  report_failure "(9) terminal restarted during the run"
fi
if tlog | grep -aE 'terminal: display> (waiting for master|refused|no socket|modeset after reclaim failed)' >/dev/null; then
  report_failure "(9) an unexpected display> line"
fi
[ "$(count_log "$YIELD")" -eq 6 ] && [ "$(count_log "$RECLAIM")" -eq 6 ] ||
  report_failure "(9) yields $(count_log "$YIELD") and reclaims $(count_log "$RECLAIM"), want 6 and 6"
echo "(9) six yields, six reclaims, one busy, no restart"
# 부팅 3의 묶음 옆 version 파일. init은 이미지의 버전과 같을 때만 묶음을 얹는다(layers.zig의 judgeVersion).
IMAGE_VER="$(grep -aoE 'tars-init: starting as PID 1 \(TARS [^)]+\)' "$LOG" | head -1 | sed -E 's/.*TARS ([^)]+)\)/\1/')"
[ -n "$IMAGE_VER" ] || report_failure "(9) no 'starting as PID 1 (TARS …)' line to read the image version from"
stop_boot

# ══ 부팅 2 — root 셸: 양보 중에 terminal이 다시 뜬다(결정 11) ════════════
make_disks 'shell=fish' 'keyboard=apple'
echo "=== boot 2: root shell, terminal restarted while yielded ==="
boot root -drive file="$CONFIG_IMG",if=virtio,format=raw

# ── 판정 10: 새 terminal은 기다리고, 앱이 죽으면 되찾는다 ─────────────────
#
# 앱은 SIGHUP을 무시한다 — 옛 terminal이 끝나며 pty가 닫혀도 산다(initrd에 setsid가 없어 trap으로). pid는 파일에 남긴다.
# reload는 양보 전에 같은 줄로 쳐 둔다(양보 중에는 키가 셸에 안 들어간다). 새 terminal은 손님을 모르므로 키를 새 셸에
# 넣는다(결정 11) — 화면은 앱의 것이라 보이지 않는 셸에 친다.
echo "=== (10) a terminal started while the program holds master waits, then takes the screen back ==="
# reload terminal은 init에 대기 중인 설정이 있어야 화면을 다시 띄운다(`nothing pending`이면 아무것도 안 한다) — 다음
# spawn에 쓰이는 키 하나를 바꿔 둔다(fullscreen 체인 판정 8과 같은 길).
type_line 'tars-config set cursor_shape=bar; tars-config reload'
wait_for_log 'tars-init: reload of /config/tars.conf' ||
  report_failure "(10) tars-config reload never reached init"
type_line "sh -c 'echo \$\$ > /tmp/dy.pid; trap \"\" HUP; exec tars-fullscreen tars-kms-fill 66cc66 0' & sleep 2; tars-config reload terminal"
wait_for_count "$YIELD" 1 ||
  report_failure "(10) no 'display> yield'"
wait_for_log 'tars-init: reload terminal: pid [0-9]+' ||
  report_failure "(10) tars-config reload terminal did not restart terminal"
wait_for_log 'kms: present by \? \(not master yet\)' ||
  report_failure "(10) the new terminal did not see that it is not master"
wait_for_log 'terminal: display> waiting for master' ||
  report_failure "(10) the new terminal did not wait for master"
wait_for_color 66cc66 ||
  report_failure "(10) the program lost the screen when terminal restarted (${LAST_BGS})"
wait_for_count 'terminal: spawned child pid' 2 ||
  report_failure "(10) the new terminal did not spawn a shell"
sleep 3
type_line 'kill -9 (cat /tmp/dy.pid)'
wait_for_count "$RECLAIM" 1 ||
  report_failure "(10) the new terminal never took the screen back"
wait_for_count 'kms: present by dirtyfb' 2 ||
  report_failure "(10) the new terminal did not ask DIRTYFB again once it was master"
type_line 'echo r2-(math 5+5)'
wait_for_screen 'r2-10' ||
  report_failure "(10) the new shell does not answer after reclaim"
if tlog | grep -aE 'giving up on terminal' >/dev/null; then
  report_failure "(10) init gave up on terminal"
fi
echo "(10) the restarted terminal waited, took the screen back when the program died, init never gave up"

# ── 판정 11: 묶음이 없으면 데모가 이유를 말한다 ──────────────────────────
echo "=== (11) without the gpu bundle tars-gpu-demo says why and exits 1 ==="
# shellcheck disable=SC2016 # 게스트의 fish가 펼칠 글자다.
type_line 'tars-gpu-demo; echo g0-$status'
wait_for_screen 'tars-gpu-demo: libSDL3.so.0 not found' ||
  report_failure "(11) tars-gpu-demo did not say libSDL3.so.0 is missing"
wait_for_screen 'g0-1' ||
  report_failure "(11) tars-gpu-demo did not exit 1 without the bundle"
echo "(11) no bundle: 'libSDL3.so.0 not found', exit 1"
stop_boot

# ══ 부팅 3 — 사용자 dyuser, 홈 디스크에 base · gpu 묶음 ═══════════════════
#
# 묶음은 make dev-layers가 구운 것이다(make check CHAIN=display와 make gate가 먼저 부른다). gpu는 base와 겹친 파일이
# 지워진 채 구워지므로(LD-M0) base가 함께 있어야 한다. init은 /home/.tars/layers의 version이 이미지와 같을 때만 얹는다.
for b in base gpu; do
  [ -f "../devlayer/build/${b}.sqfs" ] || report_failure "no devlayer/build/${b}.sqfs — run make dev-layers"
done
make_disks 'shell=fish' 'keyboard=apple' "user=${USER_NAME}"
LAYER_SEED="$(mktemp -d)"
mkdir -p "$LAYER_SEED/.tars/layers"
cp ../devlayer/build/base.sqfs ../devlayer/build/gpu.sqfs "$LAYER_SEED/.tars/layers/"
echo "$IMAGE_VER" > "$LAYER_SEED/.tars/layers/version"
rm -f "$HOME_IMG"
truncate -s $(( $(du -sm "$LAYER_SEED" | cut -f1) + 128 ))M "$HOME_IMG"
mkfs.ext4 -F -q -L tars-home -d "$LAYER_SEED" "$HOME_IMG"
rm -rf "$LAYER_SEED"
echo "=== boot 3: ${USER_NAME} with the base and gpu bundles (version ${IMAGE_VER}) ==="
boot --autorun -drive file="$CONFIG_IMG",if=virtio,format=raw -drive file="$HOME_IMG",if=virtio,format=raw

# 화면 가운데(16 × 16)의 색이 1초 사이에 바뀔 때까지 다시 뜬다 — 데모는 매 frame 띠의 색을 돌리므로, 바뀌면 GL이 그리고
# 있다(terminal의 화면은 그 자리가 멈춰 있다). 30초 — llvmpipe가 CPU 하나에서 처음 뜨는 시간을 넉넉히.
wait_for_motion() {
  local i a b
  for i in $(seq 1 30); do
    screendump "$SHOT" || return 1
    a="$(bg_of 632 392 16 16)"
    sleep 1
    screendump "$SHOT" || return 1
    b="$(bg_of 632 392 16 16)"
    LAST_BGS="$a -> $b"
    if [ -n "$a" ] && [ "$a" != "$b" ] && [ "$a" != 000000 ]; then return 0; fi
  done
  return 1
}

# ── 판정 12: 묶음 둘이 /usr에 얹힌다 ────────────────────────────────────
echo "=== (12) the base and gpu bundles are laid over /usr ==="
wait_for_log 'tars-init: overlay /usr from 2 layers in [0-9]+ms' ||
  report_failure "(12) init did not lay base and gpu over /usr"
echo "(12) overlay /usr from 2 layers"

# ── 판정 12a: base · gpu 둘뿐이라 첫 패널이 데모를 스스로 띄운다(DY-M3) ──────
echo "=== (12a) with only base and gpu the first panel starts tars-gpu-demo by itself ==="
wait_for_count "$YIELD" 1 ||
  report_failure "(12a) the gpu autorun did not ask for the screen (no 'display> yield')"
wait_for_motion ||
  report_failure "(12a) the autorun demo is not drawing (${LAST_BGS:-no shot})"
type_keys esc
wait_for_count "$RECLAIM" 1 ||
  report_failure "(12a) Esc did not end the autorun demo (no 'display> reclaim')"
wait_for_screen "${USER_NAME}@tars" ||
  report_failure "(12a) the ${USER_NAME} prompt did not show up after the autorun demo"
type_line "echo a1-(grep -c 'video kmsdrm' /tmp/gpu-demo.log)"
wait_for_screen 'a1-1' ||
  report_failure "(12a) the autorun demo left no 'video kmsdrm' in /tmp/gpu-demo.log"
echo "(12a) the first panel ran tars-gpu-demo full screen by itself; Esc gave the shell back"

# ── 판정 13: 데모가 GPU로 그리고 키를 받는다 ─────────────────────────────
echo "=== (13) tars-fullscreen tars-gpu-demo draws with SDL3 + GLES and gets the keys ==="
type_line 'tars-fullscreen tars-gpu-demo 2> /tmp/g1.log'
wait_for_count "$YIELD" 2 ||
  report_failure "(13) no 'display> yield' for tars-gpu-demo"
wait_for_count "$HANDED" 2 ||
  report_failure "(13) the inputs were not handed to uid 1000"
wait_for_motion ||
  report_failure "(13) the centre of the screen never changed colour — the demo is not drawing (${LAST_BGS:-no shot})"
type_keys x y z esc
wait_for_count "$RECLAIM" 2 ||
  report_failure "(13) Esc did not end the demo (no 'display> reclaim')"
# 셸이 x y z를 받았으면 이 줄은 `xyzecho …`가 되어 g1-7을 안 찍는다.
type_line 'echo g1-(math 3+4)'
wait_for_screen 'g1-7' ||
  report_failure "(13) the keys typed while yielded leaked into the shell"
type_line "echo g2-(grep -cE 'video kmsdrm|renderer opengles2|key (X|Y|Z)|: esc' /tmp/g1.log)"
if ! wait_for_screen 'g2-6'; then
  type_line 'cat /tmp/g1.log'
  sleep 2
  report_failure "(13) the demo's log does not have video kmsdrm, renderer opengles2, keys X Y Z and esc (its log is on the screen)"
fi
type_line "grep -E 'sdl|gl |mode|frames' /tmp/g1.log"
wait_for_screen 'tars-gpu-demo: frames [0-9]+ in [0-9]+ms' ||
  report_failure "(13) the demo did not count its frames"
echo "(13) KMSDRM + opengles2 drew moving bands; X Y Z and Esc reached the demo through SDL's own udev scan; the shell got nothing"
echo "--- the demo's own lines ---"
joined_screen_dump | grep -aE 'tars-gpu-demo: (sdl|gl|mode|frames) ' | tail -n 4

# ── 판정 14: 탈출 조합 — SDL은 SIGTERM을 QUIT으로 받는다 ─────────────────
echo "=== (14) Ctrl+Cmd+Backspace ends the demo through SIGTERM, no SIGKILL ==="
type_line 'tars-fullscreen tars-gpu-demo 2> /tmp/g3.log'
wait_for_count "$YIELD" 3 ||
  report_failure "(14) no third 'display> yield'"
wait_for_motion ||
  report_failure "(14) the demo is not drawing (${LAST_BGS:-no shot})"
type_keys ctrl-meta_l-backspace
wait_for_count "$SIGTERM_LINE" 1 ||
  report_failure "(14) the chord did not send SIGTERM"
wait_for_count "$RECLAIM" 3 ||
  report_failure "(14) no third 'display> reclaim'"
type_line "echo g3-(grep -c ': quit' /tmp/g3.log)"
wait_for_screen 'g3-1' ||
  report_failure "(14) the demo did not turn SIGTERM into a quit"
# 끝내기에 걸린 시간(데모의 줄) — SIGKILL 판정이 빨갛게 되면 어디가 느린지 여기서 읽는다.
type_line "grep -E 'frames|after the request' /tmp/g3.log"
wait_for_screen 'tars-gpu-demo: frames [0-9]+ in [0-9]+ms' ||
  report_failure "(14) the demo did not leave its loop after the quit"
sleep 1
echo "--- the demo's shutdown lines ---"
joined_screen_dump | tail -n 1 | tr '|' '\n' | grep -aE 'tars-gpu-demo: (frames|left|shut)' | tail -n 3
[ "$(count_log "$SIGKILL_LINE")" -eq 0 ] ||
  report_failure "(14) a SIGKILL went to the demo"
echo "(14) SIGTERM became SDL's quit; reclaimed without SIGKILL"

# ── 판정 15: 복귀 뒤의 화면과 terminal ───────────────────────────────────
echo "=== (15) the console is drawn again after the GL program and terminal never restarted ==="
type_line 'echo g4-(math 4+4)'
wait_for_screen 'g4-8' ||
  report_failure "(15) the shell does not answer after the demo"
if tlog | grep -aE 'tars-init: restarting|terminal: display> (waiting for master|refused|no socket|modeset after reclaim failed)' >/dev/null; then
  report_failure "(15) terminal restarted or printed an unexpected display> line"
fi
screendump "$SHOT" || report_failure "(15) screendump did not write ${SHOT}"
echo "(15) the shell answers on a redrawn console; no restart"
stop_boot

echo "PASS: DY-M2 — init opens /dev/dri to video; terminal yields the screen over /run/tars/display.sock and hands the inputs to the program's uid only while it runs; keys go to the program, not the shell; Ctrl+Cmd+Backspace ends a stuck program (SIGTERM, SIGKILL after 2s); a terminal restarted while yielded waits for master instead of dying; with the gpu bundle tars-gpu-demo draws through SDL3 KMSDRM and OpenGL ES and gets the keys without udevd; with only base and gpu the first panel starts it by itself (DY-M3)"
