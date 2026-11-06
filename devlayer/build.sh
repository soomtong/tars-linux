#!/usr/bin/env bash
# 개발 도구 층의 묶음 하나를 굽는다(TP design 결정 1~7, TP-M0 plan). 개발 컨테이너 안에서 돈다 — make dev-layers가
# 묶음마다 harvest.sh(amd64 컨테이너) 다음에 부른다.
#
#   build.sh <묶음>             devlayer/build/<묶음>.sqfs
#   DEV_MEASURE=1 build.sh ...  압축 넷의 크기 · 굽는 시간 · 한 코어로 다 읽는 시간도 잰다(plan 결정 J)
#
# 순서: 매니페스트 → 뿌리 만들기(debian은 harvest tar, upstream은 받기 · sha256 · 풀기) → verify.sh → 굽기.
#
# 뿌리는 컨테이너 안의 임시 디렉터리다. /workspace(macOS의 APFS를 붙인 자리)는 대소문자를 가리지 않아서
# linux-libc-dev의 xt_MARK.h · xt_mark.h 같은 쌍이 한쪽으로 덮인다. 그 자리에는 파일 하나짜리(tar · sqfs)만 둔다.
#
# 굽기는 stamp가 같으면 건너뛴다(결정 6). stamp는 매니페스트 줄 · harvest 결과 · 이 디렉터리의 스크립트 · 압축 ·
# verify가 지운 경로 목록의 sha256이다. 뒤의 것이 들어가는 이유: initrd가 바뀌어 겹치는 경로가 달라지면 같은 입력이라도
# 다른 묶음이어야 한다. 그래서 뿌리 만들기와 verify는 매번 돈다(base 기준 수십 초).
set -euo pipefail

cd "$(dirname "$0")/.."
bundle="${1:?usage: build.sh <bundle>}"
build=devlayer/build
cache=devlayer/cache
initrd=kernel/initrd.cpio
# 압축(plan 결정 J). 이름 넷: gzip · xz · zstd15 · zstd19.
comp="${DEV_COMP:-zstd15}"
mkdir -p "${build}" "${cache}"

die() { echo "build> ${bundle}: $*" >&2; exit 1; }

# shellcheck source=devlayer/manifest.sh
source devlayer/manifest.sh
lines="$(manifest_lines "${bundle}")" || die "${DEVLAYER_MANIFEST} has errors (above)"
[[ -n "${lines}" ]] || die "no manifest lines"
[[ -f "${initrd}" ]] || die "${initrd} is missing — run make initrd first"

comp_args() {
  case "$1" in
    gzip) echo "-comp gzip" ;;
    xz) echo "-comp xz -Xbcj x86" ;;
    zstd15) echo "-comp zstd -Xcompression-level 15" ;;
    zstd19) echo "-comp zstd -Xcompression-level 19" ;;
    *) die "unknown compression $1" ;;
  esac
}
comp_args "${comp}" >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
root="${work}/${bundle}"
ir="${work}/initrd"
mkdir -p "${root}" "${ir}"

# ── initrd의 첫 archive를 푼다(plan 결정 G) ─────────────────────────────
# 파이프 안에서 gzip -dc를 하면 cpio가 첫 archive의 끝 표시에서 멈출 때 gzip이 EPIPE로 죽고 pipefail이 그것을 실패로
# 올린다. 그래서 파일로 받는다. 꼬리의 firmware(lib/firmware)는 /usr와 안 겹친다.
gzip -dc "${initrd}" >"${work}/initrd.cpio" 2>/dev/null || [[ -s "${work}/initrd.cpio" ]] || die "cannot read ${initrd}"
(cd "${ir}" && cpio -idm --quiet --no-absolute-filenames <"${work}/initrd.cpio" 2>/dev/null) || true
# initrd의 공유 라이브러리는 /lib/x86_64-linux-gnu에 있다(merged-usr가 아니다 — bin만 usr/bin으로의 링크).
libc="${ir}/lib/x86_64-linux-gnu/libc.so.6"
[[ -e "${libc}" ]] || die "initrd has no lib/x86_64-linux-gnu/libc.so.6 — extraction failed"
rm -f "${work}/initrd.cpio"

# ── 뿌리 만들기 ─────────────────────────────────────────────────────────
mkdir -p "${root}/usr/share/tars/layers"
harvest_lines=""
info="${root}/usr/share/tars/layers/${bundle}.pkgs"
: >"${info}"

while IFS=$'\t' read -r tool _b version kind url sha opts; do
  case "${kind}" in
    debian)
      # libc6-dev는 initrd의 glibc와 같은 판이어야 한다(plan 결정 B). 헤더 · crt가 다른 판이면 빌드가 되어도 링크된
      # 실행 파일이 initrd의 libc.so.6와 어긋난다.
      if [[ "${tool}" == libc6-dev ]]; then
        have="$(grep -a -o -m1 'Debian GLIBC [^)]*' "${libc}" | sed 's/^Debian GLIBC //')"
        [[ "${have}" == "${version}" ]] || die "libc6-dev ${version} but the initrd glibc is ${have}"
      fi
      ;;
    upstream | prebuilt)
      # 둘은 받는 자리만 다르고(도구 자신 · 표준이 된 제3자) 받기 · 풀기 · 놓기는 같다(design 결정 2).
      f="${cache}/${sha}"
      if [[ ! -f "${f}" ]]; then
        echo "build> ${bundle}: fetch ${tool} ${version}"
        curl -fL --retry 4 --retry-all-errors -o "${f}.part" "${url}"
        # 옮기기 전에 본다 — 틀린 바이트가 캐시 이름을 얻으면 다음 실행이 그것을 믿는다.
        got="$(sha256sum "${f}.part" | cut -c1-64)"
        [[ "${got}" == "${sha}" ]] || die "${tool}: downloaded sha256 ${got}, manifest says ${sha} (kept ${f}.part)"
        mv "${f}.part" "${f}"
      fi
      got="$(sha256sum "${f}" | cut -c1-64)"
      [[ "${got}" == "${sha}" ]] || die "${tool}: cached ${f} has sha256 ${got}, manifest says ${sha}"
      # 결정 2: /usr/local/lib/<도구>-<버전>/에 그대로, /usr/local/bin/에 실행 파일 링크. tarball의 맨 위 디렉터리
      # 하나(jdk-25.0.5+8/)는 벗긴다. into=T면 자리가 T-<버전>이다 — 그 줄이 앞에서 이미 만들었어야 한다(TP-M2 결정 C).
      into="$(manifest_opt "${opts}" into)"
      hook="$(manifest_opt "${opts}" hook)"
      exes="$(manifest_opt "${opts}" exe)"
      dir="${into:-${tool}}-${version}"
      dest="usr/local/lib/${dir}"
      if [[ -n "${into}" ]]; then
        [[ -d "${root}/${dest}" ]] || die "${tool}: into=${into} but there is no /${dest} yet (put this line after ${into})"
      fi
      mkdir -p "${root}/${dest}" "${root}/usr/local/bin"
      if [[ -n "${hook}" ]]; then
        [[ -x "devlayer/hooks/${hook}.sh" ]] || die "${tool}: no devlayer/hooks/${hook}.sh"
        "devlayer/hooks/${hook}.sh" "${f}" "${root}" "${dest}" </dev/null | sed "s/^/build> ${bundle}: ${tool}: /"
      else
        # 풀기는 한 길이다(TP-M3 plan 결정 C): 통째로 풀고 → strip=N단(기본 1)을 벗기고 → 남은 것을 옮긴다. 배포 모양이
        # 넷이다 — 맨 위 디렉터리 하나(대부분), ./로 시작하는 경로(janet — tar가 ./를 벗긴다), 두 단(rv-ruby), 디렉터리
        # 없음(luau · cyber). zip은 URL로 가른다(bun · luau). 캐시 이름이 sha256이라 파일 이름에는 확장자가 없다.
        strip="$(manifest_opt "${opts}" strip)"
        strip="${strip:-1}"
        un="${work}/unpack"
        rm -rf "${un}"
        mkdir -p "${un}"
        case "${url}" in
          *.zip) unzip -q "${f}" -d "${un}" ;;
          *) tar -xf "${f}" -C "${un}" --no-same-owner ;;
        esac
        top="${un}"
        for ((level = 1; level <= strip; level++)); do
          entries=("${top}"/* "${top}"/.[!.]*)
          have=()
          for e in "${entries[@]}"; do [[ -e "${e}" || -L "${e}" ]] && have+=("${e}"); done
          ((${#have[@]} == 1)) && [[ -d "${have[0]}" && ! -L "${have[0]}" ]] \
            || die "${tool}: strip=${strip} but level ${level} has ${#have[@]} entries (want one directory)"
          top="${have[0]}"
        done
        # cp -a — 뿌리(${work})와 같은 파일 시스템이지만 mv로 옮기면 dest가 이미 있는 디렉터리라 그 안에 들어간다.
        cp -a "${top}/." "${root}/${dest}/"
        rm -rf "${un}"
      fi
      # 링크할 것: exe=가 있으면 그 목록, 없으면 bin/의 실행 파일 전부. into 줄은 exe=가 없으면 링크하지 않는다 —
      # 그 bin/은 앞 줄이 이미 링크했다.
      if [[ -n "${exes}" ]]; then
        IFS=, read -r -a want <<<"${exes}"
        for rel in "${want[@]}"; do
          [[ -f "${root}/${dest}/${rel}" && -x "${root}/${dest}/${rel}" ]] || die "${tool}: exe=${rel} is not an executable in /${dest}"
        done
      elif [[ -z "${into}" ]]; then
        want=()
        for exe in "${root}/${dest}/bin/"*; do
          [[ -f "${exe}" && -x "${exe}" ]] && want+=("bin/$(basename "${exe}")")
        done
      else
        want=()
      fi
      # 링크할 것이 없으면 멈춘다 — strip이 틀려 bin/이 한 단 아래 묻히면 말없이 링크 0개로 초록이었다(plan 할 일 5(a)).
      if [[ -z "${into}" && ${#want[@]} -eq 0 ]]; then
        die "${tool}: nothing to link — no exe= and no executables in /${dest}/bin (wrong strip=?)"
      fi
      for rel in "${want[@]}"; do
        name="$(basename "${rel}")"
        link="${root}/usr/local/bin/${name}"
        exists=0
        [[ -e "${link}" || -L "${link}" ]] && exists=1
        ((exists == 0)) || die "${tool}: /usr/local/bin/${name} is taken"
        ln -s "../lib/${dir}/${rel}" "${link}"
      done
      printf '%s\t%s\t%s\t%s\n' "${tool}" "${version}" "${kind}" "${url}" >>"${info}"
      ;;
    *) die "${tool}: kind ${kind} is not built yet" ;;
  esac
done <<<"${lines}"

if grep -q $'\tdebian\t' <<<"${lines}"; then
  tarball="${build}/${bundle}.harvest.tar"
  [[ -f "${tarball}" ]] || die "no ${tarball} — run make dev-layers (harvest.sh)"
  harvest_lines="$(cat "${build}/${bundle}.harvest.lines")"
  [[ "$(head -n -1 <<<"${harvest_lines}")" == "$(awk -F'\t' '$4 == "debian"' <<<"${lines}")" ]] \
    || die "${tarball} is stale — run make dev-layers"
  tar -xpf "${tarball}" -C "${root}"
  cat "${build}/${bundle}.pkgs" >>"${info}"
fi

# 출처 기록 한 줄(git describe). 결정 13의 비교에는 안 쓴다 — 묶음은 stamp로 커밋을 넘어 캐시되므로 이 줄은 ISO의 init
# 버전과 거의 늘 다르다. 비교 대상은 tars-install이 p3에 묶음과 함께 쓰는 `version`이다(TP-M1 plan 결정 E).
git -c safe.directory=/workspace -c safe.directory="${PWD}" describe --always --dirty >"${root}/usr/share/tars/layers/${bundle}"

# ── 검사 ────────────────────────────────────────────────────────────────
devlayer/verify.sh "${root}" "${ir}" devlayer/needed-ignore.tsv | sed "s/^verify>/verify> ${bundle}:/"

files="$(find "${root}" -type f | wc -l)"
bytes="$(du -sb "${root}" | cut -f1)"

# ── 묶음끼리의 대조(TP-M2 plan 결정 E) ──────────────────────────────────
# verify.sh는 initrd와만 대조한다. 묶음이 여럿이면 둘이 같은 경로에 다른 내용을 둘 수 있고, overlay는 lowerdir 앞의 것을
# 말없이 보인다. 경로마다 내용(파일은 sha256, 링크는 대상)을 적어 두고, 매니페스트의 다른 묶음이 남긴 목록과 맞춘다.
# 먼저 구운 쪽은 나중 쪽이 대조하므로 한 방향이면 덮인다. 같은 내용은 센다(shared) — overlay가 하나만 보일 뿐 틀리지 않다.
(
  cd "${root}"
  {
    find . -type l -printf '%P\tL:%l\n'
    find . -type f -print0 | xargs -0 -r sha256sum | sed -E 's#^([0-9a-f]{64})  \./(.*)$#\2\tF:\1#'
  } | LC_ALL=C sort
) >"${work}/${bundle}.paths"
shared=0
for other in $(manifest_bundles); do
  [[ "${other}" != "${bundle}" && -f "${build}/${other}.paths" ]] || continue
  LC_ALL=C join -t $'\t' "${work}/${bundle}.paths" "${build}/${other}.paths" >"${work}/joined"
  n="$(wc -l <"${work}/joined")"
  # 파일을 거친다 — `awk | grep -q`는 grep이 먼저 닫으면 awk가 SIGPIPE로 죽고 pipefail이 조건을 거짓으로 만든다.
  awk -F'\t' -v a="${bundle}" -v b="${other}" '$2 != $3 { printf "build> %s and %s both carry /%s with different contents\n", a, b, $1 }' \
    "${work}/joined" >"${work}/disagree"
  if [[ -s "${work}/disagree" ]]; then
    sed -n '1,20p' "${work}/disagree" >&2
    die "the bundles ${bundle} and ${other} disagree on $(wc -l <"${work}/disagree") paths (above)"
  fi
  shared=$((shared + n))
done
cp "${work}/${bundle}.paths" "${build}/${bundle}.paths"

# ── 굽기 ────────────────────────────────────────────────────────────────
stamp="$(
  {
    printf '%s\n' "${lines}" "${harvest_lines}" "${comp}"
    sha256sum devlayer/build.sh devlayer/verify.sh devlayer/needed-ignore.tsv devlayer/manifest.sh devlayer/hooks/*.sh
    cat "${work}/${bundle}.dropped"
  } | sha256sum | cut -c1-64
)"

bake() { # <압축> <출력>
  local args
  read -r -a args <<<"$(comp_args "$1")"
  mksquashfs "${root}" "$2" -noappend -all-root -mkfs-time 0 -all-time 0 -no-progress -quiet "${args[@]}"
}

sqfs="${build}/${bundle}.sqfs"
if [[ -f "${sqfs}" && "$(cat "${build}/${bundle}.stamp" 2>/dev/null)" == "${stamp}" ]]; then
  state=cached
else
  bake "${comp}" "${work}/out.sqfs"
  mv "${work}/out.sqfs" "${sqfs}"
  echo "${stamp}" >"${build}/${bundle}.stamp"
  state=baked
fi

echo "build> ${bundle}: ${state} files=${files} unpacked=$((bytes / 1048576))MiB ${comp}=$(($(stat -c %s "${sqfs}") / 1048576))MiB dropped=$(grep -cv '^relink ' "${work}/${bundle}.dropped" || true) shared=${shared}"

# ── 압축 넷 재기(plan 결정 J) ───────────────────────────────────────────
if [[ -n "${DEV_MEASURE:-}" ]]; then
  for c in gzip xz zstd15 zstd19; do
    t0="$(date +%s.%N)"
    bake "${c}" "${work}/m.sqfs"
    t1="$(date +%s.%N)"
    unsquashfs -processors 1 -no-progress -quiet -d "${work}/m.out" "${work}/m.sqfs" >/dev/null
    t2="$(date +%s.%N)"
    size="$(stat -c %s "${work}/m.sqfs")"
    rm -rf "${work}/m.sqfs" "${work}/m.out"
    awk -v b="${bundle}" -v c="${c}" -v s="${size}" -v t0="${t0}" -v t1="${t1}" -v t2="${t2}" \
      'BEGIN { printf "measure> %s %-6s %7.1f MiB  bake %6.1f s  read(1 cpu) %6.1f s\n", b, c, s / 1048576, t1 - t0, t2 - t1 }'
  done
fi
