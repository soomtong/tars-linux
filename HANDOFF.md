# HANDOFF: TARS Boot Foundation — BF-M1 완료, BF-M2 착수 전

## 목표

TARS는 이전 저장소(`tars.git`)에서 이해 없이 누적된 잔손질(RC6~RC21)로
막혀서, 완전히 새 저장소(`tars-linux.git`, 현재 로컬 디렉터리)에서 처음부터
다시 시작하기로 함. 첫 서브프로젝트 **Boot Foundation**의 목표는 자체 빌드
Linux kernel + Limine bootloader + 직접 구현한 Rust init(PID 1) + xorriso
hybrid ISO로 QEMU에서 shell prompt까지 부팅하는 것. 최종 비전(macOS
키바인딩, ghostty 터미널, Linux homebrew, AI 도구 통합, 자체 CJK IME)은
이후 별도 서브프로젝트이며 이번 범위 밖.

**협업 방식(고정):** 설명 먼저 → 파일 작성/명령 실행은 사용자가 직접 →
결과 상세 설명. 승인된 내용의 git commit은 Claude Code가 대신 수행
(사용자 명시적 위임, 2026-08-02).

## 현재 브랜치

`main` — 새 저장소의 root부터 시작. 이전 저장소(`tars.git`)의 commit
history는 이어받지 않음 (완전 물리적 재시작).

## 완료된 작업

- [x] BF-M0 완료 (devcontainer + multiboot sanity check) — 이전 handoff에서
      이미 기록됨
- [x] BF-M1 design doc 작성:
      `docs/superpowers/specs/2026-08-03-tars-boot-foundation-bf-m1-design.md`
- [x] BF-M1 plan 작성:
      `docs/superpowers/plans/2026-08-03-tars-boot-foundation-bf-m1.md`
      (체크박스는 이번 세션에서 실제 완료 상태에 맞춰 전부 `- [x]`로 정정함)
- [x] **BF-M1 완료** — kernel.org 6.18.42 LTS 소스를 `kernel/build.sh`로
      받아 `allnoconfig`에서 시작한 x86_64 `.config`(`kernel/.config`)를
      콘솔/initrd/devtmpfs 옵션까지 반복 확장하며 빌드. 빈 `/init` 파일만
      담은 initrd(`kernel/make_initrd.sh` → `kernel/initrd.cpio`)로 QEMU
      `-kernel`/`-initrd` 부팅 시 `Kernel panic - not syncing: No working
      init found`가 재현됨을 이번 세션에서 `kernel/check.sh` 직접 실행으로
      재검증(PASS)함 — design doc의 BF-M1 exit gate 충족
- [x] devcontainer에 kernel 빌드 의존성 추가 (`flex`, `bison`, `bc`,
      `libssl-dev`, `libelf-dev`, `curl`, `cpio`, `rsync`)
- [x] `docs/study/note.md` — 사용자 개인 학습 노트 (study skill 결과물로
      추정, 별도 검토 안 함)

## 시도했으나 실패한 접근

- 완전히 빈 cpio(newc) initrd → 커널이 initramfs 자체를 포기하고 `VFS:
  Unable to mount root fs`로 panic. 목표(`No working init found`)에
  도달 못함. **해결:** 실행 권한만 있는 빈 `/init` 파일 하나를 담은
  cpio로 교체 (`kernel/make_initrd.sh` 참고, plan Task 4 Step 1에 기록됨).
- (BF-M0 단계) 사용자가 "done"이라 답했지만 실제로는
  `devcontainer/sanity/Makefile`이 생성 안 됐던 적 있음 → 이후 매번
  `find`/`Read`로 파일 존재를 직접 확인하는 습관으로 정착.
- **이번 세션에서 발견한 새로운 교훈:** 이전 세션에서 BF-M1을 design →
  plan → 전체 5개 Task까지 실제로 완료했는데, `HANDOFF.md`를 갱신하지
  않고 세션이 끝남 (마지막 handoff는 BF-M0 완료 시점 것 그대로 남아있었음).
  plan 파일의 체크박스도 `- [ ]`인 채로 방치됨. 이번 세션 시작 시
  `git log`를 먼저 확인하지 않았다면 이미 끝난 BF-M1을 처음부터 다시
  물어볼 뻔함. **교훈:** 세션 시작 시 HANDOFF.md만 믿지 말고 `git log
  --oneline -20`으로 실제 최근 커밋과 대조할 것. 한 milestone이 실제로
  끝나면(마지막 Task 커밋 완료 시점) 그 자리에서 바로 HANDOFF.md와 plan
  체크박스를 갱신할 것 — 다음 세션 시작까지 미루지 말 것.

## 남은 작업

- [ ] BF-M2 브레인스토밍 및 plan 작성·실행: Rust로 직접 구현한 init
      (PID 1)이 `/proc`, `/sys`, `devtmpfs`를 mount하고 shell을 실행.
      여전히 QEMU `-kernel`/`-initrd` direct boot (bootloader 아직 없음).
      initramfs(cpio) 패키징 방식, Rust 빌드 타깃(x86_64-unknown-linux-musl
      등 static 빌드 전략), shell 선택(busybox sh vs 다른 것) 등은 아직
      미정 — 브레인스토밍 단계에서 결정.
- [ ] BF-M3: Limine 설정 + `xorriso`로 hybrid ISO 생성, `-cdrom`으로 부팅
      (devcontainer Dockerfile에 `xorriso`, `limine` 패키지 추가 필요)
- [ ] BF-M4: 전체 스크립트화 + 3회 연속 성공 검증

## 핵심 파일

- `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md` —
  전체 설계, milestone 정의, 비목표, 저장소 구조 계획
- `docs/superpowers/specs/2026-08-03-tars-boot-foundation-bf-m1-design.md` —
  BF-M1 design (kernel 6.18.42, x86_64, allnoconfig 확장 전략, 빈 initrd로
  panic 재현)
- `docs/superpowers/plans/2026-08-03-tars-boot-foundation-bf-m1.md` —
  BF-M1 plan (완료됨, BF-M2 plan 작성 시 이 문서의 구조/톤을 그대로 따를 것)
- `kernel/.config:1-1560+` — allnoconfig에서 시작해 콘솔/initrd/devtmpfs
  옵션까지 켠 최소 `.config`. BF-M2에서 init이 필요로 하는 추가 옵션
  (예: pipe, signal, exec 관련은 이미 켜져 있을 가능성 높음)이 있으면
  같은 방식(반복 확장)으로 이어감
- `kernel/build.sh`, `kernel/make_initrd.sh`, `kernel/check.sh` — BF-M1
  빌드/initrd 생성/검증 스크립트. BF-M2에서 `make_initrd.sh`를 실제 Rust
  init 바이너리를 담도록 확장할 가능성 높음
- `kernel/src/`, `kernel/build/` — `.gitignore`됨 (재현 가능한 산출물).
  로컬에는 이미 존재하므로 재다운로드/재빌드 불필요, `kernel/build.sh`
  재실행 시 캐시 활용됨

## 다음 에이전트에게

1. 이 파일을 먼저 읽되, **반드시 `git log --oneline -20`으로 실제 최근
   커밋과 대조할 것** — 이번 세션에서 HANDOFF.md가 한 milestone(BF-M1)
   전체만큼 stale했던 전례가 있음.
2. BF-M2 브레인스토밍을 시작할 것 (`superpowers:brainstorming` skill).
   design doc(`2026-08-01-...-design.md`)의 BF-M2 절이 큰 틀(Rust init,
   `/proc`/`/sys`/devtmpfs mount, shell 실행, initramfs 패키징, `-kernel`/
   `-initrd` direct boot 유지)을 정해뒀지만, Rust 빌드 타깃과 static
   linking 전략, shell 바이너리 선택은 미정.
3. Plan 작성 시 `superpowers:writing-plans` skill을 사용하고, BF-M0/BF-M1
   plan과 동일한 bite-sized task 구조, 협업 방식(설명 → 사용자 실행 →
   설명), commit은 Claude가 수행하는 패턴을 유지할 것.
4. **한 milestone(모든 Task 커밋)이 끝나는 즉시 그 세션 안에서
   HANDOFF.md와 plan 체크박스를 갱신할 것** — 이번 세션에서 겪은 stale
   HANDOFF 문제를 반복하지 않기 위함.
