# shellcheck shell=sh # bash · zsh가 source하는 조각이다(실행하지 않는다). 쓰는 문법은 POSIX sh 범위다.
# BB-M1(BB design 결정 5 · 6). 납품 프로젝트 묶음 fakesteak이 부팅 뒤 화면의 첫 패널에 자기 실행 파일을 띄운다. Ctrl+C로 끝내면 이 셸의
# 프롬프트가 남는다. 넷이 모두 맞을 때만 한 번 띄운다 — 대화형 셸, terminal의 패널(시리얼 콘솔은 TERM=linux), ssh가 아니다, 이번 부팅에
# 아직 안 띄웠다(/tmp는 RAM이라 부팅마다 비워진다). 표시 파일을 먼저 만든다 — 죽어도 새 패널마다 다시 뜨지 않게.
# 시스템 rc의 for 루프 안에서 source되므로 return을 쓰지 않는다(return은 바깥 rc를 끝낸다).
case $- in
  *i*)
    if [ "${TERM:-}" = xterm-256color ] && [ -z "${SSH_CONNECTION:-}" ] && [ ! -e /tmp/.tars-autorun ] &&
      command -v fakesteak >/dev/null 2>&1; then
      : >/tmp/.tars-autorun
      fakesteak -b
    fi
    ;;
esac
