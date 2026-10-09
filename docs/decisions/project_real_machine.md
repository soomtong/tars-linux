---
name: project_real_machine
description: "일반 x86_64 노트북에서 뜨는 커널(RM-M0~M3, 2026-09-09·10) — UEFI · simpledrm · USB 키보드 · NVMe. 함정 — 진짜 벽은 EFI가 아니라 RELOCATABLE이고 그것을 찾은 것은 limine.conf의 serial: yes다 · simpledrm이 있으면 GPU 드라이버가 필요 없다 · .config는 층이 셋이라 라운드마다 되접는다 · i8042=off 없이는 USB 키보드 판정이 아무것도 안 본다 · 설정 디스크는 이름이 아니라 ext2 라벨 tars-로 찾는다 · ACPI를 켜니 CPU_IDLE이 딸려 와 잠복 경합(키보드 열거 전 훑기)을 드러냈다"
metadata:
  node_type: memory
  type: project
---

[[project_target_hardware]]가 2026-08-31에 "서브프로젝트 하나"로 지목한 것을
2026-09-09에 집었다. 일의 이름은 "`ACPI_EC`를 되켠다"가 아니라 "실머신용
`.config`를 만든다"다. design은 `docs/specs/2026-09-09-tars-real-machine-design.md`,
RM-M0~M3이 2026-09-10에 끝났다. milestone별 경과와 게이트 시간은 2026-10-10에
지웠다(커밋 이력에 있다). 여기에는 결정과 다시 밟지 말 함정만 남긴다.

그 뒤에 얹힌 층 — 내장 디스크 설치와 설정 파티션([[project_disk_install]] ·
[[project_disk_carryover]]), 유선 · 무선 드라이버([[project_wired_nic]] ·
[[project_wireless]]), 터치패드([[project_pointer_devices]]), 배터리
([[project_battery_status]]). 실기에 꽂는 법은 `docs/guides/running-tars.md`의
"실기 노트북에 꽂아 보기" 절이다 — Secure Boot를 끄고(커널에 서명이 없고 안 끄면
증상이 "부팅 항목이 아예 안 보인다"다), ISO를 디스크 전체에 `dd`한다.

## 사용자가 정한 것 — 다시 논의하지 말 것

- `.config`는 하나다(게이트용과 실기용으로 안 나눈다).
- 게이트에 열번째 체인 `machine/check.sh`를 더하고 기존 체인은 안 옮긴다.
- 설정 디스크 후보 목록을 `init`에 박고, 라벨이 `tars-`로 시작하는 첫 디스크를 고른다.
- 대상은 특정 기계가 아니라 "일반 x86_64 노트북"이다. 그래서 판정은 전부 QEMU이고
  실기 부팅은 어떤 게이트도 검증하지 않는다 — 꽂아 봤는데 안 되면 새로 발견된
  사실이지 회귀가 아니다.

## 게이트가 못 보는 것은 셋뿐이다

"게이트가 이 방향을 검증할 수 없다"는 `ACPI_EC` 하나를 보고 쓴 문장이었다. `ovmf`
패키지 하나로 나머지 대부분에 길이 났다 — `EFI` · `RELOCATABLE`은 OVMF + limine의
`BOOTX64.EFI`로, `DRM_SIMPLEDRM`은 GOP 프레임버퍼가 그대로 `card0`이 되어서,
`PCI_MSI`는 `-machine q35`의 `_OSC` 협상으로, `USB_SUPPORT` · `USB_HID`는 `qemu-xhci` +
`usb-kbd` + `i8042=off`로, NVMe · AHCI는 `-device nvme`와 q35의 `ich9-ahci`로,
`THERMAL` · `ACPI_PROCESSOR`는 거버너 등록 줄로 본다. 못 보는 것은 `ACPI_EC` ·
`ACPI_AC` · 실 GPU이고 그중 둘은 안 켜기로 정했다. `ACPI_BATTERY`는 드라이버는 못
보고 sysfs 경로는 본다 — 커널에 내장한 test_power가 같은 `power_supply_sysfs.c`로
글자를 낸다([[project_battery_status]]). 착수 전에 쓴 "못 본다" 표는 두 번 다 실측보다
비관적이었다.

`ovmf`는 `Architecture: all`이라 arm64 컨테이너에 그대로 깔린다 — 게스트용 x86_64
산출물의 세 번째 종류(크로스 컴파일 · amd64 패키지 · 아키텍처가 없는 데이터)다.
`OVMF_CODE_4M.fd`를 쓰고(`.secboot`는 서명 없는 우리 커널에 안 맞는다)
`OVMF_VARS_4M.fd`는 매번 복사한다 — 읽기 전용으로 물리면 펌웨어가 NVRAM 변수를 못
써서 부트 항목을 못 만든다.

## 진짜 벽은 `EFI`가 아니라 `RELOCATABLE`이었다 — 부트로더의 말이 안 들리는 것이 병

`CONFIG_EFI` · `SYSFB_SIMPLEFB` · `DRM_SIMPLEDRM`을 켜고 UEFI로 부팅했는데 시리얼이
OVMF의 `BdsDxe: starting Boot0001`에서 멈췄다. limine의 메뉴와 에러는 GOP 콘솔로만
가고 체인은 `-display none`이라 아무것도 안 보인다. `boot/limine.conf`에 `serial: yes`
한 줄을 넣자 답이 나왔다.

```
PANIC: linux: Non-relocatable kernel could not be loaded at required address 0x1000000
```

BIOS에서는 그 주소가 비어 있어 `PHYSICAL_START=0x1000000`짜리 비재배치 커널이
그대로 실렸는데 UEFI에서는 펌웨어가 그 자리를 쓴다. `CONFIG_RELOCATABLE=y`가
처방이고 딸려 오는 `RANDOMIZE_BASE`(KASLR)는 누르지 않았다(커널이 스스로 쓰는
방어를 벗기는 편집이고 비용을 재 본 적이 없다).

"들린다"와 "읽힌다"가 또 다르다. limine은 글자마다 커서 이동 escape를 끼워
넣어서(`P` `ESC[01;02H` `A` …) `grep "PANIC"`이 아무것도 못 찾는다. 처방은 실패
경로에서만 escape를 걷어내는 `machine/check.sh`의 `denoise()`다. 그리고 "찍힌다"가
또 다르다 — `fail()`이 문맥 줄을 붙이는 루프에서 첫 패턴이 없으면 안 맞는 `grep`의
종료 코드 1을 `pipefail`이 올리고 `set -e`가 함수를 죽여 진단이 조용히 사라졌다. 첫
패턴이 "없는 것"인 경우가 가장 흔하다(그것이 실패의 이유라 목록 앞에 적힌다). `|| true`가
처방이다.

## simpledrm 하나로 GPU 드라이버가 필요 없어진다

TARS는 `/dev/dri/card0`에 KMS ioctl을 직접 쏜다. simpledrm은 모드가 하나뿐인 KMS
드라이버이고 `SYSFB_SIMPLEFB`가 `screen_info`에서 만든 `simple-framebuffer` 플랫폼
장치에 붙는다 — 펌웨어가 잡아 둔 모드를 그대로 다시 세우므로 실기에서는 패널의
네이티브 해상도다. 그래서 `DRM_I915` · `DRM_AMDGPU`를 안 켠다. 잃는 것은 모드 변경 ·
가속 · 백라이트 · 외부 모니터이고 넷 다 지금 안 쓴다. 켜면 게이트가 단 한 번도
probe하지 못하는 코드가 커널에서 가장 큰 드라이버 둘만큼 는다.

그런데 이것이 다른 체인의 암묵적 전제를 깼다. `boot/check.sh`가 검증하는 감독 루프의
포기 경로(`MAX_FAST_RESTARTS = 3`)는 `card0`이 없어야 밟히는데, 그 전제는 "virtio-gpu를
안 물렸다"에 얹힌 암묵적인 것이었다. simpledrm을 켜자 limine이 넘긴 VGA
프레임버퍼만으로 `card0`이 생겨 터미널이 뜨고 체인이 죽었다. 커널을 안 되돌리고
`-vga none` 한 줄로 전제를 암묵에서 명시로 옮겼다. "기존 체인을 안 건드린다"가 깨진
이유가 "새 체인이 흔들어서"가 아니라 "제품의 설정이 바뀌어서"다 — 다른 종류의 위험이다.

## `.config`를 켜는 데 층이 셋이라 되접기를 라운드마다 한다

`CONFIG_USB_SUPPORT=y`를 켜도 `CONFIG_USB`는 안 켜진다. `USB_SUPPORT`는 메뉴일
뿐이고 `USB`를 켜야 `USB_XHCI_HCD` · `USB_STORAGE` 줄이 `.config`에 나타난다.
`# CONFIG_X is not set` 줄이 없는 항목은 `sd`로 켤 수가 없다.

```
USB_SUPPORT (메뉴)  →  USB (코어)  →  USB_XHCI_HCD·USB_STORAGE (드라이버)
ATA (메뉴)          →  SATA_AHCI·ATA_PIIX
SCSI (메뉴)         →  BLK_DEV_SD
```

손으로 안 적었는데 켜진 것(`USB_HID` · `USB_XHCI_PCI` · `SATA_HOST` · `I2C_HID`)은
명시하지 않는다 — 적으면 "이 줄이 이 기능을 켠다"가 틀린 기록이 된다. 특정 기계가
없으므로 벤더 quirk과 호스트 컨트롤러 넷(xHCI · EHCI · UHCI · OHCI)은 넓게 켠다 —
게이트가 못 보는 자리에서는 넓게 켠다가 이 서브프로젝트의 기울기다.

설정을 켠 뒤 게이트가 초록이어도 "무엇이 딸려 왔는지"를 센다. RM-M3의
`ACPI_PROCESSOR`가 끌고 온 `CPU_IDLE`이 다른 체인의 타이밍을 흔들었고(아래), 우리가
켠 줄만 보고 있었으면 원인을 못 찾았다.

## `i8042=off`가 없으면 USB 키보드 판정이 아무것도 안 본다

`init`이 키보드를 capability로 고르므로([[project_device_discovery]]) PS/2가 남아 있으면
그쪽을 먼저 잡고, `usb-kbd`가 있으나 없으나 게이트가 초록이다. 같은 것을 두 층이
지킬 때 위층을 확인하려면 아래층을 먼저 꺼야 한다. 그리고 PS/2를 끈 채로 코드를 한
글자도 안 고쳤다 — 키보드를 이름이 아니라 성질로 찾게 만들어 둔 것이 3주 뒤에 값을
냈다.

## 설정 디스크는 이름이 아니라 ext2 라벨로 찾는다

`init`이 `/dev/vda`를 하드코딩하고 있었다. 그 이름은 virtio-blk에만 있어서 노트북에서는
부팅은 되고 설정만 매번 사라졌다. `init/src/storage.zig`가 후보 목록(virtio · NVMe ·
SATA · eMMC, DI부터 각각의 p1 · p2까지)을 훑어 ext2 라벨이 `tars-`로 시작하는 첫
디스크를 고른다 — 블록 장치에는 capability가 없지만 라벨이 그 자리를 대신한다. 게이트
디스크 넷이 이미 `tars-config` · `tars-input` · `tars-power` · `tars-hangul`이라 접두사
규칙이 기존 체인을 한 글자도 안 건드렸다.

마운트로 시험하지 않는다. superblock(오프셋 1024)의 매직 `0xEF53`과 라벨
(`s_volume_name`)을 읽어 거르고 mount는 고른 하나에만 한 번 한다 — 실패 줄이 열셋
안 찍히고, `mountFs`의 로그 계약(여러 체인이 마커로 grep한다)이 안 바뀌며, mount(2)는 fs를
ext3/4로 잘못 잡으면 저널 재생 같은 쓰기를 할 수 있다. 남의 root 파티션은 매직이
맞아도 라벨이 `tars-`가 아니라 `/config`로 잡힐 길이 없다. 오프셋은 손으로 심은
버퍼로는 원리적으로 못 본다(검사가 구현과 같은 수를 두 번 적는 것이 된다) — `mkfs.ext2`가
구운 바이트를 먼저 봤다(`1080`이 `53 ef`, `1144`가 `tars-config`). 분업이 셋이다 — 호스트
검사가 규칙을, 스파이크가 오프셋을, 체인이 셋이 함께 도는가를 본다.

## 노트북 ACPI를 켜니 잠복 경합이 드러났다 — 처방은 되돌리기가 아니라 한정된 기다림

`ACPI_EC` · `ACPI_AC` · `ACPI_BATTERY` · `ACPI_PROCESSOR` · `THERMAL`을 켜니 `CPU_IDLE`이
딸려 왔고 게이트가 간헐로 깨졌다.

```
FAIL: init did not pick the USB keyboard
  tars-init: keyboard device /dev/input/event0 (Power Button)
  [    0.927854] input: QEMU QEMU USB Keyboard as ...input1
```

두 커널을 같은 세션에서 다섯 번씩 재니 USB 열거가 0.882~0.898초 대 0.880~0.928초 —
RM-M3이 경합을 만든 것이 아니라 지터를 넓혀 드러냈다. RM-M1부터 잠복해 있었다.
처방은 커널을 되돌리는 것이 아니라 `init`이 첫 훑기에 없다고 포기하는 대신 25ms
간격으로 최대 3초까지 다시 보는 것이다(`devices.findKeyboardWaiting`). 찾으면 즉시
돌아오고 상한이 끝나면 예전대로 떨어지므로 "못 찾아도 부팅을 막지 않는다"를 안
어긴다 — 무한히 기다리는 것과 한정해서 기다리는 것은 다른 일이다.

이것이 게이트 flake가 아니라 실기 버그인 것이 결정적이다. 허브를 둘 끼워 열거를
1.693초로 늦추니 `init`이 650ms를 기다려 찾았다 — 고침이 없었으면 전원 버튼을
키보드로 골랐고, 허브를 거친 키보드는 실기에서 예외가 아니다. 그리고 초록이
아무것도 증명하지 않는 자리가 있었다 — 기다림을 넣고 여섯 번 돌려 6/6인데
`keyboard showed up after` 줄이 한 번도 안 나왔다. 바이너리가 커지며 훑는 시점이
뒤로 밀려 우연히 경합을 피한 것이고, 열거를 늦추고 나서야 고침이 도는 것을 봤다.
초록이 "내가 본 것"조차 아니었다.

기다림을 넣을 때의 실수 둘을 호스트 검사가 각각 잡는다 — 자고 나서 묻기
(`SleptBeforeLooking`, 모든 부팅이 느려지고 증상이 "좀 느리다"뿐이라 아무도 못
잡는다) · 기다림이 없음(`GaveUpTooEarly`). 같은 모양을 뒤에 `storage.zig`의 파티션
기다림이 썼다([[project_disk_carryover]]).

## ISO 하나가 두 펌웨어를 태운다

El Torito 부트 카탈로그에 항목 둘을 담는다(BIOS는 `-b`, UEFI는 `--efi-boot`).
`boot/check.sh`는 SeaBIOS로, `machine/check.sh`는 OVMF로 같은 바이트를 부팅한다.
`--protective-msdos-label`은 대시 둘이다 — 하나면 `xorriso`가 `Unrecognized
option`으로 죽는다. `limine-uefi-cd.bin`은 El Torito가 가리키는 FAT 이미지(광학
매체)이고 트리의 `EFI/BOOT/BOOTX64.EFI`는 ISO를 USB에 `dd`한 뒤 펌웨어가 파일로
찾는 것이다 — 실기에 꽂는 것은 후자다.

## 그 밖에

- 게이트는 커널을 회차마다가 아니라 1회 빌드한다([[project_gate_latency]]). 그래서
  `.config`를 하나로 유지하는 대가가 체인 수의 배수가 아니라 1배다. 문서에 적힌
  배수는 게이트 시간과 같은 종류로 낡는다.
- `SUSPEND`(S3)는 RM 밖이다. `ACPI_BUTTON`이 켜져 있어 lid 이벤트는 오지만 뚜껑을
  닫아 절전으로 가는 것은 별 서브프로젝트다.

How to apply: 실머신 방향의 `.config`를 고칠 때는 (1) 켜려는 항목의 층을 먼저
확인하고(메뉴 · 코어 · 드라이버), (2) 라운드마다 되접어 다음 층의 줄을 드러내고,
(3) 게이트가 그것을 밟는 길이 있는지 먼저 묻고, (4) 없으면 "켜 봤다"와 "된다"가 안
갈린다는 것을 명시적으로 적고, (5) 부트로더 단계가 의심되면 `serial: yes`의 출력을
escape를 걷어내고 읽고, (6) 게이트가 초록이어도 무엇이 딸려 왔는지를 센다.

관련: [[project_target_hardware]] · [[project_kernel_config]] ·
[[project_device_discovery]] · [[project_gate_latency]] ·
[[project_gate_chain_composition]] · [[project_disk_install]] · [[project_disk_carryover]]
