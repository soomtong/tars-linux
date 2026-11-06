# TARS 개발 도구 층 lang-native(TP-M4 plan 결정 E). `cargo install` · `go install`이 쓰는 홈의 bin을 PATH 앞에 둔다.
# conf.d는 이름 순이라 homebrew.fish · mise.fish보다 먼저다. fish_add_path는 없는 디렉터리를 건너뛰므로 쓰지 않는다.
for d in $HOME/.cargo/bin $HOME/go/bin
    contains -- $d $PATH; or set -gx PATH $d $PATH
end
