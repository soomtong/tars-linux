# TARS Boot Foundation — BF-M2 Design

**Date:** 2026-08-04
**Status:** Approved (design phase), plan not yet written

## 배경

[BF-M1](2026-08-03-tars-boot-foundation-bf-m1-design.md)에서 kernel.org
6.18.42 LTS를 `allnoconfig`에서 반복 확장한 `.config`로 빌드하고, init
바이너리가 없어 `Kernel panic - not syncing: No working init found`가
발생하는 지점까지 검증했다. 이 문서는 다음 단계인 **BF-M2 — 직접 만든
init(PID 1)**을 다룬다. 전체 milestone 구조와 배경은
[design doc](2026-08-01-tars-boot-foundation-design.md)을 참고.

## 목표

Rust로 작성한 init 바이너리가 PID 1로 실행되어 `/proc`, `/sys`, `/dev`
(devtmpfs)를 mount한 뒤 bash를 실행해 shell prompt에 도달한다. BF-M1과
동일하게 QEMU `-kernel`/`-initrd` direct boot를 유지한다 (bootloader는
아직 도입하지 않음).

## 비목표

- bootloader(Limine), hybrid ISO — BF-M3
- coreutils(`ls`, `cat` 등) 포함 — exit gate는 "shell prompt 등장"이며,
  실제 명령 실행 가능 여부는 이번 milestone의 범위 밖
- musl 등 정적 링크 — 이번 milestone은 의도적으로 glibc 동적 링크를
  선택해 ELF 인터프리터/동적 링커 로딩 경로를 학습 대상으로 삼는다
  (아래 핵심 설계 결정 1 참고)
- shell 자체 구현 — init만 직접 만들고, shell은 데스크톱 Linux 바이너리를
  재사용한다

## 핵심 설계 결정

### 1. Rust 빌드 전략: std + glibc 동적 링크

`x86_64-unknown-linux-gnu` 타깃으로 표준 라이브러리를 그대로 사용해
동적 링크 바이너리를 만든다. `no_std` + raw syscall이나 musl 정적 링크
대신 이 방식을 택한 이유:

- host가 이미 x86_64 Linux devcontainer이므로 크로스 컴파일 설정이
  필요 없다
- init 자신도 glibc 동적 링크이므로, 커널이 ELF 헤더의 `PT_INTERP`를
  읽어 `/lib64/ld-linux-x86-64.so.2`를 먼저 실행한다는 사실을 init
  바이너리 자체로 확인하게 된다 — "커널이 어디까지 하고 그다음부터는
  내 코드"라는 이번 서브프로젝트의 핵심 목표와 자연스럽게 이어진다
- bash를 그대로 재사용하기로 했으므로(핵심 설계 결정 3), initramfs에
  동적 링커/공유 라이브러리를 담는 작업이 어차피 필요하다 — init까지
  같은 방식으로 통일하면 배울 대상이 늘지 않고 오히려 하나로 줄어든다

### 2. Syscall 호출: `libc` crate (raw FFI)

`nix` 같은 safe wrapper 대신 `libc` crate로 `mount(2)`, `execve(2)`를
`unsafe extern "C"` 시그니처 그대로 호출한다. 인자 순서와 반환값
(`errno`)을 직접 다뤄야 하므로 "이 syscall이 정확히 무엇을 하는지"가
가장 선명하게 드러난다. `nix`의 추상화는 이 학습 목표에는 노이즈다.

### 3. init 동작 순서

```
1. mount("proc",  "/proc", "proc",     0, NULL)
2. mount("sysfs", "/sys",  "sysfs",    0, NULL)
3. mount("devtmpfs", "/dev", "devtmpfs", 0, NULL)
4. execve("/bin/bash", ["/bin/bash"], envp)
```

각 `mount()` 호출은 반환값을 확인해 실패 시 `errno`를 serial(표준
출력)로 로그만 남기고 계속 진행한다 — 하나의 mount 실패로 나머지
단계까지 막지 않는다. 마지막 `execve()`는 **fork 없이 자기 자신을
대체**한다: init 프로세스(PID 1)가 그대로 bash가 된다. bash가 종료되면
PID 1이 사라지므로 커널이 panic하는데, 이는 이번 milestone에서 의도적으로
막지 않는다 — "PID 1은 죽으면 안 된다"는 경계를 보여주는 결과이며,
exit gate(프롬프트 확인) 이후 QEMU를 강제 종료하므로 실제로 이 경로를
밟을 필요도 없다.

### 4. initramfs 구성: bash + 의존 라이브러리 복사

```text
/init                          # Rust init 바이너리, 커널이 PID 1로 실행
/bin/bash                      # devcontainer의 bash 바이너리 그대로 복사
/lib64/ld-linux-x86-64.so.2    # 동적 링커
/lib/x86_64-linux-gnu/*.so*    # ldd init && ldd bash 결과의 합집합
```

`kernel/make_initrd.sh`를 확장해 `ldd`로 `/init`과 `/bin/bash` 각각의
의존 라이브러리를 추적하고, devcontainer 안의 실제 파일을 그대로
cpio에 담는다. coreutils는 포함하지 않는다(비목표 참고).

### 5. devcontainer에 Rust 툴체인 추가: rustup

`devcontainer/Dockerfile`에 rustup 설치 스텝을 추가해 stable
`x86_64-unknown-linux-gnu` 타깃을 설치한다. Debian bookworm의 apt
`rustc`/`cargo`(1.63 계열, 구버전)는 최신 crate와 호환성 문제가 생길
수 있어 배제한다.

### 6. 검증: timeout 강제 종료 + 프롬프트 grep

bash는 interactive 입력을 기다리므로 자연 종료되지 않는다. BF-M0/BF-M1과
동일하게 `timeout N초`로 QEMU를 강제 종료한 뒤, 로그에서 bash 프롬프트
문자열(`bash-5.x#` 또는 유사 패턴)을 grep해 PASS/FAIL을 판정한다.

## 저장소 구조 변경

```text
init/
├── Cargo.toml       # libc crate 의존성
└── src/
    └── main.rs       # PID 1 진입점: mount 3회 + execve
kernel/
├── make_initrd.sh    # bash + ldd 의존 라이브러리까지 담도록 확장
└── check.sh           # exit gate 메시지를 프롬프트 문자열로 변경
```

`devcontainer/Dockerfile`에 rustup 설치 스텝을 추가한다.

## QEMU 부팅 검증

BF-M1의 `check.sh` 패턴(빌드 → 실행 → grep → PASS/FAIL)을 그대로
재사용한다.

```bash
qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -serial stdio -display none -no-reboot
```

Exit gate는 serial 로그에서 mount 결과 로그 이후 bash 프롬프트
문자열이 나타나는 것을 확인하는 것이다.

## 협업 방식

[BF-M0와 동일](2026-08-01-tars-boot-foundation-design.md#협업-방식): 설명
먼저 → 사용자가 직접 실행 → 결과 상세 설명. 승인된 내용의 git commit은
Claude Code가 대신 수행.

## 검증 방법

QEMU serial 출력에서 mount 로그 뒤 bash 프롬프트 문자열 확인. BF-M0/BF-M1의
`check.sh`와 동일한 검증 스타일을 유지한다.
