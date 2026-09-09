---
name: project_real_machine
description: "일반 x86_64 노트북에서 뜨는 커널을 만드는 층(RM, 2026-09-09 착수 · RM-M0·M1 완료 · M2·M3 남음) — 진짜 벽은 CONFIG_EFI가 아니라 CONFIG_RELOCATABLE이었고 그것을 찾은 것은 limine.conf의 `serial: yes` 한 줄이다; simpledrm이 EFI GOP 프레임버퍼 위에 /dev/dri/card0을 그대로 내놓으므로 DRM_I915도 AMDGPU도 필요 없다; ovmf 패키지는 Architecture: all이라 arm64 컨테이너에 그대로 깔린다; .config를 켜는 데 층이 셋이라 되접기를 라운드마다 해야 다음 층 줄이 나타난다; i8042=off로 PS/2를 아예 끄지 않으면 USB 키보드 판정이 아무것도 안 본다; SYSFB_SIMPLEFB를 켠 것만으로 boot/check.sh의 암묵적 전제(card0이 없다)가 깨져 -vga none을 명시해야 했다; 게이트는 커널을 15회가 아니라 1회 빌드한다(GL-M0·M1 이후)"
metadata:
  node_type: memory
  type: project
---

`docs/decisions/project_target_hardware.md`가 2026-08-31에 "서브프로젝트 하나"로
지목한 것을 2026-09-09에 집었다. **일의 이름은 "`ACPI_EC`를 되켠다"가 아니라
"실머신용 `.config`를 만든다"**이고, 저장소 어휘로 **Real Machine (RM)**이다.
design은 `docs/superpowers/specs/2026-09-09-tars-real-machine-design.md`.

**사용자가 고른 것은 둘이다** — `.config`를 하나로 유지하고(둘로 안 나눔),
게이트에 **열번째 체인을 하나 더한다**(기존 아홉을 안 옮김). 그리고 대상은
특정 기계가 아니라 **"일반 x86_64 노트북"**이다. 나머지 결정 여섯은 사용자가
자러 간 뒤 Claude가 정했고 근거가 design에 적혀 있다.

## "게이트가 이 방향을 검증할 수 없다"는 절반만 참이었다

`project_target_hardware`의 그 문장은 `ACPI_EC` 하나를 보고 쓴 것이다. `ovmf`
패키지 하나로 나머지 대부분에 길이 났다.

| 항목 | 게이트가 보나 | 수단 |
|---|---|---|
| `EFI` · `RELOCATABLE` | **본다** | OVMF + limine의 `BOOTX64.EFI`(저장소에 이미 있었다) |
| `DRM_SIMPLEDRM` | **본다** | GOP 프레임버퍼가 그대로 `card0`이 된다 |
| `PCI_MSI` | **본다** | `-machine q35`(PCIe)의 `_OSC` 협상 |
| `USB_SUPPORT`·`USB_HID` | **본다** | `qemu-xhci` + `usb-kbd` + **`i8042=off`** |
| `BLK_DEV_NVME` · AHCI | **본다** | `-device nvme` · q35의 `ich9-ahci` |
| `ACPI_EC` · 실 GPU · 배터리/온도 | **못 본다** | QEMU에 EC도 GPU도 배터리도 없다 |

**못 보는 것이 열에서 셋으로 줄었고, 그 셋 중 둘은 안 켜기로 정했다.**

## 진짜 벽은 `EFI`가 아니라 `RELOCATABLE`이었다

`CONFIG_EFI`·`SYSFB_SIMPLEFB`·`DRM_SIMPLEDRM`을 켜고 UEFI로 부팅했는데
**시리얼이 320바이트에서 멈췄다.** OVMF의 `BdsDxe: starting Boot0001`까지만
찍힌다.

limine의 메뉴와 에러는 GOP 콘솔로만 가고 체인은 `-display none`이라 **아무것도
안 보인다.** `boot/limine.conf`에 `serial: yes` 한 줄을 넣자 답이 나왔다.

```
PANIC: linux: Non-relocatable kernel could not be loaded at required address 0x1000000
```

BIOS에서는 그 주소가 비어 있어서 `PHYSICAL_START=0x1000000`짜리 비재배치
커널이 그대로 실렸는데, UEFI에서는 펌웨어가 그 자리를 쓰고 있어서 limine이
옮길 수가 없다. **`CONFIG_RELOCATABLE=y`가 처방이고 `RANDOMIZE_BASE`(KASLR)가
딸려 온다 — 누르지 않았다**(커널이 스스로 쓰는 방어를 벗기는 편집이고 비용을
재 본 적이 없다).

**`serial: yes`가 없었으면 "UEFI에서 커널이 조용히 죽는다"를 붙들고 config
항목을 하나씩 켰을 것이다. 부트로더의 말이 안 들리는 것이 병이었다.**

**그런데 "들린다"와 "읽힌다"가 또 다르다.** limine은 글자마다 커서 이동
escape를 끼워 넣어서(`P` `ESC[01;02H` `A` `ESC[01;03H` `N` …) `grep "PANIC"`이
아무것도 못 찾는다. 음성 확인에서 문맥 줄이 비어 나와 드러났고, 처방은 실패
경로에서만 escape를 걷어내는 `denoise()`다.

## simpledrm 하나로 GPU 드라이버가 필요 없어진다

**이것이 이 서브프로젝트의 크기를 가장 크게 줄인 실측이다.**

TARS는 `/dev/dri/card0`에 KMS ioctl을 직접 쏜다(`terminal/src/drm.zig`).
simpledrm은 모드가 하나뿐인 KMS 드라이버이고 `SYSFB_SIMPLEFB`가 `screen_info`
에서 만든 `simple-framebuffer` 플랫폼 장치에 붙는다. **펌웨어가 잡아 둔 모드를
그대로 다시 세우므로, 실기에서는 그 자리가 패널의 네이티브 해상도다.**

```
[drm] Initialized simpledrm 1.0.0 for simple-framebuffer.0 on minor 0
tars-init: /dev/dri/card0 exists
terminal: grid 155x47 (fb 1280x800)      ← OVMF GOP 기본. virtio-gpu 없이
```

**그래서 `DRM_I915`·`DRM_AMDGPU`를 안 켠다.** 잃는 것은 모드 변경 · 가속 ·
백라이트 · 외부 모니터이고 넷 다 지금 안 쓴다. 켜면 게이트가 **단 한 번도
probe하지 못하는** 코드가 커널에서 가장 큰 드라이버 둘만큼 늘어난다.

## 설정을 켜는 데 층이 셋이라 되접기를 라운드마다 해야 한다

`CONFIG_USB_SUPPORT=y`를 켜도 **`CONFIG_USB`는 안 켜진다.** `USB_SUPPORT`는
메뉴일 뿐이고, `USB`를 켜야 `USB_XHCI_HCD`·`USB_STORAGE` 줄이 `.config`에
**나타난다.** `# CONFIG_X is not set` 줄이 없는 항목은 `sd`로 켤 수가 없다.

```
USB_SUPPORT (메뉴)  →  USB (코어)  →  USB_XHCI_HCD·USB_STORAGE (드라이버)
ATA (메뉴)          →  SATA_AHCI·ATA_PIIX
SCSI (메뉴)         →  BLK_DEV_SD
```

**우리가 손으로 한 줄도 안 적었는데 켜진 것 다섯**이 층이 제대로 접혔다는
증거다 — `USB_HID`(`USB=y`가 켰다) · `USB_XHCI_PCI` · `USB_EHCI_PCI` ·
`SATA_HOST` · `I2C_HID`(노트북 I2C 터치패드/키보드 경로).

**`USB_HID`를 명시하지 않은 것이 옳다** — 적었으면 "이 줄이 이 기능을 켠다"가
틀린 기록이 된다.

**저절로 켜진 `HID_*` 벤더 quirk 열하나와 `I2C_HID`를 안 누른다.** 특정 기계가
없으므로 "이 키보드에서만 안 된다"를 없애는 값이 크다. 같은 이유로 USB 호스트
컨트롤러 넷(xHCI · EHCI · UHCI · OHCI)을 다 켠다 — **게이트가 못 보는 자리에서는
넓게 켠다**가 이 서브프로젝트의 기울기다.

## `i8042=off`가 없으면 USB 키보드 판정이 아무것도 안 본다

`init`이 키보드를 capability로 고르므로(HD-M2) PS/2가 남아 있으면 그쪽을
먼저 잡는다. 그러면 `usb-kbd`가 있으나 없으나 게이트가 초록이다. 음성 확인이
증명했다.

```
FAIL: init did not pick the USB keyboard
  tars-init: keyboard device /dev/input/event1 (AT Translated Set 2 keyboard)
```

**IS-M1이 적은 것과 같은 규율이다 — 같은 것을 두 층이 지킬 때 위층을
확인하려면 아래층을 먼저 꺼야 한다.**

**그리고 PS/2를 끈 채로 코드를 한 글자도 안 고쳤다.** HD-M2가 키보드를 이름이
아니라 성질로 찾게 만들어 둔 것이 3주 뒤에 값을 냈다 — 그때 design이 근거로
댄 것이 정확히 "노트북 실 하드웨어로 가는 방향"이었다.

## 커널 설정 하나가 다른 체인의 암묵적 전제를 깼다

`boot/check.sh`가 검증하는 것은 감독 루프의 **포기 경로**
(`MAX_FAST_RESTARTS = 3`)이고, 그것을 밟으려면 `/dev/dri/card0`이 없어야 한다.
그 전제는 "virtio-gpu를 안 물렸다"에 얹힌 **암묵적인** 것이었는데,
`SYSFB_SIMPLEFB`+`DRM_SIMPLEDRM`을 켜자 **limine이 넘긴 VGA 프레임버퍼만으로도
card0이 생겨서** 터미널이 뜨고 체인이 죽었다.

```
FAIL: init never gave up on the terminal
```

**커널 쪽을 안 되돌렸다.** BIOS 부팅에서도 픽셀이 나오게 된 것은 legacy
기계에서도 화면이 뜬다는 뜻이라 잃을 수 없다. 처방은 `-vga none` 한 줄이고,
그것이 전제를 **암묵에서 명시로** 옮긴다.

**"기존 체인을 안 건드린다"는 결정이 깨진 이유가 "새 체인이 옛 체인을
흔들어서"가 아니라 "제품의 설정이 바뀌어서"다.** 둘은 다른 종류의 위험이다.

## 게이트는 커널을 15회가 아니라 1회 빌드한다

`project_kernel_config`가 "커널 빌드 15회, 설정 변경이 더하는 시간은 그대로
15배"라고 적어 뒀는데 **그 문장은 GL-M0·M1 이전의 것이다.** 게이트 로그를
세어 보면 실제 빌드 **1회**, `skipping make` **29회**다(체인 열 × 3회).

- GL-M0이 `clean()`을 게이트 시작 **1회**로 옮겼다.
- GL-M1이 `.config`와 `build.sh`의 sha256 스탬프를 넣었다.

**그래서 `.config`를 하나로 유지하는 대가가 15배가 아니라 1배다.** RM-M1의
노트북 장치들이 커널 빌드에 더한 5.68초(50.947 → 56.627초, +11.1%)가
게이트에서도 5.68초다. bzImage는 2,933,760 → 3,580,928바이트(+22.1%).

**문서에 적힌 배수는 게이트 시간과 같은 종류로 낡는다.**

## `ovmf`는 아키텍처가 없다

`apt-cache show ovmf`가 `Architecture: all`이다. 펌웨어 이미지는 x86_64
바이너리지만 패키지는 아키텍처 중립이라 **arm64 컨테이너에 그대로 깔린다**
(3.6MB). ZM-M3 이후 게스트용 x86_64 산출물은 전부 크로스 컴파일이거나 amd64
패키지에서 조달했는데 **이것은 세 번째 종류다 — 아키텍처가 없는 데이터.**
`ncurses-base`의 terminfo, `libc-bin`의 로케일과 같은 종류다.

`OVMF_CODE_4M.fd`를 쓴다(`.secboot`는 Secure Boot용이고 우리 커널은 서명이
없다). **`OVMF_VARS_4M.fd`는 매번 복사한다** — 읽기 전용으로 물리면 펌웨어가
NVRAM 변수를 못 써서 부트 항목을 못 만든다.

## ISO 하나가 두 펌웨어를 태운다

El Torito 부트 카탈로그에 항목 둘을 담는다(BIOS는 `-b`, UEFI는 `--efi-boot`).
`boot/check.sh`는 SeaBIOS로, `machine/check.sh`는 OVMF로 **같은 바이트를**
부팅한다.

**`--protective-msdos-label`은 대시 둘이다** — 하나면 `xorriso`가
`Unrecognized option`으로 죽는다.

**파일 둘이 서로 다른 경로다.** `limine-uefi-cd.bin`은 El Torito가 가리키는
FAT 이미지(광학 매체)이고, 트리의 `EFI/BOOT/BOOTX64.EFI`는 이 ISO를 USB에
dd로 쓴 뒤 펌웨어가 **파일로** 찾을 때 쓰인다. 실기에 꽂는 것은 후자다.
**둘 다 BF-M0이 커밋한 limine 배포 tarball에 처음부터 들어 있었다.**

## 남은 것

- **RM-M2 — 설정 저장소를 찾는다.** `init/src/main.zig:65`가 `/dev/vda`를
  하드코딩한다. 노트북에는 virtio가 없어서 `/dev/nvme0n1`이나 `/dev/sda`다.
  **부팅은 지금도 된다**(못 찾으면 기본값으로 간다) — 안 되는 것은 설정이
  부팅 사이에 남는 것이다. **RM에서 코드를 건드리는 유일한 milestone이다.**
- **RM-M3 — 게이트가 못 보는 것들.** `ACPI_EC`(노트북 DSDT에 거의 항상 있고
  없으면 AML이 실패해 배터리·뚜껑·밝기 키가 통째로 안 붙는다) · `ACPI_AC` ·
  `ACPI_BATTERY` · `ACPI_PROCESSOR` · `THERMAL`. 켜고 QEMU에서 회귀가 없음만
  확인한다. 그리고 실기용 USB 이미지 만드는 법과 **Secure Boot를 꺼야 한다**를
  문서에 적는다.

**`SUSPEND`(S3)는 RM 밖이다.** `ACPI_BUTTON`이 켜져 있어 lid 이벤트는 이미
오지만 뚜껑을 닫아 절전으로 가는 것은 별 서브프로젝트다.

**How to apply:** 실머신 방향의 `.config`를 고칠 때는 (1) 켜려는 항목의 층을
먼저 확인하고(메뉴인지 코어인지 드라이버인지), (2) 라운드마다 되접어 다음 층의
줄을 드러내고, (3) **게이트가 그것을 밟는 길이 있는지 먼저 묻고**, (4) 없으면
"켜 봤다"와 "된다"가 안 갈린다는 것을 명시적으로 적고, (5) 부트로더 단계가
의심되면 `serial: yes`의 출력을 **escape를 걷어내고** 읽는다.

관련: [[project_target_hardware]] · [[project_kernel_config]] ·
[[project_device_discovery]] · [[project_gate_latency]] ·
[[project_gate_chain_composition]] · [[project_carryover_cleanup]]
