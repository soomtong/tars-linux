# TARS Dev Layer — Design

접두사: TP (TARS Package — `carryover.md`의 패키지 매니저 항목이 비워 둔 이름)

Status: 초안 15판(2026-11-07) — 열린 질문 없음(서버 영속성은 서비스 milestone으로 닫았다, 사용자). TP-M0 · TP-M1 · TP-M2 · TP-M3 · TP-M4 · TP-M5 · TP-M6 · TP-M7 · TP-M8 · TP-M9 끝, TP-M9 plan `docs/plans/2026-11-07-tars-dev-layer-tp-m9.md`가 결정 19(docset은 Bash 하나, 나머지는 `tars-docs get`으로 망에서 — 사용자 결정, `DASHT_DOCSETS_DIR`은 기본값)와 묶음 `docs`를 고쳤다, TP-M8 plan `docs/plans/2026-11-07-tars-dev-layer-tp-m8.md`가 터미널 유틸리티 표(자리 · 뺀 것 · duckdb · ffmpeg), 묶음 `media`, 결정 1의 `man1=` `.1.gz`를 고쳤다(사용자 결정), TP-M7 plan `docs/plans/2026-11-07-tars-dev-layer-tp-m7.md`가 편집기 줄(emacs는 `emacs-nox`, Doom은 사용자 설치)과 Milestone의 셋 나누기, 결정 1의 실행 파일 하나를 고쳤다(사용자 결정), TP-M6 plan `docs/plans/2026-11-06-tars-dev-layer-tp-m6.md`가 결정 1에 종류 `hex`와 선택 키 `man1=`을 더했다, TP-M5 plan `docs/plans/2026-11-06-tars-dev-layer-tp-m5.md`가 도구 목록에서 scala3를 빼고 cci · glc를 되돌렸다(사용자 결정), 결정 1에 종류 `maven`을 더했다(M4 plan `docs/plans/2026-11-06-tars-dev-layer-tp-m4.md`가 바닥 보강과 쓰기 가능한 `/usr/local` — 결정 9 · 비목표 3을 고쳤다. M0 plan이 결정 2 · 6을, M1 plan `docs/plans/2026-11-05-tars-dev-layer-tp-m1.md`가 결정 9의 lowerdir 순서와 결정 13의 비교 대상을, M2 plan `docs/plans/2026-11-06-tars-dev-layer-tp-m2.md`가 도구 목록의 네이티브 언어와 결정 1의 선택 열을, M3 plan `docs/plans/2026-11-06-tars-dev-layer-tp-m3.md`가 스크립트 언어 줄(luau · cyber)과 확인 8의 ruby · php 출처, 결정 1의 `strip=`을 고쳤다). 결정 18(최소 디스크)과 initrd의 lsoff · doge는 먼저 들어갔다.

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
| 바닥 | `base` 묶음(TP-M0 · M2 · M4): gcc · g++ · make, perl(+ perl-doc), pkgconf · cmake · ninja · autoconf · automake · libtool · m4 · bison · flex · gettext, coreutils 전부 · patch · file · xz · zstd · bzip2 · zip · unzip, openssh-client · rsync · gnupg, man-db · manpages · manpages-dev, gdb · strace · ltrace · valgrind, xxd · shellcheck · universal-ctags (사용자 2026-11-06 — "추천해 준 것 모두") |
| 네이티브 언어 | gcc · g++(C/C++ — `base` 묶음), zig, rust, go(`lang-native` 묶음, TP-M2) |
| 스크립트 언어 | python3, ruby, lua, luau, cyber, node, bun, janet, php(`lang-script` 묶음, TP-M3 — luau · cyber는 사용자가 2026-11-06에 더했다) |
| JVM | JDK, kotlin, clojure(`lang-jvm` 묶음, TP-M5) |
| BEAM | erlang, elixir, gleam(`lang-beam` 묶음, TP-M6 — gleam은 첫 프로젝트용 Hex 시드와 함께) |
| 편집기 | mitos `ms`(주 편집기), neovim, emacs(`emacs-nox` — Doom Emacs는 사용자가 망이 있을 때 깐다), ttt(eugenioenko/ttt, 터미널 IDE — 사용자 확인)(`editor` 묶음, TP-M7) |
| 문서 | `dasht` + `w3m` + Bash docset, 나머지 docset은 `tars-docs get`으로 망에서(`docs` 묶음, TP-M9 — 결정 19) |
| 터미널 유틸리티 | 아래 "터미널 유틸리티" 표(사용자가 Homebrew 이름으로 준 것 — `util` 묶음과 `media` 묶음, TP-M8) |
| 서버 | nginx, caddy, postgresql 18, mysql 9.7(LTS), redis |
| AI | claude code, codex, opencode v2, oh-my-pi(`omp`) |

뺀 것: rune(GUI가 X11 · OpenGL을 요구하고 TARS에는 X가 없다, 사용자 결정). Zeal(Qt GUI, 같은 이유). helix(사용자 결정). mg(사용자가 물었다 — emacs-nox를 싣는다, 2026-11-06). Doom Emacs의 시드(straight.el이 홈 경로로의 절대 링크 3,957개를 만들어 다른 홈으로 옮기면 안 선다 — TP-M7 plan 확인 4, 사용자 결정).
LLVM 툴체인(LLVM · clang · lld) · odin · tcc(사용자 결정 2026-11-06 — "GCC가 포함되니까 C나 Assembly 계열의 코드 작성은 문제가 없고,
디버거가 필요하면 직접 LLVM 툴체인을 설치한다"). scala3(사용자 결정 2026-11-06 — 아직 본격적으로 쓰지 않는다. 망 없이 `scala run`을 세우려면
컴파일 서버 Bloop(Scala 2.12로 쓰인 jar 134개, 111MiB, 상주 메모리 585MiB)까지 실어야 했다 — TP-M5 plan 확인 3). 필요해지면 Homebrew로 깐다.
LLVM 공식 tarball은 풀면 11.8GB였고 odin은 링크에 clang을 부른다. tcc는 리눅스
바이너리가 없어 Debian의 2020년 스냅숏뿐이었다(TP-M2 plan 확인 4 · 7).

### 터미널 유틸리티 (사용자, 2026-11-05)

사용자가 Homebrew 이름으로 준 목록이다. 출처는 결정 1의 순서(`upstream` → `vendor-repo` → `prebuilt` → `debian`)로 milestone이 받으면서
확정한다.

TP-M8(2026-11-07)이 받으며 확정한 자리다. 판 · 출처 · 확인은 plan `docs/plans/2026-11-07-tars-dev-layer-tp-m8.md`.

| 자리 | 도구 |
|---|---|
| `util` — initrd에 trixie 판이 있고 최신판을 `/usr/local/bin`에(결정 20 — 설치된 기기에서는 최신판이 이긴다) | bat, duf, eza, fd, fzf, hyperfine, jq, ripgrep, sd |
| `util` — `upstream`(GitHub 릴리스의 linux-amd64, gnu와 musl이 둘 다 있으면 gnu) | asciinema(3.x), ast-grep(`sg`는 링크하지 않는다 — shadow의 명령 이름), bed(itchyny), cidr, difftastic, dua-cli, dust, fastfetch, gitui, glow, go-task, gping, herdr, hexyl, hugo(extended), hurl, lazygit, lazysql, leaf-markdown-viewer(`leaf`), miller, peco, procs, scc, starship, tailspin, tree-sitter-cli, uv, viddy, wasmtime, xh, yazi, sqlite(sqlite.org의 `sqlite-tools-linux-x64` — SHA3-256을 대조하고 sha256을 적는다), duckdb 1.5.6(사용자가 더했다 — 2.0의 CLI는 x86-64-v3로 빌드돼 에어 2011에서 서지 않는다) |
| `util` — `debian` | wget, libxml2(hurl의 NEEDED) |
| `base` — `debian`(perl에 기대 base에 둔다, rlwrap과 같은 이유) | ipcalc, vifm(AppImage 대신 — 사용자 결정) |
| `media`(여덟째 묶음, TP-M8 — 사용자 결정) | ffmpeg 9.0(BtbN의 공유 빌드, 월말 태그에 고정 — 사용자가 더했다), ImageMagick · GraphicsMagick(`debian` — imagemagick의 AppImage는 X11 · 글꼴 라이브러리를 시스템에서 찾아 서지 않았다) |
| initrd에 넣었다(`docs/guides/initrd-criteria.md` 기준 B, 2026-11-05) | lsoff(yutat23/lsoff — 듣는 포트 목록), doge(Dj-Codeman/doge, musl 정적 — DNS 질의) |
| 합친 것 | tree-sitter(Homebrew의 `tree-sitter`는 라이브러리, CLI는 `tree-sitter-cli` 하나로 본다) |

뺀 것: `soomtong/tap`의 tsl, fakesteak(미리 빌드된 바이너리가 없다) — 사용자 결정. 같은 tap의 cci · glc는 사용자가 linux 빌드를 내어
(2026-11-06) TP-M5가 `util` 묶음의 첫 두 줄로 싣는다(출처는 각 저장소의 GitHub release — tap formula는 아직 macOS만 적는다). hexyl은 initrd 후보(기준 B)였지만
사용자가 개발 도구 층에 두기로 했다. TP-M8에서 뺀 것(사용자 결정 2026-11-07): cloudflared, pandoc, pillow, tree(upstream 바이너리가 없다 — initrd의
trixie 판), gron, jless, lisette, gdu(dua · dust · duf가 있다), hunk(bun 런타임을 품어 util의 25% — difftastic과 glc가 diff를 맡는다. npm도 같은 실행 파일을 받는다).

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
   (python.org는 리눅스 바이너리를 안 낸다 → python-build-standalone), ruby(→ spinel-coop/rv-ruby — ruby/ruby-builder는
   `/opt/hostedtoolcache`에 굳은 빌드라 옮길 수 없다, TP-M3 plan 확인 2), php(→ Debian trixie의 `php8.4-cli` — static-php-cli의
   미리 빌드는 2026-07의 8.5.8에서 멈췄다, 사용자 결정 2026-11-06, TP-M3 plan 확인 4),
   erlang(→ builds.hex.pm의 OTP 빌드), redis(→ packages.redis.io), postgresql(→ PGDG), nginx(→ nginx.org), lua · emacs(→ Debian
   `lua5.4` · `emacs-nox`). 각 출처가 지금도 이 모양인지는 그 묶음의 milestone이 받으면서 확인한다. mitos는 glibc tarball · `.deb`, ttt · neovim · caddy · bun · go · zig · node ·
   odin · gleam · janet · JDK · kotlin · mysql은 공식 tarball이 있다(M0이 하나씩 확인한다).
9. ISO는 `boot/make_iso.sh`가 `xorriso`로 짓고 지금 138MB다. ISO9660은 파일 하나가 4GiB를 넘으면 `-iso-level 3`이 필요하다.
   부팅 매체는 iso9660 `TARS`로 판정되고(`disk.zig`), `tars-install`이 그 안의 `BOOT_FILES` 여섯을 ESP로 옮긴다.
10. 크기 어림(실측 아님): 설치 7~10GB, squashfs로 2.5~4GB. 정확한 숫자는 묶음마다 그 milestone이 잰다. 잰 것: base 251MiB → 81MiB,
    lang-jvm 301 → 126, lang-native 2,018 → 402(TP-M2), lang-script 651 → 190(TP-M3). LLVM 공식 tarball은 풀면 11,853MiB였다 — 뺐다(도구 목록의 "뺀 것").

## 결정

### 출처와 빌드

1. 출처는 매니페스트 한 파일이다(`devlayer/manifest.tsv` 가칭). 한 줄에 도구 · 묶음 · 버전 · 종류 · URL · sha256. 소스 빌드는
   없다(사용자 결정) — 종류는 모두 미리 빌드된 바이너리이고 여섯이다(`maven`은 TP-M5, `hex`는 TP-M6). 앞의 것이 있으면 앞의 것을 쓴다.
   - `upstream` — 도구가 직접 내는 linux-amd64 바이너리 tarball. URL이 압축 확장자로 끝나지 않으면 실행 파일 하나다(TP-M7 — `bin/<도구>`에 0755로). 기본값이다.
   - `vendor-repo` — 도구 쪽이 운영하는 Debian 저장소(PGDG의 postgresql, nginx.org의 nginx, packages.redis.io의 redis).
   - `prebuilt` — 표준이 된 제3자 빌드(python-build-standalone, ruby/ruby-builder, static-php-cli, builds.hex.pm의 erlang).
   - `debian` — glibc에 묶인 것과 위의 셋이 없는 것. gcc · `libc6-dev`(헤더 · crt는 initrd의 glibc와 같은 판이어야 한다) ·
     binutils, `lua5.4`, `emacs-nox`, 공용 라이브러리.
   - `maven` — Maven Central의 jar · pom 여럿(TP-M5 plan 결정 B). 한 줄의 URL 자리는 잠금 파일(`devlayer/maven/<이름>.lock`, 줄마다 경로 ·
     sha256 — 처음 받을 때 Central의 `.sha1`과 대조해 적는다)이고, `into=`가 가리키는 도구의 `seed/m2/`에 놓는다. 배포처는 `upstream`과
     같은 자리다 — 다른 것은 받는 모양뿐이다. 첫 실행에 언어 자신의 jar를 받는 런처(clojure)가 그 시드를 사용자 캐시로 복사한다. 그 언어의
     실행에 필요한 jar만이다 — 비목표 2의 생태계 미러가 아니다.
   - `hex` — repo.hex.pm의 tarball 여럿(TP-M6 plan 결정 B). `maven`과 같은 잠금 파일(`devlayer/hex/<이름>.lock`, 줄마다 `<이름>-<판>.tar` · sha256 —
     Hex 레지스트리의 `outer_checksum`)이고, `into=`의 도구 `seed/packages/<sha256 대문자>.tar`(gleam 캐시의 이름)에 놓는다. 그 도구의 `seed/manifest.toml`이
     있으면 build.sh가 고정된 checksum과 대조한다. gleam의 런처가 첫 실행에 캐시로 복사하고, `gleam new` 뒤 그 `manifest.toml`을 넣는다(사용자 결정).
   매니페스트의 일곱째 열은 선택이다 — 공백으로 가른 `exe=` · `hook=` · `into=`(TP-M2 plan 결정 C)와 `strip=N`(풀고 벗길 맨 위
   디렉터리의 단 수, TP-M3 plan 결정 C), `man1=D`(D/*.1 · D/*.1.gz를 `/usr/local/share/man/man1`에 링크, TP-M6 plan 결정 F · TP-M8 plan 결정 D) — 다섯이다. zip도 받는다. `debian` 줄이 끌고 오는 패키지 가운데 initrd가 가진 것(tzdata · vim)은
   `devlayer/harvest-skip.tsv`가 싣지 않는다(TP-M3) — 그 패키지로 펴지는 alternatives 링크도 함께 빠진다(TP-M8 plan 확인한 것 2). 배포 형식이 절차를 요구하면
   (rust의 설치기) `devlayer/hooks/<형식>.sh`가 푼다. 열이 맞지 않는 줄은 줄 번호와 함께 빌드를 멈춘다(`devlayer/manifest.sh`).
   업스트림에 없는 파일(설정 · rc 조각)은 `devlayer/files/<묶음>/`의 트리가 뿌리에 얹는다(TP-M4 plan 결정 D). bash · zsh의 시스템 rc는
   `/etc/tars/rc.d/*.sh`를, fish는 `/etc/fish/conf.d/10-<묶음>.fish`를 읽는다.
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

7. 개발 도구 층은 묶음마다 squashfs 하나다(`base.sqfs` · `lang-native.sqfs` · `lang-script.sqfs` · `lang-jvm.sqfs` · `lang-beam.sqfs` · `editor.sqfs` · `media.sqfs` · `util.sqfs` ·
   `docs.sqfs` · `server.sqfs` · `ai.sqfs`). 하나가 4GiB를 넘지 않게 나눈다(확인 9). 압축은 M0이 xz와 zstd를 재서 고른다 — zstd 레벨 15(TP-M0 결과 2: xz보다 7~14% 크고 한 코어로 읽기가 9~17배 빠르다).
8. 커널에 `OVERLAY_FS` · `SQUASHFS`(고른 압축) · `BLK_DEV_LOOP`를 켠다. 켜기 전에 `rg -n '<SYMBOL>' */check.sh`로 음성 검사를 찾고,
   select로 따라오는 것을 본다(LP 배운 것 1).
9. 놓는 자리: p3의 `/home/.tars/layers/*.sqfs`(root 소유, 0644). init은 `/home`을 붙인 직후, 셸과 서비스를 띄우기 전에 각각을 loop로
   열어 `/run/tars-layers/<이름>`에 붙이고 `overlay`를 `lowerdir=<묶음들>/usr:/usr`로 `/usr`에 얹는다. upper가 없으므로 `/usr`는 읽기
   전용이 된다. 그 위 `/usr/local`만은 쓰기 가능하다(사용자 결정 2026-11-06, 관행대로 — TP-M4 plan 결정 H): init이 p3의
   `/home/.tars/local/{upper,work}`를 upper로 하는 overlay를 하나 더 건다(묶음이 없는 부팅에서도). root 0755라 쓰는 것은 root(sudo)뿐이고,
   재부팅 · 묶음 갱신에도 남는다. 묶음의 npm · gem · pip는 root의 전역 설치를 `/usr/local`로 보낸다(TP-M4 plan 결정 E).
10. 개발 도구 층의 `/etc` 몫은 이미지 안 `etc/`에 두고 init이 overlay 뒤에 tmpfs `/etc`로 복사한다. `/etc`에는 overlay를 걸지 않는다.
11. 묶음이 없거나 열리지 않으면 TARS는 지금과 똑같이 뜬다. init이 `tars-init: layer <이름>: <이유>` 한 줄을 남기고 넘어간다.
12. ISO에 `boot/layers/*.sqfs`로 싣는다(슬롯이 아니라 한 벌). `tars-install <disk>`가 처리한다 — 새 설치는 p3를 만든 뒤 복사, 갱신은
    개발 도구 층도 새 버전으로 바꾼다. 계획 줄에 `layers  none -> 0.1.5 (3.1 GB)`처럼 한 줄을 넣어 YES 전에 보인다. 하위 명령은 없다.
13. 버전: 묶음마다 자기가 만들어진 TARS 버전을 안에 적는다(`/usr/share/tars/layers/<이름>`). old 슬롯으로 뜬 부팅에서 버전이 다르면
    얹지 않는다(결정 11의 한 줄).

### 도구별

14. 읽기 전용 `/usr`와 자동 갱신: claude code · opencode · omp 등 스스로 갱신하는 도구는 개발 도구 층의 사본에서 갱신을 끈다(도구마다 환경
    변수나 설정 — 해당 milestone이 정한다). 사용자가 최신을 원하면 홈에 따로 깐다.
15. JVM 계열(kotlin · clojure — scala3는 TP-M5에서 뺐다)은 첫 실행 때 컴파일러 jar를 망에서 받는 경우가 있다. 개발 도구 층에 그 jar를 미리 넣고 오프라인으로
    한 번 돌아가는지를 그 milestone의 판정으로 삼는다.
16. 서버는 실행 파일까지가 개발 도구 층의 몫이다. 데이터는 `/home` 아래(`/usr`는 읽기 전용, `/var`는 RAM). 서비스로 띄우기(`tars-service`
    연결, `initdb` 등)는 서버 묶음 다음의 milestone이다.
17. AI 도구는 클라우드 모델을 부르므로 망이 있을 때만 동작한다. 오프라인 목표에 들지 않지만 목록대로 싣는다.
18. 최소 디스크는 16GiB + 2MiB다(`disk.MIN_DISK_BYTES`, HP design 결정 2의 4GiB를 사용자가 올렸다 — "요즘 작은 임베디드 장비도 8GB
    이상"). 개발 도구 층의 묶음이 p3에 놓일 자리다. 이 결정만 TP-M0보다 먼저 들어갔다(설치기 · 단위 검사 · 체인 install · home · pm · mise ·
    dualboot의 디스크 크기).
19. 문서는 `dasht`(Dash/Zeal docset을 터미널에서 찾는 셸 스크립트)와 `w3m`(HTML을 터미널에서 읽는다)이다(`docs` 묶음, TP-M9). `dasht`가
    부르는 `sqlite3`는 util의 것, `w3m`은 `debian` 줄이다. 싣는 docset은 Bash 하나다(사용자 결정 2026-11-07 — 추천 목록은 tgz로 약 1,000MiB라
    ISO의 2GiB 자리에 안 들어간다, TP-M9 plan 확인 1). 나머지는 망이 있을 때 `tars-docs get`(docs 묶음의 명령 — 깔린 언어 · 도구에 맞춘 열일곱,
    판이 있으면 판 고정 URL, 다 푼 tgz는 지운다)이나 dasht의 `dasht-docsets-install <이름>`으로 홈에 받는다. `DASHT_DOCSETS_DIR`은 기본값
    (`~/.local/share/dasht/docsets`)이다 — 디렉터리 하나라 읽기 전용 `/usr`로 잡으면 받기가 실패한다. 묶음의 Bash docset은 시스템 rc 조각이 그
    자리에 링크로 보인다. 서버 docset(PostgreSQL · MySQL · Redis · Nginx)은 서버 묶음이 `tars-docs`의 목록에 더한다. 피드에 없는 언어(zig · odin ·
    gleam · janet · kotlin · bun)와 망 없는 때는 그 언어가 내는 오프라인 문서를 쓴다 — `zig std`(HTML), `go doc`, rust-docs의 HTML, `erl -man`,
    `ri`, `pydoc`, `man 3`. HTML은 `w3m`으로 읽는다.
20. `PATH`는 `/usr/local/bin:/usr/bin:/bin`이다(사용자, 2026-11-05). 개발 도구 층의 실행 파일 링크(결정 2)가 initrd의 같은 이름보다 앞선다.
    출처는 init의 `environ.PATH_ENTRY` 하나이고, 짝인 `config_front`의 `ENVP`와 sudoers의 `secure_path`가 같은 값을 든다. 개발 도구 층이
    없으면 `/usr/local/bin`이 없는 디렉터리라 셸이 건너뛴다. 셸 안의 실제 순서는 mise(`~/.local/bin`) → Homebrew → `/usr/local/bin` →
    `/usr/bin`이다 — 시스템 rc가 앞의 둘을 앞에 붙인다(PM 결정 5, MI 결정). 이 결정만 TP-M0보다 먼저 들어갔다.

## 열린 질문 (사용자가 정한다)

없음.

닫은 것(2026-11-07): 서버의 데이터 · 설정 · 로그가 재부팅을 넘는 길(사용자 검토 요청 2026-11-07 — "mysql 같은 서버의 파일은 어디에 저장될까? 리부팅 후에도
   계속 유지되나?"). 서버 milestone(실행 파일 · 서비스)의 design이 정한다. 지금의 사실:
   - `/`(그래서 `/etc` · `/var` · `/tmp`)는 initrd를 푼 RAM(`rootfstype=ramfs`)이라 매 부팅 새로 선다. 묶음의 `etc/`는 init이 부팅마다
     `/etc`로 복사한다(`layers.zig`의 `copyTree`) — 고친 것은 다음 부팅에 원본으로 돌아간다. 남는 자리는 `/config`(p2 ext2, 작다) ·
     `/home`(p3 ext4 — 갱신도 넘는다) · `/usr/local`(실체 `/home/.tars/local`)뿐이다.
   - 그래서 기본값대로 띄운 mysql은 `/var/lib/mysql`이 RAM에 생겨 재부팅에 데이터베이스가 사라지고, 그동안 RAM(에어 2011은 2~4GB)을 먹는다.
     `/etc/mysql/my.cnf`를 고쳐도 되돌아가고, `/var/log`도 RAM에 쌓인다. postgres · redis · nginx도 같다.
   - 선례 둘: 블루투스는 `/var/lib/bluetooth` → `/config/bluetooth` 링크(`make_initrd.sh`)로 표준 경로를 지키고 실체만 남는 자리로 보냈다.
     chrony는 설정 맨 앞의 `confdir /config/chrony.d`로 `/etc`의 원본을 고치지 않고 사용자의 설정을 덧붙인다.

   Claude가 권한 방향(사용자 "That's a good idea" — 이 질문으로 적어 두자는 데 동의, 셋의 확정은 design에서):
   (a) 데이터는 표준 경로를 그대로 두고 실체만 `/home` 쪽으로 — `/var/lib/<서버>` → `/home/.tars/var/<서버>` 꼴의 링크. 문서 · 튜토리얼이
       가정하는 경로가 맞고, ext4라 크고, 갱신도 넘는다. `/config`(ext2)는 데이터에 쓰지 않는다. 링크를 누가 만드나: `/var`는 묶음이 못 닿는
       자리라 init이 부팅 때 묶음이 적은 목록으로 만드는 쪽이 후보(initrd 고정 링크는 묶음 없는 기계에도 생긴다).
   (b) 설정은 `/etc`의 원본을 고치지 않고 `/config/<서버>.d/`를 덧붙여 읽게 한다 — mysql `!includedir`, nginx `include`, redis `include`.
       postgres의 `postgresql.conf`는 데이터 디렉터리 안이라 (a)로 남는다.
   (c) 로그는 RAM의 `/var/log`에 쌓지 않는다 — stdout을 init 콘솔로(다른 서비스와 같다), 남겨야 하면 `/home` 쪽으로.

   닫음(사용자 2026-11-07, "I agree with you" · "핵심은 이게 영속성을 가지느냐"): 이 질문은 서버 설치가 아니라 영속성의 문제라
   서버(서비스) milestone이 맡는다. 방향은 (a) · (b) · (c)를 채택하고 세부(링크 목록의 모양, 서버 밖의 상태도 받는 범용 장치로 할지)는
   그 milestone plan이 정한다. 서버(실행 파일) milestone(TP-M10)은 이 장치 없이 부팅 하나 안의 응답까지만 보고, 데이터 경로는 사용자가
   띄울 때 `~` 아래로 준다(`--datadir` · `-D` · `--dir`) — 안내에 한 줄.

닫은 것(2026-11-05): gcc는 Debian trixie의 14.2(소스 빌드 없음, 미리 빌드된 최신 gcc는 trixie의 glibc와 맞는 것이 없다).
ruby · php는 `prebuilt`(TP-M3가 고쳤다 — ruby는 다른 `prebuilt`, php는 사용자 결정으로 `debian`). ttt는 eugenioenko/ttt. 문서는 `dasht`(결정 19). 최소 디스크 16GiB(결정 18). fakesteak · `soomtong/tap` ·
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
3. 사용자가 개발 도구 층을 고치는 것(`/usr`에 쓰기). `/usr/local`은 예외다 — 결정 9의 쓰기 층에 root가 깐다(TP-M4).
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
- 그 뒤 묶음마다 하나씩 — 순서 후보: 네이티브(M2) → 스크립트(M3) → 바닥 보강과 쓰기 가능한 `/usr/local`(M4, TP-M3 뒤 검토에서) → JVM → BEAM → 편집기(M7) → 터미널 유틸리티(M8) → 문서(M9, 사용자 결정 2026-11-06 — 셋으로 나눈다) → 서버(실행 파일) → 서버(서비스) → AI. 각 plan은
  앞 milestone의 숫자를 본 뒤 쓴다.
- 닫을 때: PM design 결정 4에 이 design으로의 한 줄, `carryover.md` 패키지 매니저 항목, `running-tars.md`의 "안 되는 것" 표,
  `project_release.md`의 버전 올리기 단계, `completed.md`, 기억 한 파일.
