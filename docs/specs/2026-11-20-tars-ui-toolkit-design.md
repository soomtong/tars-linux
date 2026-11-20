# TARS UI Toolkit — Design

접두사: TK

Date: 2026-11-20
Status: TK-M1 끝(2026-11-21, `c270732`, 루트 게이트 36/36). 사용자 위임(2026-11-18 "주요 결정은 너의 의견에 따를 테니까")으로 Claude가 정했다.
다음은 TK-M2 plan. 브랜치 `app-layer-0-3`.

계기: App Layer의 3단(`docs/plans/2026-11-18-tars-app-layer-roadmap.md` "3단 — TK", 4판 — WY-M6 뒤). 요구사항
`2026-11-18-tars-app-layer-requirements.md`의 결정 4 · 9 · 13, R-ARCH · R-TKW · R-CG · R-TXT · R-CA · R-KIT · R-FM.

관련 문서: WY design(`2026-11-19-tars-wayland-server-design.md` — 툴킷이 기대는 서버: column configure(결정 21 · 22), 배율(27~31),
클립보드(32~37), text-input(38~43), 호환 모드와 원래 모드의 문 `tars_menu_v1`(45 · 46), damage(47)).

## 한 줄 요약

`toolkit/`에 Zig 라이브러리 `tk`를 따로 짓는다 — Wayland 클라이언트 창 층(버퍼 둘 · configure를 따름 · 바뀐 것만 다시 그림), z2d로 그리는 레이어,
stb_truetype 비례폭 글자. terminal과는 `shared/`의 테마 색 · 글리프 한 겹만 나눈다. 첫 앱은 `tars-files`, 끝은 녹화 C.

## 확인 (2026-11-20, HEAD `79b89b6`)

조사 · 측정은 서브에이전트(`tk-m0`, Opus)가 개발 컨테이너에서 했다(세션 scratchpad `tk/research.md`). lead가 숫자와 줄 번호를 대조했다.

1. z2d(`github.com/vancluever/z2d`) v0.13.2가 Zig 0.17 대응의 고칠 것 없는 태그다(v0.13.1은 zon의 최소 판 사고). 의존 없음 · 순수 Zig · MPL-2.0.
   Zig 0.17.1에서 패치 없이 빌드, 자체 검사 199/199(LLVM ReleaseFast). Debug 자체 백엔드의 테스트 컴파일은 컨테이너 메모리를 넘어 SIGKILL —
   툴킷의 호스트 검사가 z2d를 끌어들일 때 같은 일이 날 수 있다(plan에서 잰다).
2. 시간(aarch64 native ReleaseFast): 400 × 300 판 + 둥근 사각형(r 12, AA) 97 µs, 그중 판 지우기 37 µs. 직접 쓴 SDF 70 µs. 1920 × 1080은
   z2d 1.34 ms · SDF 1.28 ms — 시간은 래스터가 아니라 메모리 쓰기에 있다. 게스트(TCG) 시간은 아직 없다.
3. z2d의 픽셀 `ARGB`는 premultiplied이고 wl_shm `ARGB8888`과 배치가 같다. `Surface.initBuffer`는 바깥 메모리를 쓰지만 stride 인자가 없고(폭 × 4)
   늘 전체를 지운다 — 버퍼마다 한 번 감싸 들고 있어야 한다. Context에 clip이 없다.
4. 한글 비례폭 OFL 후보(Regular 한 벌): Pretendard 1.3.9 .otf 1.57 MB(gzip 1.05 MB, 한자 없음, 13 px에서 줄 높이 16), Noto Sans KR 4.6 MB, IBM Plex
   Sans KR 2.8 MB, 나눔고딕 2.1 MB(줄 높이 = em), Gothic A1 2.3 MB(RFN 없음). RFN이 있는 글꼴은 잘라 싣으면 이름을 바꿔야 한다(OFL FAQ). 다섯 다
   13 px에서 읽힌다(컨테이너의 stb 대리 표본). 서브픽셀 x 위치를 끄면 글자 사이가 고르지 않다. CFF는 glyf보다 두 배 느리지만(5 µs/글자) 캐시가 있다.
5. terminal의 `font.zig`는 16 px · unifont · sprite · 정수 셀 폭이 박혀 있고 8비트 coverage를 돌려준다(문턱값은 `main.zig`). 테마 색은 `main.zig` ·
   `vt.zig` · `pointer.zig`에 상수 열셋 남짓으로 흩어져 있고 게이트 판정의 근거다(바이트까지 같아야 한다). UTF-8은 `std.unicode`뿐.
   PNG 디코더는 kitty 그래픽용(JPEG 꺼짐).
6. 공유 선례: `shared/screen_args.zig` · `display_proto.zig`를 init과 terminal이 `b.path("../shared/…")`로 받는다(순수, libc 없음, quick_check가 `zig run`).
7. 테마를 앱에 알리는 길은 지금 없다 — 설정 키에 색이 없고, terminal은 argv로 받고, 앱은 셸의 환경만 받는다.
8. 서버가 하는 일 중 툴킷이 기댈 것: configure는 논리 픽셀(column = pane 크기, 같은 크기 · activated면 다시 안 보냄), 창 크기 = 버퍼 ÷ bs, damage는
   합집합 하나(결정 47), 옛 버퍼에 release, frame done은 그 창을 낸 뒤(보이지 않으면 안 옴), 그리기 하한 16 ms, `set_title` · `set_app_id` ·
   `set_min_size`는 버린다.
9. 메뉴 바 자리: 격자는 위 여백 20 px(지금 아무것도 안 그림)과 아래 상태 줄. 위 여백 안에 16 px 한 줄이 들어간다(격자 불변).

## 결정

1. 자리와 빌드: `toolkit/`에 `build.zig` · `build.zig.zon`을 따로 둔다. 라이브러리 모듈 `tk`와 실행 파일(TK-M0의 `tars-tk-demo`, 뒤의 `tars-files`).
   부르는 자리는 `terminal/prepare.sh` 끝 한 줄 — 모든 체인이 부르는 BUILD_STEPS 넷을 늘리지 않는다. zig-wayland는 같은 url · hash로 다시 적고,
   스캐너는 terminal의 vendor xml과 `terminal/protocol/`을 가리킨다(클라이언트 쪽만). terminal의 build에서 내는 길은 "툴킷은 라이브러리"(R-ARCH-3)의
   경계를 terminal에 묶어 버린다.
2. 공유 모듈 둘. `shared/theme.zig` — 순수 상수, terminal의 색 상수를 값 그대로 옮긴다(게이트 변화 0). 앱 토큰(R-CA-5)은 같은 파일의 다른 구역.
   `shared/glyph.zig` — stb_truetype 한 겹(`init(data, em_px)` · `glyph(cp, subpixel_x) → coverage + f32 advance + 오프셋` · `kern`). stb 모듈은
   각 build가 addImport로 꽂는다(shared의 "libc 없음"에서 벗어나 quick_check의 `zig run`에서 뺀다). 16 px · unifont · sprite · 정수 셀 · 문턱값은
   terminal 감싸개(`font.zig`)에 남는다. 증거는 font_test 표 그대로 + 루트 게이트 그대로.
   한글 오토마타 · 이미지 디코더는 나누지 않는다(툴킷은 `commit_string`만 받는다 — WY 결정 39, 디코더는 툴킷의 것 — 결정 9).
3. 그리기는 z2d v0.13.2(url + hash, THIRD_PARTY 고지). 둥근 사각형 하나 때문에 버리지 않는다 — 경로 · 선 · 그림자(R-CG-1)를 직접 쓰면 z2d를 다시
   쓰는 일이다. 사각형 채우기의 빠른 길은 백엔드 인터페이스 뒤에 열어 두고 TK-M1의 숫자로 정한다.
4. clip은 툴킷의 것이다(z2d에 없다). TK-M0은 통째 그리기. TK-M1이 측정으로 "더티 크기 임시 판 + 정수 평행 이동 + 행 복사"를 골랐다(2026-11-20,
   조사 `tk-m1`): 행 띠 view(z2d 판에 stride가 없어 x를 못 자른다)보다 네이티브 ReleaseSafe에서 2~5배 빠르고 damage가 더티 사각형 그대로다. 정수 이동
   아래에서 z2d AA와 서브픽셀 글자는 바이트까지 같다(부분 = 통째). 반지름 0 불투명 사각형은 백엔드 안의 빠른 길(직접 채우기 — z2d의 2~10배).
5. 글자(결정 4 · 13): 크기는 em 기준(`stbtt_ScaleForMappingEmToPixels` — 글꼴마다 같은 "13 px"), 서브픽셀 x 위치 켬(0.25 px 넷), 감마 1.8(TK-M0의
   화면 판정 — 1.0에서는 14 px 글자에 coverage 255 픽셀이 하나도 없어 획이 흐렸다),
   소수 advance(f32), kern. 아틀라스는 프로세스마다(R-ARCH-5).
6. 글꼴은 하나, 원본 파일 그대로 싣는다(잘라 싣지 않는다 — RFN). 자리는 initrd `/vendor/fonts/`(TARS 번들 앱이 부른다), 앱은 절대 경로로 연다.
   고르는 것은 TK-M0 plan이고 첫 후보는 Pretendard Regular .otf(가장 작고 UI용 비례폭, 13 px 줄 높이 16), 대안은 Gothic A1.
7. 테마의 길(R-ARCH-6)은 빌드 때 같은 파일(`shared/theme.zig`) — 셸과 앱의 색이 한 소스라는 것을 컴파일이 보장한다. 바꿀 수 있는 테마가 생기면
   `tars_menu_v1` 다음 판의 이벤트로 받는다(terminal이 값을 들고, reload가 재시작이라 다시 붙으며 받는다). 실행 때 파일은 uid · 경로 · 감시를 새로 끈다.
8. 툴킷 창은 TK-M0부터 `tars_menu_manager_v1`을 bind한다(WY 결정 46 — 안 하면 호환 모드라 `Cmd+A` ≠ `Ctrl+A`가 깨진다). text-input은 텍스트 필드가
   포커스를 가질 때만 enable(WY 결정 40 — 리스트 이동 키가 한글 층을 안 지난다).
9. 창 층 규칙(R-TKW-1 · 2 · 4): 버퍼 둘(memfd · pool, 매핑 유지), release로 busy를 풀고 둘 다 busy면 다음 release까지 미룸. 창 층은 CG를 모른다(R-ARCH-1) — 그리는 쪽이 버퍼 픽셀을
   지우지 않는 z2d 판으로 감싼다(TK-M1, z2d `ImageSurface`의 공개 필드). 버퍼 나이 — 이번 버퍼에는 지난 두 프레임 더티의 합을 그린다. 바뀐 것이 있을 때만 frame을 걸고 commit(idle이면 commit 0). configure는
   늘 따른다(크기가 바뀌면 버퍼 둘을 다시). `preferred_buffer_scale`을 받아 물리 크기 버퍼 + `set_buffer_scale`. damage는 `damage_buffer` 사각형
   하나로 시작(서버가 합집합 하나로 합친다 — 목록은 숫자가 바랄 때).
10. 옛 TK-M5를 둘로 자른다(WY 결정 19 · 44와 같은 까닭). 메뉴 바 · 메뉴 요청 처리 · 키는 terminal(서버) 코드이고, 메뉴 모델 · 단축키 표 · 미리보기는
    툴킷 코드다. 서버 쪽은 `set_title` · `set_app_id` 저장(지금 버림)을 함께 한다. `set_min_size`는 서버가 지금처럼 무시한다(strip의 pane 크기가 이긴다).
11. 메뉴 바의 자리는 두 선택지를 TK-M5 plan이 고른다: (가) 위 여백 20 px 안의 16 px 한 줄 — 격자 · 게이트 숫자 불변, (나) 위 여백을 키움 — `geometry.grid`와
    그것을 부르는 넷 · fullscreen 체인의 숫자가 바뀐다. 감추는 조건은 상태 줄과 같다(`ws.fullscreen`, app workspace).
12. 이름: 테스트 앱 `tars-tk-demo`, 로그 접두사 `tk>`(`tk> configure w= h= scale=` · `tk> draw w= h= dirty=x,y,w,h us=` · `tk> commit`), 새 체인
    `toolkit/check.sh`(접두사 TK, monitor 45509 — 예약 범위에서 45508 다음). 호스트 검사는 툴킷의 `zig build test`(메모리 버퍼 백엔드로 픽셀 표)를
    루트 `prebuild`가 부른다.

## Milestone

전제는 WY-M6(끝). text-input · 클립보드 · damage · 원래 모드의 문이 서버에 이미 있다.

| milestone | 서는 것 | 끝나는 조건 |
|---|---|---|
| TK-M0 | 공유 모듈 뽑기(변화 0, 결정 2) · `toolkit/` 빌드 · 창 층(결정 9, 통째 그리기) · z2d · 글자(결정 5 · 6) · `tars_menu_v1` bind · `tars-tk-demo` · 체인 `toolkit` | 루트 게이트 그대로 초록. 데모가 column에 둥근 사각형과 "안녕"을 그리고 `Cmd+R`에 따라 다시 그림, idle에서 commit 0. 결정 4의 화면 판정(13 · 14 px 한글 1배 PNG)을 plan 결과에 |
| TK-M1 | 레이어 트리 · 더티 → `damage_buffer` · clip(결정 4) · 애니메이션 · 스택 레이아웃 · 토큰 | 덤프 둘의 색 차이로 불투명도 애니메이션. `tk> draw us=`와 서버 `wl> blit us=`를 나란히 `measurements.md`에 |
| TK-M2 | responder · 포커스 · 가상화 리스트 · 스크롤(키는 원래 모드의 Super) | `↓` 열 번 뒤 강조 위치. 10만 행 호스트 검사 |
| TK-M3 | column view · 분할 뷰 · `tars-files` 뼈대(로딩 · 안정 선택) | `→` `→` `←` 뒤 열 셋과 포커스 |
| TK-M4 | 비례폭 텍스트 · 텍스트 필드(포커스에서 text-input enable · preedit 그리기 · commit) · 클립보드 · 검색. 표시 → 편집 둘로 가른다 | 한글 `sendkey` → preedit 밑줄 → commit(wayland 판정 26~28의 모양) |
| TK-M5 | 서버 쪽: `tars_menu_v1` 판 2(메뉴 모델 요청 · 고른 항목 이벤트) · 메뉴 바 그리기 · 키 · title/app_id 저장(결정 10 · 11) | 메뉴 바의 좌표 판정 |
| TK-M6 | 툴킷 쪽: 메뉴 모델 · 단축키 표 하나(R-KIT-9) · 미리보기 | 녹화 C |

## 위험

1. z2d를 끌어들인 호스트 검사가 Debug 자체 백엔드에서 메모리를 넘을 수 있다 — 테스트 모듈만 LLVM이나 ReleaseSafe로.
2. 글꼴 하나가 initrd gzip을 약 1 MB 늘린다(Pretendard). 더 줄이려면 RFN 없는 Gothic A1의 부분집합(약 410 KB)이 남은 길이다.
3. TCG에서의 그리기 시간을 아직 모른다 — TK-M0의 첫 숫자가 결정 3 · 4의 근거가 된다.
