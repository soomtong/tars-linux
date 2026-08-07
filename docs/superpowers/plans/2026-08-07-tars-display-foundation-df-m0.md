# TARS Display Foundation — DF-M0 Verification Pipeline Sanity Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, HANDOFF.md 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** DF-M0를 완료한다 — DRM 드라이버 없이도 QEMU `-device
virtio-gpu-pci`를 붙여 부팅하고, QEMU monitor `screendump` → PPM → 
ImageMagick으로 이어지는 검증 파이프라인이 실제로 동작함을 확인한다. 이후
DF-M1~M3에서 이 파이프라인을 그대로 재사용해 색상 검사까지 확장한다.

**Architecture:** devcontainer에 `imagemagick`을 추가하고, 새 최상위
디렉터리 `display/`에 `check.sh`를 만든다. 이 스크립트는 기존
`kernel/build.sh` + `init` cargo build + `kernel/make_initrd.sh`로 만든
kernel/initrd를 그대로 재사용해(design doc대로 DF-M0는 kernel `.config`를
건드리지 않음) `-vga none -device virtio-gpu-pci -monitor
tcp:127.0.0.1:<port>,server,nowait`로 QEMU를 백그라운드 실행하고, bash
내장 `/dev/tcp`로 monitor에 접속해 `screendump` 명령을 보낸 뒤 생성된 PPM을
ImageMagick(`identify`, 버전에 따라 `magick identify`)으로 읽어 해상도가
파싱되는지 확인한다.

**Tech Stack:** QEMU system x86_64(TCG, SeaBIOS, virtio-gpu-pci), bash
(`/dev/tcp` 내장 기능), ImageMagick(`identify`/`magick`), 기존
kernel/init 산출물(BF-M0~M4 결과물, 수정 없음)

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행하며, 빌드·실행 명령은 devcontainer 컨테이너 안에서 돈다. Boot
Foundation이 완료되어 있어야 하고(`kernel/build.sh`, `init/`,
`kernel/make_initrd.sh`가 정상 동작), `tars-devcontainer` 이미지가 이미
빌드돼 있어야 한다.

**Design doc과의 관계:**
[2026-08-07-tars-display-foundation-design.md](../specs/2026-08-07-tars-display-foundation-design.md)
DF-M0 절의 결정을 그대로 따른다 — kernel `.config`/드라이버는 건드리지
않고, 검증 파이프라인(`/dev/tcp` + monitor + screendump + ImageMagick)
자체가 동작하는지만 확인한다. 색상 검사는 DF-M1(드라이버) 이후로 미룬다.
design doc의 "저장소 구조" 절은 `kms/`, `kernel/`, `init/`, `devcontainer/`
만 언급했지만, 검증 스크립트가 놓일 곳이 없어 이 plan에서 `display/`
디렉터리를 새로 추가한다 — design doc이 "세부 디렉터리는 구현 단계에서
조정될 수 있다"고 명시한 범위 안의 결정이다.

---

### Task 1: devcontainer에 ImageMagick 추가

**Files:**
- Modify: `devcontainer/Dockerfile`

- [x] **Step 1: Dockerfile apt 목록에 imagemagick 추가**

`devcontainer/Dockerfile`의 `apt-get install` 목록 끝에 `imagemagick`을
추가한다(기존 목록 순서 유지):

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
        imagemagick \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
        -y --default-toolchain stable --profile minimal \
        --target x86_64-unknown-linux-gnu

WORKDIR /workspace
```

- [x] **Step 2: 이미지 재빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0. `Successfully tagged tars-devcontainer:latest` 또는
`naming to docker.io/library/tars-devcontainer:latest done`.

- [x] **Step 3: ImageMagick 명령 확인(버전 확인 겸 어느 명령이 있는지 확인)**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer \
  bash -c "command -v magick && magick -version || (command -v identify && identify -version)"
```

Expected: `command not found` 없이 버전 문자열이 출력된다. Debian
trixie의 `imagemagick` 패키지가 통합 명령 `magick`을 제공하는지, 아니면
`identify`/`convert` 같은 개별 명령만 제공하는지가 여기서 결정된다 —
Task 2의 `display/check.sh`는 두 경우 모두 동작하도록 작성하므로 이 Step의
결과를 특별히 다른 곳에 반영할 필요는 없다(참고용 확인).

- [x] **Step 4: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Add imagemagick to devcontainer"
```

---

### Task 2: `display/check.sh` — screendump 파이프라인 검증

**Files:**
- Create: `display/check.sh`

- [x] **Step 1: `display/check.sh` 작성**

`display/check.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

MONITOR_PORT=45454
SCREENSHOT="$(mktemp /tmp/df-m0-XXXXXX.ppm)"
LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

MONITOR_READY=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then
    MONITOR_READY=1
    break
  fi
  sleep 0.5
done

if [ "$MONITOR_READY" != "1" ]; then
  echo "FAIL: could not connect to QEMU monitor on port ${MONITOR_PORT}"
  cat "$LOG"
  exit 1
fi

# virtio-gpu가 기본 scanout을 초기화할 시간을 준다(경험적으로 선택한 값 —
# Step 3에서 FAIL이면 가장 먼저 늘려볼 값).
sleep 3
echo "screendump ${SCREENSHOT}" >&3
sleep 1
exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$SCREENSHOT" ]; then
  echo "FAIL: screendump did not produce a file at ${SCREENSHOT}"
  cat "$LOG"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IDENTIFY=(magick identify)
else
  IDENTIFY=(identify)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$SCREENSHOT" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${SCREENSHOT}: ${DIMENSIONS}"
  exit 1
}

echo "Captured screendump: ${SCREENSHOT} (${DIMENSIONS})"

if [[ "$DIMENSIONS" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "PASS"
  exit 0
fi

echo "FAIL: unexpected ImageMagick output: ${DIMENSIONS}"
exit 1
```

`set -e`를 쓰지 않는 이유는 BF-M4의 루트 `check.sh`와 동일하다 — 각 실패
지점에서 원인을 담은 메시지를 직접 출력하고 싶어서다. `trap cleanup EXIT`는
스크립트가 어느 경로로 끝나든(성공/실패/중간 오류) 백그라운드로 띄운 QEMU
프로세스가 항상 정리되도록 한다. `-vga none`은 QEMU가 기본으로 붙이는 VGA
어댑터를 빼서 `virtio-gpu-pci` 하나만 화면 장치로 남긴다. `IDENTIFY` 배열은
Task 1 Step 3에서 확인한 대로 ImageMagick 7의 통합 명령(`magick identify`)과
6의 개별 명령(`identify`)을 모두 지원하기 위한 것이다.

- [x] **Step 2: 실행 권한 부여**

```bash
chmod +x display/check.sh
```

- [x] **Step 3: kernel/init 산출물이 없으면 먼저 준비**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd kernel && ./build.sh && cd ../init && cargo build --release && cd ../kernel && ./make_initrd.sh"
```

Expected: 종료 코드 0. `kernel/build/arch/x86/boot/bzImage`와
`kernel/initrd.cpio`가 존재한다(BF-M4에서 이미 만들어져 있다면 이 Step은
최신 상태로 재생성만 한다).

- [x] **Step 4: 실행해서 파이프라인 검증**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash display/check.sh
```

Expected: `Captured screendump: /tmp/df-m0-XXXXXX.ppm (WxH)` 형태의 줄
(`W`, `H`는 0보다 큰 정수)과 `PASS`가 출력되고 종료 코드 0. 드라이버가
아직 없으므로 화면 내용 자체(색상)는 의미가 없다 — PPM 파일이 유효한
해상도로 만들어졌다는 것만 확인한다.

**만약 `FAIL: could not connect to QEMU monitor`가 나오면:** 포트
`45454`가 컨테이너 안에서 이미 쓰이고 있을 수 있다(드물지만 재실행 시
이전 프로세스가 남아있는 경우) — 스크립트의 `MONITOR_PORT` 값을 다른
숫자로 바꿔 다시 실행한다.

**만약 `FAIL: screendump did not produce a file`이 나오면:** `$LOG`
내용(스크립트가 함께 출력한다)에서 QEMU가 `-device virtio-gpu-pci`를
인식하지 못하고 에러로 종료했는지 확인한다 — `qemu-system-x86_64
-device virtio-gpu-pci -display none -vga none -S -monitor none
/dev/null` 같은 최소 커맨드로 이 컨테이너의 QEMU 빌드가 `virtio-gpu-pci`
디바이스를 지원하는지 별도로 확인해본다(`-device help`에
`virtio-gpu-pci`가 나열되는지).

**만약 `FAIL: unexpected ImageMagick output`이 나오면:** `sleep 3` 값을
늘려 virtio-gpu 디바이스 초기화 시간을 더 준 뒤 다시 실행한다.

- [x] **Step 5: 커밋**

```bash
git add display/check.sh
git commit -m "Add DF-M0 check.sh for screendump pipeline verification"
```

---

## DF-M0 완료 확인

Task 2의 Step 4가 `PASS`로 끝나면 design doc 기준 DF-M0의 exit gate(PPM
파일이 기대한 해상도로 생성되고 ImageMagick으로 읽힘)를 만족한다. 이
시점에서 DF-M1(PCI + DRM/virtio-gpu 드라이버 활성화) plan을 별도로
작성한다.
