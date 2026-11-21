#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# CR 체인 — Debian trixie의 Chromium(묶음 browser)이 TARS의 Wayland 서버에 뜬다(CR design, CR-M1 plan 확정 8). 서른일곱째 체인.
#
# 이 게이트가 증명하는 사슬(CR-M1 plan 확정 8의 판정 1~6 — 도는 순서는 1 · 6 · 2 · 3 · 4 · 5):
#   init이 홈 디스크의 묶음 넷(base · gpu · media · browser)을 /usr에 얹고 browser의 etc/를 /etc로 옮긴다(1)
#   → 화면 셸(사용자 cruser — 설정 디스크의 user=)에서 WAYLAND_DISPLAY 없이 부른 tars-browser는 이유 한 줄과 1로 끝난다(6)
#   → tars-browser file://…이 Chromium을 --ozone-platform=wayland --disable-gpu로 띄워, 서버에 app_id chromium-browser의 toplevel ·
#     맨 위 띠의 이름 · 호환 모드 키(tars_menu_v1을 bind하지 않는다) · 그림자 여백을 둔 636 × 772 버퍼가 온다 — 60초 안(2)
#   → 페이지 제목이 창 제목이 되고, screendump의 페이지 좌표 색이 체인이 쓴 HTML과 같으며, 한글 · 한자 상자의 잉크가 noto-cjk의
#     글자다(두부가 아니다 — 아래 "한글 상자")(3)
#   → 렌더러가 seccomp 필터 안(`Seccomp: 2`)에서, 브라우저와 다른 user namespace(uid_map `1000 1000 1`)로 돈다 — 화면 셸(같은 uid)이 /proc로
#     읽는다(4 — CR design 결정 5 · 요구사항 결정 8: sandbox를 끄지 않는다)
#   → Cmd+Q가 close를 보내 Chromium이 스스로 끝나고(kill 없음) chromium 프로세스가 하나도 남지 않는다(5)
#
# 부팅 하나, NIC 없음(R-CR-5의 망은 CR-M2). 설정 디스크 `shell=fish keyboard=apple user=cruser` + 라벨 tars-home의 홈 디스크(display 체인
# 부팅 3의 모양). 키보드 apple이라 Cmd는 meta_l이다. 게스트 메모리는 CR_MEM(기본 2048 — CR design 결정 9). 루트 check.sh는 기본값이
# 2048 이상인 체인들을 한 lane에 묶는다(그 lane끼리 큰 게스트 둘이 겹치지 않게). monitor 포트는 45510 — 예약 범위(RP-M0)에서 45509(toolkit)
# 다음이다.
#
# 화면 1280 × 800. Chromium은 셸 오른쪽 column(x 644..1259 · y 20..771, 616 × 752)에 버퍼 636 × 772를 window geometry (10, 10)으로 그리고
# 탭 줄 · 주소창이 위 87픽셀이라 페이지의 원점은 화면 (644, 107)이다. --no-first-run이 이 원점을 지킨다 — 빼면 새 프로필의 첫 실행에
# Debian의 master_preferences가 먹어 북마크 줄과 "Continue where you left off" 안내 줄이 생겨 원점이 (644, 197)로 내려간다(단계 B 실측 6).
#
# 한글 상자. 잉크의 수로는 글자와 두부를 못 가른다 — noto-cjk를 뺀 묶음에서 같은 상자(690, 415, 170 × 75)의 잉크는 2,649, 글자는 2,619였다.
# 가르는 것은 잉크의 색 가짓수다 — 글자는 곡선의 안티에일리어스로 177가지, 두부(곧은 사각형)는 23가지(단계 B 실측 4). 하한 60으로 본다.
#
# 묶음은 make dev-layers가 구운 것이다(make check CHAIN=browser와 make gate가 먼저 부른다). browser는 base와 같은 파일이 지워진 채 구워지므로
# base가 함께 있어야 한다. init은 /home/.tars/layers의 version이 이미지와 같을 때만 얹는다 — 부팅이 하나라 이미지의 버전은 initrd의 init
# 실행 파일에서 읽고(VERSION + 꼬리표), 부팅 첫 줄과 같은지 본다. 홈 디스크(약 840 MiB)는 display 체인처럼 out/에 남는다(루트 게이트의
# clean이 지운다).

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

MONITOR_PORT=45510
CR_MEM="${CR_MEM:-2048}"
REPO_ROOT="$(cd .. && pwd)"
XRES=1280
YRES=800
USER_NAME=cruser
# 첫 화면 상한(CR design 결정 9). 부하 없는 TCG 한 CPU에서 콜드 22초였다.
FIRST_SECONDS=60

# 체인이 쓰는 페이지의 색(테마 · 다른 체인의 색과 겹치지 않는다). 소문자 hex는 ppm_ink의 출력 모양이다.
PAGE_BG=2e8b57
PAGE_BOX=c0392b
PAGE_TEXT_BG=f5f5dc
PAGE_TITLE=tars-cr
# 페이지 원점(644, 107) 기준: 색 상자 (40, 40) 300 × 200, 글자 상자 (40, 300) — 판정은 가장자리를 비켜 안쪽만 본다.
BOX_PROBE="734 197 200 100"
BG_PROBE="1000 400 200 200"
GLYPH_PROBE="690 415 170 75"
GLYPH_COLOURS_MIN=60

SCREENS_DIR="${REPO_ROOT}/out/cr"
mkdir -p "$SCREENS_DIR"
SHOT="${SCREENS_DIR}/shot.ppm"
# 사람이 볼 PNG는 이 회차의 로그 폴더에 남는다(make check · 루트 게이트가 TMPDIR을 그 폴더로 준다).
JUDGE_DIR="${TMPDIR:-/tmp}"

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
  echo "--- wl> · menu> · init lines ---"
  tlog | grep -aE 'terminal: (wl|menu)> |tars-init: (overlay|layer|layers|user)' | tr -d '\r' | tail -n 40
  echo "--- last screen lines ---"
  joined_screen_dump | tail -n 3
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

# 로그 어디든 패턴(ERE)이 나타날 때까지 기다린다. 상한은 초(기본 15).
wait_for_log() {
  local pattern="$1" secs="${2:-15}" i
  for i in $(seq 1 $((secs * 10))); do
    if tlog | grep -aE -- "$pattern" >/dev/null; then return 0; fi
    sleep 0.1
  done
  return 1
}

count_log() {
  tlog | grep -acE -- "$1"
}

# 셈이 N 이상이 될 때까지 기다린다. 15초.
wait_for_count() {
  local pattern="$1" want="$2" i n
  for i in $(seq 1 150); do
    n="$(count_log "$pattern")"
    if [ "$n" -ge "$want" ]; then return 0; fi
    sleep 0.1
  done
  return 1
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
      ';') keys+=(semicolon) ;;
      ':') keys+=(shift-semicolon) ;;
      '(') keys+=(shift-9) ;;
      ')') keys+=(shift-0) ;;
      '$') keys+=(shift-4) ;;
      '^') keys+=(shift-6) ;;
      '&') keys+=(shift-7) ;;
      '|') keys+=(shift-backslash) ;;
      \\) keys+=(backslash) ;;
      "'") keys+=(apostrophe) ;;
      '>') keys+=(shift-dot) ;;
      *) report_failure "type_line does not know the character '${ch}'" ;;
    esac
  done
  keys+=(ret)
  type_keys "${keys[@]}"
}

# 상자 안 잉크(바탕과 다른 픽셀)의 수와 그 색의 가짓수 — `ink=N colours=M`.
ink_colours() {
  perl -e '
    my ($f, $x0, $y0, $w, $h, $bg) = @ARGV;
    open(my $fh, "<:raw", $f) or die "$f: $!\n";
    local $/; my $d = <$fh>;
    $d =~ s/\AP6\s+(\d+)\s+\d+\s+\d+\s//s or die "$f: not a P6 ppm\n";
    my $row = $1 * 3; my ($ink, %c) = (0);
    for my $y ($y0 .. $y0 + $h - 1) {
      for my $x ($x0 .. $x0 + $w - 1) { my $p = unpack("H6", substr($d, $y * $row + $x * 3, 3)); next if $p eq $bg; $ink++; $c{$p}++; }
    }
    printf "ink=%d colours=%d\n", $ink, scalar(keys %c);' "$@"
}

# ── 묶음 · 이미지 버전 · 디스크 ──────────────────────────────────────────
for b in base gpu media browser; do
  [ -f "../devlayer/build/${b}.sqfs" ] || report_failure "no devlayer/build/${b}.sqfs — run make dev-layers"
done
# init 실행 파일 안의 버전 글자(VERSION + `+sha` · `-dirty` — init/build.zig의 buildVersion). 가장 긴 것을 고른다.
BASE_VER="$(tr -d ' \t\r\n' < ../VERSION)"
IMAGE_VER="$(gzip -dc ../kernel/initrd.cpio 2>/dev/null | cpio -i --quiet --to-stdout init 2>/dev/null |
  grep -aoE "${BASE_VER//./\\.}(\\+[0-9a-f]+(-dirty)?)?" | awk '{ print length, $0 }' | sort -rn | head -n 1 | cut -d' ' -f2)"
[ -n "$IMAGE_VER" ] || report_failure "could not read the image version (${BASE_VER}…) from the init in kernel/initrd.cpio"

CONFIG_IMG="${REPO_ROOT}/out/cr-config.img"
HOME_IMG="${REPO_ROOT}/out/cr-home.img"
SEED="$(mktemp -d)"
printf '%s\n' 'shell=fish' 'keyboard=apple' "user=${USER_NAME}" > "$SEED/tars.conf"
rm -f "$CONFIG_IMG"
truncate -s 16M "$CONFIG_IMG"
mkfs.ext2 -F -q -m 0 -L tars-cr -d "$SEED" "$CONFIG_IMG"
rm -rf "$SEED"
LAYER_SEED="$(mktemp -d)"
mkdir -p "$LAYER_SEED/.tars/layers" "$LAYER_SEED/cr"
cp ../devlayer/build/base.sqfs ../devlayer/build/gpu.sqfs ../devlayer/build/media.sqfs ../devlayer/build/browser.sqfs "$LAYER_SEED/.tars/layers/"
echo "$IMAGE_VER" > "$LAYER_SEED/.tars/layers/version"
cat > "$LAYER_SEED/cr/page.html" <<EOF
<!doctype html><meta charset="utf-8"><title>${PAGE_TITLE}</title>
<style>html,body{margin:0;height:100%;background:#${PAGE_BG}}
#box{position:absolute;left:40px;top:40px;width:300px;height:200px;background:#${PAGE_BOX}}
#ko{position:absolute;left:40px;top:300px;font:64px sans-serif;color:#000;background:#${PAGE_TEXT_BG};padding:8px}</style>
<div id="box"></div><div id="ko">한글 漢字</div>
EOF
chmod 0755 "$LAYER_SEED/cr"
chmod 0644 "$LAYER_SEED/cr/page.html"
rm -f "$HOME_IMG"
truncate -s $(( $(du -sm "$LAYER_SEED" | cut -f1) + 128 ))M "$HOME_IMG"
mkfs.ext4 -F -q -L tars-home -d "$LAYER_SEED" "$HOME_IMG"
rm -rf "$LAYER_SEED"
echo "=== boot: ${USER_NAME} with the base, gpu, media and browser bundles (version ${IMAGE_VER}, -m ${CR_MEM}) ==="

qemu-system-x86_64 \
  -nic none \
  -m "$CR_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci,xres=${XRES},yres=${YRES} \
  -display none \
  -drive file="$CONFIG_IMG",if=virtio,format=raw \
  -drive file="$HOME_IMG",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

ready=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOG" >/dev/null; then ready=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$ready" = "1" ] || report_failure "terminal never rendered a prompt"
wait_for_screen "${USER_NAME}@tars" || report_failure "the ${USER_NAME} prompt never showed up"

connected=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
  sleep 0.5
done
[ "$connected" = "1" ] || report_failure "could not connect to the QEMU monitor on port ${MONITOR_PORT}"

grep -aF "tars-init: starting as PID 1 (TARS ${IMAGE_VER})" "$LOG" > /dev/null ||
  report_failure "the image says $(grep -aoE 'starting as PID 1 \(TARS [^)]+\)' "$LOG" | head -n 1), the bundles were written for ${IMAGE_VER}"

# ── 판정 1: 묶음 넷이 /usr에 ──────────────────────────────────────────────
echo "=== (1) the base, gpu, media and browser bundles are laid over /usr ==="
wait_for_log 'tars-init: overlay /usr from 4 layers in [0-9]+ms' || report_failure "(1) init did not lay four bundles over /usr"
wait_for_log 'tars-init: layer browser: [0-9]+ files into /etc' || report_failure "(1) the browser bundle's etc/ was not copied into /etc"
echo "(1) $(tlog | grep -aoE 'tars-init: overlay /usr from 4 layers in [0-9]+ms' | head -n 1), $(tlog | grep -aoE 'layer browser: [0-9]+ files into /etc' | head -n 1)"

# ── 판정 6: Wayland 없이 부른 문은 이유와 1 ────────────────────────────────
echo "=== (6) tars-browser without WAYLAND_DISPLAY says why and exits 1 ==="
# shellcheck disable=SC2016 # 게스트의 fish가 펼칠 글자다.
type_line 'env -u WAYLAND_DISPLAY tars-browser; echo cr6-$status'
wait_for_screen "tars-browser: no Wayland display \\(WAYLAND_DISPLAY=''" || report_failure "(6) tars-browser did not say there is no Wayland display"
wait_for_screen 'cr6-1' || report_failure "(6) tars-browser did not exit 1 without a Wayland display"
echo "(6) no WAYLAND_DISPLAY: one line and exit 1"

# ── 판정 2: Chromium이 toplevel · 이름 · 호환 키 · 636 × 772 ─────────────────
echo "=== (2) tars-browser file://… is a chromium-browser window with a 636x772 buffer within ${FIRST_SECONDS}s ==="
t0="$(date +%s)"
type_line 'tars-browser file:///home/cr/page.html 2> /tmp/cr.log &'
wait_for_log 'terminal: wl> title id=[0-9]+ app_id=chromium-browser ' "$FIRST_SECONDS" || report_failure "(2) no chromium-browser toplevel in ${FIRST_SECONDS}s"
CR_ID="$(tlog | grep -aoE 'terminal: wl> title id=[0-9]+ app_id=chromium-browser ' | head -n 1 | sed -E 's/.*id=([0-9]+) .*/\1/')"
wait_for_log "terminal: wl> commit id=${CR_ID} buf=636x772 scale=1 at=0,0" "$FIRST_SECONDS" ||
  report_failure "(2) chromium's window ${CR_ID} committed no 636x772 buffer in ${FIRST_SECONDS}s"
FIRST_S=$(( $(date +%s) - t0 ))
wait_for_log "terminal: menu> bar id=${CR_ID} name=chromium-browser " || report_failure "(2) the top band does not name chromium-browser"
wait_for_log "terminal: wl> keys to=${CR_ID} mode=compat" || report_failure "(2) chromium's keys are not in compat mode"
echo "(2) window ${CR_ID}: app_id chromium-browser, the band names it, keys in compat mode, 636x772 committed ${FIRST_S}s after the command"

# ── 판정 3: 제목 · 페이지 좌표 색 · 한글 상자 ───────────────────────────────
echo "=== (3) the page title is the window title, the page's colours are where the HTML put them, the Hangul box is inked by a real font ==="
wait_for_log "terminal: wl> title id=${CR_ID} app_id=chromium-browser title=${PAGE_TITLE} - Chromium" "$FIRST_SECONDS" ||
  report_failure "(3) the window title never became '${PAGE_TITLE} - Chromium'"
# 그리기가 끝났는지는 모른다 — 판정이 모두 맞는 덤프가 두 장 잇달아 같을 때까지(60초).
page_state() {
  # shellcheck disable=SC2086 # 상자 넷은 낱말로 갈라 넘긴다.
  echo "box[$(ppm_ink "$SHOT" $BOX_PROBE)] bg[$(ppm_ink "$SHOT" $BG_PROBE)] glyph[$(ink_colours "$SHOT" $GLYPH_PROBE "$PAGE_TEXT_BG")]"
}
page_ok() {
  local s="$1" colours
  [[ "$s" == "box[bg=${PAGE_BOX} ink=0] bg[bg=${PAGE_BG} ink=0] glyph[ink="* ]] || return 1
  colours="${s##*colours=}"
  colours="${colours%]}"
  [[ "$s" != *"glyph[ink=0 "* ]] && [ "$colours" -ge "$GLYPH_COLOURS_MIN" ]
}
prev=""
stable=0
for _ in $(seq 1 $((FIRST_SECONDS * 2))); do
  screendump "$SHOT" || report_failure "(3) screendump did not write ${SHOT}"
  PAGE_STATE="$(page_state)"
  if page_ok "$PAGE_STATE" && [ "$PAGE_STATE" = "$prev" ]; then stable=1; break; fi
  prev="$PAGE_STATE"
  sleep 0.5
done
[ "$stable" = "1" ] || report_failure "(3) the page never settled on its colours (last: ${PAGE_STATE}; want box ${PAGE_BOX}, bg ${PAGE_BG}, glyph colours >= ${GLYPH_COLOURS_MIN})"
cp "$SHOT" "${SCREENS_DIR}/first.ppm"
convert "$SHOT" "${JUDGE_DIR}/cr-first.png" || report_failure "(3) could not write ${JUDGE_DIR}/cr-first.png"
convert "$SHOT" -crop 616x665+644+107 +repage -scale 200% "${JUDGE_DIR}/cr-page-2x.png" || report_failure "(3) could not write ${JUDGE_DIR}/cr-page-2x.png"
echo "(3) ${PAGE_STATE}; the screens are ${JUDGE_DIR}/cr-first.png and cr-page-2x.png"

# ── 판정 4: 렌더러의 sandbox ──────────────────────────────────────────────
#
# 화면 셸은 Chromium과 같은 uid라 /proc/<pid>/status · uid_map · ns/user가 읽힌다(단계 B 실측 2). 렌더러는 `--type=renderer`, 브라우저는
# 가장 오래된 /usr/lib/chromium/chromium이다. 한 줄로 찍는다 — 렌더러의 `Seccomp: 2` 셈(1), 두 user ns, 렌더러의 uid_map.
echo "=== (4) the renderer runs under a seccomp filter in a user namespace of its own ==="
ACT0="terminal: wl> configure id=${CR_ID} w=616 h=752 act=0"
n_act0="$(count_log "$ACT0")"
type_keys meta_l-bracket_left
wait_for_count "$ACT0" $((n_act0 + 1)) || report_failure "(4) Cmd+[ did not take the keyboard from chromium"
# shellcheck disable=SC2016 # 게스트의 fish가 펼칠 글자다.
type_line 'set r (pgrep -f type=renderer | head -n 1); set b (pgrep -o -f lib/chromium/chromium); echo cr4a $r (grep -c '"'"'^Seccomp:\s2$'"'"' /proc/$r/status); echo cr4b (readlink /proc/$r/ns/user) (readlink /proc/$b/ns/user); echo cr4c (cat /proc/$r/uid_map)'
# 셋으로 나눠 찍는다 — Chromium의 열이 서 있어 셸은 화면의 반쪽(약 77칸)이고, 한 줄로는 꺾인다.
wait_for_screen 'cr4c +[0-9]+ +[0-9]+ +[0-9]+' || report_failure "(4) the renderer's /proc lines did not come"
DUMP="$(joined_screen_dump | tail -n 1)"
read -r _ R_PID R_SECCOMP <<<"$(grep -aoE 'cr4a [0-9]+ [0-9]+' <<<"$DUMP" | tail -n 1)"
read -r _ R_NS B_NS <<<"$(grep -aoE 'cr4b user:\[[0-9]+\] user:\[[0-9]+\]' <<<"$DUMP" | tail -n 1)"
read -r _ R_MAP_IN R_MAP_OUT R_MAP_N <<<"$(grep -aoE 'cr4c +[0-9]+ +[0-9]+ +[0-9]+' <<<"$DUMP" | tail -n 1)"
SB_LINE="renderer ${R_PID:-?} seccomp ${R_SECCOMP:-?} ${R_NS:-?} browser ${B_NS:-?} uid_map ${R_MAP_IN:-?} ${R_MAP_OUT:-?} ${R_MAP_N:-?}"
[ -n "${R_PID:-}" ] && [ -n "${B_NS:-}" ] || report_failure "(4) could not read the renderer's lines (${SB_LINE})"
[ "$R_SECCOMP" = 1 ] || report_failure "(4) renderer ${R_PID} is not under a seccomp filter (${SB_LINE})"
[ "$R_NS" != "$B_NS" ] || report_failure "(4) renderer ${R_PID} shares the browser's user namespace ${B_NS}"
[ "$R_MAP_IN $R_MAP_OUT $R_MAP_N" = "1000 1000 1" ] || report_failure "(4) renderer ${R_PID}'s uid_map is '${R_MAP_IN} ${R_MAP_OUT} ${R_MAP_N}', want '1000 1000 1'"
echo "(4) renderer ${R_PID}: Seccomp 2, ${R_NS} (the browser is in ${B_NS}), uid_map ${R_MAP_IN} ${R_MAP_OUT} ${R_MAP_N}"

# ── 판정 5: Cmd+Q — Chromium이 스스로 끝나고 아무것도 안 남는다 ───────────────
echo "=== (5) Cmd+Q closes chromium, it leaves by itself and no chromium process is left ==="
ACT1="terminal: wl> configure id=${CR_ID} w=616 h=752 act=1"
n_act1="$(count_log "$ACT1")"
type_keys meta_l-bracket_right
wait_for_count "$ACT1" $((n_act1 + 1)) || report_failure "(5) Cmd+] did not give chromium the keyboard"
type_keys meta_l-q
wait_for_log "terminal: wl> close id=${CR_ID}" || report_failure "(5) Cmd+Q sent no 'wl> close id=${CR_ID}'"
wait_for_log "terminal: wl> unmap id=${CR_ID} " || report_failure "(5) chromium's window did not go"
wait_for_log 'terminal: wl> gone pid=[0-9]+' || report_failure "(5) chromium's client never went"
wait_for_screen "${USER_NAME}@tars" || report_failure "(5) the shell prompt is not back"
# 프로세스가 0이 될 때까지 본다 — 0이 된 뒤에 kill 줄이 없으면 kill은 없었다(서버는 kill 전에 그 줄을 찍는다).
left=""
for i in $(seq 1 20); do
  type_line "echo cr5-${i}-(pgrep -c -f lib/chromium)"
  wait_for_screen "cr5-${i}-[0-9]+" || report_failure "(5) the shell did not answer the process count"
  left="$(joined_screen_dump | grep -aoE "cr5-${i}-[0-9]+" | tail -n 1)"
  left="${left##*-}"
  [ "$left" = 0 ] && break
  sleep 0.5
done
[ "$left" = 0 ] || report_failure "(5) ${left} chromium process(es) still running after Cmd+Q"
if tlog | grep -aE 'terminal: wl> kill ' > /dev/null; then
  report_failure "(5) chromium was killed — it should have left on close"
fi
echo "(5) close · unmap · gone, no kill, no chromium process left"

# ── render verify ─────────────────────────────────────────────────────────
if tlog | grep -a 'terminal: verify> mismatch' > /dev/null; then
  report_failure "render verify saw a mismatch"
fi
echo "render verify lines $(count_log 'terminal: verify> '), no mismatch"

echo "PASS: CR-M1 — four bundles over /usr; tars-browser without a Wayland display says why and exits 1; in the screen shell it starts Debian's Chromium on TARS's Wayland server as a chromium-browser window with a 636x772 buffer in ${FIRST_S}s; the page title, the HTML's colours and a Hangul and Hanzi box drawn by noto-cjk are on the screen; the renderer runs under seccomp in a user namespace of its own; Cmd+Q closes it with no kill and no process left"
