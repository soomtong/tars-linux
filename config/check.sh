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
type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

# echo shell=zsh > /config/tars.conf
EDIT_KEYS=(e c h o spc s h e l l equal z s h spc shift-dot spc
           slash c o n f i g slash t a r s dot c o n f ret)
# cat /config/tars.conf
READBACK_KEYS=(c a t spc slash c o n f i g slash t a r s dot c o n f ret)

# 1차 부팅에서 QEMU를 죽이기 전에 하는 일: 게스트 안의 셸에 직접 타이핑해서
# 설정을 바꾼다.
edit_config_in_guest() {
  local log="$1"

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

  type_keys "${EDIT_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"

  # 되읽기 확인. dumpScreen은 화면 전체를 한 줄에 찍고 행을 " | "로 나눈다.
  # 그래서 **행의 첫머리가 shell=zsh인 것**이 cat의 출력이다 — 방금 타이핑한
  # 명령줄에도 shell=zsh가 들어 있지만 그 행은 프롬프트와 echo로 시작한다.
  #
  # 이 검사가 통과하면 "키가 게스트에 도달했고, 셸이 명령을 실행했고, 파일에
  # 써졌고, 다시 읽힌다"까지가 한꺼번에 확인된다.
  local wrote=0
  for _ in $(seq 1 30); do
    if grep -q "terminal: screen>.*| shell=zsh" "$log"; then wrote=1; break; fi
    sleep 1
  done

  exec 3<&-
  exec 3>&-

  if [ "$wrote" != "1" ]; then
    echo "FAIL(boot 1): typed the edit but /config/tars.conf never read back as shell=zsh"
    return 1
  fi
  echo "boot 1: typed the edit in the guest and read it back (shell=zsh)"
  return 0
}

# 2차 부팅에서 마커를 본 뒤 하는 일. 여기서 확인할 것 중 몇 개는 **없어야 할
# 것**(셸이 죽지 않았다)이라 관측 창이 필요하다. 부재는 폴링으로 증명할 수
# 없으므로 이 5초만 고정 대기다 — 재시작 backoff가 1초이므로 세 번 죽고 포기하는
# 데 3초면 충분하다.
watch_console_shell() {
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
echo "=== boot 1/2: empty disk, seed the config then edit it from inside the guest ==="
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

if grep -q "Attempted to kill init" "$LOG1"; then
  report_failure "$LOG1" "kernel panicked because PID 1 exited on the first boot"
fi
echo "boot 1: seeded with fish, then edited to zsh from inside the guest"

# ---------------------------------------------------------------- 2차 부팅
# 같은 이미지를 그대로 다시 물린다. make_disk.sh를 부르지 않는다.
echo "=== boot 2/2: same image, the guest-written config should pick the shell ==="
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
echo "boot 2: the config written inside the guest selected zsh for both shells"

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

echo "PASS"
exit 0
