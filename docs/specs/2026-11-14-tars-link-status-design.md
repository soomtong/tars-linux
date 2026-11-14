# TARS Link Status — Design

Date: 2026-11-14
Status: 끝났다(2026-11-15) — LK-M0 · M1 · M2. design과 달라진 자리: SSID는 `GET_SCAN`으로도 찾는다(M1 결과 3), 연결 판정은 유선 `IFF_RUNNING` · 무선 `IF_OPER_UP`(M2 확정 1 · 4). 판정은 wifi 체인 검사 13~15 · nic 체인 검사 9~11. 루트 게이트 34/34. 기억은 `docs/decisions/project_link_status.md`.

접두사: LK. `NS`는 Nerd Symbols가 쓰고 있다(`docs/guides/completed.md`).

사용자의 요청 한 줄에서 시작한다(2026-11-14).

> 장비가 Wifi 에 접속되어 있다면 terminal 우측 배터리 영역 좌측에 Network ID 출력; 유선 랜 접속되어 있다면 유선 네트워크 접속
> 상태를 표기하는 방법 검토 및 구현 계획

검토안의 결정 넷(아무 연결이 없으면 칸 없음 · 유선과 무선이 둘 다면 둘 다 · 유선은 `LAN` · 주소를 기다리는 동안은 흐린 색)을
사용자가 추천안 그대로 받았고, 나머지는 위임했다("agree all. accept suggestion. pick your best.").

## 한 줄 요약

상태 줄 오른쪽, 배터리 칸 왼쪽에 링크 칸이 뜬다. 무선 station이 AP에 붙어 있으면 그 SSID, 유선이 붙어 있으면 `LAN`이다. IPv4 주소까지
받았으면 보통 색, 링크만 서고 주소를 기다리는 중이면 흐린 색이다. 커널의 netlink 둘(rtnetlink · nl80211)만 읽고, wpa_supplicant ·
dhcpcd · sysfs에는 묻지 않는다. 이벤트가 없으면 terminal은 지금처럼 깨지 않는다.

```
  EN  신세벌 PCS  쿼티  CAPS                                    tars-wl   85%   ← 무선, 주소 있음
  EN  신세벌 PCS  쿼티  CAPS                                    tars-wl   85%   ← 무선, 주소 기다림(흐림)
  EN  신세벌 PCS  쿼티  CAPS                               LAN  tars-wl   85%   ← 유선과 무선 둘 다
  EN  신세벌 PCS  쿼티  CAPS                                        LAN         ← 배터리 없는 기계의 유선
  EN  신세벌 PCS  쿼티  CAPS                                              85%   ← 붙은 것이 없다
```

## 배경

배터리 칸(BS, 2026-10-09)이 상태 줄에 처음 terminal 밖의 상태를 올렸다. 링크 칸은 두 번째다. 그래서 모양은 BS를 그대로 따른다 —
순수 층과 시스템 콜의 경계(BS 결정 7), 오른쪽 끝에 따로 그리는 칸(BS 결정 6), 새 색 상수와 픽셀 셈(BS 결정 5 · 10).

다른 점은 둘이다. 배터리는 sysfs 파일 두 개를 읽으면 되지만 SSID는 sysfs에 없다. 그리고 배터리는 60초 주기로 읽어도 되지만 링크는
붙고 끊기는 순간이 바로 보여야 쓸모가 있다.

## 착수 전에 확인한 것

2026-11-14, HEAD `9886987`. 커널 소스 `kernel/src/linux-6.18.60/` · uapi 헤더(zig 0.17.1의 `libc/include/any-linux-any/linux/`) ·
저장소 코드를 읽었다. 부팅은 안 했다.

1. `kernel/.config`는 `CONFIG_CFG80211=y`이고 `CONFIG_CFG80211_WEXT`가 꺼져 있다. `SIOCGIWESSID`(`iwgetid`의 길)는 없다.
2. nl80211 `NL80211_CMD_GET_INTERFACE`는 권한 없이 부를 수 있다(`net/wireless/nl80211.c:18594`의 주석 "can be retrieved by
   unprivileged users", `GENL_ADMIN_PERM` 없음).
3. 그 응답의 SSID는 iftype마다 다른 필드에서 온다(`nl80211_send_iface`, `nl80211.c:4328~4345`). STATION · P2P_CLIENT는
   `wdev->u.client.ssid`, AP · P2P_GO는 `wdev->u.ap.ssid`다. 즉 AP 모드 인터페이스도 SSID를 낸다 — wifi 체인은 게스트 안에서
   hostapd로 AP를 띄우므로(`wifi/check.sh:192`), iftype을 안 보면 AP 쪽 SSID가 칸에 같이 뜬다. `ssid_len`이 0이면 attribute가 없다.
4. `RTM_NEWLINK`의 `IFLA_LINKINFO`는 `dev->rtnl_link_ops`가 있거나 다른 장치의 slave일 때 나온다(`net/core/rtnetlink.c:2161`).
   veth · bridge · tun · dummy는 `rtnl_link_ops`가 있어 `IFLA_INFO_KIND`를 낸다. 실NIC이 bridge에 묶이면 `IFLA_LINKINFO`는 나오지만
   그 안에는 `IFLA_INFO_SLAVE_KIND`뿐이고 `IFLA_INFO_KIND`는 없다. 그래서 가상 장치의 판정은 "`IFLA_LINKINFO`가 있다"가 아니라
   "`IFLA_INFO_KIND`가 있다"여야 한다.
5. 상수(uapi 헤더를 `zig cc -target x86_64-linux-gnu`로 컴파일해 값을 뽑았다): `RTM_NEWLINK` 16 · `DELLINK` 17 · `GETLINK` 18 ·
   `NEWADDR` 20 · `DELADDR` 21 · `GETADDR` 22, `RTMGRP_LINK` 1 · `RTMGRP_IPV4_IFADDR` 16, `IFLA_IFNAME` 3 · `IFLA_OPERSTATE` 16 ·
   `IFLA_LINKINFO` 18 · `IFLA_INFO_KIND` 1, `IF_OPER_UP` 6, `IFA_LOCAL` 2 · `IFA_ADDRESS` 1, `GENL_ID_CTRL` 16 ·
   `CTRL_CMD_GETFAMILY` 3 · `CTRL_ATTR_FAMILY_ID` 1 · `CTRL_ATTR_FAMILY_NAME` 2, `NL80211_CMD_GET_INTERFACE` 5 ·
   `NL80211_ATTR_IFINDEX` 3 · `NL80211_ATTR_IFTYPE` 5 · `NL80211_ATTR_SSID` 52, `NL80211_IFTYPE_STATION` 2 · `P2P_CLIENT` 8.
   그 밖에 `ARPHRD_ETHER` 1, `NLM_F_REQUEST` 1 · `NLM_F_DUMP` 0x300, `NLMSG_ERROR` 2 · `NLMSG_DONE` 3,
   `IFLA_INFO_SLAVE_KIND` 4, attribute 타입의 아래 14비트(`NLA_TYPE_MASK` 0x3FFF).
6. Zig 0.17 std에 `nlmsghdr` · `ifinfomsg` · `rtattr` · `IFLA`가 있다(`std/os/linux.zig`). `ifaddrmsg` · `genlmsghdr`는 없어 우리가
   둔다.
7. terminal의 상태 줄: 배터리 칸은 `drawStatus`의 끝(`terminal/src/main.zig:359~363`)에서 `cols - 4`부터 그린다. 왼쪽 문자열과
   `STATUS_BAT_GAP`(2칸)보다 가까우면 안 그린다. `dumpStatus`는 띠 전체의 픽셀을 색마다 세므로, 새 칸이 기존 색을 쓰면
   `status> ink fg=` 같은 기존 셈이 바뀐다.
8. terminal은 이미 `NETLINK_KOBJECT_UEVENT` 소켓을 `poll`의 `fds[0]`에 두고 있다(`main.zig:3958`). 소켓을 먼저 열고 그다음에
   훑는 순서(PD-M0)가 있다 — 사이에 생긴 변화를 놓치지 않는 순서다.

## 목표

- 무선 station이 AP에 붙으면 그 SSID가, 유선이 붙으면 `LAN`이 배터리 칸 왼쪽에 뜬다. 끊기면 사라진다.
- 링크는 섰지만 IPv4 주소가 없으면 흐린 색이다. 주소를 받는 순간 보통 색으로 바뀐다.
- 연결이 없는 기계 · 네트워크가 꺼진 부팅(`net=off`)에서는 화면이 한 픽셀도 안 바뀐다.
- 이벤트가 없으면 깨지 않는다. 주기 타이머를 더하지 않는다.

## 결정

### 결정 1 — 칸은 붙은 것만 말한다. 아무것도 없으면 칸이 없다

배터리가 없을 때 칸이 없는 것과 같은 규칙이다(BS 결정 1). `offline` 같은 글자는 띄우지 않는다. 링크 칸의 뜻은 "지금 이걸로
붙어 있다" 하나다.

### 결정 2 — 출처는 커널의 netlink 둘이다. 데몬에게 묻지 않는다

| 무엇 | 어디서 |
|---|---|
| 링크가 섰나 · 이름 · 장치 종류 · 가상인가 | rtnetlink `RTM_NEWLINK` · `RTM_DELLINK` |
| IPv4 주소가 있나 | rtnetlink `RTM_NEWADDR` · `RTM_DELADDR`(AF_INET) |
| 무선인가 · station인가 · SSID | nl80211 `NL80211_CMD_GET_INTERFACE`(ifindex로 하나) |
| SSID(위가 안 줄 때) | nl80211 `NL80211_CMD_GET_SCAN` dump의 associated BSS — LK-M1 결과 3 |

버린 길 셋.

- wpa_supplicant 제어 소켓(`STATUS` · `ATTACH`): 인터페이스마다 소켓이 따로이고(`/run/wpa_supplicant/<if>`), 유선은 따로
  봐야 하며, wpa_supplicant가 안 떠 있으면 아무것도 모른다. 커널이 이미 아는 사실을 데몬을 거쳐 물을 이유가 없다.
- `wpa_cli`를 주기적으로 띄우기: terminal이 프로세스를 띄우고, 주기만큼 늦으며, "이벤트가 없으면 안 깬다"(BS 결정 8)를 깬다.
- `SIOCGIWESSID`: 커널에 WEXT가 없다(확인 1).

operstate가 연결의 판정인 이유: 무선은 wpa_supplicant가 linkmode dormant로 인터페이스를 잡고 4-way handshake가 끝나야 `UP`으로
올린다. 유선은 carrier가 서면 `UP`이다. 그래서 `IF_OPER_UP` 하나가 유선과 무선 모두에서 "붙었다"를 뜻한다.

LK-M2에서 고쳤다: 유선의 판정은 `ifi_flags`의 `IFF_RUNNING`이다. 커널이 "켜져 있고 operstate가 UP 또는 UNKNOWN"일 때 세우는
비트다(`netif_get_flags` · `netif_oper_up`). operstate를 안 다루는 드라이버(QEMU의 usb-net)는 주소를 받아도 UNKNOWN에 머물러,
`IF_OPER_UP`만 보면 꽂은 USB NIC가 칸에 안 올랐다(LK-M2 plan 확정 1). 무선은 `IF_OPER_UP` 그대로다 — 켠 직후 linkwatch 전의
UNKNOWN 틈에 `IFF_RUNNING`이 서서, 그것을 믿으면 붙지 않은 station이 한 프레임 `WLAN`으로 떴다(확정 4).

### 결정 3 — 셀 인터페이스는 "ARPHRD_ETHER이고 `IFLA_INFO_KIND`가 없는 것"이다. 무선인지는 nl80211이 답한다

1. `ifinfomsg.ifi_type`이 1(ARPHRD_ETHER)이 아니면 안 센다 — `lo`(LOOPBACK), `hwsim0`(radiotap), 터널.
2. `IFLA_LINKINFO` 안에 `IFLA_INFO_KIND`가 있으면 안 센다 — veth · bridge(`docker0`) · tun · dummy(확인 4). CE의 Docker가
   컨테이너를 띄우기만 해도 "유선 연결"로 보이는 것을 막는 자리다.
3. 남은 것은 처음 볼 때 nl80211에 ifindex로 묻는다. 응답이 오면 무선, 에러(무선 장치가 아니면 `ENODEV`)가 오면 유선이다.
   무선이면 iftype이 STATION · P2P_CLIENT일 때만 센다(확인 3) — AP · monitor는 무선이지만 칸에 안 오른다.

sysfs의 `device` 링크 · `phy80211` 링크로도 같은 판정을 할 수 있지만, netlink만으로 되면 읽는 길이 하나라 순수 층에서 경계값을
전부 볼 수 있다.

### 결정 4 — 칸의 글자: 유선이 앞, 무선이 뒤, 사이는 두 칸

- 유선: 붙은 유선이 하나 이상이면 `LAN` 하나. 둘이 붙어도 `LAN`이다. 그중 하나라도 IPv4 주소가 있으면 보통 색이다.
- 무선: 붙은 station 중 ifindex가 가장 작은 하나의 SSID. 무선 둘(내장 + 동글)이 동시에 붙는 일은 드물고, 칸은 "붙어 있다"를
  말하는 자리라 하나면 된다.
- 둘 다 있으면 `LAN  tars-wl`. 사이는 왼쪽 문자열의 칸 사이와 같은 두 칸이다.
- SSID는 바이트열이다(최대 32바이트). 유효한 UTF-8이고 제어 문자(C0 · DEL · C1)가 아닌 코드포인트는 그대로 두고, 그 밖의
  바이트는 하나마다 `?`로 바꾼다. 한글 SSID는 폭 2로 그려진다(`drawRun`이 이미 한다). 결과는 언제나 32바이트 이하라 자르지 않는다.
- 붙었는데 SSID를 끝내 모르면 `WLAN`이다. `GET_INTERFACE`의 SSID는 AP가 Country 요소를 안 내면 비므로(LK-M1 결과 3)
  `GET_SCAN`의 associated BSS에서 다시 찾고, 그래도 없으면(숨긴 망) `WLAN`이다.

### 결정 5 — 색은 둘이고 전부 새 상수다

`STATUS_LINK`(주소 있음)와 `STATUS_LINK_WAIT`(링크만 섰음). 값은 LK-M1 plan이 기존 상수 열(`main.zig:59~114`)과 겹치지 않게 정한다.
새 상수여야 하는 이유는 확인 7이다 — 기존 색을 쓰면 `status> ink fg=` 같은 셈이 링크 칸의 픽셀까지 센다. 색은 토막마다 따로다
(`LAN`은 보통 색인데 무선은 흐릴 수 있다).

### 결정 6 — 자리는 배터리 칸 왼쪽이다. 오른쪽 끝을 맞춘다

- 배터리 칸이 그려지면 링크 칸의 오른쪽 끝은 `bat_col - STATUS_BAT_GAP`, 배터리 칸이 없으면 격자 오른쪽 끝(`cols`)이다.
- 폭은 글리프 폭으로 잰다. 한글은 폭 2라 바이트 수와 다르다 — `drawRun`과 같은 `cache.find`의 `cell_width`로 먼저 재고, 그 폭만큼
  왼쪽에서 시작한다.
- 왼쪽 문자열의 끝에서 `STATUS_BAT_GAP`보다 가까우면 칸 전체를 안 그린다(배터리 칸과 같은 규칙). 1280 × 800에서 격자가 155칸,
  왼쪽이 약 50칸, 배터리 4칸이라 32바이트 SSID와 `LAN`이 둘 다 들어간다.
- `status.zig` · `status> text=`는 안 바뀐다. 링크 칸은 왼쪽 문자열 밖이다(BS 결정 6과 같다).

### 결정 7 — 순수 층은 `link.zig`, 시스템 콜은 `main.zig`의 링크 절이다

`link.zig`가 하는 것: netlink 메시지 · attribute 순회(잘린 메시지에 안전하게), 요청 메시지 짓기(dump · GETFAMILY ·
GET_INTERFACE), 응답 읽기(`RTM_NEWLINK` · `RTM_NEWADDR` · nl80211 · ctrl), 인터페이스 표(최대 8개, 인터페이스마다 IPv4 주소 최대 4개),
SSID 정리, 칸의 토막과 색 고르기. 소켓을 열고 보내고 받고 로그를 찍는 것은 `main.zig`다. `link_test`가 부팅 없이 바이트 단위로 본다.

주소는 개수가 아니라 집합으로 센다. dhcpcd가 lease를 갱신하면 같은 주소의 `RTM_NEWADDR`가 수명만 바뀐 채 다시 온다 — 개수로 세면
갱신마다 늘어나고 `DELADDR` 한 번으로는 0이 안 된다.

### 결정 8 — 갱신은 처음 훑기 · rtnetlink 이벤트 둘뿐이다. 타이머는 없다

1. terminal이 뜰 때 rtnetlink 소켓을 `RTMGRP_LINK | RTMGRP_IPV4_IFADDR`로 bind하고 `poll`에 넣는다(먼저 연다 — 확인 8의 순서).
2. 그다음 따로 연 소켓 하나로 `RTM_GETLINK` dump, 끝나면 `RTM_GETADDR` dump를 동기로 받아 표를 채운다(한 소켓에서 dump 둘을
   겹치면 `EBUSY`라 차례로). 이 사이에 온 이벤트는 1의 소켓에 쌓여 있다가 다음 바퀴에 같은 함수로 들어간다 — 같은 사실을 두 번
   받아도 표는 같다.
3. 무선 판정이 필요한 인터페이스(처음 본 것)와 무선 station이 `UP`으로 바뀐 것은 nl80211에 묻는다. 별도의 genetlink 소켓에
   `SO_RCVTIMEO` 1초로 동기 질의한다 — 커널이 바로 답하는 질의라 poll에 넣을 이유가 없다. family id는 처음 한 번
   `CTRL_CMD_GETFAMILY "nl80211"`로 받는다. 못 받으면(무선 스택 없음) 모두 유선으로 본다.
4. 1의 소켓이 `ENOBUFS`(이벤트가 넘쳐 버려졌다)를 내면 표를 비우고 2부터 다시 한다.
5. 같은 SSID 안의 AP 이동은 링크가 안 내려가므로 SSID 질의를 다시 안 해도 글자가 맞다. 다른 망으로 옮기면 그 사이에 operstate가
   내려갔다 올라온다.

### 결정 9 — 로그는 `link>` 줄 둘과 `status> link` 줄 하나다

- `terminal: link> if <name> index=<n> kind=wired|wifi|ignored(<이유>)` — 인터페이스를 처음 볼 때 한 번.
- `terminal: link> state <name> up=0|1 v4=<주소 수> ssid=<정리한 SSID 또는 ->` — 그 인터페이스의 상태가 바뀔 때만.
- `terminal: status> link cell=<"글자" 또는 none> ink ready=<n> wait=<n>` — `dumpStatus`가 매번(배터리 줄과 같은 자리).

SSID는 비밀이 아니고, 게이트가 이 줄로 판정하므로 그대로 찍는다(정리한 글자).

### 결정 10 — 게이트는 기존 체인 둘에 판정을 더한다. 새 체인을 안 만든다

- `wifi/check.sh`: hwsim과 hostapd로 붙는 부팅에서 `status> link cell="tars-wl"`이고 ready 픽셀이 0보다 크다. AP 쪽 인터페이스의
  `kind=wifi`가 있는데도 칸에 SSID가 한 번만 있다(확인 3의 구멍). hostapd를 내리면 칸이 사라진다.
- `nic/check.sh`: e1000e 부팅에서 `cell="LAN"`.
- NIC이 없거나 `net=off`인 부팅 하나에서 `cell=none`.

어느 부팅을 쓰고 어떻게 hostapd를 내리는지는 LK-M2 plan이 체인을 읽고 정한다. 새 체인을 안 만드는 이유는 판정에 필요한
상황(AP 연결 · 실NIC)을 두 체인이 이미 세우고 있어서다 — 부팅을 더하면 루트 게이트만 길어진다.

### 결정 11 — milestone은 셋이다

| milestone | 무엇 | 게이트 |
|---|---|---|
| LK-M0 순수 층 | `link.zig` · `link_test.zig` · `build.zig` 등록. terminal의 동작은 하나도 안 바뀐다 | `link_test` · `make quick` |
| LK-M1 칸이 뜬다 | `main.zig`의 링크 절(소켓 · dump · nl80211 · poll), `Status` · `StatusMemo`의 `link`, `drawStatus` · `dumpStatus` | 체인 몇 개로 로그 확인, 루트 게이트 |
| LK-M2 판정과 닫기 | 결정 10의 판정, `docs/help`, 닫을 때의 목록 | 루트 게이트 |

## 위험

1. 결정 3의 "`IFLA_INFO_KIND`가 없으면 실장치"는 커널 소스로만 확인했다. virtio-net · e1000e · hwsim의 실제 줄은 LK-M1의
   `link> if` 로그로 처음 본다.
2. 게이트는 hwsim만 본다. 실칩(맥북 에어 2011의 Broadcom)에서 operstate와 SSID가 같은 순서로 오는지는 실기 몫이다.
3. virtio-net으로 부팅하는 기존 체인 모두의 띠에 `LAN`이 새로 생긴다. 새 색이라 기존 셈은 그대로여야 하지만, screendump로 띠를
   비교하는 체인이 있으면 깨진다. LK-M1 plan이 `rg`로 찾는다.
4. rtnetlink 이벤트는 `RTM_NEWLINK`가 변화 없이도 자주 온다. 표를 비교해 바뀐 것만 다시 그린다(`StatusMemo`).

## 비목표

IPv6 주소, 신호 세기, IP 주소 글자, wpa_supplicant의 중간 상태(scanning · authenticating), 무선 둘의 SSID 동시 표시, 클릭 · 메뉴.

## 닫을 때(lead의 몫)

이 문서의 `Status:`, `docs/guides/completed.md` 한 행, 소개 페이지 `data.js`, `docs/decisions/project_link_status.md`와 `MEMORY.md`
한 줄, `HANDOFF.md`. 사용자가 치는 것은 안 바뀌지만 `docs/help/`에 상태 줄 설명이 있으면 링크 칸을 더한다.

## 관련

`docs/specs/2026-10-08-tars-battery-status-design.md`(BS) · `2026-09-28-tars-wireless-design.md`(WL) ·
`2026-09-26-tars-wired-nic-design.md`(WN) · `docs/decisions/feedback_boot_never_blocks.md`.
