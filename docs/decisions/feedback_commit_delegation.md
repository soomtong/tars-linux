---
name: feedback-commit-delegation
description: "Once a step's result is approved by the user, Claude Code creates the git commit itself (user, 2026-08-02); subagents never commit. Never ask the user to run git add/commit"
metadata:
  type: feedback
---

Once content is approved (a step's expected result is confirmed), Claude Code
creates the git commit itself rather than asking the user to run `git add`/`git
commit`. Subagents that implement a milestone never commit — the lead verifies
their diff against the files and commits.

Why: User stated (2026-08-02): "앞으로 승인된 내용의 commit 생성은 claude code
에게 위임합니다" after doing the first two commits (Dockerfile, devcontainer
verification) manually. On 2026-08-03 the user also refused to be asked about
execution mode per milestone — the division of labor is settled, not a question
to re-open.

How to apply: commit only after the user has confirmed the step's result;
narrow `git add` to the intended paths (`CLAUDE.md` "Commit 전 git status
확인"). Who writes files and runs commands has changed three times since
(2026-08-22 commands, 2026-09-12 files, 2026-10-03 subagent implementation) —
the current table is in [[feedback_execution_scope]]; this memory only holds
the commit rule, which never changed. Push is a separate rule:
[[feedback_push_policy]].
