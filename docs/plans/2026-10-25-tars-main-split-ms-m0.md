# MS-M0 — terminal의 `main`을 `App`의 `open` · `tick` · `close`로 나눈다

Date: 2026-10-25
Design: `docs/specs/2026-10-25-tars-main-split-design.md`
Status: 착수 전.

## 누가 무엇을 하나

고치는 파일은 둘이다 — `terminal/src/main.zig`와 `probe/patch.pl`. 새 파일은 없다(design 결정 9). 옮기는 줄이 1,000줄이고
한 줄의 순서 실수가 컴파일을 통과한 채 게이트에서만 드러나므로(design 위험 1) lead가 직접 넣고, 네 단계로 나눠 단계마다 빌드 ·
로그 집합 비교 · 체인 하나를 거친 뒤 commit 하나를 만든다. 사용자는 commit 단위로 읽는다 — 한 commit의 진한 줄(design 결정
1(b))이 읽을 수 있는 양이어야 한다는 것이 단계를 나눈 이유다.

| 단계 | 무엇을 | 검사 |
|---|---|---|
| 1 | `App` 필드 · `open`(단계 다섯) · `close` · `tick`(바퀴 몸통을 한 덩어리로) · `main` | 빌드 · (a) · terminal 체인 |
| 2 | `tick` 앞부분을 `arm` · `readKeyboard` · `runScrolls` · `runCopies` · `runPanes` · `runDictates`로 | 빌드 · (a) · hangul 체인 |
| 3 | `tick` 뒷부분을 `readPointers` · `pollBattery` · `wirePointer` · `readPanes` · `readDictation` · `decideFrame` · `render` · `dumpFrame`으로 | 빌드 · (a) · pointer 체인 |
| 4 | `probe/patch.pl`의 anchor 셋, 호스트 `fmt` · `ast-check`, probe 부팅 한 번, 루트 게이트 | 22/22 |

## 착수 전에 확정한 것

1. 로그 집합 비교 (a)의 명령. 착수 전에 기준을 뽑아 둔다.

   ```bash
   rg -o 'logline\.print\(\s*"[^"]*"' --multiline terminal/src/main.zig | sort > /tmp/ms-logs-before.txt   # 94줄
   # 단계마다
   rg -o 'logline\.print\(\s*"[^"]*"' --multiline terminal/src/main.zig | sort | diff /tmp/ms-logs-before.txt -   # 빈 출력
   ```

   `sort`는 순서를 지운다 — 순서는 체인이 본다(`config/check.sh` 753줄의 `keyboard` → `clipboard`, pointer 검사 11의 `scroll>` →
   `at`).
2. diff를 읽는 명령 (b).

   ```bash
   git diff --stat
   git diff --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change   # 흐린 줄은 옮긴 것
   git diff --word-diff                                                              # 진한 줄의 바뀐 낱말이 self. 하나인지
   ```

3. 컨테이너 빌드와 체인 하나.

   ```bash
   docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c './prepare.sh && zig build test'
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./terminal/check.sh > /tmp/terminal.log 2>&1
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./hangul/check.sh > /tmp/hangul.log 2>&1
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./pointer/check.sh > /tmp/pointer.log 2>&1
   ```

   체인을 고른 이유 — terminal은 되살리기와 `spawned child pid` 수, hangul은 키보드 switch 넷의 길(조합 · copy · 상태 줄의 `text=` ·
   `ink fg=` 기준값), pointer는 포인터 · 배터리 · 덤프 순서(검사 11)다. 셋이 바퀴의 단계를 거의 다 밟는다.
4. `App`의 모양. 필드는 design 결정 2의 표 그대로이고 묶음 순서로 선언한다. 지역 변수의 주석은 필드의 문서 주석으로 간다.
   메서드는 전부 `fn`이다(`pub` 아님 — 이 파일 안에서만 부른다). `main`은 이렇게 된다.

   ```zig
   pub fn main(init: std.process.Init) !void {
       var app = try App.open(init, std.heap.page_allocator);
       defer app.close();
       while (try app.tick()) {}
       // 마지막 패널의 셸이 끝나면 터미널도 끝난다(WP design 결정 5) — 지금 main의 끝 주석 그대로
   }
   ```

5. `open`의 다섯 단계는 `*App`을 받아 필드를 채우는 `fn`이고, `open`이 `var self: App = undefined;`로 시작해 다섯을 순서대로
   부른 뒤 돌려준다 — 모든 필드가 다섯 안에서 채워지는지는 컴파일러가 안 봐 주므로(`undefined`), 단계마다 채우는 필드를 문서
   주석에 적고 `open` 끝에서 표와 대조한다. 기본값이 있는 필드(`needs_redraw = false` · `last_pane = null` 등)는 선언에 두고
   `open`이 `self = .{ … }` 대신 하나씩 대입하면 기본값이 안 먹으므로, `undefined` 대신 기본값을 전부 선언에 두고 `open`은
   `var self: App = .{ .fb = undefined, … }`로 시작하는 쪽이 맞다 — 그러면 "채우지 않은 필드"가 `undefined`로 적힌 것뿐이다.
   terminal은 `fb` · `cache` · `cols` · `rows` · `whole` 등 값이 준비 중에 정해지는 필드가 열다섯쯤이고, 그것만 `undefined`다.
6. `tick`의 반환은 `!bool`이다 — `false`가 `break :main_loop`(마지막 패널의 EOF), `decideFrame`의 "그릴 일이 없다"는 `tick` 안에서
   `return true`다. `readPanes`는 `!enum { keep, quit }`를 돌려준다.
7. 한 바퀴 안의 값. `readPointers`가 `struct { round: PointerRound, before_spot: ?pointer.Spot, supply_seen: bool }`을 돌려주고
   `pollBattery(supply_seen)` · `wirePointer(&round)` · `dumpFrame(round, before_spot)`이 받는다. `want`(화살표 자리)는
   `decideFrame`이 구해 `render`에 넘긴다. `ws` · `focus`는 단계마다 다시 구한다(design 결정 2).
8. 전역 `touchpad_screen` · `pointer_drawn`은 그대로 전역이다 — `tryOpenPointer` · `dumpPointerAt`이 `App` 밖에서 읽는다. 이번에
   필드로 옮기지 않는다(옮기면 그 함수들의 서명이 바뀌어 "옮기기"가 아니게 된다).
9. `defer`의 순서. 지금 `main`의 등록 순서는 `cache.deinit` → `clips.shared.deinit` → 패널 `deinit` → `cell_buf` free →
   `screen_line_buf` free → `signalDictation`이고 실행은 역순이다. `close`는 그 역순을 그대로 쓴다 — 받아쓰기 시그널 →
   `screen_line_buf` → `cell_buf` → 패널 → `clips.shared` → `cache`.
10. probe anchor 셋의 새 글자(단계 4에서 실제 코드를 보고 확정한다). (1) `pty_buf: [4096]u8 = undefined,`(필드, 들여쓰기 4) —
    끼우는 세는 값 셋도 필드가 되고 `probe_clock`은 `open` 끝에서 `std.Io.Clock.now(.awake, self.io)`로 초기화해야 하므로 anchor가
    둘로 늘 수 있다. (2) `pane.screen.feed(out);`는 그대로다. (3) `dumpFrame` 끝의 `dumpPointerAt` 호출 — 끼우는 코드의 `init.io`가
    `self.io`로, `frame_start` · `frame_us`는 `dumpFrame`의 인자나 지역으로 그 이름이 있어야 한다.
11. 체인 스크립트는 한 줄도 안 고친다(design 결정 1).

## Task 1: `App` · `open` · `close` · `tick`(한 덩어리) · `main`

`main` 바로 위에 `App`을 선언한다. 필드는 확정 4 · 5. `open`은 `openScreen` → `openKeyboard` → `spawnFirst` → `openPointers` →
`openBattery` 순서다(design 결정 3의 표). 지금 준비 구간의 코드가 그 다섯으로 잘려 들어가고, 지역 변수 선언은 필드 대입이 된다.
`tick`은 지금 `main_loop`의 몸통 전체를 `self.` 접두사만 붙여 옮긴 것이다 — `break :main_loop`는 `return false`, 끝의 `continue`는
`return true`, 몸통 끝은 `return true`.

검사 — 빌드, (a), terminal 체인. commit `MS-M0: Move the terminal main into App.open, tick and close`.

이 commit의 진한 줄은 접두사 `self.`가 붙은 줄(수백)과 필드 선언(56)이다. `--word-diff`로 읽는다.

## Task 2: `tick` 앞부분

`arm`(fds 짓기, `nfds` · `pty_base` · `pty_end`를 필드에), `readKeyboard`(`ctx` · `readKeys` · 받아쓰기 알림 지우기 · 바이트 → PTY
· `pointer_shown = false` · 넷 호출), `runScrolls` · `runCopies` · `runPanes` · `runDictates`. 네 switch는 글자 그대로다 — `else`
없음. `runPanes`가 `self.current`를 바꾸고 `ws`를 다시 구하는 자리는 지금처럼 그 함수 안이다. `readKeyboard`의 `focus`는 머리에서
한 번 잡는다(design 결정 2).

검사 — 빌드, (a), hangul 체인. commit `MS-M0: Split the keyboard phase of App.tick`.

## Task 3: `tick` 뒷부분

`readPointers` → `pollBattery` → `wirePointer` → `readPanes` → `readDictation` → `decideFrame` → `render` → `dumpFrame`(확정 7).
`tick`은 열 줄쯤의 호출과 각 줄의 순서 주석이 된다(design 결정 4). `decideFrame`은 `output_pending`의 하한 판단과 화살표만 고치는
갈래를 품고 `?pointer.Spot`(`want`)을 돌려주거나 "그릴 일 없음"을 알린다 — `enum { skip, draw }`와 `want`를 struct로. `render`는
`frame_start`를 잡아 `renderFinish`까지, `dumpFrame`은 `frame_us`를 재고 덤프 열둘 · `font>` · `dumpPointerAt`.

검사 — 빌드, (a), pointer 체인. commit `MS-M0: Split the pointer, pane and frame phases of App.tick`.

## Task 4: probe · 호스트 검사 · 루트 게이트

1. `probe/patch.pl`의 anchor 셋을 확정 10대로 고친다. `mkdir -p /tmp/rs-probe && perl probe/patch.pl terminal/src/main.zig
   /tmp/rs-probe/main.zig`가 `wrote`를 찍고 `diff`가 더한 줄만 보인다.
2. probe 부팅 한 번(약 1분 10초) — `docker run … -v /tmp/rs-probe/main.zig:/workspace/terminal/src/main.zig:ro … bash probe/run.sh
   ms 1`. 사본이 컴파일되고 `out/probe-rs/ms-run1.log`에 `terminal: probe>` 줄이 있으면 된다. 값은 안 본다 — 그리기를 안 고쳤다.
3. 호스트 0.17 `zig fmt --check` · `ast-check`(lessons "범용 명령").
4. 루트 게이트(`run_in_background`, 약 10분 반). 22/22면 commit `MS-M0: Re-anchor the render probe on App` 뒤 닫는다.
5. 닫을 때 — design `Status:`에 M0 줄, `HANDOFF.md`(M0 끝 · M1 plan 다음), lessons "핵심 파일"의 terminal `main.zig` 줄.
   completed · decisions · MEMORY는 M1 뒤에 한 번.

## MS-M0이 실측한 것

(끝난 뒤 적는다.)
