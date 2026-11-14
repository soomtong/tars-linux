# OD-M0 — odin을 lang-native에

Date: 2026-11-14
Design: `docs/specs/2026-11-14-tars-odin-design.md`
Status: 끝났다(2026-11-14). commit `c07e944`(odin) · `0a0363e`(rust 1.100.0) · `e0cb758`(`make iso-full`).

## 착수 전에 확정한 것

design의 확인 1~4와 결정 1~3. 사용자: "이제 odin을 native lang에 그대로 포함해보자"(2026-11-14).

## Task 1 — 묶음 (commit 하나)

1. `devlayer/hooks/odin.sh`: `odin.sh <tarball> <뿌리> <도구 디렉터리>`(다른 hook과 같은 인자). 임시 디렉터리에 풀고, 맨 위가 디렉터리
   하나인지, 그 안의 목록이 `LICENSE base core examples odin shared vendor`인지 보고(다르면 멈춘다), 도구 디렉터리로 `cp -a`. `bin/odin`
   런처(0755)를 쓴다 — `ODIN_CLANG_PATH`가 비면 `gcc`, `exec -a odin /<도구 디렉터리>/odin "$@"`.
2. `devlayer/manifest.toml`: lang-native 머리 주석에서 odin을 "뺐다"에서 지우고(LLVM · tcc는 그대로), go 줄 뒤에 odin 줄
   (`kind = "upstream"`, `version = "dev-2026-11a"`, url · sha256, `hook = "odin"`). 주석 한 줄에 런처의 까닭.
3. 검사: `make quick`(매니페스트 생성기 · shellcheck), `make dev-layers DEV_LAYERS=lang-native`로 굽고 요약 줄의 파일 수 · 크기를 적는다.
   묶음 안에 `/usr/local/bin/odin` → `../lib/odin-dev-2026-11a/bin/odin` 링크와 런처 내용을 `unsquashfs -l` · `-cat`으로 본다.

## Task 2 — 체인과 문서 (같은 commit)

1. `devtools/check.sh`: 머리 주석에 OD-M0 한 줄, 부팅 2 설명에 odin. zig 덩어리 뒤에 odin 덩어리 — `~/tp/od/main.odin`
   (`fmt.println("tp-odin-" + ODIN_VERSION)`이 아니라 `fmt.printf("tp-odin-%s\n", ODIN_VERSION)` — 문자열 결합은 상수끼리만이라도 피한다),
   `odin run .` 시간 `tp-ms-odin`, 기다리는 글자 `tp-odin-dev-2026-11`. 실패 문구는 "odin did not build and run a program with gcc as its
   linker (the odin launcher sets ODIN_CLANG_PATH)". `NUMBERS`에 odin.
2. `docs/help/devtools.md`: lang-native 줄에 odin.
3. TP design: 도구 목록 표의 네이티브 언어 줄에 odin(OD-M0), "뺀 것"에서 odin을 지우고 한 줄로 OD design을 가리킨다.
4. `docs/guides/measurements.md` 104의 끝 문장: "비워 두기로 했다"를 "같은 날 다시 싣기로 했다(OD-M0)"로.
5. 검사: `make quick`, 그다음 `make check CHAIN=devtools`(15~20분 어림 — TP-M9 때 713초, 그 뒤 묶음이 늘었다). 결과 절에 odin의 ms와
   다른 숫자의 변화.

## Task 3 — rust 1.100.0 (commit 따로, 같은 체인)

사용자(2026-11-14): "rust 1.100 업그레이드 함께 진행하세요." `channel-rust-stable.toml`(date 2026-11-12)의 xz_hash.

1. `devlayer/manifest.toml`: rust · rust-src를 1.100.0(`dist/2026-11-12/`)으로. 판이 박힌 다른 자리 — `docs/help/devtools.md` ·
   `docs/guides/running-tars.md`의 rust 문서 경로, `devlayer/hooks/rust-installer.sh` 주석의 예.
2. 검사: `make dev-layers DEV_LAYERS=lang-native` — hook의 컴포넌트 목록과 `libLLVM` 상대 링크가 새 판에서도 서는가. 체인은 Task 2의
   `make check CHAIN=devtools` 하나로 함께 본다(rustc · cargo hello).

## Task 4 — `make iso-full` (commit 따로)

사용자(2026-11-14): "make에 full version iso를 빌드하는 단일 명령 추가." design "배포"의 로컬 판.

1. `Makefile`: `iso-full: initrd` — recipe가 `$(MAKE) dev-layers`(묶음 전부) 뒤 `make_iso.sh`를 `ISO_LAYERS="$(DEV_LAYERS)"`,
   `ISO_OUT="../$(FULL_ISO)"`(기본 `out/tars-full.iso`)로 부르고 크기를 찍는다. 2GiB를 넘으면 한 줄로 알린다. `help`에 한 절, `.PHONY`.
2. 검사: `make -n iso-full`의 순서, `make help`. 실제 빌드는 devtools 체인이 끝난 뒤(같은 컨테이너 · `out/`을 쓴다).

## 결과

1. 첫 `make dev-layers DEV_LAYERS=lang-native`가 verify에서 멈췄다 — odin `vendor/raylib`의 미리 빌드된 `.so` 둘:
   `linux/libraylib.so.620 needs libX11.so.6`, `linux-arm64/libraylib.so.620 needs ld-linux-aarch64.so.1 · libX11.so.6`. 빼지 않고
   `needed-ignore.tsv`에 두 줄 — 앞의 것은 이유 `GUI`(TP 비목표 5), 뒤의 것은 다섯째 이유 `foreign-arch`(x86_64의 ld.so가 적재하지
   않는 다른 아키텍처의 ELF)를 새로 만들었다. 다시 구운 판 `unresolved=0 ignored=4`.
2. 묶음 `lang-native.sqfs`: 422,088,704 → 490,737,664 B(odin, +65.5MiB — `measurements.md` 104의 어림 그대로) → 493,031,424 B(rust 1.100.0,
   +2.2MiB). 파일 108,071, 풀린 2,277MiB, zstd15 470MiB. 묶음 안 `/usr/local/bin/odin -> ../lib/odin-dev-2026-11a/bin/odin`, 런처 240 B.
3. rust 1.100.0: 설치기 컴포넌트가 1.99.1과 같은 일곱, `libLLVM.so.23.1-rust-1.100.0-stable` 상대 링크도 같은 자리 — hook은 그대로.
4. 체인 `devtools` PASS(빌드 뒤 754초 — 첫 판은 사용자가 백그라운드를 실수로 멈춰 굽기에서 끊겼고 둘째 판이 rust까지 담았다).
   `B2: as tars, odin run built and ran a program through gcc (11094ms)`, rustc 5,099 · cargo 1,664ms(1.99.1 때 4.8 · 1.5초), 묶음 열셋
   1,898MiB. odin의 상한은 첫 숫자로 60초(세 배가 60초 아래). 체인 ISO 2,135,390,208 B — 2GiB까지 약 11.5MiB.
5. `make iso-full`: 5분 47초(묶음 캐시), `out/tars-full.iso` 2,135,388,160 B, 묶음 13개 — 2GiB 아래라 경고 줄은 안 나왔다.
6. 루트 게이트는 이 milestone에서 따로 돌리지 않았다 — 0.2.2의 `VERSION` commit에서 돈다(기억 `project_release` 절차 1).
