---
name: feedback-execution-scope
description: "Claude runs the build/QEMU/gate commands in TARS work (changed 2026-08-22); file edits still go through the user, and explanation before + interpretation after stay mandatory"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 10b4f7ad-4d30-4504-9301-20984c1dc23a
  modified: 2026-08-22T00:00:00.000Z
---

**2026-08-22에 이 규칙의 절반이 뒤집혔다.** 그 전까지는 Claude가 빌드·QEMU
부팅·게이트 명령을 **직접 실행하지 않는 것**이 원칙이었다. 사용자가 HD-M2
Task 3 도중에 바꿨다: "I am tired run docker script. let change role. docker
running or script running are up to you claude. I carefully read messages of
what you said."

## 지금의 규칙 (2026-08-22부터)

| 하는 일 | 누가 |
|---|---|
| 무엇을 왜 하는지 **설명** | Claude (변함없음) |
| 구현 파일 편집 | **사용자** (변함없음) |
| 빌드·QEMU 부팅·게이트·조사성 명령 실행 | **Claude** ← 바뀐 자리 |
| 결과 로그를 줄 단위로 해석 | Claude (변함없음) |
| design/plan/HANDOFF/기억 파일 작성 | Claude (변함없음) |
| git commit | Claude ([[feedback_commit_delegation]]) |

**Why 바뀌었나:** [[user_learning_goal]]은 그대로 유효하다 — TARS 작업의
목적은 여전히 속도가 아니라 이해다. 바뀐 것은 **그 이해가 어디서 오는가**에
대한 판단이다. 같은 `docker run ...` 한 줄을 사람이 옮겨 치는 데서 오는
이해는 처음 몇 번이 지나면 없다. 이해는 "이것이 왜 이렇게 생겼는지"를 읽고
"결과가 왜 그렇게 나왔는지"를 따라가는 데서 온다. 사용자가 "I carefully read
messages"라고 밝힌 것이 그 뜻이다.

**파일 편집이 사용자에게 남아 있는 이유는 다르다.** 그것은 노동이 아니라
검토 지점이다. 코드가 저장소에 들어가기 전에 사람이 한 번 읽는 자리이고,
Claude가 잘못 제시한 것을 그 자리에서 잡을 수 있다. HD-M2에서도 "넣을 것"만
제시하고 사용자가 넣는 방식이 유지되고 있다.

## How to apply

- Step마다 **설명이 먼저다.** 무엇을 만들고 왜 그렇게 생겼는지 말한 뒤에
  명령을 실행한다. 명령을 먼저 던지고 결과부터 보는 순서로 바꾸지 않는다.
- 실행한 명령의 결과는 **반드시 해석해서 전달한다.** 로그를 그대로 붙이고
  끝내지 않는다. 특히 실패했을 때 "무엇이 어디서 왜"를 짚는다.
- 긴 명령(루트 게이트 등)은 실행 전에 **얼마나 걸리는지 알린다.** 31분짜리
  명령을 말없이 시작하지 않는다.
- 편집은 여전히 "넣을 것"만 제시하고 사용자가 넣는다. 지울 것이 있으면
  `지울 것`과 `넣을 것`을 따로 표시한다. 100줄이 넘으면 `/tmp` 경로로.
- 편집 뒤에는 `Read`/`rg`로 **직접 확인하고 나서** 다음으로 넘어간다.
  "edited"라는 답만 믿지 않는다. 이 조항은 규칙 변경과 무관하게 유효하다.
- 실행 방식(subagent-driven/inline/pairing)을 milestone마다 다시 묻지
  않는다 — 항상 pairing 방식이다. 바뀐 것은 pairing 안에서 명령을 누가
  치느냐이지, pairing 자체가 아니다.

## 이 규칙이 원래 왜 생겼는가 (2026-08-05)

기록으로 남긴다. 당시 Claude가 두 가지로 원칙을 벗어났다.

**1. 실행 모드를 다시 물어본 것.** [[feedback_commit_delegation]]에 이미
pairing 방식으로 못박혀 있었는데 `writing-plans` skill의 기본 동작을 따라가다
Subagent-driven/Inline 옵션을 다시 제시했다. **이 조항은 지금도 유효하다.**

**2. "검증"의 범위를 넘어 직접 재실행한 것.** BF-M1 완료 확인을 위해
`docker run ... kernel/check.sh`를 돌렸고, BF-M2 design 단계에서 fish
feasibility 조사를 위해 컨테이너 안에서 `apt-get install fish` 등을 실행했다.
**이 조항이 2026-08-22에 뒤집힌 부분이다** — 이제는 그렇게 하는 것이 정상
경로다.
