# DR-M1 — verify 모드

Date: 2026-10-29
Design: `docs/specs/2026-10-28-tars-dirty-rows-design.md`(결정 7 · 8, 위험 1 · 2)
Status: plan(착수 전). 앞 milestone DR-M0은 끝났다(`67596a0`).

## 이 milestone이 끝나면

- 게이트의 모든 부팅에서 terminal이 프레임마다 `terminal: verify> ok us=<N>` 한 줄을 찍는다. 그리기는 통째 그대로라 전부
  `ok`여야 하고, 그것이 verify 자체의 검사다(design 결정 8 — 두 경로가 같은 픽셀을 내는가).
- 루트 게이트가 회차마다 그 줄을 세어, 하나라도 `ok`가 아니거나 한 줄도 없으면 그 회차가 빨갛다. 한 줄도 없는 것을 빨강으로
  두는 이유는 켜는 길이 조용히 빠졌을 때 "모두 통과"로 읽히지 않게 하기 위해서다.
- 배포 ISO(`make iso`)와 프로브(`probe/run.sh`)에서는 꺼져 있다. 바이너리는 같고 initrd 안의 표식 파일 하나가 다르다.
- `renderFinish`가 그리기(`renderOverlay`)와 내보내기(`presentFrame`)로 갈라져 있다 — M2가 clip을 넘길 자리가 `presentFrame`
  하나다.
- 일부러 지우기를 빼먹은 판(mutation)에서 verify가 `mismatch`를 찍고 루트 게이트의 판정이 빨개지는 것을 봤다.

## 착수 전에 확정한 것

HEAD `3d37659`에서 코드로 확인했다.

1. 켜는 길은 initrd의 표식 파일이다. `kernel/make_initrd.sh`가 환경 변수 `TARS_RENDER_VERIFY=1`일 때 `/etc/tars/render-verify`
   (빈 파일)를 initrd에 넣는다. terminal은 `App.open`에서 그 파일이 열리는지 본다(`std.c.open`으로 열어 보고 닫는다 — `:1944`의
   관용구). 루트 `check.sh`는 `prebuild` 앞에서 `export TARS_RENDER_VERIFY=1` 한 줄, `Makefile`의 `check` 타깃은 체인의
   `./check.sh` 앞에 같은 변수를 둔다(체인이 `make_initrd.sh`를 제 손으로 부르므로).
   - 다른 길을 안 고른 이유. cmdline은 체인 스물둘의 `-append`가 저마다 있어 스물두 군데다. 빌드 옵션(`-Dverify`)은 게이트가
     배포와 다른 바이너리를 시험하게 된다. 설정 키(`tars.conf`)는 체인마다 굽는 설정 디스크에 넣어야 한다. 표식 파일은 initrd를
     묶는 자리가 `make_initrd.sh` 하나라 한 군데다.
   - init → terminal의 argv 계약(`shared/screen_args.zig`)을 안 거친다. 이것은 사용자 설정이 아니라 게이트의 빌드 산출물이고 init이
     알 일이 아니다. 표식이 빠지는 어긋남은 확정 7의 "한 줄도 없으면 빨강"이 잡는다.
   - 루트 게이트는 initrd를 `prebuild`에서 한 번 묶고 체인은 건너뛴다(`TARS_PREBUILT_INITRD`). export가 `prebuild` 앞이면 된다.
     ISO 줄(boot · machine · install)의 `make_iso.sh`도 그 initrd를 싣는다. `probe/run.sh`는 변수를 안 두므로 꺼진다 — M2의
     재측정에 verify 비용이 안 섞인다.
2. `renderFinish`를 둘로 가른다(design 위험 2). `renderOverlay(fb, cache, prompt, st) !?PromptInk`는 프롬프트와 상태 줄이고,
   `presentFrame(fb, sprite, want) !void`는 `forget` → `show` → `present`다. `render`의 순서는 `renderOverlay` → `verifyFrame` →
   `presentFrame`이다. 화살표는 비교 뒤에 그려지므로 비교에서 빠진다(위험 2의 "빼거나"). `probe/patch.pl`의 anchor 넷(`App` 필드 ·
   `feed` · `dumpFrame` 둘)은 이 자리에 없어 그대로 붙는다. `probe/split.pl`의 anchor(`renderFinish(` · `try fb.present();`)는
   깨진다 — M0 plan 확정 1이 예고한 대로 M0의 HEAD 전용이다.
3. 그림자 버퍼는 `drm.Framebuffer` 값 하나 더다. `Framebuffer`는 `pixels` · `pitch` · `width` · `height`를 가진 값이고 모든 그리기
   함수가 그것을 값으로 받으므로, 같은 치수에 heap 메모리를 가리키는 값을 만들면 그 위에 그대로 그린다. `drm.zig`에
   `pub fn shadow(self: Framebuffer, pixels: [*]u8) Framebuffer`(`fd` -1 · id 셋 0 · `dirty` false)를 두고 주석에 "`present` ·
   `modeset`을 부르면 안 된다"를 적는다. 메모리는 `pitch × height`(1280×800이면 4MB)이고 verify가 켜졌을 때만 `App.open`에서 잡는다.
   `App`의 필드는 `verify: ?Verify`이고 `Verify`는 `fb` · `cell_buf`(격자 전체 크기 하나 더) · `img_buf`다.
4. `verifyFrame`의 순서는 `render`의 통째 경로 그대로다 — `renderBackdrop` → 포커스 아닌 패널(그림자 `cell_buf`에 `cells()`를
   다시 부른다) → 포커스 패널은 `frame.cells` · `frame.imgs`(실제 경로가 방금 그린 그 목록) · `cursorMark()` → `renderOverlay(frame.prompt,
   frame.status_line)`. 포커스 패널에 `cells()`를 다시 안 부르는 이유는 `frame.cells`가 `self.cell_buf`를 가리키고 덤프 열둘이 그것을
   읽기 때문이다 — 그림자 패스는 덤프가 읽는 것을 건드리지 않는다. 포커스 아닌 패널은 실제 경로가 버린 것이라 다시 불러야 하고
   그림자 `cell_buf`에 넣는다. 한 프레임에 `cells()`를 두 번 불러도 `vt.Screen`이 같은 답을 낸다고 전제한다 — 어긋나면 그것이
   design 결정 8의 "이미 있던 비결정성"이고 verify가 보여 준다.
5. 비교는 픽셀 행마다 `width × 4`바이트를 `std.mem.eql`한다. pitch의 패딩은 안 본다(우리가 안 쓴 바이트라 dumb buffer 쪽 값이
   무엇이든 뜻이 없다). 다른 픽셀 행은 격자 행(`y / ROW_HEIGHT`)으로 묶고, 격자 아래(상태 줄)는 `rows`번이다. 이 산수는 순수
   모듈 `terminal/src/verify.zig`의 `compare(a, b, width_bytes, pitch, height, row_height) Report`에 두고 호스트 `verify_test`가
   돈다(`image_test`와 같은 배선). `Report`는 `{ rows: u16, first: [8]u16 }`이다 — M2에서 행 비교 모듈(design 결정 9)이 같은 파일에
   들어올 자리다.
6. 줄의 모양. `terminal: verify> ok us=<N>` 또는 `terminal: verify> mismatch rows=<n> first=<r>,<r>,…`(최대 8). `us`는 그림자
   그리기와 비교에 든 시간이다. `render`에서 `frame_us`를 셈한 뒤에 찍는다 — `screen>`보다 앞이라 게이트의 `last_frame`(마지막
   `screen>`부터 끝까지) 밖이고, 체인의 덤프 순서 계약에 안 든다. `frame_us`는 안 건드린다 — verify 시간이 들어간 채다. 그 값을
   읽는 체인이 없고(`images>` 덤프에 실릴 뿐), 프로브는 꺼진 상태에서 돌므로 M2의 비교에는 안 섞인다. design 위험 1의 "흔들리면
   `frame_us` 밖으로"는 벽시계 쪽 말이라 이 결정과 무관하게 게이트가 본다.
7. 루트 게이트의 판정 자리는 `run_chain`의 회차 뒤 검사 둘(`count_cut_lines` · `check_initrd_inode`) 옆이다 — `check_verify_lines
   "$dir" "<label>"`. `grep -rlaE '^terminal: ' "$dir"`로 terminal 줄이 든 파일을 찾고(`cut_log_lines`와 같은 방법), 파일마다
   `tlog | grep -a 'terminal: verify>' | from_terminal`로 커널 printk가 자른 줄을 이어서 읽는다. 총 0줄이면 FAIL("verify lines
   missing — the initrd marker is off or the terminal never rendered"), `^terminal: verify> ok us=[0-9]+\r?$`가 아닌 줄이 있으면
   FAIL하고 그 줄을 파일 이름과 함께 찍는다(최대 20). 통과하면 `<label>: verify lines <N> ok` 한 줄. `make check CHAIN=x`에는 판정이
   없다(cut-line 검사와 같다) — 읽는 한 줄을 lessons "범용 명령"에 적는다.
8. mutation은 둘이다(design 결정 8).
   - (a) 호스트만. 가짜 run dir 셋 — `ok` 둘 + `mismatch` 하나 → FAIL, 줄 없음 → FAIL, `ok`만 → PASS. 함수를 `source`해서 댄다
     (lessons의 진입 검사 셋을 대 보는 법과 같은 꼴). 부팅이 없다.
   - (b) 게스트. `render`의 `renderBackdrop(self.fb, &ws.tree, self.whole);` 한 줄을 뺀 `main.zig` 사본을 `-v …:ro`로 덮고
     (lessons "범용 명령"의 mutation 꼴) `TARS_RENDER_VERIFY=1`로 `terminal/check.sh` 한 체인을 돌린 뒤 그 TMPDIR에
     `check_verify_lines`를 댄다. 실제 fb는 여백 · 빈 칸을 안 지우고 그림자는 지우므로, 글자가 사라진 프레임(스크롤 · 지움)에서
     `mismatch`가 나온다 — "지우기를 빼먹은 판"이고 M2가 틀리면 나올 바로 그 모양이다. 바뀐 것이 없는 프레임은 `ok`라 줄 전부가
     빨갛지는 않다. 기대는 `mismatch` 한 줄 이상과 판정 FAIL이다.
9. 비용의 예상과 보는 법. verify는 프레임마다 통째 그리기 한 번(약 2.45ms, DR-M0)과 4MB 비교를 더한다 — TCG에서 프레임이 두 배
   가까이 늘어진다. 타이밍에 예민한 체인(render의 pacing · pointer · battery)이 흔들리는지는 루트 게이트가 본다(design 위험 1).
   흔들리면 그때 다시 정한다 — 후보는 verify를 N 프레임에 한 번만 하는 것과 비교를 덤프 뒤로 미루는 것.

## Task 1: terminal — 분할 · 그림자 · 비교

- `terminal/src/drm.zig`: `Framebuffer.shadow`(확정 3).
- `terminal/src/verify.zig`(새, 순수 — libc · 로그 없음): `MAX_FIRST = 8`, `Report`, `compare`(확정 5).
- `terminal/src/verify_test.zig`(호스트)와 `build.zig` 배선: 같은 버퍼 → `rows` 0. 픽셀 행 셋이 다르고 그중 둘이 같은 격자 행 →
  `rows` 2, `first` 그 둘. 격자 아래 픽셀 행 → `rows`번. 아홉 격자 행이 다르면 `rows` 9, `first`는 앞 여덟. pitch에 패딩을 두고
  패딩만 다르게 해서 → `rows` 0.
- `terminal/src/main.zig`: `renderFinish` → `renderOverlay` + `presentFrame`(확정 2). `Verify` 구조체와 `App.verify`(확정 3).
  `App.open`에서 표식 파일 보기(확정 1)와 메모리, `close`에서 해제. `verifyFrame`(확정 4 · 5 · 6). `render`의 호출 순서. `render`
  머리 주석의 "부분 갱신은 불필요한 복잡도다(YAGNI)"는 낡았다 — DR을 가리키게 고친다.
- 호스트에서 `zig fmt --check` · `ast-check`(lessons "범용 명령"), `git diff --stat`. 컨테이너에서 `cd terminal && zig build test`가
  `verify_test`를 돈다.
- commit 하나.

## Task 2: 게이트 배선

- `kernel/make_initrd.sh`: 표식 파일 블록. 주석에 왜 여기인가(확정 1).
- `check.sh`: `prebuild` 앞의 `export TARS_RENDER_VERIFY=1`과 주석, `check_verify_lines`, `run_chain`의 호출(확정 7).
- `Makefile`: `check` 타깃의 환경 변수. help 글에 한 줄.
- mutation (a)(확정 8). 셋의 결과를 결과 절에 적는다.
- commit 하나.

## Task 3: mutation (b) · 루트 게이트 · 기록

- mutation (b)(확정 8) — 명령을 글자 그대로 결과 절에 적고, `mismatch` 줄 몇과 판정의 FAIL 줄을 붙인다. 사본은 지운다.
- 루트 게이트 1회(`run_in_background`, CR-M0은 9분 47초 — verify 때문에 더 걸릴 수 있다). 22/22와 회차마다 `verify lines <N> ok`.
- 결과 절: 체인별 verify 줄 수, 한 체인 로그의 `us` 중앙값, 게이트 시간(prebuild · lanes)과 CR-M0 비교, 흔들린 체인 유무.
- design의 milestone 표 M1 행, 이 plan Status, `HANDOFF.md`, lessons "범용 명령"에 verify 줄 읽는 한 줄.
- commit 하나.
