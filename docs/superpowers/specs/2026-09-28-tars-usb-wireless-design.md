# TARS USB Wireless — Design

접두사: UW

Status: M0 끝(2026-09-28, 실측 1~4). 결정은 그대로다. 다음은 M1.

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

## 실측 (M0, 2026-09-28)

하네스는 `/tmp/uw/`에 있었다. 기준선은 WL 커밋 `58a25b5`의 빌드다(`build.sh`가 "skipping
make"를 말한 산출물). 열하나를 켠 빌드는 증분이라 20.6초 걸렸다.

### 실측 1 — `olddefconfig`는 여덟을 따라 켜고 아무것도 안 끈다

해소된 `build/.config`에 열하나가 전부 `=y`로 남았다. 따라 켜진 것은 버스 층 넷(`MT76_USB` ·
`MT792x_USB` · `RTW88_USB` · `RTW89_USB`)과 칩 코어 넷(`RTW88_88XXA` · `RTW88_8821A` ·
`RTW88_8812A` · `RTW88_8814A`)뿐이다. `RTW88_88XXA`는 나머지 칩 코어 셋이 함께 쓰는 층이다.
`HID_*` · `NEW_LEDS` · `LEDS_*`는 없다. 위험 2는 현실이 되지 않았다. diff에 `RTW88_8822BE`가 `<`와 `>`로 한 번씩
나오는 것은 줄 위치가 밀린 것이고 값은 그대로다. bzImage는 7,336,960 → 7,435,264바이트
(+98,304).

### 실측 2 — 새 firmware는 예상한 셋이고 전부 실제 파일이다

`firmware=` 줄이 107 → 110. 새 셋은 `rtw88/rtw8812a_fw.bin`(27,030바이트) ·
`rtw88/rtw8814a_fw.bin`(68,320) · `rtw88/rtw8821a_fw.bin`(31,898), 합 127,248바이트다.
셋 다 linux-firmware-20260916 tarball 안에 링크가 아닌 파일로 있다 — `WHENCE`를 볼 필요가
없고, 목록의 두 경로가 같다.

### 실측 3 — 등록 이름은 modinfo의 모듈 이름과 같다

부팅 한 번(`-usb` · 탐침 `services.d/probe`)에서 `/sys/bus/usb/drivers/`에 열하나가 전부
있었다: `rtw88_8822bu` · `rtw88_8822cu` · `rtw88_8723du` · `rtw88_8821cu` · `rtw88_8821au` ·
`rtw88_8812au` · `rtw88_8814au` · `rtw89_8851bu` · `rtw89_8852bu` · `mt7921u` · `mt7925u`.
목록에는 WN의 USB 유선(`r8152` · `asix` · `cdc_ether` …)과 RM의 `usbhid` · `usb-storage` ·
`hub`도 있다. 탐침은 두 번 찍혔다 — 끝나고 나간 서비스를 `init`이 다시 띄운 것이다. M1의
판정은 "줄이 한 번 이상 있다"로 센다.

### 실측 4 — alias는 열하나에 157줄이고, 대표는 넷이다

모듈마다 alias 줄: `rtw88_8822bu` 35 · `rtw88_8812au` 34 · `rtw88_8821au` 26 ·
`rtw88_8821cu` 15 · `rtw88_8814au` 14 · `rtw89_8852bu` 14 · `rtw88_8822cu` 6 · `mt7921u` 5 ·
`rtw89_8851bu` 4 · `rtw88_8723du` 2 · `mt7925u` 2. 계열마다 하나를 대표로 고른다.

| 계열 | modinfo 줄의 앞부분 | 무엇 |
|---|---|---|
| rtw88 | `rtw88_8822bu.alias=usb:v2357p012Dd*` | TP-Link Archer T3U v1(소스 주석) |
| rtw89 | `rtw89_8852bu.alias=usb:v0BDApB832d*` | id 표 첫 줄(주석 없음) |
| mt7921u | `mt7921u.alias=usb:v0E8Dp7961d*` | 칩 제조사 기본 ID |
| mt7925u | `mt7925u.alias=usb:v0E8Dp7925d*` | 칩 제조사 기본 ID |

VID:PID는 대문자 16진이다. 결정 1~3은 그대로 간다.
