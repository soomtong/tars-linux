#!/usr/bin/env bash
# gleam(musl 정적 바이너리 하나)를 묶음 뿌리에 깐다 — manifest.toml의 `hook = "gleam"`(TP-M6 plan 결정 D, 사용자 결정).
#
#   gleam.sh <tarball> <묶음 뿌리> <도구 디렉터리(뿌리 기준, 예: usr/local/lib/gleam-1.19.2)>
#
# gleam new가 만든 프로젝트는 표준 라이브러리까지 Hex에서 받는다. 판을 고르려 레지스트리에 묻기 때문에 캐시만 채워서는 망 없이 안
# 서고, 판을 고정한 manifest.toml이 있어야 한다(plan 확인 4). 그래서 진짜 바이너리는 libexec/gleam에 두고 bin/gleam은 런처다:
#   1. 실행마다 gleam 캐시에 없는 tarball만 seed/packages/에서 채운다(시드는 다음 매니페스트 줄 — hex, into=gleam).
#   2. libexec/gleam을 부른다.
#   3. `gleam new`가 성공했고, 만든 디렉터리에 manifest.toml이 없고 gleam.toml의 두 요구가 gleam 기본 틀과 같으면 seed/manifest.toml을
#      넣는다(devlayer/files/lang-beam/…/seed/manifest.toml — build.sh가 잠금 파일과 대조한다).
set -euo pipefail

tarball="${1:?usage: gleam.sh <tarball> <root> <dir>}"
root="${2:?}"
dir="${3:?}"
prefix="/${dir}"
dest="${root}/${dir}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
tar -xf "${tarball}" -C "${work}" --no-same-owner
[[ -f "${work}/gleam" && -x "${work}/gleam" ]] || { echo "not a gleam tarball (no executable gleam at the top)" >&2; exit 1; }

mkdir -p "${dest}/bin" "${dest}/libexec"
cp "${work}/gleam" "${dest}/libexec/gleam"

cat >"${dest}/bin/gleam" <<EOF
#!/usr/bin/env bash
# TARS의 gleam 런처(TP-M6 plan 결정 D) — 진짜 gleam은 ${prefix}/libexec/gleam이다. 망 없이 새 프로젝트가 서게 한다:
# 캐시 시드를 채우고, gleam new 뒤 판을 고정한 manifest.toml을 넣는다(gleam_stdlib · gleeunit — 최신은 망이 있을 때 gleam update).
here=${prefix}
EOF
cat >>"${dest}/bin/gleam" <<'EOF'
cache="${XDG_CACHE_HOME:-$HOME/.cache}/gleam/hex/hexpm/packages"
if [[ -d "$here/seed/packages" ]]; then
  mkdir -p "$cache" && cp -r --update=none "$here/seed/packages/." "$cache/" 2>/dev/null || true
fi
"$here/libexec/gleam" "$@"
rc=$?
if [[ $rc -eq 0 && "${1:-}" == new && -f "$here/seed/manifest.toml" ]]; then
  shift
  dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name | --template) shift 2 ;;
      -*) shift ;;
      *) dir="$1"; shift ;;
    esac
  done
  if [[ -n "$dir" && -f "$dir/gleam.toml" && ! -e "$dir/manifest.toml" ]] \
    && grep -qx 'gleam_stdlib = ">= 1.0.0 and < 2.0.0"' "$dir/gleam.toml" \
    && grep -qx 'gleeunit = ">= 1.0.0 and < 2.0.0"' "$dir/gleam.toml"; then
    cp "$here/seed/manifest.toml" "$dir/manifest.toml"
  fi
fi
exit $rc
EOF
chmod 0755 "${dest}/bin/gleam"
echo "installed into ${prefix} (libexec/gleam and the bin/gleam launcher)"
