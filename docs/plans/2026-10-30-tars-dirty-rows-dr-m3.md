# DR-M3 — 행 dirty 비트로 `cells()`를 줄인다

Date: 2026-10-30
Design: `docs/specs/2026-10-28-tars-dirty-rows-design.md`(결정 10~12, 배경 절의 ghostty 1층)
Status: 진행 중. Task 0(프로브)부터.

## 이 milestone이 끝나면

- `cells()`가 매 프레임 `cols × rows` 전부를 색으로 풀지 않는다. 라이브러리가 켠 행 dirty 비트(`RenderState.dirty` ·
  `row_data`의 `Row.dirty`)와 우리 층 넷의 메모 비교로 dirty 행을 정하고, dirty 아닌 행은 지난 목록(`Pane.cells_buf[shown]`)에서
  run째 복사한다. 비트는 `cells()`의 끝에서 끈다(design 결정 10 · 12).
- 호스트 `dirty_test`가 회차마다 증분 목록과 fresh 목록(비트 없이 처음부터)을 바이트로 비교한다 — ghostty의
  `testIncrementalMatchesFresh`의 둘째 절반이다(결정 11). M2까지의 행 비교 정답지 검사는 그대로 남는다.
- 게스트 verify가 그림자를 fresh `cells()`로 그리고(픽셀 비교가 낡은 행을 보게 된다), 그 fresh 목록을 증분 목록과 행마다 비교해
  `terminal: verify> mismatch cells …`를 낸다. 루트 게이트 22체인의 모든 프레임이 `ok`다.
- 같은 프로브(`probe/patch.pl` + `probe/split.pl`)로 (a) frame을 다시 재서 M2의 1.36ms · cells 0.63ms와 비교한다.
- `vt_test`는 0줄 바뀐다(fresh 경로가 `cells(out)` 그대로다).

## 착수 전에 확정한 것

HEAD `81ff52a`에서 코드로 확인했다. 라이브러리 줄 번호는 빌드 입력 판(`terminal/ghostty-src`, `3d07ef9`)의 `src/terminal/render.zig`다
— design 배경 절은 참고 판(`_study/ghostty`)의 번호라 다르다. 두 판에서 아래 사실은 같다.

1. 라이브러리 쪽 사실 여섯.
   - `update`는 이미 증분이다. page 행의 `page_row.dirty`를 `update`가 소비하고(`:819-836`, `redraw`나 page dirty가 아니면 켜진 행만
     `builder.row`) 다시 지은 행의 `row_data` dirty 칸을 켠다(`:1427`, `b.dirties[vy] = true`).
   - `RenderState.dirty`는 `redraw`면 `.full`, 행 하나라도 다시 지었고 `.false`였으면 `.partial`(`:948-957`). `.false`로 되돌리는 자리는
     `clean()`뿐이다(`:1033-1038` — `dirty = .false` + `row_data` dirty 전부 false). 우리는 한 번도 안 불렀다 — 그래서 지금은 첫
     프레임 뒤로 늘 `.full`이고 모든 행이 dirty다. 빈 상태(`.empty`)는 `.false`이고 첫 `update`는 크기가 달라 `redraw` → `.full`.
   - `redraw`의 기준 여섯(`:553-596`): 활성 화면 키(alt screen), 터미널 전역 dirty(팔레트 · OSC 색 · reverse), 화면 전역 dirty, 행 ·
     열 수, overscan, viewport pin(스크롤). 우리 `state`는 overscan을 안 쓰므로 `row_data[y]`가 곧 뷰포트 y행이다 — `cells()`가
     지금도 그렇게 읽는다.
   - 선택이 바뀐 행은 라이브러리가 dirty로 켠다(`:914-928`, `dirty.* = true`).
   - 커서 이동은 행을 안 더럽힌다 — "We do this even if rows are not dirty because the cursor is unrelated"(`:739-741`). 커서는
     `state.cursor`에 따로 있다.
   - `Row.dirty`의 계약은 주석 그대로다(`:318-321`): "A dirty flag that can be used by the renderer to track its own draw state.
     `update` will mark this true whenever this row is changed, too." 끄는 쪽은 렌더러다. 참고 판의 렌더러도 행마다 `dirty.* = false`
     하고 다시 짓는다(`generic.zig:2736-2740`).
2. `cells()`(`vt.zig:648-885`)의 순서는 `state.update` → `findSpans` → `shell_cursor` 계산 → 행 × 열 루프다. 루프 안의 층은
   순서대로 style(fg · bg · inverse) → 매치 하이라이트(`row_spans`) → 선택(`row_sels`) → copy 커서 반전 / preedit 치환 + 셸 커서
   반전(`invert_cursor` · `span`) → spacer 상속 → `cp == 0 and bg == default_bg` 건너뛰기다. 이 가운데 라이브러리의 `row_data`에
   없는 입력은 넷이다 — `hl_spans`, `copy_cursor`, `preedit`, `invert_cursor`(= `shell_cursor != null and shape == .block`, 곧
   `focused` · copy mode 아님 · 뷰포트 안 · 모양)와 커서 위치 `cursor`(`state.cursor.viewport`). 이 넷이 design 결정 12의 층이다.
   preedit은 반전과 무관하게 `cursor` 자리의 `cp`를 바꾸므로(`:807`) 반전이 꺼져 있어도 커서 자리가 층에 든다.
3. 새 API. `cells(out)`은 그대로 두고 fresh 경로가 된다 — `cellsReuse(out, null)`을 부른다. 새 `cellsReuse(self, out: []CellGlyph,
   prev: ?Prev) ![]CellGlyph`, `pub const Prev = struct { cells: []const CellGlyph, starts: []const u32 }`. `prev`가 null이거나
   `prev.starts.len != state.rows + 1`이거나 `state.dirty == .full`이면 모든 행이 dirty다. 아니면 행마다 `row_data` dirty 칸 ∪ 층의
   행(확정 4). 루프는 행마다 갈린다 — dirty 아닌 행은 `prev.cells[prev.starts[r]..prev.starts[r + 1]]`을 `out[n..]`에 `@memcpy`
   (그 run의 `row`는 이미 r이다), dirty 행은 지금의 열 루프 그대로. 끝에서 `state.clean()`과 메모 갱신. `pub last_reused: u16`에
   복사한 행 수를 남긴다 — 호스트 검사와 Task 3의 프로브가 읽는다. `vt_test` 예순 곳은 `cells(out)` 그대로라 0줄이다.
4. 층의 메모(`Screen.drawn`, design 결정 12). 지난 `cells()`가 본 값 — `cursor: ?struct { x, y: u16, span: u8 }`(반전하거나 preedit이
   있을 때의 커서 자리와 폭. 둘 다 아니면 null), `preedit: ?u21`, `copy: ?Cursor`, `spans: ArrayListUnmanaged(RowSpan)`(지난 `hl_spans`의
   사본 — `hl_spans`는 매 호출 `clearRetainingCapacity`로 다시 짓고 `hlSpans()`가 게이트에 이번 값을 내보내므로 맞바꾸지 않고
   복사한다. 검색 중에만 비어 있지 않다). dirty에 더하는 행: 커서 셋(`cursor` · `preedit` · `copy`) 가운데 하나라도 다르면 지난 값의
   행과 이번 값의 행 둘 다. spans는 두 목록이 행 오름차순(`RowSpan.lessThan`)이므로 두 포인터로 행마다 걸어, 같은 행의 부분 목록이
   길이나 값이 다르면 그 행(한쪽에만 있는 행 포함). 행 번호가 `state.rows` 이상이면 건너뛴다(크기가 줄어든 뒤의 옛 메모 — 그
   프레임은 어차피 `.full`이다). 메모는 증분 호출이든 fresh 호출이든 끝에서 같은 값으로 적는다 — 그래서 한 프레임에 두 번 불러도
   둘째 호출이 첫째의 답을 바꾸지 않는다(결정 12의 호출 계약).
5. `main.zig`의 배선. `render`의 두 호출(`:4210` · `:4217`)이 `cellsReuse(p.cells_buf[p.shown ^ 1], if (p.prev_valid) .{ .cells =
   p.cells_buf[p.shown][0..p.shown_len], .starts = p.starts_buf[p.shown] } else null)`이 된다. `prev_valid`가 거짓인 자리(막 띄움 ·
   `applyLayout` · 지난 목록이 행 순서가 아님)는 그대로이고, 그때 라이브러리도 크기 변경으로 `.full`이라 두 겹으로 안전하다.
   `paintPane`은 0줄 — `rowStarts` · `dirtyRows` · overlay 행 · clip이 그대로 증분 목록 위에서 돈다. 비현재 워크스페이스의 패널은
   `cells()`가 안 불리는 동안 라이브러리 플래그가 쌓이므로(확정 1) 돌아왔을 때의 첫 증분 호출이 맞다 — 그 프레임은 `full`이라
   `paintPane`이 통째로 그리지만 목록은 증분으로 짓는다(값은 같아야 하고 verify가 본다).
6. verify(`verifyFrame`, `:4416`)의 둘. (가) 포커스 패널도 `cells(v.cell_buf)`(fresh)로 다시 받아 그림자에 그린다 — 지금은
   `frame.cells`를 그대로 써서 증분 목록이 낡아도 픽셀이 같아져 못 본다. 포커스 아닌 패널은 이미 fresh 재호출이다. (나) 패널마다 fresh
   목록을 그 패널의 증분 목록(`p.cells_buf[p.shown][0..p.shown_len]` — `paintPane`이 뒤집은 뒤라 이번 목록이다)과 `verify.rowStarts` +
   `dirtyRows`로 비교한다. `Verify`에 `starts_buf: []u32`(격자 행 + 1)를 더한다. 다른 행이 하나라도 있으면 그 프레임의 줄은
   `terminal: verify> mismatch cells rows=<n> first=<r>,… us=<N>`이고 픽셀 · clip보다 먼저다(원인에 가장 가까운 말). `ok` 줄은
   그대로라 루트 게이트의 regex(`VERIFY_OK_LINE`)는 안 바뀐다. 호출 순서는 증분(실제 경로) → fresh(그림자)라 결정 12의 계약대로다.
   `dumpHighlight`가 읽는 `hl_stats.us`는 둘째 호출의 값이 된다 — 측정값이라 뜻이 안 바뀐다.
7. 호스트 검사(`dirty_test.zig`). 회차마다 `cellsReuse(&bufs[next], prev)`로 증분 목록을 받고, 바로 `cells(&fresh)`로 fresh 목록을
   받아 `std.mem.sliceAsBytes`로 비교한다 — 다르면 seed · 회차 · 조작 이름 · 첫 다른 행을 찍는다. M2의 정답지 검사(`rowEql`)는 증분
   목록 위에서 그대로 돈다. load-bearing 조건 둘을 더한다 — `last_reused`의 합이 0이면 실패(한 번도 재사용을 안 했다 = 검사가 증분
   경로를 안 봤다), 그리고 조작 목록에 커서만 움직이는 것(CUP · DECSCUSR 모양 · DECTCEM 숨김은 이미 있다)이 있어 "내용은 같고 층만
   바뀐 행"이 나온다. 300회차 · seed는 M2 그대로.
8. mutation 둘. (호스트) 확정 4의 커서 행 더하기를 뺀 판 — `dirty_test`가 CUP 회차에서 fresh 비교로 실패해야 한다(커서 자리의
   반전이 지난 자리에 남는다). (게스트) spans 비교를 뺀 판 — copy 체인의 `n`(현재 매치 이동, `copy/check.sh:840`)에서 내용은 그대로이고
   `current` 색만 바뀌므로 `mismatch cells`여야 한다. `make check CHAIN=copy` 한 판. 둘 다 잡히지 않으면 왜인지 먼저 읽는다(M2 plan
   결과 절 — mutation은 가려질 수 있다).
9. 프로브. Task 0의 진단은 `probe/cells.pl`(새) — `vt.zig`를 패치해 `cells()` 안을 `update` · `spans`(`findSpans`) · `loop`(루프, 끝의
   `return` 앞)로 쪼개 `terminal: cells> update=<us> spans=<us> loop=<us>` 한 줄을 찍는다(`vt.zig`는 `logline`을 이미 import한다, `io`
   필드가 있다). anchor는 `try self.state.update(self.alloc, &self.term);` · `try self.findSpans();` · 함수 끝 `return out[0..n];`(뒤의
   `askedShape` 주석까지 넣어 한 번). `report.pl`이 `cells>` 줄을 `split>`처럼 다음 `probe>` 프레임에 붙여 (a)의 중앙값을 낸다 —
   `cells>` 없는 로그의 출력은 바이트까지 그대로다. 컨테이너에는 `main.zig`(patch + split)와 `vt.zig` 둘을 마운트한다. Task 3의
   재측정은 `split.pl`의 anchor 하나를 고친다 — `frame.cells = try focus.screen.cells(focus.cells_buf[focus.shown ^ 1]);`가 확정 5의
   `cellsReuse` 줄이 된다. `patch.pl`의 anchor 넷은 안 건드린다.
10. Task 0의 판단 규칙 — 숫자를 보기 전에 정한다. (a)에서 `loop`의 중앙값이 `cells`(split> 줄)의 70% 이상이면 M3을 그대로 간다.
    `update`가 50% 이상이면 M3이 줄일 몫이 작다(라이브러리 안의 비용은 판을 올려야 줄고 이 milestone의 범위 밖) — 멈추고 사용자에게
    숫자와 함께 묻는다. 그 사이면 가되 상한을 결과 절에 적는다. 재사용 행의 복사(패널 가득 찬 화면에서 약 110KB `memcpy`)는 `loop`에
    남는 비용이라 0이 되지는 않는다.
11. Task 3의 판단은 M2와 같은 프로브 · 부팅 3회 · 중앙값이고, 기준은 M2의 frame 1.36ms · cells 0.63ms다. 다음 단계 제안 규칙은 두지
    않는다 — 남는 구간(present 0.32 · overlay 0.20 · 행 칠하기 0.14)은 각각 커널 · 상태 줄 · 글리프라 다른 축이고, 그 뒤는 GPU 가속이다
    (design "안 하는 것").

## Task 0: `cells()` 안을 쪼갠다 (코드 0줄)

- `probe/cells.pl`(확정 9), `probe/report.pl`의 `cells>` 집계. 호스트에서 패치가 붙는지, 0.17 `ast-check`로 구문이 맞는지, 옛 로그로
  `report.pl` 출력이 안 바뀌는지(`cmp`) 본다.
- 진단 판 3회(label `dr-m3-split`). 부팅마다 terminal이 다시 컴파일되므로 3회에 8분쯤이다.
- 결과 절에 표와 확정 10의 판단. commit 하나(프로브 스크립트 둘 + plan).

## Task 1: `cellsReuse`와 호스트 검사

- `terminal/src/vt.zig`: `Prev` · `cellsReuse` · `drawn` 메모 · `last_reused`(확정 3 · 4). `cells(out)`은 `cellsReuse(out, null)`.
  `deinit`이 `drawn.spans`를 놓는다.
- `terminal/src/dirty_test.zig`: fresh 비교와 load-bearing 조건(확정 7). 호스트 mutation(확정 8)을 돌리고 결과 절에 적는다.
- 호스트 0.17로 `fmt --check` · `ast-check`(lessons "범용 명령"), 컨테이너에서 `zig build test`(`vt_test` · `dirty_test` · `verify_test`).
- commit 하나.

## Task 2: 배선과 verify

- `terminal/src/main.zig`: `render`의 두 호출(확정 5), `verifyFrame`의 fresh 재호출과 `mismatch cells`(확정 6), `Verify.starts_buf`.
  `verifyFrame` 머리 주석의 "포커스 패널은 `frame.cells`를 그대로 쓴다" 문단을 고친다.
- `probe/split.pl`의 anchor 하나(확정 9).
- 게스트 mutation(확정 8)으로 `make check CHAIN=copy`, 되돌린 뒤 `copy` · `render` · `hangul` · `pane` 체인을 돈다.
- commit 하나.

## Task 3: 측정 · 루트 게이트 · 닫기

- 비교 판 + 진단 판 각 3회(확정 11). 결과 절에 M2와 나란히.
- 루트 게이트(`RUNS` 기본, 약 10분). `verify lines`가 회차마다 찍히고 전부 `ok`.
- 닫기: design 표 DR-M3 행 · Status, `completed.md`의 DR 행에 M3 덧붙임, `measurements.md` 97, `docs/decisions/project_dirty_rows.md`
  (결정 10~12의 함정과 숫자) + `MEMORY.md` 한 줄, `HANDOFF.md`, 소개 페이지(`gh-pages` `data.js`)의 DR 줄 숫자. 이 plan Status.
- commit 하나.
