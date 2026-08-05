# HANDOFF: TARS Boot Foundation — BF-M2 design/plan 완료, 구현 착수 전

## 목표

TARS는 이전 저장소(`tars.git`)에서 이해 없이 누적된 잔손질(RC6~RC21)로
막혀서, 완전히 새 저장소(`tars-linux.git`, 현재 로컬 디렉터리)에서 처음부터
다시 시작하기로 함. 첫 서브프로젝트 **Boot Foundation**의 목표는 자체 빌드
Linux kernel + Limine bootloader + 직접 구현한 Rust init(PID 1) + xorriso
hybrid ISO로 QEMU에서 shell prompt까지 부팅하는 것. 최종 비전(macOS
키바인딩, ghostty 터미널, Linux homebrew, AI 도구 통합, 자체 CJK IME)은
이후 별도 서브프로젝트이며 이번 범위 밖.

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행(빌드, 조사용 명령 포함)은 **사용자가 직접** → 결과를 사용자가
전달하면 Claude가 상세 해석. Claude는 design/plan 문서·`HANDOFF.md`
작성과 승인된 내용의 git commit만 대신 수행한다 (`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고). **실행 방식(subagent-driven/
inline/pairing)을 milestone마다 다시 묻지 말 것** — 이미 여러 차례
확정됨, pairing 고정.

## 현재 브랜치

`main` — 새 저장소의 root부터 시작. 이전 저장소(`tars.git`)의 commit
history는 이어받지 않음 (완전 물리적 재시작).

## 완료된 작업

- [x] BF-M0, BF-M1 완료 (이전 handoff에서 기록됨, 이번 세션 시작 시
      `kernel/check.sh` 실행으로 BF-M1 exit gate 재확인함)
- [x] BF-M2 design doc 작성·커밋:
      `docs/superpowers/specs/2026-08-04-tars-boot-foundation-bf-m2-design.md`
      — Rust std+glibc 동적 링크, `libc` crate raw FFI로 mount/execve,
      shell은 **fish**(bash 아님, 아래 참고), rustup으로 devcontainer에
      Rust 툴체인 추가
- [x] BF-M2 implementation plan 작성·커밋:
      `docs/superpowers/plans/2026-08-05-tars-boot-foundation-bf-m2.md`
      — Task 1~5, self-review 완료(mount point 디렉터리 누락 문제를
      Task 4에 미리 반영함)

## 시도했으나 실패한 접근 / 중요한 정정

- **bash → fish 전환:** 당초 design은 bash를 shell로 채택했으나, 사용자
  요청으로 devcontainer 안에서 `ldd`/terminfo 실측 조사 후 fish로
  변경함. 실측 결과: fish는 bash 대비 `.so` 4개(`libpcre2-32`,
  `libstdc++`, `libm`, `libgcc_s`) 추가 필요, fish-common의 completion
  스크립트/config는 불필요, **terminfo 데이터 파일**(`/usr/lib/terminfo/
  l/linux`)은 `ldd`로 안 잡히는 별도 카테고리 의존성이라 명시적으로
  initramfs에 포함하기로 결정. exit gate 판정 문자열도 fish 배너
  (`Welcome to fish, the friendly interactive shell`)로 변경. 상세는
  design doc 핵심 설계 결정 4 참고.
- **HANDOFF.md가 BF-M1 전체만큼 stale했던 문제(이전 세션):** 이번 세션
  시작 시 `HANDOFF.md`는 "BF-M0 완료, BF-M1 착수 전"이라고 돼 있었지만
  실제 `git log`를 보니 BF-M1이 design→plan→구현 5개 Task까지 전부
  끝나 있었다. **교훈:** 세션 시작 시 `HANDOFF.md`만 믿지 말고 반드시
  `git log --oneline -20`으로 실제 최근 커밋과 대조할 것.
- **이번 세션에서 CLAUDE.md 협업 원칙을 벗어났던 지점(중요, 재발 방지
  필요):**
  1. BF-M1 완료 여부를 "검증"한다며 `docker run ... kernel/check.sh`
     (빌드+QEMU 부팅 전체)를 Claude가 직접 실행함. CLAUDE.md의 "진행
     전 검증은 Claude Code 책임" 조항은 `find`/`Read`로 파일 존재·
     내용만 확인하라는 것이지 빌드/부팅 재실행을 허용하는 게 아님.
  2. fish feasibility 조사를 위해 devcontainer 안에서 `apt-get install
     fish`, `ldd`, terminfo 실험 등을 Claude가 직접 실행함.
  3. `writing-plans` skill의 기본 흐름을 따라가다 기존 메모리
     (`feedback_commit_delegation.md`: "실행 방식을 milestone마다
     다시 묻지 말 것")를 놓치고 Subagent-driven/Inline Execution
     옵션을 다시 제시함.

  사용자가 지적해 바로잡음 — 이미 커밋된 문서/검증은 예외로 두되,
  **BF-M2 구현부터는 원칙을 엄격히 지키기로 확정**. 상세 내용과 적용
  범위는 `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`에 기록됨 — 다음 세션은 반드시 이 메모리를
  먼저 확인할 것.

## 남은 작업

- [ ] BF-M2 plan(`docs/superpowers/plans/2026-08-05-tars-boot-
      foundation-bf-m2.md`)의 **Task 1부터** 순서대로 pairing 방식으로
      실행:
  - Task 1: devcontainer에 rustup + fish 추가 (아직 파일 수정 전 —
    이번 세션 마지막에 Task 1 Step 1~3을 사용자에게 설명만 하고 실행은
    안 함)
  - Task 2: Rust init 프로젝트 뼈대 (`init/Cargo.toml`, `init/src/main.rs`
    최소 버전)
  - Task 3: mount 3회 + execve로 fish 실행 로직 완성
  - Task 4: `kernel/make_initrd.sh` 확장 (init+fish+라이브러리+terminfo
    패키징)
  - Task 5: `kernel/check.sh`를 fish 배너 grep으로 변경 + 전체 QEMU
    부팅 검증까지 exit gate 통과
- [ ] BF-M2 완료 후 BF-M3(Limine + xorriso hybrid ISO) design/plan 작성
- [ ] BF-M4: 전체 스크립트화 + 3회 연속 성공 검증

## 핵심 파일

- `docs/superpowers/specs/2026-08-04-tars-boot-foundation-bf-m2-design.md`
  — BF-M2 design (fish로 정정된 최종본)
- `docs/superpowers/plans/2026-08-05-tars-boot-foundation-bf-m2.md` —
  BF-M2 plan, Task 1부터 시작. Task 4에 mount point 디렉터리 생성 로직
  이미 반영돼 있음(self-review에서 발견한 버그 사전 수정)
- `devcontainer/Dockerfile` — 아직 Rust/fish 미추가 상태. Task 1에서
  수정 대상
- `kernel/.config`, `kernel/build.sh`, `kernel/check.sh`,
  `kernel/make_initrd.sh` — BF-M1 산출물, BF-M2에서 `make_initrd.sh`/
  `check.sh`를 확장함(아직 미착수)
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md` — 이번 세션에서 새로 기록한 협업 원칙
  준수 가이드. **다음 세션 시작 시 반드시 먼저 읽을 것**

## 다음 에이전트에게

1. `git log --oneline -20`으로 실제 최근 커밋과 이 파일이 일치하는지
   먼저 대조할 것.
2. `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
   feedback_execution_scope.md`와 `feedback_commit_delegation.md`를
   먼저 읽을 것 — 이번 세션에서 겪은 원칙 위반을 반복하지 않기 위함.
   핵심: **Claude는 빌드/QEMU 부팅/조사성 명령을 직접 실행하지 않고,
   구현 파일(Dockerfile, init 소스, 스크립트)도 직접 쓰지 않는다.**
   design/plan 문서와 `HANDOFF.md` 작성, 승인된 git commit만 예외.
3. BF-M2 plan(`docs/superpowers/plans/2026-08-05-tars-boot-foundation-
   bf-m2.md`)의 Task 1 Step 1부터 시작 — Dockerfile에 rustup 설치
   스텝과 `fish` apt 패키지를 추가하는 이유를 설명하고, 사용자가 직접
   파일을 수정하고 `docker build`/버전 확인 명령을 실행하도록 안내한다.
   결과를 받으면 해석하고, 확인되면 Claude가 커밋한다.
4. Task를 실행 방식(subagent-driven/inline)으로 처리할지 다시 묻지
   말 것 — pairing 방식으로 고정됨.
