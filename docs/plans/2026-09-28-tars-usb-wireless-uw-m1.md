# UW-M1 — USB 동글 열하나를 켜고 체인이 세게 한다

> M0이 작업 트리에 남긴 `kernel/.config`를 커밋하고, firmware 목록에 셋을 더하고, wifi
> 체인에 검사를 더한다. 우리 게스트 코드는 0줄이다.

Goal: 결정 1~3을 코드로 옮긴다. 끝나면 tools 체인과 wifi 체인이 초록이다.

Architecture: 정적 검사와 커널 산출물 검사는 wifi 체인 검사 1에 붙인다. 부팅 층은 부팅
C의 시리얼 로그에서 usbcore의 등록 줄을 센다(실측 5) — 탐침과 설정 디스크는 안 바뀐다.
firmware는 `guest_firmware.sh`에 세 줄을 더하면 tools 체인 검사 1b가 자동으로 센다.

---

## Task 1: design에 실측 5를 적는다

M0의 부팅 로그에 `usbcore: registered new interface driver <이름>`이 열하나 전부 있었다.
결정 3의 층 3을 "부팅 C의 로그에서 등록 줄을 센다"로 고치고 실측 5를 가리킨다.

## Task 2: firmware 목록에 셋을 더한다

`kernel/guest_firmware.sh`의 rtw88 칸, `rtw8723d_fw.bin` 뒤에 이름순으로 넣는다.

```
  linux-firmware/rtw88/rtw8812a_fw.bin:lib/firmware/rtw88/rtw8812a_fw.bin
  linux-firmware/rtw88/rtw8814a_fw.bin:lib/firmware/rtw88/rtw8814a_fw.bin
  linux-firmware/rtw88/rtw8821a_fw.bin:lib/firmware/rtw88/rtw8821a_fw.bin
```

머리 주석의 "PCIe 무선 드라이버"를 "PCIe 무선 드라이버와 USB 동글(UW 결정 1)"로 고친다.

## Task 3: wifi 체인 검사 1 — 심볼 열하나와 alias 넷

심볼 루프에 USB 열하나를 한 줄로 더한다. 그 뒤에 alias 넷을 본다. modinfo는 NUL로
나뉘어 있어서 `tr '\0' '\n'`을 거친다.

```bash
MODINFO=../kernel/build/modules.builtin.modinfo
for alias in rtw88_8822bu.alias=usb:v2357p012Dd rtw89_8852bu.alias=usb:v0BDApB832d \
  mt7921u.alias=usb:v0E8Dp7961d mt7925u.alias=usb:v0E8Dp7925d; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -F "$alias" >/dev/null; then
    echo "FAIL: the kernel has no ${alias%%.*} entry for ${alias#*usb:}"
    exit 1
  fi
done
```

통과 줄은 "sixteen laptop chips" 뒤에 "eleven USB dongles"를 더한다.

## Task 4: wifi 체인 검사 11 — 부팅 C에서 등록 줄 열하나

검사 10 뒤, 부팅 C의 `stop_guest` 앞에 둔다. 부팅 C를 고른 것은 가장 조용한 부팅이라서다
(파일도 라디오도 없다). 등록은 장치와 무관하게 일어나므로 `-usb`를 더하지 않는다 —
안 더한 채로 초록이면 그것이 증명이다.

```bash
for drv in rtw88_8822bu rtw88_8822cu rtw88_8723du rtw88_8821cu rtw88_8821au \
  rtw88_8812au rtw88_8814au rtw89_8851bu rtw89_8852bu mt7921u mt7925u; do
  grep -a "usbcore: registered new interface driver ${drv}\b" "$LOG" >/dev/null \
    || report_failure "usbcore never registered ${drv}"
done
```

## Task 5: 빌드하고 두 체인을 돌린다

`vendor_firmware.sh` → `make_initrd.sh` 순서로 firmware cpio와 initrd를 다시 만들고
`tools/check.sh`(검사 1b)와 `wifi/check.sh`를 돌린다. 둘 다 초록이어야 한다.

## Task 6: 커밋

`kernel/.config` · `kernel/guest_firmware.sh` · `wifi/check.sh` · design · 이 plan.
