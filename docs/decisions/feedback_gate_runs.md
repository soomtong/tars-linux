---
name: feedback_gate_runs
description: 루트 게이트의 연속 반복 수를 3에서 2로(2026-10-05), 다시 1로(2026-10-10) 줄였다(둘 다 사용자 결정). 3은 BF design의 관례였고, 회귀는 늘 1회차에서 잡혔다. 반복은 `-e RUNS=N`으로 가끔 늘린다.
metadata:
  node_type: memory
  type: feedback
---

## 2026-10-10 — 2에서 1로

사용자 결정이다. "그동안 많은 검증을 거쳤고 어느 정도 안정화됐다. 추후 간간히 RUNS 수치를 늘려서
검증한다." 2회로 PD-M2부터 BS-M1까지 지나는 동안 2회차가 잡은 것(AU-M2 pointer `seq 200` · VD-M2 render
검사 28 · TC-M3 config)은 전부 게이트 쪽 경합이었고 제품 회귀는 없었다. GP-M0의 실측으로 2회차의 몫은
약 28분(1시간 01분 18초 중)이었다.

How to apply: `check.sh`의 `RUNS`는 `"${RUNS:-1}"`이다. 반복을 늘리는 확인은 파일을 고치지 않고
`docker run -e RUNS=3 …`으로 준다. 기본 1회 게이트에서는 `skipping make`가 체인 수 − 1이다. 경합이 의심되는
체인은 여전히 그 체인만 따로 여러 번 돌린다. 아래는 3에서 2로 줄일 때의 기록이다.

Why: 3회는 Boot Foundation design(2026-08-01)의 Exit gate 한 줄 "3회 연속 실행
성공(일관성 확인)"에서 왔고, 왜 3인지 잰 기록이 없다. `check.sh`의 GL-M0 주석대로
반복이 잡는 것은 부팅 · 게스트 입력의 flakiness이고 빌드 재현성이 아니다. 실제로 회귀
(결정적 실패)는 전부 1회차에서 잡혔고(PD-M0의 install 실패도 두 번 다 1회차), 2 · 3회차가
잡은 것은 경합이었는데 그때마다 게이트가 빨개져 원인을 가르는 데 한 시간이 들었다
(GE-M1의 service 체인 → PE-M0이 고쳤다). 1회차에 빌드가 들어 있어 3회차의 몫은 약 20분이다
(1시간 8분 중). 경합이 의심되는 체인은 그 체인만 따로 여러 번 돌린다(GE-M1 · PE-M0의 방식).

How to apply: PD-M1의 루트 게이트는 3회로 돈다. PD-M1 commit 뒤, PD와 무관한 별도 commit으로
`check.sh`의 `run_chain` 반복 수와 `3/3` 문구 둘을 2로 고치고, GA의 진입 검사가 그 문구를
보는지 확인한다. 문서의 과거 `3/3` 기록은 그대로 둔다. 그 뒤의 모든 milestone은 2회다.
사용자가 1회로 더 줄일 가능성을 열어 두었다 — 2회로 몇 milestone을 지나며 2회차가 잡은 것이
없으면 그때 다시 묻는다. 관련: [[project_gate_latency]] · [[project_gate_chain_composition]].
