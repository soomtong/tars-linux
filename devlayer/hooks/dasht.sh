#!/usr/bin/env bash
# dasht(셸 스크립트 묶음)를 묶음 뿌리에 깐다 — manifest.tsv의 `hook=dasht`(TP-M9 plan 확인한 것).
#
#   dasht.sh <tarball> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/dasht-2.4.0)>
#
# 푸는 것은 다른 upstream 줄과 같다(맨 위 디렉터리 하나를 벗긴다). 고치는 것이 한 줄 있다: dasht-query-line은 `sqlite3 -line`의
# 출력을 공백으로 갈라 `$1 == "url"` · `$3 = 값`으로 읽는다 — `name = printf` 모양이다. util의 sqlite 3.54는 line 모드가
# `name: printf`를 찍어 결과가 하나도 file:// URL이 되지 못하고 dasht(w3m 결과 페이지)가 빈다. `-separator ' = '`를 더하면 3.54도
# 옛 모양을 찍고, trixie의 3.46에서도 결과가 같다. upstream 파일을 저장소에 싣지 않으려고 이 자리에서 한 줄만 고친다. 그 줄이
# 정확히 한 번 있지 않으면(판이 바뀌었으면) 멈춘다.
set -euo pipefail

tarball="${1:?usage: dasht.sh <tarball> <root> <dir>}"
root="${2:?}"
dir="${3:?}"
dest="${root}/${dir}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xf "${tarball}" -C "${work}" --no-same-owner
mapfile -t tops < <(find "${work}" -mindepth 1 -maxdepth 1 -type d)
((${#tops[@]} == 1)) || { echo "expected one top directory, got ${#tops[@]}" >&2; exit 1; }
src="${tops[0]}"
[[ -f "${src}/bin/dasht-query-line" ]] || { echo "not a dasht tarball (no bin/dasht-query-line)" >&2; exit 1; }

# shellcheck disable=SC2016 # 찾는 글자 그대로다($는 펼치지 않는다)
old='  dasht-query-exec "$pattern" "$database" -line |'
new="  dasht-query-exec \"\$pattern\" \"\$database\" -line -separator ' = ' |"
n="$(grep -cxF -- "${old}" "${src}/bin/dasht-query-line" || true)"
[[ "${n}" == 1 ]] || { echo "bin/dasht-query-line: expected the sqlite3 -line call once, found ${n} (new dasht version?)" >&2; exit 1; }
awk -v old="${old}" -v new="${new}" '$0 == old { print new; next } { print }' "${src}/bin/dasht-query-line" >"${work}/q"
cat "${work}/q" >"${src}/bin/dasht-query-line"

mkdir -p "${dest}"
cp -a "${src}/." "${dest}/"
echo "patched bin/dasht-query-line: sqlite3 -line -separator ' = '"
