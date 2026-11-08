# shellcheck shell=sh # bash · zsh가 source하는 조각이다(실행하지 않는다). 쓰는 문법은 POSIX sh 범위다.
# TARS 개발 도구 층 lang-script(TP-M12). `bun install -g`(bun add -g)가 실행 파일을 두는 홈의 bin을 PATH 앞에 둔다 — lang-native의
# `~/.cargo/bin` · `~/go/bin`과 짝이다. 아직 없는 디렉터리도 넣는다 — 처음 깐 명령이 바로 선다.
case ":$PATH:" in *":$HOME/.bun/bin:"*) ;; *) PATH="$HOME/.bun/bin:$PATH" ;; esac
export PATH
