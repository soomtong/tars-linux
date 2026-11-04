---
name: project_macbook_hardware
description: "MacBookAir4,1 · MacBookPro10,1/11,x의 내장 장치(MB-M0, 2026-11-05). 트랙패드는 HID 코어가 무조건 버려서 bcm5974 없이는 아예 안 움직인다 · ACPI_SBS를 넓게 · HID_APPLE은 끈 채 · 판정은 커널 장치 표와 등록 줄까지"
metadata:
  type: project
---

design은 `docs/specs/2026-11-04-tars-macbook-hardware-design.md`. 사용자 요청(2026-11-04) "macbookair 11 2011 · macbookpro 15 2013 설치"를
MB · HS · DB 셋으로 나눈 첫째다. 사용자가 잠들며 남은 결정을 전부 맡겼다.

## 배운 것 — 다시 조사하지 말 것

1. `drivers/hid/hid-quirks.c`의 `hid_mouse_ignore_list`가 WELLSPRING 트랙패드 전부에 `HID_QUIRK_IGNORE_MOUSE`를 붙인다. 그래서
   `MOUSE_BCM5974`가 없으면 맥 트랙패드는 "평범한 마우스"로도 안 잡힌다. ID는 0249(Air4,1) · 0262(Pro10,1) · 0290(Pro11,x).
2. 내장 키보드는 `hid-generic`이 받고 vendor 0x05ac라 KK의 `auto`가 apple로 연다. 윗줄은 F1~F12 그대로, Fn 조합은 없다(`HID_APPLE`을
   끈 대가, KK 비목표 2).
3. 소리는 AU-M2가 켠 Cirrus로 충분하다. Air4,1은 이름 있는 fixup이 없어 vendor 줄 `CS420X_APPLE`이 받는다 — 안 울리면 design 위험 1.
4. 별칭 줄은 `bcm5974.alias=usb:v05ACp0249d*dc*…`처럼 꼬리가 붙는다. 판정은 부분 일치다(`grep -x`로 써서 거짓 빨강을 한 번 봤다).
5. 커널을 켜면 다른 체인의 음성 검사가 그 심볼을 막고 있을 수 있다 — pointer 체인이 PD 결정 9로 bcm5974를 금지하고 있었다. 켜기 전에
   `rg -n '<SYMBOL>' */check.sh`.
6. 되접기를 빠뜨린 커밋이 있으면 다음 되접기 diff에 섞여 나온다(HP의 ext4 줄 여섯). 정규화는 따로 커밋한다([[project_kernel_config]]).

How to apply: 맥 실기에서 트랙패드 · 소리 · 배터리가 안 되면 위 순서로 본다. 무선(BCM4360 등)은 비목표 1.

관련: [[project_real_machine]] · [[project_keyboard_kind]] · [[project_pointer_devices]] · [[project_hidpi_scale]] · [[project_dual_boot]]
