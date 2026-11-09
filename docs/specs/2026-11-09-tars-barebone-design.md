# TARS Barebone — Design

접두사: BB

Date: 2026-11-09
Status: 확정(2026-11-09, 3판) — 열린 질문 없음. 자동 실행은 묶음의 셸 조각(결정 5 · 6, 사용자 "BB 작업 시작합시다!"). BB-M0 끝(143,751,168 B, smoke 통과 — plan `docs/plans/2026-11-09-tars-barebone-bb-m0.md`). 다음은 BB-M1

계기: `dev-20261109` 실기 설치 테스트 중 사용자(2026-11-09): "배포판을 만들 때 개발도구 층을 제외한 minimal 버전의 iso 파일도 생성해서
같이 업로드 해야겠다. 임베디드 기기에 납품되는 프로젝트의 최종 실행 파일만 포함해서 배포하는 경우 사용할거야." 이어서 정한 것: sshd 같은
기본 데몬은 포함, 파일 이름 `tars-<ver>-barebone-x86_64.iso`, 첫 데모 실행 파일은 fakesteak(domsson/fakesteak) — 사용자 계정으로 fork
(`soomtong/fakesteak`)해서 linux-amd64 릴리스를 낸다.

관련 문서: TP design(`2026-11-05-tars-dev-layer-design.md`) 결정 1(출처 순서) · 7(묶음 목록) · 9~13(묶음을 `/usr`에 겹치기),
기억 `docs/decisions/project_minimal_iso.md` · `project_release.md` · `project_release_0_2.md` · `feedback_tool_sourcing.md`.

## 한 줄 요약

barebone ISO는 개발 도구 층의 묶음을 하나도 싣지 않은 ISO다(`make iso`의 기본값). 납품할 프로젝트의 실행 파일은 개발 도구 층과 같은
장치로 묶음 하나(squashfs)에 담아 `ISO_LAYERS="<그 묶음>"`으로 barebone 위에 얹는다. 첫 사례가 fakesteak이다. init · 설치기 코드는
바꾸지 않는 것이 목표다.

## 확인 (2026-11-09, HEAD `bc02ad9`)

1. `Makefile:231-234` — `ISO_LAYERS`가 비면 "TP 전과 같은 ISO"다. 묶음 없이 initrd(기본 데몬 sshd · dhcpcd · chronyd 등 포함)만 싣는다.
   0.1.0의 ISO가 111,071,232 B였다. 개발 도구 층을 다 실은 `dev-20261109`는 2,036,903,936 B다.
2. `boot/make_iso.sh:42-55` — `ISO_LAYERS`의 이름마다 `devlayer/build/<이름>.sqfs`를 `boot/layers/`에 싣는다. 없으면 멈춘다.
3. `init/src/layers.zig` — 설치된 디스크 p3의 `/home/.tars/layers/*.sqfs`를 부팅마다 `/usr` 아래에 겹친다. 묶음 이름은 `a-z0-9-`,
   32자 이하(`judgeName`). 그러니 묶음은 디스크에 설치한 뒤에만 붙고, USB 라이브 부팅에서는 붙지 않는다.
4. `devlayer/harvest.sh:23-30` — debian · vendor-repo 줄이 없는 묶음(upstream만)은 거두기를 건너뛴다. lang-jvm이 그 선례다.
5. `devlayer/manifest.tsv`의 `upstream` 줄이 GitHub release의 linux-amd64 tarball을 받아 sha256을 대조한다. 사용자 저장소의 선례:
   cci(`soomtong/claude-code-history-viewer`) · glc(`soomtong/gluck`), 선택 열 `exe=`.
6. fakesteak 원본(domsson/fakesteak)은 C, CC0. 릴리스 v0.2.1~v0.2.4(마지막 2020-11-18)에 첨부 파일이 없다 — TP design이 이 도구를
   뺀 이유("미리 빌드된 바이너리가 없다")다.

## 결정

1. barebone ISO = `make iso`(ISO_LAYERS 비움). 새 빌드 경로를 만들지 않는다. 파일 이름만 `tars-<ver>-barebone-x86_64.iso`로 바꿔 올린다.
2. 프로젝트 실행 파일은 묶음 하나에 담는다 — 묶음 이름은 프로젝트 이름(`fakesteak`). 개발 도구 층과 같은 manifest · build 장치를 쓰고,
   `DEV_LAYERS`의 기본 목록에는 넣지 않는다(개발 도구가 아니다 — 기본 `make dev-layers`가 굽지 않는다). 굽는 것은
   `make dev-layers DEV_LAYERS=fakesteak`.
3. 납품 ISO = `make iso ISO_LAYERS="fakesteak"`. barebone 위에 그 묶음 하나만 있다.
4. 출처는 사용자의 fork `soomtong/fakesteak`의 GitHub release(linux-amd64 tarball) — `upstream` 종류. 소스 빌드 금지 규칙
   (`feedback_tool_sourcing`)을 지킨다. 릴리스는 사용자가 낸다(이 세션의 GitHub 범위는 `soomtong/tars-linux` 하나다).
5. 부팅하면 화면의 첫 패널에 프로젝트 실행 파일이 뜬다(사용자 2026-11-09: "부팅 때 프로젝트 실행 파일 자동 실행 enable 합시다.
   멋지게 데모~" — 2판의 비목표를 뒤집었다). 끝내면(fakesteak은 Ctrl+C) 그 자리에 평소의 셸 프롬프트가 남는다 — 기기를 고치러 온
   사람이 키보드로 들어갈 길이 그대로다.
6. 띄우는 장치는 묶음이 싣는 셸 조각이다 — init · terminal 코드 0줄. 개발 도구 층이 이미 쓰는 길(server 묶음의 PGHOST 조각)을 그대로 쓴다:
   묶음의 `etc/fish/conf.d/90-autorun.fish`와 `etc/tars/rc.d/autorun.sh`(bash · zsh가 맨 앞에서 읽는다, `kernel/make_initrd.sh:911-948`).
   조각은 다음 넷이 모두 참일 때만 한 번 실행한다.
   - 대화형 셸이다.
   - `TERM=xterm-256color` — terminal의 패널이다. 시리얼 콘솔 셸은 `TERM=linux`(`terminal/src/main.zig:3742-3758`)라 거른다.
   - `SSH_CONNECTION`이 없다 — ssh로 들어온 셸은 거른다.
   - 이번 부팅에 아직 안 띄웠다 — 표시 파일 `/tmp/.tars-autorun`(initrd의 RAM이라 부팅마다 비워진다)을 먼저 만들고 띄운다. 그래서 새 패널 ·
     워크스페이스를 열어도 다시 뜨지 않는다.
   띄우는 명령은 조각 한 줄이다: `fakesteak -s 10 -b`처럼 옵션까지(값은 BB-M1에서 실기를 보고 고른다).
   진짜 키오스크(셸 없이 init이 앱을 감독 · 재시작, `tars.conf` 키)는 비목표로 남긴다 — 납품 프로젝트가 그것을 요구할 때 init의 일로 다시 연다.

## 비목표

- 셸 없는 키오스크 — init이 앱을 감독하고 죽으면 다시 띄우는 것(결정 6의 끝).
- USB 라이브 부팅에서 묶음을 붙이기(확인 3 — 설치 뒤에만 붙는다).
- 납품 ISO를 릴리스마다 올리기 — 릴리스에 더하는 것은 barebone ISO 하나다. fakesteak 데모 ISO는 따로 한 번 올린다(사용자 2026-11-09: "이번
  작업 대상인 데모 릴리즈도 github releases 페이지에 올려주세요") — 태그 `demo-fakesteak-<YYYYMMDD>`(annotated), 프리릴리스 · Latest 아님,
  파일 `tars-demo-fakesteak-<YYYYMMDD>-x86_64.iso` + `SHA256SUMS`. 정식 버전의 release에는 섞지 않는다.

## fakesteak 릴리스 (2026-11-09 확인 — 사용자가 낸 뒤)

- `soomtong/fakesteak` v1.0.0. 자산은 `fakesteak-linux-x86_64.tar.gz`(343,901 B)와 `SHA256SUMS` — 받아서 `shasum -c` OK,
  sha256 `b0abec76012ceddcdad1fd8793cd0de1bd9d805e99332dd97d9415c6190cca82`.
- tarball 안: `fakesteak-linux-x86_64/{fakesteak,LICENSE,README.md}`. 맨 위 디렉터리 하나라 `strip=` 기본값(1)이 벗긴다 — `exe=fakesteak`.
- `file`: ELF 64-bit x86-64, statically linked, stripped(755,944 B). fork의 `.github/workflows/release.yml`이 `ubuntu-latest`에서
  `make CFLAGS="-Wall -O3 -static"`로 짓는다. 정적이라 NEEDED가 없다 — initrd의 glibc 판과 무관하다. `-march`를 주지 않았으니
  기본 x86-64(baseline)다 — 에어 2011에서 선다(bun · duckdb가 걸린 AVX2 문제가 없다).
- manifest 줄(BB-M1에서 넣는다):
  `fakesteak	fakesteak	1.0.0	upstream	https://github.com/soomtong/fakesteak/releases/download/v1.0.0/fakesteak-linux-x86_64.tar.gz	b0abec76012ceddcdad1fd8793cd0de1bd9d805e99332dd97d9415c6190cca82	exe=fakesteak`

## 열린 질문

1. (닫힘) fakesteak 릴리스의 모양 — 위 절.
2. (닫힘, 사용자 2026-11-09 "추천안 선택: smoke만") 체인 게이트는 더하지 않는다 — barebone ISO의 smoke(QEMU 부팅 · 버전 줄)만 본다.
   묶음을 겹치는 길은 devtools 체인이 이미 지킨다. `check.sh`의 `CHAINS`는 그대로다.

## Milestone

- BB-M0: barebone ISO를 짓고 QEMU smoke, 크기 기록. 맥북 에어 실기에서 설치 · 부팅. `project_release`의 배포 절차에 "barebone ISO도
  짓고 올린다" 단계를 더한다.
- BB-M1: manifest에 fakesteak 줄과 자동 실행 조각 둘(결정 6), `make dev-layers DEV_LAYERS=fakesteak`, 납품 ISO 짓기, QEMU에서 설치 →
  재부팅 → `fakesteak`, 맥북 에어 실기.
  BB-M1 plan이 먼저 확인할 것(아직 안 봤다): fakesteak이 Ctrl+C로 끝나고 터미널 상태를 되돌리는지, 묶음의 `etc/` 복사가 terminal의 첫 셸보다
  먼저 끝나는지, 사용자(uid 1000)가 `/tmp`에 쓸 수 있는지.
