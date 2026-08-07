# HANDOFF: Display Foundation 착수 — DF-M0 plan 작성 완료, 사용자 검토 전

## 목표

Boot Foundation(BF-M0~M4)이 2026-08-07에 완료되어(kernel + Limine +
Rust init + hybrid ISO로 QEMU shell prompt 부팅), 다음 서브프로젝트로
**Display Foundation**을 시작했다. 범위는 최종 비전의 "compositor/KMS"
후보 중 실제 compositor(창 합성, 입력 라우팅)는 제외하고 **KMS/DRM으로
화면에 픽셀을 띄우는 것까지**로 좁혔다(사용자가 이 도메인에 익숙하지
않아 Claude가 설계를 제안하고 사용자가 승인하는 방식으로 진행). 4단계
milestone(DF-M0~M3)으로 나눴고, 이번 세션에서 design doc과 첫 milestone
DF-M0의 plan을 작성했다. **DF-M0 구현은 아직 시작하지 않았다.**

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행(빌드, 조사용 명령 포함)은 **사용자가 직접** → 결과를 사용자가
전달하면 Claude가 상세 해석. Claude는 design/plan 문서·`HANDOFF.md`
작성과 **승인된** 내용의 git commit만 대신 수행한다 (`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고). 실행 방식(pairing)을 milestone마다
다시 묻지 말 것 — 고정됨. 새 milestone/서브프로젝트 착수 전 "design doc이
필요한가"는 brainstorming 스킬로 짧게 확인하되, 새 아키텍처 결정이 없다고
판단되면 생략하고 바로 writing-plans로 넘어가도 된다(BF-M4 선례).

## 현재 브랜치

`main` — 로컬이 origin/main보다 3커밋 앞서 있음(push는 사용자 판단,
이번 세션에서 요청받지 않음). 최신 **커밋**은 `b6c9a29`. **작업 트리에
커밋되지 않은 새 파일이 하나 있다** — 아래 "남은 작업" 참고.

## 완료된 작업

- [x] Boot Foundation(BF-M0~M4) 전체 완료(이전 handoff에서 기록됨,
      design doc Status `Completed`로 갱신됨)
- [x] Display Foundation design doc 작성 및 커밋(`bc4fd44`):
      `docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md`
      — 범위(KMS/DRM 픽셀 그리기까지), 핵심 설계 결정 3가지(virtio-gpu,
      QEMU screendump+ImageMagick 검증, 별도 raw-ioctl 바이너리), DF-M0~M3
      milestone 목록 포함. 사용자 승인 받음("I like your design document").
- [x] `CLAUDE.md`의 "## 참고" 절을 Boot Foundation 전용에서 완료/진행 중
      서브프로젝트 목록으로 갱신, 커밋(`b6c9a29`) — 사용자가 먼저
      "CLAUDE.md도 갱신해야 하지 않냐"고 지적해서 진행함.
- [x] DF-M0 plan 작성(**아직 커밋 안 됨**, 아래 참고):
      `docs/superpowers/plans/2026-08-07-tars-display-foundation-df-m0.md`

## 시도했으나 실패한 접근 / 중요한 정정

이번 세션에서 재시도/정정 없음. 참고로 kernel `.config`를 확인해보니
`CONFIG_PCI is not set`이었다(2026-08-07 확인) — Boot Foundation은
initramfs만으로 부팅해 PCI가 전혀 필요 없었는데, virtio-gpu는 PCI 장치라
DF-M1에서 PCI 버스 지원부터 새로 켜야 한다는 걸 design doc에 명시해뒀다.

## 남은 작업

- [ ] **DF-M0 plan을 사용자가 검토하고 승인할 것.** 사용자가 plan
      내용에 피드백을 주기 전에 "rebuild handoff"로 넘어와서, plan
      파일은 아직 git에 커밋되지 않은 상태다(`git status`에 untracked로
      나옴). 다음 세션 시작 시 가장 먼저 할 일: 사용자에게 plan 검토
      결과를 묻고, 승인되면 Claude가 커밋한 뒤 Task 1 Step 1(devcontainer
      Dockerfile에 `imagemagick` 추가)부터 pairing으로 진행.
- [ ] DF-M0 Task 1~2 구현(plan 파일 참고) — devcontainer에 `imagemagick`
      추가 → `display/check.sh`(QEMU virtio-gpu-pci + `/dev/tcp` monitor
      + screendump + ImageMagick 파이프라인 검증) 작성 및 실행 확인.
- [ ] DF-M0 완료 후 DF-M1(PCI + DRM/virtio-gpu 드라이버 활성화) plan을
      그 시점에 새로 작성(전체 미리 설계 안 함 — CLAUDE.md 원칙).
- [ ] (선택) 로컬 3커밋을 origin/main에 push할지 사용자에게 확인.

## 핵심 파일

- `docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md` —
  Display Foundation 전체 design doc. DF-M0~M3 milestone 정의, 핵심 설계
  결정(virtio-gpu, screendump 검증, raw ioctl) 전부 여기 있음.
- `docs/superpowers/plans/2026-08-07-tars-display-foundation-df-m0.md` —
  **아직 미커밋.** Task 1(devcontainer imagemagick), Task 2
  (`display/check.sh` 작성+검증+커밋)로 구성. Step 내용이 실행 가능한
  수준으로 이미 작성 완료돼 있음 — 사용자 승인만 받으면 바로 시작 가능.
- `docs/superpowers/specs/2026-08-01-tars-boot-foundation-design.md` —
  Boot Foundation 전체 design doc(Status: Completed), 최종 비전 후보
  목록이 배경 절에 있음.
- `CLAUDE.md`의 "## 참고" 절 — 서브프로젝트별 design doc 위치를 최신
  상태로 유지해야 함(새 서브프로젝트 시작/완료 시 갱신 필요).
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`, `feedback_commit_delegation.md` —
  협업 원칙(변경 없음).

## 다음 에이전트에게

1. `git log --oneline -10` && `git status`로 이 파일과 실제 상태가
   일치하는지 먼저 확인 — 최신 커밋 `b6c9a29`, `docs/superpowers/plans/
   2026-08-07-tars-display-foundation-df-m0.md`가 untracked로 남아있어야
   한다.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것.
3. 사용자에게 DF-M0 plan(`docs/superpowers/plans/
   2026-08-07-tars-display-foundation-df-m0.md`) 검토 결과부터 물어볼
   것 — 승인되면 커밋(`git add` 대상은 그 파일 하나만) 후 Task 1부터
   pairing으로 시작.
4. 실행 방식(pairing)과 design doc 필요 여부 판단 기준을 다시 묻지
   말 것 — 이미 여러 서브프로젝트에 걸쳐 확정됨.
