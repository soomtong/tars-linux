# TP-M9 — 문서(docs): dasht · w3m · Bash docset

> 2026-11-07, `5d9e766` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: design 결정 19의 문서 도구를 싣는다 — `dasht`(Dash/Zeal docset을 터미널에서 찾는 셸 스크립트)와 `w3m`(HTML을 터미널에서 읽는다). 새 묶음 `docs`(아홉째)다.
판정은 묶음마다의 것 — 망 없이 docset 하나를 찾고 그 페이지를 읽는다.

사용자 결정(2026-11-07, 조사 결과를 보고):
- docset은 Bash 하나만 싣는다. 나머지는 사용자가 처음 쓸 때 망으로 받는다("처음에 네트워크를 통해 받으라고 하자"). design 19의 추천 묶음(약 1,000MiB — 확인 1)을
  싣지 않는다.
- GitHub release의 2GiB 한도는 지금 정하지 않는다(`project_release_0_2.md` — 미룸). 이 milestone은 ISO를 몇 MB만 키운다(확인 7).

## 착수 전 확인 (2026-11-07)

받기는 호스트, 풀기 · 실행은 amd64 trixie-slim(사용자 `tars`).

1. 피드(GitHub `Kapeli/feeds`의 `<이름>.xml`, 184개)와 크기(미러 `london.kapeli.com`에 HEAD, tgz). design 19의 추천 목록은 모두 피드에 있다 — Python은 `Python`,
   Java SE는 `Java`(최신 SE27). Git은 피드에 없다.

   | docset | 피드 판 | tgz MiB | 비고 |
   |---|---|---|---|
   | Redis | 8.10.2 | 213 | 풀면 992MiB — redis.io를 통째로 긁었다(964MiB가 `Documents/redis.io`) |
   | C++ · C | 판 없음 | 165 · 163 | C를 풀면 570MiB, 그중 450이 cppreference. C 라이브러리 man은 base의 `manpages-dev`에 있다 |
   | Rust | 1.99.1 | 141 | lang-native가 `rust-docs`(HTML)를 이미 싣는다(`devlayer/hooks/rust-installer.sh`의 허용 목록) |
   | Java | SE27(SE25는 판 URL로 64) | 79 | |
   | PHP | 판 없음 | 73 | |
   | MySQL · Erlang · Python · Ruby | 9.7 · 29.1.2 · 3.15.0 · 4.0.7 | 40 · 33 · 28 · 25 | |
   | Go · SQLite · NodeJS · CMake · Elixir · Vim · PostgreSQL · Clojure · Nginx · Bash · Lua | | 14 · 11 · 11 · 11 · 7 · 5 · 4 · 4 · 1 · 0.6 · 0.2 | |

   합 약 1,000MiB(추천 목록), ISO는 1.85GB라 2GiB까지 약 293MB — 겹치는 셋(Rust · C · Redis)을 빼도 약 485MiB라 들어가지 않는다. 사용자 결정의 근거다.
2. 판 고정 URL: `https://kapeli.com/feeds/zzz/versions/<이름>/<판>/<이름>.tgz`가 판이 있는 docset에 선다(Java SE25 · Rust 1.99.1 · Go · Python에 200).
   판 없는 넷(C · C++ · PHP · Bash, 피드의 `<version>`이 `/82`꼴)은 이 자리에 없다(46,528바이트의 HTML) — `https://kapeli.com/feeds/Bash.tgz` 하나뿐이고
   Kapeli가 갱신하면 내용이 바뀐다.
3. dasht: `sunaku/dasht`의 마지막 릴리스가 v2.4.0(2020-05-16)이고 릴리스 자산은 없다 — 태그 아카이브
   `https://github.com/sunaku/dasht/archive/refs/tags/v2.4.0.tar.gz`(sha256 `5ea43b0f7461e124d46b991892dedc8dcf506ccd5e9dc94324f7bdf6e580ff73`). 안에 `bin/`의
   POSIX sh 11개, `man/man1/`의 `*.1` 11개, `etc/zsh/completions/`. 부르는 것: `sqlite3`(util의 3.54.1), `w3m`, `awk` · `sed` · `grep`, `ps -e -o`(initrd의 procps),
   받기 쪽은 `wget`(util) · `gzip` · `xargs`(initrd). `dasht-server`는 `socat`을 부르고 웹 브라우저로 보는 것이다(맡아 정한 것 2).
4. `DASHT_DOCSETS_DIR`은 디렉터리 하나다(기본 `${XDG_DATA_HOME:-$HOME/.local/share}/dasht/docsets`). 찾기(`dasht-docsets`는 그 디렉터리의 `ls`)도 받기
   (`dasht-docsets-install`이 그 자리에 `wget` 뒤 `tar -x`)도 그 한 곳이다 — design 19처럼 시스템 rc가 이 변수를 읽기 전용 `/usr` 아래로 잡으면 받기가 실패한다.
5. 컨테이너 시험(dasht 2.4.0 + trixie의 w3m · sqlite3 3.46.1, 망 없이):
   - `dasht-docsets` → `Bash`. `dasht-query-line printf Bash` → `name = printf` · `type = Builtin` · `url = file://…/Bash-Builtins.html#//apple_ref/Builtin/printf`.
   - `w3m -dump <그 url>` → "4.2 Bash Builtin Commands" 절이 글자로 나온다(조각 `#…`으로 건너뛰지는 않는다 — 덤프는 페이지 처음부터).
   - `dasht printf Bash`(w3m을 연다)가 결과 페이지를 그린다.
   - docset을 다른 디렉터리에 두고 `DASHT_DOCSETS_DIR`에는 심볼릭 링크만 두어도 `dasht-docsets` · `dasht-query-line`이 그대로 찾는다(결정 B의 근거).
   - 망을 열고 `dasht-docsets-install -f '^Lua$'`: GitHub API로 피드 목록을 `~/.cache/dasht`에 두고, `kapeli.com/feeds/Lua.tgz`를 받아
     `~/.local/share/dasht/docsets/Lua.docset`에 풀었다(받은 `Lua.tgz`도 그 자리에 남는다). 그 뒤 `dasht-query-line string.format Lua`가 찾는다.
6. w3m: trixie `0.5.3+git20230121-2.1`, Installed-Size 2,848KiB, 의존 libgc1 · libgpm2 · libssl3t64 · libtinfo6 · zlib1g(뒤의 셋은 initrd에 있을 것 — 거두기가 센다).
7. Bash docset: `https://kapeli.com/feeds/Bash.tgz`, 피드 판 `/9`, 619KiB, sha256 `f46c2566083bb6aa9e1a2a38fda8d97d8adb76851f1254d6d0e5a11b66a71712`, Last-Modified
   2025-10-02. 풀면 1.6MiB, 맨 위가 `Bash.docset/` 하나.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 새 묶음 `docs`에 세 줄:
   - `dasht` 2.4.0 `upstream`(확인 3의 태그 아카이브) `exe=` 아홉(`dasht` · `dasht-docsets` · `dasht-docsets-extract` · `-install` · `-remove` · `-update` ·
     `dasht-query-exec` · `-html` · `-line`) `man1=man/man1`.
   - Bash docset `upstream` `into=dasht strip=0` — `/usr/local/lib/dasht-2.4.0/Bash.docset`. `into=`의 규칙대로 버전 열은 dasht의 판(2.4.0)을 쓰고(rust-src와 같다),
     docset 자신의 날짜는 줄 위 주석에 둔다. 실행 파일이 없는 줄이라 `into=` 없이는 굽기가 `nothing to link`로 멈춘다.
   - `w3m` 0.5.3+git20230121-2.1 `debian`.
B. `DASHT_DOCSETS_DIR`은 건드리지 않는다(기본값 — 홈). 시스템 rc 조각이 홈의 그 자리에 Bash docset 링크를 둔다 — 없거나 깨진 링크일 때만
   `ln -sfn /usr/local/lib/dasht-2.4.0/Bash.docset "$d/Bash.docset"`. 사용자가 진짜 디렉터리로 바꿔 두었으면 손대지 않는다. `XDG_DATA_HOME`을 따른다. 아무것도 찍지
   않는다. bash · zsh는 `devlayer/files/docs/etc/tars/rc.d/docs.sh`, fish는 `etc/fish/conf.d/10-docs.fish`. 이렇게 하면 망으로 받은 docset(홈)과 묶음의 Bash가 한
   디렉터리에서 보이고, 받기에 sudo가 필요 없으며, 받은 것은 `/home`에 남는다(design 결정 16의 "데이터는 `/home`"과 같은 쪽).
C. 나머지 docset은 사용자가 망이 있을 때 `dasht-docsets-install <이름>`으로 받는다. 이것을 `docs/guides/running-tars.md`에 적는다 — 명령, 받는 자리, 확인 1의
   크기 표(큰 것을 먼저 알게), 이미 오프라인으로 있는 문서(`rust-docs` HTML · `man 3` · `erl -man` · `go doc` · `pydoc` · `ri` · `perldoc`)를 w3m · man으로 여는 법.
D. design 결정 19를 고친다(14판): `docs` 묶음은 dasht · w3m · Bash docset, `DASHT_DOCSETS_DIR`은 기본값, 추천 목록은 "싣는 것"이 아니라 "망으로 받기를 권하는 것"으로
   크기와 함께. 묶음 표에 `docs`.

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 글자로)

1. dasht는 GitHub 태그 아카이브다(릴리스 자산이 없다). Debian에도 `dasht`가 없다.
2. `dasht-server` · `dasht-server-http`는 링크하지 않는다 — `socat`(TARS에 없다)과 그래픽 브라우저를 전제로 한다. 파일은 도구 디렉터리에 남는다.
3. zsh 완성(`etc/zsh/completions/`)은 싣기만 하고 잇지 않는다(TP-M8 맡아 정한 것 3 — `carryover.md`의 셸 완성 항목과 같다).
4. Bash docset의 URL은 판 고정이 없다(확인 2). sha256을 적고, Kapeli가 갱신해 캐시 밖에서 받을 때 어긋나면 빌드가 이름을 대고 멈춘다 — 다른 도구와 같은 처리다.
   TARS 버전을 낼 때 함께 올린다(design 결정 3).
5. 링크는 rc가 셸이 열릴 때 만든다 — 대화형 셸만 rc를 읽으므로 `bash -c` 같은 비대화형 첫 사용에서는 아직 없다. TARS 터미널의 셸은 대화형이라 실제로는 처음
   터미널을 열 때 선다. 설치기 · 홈 시드에 넣지 않는 것은 묶음이 없는 TARS(묶음 없는 ISO)에서도 그 경로가 생기지 않게 하려는 것이다 — rc 조각 자체가 묶음 안에 있다.

## 할 일

1. 매니페스트: `# ── docs` 머리 주석과 세 줄(결정 A).
2. `devlayer/files/docs/`: rc 조각 둘(결정 B).
3. docs를 잇는 자리: `Makefile`의 `DEV_LAYERS`, `devtools/check.sh`의 빌드 줄 · `ISO_LAYERS` · `LAYERS` · lowerdir · 묶음 수, `rg -n 'media util'`로 한 번 더.
4. `make dev-layers` — 숫자: docs의 풀린 크기 · zstd, 거둔 패키지 수, NEEDED, 묶음 사이 `shared`.
5. chroot로 체인 덩이를 먼저.
6. 체인 부팅 2에 덩이 하나(사용자 tars, 망 없이): `bash -c ". /etc/bash.bashrc; …"`로 rc를 읽힌 뒤 `dasht-docsets` → `Bash`, `dasht-query-line printf Bash`의 `name =`,
   그 `url`을 `w3m -dump`해 "Bash Builtin Commands", `MANPAGER=cat man dasht`. 링크를 지우고 `fish -c dasht-docsets`로 fish 조각도 한 번.
   표시 글자는 명령 줄에 그대로 쓰지 않는다(TP-M4 plan 확인한 것 9).
7. 빨강: (a) rc 조각의 `ln` 줄을 빼면 체인이 `dasht-query-line`의 결과 없음을 이름으로 대고 멈춘다. (b) w3m 줄을 빼면 체인의 `w3m -dump` 덩이가 멈춘다(initrd에 w3m이
   없다 — 스크립트라 verify의 NEEDED는 못 잡는 의존이다).
8. 체인 혼자 한 번, 숫자로 상한을 고친다.
9. `make quick`, 루트 게이트(약 35분). design(결정 19 · 묶음 표), `running-tars.md`(결정 C), HANDOFF.

## 판정

- `make dev-layers`가 초록이고, docs의 NEEDED · 겹침 · 묶음 사이 검사가 지난다.
- 체인의 부팅 2에서 할 일 6의 덩이가 망 없이 사용자로 돈다. 할 일 7의 빨강 (a) · (b)를 봤다.
- 루트 게이트 초록, 잘린 줄 0.

## 비목표

1. 망으로 docset 받기(`dasht-docsets-install`) — 체인은 망이 없다. 확인 5의 컨테이너 시험과 실기로 본다.
2. design 19의 추천 docset을 싣기(사용자 결정).
3. `dasht-server`(맡아 정한 것 2).
4. 셸 완성(맡아 정한 것 3).
5. GitHub release의 2GiB 한도(사용자 결정 — 미룸).
6. 대화형 w3m 화면이 TARS 터미널에서 맞게 그려지는지 — 실기에서 본다(TP-M8 비목표 2와 같다).

## 위험

1. Kapeli의 판 없는 URL(맡아 정한 것 4) — 캐시가 없는 기기에서 받을 때 sha256이 어긋날 수 있다. 멈춤은 이름을 대므로 원인은 바로 보인다.
2. `dasht-docsets-update`가 홈의 Bash 링크를 갱신하려 들면 링크를 진짜 디렉터리로 바꾸며 받을 것이다(GNU tar가 디렉터리 자리의 심볼릭 링크를 지우고 만든다) —
   그 뒤에는 홈의 사본이 쓰이고 rc는 손대지 않는다(결정 B). 실기 확인으로 남긴다.
3. 받은 tgz가 docset 옆에 남는다(dasht의 동작 — 확인 5). 큰 docset은 홈을 두 배로 쓴다. `running-tars.md`에 적는다.
4. 묶음이 아홉이 된다 — init의 상한은 16(`init/src/layers.zig`의 `MAX`). 체인 시간은 거의 같다(묶음 몇 MB).

## 확인한 것

## 결과
