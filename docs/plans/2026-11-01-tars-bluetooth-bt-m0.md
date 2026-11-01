# BT-M0 — 켜기 전에 재고, 데몬 둘을 손으로 띄워 본다

> 커밋되는 코드는 0줄이다. `kernel/.config`와 `kernel/guest_firmware.sh`는 작업 트리에서만 바뀌고 M1이
> 커밋한다(UB-M0과 같다). 하네스는 세션 scratchpad의 `bt/` 아래. 저장소에 들어가는 것은 design의
> "실측 (M0)" 절과 이 plan이다. 사용자가 외출 중이라 판정은 Claude가 내린다(design "왜 지금인가").

Goal: design 결정 1 · 2의 값(따라 켜진 심볼 · firmware 이름과 크기 · initrd 증분 · 부팅 시간)과 위험 1 · 2 · 3 ·
5 · 7의 답을 잰다. 컨테이너 이미지는 아직 안 바꾼다 — BlueZ · D-Bus는 설정 디스크에 실어 게스트에서
`LD_LIBRARY_PATH`로 띄운다.

Architecture: 기준선(빌드 산출물 · initrd 크기 · 부팅 로그)을 떠 두고, `scripts/config -k`로 아홉을 켜 빌드하고,
firmware 목록에 BT 블록을 더해 initrd를 다시 만들어 둘을 비교한다. 부팅은 wifi 체인의 `boot()`와 같은 인자에
설정 디스크 하나 — `services.d/bt`가 `/config/bt/`의 BlueZ를 띄우고 `btvirt`로 컨트롤러를 만들고 `bluetoothctl`을
몰아 `bt-m0:` 줄을 콘솔에 찍는다(WL의 `ap.sh`와 같은 모양, 체인은 한 글자도 안 친다).

## 무엇을 재나

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | `olddefconfig`가 따라 켠 심볼, 입력 쪽이 0인지, bzImage 증분 | 결정 1 |
| 2 | 새 `firmware=` 줄(Realtek 50의 실제 이름 · tarball 존재), 목록의 수 | 결정 2 |
| 3 | initrd before/after(gzip · 푼 크기), 부팅의 initramfs 풀기 시간, `MemAvailable` | 위험 1 |
| 4 | 커널 로그의 `Bluetooth:` 줄 · `/dev/vhci` · `/dev/uhid` | 결정 8의 판정 후보 |
| 5 | dbus-daemon의 stderr(machine-id) · bluetoothd 기동 · `bluetoothctl list` · `show`의 Powered · `settings` 파일 | 위험 2 · 3, 결정 6 |
| 6 | `btvirt -l2` 두 컨트롤러 사이의 LE 페어링이 되는가, 몇 초인가, `info`의 `[LongTermKey]` | 위험 5 |
| 7 | dbus를 죽이면 bluetoothd가 어떻게 되는가 | 위험 7 |

## Task 1: 기준선

`make kernel`이 "skipping make"인지 본 뒤 `build/.config` · `modules.builtin.modinfo` · bzImage · initrd 크기를 복사한다.

## Task 2: 아홉을 켜고 빌드한다

`BT`를 먼저(부모 메뉴, UB 실측 1). 전부 `-k`. 판정: 해소된 `build/.config`에 아홉이 `=y`, diff에 `HID_` · `INPUT_LEDS`가
없다. 빌드는 `net/bluetooth` · `drivers/bluetooth`가 통째로 새로 컴파일되므로 UB의 30초보다 길다.

## Task 3: firmware 목록을 더하고 initrd를 다시 만든다

`guest_firmware.sh`에 "Bluetooth(BT-M1)" 블록 — Realtek은 Task 2의 `firmware=` 줄 중 tarball에 있는 것, Intel은
`intel/ibt-*` 전부, MediaTek 넷, Qualcomm `qca/rampatch_usb_*` · `nvm_usb_*` 전부. `make initrd` 뒤 크기 둘을 비교한다.

## Task 4: 부팅 둘

- 부팅 0 — 기준선 initrd, 디스크 없음. `tars-init: starting` 줄의 커널 시각(initramfs 풀기 포함)과 `MemAvailable`.
- 부팅 1 — 새 커널 · 새 initrd, 설정 디스크(`tars.conf` 빈 줄 · `services.d/bt` · `/config/bt/`에 BlueZ · D-Bus ·
  라이브러리 · 설정 · `btvirt`). `bt` 스크립트가 측정 4~7을 차례로 찍는다. 시각 · 메모리를 부팅 0과 비교한다.

## Task 5: 기록하고 커밋한다

design에 "## 실측 (M0, 2026-11-01)"을 더하고 바뀐 결정을 고친다. M1 plan을 쓴다.
