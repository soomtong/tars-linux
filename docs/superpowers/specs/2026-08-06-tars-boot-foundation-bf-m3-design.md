# TARS Boot Foundation — BF-M3 Design

**Date:** 2026-08-06
**Status:** Approved (design phase), plan not yet written

## 배경

[BF-M2](2026-08-04-tars-boot-foundation-bf-m2-design.md)에서 Rust로 작성한
init이 PID 1로 mount 3회 + controlling terminal 설정 후 fish로 execve해
shell prompt에 도달했다. 지금까지는 QEMU `-kernel`/`-initrd` direct
boot(BF-M1부터 유지)로 커널과 initramfs를 QEMU가 직접 주입했다 — 이는
실제 하드웨어에서는 통하지 않는 "편법"이라는 것이 [전체 design
doc](2026-08-01-tars-boot-foundation-design.md)에 이미 명시돼 있다. 이
문서는 그 편법을 걷어내는 **BF-M3 — 진짜 bootloader(Limine) + xorriso
hybrid ISO**를 다룬다.

## 목표

QEMU를 `-cdrom out/tars.iso` 하나만으로 실행해 BF-M2와 동일한 fish shell
prompt에 도달한다.

```
xorriso ISO (BIOS El Torito)
  → Limine (v12.5.2, BIOS 전용)
  → kernel/build.sh가 만든 bzImage (protocol: linux로 무수정 부팅)
  → init/가 만든 initrd.cpio
  → fish shell prompt
```

## 비목표

- UEFI 부팅 경로 검증(OVMF) — ISO에도 UEFI El Torito 항목(`limine-uefi-cd.bin`,
  `EFI/BOOT/BOOTX64.EFI`)을 포함하지 않는다. BF-M0가 이번 milestone 전까지
  xorriso/limine 자체를 devcontainer에 들이지 않은 것과 같은 이유(YAGNI):
  검증하지 못하는 경로를 미리 갖추지 않는다.
- 실머신(USB) 부팅 검증 — 전체 design doc에서 이미 다음 서브프로젝트로
  명시됨.
- Limine의 disk/partition install(`limine bios-install`을 raw disk
  대상으로 실행하는 시나리오) — 이번 milestone은 CD 이미지 대상으로만
  실행한다.
- coreutils 등 shell 안에서 실행 가능한 명령 확장 — BF-M2와 동일하게 exit
  gate는 "shell prompt 등장"이다.

## 핵심 설계 결정

### 1. Limine 조달: `v12.5.2` binary release 다운로드, host 도구만 직접 make

Debian trixie apt 저장소에는 Limine 패키지가 없다(공식 확인, 2026-08-06
WebSearch로 실측 — Debian bug tracker에 RFP(Request For Packaging)만
존재). 따라서 GitHub에서 직접 받아야 한다.

**정정(2026-08-06, 구현 시작 직전 재검토):** 처음에는 git 소스를 태그로
clone해 `./bootstrap`(autotools) → `./configure --enable-bios-cd` →
`make`로 전체를 빌드하기로 했다. 그러나 실제로 GitHub Releases의
`limine-binary.tar.gz` 자산을 받아 내용을 확인한 결과, 이 안에 이미
컴파일된 `limine-bios.sys`/`limine-bios-cd.bin`과 host 도구(`limine`
CLI, `bios-install`에 쓰는 그 도구) 소스 `limine.c` + 최소 `Makefile`
(`cc -std=c99 limine.c -o limine`, 그 이상 의존성 없음)만 들어있음을
확인했다. Limine은 kernel/init과 달리 이 프로젝트가 내부 동작을
배우거나 수정하려는 대상이 아니라 "설정이 단순해서" 고른 외부 도구다
(전체 design doc 핵심 설계 결정 표 참고) — 부트섹터 어셈블리까지
직접 조립할 학습 이득이 없는데 `nasm`/`autoconf`/`automake` 세 패키지를
devcontainer에 추가로 들이는 비용만 크다. 그래서 **binary release를
받아 부트로더 바이너리는 그대로 쓰고, host 도구(`limine`)만 이미 있는
`gcc`로 직접 빌드하는 방식**으로 바꾼다. `boot/build.sh`가 release
tarball URL(버전이 URL에 고정됨 — 재현성 유지)을 다운로드해 없으면
풀고, `make -C limine-binary`로 host 도구를 빌드한다.

### 2. Config 포맷: `limine.conf`(v12.x), `protocol: linux`로 무수정 kernel 부팅

Limine 공식 `CONFIG.md`(v12.x, 2026-08-06 WebFetch로 실측)를 직접 확인해
`protocol: linux`가 kernel.org의 표준 bzImage를 GRUB과 동일한 방식으로
무수정 부팅 지원함을 확인했다. 이 프로젝트는 kernel을 직접 빌드하지만
Linux boot protocol 자체를 바꾸지는 않으므로, Limine 고유 프로토콜
대신 이 표준 경로를 택한다. initramfs는 `module_path`로 지정한다
(Linux protocol에는 별도의 "initrd" 키가 없고 `module_path`가 그
역할을 겸함 — 공식 문서로 실측 확인).

```
timeout: 0

/TARS
    protocol: linux
    kernel_path: boot():/boot/bzImage
    module_path: boot():/boot/initrd.cpio
    cmdline: console=ttyS0
```

`boot():`는 Limine이 자신을 로드한 부팅 볼륨을 가리키는 표기다(공식
예시에서 확인). 단일 ISO9660 볼륨이므로 파티션 번호를 붙이지 않는다.

### 3. ISO 생성: BIOS El Torito만, `limine bios-install` 필수

Limine 공식 `USAGE.md`(v12.x, 2026-08-06 WebFetch로 verbatim 확인)의
hybrid ISO 절차에서 UEFI 관련 부분(`--efi-boot`, `-efi-boot-part`,
`-hfsplus`, `EFI/BOOT/` 디렉터리)을 제거하고 BIOS 전용으로 축소한다.

```
xorriso -as mkisofs -R -r -J \
        -b boot/limine/limine-bios-cd.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        <staging dir> -o out/tars.iso

limine bios-install out/tars.iso
```

**정정(2026-08-06, 설계 대화 중 실측으로 뒤집힘):** 처음에는 "El Torito
CD 부팅은 파티션/디스크 설치가 필요 없다"고 가정했으나, 공식 `USAGE.md`를
직접 읽어보니 ISO 생성 뒤에도 `limine bios-install`을 실행해야 한다는
점이 명시돼 있었다. `-no-emul-boot`로 지정한 El Torito boot catalog는
`limine-bios-cd.bin`을 raw 이미지로 로드할 뿐이고, ISO의 부트 섹터에
bootstrap 코드를 심는 별도 단계가 여전히 필요하다. 이 프로젝트가
반복적으로 확인해온 "실측 기반 결론도 재검증 없이 믿지 않는다"는
원칙([BF-M2 design doc](2026-08-04-tars-boot-foundation-bf-m2-design.md)의
fish/terminfo 재실측 사례와 동일한 패턴)이 design 단계에서도 그대로
적용된 사례다.

`limine-bios.sys`와 `limine.conf`는 공식 문서가 허용하는 네 위치(`root`,
`limine`, `boot`, `boot/limine`) 중 `boot/limine/`으로 통일해 배치한다.
`limine-bios-cd.bin`도 같은 위치에 둔다.

### 4. 저장소 구조: `boot/` 신설, kernel/init과 동일한 build.sh+check.sh 패턴

새 최상위 디렉터리 `boot/`를 만들고, `kernel/`(`build.sh` + `src/` +
`build/` + `check.sh`)과 `init/`(`Cargo.toml` + `src/` + `target/`)에서
이미 확립된 "서브시스템마다 독립적인 빌드/검증 스크립트를 갖는다" 패턴을
그대로 반복한다. 대안으로 `kernel/check.sh`를 확장해 ISO 빌드까지
포함시키는 방법도 검토했으나, "커널이 어디까지 책임지고 어디서부터
우리 도구/코드인가"를 구분하려는 이 프로젝트의 핵심 목적(부트로더는
커널과 별개 책임 영역)과 어긋나고 전체 design doc의 원래 디렉터리
스케치와도 맞지 않아 기각했다.

### 5. 검증 범위: BIOS만, QEMU 기본 SeaBIOS로 검증

QEMU 기본 machine은 이미 BIOS(SeaBIOS)이므로 별도 펌웨어 설정 없이
`-cdrom out/tars.iso`만으로 검증 가능하다. UEFI 검증에는 OVMF 펌웨어를
devcontainer에 추가로 준비해야 하는데, 이번 milestone 범위(비목표 참고)
밖이므로 들이지 않는다.

## 저장소 구조 변경

```text
tars-linux/
├── boot/                      # 신설
│   ├── limine.conf            # 커밋 대상 (kernel의 .config와 같은 위상)
│   ├── build.sh                # limine-binary release 다운로드(없으면) + host 도구 make
│   ├── make_iso.sh             # 스테이징 + xorriso + limine bios-install → out/tars.iso
│   ├── check.sh                # make_iso.sh 실행 후 QEMU -cdrom 부팅 검증
│   └── limine-binary/          # gitignore 대상 — 다운로드/압축 해제된 release + make 산출물(limine)
├── kernel/                     # 기존, 변경 없음
├── init/                       # 기존, 변경 없음
└── out/                        # 신설, gitignore 대상 — tars.iso
```

`.gitignore`에 `boot/limine-binary/`, `out/`을 추가한다.

`boot/check.sh`는 BF-M2의 `kernel/check.sh`가 `build.sh`와 init cargo
build를 자체 호출하는 것과 동일하게, 전체 체인(kernel build → init
build → initrd 패키징 → limine build → ISO 생성 → `limine bios-install`
→ QEMU 부팅)을 한 번에 실행한다.

## QEMU 부팅 검증

```bash
timeout 15 qemu-system-x86_64 \
  -cdrom out/tars.iso \
  -serial stdio -display none -no-reboot
```

`-kernel`/`-initrd` 옵션이 전혀 없다는 점이 BF-M2 대비 핵심 차이다 —
QEMU가 커널을 대신 주입해주지 않고, Limine이 ISO 안에서 직접 커널을
찾아 부팅한다. Exit gate는 BF-M2와 동일하게 serial 로그에서 fish 배너
문자열(`Welcome to fish, the friendly interactive shell`)을 확인하는
것이다. BF-M1처럼 "의도된 실패" 게이트는 없다 — 이번 milestone은 실제로
shell prompt까지 도달해야 완료로 간주한다.

## 협업 방식

[BF-M0와 동일](2026-08-01-tars-boot-foundation-design.md#협업-방식): 설명
먼저 → 사용자가 직접 실행 → 결과 상세 설명. 승인된 내용의 git commit은
Claude Code가 대신 수행.

## 검증 방법

QEMU serial 출력에서 fish 배너 문자열 확인. BF-M0~BF-M2의 `check.sh`와
동일한 검증 스타일(빌드 → 실행 → grep → PASS/FAIL)을 유지한다.
