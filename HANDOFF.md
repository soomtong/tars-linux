# HANDOFF: Display Foundation — DF-M0~M2 완료(MVP 달성), DF-M3 plan 작성 전

## 목표

Boot Foundation(BF-M0~M4, 2026-08-07 완료) 이후 두 번째 서브프로젝트인
**Display Foundation**을 진행 중이다. 범위는 KMS/DRM으로 화면에 픽셀을
띄우는 것까지(실제 compositor는 이후 별도 서브프로젝트). 4단계 milestone
(DF-M0~M3) 중 이번 세션에서 **DF-M0, DF-M1, DF-M2를 전부 완료**해 design
doc이 정의한 MVP("QEMU 가상 GPU에 DRM/KMS로 모드를 설정하고 framebuffer에
단색을 채워 화면에 나타나는 것을 자동화된 스크립트로 검증")를 달성했다.
**DF-M3(종료 게이트 — 3회 연속 실행 검증) plan은 아직 작성 전이다.**

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행은 **사용자가 직접** → 결과를 사용자가 전달하면 Claude가 상세
해석. Claude는 design/plan 문서·`HANDOFF.md` 작성과 **승인된** 내용의
git commit만 대신 수행한다(`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고). 이번 세션에서 사용자가 두 커밋
(`2df5148`, `2d6e2ce`)을 직접 만든 적이 있었다 — 문제는 없었지만 원칙은
그대로 유지(Claude가 커밋)하기로 함. 실행 방식을 milestone마다 다시 묻지
말 것 — 고정됨. 새 milestone 착수 전 "design doc이 필요한가"는
brainstorming 스킬로 짧게 확인하되, 새 아키텍처 결정이 없다고 판단되면
생략하고 바로 writing-plans로 넘어가도 된다(BF-M4, DF-M1, DF-M2 선례).

## 현재 브랜치

`main` — 로컬이 origin/main보다 23커밋 앞서 있음(push는 사용자 판단,
이번 세션에서 요청받지 않음). Working tree 완전히 깨끗함(커밋 안 된 변경
없음). 최신 커밋 `40aade5`.

## 완료된 작업

- [x] DF-M0(검증 파이프라인 sanity check) 완료·커밋 — `display/check.sh`
      작성(QEMU virtio-gpu-pci + monitor screendump + ImageMagick으로
      해상도 확인). devcontainer에 `imagemagick` 추가.
- [x] DF-M1(PCI + DRM/virtio-gpu 드라이버 활성화) 완료·커밋 —
      `kernel/.config`에서 `CONFIG_PCI`, `CONFIG_DRM`,
      `CONFIG_DRM_VIRTIO_GPU`, `CONFIG_VIRTIO_PCI`, `CONFIG_VIRTIO_MENU`
      활성화. `init`에 `/dev/dri/card0` 존재 확인 로그 추가.
      `kernel/check-virtio-gpu.sh`로 드라이버 probe 검증.
- [x] DF-M2(픽셀 그리기, MVP 종료점) 완료·커밋 — 새 Rust 바이너리
      `kms/`가 raw DRM ioctl(`libc::ioctl` 직접 호출, crate 래퍼 없음)로
      리소스 조회 → dumb buffer 생성 → mmap → 단색(빨강) 채우기 →
      framebuffer 등록(`ADDFB`) → `SETCRTC`까지 수행. `init`이
      `fork`+`execve`로 `kms`를 실행하도록 통합. `display/check.sh`에
      좌표 (10,10) 픽셀 색 검사(`#FF0000`) 추가해 공식 exit gate 자동
      검증 — **최종 PASS 확인함**(`Pixel at (10,10): ... #FF0000 red`,
      `PASS`).
- [x] `docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md`
      의 Status 줄을 `DF-M2 complete (2026-08-07); DF-M3 plan not yet
      written`으로 갱신·커밋.

## 시도했으나 실패한 접근 / 중요한 정정

DF-M2 구현 중 실제로 부팅해보며 네 가지 버그를 순서대로 발견·수정했다
(전부 `docs/superpowers/plans/2026-08-07-tars-display-foundation-df-m2.md`
에 "정정" 노트로 기록돼 있음 — 다음에 비슷한 raw ioctl 코드를 작성할 때
반드시 참고할 것):

1. **devtmpfs mount 누락**: `kms`를 임시 `/init`으로 테스트할 때
   `/dev/dri/card0` open이 `ENOENT`로 실패 — `tars-init`과 달리
   devtmpfs를 mount하는 코드가 없었다. `kms`에
   `ensure_devtmpfs_mounted()`(방어적, 실패 무시)를 추가해 해결.
2. **GETCONNECTOR 2단계 조회에서 EFAULT**: 포인터 필드만 0으로 되돌리고
   대응하는 `count_*` 필드는 그대로 둬서, 커널이 null 포인터에 복사를
   시도해 `EFAULT`(errno 14) 발생. 포인터를 비울 땐 count도 함께 0으로
   만들어야 함(`kms/src/main.rs`의 `find_connected_connector` 참고).
3. **encoder_id=0으로 인한 ENOENT**: 갓 부팅한 커널에서
   `connector.encoder_id`가 0(아직 아무 encoder도 안 붙음)일 수 있음 —
   `GETCONNECTOR`가 돌려주는 encoder 목록의 첫 번째 값으로 폴백하도록
   수정.
4. **(가장 중요) fd를 닫으면 DRM이 framebuffer를 자동 회수**: `kms`가
   정상 종료하면 커널이 `/dev/dri/card0` fd를 닫는데, virtio-gpu는
   `DRIVER_ATOMIC`이라 DRM 코어가 "이 fd가 소유한 framebuffer는 fd가
   닫히면 무조건 회수한다"는 ABI 규칙(`drm_fb_release()` →
   `drm_framebuffer_remove()` → `atomic_remove_fb()`)을 실제로
   실행해서, 화면이 검게 지워졌다. 커널 소스(`drm_file.c`,
   `drm_framebuffer.c`, `virtgpu_drv.c`)를 직접 읽어 확인함. 수정:
   `kms`는 `SETCRTC` 성공 후 `Ok(())`로 반환하지 않고
   `loop { libc::pause() }`로 fd를 영원히 붙잡는다. `tars-init`의
   `run_kms()`는 더 이상 `waitpid`로 기다리지 않고 `fork` 직후 바로
   콘솔 설정 → fish exec으로 넘어간다.
5. **타이밍 플레이키니스**: 위 수정 후에도 `display/check.sh`가 간헐적
   으로 `640x480`(모드 설정 전 기본값)을 보고하며 실패한 적이 있었다 —
   PCI+DRM+kms ioctl 시퀀스가 추가되며 부팅이 DF-M0 때보다 길어졌는데
   screendump 전 `sleep 3`이 그대로였던 게 원인으로 보임.
   `sleep 5`로 늘려서 안정화(같은 문제가 다시 보이면 더 늘려볼 것).

## 남은 작업

- [ ] **DF-M3(종료 게이트) plan을 다음 세션에서 새로 작성.** design doc
      기준 DF-M3의 결과는 "DF-M0~M2 전체를 재현 가능한 단일 스크립트로
      묶고, 반복 실행해도 매번 동일하게 픽셀 검증을 통과", exit gate는
      "스크립트 3회 연속 실행 성공"(BF-M4와 동일한 패턴 — 저장소 루트
      `check.sh`가 `boot/check.sh`를 3번 `clean`+재실행하는 방식 참고).
      DF-M2가 타이밍에 살짝 민감했던 이력이 있으니(위 5번 정정), 3회
      연속 실행 검증이 실제로 이 문제를 잡아낼 좋은 기회다.
- [ ] (선택) 로컬 23커밋을 origin/main에 push할지 사용자에게 확인.
- [ ] DF-M3 완료 후 Display Foundation 전체가 끝나면, 다음 서브프로젝트
      (compositor 등, `2026-08-01-tars-boot-foundation-design.md`의
      "배경" 절 최종 비전 후보 목록 참고) 착수 여부를 사용자와 논의.

## 핵심 파일

- `docs/superpowers/specs/2026-08-07-tars-display-foundation-design.md` —
  Display Foundation 전체 design doc(Status: DF-M2 complete). DF-M3의
  결과/exit gate 정의가 여기 있음.
- `docs/superpowers/plans/2026-08-07-tars-display-foundation-df-m2.md` —
  DF-M2 plan, 위에서 언급한 4개 버그의 "정정" 노트가 전부 기록돼 있음.
  다음에 raw DRM ioctl 코드를 다룰 때 반드시 참고.
- `kms/src/main.rs` — DRM ioctl 직접 호출 코드 전체(struct 레이아웃,
  ioctl 번호 계산 `drm_iowr()`, 리소스 선택 로직, dumb buffer/mmap,
  `SETCRTC` 이후 `loop { pause() }`로 fd 유지).
- `init/src/main.rs:42-59` — `run_kms()`, `fork`만 하고 `waitpid` 안
  함(정정 4번 참고).
- `display/check.sh` — DF-M0~M2 공용 screendump 검증 파이프라인.
  `sleep 5`(정정 5번), 좌표 (10,10) 픽셀 색 grep이 exit gate.
- `kernel/check-virtio-gpu.sh` — DF-M1의 드라이버 probe 검증(fish 배너
  대신 `/dev/dri/card0 exists` grep). `kernel/check.sh`(Boot Foundation
  때부터 있던 기본 스크립트)는 virtio-gpu-pci 장치를 안 붙이므로 DRM
  관련 검증에는 쓰면 안 됨 — 이번 세션에서 실수로 썼다가 혼란을 겪었음.
- `~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
  feedback_execution_scope.md`, `feedback_commit_delegation.md` —
  협업 원칙(변경 없음).

## 다음 에이전트에게

1. `git log --oneline -10` && `git status`로 이 파일과 실제 상태가
   일치하는지 먼저 확인 — 최신 커밋 `40aade5`, working tree 깨끗해야
   한다.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것.
3. 사용자에게 DF-M3 plan을 지금 작성할지 물어볼 것 — design doc의
   DF-M3 절은 이미 정의돼 있으므로 brainstorming 없이 바로
   writing-plans로 진행 가능(BF-M4/DF-M1/DF-M2 선례).
4. DF-M3 plan에는 저장소 루트에 새 `check.sh`(또는 기존 루트
   `check.sh`를 Display Foundation까지 포함하도록 확장)를 만들어
   `display/check.sh`를 3회 연속 clean-rebuild+실행하는 내용이 들어갈
   것으로 예상된다 — 정확한 설계는 design doc과 BF-M4 선례를 참고해
   그 시점에 정한다(전체 미리 설계 안 함, CLAUDE.md 원칙).
5. 실행 방식(pairing)과 design doc 필요 여부 판단 기준을 다시 묻지
   말 것 — 이미 여러 서브프로젝트에 걸쳐 확정됨.
