# UW-M0 — USB 동글을 켜기 전에 넷을 잰다

> 이 milestone은 커밋되는 코드를 한 줄도 안 고친다. `kernel/.config`는 작업 트리에서만
> 바뀌고, M1이 그 해소된 모양을 커밋한다(WL-M0과 같다). 하네스는 `/tmp/uw/` 아래에
> 둔다. 저장소에 들어가는 것은 design의 "실측 (M0)" 절과 이 plan이다.

Goal: design 결정 1~3이 기다리는 값 넷을 잰다. M1이 그 값을 그대로 옮겨 적기만 하면 되게 한다.

Architecture: 지금 빌드의 산출물을 기준선으로 복사해 둔다. `scripts/config`로 작업 트리의
`kernel/.config`에 USB 심볼 열하나를 켜고 `kernel/build.sh`로 다시 빌드한 뒤 두 산출물을
비교한다. 등록 이름은 부팅 한 번으로 본다. 탐침은 설정 디스크의 `services.d/probe`이고
`init`이 부팅 때 띄운다.

---

## 무엇을 재나

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | `olddefconfig`가 따라 켠 심볼, bzImage 크기의 증분 | 결정 1 · 위험 2 |
| 2 | 새 `firmware=` 줄, 그 파일이 tarball에 있는지, 크기 | 결정 2 |
| 3 | 드라이버 열하나가 `/sys/bus/usb/drivers/`에 보이는 이름 | 결정 3의 층 3 |
| 4 | 계열마다 대표 동글의 `alias=usb:v…p…` 한 줄 | 결정 3의 층 2 |

## Task 1: 기준선을 떠 둔다

지금의 `build/.config` · `modules.builtin.modinfo` · bzImage 크기를 `/tmp/uw/base/`에
복사한다. 빌드가 최신인지부터 확인한다(`build.sh`가 "skipping make"를 말해야 한다).

```bash
mkdir -p /tmp/uw/base
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer ./build.sh 2>&1 | tail -3
cp kernel/build/.config /tmp/uw/base/config
cp kernel/build/modules.builtin.modinfo /tmp/uw/base/modinfo
stat -f %z kernel/build/arch/x86/boot/bzImage > /tmp/uw/base/bzimage.size
```

## Task 2: 열하나를 켜고 빌드한다

심볼이 전부 대문자라 `--keep-case`가 필요 없다(lessons 70). 커널 빌드는 증분이라
수 분이 걸린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer bash -c '
  for s in RTW88_8822BU RTW88_8822CU RTW88_8723DU RTW88_8821CU RTW88_8821AU \
           RTW88_8812AU RTW88_8814AU RTW89_8851BU RTW89_8852BU MT7921U MT7925U; do
    src/linux-6.18.42/scripts/config --file .config --enable "$s"
  done
  ./build.sh' 2>&1 | tail -5
```

켠 뒤 해소된 `build/.config`에 열하나가 `=y`로 남았는지 센다. 기대값은 11이다.

```bash
rg -c -x 'CONFIG_(RTW88_(8822BU|8822CU|8723DU|8821CU|8821AU|8812AU|8814AU)|RTW89_(8851BU|8852BU)|MT7921U|MT7925U)=y' kernel/build/.config
```

## Task 3: 측정 1 — 무엇이 따라 켜졌나

```bash
diff /tmp/uw/base/config kernel/build/.config | rg '^[<>] CONFIG_' > /tmp/uw/config.diff
cat /tmp/uw/config.diff
echo $(( $(stat -f %z kernel/build/arch/x86/boot/bzImage) - $(cat /tmp/uw/base/bzimage.size) ))
```

판정: 열하나와 칩 코어(`RTW88_8821A` · `8812A` · `8814A`), `RTW88_USB` · `RTW89_USB` ·
`MT76_USB` 계열 말고 다른 것이 있으면 적는다. `HID_*` · `NEW_LEDS` · `LEDS_*`가 있으면
멈추고 사용자에게 알린다(위험 2).

## Task 4: 측정 2 — 새 firmware 이름

```bash
rg -o 'firmware=.*' /tmp/uw/base/modinfo | sort -u > /tmp/uw/fw.base
rg -o 'firmware=.*' kernel/build/modules.builtin.modinfo | sort -u > /tmp/uw/fw.new
comm -13 /tmp/uw/fw.base /tmp/uw/fw.new
```

새 이름마다 linux-firmware tarball 안에 있는지 보고 크기를 적는다. 기대는 `rtw88/rtw8812a_fw.bin` ·
`rtw8814a_fw.bin` · `rtw8821a_fw.bin`이다. `Link:`로만 있는 이름이면 `WHENCE`에서 실체를 찾는다.

```bash
tar -tvJf kernel/src/firmware/linux-firmware-20260916.tar.xz | rg 'rtw88/rtw8(812|814|821)a'
```

## Task 5: 측정 4 — 대표 alias

`modules.builtin.modinfo`의 alias 줄은 `<모듈 이름>.alias=usb:v…p…` 모양이다. 앞의 모듈
이름이 곧 측정 3의 기대값이기도 하다.

```bash
rg -o '^[a-z0-9_]+\.alias=usb:[^\x00]*' kernel/build/modules.builtin.modinfo \
  | rg '^(rtw88_|rtw89_|mt792)' | awk -F. '{print $1}' | sort | uniq -c
```

계열(rtw88 · rtw89 · mt7921u · mt7925u)마다 흔한 동글 하나를 드라이버 소스의 id 표에서
고르고, 그 줄을 글자 그대로 적는다.

## Task 6: 측정 3 — 부팅해서 등록 이름을 본다

`/tmp/uw/probe`는 `#!/bin/sh`로 시작해 `ls /sys/bus/usb/drivers`를 `[이름]` 모양으로
`/dev/console`에 찍는다(lessons 68 — 콘솔 줄에 앵커를 쓰지 않으려고 괄호로 감싼다).
설정 디스크는 `services.d/probe` 하나와 빈 `tars.conf`로 만든다. 부팅은 wifi 체인의
`boot()`와 같은 인자(`-nic none` · `-m 512` · `-kernel`/`-initrd`)에 `-usb`를 더한다.
40초 안에 로그에서 열하나를 센다.

```bash
cat > /tmp/uw/probe <<'EOF'
#!/bin/sh
for d in /sys/bus/usb/drivers/*; do echo "uwprobe [${d##*/}]"; done > /dev/console
EOF
```

판정: Task 5에서 센 모듈 이름 열하나가 전부 로그에 있다. 없으면 그 드라이버의 USB 코어
등록이 실패한 것이므로 멈춘다.

## Task 7: 기록하고 커밋한다

design에 "## 실측 (M0, 2026-09-28)" 절을 더하고 측정 1~4를 번호대로 적는다. 결정이
바뀌면(예: 따라 켜진 심볼 때문에) 그 결정 자리를 고치고 실측을 가리킨다. `kernel/.config`는
커밋하지 않는다 — M1이 커밋한다.

```bash
git add docs/specs/2026-09-28-tars-usb-wireless-design.md \
        docs/plans/2026-09-28-tars-usb-wireless-uw-m0.md
git commit -m "UW-M0: measure the USB dongle drivers before turning them on"
```
