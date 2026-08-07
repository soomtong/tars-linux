# HANDOFF: Display Foundation 전체 완료(DF-M0~M3) — 다음 서브프로젝트 미정

## 목표

Boot Foundation(BF-M0~M4, 2026-08-07 완료) 이후 두 번째 서브프로젝트인
**Display Foundation**(KMS/DRM으로 화면에 픽셀을 띄우는 것까지, 4단계
milestone DF-M0~M3)을 진행해 왔다. **이번 세션에서 DF-M3(종료 게이트)를
완료해 Display Foundation 서브프로젝트 전체(DF-M0~M3)가 끝났다.** 다음
서브프로젝트 착수 여부/대상은 아직 논의 전이다.

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행은 **사용자가 직접** → 결과를 사용자가 전달하면 Claude가 상세
해석. Claude는 design/plan 문서·`HANDOFF.md` 작성과 **승인된** 내용의
git commit만 대신 수행한다(`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고). 실행 방식을 milestone마다 다시
묻지 말 것 — 고정됨. 새 milestone/서브프로젝트 착수 전 "design doc이
필요한가"는 brainstorming 스킬로 짧게 확인하되, 새 아키텍처 결정이 없다고
판단되면 생략하고 바로 writing-plans로 넘어가도 된다(BF-M4, DF-M1~M3
선례).

## 현재 브랜치

`main` — 로컬이 origin/main보다 6커밋 앞서 있음(push는 사용자 판단, 이번
세션에서 요청받지 않음). Working tree 완전히 깨끗함(커밋 안 된 변경
없음). 최신 커밋 `fbaf390`.

## 완료된 작업

- [x] DF-M0~M2(검증 파이프라인, PCI+DRM 드라이버, 픽셀 그리기) — 이전
      세션에 완료(자세한 내용은 git log 참고, `40aade5` 이전 커밋들).
- [x] **DF-M3(종료 게이트) 완료·커밋** —
      `docs/superpowers/plans/2026-08-07-tars-display-foundation-df-m3.md`
      전체 실행:
  - `display/check.sh`에 kernel/init/kms 빌드 단계를 추가해 자기 완결적
    스크립트로 만듦(이전엔 사용자가 수동으로 미리 빌드해둔 뒤에만 실행
    가능했음) — 커밋 `44ed869`.
  - **정정(중요, 아래 절 참고):** `boot/check.sh`에도 `kms` crate 빌드
    단계를 추가 — 커밋 `e69ea47`.
  - 루트 `check.sh`를 `run_chain()` 함수로 일반화해 BF 체인
    (`boot/check.sh`)과 DF 체인(`display/check.sh`)을 각각 3회씩 연속
    검증하도록 확장(`clean()`에 `kms/target`도 추가) — 커밋 `f29f63e`.
  - 3회 연속 실행(BF 3회 + DF 3회, kernel 총 6회 재빌드)에서
    `TARS check PASS: all chains 3/3 consecutive runs succeeded`로
    **최종 PASS 확인함** — 커밋 `1e86227`(initrd.cpio 갱신).
  - design doc Status를 `DF-M3 complete (2026-08-08); Display Foundation
    complete`로 갱신 — 커밋 `fbaf390`.

## 시도했으나 실패한 접근 / 중요한 정정

DF-M3 Task 2 Step 3(루트 `check.sh` 3회 실행)을 처음 돌렸을 때 **BF-M4
체인이 1회차부터 실패**했다:

```
cp: cannot stat '../kms/target/release/kms': No such file or directory
BF-M4 FAIL: run 1/3 failed
```

**원인:** DF-M2에서 `kernel/make_initrd.sh`가 무조건
`../kms/target/release/kms`를 initrd에 복사하도록 바뀌었는데,
`boot/check.sh`(Boot Foundation 산출물)는 `kernel`과 `init`만 빌드하고
`kms`는 빌드하지 않았다. DF-M2 이후 `boot/check.sh`가 재실행된 적이 없어서
지금까지 드러나지 않았던 **회귀**였다 — 이번에 루트 `check.sh`를 BF+DF
둘 다 검증하도록 확장하면서 처음 발견됐다(DF-M3 plan의 Architecture 절이
예상했던 "회귀 안전망" 효과가 실제로 작동한 사례).

**수정:** `boot/check.sh`의 빌드 단계에 `(cd ../kms && cargo build
--release)`를 추가(`display/check.sh`와 동일한 패턴). 커밋 `e69ea47`에
plan 문서의 "정정" 노트와 함께 기록돼 있다.

**교훈(다음에 새 crate를 추가할 때 참고):** `kernel/make_initrd.sh`처럼
여러 진입점(`boot/check.sh`, `display/check.sh`, `kernel/check.sh` 등)이
공유하는 스크립트를 수정할 때는, 그 스크립트를 호출하는 **모든** 진입점이
새로운 전제조건(여기선 "kms가 미리 빌드돼 있어야 함")을 만족하는지 확인해야
한다 — 한 진입점(`display/check.sh`)만 테스트하고 넘어가면 다른 진입점이
조용히 깨질 수 있다.

## 남은 작업

- [ ] **다음 서브프로젝트 착수 여부/대상을 사용자와 논의.** 최종 비전
      후보 목록은 `docs/superpowers/specs/
      2026-08-01-tars-boot-foundation-design.md`의 "배경" 절 참고
      (compositor, PTY/terminal, input policy, IME, 패키지 관리자, AI
      도구 통합 등). Display Foundation이 KMS/DRM 기반을 만들었으니,
      다음 후보로는 그 위에서 동작할 compositor가 자연스러운 선택지일 수
      있지만 확정된 건 없다.
- [ ] (선택) 로컬 6커밋(이번 세션 DF-M3 작업분 포함 총 누적분)을
      origin/main에 push할지 사용자에게 확인.

## 핵심 파일

- `docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md` —
  Display Foundation 전체 design doc. Status가 `DF-M3 complete
  (2026-08-08); Display Foundation complete`로 갱신됨 — 이 서브프로젝트는
  이제 완전히 끝났다.
- `docs/superpowers/plans/2026-08-07-tars-display-foundation-df-m3.md` —
  DF-M3 plan, 모든 Step 체크 완료. 위에서 언급한 `boot/check.sh` 회귀의
  "정정" 노트가 Task 2 Step 3에 기록돼 있음.
- `check.sh`(저장소 루트) — 이제 BF-M4 체인(`boot/check.sh`)과 DF-M3 체인
  (`display/check.sh`)을 각각 3회씩 연속 검증하는 `run_chain()` 기반
  스크립트. `clean()`이 `kernel/build`, `init/target`, `kms/target`,
  `out`을 지운다.
- `boot/check.sh` — 이제 `kernel`→`init`→`kms`→`make_initrd.sh`→ISO 빌드
  순서로 자기 완결적. `kms` 빌드 단계가 이번 세션에 추가됨.
- `display/check.sh` — 이제 `kernel`→`init`→`kms`→`make_initrd.sh`→QEMU
  screendump 검증까지 자기 완결적(이전엔 빌드 단계가 없어 사용자의 수동
  사전 빌드에 의존했음).
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`, `feedback_commit_delegation.md` —
  협업 원칙(변경 없음).

## 다음 에이전트에게

1. `git log --oneline -10` && `git status`로 이 파일과 실제 상태가
   일치하는지 먼저 확인 — 최신 커밋 `fbaf390`, working tree 깨끗해야
   한다.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것.
3. Display Foundation은 완전히 끝났으므로, 이번 세션 시작 시 사용자에게
   **다음 서브프로젝트를 무엇으로 할지**부터 물어볼 것 — design doc의
   최종 비전 후보 목록(위 "남은 작업" 절 참고)을 근거로 제시하되, 확정은
   사용자가 한다.
4. 새 서브프로젝트가 정해지면, 새 아키텍처 결정이 있는지 brainstorming
   스킬로 짧게 확인 후 design doc이 필요하면 작성하고, 이후
   writing-plans로 첫 milestone(M0) plan을 작성하는 순서로 진행한다
   (BF/DF 선례).
5. 실행 방식(pairing)과 design doc 필요 여부 판단 기준을 다시 묻지
   말 것 — 이미 여러 서브프로젝트에 걸쳐 확정됨.
