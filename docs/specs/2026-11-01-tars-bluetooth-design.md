# TARS Bluetooth — Design

접두사: BT

Status: 끝났다(2026-11-02) — M0~M2, 결정 8 · 위험 8 · 실측 1~12. 커널 아홉 `=y`, firmware 157(initrd +23MB), BlueZ 5.82 + dbus-daemon을 init이 감독, `bluetooth=on`, 체인 스물셋째. mutation 셋 잡힘. 루트 게이트 23/23, 10분 25초(prebuild 약 310 + lanes 315초), verify 8208줄 전부 통과. 사용자가 외출하며 결정을 맡겨 M0~M2를 한 세션에 했다.

관련 문서: `2026-09-28-tars-wireless-design.md`(WL. 커널 드라이버 + firmware + 데몬 하나를 감독 목록에
넣은 선례 — 이 설계는 그 모양을 그대로 따른다) · `2026-10-31-tars-usb-dongles-b-design.md`(UB. firmware를
빌드 산출물에서 세는 규칙) · `2026-10-06-tars-config-tool-design.md` · `2026-10-07-tars-config-reload-design.md`(키를
더하는 자리와 reload의 갈래) · `docs/decisions/project_measuring_tool_cost.md`(게스트 도구의 비용을 재는 절차) ·
`docs/decisions/project_write_or_reuse.md`(페어링 도구를 안 짜는 근거).

## 한 줄 요약

커널에 Bluetooth 스택과 USB · PCIe HCI 드라이버 · HIDP · uhid를 켜고, 칩별 BT firmware를 initrd 꼬리에 더하고,
Debian의 BlueZ(`bluetoothd`)와 D-Bus 데몬을 initrd에 들여 init이 감독한다. `tars.conf`의 `bluetooth=on`이 둘을 켜고,
페어링은 `bluetoothctl`로 하며 키는 `/config/bluetooth`에 남는다. 목표는 클래식 BT와 BLE 키보드 · 마우스까지다.
오디오는 비목표다.

## 왜 지금인가

2026-11-01 Kernel Upgrade를 닫은 자리에서 사용자가 다음을 Bluetooth 활성화로 골랐고, 같은 날 범위를
"클래식 + BLE HID"로 정했다(오디오 A2DP는 뺐다). 0.1.4는 커널 7.4 longterm 뒤에 내기로 했다. 그리고 착수 뒤
외출하며 나머지 결정을 전부 Claude에게 맡겼다 — 그래서 이 문서의 결정은 사용자에게 묻지 않고 추천안으로
정한 것이다(`feedback_design_question_load`). 틀렸으면 돌아와서 뒤집는다.

지금 TARS에는 블루투스가 한 글자도 없다 — `kernel/.config`가 `# CONFIG_BT is not set`, initrd에 BlueZ도 D-Bus
데몬도 없다. 소개 페이지의 "부팅 · 하드웨어" note, AU design 비목표 1("블루투스 스택 자체가 없다"), VD design의
D10b · 비목표 4 · 7, BS design의 `scope` 행이 이 사실에 기대고 있다(확인 8).

## 착수 전에 아는 것 (2026-11-01에 소스 · tarball · Debian 저장소에서 확인)

### 확인 1 — 스택의 바닥은 꺼져 있고, 바닥이 기대는 것은 다 켜져 있다

`kernel/.config`(6.18.60). `# CONFIG_BT is not set`. `RFKILL=y` · `USB=y` · `PCI=y` · `HID=y` · `HID_GENERIC=y` ·
`INPUT_EVDEV=y` · `CRYPTO_AES=y` · `CRYPTO_CMAC=y` · `CRYPTO_ECB=y`. `BT`가 `select`로 끌어오는 것(CRC16 ·
ECDH · 나머지 암호)은 따로 고를 것이 없다. 꺼져 있고 우리가 켜야 하는 것:

| 심볼 | 왜 | 기본값 |
|---|---|---|
| `BT` · `BT_BREDR` · `BT_LE` | 스택. BREDR · LE는 `BT` 아래 default y | n |
| `BT_HIDP` | 클래식 BT 키보드 · 마우스. 커널이 HID 리포트를 받아 evdev로 낸다 | n |
| `BT_HCIBTUSB` | HCI over USB. x86 노트북의 내장 BT는 거의 전부 이 길이다(Intel · Realtek · MediaTek · Qualcomm) | n |
| `BT_HCIBTUSB_MTK` | btusb 안의 MediaTek 분기. `_RTL` · `_BCM`은 default y, 이것만 default n | n |
| `BT_INTEL_PCIE` | Intel BE200 · BE201(우리가 `iwlwifi-bz-*` · `gl-*`를 싣는 칩)은 BT가 USB가 아니라 PCIe로 온다(`btintel_pcie`) | n |
| `BT_HCIVHCI` | `/dev/vhci`, 가상 HCI. 게이트가 컨트롤러를 만드는 유일한 길(확인 2) | n |
| `UHID` | BLE HID(HOG)는 커널에 없다. `bluetoothd`가 GATT로 읽은 리포트를 `/dev/uhid`로 커널 HID에 넣는다 | n |
| `CRYPTO_USER_API_HASH` · `CRYPTO_USER_API_SKCIPHER` | BlueZ `src/shared/crypto.c`가 AF_ALG로 `cmac(aes)` · `ecb(aes)`를 쓴다(GATT DB 해시, 그리고 `btvirt`의 SMP 에뮬레이션) | n |

`BT_HCIBTUSB_AUTOSUSPEND`(default n)는 그대로 둔다. `BT_DEBUGFS`는 `DEBUG_FS`가 꺼져 있어 안 따라온다. `BT_RFCOMM` ·
`BT_BNEP` · `BT_HCIUART` · `BT_HCIBTSDIO`는 안 켠다(비목표 3 · 4).

### 확인 2 — QEMU에는 BT 장치가 없다. 커널에 가상 HCI가 있고 BlueZ에 그 상대가 있다

컨테이너의 QEMU 10.0.13은 `-device help`에 BT가 하나도 없다(QEMU는 5.0에서 BT 에뮬레이션을 지웠다). 커널의
`hci_vhci`는 `/dev/vhci`에 쓰는 프로그램이 컨트롤러 노릇을 하게 한다 — 첫 write가 `hci_register_dev`를 부르고
그 뒤 HCI 명령이 그 fd로 온다. 그 상대가 BlueZ의 `btvirt`(`emulator/`)다. Debian `bluez-test-tools` 5.82-1.1에
`/usr/bin/btvirt`(166,384바이트, DT_NEEDED는 libc뿐)가 있다. `btvirt -l2`는 LE 컨트롤러 둘을 만들고 둘 사이를
가상 링크로 잇는다 — BlueZ 자신의 `mgmt-tester` · `smp-tester`가 이 위에서 돈다. 그래서 게스트 안에서
"컨트롤러 등록 → bluetoothd가 켠다 → 설정이 `/config`에 써진다"까지, 그리고 아마 두 가상 컨트롤러 사이의
페어링까지 볼 수 있다(결정 8, 위험 5). 실칩은 무선처럼 실기 몫이다.

### 확인 3 — 키보드 · 마우스는 두 층이고, 둘째 층이 D-Bus를 부른다

클래식 BT HID는 커널 `hidp`가 HID 파싱까지 하고, 사용자 공간은 페어링과 L2CAP 연결만 맡는다. BLE HID(HID over
GATT, HOG)는 커널에 없다 — 사용자 공간이 GATT 클라이언트로 리포트를 읽어 `uhid`로 넣어야 한다. 요즘 키보드 ·
마우스 대부분(Apple Magic Keyboard 2 이후, Logitech MX 계열)이 BLE다. BlueZ의 `bluetoothd`가 둘 다 한다(input
플러그인 — 바이너리에 `/dev/uhid` · `UserspaceHID` · `ClassicBondedOnly` 글자가 있다). `bluetoothd`는 D-Bus 시스템
버스 없이는 안 뜬다. 즉 BLE HID를 하기로 한 순간 D-Bus 데몬이 따라온다 — 사용자가 이 범위를 고른 것은 이
사실을 들은 뒤다.

`HID_APPLE`은 꺼진 채다(UB 결정 4의 음성 검사). BT로 붙은 Apple 키보드도 USB의 것과 같이 `hid-generic`으로
온다 — `keyboard=apple`의 fn 처리는 지금과 같은 전제다.

### 확인 4 — Debian trixie의 BlueZ · D-Bus를 들이는 비용은 약 5.5MB다

`project_measuring_tool_cost`의 절차로 컨테이너에서 쟀다(`apt-cache depends --recurse` 닫힘 → 스테이징에 풀고
재귀 `DT_NEEDED`를 지금 sysroot와 대조).

| 패키지 | 버전 | 쓰는 것 | 바이트 |
|---|---|---|---|
| `bluez` | 5.82-1.1 | `/usr/libexec/bluetooth/bluetoothd` · `/usr/bin/bluetoothctl` · `btmgmt` · `/etc/bluetooth/main.conf` · `input.conf` · `/usr/share/dbus-1/system.d/bluetooth.conf` | 1,693,224 · 584,632 · 182,696 |
| `dbus-daemon` | 1.16.2-2 | `/usr/bin/dbus-daemon` | 248,408 |
| `dbus-system-bus-common` | 1.16.2-2 | `/usr/share/dbus-1/system.conf`(`<user>messagebus</user>`) | 5,807 |
| `dbus-bin` | 1.16.2-2 | `dbus-send`(진단) · `dbus-uuidgen`(위험 2) | 30,944 · 14,560 |
| `bluez-test-tools` | 5.82-1.1 | `btvirt` — sysroot에만, 게이트의 설정 디스크가 가져간다(WL 결정 7과 같다) | 166,384 |

새 라이브러리는 여덟, 합 3,023,272바이트 — `libglib-2.0.so.0` 1,404,320 · `libdw.so.1` 762,392 · `libudev.so.1`
280,936 · `liblzma.so.5` 198,832 · `libexpat.so.1` 186,528 · `libapparmor.so.1` 84,728 · `libbz2.so.1.0` 74,688 ·
`libatomic.so.1` 30,848. 패키지로는 `libglib2.0-0t64` · `libdw1t64` · `libudev1` · `liblzma5` · `libexpat1` ·
`libapparmor1` · `libbz2-1.0` · `libatomic1`. 이미 sysroot에 있는 것(`libdbus-1` · `libasound` · `libsystemd` ·
`libselinux` · `libelf` · `libz` · `libzstd` · `libpcre2-8` · `libreadline` · `libcap-ng` · `libaudit`)은 다시 안 센다 —
initrd에 아직 없는 것이 있으면 M0의 before/after가 센다. `btvirt`와 `btmgmt`는 libc(+readline)뿐이다.

`bluetoothd`는 설정을 `/var/lib/bluetooth/<어댑터>/<장치>/info`에 쓴다(바이너리의 `/var/lib/bluetooth`). 5.82의
`main.conf`는 `AutoEnable`이 기본 true다 — 컨트롤러가 보이면 켠다.

### 확인 5 — firmware 이름은 Realtek만 소스에 있고 셋은 실행 중에 만든다

| 계열 | 드라이버 | 이름 | tarball(20260916) raw | gzip -6 |
|---|---|---|---|---|
| Intel | `btintel.c` | `intel/ibt-<hw>-<rev>.sfi` · `.ddc`(ROM 세대는 `ibt-hw-37.7/37.8*.bseq`). `MODULE_FIRMWARE`는 넷뿐, 나머지는 `snprintf` | 28,169,921 (84개) | 19,951,194 |
| Realtek | `btrtl.c` | `rtl_bt/rtl8xxx_fw.bin` · `_config.bin`. `MODULE_FIRMWARE` 50줄 | 1,454,837 (38개) | 922,899 |
| MediaTek | `btmtk.c` | `mediatek/BT_RAM_CODE_MT%04x_1_%x_hdr.bin`, 7925는 `mediatek/mt7925/` 아래 | 2,503,660 (5개) | 2,263,864 |
| Qualcomm | `btusb.c` | `qca/rampatch_usb_%08x.bin` · `qca/nvm_usb_%08x*.bin` | 1,065,156 (38개) | 651,055 |

`btintel.c`의 hw_variant 표(WP · StP · SfP · WsP · JfP · ThP · HrP · CcP · TyP · Slr · Slr-F · Mgr · GaP · BzrU · Bzr ·
Scorpious Peak · BzrIW)는 7260부터 BE211까지다 — 우리가 싣는 iwlwifi(3160/7260 ~ `sc`) 세대 전부와 겹친다.
그래서 Intel은 계열로 가를 근거가 없고 전부 넣는다(결정 2). 한 칩에 `<rev>` 변형이 여럿인 것(`ibt-0190-*`
12개)은 보드마다 다른 것이라 못 고른다. MediaTek 다섯 중 `MT7902`는 우리가 무선을 안 싣는 칩이라 뺀다.
Qualcomm의 `nvm_usb` 31개는 보드 변형이라 다 넣는다(합 1MB). 이 비용의 거의 전부가 Intel이고, 그것이 위험 1이다.

### 확인 6 — init의 데몬 칸은 셋이고 설정 키는 열둘이다

`init/src/main.zig`의 감독 칸은 0 · 1(terminal · 콘솔 셸), 2 ~ 4(`wpa_supplicant` · `dhcpcd` · `chronyd`), 그 뒤
`services.d` 여덟 = 열셋(`SLOTS`). 데몬을 넣을지는 `wifi.wants` · `net.wantsDhcpcd` · `clock.prepare`가 답하고
reload(TC-M2)가 같은 함수로 다시 묻는다. `tars.conf`의 키는 열둘이고 그 수가 박힌 자리는 `reload.zig`의
갈래 · `config_edit.KEYS` · `config_edit_test`(`!= 12`) · `reload_test` · `config/check.sh`의 `TC_LIST_WANT`다. 키 하나를
더하면 이 자리들이 전부 열셋이 된다 — 빠뜨리면 호스트 검사가 먼저 잡게 되어 있다(`groupOf`의 컴파일 에러,
`KEYS.len` 검사).

### 확인 7 — terminal은 부팅 때 고른 키보드 하나만 읽는다

init이 `devices.resolveKeyboard`로 키보드 하나를 골라 terminal argv로 넘기고 terminal은 그 fd 하나(`keyboard_fd`)를
poll한다. 포인터는 다르다 — PD-M0이 uevent 소켓으로 부팅 뒤 장치를 잡는다(`drainUevents` · `tryOpenPointer`).
그래서 BT 마우스는 `bluetoothd` → uhid/hidp → evdev → uevent → terminal까지 코드 없이 닿지만, BT 키보드는
evdev까지만 간다. USB 키보드를 부팅 뒤에 꽂아도 지금 같은 틈이다 — 입력 층의 일이지 BT의 일이 아니라
비목표 1로 두고 후속 후보 "Keyboard Hotplug"로 적는다. 이 서브프로젝트가 끝나도 BT 키보드는 아직 글자를
못 친다 — 이것을 숨기지 않는다.

닫힘(2026-11-02). Keyboard Hotplug(KH)가 terminal이 키보드를 포인터와 같은 길로 스스로 열게 했다
(`docs/specs/2026-11-02-tars-keyboard-hotplug-design.md`). BT 키보드도 evdev 노드가 생기는 순간부터 친다. BLE의 uhid 길은
여전히 게이트가 못 본다(위험 4).

### 확인 8 — "블루투스가 없다"에 기대는 문서

소개 페이지(`gh-pages`의 `data.js`) "부팅 · 하드웨어"의 note · AU design 비목표 1 · VD design 63행 · D10b · 비목표
4 · 7 · BS design `scope` 행(BT 헤드셋의 배터리) · `running-tars.md` 726행("기대하지 않는 것 — Bluetooth 오디오") ·
UB design 비목표 3("TARS에 bluetooth 스택이 없다"). 닫을 때 고친다 — 오디오가 없다는 말은 그대로 참이다.

### 확인 9 — 게이트의 자리

새 체인은 스물셋째, monitor 포트는 45495(lessons의 포트 목록). sysroot에만 있는 도구는 설정 디스크로
가져간다(WL 결정 7의 hostapd). firmware가 initrd에 있는지는 `tools` 체인 검사 1b가 목록을 되읽어 자동으로
센다. `bluetooth=on`은 체인이 seed로 쓰면 되고, 기본값 `off`의 음성은 디스크 없는 부팅이 본다.

## 결정

### 결정 1 — 커널은 확인 1의 표를 전부 `=y`로 켠다

`scripts/config -k --enable`로 `BT` · `BT_HIDP` · `BT_HCIBTUSB` · `BT_HCIBTUSB_MTK` · `BT_INTEL_PCIE` · `BT_HCIVHCI` · `UHID` ·
`CRYPTO_USER_API_HASH` · `CRYPTO_USER_API_SKCIPHER`. `BT_BREDR` · `BT_LE` · `BT_HCIBTUSB_RTL` · `_BCM` · `_POLL_SYNC`는
default y로 따라온다. 모듈 없는 커널이라 전부 내장이다. `olddefconfig`가 더 켜는 것은 M0이 센다 — 입력 쪽
(`HID_*` · `INPUT_LEDS`)이 바뀌면 UB 결정 4의 음성 검사가 잡는다. `RT2X00`의 교훈(UB 실측 1)대로 부모 메뉴
`BT`를 먼저 켠다.

### 결정 2 — firmware는 계열마다 규칙이 다르다. Intel은 전부, 나머지는 이름이 있는 것

- Realtek — UB 결정 2 그대로. 빌드 뒤 `modules.builtin.modinfo`의 새 `firmware=` 줄 중 `rtl_bt/`를 tarball과 대조해
  있는 것만 넣는다(없는 이름은 머리말의 "뺀 것"에).
- Intel — `intel/ibt-*`를 tarball에서 전부 넣는다(확인 5). `firmware=` 줄로는 못 센다 — iwlwifi처럼 실행 중에
  이름을 만드는 드라이버라 `MODULE_FIRMWARE`는 넷뿐이다. `guest_firmware.sh` 머리말의 iwlwifi 단락 옆에 같은
  성질로 적는다.
- MediaTek — `BT_RAM_CODE_MT7961_1` · `_1a`(MT7921) · `MT7922_1` · `mt7925/MT7925_1`. 우리가 무선을 싣는 칩과 짝이다.
- Qualcomm — `qca/rampatch_usb_*` 7개 · `nvm_usb_*` 31개 전부.

값은 M0의 before/after가 정한다 — initrd 크기 · 부팅의 initramfs 풀기 시간 · `MemAvailable`(WL 실측 9 · 12의 방법).
예상은 gzip 뒤 약 24MB다(위험 1). 1b가 세는 목록은 140 → 약 300이 된다.

### 결정 3 — 사용자 공간은 Debian의 BlueZ와 dbus-daemon을 그대로 들인다

직접 짜지 않는다(`project_write_or_reuse` — BLE HID의 GATT 클라이언트와 SMP 에이전트는 배울 값보다 넓이가
크고, 원하는 모양이 BlueZ와 다르지 않다). D-Bus 데몬도 `dbus-daemon`이다 — `dbus-broker`는 systemd 런처 없이
못 쓴다.

Dockerfile의 sysroot 목록에 더하는 것: `bluez` · `bluez-test-tools` · `dbus-daemon` · `dbus-system-bus-common` ·
`dbus-bin` · 확인 4의 라이브러리 여덟. `guest_tools.sh`에 층 하나(Bluetooth)를 더한다 — `bluetoothd`(자리
`/usr/libexec/bluetooth/`는 그대로) · `bluetoothctl` · `btmgmt` · `dbus-daemon` · `dbus-send`(`dbus-uuidgen`은 실측 5로 뺐다). `btvirt`는
목록에 없다(게이트 전용). `make_initrd.sh`는 `/etc/bluetooth/main.conf` · `input.conf` · `/usr/share/dbus-1/system.conf` ·
`system.d/bluetooth.conf`를 sysroot에서 복사하고, `/etc/passwd` · `group`에 `messagebus`(101)를 더하고,
`/var/lib/bluetooth`를 `/config/bluetooth`로 가는 심볼릭 링크로 만든다 — 페어링 키가 재부팅을 넘는 길이 이
링크 하나다(결정 6).

### 결정 4 — init은 감독 칸 둘을 더한다. `dbus`가 앞, `bluetoothd`가 뒤

감독 목록의 2 · 3번이 `dbus` · `bluetoothd`가 되고 무선 셋은 4 ~ 6, `services.d`는 7부터다(`SLOTS` 13 → 15). 둘 다
WL과 같은 래퍼 스크립트를 띄운다(`kernel/bluetooth/tars-dbus` · `tars-bluetoothd` → initrd의 `/usr/lib/tars/`):

- `tars-dbus` — `mkdir -p /run/dbus`, `exec dbus-daemon --system --nofork --nopidfile`. `exec`이라 PID 1이 쥔 pid가
  곧 dbus-daemon이다.
- `tars-bluetoothd` — `mkdir -p /config/bluetooth`, 시스템 버스 소켓(`/run/dbus/system_bus_socket`)이 생길 때까지
  최대 10초(0.1초 × 100) 기다린 뒤 `exec bluetoothd -n -P sap,network`(실측 5 · 6 — TCG에서 소켓은 2초 뒤에
  생긴다, `-P`는 RFCOMM · BNEP가 없어 투덜대는 플러그인 둘을 끈다). 기다리는 이유는 감독 루프가 두 칸을 같은
  바퀴에 띄우고 `bluetoothd`는 버스가 없으면 바로 죽기 때문이다 — 죽음 · 재시작으로 맞추는 것보다 기다리는 것이
  로그가 깨끗하다. 10초가 지나면 그냥 exec한다(죽고 재시작되는 평소 길).

둘의 이름은 `services.RESERVED`에 들어가 `services.d`의 같은 이름을 막는다. `tars-service restart bluetoothd`가
그대로 된다(CT의 동사 넷). `dbus`를 재시작하면 `bluetoothd`가 버스를 잃고 죽어 감독자가 다시 띄운다 — 위험 7.

### 결정 5 — `tars.conf`에 `bluetooth=off|on`, 기본은 `off`

열셋째 키. 기본이 `off`인 근거는 `net`과 같다 — 라디오를 켜는 것은 이 기계를 쓰는 사람이 정하고, 안 적은
기계는 한 글자도 안 바뀐다. 데몬 둘(약 5MB RAM)과 `/config/bluetooth` 디렉터리가 생기는 것도 비용이다. reload의
갈래는 "데몬 — 지금 바꾼다"(`net`과 같은 묶음)라 `tars-config set bluetooth=on` → `tars-config reload`로 재부팅
없이 켜진다. 넣을지 답하는 함수는 `bluetooth.wants(cfg.bluetooth, mounted)` — `off`면 `bluetooth stays off`,
`/config`가 없으면 `no /config, bluetooth stays off`(키가 살아 있으면 `/config`는 있지만 `tars.noconfig`의 길이
있다), 아니면 `dbus and bluetoothd join the services`. 침묵하지 않는다(DS 결정 1).

### 결정 6 — 페어링은 `bluetoothctl`로 하고 키는 `/config/bluetooth`에 남는다

`tars-config bluetooth …`를 만들지 않는다. `bluetoothctl`이 이미 에이전트 · 스캔 · 페어 · 신뢰 · 연결을 다 하고,
그 위에 앞문을 짜면 그 다섯 낱말을 다른 글자로 옮겨 적는 것뿐이다(`write_or_reuse`). `running-tars.md`에 절을
하나 두어 순서를 적는다 — `tars-config set bluetooth=on` · `tars-config reload` · `bluetoothctl`에서 `scan on` ·
`pair <주소>` · `trust <주소>` · `connect <주소>`. `trust`가 중요하다 — HID 장치는 다음부터 장치 쪽에서 다시
붙는데 신뢰하지 않은 장치의 연결은 `bluetoothd`가 거절한다. 키 · 신뢰는 `bluetoothd`가
`/var/lib/bluetooth/<어댑터>/<장치>/info`에 쓰고 그 자리가 `/config/bluetooth`라 재부팅 뒤에도 같다.

### 결정 7 — 부팅을 절대 안 막는다

`feedback_boot_never_blocks` 그대로다. 두 데몬은 감독 목록의 칸이고 init은 그 결과를 기다리지 않는다. 컨트롤러가
없는 기계에서 `bluetoothd`는 어댑터 0개로 떠 있을 뿐이다. firmware가 없는 칩은 커널 로그에 남고 그 칩만 안 뜬다.

### 결정 8 — 게이트는 스물셋째 체인 `bluetooth/check.sh`다

(M0 뒤에 모양을 정했다 — 처음 적은 것은 "페어링은 후보"였는데 실측 7이 되는 것을 보여 검사로 올렸다.)

게스트 쪽 일은 설정 디스크의 `services.d/bt`(= `bluetooth/bt.sh`)가 하고 체인은 한 글자도 안 친다 — monitor
포트가 없다(audio 부팅 A ~ C와 같다). `btvirt`는 sysroot에서 디스크로 가고 initrd에는 없다.

- 정적(부팅 없음) — 심볼 열하나(`BT` · `BT_BREDR` · `BT_LE` · `BT_HIDP` · `BT_HCIBTUSB` · `_MTK` · `BT_INTEL_PCIE` ·
  `BT_HCIVHCI` · `UHID` · `CRYPTO_USER_API_HASH` · `_SKCIPHER`)이 `=y`, initrd에 데몬 둘 · `bluetoothctl` · `btmgmt` ·
  `dbus-send` · 설정 넷 · 래퍼 둘 · `/var/lib/bluetooth` 링크 · `libglib-2.0`, `/etc/passwd`의 `messagebus`, 래퍼 둘의
  `exec`. firmware는 `tools` 1b가 센다.
- 부팅 A — `bluetooth=on`. init의 `join` 줄과 `started service dbus`가 `bluetoothd`보다 앞(검사 2) · 프로브의 `pgrep`이
  감독자의 pid와 같다(exec, 검사 3) · 커널 줄 일곱과 `/dev/vhci` · `/dev/uhid` · 링크(검사 4) · `btvirt -l2`의
  컨트롤러 둘이 `Powered: yes`이고 `/config/bluetooth/<주소>/settings`가 둘(검사 5) · A가 B를 Just Works로 페어링해
  `Bonded: yes`, `info`에 `[LinkKey]` · LongTermKey · `Trusted=true`(검사 6) · `tars-service restart bluetoothd` 뒤 새
  pid가 컨트롤러 둘과 `Paired: yes`를 안다 — 디스크의 키를 되읽었다(검사 7) · `tars-config set bluetooth=off` + `reload`가
  `bluetooth: on -> off (now)`를 말하고 `reload: service dbus stop` · `bluetoothd stop`, `pgrep`이 비었다(검사 8).
- 부팅 B — 디스크 없음. `bluetooth=off, bluetooth stays off`, 데몬 둘 · 래퍼 줄 · `Bluetooth daemon`이 로그에 없고
  커널 스택 줄은 있다(검사 9, 기본값의 음성).
- mutation 셋 — `CONFIG_BT`를 끄면 검사 1, `bluetooth.wants`가 `.off`를 무시하면 검사 9, `make_initrd.sh`의 링크를 빼면
  검사 1(정적)과 검사 5(`settings`가 `/config`에 안 생긴다).

## 위험

### 위험 1 — initrd가 약 24MB 커진다. 거의 전부 Intel BT firmware다

지금 initrd는 93MB(firmware cpio 45MB). Intel `ibt-*`가 gzip 뒤 20MB로 WL 때 무선 firmware 전체와 맞먹는다. 부팅마다
initramfs 풀기가 늘고(WL 실측 9는 45MB에 0.96초) RAM에 그만큼 남는다(WL 실측 12). M0이 before/after로 재고,
1초를 크게 넘으면 Intel을 TLV 세대(`ibt-0040` 이후, 2020년 이후 칩)로 줄이는 안을 그때 다시 본다. limine BIOS가
100MB대 initrd를 읽는 것은 WL 실측 10(86MB)의 연장이라 M0이 ISO 부팅을 한 번 본다.

### 위험 2 — dbus-daemon이 systemd 없는 자리에서 투덜댈 것

`dbus-daemon --system`은 `/etc/machine-id` 또는 `/var/lib/dbus/machine-id`가 없으면 경고를 내거나(1.12 뒤로 치명적이지는
않다고 기억한다) `GetMachineId`만 실패한다. `libsystemd`는 라이브러리로만 쓴다(journal이 없으면 stderr). M0이
실제 stderr를 본다 — 필요하면 `tars-dbus`가 `dbus-uuidgen --ensure`를 먼저 부른다(그래서 `dbus-uuidgen`을 싣는다).

### 위험 3 — AF_ALG가 없으면 bluetoothd가 조용히 기능을 잃는다

`bt_crypto_new`가 실패하면 GATT DB 해시가 빠지고(BLE 클라이언트가 캐시를 못 쓴다) `btvirt`의 SMP가 안 된다.
결정 1이 둘을 켜지만 M0이 `bluetoothd -d`의 crypto 줄과 `btvirt` 페어링으로 확인한다.

### 위험 4 — BLE HID는 게이트가 못 본다

`btvirt`는 컨트롤러를 흉내 내지 HID 주변 장치를 흉내 내지 않는다. uhid로 입력 장치가 생기는 길은 실기의 몫이다.
게이트가 보는 것은 `/dev/uhid`가 있고 `bluetoothd`가 떴다는 것까지다. 비목표가 아니라 위험으로 적는 이유 — 이
길이 이 서브프로젝트의 목적이고, 실기에서 처음 보는 것임을 HANDOFF에 남긴다.

### 위험 5 — 두 가상 컨트롤러의 페어링이 체인에서 흔들릴 수 있다

`bluetoothctl`은 stdin이 tty가 아니면 줄을 읽고 EOF에 끝나며, `advertise on`은 그 클라이언트가 버스에 붙어 있는
동안만 유효하다. 광고 쪽은 살아 있어야 하므로 fifo로 둘을 띄우는 모양이 된다. M0이 손으로 되는지, 몇 초가
드는지 본다. 흔들리면 체인은 "컨트롤러 등록 · 켜짐 · settings 파일"까지만 보고 페어링은 실기로 넘긴다.

### 위험 6 — Broadcom BT는 firmware 없이 뜬다

`BT_HCIBTUSB_BCM`이 default y로 따라오고 그 칩은 `brcm/BCM*.hcd`를 찾는다. 우리는 brcmfmac 무선을 안 싣듯 이것도
안 싣는다(비목표 4). 그 칩은 패치 없이 ROM firmware로 뜨고 로그에 `Patch brcm/… not found`가 남는다 — 동작은
하되 안정성이 떨어질 수 있다. 실기가 근거를 주면 연다.

### 위험 7 — `dbus`를 재시작하면 `bluetoothd`가 따라 죽는다

`tars-service restart dbus`는 `bluetoothd`의 버스 연결을 끊고 `bluetoothd`는 종료한다. 감독자는 요청하지 않은
죽음으로 세어 다시 띄운다(CT 결정 4). 두 번 안에 끝나므로 "빨리 죽음" 회로차단에 걸리지 않지만 M0이 한 번
본다. 사람이 칠 일은 거의 없다 — 문서에는 `bluetoothd`만 재시작하라고 적는다.

### 위험 8 — 감독 칸이 밀린다

`SLOT_*` 상수가 둘 밀리고 `SLOTS`가 15다. 칸 번호를 아는 자리는 `main.zig` 안의 상수뿐이고 `tars-service`는 이름으로
찾는다 — 그래도 M1에서 `rg 'SLOT_|SLOTS'`로 다 센다. 게이트의 `service` 체인이 칸 수를 세지는 않는다(세면 이
서브프로젝트가 그 수를 고친다).

## 비목표

1. terminal의 키보드 hotplug(여러 키보드 · uevent). 확인 7. 후속 후보 "Keyboard Hotplug"로 HANDOFF에 적는다 —
   이것 없이 BT 키보드는 글자를 못 친다. KH(2026-11-02)가 닫았다.
2. 오디오 — A2DP · HFP · LE Audio. 코덱과 오디오 서버가 필요하다(사용자가 뺐다).
3. 시리얼 · 네트워크 프로필 — RFCOMM · BNEP(PAN) · OBEX.
4. Broadcom firmware(위험 6) · UART · SDIO 전송(`BT_HCIUART` · `BT_HCIBTSDIO`). x86 노트북은 USB · PCIe다.
5. `tars-config bluetooth` 앞문, `input.conf`의 `UserspaceHID` · `ClassicBondedOnly` 조정, `main.conf` 조정. 기본값으로 간다.
6. HID 장치의 배터리(`HID_BATTERY_STRENGTH`). BS design `scope` 행이 이미 그 날을 대비해 둔 자리다.
7. `BT_MSFTEXT` · `BT_AOSPEXT`(광고 모니터 오프로드) · mesh · `BT_DEBUGFS`.
8. 자동 페어링 정책. `bluetoothctl`의 기본 에이전트(Just Works · 숫자 확인)로 간다.
9. MediaTek `MT7902`의 BT firmware — 무선을 안 싣는 칩.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다. 세션 하나에 셋을 다 넣는 것이 목표다(사용자 지시, 2026-11-01).

- BT-M0 — 실측, 코드 0줄. `.config` diff(따라 켜진 것 · 입력 쪽 0), 새 `firmware=` 줄(Realtek), firmware 목록의 크기와
  initrd before/after(위험 1), 부팅 한 번에 데몬 둘을 손으로 띄워 `btvirt` · `bluetoothctl` · `settings` 파일 · 페어링
  후보(위험 5) · dbus의 stderr(위험 2) · crypto(위험 3) · `dbus` 재시작(위험 7).
- BT-M1 — 커널 config · firmware 목록 · Dockerfile · `guest_tools.sh` · `make_initrd.sh` · 래퍼 둘 · init(키 · 칸 둘 ·
  reload · 호스트 검사) · `tars-config`의 열셋 · `running-tars.md`.
- BT-M2 — 체인 `bluetooth/check.sh`, mutation 셋, 루트 게이트(23체인), 문서 닫기(확인 8의 자리 · completed · 소개
  페이지 · decisions · HANDOFF).

## 실측 (M0, 2026-11-01 ~ 11-02)

plan은 `plans/2026-11-01-tars-bluetooth-bt-m0.md`. 하네스는 세션 scratchpad의 `bt/`. 기준선은 KU-M1 닫기 뒤의 빌드
(bzImage 8,983,552 · initrd 93,380,191바이트). 컨테이너 이미지는 아직 옛것이라 BlueZ · D-Bus는 설정 디스크에 실어
`LD_LIBRARY_PATH`로 띄웠다 — `services.d/bt`가 WL의 `ap.sh`처럼 콘솔에 `bt-m0:` 줄을 찍었다. 부팅 다섯 번.

### 실측 1 — 아홉을 켜면 71줄이 바뀌고 입력 쪽은 안 움직인다

`scripts/config -k --enable`로 아홉을 켠 뒤 빌드 43초(증분, `net/bluetooth` · `drivers/bluetooth`가 새로). 해소된
`build/.config`에 아홉이 전부 `=y`. 기준선 대비 diff 71줄 — 따라 켜진 것은 `BT_BREDR` · `BT_LE` · `BT_LE_L2CAP_ECRED` ·
`BT_INTEL` · `BT_BCM` · `BT_RTL` · `BT_MTK` · `BT_HCIBTUSB_POLL_SYNC` · `_BCM` · `_RTL`, 암호 쪽 `CRYPTO_ECDH` · `ECC` · `KPP` ·
`HMAC` · `SHA512` · `SHA3` · `DRBG(_MENU · _HMAC)` · `JITTERENTROPY` · `RNG(_DEFAULT)` · `CRYPTO_USER_API` ·
`_ENABLE_OBSOLETE` · `LIB_SHA512(_ARCH)` · `CRC16`. `not set`으로 새로 적힌 것은 `BT_RFCOMM` · `BT_BNEP` · `BT_LEDS` ·
`BT_MSFTEXT` · `BT_AOSPEXT` · `BT_FEATURE_DEBUG` · `BT_HCIBTUSB_AUTOSUSPEND` · `BT_HCIUART` · `BT_HCIBCM203X` ·
`BT_HCIBCM4377` · `BT_HCIBFUSB` · `BT_MRVL` · `BT_ATH3K` · `BT_VIRTIO` · 그리고 `HID_NVIDIA_SHIELD`(`BT`에 기대는
심볼이라 처음 보인 것 — 입력 쪽의 변화가 아니다). `HID_` · `INPUT_LEDS` · `LEDS_`의 값은 하나도 안 바뀌었다.
bzImage 8,983,552 → 9,335,808(+352,256). `.config`는 `project_kernel_config`대로 해소된 모양으로 되접어 고정점임을
확인했다(두 번째 빌드의 diff 0).

### 실측 2 — Realtek은 `MODULE_FIRMWARE`가 아니라 칩 표가 진짜 목록이다. Intel은 넷뿐이다

`firmware=` 줄 132 → 194(+62: `rtl_bt/` 50 · `mediatek/` 8 · `intel/` 4). 그런데 tarball에는 `rtl_bt/rtl8192ee_fw.bin` ·
`rtl8192eu_fw.bin` · `rtl8812ae_fw.bin`이 있는데 50줄에 없다 — `btrtl.c`의 `ic_id_table`(`fw_name` · `cfg_name`)을 다시
세니 이름이 50이고 `MODULE_FIRMWARE` 50줄과 같은 집합이었다. 즉 셋은 6.18이 요청하지 않는 파일이다(뺐다). 50 중 19는
이 릴리스에 없다(거의 `*_config.bin` — 드라이버는 config가 없으면 넘어간다, 그리고 `rtl8852bs_*` · `rtl8723ds_*`
같은 SDIO 칩) → 31을 넣는다. MediaTek 8 중 `mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin`은 tarball에 없다(KU-M1 plan
확정 5의 그 이름) — 무선도 안 싣는 칩이라 함께 뺐다. 목록은 157줄 — Intel 84 · Realtek 31 · MediaTek 4 · Qualcomm 38,
`GUEST_FIRMWARE` 140 → 297.

함정 하나. 목록을 만드는 셸이 zsh였고 `"$n:lib/…"`의 `:l`이 zsh의 소문자 변환 수식어라 157줄이 전부 깨진 채
들어갔다(`…binib/firmware/…`). `vendor_firmware.sh`의 `tar`가 "Not found in archive"로 죽어 바로 드러났다. `${n}:lib`로
고쳤다 — 이 저장소의 셸 작업은 zsh라 `$var:` 뒤에 글자가 오면 중괄호를 쓴다.

### 실측 3 — initrd는 23.2MB 커지고 풀기는 0.48초 늘고 RAM은 약 31MB 줄어든다(위험 1)

| | 기준선 | BT 뒤 | 차 |
|---|---|---|---|
| firmware cpio의 원본 합 | — | 68,618,738 (297개) | |
| `initrd.cpio` | 93,380,191 | 116,568,247 | +23,188,056 |
| `Freeing initrd memory` | 91,192K @ 3.32s | 113,840K @ 3.80s | +22.1MB, +0.48s |
| `MemAvailable`(부팅 뒤 5초, 512MiB) | 195,856 kB | 162,408 ~ 165,264 kB | −31 ~ 33MB |

예상(약 24MB)과 맞는다. 0.48초는 WL 실측 9(0.96초)의 절반이고 받아들인다 — 결정 2는 그대로다. 512MiB 게이트
게스트의 여유는 아직 160MB대라 `GUEST_MEM`을 안 올린다.

### 실측 4 — 커널 줄 일곱, `/dev/vhci` · `/dev/uhid`

부팅마다 0.4초에 `Bluetooth: Core ver 2.22` · `HCI device and connection manager initialized` · `HCI socket layer
initialized` · `L2CAP socket layer initialized` · `SCO socket layer initialized`, 0.84초에 `HIDP (Human Interface
Emulation) ver 1.2` · `HIDP socket layer initialized`. 컨트롤러가 생기면 `Bluetooth: MGMT ver 1.23`이 컨트롤러마다
한 줄. `/dev/vhci`와 `/dev/uhid`는 부팅 직후 있다. 체인의 커널 쪽 판정은 이 줄들이다.

### 실측 5 — dbus-daemon은 2초 뒤에 소켓을 내고, machine-id 없이 뜬다(위험 2 닫음)

`--system`과 `--config-file`을 함께 주면 "--config-file specified but configuration file … already requested"로 안
뜬다(첫 판의 실패 — `--system`이 곧 그 파일이다). `/usr/share/dbus-1/system.conf`를 제자리에 두고 `--system --nofork
--nopidfile`만 주면 소켓이 약 2.0초 뒤(0.1초 × 20) 생긴다 — TCG의 값이다. stderr는 `Cannot initialize inotify: Function
not implemented` 한 줄(커널에 `INOTIFY_USER`가 없다, 설정 감시만 포기한다). `/etc/machine-id`가 없어도 `GetId`가
답한다(dbus 1.16은 제 안에서 짓는다) — `dbus-uuidgen`은 안 싣는다. `tars-bluetoothd`의 대기는 10초로 넉넉히 둔다.

### 실측 6 — bluetoothd는 떴고, 투덜대는 둘은 `-P sap,network`로 끈다(위험 3 닫음)

`bluetoothd -n`: `Bluetooth daemon 5.82` · `Starting SDP server` · `Bluetooth management interface 1.23 initialized`.
그리고 `profiles/network/bnep.c: kernel lacks bnep-protocol support`와 어댑터마다 `sap-server: Operation not permitted`
(RFCOMM이 없다) — `-P sap,network`로 둘 다 사라졌다(`Excluding (cli) sap` · `network`). AF_ALG 쪽 경고는 없었고
실측 7의 페어링(SMP)이 됐으므로 위험 3은 닫는다. `btvirt -l2`가 hci0(`00:AA:01:00:00:00`) · hci1(`00:AA:01:01:00:01`)을
만들고 `bluetoothctl list`에 둘, `show`가 `Powered: yes`(AutoEnable) · `Pairable: no`. 두 어댑터의 `settings`가
`/config/bluetooth/<주소>/settings`에 바로 생겼다 — `/var/lib/bluetooth` 링크가 산다(결정 6).

### 실측 7 — 두 가상 컨트롤러가 페어링되고 키가 `/config`에 남는다(위험 5 닫음, 결정 8에 넣는다)

길 셋을 견줬다. (1) fifo로 stdin을 주는 `bluetoothctl`은 아무 명령도 안 받은 것처럼 보였는데, 실은 stdout이 tty가
아니면 전부 버퍼링해 끝날 때까지 한 줄도 안 쓴 것이었다 — 파일로 받고 `quit` 뒤에 읽으면 된다. (2) `btmgmt`는
stdin이 `/dev/null`이면 명령 뒤에 안 끝나고 멈춘다(두 번 걸렸다) — 체인에서 안 쓴다. (3) 파이프 둘. B 쪽
`( … echo "agent off"; echo "select B"; echo "pairable on"; echo "discoverable on"; echo "advertise on"; sleep 70 ) |
bluetoothctl`과 A 쪽 `( … echo "agent NoInputNoOutput"; echo "default-agent"; echo "scan on"; sleep 8; echo "pair B";
sleep 15; echo "trust B"; echo "info B"; echo quit ) | bluetoothctl`. 에이전트는 하나(A 쪽, NoInputNoOutput → Just
Works)여야 한다 — 둘이면 확인 질문이 어디로 갈지 모른다. 결과: `[NEW] Device 00:AA:01:00:00:00` → `Connected: yes` →
`Bonded: yes`, B 쪽은 `Advertising object registered`. `/config/bluetooth/<A>/<B>/info`에 `[LinkKey]` ·
`[PeripheralLongTermKey]` · `[LocalSignatureKey]` · `Trusted=true`, 양쪽에 `cache/`와 `attributes`. 전체 40초인데 대부분
`sleep`이다 — 체인은 광고 2초 · 스캔 8초 · 페어 15초로 간다.

### 실측 8 — dbus를 죽이면 bluetoothd는 `Stopping SDP server` · `Exit`로 깨끗이 끝난다(위험 7)

감독자가 다시 띄울 것이고 두 번 안에 끝난다. 사람은 `tars-service restart bluetoothd`만 친다(문서에 그렇게 적었다).

### 실측 9 — Debian 패키지는 그대로 들어온다

`bluez 5.82-1.1` · `bluez-test-tools 5.82-1.1` · `dbus-daemon 1.16.2-2` · `dbus-system-bus-common 1.16.2-2` · `dbus-bin
1.16.2-2`와 라이브러리 여덟을 Dockerfile에 더해 이미지를 다시 구웠다(태그 `ee4aa97122b5`, 35초 — 레이어 캐시가
살아 있었다). sysroot에 `/usr/libexec/bluetooth/bluetoothd` · `/usr/bin/btvirt` · `/usr/bin/dbus-daemon`이 있다.

## 실측 (M2, 2026-11-02)

### 실측 10 — 체인은 네 번째 판에 초록이다. 앞 세 판의 빨강은 전부 체인 자신의 셈이었다

| 판 | 멈춘 곳 | 이유 |
|---|---|---|
| 1 | 검사 1 | `gzip -dc initrd \| cpio -i --to-stdout etc/passwd \| grep`을 `if` 안에 두었다. initrd 뒤에 firmware cpio가 이어 붙어 있어 cpio가 첫 archive 끝에서 멈추면 gzip이 EPIPE로 죽고 pipefail이 그것을 빨강으로 올린다. 파일에 받고 따로 본다 |
| 2 | 검사 6 | `Bonded: yes`가 pair의 `[CHG]` 줄과 `info`의 줄로 두 번 나온다 — "1 bonded"가 아니라 "하나 이상" |
| 3 | 검사 7 | 재시작 뒤 `bluetoothctl info B`가 빈 답. bluetoothctl의 기본 어댑터가 부팅마다 · 재시작마다 다를 수 있어 B를 아는 어댑터(A)를 `select`해야 한다 — 한 줄 명령은 select를 못 하므로 파이프로 |
| 4 | — | PASS, 3분 18초(빌드 건너뜀 · 부팅 둘) |

페어링의 방향도 부팅마다 다르다 — 어느 가상 컨트롤러가 `[default]`가 되는지가 바뀐다(판 4는 `00:AA:01:00:00:00`이 A였다).
체인은 `list`의 첫 줄을 A로 삼으므로 상관없다.

### 실측 11 — mutation 셋은 잡히되, 둘째는 예측한 자리가 아니다

| mutation | 예측 | 잡은 곳 |
|---|---|---|
| `CONFIG_BT=y` → not set | 검사 1 | 검사 1 `CONFIG_BT=y is missing from kernel/.config`(부팅 0회) |
| `make_initrd.sh`의 링크 줄 제거 | 검사 1 | 검사 1 `initrd has no var/lib/bluetooth`(부팅 0회) |
| `bluetooth.wants`가 `.off`를 무시 | 검사 9 | 호스트 `bluetooth_test`가 먼저(`off, mounted — got true, want false`). 체인에서는 검사 8 `init did not stop service dbus on reload` — 부팅 A의 끄기에서 reload가 `.off`를 보고도 데몬을 안 내린다. 부팅 B(검사 9)까지 못 간다 |

둘째의 첫 시도는 `if (bt == .off)` 블록을 통째로 지운 것이었는데 Zig가 `unused function parameter`로 컴파일을 막아
체인의 `zig build`에서 멈췄다 — 그것은 mutation이 아니라 문법 오류다. `bt == .on and bt == .off`(항상 거짓)로 다시 했다.
reload가 부팅과 같은 `wants`를 쓰므로 끄기가 먼저 걸린다는 것은 설계의 결과다 — 검사 8과 9가 같은 함수를 두 자리에서 본다.

### 실측 12 — 루트 게이트는 첫 판에 23/23이다

`docker run … bash check.sh`, 10분 25초(prebuild 약 310초 + lanes 315초). 23체인 전부 1/1, verify 8208줄 전부 통과(BT 체인은 verify 8줄 — 부팅 둘의 첫 프레임뿐이다). BT 체인의 lane은 68줄을 끼어든 줄로 셌는데(`bt-probe:` 줄이 커널 printk와 섞인다) 판정에는 안 걸린다. 로그는 `out/gate-logs/20261101-160733`.
