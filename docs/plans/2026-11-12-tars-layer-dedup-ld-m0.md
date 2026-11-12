# LD-M0 — 묶음 사이 중복 지우기 · emacs 빼기 · fakesteak을 기본 판에

Date: 2026-11-12
Design: `docs/specs/2026-11-12-tars-layer-dedup-design.md`
Status: 끝났다(2026-11-12).

## 착수 전에 확정한 것

design의 확인 1~8과 결정 1~6. 결정은 lead에게 맡겨졌다(사용자 2026-11-12 — 운전 중). ghostty vt-1.0.1(GU-M0)은 이미 들어 있다.

## Task 1 — 지우기 (commit 하나: 결정 1 · 2 · 3)

1. `devlayer/standalone-bundles`: 머리 주석과 `fakesteak` 한 줄. 읽는 쪽은 `#`와 빈 줄을 건너뛴다.
2. `devlayer/build.sh`: "묶음끼리의 대조" 뒤, stamp 앞에 "base와 같은 것 지우기" 절.
   - 대상: `bundle != base`이고 standalone 목록에 없을 때. `${build}/base.paths`가 없으면 `die`.
   - `LC_ALL=C join -t $'\t' "${work}/${bundle}.paths" "${build}/base.paths"`에서 `$2 == $3`인 경로 → `${work}/${bundle}.dedup`.
     파일을 거친다(`awk | grep -q`의 SIGPIPE — 위 절의 주석).
   - 그 경로들을 `${root}`에서 `rm -f`(링크도 `rm -f`가 링크를 지운다). 빈 디렉터리는 둔다.
   - `files` · `bytes`를 지운 뒤에 다시 센다. stamp에 `cat "${work}/${bundle}.dedup"`(없으면 빈 것)을 더한다.
   - 요약 줄 끝에 `deduped=N`. 머리 주석(13~15줄)의 stamp 설명에 "base와 겹쳐 지운 목록"을 더한다.
3. `boot/make_iso.sh`: `ISO_LAYERS`를 싣기 전에 — base도 standalone도 아닌 묶음이 있는데 base가 없으면 `make_iso: <묶음> leans on base;
   add base to ISO_LAYERS`로 멈춘다. 목록 파일은 `../devlayer/standalone-bundles`(make_iso는 `boot/`에서 돈다).
4. `init/src/layers.zig`: `pub fn baseIndex(list: *const List) ?usize`(이름이 정확히 `base`인 칸). `mountAll`은 붙이기 루프 전에 base가
   있으면 그것부터 `mountOne`, 실패하면 design 결정 2의 줄을 찍고 return. 루프는 base 칸을 건너뛰고 `up`에는 이름 순서대로 넣는다
   (base의 성공을 먼저 알고 루프에서 그 자리에 넣는다). 모듈 머리 주석에 LD-M0 한 줄.
5. `init/src/layers_test.zig`: `baseIndex` — base가 있을 때 그 칸, 없을 때 null, `base-x`처럼 비슷한 이름은 아니다. 기존 scan 시험과 같은
   가짜 디렉터리를 쓴다.
6. 검사: init `zig build test`(컨테이너), `make quick`. 그다음 `make dev-layers`로 열하나를 굽고(모두 baked — `build.sh` 해시가 바뀌었다) 요약 줄의
   `deduped=`가 design 확인 2 · 3의 묶음에 나오는지, base · fakesteak은 0인지(fakesteak은 `make dev-layers DEV_LAYERS=fakesteak`로 따로).
   `make_iso.sh`의 멈춤은 `ISO_LAYERS="editor"`로 한 번 본다.

## Task 2 — emacs 빼기 (commit 하나: 결정 4)

1. `manifest.toml`: emacs-nox 줄(머리 주석 포함)을 지우고 editor 머리 주석을 "mitos · neovim · ttt"로.
2. `devtools/check.sh`: 14줄 주석, 508줄 주석의 emacs, 525~530줄의 emacs 덩어리를 `command -v emacs` 확인(`tp-m7-noemacs=0`)으로, 538줄의
   `man emacs` · 541줄 · 542줄 문구, 543줄 `M7_NUMBERS`의 emacs.
3. `docs/help/devtools.md`의 editor 줄.
4. 지우는 줄은 `git diff | rg '^-'`로 그 자리만인지 본다.

## Task 3 — fakesteak을 기본 판에 (commit 하나: 결정 5)

처음 판(util에 같은 줄)은 `make quick`의 manifest 검사(`tool fakesteak again`)에 막혀 design 결정 5를 고쳤다(구현 중, 2026-11-12).

1. 조각 둘(`devlayer/files/fakesteak/etc/tars/rc.d/fakesteak.sh` · `fish/conf.d/90-fakesteak.fish`)에 `/usr/share/tars/layers/base`가 없을 때만.
2. `Makefile`의 `DEV_LAYERS` 기본값 · 도움말 글, manifest의 데모 묶음 머리 주석.
3. `devtools/check.sh`: 짓는 ISO의 `ISO_LAYERS`, `LAYERS`(이름 순 — editor 다음), 묶음 수 11 → 12(설치 · overlay · 갱신 줄과 주석),
   `command -v fakesteak`이 `/usr/local/bin/fakesteak`이고 `/tmp/.tars-autorun`이 없다는 줄.
4. `docs/help/devtools.md`의 표에 fakesteak 줄. `layers.MAX`(16)는 넉넉하다.

## Task 4 — 검사와 게이트

1. `make check CHAIN=devtools`(묶음을 다 굽는다 — 실행 전에 알린다). `out/tars-dev.iso` 크기를 지금(design 기준 판의 0.2.1 기본 판
   2,144,473,088 B와 같은 묶음 구성)과 비교한다.
2. 루트 게이트 `make gate`(33체인, 지난 판 35분 33초 — 이번엔 prebuild가 묶음을 다시 구워 더 길다).
3. 빨강이 나오면: devtools면 `B2` 줄 — 지운 파일 때문에 못 찾는 라이브러리 · 데이터인지(그러면 결정 1의 대상에서 그 경로를 다시 보거나 그
   묶음의 verify 기준을 고친다), 다른 체인이면 그 로그부터.

## Task 5 — 닫기

plan 결과 절, design Status, `completed.md` 한 행, `carryover.md`의 "묶음 사이 같은 파일 지우기" 체크, 기억 하나(`project_layer_dedup`)와
`MEMORY.md`, `project_release`의 배포 절차 3(기본 판의 묶음 · fakesteak 데모 판 그대로), HANDOFF. 소개 페이지는 다음 판을 낼 때.
docker volume `tars-dedup-survey`(조사용 풀린 묶음)를 지운다.

## 결과

commit: `d6cd805`(지우기 · init) · `46b246d`(emacs) · `a59f39e`(fakesteak) · `7ee5257` · `92394ac` · `a390daa`(체인의 묶음 수 · 목록). plan과 다른 자리는 둘.

1. Task 3: util에 같은 도구 줄을 두는 처음 판이 `make quick`의 `tool fakesteak again`에 막혔다 — design 결정 5를 "fakesteak 묶음을 기본 판에도,
   자동 실행은 `/usr/share/tars/layers/base`가 없을 때만"으로 고쳤다(design에 경위). 그래서 묶음이 열둘이 되었다.
2. Task 4: devtools 체인이 두 번 빨갰다 — 둘 다 체인에 박힌 묶음 목록 · 수였다(lowerdir 글자에 fakesteak, 부팅 3의 `from 10` → `from 11`).
   묶음이나 init의 잘못은 아니었다. 셋째 판 PASS(빌드 뒤 722초).
3. 굽기(`make dev-layers`, 모두 baked): `deduped=` container 286 · docs 289 · lang-script 1,148 · media 367 · server 3,196 · util 299, base ·
   lang-beam · lang-jvm · lang-native · fakesteak 0. editor는 emacs가 빠져 `zstd15=47MiB`(design 확인 4의 47.3과 같다). 같은 경로에 다른 내용은
   여전히 0(대조가 멈추지 않았다). `deduped`는 링크를 함께 세어 design 확인 2의 파일 수와 다르다.
4. 크기: `tars-install`이 옮긴 묶음 열둘 1,762MiB(앞 판 열하나 1,908MiB, −146 — design 예상 145.7). 묶음 열둘을 실은 `out/tars-dev.iso`
   1,992,007,680 B — 0.2.1 기본 판 2,144,473,088 B보다 145.4MiB 작고 2GiB까지 148MiB.
5. 체인이 본 것: server(postgres · mysql — base의 perl과 라이브러리에 기댄다) · container(Docker) · 서비스 끄기가 그대로, `emacs`가 없다,
   `fakesteak`이 `/usr/local/bin`에 있고 `/tmp/.tars-autorun`이 안 생겼다, 부팅 3(lang-jvm 깨짐)에서 나머지 열하나로 돈다, 갱신이 열둘을 지우고 다시.
   `make iso ISO_LAYERS="editor"`는 `make_iso: editor leans on base; add base to ISO_LAYERS`로 멈췄다.
6. 루트 게이트 33/33 첫 판 PASS(36분 13초 — prebuild 376초 + lanes 1,653초, 회차 33개 모두 `cut log lines A=0 B=0 C=0`,
   `out/gate-logs/20261112-110630`). devtools 905초.
7. 안 본 것: base가 깨진 부팅(design 결정 2)은 체인에 없다 — `carryover.md`의 LD 절.
