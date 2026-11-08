# TARS 개발 도구 층 lang-script(TP-M12). `bun install -g`가 쓰는 홈의 bin을 PATH 앞에 둔다(lang-native의 cargo · go와 짝).
# conf.d는 이름 순이라 homebrew.fish · mise.fish보다 먼저다. fish_add_path는 없는 디렉터리를 건너뛰므로 쓰지 않는다.
contains -- $HOME/.bun/bin $PATH; or set -gx PATH $HOME/.bun/bin $PATH
