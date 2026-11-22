---
name: project_branch_lines
description: 줄이 둘이던 때(2026-11-18~22 — `main` 0.2.x · `app-layer-0-3`)는 0.3.0으로 끝났다. 2026-11-22 rebase로 main의 PT-M0을 받고 `main`을 `v0.3.0`까지 fast-forward — 지금은 `main` 하나
metadata:
  type: project
---

사용자(2026-11-18): "this project (app layer enhanced) go 0.3 branch named app-layer-0-3" · "Anytime we go back to this main branch to
continue 0.2.3 next branch."

- 2026-11-18~22: `main`은 0.2.x 줄(그 사이 PT-M0 하나가 클라우드 세션의 PR로 들어왔다), `app-layer-0-3`은 App Layer(SW · WY · TK · CR,
  [[project_app_layer_vision]])의 줄. `v0.2.3`([[project_release]]) 뒤의 `main`에서 갈라졌다.
- 2026-11-22 합침: 사용자 "pull main of origin, new commits there. rebase onto main" — 브랜치 123개를 `main`의 `4782c9d` 위로 rebase
  (충돌은 문서 넷 — `-X theirs`로 옮긴 뒤 PT의 줄을 다시 넣었다, `7e22dcd`) → force push. 이어서 0.3.0 릴리스 때 사용자가 "main을 fast-forward"를
  골라 `main` = `v0.3.0`(`f6ccce4`)이 됐다.

How to apply:

- 이제 줄은 `main` 하나다. `app-layer-0-3`은 `v0.3.0`과 같은 자리에 남아 있고 더 쌓지 않는다(지울지는 사용자가 정한다).
- 다시 줄을 가를 때는 이번처럼: 갈라진 줄에 `main`의 것을 가져올 때 rebase를 썼고, `HANDOFF.md` · `MEMORY.md` · `completed.md`처럼 두 줄이
  함께 고치는 문서가 충돌의 거의 전부였다.
