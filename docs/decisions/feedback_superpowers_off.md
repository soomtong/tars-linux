---
name: feedback-superpowers-off
description: "superpowers plugin was uninstalled from the user scope (2026-10-03) because its session-start injection is pressure language written for older models and its workflows duplicate or contradict CLAUDE.md; the next milestone is the test"
metadata:
  type: feedback
  modified: 2026-10-03T00:00:00.000Z
---

2026-10-03에 superpowers plugin을 user scope에서 지웠다
(`claude plugin uninstall superpowers@claude-plugins-official --scope user`).
모든 프로젝트에서 사라졌으므로 이 저장소에 따로 끄는 설정은 없다. 처음에는
이 저장소에서만 껐다가, 필요할 때만 켜는 길(`--settings`로 세션마다 켜기)을
보고 나서 사용자가 아예 지우기로 정했다 — 켜면 시작 주입도 함께 돌아와서,
원하는 "필요할 때 skill만"을 plugin 단위로는 얻을 수 없었다. 다른 기계에
설치돼 있다면 같은 명령으로 지운다.

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

- 같은 날 `docs/superpowers/`의 `specs/` · `plans/`를 `docs/` 바로 아래로 올렸다.
  plugin 이름이 경로에 남을 이유가 없어서다.
- 새 plan 머리말에 "REQUIRED SUB-SKILL" 줄을 넣지 않는다. 기존 plan은 기록이니
  고치지 않는다.
- 끈 것은 가설이다. 다음 서브프로젝트의 첫 milestone을 plugin 없이 진행하고
  plan 품질과 검증 누락을 본다. 뭔가 빠지면 plugin 전체를 다시 켜기보다
  빠진 skill 하나(예: systematic-debugging)를 `.claude/skills/`에 두는 쪽을
  먼저 본다.

관련: [[feedback-execution-scope]]

## 첫 검증 — TG(2026-10-03)

plugin 없이 연 첫 서브프로젝트가 TG다(`project_terminal_graphics`). 본 것은 사실만 적는다.

- design 하나와 plan 넷(M0~M3)을 기존 형식대로 썼다. "REQUIRED SUB-SKILL" 줄은 없다.
- plan의 결함 둘이 실행 전에 잡혔다 — M2의 음성 검사 18(되울린 명령 줄 때문에 늘 실패),
  M3의 검사 76(머리만 고친 PNG는 선의 증거가 못 됨).
  실행 중에 잡힌 것은 하나다 — fish 구문 강조가 기존 style 상한 검사를 넘긴 것(게이트가 잡았다).
- 검사의 기대값을 매번 실행 전에 계산해 적었고, 고친 값은 0이다. "항상 TDD" skill 없이도
  기대값을 먼저 쓰는 습관은 유지됐다.
- 편집마다 `git diff --stat`과 지운 줄 읽기를 했다(CLAUDE.md의 규칙).
- plugin이 있었다면 막았을 누락은 보지 못했다. `.claude/skills/`에 되살릴 skill은 아직 없다.
