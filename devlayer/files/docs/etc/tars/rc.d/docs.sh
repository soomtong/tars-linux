# shellcheck shell=sh # bash · zsh가 source하는 조각이다(실행하지 않는다). 쓰는 문법은 POSIX sh 범위다.
# TARS 개발 도구 층 docs(TP-M9 plan 결정 B). dasht는 docset 디렉터리를 하나만 본다(DASHT_DOCSETS_DIR, 기본은 홈). 그 자리를 그대로
# 두고 묶음의 Bash docset을 링크로 보인다 — 망으로 받은 docset(`dasht-docsets-install`)도 같은 홈 자리에 sudo 없이 풀린다.
# 링크가 없거나 깨졌을 때만 만든다. 사용자가 진짜 디렉터리로 바꿔 두었으면(`dasht-docsets-update`) 손대지 않는다.
_tars_docsets="${DASHT_DOCSETS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dasht/docsets}"
if [ ! -e "$_tars_docsets/Bash.docset" ] && [ -d /usr/local/lib/dasht-2.4.0/Bash.docset ]; then
  mkdir -p "$_tars_docsets" 2>/dev/null && ln -sfn /usr/local/lib/dasht-2.4.0/Bash.docset "$_tars_docsets/Bash.docset" 2>/dev/null
fi
unset _tars_docsets
