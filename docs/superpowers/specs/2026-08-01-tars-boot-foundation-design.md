# TARS Boot Foundation — Design

**Date:** 2026-08-01
**Status:** Completed (BF-M0~M4 전부 완료, 2026-08-07)

## 배경

TARS는 이전 저장소(`tars.git`)에서 V0~V1 M12까지 진행했으나, 부팅 인프라 위에
쌓인 자잘한 guest-evidence 수정(RC6~RC21: fbdev capture race, ptmx mknod,
devpts mount point 등)이 근본 원인 이해 없이 누적되었다. 이 문서는 그 저장소를
버리고 `git@github.com:soomtong/tars-linux.git`에 완전히 새로 시작하는 첫
서브프로젝트, **Boot Foundation**의 설계를 다룬다.

최종 비전(macOS 키바인딩 의미론, ghostty 기반 내장 terminal, Linux용
homebrew 스타일 패키지 관리자, Claude Code/Codex 등 AI 코딩 도구 통합, 직접
구현한 CJK 입력기, X11/Wayland 최소화)은 다수의 독립적인 서브시스템을
포함하므로 한 번에 설계하지 않는다. Boot Foundation은 그중 가장 아래
계층이며, 이후 서브프로젝트(compositor/KMS, PTY/terminal, input policy,
IME, 패키지 관리자, AI 도구 통합)는 이 문서의 범위가 아니다.

## 목표 (이 서브프로젝트의 MVP)

QEMU에서 다음 체인으로 부팅해 root shell prompt에 도달한다.

```
xorriso hybrid ISO (El Torito)
  → Limine bootloader
  → 자체 빌드 Linux kernel
  → 자체 구현 Rust init (PID 1)
  → shell prompt
```

QEMU는 `-kernel`/`-initrd` 같은 QEMU 전용 direct boot 경로를 쓰지 않고
`-cdrom out/tars.iso`로 부팅한다. 이는 "QEMU가 커널 주입을 대신 해주는 편법"을
제거하고, 실제 하드웨어에서도 통하는 부팅 경로를 처음부터 검증하기 위함이다.

## 비목표 (이번 사이클에서 명시적으로 제외)

- 실머신(Intel 하드웨어) USB 부팅 검증 — 다음 서브프로젝트
- DRM/KMS, compositor, PTY, terminal 렌더링 — 이전 저장소의 자산이며 별도
  서브프로젝트에서 재검토
- CJK IME, macOS 키바인딩 정책, Linux homebrew, AI 코딩 도구 통합 — 훨씬
  뒤 단계
- CI 자동화 — 로컬에서 반복 재현 가능한 스크립트까지만. GitHub Actions
  재도입은 이 서브프로젝트 완료 후 별도로 판단

## 핵심 설계 결정

| 영역 | 선택 | 이유 |
|---|---|---|
| Kernel | kernel.org 소스를 직접 받아 자체 `.config`로 빌드 | 배포판이 미리 만들어둔 kernel package를 재사용하지 않고, 어떤 옵션이 왜 필요한지(virtio, devtmpfs 등) 직접 켜가며 이해하기 위함 |
| Init (PID 1) | BusyBox 등 외부 init 대신 Rust로 직접 구현 | "커널이 어디까지 하고 그다음부터는 전부 내 코드"라는 경계를 명확히 하기 위함. 이전 저장소의 RC6~RC21 문제(mount/mknod를 이해 못한 채 패치)를 반복하지 않기 위한 핵심 결정 |
| Bootloader | Limine | GRUB2 대비 설정이 단순하고 BIOS/UEFI hybrid ISO를 네이티브로 지원 |
| 이미지 형식 | `xorriso`로 만든 El Torito hybrid ISO | QEMU와 실머신(USB) 모두에서 동일 이미지로 부팅 가능 |
| 빌드 환경 | Docker Linux devcontainer (macOS host이므로) | kernel 빌드에 필요한 Linux 전용 툴체인을 macOS에서 직접 구성하지 않음 |

## 협업 방식

각 milestone은 다음 순서로 진행한다.

1. **설명 먼저** — 지금 만들 것이 무엇이고 왜 필요한지 (예: kernel `.config`의
   특정 옵션이 왜 필요한지) 사전 설명
2. **사용자가 직접 실행** — 명령 실행이나 코드 작성은 사용자가 직접 수행
   (페어 프로그래밍)
3. **결과 상세 설명** — 실행 후 무슨 일이 일어났는지, 왜 그렇게 동작했는지
   상세히 설명

속도보다 이해를 우선한다. 각 milestone은 작은 학습 사이클로 취급한다.

## Milestone 구조

### BF-M0 — 툴체인 기반선

- **결과:** Docker Linux devcontainer에서 cross toolchain(gcc, binutils,
  xorriso, limine)이 준비되고, 최소 static ELF를 QEMU `-kernel` direct
  boot로 띄우는 sanity check 통과
- **Exit gate:** QEMU serial 출력에서 sanity check 바이너리의 출력 확인

### BF-M1 — 최소 kernel 자체 빌드

- **결과:** kernel.org 소스를 자체 `.config`로 빌드한 `vmlinuz`가 QEMU
  `-kernel`로 부팅되고, init을 찾지 못해 kernel panic 발생
- **포함:** 최소 `.config` 구성(필요한 옵션만 하나씩 켜며 이해: 콘솔,
  virtio, devtmpfs 등)
- **Exit gate:** QEMU serial에 kernel boot 로그와 "no init found" 계열
  panic 메시지 확인 — 이는 실패가 아니라 "커널이 여기까지만 책임진다"는
  경계를 확인하는 의도된 gate
- **제외:** init, bootloader

### BF-M2 — 직접 만든 init (PID 1)

- **결과:** Rust로 작성한 정적 바이너리 init이 PID 1로 실행되어 `/proc`,
  `/sys`, `devtmpfs`를 mount하고 shell을 실행
- **포함:** initramfs(cpio) 패키징, QEMU `-kernel`/`-initrd` direct boot로
  검증 (bootloader는 아직 도입하지 않음)
- **Exit gate:** QEMU 콘솔에서 mount 결과와 shell prompt 확인
- **제외:** bootloader, ISO

### BF-M3 — 진짜 bootloader + hybrid ISO

- **결과:** Limine 설정 + `xorriso`로 kernel+initramfs+limine을 담은 El
  Torito hybrid ISO 생성, QEMU `-cdrom out/tars.iso`로 부팅
- **포함:** Limine config 작성, hybrid ISO 빌드 스크립트
- **Exit gate:** `-kernel`/`-initrd` 없이 `-cdrom`만으로 BF-M2와 동일한
  shell prompt 도달
- **제외:** 실머신 부팅

### BF-M4 — 종료 게이트

- **결과:** BF-M0~M3 전체를 재현 가능한 단일 스크립트로 묶고, 반복 실행해도
  매번 동일하게 shell prompt까지 도달
- **Exit gate:** 스크립트 3회 연속 실행 성공 (일관성 확인)

## 저장소 구조 (초기)

```text
tars-linux/
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── kernel/          # .config, 빌드 스크립트
├── init/            # Rust PID 1 구현
├── boot/            # Limine config, ISO 빌드 스크립트
└── devcontainer/     # Docker Linux 빌드 환경
```

세부 디렉터리는 구현 단계에서 조정될 수 있다.

## 검증 방법

각 milestone의 exit gate는 QEMU serial 출력 매칭으로 검증한다. 자동화된
테스트 프레임워크 도입은 BF-M4 이후, 이 서브프로젝트가 안정화된 뒤 별도로
판단한다.
