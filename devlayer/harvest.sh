#!/usr/bin/env bash
# 개발 도구 층의 `debian` 줄을 거둔다(TP design 결정 2, TP-M0 plan 결정 A · E).
#
# 버리는 amd64 컨테이너(`--platform=linux/amd64 debian:trixie-slim`) 안에서 돈다 — make dev-layers가 띄운다. 개발
# 컨테이너는 arm64라 amd64 패키지의 postinst를 못 돌린다(plan 확인 1). 여기서는 진짜로 apt-get install하고(postinst
# · alternatives까지), 설치 전후의 /usr · /etc를 비교해 새로 생기거나 바뀐 것만 tar 하나로 내놓는다:
#
#   devlayer/build/<묶음>.harvest.tar    묶음 뿌리 기준(앞의 / 없이) 경로들
#   devlayer/build/<묶음>.harvest.lines  그 tar를 만든 매니페스트 줄 + 이 스크립트의 sha256(build.sh가 신선도를 본다)
#   devlayer/build/<묶음>.pkgs           새로 깔린 패키지(이름 · 판 · 아키텍처)
#   devlayer/build/<묶음>.harvest.log    아래 숫자들
#
# 이 컨테이너에는 apt 말고 아무것도 깔지 않는다. 거두기 전에 무엇이든(예: binutils) 깔면 그것이 "설치 전"에 들어가
# 묶음에서 빠진다 — gcc가 부르는 as · ld가 사라진다. 기준이 initrd가 아니라 trixie-slim이라 slim에만 있는 라이브러리도
# 빠질 수 있다. 그것은 verify.sh의 NEEDED 검사가 잡는다(plan 결정 H).
set -euo pipefail

cd "$(dirname "$0")/.."
bundle="${1:?usage: harvest.sh <bundle>}"
build=devlayer/build
mkdir -p "$build"

# 매니페스트에서 이 묶음의 debian 줄. 없으면 할 일이 없다(lang-jvm처럼 upstream만인 묶음).
# shellcheck source=devlayer/manifest.sh
source devlayer/manifest.sh
lines="$(manifest_lines "$bundle" debian)" || { echo "harvest> ${DEVLAYER_MANIFEST} has errors (above)" >&2; exit 1; }
if [ -z "$lines" ]; then
  rm -f "$build/$bundle.harvest."* "$build/$bundle.pkgs"
  echo "harvest> $bundle: no debian lines"
  exit 0
fi

# 끝 줄은 해시 하나여야 한다 — build.sh가 `head -n -1`로 매니페스트 줄만 떼어 대조한다.
want="$(printf '%s\n' "$lines"; cat devlayer/harvest.sh devlayer/harvest-skip.tsv | sha256sum | cut -c1-64)"
if [ -f "$build/$bundle.harvest.tar" ] && [ "$(cat "$build/$bundle.harvest.lines" 2>/dev/null)" = "$want" ]; then
  echo "harvest> $bundle: cached"
  exit 0
fi

[ "$(dpkg --print-architecture)" = amd64 ] || { echo "harvest> not an amd64 container" >&2; exit 1; }

pkgs=()
while IFS=$'\t' read -r _tool _b version _kind name _sha _opts; do
  pkgs+=("$name=$version")
done <<<"$lines"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 한 줄에 경로 · 내용. 파일은 sha256, 링크는 대상. 디렉터리는 tar가 풀 때 만든다.
snapshot() {
  {
    find /usr /etc -xdev -type l -printf '%p\tL:%l\n'
    find /usr /etc -xdev -type f -print0 | xargs -0 sha256sum | sed -E 's/^([0-9a-f]{64})  (.*)$/\2\tF:\1/'
  } | LC_ALL=C sort
}

# man 페이지는 싣는다(TP-M4 plan 결정 B). slim의 /etc/dpkg/dpkg.cfg.d/docker가 /usr/share/man/*을 풀지 않으므로 그 한 줄만 지운다.
# doc · info · locale은 그대로 뺀다. 이 컨테이너는 버린다.
if [ -f /etc/dpkg/dpkg.cfg.d/docker ]; then
  sed -i '\#^path-exclude /usr/share/man/\*$#d' /etc/dpkg/dpkg.cfg.d/docker
fi
dpkg-query -W -f '${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort >"$work/pkgs.before"
snapshot >"$work/before"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends "${pkgs[@]}" >"$work/apt.log"

dpkg-query -W -f '${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort >"$work/pkgs.after"
LC_ALL=C comm -13 "$work/pkgs.before" "$work/pkgs.after" >"$work/pkgs"

snapshot >"$work/after"

# 새로 생긴 줄 = 새 경로이거나 내용이 바뀐 경로. 바뀐 것(설치 전에도 있던 경로)은 따로 센다 — initrd와 내용이 다르면
# verify.sh의 결정 4 검사가 멈춘다(plan 위험 3).
LC_ALL=C comm -13 "$work/before" "$work/after" | cut -f1 >"$work/new.all"
cut -f1 "$work/before" | LC_ALL=C sort -u >"$work/before.paths"
LC_ALL=C comm -12 <(LC_ALL=C sort -u "$work/new.all") "$work/before.paths" >"$work/changed"

# 의존 폐포 가운데 slim에 이미 깔려 있던 패키지(libc6 · gcc-14-base · zlib1g 등)의 /usr 파일도 싣는다. 기준이
# initrd가 아니라 slim이라 생기는 틈이다 — 첫 판에서 libc6-dev의 libanl.so -> libanl.so.1(libc6 몫)과
# usr/share/doc/gcc-14 -> gcc-14-base가 끊겼다. initrd에 같은 것이 있으면 verify.sh가 뺀다(결정 4).
apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
  "${pkgs[@]}" 2>/dev/null | grep -v '^[ <]' | sed 's/:amd64$//' | LC_ALL=C sort -u >"${work}/closure"
LC_ALL=C comm -12 <(cut -f1 "${work}/pkgs.before" | sed 's/:amd64$//') "${work}/closure" >"${work}/deps"
while IFS= read -r dep; do
  dpkg -L "${dep}"
done <"${work}/deps" | sed -E 's#^/(lib|lib64|bin|sbin)/#/usr/\1/#' | grep '^/usr/' | while IFS= read -r f; do
  [[ -L "${f}" || -f "${f}" ]] && echo "${f}"
done >"${work}/deps.files"
LC_ALL=C sort -u "${work}/new.all" "${work}/deps.files" >"${work}/new.sorted"
mv "${work}/new.sorted" "${work}/new.all"

# initrd가 가진 패키지는 싣지 않는다(devlayer/harvest-skip.tsv, TP-M3). 거두는 이미지와 initrd를 지은 개발 컨테이너는
# apt 스냅숏이 따로 움직여 판이 어긋날 수 있다 — tzdata 2026e(slim) · 2026f(initrd)의 zoneinfo가 결정 4로 멈췄다.
# 패키지는 깔린 채로 두고(의존이 서야 한다) 그 파일만 목록에서 뺀다. 실행할 때는 initrd의 사본을 쓴다.
: >"${work}/skip.files"
skipped=0
while IFS=$'\t' read -r pkg _why; do
  [[ -z "${pkg}" || "${pkg}" == \#* ]] && continue
  dpkg-query -W "${pkg}" >/dev/null 2>&1 || continue
  dpkg -L "${pkg}" | sed -E 's#^/(lib|lib64|bin|sbin)/#/usr/\1/#' >>"${work}/skip.files"
  skipped=$((skipped + 1))
done <devlayer/harvest-skip.tsv
LC_ALL=C comm -23 "${work}/new.all" <(LC_ALL=C sort -u "${work}/skip.files") >"${work}/new.kept"
mv "${work}/new.kept" "${work}/new.all"

# 싣지 않는 것: alternatives 자리, ldconfig 캐시(TARS는 ld.so의 기본 경로로 찾는다), dpkg · apt 자신의 /etc, systemd ·
# cron의 자리(TARS에는 둘 다 없다 — php의 phpsessionclean.timer가 대상 없는 링크로 남았다, TP-M3). TP-M4: 계정 파일 넷과 그
# 백업(openssh-client가 _ssh 그룹을 더해 /etc/group이 initrd와 달라졌다 — TARS의 계정은 init이 만든다)과 sysvinit · cron ·
# apparmor · logcheck의 자리(man-db · rsync가 끌고 왔다, 읽는 것이 없다).
grep -Ev '^/etc/(alternatives/|ld\.so\.cache$|apt/|dpkg/|systemd/|cron\.[a-z]+/|(passwd|group|shadow|gshadow)-?$|init\.d/|rc[0-6S]\.d/|apparmor\.d/|logcheck/)' "$work/new.all" | sed 's|^/||' >"$work/list"
grep '^etc/' "$work/list" >"$work/etc" || true

# alternatives 펴기(결정 2): 새 경로 가운데 /etc/alternatives를 지나는 링크는 최종 대상으로의 상대 링크로 바꾼다. 묶음에는
# /etc/alternatives가 없고, TARS의 /etc는 부팅마다 만드는 tmpfs다. 새 경로만 편다 — slim에 원래 있던 링크(awk · pager ·
# which)까지 펴면 "바뀐 파일"이 되어 묶음에 실린다(첫 판이 그랬다).
flattened=0
while IFS= read -r rel; do
  link="/$rel"
  [ -L "$link" ] || continue
  case "$(readlink "$link")" in
    /etc/alternatives/*) ;;
    *) continue ;;
  esac
  final="$(readlink -f "$link")"
  ln -sfn "$(realpath -s --relative-to="$(dirname "$link")" "$final")" "$link"
  echo "$rel -> $(readlink "$link")" >>"$work/flat"
  flattened=$((flattened + 1))
done <"$work/list"
touch "$work/flat"

# 이 컨테이너에서 이미 끊긴 링크는 싣지 않는다. slim의 /etc/dpkg/dpkg.cfg.d/docker가 usr/share/doc/*를 풀지 않아서
# cpp-x86-64-linux-gnu/README.Bugs -> ../gcc-14/README.Bugs 같은 링크가 대상 없이 남는다. TARS가 아니라 거둔 자리의 사정이다.
: >"${work}/broken"
while IFS= read -r rel; do
  [[ -L "/${rel}" && ! -e "/${rel}" ]] && echo "${rel}" >>"${work}/broken"
done <"${work}/list"
if [[ -s "${work}/broken" ]]; then
  LC_ALL=C sort "${work}/list" | LC_ALL=C comm -23 - <(LC_ALL=C sort "${work}/broken") >"${work}/list.kept"
  mv "${work}/list.kept" "${work}/list"
fi

# 디렉터리를 가리키는 링크는 그 디렉터리도 싣는다. 목록은 파일 · 링크뿐이라(--no-recursion) 빈 디렉터리가 빠진다 —
# libmagic1의 usr/share/misc/magic -> ../file/magic이 대상 없이 남았다(TP-M4).
: >"${work}/linkdirs"
while IFS= read -r rel; do
  if [[ -L "/${rel}" && -d "/${rel}" ]]; then
    t="$(realpath "/${rel}")"
    [[ "${t}" == /usr/* ]] && echo "${t#/}" >>"${work}/linkdirs"
  fi
done <"${work}/list"
if [[ -s "${work}/linkdirs" ]]; then
  LC_ALL=C sort -u "${work}/list" "${work}/linkdirs" >"${work}/list.dirs"
  mv "${work}/list.dirs" "${work}/list"
fi

tar -C / --no-recursion -cpf "$build/$bundle.harvest.tar.tmp" -T "$work/list"
mv "$build/$bundle.harvest.tar.tmp" "$build/$bundle.harvest.tar"
cp "$work/pkgs" "$build/$bundle.pkgs"
{
  echo "harvest> $bundle: packages=$(wc -l <"$work/pkgs") paths=$(wc -l <"$work/list") changed=$(wc -l <"$work/changed") deps=$(wc -l <"$work/deps")/$(wc -l <"$work/deps.files") flattened=$flattened broken=$(wc -l <"${work}/broken") skipped=$skipped etc=$(wc -l <"$work/etc")"
  sed 's/^/harvest>   changed /' "$work/changed"
  sed 's/^/harvest>   etc /' "$work/etc"
  sed 's/^/harvest>   dep /' "$work/deps"
  sed 's/^/harvest>   broken /' "${work}/broken"
  sed 's/^/harvest>   flat /' "$work/flat"
} | tee "$build/$bundle.harvest.log"
printf '%s\n' "$want" >"$build/$bundle.harvest.lines"
