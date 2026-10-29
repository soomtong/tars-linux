# DR-M1 — verify 모드

Date: 2026-10-29
Design: `docs/specs/2026-10-28-tars-dirty-rows-design.md`(결정 7 · 8, 위험 1 · 2)
Status: 끝났다(2026-10-29). Task 1 `b8ffd8f` · Task 2 `0c2109e` + `bc52490` + `9fd3e68` · Task 3 닫기. 루트 게이트 22/22(셋째 회차, 9분 50초). verify는 세 회차 약 2만 3천 프레임 전부 `ok`, mutation은 31프레임 `mismatch`로 잡혔다.

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

## 결과 (2026-10-29)

plan과 달라진 것 둘. 격자 행 산수는 `y / ROW_HEIGHT`가 아니라 격자 원점(`GRID_Y` 20)을 뺀 것이다(`verify.Grid.rowOf` — 위 여백은
0번, 격자 아래는 `rows`번). 그리고 부팅에 `terminal: verify> on bytes=<N>` 한 줄을 더 찍는다 — "표식이 없다"와 "프레임이 한 번도
없었다"를 가르기 위해서이고, 판정의 regex가 이 줄도 받는다. mutation (a)는 손으로 한 번 대는 대신 게이트 시작마다 도는 진입
검사 `require_verify_verdict`로 넣었다(`require_cut_lines_found`와 같은 꼴, 가짜 회차 셋 — ok만 · mismatch 섞임 · 줄 없음).

Task 1(`b8ffd8f`): 호스트 0.17 `zig fmt --check` · `ast-check` 통과, 순수 `verify_test` 다섯 통과(호스트 `zig run`과 컨테이너
`zig build test` 둘 다). 컨테이너 `prepare.sh && zig build test` 1분 57초. 지운 줄 16은 전부 `renderFinish`의 머리 · 화살표 인자 ·
호출 한 줄과 낡은 주석 둘이다.

Task 2(`0c2109e`): `check_verify_lines`의 자가검사 셋이 호스트에서 통과했고 `require_no_early_exit_pipe ./check.sh`도 통과했다.

mutation (b) — `render`의 `renderBackdrop(self.fb, &ws.tree, self.whole);` 한 줄을 뺀 사본:

```bash
cp terminal/src/main.zig /tmp/run/main.zig && perl -0pi -e 's/^        renderBackdrop\(self\.fb, &ws\.tree, self\.whole\);\n//m' /tmp/run/main.zig
docker run --rm -e TARS_RENDER_VERIFY=1 -v "$PWD":/workspace -v /tmp/run/main.zig:/workspace/terminal/src/main.zig:ro \
  -w /workspace tars-devcontainer bash -c 'mkdir -p /tmp/gate-logs/mutation && (cd terminal && TMPDIR=/tmp/gate-logs/mutation ./check.sh); \
  mkdir -p out/gate-logs && rm -rf out/gate-logs/mutation && mv /tmp/gate-logs/mutation out/gate-logs/'
bash -c 'source <(sed -n "/^VERIFY_OK_LINE=/,/^}/p" check.sh); check_verify_lines out/gate-logs/mutation MUTATION'
```

체인 자체는 PASS였다(2분 32초) — 덤프는 글자가 있는 셀만 읽으므로 잔상을 못 본다(design 배경 6 그대로). verify는 봤다: 줄 55
(`on` 2 · `ok` 22 · `mismatch` 31), 판정은 FAIL.

```
MUTATION: verify lines 55 (out/gate-logs/mutation)
MUTATION FAIL: render verify saw frames that differ from a full redraw (first 20):
out/gate-logs/mutation/tmp.meRbqHdRLN: terminal: verify> mismatch rows=1 first=0 us=9116
…
out/gate-logs/mutation/tmp.meRbqHdRLN: terminal: verify> mismatch rows=2 first=0,2 us=7848
```

다른 행은 0(프롬프트 줄)과 2다 — 체인이 글자를 치고 지우는 줄이고, 지우기가 빠진 실제 fb에 그 픽셀이 남았다. 아무것도 안
사라진 프레임은 `ok`라 줄 전부가 빨갛지는 않다(확정 8의 기대 그대로). verify 한 번의 `us` 중앙값은 5.9ms(n=53, 4.7~21.5ms) —
DR-M0의 (a) frame 2.45ms보다 크다. 그림자 그리기에 4MB 비교가 더해진 값이고 프로브와 조건이 같지 않으므로(체인 하나의 부팅,
heap 버퍼의 첫 page fault) 숫자 자체는 안 옮긴다. 이것이 프레임을 늘여 체인을 흔드는지는 아래 루트 게이트가 본다.

첫 루트 게이트는 0.8초 만에 진입 검사에서 빨갰다 — `check FAIL: check_verify_lines rejects a run whose verify lines are all ok`.
호스트의 자가검사는 통과했는데 컨테이너에서는 아니었다. 판정 regex의 `\r?`가 원인이다: macOS의 BSD grep은 `\r`를 CR로 읽지만
컨테이너의 GNU grep은 ERE에서 `\r`를 모른다(글자 `r`). 시리얼의 CR을 `tr -d '\r'`로 떼고 regex에서 `\r?`를 뺐다(`bc52490`). 양쪽
grep에서 자가검사가 통과한다 — 게이트의 셸 검사는 호스트에서 대 본 것으로 끝내지 않고 컨테이너에서도 한 번 댄다.

루트 게이트 첫 회차(`bc52490`): 12분 11초(prebuild 389초 — cold build, lanes 339초). 21/22 — 21체인 7852프레임이 전부 `ok`,
`mismatch` 0. 빨간 하나는 BF-M4(boot 체인)로, `verify lines 0`이라 판정이 FAIL했다. 그 체인은 DRM 장치 없이 부팅해 terminal이
`OpenFailed`로 세 번 죽고 init이 포기하는 것을 보는 체인이다 — 프레임이 없으니 verify 줄이 0인 것이 맞다. 판정 규칙을 좁혔다
(`9fd3e68`): 줄이 0이면 빨강인 것은 `terminal: render> first frame`이 있는 회차(프레임을 그렸다)뿐이고, 안 그린 회차는
"no frame was rendered"를 찍고 통과한다. 표식이 빠진 채 그린 부팅은 `first frame`은 있고 verify 줄은 없으니 여전히 빨갛다.
자가검사에 넷째(프레임 없는 회차 → 통과)를 더했고, 첫 회차의 BF-M4 · TF-M4 로그 디렉터리에 새 판정을 대 보니 통과 · 57줄 통과였다.

첫 회차의 체인별 verify(`ok` 줄 수 · `us` 중앙값, ms): AU 12 · 14.6, BS 226 · 5.6, CB 383 · 6.4, CM 545 · 6.5, CP 1784 · 7.0,
CT 9 · 21.8, DC 18 · 13.3, FW 510 · 6.7, HD 3 · 15.0, HI 180 · 5.8, IP 169 · 6.7, PD 678 · 6.5, PM 55 · 7.2, RM 4 · 7.7, TD 1392 · 7.9,
TF 55 · 6.1, TR 770 · 6.7, UT 895 · 10.3, VD 147 · 5.8, WL 10 · 17.7, WN 7 · 5.3. 전체 중앙값 7.2ms(n=7852, p90 15.2ms). 프레임이 적은
체인(CT · WL · HD · AU)의 중앙값이 큰 것은 첫 프레임들(heap 그림자의 첫 page fault · 글리프 굽기)이 표본의 대부분이라서다.
동시에 여섯 줄이 도는 게이트의 TCG라 DR-M0의 프로브(혼자 도는 부팅, 2.45ms)와 섞지 않는다. lanes 339초는 CR-M0의 296초보다
43초(15%) 길고 LI-M1의 334초와는 같다 — verify 비용이 게이트 시간에 보이기는 하되 체인을 흔들지는 않았다(위험 1). 가장 긴 체인은
CP 216초 · TD 213초(CR-M0은 net 196초).

루트 게이트 둘째 회차(`9fd3e68`): 10분 53초(prebuild 322 + lanes 328초). verify는 전부 통과 — 21체인 7486프레임 `ok`,
`mismatch` 0, 중앙값 6.8ms(p90 14.4ms), BF-M4는 "no frame was rendered"로 통과. 그러나 20/22 — FW-M2와 DC-M2가 verify와 무관한
제 검사에서 빨갰다(첫 회차에서는 둘 다 통과).
- DC-M2 boot 7(USB 디스크를 4초 늦게): `tars-init: config storage /dev/sda2`를 기다림 없이 찍었고 `appeared after`가 없다. 그
  부팅의 콘솔 셸이 17초 만에 떴다(다른 부팅 여섯은 8~10초) — 커널 부팅이 느려 init이 처음 훑을 때 이미 USB의 4초가 지나
  있었다. terminal이 뜨기 전의 일이고 그 부팅은 `/dev/dri/card0 not found`라 프레임도 없다. 동시에 여섯 줄이 도는 호스트의
  순간 부하다.
- FW-M2 검사 18(`tars-config firewall allow 7072` 뒤 호스트가 붙어 `fwm2-tcp-7072-ok`를 받는다): `applied now`까지 화면에 떴는데
  받은 것이 빈 값이고, 회차가 58초(첫 회차)가 아니라 35초로 끝났다 — 열 번의 `read -t 5`가 timeout이 아니라 곧바로 EOF였다는
  뜻이다. 7072의 리스너는 `nc -l -p 7072` 한 번짜리다. 읽히는 모양은: 검사 8이 막힌 포트에 붙었을 때 SLIRP이 호스트 쪽 연결은
  받고 게스트로 보낸 SYN은 방화벽이 버렸는데(실측 73의 모양), SLIRP이 그 SYN을 재전송하다가 allow로 포트가 열린 순간 닿아
  `nc`가 그 묵은 연결을 받아 한 줄을 쓰고 끝났고, 검사 18의 진짜 연결은 RST → EOF. 실측 73이 "SLIRP이 버려진 SYN을 언제 다시
  보내는지는 재지 않았다"고 남겨 둔 자리다. 검사 8과 allow 사이는 타이핑과 화면 대기라, verify로 프레임이 늘면 그 간격이
  재전송 창에 걸리는 자리가 움직일 수 있다 — verify의 잘못은 아니지만 verify가 드러낼 수 있는 체인의 숨은 경주다.

둘을 verify 켠 채 혼자 다시 돌렸다(한 컨테이너에서 차례로, 7분 4초): FW 3/3 통과(193 · 61 · 59초 — 첫 판은 빌드 포함), DC 1/1
통과(110초). verify 1549프레임 전부 `ok`. 둘 다 동시에 여섯 줄이 도는 게이트의 부하에서만 난 흔들림으로 읽는다. FW의 숨은
경주(위)는 `carryover.md`에 적는다 — 고치는 길은 검사 18이 검사 8이 건드린 적 없는 포트를 열어 보는 것, 또는 7072의 리스너를
한 번짜리 `nc`가 아니라 다시 듣는 꼴로 두는 것이다. 이 milestone에서는 안 고친다(verify의 일이 아니다).

루트 게이트 셋째 회차(`9fd3e68`, 코드는 둘째와 같다): 22/22, 9분 50초(prebuild 288 + lanes 300초). verify 8219프레임 `ok`,
`mismatch` 0, 중앙값/p90 6.6/10.4ms. BF-M4는 "no frame was rendered"로 통과. 가장 긴 체인 TD 199초 · CP 182초. lanes 300초는
CR-M0의 296초와 같다 — 둘째 회차의 328 · 첫 회차의 339초까지 합치면 verify의 게이트 시간 비용은 호스트 부하의 흔들림(±40초)
안이다. 세 회차 합쳐 21체인 약 2만 3천 프레임에서 `mismatch`가 한 번도 없었다 — 통째 경로 둘이 같은 픽셀을 내고, 이 숫자가
DR-M2가 부분 갱신을 넣은 뒤 받아야 할 기준이다.

이 milestone이 남긴 것: DR-M2의 `verifyFrame`은 그대로 두고 실제 경로만 부분 갱신으로 바꾼다. 그림자 경로가 `renderBackdrop` ·
`renderPane` · `renderOverlay`를 그대로 부르므로 M2가 그 함수들의 모양을 바꾸면 그림자도 함께 바뀐다 — 통째 경로의 정의가
"지금의 함수 셋을 차례로"라는 것을 M2 plan이 기억해야 한다.
