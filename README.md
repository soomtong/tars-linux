# TARS

직접 빌드한 Linux 커널 위에, 직접 만든 init(PID 1)과 터미널을 올린 시스템이다.
셸까지 가는 길에 배포판의 부품을 쓰지 않는다 — 커널이 어디까지 책임지고
어디서부터 우리 코드인지를 매 단계 확인하면서 만든다.

```
xorriso hybrid ISO → Limine → 자체 빌드 커널 → Zig init(PID 1)
                                                  ├── /terminal (DRM/KMS + ghostty-vt)
                                                  └── fish
```

## 준비

빌드는 컨테이너 안에서만 된다. 커널과 게스트 바이너리가 x86_64 크로스
툴체인을 쓰는데 그것이 이미지 안에만 있기 때문이다.

```bash
docker build -t tars-devcontainer -f devcontainer/Dockerfile .
```

`--platform`을 붙이지 않는다. 호스트(Apple Silicon)와 같은 arm64로 돌고,
게스트용 x86_64 산출물은 크로스 컴파일로 만든다
(`docs/decisions/project_build_host_arch.md`).

## 빌드

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  set -e
  (cd kernel   && ./build.sh)                    # bzImage
  (cd init     && zig build)                     # PID 1
  (cd terminal && ./prepare.sh)                  # vendor + terminal 바이너리
  (cd kernel   && ./make_initrd.sh)              # initrd.cpio
  (cd boot     && ./build.sh && ./make_iso.sh)   # out/tars.iso
'
```

각 스크립트는 입력의 sha256을 산출물 옆에 적어 두고 대조하므로, 바뀐 것이
없으면 건너뛴다. `terminal/src`만 고쳤다면 `terminal/prepare.sh` 한 줄이면
된다.

## 로컬(macOS)에서 화면 띄워 보기

게이트는 컨테이너 안에서 QEMU를 돌리므로 언제나 `-display none`이다. 눈으로
보려면 호스트의 QEMU로 같은 산출물을 부팅하면 된다 — 컨테이너를 거치지
않아서 오히려 빠르다(부팅 3~4초).

```bash
brew install qemu   # 한 번만
```

빠른 경로. 커널과 initrd를 QEMU가 직접 올린다.

```bash
qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci \
  -display cocoa \
  -serial stdio \
  -no-reboot
```

실제 부팅 경로. limine이 ISO에서 읽는 것까지 그대로 밟는다.

```bash
qemu-system-x86_64 -cdrom out/tars.iso \
  -vga none -device virtio-gpu-pci \
  -display cocoa -serial stdio -no-reboot
```

- 창에는 우리가 그린 화면이 뜨고, 커널·init·terminal의 로그는
  `-serial stdio`라 터미널로 흐른다.
- 창이 포커스를 가지면 키가 PS/2 → evdev → `input.zig`로 들어간다. copy
  mode도 그대로 된다 — `Cmd+Shift+C`로 진입, `/`로 검색, `n`·`N`으로 왕복,
  `y`로 복사.
- 키보드·마우스 grab을 놓는 것은 `Ctrl+Alt+G`, 끝내는 것은 창을 닫거나
  `Ctrl+C`.
### 화면 한 장만 파일로 받기

창을 안 띄우고 프레임 한 장만 뜨려면 QEMU monitor의 `screendump`을 쓴다.
`-monitor stdio`로 열어 두고 손으로 쳐도 되고, 이렇게 자동으로 해도 된다.

```bash
( sleep 12; echo "screendump /tmp/tars.ppm"; sleep 3; echo quit ) | \
qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage -initrd kernel/initrd.cpio \
  -append "console=ttyS0" -vga none -device virtio-gpu-pci \
  -display none -serial file:/tmp/tars.log -monitor stdio -no-reboot

sips -s format png /tmp/tars.ppm --out /tmp/tars.png && open /tmp/tars.png
```

1280×800 PPM이 3,072,016바이트로 나오고 `sips`가 PNG로 바꾼다.

`terminal/check.sh`가 남기는 `out/tf/*.ppm`을 기대하면 안 된다 — 그
스크립트는 실패했을 때만 남기고 성공하면 지운다(`terminal/check.sh:311`).

이 부팅은 판정이 아니다. 재현성을 보증하는 것은 컨테이너 안의 QEMU이고
버전도 다를 수 있다. 눈으로 보는 용도로 쓰고, 통과 여부는 아래 게이트로
정한다.

## VM에서 다른 배포판처럼 띄우기

위 명령들이 `-vga none -device virtio-gpu-pci`를 붙이는 것은 게이트 체인들과
같은 경로를 밟기 위한 것이고 필수가 아니다. `out/tars.iso`는 옵션 없이
`-cdrom` 하나만 줘도 뜬다.

```bash
qemu-system-x86_64 -m 1024 -cdrom out/tars.iso \
  -display cocoa -serial stdio -no-reboot
```

이때 픽셀은 virtio-gpu가 아니라 Limine이 펌웨어(BIOS VBE · UEFI GOP)에서 잡아
커널에 넘긴 프레임버퍼 위의 simpledrm에서 나온다 — 아래 실기 노트북이 밟는
것과 같은 경로다. 시리얼에 이렇게 남는다.

```
[drm] Initialized simpledrm 1.0.0 for simple-framebuffer.0 on minor 0
terminal: grid 155x47 (fb 1280x800)
```

그래서 VM이 어떤 디스플레이 장치를 주든 대체로 상관없다. 커널에 켜 둔 DRM
드라이버는 `SIMPLEDRM`과 `VIRTIO_GPU` 둘뿐이라 VMware의 vmwgfx나 QXL은 자기
드라이버로 안 붙지만, 그 장치들도 펌웨어가 선형 프레임버퍼를 남기므로 simpledrm이
받는다. 다만 확인한 것은 QEMU의 기본 VGA와 virtio-gpu 둘뿐이다 —
VirtualBox·VMware에서 직접 띄워 보지는 않았다.

### VM에 주어야 하는 것

| 항목 | 값 | 왜 |
|---|---|---|
| CPU | x86_64 | arm64 빌드가 없다 |
| 메모리 | 1GB (최소 512MB) | 84MB짜리 initramfs가 tmpfs로 풀린다. QEMU 기본 128MB면 기계가 아예 안 켜진다 — `gate_lib.sh`의 `GUEST_MEM=512`가 그것 때문이다 |
| 펌웨어 | BIOS · UEFI 아무거나 | El Torito 항목 둘이 한 ISO에 있다 |
| Secure Boot | 끈다 | 아래 실기 절과 같은 이유다 |
| 디스크 | 없어도 된다 | 붙이면 설정이 남는다(아래) |
| 네트워크 | 안 된다 | `# CONFIG_NET is not set` |

키보드는 따로 줄 것이 없다. VM이 기본으로 주는 PS/2(`AT Translated Set 2
keyboard`)를 `init`이 capability로 골라 잡는다. USB 키보드만 있는 VM도 된다 —
`machine/check.sh`가 `i8042=off`로 PS/2를 없애고 그 경로만 남겨 검증한다.

### UTM (Apple Silicon)

호스트가 arm64라 x86_64 게스트는 무조건 에뮬레이션이다. VirtualBox와 VMware
Fusion은 Apple Silicon에서 ARM 게스트만 돌리므로 쓸 수 없고, GUI로 다루려면
UTM이다(속은 같은 QEMU다).

```bash
brew install --cask utm
```

New VM → Emulate(Virtualize가 아니다) → Other → Boot ISO에 `out/tars.iso` →
Architecture `x86_64` → 메모리 1024MB 이상. 디스크는 안 만들어도 된다.

Intel Mac이나 x86 호스트라면 VirtualBox·VMware Fusion에서도 "Other Linux
(64-bit)"로 ISO를 물리면 된다.

### VM에 설정 디스크 붙이기

실기의 USB 스틱과 같은 것을 파일로 만든다. 라벨 규칙은 아래 실기 절과 같고,
macOS에는 `mkfs.ext2`가 없으니 컨테이너에서 만든다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  mkdir -p /tmp/seed && printf "hangul_layout=sebeol_3p3\n" > /tmp/seed/tars.conf
  dd if=/dev/zero of=out/tars-config.img bs=1M count=64 status=none
  mkfs.ext2 -F -q -m 0 -L tars-config -d /tmp/seed out/tars-config.img
'

qemu-system-x86_64 -m 1024 -cdrom out/tars.iso \
  -drive file=out/tars-config.img,if=virtio,format=raw \
  -display cocoa -serial stdio -no-reboot
```

오래 쓸 이미지는 `out/` 밖에 둔다 — 루트 `check.sh`가 시작할 때 `out/`을
지운다. UTM이면 이 `.img`를 두 번째 드라이브(raw)로 추가하면 `sda`로 잡힌다.

디스크가 없으면 시리얼에 이렇게 나오고 부팅은 그대로 된다.

```
tars-init: no disk labelled tars-* among 14 candidates
tars-init: no config storage, using defaults
```

### 설치는 안 된다

인스톨러가 없다. live ISO 하나뿐이고 디스크에 설치하는 경로가 없다. 게스트
안에서 만든 파일은 `/config`에 쓴 것 말고 재부팅하면 전부 사라진다 —
initramfs가 tmpfs이기 때문이다. `HANDOFF.md`가 다음 서브프로젝트 후보 1번으로
올려 둔 것이 이것이다.

## 실기 노트북에 꽂아 보기

`out/tars.iso`를 그대로 USB에 쓰면 된다. 하이브리드 ISO라 변환이 필요 없고
(El Torito 항목 둘 — BIOS와 UEFI), 같은 바이트를 게이트의 두 체인이 각각
SeaBIOS와 OVMF로 부팅한다.

먼저 `diskutil list`로 디스크 번호를 확인한다. 아래 `<N>`을 그대로
복사해 붙이면 안 된다 — 번호를 틀리면 자기 기계의 디스크를 지운다.

```bash
diskutil list                       # 어느 것이 USB인지 크기와 이름으로 확인한다
diskutil unmountDisk /dev/disk<N>   # 안 하면 dd가 Resource busy로 죽는다
sudo dd if=out/tars.iso of=/dev/rdisk<N> bs=4m status=progress
sync
```

대상은 파티션이 아니라 디스크 전체다. `/dev/disk4s1`이 아니라
`/dev/disk4`이고, `rdisk`가 버퍼를 안 거쳐 훨씬 빠르다.

### 꽂기 전에 펌웨어에서 할 일

Secure Boot를 꺼야 한다. 우리 커널에는 서명이 없고 shim도 안 쓴다. 안 끄면
증상이 "부팅 항목이 아예 안 보인다"라 원인에서 아주 멀다 — USB가 안
읽히는 것으로 오해하기 쉽다. 보통 전원을 켜고 F2/Del/F12로 펌웨어 설정에
들어가 Security 아래에 있다.

### 설정을 부팅 사이에 남기려면

`init`은 ext2 라벨이 `tars-`로 시작하는 첫 블록 장치를 `/config`로 붙인다
(`/dev/vda` · `nvme0n1..3` · `sda..sdd` · `mmcblk0..1` 순으로 훑는다).
그런 디스크가 없으면 부팅은 그대로 되고 설정만 매번 사라진다.

```bash
# 두 번째 USB 스틱 하나를 통째로 설정 디스크로 쓸 때
mkfs.ext2 -F -m 0 -L tars-config /dev/sdX
```

파티션이 아니라 디스크 전체를 포맷한다 — 지금 `init`은 파티션을 안 본다.
그리고 노트북 내장 디스크는 GPT라 이 훑기에 걸리지 않는다(superblock 매직이
안 맞는다). 남의 파일시스템을 잡을 길이 없다는 뜻이다.

### 기계가 기억하는 것 둘

설정 디스크로 처음 뜬 기계의 rc에는 훅 두 줄이 들어 있다. 켜는 일이
없다 — 기본이 켜짐이다.

| 치는 것 | 무엇이 나오나 |
|---|---|
| `z <조각>` | 자주 간 디렉터리로 간다(`zoxide`). 배우는 것은 당신이 `cd`할 때다 |
| `Ctrl+R` | 쳤던 명령을 흐릿하게 찾는다(`fzf`). `Ctrl+T`는 파일, `Alt+C`는 디렉터리 |

훅은 도구가 있을 때만 걸린다(`command -v` · fish는 `type -q`). 그 관문을
지우면 도구가 없는 기계에서 부팅할 때 에러 줄이 찍힌다 — rc를 고치는 사람이
그 줄을 남겨 둘 이유다.

`tars.conf`에 `shell_config=off`를 적거나 cmdline에 `tars.noconfig`를 주면
rc가 안 읽히고 훅도 함께 안 걸린다. 그것이 맞는 동작이다 — rc를 끄는
탈출로가 우리가 더한 것까지 덮어야 한다.

### 셸 설정을 고쳤는데 셸이 안 뜨면

설정 디스크가 붙으면 `init`이 rc 파일 셋을 거기에 깔고 홈에서 링크로 잇는다
(`/config/bashrc` · `/config/zshrc` · `/config/fish.config`). 그 파일은
그때부터 당신 것이고, 우리는 그 안에 무엇이 들었는지 모른다 — 거기 적은 한
줄이 셸을 죽이면 그 셸로는 그것을 고칠 수 없다.

탈출로가 둘이고, 둘의 성격이 다르다.

| 증상 | 무엇이 구해 주나 |
|---|---|
| 셸이 뜨자마자 죽는다 | 아무것도 안 해도 된다. 감독자가 세 번 보고 나서 rc 없이 한 번 더 띄운다 |
| 셸이 매달린다(`read` 한 줄, 무한 루프) | 부팅 순간에 limine 메뉴에서 커널 cmdline에 `tars.noconfig`를 더한다 |

```
tars-init: console shell died 3 times fast, the rc files are the suspect; restarting it with -f
tars-init: to keep it that way put shell_config=off in /config/tars.conf, or tars.noconfig on the kernel command line
```

`tars.noconfig`는 `tars.conf`를 이긴다(우선순위: cmdline > `tars.conf` >
기본값). 그 한 번의 부팅에서만 rc를 안 읽으므로, 그동안 rc를 고치거나
`tars.conf`에 `shell_config=off`를 적어 두면 된다.

### 무엇을 기대하고 무엇을 기대하지 않는가

화면은 뜬다. 펌웨어가 잡아 둔 EFI GOP 프레임버퍼에 simpledrm이 붙고, 그
모드가 패널의 네이티브 해상도다. USB 키보드도 된다 — 허브를 거쳐 늦게
열거돼도 `init`이 최대 3초까지 기다린다.

안 되는 것을 미리 적어 둔다.

| 안 되는 것 | 왜 |
|---|---|
| 밝기 조절 · 외부 모니터 · GPU 가속 | `DRM_I915`·`DRM_AMDGPU`를 안 켰다(RM design 결정 3) |
| 절전(뚜껑 닫기) | `SUSPEND`(S3)가 비목표다. lid 이벤트는 이미 온다 |
| 네트워크 | `CONFIG_NET is not set` |
| 터치패드 | 커널에 드라이버는 있지만 `terminal`이 포인터를 안 읽는다 |
| 배터리 잔량 표시 | 커널은 읽지만 그것을 보여 주는 화면이 아직 없다 |

이 저장소의 어떤 게이트도 실기 부팅을 검증하지 않는다. 열한 체인이 전부
QEMU 위에 있고, `ACPI_EC`·실 GPU·배터리는 QEMU에 대상이 없어 "켜 봤다"에서
멈춘다. 꽂아 봤는데 안 되면 그것은 새로 발견된 사실이지 회귀가 아니다.

## 게이트

```bash
# 전체 — 열한 체인 × 3회차, 약 26분
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh

# 한 체인만
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash copy/check.sh
```

체인은 자기가 부팅할 것을 스스로 빌드하므로 앞의 빌드 절을 먼저 돌릴 필요가
없다. 다만 `check.sh`는 시작할 때 `out/`·`kernel/build`·`zig-out`을 지운다 —
`out/` 아래에 남긴 조사 로그가 있으면 먼저 빼낸다.

체인 목록은 `check.sh`의 `CHAINS` 배열 하나에 있다.

## 문서

| 파일 | 무엇 |
|---|---|
| `CLAUDE.md` | 이 저장소의 작업 규칙 |
| `HANDOFF.md` | 지금 어디까지 왔는지, 다음에 무엇을 하는지 |
| `MEMORY.md` | 세션을 넘어 유지되는 기억의 색인 (본문은 `docs/decisions/`) |
| `docs/superpowers/specs/` | 서브프로젝트별 design doc |
| `docs/superpowers/plans/` | milestone별 실행 plan |
