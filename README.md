# TARS

[![checks](https://github.com/soomtong/tars-linux/actions/workflows/checks.yml/badge.svg)](https://github.com/soomtong/tars-linux/actions/workflows/checks.yml)
정적 검사 · 컨테이너 빌드 · 호스트 검사(`zig build test`)다 — 부팅 판정인 게이트는 로컬 `make gate`.

직접 빌드한 Linux 커널 위에, 직접 만든 init(PID 1)과 터미널을 올린 시스템이다.
셸까지 가는 길에 배포판의 부품을 쓰지 않는다 — 커널이 어디까지 책임지고
어디서부터 우리 코드인지를 매 단계 확인하면서 만든다.

```
xorriso hybrid ISO → Limine → 자체 빌드 커널 → Zig init(PID 1)
                                                  ├── /terminal (DRM/KMS + ghostty-vt)
                                                  └── fish
```

## 준비

빌드는 컨테이너 안에서만 된다. 커널과 게스트 바이너리가 x86_64 크로스
툴체인을 쓰는데 그것이 이미지 안에만 있기 때문이다.

```bash
docker build -t tars-devcontainer -f devcontainer/Dockerfile .
```

`--platform`을 붙이지 않는다. 호스트(Apple Silicon)와 같은 arm64로 돌고,
게스트용 x86_64 산출물은 크로스 컴파일로 만든다
(`docs/decisions/project_build_host_arch.md`).

## 빌드

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -e
  (cd kernel   && ./build.sh)                    # bzImage
  (cd init     && zig build)                     # PID 1
  (cd terminal && ./prepare.sh)                  # vendor + terminal 바이너리
  (cd kernel   && ./make_initrd.sh)              # initrd.cpio
  (cd boot     && ./build.sh && ./make_iso.sh)   # out/tars.iso
'
```

각 스크립트는 입력의 sha256을 산출물 옆에 적어 두고 대조하므로, 바뀐 것이
없으면 건너뛴다. `terminal/src`만 고쳤다면 `terminal/prepare.sh` 한 줄이면
된다.

### make로 한 줄에

루트에 `Makefile`이 있다. 컨테이너가 필요한 일은 컨테이너 안에서, QEMU만
호스트에서 돈다. 인자 없는 `make`가 목록과 각 항목의 설명을 찍는다.

```bash
make boot-qemu                 # 전부 빌드하고 설정 디스크를 붙여 QEMU로 띄운다
make run-qemu                  # 빌드 없이 방금 만든 것으로 다시 띄운다
make disk-fresh                # 설정 디스크를 지우고 새로 굽는다
make check CHAIN=config        # 체인 하나만 (2~8분)
make gate                      # 루트 게이트 — 모든 체인을 1회, 동시에 (약 10분)
make clean                     # 빌드 산출물만 지운다 — 설정 디스크는 살린다
```

`boot-qemu`가 붙이는 것은 `out/tars-config.img`다. 게이트의 `out/config.img`와
다른 파일인 이유가 있다 — 게이트는 매 회차 새로 굽는 것이 검증의 일부이고,
이쪽은 부팅 사이에 남아야 한다(별칭·히스토리·`git config --global`이 그 안에
쌓인다). `CONFIG_DISK=`로 비우면 설정 디스크 없이 띄운다.

## 실행해 보기

`make boot-qemu`로 바로 뜬다. 로컬 macOS 화면으로 직접 QEMU를 띄우거나,
VM(UTM 등)에 올리거나, 실기 노트북 USB로 부팅하는 방법은 `docs/guides/running-tars.md`에 따로 정리했다.

## 검증

```bash
# 전체 — 모든 체인(지금 스물둘)을 1회차씩, 빌드 한 번 뒤 동시에. 약 10분
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh

# 회차를 늘리거나 동시 실행 수를 정할 때 (기본 JOBS는 컨테이너 메모리로 정한다)
docker run --rm -e RUNS=2 -e JOBS=4 -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh

# 한 체인만
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash copy/check.sh
```

체인은 자기가 부팅할 것을 스스로 빌드하므로 앞의 빌드 절을 먼저 돌릴 필요가
없다. 다만 `check.sh`는 시작할 때 `out/`·`kernel/build`·`zig-out`을 지운다 —
`out/` 아래에 남긴 조사 로그가 있으면 먼저 빼낸다.

게이트가 남긴 시리얼 로그는 컨테이너가 사라진 뒤에도 `out/gate-logs/`에 있다 —
루트 게이트는 `<시작 시각>/<체인>-<회차>/`, `make check CHAIN=x`는 `<체인>/`.
다음 게이트의 시작이 `out/`을 지우므로 남길 판은 밖으로 옮긴다.

체인 목록은 `check.sh`의 `CHAINS` 배열 확인.

## 문서

| 파일 | 무엇 |
|---|---|
| `CLAUDE.md` | 이 저장소의 작업 규칙 |
| `HANDOFF.md` | 지금 어디까지 왔는지, 다음에 무엇을 하는지 |
| `MEMORY.md` | 세션을 넘어 유지되는 기억의 색인 (본문은 `docs/decisions/`) |
| `docs/guides/running-tars.md` | 로컬 화면·VM·실기 노트북에서 띄워 보는 방법 |
| `docs/guides/lessons.md` | 작업 요령의 허브 — 게이트 운영법 · 범용 명령, 아래 넷으로 옮긴 절의 표 |
| `docs/guides/measurements.md` | 다시 조사하지 말 실측 (번호 목록) |
| `docs/guides/dead-ends.md` | 시도했으나 안 되는 접근 |
| `docs/guides/carryover.md` | 이월 숙제 (미룬 일) |
| `docs/guides/key-files.md` | 핵심 파일 지도 — 어느 파일이 무엇을 책임지고 무엇을 건드리면 깨지는가 |
| `docs/guides/completed.md` | 끝난 서브프로젝트 표 (이름 · 끝난 날 · 무엇이 섰나) |
| `docs/study/` | 용어집과 개념 학습 노트 |
| `docs/specs/` | 서브프로젝트별 design doc |
| `docs/plans/` | milestone별 실행 plan |
