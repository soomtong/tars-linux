---
name: feedback_stepwise_report
description: 조사와 구현을 단계로 나누고, 단계마다 결과를 보고해 사용자의 확인("ok")을 받은 뒤 다음 단계로 간다(2026-11-06, TP-M6부터). 선택지를 묻는 것이 아니라 결과를 보이는 것이다.
metadata:
  node_type: memory
  type: feedback
---

사용자(2026-11-06, TP-M6 착수 때): "단계별로 진행하면서 점검해보자." TP-M6은 그렇게 했다 — 조사 넷(erlang · elixir · gleam · erlang의
man)과 구현 다섯(빌드 장치 · 재료와 `make dev-layers` · chroot와 빨강 · 체인 · 게이트)을 하나씩 끝내고 보고했고, 사용자가 매번
"ok"로 다음을 열었다. 그 사이 gleam의 오프라인 방식처럼 사용자가 정할 일이 나오면 그 단계에서 물었다.

Why: 이 저장소의 목표는 속도가 아니라 이해다(CLAUDE.md "왜 이런 규칙이 필요한가"). 한 번에 끝까지 가서 결과만 보이면 중간의 판단
(예: OrbStack의 Illegal instruction을 에뮬레이터 탓으로 본 근거)을 사용자가 따라갈 자리가 없다.

How to apply: 한 단계는 "무엇을 왜 → 실행 → 줄 단위 해석"(CLAUDE.md의 진행 방식) 한 벌이다. 단계 끝 보고에 다음 단계가 무엇이고
얼마나 걸리는지 한 줄을 붙이고, 확인을 받은 뒤 넘어간다. 기술 선택지는 여전히 추천안으로 정해 보고에 담는다 —
[[feedback_design_question_load]]와 부딪치지 않는다(묻는 것이 아니라 보이는 것이다). 30분짜리 게이트처럼 긴 단계는 돌기 전에 묻는다.
관련: [[feedback_execution_scope]].
