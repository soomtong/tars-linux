---
name: feedback-execution-scope
description: "Claude must not run implementation/build/QEMU-boot commands or write implementation files itself in TARS work — only explain, verify via find/Read, and commit"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 10b4f7ad-4d30-4504-9301-20984c1dc23a
  modified: 2026-08-05T10:10:12.776Z
---

이 저장소(tars-linux)의 CLAUDE.md는 "설명 → 사용자 직접 실행 → 결과
설명" 순서를 명시하고 있다. 2026-08-05 세션에서 이 원칙을 두 가지
방식으로 벗어났다가 사용자에게 지적받았다.

**1. 실행 모드를 다시 물어본 것.** [[feedback_commit_delegation]]에 이미
"subagent-driven/inline execution을 이 프로젝트에서 다시 제안하지 말 것 —
사용자가 2026-08-03에 이미 pairing 방식으로 못박음"이라고 기록돼 있었는데,
`writing-plans` skill이 실행 방식을 묻는 기본 동작을 그대로 따라가다가
이 기존 메모리를 놓치고 Subagent-driven/Inline Execution 옵션을 다시
제시했다.

**2. "검증"의 범위를 넘어 직접 재실행한 것.** CLAUDE.md의 "진행 전 검증은
Claude Code 책임" 조항은 `find`/`Read`로 파일 존재·내용을 확인하라는
것이지, 빌드나 QEMU 부팅을 Claude가 직접 재실행해도 된다는 뜻이 아니다.
이 세션에서 BF-M1 완료 여부를 확인한다며 `docker run ... kernel/check.sh`
(빌드 + QEMU 부팅 전체)를 직접 돌렸고, BF-M2 design 단계에서도 fish
feasibility 조사를 위해 devcontainer 안에서 `apt-get install fish`,
`ldd`, terminfo 실험 등을 직접 실행했다. 사용자는 이번 건은 예외로 넘어가
주었지만("이미 커밋된 문서/검증은 그대로 두고, 지금부터만 원칙을 엄격히
지키고 싶음"), 앞으로는 이렇게 하면 안 된다.

**Why:** [[user_learning_goal]] — TARS 작업은 속도가 아니라 이해가
목적이다. 커널/빌드/부팅 관련 명령을 사용자 본인이 직접 실행해야 몸으로
이해가 쌓인다. Claude가 대신 실행하면 이 목적 자체가 무너진다.

**How to apply:**
- BF 각 milestone의 plan 실행 시, Task/Step마다 무엇을·왜 하는지 설명한
  뒤 사용자가 파일을 쓰고 명령을 실행하도록 안내한다. Claude는 파일을
  쓰거나 빌드/부팅/조사성 명령을 실행하지 않는다.
- "완료됐는지 확인"이 필요하면 `find`/`Read`/`git log`/`git show`처럼
  읽기 전용 도구만 쓴다. 실제 빌드나 QEMU 부팅으로 재검증하지 않는다 —
  의심되면 사용자에게 다시 실행해서 로그를 붙여달라고 요청한다.
- design/plan 문서 자체(스펙, plan 파일, HANDOFF.md)를 Claude가 쓰는 것과
  git commit을 Claude가 만드는 것은 [[feedback_commit_delegation]]에 따라
  계속 허용된 예외다 — 이 메모리가 막는 것은 커널 빌드/QEMU 부팅/조사성
  명령 실행과, 구현 산출물(Dockerfile, init 소스, 스크립트) 파일 작성이다.
- 실행 방식(subagent-driven/inline/pairing)을 milestone마다 다시 묻지
  않는다 — 항상 pairing 방식.
