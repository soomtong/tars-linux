---
name: feedback_design_question_load
description: 설계 단계에서 기술적 선택지를 사용자에게 계속 물어보지 말 것 — 추천안을 정해서 진행하고, 설명은 계속하되 결정은 Claude가 한다.
metadata:
  type: feedback
---

2026-08-11 TF-M3 brainstorming 중. Claude가 설계 선택지를 하나씩 물어보는
방식(입력 장치 → 자식 프로세스 → 키맵 범위 → 검증 게이트, 4개)으로
진행하다가, 다섯 번째 질문을 앞두고 사용자가 말했다:

> "Ok I dont care for now I not good at this domain"

**Why:** 커널 드라이버·evdev·PTY 같은 저수준 영역은 사용자가 아직 배우는
중인 대상이다. "A와 B 중 무엇을 고를까요"는 **이미 답을 아는 사람에게만**
쉬운 질문이고, 배우는 사람에게는 판단 근거가 없는 상태에서 책임만 넘기는
것이 된다. [[user_learning_goal]]이 원하는 것은 *결정권*이 아니라 *이해*다 —
"왜 이렇게 생겼는지"를 듣고 싶은 것이지 "무엇을 고를지"를 정하고 싶은 게
아니다.

**How to apply:**
- 설계 단계에서 사용자에게 던지는 **선택 질문은 최대 2~3개**로 제한한다.
  그 이상은 Claude가 추천안으로 정하고, 정한 이유를 설명에 녹인다.
- 진짜로 물어야 하는 것은 **취향·목적·범위**(예: "이번 milestone을 어디서
  끊을까요")이지 **기술적 트레이드오프**(예: "poll이냐 epoll이냐")가 아니다.
  후자는 근거를 대고 Claude가 결정한다.
- 설명은 줄이지 않는다. 이 피드백은 "덜 설명하라"가 아니라 "덜 물어보라"다.
  `CLAUDE.md`의 설명 → 실행 → 설명 순서는 그대로 유지한다.
- 사용자가 "네가 정해"라고 말하면 되묻지 말고 바로 진행한다
  ([[feedback_execution_scope.md]]가 "실행 모드를 다시 묻지 말 것"이라고
  적은 것과 같은 종류의 실수다).

관련: [[user_learning_goal]], [[feedback_execution_scope]],
[[feedback_commit_delegation]]
