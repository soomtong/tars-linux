---
name: project_reserved_ports
description: "게이트 체인 포트 45455~45599를 컨테이너 ephemeral 범위에서 뺀 서브프로젝트(RP-M0, 2026-11-01). docker run --sysctl로만 걸리고(컨테이너 안 /proc/sys는 읽기 전용), 루트 check.sh가 값을 읽어 다르면 빌드 전에 멈춘다. 범위를 넓힐 때는 Makefile RESERVED_PORTS와 check.sh RESERVED_PORTS_WANT를 함께"
metadata:
  node_type: memory
  type: project
---

# 예약 포트 (RP)

design은 `docs/specs/2026-11-01-tars-reserved-ports-design.md`, plan은 `docs/plans/2026-11-01-tars-reserved-ports-rp-m0.md`.
2026-11-01에 사용자가 HANDOFF 후보(게이트 포트 예약 · 큰 kitty 이미지 · PD 비목표 · 패키지 매니저) 중에서 골랐다.

## 결정

- 포트를 32768 아래로 옮기지 않고 예약한다. 옮기려면 스크립트 22개에 있는 숫자 122곳을 고쳐야 하고, 예약은 줄 다섯이면 된다.
- 범위는 45455~45599다. 새 체인 몫과 probe의 45590까지 들어간다. site의 45600은 호스트에서 돌아서 뺐다.
- 루트 `check.sh`가 `/proc/sys/net/ipv4/ip_local_reserved_ports`를 읽는다. 값이 같은 문자열이 아니면 `clean` 전에 exit 1로 끝낸다.
  체인별 검사는 두지 않는다. 충돌은 lane이 동시에 돌 때 생긴다.

## 함정

- `make gate`는 `IN_CONTAINER`를 쓰지 않고 자기 `docker run` 줄을 갖고 있다. carryover 메모가 `IN_CONTAINER`만 적었던 것은 틀렸다.
- 예약은 출발 포트의 자동 배정만 막는다. 명시해서 하는 `bind()`는 그대로 된다(perl 실측, design "착수 전" 2).
- 컨테이너에 `nc` · `ss` · `python3`가 없다. 소켓 실험에는 `perl -MIO::Socket::INET`를 쓴다.
- 체인을 `docker run`으로 직접 띄울 때는 `--sysctl net.ipv4.ip_local_reserved_ports=45455-45599`를 넣는다(lessons의 세 줄).
  루트 게이트는 이 플래그가 없으면 멈추고, 체인 하나만 띄울 때는 플래그가 없어도 멈추지 않는다.

## 결과

플래그 없이 띄우거나 옛 범위로 띄우면 0.4초에 `check FAIL`로 멈춘다. `make gate` 1회 22/22, 10분 22초(prebuild 321 + lanes 299초),
verify 8126줄. 이 충돌은 원래 간헐이라 게이트를 한 번 통과한 것은 고친 근거가 아니다. 고친 근거는 실측이고, 게이트는 예약이
아무 체인도 깨지 않는다는 것을 보여 준다.
