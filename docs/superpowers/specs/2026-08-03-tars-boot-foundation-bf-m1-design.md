# TARS Boot Foundation — BF-M1 Design

**Date:** 2026-08-03
**Status:** Approved (design phase), plan not yet written

## 배경

[BF-M0](../plans/2026-08-01-tars-boot-foundation-bf-m0.md)에서 devcontainer
cross toolchain과 QEMU `-kernel` direct boot 경로를 sanity 바이너리로
검증했다. 이 문서는 다음 단계인 **BF-M1 — 최소 kernel 자체 빌드**를
다룬다. 전체 milestone 구조와 배경은
[design doc](2026-08-01-tars-boot-foundation-design.md)을 참고.

## 목표

kernel.org의 최신 LTS 소스를 devcontainer 안에서 curl로 받아,
`allnoconfig`에서 시작해 부팅에 필요한 옵션만 하나씩 켜가며 x86_64
`.config`를 구성한다. 빌드된 `vmlinuz`를 QEMU `-kernel`로, init 바이너리가
없는 빈 cpio initrd를 `-initrd`로 부팅시켜, kernel이
`Kernel panic - not syncing: No working init found` 메시지를 내는 지점까지
도달한다.

## 비목표

- bootloader(Limine) 도입 — BF-M3
- 실제 init 구현 — BF-M2
- `.config`의 완전성/최소성 증명 — "필요할 때마다 하나씩 켠다"는 반복
  탐색이 목적이며, 이론적으로 더 줄일 수 있는 옵션이 남아있어도 exit gate만
  통과하면 충분

## 핵심 설계 결정

### 1. Kernel 버전

kernel.org의 최신 LTS를 pin한다 (예: 6.12.x 계열, plan 작성/실행 시점의
실제 최신 LTS로 확정). 문서/커뮤니티 자료가 풍부하고 장기적으로 재사용하기
좋다.

### 2. 아키텍처: x86_64

BF-M0의 sanity 바이너리는 Multiboot 검증용 32-bit 코드였지만, 이는
일회성 도구였을 뿐 이후 milestone과의 연속성 제약이 없다. 실제
하드웨어(Intel)와 QEMU 기본값이 모두 64-bit이고 최종 비전도 64-bit
OS이므로, BF-M1부터는 x86_64로 통일한다.

### 3. 소스 다운로드: devcontainer 안에서 curl

devcontainer 컨테이너 안에서 kernel.org tarball을 curl로 받아
`/workspace`(호스트 bind mount)에 푼다. macOS 호스트에 별도 다운로드
도구를 설치할 필요가 없다. tarball은 용량이 크므로(수십~수백MB) git에는
커밋하지 않고 `.gitignore`에 추가한다.

### 4. `.config` 구성 방법론: allnoconfig에서 반복 확장

`make allnoconfig`로 시작해 다음 반복 사이클로 최소 옵션을 찾아간다.

```
빌드 → QEMU -kernel/-initrd 부팅 시도 → serial 로그에서 다음 에러 확인
  → 원인이 되는 옵션을 켬 → 반복
```

defconfig(아키텍처 기본값에서 줄이기)보다 느리지만, design doc의 "필요한
옵션만 하나씩 켜며 이해"라는 원칙에 가장 부합한다 — "왜 필요 없는지"가
아니라 "왜 필요한지"를 배우는 방향.

미리 알 수 있는 최소 후보 카테고리:

| 옵션 | 목적 |
|---|---|
| `CONFIG_64BIT` | x86_64 |
| `CONFIG_PRINTK`, `CONFIG_TTY` | 콘솔 출력 인프라 |
| `CONFIG_SERIAL_8250`, `CONFIG_SERIAL_8250_CONSOLE` | QEMU `-serial stdio`(16550 UART)로 부팅 로그 확인 |
| `CONFIG_BLK_DEV_INITRD` | `-initrd`로 넘긴 cpio 인식 |
| `CONFIG_DEVTMPFS` | design doc이 명시적으로 언급한 항목 |
| `CONFIG_BINFMT_ELF` | init 바이너리 실행을 "시도"해야 실행 실패(없음)까지 도달 |

이 목록은 완전하다고 가정하지 않는다. 실제 빌드·부팅 반복 중 발견되는
부족한 옵션을 그때그때 채운다.

`.config`는 저장소에 커밋해, "지금 왜 이 옵션이 켜져 있는지"를 이후
milestone에서도 그대로 재현할 수 있게 한다.

### 5. 의도된 실패 지점: 빈 initrd로 "No working init found"

"init을 못 찾아 panic"은 두 가지 서로 다른 실패 지점을 가리킬 수 있다.

- **A. initrd 자체가 없음** → kernel이 root filesystem을 찾는 단계에서
  실패 (`VFS: Unable to mount root fs`) — design doc의 "no init found"
  문구와 일치하지 않음
- **B. 빈 initrd는 있지만 init 바이너리가 없음** → root는 mount되지만
  kernel이 `/sbin/init`, `/etc/init`, `/bin/init`, `/bin/sh` 등 후보를
  모두 못 찾아 `Kernel panic - not syncing: No working init found`

design doc이 명시한 문구와 정확히 일치하는 B를 채택한다. `initrd.cpio`는
완전히 빈 cpio(newc) 아카이브로 만든다 (`echo | cpio -o -H newc`).
디렉터리 구조조차 없어도 되며, "빈 컨테이너"일 뿐 init 구현이 아니므로
BF-M1의 "init 제외" 범위와 모순되지 않는다.

## 저장소 구조 변경

```text
kernel/
├── .config           # 커밋 대상 (재현성의 핵심)
├── build.sh           # 소스 다운로드(curl) + 압축 해제 + 빌드 스크립트
├── initrd.cpio        # 빈 cpio, 커밋 대상 (작고 재현 목적)
└── src/                # kernel.org tarball 압축 해제 위치 — .gitignore 처리
```

`devcontainer/Dockerfile`에 커널 빌드 필수 의존성을 추가한다: `flex`,
`bison`, `bc`, `libssl-dev`, `libelf-dev`. BF-M0의 sanity check는 이들이
필요 없어서 뺐었다. `gcc-multilib`은 이제 커널 빌드에는 불필요하지만(BF-M0
sanity 바이너리가 32-bit 참고 자산으로 남아있으므로) 유지한다.

## QEMU 부팅 검증

BF-M0의 `check.sh` 패턴(빌드 → 실행 → grep → PASS/FAIL)을 재사용한다.

```bash
qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -serial stdio -display none -no-reboot
```

`console=ttyS0`을 kernel 커맨드라인에 명시해 boot 로그가 확실히 serial로
나오게 한다. Exit gate는 serial 로그에서
`Kernel panic - not syncing: No working init found` 문자열을 grep으로
확인하는 것이다.

## 협업 방식

[BF-M0와 동일](2026-08-01-tars-boot-foundation-design.md#협업-방식): 설명
먼저 → 사용자가 직접 실행 → 결과 상세 설명. 승인된 내용의 git commit은
Claude Code가 대신 수행.

## 검증 방법

QEMU serial 출력에서 `Kernel panic - not syncing: No working init found`
매칭. BF-M0의 `check.sh`와 동일한 검증 스타일을 유지한다.
