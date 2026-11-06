#!/usr/bin/env bash
# builds.hex.pm의 Erlang/OTP 빌드를 묶음 뿌리에 깐다 — manifest.tsv의 `hook=otp-install`(TP-M6 plan 결정 C).
#
#   otp-install.sh <tarball> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/erlang-29.1.2)>
#
# tarball(맨 위 OTP-<판>/)은 풀기만 해서는 bin/erl이 없다. 동봉 Install이 erts-*/bin/erl.src의 %FINAL_ROOTDIR%에 경로를 박고
# 실행 파일 · 부트 파일을 bin/에 놓는다(plan 확인 2). Install은 sed · cp뿐이라 arm64 빌드 컨테이너에서도 돈다. `-cross`는 파일이 있는
# 자리(pwd — 빌드 중의 뿌리)와 박을 경로(인자 — 실행 때의 /usr/local/lib/…)를 가른다. `-minimal`은 시작 방식을 묻지 않는다.
set -euo pipefail

tarball="${1:?usage: otp-install.sh <tarball> <root> <dir>}"
root="${2:?}"
dir="${3:?}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xf "${tarball}" -C "${work}" --no-same-owner
mapfile -t tops < <(find "${work}" -mindepth 1 -maxdepth 1)
((${#tops[@]} == 1)) && [[ -d "${tops[0]}" && -x "${tops[0]}/Install" ]] \
  || { echo "expected one OTP-<version>/ directory with Install, got ${#tops[@]} entries" >&2; exit 1; }

cp -a "${tops[0]}/." "${root}/${dir}/"
(cd "${root}/${dir}" && ./Install -cross -minimal "/${dir}" >/dev/null)

# Install이 지나간 자리 — 자리표가 남으면 erl이 엉뚱한 뿌리를 찾는다.
for f in bin/erl bin/start "${root}/${dir}"/erts-*/bin/erl; do
  f="${f#"${root}/${dir}/"}"
  [[ -f "${root}/${dir}/${f}" ]] || { echo "Install left no ${f}" >&2; exit 1; }
  if grep -q '%FINAL_ROOTDIR%' "${root}/${dir}/${f}"; then
    echo "${f} still has %FINAL_ROOTDIR%" >&2
    exit 1
  fi
done
grep -q "/${dir}\"" "${root}/${dir}/bin/erl" || { echo "bin/erl does not name /${dir}" >&2; exit 1; }
echo "installed into /${dir} ($(basename "${tops[0]}"), start_clean)"
