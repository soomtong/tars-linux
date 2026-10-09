#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# BS 체인 — 상태 줄의 배터리 칸(BS-M1). 스물두번째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   커널에 test_power가 내장되고, 내장 cmdline의 test_power.battery_present=false가 그
#   배터리를 끈다(BS design 결정 9의 겹 1)
#   → terminal이 첫 프레임 전에 /sys/class/power_supply를 훑는다. test_battery가 있지만
#     present가 0이라 안 센다. 상태 줄은 BS 전과 같다(검사 A1)
#   → 셸에서 battery_present에 true를 쓰면 test_power가 test_ac에 uevent를 보낸다
#   → terminal의 uevent 소켓(PD-M0이 연 것)이 SUBSYSTEM=power_supply를 보고 다시 훑는다.
#     상태 줄의 오른쪽 끝에 넉 자 ` 50%`가 회색으로 뜬다(검사 A2)
#   → 키도 PTY 출력도 없이 잔량이 10이 되면 그 칸만 빨강 ` 10%`로 다시 그린다(검사 A3)
#   → 글자가 그대로인 채 충전이 시작되면 초록이 되고 새 줄이 찍힌다(검사 A4)
#   → 배터리를 끄면 칸이 사라진다(검사 A5)
#   → 부팅 cmdline으로 켠 배터리는 첫 프레임에 이미 칸이 있다(검사 B1)
#
# 판정은 전부 terminal의 줄이다 — battery> scan · battery> read(main.zig의 배터리 절)와
# status> battery(dumpStatus가 띠의 픽셀을 색마다 센 것). 화면 글자로는 판정하지 않는다.
# 상태 줄은 격자 밖이라 screen>에 안 나오고, 그래서 친 명령의 에코가 판정을 속일 자리도
# 없다(docs/decisions/project_gate_screen_echo.md). screen>은 검사 A3에서 "그 프레임에 칸
# 말고 바뀐 것이 없다"를 보는 데만 쓴다.
#
# 부팅이 둘이다. A는 내장 cmdline 그대로(배터리 꺼짐)이고 monitor로 친다. B는 -append로
# 배터리를 켜고 아무것도 안 친다. 둘 다 디스크를 물지 않는다 — 배터리는 설정과 무관하다.
#
# 주기 경로(60초)는 안 본다(BS design 결정 11). test_power의 setter가 전부 uevent를
# 부르므로 "uevent 없이 바뀐 값"을 게스트에서 만들 길이 없다. 그 길은 battery_test의
# pollTimeout 검사가 호스트에서 본다.

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

# sysfs 글자 · 고르기 · 갈래 · 칸 글자 · uevent · poll timeout은 여기서 먼저 걸러진다
# (battery_test, BS-M0) — 부팅 전에 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# ── 검사 0: 커널과 부트로더가 가짜 배터리를 안다 (부팅 없음) ──────────────
#
# 기호 셋 중 하나만 빠져도 아래 부팅이 전부 빨갛지만, 그 빨강은 "terminal이 배터리를 못
# 읽는다"처럼 보인다. 여기서 먼저 갈라 둔다.
#
# 내장 cmdline은 낱말 하나만 본다(BS design 결정 9). 같은 줄에 wifi 체인의 낱말도 있다.
# 값이 0이 아니라 false인 것이 중요하다 — test_power는 0을 조용히 무시하고 배터리가 켜진
# 채 남는다(design 확인 2). 그 사고는 검사 A1이 다시 본다.
#
# limine의 블랙리스트는 실기에서 test_power를 아예 등록하지 않게 하는 겹 2다. 이 체인은
# -kernel로 떠서 limine을 안 지나므로 그 효과는 machine 체인이 본다(판정 14).
CONFIG=../kernel/.config
for sym in TEST_POWER ACPI_BATTERY POWER_SUPPLY; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym}=y is missing from kernel/.config"
    exit 1
  fi
done
if ! grep -E '^CONFIG_CMDLINE="([^"]* )?test_power\.battery_present=false( [^"]*)?"$' "$CONFIG" >/dev/null; then
  echo "FAIL: the built-in cmdline no longer turns test_power's battery off (test_power.battery_present=false)"
  exit 1
fi
if ! grep -E '^[[:space:]]*cmdline:(.* )?initcall_blacklist=test_power_init( .*)?$' ../boot/limine.conf >/dev/null; then
  echo "FAIL: boot/limine.conf no longer keeps test_power from registering (initcall_blacklist=test_power_init)"
  exit 1
fi
echo "the kernel has test_power, ACPI_BATTERY and POWER_SUPPLY; the built-in cmdline turns the battery off; limine blacklists test_power"

# 스물한 체인이 45455~45493을 쓴다(docs/guides/lessons.md의 포트 목록). 부팅 B는 monitor가 없다.
MONITOR_PORT=45494

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
    "terminal: battery> scan " \
    "terminal: battery> scan failed" \
    "terminal: battery> read " \
    "terminal: status> battery " \
    "terminal: pointer> uevent failed" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- battery and status lines ---"
  grep -aE 'terminal: (battery> |status> (text=|battery ))' "$LOG" | tr -d '\r' | tail -n 30
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# 접두가 $1인 마지막 줄. 값이 줄 끝까지 가므로 \r를 지운다(HI-M1 실측 4).
last_line() {
  grep -a "$1" "$LOG" | tail -n 1 | tr -d '\r'
}

# 접두가 $1인 줄의 수.
count_lines() {
  grep -ac "$1" "$LOG" || true
}

# 마지막 status> text= 줄의 값(hangul/check.sh의 status_text와 같다).
status_text() {
  grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*text=//'
}

# 접두가 $1인 마지막 줄이 패턴(ERE) $2에 맞을 때까지 기다린다. 있으면 0, 30초가 지나면 1.
# 15초가 아니라 30초인 것은 검사 A3이 셸의 sleep 5를 기다리기 때문이다.
wait_for_last() {
  local prefix="$1" pattern="$2" i
  for i in $(seq 1 300); do
    if grep -aqE -- "$pattern" <<<"$(last_line "$prefix")"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 검사 A3의 판정 재료. 접두가 $1인 첫 줄을 찾아, 그 앞의 screen> 두 줄(그 칸을 그린
# 프레임과 바로 앞 프레임)이 글자까지 같은지와, 앞 프레임부터 그 줄까지 사이의 key> 줄
# 수를 낸다. `same=1 keys=0`이면 그 프레임은 칸 말고 바뀐 것이 없고 키도 없었다.
# 그 줄이 없으면 `missing`이다.
redraw_alone() {
  tr -d '\r' < "$LOG" | awk -v want="$1" '
    found { next }
    index($0, want) == 1 { found = 1; next }
    /^terminal: screen>/ { prev = cur; cur = $0; gap = since; since = 0; next }
    /^terminal: key>/ { since++ }
    END {
      if (!found) { print "missing"; exit }
      printf "same=%d keys=%d\n", (prev != "" && prev == cur), gap + since
    }'
}

STATUS_A="EN  신세벌 PCS  쿼티  CAPS"
SCAN_OFF="terminal: battery> scan seen=1 present=0 pick=none"
SCAN_ON="terminal: battery> scan seen=1 present=1 pick=test_battery"
CELL_NONE="terminal: status> battery cell=none ink norm=0 plug=0 low=0"

# ── 부팅 A: test_power가 있고 배터리가 꺼져 있다 ────────────────────────
echo "=== boot A: test_power is built in and its battery is off ==="
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
[ "$READY" = "1" ] || report_failure "boot A: terminal never rendered a prompt"
wait_for_screen 'root@\(none\) ~#' ||
  report_failure "boot A: the shell prompt never showed up"
sleep 1

# ── 검사 A1: 꺼진 배터리는 칸이 아니다 ────────────────────────────────
#
# 키를 하나도 안 친다. 처음 훑기는 test_battery를 보지만(seen=1) present가 0이라 안
# 센다(present=0). 그래서 읽은 배터리가 없고(read 줄 0), 상태 줄 글자는 BS 전과 같고, 띠에
# 배터리 색이 한 픽셀도 없다. 이 셋이 스물한 체인이 BS-M1 뒤에도 그대로인 이유다.
#
# 내장 cmdline의 값이 false가 아니라 0이었다면(design 결정 9) 여기가 seen=1 present=1로
# 빨개진다. BS-M1 plan Task 7의 mutation m1이 그 자리를 본다.
echo "=== A1: the boot scan sees test_battery and does not count it ==="
SCAN="$(last_line 'terminal: battery> scan ')"
[ "$SCAN" = "$SCAN_OFF" ] ||
  report_failure "A1: the boot scan reads \"${SCAN}\", expected \"${SCAN_OFF}\""
[ "$(count_lines 'terminal: battery> read ')" -eq 0 ] ||
  report_failure "A1: terminal read a battery although none counts ($(last_line 'terminal: battery> read '))"
TEXT="$(status_text)"
[ "$TEXT" = "$STATUS_A" ] ||
  report_failure "A1: the status line reads \"${TEXT}\", expected \"${STATUS_A}\""
CELL="$(last_line 'terminal: status> battery ')"
[ "$CELL" = "$CELL_NONE" ] ||
  report_failure "A1: the battery cell reads \"${CELL}\", expected \"${CELL_NONE}\""
echo "${SCAN}; no battery was read; the status line is \"${TEXT}\" with no battery pixels"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor on port ${MONITOR_PORT}"

# ── 검사 A2: 배터리를 켜면 uevent가 다시 훑게 하고 칸이 뜬다 ──────────────
#
# test_power는 배터리를 켜는 uevent를 test_battery가 아니라 test_ac에 보낸다(design 확인
# 4). 이름을 보고 다시 훑는 코드는 여기서 빨개진다. drainUevents가 power_supply를 안 알리는
# 코드도 여기서 빨개진다 — 고른 배터리가 없으면 주기 읽기도 없어서 남는 길이 없다(plan
# Task 7의 mutation m2).
#
# 잔량 50 · Discharging은 test_power의 기본값이다(BS-M0 Task 6이 sysfs에서 읽었다).
echo "=== A2: battery_present=true from the shell ==="
# cd /sys/module/test_power/parameters
type_keys c d spc slash s y s slash m o d u l e slash t e s t shift-minus p o w e r slash \
  p a r a m e t e r s ret
# echo true > battery_present
type_keys e c h o spc t r u e spc shift-dot spc b a t t e r y shift-minus p r e s e n t ret
wait_for_last 'terminal: battery> scan ' "^${SCAN_ON}\$" ||
  report_failure "A2: no rescan picked test_battery after battery_present=true (last scan: $(last_line 'terminal: battery> scan '))"
wait_for_last 'terminal: status> battery ' '^terminal: status> battery cell=" 50%" ink norm=[1-9][0-9]* plug=0 low=0$' ||
  report_failure "A2: the cell never showed \" 50%\" in the normal colour (last: $(last_line 'terminal: status> battery '))"
READ="$(last_line 'terminal: battery> read ')"
[ "$READ" = "terminal: battery> read test_battery capacity=50 status=Discharging class=normal" ] ||
  report_failure "A2: the read line is \"${READ}\", expected capacity=50 status=Discharging class=normal"
TEXT="$(status_text)"
[ "$TEXT" = "$STATUS_A" ] ||
  report_failure "A2: the status text changed to \"${TEXT}\"; the battery cell must stay out of it"
echo "$(last_line 'terminal: status> battery '); the status text is unchanged"

# ── 검사 A3: 키도 PTY 출력도 없이 칸이 바뀐다 ───────────────────────────
#
# bash의 배경 작업이 5초 뒤에 잔량을 쓴다. bash는 배경 작업이 끝난 것을 다음 프롬프트에서야
# 알린다(set -b가 꺼져 있다). 그래서 그 순간 PTY에 아무 글자도 안 나오고, 다시 그리기를 부를
# 수 있는 것은 uevent뿐이다(design 결정 11). 끝나는 순간 글자를 쓰는 셸(fish의 "has ended")이면
# 그 출력도 다시 그리기를 불러서 성공 경로가 둘이 된다
# (docs/decisions/project_gate_chain_composition.md).
#
# 판정은 셋이다. 칸이 빨강 ` 10%`가 됐다. 그 칸을 그린 프레임의 screen>이 바로 앞
# 프레임과 글자까지 같다 — PTY 출력이 끼었다면 다르다. 앞 프레임부터 그 줄까지 key> 줄이
# 없다. 5초는 bash가 `[1] <pid>`와 프롬프트를 다 그릴 여유다 — 그 프레임이 늦어 칸의
# 프레임과 겹치면 둘째 판정이 거짓으로 빨갛다.
echo "=== A3: the capacity drops to 10 while nothing is typed ==="
# /usr/bin/bash --norc
type_keys slash u s r slash b i n slash b a s h spc minus minus n o r c ret
wait_for_screen 'bash-[0-9]' ||
  report_failure "A3: bash never drew a prompt inside the pty"
# ( sleep 5; echo 10 > battery_capacity ) &
type_keys shift-9 spc s l e e p spc 5 semicolon spc e c h o spc 1 0 spc shift-dot spc \
  b a t t e r y shift-minus c a p a c i t y spc shift-0 spc shift-7 ret
wait_for_screen '\[1\] [0-9]+' ||
  report_failure "A3: bash never reported the background job"
wait_for_last 'terminal: status> battery ' '^terminal: status> battery cell=" 10%" ink norm=0 plug=0 low=[1-9][0-9]*$' ||
  report_failure "A3: the cell never turned into a low \" 10%\" (last: $(last_line 'terminal: status> battery '))"
ALONE="$(redraw_alone 'terminal: status> battery cell=" 10%"')"
[ "$ALONE" = "same=1 keys=0" ] ||
  report_failure "A3: the frame that drew \" 10%\" was not a battery-only redraw (${ALONE}, want same=1 keys=0)"
LOW_A3="$(last_line 'terminal: status> battery ' | sed -E 's/.* low=([0-9]+)$/\1/')"
READ="$(last_line 'terminal: battery> read ')"
[ "$READ" = "terminal: battery> read test_battery capacity=10 status=Discharging class=low" ] ||
  report_failure "A3: the read line is \"${READ}\", expected capacity=10 status=Discharging class=low"
echo "$(last_line 'terminal: status> battery '); ${ALONE}"

# ── 검사 A4: 글자가 그대로인 채 갈래만 바뀐다 ───────────────────────────
#
# 잔량이 10 그대로이고 상태만 Charging이 된다. 칸의 글자 ` 10%`는 그대로이고 색이
# 빨강에서 초록으로 바뀐다. dumpStatus의 메모가 글자만 기억하면 화면은 초록인데 새 줄이
# 안 찍힌다 — IS-M1이 CAPS에서 겪은 구멍이다(design 결정 10, plan Task 7의 mutation m3).
# 그리고 픽셀 수가 A3의 빨강과 같아야 한다. 같은 넉 자를 색만 바꿔 칠했다는 증거다.
echo "=== A4: the adapter goes in at the same capacity ==="
# echo charging > battery_status
type_keys e c h o spc c h a r g i n g spc shift-dot spc b a t t e r y shift-minus s t a t u s ret
wait_for_last 'terminal: status> battery ' '^terminal: status> battery cell=" 10%" ink norm=0 plug=[1-9][0-9]* low=0$' ||
  report_failure "A4: no new status> battery line with plug>0 after battery_status=charging (last: $(last_line 'terminal: status> battery '))"
READ="$(last_line 'terminal: battery> read ')"
[ "$READ" = "terminal: battery> read test_battery capacity=10 status=Charging class=plugged" ] ||
  report_failure "A4: the read line is \"${READ}\", expected capacity=10 status=Charging class=plugged"
# 같은 넉 자를 색만 바꿔 칠했으면 픽셀 수가 같다(IS-M1의 on=87 · off=87과 같은 증거).
PLUG_A4="$(last_line 'terminal: status> battery ' | sed -E 's/.* plug=([0-9]+) .*/\1/')"
[ "$PLUG_A4" = "$LOW_A3" ] ||
  report_failure "A4: the plugged cell has ${PLUG_A4} pixel(s) and the low one had ${LOW_A3}; the same four glyphs must only change colour"
echo "$(last_line 'terminal: status> battery '); the same ${PLUG_A4} pixel(s) as the low cell"

# ── 검사 A5: 배터리를 끄면 칸이 사라진다 ────────────────────────────────
#
# A2와 짝이다. 한 번 고른 배터리를 영영 붙들고 있는 코드는 A2를 통과하고 여기서 빨개진다
# (IS-M1 plan 확정 7과 같은 짝).
#
# 마지막에 줄 수를 센다. 훑기 줄은 결과가 바뀔 때만 찍히므로 셋이다(A1 · A2 · A5) — A3 · A4의
# uevent도 다시 훑지만 결과가 그대로다. 읽기 줄도 셋이다(A2 · A3 · A4).
echo "=== A5: battery_present=false takes the cell away ==="
# echo false > battery_present
type_keys e c h o spc f a l s e spc shift-dot spc b a t t e r y shift-minus p r e s e n t ret
wait_for_last 'terminal: battery> scan ' "^${SCAN_OFF}\$" ||
  report_failure "A5: no rescan dropped test_battery after battery_present=false (last scan: $(last_line 'terminal: battery> scan '))"
wait_for_last 'terminal: status> battery ' "^${CELL_NONE}\$" ||
  report_failure "A5: the cell did not go away (last: $(last_line 'terminal: status> battery '))"
TEXT="$(status_text)"
[ "$TEXT" = "$STATUS_A" ] ||
  report_failure "A5: the status text is \"${TEXT}\", expected \"${STATUS_A}\""
SCANS="$(count_lines 'terminal: battery> scan ')"
READS="$(count_lines 'terminal: battery> read ')"
[ "$SCANS" -eq 3 ] && [ "$READS" -eq 3 ] ||
  report_failure "A5: boot A printed ${SCANS} scan line(s) and ${READS} read line(s), expected 3 and 3"
echo "the cell is gone; boot A printed ${SCANS} scan and ${READS} read lines"

# NUL만 세어 한 번에 읽는다(pointer/check.sh와 같은 이유, AL-M1).
if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "the boot A serial log contains NUL bytes"
fi

exec 3>&- 2>/dev/null
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

# ── 부팅 B: 부팅 cmdline이 배터리를 켜 둔다 ─────────────────────────────
#
# -append의 파라미터가 내장 cmdline의 false를 덮는다 — 커널이 내장 문자열 뒤에 부트로더의
# 것을 붙이고 같은 파라미터는 뒤의 것이 이긴다(design 확인 9). 키를 안 친다.
LOG_A="$LOG"
LOG="$(mktemp)"
echo "=== boot B: the battery is on, full and plugged from the kernel command line ==="
qemu-system-x86_64 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0 test_power.battery_present=true test_power.battery_status=full test_power.battery_capacity=100" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: status> battery " "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "boot B: terminal never printed a status> battery line"

# ── 검사 B1: 첫 프레임에 이미 칸이 있다 ────────────────────────────────
#
# 첫 status> battery 줄은 첫 프레임의 것이다. 그 줄이 이미 초록 `100%`이면 처음 훑기가
# 첫 프레임 전에 돌았다. 처음 훑기를 첫 프레임 뒤로 미룬 코드는 첫 줄이 cell=none이다.
echo "=== B1: the first frame already has the cell ==="
FIRST="$(grep -a -m 1 'terminal: status> battery ' "$LOG" | tr -d '\r')"
grep -aqE '^terminal: status> battery cell="100%" ink norm=0 plug=[1-9][0-9]* low=0$' <<<"$FIRST" ||
  report_failure "B1: the first battery line is \"${FIRST}\", expected a plugged \"100%\""
FIRST_SCAN="$(grep -a -m 1 'terminal: battery> scan ' "$LOG" | tr -d '\r')"
[ "$FIRST_SCAN" = "$SCAN_ON" ] ||
  report_failure "B1: the first scan line is \"${FIRST_SCAN}\", expected \"${SCAN_ON}\""
FIRST_READ="$(grep -a -m 1 'terminal: battery> read ' "$LOG" | tr -d '\r')"
[ "$FIRST_READ" = "terminal: battery> read test_battery capacity=100 status=Full class=plugged" ] ||
  report_failure "B1: the first read line is \"${FIRST_READ}\", expected capacity=100 status=Full class=plugged"
echo "${FIRST}"

if [ "$(tr -cd '\0' < "$LOG" | wc -c)" -ne 0 ]; then
  report_failure "the boot B serial log contains NUL bytes"
fi

echo "boot A battery lines:"
grep -aE 'terminal: (battery> |status> battery )' "$LOG_A" | tr -d '\r'
echo "BS-M1 check PASS"
