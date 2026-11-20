# TK-M1 — 레이어 트리 · 더티 · clip · 버퍼 나이 · 애니메이션 · 스택 · 토큰

Date: 2026-11-20
Design: `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 3 · 4 · 9, milestone 표 TK-M1), 요구사항 R-ARCH-1 · 2 · 4, R-CA-1~5, R-TKW-1
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `tk-m1`, 세션 scratchpad `tk1/research.md` — HEAD `80332bf`, 개발 컨테이너 aarch64 벤치)

- z2d v0.13.2의 clip은 판 경계 하나다. 판에 stride가 없어 "행 띠 view"만 되고 x는 못 자른다. 정수 평행 이동 아래에서 z2d AA · 서브픽셀 글자는
  바이트까지 같다(부분 = 통째, 벤치 모든 경우).
- clip 두 길(616 × 752, 200회 중앙값, ReleaseSafe): 더티 크기 임시 판 32 × 32 9~14 µs · 200 × 40 23~40 µs, 행 띠 31~74 µs · 32~88 µs. 통째 635~1,527 µs.
  우리 `fillRect`는 z2d 같은 사각형의 2~10배 빠르다. 616 × 752 memset 143 µs — 통째 그리기의 1/3~1/2이 바탕 칠하기.
- 서버는 언제든 붙은 버퍼 전체를 읽을 수 있다(통째 프레임 · fit 바뀜) — 클라이언트 버퍼는 commit 때 늘 전체가 맞아야 한다 → 버퍼 나이가 필요하다.
- frame done의 `ms`는 terminal의 시계(원점이 다르고 u32) — 툴킷은 자기 monotonic을 쓴다. idle commit 0의 사슬(바뀐 것 없으면 안 그림 → frame 없음)은
  창 층에 이미 있다.
- 불투명도 그룹(200 × 100)의 임시 판 + 알파 섞기는 네이티브 약 100~140 µs. 잎 레이어의 불투명도는 누적 알파 곱으로 비용 0.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `tk-m1`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — 그리는 사슬: CG 백엔드 · CA 레이어 트리 · 창 층의 더티 · 버퍼 나이 · `damage_buffer` 사각형 · 데모를 트리로. 할 일 1~3.
  체인 toolkit 판정 1~6이 그대로 초록(좌표 · 색 불변).
- 단계 B — 움직임 · 배치 · 체인: 애니메이션 · 스택 · 토큰 · 데모 키 · 판정 7~9 · 측정. 할 일 4~6.

## 착수 전에 확정한 것

1. CG 백엔드(R-ARCH-2): `fillRect(rect, color, alpha)`(빠른 길 — 직접 채우기) · `fillRoundedRect(rect, r, color, alpha)`(z2d) · `drawGlyphs(face, x, baseline,
   str, color, alpha)` · `pushClip(rect)` / `popClip` · `translate(dx, dy)`(정수, 물리). 메모리 판 구현 하나를 창 층과 호스트 검사가 같이 쓴다. 레이어 트리
   코드에 픽셀 포인터가 없다. `draw_image` · 회전 · 늘림 · 그림자는 뒤로.
2. clip(design 결정 4): 더티 크기 임시 판(z2d `initBuffer`로 그 크기만 지움) → 겹치는 레이어만 `translate(-x, -y)`로 → 행 복사. 더티가 판 전체면 임시 판 없이
   버퍼에 바로. 임시 판 메모리는 버퍼를 만들 때(`rebuild`) 버퍼 크기로 하나.
3. 레이어(R-CA-1): frame(f32 논리, 부모 기준) · background ?u32 · radius · opacity · masks · hidden · children · content 콜백. setter만 — 바꾸기 전 · 뒤 화면
   사각형(조상 원점 · masks 조상으로 자름, 물리로 바깥 반올림)의 합을 트리의 더티에. 그리기는 깊이 우선, clip과 안 겹치면 건너뜀.
4. 불투명도는 누적 알파 곱(배경 · 글자). 겹치는 자식의 정확한 그룹 불투명도는 carryover(임시 판 장치가 같으니 필요할 때 더한다).
5. 창 층(design 결정 9): `invalidate(rect)` · `invalidateAll()`, `Window.seq` · `history[4]` · `Buffer.drawn_seq`. repaint = pending ∪ (그 버퍼가 마지막으로
   그려진 뒤의 history), 첫 그림 · rebuild 뒤 · history보다 오래면 통째. `Frame.clip = repaint`. 보내는 `damage_buffer`는 pending(이번 프레임에 화면에서
   바뀐 것). 로그 `tk> draw … dirty=` 는 repaint, damage가 다르면 끝에 ` damage=x,y,w,h`. repaint 셈은 순수 함수로 호스트 검사(버퍼 둘 번갈아 흉내 —
   여러 번 바꾼 뒤 각 버퍼 = 통째 그림).
6. 애니메이션(R-CA-3): 속성 넷(위치 · 크기 · 불투명도 · 색)을 같은 틀로. 시계는 툴킷의 monotonic, `tick(now_ns)`은 시각을 인자로(호스트 검사가 주입).
   이징 `easeOutCubic`(기본) · `linear`. done에서 tick → maybeDraw, 활성 목록이 비면 frame 없음. 줄 `tk> anim start prop= dur=` · `tk> anim end frames=N`.
7. 스택(R-CA-4): axis · spacing · padding · align(start · center · end · fill), 자식마다 size · flex · cross. 정수 반올림, 누적 오차는 마지막 자식이.
8. 토큰(R-CA-5): `TK_SPACE_S 4` · `TK_SPACE_L 16` · `TK_PADDING 16` · `TK_RADIUS_S 6` · `TK_FONT_TITLE 17`, 색 `TK_SURFACE` · `TK_TEXT_DIM` · `TK_SEPARATOR` ·
   `TK_SELECTION`(값은 단계 B가 셸 색과 겹치지 않게 고른다 — `tk_test`에 "앱 색 ∩ 셸 색 = ∅" comptime 검사). `tk.tokens`로 다시 내보내 위젯은 theme을 직접 안 부른다.
9. 데모: 단계 A는 같은 그림을 트리로(좌표 · 색이 같으면 된다 — 바이트까지는 안 바란다). 단계 B는 스택으로 배치하고 키 `space`가 `TK_TEXT` 면(64 × 32쯤)의
   불투명도를 0 → 1로(`--anim-ms`, 체인은 linear 3000).
10. 체인 toolkit 판정 7~9: 7 `space` → `tk> anim start` 뒤 screendump A의 면 가운데 세 채널이 바탕과 끝 색 사이(같지 않음), 길이 + 여유 뒤 screendump B가 끝 색.
    8 애니메이션 프레임의 서버 `wl> blit … w= h=`가 그 면의 사각형(통째 아님). 9 애니메이션 뒤 idle 2초 commit 늘지 않음, 데모 로그 셈 갱신.
    측정은 셸에서 `grep 'tk> draw' /tmp/tk.log > /dev/ttyS0`로 시리얼에 꺼내 체인이 참고 줄로 남긴다(판정 아님). 막히면 임시 스크립트로.

## 할 일

1. (A) CG 백엔드 · 빠른 길 · clip 임시 판 · translate · 누적 알파. 호스트 검사(부분 = 통째 바이트 비교, 무작위 속성 바꾸기 여러 번).
2. (A) CA 레이어 트리 · setter의 더티 · 그리기 걷기. 호스트 검사(더티 = 옛 ∪ 새, masks · hidden).
3. (A) 창 층의 더티 · 버퍼 나이 · damage 사각형 · `Frame.clip`, 데모를 트리로. 체인 toolkit 판정 1~6 그대로.
4. (B) 애니메이션 · 스택 · 토큰(+ 겹침 검사) · `tk.tokens`.
5. (B) 데모의 스택 배치 · `space` 애니메이션 · `--anim-ms`, 판정 7~9, 체인 머리 주석.
6. (B) `measurements.md` 108(조사 7절의 문장 꼴, 게스트 · 네이티브 숫자).
7. lead: 단계마다 대조 · commit, 끝에 루트 게이트(36).

## 판정

- 호스트 검사, 체인 toolkit 두 번 연속 · terminal PASS, 루트 게이트 36/36, verify mismatch 0.

## plan에서 실측할 것

1. 게스트의 `tk> draw us=` 통째 · 애니메이션 한 프레임과 같은 프레임의 서버 `wl> blit us=`, 게스트/네이티브 비. 2. 애니메이션 하나의 프레임 수와 간격
(16 ms 하한에 붙는가). 3. 버퍼 나이가 실제로 2로 도는가. 4. 부분 그리기 뒤 좌표 색 판정이 그대로인가. 5. 호스트 검사의 MaxRSS. 6. `/dev/ttyS0`로 꺼낸 줄이
쪼개지지 않는가.

## 결과

구현은 `tk-m1`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `d3eaa34`: 층을 디렉터리 · 모듈로(`window/` → `cg/` → `ca/`, 그리고 순수 값 `geom`). 위 층 파일을 경로로 부르면 두 모듈에 들어 컴파일 오류 —
   그것이 층 경계를 막는 장치다. CG `Painter`(fillRect 빠른 길 · fillRoundedRect · drawGlyphs · pushClip/popClip · translate, 프레임 clip이 판 전체가 아니면
   임시 판 + 행 복사, masks clip을 넘는 둥근 사각형은 작은 임시 판 + `compositeOver`), CA `Layer` · `Tree`(setter의 더티 = 옛 ∪ 새, 바깥 반올림), 창 층의
   `invalidate(rect)` · `age.zig`(history 4) · `damage_buffer` = pending · `run` 루프(앱 콜백 안의 여러 바꿈이 한 프레임). 데모를 트리로 — 결정 4의 PNG가 TK-M0과
   픽셀 차 0. ReleaseSafe 누수 보고가 셸을 채우던 것(TK-M0부터)을 `deinit`으로 고쳤다.
2. 호스트 검사: 무작위 트리 여섯 × 바꾸기 60(부분 다시 그리기 222번) · 버퍼 둘 번갈아 197프레임에서 부분 = 통째 다름 0. 일부러 망가뜨린 셋(history 무시 ·
   겹친 clip 무시 · 길 선택에 프레임 clip을 섞음)이 모두 다름을 냈다 — 검사가 잡는다. 체인 단독 toolkit 두 번 · terminal PASS.
3. 실측(게스트, `space`로 면 불투명도 0 ↔ 1 일곱 번): 첫 그림 65 ms(글리프 굽기), 첫 `space`는 새 버퍼라 통째 15.4 ms(`damage=24,300,64,32`), 그 뒤 여섯 번
   `age=2` · `dirty=24,300,64,32` · 120~952 µs. 서버 `wl> blit x=668 y=320 w=64 h=32` 일곱 줄 — 면의 화면 사각형 그대로. 데모 VmRSS 10 MB. 호스트 검사 MaxRSS 476 MB.
4. 단계 A에서 달라진 것: 창 층이 CG를 모른다(버퍼마다 z2d Surface를 안 든다 — design 결정 9 문장을 고쳤다), `Handler.resize`, 로그에 ` age=N`, 데모의 면(단계 B가
   애니메이션으로). `tk>` 줄 꺼내기는 `/dev/console`(체인의 `type_text`가 대문자 `S`를 못 친다).
