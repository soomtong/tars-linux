#!/usr/bin/env bash
# rust의 standalone 설치기(rust-installer 형식)를 묶음 뿌리에 깐다 — manifest.tsv의 `hook=rust-installer`(TP-M2 plan 결정 C).
#
#   rust-installer.sh <tarball> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/rust-1.99.1)>
#
# tarball은 설치기다. 풀기만 해서는 bin/이 서지 않고 컴포넌트 디렉터리 열하나와 install.sh가 나온다(plan 확인 2).
# install.sh는 파일을 복사하는 셸 스크립트라 arm64 개발 컨테이너에서도 돈다. 아래 허용 목록 가운데 그 tarball에 있는 것만
# 깐다 — rust 본체 tarball에는 rust-src가 없고, rust-src tarball에는 rust-src 하나뿐이다. 같은 자리에 두 번 깔아도
# 설치기는 자기가 까는 컴포넌트만 먼저 지운다(install.sh의 uninstall_components).
set -euo pipefail

tarball="${1:?usage: rust-installer.sh <tarball> <root> <dir>}"
root="${2:?}"
dir="${3:?}"

# 싣는 것. 빼는 것은 llvm-tools-preview(LLVM 툴체인은 사용자 결정으로 뺐다) · rust-docs-json-preview · rust-analysis ·
# llvm-bitcode-linker-preview. rust-docs는 오프라인 문서(TP design 결정 19)다 — share/doc/rust/html, w3m으로 읽는다.
allow="rustc cargo rust-std-x86_64-unknown-linux-gnu rustfmt-preview clippy-preview rust-analyzer-preview rust-docs rust-src"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xf "${tarball}" -C "${work}" --no-same-owner
mapfile -t tops < <(find "${work}" -mindepth 1 -maxdepth 1 -type d)
((${#tops[@]} == 1)) || { echo "expected one top directory, got ${#tops[@]}" >&2; exit 1; }
src="${tops[0]}"
[[ -f "${src}/install.sh" && -f "${src}/components" ]] || { echo "not a rust-installer tarball (no install.sh or components)" >&2; exit 1; }

picked=()
while IFS= read -r c; do
  for a in ${allow}; do
    [[ "${c}" == "${a}" ]] && picked+=("${c}")
  done
done <"${src}/components"
((${#picked[@]} > 0)) || { echo "none of the allowed components is in this tarball" >&2; exit 1; }
list="$(IFS=,; echo "${picked[*]}")"

bash "${src}/install.sh" --prefix="/${dir}" --destdir="${root}" --disable-ldconfig --components="${list}" >"${work}/install.out" 2>&1 \
  || { cat "${work}/install.out" >&2; exit 1; }

# 설치기의 기록(lib/rustlib/manifest-<컴포넌트>)은 destdir를 붙인 절대 경로다. destdir는 build.sh의 mktemp라 매번 달라서
# 그대로 두면 같은 입력이 다른 묶음이 된다. 게스트에서의 경로(/usr/local/lib/…)로 고친다. install.log는 그 경로와 시각만
# 담은 설치 기록이라 지운다.
md="${root}/${dir}/lib/rustlib"
for m in "${md}"/manifest-*; do
  sed -i "s#:${root}/#:/#" "${m}"
done
rm -f "${md}/install.log"
grep -l "${root}" "${md}"/* 2>/dev/null && { echo "the installer left ${root} in the files above" >&2; exit 1; }

# rust-objcopy의 RUNPATH는 $ORIGIN/../lib(= rustlib/x86_64-unknown-linux-gnu/lib)인데 그것이 끄는 libLLVM은 두 층 위
# lib/에 있다. rustup은 LD_LIBRARY_PATH로 덮지만 TARS에는 rustup이 없다 — verify.sh의 NEEDED가 잡았다(TP-M2 확인한 것).
# 그 자리에 상대 링크 하나를 두어 실제로 풀리게 한다. 같은 라이브러리를 가리키므로 rust-lld($ORIGIN/../../../)와 같은 것이 올라온다.
tlib="${md}/x86_64-unknown-linux-gnu/lib"
if [[ -f "${md}/x86_64-unknown-linux-gnu/bin/rust-objcopy" ]]; then
  for so in "${root}/${dir}/lib/"libLLVM.so.*; do
    [[ -e "${so}" ]] || continue
    name="$(basename "${so}")"
    [[ -e "${tlib}/${name}" || -L "${tlib}/${name}" ]] && continue
    ln -s "../../../${name}" "${tlib}/${name}"
    echo "linked rustlib/x86_64-unknown-linux-gnu/lib/${name} for rust-objcopy"
  done
fi

echo "installed ${list}"
