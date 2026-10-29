# DR-M2 — 행 단위 부분 갱신과 clip

Date: 2026-10-29
Design: `docs/specs/2026-10-28-tars-dirty-rows-design.md`(결정 2~6 · 9, 위험 3 · 4 · 5)
Status: plan(2026-10-29, HEAD `f107e5f`). 착수 전.

## 이 milestone이 끝나면

- 프레임마다 패널 전체를 다시 칠하지 않는다. 패널마다 지난 프레임의 `cells()` 목록과 이번 목록을 행마다 비교해, 달라진 행만
  지우고 다시 칠한다(design 결정 2 · 5). 통째로 다시 그리는 것은 첫 프레임 · 워크스페이스 전환 · 트리 변경 · 이미지가 있는
  패널뿐이다(결정 3).
- 다시 칠한 사각형이 DIRTYFB의 clip으로 간다(결정 6). 화살표만 고치는 바퀴도 화살표의 옛 자리와 새 자리 둘을 clip으로 넘긴다.
- 루트 게이트 22체인의 모든 프레임이 `terminal: verify> ok`다 — DR-M1이 세운 기준(세 회차 약 2만 3천 프레임, `mismatch` 0)을
  부분 경로가 그대로 받는다. verify는 clip도 본다(아래 확정 9).
- 행 비교는 `verify.zig`의 순수 함수이고 호스트에서 ghostty식 무작위 검사(`dirty_test`)가 돈다(결정 9).
- 같은 프로브로 (a) frame을 다시 재서 DR-M0의 2.45ms와 비교하고, `cells()`의 몫으로 M3(행 dirty 비트)을 다시 판단한다.
- `verifyFrame`의 그림자 경로는 손대지 않는다 — `renderBackdrop` · `renderPane` · `renderOverlay`의 모양이 그대로이므로
  "통째 경로"의 정의가 M1과 같다.

## 착수 전에 확정한 것

HEAD `f107e5f`에서 코드로, 커널 6.18.42 소스로 확인했다.

1. 지우는 색은 `MARGIN_COLOR`다 — design 결정 5의 "기본 배경"이 아니다. 통째 경로에서 빈 칸은 `fill(MARGIN_COLOR)`의 색으로
   남는다: `cells()`가 `cp == 0 and bg == default_bg`인 셀을 안 내보내고(`vt.zig:874`) `renderPane`은 내보낸 셀만 칠하기 때문이다.
   verify의 정답이 그 경로이므로 부분 경로도 같은 색으로 지워야 한다. 지금은 `default_bg`도 `0x102030`이라 둘이 같지만, OSC 11로
   기본 배경이 바뀌어도 통째 경로의 빈 칸은 여전히 `MARGIN_COLOR`다 — 그래서 결정 3의 "기본 배경색이 바뀜 → 통째" 조건은 필요
   없다(내보낸 셀의 `bg` 값이 바뀌어 행이 저절로 dirty다). design 결정 3 · 5에 이 확정을 한 줄씩 단다.
2. 행 하나를 다시 칠하는 사각형은 패널 폭 + 오른쪽 한 칸이다. 마지막 열의 preedit(폭 2)은 오른쪽 절반을 격자 밖에 그리고
   (`vt.zig`의 "커서가 마지막 열이면" 주석, `drawPrompt`의 조합 글자도 `drawGlyph`가 경계를 안 본다), 통째 경로는 다음 프레임의
   `fill`이 그것을 지운다. 부분 경로는 그 행을 다시 칠할 때 패널 오른쪽 한 칸(8 × 16)을 함께 되돌린다 — 그 칸은 트리의 타일링상
   언제나 구분선(세로 분할의 `first` 쪽)이거나 여백(격자 오른쪽 끝)이다: `rect.col + rect.cols == whole.cols`면 `MARGIN_COLOR`,
   아니면 `SEPARATOR`. 이 주장이 틀리면 패널을 가른 모든 프레임에서 verify가 `mismatch`를 낸다(pane 체인이 매 프레임 그 칸을 칠한다).
   오른쪽 여백은 `GRID_X` 20픽셀이라 한 칸이 들어가지만 `fillRect`가 경계를 안 보므로 `x + CELL_W <= fb.width`를 검사한다.
   왼쪽 · 위아래로 새는 글리프는 없다고 전제한다(design 결정 5) — 생기면 verify가 잡는다.
3. 통째로 다시 그리는 판정은 플래그가 아니라 상태 비교다(결정 2의 정신). `App`에 `last_current: ?usize` · `last_tree: ?layout.Tree`를
   두고, 프레임마다 `self.current`와 `ws.tree`(`std.meta.eql` — `Node`가 `union(enum)`이라 태그와 값을 함께 본다)를 지난 값과
   대조한다. 다르거나 null(첫 프레임)이면 화면 전체다 — 지금의 `renderBackdrop` → 패널마다 `renderPane` → `renderOverlay` 그대로,
   clip 없이 `present`. 트리가 같으면 패널의 사각형도 같으므로(`rect`는 `applyLayout`에서만 바뀐다) 패널 단위로 내려간다.
   `needs_redraw`를 켜는 자리 열하나를 안 건드린다.
4. 패널 단위의 통째 조건은 셋이다(결정 3) — 지난 목록이 없음(`spawnPane` 직후, `applyLayout`이 `rect`를 바꾼 뒤), 이번 프레임에
   이미지가 있음, 지난 프레임에 이미지가 있었음. 그 패널의 사각형(+ 확정 2의 오른쪽 한 칸)을 `MARGIN_COLOR`로 지우고 구분선 칸을
   되돌린 뒤 지금의 `renderPane`을 그대로 부른다. clip은 그 사각형 하나.
5. 패널의 셀 목록은 두 벌이다. `Pane`에 `cells_buf: [2][]vt.CellGlyph`(패널의 `cols × rows`) · `starts_buf: [2][]u32`(`rows + 1`) ·
   `shown: u1` · `shown_len: usize` · `prev_valid: bool` · `had_imgs: bool` · `had_prompt: bool` · `band_row: ?u16`을 둔다. `cells()`는
   `cells_buf[shown ^ 1]`에 받고 `cells_buf[shown]`과 비교하며, 그 패널을 다 그린 뒤에 `shown`을 뒤집는다(design 위험 4 — 사본은 다
   그린 뒤에 바꾼다. 다만 지금 `render`의 에러는 `tick`을 거쳐 terminal을 끝내므로 반만 칠한 fb가 다음 프레임을 만날 일은 없다).
   사본을 복사하지 않는 이유는 비용이다 — 격자 전체 7285셀 × 16바이트 = 116KB를 TCG에서 매 프레임 옮기면 패널마다 수십 µs다.
   버퍼를 격자 전체가 아니라 패널 크기로 잡는 이유는 메모리다 — 워크스페이스 아홉 × 패널 여덟이 격자 크기 두 벌씩이면 17MB다.
   `applyLayout`이 `rect`를 바꾸는 자리에서 `screen.resize` · `pty.resize` 옆에 버퍼도 다시 잡고 `prev_valid = false`. `App.cell_buf`는
   지운다 — `frame.cells`가 포커스 패널의 `cells_buf[shown]`을 가리키고 덤프 열둘은 그 슬라이스만 읽는다. verify의 `cell_buf`는 그대로다
   (포커스 아닌 패널의 재호출 자리).
6. 행 비교 모듈(결정 9)은 `verify.zig`에 둘이다. `rowStarts(comptime Cell, cells, starts: []u32) bool` — 목록을 한 번 훑어 행마다
   시작 위치를 채우고, 행이 오름차순이 아니면 false다(그러면 그 패널은 통째). `dirtyRows(comptime Cell, prev, prev_starts, cur,
   cur_starts, dirty: []bool) u16` — 행마다 길이가 같고 바이트가 같은지(`std.mem.sliceAsBytes` + `std.mem.eql`) 본다. `Cell`이
   `comptime` 인자인 이유는 `verify.zig`가 `vt.zig`(ghostty)를 import하지 않기 위해서다 — `verify_test`는 ghostty 없이 돈다. 바이트
   비교가 패딩을 안 보려면 `@sizeOf(Cell)`이 필드 크기의 합과 같아야 한다 — 모듈이 `comptime`에 단언한다(`CellGlyph`는 4+2+2+4+4 = 16).
7. overlay 행(결정 4). 포커스 패널에 셋을 더한다 — 커서 띠의 행(이번 `cursorMark().px`의 행과 지난 프레임의 `band_row`), 프롬프트
   행(이번에 `frame.prompt != null`이거나 지난 프레임에 있었으면 `rect.rows - 1`). block 커서와 preedit의 반전은 `cells()` 안이라
   저절로 잡힌다. 다시 칠한 행에 커서 띠의 행이 있으면 그 행의 글리프 뒤에 띠를 칠한다(`renderPane`의 맨 끝과 같은 순서). 상태 줄은
   격자 아래 띠 전체(`GRID_Y + rows × ROW_HEIGHT`부터 `fb.height`까지, 폭 전체)를 `MARGIN_COLOR`로 지우고 `drawStatus` — 이 지우기는
   `renderOverlay` 안에 둔다. 그림자 경로도 같은 함수를 부르지만 거기서는 이미 그 색이라 픽셀이 안 바뀐다(통째 경로의 정의가 안
   바뀐다). `drawStatus`의 "띠를 따로 안 지운다" 주석을 고친다.
8. 화살표는 프레임 처음에 `restore`한다(지금은 끝에 `forget`). 부분 경로는 지난 화살표를 지워 주는 `fill`이 없으므로 저장한 픽셀로
   되돌리는 것이 유일한 길이고, 통째 프레임에서도 같은 순서면 된다(되돌린 뒤 덮는다). 그래서 verify의 픽셀 비교 시점(화살표를
   그리기 전)에 실제 fb에 화살표가 없다. 옛 자리와 새 자리의 12 × 19 사각형 둘이 clip에 든다. `decideFrame`의 화살표만 고치는
   바퀴도 같은 둘을 clip으로 넘긴다 — `restore` · `show` · `present(clips)`.
9. clip. `drm.zig`에 uapi `drm_clip_rect` 모양의 `Clip = extern struct { x1, y1, x2, y2: u16 }`(x2 · y2는 끝 다음)과 `ClipList`
   (`[MAX_CLIPS]Clip` 고정 배열, `push(x, y, w, h)`, 가득 차면 전부를 경계 상자 하나로 접는 `folded`)를 둔다. `present(clips: []const
   Clip)` — 비어 있으면 지금처럼 `num_clips` 0(fb 전체), 아니면 `num_clips` · `clips_ptr`를 채운다. `dirty`가 false인 드라이버는 clip을
   무시하고 SETCRTC다. 합치는 규칙은 한 패널 안의 이웃한 dirty 행을 사각형 하나로(세로 run). `MAX_CLIPS`는 64다 — 커널 상한은
   `DRM_MODE_FB_DIRTY_MAX_CLIPS` 256이고 패널 여덟 × 행 47의 교대 run은 192까지 가능하므로 접는 규칙이 있어야 한다. 64인 이유는
   커널 쪽 사실 둘이다(`kernel/src/linux-6.18.42`):
   - virtio-gpu(`virtgpu_plane.c:262`)는 `drm_atomic_helper_damage_merged`로 clip 전부를 경계 상자 하나로 합쳐 그 사각형만
     `transfer_to_host_2d` · `resource_flush`한다. QEMU에서는 clip 개수가 아니라 상자의 크기만 뜻이 있다.
   - simpledrm(`sysfb/drm_sysfb_modeset.c:256`)은 `drm_atomic_for_each_plane_damage`로 clip마다 `drm_fb_blit`를 한다 — 개수마다
     복사 한 번이고 겹치면 두 번 복사한다. 행 run을 합치는 것이 여기서 값어치가 있고, 64를 넘는 프레임은 어차피 화면 대부분이다.
   - 둘 다 `drm_atomic_helper_dirtyfb`(`drm_damage_helper.c`)를 지난다 — clip을 plane의 `fb_damage_clips` blob으로 바꿔 commit한다.
     fb가 바뀌면 clip을 무시하지만(`virtgpu_plane.c:118`) 우리는 fb 하나다. design 위험 5의 답이 이것이다.
10. clip의 판정은 verify 모드의 "화면 흉내" 버퍼다. verify는 fb와 그림자를 비교하므로 clip을 빼먹은 프레임을 못 본다 — fb는 맞고
    화면만 낡는다. 게이트의 덤프도 fb를 읽는다. 그래서 `Verify`에 `screen: [*]u8`(같은 치수, heap 4MB)을 하나 더 두고, `present(clips)`
    뒤에 clip 안의 픽셀 행만 fb에서 `screen`으로 복사한 뒤(clip이 없으면 전체) `verify.compare(fb, screen)`을 한 번 더 한다. 다르면
    "clip 밖의 픽셀을 바꿨다"이고 줄은 `terminal: verify> mismatch clip rows=<n> first=…`다. 둘 다 같으면 지금의 `ok us=<N>` 한 줄
    그대로라 루트 게이트의 regex는 안 바뀐다 — `ok`가 아닌 줄은 모두 빨강이다. `us`는 두 비교를 합친 시간이다. 화살표만 고치는 바퀴는
    `screen`에 두 사각형을 복사만 하고 비교는 안 한다(포인터 체인의 움직임마다 4MB 비교를 더하지 않는다) — 거기서 clip이 빠지면 다음
    프레임의 비교가 잡는다. 안 고른 길: QEMU monitor의 `screendump`는 host 표면의 PPM이지만 virtio-gpu의 host 갱신이 비동기라
    프레임과 맞추기 어렵다.
11. 호스트 검사. `verify_test`에 `rowStarts` · `dirtyRows`의 단위 검사(가짜 `Cell` — 빈 행 · 끝 행 · 길이만 다른 행 · 순서가 깨진
    목록)를 더하고, 새 `terminal/src/dirty_test.zig`가 ghostty식 무작위 검사를 돈다(`build.zig`에서 `image_test`와 같은 배선 —
    ghostty-vt host dep + stb). 고정 seed(`std.Random.DefaultPrng`)로 300회차, 회차마다 `vt.Screen`에 조작 하나를 넣는다 — 글자 run
    (ASCII · 한글) · `\n` · `\r` · CUP · SGR(fg · bg · inverse · reset) · EL · ED · alt screen 켜고 끄기 · `scrollByRows` · `setPreedit` ·
    copy mode 들어가서 움직이고 나오기 · `findOpen` → `findChar` → `findSubmit` → `findCancel` · `focused` 토글. 회차마다 `cells()` →
    `rowStarts` → `dirtyRows`를 돌리고, 행마다 목록을 `row` 필드로 걸러 낸 무식한 비교(정답지)와 dirty 비트가 정확히 같은지 단언한다
    (같지 않다고 한 행은 정말 다르고, 같다고 한 행은 정말 같다). 실패 메시지에 seed와 회차 번호를 찍는다.
12. `render`의 부분 경로 순서. `sprite.restore` → 통째 판정(확정 3) → 패널마다 [`cells()` → `rowStarts` → 통째 조건(확정 4) 아니면
    `dirtyRows` + overlay 행(확정 7) → 그 행들을 지우고 다시 칠한다(`renderRows`, 새 함수 — 행마다 배경 전부 → 글리프 전부의 두 벌
    순서, design 결정 5) → `shown` 뒤집기] → `renderOverlay` → `verifyFrame`(픽셀) → `sprite.show` → `present(clips)` → verify의
    화면 흉내(확정 10). 포커스 아닌 패널 먼저 · 포커스 패널 마지막은 그대로다. `frame_us`는 그대로 `present` 뒤까지다.
13. 프로브. 비교 판 `probe/patch.pl`의 anchor 넷(`pty_buf` 필드 · `battery_clock` 줄 · `pane.screen.feed(out);` · `dumpFrame`의
    `frame_us` 줄)은 이 milestone이 안 건드린다. 진단 판 `probe/split.pl`은 M0 HEAD 전용이라 anchor를 새로 고른다 — 구간은
    `cells`(포커스 패널의 `cells()`) · `diff`(`rowStarts` + `dirtyRows`) · `rows`(`renderRows` 또는 통째) · `overlay`(`renderOverlay`) ·
    `present`다. M0의 `backdrop` · `pane`은 부분 경로에 없다.
14. M3 판단 규칙 — 숫자를 보기 전에 정한다(M0 확정 6과 같은 30%). 새 (a) frame 중앙값에서 `cells`의 몫이 30% 이상이면 M3(행 dirty
    비트로 `cells()`를 줄이기, design 결정 2)을 사용자에게 제안한다. M0의 cells 0.63ms가 그대로이고 frame이 1ms 안팎으로 내려오면
    60%쯤이라 제안이 나올 가능성이 크다 — 하느냐는 사용자가 고른다.
15. mutation은 둘이다. (a) 확정 7의 "지난 프레임의 프롬프트 행"을 뺀 판 — render 체인에서 검색 프롬프트가 닫히는 프레임에 verify가
    `mismatch`여야 한다(verify가 부분 경로에서도 load-bearing인지). (b) 상태 줄 띠의 clip을 뺀 판 — 모든 프레임에 `mismatch clip`이어야
    한다(확정 10의 판정이 clip을 정말 보는지). 둘 다 `make check CHAIN=render` 한 판이면 된다.

## Task 1: 행 비교 모듈과 호스트 검사

- `terminal/src/verify.zig`: `rowStarts` · `dirtyRows`(확정 6). 머리 주석의 "DR-M2의 행 비교도 이 파일에 들어온다"를 현재형으로.
- `terminal/src/verify_test.zig`: 확정 11의 단위 검사.
- `terminal/src/dirty_test.zig` + `build.zig`: 확정 11의 무작위 검사. `zig build test`에 더한다.
- 호스트 0.17로 `fmt --check` · `ast-check`(lessons "범용 명령"), 컨테이너에서 `zig build test`.
- commit 하나.

## Task 2: 부분 갱신 (clip 없이)

- `Pane`의 두 벌 버퍼와 플래그(확정 5), `spawnPane` · `applyLayout` · EOF 닫기 · `App.close`의 잡기와 놓기. `App.cell_buf` 삭제.
- `App.last_current` · `last_tree`와 통째 판정(확정 3), 패널 통째 조건(확정 4), `renderRows`(확정 2 · 7), `renderOverlay`의 띠 지우기
  (확정 7), 화살표 `restore`(확정 8). `present`는 아직 clip 없이 전체다 — 이 Task의 판정은 verify의 픽셀 비교 하나로 충분하다.
- `make check CHAIN=`으로 render · pane · hangul · copy · pointer 다섯을 돈다(각 2~4분). verify 줄은 lessons "범용 명령"의 한 줄로
  본다 — `ok`가 아닌 줄이 0이어야 한다.
- mutation (a)(확정 15).
- commit 하나.

## Task 3: clip

- `drm.Clip` · `ClipList` · `present(clips)`(확정 9). `render`가 clip을 모으고, `decideFrame`의 화살표 바퀴도 둘을 넘긴다(확정 8).
- verify의 화면 흉내(확정 10) — `openVerify`에서 버퍼 하나 더, `close`에서 놓기, `present` 뒤의 복사와 비교, 줄의 모양.
- render(`kms: present by dirtyfb` 줄이 그대로인지) · pointer 체인. mutation (b).
- commit 하나.

## Task 4: 재측정 · 루트 게이트 · 닫기

- `probe/split.pl`의 새 anchor(확정 13). 비교 판 3회(label `dr-m2`) · 진단 판 3회(`dr-m2-split`), 약 15분. 결과를 이 plan에 옮겨 적고
  M0의 2.45ms와 비교, 확정 14의 판단.
- 루트 게이트(약 10분, `RUNS` · `JOBS`는 lessons "게이트를 돌리고 읽는 법"). 22/22와 `verify lines N ok`가 회차마다.
- 닫기 — design의 milestone 표 DR-M2 행과 `Status:`, 결정 3 · 5의 한 줄(확정 1), `docs/guides/completed.md` 한 행,
  `docs/guides/carryover.md`의 렌더 쪽 첫 항목(부분 갱신) 닫기, `measurements.md`에 실측(94부터 — 커널의 clip 처리 둘, 새 (a) frame),
  `docs/decisions/project_dirty_rows.md`와 `MEMORY.md` 한 줄, `HANDOFF.md`. 소개 페이지는 RS가 어떻게 했는지 보고 같게 한다.
- M3을 제안하게 되면 design의 milestone 표에 행을 더하고 사용자가 고른다.

## 위험 (이 milestone의 것)

- 행 비교가 "같다"고 했는데 픽셀이 다른 길. 셀 목록 밖에서 픽셀을 정하는 것은 이미지(패널 통째) · 커서 띠 · 프롬프트(overlay 행) ·
  preedit의 새는 반 칸(확정 2) · 상태 줄(매 프레임)뿐이라고 믿는다. 하나라도 빠졌으면 verify가 그 체인에서 `mismatch`를 찍는다 —
  그것이 이 milestone에서 verify의 일이다.
- 행 비교와 두 벌 버퍼가 프레임마다 더하는 비용. `cells()`가 패널마다 한 번인 것은 그대로이고, 비교는 목록 바이트를 한 번 읽는
  것(최대 116KB)이다. 프로브가 `diff` 구간으로 그것을 보여 준다.
- 접힌 clip(`folded`)은 언제나 상위 집합이라 안전하다. 확정 10의 판정은 상위 집합을 통과시키므로 "너무 큰 clip"은 못 잡는다 — 그것은
  성능이지 정확성이 아니고, 실기의 효과는 "사용자가 확인할 것"이다(design "효과가 없거나…" 절).
