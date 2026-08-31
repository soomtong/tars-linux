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

**`--platform`을 붙이지 않는다.** 호스트(Apple Silicon)와 같은 arm64로 돌고,
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

게이트는 컨테이너 안에서 QEMU를 돌리므로 언제나 `-display none`이다. **눈으로
보려면 호스트의 QEMU로 같은 산출물을 부팅하면 된다** — 컨테이너를 거치지
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

- **창에는 우리가 그린 화면이 뜨고**, 커널·init·terminal의 로그는
  `-serial stdio`라 터미널로 흐른다.
- 창이 포커스를 가지면 키가 PS/2 → evdev → `input.zig`로 들어간다. **copy
  mode도 그대로 된다** — `Cmd+Shift+C`로 진입, `/`로 검색, `n`·`N`으로 왕복,
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

**`terminal/check.sh`가 남기는 `out/tf/*.ppm`을 기대하면 안 된다** — 그
스크립트는 **실패했을 때만** 남기고 성공하면 지운다(`terminal/check.sh:311`).

**이 부팅은 판정이 아니다.** 재현성을 보증하는 것은 컨테이너 안의 QEMU이고
버전도 다를 수 있다. 눈으로 보는 용도로 쓰고, 통과 여부는 아래 게이트로
정한다.

## 게이트

```bash
# 전체 — 여덟 체인 × 3회차, 약 16분
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh

# 한 체인만
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash copy/check.sh
```

체인은 자기가 부팅할 것을 스스로 빌드하므로 앞의 빌드 절을 먼저 돌릴 필요가
없다. 다만 `check.sh`는 시작할 때 `out/`·`kernel/build`·`zig-out`을 지운다 —
**`out/` 아래에 남긴 조사 로그가 있으면 먼저 빼낸다.**

체인 목록은 `check.sh`의 `CHAINS` 배열 하나에 있다.

## 문서

| 파일 | 무엇 |
|---|---|
| `CLAUDE.md` | 이 저장소의 작업 규칙 |
| `HANDOFF.md` | 지금 어디까지 왔는지, 다음에 무엇을 하는지 |
| `MEMORY.md` | 세션을 넘어 유지되는 기억의 색인 (본문은 `docs/decisions/`) |
| `docs/superpowers/specs/` | 서브프로젝트별 design doc |
| `docs/superpowers/plans/` | milestone별 실행 plan |
