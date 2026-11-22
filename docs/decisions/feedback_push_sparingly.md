---
name: feedback_push_sparingly
description: app-layer-0-3 브랜치의 push는 필요한 만큼만 한다(사용자 2026-11-22 — CI 비용). milestone마다 자동으로 push하지 않는다
metadata:
  type: feedback
---

사용자(2026-11-22): "app layer 03 브랜치는 필요한 만큼만 푸시 진행 (CI 돌아가는 비용 조절해야 함)".

Why: push가 CI를 돌리면 비용이 든다. 지금 `.github/workflows/checks.yml`은 `main`의 push · pull request · 수동 실행에만 돌아 `app-layer-0-3`의 맨 push는 CI를
부르지 않는다(2026-11-22 확인) — 다만 PR을 열면 그 뒤의 push마다 돈다(뒤 문장은 Claude의 확인).

How to apply:

- commit마다 · milestone마다 push하지 않는다. 모아서, 까닭이 있을 때(다른 기계에서 받아야 함 · 백업할 만큼 쌓임 · 사용자가 보려 함) 한 번에.
- push하기 전에 그 브랜치에 열린 PR이 있는지와 workflow의 트리거를 본다 — CI가 도는 push면 더 아낀다.
- 같은 뜻으로 `tars-doom`의 release는 로컬 빌드를 올린다(사용자 2026-11-22 "로컬에서 빌드 후 업로드 정도면 충분함") — 그 저장소의 workflow는 수동 실행 전용으로 바꿨다.

관련: [[project_branch_lines]] · [[project_release]]
