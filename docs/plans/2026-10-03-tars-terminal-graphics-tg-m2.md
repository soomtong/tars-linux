# TG-M2 — 렌더러가 이미지를 그린다

Goal: design 결정 4 · 7. `main.zig`가 `Screen.images()`의 결과를 프레임버퍼에 그리고,
`render` 체인이 게스트 안에서 이미지 둘을 보내 픽셀로 판정한다. 위험 1(프레임 비용)을 잰다.

Architecture: 픽셀 산수(최근접 이웃 · 자르기 · 알파 합성)는 새 순수 모듈
`terminal/src/image.zig`에 둔다. 대상은 `anytype` — `getPixel` · `setPixel`이 있는 것 —
이라 게스트에서는 `drm.Framebuffer`를, 호스트 검사 `image_test.zig`에서는 `u32` 배열 하나를
받는다(`control.zig`가 anytype으로 규칙을 호스트에서 검사하는 것과 같은 모양). `main.zig`는
층을 나눠 부르고 덤프 줄을 찍는 일만 한다.

---

## 정한 것

1. 결정 4의 순서. `fill` → `below_bg` → 셀 배경 → `below_text` → 글리프 → `above_text` →
   프롬프트 → 상태 줄. `images()`의 결과가 이미 z 순이라 층마다 앞에서부터 그린다.
2. 기본 배경색 셀은 `below_bg` 이미지 위에서 투명하다. `cells()`는 글자가 있는 셀을 기본
   배경이어도 내보내므로(`vt.zig:750`), 그대로 칠하면 `below_bg` 이미지가 글자 셀마다
   덮인다. kitty의 뜻은 "기본이 아닌 배경 아래"라서, `bg == defaultBg()`인 셀이 `below_bg`
   사각형과 겹치면 배경을 건너뛴다. 이미지가 몇 개뿐이라 셀마다 사각형 검사를 해도 싸다.
   `below_bg` 이미지가 없는 프레임은 지금과 한 픽셀도 다르지 않다.
3. 자르기 영역은 격자다 — `GRID_X`부터 `cols × CELL_W`, `GRID_Y`부터 `rows × ROW_HEIGHT`.
   여백과 상태 줄에는 안 그린다. `setPixel`에 범위 검사가 없으므로(`drm.zig:149`) 자르기가
   곧 게스트를 지키는 일이다.
4. 최근접 이웃 대응: 목적지 픽셀 `(dx, dy)`(사각형 안의 상대 좌표)는 원본
   `(src_x + dx × src_w / dst_w, src_y + dy × src_h / dst_h)`. 정수 나눗셈이라 확대 배율이
   정수일 때 사분면 경계가 정확히 떨어진다.
5. 알파 합성: `out = (s × a + d × (255 − a) + 127) / 255`, 채널마다. `a == 255`면 그냥 쓰고
   `a == 0`이면 건너뛴다. RGB는 `a = 255`다. 프레임버퍼는 `0x00RRGGBB`.
6. 덤프 두 줄. 매 프레임, 이미지가 있을 때만, placement 넷까지.
   - `terminal: image> id=1 layer=above_text dst=20,52 32x32 src=0,0 2x2 draw=NNNus` —
     dst는 프레임버퍼 좌표(격자 원점을 더한 값). `draw`는 그 프레임의 이미지 그리기 전체.
   - `terminal: imgpx> id=1 tl=FF0000 tr=00FF00 bl=0000FF br=FFFFFF` — 사각형의 네
     사분면 중심 픽셀을 `getPixel`로 읽은 값. 격자 밖이면 `--`.
   `render` 체인의 `style>` / `pixel>`와 같은 두 겹이다 — 앞의 것은 vt.zig가 낸 것,
   뒤의 것은 실제로 칠해진 것.
7. 게이트는 `render` 체인의 같은 부팅이다. 새 체인도 새 부팅도 없다. 기존 검사 14 뒤,
   음성 검사 앞에 둔다.

## Task 1: `image.zig`와 `image_test.zig`

`pub fn draw(target: anytype, p: vt.ImagePlacement, origin_x: i32, origin_y: i32, clip: Clip) void`
와 `pub fn blend(src: u32, dst: u32, a: u8) u32`. `image_test`는 `build.zig`에 `vt_test`와 같은
모양으로 더하고(ghostty 의존이 필요하다 — `vt.zig`의 타입을 쓴다) `test` 단계에 건다.

검사:

| 검사 | 무엇 | 기대 |
|---|---|---|
| 1 | 2×2 RGB → 32×32 | 사분면 넷이 각 256픽셀 같은 색 |
| 2 | 반투명 흰색 1×1 RGBA를 `102030` 위에 | `889098`(정한 것 5의 식으로 미리 계산) |
| 3 | `a == 0` | 바탕 그대로 |
| 4 | dst_y = −16, 32×32, 자르기 y ≥ 0 | 아래 절반만 칠해지고 자르기 밖은 한 픽셀도 안 바뀐다 |
| 5 | 자르기 오른쪽 끝을 넘는 사각형 | 넘는 열이 안 바뀐다 |
| 6 | 원본 사각형 `x=1,w=1` | 오른쪽 열의 색만 나온다 |

## Task 2: `render()`와 덤프

정한 것 1 · 2 · 3 · 6. `images()` 버퍼는 16칸(`images_dropped`가 0이 아니면 키운다).
`render()`가 슬라이스를 받는다.

## Task 3: `render` 체인

```
printf '\033_Ga=T,f=24,s=2,v=2,i=1,c=4,r=2,q=2;/wAAAP8AAAD/////\033\\\n'
printf '\033_Ga=T,f=32,s=1,v=1,i=2,c=2,r=1,q=2;////gA==\033\\\n'
```

`q=2`는 답을 끈다 — 답이 셸 입력으로 가면 프롬프트에 글자가 찍힌다(실측 3). 검사 15 ~ 18:

- 15. `image> id=1 … 32x32`가 있다(vt.zig가 셀 크기를 알고 사각형을 냈다).
- 16. `imgpx> id=1 tl=FF0000 tr=00FF00 bl=0000FF br=FFFFFF`(렌더러가 사분면을 정확히 칠했다).
- 17. `imgpx> id=2`의 넷이 전부 `889098`(알파 합성).
- 18. 음성 — 화면 줄(`screen>`)에 `_G`가 없다. 명령이 글자로 새어 나오지 않았다.

## Task 4: 위험 1을 잰다

같은 부팅이 아니라 따로, 한 번만. 1×1 RGB를 `c=155,r=47`(격자 전체)로 보내고 `image>`의
`draw=`와 `render> first frame`을 견준다. design "실측 (M2)"에 적는다. 게이트에는 안 넣는다.

## 끝났다고 말할 조건

- `zig build test` 통과(`image_test` 포함).
- `render` 체인 PASS. 다른 체인은 안 돌린다 — 바뀐 것은 렌더러뿐이고 루트 게이트는 M3이
  돈다.
- design의 Status와 실측 (M2).

## 한 대로 (2026-10-03)

Task 1 · 2 · 3 · 4를 했다. 다른 것:

- `image>`의 `draw=`(이미지 그리기 시간)가 `frame=`(`render()` 전체)이 됐다. 호출부에 이미
  `frame_start`가 있어서 시계를 `render()`에 넘기지 않아도 됐고, 위험 1이 묻는 것도 프레임
  전체다.
- 검사 18을 "`_G`가 없다"에서 "페이로드가 한 번"으로 바꿨다(design 실측 6).
- 기존 style 상한 음성 검사를 이미지 구간 앞으로 좁혔다(design 실측 6).
- 끝의 `ESC \`는 `\033\134`다. 셸이 fish라 `\\`가 따옴표 안에서 접힌다.
- `image_test` 여섯 · `render` 체인 검사 넷 모두 기대값을 먼저 적었고 고친 값이 없다.
