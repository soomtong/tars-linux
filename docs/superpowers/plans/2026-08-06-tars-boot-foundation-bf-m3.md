# TARS Boot Foundation — BF-M3 Bootloader + Hybrid ISO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** BF-M3를 완료한다 — Limine(v12.5.2) bootloader와 `xorriso`로 만든
BIOS El Torito ISO(`out/tars.iso`)를 QEMU `-cdrom` 하나만으로 부팅해
BF-M2와 동일한 fish shell 배너(`Welcome to fish, the friendly interactive
shell`)가 QEMU serial에 출력되는 지점까지 검증한다.

**Architecture:** 새 최상위 디렉터리 `boot/`에 Limine 소스를 clone+빌드하는
`build.sh`, ISO를 만드는 `make_iso.sh`, 전체 체인을 실행하고 QEMU로
검증하는 `check.sh`를 만든다. Limine은 apt에 없으므로 GitHub `v12.5.2`
태그를 clone해 `./bootstrap` → `./configure --enable-bios-cd` → `make`로
직접 빌드한다(out-of-tree, `boot/build/`). `limine.conf`는
`protocol: linux`로 `kernel/build.sh`가 만든 bzImage를 무수정으로
부팅하고 `module_path`로 initramfs를 지정한다. ISO는 BIOS El Torito만
포함하며(UEFI 제외, design doc 비목표 참고), `xorriso -as mkisofs` 뒤
반드시 `limine bios-install`을 실행해야 부팅 가능한 이미지가 된다.

**Tech Stack:** Limine v12.5.2(GitHub 소스 빌드, nasm+autotools),
`xorriso`, Linux 6.18.42(BF-M1 산출물), Rust init + fish
4.0.2(BF-M2 산출물), QEMU system x86_64(TCG, SeaBIOS), bash

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행하며, 빌드·실행 명령은 devcontainer 컨테이너 안에서 돈다(`docker run`
으로 감싸는 커맨드는 명시적으로 표기). BF-M2까지 완료되어
`kernel/build.sh`, `init/`, `kernel/make_initrd.sh`가 정상 동작해야
한다(없다면 Task 5의 `check.sh`가 이들을 다시 호출한다).

**Design doc과의 관계:**
[2026-08-06-tars-boot-foundation-bf-m3-design.md](../specs/2026-08-06-tars-boot-foundation-bf-m3-design.md)
의 결정을 그대로 따른다 — Limine v12.5.2 소스 빌드, `protocol: linux` +
`limine.conf`, BIOS El Torito ISO + `limine bios-install`, `boot/`
디렉터리 신설, BIOS 전용 검증(SeaBIOS, UEFI 제외).

**Limine 빌드 절차의 실측 근거(2026-08-06, plan 작성 중 조사):** Limine
공식 `INSTALL.md`와 `configure.ac`를 직접 확인해 다음을 확인했다 — (1)
git checkout(release tarball 아님)에서 빌드하려면 `GNU autoconf`가 있어야
`./bootstrap`이 동작한다, (2) BIOS CD 이미지는 `./configure
--enable-bios-cd`로 활성화하며 이 옵션이 `--enable-bios`도 자동으로
켠다, (3) BIOS 포트 빌드에는 `nasm`이 필수다(`configure.ac`의
`NEED_NASM` 로직), (4) UEFI용 `mtools`는 BIOS 전용 빌드에서는 필요 없다.
아래 Task 1의 devcontainer 패키지 목록은 이 조사 결과를 반영한다.

---

### Task 1: devcontainer에 Limine/ISO 빌드 도구 추가

**Files:**
- Modify: `devcontainer/Dockerfile`

- [ ] **Step 1: Dockerfile apt 목록에 xorriso, nasm, autoconf, automake 추가**

`devcontainer/Dockerfile`의 `apt-get install` 목록에 다음 네 패키지를
추가한다(기존 목록 순서 유지, 알파벳 순으로 끝에 삽입):

```dockerfile
FROM --platform=linux/amd64 debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc-multilib \
        binutils \
        qemu-system-x86 \
        git \
        ca-certificates \
        flex \
        bison \
        bc \
        libssl-dev \
        libelf-dev \
        curl \
        cpio \
        rsync \
        fish \
        autoconf \
        automake \
        nasm \
        xorriso \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
        -y --default-toolchain stable --profile minimal \
        --target x86_64-unknown-linux-gnu

WORKDIR /workspace
```

`autoconf`/`automake`는 Limine을 release tarball이 아닌 git 소스에서
빌드하기 위한 `./bootstrap` 단계에 필요하다(핵심 설계 결정 1). `nasm`은
BIOS stage1 부트섹터 어셈블리를 조립하는 데 필수다. `xorriso`는 El
Torito ISO 생성에 쓴다. `mtools`는 UEFI CD 빌드에만 필요하므로(비목표)
추가하지 않는다.

- [ ] **Step 2: 이미지 재빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0. `Successfully tagged tars-devcontainer:latest` 또는
`naming to docker.io/library/tars-devcontainer:latest done`.

- [ ] **Step 3: 새 도구 확인**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer \
  bash -c "xorriso --version && nasm -v && autoconf --version | head -1 && automake --version | head -1"
```

Expected: 네 명령 모두 버전 문자열 출력, `command not found` 없음.

- [ ] **Step 4: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Add Limine and ISO build tools to devcontainer"
```

---

### Task 2: boot/ 디렉터리 뼈대 + limine.conf

**Files:**
- Create: `boot/limine.conf`
- Modify: `.gitignore`

- [ ] **Step 1: `.gitignore`에 boot/init 빌드 산출물 추가**

`.gitignore`에 다음 줄을 추가한다:

```
boot/src/
boot/build/
out/
```

- [ ] **Step 2: `limine.conf` 작성**

`boot/limine.conf`:
```
timeout: 0

/TARS
    protocol: linux
    kernel_path: boot():/boot/bzImage
    module_path: boot():/boot/initrd.cpio
    cmdline: console=ttyS0
```

design doc 핵심 설계 결정 2를 그대로 따른다 — `protocol: linux`로
kernel.org bzImage를 무수정 부팅, initramfs는 `module_path`로 지정,
`boot():`는 Limine 자신을 로드한 볼륨(단일 ISO9660이므로 파티션 번호
없음)을 가리킨다. `timeout: 0`은 메뉴 없이 즉시 이 엔트리로 부팅한다는
뜻이다(BF-M2까지 QEMU direct boot에 메뉴가 없던 것과 동일한 무인 부팅
경험을 유지).

- [ ] **Step 3: 커밋**

```bash
git add .gitignore boot/limine.conf
git commit -m "Add boot directory skeleton and limine.conf"
```

---

### Task 3: Limine 소스 clone + 빌드

**Files:**
- Create: `boot/build.sh`

- [ ] **Step 1: `build.sh` 작성**

`boot/build.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LIMINE_TAG="v12.5.2"
SRC_DIR="src/limine-12.5.2"

if [ ! -d "$SRC_DIR" ]; then
  echo "Cloning Limine ${LIMINE_TAG}..."
  mkdir -p src
  git clone --branch "$LIMINE_TAG" --depth 1 \
    https://github.com/limine-bootloader/limine.git "$SRC_DIR"
  (cd "$SRC_DIR" && ./bootstrap)
fi

mkdir -p build
(cd build && "../${SRC_DIR}/configure" --enable-bios-cd && make)
```

`SRC_DIR`가 없을 때만 clone + `./bootstrap`을 실행해 반복 실행 시
매번 다시 받지 않는다(`kernel/build.sh`의 `if [ ! -d "$SRC_DIR" ]` 패턴과
동일). `./bootstrap`은 git 소스 체크아웃에서만 필요한 단계로,
`autoreconf`를 호출해 `configure` 스크립트를 생성하고 3RDPARTY.md에
명시된 의존 서브모듈을 내려받는다(release tarball을 쓴다면 생략
가능하지만, 이 프로젝트는 태그 고정 git clone을 택했으므로 항상
실행한다 — 핵심 설계 결정 1). `--enable-bios-cd`는 BIOS El Torito CD
이미지(`limine-bios-cd.bin`)와 BIOS 포트 전체를 빌드하도록 켠다(UEFI는
기본값 미포함이므로 별도 옵션 없이 제외됨).

- [ ] **Step 2: 실행 권한 확인**

```bash
chmod +x boot/build.sh
```

- [ ] **Step 3: 실행해서 빌드 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/boot \
  tars-devcontainer ./build.sh
```

Expected: 종료 코드 0. clone/bootstrap/configure/make 로그가 순서대로
출력되고 마지막에 `make`가 에러 없이 끝난다.

- [ ] **Step 4: 산출물 위치 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/boot \
  tars-devcontainer bash -c "find build -maxdepth 3 -iname 'limine-bios*' -o -iname 'limine'"
```

Expected: `limine-bios.sys`, `limine-bios-cd.bin`, 그리고 `limine`(host
CLI 도구) 세 파일의 경로가 출력된다.

**만약 경로가 예상(`build/bin/`)과 다르면:** Limine의 `GNUmakefile.in`이
정의하는 `BINDIR`은 버전에 따라 바뀔 수 있다 — 여기서 출력된 실제
경로를 그대로 Task 4의 `make_iso.sh`에 반영하고, 이 Step의 결과를
아래에 "갱신" 메모로 남긴다.

- [ ] **Step 5: 커밋**

```bash
git add boot/build.sh
git commit -m "Add Limine build script"
```

`boot/src/`, `boot/build/`는 `.gitignore` 대상이라 커밋되지 않는다.

---

### Task 4: ISO 생성 스크립트

**Files:**
- Create: `boot/make_iso.sh`

- [ ] **Step 1: `make_iso.sh` 작성**

`boot/make_iso.sh`(Task 3 Step 4에서 확인한 실제 산출물 경로가
`build/bin/`과 다르면 `LIMINE_BIN` 값을 그 경로로 바꾼다):

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LIMINE_BIN="build/bin"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/boot/limine"
cp ../kernel/build/arch/x86/boot/bzImage "$STAGE/boot/bzImage"
cp ../kernel/initrd.cpio "$STAGE/boot/initrd.cpio"
cp limine.conf "$STAGE/boot/limine/limine.conf"
cp "$LIMINE_BIN/limine-bios.sys" "$STAGE/boot/limine/limine-bios.sys"
cp "$LIMINE_BIN/limine-bios-cd.bin" "$STAGE/boot/limine/limine-bios-cd.bin"

mkdir -p ../out
xorriso -as mkisofs -R -r -J \
        -b boot/limine/limine-bios-cd.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        "$STAGE" -o ../out/tars.iso

"$LIMINE_BIN/limine" bios-install ../out/tars.iso
```

design doc 핵심 설계 결정 3을 그대로 따른다 — `limine-bios.sys`와
`limine.conf`는 공식 문서가 허용하는 `boot/limine/` 위치에 두고,
UEFI 관련 xorriso 플래그(`--efi-boot`, `-efi-boot-part`, `-hfsplus`)는
넣지 않는다. `xorriso` 실행 뒤 `limine bios-install`을 반드시 실행해야
한다 — 이 단계 없이는 El Torito boot catalog만으로 실제 부팅이 되지
않는다(design doc에 기록된 실측 정정 사항).

- [ ] **Step 2: 실행 권한 확인**

```bash
chmod +x boot/make_iso.sh
```

- [ ] **Step 3: kernel/init 산출물이 없으면 먼저 준비**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd kernel && ./build.sh && cd ../init && cargo build --release && cd ../kernel && ./make_initrd.sh"
```

Expected: 종료 코드 0. `kernel/build/arch/x86/boot/bzImage`와
`kernel/initrd.cpio`가 존재한다(이미 BF-M2에서 만들어져 있다면 이
Step은 최신 상태로 재생성만 한다).

- [ ] **Step 4: ISO 생성 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/boot \
  tars-devcontainer ./make_iso.sh
```

Expected: 종료 코드 0. `xorriso` 로그에 경고 정도는 나올 수 있으나
에러로 중단되지 않는다.

- [ ] **Step 5: ISO 파일 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "ls -la out/tars.iso && xorriso -indev out/tars.iso -report_el_torito plain 2>&1 | head -30"
```

Expected: `out/tars.iso` 파일이 존재하고 크기가 0보다 크다.
`-report_el_torito` 출력에 BIOS 부팅 이미지(`Boot record`,
`El Torito boot img` 등) 정보가 보인다 — UEFI 관련 항목은 없어야
한다(BIOS 전용이므로).

**만약 `xorriso: -b` 관련 에러가 나면:** `limine-bios-cd.bin`의 스테이징
경로가 실제와 다른 것이다 — `find "$STAGE" -iname 'limine-bios-cd.bin'`
로 실제 경로를 확인하고 `-b` 인자를 맞춘다.

**만약 `limine bios-install`이 `command not found`나 실행 권한 에러를
내면:** Task 3 Step 4에서 확인한 `limine` CLI 경로가 실행 권한을
가졌는지(`chmod +x`) 확인한다 — `make`가 만든 산출물은 보통 이미
실행 권한이 있지만, 볼륨 마운트 방식에 따라 권한이 달라질 수 있다.

- [ ] **Step 6: 커밋**

```bash
git add boot/make_iso.sh
git commit -m "Add hybrid ISO build script"
```

`out/tars.iso`는 `.gitignore` 대상이라 커밋하지 않는다(kernel의
bzImage/`build/`와 동일하게 재생성 가능한 큰 바이너리이기 때문 — 이 점은
`initrd.cpio`를 커밋해온 기존 관례와 다르다: ISO는 initrd보다 훨씬 크고
매번 kernel+initrd+limine을 그대로 합친 파생물이라 diff 추적 가치가
낮다).

---

### Task 5: check.sh + 전체 부팅 검증

**Files:**
- Create: `boot/check.sh`

- [ ] **Step 1: `check.sh` 작성**

`boot/check.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

(cd ../kernel && ./build.sh)
(cd ../init && cargo build --release)
(cd ../kernel && ./make_initrd.sh)
./build.sh
./make_iso.sh

LOG="$(mktemp)"
timeout 15 qemu-system-x86_64 \
  -cdrom ../out/tars.iso \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "Welcome to fish, the friendly interactive shell" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected fish banner not found"
exit 1
```

BF-M2의 `kernel/check.sh`와 동일한 패턴(전체 체인 재실행 → QEMU 강제
종료 → grep → PASS/FAIL)이되, `-kernel`/`-initrd` 없이 `-cdrom`만
쓴다는 점이 design doc이 강조하는 핵심 차이다.

- [ ] **Step 2: 실행 권한 확인**

```bash
chmod +x boot/check.sh
```

- [ ] **Step 3: 실행해서 결과 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash boot/check.sh
```

Expected: BF-M2 때와 동일한 mount 로그와 fish 배너
(`Welcome to fish, the friendly interactive shell`)가 serial 출력에
나타나고 `PASS`, 종료 코드 0. `-kernel`/`-initrd` 옵션이 전혀 없다는
점을 로그의 QEMU 실행 커맨드 자체(스크립트 안에 있으므로 로그에는
안 보임 — `check.sh` 파일 내용으로 재확인)로 다시 확인한다.

**만약 FAIL이거나 QEMU가 아무것도 출력하지 않으면:** BF-M1/BF-M2와
달리 이번엔 커널 이전 단계(bootloader)에서 멈출 수 있다. 원인 구분
방법:
- 화면(serial)에 아무 것도 없이 멈춤 — Limine 자체가 뜨지 않은 것.
  `limine bios-install`이 정말 실행됐는지(Task 4 Step 4 로그 재확인),
  `-b boot/limine/limine-bios-cd.bin` 경로가 스테이징 디렉터리 실제
  구조와 일치하는지 확인한다.
- Limine 부팅 메시지는 보이지만 커널 부팅 로그로 이어지지 않음 —
  `limine.conf`의 `kernel_path`/`module_path` 경로(`boot():/boot/...`)가
  스테이징된 ISO 안의 실제 경로와 일치하는지 `xorriso -indev
  out/tars.iso -find` 로 ISO 내부 파일 목록을 확인한다.
- 커널은 부팅하지만 이후 로그가 BF-M2와 다름 — `cmdline: console=ttyS0`
  가 BF-M2의 `-append "console=ttyS0"`와 동일한 문자열인지 재확인한다.
- mount/execve 로그까지는 BF-M2와 동일하게 나오지만 fish 배너가 없음 —
  이는 bootloader와 무관한 init/fish 문제이므로 BF-M2 design doc의
  troubleshooting(controlling terminal, `/usr/share/fish` 최소 집합)을
  다시 참고한다.

이 반복도 BF-M1/BF-M2와 같은 학습 사이클이므로 몇 차례 반복이 필요할
수 있다. 원인을 고치면 Step 3을 다시 실행한다.

- [ ] **Step 4: 커밋**

```bash
git add boot/check.sh
git commit -m "Add BF-M3 check.sh and verify cdrom boot"
```

---

## BF-M3 완료 확인

Task 5의 Step 3이 PASS로 끝나면 BF-M3의 exit gate(design doc 기준:
`-kernel`/`-initrd` 없이 `-cdrom out/tars.iso`만으로 fish 배너 확인)를
만족한다. 이 시점에서 BF-M4(전체 스크립트화 + 3회 연속 성공 검증) plan을
별도로 작성한다.
