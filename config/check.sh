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
# 반대로 두 부팅 사이에서는 절대 다시 부르지 않는다. 그게 이 체인의 검증
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
# sendkey가 보내는 것은 문자가 아니라 키다. 그래서 '='는 equal, '>'는
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
# tars-config — 씨앗이 정의한 alias다. 이 한 명령이 셋을 동시에 본다:
#   1. /config/fish.config가 생겼다
#   2. fish가 그것을 읽었다(안 읽었으면 모르는 명령이다)
#   3. 씨앗 tars.conf가 실제로 shell_config=on을 담고 있다
# SC-M0의 게이트는 로그에서 기본값만 봤고 파일의 내용은 못 봤다.
ALIAS_KEYS=(t a r s minus c o n f i g ret)
# echo echo tars-rc-alive >> /config/zshrc
#
# 판정 글자를 사람이 심는 자리다. 씨앗에는 echo를 넣을 수 없다 — 설정
# 디스크를 붙이는 다섯 체인의 화면 좌표가 밀린다. 그래서 "rc가 읽혔다"를
# 말해 줄 글자는 게이트가 타이핑한다(design 결정 10의 "사람이 줄을 더한다").
#
# >> 는 shift-dot 둘이다. 씨앗을 덮어쓰지 않는 것이 요점이다 — 2차 부팅이
# 읽는 파일은 씨앗 + 사람이 더한 줄이어야 한다.
APPEND_KEYS=(e c h o spc e c h o spc t a r s minus r c minus a l i v e spc
             shift-dot shift-dot spc slash c o n f i g slash z s h r c ret)
# grep alive /config/zshrc — 더한 줄이 파일에 들어갔는지 되읽는다.
# cat이 아니라 grep인 이유는 출력이 한 줄이어야 하기 때문이다. 씨앗은
# 열몇 줄이고, UT-M3이 배운 대로 긴 출력의 첫 줄은 프레임에 안 남는다.
RC_READBACK_KEYS=(g r e p spc a l i v e spc slash c o n f i g slash z s h r c ret)
# echo shell_config=off >> /config/tars.conf — 2차 부팅에서 친다.
# 밑줄은 shift-minus다(design 실측 14(f)에서 게스트에 닿는 것을 확인했다).
OFF_KEYS=(e c h o spc s h e l l shift-minus c o n f i g equal o f f spc
          shift-dot shift-dot spc slash c o n f i g slash t a r s dot c o n f ret)

# ── SC-M2 ───────────────────────────────────────────────────────────────
# echo exit >> /config/zshrc — 3차 부팅에서 친다. 일부러 죽는 rc다.
# 이 한 줄이 셸을 rc 처리 도중에 끝내므로 셸은 프롬프트를 그리기 전에 죽는다.
BREAK_KEYS=(e c h o spc e x i t spc shift-dot shift-dot spc
            slash c o n f i g slash z s h r c ret)
# grep exit /config/zshrc — 되읽기.
#
# cat이 아니라 grep인 이유가 둘이다. 하나는 M1의 이유 그대로(씨앗이 열몇
# 줄이라 긴 출력의 첫 줄이 프레임에 안 남는다), 다른 하나는 이 부팅이 부정
# 검사를 갖고 있다는 것이다 — cat하면 `echo tars-rc-alive`가 화면에 뜨고
# 3차의 판정이 그것을 보게 된다. 화면에 안 띄우는 것이 요점이다.
BREAK_READBACK_KEYS=(g r e p spc e x i t spc slash c o n f i g slash z s h r c ret)
# echo shell_config=on >> /config/tars.conf — 2차가 쓴 off를 되돌린다.
# 마지막 줄이 이긴다(config_test.zig가 그 규칙을 못 박고 있다).
ON_KEYS=(e c h o spc s h e l l shift-minus c o n f i g equal o n spc
         shift-dot shift-dot spc slash c o n f i g slash t a r s dot c o n f ret)

# ── SM-M1 ───────────────────────────────────────────────────────────────
#
# 6차 부팅은 수리만 한다. 3차가 심은 `exit`가 아직 `/config/zshrc`에
# 있어서, 그 파일을 읽는 부팅은 셸이 죽고 탈출로가 rc 없이 되살린다 —
# 훅도 함께 안 걸린다. 훅을 보려면 먼저 그 줄을 없애야 한다.
#
# 한 줄만 지우지 않고 파일을 통째로 지운다. 이유가 셋이다.
#   1. 7차의 rc가 정확히 우리 씨앗이 된다 — 1차에서 사람이 더한
#      `echo tars-rc-alive`도 없다. 증명 대상이 `rcSeed()`의 내용 그 자체다.
#   2. `seedRcFiles`의 `O_EXCL`이 "없으면 만든다"를 빈 디스크가 아닌
#      자리에서 다시 증명한다. 셋 중 하나만 지웠으니 7차의 `seeded`도
#      하나여야 한다 — 그것이 `O_EXCL`의 정확한 계약이다.
#   3. 타이핑이 두 명령으로 끝난다.
RM_RC_KEYS=(r m spc slash c o n f i g slash z s h r c ret)
# ls /config/zshrc — 되읽기. 판정 글자는 ls가 만든다(`No such file`).
# 타이핑한 줄에는 그 글자가 없다 — 이 체인의 오래된 규칙이다.
RM_READBACK_KEYS=(l s spc slash c o n f i g slash z s h r c ret)

# ── 7차 부팅이 치는 넷 ──────────────────────────────────────────────────
#
# design 결정 8의 시퀀스가 여기서 바뀌었다. design은 `cd /tmp` → `cd /` →
# `z tmp` → `pwd`로 `/tmp`을 보라고 적었는데, `/tmp`은 방금 타이핑한
# `cd /tmp`에 들어 있다 — 훅이 죽어도 초록인 검사다(M0이 세 번 밟은 함정).
#
# 처방은 M0의 것 그대로다. `..`를 지나는 경로를 `cd`하면 셸이 `$PWD`를
# 정규화하고 훅이 그 정규형을 DB에 넣는다. 화면에 남는 타이핑은 `..`가 든
# 쪽이고, `/usr/share/terminfo/x`를 만든 주체는 DB뿐이다.
#
# `tools/check.sh` 검사 18과 판정 글자가 같은 것에 뜻이 있다. 그 검사는
# 사람이 `zoxide add`를 쳤고 이쪽은 아무도 안 친다. 둘의 차이가 훅이다.
HOOK_CD_KEYS=(c d spc slash u s r slash b i n slash dot dot slash
              s h a r e slash t e r m i n f o slash x ret)
HOOK_HOME_KEYS=(c d spc slash ret)
HOOK_Z_KEYS=(z spc t e r m i n f o spc x ret)
HOOK_PWD_KEYS=(p w d ret)
# whence -w fzf-history-widget — fzf 통합이 위젯을 정의했다는 것을
# `Ctrl+R`을 안 치고 보는 법(design 비목표 2 — 셋 다 TUI라 게이트가 치면
# 체인이 매달린다).
#
# 판정 글자가 `widget`이 아니라 `function`이다(SM-M1 실측 24). `zle -N`로
# 위젯이 되지만 `whence -w`가 보는 것은 그 이름의 함수다. design 결정 8이
# 명령만 적고 출력을 안 적어서 실측으로 정했다.
#
# 치는 것이 전부 소문자다 — `sendkey`에 대문자가 없다(UT-M3).
HOOK_WIDGET_KEYS=(w h e n c e spc minus w spc
                  f z f minus h i s t o r y minus w i d g e t ret)

# ── SM-M2 ───────────────────────────────────────────────────────────────
#
# 게이트는 전원을 뽑는다. boot_once가 마커를 보면 `kill "$QEMU_PID"`로
# 기계를 끝내므로 셸이 나갈 때 하는 일이 하나도 안 일어난다. zsh는
# SIGTERM·SIGHUP을 받으면 HISTFILE을 쓰지만(실측 34) QEMU가 죽으면 그 신호도
# 안 온다 — 실기의 전원 버튼에서는 저장되고, 여기서만 안 된다.
#
# 그래서 7차가 직접 쓴다. `fc -W`는 히스토리 목록을 그 자리에서 파일에 쓴다.
#
# ⚠ 이 저장소가 대문자를 처음 친다. `sendkey`에 대문자 키 이름은 없지만
# `shift-w`는 있고, 게스트의 keymap이 `.{ 'w', 'W' }`를 갖고 있다
# (`terminal/src/input.zig:47`). 안 먹으면 화면에 `fc: bad option`이 뜨고 바로
# 아래 되읽기가 빨개진다 — 실패가 그 자리에서 보인다.
HIST_WRITE_KEYS=(f c spc minus shift-w ret)
# wc -l /config/zsh_history — 되읽기. 판정 글자는 wc가 만드는 숫자다.
# GNU wc는 파일이 하나면 앞에 공백을 안 넣으므로(실측 35) 행의 첫머리가
# 숫자인 줄은 이 출력뿐이고, 방금 타이핑한 줄은 프롬프트로 시작한다.
# 밑줄은 shift-minus다(OFF_KEYS가 쓰고 있는 그 키다).
HIST_COUNT_KEYS=(w c spc minus l spc slash c o n f i g slash
                 z s h shift-minus h i s t o r y ret)

# ── 8차 부팅이 치는 셋 ──────────────────────────────────────────────────
#
# `z`와 `pwd`는 7차의 것을 그대로 다시 쓴다(HOOK_Z_KEYS · HOOK_PWD_KEYS).
# 같은 두 명령이 두 부팅에서 다른 것을 증명한다 — 7차에서는 "훅이 걸렸다"를,
# 8차에서는 "그 기억이 전원을 넘었다"를. 8차는 `cd`를 한 번도 안 친다.
#
# ls /config/xdg/zoxide — 그 기억이 tmpfs의 홈이 아니라 설정 디스크에
# 있다는 것을 보는 한 줄. 판정 글자 `db.zo`는 타이핑한 줄에 없다(실측 38).
XDG_LS_KEYS=(l s spc slash c o n f i g slash x d g slash z o x i d e ret)
# history — zsh는 인자 없이 부르면 최근 16개를 번호와 함께 찍는다(실측 36).
HISTORY_KEYS=(h i s t o r y ret)

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
  # 고치기 전에 묻는 것이 순서다. 아래 EDIT_KEYS가 tars.conf를 한 줄로
  # 덮어쓰므로, 씨앗 파일의 내용을 볼 수 있는 것은 지금뿐이다.
  #
  # dumpScreen은 화면 전체를 한 줄에 찍고 행을 " | "로 나눈다. 그래서
  # 행의 첫머리를 보는 것이 출력이고, 방금 타이핑한 명령줄은 프롬프트로
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

  # 되읽기 확인. 위와 같은 수법이다 — 행의 첫머리가 shell=zsh인 것이
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
#   1. 관측 창 — 여기서 확인할 것 중 몇 개는 없어야 할 것(셸이 죽지
#      않았다)이라 시간이 필요하다. 부재는 폴링으로 증명할 수 없으므로 이
#      5초만 고정 대기다 — 재시작 backoff가 1초이므로 세 번 죽고 포기하는
#      데 3초면 충분하다.
#   2. 3차 부팅이 읽을 설정을 심는다(SC-M1) — tars.conf에
#      shell_config=off 한 줄을 더한다. 1차에서 사람이 친 shell=zsh는
#      그대로 남아야 한다: 3차의 부정 검사는 "같은 셸이 같은 rc를 안 읽는다"
#      여야 하고, 셸까지 바뀌면 무엇 때문에 안 읽혔는지 갈리지 않는다.
#
# 이 부팅의 셸은 zsh다. 프롬프트가 fish의 `root@(none) ~#`가 아니라
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

# 3차 부팅의 훅. 관측 창 + 4차가 밟을 함정을 판다(SC-M2).
#
# M1까지 이 부팅은 아무것도 안 쳤다. 이유는 *"타이핑을 하면 그 글자가 화면에
# 남고, 판정 글자가 우연히 화면에 생기는 길이 하나 늘어난다"*였고 그 이유는
# 그대로 산다. 그래서 여기서 치는 두 명령과 그 되읽기에 `tars-rc-alive`가
# 한 글자도 안 들어간다(위 BREAK_READBACK_KEYS의 주석).
#
# 심는 것 둘:
#   1. `/config/zshrc` 끝에 `exit` — 일부러 죽는 rc다.
#   2. `tars.conf`에 `shell_config=on` — 2차가 쓴 off를 되돌린다.
#
# 이 부팅은 안 다친다. 여기 셸은 off라 rc를 안 읽으므로 함정을 파도 밟지
# 않는다. 4차부터 밟는다.
plant_broken_rc() {
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
    echo "FAIL(boot 3): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 3): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  type_keys "${BREAK_KEYS[@]}"
  type_keys "${BREAK_READBACK_KEYS[@]}"
  local ok=0
  if wait_for_screen '\| exit'; then ok=1; fi
  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 3): the exit line never landed in /config/zshrc; boot 4 would have no trap to spring"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 3: planted a shell-killing 'exit' in /config/zshrc for the fourth boot"

  type_keys "${ON_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"
  ok=0
  if wait_for_screen '\| shell_config=on'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 3): typed shell_config=on but /config/tars.conf never read it back"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 3: turned shell_config back on so the fourth boot walks into that trap"
  return 0
}

# 4차 부팅의 훅. 타이핑은 없고 기다리는 것이 둘이다.
#
#   1. terminal의 탈출로는 콘솔 셸의 것보다 늦게 온다 — 콘솔 셸은 죽는 데
#      0초가 걸리고 terminal은 DRM을 열고 폰트를 굽고 나서 셸을 띄우므로 한
#      바퀴가 몇 초다. 부팅의 마커가 빠른 쪽(콘솔 셸)이라 느린 쪽을 여기서
#      기다린다.
#   2. 되살아난 둘이 그대로 사는지 본다. 확인할 것이 "없어야 할 것"(더
#      이상의 재시작·포기)이라 부재를 폴링으로 증명할 수 없다 — 2차 부팅의
#      5초와 같은 이유의 고정 대기이고, 재시작 backoff 1초에 terminal의 기동
#      몇 초를 더해 넉넉히 잡았다.
watch_rescue() {
  local log="$1"

  local seen=0
  for _ in $(seq 1 60); do
    if grep -q "tars-init: terminal died" "$log"; then seen=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$seen" != "1" ]; then
    echo "FAIL(boot 4): the console shell was rescued but the terminal never was"
    return 1
  fi

  sleep 8
  return 0
}

# 5차 부팅의 훅. M1의 3차와 같은 자리다 — 볼 것이 전부 "없어야 할 것"이라
# 타이핑을 안 하고 관측 창만 둔다.
#
# ⚠ 여기에 타이핑을 더하지 말 것. SM-M1이 rc 수리를 6차 부팅으로 따로
# 뽑은 이유가 이 함수다 — 수리를 여기 얹으면 SC-M2의 증명(아무도 안 죽는다)과
# SM-M1의 준비(깨진 rc를 지운다)가 한 함수에서 엉키고, 5차의 부정 검사가
# 화면에 생긴 글자에 걸릴 길이 하나 늘어난다.
watch_quiet() {
  sleep 8
  return 0
}

# 6차 부팅의 훅. 수리만 한다(SM-M1).
#
# 이 부팅의 셸은 `tars.noconfig`로 떠서 rc를 안 읽는다 — 그래서 3차가 심은
# `exit`를 밟지 않고, 그 파일을 지울 수 있다. SC-M2가 그 토큰을 만든 근거가
# 정확히 이것이었다(*"설정을 고칠 셸이 없을 때 쓰는 것"*). 게이트가 자기
# 탈출로를 실제로 그 용도로 쓰는 첫 자리다.
repair_broken_rc() {
  local log="$1"
  LOG="$log"

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 6): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 6): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  type_keys "${RM_RC_KEYS[@]}"
  type_keys "${RM_READBACK_KEYS[@]}"

  local ok=0
  if wait_for_screen "No such file"; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 6): /config/zshrc is still there; the seventh boot would read the broken rc"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 6: removed the rc the third boot broke, so the seventh boot gets a fresh seed"
  return 0
}

# 7차 부팅의 훅. 이 milestone이 증명하려는 것 전부가 여기 있다(SM-M1).
#
# 이 부팅의 `/config/zshrc`는 init이 방금 다시 깐 씨앗이다(6차가 지웠다).
# 사람이 손댄 줄이 한 줄도 없으므로 증명 대상이 `rcSeed()`의 내용 그
# 자체다.
#
# 판정 둘이 서로 독립이다 — 하나가 죽어도 다른 하나는 초록이어야 하고,
# SM-M1의 되돌림 C·D가 그것을 한 번씩 실제로 깨뜨려 봤다.
#
#   1. `z`가 돈다      → zoxide 훅이 `chpwd`에 걸렸다
#   2. 위젯이 있다      → fzf 통합이 돌았다
probe_shell_hooks() {
  local log="$1"
  LOG="$log"

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 7): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 7): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  # `cd` 뒤에 `pwd`를 넣지 않는다. 넣으면 판정 글자가 `z`보다 먼저 화면에
  # 생기고, 그때부터 이 검사는 zoxide가 죽어도 초록이다.
  type_keys "${HOOK_CD_KEYS[@]}"
  type_keys "${HOOK_HOME_KEYS[@]}"
  type_keys "${HOOK_Z_KEYS[@]}"
  type_keys "${HOOK_PWD_KEYS[@]}"

  # 행의 첫머리가 그 경로인 것이 `pwd`의 출력이다. 타이핑한 줄은 프롬프트로
  # 시작하므로 안 걸린다 — 이 파일이 오래 쓰고 있는 수법이고, 여기서는 `..`가
  # 든 경로와 정규형이 애초에 다른 글자라 belt가 둘이다.
  if ! wait_for_screen '\| /usr/share/terminfo/x'; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 7): nobody typed 'zoxide add', and z did not walk back to the directory the cd should have taught"
    echo "  셋 중 하나다 — 씨앗의 훅 줄이 안 돌았거나(rc를 안 읽었다),"
    echo "  zoxide가 없거나, cd가 실패했다. 아래 마지막 화면에 'command not"
    echo "  found'가 있으면 둘째다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: nobody typed 'zoxide add' — the cd hook learned the directory and z walked back to it"

  type_keys "${HOOK_WIDGET_KEYS[@]}"
  local ok=0
  if wait_for_screen '\| fzf-history-widget: function'; then ok=1; fi

  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 7): the fzf integration never defined its history widget"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: the fzf integration defined its Ctrl+R widget without the gate pressing Ctrl+R"

  # ── SM-M2: 8차가 읽을 것을 여기서 디스크에 쓴다 ──────────────────────
  #
  # 게이트가 전원을 뽑기 때문에 필요한 두 줄이다(실측 34). 실기에서
  # 전원 버튼을 누르면 PID 1의 SIGTERM이 셸에게 가고 zsh가 스스로 쓴다 —
  # 여기서만 그 신호가 없다.
  #
  # `fc -W`는 아무것도 안 찍으므로 되읽기가 따로 필요하다. 그 되읽기가
  # 없으면 이 줄이 실패했을 때 8차가 빨간 이유가 "안 썼다"인지 "안
  # 읽었다"인지 안 갈린다 — M1이 부팅을 둘로 나눈 것과 같은 이유다.
  type_keys "${HIST_WRITE_KEYS[@]}"
  type_keys "${HIST_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| [1-9][0-9]* /config/zsh_history'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 7): 'fc -W' left no history file for the eighth boot to read"
    echo "  둘 중 하나다 — HISTFILE/SAVEHIST가 셸에 안 갔거나(init의 env),"
    echo "  대문자 W가 게스트에 안 닿았다. 아래 마지막 화면에 'bad option'이"
    echo "  있으면 후자다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: the shell wrote its history to the config disk before the power was cut"
  return 0
}

# 8차 부팅의 훅. 이 milestone이 증명하려는 것 전부가 여기 있다(SM-M2).
#
# 이 부팅이 7차와 다른 점은 아무것도 안 심는다는 것이다. 디스크는 그대로고
# cmdline도 기본값이다 — 달라진 것은 기계가 한 번 꺼졌다 켜졌다는 것뿐이고,
# 그것이 이 서브프로젝트의 제목이다.
#
# 판정 셋이 서로 다른 실패를 본다.
#
#   1. z가 돈다        → zoxide DB가 /config/xdg에 남았다(쓰는 시점이 cd다)
#   2. db.zo가 보인다  → 그 DB가 tmpfs의 홈이 아니라 설정 디스크에 있다
#   3. history에 있다  → 나갈 때 쓰는 파일을 7차가 fc -W로 대신 썼다
probe_persisted_memory() {
  local log="$1"
  LOG="$log"

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 8): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 8): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  # ── 1. 자주 간 디렉터리 ────────────────────────────────────────────────
  #
  # 이 부팅은 `cd`를 한 번도 안 친다. 7차가 배운 것이 디스크에 없으면
  # `z`는 아무 데도 못 가고 `pwd`는 `/`를 찍는다. 판정 글자를 만들 수 있는
  # 것은 DB 하나뿐이다 — 7차와 같은 이유이고(실측 15의 `..`), 여기서는
  # `..`가 든 줄조차 화면에 없다.
  type_keys "${HOOK_Z_KEYS[@]}"
  type_keys "${HOOK_PWD_KEYS[@]}"
  if ! wait_for_screen '\| /usr/share/terminfo/x'; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 8): the machine forgot the directory the seventh boot learned"
    echo "  셋 중 하나다 — XDG_DATA_HOME이 셸에 안 갔거나, DB가 tmpfs에"
    echo "  쓰였거나(그러면 전원과 함께 사라진다), 훅이 안 걸렸다. 7차가"
    echo "  초록이었으면 셋째는 아니다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 8: z walked into a directory this boot never visited"

  # ── 2. 그 기억이 사는 자리 ─────────────────────────────────────────────
  #
  # 위의 판정만으로는 "어딘가에 남았다"까지다. 이 한 줄이 설정 디스크라는
  # 것을 말한다 — 홈(/)은 tmpfs라 거기 있었으면 위가 이미 빨갰겠지만,
  # 그 추론과 보는 것은 다르다.
  type_keys "${XDG_LS_KEYS[@]}"
  if ! wait_for_screen '\| db\.zo'; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 8): /config/xdg/zoxide holds no db.zo; the memory is not on the disk"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 8: that memory lives on the config disk, not in the tmpfs home"

  # ── 3. 쳤던 명령 ───────────────────────────────────────────────────────
  #
  # 판정 글자가 행의 첫머리가 아니다. `history`의 출력은 네 칸 들여쓴
  # 번호로 시작하기 때문이다(실측 36). 그래도 이 검사가 진짜인 이유는 같다 —
  # `whence -w fzf-history-widget`은 이 부팅에서 아무도 안 친다. 8차가
  # 치는 것은 `z`·`pwd`·`ls`·`history` 넷뿐이고, 그 글자를 화면에 만들 수
  # 있는 것은 7차가 쓰고 간 파일 하나다.
  type_keys "${HISTORY_KEYS[@]}"
  local ok=0
  if wait_for_screen 'whence -w fzf-history-widget'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 8): the history list has nothing the seventh boot typed"
    echo "  둘 중 하나다 — 7차의 fc -W가 못 썼거나(그러면 7차가 빨갰다),"
    echo "  이 부팅의 셸이 HISTFILE을 안 읽었다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 8: the history list carries a command only the seventh boot typed"
  return 0
}

# 부팅 한 번. $1 = 시리얼 로그 파일, $2 = 기다릴 마커, $3 = (선택) 마커를 본 뒤
# QEMU를 죽이기 전에 부를 함수, $4 = (선택) 커널 cmdline.
#
# 넷째 인자는 SC-M2가 더했다. 5차 부팅만 다른 cmdline으로 뜬다 — 탈출로 2가
# 보는 것이 `/proc/cmdline`이라 그것 말고 심을 자리가 없다(실기에서는 limine의
# 부팅 메뉴가 이 자리다).
boot_once() {
  local log="$1"
  local marker="$2"
  local hook="${3:-}"
  local cmdline="${4:-console=ttyS0}"

  qemu-system-x86_64 \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "$cmdline" \
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
  # 다음 부팅이 같은 디스크 이미지를 열기 때문이다 — 두 QEMU가 같은
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
echo "=== boot 1/8: empty disk, seed the config and the rc files, then edit them from inside ==="
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

# SC-M0. 같은 줄을 넓혀서 본다 — 새 줄을 안 만든 이유는 이 파일과
# 다른 체인들이 `tars-init: config shell=`을 앞부분으로 grep하고 있기
# 때문이다(main.zig의 그 자리 주석이 HI-M2에 대해 같은 것을 적고 있다).
#
# 여기가 게이트에서 기본값을 보는 유일한 자리다. 씨앗 파일이 실제로
# `shell_config=on`을 담았다는 것은 SC-M1이 2차 부팅으로 본다 — 이 검사가
# 보는 것은 파서가 그 키를 알고, 기본값이 on이라는 것까지다.
if ! grep -q "tars-init: config shell=fish.*shell_config=on" "$LOG1"; then
  report_failure "$LOG1" "first boot did not report the default shell_config=on"
fi
echo "boot 1: init reported shell_config=on (the sixth key reached the log)"

# SC-M1 결정 7. 씨앗 셋이 로그에 한 줄씩 남는다. 화면으로 보는 것은
# fish의 것 하나뿐이고(1차 부팅의 셸이 fish다) 나머지 둘은 이 줄이 전부다 —
# bash·zsh의 씨앗이 읽히는지는 이 milestone이 zsh에 대해서만 본다.
for rc in /config/bashrc /config/zshrc /config/fish.config; do
  if ! grep -q "tars-init: seeded ${rc}" "$LOG1"; then
    report_failure "$LOG1" "first boot did not seed ${rc}"
  fi
done
echo "boot 1: init seeded all three rc files on the empty disk"

# SM-M2. 이 부팅의 셸은 fish다(씨앗이 기본값이다). fish의 히스토리는
# XDG_DATA_HOME 아래로 통째로 따라오므로(실측 11·40) HISTFILE이 한 줄도
# 안 나와야 한다 — 그 침묵이 결정 3의 절반이고, 값이 폴백 뒤의 셸을
# 따른다는 증거이기도 하다.
if ! grep -q "tars-init: env PATH=/usr/bin:/bin XDG_DATA_HOME=/config/xdg" "$LOG1"; then
  report_failure "$LOG1" "first boot did not put XDG_DATA_HOME in the env block"
fi
if grep -q "tars-init: env HISTFILE" "$LOG1"; then
  report_failure "$LOG1" "first boot gave fish a HISTFILE; fish carries its history under XDG_DATA_HOME"
fi
echo "boot 1: the env block carries XDG_DATA_HOME, and fish asked for no HISTFILE"

if grep -q "Attempted to kill init" "$LOG1"; then
  report_failure "$LOG1" "kernel panicked because PID 1 exited on the first boot"
fi
echo "boot 1: seeded with fish, then edited to zsh from inside the guest"

# ---------------------------------------------------------------- 2차 부팅
# 같은 이미지를 그대로 다시 물린다. make_disk.sh를 부르지 않는다.
echo "=== boot 2/8: same image, the guest-written config should pick the shell and its rc ==="
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
# ⚠ 여기가 일곱 중 가장 나빴던 자리다(GA-M0). `!`가 없는 형이라 SIGPIPE의
# 141이 "안 맞았다"가 되고 `if`가 거짓이 되어 조용히 통과한다 — 거짓 빨강이
# 아니라 거짓 초록이다.
#
# 평시에는 앞단 출력이 0줄이다. 2차 부팅은 두 셸이 다 zsh라 fish 인사말이
# 아예 없다. 그래서 "앞단이 작아서 안전하다"로 읽히는데, 이 검사가 관심
# 있는 상황은 평시가 아니다 — 시리얼 콘솔이 정말 fish로 떴다면 화면 셸도
# fish이므로 인사말이 screen> 프레임마다 붙어 앞단이 커진다.
#
# 그 상황을 합성해서 200회씩 쟀다(GA design 실측 4). 화면 인사말이 1,000줄
# 이면 앞단이 97,054바이트이고, `-q`를 쓴 코드는 200회 중 200회 통과라고
# 말했다. `-q`를 뺀 코드는 같은 상황에서 200/200 실패를 말한다.
#
# 검사가 망가지는 조건이 검사가 필요한 조건과 같다 — 그래서 이 병은
# 평시 관측으로 영영 안 드러난다.
if grep "Welcome to fish, the friendly interactive shell" "$LOG2" | grep -v "terminal: screen>" >/dev/null; then
  report_failure "$LOG2" "the serial console still ran fish on the second boot"
fi

if grep -q "Attempted to kill init" "$LOG2"; then
  report_failure "$LOG2" "kernel panicked because PID 1 exited on the second boot"
fi
# ── SC-M1: 이 milestone이 증명하려는 것 ─────────────────────────────────
#
# 1차에서 사람이 /config/zshrc에 더한 `echo tars-rc-alive` 한 줄이 이 부팅의
# 셸에서 실행됐는가. 씨앗을 덮어쓰지 않고 더한 줄이므로, 이 글자가 보이면
# 씨앗 파일 자체가 읽혔다는 뜻이기도 하다.
#
# 두 자리를 따로 본다(결정 4).
#
#   terminal: screen> 가 아닌 줄  →  시리얼 콘솔 셸. init이 직접 exec했다
#   terminal: screen> 인 줄        →  화면 셸. terminal이 PTY에 띄웠다
#
# 아래 "시리얼 콘솔이 정말 fish가 아닌지"가 이미 같은 구분을 쓰고 있다.
# 콘솔 셸에는 타이핑을 못 하지만(체인이 -serial file:, 쓰기 전용)
# 그 셸이 스스로 찍는 것은 읽을 수 있다.
if ! grep "tars-rc-alive" "$LOG2" | grep -v "terminal: screen>" >/dev/null; then
  report_failure "$LOG2" "the serial console shell never ran the line the user added to /config/zshrc"
fi
# 위 둘이 이 파일에서 앞단이 자라는 자리다(GA-M0). 이 줄의 앞단은 screen>
# 줄 전체이고 매 프레임 47줄이 다시 찍히며, 바로 위 줄의 앞단도
# tars-rc-alive가 화면에 떠 있는 동안 프레임마다 한 줄씩 늘어난다.
# 2026-09-12에 쟀을 때 둘 다 5.7KB라 200/200 초록이었지만, 네 배면 위 줄은
# 200회 중 160회, 이 줄은 63회 빨개진다(GA design 실측 1).
if ! grep -a "terminal: screen>" "$LOG2" | grep -a "tars-rc-alive" >/dev/null; then
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
# 이 부팅은 아무것도 안 친다. 볼 것이 전부 없어야 할 것이기 때문이다 —
# 타이핑을 하면 그 글자가 화면에 남고, 판정 글자가 우연히 화면에 생기는 길이
# 하나 늘어난다.
echo "=== boot 3/8: same image with shell_config=off, the rc must not run ==="
if ! boot_once "$LOG3" "tars-init: started console shell" plant_broken_rc; then
  report_failure "$LOG3" "third boot never started a console shell"
fi

# 먼저 이 부팅이 2차와 같은 기계인지 확인한다. 아래 부정 검사는 "안
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

# ★ SC-M1이 증명하려는 나머지 절반. 같은 디스크, 같은 셸, 같은 rc 파일인데
#   한 줄이 바뀌어서 안 읽힌다. 2차와 3차 사이에 달라진 것은 tars.conf의
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

# ---------------------------------------------------------------- 4차 부팅
# 또 같은 이미지다. 3차가 `/config/zshrc`에 `exit` 한 줄을 심고
# `shell_config=on`을 되돌려 두었다 — 이 부팅의 두 셸은 뜨자마자 죽는다.
#
# design 위험 3이 말하는 상태가 정확히 이것이다: *"rc가 깨지면 그것을 고칠
# 셸이 없다."* M1까지 이 기계의 탈출로는 호스트에서 ext2 이미지를 직접 고치는
# 것뿐이었다.
LOG4="$(mktemp)"
echo "=== boot 4/8: the rc kills both shells; the supervisor must bring them back without it ==="
if ! boot_once "$LOG4" "tars-init: console shell died" watch_rescue; then
  report_failure "$LOG4" "the supervisor never rescued a shell from the rc that kills it"
fi

# 먼저 이 부팅이 함정을 실제로 밟았는지 확인한다. 아래 검사들은 "되살아
# 났다"를 보는데, 애초에 안 죽었으면 전부 공허해진다.
if ! grep -q "tars-init: config shell=zsh.*shell_config=on" "$LOG4"; then
  report_failure "$LOG4" "fourth boot did not read back the shell_config=on the third boot restored"
fi

# 콘솔 셸이 rc를 읽었다는 증거. 그 rc의 마지막 줄이 exit이므로 "읽었다"와
# "죽었다"가 같은 사실이다. 세 번인 것이 정책 그 자체다 — 처음 뜨고, 두 번
# 재시작하고, 세 번째 빠른 종료에서 탈출로가 발동한다(main.zig의
# MAX_FAST_RESTARTS = 3). boot/check.sh가 같은 모양으로 센다.
ALIVE="$(grep "tars-rc-alive" "$LOG4" | grep -cv "terminal: screen>" || true)"
if [ "$ALIVE" != "3" ]; then
  report_failure "$LOG4" "the console shell ran the broken rc ${ALIVE} times, want exactly 3 (the rescue must stop it there)"
fi

# ★ SC-M2가 증명하려는 것의 절반. 자식 둘 다 탈출로를 받는다(결정 4의
#   "두 셸이 같은 설정을 따른다"가 여기까지 온다).
if ! grep -q "tars-init: console shell died .* times fast" "$LOG4"; then
  report_failure "$LOG4" "the supervisor never offered the console shell a life without the rc"
fi
if ! grep -q "tars-init: terminal died .* times fast" "$LOG4"; then
  report_failure "$LOG4" "the supervisor never offered the terminal a life without the rc"
fi

# 그리고 그 탈출이 성공했다. 포기 줄이 하나도 없다는 것이 그 뜻이다 —
# 탈출로가 없던 M1이었다면 이 부팅은 자식 둘을 다 포기한 기계로 끝난다.
if grep -q "tars-init: giving up on" "$LOG4"; then
  report_failure "$LOG4" "the supervisor gave up anyway; the rescue did not save the shell"
fi

# 개수가 정책이다. 처음 셋은 rc를 읽고 죽었고 넷째가 rc 없이 살아남았다.
# 다섯이면 되살린 것도 죽은 것이고, 셋이면 탈출로가 안 돌았다는 뜻이다.
for want in "console shell" "terminal"; do
  STARTS="$(grep -c "tars-init: started ${want}" "$LOG4" || true)"
  if [ "$STARTS" != "4" ]; then
    report_failure "$LOG4" "init started the ${want} ${STARTS} times, want exactly 4 (three with the rc, one without)"
  fi
done

# 되살아난 화면 셸이 실제로 프롬프트를 그렸다. 죽는 동안에는 이 줄이 안
# 나온다 — 셸이 rc 처리 중에 죽어서 PTY에 아무것도 안 오기 때문이다.
if ! grep -q "terminal: screen>" "$LOG4"; then
  report_failure "$LOG4" "the rescued terminal never rendered; the machine came back unusable"
fi

if grep -q "Attempted to kill init" "$LOG4"; then
  report_failure "$LOG4" "kernel panicked because PID 1 exited on the fourth boot"
fi
echo "boot 4: the rc killed both shells three times, then the supervisor brought them back without it"

# ---------------------------------------------------------------- 5차 부팅
# 같은 이미지, 같은 함정. 다른 것은 커널 cmdline의 한 단어뿐이다.
#
# 4차가 이 부팅의 부정 검사를 진짜로 만든다 — 같은 디스크로 방금 셸이
# 여섯 번 죽는 것을 봤으므로, 여기서 아무도 안 죽으면 그것은 tars.noconfig가
# 한 일이다. M1의 3차가 2차에 기대던 구조와 같다.
LOG5="$(mktemp)"
echo "=== boot 5/8: same disk, same trap, but tars.noconfig on the command line ==="
if ! boot_once "$LOG5" "tars-init: started console shell" watch_quiet "console=ttyS0 tars.noconfig"; then
  report_failure "$LOG5" "fifth boot never started a console shell"
fi

# 기계가 2·3·4차와 같은 디스크를 봤다는 것부터.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG5"; then
  report_failure "$LOG5" "fifth boot did not load /config/tars.conf"
fi

# ★ SC-M2가 증명하려는 나머지 절반. 파일에는 on이라고 적혀 있다(4차가 같은
#   파일에서 on을 읽었다). 그런데 실효값이 off다 — cmdline이 이긴 것이다.
if ! grep -q "tars-init: tars.noconfig on the kernel command line beats /config/tars.conf" "$LOG5"; then
  report_failure "$LOG5" "init never reported that the command line token outranked the config file"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=off" "$LOG5"; then
  report_failure "$LOG5" "the command line token did not turn shell_config off"
fi

# 그리고 아무도 rc를 안 읽었다. 같은 디스크에서 4차는 여섯 번 죽었다.
if grep -q "tars-rc-alive" "$LOG5"; then
  report_failure "$LOG5" "tars.noconfig did not keep the shells out of the rc"
fi
if grep -q "times fast" "$LOG5"; then
  report_failure "$LOG5" "a shell still died on the fifth boot; the token did not reach the rc decision"
fi
if grep -q "tars-init: giving up on" "$LOG5"; then
  report_failure "$LOG5" "the supervisor gave up on a child that had no reason to die"
fi

# 한 번 뜨고 그대로 산다. 4차의 넷과 나란히 놓으면 이 수가 이야기 전부다.
for want in "console shell" "terminal"; do
  STARTS="$(grep -c "tars-init: started ${want}" "$LOG5" || true)"
  if [ "$STARTS" != "1" ]; then
    report_failure "$LOG5" "init started the ${want} ${STARTS} times on the fifth boot, want exactly 1"
  fi
done

if ! grep -q "terminal: screen>" "$LOG5"; then
  report_failure "$LOG5" "the terminal never rendered on the fifth boot"
fi
if grep -q "Attempted to kill init" "$LOG5"; then
  report_failure "$LOG5" "kernel panicked because PID 1 exited on the fifth boot"
fi
echo "boot 5: one word on the kernel command line beat the config file, and nothing died"

# ---------------------------------------------------------------- 6차 부팅
# 같은 이미지, 같은 함정, 같은 cmdline 토큰. 이 부팅은 증명하지 않고
# 수리한다(SM-M1).
#
# 3차가 심은 `exit`가 아직 `/config/zshrc`에 있다. 그 파일을 읽는 부팅은 셸이
# 죽고 탈출로가 rc 없이 되살리므로 훅도 함께 안 걸린다 — 7차가 훅을 보려면
# 먼저 이 줄이 없어져야 한다. `tars.noconfig`로 뜬 이 부팅의 셸은 rc를 안
# 읽으니 함정을 밟지 않고 그 파일을 지울 수 있다.
#
# design 결정 8은 M1이 부팅 하나를 더한다고 적었다. 그 계산에 이 수리가
# 빠져 있었다 — 4차·5차가 쓰고 간 디스크 상태를 안 본 것이다.
LOG6="$(mktemp)"
echo "=== boot 6/8: same broken rc, but tars.noconfig gives us a shell that can delete it ==="
if ! boot_once "$LOG6" "tars-init: started console shell" repair_broken_rc "console=ttyS0 tars.noconfig"; then
  report_failure "$LOG6" "sixth boot could not remove the rc the third boot broke"
fi

# 이 부팅도 5차와 같은 기계여야 한다 — 아래 수리가 "됐다"고 말하기 전에.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG6"; then
  report_failure "$LOG6" "sixth boot did not load /config/tars.conf"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=off" "$LOG6"; then
  report_failure "$LOG6" "the command line token did not turn shell_config off on the sixth boot"
fi
# 5차와 나란히 — 토큰이 셸을 함정에서 빼낸 것이 두 번 연속 재현된다.
if grep -q "times fast" "$LOG6"; then
  report_failure "$LOG6" "a shell still died on the sixth boot; there would have been no shell to repair with"
fi
if grep -q "Attempted to kill init" "$LOG6"; then
  report_failure "$LOG6" "kernel panicked because PID 1 exited on the sixth boot"
fi

# ---------------------------------------------------------------- 7차 부팅
# 같은 이미지, 기본 cmdline. 6차가 `/config/zshrc`를 지웠으므로 init이
# 그것만 다시 깔고(`O_EXCL`), 셸이 그 씨앗을 읽는다.
#
# ★ SM-M1이 증명하려는 것이 여기 있다. 그리고 그 증명의 성질이 M0과
#   다르다 — `tools/check.sh` 검사 18은 사람이 `zoxide add`를 쳤고, 이 부팅은
#   아무도 안 친다. 같은 판정 글자를 보는 두 검사의 차이가 정확히 "훅"이다.
LOG7="$(mktemp)"
echo "=== boot 7/8: init re-seeds the rc it lost, and the hooks in that seed must run ==="
if ! boot_once "$LOG7" "tars-init: started console shell" probe_shell_hooks; then
  report_failure "$LOG7" "the hooks in the seeded rc did not run on the seventh boot"
fi

# `O_EXCL`의 정확한 계약이 이 두 검사다 — 없어진 하나는 다시 깔고, 있는
# 둘은 안 건드린다. 셋을 다 깔면 사용자가 bashrc에 쓴 것이 조용히 사라진다.
if ! grep -q "tars-init: seeded /config/zshrc" "$LOG7"; then
  report_failure "$LOG7" "init did not re-seed the /config/zshrc that the sixth boot removed"
fi
for rc in /config/bashrc /config/fish.config; do
  if grep -q "tars-init: seeded ${rc}" "$LOG7"; then
    report_failure "$LOG7" "seventh boot re-seeded ${rc}; O_EXCL should have left the existing file alone"
  fi
done
echo "boot 7: init re-seeded only the rc that was missing"

# 기계가 같은 디스크를 봤고, cmdline 토큰이 없으므로 rc가 다시 읽힌다.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG7"; then
  report_failure "$LOG7" "seventh boot did not load /config/tars.conf"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=on" "$LOG7"; then
  report_failure "$LOG7" "seventh boot did not read back shell_config=on"
fi

# SM-M2. 이 부팅의 셸은 zsh다 — 셋이 다 나와야 한다. SAVEHIST가 없으면
# zsh는 HISTFILE이 있어도 한 줄도 안 쓴다(실측 9). 아래 화면 판정이
# 그것을 실제로 보지만, 로그의 이 셋이 왜 그런지를 말해 준다.
for want in \
  "tars-init: env HISTFILE=/config/zsh_history" \
  "tars-init: env HISTSIZE=5000" \
  "tars-init: env SAVEHIST=5000"; do
  if ! grep -q "$want" "$LOG7"; then
    report_failure "$LOG7" "seventh boot did not put '${want#tars-init: env }' in the env block"
  fi
done

# 7차의 rc는 사람이 손댄 적이 없는 씨앗이다. 1차에서 사람이 더한 줄은
# 6차가 파일과 함께 지웠다 — 이 부정 검사가 그것을 말한다. 이 글자가 보이면
# 6차의 `rm`이 안 먹었거나 init이 다른 파일을 깐 것이다.
if grep -q "tars-rc-alive" "$LOG7"; then
  report_failure "$LOG7" "the seventh boot's rc still carries the line a human typed; it is not the seed"
fi

# 그리고 그 씨앗은 셸을 안 죽인다. 훅 두 줄이 늘어난 파일이라 이 검사가
# 전보다 중요해졌다 — design 위험 1이 말하는 실패가 여기로도 온다.
if grep -q "times fast" "$LOG7"; then
  report_failure "$LOG7" "a shell died on the seventh boot; the hooks in the seed are not safe to read"
fi
if grep -q "tars-init: giving up on" "$LOG7"; then
  report_failure "$LOG7" "the supervisor gave up on a child on the seventh boot"
fi
for want in "console shell" "terminal"; do
  STARTS="$(grep -c "tars-init: started ${want}" "$LOG7" || true)"
  if [ "$STARTS" != "1" ]; then
    report_failure "$LOG7" "init started the ${want} ${STARTS} times on the seventh boot, want exactly 1 (the seeded hooks must not cost a restart)"
  fi
done
if grep -q "Attempted to kill init" "$LOG7"; then
  report_failure "$LOG7" "kernel panicked because PID 1 exited on the seventh boot"
fi
echo "boot 7: the machine learned a directory from a cd nobody told it to remember"

# ---------------------------------------------------------------- 8차 부팅
# 같은 이미지, 기본 cmdline, 아무것도 안 심는다. 7차와 이 부팅 사이에
# 달라진 것은 기계가 한 번 꺼졌다 켜졌다는 것뿐이다.
#
# ★ SM-M2가 증명하려는 것이 여기 있다. 7차가 8차를 진짜로 만든다 —
#   7차가 DB에 넣은 것은 `/usr/share/terminfo/x` 하나이고, 그 하나가
#   `XDG_DATA_HOME` 덕분에 여기까지 살아남는다.
LOG8="$(mktemp)"
echo "=== boot 8/8: nothing is planted — the machine must remember the seventh boot ==="
if ! boot_once "$LOG8" "tars-init: started console shell" probe_persisted_memory; then
  report_failure "$LOG8" "the eighth boot did not find what the seventh boot learned"
fi

# 기계가 같은 디스크를 봤다는 것부터. 아래 부정 검사들이 공허해지는 길을 막는다.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG8"; then
  report_failure "$LOG8" "eighth boot did not load /config/tars.conf"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=on" "$LOG8"; then
  report_failure "$LOG8" "eighth boot did not read back shell_config=on"
fi

# 씨앗은 다시 안 깔린다. 7차가 zshrc를 되깔았으므로 셋이 다 있다 —
# 여기서 seeded가 하나라도 나오면 디스크가 아니라 tmpfs를 보고 있는 것이다.
if grep -q "tars-init: seeded /config/" "$LOG8"; then
  report_failure "$LOG8" "eighth boot re-seeded an rc file; it was not looking at the same disk"
fi

# 7차와 같은 rc다 — 사람이 손댄 줄이 없고, 셸을 안 죽인다.
if grep -q "tars-rc-alive" "$LOG8"; then
  report_failure "$LOG8" "the eighth boot's rc carries a line a human typed; it is not the seed"
fi
if grep -q "times fast" "$LOG8"; then
  report_failure "$LOG8" "a shell died on the eighth boot"
fi
if grep -q "tars-init: giving up on" "$LOG8"; then
  report_failure "$LOG8" "the supervisor gave up on a child on the eighth boot"
fi
for want in "console shell" "terminal"; do
  STARTS="$(grep -c "tars-init: started ${want}" "$LOG8" || true)"
  if [ "$STARTS" != "1" ]; then
    report_failure "$LOG8" "init started the ${want} ${STARTS} times on the eighth boot, want exactly 1"
  fi
done
if grep -q "Attempted to kill init" "$LOG8"; then
  report_failure "$LOG8" "kernel panicked because PID 1 exited on the eighth boot"
fi
echo "boot 8: the machine remembered a directory and a command across a power cut"

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
echo "--- init log (boot 4) ---"
grep 'tars-init:' "$LOG4" || true
echo "--- init log (boot 5) ---"
grep 'tars-init:' "$LOG5" || true
echo "--- init log (boot 6) ---"
grep 'tars-init:' "$LOG6" || true
echo "--- init log (boot 7) ---"
grep 'tars-init:' "$LOG7" || true
echo "--- init log (boot 8) ---"
grep 'tars-init:' "$LOG8" || true

echo "PASS"
exit 0
