# HANDOFF: TP-M10(서버 실행 파일)과 덧붙임(gpg 키 검사 · mkcert) 끝 · 커밋함(push 안 함) — 다음은 서버(서비스) milestone(TP-M11)

## 목표

사용자 요청(2026-11-05): "타스 리눅스를 설치하고 기본적으로 바로 뭔가를 컴파일하거나 자바 서버를 구동하고 싶다. 부팅 디스크(initrd)에
담는 것은 원하지 않는다. 네트워크가 없는 곳에서도 코딩 · 개발을 할 수 있는 환경을 만들자." 언어 21 · 편집기 · 문서(dasht) · 터미널
유틸리티 · 서버 · AI 도구 목록을 사용자가 줬다. design은 `docs/specs/2026-11-05-tars-dev-layer-design.md`(초안 11판, 열린 질문 없음).

## 현재 브랜치

`main`(push함). 0.1.4 이후 커밋이 쌓였고 버전은 안 냈다. 사용자(2026-11-06): "이 작업을 마무리하면 0.2 버전을 정식으로 릴리즈" — 개발 도구 층(TP)을
마치면 다음 번호는 0.1.5가 아니라 0.2.0이다(`docs/decisions/project_release.md`의 절차). 실기 확인용 프리릴리스 `dev-20261106`(아래).
Dockerfile이 바뀌어 이미지 태그가 바뀌었다 — push 뒤 CI가 ghcr.io에 새로 굽는다. 그 전 다른 기기의 `make container`는 로컬 빌드(약 1분).

## 다음 할 것

1. 사용자에게 보고: TP-M10은 사용자가 "남은 결정을 위임"하고 잔 사이에 끝났다(2026-11-08). Claude가 맡아 정한 것은 plan
   `docs/plans/2026-11-08-tars-dev-layer-tp-m10.md`의 "확인한 것" 1~8 — 특히 2(지문 대신 키 sha256), 3(`mysql-community-client`, 설정은 `conf.d/tars.cnf`),
   4(server 166MiB — ISO가 2GiB까지 약 110MB). 덧붙임(gpg · mkcert)은 사용자와 함께 정했다. 커밋은 했고 push는 안 했다(사용자 확인 뒤).
   Dockerfile이 바뀌었다(gpg, 이미지 태그 `76bca5f6adc3`) — push 뒤 CI가 굽는다. 그 전 다른 기기는 `./devcontainer/image.sh build`
   (`make container`는 로컬 이름 `tars-devcontainer`가 있으면 다시 굽지 않는다 — 이 세션에서 겪었다).
2. TP-M11 = 서버(서비스) milestone plan — `docs/decisions/project_server_persistence.md`: (a) `/var/lib/<서버>` → `/home/.tars/var/<서버>` 링크를 init이,
   (b) `/config/<서버>.d` include(mysql은 이미 `/etc/mysql/conf.d/`가 있다), (c) 로그 stdout, `tars-service` 연결 · 첫 시작 초기화 · 서비스 계정.
   그 plan에서 물을 것: 링크 장치를 서버 전용으로 할지 범용으로 할지(Claude는 범용을 권할 생각). 같은 milestone에 기계별 자체 서명 인증서와
   시스템 신뢰(`/usr/local/share/ca-certificates` → 부팅 때 CA 묶음) — 사용자 "둘 다"(기억 파일 끝).
3. 2GiB 한도: AI milestone이 남은 약 113MB에 들어가는지 먼저 재기. 줄일 후보는 server의 perl(base와 겹침, 압축 약 15MB)과 libicu 데이터(31MiB).

## 완료된 작업 (2026-11-08, TP-M10 — 사용자가 조사 결과로 셋을 정하고, 구현 중 남은 결정을 위임하고 잤다)

- [x] 사용자 결정: mysql은 Oracle의 trixie apt(generic tarball은 `libaio.so.1`로 안 선다), nginx stable 1.30, redis.io 8.10. plan `c77eeb4`.
- [x] 종류 `vendor-repo`를 처음 세웠다: `devlayer/repos.tsv`(apt 한 줄 · 키 sha256 · 지문) · `devlayer/keys/*.asc`, URL 자리 `<저장소>/<패키지>`, harvest가 키 sha256을
  대조한 뒤 `signed-by=`. URI는 http(slim에 ca-certificates가 없다 — 서명이 지킨다).
- [x] 열째 묶음 `server`(166MiB, 패키지 67): postgresql-18 18.6(PGDG) · mysql-community-server-core/client-core/client 9.7.4 · nginx 1.30.6 · redis-server/tools 8.10.3 ·
  caddy 2.11.9(upstream). `devlayer/files/server/`: `/usr/local/bin` 링크 38(`mysqld` · `nginx` — `/usr/sbin`은 PATH 밖, postgres 36), `etc/mysql/conf.d/tars.cnf`,
  `PGHOST=/tmp` rc 조각 둘.
- [x] harvest가 새로 빼는 것: `/etc/postgresql/`(TARS에 없는 클러스터의 설정), ssl-cert가 거두기 컨테이너에서 만든 snakeoil 비밀 키 · 인증서 · 해시 링크와
  `usr/lib/ssl/private`, perl-doc 없는 거두기의 `perldoc` 자리표(base의 진짜와 부딪쳤다).
- [x] 체인 부팅 2에 서버 덩이(다섯을 사용자로 띄우고 응답 · 끄기 · man), 빨강 셋은 chroot · harvest에서. `tars-help devtools`에 "서버" 절(fish라 heredoc 없이,
  nginx는 상대 경로 + `-p`), `running-tars.md` 한 절, `tars-docs` 목록에 PostgreSQL · MySQL · Redis · Nginx. design 16판.
- [x] 루트 게이트 31/31, prebuild 354초 + lanes 1,455초, 잘린 줄 0. ISO 2,034,094,080바이트.
- [x] 덧붙임(사용자 "gpg … 검토하자" · "ssl-cert 같은 툴도" → "둘 다"): 개발 컨테이너에 gpg, `devlayer/keys.sh`(sha256 · 지문 · 만료 — `make quick` 단계 7과
  `make dev-layers` 앞), util에 mkcert 1.4.4(체인 덩이 — `openssl verify` OK). 게이트 31/31, lanes 1,494초. plan 끝의 "덧붙임" 절.

## 완료된 작업 (2026-11-07, FS-M0 닫기 — 다음 세션)

- [x] 루트 게이트 2회차 31/31, prebuild 356초 + lanes 1,454초, 잘린 줄 0, 로그 `out/gate-logs/20261107-135753`. PD-M4도 초록(1회차의 말없는 끝은 간헐, carryover 그대로).
  `tools`(UT-M3)의 `tars-help` 셋과 `install`(DC-M2)의 새 줄이 게이트 안에서 돌았다.
- [x] FS design `Status:` 끝남, plan "결과" 절, `completed.md` 한 행, 기억 `project_first_steps_guide` 끝 표시.
- [x] TP design 열린 질문 1 → "닫은 것"(15판): 사용자 "핵심은 이게 영속성을 가지느냐" — 서버(서비스) milestone이 맡고 (a) 링크 (b) `/config/<서버>.d` include
  (c) 로그 stdout을 채택. 새 기억 `docs/decisions/project_server_persistence.md`(그 plan에서 링크 장치를 범용으로 할지 물을 것).

## 완료된 작업 (2026-11-07, FS-M0 구현 — 사용자 "commit as you wish"로 게이트 2회차 결과 전에 커밋했다)

FS = First Steps. 사용자: "설치를 잘 마치고 나니까 뭘 해야 될지 모르겠어서 당황해." design `docs/specs/2026-11-07-tars-first-steps-design.md`(2판,
커밋 `b276ba9`), plan `docs/plans/2026-11-07-tars-first-steps-fs-m0.md`(커밋 `9f5bf22`, 확인한 것 1~5는 working tree). 사용자 결정: 찾는 길은
`tars-help` 명령 하나(motd · home 파일 없음), 한국어 존댓말(합니다체 — 구현 중 사용자 지시), 범위 넷, 일곱 장 · `glow -p` · 한국 기준 예시.

- [x] `kernel/help/tars-help`(bash, initrd `/usr/bin`) · 본문 `docs/help/{index,network,bluetooth,config,services,devtools,desk}.md`(initrd `/usr/share/doc/tars/`) ·
  `kernel/make_initrd.sh` 복사 · `init/src/install.zig` 새 설치 `done` 다음 줄 `tars-install: after the reboot, type tars-help for the first steps.`
- [x] `docs/help/check.sh`(quick_check 단계 6): 코드 블록의 `tars-config X` · `tars-service X`를 소스 `USAGE`와, `tars-help Y`를 장 파일과 대조. 빨강 봤다.
- [x] 체인: `tools` 검사 23(`tars-help --list` · `network | grep` · `nope` rc 1), `install`이 새 줄. 둘 다 혼자 PASS. `make quick` PASS.
- [x] 장을 쓰며 `running-tars.md`가 낡은 자리를 찾았다(plan 확인한 것 1 — `sudo` 빠짐, `lt` 별칭, 키 수, …). 장은 소스를 따랐다. `running-tars.md` 본문은 안 고쳤다(맨 위에 "기계 안은 tars-help" 세 줄만).
- [x] 사용자가 `/humanize-korean`을 돌렸다(light, 쉼표 8곳) → 이어서 존댓말로 다시 썼다. CLAUDE.md "끝내면 함께 고칠 것"에 `docs/help/` 한 줄.
- [x] 루트 게이트: 1회차 30/31 — `pointer`(PD-M4) 부팅 B 두 손가락 스크롤에서 말없는 끝(carryover 넷째로 적었다, 혼자는 초록). 2회차를 이 세션 끝에
  백그라운드로 돌렸으나 결과를 못 봤다(scratchpad 로그는 세션과 함께 사라진다) — 다음 세션은 `make gate`를 다시 돌린다(약 32분).
- [x] 커밋: FS-M0 구현 한 덩이, TP design 열린 질문 1 · carryover · HANDOFF는 따로.
- [x] 게이트가 초록이면 닫기(위 절, 소개 페이지는 남음): FS design `Status:`, `completed.md` 한 행, 소개 페이지(`gh-pages` `data.js` — `site/README.md`의 순서, 공개라 승인에 함께), 기억 파일 갱신, HANDOFF.
- FS와 별개로 커밋한 것: TP design의 "열린 질문 1"(서버의 데이터 · 설정 · 로그가 재부팅을 넘는 길 — `/etc` · `/var`는 RAM, 권한 방향 (a) 링크 (b) `/config/<서버>.d` include (c) 로그는 stdout),
  사용자 "That's a good idea"로 적어 둔 것. TP-M10 plan 전에 사용자와 닫는다.

## 완료된 작업 (2026-11-07, TP-M9 — 조사를 보고하고 사용자가 정했다, 구현 중 `tars-docs`를 사용자가 더했다)

- [x] 사용자 결정: docset은 Bash 하나만 싣는다(추천 목록은 tgz 약 1,000MiB — ISO의 2GiB 자리에 안 들어간다), 나머지는 망으로. 2GiB 한도 결정은 계속 미룸.
- [x] plan `962d78a`. 새 묶음 `docs`: dasht 2.4.0(GitHub 태그 아카이브, `hook=dasht`, dasht-server는 링크 안 함) · Bash docset(`into=dasht strip=0`) · w3m(debian).
  `DASHT_DOCSETS_DIR`은 기본값(홈) — 디렉터리 하나라 `/usr`로 잡으면 받기가 실패한다. rc 조각 둘(`devlayer/files/docs/etc/…`)이 홈에 Bash 링크를 둔다.
- [x] `tars-docs`(사용자 요청 — "설치한 언어 · 서버 · 도구의 문서를 한 방에"): `devlayer/files/docs/usr/local/bin/tars-docs`. 목록 열일곱, `get [-y] [이름…]`,
  판 고정 URL(Java SE25), tgz를 지운다. 서버 docset은 TP-M10이 목록에 더한다.
- [x] chroot가 잡은 결함: util의 sqlite 3.54는 `-line`이 `name: x`라 dasht-query-line의 파싱이 빈다 → 훅 `devlayer/hooks/dasht.sh`가 `-separator ' = '` 한 줄.
- [x] 체인 부팅 2에 M9 덩이(링크 · 찾기 · w3m -dump · man dasht · fish 조각 · tars-docs 목록과 망 없는 실패). 빨강 둘은 chroot로(plan 확인한 것 5).
- [x] design 14판(결정 19), `running-tars.md`의 "문서 — dasht와 tars-docs" 절. 루트 게이트 31/31, 31분 58초(lanes 1,426초), 잘린 줄 0. ISO 1.86GB, 묶음 아홉 1,637MiB.
- [x] 사용자 요청을 기억으로(`project_first_steps_guide`): 설치 뒤 "뭘 하지"에 답하는 첫걸음 안내 — 새 milestone(사용자 "새로운 마일스톤으로 하자").

## 완료된 작업 (2026-11-07, TP-M8 — 조사 · 구현을 단계마다 보고하며 사용자가 정했다)

- [x] 사용자 결정: 뺀다 — cloudflared · pandoc · pillow · tree · gron · jless · lisette · gdu · hunk(bun 런타임을 품어 util의 25%). vifm은 Debian(AppImage 장치 없음).
  ffmpeg를 더하고 ImageMagick · GraphicsMagick과 새 묶음 `media`로(GM 대 IM을 재 보고 — 둘 다). DuckDB를 더하되 1.5.6(2.0의 CLI는 x86-64-v3, 에어 2011에서 안 선다).
  alias `lt='eza -ls modified'` · `ltt='eza -ls changed'`(`24b8fc4` · 짝인 허용 목록 `8887989`).
- [x] plan `a40c0f7`. util에 upstream 42줄(sqlite는 SHA3 대조 뒤 sha256) + debian wget · libxml2(hurl의 NEEDED — libcurl.so.4는 initrd에), base에 ipcalc · vifm
  (perl에 기댄다 — rlwrap과 같은 이유), media에 ffmpeg 9.0(BtbN 공유 빌드, 월말 태그 고정) · imagemagick · graphicsmagick. `man1=`이 `.1.gz`도 받는다.
- [x] `make dev-layers`가 다섯 판 멈추며 고친 것(plan 확인한 것 2): `needed-ignore.tsv`의 넷째 이유 `exe-loaded`(ffmpeg의 libav*), `harvest-skip.tsv`에 vim 셋,
  harvest.sh의 skip 판정을 `${db:Status-Status}`로(잠재 결함), 편 alternatives의 대상이 skip 패키지면 그 링크도 빼기(`skipalt=`).
- [x] 체인 부팅 2에 60개 `--version` · 일하는 도구 여덟 · ffmpeg → ffprobe · magick · gm · man(`.1` · `.1.gz`), 부팅 3에 rg. 빨강 둘(plan 확인한 것 5).
- [x] 루트 게이트 31/31, 33분 13초(lanes 1,490초), 잘린 줄 0. ISO 1.85GB(2GiB까지 약 293MB), 묶음 여덟 1,632MiB.

## 완료된 작업 (2026-11-07, TP-M7 — 사용자가 조사 중 결정 둘을 정하고 남은 결정을 위임한 뒤 잤다)

- [x] 사용자 결정: "편집기 · 터미널 유틸리티 · 문서"를 셋으로(M7 편집기 → M8 util → M9 문서, 서버 · AI는 M10부터). emacs 자리는 `emacs-nox`,
  Doom Emacs는 사용자가 망이 있을 때 직접 깐다(mg를 물었고, Doom을 검토했다 — 시드는 안 섰다, 아래 "실패한 접근").
- [x] plan `d29f0ad`. 일곱째 묶음 editor(140MiB, 풀면 620MiB): mitos 0.1.3(`exe=ms`, 옆의 `runtime/` 문법 301개) · neovim 0.12.6(`man1=`) ·
  ttt 1.11.0(압축 없는 실행 파일 하나 — build.sh의 새 길, URL이 압축 확장자가 아니면 `bin/<도구>`에 0755, 선택 키는 안 늘렸다) · emacs-nox 30.1(Debian, 패키지 47).
- [x] harvest.sh: emacs-nox의 alternatives가 `/usr/bin/editor`(initrd의 vim)와 `ctags`(base의 universal-ctags)를 덮어 — 그 넷(man 포함)을 싣지 않는다.
  `common-licenses`로의 링크는 본문도 싣는다(emacs의 `etc/COPYING`). base · lang-script를 다시 거뒀고 숫자는 그대로.
- [x] 체인 부팅 2에 ms(health) · nvim(treesitter · 고쳐 쓰기) · emacs(batch, native-comp · treesit · 저장) · ttt(`--exec`) · man, 부팅 3에 nvim. 빨강 둘(plan 확인 4 · 5).
- [x] 루트 게이트 31/31, 30분 11초(lanes 1,356초), 잘린 줄 0. ISO 1.51GB. `EDITOR`는 vim 그대로(맡아 정한 것 — plan).

## 완료된 작업 (2026-11-06, TP-M6 — 같은 세션, 사용자가 "단계별로 진행하면서 점검"을 요청)

- [x] 조사 네 단계(erlang · elixir · gleam · erlang man)를 하나씩 보고하고 plan `d6735bd`. 구현은 다섯 단계(빌드 장치 · 재료 · chroot · 체인 · 게이트)로 나눠 보고.
- [x] 여섯째 묶음 lang-beam(84MiB): erlang OTP-29.1.2(builds.hex.pm ubuntu-24.04, 훅 `otp-install.sh`가 `Install -cross -minimal`) + man(GitHub
  `otp_doc_man`, `erl -man`), elixir 1.20.5(`elixir-otp-29.zip`, 훅 없음), gleam 1.19.2(musl, 훅 `gleam.sh` — `bin/gleam`은 런처).
- [x] gleam 오프라인(사용자 결정): 새 종류 `hex`(`devlayer/hex/gleam-seed.lock` → `seed/packages/<SHA>.tar`)와 시드 `manifest.toml`. 런처가 캐시를 채우고
  `gleam new` 뒤 `manifest.toml`을 넣는다. build.sh가 시드 manifest의 `outer_checksum`과 잠금 파일을 대조한다. 새 선택 키 `man1=`(키 다섯 — 한도).
- [x] 위험 1(BEAM JIT): OrbStack(qemu-user)에서 새 프로젝트의 첫 `mix test`가 Illegal instruction으로 죽었지만 체인(SandyBridge)에서는 세 판 모두 통과 —
  에뮬레이터의 CPUID 탓으로 본다(plan 확인한 것 4 · 6). 실기 확인으로 남긴다.
- [x] 루트 게이트 두 판: 1회차 30/31(BT-M2의 `btvirt` crash 간헐, 세 번째 — `carryover.md`), 2회차 33분 38초 31/31, 잘린 줄 0. ISO 1.36GB.

## 완료된 작업 (2026-11-06, TP-M5 세션)

- [x] TP-M5 plan `9a04566`(조사 뒤 사용자 결정 둘: scala3를 뺀다, cci · glc로 util 묶음을 연다). 구현은 이 HANDOFF와 같은 커밋.
- [x] lang-jvm에 kotlin 2.4.21(jar뿐, 그대로 오프라인) · clojure 1.12.6.1673(훅 `clojure-tools.sh`가 자리표를 바꾸고 `bin/clojure`에 첫 실행 시드 줄).
  새 출처 종류 `maven`(잠금 파일 `devlayer/maven/clojure-m2.lock`의 jar · pom 일곱 → 도구의 `seed/m2/`, 첫 실행이 `~/.m2`로 복사). lang-jvm 127 → 226MiB.
- [x] base에 rlwrap(`clj`가 요구한다 — lang-jvm에 두면 perl · python을 한 번 더 싣는다, plan 확인한 것 1). python3 실행 파일 패키지 넷은 `harvest-skip.tsv`.
- [x] util 묶음(다섯째, 13MiB): cci 0.6.1(Go 정적) · glc 0.19.3(Rust, libstdc++ · libz는 initrd). design의 "뺀 것"에서 되돌렸다.
- [x] 체인은 가르지 않았다 — 512초로 420초를 넘었지만 devtools는 ISO 줄(lane-0, 직렬)에 있어 새 체인도 같은 줄에 붙는다(plan 확인한 것 6).
- [x] 루트 게이트 31/31, 29분 26초(lanes 1,284초), 잘린 줄 0. ISO 1.27GB. `make quick`이 TP-M4의 `lang-native.sh` SC2148을 잡아 고쳤다.
- [x] cyber 0.4.2 → 0.4.3(사용자가 soomtong/cyber에 낸 판, 2026-11-06). 모양 · CPU 수준(`%ymm` 0) 같음, devtools 체인 초록(빌드 뒤 488초). 게이트는 안 돌렸다 — 묶음을 쓰는 체인은 devtools 하나다.

## 완료된 작업 (2026-11-06, TP-M4 — 앞 세션)

- [x] 프리릴리스 `dev-20261106`(`181271e`, 묶음 넷 — 실기 확인용, Latest는 0.1.4 그대로). 0.2.0은 TP 전체 뒤(`docs/decisions/project_release_0_2.md`).
- [x] TP-M4 plan `ea92b03` · `f35a176`, 구현 `657e0a3`. base에 Debian 서른 줄과 upstream 넷(cmake 4.4.5 · ninja 1.13.2 · shellcheck 0.11.0 ·
  ctags 2026.10.08): perl(+ doc) · 빌드 도구 · coreutils 전부(configure가 `expr` 없이 안 돌았다) · 압축 · ssh · rsync · gpg · man(3,669) ·
  gdb · strace · ltrace · valgrind. base 238MiB(풀면 738).
- [x] 쓰기 가능한 `/usr/local`(사용자 결정 — p3에, root만, 전역 설치 통일): init `layers.mountLocal`, npm builtin npmrc · gem
  `operating_system.rb` · python `sitecustomize.py`(Debian의 posix_local 꼴 — `--user` · venv는 그대로). `devlayer/files/<묶음>/`(새 자리),
  시스템 rc의 `/etc/tars/rc.d/*.sh`, fish `10-<묶음>.fish`.
- [x] TP-M1부터의 결함 하나: init의 `/etc` 복사가 링크를 건너뛰어 php 확장 열아홉이 안 켜졌다 — 고쳤다(체인이 `ctype_digit`을 본다).
- [x] 체인 380초 남짓, 루트 게이트 31/31 32분 47초, 잘린 줄 0. 확인한 것 열하나는 plan.

## 완료된 작업 (2026-11-06, TP-M3 세션)

- [x] TP-M3 plan `16a189d`, 구현 `5871158`. `lang-script`(190MiB, 풀면 651MiB): python 3.15.2(python-build-standalone, stripped) ·
  ruby 4.0.9(spinel-coop/rv-ruby — ruby/ruby-builder는 `/opt/hostedtoolcache`에 굳어 옮길 수 없다) · lua 5.4.7(Debian) · luau 0.745(사용자가
  더함, Roblox) · cyber 0.4.2(soomtong/cyber, 사용자가 더함) · node 26.13.0 LTS · bun 1.4.4(baseline — AVX2 없음) · janet 1.42.1 · php 8.4.27
  (Debian trixie-security — 사용자 결정, static-php는 8.5.8에서 멈췄다).
- [x] build.sh 풀기 일원화: 통째로 풀고(zip이면 unzip) `strip=N`(새 키, 기본 1)단 벗기고 옮긴다. `prebuilt`도 받는다. 링크 0개면 멈춘다.
  리팩터링이 기존 셋의 `.paths`를 바꾸지 않았다. harvest: `devlayer/harvest-skip.tsv`(initrd가 가진 패키지 — tzdata, 거두는 이미지 2026e와
  initrd 2026f가 어긋났다), `/etc/systemd/` · `/etc/cron.d/`는 싣지 않는다. verify: RUNPATH 빈 항목 건너뛰기, `/`가 든 NEEDED(`$ORIGIN/…`).
- [x] devtools 체인: 묶음 넷, hello 아홉(+ venv · npm · luau-analyze), 빌드 뒤 305초. 체인 CPU는 `-cpu SandyBridge`(사용자 결정) — qemu64에서
  rv-ruby가 SSSE3 `palignr`로 죽었다. QEMU TCG는 CPUID에 없는 AVX2도 실행해서 "일반 bun이면 빨강"은 체인으로 못 봤다(plan 확인한 것 8).
- [x] 루트 게이트 31/31, 25분 23초, 잘린 줄 0.

## 완료된 작업 (2026-11-06, TP-M2 세션 — 사용자가 남은 결정을 위임하고 잤다)

- [x] TP-M2 plan `c169817`, 구현 `e030523`, HP-M2 견고화 `86b34c5`. 사용자 결정: LLVM 툴체인 · odin · tcc를 뺀다("GCC가 포함되니까 C나 Assembly 계열은
  문제없고, 디버거가 필요하면 직접 LLVM 툴체인을 설치"). base에 g++(81MiB), `lang-native`에 zig 0.17.1 · rust 1.99.1(+ rust-src,
  설치기는 `devlayer/hooks/rust-installer.sh`) · go 1.27.3(402MiB, 풀면 2,018MiB). 매니페스트 파서 `devlayer/manifest.sh`(열이 맞지 않으면
  줄 번호로 멈춘다, 일곱째 열 `exe=` · `hook=` · `into=`), 묶음끼리 같은 경로의 다른 내용 검사(`devlayer/build/<묶음>.paths`).
- [x] devtools 체인이 묶음 셋, 부팅 2에 g++ · zig · rustc · cargo · go run · go build의 hello(망 없이, TCG zig 53초 · go 첫 빌드 94초).
- [x] 루트 게이트 세 판: HP-M2(끼어든 init 줄 — `home/check.sh`를 고쳤다, lessons 덧붙임), PD-M4(말없는 끝 — `carryover.md`), 셋째 31/31
  24분 3초, 잘린 줄 0. 숫자 · 확인한 것 일곱은 plan.

## 완료된 작업 (2026-11-05, TP-M1 세션)

- [x] TP-M1 plan `0b66cb8`, 구현 `36677c3`. 커널에 `BLK_DEV_LOOP` · `OVERLAY_FS` · `MISC_FILESYSTEMS` · `SQUASHFS` ·
  `SQUASHFS_ZSTD`(+80KiB). init `layers.zig`가 `/home`을 붙인 직후 `/home/.tars/layers/*.sqfs`를 loop · squashfs로 열어
  `lowerdir=/usr:<묶음들>`(initrd가 맨 위)로 `/usr`에 읽기 전용 overlay, 묶음의 `etc/`를 `/etc`로. 비교 대상은 설치기가 묶음 옆에
  쓰는 `version`(= 이미지 버전, 매 부팅). 설치기는 매체에 `boot/layers`가 있을 때만 p3를 연다(새 설치 · 갱신, 계획 줄 · 자리 판정).
  `make iso ISO_LAYERS="base lang-jvm"`이 묶음을 싣는다(기본은 안 싣는다). 새 체인 `devtools`(TP-M1, 45504, `-nic none`, 부팅 넷).
- [x] 숫자 · 빨강 셋 · 바꾼 것 넷(`LOOP_CLR_FD` 불필요, 갱신은 옛 묶음을 먼저 지움, 게스트에 `mount` · `free` 없음)은 plan의
  "확인한 것" · "결과". 루트 게이트 31/31, 20분 14초, 잘린 줄 0.

## 완료된 작업 (2026-11-05, TP-M0 세션)

- [x] TP-M0 plan `a98564f`, 구현. `make dev-layers`가 `devlayer/manifest.tsv`대로
  `base.sqfs`(gcc 14.2 · `libc6-dev` · make, 64MiB)와 `lang-jvm.sqfs`(Temurin 25.0.5+8, 126MiB)를 zstd15로 굽는다. 거두기는
  amd64 컨테이너(`devlayer/harvest.sh`), 받기 · 검사 · 굽기는 개발 컨테이너(`devlayer/build.sh` · `verify.sh`). 숫자 · 빨강 셋 ·
  chroot의 `cc` · `make` · `java Hello`는 plan의 "결과", 구현이 드러낸 사실 아홉은 "확인한 것"(merged-usr 아닌 initrd, slim 기준의 틈,
  APFS 대소문자, SIGPIPE).
- [x] Dockerfile 끝에 `squashfs-tools` 층(이미지 태그가 바뀐다 — push 뒤 CI가 다시 굽는다). 기억 `feedback_devcontainer_additions`
  (사용자: 개발 컨테이너에 필요한 것은 언제든 더한다).

## 완료된 작업 (2026-11-05, 앞 세션)

- [x] 검토: 지금 initrd에는 C 빌드에 필요한 것(헤더 · crt · `cc` · `ld` · `make`)이 하나도 없다 — PM design 결정 4의 "`brew install gcc`가
  열 수 있다"는 낙관이었다(TP design 확인 2 · 3).
- [x] TP design 초안 — 디스크(p3)의 squashfs 묶음을 init이 `/usr` 위에 읽기 전용 overlay로 얹는다. 출처는 매니페스트(`upstream` →
  `vendor-repo` → `prebuilt` → `debian`), 소스 빌드 없음, `tars-install <disk>`가 새 설치 · 갱신 때 함께 옮긴다(하위 명령 없음). `98b3c93`.
- [x] 최소 설치 디스크 16GiB + 2MiB(`disk.MIN_DISK_BYTES`, TP 결정 18). 체인 install · home · pm · mise · dualboot의 디스크 크기. `4e5d2f1`.
- [x] initrd 기준 `docs/guides/initrd-criteria.md`(A · B · C, 크기 기준 없음). 그 기준 B로 lsoff · doge를 공식 정적 바이너리(sha256 고정,
  Dockerfile 층 20)로 initrd에 — UT design 결정 3 취소(사용자 확정). tools 체인 검사 10b. `d8a899b`.
- [x] `PATH=/usr/local/bin:/usr/bin:/bin`(TP 결정 20) — environ · config_front · sudoers, 체인 tools · config · pm · net · service. `c6e2831`.
- [x] 기억 `feedback_tool_sourcing`(출처 · 기준 · 용어 · PATH).
- [x] 루트 게이트 셋: 16GiB 17분 58초, +lsoff · doge 18분 04초, +PATH 18분 14초. 모두 30/30, 잘린 줄 0.

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 design의 번호로)

- 출처 종류의 이름과 순서(TP 결정 1), 묶음 나누기(결정 7 — 파일 하나 4GiB 아래), 개발 도구 층은 따로 빌드 · 캐시하고 다른 체인은
  층 없는 ISO로(결정 6, 게이트 시간 보존).
- dasht의 docset 추천 묶음(결정 19) — 사용자가 "추천대로".
- TP-M8: gnu와 musl이 둘 다 있으면 gnu, hugo는 extended(`withdeploy` 아님), ffmpeg는 9.0 gpl, 셸 완성은 비목표(`carryover.md`), 체인 F-1의 목록은 체인에 적는다(매니페스트에서
  계산하지 않는다), 상한은 넷 다 60초, ast-grep의 `sg`는 링크하지 않는다.
- TP-M7(위임): `EDITOR` · `/usr/bin/editor`는 vim 그대로, mitos는 `.deb`가 아니라 tarball, 셸 완성은 싣기만(M8에서 함께 본다), 실행 파일 하나도
  `/usr/local/lib/<도구>-<판>/bin/`에. 체인 상한은 넷 다 60초(잰 값 2초 아래).
- TP-M2(위임): g++를 base에(결정 A), rust 컴포넌트 고르기(rust-docs · rust-analyzer · rust-src는 싣고 llvm-tools · docs-json은 뺀다),
  형식별 훅(묶음별이 아니라), `rust-objcopy`에 libLLVM 상대 링크(예외 대신), go testdata의 예외 이유 `testdata`, 캐시 빠른 길은 안
  넣었다(lang-native 51초 < 60초), hello 상한은 잰 값의 세 배(60초 아래로는 안 내린다), HP-M2의 별표 검사를 init 줄에 견디게.
- `disk_test`는 실제 sfdisk가 쓴 7GiB 맥 GPT 고정 데이터를 그대로 두고 "그 5.8GiB는 이제 거절"로 바꿨다. dualboot의 가짜 맥은 19 · 20GiB.
- pm · mise 체인이 주는 최소 PATH(`/usr/bin:/bin`)는 그대로 — "brew · mise가 보이면 rc가 넣은 것"이라는 판정의 전제다.

## 시도했으나 실패한 접근

TP-M8(2026-11-07):

- alias를 시드 rc(`init/src/config.zig`)에서만 고치고 "검증 없이" 커밋 — init의 `config_test.zig`가 `ALLOWED_ALIAS_NAMES`로 묶고 있어 게이트의 사전 빌드에서 멈췄다.
  `make quick`은 init의 `zig build test`를 돌리지 않는다(macOS에서 안 끝난다) — 시드 rc를 바꾸면 컨테이너에서 `zig build test`.
- chroot 뿌리를 만들 때 cpio가 없는 이미지 + `|| true` — initrd 없이 섰다(TP-M5의 같은 함정). 풀린 항목 수와 `bash`를 찍는다.
- 판 옵션 시험을 출력 첫 줄로만 — ffmpeg · ffprobe의 `--version`은 판을 찍고 0이 아닌 값으로 끝난다(`-version`이 맞다). 종료 코드를 센다.
- 크기 어림을 `tar | zstd -15`로 — squashfs는 128KiB 블록마다 압축해 util이 약 20% 컸다(192 어림 → 236MiB).

TP-M7(2026-11-07, plan 확인 4):

- Doom Emacs를 빌드 때 시드로: 망 있는 컨테이너의 `doom install`(12분 43초, 289MB)을 다른 홈으로 옮기면 Doom 부팅이 `file-missing`으로 멈추고,
  망 없는 `doom sync`는 y/n을 묻고(`yes |`로 답해도) 끊긴 `straight/build-30.1/…`에서 죽는다. straight.el의 빌드가 홈 경로로의 절대 링크 3,957개다.
- ttt의 TUI를 `timeout 8`로 끝내기: SIGTERM에 안 끝나 컨테이너가 매달렸다 — `--exec … quit`만 쓴다. 시험 스크립트의 `--eval`로 `doom-after-init-hook`을
  걸면 이미 지난 hook이다(한 판을 버렸다) — init 뒤 확인은 `-l <파일>`.

TP-M5(2026-11-06, plan 확인 3 · 4에 자세히):

- scala3의 `scala run`을 오프라인으로: Bloop은 `-r` 동봉 저장소를 안 본다(합쳐도 같은 오류), `COURSIER_REPOSITORIES`는 다른 해석 경로로
  멈춘다, 런처의 옵션 줄에 `--server=false`를 끼우면 모든 명령이 깨진다. 통한 것은 `~/.cache/coursier` 시드뿐 — 그러나 사용자가 scala를 뺐다.
- clojure의 오프라인: 설치 디렉터리 `deps.edn`에 `file://` 저장소, 셋을 `:local/root` jar로 — 둘 다 안 된다(tools.deps가 `central`부터 찾고 망 오류를
  "없음"이 아니라 실패로 다룬다). `~/.m2` 시드만 통한다. Java의 `user.home`은 `$HOME`이 아니라 `/etc/passwd`의 홈이다(root 컨테이너에서 헷갈렸다).
- 조사용 이미지에 `cpio`가 없어 시드 0개를 복사하고 "jar · pom만으로는 안 된다"고 읽을 뻔했다 — 복사된 파일 수를 먼저 찍는다.

TP-M3 · M4(2026-11-06):

- ruby/ruby-builder(design 확인 8의 출처): `--prefix=/opt/hostedtoolcache/…`로 굳은 빌드(`LIBRUBY_RELATIVE=no`, 절대 RUNPATH) — 옮기면 안 선다.
  rv-ruby로 바꿨다.
- static-php-cli의 미리 빌드: 2026-07의 8.5.8에서 멈췄다(sha256도 안 낸다). php는 사용자 결정으로 Debian 8.4.
- python site `pip.conf`의 `prefix=/usr/local`: 사용자의 `pip install --user`가 `Can not combine '--user' and '--prefix'`로 막힌다 → `sitecustomize.py`.
- "일반(AVX2) bun이면 체인이 빨개진다"는 빨강: QEMU TCG는 CPUID에 없는 AVX2를 그냥 실행한다 — 체인으로 CPU 수준을 못 잡는다(measurements 103).
- base에 grep 줄: 개발 컨테이너(initrd)의 `3.11-4+b1`과 거두는 이미지의 `3.11-4`가 달라 결정 4에 걸린다 — 넣지 않았다.
- `man gcc`: Debian은 gcc의 man을 non-free `gcc-doc`으로 뺀다 — 없다. 체인은 `man 1 ssh`.
- Rosetta(amd64 컨테이너) chroot의 gdb · strace · ltrace: ptrace가 없다(`PTRACE_TRACEME: Function not implemented`) — 판정은 체인만.
- 체인 로그를 ANSI가 섞인 채 `rg`로 걸러 "출력이 없다"고 읽은 판이 있었다(실제로는 있었다). 그 판독으로 세운 "`bash -i`가 tty를 가져갔다"는 추정은 틀렸다 —
  로그는 바이트로 읽는다(`python3`로 `133;C` 뒤를 본다).

TP-M0~M2:

- 컨테이너에서 Temurin JDK tarball을 받아 `NEEDED`를 재려 했다 — GitHub 다운로드가 504를 다섯 번 냈다. JDK 쪽 실측은 TP-M0의 몫.
- GitHub release API로 hexyl 자산을 찾을 때 grep 필터가 linux 자산을 걸러 "없다"고 잘못 말했다(실제로는 musl tarball과 `.deb`가 있다).

## 남은 작업

- [x] FS 소개 페이지(`gh-pages` `data.js`, `495cf9e`) — 사용자 승인 뒤 push했다(2026-11-07).
- [ ] TP-M11 plan — 서버(서비스). TP-M10(실행 파일)은 끝났다. 그 뒤 AI.
  사용자는 조사 · 구현을 단계별로 보고받기를 원한다. ISO가 1.86GB다 — 2GiB 한도(아래 사용자 결정 대기)까지 약 288MB. 묶음은 squashfs 하나씩이라 떼어 낼 수 있다(media가 첫 후보).
  체인은 빌드 뒤 약 593초다. dasht처럼 셸 스크립트가 부르는 의존은 verify의 NEEDED가 못 잡는다 — 체인이 본다(TP-M9). 체인을 가를지는 게이트 lane-0(ISO 줄, 직렬)의 합으로 본다(TP-M5 plan 확인한 것 6). 체인의 표시 글자는 명령 줄에 그대로 쓰지 않는다
  (TP-M4 plan 확인한 것 9), `as_tars`는 작은따옴표를 못 담는다(SQL의 `'`는 printf `\x27`). 매니페스트의 선택 키는 다섯 — 한도. `vendor-repo`는 서버 묶음이 처음 세운다.
  CPU 수준: 묶음의 실행 파일은 SandyBridge(에어 2011)에서 돌아야 한다 — 받을 때 AVX2 전용 빌드인지 본다(TCG는 못 잡는다). `%ymm` 수가 아니라 ymm이 든 함수의
  비율을 본다(DuckDB 2.0 — TP-M8 plan 확인 11). 자동 검사는 `carryover.md` 후보.
  Debian 줄이 perl에 기대면 base에 둔다(rlwrap · ipcalc · vifm). 의존이 initrd의 것과 부딪치면 `harvest-skip.tsv`(alternatives는 skipalt가 함께 뺀다).
- [ ] 사용자 결정 대기: 0.2 전에 GitHub release의 파일당 2GiB 한도를 어떻게 넘을지(지금 ISO 2.03GB — 2GiB까지 약 113MB, TP-M10 뒤. AI 묶음이 남았다) — 묶음을 따로 올리기 등.
  design 결정 12(ISO가 묶음을 싣는다)와 맞물린다. `docs/decisions/project_release_0_2.md`.
- [ ] 사용자: 실기에서 개발 도구 층 — 프리릴리스 `dev-20261106`(TP-M3까지)이 올라가 있다. 다음 프리릴리스는 TP의 남은 milestone을 모두 마친 뒤에
  만든다(사용자 2026-11-06 — "남은 작업을 모두 마치고 프리릴리즈를 준비할게"). 절차는 `project_release_0_2.md`. 볼 것: 망 없이 언어들의 hello, 특히 `ruby -v` · `bun --version`(에어 2011의
  CPU에서 서는지가 남은 확인), `sudo npm i -g` 등이 `/usr/local/bin`에 서는지, javac 시간(TCG 11초). TP-M5 뒤: `cci --version` · `glc --help`가 에어 2011에서
  서는지(둘 다 x86-64 v1 빌드로 보이지만 `%ymm`이 있다 — TCG는 못 잡는다), 망 없이 `clojure -M -e '(+ 1 2)'` · `clj`(rlwrap의 줄 편집), `kotlinc` 시간. TP-M6 뒤: 새 프로젝트의 첫 `mix test`(JIT — 에어 2011의
  진짜 SandyBridge에서 Illegal instruction이 없는지), `gleam new` → `gleam run`(망 없이), `erl -man lists`. TP-M7 뒤: `ms` · `ttt`가 에어 2011에서 서는지(`%ymm`이 있다 — 실행 중 고르기로 보인다), TP-M9 뒤: `dasht printf Bash`의 w3m 화면이 TARS 터미널에서 맞게 그려지는지, 망이 있을 때 `tars-docs get`(약 700MiB)과 `dasht <말>`, TP-M8 뒤: util의 60개와 ffmpeg가 에어 2011에서 서는지(`rg --version` ·
  `ffmpeg -version` · `duckdb`의 GROUP BY 하나), TUI 도구(lazygit · yazi · gitui · herdr · vifm · lazysql)의 화면이 TARS 터미널에서 맞게 그려지는지, `emacs`의 첫 native-comp(gcc를 부른다)가
  견딜 만한지, 망이 있을 때 `git clone … ~/.config/emacs && ~/.config/emacs/bin/doom install`이 TARS 위에서 되는지(체인은 안 봤다).
- [ ] 사용자: 맥북 실기 — 아래 "사용자가 확인할 것"의 LP 절. 다음 번호는 0.2.0(TP 전체 뒤)이다. 최소 디스크는 16GiB다.
- [ ] 보류: Pro 2013 내장 Wi-Fi(BCM4360) — `carryover.md`의 "맥 실기" 절.

## 다음 에이전트에게

이 저장소의 규칙(CLAUDE.md): 큰 편집은 먼저 설명, 매 편집 뒤 `git diff --stat` · `git diff | rg '^-'`, 명령은 Claude가 실행, 커밋은
사용자 승인 뒤, push는 묻지 않는다(`feedback_push_policy`). init의 `zig build test`와 terminal 빌드는 컨테이너에서. 체인 하나: `docker run
--rm --sysctl net.ipv4.ip_local_reserved_ports=45455-45599 -v "$PWD":/workspace -w /workspace tars-devcontainer ./tools/check.sh`. 루트
게이트는 시작하며 `out/gate-logs/`와 `out/` 아래 로그를 비운다 — `time make gate`의 출력은 scratchpad에 둔다. 게이트가 도는 동안
`*/check.sh`를 작업 트리에서 고치지 않는다(bash가 실행 중에 스크립트를 읽는다). 한 파일에 두 커밋 몫이 섞이면 `git add -p` 대신
작업 파일을 고쳐 `git hash-object -w` → `git update-index --cacheinfo <모드>`로 덩어리만 올린다(모드는 `git ls-files -s`).
용어: "개발 도구 층"(전체), "묶음"(squashfs 하나), `guest_tools.sh`의 "층 N"은 UT 때부터의 목록 번호. 도구를 더할 때는
`initrd-criteria.md`와 `feedback_tool_sourcing`. 새 체인의 monitor · QMP 포트는 45505부터. initrd에는 `mount` · `free` · `base64` · `dd`가 없다(체인은 mount(2)를
부르는 init · 설치기에 기댄다). 묶음이 얹힌 부팅에는 coreutils 전부가 있다(TP-M4) — 묶음 없는 체인에서는 여전히 쓰지 않는다.

TP 묶음 작업 요령(TP-M3 · M4에서 배운 것):
- 새 도구는 받기 전에 배포처의 기계용 목록(GitHub `releases` API의 `digest`, nodejs `index.json` 등)으로 판 · sha256을 정하고, amd64 trixie-slim에서
  한 번 띄워 본다. 옮길 수 있는 빌드인지(절대 prefix · RUNPATH)와 CPU 수준(AVX2 전용인지, `objdump`의 `%ymm`)을 본다.
- 묶음 안 설정 파일은 `devlayer/files/<묶음>/`. 경로에 `<도구>-<판>`이 들어가면 판을 올릴 때 디렉터리 이름도 고친다(build.sh가 이름을 대고 멈춘다).
- harvest의 캐시 열쇠는 매니페스트 줄 + `harvest.sh` · `harvest-skip.tsv`의 해시 한 줄이다 — harvest.sh를 고치면 base를 다시 거둔다(3~4분).
- 체인의 표시 글자는 명령 줄에 그대로 쓰지 않는다(`printf "tp-m4-%s\n" ok` · `sed` 접두 · 실제 출력만 가질 글자로 기다린다). 콘솔이 명령을 되비춰
  `wait_log`가 출력 전에 맞는다(TP-M4 plan 확인한 것 9).
- chroot 시험은 버리는 amd64 컨테이너에서 initrd를 풀고 묶음을 `unsquashfs`로 덮은 뒤 `/dev/null`을 `mknod`해 둔다(perl이 그것으로 넘어졌다).

## 핵심 파일

- `devlayer/manifest.tsv` — 개발 도구 층의 유일한 출처(도구 · 묶음 · 판 · 종류 · URL · sha256 · 선택 열).
- `devlayer/build.sh` — 받기(`fetch_checked`) · 풀기(`strip=`, 압축 없는 실행 파일 하나 — TP-M7) · 종류 `maven` · `hex`(잠금 파일 → `seed/`) · `man1=` 링크 · hex 시드와 `seed/manifest.toml` 대조 · `devlayer/files/` 얹기 · verify · 묶음 사이 대조 · 굽기.
  `devlayer/maven/*.lock` — Maven Central의 경로 · sha256. `devlayer/hex/*.lock` — Hex tarball · sha256. 훅 `clojure-tools.sh`(자리표 · 시드 줄) · `otp-install.sh`(`Install -cross`) · `gleam.sh`(런처). `devlayer/harvest.sh` — debian 줄 거두기(man 제외 풀기,
  계정 · sysvinit 자리 빼기, `harvest-skip.tsv`, 남의 이름인 alternatives `editor` · `ctags` 빼기, `common-licenses` 본문 싣기 — TP-M7, skip 패키지로 펴지는 alternatives 빼기 `skipalt` — TP-M8). `devlayer/needed-ignore.tsv` — NEEDED 예외의 이유 넷(GUI · jvm-loaded · exe-loaded · testdata). `devlayer/verify.sh` — 결정 4(겹침) · 5(NEEDED). `devlayer/manifest.sh` — 파서.
- `devlayer/files/lang-script/…` — npmrc · `operating_system.rb` · `sitecustomize.py`. `devlayer/files/lang-native/etc/…` — PATH 조각.
- `init/src/layers.zig` — `mountAll`(`/usr` overlay) · `mountLocal`(`/usr/local` 쓰기 층) · `copyTree`(`/etc` 복사, 링크 포함). 호스트 검사 `layers_test.zig`.
  부르는 자리 `init/src/main.zig`의 `readConfig`(`mountHome` 바로 뒤).
- `kernel/make_initrd.sh` — 시스템 rc 셋(`/etc/bash.bashrc` · `/etc/zsh/zshrc` · fish `conf.d`)과 `/etc/tars/rc.d` 읽기.
- `devtools/check.sh` — 체인(부팅 넷). `TP_CPU=SandyBridge`, 부팅 2의 hello 덩이들, 부팅 3의 `/usr/local` 잔존.
- `devlayer/hooks/dasht.sh`(sqlite 3.54 파싱 한 줄), `devlayer/files/docs/usr/local/bin/tars-docs`(docset 한 번에 받기).
- `docs/specs/2026-11-05-tars-dev-layer-design.md`(14판), plan `docs/plans/2026-11-06-tars-dev-layer-tp-m{2,3,4,5,6}.md` · `2026-11-07-…-tp-m{7,8,9}.md`.

## 지금 상태 (2026-11-07)

- 진행 중인 것은 TP(design 14판, M0~M9 끝). 다음은 첫걸음 안내(새 milestone, design부터), 그 뒤 TP-M10. 마지막으로 닫은 것은 PW · RB · LP. 최신 공개 버전 0.1.4(tag `v0.1.4` = `d93a8aa`).
- 체인은 서른하나다(`check.sh`의 `CHAINS`, 끝이 `LP-M1:./sleep/check.sh` · `TP-M1:./devtools/check.sh`). 마지막 루트 게이트 31/31, 31분 58초(TP-M9 — lanes 1,426초, devtools 713초).
  `make gate`는 먼저 `make dev-layers`(묶음 아홉 — base · docs · editor · lang-beam · lang-jvm · lang-native · lang-script · media · util, 캐시면 약 1분 반 — lang-native의 다시 풀기가 51초)를 부른다 — devtools 체인은 그 위에서 검사만 다시 돈다.
- initrd는 도구 112개(lsoff · doge 포함), 풀면 약 141MB.
- 닫은 서브프로젝트의 경과 · 함정 · 숫자는 `docs/guides/completed.md`의 표와 `docs/decisions/`의 기억 파일이다.
- 테스트 흐름: 실기는 쓰지 않고 테스트마다 `tars-install <disk> --wipe`로 새로 깐다.

## 사용자가 확인할 것 (실기 또는 실제 장치가 있을 때)

- LP · PW · RB — MacBook Air 2011 · Pro 2013. 프리릴리스 `dev-20261106`(또는 그 뒤 판)이나 main의 `make iso`로 USB 갱신한다(0.1.4에는 없다).
  - 첫 부팅이 화면까지 뜨는지 — i915가 simpledrm을 넘겨받는다. 검은 화면이면 i915가 `card0`이 아닌 번호를 받은 것(LP 위험 1):
    Limine 메뉴(3초)에서 아래 화살표로 `(old)`를 골라 갱신 전 이미지로 뜨고 알려 준다.
  - 밝기: Air 내장 키보드의 F1 · F2. 로그 `terminal: backlight> pick=intel_backlight of N` · `backlight> intel_backlight A -> B of MAX`.
    `pick=none`이면 `ls /sys/class/backlight`. 16단계가 손에 맞는지, 가장 낮은 단계가 너무 어두운지.
  - 절전: 뚜껑을 닫았다 연다. 로그 `tars-init: lid closed` · `suspend (deep)` · `resumed after Nms`. 깨어난 화면이 다시 그려지는지(키 하나),
    무선이 다시 붙는지(`tars-config wifi`, brcmsmac — LP 위험 2), USB · 내장 키보드의 첫 키(위험 3), 배터리 칸이 곧 따라오는지(위험 6).
    `suspend (s2idle)`이면 펌웨어가 S3를 안 내놓은 것(위험 4). `sudo suspend`도 한 번.
  - 비밀번호 칸: `tars-config wifi …`의 passphrase와 `sudo`의 칸에 `*`가 찍히는지, Backspace가 하나씩 지우는지.
  - `sudo reboot` · `sudo poweroff`.
  - 소리가 여전히 나는지(i915를 켜도 `gpu_bind=0`이라 그대로여야 한다) — `speaker-test -c 2 -t wav -l 1`.

- MB · HS · DB — 맥 두 대(이번 판의 본론, 게이트는 드라이버 등록까지만 봤다).
  - 준비: macOS에서 Time Machine 백업 → `diskutil list` → `diskutil apfs resizeContainer disk0s2 <크기>`(HFS+면 `diskutil resizeVolume`)로
    빈 공간(0.1.4는 4GiB 넘게, main · 0.1.5부터는 16GiB 넘게) → 0.1.4 ISO를 USB에 `dd`(`docs/guides/running-tars.md`의 macOS 절). 디스크 유틸리티의 "파티션"으로
    MS-DOS(FAT) · ExFAT 파티션을 만들어도 된다(DB-M1). APFS로 만들었다면 `diskutil eraseVolume free free disk0sN`으로 빈 자리로.
  - 전원을 켤 때 Option → "EFI Boot"로 USB가 보이는지(ISO의 EFI 파티션). 안 보이면 그것이 새 사실이다.
  - `tars-install` 목록에 내장 디스크가 `GPT: EFI, macOS (APFS); N GB free`로, 그 밑에 파티션 줄이 보이는지(FAT 파티션을 만들었으면
    `<- tars-install /dev/sda3 installs here`) → `tars-install /dev/sda --beside` 또는 `tars-install /dev/sda3` → 재부팅하며
    Option → TARS-BOOT가 "EFI Boot"로 보이는지(DB 위험 3 — Air 2011은 확인됨, 2026-11-05: `/dev/sda3` 지정 설치 → EFI Boot → TARS
    터미널). Pro 2013은 아직. macOS가 그대로 뜨는지도(Air는 사용자가 준비 중 macOS를 지워 볼 수 없다).
  - Air 2011 실기 결과(2026-11-05, 사용자): 트랙패드 · 속도 좋음, Cmd · Option과 Cmd+Option+화살표 패널 이동 정상, 소리 정상(speaker-test의
    핑크 노이즈 — MB 위험 1은 안 일어났다), 배터리 칸 정상. Bluetooth 어댑터가 `Controller … BlueZ 5.82 [default]`로 잡혔다(보정
    펌웨어 없이 — BT 위험 6은 안 일어났다). 내장 무선이 5GHz 망에 붙어 주소를 받고 `curl`이 바깥까지 간다(BW 위험 1 풀림). BT 장치 페어링은 아직.
    게스트에 `ping`이 없다 — 다음 판의 작은 숙제(`iputils-ping`). 실기가 드러낸 거친 곳 셋(`tars-config help`에서 bluetooth를 못
    찾음, `tars-config bluetooth=on`이 쓰는 법만 찍음, 꺼진 버스에서 `bluetoothctl`이 SIGABRT)은 고쳤다 — help의 "turning things on" 절,
    `missing_set`, `/usr/bin/bluetoothctl` 감싸개(bluetooth 체인 검사 8).
  - Option 화면의 이름(2026-11-05, 사용자 요청): TARS-BOOT와 USB가 "EFI Boot" 대신 "TARS Linux"로 보이게 `EFI/BOOT/.disk_label(_2x)`
    (macOS `bless --label`이 그린 그림, `boot/make_disk_label.sh`)를 ISO의 EFI/BOOT와 El Torito FAT 이미지에 넣고 `disk.BOOT_FILES`로
    복사한다. QEMU는 이 그림을 안 읽어 실기 확인이 남았다.
  - Pro 2013 실기(2026-11-05): Limine 메뉴가 GOP 화면에 보인다(KU의 이월 확인 하나가 풀렸다). Retina 2배가 잘 보이고(HS 결정 3),
    트랙패드 · 키보드 · 배터리 · Bluetooth 정상. 기종은 MacBookPro11,x(코덱 SSID `106b:5e00`, CS4208). 소리가 안 났던 원인은 init의
    오디오 일꾼이 카드 0만 기다린 것 — 카드 0(HDMI 쪽 HDA)이 i915 없이 안 서서 노드 권한 · 믹서가 그대로였다. 아무 카드나 기다리게 고쳤다
    (audio 체인 부팅 C가 `snd_hda_intel.index=1`로 보고, 되돌리면 빨개지는 것도 봤다). 실기 확인은 다음 0.1.4에서.
    내장 Wi-Fi(10,1 BCM4331 · 11,x BCM4360)는 사용자 결정으로 대기 — 조사는 `carryover.md`의 "맥 실기" 절.
  - 트랙패드: 한 손가락 이동 · 탭 · 두 손가락 스크롤, 로그 `pointer> open … kind=touchpad`. 손에 안 맞으면 `touchpad_accel`부터(MB 위험 2).
  - 키보드: `keyboard> open … kind=apple`, Cmd · Option 자리. Fn 조합이 없는 것이 거슬리는지(MB 위험 3).
  - 소리: `speaker-test`. Air4,1이 안 울리면 MB 위험 1(`snd_hda_intel.model=mba42`).
  - 배터리 칸이 뜨는지, 어느 길인지(`ls /sys/class/power_supply`).
  - Retina: 로그 `kms: scale 2 (2880x1800 -> 1440x900)`. 펌웨어가 낮은 모드를 주면 `scale 1`로 나온다(HS 위험 2). 출력이 쏟아질 때 늦지
    않은지, `sudo tars-config set display_scale=1` · `tars-config reload` · `tars-config reload terminal`로 1배와 비교.
  - 외장 USB 마우스 · 키보드를 함께.
- 무선: Air 2011은 내장(`tars-config wifi …`, 로그 `bcma` · `brcmsmac`, 안 되면 BW 위험 1). Pro 2013은 내장이 없다 — 유선 USB 어댑터나
  USB 무선 동글(UW · UB 계열). 내장 Bluetooth는 세 기종 다 `bluetooth=on` · `bluetoothctl`(보정 펌웨어 없이 돈다 — 안 되면 BT 위험 6).

- PS: 노트북 터치패드 + USB 마우스를 함께 쓰며 — 기본값에서 마우스 휠은 앞으로 = 위의 글, 두 손가락은 내용이 손가락을
  따라가는지. `sudo tars-config set mouse_scroll=natural` · `tars-config reload` · `tars-config reload terminal` 뒤 마우스만 뒤집히는지.
  로그 `pointer> open … kind= scroll= accel=`가 장치마다 맞는지 — 터치패드가 `kind=mouse`로 열리면 design 위험 1(`carryover.md`에).
  가속: `touchpad_accel=5` · `mouse_accel=5`로 — 천천히 칸 하나를 고르는 손이 그대로인지(배율 1), 빠르게 밀 때 화면 끝까지 한두 번에
  가는지, 10이 너무 세거나 1이 이미 거슬리는지. 맞지 않으면 값은 `pointer.ACCEL_V_LOW_MPX` · `ACCEL_V_HIGH_MPX` · `ACCEL_GAIN_MAX` ·
  `ACCEL_IDLE_US` 넷이다(design 위험 2). 손가락을 뗐다 다시 댄 첫 이동이 튀지 않는지(위험 3).

- KK: 일반 노트북 내장 키보드 + Apple 키보드(USB 또는 BT)를 함께 꽂고 — 두 키보드에서 Option+← · Cmd+←(PC 키보드는 Alt 자리가
  Cmd)가 각자 맞는지, 로그 `terminal: keyboard> open … kind= bus= vendor=`가 둘에 맞게 찍히는지(BT Magic Keyboard가 bus `0005` ·
  vendor `004c`인지). Mac 배열 서드파티 키보드가 있으면 그 vendor(design 위험 1 — `pc`로 읽히면 `carryover.md`의 KK 절). MacBook 내장
  (2015년 전)은 `kind=apple`이어야 한다.

- DM: 키보드 둘(노트북 내장 + USB/BT)로 — A의 Shift를 쥐고 A로 글자 하나를 친 뒤(커널 반복을 멈춘다, DM 실측 1) B의 Shift를
  눌렀다 떼고 B로 글자 → 대문자가 그대로인지. A의 Shift를 쥔 채 B를 뽑아도 A로 친 글자가 대문자인지. 두 키보드의 왼쪽 Ctrl을
  겹쳐 눌렀을 때 한/영이 안 바뀌는지.

- MI: 화면 셸에서 `curl https://mise.run | sh` → 새 패널에서 `mise use -g node@lts` → 또 새 패널에서 `node --version`. rc를 안
  고쳐도 되는지(시스템 rc), 실기에서 패널을 열 때 늦어진 것이 느껴지는지(TCG는 셸 하나에 약 115ms, 부팅 뒤 첫 패널은 mise를
  디스크에서 처음 읽는다), 프로젝트 디렉터리에 `mise.toml`을 두고 `cd`했을 때 버전이 바뀌는지. 다른 런타임(python · go)은 처음이다.

- PM: 화면 셸에서 공식 안내 그대로 `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
  — 게이트는 `NONINTERACTIVE=1`이라 대화형 길(RETURN 누르기 · 비밀번호 묻기)은 처음이다. 실기에서 걸리는 시간(TCG 1GiB는
  140초). 끝의 "Next steps"가 rc에 eval을 넣으라고 하는데, 넣지 않고 새 패널을 열어도 `brew`가 되는지(시스템 rc, 결정 5),
  넣어도 PATH가 두 번 안 붙는지. 그다음 실제로 쓰고 싶은 formula 하나(`chafa` 등) — bottle이 없으면 소스 빌드라 안 된다(결정 4).

- HP: 화면 셸에서 `sudo tars-config set …`이 비밀번호를 한 번 묻고 그 패널에서 15분 동안 다시 안 묻는지, 다른 패널은 따로
  묻는지(timestamp가 tty 단위 — 거슬리면 `carryover.md`). `sudo tars-config passwd` 뒤 새 비밀번호, 사용자로 `tars-config set`을
  쳤을 때의 `try: sudo` 줄이 읽히는지.
- HP: 실제 키보드로 `tars-install`의 질문 셋 — 이름을 틀리게 쳤을 때 다시 묻는 말이 읽히는지, 비밀번호가 화면에 안 찍히는지(확인
  칸이 없어 오타가 그대로 들어간다 — 거슬리면 두 번 묻기). 설치 뒤 화면 셸에서 `id` · `echo $HOME` · `speaker-test`(소리), 명령
  몇 개를 친 뒤 재부팅하고 `history`가 남는지와 `ls ~/.local/share`(HP 실측 11), `bluetooth=on`인 기계에서 사용자의 `bluetoothctl`.

- KH: BT 키보드를 페어링 · 연결한 뒤 곧바로 글자가 쳐지는지(`keyboard> open … name=…`), 노트북 내장 키보드와 함께 쓸 때 한/영 ·
  조합이 이어지는지. `keyboard> open`이 같은 `name=`으로 둘 뜨고 글자가 두 번 나오면 KH 위험 6이다. 부팅 때 키보드가 하나도 없는
  기계(BT만)의 3초는 IK-M0이 걷었다 — 그런 기계에서 화면이 곧바로 뜨는지.
- BT: `tars-config set bluetooth=on` · `tars-config reload` 뒤 `bluetoothctl list`에 내장 어댑터가 뜨는지(안 뜨면 `dmesg | grep -i
  bluetooth` — firmware 이름이 안 보이면 그 이름을 `guest_firmware.sh`에). BLE 마우스를 `scan on` · `pair` · `trust` · `connect`한 뒤
  화살표가 움직이는지 — 게이트가 못 보는 uhid → evdev → terminal의 길이다(BT design 위험 4). 재부팅 뒤 마우스가 스스로 다시 붙는지
  (`/config/bluetooth`의 키). dbus-daemon의 소켓이 실기에서 몇 ms에 생기는지(`tars-bluetoothd: bus ready after Nms`, TCG는 2000).
  initrd가 23MB 커진 만큼 실기 부팅이 느려졌는지(QEMU는 +0.48초).
- RS · DR: 로그에 `kms: present by dirtyfb`가 찍히는지, `cat` · 빌드 로그처럼 출력이 쏟아질 때 화면이 매끄럽게 따라오는지,
  키 입력이 늦게 느껴지지 않는지. DR 뒤로 키 하나는 바뀐 행 몇 줄만 VRAM으로 가므로(simpledrm은 clip마다 복사) 체감이 달라야
  한다 — 달라지지 않았으면 그것이 새 사실이다. SB 뒤로는 상태 줄 띠(1280 × 28 = 143KB, 1080p에서 153KB)도 내용이 바뀐
  프레임에만 간다. TCG에서 키 하나의 그리기는 0.42ms다(SB-M0). 한/영 · CapsLock · 배터리가 바뀔 때 상태 줄이 그 프레임에
  바로 따라오는지도 본다(안 따라오면 `StatusMemo`의 비교가 그 칸을 못 보는 것).
- TC: `tars-config wifi …`와 `tars-config dictation key`의 tty 입력(echo 없이 묻는다), `tars-config set net=dhcp ntp=dhcp`,
  `tars-config reload`, `tars-config reload terminal`. 게이트가 못 보는 것은 tty 질문, `--country`, `firewall deny`,
  `firewall=off`의 말이다.
- AU: `cat /proc/asound/cards` · `aplay -l` · `arecord -l` · `speaker-test`, 헤드폰 잭 · USB 헤드셋. SOF 노트북이면
  `dmesg | grep -i sof`의 `Firmware file:` · `Topology file:`. 조용하면 `amixer -c N` · `snd_intel_dspcfg.dsp_driver=1`.
- BS: 노트북에서 상태 줄 오른쪽 끝에 칸이 뜨는지, 어댑터를 꽂았다 뺄 때 색이 곧바로 바뀌는지, 방전 중 잔량이 60초 안에
  따라오는지. 칸이 안 뜨면 `cat /sys/class/power_supply/*/type`과 로그 `terminal: battery> scan …` 줄(`carryover.md`의 BS 항목).
- MC: 실기 마우스로 더블클릭 · 트리플클릭이 손의 속도에 맞는지(500ms · 8픽셀), 터치패드의 두 번 탭이 더블이 되는지(탭 판정
  180ms 뒤 두 탭 끝의 차). 안 맞으면 값은 `pointer.MULTI_CLICK_US` · `MULTI_CLICK_PX` 둘이다(설정은 MC 비목표 3).
- SE: 끌어 뗀 뒤 반전이 남는 것이 거슬리는지(글자를 쳐도 남는다 — 거슬리면 SE 비목표 1, 키 경로에 `clearLinger` 한 줄), Shift
  클릭이 늘리는 끝이 손의 기대와 맞는지(가까운 끝). 자식이 마우스를 원하는 패널(vim)에서 Shift 끌기 뒤 Shift 클릭도 같다.
- KU: 실기에서 설치된 디스크로 뜰 때 메뉴 3초가 손에 맞는지(길면 `disk.MENU_TIMEOUT`), 갱신한 뒤 메뉴에서 아래 화살표로
  `(old)`를 골라 뜨는지. 실제 펌웨어에서 Limine 메뉴가 GOP 화면에 보이는지도 이때 처음 본다. 커널 6.18.60 자체의 실칩 동작(SOF ·
  무선 · 그래픽)도 처음이다 — 이상하면 old(6.18.42)를 고르는 것이 이 서브프로젝트의 목적이다. 0.1.3 이하로 깐 디스크는 `boot/version`이
  없어 첫 갱신에 old가 안 생긴다(`carryover.md`의 KU 항목).
- ER: Shift 더블 · 트리플클릭이 단어 · 줄로 느는지, Shift 클릭 바로 뒤(500ms · 8픽셀 안) Shift 없이 누른 클릭이 지우기가 아니라
  단어 늘리기가 되는 것이 거슬리는지(거슬리면 ER 비목표 1 — 둘째 누름의 Shift를 본다).
- WP-M3: `Cmd+Option+화살표`(`keyboard=pc`면 `Alt+Win+화살표`)로 패널 사이를 다닐 때 손에 맞는지, 동률의 "맨 위 · 맨
  왼쪽" 규칙이 어색하지 않은지. 어색하면 최근 포커스(tmux식)가 다른 후보였다.
- VD: `/config/groq.key`를 만들고 오른쪽 Cmd 두 번. 첫 연결 지연, `cleanup timed out`이 매번 나면 `cleanup_timeout`을
  늘리거나 끈다, SOF DMIC 앞부분이 0인지(VD design 위험 1).

## 다음 후보 (새 서브프로젝트는 design부터, 방향은 사용자가 고른다)

- KH가 남긴 것(`carryover.md`의 KH 절)은 셋 다 닫혔다 — init 정리는 IK, 장치별 수정키는 DM, 키보드마다 종류는 KK. 남은 KH 항목은
  실기의 근거를 기다리는 자동 반복 · 칸 순서 · 두 노드 키보드다. KK가 남긴 것은 vendor가 배열을 말하지 않는 키보드(`carryover.md`의 KK 절).
- 커널 7.4 longterm 이동(12월 중순 예상, `carryover.md`의 KU 항목). 0.1.4는 그 전에 냈다 — 7.4는 0.1.5의 후보.
- BT 비목표에서 실기가 요구하면: Broadcom BT firmware(위험 6), `input.conf`의 `UserspaceHID` · `ClassicBondedOnly`, HID 배터리
  (`HID_BATTERY_STRENGTH`, BS design `scope` 행이 대비해 둔 자리). 오디오(A2DP)는 사용자가 뺐다 — 다시 열려면 코덱 + 오디오 서버.
- 렌더: 부분 갱신은 DR + SB로 닫았다. 남은 축은 GPU 가속뿐이다(키 하나 0.42ms 가운데 present 0.27이 커널 쪽, DR design "안 하는 것").
  실기 없이 할 수 있는 작은 것은 큰 kitty 이미지의 그리기 비용 하나(`carryover.md`).
- PS 비목표: 기본 속도(`*_speed`), 장치 이름별 설정, 스크롤 가속. SE 비목표: 키 입력이 남은 선택을 지우기(ghostty식) · 키보드 `y` 뒤에도 남기기.
- CB 범위 `workspace`(`docs/specs/2026-10-05-tars-clipboard-scope-design.md` 비목표 1).
- VD 비목표: 상주 프로세스로 연결 재사용(첫 연결 지연이 크면), 알림음, hold 모드.
- AU 비목표 10: SoundWire 코덱 노트북(`sof_sdw`), side-codec 스피커 앰프(실기가 요구하면).
- 패키지 매니저는 Homebrew로 닫았다(PM). 자체 매니저는 나중에 다시 논의(`carryover.md`의 PM 절). 이미지 뷰어는 Homebrew 위에서(`carryover.md`의 "이미지 뷰어 메모" — 기본 이미지에 뷰어를 넣지 않는다, 사용자 결정 2026-10-03). USB 동글은
  층 A(UW) · 층 B + rtl8xxxu(UB)로 끝났고 남은 것은 실제 동글이 근거를 줄 때.
- IPv6는 후보가 아니다 — IPv4만 지원한다(사용자 결정, 2026-10-31, `docs/decisions/feedback_ipv4_only.md`). 다시 여는 조건은 IPv6 망의 제품 탑재.
- vim 런타임 싣기는 2026-10-27에 착수 전 취소했다(`docs/decisions/user_editor_use.md`). 실측은 `docs/specs/2026-10-27-tars-vim-runtime-design.md`.
- 그보다 작은 것과 간헐은 `docs/guides/carryover.md`. 대부분 실기나 간헐의 다음 근거를 기다린다.

## 이어받는 사람이 볼 것

- Docker는 OrbStack이다(메모리 12GB). 소켓이 없다고 나오면 `orb start`. 호스트 디스크가 가득 차면(ENOSPC) 체인이 `ld.lld`에서
  죽고 OrbStack이 내려간다 — 비운 뒤 `orb start`(MC 중에 한 번).
- 부팅 없이 1분에 보는 검사는 `make quick`(`quick_check.sh`) — shellcheck(note까지) · Zig fmt · ast-check · shared · init 빌드. 호스트
  Zig는 `/opt/homebrew/bin/zig`(0.17). init의 `zig build test`는 macOS에서 안 끝난다 — 컨테이너에서 돌린다(BT-M1에서 다시 겪었다).
  push마다 CI(`checks.yml`)가 같은 것과 컨테이너 안 `zig build test`를 돌리고 README 배지가 그 결과다. 빨강이 `sha256sum` ·
  `curl`이면 우리 코드가 아니다 — `gh run rerun`.
- 새로 받은 저장소는 `make container`가 이미지를 ghcr.io에서 받는다(1.5GB, 없거나 오프라인이면 Dockerfile로 굽는다 — GI-M0).
  첫 빌드가 linux-firmware 662MB를 `kernel/src/firmware/`에 받고 `clean()`이 지우지 않는다. `terminal/prepare.sh`가
  `stb_image.h`도 받는다(`terminal/vendor/`, 커밋 안 함).
- `shared/`는 init과 terminal이 함께 컴파일하는 파일의 자리다. 순수해야 한다(libc · 로그 없음) — init이 libc를 안 링크한다.
  그 파일을 고치면 두 빌드가 다시 돈다(`zig build --summary all`로 보인다).
- initrd는 두 archive다. `gzip -dc initrd.cpio | cpio -it`에 firmware가 안 나온다(measurements 62). 그 파이프라인을 `if` 안에 두면
  pipefail이 gzip의 EPIPE를 거짓 빨강으로 올린다(BT-M2 체인의 첫 판) — 파일에 받고 따로 본다.
- 이 저장소의 셸 작업은 zsh다. `"$n:lib"`처럼 `$var` 뒤에 `:`가 오면 수식어로 읽혀 글자가 깨진다 — `${n}:lib`(BT-M0 실측 2).
- 실칩 무선 · 블루투스는 PCIe도 USB도 아직 한 번도 안 떴다. 실기와 실제 장치가 생기면 그것이 새 사실이다.
- 세션 문서(HANDOFF · MEMORY · `docs/guides` · `docs/decisions`)의 중복을 2026-11-01에 걷어냈다 — 사실 하나는 한 자리에 두고 나머지는
  포인터다. 닫은 서브프로젝트의 경과를 HANDOFF에 다시 쌓지 않는다. 문서 속 줄 번호 · 배열 길이는 낡으니 인용하기 전에 코드에서 다시 본다.
