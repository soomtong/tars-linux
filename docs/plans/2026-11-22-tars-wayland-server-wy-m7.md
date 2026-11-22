# WY-M7 — subsurface · window geometry · surface 단위 포인터 · popup · 호환 Cmd 키

Date: 2026-11-22
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(결정 48~55, milestone 표 WY-M7), CR design `docs/specs/2026-11-22-tars-chromium-design.md`(확인 3 · 4 · 8 · 9,
결정 7), 요구사항 R-WY-14(고침)
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `wy-m7`, 세션 scratchpad `wy7/research.md` — HEAD `dcf6046`, 작업 사본의 시제품 서버로 browser 묶음의 Chromium을 띄움)

- `wl_subcompositor` 판 1 하나만 내면 "주소창에 글자를 치면 죽는다"가 사라진다. bubble은 subsurface 하나(부모 = toplevel surface, `set_desync` · `set_position(109, 35)` ·
  `destroy`)뿐이고 다른 global을 더 바라지 않았다(CR design 위험 2 해소). 자동 완성 목록은 네트워크 없이 뜬다. F11 안내 bubble · 둘째 창 · 한글(`ㅎ` `하` `한`)도 산다.
- bubble은 ARGB 버퍼(그림자 반투명)이고 입력 영역을 보낸다(`set_input_region(0, 44, 454, 45)` — 위 44줄은 부모의 주소창으로 가야 한다). bubble이 떠 있는 동안 Chromium은
  그 아래 주소창 캐럿을 계속 깜빡인다 — 부모만 다시 옮기면 bubble 위에 구멍이 난다. bubble에 `frame`을 건다(자식의 frame done이 필요하다).
- popup 다섯 장면(문맥 메뉴 · `<select>` · 툴팁 · 앱 메뉴 · 하위 메뉴): positioner 다섯 요청(`set_size` · `set_anchor_rect` · `set_anchor` · `set_gravity` ·
  `set_constraint_adjustment`)만 쓰고 `grab` · `reposition`은 없다. 닫기는 Chromium 스스로(Esc · 고름 · 포커스 잃음에 `destroy`). popup의 window geometry가 버퍼와 다르다
  (문맥 메뉴 geometry `(24, 12, 319, 319)` · 버퍼 367 × 367). 하위 메뉴의 부모는 popup이다. 메뉴가 열린 동안 키보드 포커스는 toplevel에 남고 `↓` Enter Esc가 메뉴에 먹는다.
- 하위 메뉴(폭 364, `flip_x`는 있고 `slide_x`가 없다)는 616폭 pane 안에서는 resize로 6픽셀이 된다 — 화면을 경계로 하면 flip해 셸 column 위에 선다.
- 시제품의 잘못이 알려 준 것: "보이는 popup이 있으면 바깥 누름에 닫고 삼킨다"로 하자 툴팁이 누름을 삼켜 앱 메뉴 단추가 안 눌렸다 — 바깥 누름 규칙은 grab한 popup만.
- 지금 서버: surface는 opaque · input region과 `set_window_geometry`를 버린다. `fit`이 버퍼 전체를 pane 가운데에 둔다(Chromium의 그림자 10이 대칭이라 우연히 맞는다 —
  configure 전 첫 geometry는 비대칭이었다). `paint`는 복사 하나(알파 무시), `paintPhys`는 "창 하나 = 버퍼 하나" 전제, `presented`는 toplevel surface의 frame만 `done`.
  배율 2에서 시제품은 자식을 그림자에만 섞어 물리 합성이 덮어 bubble이 사라졌다.
- text-input: `Cmd+N`의 둘째 창에서 한글이 그 창으로 간다 — 동작의 귀속은 이미 surface다. 어긋난 것은 `logEnabled` · `textInputDestroyed`가 `toplevelOf(client)`(첫 창)를
  찍는 표기뿐이다.
- 호환 Cmd 키를 세 갈래로 쟀다: 지금(125 그대로) 페이지가 `key=Meta`를 보고 누름 `ctrl=false` · 뗌 `ctrl=true`, 29로 바꾸면 진짜 Ctrl과 같지만 둠에서 Cmd가 쏜다
  (`doomgeneric_wayland.c`의 `KEY_LEFTCTRL` = 사격), 보내지 않으면 Cmd 이벤트가 없고 `Cmd+C` `V`가 `ctrl=true`로 먹는다. 어느 체인도 `code=125`를 세지 않는다.
- 곁에서: initrd 뒤에 cpio를 이어 붙일 때 앞 파일 크기가 4의 배수가 아니면 커널이 조용히 무시한다(512 경계까지 0으로 채운다).

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `wy-m7`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit. 루트 게이트는 단계 A 뒤와 B 뒤(서버의 그리기를 건드려
verify가 모든 체인에서 돈다).

- 단계 A — subsurface와 작은 고침 둘(죽음을 없앤다): 할 일 1~5.
- 단계 B — popup: 할 일 6~9.

## 착수 전에 확정한 것(design 결정 48~55)

1. `wl_subcompositor` 판 1을 xml대로 다 받는다(결정 48) — sync 캐시(pending → cached → 부모 적용 때 current, 부모의 sync 여부는 재귀) · `place_above/below` · 에러
   (`bad_surface` · `bad_parent`) · 수명(자식 surface · 부모 · subsurface가 어느 순서로 사라져도). 순수한 부분(트리의 z 순서 · sync 판단)은 `wl_logic.zig`에 두고 호스트 검사.
2. 합성(결정 49): `paint` · `paintPhys`가 트리를 지난다 — 부모(복사) → 자식(z 순, ARGB는 premultiplied over) → (단계 B) popup. clip 안에서. 자식의 buffer_scale이 부모와
   달라도 물리 합성이 맞다. 자식의 매핑/해제/움직임/크기 바뀜은 부모 통째, 자식의 damage만 온 commit은 화면 좌표의 부분 blit. `presented`는 트리 전체의 frame에 `done`,
   자식이 처음 보일 때 `wl_surface.enter(output)`. subsurface는 app slot 사각형으로 자른다. 줄 `wl> subsurface id= …`는 만들기 · 매핑 · 닫기만(창마다 상한).
3. window geometry와 입력 영역(결정 50): `set_window_geometry`는 double-buffered로 담아 `fit`의 대상으로(없으면 버퍼 전체 — 둠 · SDL · tars-wl-test의 좌표 불변).
   `set_input_region`은 상자의 합(`wl_region.add` — `subtract`는 받되 단순하게: 조사에서 Chromium은 0번).
4. 포인터(결정 51): (창, surface). 고르는 순수 함수 `pick`(단계 A는 자식과 부모, 단계 B가 popup을 앞에). surface가 바뀌면 leave · enter, 버튼을 쥔 동안 고정, 좌표는 surface 기준.
5. 호환 Cmd 키(결정 54): 호환 창에 evdev 125 · 126의 key 이벤트를 보내지 않는다(modifiers는 Ctrl). 원래 모드 창은 지금처럼 125.
6. text-input 표기(결정 55): `ti enable` · `ti disable`의 `to=`를 그 text_input이 들어가 있는 surface의 창으로.
7. popup(결정 52 · 53): positioner 셈은 순수 함수 + 호스트 표(Chromium의 다섯 장면 값이 표본 — 문맥 41 · select 8 · 툴팁 11 · 앱 메뉴 41 · 하위 메뉴 54). 경계는 앞 workspace의
   화면(위 띠 · 상태 줄 제외). popup 원점 = 부모 geometry 원점 + configure (x, y) − popup geometry (x, y). column 밖 합성 · verify 그림자에 실제 fb 복사 · 닫히거나 움직인
   프레임은 통째 · 포인터는 app slot보다 먼저 popup. grab은 받되 키보드 포커스를 안 옮긴다, grab한 popup만 바깥 누름에 `popup_done` + 삼킴. 서버 쪽 닫기 셋(포커스 떠남 ·
   toplevel 닫힘/숨음 · 부모 크기 바뀜). `reposition` · `set_reactive` · `set_parent_*` · `set_offset`은 xml대로(다시 셈하지 않는 것은 닫기로). 에러(`invalid_positioner` ·
   `invalid_grab` · `not_the_topmost_popup`). 메뉴 바(TK-M5)가 열린 동안은 그쪽이 먼저다.
8. 테스트 클라이언트: `tars-wl-test --subsurface`(창 3366CC 위 64 × 64 자식 `set_position(40, 40)`, 키로 위치만 바꾸고 부모 commit은 다음 키에, `--subsurface-sync`) ·
   `--popup`(누른 점 anchor, 120 × 80, `--popup-grab` · `--popup-ca N` · 가장자리 시험). 받은 enter의 surface와 좌표 · `popup configure` · `popup_done`을 찍는다.
9. 체인 wayland(판정 37~, 좌표는 단계가 실제 덤프로):
   - 37(A) subsurface 좌표 색. 38(A) 부모 commit에 묶인 위치 + sync 모드에서 자식 색 바꿈이 부모 commit 전에는 안 보임. 39(A) 포인터 enter의 surface와 자식 좌표.
   - 40(B) popup 좌표 색과 configure 값(제약 없는 자리 하나, 화면 가장자리의 flip/slide 하나 — 그중 하나는 셸 pane 위로 나가 verify를 함께 본다).
   - 41(B) grab한 popup의 바깥 누름 → `popup_done` 한 줄 · 그 누름은 창에 안 감. grab 없는 popup의 바깥 누름은 창에 간다. 42(B) popup이 열린 채 `Cmd+[` → `popup_done`.
   - 43(A) text-input 표기: 창 둘, 둘째 창에서 `ti enable to=<둘째>`. 44(A) 호환 Cmd 단독 tap → `key code=125` 0줄(서버 · 클라이언트), 뒤이은 `Cmd+V`는 `depressed=0x4`.
   hidpi 체인: bs 2 창의 subsurface(자식도 bs 2)와 자식 bs 1 한 장면(A), popup 한 장면(B) — 물리 좌표 색.
10. 체인 browser(판정 3과 4 사이): 3a(A) `Cmd+L` · `a` → `wl> subsurface` 줄 · `wl> gone pid=` 0 · `Crash Reports/pending` 비었음 · bubble 자리의 좌표 색이 페이지 색에서
    바뀜, Esc 둘. 한글은 넣지 않는다(CR-M2). 3b(B) 페이지 안 오른쪽 누름 → `wl> popup` 줄 · 메뉴 자리의 좌표 색, Esc → 그 자리가 다시 페이지 색. 좌표는 Chromium 판에
    덜 묶이게 넉넉한 상자로.
11. 서버 쪽 장식은 하지 않는다(결정 55). `docs/help/desk.md`의 "주소창에 글자를 치면 죽는다" 문장을 단계 A가 지운다.

## 할 일

1. (A) `wl_subcompositor` · `wl_subsurface`(확정 1), 트리 합성 · 물리 합성 · frame done · `enter`(확정 2).
2. (A) geometry · 입력 영역(확정 3), surface 단위 포인터(확정 4 — 자식까지).
3. (A) 호환 Cmd 키(확정 5), text-input 표기(확정 6).
4. (A) `tars-wl-test --subsurface`, 호스트 검사(트리 · sync · `pick` · geometry의 `fit`), 판정 37~39 · 43 · 44 · hidpi 둘 · browser 3a.
5. (A) `docs/help/desk.md`, `measurements.md` 116(블렌드 비용 — bubble 한 장 · 캐럿 깜빡임 때 자식 재합성).
6. (B) positioner 셈과 호스트 표, `xdg_popup` 전부(확정 7).
7. (B) popup 합성(column 밖) · verify 복사 · 통째 프레임 · 포인터 · grab · 서버 쪽 닫기.
8. (B) `tars-wl-test --popup`, 판정 40~42 · hidpi 하나 · browser 3b.
9. (B) `measurements.md`(메뉴 한 장의 블렌드 · 열고 닫는 프레임), carryover에 넘길 것.
10. lead: 단계마다 대조 · commit · 루트 게이트(37), 끝에 WY design Status · CR design의 확인 9 고침 · carryover · HANDOFF.

## 판정

- 호스트 검사, `make quick`, 체인 wayland 두 번 연속 · terminal · toolkit · hidpi · pointer · display · browser PASS(단계마다), 루트 게이트 37/37, verify mismatch 0.

## plan에서 실측할 것

1. 블렌드 비용 — bubble 454 × 298 · 앱 메뉴 412 × 735 한 장의 µs, 캐럿 깜빡임 때 자식 재합성. 2. 배율 2에서 자식 · popup의 물리 좌표(bubble 676 × 178 bs 2가 1:1인가).
3. column 밖 popup의 verify(mismatch 0)와 닫은 뒤 셸 pane의 다시 그림. 4. 자식에 `wl_surface.enter`를 안 보내면 Chromium의 bubble 배율이 달라지는가. 5. 부모 크기 바뀜
(`Cmd+R`)에 닫힌 popup을 Chromium이 다시 여는가. 6. SDL3 앱에서 "Cmd 이벤트 없음"이 Ctrl 조합으로 먹는가(display 체인의 SDL 판정이 그대로인가). 7. 체인 3a · 3b의 좌표.
8. geometry를 `fit`에 쓴 뒤 Chromium의 첫 화면 좌표(browser 판정 2 · 3의 `buf=636x772` · 페이지 원점 (644, 107))가 그대로인가.

## 결과

구현은 `wy-m7`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `9b945c7`: 서버의 surface 상태 세 칸(pending → cache → current — 적용하는 길이 하나) · `wl_subcompositor` 판 1과 `wl_subsurface` 전부(에러 · sync · 쌓임 · 수명) ·
   트리 합성(`paint` · `paintPhys` — 아래 자식 → 부모 → 위 자식, ARGB는 over, clip 안) · 자식 damage의 부분 blit · 트리 전체의 frame done과 `enter` · `set_window_geometry`
   (`fitGeom`) · `wl_region`과 입력 영역 · (창, surface) 포인터(`pickAt`) · 호환 창에 Cmd 키 안 보냄 · text-input 표기. 순수 함수 열(`wl_logic.zig` — `fitGeom` · `rootOrigin` ·
   `over` · `blendClip` · `damageAt` · `pick` · `restack` · `effectiveSync`)과 호스트 검사 30경우. `tars-wl-test --subsurface` · `--subsurface-sync` · `--sub-scale` · `--second`.
   체인 wayland 두 번 연속 · terminal · toolkit · hidpi · pointer · display · browser PASS, verify mismatch 0.
   판정의 실제 값: 37 자식 (684, 60)~(747, 123)이 `cc3366` · 그 오른쪽 `3366cc`. 38 `set_position`만 한 뒤 1초에도 그대로 → 부모 commit 뒤 옮겨짐, sync 창은 자식 색 바꿈이
   부모 commit 뒤에야 `33cc66`. 39 `sub enter x=32 y=32` · `sub leave` · `pointer enter x=152 y=172`. 43 한 클라이언트의 창 둘에서 `wl> ti enable to=18`(둘째).
   44 호환 창의 Cmd tap + `Cmd+V` → `key code=125|126` 0줄 · `depressed=0x4`. hidpi 9: 물리 2880 × 1800에서 bs 2 창의 자식(bs 2 · bs 1 둘 다)이 물리 (1528, 120)에.
   browser 3a: `Cmd+L` · `a` → `wl> subsurface id=1 sub=1 map w=454 h=89 bs=1 at=109,35` · bubble 자리 `2e8b57` → `f2f2f2` · `wl> gone pid=` 0 · crash report 0.
   Chromium의 첫 화면(판정 2 · 3)은 한 글자도 안 바뀌었다 — 그림자 10이 대칭이라 geometry로 한 fit이 가운데 자르기와 같다(호스트 검사가 단언한다).
   plan과 달라진 것: (가) `--second`(판정 43은 "한 클라이언트의 창 둘"이어야 옛 표기 오류가 드러난다 — 클라이언트 둘은 옛 코드로도 맞게 찍힌다). (나) `wl> tree` 줄
   (자식을 섞은 옮기기의 시간 — `wl> blit`의 통째 줄은 창마다 둘뿐이다). (다) `TextInput.to` · `Subsurface.top` — 클라이언트가 끝날 때 surface가 먼저 사라져 창을 못 찾는다.
   (라) 3a는 주소창의 `ti enable`을 기다린 뒤 `a`를 친다(Chromium의 포커스 이동이 비동기다 — 안 기다리면 `a`가 페이지로 간다). (마) 판정 37 앞에서 한글을 끈다(36이 켠 채 끝난다).
   첫 체인 판 셋이 FAIL이었다 — 한글이 켜진 채 친 명령(판정 순서), 끝나는 클라이언트의 `gone` 줄(코드 — `top`으로 고침), 이른 `a`(판정). 다 고친 뒤 여덟 체인 PASS.
   lead의 화면 판정: 주소창에 `a`를 친 전체 화면 — 자동 완성 목록 다섯 줄, 그림자가 페이지와 섞였고 캐럿 자리에 구멍이 없다.
   실측(`measurements.md` 116): bubble이 처음 보인 통째 프레임 17.5 ms(부모만은 1.0~1.2 ms — 섞기 약 0.4 µs/px, TCG), 떠 있는 동안 부모 캐럿 1 × 17은 26~34 µs.
   루트 게이트 37/37 첫 판(`out/gate-logs/20261122-002737`), verify mismatch 0. browser 체인의 첫 화면은 게이트 부하 아래 28초.
2. 단계 B `f0f3524`: `xdg_positioner`(상태 · `invalid_input`) · `xdg_popup` 전부(`get_popup` · `grab` · `reposition` · `destroy`의 에러 넷) · 자리 셈 `wl_logic.placePopup`
   (축마다 flip → slide → resize, 호스트 표 16경우 + anchor × gravity 81) · column 밖 합성(`beginPopups` → `paintPopups` → `shownPopups`, 경계는 위 띠 아래 · 격자 끝 위) ·
   verify 그림자가 popup이 덮은 자리를 실제 fb에서 복사 · 물리 합성(`physPopups` — 창 사각형 안만) · 포인터가 popup 먼저(`popupAt` · `pickAt`) · 서버 쪽 닫기 셋
   (`done why=focus|resize|outside`) · `blendClip`의 1:1 길. `tars-wl-test --popup` · `--popup-grab` · `--popup-ca N` · `--popup-left`.
   체인 wayland 두 번 연속 · terminal · toolkit · hidpi · pointer · display · browser PASS(서브에이전트), verify mismatch 0(wayland 판정 9: 7,263줄).
   판정의 실제 값: 40a 창 (900, 300) 누름 → `new parent=main at=256,281 w=120 h=80 ca=0`, 상자 `930 321 80 50`이 `33cc66`. 41b popup이 열린 채 창 안 누름 → `wl> button` 하나 늘고
   클라이언트가 지움. 40b `--popup-left --popup-ca 8`의 (660, 300) → `at=-104,281` — 셸 pane 위 상자 `550 311 80 60`이 `33cc66`, 닫은 뒤 열기 전의 셸 값. (900, 740) →
   `at=136,640`(flip_y). 41a grab popup + 셸 (200, 400) 누름 → `done why=outside`, 셸 포커스 줄 · 창의 `wl> button` 수 그대로. 42 `Cmd+[` → `done why=focus`.
   hidpi 10: 물리 2880 × 1800, bs 2 창의 popup이 물리 (1648, 242) 240 × 160. browser 3b: (1000, 500) 오른쪽 누름 → `new parent=main at=317,161 w=319 h=319 ca=41`
   (호스트 표의 셈 그대로), 상자 `1150 300 40 10`이 `2e8b57` → `ffffff` → Esc 뒤 `2e8b57`, `wl> gone pid=` 0.
   체인 밖 시험 VM(Chromium 156): 문맥 메뉴 · `<select>` · 툴팁 · 앱 메뉴(resize_y로 672) · 하위 메뉴(flip_x로 셸 column 위) · 배율 2의 bs 2 메뉴가 보이고 고를 수 있다.
   plan과 달라진 것: (가) `blendClip`의 1:1 길(opaque region은 Chromium이 `nil`을 보내 쓸 수 없었다) — 메뉴 한 장 50 ms 걱정이 약 1 ms가 됐다. (나) popup이 보이는 동안
   프레임은 늘 통째(plan은 "닫히거나 움직인 프레임") — 부분 프레임은 다시 칠하지 않은 clip에서 그림자가 두 번 섞인다. (다) browser 체인 QEMU에 USB 마우스.
   (라) 판정 순서 40a → 41b → 40b → 41a → 42. 첫 체인 판 하나가 FAIL — 40a의 상자에 화살표(12 × 19)가 걸렸다(상자를 옮김, 코드는 그대로).
   lead의 대조: plan 확정 7 · 결정 52 · 53과 맞다. 고친 것 둘 — `menuPress`의 주석이 새 `popupPress` 위에 얹혀 있던 것, 호스트 검사의 "y는 x의 거울"이 크기만 보던 것
   (y 자리 81조합을 실제로 단언).
   실측(`measurements.md` 117): 앱 메뉴 412 × 684 한 장 1,073 ~ 1,119 µs, popup이 보이는 동안 `wl> frame full` 26 ~ 54 ms. 안 잰 것은 실측 2 · 4 · 5 · 6(carryover).
   루트 게이트 37/37 첫 판(`out/gate-logs/20261122-025252`, lanes 1,785초 — WY 체인 318초 · browser 76초), verify mismatch 0.
3. 마감: WY design Status · CR design 확인 9 고침 · `completed.md` · 기억 `project_wayland_server` · carryover "WY-M7이 남긴 것" · 로드맵. 서브에이전트 pane은 세션이 다시
   시작되며 사라졌다(보고서 `wy7/report-b.md`는 남아 있었다).
