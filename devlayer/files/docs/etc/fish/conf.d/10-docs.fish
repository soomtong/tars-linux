# TARS 개발 도구 층 docs(TP-M9 plan 결정 B) — /etc/tars/rc.d/docs.sh와 같은 일. 홈의 dasht docset 자리에 묶음의 Bash docset 링크를,
# 없거나 깨졌을 때만 둔다.
set -l docsets $DASHT_DOCSETS_DIR
if test -z "$docsets"
    set docsets $HOME/.local/share/dasht/docsets
    test -n "$XDG_DATA_HOME"; and set docsets $XDG_DATA_HOME/dasht/docsets
end
if not test -e $docsets/Bash.docset; and test -d /usr/local/lib/dasht-2.4.0/Bash.docset
    mkdir -p $docsets 2>/dev/null; and ln -sfn /usr/local/lib/dasht-2.4.0/Bash.docset $docsets/Bash.docset 2>/dev/null
end
