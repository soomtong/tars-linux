# TG-M1 — `vt.zig`가 이미지를 픽셀 사각형으로 내놓는다

Goal: design 결정 2 · 3. `Screen`이 셀의 픽셀 크기를 라이브러리에 알리고, 화면에 보이는
kitty placement를 렌더러가 그대로 그릴 수 있는 숫자로 내놓는다. 그리는 일(`main.zig`)은
M2다 — 이 milestone이 끝나도 화면은 그대로다.

Architecture: `Screen.init`이 인자 하나(`cell: CellPx`)를 더 받아 `term.width_px` ·
`term.height_px`를 채운다. 새 함수 `Screen.images(out)`가 `cells(out)`과 같은 모양으로
호출자의 버퍼를 채워 슬라이스를 돌려준다. 계산은 라이브러리 C API의
`placement_render_info`(`ghostty-src/src/terminal/c/kitty_graphics.zig:549`)와
`computeViewportPos`(같은 파일 `:603`)를 정답지로 옮긴다 — 둘 다 C 래퍼 타입을 받거나
`pub`이 아니어서 Zig 모듈에서 부를 수 없다. 검사는 `vt_test`다.

---

## 정한 것

1. 픽셀 크기는 `init`의 인자다. 실측 2에서 커서 이동이 전송 순간에 정해지는 것을 봤다 —
   setter로 두면 첫 `feed` 뒤에 부르는 실수가 컴파일을 통과한다. 인자면 빠뜨릴 수 없다.
   대가는 `Screen.init` 호출부 열아홉(`main.zig` 하나 · `vt_test.zig` 열여덟)을 고치는 것이다.
   `vt_test`는 전부 `main.zig`와 같은 `.{ .w = 8, .h = 16 }`을 넘긴다.
2. 필드는 직접 채운다. 라이브러리의 정식 경로는 `resize(.., .{ .cell_size_px = .. })`지만
   우리는 크기를 바꾸지 않고, `resize`도 같은 곱셈을 두 필드에 쓴다(`Terminal.zig:3800`).
3. `ImagePlacement` 하나에 렌더러가 필요한 것 전부를 담는다.

   ```zig
   pub const ImageLayer = enum { below_bg, below_text, above_text };
   pub const ImageFormat = enum { rgb, rgba };
   pub const ImagePlacement = struct {
       layer: ImageLayer,
       format: ImageFormat,
       data: []const u8,      // 라이브러리 저장소의 바이트. 다음 feed까지만 유효하다
       width: u32, height: u32,               // 이미지 전체
       src_x: u32, src_y: u32, src_w: u32, src_h: u32,
       dst_x: i32, dst_y: i32,                // 격자 왼쪽 위 기준 픽셀. 음수일 수 있다
       dst_w: u32, dst_h: u32,
   };
   ```

   `dst_x = col × cell.w + x_offset`, `dst_y = row × cell.h + y_offset`이고 `row`는
   viewport 기준이라 음수일 수 있다. 격자 밖으로 나간 부분을 자르는 것은 렌더러다 —
   잘린 부분의 원본 좌표는 확대 비율에 딸려 있어서, 사각형을 미리 자르면 최근접 이웃의
   대응이 렌더러와 이쪽에 나뉜다. 여기서는 화면에 한 픽셀도 안 걸리는 것만 뺀다.
4. 층은 ghostty 렌더러의 경계와 같다 — `z < minInt(i32)/2`는 `below_bg`, `z < 0`은
   `below_text`, 나머지는 `above_text`(`renderer/image.zig:384`). 결과는 z 오름차순이고 같은
   z는 image id 오름차순이다. 렌더러는 층마다 앞에서부터 그리면 된다.
5. 빼는 것 — virtual placement, 데이터가 아직 다 안 온 이미지(`isPending`), 크기가 0인 것,
   형식이 `rgb` · `rgba`가 아닌 것(`gray` · `gray_alpha`는 PNG 디코드에서만 생긴다 — M3).
   `out`이 차면 나머지는 버리고 `images_dropped`를 센다. 정렬은 버린 뒤가 아니라 모은 뒤에
   해야 하므로, 모으는 동안은 `out` 안에서 하고 넘친 것만 센다.

## Task 1: `Screen.init`이 셀 픽셀 크기를 받는다

`pub const CellPx = struct { w: u32, h: u32 }`. `init`이 `term`을 만든 직후
`width_px = cols × w`, `height_px = rows × h`. 호출부 열아홉을 고친다. `main.zig`는
`.{ .w = CELL_W, .h = ROW_HEIGHT }`을 넘긴다.

검증: `zig build test`가 지금과 같은 결과로 통과한다(동작 변화 없음).

## Task 2: `Screen.images(out)`

위의 정한 것 3~5. 데이터 슬라이스는 `image.data`의 `.complete`다.

## Task 3: `vt_test` 검사

새 화면을 만든다(lessons의 규칙 — 남의 화면에 붙이지 않는다). 20×5, 셀 8×16. 2×2 RGBA를
base64로 실은 명령을 보내고 본다.

| 검사 | 보내는 것 | 기대 |
|---|---|---|
| a | `a=T,f=32,s=2,v=2,i=1` | 하나, `above_text`, dst (0,0) 2×2, src 0,0,2,2, data 16바이트, 커서 (1,0) |
| b | 이어서 `c=4,r=2,i=2` | 둘. id 2는 dst 32×32 |
| c | `z=-1,i=3` · `z=-1073741825,i=4` | 층이 `below_text` · `below_bg`, 정렬은 z 순 |
| d | `X=3,Y=5`(셀 안 오프셋) | dst가 오프셋만큼 밀린다 |
| e | `x=1,y=0,w=1,h=2`(원본 사각형) | src가 1,0,1,2 |
| f | 줄바꿈으로 첫 이미지를 밀어 올려 한 줄 걸치게 | dst_y 음수, 여전히 나온다 |
| g | 더 밀어 완전히 위로 | 안 나온다. `scrollToTop()` 뒤에 다시 나온다 |
| h | `f=24`(RGB) | `format == .rgb`, data 12바이트 |
| i | `out` 길이 1에 둘 | 하나 나오고 `images_dropped == 1` |

정확한 값은 Task 2를 쓴 뒤 탐침 숫자(실측 2 · 4)와 맞춰 확정한다. 기대값을 결과를 보고
고치지 않는다 — 다르면 왜 다른지부터 쓴다.

## Task 4: 문서

design의 Status를 M1 끝으로. 실측이 새로 나오면 "실측 (M1)" 절.

## 끝났다고 말할 조건

- `zig build test` 통과(컨테이너, 1~2분). 부팅 게이트는 돌리지 않는다 — 렌더러가 안
  바뀌었고 `main.zig`의 변화는 인자 하나다. terminal 체인 하나는 돌려 그 인자가 부팅을
  안 깨는 것을 본다(약 수 분).
- `git diff --stat`의 지운 줄이 `Screen.init` 호출부 열아홉의 옛 줄뿐이다.

## 한 대로 (2026-10-03)

Task 1 · 2 · 3은 plan대로 했다. 다른 것 셋:

- `ImagePlacement`에 `z` · `image_id`가 더 들어갔다. 정렬의 열쇠가 필요했다. 렌더러는 안 쓴다.
- 셀 크기를 `Screen`의 필드로 들고 있지 않고 `term.width_px / term.cols`로 되찾는다.
  라이브러리가 placement 크기를 셀 때 쓰는 식이라 두 값이 어긋날 수 없다.
- 검사가 아홉이 아니라 열(65~74)이다. 대체 화면(design 위험 3)을 하나 더 봤다.
  기대값은 쓰기 전에 계산해 주석에 적었고 첫 실행에 전부 맞았다 — 고친 값이 없다.
