---
name: feedback_ipv4_only
description: TARS는 IPv4만 지원한다(2026-10-31 사용자 결정). IPv6는 후보에서 빼고 더 논의하지 않는다 — 트리거는 "TARS Linux가 IPv6 망의 제품에 탑재된다"이고, 그때 FW 위험 6(표를 inet으로, v6 음성 검사)부터 다시 연다
metadata:
  type: feedback
---

2026-10-31, GI-M0을 닫고 다음 방향을 고르는 자리에서 사용자가 "네트워크: IPv6
또는 USB 동글 층 B"를 골랐다가, IPv6를 지금 써야 할 이유가 있는지 물었다. 조사
결과(커널 `# CONFIG_IPV6 is not set`, 방화벽 표 `ip`, IPv6 없이 생긴 불편은
chrony `cmdport 0`으로 지운 로그 한 줄뿐, 실기 네트워크는 아직 한 번도 안 뜸)를
듣고 사용자가 결정했다 — "우리 프로덕트가 향후 다양한 시스템에 탑재될 것을
예상하긴 하지만 지금 상태에서는 IPv6 환경으로 배포될 일은 아주 희박해. IPv4만
지원하면 충분하다. 이 부분은 결정으로 남기고 더 이상 논의하지 않도록 하자. 추후
IPv6 제품에 TARS Linux가 탑재되는 경우 다시 개발하도록 하자."

## Why

IPv6가 필요한 자리는 IPv4를 아예 안 주는 망(NAT64/464XLAT만 주는 이동통신
테더링)과 AAAA만 응답하는 서비스인데, 둘 다 지금 배포 환경에 없다. 켜면 커널
크기 · SLIRP의 v6 동작 · dhcpcd의 RA/DHCPv6 · 방화벽 `inet` 전환과 v6 음성 검사
· `tars-config`의 net 표시가 따라오고, 게이트로는 SLIRP 안의 v6만 증명된다.
근거 없이 미리 하는 일은 이 저장소의 방식(이해가 쌓이면 다음을 정한다)과
맞지 않는다.

## How to apply

- IPv6를 후보로 다시 올리지 않는다. HANDOFF의 "다음 후보"와 `carryover.md`에서
  IPv6는 뺐다. 네트워크 design의 비목표에 IPv6가 적혀 있으면 이 결정을 인용한다.
- 다시 여는 조건은 하나다 — TARS Linux가 IPv6 망의 제품에 탑재되는 것. 그때
  첫 확인은 FW design 위험 6(`CONFIG_NF_TABLES_INET`을 켜고 표를 `inet`으로,
  `firewall/check.sh`에 v6 음성 검사)이고, 함께 볼 자리는 NW design 결정 2(커널
  옵션)와 `init/src/clock.zig`의 `cmdport 0` 주석이다.
- 새 네트워크 기능(IN · FW · WL · UW 계열)은 IPv4 전제로 설계한다. "v6는
  어떻게 하나"는 묻지 않고 이 결정을 가리킨다.

관련: [[project_guest_network]] · [[project_firewall]] · [[feedback_network_default_stays_off]]
