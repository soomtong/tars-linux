#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# KH-M2: 스물넷째 체인. 부팅 뒤에 꽂은 키보드가 글자를 치고, 키보드 둘이 함께
# 열리고, 빠진 키보드가 닫히는지를 본다(KH design 결정 8).
#
# 기계는 machine 체인처럼 PS/2를 끈 q35이고 부팅 때 키보드가 하나도 없다 — PS/2가
# 남아 있으면 그 키보드가 판정을 대신 초록으로 만든다(machine 체인의 i8042=off와
# 같은 이유). BT 키보드만 쓰는 노트북이 이 모양이다.
#
# 키보드 둘에 따로 치는 길(KH-M0 실측 1 · 2, measurements 100 · 101):
#   k1  화면에 안 묶는다. HMP `sendkey`(type_keys)와 `device` 없는 QMP가 간다.
#   k2  `display=gpu`로 화면에 묶는다. QMP `input-send-event`의 `device: gpu`가 간다.
# 그래서 `virtio-gpu-pci,id=gpu`와 `-qmp`가 있고, `-parallel none`이 있다 — 없으면
# `device`를 준 QMP에서 QEMU가 abort로 죽는다(기본 parallel의 텍스트 콘솔).
#
# 판정 일곱(design 결정 8):
#   1. 키보드 없이 뜬다 — `keyboard> none`, `terminal: opened`가 없다.
#   2. 꽂은 k1이 친다.
#   3. k2를 더 꽂아 둘이 함께 친다.
#   4. 장치를 건너는 조합 — k2의 Shift + k1의 z = Z.
#   5. 장치를 건너는 한글 — k1의 ㄱ + k2의 ㅏ = 가.
#   6. k2를 빼면 닫히고, terminal이 바쁜 루프에 안 빠진다(KH-M0 실측 4).
#   7. Shift를 쥔 채 빠진 키보드의 Shift가 풀린다(결정 4) — 보통은 커널이 푼다.
#   7b. terminal이 그 뗌을 못 읽은 경우에도 풀린다 — 그때 푸는 것이 releaseDevice다(KH 때는 releaseHeld).
#
# DM-M0이 더한 셋(DM design 결정 7, 수정키를 키보드 칸마다 든다):
#   8. k2가 쥔 Shift는 k1의 Shift 뗌에 안 풀린다.
#   9. k2가 빠져도 k1이 쥔 Shift는 남는다.
#   10. 두 키보드의 왼쪽 Ctrl을 겹쳐 누르면 한/영 tap이 아니다(양성 대조 — k1 혼자의 tap은 한/영이다).
#
# BT 키보드의 길(bluetoothd → uhid/hidp → evdev)은 여기 없다. terminal에게는 evdev
# 노드가 부팅 뒤에 생긴다는 것만 같고, 그것을 usb-kbd가 본다(BT design 위험 4).

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
if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

source ../gate_lib.sh

# RP-M0 예약 범위에서 새 체인 몫의 첫 두 자리.
MONITOR_PORT=45495
QMP_PORT=45496

REPO_ROOT="$(cd .. && pwd)"
DISK="${REPO_ROOT}/out/keyboard.img"
LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3>&- 2>/dev/null
  exec 4>&- 2>/dev/null
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
    "tars-init: keyboard device" \
    "tars-init: no keyboard found" \
    "terminal: screen>" \
    "terminal: keyboard> none" \
    "terminal: keyboard> open" \
    "terminal: keyboard> close" \
    "terminal: keyboard> skip" \
    "terminal: keyboard> clock" \
    "terminal: opened" \
    "terminal: key>" \
    "terminal: hangul>" \
    "kh-cpu:" \
    "kh-stop:" \
    "USB disconnect"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- keyboard lines ---"
  tlog | grep -a 'terminal: keyboard>' | tr -d '\r'
  echo "--- last screen ---"
  joined_screen_dump | tail -n 1 | tr -d '\r' | cut -c1-400
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
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

keyboard_count() {
  grep -ac "terminal: keyboard> $1" "$LOG" || true
}

# `terminal: hangul> on=<bool>` 줄의 수(판정 10). 인자가 비면 둘 다 센다. 한/영이 바뀐 키가 `redraw`를 켜고
# `readKeyboard`가 이 줄을 찍는다(`dumpHangul`). 앞 판정이 이미 찍은 줄이 있으므로 있기만을
# 보는 `wait_for_log`로는 못 가르고, 수가 늘었는지를 본다.
hangul_count() {
  grep -ac "terminal: hangul> on=$1" "$LOG" || true
}

wait_for_hangul_count() {
  local on="$1" want="$2" i
  for i in $(seq 1 150); do
    if [ "$(hangul_count "$on")" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

wait_for_keyboard_count() {
  local verb="$1" want="$2" i
  for i in $(seq 1 150); do
    if [ "$(keyboard_count "$verb")" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
}

# n번째 `keyboard> open` 줄의 경로.
open_path() {
  tlog | grep -a 'terminal: keyboard> open ' | sed -n "${1}p" | from_terminal | awk '{print $4}'
}

# QMP 명령 하나를 보내고 답을 읽는다. 답이 `return`이 아니면 실패다 — `error`를
# 삼키면 키가 안 갔는데 판정만 기다리다 15초 뒤에 엉뚱한 문구로 빨개진다.
#
# 같은 소켓에 비동기 이벤트(`{"event": "DEVICE_DELETED", …}`)가 끼어 온다 — `device_del`은
# HMP로 보내도 QMP 쪽에 그것이 뜬다. 그래서 `return` · `error`가 든 줄이 올 때까지 읽는다.
qmp() {
  local reply="" i
  echo "$1" >&4
  for i in $(seq 1 20); do
    reply=""
    read -r -t 5 reply <&4 || break
    case "$reply" in
      *'"return"'*) return 0 ;;
      *'"error"'*) break ;;
    esac
  done
  report_failure "QMP said: ${reply:-nothing} to $1"
}

# 키 하나를 누르거나 뗀다. 첫 인자가 `gpu`면 화면에 묶인 k2로, `-`면 묶이지 않은 k1로.
qmp_key() {
  local where="$1" key="$2" down="$3" dev=""
  [ "$where" = gpu ] && dev='"device":"gpu",'
  qmp "{\"execute\":\"input-send-event\",\"arguments\":{${dev}\"events\":[{\"type\":\"key\",\"data\":{\"down\":${down},\"key\":{\"type\":\"qcode\",\"data\":\"${key}\"}}}]}}"
}

# k2에 글자를 친다. 인자는 qcode이고 `shift-X`는 Shift를 쥔 채 X다. 키 사이 50ms는
# type_keys의 하한과 같다 — 사람의 손보다 빠르지만 같은 키의 누름 · 뗌이 한 SYN에
# 뭉치지 않는다.
qmp_type() {
  local k
  for k in "$@"; do
    case "$k" in
      shift-*)
        qmp_key gpu shift true
        qmp_key gpu "${k#shift-}" true
        qmp_key gpu "${k#shift-}" false
        qmp_key gpu shift false
        ;;
      *)
        qmp_key gpu "$k" true
        qmp_key gpu "$k" false
        ;;
    esac
    sleep 0.05
  done
}

# 그 키보드의 커널 자동 반복을 멈춘다(DM-M0 실측 1). 커널 input core는 장치마다 마지막에
# 누른 키를 250ms 뒤부터 33ms마다 value=2로 반복하고, Shift 같은 수정키도 반복한다. 그 반복이
# terminal의 수정키 비트를 매번 다시 켜서, 쥔 Shift가 풀렸는지를 판정이 못 본다. 같은 장치에서
# 아무 키나 떼면 반복이 멈추므로(`input_stop_autorepeat`), 화면에 아무것도 안 내는 오른쪽 Ctrl을
# 눌렀다 뗀다. 사람의 손에서는 "Shift를 쥔 채 그 키보드로 글자를 하나 친 뒤"가 이 모양이다.
stop_repeat() {
  qmp_key "$1" ctrl_r true
  qmp_key "$1" ctrl_r false
  sleep 0.1
}

# 설정 디스크. 한글 판정이 hangul 체인과 같은 자판(3-P3, `k`=ㄱ · `f`=ㅏ)을 쓰도록 한
# 줄, 그리고 판정 6의 `kh-cpu` — terminal의 utime + stime을 1초 간격으로 두 번 읽어 차를
# 찍는다. 화면 판정 글자 `delta=`는 친 명령줄(`/config/kh-cpu`)에 없다.
#
# 판정 7b의 `kh-stop` — 2초 뒤 terminal을 SIGSTOP으로 멈추고 4초 뒤 SIGCONT한다. 멈춘 동안은
# 화면이 안 그려지므로 두 표식을 `/dev/console`(시리얼)에 직접 쓴다.
mkdir -p "${REPO_ROOT}/out"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-kh "$DISK"
SEED="$(mktemp -d)"
printf 'hangul_layout=sebeol_3p3\n' > "$SEED/tars.conf"
cat > "$SEED/kh-cpu" <<'EOF'
#!/bin/sh
pid=""
for p in /proc/[0-9]*; do
  [ "$(cat "$p/comm" 2>/dev/null)" = terminal ] && pid=${p#/proc/}
done
read -r -a f < "/proc/$pid/stat"
a=$(( f[13] + f[14] ))
sleep 1
read -r -a f < "/proc/$pid/stat"
b=$(( f[13] + f[14] ))
echo "kh-cpu: pid=$pid delta=$(( b - a ))"
EOF
cat > "$SEED/kh-stop" <<'EOF'
#!/bin/sh
pid=""
for p in /proc/[0-9]*; do
  [ "$(cat "$p/comm" 2>/dev/null)" = terminal ] && pid=${p#/proc/}
done
sleep 2
kill -STOP "$pid"
echo "kh-stop: stopped $pid" > /dev/console
sleep 4
kill -CONT "$pid"
echo "kh-stop: continued $pid" > /dev/console
EOF
chmod 0755 "$SEED/kh-cpu" "$SEED/kh-stop"
dbg() { debugfs -w -R "$1" "$DISK" 2>&1 | grep -v '^debugfs' || true; }
dbg "write $SEED/tars.conf tars.conf"
dbg "write $SEED/kh-cpu kh-cpu"
dbg "write $SEED/kh-stop kh-stop"

qemu-system-x86_64 \
  -machine q35,i8042=off \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci,id=gpu \
  -display none \
  -parallel none \
  -device qemu-xhci,id=xhci \
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -qmp tcp:127.0.0.1:${QMP_PORT},server,nowait \
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
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 4<>"/dev/tcp/127.0.0.1/${QMP_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to QMP"
read -r -t 5 _ <&4 || report_failure "QMP sent no greeting"
qmp '{"execute":"qmp_capabilities"}'

# ── 판정 1: 키보드 없이 뜬다 ──────────────────────────────────────────
#
# init은 키보드를 보지 않는다(IK-M0) — 그래서 init의 키보드 줄은 둘 다 없어야 한다.
# KH-M0부터 IK 전까지는 init이 3초를 기다린 뒤 event0(전원 버튼)으로 떨어졌고
# (KH-M0 실측 3, `no keyboard found`), terminal은 그 경로를 안 열었다(결정 1 · 7).
# KH 전에는 여기서 `terminal: opened /dev/input/event0`이 찍히고 전원 버튼이 키보드
# 자리에 있었다. "부팅 때 키보드가 없다"는 이제 아래 `keyboard> none`이 혼자 진다
# (i8042가 켜져 있으면 terminal이 AT 키보드를 연다).
echo "=== 1. no keyboard at boot ==="
if grep -aqE "tars-init: (keyboard device|no keyboard found)" "$LOG"; then
  report_failure "init still looks for a keyboard (IK-M0 took that out)"
fi
grep -aq "terminal: keyboard> none" "$LOG" ||
  report_failure "terminal did not say keyboard> none with no keyboard in the machine"
if grep -aq "terminal: opened" "$LOG"; then
  report_failure "terminal still opens the device path init passed (terminal: opened)"
fi
echo "booted with no keyboard: keyboard> none, and terminal is up"

# ── 판정 2: 부팅 뒤에 꽂은 키보드가 친다 ───────────────────────────────
#
# 이 서브프로젝트의 목표 그 자체다. 출력 `kh10`은 명령줄(`echo kh1$status`)에 없다.
# 같은 노드가 두 칸에 열리면(위험 5) 글자가 두 번씩 가서 명령줄이 `eecchhoo`가 되고
# `kh10`이 안 나온다.
echo "=== 2. a keyboard plugged in after boot types ==="
echo "device_add usb-kbd,bus=xhci.0,id=k1" >&3
wait_for_keyboard_count open 1 ||
  report_failure "the USB keyboard plugged in after boot was never opened"
K1_PATH="$(open_path 1)"
tlog | grep -a "terminal: keyboard> open ${K1_PATH} name=QEMU QEMU USB Keyboard" >/dev/null ||
  report_failure "the first keyboard> open line is not the QEMU USB keyboard"
sleep 0.5
type_keys e c h o spc k h 1 shift-4 s t a t u s ret
wait_for_screen 'kh10' ||
  report_failure "keys from the hotplugged keyboard did not reach the shell (no kh10)"
echo "k1 (${K1_PATH}) opened after boot and typed: kh10"

# ── 판정 3: 키보드 둘이 함께 친다 ─────────────────────────────────────
echo "=== 3. two keyboards at once ==="
echo "device_add usb-kbd,bus=xhci.0,id=k2,display=gpu" >&3
wait_for_keyboard_count open 2 ||
  report_failure "the second keyboard was never opened"
K2_PATH="$(open_path 2)"
[ "$K2_PATH" != "$K1_PATH" ] ||
  report_failure "the second keyboard> open has the same path as the first (${K2_PATH})"
sleep 0.5
qmp_type e c h o spc k h 2 shift-4 s t a t u s ret
wait_for_screen 'kh20' ||
  report_failure "keys sent to k2 did not reach the shell (no kh20)"
type_keys e c h o spc k h 3 shift-4 s t a t u s ret
wait_for_screen 'kh30' ||
  report_failure "keys sent to k1 stopped reaching the shell once k2 was in (no kh30)"
echo "k2 (${K2_PATH}) typed kh20, and k1 still typed kh30"

# ── 판정 4: 장치를 건너는 조합 ────────────────────────────────────────
#
# k2의 Shift를 쥔 채 k1의 z. 키보드들이 수정키를 합쳐 쓰므로 Z다(결정 3, 시나리오 S2).
# 장치마다 따로 들었다면 z다. 출력 `qZq0`은 명령줄(`echo qZq$status`)에 없다.
echo "=== 4. Shift on one keyboard, a letter on the other ==="
type_keys e c h o spc q
sleep 0.3
qmp_key gpu shift true
sleep 0.1
qmp_key - z true
qmp_key - z false
sleep 0.1
qmp_key gpu shift false
sleep 0.3
type_keys q shift-4 s t a t u s ret
wait_for_screen 'qZq0' ||
  report_failure "Shift on k2 did not shift the z typed on k1 (no qZq0)"
echo "k2's Shift and k1's z made Z: qZq0"

# ── 판정 5: 장치를 건너는 한글 ────────────────────────────────────────
#
# 한/영과 조합 중인 음절은 키보드 수와 상관없이 하나다(결정 3, 시나리오 S3). k1으로 한글을
# 켜고 ㄱ, k2로 ㅏ — 조합이 `가`로 이어진다. 끝나면 한글을 끄고(조합이 셸에 확정된다)
# `ctrl-u`로 그 줄을 지운다.
echo "=== 5. one syllable across two keyboards ==="
type_keys shift-spc
wait_for_log 'terminal: hangul> on=true' ||
  report_failure "Shift+Space on k1 did not turn hangul on"
type_keys k
wait_for_log 'terminal: hangul> on=true preedit=[^(]' ||
  report_failure "k on k1 did not start composing (preedit still (none))"
qmp_type f
wait_for_log 'terminal: hangul> on=true preedit=가' ||
  report_failure "f on k2 did not continue ㄱ into 가"
type_keys shift-spc ctrl-u
wait_for_log 'terminal: hangul> on=false' ||
  report_failure "Shift+Space did not turn hangul off again"
echo "k1's ㄱ and k2's ㅏ composed 가"

# ── 판정 6: 빠진 키보드는 닫히고, terminal이 쉰다 ─────────────────────
#
# KH 전에는 키보드 fd의 POLLERR를 아무도 안 봐서 1초에 약 100틱(CPU 하나)을 썼다(KH-M0
# 실측 4). `kh-cpu`가 1초 동안 는 틱을 찍는다. 30은 넉넉한 선이다 — 그 1초에 terminal은
# 명령줄 에코 몇 프레임만 그린다.
echo "=== 6. unplugging a keyboard closes it, and terminal goes quiet ==="
echo "device_del k2" >&3
wait_for_log "terminal: keyboard> close ${K2_PATH}" ||
  report_failure "k2 was unplugged but terminal never closed ${K2_PATH}"
sleep 0.5
type_keys slash c o n f i g slash k h minus c p u ret
wait_for_screen 'kh-cpu: pid=[0-9]+ delta=[0-9]+' ||
  report_failure "kh-cpu never printed its line"
DELTA="$(joined_screen_dump | tail -n 1 | grep -aoE 'kh-cpu: pid=[0-9]+ delta=[0-9]+' | tail -n 1 | sed 's/.*delta=//')"
[ -n "$DELTA" ] || report_failure "could not read kh-cpu's delta"
[ "$DELTA" -lt 30 ] ||
  report_failure "terminal used ${DELTA} ticks in one second after the unplug — a busy loop on the dead fd"
echo "k2 closed, and terminal used ${DELTA} tick(s) in the next second"

# ── 판정 7: 쥔 채 빠진 키보드의 Shift가 풀린다 ────────────────────────
#
# k2를 다시 꽂고 Shift를 누른 채 뗌 없이 뺀다. 안 풀리면 k1으로 친 글자가 전부 대문자라
# `ECHO …`가 되고 `qxq0`이 안 나온다.
#
# 이 판정은 누가 풀었는지를 안 가린다. 커널이 장치를 해제할 때 눌린 키마다 뗌을 흉내 내
# 보내고(`input_disconnect_device`), evdev가 죽은 표시를 하기 전(`cdev_device_del`이 그
# 사이다)에 terminal이 깨어 그 뗌을 읽는다 — closeKeyboard의 releaseHeld(DM 뒤 releaseDevice)를
# 빼도 이 판정은 초록이었다(KH-M2 실측, mutation M-c). 그것만을 보는 것은 아래 7b다.
echo "=== 7. Shift held on a keyboard that goes away is released ==="
echo "device_add usb-kbd,bus=xhci.0,id=k2,display=gpu" >&3
wait_for_keyboard_count open 3 ||
  report_failure "k2 plugged in again was never opened"
K2B_PATH="$(open_path 3)"
sleep 0.5
qmp_key gpu shift true
sleep 0.3
echo "device_del k2" >&3
wait_for_log "terminal: keyboard> close ${K2B_PATH}" ||
  report_failure "k2 (holding Shift) was unplugged but terminal never closed ${K2B_PATH}"
sleep 0.5
type_keys e c h o spc q x q shift-4 s t a t u s ret
wait_for_screen 'qxq0' ||
  report_failure "after k2 left holding Shift, k1 does not type lower case (no qxq0) — the Shift was not released"
echo "k2 left with Shift down, and k1 types lower case: qxq0"

# ── 판정 7b: terminal이 커널의 뗌을 못 읽어도 Shift가 풀린다 ──────────
#
# terminal이 바빠(큰 프레임을 그리는 중) 그 틈을 놓치면 evdev는 죽은 표시가 된 뒤라 read가
# `ENODEV`이고, poll은 `POLLHUP|POLLERR`를 준다 — 버퍼의 뗌은 읽히지 않는다. 그때 Shift를
# 푸는 것은 closeKeyboard의 releaseDevice뿐이다(결정 4). 그 틈을 결정적으로 만든다:
# `kh-stop`이 2초 뒤 terminal을 SIGSTOP으로 멈추고, 그 사이에 Shift를 쥔 k2를 빼고, 4초 뒤
# SIGCONT한다. Shift는 kh-stop을 친 뒤에 누른다 — 먼저 누르면 명령줄이 대문자가 된다.
echo "=== 7b. Shift is released even when terminal missed the kernel's key-up ==="
echo "device_add usb-kbd,bus=xhci.0,id=k2,display=gpu" >&3
wait_for_keyboard_count open 4 ||
  report_failure "k2 plugged in a third time was never opened"
K2C_PATH="$(open_path 4)"
sleep 0.5
type_keys slash c o n f i g slash k h minus s t o p ret
sleep 0.3
qmp_key gpu shift true
wait_for_log 'kh-stop: stopped [0-9]+' ||
  report_failure "kh-stop never stopped terminal"
DISCONNECTS="$(grep -ac 'USB disconnect' "$LOG" || true)"
echo "device_del k2" >&3
for _ in $(seq 1 50); do
  [ "$(grep -ac 'USB disconnect' "$LOG" || true)" -gt "$DISCONNECTS" ] && break
  sleep 0.1
done
[ "$(grep -ac 'USB disconnect' "$LOG" || true)" -gt "$DISCONNECTS" ] ||
  report_failure "the kernel never said USB disconnect for k2 while terminal was stopped"
wait_for_log 'kh-stop: continued [0-9]+' ||
  report_failure "kh-stop never continued terminal"
wait_for_log "terminal: keyboard> close ${K2C_PATH}" ||
  report_failure "after SIGCONT terminal never closed ${K2C_PATH}"
sleep 1
type_keys e c h o spc q y q shift-4 s t a t u s ret
wait_for_screen 'qyq0' ||
  report_failure "k2 left holding Shift while terminal was stopped, and k1 types upper case (no qyq0) — releaseDevice did not run"
echo "terminal was stopped through the unplug, and k1 still types lower case: qyq0"

# ── 판정 8: 겹쳐 쥔 Shift의 한쪽 뗌 ───────────────────────────────────
#
# k2가 Shift를 쥔 채 k1도 Shift를 눌렀다 뗀다. 수정키를 키보드 칸마다 들면 k1의 뗌은 k1의
# 비트만 지우고 k2의 Shift가 남아 z가 Z다(DM design 결정 1, KH 시나리오 S5). 하나로 합쳐
# 들면 k1의 뗌이 비트를 지워 z다. 둘 중 어느 쪽인지를 기다려 가른다 — 빨강의 이유를 문구가
# 바로 말하고, 15초를 기다리지 않는다. 출력 `wZw0`은 명령줄(`echo wZw$status`)에 없다.
# k2의 Shift 반복을 멈추는 것(`stop_repeat`)이 판정의 전제다 — 반복이 살아 있으면 하나로
# 합쳐 든 코드에서도 k2의 반복이 지운 비트를 곧 다시 켜서 Z가 나온다(DM-M0 실측 1).
echo "=== 8. a Shift key-up on one keyboard keeps the Shift held on the other ==="
echo "device_add usb-kbd,bus=xhci.0,id=k2,display=gpu" >&3
wait_for_keyboard_count open 5 ||
  report_failure "k2 plugged in a fourth time was never opened"
K2D_PATH="$(open_path 5)"
sleep 0.5
type_keys e c h o spc w
sleep 0.3
qmp_key gpu shift true
stop_repeat gpu
qmp_key - shift true
sleep 0.1
qmp_key - shift false
sleep 0.1
qmp_key - z true
qmp_key - z false
sleep 0.1
qmp_key gpu shift false
sleep 0.3
type_keys w shift-4 s t a t u s ret
wait_for_screen 'w[zZ]w0' ||
  report_failure "keys for check 8 never reached the shell (neither wZw0 nor wzw0)"
if ! joined_screen_dump | grep -a 'wZw0' >/dev/null; then
  report_failure "k1's Shift key-up released the Shift k2 still holds (wzw0)"
fi
echo "k2 held Shift through k1's Shift tap, and k1's z made Z: wZw0"

# ── 판정 9: 빠진 키보드는 남은 키보드의 Shift를 안 가져간다 ───────────
#
# k1이 Shift를 쥔 채 k2를 뺀다. k2는 아무 키도 안 쥐었으므로 커널이 해제 때 흉내 내는 뗌
# (KH 실측 9)이 없다 — 이 Shift를 지울 수 있는 것은 closeKeyboard뿐이다. 그 칸만 풀면
# (DM design 결정 4) k1의 z가 Z다. 출력 `vZv0`은 명령줄에 없다. k1의 Shift 반복을 먼저
# 멈춘다 — 살아 있으면 DM 전의 releaseHeld가 지운 비트를 k1 자신의 반복이 다시 켠다(DM-M0 실측 1).
echo "=== 9. a keyboard that goes away leaves the other keyboard's Shift alone ==="
type_keys e c h o spc v
sleep 0.3
qmp_key - shift true
stop_repeat -
echo "device_del k2" >&3
wait_for_log "terminal: keyboard> close ${K2D_PATH}" ||
  report_failure "k2 was unplugged but terminal never closed ${K2D_PATH}"
sleep 0.5
qmp_key - z true
qmp_key - z false
sleep 0.1
qmp_key - shift false
sleep 0.3
type_keys v shift-4 s t a t u s ret
wait_for_screen 'v[zZ]v0' ||
  report_failure "keys for check 9 never reached the shell (neither vZv0 nor vzv0)"
if ! joined_screen_dump | grep -a 'vZv0' >/dev/null; then
  report_failure "k2 left and took k1's held Shift with it (vzv0)"
fi
echo "k2 left while k1 held Shift, and k1's z made Z: vZv0"

# ── 판정 10: 겹친 왼쪽 Ctrl은 한/영 tap이 아니다 ──────────────────────
#
# k2가 왼쪽 Ctrl을 쥔 동안 k1의 왼쪽 Ctrl을 짧게 누른다. 다른 칸이 같은 tap 키를 쥐고
# 있을 때의 누름은 조합이라 tap이 아니고, 그 누름이 k2의 tap도 소비한다(DM design
# 결정 2). 하나로 합쳐 들면 k1의 뗌이 k2의 누름에 짝지어져 한/영이 켜진다(KH 시나리오
# S5). 누름부터 마지막 뗌까지 약 150ms라 TAP_MAX_US(300ms) 안이다.
#
# 음성 판정만 있으면 tap 길이 통째로 죽어 있어도(QMP의 키가 늦어 300ms를 넘겨도) 초록이다.
# 그래서 k1 혼자의 tap이 한/영을 켜고 끄는 것을 양성 대조로 함께 본다.
echo "=== 10. overlapping left Ctrl on two keyboards is not a hangul tap ==="
echo "device_add usb-kbd,bus=xhci.0,id=k2,display=gpu" >&3
wait_for_keyboard_count open 6 ||
  report_failure "k2 plugged in a fifth time was never opened"
sleep 0.5
ON0="$(hangul_count true)"
qmp_key gpu ctrl true
sleep 0.05
qmp_key - ctrl true
sleep 0.05
qmp_key - ctrl false
sleep 0.05
qmp_key gpu ctrl false
sleep 1
ON1="$(hangul_count true)"
[ "$ON1" -le "$ON0" ] ||
  report_failure "overlapping left Ctrl on two keyboards toggled hangul (hangul> on=true ${ON0} -> ${ON1})"
# 대조는 켜짐 · 꺼짐을 안 가리고 `on=` 줄 전체가 탭마다 하나씩 느는지 본다. 탭 둘이면 한/영이
# 처음 상태로 돌아온다.
ALL1="$(hangul_count '')"
qmp_key - ctrl true
sleep 0.05
qmp_key - ctrl false
wait_for_hangul_count '' $((ALL1 + 1)) ||
  report_failure "a lone left Ctrl tap on k1 did not toggle hangul — check 10 proves nothing"
qmp_key - ctrl true
sleep 0.05
qmp_key - ctrl false
wait_for_hangul_count '' $((ALL1 + 2)) ||
  report_failure "a second lone left Ctrl tap on k1 did not toggle hangul back"
echo "overlapping Ctrl did not toggle hangul, and k1's lone Ctrl taps turned it on and off"

echo "=== KH-M2 · DM-M0: all eleven checks passed ==="
