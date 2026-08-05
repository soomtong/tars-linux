# HANDOFF: TARS Boot Foundation — BF-M2 완료, BF-M3 design 착수 전

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
history는 이어받지 않음 (완전 물리적 재시작). Working tree는 깨끗함
(커밋 안 된 변경 없음).

## 완료된 작업

- [x] BF-M0, BF-M1 완료 (이전 handoff에서 기록됨)
- [x] **BF-M2 완료** — Rust init이 PID 1로 실행되어 `/proc`/`/sys`/`/dev`
      mount → controlling terminal 설정 → fish로 execve → QEMU serial에
      `Welcome to fish, the friendly interactive shell` 배너 확인,
      `kernel/check.sh` PASS(exit code 0). design doc 상태를 "Completed"로
      갱신함:
      `docs/superpowers/specs/2026-08-04-tars-boot-foundation-bf-m2-design.md`
      plan의 Task 1~5 모든 체크박스 완료:
      `docs/superpowers/plans/2026-08-05-tars-boot-foundation-bf-m2.md`
- [x] BF-M2 진행 중 devcontainer 베이스를 `debian:bookworm-slim` →
      `debian:trixie-slim`으로 전환, fish 3.6.0 → 4.0.2(Rust 재작성판)로
      업그레이드 (design doc 핵심 결정 4·5 참고)

## 시도했으나 실패한 접근 / 중요한 정정

BF-M2 구현 과정에서 계획에 없던 문제 4가지를 순서대로 만나 해결함
(모두 design doc/plan에 실측 결과로 기록돼 있음):

1. **`libc::environ` not found (E0425):** libc crate 0.2.189에서
   `libc::environ` 재노출이 빌드 실패. glibc가 제공하는 POSIX 심볼
   `environ`을 `extern "C"`로 직접 선언하는 방식으로 해결
   (`init/src/main.rs`, 커밋 `4f8eac9`). design doc 핵심 결정 2의 "raw
   FFI" 취지에 더 맞는 방식으로 판단함.
2. **`file` 명령 없음:** devcontainer 이미지에 `file` 패키지가 없어
   `file` 명령이 실패. 이미 설치된 `binutils`의 `readelf -h`로 대체
   (plan Task 2 Step 5).
3. **`Fish cannot find its asset files in '/usr/share/fish'`:** fish의
   내장 함수가 `/usr/share/fish/functions/*.fish` 스크립트로 구현돼
   있어 initramfs에 없으면 즉시 종료. `ldd`(링킹)·terminfo(외부 데이터
   조회)와는 다른 **세 번째 의존성 카테고리**. `functions/`,
   `config.fish`, `__fish_build_paths.fish`만 최소로 추려 포함
   (`kernel/make_initrd.sh`, 커밋 `a286c96`). 전체 `/usr/share/fish`는
   11M/1439개 파일이라 통째로 넣지 않음.
4. **`setpgid: Inappropriate ioctl for device` → `Attempted to kill
   init!` panic:** mount 이후 바로 execve하면 fish가 controlling
   terminal 부재로 job control 설정에 실패해 스스로 치명적 신호로
   종료 → 커널이 panic. fish 4.0은 멀티스레드라 panic 로그의 PID가
   개별 스레드 TID였지만 커널의 `is_global_init()`은 스레드 그룹 ID를
   본다는 것도 이 과정에서 확인함. `open("/dev/console")` → `setsid()`
   → `ioctl(fd, TIOCSCTTY, 0)` → `dup2(fd, 0/1/2)`를 mount와 execve
   사이에 추가하는 `setup_controlling_terminal()`로 해결
   (`init/src/main.rs`, 커밋 `b7b5bf7`). 이건 "PID 1은 다른 누구도
   대신해주지 않는다"는 이번 서브프로젝트 핵심 주제와 정확히 맞닿는
   지점이었음.

또한 fish 버전 자체를 3.6.0(bookworm)에서 4.0.2(trixie)로 바꾸기로
사용자가 결정하면서, 이미 커밋했던 design doc의 실측 결론(terminfo 필요)이
뒤집힘 — fish 4.0(Rust 재작성)은 terminfo 없이도 경고 없이 조용히
동작함을 재실측으로 확인하고 `/usr/lib/terminfo/l/linux` 포함 로직을
제거함. **교훈:** 실측 기반 결론도 전제(라이브러리 버전 등)가 바뀌면
반드시 재검증해야 하며, 이 프로젝트는 그 원칙을 실제로 지켰음(블로그
서술만 믿지 않고 매번 `env -i fish ...` 류 실험으로 재확인).

## 남은 작업

- [ ] **BF-M3 design doc 작성** — Limine bootloader + xorriso hybrid ISO.
      아직 착수 전. `docs/superpowers/specs/`에
      `2026-08-0X-tars-boot-foundation-bf-m3-design.md` 형식으로 작성
      예정 (파일명 날짜는 실제 작성일 기준으로 정할 것). CLAUDE.md 원칙상
      BF-M3 plan은 design 승인 후 별도로 작성 — 지금 단계에서 plan까지
      미리 쓰지 않는다.
- [ ] BF-M3 완료 후 BF-M4: 전체 스크립트화 + 3회 연속 성공 검증

## 핵심 파일

- `docs/superpowers/specs/2026-08-04-tars-boot-foundation-bf-m2-design.md`
  — BF-M2 design 최종본(Status: Completed). 특히 핵심 결정 3(init 동작
  순서, controlling terminal 추가분)과 핵심 결정 4(fish shell/의존성
  3종 카테고리: ldd 링킹, terminfo, `/usr/share/fish` 에셋)가 BF-M3
  design 작성 시 참고할 만한 실측 패턴(가정하지 말고 항상 재측정)을
  보여줌.
- `docs/superpowers/plans/2026-08-05-tars-boot-foundation-bf-m2.md` —
  BF-M2 plan, Task 1~5 전부 완료 체크. 각 Task의 "갱신"/"추가 커밋"
  노트에 실제로 부딪힌 문제와 해결 과정이 순서대로 기록돼 있음.
- `init/src/main.rs` — 최종 init 구현: mount 3회 →
  `setup_controlling_terminal()` → execve. `environ`은 `extern "C"`로
  직접 선언(라인 상단).
- `kernel/make_initrd.sh` — init/fish/공유 라이브러리/`/usr/share/fish`
  최소 에셋을 cpio로 패키징. terminfo는 포함하지 않음.
- `kernel/check.sh` — exit gate가 fish 배너 grep으로 변경됨, PASS 확인됨.
- `devcontainer/Dockerfile` — 베이스 이미지 `debian:trixie-slim`,
  rustup(`x86_64-unknown-linux-gnu`, stable, minimal profile) + `fish`
  apt 패키지 추가됨.
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`, `feedback_commit_delegation.md` — 협업
  원칙(Claude는 빌드/QEMU/조사성 명령 직접 실행 안 함, 구현 파일도 직접
  안 씀, design/plan/HANDOFF 문서와 승인된 git commit만 예외). 이번
  세션에서는 이 원칙을 계속 지켰음(fish 4.0 웹 리서치만 Claude가 직접
  수행 — 이건 devcontainer 내부 조사가 아니라 일반 웹 검색이라 범위 밖
  아님).

## 다음 에이전트에게

1. `git log --oneline -20`으로 실제 최근 커밋과 이 파일이 일치하는지
   먼저 대조할 것 — 최신 커밋은 `38adaeb`(BF-M2 완료 기록)여야 함.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것 — 원칙은 동일하게 유지: Claude는 빌드/QEMU 부팅/
   devcontainer 내부 조사성 명령을 직접 실행하지 않고, 구현 파일도
   직접 쓰지 않는다. design/plan 문서와 HANDOFF.md 작성, 승인된 git
   commit만 예외. 웹 검색(WebSearch/WebFetch)으로 외부 정보(라이브러리
   버전, 릴리스 노트 등)를 조사하는 것은 이 제약 밖이며 이번 세션에서도
   실제로 활용함(fish 4.0 릴리스 조사).
3. BF-M3(Limine bootloader + xorriso hybrid ISO) design doc을 새로
   작성하는 것부터 시작. 아직 아무 내용도 없음 — 이전 BF-M1/BF-M2
   design doc의 구조(배경 → 목표 → 비목표 → 핵심 설계 결정 → 저장소
   구조 변경 → 검증 방법 → 협업 방식)를 참고해서 작성하되, 먼저
   brainstorming 형태로 사용자와 방향(Limine 버전, BIOS/UEFI 중 무엇을
   먼저 다룰지, xorriso 옵션 등)을 정하고 문서화할 것.
4. Task를 실행 방식(subagent-driven/inline)으로 처리할지 다시 묻지
   말 것 — pairing 방식으로 고정됨.
