# TARS USB Wireless — Design

접두사: UW

Status: 설계(2026-09-28). M0부터 시작한다.

관련 문서: `2026-09-28-tars-wireless-design.md`(WL. 이 사이클은 그 비목표 5의 USB 절반을
목표로 옮긴다) · `docs/decisions/project_wireless.md` · `docs/guides/lessons.md`의
"이월 숙제"(USB 동글의 비용을 2026-09-28에 잰 기록).

## 한 줄 요약

노트북 내장 무선과 같은 칩 계열의 USB 동글 열하나를 커널에 켜고, 그 동글들이 새로
요청하는 firmware 셋을 initrd 꼬리에 더한다. 우리 코드는 0줄이다 — `tars-wifi`와
dhcpcd hook `10-tars-wifi`가 드라이버를 가리지 않는다.

## 왜 지금인가

2026-09-28에 사용자가 후보(IPv6 · 패키지 매니저 · USB 무선 동글 층 A) 중 이것을 골랐다.
WL이 켠 것은 PCIe 칩뿐이라, 내장 무선이 없거나 지원하지 않는 칩인 기계는 꽂아 쓸 수단이
없다. 비용은 같은 날 아침에 쟀다 — 커널 +98KB, 새 firmware 셋 127KB, 부작용 없음.

## 착수 전에 아는 것

- 늦게 생긴 인터페이스는 이미 길이 있다. dhcpcd가 새 인터페이스를 보면 hook의
  `PREINIT`이 wpa_supplicant에 `interface_add`를 보낸다(WL 결정 4 · 실측 7). 부팅 뒤에
  꽂은 동글이 이 길을 탄다. wifi 체인 검사 8이 이 길을 hwsim으로 본다.
- QEMU에는 USB 무선 장치가 없다. 게이트는 실칩의 probe를 못 본다(WL 위험 4와 같다).
- 켜지 않은 채 남아 있는 USB 심볼은 `kernel/.config`에 `# ... is not set`으로 보인다:
  `RTW88_8822BU` · `8822CU` · `8723DU` · `8821CU` · `8821AU` · `8812AU` · `8814AU` ·
  `RTW89_8851BU` · `8852BU` · `MT7921U` · `MT7925U`.

## 결정

### 결정 1 — 커널은 USB 동글 열하나를 켠다(층 A)

rtw88 USB 일곱, rtw89 USB 둘, MediaTek USB 둘. 고른 기준은 "WL이 켠 칩
계열과 같은 드라이버 코어를 쓰는 것"이다 — 코어가 이미 들어 있어서 증분이 작다.
`8821AU` · `8812AU` · `8814AU`는 새 칩 코어(`RTW88_8821A` · `8812A` · `8814A`)를 따라
켠다. `olddefconfig`가 무엇을 더 켜는지는 M0이 센다.

### 결정 2 — firmware는 빌드 산출물이 말한 새 이름만 더한다

WL 실측 3의 방법 그대로다. 빌드한 뒤 `kernel/build/modules.builtin.modinfo`의
`firmware=` 줄을 WL 때와 비교해 새로 생긴 이름만 `kernel/guest_firmware.sh`에 더한다.
예상은 `rtw88/rtw8812a_fw.bin` · `rtw8814a_fw.bin` · `rtw8821a_fw.bin`이다. 나머지 동글은
PCIe판과 같은 파일을 요청한다. linux-firmware 릴리스는 WL이 고정한 것(20260916)을 그대로
쓴다.

### 결정 3 — 게이트는 세 층이고 새 체인도 새 부팅도 없다

1. 정적. wifi 체인 검사 1의 심볼 목록에 USB 열하나를 더한다. firmware 셋은 tools
   체인 검사 1b가 `guest_firmware.sh`를 source하므로 목록에 더하는 순간 자동으로 센다.
2. 커널 산출물. wifi 체인 검사 1에서 `modules.builtin.modinfo`에 계열마다 대표 동글
   하나의 `alias=usb:v…p…` 줄이 있는지 본다. 이 줄이 "그 VID:PID가 꽂히면 이 드라이버가
   잡는다"는 표가 커널 안에 있다는 증거다. 대표 VID:PID는 M0이 드라이버 소스의 id 표에서
   고른다.
3. 부팅. wifi 체인의 기존 부팅 C에서 `/sys/bus/usb/drivers/` 아래에 드라이버 열하나가
   등록돼 있는지 본다. 1·2는 "켜기로 했다"까지이고, 3은 "커널이 USB 코어에 드라이버를
   실제로 올렸다"이다. 등록 이름(`KBUILD_MODNAME`)은 M0이 잰다.

반사실은 `CONFIG_RTW88_8812AU`를 끄는 것 하나다. 예측은 검사 1이 잡는 것이다.

## 위험

### 위험 1 — 부팅 층이 등록만 보고 probe는 못 본다

`/sys/bus/usb/drivers/<이름>`은 장치가 없어도 드라이버가 등록되면 생긴다. 실제 동글에서
firmware를 올리고 인터페이스를 만드는지는 게이트 밖이다(비목표 2).

### 위험 2 — `olddefconfig`가 예상 밖의 심볼을 끌어온다

측정 때는 부작용이 없었다. M0이 `.config` diff를 세어 다시 확인한다. 켜진 것이 입력 쪽
(`HID_*` · `NEW_LEDS`)에 닿으면 멈추고 다시 정한다 — `RTL8XXXU`를 뺀 이유와 같다.

## 비목표

1. 층 B(MT7601U · MT76x0U · MT76x2U · rt2800usb · ath9k_htc)와 `RTL8XXXU`.
   `RTL8XXXU`는 `NEW_LEDS`를 거쳐 `HID_APPLE`을 끌고 와서 `keyboard=apple`과 부딪칠 수 있다.
2. 실칩 판정. 실제 동글을 꽂아 보는 것은 동글이 생기면 연다.
3. WL의 나머지 비목표(BE201 · 보드별 변형 firmware · WPA-Enterprise)는 그대로 남는다.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- UW-M0 — 실측, 코드 0줄. 등록 이름 열하나, `olddefconfig`가 따라 켜는 심볼, 새
  `firmware=` 줄, 계열마다 대표 alias.
- UW-M1 — 커널 config, firmware 목록, 체인 검사 셋.
- UW-M2 — 반사실, 루트 게이트(17체인, 약 60분), 문서, 닫기.
