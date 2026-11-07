#!/usr/bin/env bash
# 첫걸음 안내(docs/help/*.md)가 실제 명령과 맞는지 — FS-M0 plan 결정 D. quick_check.sh가 부른다(호스트, macOS도).
#
#   1. 코드 블록 안의 `tars-config X` · `tars-service X`(앞의 sudo 허용)에서 X가 진짜 하위 명령인가. 정답은 소스의 쓰는 법이다 —
#      init/src/config_cli.zig의 USAGE, init/src/service_cli.zig의 usage(). 인자 없는 `tars-config`는 통과.
#   2. 문서 어디서든 `tars-help Y`의 Y가 kernel/help/tars-help의 TOPICS에 있고 docs/help/Y.md가 있는가. `--list` 같은 옵션은 통과.
#
# 옵션 · 키 이름 · 순서는 보지 않는다(design 위험 1). 실패는 파일:줄과 단어를 댄다.
set -euo pipefail
cd "$(dirname "$0")/../.."

help_dir=docs/help
cfg_src=init/src/config_cli.zig
svc_src=init/src/service_cli.zig
cmd=kernel/help/tars-help

# 정답 목록. Zig 여러 줄 글자(`\\`로 시작하는 줄)에서, 줄 머리(`\\` 뒤 공백 · `usage:`)나 `sudo ` 바로 뒤에 온 명령 이름의 다음 단어다
# (a|b|c는 가른다). 설명 칸의 산문("ports tars-config opens")은 세지 않는다.
words() {
  # shellcheck disable=SC1003 # 작은따옴표 안의 \\\\는 탈출이 아니라 grep에 줄 백슬래시 둘이다
  grep -E '^[[:space:]]*\\\\' "$2" | grep -oE "(\\\\(usage:)?[[:space:]]+|sudo )$1 [a-z|-]+" | sed "s/.*$1 //" | tr '|' '\n' | sort -u
}
cfg_words="$(words tars-config "${cfg_src}")"
svc_words="$(words tars-service "${svc_src}")"
topics="$(sed -n 's/^TOPICS=(\(.*\))$/\1/p' "${cmd}" | tr ' ' '\n')"
[ -n "${cfg_words}" ] && [ -n "${svc_words}" ] && [ -n "${topics}" ] || { echo "help check: could not read the subcommand lists" >&2; exit 2; }

bad=0
for f in "${help_dir}"/*.md; do
  # 1. 코드 블록 안의 명령 — 파일:줄 단어 꼴로 뽑는다.
  while read -r where name word; do
    case "${name}" in
      tars-config) list="${cfg_words}" ;;
      tars-service) list="${svc_words}" ;;
    esac
    if ! printf '%s\n' "${list}" | grep -qxF -- "${word}"; then
      echo "${where}: ${name} ${word} is not a ${name} subcommand" >&2
      bad=1
    fi
  done < <(awk -v f="${f}" '
    /^```/ { code = !code; next }
    code {
      line = $0
      while (match(line, /tars-(config|service) [a-z][a-z-]*/)) {
        hit = substr(line, RSTART, RLENGTH)
        split(hit, p, " ")
        print f ":" NR, p[1], p[2]
        line = substr(line, RSTART + RLENGTH)
      }
    }' "${f}")
  # 2. tars-help 주제.
  while read -r where word; do
    if ! printf '%s\n' "${topics}" | grep -qxF -- "${word}" || [ ! -f "${help_dir}/${word}.md" ]; then
      echo "${where}: tars-help ${word} has no chapter" >&2
      bad=1
    fi
  done < <(awk -v f="${f}" '{
      line = $0
      while (match(line, /tars-help [a-z][a-z-]*/)) {
        hit = substr(line, RSTART, RLENGTH)
        split(hit, p, " ")
        print f ":" NR, p[2]
        line = substr(line, RSTART + RLENGTH)
      }
    }' "${f}")
done

# 주제마다 장이 있고, 장마다 맨 위가 `# 제목`이다(tars-help --list가 쓴다).
for t in index ${topics}; do
  f="${help_dir}/${t}.md"
  [ -f "${f}" ] || { echo "${f}: missing (a tars-help topic)" >&2; bad=1; continue; }
  head -1 "${f}" | grep -q '^# ' || { echo "${f}:1: the first line is not a '# ' title" >&2; bad=1; }
done

[ "${bad}" = 0 ] || exit 1
chapters=("${help_dir}"/*.md)
echo "help check: ${#chapters[@]} chapters, tars-config $(printf '%s\n' "${cfg_words}" | wc -l | tr -d ' ') and tars-service $(printf '%s\n' "${svc_words}" | wc -l | tr -d ' ') subcommands"
