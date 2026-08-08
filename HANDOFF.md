# HANDOFF: TF-M1 plan 작성 완료, Task 1 Step 1부터 실행 대기

## 목표

Terminal Foundation 세 번째 서브프로젝트의 두 번째 milestone **TF-M1(프레임버퍼
텍스트 렌더링)**을 진행 중이다. TF-M0(검증 파이프라인 확장, 2026-08-08
완료)에서 확보한 `libghostty-vt`, `8x4x4-fonts`, `stb_truetype`을 조합해,
Terminal Foundation 앱(Zig)이 KMS/DRM 프레임버퍼에 실제로 읽을 수 있는
텍스트("TARS 하이" — ASCII + 한글 음절)를 렌더링하고 QEMU screendump로
자동 검증하는 것이 목표다. `libghostty-vt`(ANSI 파싱)는 아직 쓰지 않는다 —
PTY가 들어오는 TF-M2부터 필요하다.

이번 세션에서는 **brainstorming → writing-plans** 스킬로 TF-M1의 설계
결정을 확정하고 상세 실행 plan을 작성·커밋했다. 아직 실제 구현(Task 1~4)은
시작하지 않았다.

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행은 **사용자가 직접** → 결과를 사용자가 전달하면 Claude가 상세
해석. Claude는 design/plan 문서·`HANDOFF.md` 작성과 **승인된** 내용의
git commit만 대신 수행한다(`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고).

## 현재 브랜치

`main` — origin/main보다 2개 커밋 앞서 있음(`9e45aed`, `70b2ca4`, 아직
push 안 함). Working tree 깨끗함. 최신 커밋 `70b2ca4`.

## 완료된 작업

- [x] **TF-M0 전체(Task 1~5)** — 이전 세션에서 완료·커밋·push까지 끝남
      (커밋 `387353b`~`9727a3e`, 자세한 내용은 git log 참고).
- [x] **TF-M1 브레인스토밍** — `superpowers:brainstorming` 스킬로 다음
      핵심 결정을 확정:
  - **KMS 접근 방식**: `kms` crate(Rust)를 FFI로 링크하지 않고, Zig로
    raw DRM ioctl을 새로 포팅한다. `terminal/src/drm.zig`가
    `kms/src/main.rs`의 1:1 이식이 된다. `kms` crate 자체는 Display
    Foundation 산출물로 저장소에 남지만 boot chain에서는 빠진다(`init`이
    `/kms` 대신 `/terminal`을 exec).
  - **고정 문자열**: ASCII + 한글 음절 하나(`"TARS 하이"`). 확인 결과
    `Hanme_8x4x4.ttf`는 완성형 한글 음절 11,172자를 표준 유니코드
    코드포인트로 직접 매핑하고 있어(cmap에 U+D558 "하" 존재 확인),
    초성/중성/종성을 앱이 직접 조합할 필요가 없다 — ASCII와 동일하게
    코드포인트 하나당 `stbtt_GetCodepointBitmap` 한 번이면 된다.
  - **glyph cache 범위**: 테스트 문자열에 등장하는 코드포인트만
    래스터라이징(전체 ASCII+한글 타일 세트는 범위 밖).
  - **검증 방법**: screendump에서 (a) 배경색 단일 픽셀 검사 +
    (b) 글리프가 그려질 좌표 영역을 crop해 ImageMagick unique color
    개수(`-format "%k"`)로 "뭔가 그려졌다"만 자동 확인. 정확한 글자
    모양까지는 육안 확인으로 남겨둠.
  - mmap/ioctl 동작 원리(프레임버퍼를 프로세스 주소공간에 매핑하는
    이유, `MAP_SHARED`, `volatile` 쓰기, `pitch` vs `width`)를 사용자
    학습 목적으로 상세 설명함(이 대화 히스토리 참고, 별도 문서화는
    안 함).
  - 이 프로젝트 관례(서브프로젝트당 design doc 하나, milestone별로는
    바로 plan)에 따라 TF-M1은 별도 spec 문서 없이 기존
    `2026-08-08-tars-terminal-foundation-design.md`를 기준으로 바로
    plan을 작성했다.
- [x] **TF-M1 plan 작성 + 커밋** —
      `docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m1.md`
      (커밋 `9e45aed`, Task 1~4, 전부 코드 포함해서 상세 작성, 자체 검토
      완료). 아직 실행은 시작 안 함(체크박스 전부 미완료).
- [x] **`docs/study/note.md`에 KMS 개념 정리 커밋** (커밋 `70b2ca4`,
      사용자가 직접 작성한 학습 노트).

## 시도했으나 실패한 접근

없음 — 이번 세션은 설계/계획 단계만 진행했고 아직 코드를 실행하지 않았다.

## 남은 작업

- [ ] **TF-M1 plan Task 1**부터 pairing 방식으로 실행 시작. Task 1은
      `terminal/src/main.zig` 최소 스캐폴드 작성 + `.gitignore`에
      `terminal/zig-out/`, `terminal/.zig-cache/` 추가 + `zig build-exe`
      컴파일/실행 확인.
- [ ] Task 2: `terminal/src/drm.zig`(DRM/KMS Zig 포팅) + `main.zig` 배경
      채우기 + `init/src/main.rs`(`/kms`→`/terminal`) + `kernel/
      make_initrd.sh` 수정 + `terminal/check.sh` 작성 + QEMU 배경색
      검증.
- [ ] Task 3: `terminal/src/font.zig`(stb_truetype 기반 glyph cache) +
      `terminal/src/font_test.zig`(네이티브 테스트, QEMU 불필요) + 호스트
      실행 검증.
- [ ] Task 4: `main.zig`에 렌더러 통합(glyph cache → 프레임버퍼 blit) +
      `terminal/check.sh`에 글리프 영역 unique-color 검사 추가 + 전체
      QEMU 파이프라인 검증 + screendump 육안 확인.
- [ ] TF-M1 완료 후 TF-M2(PTY + `libghostty-vt` 연동) plan을 새로
      브레인스토밍부터 작성.
- [ ] (선택) origin/main에 현재 2개 커밋(`9e45aed`, `70b2ca4`) push —
      사용자에게 먼저 확인 후 진행.

## 핵심 파일

- `docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m1.md` —
  TF-M1 전체 실행 plan(Task 1~4, 완전한 Zig 코드 포함). 다음 세션은 이
  파일의 Task 1 Step 1부터 그대로 진행하면 된다.
- `docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md` —
  Terminal Foundation design doc. milestone 초안(TF-M0~M4) 및 핵심 설계
  결정 6개.
- `kms/src/main.rs` — TF-M1 Task 2에서 Zig로 포팅할 원본 Rust raw DRM
  ioctl 구현(이미 DF-M0에서 검증됨). `terminal/src/drm.zig` 작성 시
  구조체 필드 순서/타입을 여기와 1:1로 맞춰야 한다.
- `display/check.sh` — `terminal/check.sh`가 그대로 참고하는 QEMU
  screendump 검증 스크립트 패턴(monitor 포트, screendump, ImageMagick
  pixel 검사).
- `init/src/main.rs`, `kernel/make_initrd.sh` — TF-M1 Task 2에서 `/kms`
  대신 `/terminal`을 boot chain에 넣도록 수정 대상.
- `terminal/vendor/fonts/Hanme_8x4x4.ttf`, `terminal/vendor/
  stb_truetype.h` — TF-M0에서 이미 벤더링됨(gitignore 대상, 새 세션에서
  `terminal/vendor_fonts.sh`, `terminal/vendor_stb_truetype.sh` 재실행
  필요할 수 있음).

## 다음 에이전트에게

1. `git log --oneline -6` && `git status`로 이 파일과 실제 상태가
   일치하는지 먼저 확인 — 최신 커밋 `70b2ca4`, origin/main보다 2개
   커밋 앞섬(미push), working tree 깨끗해야 한다.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것(경로: `~/.claude/projects/
   -Users-dp-Repository-tars-linux/memory/`).
3. `docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m1.md`의
   **Task 1 Step 1**부터 그대로 안내 시작 — 이미 완전한 plan이 작성되어
   있으므로 새로 브레인스토밍하지 않는다.
4. 실행 단계에서는 각 Step 실행 결과(로그, 에러)를 사용자가 붙여주면
   Claude가 해석하고 다음 Step으로 안내한다. Claude가 직접 build/docker
   run/QEMU 명령을 실행하지 않는다(웹 리서치·`git`/`find`/`Read` 같은
   읽기 전용 확인은 허용). **매 Step 완료 후 파일 내용을 `Read`로 직접
   검증** — TF-M0에서 사용자가 두 파일 내용을 합쳐서 저장한 실수를 이
   방식으로 잡아낸 적이 있다.
5. `terminal/src/drm.zig`는 사람이 손으로 옮겨 적은 Zig 코드라 컴파일
   에러(타입 캐스트, `@cImport` 관련 등)가 날 가능성이 plan 문서 자체에
   이미 troubleshooting 노트로 언급돼 있다 — 에러가 나면 당황하지 말고
   plan의 "만약 ~ 에러가 나면" 안내를 먼저 참고하고, 없으면 정상적인
   디버깅 루프(에러 메시지 → 원인 설명 → 수정)로 처리한다.
6. 실행 방식(pairing)과 design doc 필요 여부 판단 기준을 다시 묻지
   말 것 — 이미 여러 서브프로젝트에 걸쳐 확정됨.
