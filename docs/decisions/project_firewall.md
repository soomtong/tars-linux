---
name: project_firewall
description: "tars.conf의 firewall=on이 들어오는 것을 기본으로 버리고 사람은 /config/nftables.d/*.nft에 여는 서브프로젝트(FW-M0~M2, 2026-09-27 종료). init은 net.bringUp 앞에서 nft -f를 기다리기만 하고, nft -f가 원자적이라 사람의 파일이 틀리면 include 없는 기본 규칙을 다시 올린다. 표는 table ip — IPv6가 오면 inet으로 바꿔야 한다. 열다섯번째 체인 firewall/check.sh"
metadata:
  node_type: memory
  type: project
---

# Firewall (FW)

design은 `docs/specs/2026-09-27-tars-firewall-design.md`. IN이 미룬 셋(UDP ·
포트 여럿 · 방화벽)을 사용자가 골랐고, 방화벽 하나의 이야기로 묶었다 — UDP와 포트
여럿은 "연 것은 닿고 안 연 것은 안 닿는다"를 판정하는 재료가 됐다.

사용자가 정한 셋. 기본은 꺼짐이고 켜면 닫힘(키를 안 적은 기계는 한 글자도 안
바뀐다는 관례) · 포트는 `/config/nftables.d/*.nft`에 nftables 문법으로 연다(chrony.d와
같은 모양) · 규칙을 넣는 것은 `nft`이고 `init`은 배관만 한다.

무엇이 섰나.

- 커널 `NETFILTER` · `NF_TABLES` · `NF_TABLES_IPV4` · `NF_CONNTRACK` · `NFT_CT`(끌려온 열,
  전부 `=y`). Dockerfile 층 10 · `guest_tools.sh`의 `/usr/bin/nft`(새 파일 다섯, 1.39MB).
- `make_initrd.sh`의 `/etc/tars/firewall.nft`(기본 규칙 + include)와
  `/etc/tars/firewall-base.nft`(include 없음).
- `init/src/firewall.zig`의 `up()` — `fork` · `execve(nft -f)` · `wait4`. 갈래는 `off`와
  셋(1 섰다 · 2 사람의 파일 때문에 기본만 섰다 · 3 기본도 실패해서 열려 있다).
- `firewall/check.sh` — 부팅 둘, 검사 열일곱.

Why: IN 이후 게스트는 연 포트를 누구에게나 받았고, WN · DI 이후 실기에서 LAN에 붙을
수 있다. 받을 것을 고르는 층이 없었다.

How to apply:

- `nft -f`는 원자적이다(M0 실측 8). 틀린 파일 하나가 있으면 멀쩡한 파일까지 전부
  빠진다. 부팅 첫 회에는 "앞의 규칙"이 없어서, 실패를 그냥 두면 열린 채다 — 그래서
  include 없는 파일을 한 번 더 올린다. 이 갈래를 없애면 기계가 조용히 열린다(M2의
  mutation이 그것을 봤다).
- 빈 include glob은 에러가 아니다(M0 실측 4). `/config`가 없는 부팅도 같은 파일을 올린다.
- `policy drop` 아래에서도 DHCP는 처음부터 다시 선다(M0 실측 5). 67→68 허용 줄이
  필요 없다.
- 표가 `table ip`다. `NF_TABLES_INET`이 `depends on IPV6`이고 커널에 IPv6가 없다.
  IPv6를 켜는 사이클은 표를 `inet`으로 바꾸고 v6 음성 검사를 더해야 한다(design 위험 6).
- 막힌 TCP를 SLIRP은 끊지 않는다. 체인 쪽 `connect`는 성공하고 read가 타임아웃을 꽉
  쓴다(M0 실측 6). 판정은 읽은 바이트이고 음성 타임아웃은 2초다. IN의 "아무도 안
  들을 때"는 즉시 닫혔던 것과 다르다.
- 음성이 "게스트 프로그램이 조용했다"가 아니라 "커널이 안 넘겼다"라는 증거는 리스너
  쪽에서 본다. 한 번만 사는 TCP 리스너가 아직 LISTEN이면 연결이 안 왔고, `nc -u -l`은
  첫 데이터그램에 connect하므로 `/proc/net/udp`의 상대 주소가 `00000000:0000`이면
  아무것도 안 왔다.
- `/proc/net/tcp`의 포트 16진수는 손으로 옮기지 않는다. 7070은 `0x1B9E`인데 `0x1BAE`로
  옮겨서 M0에서 한 번, M1에서 한 번 0을 셌다. 체인은 `printf '%04X'`를 쓴다. M0에서
  "패턴이 틀렸다"로 적고 원인을 안 본 것이 두 번째를 불렀다.

관련: [[project_inbound_network]] · [[project_guest_network]] · [[project_loopback]] ·
[[feedback_boot_never_blocks]] · [[project_write_or_reuse]] · [[project_gate_screen_echo]]
