# TK-M6 — 툴킷 쪽 메뉴 모델 · 단축키 표 하나 · 미리보기(TK의 마지막 milestone)

Date: 2026-11-21
Design: `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 2 · 16 · 17, milestone 표 TK-M6), 요구사항 결정 9 · 13, R-KIT-7 · 8 · 9, R-FM-1 · 2 · 5 · 7, R-CG-3, R-TXT-1, 녹화 C
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `tk-m6`, 세션 scratchpad `tk6/research.md` — HEAD `08fb7fe`, 읽기만 한 조사)

- 녹화 C의 장면 일곱 가운데 다섯은 toolkit 체인 판정 15~25가 이미 돈다(column에 뜸 15 · 방향키 16 · `Cmd+L` 한글 21 · 22 · `Cmd+K` 25 · `Cmd+C` → 셸 `Cmd+V` 20).
  남은 것은 "메뉴 바에 File · Edit · View · Go"이고, "선택 강조가 짧게 움직인다"는 덤프 하나로 안 보인다(사람 녹화의 몫). 녹화 A · B도 사람이 찍는 일로 남아 있다.
- 지금 단축키는 두 군데에 박혀 있다: `tars-files`의 `unhandled`(`Cmd+L` `F` `K` `C`)와 `TextField.key`의 Super 갈래(`Cmd+A` `C` `X` `V` `Z`). 필드가 포커스면 `Cmd+C`를
  필드가 늘 먹어 앱의 경로 복사가 안 온다. 맨 `Space`는 아무도 안 먹는다.
- 서버가 먹는 Cmd 표(`Cmd+D W [ ] R Q T 1~9` · `Cmd+Shift+D` · `Cmd+Shift+/` 등)는 앱에 안 온다. 메뉴가 열린 동안 앱에는 수정키만 오고, 모델을 다시 commit하면 열린
  메뉴가 닫힌다(`why=model`). `opened`/`closed` 이벤트는 없다.
- 툴킷은 `tars_menu_manager_v1`을 판 1로 bind하고 객체를 버린다. toplevel · 첫 commit은 `Window.open` 안에서 끝난다. 테스트 클라이언트의 `sendMenu`가 판 2의 꼴이다.
- 서버 `menubar.keyName` 표와 툴킷의 evdev 코드 · mask는 같은 뜻이다(L 38 · F 33 · K 37 · C 46 …). 툴킷의 글자 키 상수는 세 파일에 흩어져 있다.
- 미리보기는 지금 `TK_SURFACE` 판에 이름 한 줄. 판정 15가 미리보기 판 (1100, 400) 140 × 300이 한 색인지 본다. CG에 이미지 함수가 없다(`Canvas.compositeOver`뿐).
- terminal의 디코더는 stb_image(PNG만, JPEG 꺼짐)와 ghostty-vt 모양에 묶인 `png.zig`다. 툴킷은 이미 stb_truetype을 terminal의 vendor 헤더로 빌려 컴파일한다.
- 창 층에 "N ms 뒤 한 번" 타이머가 없다(키 반복용 timerfd 하나). 로딩은 `Handler.idle`.
- initrd에 `base64`가 없고 `type_text`는 대문자 · `\`를 못 친다 — 게스트에서 PNG 바이트를 손으로 만드는 길은 느리다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `tk-m6`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit · TK 마감. 루트 게이트는 단계 A 뒤와 B 뒤.

- 단계 A — 메뉴 모델 · 단축키 표 · 창 층 판 2: 할 일 1~5.
- 단계 B — 미리보기: 할 일 6~9.

## 끝나는 조건(design의 "녹화 C"를 바꿔 적는다)

toolkit 체인에서 `tars-files`가 바에 `File · Edit · View · Go`를 보이고(`menu> bar … titles=File,Edit,View,Go`와 위 띠 잉크), 키로 연 메뉴의 항목과 그 단축키가 같은
동작 줄을 내고, 텍스트 · PNG · JPEG 미리보기가 좌표 색으로 보인다. 녹화 C 자체(사람 녹화)는 HANDOFF의 남은 작업으로 녹화 B와 함께 둔다.

## 착수 전에 확정한 것

1. 순수 값 모듈 `tk_menu`(`toolkit/src/menu.zig`, 층 밖 — 창 층이 직렬화하고 kit이 맞춘다): `Item { action: u32, label, mods: input.Mods, key: u32 }` · 구분선 ·
   `Menu { title, entries }` · `Model`(고정 배열, 상한은 서버와 같은 수 — 메뉴 8 · 메뉴당 32 · 전체 128 · 글 64바이트 · UTF-8, terminal 파일은 import하지 않는다).
   `check()`가 서버와 같은 넷을 돌려준다. `match(model, mods, code)`(caps를 뺀 수정키 넷과 코드, 코드 0은 안 맞음) · `maskOf`. 프로토콜의 id = action 값.
   비활성은 모델이 들지 않고 보낼 때 셈한 flags.
2. action과 responder chain(macOS 꼴): kit `VTable`에 `perform(ctx, action) bool` · `validate(ctx, action) ?bool`(null = 모름, 부모에게). 표준 action 다섯 `undo` · `cut` ·
   `copy` · `paste` · `select_all`은 kit이 예약하고 `TextField`가 구현한다 — 필드의 Super 갈래 `A` `C` `X` `V` `Z`를 지운다(`Cmd+←` `→`는 keyDown에 남는다). 앱의 동작은
   루트 뷰나 `Root`의 앱 훅이 구현한다. `copy`는 필드가 포커스면 필드, 아니면 앱의 경로 복사 — 항목 하나 · 단축키 하나(R-KIT-9).
3. 키의 순서(`Root`): (가) Super가 섞인 키 → 메뉴 표 `match` → 맞으면 `validate`를 chain으로 묻고 활성이면 `perform`을 chain으로, 비활성이면 먹고 끝. 안 맞으면 (나).
   (나) 지금 chain(first responder → … → Tab). (다) chain이 다 거절한 수정키 없는 키는 메뉴 표를 본다(`Space` — 필드에서는 글자, 리스트에서는 미리보기).
   검색 모드의 `↑` `↓` 넘김은 `unhandled`에 남는다.
4. 모델이 없는 `Root`(데모)는 kit의 기본 표(표준 Edit 다섯의 Super+글자)를 쓴다 — 필드만 쓰는 앱이 안 깨진다. kit이 `menu.standardEdit` 조각을 준다.
5. `activated(id)` → 창 층이 `input.Event.menu: u32` → `Root`가 (가)의 "맞은 뒤"와 같은 함수(`validate` → `perform`). 비활성인데 온 id는 버린다.
   줄 `tk> action name= via=key|menu` — 같은 동작임을 체인이 같은 줄로 본다.
6. 비활성의 다시 셈 · commit: 입력 이벤트(키 누름 · 버튼 · 창 포커스 · ime · menu) 하나를 처리한 뒤 모든 항목의 `validate`를 다시 묻고 지난번 flags와 다를 때만 전체를
   다시 보낸다. 수정키만의 키 이벤트와 idle에서는 셈하지 않는다 — 메뉴가 열린 동안 앱에 오는 것은 수정키뿐이라 열린 메뉴가 앱의 commit으로 닫히지 않는다.
   값이 낡는 틈은 다음 입력에서 맞춰지고 `activated`는 다시 `validate`한다.
7. 창 층: build · `MENU_MANAGER_VERSION`을 2로, manager를 들고 있는다. `Window.open`의 선택 인자로 모델을 받아 toplevel 뒤 · 첫 `surface.commit()` 앞에 `get_menu` + 모델 +
   commit. 그 뒤는 `sendMenu`(매번 전체). `check()` 실패면 보내지 않고 `tk> menu error=`(연결을 잃지 않는다). 서버가 판 1이거나 global이 없으면 `tk> menu unsupported`로
   조용히 건너뛴다(원래 모드는 그대로). 줄 `tk> menu sent menus= items=` · `tk> menu activated id=`.
8. 글자 키 코드 상수를 `input.zig` 한 자리에(`KEY_A` … `KEY_Z`) — 흩어진 셋을 지운다. 호스트 검사: 모델의 모든 단축키 키가 "서버가 이름을 그리는 집합"에 들고,
   서버 chord 목록과 안 겹친다(`quit`의 `Cmd+Q`만 "서버 몫"으로 허용 — 목록의 출처는 주석에).
9. `tars-files` 메뉴(제목은 영문, 항목은 한글):
   File[끝내기 `Cmd+Q` — 표시만, 키는 서버가 close로. 메뉴로 고르면 창을 닫는다], Edit[되돌리기 `Cmd+Z` · 구분선 · 오려두기 `Cmd+X` · 복사 `Cmd+C` · 붙여넣기 `Cmd+V` ·
   전체 선택 `Cmd+A` · 구분선 · 찾기 `Cmd+F`], View[미리보기 `Space` · 새로 고침], Go[경로로 가기… `Cmd+L` · 검색… `Cmd+K`].
   활성: undo = 필드 + 스냅숏, cut = 필드 + 선택, copy = 필드면 선택 있을 때 · 아니면 포커스 열에 선택 항목, paste · select_all = 필드 포커스, 나머지는 늘.
10. 디코더는 툴킷이 따로 컴파일한다(design 결정 2 — terminal 것을 나누지 않는다): 헤더는 `../terminal/vendor/stb_image.h`, 구현 `toolkit/src/cg/stb_image_impl.c`
    (`STBI_ONLY_PNG` + `STBI_ONLY_JPEG` · `NO_STDIO` · `NO_LINEAR` · `NO_HDR` · `STBI_MAX_DIMENSIONS 8192`), 감싸개 `cg/image.zig`(extern 직접 선언, `decode(alloc, bytes)`).
    상한: 입력 16 MiB · 한 변 8192(요구사항 결정 13) · 넓이 × 4 ≤ 64 MiB(새 값 — 머리로 먼저 본다). 넘으면 아이콘 + "너무 큼".
    디코드 결과는 곧장 미리보기 크기로 줄여 premultiplied ARGB 작은 판만 들고 원본은 놓는다. 축소는 박스(넓이 평균), 확대는 하지 않는다(1:1 가운데).
11. `Painter.drawImage(view, x, y)` — clip 스택과 translate를 따른다. 배율 변환은 CG가 아니라 미리보기 쪽.
12. 미리보기의 판정 순서: 바이트 머리(PNG · JPEG) → 이미지, 아니면 일반 파일 · 크기 ≤ 1 MiB · 앞 8 KiB에 NUL 없음 → 텍스트, 그 밖 · 디렉터리는 아이콘.
    텍스트는 앞 16 KiB만 읽어 UTF-8로 `\n`마다 `layout.wrap`, 판 높이를 넘으면 멈춤, 탭은 공백 넷, 스크롤 없음. 아이콘은 z2d 도형(문서 · 폴더) + 이름 · 종류 · 크기 한 줄.
    디렉터리의 항목 수는 안 센다. design 결정 14의 자동 따라가기는 하지 않는다(녹화 C에 없다 — carryover).
13. 미리보기를 레이어로 나눈다(이름 · 본문/그림/아이콘) — 안 바뀐 레이어는 안 그린다. 로딩: 선택이 바뀌면 요청만 적고 idle 한 조각에서 지금 선택과 같을 때만 읽기 +
    디코드 + 축소(낡은 요청은 버림). 디코드 한 장은 못 쪼갠다 — carryover. 줄 `tk> preview kind=text|png|jpeg|icon …`.
14. `Space` = 미리보기 판 토글(분할 뷰의 오른쪽 폭 0 ↔ 200), 시작값은 켜짐. View › 미리보기와 같은 action.
15. R-FM-7의 원칙(design 결정 17에): 파서는 파일을 열지 않고 상한 안의 바이트만 받는 순수 함수이고 크기는 머리로 먼저 거른다. 그 함수 경계가 격리의 자리 — 나중에
    별도 프로세스로 옮겨도 부르는 쪽이 안 바뀐다. 구현은 뒤로.
16. 시험 그림: `tars-tk-demo --write-samples DIR`이 미리 구운 바이트 배열(작은 PNG 16 × 16 단색 · baseline JPEG 32 × 32 단색 — 만든 명령과 sha256을 주석에)과 이진 파일
    하나를 쓴다. initrd에 시험 그림 파일을 넣지 않는다. 그림 색은 테마 · 다른 체인 색과 안 겹치는 값.
17. 체인 toolkit: 다섯째 실행 `tars-files /tmp/tkp > /tmp/tk7.log`(판정 25 뒤 — 앞 판정의 숫자를 안 건드린다). 좌표는 단계가 실제 덤프로 정한다.
    - 26(A) 바: `menu> bar id=ID name=tars-files titles=File,Edit,View,Go` · `tk> menu sent menus=4 items=13` · 위 띠의 `MENU_NAME` · `MENU_FG` 잉크.
    - 27(A) 단축키 = 메뉴: `Cmd+L` → `tk> action name=goto via=key` · 바 열림, Esc. `Cmd+Shift+/` → `→ → →` → Enter → `menu> activate` · `tk> menu activated id=` ·
      `tk> action name=goto via=menu` · 바 열림(둘째). `menu> close why=model` 0.
    - 28(A) 복사의 두 주인: 리스트 포커스의 `Cmd+C` → `tk> copy path=`, 메뉴 Edit › 복사 → 같은 줄 하나 더.
    - 29(A) 비활성: 리스트 포커스에서 Edit › 붙여넣기에 Enter → `menu> activate`가 늘지 않음, Esc. 키 `Cmd+V` → `tk> paste` · `tk> action` 줄 없음.
    - 30(B) 텍스트: `t.txt` → `tk> preview kind=text … lines=` · 판 위쪽 상자의 글자 잉크(한글 줄 포함).
    - 31(B) PNG: `tk> preview kind=png w=16 h=16` · 그 16 × 16 자리가 그림 색 한 가지.
    - 32(B) JPEG: `kind=jpeg w=32 h=32` · 상자의 최빈 색이 기대 색 ±4.
    - 33(B) 그 밖: 이진 → `kind=icon reason=binary`, 디렉터리 → `reason=dir` · 아이콘 잉크.
    - 34(B) Space: `tk> action name=preview via=key` · 미리보기 판이 사라짐 · 다시 `Space`로 돌아옴.
    판정 15~25는 한 글자도 안 바꾼다 — 판정 15의 미리보기 상자(창 y 380..680)에 새 그림 · 글이 닿지 않게 자리를 잡는다.

## 할 일

1. (A) `menu.zig`(확정 1) · `input.zig`의 키 상수와 `Event.menu`(확정 8).
2. (A) kit: `perform` · `validate` · 표준 action · `Root`의 키 순서 · 기본 표 · 다시 셈(확정 2~6), `TextField`의 Super 갈래를 action으로.
3. (A) 창 층 판 2 · `get_menu` · 보내기 · `activated`(확정 7).
4. (A) `tars-files`의 모델과 action(확정 9) — `unhandled`의 Cmd 갈래를 지운다. `docs/help/desk.md`.
5. (A) 호스트 검사(모델 → 요청 열 · 상한의 경계 · `match` · mask 왕복 · chain 순서 · 다시 셈 규칙 · 모델의 키가 서버 이름 집합 안 · chord와 안 겹침)와 판정 26~29.
6. (B) `cg/image.zig` · 툴킷 stb_image 구현 · `Painter.drawImage` · 박스 축소(확정 10 · 11). 호스트 검사(작은 PNG · JPEG 표본, 상한 셋, 축소의 평균, 인터레이스 PNG ·
   progressive JPEG · 16비트 PNG · 깨진 바이트가 죽지 않음).
7. (B) 미리보기 뷰(확정 12~14) · `Space` · 데모 `--write-samples`(확정 16).
8. (B) 판정 30~34, `measurements.md` 114(디코드 · 축소 · 텍스트 나누기 시간), `docs/help/desk.md`.
9. lead: 단계마다 대조 · commit · 루트 게이트(36), 끝에 TK 마감(design Status · `docs/guides/completed.md` · roadmap · carryover · 기억 · HANDOFF).

## 판정

- 호스트 검사, `make quick`, 체인 toolkit 두 번 연속 · terminal · wayland PASS, 루트 게이트 36/36, verify mismatch 0.

## plan에서 실측할 것

1. 게스트의 PNG · JPEG 디코드와 박스 축소 시간(체인 그림과 큰 JPEG 하나). 2. 텍스트 미리보기 한 장의 `wrap` + 그리기 시간과 줄 수. 3. JPEG를 켠 뒤 `tars-files`
바이너리 크기와 호스트 검사의 시간 · 메모리. 4. 메뉴 모델이 첫 그림 시간에 주는 차이와 서버 `wl> menu id= menus=4 items=13`. 5. 체인 한 판의 `tk> menu sent` 줄 수.
6. `menu activated` 뒤의 `copyText`로 셸 `Cmd+V`가 되는가. 7. 미리보기가 붙은 뒤 `↓` 한 번의 더티와 시간. 8. 체인 toolkit 시간과 루트 게이트 lane(지금 157초).
9. 판정 15~25가 미리보기 · 바와 함께 그대로인가. 10. stb_image가 16비트 · 인터레이스 PNG · progressive · CMYK JPEG를 어떻게 다루는가.

## 결과

구현은 `tk-m6`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `5339440`: 순수 모듈 `menu.zig`(`tk_menu` — 모델 · `check` · `match` · `maskOf` · `emit` · 표준 action 다섯 · `standard_edit` · 기본 표) · kit의
   `VTable.perform` · `validate` · `Root`의 키 순서와 다시 셈 · `TextField`의 Super 갈래 `A C X V Z`를 action으로 · 창 층 판 2(`Options{menu, disabled}` · `startMenu` ·
   `sendMenu` · `menuListener`) · `files/menus.zig`(단축키 정의가 이 표 하나) · `tars-files`의 `rootValidate` · `rootPerform` · `Space` 토글 · `docs/help/desk.md` ·
   판정 26~29. 서버는 고치지 않았다. 체인 toolkit 두 번 · terminal · wayland PASS.
   판정의 실제 값: 26 `wl> menu id=7 menus=4 items=13` · `menu> bar id=7 name=tars-files titles=File,Edit,View,Go` · 이름 잉크 161 · 제목 잉크 72 + 79 + 79 + 45 = 275.
   27 `tk> action name=goto via=key` → 메뉴 `→ → →` Enter → `menu> activate id=7 item=20` · `tk> menu activated id=20` · `tk> action name=goto via=menu` · 바 열림 둘.
   28 `tk> copy path=/tmp/tkp/d` 두 줄(키 하나 · 메뉴 하나). 29 붙여넣기 행의 `687484`(흐림) 301 · 그 칸을 눌러도 `menu> activate` 0 · 키 `Cmd+V`에 `tk> paste` 0.
   `menu> close why=model` 0. 판정 1~25는 그대로(넷째 앱의 `Cmd+C` · `L` · `A` · `V` · `F` · `K`가 이제 메뉴 표 → action 길을 지나 같은 줄을 낸다 — 회귀 검사).
   호스트 검사 덩어리 18(46개): 모델 → 요청 열, 상한의 경계, `match`, mask 왕복, `tars-files` 모델의 키가 서버 이름 집합 안 · chord와는 `Cmd+Q`만, chain 순서, 다시 셈.
   plan과 달라진 것: (가) 모델 없는 Root의 기본 표는 chain의 누군가가 그 action을 알 때만 단축키(필드 없는 데모의 `Cmd+A`는 지금처럼 `unhandled`). (나) 다시 셈의 계기에서
   ime를 뺐다 — 서버가 메뉴를 열며 앱 조합을 확정해 보내는 `ime` 하나로 비트가 바뀌면 막 연 메뉴가 `why=model`로 닫힌다. (다) `Item.name`(로그 이름). (라) 모델을
   `files/menus.zig`로(호스트 검사가 같은 파일을 부른다). (마) `Space` 토글을 단계 A에(항목이 있는데 동작이 없으면 안 된다). (바) 판정 29의 비활성 칸은 클릭으로
   (서버의 `↓`가 비활성을 건너뛰어 키로는 못 간다).
   첫 체인 판은 FAIL이었다 — 판정 29의 줄 셈 패턴이 앞 판정의 열기까지 센 판정 쪽 잘못(코드는 그대로).
   lead의 화면 판정: 4배 덤프 — 바 `tars-files  File  Edit  View  Go`, Edit 메뉴의 흐린 넷 · 밝은 복사 · 찾기.
   실측: 체인 한 판의 `tk> menu sent` 5줄(열 때 1 + 경로 바 여닫기 둘 × 2). `menu activated` 뒤의 `copyText`가 셸 클립보드에 닿는다. 체인 toolkit 단독 326 · 329초.
   루트 게이트 36/36 첫 판(`out/gate-logs/20261121-132443`, toolkit lane 182초), verify mismatch 0.
