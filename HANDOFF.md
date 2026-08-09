# HANDOFF: TF-M1 완료(Task 1~4 전부 커밋됨), TF-M2 브레인스토밍 대기

## 목표

Terminal Foundation 세 번째 서브프로젝트의 두 번째 milestone **TF-M1(프레임버퍼
텍스트 렌더링)**을 이번 세션에서 **완료**했다. Terminal Foundation 앱(Zig)이
`/dev/dri/card0`를 직접 열어(raw DRM ioctl, `kms/src/main.rs`를 Zig로 포팅)
프레임버퍼를 얻고, `8x4x4-fonts` + `stb_truetype`으로 만든 glyph cache에서
고정 문자열 `"TARS 하이"`(ASCII + 한글 음절)를 blit해 화면에 그리는 것까지
QEMU screendump 자동 검증(`terminal/check.sh`)으로 확인했다.

**협업 방식(고정, 매 세션 반드시 지킬 것):** 설명 먼저 → 파일 작성과
명령 실행은 **사용자가 직접** → 결과를 사용자가 전달하면 Claude가 상세
해석. Claude는 design/plan 문서·`HANDOFF.md` 작성과 **승인된** 내용의
git commit만 대신 수행한다(`~/.claude/projects/
-Users-dp-Repository-tars-linux/memory/feedback_execution_scope.md`,
`feedback_commit_delegation.md` 참고).

## 현재 브랜치

`main` — origin/main보다 4개 커밋 앞서 있음(`cd899c0`, `673d32c`, `121bce4`,
`2d9460f`, 아직 push 안 함. push 여부는 사용자에게 먼저 확인 필요). Working
tree는 `kernel/initrd.cpio`(빌드 산출물, 이미 예전부터 git 추적 대상으로
잡혀 있던 파일 — 이번 세션에서 만든 문제 아님, 매 빌드마다 diff가 남는 게
정상)만 unstaged로 남아있고 나머지는 깨끗함. 최신 커밋 `2d9460f`.

## 완료된 작업

- [x] **TF-M1 Task 1(Zig 프로젝트 스캐폴드)** — 커밋 `cd899c0`.
- [x] **TF-M1 Task 2(DRM/KMS를 Zig로 포팅 + 배경색 채우기 + boot chain
      교체)** — 커밋 `673d32c`. `/kms` 대신 `/terminal`을 `init`이
      fork/exec하도록 바뀜.
- [x] **TF-M1 Task 3(stb_truetype FFI로 glyph cache 구축)** — 커밋
      `121bce4`.
- [x] **TF-M1 Task 4(렌더러 통합 + 전체 파이프라인 검증)** — 커밋
      `2d9460f`. `terminal/check.sh` 최종 결과: 배경색 `#102030` 정확,
      글리프 영역 unique color 2개(배경+글자) 확인, `PASS`.
- [ ] **screendump 육안 확인 미완료** — plan의 "TF-M1 완료 확인" 절이
      권장하는 마지막 단계(`"TARS 하이"`가 실제로 읽을 수 있는 모양인지
      눈으로 보기)를 아직 안 했다. `terminal/check.sh`가
      `docker run --rm`이라 컨테이너가 끝나면 `/tmp`의 screendump도
      같이 사라지므로, 다음에 `check.sh`를 돌릴 때 스크립트 끝에
      `cp "$SCREENSHOT" /workspace/tf-m1-screenshot.ppm` 같은 줄을
      임시로 추가해서 호스트로 빼낸 뒤 열어보는 걸 권장.

## Task 2~4에서 겪은 근본 원인들 (TF-M2에서 반드시 참고할 것 — 매우 중요)

이번 세션은 plan 문서의 코드를 그대로 옮겨 적는 것만으로는 전혀 동작하지
않았다. `superpowers:systematic-debugging`으로 8개의 서로 다른 근본 원인을
순서대로 찾아냈다. TF-M2도 같은 Zig 툴체인/환경을 쓰므로 아래 문제들이
그대로 다시 나타날 가능성이 높다 — 특히 1, 2, 6번은 `libghostty-vt` 연동
때 다시 마주칠 게 거의 확실하다.

1. **Zig 0.16.0(devcontainer에 설치된 버전)은 `std.fs` → `std.Io`로
   대규모 I/O API 이전("Writergate")이 진행 중이다.** `std.fs.File`이
   없어졌고(`std.Io.File`로 이동), `std.fs.openFileAbsolute`도 없다.
   새 패턴은 `std.Io.Dir.openFileAbsolute(io, path, opts)` /
   `std.Io.Dir.cwd().readFileAlloc(io, path, allocator, limit)`처럼
   **명시적 `io: std.Io` 컨텍스트**를 요구한다(allocator를 명시적으로
   넘기는 것과 같은 패턴). `std.time.sleep`도 마찬가지로
   `std.Io.sleep(io, duration, mode)`로 이동했다.
2. **`std.Io` 컨텍스트를 직접 만드는 건(`std.Io.Threaded` 스레드풀 초기화)
   과하다.** 우리처럼 fd 하나 얻어서 raw `ioctl`/`mmap`만 쓰는 저수준
   코드는 `std.fs`/`std.Io`를 아예 안 쓰고 `@cImport`로 POSIX
   `open()`/`sleep()`을 직접 부르는 게 훨씬 간단하다(`terminal/src/
   drm.zig`, `terminal/src/main.zig`가 이 패턴). 다만 **파일을 읽어야
   하는 경우**(`font_test.zig`, `main.zig`의 폰트 로드처럼)는
   `std.process.Init`이 `pub fn main(init: std.process.Init) !void`의
   매개변수로 넘겨주는 `init.io`를 쓰면 된다 — Zig 런타임이 이미
   준비해서 넘겨주므로 직접 초기화할 필요가 없다. `pub fn main()`은
   0-인자 형태(`void`/`!void`)도 여전히 동작하지만(`io`가 필요 없을
   때), 파일 I/O가 필요하면 `init: std.process.Init` 인자를 받아야
   한다.
3. **참고할 실제 동작 예시가 필요하면 `terminal/ghostty-src/`(TF-M0에서
   이미 vendor된 ghostty 전체 소스)를 grep하라.** 이번에 `std.Io.File`,
   `std.Io.Dir.openFileAbsolute`, `std.Io.sleep`, `init.io`,
   `std.process.Init` 사용 패턴을 전부 이걸로 찾았다. 최신 Zig std
   문서보다 이 vendor 소스가 훨씬 정확하다(같은 Zig 버전으로 실제
   컴파일되는 코드이므로).
4. **`stb_truetype.h`를 `@cImport` 안에서 `STB_TRUETYPE_IMPLEMENTATION`
   과 함께 include하면 Zig의 `translate-c`가 깨진다**(`invalid
   left-hand side to assignment`, `@as(c_int, x) -= 1` 패턴에서 발생).
   해결: 구현부를 별도 `.c` 파일로 분리(`terminal/src/
   stb_truetype_impl.c`, 2줄짜리 `#define` + `#include`)해서 `zig
   build-exe`에 직접 `.c` 파일로 넘겨 C 컴파일러 경로로 컴파일하고,
   `font.zig`의 `@cImport`는 선언만 가져오게(`@cDefine` 없이) 한다.
5. **Docker Desktop의 Rosetta amd64 에뮬레이션 자체가 Zig의
   `translate-c`(`@cImport` 처리 도구) 실행 중 `rosetta error:
   bss_size overflow` / `signal TRAP`으로 죽는 버그가 있다**(Apple
   Silicon Mac + `--platform linux/amd64`). 이 세션에서 Docker Desktop
   → Settings → General → "Use Rosetta for x86_64/amd64 emulation on
   Apple Silicon" 체크를 해제해서 우회했다(QEMU 기반 에뮬레이션으로
   대체 — 느리지만 안 죽음). **이 설정은 이제 이 Mac에 계속 꺼진
   상태로 남아있다** — 되돌리면 이 크래시가 다시 날 것이다.
6. **위 5번 때문에 이중 에뮬레이션(arm64 Mac → QEMU로 도는 amd64
   컨테이너 → 그 안에서 TCG로 x86_64 게스트를 돌리는
   qemu-system-x86_64)이 되면서 훨씬 느려졌다.** 두 가지 부작용:
   - `terminal/check.sh`의 screendump 전 대기 시간을 `sleep 5`(원래
     `display/check.sh`에서 그대로 가져온 값)에서 **`sleep 30`으로
     늘려야 했다** — 안 그러면 게스트 커널이 `/init`을 실행하기도
     전에 screendump를 찍어버린다.
   - `zig build-exe`가 `-mcpu`를 명시하지 않으면 **native CPU
     자동 감지에 의존하는데, 이 감지 결과가 이 에뮬레이션 환경에서
     신뢰할 수 없다.** 두 가지 증상으로 나타났다: (a) QEMU 게스트
     안에서 바이너리가 `invalid opcode` 트랩으로 즉시 죽음(빌드
     머신이 게스트의 가상 CPU가 지원 안 하는 명령어를 넣어버림),
     (b) `.c` 파일이 빌드에 섞이면 아예 `unknown target CPU
     'athlon-xp'`라는 말도 안 되는 값으로 컴파일 자체가 실패함.
     **해결: QEMU 게스트 안에서 실행될 바이너리(`terminal`)를 만드는
     모든 `zig build-exe` 호출에 `-mcpu=baseline`을 명시한다**
     (`terminal/check.sh` 참고). devcontainer 안에서 직접 실행하는
     `font_test`는 CPU 불일치 문제는 없었지만 (b) 때문에 결국
     필요했다.
7. **virtio-gpu 표시 순서 버그(Zig 포팅 과정에서 Claude가 만든 실수,
   Zig 버전과 무관)** — Rust 원본(`kms/src/main.rs`)은 픽셀을 채운
   *다음* `AddFB`+`SetCrtc`(화면에 실제로 표시하는 ioctl)를 부른다.
   처음 만든 `drm.zig` 포팅은 이 순서를 반대로 해서 `open()` 안에서
   `AddFB`+`SetCrtc`까지 다 해버리고, 그 후에 호출자가 `fill()`을
   불렀다 — 그 결과 화면은 항상 새까맣게 나왔다(에러도 크래시도 없이
   조용히 틀린 결과만 나오는 유형이라 가장 찾기 어려웠다). 지금
   커밋된 코드는 `drm.zig`의 `Framebuffer`가 `crtc_id`/`fb_id`/
   `connector_id`/`mode`를 들고 있고, `open()`은 `AddFB`까지만 하고
   `SetCrtc`는 별도 `pub fn present(self: Framebuffer) !void`
   메서드로 분리했다. **호출자는 모든 그리기(배경 채우기, 글자
   그리기 등)를 다 끝낸 뒤 `present()`를 정확히 한 번만 불러야
   한다.** TF-M2에서 입력에 반응해 다시 그리는 로직을 넣게 되면,
   매번 다시 그릴 때마다 `present()`를 또 불러야 하는지, 아니면
   최초 1회 이후엔 mmap 메모리 쓰기만으로 자동 반영되는지는 **아직
   검증 안 됨** — TF-M1은 최초 1회만 그리고 끝이라 이 케이스를
   테스트한 적이 없다.
8. **initrd는 바이너리가 런타임에 읽는 파일을 자동으로 담아주지
   않는다.** `kernel/make_initrd.sh`는 `init`/`terminal`/`fish`
   바이너리와 그 공유 라이브러리 의존성만 복사한다. TF-M1의 폰트
   파일(`terminal/vendor/fonts/Hanme_8x4x4.ttf`)을 깜빡하고 안 넣었다가
   `error: FileNotFound`로 처음 발견했다(`make_initrd.sh:26-27`에
   추가해서 해결). **TF-M2에서 `libghostty-vt`나 터미널이 런타임에
   읽는 설정/데이터 파일이 있다면 반드시 `make_initrd.sh`에도 추가할
   것** — 컴파일 타임에는 전혀 경고가 없고 QEMU 부팅 후에야 드러난다.

### 그 외 사소하지만 재발 가능한 것들

- `terminal/vendor/`는 `.gitignore:15`로 통째로 무시된다(다운로드
  스크립트로 받는 진짜 vendored 파일용). **손으로 작성한 소스 파일을
  거기 두면 커밋이 안 된다** — `stb_truetype_impl.c`를 처음엔
  `vendor/`에 뒀다가 `terminal/src/`로 옮겼다.
- Task 실행 중 파일명 오타(`font_text.zig` → `font_test.zig`)를 파일
  존재 확인(`find`)으로 잡아낸 적이 있다 — plan 파일명과 정확히
  일치하는지 매번 확인.

## 남은 작업

- [ ] screendump 육안 확인 (위 "완료된 작업" 절 참고)
- [ ] origin/main에 현재 4개 커밋 push — **사용자에게 먼저 확인 후 진행**
- [ ] **TF-M2(PTY + `libghostty-vt` 연동) 브레인스토밍부터 새로 시작.**
      `superpowers:brainstorming` 스킬 사용, 이 프로젝트 관례대로
      milestone plan은 브레인스토밍 이후 새로 작성(전체를 미리 설계하지
      않음). TF-M1에서 얻은 위 8가지 교훈(특히 1, 2, 6번)을 반드시
      전제로 깔고 설계할 것 — 특히 `libghostty-vt`가 내부적으로
      `std.Io`를 어떻게 쓰는지, PTY(파일 디스크립트 read/write 루프)를
      raw POSIX로 갈지 `std.Io`로 갈지는 브레인스토밍에서 명시적으로
      결정해야 한다.

## 핵심 파일

- `terminal/src/drm.zig` — DRM ioctl 포팅 완료본. `Framebuffer.present()`
  분리 패턴(교훈 7번) 참고용으로 계속 중요.
- `terminal/src/font.zig`, `terminal/src/font_test.zig`,
  `terminal/src/stb_truetype_impl.c` — glyph cache + FFI 우회 패턴
  (교훈 4번).
- `terminal/src/main.zig` — 전체 렌더러 통합본. `pub fn main(init:
  std.process.Init)` 시그니처와 `init.io` 사용 예시(교훈 2번).
- `terminal/check.sh` — QEMU 자동 검증 스크립트. `sleep 30`,
  `-mcpu=baseline` 값 자체가 교훈 6번의 증거이자 재발 방지 장치이므로
  섣불리 원래 값으로 되돌리지 말 것.
- `kernel/make_initrd.sh:26-27` — 폰트 파일 복사 라인(교훈 8번).
- `terminal/ghostty-src/` — TF-M0에서 vendor된 ghostty 전체 소스.
  Zig 0.16 API 사용 예시를 찾을 때 최우선으로 grep할 곳.
- `docs/superpowers/plans/2026-08-08-tars-terminal-foundation-tf-m1.md` —
  TF-M1 원본 plan. 코드 블록 상당수가 이제 실제 커밋된 코드와 다르다
  (위 교훈들 때문에 세션 중 수정됨) — plan 문서 자체는 갱신 안 했으므로
  참고용으로만 보고, 실제 소스는 `terminal/src/`를 신뢰할 것.

## 다음 에이전트에게

1. `git log --oneline -6` && `git status`로 이 파일과 실제 상태가
   일치하는지 먼저 확인 — 최신 커밋 `2d9460f`, origin/main보다 4개
   커밋 앞섬(미push), `kernel/initrd.cpio`만 unstaged.
2. `feedback_execution_scope.md`, `feedback_commit_delegation.md`를
   먼저 읽을 것(경로: `~/.claude/projects/
   -Users-dp-Repository-tars-linux/memory/`).
3. 위 "Task 2~4에서 겪은 근본 원인들" 8가지를 전제로 깔고 시작할 것 —
   특히 TF-M2가 `libghostty-vt`를 연동하는 첫 milestone이라면 1, 2,
   3번(Zig 0.16 `std.Io` API, `terminal/ghostty-src/` grep 습관)을
   가장 먼저 다시 적용하게 될 것이다.
4. 사용자가 아직 screendump를 육안으로 안 봤다면 그것부터 안내.
5. `superpowers:brainstorming`으로 TF-M2 설계를 새로 시작 — 이미
   완료된 design doc(`2026-08-08-tars-terminal-foundation-design.md`)
   의 milestone 초안은 있지만 TF-M2의 구체적 결정(PTY 구현 방식,
   `libghostty-vt` 연동 지점 등)은 아직 없다.
6. 실행 방식(pairing)과 design doc 필요 여부 판단 기준을 다시 묻지
   말 것 — 이미 여러 서브프로젝트에 걸쳐 확정됨.
