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

lines="$(awk -F'\t' -v b="${bundle}" '!/^#/ && NF >= 6 && $2 == b' devlayer/manifest.tsv)"
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

while IFS=$'\t' read -r tool _b version kind url sha; do
  case "${kind}" in
    debian)
      # libc6-dev는 initrd의 glibc와 같은 판이어야 한다(plan 결정 B). 헤더 · crt가 다른 판이면 빌드가 되어도 링크된
      # 실행 파일이 initrd의 libc.so.6와 어긋난다.
      if [[ "${tool}" == libc6-dev ]]; then
        have="$(grep -a -o -m1 'Debian GLIBC [^)]*' "${libc}" | sed 's/^Debian GLIBC //')"
        [[ "${have}" == "${version}" ]] || die "libc6-dev ${version} but the initrd glibc is ${have}"
      fi
      ;;
    upstream)
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
      # 하나(jdk-25.0.5+8/)는 벗긴다.
      dest="usr/local/lib/${tool}-${version}"
      mkdir -p "${root}/${dest}" "${root}/usr/local/bin"
      # 목록은 파일로 받는다 — `tar -tf | head -n1`은 head가 닫을 때 tar가 SIGPIPE(141)로 죽고 pipefail이 set -e로
      # 이 스크립트를 말없이 끝낸다(첫 판이 그랬다).
      tar -tf "${f}" >"${work}/tar.list"
      top="$(sed -n '1{s#/.*##;p;q}' "${work}/tar.list")"
      grep -qv "^${top}/" "${work}/tar.list" && die "${tool}: tarball has more than one top directory"
      [[ -n "${top}" ]] || die "${tool}: empty tarball"
      tar -xf "${f}" -C "${root}/${dest}" --strip-components=1 --no-same-owner
      for exe in "${root}/${dest}/bin/"*; do
        [[ -f "${exe}" && -x "${exe}" ]] || continue
        name="$(basename "${exe}")"
        link="${root}/usr/local/bin/${name}"
        exists=0
        [[ -e "${link}" || -L "${link}" ]] && exists=1
        ((exists == 0)) || die "${tool}: /usr/local/bin/${name} is taken"
        ln -s "../lib/${tool}-${version}/bin/${name}" "${link}"
      done
      printf '%s\t%s\tupstream\t%s\n' "${tool}" "${version}" "${url}" >>"${info}"
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

# 결정 13의 버전 줄. M0은 git describe다 — 버전을 낼 때의 모양은 M1이 정한다.
git -c safe.directory=/workspace -c safe.directory="${PWD}" describe --always --dirty >"${root}/usr/share/tars/layers/${bundle}"

# ── 검사 ────────────────────────────────────────────────────────────────
devlayer/verify.sh "${root}" "${ir}" devlayer/needed-ignore.tsv | sed "s/^verify>/verify> ${bundle}:/"

files="$(find "${root}" -type f | wc -l)"
bytes="$(du -sb "${root}" | cut -f1)"

# ── 굽기 ────────────────────────────────────────────────────────────────
stamp="$(
  {
    printf '%s\n' "${lines}" "${harvest_lines}" "${comp}"
    sha256sum devlayer/build.sh devlayer/verify.sh devlayer/needed-ignore.tsv
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

echo "build> ${bundle}: ${state} files=${files} unpacked=$((bytes / 1048576))MiB ${comp}=$(($(stat -c %s "${sqfs}") / 1048576))MiB dropped=$(grep -cv '^relink ' "${work}/${bundle}.dropped" || true)"

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
