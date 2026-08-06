# HANDOFF: TARS Boot Foundation — BF-M3 완료, BF-M4 plan 착수 전

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
확정됨, pairing 고정. 외부 라이브러리/도구 조사(WebSearch/WebFetch,
공식 문서 확인)는 이 실행 제약 밖이며 이번 BF-M3에서도 Limine 공식 문서
조사에 적극 활용함.

## 현재 브랜치

`main` — 새 저장소의 root부터 시작. 이전 저장소(`tars.git`)의 commit
history는 이어받지 않음. Working tree는 깨끗함(커밋 안 된 변경 없음,
최신 커밋 `fe4ac19`).

## 완료된 작업

- [x] BF-M0, BF-M1, BF-M2 완료 (이전 handoff에서 기록됨)
- [x] **BF-M3 완료** — Limine(v12.5.2) bootloader + xorriso BIOS El
      Torito ISO를 `boot/check.sh`로 빌드해 QEMU `-cdrom out/tars.iso`
      **단독**(`-kernel`/`-initrd` 없이)으로 부팅, fish 배너 확인,
      `PASS`. **첫 실행에 바로 성공** — BF-M1/BF-M2와 달리 반복 디버깅
      없이 exit gate 통과. design doc 상태를 "Completed"로 갱신함:
      `docs/superpowers/specs/2026-08-06-tars-boot-foundation-bf-m3-design.md`
      plan의 Task 1~5 전부 완료:
      `docs/superpowers/plans/2026-08-06-tars-boot-foundation-bf-m3.md`
- [x] 구현 중 설계를 한 번 뒤집음(중요, 아래 "시도했으나 실패한 접근"
      참고) — Limine 조달 방식을 "git 소스 clone + autotools 빌드"에서
      "GitHub binary release 다운로드 + host 도구만 make"로 전환

## 시도했으나 실패한 접근 / 중요한 정정

1. **Limine "El Torito CD는 disk install 불필요" 가정이 틀림:**
   design 단계에서 처음엔 "El Torito boot catalog만 있으면 CD는 그냥
   부팅된다"고 가정했으나, Limine 공식 `USAGE.md`를 WebFetch로 직접
   읽어보니 `xorriso`로 ISO를 만든 뒤에도 **`limine bios-install
   out/tars.iso`를 반드시 실행**해야 한다는 게 명시돼 있었다(El Torito
   boot catalog는 `limine-bios-cd.bin`을 raw 이미지로 로드할 뿐, ISO의
   부트 섹터에 bootstrap 코드를 심는 별도 단계가 필요). design doc
   핵심 설계 결정 3에 정정 사항으로 기록함. 실제 실행 로그에서도
   `Setting partition 1 as active...`, `Limine BIOS stages installed
   successfully.`로 이 단계가 실제로 필요했음을 확인.
2. **Limine 조달 방식을 구현 시작 직전에 뒤집음(사용자 제안):**
   당초 design/plan 모두 "GitHub `v12.5.2` 태그를 git clone → `./bootstrap`
   (autotools) → `./configure --enable-bios-cd` → `make`"로 작성했고
   `configure.ac`까지 읽어 필요한 패키지(`nasm`, `autoconf`, `automake`)
   까지 확정했었다. 그런데 Task 1 구현 직전, 사용자가 "바이너리를 받아
   쓰면 안 되나?"라고 질문했고, 실제로 `limine-binary.tar.gz`를
   다운로드해 열어본 결과 부트로더 바이너리(`limine-bios.sys`,
   `limine-bios-cd.bin`)는 이미 컴파일돼 있고 host 도구(`limine` CLI)만
   `cc -std=c99 limine.c -o limine`로 빌드하면 된다는 게 확인됐다.
   Limine은 kernel/init과 달리 이 프로젝트가 내부 동작을 배우려는
   대상이 아니라 "설정이 단순해서" 고른 외부 도구이므로, autotools
   전체 체인을 끌어올 학습 이득이 없었다 — binary release로 전환해
   devcontainer 패키지도 `xorriso` 하나로 줄었다(`nasm`/`autoconf`/
   `automake` 불필요). **교훈:** design 단계에서 세운 계획도 구현
   직전 사용자의 "이게 최선인가?" 질문 한 번으로 크게 단순해질 수
   있다 — plan을 문서화했다고 해서 재검토를 멈추지 않았다.
3. **BF-M2 재확인 사항(참고용, 이번 세션 재발 없음):** controlling
   terminal 설정, fish `/usr/share/fish` 최소 자산 포함 등은 BF-M2에서
   이미 해결된 상태로 BF-M3 진입. 이번 milestone에서 kernel/init 쪽
   재발 문제는 없었음(부트로더 계층만 새로 추가됐고 그 위 스택은
   그대로 재사용됨).

## 남은 작업

- [ ] **BF-M4 plan 작성** — "전체 스크립트화 + 3회 연속 성공 검증"
      (전체 design doc 기준). 아직 design doc은 별도로 필요 없어
      보임(BF-M0~M3 스크립트를 그대로 묶어 반복 실행하는 성격이라 새
      아키텍처 결정이 크지 않음) — 다음 세션 시작 시 brainstorming
      스킬로 사용자와 짧게 확인하고, 필요 없다고 판단되면 바로
      writing-plans로 plan만 작성해도 됨. CLAUDE.md 원칙상 이 판단도
      독단적으로 생략하지 말고 사용자와 확인할 것.
- [ ] BF-M4 exit gate: 전체 체인(devcontainer 빌드 확인 제외하고
      kernel+init+boot 빌드부터 QEMU `-cdrom` 부팅까지)을 단일
      스크립트로 묶어 **3회 연속** 성공 확인(일관성 검증) — 전체 design
      doc의 BF-M4 절 참고.

## 핵심 파일

- `docs/superpowers/specs/2026-08-06-tars-boot-foundation-bf-m3-design.md`
  — BF-M3 design 최종본(Status: Completed). 핵심 설계 결정 1(Limine
  조달 방식, binary release로 정정된 최종판), 3(ISO 생성 + `limine
  bios-install` 정정)이 특히 재검토 과정을 상세히 기록.
- `docs/superpowers/plans/2026-08-06-tars-boot-foundation-bf-m3.md` —
  BF-M3 plan, Task 1~5 전부 완료 체크. Task 3이 처음 작성 시점(git
  clone+autotools)과 실제 구현 시점(binary release) 사이에 통째로
  다시 쓰인 사례.
- `boot/build.sh` — `limine-binary.tar.gz`(v12.5.2) 다운로드(없으면)
  + `make -C limine-binary`로 host 도구 `limine`만 빌드.
- `boot/make_iso.sh` — kernel bzImage + initrd + `limine.conf` +
  Limine 바이너리를 스테이징 → `xorriso -as mkisofs`(BIOS El Torito만,
  UEFI 플래그 없음) → **`limine bios-install`**(필수 단계) →
  `out/tars.iso`.
- `boot/check.sh` — 전체 체인(kernel→init→initrd→limine→ISO) 재실행 →
  `qemu-system-x86_64 -cdrom out/tars.iso`(`-kernel`/`-initrd` 없음) →
  fish 배너 grep → PASS/FAIL. 실행 결과 PASS 확인됨.
- `boot/limine.conf` — `protocol: linux`, `kernel_path`/`module_path`
  모두 `boot():/boot/...` 형식(단일 ISO9660 볼륨이라 파티션 번호 없음).
- `devcontainer/Dockerfile` — `xorriso` 패키지 추가됨(BF-M3용 유일한
  변경, `nasm`/`autoconf`/`automake`는 최종적으로 불필요해 추가 안 함).
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`, `feedback_commit_delegation.md` —
  협업 원칙(변경 없음, 이번 세션도 계속 준수).

## 다음 에이전트에게

1. `git log --oneline -20`으로 실제 최근 커밋과 이 파일이 일치하는지
   먼저 대조할 것 — 최신 커밋은 `fe4ac19`(BF-M3 완료 후 initrd.cpio
   갱신)여야 함.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것 — 원칙 동일: Claude는 빌드/QEMU 부팅/devcontainer 내부
   조사성 명령을 직접 실행하지 않고 구현 파일도 직접 쓰지 않는다.
   design/plan/HANDOFF.md 작성과 승인된 git commit만 예외. 외부 공식
   문서 조사(WebFetch/WebSearch)는 이 제약 밖이며 이번 세션에서도
   Limine `USAGE.md`/`CONFIG.md`/`INSTALL.md`/`configure.ac`를 직접
   조사해 두 차례(bios-install 필수 여부, binary release 대안)나 계획을
   실측으로 바로잡았다 — 이런 재검토는 계획 문서화 이후에도 계속
   허용된다는 걸 보여주는 사례다.
3. BF-M4(전체 스크립트화 + 3회 연속 성공 검증)부터 시작. brainstorming
   스킬로 "이 milestone에 별도 design doc이 필요한지"부터 사용자와
   짧게 확인하고, 필요 없다고 합의되면 곧장 writing-plans로 plan만
   작성한다 — CLAUDE.md의 "Milestone 단위 작업" 원칙(다음 milestone
   plan은 그 시점에 새로 작성, 미리 전체를 설계하지 않음)을 따른다.
4. Task 실행 방식(subagent-driven/inline)을 다시 묻지 말 것 — pairing
   방식으로 고정됨.
