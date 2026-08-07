# HANDOFF: Boot Foundation 완료(BF-M0~M4) — 다음 서브프로젝트 선정 전

## 목표

TARS는 이전 저장소(`tars.git`)에서 이해 없이 누적된 잔손질(RC6~RC21)로
막혀서, 완전히 새 저장소(`tars-linux.git`, 현재 로컬 디렉터리)에서 처음부터
다시 시작하기로 함. 첫 서브프로젝트 **Boot Foundation**의 목표는 자체 빌드
Linux kernel + Limine bootloader + 직접 구현한 Rust init(PID 1) + xorriso
hybrid ISO로 QEMU에서 shell prompt까지 부팅하는 것이었고, **이번 세션에서
BF-M4(종료 게이트)까지 완료해 Boot Foundation 서브프로젝트 전체가
끝났다**. 최종 비전(macOS 키바인딩, ghostty 터미널, Linux homebrew, AI 도구
통합, 자체 CJK IME)은 다수의 독립적인 서브시스템을 포함하는 이후 별도
서브프로젝트이며, 어떤 걸 다음으로 할지는 **아직 정해지지 않았다**.

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행(빌드, 조사용 명령 포함)은 **사용자가 직접** → 결과를 사용자가
전달하면 Claude가 상세 해석. Claude는 design/plan 문서·`HANDOFF.md`
작성과 승인된 내용의 git commit만 대신 수행한다 (`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고). **실행 방식(subagent-driven/
inline/pairing)을 milestone마다 다시 묻지 말 것** — pairing으로 고정됨,
이번 BF-M4에서도 재확인 없이 그대로 적용함. 새 milestone/서브프로젝트
착수 전 "design doc이 필요한가"는 brainstorming 스킬로 짧게 확인하되,
새 아키텍처 결정이 없다고 판단되면 design doc 생략하고 바로
writing-plans로 plan만 작성해도 된다는 선례가 BF-M4에서 만들어짐(design
doc 없이 plan만으로 완료).

## 현재 브랜치

`main` — 새 저장소의 root부터 시작. 이전 저장소(`tars.git`)의 commit
history는 이어받지 않음. Working tree는 깨끗함(커밋 안 된 변경 없음).
`origin/main`으로 push 완료, tracking 설정됨. 최신 커밋 `d0cffff`.

## 완료된 작업

- [x] BF-M0, BF-M1, BF-M2, BF-M3 완료 (이전 handoff에서 기록됨)
- [x] **BF-M4 완료 — Boot Foundation 종료 게이트 통과.** 저장소 루트에
      `check.sh`를 새로 작성: `boot/check.sh`(BF-M0~M3 전체 체인이 이미
      묶여 있던 스크립트, 수정 없이 그대로 재사용)를 3회 반복 호출하며
      매회 시작 전 `kernel/build/`, `init/target/`, `out/`(모두
      `.gitignore` 대상)만 삭제하고 `kernel/src/`,
      `boot/limine-binary/`(다운로드 캐시)는 유지. `set -e` 없이 각
      회차 결과를 직접 검사해 실패 시 몇 번째 회차인지 출력하고
      즉시 중단(fail-fast)하도록 구현. **실행 결과 3회 모두 PASS**
      (`BF-M4 PASS: 3/3 consecutive runs succeeded`).
- [x] design doc 없이 brainstorming → writing-plans로 바로 plan 작성 —
      BF-M4는 새 아키텍처 결정이 없다고 사용자와 합의(2026-08-07)하고
      진행. plan:
      `docs/superpowers/plans/2026-08-07-tars-boot-foundation-bf-m4.md`
      (Task 1, Step 1~6 전부 완료 체크)
- [x] 전체 Boot Foundation design doc의 Status를 `Completed`로 갱신:
      `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md`

## 시도했으나 실패한 접근 / 중요한 정정

이번 세션(BF-M4)에서는 재시도나 정정 없이 plan대로 한 번에 성공함
(BF-M3와 대조적 — BF-M3는 Limine 조달 방식을 구현 직전에 한 번 뒤집었고,
`limine bios-install` 필요 여부도 실측으로 정정한 바 있음, 자세한 내용은
git log의 BF-M3 관련 커밋 및 `2026-08-06-tars-boot-foundation-bf-m3-design.md`
참고).

## 남은 작업

- [ ] **다음 서브프로젝트 선정.** Boot Foundation design doc 배경 절
      (`docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md`
      상단)에 나열된 최종 비전 후보: compositor/KMS, PTY/terminal, input
      policy, IME, 패키지 관리자(homebrew 스타일), AI 코딩 도구 통합
      (Claude Code/Codex). 어느 것을 먼저 할지 이번 세션에서 결정하지
      않았다 — 다음 세션 시작 시 사용자와 논의할 것.
- [x] 로컬 커밋을 origin/main에 push 완료(사용자가 직접 실행, `main`이
      이제 `origin/main`을 tracking, `d0cffff`까지 동기화됨).

## 핵심 파일

- `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md` —
  Boot Foundation 전체 design doc, Status가 이번 세션에 `Completed`로
  갱신됨. 다음 서브프로젝트 후보 목록이 배경 절에 있음.
- `docs/superpowers/plans/2026-08-07-tars-boot-foundation-bf-m4.md` —
  BF-M4 plan(design doc 없이 작성), Task 1 Step 1~6 전부 완료 체크.
- `check.sh`(저장소 루트) — BF-M4 산출물. `boot/check.sh`를 clean
  상태에서 3회 반복 호출하는 얇은 래퍼. 앞으로 회귀 검증용으로 계속
  쓸 수 있음(`docker run --rm --platform linux/amd64 -v "$PWD":/workspace
  -w /workspace tars-devcontainer bash check.sh`).
- `boot/check.sh`, `kernel/check.sh` — BF-M3/BF-M2에서 만들어진 하위
  체인 스크립트, BF-M4에서 수정 없이 그대로 재사용됨.
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`, `feedback_commit_delegation.md` —
  협업 원칙(변경 없음, 이번 세션도 계속 준수).

## 다음 에이전트에게

1. `git log --oneline -10`으로 실제 최근 커밋과 이 파일이 일치하는지
   먼저 대조할 것 — 최신 커밋은 `c8ee1e2`(BF-M4 plan 체크 + design doc
   완료 표시)여야 한다.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것 — 원칙 동일: Claude는 빌드/QEMU 부팅/devcontainer 내부
   조사성 명령을 직접 실행하지 않고 구현 파일도 직접 쓰지 않는다.
   design/plan/HANDOFF.md 작성과 승인된 git commit만 예외.
3. Boot Foundation은 **완전히 끝났다** — BF-M4 재작업 불필요. 첫
   메시지에서 사용자에게 "다음 서브프로젝트로 무엇을 할지"부터 물어볼
   것(위 "남은 작업" 목록 참고). 사용자가 이미 정해뒀다면 그 주제로
   바로 brainstorming 스킬을 사용해 design 필요 여부부터 확인한다.
4. Task 실행 방식(subagent-driven/inline)을 다시 묻지 말 것 — pairing
   방식으로 고정됨. design doc 필요 여부도 BF-M4처럼 "필요 없으면
   생략" 판단을 milestone/서브프로젝트마다 짧게 확인하고 넘어가면 됨.
