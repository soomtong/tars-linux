---
name: project_usb_wireless
description: "WL이 켠 칩 계열의 USB 동글 열하나를 켠 서브프로젝트(UW-M0~M2, 2026-09-28). 우리 코드는 0줄이고 firmware는 rtw88 셋만 늘었다(74→77). QEMU에 USB 무선이 없어서 게이트는 심볼 · modinfo alias · 부팅 로그의 usbcore 등록 줄까지만 본다"
metadata:
  node_type: memory
  type: project
---

# USB 무선 동글 (UW)

design은 `docs/specs/2026-09-28-tars-usb-wireless-design.md`(결정 3 · 위험 2 ·
실측 1~6). 2026-09-28에 사용자가 후보(IPv6 · 패키지 매니저 · USB 동글 층 A) 중 이것을
골랐다. 비용은 같은 날 아침에 lessons의 이월 숙제로 재 두었다.

무엇이 섰나.

- `kernel/.config` — rtw88 USB 일곱 · rtw89 USB 둘 · `MT7921U` · `MT7925U`. `olddefconfig`가
  버스 층 넷과 rtw88 칩 코어 넷을 따라 켰고 입력 쪽(`HID_*` · `NEW_LEDS`)은 안 건드렸다.
  bzImage +98,304바이트.
- `kernel/guest_firmware.sh` — `rtw88/rtw8812a` · `8814a` · `8821a`(합 127KB). 나머지 동글은
  PCIe판과 같은 파일을 요청한다.
- `wifi/check.sh` — 검사 1에 심볼 열하나와 계열마다 대표 alias 넷, 검사 11이 부팅 C에서
  usbcore 등록 줄 열하나를 센다.

[[project_wireless]]의 `tars-wifi`와 hook `10-tars-wifi`가 드라이버를 안 가려서 게스트 코드는
0줄이다. 부팅 뒤에 꽂은 동글도 hook의 `interface_add` 길을 탄다.

배운 것.

- 드라이버 등록은 장치와 무관하다. `usb_register_driver`가 `usbcore: registered new
  interface driver <이름>`을 찍고, USB 컨트롤러가 없는 부팅(`-usb` 없음)에서도 나온다.
  `/sys/bus/usb/drivers/`를 보는 탐침이 필요 없었다(실측 5).
- 등록 이름은 `modules.builtin.modinfo`의 모듈 이름과 같다. Realtek은 `rtw88_` · `rtw89_`
  접두사가 붙고 MediaTek은 안 붙는다.
- modinfo의 alias는 `<모듈>.alias=usb:v<VID>p<PID>d*…` 모양이고 16진은 대문자다. 파일이
  NUL로 나뉘어 있어서 `tr '\0' '\n'`을 거쳐 grep한다.
- `services.d`의 탐침은 끝나고 나가면 `init`이 다시 띄운다 — 탐침 출력은 여러 번 찍힌다.

게이트가 못 보는 것: 실제 동글의 probe · firmware 로딩 · `wlan` 생성. 층 B와 `RTL8XXXU`는
lessons의 이월 숙제에 남았다.
