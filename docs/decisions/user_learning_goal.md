---
name: user-learning-goal
description: "User's goal for the TARS boot-foundation project is learning, not shipping — pacing and depth should favor understanding over speed"
metadata: 
  node_type: memory
  type: user
  originSessionId: e314fd7b-fcc8-48dd-aa0a-0f7b55008289
---

The user is working through TARS boot-foundation (kernel/init/bootloader
from scratch) primarily to learn, not to finish the project as fast as
possible. Stated directly (2026-08-03): "나는 프로젝트 완성보다 학습을
목적으로 대화를 진행하고 있다" (I'm having this conversation for learning,
not project completion).

**How to apply:** Favor thorough explanations of *why* (e.g. why a specific
kernel .config option is needed, why a boot failure happens) over speed of
reaching the exit gate. This aligns with the project's own design principle
of "필요한 옵션만 하나씩 켜며 이해" (turn on only the options you need, one
at a time, to understand them) — see [[project_boot_foundation_restart]].
Also reinforces [[feedback_commit_delegation]]'s pair-programming execution
style: don't push toward subagent-driven/inline automated execution, since
the user doing the hands-on work themselves is part of how they learn.
