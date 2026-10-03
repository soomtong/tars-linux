---
name: feedback-superpowers-off
description: "superpowers plugin is disabled for tars-linux (2026-10-03) because its session-start injection is pressure language written for older models and its workflows duplicate or contradict CLAUDE.md; the next milestone is the test"
metadata:
  type: feedback
  modified: 2026-10-03T00:00:00.000Z
---

2026-10-03에 이 저장소에서만 superpowers plugin을 껐다. 설정은
`.claude/settings.json`의 `"superpowers@claude-plugins-official": false` 한 줄이다.
`.gitignore`가 `.claude/`를 통째로 빼므로 그 파일은 이 기계에만 있고, 이
기록이 결정의 유일한 사본이다. 다른 기계에서 일하면 같은 줄을 다시 넣는다.
전역 `~/.claude/settings.json`에서는 여전히 켜져 있다.

Why: `/claude-api prompt-audit`로 `CLAUDE.md`를 감사한 뒤 사용자가 "Opus 5.5를
중점적으로 쓰면 superpowers가 계속 필요한가"를 물었고, 끄는 쪽으로 정했다.
이유는 셋이다.

- 세션 시작 때 주입되는 `using-superpowers`는 "1%라도 해당되면 반드시 호출",
  "협상 불가" 같은 문구로 되어 있다. skill을 덜 부르던 옛 모델에 맞춘 것이라,
  지시를 문자 그대로 따르는 지금 모델에서는 작은 일에도 절차를 끼워 넣는다.
- 절차 skill들이 `CLAUDE.md`와 겹치거나 부딪힌다. brainstorming · writing-plans는
  "Milestone 단위 작업"과 겹치고, worktree · finishing-a-development-branch는
  `main`에 바로 커밋하는 방식과, "항상 TDD"는 `check.sh` 게이트 중심 검증과
  맞지 않는다.
- 이미 덜 쓰이고 있었다. plan 136개 중 33개가 머리에 "REQUIRED SUB-SKILL"을
  적었지만 마지막은 2026-09-27(DS-M1)이고 WL · UW plan에는 없다.

How to apply:

- `docs/superpowers/` 경로는 그대로 쓴다. 이름일 뿐 plugin이 없어도 된다.
- 새 plan 머리말에 "REQUIRED SUB-SKILL" 줄을 넣지 않는다. 기존 plan은 기록이니
  고치지 않는다.
- 끈 것은 가설이다. 다음 서브프로젝트의 첫 milestone을 plugin 없이 진행하고
  plan 품질과 검증 누락을 본다. 뭔가 빠지면 plugin 전체를 다시 켜기보다
  빠진 skill 하나(예: systematic-debugging)를 `.claude/skills/`에 두는 쪽을
  먼저 본다.

관련: [[feedback-execution-scope]]
