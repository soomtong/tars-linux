# WP-M2 — 워크스페이스

Date: 2026-10-03
Design: `docs/specs/2026-10-03-tars-workspace-panes-design.md`
Status: 끝났다(2026-10-04). 호스트 검사 다섯이 새로 섰고, `pane/check.sh`가 검사 열여섯이 됐으며, 루트 게이트 18체인 3/3 PASS(1시간 4분 30초). 값은 아래 "M2가 실측한 것" 절에 있다.

## 이 milestone이 끝나면

- `Cmd+T`가 새 워크스페이스를 끝에 만들고(패널 하나, 격자 전체) 그리로
  간다. 아홉이 차 있으면 `pane> workspace refused`를 찍고 아무 일도 안
  한다(design "모델" 절).
- `Cmd+1`~`Cmd+9`가 그 번호의 워크스페이스로 간다. 없는 번호면 아무 일도
  안 하고 로그도 안 찍는다 — 게이트가 `pane>` 줄 수로 그것을 본다.
- 워크스페이스의 마지막 패널이 닫히면(EOF) 그 워크스페이스가 사라지고 뒤의
  것들이 한 자리씩 앞으로 온다(번호는 자리다). 전체의 마지막 패널이면
  M1처럼 terminal이 끝난다.
- 상태 줄 꼬리에 `  W2` 칸이 붙는다 — 워크스페이스가 둘 이상일 때만, `COPY`
  앞에, 색은 `STATUS_FG`(결정 8). 하나뿐이면 글자도 픽셀도 M1과 같다.
- 패널을 닫은 뒤 포커스가 자리를 넘겨받는 형제로 간다(M1 실측 6, 사용자가
  2026-10-03에 골랐다). 잎이 `second`면 `prev`, `first`면 `next`.
- `pane/check.sh`에 검사 7 · 8이 붙고 검사 6의 기대값이 `focus=1`이 된다.
  루트 게이트 3/3. 서브프로젝트 WP가 닫힌다(M3은 사용자가 따로 연다).

## 착수 전에 확정한 것

1. `drawStatus`는 꼬리에서 `CAPS`의 시작을 센다(`main.zig:261-264`) —
   `tail_len = copy ? COPY_TAIL.len : 0`. 워크스페이스 칸이 `CAPS`와
   `COPY` 사이에 서므로 꼬리가 둘이 된다: `… CAPS[  W2][  COPY]`. `caps_at =
   len - copy_tail - ws_tail - CAPS.len`이고, 색은 넷 — 앞 세 칸 `STATUS_FG`
   · `CAPS` 켜짐/꺼짐 · `W2` `STATUS_FG` · `COPY` `STATUS_COPY`.
2. `dumpStatus`는 `text`와 `caps`가 바뀔 때만 찍는다. `W2`는 글자가 생기고
   사라지므로 메모를 넓힐 일이 없다(CI 결정 6과 같은 이유).
3. hangul 체인의 `status>` 판정은 전부 워크스페이스 하나에서다. `W` 칸이
   둘 이상일 때만 뜨므로 기대값이 안 바뀐다.
4. `PaneRef.ws`는 `fd_panes`를 지은 바퀴 안에서만 유효하다. 워크스페이스를
   지워 배열이 당겨지면 같은 바퀴의 뒤 항목이 낡는다 — 지운 직후 PTY 루프를
   `break`한다. 안 읽은 출력은 다음 `poll`이 다시 알린다.
5. `Cmd+1`~`9`는 evdev `KEY_1`~`KEY_9`(물리 자리)다. `KEY_1`은 `KEY_2`-1이
   아니다 — `input-event-codes.h`에서 `KEY_1`=2 … `KEY_9`=10으로 연속이지만
   `KEY_0`=11이다. 아홉만 쓰므로 `code - KEY_1`로 번호를 센다.
6. `Cmd+T`는 Meta 분기의 비-Shift 표에 든다. `Cmd+Shift+T`는 표에 없어
   null이다(M1 실측 5의 모양 그대로).

## Task 1: `layout.zig` · `layout_test.zig`

- `pub fn heir(self: *const Tree, leaf: u4) u4` — 그 잎을 지우면 자리를
  넘겨받는 쪽의 잎. 잎이 부모의 `second`면 `prev(leaf)`, `first`면
  `next(leaf)`, 부모가 없으면 `leaf`.
- `layout_test`: 0을 오른쪽으로 갈라 1, 1을 아래로 갈라 2 → `heir(2) == 1` ·
  `heir(1) == 2` · `heir(0) == 1` · 잎 하나면 `heir(0) == 0`.

## Task 2: `input.zig` · `input_test.zig`

- `Pane` enum에 `new_workspace` · `workspace_1` … `workspace_9`. 아홉을
  variant로 적는 이유는 결정 4(payload를 두면 `std.meta.eql`이 필요하다).
- `chord` Meta 비-Shift 표에 `KEY_T => .new_workspace`, `KEY_1 … KEY_9 =>
  .workspace_N`. 아홉 줄을 손으로 적는다 — `inline` 트릭보다 읽히는 쪽.
- `input_test`: `Cmd+T` · `Cmd+1` · `Cmd+9` 양성 · `Cmd+0`이 `nothing`(표에
  없다) · copy mode 안의 `Cmd+T`가 `nothing`.

## Task 3: `status.zig` · `status_test.zig`

- `pub const WS_PREFIX = "W"`, `pub const WS_TAIL_LEN = GAP.len + 2`
  (`W` + 숫자 한 자리). `MAX_LEN`에 더한다.
- `statusText(state, copy, workspace: ?u8, buf)`. `workspace`가 있으면 `CAPS`
  뒤 · `COPY_TAIL` 앞에 `GAP ++ "W" ++ 숫자`. 1~9만 온다 — 두 자리는 안
  만든다(`MAX_WORKSPACES = 9`).
- `status_test`: `workspace=2, copy=true` → `…CAPS  W2  COPY`(순서) · `null`이면
  `W`가 없다 · 검사 10(가장 긴 줄 = `MAX_LEN`)을 `workspace=9, copy=true`로.
  기존 호출은 `null`.

## Task 4: `main.zig`

- `current`를 `var`로. `workspaceCount(workspaces)`.
- `Status.workspace: ?u8`. `drawStatus`의 꼬리 산수(확정 1). `statusText`
  호출에 `if (count > 1) current + 1 else null`.
- 패널 명령 루프:
  - `.new_workspace`: `count == 9`면 `pane> workspace refused`. 아니면
    `workspaces[count] = { Tree.init(), panes = null, focus = 0 }` ·
    `panes[0] = spawnPane(whole)` · `current = count`.
  - `.workspace_N`: `N-1 < count and N-1 != current`면 `current = N-1`.
    아니면 아무것도 안 한다(로그 없음).
  - 루프 뒤에 `ws` · `focus`를 다시 구한다(M1이 이미 그렇게 한다).
- EOF 경로: `w.focus = w.tree.heir(ref.leaf)`(next 대신). `remove` 뒤
  `w.tree.count() == 0`이면 워크스페이스를 지운다 — `workspaces[ref.ws..]`를
  한 칸 당기고 끝을 null, `current`를 맞춘다(`current == ref.ws`면
  `min(ref.ws, count-1)`, `current > ref.ws`면 `-1`). 그리고 PTY 루프를
  `break`(확정 4). `pane> workspace closed ws=N`을 찍는다.
- `dumpPane`의 서명에 `current`를 더한다 — 지금은 `panes` · `focus` · `rect`
  뿐이라 `Cmd+1`로 같은 모양의 워크스페이스로 옮기면 줄이 안 찍힌다.

## Task 5: `pane/check.sh`

- 검사 6: `focus=0` → `focus=1`(형제). 주석에 이유.
- 검사 9b 뒤(되살아난 terminal, 패널 하나)에 붙인다:

| 검사 | 친다 | 본다 |
|---|---|---|
| 7 | `meta_l-t` | `pane> ws=2/2 panes=1` · `status>`의 `text=`가 `  W2`로 끝나고 `COPY`가 없다 · `spawn_lines` 그대로 |
| 7a | `echo ws-two` Enter | `wait_for_screen 'ws-two'` |
| 7b(음성) | `meta_l-5` | `pane>` 줄 수 · `key>` 줄 수가 안 는다 |
| 8 | `meta_l-1` | `ws=1/2` · `text=`가 `  W1`로 끝난다 · `last_screen`에 `ws-two`가 없다 |
| 8a | `meta_l-2` | `ws=2/2` · `last_screen`에 `ws-two`가 있다 |
| 8b | `meta_l-w` | `pane> workspace closed ws=2` · `ws=1/1 panes=1` · `text=`에 `W`가 없다 · `spawn_lines` 그대로(terminal이 산다) |

- `status>` 판정 헬퍼는 `copy/check.sh`의 `status_text`를 그대로 가져온다.

## Task 6: 게이트

- `zig build test` — `status_test` 검사 10이 먼저 빨갛다(`MAX_LEN`이 늘었다).
  음성 검사(`Cmd+0` · copy mode의 `Cmd+T`)는 빨강을 먼저 본다.
- `pane/check.sh` 한 번 → hangul · copy · terminal · render 각 한 번(하나씩).
- 반사실 하나: EOF 경로에서 워크스페이스를 지우는 갈래를 빼고 pane 체인 —
  검사 8b가 `ws=1/1`을 못 보고 빨갛다(빈 트리의 워크스페이스가 남는다).
  되돌리고 캐시를 컨테이너 안에서 지운다.
- 루트 게이트 3/3(배경, 약 1시간 5분).

## Task 7: 문서(lead가 한다)

plan · design `Status: 끝났다` · `docs/decisions/project_workspace_panes.md` ·
`MEMORY.md` 한 줄 · `CLAUDE.md` 완료 표 · `HANDOFF.md` · `running-tars.md`
키 표에 `Cmd+T` · `Cmd+1~9` · `lessons.md` 게이트 절.

## M2가 실측한 것

2026-10-04. Opus 서브에이전트가 구현했고 Fable이 diff · 로그를 대조했다.

1. 반사실 1(워크스페이스를 지우는 갈래를 끔)은 plan이 예상한 자리(8b의
   `ws=1/1`)가 아니라 그 앞에서 잡혔다 — `FAIL: no 'pane> workspace closed
   ws=2' line`. 빈 트리의 워크스페이스가 남아 렌더 앞 `ws.panes[ws.focus].?`
   에서 terminal이 죽었고, init이 되살린 새 terminal이 `ws=1/1 panes=1`을
   찍어 `wait_for_pane`은 통과했다. "terminal이 살았다"는 `pane>` 줄로
   보면 안 되고 `spawned child pid` 수로 본다(lessons에 적었다).
2. 반사실 2(`drawStatus`의 `ws_len = 0`)는 글자가 맞고 색만 밀리는 고장이다
   (CI 위험 2와 같은 병). 검사 7의 `caps ink off=` 판정이 `off=49`로
   잡았다 — 49는 `W2` 두 글자의 픽셀이고, 정상은 워크스페이스 하나일 때와
   같은 87이다. 이 판정은 반사실을 보고 더한 것이다.
3. `PaneSig`에 `current`뿐 아니라 `total`도 들어갔다. 1번에 있는데 2번이
   닫히면 `ws=1/2`가 `ws=1/1`이 되는데 `current`만 보면 그 줄이 안 찍힌다.
4. 루프의 `ws`가 `var`가 됐고, 워크스페이스를 바꾸는 명령 직후와 렌더
   앞에서 `ws` · `focus`를 함께 다시 구한다. 같은 read에 실려 온 `Cmd+T` 뒤
   `Cmd+D`가 새 워크스페이스에 가야 한다.
5. 검사 6이 `focus=1 rect=78,0`(형제)이 되면서 검사 9a가 닫는 잎이 1이
   됐고, 남는 잎 0은 155 → 77 → 155칸을 지나므로 `whole 155` 판정이
   여전히 `TIOCSWINSZ`를 본다.
6. `statusText`는 1~9 밖의 번호에 `?`를 쓴다. 칸 길이가 늘 셋이어야
   `drawStatus`의 꼬리 산수가 서기 때문이고, 지금은 닿는 길이 없다.
7. evdev `KEY_1`=2 … `KEY_9`=10, `KEY_0`=11, `KEY_T`=20을 `input_test`의
   고장 주입에서 실측했다(`code=11 got pane .workspace_9` ·
   `code=20 got pane .new_workspace`).
8. `MAX_LEN`이 42에서 46이 됐다. 손으로 늘린 버퍼는 없다(IS 결정 5의 못이
   세 번째로 값을 했다).
9. 루트 게이트: 18체인 3/3 PASS, `FAIL` 0줄, 00:07:06 → 01:11:30(1시간
   4분 30초). pane 체인 한 회전 99초.
