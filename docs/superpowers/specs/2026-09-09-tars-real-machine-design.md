# TARS Real Machine — Design

**Date:** 2026-09-09
**Status:** **진행 중 — RM-M0 · RM-M1 완료(2026-09-09·10), RM-M2 · RM-M3 남음.**
milestone 넷을 계획했고 plan 둘이 `docs/superpowers/plans/`에 있다. 아래 실측
절 셋("착수 전에" · "RM-M0이" · "RM-M1이")이 실행이 증명한 것을 담는다.
착수 전 게이트 기준선은 아홉 체인 3/3으로 **19분 40.02초**(FP-M1 시점),
RM-M0 뒤 열 체인 3/3으로 **19분 52.07초**, RM-M1 뒤 **20분 23.41초**다.

`docs/decisions/project_target_hardware.md`가 2026-08-31에 지목한 것을 집는다 —
**지금 커널은 노트북에서 아예 못 뜬다.** 사용자가 그날 "TARS는 노트북 사용을
포함한다"고 정했고, 그 기준으로 `kernel/.config`를 훑어 보니 되켤 것이
`ACPI_EC` 한 줄이 아니었다.

**이름.** `docs/decisions/project_target_hardware.md`가 일의 이름을 이미
지어 뒀다 — "`ACPI_EC`를 되켠다"가 아니라 **"실머신용 `.config`를 만든다"**다.
저장소 어휘로 **Real Machine (RM)**이라 부른다. `RM`은 비어 있다(BF · DF · TF ·
ZM · CP · IP · PM · HD · TR · CM · GL · CN · CS · SP · RC · CC · HI · IS · SH ·
FP가 쓰인 것 전부다).

## 한 줄 요약

**이 커널이 일반 x86_64 노트북에서 뜨게 한다.** UEFI로 부팅하고, EFI GOP
프레임버퍼에 픽셀을 내고, USB 키보드로 입력을 받고, NVMe·SATA 저장장치를
본다.

```
  BIOS(SeaBIOS) + virtio-gpu + PS/2 + virtio-blk     ← 지금. QEMU에서만 산다
  UEFI(OVMF)   + simpledrm   + USB + NVMe/AHCI       ← RM이 더한다
```

**`.config`는 하나다.** 둘이 아니다 — 아래 결정 1.

## 왜 지금인가

FP를 닫은 뒤 손에 남은 후보 셋 중 이것을 사용자가 골랐다. 근거는
`project_target_hardware`가 이미 적어 둔 것이다.

**후보 셋 중 이것만이 "TARS가 무엇인가"를 건드린다.** HI가 남긴 둘(기호 확장 ·
모아주기)과 IS 비목표(상태 줄 색을 설정으로)는 이미 되는 것을 넓히는 일이다.
이것은 **아직 아무 실기에서도 안 되는 것**을 되게 하는 일이다.

그리고 이 후보에는 다른 것들에 없는 무게가 하나 있다 —
`project_target_hardware`가 **"게이트가 이 방향을 검증할 수 없다"**고 적어 뒀다.
아홉 체인이 전부 QEMU 위에 서 있고, 이 서브프로젝트는 QEMU에 없는 것을 향한다.

## 조사가 그 문장을 절반 뒤집었다

**"게이트가 검증할 수 없다"는 절반만 참이다.** 그 문장은 `ACPI_EC` 하나를 보고
쓴 것이고(QEMU `pc` 기계에 EC가 없다는 CC-M0의 실측), 나머지 항목에는 QEMU에
길이 있다.

| 항목 | 게이트가 볼 수 있나 | 수단 |
|---|---|---|
| `EFI` | **볼 수 있다** | OVMF(`ovmf` 패키지) + limine의 `BOOTX64.EFI` |
| `RELOCATABLE` | **볼 수 있다** | UEFI에서만 필요해진다 — 아래 실측 2 |
| `DRM_SIMPLEDRM` | **볼 수 있다** | OVMF의 GOP 프레임버퍼가 그대로 `card0`이 된다 |
| `PCI_MSI` | **볼 수 있다** | `-machine q35`는 PCIe라 MSI를 협상한다 |
| `USB_SUPPORT`·`USB_HID` | **볼 수 있다** | `-device qemu-xhci -device usb-kbd`, 그리고 `i8042=off` |
| `BLK_DEV_NVME` | **볼 수 있다** | `-device nvme` |
| `ATA`·`SATA_AHCI` | **볼 수 있다** | q35의 `ich9-ahci` |
| `ACPI_EC` | **못 본다** | QEMU에 EC(`PNP0C09`)가 없다 |
| `DRM_I915`·`DRM_AMDGPU` | **못 본다** | 실 GPU가 없다 |
| `ACPI_AC`·`ACPI_BATTERY`·`THERMAL` | **못 본다** | 실기의 ACPI 객체가 없다 |

**못 보는 것이 열에서 셋으로 줄어든다.** 그리고 그 셋 중 둘(i915 · amdgpu)은
애초에 안 켜기로 정했다(결정 3).

**저장소에 이미 있어서 안 받아 와도 되는 것이 있다.** `boot/limine-binary/`에
`BOOTX64.EFI`와 `limine-uefi-cd.bin`이 들어 있다 — BF-M0이 limine 바이너리
릴리스를 통째로 커밋했고 그때는 BIOS 파일 둘만 썼다. **UEFI 경로의 부트로더
쪽은 3년 전부터 저장소에 있었다.**

## 착수 전에 실측한 것 — **다시 조사하지 말 것**

design을 쓰기 전에 스파이크를 돌렸다. 아래 다섯은 실행이 증명한 것이고,
이 문서의 결정 전부가 그 위에 서 있다.

### 실측 1. OVMF는 arm64 컨테이너에 그대로 깔린다

`apt-cache show ovmf`가 `Architecture: all`이다. 펌웨어 이미지는 x86_64
바이너리지만 **패키지는 아키텍처 중립**이라, 컨테이너가 arm64인 채로
`/usr/share/OVMF/OVMF_CODE_4M.fd`(3.6MB)를 얻는다. ZM-M3이 컨테이너를 arm64로
옮긴 뒤 게스트용 x86_64 산출물은 전부 크로스 컴파일이거나 amd64 패키지에서
조달했는데, **이것은 세 번째 종류다 — 아키텍처가 없는 데이터.**
`ncurses-base`·`libc-bin`의 로케일과 같은 종류다.

`OVMF_CODE_4M.fd`를 고른다. `.secboot.fd`는 Secure Boot를 켠 것이고 우리 커널은
서명이 없다. `OVMF_VARS_4M.fd`는 **쓰기가 되어야 하므로 매번 복사해서 쓴다** —
읽기 전용으로 물리면 펌웨어가 NVRAM 변수를 못 써서 부트 항목을 만들지 못한다.

### 실측 2. 진짜 벽은 `EFI`가 아니라 `RELOCATABLE`이었다

`CONFIG_EFI=y`·`SYSFB_SIMPLEFB=y`·`DRM_SIMPLEDRM=y`를 켜고 하이브리드 ISO를
OVMF로 부팅했는데 **시리얼에 커널 줄이 한 줄도 안 나왔다.** OVMF의
`BdsDxe: starting Boot0001`까지만 찍히고 320바이트에서 멈춘다.

limine의 메뉴와 에러는 GOP 콘솔로 가고 우리는 `-display none`이라 **아무것도
안 보인다.** `limine.conf`에 `serial: yes` 한 줄을 넣자 답이 나왔다.

```
PANIC: linux: Non-relocatable kernel could not be loaded at required address 0x1000000
Stacktrace:
  [0x1e28c685] <panic+0x155>
  [0x1e2aa505] <linux_load+0x805>
```

**`CONFIG_RELOCATABLE`이 꺼져 있었다.** BIOS에서는 0x1000000이 비어 있어서
`PHYSICAL_START=0x1000000`짜리 비재배치 커널이 그대로 실렸는데, UEFI에서는
펌웨어가 그 자리를 쓰고 있어서 limine이 옮길 수가 없다.

**이것이 이 서브프로젝트에서 가장 값진 30초였다.** `EFI`만 켜고 끝날 일이라고
믿었으면 "UEFI에서 커널이 조용히 죽는다"를 붙들고 config 항목을 하나씩
켰을 것이다. **부트로더의 말이 안 들리는 것이 병이었고, `serial: yes`가
처방이었다.**

`RELOCATABLE=y`가 `olddefconfig`로 끌고 온 것 다섯: `RANDOMIZE_BASE=y`(KASLR) ·
`X86_NEED_RELOCS=y` · `RANDOMIZE_MEMORY=y` ·
`RANDOMIZE_MEMORY_PHYSICAL_PADDING=0x0` · `ARCH_VMLINUX_NEEDS_RELOCS=y`.
**KASLR이 저절로 켜졌다** — 안 켜기로 누를 수 있지만 누르지 않는다(결정 6).

### 실측 3. simpledrm이 EFI GOP 위에서 그대로 `card0`이 된다 — i915도 amdgpu도 없이

`RELOCATABLE`을 켜자 전체가 떴다. virtio-gpu를 **하나도 안 물리고**다.

```
[    0.000000] efi: EFI v2.7 by Debian distribution of EDK II
[    0.000000] efi: SMBIOS=0x1f588000 ACPI=0x1f77e000 ACPI 2.0=0x1f77e014
[    0.449039] [drm] Initialized simpledrm 1.0.0 for simple-framebuffer.0 on minor 0
tars-init: /dev/dri/card0 exists
terminal: grid 155x47 (fb 1280x800)
Welcome to fish, the friendly interactive shell
terminal: status> text=EN  신세벌 PCS  쿼티  CAPS
```

**TARS가 `/dev/dri/card0`에 KMS ioctl을 직접 쏘는 방식(`terminal/src/drm.zig`)이
simpledrm에서도 그대로 통한다.** simpledrm은 모드가 하나뿐인 KMS 드라이버라
`drmModeSetCrtc`가 펌웨어가 잡아 둔 모드를 그대로 다시 세운다. 그 모드가
실기에서는 **패널의 네이티브 해상도**다.

**그러므로 `DRM_I915`와 `DRM_AMDGPU`가 필요 없다**(결정 3). 이것이 이
서브프로젝트의 크기를 가장 크게 줄인 실측이다.

**프레임버퍼 해상도가 갈린다.** virtio-gpu 체인들은 1024x768이고 OVMF의 GOP
기본은 **1280x800**이라 격자가 `155x47`이다. 새 체인의 판정은 이 수를 전제로
쓴다 — **다른 체인의 격자 수를 베껴 오면 안 된다.**

**첫 프레임이 27.9밀리초에서 64.2밀리초로 늘었다.** simpledrm은 섀도 버퍼를
두고 damage 영역을 memcpy로 밀어내는 구조이고 픽셀 수도 1.30배다
(1280×800 / 1024×768). 게이트 판정에 첫 프레임 시간은 안 쓰이므로 위험이 아니고,
**RC-M0이 재기만 하고 안 고친 `fill` 84.7%가 이 기계에서는 더 비싸다**는 사실만
적어 둔다.

### 실측 4. 노트북 장치 넷이 한 번에 다 붙었다 — 코드를 한 글자도 안 고쳤다

`-machine q35,i8042=off` + `qemu-xhci` + `usb-kbd` + `nvme`로 부팅한 결과다.

```
[    0.342675] acpi PNP0A08:00: _OSC: OS supports [ExtendedConfig ASPM ClockPM Segments MSI HPX-Type3]
[    0.425637] nvme nvme0: pci function 0000:00:04.0
[    0.468432] xhci_hcd 0000:00:03.0: xHCI Host Controller
[    0.748084] usb 1-1: new high-speed USB device number 2 using xhci_hcd
[    0.896637] input: QEMU QEMU USB Keyboard as /devices/pci0000:00/.../0003:0627:0001.0001/input/input1
[    0.955339] hid-generic 0003:0627:0001.0001: input: USB HID v1.11 Keyboard [QEMU QEMU USB Keyboard]
tars-init: keyboard device /dev/input/event1 (QEMU QEMU USB Keyboard)
terminal: opened /dev/input/event1
```

**마지막 두 줄이 이 서브프로젝트에서 가장 좋은 소식이다.** PS/2 컨트롤러를
아예 끄고(`i8042=off`) USB 키보드만 남겼는데 **`init`도 `terminal`도 한 글자도
안 고쳤다.** HD-M2가 키보드를 이름이 아니라 capability로 찾게 만들어 둔 것이
여기서 값을 냈다 — 그때 design이 "노트북 실 하드웨어로 가는 방향"을 근거로
그 모양을 골랐고, 3주 뒤에 그 근거가 실행으로 확인됐다.

`_OSC` 줄의 `MSI`가 `PCI_MSI=y`의 증거다. q35는 PCIe이므로 장치들이 MSI로
인터럽트를 받는다.

### 실측 5. `.config`를 켜는 데는 층이 있고 한 번에 안 드러난다

`CONFIG_USB_SUPPORT=y`를 켜도 **`CONFIG_USB`는 안 켜진다.** `USB_SUPPORT`는
메뉴일 뿐이고, `USB`를 켜야 `USB_XHCI_HCD`·`USB_STORAGE` 항목이 `.config`에
**나타난다.** 즉 켜기는 세 층이다.

```
USB_SUPPORT (메뉴)  →  USB (코어)  →  USB_XHCI_HCD·USB_STORAGE (드라이버)
ATA (메뉴)          →  SATA_AHCI·ATA_PIIX
SCSI (메뉴)         →  BLK_DEV_SD
```

**`project_kernel_config`의 되접기 규칙이 그래서 라운드마다 필요하다** —
`# CONFIG_X is not set` 줄이 없는 항목은 `sd`로 켤 수가 없고, 되접은 뒤에야
줄이 생긴다. 스파이크는 라운드 셋을 돌아 고정점에 닿았다.

**저절로 켜진 것 중 눈여겨볼 셋.** `USB_HID=y`(우리가 명시 안 했다) ·
`I2C_HID=y`(노트북 I2C 터치패드/키보드 경로) · `HID_*` 벤더 quirk 열하나
(A4TECH·BELKIN·CHERRY·CHICONY·CYPRESS·EZKEY·ITE·KENSINGTON·MICROSOFT·
MONTEREY·REDRAGON — `default !EXPERT`라 켜진다). **셋 다 안 누른다** —
특정 기계가 없으므로 "이 키보드에서만 안 된다"를 없애는 값이 크다.

**bzImage 크기.** 2,933,760 → 3,060,736(M0, +4.3%) → 3,580,928(M1, +22.1%).

## 비목표

- **실기에서 실제로 부팅해 보기.** 사용자가 "특정 기계 없이 일반 x86_64
  노트북을 겁낸다"를 골랐다. 그래서 이 서브프로젝트의 판정은 전부 QEMU이고,
  **못 보는 셋(EC · GPU · 배터리/온도)은 "켜고 회귀가 없음"까지만 확인한다.**
  RM-M3이 USB 이미지를 만드는 데까지 가지만 꽂아 보는 것은 다음 사람 몫이다.
- **`DRM_I915`·`DRM_AMDGPU`.** 결정 3.
- **Secure Boot.** 커널에 서명이 없고 shim도 없다. 실기에서는 펌웨어 설정에서
  꺼야 한다 — RM-M3의 문서에 적는다.
- **`SUSPEND`(S3 절전).** PM-M0~M1이 시그널로 끄고 되살리는 데까지 갔고
  S3은 그때도 비목표였다. 노트북의 뚜껑 닫기가 절전이 되는 것은 별 서브프로젝트다
  (`ACPI_BUTTON`이 이미 켜져 있어 lid 이벤트는 이미 온다).
- **네트워크.** `CONFIG_NET is not set`이고 이 서브프로젝트가 건드리지 않는다.
- **`/config`를 파티션 테이블 위에 두기.** 지금 디스크 전체가 파티션 없는
  ext2다(`init/src/main.zig:54`). RM-M2는 **장치 이름만** 넓히고 파티션은
  건드리지 않는다.

## 결정

### 결정 1. `.config`는 하나다 — 사용자가 골랐다

후보 넷 중 "둘로 나눈다"를 안 골랐다. 근거는 `project_gate_latency`가 세운
문장이다 — **"게이트가 부팅하는 바이너리가 곧 제품이다."** 둘로 나누면 게이트가
초록인 것이 실기용 config에 대해 아무것도 말하지 않고, 둘이 때로 갈라진다.

대가는 **커널이 커지고 빌드가 느려지는 것**이고 게이트가 그것을 15~18배로
치른다. 실측이 그 대가를 재고 나서 결정을 확인한다(RM-M1 plan).

### 결정 2. 게이트에 열번째 체인을 하나 더한다 — 사용자가 골랐다

**기존 아홉은 한 글자도 안 건드린다.** 안 고른 쪽은 "아홉을 전부 q35+UEFI로
옮긴다"였고, 그러면 부팅이 깨졌을 때 어느 체인이 왜 깨졌는지를 가를 수 없다.
게이트가 지금 유일한 검증 수단이므로 그것을 흔드는 위험이 크다.

**구조적 사실 하나가 이 결정을 싸게 만든다** — 아홉 체인 중 부트로더를 실제로
지나는 것은 `boot/check.sh` 하나뿐이고, 나머지 여덟은 `-kernel`로 limine을
통째로 건너뛴다. 그래서 UEFI 경로를 더하는 것이 여덟에 닿지 않는다.

새 체인의 이름은 **`machine/check.sh`**다. 디렉터리 이름이 곧 체인 이름인
관례를 따른다(`boot` · `terminal` · `config` · `input` · `power` · `device` ·
`render` · `copy` · `hangul`). `CHAINS` 배열에 `"RM-M1:./machine/check.sh"`로
들어간다.

**커널 빌드가 늘지 않는다.** `check.sh`의 `clean()`이 회차마다 `kernel/build`를
지우지만 `build.sh`의 스탬프 때문에 첫 체인만 진짜로 빌드하고 나머지는
스킵한다. 열번째 체인이 더하는 것은 자기 부팅 시간뿐이다.

### 결정 3. `DRM_I915`와 `DRM_AMDGPU`는 안 켠다 — Claude가 정했다

**사용자가 자러 간 뒤에 정한 것이고, 근거가 셋이다.**

1. **실측 3이 필요 없음을 증명했다.** simpledrm이 EFI GOP 프레임버퍼를
   `/dev/dri/card0`으로 내놓고, TARS의 KMS 경로가 그 위에서 그대로 돈다.
   펌웨어가 잡아 둔 모드가 실기에서는 패널의 네이티브 해상도다.
2. **게이트가 볼 수 없다.** 실 GPU가 없으므로 켜도 게이트에서 단 한 번도
   probe되지 않는다. "켜 봤다"와 "된다"가 안 갈린다 — 사용자가 "config만 켜고
   게이트는 그대로 둔다"를 안 고른 이유와 같은 것이다.
3. **빌드 비용이 이 저장소에서 가장 비싼 항목이다.** amdgpu는 커널에서 가장 큰
   드라이버이고 i915도 크다. 게이트가 커널을 15~18회 빌드하므로 그 비용이
   그대로 곱해진다. `project_kernel_config`가 ACPI의 +2.589초를 재고 "15배는
   39초라 정책을 바꿀 이유가 못 된다"고 판단한 자리인데, 이쪽은 자릿수가 다르다.

**안 켜서 잃는 것을 명시한다** — 모드 변경(해상도 바꾸기) · 하드웨어 가속 ·
백라이트 밝기 제어 · 외부 모니터. TARS는 고정 격자에 글자를 그리는
터미널이므로 넷 다 지금 쓰지 않는다. **필요해지면 그때가 별 서브프로젝트다.**

### 결정 4. `limine.conf`에 `serial: yes`를 넣는다 — Claude가 정했다

실측 2가 이 줄 하나로 풀렸다. **부트로더가 실패하면 그 말이 시리얼로
나와야 한다** — 안 그러면 증상이 "커널이 조용히 안 뜬다"이고 원인에서 아주
멀다.

**BIOS 체인에도 함께 들어간다.** 지금 `boot/check.sh`는 이 줄 없이도 통과하지만
limine이 실패할 때 아무것도 안 보이는 사정은 BIOS에서도 같다. 한 파일이 두
경로를 다 태우므로 갈라 둘 자리가 없다 — **그리고 그것이 옳다.**

**대가는 시리얼 로그에 커서 이동 escape가 섞이는 것**이다. limine이 글자마다
`ESC[01;NNH`를 찍는다(실측 2의 로그를 보면 한 글자씩이다). 체인들의 `grep`은
전부 부분 문자열 매치이고 우리 쪽 줄에는 escape가 안 붙으므로 판정에 안
닿는다 — **하지만 로그를 사람이 읽을 때 시끄럽다.** 그래서 `boot/check.sh`가
`cat -v` 없이 읽는 자리를 확인하고 넘어간다(RM-M0 plan).

### 결정 5. ISO는 하나이고 BIOS·UEFI를 둘 다 태운다 — Claude가 정했다

두 ISO로 나누지 않는다. `xorriso`의 El Torito는 **부트 카탈로그에 항목 둘**을
담을 수 있고(BIOS는 `-b`, UEFI는 `--efi-boot`), 펌웨어가 자기 것을 고른다.
`boot/check.sh`는 SeaBIOS로 같은 ISO를 부팅하고 `machine/check.sh`는 OVMF로
부팅한다 — **같은 바이트를 두 펌웨어가 지난다는 것이 이 선택의 값이다.**

실기에서도 이 ISO 하나를 USB에 쓰면 UEFI든 legacy든 뜬다.

레시피는 limine이 문서화한 그대로다. `--protective-msdos-label`이 붙어야
펌웨어가 하이브리드 이미지를 GPT/MBR 혼동 없이 읽는다.

```
xorriso -as mkisofs -R -r -J \
  -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
  --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
  --protective-msdos-label "$STAGE" -o ../out/tars.iso
```

**`--protective-msdos-label`은 대시 둘이다.** 하나로 쓰면
`xorriso : FAILURE : -as mkisofs: Unrecognized option`이다 — 스파이크에서
한 번 밟았다.

`EFI/BOOT/BOOTX64.EFI`도 ISO 트리에 함께 넣는다. `limine-uefi-cd.bin`이
El Torito용 FAT 이미지이고, 트리의 `BOOTX64.EFI`는 이 ISO를 **USB에 dd로
쓴 뒤 펌웨어가 파일로 찾을 때** 쓰인다. 둘이 다른 경로다.

### 결정 6. KASLR을 안 누른다 — Claude가 정했다

`RELOCATABLE=y`가 `RANDOMIZE_BASE=y`를 끌고 왔다. 누를 수 있지만 누르지 않는다.

**근거는 "쓰지 않는 것은 안 켠다"의 반대편이다** — KASLR은 우리가 안 쓰는
기능이 아니라 **커널이 스스로 쓰는 방어**이고, 끄는 것은 방어를 벗기는
편집이다. `project_kernel_config`의 규율("이해하는 것은 끄고 이해하지 못하는
것은 남긴다")에서 이것은 **이해하지 못하는 쪽**이다 — 부팅 시간에 얼마를 더하고
무엇을 막는지 우리가 재 본 적이 없다.

스파이크가 KASLR이 켜진 채로 통과했으므로 게이트에 위험이 아니다.

### 결정 7. `i8042=off`로 PS/2를 아예 끈다 — Claude가 정했다

새 체인은 `-machine q35,i8042=off`로 돈다. **PS/2를 남겨 두면 USB 경로가 안
밟힌다** — `init`이 capability로 첫 키보드를 고르므로 PS/2가 먼저 열거되면
USB 키보드는 열리지도 않고 `usb-kbd`가 있으나 없으나 게이트가 초록이다.
실측 4가 `tars-init: keyboard device /dev/input/event1 (QEMU QEMU USB Keyboard)`를
찍은 것은 PS/2를 껐기 때문이다.

**IS-M1 실측 4와 같은 종류다** — "같은 것을 두 층이 지킬 때 위층을 확인하려면
아래층을 먼저 꺼야 한다."

### 결정 8. USB 호스트 컨트롤러 넷을 다 켠다 — Claude가 정했다

`USB_XHCI_HCD`(요즘 전부) · `USB_EHCI_HCD`(USB 2.0) · `USB_UHCI_HCD`(인텔
컴패니언) · `USB_OHCI_HCD`(AMD/VIA 컴패니언). 게이트가 밟는 것은 xHCI
하나뿐이다.

**"특정 기계가 없다"가 이 결정의 근거다.** 사용자가 후보 셋 중 "일반 x86_64
노트북"을 골랐으므로, 안 켠 컨트롤러 하나가 "그 노트북에서만 키보드가 안
된다"가 된다. 그 증상은 실기에서만 나타나고 게이트가 영영 못 본다 —
**게이트가 못 보는 자리에서는 넓게 켠다**는 것이 이 서브프로젝트의 기울기다.

같은 이유로 `HID_*` 벤더 quirk 열하나와 `I2C_HID`도 안 누른다(실측 5).

## Milestone 넷

| | 무엇 | 검증 |
|---|---|---|
| **RM-M0** | **UEFI로 뜬다.** `RELOCATABLE`·`EFI`·`SYSFB_SIMPLEFB`·`DRM_SIMPLEDRM` · 하이브리드 ISO · `serial: yes` · 열번째 체인 | `machine/check.sh`가 OVMF로 부팅해 simpledrm `card0`에 격자를 그린다 |
| **RM-M1** | **노트북 장치가 붙는다.** `PCI_MSI` · USB(HCD 넷 + HID + storage) · `BLK_DEV_NVME` · `ATA`/`SATA_AHCI` · `SCSI`/`BLK_DEV_SD` | 같은 체인이 `i8042=off`로 돌아 **USB 키보드만으로** 타이핑한다 |
| **RM-M2** | **설정 저장소를 찾는다.** `/dev/vda` 하드코딩을 후보 훑기로 | 체인이 NVMe 디스크에서 `tars.conf`를 읽는다 |
| **RM-M3** | **게이트가 못 보는 것들.** `ACPI_EC`·`ACPI_AC`·`ACPI_BATTERY`·`ACPI_PROCESSOR`·`THERMAL` + 실기용 USB 이미지와 문서 | QEMU에서 회귀 없음(음성 확인) + `docs/`에 꽂는 법 |

**RM-M0과 RM-M1의 경계가 "부팅"과 "장치"다.** M0이 끝난 시점에 새 체인은
UEFI로 뜨지만 키보드는 PS/2이고 저장장치는 없다 — **의도된 중간 상태다.**
SH-M1이 끝난 시점에 프롬프트의 한글이 깨져 보였던 것과 같은 종류의 갈림이다.

**RM-M2가 코드를 건드리는 유일한 milestone이다.** M0·M1·M3은 `.config`와
셸 스크립트뿐이다.

## RM-M0의 모양

**닿는 파일 여섯.**

1. **`devcontainer/Dockerfile`** — `ovmf` 한 줄. 이미지를 다시 빌드해야 한다.
2. **`kernel/.config`** — 넷을 켜고 되접은 고정점. `olddefconfig`가 40줄을
   더하고 6줄을 지운다.
3. **`boot/limine.conf`** — `serial: yes` 한 줄.
4. **`boot/make_iso.sh`** — 하이브리드 레시피. `EFI/BOOT/BOOTX64.EFI`와
   `limine-uefi-cd.bin`을 스테이지에 더한다.
5. **`machine/check.sh`** — 새 체인. OVMF로 같은 ISO를 부팅하고 격자를 본다.
6. **`check.sh`** — `CHAINS`에 한 줄.

**`machine/check.sh`의 판정 셋.** 하나만 보면 "안 뜬다"의 이유가 안 갈린다
(IS-M1 실측 5와 같은 종류).

| 보는 것 | 값 | 무엇이 갈리는가 |
|---|---|---|
| `efi: EFI v` | 있다 | **펌웨어가 UEFI다.** 없으면 OVMF가 아니라 SeaBIOS로 떴다 |
| `Initialized simpledrm` | 있다 | **GOP 프레임버퍼가 `card0`이 됐다** |
| `terminal: grid 155x47 (fb 1280x800)` | 정확히 이 수 | **네이티브 모드를 그대로 썼다.** 다른 수면 모드가 갈렸다 |

**`Welcome to fish`만 보는 것으로는 안 된다** — 그것은 `boot/check.sh`가 이미
보는 것이고, simpledrm이 실패해도 `init`이 시리얼 콘솔 셸로 폴백해서 그 줄이
나온다. **CC-M0/IS-M0이 겪은 "증상이 성공과 똑같다"의 자리다.**

**`machine/check.sh`는 `-cdrom`으로 ISO를 부팅한다** — 아홉 중 여덟이 쓰는
`-kernel` 직접 부팅으로는 부트로더도 UEFI도 안 지난다. 그래서 이 체인은
`boot/check.sh`의 골격을 따르고 `hangul/check.sh`의 판정 헬퍼를 따른다.

## 위험

**위험 1. OVMF가 느리다.** 펌웨어 초기화가 SeaBIOS보다 오래 걸린다. 스파이크는
셸 배너까지 30초 안에 닿았지만 게이트는 3회 돌고 부하가 다르다. **처방은
`boot/check.sh`가 이미 쓰는 것과 같다** — 고정 timeout이 아니라 배너가 나오면
즉시 끝내고 최대 120초 기다린다.

**위험 2. 커널이 커져서 게이트가 느려진다.** M1까지 가면 bzImage가 22% 크다.
빌드 시간을 재서 plan에 적는다 — 15배가 견딜 만한지가 결정 1의 대가다.
**게이트 시간의 잡음이 ±3분이므로**(IS-M0 실측 3) 단일 게이트 시간 차이로
판정하지 않고 커널 빌드 시간을 따로 잰다.
**→ 실현되지 않았다.** 배수가 15가 아니라 **1**이고(실측 8) 증가분이
5.68초다(실측 11). "15배"는 GL-M0·M1 이전에 쓰인 낡은 문장이었다.

**위험 3. `serial: yes`가 로그를 시끄럽게 만들어 기존 판정을 흔든다.** limine이
글자마다 escape를 찍는다. **`boot/check.sh`의 `grep -q "Welcome to fish"`는
부분 문자열이라 안 흔들리지만**, 로그 크기가 커지면 `last_frame` 같은 헬퍼가
느려질 수 있다. `boot/check.sh`만 ISO를 쓰고 그 체인은 `last_frame`을 안 쓴다 —
착수 전에 확인했다.

**위험 4. OVMF의 GOP 기본 모드가 QEMU 버전에 따라 다르다.** 판정이
`1280x800`을 못으로 박으면 컨테이너의 QEMU가 올라갈 때 깨진다. 지금은
QEMU 10.0.11이다. **깨지는 방식이 조용하지 않다**(격자 수가 안 맞아 exit 1)는
것이 이 위험을 감수하는 이유이고, 정확한 수를 보는 것이 결정 3("네이티브 모드를
그대로 쓴다")을 정면으로 보는 유일한 방법이다.

**위험 5. 이미지를 다시 빌드해야 한다.** `ovmf`가 첫 `RUN`에 들어가므로 그
뒤의 레이어(amd64 sysroot · Zig)가 전부 다시 돈다. 네트워크가 필요하고
`fish`·`zig` 버전이 그때와 달라질 수 있다. **버전은 Dockerfile에 못으로 박혀
있다**(`ZIG_VERSION=0.16.0`)는 것이 이 위험의 크기를 줄인다 — 다만 apt
패키지는 안 박혀 있다.

## RM-M0이 실행으로 증명한 것 — **다시 조사하지 말 것**

### 실측 6. `boot/check.sh`가 깨졌고, 깨진 이유가 좋은 쪽이었다

plan Task 4의 판정("`boot/check.sh`가 여전히 통과한다")이 잡았다.

```
Boot reached the fish banner after ~3s
init mounted all four filesystems
FAIL: init never gave up on the terminal
```

**터미널이 뜬 것이 실패였다.** 그 체인이 검증하는 것은 감독 루프의 **포기
경로**(`MAX_FAST_RESTARTS = 3`)이고, 그것을 밟으려면 `/dev/dri/card0`이
없어야 한다. 여태 그 전제는 "virtio-gpu를 안 물렸다"에 얹힌 **암묵적인**
것이었는데, `SYSFB_SIMPLEFB`와 `DRM_SIMPLEDRM`을 켜자 **limine이 넘긴 VGA
프레임버퍼만으로도 `card0`이 생겼다.**

**커널 쪽을 되돌리지 않았다.** BIOS 부팅에서도 픽셀이 나오게 된 것은 잃을 수
없는 개선이다 — legacy 기계에서도 화면이 뜬다는 뜻이고, 이 서브프로젝트가
향하는 방향 그 자체다. 처방은 `boot/check.sh`에 `-vga none` 한 줄이고,
**그것이 전제를 암묵에서 명시로 옮긴다.**

`-vga none`으로 돌린 결과가 옛 계약을 정확히 되살렸다.

```
tars-init: /dev/dri/card0 not found
tars-init: started terminal (pid 19) / (pid 25) / (pid 26)
tars-init: giving up on terminal after 3 fast exits
```

**design 결정 2("기존 아홉은 한 글자도 안 건드린다")를 지키지 못했다.**
한 줄을 건드렸고, 이유는 "새 체인이 옛 체인을 흔들어서"가 아니라 **커널
설정 변경이 옛 체인의 전제를 바꿔서**다. 결정 2가 막으려던 위험(체인들을
한꺼번에 흔드는 것)과는 다른 종류다.

### 실측 7. `serial: yes`가 들리게 만든 말은 `grep`으로 못 읽는다

음성 확인에서 드러났다. `CONFIG_RELOCATABLE`을 끄고 체인을 돌리니 exit 1은
맞는데 **`fail()`이 찍기로 한 문맥 줄이 비어 나왔다.**

limine은 글자마다 커서 이동 escape를 끼워 넣는다 —
`P` `ESC[01;02H` `A` `ESC[01;03H` `N` … 이라서 `grep "PANIC"`이 아무것도 못
찾는다. 처방은 실패 경로에서만 escape를 걷어내는 `denoise()`이고, 걷어내자
말이 도로 붙었다.

```
FAIL: expected fish banner not found (waited 120s)
  linux: Loading kernel `boot():/boot/bzImage`...PANIC: linux: Non-relocatable
  kernel could not be loaded at required address 0x1000000Stacktrace:  [0x1e28c685] <panic+0x155>
```

**"들린다"와 "읽힌다"가 다르다.** `serial: yes`는 말을 시리얼로 보냈을 뿐이고,
그 말을 판정이 쓰려면 한 겹이 더 필요했다. **우리 쪽 줄에는 escape가 안
붙으므로 판정 셋은 이 처리 없이도 맞는다** — 걷어내기가 필요한 곳은 사람이
읽는 자리뿐이다.

### 실측 8. 게이트가 커널을 15회가 아니라 **1회** 빌드한다

`project_kernel_config`가 "루트 게이트의 `clean()`이 매 회차 `kernel/build`를
지우므로 커널 빌드 15회다. 설정 변경이 빌드에 더하는 시간은 그대로 15배가
된다"고 적어 뒀다. **그 문장이 낡았다.**

게이트 로그를 세어 보면 실제 빌드가 **1회**이고 `kernel: bzImage matches
.config and build.sh, skipping make`가 **29회**다(체인 10 × 3회 = 30번 호출).

- **GL-M0이 `clean()`을 게이트 시작 1회로 옮겼다.**
- **GL-M1이 `.config`와 `build.sh`의 sha256 스탬프를 넣었다.**

**그래서 design 결정 1의 대가가 15배가 아니라 1배다.** RM-M1의 실측(+5.68초)에
15를 곱하면 85초지만 실제로는 5.68초다. **문서에 적힌 배수는 게이트 시간과
같은 종류로 낡는다**(IS-M0 실측 2와 같은 교훈이고, 이번에는 시간이 아니라
구조다).

### 실측 9. 게이트가 열 체인 3/3으로 19분 52.07초다

직전 아홉 체인 값이 19분 40.02초였으므로 **+12.05초**다. 체인 하나가 3회
늘고 커널이 4.3% 커졌는데도 잡음(±3분) 안이다 — 새 체인의 부팅이 5초로
싸고, 커널을 한 번만 빌드하기 때문이다(실측 8).

## RM-M1이 실행으로 증명한 것 — **다시 조사하지 말 것**

### 실측 10. `.config`의 층이 정확히 셋이었고 되접기가 그것을 드러냈다

라운드마다 켜고 → 빌드 → 되접기를 셋 돌아 고정점에 닿았다. **우리가 손으로
한 줄도 안 적었는데 켜진 것 다섯**이 층이 제대로 접혔다는 증거다.

```
CONFIG_USB_HID=y        ← USB=y가 켰다
CONFIG_USB_XHCI_PCI=y   ← USB_XHCI_HCD=y가 켰다
CONFIG_USB_EHCI_PCI=y   ← USB_EHCI_HCD=y가 켰다
CONFIG_SATA_HOST=y      ← SATA_AHCI=y가 켰다
CONFIG_I2C_HID=y        ← HID_SUPPORT=y가 켰다 (노트북 I2C 터치패드/키보드)
```

**`USB_HID`를 명시하지 않은 것이 옳았다.** 적었으면 "이 줄이 이 기능을
켠다"가 틀린 기록이 된다 — 실제로 켜는 것은 `USB=y`다.

### 실측 11. 커널 빌드가 50.947초 → 56.627초다 (+5.68초, +11.1%)

결정 1("`.config`는 하나")의 대가다. 같은 컨테이너에서 `rm -rf kernel/build`
뒤에 잰 값이고, `git stash`로 RM-M0 상태를 되살려 **같은 세션에서** 둘을
쟀다(IS-M0 실측 2의 규율 — 다른 날에 잰 기준선과 비교하지 않는다).

**게이트는 이것을 1배로 치른다**(실측 8). `project_kernel_config`가 ACPI에
대해 "15배는 39초라 정책을 바꿀 이유가 못 된다"고 판단했던 자리인데,
지금은 **5.68초**다. 결정 1을 다시 볼 이유가 없다.

bzImage는 3,060,736 → 3,580,928바이트(+17.0%)다.

### 실측 12. `i8042=off`가 없으면 이 milestone이 아무것도 안 본다

음성 확인이 design 결정 7을 정면으로 증명했다. 그 플래그만 빼고 체인을
돌렸다.

```
FAIL: init did not pick the USB keyboard (is i8042 still on? did USB_HID build?)
  tars-init: keyboard device /dev/input/event1 (AT Translated Set 2 keyboard)
```

`usb-kbd`도 `qemu-xhci`도 그대로 물려 있고 커널의 USB 스택도 그대로인데,
**PS/2가 있다는 것만으로 `init`이 그쪽을 골랐다.** 그 플래그가 없었으면
`usb-kbd`를 아예 안 물려도 게이트가 초록이었을 것이다.

**IS-M1 실측 4의 사촌이다** — "같은 것을 두 층이 지킬 때 위층을 확인하려면
아래층을 먼저 꺼야 한다." 그때는 호스트 검사 넷을 되돌려야 게이트 판정이
보였고, 이번에는 PS/2를 꺼야 USB 판정이 보인다.

### 실측 13. 게이트가 열 체인 3/3으로 20분 23.41초다

RM-M0 뒤 값(19분 52.07초)에서 **+31.34초**다. 설명되는 값이다 — 커널 빌드
+5.68초(1배, 실측 8·11)와 체인이 새로 하는 일(모니터 연결 · 글자 셋 타이핑
0.4초씩 · 확인 대기 2초 · NVMe와 xHCI 초기화)이 3회 돈다.

착수 전 아홉 체인 값 19분 40.02초에서 보면 **전체 +43.39초**이고, 그 사이에
게이트가 **부팅 33회에서 36회**로 늘고 커널이 22.1% 커졌다.

### 실측 14. "장치가 보인다"와 "키가 화면에 닿는다"가 다르다

체인의 판정 여섯은 전부 커널이 만든 줄이거나 `init`이 연 결과다. 일곱째만이
**USB 키보드로 친 글자가 PTY를 지나 격자에 그려지는가**를 본다.

```
=== typing 'usb' on the USB keyboard ===
keys from the USB keyboard reached the grid
```

QEMU 모니터의 `sendkey`가 `usb-kbd`로 간다는 것은 문서가 아니라 이 줄이
증명한다 — `i8042=off`라 경쟁자가 없으므로 다른 해석이 없다.

## 이 세션의 예외 — 편집을 Claude Code가 한다

사용자가 2026-09-09에 브레인스토밍 중간에 "나 이제 자러 가니까 이번 태스크의
모든 작업을 마무리해줘"라고 정했다. `CLAUDE.md`의 기본 규칙("파일 편집은
사용자가")에 대한 **이 서브프로젝트 한정 예외**이고 SH·FP 세션의 예외와 같은
종류다.

**남은 결정 여섯(결정 3~8)을 Claude가 정했고 근거를 각 결정에 적었다.**
사용자가 고른 것은 둘(결정 1 · 2)이다.

관련: [[project_target_hardware]] · [[project_kernel_config]] ·
[[project_device_discovery]] · [[project_gate_latency]] ·
[[project_gate_chain_composition]]
