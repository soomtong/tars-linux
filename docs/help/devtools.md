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

AI 코딩 도구는 싣지 않습니다 — 모델을 망으로 부르므로 망이 있을 때 각자의 공식 설치로 홈에 받습니다. 받은 것은 재부팅 · 갱신에도 남습니다.

```sh
curl -fsSL https://claude.ai/install.sh | bash          # Claude Code → ~/.local/bin/claude
curl -fsSL https://chatgpt.com/codex/install.sh | sh    # Codex → ~/.local/bin/codex
curl -fsSL https://opencode.ai/install | bash           # OpenCode → ~/.opencode/bin/opencode
curl -fsSL https://omp.sh/install | sh                  # oh-my-pi → bun으로 ~/.bun/bin/omp
```

`~/.local/bin`과 `~/.bun/bin`은 셸이 PATH에 잇습니다(새 셸부터) — 설치기가 PATH를 고치라고 안내해도 따로 할 일은 없습니다.
TARS 커널에는 사용자 이름공간이 없어 codex의 샌드박스가 서지 않습니다(`bwrap: Creating new namespace failed`). 명령을 실행시키려면
`codex --sandbox danger-full-access`로 띄웁니다 — 샌드박스 없이 내 권한으로 돌고, 명령마다 묻는 것은 그대로입니다.

## 서버

postgres · mysql · redis · nginx · caddy를 서비스로 켜면 부팅할 때마다 저절로 뜹니다. 기본은 모두 꺼져 있습니다.

```sh
sudo tars-service enable postgres      # 켭니다 — 지금 뜨고, 다음 부팅에도 뜹니다
sudo tars-service status postgres
sudo tars-service disable postgres     # 끕니다 — 지금 멈추고, 다음 부팅에도 안 뜹니다
```

| 서버 | 주소 | 처음 켤 때 |
|---|---|---|
| postgres | `/tmp` 소켓 · 127.0.0.1:5432 | 내 계정이 슈퍼유저입니다. 비밀번호 없이 붙습니다(`psql postgres`) |
| mysql | `/tmp/mysql.sock` · 127.0.0.1:3306 | `mysql -uroot`, 비밀번호 없음 |
| redis | 127.0.0.1:6379 | `redis-cli ping` |
| nginx | http://127.0.0.1:8080 | 기본 페이지 |
| caddy | http://127.0.0.1:8081 | 안내 한 줄 |

- 서버는 내 계정으로 돕니다. 그래서 1024 아래 포트(80 · 443)는 열 수 없고, 모두 이 기계 안(127.0.0.1)에서만 들립니다.
- 데이터는 `/home/.tars/var/<서버>`에 남습니다. `/var/lib/<서버>`는 그리로 가는 링크입니다(`/var`는 부팅마다 새로 만들어집니다).
- 내 설정은 `/config/<서버>.d/`에 둡니다. 재부팅과 갱신을 넘어 남고, 다시 띄우면 읽습니다.

```sh
sudo vi /config/nginx.d/app.conf       # server { listen 127.0.0.1:8082; root /home/tars/www; }
sudo tars-service restart nginx
```

| 서버 | 조각 자리 | 모양 |
|---|---|---|
| postgres | `/config/postgres.d/*.conf` | `postgresql.conf`의 줄 |
| mysql | `/config/mysql.d/*.cnf` | `[mysqld]` 절 |
| redis | `/config/redis.d/*.conf` | `redis.conf`의 줄 |
| nginx | `/config/nginx.d/*.conf` | `server { … }` 블록(http 안에 읽힙니다) |
| caddy | `/config/caddy.d/*.caddy` | 사이트 블록 |

서버의 출력은 init의 콘솔로 가고 파일로는 남지 않습니다. 남기려면 조각에 씁니다. 예를 들어 postgres는
`logging_collector = on`이면 데이터 안의 `log/`에, nginx는 `access_log /home/.tars/var/nginx/access.log;`로 남습니다.

서비스로 켜지 않고 홈에서 직접 띄워도 됩니다. 데이터를 홈 아래에 둡니다.

```sh
initdb -D ~/pg && pg_ctl -D ~/pg -o "-k /tmp" -l ~/pg.log start     # postgres
mysqld --initialize-insecure --datadir=$HOME/mysql && mysqld --datadir=$HOME/mysql &
redis-server --dir ~ --daemonize yes
caddy file-server --listen :8000       # 지금 디렉터리를 보입니다
```

https로 개발하려면 mkcert로 이 기계만의 인증서를 만듭니다. CA는 홈(`~/.local/share/mkcert`)에 남습니다.

```sh
mkcert localhost 127.0.0.1             # localhost+1.pem · localhost+1-key.pem
mkcert -install                        # 이 기계가 그 CA를 믿게 합니다(sudo 비밀번호를 묻습니다)
curl https://localhost:8443            # 이제 --cacert 없이 믿습니다
```

`mkcert -install`은 CA를 `/usr/local/share/ca-certificates/`에 두고 `update-ca-certificates`를 부릅니다. 그 자리는 재부팅에도
남고, 부팅할 때 다시 읽힙니다. 믿지 않게 하려면 `mkcert -uninstall`입니다. node는 시스템 목록을 안 읽으니
`NODE_EXTRA_CA_CERTS="$(mkcert -CAROOT)/rootCA.pem"`으로 더합니다.

서버를 처음 켤 때 이 기계만의 자체 서명 인증서도 하나 만듭니다(`/config/ssl/tars-selfsigned/cert.pem` · `key.pem`, localhost와
127.0.0.1). 믿을 필요 없이 https를 켜 보는 데 씁니다.

```nginx
server {
  listen 127.0.0.1:8443 ssl;
  ssl_certificate     /config/ssl/tars-selfsigned/cert.pem;
  ssl_certificate_key /config/ssl/tars-selfsigned/key.pem;
  root /usr/share/nginx/html;
}
```

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
