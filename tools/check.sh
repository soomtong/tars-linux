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
# **UT-M2가 층 2(모던 13)를 더하고 검사 셋을 더 친다** — eza(libgit2 사슬
# 열여섯) · fd(결정 4의 이름 바꾸기) · jq(libjq→libonig). 열셋 중 넷은
# 게이트가 못 친다: htop·btop·ncdu는 대화형이라 매달리고, bat은 판정 글자를
# 못 만든다. **넷의 이유가 각각 다르고, 그 넷이 쓰는 라이브러리 둘은 검사
# 1이 정적으로만 본다.**
#
# **UT-M3이 층 3(git · vim.tiny)을 더하고 검사 다섯을 더 친다** — 저장소를
# 만들고, 전역 설정을 /config에 쓰고, 커밋하고, 그것을 다시 읽는다. **여기서
# 처음으로 게이트가 게스트에 무언가를 쓴다** — 지금까지 열한 체인이 친 것은
# 전부 읽거나 찍는 명령이었다. `/tmp`(UT-M0이 놓고 아무도 안 쓰던 뼈대)와
# `/config`(CP가 만든 마운트)가 그 쓰기를 받는다.
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

# **타이핑으로는 절대 증명할 수 없는 라이브러리 둘.** 이 둘을 쓰는 도구가
# htop·ncdu·btop뿐인데 셋 다 대화형이라 게이트가 못 친다(실측 26). 파일이
# 들어갔다는 것까지가 게이트가 이 셋에 대해 볼 수 있는 전부이고, 그 사실을
# 알고 두는 것이 낫다.
#
# 라이브러리가 아예 없는 경우는 사실 여기까지 못 온다 — copy_lib_deps가
# 소네임을 못 풀면 **빌드 때** 죽는다. 이 둘이 잡는 것은 그 다음이다:
# LIB_DEST가 바뀌었거나 cpio가 떨어뜨린 경우.
WANT+=(lib/x86_64-linux-gnu/libncursesw.so.6 lib/x86_64-linux-gnu/libstdc++.so.6)

# **UT-M3: 배열에 없는 다섯.** 링크 셋과 `.gitconfig`는 바이너리가 아니라
# make_initrd.sh가 손으로 거는 것이고(뼈대 넷과 같은 자리), 템플릿은 트리다.
#
# **이 다섯에 대해서는 검사 1이 tautology가 아니다.** 아래 이름들이 배열이
# 아니라 여기 literal로 적혀 있어서, make_initrd.sh에서 그 줄을 지우면
# **부팅 20초를 쓰기 전에 여기서 죽는다.** 배열을 되읽는 검사와 다른 점이
# 이것이고(design 실측 24·33), 그래서 M1·M2의 음성 확인이 보여 준 경계가
# 여기서는 반대로 선다.
#
#   usr/bin/vi       vim의 두 번째 이름(결정 4). 실체는 usr/bin/vim이고
#                    배열이 그쪽만 안다
#   usr/bin/pager    **git이 컴파일 타임에 박아 둔 이름이다.** 없으면
#                    `git log`가 `cannot run pager`로 죽는다 — 게이트는
#                    --no-pager로 치므로 **타이핑으로는 영영 안 드러난다**
#   usr/bin/editor   같은 종류. -m 없는 git commit과 rebase -i가 이 이름을
#                    부른다. 게이트는 -m을 주므로 이것도 정적으로만 본다
#   .gitconfig       결정 8. 아래 검사 13이 이 링크를 실제로 통과시킨다
#   templates/...    없으면 git init이 매번 경고를 찍는다. 잎 하나를 보는
#                    것으로 cp -r 전체를 본다
WANT+=(usr/bin/vi usr/bin/pager usr/bin/editor .gitconfig
       usr/share/git-core/templates/info/exclude)

INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"

# **명령 치환으로 패딩을 만들면 안 된다.** `$(printf '\n%s\n' ...)`은 끝의
# 개행을 명령 치환이 도로 지운다 — 그래서 **아카이브의 마지막 항목은 어떤
# 이름을 찾아도 영원히 못 맞춘다.** UT-M3에서 `.gitconfig`이 마침 마지막
# 항목이라 드러났다. 지금까지 안 드러난 이유는 마지막 항목이 한 번도 WANT에
# 없었기 때문이고, **증상은 초록이 아니라 설명 안 되는 빨강**이었을 것이다
# (TR-M2의 글로브와 같은 종류인데 방향이 반대다 — 그쪽은 조용한 초록이었다).
PADDED_LIST=$'\n'"${INITRD_LIST}"$'\n'
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

# **아래 여덟 자리에 `sleep 2`가 없다.** UT-M2 전에는 명령마다 2~3초를 무조건
# 쉬고 한 번 grep했는데, 그 수를 아무도 잰 적이 없고 8회 중 2회 깨졌다 —
# 깨진 회차의 마지막 화면에는 찾던 글자가 정확히 찍혀 있었다. gate_lib.sh의
# wait_for_screen 주석이 본문이다. 찾으면 즉시 돌아오므로 이 체인은 그 변경
# 뒤에 **더 빠르다**(부팅당 고정 17초가 사라졌다).
echo "=== typing 'ls' with no absolute path ==="
type_keys l s ret

# 게스트 루트에는 vendor 디렉터리가 있다(폰트가 거기 있다). 화면 줄에만
# 있어야 한다 — tars-init: 줄에도 vendor가 나올 수 있으므로 screen>으로
# 먼저 거른다(wait_for_screen이 그 거르기를 한다).
if ! wait_for_screen "vendor"; then
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

if ! wait_for_screen "bash"; then
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

if ! wait_for_screen "/terminal"; then
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

if ! wait_for_screen "root:x:0:0:root"; then
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

if ! wait_for_screen "tars:x:0:"; then
  fail "sed did not rewrite the group line (did libacl come along?)" \
    "terminal: screen>" "Unknown command"
fi
echo "sed rewrote a line"

# ── 검사 8: eza가 돈다 — **libgit2 사슬 열여섯** ────────────────────────
#
# **UT-M2의 심장이다.** eza·bat이 데려오는 사슬이 저장소에서 가장 길다.
#
#   eza → libgit2.so.1.9 → libssh2 → libcrypto.so.3 → libz · libzstd
#                        → libgssapi_krb5 → libkrb5 → libresolv · libcom_err
#                                                   · libkeyutils · libk5crypto
#                        → libmbedtls → libmbedx509 → libmbedcrypto
#                        → libhttp_parser
#
# 열여섯 전부를 로더가 실행 시점에 풀어야 한다(dlopen이 아니다). M1의
# `ps ax`가 libproc2→libsystemd→libcap 셋을 보던 자리를 이것이 이어받는다.
#
# 판정 글자를 `fonts`로 잡는다. 게스트 루트에 vendor/fonts가 있고, **화면
# 어느 프레임에도 그 글자가 없다** — 검사 3의 `ls`는 루트 항목만 냈고
# 타이핑한 명령줄 자체는 `eza vendor`다. 검사 둘이 같은 글자를 보면 하나가
# 죽어도 둘 다 초록일 수 있다(검사 7의 주석과 같은 이유).
echo "=== typing 'eza vendor' ==="
type_keys e z a spc v e n d o r ret

if ! wait_for_screen "fonts"; then
  fail "eza did not list the vendor directory (did the libgit2 chain resolve?)" \
    "terminal: screen>" "error while loading"
fi
echo "eza listed a directory through the sixteen-library libgit2 chain"

# ── 검사 9: fd가 **우리가 준 이름으로** 돈다 — 결정 4 ───────────────────
#
# .deb 안에서 실체는 /usr/lib/cargo/bin/fd이고 /usr/bin/fdfind가 그것을
# 가리키는 심볼릭 링크다. guest_tools.sh가 `usr/lib/cargo/bin/fd:usr/bin/fd`로
# 넣지 않았으면 이 줄이 `Unknown command`다 — mawk→awk와 같은 자리이고,
# **initrd 안의 이름은 우리가 정한다는 결정 4를 M2에서 보는 자리다.**
#
# **인자로 vendor를 주는 것이 중요하다.** fd는 인자가 없으면 현재 디렉터리
# 아래를 전부 훑는데, 게스트의 cwd가 / 이고 거기에 /proc·/sys가 있다.
# 훑는 데 오래 걸리고 출력이 화면을 뒤덮는다 — less·top이 매달리는 것과
# 종류는 다르지만 게이트에 미치는 결과가 같다.
echo "=== typing 'fd otf vendor' ==="
type_keys f d spc o t f spc v e n d o r ret

if ! wait_for_screen "unifont"; then
  fail "fd did not find the font under the name we gave it" \
    "terminal: screen>" "Unknown command"
fi
echo "fd ran under the name we gave it"

# ── 검사 10: jq가 돈다 — libjq → libonig ────────────────────────────────
#
# 게스트에 JSON 파일이 하나도 없고, 게이트에 파일을 만들어 넣는 것은 이
# 검사 하나를 위해 initrd를 넓히는 일이다. `--version`으로 충분한 이유는
# **이 검사가 보는 것이 파싱이 아니라 동적 링크**이기 때문이다 — libjq도
# libonig도 DT_NEEDED라 로더가 exec 시점에 둘 다 풀어야 하고, 못 풀면
# 한 글자도 안 찍고 죽는다.
#
# 버전을 `jq-1.7`로 박지 않고 `jq-[0-9]`로 보는 것은 trixie가 올라가면
# 갈릴 자리라서다. 타이핑한 명령줄은 `jq --version`이라 이 정규식과 안
# 겹친다.
echo "=== typing 'jq --version' ==="
type_keys j q spc minus minus v e r s i o n ret

if ! wait_for_screen "jq-[0-9]"; then
  fail "jq did not print its version (did libjq/libonig resolve?)" \
    "terminal: screen>" "error while loading"
fi
echo "jq loaded libjq and libonig"

# **bat은 일부러 안 친다.** 매달리지는 않지만(-P로 페이저를 끌 수 있다)
# 화면에 내는 글자가 문제다 — /etc/passwd도 /etc/group도 검사 6·7이 이미
# 본 글자이고, 헤더의 `File: ` 문자열은 바이너리 안에서 확인되지 않았다
# (2026-09-11, `strings`로 확인). **판정을 만들 수 없는 검사는 안 만든다.**
# bat이 잃는 것은 크지 않다 — 라이브러리는 eza와 같은 사슬이라 검사 8이
# 보고, 이름은 검사 1이 dest로 본다.

# ── 검사 12: git이 저장소를 만든다 — **UT-M3의 심장** ───────────────────
#
# `/tmp`로 먼저 옮기는 것에 뜻이 둘 있다. 게스트의 cwd가 `/`이고 거기는
# initrd 트리라 저장소를 만들 자리가 아니라는 것이 하나, 그리고 **UT-M0이
# 놓은 뼈대 `/tmp`(모드 1777)를 이 저장소가 처음으로 실제로 쓴다**는 것이
# 둘이다 — M0이 만들어 두고 아무도 안 쓰던 자리다.
#
# **`-b main`을 주는 이유는 화면을 아끼기 위해서다.** 안 주면 git이 기본
# 브랜치 이름에 대한 힌트를 다섯 줄 찍는다. 판정을 만드는 데 방해가 되지는
# 않지만, 게이트가 보는 화면에 안 읽을 글자를 다섯 줄 늘릴 이유가 없다.
#
# 판정 `Initialized empty`는 git만 만들 수 있다 — 타이핑한 명령줄은
# `git init -b main r`이라 겹치지 않는다. **이 한 줄이 템플릿까지 본다**:
# /usr/share/git-core/templates가 없으면 이 줄 앞에 `warning: templates not
# found`가 함께 나온다(검사는 통과하지만 화면이 말해 준다).
echo "=== typing 'cd /tmp' and 'git init -b main r' ==="
type_keys c d spc slash t m p ret
if ! wait_for_screen "/tmp#"; then
  fail "the shell never moved into /tmp (is the 1777 bone there?)" \
    "terminal: screen>"
fi

type_keys g i t spc i n i t spc minus b spc m a i n spc r ret
if ! wait_for_screen "Initialized empty"; then
  fail "git did not create a repository under /tmp" \
    "terminal: screen>" "Unknown command" "error while loading"
fi
echo "git created a repository in the 1777 bone /tmp"

# ── 검사 13: 전역 설정이 /config로 간다 — **결정 8** ────────────────────
#
# git은 전역 설정을 $HOME/.gitconfig에서 읽고 게스트의 HOME은 /다. 그런데
# /는 tmpfs라 재부팅하면 사라지므로 make_initrd.sh가
# `/.gitconfig -> config/gitconfig` 링크를 걸어 뒀다. **git이 그 링크를 풀고
# 저쪽에 쓰는지를 여기서 본다** — 쓰는 쪽이 링크를 따라가지 않고 링크 자체를
# 덮어쓰면 설정은 tmpfs에 남고 재부팅하면 사라진다. 둘은 화면에서 구별되지
# 않으므로 **읽는 자리를 바꿔서** 묻는다: /config/gitconfig를 cat한다.
#
# **이 체인에는 설정 디스크가 없다.** 그래서 /config는 initrd 안의 빈
# 디렉터리(tmpfs)이고, 이 검사가 증명하는 것은 "링크가 풀려 /config에
# 쓰인다"까지다. 그 디스크가 부팅 사이에 파일을 지킨다는 것은 **CP 체인이
# 같은 마운트로 이미 증명한 것**이다 — 알고 두는 경계다.
#
# 판정을 `email = tars`로 잡는 것은 타이핑한 명령줄(`user.email tars`)과
# 글자가 겹치지 않게 하기 위해서다. 등호 양쪽의 공백은 git이 파일을 쓸 때
# 만드는 것이고 우리가 친 적이 없다.
echo "=== typing 'git config --global user.email tars' and reading it back ==="
type_keys g i t spc c o n f i g spc minus minus g l o b a l spc \
          u s e r dot e m a i l spc t a r s ret
type_keys c a t spc slash c o n f i g slash g i t c o n f i g ret

if ! wait_for_screen "email = tars"; then
  fail "git config --global did not land in /config (did the .gitconfig link resolve?)" \
    "terminal: screen>" "No such file"
fi
echo "the global gitconfig resolved through the link into /config"

# ── 검사 14: add와 commit이 돈다 ────────────────────────────────────────
#
# **신원이 검사 13에 달려 있다.** 게스트의 호스트 이름이 `(none)`이라 git이
# 이메일을 자동으로 못 만들고, 설정이 없으면 커밋이 이렇게 죽는다:
#
#   fatal: unable to auto-detect email address (got 'root@(none).(none)')
#
# 이름은 안 줘도 된다 — /etc/passwd의 gecos에서 `root`가 온다(UT-M0의 뼈대).
# **그래서 검사 13이 실패하면 이 검사도 실패하고, 순서가 그 인과를 그대로
# 보여 준다.**
#
# 판정 `root-commit`은 git이 첫 커밋에만 찍는 글자다 — `[main (root-commit)
# 4204d69] one`. 타이핑한 명령줄에도, 다른 어느 검사에도 없다.
echo "=== typing 'cd r', 'touch a', 'git add a', 'git commit -m one' ==="
type_keys c d spc r ret
if ! wait_for_screen "/t/r"; then
  fail "the shell never moved into the new repository" "terminal: screen>"
fi

type_keys t o u c h spc a ret
type_keys g i t spc a d d spc a ret
type_keys g i t spc c o m m i t spc minus m spc o n e ret

if ! wait_for_screen "root-commit"; then
  fail "git did not record a first commit" \
    "terminal: screen>" "Unknown command" "error while loading"
fi
echo "git recorded a first commit"

# ── 검사 15: log가 돈다 — **한 줄이 둘을 증명한다** ─────────────────────
#
# **`--no-pager`가 없으면 이 체인이 매달린다.** Debian git의 기본 페이저는
# alternatives 이름 `pager`이고, make_initrd.sh가 그것을 less로 걸어 뒀다.
# less는 화면을 통째로 가져가는 대화형이라 sendkey로 열면 체인이 실패가
# 아니라 **타임아웃**으로 죽는다(design 실측 26의 less·top과 같다).
# **사람이 치는 모양(`git log`)과 게이트가 치는 모양이 다른 자리이고,
# 그 차이가 여기 적혀 있어야 한다.**
#
# 판정 `Author: root <tars>`가 한 줄로 둘을 증명한다.
#   root    /etc/passwd의 gecos에서 왔다 — **UT-M0의 뼈대**
#   tars    검사 13이 /config에 쓴 값이다 — **결정 8**
# 둘 중 하나라도 안 서면 이 줄이 안 나온다.
echo "=== typing 'git --no-pager log' ==="
type_keys g i t spc minus minus n o minus p a g e r spc l o g ret

if ! wait_for_screen "Author: root <tars>"; then
  fail "git log did not show the author we configured" \
    "terminal: screen>" "cannot run pager"
fi
echo "git log named the author the passwd bone and /config together made"

# ── 검사 16: vi가 **우리가 준 이름으로** 돈다 ───────────────────────────
#
# 편집기를 여는 것은 안 한다 — 화면을 통째로 가져가는 대화형이라 htop·btop·
# ncdu·less·top과 같은 자리다. **다만 `--version`은 찍고 즉시 끝나므로 그
# 다섯과 달리 바이너리가 도는 것까지는 본다.**
#
# **판정이 첫 줄이 아니라 마지막 줄인 것에 이유가 있다.** 처음에는
# `VIM - Vi IMproved`로 잡았는데 **화면 프레임 어디에도 그 글자가 없었다**
# (2026-09-11 실측, 0회). 출력 약 50줄이 한 번에 오고, 프레임이 그려질 때는
# 첫 줄이 이미 스크롤로 사라진 뒤다. `Linking: gcc`는 출력의 마지막 줄이라
# 프롬프트와 함께 화면에 남는다.
#
# **긴 출력을 내는 명령의 판정은 마지막까지 남는 줄로 잡는다** — 이 저장소가
# dmesg를 안 치는 이유(출력이 화면을 뒤덮는다)의 뒷면이다.
echo "=== typing 'vi --version' ==="
type_keys v i spc minus minus v e r s i o n ret

if ! wait_for_screen "Linking: gcc"; then
  fail "vi did not print its version under the name we gave it" \
    "terminal: screen>" "Unknown command" "error while loading"
fi
echo "vi ran under the name we gave it"

# ── 검사 17: 음성 확인 — **위의 아홉 전부에 대해** ──────────────────────
#
# fish는 못 찾은 명령에 `Unknown command`를 낸다. 이 검사가 맨 뒤에 있는
# 이유가 그것이다 — ls · ps · awk · sed · eza · fd · jq · git · vi 아홉을
# 다 친 뒤에 한 번 보면 아홉 전부의 음성 확인이 된다. UT-M0 때는 ls
# 하나뿐이라 바로 뒤에 있었다.
#
# **번호가 11에서 17로 뛴 것은 UT-M3이 검사 다섯을 앞에 끼웠기 때문이다** —
# 음성 확인은 언제나 맨 뒤이고, 앞에 무엇이 늘든 이 검사는 늘어난 것까지
# 함께 본다. 그것이 이 자리의 값이다.
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
