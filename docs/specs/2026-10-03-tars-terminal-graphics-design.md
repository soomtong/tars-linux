# TARS Terminal Graphics — Design

접두사: TG

Status: 진행 중(2026-10-03) — M1 끝(`vt.zig`의 `CellPx` · `images()`, `vt_test` 검사 65~74). 결정 5를 실측 1로 고쳤다.

관련 문서: `docs/decisions/project_termium_survey.md`(이 후보가 나온 조사) ·
`docs/decisions/project_terminal_rendering.md`(색·오프셋을 `vt.zig`가 확정하는 경계) ·
`docs/decisions/project_render_cost.md`(한 프레임의 84.7%가 `fill`) ·
`docs/decisions/project_terminal_queries.md`(질의의 답이 나가는 `write_pty` 길) ·
`docs/decisions/feedback_superpowers_off.md`(이 서브프로젝트의 첫 milestone이 그 검증이다).

## 한 줄 요약

자식이 kitty graphics 프로토콜로 보낸 이미지를 우리 렌더러가 프레임버퍼에 그린다.
명령을 해석하고 이미지를 저장하는 것은 ghostty vt가 이미 한다. 우리 코드는 셋이다 —
셀의 픽셀 크기를 라이브러리에 알리는 것, 저장된 placement를 화면 픽셀 사각형으로 바꾸는
것(`vt.zig`), 그 사각형에 RGBA를 그리는 것(`main.zig`).

## 왜 지금인가

2026-10-03에 사용자가 후보 넷(터미널 그래픽 · USB 동글 층 B · IPv6 · 패키지 매니저) 중
이것을 골랐다. termium 조사(2026-10-01)에서 브라우저는 non-root와 패키지 관리자 뒤로
미뤘지만, 그 아래 층인 "터미널이 그림을 그린다"는 그 둘과 무관하게 설 수 있다. 서면
이미지 뷰어 · 파일 관리자 미리보기도 함께 된다.

## 착수 전에 아는 것

2026-10-03에 소스를 읽어 확인했다. 실행해서 본 것은 아니다 — 그것이 M0이다.

1. 라이브러리 쪽은 켜져 있다. `kitty_graphics` 빌드 옵션은 wasm32-freestanding만 끈다
   (`ghostty-src/src/terminal/build_options.zig`). `ImageStorage.enabled()`는
   `total_limit != 0`이다. 필드 기본값은 320MB지만(`kitty/graphics_storage.zig:133`)
   실제 한도는 10MB다 — 실측 1. 받는 방식은 `image_limits = .direct`라 이스케이프 안에 base64로 실어 보내는 것만 된다.
2. 형식. raw RGB · RGBA와 zlib 압축은 라이브러리가 푼다. PNG는 `sys.decode_png`가 lib 빌드에서
   `null`이라 거부된다(`terminal/sys.zig:18`). 이 함수 포인터는 쓰는 쪽이 채우게 되어 있다.
3. 셀 픽셀 크기가 비어 있다. `vt.zig`는 `Terminal`의 `width_px` · `height_px`를 안 채운다
   (기본 0). placement 크기 계산은 `t.width_px / t.cols`로 셀 크기를 구하므로
   (`graphics_storage.zig:912`), 셀 수로 크기를 지정한 이미지는 0픽셀이 될 것이다.
4. `RenderState`는 이미지를 안 담는다. ghostty 앱의 렌더러도 저장소
   (`t.screens.active.kitty_images`)를 직접 읽어 placement를 뷰포트 좌표로 바꾸고, z 값으로
   세 층 — 배경 아래(`z < minInt(i32)/2`) · 글자 아래(`z < 0`) · 글자 위 — 으로 나눈다
   (`ghostty-src/src/renderer/image.zig:256` `kittyUpdate`).
5. 렌더러 `render()`(`terminal/src/main.zig:299`)는 여백 `fill` → 셀 배경 → 글리프 →
   프롬프트 → 상태 줄 순으로 그린다. 이미지를 다루는 줄은 없다.
6. 게이트는 이미 픽셀을 본다. `ink>` 줄이 `fb.getPixel`로 그린 결과를 세고
   (`main.zig:563`), `terminal/check.sh`가 QEMU `screendump`를 쓴다.

## 결정

### 결정 1 — 프로토콜은 라이브러리가 해석하고 우리는 해석기를 짜지 않는다

명령 파싱 · base64 · zlib · 청크 이어 붙이기 · id 관리 · 삭제 · 질의 답은 전부 ghostty vt의
`kitty/` 아래에 있다(7,659줄). 우리가 짜서 배울 것보다 맞추는 비용이 크다
(`project_write_or_reuse`의 기준). 우리 몫은 라이브러리가 끝내지 않은 곳, 곧 "저장된 것을
어느 픽셀에 그리나"다.

### 결정 2 — `vt.zig`가 셀의 픽셀 크기를 라이브러리에 알린다

`width_px = cols × CELL_W`, `height_px = rows × ROW_HEIGHT`. 이 두 상수는 지금 `main.zig`에
있으므로 `Screen.init`이 받는 인자가 늘어난다. 같은 값이 `CSI 14t`(창 픽셀 크기) 질의의 답도
된다. M0이 "0일 때 무엇이 깨지는가"를 먼저 본다.

### 결정 3 — 화면에 보이는 placement를 `vt.zig`가 픽셀 사각형으로 확정한다

TR의 경계 — 색·오프셋·스크롤은 `vt.zig`에서 확정하고 렌더러는 숫자만 받는다 — 를 그대로
따른다. `vt.zig`가 내놓는 것은 placement마다 "이미지의 RGBA와 그 폭·높이, 원본 사각형,
화면의 목적지 픽셀 사각형, 층(셋 중 하나)"이다. 모양은 ghostty `kittyUpdate`의 축소판이고,
virtual placement(Unicode placeholder)는 뺀다(비목표 3). 뷰포트는 copy mode로 스크롤백을
보고 있을 때도 맞아야 한다 — 기준은 active가 아니라 viewport의 꼭대기다.

### 결정 4 — 렌더러는 층 사이에 끼워 그리고, 확대·축소는 최근접 이웃이다

순서는 `fill` → 배경 아래 이미지 → 셀 배경 → 글자 아래 이미지 → 글리프 → 글자 위 이미지 →
프롬프트 → 상태 줄. RGBA의 알파는 이미 그려진 픽셀 위에 합성한다. 확대·축소는 최근접
이웃 하나다 — 쌍선형은 품질이 낫지만 픽셀당 비용이 네 배이고(`project_render_cost`),
게이트가 "이 픽셀은 이 색"으로 판정하기에 최근접 이웃이 정확히 예측된다.

### 결정 5 — 저장 한도는 라이브러리 기본값 10MB를 그대로 둔다

처음에는 "기본 320MB를 낮춘다"였다. 실측 1에서 lib 빌드의 실제 한도가 이미 10MB라는 것이
나왔다(`Terminal.Options.kitty_image_storage_limit`, `Terminal.zig:291`). 1280×800 화면을
가득 채우는 RGBA 한 장이 4,096,000바이트라 두 장이 들어가고, 게이트 게스트의 여유
메모리 213MB(실측 5)에 비해 작다. 넘으면 라이브러리가 오래된 이미지부터 지운다. 바꿀
이유가 생기면 `Screen.init`이 `Terminal`에 넘기는 옵션 한 칸이다.

### 결정 6 — PNG는 `stb_image`로 `sys.decode_png`를 채운다(M3)

이미 `stb_truetype`을 vendor로 갖고 있다(`terminal/vendor/` · `vendor_stb_truetype.sh`).
같은 저자 · 같은 단일 헤더 방식이라 붙이는 모양이 같다. raw RGBA만으로도 프로토콜 경로
전체가 서므로 PNG는 마지막 milestone으로 미룬다 — 그 전까지 PNG를 보내면 라이브러리가
오류를 답한다.

### 결정 7 — 게이트는 호스트 검사와 부팅 하나다

1. 호스트 `vt_test` — 알려진 RGBA 명령을 `feed`하고 결정 2·3의 출력(사각형 · 층)을 숫자로
   본다. 질의 `a=q`의 답이 `takeReplies`로 나오는지도 여기서 본다.
2. 부팅 — QEMU 게스트의 셸이 `printf`로 이미지 하나를 보내고, 렌더러가 찍는 `image>` 덤프
   줄과 프레임버퍼 픽셀(`getPixel`)로 판정한다. 화면 판정 글자는 출력에만 둔다
   (`project_gate_screen_echo`).

어느 체인에 붙일지(새 체인인가, `terminal/check.sh`에 부팅을 더하나)는 M2 plan이 정한다.
M0은 호스트에서만 쟀고 체인 시간을 보지 않았다. 기본안은 새 체인 없이 `terminal` 체인이다.

## 위험

### 위험 1 — 큰 이미지가 프레임 비용을 키운다

한 프레임의 84.7%가 이미 `fill`이다. 화면 가득한 이미지는 그만큼을 한 번 더 쓴다. dirty
추적은 안 하기로 근거가 쌓여 있다(lessons의 이월 숙제). M2가 화면 크기 이미지 하나로 한
프레임을 재고, 사람이 느낄 만큼이면 그때 정한다.

### 위험 2 — 출력에 섞인 이미지 명령이 메모리를 먹는다

`cat`한 파일 안의 명령도 저장된다. 결정 5의 한도가 막는 것이고, 한도에 닿으면 라이브러리가
지운다. 질의의 답은 라이브러리가 짓는 고정 모양(`ESC _G i=…;OK ESC \`)이라 TQ의 제목 보고
같은 입력 주입 경로는 아닐 것이다 — M0이 답의 모양을 본다.

### 위험 3 — placement의 위치가 스크롤과 화면 전환에서 어긋난다

placement는 페이지의 pin에 붙어 있어서 스크롤하면 함께 움직인다. 대체 화면(alternate
screen)은 저장소를 따로 갖는다. 결정 3이 viewport 기준으로 바꾸는 것이 이것을 다루는
자리이고, `vt_test`가 스크롤 뒤의 사각형을 본다.

## 비목표

1. 애니메이션 프레임(`a=f` · `a=a` · `a=c`). 라이브러리가 받는지부터 모른다.
2. 파일 · 임시 파일 · 공유 메모리로 보내기(`t=f` · `t=t` · `t=s`). `image_limits`가 막고
   있고, 게스트가 root라 남의 파일을 읽히는 문이 된다.
3. Unicode placeholder(`U=1`, virtual placement). tmux 너머 그림에 쓰인다 — 우리에게 tmux가
   없다.
4. sixel · iTerm2 `OSC 1337`. 라이브러리가 해석하지 않는다.
5. termium 자체. 막힌 자리(root · namespace · seccomp)는 그대로다.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- TG-M0 — 실측, 제품 코드 0줄. 저장소에 실제로 들어가는가, `width_px`가 0일 때 무엇이
  깨지는가, 질의의 답, placement를 viewport 좌표로 꺼내는 API, 게스트의 여유 메모리.
- TG-M1 — `vt.zig`(결정 2 · 3 · 5)와 `vt_test`.
- TG-M2 — `main.zig`의 그리기(결정 4), `image>` 덤프, 부팅 게이트.
- TG-M3 — PNG(결정 6), 반사실, 루트 게이트, 문서, 닫기.

## 실측 (M0, 2026-10-03)

탐침은 작업 트리에만 둔 `terminal/src/tg_probe.zig`와 `build.zig`의 실행 파일 하나였고,
`vt_test`처럼 호스트(컨테이너, arm64)에서 돌았다. 20×5 화면에 2×2 RGBA를 보내고
`screen.term.screens.active.kitty_images`를 직접 읽었다. 로그는 `/tmp/tg/probe.log`였다.

### 실측 1 — 명령 하나가 이미지 하나 · placement 하나로 들어가고, 한도는 10MB다

`a=T,f=32,s=2,v=2,i=1`(전송하고 바로 표시)이 `images=1 placements=1 bytes=16`을 만들었다.
16바이트는 2×2×4 — 디코드된 RGBA가 그대로 저장된다. `limit=10000000`이 찍혔다. lib 빌드에서
`Terminal.Options.kitty_image_storage_limit`의 기본값이 10MB이고 `Screen` 생성이 그것으로
`setLimit`을 부른다(`Terminal.zig:291` · `Screen.zig:337`). 결정 5를 이것으로 고쳤다.

host 빌드(Debug)에서는 명령마다 `debug(kitty_gfx): …` 세 줄이 stderr로 나온다. 게스트는
ReleaseSafe라 `std.log`의 기본 수준이 info여서 debug 줄은 안 나오고, 틀린 명령의
`warning(kitty_gfx): erroneous kitty graphics response: …`만 나올 것이다 — M2의 부팅 로그에서
확인한다.

### 실측 2 — `width_px`가 0이면 크기를 안 준 이미지는 저장되지만 아무 데도 놓이지 않는다

| 상태 | placement | `pixelSize` | `gridSize` | `rect` | 커서 이동 |
|---|---|---|---|---|---|
| px=0, `c` · `r` 없음 | id 1 | 2×2 | 0×0 | `null` | 없음 (0,0)→(0,0) |
| px=0, `c=4,r=2` | id 2 | 0×0 | 4×2 | (0,0)–(3,1) | (0,0)→(4,1) |
| px=160×80 뒤, 같은 id 1 · 2 | id 1 | 2×2 | 1×1 | (0,0)–(0,0) | — |
| | id 2 | 32×32 | 4×2 | (0,0)–(3,1) | — |
| px=160×80, `c` · `r` 없음 | id 5 | 2×2 | 1×1 | (4,1)–(4,1) | (4,1)→(5,1) |

`gridSize`가 `divCeil(…, width_px / cols)`의 0 나누기를 `catch 0`으로 삼켜 `rect()`가 `null`이
된다(`graphics_storage.zig:957`). 거꾸로 셀 수로 지정하면 사각형은 있는데 픽셀 크기가 0이라
ghostty 렌더러가 건너뛴다(`dest_size.width > 0` 조건). 어느 쪽이든 안 그려진다.

크기는 매번 다시 계산되므로 나중에 px를 채우면 이미 있던 placement도 제 크기가 된다. 그러나
커서 이동은 전송 순간에 한 번 일어난다 — px=0일 때 보낸 id 1 뒤의 글자는 이미지 위에 겹친다.
그래서 결정 2의 px는 `init`에서 채워야 하고, 첫 `feed` 뒤에 채우면 늦다. 셀 크기 8×16에서
`c=4,r=2`가 32×32인 것은 예측(4×8, 2×16)과 같다.

### 실측 3 — 답은 고정된 모양으로 `takeReplies`에 나오고, PNG는 `EINVAL`이다

| 명령 | 답(이스케이프는 `\x1b`) |
|---|---|
| `a=T,…,i=1` | `\x1b_Gi=1;OK\x1b\`(11바이트) |
| `a=q,f=32,s=1,v=1,i=3` | `\x1b_Gi=3;OK\x1b\` — 저장은 안 된다(이미지 수가 그대로) |
| `a=T,f=100,i=4` | `\x1b_Gi=4;EINVAL: unsupported format\x1b\`(35바이트), 저장 안 됨 |
| `a=T,…,i=6,q=2` | 0바이트 — 조용히 저장된다 |

TQ가 세운 `write_pty` 길로 나간다 — 우리 코드는 할 것이 없다. 답에 들어가는 것은 사람이
고른 id 숫자와 라이브러리가 고른 고정 메시지뿐이라, 제목 보고처럼 출력의 글자가 입력 줄에
심기는 길이 아니다(위험 2의 뒷부분은 현실이 아니다). PNG는 결정 6 전까지 지금처럼
`EINVAL`로 거절된다 — `icat`류 도구가 이 답을 보고 다른 형식으로 다시 보내는지는 M3에서 본다.

### 실측 4 — placement는 스크롤과 함께 움직이고, viewport 기준 y가 음수로 나간다

줄바꿈 열 개 뒤 viewport 꼭대기의 `screen.y`가 0 → 7이 되고, 맨 위에 있던 이미지의
viewport y는 −7이 됐다. `scrollByRows(-3)` 뒤 −4, `scrollToTop()` 뒤 0으로 돌아왔다. 변환식은
ghostty 렌더러와 같은 `img_top_y − viewport_top_y`(`renderer/image.zig:445`)이고, 결정 3은 이
값이 음수이거나 행 수를 넘는 placement를 사각형을 잘라서 그리거나 건너뛰어야 한다.
스크롤백에 들어간 placement는 지워지지 않고 남는다.

대체 화면(`ESC[?1049h`)에 들어가면 저장소가 비어 있고(images=0), 나오면 넷이 그대로 있다.
화면마다 저장소가 따로라는 착수 전 4의 읽기와 같다 — 결정 3이 `screens.active`를 보면 된다.

### 실측 5 — 게이트 게스트의 여유 메모리는 이미 재 둔 값을 쓴다

부팅하지 않았다. `docs/guides/lessons.md`의 이월 숙제에 WL 때 잰 값이 있다 — 게이트
`GUEST_MEM=512`(`gate_lib.sh`)에서 `MemAvailable` 213MB. UW가 더한 firmware는 127KB라 이
값을 흔들지 않는다. 결정 5가 이 값을 쓴다.
