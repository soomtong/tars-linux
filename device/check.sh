#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# HD 체인 — 하드웨어 탐색과 전원 버튼.
#
# 이 게이트가 증명하는 사슬 전체:
#   QEMU monitor의 system_powerdown → QEMU가 ACPI 전원 버튼 이벤트를 만든다
#   → 커널의 acpi/button.c가 그것을 evdev 장치에 KEY_POWER로 올린다
#   → PID 1이 부팅 때 열어 둔 fd의 poll이 깨어난다
#   → init/src/devices.zig의 drainButton이 누름(value 1)을 가려낸다
#   → power.request(.power_off)가 시그널과 같은 플래그를 세운다
#   → 감독 루프 머리의 take()가 종료 순서를 시작한다
#   → reboot(POWER_OFF) → 커널이 ACPI로 전원을 끊는다 → QEMU가 사라진다
#
# PM 체인과 나란히 놓고 보면 이 체인의 자리가 분명해진다. PM은 **셸에서
# 시작하는** 종료를 보고(kill -TERM 1), 이쪽은 **바깥에서 눌린 버튼**으로
# 시작하는 종료를 본다. 마지막 절반은 같지만 첫 절반이 완전히 다르고, 그
# 첫 절반이 HD-M2가 만든 전부다.
#
# 디스크를 물지 않는다. 전원 버튼은 설정과 무관하고, 이 체인은 게스트에 한
# 글자도 타이핑하지 않는다 — 종료 명령이 monitor에서 오기 때문이다. 그래서
# 다른 체인보다 빠르다(회차당 부팅 1회, 타이핑 0회).
#
# -no-reboot을 다는 이유는 power/check.sh 부팅 1과 같다. 다만 그 옵션 때문에
# "QEMU가 사라졌다"가 리셋으로도 성립할 수 있으므로, 아래 음성 검사가
# Restarting system이 없음을 요구해서 둘을 가른다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사 셋(config 파서, 시그널 플래그, 장치 탐색).
# HD-M2가 여기에 얹은 것이 둘이다 — "키보드는 전원 버튼이 아니다"와 "누름만
# 종료가 된다". 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../terminal && zig build test); then
  echo "FAIL: input_test failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM. 겹치지 않는 번호를 쓰는 이유는 죽다
# 만 QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45459

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
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
    "ACPI: button: Power Button" \
    "tars-init: keyboard device /dev/input/event" \
    "tars-init: power button /dev/input/event" \
    "tars-init: watching 1 power button" \
    "terminal: screen>" \
    "tars-init: power button pressed" \
    "tars-init: shutdown requested (action power_off)" \
    "tars-init: sent SIGTERM to every process" \
    "tars-init: filesystems synced" \
    "tars-init: calling reboot(POWER_OFF)" \
    "reboot: Power down"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

qemu-system-x86_64 \
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

# "terminal: screen>" 첫 줄이 곧 부팅이 끝까지 갔다는 신호다. 버튼을 누르기
# 전에 이것을 기다리는 이유는, 감독 루프가 자식을 띄우는 도중에 종료 요청이
# 오는 경우를 이 체인이 다루지 않기 때문이다 — 그 경합은 별도로 볼 일이다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

# ── 탐색 검사 ───────────────────────────────────────────────────────────
#
# 버튼을 누르기 **전에** 본다. 여기서 실패하면 아래의 종료가 왜 안 됐는지를
# 따로 물을 필요가 없다.

# 커널 쪽 전제. ACPI가 꺼지면 여기가 먼저 실패한다.
grep -q "ACPI: button: Power Button" "$LOG" \
  || report_failure "the kernel did not register an ACPI power button"

# 키보드는 여전히 성질로 찾아야 한다. 번호를 요구하지 않는 이유는 탐색기를
# 만든 이유와 같다(design 결정 2).
grep -q "tars-init: keyboard device /dev/input/event" "$LOG" \
  || report_failure "init did not discover a keyboard device"
if grep -q "tars-init: no keyboard found" "$LOG"; then
  report_failure "init fell back to event0 instead of discovering a keyboard"
fi

# 전원 버튼도 마찬가지다. 이 음성 검사가 없으면 탐색이 조용히 실패해도
# 부팅은 멀쩡해 보인다 — 그리고 아래 종료가 실패하는 이유를 알 수 없다.
grep -q "tars-init: power button /dev/input/event" "$LOG" \
  || report_failure "init did not open any power button"
if grep -q "tars-init: no power button found" "$LOG"; then
  report_failure "init found no power button at all"
fi

# ★ 개수를 요구하는 것이 이 체인에서 가장 값진 한 줄이다.
#
# QEMU의 AT 키보드도 KEY_POWER를 갖고 있다(devices_test의 실측 비트맵 1번
# 워드 0xfeffffdfffefffff의 52번 비트). looksLikePowerButton이 키보드를
# 제외하지 않으면 여기가 2가 되고, 그러면 PID 1이 글자 하나마다 깨어나는
# 상태로 조용히 굴러간다 — 종료는 여전히 되므로 개수를 안 보면 아무도
# 모른다.
grep -q "tars-init: watching 1 power button" "$LOG" \
  || report_failure "init is not watching exactly one power button (did the keyboard sneak in?)"

echo "init found the keyboard and exactly one power button"

# ── 버튼을 누른다 ───────────────────────────────────────────────────────

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# QEMU의 system_powerdown은 ACPI 전원 버튼을 누른 것과 같다. sendkey와 달리
# 키보드를 거치지 않으므로, 이 체인은 IP 체인의 번역 경로를 하나도 밟지
# 않는다 — 여기서 증명되는 것은 순수하게 버튼 경로다.
echo "=== sending system_powerdown to the guest ==="
echo "system_powerdown" >&3
sleep 0.3

exec 3<&-
exec 3>&-

# 로그의 문자열이 아니라 프로세스의 존재를 본다. HD-M1이 power 체인에 세운
# 것과 같은 통과 조건이다.
GONE=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 1
done

[ "$GONE" = "1" ] \
  || report_failure "the machine never switched itself off after the power button"

# 여기서 거둬야 좀비가 남지 않고, EXIT trap의 cleanup이 이미 없는 PID를
# 건드리지 않는다. 아래 검사들은 완성된 로그를 읽는다.
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

# ── 어떻게 꺼졌는가 ─────────────────────────────────────────────────────
#
# 위의 GONE 하나만 보면 기계가 꺼진 것은 알 수 있지만 **왜** 꺼졌는지는 알 수
# 없다. 특히 첫 줄이 중요하다 — 그것이 없으면 버튼이 아니라 다른 경로로
# 꺼졌다는 뜻이고, 이 체인이 존재할 이유가 사라진다.
for marker in \
  "tars-init: power button pressed" \
  "tars-init: shutdown requested (action power_off)" \
  "tars-init: sent SIGTERM to every process" \
  "tars-init: filesystems synced" \
  "tars-init: calling reboot(POWER_OFF)"; do
  grep -q "$marker" "$LOG" || report_failure "missing shutdown log line: ${marker}"
done

# 커널 쪽 증거(kernel/reboot.c:711).
grep -q "reboot: Power down" "$LOG" \
  || report_failure "the kernel never reported 'Power down'"

# 음성 검사 1 — PID 1이 죽어서 커널이 패닉한 것이 아니어야 한다.
if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "the kernel panicked instead of shutting down cleanly"
fi

# 음성 검사 2 — POWER_OFF가 HALT로 강등되지 않았는가.
if grep -q "Power off not available: System halted instead" "$LOG"; then
  report_failure "the kernel demoted POWER_OFF to a halt; is CONFIG_ACPI still on?"
fi

# 음성 검사 3 — 꺼진 것이지 리셋된 것이 아니어야 한다. -no-reboot이 붙어
# 있어서 게스트가 리셋을 걸어도 QEMU는 사라지고, 그러면 위의 GONE이 엉뚱한
# 이유로 참이 된다.
if grep -q "Restarting system" "$LOG"; then
  report_failure "the guest reset the machine instead of powering it off"
fi

# 음성 검사 4 — 종료 중에 감독 루프가 자식을 되살리면 안 된다. poll 구조로
# 바꾸면서 루프 머리의 take()가 start()보다 앞이라는 성질이 깨지면 이 개수가
# 는다. PM 체인이 콘솔 셸로 보는 것을 이쪽은 terminal로 본다.
STARTED="$(grep -c "tars-init: started terminal" "$LOG" || true)"
if [ "$STARTED" != "1" ]; then
  report_failure "the supervisor started the terminal ${STARTED} times, want exactly 1"
fi

# 음성 검사 5 — poll 구조가 자식을 잘못 포기하면 안 된다. 이 체인에는 GPU가
# 있으므로 terminal은 살아 있어야 한다.
if grep -q "tars-init: giving up on" "$LOG"; then
  report_failure "the supervisor gave up on a child that should have stayed alive"
fi

echo "--- init log ---"
grep 'tars-init:' "$LOG" || true

echo "HD-M2 PASS: the guest switched itself off because someone pressed the power button"
