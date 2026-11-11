#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# CO 체인 — 커서 모양의 기본값(CO-M1). 서른셋째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   설정 디스크의 cursor_shape=bar → init이 읽어(`tars-init: config … cursor_shape=bar`) terminal의 argv 15번 칸으로
#   → terminal이 받아(`terminal: cursor_shape=bar`) 새 패널의 lib-vt 기본값으로 준다
#   → 첫 프롬프트의 커서가 bar 띠다(`cursor> vt=bar drawn=bar … ink=32 box=2x16`, 반전 0)
#   그리고 프로그램이 정한 모양이 이기고(`CSI 2 SP q` → block) `CSI 0 SP q`가 사용자의 모양으로 되돌리며,
#   vim이 대체 화면에서 모양을 바꾸고 나와도 프롬프트는 bar다. 마지막으로 tars-config set · reload terminal이
#   다시 뜬 terminal을 underline으로 띄운다.
#
# 화면은 1280 × 800(게이트의 다른 체인과 같다). monitor 포트는 45506 — 예약 범위(RP-M0)에서 fullscreen의 45505
# 다음 빈 자리다. 회차당 부팅 1회. 숨김(DECTCEM, CO-M0)은 render 체인의 검사 38 · 39가 본다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# cursor_shape의 파싱 · 견본 · tars-config set의 거절(`beam`) · argv 칸은 여기서 먼저 걸러진다
# (config_test · config_edit_test · reload_test · screen_args_test).
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 기본값이 프로그램의 모양에 지고 `0`에 돌아오는 것(vt_test 검사 134~136)은 여기서 먼저 걸러진다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45506
REPO_ROOT="$(cd .. && pwd)"
XRES=1280
YRES=800

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
  echo "--- config, cursor_shape and reload lines ---"
  tlog | grep -aE 'tars-init: config shell=|terminal: cursor_shape=|tars-init: reload terminal' | tr -d '\r'
  echo "--- last cursor lines ---"
  tlog | grep -a 'terminal: cursor>' | tr -d '\r' | tail -n 5
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

# 아래 다섯은 render/check.sh에서 그대로 가져왔다 — 이유는 그 자리의 주석에 있다.
#
# 마지막으로 끝난 프레임(`screen>`에서 `cursor>`까지), 마지막 `cursor>` 줄, 그 줄을 기다리기, 반전 셀 수, 덤프가 잘렸는가.
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } /terminal: cursor>/ { done = buf } END { printf "%s", done }' "$LOG"
}
last_cursor() { tlog | grep -a 'terminal: cursor>' | tail -n 1 || true; }
wait_for_cursor() {
  local pattern="$1" i
  for i in $(seq 1 150); do
    if grep -aqE -- "$pattern" <<<"$(last_cursor)"; then return 0; fi
    sleep 0.1
  done
  return 1
}
inverted_now() { last_frame | grep -acE 'terminal: style> [0-9]+,[0-9]+ fg=102030 ' || true; }
truncated_now() { last_frame | grep -ac 'more cell(s) not shown' || true; }

# 문자 하나를 sendkey 이름 하나로 바꾼다(render/check.sh의 type_text에서 이 체인이 치는 글자만).
type_text() {
  local s="$1" ch keys=() i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
      [a-z0-9]) keys+=("$ch") ;;
      [A-Z]) keys+=("shift-${ch,,}") ;;
      ' ') keys+=(spc) ;;
      "'") keys+=(apostrophe) ;;
      \\) keys+=(backslash) ;;
      '_') keys+=(shift-minus) ;;
      '=') keys+=(equal) ;;
      '/') keys+=(slash) ;;
      '-') keys+=(minus) ;;
      '[') keys+=(bracket_left) ;;
      '.') keys+=(dot) ;;
      ':') keys+=(shift-semicolon) ;;
      *) report_failure "type_text has no key for '${ch}'" ;;
    esac
  done
  type_keys "${keys[@]}"
}

# 설정 디스크 하나. $1 = 이미지 경로, $2 = 라벨, 나머지 = tars.conf의 줄(fullscreen/check.sh와 같다).
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

# 부팅 하나. $1 = 설정 디스크(fullscreen/check.sh와 같다).
boot() {
  local disk="$1"
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
  wait_for_screen 'root@tars ~#' ||
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

DISK="${REPO_ROOT}/out/co-bar.img"
settings_disk "$DISK" tars-co 'shell=fish' 'cursor_shape=bar'
echo "=== boot: ${XRES}x${YRES}, cursor_shape=bar on the settings disk ==="
boot "$DISK"

# ── 판정 1: 설정이 argv를 건너 terminal에 닿았다 ──────────────────────────
echo "=== (1) the key reaches the terminal ==="
grep -a 'tars-init: loaded /config/tars.conf' "$LOG" >/dev/null ||
  report_failure "the settings disk was not loaded (no 'tars-init: loaded /config/tars.conf')"
tlog | grep -aE 'tars-init: config shell=.* cursor_shape=bar' >/dev/null ||
  report_failure "the tars-init: config line does not carry cursor_shape=bar"
tlog | grep -a 'terminal: cursor_shape=bar' >/dev/null ||
  report_failure "the terminal did not log cursor_shape=bar (argv slot 15 did not arrive)"
echo "(1) tars-init: config … cursor_shape=bar and terminal: cursor_shape=bar"

# ── 판정 2: 첫 프롬프트의 커서가 bar 띠다 ────────────────────────────────
#
# 화면을 지우고 본다 — fish의 인사말은 색을 입혀 style 덤프를 늘린다. 셸은 DECSCUSR을 안 보내므로(CU 실측 8,
# render 검사 20) 이 bar는 사용자의 기본값이다.
# 칸 13은 프롬프트 `root@tars ~# `의 폭이다. LT-M0 전에는 이름이 `(none)`이라 15였다 — 이름을 바꾸는 사람은 이 수를 함께 본다.
echo "=== (2) the prompt cursor is a bar ==="
type_text "printf '\\033[H\\033[2J'"
type_keys ret
wait_for_cursor 'vt=bar drawn=bar row=0 col=13 cols=1 ink=32 box=2x16' ||
  report_failure "the prompt cursor is not a bar at 0,13: $(last_cursor)"
settle_cursor="$(last_cursor)"
if [ "$(truncated_now)" -ne 0 ]; then report_failure "the style dump of the cleared screen was truncated"; fi
if [ "$(inverted_now)" -ne 0 ]; then report_failure "a bar cursor left $(inverted_now) inverted cell(s), 0 expected"; fi
echo "(2) ${settle_cursor#*cursor> }, $(inverted_now) inverted cell(s)"

# ── 판정 3: 프로그램이 정한 모양이 이기고, CSI 0 SP q가 bar로 되돌린다 ───────
#
# 기다리는 줄이 바로 앞 줄과 다른 모양이라, 맞으면 그것은 새 프레임이다.
echo "=== (3) CSI 2 SP q wins, CSI 0 SP q goes back to the bar ==="
type_text "printf '\\033[H\\033[2J\\033[2 q'"
type_keys ret
wait_for_cursor 'vt=block drawn=block row=0 col=13 ' ||
  report_failure "after CSI 2 SP q the cursor is not a block: $(last_cursor)"
type_text "printf '\\033[H\\033[2J\\033[0 q'"
type_keys ret
wait_for_cursor 'vt=bar drawn=bar row=0 col=13 cols=1 ink=32 box=2x16' ||
  report_failure "after CSI 0 SP q the cursor did not go back to the bar: $(last_cursor)"
echo "(3) CSI 2 SP q -> block, CSI 0 SP q -> bar"

# ── 판정 4: vim을 나오면 프롬프트는 다시 bar다 ──────────────────────────
#
# vim의 시스템 vimrc는 normal에서 2(block)를 보낸다(CU-M1). vim은 1049 대체 화면에서 그것을 하고, 기본 화면의
# 모양은 들어가기 전 그대로다(CO design 확인 8). 빈 버퍼의 커서는 줄 번호 칸 뒤 0,4다(render의 VIM_COL).
echo "=== (4) vim switches to a block inside, the prompt is a bar after :q ==="
type_text "vim /tmp/co.txt"
type_keys ret
wait_for_cursor 'vt=block drawn=block row=0 col=4 ' ||
  report_failure "vim did not show a block cursor at 0,4 in normal mode: $(last_cursor)"
type_text ":q"
type_keys ret
wait_for_cursor 'vt=bar drawn=bar .* ink=32 box=2x16' ||
  report_failure "after vim the prompt cursor is not the bar: $(last_cursor)"
echo "(4) vim normal -> block, after :q -> $(last_cursor | sed 's/.*cursor> //')"

# ── 판정 5: tars-config set · reload terminal이 underline으로 다시 띄운다 ─────
echo "=== (5) tars-config set cursor_shape=underline and reload terminal ==="
type_text "tars-config set cursor_shape=underline"
type_keys ret
wait_for_screen 'cursor_shape: bar .*-> underline' ||
  report_failure "tars-config set cursor_shape=underline did not answer 'cursor_shape: bar -> underline'"
type_text "tars-config reload"
type_keys ret
wait_for_log 'tars-init: reload of /config/tars.conf' ||
  report_failure "tars-config reload never reached init"
type_text "tars-config reload terminal"
type_keys ret
wait_for_log 'tars-init: reload terminal: pid [0-9]+, .* cursor_shape=underline' ||
  report_failure "init's reload terminal line does not carry cursor_shape=underline"
wait_for_log 'terminal: cursor_shape=underline' ||
  report_failure "the restarted terminal did not log cursor_shape=underline"
wait_for_screen 'root@tars ~#' ||
  report_failure "the restarted terminal never showed a prompt"
wait_for_cursor 'vt=underline drawn=underline .* ink=16 box=8x2' ||
  report_failure "the restarted terminal's prompt cursor is not an underline: $(last_cursor)"
echo "(5) reload terminal -> $(last_cursor | sed 's/.*cursor> //')"

stop_boot
echo "PASS: CO-M1 — cursor_shape=bar reaches the terminal through argv slot 15, the prompt cursor is a bar, a program's CSI 2 SP q wins and CSI 0 SP q goes back to the bar, vim leaves the prompt a bar, tars-config set and reload terminal bring it back as an underline"
