# BB-M1 — /etc/tars/rc.d/fakesteak.sh와 같은 일. 대화형 · terminal의 패널 · ssh 아님 · 이번 부팅에 처음일 때만 첫 패널에 fakesteak을 띄운다.
if status is-interactive; and test "$TERM" = xterm-256color; and not set -q SSH_CONNECTION; and not test -e /tmp/.tars-autorun; and command -q fakesteak
    touch /tmp/.tars-autorun
    fakesteak -b
end
