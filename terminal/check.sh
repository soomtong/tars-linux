#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# vendor 준비 + terminal 빌드는 prepare.sh가 맡는다(boot/check.sh와 공유).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && cargo build --release); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! ./prepare.sh; then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45455
LOG="$(mktemp)"
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
    "terminal: opened /dev/input/event0" \
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
for k in m a t h spc 6 spc x spc 7 ret; do
  echo "sendkey $k" >&3
  sleep 0.3
done

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

# 성공했으면 스크린샷은 필요 없다. 실패했을 때만 남겨서 눈으로 볼 수 있게 한다.
rm -f "$BEFORE" "$AFTER"

echo "PASS"
exit 0
