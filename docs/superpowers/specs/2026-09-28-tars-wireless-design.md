# TARS Wireless — Design

접두사: WL

Status: 진행 중(2026-09-28) — M0~M2 끝, 실측 1~13. 결정 4를 실측 5로 고쳤다(`-M`이 없다).

관련 문서: `2026-09-26-tars-wired-nic-design.md`(WN. 이 사이클이 그 비목표 2를 목표로
옮긴다) · `2026-09-27-tars-daemon-supervision-design.md`(DS. 데몬을 감독 목록에 넣는
모양) · `2026-09-09-tars-real-machine-design.md`(RM. 실기 커널) ·
`docs/decisions/project_wired_nic.md` · `docs/decisions/project_daemon_supervision.md` ·
`docs/decisions/project_target_hardware.md` · `docs/decisions/feedback_boot_never_blocks.md`.

## 한 줄 요약

`/config/wpa_supplicant.conf`가 있으면 노트북의 내장 무선(Intel · Realtek · MediaTek ·
Qualcomm)이 AP에 붙고, dhcpcd가 지금처럼 주소를 받는다. 우리 코드는 wpa_supplicant를
감독 목록에 넣는 데까지다. 연결은 wpa_supplicant가, 주소는 dhcpcd가 한다.

## 왜 지금인가

2026-09-27에 사용자가 후보(IPv6 · 패키지 매니저 · 무선 NIC · 이월 숙제) 중 무선을
골랐다. 대상 하드웨어에 노트북이 들어 있는데(`project_target_hardware`) 노트북에서
유선 포트가 있는 경우가 점점 드물다 — 무선이 없으면 NW부터 DS까지 네트워크를 쓰는
기능 전부가 USB 동글 없이는 꺼져 있다.

사용자가 정한 셋 — 드라이버는 노트북형으로 넓게(Intel · Realtek · MediaTek ·
Qualcomm), 자격 증명은 wpa_supplicant의 원래 형식 파일, wpa_supplicant는 `init`이
감독한다(접근 A). 2026-09-28에 사용자가 나머지 결정을 전부 위임했다 — 아래에서 그
뒤에 정한 것은 Claude가 정한 것이다.

## 착수 전에 읽은 것 — 부팅은 한 번도 안 했다

### 확인 1 — 무선 스택의 바닥이 꺼져 있다

`kernel/.config`에 `CONFIG_WIRELESS=y`와 `CONFIG_WLAN=y`(벤더 메뉴만)는 있지만
`CFG80211` · `RFKILL`이 꺼져 있다. 드라이버는 하나도 없다. `FW_LOADER=y`이고
`EXTRA_FIRMWARE=""`다.

### 확인 2 — 모듈이 없다

`# CONFIG_MODULES is not set`. 켜는 것은 전부 `=y`로 커널에 박힌다. 게이트만 쓰는
드라이버(hwsim)도 제품 커널에 들어간다.

### 확인 3 — 우리가 새로 채울 칸은 둘이다

WN이 dhcpcd를 manager mode로 띄워서 인터페이스를 dhcpcd가 고른다 — 나중에 생긴
장치도 잡는다(WN 실측). 무선 인터페이스는 AP에 붙기 전까지 carrier가 없고, 붙으면
carrier가 선다. 그러면 dhcpcd가 할 일은 이미 되어 있다. 새로 채울 칸은 커널 드라이버와
firmware, 그리고 연결을 맡는 데몬과 그 설정이다.

### 확인 4 — QEMU에는 무선 장치가 없다. 커널에 가짜 라디오가 있다

`mac80211_hwsim`은 mac80211 위의 가짜 라디오다. firmware가 필요 없고, 라디오끼리
커널 안에서 프레임을 주고받는다. 라디오 하나에 hostapd로 AP를 띄우고 다른 하나에
wpa_supplicant를 붙이면 연결 → carrier → DHCP가 게스트 안에서 닫힌다. 기본값은 라디오
둘이다.

## 결정

### 결정 1 — 커널은 무선 스택과 네 계열의 PCIe 드라이버를 켠다

`CFG80211` · `MAC80211` · `RFKILL`과 Intel(`IWLWIFI` · `IWLMVM` · `IWLMLD`) ·
Realtek(`RTW88`/`RTW89`의 PCIe 칩) · MediaTek(`MT7921E` · `MT7925E`) ·
Qualcomm(`ATH11K_PCI` · `ATH12K`). 정확한 심볼은 M0이 커널 6.18의 Kconfig를 읽고
정한다. 켠 목록 밖의 벤더 메뉴(`WLAN_VENDOR_*`)는 끈다 — 켜 둔 메뉴가 `olddefconfig`에서
무엇을 끌어오는지 매번 볼 필요가 없게.

### 결정 2 — hwsim은 기본이 라디오 0개다

`MAC80211_HWSIM=y`와 `CONFIG_CMDLINE="mac80211_hwsim.radios=0"`. wifi 체인만 부트로더
cmdline에 `mac80211_hwsim.radios=2`를 덧붙인다. 제품 부팅에 가짜 `wlan`이 생기면
wpa_supplicant와 dhcpcd가 그것을 붙잡는다. 모듈이 없어서 제품과 게이트가 같은 커널을
쓰려면 이 길뿐이다. 같은 param이 두 번 오면 뒤의 것이 이기는지는 M0이 잰다(위험 3).

### 결정 3 — firmware는 linux-firmware 릴리스 하나를 sha256으로 고정해서 고른다

kernel.org의 linux-firmware 릴리스 tarball 하나를 받아 sha256을 확인하고(unifont의
`terminal/vendor_fonts.sh`와 같은 방식), 네 계열에 필요한 파일만 initrd의
`/lib/firmware`에 넣는다. Debian bookworm의 firmware 패키지는 커널 6.18보다 낡아서
드라이버가 찾는 파일 이름이 없을 수 있다 — M0이 확인한다. 목록은 한 파일에 두고
(`guest_tools.sh`처럼 데이터만), 체인이 그 파일을 source해서 initrd 안에 있는지 센다.
`regulatory.db`(+`.p7s`)도 함께 넣는다. 없으면 규제 도메인이 world(`00`)로 남아
5GHz 대부분에서 능동 스캔을 못 한다.

### 결정 4 — `init`은 파일이 있으면 `tars-wifi`를 감독한다. 늦은 인터페이스는 hook이 넣는다

(M0 뒤에 고쳤다. 처음에는 wpa_supplicant `-M -i 'wlan*'`이었는데 Debian 빌드에 `-M`이
없다 — 실측 5.)

`/config/wpa_supplicant.conf`가 있고 `net`이 `off`가 아니면 `Kind.service`로 목록에
넣는다. label은 `service wpa_supplicant`, 자리는 dhcpcd 앞이다. 넣지 않을 때는 이유를
한 줄 남긴다(DS 결정 1). `services.d`의 같은 이름은 건너뛴다(DS 결정 5).

path는 initrd의 셸 스크립트 `/usr/lib/tars/tars-wifi`다. 이 스크립트는 뜰 때
`/sys/class/net/*/phy80211`로 지금 있는 무선 인터페이스를 세고
`wpa_supplicant -g /run/wpa_supplicant/global -O /run/wpa_supplicant -c <파일> -i wlan0 -N -c <파일> -i wlan1 …`을
`exec`한다. 하나도 없으면 `-g` · `-O`만으로 뜬다(실측 7). `exec`이라서 PID 1이 쥔 pid가 곧
wpa_supplicant다(DS 결정 2의 교훈). 재시작될 때 다시 세므로 인터페이스를 잃지 않는다.

그 뒤에 생긴 인터페이스는 dhcpcd hook `10-tars-wifi`가 넣는다. dhcpcd는 새 인터페이스마다
hook을 `reason=PREINIT`으로 부르고 무선이면 `ifwireless=1`을 준다(실측 7). hook은
`wpa_cli -g … interface_add <iface> <파일>`을 부른다. 이미 있는 인터페이스면 `FAIL`이고
기존 연결은 그대로다(실측 6). 부팅 직후에는 global 소켓이 아직 없을 수 있어서(실측 7),
소켓에 못 닿았을 때만 배경에서 몇 초 다시 시도한다 — dhcpcd를 붙잡지 않는다.

`-O`는 사람의 파일에 `ctrl_interface` 줄이 없어도 `wpa_cli`가 닿게 하려는 것이다.

`net=off`에서 안 넣는 이유 — 주소를 받을 dhcpcd가 없고 hook도 안 돈다. 연결만 서는 것은
사람이 볼 때 "붙었는데 안 된다"다.

### 결정 5 — 게스트 도구는 넷이다

`wpa_supplicant` · `wpa_cli` · `wpa_passphrase` · `iw`. 새 라이브러리는 다섯이다(실측 4).
hostapd와 busybox(udhcpd · nc)는 sysroot에만 들이고 initrd에는 안 넣는다 — 게이트의
설정 디스크가 가져간다. 사람의 첫 설정은
`wpa_passphrase SSID 비밀번호 > /config/wpa_supplicant.conf` 다음 재부팅이다.
`docs/guides/running-tars.md`에 적는다.

### 결정 6 — 부팅을 절대 안 막는다

`feedback_boot_never_blocks` 그대로다. wpa_supplicant는 감독 목록의 한 칸이고 `init`은
기다리지 않는다. 파일이 틀려 곧 죽으면 감독자의 backoff와 포기 규칙이 다룬다.

### 결정 7 — 게이트는 열일곱번째 체인 `wifi/check.sh`다

- 양성 부팅 — `radios=2`. 둘째 라디오를 별도 network namespace로 옮기고 그 안에서
  hostapd(WPA2)와 DHCP 서버를 띄운다. 그러면 제품의 wpa_supplicant `-M`과 dhcpcd가 AP
  쪽 인터페이스를 못 보고, 패킷이 커널의 로컬 지름길이 아니라 무선 경로를 탄다.
  hostapd · netns 도구 · DHCP 서버는 설정 디스크로만 들어간다. 판정은
  `wpa_state=COMPLETED` · `wlan0: leased` · AP 쪽으로 가는 TCP 왕복이다.
- 음성 — 비밀번호가 틀리면 연결이 안 서고 부팅은 끝난다. 파일이 없으면 wpa_supplicant가
  안 떴다는 줄이 나온다. 다른 체인의 부팅에는 `wlan`이 없다(결정 2).
- 정적 — firmware 목록의 파일이 initrd에 전부 있다.
- 반사실 — `-M`을 빼거나 `radios=0`을 빼면 예측한 검사가 빨개진다.

netns · hostapd · DHCP 서버를 정확히 무엇으로 하는지는 M0이 잰다.

## 위험

### 위험 1 — initrd가 커지고 게이트의 모든 부팅이 그것을 푼다

firmware는 파일 하나가 수백 KB에서 수 MB다. DC가 TCG에서 initramfs 풀기가 느리다는
것을 이미 쟀다. M0이 크기와 부팅당 시간을 잰다. 너무 크면 firmware만 ISO · ESP에 따로
두는 길을 그때 연다.

### 위험 2 — Debian 빌드에 `-M`이 없을 수 있다 (M0에서 현실이 됐다)

`-M`은 `CONFIG_MATCH_IFACE`로 빌드해야 생기고 Debian은 안 켰다(실측 5). 결정 4를 wrapper와
hook으로 고쳤다. 부팅 뒤에 생기는 인터페이스도 hook이 잡으므로 잃은 것은 없다.

### 위험 3 — 커널 param이 두 번 오면 뒤의 것이 이긴다는 것은 짐작이다

M0이 잰다. 틀리면 결정 2를 다시 본다.

### 위험 4 — 게이트는 실칩의 probe와 firmware 로딩을 못 본다

RM · WN과 같은 반쪽 판정이다. 파일이 initrd에 있는지만 본다.

### 위험 5 — firmware가 게스트 RAM에 남는다

initramfs는 RAM이다. firmware 96MB(풀린 크기)가 부팅 내내 메모리에 있다. 게이트의 게스트는
512MB다(`GUEST_MEM`). M1이 쟀다 — `MemAvailable` 309MB → 213MB(실측 12). 루트 게이트가
메모리 부족으로 흔들리면 여기로 돌아온다.

### 위험 6 — 시작하는 동안 명령줄 인터페이스가 사라지면 wpa_supplicant가 죽는다

`-i`로 받은 인터페이스를 초기화하는 중에 사라지면 `Failed to initialize driver interface`로
status 255다(실측 13). 다 잡은 뒤에 사라지는 것(동글을 뽑는 것)은 같은 pid로 산다.
앞의 경우도 감독자가 1초 뒤 되살리고 `tars-wifi`가 다시 세므로 제자리로 온다 — 다만
빨리 죽음 하나로 센다.

## 비목표

1. 실기 판정. 실기가 생기면 연다.
2. 파일 없이 부팅 뒤에 네트워크를 고르는 UI.
3. WPA-Enterprise(802.1X).
4. 제품 쪽의 AP 모드.
5. Broadcom · 그 밖의 벤더. USB · SDIO 무선 칩(드라이버를 안 켰다).
8. 커널 6.18이 받는 번호의 firmware가 이 릴리스에 없는 Intel 칩 둘(`bz-b0-wh-b0` = BE201,
   `sc-a0-fm-c0`) — 실측 3. 커널을 올리는 날 같이 본다.
9. 보드별 변형 firmware(ath11k `nfa765` · ath12k `ncm865`).
6. 여러 NIC 사이의 route 우선순위. dhcpcd 기본값이다.
7. IPv6.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- WL-M0 — 실측, 코드 0줄. 위험 1~3, firmware 파일 목록, netns · hostapd 게이트가 서는가.
- WL-M1 — 커널 config, firmware를 initrd에 넣기, 정적 검사.
- WL-M2 — `init`과 게스트 도구.
- WL-M3 — 체인 · 반사실 · 가이드 · 루트 게이트 · 닫기.

## 실측 (M0, 2026-09-28)

하네스는 `/tmp/wl/`이고 저장소에 안 들어갔다. 작업 트리의 `kernel/.config`에 심볼을 켜고
`kernel/build.sh`로 빌드했다. 게스트에 넣을 것은 initrd 뒤에 cpio를 이어 붙여 넣었다 —
커널은 이어 붙인 cpio를 차례로 풀고 뒤의 것이 앞의 것을 덮는다. 탐침은 설정 디스크의
`services.d/probe`로 돌렸다(타이핑이 없다).

### 실측 1 — `olddefconfig`는 115줄을 켜고 아무것도 안 끈다

스물다섯 심볼이 전부 `=y`로 남았다. 끌려온 것 중 셋이 눈에 띈다. `CONFIG_CRYPTO=y` —
이 커널에는 crypto 층이 통째로 없었다. WPA2의 CCMP와 관리 프레임 보호를 mac80211이
소프트웨어로 하므로 `CCM` · `GCM` · `CMAC` · `AES`가 온다. `KEYS` · `X509` · `PKCS7` —
`CFG80211_REQUIRE_SIGNED_REGDB`가 `regulatory.db.p7s`를 검증하려고 끌고 온다. `MHI_BUS` ·
`QRTR` — ath11k/ath12k가 칩과 대화하는 버스다. 지워진 13줄은 "is not set" 주석과 머리
주석뿐이다. bzImage는 5.0M → 7.3M.

### 실측 2 — 내장 cmdline 뒤에 부트로더 cmdline이 붙고 뒤의 값이 이긴다

`Kernel command line: mac80211_hwsim.radios=0 console=ttyS0 mac80211_hwsim.radios=2`에서
라디오 둘(`phy0 phy1`, `wlan0 wlan1`)이 생겼다. `radios=0`만 있으면 없다. 위험 3은 짐작이
맞았다. 라디오가 0이어도 `hwsim0`(type 803 = `ARPHRD_IEEE80211_RADIOTAP`)은 늘 생긴다 —
`phy80211`이 없고 dhcpcd가 건드리지 않는다.

### 실측 3 — firmware 파일은 빌드 산출물이 말해 준다. iwlwifi는 요청 순서를 따라 고른다

`kernel/build/modules.builtin.modinfo`의 `firmware=` 줄이 드라이버가 찾는 이름이다(108줄,
그중 `r8169` · `r8152` 33줄은 WN 비목표 1). iwlwifi는 실행 중에 칩의 MAC · stepping · RF로
접두사를 만들고(`iwl_drv_get_fwname_pre`) 커널의 최대 API부터 아래로 내려가며 요청한다.
`c99` 다음은 `101`이다(`iwl_request_firmware`). 그래서 linux-firmware의 `c101`~`c107`은
6.18이 절대 요청하지 않는다 — "가장 새 파일"을 넣으면 안 되는 파일만 넣는다. 접두사마다
(MAC, RF)의 최대치에서 처음 만나는 실제 파일 하나를 골랐다: 39개(`.pnvm` 포함).
BE201(`bz-b0-wh-b0`)과 `sc-a0-fm-c0`은 받을 번호의 파일이 없다(비목표 8).

iwlwifi 파일은 tarball 안에서 `intel/iwlwifi/`에 있고 드라이버는 `/lib/firmware/` 맨 위를
찾는다. 둘을 잇는 것이 `WHENCE`의 `Link:` 줄이고 tarball에는 링크가 없다. ath11k
`WCN6855/hw2.1`도 `hw2.0`을 가리키는 `Link:`다. 그래서 목록은 "tarball 안 경로 : initrd
안 경로"의 쌍이다.

`regulatory.db`는 linux-firmware에 없다. wireless-regdb 릴리스가 따로 있다.

크기(gzip -6): Intel 18.3MB · ath11k 4.9 · rtw89 4.2 · ath12k 3.5 · MediaTek 3.4 · rtw88 0.3,
합쳐 cpio 38.7MB. 풀면 96MB(ath11k `hw2.1` 사본 포함). 고정한 릴리스는
`linux-firmware-20260916.tar.xz`(662MB, sha256 `f80dcb75…90ccc5`)와
`wireless-regdb-2026.09.03.tar.xz`(sha256 `b22e0901…4cbf58d`). 둘 다 kernel.org의
`sha256sums.asc`와 맞았다.

### 실측 4 — 새 라이브러리는 다섯이다

재귀 `DT_NEEDED`(`project_measuring_tool_cost`). wpa_supplicant 3.4MB가 `libnl-3` ·
`libnl-genl-3` · `libnl-route-3` · `libpcsclite1` · `libdbus-1-3`(합 1.1MB)을 새로 부른다.
dbus는 라이브러리뿐이고 데몬은 `-u`를 줄 때만 필요하다. `iw`는 libnl 둘, `wpa_cli`는
readline, `wpa_passphrase`는 libcrypto. hostapd는 wpa_supplicant의 부분집합이고 busybox는
libc와 libresolv.

### 실측 5 — Debian의 wpa_supplicant 2.10에는 `-M`이 없다

도움말에 `-N`(새 인터페이스 기술)과 `-O`는 있고 `-M`은 없다. 결정 4를 고쳤다.

### 실측 6 — hwsim 위에서 제품 경로가 끝까지 선다

`net=dhcp` 부팅. `phy1`을 netns `ap`로 옮기고(`iw phy phy1 set netns name ap`) 그 안에서
hostapd(WPA2-PSK, 채널 1)와 busybox udhcpd를 띄웠다. wpa_supplicant를 `-g -O -c -i wlan0`로
띄우자 시작에서 `COMPLETED`까지 4.5초, `Key negotiation completed [PTK=CCMP GTK=CCMP]`.
PID 1이 띄운 dhcpcd가 아무 도움 없이 `wlan0: carrier acquired` → `leased 192.168.77.126`
(carrier에서 8.5초, 대부분 ARP probe). netns 안의 `nc -l`로 가는 TCP 왕복이 답을 받았다.
`wlan1`이 netns로 떠날 때 dhcpcd는 `removing interface`로 놓았다.

`interface_add`로 이미 있는 인터페이스를 넣으면 `FAIL`이고 연결은 그대로다. SIGTERM에
56ms에 죽으며 deauth를 보내고, dhcpcd가 `carrier lost`로 route를 지운다. wpa_supplicant는
`p2p-dev-wlan0`을 스스로 만든다(해는 없다).

### 실측 7 — 늦은 인터페이스는 hook의 `PREINIT`이 잡는다. 부팅 직후에는 소켓이 없다

`phy0`을 netns `park`에 넣어 두고 wpa_supplicant를 `-g -O`만으로(인터페이스 0개) 띄웠다 —
산다. `phy0`을 root ns로 되돌리자 dhcpcd가 hook을 `reason=PREINIT iface=wlan0 wireless=1`로
불렀고, hook의 `interface_add`가 `OK`, 10초 뒤 `COMPLETED`, 그 뒤 `BOUND`. hook의 reason
순서는 `PREINIT` → `NOCARRIER` → `CARRIER` → `BOUND`, 떠날 때 `DEPARTED`.

부팅 직후 dhcpcd가 처음 본 `wlan0` · `wlan1`의 `PREINIT`에서는 global 소켓이 아직 없어
`Failed to connect … No such file or directory`였다. 결정 4의 배경 재시도가 이것 때문이다.

### 실측 8 — `regulatory.db`는 서명 검증을 지나 받아들여진다

wireless-regdb의 `regulatory.db` · `.p7s`를 넣자 `failed to load regulatory.db` 줄이
사라졌다. 국가는 `00`(아무도 안 정했다). 게이트는 설정에 `country=KR`을 넣고 `iw reg get`이
`KR`이 되는 것으로 db가 있다는 것을 본다.

### 실측 9 — firmware를 넣으면 부팅마다 initramfs 풀기가 0.96초 는다

`Unpacking initramfs` → `Freeing initrd memory`가 1.48초(46,100K) → 2.44초(83,904K). 탐침까지의
벽시계 5.1초 → 6.1초. 루트 게이트의 부팅이 100번 안팎이므로 한 판에 1~2분이다. 위험 1은
받아들인다 — firmware를 ISO에만 따로 두는 길은 안 연다. 게이트가 제품과 같은 initrd로 뜬다.

## 실측 (M1 · M2, 2026-09-28)

### 실측 10 — 86MB initrd가 limine BIOS로 ISO에서 뜬다

`make_initrd.sh`의 옛 주석이 "53MB에서 부팅조차 못 했다"고 적은 경로(`boot` 체인)다. 그
벽은 gzip 전의 것이었다. firmware를 붙인 86MB가 fish 배너까지 약 11초, 체인 전체 43초(첫
회차라 firmware를 푸는 시간 포함). `nic` 32초 · `net` 170초 · `tools` 56초도 초록이다 —
모든 부팅에 `hwsim0`이 생겨도 dhcpcd와 판정이 그대로다.

### 실측 11 — 정적 검사는 이어 붙이는 줄이 빠진 것을 잡는다

`gzip -dc | cpio -it`는 첫 archive에서 멈춰서 firmware가 목록에 안 나온다. 그래서 `tools`
체인의 검사 1b는 initrd의 꼬리가 `firmware.cpio.gz`와 바이트까지 같은지와, 그 cpio에 목록의
경로가 전부 있는지를 따로 본다. 반사실 — `make_initrd.sh`의 `cat … >> initrd.cpio`를 뺀
사본으로 덮으면 검사 1은 초록이고 1b가 `the initrd does not end with the firmware cpio`로
멈춘다.

### 실측 12 — firmware가 `MemAvailable`을 96MB 줄인다

`services.d` 탐침이 부팅 3초 뒤 `/proc/meminfo`를 찍었다. firmware 없는 initrd(지금 initrd의
꼬리를 잘라 만들었다) 309,200kB, 있는 것 213,368kB. 풀린 크기와 같다.

### 실측 13 — 제품 경로가 hwsim에서 선다. 시작 중에 사라진 인터페이스는 wpa_supplicant를 죽인다

측정용 cpio 없이 제품 initrd로 뜨고, 설정 디스크에 `wpa_supplicant.conf`(`country=KR`)와 AP를
세우는 탐침을 두었다.

- `tars-init: wpa_supplicant joins the services, tars-wifi picks the interfaces` 뒤에
  `started service wpa_supplicant (pid 39, /usr/lib/tars/tars-wifi)`,
  `tars-wifi: wpa_supplicant on wlan0 wlan1`. `pgrep -a`의 pid 39가
  `/usr/bin/wpa_supplicant -g … -i wlan0 -N … -i wlan1`이다 — exec이 pid를 지켰다.
- 제품 dhcpcd가 `wlan0: leased 192.168.77.126`. `iw reg get`이 `country KR`이다 — `regulatory.db`가
  initrd에 있다는 양성 증거다.
- `tars-service restart wpa_supplicant` — `restarting service wpa_supplicant on request`, 새 pid가
  `wlan0`만 세어 다시 `COMPLETED`.
- 탐침이 부팅 직후 곧바로 `phy1`을 옮긴 판에서는 pid 39가 status 255로 죽었다. 로그는
  `wlan1: Failed to initialize driver interface` → `CTRL-EVENT-TERMINATING`. 명령줄로 받은
  인터페이스의 초기화 실패는 치명적이다. 감독자가 1초 뒤 되살렸고 새 `tars-wifi`가 `wlan0`만
  세어 연결까지 갔다. 탐침이 global 소켓의 `interface` 목록에 `wlan1`이 나올 때까지 기다린
  뒤 옮긴 판에서는 pid 39가 그대로 살았고 목록에 `wlan1`이 남았다(위험 6). wifi 체인은 뒤의
  모양을 쓴다 — 실기에서 동글을 뽑는 것과 같은 경로다.
