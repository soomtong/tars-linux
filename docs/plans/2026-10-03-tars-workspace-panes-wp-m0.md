# WP-M0 — 구조: 패널 하나짜리 워크스페이스 하나

Date: 2026-10-03
Design: `docs/specs/2026-10-03-tars-workspace-panes-design.md`
Status: 구현과 검증이 끝났다(2026-10-03). 호스트 검사 일곱 · 체인 넷(terminal 60초 · render 67초 · copy 150초 · hangul 63초) · mutation 하나가 초록이고, `ink fg=383` · `caps ink off=87` · `copy ink=80`이 착수 전과 같다. 설계와 달리 한 것은 아래 "M0이 실측한 것" 절에 있다.

## 이 milestone이 끝나면

- `terminal/src/layout.zig`가 서고 `layout_test`가 호스트에서 돈다(결정 2).
  트리 · 사각형 · 순환 · 꽉 참 전부 이 milestone에서 검사한다 — 산수는
  부팅 없이 끝낼 수 있는 것이라 M1로 미룰 이유가 없다.
- `main.zig`에 `Pane` · `Workspace`가 생기고, 루프가 `focus` 패널을 거쳐
  돈다(결정 1). 부팅은 패널 하나 · 워크스페이스 하나이고 패널 명령은 아직
  없다.
- `render`와 덤프 넷이 패널의 `rect`를 받아 원점을 더한다(결정 6). 패널
  하나면 `rect`가 격자 전체라 산수 결과가 지금과 같다.
- `poll`의 fd 배열을 매 바퀴 짓는다(위험 1). 지금은 키보드 하나 + 패널 하나.
- 눈에 보이는 변화가 0이다. 기존 체인 넷(terminal · render · copy · hangul)이
  그대로 서고, `screen>` 줄이 바이트까지 같다.
- 새 로그 줄도 새 색도 없다. `pane>` 줄과 `SEPARATOR`는 M1이다.

## 착수 전에 확정한 것

1. `main.zig`에서 `screen`을 쓰는 자리는 루프 안이 전부이고, `session`은
   `pty.write`(키 · 답) · `readSome` · fd 셋이다. 전부 `focus.screen` ·
   `focus.session`으로 이름이 바뀔 뿐이다.
2. 덤프 중 프레임버퍼를 셀 좌표로 읽는 것은 넷 — `dumpStyles` · `dumpInk` ·
   `dumpImages` · `dumpPromptInk`. 전부 `GRID_X + col * CELL_W` 산수를
   자기 안에서 한다. 원점을 인자로 받게 바꾸는 것이 이 milestone의 유일한
   덤프 변경이고, 찍는 글자는 안 바뀐다.
3. `grid_clip`은 상수였다. 패널의 `rect`에서 계산하는 함수 하나로 바뀐다.
4. `pty.Session`에 `child_pid`가 있다. 닫기(waitpid)는 M1이지만 구조체는
   그대로 쓴다.
5. `vt_test`는 `vt.Screen.init`을 그대로 부른다. 이 milestone은 `vt.zig`를
   안 건드린다 — `resize` · `focused`는 M1이다.

## Task 1: `layout.zig` · `layout_test.zig`

- `Rect` · `Dir` · `Tree`(노드 풀 15 · `root`). `split` · `remove` · `rects`
  · `next` · `prev` · `count`.
- 사각형 산수: 구분선 한 칸을 빼고 `first = (n - 1) / 2`,
  `second = n - 1 - first`. 가를 수 없을 만큼 작으면(폭 또는 높이가 3 미만)
  `split`이 `null`.
- `layout_test`: 잎 하나의 `rects`가 격자 전체 · 오른쪽 분할 둘의 폭 합 + 1 =
  격자 폭 · 아래 분할 · 셋을 가른 뒤 가운데를 지우면 형제가 올라간다 ·
  여덟 뒤 아홉째는 `null` · `next`가 끝에서 처음으로 · `prev`가 처음에서
  끝으로.
- `build.zig`에 `layout_test` 실행 파일과 `test` step 등록 — `status_test`와
  같은 모양(ghostty 링크 없음).

## Task 2: `main.zig` — `Pane` · `Workspace` · 루프

- `Pane { screen, session, rect }`, `Workspace { tree: layout.Tree, panes:
  [8]?Pane, focus: u4 }`. 워크스페이스 배열 `[9]?Workspace`와 `current`.
  M0은 `[0]`에 하나만 만든다.
- 부팅: 지금 `pty.spawn` · `vt.Screen.init` 자리가 `spawnPane(rect)` 하나가
  된다 — M1이 분할에서 같은 함수를 부른다.
- 루프: `fds`를 매 바퀴 짓는다(키보드 + 모든 워크스페이스의 모든 패널).
  키 입력 분기 · copy 루프 · 프롬프트 · 상태 줄은 `focus`를 본다. PTY 분기는
  `revents`가 선 패널마다 `feed` · `takeReplies` · `scrollToBottom`을 한다 —
  포커스 아닌 패널도 읽는다(위험 1).
- EOF: `child exited (pty EOF)` 줄은 그대로 찍고, M0에서는 패널이 하나라
  지금처럼 루프를 나간다. "마지막 패널이면 나간다"의 조건을 여기서 세운다
  (`count == 1`) — M1이 그 앞에 "아니면 패널을 닫는다"를 넣는다.
- `render(fb, cache, panes...)`: 패널마다 `cells` · `images` · `clip` ·
  `rect`를 받아 원점을 더한다. `fb.fill`은 한 번, `present`도 한 번.
- 덤프 넷에 `rect` 인자.

## Task 3: 게이트

- `zig build test`(컨테이너) — `layout_test` 포함 전부 초록.
- `terminal/check.sh` · `render/check.sh` · `copy/check.sh` ·
  `hangul/check.sh` 각 한 번. 네 체인의 `screen>` · `ink` · `status>` 값이
  착수 전과 같다.
- mutation 하나: `render`의 원점에 `rect.col`을 안 더하게 박고 render 체인을
  돌린다 — 패널 하나면 `rect.col == 0`이라 통과해야 한다. 이것은 "M0이
  아무것도 안 바꿨다"의 확인이고, 원점 산수가 맞는지는 M1의 `sep ink`와
  `screen>` 음성 검사가 본다.
- 루트 게이트는 M0에서 안 돈다. 눈에 보이는 변화가 0이고 네 체인이 섰으면
  M1을 열고, 루트 게이트는 M1을 닫을 때 돈다.

## Task 4: 문서

plan `Status:` · `HANDOFF.md` 맨 위 절 · `docs/guides/lessons.md`의 핵심 파일
지도에 `layout.zig` 한 줄.

## M0이 실측한 것

2026-10-03. Opus 서브에이전트가 구현했고 Fable이 diff · 로그를 대조했다.

1. `Tree.split`이 `whole: Rect`를 더 받는다. "가르는 방향의 길이가 3 미만이면
   `null`"을 지키려면 잎의 크기가 필요한데 트리는 크기를 모른다. 155x47
   격자에서도 아래로만 다섯 번 가르면 47 → 23 → 11 → 5 → 2로 실제로 닿는
   경계다. design 결정 2의 코드 블록은 이 인자가 빠져 있었다.
2. 잎 번호(0..7)와 노드 번호(0..14)를 갈랐다. `Workspace.panes[8]`이 잎
   번호로 인덱싱되므로, 분할이 기존 패널의 번호를 안 바꿔야 포커스가 조용히
   다른 패널을 가리키지 않는다. `split`은 옛 잎 노드를 그 자리에서 내부
   노드로 바꾸고 잎 둘을 빈 노드로 내린다. `remove`는 형제의 내용을 부모
   노드에 덮는다. 지운 번호는 가장 작은 빈 번호로 다시 쓰인다.
3. 원점 산수는 `paneOrigin(rect)` 하나다. `render` · `drawPrompt` ·
   `drawImages` · `overBelowBg` · `dumpStyles` · `dumpInk` · `dumpImages`가
   전부 그것을 부르므로 그리는 쪽과 되읽는 쪽이 다른 원점을 볼 수 없다.
   `dumpPromptInk`는 셀 좌표가 아니라 `drawPrompt`가 돌려준 픽셀 범위를
   읽으므로 `rect`를 안 받는다. `Prompt`의 `rows` · `cols`는 `rect`가 됐다.
4. `Status.rows`는 격자 전체의 rows로 남았다 — 상태 줄은 패널이 아니라
   격자 아래 여백이다. PageUp · PageDown의 delta는 `focus.rect.rows`다.
5. `layout_test`는 첫 회에 초록이라 일부러 빨강을 봤다 — `b.col`의 구분선
   `+1`을 빼면 `right = 77,0 77x47, want 78,0`으로 잡힌다.
6. mutation(render 원점의 `rect.col`을 0으로 박음)은 예상대로 render 체인
   PASS였다. 패널 하나면 `rect.col == 0`이라 M0은 아무것도 안 바꿨다는
   확인이고, 원점 산수 자체는 M1의 `sep ink`와 `screen>` 음성 검사가 본다.
7. `zig fmt --check terminal/src`는 착수 전부터 여섯 파일이 빨갛다(ZU design
   실측 2의 fmt 차이). 새 파일 둘과 `build.zig`에만 돌렸고 `main.zig`의
   고친 hunk는 fmt 출력과 같다.
8. 체인 넷을 겹쳐 돌리지 않았다. 각 체인이 kernel · init · terminal · initrd를
   같은 디렉터리에 다시 빌드하므로 한 체인의 QEMU가 읽는 initrd를 다른
   체인이 다시 쓸 수 있다 — CPU 포화보다 이쪽이 먼저다.

M1을 위해 남긴 자리:

- `spawnPane(io, alloc, path, argv, rect) !Pane`. `spawned child pid` 줄은
  이 함수 밖(부팅 호출부)이라 분할 때 찍을지는 M1이 정한다 —
  `terminal/check.sh`가 그 줄의 개수를 센다.
- EOF 경로의 `if (paneCount == 1) break :main_loop;` 뒤 `unreachable`이
  닫기(waitpid · `tree.remove`)의 자리다.
- `render`는 아직 포커스 패널의 `cells` 하나를 받는다. 패널마다 도는 모양은
  M1이 만든다 — `fb.fill` 한 번, 패널마다 셀 · 이미지 · clip, `present`
  한 번.
- `focus`를 poll 직후 한 번 구한다. 패널 명령이 포커스를 바꾸면 렌더 앞에서
  다시 구해야 한다.
- `current`는 `const`다. M2에서 `var`가 된다.
