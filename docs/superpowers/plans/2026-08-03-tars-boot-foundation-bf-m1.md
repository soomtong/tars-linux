# TARS Boot Foundation — BF-M1 Minimal Kernel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** BF-M1을 완료한다 — kernel.org의 최신 LTS(6.18.42) 소스를 devcontainer
안에서 받아 `allnoconfig`에서 시작한 x86_64 `.config`로 최소 kernel을
빌드하고, QEMU가 `-kernel`/`-initrd`(빈 cpio)로 부팅해
`Kernel panic - not syncing: No working init found`를 내는 지점까지
검증한다.

**Architecture:** `devcontainer/Dockerfile`에 kernel 빌드 의존성(`flex`,
`bison`, `bc`, `libssl-dev`, `libelf-dev`)을 추가한다. `kernel/build.sh`가
소스 다운로드(curl)·압축 해제·빌드를 담당하고, `kernel/.config`는
`allnoconfig`에서 시작해 반복적으로 옵션을 켜 나간 결과를 커밋한다.
`kernel/initrd.cpio`는 완전히 빈 cpio(newc) 아카이브로, init 바이너리가
없다는 사실만 kernel에 알려주는 역할을 한다. `kernel/check.sh`가 BF-M0의
`check.sh`와 동일한 빌드→실행→grep→PASS/FAIL 패턴으로 exit gate를
검증한다.

**Tech Stack:** Debian bookworm-slim devcontainer(BF-M0에서 확장), Linux
6.18.42 소스, GNU make/kconfig, QEMU system x86_64(TCG), cpio, bash

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행하며, 대부분 devcontainer 컨테이너 안에서 실행한다(`docker run`으로
감싸는 커맨드는 명시적으로 표기). BF-M0의 `tars-devcontainer` 이미지가
빌드되어 있어야 한다(없다면 Task 1의 재빌드 스텝이 새로 만든다).

**Design doc과의 관계:**
[2026-08-03-tars-boot-foundation-bf-m1-design.md](../specs/2026-08-03-tars-boot-foundation-bf-m1-design.md)의
결정을 그대로 따른다 — kernel 6.18.42, x86_64, `allnoconfig`에서 반복
확장, 빈 initrd로 "No working init found" 재현.

---

### Task 1: devcontainer에 kernel 빌드 의존성 추가

**Files:**
- Modify: `devcontainer/Dockerfile`

- [x] **Step 1: Dockerfile에 패키지 추가**

`devcontainer/Dockerfile`의 `apt-get install` 목록에 다음을 추가한다
(기존 `build-essential`, `gcc-multilib`, `binutils`, `qemu-system-x86`,
`git`, `ca-certificates`는 유지):

```dockerfile
FROM --platform=linux/amd64 debian:bookworm-slim

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
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
```

`flex`/`bison`은 kconfig 파서와 커널 빌드 스크립트가 사용하고, `bc`는
커널 빌드의 일부 스크립트(`kernel/timeconst.bc` 등)가 필요로 하며,
`libssl-dev`/`libelf-dev`는 커널 모듈 서명·BTF 관련 빌드 단계가 참조한다.
`curl`은 소스 다운로드용, `cpio`는 initrd 생성용, `rsync`는
`make headers_install` 등 일부 커널 빌드 타깃이 사용한다.

- [x] **Step 2: 이미지 재빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0. `Successfully tagged tars-devcontainer:latest` 또는
`naming to docker.io/library/tars-devcontainer:latest done`.

- [x] **Step 3: 의존성 확인**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer \
  bash -c "flex --version && bison --version && bc --version && curl --version && cpio --version"
```

Expected: 다섯 명령 모두 버전 문자열을 출력하고 `command not found` 없음.

- [x] **Step 4: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Add kernel build dependencies to devcontainer"
```

---

### Task 2: kernel 소스 다운로드 스크립트

**Files:**
- Create: `kernel/build.sh`
- Modify: `.gitignore`

- [x] **Step 1: `.gitignore`에 소스 디렉터리 추가**

`.gitignore`에 다음 줄을 추가한다:

```
kernel/src/
kernel/build/
```

`kernel/src/`는 압축 해제된 kernel.org 소스(수백MB), `kernel/build/`는
빌드 산출물(`bzImage` 등)이 위치할 디렉터리다. 둘 다 재현 가능한
산출물이므로 git에는 스크립트와 `.config`만 남긴다.

- [x] **Step 2: `build.sh` 작성**

`kernel/build.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

KERNEL_VERSION="6.18.42"
KERNEL_MAJOR="6.x"
TARBALL="linux-${KERNEL_VERSION}.tar.xz"
URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}/${TARBALL}"
SRC_DIR="src/linux-${KERNEL_VERSION}"

if [ ! -d "$SRC_DIR" ]; then
  echo "Downloading ${URL}..."
  mkdir -p src
  curl -sSL -o "src/${TARBALL}" "$URL"
  tar -C src -xf "src/${TARBALL}"
  rm "src/${TARBALL}"
fi

mkdir -p build
cp .config build/.config

MAKE_ARGS=(-C "$SRC_DIR" O=../../build ARCH=x86_64)

make "${MAKE_ARGS[@]}" olddefconfig
make "${MAKE_ARGS[@]}" -j"$(nproc)" bzImage
```

`O=../../build`로 빌드 산출물을 소스 트리 밖(`kernel/build/`)에 분리해,
소스 트리 자체는 깨끗하게 유지한다. kbuild는 out-of-tree 빌드 시
`.config`를 소스 트리가 아니라 `O=` 디렉터리에서 찾으므로, 커밋된
`kernel/.config`를 `build/.config`로 복사해야 한다(소스 트리로 복사하면
무시된다). `olddefconfig`는 그 `.config`를 현재 커널 버전 기준으로
정규화한다(새 옵션에 기본값을 채워 넣음) — `allnoconfig`로 시작했으므로
새 옵션의 기본값은 대부분 `n`이 된다.

```bash
chmod +x kernel/build.sh
```

- [x] **Step 3: 커밋**

```bash
git add .gitignore kernel/build.sh
git commit -m "Add kernel source download and build script"
```

---

### Task 3: allnoconfig에서 시작하는 초기 `.config`

**Files:**
- Create: `kernel/.config`

- [x] **Step 1: 소스를 받고 allnoconfig 생성**

`build.sh`는 `.config`가 이미 있다고 가정하므로, 아직 없는 지금은
컨테이너 안에서 소스만 받고 `allnoconfig`를 직접 실행한다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kernel \
  tars-devcontainer bash -c '
    set -euo pipefail
    KERNEL_VERSION="6.18.42"
    URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
    mkdir -p src
    curl -sSL -o "src/linux-${KERNEL_VERSION}.tar.xz" "$URL"
    tar -C src -xf "src/linux-${KERNEL_VERSION}.tar.xz"
    rm "src/linux-${KERNEL_VERSION}.tar.xz"
    make -C "src/linux-${KERNEL_VERSION}" O=../../build ARCH=x86_64 allnoconfig
    cp build/.config .config
  '
```

Expected: 종료 코드 0. `kernel/.config`가 생성되고, 첫 줄 근처에
`CONFIG_64BIT`가 `# CONFIG_64BIT is not set` 또는 유사한 allnoconfig
기본값으로 나타난다(x86_64 아키텍처 자체는 `ARCH=x86_64`로 고정되므로
64bit 빌드가 됨 — 이 옵션은 Task 4에서 확인·조정한다).

- [x] **Step 2: `.config`에 64BIT 명시적으로 켜기**

`kernel/.config`를 열어 `CONFIG_64BIT` 관련 줄을 찾아 다음으로
바꾼다(없으면 파일 끝에 추가):

```
CONFIG_64BIT=y
```

- [x] **Step 3: 커밋**

```bash
git add kernel/.config
git commit -m "Add allnoconfig baseline for kernel .config"
```

---

### Task 4: 빈 initrd와 QEMU 부팅 검증 스크립트

**Files:**
- Create: `kernel/make_initrd.sh`
- Create: `kernel/check.sh`

- [x] **Step 1: 빈 initrd 생성 스크립트**

**BF-M1 실행 중 정정(design doc 참고):** 완전히 빈 cpio는 커널이
initramfs 자체를 포기하고 `VFS: Unable to mount root fs`로 panic해버려
목표(`No working init found`)에 도달하지 못한다. 실행 권한만 있고
내용은 빈 `/init` 파일 하나를 담아야 한다.

`kernel/make_initrd.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

WORKDIR="$(mktemp -d)"
touch "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"
(cd "$WORKDIR" && echo init | cpio -o -H newc) > initrd.cpio
rm -rf "$WORKDIR"
```

```bash
chmod +x kernel/make_initrd.sh
```

- [x] **Step 2: check.sh 작성 (아직 실패하는 상태로)**

`kernel/check.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./build.sh
./make_initrd.sh

LOG="$(mktemp)"
timeout 15 qemu-system-x86_64 \
  -kernel build/arch/x86/boot/bzImage \
  -initrd initrd.cpio \
  -append "console=ttyS0" \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "Kernel panic - not syncing: No working init found" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected panic message not found"
exit 1
```

```bash
chmod +x kernel/check.sh
```

- [x] **Step 3: 실행해서 실패 지점 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/check.sh
```

Expected: FAIL. 이 시점에서는 `allnoconfig`가 콘솔/initrd 관련 옵션을
대부분 꺼두었으므로, QEMU serial 로그가 비어있거나 극히 짧고 예상 panic
메시지가 나오지 않는다. 로그 내용을 확인해 다음에 켜야 할 옵션을
판단한다(예: 로그가 완전히 비어있으면 `CONFIG_SERIAL_8250_CONSOLE`이
꺼져 있을 가능성이 높음).

- [x] **Step 4: 커밋**

```bash
git add kernel/make_initrd.sh kernel/check.sh
git commit -m "Add initrd generation and boot check scripts"
```

---

### Task 5: 콘솔 출력이 나올 때까지 `.config` 반복 확장

**Files:**
- Modify: `kernel/.config`

- [x] **Step 1: 콘솔 관련 옵션 켜기**

`kernel/.config`에 다음 줄을 추가한다(기존에 `# CONFIG_X is not set`
형태로 있으면 그 줄을 지우고 아래로 교체):

```
CONFIG_PRINTK=y
CONFIG_TTY=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
```

- [x] **Step 2: 재실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/check.sh
```

Expected: 여전히 FAIL일 수 있지만, 이번에는 QEMU serial 로그에 실제
kernel boot 메시지(`Linux version 6.18.42 ...`로 시작하는 줄들)가
나타난다. 로그 마지막 부분을 읽고 다음 실패 원인을 판단한다 — 전형적으로
`VFS: Unable to mount root fs` 계열 메시지가 나오면 `CONFIG_BLK_DEV_INITRD`
확인 단계(Step 3)로, 이미 root는 mount됐는데 다른 이유로 멈추면 그 로그를
근거로 원인 옵션을 추가로 조사한다.

- [x] **Step 3: initrd/devtmpfs/binfmt 옵션 켜기**

`kernel/.config`에 추가:

```
CONFIG_BLK_DEV_INITRD=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
```

- [x] **Step 4: 재실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/check.sh
```

Expected: PASS. serial 로그에 kernel boot 메시지와
`Kernel panic - not syncing: No working init found`가 출력되고, 스크립트
마지막 줄에 `PASS`, 종료 코드 0.

**만약 여전히 FAIL이면:** 로그 마지막 20줄을 읽고 어떤 파일/기능을 kernel이
찾지 못했는지 확인한 뒤, 해당 `CONFIG_*` 옵션을 `kernel/.config`에 추가하고
Step 4를 반복한다. 이 반복 자체가 design doc이 의도한 학습 사이클이므로,
몇 차례 반복이 필요할 수 있다.

- [x] **Step 5: 커밋**

```bash
git add kernel/.config
git commit -m "Add console and initrd config options to reach init panic"
```

---

## BF-M1 완료 확인

Task 5의 Step 4가 PASS로 끝나면 BF-M1의 exit gate(design doc 기준: QEMU
serial 출력에서 `Kernel panic - not syncing: No working init found` 확인)를
만족한다. 이 시점에서 BF-M2(Rust로 직접 만든 init) plan을 별도로 작성한다
— PID 1 구현과 initramfs 실제 구성은 이번 빈 initrd 검증과 무관한 새
학습 사이클이므로 여기 포함하지 않는다.
