#!/usr/bin/env bash
# Freedoom을 tars-doom의 자리에 깐다 — manifest.toml의 `hook = "freedoom"`(WY-M1 plan 확정 9).
#
#   freedoom.sh <zip> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/tars-doom-0.1.0)>
#
# zip(freedoom-0.13.0/ 아래 WAD 둘 · PDF 셋 · 글 몇)에서 셋만 꺼낸다: freedoom1.wad(Phase 1 — 포트가 -iwad 없이 여는 것),
# COPYING.txt(BSD 3조항 — 바이너리로 재배포할 때 고지를 함께 싣는 조건), CREDITS.txt. 놓는 자리는 <도구 디렉터리>/share/doom/이다 —
# 포트가 /proc/self/exe(심볼릭 링크를 푼 /usr/local/lib/tars-doom-<판>/bin/tars-doom)의 ../share/doom/freedoom1.wad를 연다.
# 셋 중 하나라도 zip에 없으면(판이 바뀌었으면) 멈춘다.
set -euo pipefail

zip="${1:?usage: freedoom.sh <zip> <root> <dir>}"
root="${2:?}"
dir="${3:?}"
dest="${root}/${dir}/share/doom"

[[ -x "${root}/${dir}/bin/tars-doom" ]] || { echo "no ${dir}/bin/tars-doom — put the freedoom line after tars-doom" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
want=(freedoom1.wad COPYING.txt CREDITS.txt)
# -j: zip 안의 맨 위 디렉터리(freedoom-<판>/)를 버린다. 이름은 글롭이 아니라 정확한 경로라 다른 파일이 따라오지 않는다.
# 목록을 변수로 먼저 받는다(`unzip | head`의 SIGPIPE가 pipefail로 올라오지 않게).
list="$(unzip -Z1 "${zip}")"
top="${list%%/*}"
paths=()
for f in "${want[@]}"; do paths+=("${top}/${f}"); done
unzip -q -j "${zip}" "${paths[@]}" -d "${work}"
for f in "${want[@]}"; do
  [[ -s "${work}/${f}" ]] || { echo "${top}/${f} is not in the zip (new freedoom version?)" >&2; exit 1; }
done
mkdir -p "${dest}"
install -m 0644 "${work}/freedoom1.wad" "${work}/COPYING.txt" "${work}/CREDITS.txt" "${dest}/"
echo "put ${want[*]} from ${top} in /${dir}/share/doom"
