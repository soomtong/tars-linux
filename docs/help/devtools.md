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
| util | rg · fd · bat · fzf · jq · lazygit · yazi · duckdb · sqlite3 · hyperfine · 그 밖의 터미널 도구 |
| media | ffmpeg · ImageMagick(magick) · GraphicsMagick(gm) |
| docs | dasht · w3m · `tars-docs` |

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
tars-docs get                # 안 받은 것 전부(약 700MiB) — 합계를 보이고 묻습니다
tars-docs get Python Go      # 고른 것만
dasht 'ArrayList' Java       # 받은 뒤 찾기
```

받은 docset은 홈(`~/.local/share/dasht/docsets`)에 남습니다.

다음: `tars-help desk`
