# BB-M1 — /etc/tars/rc.d/fakesteak.sh와 같은 일. 대화형 · terminal의 패널 · ssh 아님 · 이번 부팅에 처음일 때만 첫 패널에 fakesteak을 띄운다.
# FU-M1: 도는 동안은 전체 화면(CSI 10;1 t), 끝나면(Ctrl+C) 되돌린다(CSI 10;0 t).
if status is-interactive; and test "$TERM" = xterm-256color; and not set -q SSH_CONNECTION; and not test -e /tmp/.tars-autorun; and command -q fakesteak
    touch /tmp/.tars-autorun
    printf '\033[10;1t'
    fakesteak -b
    printf '\033[10;0t'
end
