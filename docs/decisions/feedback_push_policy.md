---
name: feedback-push-policy
description: "Pushing to the remote is not something the user tracks — never ask permission, never report unpushed counts as a risk; push whenever it is convenient"
metadata:
  node_type: memory
  type: feedback
---

2026-08-24. `HANDOFF.md`가 오랫동안 맨 앞에 "`git rev-list --count
origin/main..main`이 0이어야 한다"를 두고, 세션 끝마다 "push해 둘까요?"를
물었다. 사용자가 그것을 끊었다 — **"push to remote is not important. don't
care push. and push anytime when your needs."**

**Why:** 이 저장소의 진짜 산출물은 원격의 상태가 아니라 로컬 히스토리와
그 위에 쌓이는 이해다([[user_learning_goal]]). 원격은 백업일 뿐이라 몇 개가
안 올라갔는지를 세는 것은 주의를 쓸 자리가 아니었다. 그런데 HANDOFF가 그
확인을 **가장 먼저 하는 일**로 올려 두어서, 세션마다 값 없는 확인과 값 없는
질문이 한 번씩 붙었다.

**How to apply:**

- **push 여부를 묻지 않는다.** 필요하다고 판단되면 그냥 한다.
- **미푸시 커밋 수를 위험처럼 보고하지 않는다.** "커밋 셋이 안 올라가
  있습니다" 같은 문장을 세션 요약에 넣지 않는다.
- `HANDOFF.md`의 시작 절차에서 push 확인을 뺀다. 대신 working tree가 깨끗한지
  같은, 작업에 실제로 영향을 주는 것만 확인한다.
- **commit은 그대로 Claude가 만든다** — 이 기억이 바꾼 것은 push뿐이고
  [[feedback_commit_delegation]]은 그대로다.

관련: [[feedback_execution_scope]], [[feedback_design_question_load]]
