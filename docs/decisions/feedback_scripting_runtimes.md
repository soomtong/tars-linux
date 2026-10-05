---
name: feedback_scripting_runtimes
description: 컨테이너에 스크립팅 런타임을 들일 때는 python3 하나가 아니라 python3 · lua · nodejs(bun) · ruby 한 묶음으로 들인다(사용자, 2026-10-05). 지금은 안 들이고 perl로 간다
metadata:
  type: feedback
---

2026-10-05 AU 착수 중 "컨테이너에 python3가 없고 perl이 있는 이유"를 묻는
자리에서 사용자가 정했다.

> python3가 설치된다면 lua, nodejs(bunjs), ruby도 함께 설치되는게 맞습니다.
> (추후 필요할 때 구성하도록 하죠)

## 지금의 사실

`devcontainer/Dockerfile`은 스크립팅 런타임을 하나도 적지 않는다. perl 5.40은
`build-essential`(`dpkg-dev` · `libdpkg-perl`)과 `git`의 의존으로 따라 들어온
것이고 python3는 어느 패키지도 끌어오지 않아 없다(`--no-install-recommends`,
`debian:trixie-slim`). 컨테이너 안에서 듣는 소켓 · stub 서버 · MBR 쓰기는 전부
perl로 해 왔다(lessons 41 · 45 · 49, `net` 체인의 NTP stub).

## Why

런타임 하나를 들이면 그 하나로 쓴 도구가 생기고, 다음 사람이 다른 런타임을
들이면 같은 자리의 도구가 둘로 갈린다. 들일 거면 한 번에 묶어 들이고 이미지
크기 · 굽는 시간을 한 번만 치른다. 그리고 지금은 필요가 없다 — perl이 다 한다.

## How to apply

- 컨테이너의 stub · 리스너 · 파일 조작은 perl로 짠다. python3가 없다고
  Dockerfile에 python3만 더하지 않는다.
- 런타임이 정말 필요해지면 python3 · lua · nodejs(bun) · ruby 넷을 한 서브프로젝트
  (또는 한 milestone)로 묶어 들이고, Dockerfile 주석에 이 결정을 가리킨다.
- 게스트(initrd)에 런타임을 들이는 일은 별개의 결정이다 — 그때도 같은 묶음
  원칙을 먼저 묻는다. 비용은 [[project_measuring_tool_cost]]의 절차로 잰다.
