# TARS Dirty Rows — Design

Date: 2026-10-28
Status: 진행 중 — DR-M0 끝(2026-10-28) · DR-M1 끝(2026-10-29), 다음은 DR-M2(부분 갱신 + clip).

HANDOFF "다음 후보"의 부분 갱신을 집는다(사용자가 2026-10-28에 골랐다). Render Speed(RS-M0~M3, 2026-10-11)가 그 앞의 축
셋(칠하기 방식 · 프레임 수 · 모드셋)을 줄이고 남겨 둔 것이다 — `docs/decisions/project_render_speed.md`의 "남은 것",
`docs/guides/carryover.md`의 렌더 쪽 첫 항목.

## 한 줄 요약

프레임마다 화면 전체를 다시 칠하던 것을, 패널마다 지난 프레임의 `cells()` 사본과 행 단위로 비교해 달라진 행만 지우고 다시
칠하게 바꾼다. 다시 칠한 사각형은 DIRTYFB의 clip으로 넘긴다. 잔상은 게이트에서만 켜는 verify 모드가 판정한다 — 프레임마다
같은 프레임을 별도 버퍼에 통째로 그려 바이트로 비교한다.

## 배경 — 착수 전 조사 (2026-10-28, HEAD `7dc220f`)

1. `App.render`(`terminal/src/main.zig`)는 세 단계다. `renderBackdrop`이 `fb.fill(MARGIN_COLOR)`로 fb 전체를 칠하고 구분선을
   긋는다. 패널마다 `renderPane`이 셀 배경 → 이미지 세 층 → 글리프 → 커서 띠를 그린다. `renderFinish`가 프롬프트 · 상태 줄 ·
   화살표를 얹고 `present`를 부른다.
2. `present`(`terminal/src/drm.zig`)는 clip 없이 DIRTYFB를 보낸다(`num_clips` 0) — 커널은 fb 전체를 손상으로 받는다. 주석이
   "부분 갱신이 생기면 여기에 사각형을 넘길 자리"라고 적어 두었다. clip이 하나라도 있으면 `num_clips`와 `clips_ptr`가 둘 다
   0이 아니어야 한다(둘 중 하나만 0이면 `-EINVAL`).
3. 키 하나의 그리기는 4.3ms(RS-M3, TCG, 부팅 3회 중앙값)다. 이 안의 구간별 몫은 아무도 안 쟀다. RS-M0의 `frame`은 그리기 전체
   하나였다.
4. 실기는 simpledrm이다. dumb buffer는 시스템 메모리의 그림자이고, 커밋마다 손상 영역을 VRAM으로 복사한다 — clip이 없으면
   1080p에서 프레임마다 8MB다. QEMU에서는 이 차이가 잡음 안이었다(RS 재사용 사실 5). 그래서 이 축의 효과는 게이트로 못 재고,
   사용자가 실기에서 본다.
5. `vt.Screen.cells()`는 그릴 것이 있는 셀만 내보낸다 — 글자가 있거나 색이 기본과 다른 셀. 기본 배경의 빈 칸은 목록에 없다.
   셀 하나는 16바이트(`CellGlyph`: codepoint · col · row · fg · bg)다.
6. 게이트가 그리기를 판정하는 창구는 덤프다. `style>`은 셀 최대 96개, `ink>`는 8개를 표본으로 fb를 되읽는다. 글자가 있는 셀만
   보므로, 이제 비어 있어야 할 칸에 남은 지난 프레임의 픽셀(잔상)은 못 잡는다.

## ghostty는 어떻게 하나 (2026-10-28 검토)

사용자 지시: "ghostty는 가장 잘 구현된 예제가 될 거야." 읽는 판은 `/Users/dp/Repository/_study/ghostty`(사용자가 담은 최신,
`46e9dc9`, 2026-10-27, 얕은 clone)다 — 아래 줄 번호는 그 판의 것이다. 우리 빌드가 링크하는 `terminal/ghostty-src`(`3d07ef9`,
ZU-M2)는 빌드 입력으로만 두고 참고로 읽지 않는다(사용자 결정, 2026-10-28). 두 판에서 `redraw`의 여섯 기준은 글자까지 같다.

- 1층, `RenderState.update`(`src/terminal/render.zig`). page마다 · 행마다 dirty 비트가 있고 VT 파서가 행을 고칠 때 켠다.
  `update`는 먼저 통째로 다시 할지(`redraw`)를 여섯 기준으로 정한다(`:980-1023`) — 활성 화면이 바뀜(alt screen), 터미널 전역
  dirty(팔레트 · reverse colors), 화면 전역 dirty, 행 · 열 수, overscan, viewport pin(스크롤). 아니면 dirty 비트가 켜진 행만
  다시 복사하고 비트를 끈다(`:1238-1265`). 선택 범위가 바뀐 행도 dirty다(`:1356`부터). 답은 `state.dirty`(`false | partial |
  full`)와 행마다 `row.dirty`다.
- 2층, 렌더러 `rebuildCells`(`src/renderer/generic.zig:2630`). `full`이면 GPU 셀 버퍼를 비우고 전부 짓는다. `partial`이면
  dirty 행만 `cells.clear(y)`로 지우고(`:2736`) `rebuildRow`로 다시 짓는다. 1층이 모르는 층(검색 하이라이트)은 그 층을 가진
  렌더러가 직접 행의 dirty를 켠다(`:1582-1599`). 커서와 preedit는 행 dirty와 무관한 overlay로 프레임마다 따로 얹는다.
  아무 행도 안 지었으면 `drawFrame`이 그리기를 건너뛴다(`:1794-1808`).
- 이미지. 최신 판은 kitty 배치를 `RenderState`가 담고(`ImagePlacement`, `:653`) 목록이 바뀌면 값이 바뀌는
  `imagePlacementsGeneration()`(`:823`)을 준다. 렌더러는 그 값이 지난번과 다를 때만 이미지 쪽을 다시 짓는다
  (`renderer/image.zig:259`). 우리 판(`3d07ef9`)의 `RenderState`는 이미지를 안 담는다(`vt.zig`의 `images()` 주석) — 그래서
  우리는 결정 3대로 이미지가 있는 패널을 통째로 그린다. 판을 올리는 일이 생기면 이 값이 "이미지가 그대로인 패널"을 가를 자리다.
- 증분 = 새로 짓기 검사. `testIncrementalMatchesFresh`(`:3156`)는 고정 seed로 300회차 동안 무작위 VT 조작(글자 · 줄바꿈 ·
  커서 이동 · 색 …)을 넣고, 회차마다 증분으로 갱신한 상태와 처음부터 지은 상태를 `testCompareStates`(`:3050`)로 비교한다. 주석이
  이것을 "dirty 추적이 기대는 검사"(load-bearing check)라고 부른다. 결정 7의 verify와 같은 생각이고, 결정 9가 이것을 호스트
  쪽에 옮긴다.
- 픽셀 그리기는 부분이 아니다. GPU가 프레임마다 화면 전체를 셀 버퍼에서 다시 그린다. ghostty가 아끼는 것은 "셀 → GPU
  데이터"의 변환이고, 픽셀은 GPU가 거의 공짜로 칠한다. 우리는 CPU가 dumb buffer에 직접 칠하므로 비싼 자리가 반대다 —
  ghostty의 셀 버퍼 자리에 우리는 프레임버퍼가 온다. dirty 행은 픽셀을 지우고 다시 칠해야 하고, overlay도 지난 프레임에 덮은
  자리를 우리가 되돌려야 한다.
- 우리 `vt.zig`는 같은 `RenderState.update`를 부르지만 `row.dirty`를 끄지 않는다. 그대로 쓰면 첫 프레임 뒤로 모든 행이 늘
  dirty다.

가져오는 것: full 판정의 체크리스트(결정 3), overlay를 행 dirty와 따로 다루는 구조(결정 4), "행을 지우고 다시 채운다"는 모양.
안 가져오는 것: 행 dirty 비트를 dirty의 출처로 쓰는 것(결정 2).

## 효과가 없거나 이 서브프로젝트가 안 하는 것

- 처리량((b) `seq 1 200000`). 출력이 쏟아지면 화면이 프레임마다 스크롤해 모든 행이 바뀐다 — ghostty도 스크롤은 full이다. (b)의
  81%는 VT 파서다(RS). 스크롤을 fb 안의 행 복사(`memmove`)로 바꾸는 것은 비목표 — 하게 되면 그때의 숫자로 정한다.
- 큰 kitty 이미지의 그리기 비용(carryover 렌더 쪽 둘째). 이미지가 있는 패널은 통째로 그린다(결정 3). 이미지를 부분으로
  그리는 일은 그 항목이 다시 집힐 때다.
- GPU 가속. 이 서브프로젝트의 뒤에 있는 일이다.
- 실기 절대값. 게이트와 프로브는 TCG의 전후 비율만 본다(RS와 같다). clip의 효과는 "사용자가 확인할 것"으로 넘긴다.
- 덤프 비용. 덤프는 지금처럼 `cells()` 전체와 fb를 되읽는다(RS design 결정 5와 같은 이유 — 22체인이 판정하는 창구다).

## 결정

1. 측정이 먼저다(RS design 결정 1과 같다). DR-M0은 코드를 안 고치고 키 하나의 4.3ms를 구간으로 쪼갠다 — `renderBackdrop`의
   `fill` · 포커스 아닌 패널 · `cells()` · 포커스 패널의 `renderPane` · `renderFinish`(`present` 따로). RS의 `probe/`를 쓰고,
   새 anchor는 DR-M2가 고칠 자리를 피해 고른다. 이 숫자가 부분 갱신이 줄일 수 있는 몫의 상한이고, `cells()`의 몫이 결정 2의
   다음 단계를 부를지 정한다.
2. dirty의 출처는 `cells()` 결과의 사본이다(사용자 결정, 2026-10-28). 패널마다 지난 프레임에 그린 셀 목록과 행별 시작 위치를
   남기고, 이번 `cells()`와 행마다 바이트로 비교한다(`std.mem.eql`). 이유는 정확성이다 — `cells()`가 라이브러리 위에 얹는
   층(검색 하이라이트 · 선택 · block 커서 반전 · preedit · focus)이 무엇이든 최종 결과를 비교하므로 저절로 잡힌다. 행 dirty
   비트(ghostty의 길)는 그 층이 바뀌는 자리마다 dirty를 켜야 하고 하나만 빠져도 잔상이다. 대가로 `cells()`는 매 프레임 전체를
   돈다. DR-M0에서 `cells()` 몫이 크면 다음 milestone에서 행 dirty 비트로 `cells()`를 줄이고, 그때 셀 사본 비교가 dirty 비트의
   정답지 노릇을 한다(사용자 결정, 같은 날). 사본 크기는 격자 전체의 셀 수 × 16바이트다 — 패널마다 수백 KB.
3. 패널을 통째로 다시 그리는 조건. 셀 비교가 저절로 잡는 것과 따로 잡아야 하는 것을 가른다.
   - 저절로 잡힌다: 스크롤 · alt screen 전환 · 팔레트 변경(셀의 fg · bg 값이 바뀐다) · 선택 · 하이라이트.
   - 따로 잡는다: 기본 배경색이 바뀜(빈 칸은 목록에 없다 — 결정 5의 "지우기" 색이 바뀐다), 패널의 rect가 바뀜(분할 · 닫기 ·
     워크스페이스 전환 — 구분선과 여백도 다시), 이번 또는 지난 프레임에 그 패널에 이미지가 있음, 첫 프레임. "기본 배경색이
     바뀜"은 M2 plan 확정 1이 뺐다 — 지우는 색이 `MARGIN_COLOR`로 고정이라 그 조건이 필요 없다.
   - 화면 전체(`renderBackdrop`부터): 워크스페이스 전환 · 레이아웃 변경 · 패널 수 변경 · 첫 프레임.
4. overlay는 행 dirty와 따로 다룬다(ghostty의 구조). 우리 쪽 overlay는 커서 띠 · 프롬프트(포커스 패널의 마지막 행) · 상태
   줄(격자 밖) · 화살표다. 픽셀이 남으므로 "지난 프레임에 overlay가 덮은 행 ∪ 이번 프레임에 덮을 행"을 그 패널의 dirty 행에
   더한다. 상태 줄은 매 프레임 그 줄만 다시 칠한다(한 줄이다). 화살표는 이미 `pointer.Sprite`의 저장 · 되돌리기가 있다 —
   다시 칠하는 행이 화살표 밑과 겹치면 저장한 픽셀이 낡으므로, 지금처럼 `forget` 뒤 새로 저장하는 순서를 지킨다.
5. dirty 행 하나를 다시 칠하는 법. 그 행 전체(패널 폭)를 기본 배경으로 지우고, 그 행의 셀을 배경 → 글리프 순으로 칠한다
   (TR design 결정 6의 두 벌 순서를 행 안에서 지킨다). "기본 배경"은 `MARGIN_COLOR`다(M2 plan 확정 1) — 통째 경로의 빈 칸이
   `fill`의 그 색이고 verify의 정답이 그 경로다. 글리프는 셀 밖으로 안 나간다는 것을 전제로 한다 — `font_test`가 한글
   11172자에 대해 단언하지만 코드의 성질은 아니다(`drawGlyph` 주석). 위아래로 삐져나오는 글리프가 생기면 이웃 행을 함께 더럽혀야
   하고, verify가 그것을 잡는다.
6. clip. 다시 칠한 사각형들을 DIRTYFB의 clip으로 넘긴다. 사각형 수가 많으면 행을 합친다 — 상한과 합치는 규칙은 M2 plan이 정한다.
   DIRTYFB를 안 받는 드라이버(`dirty` false)는 지금처럼 SETCRTC이고 clip이 없다.
7. 잔상 판정은 verify 모드로 한다(사용자 결정, 2026-10-28). 켜면 프레임마다 부분으로 그린 뒤 같은 프레임을 별도 메모리 버퍼에
   지금의 통째 경로로 그리고 두 버퍼를 비교해, 한 줄을 찍는다 — 같으면 `ok`, 다르면 다른 첫 행들. 22체인 전부에서 켠다 —
   그래서 모든 체인의 모든 프레임이 잔상 검사가 된다. 이 줄이 하나라도 `ok`가 아니면 루트 게이트가 빨개진다. 게이트 밖(배포
   ISO)에서는 꺼져 있다. 켜는 길(빌드 옵션 · cmdline · 설정 키)은 M1 plan이 정하되, 체인 스물둘을 하나씩 안 고치는 길이어야 한다.
8. verify를 먼저 세운다. M1은 verify만 넣고 그리기는 아직 통째다 — 그래서 모든 프레임이 `ok`여야 하고, 그것이 verify 자체의
   검사다(두 경로가 같은 픽셀을 내는가). 여기서 `ok`가 아닌 것이 나오면 부분 갱신 전에 이미 있던 비결정성이다. 그리고 M1은
   일부러 잔상을 만드는 mutation(예: 지우기를 빼먹은 판)에 대고 verify가 빨개지는 것을 본다.
9. 행 비교는 순수한 모듈로 두고 호스트에서 ghostty식 무작위 검사를 돌린다(`testIncrementalMatchesFresh`를 옮긴 것). 지난 셀
   목록과 이번 셀 목록에서 dirty 행 집합을 내는 함수는 fb도 libc도 모르므로 `main.zig` 밖에 둘 수 있다. 호스트 검사는 `vt_test`처럼
   `vt.Screen`에 고정 seed의 무작위 바이트를 먹이고, 회차마다 "dirty가 아니라고 한 행의 셀이 정말 지난번과 같은가"를 단언한다.
   픽셀 쪽(지우기 · overlay · clip)은 이 검사가 못 닿고 결정 7의 verify가 본다. 두 검사가 나눠 맡는다 — 호스트는 빠르고 많은 경우를,
   게스트는 실제 경로(패널 · 프롬프트 · 화살표)를.

## Milestone

| | 무엇을 | 상태 |
|---|---|---|
| DR-M0 | 프로브로 키 하나의 그리기를 구간별로 쪼갠다(결정 1). 코드 0줄 | 끝 — (a) frame 2.45ms(새 기준선). backdrop 0.72 · cells 0.63(25.5%) · pane 0.81 · finish 0.29(present 0.21). M2가 줄일 몫의 상한 약 1.5ms. M3은 M2 재측정 뒤에 다시 판단 |
| DR-M1 | verify 모드(결정 7 · 8). 그리기는 통째 그대로라 모든 프레임이 `ok`. mutation으로 verify가 잡는 것을 본다 | 끝 — initrd 표식 `/etc/tars/render-verify`(`make_initrd.sh`, `TARS_RENDER_VERIFY=1`)로 켠다. 프레임마다 `terminal: verify> ok us=N`, 루트 게이트 `check_verify_lines`가 회차마다 판정. 세 회차 약 2만 3천 프레임 `ok`, verify 한 번 중앙값 약 7ms(게이트 TCG). `renderFinish` → `renderOverlay` + `presentFrame`. mutation(지우기 뺌) 31프레임 `mismatch` |
| DR-M2 | 행 단위 부분 갱신(결정 2~5)과 clip(결정 6), 행 비교 모듈과 호스트 무작위 검사(결정 9). 같은 프로브로 다시 잰다. 루트 게이트에서 verify 전부 `ok` | plan `docs/plans/2026-10-29-tars-dirty-rows-dr-m2.md`(2026-10-29) |

`cells()` 몫에 따라 M3(행 dirty 비트)이 생길 수 있다(결정 2). M1 이후의 구체 결정은 앞 milestone의 숫자를 보고 그 plan에서
정한다.

## 위험

1. verify가 그리기를 두 배로 만든다. TCG에서 프레임이 늘어지면 타이밍에 예민한 검사(pacing · pointer · battery의 대기)가
   흔들릴 수 있다. M1의 루트 게이트가 그것을 본다 — 흔들리면 verify 쪽 그리기를 `frame_us` 밖에 두는 것부터 본다.
2. verify의 통째 경로는 `present` · 화살표 · 덤프를 건드리면 안 된다. 지금 `renderFinish`가 화살표와 `present`를 함께 하므로
   그리는 부분과 내보내는 부분을 가르는 손질이 M1에 든다. 화살표는 비교에서 빼거나 양쪽에 똑같이 그린다(M1 plan).
3. 덤프가 fb를 되읽는 자리(`style>` · `ink>` · `cursor>` · `pixel>`)는 부분 갱신 뒤에도 같은 값을 읽어야 한다 — 같은 프레임이면
   fb가 같기 때문이다. verify가 `ok`이면 이것도 따라온다.
4. 셀 사본과 fb가 어긋나는 길. 그리기 도중 에러로 빠지면(`cache.find` 실패) 사본은 갱신됐는데 fb는 반만 칠해질 수 있다. 사본은
   그 패널을 다 그린 뒤에 바꾼다.
5. 커널 쪽 clip의 모양. clip 수의 상한은 `DRM_MODE_FB_DIRTY_MAX_CLIPS` 256이고(uapi `drm_mode.h:742`), 넘으면
   `drm_mode_dirtyfb_ioctl`이 거부한다(`drm_framebuffer.c:746`, 6.18.42) — 격자 행 수가 이보다 적어 행마다 하나여도 안 넘지만,
   패널 여럿이면 합쳐야 할 수 있다. virtio-gpu · simpledrm이 clip 여러 개를 어떻게 합치는지는 M2에서 확인한다. 답은 M2 plan 확정 9다 —
   virtio-gpu는 경계 상자 하나로 합치고 simpledrm은 clip마다 복사한다.
