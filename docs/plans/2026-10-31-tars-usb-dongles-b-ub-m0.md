# UB-M0 — 여섯을 켜기 전에 넷을 잰다

> 이 milestone은 커밋되는 코드를 한 줄도 안 고친다. `kernel/.config`는 작업 트리에서만
> 바뀌고, M1이 그 해소된 모양을 커밋한다(UW-M0과 같다). 하네스는 세션 scratchpad
> (`/private/tmp/claude-501/-Users-dp-Repository-tars-linux/<세션>/scratchpad/ub/`) 아래에
> 둔다. 저장소에 들어가는 것은 design의 "실측 (M0)" 절과 이 plan, 그리고 확인 6의 결과로
> 고칠 수 있는 `carryover.md` 한 줄이다.

Goal: design 결정 1~4가 기다리는 값 넷을 잰다. M1이 그 값을 그대로 옮겨 적기만 하면 되게 한다.

Architecture: 지금 빌드의 산출물을 기준선으로 복사해 둔다. `scripts/config -k`로 작업 트리의
`kernel/.config`에 여섯과 rt2800usb의 하위 셋을 켜고 `make kernel`로 다시 빌드한 뒤 두 산출물을
비교한다. 등록 이름은 부팅 한 번의 시리얼 로그에서 본다 — UW 실측 5대로 usbcore가 장치 없이도
찍으므로 탐침도 설정 디스크도 없다.

---

## 무엇을 재나

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | `olddefconfig`가 따라 켠 심볼, 입력 쪽이 0인지, `ATH9K_PCI`의 진실, bzImage 증분 | 결정 1 · 위험 2 · 확인 6 |
| 2 | 새 `firmware=` 줄, 확인 3의 27개와 같은지, `enable_bluetooth`의 출처 | 결정 2 · 위험 3 |
| 3 | 여섯의 대표 alias 줄(글자 그대로, rtl8xxxu의 `d*` 뒤) | 결정 3의 층 2 · 확인 5 |
| 4 | usbcore 등록 줄 여섯 — 특히 `ath9k_hif_usb` | 결정 3의 층 3 · 확인 4 |

## Task 1: 기준선을 떠 둔다

빌드가 최신인지부터 본다(`build.sh`가 "skipping make"를 말해야 한다). 그 뒤 `build/.config` ·
`modules.builtin.modinfo` · bzImage 크기를 복사한다.

```bash
UB=<scratchpad>/ub; mkdir -p "$UB/base"
make kernel 2>&1 | tail -2
cp kernel/build/.config "$UB/base/config"
cp kernel/build/modules.builtin.modinfo "$UB/base/modinfo"
stat -f %z kernel/build/arch/x86/boot/bzImage > "$UB/base/bzimage.size"
```

## Task 2: 여섯과 하위 셋을 켜고 빌드한다

`MT76x0U` · `MT76x2U`는 소문자가 섞였다 — `-k`(`--keep-case`) 없이 켜면 `MT76X0U`가 적히고
`olddefconfig`가 조용히 버린다(measurements 70). 전부 `-k`로 켠다. `RT2800USB_RT3573` ·
`RT53XX` · `RT55XX`는 default n이라 명시한다. `RT33XX` · `RT35XX`는 default y라 메뉴가 열리면
따라온다 — 그래도 해소된 파일에서 센다. 커널 빌드는 증분이지만 `RT2X00` 메뉴 하나가 새로
열리므로 UW의 20초보다 길다.

```bash
$IN_CONTAINER 'cd kernel && for s in MT7601U MT76x0U MT76x2U RT2800USB RT2800USB_RT3573 \
  RT2800USB_RT53XX RT2800USB_RT55XX ATH9K_HTC RTL8XXXU; do
  src/linux-6.18.42/scripts/config -k --file .config --enable "$s"; done && ./build.sh' 2>&1 | tail -5
```

판정: 해소된 `kernel/build/.config`에 여섯 + 하위 다섯 = 열하나가 `=y`다.

```bash
rg -c -x 'CONFIG_(MT7601U|MT76x0U|MT76x2U|RT2800USB|RT2800USB_RT(33XX|35XX|3573|53XX|55XX)|ATH9K_HTC|RTL8XXXU)=y' kernel/build/.config
```

## Task 3: 측정 1 — 무엇이 따라 켜졌나

```bash
diff "$UB/base/config" kernel/build/.config | rg '^[<>] (# )?CONFIG_' > "$UB/config.diff"
cat "$UB/config.diff"
echo $(( $(stat -f %z kernel/build/arch/x86/boot/bzImage) - $(cat "$UB/base/bzimage.size") ))
```

판정 셋.
- 입력 쪽(`HID_` · `INPUT_LEDS` · `LEDS_`)이 diff에 하나라도 있으면 멈추고 사용자에게 알린다
  (위험 2). 있으면 rtl8xxxu를 빼고 Task 2를 다섯으로 다시 돈다.
- `ATH9K_PCI` · `ATH9K`가 있는지 본다(확인 6). 없으면 carryover의 그 줄을 고친다.
- 그 밖의 것은 전부 적는다 — 예상은 `MT76x0_COMMON` · `MT76x2_COMMON` · `MT76x02_LIB` ·
  `MT76x02_USB` · `RT2X00` · `RT2800_LIB` · `RT2X00_LIB(_USB|_FIRMWARE|_CRYPTO|_LEDS)` ·
  `ATH9K_HW` · `ATH9K_COMMON` · `CRC_CCITT`다.

## Task 4: 측정 2 — 새 firmware 이름

```bash
tr '\0' '\n' < "$UB/base/modinfo" | rg -o 'firmware=.*' | sort -u > "$UB/fw.base"
tr '\0' '\n' < kernel/build/modules.builtin.modinfo | rg -o 'firmware=.*' | sort -u > "$UB/fw.new"
comm -13 "$UB/fw.base" "$UB/fw.new"
```

판정: 확인 3의 27개와 글자 그대로 같다. 다르면 design 확인 3을 고친다. 그리고 `rtl8xxxu`
소스에서 `enable_bluetooth`에 대입하는 자리를 찾는다 — design을 쓸 때의 `rg`는 읽는 자리
둘(`8723a.c` · `8723b.c`)과 선언(`rtl8xxxu.h`)만 보였고 대입이 0곳이었다. 그것이 맞으면
`rtl8723bu_bt.bin`은 6.18이 절대 요청하지 않는 이름이고 위험 3은 "없는 파일"이 아니라
"안 쓰는 이름"으로 닫힌다. 파일 27 중 26개의 tarball 존재는 design이 이미 봤다.

## Task 5: 측정 3 — 대표 alias 여섯의 실제 줄

```bash
tr '\0' '\n' < kernel/build/modules.builtin.modinfo \
  | rg '^(mt7601u|mt76x0u|mt76x2u|rt2800usb|ath9k_htc|rtl8xxxu)\.alias=usb:' | awk -F. '{print $1}' | sort | uniq -c
tr '\0' '\n' < kernel/build/modules.builtin.modinfo \
  | rg '^(mt7601u\.alias=usb:v0B05p17D3|mt76x0u\.alias=usb:v148Fp7610|mt76x2u\.alias=usb:v0B05p1833|rt2800usb\.alias=usb:v07B8p2870|ath9k_htc\.alias=usb:v0CF3p9271|rtl8xxxu\.alias=usb:v2357p0108)'
```

판정: 여섯 줄이 다 있다. rtl8xxxu의 줄은 `d*` 뒤에 `ic*isc*ip*`가 아니라 `icFFiscFFipFF`
비슷한 것이 붙을 것이다(`USB_DEVICE_AND_INTERFACE_INFO`) — M1의 검사는 UW처럼 `d` 앞까지만
`grep -F`로 대조하므로 모양만 적어 둔다. 모듈 이름 `ath9k_htc`의 alias가 있는지도 여기서
확인한다(등록 이름과 다른 것은 usb_driver의 `.name`뿐이고 alias는 모듈 이름을 쓴다).

## Task 6: 측정 4 — 부팅해서 등록 줄을 본다

wifi 체인의 `boot()`와 같은 인자에서 `-drive`를 뺀다(설정 디스크 없이도 커널은 드라이버를
등록한다 — 등록은 `init` 전에 일어난다). `-usb`도 필요 없다(UW 실측 5). 40초 안에 로그에서
여섯을 센다. initrd는 지금 것을 그대로 쓴다 — firmware가 없어도 등록은 된다.

```bash
qemu-system-x86_64 -nic none -m 512 -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio -append console=ttyS0 -vga none -device virtio-gpu-pci -display none \
  -serial file:"$UB/boot.log" -no-reboot & sleep 40; kill %1
rg -a 'usbcore: registered new interface driver (mt7601u|mt76x0u|mt76x2u|rt2800usb|ath9k_hif_usb|ath9k_htc|rtl8xxxu)\b' "$UB/boot.log"
```

판정: 여섯 줄 — `mt7601u` · `mt76x0u` · `mt76x2u` · `rt2800usb` · `ath9k_hif_usb` · `rtl8xxxu`.
`ath9k_htc`라는 등록 줄은 없어야 한다(확인 4). 하나라도 빠지면 그 드라이버의 USB 코어 등록이
실패한 것이므로 멈춘다.

## Task 7: 기록하고 커밋한다

design에 "## 실측 (M0, 2026-10-31)" 절을 더하고 측정 1~4를 번호대로 적는다. 결정이 바뀌면 그
결정 자리를 고치고 실측을 가리킨다. 확인 6이 틀렸다고 나오면 `carryover.md`의 "`ATH9K_PCI`가
따라 켜진다"를 고친다. `kernel/.config`는 커밋하지 않는다 — M1이 커밋한다. 작업 트리의
`.config`는 M1까지 켠 채로 둔다(되돌리면 커널을 두 번 더 빌드한다).

```bash
git add docs/specs/2026-10-31-tars-usb-dongles-b-design.md \
        docs/plans/2026-10-31-tars-usb-dongles-b-ub-m0.md docs/guides/carryover.md
git commit -m "UB-M0: measure the six USB dongle drivers before turning them on"
```
