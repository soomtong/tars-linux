# DY-M3 — /etc/tars/rc.d/gpu.sh와 같은 일. 얹힌 묶음이 base와 gpu 둘뿐이고(GPU 데모 판) 대화형 · terminal의 패널 · ssh 아님 ·
# 이번 부팅에 처음일 때만 첫 패널에 tars-gpu-demo를 화면 가득 띄운다. 까닭과 끝내는 길은 rc.d/gpu.sh의 주석.
if status is-interactive; and test "$TERM" = xterm-256color; and not set -q SSH_CONNECTION; and not test -e /tmp/.tars-autorun; and command -q tars-fullscreen; and command -q tars-gpu-demo
    set -l only yes
    for f in /usr/share/tars/layers/*
        switch (path basename $f)
            case base base.pkgs gpu gpu.pkgs
            case '*'
                set only no
        end
    end
    if test $only = yes
        touch /tmp/.tars-autorun
        tars-fullscreen tars-gpu-demo 2>/tmp/gpu-demo.log
    end
end
