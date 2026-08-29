#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# PM 체인 — 전원 관리.
#
# 이 게이트가 증명하는 사슬 전체:
#   sendkey k,i,l,l,... → 커널 atkbd → evdev → terminal/src/input.zig가
#   바이트를 만든다 → pty write → bash가 kill 빌트인을 실행한다
#   → 커널이 PID 1에게 SIGTERM을 배달한다(핸들러가 있을 때만!)
#   → init/src/power.zig가 자식을 정리하고 reboot(2)를 부른다
#   → 커널이 시스템을 멈춘다
#
# 마지막 칸을 게이트가 어떻게 보는가가 이 체인의 성격을 정한다. HD-M1이
# 커널에 ACPI를 켜기 전에는 reboot(POWER_OFF)이 HALT로 강등돼서 QEMU가 스스로
# 끝나지 않았고, 이 게이트가 대신 죽여 줬다. 이제는 **QEMU가 스스로 사라지는
# 것**이 통과 조건이다 — 우리가 죽여 주던 그 손길이 없어진 것 자체가 전원이
# 진짜로 끊겼다는 증거다.
#
# -no-reboot은 그대로 둔다. 전원을 끄는 경로에는 영향이 없고, 루트 게이트가
# 이 체인을 회차당 세 번 돌리는 동안 예기치 못한 리셋 고리에 빠지는 것을
# 막아 준다. 다만 그 옵션 때문에 "QEMU가 사라졌다"가 리셋으로도 성립할 수
# 있으므로, 아래 음성 검사 4가 Restarting system이 없음을 요구해서 둘을 가른다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사 둘(config.zig의 parse, power.zig의 시그널
# 플래그). 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
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

if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP. 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가
# 남았을 때 엉뚱한 게스트에 키를 보내지 않기 위해서다.
MONITOR_PORT=45458

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
    "tars-init: mounted ext2 at /config" \
    "tars-init: config shell=bash" \
    "tars-init: signal handlers installed" \
    "terminal: screen>" \
    "tars-init: shutdown requested" \
    "tars-init: sent SIGTERM to every process" \
    "tars-init: every child is gone" \
    "tars-init: filesystems synced" \
    "tars-init: calling reboot" \
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

# 게스트 셸에 한 글자씩 타이핑한다. CP·IP와 같은 함수다 — sendkey가 보내는
# 것은 문자가 아니라 **키**이므로, 대문자는 shift-를 붙여야 한다.
source ../gate_lib.sh

# kill -TERM 1
KILL_KEYS=(k i l l spc minus shift-t shift-e shift-r shift-m spc 1 ret)

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="${REPO_ROOT}/out/power.img",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

# "terminal: screen>" 첫 줄이 곧 DRM 열기 + 폰트 래스터라이즈 + evdev 열기 +
# 셸 spawn + 첫 렌더가 전부 끝났다는 신호다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

# 디스크가 정말 읽혔는지 먼저 본다. 이 줄이 없으면 셸은 fish이고, 그러면
# 아래 타이핑은 kill을 못 찾아서 실패한다 — 그 실패를 시그널 처리의 실패로
# 오진하지 않도록 여기서 갈라둔다.
grep -q "tars-init: config shell=bash" "$LOG" \
  || report_failure "the config disk was not read; the shell is not bash"

# bash가 정말 떴는지. --norc로 뜬 bash의 기본 PS1은 `\s-\v\$`라 화면에
# `bash-5.2$` 같은 프롬프트가 그려진다.
BASH_OK=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*bash-" "$LOG"; then BASH_OK=1; break; fi
  sleep 1
done
[ "$BASH_OK" = "1" ] || report_failure "the PTY shell never showed a bash prompt"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

echo "=== typing 'kill -TERM 1' into the guest ==="
type_keys "${KILL_KEYS[@]}"

# 종료 순서가 도는 데 걸리는 시간은 유예 3초가 지배한다. 대화형 셸은
# SIGTERM을 무시하므로(POSIX), 셸 둘은 그 3초가 지난 뒤 SIGKILL로 죽는다.
# 로그의 문자열이 아니라 **프로세스의 존재**를 본다. 이것이 HD-M1이 바꾼
# 통과 조건이다 — 게스트가 reboot(POWER_OFF)을 불렀고 커널이 그것을 ACPI로
# 실행했다면, QEMU는 우리가 아무것도 하지 않아도 사라진다.
GONE=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

[ "$GONE" = "1" ] \
  || report_failure "the machine never switched itself off after kill -TERM 1"

# 여기서 거둬야 좀비가 남지 않고, EXIT trap의 cleanup이 이미 없는 PID를
# 건드리지 않는다. 아래 검사들은 QEMU가 끝난 뒤의 완성된 로그를 읽는다.
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

# 여기서부터는 "어떻게 꺼졌는가"를 따진다. 위의 GONE 하나만 보면 기계가
# 꺼진 것은 알 수 있지만 **왜** 꺼졌는지는 알 수 없다.
for marker in \
  "tars-init: signal handlers installed (TERM, INT)" \
  "tars-init: shutdown requested (action power_off)" \
  "tars-init: sent SIGTERM to every process" \
  "tars-init: every child is gone" \
  "tars-init: filesystems synced" \
  "tars-init: calling reboot(POWER_OFF)"; do
  grep -q "$marker" "$LOG" || report_failure "missing shutdown log line: ${marker}"
done

# 음성 검사 1 — PID 1이 죽어서 커널이 패닉한 것이 아니어야 한다. HD-M1 전에는
# 이 검사가 HALT_MARKER 하나로는 갈라지지 않는 두 경우를 갈라 주는 역할이었다.
# 이제는 패닉이 나도 기계가 꺼지지는 않으므로 위의 GONE이 먼저 실패한다.
# 그래도 남겨 두는 이유는 실패의 이유에 이름을 붙여 주는 것이 이 한 줄이기
# 때문이다.
if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "the kernel panicked instead of shutting down cleanly"
fi

# 음성 검사 2 — 종료 중에 감독 루프가 자식을 되살리면 안 된다. 되살리면
# 이 줄이 둘 이상이 된다.
STARTED="$(grep -c "tars-init: started console shell" "$LOG")"
if [ "$STARTED" != "1" ]; then
  report_failure "the supervisor restarted the console shell during shutdown (started ${STARTED} times)"
fi

# 음성 검사 3 — POWER_OFF가 HALT로 강등되지 않았는가. 커널에서 ACPI가
# 빠지면 이 줄이 다시 나온다. 그때는 위의 GONE도 함께 실패하지만, 실패의
# **이유**를 알려 주는 것은 이 한 줄뿐이다.
if grep -q "Power off not available: System halted instead" "$LOG"; then
  report_failure "the kernel demoted POWER_OFF to a halt; is CONFIG_ACPI still on?"
fi

# 음성 검사 4 — 꺼진 것이지 리셋된 것이 아니어야 한다. -no-reboot이 붙어
# 있어서 게스트가 리셋을 걸어도 QEMU는 사라지고, 그러면 위의 GONE이 엉뚱한
# 이유로 참이 된다. 그 경로를 여기서 막는다.
if grep -q "Restarting system" "$LOG"; then
  report_failure "the guest reset the machine instead of powering it off"
fi

# 양성 검사 — 커널이 전원 차단 경로를 실제로 밟았다는 줄(kernel/reboot.c:711).
# QEMU가 사라졌다는 사실만으로는 커널이 어디까지 갔는지 알 수 없다.
grep -q "reboot: Power down" "$LOG" \
  || report_failure "the kernel never reported 'Power down'"

# 관측만 하는 줄. 셸이 SIGTERM을 무시하는 것이 정상이므로 이 줄이 나오는
# 것은 실패가 아니다. 어느 경로였는지 사람이 알 수 있게 남긴다.
if grep -q "tars-init: grace period expired" "$LOG"; then
  echo "note: the grace period expired and SIGKILL finished the job (this is the normal path)"
else
  echo "note: every child died from SIGTERM alone"
fi

echo "boot 1/2 PASS: the guest shut itself down from a shell command"

# ============================================================== 부팅 2/2 (A)
# 재시작 경로. **-no-reboot을 뺀다** — 게스트가 reboot(RESTART)를 부르면 QEMU가
# 정말로 다시 부팅해야 하기 때문이다. 두 부팅의 QEMU 옵션이 이렇게 갈리는 것이
# PM을 기존 체인에 얹지 않고 새 체인으로 만든 이유였다(design 결정 8).
#
# 디스크는 방금 부팅 1이 쓰던 것을 그대로 재사용한다. 부팅 1은 설정을 고치지
# 않으므로(친 것은 kill -TERM 1 하나다) 여기 들어올 때 디스크는 여전히
# shell=bash이고, 그것이 이 부팅의 전제다. make_disk.sh를 다시 부르지 않는다.
#
# 이 부팅 하나가 증명하는 것:
#   Ctrl+Alt+Del → 커널이 PID 1에게 SIGINT를 보낸다(CAD_OFF를 불렀을 때만!)
#   → 우리 종료 순서가 돈다 → reboot(RESTART) → 커널이 기계를 리셋한다
#   → 같은 QEMU가 다시 뜬다 → 게스트가 아까 쓴 설정을 읽는다 → zsh가 뜬다

LOG_A="$(mktemp)"
# 두 번째 부팅 구간만 잘라낸 것. design 결정 8이 "그 뒤에"라고 요구한 순서를
# grep만으로는 지킬 수 없어서, 파일을 나누어 조건을 파일 자체로 만든다.
SECOND="$(mktemp)"

# 부팅 2에서 두 번째 부팅 구간을 다시 잘라낸다. 로그가 계속 자라므로 검사할
# 때마다 새로 자른다.
slice_second_boot() {
  awk '/tars-init: starting as PID 1/{n++} n>=2' "$LOG_A" > "$SECOND"
}

count_boots() {
  grep -c "tars-init: starting as PID 1" "$LOG_A" 2>/dev/null || true
}

report_failure_a() {
  echo "FAIL(boot 2): $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "tars-init: signal handlers installed (TERM, INT)" \
    "tars-init: ctrl-alt-del now arrives as SIGINT" \
    "terminal: screen>" \
    "tars-init: shutdown requested (action restart)" \
    "tars-init: every child is gone" \
    "tars-init: filesystems synced" \
    "tars-init: calling reboot(RESTART)" \
    "Restarting system" \
    "tars-init: config shell=zsh"; do
    if grep -q "$marker" "$LOG_A"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- boots seen: $(count_boots) (want exactly 2) ---"
  echo "--- last 80 lines ---"
  tail -n 80 "$LOG_A"
  exit 1
}

# echo shell=zsh > /config/tars.conf — CP 체인과 같은 시퀀스다. sendkey가
# 보내는 것은 문자가 아니라 키이므로 '='는 equal, '>'는 shift-dot이다.
EDIT_KEYS=(e c h o spc s h e l l equal z s h spc shift-dot spc
           slash c o n f i g slash t a r s dot c o n f ret)

echo "=== boot 2/2: edit the config in the guest, then ctrl-alt-delete ==="

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="${REPO_ROOT}/out/power.img",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG_A" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG_A"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure_a "terminal never rendered a prompt"
sleep 1

# 부팅 1과 같은 디스크이므로 여기도 bash여야 한다. 아니라면 부팅 1이 디스크를
# 건드렸다는 뜻이고, 그건 이 체인의 전제가 무너진 것이다.
grep -q "tars-init: config shell=bash" "$LOG_A" \
  || report_failure_a "the first boot left the disk in an unexpected state (not bash)"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure_a "could not connect to the QEMU monitor"

echo "=== typing the config edit into the guest ==="
type_keys "${EDIT_KEYS[@]}"
sleep 1

# 여기가 이 체인의 심장이다. sendkey ctrl-alt-delete는 커널의 VT 키보드
# 핸들러(drivers/tty/vt/keyboard.c:618의 fn_boot_it)까지 가고, 그것이
# ctrl_alt_del()을 부른다. 그 다음에 무슨 일이 생기는지가 C_A_D 값에 갈린다:
#   C_A_D = 1 (기본값) → 커널이 우리를 건너뛰고 즉시 재부팅한다
#   C_A_D = 0 (우리가 CAD_OFF로 바꾼 뒤) → PID 1에게 SIGINT가 온다
# 겉으로는 둘 다 "재부팅됐다"로 보이기 때문에, 아래 검사가 그 둘을 가른다.
echo "=== sending ctrl-alt-delete ==="
echo "sendkey ctrl-alt-delete" >&3
sleep 0.3

exec 3<&-
exec 3>&-

# 두 번째 부팅이 시작될 때까지 기다린다.
BOOTS=0
for _ in $(seq 1 90); do
  BOOTS="$(count_boots)"
  if [ "${BOOTS:-0}" -ge 2 ]; then break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "${BOOTS:-0}" -ge 2 ] \
  || report_failure_a "the guest never came back up after ctrl-alt-delete"

# ★ 이 여섯 줄이 "재부팅됐다"와 "우리를 거쳐 재부팅됐다"를 가른다. 이것들
#   없이 위의 BOOTS >= 2만 보면, reboot(CAD_OFF)를 한 줄도 안 쓴 상태에서도
#   게이트가 통과한다 — 커널이 직접 재부팅해도 게스트는 다시 뜨기 때문이다.
for marker in \
  "tars-init: signal handlers installed (TERM, INT)" \
  "tars-init: ctrl-alt-del now arrives as SIGINT" \
  "tars-init: shutdown requested (action restart)" \
  "tars-init: sent SIGTERM to every process" \
  "tars-init: filesystems synced" \
  "tars-init: calling reboot(RESTART)"; do
  grep -q "$marker" "$LOG_A" || report_failure_a "missing restart log line: ${marker}"
done

# 커널 쪽 증거. 우리가 부른 reboot(2)를 커널이 정말 받았다는 줄이다
# (kernel/reboot.c:294). POWER_OFF와 달리 RESTART는 강등되지 않는다.
grep -q "Restarting system" "$LOG_A" \
  || report_failure_a "the kernel never reported 'Restarting system'"

# 재부팅 뒤의 구간에서만 찾는다. 1차 부팅의 줄과 섞이면 순서를 증명할 수 없다.
ZSH_OK=0
for _ in $(seq 1 60); do
  slice_second_boot
  if grep -q "tars-init: started console shell (pid .*, /usr/bin/zsh)" "$SECOND"; then
    ZSH_OK=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done

slice_second_boot
grep -q "tars-init: config shell=zsh" "$SECOND" \
  || report_failure_a "the second boot did not read the config the guest had written"

[ "$ZSH_OK" = "1" ] \
  || report_failure_a "the second boot parsed zsh but never exec'd /usr/bin/zsh"

# 재부팅 고리 감시. -no-reboot을 뺐으므로 원리적으로 가능한 실패다. 부팅 한
# 번이 약 4초이므로, 고리에 빠졌다면 이 3초 안에 개수가 한 번 더 는다.
sleep 3
FINAL="$(count_boots)"
if [ "${FINAL:-0}" -gt 2 ]; then
  report_failure_a "the guest booted ${FINAL} times; it is stuck in a reboot loop"
fi

# 음성 검사 — 부팅 1과 같은 이유다. PID 1이 죽어서 커널이 패닉해도 시스템은
# 어차피 멈추고 QEMU는 -no-reboot 없이 다시 뜰 수 있다.
if grep -q "Attempted to kill init" "$LOG_A"; then
  report_failure_a "the kernel panicked instead of restarting cleanly"
fi

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

echo "boot 2/2 PASS: ctrl-alt-delete went through PID 1 and the new config took effect"

echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG_A" || true

echo "PM-M1 PASS: the guest can shut itself down and bring itself back up"
