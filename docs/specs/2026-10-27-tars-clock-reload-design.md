# TARS Clock Reload — Design

Date: 2026-10-27
Status: 끝났다 — CR-M0(2026-10-28, 루트 게이트 22/22). plan은 `docs/plans/2026-10-28-tars-clock-reload-cr-m0.md`. 기억은 `docs/decisions/project_clock_reload.md`.

`docs/guides/carryover.md`(이월 숙제)의 "chronyd의 reload(`ntp` 키)를 게이트가 안 본다" 항목을 닫는다(사용자가 2026-10-27에
골랐다). HANDOFF "다음 후보"의 "실기 없이 할 수 있는 것" 첫째다.

## 한 줄 요약

net 체인의 부팅 A(ntp=10.0.2.2, stub이 있는 부팅) 끝에 `tars-config set ntp=…` · `tars-config reload`를 세 번 쳐서, reload가
chronyd를 다시 띄우고(restart) · 멈추고(stop) · 새로 띄우는(start) 세 길을 게스트에서 한 번씩 밟는다. 코드는 바뀌지 않는다 —
`net/check.sh`에 검사 하나(32)가 는다.

## 배경

TC-M2가 `reload` 동사를 세울 때 net 검사 31은 `net` 키만 밟았다(TC-M2 plan 확정 4). 그 부팅의 디스크(`out/net.img`)에는
ntp가 없어서 chronyd 칸이 처음부터 꺼져 있기 때문이다. 그래서 `doReload`의 ntp 갈래는 게이트가 한 번도 지나지 않는다.

덮인 것과 안 덮인 것:
- 덮였다: `reload.step`의 네 갈래(`reload_test`, 호스트). `clock.prepare`가 짓는 설정의 글자(`clock_test`, 호스트). 부팅이
  `clock.prepare`를 부르는 길(net 검사 17 · 18).
- 안 덮였다: `doReload`가 `keys.has("ntp")`를 보고 `clock.prepare`를 다시 부르고, 그 답을 `steer`에 `rewrote`로 넘기는 배선.
  이 배선이 틀리면(예: `rewrote`에 `false`를 넘긴다) `ntp=1.2.3.4`로 바꾼 reload가 옛 서버를 계속 묻는 chronyd를 남기는데,
  호스트 검사는 그 실수를 못 본다.

## 착수 전에 확인한 것

2026-10-27, HEAD `64e2a0d`.

1. `doReload`(`init/src/main.zig`)의 ntp 갈래는 다음 두 줄이다. `net` 또는 `ntp`가 바뀌었을 때만 돈다.
   ```zig
   const want_chronyd = clock.prepare(new.net, new.ntp, live.mounted);
   steer(&children[SLOT_CHRONYD], reload.step(!children[SLOT_CHRONYD].config_off, want_chronyd, want_chronyd), now, out);
   ```
   `clock.prepare`는 원할 때 `/run/tars/chrony.conf`를 먼저 다시 쓰므로 `rewrote`는 `want_chronyd`와 같다.
2. `reload.step(was, now, rewrote)`의 답은 셋이 의미가 있다 — 꺼짐→켬은 `start`, 켬→꺼짐은 `stop`, 켬→켬(파일을 다시 씀)은
   `restart`. 부팅 A는 chronyd가 켜진 채로 시작하므로 세 길을 모두 밟으려면 reload가 셋 필요하다.
3. `steer`가 남기는 것. 화면에는 `service chronyd: starts|stops|restarts`(칸의 label이 `services.LABEL_PREFIX ++ "chronyd"`),
   시리얼에는 `tars-init: reload: service chronyd start|stop|restart`. 감독 루프는 멈춘 것을 거둘 때
   `tars-init: service chronyd stopped on request`, 새로 띄울 때 `tars-init: started service chronyd (pid N`을 찍는다.
4. `tars-config set`의 답은 `ntp: 10.0.2.2 -> dhcp` 꼴이다(`config_edit`의 `key: old -> new`). 검사 31이 같은 꼴의 `net:`
   줄을 화면에서 기다린 뒤 reload를 친다(TC-M2 Task 5b) — 같은 순서를 따른다.
5. SLIRP의 DHCP 응답에는 option 42가 없다. 그래서 `ntp=dhcp`로 바꾸면 hook이 `/run/tars/chrony.sources`를 만들지 않고, 다시 뜬
   chronyd는 서버 없이 산다. 부팅 B의 검사 31(DS-M2)이 같은 상태를 이미 본다 — 살아 있는 것은 정상이다.
6. 부팅 A의 마지막 검사는 30(`tars-service restart chronyd` 뒤에 `Selected source`가 하나 더)이고, 그 뒤에 전원을 끈다.
   chronyd가 다시 서버를 골랐다는 증거로 같은 줄의 개수를 쓰는 선례다.
7. 곁에서 본 것. `init/src/power.zig`의 `resetToDefault` 문서 주석이 "`clock.zig`의 자식이 `ntp=dhcp`면 서버 파일을 최대
   30초 기다린 뒤에 chronyd가 된다"고 말한다. 지금 chronyd는 감독 목록에서 `CHRONYD_ARGV`로 곧바로 exec되고(DS-M1), 그렇게
   기다리는 자식은 없다. 낡은 주석이다.

## 결정

### 결정 1. 부팅 A에 얹는다

새 부팅을 만들지 않는다. 부팅 A는 이미 chronyd가 10.0.2.2를 고른 상태이고, 그 서버에 답하는 stub이 떠 있다. start 길의 증거
(`Selected source` 한 줄 더)를 얻으려면 답하는 서버가 있어야 하는데, 그런 부팅은 A뿐이다.

자리는 검사 30 뒤, 전원을 끄기 전이다. 검사 30이 남긴 chronyd(10.0.2.2를 고른 것)에서 출발한다.

### 결정 2. reload 셋의 순서 — `dhcp` → `off` → `10.0.2.2`

| 차례 | set | 기대하는 `steer` | 증거 |
|---|---|---|---|
| a | `ntp=dhcp` | `restart` | 화면 `service chronyd: restarts` · 새 pid의 `started service chronyd` · 설정 파일에 `sourcedir` |
| b | `ntp=off` | `stop` | 화면 `service chronyd: stops` · 시리얼 `service chronyd stopped on request` |
| c | `ntp=10.0.2.2` | `start` | 화면 `service chronyd: starts` · `Selected source 10.0.2.2`가 하나 더 |

이 순서를 고른 이유:
- 끝이 처음과 같다(ntp=10.0.2.2, chronyd가 서버를 고름). 뒤의 전원 끄기 검사("grace period expired"가 없다)가 지금과 같은
  상태에서 돈다.
- restart를 먼저 밟는다. 셋 중 `rewrote`를 쓰는 것은 restart뿐이라 배경의 "틀릴 수 있는 배선"이 여기서 갈린다.
- a의 설정 파일 판정. 시리얼만 보면 "init이 파일을 다시 썼다고 말했다"까지다. 화면에서
  `echo cr$(grep -c sourcedir /run/tars/chrony.conf)`를 쳐서 `cr1`을 본다 — 판정 글자가 명령줄에 없다(NW-M3 실측 2, 검사 19 ·
  31과 같은 방법).
- c의 증거는 검사 30과 같은 방법이다. 꺼졌다가 새로 뜬 chronyd가 다시 쓴 파일(`server 10.0.2.2`)을 읽고 stub을 믿었다는 것이
  `Selected source` 한 줄 더다.

검토한 다른 길:
- (b) `ntp=10.0.2.2` → 다른 주소로 바꿔 restart를 본다. SLIRP 안에서 stub에 닿는 주소는 10.0.2.2 하나라 다른 주소로 바꾸면
  "다시 떴다"까지만 보이고, 되돌리는 reload가 하나 더 든다. `dhcp`는 주소 없이 같은 것(파일의 글자가 바뀜)을 본다.
- (c) restart만 본다. start · stop은 net 키 쪽(검사 31의 dhcpcd)에서 이미 같은 `steer`를 지난다. 하지만 chronyd 칸은
  `clock.prepare`의 답을 받는 자리가 따로라, 그 배선을 셋 다 보는 비용(reload 둘, 수 초)이 작다.

### 결정 3. 진단

검사 31의 `nw_reload_diag`와 같은 일을 한다 — 마지막 화면, `cat /config/tars.conf`, 마지막 `reload of` 뒤의 tars-init 줄.
함수를 일반화하지 않고 부팅 A의 `$LOG`(= `$LOGA`)에서 그대로 부른다. 그 함수는 전역 `$LOG`만 보므로 부팅 A에서도 맞는 로그를
읽는다.

### 결정 4. 번호와 문서

- 검사 번호는 32다. 31은 두 자리(부팅 0의 TC-M2 · 부팅 B의 DS-M2)가 이미 쓴다. 번호는 자리가 아니라 이름이다(TS-M3 plan
  결정 M3-F).
- 머리 주석의 부팅 A 줄거리(`net/check.sh` 43행 근처)에 "reload가 chronyd를 세 번 바꾼다"를 한 줄 더한다.
- `carryover.md`에서 이 항목을 지운다.
- 착수 전 확인 7의 낡은 주석(`power.zig`)을 함께 고친다 — 주석만, 동작 0줄.

### 결정 5. 검증

- net 체인 단독으로 먼저 초록을 본다(LE-M0 루트 게이트 안에서 181초).
- mutation 하나. `doReload`의 `steer` 줄에서 `rewrote`를 `false`로 바꾸면 차례 a가 `restarts` 대신 아무 줄도 안 남겨 빨개지는지
  본다. 본 뒤 되돌린다(commit하지 않는다).
- 루트 게이트 22/22(약 10~12분).

## Milestone

하나다(CR-M0). Task 둘, Task마다 commit 하나.

1. 검사 32와 머리 주석, `power.zig` 주석.
2. mutation과 루트 게이트를 본 뒤 `carryover.md`에서 항목을 지운다(문서만).

## 위험

1. 차례 c의 `Selected source`가 늦을 수 있다. 부팅 A에는 gate.conf가 없어 폴링이 기본값이다. 다만 `iburst`라 첫 선택은 수 초
   안이고, 검사 30이 같은 대기(30초)로 초록이다. 같은 창을 쓴다.
2. 차례 a의 새 chronyd가 서버 없이 사는 동안 stub에 아무것도 안 보낸다. stub의 답 수(전원을 끈 뒤 찍는 `answered N`)는
   판정이 아니라 사람이 보는 숫자라 영향이 없다.
3. 검사 31(부팅 0)의 간헐과 같은 창. set의 답을 화면에서 보고 reload를 치므로 같은 방어를 갖는다. 빨개지면 결정 3의 진단으로
   "set이 안 됐다"와 "reload가 안 됐다"를 가른다.
4. net 체인이 수십 초 길어진다(reload 셋 + `Selected source` 대기). net은 이미 가장 긴 체인이다(LE-M0 루트 게이트에서 TD-M2
   181초, 다음이 CP-M2 180초, lanes 291초). 그래서 늘어난 만큼 lanes가 늘 수 있다. 판정 대기를 짧게 끊지 않고, 늘어난 수를
   루트 게이트의 시간 표에서 재어 기억에 남긴다.

## 비목표

1. `timezone` 등 다른 키의 reload를 게이트에 더하는 것. carryover에 없고, 사용자가 실기에서 보기로 한 목록(HANDOFF "사용자가
   확인할 것"의 TC)에 있다.
2. `ntp=dhcp`에서 hook이 reload 뒤의 chronyd에 서버를 알려 주는 길. SLIRP가 option 42를 안 주므로 게이트 안에서 밟을 수 없다
   (부팅 B가 심은 파일로 "파일 → chronyd" 조각만 본다).
3. `doReload`의 코드 변경. 이번은 보는 것만 더한다.
