# TARS Firewall — Design

접두사: FW

Status: M0 끝났다(2026-09-27) — 실측 1~9. 다음은 M1.

관련 문서: `2026-09-14-tars-inbound-network-design.md`(IN. 비목표 1 · 2 · 4가 이
서브프로젝트의 범위다) · `2026-09-13-tars-guest-network-design.md`(NW. 비목표 3이
방화벽이다) · `2026-09-26-tars-time-discipline-design.md`(TD. `init`은 배관만 한다는
방향과 `/config/chrony.d/`의 모양) · `2026-09-26-tars-loopback-design.md`(LB. `lo`가
늘 선다) · `docs/decisions/feedback_boot_never_blocks.md` ·
`docs/decisions/project_write_or_reuse.md`.

## 한 줄 요약

`tars.conf`에 `firewall=on`을 적은 기계는 들어오는 것을 기본으로 버리고, 사람이
`/config/nftables.d/*.nft`에 적은 것만 받는다. 규칙을 커널에 넣는 것은 `nft`이고
`init`은 순서와 실패 처리만 맡는다. 게이트는 TCP 둘과 UDP 둘 — 연 것과 안 연 것 —
로 판정한다.

## 왜 지금인가

IN이 "게스트가 연 포트에 바깥에서 붙는다"를 증명했다. 그 말은 곧 게스트가 연
것은 무엇이든 받는다는 뜻이다. 게이트 안에서는 `hostfwd`가 `127.0.0.1`에 묶여
있어 문제가 없지만, WN · DI가 선 지금 TARS는 실기 노트북에서 LAN에 붙을 수 있다.
그 자리에서 무엇을 받을지를 고르는 층이 없다.

IN 비목표 셋이 이 자리에 모인다. 방화벽이 있으면 "이 포트는 받고 저 포트는
버린다"를 증명하는 데 포트 여럿이 필요하고, "TCP는 막았는데 UDP는 새는가"를 보는
데 UDP가 필요하다. 따로 하면 IN의 반복이지만 방화벽 아래에서는 판정의 재료가 된다.

2026-09-27에 사용자가 후보(패키지 매니저 · 부팅 때 뜨는 서비스 · IPv6 · UDP ·
포트 여럿 · 방화벽) 중에서 마지막 묶음을 골랐고, 셋을 정했다 — 중심은 방화벽,
기본은 꺼짐이고 켜면 닫힘, 포트는 `/config`의 nft 파일로 연다. 아래 결정 1 · 3 ·
4가 그 셋이다.

## 착수 전에 읽은 것 — 부팅은 한 번도 안 했다

### 확인 1 — 커널에 netfilter가 한 줄도 없다

`kernel/.config` 828행이 `# CONFIG_NETFILTER is not set`이다. NW design이 이 줄을
인용해 방화벽을 뺐다. 그래서 규칙을 올릴 자리(hook)가 지금 커널에 없다.

### 확인 2 — 게스트에 `nft`가 없다

`kernel/guest_tools.sh`에도 Dockerfile의 sysroot 층에도 `nftables`가 없다.
dhcpcd(층 5) · chrony(층 8) · `libnss-myhostname`(층 9)과 같은 길로 들어와야 한다.

### 확인 3 — `init`이 외부 도구를 부르는 모양이 둘 있다

`net.zig`의 dhcpcd는 `fork` · `execve` 뒤 안 기다린다(감독 목록 밖, `reapAll()`이
거둔다). `clock.zig`의 chronyd도 같다. 둘 다 네트워크를 기다리는 도구라 안
기다리는 것이 맞았다. `nft`는 로컬 netlink만 쓰므로 기다려도 부팅이 네트워크에
묶이지 않는다 — 이번에 처음으로 `waitpid`로 기다리는 외부 도구가 된다.

### 확인 4 — 사람이 설정을 적는 디렉터리의 선례가 있다

TD가 `/config/chrony.d/`를 만들었다. chronyd가 `confdir`로 읽고 `init`은 그 안을 안
본다. 이번 `nftables.d`도 같은 모양이다.

### 확인 5 — SLIRP은 막힌 포트에도 연결을 성공시킨다

IN 실측 4. 체인이 `hostfwd` 포트에 붙으면 게스트가 버려도 체인 쪽 `connect`는
성공한다. 그래서 판정은 IN처럼 읽은 바이트 수여야 하고 `rc`로는 못 가른다.

### 확인 6 — `inet` 표는 IPv6 없이 못 만든다

`net/netfilter/Kconfig`의 `NF_TABLES_INET`이 `depends on IPV6`다. `NF_CONNTRACK`은
`NETFILTER_ADVANCED=n`이면 기본이 `m`인데 우리 커널은 `# CONFIG_MODULES is not
set`이라 tristate가 전부 `y`로 해소될 것으로 본다(M0이 `olddefconfig` 결과로 본다).

## 결정

### 결정 1 — 기본은 꺼짐. `firewall=on`이면 켜지고, 켜지면 닫힌다

`tars.conf`의 새 키 `firewall`(값 `on` · `off`, 기본 `off`). 키를 안 적은 기계는 한
글자도 안 바뀐다 — `net` · `ntp` · `timezone`과 같은 관례이고, IN의 `net` 체인
검사들이 그대로 산다. 켜면 들어오는 방향의 정책이 `drop`이다.

`net=off`인데 `firewall=on`이어도 올린다. `lo`는 LB 이후 늘 있고, 규칙이 선 뒤에
사람이 셸에서 NIC를 올릴 수도 있다.

### 결정 2 — 규칙을 넣는 것은 `nft`다. `init`은 배관만 한다

접근 셋을 비교했다. 셸 스크립트가 올리는 것(부팅 경로에 처음으로 셸이 끼어든다)과
`init`이 nf_tables netlink를 직접 말하는 것(규칙 하나가 바이트코드 VM 명령 여러
개다 — `project_write_or_reuse`의 기준으로 dhcpcd와 같은 자리다)을 뺐다.
`init`은 `fork` → `execve("/usr/bin/nft", "-f", 기본 파일)` → `waitpid`다.
규칙의 의미는 전부 nft 파일 안에 있다.

### 결정 3 — 기본 규칙 파일 하나를 initrd에 굽는다

```
table ip tars {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ct state invalid drop
    include "/config/nftables.d/*.nft"
  }
}
```

- 받는 방향(input)만 거른다. 나가는 방향(output)과 forward는 안 만든다.
- `ct state established,related`가 나간 연결의 답(dhcpcd의 lease 갱신 · chrony의
  NTP 답 · curl)과 ICMP 오류를 받는다. ping은 사람이 열어야 받는다.
- 계열은 `ip`(IPv4)다. 처음에는 IPv6까지 한 표로 거르는 `inet`을 적었는데, 커널의
  `NF_TABLES_INET`이 `depends on IPV6`이고 우리 커널은 `# CONFIG_IPV6 is not set`이다
  (확인 6). IPv6를 켜는 것은 비목표 2라서 `ip`로 둔다. 대가는 위험 6이다.
- 자리는 `/etc/tars/firewall.nft`. 사람이 파일 전체를 바꾸는 길은 두지 않는다 —
  바꾸고 싶은 것은 `nftables.d`에 적는다.

### 결정 4 — 포트는 사람이 `/config/nftables.d/*.nft`에 nftables 문법으로 연다

include가 chain 블록 안에 있으므로 파일 한 줄이 규칙 한 줄이다.

```
tcp dport 8080 accept
udp dport 5353 accept
```

`tars.conf`에 포트 목록 키를 두지 않는다 — 파서와 규칙 생성이 우리 코드가 되고
출발지 제한 같은 표현력이 없다. `/config`가 안 붙은 부팅은 include가 아무것도
못 찾으므로 닫힌 기본 규칙만 선다(glob이 빈 것을 nft가 에러로 보는지는 M0이 잰다).

### 결정 5 — 순서는 `net.bringUp` 앞이고, 실패하면 닫힌 채로 끝난다

`firewall=on`이면 `init`은 `net.bringUp` 앞에서 `nft`를 기다린다. 규칙이 서기
전에 주소가 붙는 틈을 없애기 위해서다.

실패 처리의 갈래 셋. 각 갈래가 로그 한 줄을 남긴다(`boot_never_blocks`의 "침묵으로
때우지 않는다").

1. 성공 — `firewall up, N rule files` 모양의 한 줄.
2. 사람이 쓴 파일 때문에 실패(문법 오류 등) — include 없는 기본 규칙을 다시
   올린다. 규칙 파일은 initrd에 따로 하나 더 굽는다(`/etc/tars/firewall-base.nft`).
   결과는 닫힌 기계이고, 로그가 "사람의 파일을 무시했다"고 말한다. nft의 stderr는
   콘솔로 흘려 사람이 몇 행이 틀렸는지 보게 한다.
3. 기본 규칙도 실패(`nft`가 없음 · 커널 옵션 모자람) — 열린 채로 부팅이 끝나고
   로그가 그것을 크게 말한다. 네트워크를 막는 쪽(fail-closed로 `bringUp`을
   건너뛰기)도 생각했지만, 이 갈래는 우리 빌드가 틀린 것이라 게이트가 잡을 일이고,
   사람의 기계에서 네트워크를 통째로 잃게 하는 값이 더 크다.

`firewall=off`이면 `nft`를 안 부르고 한 줄(`firewall off`)만 남긴다.

### 결정 6 — 게이트는 열다섯번째 체인 `firewall/check.sh`다

`net` 체인은 이미 부팅 다섯에 검사 서른이다. 이번 부팅은 설정이 달라(`firewall=on`
과 `nftables.d`를 심는다) 한 부팅을 나눠 쓸 수도 없다. 새 체인으로 둔다.

- 부팅 A — `net=dhcp` · `firewall=on`, `nftables.d/allow.nft`가 TCP A와 UDP B를
  연다. 게스트는 넷(TCP A · TCP C · UDP B · UDP D)을 다 듣는다.
  - TCP A — 체인이 바이트를 읽는다(양성).
  - TCP C — 듣고 있는데 0바이트다(음성).
  - UDP B — 체인이 보낸 글자가 게스트 화면에 뜬다(양성).
  - UDP D — 안 뜬다(음성).
  - `nft list ruleset`에 기본 표가 있다. 나가는 방향이 산다 — dhcpcd가 lease를 받는다.
- 부팅 B — 같은 설정에 문법 오류 파일 하나를 심는다. 셸이 평소 자리에서 뜨고,
  로그에 갈래 2의 줄이 있고, TCP A가 막혔다.
- 꺼진 기본값은 기존 `net` 체인의 IN 검사(열린 포트에서 바이트를 읽는다)가
  그대로 지킨다.

판정의 재료(연 포트 목록)를 판정 대상(규칙 파일)과 따로 둔다(LB 실측 17).
반사실 — 기본 규칙에서 `policy drop`을 빼면 TCP C · UDP D가 빨개지고,
`allow.nft`를 빼면 TCP A · UDP B가 빨개지는 것을 M1 · M2가 본다.

## Milestone

- FW-M0 — 재기만 한다. 커널 옵션의 최소 집합 · `nft`의 비용(재귀 `DT_NEEDED`) ·
  `policy drop` 아래에서 dhcpcd와 chronyd가 사는가(DHCP는 raw socket이라 input
  hook 앞일 것으로 짐작한다) · UDP `hostfwd`가 게스트에 닿는 모양 · 빈 include
  glob이 에러인가 · 막힌 TCP에서 체인이 읽는 바이트가 0인가.
- FW-M1 — 커널 옵션 · `nft` · `firewall` 키 · `init` 배관 · 기본 규칙 두 파일.
  새 체인의 부팅 A 중 TCP 양성 · 음성.
- FW-M2 — `nftables.d`의 UDP · 포트 여럿 · 부팅 B(갈래 2) · 사용자 가이드
  (`docs/guides/running-tars.md`에 방화벽 절).

## 비목표

1. 나가는 방향 필터. 받는 것을 고르는 것과 나가는 것을 막는 것은 다른 이야기다.
2. IPv6. 커널에 없다. 들어오는 사이클이 표를 `inet`으로 바꾼다(위험 6).
3. 실머신 LAN에서의 판정. 게이트는 SLIRP 안에서 닫힌다(IN 비목표 3과 같다).
4. NAT · forward · 라우팅.
5. 부팅 중 규칙 다시 읽기. 사람이 셸에서 `nft -f`를 치면 된다.
6. `tars.conf`의 포트 목록 키. 결정 4가 뺐다.
7. 부팅 때 뜨는 서비스. 방화벽이 여는 포트를 쓸 주체이지만 별개의 서브프로젝트다.

## 위험

### 위험 1 — `policy drop`이 dhcpcd나 chronyd를 죽인다

DHCP OFFER는 브로드캐스트로 올 수 있어 conntrack이 짝을 못 찾을 수 있다. dhcpcd가
raw socket으로 받으면 input hook 앞이라 무관하다. M0이 잰다. 죽으면 기본 규칙에
`udp sport 67 udp dport 68 accept`를 더하는 것이 처방 후보다.

### 위험 2 — 커널 옵션이 생각보다 많다

`nft`는 없는 표현식을 `Operation not supported`로 알린다. M0이 기본 규칙을 올려
보면서 하나씩 켠다. 모듈이 아니라 `=y`로 켠다(initrd에 모듈 로더가 없다).

### 위험 3 — `nft`가 끌고 오는 라이브러리가 크다

`libnftables` · `libnftnl` · `libmnl` · `libjansson` · `libxtables` · `libgmp` ·
`libedit` 후보. `project_measuring_tool_cost`의 절차로 잰다.

### 위험 4 — UDP `hostfwd`의 판정이 화면에 달린다

UDP는 연결이 없어 체인 쪽에서 "읽은 바이트"가 없다. 게스트 `nc -u -l`이 받은
글자를 화면에 내는 것으로 판정하고, `project_gate_screen_echo`대로 판정 글자는
체인이 친 명령에 안 나오게 만든다.

### 위험 5 — 이 사이클이 증명하는 것보다 넓게 읽힌다

증명하는 문장은 "SLIRP 안에서 규칙이 받는 것과 버리는 것을 가른다"이다. 실기
LAN에서의 동작은 같은 커널 경로를 탈 것으로 보지만 게이트가 보지는 않는다.

### 위험 6 — IPv6가 들어오면 v6는 안 걸러진다

표가 `ip`라 IPv4만 본다. 지금은 커널에 IPv6가 없어 구멍이 없다. IPv6를 켜는
사이클이 `CONFIG_NF_TABLES_INET`을 켜고 표를 `inet`으로 바꿔야 한다. 그 사이클의
design이 이 위험을 첫 확인으로 인용해야 하고, `firewall/check.sh`에 v6 음성 검사를
더하는 것이 그 사이클의 몫이다.

## FW-M0이 실행으로 증명한 것

plan은 `plans/2026-09-27-tars-firewall-fw-m0.md`. 부팅 하나(`net=dhcp`, SLIRP에
`hostfwd` 넷)에서 규칙을 올리기 전(`pre`)과 후(`post`)를 같은 탐침으로 쟀다. 커널
옵션은 작업 트리에서만 켜고 되돌렸다. 커밋되는 코드는 0줄이다.

### 실측 1 — 다섯을 켜면 열이 따라오고 전부 `=y`다

`scripts/config -e NETFILTER -e NF_TABLES -e NF_TABLES_IPV4 -e NF_CONNTRACK -e NFT_CT`
뒤 `olddefconfig`가 더한 것.

```
> CONFIG_NET_CRC32C=y          > CONFIG_NETFILTER_NETLINK=y
> CONFIG_NET_EGRESS=y          > CONFIG_NF_CT_PROTO_SCTP=y
> CONFIG_NET_INGRESS=y         > CONFIG_NF_CT_PROTO_UDPLITE=y
> CONFIG_NETFILTER_ADVANCED=y  > CONFIG_NF_DEFRAG_IPV4=y
> CONFIG_NETFILTER_EGRESS=y    > CONFIG_NETFILTER_INGRESS=y
```

`=m`은 0줄이다(`# CONFIG_MODULES is not set`이라 tristate가 `y`로 해소된다 — 확인 6).
`NETFILTER_ADVANCED`는 Kconfig 기본값이 `y`라 저절로 켜졌다. 메뉴를 넓히는 스위치라
코드가 늘지 않는다. bzImage는 5,030,912바이트. 위험 2는 닫혔다 — M1은 이 다섯을
켜고 해소본을 커밋한다(WN과 같은 관례).

### 실측 2 — `nft`가 initrd에 더하는 것은 다섯, 1,386,600바이트다

재귀 `DT_NEEDED` 열둘 중 여덟(`libc` · `ld-linux` · `libedit` · `libgmp` · `libmnl` ·
`libtinfo` · `libbsd` · `libmd`)이 initrd에 이미 있다. 새것은 다섯이다.

| 파일 | 바이트 | 패키지 |
|---|---|---|
| `nft` | 26,776 | `nftables 1.1.3-1` |
| `libnftables.so.1` | 1,015,256 | `libnftables1 1.1.3-1` |
| `libnftnl.so.11` | 217,312 | `libnftnl11 1.2.9-1` |
| `libxtables.so.12` | 67,504 | `libxtables12 1.8.11-2` |
| `libjansson.so.4` | 59,752 | `libjansson4 2.14-2+b3` |

압축 전 initrd(111,232,000바이트)의 1.25%다. 위험 3은 닫혔다. sysroot 층에 없는
패키지 넷(`nftables` · `libnftables1` · `libnftnl11` · `libxtables12` · `libjansson4`)을
M1이 Dockerfile에 더한다. `libxtables`는 nft가 옛 `iptables` 확장을 해석하려고
링크할 뿐 우리 규칙은 안 쓴다 — 그래도 `NEEDED`라 빼면 nft가 안 뜬다.

plan Task 2 Step 2의 `cpio -t < initrd.cpio`는 0줄을 냈다. initrd가 gzip이다
(`make_initrd.sh` 461행). `zcat initrd.cpio | cpio -it`로 다시 봤다.

### 실측 3 — 기본 규칙이 이 커널에 그대로 올라간다

```
FWM0-LOAD file=/tmp/fw/base.nft rc=0 err=[;]
FWM0-RULES table ip tars { chain input { type filter hook input priority filter; policy drop;
  iif "lo" accept; ct state established,related accept; ct state invalid drop;
  tcp dport 7070 accept; udp dport 7071 accept; }; };
```

include한 파일의 두 줄이 chain 안에 펼쳐져 있다 — 결정 4의 "파일 한 줄이 규칙 한
줄"이 그대로다. nft는 `priority 0`을 `priority filter`라는 이름으로 되돌려 보여 준다.

### 실측 4 — include glob은 디렉터리가 없어도, 비어도 에러가 아니다

`/tmp/nftables.d`를 지운 채로, 빈 채로 두 번 올려 둘 다 `rc=0`이고 기본 세 줄만
섰다. 그래서 M1의 `init`은 `/config`가 안 붙은 부팅이나 `nftables.d`가 없는 기계를
따로 다루지 않는다 — 같은 파일 하나를 늘 올린다.

### 실측 5 — `policy drop` 아래에서 DHCP가 처음부터 다시 서고, 나가는 길의 답이 온다

```
FWM0-OUTUDP rc=0 got=[ECHO-FWM0OUTU]
FWM0-OUTTCP rc=0 got=[ECHO-FWM0OUTT]
FWM0-FLUSHED 0
FWM0-DHCP rc=0 secs=5 addr=[10.0.2.15/24]
```

규칙을 올린 뒤 `dhcpcd -x`로 manager를 멈추고 주소를 비운 다음 `dhcpcd -1 -4 eth0`로
DISCOVER부터 다시 했다. 5초에 같은 주소다. 그 뒤의 나가는 UDP · TCP(컨테이너의
perl echo)도 답을 받았다. 위험 1은 닫혔다 — 67→68 허용 줄은 필요 없다. dhcpcd가
raw socket으로 받아 input hook 앞이라는 짐작과 맞지만, 이 측정이 가르는 것은
결과이고 경로는 아니다.

### 실측 6 — 막힌 TCP는 연결되고 0바이트이며, SLIRP은 안 끊는다

```
FWM0-PROBE pre  tcp 45472 connected rc=0   bytes=8 got=[FWM0TCPC] ms=3
FWM0-PROBE post tcp 45470 connected rc=0   bytes=8 got=[FWM0TCPA] ms=22
FWM0-PROBE post tcp 45472 connected rc=142 bytes=0 got=[]         ms=5012
```

`rc=142`는 bash `read -t`의 타임아웃(128+14)이다. 확인 5대로 `connect`는 늘 성공하므로
판정은 `bytes`다. SLIRP은 게스트가 SYN을 버려도 체인 쪽 연결을 끊지 않아, 음성
판정 하나가 읽기 타임아웃을 꽉 쓴다. M1 체인의 음성 검사는 타임아웃을 짧게(2초 —
IN의 음성 검사와 같은 값) 두고, 양성 22ms와의 간격이 넉넉하다는 것이 근거다.

### 실측 7 — UDP도 연 것만 닿는다

```
FWM0-UDPB [FWM0UDPpre45471]    FWM0-UDPD [FWM0UDPpre45473]     (규칙 전)
FWM0-UDPB [FWM0UDPpost45471]   FWM0-UDPD []                    (규칙 후)
```

게스트의 `nc -u -l`이 파일에 받고 스크립트가 표지 뒤에 낸다. 표지 글자는 컨테이너가
보낸 것이라 게스트에 친 명령에 없다(위험 4). M2의 UDP 판정은 이 모양이다.

### 실측 8 — `nft -f`는 원자적이다. 문법 오류는 아무것도 안 바꾼다

```
FWM0-LOAD file=/tmp/fw/base.nft rc=1 err=[In file included from /tmp/fw/base.nft:9:5-36:;
  /tmp/nftables.d/bad.nft:1:21-21: Error: syntax error, unexpected newline;tcp dport 7072 acept; ^;]
FWM0-RULES (load 때와 같다 — tcp dport 7070 · udp dport 7071이 그대로)
```

좋은 규칙이 선 상태에서 include에 틀린 파일을 넣고 다시 올리면 `rc=1`이고 표는 그대로다.
맨 위의 `flush ruleset`까지 한 트랜잭션이라 그것도 안 됐다. 에러는 파일 · 행 · 열을
짚는다 — 결정 5의 "stderr를 콘솔로 흘린다"가 사람에게 그대로 쓸모 있다.

결정 5의 갈래 2가 맞다. 부팅에서 첫 `nft -f`가 실패하면 "앞의 규칙"이 없으므로
열린 상태 그대로다. 그래서 include 없는 기본 규칙 전용 파일을 한 번 더 올려야 닫힌다.

### 실측 9 — 하네스가 틀린 것 둘 (판정과 무관)

`FWM0-LISTEN 0 tcp, 0 udp`는 grep 패턴이 틀린 것이다 — `pre` 탐침이 넷 다 닿아
리스너가 있었다. `COUNTERS`는 `grep -A1 '^Udp:'`가 `UdpLite:`까지 잡아 헤더 줄을
냈다. 둘 다 가리려던 것이 없어 다시 돌리지 않았다.

### M0이 M1에 넘기는 것

- 커널: 실측 1의 다섯을 켜고 해소본 열다섯 줄을 커밋한다.
- 도구: 실측 2의 다섯 파일. Dockerfile에 패키지 넷(층 10), `guest_tools.sh`에 한 줄씩.
- 규칙 파일 둘: 결정 3 그대로(include 경로만 `/config/nftables.d/*.nft`)와 include 없는
  것. 맨 위의 `flush ruleset`은 부팅 첫 회에는 필요 없지만 사람이 셸에서 같은 파일을
  다시 올릴 때 표가 겹치지 않게 둔다.
- `init`: `/config` 유무와 `nftables.d` 유무를 가리지 않고 같은 파일을 올린다(실측 4).
- 체인: 음성 TCP는 `bytes=0`과 짧은 읽기 타임아웃(실측 6).
