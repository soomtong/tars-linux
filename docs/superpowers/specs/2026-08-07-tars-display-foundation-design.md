# TARS Display Foundation — Design

**Date:** 2026-08-07
**Status:** DF-M0 complete (2026-08-07); DF-M1 plan not yet written

## 배경

Boot Foundation(BF-M0~M4, `2026-08-01-tars-boot-foundation-design.md`)이
kernel + Limine bootloader + Rust init(PID 1) + hybrid ISO로 QEMU에서 fish
shell prompt까지 부팅하는 것을 끝냈다. 최종 비전에 있던 후보(compositor/KMS,
PTY/terminal, input policy, IME, 패키지 관리자, AI 도구 통합) 중 이번
서브프로젝트가 다룰 영역을 고르면서, "compositor"라는 이름이 실제로는 창
합성·입력 라우팅까지 포함하는 것처럼 들려 범위가 불명확했다. 그래서 이번
서브프로젝트는 **Display Foundation**으로 이름 붙이고, 범위를 "KMS/DRM으로
화면에 픽셀을 띄우는 것"까지로 좁혔다 — 실제 compositor(창 합성, 입력
라우팅, 여러 클라이언트 관리)는 Display Foundation이 만든 기반 위에서
움직이는 별도의 이후 서브프로젝트로 남긴다.

지금까지 QEMU 부팅은 전부 serial 콘솔(`-serial stdio -display none`)만
썼고, kernel `.config`는 화면 출력과 관련된 어떤 서브시스템도 켜져 있지
않다(`CONFIG_DRM`, `CONFIG_FB` 모두 `is not set`). 더 근본적으로 **PCI 버스
지원 자체가 꺼져 있다**(`CONFIG_PCI is not set`, 2026-08-07 `kernel/.config`
확인) — Boot Foundation은 initramfs를 통째로 메모리에 올려 부팅했기 때문에
디스크/PCI 드라이버가 전혀 필요 없었다. Display Foundation은 QEMU의 가상
GPU가 PCI 장치로 노출되므로, 화면 출력 이전에 PCI 버스 지원부터 새로 켜야
한다는 뜻이다.

## 목표 (MVP)

QEMU에서 가상 GPU에 대해 DRM/KMS로 모드를 설정하고 framebuffer에 단색을
채워, 화면에 그 색이 실제로 나타나는 것을 **자동화된 스크립트**로 검증한다.
텍스트(fish 배너)가 아니라 픽셀이 결과물이라는 점이 Boot Foundation과의
핵심 차이다.

## 비목표

- 실제 compositor(창 합성, 여러 클라이언트, 입력 라우팅) — 이후 별도
  서브프로젝트
- Wayland/X11 프로토콜 구현 — 최종 비전에서 이미 "최소화" 대상으로 명시됨
- GPU 가속(3D, OpenGL/Vulkan) — 2D framebuffer 쓰기만 다룬다
- 실제 GPU 드라이버(i915, amdgpu 등) — QEMU 가상 GPU만 대상
- 여러 모니터/플레인 관리, 해상도 자동 협상(EDID 파싱 등) — 고정 해상도
  하나만 다룬다

## 핵심 설계 결정

### 1. 가상 GPU: virtio-gpu

QEMU가 제공하는 가상 GPU 중 `virtio-gpu`(paravirtualized, QEMU/KVM
표준)를 쓴다. 대안인 `bochs-display`/`stdvga`(단순 VGA 에뮬레이션)보다
프로토콜은 복잡하지만, 실제 클라우드 VM 대부분이 이 경로를 쓰므로 자료가
많고 커널 드라이버(`CONFIG_DRM_VIRTIO_GPU`)도 잘 관리된다. QEMU 실행 시
`-device virtio-gpu-pci`로 노출한다.

### 2. 검증: QEMU screendump → PPM → 픽셀 검사

QEMU는 `-display none`이어도 가상 GPU가 그린 framebuffer 상태를 내부적으로
유지하므로, QEMU monitor(제어 콘솔, 사람이 읽는 텍스트 프로토콜인 HMP)에
`screendump <path>` 명령을 보내면 현재 화면을 PPM 이미지 파일로 저장할 수
있다. monitor에 명령을 보내는 방법으로 `socat` 같은 새 패키지를 추가하는
대신, bash 내장 기능인 `/dev/tcp`(TCP 소켓을 파일 디스크립터처럼 다루는 bash
전용 확장)로 `-monitor tcp:127.0.0.1:<port>,server,nowait`에 직접 접속해
`screendump` 한 줄을 보낸다 — 지금까지 전체 체인이 순수 bash 스크립트로
구성된 방식과 일관된다. PPM에서 특정 좌표의 픽셀 색을 읽는 데는
`ImageMagick`(devcontainer에 패키지 하나만 추가)의 `magick ... txt:-` 출력을
`grep`으로 검사한다 — 지금까지의 "serial 로그 grep → PASS/FAIL" 패턴을
그대로 잇는다.

### 3. 픽셀을 그리는 코드: 별도 최소 바이너리, raw DRM ioctl

DRM 초기화 코드는 `init`(PID 1, `init/`) 안에 넣지 않고 새 디렉터리(예:
`kms/`)에 별도 Rust 바이너리로 만들어 init이 부팅 과정에서 실행한다. init은
지금까지 mount + fish exec만 하는 간결한 역할을 유지해 왔고, 화면 초기화
같은 실험적이고 자주 바뀔 코드를 섞으면 그 경계가 무너진다.

이 바이너리는 Rust용 DRM 라이브러리(`drm` crate 등)로 감싸지 않고,
`/dev/dri/card0`를 직접 열어 DRM ioctl(모드 리소스 조회 →
dumb buffer 생성 → `mmap` → 픽셀 채우기 → CRTC에 모드 설정)을 순서대로
호출한다. Limine 때는 "설정이 단순해서" 고른 외부 도구라 binary release를
그대로 썼지만(BF-M3), DRM/KMS는 이번 서브프로젝트가 배우려는 대상 그
자체이므로 라이브러리로 메커니즘을 감출 이유가 없다 — init을 프레임워크
없이 직접 만든 것과 같은 원칙이다.

## Milestones

### DF-M0 — 검증 파이프라인 sanity check

- **결과:** DRM 드라이버 없이도 `-device virtio-gpu-pci`를 붙여 부팅하고,
  `/dev/tcp` + QEMU monitor `screendump` + ImageMagick으로 이어지는 검증
  파이프라인 자체가 정상 동작함을 확인
- **포함:** devcontainer에 `imagemagick` 패키지 추가, screendump/픽셀 검사
  스크립트 초안
- **Exit gate:** PPM 파일이 기대한 해상도로 생성되고 ImageMagick으로 읽힘
  (색상 내용은 아직 검사하지 않음 — 드라이버가 없으니 정의되지 않은 화면)
- **제외:** DRM 드라이버, 커널 설정 변경

### DF-M1 — PCI + DRM/virtio-gpu 드라이버 활성화

- **결과:** `CONFIG_PCI`부터 `CONFIG_DRM`, `CONFIG_DRM_VIRTIO_GPU`까지
  필요한 kernel 옵션을 켜고 재빌드, 부팅 시 드라이버가 가상 GPU를 인식
- **포함:** kernel `.config` 변경, `/dev/dri/card0` 노드가 devtmpfs에
  생성되는지 init 로그로 확인
- **Exit gate:** serial(dmesg)에 virtio-gpu 드라이버 probe 성공 로그가
  보이고 `/dev/dri/card0`가 존재
- **제외:** 실제로 화면에 그리는 것(다음 milestone)

### DF-M2 — 픽셀 그리기(MVP 종료점)

- **결과:** `kms/` 바이너리가 DRM ioctl로 모드 설정 + dumb buffer 채우기를
  수행해 화면에 지정한 단색이 나타남
- **포함:** `kms/` Rust 바이너리, init이 부팅 시 이를 실행하도록 연결
- **Exit gate:** DF-M0의 검증 파이프라인으로 screendump → 지정 좌표 픽셀
  색이 의도한 색과 일치
- **제외:** 여러 색/도형, 사용자 입력에 반응하는 그리기

### DF-M3 — 종료 게이트

- **결과:** DF-M0~M2 전체를 재현 가능한 단일 스크립트로 묶고, 반복
  실행해도 매번 동일하게 픽셀 검증을 통과
- **Exit gate:** 스크립트 3회 연속 실행 성공(BF-M4와 동일한 패턴)

## 저장소 구조 (추가분)

```text
tars-linux/
├── kms/             # DRM ioctl 기반 최소 pixel-draw 바이너리 (Rust, DF-M2)
├── kernel/          # .config에 PCI/DRM/virtio-gpu 옵션 추가 (DF-M1)
├── init/            # 부팅 시 kms/ 바이너리 실행하도록 확장 (DF-M2)
└── devcontainer/     # imagemagick 패키지 추가 (DF-M0)
```

세부 디렉터리/파일명은 구현 단계에서 조정될 수 있다.

## 검증 방법

각 milestone의 exit gate는 QEMU screendump로 얻은 PPM 이미지의 지정 좌표
픽셀 값을 ImageMagick + grep으로 검사해 자동화한다(DF-M1까지는 색상 대신
serial dmesg 로그 grep을 함께 쓴다). Boot Foundation과 마찬가지로 각
milestone이 끝난 뒤에야 다음 milestone의 상세 plan을 작성한다 — 전체를
한 번에 미리 설계하지 않는다.
