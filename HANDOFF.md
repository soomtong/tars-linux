# HANDOFF: TARS Boot Foundation — BF-M0 완료, BF-M1 착수 전

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

- [x] 이전 로컬 작업 폴더 정리 (구 커밋/소스 삭제, remote를
      `git@github.com:soomtong/tars-linux.git`로 교체) — 사용자가 세션 중
      직접 수행
- [x] Design doc 작성:
      `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md`
      (BF-M0~M4 milestone 구조, 핵심 설계 결정 표 포함)
- [x] BF-M0 plan 작성:
      `docs/superpowers/plans/2026-08-01-tars-boot-foundation-bf-m0.md`
- [x] **BF-M0 완료** — Task 1(devcontainer) + Task 2(multiboot sanity
      check) 모두 구현·검증·커밋 완료. QEMU가 `-kernel`로 우리 ELF를 직접
      부팅해 serial에 `tars: sanity check ok` 출력 확인함 (design doc의
      BF-M0 exit gate 충족)
- [x] `.gitignore` 추가 (커밋 실수로 들어간 `*.o`, `sanity.elf` 빌드
      산출물 제거 — `git rm --cached` 후 재커밋으로 정정)

## 시도했으나 실패한 접근

- 없음. 단, 진행 중 사용자가 "done"이라 답했지만 실제로는
  `devcontainer/sanity/Makefile`이 생성되지 않았던 적 있음 (`check.sh`만
  존재) → `make` 실행 시 "No targets specified and no makefile found"로
  발견. **교훈:** 사용자가 "완료"라고 해도 다음 단계 진행 전 `find`/`Read`로
  파일 존재를 직접 확인할 것.
- git commit 시 `git add devcontainer/sanity/`로 빌드 산출물까지 실수로
  포함됨 → `.gitignore` 추가 + `git rm --cached`로 후속 커밋에서 정정.
  **교훈:** 커밋 전 `git status`로 무엇이 add됐는지 반드시 확인할 것
  (이번엔 사후 확인이라 한 박자 늦었음).

## 남은 작업

- [ ] BF-M1 plan 작성 및 실행: kernel.org 소스를 받아 자체 `.config`로
      최소 kernel 빌드, QEMU `-kernel`로 부팅해 init을 못 찾아 panic하는
      지점까지 확인 (의도된 실패 — "커널이 어디까지 책임지는지" 경계
      확인용). Design doc의 BF-M1 절 참고.
- [ ] BF-M2: Rust로 직접 만든 init(PID 1) — `/proc`, `/sys`, `devtmpfs`
      mount 후 shell 실행. 여전히 QEMU `-kernel`/`-initrd` direct boot
      (bootloader 아직 없음)
- [ ] BF-M3: Limine 설정 + `xorriso`로 hybrid ISO 생성, `-cdrom`으로 부팅
      (이때 devcontainer Dockerfile에 `xorriso`, `limine` 패키지 추가 필요
      — BF-M0에서 YAGNI로 의도적으로 뺐음, plan 파일에 명시돼 있음)
- [ ] BF-M4: 전체 스크립트화 + 3회 연속 성공 검증

## 핵심 파일

- `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md` — 전체
  설계, milestone 정의, 비목표, 저장소 구조 계획
- `docs/superpowers/plans/2026-08-01-tars-boot-foundation-bf-m0.md` — BF-M0
  plan (완료됨, BF-M1 plan 작성 시 이 문서의 구조/톤을 그대로 따를 것)
- `devcontainer/Dockerfile` — amd64 Debian + gcc-multilib/binutils/qemu-
  system-x86. BF-M1/M2에서 재사용, BF-M3에서 xorriso/limine 추가 예정
- `devcontainer/sanity/` — BF-M0 전용 일회성 검증 바이너리 (boot.S,
  linker.ld, kmain.c, Makefile, check.sh). 최종 산출물 아님, 참고용으로만
  남겨둠

## 다음 에이전트에게

1. 이 파일과 design doc(`docs/superpowers/specs/2026-08-01-tars-boot-
   foundation-design.md`)을 먼저 읽을 것.
2. 사용자가 별다른 지시 없이 세션을 시작하면, "BF-M1 plan을 작성할까요?"로
   물어볼 것 — BF-M0 완료 직후 자연스러운 다음 단계임.
3. BF-M1 plan 작성 시 `superpowers:writing-plans` skill을 다시 사용하고,
   BF-M0 plan(`2026-08-01-tars-boot-foundation-bf-m0.md`)과 동일한 bite-
   sized task 구조, 협업 방식(설명 → 사용자 실행 → 설명), commit은 Claude가
   수행하는 패턴을 그대로 유지할 것.
4. kernel.org 소스 다운로드 방식(어느 버전을 pin할지), `.config` 최소
   구성 전략은 아직 결정 안 됨 — BF-M1 브레인스토밍/plan 단계에서 정해야
   함 (design doc은 "필요한 옵션만 하나씩 켜며 이해"라는 원칙만 정해둠,
   구체적 커널 버전이나 config 옵션 목록은 미정).
