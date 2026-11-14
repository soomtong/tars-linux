---
name: project_link_status
description: 상태 줄의 배터리 칸 왼쪽에 무선 SSID나 LAN을 보이는 서브프로젝트 Link Status(LK-M0~M2, 2026-11-15). 커널 netlink 둘(rtnetlink 이벤트 · nl80211)만 읽는다. 함정 둘 — 커널은 AP가 Country 요소를 안 내면 station의 SSID를 안 채운다(GET_SCAN의 associated BSS로 찾는다), operstate를 안 다루는 유선 드라이버는 UNKNOWN에 머문다(유선은 IFF_RUNNING, 무선은 IF_OPER_UP으로 판정한다)
metadata:
  type: project
---

Link Status(LK)는 사용자의 요청("Wifi에 접속되어 있다면 배터리 영역 좌측에 Network ID, 유선이면 유선 접속 상태", 2026-11-14)에서
시작했다. design `docs/specs/2026-11-14-tars-link-status-design.md`, plan `docs/plans/2026-11-14-tars-link-status-lk-m0.md`(순수 층) ·
`-lk-m1.md`(`main.zig` 배선) · `docs/plans/2026-11-15-tars-link-status-lk-m2.md`(판정 · 닫기). 사용자는 검토안의 결정 넷(없으면 칸 없음 ·
둘 다면 둘 다 · 유선은 `LAN` · 주소를 기다리면 흐린 색)을 받고 나머지를 위임했다. M2는 사용자가 자는 동안 lead가 끝까지 했다.

## 모양

- 읽는 길: rtnetlink(`RTMGRP_LINK | RTMGRP_IPV4_IFADDR` 이벤트 + 처음 dump)와 nl80211(`GET_INTERFACE` — 무선인가 · station인가 ·
  SSID, 모자라면 `GET_SCAN`). 셋 다 권한이 필요 없다. wpa_supplicant · dhcpcd · sysfs에는 안 묻는다. 타이머 없음.
- 셀 인터페이스: ARPHRD_ETHER이고 `IFLA_LINKINFO` 안에 `IFLA_INFO_KIND`가 없는 것(veth · bridge · tun은 빠지고 bridge에 묶인
  실NIC은 남는다). nl80211이 답하면 무선이고 STATION · P2P_CLIENT만 센다 — AP도 SSID를 낸다.
- 연결 판정: 유선은 `ifi_flags & IFF_RUNNING`, 무선은 `IF_OPER_UP`(`Iface.isUp`). 주소: IPv4 주소의 집합(lease 갱신의 NEWADDR가 되풀이되므로 개수가 아니다).
- 로그: `link> if` · `link> state` · `link> nl80211 …`(답 한 줄, 실기 진단용) · `status> link cell=… ink ready= wait=`.

## 함정 — 다시 조사하지 말 것

1. `__cfg80211_connect_result`(`net/wireless/sme.c`, 6.18)는 BSS에 Country 요소가 없으면 SSID를 복사하기 전에 돌아간다.
   wpa_supplicant + mac80211 경로에서 `GET_INTERFACE`의 SSID가 빈다(wifi 체인의 hostapd가 그렇다). associated 표시는 그보다
   앞에서 서므로 `GET_SCAN` dump의 `NL80211_BSS_STATUS` ASSOCIATED BSS의 정보 요소에서 SSID를 읽는다(`iw dev … link`의 길).
2. QEMU usb-net(cdc_ether)은 operstate를 안 다뤄 주소를 받아도 `IF_OPER_UNKNOWN`이다. 커널의 `IFF_RUNNING`은 UP과 UNKNOWN에
   선다(`netif_oper_up`의 "backward compat"). `IF_OPER_UP`만 보면 꽂은 USB NIC가 칸에 안 오른다 — nic 체인 검사 11.
   그런데 무선에 `IFF_RUNNING`을 쓰면 켠 직후 linkwatch 전의 UNKNOWN 틈에 붙지 않은 station이 한 프레임 `WLAN`으로 뜬다 —
   wifi 체인 검사 14. 그래서 종류마다 다르다.
3. 화면을 비교하거나 `ink fg=`를 세는 체인은 전부 `-nic none`이다(`require_explicit_nic`). 링크 칸은 NIC를 단 체인에만 뜬다.

## 남은 것

- 실기(맥북 에어 2011): Country 요소를 내는 실제 AP에서 `GET_INTERFACE`의 SSID 길(`link> nl80211 … ssid_len=`). 게이트는 못 밟는다.
- 무선 둘의 SSID 동시 표시 · IPv6 · 신호 세기는 비목표다.
