# BB-M1 — /etc/tars/rc.d/fakesteak.sh와 같은 일. 대화형 · terminal의 패널 · ssh 아님 · 이번 부팅에 처음일 때만 첫 패널에 fakesteak을 띄운다.
# FU-M1: 도는 동안은 전체 화면(CSI 10;1 t), 끝나면(Ctrl+C) 되돌린다(CSI 10;0 t). sh -c로 감싸는 이유는 rc.d/fakesteak.sh의 주석.
# LD-M0: base가 얹힌 기본 판에서는 안 띄운다(/usr/share/tars/layers/base) — 까닭은 rc.d/fakesteak.sh의 주석.
if status is-interactive; and test "$TERM" = xterm-256color; and not set -q SSH_CONNECTION; and not test -e /tmp/.tars-autorun; and not test -e /usr/share/tars/layers/base; and command -q fakesteak
    touch /tmp/.tars-autorun
    sh -c 'trap : INT; printf "\033[10;1t"; fakesteak -b; printf "\033[10;0t\033[H\033[2J\033[3J"'
end
