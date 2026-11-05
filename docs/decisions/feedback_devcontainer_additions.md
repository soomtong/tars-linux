---
name: feedback_devcontainer_additions
description: 개발 컨테이너(devcontainer/Dockerfile)에 필요한 도구는 묻지 않고 언제든 더해도 된다(2026-11-05)
metadata:
  type: feedback
---

개발 컨테이너에 필요한 것이 있으면 언제든 `devcontainer/Dockerfile`에 더한다. 이미지 태그가 바뀌어 CI가 다시 굽고 다른 기기의
`make container`가 로컬 빌드(약 1분)를 하는 것은 감수한다.

**Why:** 사용자, 2026-11-05(TP-M0 plan 직후): "개발 컨테이너에 필요한 게 있으면 언제든지 추가하세요." TP-M0 plan의 첫 판이 이미지
태그를 지키려고 굽기 · 검사를 버리는 amd64 컨테이너로 돌리는 우회를 골랐다 — 그 우회가 필요 없다는 뜻이다.

**How to apply:** 이미지를 안 바꾸려는 우회(매 실행마다 `apt-get install`, 다른 컨테이너로 돌리기)를 설계 이유로 삼지 않는다. 더한 줄에는
다른 층처럼 왜 필요한지 주석을 단다. 게스트에 들어가는 amd64 바이너리의 출처 규칙은 그대로다([[feedback_tool_sourcing]]).
