# LK-M0 — 링크 칸의 순수 층

Date: 2026-11-14
Design: `docs/specs/2026-11-14-tars-link-status-design.md`
Status: 끝났다(2026-11-14). 결과는 맨 아래 "결과" 절. 다음은 LK-M1.

## 누가 무엇을 하나

lead가 직접 넣는다(design 결정 11). 새 파일 둘과 `terminal/build.zig` 편집 하나다. `main.zig` · `status.zig`는 한 줄도 안 바뀐다 —
terminal은 아직 링크를 안 읽고 화면은 그대로다.

| 파일 | 무엇을 |
|---|---|
| `terminal/src/link.zig` | 새 파일 — netlink 순회 · 요청 짓기 · 응답 읽기 · 인터페이스 표 · SSID 정리 · 칸 |
| `terminal/src/link_test.zig` | 새 파일 — 호스트 검사(아래 표) |
| `terminal/build.zig` | `link_test` 등록. `battery_test`와 같은 모양 두 자리(실행 파일 · `test_step`) |

## 이 milestone이 끝나면

- `zig build test`에 `link_test`가 더해져 돈다. 호스트에서는 `zig run terminal/src/link_test.zig`로도 돈다(std만 쓴다).
- 화면 · 상태 줄 · 로그는 하나도 안 바뀐다.

## 착수 전에 확정한 것

1. 상수는 design "착수 전에 확인한 것" 5의 값이다. 바이트 순서는 호스트 순서(`builtin.cpu.arch.endian()`)다 — netlink는 호스트 순서이고
   게스트(x86_64)와 이 맥(arm64) 둘 다 little이다.
2. 헤더 크기: `nlmsghdr` 16, `ifinfomsg` 16, `ifaddrmsg` 8, `genlmsghdr` 4, attribute 머리 4. 정렬은 4바이트.
3. dump 요청은 `RTM_GETLINK`에 `ifinfomsg`(16바이트, family 0), `RTM_GETADDR`에 `ifaddrmsg`(8바이트, family `AF_INET` 2)를 붙인다.
   flags는 `NLM_F_REQUEST | NLM_F_DUMP`(0x301).
4. `CTRL_CMD_GETFAMILY`는 genl version 1, attribute `CTRL_ATTR_FAMILY_NAME`에 `"nl80211\0"`(8바이트) — 메시지 32바이트.
   `NL80211_CMD_GET_INTERFACE`는 version 0, attribute `NL80211_ATTR_IFINDEX` u32 — 메시지 28바이트. flags는 `NLM_F_REQUEST`.
5. 표는 인터페이스 8개, 인터페이스마다 IPv4 주소 4개까지다. 넘치면 새 것을 버리고 그 사실을 돌려준다(`main.zig`가 로그로 찍는다).
6. 다시 묻기(nl80211)가 필요한 때: 처음 본 후보(ARPHRD_ETHER이고 가상이 아님), 그리고 무선으로 판정된 것이 내려갔다가 올라올 때.
   iftype 변경 자체는 이벤트로 안 온다. mac80211은 드라이버에 따라 올라간 인터페이스의 iftype도 바꾼다
   (`net/mac80211/iface.c:2082`의 `ieee80211_runtime_change_iftype`). 그래도 올라올 때마다 물으면 맞다 — mac80211은 station이
   붙기 전, AP가 시작하기 전에 carrier를 내려 두므로 operstate가 `UP`이 되는 순간은 언제나 iftype이 정해진 뒤다.
7. 칸의 `Cell`은 0으로 채운 고정 버퍼와 토막의 (시작, 길이, 색) 셋이다 — `StatusMemo`가 `std.meta.eql`로 비교하므로 slice를 담지
   않는다. 글자는 최대 `LAN` 3 + 사이 2 + SSID 32 = 37바이트.
8. SSID 정리는 바이트 하나씩 본다. ASCII는 0x20~0x7E만 두고, 여러 바이트 글자는 유효한 UTF-8이고 C1(0x80~0x9F)이 아니면 둔다.
   그 밖에는 `?`를 쓰고 한 바이트 나아간다. 출력은 입력보다 길어지지 않는다.

## 검사

| # | 무엇을 | 기대 |
|---|---|---|
| 1 | 메시지 순회 — 두 메시지(첫째 길이가 4의 배수가 아님) | 둘 다 나오고 둘째의 payload가 맞다 |
| 2 | 메시지 순회 — 길이가 남은 바이트보다 큼 · 16보다 작음 | 거기서 멈춘다 |
| 3 | attribute 순회 — 패딩 · `NLA_F_NESTED` 비트 · 잘린 attribute | 타입은 아래 14비트, 잘린 것에서 멈춘다 |
| 4 | `parseLink` — 실NIC, operstate UP | index · 이름 · ether · up · 가상 아님 |
| 5 | `parseLink` — `IFLA_INFO_KIND` "veth" · slave만(`IFLA_INFO_SLAVE_KIND`) · DORMANT · 짧은 payload | 가상 · 가상 아님 · up 아님 · null |
| 6 | `parseAddr` — `IFA_LOCAL` · `IFA_ADDRESS`만 · AF_INET6 | 주소 · 주소 · null |
| 7 | `parseInterface` · `parseFamilyId` · `parseError` | 값이 맞다 |
| 8 | 요청 넷의 바이트 | 확정 3 · 4의 바이트와 글자 그대로 같다 |
| 9 | 유선 흐름 — 후보 → 판정 요청 → 유선 → up → 주소 | 칸 없음 → `LAN`(wait) → `LAN`(ready) |
| 10 | 같은 주소 NEWADDR 두 번 + DELADDR 한 번 | 주소 0, `LAN`(wait) |
| 11 | 무선 흐름 — station up, SSID `tars-wl` | `tars-wl`(wait → ready) |
| 12 | AP가 같은 SSID로 up | 칸에 SSID가 한 번이다 |
| 13 | 둘 다 | `LAN  tars-wl`, 토막 둘의 색이 따로 |
| 14 | down · DELLINK | 칸이 사라진다, 표에서 빠진다 |
| 15 | 가상 · 비ether | 판정 요청이 없고 칸에 안 오른다 |
| 16 | station이 내려갔다가 AP로 올라옴 | 다시 묻기 요청, 칸에서 빠진다 |
| 17 | SSID attribute 없음 | `WLAN` |
| 18 | station 둘 up | ifindex가 작은 쪽 |
| 19 | 표가 참 | 아홉째는 `full` |
| 20 | `cleanSsid` — ASCII · 한글 · 깨진 바이트 · 제어 · DEL · C1 · 잘린 글자 · 33바이트 | 확정 8 |

## 할 일

1. `link.zig`를 넣는다.
2. `link_test.zig`를 넣는다.
3. `terminal/build.zig`에 등록한다.
4. 호스트에서 `zig run terminal/src/link_test.zig`, `zig fmt --check`, `make quick`.
5. 컨테이너에서 terminal의 `zig build test`(어느 명령인지는 이 단계에서 Makefile을 보고 정한다).
6. 결과를 이 plan의 끝에 적고, 사용자가 승인하면 commit한다.

## 결과 (2026-11-14)

- 새 파일 `terminal/src/link.zig` 571줄 · `terminal/src/link_test.zig` 495줄, `terminal/build.zig` +14 −0. `main.zig` · `status.zig`는 0줄.
- 호스트 `zig run terminal/src/link_test.zig`: `link_test: all 20 checks passed`. `make quick` PASS(42초).
- 컨테이너 `cd terminal && ./prepare.sh && zig build test`: `PASS`, rc=0(약 2분 22초). `zig-out/bin/link_test`도 20/20.
- mutation 넷이 예측한 검사에서 잡혔다: `IFLA_LINKINFO`만 있어도 가상으로 봄 → 5, 주소를 집합이 아니라 개수로 셈 → 10,
  올라올 때 다시 안 물음 → 11 · 16, AP의 SSID를 남김 → 12. 처음 판에서 둘이 조용했던 것은 mutation이 unused 변수 컴파일
  에러를 냈기 때문이었고(출력을 `FAIL`로만 걸렀다), 고쳐 다시 돌렸다.
- 첫 실행에서 검사 4 · 20이 빨갰다. 원인은 검사 쪽이었다 — `parsedLink`가 지역 `Builder`에 지은 메시지의 `name` slice를
  돌려줘 함수가 끝난 뒤의 스택을 읽었다. ring에 짓도록 고쳤다. `link.zig`의 `LinkMsg.name`도 같은 성질(메시지 버퍼를 가리킨다)이라
  LK-M1은 `recv` 버퍼가 살아 있는 동안 `applyLink`까지 끝내야 한다 — 표는 이름을 복사해 둔다.
- Zig 0.17에는 배열 반복 `**`이 없다 — `@splat`으로 썼다.
- 루트 게이트는 안 돌렸다. terminal 바이너리가 `link.zig`를 아직 import하지 않아 게스트 동작이 같고, 컨테이너의 `zig build test`가
  게이트가 terminal 검사로 도는 명령(`check.sh:818`) 그대로다. LK-M1에서 돌린다.
