# shellcheck shell=sh # bash · zsh가 source하는 조각이다(실행하지 않는다). 쓰는 문법은 POSIX sh 범위다.
# BB-M1(BB design 결정 5 · 6). 납품 프로젝트 묶음 fakesteak이 부팅 뒤 화면의 첫 패널에 자기 실행 파일을 띄운다. Ctrl+C로 끝내면 이 셸의
# 프롬프트가 남는다. 넷이 모두 맞을 때만 한 번 띄운다 — 대화형 셸, terminal의 패널(시리얼 콘솔은 TERM=linux), ssh가 아니다, 이번 부팅에
# 아직 안 띄웠다(/tmp는 RAM이라 부팅마다 비워진다). 표시 파일을 먼저 만든다 — 죽어도 새 패널마다 다시 뜨지 않게.
# FU-M1(FU design 결정 7): 도는 동안은 전체 화면이다 — xterm의 CSI 10;1 t를 terminal이 알아듣는다. 끝나면 CSI 10;0 t로 여백과 상태
# 줄을 되돌린다 — 셸로 돌아온 사람은 상태 줄을 본다. 셋을 sh -c 하나로 감싼다: fakesteak은 Ctrl+C를 SIGINT로 받고, 대화형 셸은
# 전경 job이 SIGINT로 죽으면 남은 명령을 취소한다(FU-M1 probe에서 끄기 printf가 안 돌았다). 안쪽 sh는 trap : INT(무시가 아니라 빈
# 처리기 — exec가 기본값으로 되돌리므로 fakesteak은 그대로 죽는다)로 살아남아 끄기를 찍고 정상으로 끝난다.
# 끄기 뒤의 H · 2J · 3J(clear가 보내는 것)는 비의 잔상을 지운다 — 160열에서 155열로 줄면 남은 비 몇 줄이 다시 접혀 프롬프트 위에
# 남았다(FU-M1 probe). 지울 스크롤백은 부팅 직후의 비뿐이다.
# 시스템 rc의 for 루프 안에서 source되므로 return을 쓰지 않는다(return은 바깥 rc를 끝낸다).
# LD-M0(LD design 결정 5): 기본 판도 이 묶음을 싣는다 — 저절로 뜨는 것은 개발 도구 층이 없는 납품 데모 판뿐이다. base가 얹힌 기계는
# 그 출처 기록 /usr/share/tars/layers/base가 있다. 기본 판에서는 fakesteak을 손으로 친다.
case $- in
  *i*)
    if [ "${TERM:-}" = xterm-256color ] && [ -z "${SSH_CONNECTION:-}" ] && [ ! -e /tmp/.tars-autorun ] &&
      [ ! -e /usr/share/tars/layers/base ] &&
      command -v fakesteak >/dev/null 2>&1; then
      : >/tmp/.tars-autorun
      sh -c 'trap : INT; printf "\033[10;1t"; fakesteak -b; printf "\033[10;0t\033[H\033[2J\033[3J"'
    fi
    ;;
esac
