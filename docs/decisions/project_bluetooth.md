---
name: project_bluetooth
description: "블루투스 활성화(BT-M0~M2, 2026-11-02) — 커널 BT 스택 · USB/PCIe HCI · HIDP · uhid, BlueZ 5.82 + dbus-daemon을 init이 감독, tars.conf `bluetooth=on`, 페어링은 bluetoothctl · 키는 /config/bluetooth. 함정 — bluetoothctl은 tty가 아니면 끝까지 버퍼링, btmgmt는 stdin 없이 멈춤, zsh의 `$n:l`, Realtek 이름은 MODULE_FIRMWARE가 아니라 ic_id_table"
metadata:
  node_type: memory
  type: project
---

# Bluetooth (BT)

design은 `docs/specs/2026-11-01-tars-bluetooth-design.md`, plan은 `docs/plans/2026-11-01-tars-bluetooth-bt-m0.md` · `-m1.md` ·
`-m2.md`. 2026-11-01에 사용자가 KU 다음으로 골랐고 범위를 "클래식 + BLE 키보드 · 마우스"(오디오 제외)로 정한 뒤 외출하며
나머지 결정을 Claude에게 맡겼다 — design의 결정은 추천안으로 정한 것이다.

## 무엇이 섰나

- 커널 `BT` · `BT_HIDP` · `BT_HCIBTUSB`(+`_MTK`) · `BT_INTEL_PCIE`(BE200 · BE201은 BT가 PCIe로 온다) · `BT_HCIVHCI`(게이트) · `UHID`(BLE
  HID) · `CRYPTO_USER_API_HASH` · `_SKCIPHER`(BlueZ의 AF_ALG). 아홉을 켜면 71줄이 따라 움직이고 입력 쪽은 안 움직인다.
- firmware 157 — Intel `ibt-*` 전부(84, 28MB · gzip 20MB, hw_variant 표가 우리 iwlwifi 세대 전부와 겹친다) · Realtek 31 · MediaTek
  4(MT7921 · 7922 · 7925) · Qualcomm USB 38. initrd 93.4 → 116.6MB, 풀기 +0.48초, RAM −31MB.
- 사용자 공간은 Debian trixie의 `bluez 5.82` · `dbus-daemon 1.16`(dbus-broker는 systemd 런처가 필요하다). 새 라이브러리 여덟 3.0MB.
  `btvirt`(bluez-test-tools)는 sysroot에만 — 게이트의 설정 디스크가 가져간다.
- init의 감독 칸 둘 `dbus` · `bluetoothd`(2 · 3번, 무선 셋 앞), 래퍼 `kernel/bluetooth/tars-dbus` · `tars-bluetoothd`(뒤는 버스 소켓을
  10초까지 기다린 뒤 `bluetoothd -n -P sap,network`). `tars.conf` 열셋째 키 `bluetooth=off|on`(기본 off, reload의 `now` 갈래).
- 페어링은 `bluetoothctl` 그대로(`scan on` · `pair` · `trust` · `connect`). 키는 `/var/lib/bluetooth → /config/bluetooth` 링크로
  디스크에 남고 재시작한 bluetoothd가 되읽는다.
- 게이트는 스물셋째 체인 `bluetooth/check.sh`(monitor 없음) — `hci_vhci` 위의 `btvirt -l2` 컨트롤러 둘을 Just Works로 페어링하고
  재시작 · 끄기까지 본다. 부팅 B는 기본값의 음성.

## 배운 것 — 다시 조사하지 말 것

1. `bluetoothctl`은 stdout이 tty가 아니면 끝날 때까지 한 줄도 안 쓴다 — 파일로 받고 `quit` 뒤에 읽는다. stdin은 파이프로 줘도
   명령을 받는다(`( sleep 2; echo cmd; … ) | bluetoothctl`). `--timeout N`은 한 줄 명령 모드의 수명이다.
2. `btmgmt`는 stdin이 `/dev/null`이면 명령 뒤에 안 끝나고 멈춘다. 자동화에 안 쓴다.
3. 두 어댑터가 한 bluetoothd 안에 있으면 에이전트는 하나만 둔다(A 쪽 `agent NoInputNoOutput` + `default-agent` → Just Works). B 쪽
   bluetoothctl은 `agent off`. 광고는 B의 bluetoothctl이 살아 있는 동안만 유효하다(`advertise on`은 클라이언트의 것).
4. `dbus-daemon --system`과 `--config-file`은 함께 못 준다(`--system`이 곧 `/usr/share/dbus-1/system.conf`). machine-id 없이 뜬다.
   커널에 `INOTIFY_USER`가 없어 "Cannot initialize inotify" 한 줄을 적는다 — 설정 감시만 포기한다. TCG에서 소켓은 2초 뒤.
5. Realtek BT firmware의 이름은 `btrtl.c`의 `ic_id_table`(fw_name · cfg_name)이 정본이고 `MODULE_FIRMWARE` 50줄은 그 부분집합이다.
   tarball에만 있고 안 요청되는 셋(`rtl8192ee_fw` · `rtl8192eu_fw` · `rtl8812ae_fw`)은 안 넣는다. Intel · MediaTek · Qualcomm은
   이름을 실행 중에 만든다(`snprintf`) — modinfo로 못 센다.
6. zsh에서 `"$n:lib/…"`는 `$n`을 소문자로 바꾸고 `:l`을 먹는다(수식어). `${n}:lib`로 쓴다. 이 저장소의 셸 작업은 zsh다.
7. terminal은 부팅 때 고른 키보드 하나만 읽는다 — BT 키보드는 evdev까지만 간다. 후속 "Keyboard Hotplug"(`carryover.md`).

관련: [[project_wireless]] (같은 모양의 선례), [[project_measuring_tool_cost]], [[project_kernel_upgrade]] (firmware 넷의 출처)
