# TARS Boot Foundation — BF-M0 Toolchain Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** BF-M0을 완료한다 — Docker 기반 amd64 Linux 빌드 환경에서 x86 cross
toolchain(gcc, binutils, qemu-system-x86)이 정상 동작함을, QEMU가 `-kernel`로
직접 부팅하는 최소 Multiboot 호환 바이너리의 serial 출력으로 검증한다.

**Architecture:** `devcontainer/Dockerfile`이 `linux/amd64` Debian
bookworm-slim 위에 cross toolchain을 설치한다. `devcontainer/sanity/`의
Multiboot v1 헤더를 가진 32-bit 어셈블리 진입점(`boot.S`)이 스택을 설정하고
freestanding C 함수(`kmain.c`)를 호출하며, 이 함수가 UART 16550(COM1,
포트 0x3F8)에 직접 byte를 써서 문자열을 출력한다. QEMU가 이 ELF를
`-kernel`로 직접 로드해 Multiboot 규약대로 실행하고, `check.sh`가 QEMU
serial 출력에서 marker 문자열을 확인한다. 이 sanity 바이너리는 실제
Linux kernel(BF-M1)과 무관한 일회성 검증 도구이며 최종 산출물에는
포함되지 않는다.

**Tech Stack:** Debian bookworm-slim (linux/amd64 컨테이너), GCC
(`-m32 -ffreestanding`), GNU `as`/`ld` (`elf_i386`), QEMU system x86_64
(TCG software emulation, KVM/HVF 불필요), bash

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행한다. Docker Desktop 또는 OrbStack이 실행 중이어야 하며, `linux/amd64`
플랫폼 빌드(멀티플랫폼 emulation)를 지원해야 한다 — 대부분의 현대 Docker
설치에는 기본 포함되어 있다.

**Design doc과의 의도적 차이:** design doc(BF-M0)은 devcontainer에
`xorriso`, `limine`도 함께 준비한다고 적었지만, 이 plan에서는 제외한다.
이 두 도구는 BF-M3(bootloader + hybrid ISO)에서 처음 쓰이므로, 지금
설치해도 이번 sanity check으로는 검증할 방법이 없다. BF-M3 plan을 작성할
때 devcontainer/Dockerfile에 추가한다 (YAGNI).

---

### Task 1: Devcontainer 이미지

**Files:**
- Create: `devcontainer/Dockerfile`

- [ ] **Step 1: Dockerfile 작성**

```dockerfile
FROM --platform=linux/amd64 debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc-multilib \
        binutils \
        qemu-system-x86 \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
```

`gcc-multilib`은 x86_64 호스트에서 32-bit(`-m32`) 코드를 컴파일하기 위해
필요하다 (BF-M0의 sanity 바이너리는 Multiboot v1 규약에 따라 32-bit
protected mode로 진입한다). `--platform=linux/amd64`는 Apple Silicon
host에서도 항상 x86 네이티브 툴체인을 쓰도록 고정한다.

- [ ] **Step 2: 이미지 빌드**

Run:
```bash
docker build --platform linux/amd64 -t tars-devcontainer -f devcontainer/Dockerfile .
```

Expected: 종료 코드 0. 마지막 줄 근처에 `tars-devcontainer` 태그가 적용됐다는
메시지 (`naming to docker.io/library/tars-devcontainer:latest done` 또는
`Successfully tagged tars-devcontainer:latest`).

- [ ] **Step 3: 툴체인 확인**

Run:
```bash
docker run --rm --platform linux/amd64 tars-devcontainer \
  bash -c "gcc --version && ld --version && qemu-system-x86_64 --version"
```

Expected: 세 명령 모두 버전 문자열을 출력하고 `command not found` 오류가
없음. (예: `gcc (Debian 12.2.0-...) 12.2.0`, `GNU ld (GNU Binutils for
Debian) 2.40`, `QEMU emulator version 7.2.x`)

- [ ] **Step 4: 커밋**

```bash
git add devcontainer/Dockerfile
git commit -m "Add amd64 devcontainer with x86 cross toolchain"
```

---

### Task 2: Multiboot sanity 바이너리

**Files:**
- Create: `devcontainer/sanity/Makefile`
- Create: `devcontainer/sanity/check.sh`
- Create: `devcontainer/sanity/boot.S`
- Create: `devcontainer/sanity/linker.ld`
- Create: `devcontainer/sanity/kmain.c`

- [ ] **Step 1: 실패하는 check 스크립트와 Makefile 작성**

아직 `boot.S`/`kmain.c`/`linker.ld`가 없는 상태에서 먼저 빌드+실행+검증을
묶는 스크립트를 작성한다.

`devcontainer/sanity/Makefile`:
```makefile
CC := gcc
LD := ld

CFLAGS  := -m32 -ffreestanding -fno-pic -fno-stack-protector -Wall -Wextra -std=gnu11 -O2
ASFLAGS := -m32
LDFLAGS := -m elf_i386 -T linker.ld -nostdlib

all: sanity.elf

boot.o: boot.S
	$(CC) $(ASFLAGS) -c boot.S -o boot.o

kmain.o: kmain.c
	$(CC) $(CFLAGS) -c kmain.c -o kmain.o

sanity.elf: boot.o kmain.o linker.ld
	$(LD) $(LDFLAGS) -o sanity.elf boot.o kmain.o

clean:
	rm -f boot.o kmain.o sanity.elf

.PHONY: all clean
```

레시피 줄(`$(CC) ...` 등)은 반드시 tab 문자로 시작해야 한다 — space를 쓰면
`make`가 `missing separator` 오류를 낸다.

`devcontainer/sanity/check.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
make

LOG="$(mktemp)"
timeout 5 qemu-system-x86_64 \
  -kernel sanity.elf \
  -serial stdio \
  -display none \
  -no-reboot \
  > "$LOG" 2>&1 || true

cat "$LOG"

if grep -q "tars: sanity check ok" "$LOG"; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected marker not found"
exit 1
```

```bash
chmod +x devcontainer/sanity/check.sh
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash devcontainer/sanity/check.sh
```

Expected: FAIL. `make`가 `boot.S`/`kmain.c`/`linker.ld`를 찾지 못해 오류
(`No rule to make target 'boot.S'` 계열)로 0이 아닌 종료 코드 반환.

- [ ] **Step 3: Multiboot 진입점 작성**

`devcontainer/sanity/boot.S`:
```asm
.set MULTIBOOT_MAGIC,    0x1BADB002
.set MULTIBOOT_FLAGS,    0x0
.set MULTIBOOT_CHECKSUM, -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

.section .multiboot
.align 4
.long MULTIBOOT_MAGIC
.long MULTIBOOT_FLAGS
.long MULTIBOOT_CHECKSUM

.section .bss
.align 16
stack_bottom:
.skip 16384
stack_top:

.section .text
.code32
.global _start
.type _start, @function
_start:
    mov $stack_top, %esp
    call kmain
    cli
1:  hlt
    jmp 1b
.size _start, . - _start
```

`devcontainer/sanity/linker.ld`:
```ld
ENTRY(_start)

SECTIONS
{
    . = 1M;

    .multiboot : { *(.multiboot) }
    .text      : { *(.text) }
    .rodata    : { *(.rodata*) }
    .data      : { *(.data) }
    .bss       : { *(COMMON) *(.bss) }
}
```

- [ ] **Step 4: kmain (serial 출력) 작성**

`devcontainer/sanity/kmain.c`:
```c
#include <stdint.h>

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

#define COM1 0x3F8

static void serial_init(void) {
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x80);
    outb(COM1 + 0, 0x03);
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);
    outb(COM1 + 2, 0xC7);
    outb(COM1 + 4, 0x0B);
}

static int serial_transmit_empty(void) {
    return inb(COM1 + 5) & 0x20;
}

static void serial_putc(char c) {
    while (!serial_transmit_empty()) {
    }
    outb(COM1, (uint8_t)c);
}

static void serial_puts(const char *s) {
    while (*s) {
        serial_putc(*s++);
    }
}

void kmain(void) {
    serial_init();
    serial_puts("tars: sanity check ok\n");
}
```

- [ ] **Step 5: 통과 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash devcontainer/sanity/check.sh
```

Expected: 로그에 `tars: sanity check ok`가 출력되고 마지막 줄에 `PASS`,
종료 코드 0.

- [ ] **Step 6: 커밋**

```bash
git add devcontainer/sanity/
git commit -m "Add multiboot sanity check for BF-M0 toolchain baseline"
```

---

## BF-M0 완료 확인

Task 1과 Task 2가 모두 끝나면 BF-M0의 exit gate(design doc 기준: "QEMU
serial 출력에서 sanity check 바이너리의 출력 확인")를 만족한다. 이 시점에서
BF-M1(자체 kernel 빌드) plan을 별도로 작성한다 — kernel.org 소스를 받고
`.config`를 구성하는 작업은 이번 sanity 바이너리와 무관한 새 학습
사이클이므로 여기 포함하지 않는다.
