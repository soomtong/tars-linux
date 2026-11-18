---
name: feedback_herdr_subagents
description: App Layer 브랜치(`app-layer-0-3`)에서 서브에이전트는 Herdr로 운용한다(사용자 2026-11-18). 사용법은 `herdr --skill`이 말한다. 옆 pane을 갈라 agent를 띄우고 `agent prompt --wait`로 맡기고 `agent read`로 읽는다. lead의 몫(diff 대조 · 게이트 · commit)은 그대로
metadata:
  type: feedback
---

사용자(2026-11-18): "우리는 Herdr, herdr Agent manage tool을 사용하고 있는데 이게 서브 에이전트를 구동하는데 최적화되어 있어.
herdr --skill 명령을 통해 확인 가능. 핸드오프에 추가해주고 App Layer Branch에서는 허더를 이용해서 서브에이전트를 운용하자."

Why: 사용자가 이 세션들을 Herdr(코딩 에이전트용 터미널 멀티플렉서, 0.9.5) 안에서 돌린다. 서브에이전트가 옆 pane에서 돌면 사용자가
그 화면을 직접 본다 — "사용자는 만들어진 코드를 읽으며 따라간다"([[feedback_execution_scope]])와 같은 방향이다(뒤 문장은 Claude의 해석).

How to apply:

- 범위는 `app-layer-0-3` 브랜치다. `main`의 작업 방식은 이 기억이 바꾸지 않는다.
- 세션을 시작하면 `herdr --skill`을 한 번 읽는다 — 명령 문법은 설치된 바이너리가 기준이고 판마다 바뀔 수 있다.
- `test "${HERDR_ENV:-}" = 1`이 아니면 Herdr 밖이다. 그때는 Herdr로 조종하지 않고, 서브에이전트가 필요하면 사용자에게 말한다.
- 맡기는 순서(0.9.5에서 확인한 모양):
  1. `herdr pane split --current --direction right|down --cwd "$PWD" --no-focus` — 새 pane의 id는 응답 JSON의 `.result.pane.pane_id`
  2. `herdr agent start <이름> --kind claude --pane <id>`
  3. `herdr agent prompt <이름> "<일>" --wait --timeout <ms>`
  4. `herdr agent read <이름> --source recent-unwrapped --lines 120`
- id는 응답에서 읽는다(지어내지 않는다). 내가 만들지 않은 pane · tab · workspace는 닫지 않는다. `herdr` 한 단어만 치지 않는다(TUI가 뜬다).
- lead의 몫은 그대로다 — 설명 · plan · 보고된 diff를 실제 파일과 대조 · 게이트 · commit. 서브에이전트는 commit하지 않는다
  ([[feedback_commit_delegation]]). 맡기는 글에 그것을 적는다.
- 무엇을 맡길지의 기준도 그대로다: design doc의 확인 절처럼 lead가 이해해야 하는 읽기는 직접 한다.

관련: [[project_branch_lines]] · [[project_app_layer_vision]]
