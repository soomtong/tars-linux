# LK-M1 — 칸이 뜬다

Date: 2026-11-14
Design: `docs/specs/2026-11-14-tars-link-status-design.md`
Status: 끝났다(2026-11-14). 결과는 맨 아래 "결과" 절 — 무선 SSID는 `GET_SCAN`으로 다시 찾는다(결과 3). 다음은 LK-M2.

## 누가 무엇을 하나

lead가 직접 넣는다. 고치는 파일은 `terminal/src/main.zig` 하나다. `link.zig` · `status.zig`는 안 바뀐다.

## 이 milestone이 끝나면

- NIC를 단 부팅의 상태 줄에 `LAN`(virtio-net · e1000e)이, hwsim으로 AP에 붙은 부팅에 `tars-wl`이 배터리 칸 자리 왼쪽에 뜬다.
- 로그에 `terminal: link> if …` · `terminal: link> state …` · `terminal: status> link …` 줄이 생긴다(design 결정 9).
- `-nic none` 부팅(체인의 대부분)은 `status> link cell=none ink ready=0 wait=0` 한 줄이 더해질 뿐 화면이 그대로다.
- 판정은 아직 안 더한다(LK-M2). 이 milestone은 net · wifi 체인의 로그를 사람이 읽어 확인하고, 루트 게이트가 회귀를 본다.

## 착수 전에 확정한 것

2026-11-14, HEAD `ca5ef19`.

1. 기존 판정이 깨질 걱정(design 위험 3)은 사실상 닫혔다. 띠를 screendump로 보거나 `ink fg=`를 세는 체인(pointer · terminal · hidpi ·
   display · fullscreen · hangul)은 모두 `-nic none`이고, 루트 `check.sh`의 `require_explicit_nic`가 모든 QEMU 호출에 NIC를 밝히게
   한다. NIC가 있는 체인은 service · mise · firewall · nic · dictation · net · pm(+ wifi의 hwsim)이고, 이 중 띠의 픽셀을 보는 것은
   dictation의 `dict ink` 하나인데 색이 다르다.
2. 색: `STATUS_LINK` `0x0070B0E0`(주소 있음), `STATUS_LINK_WAIT` `0x00586878`(링크만). `main.zig` · `pointer.zig`의 어느 색과도
   다르다(`rg -o "0x00[0-9A-Fa-f]{6}"`로 대조).
3. 자리(design 결정 6): 배터리가 없으면 오른쪽 끝이 `cols`, 배터리가 그려졌으면 `bat_col - STATUS_BAT_GAP`이다. 배터리 칸이
   있는데 왼쪽 문자열에 막혀 못 그렸으면 링크 칸도 안 그린다 — 오른쪽 칸이 왼쪽 칸만 남는 모양을 막는다. 폭은 `drawRun`과 같은
   글리프 폭 셈(`runWidth`)으로 먼저 잰다.
4. 소켓 셋.
   - 이벤트: `NETLINK_ROUTE`, `SOCK_RAW | NONBLOCK | CLOEXEC`, groups `RTMGRP_LINK | RTMGRP_IPV4_IFADDR`. `poll`의 맨 끝 칸이다
     (`fds`의 상한에 1을 더한다). 이 순서 이름은 `link_at = pty_end + 4`.
   - dump: `NETLINK_ROUTE`, 막는 소켓, `SO_RCVTIMEO` 1초. 훑을 때마다 열고 닫는다.
   - nl80211: `NETLINK_GENERIC`, 막는 소켓, `SO_RCVTIMEO` 1초. 준비 때 열고 family를 받는다. 못 받으면 닫고 모두 유선으로 본다.
5. 준비 순서는 `openInputs` → `openBattery` → `openLink`다. 이벤트 소켓을 연 뒤 dump한다(design 결정 8). 처음 훑기는 다시
   그리기를 안 켠다 — `openBattery`와 같은 이유(첫 프레임은 셸의 출력이 그리고 칸은 이미 그 안에 있다).
6. 바퀴에서는 `pollBattery` 뒤에 `readLink`다. `decideFrame`보다 앞이라 이벤트만으로 깬 바퀴도 그린다.
7. `recv` 버퍼는 32KiB 정적 배열 하나다(`link_buf`). `RTM_NEWLINK` 하나는 통계를 담아 1~2KiB이고, dump는 여러 번 `recv`한다.
   `LinkMsg.name`이 이 버퍼를 가리키므로 `applyLink`까지 같은 `recv` 안에서 끝낸다(LK-M0 결과).
8. 이벤트 소켓의 `ENOBUFS`는 표를 비우고 다시 훑는다(design 결정 8의 4). uevent의 `drainUevents`와 같은 관용구다.
9. nl80211 응답은 seq로 맞춘다. 시간이 지나 늦게 온 옛 응답은 건너뛴다. 1초 안에 답이 없으면 그 인터페이스는 `unknown`으로
   남고 다음 `RTM_NEWLINK`에 다시 묻는다.
10. 로그(design 결정 9): `link> if <name> index=<n> kind=<kindName>`은 처음 보고 판정을 마친 뒤 한 번. `link> state <name> up=<0|1>
    v4=<n> ssid=<글자|->`는 그 인터페이스의 (up, 주소 수, SSID)가 바뀔 때만(후보만 — 가상 · 비ether는 안 찍는다).
    `link> gone <name>`은 DELLINK. `link> scan links=<n>`은 훑기마다. 실패는 `link> open failed …` · `link> nl80211 none`.

## 할 일

1. 상수 · `Status.link` · `StatusMemo` · `drawStatus` · `runWidth` · `dumpStatus` · `dumpLinkInk`.
2. 링크 절: `LinkState`, 소켓 열기, dump, nl80211 질의, 메시지 처리, 이벤트 비우기.
3. `App`: 필드, `openLink`, `fds` 칸, `readLink`, 프레임의 `.link`.
4. `make quick`, 컨테이너 `zig build test`.
5. 체인 net · wifi를 돌려 로그를 읽는다. 그다음 루트 게이트.

## 결과 (2026-11-14)

1. 유선은 처음 판에 의도대로 섰다. net 체인(PASS, 554초)의 부팅 여섯 모두 `eth0 kind=wired`, `lo` · `hwsim0`은 `ignored(not-ether)`,
   칸은 `LAN`이 `wait=67`로 떴다가 DHCP 뒤 `ready=67`로 바뀐다. lease를 다시 받는 부팅은 그 왕복이 한 번 더 찍힌다.
   design 위험 1(`IFLA_INFO_KIND`가 없으면 실장치)은 virtio-net에서 맞았다.
2. 무선의 첫 판은 칸이 `WLAN`이었다 — station 판정과 붙는 순간은 맞는데 SSID가 비었다. nl80211 답을 찍는 줄
   (`link> nl80211 index=… iftype=… ssid_len=…|ssid=none|error=…`)을 더해 다시 돌리니 올라온 뒤의 답도 `iftype=2 ssid=none`이었다.
   이 줄은 실기 진단용으로 남긴다.
3. 원인은 커널이다. `__cfg80211_connect_result`(`net/wireless/sme.c`)가 BSS에 Country 요소가 없으면 `return`하는데, SSID를 복사하는
   블록이 그 뒤에 있다. wifi 체인의 hostapd는 국가 코드를 광고하지 않는다. associated 표시(`current_bss`)는 그 `return`보다 앞에서
   선다. 그래서 `GET_INTERFACE`가 SSID를 안 준 station은 `NL80211_CMD_GET_SCAN` dump(권한 없음 — `GENL_UNS_ADMIN_PERM`이 없다)에서
   `NL80211_BSS_STATUS`가 ASSOCIATED인 BSS의 정보 요소(probe → beacon 순)에서 SSID(요소 0)를 읽는다. `iw dev … link`와 같은 길이다.
   상수: `GET_SCAN` 32 · `NEW_SCAN_RESULTS` 34 · `ATTR_BSS` 47 · `BSS_INFORMATION_ELEMENTS` 6 · `BSS_BEACON_IES` 11 · `BSS_STATUS` 9 ·
   ASSOCIATED 1. `link.zig`에 `parseScanBss` · `ieSsid` · `buildGetScan` · `Table.needsScan` · `Table.applySsid`, 검사 21~24를 더했다.
   `genl_buf`는 8 → 32KiB(scan dump는 받는 쪽 길이에 맞춰 묶인다).
4. 고친 판의 wifi 체인(PASS, 259초): `link> nl80211 scan index=2 bss=1 associated=changed` 뒤 `tars-wl`이 `wait=114` → `ready=114`,
   끊기면 `cell=none`, 다시 붙으면 다시 scan해 `tars-wl`. AP 쪽 인터페이스(`wlan1` · `wlan2`)는 체인이 다른 netns로 옮겨 `gone`으로
   빠지고 칸에 SSID는 한 번만 있다.
5. `GET_INTERFACE`의 SSID 길(Country 요소가 있는 실제 AP)은 게이트가 못 밟는다 — 단위 검사 11 · 12가 본다. 실기 몫이다.
6. 루트 게이트 34/34 첫 판 PASS(2,217초, 잘린 줄 0, `out/gate-logs/20261114-141954`). 같은 판에 cyber 0.4.11(별도 commit)이 실려
   devtools 체인이 `cyber 355ms`였다.
