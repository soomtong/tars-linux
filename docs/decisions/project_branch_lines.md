---
name: project_branch_lines
description: 2026-11-18부터 줄이 둘이다 — `main`은 0.2.x(0.2.3 다음의 작업은 언제든 여기로 돌아와 잇는다), App Layer(0.3)는 브랜치 `app-layer-0-3`. 갈라진 자리는 프리릴리스 v0.2.3
metadata:
  type: project
---

사용자(2026-11-18): "this project (app layer enhanced) go 0.3 branch named app-layer-0-3" · "Anytime we go back to this main branch to
continue 0.2.3 next branch."

- `main` — 0.2.x 줄. 0.2.3 다음의 패치(도구 판올림 · 실기 수정 · 작은 서브프로젝트)는 여기서 한다. 릴리스 tag도 여기에 단다.
- `app-layer-0-3` — App Layer(SW · WY · TK · CR, [[project_app_layer_vision]])의 줄. `v0.2.3`([[project_release]]) 뒤의 `main`에서 갈라졌다.

How to apply:

- 세션을 시작하면 `git branch --show-current`로 어느 줄인지 먼저 본다. App Layer 일이면 `app-layer-0-3`, 그 밖이면 `main`.
- `main`에 쌓인 것을 0.3 줄로 가져오는 방법(merge · rebase)과 0.3을 `main`에 합치는 때는 아직 정하지 않았다 — 처음 필요해질 때 사용자에게 묻는다
  (Claude의 해석: 사용자의 말은 두 줄을 오간다는 것까지다).
- `HANDOFF.md` · `MEMORY.md`는 두 줄에서 따로 자란다. 줄을 옮길 때 다른 줄의 HANDOFF를 `git show <branch>:HANDOFF.md`로 읽는다.
