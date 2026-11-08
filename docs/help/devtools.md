# 개발 도구와 문서

## 무엇이 깔려 있나

설치 이미지에 개발 도구 층이 실려 있었다면 망 없이 바로 쓸 수 있습니다.

| 묶음 | 들어 있는 것 |
|---|---|
| base | gcc · g++ · make · cmake · ninja · autotools · gdb · valgrind · strace · perl · 압축 · ssh · man |
| lang-native | rust(cargo) · go · zig |
| lang-script | python3(pip · venv) · ruby · node(npm) · bun · lua · luau · janet · php |
| lang-jvm | JDK 25(java · javac) · kotlin · clojure |
| lang-beam | erlang · elixir(mix) · gleam |
| editor | ms(mitos) · nvim · emacs · ttt |
| util | rg · fd · bat · fzf · jq · lazygit · yazi · duckdb · sqlite3 · hyperfine · mkcert · 그 밖의 터미널 도구 |
| media | ffmpeg · ImageMagick(magick) · GraphicsMagick(gm) |
| docs | dasht · w3m · `tars-docs` |
| server | postgresql 18 · mysql 9.7 · nginx · redis · caddy |

`ls /usr/local/bin`이 없거나 비어 있으면 이 기계에는 개발 도구 층이 없습니다(층 없이 만든 이미지로 설치한 경우입니다).

## 더 깔기

- 시스템 디렉터리(`/usr`)는 읽기 전용입니다. `sudo`로 전역 설치한 것(`sudo npm i -g` · `sudo pip install` · `sudo gem install` ·
  `make install`)은 `/usr/local`에 들어가고 재부팅 · 갱신에도 남습니다.
- 사용자 설치는 각 도구의 방식 그대로입니다 — `cargo install`(`~/.cargo/bin`), `go install`(`~/go/bin`), `pip install --user`, venv.
- 더 새 판이나 없는 도구는 망이 있을 때 Homebrew나 mise로 받습니다.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"   # Homebrew
curl https://mise.run | sh && ~/.local/bin/mise use -g node@lts                                  # mise
```

셸이 둘 다 알아서 PATH에 잇습니다(새 셸부터).

## 서버

서버는 내 계정으로, 데이터를 홈 아래에 두고 띄웁니다. 시스템 서비스로 등록돼 있지 않아서 부팅할 때 저절로 뜨지 않습니다.
홈은 재부팅해도 남지만 `/etc`와 `/var`는 부팅할 때마다 새로 만들어집니다. 그래서 데이터와 내 설정은 홈에 둡니다.

```sh
initdb -D ~/pg                         # postgres — 처음 한 번
pg_ctl -D ~/pg -o "-k /tmp" -l ~/pg.log start
psql postgres                          # 소켓은 /tmp(PGHOST)
pg_ctl -D ~/pg stop

mysqld --initialize-insecure --datadir=$HOME/mysql   # mysql — 처음 한 번(root 비밀번호 없음)
mysqld --datadir=$HOME/mysql &
mysql -uroot
mysqladmin -uroot shutdown

redis-server --dir ~ --daemonize yes   # redis
redis-cli ping
redis-cli shutdown

caddy file-server --listen :8080       # caddy — 지금 디렉터리를 보입니다
```

nginx는 기본 설정이 시스템 계정과 `/var/log`를 가정합니다. 내 설정을 홈에 두고 `-p`로 띄웁니다. 설정 안의 상대 경로는
`-p`로 준 자리(`~/nginx`)에서 찾습니다.

```sh
mkdir -p ~/nginx/logs ~/nginx/tmp ~/nginx/www
vim ~/nginx/nginx.conf                  # 아래 내용으로
nginx -p ~/nginx -e logs/error.log -c nginx.conf           # 띄우기
nginx -p ~/nginx -e logs/error.log -c nginx.conf -s stop   # 끄기
```

```nginx
pid nginx.pid;
error_log logs/error.log;
events {}
http {
  access_log logs/access.log;
  client_body_temp_path tmp; proxy_temp_path tmp; fastcgi_temp_path tmp; uwsgi_temp_path tmp; scgi_temp_path tmp;
  server { listen 8080; root www; }
}
```

1024 아래 포트(80 · 443)는 root만 열 수 있으니 8080 같은 포트를 씁니다.

https로 개발하려면 mkcert로 이 기계만의 인증서를 만듭니다. CA는 홈(`~/.local/share/mkcert`)에 남습니다.

```sh
mkcert localhost 127.0.0.1             # localhost+1.pem · localhost+1-key.pem
curl --cacert "$(mkcert -CAROOT)/rootCA.pem" https://localhost:8443
```

`mkcert -install`(시스템이 그 CA를 믿게 하기)은 TARS에서 아직 되지 않습니다. 위처럼 CA 파일을 직접 줍니다
(node는 `NODE_EXTRA_CA_CERTS`로 더할 수 있습니다).

## 문서

망 없이 바로 읽을 수 있는 것입니다.

```sh
man 3 printf                 # C 라이브러리
go doc fmt.Println
pydoc json
ri Array
erl -man lists
dasht printf Bash            # Bash docset — 찾아서 w3m으로 엽니다
w3m /usr/local/lib/rust-1.99.1/share/doc/rust/html/std/index.html   # rust 표준 라이브러리
```

다른 언어의 docset은 망이 있을 때 한 번 받습니다.

```sh
tars-docs                    # 깔린 언어 · 도구에 맞춘 목록과 크기, 받은 것은 *
tars-docs get                # 안 받은 것 전부(약 1,000MiB) — 합계를 보이고 묻습니다
tars-docs get Python Go      # 고른 것만
dasht 'ArrayList' Java       # 받은 뒤 찾기
```

받은 docset은 홈(`~/.local/share/dasht/docsets`)에 남습니다.

다음: `tars-help desk`
