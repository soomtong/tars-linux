# TARS 개발 도구 층 server(TP-M10 plan 결정 E) — /etc/tars/rc.d/server.sh와 같은 일. 사용자가 잡지 않았으면 PGHOST=/tmp.
set -q PGHOST; or set -gx PGHOST /tmp
