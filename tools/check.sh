#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# UT 체인 — 게스트가 명령을 **이름으로** 찾는가.
#
# 이 게이트가 증명하는 사슬 전체:
#   커널이 PID 1에게 envp 둘을 준다(HOME=/ · TERM=linux)
#   → init/src/environ.zig의 withPath가 PATH를 붙인 블록을 짓는다
#   → supervise()가 그 블록을 자식 둘에게 똑같이 넘긴다
#   → terminal이 forkpty 뒤 셸을 exec하며 자기 환경을 물려준다
#   → 셸이 `ls` 세 글자로 /usr/bin/ls를 찾아 실행한다
#
# **UT-M1이 두 번째 질문을 더한다 — 그 도구들이 실제로 도는가.** 파일이
# initrd에 있는 것과 게스트에서 도는 것은 다르고, 그 사이에 라이브러리가
# 있다. 검사 5~7이 사슬이 가장 긴 셋(ps · awk · sed)을 실제로 친다.
#
# **열 체인 중 어느 것도 이것을 못 본다.** 나머지는 전부 게스트 명령을 절대
# 경로로 친다 — docs/decisions/project_guest_environment.md가 IP-M0에서
# 그렇게 고치라고 적어 둔 그대로다. 그 문서의 "결과 1"을 닫는 체인이다.
#
# 시리얼 콘솔 셸은 이 체인도 안 본다. 저장소의 열한 체인 전부가
# -serial file:(쓰기 전용)이고 키는 QEMU monitor로 **화면 셸**에만 간다.
# 그쪽은 init이 찍는 `tars-init: env` 한 줄과 코드 구조로 안다
# (design의 "시리얼 셸은 관측하지 않는다" 절).

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
# environ_test가 여기 들어 있다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
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

. ../gate_lib.sh

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR, 45461=CM,
# 45462=HI, 45471=RM. 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때
# 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45463

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  for pattern in "$@"; do
    # `|| true`가 없으면 이 루프가 첫 패턴에서 죽는다 — 안 맞는 grep은
    # 종료 코드 1이고 pipefail이 그것을 파이프라인 코드로 올린다.
    # RM-M2가 잡은 잠복 결함이고, 하필 첫 패턴이 "없는 것"인 경우가 가장
    # 흔하다(그것이 실패의 이유라서 목록 앞에 적힌다).
    grep -a "$pattern" "$LOG" | head -3 | sed 's/^/  /' || true
  done
  exit 1
}

# ── 검사 1: initrd에 뼈대와 도구가 들어 있는가 (부팅 전, 정적) ──────────
#
# 부팅 20초를 쓰기 전에 본다. 그리고 **줄을 통째로 맞춘다** — TR-M2가
# `*terminfo/x/xterm*` 글로브 하나로 xterm-256color가 없는 것을 두 milestone
# 동안 못 잡은 자리가 있다. 조용한 실패를 막으려고 만든 검사가 조용히
# 실패한 자리였다.
#
# **UT-M1: 목록이 make_initrd.sh와 같은 파일에서 온다**(design 결정 7).
# 여기에 도구 이름을 다시 적지 않는다 — kernel/guest_tools.sh 한 줄을
# 더하면 이 검사가 그 줄을 자동으로 본다.
#
# **이 검사가 증명하는 것과 안 하는 것을 갈라 둔다.**
#   증명한다:   make_initrd.sh가 목록이 말하는 것을 **전부 실제로 넣었다.**
#               루프가 중간에 끊기거나, dest 경로가 어긋나거나, cpio가
#               떨어뜨리면 여기서 죽는다.
#   증명 안 한다: 목록 자체가 완전한가. 목록에 없는 도구는 이 검사도 모른다 —
#               그것은 게이트가 아니라 design이 답할 질문이다(최종 목록).
# 목록을 되읽는 검사라 tautology에 가깝다는 것을 알고 두는 것이, 모르고
# "게이트가 도구를 다 본다"고 믿는 것보다 낫다.
#
# **접두사 `./`를 붙이면 안 된다.** make_initrd.sh가 `find .`이 아니라
# 다른 방식으로 목록을 만들어서 cpio 안의 이름이 `usr/bin/ls`이지
# `./usr/bin/ls`가 아니다(2026-09-10 UT-M0에서 실측). input/check.sh:83이
# 이미 접두사 없이 맞추고 있다 — 여기가 그것과 같은 모양이어야 한다.
# 붙였으면 이 검사가 **언제나** FAIL이고, 그것도 위의 TR-M2와 같은 종류의
# 사고다(다만 이쪽은 조용하지 않아서 첫 실행에서 드러난다).
#
# 파이프라인 대신 변수에 담아 case로 보는 이유는 이 스크립트의 pipefail이다
# (input/check.sh:71의 주석과 같다) — `... | grep -q`는 첫 매치에서 빠져나가며
# 앞단 cpio에 SIGPIPE를 일으키고 pipefail이 그것을 파이프라인 실패로 만든다.
. ../kernel/guest_tools.sh

# 뼈대 넷은 배열에 없다 — 바이너리가 아니라 디렉터리·링크·텍스트 파일이고
# make_initrd.sh가 손으로 만든다(design 결정 6). 그래서 여기 literal로 둔다.
WANT=(bin/sh tmp etc/passwd etc/group)
for entry in "${GUEST_TOOLS[@]}"; do
  WANT+=("${entry#*:}")
done

INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
PADDED_LIST="$(printf '\n%s\n' "$INITRD_LIST")"
for want in "${WANT[@]}"; do
  case "$PADDED_LIST" in
    *$'\n'"${want}"$'\n'*) ;;
    *)
      echo "FAIL: ${want} is missing from the initrd"
      echo "--- what is there ---"
      printf '%s\n' "$INITRD_LIST" | grep -E '^(bin|tmp|etc|usr/bin)' | head -20
      exit 1
      ;;
  esac
done
echo "the initrd carries the four bones and all ${#GUEST_TOOLS[@]} tools the list names"

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

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || fail "the terminal never rendered a prompt" \
  "tars-init: started" "terminal:" "Kernel panic"
sleep 1

# ── 검사 2: init이 블록을 지었다 ────────────────────────────────────────
#
# 이 줄이 없으면 withPath가 자리 부족으로 폴백했거나 main.zig가 아직 옛
# 포인터를 쓰고 있다. 아래 타이핑 검사가 실패하기 **전에** 원인을 가른다.
if ! grep -aq "tars-init: env PATH=/usr/bin:/bin" "$LOG"; then
  fail "init never reported building an environment block with PATH" \
    "tars-init: env" "tars-init: starting as PID 1"
fi
echo "init built an environment block carrying PATH"

# ── 검사 3: 셸이 이름으로 명령을 찾는다 ─────────────────────────────────
#
# **이 milestone의 심장이다.** 앞의 둘은 파일이 있다는 것과 init이 문자열을
# 찍었다는 것이고, 여기부터가 **PATH가 실제로 동작하는가**다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor" "terminal: grid"

echo "=== typing 'ls' with no absolute path ==="
type_keys l s ret
sleep 2

# 게스트 루트에는 vendor 디렉터리가 있다(폰트가 거기 있다). 화면 줄에만
# 있어야 한다 — tars-init: 줄에도 vendor가 나올 수 있으므로 screen>으로
# 먼저 거른다.
if ! grep -a "terminal: screen>" "$LOG" | grep -aq "vendor"; then
  fail "'ls' with no path never listed the guest root (is PATH reaching the shell?)" \
    "terminal: screen>" "tars-init: env"
fi
echo "the shell resolved 'ls' through PATH"

# ── 검사 4: /bin/sh 링크가 살아 있다 ────────────────────────────────────
#
# `ls -l /bin`이 한 줄로 둘을 증명한다 — ls가 플래그와 인자를 받아 돌고,
# 링크가 bash를 가리킨다. 링크가 끊겨 있어도 ls -l은 그 사실을 그대로
# 보여주므로, 여기서 보는 것은 "무엇을 가리키는가"다.
echo "=== typing 'ls -l /bin' ==="
type_keys l s spc minus l spc slash b i n ret
sleep 2

if ! grep -a "terminal: screen>" "$LOG" | grep -aq "bash"; then
  fail "/bin/sh does not point at bash" \
    "terminal: screen>" "tars-init: env"
fi
echo "/bin/sh points at bash"

# ── 검사 5: ps가 돈다 — **위험 3의 대표 검사** ──────────────────────────
#
# 검사 1은 "파일이 initrd에 들어갔다"까지다. 도구가 못 도는 가장 흔한 방식은
# 파일이 없는 것이 아니라 **라이브러리가 없는 것**이고, 그 실패는 빌드 때가
# 아니라 게스트가 그 명령을 처음 칠 때 `error while loading shared libraries`
# 로 나타난다(design 위험 3).
#
# **ps를 고른 이유는 사슬이 가장 길어서다.**
#
#   ps → libproc2.so.0 → libsystemd.so.0 → libcap.so.2
#
# 저장소에서 가장 깊은 동적 의존이고, 셋 다 dlopen이 아니라 로더가 실행
# 시점에 전부 풀어야 하는 것들이다. make_initrd.sh의 copy_lib_deps 루프가
# .so의 DT_NEEDED까지 재귀로 따라가는지가 이 한 줄에 걸린다 — **design
# 실측 3이 바이너리의 DT_NEEDED만 보고 libsystemd를 놓쳤던 자리다.**
#
# 판정을 `/terminal`로 잡는 것에 뜻이 있다. ps가 그냥 도는 것만 보려면
# 아무 줄이나 쓰면 되지만, 이 문자열은 **감독자가 띄운 자식이 커널의
# 프로세스 테이블에 실제로 있다**까지 함께 말한다. `terminal: screen>`
# 접두사에는 슬래시가 없으므로 접두사 자신과 헷갈리지 않는다.
echo "=== typing 'ps ax' ==="
type_keys p s spc a x ret
sleep 3

if ! grep -a "terminal: screen>" "$LOG" | grep -aq "/terminal"; then
  fail "'ps ax' never listed the supervised terminal (did libproc2/libsystemd resolve?)" \
    "terminal: screen>" "error while loading"
fi
echo "ps walked /proc and found the supervised terminal"

# ── 검사 6: awk가 돈다 — **결정 4의 이름 바꾸기** ───────────────────────
#
# mawk 패키지는 /usr/bin/mawk만 담는다. /usr/bin/awk는 Debian의 alternatives가
# postinst에서 만드는 것이라 dpkg -x로 푼 sysroot에 없다. guest_tools.sh가
# `usr/bin/mawk:usr/bin/awk`로 넣지 않았으면 이 줄이 `Unknown command`다 —
# **initrd 안의 이름은 우리가 정한다는 결정 4가 실제로 먹었는지를 보는
# 유일한 자리다.**
#
# 따옴표 없는 awk 프로그램이라 sendkey로 칠 수 있다. 패턴만 있고 액션이
# 없으면 맞는 줄을 그대로 출력한다.
echo "=== typing 'awk /root/ /etc/passwd' ==="
type_keys a w k spc slash r o o t slash spc slash e t c slash p a s s w d ret
sleep 2

if ! grep -a "terminal: screen>" "$LOG" | grep -aq "root:x:0:0:root"; then
  fail "awk did not print the passwd line (is mawk installed under the name awk?)" \
    "terminal: screen>" "Unknown command"
fi
echo "awk ran under the name we gave it"

# ── 검사 7: sed가 돈다 — libacl 사슬 ────────────────────────────────────
#
# **출력이 저장소 어디에도 없는 문자열이어야 한다.** `sed -n 1p /etc/group`은
# `root:x:0:`을 내는데 그것은 /etc/passwd 줄의 앞부분과 겹쳐서 바로 위의 awk
# 검사와 구분이 안 된다 — 검사 둘이 같은 글자를 보면 하나가 죽어도 둘 다
# 초록일 수 있다. 치환을 시키면 출력이 `tars:x:0:`이고 **그 글자를 만들 수
# 있는 것은 sed뿐이다**(타이핑한 명령줄 자체는 `s/root/tars/`라서 이 글자를
# 안 만든다).
echo "=== typing 'sed s/root/tars/ /etc/group' ==="
type_keys s e d spc s slash r o o t slash t a r s slash spc slash e t c slash g r o u p ret
sleep 2

if ! grep -a "terminal: screen>" "$LOG" | grep -aq "tars:x:0:"; then
  fail "sed did not rewrite the group line (did libacl come along?)" \
    "terminal: screen>" "Unknown command"
fi
echo "sed rewrote a line"

# ── 검사 8: 음성 확인 — **위의 넷 전부에 대해** ─────────────────────────
#
# fish는 못 찾은 명령에 `Unknown command`를 낸다. 이 검사가 맨 뒤에 있는
# 이유가 그것이다 — ls · ps · awk · sed 넷을 다 친 뒤에 한 번 보면 넷
# 전부의 음성 확인이 된다. UT-M0 때는 ls 하나뿐이라 바로 뒤에 있었다.
#
# **positive 검사만으로는 안 닫히는 길이 있다.** 예를 들어 검사 5의
# `/terminal`은 화면 어딘가에 그 글자가 있으면 초록인데, ps가 죽고 그 앞의
# 프레임이 남아 있어도 그럴 수 있다. 못 찾았다는 말이 화면에 없다는 것이
# 그 길을 닫는다.
if grep -a "terminal: screen>" "$LOG" | grep -aq "Unknown command"; then
  fail "the shell said it could not find one of the commands" \
    "terminal: screen>" "tars-init: env"
fi

# `error while loading shared libraries`는 위험 3의 실제 문구다. 검사 5~7의
# positive가 우연히 지나가도 이 한 줄이 남아 있으면 무언가는 못 돈 것이다.
if grep -a "error while loading shared libraries" "$LOG"; then
  fail "a tool could not load its libraries (copy_lib_deps missed something)" \
    "error while loading shared libraries"
fi

echo "PASS"
exit 0
