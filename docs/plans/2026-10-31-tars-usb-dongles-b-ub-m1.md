# UB-M1 — 여섯을 켜고 체인이 세게 한다

> M0이 작업 트리에 남긴 `kernel/.config`(열하나 `=y`, `RT2X00` 메뉴 포함)를 커밋하고, firmware
> 목록에 21개를 더하고, wifi 체인에 검사를 더한다. 우리 게스트 코드는 0줄이다. UW-M1과 같은
> 모양이고 다른 것은 결정 4의 음성 검사 둘뿐이다.

Goal: 결정 1~4를 코드로 옮긴다. 끝나면 tools 체인과 wifi 체인이 초록이다.

Architecture: 정적 검사 · 커널 산출물 검사 · 음성 검사는 wifi 체인 검사 1에 붙인다. 부팅 층은
부팅 C의 시리얼 로그에서 usbcore의 등록 줄을 센다(검사 11에 여섯을 더한다). firmware는
`guest_firmware.sh`에 21줄을 더하면 tools 체인 검사 1b가 자동으로 센다.

---

## Task 1: 해소된 `build/.config`를 `kernel/.config`로 복사한다

커밋된 `kernel/.config`는 늘 `olddefconfig`가 해소한 모양이다(HEAD의 것과 M0 기준선 `build/.config`의
diff가 0줄). M0이 `scripts/config`로 켠 작업 트리의 `.config`는 `RT2800USB` 넷이 파일 끝에 덧붙은
채라 그대로 커밋하지 않는다 — `cp kernel/build/.config kernel/.config` 뒤 `git diff kernel/.config`가
실측 1의 diff(따라 켜진 열여섯 · 새로 `not set`인 아홉 · 여섯의 뒤집힘)와 같아야 한다. 다른 줄이
있으면 멈춘다. `build.sh`는 `.config`의 해시로 판정하므로 다음 `make kernel`이 make를 한 번 더
돌지만 할 일이 없다(약 10초).

## Task 2: firmware 목록에 21개를 더한다

`kernel/guest_firmware.sh`의 계열 칸에 이름순으로 넣는다. 출처 경로는 tarball 안의 실제 파일이고
initrd 경로는 드라이버가 요청하는 이름이다 — 맨 위 이름 셋(`mt7601u.bin` · `mt7662.bin` ·
`mt7662_rom_patch.bin`)은 둘이 다르다(WHENCE `Link:`, 확인 3).

- MediaTek 칸(`mt7921e` 줄들 뒤), 머리 주석을 `mt7921e(MT7921 · MT7922) · mt7925e · mt7601u ·
  mt76x0u · mt76x2u(UB)`로:
  ```
  linux-firmware/mediatek/mt7601u.bin:lib/firmware/mt7601u.bin
  linux-firmware/mediatek/mt7610e.bin:lib/firmware/mediatek/mt7610e.bin
  linux-firmware/mediatek/mt7610u.bin:lib/firmware/mediatek/mt7610u.bin
  linux-firmware/mediatek/mt7662.bin:lib/firmware/mt7662.bin
  linux-firmware/mediatek/mt7662_rom_patch.bin:lib/firmware/mt7662_rom_patch.bin
  ```
- 새 칸 `# Ralink — rt2800usb(UB)`:
  ```
  linux-firmware/rt2870.bin:lib/firmware/rt2870.bin
  ```
- Qualcomm 칸 머리를 `# Qualcomm · Atheros — ath11k · ath12k · ath9k_htc(UB)`로, 끝에:
  ```
  linux-firmware/ath9k_htc/htc_7010-1.4.0.fw:lib/firmware/ath9k_htc/htc_7010-1.4.0.fw
  linux-firmware/ath9k_htc/htc_9271-1.4.0.fw:lib/firmware/ath9k_htc/htc_9271-1.4.0.fw
  ```
- Realtek 칸 머리를 `# Realtek — rtw88 · rtw89 · rtl8xxxu(UB)`로, 끝에 `rtlwifi/` 열셋
  (`rtl8188eufw` · `rtl8188fufw` · `rtl8192cufw_A` · `_B` · `_TMSC` · `rtl8192eu_nic` ·
  `rtl8192fufw` · `rtl8710bufw_SMIC` · `_UMC` · `rtl8723aufw_A` · `_B` · `_B_NoBT` ·
  `rtl8723bu_nic`), 출처와 initrd 경로가 같은 꼴 `linux-firmware/rtlwifi/X:lib/firmware/rtlwifi/X`.

머리말 둘을 고친다. "무엇을 넣었나"의 "USB 동글이 새로 찾는 것은 rtw88의 `…a_fw.bin` 셋뿐이다"
뒤에 "UB(층 B + rtl8xxxu)가 21개를 더했다 — 실측 2"를 더한다. "뺀 것"에 한 문장 —
`rtlwifi/rtl8723bu_bt.bin`(이 릴리스에 없고, 6.18의 rtl8xxxu가 요청하지 않는 죽은 이름 — UB 위험 3) ·
`mt7662u.bin` · `htc_9271.fw`(6.18이 요청하지 않는다, UB 비목표 4).

## Task 3: wifi 체인 검사 1 — 심볼 열하나 · alias 여섯 · 음성 검사 둘

심볼 루프의 마지막 줄 뒤에 한 줄을 더한다:
`MT7601U MT76x0U MT76x2U RT2X00 RT2800USB RT2800USB_RT53XX ATH9K_HTC RTL8XXXU`
(`RT53XX`는 결정 3의 층 1 — RT5370이 빠지는 것은 드라이버가 빠지는 것과 같다. `RT2X00`은
실측 1의 함정을 게이트가 기억하는 자리다).

alias 루프에 여섯을 더한다(실측 3의 `d`까지):
`mt7601u.alias=usb:v0B05p17D3d mt76x0u.alias=usb:v148Fp7610d mt76x2u.alias=usb:v0B05p1833d
rt2800usb.alias=usb:v07B8p2870d ath9k_htc.alias=usb:v0CF3p9271d rtl8xxxu.alias=usb:v2357p0108d`.

alias 루프 뒤, 통과 줄 앞에 음성 검사 둘(결정 4):

```bash
# rtl8xxxu가 기대는 LEDS_CLASS는 HID_APPLE · INPUT_LEDS의 조건이기도 하다. 둘이 켜지면 커널 HID
# 층이 Apple 키보드의 fn 키를 먼저 바꿔 keyboard=apple과 부딪친다(UW 비목표 1의 이유). 지금은
# .config에 "not set"으로 적혀 있어 olddefconfig가 안 뒤집지만, 커널을 올리는 날 새로 물을 수
# 있다 — 그날 여기가 빨개진다(UB design 결정 4).
for sym in HID_APPLE INPUT_LEDS; do
  if ! grep -x "# CONFIG_${sym} is not set" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is no longer 'not set' in kernel/.config — keyboard=apple may break"
    exit 1
  fi
done
```

통과 줄 `eleven USB dongles` → `seventeen USB dongles`. 검사 1 머리 주석의 "실칩 열여섯"은 그대로다
(노트북 칩 수).

## Task 4: wifi 체인 검사 11 — 등록 줄 여섯

`for drv in …` 목록 끝에 `mt7601u mt76x0u mt76x2u rt2800usb ath9k_htc rtl8xxxu`를 더하고 통과 줄을
`all seventeen USB dongle drivers`로, 머리 주석의 "열하나"를 "열일곱(UW 열하나 + UB 여섯)"으로.

## Task 5: 빌드하고 두 체인을 돌린다

```bash
make initrd 2>&1 | tail -3      # kernel(이미 최신) → init → terminal → make_initrd(vendor_firmware 포함)
make check CHAIN=tools
make check CHAIN=wifi
```

둘 다 초록이어야 한다. tools 1b의 통과 줄이 "all N files"에서 N이 21 늘었는지, wifi 검사 1의
통과 줄이 `seventeen`인지 본다. wifi 체인은 부팅 셋이라 약 3분이다.

## Task 6: 커밋

`kernel/.config` · `kernel/guest_firmware.sh` · `wifi/check.sh` · 이 plan. design은 Status 줄만
(`M1 끝`). `git add`는 넷을 이름으로 적는다 — `out/`과 `kernel/build/`는 산출물이다.

```bash
git commit -m "UB-M1: six USB dongle drivers on, 21 firmware files, wifi chain checks seventeen"
```
