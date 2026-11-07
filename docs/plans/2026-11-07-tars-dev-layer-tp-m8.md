# TP-M8 — 터미널 유틸리티(util)와 여덟째 묶음 media

> 2026-11-07, `24b8fc4` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: design "터미널 유틸리티" 표를 싣는다(사용자 결정 2026-11-06 — M7 편집기, M8 터미널 유틸리티, M9 문서). 대부분은 TP-M5가 연 `util` 묶음에 더하고,
미디어 셋(ffmpeg · ImageMagick · GraphicsMagick)은 새 묶음 `media`로 가른다. 판정은 묶음마다의 것 — 망 없이 도구가 서고 일을 한다.

사용자 결정(2026-11-07, 조사를 단계별로 보고):
- 뺀다: cloudflared, pandoc, pillow, tree, gron, jless, lisette. 그리고 hunk(확인 4 · 10 — util의 25%를 혼자 차지한다. difftastic과 util의 glc가 diff를 맡는다.
  필요하면 망이 있을 때 `npm i -g hunkdiff`).
- vifm은 Debian 0.14(AppImage 장치를 만들지 않는다).
- ffmpeg를 더하고, ImageMagick · GraphicsMagick 둘 다와 함께 새 묶음 `media`에 둔다(확인 6 · 7).
- DuckDB를 더한다 — 1.5.6(확인 11. 2.0.0 CLI는 x86-64-v3로 빌드돼 에어 2011에서 서지 않는다).
- 셸 alias: `lt='eza -ls modified'`, `ltt='eza -ls changed'`(tree를 빼며 — `24b8fc4`로 따로 커밋했다).

## 착수 전 확인 (2026-11-07)

판 · sha256은 GitHub `releases` API, 받기는 호스트, 풀기 · 실행은 amd64 trixie-slim(`--network none`, 사용자 `tars`).

1. 판과 자산(upstream 42개 — sqlite 포함, hunk는 뺐다. DuckDB는 확인 11). gnu와 musl이 둘 다 있으면 gnu(맡아 정한 것 1). 받은 GitHub 자산 44개(AppImage 둘 포함)가 모두 `digest`의 sha256과 맞았다 — util에 남는 것은 그중 41개와 sqlite.

   | 모양 | 도구 (판 — 자산) |
   |---|---|
   | 맨 위 디렉터리 하나 | bat 0.26.1 · fd 10.5.1 · hyperfine 2.0.0 · sd 1.1.0 · dust 1.2.7(모두 `-x86_64-unknown-linux-gnu.tar.gz`), ripgrep 15.2.0 · dua 3.0.0 · xh 0.26.3(`-musl` — gnu가 없다), bed 0.2.9, glow 3.0.0, hexyl 0.17.0, hurl 8.1.0, miller 6.22.0, uv 0.13.7, wasmtime 50.0.1(`.tar.xz`), yazi 26.9.1(zip), fastfetch 2.71.0(`usr/bin/`) |
   | 디렉터리 없음(`strip=0`) | duf 0.9.1 · fzf 0.74.5 · cidr 2.3.0 · gdu 5.39.0(`_static`) · gitui 0.28.1 · go-task 3.54.0 · gping 1.21.0 · hugo extended 0.169.0 · lazygit 0.66.2 · lazysql 0.7.0 · peco 0.6.0 · scc 4.1.0 · starship 1.27.0 · viddy 1.3.1 · difftastic 0.72.0 · tailspin 7.0.0(musl) · eza 0.23.5 · procs 0.14.12(zip) · tree-sitter-cli 0.27.1(zip) · ast-grep 0.51.1(zip) · sqlite 3.54.1(zip) |
   | 압축 없는 실행 파일 하나(TP-M7 결정 D) | jq 1.8.2 · asciinema 3.2.1 · herdr 0.9.5 · leaf 1.29.2 |

   - sd의 v1.1.0 자산이 `sd 1.0.0`을 찍는다 — upstream이 판 문자열을 안 올렸다. 파일은 v1.1.0 자산이 맞다.
   - sqlite.org의 해시는 SHA3-256이다. 받은 파일을 SHA3로 대조한 뒤(맞았다) 그 파일의 sha256을 매니페스트에 적는다.
   - gdu의 실행 파일 이름이 `gdu_linux_amd64_static`이다(결정 C).
   - ast-grep은 `ast-grep`과 `sg`를 싣는다. `sg`는 리눅스에서 shadow의 명령 이름이다 — `ast-grep`만 링크한다.
2. ELF: 동적인 것의 가장 높은 요구가 GLIBC_2.39(gping · tree-sitter · yazi) — trixie 2.41 아래다. 나머지는 Go · musl 정적. 절대 prefix는 없고, 절대 RUNPATH는
   sqlite3의 `/usr/local/lib` 하나다(그 자리에 없으면 기본 자리의 libz — 해가 없다. 다만 root가 쓰는 층이 그 앞에 온다). `%ymm`은 거의 모두에 있다 — Go · Rust
   런타임과 memchr식 실행 중 고르기(TP-M7 확인 2 · 5와 같은 꼴). 실기 확인으로 남긴다.
3. 망 없이 `--version`: 41개가 섰다. hurl · hurlfmt만 `libxml2.so.2`(그리고 `libcurl.so.4` — initrd는 `libcurl-gnutls`만)가 없어 멈췄다(결정 B).
4. hunk(뒤에 뺐다 — 사실은 남긴다): npm 패키지 `hunkdiff`의 `optionalDependencies`가 `hunkdiff-linux-x64` — 결국 같은 실행 파일이다. npm 장치는 필요 없다. 실행 파일은 bun 1.4.4 런타임에
   JS를 붙인 것(184MiB). bun 1.4.4의 `bun-linux-x64-baseline.zip`과 `bun-linux-x64.zip`의 `bun`이 sha256까지 같다(`10702245…`) — 이 판에는 baseline 구분이
   없다. 그러니 hunk의 CPU 수준은 lang-script의 bun과 같다(TP-M3 확인 8에 덧붙일 사실).
5. AppImage: imagemagick 7.1.2-35는 `--appimage-extract`가 FUSE 없이 되지만, `magick`이 `libX11` · `libfontconfig` · `libfreetype` · `libfribidi` · `libharfbuzz`를
   시스템에서 찾는다(데스크톱 전제), `AppRun`이 `LD_LIBRARY_PATH`로 자기 `usr/lib`(Ubuntu 22.04 판)를 앞세운다. vifm 0.14.5는 풀면 바로 선다. 둘 다 design의
   "안 되면 debian"으로 — vifm은 사용자 결정, 이미지 도구는 확인 7.
6. ffmpeg(사용자가 더했다). FFmpeg는 바이너리를 내지 않는다. 공식 다운로드 페이지가 링크하는 리눅스 빌드 둘:

   | 출처 | 판 | 풀린 크기 | 의존 | `--enable-*` |
   |---|---|---|---|---|
   | BtbN `linux64-gpl-shared-9.0` | 9.0.2-39 | 234MiB(`lib/` 191) | glibc(2.28) — `$ORIGIN/../lib` | 79 |
   | BtbN `linux64-gpl-9.0`(정적) | 같음 | 517MiB(실행 파일 셋이 각 166MiB) | glibc | 78 |
   | johnvansickle | 7.0.2(2024)에서 멈춤 | | | |
   | Debian trixie `ffmpeg` | 7.1.5 | 패키지 207, 445MiB | X11 · GL · Vulkan · Pulse · SDL 등 29 | 68 |

   - BtbN은 날마다의 `autobuild-*`를 약 2주 뒤 지우고 월말 것은 남긴다(2024-12-31부터 모두 있다) — 월말 태그 `autobuild-2026-10-31-12-59`에 고정한다.
   - 공유 빌드로 망 없이: H.264+AAC 5초 인코딩 → `ffprobe`(duration 5.000000), AV1(SVT)+Opus 변환, PNG 한 장 — 모두 섰다. SVT-AV1이 `asm level on system : up to avx2`를
     찍는다 — 실행 중 고르기다.
7. ImageMagick 대 GraphicsMagick(둘 다 Debian trixie, `--no-install-recommends`).
   - IM 7.1.1-43(`deb13u14`): 더해지는 패키지 45, 약 43MiB, 명령 9(`magick` · `convert` · `identify` …). GM 1.3.45(`1.4+really1.3.45`, 2025-03 스냅숏): 30, 약 34MiB, `gm` 하나.
     함께 쓰는 패키지 25. IM만: fontconfig · DejaVu · glib · fftw3 · liblqr · libraw · openjp2 등 20, GM만: libjxl · libhwy · libwmflite 등 5.
   - 성능(OrbStack amd64, 10코어, 4000×3000, hyperfine — 상대 비교로만): 줄이기 IM 2.70초 · GM 2.31초, PNG → JPEG 2.42 · 2.07, `-blur 0x4` 17.2 · 10.4, `identify` 64 · 63ms.
     스레드 하나로도 같은 경향(GM 12~38% 빠름). GM이 메모리를 25~30% 더 쓴다. `mogrify` 20장은 hyperfine `-N`(셸 없음)이 `&&` · 글롭을 펴지 않아 재지 못했다.
   - 보안: IM은 2026년에도 Debian 공지가 이어진다(DSA-6310-1 · DSA-6356-1 · DLA-4680-1). GM upstream은 1.3.46(2025-10, CVE 셋) · 1.3.47을 냈고 trixie는 1.3.45다
     (backport 여부는 확인하지 않았다).
8. 셸 완성: 12개 도구가 완성 파일을 싣는다(bat · fd · hyperfine `autocomplete/`, glow · hurl · sd · xh · yazi `completions/`, ripgrep `complete/`, go-task, fastfetch는 표준 자리).
   initrd의 zsh는 Completion 트리(`/usr/share/zsh`, 17MB)를 싣지 않고 `compinit`도 부르지 않는다(`kernel/make_initrd.sh`의 주석), bash에는 `bash-completion`이 없다 —
   이을 자리가 없다(맡아 정한 것 3).
9. man: 13개가 싣는다. 대부분 `*.1`, glow(`manpages/glow.1.gz`) · hurl(`man/man1/*.1.gz`)은 gz(결정 D).
10. 크기(도구마다 `tar | zstd -15`로 잰 값, MiB 아래 버림): upstream 43개가 풀면 919MiB, zstd15 234MiB. hunk 59(bun 런타임을 품었다 — 25%) · hugo 18 · wasmtime 13 ·
    uv 13 · go-task 13 · yazi 11 · herdr 8, 나머지 36개가 105. difftastic(87 → 7) · ast-grep(54 → 6)은 tree-sitter 문법 표라 잘 준다. 처음 어림(풀면 760, zstd 300~350)은
    양쪽으로 틀렸다. hunk를 빼고 DuckDB(17)를 더하면 util 약 192MiB(+ debian 다섯 줄 몇 MiB), media 90~110MiB — ISO는 1.51GB에서 약 1.8GB.

11. DuckDB(사용자가 더했다, "2.0 이상" 검토). 2.0.0(2026-10-21) CLI `duckdb-cli-linux-amd64.tar.gz`(74MiB, glibc 2.25 · libstdc++)는 함수 73,757개 가운데 14,901개(20%)에
    `%ymm`, AVX2 정수 명령 96,765 · FMA 1,025 — `VectorOperations::Hash` 등 모든 GROUP BY가 지나는 길이다. 릴리스 노트의 PR #24391 "Try -march x86-64-v3 for CLI and
    v2 for extensions"가 이유다. musl판도 같다(16%). 1.5.6 · 1.4.5(LTS)는 `%ymm` 0. 에어 2011(SandyBridge)에는 AVX2가 없다 — TCG · OrbStack은 그것을 실행해 버려
    체인으로 못 잡는다. 사용자 결정: 1.5.6.
    - 1.5.6 `duckdb_cli-linux-amd64.zip`(21,294,383, sha256 `6e89deac…` — GitHub `digest`와 맞다), 안에 `duckdb` 하나(디렉터리 없음), 59MiB, zstd15 17MiB.
    - 내장 확장은 autocomplete · core_functions · icu · json · parquet · shell. 망 없이 CSV → Parquet → JSON 왕복과 `sum` = 6. 나머지(fts · excel · spatial …)는 첫 사용에
      `extensions.duckdb.org`에서 받는다 — 망 없으면 `Failed to download extension`(비목표 6).

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. util에 upstream 43줄(확인 1의 표, sqlite 포함, DuckDB 1.5.6 — `strip=0`)과 `debian` 다섯 줄 — `wget` 1.25.0-2, `ipcalc` 0.51-1, `vifm` 0.14-3, `libxml2` · `libcurl4t64`(hurl의 NEEDED, 결정 B).
   initrd에 trixie 판이 있는 아홉(bat · duf · eza · fd · fzf · hyperfine · jq · ripgrep · sd)은 `/usr/local/bin`이 앞서 최신판이 돈다(design 결정 20).
B. hurl의 라이브러리는 같은 묶음의 `debian` 줄이다 — verify의 NEEDED(결정 5)가 묶음 안 `usr/lib/x86_64-linux-gnu`에서 찾는다.
C. `exe=`의 항목이 `rel:이름`이면 `/usr/local/bin/이름`으로 링크한다(gdu — `exe=gdu_linux_amd64_static:gdu`). 키는 늘리지 않는다(다섯 — 한도). `:`가 없으면 지금대로
   `basename`. 이름에 `/`가 있으면 멈춘다.
D. `man1=D`가 `D/*.1`과 `D/*.1.gz`를 함께 링크한다(glow · hurl). 둘 다 없으면 지금처럼 멈춘다.
E. 새 묶음 `media`(design 결정 7의 나누기): ffmpeg(upstream, BtbN 공유 빌드, `exe=bin/ffmpeg,bin/ffprobe` — `ffplay`는 화면이 없어 링크하지 않는다, `man1=man/man1`),
   `imagemagick` · `graphicsmagick`(debian). 이름 순이라 lowerdir는 `… lang-script media util`. `DEV_LAYERS` · 체인의 `LAYERS` · `ISO_LAYERS`에 넣는다.
   체인의 묶음 수는 여덟(부팅 3은 일곱).
F. 체인: devtools 부팅 2에 더한다(망 없이, 사용자로, `~/tp/m8`). 기다리는 글자는 계산된 값이다(TP-M4 확인 9).
   1. util 전부: 링크된 실행 파일 목록을 돌며 `--version`(go-task `task --version`, sqlite3 `-version` 등 각자)이 0으로 끝난 수 — 목록의 길이와 같아야 한다.
      `command -v rg`가 `/usr/local/bin/rg`이고 `rg --version`이 15.2.0(initrd 판을 이겼다).
   2. 일하는 덩이: `jq '.a|add'`, `sqlite3 :memory: 'select 6*7'`, `mlr --icsv --ojson`, `difft` 두 파일의 바뀐 줄, `ast-grep run -p` 한 패턴, `hyperfine -r 2 true`의 끝 줄,
      `hurl --version`의 `libcurl`(라이브러리 링크), `uv --version`, `duckdb`의 CSV → Parquet → JSON 왕복과 `sum`.
   3. media: `ffmpeg -f lavfi` 3초 H.264 → `ffprobe`의 duration, `magick` PNG → JPEG → `magick identify`의 크기, `gm identify`의 같은 크기.
   4. man: `man rg`(`.1`), `man hurl`(`.1.gz`).
   상한은 처음 하나에 120초, 잰 뒤 세 배(60초 아래로는 안 내린다). 부팅 3(lang-jvm이 깨진 판)에 `rg --version` 한 줄 — util이 맨 끝 자리라 깨진 묶음이 그 앞에 있어도 선다.

## Claude가 맡아 정한 것 (뒤집을 것이 있으면 글자로)

1. gnu와 musl이 둘 다 있으면 gnu — 다른 묶음과 같은 glibc 위, musl 기본 할당자의 느림을 피한다. musl뿐인 넷(ripgrep · dua · xh · tailspin)은 musl.
2. hugo는 extended(SCSS — design 표 그대로), `withdeploy`는 뺀다(클라우드 배포 기능, 망 전제).
3. 셸 완성은 싣기만 하고 잇지 않는다(TP-M7 맡아 정한 것 3을 잇는다). 이으려면 zsh `compinit`과 Completion 트리 · `bash-completion`부터 세워야 한다 — 셸 전체의 기능이라
   `carryover.md`로 넘긴다(TCG에서 `compinit`이 셸 시작을 얼마나 늦추는지도 함께 재야 한다).
4. ffmpeg는 9.0(최신 릴리스 브랜치), master는 쓰지 않는다. gpl 빌드(x264 · x265 — 이미 싣는 Debian GPL 도구와 같은 처지).
5. 체인 F-1의 목록은 매니페스트에서 계산하지 않고 체인에 적는다 — 도구를 더하거나 뺄 때 체인도 고쳐야 한다는 것이 판정의 일부다.

## 할 일

1. 매니페스트: util 43 + debian 5, media 3. 지금 `# ── util` 머리 주석을 고친다.
2. `devlayer/build.sh`: 결정 C(`rel:이름`) · D(`.1.gz`).
3. media를 잇는 자리: `Makefile`의 `DEV_LAYERS`, `devtools/check.sh`의 빌드 줄 · `LAYERS` · lowerdir · 묶음 수, `rg -n 'lang-script util'`로 한 번 더.
4. `make dev-layers` — 숫자: util · media의 풀린 크기 · zstd, harvest 패키지 수, NEEDED, 묶음 사이 `shared`.
5. chroot로 결정 F의 덩이를 먼저.
6. 빨강: (a) gdu의 `:gdu`를 빼면 `/usr/local/bin/gdu`가 없어 F-1의 수가 하나 모자란다(또는 `gdu --version`이 없다). (b) 결정 D를 되돌리면 glow 줄이 `has no *.1`로 굽기에서 멈춘다.
7. 체인 혼자 한 번, 숫자로 상한을 고친다.
8. `make quick`, 루트 게이트. design(터미널 유틸리티 표 · 뺀 것 · 묶음 표에 media · 결정 1의 `exe=` · `man1=`), `carryover.md`(셸 완성), HANDOFF.

## 판정

- `make dev-layers`가 초록이고, util · media의 NEEDED · 겹침 · 묶음 사이 검사가 지난다.
- 체인의 부팅 2에서 결정 F의 네 덩이가 망 없이 사용자로 돈다. 할 일 6의 빨강 (a) · (b)를 봤다.
- 루트 게이트 초록, 잘린 줄 0.

## 비목표

1. 셸 완성(맡아 정한 것 3).
2. TUI 도구(lazygit · gitui · yazi · lazysql · herdr · bed · vifm · peco · viddy · gdu의 화면)의 상호작용 — 체인은 `--version`까지. 실기에서 본다.
3. 망이 있어야 하는 기능(hurl · xh의 실제 요청, uv의 패키지 받기, hugo의 모듈, asciinema 업로드).
4. ffmpeg의 하드웨어 가속(VAAPI · Vulkan · CUDA) · `ffplay`(화면 출력).
5. GitHub release의 2GiB 한도 해결(`project_release_0_2.md`의 사용자 결정 대기 — 위험 1).
6. DuckDB의 내장 밖 확장 시드(필요해지면 clojure `~/.m2`꼴 — 확인 11).

## 위험

1. ISO가 약 1.8GB로 2GiB(2.147GB)까지 약 300MB 남는다 — M9(docset) · 서버 · AI가 넘긴다. 게이트와 로컬 ISO는 그대로 돈다 — 한도는 release에 올릴 때의 문제다. media를 따로 둔 것이 그때 떼어 낼 단위다.
2. `%ymm` — 대부분이 실행 중 고르기로 보이지만 에어 2011의 실기 확인으로 남긴다(TCG는 CPUID에 없는 AVX2도 실행한다 — TP-M3 확인 8).
3. 체인 시간이 1~2분 늘고 lane-0도 그만큼 는다(묶음 복사 1,302MiB → 약 1.7GiB).
4. media의 Debian 줄(IM · GM)이 util의 Debian 줄(libxml2 등)과 같은 경로를 들고 온다 — 같은 날 같은 미러라 내용이 같아야 하고, 어긋나면 묶음 사이 대조가 이름을 대고 멈춘다.
5. initrd의 trixie 판과 util의 최신판이 다르게 동작하는 자리(eza의 출력, fzf의 `--zsh`) — 묶음이 얹힌 부팅에서만이다. 게이트가 치는 셸 체인들은 묶음 없는 ISO라 영향이 없다.

## 확인한 것

(구현 뒤 채운다)

## 결과

(구현 뒤 채운다)
