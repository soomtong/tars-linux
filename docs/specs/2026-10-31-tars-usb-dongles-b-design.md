# TARS USB Dongles B — Design

접두사: UB

Status: 설계(2026-10-31). 착수 전 확인 1~7. M0이 실측으로 채운다.

관련 문서: `2026-09-28-tars-usb-wireless-design.md`(UW. 이 사이클은 그 비목표 1을 목표로
옮긴다) · `docs/decisions/project_usb_wireless.md` · `docs/guides/carryover.md`의 "USB 무선
동글의 나머지" 항목(2026-09-28에 잰 비용) · `docs/decisions/feedback_ipv4_only.md`(네트워크
기능은 IPv4 전제).

## 한 줄 요약

UW가 남긴 USB 무선 동글 드라이버 여섯(MediaTek 셋 · Ralink · Atheros HTC · Realtek
rtl8xxxu)을 커널에 켜고, 그것들이 요청하는 firmware 27개(약 739KB)를 initrd 꼬리에
더한다. 우리 코드는 0줄이고 게이트는 UW의 세 층을 그대로 늘린다 — 단, 등록 이름 하나가
모듈 이름과 다르고(확인 5), `HID_APPLE`이 꺼진 채인지 보는 음성 검사 하나가 는다(결정 4).

## 왜 지금인가

2026-10-31에 사용자가 후보(큰 kitty 이미지 · GPU 가속 · 패키지 매니저 · 네트워크) 중
네트워크를 골랐고, 같은 자리에서 IPv6를 결정으로 닫았다(`feedback_ipv4_only`). 네트워크에
남은 것은 이것 하나다. UW의 층 A는 "노트북 내장 칩과 같은 코어"를 쓰는 비교적 새 동글이고,
층 B는 그 반대쪽 — 2.4GHz 802.11n 시대의 싸고 흔한 동글(RT5370 · MT7601U · AR9271 ·
RTL8188EU)과 USB 802.11ac 초기 칩(MT7610U · MT7612U)이다. 내장 무선이 없는 데스크톱이나
오래된 기계에 꽂혀 있을 확률이 가장 높은 쪽이 이것이다.

## 착수 전에 아는 것 (2026-10-31에 소스와 tarball에서 확인)

### 확인 1 — 다섯의 의존성은 전부 이미 켜진 것 위에 선다

`kernel/src/linux-6.18.42`의 Kconfig. 다섯 다 `depends on MAC80211 && USB`이고 둘 다 `=y`다.

| 옵션 | select | 지금 `.config` |
|---|---|---|
| `MT7601U` | 없음(독립 드라이버) | not set |
| `MT76x0U` | `MT76x0_COMMON` · `MT76x02_USB` | not set. `MT76_CORE` · `MT76_USB`는 UW가 켰다 |
| `MT76x2U` | `MT76x2_COMMON` · `MT76x02_USB` | not set |
| `RT2800USB` | `RT2800_LIB` · `RT2X00_LIB_USB` · `RT2X00_LIB_FIRMWARE` · `RT2X00_LIB_CRYPTO` | `RT2X00` 자체가 not set — 메뉴 하나가 통째로 열린다 |
| `ATH9K_HTC` | `ATH9K_HW` · `ATH9K_COMMON` · `MAC80211_LEDS` | not set. `ATH_COMMON` · `MAC80211_LEDS`는 이미 `=y` |

`RT2800USB` 아래 bool 다섯: `RT33XX` · `RT35XX`는 default y, `RT3573` · `RT53XX` · `RT55XX`는
default n, `UNKNOWN`은 default n. RT5370(`RT53XX`)이 가장 흔한 싸구려 동글이라 n인 셋도
켠다(결정 1). `RT2X00_LIB_LEDS`는 `LEDS_CLASS=y`라 따라 켜진다 — 입력 쪽이 아니다.

### 확인 2 — `RTL8XXXU`를 막던 것이 없어졌다

UW 비목표 1의 근거는 "`NEW_LEDS`가 있어야 붙고 그것이 `HID_APPLE` · `INPUT_LEDS`를 끌고
온다"였다. 지금 `.config`는 `CONFIG_NEW_LEDS=y` · `CONFIG_LEDS_CLASS=y`다 — AU-M2(`cd9c12e`,
소리 카드)가 켰다. 그런데 `# CONFIG_HID_APPLE is not set` · `# CONFIG_INPUT_LEDS is not set`은
그대로다. `HID_APPLE`은 `default !EXPERT`지만 `.config`에 이미 답이 적힌 심볼은 `olddefconfig`가
다시 묻지 않는다. 즉 `RTL8XXXU`(`depends on MAC80211 && USB && LEDS_CLASS`)는 지금 켜도
입력 쪽을 건드리지 않는다. M0이 `.config` diff로 확인한다(위험 2). 틀리면 UW처럼 뺀다.

### 확인 3 — 요청하는 firmware 이름은 소스에 전부 적혀 있고 tarball에 다 있다

이름은 `MODULE_FIRMWARE`와 `request_firmware` 호출에서, 크기는 linux-firmware-20260916
tarball에서 읽었다. 맨 위 이름 셋은 WHENCE의 `Link:`라 원본은 `mediatek/` 아래다(UW의
iwlwifi · ath11k와 같은 사정, `guest_firmware.sh` 형식의 이유).

| 드라이버 | 요청 이름 | tarball 원본 | 바이트 |
|---|---|---|---|
| mt7601u | `mt7601u.bin` | `mediatek/mt7601u.bin`(Link) | 45,412 |
| mt76x0u | `mediatek/mt7610e.bin` 먼저, 없으면 `mediatek/mt7610u.bin` | 둘 다 File | 80,680 · 80,288 |
| mt76x2u | `mt7662_rom_patch.bin` · `mt7662.bin` | `mediatek/`(둘 다 Link) | 26,350 · 81,908 |
| rt2800usb | `rt2870.bin` | File | 8,192 |
| ath9k_htc | `ath9k_htc/htc_9271-1.4.0.fw` · `ath9k_htc/htc_7010-1.4.0.fw` | File | 51,008 · 72,812 |
| rtl8xxxu | `rtlwifi/` 아래 열넷(`MODULE_FIRMWARE`) | 열셋 File | 292,054 |

층 B 다섯의 합 446,650, rtl8xxxu 292,054 — 약 739KB다. carryover의 "약 0.4MB · 약 0.3MB"와
맞는다.

- mt76x0u는 `mt7610e.bin`을 `firmware_request_nowarn`으로 먼저 찾고 없으면 `mt7610u.bin`을
  찾는다(`usb_mcu.c`). 둘 다 modinfo `firmware=`에 나오므로 둘 다 넣는다 — 결정 2의 규칙
  그대로다.
- mt76x2u가 요청하는 것은 `mt7662.bin`이지 tarball에 함께 있는 `mt7662u.bin`이 아니다.
  이름이 "더 맞아 보이는" 파일을 넣으면 안 올라가는 파일만 넣는 것이다(iwlwifi `c101`의
  교훈, `guest_firmware.sh` 머리말).
- ath9k_htc는 1.4.0 이름을 먼저 요청하고, 그것이 없으면 1.3의 맨 위 이름 `htc_9271.fw`로
  내려간다(`hif_usb.c`). 1.4.0 둘만 넣는다.
- rtl8xxxu의 열넷 중 `rtlwifi/rtl8723bu_bt.bin`은 이 릴리스에 없다(WHENCE에 `File:` 줄이
  없다, carryover와 같다). 8723BU에서 `enable_bluetooth`일 때만 요청하는 이름이고 아니면
  `rtl8723bu_nic.bin`이다(`8723b.c`). 열셋만 넣고 위험 3에 적는다. `vendor_firmware.sh`는
  없는 파일이면 죽으므로 목록에 못 적는다.

### 확인 4 — 등록 이름은 다섯이 모듈 이름이고 하나가 아니다

`usbcore: registered new interface driver <이름>`의 `<이름>`은 `struct usb_driver.name`이다.
mt7601u · mt76x0u · mt76x2u · rt2800usb · rtl8xxxu(`DRIVER_NAME "rtl8xxxu"`)는 모듈 이름과
같다(UW 실측 3). ath9k_htc만 `.name = "ath9k_hif_usb"`(`hif_usb.c`)다 — 모듈 `ath9k_htc`
안의 USB 전송 층 이름이다. 부팅 층 검사에는 이 이름을 적는다.

### 확인 5 — 대표 alias는 소스의 id 표 첫 줄과 주석에서 고른다

| 드라이버 | 첫 줄 | 주석 |
|---|---|---|
| mt7601u | `0x0b05, 0x17d3` | 없음(Asus USB-N10 Nano) |
| mt76x0u | `0x148F, 0x7610` | MT7610U(칩 제조사 기본) |
| mt76x2u | `0x0b05, 0x1833` | Asus USB-AC54 |
| rt2800usb | `0x07b8, 0x2870` | 없음(AboCom) |
| ath9k_htc | `0x0cf3, 0x9271` | Atheros(칩 제조사 기본) |
| rtl8xxxu | `0x2357, 0x0108` | TP-Link(`USB_DEVICE_AND_INTERFACE_INFO`) |

modinfo 줄의 모양은 `<모듈>.alias=usb:v<VID>p<PID>d*…`이고 16진은 대문자다(UW 실측 4).
rtl8xxxu는 인터페이스 class까지 적는 매크로라 `d*` 뒤가 다를 수 있다 — M0이 실제 줄을 보고
앞부분만 대조한다. 모듈 이름은 Makefile의 `obj-$(CONFIG_…) += <이름>.o`다: `mt7601u` ·
`mt76x0u` · `mt76x2u` · `rt2800usb` · `ath9k_htc` · `rtl8xxxu`.

### 확인 6 — carryover의 "`ATH9K_PCI`가 따라 켜진다"는 Kconfig와 맞지 않는다

`ATH9K_PCI`는 `depends on ATH9K && PCI`이고 `ATH9K_HTC`는 `ATH9K`를 select하지 않는다. 2026-09-28의
측정이 `ATH9K`까지 켰거나 다른 것을 봤을 수 있다. M0의 `.config` diff가 가린다 — `ATH9K_PCI`가
켜지면 그 이유를 적고, 안 켜지면 carryover의 그 줄을 고친다.

### 확인 7 — 게이트의 자리는 UW가 만든 셋이고 셈 문자열이 넷이다

`wifi/check.sh` 검사 1(심볼 목록 · alias 넷 · `sixteen laptop chips, eleven USB dongles`) ·
검사 11(등록 줄 열하나 · `all eleven USB dongle drivers`) · `tools/check.sh` 검사 1b(목록을
source해서 세므로 자동). 새 체인 · 새 부팅 · 설정 디스크 변경은 없다.

## 결정

### 결정 1 — 커널은 여섯을 켠다(층 B 다섯 + rtl8xxxu)

`MT7601U` · `MT76x0U` · `MT76x2U` · `RT2800USB`(하위 `RT33XX` · `RT35XX` · `RT3573` ·
`RT53XX` · `RT55XX` 전부 y, `UNKNOWN`은 n) · `ATH9K_HTC` · `RTL8XXXU`(`UNTESTED`는 n). 전부
`=y`(모듈 없는 커널). `olddefconfig`가 더 켜는 것은 M0이 센다. 입력 쪽(`HID_*` · `INPUT_LEDS`)이
바뀌면 그 드라이버를 빼고 다시 정한다(UW 위험 2와 같다).

### 결정 2 — firmware는 빌드 산출물의 `firmware=` 줄에서 센다

UW 결정 2 그대로다. 빌드 뒤 `kernel/build/modules.builtin.modinfo`의 `firmware=` 줄을 지금
(115줄)과 비교해 새 이름만 `kernel/guest_firmware.sh`에 더한다. 예상은 확인 3의 27개이고
그중 하나(`rtl8723bu_bt.bin`)는 파일이 없어 못 넣는다. 출처는 linux-firmware-20260916 그대로.
목록에는 UW처럼 계열 주석을 달고, 빠진 하나는 머리말의 "뺀 것"에 적는다.

### 결정 3 — 게이트는 세 층을 늘린다. 새 체인도 새 부팅도 없다

1. 정적. 검사 1의 심볼 목록에 여섯을 더한다. `RT2800USB_RT53XX`도 더한다 — 하위 bool이
   빠지는 것은 드라이버가 빠지는 것과 같은 실패(RT5370이 안 잡힌다)인데 심볼은 따로다.
   firmware는 1b가 자동으로 센다(목록에 26개가 늘어난다 — 이름 27 중 파일 없는 하나를 뺀 수).
2. 커널 산출물. 검사 1의 alias 목록에 확인 5의 여섯을 더한다.
3. 부팅. 검사 11의 등록 줄에 여섯을 더한다 — 다섯은 모듈 이름, 하나는 `ath9k_hif_usb`(확인 4).

셈 문자열은 `eleven` → `seventeen`으로 고친다. mutation은 둘이다 — `CONFIG_MT7601U`를 끄면
검사 1이 부팅 전에 잡는다(UW 실측 6과 같은 모양). 둘째는 검사 11의 등록 이름을 모듈 이름
`ath9k_htc`로 적는 것이다 — 확인 4가 맞으면 빨개지고, 틀렸으면 거기서 드러난다.
`guest_firmware.sh`의 줄을 지우는 것은 mutation이 못 된다 — 1b는 목록을 되읽는다(WL 위험 4).

### 결정 4 — `HID_APPLE` · `INPUT_LEDS`가 꺼진 채인지 게이트가 본다

확인 2의 전제("이미 적힌 답은 안 뒤집힌다")는 지금 참이지만 커널을 올릴 때(`olddefconfig`가
새 심볼을 묻는 날) 깨질 수 있다. 검사 1에 음성 검사 둘을 더한다 — `kernel/.config`에
`# CONFIG_HID_APPLE is not set` · `# CONFIG_INPUT_LEDS is not set` 줄이 있어야 한다. 이것이
`keyboard=apple`(`tars.conf`의 키보드 종류)의 fn 키를 커널 HID 층이 먼저 바꾸지 않는다는 표지다. 이 검사는
rtl8xxxu와 무관하게 유효하고, UW가 뺐던 이유를 게이트가 기억하는 자리다.

## 위험

### 위험 1 — 부팅 층이 등록만 보고 probe는 못 본다

UW 위험 1 그대로. QEMU에 이 동글이 없다. 실제 동글의 probe · firmware 올리기 · `wlan`
생성은 게이트 밖이다(비목표 1).

### 위험 2 — `olddefconfig`가 입력 쪽을 켠다

확인 2가 전제를 적었다. M0이 `.config` diff에서 `HID_` · `INPUT_LEDS` · `LEDS_` 줄을 센다.
하나라도 바뀌면 rtl8xxxu를 빼고 다섯으로 간다 — 결정 4의 음성 검사는 그래도 넣는다.

### 위험 3 — 8723BU의 bluetooth 짝 firmware가 없다

`rtl8723bu_bt.bin`은 이 linux-firmware에 없다. `enable_bluetooth`가 참인 8723BU에서 드라이버가
그 이름을 요청하고 실패하면 `request_firmware(...) failed` 경고 뒤 그 동글은 안 뜬다.
`enable_bluetooth`가 어디서 정해지는지(efuse인지 모듈 파라미터인지)는 M0이 소스에서 본다.
그것이 efuse라면 그 동글은 비목표 3이고, 파라미터라면 기본값이 무엇인지 적는다.

### 위험 4 — 2.4GHz 전용 옛 칩의 regulatory

mt7601u · rt2800usb · ath9k_htc · rtl8xxxu 대부분은 2.4GHz 전용이다. `wireless-regdb`는 이미
initrd에 있고(WL) 채널 12~14는 나라 설정(`tars-config wifi --country`)이 가른다. 새 일은 없고
적어 두는 것뿐이다.

## 비목표

1. 실칩 판정. 동글이 생기면 연다.
2. `RT2800USB_UNKNOWN` · `RTL8XXXU_UNTESTED`. 드라이버 작성자가 안 본 장치 목록이다. 실제
   동글이 그 목록에 있으면 그때 켠다.
3. 8723BU의 bluetooth(위험 3). TARS에 bluetooth 스택이 없다.
4. ath9k_htc의 1.3 firmware(`htc_9271.fw`) · mt76x2의 `mt7662u.bin` — 커널 6.18이 요청하지
   않는 파일.
5. 다른 USB 무선 계열 — `rtl8187` · `zd1211rw` · `carl9170` · `ar5523` · `p54usb` ·
   `libertas` · brcmfmac USB. 802.11g 시대이거나 시장에 거의 없다. 근거(실제 동글)가 오면 연다.
6. `tars-wifi` · dhcpcd hook의 변경. 드라이버를 가리지 않는다(UW).

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다. UW처럼 셋이지만 M0과 M1은 한 세션에 들어갈
크기다.

- UB-M0 — 실측, 코드 0줄. `.config` diff(따라 켜진 것 · 입력 쪽 0 · `ATH9K_PCI`의 진실), 새
  `firmware=` 줄, 등록 이름 여섯(부팅 한 번), 대표 alias 여섯의 실제 줄, `enable_bluetooth`의
  출처, bzImage 증분.
- UB-M1 — 커널 config, firmware 목록, 체인 검사 셋 + 음성 검사 둘.
- UB-M2 — mutation 둘, 루트 게이트(22체인, 약 10분), carryover · decisions · HANDOFF, 닫기.
