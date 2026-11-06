# TP-M3 — `lang-script` 묶음(python3 · ruby · lua · luau · cyber · node · bun · janet · php)

> 2026-11-06, `f12ffa3` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: TP design 도구 목록의 "스크립트 언어" 줄을 개발 도구 층에 싣는다. 판정은 design "TP-M2 이후"대로 각 언어의 hello가
devtools 체인에서 망 없이(`-nic none`) 사용자로 도는 것이다.

사용자 결정(2026-11-06): php는 Debian 저장소를 따른다. "사실 php 잘 쓰지 않습니다." — design 열린 질문에서 닫았던 "php는
`prebuilt`(static-php-cli)"를 뒤집는다(확인 4). 이어서 Luau를 더한다(같은 날, 사용자 — "로블록스에서 관리하는 엔진"). design 도구
목록의 스크립트 언어 줄에 없던 것이다(확인 9). 또 사용자가 관리하는 Cyber(soomtong/cyber, fubark/cyber의 fork)를 더한다(같은 날, 확인 10).

## 착수 전 확인 (2026-11-06, 호스트에서 받아서 · 개발 컨테이너의 `readelf`로 · amd64 trixie-slim에서 실행)

1. 판(각 배포처의 기계용 목록):

   | 도구 | 판 | 받는 것 | 받는 크기 | 풀린 크기 | sha256 출처 |
   |---|---|---|---|---|---|
   | python3 | 3.15.2 | python-build-standalone `20261026`의 `cpython-3.15.2+20261026-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz` | 38,129,918 | (할 일 3) | GitHub 자산의 `digest` |
   | ruby | 4.0.9 | spinel-coop/rv-ruby `20261023`의 `ruby-4.0.9.x86_64_linux.tar.gz` | 49,714,550 | 165MiB | GitHub 자산의 `digest` |
   | lua | 5.4.7 | Debian trixie `lua5.4 5.4.7-1+b2` | — | — | apt(서명된 Release) |
   | luau | 0.745 | luau-lang/luau의 `luau-ubuntu.zip` | 7,871,445 | 21MiB | GitHub 자산의 `digest` |
   | cyber | 0.4.2 | soomtong/cyber의 `cyber-linux-x64.tar.gz` | 1,535,795 | 4MiB | GitHub 자산의 `digest` |
   | node | 26.13.0(LTS) | `node-v26.13.0-linux-x64.tar.xz` | 34,083,252 | 238MiB | `nodejs.org/dist/v26.13.0/SHASUMS256.txt` |
   | bun | 1.4.4 | `bun-linux-x64-baseline.zip` | 51,794,559 | 103MiB | GitHub 자산의 `digest` |
   | janet | 1.42.1 | `janet-v1.42.1-linux-x64.tar.gz` | 3,073,914 | 11MiB | GitHub 자산의 `digest` |
   | php | 8.4.27 | Debian trixie-security `php8.4-cli 8.4.27-1~deb13u1` | — | — | apt |

   받은 바이트의 sha256이 일곱 다 배포처의 값과 같다. python은 strip하지 않은 `install_only`(82,941,798, 풀면 543MiB)도 받아 봤다.
   node 최신은 v27 alpha라서 LTS(`index.json`의 `lts`가 붙은 첫 줄)를 고른다. python 3.16은 아직 alpha다. lua 공식 최신은 5.5.1이지만
   lua.org는 소스만 낸다 — trixie에는 5.4뿐이다(design 확인 8의 "`debian`"이 그대로 맞다).
2. ruby의 출처를 바꾼다. design 확인 8이 적은 ruby/ruby-builder의 `ruby-4.0.9-ubuntu-24.04-x64.tar.gz`는
   `--prefix=/opt/hostedtoolcache/Ruby/4.0.9/x64`로 굳은 빌드다. `LIBRUBY_RELATIVE = "no"`이고, `bin/ruby`의 RUNPATH도
   `/opt/hostedtoolcache/Ruby/4.0.9/x64/lib`로 절대 경로다. 표준 라이브러리 경로도 libruby 안에 그 접두로 박혀 있다. setup-ruby가
   늘 그 자리에 풀기 때문에 그렇게 지었고, `/usr/local/lib/`로 옮기면 서지 않는다. 또 `libgmp.so.10`을 끈다. rv-ruby(Homebrew
   portable-ruby와 같은 방식)는 `--enable-load-relative`로 지었다(`LIBRUBY_RELATIVE = "yes"`). openssl · psych · zlib · libffi는
   정적이고, `bin/ruby` · `openssl.so` · `psych.so`의 NEEDED는 libc 계열뿐이다. glibc 요구는 최대 `GLIBC_2.38`이다(trixie는 2.41).
   종류는 같은 `prebuilt`다.
3. bun은 일반 빌드가 AVX2를 요구한다. TCG의 qemu64에도, 맥북 에어 2011(Sandy Bridge — AVX는 있고 AVX2는 없다)에도 AVX2가 없다.
   그래서 `baseline`을 쓴다. glibc 판(`musl`이 아닌 것)이고 NEEDED는 libc 계열이며 `GLIBC_2.17`이다.
4. php. design의 static-php-cli 미리 빌드는 `dl.static-php.dev`의 `common/` · `bulk/` · `gnu-bulk/` · `minimal/` 모두 2026-07-07의
   8.5.8에서 멈췄다. php.net의 8.5는 8.5.12이고(2026-10-21), static-php는 sha256도 내지 않는다. php.net의 Debian 설치 안내는
   packages.sury.org(8.5.12)를 가리킨다. 사용자가 셋(sury `vendor-repo` · Debian 8.4 · static 8.5.8) 가운데 Debian을 골랐다.
   `vendor-repo`는 서버 묶음(PGDG · nginx.org · redis)이 처음 세운다.
5. tarball 모양. 지금의 `build.sh`가 받는 것은 "tar, 맨 위 디렉터리 하나"뿐인데 넷이 그 틀을 벗어난다.
   - node: `node-v26.13.0-linux-x64/bin/{node,npm,npx}` — 틀 그대로. `npm` · `npx`는 `../lib/node_modules/npm/bin/*.js`로의 링크다.
   - python: `python/bin/`(`python3` · `pip3` · `pydoc3` · `idle3` · `python3-config` 등 열둘) — 틀 그대로.
   - janet: 모든 경로가 `./janet-v1.42.1-linux/`로 시작한다. 지금의 맨 위 판정(`s#/.*##`)은 `.`을 맨 위로 본다.
   - ruby(rv): 맨 위가 두 단이다 — `rv-ruby@4.0.9/4.0.9/{bin,lib,include,libexec,share}`.
   - php(static): 디렉터리 없이 `php` 파일 하나였다(이번에는 안 쓴다).
   - bun: zip이고 `bun-linux-x64-baseline/bun` 하나, `bin/`이 없다.
   - luau: zip이고 디렉터리 없이 실행 파일 넷(`luau` · `luau-analyze` · `luau-compile` · `luau-ast`)이 맨 위에 있다.
6. NEEDED. node는 `libatomic.so.1` · `libstdc++.so.6` · `libgcc_s.so.1`을 끈다. trixie-slim에는 `libatomic.so.1`이 없어 거기서는
   못 떴다. initrd에는 셋 다 있다. python은 RUNPATH가 `$ORIGIN/../lib`이고 libc 계열만 끈다. ssl은 자기 안의 OpenSSL 3.5.9다.
   janet은 `libm` · `libc`만 끈다(`GLIBC_2.38`).
7. amd64 trixie-slim에서 바로 돌려 본 것(Rosetta, root): janet `1.42.1`, bun `1.4.4`, ruby `-ropenssl` `4.0.9`(OpenSSL ext 4.0.2),
   python `3.15.2`(`ssl` OK). node는 6처럼 trixie-slim에서는 못 떴다.
8. initrd에는 `python3` · `ruby` · `lua` · `node` · `php` · `perl`이 없다(`usr/bin` · `bin`). 같은 이름을 initrd와 다투지 않는다.
   개발 컨테이너에는 `unzip`이 있다(`/usr/bin/unzip`).
9. Luau(Roblox가 관리하는 Lua 계열 언어, 점진적 타입). 릴리스는 매주 `0.NNN`이다. 리눅스 자산은 `luau-ubuntu.zip` 하나이고, 실행 파일 넷의
   NEEDED는 `libstdc++.so.6` · `libgcc_s.so.1` · libc 계열이다. 요구하는 판은 `GLIBC_2.34`와 `GLIBCXX_3.4.30`이고, initrd의
   `libstdc++.so.6.0.33`은 3.4.33까지 낸다. trixie-slim에서 타입 주석이 붙은 hello가 `tp-luau-42`를 찍었고 `luau-analyze`가 통과했다.
   `luau --version`은 없다(`Unrecognized option`) — 판은 매니페스트가 기록한다.
10. Cyber(soomtong/cyber, Zig로 지은 스크립트 언어). 릴리스에 `latest` 태그가 있지만 같은 이름에 새 자산이 올라오는 움직이는 태그라서
    sha256 고정과 맞지 않는다. 판 이름 태그 `0.4.2`(2026-11-01)를 쓴다. tarball 맨 위에 디렉터리가 없다 — `cyber`(3.4MB)와
    `src/builtins/*.cy` · `src/std/*.cy`. NEEDED는 libc 계열뿐이다. 실행 파일은 자기 실제 위치 옆의 `src/`를 읽는다. 실행 파일만 떼면
    `Can not load …/src/builtins/core.cy`로 실패하고, `/usr/local/bin`의 링크로 부르면 링크를 따라가 찾는다(trixie-slim에서 확인).
    `use math`와 함수 · 문자열 보간이 든 hello가 `tp-cyber-42-4`를 찍었다. `cyber version`은 `Cyber 0.4.2 build-605-a2c586c`다.
    릴리스의 `docs.html` · `docs.md`는 이번에 싣지 않는다 — 문서 묶음(design 결정 19)의 몫이다.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 출처: python · ruby는 `prebuilt`, luau · cyber · node · bun · janet은 `upstream`, lua · php는 `debian`이다. 그래서 lang-script는 lang-native와 달리
   harvest를 거친다. 매니페스트의 `debian` 두 줄은 `lua5.4 5.4.7-1+b2`와 `php8.4-cli 8.4.27-1~deb13u1`이다. 실행 파일 이름 `lua`와
   `php`는 alternatives가 만든다. harvest가 그것을 직접 링크로 편다(TP-M0 결정, design 결정 2). php의 확장은 `php8.4-cli`가 끌고 오는
   `php8.4-common`(ctype · json · tokenizer 등)까지만 넣고 더하지 않는다(사용자가 잘 쓰지 않는다). php의 `/etc/php/8.4/cli/`는 묶음의
   `etc/`로 들어가고, init이 `/etc`로 복사한다(design 결정 10).
B. python은 `install_only_stripped`를 쓴다. 디버그 심볼은 묶음에 디버거가 없어 쓸 데가 없다(LLVM · lldb는 TP-M2에서 뺐다). tkinter ·
   idle(tcl/tk)은 지우지 않는다. GUI는 비목표 5지만, 지우려면 훅이 필요하고 크기를 본 뒤에도 늦지 않다. 크기가 크면 할 일 3의 숫자로
   다시 본다.
C. 풀기를 한 길로 합친다. 지금의 "tar 목록 → 맨 위 하나 판정 → `tar --strip-components=1`"을 다음 순서로 바꾼다.
   1. `${work}/unpack`에 통째로 푼다. 파일이 zip(URL이 `.zip`으로 끝난다)이면 `unzip -q`, 아니면 `tar -xf --no-same-owner`다. tar가
      `./`를 벗겨 주므로 janet은 여기서 보통 모양이 된다.
   2. 선택 키 `strip=N`(기본 1, 0 이상)만큼 벗긴다. 매 단에서 항목이 디렉터리 하나뿐이어야 하고, 아니면 `<tool>: strip=N but level K
      has M entries`로 멈춘다(지금의 "more than one top directory"를 일반화했다).
   3. 남은 내용을 `${root}/${dest}`로 옮긴다(`cp -a` 뒤 지운다 — 같은 파일 시스템이 아닐 수 있다).
   rv-ruby가 `strip=2`, luau · cyber가 `strip=0`이다(맨 위에 파일이 바로 있다). 키는 넷(`exe` · `hook` · `into` · `strip`)이 된다. TP-M2 결정 C의 "다섯을 넘으면 TSV를 옮긴다"에는 아직 안
   닿는다. `manifest.sh`는 `strip`의 값이 숫자가 아니면 `unknown option`으로 멈춘다. 훅(`rust-installer`)은 그대로 tarball을 받는다
   — 훅이 있는 줄은 1~3을 건너뛴다.
D. luau는 `exe=luau,luau-analyze,luau-compile,luau-ast`이다(`bin/`이 없다). cyber는 `exe=cyber`이고 `src/`는 옆에 그대로 둔다(확인 10). bun은 `exe=bun`이다. `bunx`는 싣지 않는다. bun은 `argv[0]`이 `bunx`면 `bun x`로 동작하지만, 그 링크를 만들려면 키가 하나 더
   필요하다. `bun x`가 같은 일을 한다.
E. 읽기 전용 `/usr`와 패키지 관리자. `pip install` · `gem install` · `npm -g`는 각 도구 디렉터리에 쓰려다 `Read-only file system`으로
   실패한다. 이것은 design 비목표 3이고, 홈의 venv · `--user` · `npm prefix`가 길이다. 체인은 그 길 하나가 망 없이 서는지만 본다
   — `python3 -m venv`(ensurepip가 묶음 안의 pip wheel로 깐다). `EXTERNALLY-MANAGED` 표시(PEP 668)는 넣지 않는다. 묶음에 업스트림에
   없는 파일을 만들어 넣는 첫 사례가 되기 때문이다 — 사용자가 원하면 그때 훅으로 한다.
F. 체인은 `devtools`를 넓힌다. 포트는 45504 그대로다.
   - ISO: `ISO_LAYERS="base lang-jvm lang-native lang-script"`. 이름 순이라 lowerdir 끝에 lang-script가 붙는다. 부팅 1: 복사 줄 넷과
     `copied 4 layers`. 부팅 2: `overlay /usr from 4 layers`. 부팅 3: lang-jvm이 깨지고 `from 3 layers`. 부팅 4: `4 old layers removed`.
   - 부팅 2에 사용자로, 망 없이, 하나씩 시간을 잰다(지금처럼 `printf` 한 겹으로 소스를 만든다).
     1. `python3 h.py` — `sys.version` · `ssl.OPENSSL_VERSION` · `sqlite3` 메모리 DB 한 줄. 이어서 `python3 -m venv ~/tp/v && ~/tp/v/bin/python -c …`
     2. `ruby h.rb` — `RUBY_VERSION`, `require "openssl"` · `require "json"`
     3. `lua h.lua` — `_VERSION`
     4. `luau h.luau` — 타입 주석이 있는 함수로 `tp-luau-42`, 이어서 `luau-analyze h.luau`가 0으로 끝난다
     5. `cyber h.cy` — `use math` · 함수 · 보간으로 `tp-cyber-42-4`
     6. `node h.js` — `process.version` · `crypto.createHash("sha256")`. `npm --version`
     7. `bun h.ts` — TypeScript 한 줄(타입 주석이 있는 함수)과 `Bun.version`
     8. `janet h.janet` — `janet/version`
     9. `php h.php` — `PHP_VERSION` · `json_encode`
   - 시간 상한: 처음에는 하나에 300초, 첫 측정 뒤 잰 값의 세 배이되 60초 아래로는 내리지 않는다(TP-M2의 규칙).
   - 체인을 가를지: 체인 시간(게이트 안, 빌드 뒤)이 420초를 넘으면 lang-script hello를 새 체인(monitor 45505)으로 뗀다. TP-M2가 257초였다.
     안 넘으면 하나로 둔다. 가르면 부팅 1~4(설치 · 깨짐 · 지우기)를 두 번 도는 비용이 든다. 그 비용이 hello를 더한 비용보다 크다.
G. design을 고칠 자리: 도구 목록 표의 스크립트 언어 줄에 luau · cyber(사용자 2026-11-06), 확인 8의 ruby(ruby-builder → rv-ruby, 이유는 확인 2)와 php(static-php → `debian` 8.4, 사용자), "열린 질문"의 닫은
   것("ruby · php는 `prebuilt`")에 이 plan으로의 한 줄, 결정 1에 `strip=` 한 줄, 확인 10에 lang-script의 크기. Status는 "TP-M3 끝"이다.

## 할 일

1. 매니페스트(결정 A · B · D): lang-script 아홉 줄. `Makefile`의 `DEV_LAYERS ?= base lang-jvm lang-native lang-script`, `help` 줄.
2. `devlayer/manifest.sh`에 `strip`(숫자) 키. `build.sh`의 풀기를 결정 C로 바꾼다. 바꾼 뒤 lang-jvm · lang-native가 같은 `.paths`를 내는지
   `cmp`로 본다 — 리팩터링이 기존 묶음을 바꾸지 않아야 한다.
3. `make dev-layers` — lang-script 받기 · 거두기(lua · php) · 굽기. 도구별 풀린 크기, 묶음 크기(zstd15), 받기 · 굽기 시간, 두 번째
   실행(캐시)의 시간. 캐시 실행이 60초를 넘으면 TP-M2 결정 F의 빠른 길을 다시 본다.
4. 손으로 한 번, 버리는 amd64 컨테이너에서 풀린 initrd 위에 네 묶음을 덮고 `chroot`해 결정 F의 hello 아홉을 돌린다(TP-M2 할 일 4의 모양).
   node의 `libatomic`이 여기서 처음 initrd 쪽으로 풀린다.
5. 빨강 둘, 되돌리면 초록:
   (a) rv-ruby 줄의 `strip=2`를 지운다. 1단만 벗기면 `4.0.9/` 디렉터리 하나가 남고 `bin/`이 없다. 그러면 링크할 것이 없다는 실패가
       도구 이름을 대고 나와야 한다. 지금 코드는 링크 0개로 말없이 초록일 것이다. 그래서 `exe=`도 없고 `bin/`에 실행 파일도 없으면
       (into 줄이 아니면) 멈추게 고친다.
   (b) `strip=x` → `unknown option strip=x`.
6. 체인 `devtools`(결정 F)를 혼자 한 번 돌리고, 숫자를 본 뒤 상한을 고친다. 빨강 하나: bun 줄을 일반(non-baseline) zip으로 바꾸면 부팅 2가
   bun hello에서 멈추는지(TCG qemu64에 AVX2가 없다 — 확인 3을 체인으로 본다). 받기가 하나 더 들지만 결정의 근거라서 한 번 본다.
7. `make quick`. init · 설치기 코드는 안 바꿀 것으로 본다 — 바뀌면 컨테이너의 `zig build test`도.
8. 루트 게이트(31체인). 어림: 24분 3초에 lang-script 복사(+0.2~0.3GB)와 hello 아홉의 TCG 시간을 더해 25~28분. `time make gate`의 출력은
   scratchpad에 둔다.
9. design 고치기(결정 G), HANDOFF.

## 판정

- `make dev-layers`가 네 묶음을 굽고, 검사(겹침 · NEEDED · 묶음 사이)가 초록이다. 할 일 2의 `cmp`가 같고, 할 일 5 · 6의 빨강을 봤다.
- 체인 `devtools`의 부팅 2에서 hello 아홉(python + venv · ruby · lua · luau + analyze · cyber · node + npm · bun · janet · php)이 망 없이 사용자로 돈다.
- 루트 게이트 31/31(체인을 가르면 32/32), 잘린 줄 0.
- 숫자: lang-script의 풀린 크기와 sqfs 크기(도구별 포함), `tars-dev.iso` 크기, 설치기 복사 시간, hello마다 TCG 시간, `build.sh`의 캐시 실행 시간.

## 위험

1. Debian의 `=` 고정. `php8.4-cli 8.4.27-1~deb13u1`은 trixie-security에 있는 판이다. 다음 보안 판이 나오면 색인에서 빠진다. 그러면
   캐시(`devlayer/build/lang-script.harvest.tar`)가 없는 기기의 `make dev-layers`가 apt에서 실패한다. base의 `libc6-dev …+deb13u4`가 이미
   같은 사정이고, 고치는 일은 버전을 낼 때의 갱신 단계(design 결정 3)다. 실패하면 판 이름이 apt 오류에 나온다.
2. TCG에서 JIT 런타임의 시작. node(V8) · bun(JavaScriptCore)은 시작 때 코드를 많이 만든다. qemu64 · 1GiB에서 수 초 넘게 걸릴 수 있다.
   상한(결정 F)과 체인 가르기의 420초가 이 숫자에 달려 있다.
3. python의 `venv`는 `ensurepip`로 pip를 홈에 복사한다(수십 MB의 쓰기, TCG에서 수십 초일 수 있다). 상한 안에 안 들면 `--without-pip`로
   줄이고 그 사실을 적는다.
4. harvest의 기준은 trixie-slim이다(TP-M0 결정). php8.4 · lua5.4가 끄는 라이브러리 가운데 slim에는 있고 initrd에는 없는 것은
   묶음에서 빠진다. 그것은 NEEDED 검사가 이름을 대고 잡는다(TP-M0 결정 H). 그때 `debian` 줄을 더한다. 어떤 라이브러리인지는 할 일 3이 본다.

## 확인한 것

1. build.sh의 `case`는 `upstream`만 받고 있었다 — `prebuilt`(python · ruby)는 `kind prebuilt is not built yet`으로 멈췄을 것이다. 둘은
   받는 자리만 다르고 풀기 · 놓기가 같아(design 결정 2) `upstream | prebuilt`로 묶었다. 출처 기록(`<묶음>.pkgs`)의 종류 열도 줄의 값을 쓴다.
2. 첫 `make dev-layers`가 lang-script에서 셋으로 멈췄다.
   - tzdata: `/usr/share/zoneinfo/*` 19개가 initrd와 다르다(결정 4). php8.4-common이 tzdata에 기대고, harvest의 "의존 폐포" 단계(TP-M0)가
     trixie-slim에 원래 깔린 tzdata의 파일을 실었다. 거두는 이미지는 `2026e-0+deb13u1`(이미지 2026-10-27), initrd를 지은 개발 컨테이너는
     `2026f-0+deb13u1`이다. 두 apt 스냅숏은 따로 움직이므로 판을 맞추지 않고 `devlayer/harvest-skip.tsv`(패키지 · 이유)로 initrd가 가진
     패키지의 파일을 뺀다. 패키지는 깔린 채로 둔다. harvest의 신선도 열쇠에 이 파일도 들어간다 — 끝 줄은 해시 하나여야 한다(build.sh가
     `head -n -1`로 뗀다. 두 줄로 했다가 `harvest.tar is stale`로 멈췄다).
   - systemd: `etc/systemd/system/timers.target.wants/phpsessionclean.timer`가 대상 없는 링크였다. harvest가 `/etc/systemd/` · `/etc/cron.d/`를
     싣지 않는다(TARS에는 둘 다 없다).
   - `realpath: ''`: cyber의 RUNPATH가 `:$ORIGIN:/usr/lib/x86_64-linux-gnu`로 빈 항목에서 시작한다. ld.so는 빈 항목을 현재 디렉터리로
     읽는다 — 묶음 안의 자리가 아니라서 verify가 건너뛴다. (cyber 쪽의 작은 숙제: 빈 항목은 실행하는 곳의 `.so`를 먼저 찾는다.)
3. 둘째 판이 python의 `lib/libpython3.so`에서 멈췄다. 안정 ABI 껍데기라서 NEEDED가 이름이 아니라 `$ORIGIN/../lib/libpython3.15.so.1.0`이다.
   glibc ld.so는 `/`가 든 NEEDED를 검색하지 않고 그 경로를 열며 `$ORIGIN`을 펼친다. verify.sh에 같은 규칙을 넣었다.
4. 리팩터링(결정 C)이 기존 묶음을 바꾸지 않았다: base · lang-jvm · lang-native의 `.paths`가 고치기 전과 `usr/share/tars/layers/<묶음>`
   한 줄(안에 든 `git describe --dirty`)만 다르다. lang-script는 base와 274 경로를 같은 내용으로 나눈다(`gconv` 256과 libc6 · zlib 등).
5. 빨강: (a) rv-ruby의 `strip=2`를 지우면 `ruby: nothing to link — no exe= and no executables in /usr/local/lib/ruby-4.0.9/bin (wrong
   strip=?)`. (b) `strip=x` → `red-b.tsv:40: unknown option strip=x`.
6. chroot(할 일 4, Rosetta 위 amd64, root, initrd + base + lang-script): python 0.9초, `venv` 13.0초, ruby 0.8초, lua 0.06초, luau 0.09초 ·
   analyze 0.2초, cyber 0.2초, node 0.6초, npm 1.5초, bun 0.3초, janet 0.07초, php 0.2초. ruby와 node가 같은 sha256 앞자리 `3abd8072`를 냈다.
   cyber는 큰따옴표 문자열에서도 `%{…}`를 펼친다 — 체인의 printf 한 겹에서 작은따옴표를 피할 수 있다.
7. 체인 첫 판(qemu64)이 ruby에서 빨갰다: `ruby: [BUG] Illegal instruction`, Ruby 프레임이 서기 전(`DUMMY [FINISH]`). PIE는 페이지 단위로
   적재되므로 RIP의 끝 세 자리 `5eb`로 후보를 추렸다 — 기본 x86-64 밖의 명령은 `require_internal`의 `palignr`(SSSE3) 하나다. rv-ruby는
   SSSE3 이상을 가정하고 지었고, qemu64는 x86-64 첫 세대라 SSSE3가 없다. 맥북 에어 2011(Sandy Bridge)에는 있다. 사용자 결정(2026-11-06):
   devtools 체인만 `-cpu SandyBridge`로 돈다(`TP_CPU`의 기본값). 다른 체인은 qemu64 그대로다. CPU를 바꿔도 앞 hello의 시간은 TP-M2와
   거의 같다(zig 53.6초 · go 94.6초).
8. 할 일 6의 빨강은 체인으로 보일 수 없었다. 매니페스트의 bun을 일반 빌드(`bun-linux-x64.zip`, `%ymm` 20,871 · `vpbroadcast` 1,769 ·
   `shlx/shrx/sarx` 1,269개)로 바꿔도 SandyBridge 체인이 초록이었다(bun 631ms). QEMU 10.0 TCG는 CPUID에 AVX2를 알리지 않으면서 AVX2
   명령을 실행하는 것으로 보인다(추정 — SSSE3 `palignr`는 qemu64에서 막았다). baseline의 근거는 실기 쪽에 남는다: Sandy Bridge에는
   AVX2가 없고 bun은 일반 빌드가 AVX2를 요구한다고 밝힌다(확인 3). 맥북 에어 실기에서 `bun --version`이 서는지가 남은 확인이다.
9. 체인 `devtools`(SandyBridge · 1GiB, 혼자 한 번)가 초록, 빌드 뒤 304초(TP-M2 257초) — 결정 F의 420초 아래라 하나로 둔다. 상한은 잰 값의
   세 배로 고쳤다: venv 90초, 나머지 여덟은 60초.

## 결과

1. `make dev-layers`가 네 묶음을 굽고 초록이다. 앞의 셋은 숫자가 TP-M2와 같고 `.paths`도 같다(확인한 것 4).

   | 묶음 | 줄 | 파일 | 풀린 크기 | zstd15 | 뺀 경로 | ELF | 묶음 사이 |
   |---|---|---|---|---|---|---|---|
   | lang-script | prebuilt 둘 · upstream 다섯 · debian 둘(패키지 22) | 12,602 | 651MiB | 190MiB(199,331,840바이트) | 39 | 506 | shared 274(base) |

   도구별 풀린 크기: node 225 · ruby 165 · python 116(stripped) · bun 103 · luau 22 · janet 11 · cyber 4MiB, Debian 몫(lua · php와 라이브러리)
   `/usr/lib` 32MiB. harvest: `packages=22 … flattened=5 skipped=1(tzdata) etc=45`. 받기 · 거두기 · 굽기 첫 실행은 약 4분 39초(python 받기 포함).
2. 빨강: 할 일 5의 둘(확인한 것 5). 할 일 6은 체인으로 보일 수 없었다(확인한 것 8).
3. 체인 `devtools`가 초록이다(`-cpu SandyBridge`, 확인한 것 7). 게이트 안에서 빌드 뒤 305초. 숫자(TCG SandyBridge · 1GiB, 게이트 안):

   | 항목 | 값 |
   |---|---|
   | 묶음 넷 | 840,060,928바이트(802MiB) |
   | `tars-dev.iso` | 983,654,400바이트(TP-M2 784,324,608) |
   | 설치기의 복사 | 4,218ms |
   | init의 얹기(묶음 넷) | 41ms |
   | python · venv · ruby · lua · luau | 1,446 · 27,329 · 1,429 · 35 · 401ms |
   | cyber · node · npm · bun · janet · php | 503 · 1,449 · 1,950 · 628 · 69 · 272ms |
   | JVM 뒤 MemAvailable | 602,940kB |

4. 루트 게이트 한 판: 31/31, 25분 23초, 31회차 모두 `cut log lines A=0 B=0 C=0`. devtools(TP-M1 줄)가 378초로 가장 길다.
5. 위험 1(Debian `=` 고정)은 그대로 남는다. 위험 2(JIT 시작)는 node 1.4초 · bun 0.6초로 작다. 위험 3(venv)은 27초로 상한 90초 안이다.
   위험 4(slim에만 있는 라이브러리)는 NEEDED가 아니라 결정 4(tzdata)로 나타났다 — `harvest-skip.tsv`.
