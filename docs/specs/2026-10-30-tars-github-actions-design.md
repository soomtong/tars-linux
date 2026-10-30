# TARS GitHub Actions — Design

Date: 2026-10-30
Status: 열려 있다 — GH-M0 plan은 `docs/plans/2026-10-30-tars-github-actions-gh-m0.md`(design 뒤에 쓴다).

HANDOFF "다음 후보"의 (5)에서 시작한다(2026-10-24 프로젝트 점검이 남긴 다섯 가운데 마지막. (3)은 HC, (4)는 LS로 닫았다.
사용자가 2026-10-30에 골랐다).

> `.github`가 없다 — Dockerfile 빌드 · 호스트 Zig 검사 · shellcheck 정도는 Actions에서 돌릴 수 있다(혼자 작업하는 지금은 선택).

## 한 줄 요약

워크플로 파일 하나(`.github/workflows/checks.yml`)에 job 둘을 둔다. `host`(amd64 runner)는 저장소 루트의 새 스크립트
`quick_check.sh`를 돌린다 — shellcheck 0.11.0으로 추적 중인 셸 스크립트 51개, Zig 0.17.0으로 `fmt --check` · `ast-check` ·
`shared/screen_args_test.zig` · `init`의 크로스 빌드. 같은 스크립트를 사람도 호스트에서 `make quick`으로 돌린다(지금 lessons
"범용 명령"에 손으로 치는 세 줄이 이것이 된다). `container`(arm64 runner)는 `devcontainer/Dockerfile`을 0줄 고치지 않고 그대로
굽고, 그 안에서 BF-M0의 sanity 부팅과 `init`의 `zig build`를 돌려 이미지가 쓸 수 있는 상태임을 본다. 게이트(`check.sh`의
22체인)는 Actions에서 돌리지 않는다 — 초록은 "소스가 서식 · 문법 · 셸 규칙을 지키고 컨테이너가 구워진다"이지 "부팅한다"가
아니다.

## 배경

### 왜 지금인가

BF design(2026-08-01)의 비목표가 "CI 자동화 — 로컬에서 반복 재현 가능한 스크립트까지만. GitHub Actions 재도입은 이 서브프로젝트
완료 후 별도로 판단"이라 적었다. 그 뒤 석 달 동안 판정은 전부 로컬 게이트였고, 그것이 맞았다 — 게이트는 커널을 굽고 QEMU로 22번
부팅하는 물건이라 호스트의 Docker(OrbStack 12GB)가 10분에 끝내는 것을 공용 runner가 몇 배 걸려 할 이유가 없었다.

그런데 게이트가 안 보는 검사가 셋 있다. 호스트 Zig의 `fmt --check` · `ast-check` · `shared/screen_args_test.zig`이고, lessons
"범용 명령"에 "사람이 돌리는 검사라 목록에 없으면 영영 안 돈다(SA-M0)"라고 적혀 있다. shellcheck는 그 목록에도 없다 — 이 저장소의
셸 스크립트 51개를 지금까지 한 번도 기계가 읽지 않았다(기준선은 아래 확인 4). 둘 다 1분 안에 끝나고 빌드 산출물이 필요 없다 —
Actions가 맞는 자리는 게이트가 아니라 이것이다.

Dockerfile 빌드를 더하는 이유는 하나다. 이미지는 사람마다 호스트에서 한 번 굽고 몇 주를 쓰므로(지금 것은 2026-10-24에 구웠다),
Dockerfile을 고친 commit이 실제로 구워지는지는 다음 사람이 처음 받을 때까지 아무도 모른다. apt 패키지 이름이 바뀌거나 tarball
URL이 죽으면 그때 드러난다. 매 push마다 깨끗한 기계에서 한 번 굽는 것이 그 간격을 없앤다.

### Actions가 할 수 있는 것과 없는 것

| 검사 | 로컬 비용 | Actions에서 | 이번 범위 |
|---|---|---|---|
| shellcheck 51파일 | 1초 | runner에 shellcheck 0.9.0이 있지만 버전이 호스트(0.11.0)와 다르다 — tarball로 받는다 | M0 |
| Zig `fmt --check` · `ast-check` · shared test | 2초 | Zig 0.17.0 tarball 57MB | M0 |
| `cd init && zig build` | 25초(cold, 호스트 Mac) | target이 x86_64-linux로 고정이고 libc를 안 쓰므로 어느 호스트에서나 된다(확인 5) | M0 |
| `docker build devcontainer/` | 몇 분(네트워크) | arm64 runner에서 Dockerfile 그대로. 시간은 첫 회차가 잰다 | M0 |
| sanity 부팅(`devcontainer/sanity/check.sh`) | 5초 | 컨테이너 안 qemu TCG | M0 |
| `init` · `terminal`의 `zig build test`(호스트 검사) | 컨테이너 arm64에서 돈다 | 컨테이너 안이면 된다. terminal은 `prepare.sh`가 네트워크에서 넷을 받아야 한다(확인 6) | M1 후보 |
| 게이트 22체인 | 10분(prebuild 364 + lanes 308초, M-series 12GB) | 커널 빌드 · firmware 662MB · TCG 부팅 22번을 4 vCPU에서 — 재지 않았고, 타이밍 판정(GF)이 공용 runner에서 흔들릴 것이다 | 비목표 |

## 착수 전에 확인한 것

2026-10-30, HEAD `c0b0c9a`.

1. 저장소 쪽. `.github`가 없다. 원격은 `github.com/soomtong/tars-linux`(public, 기본 브랜치 `main`), Actions는 켜져 있고
   `allowed_actions: all`. Pages는 `gh-pages` 브랜치의 legacy 빌드라 워크플로가 필요 없다 — 이번 일과 겹치지 않는다. 원격 브랜치는
   `main` · `gh-pages` · 옛것 하나(`pin-title-report-off-and-harden-config-mount`).
2. Dockerfile은 arm64 전제다. ZM-M3가 컨테이너를 호스트(Apple Silicon)와 같은 arm64로 바꿨고, 마지막 층이
   `zig-aarch64-linux-0.17.0.tar.xz`를 받는다. amd64 runner에서 그대로 굽으면 이미지는 만들어지지만 안의 zig가 돌지 않는다.
   GitHub는 public 저장소에 arm64 Linux runner(`ubuntu-24.04-arm`, 4 vCPU)를 무료로 준다(2025-01 public preview, 2026-01에
   private까지 — 뒤의 것은 2차 출처). 지금 이미지는 1.54GB이고 층은 base 101 · apt 824 · amd64 sysroot 258 · zig 360MB.
3. runner 이미지(2026-10-26판, amd64 · arm64 둘 다): shellcheck 0.9.0-1, Docker 28.0.4, Buildx 0.38.1, jq 1.7. 호스트 Mac은
   shellcheck 0.11.0(Homebrew). SC2329(한 번도 안 부르는 함수)는 0.10에서 생긴 검사라 0.9.0은 그 19줄을 못 본다 — 버전이 다르면
   같은 파일에서 다른 답이 나오므로 runner의 것을 쓰지 않고 0.11.0을 받는다(`shellcheck-v0.11.0.linux.x86_64.tar.xz` 2.5MB,
   sha256 `8c3be12b…`).
4. shellcheck 기준선(호스트 0.11.0). 대상은 `git ls-files '*.sh'` 49개(`fd -e sh`로 vendor · ghostty-src를 뺀 목록과 같다)에 게스트로
   들어가는 확장자 없는 둘(`kernel/wifi/tars-wifi` `#!/bin/sh` · `kernel/dictation/tars-dictate` `#!/usr/bin/bash`)을 더한 51개.
   shebang은 `#!/usr/bin/env bash` 42 · `#!/usr/bin/bash` 2 · `#!/bin/sh` 2, 그리고 `# shellcheck shell=bash` 지시자만 있는 source
   전용 셋(`gate_lib.sh` · `kernel/guest_tools.sh` · `kernel/guest_firmware.sh`).
   - 맨 `shellcheck`은 76줄인데 28이 SC1091("`../gate_lib.sh`를 안 따라갔다")이다. `-x -P SCRIPTDIR`(source를 스크립트 위치 기준으로
     따라간다)로 50줄 · 21파일이 된다.
   - 그 50줄은 warning 4 · note 46. warning은 `audio/probe.sh:98`(SC2010 `ls | grep`) · `kernel/tq-probe.sh:27`(SC3045 POSIX sh의
     `read -n`) · `probe/run.sh:21`(SC2164 `cd` 실패 처리) · `wifi/ap.sh:89`(SC2034 안 쓰는 `i`). note는 SC2329(안 부르는 함수) 19 ·
     SC2028(`echo`의 이스케이프) 7 · SC2086(따옴표) 5 · SC2012(`ls` 대신 `find`) 5 · SC2016(작은따옴표 안 `$`) 3 · 그 밖 7.
     SC2329 19 가운데 10이 `config/check.sh`다 — 정의만 있고 안 부르는 함수가 열이라는 뜻이고, 왜 남아 있는지는 안 읽었다.
   - 네 warning이 있는 파일은 전부 체인의 `check.sh`가 아니다(프로브 둘 · 조사 스크립트 · wifi AP 스크립트).
5. Zig 쪽 기준선(호스트 0.17.0). `fmt --check` 통과(0.09초), `ast-check` 80파일 실패 0, `zig run shared/screen_args_test.zig` 통과
   (1.9초). `cd init && zig build`가 macOS 호스트에서 된다 — 25초(cold), 산출물 넷(init · tars-config · tars-install · tars-service)이
   x86_64 ELF다. `build.zig`가 target을 x86_64-linux로 고정하고 libc를 안 링크하기 때문이다. 반면 `zig build test`(init의 호스트
   검사 `config_test` 등)는 macOS에서 5분이 넘도록 안 끝나 멈췄다 — 그 검사는 컨테이너의 Linux에서 도는 것이고 왜 macOS에서
   멈추는지는 쫓지 않았다(이번 범위가 아니다). host job에 `zig build test`는 넣지 않는다.
6. terminal은 `prepare.sh`가 네트워크에서 넷(ghostty tarball · `stb_truetype.h` · `stb_image.h` · unifont)을 받아야 `zig build`가
   된다. M0의 host job에 넣지 않는다.
7. Zig 0.17.0 tarball(ziglang.org `index.json`, 2026-10-01): x86_64-linux 57.3MB sha256 `1cbe9df9…`, aarch64-linux 52.9MB sha256
   `9e8d1166…`(Dockerfile이 받는 것 — Dockerfile은 해시를 대조하지 않는다).
8. `docker build`에 걸리는 시간은 호스트에서 다시 재지 않았다 — 네트워크에서 받는 층이 셋이라 회차마다 다르고, 호스트의 숫자가
   runner의 숫자가 아니다. runner의 첫 회차가 잰다.
9. 체인 스크립트가 `TMPDIR` · `TARS_RENDER_VERIFY` 같은 환경을 읽듯 runner도 환경이 다르다 — `quick_check.sh`가 쓰는 도구는
   `git` · `shellcheck` · `zig` · `xargs` 넷뿐이다(`fd` · `rg`는 호스트 Mac에는 있지만 runner에는 없으므로 쓰지 않는다).

## 결정

### 결정 1. 워크플로 파일 하나, job 둘

`.github/workflows/checks.yml` 하나. 트리거는 `push`(모든 브랜치) · `pull_request` · `workflow_dispatch`(손으로). `concurrency`로
같은 ref의 앞 회차를 취소한다. job 둘은 병렬이고 서로 기다리지 않는다.

- `host` — `ubuntu-24.04`(amd64). `actions/checkout` 뒤 shellcheck와 Zig tarball을 받아 `./quick_check.sh`를 돌린다.
- `container` — `ubuntu-24.04-arm`. `docker build -t tars-devcontainer devcontainer/`(Makefile `container`와 같은 줄), 그 다음
  `docker run … devcontainer/sanity/check.sh`와 `docker run … 'cd init && zig build'`.

왜 하나인가 — 검사가 두 종류뿐이고, 읽을 파일이 하나면 "CI가 무엇을 하는가"를 한 번에 읽는다. 왜 `push`가 모든 브랜치인가 — 혼자
작업하는 저장소라 브랜치가 드물고, 일부러 깨뜨린 브랜치를 push해서 빨개지는지 보는 것(결정 6의 mutation)이 PR 없이 된다.

### 결정 2. 도구는 저장소가 정한 버전을 tarball로 받고 sha256을 대조한다

shellcheck 0.11.0과 Zig 0.17.0을 각자의 release tarball로 받는다. 제3자 action(`mlugg/setup-zig` · `ludeeus/action-shellcheck`
류)은 쓰지 않는다 — 무엇이 도는지 워크플로 파일에서 읽히지 않고, Dockerfile이 zig를 `curl`로 받는 모양과도 다르다. 쓰는 action은
`actions/checkout`뿐이다.

Zig의 버전은 Dockerfile의 `ENV ZIG_VERSION=0.17.0`이 정본이다. 워크플로와 `quick_check.sh`가 그 줄을 읽어 쓴다 — ZU가 다음에
Zig를 올릴 때 고칠 자리가 Dockerfile 한 곳으로 남는다. 해시는 버전마다 다르므로 워크플로에 적고, ZU의 절차에 "해시도 고친다"를
더한다. shellcheck 버전은 `quick_check.sh` 머리에 적는다.

### 결정 3. `quick_check.sh` — 사람과 CI가 같은 스크립트를 돌린다

저장소 루트에 `quick_check.sh`를 둔다. 하는 일은 순서대로

1. `shellcheck -x -P SCRIPTDIR -S warning` — 대상은 `git ls-files '*.sh'`에 게스트 스크립트 둘을 더한 목록. 추적 파일 기준이라
   `terminal/vendor/` · `ghostty-src/` · `out/`이 안 걸린다.
2. `zig fmt --check init/build.zig terminal/build.zig init/src terminal/src shared`.
3. `zig ast-check` — `init/src` · `terminal/src` · `shared`의 `.zig` 전부.
4. `zig run shared/screen_args_test.zig`.
5. `cd init && zig build` — `--prefix` · `--cache-dir`를 `out/quick/` 아래로 두어 `init/zig-out`(initrd가 복사하는 원본)을 건드리지
   않는다.

PATH의 `shellcheck` · `zig` 버전이 정한 것과 다르면 그 사실을 한 줄 찍고 계속 돈다(실패가 아니다 — 호스트 Mac은 Homebrew가
올리는 대로 따라가고, 답이 다르면 그 줄이 이유를 말한다). 끝에 `quick_check: PASS` 또는 실패한 단계 이름을 찍는다.

Makefile에 `quick` 타깃을 더한다(`./quick_check.sh` 한 줄, 컨테이너 없이 호스트에서). lessons "범용 명령"의 Zig 세 줄은 "`make quick`
이 돈다"로 바꾸고 명령은 스크립트에 남는다 — 명령을 두 벌 두지 않는다(Makefile 머리의 규칙).

### 결정 4. shellcheck의 판정 수준은 warning, note는 수만 찍는다

`-S warning`으로 판정한다. 지금 warning 넷은 GH-M0이 고친다 — 고치는 모양은 plan이 자리마다 정하고, 동작이 바뀔 수 있는 자리는
고치는 대신 `# shellcheck disable=SCxxxx` 지시자와 이유 한 줄을 둔다(예: `tq-probe.sh`의 `read -n`은 게스트의 `sh`가 무엇인지에
달렸다). note 46은 판정하지 않는다 — 19가 "안 부르는 함수"이고 그중 10이 `config/check.sh`라 하나하나 읽어야 하는 일이며, 체인
스크립트를 고치면 게이트가 따라와야 한다. 대신 `quick_check.sh`가 `-S style`로 한 번 더 세어 `shellcheck notes: N`을 찍는다 —
판정은 아니지만 수가 움직이면 보인다(위험 4). 그 46의 정리는 M1 후보다.

검토한 다른 길 — 처음부터 note까지 판정(`-S style`). 50줄을 다 고치거나 지시자로 덮어야 첫 회차가 초록이고, 그 가운데 "안 부르는
함수"는 지우는 쪽이 맞을 수 있어 체인 코드 편집과 게이트가 따라온다. GH의 범위가 아니다.

### 결정 5. container job은 Dockerfile을 그대로 굽고 안에서 둘을 돌린다

Dockerfile은 0줄 바꾸지 않는다(arm64 runner를 쓰는 이유다 — 확인 2). 구운 뒤

- `devcontainer/sanity/check.sh` — BF-M0의 것. 크로스 gcc로 32비트 ELF를 만들어 qemu TCG로 5초 부팅하고 시리얼의 표식을 본다.
  컨테이너의 도구 셋(크로스 툴체인 · qemu · make)이 실제로 동작하는지를 한 번에 본다. 산출물(`*.o` · `sanity.elf`)은 `.gitignore`에
  있다.
- `cd init && zig build` — 이미지 안의 zig(aarch64)가 게스트 바이너리를 만든다. host job의 같은 명령과 짝이다 — 호스트의 zig와
  이미지의 zig가 같은 소스를 같은 버전으로 굽는다.

층 캐시(`buildx`의 gha 캐시)는 M0에 넣지 않는다. 먼저 캐시 없는 시간을 잰다 — 10분을 넘으면 M1이 본다.

### 결정 6. 검증 — push가 게이트다

워크플로는 push해야 돈다. GH-M0의 Task는 "로컬 `make quick` 통과 → commit → push → `gh run watch`"의 순서이고, 결과(두 job의
시간 · 로그의 버전 줄)를 plan의 결과 절에 적는다. 일부러 깨뜨려 빨개지는 것을 둘 본다 — (a) `.sh` 하나에 `cd /nowhere` 같은
warning을 넣은 브랜치, (b) `.zig` 하나의 서식을 깨뜨린 브랜치. 둘 다 임시 브랜치를 push해 `host`가 빨개지는 것을 보고 브랜치를
지운다. `container`의 mutation은 Dockerfile을 깨뜨려 몇 분을 기다리는 일이라 하지 않는다 — `docker build`의 exit code가 판정이고
그것은 Docker의 몫이다.

로컬 게이트는 결정 4가 고치는 네 파일이 어느 체인에 닿는지 plan이 보고 정한다 — 넷 다 체인의 `check.sh`가 아니므로 닿는 체인만
`make check`로 돌리고, 닫을 때 루트 게이트 1회(관행)를 돈다.

### 결정 7. README에 상태 배지 한 줄

README 제목 아래에 `checks.yml`의 배지를 한 줄 둔다. 배지 옆 글은 "정적 검사와 컨테이너 빌드 — 게이트는 로컬(`make gate`)"이다.
초록이 부팅을 뜻한다고 읽히지 않게 하는 한 줄이다(위험 5).

## Milestone

- GH-M0 — 위 결정 전부. Task 넷으로 나누고 Task마다 commit 하나.
  1. `quick_check.sh` + Makefile `quick` + shellcheck warning 넷 고치기(닿는 체인 `make check`). 로컬에서 `make quick` PASS.
  2. `.github/workflows/checks.yml` + README 배지. push → `gh run watch` → 두 job 초록, 시간 기록.
  3. mutation 둘(결정 6). 임시 브랜치 push → 빨강 확인 → 브랜치 삭제.
  4. 문서 — lessons "범용 명령" · `key-files.md` · `docs/decisions/project_zig_upgrade.md`(또는 ZU의 절차가 있는 자리)에 "해시도
     고친다". 루트 게이트 1회.
- M1 후보(M0의 숫자를 보고 사용자가 고른다) — shellcheck note 46 정리 · 컨테이너 안 `zig build test`(init, 그리고 네트워크 넷을
  받는 terminal) · `buildx` 층 캐시 · 구운 이미지를 ghcr.io에 올려 다음 사람이 굽지 않게 하는 것(이건 새 판단이다 — README "준비"의
  첫 줄이 바뀐다).

## 위험

1. arm64 runner의 대기. public preview 때 "피크 시간에 큐가 길 수 있다"고 했다. 혼자 작업하는 지금은 받는다 — `container`가 늦어도
   `host`는 따로 끝난다(결정 1의 병렬).
2. 우리 코드가 아닌 빨강. ziglang.org · GitHub releases · debian 미러 · apt가 죽으면 빨개진다. 구분은 로그의 `curl` · `apt-get` 줄이고
   처방은 재실행(`gh run rerun`)이다. sha256이 안 맞는 빨강은 다르다 — tarball이 바뀐 것이고 재실행으로 안 풀린다.
3. 버전 드리프트. Zig는 Dockerfile 한 곳(결정 2), shellcheck는 `quick_check.sh` 한 곳. 호스트 Mac의 Homebrew가 둘을 올리면
   `quick_check.sh`가 "버전이 다르다" 한 줄을 찍는다 — 그때 답이 CI와 다르면 그 줄이 이유다.
4. note가 조용히 쌓인다(결정 4). `shellcheck notes: N` 줄이 로그에 남으므로 M1이 집을 때 기준선 46과 견준다.
5. 초록을 "부팅한다"로 읽는 것. 배지 옆 한 줄(결정 7)과 이 design의 한 줄 요약이 말한다. 게이트는 로컬이다.
6. `quick_check.sh`의 `cd init && zig build`가 `init/zig-out`을 덮으면 initrd가 호스트 Mac의 zig로 만든 바이너리를 싣는다 — 같은
   버전이면 같은 산출물이겠지만 확인하지 않았다. `--prefix out/quick/init`로 비켜 간다(결정 3의 5).
7. `tq-probe.sh`의 `read -n`을 고치면 게스트에서 동작이 바뀔 수 있다. 결정 4가 "동작이 바뀔 수 있는 자리는 지시자로"라 적은 이유다.
   plan이 그 스크립트가 어디서 무슨 `sh`로 도는지 읽고 정한다.

## 비목표

1. 게이트(`check.sh` · 22체인)를 Actions에서. 커널 빌드 · firmware 662MB · TCG 부팅 22번을 공용 runner에서 — 재지 않았고 타이밍
   판정이 흔들릴 것이다. 원격 runner(자기 기계)를 두는 날 다시 본다.
2. 릴리스 자동화(tag → ISO → GitHub release). `docs/decisions/project_release.md`의 일곱 단계는 손으로 한다 — 버전은 사용자가 낸다.
3. `gh-pages`(소개 페이지)의 빌드. legacy Pages가 브랜치를 그대로 서빙한다.
4. Dependabot · 제3자 action · 브랜치 보호 규칙.
5. terminal의 빌드와 `zig build test`(네트워크 넷). M1 후보.
6. shellcheck note 46의 정리. M1 후보.
7. 소개 페이지(`gh-pages` `data.js`). 내부 작업이다(사용자 결정, 2026-10-25).

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_github_actions.md`와 `MEMORY.md` 한 줄.
- `HANDOFF.md` — 후보 (5) 지우기, "이어받는 사람이 볼 것"에 `make quick`과 배지 한 줄.
- `docs/guides/lessons.md` "범용 명령"의 Zig 세 줄 → `make quick`. `key-files.md`에 `quick_check.sh` · `checks.yml` 한 줄씩.

## 관련

- `docs/specs/2026-08-01-tars-boot-foundation-design.md` 비목표 — "GitHub Actions 재도입은 … 별도로 판단". 이 문서가 그 판단이다.
- `docs/specs/2026-10-25-tars-host-checks-design.md` 비목표 6 · `docs/specs/2026-10-26-tars-lessons-split-design.md` 비목표 5 —
  점검의 (5)를 각자 미룬 자리.
- `docs/decisions/project_zig_upgrade.md` — Zig 버전을 올리는 절차. 결정 2가 해시 한 자리를 더한다.
- `docs/decisions/feedback_push_policy.md` — push는 묻지 않고 한다. 결정 6의 "push가 게이트다"가 이 위에 선다.
- Makefile 머리의 규칙 — "순서와 판정은 스크립트에, Makefile은 부르기만". 결정 3의 `quick` 타깃이 그 모양이다.
