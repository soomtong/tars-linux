# TARS MacBook Hardware — Design

접두사: MB

Status: 진행 중

사용자의 요청(2026-11-04)에서 시작한다.

> macbookair 11 2011 모델 설치 → 기본 모델; 내장 키보드, 내장 트랙패드, 외장 마우스, 외장 키보드 장착, 스피커, 마우스 장치 내장됨
> macbookpro 15 2013 모델 설치 → macbookair 11 모델에 더해 레티나 디스플레이가 추가됨.
>
> 인스톨러 개선: 대상 디스크 고르기 beside macOS partition (or volume), dual booting 가능해야 해.
>
> 여기까지 완료 후 다음 패치 버전 찍기: tag, release & distribute!

요청 하나를 서브프로젝트 셋으로 나눴다. 이 문서는 첫째(장치), Retina는 HS(`2026-11-04-tars-hidpi-scale-design.md`), 설치기는
DB(`2026-11-04-tars-dual-boot-design.md`)다. 그 뒤 0.1.4를 낸다 — 2026-11-01의 "0.1.4는 커널 7.4 뒤" 결정은 이 요청이 대신한다.

관련 문서: RM design(`2026-09-09-tars-real-machine-design.md` — "일반 x86_64 노트북"의 커널, 판정은 QEMU), KK design(결정과 비목표 2 —
`HID_APPLE`을 끈 채 Apple 키보드를 vendor로 안다), AU design(Cirrus HDA 코덱을 켰다), BS design(배터리 칸).

## 한 줄 요약

두 맥북의 내장 장치 가운데 지금 커널이 못 받는 것은 트랙패드(bcm5974) 하나이고, 배터리 길 하나(SBS)를 넓게 더한다. `.config` 두 줄,
코드 0줄. 게이트는 커널의 장치 표와 등록 줄까지 보고, 실제로 붙는 것은 실기에서 사용자가 본다.

## 기종

| 요청 | 모델 식별자 | 트랙패드(USB 05ac) | 소리 코덱 | 화면 | 저장장치 |
|---|---|---|---|---|---|
| MacBook Air 11" 2011 | MacBookAir4,1 | WELLSPRING6A `0249`~`024b` | Cirrus CS4206 | 1366×768 | SATA SSD |
| MacBook Pro 15" Retina, 2012~early 2013 | MacBookPro10,1 | WELLSPRING7 `0262`~`0264` | Cirrus CS4206 | 2880×1800 | SATA SSD |
| MacBook Pro 15" Retina, late 2013 | MacBookPro11,2 · 11,3 | WELLSPRING8 `0290`~`0292` | Cirrus CS4208 | 2880×1800 | PCIe AHCI SSD |

"15 2013"은 두 세대에 걸쳐 있어 둘 다 대상으로 둔다(결정 1). 키보드와 트랙패드는 같은 USB 장치의 다른 인터페이스다.

## 착수 전에 확인한 것 (2026-11-04, 커널 6.18.60 소스와 `kernel/.config`)

### 확인 1 — 트랙패드는 지금 아예 안 움직인다

`drivers/hid/hid-quirks.c`의 `hid_mouse_ignore_list`가 WELLSPRING 계열 전부를 담고, `hid_lookup_quirk`가 그 장치에
`HID_QUIRK_IGNORE_MOUSE`를 붙인다. HID 코어는 그 장치의 마우스 인터페이스를 버린다 — `bcm5974`가 받으라고 비켜 주는 것이다. 그런데
`.config`는 `# CONFIG_MOUSE_BCM5974 is not set`이었다. 그래서 TARS로 맥북을 띄우면 트랙패드가 "평범한 마우스"로도 안 잡힌다. 이것이
이 서브프로젝트의 본론이다.

`bcm5974`는 멀티터치 프로토콜 B(`input_mt_init_slots`)와 `BTN_TOOL_*`를 내므로 terminal의 `pointer.classify`가 `touchpad`로 읽고 PD-M3의
`touchpad.zig`가 그대로 받는다. 탭 · 두 손가락 스크롤은 우리 소프트웨어가 한다(하드웨어 탭은 없다).

### 확인 2 — 내장 키보드는 지금도 된다

키보드 인터페이스는 `hid-generic`이 받는다(`HID_APPLE`이 꺼져 있다). vendor `0x05ac`라 KK의 `keyboard=auto`가 `apple`로 연다 — Cmd ·
Option이 제자리다. 윗줄은 하드웨어가 F1~F12 usage를 그대로 보내므로 F 키로 온다. 잃는 것은 Fn 조합(Fn+↑ = PageUp 등 — `hid-apple`의
소프트웨어 변환)이고 KK 비목표 2가 이미 적은 자리다.

### 확인 3 — 소리는 이미 켜진 설정으로 받는다

`sound/hda/codecs/cirrus/cs420x.c`의 fixup 표 — MacBookPro10,1은 `0x106b:0x2800` → `CS420X_MBP101`, MacBookPro11,2는 `0x106b:0x5e00` →
`CS4208_MBP11`, MacBookAir4,1은 이름이 따로 없어 vendor 줄(`SND_PCI_QUIRK_VENDOR(0x106b, "Apple", CS420X_APPLE)`)이 받는다.
`SND_HDA_CODEC_CS420X` · `SND_HDA_CODEC_CS8409`는 AU-M2가 켰다.

### 확인 4 — 나머지

- 화면: simpledrm이 Apple GOP 프레임버퍼를 받는다(RM 결정 3). Retina 크기는 HS의 일이다.
- 저장장치: 셋 다 AHCI(`SATA_AHCI=y`) — `/dev/sda`.
- USB: MacBookAir4,1은 xHCI가 없고 EHCI뿐이다. `USB_EHCI_HCD=y`.
- 배터리: 일반 ACPI 배터리(`PNP0C0A`, `ACPI_BATTERY=y`)와 Smart Battery System(`ACPI0002`, `ACPI_SBS`) 중 어느 쪽으로 오는지 기종마다
  기록이 갈린다. 실기 없이 못 가르므로 둘 다 켠다(결정 2).
- 외장 USB 마우스 · 키보드: 지금도 된다(PD · KH).

## 결정

1. 대상은 위 표의 넷(4,1 · 10,1 · 11,2 · 11,3)이다. 드라이버가 같아 비용이 같다.
2. `CONFIG_MOUSE_BCM5974=y` · `CONFIG_ACPI_SBS=y` 두 줄. `ACPI_SBS`는 `ACPI_EC`(켜져 있다)에 기대고 `POWER_SUPPLY`(켜져 있다)를 select한다
   — 되접기 diff가 두 줄 말고는 비었다. `battery.zig`는 `type`이 `Battery`인 첫 이름을 고르므로 어느 길로 와도 칸이 뜬다.
3. `HID_APPLE`은 끈 채다(KK 비목표 2, `audio` · `wifi` 체인의 음성 검사).
4. 판정은 `machine/check.sh`(RM-M1 체인)에 더한다. 그 체인이 "실기 노트북"의 체인이다.
   - 부팅 전: `modules.builtin.modinfo`에 `bcm5974.alias=usb:v05ACp0249d` · `…0262d` · `…0290d`와 `sbs.alias=acpi*:ACPI0002:`.
   - 부팅 뒤: `usbcore: registered new interface driver bcm5974`.

## 게이트가 못 보는 것

트랙패드가 실제로 붙는지, 패드의 좌표 범위에 `touchpad.zig`의 상수(탭 180ms · 2% · 배율)가 맞는지, 소리가 스피커로 나오는지, 배터리 칸이
어느 길로 뜨는지. 넷 다 실기에서 사용자가 본다(HANDOFF).

## 위험

1. MacBookAir4,1의 스피커가 vendor 줄의 일반 fixup(`CS420X_APPLE`)으로 안 울릴 수 있다. 그러면 `dmesg | grep -i cs420`과
   `/proc/asound/card0/codec#0`의 subsystem id를 보고 fixup을 cmdline(`snd_hda_intel.model=mba42`)으로 고른다.
2. bcm5974 패드의 좌표 범위가 QEMU 대역(`tp-replay`)과 달라 이동 배율이 어색할 수 있다. 고칠 자리는 `touchpad.zig`의 배율과
   PS의 `touchpad_accel`이다.
3. Fn 조합이 없어 PageUp · Home이 없다(확인 2). 거슬리면 KK 비목표 2를 다시 연다.

## 비목표

1. 무선. MacBookAir4,1은 BCM43224(`brcmsmac`), 10,1은 BCM4331(`b43`, firmware를 사용자가 잘라 내야 한다), 11,x는 BCM4360(열린 드라이버가
   없다). 요청에 없고, 셋째는 길이 없다.
2. 화면 밝기 · 키보드 백라이트(`apple_bl` · `applesmc`), 절전, GPU 전환(`apple-gmux`). simpledrm은 펌웨어가 켜 둔 GPU를 그대로 쓴다.
3. 내장 BT의 Broadcom firmware(BT 위험 6).

## Milestone

- MB-M0 — `.config` 두 줄, `machine/check.sh`의 정적 검사와 등록 줄 판정.
