#!/usr/bin/env bash
# 개발 도구 층의 `debian` · `vendor-repo` 줄을 거둔다(TP design 결정 2, TP-M0 plan 결정 A · E, vendor-repo는 TP-M10 plan 결정 A).
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

# 매니페스트에서 이 묶음의 debian · vendor-repo 줄. 없으면 할 일이 없다(lang-jvm처럼 upstream만인 묶음).
# shellcheck source=devlayer/manifest.sh
source devlayer/manifest.sh
lines="$(manifest_lines "$bundle")" || { echo "harvest> ${DEVLAYER_MANIFEST} has errors (above)" >&2; exit 1; }
lines="$(awk -F'\t' '$4 == "debian" || $4 == "vendor-repo"' <<<"$lines")"
if [ -z "$lines" ]; then
  rm -f "$build/$bundle.harvest."* "$build/$bundle.pkgs"
  echo "harvest> $bundle: no debian lines"
  exit 0
fi

# vendor-repo 줄이 쓰는 저장소 이름(TP-M10 plan 결정 A). 그 저장소의 repos.tsv 줄과 키도 캐시 해시에 든다 — 다른 묶음의 캐시는
# 이 두 자리가 바뀌어도 그대로다.
repos="$(awk -F'\t' '$4 == "vendor-repo" { split($5, a, "/"); print a[1] }' <<<"$lines" | LC_ALL=C sort -u)"
repo_state=""
for r in $repos; do
  row="$(awk -F'\t' -v r="$r" '!/^#/ && $1 == r' devlayer/repos.tsv)"
  [ -n "$row" ] || { echo "harvest> $bundle: repo $r is not in devlayer/repos.tsv" >&2; exit 1; }
  [ -f "devlayer/keys/$r.asc" ] || { echo "harvest> $bundle: no devlayer/keys/$r.asc" >&2; exit 1; }
  repo_state+="$row"$'\n'"$(sha256sum <"devlayer/keys/$r.asc")"$'\n'
done

# 끝 줄은 해시 하나여야 한다 — build.sh가 `head -n -1`로 매니페스트 줄만 떼어 대조한다.
want="$(printf '%s\n' "$lines"; { cat devlayer/harvest.sh devlayer/harvest-skip.tsv; printf '%s' "$repo_state"; } | sha256sum | cut -c1-64)"
if [ -f "$build/$bundle.harvest.tar" ] && [ "$(cat "$build/$bundle.harvest.lines" 2>/dev/null)" = "$want" ]; then
  echo "harvest> $bundle: cached"
  exit 0
fi

[ "$(dpkg --print-architecture)" = amd64 ] || { echo "harvest> not an amd64 container" >&2; exit 1; }

pkgs=()
while IFS=$'\t' read -r _tool _b version _kind name _sha _opts; do
  pkgs+=("${name#*/}=$version") # vendor-repo는 <저장소>/<패키지>
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

# slim에 이미 깔린 패키지를 먼저 최신 판으로 올린다(TP-M12). apt-get install은 깔린 의존을 올리지 않는데, 아래 의존 폐포 단계가
# 그 옛 파일을 싣는다 — slim 스냅숏의 zlib1g -1+b1이 initrd(개발 컨테이너가 trixie-security에서 받은 +deb13u1)의 libz와 같은
# 경로 · 다른 내용이 되어 verify의 결정 4로 멈췄다. upgrade는 새 패키지를 들이지 않으므로 "설치 전" 기준을 흐리지 않는다.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq >/dev/null

dpkg-query -W -f '${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort >"$work/pkgs.before"
snapshot >"$work/before"

# vendor-repo(TP-M10 plan 결정 A): 키 파일의 sha256을 repos.tsv와 대조한 뒤 그 키만 믿는 저장소로 붙인다. /etc/apt는 거두지 않으므로
# 이 sources 파일은 묶음에 들지 않는다. 키는 /workspace의 것을 그대로 가리킨다.
for r in $repos; do
  IFS=$'\t' read -r _name aptline keysha _fpr < <(awk -F'\t' -v r="$r" '!/^#/ && $1 == r' devlayer/repos.tsv)
  have="$(sha256sum <"devlayer/keys/$r.asc" | cut -c1-64)"
  [ "$have" = "$keysha" ] || { echo "harvest> $bundle: devlayer/keys/$r.asc is $have, devlayer/repos.tsv says $keysha" >&2; exit 1; }
  echo "deb [signed-by=$PWD/devlayer/keys/$r.asc] $aptline" >"/etc/apt/sources.list.d/tars-$r.list"
done

apt-get update -qq # vendor-repo 목록을 붙인 뒤라 다시
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
  # -W만으로는 dpkg가 이름만 아는 패키지(설치 안 됨)도 0이다 — base 거두기에서 vim-common이 그랬다(TP-M8). 상태를 묻는다.
  [[ "$(dpkg-query -W -f='${db:Status-Status}' "${pkg}" 2>/dev/null)" == installed ]] || continue
  dpkg -L "${pkg}" | sed -E 's#^/(lib|lib64|bin|sbin)/#/usr/\1/#' >>"${work}/skip.files"
  skipped=$((skipped + 1))
done <devlayer/harvest-skip.tsv
LC_ALL=C comm -23 "${work}/new.all" <(LC_ALL=C sort -u "${work}/skip.files") >"${work}/new.kept"
mv "${work}/new.kept" "${work}/new.all"

# 싣지 않는 것: alternatives 자리, ldconfig 캐시(TARS는 ld.so의 기본 경로로 찾는다), dpkg · apt 자신의 /etc, systemd ·
# cron의 자리(TARS에는 둘 다 없다 — php의 phpsessionclean.timer가 대상 없는 링크로 남았다, TP-M3). TP-M4: 계정 파일 넷과 그
# 백업(openssh-client가 _ssh 그룹을 더해 /etc/group이 initrd와 달라졌다 — TARS의 계정은 init이 만든다)과 sysvinit · cron ·
# apparmor · logcheck의 자리(man-db · rsync가 끌고 왔다, 읽는 것이 없다). TP-M10: postgresql-18의 postinst가 만든 클러스터 18/main의
# 설정(/etc/postgresql/) — 그 클러스터의 데이터는 거두지 않으므로 TARS에 없는 클러스터의 설정이 된다(plan 결정 D). postgresql-common/은 싣는다.
# 같은 postinst 무리의 ssl-cert가 이 컨테이너에서 만든 자체 서명 인증서와 그 비밀 키(snakeoil)와 해시 링크 — 실으면 모든 TARS가 같은
# 비밀 키를 갖는다(TP-M10 plan 확인한 것). CA 인증서는 initrd의 것이다. openssl의 usr/lib/ssl/private는 그 빠진 디렉터리로의 링크라 함께 뺀다.
grep -Ev '^/usr/lib/ssl/private$|^/etc/(alternatives/|ld\.so\.cache$|apt/|dpkg/|systemd/|cron\.[a-z]+/|(passwd|group|shadow|gshadow)-?$|init\.d/|rc[0-6S]\.d/|apparmor\.d/|logcheck/|postgresql/|ssl/private/|ssl/certs/ssl-cert-snakeoil\.pem$|ssl/certs/[0-9a-f]{8}\.[0-9]+$)' "$work/new.all" | sed 's|^/||' >"$work/list"
grep '^etc/' "$work/list" >"$work/etc" || true

# perl의 /usr/bin/perldoc은 "perl-doc을 깔라"고 찍는 자리표다(perl-doc이 divert해 진짜로 바꾼다). perl-doc 없이 perl을 끌고 온 묶음
# (server — postgresql-common)이 그 자리표를 실으면 진짜를 실은 base와 같은 경로의 다른 내용이 된다(TP-M10 plan 확인한 것).
if [[ "$(dpkg-query -W -f='${db:Status-Status}' perl-doc 2>/dev/null)" != installed ]]; then
  grep -vx 'usr/bin/perldoc' "$work/list" >"$work/list.kept" || true
  mv "$work/list.kept" "$work/list"
fi

# 이름을 다른 것에 맡긴 alternatives(TP-M7): emacs-nox의 postinst가 /usr/bin/editor와 /usr/bin/ctags를 자기로 돌린다. editor는 initrd의
# vim이 맡고(TP-M7 plan 맡아 정한 것 1 — 묶음이 덮으면 verify의 결정 4에 걸린다), ctags는 base의 universal-ctags가 맡는다(TP-M4).
# man 페이지의 짝도 뺀다 — 남기면 man ctags가 emacs판을 연다.
grep -Ev '^usr/(bin/(editor|ctags)|share/man/man1/(editor|ctags)\.1\.gz)$' "$work/list" >"$work/list.kept" || true
mv "$work/list.kept" "$work/list"

# alternatives 펴기(결정 2): 새 경로 가운데 /etc/alternatives를 지나는 링크는 최종 대상으로의 상대 링크로 바꾼다. 묶음에는
# /etc/alternatives가 없고, TARS의 /etc는 부팅마다 만드는 tmpfs다. 새 경로만 편다 — slim에 원래 있던 링크(awk · pager ·
# which)까지 펴면 "바뀐 파일"이 되어 묶음에 실린다(첫 판이 그랬다).
# 대상이 harvest-skip의 패키지 파일이면 그 링크도 싣지 않는다(TP-M8): vifm이 끌고 온 vim의 postinst가 vi · vim · ex · view ·
# vimdiff와 그 man(여러 언어의 editor.1.gz 등)을 vim.basic으로 돌렸다. vim을 빼면 끊기고, vi · vim은 initrd의 것과 부딪친다.
flattened=0
: >"$work/skipalt"
while IFS= read -r rel; do
  link="/$rel"
  [ -L "$link" ] || continue
  case "$(readlink "$link")" in
    /etc/alternatives/*) ;;
    *) continue ;;
  esac
  final="$(readlink -f "$link")"
  if grep -qxF "$final" "${work}/skip.files"; then
    echo "$rel" >>"$work/skipalt"
    continue
  fi
  ln -sfn "$(realpath -s --relative-to="$(dirname "$link")" "$final")" "$link"
  echo "$rel -> $(readlink "$link")" >>"$work/flat"
  flattened=$((flattened + 1))
done <"$work/list"
touch "$work/flat"
if [[ -s "$work/skipalt" ]]; then
  LC_ALL=C sort "$work/list" | LC_ALL=C comm -23 - <(LC_ALL=C sort "$work/skipalt") >"$work/list.kept"
  mv "$work/list.kept" "$work/list"
fi

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
# 라이선스 본문으로의 링크는 그 본문도 싣는다(TP-M7). emacs의 etc/COPYING -> ../../../common-licenses/GPL-3의 대상은 slim에 원래 있는
# base-files의 것이라 목록에 없고, initrd에도 없어 verify가 끊긴 링크로 멈췄다. C-h C-c가 etc/COPYING을 읽는다.
while IFS= read -r rel; do
  if [[ -L "/${rel}" && -f "/${rel}" ]]; then
    t="$(realpath "/${rel}")"
    [[ "${t}" == /usr/share/common-licenses/* ]] && echo "${t#/}" >>"${work}/linkdirs"
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
  echo "harvest> $bundle: packages=$(wc -l <"$work/pkgs") paths=$(wc -l <"$work/list") changed=$(wc -l <"$work/changed") deps=$(wc -l <"$work/deps")/$(wc -l <"$work/deps.files") flattened=$flattened skipalt=$(wc -l <"$work/skipalt") broken=$(wc -l <"${work}/broken") skipped=$skipped etc=$(wc -l <"$work/etc")"
  sed 's/^/harvest>   changed /' "$work/changed"
  sed 's/^/harvest>   etc /' "$work/etc"
  sed 's/^/harvest>   dep /' "$work/deps"
  sed 's/^/harvest>   broken /' "${work}/broken"
  sed 's/^/harvest>   flat /' "$work/flat"
} | tee "$build/$bundle.harvest.log"
printf '%s\n' "$want" >"$build/$bundle.harvest.lines"
