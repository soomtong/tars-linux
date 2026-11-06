# TARS 개발 도구 층 lang-native(TP-M4 plan 결정 E). `cargo install` · `go install`이 쓰는 홈의 bin을 PATH 앞에 둔다.
# /etc/bash.bashrc · /etc/zsh/zshrc가 Homebrew · mise보다 먼저 읽는다. 아직 없는 디렉터리도 넣는다 — 처음 깐 명령이 바로 선다.
case ":$PATH:" in *":$HOME/.cargo/bin:"*) ;; *) PATH="$HOME/.cargo/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) PATH="$HOME/go/bin:$PATH" ;; esac
export PATH
