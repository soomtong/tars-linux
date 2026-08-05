# TARS Boot Foundation — BF-M2 Rust Init Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** BF-M2를 완료한다 — Rust로 작성한 init 바이너리가 PID 1로 실행되어
`/proc`, `/sys`, `/dev`(devtmpfs)를 mount한 뒤 fish로 자신을 대체(execve)해
QEMU serial에 fish의 시작 배너(`Welcome to fish, the friendly interactive
shell`)가 출력되는 지점까지 검증한다.

**Architecture:** `init/`에 독립된 Rust 바이너리 프로젝트를 만든다.
`x86_64-unknown-linux-gnu` 타깃(std, glibc 동적 링크)으로 빌드하고, `libc`
crate로 `mount(2)`/`execve(2)`를 raw FFI로 직접 호출한다. `kernel/
make_initrd.sh`를 확장해 init 바이너리, fish 바이너리, 둘의 `ldd` 의존
라이브러리, fish가 필요로 하는 terminfo 엔트리(`/usr/lib/terminfo/l/
linux`)를 하나의 cpio(newc) initramfs로 묶는다. `kernel/check.sh`는
BF-M1과 동일한 빌드→부팅→grep→PASS/FAIL 패턴을 유지하되 판정 문자열만
바꾼다.

**Tech Stack:** Rust stable(rustup, `x86_64-unknown-linux-gnu`), `libc`
crate, fish 3.6.0(Debian bookworm apt), Linux 6.18.42(BF-M1에서 빌드됨),
QEMU system x86_64(TCG), cpio, bash

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행하며, 빌드·실행 명령은 devcontainer 컨테이너 안에서 돈다(`docker run`
으로 감싸는 커맨드는 명시적으로 표기). BF-M1까지 완료되어 `kernel/build.sh`,
`kernel/.config`, `kernel/build/arch/x86/boot/bzImage`가 이미 존재해야
한다(없다면 Task 5에서 `check.sh`가 `build.sh`를 호출해 새로 빌드한다).

**Design doc과의 관계:**
[2026-08-04-tars-boot-foundation-bf-m2-design.md](../specs/2026-08-04-tars-boot-foundation-bf-m2-design.md)
의 결정을 그대로 따른다 — std+glibc 동적 링크, `libc` crate raw FFI,
fish(bash 아님) + terminfo 파일 포함, timeout 강제 종료 + 배너 grep.

---

### Task 1: devcontainer에 Rust 툴체인과 fish 추가

**Files:**
- Modify: `devcontainer/Dockerfile`

- [ ] **Step 1: Dockerfile에 rustup 설치와 fish 패키지 추가**

`devcontainer/Dockerfile` 전체를 다음으로 교체한다:

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
        fish \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
        -y --default-toolchain stable --profile minimal \
        --target x86_64-unknown-linux-gnu

WORKDIR /workspace
```

`fish`는 `--no-install-recommends`로 설치해도 `fish-common`이 `python3`,
`man-db` 등을 끌어오지만, 이는 devcontainer 안에서 `/usr/bin/fish`와 그
라이브러리를 추출해 오기 위한 소스일 뿐 initramfs에는 담지 않는다(Task 4
참고). rustup은 `--profile minimal`로 `rustc`/`cargo`/`rust-std`만
설치해 이미지 크기를 줄인다.

- [ ] **Step 2: 이미지 재빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0. `Successfully tagged tars-devcontainer:latest` 또는
`naming to docker.io/library/tars-devcontainer:latest done`.

- [ ] **Step 3: 툴체인 확인**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer \
  bash -c "rustc --version && cargo --version && fish --version"
```

Expected: 세 명령 모두 버전 문자열을 출력하고 `command not found` 없음
(예: `rustc 1.8x.x`, `cargo 1.8x.x`, `fish, version 3.6.0`).

- [ ] **Step 4: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Add Rust toolchain and fish shell to devcontainer"
```

---

### Task 2: Rust init 프로젝트 뼈대

**Files:**
- Create: `init/Cargo.toml`
- Create: `init/src/main.rs`
- Modify: `.gitignore`

- [ ] **Step 1: `.gitignore`에 Rust 빌드 산출물 추가**

`.gitignore`에 다음 줄을 추가한다:

```
init/target/
```

- [ ] **Step 2: `Cargo.toml` 작성**

`init/Cargo.toml`:
```toml
[package]
name = "tars-init"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"
```

- [ ] **Step 3: 최소 `main.rs` 작성**

`init/src/main.rs`:
```rust
fn main() {
    println!("tars-init: starting as PID 1");
}
```

이 시점에는 PID 1 시작 로그만 찍는다 — mount/execve는 Task 3에서 추가한다.
먼저 "Rust 프로젝트가 devcontainer에서 빌드되고, 동적 링크된 ELF가
나온다"는 것부터 확인한다.

- [ ] **Step 4: 빌드 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer cargo build --release
```

Expected: 종료 코드 0. `Compiling tars-init v0.1.0 ...`, `Finished
release [optimized] target(s) in ...`. `init/target/release/tars-init`
파일이 생성된다.

- [ ] **Step 5: 동적 링크 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "file target/release/tars-init && ldd target/release/tars-init"
```

Expected: `file` 출력에 `ELF 64-bit LSB pie executable, x86-64 ...
dynamically linked`가 포함됨. `ldd` 출력에 `libc.so.6`과
`/lib64/ld-linux-x86-64.so.2`가 보임 — design doc 핵심 결정 1이 의도한
대로 init 자신도 glibc 동적 링크임을 확인하는 지점이다.

- [ ] **Step 6: 커밋**

```bash
git add .gitignore init/Cargo.toml init/Cargo.lock init/src/main.rs
git commit -m "Add minimal Rust init skeleton"
```

`Cargo.lock`은 Step 4의 `cargo build`가 생성한다. 바이너리 프로젝트이므로
`libc` crate의 정확한 버전을 고정하기 위해 커밋한다(라이브러리
crate였다면 커밋하지 않는 것이 관례지만, init은 최종 실행 바이너리다).

---

### Task 3: mount 3회 + execve로 fish 실행

**Files:**
- Modify: `init/src/main.rs`

- [ ] **Step 1: mount와 execve 로직 작성**

`init/src/main.rs` 전체를 다음으로 교체한다:

```rust
use std::ffi::CString;
use std::ptr;

fn mount_fs(source: &str, target: &str, fstype: &str) {
    let source_c = CString::new(source).expect("CString::new failed");
    let target_c = CString::new(target).expect("CString::new failed");
    let fstype_c = CString::new(fstype).expect("CString::new failed");

    let ret = unsafe {
        libc::mount(
            source_c.as_ptr(),
            target_c.as_ptr(),
            fstype_c.as_ptr(),
            0,
            ptr::null(),
        )
    };

    if ret == 0 {
        println!("tars-init: mounted {} at {}", fstype, target);
    } else {
        let errno = unsafe { *libc::__errno_location() };
        println!(
            "tars-init: failed to mount {} at {} (errno {})",
            fstype, target, errno
        );
    }
}

fn main() {
    println!("tars-init: starting as PID 1");

    mount_fs("proc", "/proc", "proc");
    mount_fs("sysfs", "/sys", "sysfs");
    mount_fs("devtmpfs", "/dev", "devtmpfs");

    let shell = CString::new("/usr/bin/fish").expect("CString::new failed");
    let argv: [*const libc::c_char; 2] = [shell.as_ptr(), ptr::null()];

    unsafe {
        libc::execve(
            shell.as_ptr(),
            argv.as_ptr(),
            libc::environ as *const *const libc::c_char,
        );
    }

    // execve가 성공하면 이 아래 코드는 실행되지 않는다(프로세스 이미지 자체가
    // 대체되므로). 여기 도달했다는 것은 execve가 실패했다는 뜻이다.
    let errno = unsafe { *libc::__errno_location() };
    eprintln!("tars-init: execve failed (errno {})", errno);
}
```

`mount(2)`는 성공 시 `0`, 실패 시 `-1`을 반환하고 `errno`에 원인을 남긴다
(design doc 핵심 결정 3: 실패해도 나머지 mount는 계속 진행). `execve(2)`는
성공하면 반환하지 않는다 — 반환했다는 것 자체가 실패 신호다.
`libc::environ`은 `libc` crate가 이미 선언해 둔 전역 `char **environ`
포인터로, 현재 프로세스의 환경변수를 그대로 fish에 넘기기 위해 사용한다.

- [ ] **Step 2: 빌드 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer cargo build --release
```

Expected: 종료 코드 0, `Finished release [optimized] target(s)`.

- [ ] **Step 3: 커밋**

```bash
git add init/src/main.rs
git commit -m "Implement mount and execve in Rust init"
```

---

### Task 4: initramfs에 init/fish/라이브러리/terminfo 담기

**Files:**
- Modify: `kernel/make_initrd.sh`

- [ ] **Step 1: `make_initrd.sh`를 실제 바이너리 패키징 스크립트로 교체**

BF-M1의 `make_initrd.sh`는 실행 권한만 있는 빈 `/init` 파일 하나만
담았다(커널의 "init 존재 확인 vs 실행 성공" 판단 로직을 통과시키기 위한
최소 유인책). 이제 실제 init 바이너리와 fish, 그 의존성을 담도록 전체
교체한다.

`kernel/make_initrd.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

copy_lib_deps() {
  local bin="$1"
  local lib
  for lib in $(ldd "$bin" | grep -oE '/[^ ]+\.so[0-9.]*'); do
    mkdir -p "$WORKDIR$(dirname "$lib")"
    cp -n "$lib" "$WORKDIR$lib"
  done
}

mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev"

cp ../init/target/release/tars-init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

cp /usr/bin/fish "$WORKDIR/usr/bin/fish"
chmod 0755 "$WORKDIR/usr/bin/fish"

copy_lib_deps "$WORKDIR/init"
copy_lib_deps "$WORKDIR/usr/bin/fish"

mkdir -p "$WORKDIR/usr/lib/terminfo/l"
cp /usr/lib/terminfo/l/linux "$WORKDIR/usr/lib/terminfo/l/linux"

(cd "$WORKDIR" && find . | cpio -o -H newc) > initrd.cpio
```

`copy_lib_deps`는 `ldd`의 두 출력 형태를 모두 처리한다: `이름 => /경로/
파일.so.N (주소)`와 동적 링커 자신을 가리키는 `/lib64/ld-linux-
x86-64.so.2 (주소)`. `grep -oE '/[^ ]+\.so[0-9.]*'`는 두 형태 모두에서
절대경로만 추출한다. `cp -n`(no-clobber)으로 init과 fish가 공유하는
라이브러리(`libc.so.6`, 동적 링커 등)를 중복 복사하지 않는다.

`mkdir -p "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev"`로 Task 3의
`mount_fs`가 호출할 mount point 디렉터리를 미리 만들어 둔다 — `mount(2)`
는 target 디렉터리가 이미 존재해야 성공하며, initramfs cpio 안에 없으면
커널이 자동으로 만들어주지 않는다.

- [ ] **Step 2: 실행 권한 확인**

```bash
chmod +x kernel/make_initrd.sh
```

- [ ] **Step 3: 단독 실행으로 cpio 생성 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd init && cargo build --release && cd ../kernel && ./make_initrd.sh && ls -la initrd.cpio && cpio -itv < initrd.cpio"
```

Expected: 종료 코드 0. `cpio -itv` 목록에 `init`, `usr/bin/fish`,
`usr/lib/terminfo/l/linux`, 그리고 `lib/x86_64-linux-gnu/libc.so.6`
등 여러 `.so` 파일과 `lib64/ld-linux-x86-64.so.2`가 보인다.

**만약 `ldd` 파싱이 실패하거나 파일이 빠지면:** `ldd` 원본 출력을 그대로
확인해(`docker run ... ldd usr/bin/fish`) 정규식이 실제 경로 형식과
맞는지 점검한다 — devcontainer의 glibc 버전에 따라 라이브러리 경로가
`/lib/x86_64-linux-gnu/`가 아닌 다른 경로일 수 있다.

- [ ] **Step 4: 커밋**

```bash
git add kernel/make_initrd.sh
git commit -m "Package init, fish, and dependencies into initramfs"
```

`initrd.cpio`는 매 빌드마다 내용이 재생성되는 산출물이지만 BF-M1부터
저장소에 커밋해 왔으므로(작고 재현 목적) 이 관례를 유지한다 — Step 3에서
생성된 최신 `initrd.cpio`도 함께 커밋 대상에 포함된다.

---

### Task 5: check.sh 배너 판정으로 변경 + 전체 부팅 검증

**Files:**
- Modify: `kernel/check.sh`

- [ ] **Step 1: exit gate 문자열을 fish 배너로 변경**

`kernel/check.sh`의 판정 부분을 다음으로 교체한다(빌드/실행 부분은
BF-M1과 동일하게 유지):

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./build.sh
(cd ../init && cargo build --release)
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

if grep -q "Welcome to fish, the friendly interactive shell" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected fish banner not found"
exit 1
```

`(cd ../init && cargo build --release)`를 추가해 `check.sh` 한 번 실행으로
kernel, init, initramfs가 모두 최신 상태로 재생성되게 한다.

- [ ] **Step 2: 실행해서 결과 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/check.sh
```

Expected: serial 로그에 `tars-init: starting as PID 1`, 3개의 mount 로그
(`tars-init: mounted proc at /proc` 등, 실패 시 `failed to mount ...
(errno N)` 형태로 보일 수 있음), 이어서 fish 배너
(`Welcome to fish, the friendly interactive shell`)와 프롬프트가 출력되고
`PASS`, 종료 코드 0.

**만약 FAIL이면:** 로그 마지막 부분을 읽고 원인을 판단한다. 예상 가능한
실패 유형과 확인 방법:
- `tars-init: failed to mount ... (errno 2)`(ENOENT) — mount target
  디렉터리(`/proc`, `/sys`, `/dev`)가 initramfs 루트에 없음. init이
  실행되는 시점에는 커널이 이미 initramfs를 루트로 마운트해 두므로
  디렉터리 자체는 kernel이 만들어주지 않는다 — `make_initrd.sh`에서
  `mkdir -p "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev"`로 마운트
  지점을 미리 만들어야 할 수 있다(Task 4로 돌아가 수정).
- `tars-init: execve failed (errno 2)`(ENOENT) — `/usr/bin/fish`가
  initramfs에 없거나 경로가 다름. Task 4 Step 3의 `cpio -itv` 결과를
  재확인한다.
- `execve failed (errno 8)`(ENOEXEC) 또는 커널이 곧바로 panic — fish의
  동적 링커나 공유 라이브러리가 빠짐. `ldd`로 다시 의존성을 대조한다.
- 로그가 `tars-init: starting as PID 1` 이후 아무 mount 로그도 없이
  멈추면 init 바이너리 자체가 실행되지 않은 것 — `file init/target/
  release/tars-init`로 ELF 아키텍처(x86-64)를 재확인한다.

이 반복 자체가 BF-M1과 동일한 학습 사이클이므로, 몇 차례 반복이 필요할
수 있다. 원인을 고치면 Step 2를 다시 실행한다.

- [ ] **Step 3: 커밋**

```bash
git add kernel/check.sh kernel/initrd.cpio
git commit -m "Switch BF-M2 exit gate to fish banner and verify boot"
```

(Task 4의 Step 4 커밋 이후 `initrd.cpio`가 다시 재생성되었다면 그 최신
버전이 포함된다.)

---

## BF-M2 완료 확인

Task 5의 Step 2가 PASS로 끝나면 BF-M2의 exit gate(design doc 기준: QEMU
serial 출력에서 fish 배너 확인)를 만족한다. 이 시점에서 BF-M3(Limine
bootloader + xorriso hybrid ISO) plan을 별도로 작성한다 — bootloader
도입과 ISO 이미지 빌드는 이번 initramfs 직접 부팅과 무관한 새 학습
사이클이므로 여기 포함하지 않는다.
