# shellcheck shell=bash
# 개발 도구 층 매니페스트의 파서 — build.sh와 harvest.sh가 source한다(TP-M2 plan 결정 D). 거두기 컨테이너
# (debian:trixie-slim)에도 bash와 mawk가 있으므로 awk는 POSIX 범위만 쓴다.
#
# 부를 때마다 manifest.tsv 전체를 검사한다. 주석(#)과 빈 줄이 아닌 줄은 열이 6이나 7이어야 하고, 아니면 줄 번호를 찍고
# 실패한다. 첫 판의 `awk … NF >= 6`은 탭이 공백으로 바뀐 줄을 말없이 건너뛰어, 그 도구가 묶음에서 빠진 채 초록이었다.
#
#   열     도구 · 묶음 · 버전 · 종류 · URL · sha256 [· 선택]
#   종류   upstream · vendor-repo · prebuilt · debian(TP design 결정 1의 넷)과 maven(TP-M5 plan 결정 B — URL 자리가
#          devlayer/maven/의 잠금 파일, sha256 자리가 그 파일의 sha256)
#   선택   공백으로 가른 키=값. 값에는 공백이 없다. 키는 넷이다(TP-M2 plan 결정 C, strip은 TP-M3 plan 결정 C):
#          exe=a,b   링크할 실행 파일(도구 디렉터리 기준). 없으면 bin/의 실행 파일 전부
#          hook=X    풀기를 devlayer/hooks/X.sh가 한다(받기 · sha256은 build.sh)
#          into=T    도구 디렉터리를 T-<버전>으로(rust-src가 rust의 자리로)
#          strip=N   풀고 나서 벗길 맨 위 디렉터리의 단 수(숫자, 기본 1). 0이면 맨 위의 파일을 그대로

DEVLAYER_MANIFEST="${DEVLAYER_MANIFEST:-devlayer/manifest.tsv}"

# manifest_check — 문제가 있으면 줄마다 한 줄을 stderr에 찍고 1을 돌려준다.
manifest_check() {
  awk -F'\t' -v file="${DEVLAYER_MANIFEST}" '
    function bad(msg) { printf "%s:%d: %s\n", file, NR, msg > "/dev/stderr"; failed = 1 }
    /^#/ || /^[ \t]*$/ { next }
    {
      if (NF < 6 || NF > 7) { bad("expected 6 or 7 tab-separated columns, got " NF); next }
      for (i = 1; i <= 6; i++) if ($i == "") { bad("column " i " is empty"); next }
      if ($4 != "upstream" && $4 != "vendor-repo" && $4 != "prebuilt" && $4 != "debian" && $4 != "maven") bad("unknown kind " $4)
      if (NF == 7) {
        n = split($7, o, " ")
        for (i = 1; i <= n; i++) if (o[i] !~ /^(exe|hook|into)=[^=]+$/ && o[i] !~ /^strip=[0-9]+$/) bad("unknown option " o[i])
      }
      if ($1 in seen) bad("tool " $1 " again (first on line " seen[$1] ")")
      else seen[$1] = NR
    }
    END { exit failed }
  ' "${DEVLAYER_MANIFEST}"
}

# manifest_lines <묶음> [종류] — 검사를 지난 뒤 그 묶음의 줄(종류를 주면 그 종류만)을 원래 모양 그대로.
manifest_lines() {
  manifest_check || return 1
  awk -F'\t' -v b="$1" -v k="${2:-}" '!/^#/ && !/^[ \t]*$/ && $2 == b && (k == "" || $4 == k)' "${DEVLAYER_MANIFEST}"
}

# manifest_bundles — 매니페스트에 나오는 묶음 이름(처음 나온 순서).
manifest_bundles() {
  manifest_check || return 1
  awk -F'\t' '!/^#/ && !/^[ \t]*$/ && !($2 in s) { s[$2] = 1; print $2 }' "${DEVLAYER_MANIFEST}"
}

# manifest_opt <선택 열> <키> — 그 키의 값. 없으면 빈 글자.
manifest_opt() {
  local word
  for word in $1; do
    [[ "${word}" == "$2="* ]] && { printf '%s\n' "${word#*=}"; return 0; }
  done
  return 0
}
