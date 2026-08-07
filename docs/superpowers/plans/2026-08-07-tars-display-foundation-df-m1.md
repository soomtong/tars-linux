# TARS Display Foundation — DF-M1 PCI + DRM/virtio-gpu 드라이버 활성화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, HANDOFF.md 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** DF-M1을 완료한다 — kernel `.config`에서 `CONFIG_PCI`, `CONFIG_DRM`,
`CONFIG_DRM_VIRTIO_GPU`, `CONFIG_VIRTIO_PCI`를 활성화하고 재빌드하여, QEMU
`-device virtio-gpu-pci`를 붙여 부팅했을 때 커널이 드라이버를 통해 가상
GPU를 인식하고 `/dev/dri/card0` 노드가 devtmpfs에 생성됨을 확인한다.

**Architecture:** `kernel/.config`를 `scripts/config`(다운로드된 kernel
source tree에 포함된 표준 도구)로 직접 수정한 뒤 `kernel/build.sh`(이미
`make olddefconfig`를 실행함)로 재빌드한다. `init/src/main.rs`에
`/dev/dri/card0` 존재 여부를 devtmpfs mount 직후 serial 로그로 남기는 코드를
한 줄 추가해, 화면을 그리는 코드(DF-M2 이후) 없이도 드라이버가 실제로 노드를
만들었는지 non-interactive하게 검증할 수 있게 한다. 검증 스크립트
`kernel/check-virtio-gpu.sh`는 이 로그 줄을 grep해서 PASS/FAIL을 결정한다 —
정확한 커널 dmesg 문구는 커널 버전마다 달라질 수 있어 신뢰할 수 없지만, 우리가
직접 작성한 init 로그 문구는 우리가 정한 그대로 나오므로 확실한 판정 기준이
된다.

**Tech Stack:** Linux kernel 6.18.42 Kconfig(`scripts/config`), QEMU
`-device virtio-gpu-pci`, Rust(`init/`, 기존 `mount_fs` 패턴 재사용), bash
check 스크립트(기존 `kernel/check.sh` 스타일)

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행하며, 빌드 명령은 devcontainer 컨테이너 안에서 돈다. DF-M0가 완료돼
있어야 하고(`kernel/build/`, `kernel/src/linux-6.18.42/`, `init/target/`가
이미 존재), `tars-devcontainer` 이미지가 `imagemagick` 포함 버전으로 빌드돼
있어야 한다.

**현재 상태(2026-08-07 확인):** `kernel/.config`에서 `CONFIG_PCI`,
`CONFIG_DRM`, `CONFIG_FB`는 `# ... is not set`으로 존재하지만 꺼져 있고,
`CONFIG_DRM_VIRTIO_GPU`, `CONFIG_VIRTIO_PCI`, `CONFIG_VIRTIO`는 `CONFIG_PCI`가
꺼져 있어 아예 파일에 나타나지도 않는다(하위 옵션이라 상위 조건이 거짓이면
`olddefconfig`가 줄 자체를 만들지 않음). `CONFIG_DEVTMPFS`,
`CONFIG_DEVTMPFS_MOUNT`는 이미 `y`로 켜져 있다 — `init`이 이미 `/dev`에
devtmpfs를 mount하고 있으므로(`init/src/main.rs`), 드라이버가 성공적으로
probe하면 별도 udev 없이도 `/dev/dri/card0`가 자동으로 나타난다.

**Design doc과의 관계:**
[2026-08-07-tars-display-foundation-design.md](../specs/2026-08-07-tars-display-foundation-design.md)
DF-M1 절의 결정을 그대로 따른다 — kernel `.config` 변경과
`/dev/dri/card0`가 devtmpfs에 생성되는지 init 로그로 확인하는 것까지가
범위이고, 실제로 화면에 그리는 것(`kms/` 바이너리)은 DF-M2로 미룬다. design
doc의 "검증 방법" 절은 "DF-M1까지는 색상 대신 serial dmesg 로그 grep을 함께
쓴다"고 명시했다 — 이 plan의 `kernel/check-virtio-gpu.sh`가 그 grep이다.

---

### Task 1: kernel `.config`에서 PCI/DRM/virtio-gpu 옵션 활성화

**Files:**
- Modify: `kernel/.config`

- [ ] **Step 1: `scripts/config`로 옵션 활성화**

`scripts/config`는 다운로드된 kernel source tree(`kernel/src/linux-6.18.42/`)
안에 포함된 표준 스크립트로, `.config` 파일의 특정 옵션 값을 직접
켜고/끌 수 있다. `CONFIG_PCI`(PCI 버스 자체), `CONFIG_VIRTIO_MENU`(virtio
드라이버 서브메뉴 표시 여부 — 현재 꺼져 있어 하위 옵션이 안 보이는 원인),
`CONFIG_VIRTIO_PCI`(virtio 장치를 PCI 위에서 쓰는 transport — QEMU
`-device virtio-gpu-pci`가 바로 이 경로), `CONFIG_DRM`(그래픽 서브시스템),
`CONFIG_DRM_VIRTIO_GPU`(실제 드라이버) 다섯 개를 한 번에 켠다. 이 중
`CONFIG_VIRTIO_PCI`는 `CONFIG_DRM_VIRTIO_GPU`가 자동으로 딸려오게 하지
않는다 — virtio 장치는 PCI 외에 MMIO 등 다른 transport도 있어서
Kconfig가 자동으로 하나를 고르지 않기 때문에 명시적으로 켜야 한다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kernel \
  tars-devcontainer bash -c "src/linux-6.18.42/scripts/config --file .config \
    --enable PCI --enable VIRTIO_MENU --enable VIRTIO_PCI \
    --enable DRM --enable DRM_VIRTIO_GPU"
```

Expected: 출력 없이 종료 코드 0(`scripts/config`는 조용히 파일을 수정한다).

- [ ] **Step 2: 재빌드(olddefconfig + bzImage)**

`kernel/build.sh`는 `.config`를 `build/.config`로 복사한 뒤
`make olddefconfig`를 실행한다 — 이 과정에서 우리가 방금 켠 다섯 옵션이
서로 의존성을 만족시키므로(`PCI=y`가 있어야 `VIRTIO_PCI`가 보이고,
`DRM=y`가 있어야 `DRM_VIRTIO_GPU`가 보이는 식) `olddefconfig`가 우리가
지정한 값을 그대로 반영하면서 그 아래 숨은 의존 옵션들(예:
`DRM_KMS_HELPER`, `VIRTIO_DMA_SHARED_BUFFER`)도 자동으로 켠다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kernel \
  tars-devcontainer bash -c "./build.sh"
```

Expected: 종료 코드 0, 마지막 근처에 `Kernel: arch/x86/boot/bzImage is
ready`가 출력된다.

- [ ] **Step 3: 옵션이 실제로 `y`로 반영됐는지 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kernel \
  tars-devcontainer bash -c "grep -E '^CONFIG_(PCI|DRM|DRM_VIRTIO_GPU|VIRTIO_PCI)=' build/.config"
```

Expected: 아래 네 줄이 모두 출력된다(순서는 다를 수 있음):
```
CONFIG_PCI=y
CONFIG_DRM=y
CONFIG_DRM_VIRTIO_GPU=y
CONFIG_VIRTIO_PCI=y
```

**만약 어떤 줄이 `=m`으로 나오거나 아예 안 보이면:** Step 1의
`--enable`이 아니라 `--module`로 잘못 적용됐거나, 의존성이 아직 만족되지
않은 것이다. `--enable`은 `y`를 강제하므로 이 경우는 드물지만, 발생하면
`kernel/build/.config`에서 해당 옵션 주변 의존성 줄(`depends on` 계열)을
확인해서 알려달라 — 어떤 옵션이 더 필요한지 함께 판단한다.

- [ ] **Step 4: 정규화된 config를 `kernel/.config`로 복사**

`build.sh`가 실행한 `olddefconfig`는 `build/.config`만 갱신하고 원본
`kernel/.config`는 건드리지 않는다. 우리가 git에 커밋할 대상은
`kernel/.config`이므로, `olddefconfig`가 자동으로 채운 하위 의존 옵션까지
포함된 완전한 상태를 그대로 가져온다.

Run:
```bash
cp kernel/build/.config kernel/.config
```

- [ ] **Step 5: 변경 규모 확인**

Run:
```bash
git diff --stat kernel/.config
```

Expected: `kernel/.config | N ++++----` 형태로 변경된 줄 수가 나온다.
Step 1에서 지정한 다섯 옵션 외에도 `olddefconfig`가 함께 켠 하위 의존
옵션들이 있어서 몇십 줄 단위로 바뀌는 것이 정상이다.

- [ ] **Step 6: 커밋**

```bash
git add kernel/.config
git commit -m "Enable PCI, DRM, and virtio-gpu kernel config for DF-M1"
```

---

### Task 2: init에 `/dev/dri/card0` 존재 확인 로그 추가

**Files:**
- Modify: `init/src/main.rs`

- [ ] **Step 1: 존재 확인 함수 추가 및 호출**

지금 `init`은 `proc`/`sysfs`/`devtmpfs`를 mount하고 바로 fish로 exec한다
— 화면이나 DRM에 대해 아무것도 확인하지 않는다. DF-M1의 exit gate("
`/dev/dri/card0`가 존재")를 QEMU를 매번 대화형으로 붙여서 사람이 눈으로
확인하는 대신, devtmpfs mount 직후 `/dev/dri/card0`가 있는지 검사해서 serial
로그에 한 줄 남기도록 한다. 이 문구는 우리가 직접 정한 것이라 커널
버전마다 달라지는 dmesg 문구와 달리 항상 동일하게 나온다는 점이 grep
기반 자동 검증에 유리하다.

`init/src/main.rs`에서 `setup_controlling_terminal` 함수 앞에 새 함수를
추가한다:

```rust
fn log_drm_device_presence() {
    if std::path::Path::new("/dev/dri/card0").exists() {
        println!("tars-init: /dev/dri/card0 exists");
    } else {
        println!("tars-init: /dev/dri/card0 not found");
    }
}
```

그리고 `main()`에서 devtmpfs를 mount한 직후, `setup_controlling_terminal()`을
부르기 전에 호출을 추가한다:

```rust
fn main() {
    println!("tars-init: starting as PID 1");

    mount_fs("proc", "/proc", "proc");
    mount_fs("sysfs", "/sys", "sysfs");
    mount_fs("devtmpfs", "/dev", "devtmpfs");

    log_drm_device_presence();

    setup_controlling_terminal();

    let shell = CString::new("/usr/bin/fish").expect("CString::new failed");
    // ... (이하 기존 코드 그대로)
```

- [ ] **Step 2: 컴파일 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "cargo build --release"
```

Expected: 종료 코드 0, `Finished \`release\` profile [optimized] target(s)`가
출력된다. 에러 없이 컴파일되면 `std::path::Path::exists()` 호출이
문제없다는 뜻이다(별도 crate 의존성 추가 불필요 — `std`에 포함됨).

- [ ] **Step 3: initrd 재생성**

새로 빌드한 `tars-init` 바이너리를 initrd에 반영한다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kernel \
  tars-devcontainer bash -c "./make_initrd.sh"
```

Expected: 종료 코드 0, `N blocks` 형태의 줄이 출력되고
`kernel/initrd.cpio`의 수정 시각이 갱신된다.

- [ ] **Step 4: 커밋**

```bash
git add init/src/main.rs kernel/initrd.cpio
git commit -m "Log /dev/dri/card0 presence from init for DF-M1 verification"
```

---

### Task 3: `kernel/check-virtio-gpu.sh` — 드라이버 probe 검증

**Files:**
- Create: `kernel/check-virtio-gpu.sh`

- [ ] **Step 1: 검증 스크립트 작성**

기존 `kernel/check.sh`(fish 배너 grep)와 같은 구조이되, `-device
virtio-gpu-pci`를 붙이고 `/dev/dri/card0 exists` 로그를 grep한다. `-vga
none`으로 QEMU 기본 VGA 어댑터를 빼서 `virtio-gpu-pci`만 화면 장치로
남기는 것은 `display/check.sh`(DF-M0)와 동일한 이유다.

`kernel/check-virtio-gpu.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

LOG="$(mktemp)"
timeout 15 qemu-system-x86_64 \
  -kernel build/arch/x86/boot/bzImage \
  -initrd initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "tars-init: /dev/dri/card0 exists" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: /dev/dri/card0 was not found by tars-init"
exit 1
```

`cat "$LOG"`가 항상 전체 로그를 먼저 출력하므로, PASS/FAIL 판정과
별개로 커널이 실제로 어떤 virtio-gpu/DRM 관련 dmesg 줄을 남겼는지 눈으로
확인할 수 있다 — design doc이 요구하는 "serial(dmesg)에 virtio-gpu
드라이버 probe 성공 로그가 보이고"는 이 출력으로 사람이 직접 확인하고,
자동 PASS/FAIL 판정 자체는 우리가 제어하는 `/dev/dri/card0 exists` 문구로
한다.

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x kernel/check-virtio-gpu.sh
```

- [ ] **Step 3: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/check-virtio-gpu.sh
```

Expected: 커널 부팅 로그(dmesg)와 `tars-init: ...` 줄들이 출력되고, 그 중
`tars-init: /dev/dri/card0 exists`가 포함되며, 마지막에 `PASS`와 종료
코드 0.

**만약 `FAIL: /dev/dri/card0 was not found`이 나오면:** 출력된 전체 로그를
붙여서 알려달라. 확인할 지점은 두 가지다.
1. PCI 장치 자체가 열거됐는지 — dmesg에서 `virtio-pci` 또는 `0000:00:`로
   시작하는 PCI 장치 인식 줄이 있는지 찾는다. 없다면 `CONFIG_PCI`가 실제로
   `y`인지(Task 1 Step 3) 다시 확인한다.
2. 장치는 열거됐지만 드라이버가 안 붙었는지 — 이 경우 `CONFIG_ACPI`처럼
   PCI 인터럽트 라우팅에 필요한 옵션이 추가로 필요할 수 있다. 이때는
   `kernel/.config`에서 `CONFIG_ACPI` 상태를 확인하고 필요하면 Task 1과
   같은 방식(`scripts/config --enable ACPI` + 재빌드)으로 추가한다.

- [ ] **Step 4: 커밋**

```bash
git add kernel/check-virtio-gpu.sh
git commit -m "Add DF-M1 check-virtio-gpu.sh for driver probe verification"
```

---

## DF-M1 완료 확인

Task 3의 Step 3이 `PASS`로 끝나고, 출력된 로그에서 `tars-init:
/dev/dri/card0 exists`와 함께 virtio-gpu/DRM 관련 dmesg 줄이 눈으로
확인되면 design doc 기준 DF-M1의 exit gate를 만족한다. 이 시점에서
DF-M2(픽셀 그리기 — `kms/` Rust 바이너리로 DRM ioctl 호출) plan을 별도로
작성한다.
