#!/usr/bin/env bash
# quick_check.sh — 게이트가 아닌, 1분 안에 끝나는 검사(GH-M0 design 결정 3).
#
# 사람은 `make quick`으로, CI는 .github/workflows/checks.yml의 host job이 같은 파일을
# 돌린다. 명령을 두 벌 두지 않으려고 스크립트 하나에 모았다 — lessons "범용 명령"에
# 손으로 치던 Zig 세 줄이 여기로 왔다.
#
# 단계는 다섯이다. 셸 스크립트(shellcheck) · Zig 서식(fmt --check) · Zig 문법(ast-check) ·
# shared/의 순수 검사(zig run) · init의 크로스 빌드(zig build). 빌드 산출물은 out/quick/
# 아래에만 두어 init/zig-out(initrd가 싣는 원본)을 건드리지 않는다.
#
# 도구는 PATH의 shellcheck · zig다. 버전이 아래와 다르면 한 줄 찍고 계속 돈다 — 실패가
# 아니다. 호스트 Mac은 Homebrew가 올리는 대로 따라가고, CI와 답이 다르면 그 줄이 이유다.
# 셸 검사기의 버전은 여기(SHELLCHECK_VERSION)가 정본이고, Zig 버전은 devcontainer/Dockerfile의
# ENV ZIG_VERSION이 정본이다(ZU가 올릴 때 고칠 자리 하나). 주석 줄을 "# shellcheck"로 시작하면
# 지시자로 읽히므로(SC1073) 그 글자로 시작하지 않는다.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

SHELLCHECK_VERSION=0.11.0
ZIG_VERSION="$(sed -n 's/^ENV ZIG_VERSION=\([0-9.]*\).*/\1/p' devcontainer/Dockerfile)"

failed=()
note() { printf 'quick_check: %s\n' "$*"; }

for tool in shellcheck zig; do
  command -v "$tool" >/dev/null 2>&1 || { note "$tool is not on PATH"; exit 2; }
done
have_sc="$(shellcheck --version | sed -n 's/^version: //p')"
have_zig="$(zig version)"
[ "$have_sc" = "$SHELLCHECK_VERSION" ] || note "shellcheck is $have_sc, this file expects $SHELLCHECK_VERSION"
[ "$have_zig" = "$ZIG_VERSION" ] || note "zig is $have_zig, Dockerfile says $ZIG_VERSION"

# 1. shellcheck. 대상은 추적 중인 *.sh 전부와, 확장자 없이 게스트에 들어가는 둘이다.
#    추적 파일 기준이라 terminal/vendor · ghostty-src · out/은 안 걸린다. -x -P SCRIPTDIR은
#    `source ../gate_lib.sh`를 스크립트 위치 기준으로 따라가게 한다(없으면 SC1091 28줄).
#    판정은 style 이상(-S style), 곧 note까지 전부다. GH-M0은 warning 이상만 판정하고 note 46은 수만
#    찍었는데, SN-M0이 그 46을 고치거나 지시자로 표시해 0으로 만들고 판정을 내렸다. 의도한 것은 그 줄
#    위에 지시자와 이유를 단다 — trap · 콜백 함수의 SC2329는 파일 끝이 exit일 때 shellcheck가 헛짚는 것이다.
mapfile -t sh_files < <(git ls-files '*.sh')
sh_files+=(kernel/wifi/tars-wifi kernel/dictation/tars-dictate)
note "shellcheck ${#sh_files[@]} files"
if shellcheck -x -P SCRIPTDIR -S style "${sh_files[@]}"; then
  :
else
  failed+=(shellcheck)
fi

# 2. Zig 서식. 디렉터리는 재귀다.
zig fmt --check init/build.zig terminal/build.zig init/src terminal/src shared || failed+=(zig-fmt)

# 3. Zig 문법. 컨테이너 컴파일러가 거부하지 않는 문법이 다시 들어오는 것을 여기서 본다(ZU).
ast_failed=0
while IFS= read -r f; do
  zig ast-check "$f" || { echo "ast-check FAIL $f"; ast_failed=1; }
done < <(find init/src terminal/src shared -name '*.zig' | sort)
[ "$ast_failed" = 0 ] || failed+=(zig-ast-check)

# 4. shared/의 순수 검사. libc · 시스템 콜이 없어 어느 호스트에서나 돈다(SA-M1).
zig run shared/screen_args_test.zig || failed+=(shared-test)

# 5. init의 크로스 빌드. build.zig가 target을 x86_64-linux로 고정하고 libc를 안 쓰므로
#    호스트가 무엇이든 같은 산출물 넷이 나온다. `zig build test`(호스트 검사)는 Linux
#    컨테이너의 몫이라 여기 없다(design 확인 5).
mkdir -p out/quick
(cd init && zig build --prefix ../out/quick/init --cache-dir ../out/quick/init-cache) || failed+=(init-build)

if [ "${#failed[@]}" = 0 ]; then
  note PASS
  exit 0
fi
note "FAIL: ${failed[*]}"
exit 1
