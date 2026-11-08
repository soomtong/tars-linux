#!/usr/bin/env bash
# vendor-repo 키 검사(TP-M10 plan 덧붙임, 사용자 요청 2026-11-08). devlayer/repos.tsv의 줄마다 devlayer/keys/<이름>.asc가
#
#   1. 셋째 열의 sha256과 같은가 — harvest.sh가 거두기 컨테이너에서 대조하는 것과 같은 값(멈춤)
#   2. 넷째 열의 지문을 가진 키를 담았는가 — 저장소 안내 페이지의 지문과 사람이 대조하는 값(멈춤)
#   3. 그 키가 만료됐는가(멈춤), KEYS_WARN_DAYS(기본 180)일 안에 만료되는가(경고만 — 저장소가 같은 지문에 만료일을 늘린 키를
#      다시 내면 그 키를 받아 넣고 셋째 열을 고친다. gpg가 같은 지문을 보이므로 정상 갱신인지 바로 안다)
#
# gpg가 있는 곳에서 돈다 — 개발 컨테이너(make dev-layers가 거두기 전에 부른다)와 호스트(make quick). 거두기 컨테이너는 설치 전에
# 아무것도 깔지 않으므로(gpg를 깔면 base의 gnupg가 묶음에서 빠진다) 거기서는 sha256만 본다. KEYS_NOW(epoch 초)는 시험용이다.
set -euo pipefail
cd "$(dirname "$0")/.."

warn_days="${KEYS_WARN_DAYS:-180}"
now="${KEYS_NOW:-$(date +%s)}"
failed=0
count=0
nearest=""

while IFS=$'\t' read -r name _aptline keysha fpr; do
  [[ -z "${name}" || "${name}" == \#* ]] && continue
  count=$((count + 1))
  f="devlayer/keys/${name}.asc"
  if [[ ! -f "${f}" ]]; then
    echo "keys> ${name}: no ${f}" >&2
    failed=1
    continue
  fi
  have="$(sha256sum <"${f}" 2>/dev/null | cut -c1-64 || shasum -a 256 <"${f}" | cut -c1-64)"
  if [[ "${have}" != "${keysha}" ]]; then
    echo "keys> ${name}: ${f} is ${have}, devlayer/repos.tsv says ${keysha}" >&2
    failed=1
  fi
  # pub · sub 줄의 일곱째 칸이 만료(epoch, 비면 없음)이고 바로 뒤의 fpr 줄이 그 키의 지문이다.
  expires="$(gpg --show-keys --with-colons "${f}" 2>/dev/null \
    | awk -F: -v want="${fpr}" '$1 == "pub" || $1 == "sub" { e = $7 } $1 == "fpr" && $10 == want { print (e == "" ? "never" : e); found = 1; exit } END { if (!found) print "missing" }')"
  case "${expires}" in
    missing)
      echo "keys> ${name}: ${f} has no key with the fingerprint ${fpr}" >&2
      failed=1
      ;;
    never) ;;
    *)
      days=$(((expires - now) / 86400))
      when="$(date -u -d "@${expires}" +%Y-%m-%d 2>/dev/null || date -u -r "${expires}" +%Y-%m-%d)"
      if ((expires <= now)); then
        echo "keys> ${name}: the key ${fpr} expired on ${when} — get the renewed key, then fix devlayer/repos.tsv" >&2
        failed=1
      elif ((days < warn_days)); then
        echo "keys> ${name}: warning — the key ${fpr} expires on ${when}, in ${days} days"
      fi
      if [[ -z "${nearest}" ]] || ((expires < ${nearest%% *})); then nearest="${expires} ${name} ${when}"; fi
      ;;
  esac
done <devlayer/repos.tsv

if ((failed)); then
  echo "keys> FAIL (above)" >&2
  exit 1
fi
if [[ -n "${nearest}" ]]; then
  read -r _ n w <<<"${nearest}"
  echo "keys> ${count} repos: sha256 and fingerprints match, the nearest expiry is ${n} on ${w}"
else
  echo "keys> ${count} repos: sha256 and fingerprints match, no key expires"
fi
