---
name: reference-ghostty-source
description: ghostty 구현을 참고로 읽을 때는 /Users/dp/Repository/_study/ghostty(사용자가 담는 최신)를 본다. terminal/ghostty-src는 빌드 입력일 뿐이다
metadata:
  type: reference
---

# ghostty 소스의 두 자리

- 참고로 읽는 판: `/Users/dp/Repository/_study/ghostty`. 사용자가 최신 소스를 담아 둔다(2026-10-28에 `46e9dc9`, 얕은
  clone이라 커밋 기록은 없다). 사용자 말: "ghostty는 가장 잘 구현된 예제가 될 거야." 구현 방향을 정할 때 이 판을 먼저 본다.
- 빌드 입력: `terminal/ghostty-src`. `.gitignore`에 걸려 있고 `vendor_libghostty_vt.sh`가 고정 판(`GHOSTTY_SHA`, 지금
  `3d07ef9`)을 받는다. `build.zig.zon`의 `.path = "ghostty-src"`가 이것을 잡는다. 지워도 `prepare.sh`가 다시 받는다.
  `_study`는 저장소 밖이라 컨테이너(`/workspace`)에서 안 보인다.

Why: 사용자가 2026-10-28에 "우리 내부 소스는 지우자"고 했다가, 빌드 입력이라는 설명을 듣고 "빌드 입력은 두고 참고만
`_study`"로 정했다.

How to apply: design · plan에 ghostty 줄 번호를 적을 때는 `_study` 판과 그 커밋을 함께 적는다. 우리가 링크하는 판과
API가 다를 수 있다 — 예: 최신 `RenderState`는 kitty 배치(`imagePlacementsGeneration`)를 담지만 `3d07ef9`는 안 담는다
([[project_dirty_rows]]). 최신 판의 기능을 쓰려면 ghostty를 올리는 일(ZU 같은 서브프로젝트)이 먼저다.
