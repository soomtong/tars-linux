#!/usr/bin/env bash
# 묶음 하나의 뿌리를 initrd와 대조한다(TP design 결정 4 · 5, TP-M0 plan 결정 G · H). build.sh가 굽기 전에 부른다.
#
#   verify.sh <묶음 뿌리> <풀린 initrd> <예외 tsv>
#
# 1. 겹친 경로(결정 4) — 같은 경로가 initrd에도 있으면, 내용(파일은 바이트, 링크는 대상)이 같을 때 묶음에서 지운다
#    (initrd가 이긴다). 다르면 경로를 찍고 실패한다. 같은 이름이 다른 경로에 있는 것(/usr/local/bin/fd와 /usr/bin/fd)은
#    겹침이 아니다 — PATH가 가른다(결정 20).
#    initrd는 merged-usr가 아니다 — 공유 라이브러리가 /lib/x86_64-linux-gnu(와 /lib64)에 있다. Debian(merged-usr)에서
#    거둔 묶음의 usr/lib/…는 그 짝(앞의 usr/ 없는 경로)과도 대조한다. 같은 내용이면 뺀다(ld.so가 /lib를 먼저 보므로
#    묶음 쪽은 어차피 안 쓰인다). 다르면 판이 어긋난 것이라 실패한다.
# 2. 끊긴 링크 — 묶음의 링크마다 대상이 묶음이나 initrd에 있는지. 한 단계만 본다. 대상이 1에서 빠진 usr/lib/…이고
#    initrd의 짝이 있으면 그 절대 경로로 바꾼다(relinked) — libc6-dev의 libanl.so -> libanl.so.1이 그렇다.
#    merged-usr 이전 Debian의 libc6-dev가 쓰던 모양(/lib/x86_64-linux-gnu/…로의 절대 링크)이다.
# 3. NEEDED(결정 5) — 묶음의 ELF마다 NEEDED를 RUNPATH · RPATH($ORIGIN을 편다)와 ld.so의 기본 자리에서 찾는다.
#    두 뿌리(묶음 · initrd) 어디든 있으면 풀린다. 못 찾은 것은 예외 tsv(경로 glob · soname glob · 이유)에 없으면 실패다.
#
# 1이 뿌리를 고치므로(지운다) 이 스크립트는 굽기 전 한 번 돈다. 마지막 줄의 dropped 목록은 build.sh가 stamp에 넣는다 —
# initrd가 바뀌어 지울 것이 달라지면 다시 굽는다.
set -euo pipefail

root="${1:?usage: verify.sh <root> <initrd-root> <ignore.tsv>}"
ir="${2:?}"
ignore="${3:?}"
[[ -d "${root}" && -d "${ir}/usr" ]] || { echo "verify> bad roots: ${root} ${ir}" >&2; exit 1; }

fail=0
dropped=0
differ=0
links=0
dangling=0
elves=0
relinked=0
unresolved=0
ignored=0
dropped_list="${root}/../$(basename "${root}").dropped"
: >"${dropped_list}"

exists() { [[ -e "$1" || -L "$1" ]]; }

# ── 1. 겹친 경로 ────────────────────────────────────────────────────────
# 두 패스다. 먼저 뺄 것을 다 정하고 나서 지운다 — 링크를 먼저 지우면 그 대상의 내용 비교가 끊긴다.
drop=()
while IFS= read -r -d '' p; do
  same=0
  if exists "${ir}/${p}"; then
    if [[ -L "${root}/${p}" && -L "${ir}/${p}" ]]; then
      [[ "$(readlink "${root}/${p}")" == "$(readlink "${ir}/${p}")" ]] && same=1
    elif [[ -f "${root}/${p}" && ! -L "${root}/${p}" && -f "${ir}/${p}" && ! -L "${ir}/${p}" ]]; then
      cmp -s "${root}/${p}" "${ir}/${p}" && same=1
    fi
    twin="${p}"
  elif [[ "${p}" == usr/lib/* || "${p}" == usr/lib64/* ]] && exists "${ir}/${p#usr/}"; then
    # 짝 대조는 링크를 따라간 내용으로 한다 — 묶음의 libz.so.1(링크)와 initrd의 libz.so.1(링크)은 대상 이름이 달라도
    # 같은 바이트면 같은 것이다.
    cmp -s "${root}/${p}" "${ir}/${p#usr/}" && same=1
    twin="${p#usr/}"
  else
    continue
  fi
  if ((same)); then
    drop+=("${p}")
  else
    echo "verify>   differs from initrd /${twin}: ${p}"
    differ=$((differ + 1))
    fail=1
  fi
done < <(cd "${root}" && find . \( -type f -o -type l \) -printf '%P\0' | LC_ALL=C sort -z)
for p in "${drop[@]}"; do
  rm -f "${root}/${p}"
  echo "${p}" >>"${dropped_list}"
done
dropped="${#drop[@]}"

# ── 2. 끊긴 링크 ────────────────────────────────────────────────────────
while IFS= read -r -d '' p; do
  links=$((links + 1))
  t="$(readlink "${root}/${p}")"
  if [[ "${t}" == /* ]]; then
    abs="${t}"
  else
    abs="/$(dirname "${p}")/${t}"
  fi
  rel="$(realpath -m -s "${abs}")"
  rel="${rel#/}"
  if exists "${root}/${rel}" || exists "${ir}/${rel}"; then
    continue
  fi
  if [[ "${rel}" == usr/lib/* || "${rel}" == usr/lib64/* ]] && exists "${ir}/${rel#usr/}"; then
    ln -sfn "/${rel#usr/}" "${root}/${p}"
    echo "relink ${p} -> /${rel#usr/}" >>"${dropped_list}"
    relinked=$((relinked + 1))
  else
    echo "verify>   dangling link: ${p} -> ${t}"
    dangling=$((dangling + 1))
    fail=1
  fi
done < <(cd "${root}" && find . -type l -printf '%P\0' | LC_ALL=C sort -z)

# ── 3. NEEDED ───────────────────────────────────────────────────────────
ignored_by() { # <경로> <soname> — 예외 tsv의 이유를 찍고 참
  local glob so reason
  while IFS=$'\t' read -r glob so reason; do
    [[ -z "${glob}" || "${glob}" == \#* ]] && continue
    # shellcheck disable=SC2053 # 오른쪽은 glob 패턴이다
    if [[ "$1" == ${glob} && "$2" == ${so} ]]; then
      echo "${reason}"
      return 0
    fi
  done <"${ignore}"
  return 1
}

std_dirs=(/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib64 /lib /usr/lib)
while IFS= read -r -d '' p; do
  magic=""
  LC_ALL=C read -r -n 4 -d '' magic <"${root}/${p}" || true
  [[ "${magic}" == $'\x7fELF' ]] || continue
  dyn="$(LC_ALL=C readelf -dW "${root}/${p}" 2>/dev/null || true)"
  needed="$(sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p' <<<"${dyn}")"
  elves=$((elves + 1))
  [[ -n "${needed}" ]] || continue
  dirs=()
  runpath="$(sed -n 's/.*(\(RUNPATH\|RPATH\)).*\[\(.*\)\]$/\2/p' <<<"${dyn}" | head -n1)"
  if [[ -n "${runpath}" ]]; then
    origin="/$(dirname "${p}")"
    IFS=: read -r -a rp <<<"${runpath}"
    for d in "${rp[@]}"; do
      d="${d//\$\{ORIGIN\}/${origin}}"
      d="${d//\$ORIGIN/${origin}}"
      dirs+=("$(realpath -m -s "${d}")")
    done
  fi
  dirs+=("${std_dirs[@]}")
  while IFS= read -r so; do
    found=0
    for d in "${dirs[@]}"; do
      if exists "${root}${d}/${so}" || exists "${ir}${d}/${so}"; then
        found=1
        break
      fi
    done
    ((found)) && continue
    if reason="$(ignored_by "${p}" "${so}")"; then
      ignored=$((ignored + 1))
      continue
    fi
    echo "verify>   unresolved: ${p} needs ${so}"
    unresolved=$((unresolved + 1))
    fail=1
  done <<<"${needed}"
done < <(cd "${root}" && find . -type f -printf '%P\0' | LC_ALL=C sort -z)

echo "verify> dropped=${dropped} differs=${differ} links=${links} relinked=${relinked} dangling=${dangling} elf=${elves} unresolved=${unresolved} ignored=${ignored}"
exit "${fail}"
