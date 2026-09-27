# TARS Firewall — Design

접두사: FW

Status: 설계(2026-09-27). M0부터.

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
table inet tars {
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
- `inet` 계열은 IPv6가 들어와도 같은 표가 그대로 걸리게 하려는 것이다.
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
2. IPv6. 커널에 없다. 표가 `inet`이라 들어오면 같은 규칙이 걸린다.
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
