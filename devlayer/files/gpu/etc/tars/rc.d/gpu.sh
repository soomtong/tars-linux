# shellcheck shell=sh # bash · zsh가 source하는 조각이다(실행하지 않는다). 쓰는 문법은 POSIX sh 범위다.
# DY-M3(DY design 결정 12). GPU 데모 판 — 얹힌 묶음이 base와 gpu 둘뿐인 기계 — 에서 부팅 뒤 첫 패널이 tars-gpu-demo를 화면 가득
# 띄운다. fakesteak의 autorun(rc.d/fakesteak.sh)과 같은 넷을 본다: 대화형 셸, terminal의 패널(시리얼 콘솔은 TERM=linux), ssh가
# 아니다, 이번 부팅에 아직 안 띄웠다(/tmp/.tars-autorun — fakesteak과 같은 표시라 한 부팅에 하나만 뜬다). 표시를 먼저 만든다.
# 판정 "base와 gpu 둘뿐"은 출처 기록 /usr/share/tars/layers/<묶음>(과 .pkgs)으로 한다 — 개발 도구 묶음이 하나라도 있으면 띄우지 않는다.
# 화면은 tars-fullscreen이 terminal에게서 양보받는다. CSI 10;1 t는 쓰지 않는다 — 양보 중에는 terminal이 그리지 않는다.
# Esc(또는 Ctrl+Cmd+Backspace)로 끝나면 terminal이 화면을 되찾고 이 셸의 프롬프트가 남는다. 데모의 단계 줄은 /tmp/gpu-demo.log.
# 시스템 rc의 for 루프 안에서 source되므로 return을 쓰지 않는다(return은 바깥 rc를 끝낸다).
case $- in
  *i*)
    if [ "${TERM:-}" = xterm-256color ] && [ -z "${SSH_CONNECTION:-}" ] && [ ! -e /tmp/.tars-autorun ] &&
      command -v tars-fullscreen >/dev/null 2>&1 && command -v tars-gpu-demo >/dev/null 2>&1; then
      tars_gpu_only=yes
      for tars_gpu_f in /usr/share/tars/layers/*; do
        case "${tars_gpu_f##*/}" in
          base | base.pkgs | gpu | gpu.pkgs) ;;
          *) tars_gpu_only=no ;;
        esac
      done
      if [ "${tars_gpu_only}" = yes ]; then
        : >/tmp/.tars-autorun
        tars-fullscreen tars-gpu-demo 2>/tmp/gpu-demo.log
      fi
      unset tars_gpu_only tars_gpu_f
    fi
    ;;
esac
