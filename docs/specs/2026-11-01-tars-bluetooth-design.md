# TARS Bluetooth — Design

접두사: BT

Status: 진행 중(2026-11-01) — M0부터.

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
| Intel | `btintel.c` | `intel/ibt-<hw>-<rev>.sfi` · `.ddc`(ROM 세대는 `ibt-hw-37.7/37.8*.bseq`). `MODULE_FIRMWARE`는 넷뿐, 나머지는 `snprintf` | 28,169,921 (91개) | 19,951,194 |
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
`/usr/libexec/bluetooth/`는 그대로) · `bluetoothctl` · `btmgmt` · `dbus-daemon` · `dbus-send` · `dbus-uuidgen`. `btvirt`는
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
  최대 5초(0.1초 × 50) 기다린 뒤 `exec bluetoothd -n`. 기다리는 이유는 감독 루프가 두 칸을 같은 바퀴에 띄우고
  `bluetoothd`는 버스가 없으면 바로 죽기 때문이다 — 죽음 · 재시작으로 맞추는 것보다 기다리는 것이 로그가
  깨끗하다. 5초가 지나면 그냥 exec한다(죽고 재시작되는 평소 길).

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

- 정적(부팅 없음) — 확인 1의 심볼 아홉이 `=y`, initrd에 데몬 둘 · `bluetoothctl` · 설정 파일 넷 · `messagebus` 줄 ·
  `/var/lib/bluetooth` 링크가 있다. firmware는 1b가 센다.
- 부팅 A — 설정 디스크에 `bluetooth=on`과 `btvirt`(sysroot에서), 그리고 가상 컨트롤러를 띄우고 `bluetoothctl`을
  모는 스크립트(`bluetooth/bt.sh`, `services.d`가 아니라 셸에서 친다). 판정: init의 `join` 줄 · 감독자의 `started
  service dbus` · `started service bluetoothd` · 커널의 `Bluetooth: HIDP (Human Interface Emulation)` 줄 ·
  `/dev/uhid` 존재 · `btvirt` 뒤 `bluetoothctl list`에 컨트롤러 · `show`의 `Powered: yes`(AutoEnable) ·
  `/config/bluetooth/<주소>/settings`가 생겼다(링크가 산다) · `tars-service restart bluetoothd` 뒤 복귀 ·
  `tars-config set bluetooth=off` + `reload`로 둘이 내려간다.
- 부팅 A의 후보 — 두 가상 컨트롤러 사이의 LE 페어링(`btvirt -l2`, 한쪽 `advertise on` · 다른 쪽 `scan on` · `pair`).
  되면 `/config/bluetooth/<A>/<B>/info`의 `[LongTermKey]`가 "페어링 키가 디스크에 남는다"를 글자로 증명한다. M0이
  손으로 먼저 해 보고 되는 만큼만 체인에 넣는다(위험 5).
- 부팅 B — 디스크 없음. `bluetooth stays off`, 데몬 둘은 `config_off`, `bluetoothd`가 로그에 없다(기본값의 음성).
- mutation 셋 — `CONFIG_BT`를 끄면 정적 검사, `wants`가 `off`를 무시하면 부팅 B, 링크를 빼면 `settings`가
  `/config`에 안 생긴다.

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
   이것 없이 BT 키보드는 글자를 못 친다.
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
