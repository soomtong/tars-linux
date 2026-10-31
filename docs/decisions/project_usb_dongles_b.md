---
name: project_usb_dongles_b
description: "UW가 남긴 USB 무선 동글 드라이버 여섯(mt7601u · mt76x0u · mt76x2u · rt2800usb · ath9k_htc · rtl8xxxu)을 켠 서브프로젝트(UB-M0~M2, 2026-10-31). 코드 0줄, firmware 119 → 140. RTL8XXXU를 막던 LEDS_CLASS는 AU-M2가 이미 켰고 HID_APPLE은 not set인 채라 게이트가 그것을 음성 검사로 지킨다. RT2X00은 부모 메뉴라 직접 켠다"
metadata:
  node_type: memory
  type: project
---

# USB 동글 층 B (UB)

design은 `docs/specs/2026-10-31-tars-usb-dongles-b-design.md`(결정 4 · 위험 4 · 실측 1~6).
2026-10-31에 사용자가 후보(큰 kitty 이미지 · GPU 가속 · 패키지 매니저 · 네트워크) 중
네트워크를 골랐고, 같은 자리에서 IPv6를 결정으로 닫아([[feedback_ipv4_only]]) 남은 것이
이것이었다.

무엇이 섰나.

- `kernel/.config` — `MT7601U` · `MT76x0U` · `MT76x2U` · `RT2X00` + `RT2800USB`(하위 다섯,
  `UNKNOWN` 제외) · `ATH9K_HTC` · `RTL8XXXU`(`UNTESTED` 제외). 따라 켜진 것은 mt76 공통 층 ·
  rt2x00 라이브러리 · `ATH9K_HW/COMMON/BTCOEX_SUPPORT` · `CRC_CCITT`. bzImage +372,736바이트.
- `kernel/guest_firmware.sh` — 21개(MediaTek 다섯 · Ralink 하나 · ath9k_htc 둘 · rtlwifi 열셋).
  firmware cpio 119 → 140 파일.
- `wifi/check.sh` — 검사 1에 심볼 여덟 · alias 여섯 · 음성 검사 둘(`HID_APPLE` · `INPUT_LEDS`가
  `not set`), 검사 11에 등록 줄 여섯(열일곱).

배운 것 · 함정.

- `scripts/config --enable`은 `.config`에 없던 심볼을 파일 끝에 덧붙이고, 부모 메뉴(`RT2X00`)가
  `not set`이면 `olddefconfig`가 조용히 버린다. 해소된 `build/.config`에서 `=y`를 센 것이 잡았다
  (measurements 70의 대소문자 침묵과 같은 종류). 부모 메뉴를 함께 켠다.
- UW가 `RTL8XXXU`를 뺀 근거(`LEDS_CLASS`가 `HID_APPLE`을 끌고 온다)는 AU-M2(2026-10-06)가
  `LEDS_CLASS=y`를 켠 순간 사라져 있었다. `.config`에 "not set"으로 적힌 심볼은 `olddefconfig`가
  안 뒤집는다 — 커널을 올리는 날 새로 물을 수 있어 게이트의 음성 검사가 그 자리를 지킨다.
- 등록 줄 `usbcore: registered new interface driver <이름>`의 이름은 `struct usb_driver.name`이다.
  `hif_usb.c`의 `.name = "ath9k_hif_usb"`는 드라이버 안 전송 층 구조체의 것이고 등록 이름은
  `KBUILD_MODNAME`(`ath9k_htc`)이다 — design이 처음 잘못 읽었고 부팅 로그가 바로잡았다.
- `MODULE_FIRMWARE`에 있어도 요청하지 않는 이름이 있다. `rtl8723bu_bt.bin`은 `enable_bluetooth`
  비트에 대입하는 자리가 0곳이라 죽은 이름이다(이 릴리스에 파일도 없다). `mt7662u.bin` ·
  `htc_9271.fw`는 이름이 더 맞아 보여도 6.18이 안 찾는다 — 목록은 `firmware=` 줄에서 센다.
- 커밋되는 `kernel/.config`는 늘 `olddefconfig`가 해소한 모양이다(HEAD와 `build/.config`의
  diff 0줄). 작업 트리에서 켠 뒤 `cp build/.config .config`로 가져온다.

게이트가 못 보는 것: 실제 동글의 probe · firmware 올리기 · `wlan` 생성(UW와 같다). 남은 것은
`RT2800USB_UNKNOWN` · `RTL8XXXU_UNTESTED`와 다른 계열(`rtl8187` · `zd1211rw` · `carl9170` 등) —
실제 동글이 근거를 줄 때 연다(UB 비목표 2 · 5).

관련: [[project_usb_wireless]] · [[project_wireless]] · [[feedback_ipv4_only]]
