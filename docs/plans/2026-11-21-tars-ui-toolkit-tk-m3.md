# TK-M3 — column view · 분할 뷰 · `tars-files` 뼈대(로딩 · 안정 선택)

Date: 2026-11-21
Design: `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 1 · 14, milestone 표 TK-M3), 요구사항 R-KIT-3 · 5, R-FM-1 · 3 · 6 · 8, R-ARCH-3 · 4, 녹화 C
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `tk-m3`, 세션 scratchpad `tk3/research.md` — HEAD `3820666`, 개발 컨테이너 aarch64 · tmpfs 벤치)

- `kit.List`는 `←` `→`를 안 받아 이미 부모 뷰로 올라간다. `sync()`는 오프셋만 자르고 `selected`는 안 자르며, 같은 오프셋에서 내용만 바뀌면 다시 안 그린다.
  `select()`는 늘 줄을 내고 애니메이션한다. 선택 알림 자리는 `hook` 하나(로그가 쓴다).
- 레이어 · 뷰를 지우는 API가 없다(`Tree.create`만, `View.removeChild` 없음) — 열을 만들고 버리면 샌다.
- 창 층 `run`의 poll은 시간 제한 −1이고 앱이 끼울 fd도 idle 콜백도 없다. `Handler.tick`은 그릴 수 있을 때만 불린다.
- 10만 파일 디렉터리(네이티브): getdents 32 KiB 124번 9.1~9.6 ms(첫 조각 818항목 0.075 ms), 자연 정렬 14.2~14.5 ms, 전부 fstatat 34 ms. tmpfs의 getdents 순서는
  이름순이 아니다. 이름 풀 1.6 MB.
- `tars-tk-demo`가 initrd에 실리는 길: `toolkit/build.zig` → `terminal/prepare.sh` → `kernel/make_initrd.sh`(cp · `OWN_BINS` · `copy_lib_deps`) · `initrd-criteria.md`.
- Strata의 `docs/keyboard-navigation.md`는 이 저장소에 없다 — 방향키의 뜻은 녹화 C와 design milestone 표가 근거다.
- 체인 toolkit lane은 루트 게이트에서 71초, `type_text`는 소문자 · 숫자 · 공백 · `- / . > & ( )`만 친다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `tk-m3`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — 툴킷(화면 변화 0, 체인 판정 1~14 그대로): 할 일 1~4.
- 단계 B — `tars-files`: 할 일 5~9.

## 착수 전에 확정한 것

1. 자리: `tars-files`의 소스는 `toolkit/src/files/`(`main.zig` 앱 · `model.zig` 순수 모델 · `dir.zig` getdents 소스), `toolkit/build.zig`의 둘째 exe. 앱은 `tk` 모듈만
   import한다(경계는 import가 지킨다). 요구사항 결정 12의 `apps/files/`는 design 결정 14가 고친다.
2. 열 모델은 명시 모델이다. 처음엔 시작 경로의 열 하나. `→` · Enter: 포커스 열의 선택이 디렉터리면 그 오른쪽 열들을 버리고 새 열을 붙여 로딩하고 포커스를 새 열로.
   디렉터리가 아니면 아무 일 없음(받았다고 답해 체인을 멈춘다). `←`: 포커스를 왼쪽 열로, 오른쪽 열은 남긴다. 포커스 열의 선택이 바뀌면(키 · 클릭) 그 오른쪽 열을 버린다.
   첫 열의 `←`는 아무 일 없음. 부모 경로로 올라가는 키와 자동 따라가기(선택만으로 오른쪽 열)는 뒤로(미리보기가 오는 TK-M6에서 다시 본다).
3. `kit.ColumnView`: 컨테이너 레이어(masks · 바탕) → 내용 레이어(x = −scroll) → 열마다 `List` 컨테이너 + 오른쪽 1 px 구분선 레이어(`TK_SEPARATOR`).
   열 폭 토큰 `size.column` = 200, 구분선 1 — 열 i의 x = i × 201. 끌기 없음. 데이터는 `ColumnSource`(열마다 `ListSource`와 "이 행이 열리는가")로 받는다 — kit은 파일을 모른다.
4. 열은 풀로 다시 쓴다(최대 깊이 32, 넘으면 `→`를 거절). 버린 열은 레이어를 `removeChild` · hidden, 다시 쓸 때 `List.reset(source)`. `Tree.destroy`는 만들지 않는다.
   `View.removeChild`를 더하고, 버린 뷰가 first responder면 Root가 포커스 열로 옮긴다.
5. 가로 스크롤: 포커스 열이 보이게 최소만, 열 경계에 맞춘다. 애니메이션 없음(TCG에서 리스트 통째가 4.7~27.7 ms — carryover).
6. Tab: column view는 포커스 자리 하나다 — 포커스 열만 `acceptsFocus`. `←` `→` Enter는 `ColumnView.keyDown`이 수정키 없을 때만 받는다.
7. List에 더할 것: `reload()`(선택 · 오프셋 자르기, 글자 다시 그림, 줄 없음) · `restore(index, offset)`(애니메이션 · 줄 없음 — 안정 선택의 자리) · `reset(source)` ·
   선택 바뀜 delegate(로그 hook과 따로).
8. `kit.SplitView`: 가로 둘(앞 신축 · 뒤 고정 폭), 사이 1 px 구분선, 끌기 · 접기 없음. 배치 뒤 자식에 알린다. `tars-files`는 column view | 미리보기 자리(토큰
   `size.preview` = 200, `TK_SURFACE` 판에 선택 항목 이름 한 줄 `TK_TEXT_DIM`). 미리보기 내용은 TK-M6.
9. 로딩(R-FM-3)은 메인 루프의 조각 읽기다(스레드 아님). 창 층에 `Handler.idle: ?fn(ctx) bool`(참 = 할 일이 더 있다) — `run`이 `dispatchPending` · 반복 뒤에 부르고 참이면
   다음 poll의 시간 제한을 0으로. idle 한 번 = getdents 32 KiB 한 번 + 그 조각 정렬 + 정렬된 배열에 병합. 첫 조각이 오면 바로 보인다. 취소 = dir fd를 닫고 세대를 올림.
   로딩 중인 열이 여럿이면 포커스 열 먼저. 0행일 때 열 가운데 한 줄: 로딩 중 "불러오는 중…", 끝났는데 비면 "비어 있음", 못 열면 "열 수 없음"(`TK_TEXT_DIM`).
10. 첫 로딩의 선택: 사용자가 그 열의 선택을 건드리지 않았으면 로딩이 끝날 때까지 늘 0행, 건드렸으면 그 이름을 따라간다.
11. 모델: `Entry { name, kind: dir | file }`, 정렬은 디렉터리 먼저 · 자연 정렬(숫자 덩어리는 값, ASCII 대소문자 무시, 그 밖은 UTF-8 바이트, 같으면 바이트 순 — 전순서).
    숨김(`.` 시작) · `.` · `..`는 뺀다. kind는 `d_type`, 링크와 `DT_UNKNOWN`만 `fstatat`으로 따라가 정한다(깨진 링크는 파일). `DirSource` 인터페이스
    (`open` · `next` · `close`)를 모델이 받고 호스트 검사는 메모리 표를 꽂는다. 시작 경로는 `argv[1]` → `$HOME` → `/`.
12. 안정 선택(R-FM-6): 열쇠는 이름. 갱신은 같은 경로를 새로 다 읽은 뒤 바꿔 끼운다(읽는 동안 옛 목록). 옛 선택 이름을 이분 탐색 — 있으면 그 색인, 없으면 삽입 자리
    (끝을 넘으면 마지막, 0행이면 선택 없음). 스크롤은 선택 행의 화면 위치를 지킨다(선택이 화면 밖이었으면 오프셋 그대로, 자름만). 선택이 디렉터리였고 이름이 남았으면
    오른쪽 열을 유지(그 열도 갱신), 사라졌으면 버린다. 계기는 창이 키보드 포커스를 다시 얻을 때 — 보이는 열 전부. 손 키 · inotify는 뒤로.
13. 행 그리기: 왼쪽 16에서 이름(13 px `TK_TEXT`), 디렉터리는 오른쪽 끝(막대 앞)에 `›`(U+203A, `TK_TEXT_DIM` — Pretendard에 없으면 z2d 삼각형). 넘침은 masks, 가운데 생략은 TK-M4.
14. 로그: `tk> files path=` · `tk> load path= n= chunks= first_us= all_us= state=done|cancelled|error` · `tk> columns n= focus= scroll=`(열 바뀜마다) ·
    `tk> column i= path= count= sel= name=`(열의 선택이 바뀔 때) · `tk> refresh path= name= before= after=`(사라졌으면 끝에 ` gone=1`). 열 뷰 이름 `col0`….
15. 체인 toolkit에 판정 15~18을 더한다(새 체인 없음 — CHAINS 36 그대로). 게스트 트리 `mkdir -p /tmp/tkf/a/b/c /tmp/tkf/z` · `touch /tmp/tkf/m.txt /tmp/tkf/.h
    /tmp/tkf/a/b/x.txt`, `tars-files /tmp/tkf > /tmp/tk3.log`.
    - 15 시작: 첫 열 행 0(`a`)이 `TK_SELECTION`, 행 셋에 잉크 · 넷째 행 바탕(숨김이 빠졌다), 미리보기 판 `TK_SURFACE`, 분할 구분선 `TK_SEPARATOR`, `tk> column i=0 … count=3 sel=0 name=a`.
    - 16 `→` `→` `←`(design의 끝나는 조건): `tk> columns n=3 focus=1 scroll=201`, 화면의 둘째 열 행 0이 `TK_SELECTION`, 셋째 열 행 0이 `TK_SELECTION_INACTIVE`, 열 사이 구분선.
    - 17 안정 선택: 셸로 가 `mkdir /tmp/tkf/a/0`, 앱으로 돌아옴 → 둘째 열이 `0` `b`가 되고 선택은 `b`(행 1), 셋째 열이 남는다, `tk> refresh path=/tmp/tkf/a name=b before=0 after=1`.
      지움 갈래는 호스트 표로만.
    - 18 스트리밍: 큰 디렉터리에서 `tk> load … state=done`과 첫 그림 줄이 `all_us`보다 먼저, 행 0의 레이블 잉크. 항목 수는 단계 B가 게스트의 만들기 시간을 재고 정한다
      (기본 1만, 10만은 측정 전용 임시 스크립트).

## 할 일

1. (A) List: `reload` · `restore` · `reset` · delegate. `View.removeChild`와 Root의 first responder 정리.
2. (A) `kit/column.zig`(확정 2~6) · `kit/split.zig`(확정 8) · 토큰 `size.column` · `size.preview`.
3. (A) 창 층 `Handler.idle`과 poll 시간 제한(확정 9의 창 층 몫).
4. (A) 호스트 검사: column view 표(가짜 소스 — `→ → ←`의 열 수 · 포커스 · 스크롤, 파일에서 `→`, 첫 열에서 `←`, 선택 바뀜이 오른쪽 열을 버림, 풀을 수백 번 오가도 레이어 수가
   안 늘어남, 깊이 32의 거절, Tab이 column view를 한 자리로 봄), 분할 뷰 배치 표, 부분 = 통째(가로 스크롤 포함), List의 `reload` · `restore`.
5. (B) `files/model.zig`(정렬 · 조각 병합 · 안정 선택 · `DirSource`)와 호스트 표: 조각 크기 1 · 7 · 전부의 끝 결과가 같다, 숨김 빠짐, 디렉터리 먼저 · 자연 정렬(`a2` < `a10` ·
   대소문자 · 한글), 취소 뒤 옛 조각이 모델을 안 바꾼다, 10만 항목 조각 병합 = 한 번 정렬, 안정 선택 표(위에 더함 · 위에서 지움 · 선택 지움 · 마지막 지움 · 전부 지움 ·
   화면 밖 선택 · 대소문자만 다른 둘 · 로딩 중 병합), 확정 10.
6. (B) `files/dir.zig`(getdents64 · `d_type` · 취소) · `files/main.zig`(분할 뷰 · column view · 미리보기 자리 · 창 포커스 갱신 · 로그 줄).
7. (B) `build.zig` 둘째 exe · `kernel/make_initrd.sh` · `docs/guides/initrd-criteria.md` 한 행.
8. (B) 체인 판정 15~18, 머리 주석. 파이프 끝 `grep -q` 금지.
9. (B) `measurements.md` 110(게스트의 getdents · 정렬 · 병합 · 첫 그림, 가로 스크롤 한 번의 draw, 네이티브와 나란히).
10. lead: 단계마다 대조 · commit, 끝에 루트 게이트(36).

## 판정

- 호스트 검사, `make quick`, 체인 toolkit 두 번 연속 · terminal PASS, 루트 게이트 36/36, verify mismatch 0.

## plan에서 실측할 것

1. 게스트의 getdents 32 KiB 한 번 · 10만 항목 전부 읽기 · 정렬 · 병합 합, 첫 조각에서 첫 그림까지. 2. 게스트의 `seq 1 N | xargs touch` 시간과 10만 항목 `tars-files`의 VmRSS.
3. idle 루프가 도는 동안의 키 응답과 그림 수(poll 0이 그리기를 굶기지 않는가). 4. 가로 스크롤 한 번의 `tk> draw us=`와 서버 blit. 5. 열 셋 · 분할 뷰 화면의 통째 그림(616 ·
1240), `→` 한 번의 더티. 6. 판정 15~18을 더한 체인의 시간(지금 lane 71초). 7. 풀을 수백 번 오간 뒤의 레이어 수 · VmRSS. 8. Pretendard의 `›` 유무와 13 px 모양.

## 결과

구현은 `tk-m3`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `99e8567`: `kit/column.zig`(`ColumnView` · `ColumnSource` · 열 풀 32) · `kit/split.zig` · List의 `reload` · `restore` · `reset` · delegate ·
   `View.removeChild` · `Root.viewRemoved` · 토큰 `size.column` · `size.preview` · 창 층 `Handler.idle`. 화면 변화 0: 체인 toolkit 두 번 · terminal PASS, 판정 1~14의
   문장 그대로. 호스트 검사 덩어리 12 · 13(가짜 트리로 `→ → ←` = n 3 · focus 1 · scroll 201, 풀 300바퀴 뒤 레이어 25 그대로, 깊이 32, 부분 = 통째 300단계).
   plan과 달라진 것: (가) 버린 열은 `removeChild`만(hidden 없음 — 루트에 안 붙은 레이어는 안 그려진다). (나) 가로 스크롤에 상한(열을 버리거나 창이 넓어지면
   마지막 열이 보이는 가장 작은 열 경계로). (다) delegate가 안 바뀐 선택도 알린다 — 포커스가 아닌 열의 선택된 행을 누르면 오른쪽 열을 남긴 채 포커스만.
   (라) column view가 `Root`를 받아 first responder를 직접 옮긴다. (마) "불러오는 중…" 같은 문구는 kit이 아니라 앱이 그린다(kit은 글꼴을 모른다).
   lead가 대조에서 찾은 것: 이미 열린 오른쪽 열로 다시 `→`하면 소스를 새로 열고 오른쪽을 버린다(로딩 취소 콜백과 엇갈리고 그 열의 선택을 잃는다) — 오른쪽 열이
   남아 있으면 늘 지금 선택의 열이므로 포커스만 옮기게 단계 B에서 고친다.
