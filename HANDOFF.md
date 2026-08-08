# HANDOFF: TF-M0 완료, TF-M1 plan 작성 대기

## 목표

Terminal Foundation 세 번째 서브프로젝트의 첫 milestone **TF-M0(검증
파이프라인 확장)**을 이번 세션에서 Task 1~5 전부 실행·검증·커밋했다.
목표는 devcontainer에 Zig 툴체인을 추가하고, `libghostty-vt`(ANSI/VT
파싱 코어), `8x4x4-fonts`(한글 조합형 지원 비트맵 폰트),
`stb_truetype`(TTF 래스터라이저) 세 가지를 각각 가져와 빌드/링크/FFI가
실제로 동작함을 sanity check 프로그램으로 확인하는 것이었다 — **모두
성공**.

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행은 **사용자가 직접** → 결과를 사용자가 전달하면 Claude가 상세
해석. Claude는 design/plan 문서·`HANDOFF.md` 작성과 **승인된** 내용의
git commit만 대신 수행한다(`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고).

## 현재 브랜치

`main` — origin/main과 완전히 동기화됨(이번 세션에서 5개 커밋 push
완료). Working tree 깨끗함. 최신 커밋 `9727a3e`.

## 완료된 작업 (TF-M0 전체, Task 1~5)

- [x] **Task 1** — devcontainer에 Zig 0.16.0 + `xz-utils`/`unzip` 추가
      (커밋 `387353b`). `docker run ... zig version` → `0.16.0` 확인.
- [x] **Task 2** — `terminal/vendor_libghostty_vt.sh` 작성, ghostty-org
      /ghostty 커밋 `2602886144c7e95099c9e2ba07f181c69e7276f3`을
      `-Demit-lib-vt`로 빌드(커밋 `0889db3`). `terminal/vendor/
      libghostty-vt/{include/ghostty/vt.h, lib/libghostty-vt.a,.so*}`
      생성 확인.
- [x] **Task 3** — `libghostty_vt_main.c` sanity check(OSC 0 "change
      window title" 시퀀스 파싱, 커밋 `bd0f3af`). 실행 결과
      `Extracted title: hello` 정확히 확인.
- [x] **Task 4** — `terminal/vendor_fonts.sh`로 `8x4x4-fonts` v0.0.7
      릴리스에서 `Hanme_8x4x4.ttf`만 추출(커밋 `49dfc7d`). devcontainer에
      `file` 명령이 없어서(`debian:trixie-slim` 최소 설치) `od -An -tx1
      -N4`로 매직 넘버 `00 01 00 00`(TrueType) 확인, 크기 451512
      bytes(~441KB) 확인 — plan의 `file` 검증을 대체.
- [x] **Task 5** — `stb_truetype_main.c` sanity check(글리프 'A' 실제
      래스터라이징, 커밋 `9727a3e`). 실행 결과 `glyph 'A': 7x10 pixels,
      39 non-zero` 확인.
- [x] **origin/main push** — 5개 커밋(`387353b`~`9727a3e`) 전부 push
      완료.

## 시도했으나 실패한 접근

- **Task 5 Step 1/2 파일 분리 실수**: 사용자가 `terminal/
  vendor_stb_truetype.sh` 파일 안에 Step 1(쉘 스크립트)과 Step 2(C
  sanity check 프로그램) 내용을 이어 붙여서 저장 → `line 16: Step:
  command not found` 에러. 원인은 안내 문구("Step 2: ... 새로 작성")가
  파일 안에 그대로 붙여넣기 된 것. Claude가 `Read`로 실제 파일 내용을
  확인해서 발견, 두 파일(`vendor_stb_truetype.sh` 14줄 + `sanity/
  stb_truetype_main.c` 별도 파일)로 다시 분리하도록 안내해서 해결. **교훈:**
  매 Step 실행 후 Claude가 `Read`로 실제 파일 내용을 검증하는 습관이
  이번에도 문제를 잡아냄 — 계속 유지할 것.
- **Task 4 Step 4 `file` 명령 부재**: devcontainer 이미지에 `file`
  패키지가 없음(`command not found`). 이미지 재빌드 대신 `od`로 매직
  넘버를 직접 확인하는 대체 검증으로 처리 — plan을 수정하지 않고
  그때그때 대체 명령을 제시했다. TF-M1 이후 `file`이 자주 필요하면
  Dockerfile에 추가 고려.

## 남은 작업

- [ ] **TF-M1(프레임버퍼 텍스트 렌더링) plan 작성.** design doc
      (`docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md`)의
      milestone 초안(TF-M0~M4)에 따라, TF-M0에서 검증한 세 가지
      (`libghostty-vt`, `8x4x4-fonts`+`stb_truetype`)를 조합해 실제 KMS
      프레임버퍼에 텍스트를 그리는 milestone. brainstorming →
      writing-plans 스킬로 새로 시작한다(TF-M0 plan처럼 pairing 방식
      override 문구를 plan 상단에 명시).
- [ ] TF-M1 plan 작성 후 Task 1 Step 1부터 pairing 방식으로 실행.

## 핵심 파일

- `docs/superpowers/specs/2026-08-08-tars-terminal-foundation-design.md` —
  Terminal Foundation design doc(배경, MVP 목표/비목표, 핵심 설계 결정
  6개, milestone 초안 TF-M0~M4). TF-M1 plan 작성 시 이 문서의 milestone
  초안을 기준으로 삼는다.
- `docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m0.md` —
  TF-M0 plan, Task 1~5 전부 완료·체크됨(체크박스 자체는 갱신 안 했지만
  실제로는 전부 완료).
- `terminal/vendor_libghostty_vt.sh`, `terminal/vendor_fonts.sh`,
  `terminal/vendor_stb_truetype.sh` — 외부 소스 벤더링 스크립트 3개,
  각각 버전/커밋 SHA 고정. `terminal/ghostty-src/`, `terminal/vendor/`는
  `.gitignore`에 등록되어 커밋되지 않음 — 새 세션에서는 다시
  다운로드/빌드해야 한다(스크립트가 이미 있으면 재실행만 하면 됨).
- `terminal/sanity/{libghostty_vt,stb_truetype}_main.c` — 두 sanity
  check 프로그램, 둘 다 통과 확인됨. TF-M1에서 실제 렌더링 코드 작성 시
  참고 예제로 재사용 가능.

## 다음 에이전트에게

1. `git log --oneline -8` && `git status`로 이 파일과 실제 상태가
   일치하는지 먼저 확인 — 최신 커밋 `9727a3e`, origin/main과 동기화됨,
   working tree 깨끗해야 한다.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것(경로: `~/.claude/projects/
   -Users-dp-Repository-tars-linux/memory/`).
3. `superpowers:brainstorming` → `superpowers:writing-plans` 스킬로
   TF-M1 plan을 새로 작성하는 것부터 시작한다. design doc의 TF-M1
   milestone 초안(프레임버퍼 텍스트 렌더링)을 기준으로 하되, 이해가
   쌓이면서 구체적 결정이 달라질 수 있으므로 TF-M0 plan을 그대로
   베끼지 말고 다시 브레인스토밍한다.
4. Plan 작성 후 실행 단계에서는 각 Step 실행 결과(로그, 에러)를
   사용자가 붙여주면 Claude가 해석하고 다음 Step으로 안내한다. Claude가
   직접 build/docker run/QEMU 명령을 실행하지 않는다(웹 리서치·`git`/
   `find`/`Read` 같은 읽기 전용 확인은 허용). **매 Step 완료 후 파일
   내용을 `Read`로 직접 검증** — 이번 세션에서 사용자가 두 파일 내용을
   합쳐서 저장한 실수를 이 방식으로 잡아냈다.
5. 실행 방식(pairing)과 design doc 필요 여부 판단 기준을 다시 묻지
   말 것 — 이미 여러 서브프로젝트에 걸쳐 확정됨.
