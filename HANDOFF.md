# HANDOFF: Terminal Foundation design + TF-M0 plan 완료, 실행 대기

## 목표

Display Foundation(DF-M0~M3, 2026-08-08 완료) 이후 세 번째 서브프로젝트로
**Terminal Foundation**을 brainstorming → writing-plans 스킬로 진행했다.
이번 세션에서 design doc과 TF-M0(검증 파이프라인 확장) plan을 모두
작성·커밋했고, **아직 TF-M0의 실제 실행(Task 1 Step 1)은 시작 전**이다.

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행은 **사용자가 직접** → 결과를 사용자가 전달하면 Claude가 상세
해석. Claude는 design/plan 문서·`HANDOFF.md` 작성과 **승인된** 내용의
git commit만 대신 수행한다(`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고). 이 plan은 `writing-plans` 스킬의
기본 handoff(subagent-driven/inline execution 선택)를 명시적으로
따르지 않고 pairing 방식으로 작성됐다 — plan 파일 상단에 이 저장소는
pairing 고정이라는 override 문구가 이미 들어 있다.

## 현재 브랜치

`main` — **origin/main보다 4커밋 앞서 있고 아직 push 안 함**
(`git push` 실행 전, 사용자 확인 필요). Working tree 깨끗함(커밋 안 된
변경 없음). 최신 커밋 `33999eb`.

## 완료된 작업

- [x] **다음 서브프로젝트 결정: Compositor → Terminal Foundation.**
      brainstorming 스킬로 진행하며 "compositor"라는 이름이 실제로는
      불필요하다는 것을 발견함(터미널 앱 하나만 화면을 독점, 다른 독립
      앱 구동 계획 없음 → 여러 프로세스 화면 중재가 필요 없음).
- [x] **Design doc 작성·커밋** —
      `docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md`
      (커밋 `1d905cb`, 이후 `81f2972`/`99a4546`로 두 차례 수정):
  - 아키텍처: 단일 프로세스가 KMS/DRM 디스플레이 독점(compositor
    프로토콜 없음)
  - 터미널 코어: `libghostty-vt`(Ghostty의 ANSI/VT 파싱 하위 컴포넌트,
    "extremely stable" 기능 + 유동적 API — 조사 후 확정)
  - 구현 언어: **Zig**(이 서브프로젝트부터 도입, `kernel`/`init`/`kms`는
    기존대로 Rust 유지)
  - 폰트: `8x4x4-fonts`(iolo, 한글 조합형 지원 비트맵 원본 → TTF 배포)를
    `stb_truetype`으로 시작 시 1회 래스터라이징 → glyph cache → blit
  - PTY: `libc openpty()/forkpty()` (raw syscall 대신 — 새 의존성
    아니고, 이 프로젝트의 학습 목적과 거리가 먼 보일러플레이트라 판단)
  - 입력: **raw evdev 직접 파싱**(`libevdev` 도입을 검토했다가 재검토
    끝에 철회 — 아래 "시도했으나 철회한 접근" 참고) + macOS 스타일
    modifier/조합 dispatch(cmd+1~9 탭 전환 등)를 직접 구현
- [x] **TF-M0 plan 작성·커밋** —
      `docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m0.md`
      (커밋 `33999eb`). 웹 조사로 모든 버전/URL을 실제로 고정함:
  - Zig 0.16.0 (`https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz`)
  - `libghostty-vt`: ghostty-org/ghostty 커밋
    `2602886144c7e95099c9e2ba07f181c69e7276f3` 고정, `zig build
    -Demit-lib-vt`로 빌드
  - `8x4x4-fonts`: 릴리스 태그 `v0.0.7`, zip에서 `Hanme_8x4x4.ttf`만 추출
  - `stb_truetype.h`: nothings/stb 커밋
    `2c980bb59875b0d32144a71867fbdebb2f77cd20` 고정
  - Task 1(Zig+xz-utils+unzip devcontainer 추가) → Task 2(`libghostty-vt`
    벤더링+빌드) → Task 3(링크 sanity check, 공식 예제 기반 OSC 파싱
    프로그램) → Task 4(`8x4x4-fonts` 확보) → Task 5(`stb_truetype`로
    실제 글리프 래스터라이징 확인)

## 시도했으나 철회한 접근

**입력 처리에 `libevdev` 도입 → 재검토 후 raw evdev로 되돌림.** 처음엔
"capability 열거·`SYN_DROPPED` 재동기화를 작은 C 헬퍼에 맡기자"고
design doc에 넣었다(커밋 `81f2972`). 그런데 사용자가 다시 검토를
요청해서 짚어보니:
- `libevdev`가 아껴주는 코드량(~50~100줄)이 `stb_truetype`/
  `libghostty-vt`가 아껴주는 양(수천 줄, 수십 년치 호환성)에 비해
  훨씬 작음
- 저빈도 키보드/마우스 입력에서 `SYN_DROPPED`가 실제로 발생할
  가능성이 낮음
- macOS 스타일 modifier/조합 dispatch를 위해 raw `input_event`를
  어차피 직접 들여다봐야 해서 `libevdev`의 이점이 희석됨
- 새 FFI 의존성을 하나 더 늘릴 실익이 없다고 판단

결국 `kms`와 같은 수준의 raw ioctl 직접 구현으로 되돌렸다(커밋
`99a4546`). **교훈:** 외부 라이브러리 도입 결정은 "얼마나 위험한/복잡한
부분을 대신해주는가"를 구체적 코드량으로 따져야 한다 — "작은 헬퍼
같으니 괜찮겠지"라는 느낌만으로 판단하면 나중에 뒤집힐 수 있다.

## 남은 작업

- [ ] **TF-M0 Task 1부터 실행 시작.** plan의 Task 1 Step 1(devcontainer
      Dockerfile에 Zig 0.16.0 + `xz-utils`/`unzip` 추가)부터 사용자가
      직접 파일을 수정하고 명령을 실행한다.
- [ ] (TF-M0 완료 후) TF-M1(프레임버퍼 텍스트 렌더링) plan을 새로
      작성 — design doc의 milestone 초안(TF-M0~M4)에 따라 한 번에 하나씩.
- [ ] **origin/main에 push 여부 확인.** 현재 로컬이 4커밋 앞서 있고
      아직 push하지 않았다 — 사용자에게 물어보고 진행한다.

## 핵심 파일

- `docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md` —
  Terminal Foundation design doc 전체(배경, MVP 목표/비목표, 핵심 설계
  결정 6개 항목, milestone 초안 TF-M0~M4).
- `docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m0.md` —
  TF-M0 plan, Task 1~5, 아직 체크된 Step 없음(실행 전).
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`, `feedback_commit_delegation.md` —
  협업 원칙(변경 없음).

## 다음 에이전트에게

1. `git log --oneline -8` && `git status`로 이 파일과 실제 상태가
   일치하는지 먼저 확인 — 최신 커밋 `33999eb`, origin/main보다 4커밋
   앞섬(미push), working tree 깨끗해야 한다.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것.
3. TF-M0 plan(`docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m0.md`)의
   Task 1 Step 1부터 시작 — 사용자에게 Dockerfile 수정 내용을 설명하고
   직접 편집/빌드하도록 안내한다. Task/Step을 건너뛰거나 순서를 바꾸지
   말 것.
4. 각 Step 실행 결과(로그, 에러)를 사용자가 붙여주면 Claude가 해석하고
   다음 Step으로 안내한다. Claude가 직접 build/docker run/QEMU 명령을
   실행하지 않는다(웹 리서치·`git`/`find`/`Read` 같은 읽기 전용 확인은
   허용).
5. 실행 방식(pairing)과 design doc 필요 여부 판단 기준을 다시 묻지
   말 것 — 이미 여러 서브프로젝트에 걸쳐 확정됨.
