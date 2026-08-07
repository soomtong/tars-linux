# TARS Boot Foundation — BF-M4 종료 게이트 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, HANDOFF.md 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** BF-M4를 완료한다 — BF-M0~M3 전체 체인(kernel 빌드 → init 빌드 →
initrd 생성 → Limine 빌드 → hybrid ISO 생성 → QEMU `-cdrom` 부팅 → fish 배너
확인)을 재현 가능한 방식으로 **3회 연속 성공**시켜 Boot Foundation
서브프로젝트의 종료 게이트를 통과한다.

**Architecture:** `boot/check.sh`가 이미 BF-M0~M3 전체 체인을 단일 스크립트로
묶어 놓았으므로 새 아키텍처 결정은 없다. 저장소 루트에 `check.sh`를 추가해
`boot/check.sh`를 3회 반복 호출하는 얇은 래퍼로 둔다. 매 회 시작 전
빌드 산출물(`kernel/build/`, `init/target/`, `out/`)을 삭제해 incremental
캐시에 의존한 우연한 성공을 배제하고(다운로드 캐시인 `kernel/src/`,
`boot/limine-binary/`는 유지 — 재다운로드는 이번 검증 목표인 "빌드
재현성"과 무관하고 네트워크 의존성만 늘림), `set -e` 없이 각 회 결과를
직접 검사해 실패 시 몇 번째 회차에서 실패했는지 출력하고 즉시 중단한다
(fail-fast). devcontainer 이미지 자체의 빌드는 체인에 포함하지 않는다 —
이미 BF-M3에서 만들어진 `tars-devcontainer` 이미지를 그대로 사용한다.

**Tech Stack:** bash, Docker(`tars-devcontainer` 이미지, BF-M3 산출물),
`boot/check.sh`(BF-M0~M3 산출물, 수정 없음)

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행한다. BF-M3까지 완료되어 `tars-devcontainer` 이미지가 빌드돼 있고
`boot/check.sh` 단독 실행이 PASS함이 확인된 상태여야 한다(HANDOFF.md 기준
최신 커밋 `a5a66f2`, BF-M3 완료).

**brainstorming 단계 결정 사항(design doc 없이 바로 plan 작성):**
- BF-M4는 새 아키텍처 결정이 없어 별도 design doc을 생략하기로 사용자와
  합의함(2026-08-07).
- 3회 연속 실행 중 중간 실패 시 **즉시 중단(fail-fast)**으로 처리 — design
  doc(`2026-08-01-tars-boot-foundation-design.md`) BF-M4 절의 "3회 연속
  성공"이라는 exit gate 문구에 가장 부합하는 해석(어차피 한 번이라도
  실패하면 일관성 검증은 실패한 것).
- 매 회 실행 전 **빌드 산출물만** 깔끔히 지우고(`kernel/build/`,
  `init/target/`, `out/`), **다운로드 캐시는 유지**(`kernel/src/`,
  `boot/limine-binary/`) — 네트워크/미러 의존성을 3배로 늘리지 않으면서도
  "소스로부터 매번 동일하게 빌드되는가"를 검증하기에 충분함.

---

### Task 1: 루트 `check.sh` — 3회 연속 clean 빌드 검증

**Files:**
- Create: `check.sh` (저장소 루트)

- [x] **Step 1: `check.sh` 작성**

`check.sh`(저장소 루트):
```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

clean() {
  rm -rf kernel/build init/target out
}

for i in 1 2 3; do
  echo "=== BF-M4 run ${i}/3 ==="
  clean
  if ! ./boot/check.sh; then
    echo "BF-M4 FAIL: run ${i}/3 failed"
    exit 1
  fi
  echo "=== BF-M4 run ${i}/3 PASSED ==="
done

echo "BF-M4 PASS: 3/3 consecutive runs succeeded"
```

`set -e`를 쓰지 않는 이유: `set -e`가 있으면 `boot/check.sh`가 실패했을 때
스크립트가 바로 죽어버려 "몇 번째 회차에서 실패했는지"를 우리가 직접 찍을
기회가 없다(bash가 함수 호출 안에서 `if`의 조건으로 쓰인 명령에는 어차피
`set -e`를 적용하지 않지만, 의도를 명확히 하기 위해 애초에 빼둔다). `clean()`은
gitignore 대상 디렉터리만 지운다 — `kernel/build/`, `init/target/`, `out/`는
모두 `.gitignore`에 등록돼 있어(Task 2 확인) 삭제해도 git 추적 파일을 잃지
않는다. `kernel/src/`(kernel 소스)와 `boot/limine-binary/`(Limine binary
release)는 다운로드 캐시이므로 그대로 둔다.

- [x] **Step 2: 실행 권한 부여**

```bash
chmod +x check.sh
```

- [x] **Step 3: `.gitignore` 대상 재확인**

Run:
```bash
git check-ignore -v kernel/build init/target out
```

Expected: 세 경로 모두 `.gitignore`의 어느 줄에 걸리는지 출력된다(예:
`.gitignore:6:kernel/build\tkernel/build`). 하나라도 출력이 없으면(즉
git-ignore 대상이 아니면) `clean()`이 추적 파일을 지울 위험이 있으므로 Step 1로
돌아가 대상 목록을 다시 확인한다.

- [x] **Step 4: 실행해서 3회 연속 PASS 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh
```

Expected: `=== BF-M4 run 1/3 ===`부터 `=== BF-M4 run 3/3 PASSED ===`까지 세
번 모두 `boot/check.sh`의 mount 로그 + fish 배너(`Welcome to fish, the
friendly interactive shell`) + `PASS`가 출력되고, 마지막 줄에 `BF-M4 PASS:
3/3 consecutive runs succeeded`가 나온다. 종료 코드 0. `kernel/build/`를
매번 지우므로 각 회차마다 kernel 전체 재컴파일이 일어나 실행 시간이
`boot/check.sh` 단독 실행보다 3배 이상 걸릴 수 있다 — 정상이다.

**만약 특정 회차에서 FAIL이 나면:** `BF-M4 FAIL: run N/3 failed`로 몇 번째
회차인지 먼저 확인한다. 1회차부터 실패하면 `boot/check.sh` 자체의 문제(BF-M3
때와 동일한 원인일 가능성 — BF-M3 design doc의 troubleshooting 절 참고)이고,
2~3회차에서만 실패하면 **clean 상태에서만 재현되는 문제**(예: 캐시된
산출물에 의존해 이전엔 우연히 통과했던 경우)이므로 실패한 회차 직전의 로그를
`kernel/build.sh`, `init`(cargo), `kernel/make_initrd.sh`, `boot/make_iso.sh`
단계별로 나눠 어느 단계에서 clean 빌드가 실패하는지 좁혀간다.

- [x] **Step 5: `git status`로 초기화 재현성 확인**

Run:
```bash
git status
```

Expected: `kernel/initrd.cpio`가 수정된 것으로 나타날 수 있다(빌드
산출물이지만 관례상 git에 커밋돼 있음 — BF-M3 때도 `fe4ac19` 커밋으로 동일하게
갱신한 전례가 있다). 그 외 추적 파일에 의도치 않은 변경이 없는지 확인한다.

- [x] **Step 6: 커밋**

`kernel/initrd.cpio`가 변경되지 않았다면:
```bash
git add check.sh
git commit -m "Add BF-M4 check.sh for 3x consecutive boot verification"
```

`kernel/initrd.cpio`도 변경됐다면 두 커밋으로 나눈다:
```bash
git add check.sh
git commit -m "Add BF-M4 check.sh for 3x consecutive boot verification"
git add kernel/initrd.cpio
git commit -m "Refresh initrd.cpio from BF-M4 check.sh run"
```

---

## BF-M4 완료 확인

Task 1의 Step 4가 `BF-M4 PASS: 3/3 consecutive runs succeeded`로 끝나면
design doc(`2026-08-01-tars-boot-foundation-design.md`) 기준 BF-M4 exit
gate(스크립트 3회 연속 실행 성공)를 만족하고, Boot Foundation
서브프로젝트(BF-M0~M4) 전체가 완료된다. 이 시점에 전체 design doc의
**Status**를 `Approved (design phase), plan not yet written`에서
`Completed`로 갱신하고, HANDOFF.md를 다음 서브프로젝트 착수 전 상태로
정리한다.
