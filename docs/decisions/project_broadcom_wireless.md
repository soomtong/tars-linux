---
name: project_broadcom_wireless
description: "MacBookAir4,1 내장 BCM43224를 brcmsmac으로(BW-M0, 2026-11-05). 칩은 PCI → bcma → 802.11 코어의 두 단 · Pro의 BCM4331은 firmware 재배포 불가, BCM4360은 열린 드라이버 없음 · 맥 BT는 이미 켜진 btusb Broadcom"
metadata:
  type: project
---

design은 `docs/specs/2026-11-05-tars-broadcom-wireless-design.md`. MB 비목표 1의 한 갈래를 사용자 요청으로 열었다.

## 다시 조사하지 말 것

1. 맥 세 기종의 내장 무선: Air4,1 BCM43224(`brcmsmac`, firmware 둘이 linux-firmware에) · Pro10,1 BCM4331(`b43`, firmware는 `b43-fwcutter`로
   독점 드라이버에서 — 재배포 불가) · Pro11,x BCM4360(AC-PHY `BROKEN`, 독점 `wl`은 모듈이라 TARS에 못 들어간다).
2. 판정은 두 단의 별칭을 함께 본다 — `bcma`(PCI id)와 `brcmsmac`(bcma 코어 id · rev). 한쪽만 있으면 칩이 안 잡힌다.
3. 맥 내장 BT는 USB Broadcom이라 BT-M0의 `BT_HCIBTUSB_BCM`이 받는다. `.hcd` 보정 펌웨어 없이 돈다.

관련: [[project_macbook_hardware]] · [[project_wireless]] · [[project_usb_dongles_b]] · [[project_bluetooth]]

실기(2026-11-05, MacBook Air 11" 2011): `sudo tars-config wifi <SSID>` · `set net=dhcp ntp=dhcp` · `reload`로 5GHz 망에 붙었다(DHCP 주소,
`curl http://example.com` 200). design 위험 1의 붙는가는 풀렸고 절전은 남았다. 게스트에 `ping`이 없어 확인은 `curl`로 했다.
