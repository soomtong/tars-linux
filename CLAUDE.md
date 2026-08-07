# TARS 작업 규칙

이 파일은 이 저장소(`tars-linux`)에서만 적용되는 협업 규칙입니다. 전역
규칙(`~/.claude/CLAUDE.md`: 응답 언어, 커밋 스타일, 도구 환경, Handoff/
Memory 저장 위치)은 항상 함께 적용됩니다.

## 왜 이런 규칙이 필요한가

TARS는 이전 저장소(`tars.git`)에서 "이해 없이 코드만 쌓이는" 문제로 막혀서
완전히 새로 시작한 프로젝트입니다. 이번 재시작의 핵심 목표는 **속도가
아니라 이해**입니다. 커널이 어디까지 책임지고 어디서부터 우리 코드인지,
왜 이 명령이 이렇게 동작하는지를 매 단계 몸으로 확인하면서 진행합니다.
아래 규칙은 이 목표를 지키기 위한 것이며, 임의로 생략하지 않습니다.

## 진행 방식 (설명 → 실행 → 설명)

매 작업 단계는 다음 순서를 따릅니다.

1. **설명 먼저** — 지금 무엇을 만들고 왜 필요한지 사용자가 이해할 수 있게
   먼저 설명한다. 코드를 던지기 전에 "이게 왜 이렇게 생겼는지"를 말한다.
2. **사용자가 직접 실행** — 파일 작성과 명령 실행(빌드, QEMU 부팅 등)은
   사용자가 직접 한다. Claude Code가 대신 파일을 쓰거나 명령을 실행하지
   않는다.
3. **결과를 상세히 설명** — 실행 결과(로그, 에러, 경고)가 왜 그렇게
   나왔는지 줄 단위로 설명한다. 특히 "실패가 정상인 단계"(예: BF-M1의
   init 없는 kernel panic)는 왜 실패가 의도된 결과인지 명확히 짚는다.

## Commit은 Claude Code가 수행

파일 작성·명령 실행은 사용자가 하지만, **사용자가 결과를 승인한 뒤의 git
commit은 Claude Code가 대신 만든다** (2026-08-02 합의). 사용자에게 `git
add`/`git commit`을 실행하라고 안내하지 않는다.

## 진행 전 검증은 Claude Code 책임

사용자가 "done"이라고 답해도, 다음 단계로 넘어가기 전에 반드시
`find`/`Read`로 실제 파일이 만들어졌는지, 내용이 맞는지 확인한다. BF-M0
진행 중 `check.sh`만 만들어지고 `Makefile`은 안 만들어졌는데도 "done"이라고
답한 적이 있었다 — 이후 매번 파일 존재를 먼저 확인하고 나서 다음 명령을
안내한다.

## Commit 전 git status 확인

`git add`로 디렉터리를 통째로 추가하기 전에 무엇이 포함되는지 확인한다.
BF-M0에서 `git add devcontainer/sanity/`로 빌드 산출물(`*.o`,
`sanity.elf`)까지 실수로 커밋된 적이 있다 — 이후 `.gitignore`로 빌드
산출물을 미리 배제하고, add 대상을 항상 좁혀서 지정한다. 이 저장소는
kernel/init/bootloader를 직접 빌드하므로 바이너리 산출물이 계속
생성된다 — 소스와 산출물을 구분하는 습관이 특히 중요하다.

## Milestone 단위 작업

각 서브프로젝트는 `docs/superpowers/specs/`에 design doc, `docs/
superpowers/plans/`에 milestone별 plan을 작성한다 (예:
`2026-08-01-tars-boot-foundation-design.md`,
`2026-08-01-tars-boot-foundation-bf-m0.md`). 한 milestone이 끝나면 다음
milestone의 plan은 그 시점에 새로 작성한다 — 전체 milestone을 한 번에
미리 상세 설계하지 않는다 (이해가 쌓이면서 다음 단계의 구체적 결정이
바뀔 수 있기 때문).

## 참고

- 최종 비전 전체 배경(왜 여러 서브프로젝트로 나뉘는지, 후보 목록):
  `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md`의
  "배경" 절
- 완료된 서브프로젝트: Boot Foundation(BF-M0~M4, 2026-08-07 완료)
- 진행 중인 서브프로젝트: Display Foundation
  (`docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md`)
- 현재 진행 상황: `HANDOFF.md`
