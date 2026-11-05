# TARS Broadcom Wireless — Design

접두사: BW

Status: 닫힘(2026-11-05) — BW-M0 `BRCMSMAC=y`(+ `BCMA` · `BRCMUTIL` · `CORDIC`), firmware 둘, wifi 체인의 심볼 · 두 단 별칭.

사용자의 요청(2026-11-05): "내장 wifi와 bluetooth는 안되나?"에 기종별로 답한 뒤 "켜주세요 그리고 0.1.4 버전을 다시 릴리즈/배포 해줘".

관련 문서: MB design(비목표 1이 이 자리를 남겼다), WL design(PCIe 무선과 wpa_supplicant 감독), UB design(드라이버 + firmware를 켜고 커널
표로 보는 모양).

## 한 줄 요약

MacBookAir4,1의 내장 BCM43224를 `brcmsmac`으로 받는다. `.config` 한 줄과 firmware 두 파일, 코드 0줄. 같은 시기 MacBook Pro의 둘은
열 수 없다(비목표).

## 확인 (2026-11-05, 커널 6.18.60 · linux-firmware-20260916)

1. `BRCMSMAC`은 `MAC80211`(켜짐) · `BCMA_POSSIBLE`(켜짐)에 기대고 `BCMA` · `BRCMUTIL` · `CORDIC`을 select한다. 되접기 diff는 그 셋과 bcma의
   PCI 호스트(`BCMA_HOST_PCI` · `BCMA_DRIVER_PCI`)와 "not set" 줄뿐이다 — 입력 쪽(`HID_*` · `LEDS`)은 그대로다.
2. 칩은 두 단으로 잡힌다. PCI `14e4:4353` → `bcma`(host_pci), bcma의 802.11 코어 `id 0812 rev 17` → `brcmsmac`.
3. `brcmsmac`이 찾는 firmware는 `brcm/bcm43xx-0.fw`(96,224 B) · `brcm/bcm43xx_hdr-0.fw`(180 B)이고 tarball에 있다.
4. Bluetooth는 이미 켜져 있다 — 세 기종의 내장 BT는 USB Broadcom(BCM20702 계열)이고 `BT_HCIBTUSB_BCM=y` · `BT_BCM=y`. 보정 펌웨어
   (`BCM*.hcd`)는 linux-firmware에 없어 없이 돈다(BT 비목표 4).

## 결정

1. `CONFIG_BRCMSMAC=y`. 따라오는 것은 되접기 그대로 둔다.
2. firmware 두 파일을 `kernel/guest_firmware.sh`에. `tools` 체인 검사 1b가 initrd에 들었는지 센다.
3. 판정은 `wifi/check.sh` 검사 1 — 심볼 `BCMA` · `BRCMSMAC`, 별칭 `bcma.alias=pci:v000014E4d00004353` ·
   `brcmsmac.alias=bcma:m04BFid0812rev17cl`. QEMU에 Broadcom 칩이 없어 부팅으로는 못 본다.
4. 접속 길은 WL 그대로 — `tars-config wifi …`. 코드는 칩을 모른다.

## 비목표

1. MacBookPro10,1의 BCM4331(`b43`). firmware를 Broadcom 독점 드라이버에서 `b43-fwcutter`로 잘라 내야 하고 재배포할 수 없다. 사용자가
   잘라 `/config`에 두는 길은 나중에.
2. MacBookPro11,x의 BCM4360. 커널의 AC-PHY는 `BROKEN`이고 독점 `wl`은 외부 모듈이라 `CONFIG_MODULES`가 없는 TARS에 못 들어간다.
3. bcma가 4331 · 43a0에도 붙는다(무선 드라이버 없이 버스만). 해가 없어 두었다.

## 위험

1. brcmsmac은 오래된 드라이버이고 BCM43224의 실기 동작(특히 5GHz · 절전)은 실기가 말한다. 안 붙으면 `dmesg | grep -iE 'bcma|brcm'`.
   — 2026-11-05 실기(MacBook Air 11" 2011): 5GHz SSID에 `--country KR` 없이 붙어 DHCP 주소를 받고 `curl`이 바깥까지 간다. 절전은 아직 모른다.
2. 실기에서 firmware를 못 찾으면 이름을 `guest_firmware.sh`와 대조한다.

## Milestone

- BW-M0 — 위 결정 넷. lead가 직접.
