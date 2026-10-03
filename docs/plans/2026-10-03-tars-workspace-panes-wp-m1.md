# WP-M1 — 분할 · 닫기 · 순환

Date: 2026-10-03
Design: `docs/specs/2026-10-03-tars-workspace-panes-design.md`
Status: 구현과 검증이 끝났다(2026-10-03). 호스트 검사 아홉이 새로 섰고, 열여덟번째 체인 `pane/check.sh`(검사 열하나)와 regression 네 체인이 초록이며, 루트 게이트 18체인 3/3 PASS(1시간 3분 30초). 값은 아래 "M1이 실측한 것" 절에 있다.

## 이 milestone이 끝나면

- `Cmd+D`가 포커스 패널을 세로로 갈라 오른쪽에 새 셸을 띄우고, `Cmd+Shift+D`가
  가로로 갈라 아래에 띄운다. 새 패널이 포커스다(design 키 표).
- `Cmd+W`가 포커스 패널의 셸에 SIGHUP을 보내고, 셸이 끝나 PTY가 EOF를 내면
  그 패널이 닫힌다. 셸에 `exit`를 친 것과 같은 길이다(결정 5). 형제가 그
  자리를 채우고 포커스는 다음 패널로 간다. 마지막 패널이면 WP 전처럼
  terminal이 끝나고 init이 되살린다.
- `Cmd+]` · `Cmd+[`가 포커스를 순환한다(끝에서 감긴다).
- 패널 사이에 셀 한 칸짜리 구분선이 전용 색 `SEPARATOR`로 그려진다(결정 2).
- 셸 커서는 포커스 패널에만 보인다(결정 6).
- 새 로그 줄 `pane>`이 선다(결정 7). `screen>`은 포커스 패널만 찍고 글자 모양이
  안 바뀐다.
- 새 체인 `pane/check.sh`(열여덟번째)가 `check.sh`의 `CHAINS`에 든다. 루트
  게이트 3/3.
- copy mode 안에서는 이 키들이 아무 일도 안 한다(결정 4). 게이트가 그것을
  음성으로 본다.

## 착수 전에 확정한 것

1. `terminal/check.sh:196-202`가 `spawned child pid` 줄의 개수로 "init이
   terminal을 되살렸다"를 판정한다. 분할로 띄운 셸은 그 줄을 안 찍는다 —
   `pane>` 줄이 대신한다. 부팅의 첫 패널만 지금처럼 찍는다.
2. `screen>`은 프레임당 한 줄이고 행은 ` | `로 갈린다(`dumpScreen`). 그래서
   "마지막 프레임"은 `grep | tail -n 1`이다. `wait_for_screen`은 로그
   전체를 보므로(`project_gate_screen_echo`) 포커스를 옮긴 뒤의 음성 판정은
   마지막 줄 하나만 본다.
3. ghostty `Terminal.resize(alloc, .{ .cols, .rows, .cell_size_px = .{
   .width, .height } })`(`Terminal.zig:3733-3779`). `cell_size_px`를 안 주면
   `width_px` · `height_px`가 안 바뀐다 — kitty 이미지와 `CSI 14t`의 답이
   그 값을 본다(TG 결정 2). `Screen`이 `cell: CellPx`를 필드로 들어야
   `resize`가 같은 값을 다시 준다.
4. `cells()`는 글자도 색도 없는 셀을 안 내보낸다. 그래서 격자를 통째로
   `SEPARATOR`로 칠하고 패널이 덮게 둘 수 없다 — 빈 셀이 구분선 색이 된다.
   구분선은 트리에서 사각형 목록으로 꺼내 따로 그린다(`Tree.separators`).
5. `c_pty` 번역에 `signal.h` · `sys/wait.h`가 없다. `pty.zig`가 `execv`를
   `extern "c"`로 직접 선언한 것과 같은 모양으로 `kill` · `waitpid`를
   선언한다 — 번역에 헤더를 더하면 fortify 문제가 생길 자리가 는다
   (`project_zig_c_uapi_rule`).
6. `handleKey`의 copy 분기(`input.zig:1333`)가 `chord`(1406)보다 앞이다.
   copy mode에서 `Cmd+D`는 copy 표가 삼키고 `nothing`이 된다 — 코드를 안
   고치고 `input_test`로 못 박는다.
7. 체인 넷을 겹쳐 돌리지 않는다(M0 실측 8). 각 체인이 같은 디렉터리에
   initrd를 다시 빌드한다.

## Task 1: `layout.zig` — 구분선

- `pub fn separators(self: *const Tree, whole: Rect, out: []Rect) []Rect` —
  내부 노드마다 사각형 하나. 세로 분할이면 `col = first.col + first.cols,
  cols = 1, row · rows는 부모의 것`, 가로 분할이면 그 반대.
- `layout_test`: 오른쪽 분할 하나 → 구분선 하나 `(77,0) 1x47`(155x47 기준) ·
  셋으로 가르면 둘 · 패널 사각형과 구분선 사각형의 넓이 합이 격자 넓이와
  같다.

## Task 2: `input.zig` · `input_test.zig`

- `pub const Pane = enum { split_right, split_below, close, focus_next,
  focus_prev }`. 워크스페이스 variant는 M2에서 더한다(미리 만들지 않는다).
- `Action.pane: Pane`. `State.panes: [8]Pane`, `Keys.panes`. `readKeys`에
  `.pane` arm — `scrolls`와 같은 모양.
- `chord`의 Meta 분기를 바꾼다(결정 4): 첫머리에 `if (self.shifted()) return
  switch (code) { KEY_C => copy enter(모드 세우기 포함), KEY_D =>
  .split_below, else => null }`. 그 뒤 기존 표에 `KEY_D => .split_right`,
  `KEY_W => .close`, `KEY_RIGHTBRACE => .focus_next`, `KEY_LEFTBRACE =>
  .focus_prev`. CM design 위험 2의 "Shift 예외는 하나뿐" 주석을 "이 switch
  하나뿐"으로 고친다.
- `input_test`: 다섯 키 각각 양성 · copy mode 안의 `Cmd+D`가 `nothing`(음성) ·
  `Cmd+Shift+D`가 `.split_below`이지 `.split_right`가 아니다 · `Cmd+Shift+C`가
  여전히 copy enter다.

## Task 3: `vt.zig` · `vt_test.zig`

- `Screen.cell: CellPx` 필드(`init`이 채운다).
- `pub fn resize(self: *Screen, cols: u16, rows: u16) !void` — copy mode면
  먼저 `copyExit()`(결정 3, `find`까지 함께 버린다), 그다음
  `term.resize(alloc, .{ .cols, .rows, .cell_size_px = .{ .width = cell.w,
  .height = cell.h } })`.
- `Screen.focused: bool = true`. `cells()`의 셸 커서 반전(`vt.zig:693`
  근처)이 거짓이면 건너뛴다. copy 커서 · preedit은 안 건드린다.
- `vt_test`: `resize(10, 3)` 뒤 `cells()`의 모든 `col < 10`, `row < 3` ·
  copy mode에서 `resize`하면 `copyActive()`가 거짓 · `focused = false`면
  커서 자리 셀의 `fg` · `bg`가 기본값 그대로(반전 없음) · `resize` 뒤
  `term.width_px == 10 * 8`.

## Task 4: `pty.zig`

- `pub fn resize(fd: c_int, cols: u16, rows: u16) void` —
  `ioctl(fd, TIOCSWINSZ, &ws)`. SIGWINCH는 커널이 보낸다.
- `pub fn hangup(s: Session) void` — `kill(child_pid, SIGHUP)`.
- `pub fn close(s: Session) void` — `close(master_fd)` 뒤 `waitpid(child_pid,
  null, 0)`. 막히는 이유와 짧은 이유는 결정 5.
- `kill` · `waitpid`는 `extern "c"`(확정 5). `SIGHUP = 1`은 리눅스 상수를
  여기 적고 주석에 출처(`asm-generic/signal.h`)를 둔다.

## Task 5: `main.zig`

- `SEPARATOR: u32 = 0x00405060`(결정 2). 주석에 왜 전용 색인지(CI 결정 3과
  같은 이유).
- `applyLayout(ws: *Workspace, whole)` — `tree.rects`로 사각형을 다시 구하고,
  `rect`가 바뀐 패널마다 `screen.resize` · `pty.resize` · `pane.rect = new`.
  분할 뒤와 닫기 뒤 둘 다 이것을 부른다 — "크기가 바뀐 것만 다시 잰다"
  규칙 하나로 두 경우를 덮는다. 새 잎의 칸은 아직 null이라 건너뛴다.
- 패널 명령 루프(copy 루프 뒤, `keys.redraw` 앞):
  - `.split_right` · `.split_below`: `tree.split(focus, dir, whole)`이 null이면
    `pane> split refused`를 찍고 끝. 아니면 `applyLayout` → `spawnPane(새
    rect)` → `panes[new] = pane` → `focus = new`. 새 셸의 argv는 부팅의
    것과 같다(`shell_path` · `argv`).
  - `.close`: `pty.hangup(focus.session)` · `pane> hangup leaf=L pid=N`.
    닫지 않는다 — EOF 경로가 닫는다.
  - `.focus_next` · `.focus_prev`: `ws.focus = tree.next/prev(ws.focus)`.
  - 전부 `needs_redraw = true`. 루프 뒤에 `focus`를 다시 구한다 — M0은 poll
    직후 한 번만 구했다.
- EOF 경로의 `unreachable` 자리: `pane> closed leaf=L` · `pty.close` ·
  `screen.deinit` · `panes[L] = null` · 포커스가 그 잎이면 먼저
  `tree.next(L)`로 옮긴다 · `tree.remove(L)` · `applyLayout`. 그 패널의
  `Pane` 슬롯을 비운 뒤에는 그 바퀴에서 더 안 만진다(`continue`). 마지막
  패널이면 지금처럼 `break :main_loop`.
- `render`: `fb.fill` 한 번 → 구분선(`tree.separators` → `drawCellBackground`
  로 칸마다) → 워크스페이스의 모든 패널(`cells` · `images` · 층 셋 ·
  글리프, `paneOrigin(rect)` · `paneClip(rect)`) → 프롬프트(포커스 패널) →
  상태 줄 → `present` 한 번. 포커스 패널을 마지막에 그린다 — 그래야
  `cell_buf` · `img_buf`에 남은 것이 포커스 패널의 것이고 덤프 넷이 그것을
  읽는다. `focused`는 그리기 전에 `pane.screen.focused = (leaf == ws.focus)`로
  매 프레임 맞춘다(상태를 두 자리에 두지 않는다).
- `dumpPane(fb, ws, last: *PaneSig)`: 서명(`panes` · `focus` · `rect`)이
  바뀌었을 때만 `terminal: pane> ws=1/1 panes=N focus=L rect=C,R WxH sep
  ink=K`. `sep ink`는 프레임버퍼 전체에서 `SEPARATOR` 픽셀 수(`dumpStatus`가
  `STATUS_COPY`를 세는 것과 같은 모양). 첫 프레임에 한 번 찍힌다(부팅 →
  `panes=1 focus=0 rect=0,0 … sep ink=0`).

## Task 6: `pane/check.sh` · `check.sh`

- 빌드 머리 · `cleanup` · `report_failure` · `source ../gate_lib.sh`는
  `copy/check.sh`를 그대로 따른다. `MONITOR_PORT`는 열일곱 체인이 안 쓰는
  번호(`rg -n '^MONITOR_PORT=' */check.sh`로 고른다). QEMU에 `-nic none`.
- 헬퍼: `pane_value KEY`(마지막 `pane>` 줄의 값), `last_screen`(마지막
  `screen>` 줄), `spawn_lines`(`spawned child pid` 수), `key_lines`.
- 검사(design 결정 9의 1~6 · 9, 워크스페이스가 하나라 7 · 8은 M2):

| 검사 | 친다 | 본다 |
|---|---|---|
| 1 | 부팅, 프롬프트 대기 | `pane> ws=1/1 panes=1 focus=0` · `sep ink=0` |
| 2 | `meta_l-d` | `panes=2 focus=1` · `sep ink>0` · `rect=`의 col이 0보다 크다 |
| 3 | `echo right-side` Enter | `wait_for_screen 'right-side'` |
| 4 | `meta_l-bracket_left` | `focus=0` · `last_screen`에 `right-side`가 없다 · `key>` 수가 안 늘었다 |
| 4b | `echo left-side` Enter, `meta_l-bracket_right` | `focus=1` · `last_screen`에 `right-side`가 있고 `left-side`가 없다 |
| 4c | `meta_l-shift-c`, `meta_l-d`, `esc` | `pane>` 줄 수가 안 늘었다(copy mode가 삼켰다) · `panes=2` 그대로 |
| 5 | `meta_l-shift-d` | `panes=3 focus=2` · `rect=`의 row가 0보다 크다 |
| 6 | `meta_l-w` | `pane> hangup` · `child exited` 한 줄 · `pane> closed` · `panes=2` · `spawn_lines`가 1 그대로(terminal이 안 죽었다) |
| 9a | `meta_l-w` | `panes=1` · `sep ink=0` |
| 9b | `meta_l-w` | `child exited` 뒤 `spawn_lines`가 2(init이 되살렸다) · 새 `pane> … panes=1` |

- `check.sh`의 `CHAINS`에 `"WP-M1:./pane/check.sh"`를 끝에 더한다.
  진입 검사 셋(`require_build_steps` · `require_no_early_exit_pipe` ·
  `require_explicit_nic`)을 통과해야 한다 — 파이프 뒤 `grep -q`를 쓰지
  않는다(lessons 152행).

## Task 7: 게이트

- `zig build test`(컨테이너) 전부 초록. `input_test` · `vt_test`는 새 검사를
  더하기 전에 한 번 빨간 것을 보는 것이 좋다 — 음성 검사는 특히.
- `pane/check.sh` 한 번. 그다음 regression으로 terminal · render · copy ·
  hangul 각 한 번(하나씩).
- 반사실 하나: `applyLayout`에서 `pty.resize`를 빼고 pane 체인을 돌린다 —
  검사 3의 `right-side`가 틀린 폭으로 접혀 `last_screen`의 모양이 달라지거나
  셸이 155칸으로 프롬프트를 그려 오른쪽 패널 밖으로 넘친다. 어느 쪽이든
  어느 검사가 잡는지(또는 못 잡는지)를 적는다. 되돌리고 캐시를 컨테이너
  안에서 지운다.
- 루트 게이트 3/3(약 1시간 5분 예상 — 체인이 열여덟이 된다). 배경으로
  돌린다.

## Task 8: 문서

plan `Status:` · design `Status:` · `HANDOFF.md` 맨 위 표 · `lessons.md`
핵심 파일(`pty.zig`의 함수 셋 · 게이트 절에 `pane/check.sh`) ·
`docs/guides/running-tars.md`에 키 표.

## M1이 실측한 것

2026-10-03. Opus 서브에이전트가 구현했고 Fable이 diff · 로그를 대조했다.

1. `sep ink`는 셀 단위 값이다. 세로 구분선 하나가 47줄 × 128픽셀 = 6016,
   거기에 가로 구분선(77칸 × 128)이 더해지면 15872. design 결정 7의 예시
   752는 1픽셀 선을 짐작한 값이었다 — 구분선이 셀 한 칸이라는 결정 2와
   어긋난 숫자였고, 실측이 바로잡았다.
2. 반사실(`applyLayout`에서 `pty.resize`를 뺌)이 plan의 검사만으로는 통과했다
   (91초, 구멍). 셸이 155칸이라 믿어도 `echo`의 짧은 출력은 77칸 안에서
   똑같이 보인다. 그래서 판정 셋을 더했다 — fish의 `$COLUMNS`를 화면에
   찍게 한다: 검사 3 `right-side 77`(대조군, `spawnPane`이 처음부터 77로
   띄운다) · 4b `left-side 77`(분할로 줄어든 패널) · 9a 뒤 `whole 155`(닫기로
   커진 패널). 같은 반사실이 4b에서 `left-side 155`로 빨갰다. "크기를
   바꿨다"는 셀 수가 아니라 셸이 아는 폭으로만 증명된다.
3. `render`를 셋으로 갈랐다 — `renderBackdrop`(fill + 구분선) ·
   `renderPane` · `renderFinish`(프롬프트 + 상태 줄 + present). 포커스
   패널을 마지막에 그려야 `cell_buf` · `img_buf`가 그 패널의 것으로 남는데,
   프롬프트는 포커스 패널의 `cells()` 뒤에야 만들 수 있다(`defaultFg`).
   계산 순서와 그리기 순서가 엇갈려서 루프가 순서를 잡는다. `render> first
   frame`은 이제 다른 패널 그리기까지 포함하고, 그 값을 보는 판정은 없다.
4. 패널 명령 루프는 `keys.redraw` 뒤다(plan은 앞이라고 썼다). 포커스를
   옮기는 키가 조합 중인 한글을 확정시키고 `redraw`를 켜는데, 그때
   `setPreedit(null)`이 떠나는 패널에 가야 한다. 앞에 두면 새 패널에 가고
   떠난 패널에 조합 글자가 남는다.
5. Meta 분기의 Shift switch가 `else => null`이라 동작 하나가 바뀌었다 —
   `Cmd+Shift+←·→·Backspace`가 WP 전에는 Shift를 무시하고 `0x01` · `0x05` ·
   `0x15`였는데 이제 맨 키로 나간다. 보는 검사가 없었고 주석에 적었다.
   `else`에서 아래 표로 떨어지게 하면 원래대로지만 `Cmd+Shift+W`가 닫기가
   된다.
6. 닫은 뒤 포커스는 `tree.next(L)`이다. 잎 2(잎 1의 아래)를 닫으면 감겨서
   0으로 갔다(체인 검사 6의 `focus=0`). iTerm2는 자리를 넘겨받는 형제로
   간다 — 지우는 잎이 `second`면 `prev`, `first`면 `next`가 그 규칙이다. M2에서
   사용자가 고른다.
7. 음성 검사 61(copy mode 안의 `Cmd+D`)의 빨강은 고장을 "copy mode에서만
   패널 명령을 낸다"로 넣어야 보였다. 모드 구분 없이 넣으면 검사 60이 먼저
   걸려 61까지 안 간다.
8. ghostty `resize`는 `cell_size_px`가 null이면 `width_px` · `height_px`를
   안 건드리고(`Terminal.zig:3800`), cols · rows가 같으면 격자 작업을 건너뛰고
   픽셀만 적용한다(`:3815`). `vt_test` 79가 앞의 것을 본다.
9. 루트 게이트: 18체인 3/3 PASS, `FAIL` 0줄, 22:20:38 → 23:24:07(1시간 3분
   30초). pane 체인 한 회전 91초.

M2를 위해 남긴 자리:

- `current`는 `const usize = 0`. `dumpPane`은 `ws=current+1/전체`를 이미 센다.
- `PaneRef`가 `ws` 번호를 들어 포커스 없는 워크스페이스의 EOF도 그
  워크스페이스의 트리에서 지운다.
- 워크스페이스의 마지막 패널이 닫힐 때(`paneCount > 1`인데 그 ws의
  `count == 1`) 그 ws를 지우는 갈래가 없다 — 지금은 `remove` 뒤 빈 트리가
  남는다. M2의 `Cmd+T`가 이 자리를 연다.
- `input.Pane`에 워크스페이스 variant를 더하면 `main.zig`의 switch가 배선
  자리를 컴파일 에러로 알려 준다.
