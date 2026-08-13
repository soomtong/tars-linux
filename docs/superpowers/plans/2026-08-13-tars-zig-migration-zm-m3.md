# TARS Zig Migration — ZM-M3 빌드 호스트 arm64 네이티브화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md` 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** 빌드 컨테이너를 `linux/amd64`에서 호스트와 같은 arm64로 바꾸고,
게스트용 x86_64 산출물(커널·`init`·`terminal`·유저랜드)은 전부 **크로스
컴파일 또는 amd64 패키지 조달**로 만든다. 에뮬레이션 층이 두 겹(Rosetta로
x86_64 툴체인 → TCG로 x86_64 게스트)에서 한 겹(TCG로 x86_64 게스트)으로
줄어든다. 게스트에서 관측되는 동작은 바뀌지 않는다.

**Architecture:** 바꿔야 할 것은 "무엇을 만드느냐"가 아니라 "무엇이 그것을
만드느냐"다. 산출물의 타깃은 전부 이미 x86_64로 **명시**돼 있어서
(`init/build.zig:8`, `terminal/build.zig:5`가 `resolveTargetQuery`로 고정,
`kernel/build.sh:23`이 `ARCH=x86_64`) 호스트가 바뀌어도 그대로다. 바뀌는 건
도구 넷이다.

1. **Zig** — 설치 tarball을 `zig-x86_64-linux`에서 `zig-aarch64-linux`로.
   Zig는 크로스 컴파일이 기본값이라 이것만 바꾸면 `init`·`terminal`은
   그대로 x86_64 산출물을 낸다.
2. **커널 gcc** — `CROSS_COMPILE=x86_64-linux-gnu-` 추가 + 크로스 툴체인 설치.
3. **initrd 유저랜드** — 지금은 컨테이너 자신의 `/usr/bin/fish`를 복사한다.
   컨테이너가 arm64가 되면 이 경로가 통째로 무효다. amd64 `.deb`를 받아
   이미지 안 sysroot에 풀어두고 거기서만 복사한다.
4. **`ldd` → `readelf`** — `ldd`는 바이너리를 실제 로더에 태워보는 것이라
   arm64 호스트에서 x86_64 바이너리에 쓸 수 없다. `readelf -d`는 파일을 읽기만
   하므로 아키텍처와 무관하다.

순서는 **조사 → 이미지 → 커널 → Zig → initrd → 체인 1회씩 → 전체 게이트**다.
design doc이 이 milestone을 마지막에 둔 이유가 "실패 모드가 넓다"인데, 그
대책은 **하나 바꾸고 그 자리에서 확인**하는 것뿐이다. 그래서 게이트 전체를
돌리기 전에 커널만·Zig만·initrd만 따로 확인하는 Task를 뒀다.

**Tech Stack:** Docker(arm64 네이티브), Debian trixie, Zig 0.16.0,
`gcc-multilib-x86-64-linux-gnu`, `dpkg -x` sysroot, QEMU TCG, bash

---

## 사전 조사 결과 (plan을 쓰기 전에 확인한 것)

읽기 전용 확인과 웹 리서치로 다음 다섯을 먼저 확정했다. 세 개는 design
doc의 서술을 **바꾼다.**

### 1. design doc이 "M3 전체가 막힐 수 있는 유일한 지점"이라 쓴 리스크는 성립하지 않는다

design doc 리스크 절은 `terminal/src/drm.zig:3`의 `@cImport`가 **DRM UAPI
헤더**를 읽으므로 Zig 번들에 그게 없으면 막힌다고 적었다. 실제 파일을 보면
그렇지 않다.

```zig
const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
});
```

셋 다 **glibc 헤더**이고, DRM 쪽은 구조체를 `extern struct`로 손으로 선언해
두었다(`drm.zig:9-40`의 `DrmModeCardRes`·`DrmModeModeinfo`, ioctl 번호도
직접 계산). `libdrm`도 커널 UAPI 헤더도 include하지 않는다.

게다가 이 `@cImport`는 **지금도 크로스 컴파일 경로로 처리되고 있다.**
`build.zig`가 `resolveTargetQuery`로 타깃을 명시하는 순간 Zig에게 이 빌드는
네이티브가 아니고, glibc 헤더는 시스템이 아니라 Zig 번들에서 온다. 호스트가
arm64로 바뀌어도 이 부분 입력은 한 글자도 달라지지 않는다. **리스크를
"해소"가 아니라 "처음부터 오해였다"로 정정하고 design doc에 반영한다**
(Task 9).

### 2. 커널 실모드 때문에 크로스 컴파일러도 32비트 코드 생성이 필요하다

`kernel/.config:307`에 `CONFIG_X86_16BIT=y`가 있고, `arch/x86/boot`와
`arch/x86/realmode`는 `-m16`/`-m32`로 빌드된다(`-m16`은 gcc가 내부적으로
`-m32` + `.code16gcc`로 처리한다). 지금 Dockerfile에 `gcc-multilib`이 들어
있는 이유가 이것이다 — amd64 네이티브 gcc가 `-m32`를 쓸 수 있게 하는
패키지다.

크로스로 넘어가면 이 역할은 **`gcc-multilib-x86-64-linux-gnu`**(Debian
trixie, `4:14.2.0-1`, **arm64에서 설치 가능**)가 맡는다. 이 패키지는
`gcc-x86-64-linux-gnu`와 `gcc-14-multilib-x86-64-linux-gnu`를 함께 끌고
온다. design doc은 `gcc-x86-64-linux-gnu`만 적었는데, 그것만 넣으면 실모드
컴파일에서 32비트 지원이 없어 깨질 수 있다. **이미지 재빌드는 비싸므로
처음부터 multilib 쪽을 넣는다** — 추가 용량 수십 MB가 재빌드 한 번보다 싸다.

링크 쪽은 걱정할 것이 없다. 실모드는 `ld -m elf_i386 -nostdlib`으로 링크되고
크로스 binutils는 두 emulation을 모두 지원하며, 32비트 libc는 애초에 필요
없다(freestanding).

### 3. Zig aarch64 tarball 이름 확인

`https://ziglang.org/download/index.json`에서 0.16.0 항목을 확인했다.

- 지금: `zig-x86_64-linux-0.16.0.tar.xz`
- 바꿀 것: `zig-aarch64-linux-0.16.0.tar.xz`

`Dockerfile`의 URL 템플릿에서 `x86_64` 한 곳만 `aarch64`로 바꾸면 된다.

### 4. `/usr/share/fish/*`는 `fish` 패키지가 아니라 `fish-common`이 준다

trixie의 `fish`는 4.0.2-1이고, `/usr/bin/fish`·`fish_indent`·`fish_key_reader`만
들어 있다. `make_initrd.sh:53-56`이 복사하는 `functions/`·`config.fish`·
`__fish_build_paths.fish`는 **`fish-common`(architecture: all)** 소속이다.
arch가 all이라 amd64 sysroot에 그냥 같이 풀어두면 된다.

`fish` 4.0.2의 동적 의존은 `libc6`·`libgcc-s1`·`libpcre2-8-0`·`libpcre2-32-0`
이고(나머지 Depends인 `python3`·`man-db`·`groff-base`·`procps`·
`bsdextrautils`는 실행 파일 링크가 아니라 기능 의존이라 지금 initrd에도
없다), `coreutils`는 `libacl1`·`libattr1`·`libcap2`·`libgmp10`·`libselinux1`·
`libssl3t64`·`libsystemd0`를 Depends로 건다. 우리가 넣는 `cat`/`uname`/`mkdir`
셋이 그중 무엇을 실제로 링크하는지는 Task 1에서 `ldd`로 확정한다.

### 5. limine과 나머지 도구는 손댈 것이 없다

- `boot/build.sh:17`의 `make -C limine-binary`는 **호스트용 유틸리티**를
  빌드한다(ISO에 부트 섹터를 써넣는 프로그램). arm64로 빌드되어 arm64에서
  실행되면 그만이다. ISO에 들어가는 `limine-bios.sys`·`limine-bios-cd.bin`은
  tarball에 이미 들어 있는 **x86 바이너리 blob**이라 빌드 대상이 아니다.
- `xorriso`·`imagemagick`·`cpio`·`gzip`은 호스트 도구다.
- `qemu-system-x86` 패키지는 arm64에도 있고, 거기 든 `qemu-system-x86_64`는
  **arm64 네이티브 바이너리가 x86_64 게스트를 TCG로 돌린다.** 이게 이번
  milestone에서 얻는 것 그 자체다.

---

## design doc에 없던 결정 셋

ZM-M2에서 `kernel/check.sh`가 그랬듯, 실제로 만져보면 design doc이 정하지
않은 갈림길이 나온다. 셋을 미리 정해둔다.

### A. 새 이미지는 `tars-devcontainer:arm64` 태그로 만들고, 끝에 승격한다

`tars-devcontainer:latest`를 바로 덮어쓰면 중간에 막혔을 때 돌아갈 곳이
없다. 태그는 공짜이고(레이어는 공유), 게이트를 부르는 명령줄에만 태그가
등장하므로 저장소 파일은 하나도 바뀌지 않는다. Task 8에서 전체 게이트가
통과한 뒤에 `latest`로 승격한다.

ZM-M2가 남겨둔 `tars-devcontainer:pre-zm-m2`(amd64, Rust 포함)와 현재
`latest`(amd64, Rust 없음)는 이 milestone 동안 그대로 둔다.

### B. amd64 유저랜드는 **이미지 빌드 시점에** sysroot로 굽는다

`make_initrd.sh`가 매번 `apt-get download`를 하게 만들면 안 된다. 루트
`check.sh`는 clean 재빌드를 6회 하므로 initrd도 6번 만들어지고, 그때마다
네트워크에 나가면 (a) 느리고 (b) 오프라인에서 못 돌고 (c) 회차마다 패키지
버전이 달라질 수 있다 — 게이트의 대전제인 "같은 입력이면 같은 결과"가
깨진다.

그래서 `Dockerfile`이 `/usr/local/amd64-sysroot`에 한 번 풀어두고,
`make_initrd.sh`는 그 디렉터리에서만 복사한다. 이미지가 고정되면 유저랜드도
고정된다.

### C. `devcontainer/sanity`는 크로스 도구로 두 줄 고쳐서 살린다

`devcontainer/sanity/Makefile`은 `gcc -m32`와 `ld -m elf_i386`으로 BF-M0의
"진짜 x86 기계어를 만들어 QEMU가 부팅시키는가" 확인용 미니 커널을 만든다.
호스트가 arm64가 되면 네이티브 `gcc`로는 불가능해진다.

ZM-M2에서 세운 구분을 그대로 적용한다 — **깨진 게이트는 지우고, 동작하는
수동 도구는 남긴다**(`kernel/check-virtio-gpu.sh`를 남긴 근거). 이건 지금도
동작하고, `CC`/`LD`를 크로스 접두사로 바꾸는 두 줄이면 계속 동작한다. 지울
이유가 없다.

---

## 시간 측정 (완료 조건의 일부)

design doc이 "전환 전후 소요 시간 기록"을 완료 조건에 넣었다. 무엇을 재는지
먼저 정해둔다. **Task 1(옛 이미지)과 Task 8(새 이미지)에서 같은 두 가지를
잰다.**

| 기호 | 측정 대상 | 명령 |
|------|-----------|------|
| **T1** | 커널 clean 빌드 | `rm -rf kernel/build && bash kernel/build.sh` |
| **T2** | BF 체인 1회(clean 포함, 커널 빌드 + Zig 빌드 + initrd + ISO + 부팅) | `bash check.sh`의 BF 1회분에 해당 |

`check.sh` 전체(BF 3 + TF 3)는 Task 8에서 어차피 돌리므로 그 wall clock도
기록하되, 옛 이미지 쪽 대응 숫자는 재지 않는다(같은 것을 6번 재는 데 몇
시간을 쓸 이유가 없다). 비교의 핵심은 T1·T2다.

`nproc`도 함께 기록한다 — 커널 빌드는 `-j$(nproc)`이라 컨테이너에 보이는
CPU 수가 다르면 T1 비교가 무의미해진다. 두 이미지 모두 같은 Docker VM에서
돌므로 같아야 하고, 다르면 그 사실을 기록한다.

### 기준선 실측 (2026-08-13, 옛 amd64 이미지)

| 항목 | 값 |
|---|---|
| `nproc` | **10** |
| **T1** 커널 clean 빌드 | **9분 55초** |
| **T2** BF 체인 1회(빌드+부팅) | **17분 40초** |
| `bzImage` | 2.6MB |
| `initrd.cpio` | 14MB, 파일 264개 |

T2 − T1 ≈ 7분 45초가 Zig 두 컴포넌트 빌드 + initrd + ISO + 부팅(≈34초)이다.
**커널이 전체의 56%**이므로 크로스 컴파일이 통하면 여기서 가장 크게 줄어든다.

---

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
시작 상태는 ZM-M2 완료 직후 — `main`, working tree 깨끗함, 마지막 커밋
`194990e`.

Task 2에 **네트워크가 필요하다**(이미지 재빌드: apt, amd64 `.deb`, Zig
tarball). 그 뒤 Task들은 오프라인으로 돈다.

이 milestone 동안 `docker run` 명령에서 **`--platform linux/amd64`를
빼는 것**이 매번 중요하다. 붙인 채로 arm64 이미지를 돌리면 Docker가 다시
에뮬레이션을 걸거나 실행을 거부한다 — 이 milestone이 없애려는 바로 그
층이다.

---

## Task 1: 기준선 측정과 유저랜드 의존 조사 (옛 amd64 이미지에서)

이 Task는 **아무것도 바꾸지 않는다.** 나중에 비교할 숫자와, sysroot에 무엇을
넣어야 하는지를 지금 확정한다. 새 이미지를 만들고 나면 옛 환경의 숫자는 다시
못 잰다.

**Files:** 없음(측정과 레퍼런스 보관만)

- [ ] **Step 0: 옛 방식으로 만든 initrd와 커널을 "정답지"로 저장소 밖에 보관**

Step 2가 `kernel/build`를 지우고, Task 5가 `initrd.cpio`를 새 방식으로 다시
만든다. 그 전에 **지금 있는 산출물**(옛 amd64 이미지가 `ldd`로 만든 것)을
빼두면, Task 5의 결과를 크기가 아니라 **파일 목록 단위로** 대조할 수 있다.
이 milestone에서 가장 위험한 변경에 대한 유일한 정답지다.

저장소 밖(`/tmp`)에 두는 이유는 `.gitignore`와 `clean()`을 둘 다 피하기
위해서다. 파일 목록은 이름만 뽑아 정렬한다 — BSD cpio(macOS)와 GNU
cpio(컨테이너)의 상세 출력 형식이 달라서 나중에 diff가 안 되기 때문이다.

Run:
```bash
cp kernel/initrd.cpio /tmp/zm-m3-initrd-amd64-ref.cpio
cp kernel/build/arch/x86/boot/bzImage /tmp/zm-m3-bzImage-amd64-ref
gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null | sort > /tmp/zm-m3-initrd-amd64-ref.txt
wc -l /tmp/zm-m3-initrd-amd64-ref.txt
ls -l /tmp/zm-m3-initrd-amd64-ref.cpio /tmp/zm-m3-bzImage-amd64-ref
```

Expected: 파일 목록 줄 수(수십 줄), `initrd.cpio` 14MB, `bzImage` 10MB 근처.
**세 숫자를 기록할 것.**

- [ ] **Step 1: 컨테이너에 보이는 CPU 수 기록**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer nproc
```

Expected: 숫자 하나(예: `8`). **기록할 것.** Task 8에서 같은 값이어야 T1
비교가 성립한다.

- [ ] **Step 2: T1 — 커널 clean 빌드 시간 (옛 이미지)**

Run:
```bash
time docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'rm -rf kernel/build && bash kernel/build.sh'
```

Expected: 마지막에 `Kernel: arch/x86/boot/bzImage is ready`. `real` 값을
**기록할 것.**

`kernel/src/`는 이미 받아져 있으므로 다운로드 시간은 안 들어간다. 없으면
받는 시간이 섞이니, 그 경우 한 번 더 돌려서 두 번째 값을 쓴다.

- [ ] **Step 3: T2 — BF 체인 1회 시간 (옛 이미지)**

Run:
```bash
time docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out && bash boot/check.sh' \
  2>&1 | tail -20
```

Expected: `Boot reached the fish banner after ~NNs` → `init mounted all four
filesystems` → `PASS`. **`real` 값과 `~NNs` 값 둘 다 기록할 것** (앞은 빌드
포함 전체, 뒤는 QEMU 부팅만). HANDOFF에 적힌 기준선 "BF 부팅 33~34초"가
뒤쪽 숫자다.

`rm -rf` 목록은 루트 `check.sh:15`의 `clean()`과 같다 — vendor 트리를 건드리지
않는 그 목록 그대로여야 한다.

- [ ] **Step 4: initrd에 들어간 x86_64 유저랜드의 실제 의존 확인**

sysroot에 어떤 패키지를 넣어야 하는지 **지금 옛 이미지에서** 확정한다. 여기
나오는 `.so` 전부가 새 sysroot에서도 찾아져야 한다.

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer bash -c \
  'for b in /usr/bin/fish /usr/bin/cat /usr/bin/uname /usr/bin/mkdir; do
     echo "== $b"; ldd $b; done'
```

Expected: 각 바이너리마다 `linux-vdso.so.1`(가짜, 파일 아님) +
`/lib64/ld-linux-x86-64.so.2` + 몇 개의 `.so`. **전체 출력을 기록할 것.**
`fish`에는 `libpcre2-32.so.0`·`libpcre2-8.so.0`·`libstdc++`(있다면)·
`libgcc_s.so.1`·`libm.so.6`·`libc.so.6`가, coreutils 쪽에는 `libselinux.so.1`·
`libacl.so.1` 같은 것이 나올 수 있다.

- [ ] **Step 5: 각 `.so`가 어느 패키지에서 오는지**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer bash -c \
  'for b in /usr/bin/fish /usr/bin/cat /usr/bin/uname /usr/bin/mkdir; do
     ldd $b; done | grep -oE "/[^ ]+\.so[0-9.]*" | sort -u | xargs dpkg -S 2>&1 | \
   awk -F: "{print \$1}" | sort -u'
```

Expected: 패키지 이름 목록(예: `libc6`, `libgcc-s1`, `libpcre2-8-0`,
`libpcre2-32-0`, `libselinux1`, `libacl1`, ...). **이 목록을 Task 2 Step 2의
`apt-get download` 줄과 대조할 것.** 목록에 있는데 Task 2에 없는 패키지가
있으면 그때 추가한다.

- [ ] **Step 6: 커밋할 것 없음**

측정만 했으므로 `git status`는 깨끗해야 한다. 기록한 숫자와 목록은 Task 9에서
문서에 들어간다.

---

## Task 2: Dockerfile을 arm64로 전환하고 새 태그로 빌드

**Files:**
- Modify: `devcontainer/Dockerfile` (전체적으로)

- [ ] **Step 1: `Dockerfile`을 아래 내용으로 교체**

바뀌는 곳이 다섯이다 — ① `FROM`의 `--platform` 제거, ② `gcc-multilib` →
`gcc-multilib-x86-64-linux-gnu`, ③ `fish` 제거(더 이상 컨테이너에서 복사하지
않는다) + `file` 추가, ④ amd64 sysroot 레이어 신설, ⑤ Zig URL `aarch64`.

```dockerfile
# 호스트(Apple Silicon)와 같은 arm64로 돈다. 예전에는
# `--platform=linux/amd64`가 붙어 있어서 컴파일러와 QEMU 바이너리 자체가
# Rosetta 에뮬레이션을 통과했고, 그 안에서 다시 x86_64 게스트를 TCG로
# 돌렸다(에뮬레이터의 에뮬레이션). 게스트용 x86_64 산출물은 이제 전부
# 크로스 컴파일이거나 amd64 패키지에서 조달한다 — ZM-M3.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc-multilib-x86-64-linux-gnu \
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
        file \
        xorriso \
        imagemagick \
        xz-utils \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# initrd에 들어갈 x86_64 유저랜드. 컨테이너가 arm64라서 컨테이너 자신의
# /usr/bin/fish를 복사할 수 없다 — amd64 .deb를 받아 여기에 풀어두고
# kernel/make_initrd.sh가 이 디렉터리에서만 복사한다. 네트워크는 이미지
# 빌드 때 한 번만 쓴다: 게이트는 clean 재빌드를 6회 하므로 initrd 생성이
# 네트워크에 나가면 안 된다(느리고, 오프라인에서 죽고, 회차마다 패키지
# 버전이 달라질 수 있다).
#
# fish-common은 architecture: all이라 :amd64를 붙이지 않는다. 여기에
# /usr/share/fish/{functions,config.fish,__fish_build_paths.fish}가 들어 있다.
ENV AMD64_SYSROOT=/usr/local/amd64-sysroot

RUN dpkg --add-architecture amd64 \
    && apt-get update \
    && mkdir -p /tmp/debs "$AMD64_SYSROOT" \
    && (cd /tmp/debs && apt-get download \
        fish:amd64 \
        fish-common \
        coreutils:amd64 \
        libc6:amd64 \
        libgcc-s1:amd64 \
        libpcre2-8-0:amd64 \
        libpcre2-32-0:amd64 \
        libselinux1:amd64) \
    && for deb in /tmp/debs/*.deb; do dpkg -x "$deb" "$AMD64_SYSROOT"; done \
    && rm -rf /tmp/debs /var/lib/apt/lists/*

ENV ZIG_VERSION=0.16.0 \
    PATH=/usr/local/zig:$PATH

RUN curl -sSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /usr/local/zig \
    && tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

WORKDIR /workspace
```

`apt-get download`는 **의존을 따라가지 않는다** — 이름을 댄 `.deb` 하나씩만
받는다. 그래서 목록이 명시적이고, 빠진 게 있으면 Task 5에서
`make_initrd.sh`가 소네임을 찍으며 즉시 죽는다(조용히 통과하지 않는다).

이 여덟 줄은 **Task 1의 실측에서 나온 최소 집합**이다. 옛 initrd에 실제로
들어 있던 `.so`는 아홉 개이고 소속은 넷뿐이다.

| initrd 안의 `.so` | 소속 패키지 | 누가 요구했나 |
|---|---|---|
| `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `librt.so.1`, `libutil.so.1`, `ld-linux-x86-64.so.2` | `libc6` | 전부 |
| `libgcc_s.so.1` | `libgcc-s1` | `fish` |
| `libpcre2-8.so.0`, `libpcre2-32.so.0` | `libpcre2-8-0`, `libpcre2-32-0` | `fish`, `mkdir`(selinux 경유) |
| `libselinux.so.1` | `libselinux1` | `mkdir` |

`libpthread`·`librt`·`libutil` 셋은 `fish`/`cat`/`uname`/`mkdir`의 `ldd`에
나오지 않는다 — **`terminal`이 요구하는 것들이다.** Zig가 glibc를 링크하면서
`DT_NEEDED`에 넣는 스텁들이고(glibc 2.34부터 내용은 `libc.so.6`에 흡수됐지만
빈 `.so`는 여전히 배포된다), 셋 다 `libc6` 소속이라 목록은 늘지 않는다.
`libstdc++6`은 필요 없다 — trixie의 fish 4.0.2는 Rust로 작성됐다.

`coreutils`의 Depends에는 `libacl1`·`libattr1`·`libcap2`·`libgmp10`·
`libssl3t64`·`libsystemd0`가 더 있지만, 우리가 넣는 세 바이너리
(`cat`/`uname`/`mkdir`)는 그중 아무것도 링크하지 않으므로 받지 않는다.
나중에 `ls` 같은 것을 추가해서 resolver가 소네임을 찍고 죽으면, 그때 해당
패키지 줄을 추가하고 이미지를 다시 빌드한다.

- [ ] **Step 2: 새 이미지를 별도 태그로 빌드**

Run:
```bash
docker build -t tars-devcontainer:arm64 -f devcontainer/Dockerfile .
```

**`--platform`을 붙이지 않는다.** 호스트가 arm64이므로 기본값이 arm64다.

Expected: 종료 코드 0. 모든 레이어가 새로 돈다 — `FROM`부터 아키텍처가
다르므로 캐시가 하나도 안 맞는다(ZM-M2 때와 다른 점이다). apt와 Zig
tarball을 다시 받으므로 몇 분 걸린다.

- [ ] **Step 3: 이미지가 정말 arm64인지, 도구가 다 있는지**

Run:
```bash
docker run --rm tars-devcontainer:arm64 bash -c \
  'uname -m; zig version; zig targets | head -1 >/dev/null && echo zig-ok;
   x86_64-linux-gnu-gcc --version | head -1;
   x86_64-linux-gnu-gcc -m32 -E -x c /dev/null >/dev/null && echo m32-ok;
   file /usr/bin/qemu-system-x86_64;
   ls "$AMD64_SYSROOT/usr/bin/fish" "$AMD64_SYSROOT/usr/share/fish/config.fish";
   file "$AMD64_SYSROOT/usr/bin/fish"'
```

Expected:
- `uname -m` → **`aarch64`** (여기서 `x86_64`가 나오면 `--platform`이 어딘가
  남아 있는 것이다)
- `zig version` → `0.16.0`, 그리고 `zig-ok`
- `x86_64-linux-gnu-gcc` 버전 한 줄(14.x)
- **`m32-ok`** — 실모드 빌드에 필요한 32비트 코드 생성이 되는지 미리 보는
  가장 싼 검사다. 여기서 죽으면 커널 빌드는 반드시 죽는다.
- `qemu-system-x86_64` → `ELF 64-bit LSB ... ARM aarch64` (arm64 네이티브
  바이너리가 x86_64 게스트를 돌린다는 증거)
- sysroot의 두 파일이 존재하고, `fish`는 `ELF 64-bit LSB ... x86-64`

- [ ] **Step 4: Commit**

Claude가 수행한다. 이미지 확인이 끝났고 게이트는 아직 안 돌렸지만, ZM-M2와
같은 이유로 `Dockerfile`만 따로 커밋한다 — 뒤에서 깨지면 되돌릴 단위가
분명해진다.

---

## Task 3: 커널을 크로스 컴파일로

**Files:**
- Modify: `kernel/build.sh:23`

- [ ] **Step 1: `MAKE_ARGS`에 `CROSS_COMPILE` 추가**

23번째 줄을 다음으로 바꾼다(주석 세 줄 포함).

수정 전:
```bash
MAKE_ARGS=(-C "$SRC_DIR" O=../../build ARCH=x86_64)
```

수정 후:
```bash
# ARCH는 arch/x86 트리를 쓰라는 뜻일 뿐 컴파일러를 고르지 않는다. 컨테이너가
# arm64가 된 ZM-M3부터는 CROSS_COMPILE 접두사로 x86_64용 gcc를 명시해야 한다.
# arch/x86/boot의 실모드 코드가 -m32/-m16으로 빌드되므로 크로스 gcc도 32비트
# 코드 생성이 가능해야 한다(Dockerfile의 gcc-multilib-x86-64-linux-gnu).
MAKE_ARGS=(-C "$SRC_DIR" O=../../build ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu-)
```

- [ ] **Step 2: 커널만 clean 빌드 (T1 신규 측정)**

Run:
```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer:arm64 bash -c 'rm -rf kernel/build && bash kernel/build.sh'
```

Expected: `Kernel: arch/x86/boot/bzImage is ready`. **`real` 값을 기록할 것**
— Task 1 Step 2의 T1과 짝이 되는 숫자다.

깨진다면 어디서 깨졌는지가 중요하다. 세 가지 중 하나일 가능성이 높다.

1. `arch/x86/boot` 또는 `arch/x86/realmode`에서 `-m32`/`-m16` 관련 에러 →
   multilib 크로스 패키지 문제. Step 3 Expected의 `m32-ok`가 통과했다면
   이건 아닐 가능성이 크다.
2. `tools/objtool` 또는 `arch/x86/tools/relocs` → 이건 **호스트 도구**라
   arm64로 빌드되어 x86 오브젝트를 읽는다. `CONFIG_OBJTOOL=y`,
   `CONFIG_UNWINDER_ORC=y`라 objtool을 많이 쓴다. 크로스 빌드에서 드물게
   문제가 되는 지점이므로, 에러 메시지 전문을 그대로 전달할 것.
3. `HOSTCC` 관련 → `build-essential`이 있으므로 없을 것이다.

- [ ] **Step 3: 만들어진 커널이 x86-64인지 확인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'file kernel/build/arch/x86/boot/bzImage; ls -l kernel/build/arch/x86/boot/bzImage'
```

Expected: `Linux kernel x86 boot executable bzImage, version 6.18.42 ...`.
**크기를 기록할 것** — 옛 이미지에서 만든 것과 크게 다르면(수십 KB 차이는
컴파일러 버전 차이로 정상) 알릴 것.

이 확인을 위해 Task 2에서 `file`을 넣었다. ZM-M1에서 `file`이 없어 건너뛴
확인이 이것이다.

- [ ] **Step 4: Commit**

Claude가 수행한다. `kernel/build.sh` 한 줄 + 주석.

---

## Task 4: Zig 두 컴포넌트가 크로스로 나오는지

**Files:** 없음(확인만 — `init/build.zig`·`terminal/build.zig`는 이미
타깃을 명시하고 있어서 **고칠 것이 없다는 사실 자체를 확인한다**)

- [ ] **Step 1: `init`과 `terminal` 빌드**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'rm -rf init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache \
           && (cd init && zig build) && (cd terminal && ./prepare.sh)'
```

Expected: 조용히 끝나고 종료 코드 0.

`prepare.sh`는 `terminal/ghostty-src`가 이미 있으면 다운로드와 libghostty-vt
빌드를 건너뛰고 `zig build`만 한다. 여기서 **libghostty-vt 재빌드가 시작되면
안 된다** — 그건 `ghostty-src`가 없다는 뜻이고 네트워크가 필요하다.

- [ ] **Step 2: 산출물이 x86_64인지**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'file init/zig-out/bin/init terminal/zig-out/bin/terminal; \
           ls -l init/zig-out/bin/init terminal/zig-out/bin/terminal'
```

Expected:
- `init` → `ELF 64-bit LSB executable, x86-64, ... statically linked`
  (libc를 링크하지 않는다는 ZM-M1의 결정이 여기 그대로 보인다)
- `terminal` → `ELF 64-bit LSB pie executable, x86-64, ... dynamically
  linked, interpreter /lib64/ld-linux-x86-64.so.2`
- 크기: `terminal`은 42MB 근처(Debug + 심볼)

`terminal`이 여기까지 나왔다면 design doc이 "M3의 유일한 블로커"로 적었던
`@cImport` 문제는 존재하지 않는 것이 실측으로 확정된다(사전 조사 1번).

- [ ] **Step 3: 커밋할 것 없음**

파일을 바꾸지 않았다. `git status`는 깨끗해야 한다.

---

## Task 5: `make_initrd.sh`를 sysroot 기반으로

이 milestone에서 가장 많이 바뀌는 파일이다. `ldd`를 못 쓰게 되는 것이 핵심
변경이고, 나머지는 복사 원본 경로가 `/`에서 `$SYSROOT`로 바뀌는 것이다.

**Files:**
- Modify: `kernel/make_initrd.sh` (9-16, 35-56번째 줄 중심)

- [ ] **Step 1: 파일을 아래 내용으로 교체**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# initrd에 들어가는 유저랜드는 전부 x86_64다. 빌드 컨테이너는 ZM-M3부터
# arm64라서 컨테이너 자신의 /usr/bin/fish를 복사할 수 없다 — Dockerfile이
# 구워둔 amd64 sysroot에서만 가져온다. 여기서 실패하면 게이트가 엉뚱한
# 곳(부팅 후 로더 에러)에서 죽으므로 시작 전에 확인한다.
SYSROOT="${AMD64_SYSROOT:-/usr/local/amd64-sysroot}"
if [ ! -d "$SYSROOT" ]; then
  echo "make_initrd: amd64 sysroot not found at ${SYSROOT}" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# "찾는 곳"과 "넣는 곳"을 분리한다.
#
# 찾는 곳: sysroot는 .deb를 푼 자리라 usrmerge 규칙대로 /usr/lib/... 이다.
# 넣는 곳: initrd 안은 /lib/x86_64-linux-gnu로 고정한다 — 옛 방식(ldd)이
#          알려준 경로가 /lib/... 이었고 지금 부팅되는 initrd가 그 모양이다.
# 둘을 같게 만들면(=찾은 자리에 그대로 복사) 게스트 로더는 /usr/lib도 뒤지니
# 부팅은 되겠지만, 파일 경로가 통째로 바뀌어 옛 initrd와 대조가 불가능해진다.
LIB_DEST=/lib/x86_64-linux-gnu

find_in_sysroot() {
  local soname="$1" dir
  for dir in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /lib64; do
    if [ -e "${SYSROOT}${dir}/${soname}" ]; then
      echo "${SYSROOT}${dir}/${soname}"
      return 0
    fi
  done
  return 1
}

# 예전에는 ldd를 썼다. ldd는 대상 바이너리를 실제 동적 로더에 태워서 답을
# 얻는 것이라, arm64 호스트에서 x86_64 바이너리에는 쓸 수 없다. readelf는
# 파일을 읽기만 하므로 아키텍처와 무관하다. 대신 두 가지를 직접 해야 한다 —
# (1) 인터프리터는 DT_NEEDED가 아니라 PT_INTERP에 있어서 따로 봐야 하고,
# (2) 의존의 의존은 재귀로 따라가야 한다. ldd는 둘 다 대신 해줬었다.
copy_lib_deps() {
  local bin="$1" interp src soname dest

  interp="$(readelf -p .interp "$bin" 2>/dev/null | grep -oE '/[^ ]*ld-linux[^ ]*' || true)"
  if [ -n "$interp" ] && [ ! -e "${WORKDIR}${interp}" ]; then
    if ! src="$(find_in_sysroot "$(basename "$interp")")"; then
      echo "make_initrd: cannot resolve interpreter ${interp} (needed by ${bin})" >&2
      exit 1
    fi
    mkdir -p "${WORKDIR}$(dirname "$interp")"
    cp "$src" "${WORKDIR}${interp}"
  fi

  for soname in $(readelf -d "$bin" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    dest="${WORKDIR}${LIB_DEST}/${soname}"
    if [ ! -e "$dest" ]; then
      if ! src="$(find_in_sysroot "$soname")"; then
        echo "make_initrd: cannot resolve ${soname} (needed by ${bin}) in ${SYSROOT}" >&2
        echo "             add the package that provides it to devcontainer/Dockerfile" >&2
        exit 1
      fi
      mkdir -p "${WORKDIR}${LIB_DEST}"
      cp "$src" "$dest"
      copy_lib_deps "$src"
    fi
  done
}

mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev"

cp ../init/zig-out/bin/init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

# terminal은 Debug 빌드라 42MB이고 대부분이 디버그 심볼이다. strip하면
# initrd가 6.5MB까지 줄지만(부팅 25초 → 34초 차이), 심볼을 남긴다 —
# strip한 바이너리에서는 QEMU 안의 에러 트레이스가 원리적으로 복구
# 불가능해지기 때문이다. 단, 심볼이 있다고 트레이스가 바로 읽히지는
# 않았다(2026-08-12 TF-M4 실측: strip 버전은 `???` 주소 두 줄, 심볼 버전은
# 트레이스 자체가 없었다 — 원인 미규명). 크기는 아래 gzip으로 처리한다.
cp ../terminal/zig-out/bin/terminal "$WORKDIR/terminal"
chmod 0755 "$WORKDIR/terminal"

mkdir -p "$WORKDIR/vendor/fonts"
cp ../terminal/vendor/fonts/Hanme_8x4x4.ttf "$WORKDIR/vendor/fonts/Hanme_8x4x4.ttf"

cp "$SYSROOT/usr/bin/fish" "$WORKDIR/usr/bin/fish"
chmod 0755 "$WORKDIR/usr/bin/fish"

cp "$SYSROOT/usr/bin/cat" "$WORKDIR/usr/bin/cat"
cp "$SYSROOT/usr/bin/uname" "$WORKDIR/usr/bin/uname"
cp "$SYSROOT/usr/bin/mkdir" "$WORKDIR/usr/bin/mkdir"
chmod 0755 "$WORKDIR/usr/bin/cat" "$WORKDIR/usr/bin/uname" "$WORKDIR/usr/bin/mkdir"

# init은 libc를 링크하지 않는 정적 바이너리라 copy_lib_deps가 필요 없다
# (ZM-M1). 나머지는 전부 glibc 동적 링크다.
copy_lib_deps "$WORKDIR/terminal"
copy_lib_deps "$WORKDIR/usr/bin/fish"
copy_lib_deps "$WORKDIR/usr/bin/cat"
copy_lib_deps "$WORKDIR/usr/bin/uname"
copy_lib_deps "$WORKDIR/usr/bin/mkdir"

# /usr/share/fish/*는 fish 패키지가 아니라 fish-common(arch: all)이 준다.
mkdir -p "$WORKDIR/usr/share/fish"
cp -r "$SYSROOT/usr/share/fish/functions" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/config.fish" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/__fish_build_paths.fish" "$WORKDIR/usr/share/fish/"

# gzip으로 압축해 둔다. 커널은 initramfs의 magic을 보고 알아서 푼다
# (CONFIG_RD_GZIP=y). 파일명은 initrd.cpio 그대로 유지한다 — limine.conf와
# 두 check 스크립트가 이 이름을 참조하기 때문이다. 압축이 필요한 이유는 BF
# 체인인데, limine이 BIOS INT13h로 ISO에서 읽는 경로가 에뮬레이션에서
# 극단적으로 느려 53MB에서는 부팅조차 못 했다. 53MB → gzip 11.8MB.
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -9 > initrd.cpio
```

- [ ] **Step 2: initrd 생성 (Task 4의 산출물이 아직 있는 상태에서)**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'bash kernel/make_initrd.sh && ls -l kernel/initrd.cpio'
```

Expected: 에러 없이 끝나고 크기가 **14MB 근처**. ZM-M2 종료 시점 값과 같아야
한다 — 유저랜드의 출처만 바뀌었을 뿐 내용물은 같은 trixie 패키지다.

`make_initrd: cannot resolve <소네임>`이 나오면 sysroot 패키지 목록이 모자란
것이다. 그 소네임을 알릴 것 — Task 2 Step 1의 `apt-get download` 목록에 한 줄
추가하고 이미지를 다시 빌드한다. **이 실패는 조용하지 않게 설계한 것이다.**

- [ ] **Step 3: initrd 내용물을 직접 열어서 확인**

크기만으로는 "옛날 것이 그대로 남아 있는" 경우를 못 거른다. 실제로 풀어본다.

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'cd $(mktemp -d) && gzip -dc /workspace/kernel/initrd.cpio | cpio -idm --quiet \
           && find . -type f | sort && echo "--- arch ---" \
           && file init terminal usr/bin/fish lib64/ld-linux-x86-64.so.2'
```

Expected:
- 파일 목록에 `./init`, `./terminal`, `./usr/bin/{fish,cat,uname,mkdir}`,
  `./vendor/fonts/Hanme_8x4x4.ttf`, `./usr/share/fish/...`,
  `./lib64/ld-linux-x86-64.so.2`, 그리고 `./lib/x86_64-linux-gnu/` 아래
  `.so` 아홉 개(`libc`·`libm`·`libpthread`·`librt`·`libutil`·`libgcc_s`·
  `libpcre2-8`·`libpcre2-32`·`libselinux`)
- `file` 결과가 **전부 x86-64**. 하나라도 `ARM aarch64`가 나오면 sysroot가
  아니라 컨테이너에서 복사된 것이다.

- [ ] **Step 3-b: 옛 방식으로 만든 initrd와 파일 목록을 대조**

Task 1 Step 0에서 빼둔 정답지와 이름 단위로 비교한다. 크기만 보는 것으로는
"`.so` 하나가 빠졌는데 다른 게 늘어난" 경우를 못 거른다.

Run:
```bash
gzip -dc kernel/initrd.cpio | cpio -it 2>/dev/null | sort > /tmp/zm-m3-initrd-arm64-new.txt
diff /tmp/zm-m3-initrd-amd64-ref.txt /tmp/zm-m3-initrd-arm64-new.txt && echo "IDENTICAL FILE LIST"
```

Expected: **`IDENTICAL FILE LIST`.** 유저랜드의 출처만 바뀌었을 뿐 같은
trixie 패키지에서 같은 파일을 꺼내오므로 목록이 한 줄도 달라지면 안 된다.

차이가 나오면 그 diff 전문을 알릴 것. 방향에 따라 뜻이 다르다 — `<`(옛것에만
있음)는 `readelf` 재귀가 의존을 덜 따라간 것이고, `>`(새것에만 있음)는
sysroot에서 더 많이 딸려온 것이다. 전자가 위험하다.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 6: 두 체인을 한 번씩 (게이트 3/3 전에)

`make_initrd.sh`가 바뀌면 **두 체인을 모두** 돌린다 — DF-M3와 TF-M4에서 이
파일 때문에 다른 체인이 조용히 깨진 사고가 두 번 있었다
([[project_gate_chain_composition]]). 3회씩 도는 전체 게이트에 들어가기 전에
1회씩으로 먼저 본다.

**Files:** 없음(확인만)

- [ ] **Step 1: BF 체인 1회 (T2 신규 측정)**

Run:
```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out \
           && bash boot/check.sh' 2>&1 | tail -30
```

Expected: `Boot reached the fish banner after ~NNs` → `init mounted all four
filesystems` → `PASS`. **`real`과 `~NNs` 둘 다 기록할 것** — Task 1 Step 3의
T2와 짝이다.

여기서 부팅이 fish 배너까지 못 가면 원인은 십중팔구 initrd의 유저랜드다.
그때는 `--- init log ---`가 아니라 커널 로그 끝부분을 보내줄 것 —
`/init` 자체가 못 뜨는지(로더 에러), fish에서 죽는지가 갈린다.

- [ ] **Step 2: TF 체인 1회**

Run:
```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out \
           && bash terminal/check.sh' 2>&1 | tail -40
```

Expected: `Pixels changed after typing: NNNN` → `Found '42' in parsed screen
dump` → `init mounted all four filesystems` → `PASS`.

TF 체인은 DRM 렌더링·evdev 입력·PTY까지 본다. 여기까지 통과하면 크로스
컴파일된 `terminal`이 게스트에서 실제로 그리고 읽는다는 뜻이다.

- [ ] **Step 3: 커밋할 것 없음**

---

## Task 7: `devcontainer/sanity`를 크로스 도구로

**Files:**
- Modify: `devcontainer/sanity/Makefile:1-2`

- [ ] **Step 1: `CC`/`LD`를 크로스 접두사로**

수정 전:
```make
CC := gcc
LD := ld
```

수정 후:
```make
# ZM-M3: 컨테이너가 arm64가 되면서 네이티브 gcc로는 x86 코드를 못 만든다.
# 크로스 툴체인(gcc-multilib-x86-64-linux-gnu)을 쓴다. -m32/-m16과
# `ld -m elf_i386`은 그대로다 — 32비트 코드 생성 능력은 multilib 쪽 패키지가
# 준다.
CC := x86_64-linux-gnu-gcc
LD := x86_64-linux-gnu-ld
```

`CFLAGS`·`ASFLAGS`·`LDFLAGS`는 손대지 않는다.

- [ ] **Step 2: BF-M0 sanity 커널이 여전히 부팅하는지**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer:arm64 \
  bash -c 'cd devcontainer/sanity && make clean && bash check.sh'
```

Expected: 시리얼 로그에 `tars: sanity check ok` → `PASS`.

이건 루트 게이트에 없는 수동 도구다. 통과하면 "arm64 컨테이너에서 만든
32비트 x86 기계어를 QEMU가 실제로 실행한다"가 확인된 것이라, 커널 실모드
빌드가 되는 이유를 눈으로 보는 최소 예제가 된다.

- [ ] **Step 3: 빌드 산출물이 커밋에 섞이지 않는지 확인**

`*.o`와 `devcontainer/sanity/sanity.elf`는 `.gitignore`에 있다. 그래도
`CLAUDE.md`의 "Commit 전 git status 확인" 규칙대로 본다.

Run:
```bash
git status --short
```

Expected: `M devcontainer/sanity/Makefile` 한 줄만.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 8: 전체 게이트 3/3과 시간 비교

design doc이 정한 ZM-M3 완료 조건이다 — BF 3/3 + TF 3/3, **그리고** 전환
전후 숫자.

**Files:** 없음(확인만)

- [ ] **Step 1: 루트 게이트 전체**

Run:
```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer:arm64 bash check.sh 2>&1 | tee /tmp/zm-m3-gate.log
```

Expected 마지막 줄:
```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

**`real` 값을 기록할 것.**

- [ ] **Step 2: 6회 전부에서 init이 제 일을 했는지**

Run:
```bash
grep -c 'tars-init: starting as PID 1' /tmp/zm-m3-gate.log
grep -c 'init mounted all four filesystems' /tmp/zm-m3-gate.log
grep -c 'tars-init: failed' /tmp/zm-m3-gate.log
```

Expected: `6`, `6`, `0`. 게이트가 PASS해도 이 숫자가 안 맞으면 실패로 본다.

- [ ] **Step 3: 부팅 시간 6회분을 뽑아서 기준선과 비교**

Run:
```bash
grep -oE 'Boot reached the fish banner after ~[0-9]+s' /tmp/zm-m3-gate.log
docker run --rm tars-devcontainer:arm64 nproc
```

Expected: BF 3회분의 `~NNs` 세 줄, 그리고 `nproc` 값(Task 1 Step 1과 같아야
한다). 기준선은 **33~34초**(ZM-M1·M2 실측).

이 숫자가 거의 안 줄어도 실패는 아니다 — 게스트 x86_64는 Apple Silicon에서
어차피 TCG라 부팅 자체는 크게 안 빨라질 수 있다. 이 milestone이 겨냥한 것은
**빌드 시간(T1)**이다. 두 숫자를 구분해서 기록한다.

- [ ] **Step 4: 이미지 크기와 `latest` 승격**

Run:
```bash
docker images tars-devcontainer
docker tag tars-devcontainer:arm64 tars-devcontainer:latest
docker images tars-devcontainer
```

Expected: 승격 후 `latest`와 `arm64`가 **같은 IMAGE ID**. ZM-M2에서 배운
대로, 이미지가 실제로 바뀌었는지는 ID로 본다. `latest`의 SIZE도 기록할 것
(ZM-M2 종료 시점 1.11GB, 여기에 amd64 sysroot와 크로스 툴체인이 더해진다).

- [ ] **Step 5: 승격한 `latest`로 한 번 더 짧게 확인**

`latest`를 쓰는 기존 명령이 `--platform` 없이 그대로 동작하는지 본다.

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'uname -m; zig version'
```

Expected: `aarch64`, `0.16.0`.

- [ ] **Step 6: 커밋할 것 없음**

---

## Task 9: 문서와 기억 갱신

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-tars-zig-migration-design.md`
- Modify: `docs/decisions/project_gate_chain_composition.md`
- Create: `docs/decisions/project_build_host_arch.md`
- Modify: `MEMORY.md`
- Modify: `HANDOFF.md`
- Modify: 이 plan 파일(말미에 "실제 실행에서 plan과 달라진 점" 추가)

- [ ] **Step 1: Claude가 문서를 갱신한다**

사용자는 기록해 둔 숫자들(Task 1의 T1·T2·`nproc`, Task 3 Step 2의 T1,
Task 6 Step 1의 T2, Task 8의 전체 시간·부팅 3회·이미지 크기)만 전달하면
된다.

갱신 내용:

- **design doc** — Status를 `ZM-M3 complete`로. ZM-M3 절에 ① 리스크로 적었던
  `drm.zig` `@cImport` 문제가 **처음부터 오해였다**는 정정(실제로는 glibc
  헤더 셋만 include하고 DRM 구조체는 손으로 선언), ② `gcc-x86-64-linux-gnu`
  대신 `gcc-multilib-x86-64-linux-gnu`를 쓴 이유(`CONFIG_X86_16BIT=y` →
  실모드 `-m32`), ③ sysroot 방식과 `ldd`→`readelf` 전환, ④ 측정 결과를 적는다.
- **새 기억 `project_build_host_arch`** — 이 저장소의 빌드 호스트는 arm64이고
  게스트 산출물은 전부 크로스로 만든다는 사실, 그리고 그 결과로 생긴 규칙
  셋: (a) `docker run`에 `--platform`을 붙이지 않는다, (b) x86_64 산출물의
  의존은 `ldd`가 아니라 `readelf -d`로 본다, (c) initrd 유저랜드는 컨테이너가
  아니라 `$AMD64_SYSROOT`에서 온다. `[[project_gate_chain_composition]]`,
  `[[project_zig_c_uapi_rule]]`과 링크한다.
- **`project_gate_chain_composition`** — "동작하는 수동 도구는 남긴다"에
  `devcontainer/sanity`를 추가(이번엔 지우지 않고 크로스로 고쳐 살렸다).
- **`MEMORY.md`** — 새 기억 한 줄 추가.
- **`HANDOFF.md`** — ZM 서브프로젝트 종료 기준으로 다시 쓴다. 다음 후보는
  "설정 영속화 + 부팅 셸 선택"이고, ZM이 끝나면서 "동작을 바꾸지 않는다"
  제약이 풀려 PID 1 기능 보강(좀비 수거, 셸 종료 처리)이 가능해진다는 점을
  명시한다.
- **이 plan 말미** — "실제 실행에서 plan과 달라진 점". 다음 세션이 가장 먼저
  읽는 절이다.

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## 이번 milestone에서 하지 않는 것

- **`terminal/sanity/`의 두 수동 확인 도구.** `libghostty_vt_check`와
  `stb_truetype_check`는 빌드 스크립트 없이 손으로 컴파일해 쓰던 것이고,
  전자는 x86_64용 `vendor/libghostty-vt` 산출물을 링크하므로 arm64
  네이티브 `gcc`로는 못 만들게 된다. 지금 아무 체인도 부르지 않고 소스도
  그대로 남아 있으므로 건드리지 않는다. 나중에 필요하면
  `zig cc -target x86_64-linux-gnu`로 만들면 된다 — 이 사실만 기록해 둔다.
- **`init`을 `ReleaseSafe`로.** 여전히 보류. 크기가 실제 문제가 될 때 꺼낼
  카드다.
- **PID 1 기능 보강(좀비 수거, 셸 종료 처리).** design doc의 비목표.
  **ZM이 끝나면 이 제약이 풀린다** — 다음 작업 후보다.
- **`terminal` 바이너리 strip.** `make_initrd.sh` 주석에 적힌 대로 심볼을
  남기는 결정은 그대로다.
- **설정 영속화 / 부팅 셸 선택.** ZM 종료 후의 다음 서브프로젝트 후보.

---

## 막혔을 때 되돌아가는 법

| 어디서 깨졌나 | 되돌릴 것 |
|---|---|
| Task 3(커널) | `kernel/build.sh` 한 줄. 옛 이미지(`tars-devcontainer:latest`, amd64)는 그대로 있으므로 `--platform linux/amd64`를 붙여 이전과 똑같이 돌릴 수 있다. |
| Task 5(initrd) | `git checkout kernel/make_initrd.sh`. 단 옛 버전은 arm64 컨테이너에서 동작하지 않는다 — 확인은 옛 이미지에서. |
| Task 8(게이트) | 커밋이 Task별로 나뉘어 있으므로 `git revert`로 한 층씩 벗긴다. 이미지는 `latest` 승격 전이라 안전하다. |
| 커널 크로스 자체가 불가능 | 이 milestone은 여기서 막힌다. 그 경우 `Dockerfile`을 amd64로 되돌리고(=ZM-M2 상태), 무엇이 왜 막혔는지를 design doc에 남긴다. "커널만 amd64 이미지에서 빌드하고 나머지는 arm64" 같은 이중 컨테이너 구성은 게이트를 두 이미지에 걸치게 만들어 더 나쁘다 — 선택지로 적어두되 택하지 않는다. |

---

## 실제 실행에서 plan과 달라진 점 (2026-08-13 완료)

**다음 세션은 이 절부터 읽을 것.** ZM-M3은 `TARS check PASS`로 완료됐다
(BF 3/3, TF 3/3, 전체 8분 52초).

### 1. 측정 결과 — 예상보다 크게 빨라졌다

| 항목 | 전 | 후 | 배수 |
|---|---|---|---|
| 커널 clean 빌드 | 9분 55초 | 46.5초 | 12.8× |
| Zig 두 컴포넌트 | ~6분(추정) | 49.3초 | ~7× |
| BF 체인 1회 | 17분 40초 | 1분 48초 | 9.8× |
| QEMU 부팅만 | 33~34초 | ~4초 | 8.5× |
| 루트 게이트 전체 | (BF 3회만 53분) | 8분 52초 | — |

**부팅 8.5배가 이 milestone의 근거를 사후에 증명한다.** design doc의 "배경"
절이 세운 가설(qemu 바이너리 자체가 Rosetta를 통과한 뒤 그 안에서 게스트를
TCG로 번역한다)이 맞았다는 뜻이다 — TCG는 JIT이라 에뮬레이션 위에서 특히
불리하다. 이미지는 1.11GB → 1.3GB.

### 2. Task 1 Step 0(정답지 보관)이 두 번 값을 했다

plan을 쓴 뒤 실행 직전에 추가한 Step인데, 이번 milestone에서 가장 유용했다.

- **`.so` 목록에서 `libpthread`·`librt`·`libutil`을 발견했다.** `fish`/`cat`/
  `uname`/`mkdir`의 `ldd` 어디에도 없어서 사전 조사만으로는 놓쳤을
  것들이다. 출처는 `terminal`(Zig 산출물)이었다.
- **로더가 두 번 들어간 것을 잡았다.** 크기만 봤으면(13.83MB → 13.94MB)
  "gzip 편차"로 넘겼을 차이다.

**빌드 산출물을 바꾸는 작업에서는 바꾸기 전 산출물의 파일 목록을 저장소
밖에 떠두는 것이 싸고 강력하다.**

### 3. Zig 산출물은 로더를 `DT_NEEDED`에도 적는다

`terminal`의 `readelf -d`에 `ld-linux-x86-64.so.2`가 들어 있다. Debian이
만든 `fish`·`mkdir`에는 없다. `ldd`는 소네임을 절대 경로로 해석해 돌려주므로
이 사실이 가려져 있었고, `PT_INTERP`와 `DT_NEEDED`를 각각 처리하는 새
resolver에서 사본이 둘 생겼다. `NEEDED` 순회에서 `ld-linux*`를 건너뛰는
한 줄로 해결했고, 그 뒤 파일 목록이 264줄 완전 일치했다.

### 4. plan이 통째로 놓친 것: `boot/limine-binary/limine`

BF 체인이 ISO 만들기 단계에서 죽었다. 원인은 옛 amd64 컨테이너가 빌드해 둔
**호스트용** x86_64 유틸리티가 남아 있었고 `make`가 소스보다 새것이라 다시
만들지 않은 것. 게다가 binfmt_misc가 `ENOEXEC` 대신 qemu-user로 넘겨
`[qemu]: Could not open '/lib64/ld-linux-x86-64.so.2'`라는 위장된 메시지가
나왔다.

plan의 사전 조사 5번이 "limine은 손댈 것이 없다 — `make -C limine-binary`는
호스트용 유틸리티를 빌드한다"고 **정확히 그 파일을 짚고도 결론을 반대로
냈다.** 빌드된다는 것과 **다시** 빌드된다는 것을 구분하지 않았다.
`boot/build.sh`를 `make -C "$DIR" -B`로 고쳤다.

**진단이 빨랐던 이유는 Task 순서 덕이다.** BF만 실패하고 TF는 통과했는데,
TF는 `-kernel`/`-initrd` 직접 부팅이라 limine을 안 거친다. 이 조합 자체가
범인을 ISO 경로로 좁혔고, initrd·커널·유저랜드는 그 시점에 이미 무죄였다.

### 5. sysroot 패키지 목록은 실측으로 8개까지 줄었다

plan 초안은 `coreutils`의 Depends를 그대로 옮겨 15개를 받으려 했다. Task 1의
`ldd`와 정답지를 대조하니 실제로 필요한 것은 `fish`·`fish-common`·
`coreutils` + `libc6`·`libgcc-s1`·`libpcre2-8-0`·`libpcre2-32-0`·
`libselinux1`뿐이었다. `libstdc++6`도 필요 없다 — trixie의 fish 4.0.2는
Rust로 작성됐다.

### 6. 커밋 여섯 개

`dc7a71a`(plan) → `4edf95b`(기준선 반영) → `aa474a3`(Dockerfile) →
`f757be4`(커널 크로스) → `8bd9181`(initrd sysroot) → `7b464b5`(limine) →
`0e65be7`(sanity). Task마다 끊은 것이 limine 사고 때 실제로 값을 했다 —
되돌릴 단위가 분명했다.
