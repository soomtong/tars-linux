# TARS Wireless — Design

접두사: WL

Status: 설계(2026-09-28). M0 실측 전이다.

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

### 결정 4 — `init`은 파일이 있으면 wpa_supplicant를 감독한다

`/config/wpa_supplicant.conf`가 있고 `net`이 `off`가 아니면 `Kind.service`로 목록에
넣는다. label은 `service wpa_supplicant`, 자리는 dhcpcd 앞이다. argv는
`wpa_supplicant -M -i 'wlan*' -c /config/wpa_supplicant.conf -O /run/wpa_supplicant`의
모양이고 M0이 확정한다. `-O`는 사람의 파일에 `ctrl_interface` 줄이 없어도 `wpa_cli`가
닿게 하려는 것이다. 넣지 않을 때는 이유를 한 줄 남긴다(DS 결정 1). `services.d`의
같은 이름은 건너뛴다(DS 결정 5).

`net=off`에서 안 넣는 이유 — 주소를 받을 dhcpcd가 없는데 연결만 서는 것은 사람이 볼 때
"붙었는데 안 된다"다.

### 결정 5 — 게스트 도구는 넷이다

`wpa_supplicant` · `wpa_cli` · `wpa_passphrase` · `iw`. 사람의 첫 설정은
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

### 위험 2 — Debian 빌드에 `-M`이 없을 수 있다

`-M`은 `CONFIG_MATCH_IFACE`로 빌드해야 생긴다. 없으면 부팅 때 `/sys/class/net/*/wireless`를
한 번 훑는 것으로 물러서고, 부팅 뒤 꽂는 USB 무선은 비목표가 된다.

### 위험 3 — 커널 param이 두 번 오면 뒤의 것이 이긴다는 것은 짐작이다

M0이 잰다. 틀리면 결정 2를 다시 본다.

### 위험 4 — 게이트는 실칩의 probe와 firmware 로딩을 못 본다

RM · WN과 같은 반쪽 판정이다. 파일이 initrd에 있는지만 본다.

## 비목표

1. 실기 판정. 실기가 생기면 연다.
2. 파일 없이 부팅 뒤에 네트워크를 고르는 UI.
3. WPA-Enterprise(802.1X).
4. 제품 쪽의 AP 모드.
5. Broadcom · 그 밖의 벤더.
6. 여러 NIC 사이의 route 우선순위. dhcpcd 기본값이다.
7. IPv6.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- WL-M0 — 실측, 코드 0줄. 위험 1~3, firmware 파일 목록, netns · hostapd 게이트가 서는가.
- WL-M1 — 커널 config, firmware를 initrd에 넣기, 정적 검사.
- WL-M2 — `init`과 게스트 도구.
- WL-M3 — 체인 · 반사실 · 가이드 · 루트 게이트 · 닫기.
