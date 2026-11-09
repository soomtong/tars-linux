#!/usr/bin/env bash
# clojure CLI(clojure/brew-install의 clojure-tools tarball)를 묶음 뿌리에 깐다 — manifest.toml의 `hook = "clojure-tools"`(TP-M5 plan 결정 C · D).
#
#   clojure-tools.sh <tarball> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/clojure-1.12.6.1673)>
#
# tarball은 풀기만 해서는 서지 않는다. 스크립트 둘에 자리표(`clojure`의 PREFIX, `clj`의 BINDIR)가 있고, 동봉 install.sh가
# ruby로 그것을 바꿔 넣는다(plan 확인 4). 여기서 install.sh와 같은 일을 sed로 한다:
#   deps.edn · example-deps.edn · tools.edn → 도구 디렉터리, *.jar → libexec/, clojure · clj → bin/, man 둘 → share/man/man1/
# 그리고 bin/clojure에 첫 실행 시드 줄을 넣는다(결정 D) — 시드 자체(seed/m2/)는 다음 매니페스트 줄(`maven`, into=clojure)이 놓는다.
set -euo pipefail

tarball="${1:?usage: clojure-tools.sh <tarball> <root> <dir>}"
root="${2:?}"
dir="${3:?}"
prefix="/${dir}"
dest="${root}/${dir}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xf "${tarball}" -C "${work}" --no-same-owner
src="${work}/clojure-tools"
for f in clojure clj deps.edn example-deps.edn tools.edn clojure.1 clj.1; do
  [[ -f "${src}/${f}" ]] || { echo "not a clojure-tools tarball (no clojure-tools/${f})" >&2; exit 1; }
done

# 시드의 표시 파일 — root deps가 고른 clojure 판의 jar. 이것이 ~/.m2에 있으면 시드를 이미 채웠거나 사용자가 받은 것이다.
clj_version="$(sed -n 's|.*org.clojure/clojure {:mvn/version "\([^"]*\)"}.*|\1|p' "${src}/deps.edn")"
[[ -n "${clj_version}" ]] || { echo "deps.edn names no org.clojure/clojure version" >&2; exit 1; }
marker="org/clojure/clojure/${clj_version}/clojure-${clj_version}.jar"

mkdir -p "${dest}/bin" "${dest}/libexec" "${dest}/share/man/man1"
cp "${src}/deps.edn" "${src}/example-deps.edn" "${src}/tools.edn" "${dest}/"
cp "${src}"/*.jar "${dest}/libexec/"
cp "${src}/clojure.1" "${src}/clj.1" "${dest}/share/man/man1/"

grep -qx 'install_dir=PREFIX' "${src}/clojure" || { echo "clojure has no 'install_dir=PREFIX' line" >&2; exit 1; }
grep -qx 'bin_dir=BINDIR' "${src}/clj" || { echo "clj has no 'bin_dir=BINDIR' line" >&2; exit 1; }
# 시드 줄은 install_dir= 바로 뒤에 넣는다 — 그 아래의 본문이 ~/.m2를 처음 읽기 전이다.
awk -v prefix="${prefix}" -v marker="${marker}" '
  $0 == "install_dir=PREFIX" {
    print "install_dir=" prefix
    print "# TARS(TP-M5 plan 결정 D): 첫 실행이 Maven Central에서 받을 jar를 묶음의 사본(seed/m2)에서 ~/.m2로 채운다 — 망 없이 선다."
    print "# 이미 있는 파일은 건드리지 않는다. ~/.m2를 지우면 다음 실행에 다시 채운다."
    print "if [[ -d \"$install_dir/seed/m2\" && ! -e \"$HOME/.m2/repository/" marker "\" ]]; then"
    print "  mkdir -p \"$HOME/.m2/repository\" && cp -r --update=none \"$install_dir/seed/m2/.\" \"$HOME/.m2/repository/\" || true"
    print "fi"
    next
  }
  { print }
' "${src}/clojure" >"${dest}/bin/clojure"
sed "s|^bin_dir=BINDIR\$|bin_dir=${prefix}/bin|" "${src}/clj" >"${dest}/bin/clj"
chmod 0755 "${dest}/bin/clojure" "${dest}/bin/clj"
if grep -q 'PREFIX\|BINDIR' "${dest}/bin/clojure" "${dest}/bin/clj"; then
  echo "a placeholder is left in bin/clojure or bin/clj" >&2
  exit 1
fi

# man은 /usr/local/share/man에 링크한다 — man-db가 /usr/local/bin의 짝으로 그 자리를 본다.
mkdir -p "${root}/usr/local/share/man/man1"
for m in clojure.1 clj.1; do
  ln -s "../../../lib/$(basename "${dir}")/share/man/man1/${m}" "${root}/usr/local/share/man/man1/${m}"
done
echo "installed into ${prefix} (seed marker ${marker})"
