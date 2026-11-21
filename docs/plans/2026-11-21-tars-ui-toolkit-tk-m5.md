# TK-M5 — 서버 쪽 메뉴 바(`tars_menu_v1` 판 2 · 바와 드롭다운 그리기 · 키 · 포인터 · title/app_id)

Date: 2026-11-21
Design: `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 10 · 11 · 16, milestone 표 TK-M5), 요구사항 결정 1 · 3 · 9, R-KIT-7 · 8 · 9, R-TKW-3, R-KEY-1 · 2,
WY design 결정 42 · 44~47
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `tk-m5`, 세션 scratchpad `tk5/research.md` — HEAD `b0ff7d2`, 읽기만 한 조사)

- 위 여백 20 px(`geometry.MARGIN`)는 지금 통째 경로의 `renderBackdrop`만 칠하고 부분 경로는 안 건드린다. 16 px unifont 한 줄이 y 2..18에 들어간다.
- verify: 그림자 프레임(`verifyFrame`)이 `renderBackdrop` → pane → `renderOverlay`를 그리고 app slot 사각형은 실제 fb에서 옮긴다. 비교는 화면 전체, clip 판정
  (`verifyClips`)은 이 프레임의 clip만 화면 흉내에 복사해 견준다 — 실제 fb에만 바를 그리면 `mismatch rows`, 그리고 clip에 안 넣으면 `mismatch clip`.
- terminal에 pane 위를 덮는 오버레이 장치는 없다. 부분 경로(아래 pane의 dirty 행 · 창의 `.part` blit)와 `presentComposed`의 bs 2 물리 합성이 그림자 위의 그림을 덮는다
  (화살표는 "덮은 뒤 다시 늘리기"로 푼다).
- hidpi: terminal은 논리 그림자에 그리고 present가 정수배로 늘린다 — 바를 논리 그림자에 그리면 2 × 2 블록이 유지된다(hidpi 판정).
- 지금 프로토콜은 manager 판 1에 `destroy`뿐. 서버 `Toplevel`에 title · app_id 칸이 없고 `set_title` · `set_app_id`를 버린다. 툴킷은 판 1로 bind한다.
- R-KEY-1 표에 메뉴를 여는 키가 없다. Apple 칸의 F1 · F2는 밝기가 먼저라 `Ctrl+F2`는 못 쓰고, `F10`은 앱의 맨 키다. 표 밖 Cmd는 셸에서 삼키고 앱에는 Super로 간다.
- 앱 키의 길은 `readKeysApp`이 한 read 배치를 돈 뒤 pane 명령을 처리한다. 서버는 누름을 보낸 키의 뗌만 보낸다(`Held`). 조합 확정의 자리는 `focusTo`.
- 포인터의 첫 누름은 `paneAt`으로 주인을 정하고 위 여백은 `press none`이다(pointer 체인 검사 12가 위 여백의 휠을 본다 — 셸 포커스).
- 기존 덤프가 fb 전체나 띠에서 세는 전용 색: `SEPARATOR` · `STATUS_OFF` · `STATUS_FG` · `MARGIN_COLOR` 등.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `tk-m5`(Opus — 조사도 같은 에이전트)에 세 단계로. lead는 plan · 대조 · 게이트 · commit. 루트 게이트는 단계 B 뒤와 단계 C 뒤(verify가 모든
체인에서 돈다).

- 단계 A — 그리기 없음: 할 일 1~3.
- 단계 B — 닫힌 바: 할 일 4 · 5.
- 단계 C — 열린 메뉴: 할 일 6~9.

## 착수 전에 확정한 것

1. 자리는 (가)(design 결정 11을 닫는다): 위 여백 20 안의 16 px 한 줄, y 2..18, 왼쪽 끝은 `grid_origin.x`(20). 논리 그림자에 그린다. 격자 · configure 크기 · 다른 체인의
   숫자는 그대로. 감추는 조건은 상태 줄과 같다(셸 workspace의 `ws.fullscreen`, app workspace).
2. 셸 pane이 포커스면 바는 비운다(위 여백이 `MARGIN_COLOR` 한 가지 — 셸만 도는 체인과 그 verify가 바이트 그대로). app slot이 포커스면 앱 이름 + 메뉴 제목들,
   모델이 없으면(판 1 · 호환 클라이언트) 이름만.
3. 프로토콜 판 2: manager에 `get_menu(id, toplevel)` since 2(모델은 toplevel마다, 둘째는 `already_constructed`). `tars_menu_v1`의 요청 `reset` · `add_menu(title)` ·
   `add_item(id, label, shortcut_mods, shortcut_key, flags)` · `add_separator` · `commit` · `destroy`, 이벤트 `activated(id)`. pending을 쌓고 commit으로 통째 교체(증분 없음).
   단축키는 구조(mods = `wl_keyboard.modifiers`의 비트, key = evdev 코드, 0이면 없음), flags 비트 `disabled`. 상한: 메뉴 8 · 메뉴당 항목(구분선 포함) 32 · 전체 128 ·
   글 64바이트 · UTF-8. 넘으면 `post_error`(`too_many` · `too_long` · `bad_utf8` · `no_menu`). 원래 모드 판정(`native`)은 판과 무관하게 bind 그대로.
4. title · app_id: `Toplevel`에 64바이트씩(넘으면 UTF-8 경계에서 자름, UTF-8이 아니면 버림). 줄 `wl> title id= app_id= title=`(창마다 상한 4줄). 바의 앱 이름 =
   app_id의 마지막 `.` 뒤 조각, 없으면 title, 표시 상한 24칸. `set_min_size`는 무시 그대로.
5. 순수 모듈 `terminal/src/menubar.zig`와 호스트 검사: 모델 검증 · 바 배치(이름 · 제목의 x와 폭, 한글 폭 2) · 드롭다운 사각형(가장 긴 줄 · 오른쪽에서 밀기 · 아래 자름) ·
   키 이동(구분선 · 비활성 건너뜀 · 돌아감 · 전부 비활성) · hit-test(바 · 드롭다운 · 바깥) · 단축키 글(`Cmd+Shift+O` 순서).
6. 색: `shared/theme.zig`의 터미널 구역에 새 전용 상수(`MENU_NAME` · `MENU_FG` · `MENU_BG` · `MENU_HL_BG` · `MENU_DIM` · `MENU_SEP`). 값은 단계 A가 고르되 기존 덤프 색
   (`SEPARATOR` · `STATUS_*` · `MARGIN_COLOR` · 화살표 둘 · `CURSOR_COLOR` · `MATCH_BG` · `CURRENT_BG`)과 툴킷 앱 색 모두와 달라야 한다(표와 comptime 검사).
   단축키 글은 `Cmd+L` 꼴(ASCII).
7. 닫힌 바 그리기: `BarMemo`(포커스 창 id · 이름 · 모델 세대 · 열린 메뉴 · 강조)가 바뀐 프레임과 통째 프레임에만 위 띠 (0, 0, fb.width, 20)를 지우고 그린 뒤 clip에 넣는다
   (`paintBand`와 같은 꼴). 그림자(`verifyFrame`)도 같은 함수로 같은 순서. 줄 `menu> bar id= name= titles=`(바뀐 프레임만, 셸 포커스는 `menu> bar empty`)와 잉크 덤프.
8. 드롭다운: 열린 제목의 x에서 y 20부터, 폭 = 가장 긴 (레이블 + 두 칸 + 단축키) + 좌우 한 칸, 행 16(항목) · 8(구분선, 가운데 1 px 선). 열린 제목은 `MENU_HL_BG` 칸.
   "프레임의 마지막 그리기"다 — 열려 있는 동안 매 프레임 pane · 창 · 프롬프트 · 띠 뒤, verify 앞에 다시 그리고 그 사각형을 clip에. 열기 · 닫기 · 메뉴 옮김은 통째 프레임
   (밑의 픽셀을 저장하지 않는다), 강조만 바뀌면 드롭다운만. 그림자는 app slot 복사 뒤에 같은 함수로. `presentComposed`는 물리 합성 창과 겹친 드롭다운 자리를 그림자에서
   다시 늘린다. 연 동안 아래 창의 commit · frame done은 그대로.
9. 여는 키는 `Cmd+Shift+/`(`tableChord`의 Shift 갈래 — R-KEY-1 표 · `docs/help/desk.md`를 함께 고친다). 모델이 없으면 아무 일 없음(삼킴 그대로).
   연 동안: 수정키의 누름 · 뗌은 지금처럼 앱에 보낸다(Cmd가 끼지 않게). 수정키가 아닌 누름은 메뉴가 먹는다 — `←` `→` 메뉴, `↑` `↓` 항목, Enter 고르기(`activated`를
   보내고 닫음, 비활성이면 아무것도), Esc 닫기, 그 밖은 버린다. 한글 층을 안 지난다. 표의 chord는 메뉴를 닫고 평소대로. 글자로 건너뛰기는 뒤로.
10. 열 때 앱 조합이 있으면 `focusTo`와 같은 확정(`imeSend(commit, "")` + 조합 버림)을 먼저 한다 — 키보드 `leave`는 안 보낸다. 함수 하나로 뽑아 함께 쓴다.
11. 포인터: 첫 누름 앞에서 바(모델이 있을 때) · 드롭다운 사각형을 먼저 본다. 제목 누름 = 그 메뉴 열기(열린 제목이면 닫기), 항목 누름 = 고르기, 그 밖 누름 = 닫기만 하고
    먹는다. 연 동안 창에는 포인터 leave, 드롭다운 위 움직임은 강조를 옮긴다(바뀔 때만 그림), 휠은 먹는다. 누름-끌기-뗌 꼴은 뒤로. 모델이 없으면 위 여백은 지금처럼
    `press none`.
12. 닫는 때(줄 `menu> close why=`): Esc · 고름 · 바깥 클릭 · 포커스 창 바뀜 · workspace 전환 · fullscreen 전환 · 그 창의 모델 commit · 창/클라이언트 사라짐. 판정은
    `syncFocus` 다음 한 자리로 모은다.
13. 테스트 클라이언트 `tars-wl-test --menu`(판 2 bind + `get_menu` + 고정 모델 — `File`[`Open` id 1 `Cmd+O`, 구분선, `Quit` id 2 비활성], `Edit`[`Copy` id 3 `Cmd+C`,
    `한글` id 4]), `activated`에 `wl-test> menu activated id=N`. 툴킷의 판 2 bind와 모델 보내기는 TK-M6.
14. 줄: `wl> menu id= menus= items=`(commit마다, 창마다 상한) · `wl> title …` · `menu> bar …` · `menu> open id= menu=` · `menu> move menu= item=` ·
    `menu> activate id= item=` · `menu> close why=`.
15. 체인 wayland(판정 30 뒤, 좌표는 단계가 실제 덤프로 정한다):
    - 31(B) 바: `--menu` 창 포커스 → `menu> bar id=ID name=tars-wl-test titles=File,Edit` · 위 띠에 `MENU_NAME` · `MENU_FG` 잉크. 셸 포커스 → `menu> bar empty` · 위 띠가
      `MARGIN_COLOR` 한 가지.
    - 32(C) 키: `Cmd+Shift+/` → `menu> open` · 드롭다운 사각형 `MENU_BG` · 첫 활성 항목 `MENU_HL_BG` · 단축키 글의 오른쪽 정렬. `↓`가 구분선 · 비활성을 건너뛰어 돌아옴,
      `→` `↓` Enter → `menu> activate id=ID item=4` + 클라이언트 `menu activated id=4`, 그 사이 창에 `wl> key` 줄 없음.
    - 33(C) 닫기: 열고 Esc → `menu> close why=esc` · 드롭다운 자리가 다시 창 색.
    - 34(C) 포인터: 제목 클릭 → 열림, 항목 클릭 → activate, 바깥 클릭 → 닫기만(클라이언트의 `button` 줄 수 그대로).
    - 35(B) 이름만: 호환 창 포커스 → `titles=-`, 여는 키는 아무 일 없음(C에서 다시 본다).
    - 36(C) 조합 확정: `--text-input --menu` 창에서 조합 `한` 뒤 여는 키 → `wl> ime to=ID commit=한 preedit=(none)`가 `menu> open` 앞.

## 할 일

1. (A) xml 판 2 · terminal build 판 2 · 서버의 메뉴 객체(pending · commit · 상한 · 에러 · 수명) · title/app_id 저장 · 줄.
2. (A) `menubar.zig` 순수 모듈과 호스트 검사(확정 5), 색 상수와 겹침 검사.
3. (A) `tars-wl-test --menu`, wayland 체인에 줄 판정 하나(`wl> menu id= menus=2 items=5` · `wl> title`).
4. (B) 바 그리기 · `BarMemo` · clip · 그림자 · `menu> bar` 줄과 잉크 덤프.
5. (B) 판정 31 · 35.
6. (C) 여는 키(표 · 요구사항 R-KEY-1 · `docs/help/desk.md`) · 드롭다운 오버레이 · 그림자 순서 · `presentComposed`의 다시 늘리기.
7. (C) 연 동안 키 · 조합 확정 · 포인터 · `activated` · 닫는 조건.
8. (C) 판정 32~34 · 36, `measurements.md` 113(바 그리기 · 메뉴 연 통째 프레임 · 강조 프레임).
9. lead: 단계마다 대조 · commit, 단계 B 뒤와 C 뒤에 루트 게이트(36).

## 판정

- 호스트 검사, `make quick`, 체인 wayland 두 번 연속 · terminal · toolkit · hidpi · pointer PASS(단계 B · C), 루트 게이트 36/36, verify mismatch 0.

## plan에서 실측할 것

1. 스캐너가 `generate("tars_menu_manager_v1", 2)` 하나로 since 2 요청과 새 인터페이스를 만드는가, `xdg_toplevel` 인자의 타입. 2. libwayland-server가 판 1 bind의
`get_menu`를 막는가. 3. unifont의 U+2318 · U+21E7 · U+2325 유무(표시는 ASCII로 가되 기록). 4. 바 그리기 시간과 메뉴 연 통째 프레임 시간. 5. 강조만 바뀌는 프레임의
시간과 clip. 6. hidpi(bs 2)에서 바가 있는 채 블록 판정. 7. SDL3 · 둠이 보내는 `set_title` · `set_app_id`. 8. `sendkey alt-shift-slash`가 evdev 53 + Shift + Meta로
오는가. 9. 기존 체인의 위 여백 판정(루트 게이트 결과로).

## 결과

(단계마다 채운다.)
