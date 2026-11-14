# LK-M2 — 판정과 닫기

Date: 2026-11-15
Design: `docs/specs/2026-11-14-tars-link-status-design.md`
Status: 끝났다(2026-11-15). 결과는 맨 아래 "결과" 절.

## 누가 무엇을 하나

lead가 직접 한다. 사용자가 이 milestone의 결정을 전부 위임했다(2026-11-14 밤 "All decisions are up to you"). commit까지 하고
push · 소개 페이지 공개는 하지 않는다 — 밖으로 나가는 일은 사용자가 돌아와서 정한다.

## 착수 전에 확정한 것

1. 연결 판정을 `IF_OPER_UP`에서 `ifi_flags & IFF_RUNNING`으로 바꾼다. LK-M1의 루트 게이트 로그(`WN-M3-1`)에서 꽂은 usb-net이
   `state usb0 up=0 v4=1` — 주소를 받았는데 칸에 안 올랐다. 커널 문서(`Documentation/networking/operstates.rst`)는 UNKNOWN을
   "드라이버가 operstate를 안 다룬다, 쓸 수 있는 것으로 보라"고 하고, `netif_get_flags`(`net/core/dev.c:9663`)가
   `netif_running && netif_oper_up`일 때 `IFF_RUNNING`을 세운다 — `netif_oper_up`은 UP과 UNKNOWN이다(주석 "backward compat").
   DORMANT(무선이 인증을 기다린다)는 서지 않으므로 무선의 판정은 그대로다. `link.zig` · 검사 25.
2. 판정은 design 결정 10대로 기존 체인 둘에 넣는다.
   - wifi 검사 13: 부팅 A에서 `cell="tars-wl" ink ready>0 wait=0`, 그리고 칸이 `"tars-wl"` → `none` → `"tars-wl"` 순서로 바뀐다
     (검사 7의 재시작). 검사 14: 부팅 A의 칸 값은 `none`과 `"tars-wl"`뿐이다 — AP 쪽 SSID가 섞이거나(`tars-wl  tars-wl`)
     `GET_SCAN` 길이 끊겨 `WLAN`이 되면 빨갛다. 검사 15: 부팅 C(라디오 없음)는 `cell=none` 뿐이다.
   - nic 검사 9: 부팅 A의 e1000e가 `cell="LAN" ready>0`. 검사 10: 부팅 B의 꽂기 전은 `cell=none`이고 `cell="`이 없다.
     검사 11: 꽂은 usb0이 `link> if usb0 … kind=wired`이고 `cell="LAN" ready>0` — 확정 1이 지키는 자리다.
3. 체인 이름(`WL-M3` · `WN-M3`)은 그대로 둔다. PASS 줄에 링크 칸을 한 마디 더한다.
4. (첫 체인 판에서 고쳤다) 판정은 종류마다 다르다 — 무선(station · 그 밖의 무선)은 `IF_OPER_UP`, 그 밖은 `IFF_RUNNING`.
   확정 1만으로 돌린 wifi 체인의 검사 14가 빨갰다. 부팅 초기에 wlan0 · wlan1 · wlan2가 붙지도 않았는데(`scan … bss=0`) 잠깐
   `up=1`이 되어 칸에 `WLAN`이 한 프레임 섰다. 인터페이스를 켠 직후 linkwatch가 첫 상태를 정하기 전까지 operstate가 UNKNOWN이고,
   그 틈에 `IFF_RUNNING`이 선다. 무선은 wpa_supplicant가 dormant → UP을 다루므로 UP만 믿는다. 유선의 같은 틈은 usb-net과
   구별할 길이 없어 그대로 둔다(커널도 그렇게 본다). `Iface.isUp` · 검사 26.

## 할 일

1. `link.zig` · `link_test.zig`(확정 1), design 결정 2의 덧붙임.
2. `wifi/check.sh` · `nic/check.sh`(확정 2).
3. nic · wifi · net 체인. mutation 하나 — 판정을 `IF_OPER_UP`으로 되돌리면 nic 검사 11이 빨개지는가.
4. 루트 게이트.
5. 닫기(design "닫을 때"): design `Status:`, `completed.md`, `docs/help`, 기억 `project_link_status.md` · `MEMORY.md`, `HANDOFF.md`.
   소개 페이지 `data.js`는 gh-pages worktree에 commit만 하고 push는 안 한다.

## 결과 (2026-11-15)

1. 첫 체인 판: nic PASS(검사 9~11, 꽂은 usb0이 `kind=wired` → `LAN` — 확정 1이 바로 효과를 봤다), net PASS, wifi는 검사 14가 빨강
   (`the link cell showed something other than tars-wl: "WLAN"`). 원인과 고침이 확정 4다.
2. 고친 판: wifi PASS(249초) · nic PASS(160초) · net PASS. 단위 검사 26/26.
3. mutation: 유선의 판정을 `IF_OPER_UP`으로 되돌리면 nic 체인이 검사 11에서만 빨갛다
   (`the link cell never showed LAN in the ready color for the plugged usb0`) — e1000e(검사 9)는 operstate를 다루는 드라이버라 초록.
4. 루트 게이트 34/34 첫 판 PASS(2,076초, 잘린 줄 0, `out/gate-logs/20261114-153318`).
5. 도움말: `docs/help/desk.md`(상태 줄의 칸 한 줄) · `docs/help/network.md`(잘 안 되면 절의 첫 문단). `make quick` PASS.
