# WN-M2 — `init`은 dhcpcd를 띄우기만 하고, 인터페이스는 dhcpcd가 고른다

Design: `docs/superpowers/specs/2026-09-26-tars-wired-nic-design.md`(결정 4 · 6, 위험 4, 실측 12~14)
Date: 2026-09-26

## 이 milestone이 하는 일

`init/src/net.zig`가 하던 세 가지 중 둘을 뺀다.

| 지금 | M2 뒤 |
|---|---|
| `/sys/class/net/eth0`이 있나 본다 | 안 본다 — 없어도 dhcpcd가 기다린다(실측 14) |
| `SIOCGIFFLAGS` · `SIOCSIFFLAGS`로 `IFF_UP`을 세운다 | 안 한다 — dhcpcd가 올린다(실측 3) |
| `dhcpcd -o ntp_servers eth0`을 fork · `execve` | `dhcpcd -j /dev/console -o ntp_servers`를 fork · `execve` |

`init`이 찍는 줄도 둘(`net link eth0 is up` · `started dhcpcd on eth0 (pid N)`)에서
하나(`started dhcpcd (pid N), it picks the interface`)가 된다. `net` 체인의 검사 4와
`fail()`의 표지 목록이 그 줄을 따라간다.

## 이 milestone을 지배하는 사실 넷

### 1. `-j /dev/console`은 선택이 아니다

실측 12. 인터페이스 이름을 빼면 dhcpcd는 lease 전에 배경으로 가고, 배경으로 간 뒤의
로그는 syslog로 가는데 게스트에는 syslog가 없다. `-j` 없이 바꾸면 주소는 붙지만
`net` 검사 5가 기다리는 `eth0: leased 10.0.2.15`가 영영 안 나와서 빨갛다.

`-j`를 주면 줄머리에 `Sep 26 11:07:33 [78]: `이 붙는다(실측 13). 검사 5의 grep은
머리 뒤의 글자를 찾으므로 안 고친다. 배경으로 가기 전 세 줄은 두 번 찍힌다.
그 세 줄을 세는 검사는 없다.

### 2. `-b`는 안 붙인다

실측 14. NIC가 없어도, `-b`가 없어도 dhcpcd는 살아서 기다리고 꽂힌 장치를 잡는다.
manager mode가 이미 곧바로 배경으로 가므로 `-b`가 더해 주는 것이 없다. 감독 목록
밖에서 fork한다는 NW 결정 9의 갈래 A도 그대로다 — `init`은 기다리지 않는다.

### 3. 줄어드는 것이 대부분이다

`IFACE` · `SYS_IFACE` · `SIOCGIFFLAGS` · `SIOCSIFFLAGS` · `IFF_UP` · `ifreq`와 그
`comptime` 크기 검사 · `ifacePresent` · `linkUp`이 빠진다. `IFACE`는 `pub`이지만
`net.zig` 밖에서 쓰는 자리가 없다(`rg IFACE`로 확인했다). 남는 것은 `failed` ·
`DHCPCD_PATH` · `startDhcpcd` · `bringUp`이다.

`failed`가 남는 이유는 `fork`의 실패 판정이다.

### 4. hook과 TS · TD는 인터페이스 이름을 안 본다

design 위험 4의 절반은 M2 전에 닫혔다. `kernel/dhcpcd-hooks/30-tars-ntp`는
`$new_ntp_servers`만 `/run/tars/ntp_servers`에 적고 `$interface`를 안 쓴다.
`clock.zig`는 그 파일을 읽을 뿐이다. 인터페이스가 여럿이면 마지막에 lease를 받은
쪽이 파일을 덮어쓰는데, 여러 NIC의 우선순위는 design 비목표 5다.

## Task 1 — 판정을 먼저 바꾸고 옛 코드로 빨간 것을 본다

- [ ] Step 1: `net/check.sh` 검사 4를 새 줄 하나로 바꾼다

`tars-init: started dhcpcd (pid`가 있어야 하고, `tars-init: net link`는 없어야 한다.
뒤의 것은 음성이다 — `init`이 링크를 다시 만지는 날을 잡는다. 주석은 경계가 옮겨간
것을 적는다. 우리 코드는 dhcpcd를 띄우는 것뿐이고, 링크를 올리고 인터페이스를
고르는 것은 dhcpcd다.

- [ ] Step 2: `fail()`의 표지 목록에서 두 줄을 새 줄 하나로 바꾼다
- [ ] Step 3: `net` 체인 한 판 (약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh > /tmp/wn/m2-red.log 2>&1; echo "exit=$?"
grep -a '^FAIL' /tmp/wn/m2-red.log
```

기대: `exit=1`이고 `FAIL: init did not do its half of the work` 계열이 검사 4에서
나온다. 옛 코드는 `started dhcpcd on eth0 (pid N)`이라 새 패턴 `started dhcpcd
(pid`에 안 걸린다.

## Task 2 — `net.zig`를 줄인다

- [ ] Step 1: 사실 3의 목록을 지운다
- [ ] Step 2: `startDhcpcd`의 argv를 `DHCPCD_PATH, "-j", "/dev/console", "-o",
  "ntp_servers", null`로 바꾸고, 주석에 실측 12 · 13(왜 `-j`인가)과 사실 2(왜 `-b`가
  없는가)를 적는다. `-o ntp_servers`의 긴 주석은 그대로 둔다.
- [ ] Step 3: 부모가 찍는 줄을 `tars-init: started dhcpcd (pid {d}), it picks the
  interface`로 바꾼다
- [ ] Step 4: `bringUp`에서 `ifacePresent` · `linkUp` 호출을 빼고, doc 주석에 NIC가
  없어도 dhcpcd를 띄우는 이유(결정 6 · 실측 14)를 적는다
- [ ] Step 5: 빌드와 diff

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build && echo "init build OK"
git diff --stat init/
git diff init/ | grep '^-' | grep -v '^---'
```

기대: 빌드가 경고 없이 된다(Zig은 안 쓰는 상수를 에러로 내지 않지만 안 쓰는 지역
변수는 에러로 낸다). 지운 줄은 사실 3의 목록과 바꾼 argv · 로그 두 줄뿐이다.

## Task 3 — 주석 둘

- [ ] `check.sh:277`의 "우리 코드가 하는 일은 로그 두 줄이 전부다(net link eth0 is up ·
  started dhcpcd on eth0)"를 새 경계로 고친다
- [ ] `init/src/clock.zig:288`의 "`net.zig`의 `started dhcpcd on eth0 (pid N)`과 짝이
  되는 자리"를 새 줄로 고친다

## Task 4 — `net` 체인 초록 (약 2분)

Task 1 Step 3과 같은 명령에 로그만 `/tmp/wn/m2-green.log`로 바꾼다.

기대: `exit=0`. 그리고 로그에서 둘을 본다.

```bash
grep -a 'tars-init: started dhcpcd\|tars-init: net link' /tmp/wn/m2-green.log
grep -a 'eth0: leased' /tmp/wn/m2-green.log | head -2
```

첫 줄은 `started dhcpcd (pid N), it picks the interface`이고 `net link`는 없다.
둘째는 `Sep … [pid]: eth0: leased 10.0.2.15 …` 모양이다. 부팅이 다섯이라 다섯 번 나올
수 있다.

## Task 5 — 루트 게이트 3/3 (약 41분)

`net=dhcp`로 뜨는 것은 `net` 체인뿐이다(`rg -l net=dhcp`). 다른 체인은 `bringUp`이
`off` 갈래에서 끝나므로 바뀐 코드를 안 밟는다. 그래도 `init`이 바뀌었으므로
게이트를 돈다. 기준선은 M1의 40분 37.55초다.

백그라운드 완료 알림이 실행 직후에 오는 일이 이 세션에 있었다(M1). 판정은
`pgrep -f 'tars-devcontainer bash check.sh'`가 비는 것을 보고 한다.

## Task 6 — 문서와 커밋

- design: `Status:`와 "WN-M2가 실행으로 증명한 것"(빨강 한 판 · 초록 한 판 · 게이트)
- `HANDOFF.md`: 다음은 M3 plan(`nic/check.sh`)
- 커밋 하나
