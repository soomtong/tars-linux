#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# HI 체인 — 한글 입력.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Shift+Space를 누른다
#   → input.zig의 hangulLayer가 한/영을 켠다
#   → 두벌식 키가 자모가 되고 hangul.zig가 음절로 모은다
#   → 그 글자가 **PTY로 안 나가고** 커서 자리에 그려진다
#   → Backspace가 자모를 하나 뺀다
#   → Enter가 조합을 확정시켜 UTF-8 세 바이트와 CR을 **한 번에** 내보낸다
#   → **셸이 그 한글을 되울리고 실행한다**
#   → Shift+Space를 다시 누르면 영문으로 돌아온다
#
# **음성 검사가 이 체인의 값이다.** "한글이 조합된다"만 보면 조합 중인 자모가
# PTY로 새는지는 아무것도 증명되지 않는다 — 그리고 그것이 이 기능의 가장 흔한
# 실패 방식이다. 도구는 CM 체인과 같은 `terminal: key>` 줄 개수다. 그 줄은
# PTY로 바이트가 나갈 때만 찍히므로(main.zig의 `if (keys.bytes.len > 0)`)
# 개수가 안 늘어나는 것이 곧 "아무것도 안 나갔다"이다.
#
# **반전된 셀의 개수가 두 번째 도구다.** 한글은 두 칸이라(HI-M0 실측 3) 조합
# 중에는 커서가 두 칸을 반전한다. 하나만 반전되면 게스트 화면에서 글자의
# 오른쪽 절반이 어두운 바탕에 어두운 색으로 그려져 사라지는데, 로그만 보는
# 게이트가 그 사고를 잡는 길이 이 셀 개수다.
#
# grep에 -a를 붙이는 이유는 로그에 NUL이 한 바이트라도 섞이면 grep이 파일을
# binary로 취급해 "Binary file matches"만 뱉기 때문이다.
#
# **디스크를 문다(HI-M2).** `hangul_layout=sebeol_3p3`이 든 이미지를 굽고
# 읽기만 한다. **2차 부팅은 안 붙였다** — 설정이 자판까지 닿는지만 보면 되고,
# 설정을 쓰고 다시 읽는 왕복은 CP 체인이 이미 본다(design 결정 14).
#
# 그래서 **이 체인이 게스트에서 돌리는 자판은 공세벌 3-P3 하나다.** 두벌식은
# `hangul_test`가, 기본값이 shin_pcs라는 것은 `config_test`가 본다. 그 교환을
# 받아들인 이유는 설정 → argv → 자판 선택 배선이 **호스트 검사로는 절대 안
# 보이는 유일한 구간**이기 때문이다.
#
# 3-P3의 키는 초성이 오른손, 중성과 종성이 왼손이다. 아래에서 쓰는 것 넷:
#   k = 초성 ㄱ    f = 중성 ㅏ    q = 종성 ㅅ    h = 초성 ㄴ    u = 초성 ㄷ
# 그래서 `kf`가 `가`이고 `kfq`가 `갓`, `kfhfuf`가 `가나다`다.

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

# 한글 층의 분기 순서와 확정 목록은 전부 여기서 먼저 걸러진다 — 부팅 1.5초를
# 쓰기 전에 0.1초로 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (input_test, vt_test or hangul_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 설정 디스크. **매 회차 새로 굽는다** — 그 이유는 make_disk.sh의 주석에 있다.
if ! ./make_disk.sh; then
  echo "FAIL: hangul config disk build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR, 45461=CM.
# 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에
# 명령을 보내지 않기 위해서다.
MONITOR_PORT=45462

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
    "tars-init: config " \
    "tars-init: config .*toggles=" \
    "terminal: hangul layout=" \
    "terminal: hangul layout=.*toggles=" \
    "terminal: screen>" \
    "terminal: hangul>" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- hangul lines ---"
  grep -a 'terminal: hangul>' "$LOG" | tail -n 20
  echo "--- key lines ---"
  grep -a 'terminal: key>' "$LOG" | tail -n 10
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# key> 줄이 지금까지 몇 개 찍혔는지. 음성 검사가 이 값의 변화를 본다.
key_lines() {
  grep -ac 'terminal: key>' "$LOG" || true
}

# 마지막 hangul> 줄에서 값 하나를 뽑는다. **언제나 마지막 줄을 본다** — 그
# 줄이 곧 지금의 상태다.
#
# **`tr -d '\r'`이 없으면 안 된다.** 시리얼 로그는 줄을 CRLF로 끝내는데
# `preedit=`은 줄 끝이라 `[^ ]+`가 CR까지 삼킨다. 증상이 지독하다 —
# `preedit=가, expected 가`처럼 **똑같아 보이는 값으로 실패한다.**
# `copy/check.sh`의 `copy_value`가 이 함정을 안 밟은 것은 `([0-9]+)`로 잡아
# 숫자에서 멈추기 때문이고, 우연이지 설계가 아니다.
hangul_field() {
  grep -a 'terminal: hangul>' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E "s/.*$1=([^ ]+).*/\1/"
}

# 마지막 프레임만 잘라낸다. main.zig가 한 프레임을 screen> 로 시작하므로
# (dumpScreen이 render 직후 첫 번째다) 마지막 screen> 부터 파일 끝까지가 곧
# 마지막 프레임이다. **누적으로 세면 "부팅 이후 몇 번 찍혔는가"가 된다.**
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

# 마지막 프레임에서 **반전된 셀**이 전부 몇 개인가.
#
# 기본 색은 fg=FFFFFF bg=102030이고(vt.zig의 init), 반전되면 정확히 뒤집힌
# 값이 된다. 이 화면에는 선택도 매치도 없으므로 반전된 셀은 커서뿐이고,
# 그래서 개수가 곧 "커서가 몇 칸을 먹었는가"다.
inverted_cells() {
  last_frame | grep -acE "terminal: style> [0-9]+,[0-9]+ fg=102030 bg=FFFFFF" || true
}

# 키 하나를 `ms` 밀리초 동안 누르고 있다가 뗀다(HI-M3).
#
# **`type_keys`를 못 쓴다.** 이유가 둘이다.
#   1. 그쪽은 `sendkey $k` 하나만 보내므로 hold 시간을 못 준다.
#   2. 그쪽은 로그가 자라기를 기다리는데, **긴 CapsLock은 로그를 한 줄도 안
#      만들 수 있다** — 대문자 잠금만 켜지고 화면은 그대로다. 그러면 0.3초를
#      꽉 채우고 다음 줄로 간다(그 자체는 안전하지만 판정이 흐려진다).
#
# **hold가 끝나기를 여기서 기다려야 한다.** `sendkey`의 hold는 QEMU가 타이머로
# 처리하므로 monitor는 즉시 돌아온다 — 안 기다리면 다음 키가 이 키를 **누른
# 채로** 도착해서 "소비됨"이 켜지고 tap이 사라진다. 1.5초는 이 체인이 쓰는
# 최대 hold(0.5초)에 게스트 반응 시간을 얹은 값이다.
#
# QEMU가 이 값을 오차 4밀리초 안에 지킨다는 것은 HI-M0이 evdev 타임스탬프로
# 쟀다(실측 2). 그래서 문턱 0.3초의 양쪽을 게이트가 실제로 밟을 수 있다.
hold_key() {
  local key="$1" ms="$2"
  echo "sendkey $key $ms" >&3
  sleep 1.5
}

# 마지막 프레임의 화면 줄에서 그 문자열이 몇 번 나오는가.
screen_count() {
  last_frame | grep -a 'terminal: screen>' | grep -oaF "$1" | wc -l
}

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file=../out/hangul.img,if=virtio,format=raw \
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

# ── 검사 0: 설정이 자판을 골랐다 ───────────────────────────────────────
#
# **줄 둘을 다 본다.** 앞의 줄은 "init이 디스크의 파일에서 읽었다"를, 뒤의
# 줄은 "그 값이 argv를 건너 terminal에 닿았다"를 말한다. **앞만 보면 argv
# 배선이 끊겨도 초록이고, 뒤만 보면 terminal의 기본값이 우연히 맞아도
# 초록이다.**
#
# 심은 값이 기본값(shin_pcs)이 아닌 것이 이 검사의 전제다 — 같았다면 설정을
# 통째로 무시하는 코드도 통과한다. **그리고 아래 검사 3~11이 전부 3-P3 키를
# 쓰므로, 이 검사가 실패하면 그것들도 함께 실패한다** — 진짜 판정은 둘이 짝을
# 이루는 데서 온다.
echo "=== the config disk should have selected sebeol_3p3 ==="
if ! grep -aq 'tars-init: config .*hangul=sebeol_3p3' "$LOG"; then
  report_failure "init did not read hangul_layout=sebeol_3p3 from the config disk"
fi
if ! grep -aq 'terminal: hangul layout=sebeol_3p3' "$LOG"; then
  report_failure "the layout did not reach terminal through argv"
fi
echo "sebeol_3p3 came from the config file and reached the composer"

# 전환 키 목록도 같은 짝을 이룬다(HI-M3). **판정이 둘이 아니라 셋이다.**
#
#   1. init이 파일에서 읽었다
#   2. 그 값이 argv를 건너 terminal에 닿았다
#   3. **`hangul_key`가 목록에 없다** — 기본값은 넷이므로, 설정을 통째로
#      무시하는 코드는 `hangul_key,`로 시작하는 목록을 찍는다.
#
# 셋째가 이 체인이 "꺼짐"을 보는 유일한 자리다. 나머지 꺼짐 갈래 넷은
# `input_test`가 호스트에서 본다.
echo "=== the config disk should have selected three toggle keys ==="
#
# **CR을 먼저 지우고 나서 `$`를 쓴다 — 그러지 않으면 줄이 정확히 맞는데도 안
# 맞는다.** 시리얼 로그는 줄을 CRLF로 끝내므로 `$` 바로 앞에 CR이 있다.
# HI-M1 실측 4가 `[^ ]+`로 밟은 것과 같은 함정이고, `hangul_field`가 쓰는
# 처방을 그대로 쓴다.
#
# **plan이 적어 둔 `\r\?$`는 안 통했다**(HI-M3 실측). GNU grep의 BRE는 `\r`을
# CR 이스케이프로 안 보고 **리터럴 `r`로** 읽는다 — `-P` 없이는 그 표기가
# 아무 뜻도 없다. 파이프로 CR을 지우는 쪽이 이 파일의 기존 관습과도 같다.
EXPECT_TOGGLES='shift_space,capslock_tap,lctrl_tap'
if ! tr -d '\r' < "$LOG" | grep -aq "tars-init: config .*toggles=${EXPECT_TOGGLES}\$"; then
  report_failure "init did not read hangul_toggle=${EXPECT_TOGGLES} from the config disk"
fi
if ! tr -d '\r' < "$LOG" |
  grep -aq "terminal: hangul layout=sebeol_3p3 latin=qwerty toggles=${EXPECT_TOGGLES}\$"; then
  report_failure "the toggle list did not reach terminal through argv"
fi
echo "three toggle keys came from the config file; hangul_key is off"

# ── 검사 1: 대조군 — 한글이 꺼져 있으면 키가 PTY로 나간다 ──────────────
#
# **이 검사가 없으면 아래 음성 검사가 뜻을 잃는다.** 키가 원래부터 안 나가고
# 있었다면 "조합 중에 안 나간다"는 아무것도 증명하지 않는다.
echo "=== typing 'echo ' with hangul off ==="
BEFORE_ECHO="$(key_lines)"
type_keys e c h o spc
sleep 1
AFTER_ECHO="$(key_lines)"
if [ "$AFTER_ECHO" -le "$BEFORE_ECHO" ]; then
  report_failure "plain keys did not reach the PTY (key> lines ${BEFORE_ECHO} -> ${AFTER_ECHO})"
fi
if [ "$(screen_count 'echo')" -lt 1 ]; then
  report_failure "the shell never echoed 'echo'"
fi
echo "plain keys reach the PTY and the shell echoes them"

# 조합 중이 아닐 때 커서가 먹는 칸 수. 아래 검사 3이 이 값과 비교한다.
CURSOR_CELLS="$(inverted_cells)"
if [ "$CURSOR_CELLS" != "1" ]; then
  report_failure "expected exactly 1 inverted cell for the shell cursor, got ${CURSOR_CELLS}"
fi

# ── 검사 2: Shift+Space가 한/영을 켠다 ─────────────────────────────────
#
# **`hangul>` 줄이 나온다는 것 자체가 절반이다.** 그 줄은 `keys.hangul`이
# 참일 때만 찍히므로(main.zig), 줄이 없으면 `Action.hangul`이 `readKeys`까지
# 못 왔다는 뜻이다.
echo "=== sendkey shift-spc ==="
BEFORE_TOGGLE="$(key_lines)"
type_keys shift-spc
sleep 1
if ! grep -aq 'terminal: hangul>' "$LOG"; then
  report_failure "Shift+Space produced no hangul> line at all"
fi
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "Shift+Space left hangul on=${ON}, expected true"
fi
# **공백이 셸로 새면 안 된다.** 전환 키가 글자를 만들면 명령줄에 빈칸이
# 하나씩 늘어난다.
AFTER_TOGGLE="$(key_lines)"
if [ "$AFTER_TOGGLE" != "$BEFORE_TOGGLE" ]; then
  report_failure "Shift+Space leaked to the PTY (key> lines ${BEFORE_TOGGLE} -> ${AFTER_TOGGLE})"
fi
echo "Shift+Space turned hangul on and sent nothing to the shell"

# ── 검사 3: 세벌식이 조합되고, 그 글자는 PTY로 안 나간다 ───────────────
#
# 3-P3에서 `k`=초성 ㄱ, `f`=중성 ㅏ 라 `가`가 된다. 넷을 함께 본다.
#
#   1. `hangul> preedit=가`      — 조합 상태가 맞다
#   2. 마지막 프레임의 `screen>`에 `가`  — **화면에 실제로 그려졌다**
#   3. 반전된 셀이 **둘**        — 두 칸을 먹었다(HI-M0 실측 3)
#   4. `key>` 줄이 안 늘었다     — 음성 검사
#
# **1만 보면 "값은 맞는데 안 그렸다"를 못 잡고, 2만 보면 "그렸는데 값이
# 틀렸다"를 못 잡는다.** SP-M1의 실측 5가 같은 자리를 적어 두었다.
echo "=== typing 'kf' (가) ==="
type_keys k f
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "가" ]; then
  report_failure "typing 'kf' composed preedit=${PRE}, expected 가"
fi
if [ "$(screen_count '가')" -lt 1 ]; then
  report_failure "the composing syllable 가 was never drawn on screen"
fi
INV="$(inverted_cells)"
if [ "$INV" != "2" ]; then
  report_failure "the composing syllable took ${INV} inverted cell(s), expected 2"
fi
AFTER_JAMO="$(key_lines)"
if [ "$AFTER_JAMO" != "$AFTER_TOGGLE" ]; then
  report_failure "composing jamo leaked to the PTY (key> lines ${AFTER_TOGGLE} -> ${AFTER_JAMO})"
fi
echo "가 is composed, drawn across two cells, and nothing reached the shell"

# ── 검사 4: 받침이 붙는다 ──────────────────────────────────────────────
echo "=== typing 'q' (갓) ==="
type_keys q
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "갓" ]; then
  report_failure "adding the final gave preedit=${PRE}, expected 갓"
fi
echo "the final attached: 가 -> 갓"

# ── 검사 5: Backspace가 자모를 하나 뺀다 ───────────────────────────────
#
# **음절을 통째로 지우지 않는 것이 요점이다**(design 결정 6). 그리고
# Backspace도 PTY로 안 나가야 한다 — 나가면 셸이 앞 글자를 하나 지운다.
echo "=== sendkey backspace ==="
type_keys backspace
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "가" ]; then
  report_failure "backspace gave preedit=${PRE}, expected 가"
fi
AFTER_BKSP="$(key_lines)"
if [ "$AFTER_BKSP" != "$AFTER_JAMO" ]; then
  report_failure "backspace while composing leaked to the PTY (key> lines ${AFTER_JAMO} -> ${AFTER_BKSP})"
fi
echo "backspace removed one jamo and sent nothing to the shell"

# ── 검사 6: Enter가 확정시키고 네 바이트가 한 번에 나간다 ──────────────
#
# **`key> 4 byte(s)`가 이 milestone의 결승선이다.** 확정된 음절의 UTF-8 세
# 바이트와 CR 하나가 **같은 write**로 나갔다는 뜻이고, 그것이 `readKeys`가
# 지키는 순서 계약(확정이 먼저)의 유일한 관측 가능한 증거다.
#
# 셋이 아니라 넷인 것에 뜻이 있다. 셋이면 CR이 빠진 것이고, 하나면 확정이
# 통째로 사라진 것이다.
echo "=== typing 'q' then Enter ==="
type_keys q
sleep 1
type_keys ret
sleep 2
if ! grep -aq 'terminal: key> 4 byte(s)' "$LOG"; then
  report_failure "Enter did not send the committed syllable and CR as one 4-byte write"
fi
PRE="$(hangul_field preedit)"
if [ "$PRE" != "(none)" ]; then
  report_failure "Enter left preedit=${PRE}, expected (none)"
fi
echo "Enter committed 갓 and sent 3 UTF-8 bytes plus CR in one write"

# ── 검사 7: 셸이 그 한글을 되울리고 실행한다 ───────────────────────────
#
# 명령줄에 하나(`echo 갓`), 출력줄에 하나. **둘이라는 것이 왕복의 증거다** —
# 하나면 셸이 되울리기만 하고 실행은 안 된 것이고, 없으면 세 바이트가 셸에
# 도착하지 않았거나 깨진 것이다.
#
# 이 검사는 착수 전에 실측으로 확정했다. 게스트에 LANG도 LC_ALL도 없어서
# C 로케일의 fish가 UTF-8을 되울릴지 몰랐는데, HI-M1의 실측이 되울린다고
# 답했다.
if [ "$(screen_count '갓')" -lt 2 ]; then
  report_failure "the shell did not echo and run the committed syllable"
fi
echo "the shell echoed 갓 on the command line and printed it as output"

# ── 검사 8: 조합이 끝난 뒤 커서가 다시 한 칸이다 ───────────────────────
#
# 안 돌아오면 증상이 "커서가 항상 두 칸으로 뚱뚱하다"이고, 원인은 `preedit`을
# 안 지운 것이다. **검사 3의 값과 짝이어야 뜻이 선다.**
INV="$(inverted_cells)"
if [ "$INV" != "1" ]; then
  report_failure "after committing, the cursor takes ${INV} inverted cell(s), expected 1"
fi
echo "the cursor is back to one cell"

# ── 검사 9: Shift+Space가 한/영을 끈다 ─────────────────────────────────
echo "=== sendkey shift-spc again ==="
type_keys shift-spc
sleep 1
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "the second Shift+Space left hangul on=${ON}, expected false"
fi
echo "Shift+Space turned hangul off"

# ── 검사 10: 영문이 돌아온다 ───────────────────────────────────────────
#
# **대조군이 하나 더 필요한 이유가 있다.** 검사 1은 한글을 켜기 **전**을
# 봤으므로, 껐을 때 되돌아오는지는 아무것도 말하지 않는다 — 토글이 한
# 방향으로만 동작해도 검사 1과 9가 전부 통과한다.
echo "=== typing 'kf' with hangul off ==="
BEFORE_LATIN="$(key_lines)"
type_keys k f
sleep 1
AFTER_LATIN="$(key_lines)"
if [ "$AFTER_LATIN" -le "$BEFORE_LATIN" ]; then
  report_failure "latin keys did not reach the PTY after turning hangul off"
fi
if [ "$(screen_count 'kf')" -lt 1 ]; then
  report_failure "the shell never echoed 'kf' after turning hangul off"
fi
echo "latin input is back"

# ── 검사 11: 음절 셋을 이어 쳐도 앞 글자가 안 지워진다 ─────────────────
#
# **이 검사가 없어서 HI-M1이 사고를 안고 통과했다.** 위 검사들은 음절을
# **하나만** 확정시키는데, 그러면 게스트에 UTF-8 로케일이 없어도 통과한다 —
# 로케일이 없으면 셸이 우리가 보낸 세 바이트를 한 글자가 아니라 **세 글자로**
# 읽고 바이트마다 폭을 세는데(0x80~0x9F는 0칸, 0xA0 이상은 1칸), `갓`은
# EA B0 93이라 1+1+0 = 2가 되어 **깨진 계산이 우연히 맞는 답을 낸다.**
#
# 두 번째 음절부터 어긋난 폭이 쌓여서 셸이 커서를 두 칸짜리 글자의 가운데에
# 세우고, 거기에 다음 글자를 써서 앞 글자를 지운다. 증상은 `가나다`가
# **`가 다`**로 나타나는 것이다.
#
# `가나다`가 **둘** 나와야 한다 — 명령줄과 출력줄. 깨지면 명령줄이 `가 다`가
# 되므로 하나로 준다. **출력줄은 깨져도 멀쩡하다**(그쪽은 셸이 커서를
# 계산하지 않고 쭉 쓰기만 한다). 그래서 "둘"이 판정이고 "하나 이상"은 아니다.
echo "=== typing 'echo 가나다' ==="
type_keys ctrl-c
sleep 1
type_keys e c h o spc
type_keys shift-spc
type_keys k f h f u f
type_keys ret
sleep 2
if [ "$(screen_count '가나다')" -lt 2 ]; then
  report_failure "three syllables in a row got corrupted: the command line lost a character"
fi
echo "three syllables in a row survive on the command line"

# ── 검사 12: 짧은 CapsLock이 한/영을 끈다 ──────────────────────────────
#
# **`sendkey caps_lock 100`의 100은 밀리초다.** 문턱이 0.3초이므로 이것은
# tap이고, 검사 13의 500은 hold다. **둘이 짝이어야 뜻이 선다** — 짧은 것만
# 보면 "언제나 전환한다"가 통과한다.
#
# 여기 오기 전에 검사 11이 한/영을 켜 두었다.
#
# **음성 검사가 함께 있어야 한다** — CapsLock이 글자를 만들면 명령줄이
# 더러워지고, 그것이 표 밖의 키를 다루는 가장 흔한 실패 방식이다.
echo "=== sendkey caps_lock 100 (tap) ==="
BEFORE_CAPS="$(key_lines)"
hold_key caps_lock 100
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "a short CapsLock left hangul on=${ON}, expected false"
fi
AFTER_CAPS="$(key_lines)"
if [ "$AFTER_CAPS" != "$BEFORE_CAPS" ]; then
  report_failure "CapsLock leaked to the PTY (key> lines ${BEFORE_CAPS} -> ${AFTER_CAPS})"
fi
echo "a short CapsLock turned hangul off and sent nothing to the shell"

# ── 검사 13: 긴 CapsLock은 한/영을 안 바꾸고 대문자 잠금을 켠다 ─────────
#
# **판정이 화면이다.** 대문자 잠금에는 LED도 표시도 없으므로(결정 9), 켜졌는지
# 아는 유일한 길은 다음 글자가 대문자로 나오는 것이다.
#
# **숫자를 함께 치는 것이 결정 9의 전부다** — CapsLock은 알파벳에만 적용되고
# 숫자와 기호는 안 바뀐다. `abc1`을 쳐서 `ABC1`이 나와야 하고, Shift를 통째로
# 걸어 버리는 구현은 `ABC!`를 낸다.
#
# **한/영이 안 바뀐 것도 함께 본다.** `hangul_field`는 마지막 `hangul>` 줄을
# 읽는데, 그 줄은 `Action.hangul`이 나올 때만 찍힌다 — 긴 CapsLock이 잘못
# 전환하면 새 줄이 `on=true`로 찍혀서 여기가 갈린다.
echo "=== sendkey caps_lock 500 (hold) ==="
hold_key caps_lock 500
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "a long CapsLock changed hangul to on=${ON}, expected false"
fi
type_keys a b c 1
sleep 1
if [ "$(screen_count 'ABC1')" -lt 1 ]; then
  report_failure "a long CapsLock did not lock capitals (expected ABC1 on screen)"
fi
echo "a long CapsLock locked capitals and left the digit alone"

# ── 검사 14: 한 번 더 길게 누르면 잠금이 풀린다 ─────────────────────────
#
# **켜지는 것만 보면 토글이 한 방향으로만 동작해도 통과한다** — 검사 1과 9가
# Shift+Space에 대해 이루는 짝과 같은 이유다.
echo "=== sendkey caps_lock 500 again ==="
hold_key caps_lock 500
type_keys a
sleep 1
if [ "$(screen_count 'ABC1a')" -lt 1 ]; then
  report_failure "a second long CapsLock did not release the capital lock"
fi
echo "a second long CapsLock released the lock"

# ── 검사 15: 짧은 왼쪽 Ctrl이 한/영을 켠다 ─────────────────────────────
echo "=== ctrl-c to clear the line, then sendkey ctrl 100 ==="
type_keys ctrl-c
sleep 1
hold_key ctrl 100
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "a short left Ctrl left hangul on=${ON}, expected true"
fi
echo "a short left Ctrl turned hangul on"

# ── 검사 16: Ctrl+C는 한/영을 안 바꾼다 ────────────────────────────────
#
# **이것이 결정 8의 심장이고 이 체인에서 가장 값진 한 줄이다.** 누른 동안 다른
# 키가 오면 "소비됨"이 켜져서 tap이 아니어야 하는데, 그것이 없으면 터미널에서
# 가장 흔한 조합인 Ctrl+C가 누를 때마다 한/영을 뒤집는다. 증상은 "가끔 한글이
# 안 쳐진다"라 원인에서 아주 멀다.
#
# **판정이 서는 이유를 적어 둔다.** Ctrl+C는 그 자체로 `hangul>` 줄을 안 만든다
# (조합 중이 아니면 `hangulLayer`가 확정할 것이 없어 null을 돌려준다). 그래서
# 여기서 읽는 값은 검사 15가 남긴 `on=true`이고, **만약 Ctrl+C가 잘못
# 전환했다면 `on=false`인 새 줄이 그 뒤에 찍혀서 갈린다.**
echo "=== ctrl-c while hangul is on ==="
type_keys ctrl-c
sleep 1
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "Ctrl+C flipped hangul to on=${ON} — the left Ctrl tap was not consumed"
fi
echo "Ctrl+C did not flip hangul: the tap was consumed"

echo "HI check PASS"
