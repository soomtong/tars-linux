#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# vendor 준비 + terminal 빌드는 prepare.sh가 맡는다(boot/check.sh와 공유).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! ./prepare.sh; then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사. 부팅보다 먼저 돌린다 — keymap이나 Ctrl
# 마스크의 오타는 QEMU를 띄우지 않고도 잡히고, 여기서 걸리면 아래 4초
# 부팅을 아낀다. IP-M0 전에는 이 바이너리가 빌드만 되고 아무도 실행하지
# 않았다(design doc 결정 10).
if ! zig build test; then
  echo "FAIL: input_test failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45455
LOG="$(mktemp)"
source ../gate_lib.sh
QEMU_PID=""

# --- (변경 2) 스크린샷을 out/tf/ 아래 고정 이름으로 ---------------------
# 예전에는 /workspace 아래 mktemp로 만들고 지우지 않아서 저장소 루트에
# 3MB짜리 파일이 계속 쌓였다. out/은 .gitignore 대상이고 루트 check.sh의
# clean()이 매 회차 지운다. QEMU monitor의 screendump는 QEMU 프로세스의
# 작업 디렉터리를 기준으로 삼으므로 절대 경로로 넘긴다.
SCREENS_DIR="${REPO_ROOT}/out/tf"
mkdir -p "$SCREENS_DIR"
BEFORE="${SCREENS_DIR}/before.ppm"
AFTER="${SCREENS_DIR}/after.ppm"
rm -f "$BEFORE" "$AFTER"

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

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

MONITOR_READY=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then
    MONITOR_READY=1
    break
  fi
  sleep 0.5
done

if [ "$MONITOR_READY" != "1" ]; then
  echo "FAIL: could not connect to QEMU monitor on port ${MONITOR_PORT}"
  cat "$LOG"
  exit 1
fi

# --- (변경 3) 고정 sleep 30 대신 로그 폴링 ------------------------------
# main.zig:56의 dumpScreen()은 PTY 출력을 렌더링할 때마다
# "terminal: screen> ..." 한 줄을 serial에 찍는다. 그 줄이 처음 나타났다는
# 것은 (a) DRM 열기, (b) 폰트 래스터라이즈, (c) evdev 열기, (d) fish spawn,
# (e) 첫 프롬프트 렌더링까지 전부 끝났다는 뜻이다 — 키를 넣어도 되는 시점의
# 정확한 신호다. 고정 대기는 빠른 머신에서 낭비이고 느린 머신에서 깨진다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then
    READY=1
    break
  fi
  sleep 1
done

if [ "$READY" != "1" ]; then
  echo "FAIL: terminal did not render a prompt within 120s"
  echo "--- startup markers ---"
  for marker in \
    "terminal: grid " \
    "terminal: rasterized " \
    "terminal: opened /dev/input/event" \
    "terminal: spawned child pid "; do
    if grep -q "$marker" "$LOG"; then
      echo "  ok      ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  tail -n 60 "$LOG"
  exit 1
fi

# 첫 렌더링 직후 present가 끝나도록 한 박자 준다.
sleep 1

# 1) 키를 넣기 전 화면
echo "screendump ${BEFORE}" >&3
sleep 1

# 2) "math 6 x 7" + Enter 를 한 글자씩 주입.
#    fish 내장 math가 42를 출력하므로, 화면에 42가 나타나면 셸이 실제로
#    명령을 "실행"한 것이다 — 단순 에코와 구분된다.
type_keys m a t h spc 6 spc x spc 7 ret

# --- (변경 4) 결과도 고정 sleep 3 대신 폴링 -----------------------------
# 42가 로그에 찍힌 뒤에 after 스크린샷을 뜨면, 픽셀 차이 검사와 로그 검사가
# 같은 화면 상태를 본다.
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*42" "$LOG"; then
    break
  fi
  sleep 1
done
sleep 1

# 3) 키를 넣은 뒤 화면
echo "screendump ${AFTER}" >&3
sleep 1

# --- TQ-M1: 터미널이 자식의 질의에 답하는가 ---------------------------
#
# fzf는 `--height`일 때 커서가 지금 몇 행에 있는지 터미널에 묻고(`ESC[6n`)
# 그 답으로 자기 상자 높이를 정한다. ST-M3 전까지 우리 terminal은 vt의 질의
# 콜백(`effects.write_pty`)을 하나도 등록하지 않아 답이 없었고, 그래서 첫
# Ctrl+R이 멈췄다(두 번째 키가 그 잠금을 풀어 "두 번 눌러야 열린다"로 보였다).
#
# 질의 바이트를 게이트가 타이핑으로 만들지 않는다 — `printf '\033[6n'`을
# type_keys로 치면 이스케이프가 fish → bash → printf 층에서 죽어 리터럴
# `033[6n`이 나갔다(화면에 그대로 찍혀 확인했다). 그래서 ESC가 든 스크립트를
# initrd에 실어 이름으로 친다(`kernel/tq-probe.sh`가 /usr/bin/tq-probe다).
#
# 그 스크립트 안에서 묻기와 읽기가 한 프로세스인 것도 같은 뿌리다. 답은 pty의
# 입력이라, 사이에 프롬프트로 돌아온 셸의 라인 편집기가 먼저 가져가면
# 0바이트가 된다 — fish가 묻고 bash가 읽게 했더니 실제로 그랬다.
#
# 판정은 길이다. 답이 오면 `len6`(CPR은 `ESC[행;열R` 6바이트), 안 오면
# `len0`이다. 정확한 문자열을 안 박는 것은 포맷이 vendored ghostty의
# 몫이기 때문이다(design 결정 5) — 박으면 우리가 아니라 그 코드를 검사한다.
#
# 행 경계(`\| `)를 안 박는 이유가 있다. tty의 line discipline이 pty로 들어온
# 답을 되울리고(ECHOCTL이 ESC를 `^[`로 바꾼다) 우리 terminal이 그걸 글자로
# 그리기 때문에, 화면의 그 행은 `^[[4;1Rlen6`처럼 나온다 — 길이 글자가 행
# 첫머리에 안 온다(TQ-M1 실측). 판정 글자가 `len<숫자>`인 것 자체가 안전한
# 이유는 우리가 치는 것에 그 글자가 없기 때문이다(autosuggestion 함정과 같은
# 자리 — project_gate_screen_echo).
#
# 이 자리(재시작 경로 앞)에 두는 데도 뜻이 있다. 다음 검사가 `exit`를 쳐서
# 셸을 죽이는데, 프로브가 남긴 그 행의 글자가 그 뒤 화면에 섞이면 재시작
# 판정이 흔들린다.
type_keys t q minus p r o b e ret
if ! wait_for_screen 'len[1-9]'; then
  echo "FAIL: the terminal did not answer the cursor-position query"
  echo "  /usr/bin/tq-probe가 ESC[6n을 보내고 read로 답을 읽는다 — len0이면"
  echo "  답이 안 온 것이고, 그러면 fzf의 --height 상자가 다시 멈춘다."
  grep -a "terminal: screen>" "$LOG" | tail -1
  exit 1
fi
echo "terminal answered the cursor-position query"

# --- 재시작 경로 검증 (IS) ---------------------------------------------
# 화면 셸에 exit를 쳐서 죽인다. 그러면 이 순서가 일어나야 한다:
#   fish 종료 → terminal이 PTY EOF로 종료 → PID 1이 수거 → PID 1이 재시작
#   → 새 terminal이 DRM을 다시 열고 새 프롬프트를 그린다
# 이 milestone 전에는 terminal이 무한 sleep으로 버텨서 아무 일도 안 났다.
SPAWNS_BEFORE=$(grep -c "terminal: spawned child pid" "$LOG")

type_keys e x i t ret

RESTARTED=0
for _ in $(seq 1 60); do
  if [ "$(grep -c "terminal: spawned child pid" "$LOG")" -gt "$SPAWNS_BEFORE" ]; then
    RESTARTED=1
    break
  fi
  sleep 1
done

if [ "$RESTARTED" != "1" ]; then
  echo "FAIL: init did not restart the terminal within 60s after the shell exited"
  echo "--- restart markers ---"
  for marker in \
    "terminal: child exited (pty EOF)" \
    "tars-init: terminal exited" \
    "tars-init: restarting terminal" \
    "tars-init: started terminal"; do
    if grep -q "$marker" "$LOG"; then
      echo "  ok      ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  tail -n 60 "$LOG"
  exit 1
fi
echo "init restarted the terminal after the shell exited"

# 좀비 수거 검증: 죽은 fish는 terminal이 거두지 않으므로 PID 1로
# 재부모화되고, PID 1이 거둔다. 이 줄이 없으면 좀비가 쌓인다는 뜻이다.
if ! grep -q "tars-init: reaped orphan pid" "$LOG"; then
  echo "FAIL: init never reaped a re-parented orphan"
  tail -n 60 "$LOG"
  exit 1
fi
echo "init reaped the re-parented shell"

# 이 milestone의 존재 이유를 직접 지키는 검사.
if grep -q "Attempted to kill init" "$LOG"; then
  echo "FAIL: kernel panicked because PID 1 exited"
  tail -n 60 "$LOG"
  exit 1
fi

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$BEFORE" ] || [ ! -s "$AFTER" ]; then
  echo "FAIL: screendump did not produce both files (kept in ${SCREENS_DIR})"
  tail -n 60 "$LOG"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IDENTIFY=(magick identify)
  COMPARE=(magick compare)
else
  IDENTIFY=(identify)
  COMPARE=(compare)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$AFTER" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${AFTER}: ${DIMENSIONS}"
  exit 1
}
echo "Captured screendumps: ${BEFORE} / ${AFTER} (${DIMENSIONS})"

# 렌더링 경로 검증: 키 주입 전후로 화면이 실제로 달라졌는가.
DIFF_PIXELS=$("${COMPARE[@]}" -metric AE "$BEFORE" "$AFTER" null: 2>&1) || true
DIFF_PIXELS="${DIFF_PIXELS%%[!0-9]*}"
echo "Pixels changed after typing: ${DIFF_PIXELS:-0}"

if [ -z "$DIFF_PIXELS" ] || [ "$DIFF_PIXELS" -lt 100 ]; then
  echo "FAIL: screen did not change after key injection (${DIFF_PIXELS:-0} pixels)"
  echo "      screenshots kept in ${SCREENS_DIR}"
  tail -n 60 "$LOG"
  exit 1
fi

# 파싱 경로 검증: 셸이 명령을 실행해 42를 내놓았는가.
if ! grep -q "terminal: screen>.*42" "$LOG"; then
  echo "FAIL: expected '42' in the parsed screen dump (shell did not run the command)"
  echo "      screenshots kept in ${SCREENS_DIR}"
  tail -n 60 "$LOG"
  exit 1
fi
echo "Found '42' in parsed screen dump"

# init 경로 검증: PID 1이 파일시스템 넷을 전부 붙였는가.
#
# 이 검사가 없으면 init이 /proc 하나 못 붙여도 부팅만 되면 PASS가 난다 —
# 위 검사들은 전부 terminal 프로세스의 출력만 보기 때문이다. ZM-M1에서
# init을 Rust에서 Zig로 다시 쓰면서 이 사각지대가 실제 위험이 됐다.
echo "--- init log ---"
grep 'tars-init:' "$LOG" || true

for marker in \
  "tars-init: mounted proc at /proc" \
  "tars-init: mounted sysfs at /sys" \
  "tars-init: mounted devtmpfs at /dev" \
  "tars-init: mounted devpts at /dev/pts"; do
  if ! grep -q "$marker" "$LOG"; then
    echo "FAIL: init did not report '${marker}'"
    tail -n 60 "$LOG"
    exit 1
  fi
done
echo "init mounted all four filesystems"

# HD-M0: 키보드를 번호가 아니라 성질로 찾았는가.
#
# HD-M0에서 이 검사가 볼 수 있었던 것은 "탐색이 실제로 돌았다"까지였다. 그때는
# event0이 곧 키보드라 틀린 탐색기도 똑같이 통과했기 때문이다. 탐색이 옳다는
# 증명은 HD-M1이 ACPI를 켜면서 했다 — 전원 버튼이 event0을 차지해 키보드가
# event1로 밀렸는데도 아래 화면 검사들이 통과한다. 아래 HD-M1 검사가 그
# 전제가 사라지지 않게 붙박는다.
#
# 장치 이름은 요구하지 않는다. 실 하드웨어에서 달라지는 것이 정상이고,
# 판정에도 쓰지 않는 값이다(design 결정 2).
if ! grep -q "tars-init: keyboard device /dev/input/event" "$LOG"; then
  echo "FAIL: init did not discover a keyboard device"
  grep 'tars-init:' "$LOG" | tail -n 20
  exit 1
fi
if grep -q "tars-init: no keyboard found" "$LOG"; then
  echo "FAIL: init fell back to event0 instead of discovering a keyboard"
  grep 'tars-init:' "$LOG" | tail -n 20
  exit 1
fi
echo "init discovered the keyboard by capability"

# HD-M1: ACPI가 입력 장치를 하나 더 등록했는가.
#
# 이 검사가 없으면 바로 위의 탐색 검사는 "성질로 찾았다"와 "장치가 하나뿐이라
# 우연히 맞았다"를 구별하지 못한다. 전원 버튼이 evdev 장치 목록에 끼어든
# 상태에서 위쪽 화면 검사들이 통과하는 것이 HD-M0의 탐색기가 옳다는 증명이고,
# 이 줄은 그 전제가 사라지지 않았음을 확인한다. 커널에서 ACPI를 다시 끄면
# 여기가 먼저 실패하므로, 증명이 조용히 사라지지 않는다.
#
# 장치 번호를 요구하지 않는 이유는 탐색기를 만든 이유와 같다 — 번호는
# 하드웨어 사정에 따라 달라지는 값이다.
if ! grep -q "ACPI: button: Power Button" "$LOG"; then
  echo "FAIL: the kernel did not register an ACPI power button"
  grep -i "acpi" "$LOG" | tail -n 20
  exit 1
fi
echo "the keyboard was found even though ACPI added another input device"

# 성공했으면 스크린샷은 필요 없다. 실패했을 때만 남겨서 눈으로 볼 수 있게 한다.
rm -f "$BEFORE" "$AFTER"

echo "PASS"
exit 0
