# RM-M1 Implementation Plan — 노트북 장치가 붙는다

> **실행 방식은 `CLAUDE.md`를 따른다.** 설명 먼저 → 파일 편집 → 명령 실행은
> Claude Code가 → 결과를 상세히 설명. 승인 뒤의 `git commit`도 Claude Code가
> 만든다. 체크박스는 진행 추적용이다.
>
> **이 milestone도 편집을 Claude Code가 한다** — RM-M0의 예외와 같다.

**Goal:** 열번째 체인이 **PS/2를 아예 끈 채로** 돌아, USB 키보드로 친 글자가
화면에 나타나고 NVMe 디스크가 커널에 보인다.

**Architecture:** RM-M0이 세운 체인에 장치를 얹는다. 커널 쪽은 `.config`
라운드 셋(design 실측 5의 층: 메뉴 → 코어 → 드라이버)이고, 체인 쪽은 QEMU
인자 넷과 판정 넷이다. **코드는 한 줄도 안 고친다** — HD-M2의 capability
탐색이 이미 USB 키보드를 고른다(design 실측 4).

**Tech Stack:** `kernel/.config` · `machine/check.sh` · 컨테이너 안의 게이트

---

## 착수 전에 스파이크로 확인한 것 — **다시 조사하지 말 것**

전문은 design의 **"착수 전에 실측한 것"** 절에 있다. 이 plan이 기대는 넷.

**1. 넷이 한 번에 다 붙었다.** `_OSC ... MSI` · `nvme nvme0: pci function` ·
`xhci_hcd ... xHCI Host Controller` · `hid-generic ... USB HID v1.11 Keyboard`.
그리고 `tars-init: keyboard device /dev/input/event1 (QEMU QEMU USB Keyboard)`.

**2. `i8042=off`가 없으면 이 milestone이 아무것도 안 본다.** PS/2가 남아 있으면
`init`이 그것을 먼저 골라서 `usb-kbd`가 있으나 없으나 게이트가 초록이다
(design 결정 7). **IS-M1 실측 4와 같은 종류다.**

**3. `.config`를 켜는 데 층이 셋이다**(design 실측 5). 라운드마다 되접어야
다음 층의 줄이 나타난다.

```
라운드 1  PCI_MSI · HID_SUPPORT · USB_SUPPORT · SCSI · BLK_DEV_NVME · ATA
라운드 2  USB · BLK_DEV_SD · SATA_AHCI · ATA_PIIX
라운드 3  USB_XHCI_HCD · USB_EHCI_HCD · USB_OHCI_HCD · USB_UHCI_HCD · USB_STORAGE
```

**`USB_HID`는 라운드 2에서 저절로 켜진다** — 우리가 명시하지 않는다.

**4. bzImage가 3,060,736 → 3,580,928바이트가 된다**(+17.0%, M0 대비). 착수 전
기준(RM 이전)에서 보면 +22.1%다.

## 착수 전에 확인할 것

**5. QEMU의 `sendkey`가 USB 키보드로 간다.** 모니터의 `sendkey`는 QKbd 입력
핸들러로 가고 `usb-kbd`가 그것을 등록한다. `i8042=off`이므로 경쟁자가 없다.
**Task 3에서 실제로 글자가 나오는지로 확인한다** — 문서로 믿지 않는다.

---

## Task 1 — 커널에 노트북 장치를 켠다 (라운드 셋)

**넣을 것:** `kernel/.config`. 라운드마다 켜고 → 빌드 → 되접기.

**왜 이 목록인가.**

| 항목 | 노트북에서 무엇 |
|---|---|
| `PCI_MSI` | 요즘 장치는 MSI/MSI-X로 인터럽트를 받는다. 없으면 legacy INTx로 떨어지거나 아예 안 붙는다 |
| `USB_SUPPORT`→`USB`→HCD 넷 | 외장 키보드와 **USB 부팅 매체**. HCD 넷을 다 켜는 이유는 design 결정 8 |
| `HID_SUPPORT`→`HID`→`USB_HID` | HID 부트 프로토콜을 evdev로 바꾸는 층 |
| `USB_STORAGE` | USB 스틱의 파티션을 블록 장치로 |
| `SCSI`→`BLK_DEV_SD` | `USB_STORAGE`와 AHCI가 둘 다 SCSI 디스크로 나온다 |
| `BLK_DEV_NVME` | 요즘 노트북의 내장 저장장치 |
| `ATA`→`SATA_AHCI`·`ATA_PIIX` | 그 앞 세대의 내장 저장장치 |

**`HID_*` 벤더 quirk 열하나와 `I2C_HID`가 저절로 켜지는 것을 누르지 않는다**
(design 결정 8). 특정 기계가 없으므로 "이 키보드에서만 안 된다"를 없애는 값이
크다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  ./kernel/build.sh >/dev/null 2>&1
  cp kernel/build/.config kernel/.config
  ./kernel/build.sh >/dev/null 2>&1
  diff kernel/.config kernel/build/.config && echo "fixpoint OK"'
```

**판정:** 라운드 셋 뒤 `fixpoint OK`. 그리고 `CONFIG_USB_XHCI_PCI=y`와
`CONFIG_USB_HID=y`가 `.config`에 있다 — **둘 다 우리가 손으로 안 적은 것**이라
층이 제대로 접혔다는 증거다.

- [ ] Task 1

## Task 2 — 커널 빌드 비용을 잰다

**결정 1의 대가를 숫자로 받는다.** design 결정 1(`.config`는 하나)이 "커널이
커지고 게이트가 그것을 15~18배로 치른다"를 대가로 받아들인 것이므로, 그 값이
얼마인지 모르는 채로 넘어가지 않는다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'rm -rf kernel/build && time ./kernel/build.sh' 2>&1 | tail -5
```

**RM 착수 전 값과 비교한다.** `project_kernel_config`가 ACPI에 대해 잰 값이
50.355 → 52.944초(+2.589초)였고 "15배는 39초라 정책을 바꿀 이유가 못 된다"고
판단했다. **같은 자를 쓴다.**

**판정이 아니라 기록이다.** 어떤 값이 나와도 이 Task는 실패하지 않는다 —
결정 1은 사용자가 골랐고, 이 숫자는 그 결정을 나중에 다시 볼 사람의 것이다.

- [ ] Task 2

## Task 3 — 체인이 PS/2 없이 USB 키보드로 친다

**넣을 것:** `machine/check.sh`의 QEMU 줄과 판정.

QEMU 인자에 더할 것 넷.

```
-machine q35,i8042=off          ← PS/2를 아예 끈다
-device qemu-xhci,id=xhci
-device usb-kbd,bus=xhci.0
-drive file=$DISK,if=none,id=cfg,format=raw -device nvme,drive=cfg,serial=tarscfg
-monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait
```

`$DISK`는 `mktemp`로 만든 8MB `mkfs.ext2` 이미지다. **RM-M1은 그것을 마운트하지
않는다** — `/dev/vda`가 하드코딩돼 있어서 `init`이 못 찾는다. NVMe가 **커널에
보이는 것**까지가 이 milestone이고, 읽는 것은 RM-M2다.

**판정 넷을 더한다.**

| 보는 것 | 없으면 무엇이 틀렸나 |
|---|---|
| `_OSC: OS supports [` … `MSI` | `PCI_MSI`가 안 켜졌다 |
| `xHCI Host Controller` | `USB_XHCI_HCD`가 없다 |
| `keyboard device` + `USB Keyboard` | **HID가 evdev까지 안 왔다.** 이 판정이 이 milestone의 심장이다 |
| `nvme nvme0: pci function` | `BLK_DEV_NVME`가 없다 |

**그리고 실제로 친다.** `hangul/check.sh`의 모니터 연결과 `sendkey`를 따른다.
글자 몇을 치고 `terminal: screen>`에 그 글자가 나오는지 본다.

**왜 "장치가 보인다"만으로는 부족한가.** `input: QEMU QEMU USB Keyboard`는
커널이 장치를 만들었다는 뜻일 뿐이고, TARS가 그것을 열어 읽는 것은 다른
일이다. `terminal: opened /dev/input/event1`이 그 사이를 잇지만 **실제 키가
화면에 닿는 것**까지 봐야 경로 전체가 확인된다 — CM·HI·SH의 체인이 전부
그렇게 판정한다.

- [ ] Task 3

## Task 4 — 게이트

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } 2> /tmp/gate.time
```

**판정:** `TARS check PASS`. 시간은 RM-M0 값과 비교해 적고, 차이가 설명되는지
본다(커널 빌드 증가분 × 회차 + 체인의 타이핑 지연 × 3).

**백그라운드로 돌린다** — 20분이 넘고 Bash 도구의 상한이 10분이다.

- [ ] Task 4

## Task 5 — 음성 확인

**`i8042=off`를 빼고** 체인 하나만 돌린다.

**기대하는 실패:** `tars-init: keyboard device /dev/input/event0 (AT Translated
Set 2 keyboard)` — PS/2를 골라서 판정이 exit 1이다. **이것이 design 결정 7을
정면으로 본다** — 그 플래그가 없으면 `usb-kbd`가 있으나 없으나 초록이라는
사실을 실행으로 증명한다.

되돌린 뒤 다시 그 체인만 돌려 초록을 확인한다.

- [ ] Task 5

## Task 6 — 커밋과 문서

**커밋 둘.** 커널 `.config`(Task 1)와 체인(Task 3)을 나눈다 — 앞의 것은
"제품이 무엇을 할 수 있게 됐나"이고 뒤의 것은 "그것을 보는 자리"다.

`check.sh`의 `CHAINS`에서 `RM-M0`을 `RM-M1`로 고친다 — 그 배열이
서브프로젝트의 실제 상태를 가장 정확히 말하는 자리다(`CLAUDE.md`).

design의 `Status:`와 실측 절을 갱신한다.

- [ ] Task 6

---

## 위험 요약

| | 위험 | 처방 |
|---|---|---|
| 1 | `sendkey`가 USB 키보드로 안 간다 | Task 3에서 실제로 글자가 나오는지로 확인한다. 안 되면 `-device usb-kbd`의 버스 지정을 본다 |
| 2 | 커널이 커져 게이트가 눈에 띄게 느려진다 | Task 2가 숫자를 만든다. 결정 1은 사용자가 골랐으므로 되돌리는 것은 이 milestone의 일이 아니다 |
| 3 | `i8042=off`로 부팅이 아예 안 된다 | 스파이크가 이미 통과했다(design 실측 4) |
| 4 | HID quirk 드라이버들이 빌드를 크게 늘린다 | Task 2가 함께 잰다. 누르는 것은 결정 8을 뒤집는 일이라 사용자에게 묻는다 |
