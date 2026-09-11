#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# 빌드 순서는 TF 체인과 같다(kernel → init → terminal → initrd).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사(config.zig의 parse). terminal/check.sh가
# input_test를 부팅 앞에서 돌리는 것과 같은 자리다 — 부팅 20초를 쓰기 전에
# 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
if ! (cd ../init && zig build test); then
  echo "FAIL: config_test failed"
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

# 디스크는 매 회차 새로 굽는다. 남은 이미지를 재사용하면 "빈 디스크로 첫
# 부팅"이라는 전제가 무너지고, 1차 부팅이 검증할 seeding 경로가 다시는
# 실행되지 않은 채 게이트가 자기를 속이게 된다.
#
# 반대로 **두 부팅 사이에서는 절대 다시 부르지 않는다.** 그게 이 체인의 검증
# 그 자체다 — 1차에서 사람이 고친 것을 2차가 읽어야 한다.
if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

# TF 체인은 45455를 쓴다. 다른 번호를 쓰는 이유는 어느 한쪽이 죽다 만 QEMU를
# 남겼을 때 엉뚱한 게스트에 키를 보내지 않기 위해서다.
MONITOR_PORT=45456

LOG1="$(mktemp)"
LOG2="$(mktemp)"
LOG3="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# 게스트 셸에 한 글자씩 타이핑한다.
#
# sendkey가 보내는 것은 **문자가 아니라 키**다. 그래서 '='는 equal, '>'는
# shift-dot, '/'는 slash로 적어야 하고, 게스트 쪽에서 evdev 이벤트를 다시
# 문자로 바꾸는 것은 우리 코드다(terminal/src/input.zig의 keymap). 두 겹이 다
# 맞아야 파일에 한 줄이 써진다 — 이 게이트는 그 두 겹까지 검사하는 셈이다.
source ../gate_lib.sh

# echo shell=zsh > /config/tars.conf
EDIT_KEYS=(e c h o spc s h e l l equal z s h spc shift-dot spc
           slash c o n f i g slash t a r s dot c o n f ret)
# cat /config/tars.conf
READBACK_KEYS=(c a t spc slash c o n f i g slash t a r s dot c o n f ret)

# ── SC-M1 ───────────────────────────────────────────────────────────────
# tars-config — **씨앗이 정의한 alias다.** 이 한 명령이 셋을 동시에 본다:
#   1. /config/fish.config가 생겼다
#   2. fish가 그것을 읽었다(안 읽었으면 모르는 명령이다)
#   3. 씨앗 tars.conf가 실제로 shell_config=on을 담고 있다
# SC-M0의 게이트는 로그에서 **기본값**만 봤고 파일의 내용은 못 봤다.
ALIAS_KEYS=(t a r s minus c o n f i g ret)
# echo echo tars-rc-alive >> /config/zshrc
#
# **판정 글자를 사람이 심는 자리다.** 씨앗에는 echo를 넣을 수 없다 — 설정
# 디스크를 붙이는 다섯 체인의 화면 좌표가 밀린다. 그래서 "rc가 읽혔다"를
# 말해 줄 글자는 게이트가 타이핑한다(design 결정 10의 "사람이 줄을 더한다").
#
# >> 는 shift-dot 둘이다. 씨앗을 덮어쓰지 않는 것이 요점이다 — 2차 부팅이
# 읽는 파일은 **씨앗 + 사람이 더한 줄**이어야 한다.
APPEND_KEYS=(e c h o spc e c h o spc t a r s minus r c minus a l i v e spc
             shift-dot shift-dot spc slash c o n f i g slash z s h r c ret)
# grep alive /config/zshrc — 더한 줄이 파일에 들어갔는지 되읽는다.
# cat이 아니라 grep인 이유는 출력이 한 줄이어야 하기 때문이다. 씨앗은
# 열몇 줄이고, UT-M3이 배운 대로 **긴 출력의 첫 줄은 프레임에 안 남는다.**
RC_READBACK_KEYS=(g r e p spc a l i v e spc slash c o n f i g slash z s h r c ret)
# echo shell_config=off >> /config/tars.conf — 2차 부팅에서 친다.
# 밑줄은 shift-minus다(design 실측 14(f)에서 게스트에 닿는 것을 확인했다).
OFF_KEYS=(e c h o spc s h e l l shift-minus c o n f i g equal o f f spc
          shift-dot shift-dot spc slash c o n f i g slash t a r s dot c o n f ret)

# 1차 부팅에서 QEMU를 죽이기 전에 하는 일: 게스트 안의 셸에 직접 타이핑해서
# 설정을 바꾼다.
edit_config_in_guest() {
  local log="$1"

  # type_keys가 보는 것은 전역 $LOG다. 이 체인은 부팅이 둘이라 로그를 인자로
  # 받는 구조인데, 그 둘을 잇는 자리가 여기다. local로 선언하지 않는 것이
  # 요점이다 — 함수 안에서만 살아 있으면 type_keys가 못 본다.
  LOG="$log"

  # 프롬프트가 그려진 뒤에 쳐야 한다. "terminal: screen>" 첫 줄이 곧 DRM 열기 +
  # 폰트 래스터라이즈 + evdev 열기 + 셸 spawn + 첫 렌더가 전부 끝났다는
  # 신호다(TF 체인과 같은 신호를 쓴다).
  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 1): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi
  sleep 1

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 1): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  # ── SC-M1: 씨앗을 먼저 묻는다 ────────────────────────────────────────
  #
  # **고치기 전에 묻는 것이 순서다.** 아래 EDIT_KEYS가 tars.conf를 한 줄로
  # 덮어쓰므로, 씨앗 파일의 내용을 볼 수 있는 것은 지금뿐이다.
  #
  # dumpScreen은 화면 전체를 한 줄에 찍고 행을 " | "로 나눈다. 그래서
  # **행의 첫머리**를 보는 것이 출력이고, 방금 타이핑한 명령줄은 프롬프트로
  # 시작하므로 안 걸린다 — 이 파일이 아래에서 오래 쓰고 있는 수법이다.
  type_keys "${ALIAS_KEYS[@]}"
  if ! wait_for_screen '\| shell_config=on'; then
    echo "FAIL(boot 1): 'tars-config' never printed the seeded config"
    echo "  둘 중 하나다 — 씨앗 /config/fish.config가 안 생겼거나, 생겼는데"
    echo "  fish가 그것을 안 읽었다. 아래 마지막 화면에 'Unknown command'가"
    echo "  있으면 후자다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: the seeded fish.config defined tars-config, and it printed shell_config=on"

  type_keys "${EDIT_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"

  # 되읽기 확인. 위와 같은 수법이다 — **행의 첫머리가 shell=zsh인 것**이
  # cat의 출력이고, 방금 타이핑한 명령줄에도 shell=zsh가 들어 있지만 그 행은
  # 프롬프트와 echo로 시작한다.
  #
  # 이 검사가 통과하면 "키가 게스트에 도달했고, 셸이 명령을 실행했고, 파일에
  # 써졌고, 다시 읽힌다"까지가 한꺼번에 확인된다.
  if ! wait_for_screen '\| shell=zsh'; then
    echo "FAIL(boot 1): typed the edit but /config/tars.conf never read back as shell=zsh"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: typed the edit in the guest and read it back (shell=zsh)"

  # ── SC-M1: 2차·3차가 볼 글자를 심는다 ────────────────────────────────
  type_keys "${APPEND_KEYS[@]}"
  type_keys "${RC_READBACK_KEYS[@]}"
  if ! wait_for_screen '\| echo tars-rc-alive'; then
    echo "FAIL(boot 1): the line appended to /config/zshrc did not read back"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 1: appended a marker line to the seeded /config/zshrc"

  exec 3<&-
  exec 3>&-
  return 0
}

# 2차 부팅에서 마커를 본 뒤 하는 일. 둘이다.
#
#   1. **관측 창** — 여기서 확인할 것 중 몇 개는 **없어야 할 것**(셸이 죽지
#      않았다)이라 시간이 필요하다. 부재는 폴링으로 증명할 수 없으므로 이
#      5초만 고정 대기다 — 재시작 backoff가 1초이므로 세 번 죽고 포기하는
#      데 3초면 충분하다.
#   2. **3차 부팅이 읽을 설정을 심는다**(SC-M1) — tars.conf에
#      shell_config=off 한 줄을 **더한다.** 1차에서 사람이 친 shell=zsh는
#      그대로 남아야 한다: 3차의 부정 검사는 "같은 셸이 같은 rc를 안 읽는다"
#      여야 하고, 셸까지 바뀌면 무엇 때문에 안 읽혔는지 갈리지 않는다.
#
# **이 부팅의 셸은 zsh다.** 프롬프트가 fish의 `root@(none) ~#`가 아니라
# `(none)#`이지만(design 실측 14(e)) 타이핑하는 쪽은 그것을 안 봐도 된다 —
# 판정은 전부 출력의 행 첫머리로 한다.
watch_console_shell() {
  local log="$1"
  LOG="$log"

  sleep 5

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 2): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 2): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  type_keys "${OFF_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"

  local ok=0
  if wait_for_screen '\| shell_config=off'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 2): typed shell_config=off but /config/tars.conf never read it back"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 2: appended shell_config=off to the config for the third boot"
  return 0
}

# 3차 부팅의 훅. **타이핑을 안 하므로 관측 창만 있다.** 2차가 쓰는 함수를
# 그대로 쓸 수 없는 이유는 그쪽이 설정을 고치기 때문이다 — 3차가 그것을
# 부르면 tars.conf에 off가 한 줄 더 붙는다(해롭진 않지만 거짓말이 된다).
watch_console_shell_quiet() {
  sleep 5
  return 0
}

# 부팅 한 번. $1 = 시리얼 로그 파일, $2 = 기다릴 마커, $3 = (선택) 마커를 본 뒤
# QEMU를 죽이기 전에 부를 함수.
boot_once() {
  local log="$1"
  local marker="$2"
  local hook="${3:-}"

  qemu-system-x86_64 \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -drive file="${REPO_ROOT}/out/config.img",if=virtio,format=raw \
    -display none \
    -serial file:"$log" \
    -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
    -no-reboot &
  QEMU_PID=$!

  # 고정 sleep 대신 로그 폴링. 마커가 나오면 즉시 다음으로 간다.
  local found=0
  for _ in $(seq 1 120); do
    if grep -q "$marker" "$log"; then
      found=1
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  local hook_ok=1
  if [ "$found" = "1" ] && [ -n "$hook" ]; then
    "$hook" "$log" || hook_ok=0
  fi

  # 마커를 봤든 못 봤든 여기서 QEMU를 확실히 끝낸다. wait까지 하는 이유는
  # 다음 부팅이 **같은 디스크 이미지**를 열기 때문이다 — 두 QEMU가 같은
  # 이미지를 동시에 쓰면 파일시스템이 깨지고, 그 실패는 이 체인이 검증하려는
  # 것과 구분이 안 되는 모양으로 나타난다.
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""

  [ "$found" = "1" ] && [ "$hook_ok" = "1" ]
}

# 실패했을 때 "어디까지 갔는가"를 보여준다. 마커 하나하나가 부팅의 단계다.
report_failure() {
  local log="$1"
  local msg="$2"
  echo "FAIL: ${msg}"
  echo "--- markers ---"
  local marker
  for marker in \
    "\[vda\]" \
    "tars-init: mounted ext2 at /config" \
    "tars-init: failed to mount ext2 at /config" \
    "tars-init: created /config/tars.conf" \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: config shell=" \
    "tars-init: started console shell" \
    "tars-init: shell .* is not executable" \
    "terminal: spawned child pid" \
    "terminal: screen>"; do
    if grep -q "$marker" "$log"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- tail ---"
  tail -n 60 "$log"
  exit 1
}

# ---------------------------------------------------------------- 1차 부팅
# 빈 디스크. init이 씨앗을 심고(fish), 그 다음 사람이 zsh로 고친다.
echo "=== boot 1/3: empty disk, seed the config and the rc files, then edit them from inside ==="
if ! boot_once "$LOG1" "tars-init: created /config/tars.conf" edit_config_in_guest; then
  report_failure "$LOG1" "first boot did not seed and edit /config/tars.conf"
fi

if ! grep -q "\[vda\]" "$LOG1"; then
  report_failure "$LOG1" "kernel never reported a [vda] block device on the first boot"
fi

# 빈 디스크였는데 loaded가 나왔다면 make_disk.sh가 안 돌았거나 이전 회차의
# 이미지가 남아 있는 것이다.
if grep -q "tars-init: loaded /config/tars.conf" "$LOG1"; then
  report_failure "$LOG1" "first boot loaded an existing config; the disk was not empty"
fi

# 씨앗은 언제나 기본값이다. 1차 부팅의 셸은 아직 fish여야 한다 — 여기가
# zsh였다면 디스크가 비어 있지 않았다는 뜻이다.
if ! grep -q "tars-init: config shell=fish" "$LOG1"; then
  report_failure "$LOG1" "first boot did not start from the default (fish)"
fi

# SC-M0. **같은 줄을 넓혀서 본다** — 새 줄을 안 만든 이유는 이 파일과
# 다른 체인들이 `tars-init: config shell=`을 앞부분으로 grep하고 있기
# 때문이다(main.zig의 그 자리 주석이 HI-M2에 대해 같은 것을 적고 있다).
#
# **여기가 게이트에서 기본값을 보는 유일한 자리다.** 씨앗 파일이 실제로
# `shell_config=on`을 담았다는 것은 SC-M1이 2차 부팅으로 본다 — 이 검사가
# 보는 것은 **파서가 그 키를 알고, 기본값이 on이라는 것**까지다.
if ! grep -q "tars-init: config shell=fish.*shell_config=on" "$LOG1"; then
  report_failure "$LOG1" "first boot did not report the default shell_config=on"
fi
echo "boot 1: init reported shell_config=on (the sixth key reached the log)"

# SC-M1 결정 7. **씨앗 셋이 로그에 한 줄씩 남는다.** 화면으로 보는 것은
# fish의 것 하나뿐이고(1차 부팅의 셸이 fish다) 나머지 둘은 이 줄이 전부다 —
# bash·zsh의 씨앗이 **읽히는지**는 이 milestone이 zsh에 대해서만 본다.
for rc in /config/bashrc /config/zshrc /config/fish.config; do
  if ! grep -q "tars-init: seeded ${rc}" "$LOG1"; then
    report_failure "$LOG1" "first boot did not seed ${rc}"
  fi
done
echo "boot 1: init seeded all three rc files on the empty disk"

if grep -q "Attempted to kill init" "$LOG1"; then
  report_failure "$LOG1" "kernel panicked because PID 1 exited on the first boot"
fi
echo "boot 1: seeded with fish, then edited to zsh from inside the guest"

# ---------------------------------------------------------------- 2차 부팅
# 같은 이미지를 그대로 다시 물린다. make_disk.sh를 부르지 않는다.
echo "=== boot 2/3: same image, the guest-written config should pick the shell and its rc ==="
if ! boot_once "$LOG2" "tars-init: started console shell" watch_console_shell; then
  report_failure "$LOG2" "second boot never started a console shell"
fi

if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG2"; then
  report_failure "$LOG2" "second boot did not load /config/tars.conf"
fi

# 1차가 쓴 파일이 살아남았는지. CP-M1부터 이 게이트의 핵심인 부정 검사다.
if grep -q "tars-init: created /config/tars.conf" "$LOG2"; then
  report_failure "$LOG2" "second boot re-created the config file; nothing persisted"
fi

# ★ CP-M2가 증명하려는 것. 파일을 읽었다 → 값이 파싱됐다 → 그 값이 실제로
#   exec된 바이너리를 바꿨다. 세 줄이 각각 그 세 단계다.
if ! grep -q "tars-init: config shell=zsh" "$LOG2"; then
  report_failure "$LOG2" "second boot did not parse shell=zsh out of the config file"
fi

if ! grep -q "tars-init: started console shell (pid .*, /usr/bin/zsh)" "$LOG2"; then
  report_failure "$LOG2" "second boot parsed zsh but did not exec /usr/bin/zsh"
fi

if ! grep -q "terminal: spawned child pid .*(/usr/bin/zsh)" "$LOG2"; then
  report_failure "$LOG2" "the terminal did not spawn zsh in its PTY"
fi

# 폴백이 발동했다면 initrd에 zsh가 안 들어간 것이다. 부팅은 계속되므로 위
# 검사만으로는 원인이 안 보인다 — 이 줄이 그 자리를 가리킨다.
if grep -q "tars-init: shell .* is not executable" "$LOG2"; then
  report_failure "$LOG2" "the configured shell was missing from the initrd (init fell back)"
fi

if grep -q "tars-init: execve /usr/bin/zsh failed" "$LOG2"; then
  report_failure "$LOG2" "execve of /usr/bin/zsh failed (missing loader or library?)"
fi

# zsh가 떴다가 바로 죽는 경우. terminfo가 없어 zle가 깨지는 상황이 여기로 온다.
if grep -q "tars-init: giving up on console shell" "$LOG2"; then
  report_failure "$LOG2" "the console shell kept dying; init gave up on it"
fi

# 시리얼 콘솔이 정말 fish가 아닌지. 화면 덤프(terminal: screen>) 안의 문자열은
# 터미널이 렌더링한 픽셀의 텍스트일 뿐이라 제외한다.
if grep "Welcome to fish, the friendly interactive shell" "$LOG2" | grep -qv "terminal: screen>"; then
  report_failure "$LOG2" "the serial console still ran fish on the second boot"
fi

if grep -q "Attempted to kill init" "$LOG2"; then
  report_failure "$LOG2" "kernel panicked because PID 1 exited on the second boot"
fi
# ── SC-M1: 이 milestone이 증명하려는 것 ─────────────────────────────────
#
# 1차에서 사람이 /config/zshrc에 더한 `echo tars-rc-alive` 한 줄이 이 부팅의
# 셸에서 실행됐는가. **씨앗을 덮어쓰지 않고 더한 줄이므로, 이 글자가 보이면
# 씨앗 파일 자체가 읽혔다는 뜻이기도 하다.**
#
# **두 자리를 따로 본다**(결정 4).
#
#   terminal: screen> 가 아닌 줄  →  시리얼 콘솔 셸. init이 직접 exec했다
#   terminal: screen> 인 줄        →  화면 셸. terminal이 PTY에 띄웠다
#
# 아래 "시리얼 콘솔이 정말 fish가 아닌지"가 이미 같은 구분을 쓰고 있다.
# 콘솔 셸에는 타이핑을 못 하지만(체인이 -serial file:, 쓰기 전용)
# **그 셸이 스스로 찍는 것은 읽을 수 있다.**
if ! grep "tars-rc-alive" "$LOG2" | grep -qv "terminal: screen>"; then
  report_failure "$LOG2" "the serial console shell never ran the line the user added to /config/zshrc"
fi
if ! grep -a "terminal: screen>" "$LOG2" | grep -q "tars-rc-alive"; then
  report_failure "$LOG2" "the screen shell never ran the line the user added to /config/zshrc"
fi
echo "boot 2: both shells read /config/zshrc (the user's line ran twice)"

# 씨앗은 한 번만 깐다. 이 부정 검사가 없으면 "매 부팅 덮어쓴다"와 구분이
# 안 되고, 그러면 사용자가 rc에 쓴 것이 조용히 사라진다 — 위에서 tars.conf에
# 대해 CP-M1부터 갖고 있는 검사와 같은 자리다.
if grep -q "tars-init: seeded /config/" "$LOG2"; then
  report_failure "$LOG2" "second boot re-seeded an rc file; the user's edits would be gone"
fi
echo "boot 2: init left the existing rc files alone"

echo "boot 2: the config written inside the guest selected zsh for both shells"

# ---------------------------------------------------------------- 3차 부팅
# 또 같은 이미지다. 2차가 tars.conf에 shell_config=off를 더해 두었다.
#
# **이 부팅은 아무것도 안 친다.** 볼 것이 전부 **없어야 할 것**이기 때문이다 —
# 타이핑을 하면 그 글자가 화면에 남고, 판정 글자가 우연히 화면에 생기는 길이
# 하나 늘어난다.
echo "=== boot 3/3: same image with shell_config=off, the rc must not run ==="
if ! boot_once "$LOG3" "tars-init: started console shell" watch_console_shell_quiet; then
  report_failure "$LOG3" "third boot never started a console shell"
fi

# 먼저 이 부팅이 **2차와 같은 기계인지** 확인한다. 아래 부정 검사는 "안
# 보인다"로 판정하므로, 기계가 애초에 안 떴어도 통과한다 — 그 구멍을
# 막는 것이 이 네 줄이다.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG3"; then
  report_failure "$LOG3" "third boot did not load /config/tars.conf"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=off" "$LOG3"; then
  report_failure "$LOG3" "third boot did not parse the shell_config=off the second boot appended"
fi
if ! grep -q "tars-init: started console shell (pid .*, /usr/bin/zsh)" "$LOG3"; then
  report_failure "$LOG3" "third boot did not exec /usr/bin/zsh on the serial console"
fi
if ! grep -q "terminal: screen>" "$LOG3"; then
  report_failure "$LOG3" "the terminal never rendered on the third boot; the negative check would be vacuous"
fi

# ★ SC-M1이 증명하려는 나머지 절반. **같은 디스크, 같은 셸, 같은 rc 파일인데
#   한 줄이 바뀌어서 안 읽힌다.** 2차와 3차 사이에 달라진 것은 tars.conf의
#   마지막 줄 하나뿐이다.
if grep -q "tars-rc-alive" "$LOG3"; then
  report_failure "$LOG3" "shell_config=off did not stop the shells from reading /config/zshrc"
fi
echo "boot 3: shell_config=off kept both shells out of the rc that boot 2 ran"

if grep -q "tars-init: giving up on console shell" "$LOG3"; then
  report_failure "$LOG3" "the console shell kept dying on the third boot"
fi
if grep -q "Attempted to kill init" "$LOG3"; then
  report_failure "$LOG3" "kernel panicked because PID 1 exited on the third boot"
fi

# 정보성. ext2가 "not clean"이라고 말하는 것은 예상된 결과다(1차를 kill했다).
if grep -q "mounting unchecked fs" "$LOG2"; then
  echo "note: ext2 reported an unclean superblock on boot 2 (expected: boot 1 was killed)"
fi

# 성공해도 시리얼 로그의 init 줄은 남긴다. 루트 게이트가 만드는 통합 로그에서
# 이 체인이 무엇을 봤는지 나중에 확인할 수 있어야 한다.
echo "--- init log (boot 1) ---"
grep 'tars-init:' "$LOG1" || true
echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG2" || true
echo "--- init log (boot 3) ---"
grep 'tars-init:' "$LOG3" || true

echo "PASS"
exit 0
