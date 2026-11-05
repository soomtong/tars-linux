---
name: feedback_tool_sourcing
description: 도구의 출처와 자리(2026-11-05 사용자 결정) — 커널과 바닥(glibc · 공용 라이브러리)은 Debian, 개별 유틸리티는 공식 미리 빌드된 바이너리(sha256 고정), 소스 빌드는 안 한다. initrd냐 개발 도구 층이냐는 docs/guides/initrd-criteria.md의 A · B · C, 크기 기준 없음. 용어는 "개발 도구 층", PATH는 /usr/local/bin이 앞
metadata:
  type: feedback
---

2026-11-05, TP(개발 도구 층) design을 짜면서 사용자가 하나씩 정했다.

- "커널은 Debian에 의존하는 부분은 이해된다. 보안 문제와 안정성 문제가 중요하니까. 개별 유틸리티들은 꼭 Debian에 의지하지
  않아도 된다." — 그래서 UT design 결정 3(initrd 조달은 Debian `.deb` 하나)을 취소했다. 첫 사례가 initrd의 lsoff · doge
  (`devcontainer/Dockerfile` 층 20).
- "Debian 배포판보다 직접 받을 수 있는 버전을 패키징하는 것을 선호한다." "소스 코드에서 빌드를 꼭 해야 하나? 프리빌드 바이너리가
  있다면 그걸 써야 한다. 보통 linux amd64 빌드는 tier 1이다." — 소스 빌드는 안 한다. 미리 빌드된 바이너리가 없는 도구(fakesteak)는
  뺐다.
- 각 도구는 최신 버전, LTS 정책이 있으면 최신 LTS.
- initrd에 넣는 기준은 `docs/guides/initrd-criteria.md`(A TARS가 부른다 · B 개발 도구 층 없이도 있어야 한다 · C 셸의 일상 기본).
  크기 기준은 두지 않는다(사용자가 "크기 기준 없음"을 골랐다). 같은 일을 하는 도구가 이미 있으면 안 넣는다.
- 맨 "층"은 애매하다 — "개발 도구 층"이라 쓴다. 그 안의 squashfs 하나는 "묶음"이다. `guest_tools.sh`의 "층 N"은 UT 때부터의
  목록 번호로 남는다.
- `PATH=/usr/local/bin:/usr/bin:/bin` — 개발 도구 층의 최신판이 initrd의 trixie 판보다 앞선다(TP design 결정 20).
- 최소 설치 디스크는 16GiB(HP design 결정 2의 4GiB를 올렸다 — "요즘 작은 임베디드 장비도 8GB 이상"). 우선순위는 사용자의 구형
  맥북 에어를 개발 장비로 쓰는 것이다.

## Why

TARS의 `/`는 RAM이고(initrd), 개발 도구는 GB 단위라 RAM에 둘 수 없다. 망 없는 곳에서도 개발할 수 있어야 한다는 것이 목표라
설치 USB에 싣고 디스크로 옮긴다. 최신판과 빌드 시간 두 가지가 Debian 패키지와 소스 빌드를 밀어냈다. 바닥만 Debian에 남긴 이유는
보안 갱신과 ABI 안정성이다.

## How to apply

- 도구를 하나 더할 때: 먼저 `initrd-criteria.md`로 initrd냐 개발 도구 층이냐를 가르고, 출처는 `upstream` → `vendor-repo` →
  `prebuilt` → `debian` 순서(TP design 결정 1)로 고른다. 버전과 sha256을 고정한다.
- 공식 바이너리가 없다고 해서 소스 빌드를 제안하지 않는다 — 표준이 된 제3자 빌드나 Debian을 찾고, 없으면 빼는 쪽을 묻는다.
- 관련: [[feedback_scripting_runtimes]] · [[project_package_manager]] · [[project_mise]].
