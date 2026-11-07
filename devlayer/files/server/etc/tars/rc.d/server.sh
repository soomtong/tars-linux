# shellcheck shell=sh # bash · zsh가 source하는 조각이다(실행하지 않는다). 쓰는 문법은 POSIX sh 범위다.
# TARS 개발 도구 층 server(TP-M10 plan 결정 E). postgres의 컴파일 기본 소켓 자리(/var/run/postgresql)가 TARS에 없다 — 서버는
# `pg_ctl -D ~/pg -o "-k /tmp" start`로 /tmp에 소켓을 두고, psql 등 클라이언트는 PGHOST로 거기를 찾는다. 사용자가 잡았으면 그대로.
[ -n "${PGHOST:-}" ] || export PGHOST=/tmp
