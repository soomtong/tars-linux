---
name: feedback_gate_runs
description: 루트 게이트의 연속 반복 수를 3에서 2로 줄인다(사용자 결정, 2026-10-05). 3은 측정이 아니라 BF design의 관례였고, 회귀는 늘 1회차에서 잡혔다.
metadata:
  node_type: memory
  type: feedback
---

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
