#!/usr/bin/env bash
# 소개 페이지(gh-pages 브랜치)의 영상을 찍는다.
#
#   site/capture.sh boot hangul panes copy vim    # 장면 이름을 고른다
#   site/capture.sh                               # 전부
#
# 판정이 아니다 — 호스트 QEMU로 이미 빌드한 bzImage · initrd.cpio를 띄우고,
# monitor의 sendkey로 치면서 screendump를 0.1초마다 뜬다. 장면마다 새로
# 부팅해서 앞 장면의 화면이 섞이지 않는다. 산출물은 out/site/<장면>.mp4와
# 마지막 프레임 <장면>.webp다. 페이지에 올리는 것은 그 둘을 gh-pages의
# media/로 옮기는 일이다.
#
# 필요한 것: qemu-system-x86_64, ffmpeg, cwebp, magick(전부 brew).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/out/site"
PORT=45600
FPS=10
# 게스트 화면. 셀 크기는 그대로라 화면이 작을수록 웹에서 글자가 크다.
XRES=1024
YRES=640
mkdir -p "$OUT"

# 장면 도중에 빠져도 QEMU와 녹화 루프를 남기지 않는다. 남으면 다음 회차의
# rm -rf가 아직 쓰이는 프레임 디렉터리를 만난다.
QEMU_PID=""; REC_PID=""
cleanup() {
  [ -n "$REC_PID" ] && kill "$REC_PID" 2>/dev/null
  [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT

# ── QEMU 하나 띄우고 끄기 ──────────────────────────────────────────────

boot_guest() {
  local scene="$1"
  WORK="${OUT}/${scene}.d"
  rm -rf "$WORK"; mkdir -p "$WORK/f"
  LOG="${WORK}/serial.log"; : > "$LOG"
  qemu-system-x86_64 \
    -nic none -m 2G \
    -kernel "${ROOT}/kernel/build/arch/x86/boot/bzImage" \
    -initrd "${ROOT}/kernel/initrd.cpio" \
    -append "console=ttyS0" \
    -vga none -device virtio-gpu-pci,xres=${XRES},yres=${YRES} \
    -display none \
    -serial file:"$LOG" \
    -monitor tcp:127.0.0.1:${PORT},server,nowait \
    -monitor tcp:127.0.0.1:$((PORT + 1)),server,nowait \
    -no-reboot &
  QEMU_PID=$!
  local i
  for i in $(seq 1 40); do
    { exec 3<>"/dev/tcp/127.0.0.1/${PORT}"; } 2>/dev/null && return 0
    sleep 0.05
  done
  echo "could not reach the QEMU monitor" >&2; exit 1
}

# 0.1초마다 한 장. monitor 하나는 손님을 하나만 받아서 녹화는 둘째 monitor(PORT+1)로 간다.
start_recording() {
  (
    exec 4<>"/dev/tcp/127.0.0.1/$((PORT + 1))"
    local n=0
    while kill -0 "$QEMU_PID" 2>/dev/null && [ ! -e "${WORK}/stop" ]; do
      printf -v name '%s/f/%05d.ppm' "$WORK" "$n"
      echo "screendump ${name}" >&4
      n=$((n + 1))
      sleep "0.$((10 / FPS))"
    done
  ) &
  REC_PID=$!
}

stop_recording() {
  touch "${WORK}/stop"
  wait "$REC_PID" 2>/dev/null || true
  echo quit >&3 || true
  wait "$QEMU_PID" 2>/dev/null || true
  exec 3>&-
}

wait_for_prompt() {
  local i
  for i in $(seq 1 200); do
    grep -aq "terminal: screen>" "$LOG" && return 0
    sleep 0.1
  done
  echo "terminal never drew a prompt" >&2; exit 1
}

# ── 키 ──────────────────────────────────────────────────────────────

pause() { sleep "$1"; }

# 화면 줄(terminal의 screen> 로그)에 패턴이 나올 때까지. 15초.
# TCG라 한 프레임이 2초를 넘기도 한다 — 고정 pause로는 녹화가 먼저 끝난다.
wait_screen() {
  local i
  for i in $(seq 1 150); do
    grep -a "terminal: screen>" "$LOG" | tail -1 | grep -aqE "$1" && return 0
    sleep 0.1
  done
  echo "screen never showed '$1'" >&2; exit 1
}

key() {
  local k
  for k in "$@"; do echo "sendkey $k" >&3; sleep 0.09; done
}

# 영문과 기호. 한글은 hangul_keys로 자판(신세벌 PCS)의 키를 직접 준다.
typ() {
  local s="$1" ch i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
      [a-z0-9]) key "$ch" ;;
      [A-Z]) key "shift-$(tr 'A-Z' 'a-z' <<<"$ch")" ;;
      ' ') key spc ;;
      "'") key apostrophe ;;
      '"') key shift-apostrophe ;;
      '\') key backslash ;;
      '_') key shift-minus ;;
      '=') key equal ;;
      ',') key comma ;;
      ';') key semicolon ;;
      '/') key slash ;;
      '-') key minus ;;
      '.') key dot ;;
      ':') key shift-semicolon ;;
      '|') key shift-backslash ;;
      '~') key shift-grave_accent ;;
      '*') key shift-8 ;;
      '>') key shift-dot ;;
      '!') key shift-1 ;;
      '#') key shift-3 ;;
      *) echo "no key for '$ch'" >&2; exit 1 ;;
    esac
  done
}

line() { typ "$1"; key ret; }

# 신세벌 PCS의 키. 한 글자가 영문 소문자나 쉼표 · 마침표 하나다.
hangul_keys() {
  local s="$1" i
  for ((i = 0; i < ${#s}; i++)); do
    case "${s:i:1}" in
      ' ') key spc ;;
      ',') key comma ;;
      '.') key dot ;;
      *) key "${s:i:1}" ;;
    esac
  done
}

# ── 장면 ────────────────────────────────────────────────────────────

# 전원을 넣은 순간부터 프롬프트까지. 녹화가 부팅과 함께 시작한다.
scene_boot() {
  start_recording
  wait_for_prompt
  pause 1.5
  line "uname -sr"
  pause 1.2
  line "cat /proc/1/comm"
  pause 2
}

scene_hangul() {
  wait_for_prompt; pause 1
  start_recording
  pause 1
  typ "echo "
  key shift-spc; pause 0.6
  hangul_keys "jfshtamfncjx "     # 안녕하세요
  pause 0.3
  hangul_keys ",fygng"            # 타르스
  pause 0.6
  key shift-spc; pause 0.6
  typ " TARS"
  key ret; pause 1.5
  typ "echo "
  key shift-spc; pause 0.4
  hangul_keys "mfskgw jdeytc"     # 한글 입력
  key shift-spc; pause 0.4
  key ret
  pause 2
}

scene_panes() {
  wait_for_prompt; pause 1
  start_recording
  pause 0.8
  line "eza -l --group-directories-first /"
  wait_screen "vendor"; pause 1
  key meta_l-d; pause 1.5
  line "htop"
  pause 4
  key meta_l-shift-d; pause 1.5
  line "tree -L 1 /etc | head -20"
  wait_screen "directories"; pause 1.5
  key meta_l-bracket_left; pause 1
  key meta_l-bracket_left; pause 1
  line "uname -sr"
  wait_screen "Linux "; pause 3
}

# 스크롤백 위 검색과 선택. 커널 로그 끝 마흔 줄에 Freeing이 넷 있다.
scene_copy() {
  wait_for_prompt; pause 1
  start_recording
  pause 0.8
  line "dmesg | tail -40"
  wait_screen "TERM=linux"; pause 1.2
  key meta_l-shift-c; pause 1
  key slash; pause 0.3
  typ "Freeing"; key ret; pause 1.2
  key n; pause 0.8
  key n; pause 0.8
  key shift-n; pause 0.8
  key shift-v; pause 0.6
  key y; pause 1
  typ "echo '"; key meta_l-v; typ "'"; key ret
  wait_screen "Freeing.*Freeing.*Freeing.*Freeing.*Freeing"; pause 3
}

# 커서 셋: insert는 bar, normal은 block, replace는 underline.
scene_vim() {
  wait_for_prompt; pause 1
  start_recording
  pause 0.8
  line "vim /tmp/hello.md"
  pause 2
  key i; pause 0.6
  typ "# TARS"; key ret; key ret
  key shift-spc; pause 0.3
  hangul_keys "jfshtamfncjx"      # 안녕하세요
  key esc; pause 0.8            # 조합을 끝내고 영문으로 — esc_latin
  key o; pause 0.3
  typ "Esc brings me back to Latin."
  key esc; pause 0.8
  key 0; pause 0.4
  key shift-r; pause 0.8
  typ "ESC"; key esc; pause 0.8
  typ ":wq"; key ret; pause 1
  line "bat --style=plain /tmp/hello.md"
  wait_screen "ESC brings"; pause 3
}

# ── 인코딩 ──────────────────────────────────────────────────────────

encode() {
  local scene="$1" frames="${WORK}/f" last
  # 마지막 한 장이 쓰는 중일 수 있어 크기가 덜 찬 것은 버린다.
  find "$frames" -name '*.ppm' -size -$((XRES * YRES * 3 / 1024))k -delete
  last="$(ls "$frames" | tail -1)"
  ffmpeg -loglevel error -y -framerate "$FPS" -pattern_type glob -i "${frames}/*.ppm" \
    -vf "fps=30,scale=${XRES}:-2:flags=lanczos,format=yuv420p" \
    -c:v libx264 -preset slow -crf 24 -tune animation -movflags +faststart \
    "${OUT}/${scene}.mp4"
  magick "${frames}/${last}" "${WORK}/last.png"
  cwebp -quiet -q 85 "${WORK}/last.png" -o "${OUT}/${scene}.webp"
  printf '%s: %s frames, %s\n' "$scene" "$(ls "$frames" | wc -l | tr -d ' ')" \
    "$(du -h "${OUT}/${scene}.mp4" | cut -f1)"
}

SCENES=("$@")
[ ${#SCENES[@]} -gt 0 ] || SCENES=(boot hangul panes copy vim)
for s in "${SCENES[@]}"; do
  boot_guest "$s"
  "scene_${s}"
  stop_recording
  encode "$s"
done
