# TARS Dev Layer — Design

접두사: TP (TARS Package — `carryover.md`의 패키지 매니저 항목이 비워 둔 이름)

Status: 초안 7판(2026-11-05) — 열린 질문 없음. 구현 전(TP-M0 plan `docs/plans/2026-11-05-tars-dev-layer-tp-m0.md`가 결정 2 · 6을 고쳤다). 결정 18(최소 디스크)과 initrd의 lsoff · doge는 먼저 들어갔다.

사용자의 요청(2026-11-05): "타스 리눅스를 설치하고 기본적으로 바로 뭔가를 컴파일하거나 자바 서버를 구동하고 싶다. 부팅 디스크에 담는
것은 원하지 않는다." 이어서 정한 것:

- 개발 도구 바이너리는 initrd에 들어가지 않는다. 설치된 디스크에서 망 없이 쓴다. 설치 USB에는 싣되 설치할 때 디스크로 옮긴다.
- `tars-install dev` 같은 하위 명령은 두지 않는다. `tars-install <disk>`(새 설치 · 갱신)가 개발 도구 층까지 처리한다.
- Debian 패키지보다 각 도구가 직접 내는 배포판을 선호한다. 각 최신 버전, LTS 정책이 있으면 최신 LTS.
- 소스에서 빌드하지 않는다. 미리 빌드된 바이너리를 쓴다 — linux-amd64는 보통 tier 1이다.
- USB는 8GB · 16GB가 있고, 대상 디스크는 거의 모두 100GB 이상이다(작은 임베디드 장비도 8GB 이상). 우선순위는 사용자의 구형
  맥북 에어를 개발 장비로 쓰는 것이다. rune은 뺀다. 최소 디스크는 16GiB로 올린다.
- Zeal 대신 `dasht` 조합을 쓴다. docset은 추천대로.
- 자주 쓰는 터미널 유틸리티도 싣는다("터미널 유틸리티" 표).
- 목표: "네트워크가 없는 곳에서도 코딩 · 개발을 할 수 있는 환경".

관련 문서: PM design 결정 4(컴파일러는 넣지 않는다 — 이 design이 다른 자리로 연다), `carryover.md`의 패키지 매니저 항목, HP design
(p3 `/home`), DI design(`tars-install`과 부팅 매체), KU design(이미지 슬롯 둘), MI design(mise), CT design
(`tars-service`).

## 한 줄 요약

빌드 컨테이너가 매니페스트(도구마다 버전 · URL · sha256 한 줄)대로 받아 묶음별 squashfs 이미지(`lang-native.sqfs` 같은 것) 여럿으로
굳히고, ISO에 initrd와 따로 싣는다. `tars-install`이 그 파일들을 p3로 복사하고, init이 부팅마다 loop로 열어 `/usr` 위에 읽기 전용
overlay로 겹쳐 얹는다. RAM에는 상주하지 않는다.

## 용어 (사용자, 2026-11-05)

- 개발 도구 층 — 전체 개념. 디스크(p3)의 squashfs들을 `/usr` 위에 읽기 전용 overlay로 겹친 것. 맨 "층"으로 쓰지 않는다.
- 묶음 — 그 안의 squashfs 파일 하나(`lang-native` 묶음, `util` 묶음).
- 도구 목록의 "층 N" — `kernel/guest_tools.sh`와 `devcontainer/Dockerfile`이 UT 때부터 쓴 initrd 도구 목록의 묶음 번호. 이 문서는 그
  뜻으로 "층"을 쓰지 않는다.
- 코드와 경로의 영어 이름(`/home/.tars/layers/`, dev layer)은 그대로다.

## 도구 목록 (사용자, 2026-11-05)

| 묶음 | 도구 |
|---|---|
| 네이티브 언어 | gcc · g++(C/C++), LLVM · clang · lld, zig, rust, odin, go |
| 스크립트 언어 | python3, ruby, lua, node, bun, janet, php |
| JVM | JDK, kotlin, scala3, clojure |
| BEAM | erlang, elixir, gleam |
| 편집기 | mitos `ms`(주 편집기), neovim, emacs, ttt(eugenioenko/ttt, 터미널 IDE — 사용자 확인) |
| 문서 | `dasht` + `w3m` + Dash/Zeal docset(결정 19) |
| 터미널 유틸리티 | 아래 "터미널 유틸리티" 표(사용자가 Homebrew 이름으로 준 것) |
| 서버 | nginx, caddy, postgresql 18, mysql 9.7(LTS), redis |
| AI | claude code, codex, opencode v2, oh-my-pi(`omp`) |

뺀 것: rune(GUI가 X11 · OpenGL을 요구하고 TARS에는 X가 없다, 사용자 결정). Zeal(Qt GUI, 같은 이유). helix(사용자 결정).

### 터미널 유틸리티 (사용자, 2026-11-05)

사용자가 Homebrew 이름으로 준 목록이다. 출처는 결정 1의 순서(`upstream` → `vendor-repo` → `prebuilt` → `debian`)로 milestone이 받으면서
확정한다. 아래 "출처 후보"는 이 design을 쓸 때의 어림이다.

| 처리 | 도구 |
|---|---|
| initrd에 trixie 판이 있고, `util` 묶음에 최신판도 싣는다(결정 20 — 설치된 기기에서는 최신판이 이긴다) | bat, duf, eza, fd, fzf, hyperfine, jq, ripgrep, sd, tree |
| initrd에 새로 넣었다(`docs/guides/initrd-criteria.md` 기준 B, 2026-11-05) | lsoff(yutat23/lsoff, `lsoff-linux-amd64` — 듣는 포트 목록), doge(Dj-Codeman/doge, musl 정적 — DNS 질의) |
| `upstream` 후보(GitHub 릴리스의 linux-amd64 바이너리) | asciinema(3.x), ast-grep, bed(itchyny), cidr, cloudflared, difftastic, dua-cli, dust, fastfetch, gdu, gitui, glow, go-task, gping, gron, herdr, hexyl, hugo(extended), hurl, jless, lazygit, lazysql, leaf-markdown-viewer(`leaf`), miller, pandoc, peco, procs, scc, starship, tailspin, tree-sitter-cli, uv, viddy, wasmtime, xh, yazi, sqlite(sqlite.org의 `sqlite-tools-linux-x64`), lisette(`lis`, cargo-dist의 `lisette-x86_64-unknown-linux-musl.tar.xz` — 정적. 만든 Go 코드를 짓는 데는 개발 도구 층의 go를 쓴다) |
| `upstream`이지만 다른 묶음에 기댄다 | hunk(npm 패키지, Node.js 18+ — `lang-script`의 node 위에 빌드 때 `npm install -g`), pillow(Python 라이브러리 — 개발 도구 층의 python에 manylinux wheel을 빌드 때 `pip install`) |
| AppImage를 빌드 때 풀어서(`--appimage-extract`, FUSE 없이) | imagemagick(`magick`), vifm — 안 되면 `debian` |
| `debian` | ipcalc, wget |
| 합친 것 | tree-sitter(Homebrew의 `tree-sitter`는 라이브러리, CLI는 `tree-sitter-cli` 하나로 본다) |

뺀 것: `soomtong/tap`의 cci · glc · tsl, fakesteak(미리 빌드된 바이너리가 없다) — 사용자 결정. hexyl은 initrd 후보(기준 B)였지만
사용자가 개발 도구 층에 두기로 했다.

initrd에 있는 열은 Debian trixie 판이라 최신이 아닐 수 있다. 그래서 `util` 묶음이 최신판을 `/usr/local/bin`에 따로 싣고, `PATH`가
`/usr/local/bin`을 `/usr/bin`보다 앞에 둔다(결정 20, 사용자). 설치된 기기에서는 최신판, 라이브 USB와 개발 도구 층이 없는 부팅에서는
trixie 판이 돈다.

## 확인 (2026-11-05, `92c15ed`, 커널 6.18.60)

1. 설치된 TARS에서도 `/`는 디스크가 아니라 RAM이다(`rootfstype=ramfs`, initrd가 통째로 풀린다). 디스크에 사는 자리는 p3 `/home`
   (ext4, `nosuid,nodev`, `noexec` 아님) 하나다. p1은 이미지 슬롯 둘, p2는 설정이다(`disk.SFDISK_SCRIPT`).
2. 오늘 UT 게이트가 남긴 initrd(gzip 122MB, 풀면 127MB)에 C 빌드에 필요한 것이 하나도 없다 — `/usr/include`, `crt1.o` · `crti.o` ·
   `Scrt1.o`, `libc.so`(링커 스크립트) · `libc_nonshared.a`, `cc` · `gcc` · `ld` · `as` · `make`. 런타임 쪽(`libstdc++.so.6` ·
   `libgcc_s.so.1` · `libz.so.1` · `ld-linux-x86-64.so.2`)은 있다.
3. 그래서 PM design 결정 4의 "`brew install gcc`가 열 수 있다"는 지금 낙관이다. PM-M1 첫 판의 gcc post-install 실패도 이것으로 보이지만
   원인은 기록되지 않았다(추정).
4. 커널: `# CONFIG_OVERLAY_FS is not set`, `CONFIG_SQUASHFS`는 `.config`에 줄이 없다. `ISO9660_FS=y` · `EXT4_FS=y`는 있다. loop
   (`BLK_DEV_LOOP`)는 M0이 확인한다.
5. Debian trixie로 잰 크기(`--download-only`, `debian:trixie` 기본 위): `gcc` · `g++` · `libc6-dev` · `make` 42개 68MB, 설치 266MB.
   `openjdk-21-jdk-headless` 11개 122MB, 설치 295MB. trixie의 gcc는 14.2.0이다.
6. Debian 패키지를 그냥 풀어서는 안 서는 것: `cc` · `c++` · `java` · `javac`는 `.deb` 안의 파일이 아니라 postinst의
   `update-alternatives`가 만든다. 공식 tarball은 이 문제가 없다(자기 디렉터리 안에 `bin/`이 있다).
7. JDK의 TLS 인증서: Debian 판은 `/etc/ssl/certs/java/cacerts`로의 링크다. 공식 tarball(Temurin)은 `lib/security/cacerts`를 자기 안에
   갖는다. TARS의 `/etc`는 부팅마다 만드는 tmpfs다.
8. 공식 바이너리 tarball이 없는 도구도 미리 빌드된 출처는 있다 — gcc(프로젝트가 바이너리를 내지 않는다 → Debian), python
   (python.org는 리눅스 바이너리를 안 낸다 → python-build-standalone), ruby(→ ruby/ruby-builder), php(→ static-php-cli의 정적 빌드),
   erlang(→ builds.hex.pm의 OTP 빌드), redis(→ packages.redis.io), postgresql(→ PGDG), nginx(→ nginx.org), lua · emacs(→ Debian
   `lua5.4` · `emacs-nox`). 각 출처가 지금도 이 모양인지는 그 묶음의 milestone이 받으면서 확인한다. mitos는 glibc tarball · `.deb`, ttt · neovim · caddy · bun · go · zig · node ·
   odin · gleam · janet · JDK · kotlin · scala3 · mysql은 공식 tarball이 있다(M0이 하나씩 확인한다).
9. ISO는 `boot/make_iso.sh`가 `xorriso`로 짓고 지금 138MB다. ISO9660은 파일 하나가 4GiB를 넘으면 `-iso-level 3`이 필요하다.
   부팅 매체는 iso9660 `TARS`로 판정되고(`disk.zig`), `tars-install`이 그 안의 `BOOT_FILES` 여섯을 ESP로 옮긴다.
10. 크기 어림(실측 아님): 설치 7~10GB, squashfs로 2.5~4GB. LLVM 공식 tarball 하나가 풀면 수 GB다. 정확한 숫자는 묶음마다 그 milestone이
    잰다.

## 결정

### 출처와 빌드

1. 출처는 매니페스트 한 파일이다(`devlayer/manifest.tsv` 가칭). 한 줄에 도구 · 묶음 · 버전 · 종류 · URL · sha256. 소스 빌드는
   없다(사용자 결정) — 종류는 모두 미리 빌드된 바이너리이고 넷이다. 앞의 것이 있으면 앞의 것을 쓴다.
   - `upstream` — 도구가 직접 내는 linux-amd64 바이너리 tarball. 기본값이다.
   - `vendor-repo` — 도구 쪽이 운영하는 Debian 저장소(PGDG의 postgresql, nginx.org의 nginx, packages.redis.io의 redis).
   - `prebuilt` — 표준이 된 제3자 빌드(python-build-standalone, ruby/ruby-builder, static-php-cli, builds.hex.pm의 erlang).
   - `debian` — glibc에 묶인 것과 위의 셋이 없는 것. gcc · `libc6-dev`(헤더 · crt는 initrd의 glibc와 같은 판이어야 한다) ·
     binutils, `lua5.4`, `emacs-nox`, 공용 라이브러리.
2. `upstream` · `prebuilt` tarball은 `/usr/local/lib/<도구>-<버전>/`에 그대로 풀고 `/usr/local/bin/`에 실행 파일 링크를 둔다. Debian식 alternatives는 없다.
   `debian`과 `vendor-repo`는 버리는 amd64 컨테이너(`--platform=linux/amd64 debian:trixie-slim`)에서 진짜로 `apt-get install`하고
   (postinst까지), 새로 생긴 파일만 가져온다. 개발 컨테이너는 arm64라 amd64 postinst를 못 돌린다(TP-M0 plan 확인 1). alternatives
   링크는 빌드 때 펴서 직접 링크로 놓는다.
3. 버전은 "최신, LTS가 있으면 최신 LTS"를 매니페스트에 고정한다. 바꾸는 것은 TARS 버전을 낼 때 한 단계로 한다
   (`project_release.md`의 절차에 한 줄 — 닫을 때 더한다). sha256이 다르면 빌드가 이름을 대고 실패한다.
4. 개발 도구 층에서 initrd와 겹치는 경로는 뺀다(initrd가 이긴다). 내용이 다르면 실패한다. 이것은 같은 경로의 이야기다 — 같은 이름이
   다른 경로에 있을 때(`/usr/local/bin/fd`와 `/usr/bin/fd`)는 결정 20의 `PATH`가 가른다.
5. 개발 도구 층의 모든 ELF의 `NEEDED`가 initrd + 개발 도구 층 안에서 풀리는지 빌드 때 검사한다. 공식 바이너리가 끄는 공용 라이브러리(libssl · libicu ·
   libncurses · libaio 등)는 `debian` 줄로 개발 도구 층에 더한다.
6. 개발 도구 층은 따로 빌드하고 캐시한다(`make dev-layers` 가칭). 매니페스트 줄이 안 바뀐 묶음은 다시 굽지 않는다. 받은 파일은 sha256 이름으로
   `devlayer/cache/`에 둔다 — 루트 게이트의 `clean()`이 `out`을 통째로 지우므로 `out/` 밖이다(TP-M0 plan 확인 4). `make iso`는 구워진 개발 도구 층이 있으면 싣는다 — 다른 체인은 개발 도구 층 없는 ISO로 돌아 게이트 시간이 지금과 같다.
   릴리스 ISO는 개발 도구 층을 싣는다.

### 디스크와 부팅

7. 개발 도구 층은 묶음마다 squashfs 하나다(`base.sqfs` · `lang-native.sqfs` · `lang-script.sqfs` · `lang-jvm.sqfs` · `lang-beam.sqfs` · `editor.sqfs` · `util.sqfs` ·
   `docs.sqfs` · `server.sqfs` · `ai.sqfs`). 하나가 4GiB를 넘지 않게 나눈다(확인 9). 압축은 M0이 xz와 zstd를 재서 고른다 — zstd 레벨 15(TP-M0 결과 2: xz보다 7~14% 크고 한 코어로 읽기가 9~17배 빠르다).
8. 커널에 `OVERLAY_FS` · `SQUASHFS`(고른 압축) · `BLK_DEV_LOOP`를 켠다. 켜기 전에 `rg -n '<SYMBOL>' */check.sh`로 음성 검사를 찾고,
   select로 따라오는 것을 본다(LP 배운 것 1).
9. 놓는 자리: p3의 `/home/.tars/layers/*.sqfs`(root 소유, 0644). init은 `/home`을 붙인 직후, 셸과 서비스를 띄우기 전에 각각을 loop로
   열어 `/run/tars-layers/<이름>`에 붙이고 `overlay`를 `lowerdir=<묶음들>/usr:/usr`로 `/usr`에 얹는다. upper가 없으므로 `/usr`는 읽기
   전용이 된다.
10. 개발 도구 층의 `/etc` 몫은 이미지 안 `etc/`에 두고 init이 overlay 뒤에 tmpfs `/etc`로 복사한다. `/etc`에는 overlay를 걸지 않는다.
11. 묶음이 없거나 열리지 않으면 TARS는 지금과 똑같이 뜬다. init이 `tars-init: layer <이름>: <이유>` 한 줄을 남기고 넘어간다.
12. ISO에 `boot/layers/*.sqfs`로 싣는다(슬롯이 아니라 한 벌). `tars-install <disk>`가 처리한다 — 새 설치는 p3를 만든 뒤 복사, 갱신은
    개발 도구 층도 새 버전으로 바꾼다. 계획 줄에 `layers  none -> 0.1.5 (3.1 GB)`처럼 한 줄을 넣어 YES 전에 보인다. 하위 명령은 없다.
13. 버전: 묶음마다 자기가 만들어진 TARS 버전을 안에 적는다(`/usr/share/tars/layers/<이름>`). old 슬롯으로 뜬 부팅에서 버전이 다르면
    얹지 않는다(결정 11의 한 줄).

### 도구별

14. 읽기 전용 `/usr`와 자동 갱신: claude code · opencode · omp 등 스스로 갱신하는 도구는 개발 도구 층의 사본에서 갱신을 끈다(도구마다 환경
    변수나 설정 — 해당 milestone이 정한다). 사용자가 최신을 원하면 홈에 따로 깐다.
15. JVM 계열(kotlin · scala3 · clojure)은 첫 실행 때 컴파일러 jar를 망에서 받는 경우가 있다. 개발 도구 층에 그 jar를 미리 넣고 오프라인으로
    한 번 돌아가는지를 그 milestone의 판정으로 삼는다.
16. 서버는 실행 파일까지가 개발 도구 층의 몫이다. 데이터는 `/home` 아래(`/usr`는 읽기 전용, `/var`는 RAM). 서비스로 띄우기(`tars-service`
    연결, `initdb` 등)는 서버 묶음 다음의 milestone이다.
17. AI 도구는 클라우드 모델을 부르므로 망이 있을 때만 동작한다. 오프라인 목표에 들지 않지만 목록대로 싣는다.
18. 최소 디스크는 16GiB + 2MiB다(`disk.MIN_DISK_BYTES`, HP design 결정 2의 4GiB를 사용자가 올렸다 — "요즘 작은 임베디드 장비도 8GB
    이상"). 개발 도구 층의 묶음이 p3에 놓일 자리다. 이 결정만 TP-M0보다 먼저 들어갔다(설치기 · 단위 검사 · 체인 install · home · pm · mise ·
    dualboot의 디스크 크기).
19. 문서는 `dasht`(Dash/Zeal docset을 터미널에서 찾는 셸 스크립트)와 `w3m`(HTML을 터미널에서 읽는다)이다. `dasht`가 부르는
    `sqlite3` · `w3m`은 `debian` 줄, docset은 `docs.sqfs`의 `/usr/share/dasht/docsets/`에 미리 풀어 둔다(`DASHT_DOCSETS_DIR`을 시스템
    rc가 그 자리로). docset은 Kapeli의 공식 피드에서 받는 미리 빌드된 tarball이다. 추천 묶음(사용자가 "추천대로"):
    - 언어: C, C++, Rust, Go, Python 3, Ruby, Lua, NodeJS, PHP, Java SE(개발 도구 층의 JDK와 같은 판), Erlang, Elixir, Clojure, Scala
    - 서버: PostgreSQL, MySQL, Redis, Nginx
    - 셸과 도구: Bash, CMake, Git(피드에 있으면), Vim(neovim 몫)
    공식 피드에 없는 언어(zig · odin · gleam · janet · kotlin · bun 후보)는 그 언어가 내는 오프라인 문서를 쓴다 — `zig std`(HTML),
    `go doc`, `rustup doc`의 HTML, `erl -man`, `ri`, `pydoc`. HTML은 `w3m`으로 읽는다. 피드의 실제 목록과 크기(Java SE가 수백 MB)는
    문서 묶음의 milestone이 받으면서 확인하고, 크기가 크면 그때 다시 묻는다.
20. `PATH`는 `/usr/local/bin:/usr/bin:/bin`이다(사용자, 2026-11-05). 개발 도구 층의 실행 파일 링크(결정 2)가 initrd의 같은 이름보다 앞선다.
    출처는 init의 `environ.PATH_ENTRY` 하나이고, 짝인 `config_front`의 `ENVP`와 sudoers의 `secure_path`가 같은 값을 든다. 개발 도구 층이
    없으면 `/usr/local/bin`이 없는 디렉터리라 셸이 건너뛴다. 셸 안의 실제 순서는 mise(`~/.local/bin`) → Homebrew → `/usr/local/bin` →
    `/usr/bin`이다 — 시스템 rc가 앞의 둘을 앞에 붙인다(PM 결정 5, MI 결정). 이 결정만 TP-M0보다 먼저 들어갔다.

## 열린 질문 (사용자가 정한다)

없다(2026-11-05). 닫은 것: gcc는 Debian trixie의 14.2(소스 빌드 없음, 미리 빌드된 최신 gcc는 trixie의 glibc와 맞는 것이 없다).
ruby · php는 `prebuilt`. ttt는 eugenioenko/ttt. 문서는 `dasht`(결정 19). 최소 디스크 16GiB(결정 18). fakesteak · `soomtong/tap` ·
helix는 뺀다. initrd에 실린 열 도구는 `util` 묶음에 최신판도 싣고 `PATH`로 최신판이 앞선다(결정 20). initrd에 넣는 기준은 `docs/guides/initrd-criteria.md`로 떼어 냈고,
그 기준으로 lsoff · doge가 initrd에 들어갔다(UT design 결정 3을 취소하는 첫 사례).

## 판정

- TP-M0: `base.sqfs`(Debian의 gcc · `libc6-dev` · make)와 `lang-jvm.sqfs`의 JDK(Temurin LTS, `upstream`) 둘이 결정 4 · 5의 검사를 지난다.
  두 종류의 출처를 하나씩 세우는 것이 본론이다. 크기 · 압축별 숫자 · 겹친 경로 수. 부팅은 바꾸지 않는다.
- TP-M1: 새 체인(가칭 `devtools`, monitor 45504) — `tars-install`로 깐 디스크로 다시 뜬 게스트에서 사용자로 `gcc hello.c && ./a.out`,
  `make`, `javac Hello.java && java Hello`, `jwebserver`를 띄워 `curl`이 받는다. 체인은 망을 끊고 돈다(`-nic none`) — 오프라인이 목표다.
  개발 도구 층 없이 뜬 부팅에서 `tars-init: layer` 줄과 기존 동작 그대로. 루트 게이트 — `/usr`가 읽기 전용이 된 것이 다른 체인을 흔들지 않는지.
- TP-M2 이후: 묶음마다 그 언어의 hello(또는 편집기의 실행, 서버의 응답)가 망 없이 도는 것.

## 비목표

1. 망에서 패키지를 더 받는 것(`apt install`에 해당). 묶음 밖은 Homebrew · mise.
2. 언어 생태계의 라이브러리를 오프라인으로 담는 것(crates · npm · PyPI · Maven · Hex의 미러). 오프라인 개발은 각 언어의 표준
   라이브러리 범위다.
3. 사용자가 개발 도구 층을 고치는 것(upper, `/usr`에 쓰기). `sudo pip install` 같은 사용법은 venv · `~/.local`로.
4. 라이브 USB(설치 전)에서의 개발 도구 층.
5. GUI 도구(rune · Zeal · AWT/Swing).
6. 묶음을 고르는 설치 옵션.
7. 소스 빌드(결정 1).

## 위험

1. `/usr`가 읽기 전용이 된다(결정 9). 실행 중에 `/usr`에 쓰는 TARS 코드나 체인이 있으면 깨진다. M0이 `rg`로 찾고 M1의 루트 게이트가 본다.
2. 공식 바이너리가 일반 배포판을 가정하고 TARS에 없는 것(`/etc`의 설정, `/usr/share`의 데이터, 특정 `.so`)을 찾는다. 결정 5가 `.so`는
   빌드 때 잡지만 파일 경로는 실행해 봐야 안다 — 묶음마다 hello를 판정으로 삼는 이유.
3. 빌드가 바깥 망 여러 곳(GitHub · 각 프로젝트 · Debian 미러)에 기댄다. 오늘 GitHub 다운로드가 504를 다섯 번 냈다. 캐시(결정 6)가
   한 번 받은 것은 다시 안 받는다.
4. 묶음이 클수록 릴리스 빌드와 `tars-install` 복사가 길다(USB 2.0에서 3GB면 수 분). 계획 줄에 크기를 보인다.
5. 보안 갱신은 TARS 버전을 낼 때만 따라온다.
6. 맥북 에어 2011(RAM 2~4GB)에서 큰 빌드 · JVM 서버 · mysql은 RAM을 쓴다. 개발 도구 층 자체는 page cache라 상주하지 않는다.

## Milestone

- TP-M0 — 결정 1~7(빌드 쪽). `base`와 JDK 둘. 부팅 무변경.
- TP-M1 — 결정 8~13. 커널 · ISO · `tars-install` · init · 체인 `devtools`.
- 그 뒤 묶음마다 하나씩 — 순서 후보: 네이티브 → 스크립트 → JVM → BEAM → 편집기 · 터미널 유틸리티 · 문서 → 서버(실행 파일) → 서버(서비스) → AI. 각 plan은
  앞 milestone의 숫자를 본 뒤 쓴다.
- 닫을 때: PM design 결정 4에 이 design으로의 한 줄, `carryover.md` 패키지 매니저 항목, `running-tars.md`의 "안 되는 것" 표,
  `project_release.md`의 버전 올리기 단계, `completed.md`, 기억 한 파일.
