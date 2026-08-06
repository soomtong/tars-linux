# TARS Boot Foundation — BF-M3 Bootloader + Hybrid ISO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** BF-M3를 완료한다 — Limine(v12.5.2) bootloader와 `xorriso`로 만든
BIOS El Torito ISO(`out/tars.iso`)를 QEMU `-cdrom` 하나만으로 부팅해
BF-M2와 동일한 fish shell 배너(`Welcome to fish, the friendly interactive
shell`)가 QEMU serial에 출력되는 지점까지 검증한다.

**Architecture:** 새 최상위 디렉터리 `boot/`에 Limine binary release를
다운로드하는 `build.sh`, ISO를 만드는 `make_iso.sh`, 전체 체인을
실행하고 QEMU로 검증하는 `check.sh`를 만든다. Limine은 apt에 없으므로
GitHub Releases의 `limine-binary.tar.gz`(v12.5.2)를 받는다 — 안에 이미
컴파일된 부트로더 바이너리(`limine-bios.sys`, `limine-bios-cd.bin`)가
들어있고, host 도구(`limine` CLI)만 `cc`로 직접 빌드한다(`make -C
limine-binary`). `limine.conf`는 `protocol: linux`로 `kernel/build.sh`가
만든 bzImage를 무수정으로 부팅하고 `module_path`로 initramfs를 지정한다.
ISO는 BIOS El Torito만 포함하며(UEFI 제외, design doc 비목표 참고),
`xorriso -as mkisofs` 뒤 반드시 `limine bios-install`을 실행해야 부팅
가능한 이미지가 된다.

**Tech Stack:** Limine v12.5.2(GitHub binary release + host 도구
`cc` 빌드), `xorriso`, Linux 6.18.42(BF-M1 산출물), Rust init + fish
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
의 결정을 그대로 따른다 — Limine v12.5.2 binary release 다운로드 +
host 도구 make, `protocol: linux` + `limine.conf`, BIOS El Torito ISO +
`limine bios-install`, `boot/` 디렉터리 신설, BIOS 전용 검증(SeaBIOS,
UEFI 제외).

**Limine 조달 방식의 실측 근거(2026-08-06, plan 작성 중 재검토):**
처음에는 git 소스를 태그로 clone해 `./bootstrap`(autotools) →
`./configure --enable-bios-cd` → `make`로 전체를 빌드하기로 하고
`configure.ac`까지 읽어 필요한 패키지(`nasm`, `autoconf`, `automake`)를
확인했었다. 그러나 GitHub Releases의 `limine-binary.tar.gz` 자산을
실제로 받아 내용을 확인한 결과, 이미 컴파일된
`limine-bios.sys`/`limine-bios-cd.bin`과 host 도구 소스 `limine.c` +
최소 `Makefile`(`cc -std=c99 limine.c -o limine`, 그 이상 의존성 없음)
만 들어있음을 확인했다(design doc 핵심 설계 결정 1의 정정 사항 참고).
Limine은 이 프로젝트가 내부 동작을 배우려는 대상이 아니라 "설정이
단순해서" 고른 외부 도구이므로, 부트섹터 어셈블리까지 직접 조립할
학습 이득 없이 `nasm`/`autoconf`/`automake`를 devcontainer에 들이는
비용만 드는 첫 접근을 버리고 binary release로 바꿨다. 아래 Task 1의
devcontainer 패키지 목록은 이 재검토를 반영한다(`xorriso`만 추가).

---

### Task 1: devcontainer에 ISO 빌드 도구 추가

**Files:**
- Modify: `devcontainer/Dockerfile`

- [x] **Step 1: Dockerfile apt 목록에 xorriso 추가**

`devcontainer/Dockerfile`의 `apt-get install` 목록에 `xorriso` 하나만
추가한다(기존 목록 순서 유지, 끝에 삽입):

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

`xorriso`는 El Torito ISO 생성에 쓴다. Limine 자체는 binary release로
받으므로(design doc 핵심 설계 결정 1, 2026-08-06 정정) `nasm`/
`autoconf`/`automake`는 필요 없다 — 이미 있는 `build-essential`의 `cc`
만으로 host 도구(`limine`)를 빌드할 수 있다.

- [x] **Step 2: 이미지 재빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0. `Successfully tagged tars-devcontainer:latest` 또는
`naming to docker.io/library/tars-devcontainer:latest done`.

- [x] **Step 3: 새 도구 확인**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer \
  bash -c "xorriso --version"
```

Expected: 버전 문자열 출력, `command not found` 없음.

- [x] **Step 4: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Add xorriso to devcontainer"
```

---

### Task 2: boot/ 디렉터리 뼈대 + limine.conf

**Files:**
- Create: `boot/limine.conf`
- Modify: `.gitignore`

- [x] **Step 1: `.gitignore`에 boot 빌드 산출물 추가**

`.gitignore`에 다음 줄을 추가한다:

```
boot/limine-binary/
out/
```

- [x] **Step 2: `limine.conf` 작성**

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

- [x] **Step 3: 커밋**

```bash
git add .gitignore boot/limine.conf
git commit -m "Add boot directory skeleton and limine.conf"
```

---

### Task 3: Limine binary release 다운로드 + host 도구 빌드

**Files:**
- Create: `boot/build.sh`

- [x] **Step 1: `build.sh` 작성**

`boot/build.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LIMINE_TAG="v12.5.2"
DIR="limine-binary"
URL="https://github.com/limine-bootloader/limine/releases/download/${LIMINE_TAG}/limine-binary.tar.gz"

if [ ! -d "$DIR" ]; then
  echo "Downloading ${URL}..."
  curl -sSL -o limine-binary.tar.gz "$URL"
  tar xzf limine-binary.tar.gz
  rm limine-binary.tar.gz
fi

make -C "$DIR"
```

`DIR`가 없을 때만 다운로드해 반복 실행 시 매번 다시 받지 않는다
(`kernel/build.sh`의 `if [ ! -d "$SRC_DIR" ]` 패턴과 동일). 릴리스 URL에
버전 태그가 그대로 박혀있으므로 이것만으로 재현성이 확보된다(release
tarball의 최상위 디렉터리 이름이 `limine-binary/`임을 2026-08-06에 직접
다운로드해 확인했다). `make -C "$DIR"`는 `limine-binary/Makefile`(`cc
-std=c99 limine.c -o limine`)을 실행해 host 도구 `limine`을 만든다 —
이미 다운로드되어 있어도 `make`는 산출물이 최신이면 다시 컴파일하지
않으므로 매번 실행해도 안전하다. `limine-bios.sys`, `limine-bios-cd.bin`
은 tarball 안에 이미 컴파일되어 들어있어 이 스크립트가 따로 만들
필요가 없다.

- [x] **Step 2: 실행 권한 확인**

```bash
chmod +x boot/build.sh
```

- [x] **Step 3: 실행해서 다운로드/빌드 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/boot \
  tars-devcontainer ./build.sh
```

Expected: 종료 코드 0. 다운로드 로그 뒤 `cc -std=c99 ... -o limine`
컴파일 명령이 출력되고 에러 없이 끝난다.

- [x] **Step 4: 산출물 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/boot \
  tars-devcontainer bash -c "ls -la limine-binary/limine-bios.sys limine-binary/limine-bios-cd.bin limine-binary/limine"
```

Expected: 세 파일 모두 존재하고 크기가 0보다 크다. `limine`은 실행
권한(`-rwxr-xr-x` 등)을 가진다.

- [x] **Step 5: 커밋**

```bash
git add boot/build.sh
git commit -m "Add Limine binary release download script"
```

`boot/limine-binary/`는 `.gitignore` 대상이라 커밋되지 않는다.

---

### Task 4: ISO 생성 스크립트

**Files:**
- Create: `boot/make_iso.sh`

- [x] **Step 1: `make_iso.sh` 작성**

`boot/make_iso.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LIMINE_BIN="limine-binary"
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

- [x] **Step 2: 실행 권한 확인**

```bash
chmod +x boot/make_iso.sh
```

- [x] **Step 3: kernel/init 산출물이 없으면 먼저 준비**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd kernel && ./build.sh && cd ../init && cargo build --release && cd ../kernel && ./make_initrd.sh"
```

Expected: 종료 코드 0. `kernel/build/arch/x86/boot/bzImage`와
`kernel/initrd.cpio`가 존재한다(이미 BF-M2에서 만들어져 있다면 이
Step은 최신 상태로 재생성만 한다).

- [x] **Step 4: ISO 생성 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/boot \
  tars-devcontainer ./make_iso.sh
```

Expected: 종료 코드 0. `xorriso` 로그에 경고 정도는 나올 수 있으나
에러로 중단되지 않는다.

- [x] **Step 5: ISO 파일 확인**

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

- [x] **Step 6: 커밋**

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
