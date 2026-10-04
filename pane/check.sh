#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# WP 체인 — 패널 분할 · 닫기 · 순환(WP-M1)과 워크스페이스(WP-M2). 열여덟번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Cmd+D를 누른다
#   → input.zig의 chord()가 그것을 .pane = .split_right로 바꾼다
#   → main.zig가 트리를 가르고 옛 패널을 줄이고(vt resize + TIOCSWINSZ)
#     새 패널에 셸을 띄우고 포커스를 옮긴다
#   → 구분선이 SEPARATOR 색으로 프레임버퍼에 그려진다
#   → 친 글자가 새 패널의 셸에 가고, Cmd+[ 뒤에는 옛 패널의 셸에 간다
#   → Cmd+W가 셸에 SIGHUP을 보내고, 셸이 끝나면 그 패널만 닫힌다
#   → 마지막 패널을 닫으면 terminal이 끝나고 init이 되살린다
#
# copy · render 체인에 끼우지 않은 이유는 WP design 결정 9다. 그 체인들의
# screen> 판정이 "격자 전체 = 패널 하나"를 전제하므로, 그 안에서 가르면 뒤
# 검사가 전부 흔들린다.
#
# 판정의 도구가 셋이다.
#   pane> 줄   — 트리 · 포커스 · 사각형 · 구분선 픽셀(main.zig의 dumpPane)
#   screen> 줄 — 포커스 패널의 글자만 찍힌다(결정 7). 그래서 포커스를 옮긴 뒤
#                "옛 패널의 글자가 없다"는 마지막 줄 하나로 본다. wait_for_screen은
#                로그 전체를 보므로(project_gate_screen_echo) 음성 판정에 못 쓴다.
#   spawned child pid 줄 — 부팅의 첫 셸만 찍는다(WP-M1 plan 확정 1). 그
#                개수가 "terminal이 죽고 init이 되살렸다"의 증거다.
#
# 검사 6과 9가 짝이다(design 결정 9). 6은 "패널 하나를 닫아도 terminal이
# 산다", 9는 "마지막까지 닫으면 끝난다". 하나만 보면 "닫기가 늘 terminal을
# 죽인다"도 "영영 안 죽는다"도 통과한다.
#
# 디스크를 물지 않는다. 패널은 설정과 무관하다.

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

# 트리 산수 · 키 표 · resize는 여기서 먼저 걸러진다(layout_test · input_test ·
# vt_test) — 부팅 1.5초를 쓰기 전에 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 열일곱 체인이 45455~45486을 쓴다. 겹치지 않는 번호를 쓰는 이유는 죽다 만
# QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45487

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
    "terminal: screen>" \
    "terminal: pane>" \
    "terminal: key>" \
    "terminal: child exited (pty EOF)" \
    "terminal: spawned child pid"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- pane lines ---"
  grep -a 'terminal: pane>' "$LOG" | tail -n 20
  echo "--- last screen ---"
  last_screen
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# key> 줄이 지금까지 몇 개 찍혔는지. 패널 명령은 PTY로 바이트를 안 보내므로
# 이 값이 안 늘어야 한다.
key_lines() {
  grep -ac 'terminal: key>' "$LOG" || true
}

# pane> 줄 전부의 개수. 배치가 바뀐 프레임에만 찍히므로(결정 7) 이 값이 안
# 느는 것이 "패널 명령이 아무 일도 안 했다"다. hangup · closed · refused
# 줄도 센다 — 그중 무엇이 찍혀도 명령이 닿은 것이다.
pane_lines() {
  grep -ac 'terminal: pane>' "$LOG" || true
}

# 부팅의 첫 셸만 이 줄을 찍는다. 분할로 띄운 셸은 안 찍는다(plan 확정 1).
spawn_lines() {
  grep -ac 'terminal: spawned child pid' "$LOG" || true
}

exit_lines() {
  grep -ac 'terminal: child exited (pty EOF)' "$LOG" || true
}

# 마지막 배치 줄(`pane> ws=…`). hangup · closed 줄은 모양이 달라 뺀다.
# `tr -d '\r'`은 값이 줄 끝이라 안 지우면 같아 보이는 값으로 실패하기
# 때문이다(HI-M1 실측 4).
last_pane_line() {
  grep -a 'terminal: pane> ws=' "$LOG" | tail -n 1 | tr -d '\r'
}

# 마지막 배치 줄에서 값 하나. ws는 `1/1`이라 `/`까지 받는다.
pane_value() {
  last_pane_line | sed -E "s/.* $1=([0-9/]+).*/\1/"
}

# 마지막 배치 줄의 사각형에서 `col row`.
pane_origin() {
  last_pane_line | sed -E 's/.*rect=([0-9]+),([0-9]+) .*/\1 \2/'
}

# 마지막 프레임의 screen> 줄. 포커스 패널의 것이다(결정 7).
last_screen() {
  grep -a 'terminal: screen>' "$LOG" | tail -n 1
}

# 마지막 배치 줄이 패턴에 맞을 때까지 기다린다. 있으면 0, 15초가 지나면 1.
# gate_lib.sh의 wait_for_screen과 같은 이유로 고정 sleep을 안 쓴다 — 셸 둘이
# 같은 TCG 게스트에서 돌고 있어 한 프레임이 얼마나 걸릴지 아무도 안 쟀다.
wait_for_pane() {
  local pattern="$1" i line
  for i in $(seq 1 150); do
    line="$(last_pane_line)"
    if grep -aqE -- "$pattern" <<<"$line"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 어떤 줄의 개수가 기준보다 커질 때까지 기다린다. 60초 — init이 terminal을
# 되살리는 데 걸리는 시간을 terminal/check.sh가 같은 한도로 본다.
wait_for_more() {
  local fn="$1" before="$2" i
  for i in $(seq 1 600); do
    if [ "$("$fn")" -gt "$before" ]; then return 0; fi
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
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 검사 1: 부팅은 패널 하나짜리 워크스페이스 하나 ─────────────────────
#
# 첫 프레임이 반드시 pane> 줄을 찍는다(dumpPane의 `last`가 null). 구분선이
# 없으므로 sep ink=0 — 이것이 검사 2의 sep ink>0의 대조군이다.
echo "=== boot: one workspace, one pane ==="
wait_for_pane 'ws=1/1 panes=1 focus=0 rect=0,0 ' ||
  report_failure "the boot pane> line is not 'ws=1/1 panes=1 focus=0 rect=0,0 …'"
[ "$(pane_value ink)" -eq 0 ] ||
  report_failure "one pane but sep ink=$(pane_value ink), a separator was drawn with nothing to separate"
BOOT_SPAWNS="$(spawn_lines)"
echo "boot: $(last_pane_line)"

# ── 검사 2: Cmd+D가 오른쪽에 새 패널을 연다 ───────────────────────────
#
# 셋을 본다. 트리(panes=2) · 포커스가 새 패널(focus=1) · 그 사각형이
# 오른쪽(col>0). 그리고 구분선 픽셀이 생겼다 — 트리만 맞고 안 그린 구현을 잡는다.
echo "=== Cmd+D splits to the right ==="
KEYS_BEFORE_SPLIT="$(key_lines)"
type_keys meta_l-d
wait_for_pane 'panes=2 focus=1 ' ||
  report_failure "Cmd+D did not give 'panes=2 focus=1'"
read -r COL ROW <<<"$(pane_origin)"
[ "$COL" -gt 0 ] ||
  report_failure "the new pane is not on the right (rect col=${COL})"
SEP_INK="$(pane_value ink)"
[ "$SEP_INK" -gt 0 ] ||
  report_failure "two panes but sep ink=0, the separator was never drawn"
[ "$(key_lines)" -eq "$KEYS_BEFORE_SPLIT" ] ||
  report_failure "Cmd+D leaked bytes to the PTY (key> ${KEYS_BEFORE_SPLIT} -> $(key_lines))"
echo "split: $(last_pane_line)"

# ── 검사 3: 친 글자가 새 패널의 셸에 가고, 셸이 패널의 폭을 안다 ──────
#
# 출력줄을 본다. 명령줄만 보면 "글자는 그려졌는데 셸이 안 받았다"를 못 가른다.
#
# `$COLUMNS`를 함께 찍는 이유가 이 체인의 mutation이다(WP-M1 실측).
# `applyLayout`에서 `pty.resize`를 빼도 이 체인은 처음에 초록이었다 —
# `echo`의 짧은 출력은 셸이 155칸이라고 믿어도 77칸 안에서 똑같이 보인다.
# 셸이 아는 폭을 직접 물어야 "셸과 우리가 같은 폭을 본다"가 판정된다.
# fish는 SIGWINCH를 받으면 `$COLUMNS`를 고친다. 새 패널은 `spawnPane`이
# 처음부터 77칸으로 띄우므로 이 줄은 대조군이다 — 검사 4b(줄어든 쪽)와
# 9a(늘어난 쪽)가 resize를 본다.
echo "=== typing in the new pane ==="
type_keys e c h o spc r i g h t minus s i d e spc shift-4 \
  shift-c shift-o shift-l shift-u shift-m shift-n shift-s ret
wait_for_screen '\| right-side 77 \|' ||
  report_failure "the new pane's shell did not answer 'right-side 77' (wrong shell, or it thinks the pane is another width)"
echo "the new pane's shell answered: right-side 77"

# ── 검사 4: Cmd+[가 포커스를 왼쪽으로 옮긴다 ──────────────────────────
#
# 마지막 screen> 줄은 이제 왼쪽 패널의 것이라 right-side가 없어야 한다
# (음성). 포커스를 안 옮기고 pane> 줄만 고친 구현은 여기서 걸린다.
echo "=== Cmd+[ moves the focus left ==="
KEYS_BEFORE_FOCUS="$(key_lines)"
type_keys meta_l-bracket_left
wait_for_pane 'panes=2 focus=0 rect=0,0 ' ||
  report_failure "Cmd+[ did not move the focus to leaf 0"
case "$(last_screen)" in
  *right-side*) report_failure "focus is on the left pane but the last screen still shows right-side" ;;
esac
[ "$(key_lines)" -eq "$KEYS_BEFORE_FOCUS" ] ||
  report_failure "Cmd+[ leaked bytes to the PTY (key> ${KEYS_BEFORE_FOCUS} -> $(key_lines))"
echo "focus moved left: $(last_pane_line)"

# ── 검사 4b: 키가 왼쪽 셸에 가고, Cmd+]가 되돌아온다 ──────────────────
echo "=== typing in the left pane, then Cmd+] ==="
# 왼쪽 셸은 155칸으로 떴다가 분할로 77칸이 됐다. 77이라고 답하면 분할이
# `TIOCSWINSZ`를 보냈고 커널이 SIGWINCH를 건넸다는 뜻이다(결정 3).
type_keys e c h o spc l e f t minus s i d e spc shift-4 \
  shift-c shift-o shift-l shift-u shift-m shift-n shift-s ret
wait_for_screen '\| left-side 77 \|' ||
  report_failure "the left pane's shell did not answer 'left-side 77' — if it says 155, the split never told the shell (TIOCSWINSZ)"
type_keys meta_l-bracket_right
wait_for_pane 'panes=2 focus=1 ' ||
  report_failure "Cmd+] did not move the focus back to leaf 1"
case "$(last_screen)" in
  *right-side*) ;;
  *) report_failure "focus is back on the right pane but right-side is not on the last screen" ;;
esac
case "$(last_screen)" in
  *left-side*) report_failure "the right pane's screen shows left-side, the keys went to the wrong shell" ;;
esac
echo "each pane kept its own shell: right-side on the right, left-side on the left"

# ── 검사 4c(음성): copy mode 안의 Cmd+D는 아무 일도 안 한다 ─────────────
#
# design 결정 4. copy 분기가 chord()보다 앞이라 copy 표가 삼킨다. 대조군은
# 모드에 들어갔다는 copy> enter 줄이다 — 그것 없이 "pane> 줄이 안 늘었다"만
# 보면 키가 아예 안 왔어도 통과한다.
echo "=== Cmd+D inside copy mode is swallowed ==="
PANES_BEFORE_COPY="$(pane_lines)"
type_keys meta_l-shift-c
sleep 1
grep -aE 'terminal: copy> enter row=' "$LOG" >/dev/null ||
  report_failure "Cmd+Shift+C did not open copy mode, so the negative check below means nothing"
type_keys meta_l-d
sleep 1
type_keys esc
sleep 1
[ "$(pane_lines)" -eq "$PANES_BEFORE_COPY" ] ||
  report_failure "Cmd+D inside copy mode changed the panes (pane> ${PANES_BEFORE_COPY} -> $(pane_lines))"
[ "$(pane_value panes)" -eq 2 ] ||
  report_failure "after Cmd+D in copy mode there are $(pane_value panes) panes, expected 2"
echo "copy mode swallowed Cmd+D: still $(pane_value panes) panes"

# ── 검사 5: Cmd+Shift+D가 아래에 새 패널을 연다 ───────────────────────
echo "=== Cmd+Shift+D splits below ==="
type_keys meta_l-shift-d
wait_for_pane 'panes=3 focus=2 ' ||
  report_failure "Cmd+Shift+D did not give 'panes=3 focus=2'"
read -r COL ROW <<<"$(pane_origin)"
[ "$ROW" -gt 0 ] ||
  report_failure "the new pane is not below (rect row=${ROW})"
echo "split below: $(last_pane_line)"

# ── 검사 6: Cmd+W가 그 패널만 닫고 terminal은 산다 ────────────────────
#
# 순서가 셋이다 — SIGHUP을 보냈다(hangup) → 셸이 끝나 PTY가 EOF를 냈다
# (child exited) → 그 패널을 닫았다(closed). 그리고 spawned child pid가
# 부팅 때 그대로다: terminal이 끝났다면 init이 되살리며 하나 늘었다.
echo "=== Cmd+W closes one pane, terminal stays ==="
EXITS_BEFORE="$(exit_lines)"
type_keys meta_l-w
# 포커스는 닫힌 패널의 자리를 넘겨받는 형제로 간다(WP-M2, 사용자가 고른
# 것). 2는 오른쪽 절반의 아래였으니 위의 1이 커져 그 자리를 받는다. M1은
# 순회의 다음이라 끝에서 감겨 focus=0(왼쪽)이었다.
wait_for_pane 'panes=2 focus=1 rect=78,0 ' ||
  report_failure "Cmd+W did not leave 'panes=2 focus=1 rect=78,0' (the focus should go to the sibling that took the place)"
grep -aE 'terminal: pane> hangup leaf=2 pid=[0-9]+' "$LOG" >/dev/null ||
  report_failure "no 'pane> hangup leaf=2' line, Cmd+W never sent SIGHUP"
grep -aE 'terminal: pane> closed leaf=2' "$LOG" >/dev/null ||
  report_failure "no 'pane> closed leaf=2' line, the pane was never closed"
[ "$(exit_lines)" -eq $((EXITS_BEFORE + 1)) ] ||
  report_failure "expected one more 'child exited' line, got ${EXITS_BEFORE} -> $(exit_lines)"
sleep 2
[ "$(spawn_lines)" -eq "$BOOT_SPAWNS" ] ||
  report_failure "closing one pane restarted the terminal (spawned child pid ${BOOT_SPAWNS} -> $(spawn_lines))"
echo "one pane closed, terminal alive: $(last_pane_line)"

# ── 검사 9a: 하나 더 닫으면 패널 하나, 구분선 없음 ────────────────────
echo "=== Cmd+W again: one pane left ==="
type_keys meta_l-w
wait_for_pane 'panes=1 focus=[0-9]+ rect=0,0 ' ||
  report_failure "the second Cmd+W did not leave one pane covering the grid"
[ "$(pane_value ink)" -eq 0 ] ||
  report_failure "one pane left but sep ink=$(pane_value ink), the separator outlived the split"
[ "$(spawn_lines)" -eq "$BOOT_SPAWNS" ] ||
  report_failure "closing the second pane restarted the terminal"
echo "one pane left: $(last_pane_line)"

# 남은 패널은 77칸으로 떴다가 형제가 닫혀 155칸이 됐다. 검사 4b의 반대
# 방향이다 — 닫기도 `applyLayout`을 지나 `TIOCSWINSZ`를 보내야 한다.
type_keys e c h o spc w h o l e spc shift-4 \
  shift-c shift-o shift-l shift-u shift-m shift-n shift-s ret
wait_for_screen '\| whole 155 \|' ||
  report_failure "the remaining pane's shell did not answer 'whole 155' — if it says 77, closing never told the shell (TIOCSWINSZ)"
echo "the remaining pane's shell answered: whole 155"

# ── 검사 9b: 마지막 패널을 닫으면 terminal이 끝나고 init이 되살린다 ────
#
# 되살아난 terminal은 새 첫 프레임에 pane> 줄을 다시 찍는다 — panes=1인
# 배치 줄이 하나 는 것이 그 증거다.
echo "=== Cmd+W on the last pane: terminal exits, init restarts it ==="
BOOT_LINES="$(grep -ac 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 ' "$LOG" || true)"
type_keys meta_l-w
wait_for_more spawn_lines "$BOOT_SPAWNS" ||
  report_failure "closing the last pane did not restart the terminal within 60s"
wait_for_more exit_lines "$((EXITS_BEFORE + 2))" ||
  report_failure "no 'child exited' line for the last pane"
for _ in $(seq 1 300); do
  [ "$(grep -ac 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 ' "$LOG" || true)" -gt "$BOOT_LINES" ] && break
  sleep 0.1
done
[ "$(grep -ac 'terminal: pane> ws=1/1 panes=1 focus=0 rect=0,0 ' "$LOG" || true)" -gt "$BOOT_LINES" ] ||
  report_failure "the restarted terminal never printed its boot pane> line"
echo "init restarted the terminal: spawned child pid ${BOOT_SPAWNS} -> $(spawn_lines)"

# ── 워크스페이스(WP-M2) ───────────────────────────────────────────────
#
# 9b가 되살린 terminal에서 시작한다 — 워크스페이스 하나 · 패널 하나.
# 검사 번호는 design 결정 9의 표를 따른다(7 · 8이 워크스페이스).
#
# 상태 줄의 `W` 칸은 워크스페이스가 둘 이상일 때만 뜬다(결정 8). 그 판정은
# 마지막 `status> text=` 줄로 본다.
status_text() {
  grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E 's/.*text=//'
}

# 마지막 `status> caps ink` 줄의 `off=` 값. `CAPS` 칸이 꺼진 색으로 그려진
# 픽셀 수다(IS-M1). hangul 체인의 같은 헬퍼와 같은 모양이다.
caps_off() {
  grep -a 'terminal: status> caps ink ' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E 's/.*off=([0-9]+).*/\1/'
}

RESTART_SPAWNS="$(spawn_lines)"
CAPS_OFF_ONE="$(caps_off)"

# ── 검사 7: Cmd+T가 새 워크스페이스를 끝에 만들고 그리로 간다 ─────────
echo "=== Cmd+T opens a second workspace ==="
type_keys meta_l-t
wait_for_pane 'ws=2/2 panes=1 focus=0 rect=0,0 155x47 ' ||
  report_failure "Cmd+T did not give 'ws=2/2 panes=1 focus=0 rect=0,0 155x47'"
TEXT="$(status_text)"
case "$TEXT" in
  *"  W2") ;;
  *) report_failure "with two workspaces the status line reads \"${TEXT}\", expected it to end with \"  W2\"" ;;
esac
case "$TEXT" in
  *COPY*) report_failure "the status line reads \"${TEXT}\" — COPY outside copy mode" ;;
esac
[ "$(spawn_lines)" -eq "$RESTART_SPAWNS" ] ||
  report_failure "Cmd+T printed 'spawned child pid' (${RESTART_SPAWNS} -> $(spawn_lines)), that line is for the boot shell only"
# `CAPS` 칸의 픽셀이 워크스페이스 하나일 때와 같아야 한다. `drawStatus`가
# 꼬리에서 `W2` 칸만큼 물러나지 않으면 `CAPS`가 회색으로, `  W2`의 앞이
# `CAPS`의 색으로 그려진다 — 글자는 맞아서 `text=`로는 안 보인다(CI design
# 위험 2와 같은 병). 그것을 픽셀로 본다.
for _ in $(seq 1 30); do
  [ "$(grep -ac 'terminal: status> caps ink ' "$LOG" || true)" -gt 0 ] && break
  sleep 0.1
done
[ "$(caps_off)" -eq "$CAPS_OFF_ONE" ] ||
  report_failure "with two workspaces the CAPS field has off=$(caps_off) pixels, with one it had ${CAPS_OFF_ONE} (the W2 field shifted the colours)"
echo "second workspace: $(last_pane_line), status \"${TEXT}\", CAPS off=$(caps_off) (one workspace: ${CAPS_OFF_ONE})"

# ── 검사 7a: 키가 새 워크스페이스의 셸에 간다 ─────────────────────────
echo "=== typing in the second workspace ==="
type_keys e c h o spc w s minus t w o ret
wait_for_screen '\| ws-two \|' ||
  report_failure "the second workspace's shell did not run 'echo ws-two'"
echo "the second workspace's shell answered: ws-two"

# ── 검사 7b(음성): 없는 번호의 Cmd+5는 아무 일도 안 한다 ──────────────
#
# 로그도 안 찍는다. pane> 줄이 안 늘어나야 하고(배치가 그대로) key> 줄도
# 안 늘어나야 한다(`5`가 셸로 새지 않았다). 아무것도 안 찍으므로 type_keys가
# 로그 증가를 못 보고 0.3초 뒤 돌아온다 — 그 뒤 1초를 더 기다린다.
echo "=== Cmd+5 with two workspaces does nothing ==="
PANES_BEFORE_5="$(pane_lines)"
KEYS_BEFORE_5="$(key_lines)"
type_keys meta_l-5
sleep 1
[ "$(pane_lines)" -eq "$PANES_BEFORE_5" ] ||
  report_failure "Cmd+5 with two workspaces changed something (pane> ${PANES_BEFORE_5} -> $(pane_lines))"
[ "$(key_lines)" -eq "$KEYS_BEFORE_5" ] ||
  report_failure "Cmd+5 leaked bytes to the PTY (key> ${KEYS_BEFORE_5} -> $(key_lines))"
echo "Cmd+5 changed nothing: still $(pane_value ws)"

# ── 검사 8: Cmd+1이 첫 워크스페이스로 간다 ────────────────────────────
#
# 첫 워크스페이스도 패널 하나 · 격자 전체라 배치 서명에 워크스페이스 번호가
# 없으면 pane> 줄이 안 찍힌다(WP-M2 plan Task 4). 마지막 screen> 줄에
# ws-two가 없어야 한다 — 화면이 정말 바뀌었다는 음성 판정이다.
echo "=== Cmd+1 goes back to the first workspace ==="
type_keys meta_l-1
wait_for_pane 'ws=1/2 panes=1 ' ||
  report_failure "Cmd+1 did not give 'ws=1/2 panes=1'"
TEXT="$(status_text)"
case "$TEXT" in
  *"  W1") ;;
  *) report_failure "on the first workspace the status line reads \"${TEXT}\", expected it to end with \"  W1\"" ;;
esac
case "$(last_screen)" in
  *ws-two*) report_failure "the first workspace's screen shows ws-two" ;;
esac
echo "first workspace: $(last_pane_line), status \"${TEXT}\""

# ── 검사 8a: Cmd+2가 되돌아오고 그 셸의 화면이 그대로다 ───────────────
echo "=== Cmd+2 comes back ==="
type_keys meta_l-2
wait_for_pane 'ws=2/2 panes=1 ' ||
  report_failure "Cmd+2 did not give 'ws=2/2 panes=1'"
case "$(last_screen)" in
  *ws-two*) ;;
  *) report_failure "back on the second workspace but ws-two is not on the last screen" ;;
esac
echo "second workspace kept its screen: ws-two"

# ── 검사 8b: 워크스페이스의 마지막 패널을 닫으면 그 워크스페이스가 사라진다 ─
#
# terminal은 산다 — 다른 워크스페이스에 패널이 남아 있다. 검사 6과 같은
# 짝의 판정이다: spawned child pid가 그대로다.
echo "=== Cmd+W on the second workspace's only pane ==="
type_keys meta_l-w
wait_for_pane 'ws=1/1 panes=1 ' ||
  report_failure "closing the second workspace's last pane did not bring 'ws=1/1 panes=1'"
grep -aE 'terminal: pane> workspace closed ws=2' "$LOG" >/dev/null ||
  report_failure "no 'pane> workspace closed ws=2' line"
TEXT="$(status_text)"
case "$TEXT" in
  *"  W"[0-9]*) report_failure "one workspace left but the status line still reads \"${TEXT}\"" ;;
esac
sleep 2
[ "$(spawn_lines)" -eq "$RESTART_SPAWNS" ] ||
  report_failure "closing a workspace restarted the terminal (spawned child pid ${RESTART_SPAWNS} -> $(spawn_lines))"
echo "workspace 2 closed, terminal alive: $(last_pane_line), status \"${TEXT}\""

# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "pane> lines:"
grep -a 'terminal: pane>' "$LOG" | tr -d '\r'
echo "status> text lines:"
grep -a 'terminal: status> text=' "$LOG" | tr -d '\r'
echo "WP-M2 check PASS"
