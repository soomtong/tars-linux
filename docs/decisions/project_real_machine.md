---
name: project_real_machine
description: "일반 x86_64 노트북에서 뜨는 커널을 만드는 층(RM, 2026-09-09 착수 · **2026-09-10 완료**, RM-M0~M3) — 진짜 벽은 CONFIG_EFI가 아니라 CONFIG_RELOCATABLE이었고 그것을 찾은 것은 limine.conf의 `serial: yes` 한 줄이다; simpledrm이 EFI GOP 프레임버퍼 위에 /dev/dri/card0을 그대로 내놓으므로 DRM_I915도 AMDGPU도 필요 없다; ovmf 패키지는 Architecture: all이라 arm64 컨테이너에 그대로 깔린다; .config를 켜는 데 층이 셋이라 되접기를 라운드마다 해야 다음 층 줄이 나타난다; i8042=off로 PS/2를 아예 끄지 않으면 USB 키보드 판정이 아무것도 안 본다; SYSFB_SIMPLEFB를 켠 것만으로 boot/check.sh의 암묵적 전제(card0이 없다)가 깨져 -vga none을 명시해야 했다; 게이트는 커널을 15회가 아니라 1회 빌드한다(GL-M0·M1 이후); 설정 디스크는 /dev/vda라는 이름이 아니라 ext2 라벨 tars-로 찾는다(후보 열넷을 훑고 superblock을 읽어 거른다 — 마운트로 시험하지 않는다); 노트북 ACPI 다섯을 켜니 그것이 끌고 온 CPU_IDLE이 RM-M1부터 잠복하던 경합(USB 키보드가 열거되기 전에 init이 훑으면 전원 버튼을 키보드로 고른다)을 드러냈고, 처방은 커널을 되돌리는 것이 아니라 init이 한정된 시간 동안 다시 보게 하는 것이었다 — 이것은 게이트 flake가 아니라 실기 버그다(허브를 거치면 열거가 1.7초)"
metadata:
  node_type: memory
  type: project
---

`docs/decisions/project_target_hardware.md`가 2026-08-31에 "서브프로젝트 하나"로
지목한 것을 2026-09-09에 집었다. **일의 이름은 "`ACPI_EC`를 되켠다"가 아니라
"실머신용 `.config`를 만든다"**이고, 저장소 어휘로 **Real Machine (RM)**이다.
design은 `docs/superpowers/specs/2026-09-09-tars-real-machine-design.md`.

**사용자가 고른 것은 넷이다** — `.config`를 하나로 유지하고(둘로 안 나눔),
게이트에 **열번째 체인을 하나 더하고**(기존 아홉을 안 옮김), RM-M2에서
**후보 목록을 `init`에 박고**, **라벨이 `tars-`로 시작하는 첫 디스크를**
고른다. 그리고 대상은 특정 기계가 아니라 **"일반 x86_64 노트북"**이다.
나머지 결정 열하나는 Claude가 정했고 근거가 design에 적혀 있다.

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
| `THERMAL` · `ACPI_PROCESSOR` | **본다**(RM-M3에서 뒤집혔다) | 거버너 등록 줄과 `_PPC` notify |
| `ACPI_EC` · `ACPI_AC` · `ACPI_BATTERY` · 실 GPU | **못 본다** | QEMU에 EC도 어댑터도 배터리도 GPU도 없다 |

**못 보는 것이 열에서 셋으로 줄었고, 그 셋 중 둘은 안 켜기로 정했다.**
**그리고 RM-M3에서 한 번 더 줄었다** — 재 보니 `THERMAL`과 `ACPI_PROCESSOR`도
줄을 남긴다(아래). **착수 전에 쓴 표는 두 번 다 실측보다 비관적이었다.**

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

## 설정 디스크는 이름이 아니라 ext2 라벨로 찾는다 (RM-M2)

`init/src/main.zig`가 `/dev/vda`를 하드코딩하고 있었다. 그 이름은 virtio-blk에만
있어서 **노트북에서는 저장소를 영영 못 찾았다** — 부팅은 됐고 설정만 매번
사라졌다. `init/src/storage.zig`가 후보 열넷을 훑어 **ext2 라벨이 `tars-`로
시작하는** 첫 디스크를 고른다.

```
/dev/vda vdb vdc vdd · nvme0n1…nvme3n1 · sda sdb sdc sdd · mmcblk0 mmcblk1
```

**HD-M2의 "이름이 아니라 성질로"의 블록 장치 판이다.** 블록 장치에는
capability가 없지만 **ext2 라벨이 그 자리를 대신한다** — 그리고 게이트 디스크
넷이 이미 `tars-config`·`tars-input`·`tars-power`·`tars-hangul`이었다(CP-M0이
`-L`을 "나중에 알아보기 위함"이라고 적으며 넣었고 셋이 베꼈다). **그래서
접두사 규칙이 기존 체인을 한 글자도 안 건드린다.**

**마운트로 시험하지 않는다.** superblock(오프셋 1024)의 매직 `0xEF53`과 라벨
(`s_volume_name`, superblock 안 120)을 **읽어서** 거르고 mount는 고른 하나에만
한 번 한다. 근거 셋: 실패 줄이 열셋 안 찍힌다 · `mountFs`의 로그 계약이 안
바뀐다(다섯 체인이 마커로 갖고 있다) · mount(2)는 fs를 ext3/4로 잘못 잡으면
저널 재생 같은 **쓰기**를 할 수 있다.

**파티션은 안 본다**(디스크 전체만). 부수 효과가 안전 쪽이다 — 노트북 내장
디스크는 예외 없이 GPT라 디스크 전체를 읽으면 매직이 안 맞고, **그래서 남의
root 파티션을 `/config`로 잡을 길이 아예 없다.**

**오프셋은 손으로 심은 버퍼로 원리적으로 못 본다** — 검사가 구현과 같은 수를
두 번 적은 것이 되기 때문이다. 그래서 `mkfs.ext2`가 구운 바이트를 먼저 봤다
(`1080`이 `53 ef`, `1144`가 `tars-config`). **분업이 셋이다: 호스트 검사가
규칙을, 스파이크가 오프셋을, 체인이 셋이 함께 도는가를 본다.**

## `set -euo pipefail`이 실패 진단을 조용히 삼킨다

`machine/check.sh`의 `fail()`이 문맥 줄을 붙이는 루프에서 **첫 패턴이 없으면
그 자리에서 함수가 끝났다.** 안 맞는 `grep`은 종료 코드 1이고 `pipefail`이
그것을 파이프라인 전체의 코드로 올리며 `set -e`가 함수를 죽인다.

```bash
denoise | grep -a "$pattern" | head -3 | sed 's/^/  /' || true   # ← || true가 없었다
```

**하필 첫 패턴이 "없는 것"인 경우가 가장 흔하다** — 그것이 실패의 이유라서
목록의 앞에 적힌다. RM-M0에서는 첫 패턴이 `PANIC`이었고 마침 있어서 결함이
드러날 조건이 없었다. **RM-M2의 음성 확인이 잡았다.**

**"들린다"(serial) · "읽힌다"(escape) · "찍힌다"(pipefail)가 각각 다르다.**

## 노트북 ACPI 다섯을 켜니 잠복 경합이 드러났다 (RM-M3)

`ACPI_EC` · `ACPI_AC` · `ACPI_BATTERY` · `ACPI_PROCESSOR` · `THERMAL`을 켰다.
층이 얕아 되접기가 **한 라운드**에 고정점에 닿았고(`CONFIG_ACPI=y`가 이미
상위 메뉴를 열어 뒀다) **열둘이 딸려 왔다.** 대가는 빌드 **+0.256초**,
bzImage **+61,440바이트(+1.7%)** — 결정 3이 `DRM_I915`를 안 켠 것과 조건이
같은데 답이 다른 이유가 **크기**다.

**착수 전 표가 또 절반 틀렸다.** `THERMAL`을 "못 본다"로 적었고
`ACPI_PROCESSOR`는 아예 안 적었는데, 재 보니 둘 다 줄을 남긴다 —
`thermal_sys: Registered thermal governor 'step_wise'`와
`cpuidle: using governor ladder`. 그리고 **직접 증거가 따로 있다**:
`Warning: Processor Platform Limit event detected`는 QEMU의 `_PPC` notify를
`ACPI_PROCESSOR`가 **실제로 받았다**는 뜻이다(판정으로는 안 쓴다 — notify
시점이 QEMU에 달려 flaky하다). **못 보는 것이 다섯에서 셋으로 줄었다.**

### 그런데 `CPU_IDLE`이 딸려 오면서 게이트가 깨졌다

```
FAIL: init did not pick the USB keyboard
  tars-init: keyboard device /dev/input/event0 (Power Button)
  [    0.927854] input: QEMU QEMU USB Keyboard as ...input1
```

**같은 커널로 바로 앞 회차가 통과했다 — 경합이다.** 두 커널을 같은 세션에서
다섯 번씩 돌려 쟀다: RM-M2는 USB 열거가 0.882~0.898초(실패 0), RM-M3은
0.880~0.928초(실패 1). **RM-M3이 경합을 만든 것이 아니라 지터를 넓혀
드러냈다.** RM-M1부터 잠복해 있었다.

**처방이 "커널을 되돌린다"가 아니다.** `init`이 첫 훑기에 없다고 포기하는
대신 25ms 간격으로 **최대 3초까지 다시 본다**(`findKeyboardWaiting`).
찾으면 즉시 돌아오고 상한이 끝나면 예전대로 `event0`으로 떨어지므로
**HD 결정 6("못 찾아도 부팅을 막지 않는다")을 안 어긴다** — 무한히 기다리는
것과 한정해서 기다리는 것은 다른 일이다.

**이것이 게이트 flake가 아니라 실기 버그인 것이 결정적이다.** 허브를 둘
끼워 열거를 **1.693초**로 늦추니 `init`이 **650ms를 기다려** 찾았다.
고침이 없었으면 그 부팅은 전원 버튼을 키보드로 골랐다 — 허브를 거친 키보드는
실기에서 예외가 아니다.

### 초록이 아무것도 증명하지 않는 자리가 있었다

기다림을 넣고 체인을 여섯 번 돌리니 6/6 통과인데 **`keyboard showed up
after` 줄이 한 번도 안 나왔다.** `init` 바이너리가 커지며 훑는 시점이 뒤로
밀려 **우연히 경합을 피한 것**이다. `resolveKeyboard`를 sysfs 마운트 직후로
끌어올려도 마찬가지였다. **열거를 늦추고 나서야 고침이 도는 것을 봤다.**

**SH-M2가 적은 "초록은 '내가 본 것이 맞다'이지 '볼 것을 다 봤다'가 아니다"의
한 걸음 더 나쁜 판이다** — 초록이 '내가 본 것'조차 아니었다.

### 기다림을 넣을 때의 실수 둘

호스트 검사가 각각 잡는다. **첫째가 특히 위험하다** — 묻기 전에 자면 **모든
부팅이 느려지고 증상이 "부팅이 좀 느리다"뿐이라 아무도 못 잡는다.**

| 실수 | 잡는 검사 |
|---|---|
| 자고 나서 묻기 | `SleptBeforeLooking`(있는 키보드가 26ms 걸렸다) |
| 기다림이 없음 | `GaveUpTooEarly`(0ms 만에 포기했다) |

**`std.time.Timer`가 Zig 0.16에 없다** — SH-M1이 `std.posix`의 `pipe`에서 겪은
것과 같은 종류이고 처방도 같다: `clock_gettime`을 직접 부른다.

## 실기에 꽂는 법은 README에 있다

`README.md`의 **"실기 노트북에 꽂아 보기"** 절이다. 요점 넷.

1. `out/tars.iso`를 **디스크 전체**에 `dd`한다(하이브리드라 변환이 없다).
2. **Secure Boot를 꺼야 한다.** 커널에 서명이 없고, 안 끄면 증상이 "부팅
   항목이 아예 안 보인다"라 원인에서 아주 멀다.
3. 설정을 남기려면 **`tars-`로 시작하는 ext2 라벨**을 가진 디스크가 있어야
   한다.
4. **안 되는 것을 표로 적었다** — 밝기·외부 모니터·절전·네트워크·터치패드.

**그리고 "이 저장소의 어떤 게이트도 실기 부팅을 검증하지 않는다"를 적었다.**
꽂아 봤는데 안 되면 그것은 새로 발견된 사실이지 회귀가 아니다.

## 남은 것

**RM은 끝났다.** 계획한 milestone 넷을 전부 했다. 남긴 것은 아래 둘이고,
**둘 다 처음부터 비목표로 적어 둔 것**이지 중간에 포기한 것이 아니다.

- **실기에서 실제로 부팅해 보기.** 특정 기계가 없다는 것이 착수 때의 전제였고
  (사용자가 "일반 x86_64 노트북"을 골랐다), 그래서 판정이 전부 QEMU다.
  `README.md`에 꽂는 법을 적었으니 **다음은 꽂아 보는 사람의 몫이다.**
- **`/config`를 파티션 테이블 위에 두기.** RM-M2 결정 12가 명시적으로 안 한
  것이다 — 지금 디스크 전체가 파티션 없는 ext2다.

**`SUSPEND`(S3)는 RM 밖이다.** `ACPI_BUTTON`이 켜져 있어 lid 이벤트는 이미
오지만 뚜껑을 닫아 절전으로 가는 것은 별 서브프로젝트다.

**How to apply:** 실머신 방향의 `.config`를 고칠 때는 (1) 켜려는 항목의 층을
먼저 확인하고(메뉴인지 코어인지 드라이버인지), (2) 라운드마다 되접어 다음 층의
줄을 드러내고, (3) **게이트가 그것을 밟는 길이 있는지 먼저 묻고**, (4) 없으면
"켜 봤다"와 "된다"가 안 갈린다는 것을 명시적으로 적고, (5) 부트로더 단계가
의심되면 `serial: yes`의 출력을 **escape를 걷어내고** 읽는다. 그리고
(6) **설정을 켠 뒤 게이트가 초록이어도 "무엇이 딸려 왔는지"를 센다** —
RM-M3에서 `ACPI_PROCESSOR`가 끌고 온 `CPU_IDLE`이 다른 체인의 타이밍을
흔들었고, 우리가 켠 줄만 보고 있었으면 원인을 못 찾았다.

관련: [[project_target_hardware]] · [[project_kernel_config]] ·
[[project_device_discovery]] · [[project_gate_latency]] ·
[[project_gate_chain_composition]] · [[project_carryover_cleanup]]
