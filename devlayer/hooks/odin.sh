#!/usr/bin/env bash
# odin을 묶음 뿌리에 깐다 — manifest.toml의 `hook = "odin"`(OD design 결정 1 · 2).
#
#   odin.sh <tarball> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/odin-dev-2026-11a)>
#
# 푸는 것은 다른 upstream 줄과 같다(맨 위 디렉터리 하나를 벗긴다). 더하는 것이 하나다: bin/odin 런처. odin은 링크 드라이버로 clang을
# 부르는데 TARS에는 clang이 없다(TP-M2 — LLVM 툴체인을 뺐다). ODIN_CLANG_PATH가 그 이름을 바꾸고 base의 gcc가 링크를 맡는다
# (measurements 104). 환경 변수를 rc 조각에 두면 대화형 셸에만 닿으므로 실행 파일 자리에 런처를 둔다. 런처는 변수가 비었을 때만 채운다 —
# 사용자가 clang을 깔고 ODIN_CLANG_PATH를 주면 그쪽이다. odin은 자기 자리를 진짜 실행 파일의 경로에서 찾으므로(odin root) 런처를 거쳐도
# core:가 풀린다. tarball 맨 위의 목록이 아는 일곱과 다르면(판이 바뀌었으면) 멈춘다.
set -euo pipefail

tarball="${1:?usage: odin.sh <tarball> <root> <dir>}"
root="${2:?}"
dir="${3:?}"
dest="${root}/${dir}"

want="LICENSE base core examples odin shared vendor"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xf "${tarball}" -C "${work}" --no-same-owner
tops=("${work}"/*)
((${#tops[@]} == 1)) && [[ -d "${tops[0]}" ]] || { echo "expected one top directory in the odin tarball" >&2; exit 1; }
have="$(find "${tops[0]}" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ')"
[[ "${have% }" == "${want}" ]] || { echo "odin tarball holds '${have% }', expected '${want}' (new odin version?)" >&2; exit 1; }

mkdir -p "${dest}/bin"
cp -a "${tops[0]}/." "${dest}/"
cat >"${dest}/bin/odin" <<EOF
#!/bin/bash
# TARS 런처(devlayer/hooks/odin.sh): clang 대신 gcc로 링크한다. ODIN_CLANG_PATH를 주면 그 값이 이긴다.
: "\${ODIN_CLANG_PATH:=gcc}"
export ODIN_CLANG_PATH
exec -a odin /${dir}/odin "\$@"
EOF
chmod 0755 "${dest}/bin/odin"
echo "wrote the bin/odin launcher (ODIN_CLANG_PATH defaults to gcc)"
