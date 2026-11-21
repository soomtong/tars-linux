# TK-M2 — 입력 이벤트 · hit-test · responder · 포커스 · 가상화 리스트 · 스크롤

Date: 2026-11-21
Design: `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 8 · 9 · 13, milestone 표 TK-M2), 요구사항 R-ARCH-1 · 4, R-CA-6, R-KIT-1 · 2 · 4, R-KEY-2 · 3 · 7,
요구사항 결정 3 · 11
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `tk-m2`, 세션 scratchpad `tk2/research.md` — HEAD `b0c70f3`, 개발 컨테이너 aarch64 벤치)

- 창 층은 지금 키의 evdev 코드와 누름만 본다. keymap fd는 닫고 `enter` · `leave` · `modifiers` · `repeat_info`를 버리며 포인터는 받지 않는다.
  `run`은 `display.dispatch()`로 막혀 기다려 타이머를 끼울 자리가 없다.
- 서버는 고정 us · pc105 키맵과 `repeat_info(30, 250)`을 보내고 수정키 비트를 직접 채운다(Shift 0x1 · Lock 0x2 · Ctrl 0x4 · Alt 0x8 · Super 0x40).
  툴킷은 `tars_menu_manager_v1`을 bind하므로 Super가 그대로 온다. 자동 반복(evdev value 2)은 app pane에 안 간다 — 반복은 클라이언트 몫(R-KEY-2).
  initrd에 libxkbcommon은 없다.
- 포인터: `enter` · `motion` · `button`(BTN_LEFT 272) · `axis`(한 칸 wl_fixed 10.0, 아래가 양수) · `axis_discrete` · `frame`. 좌표는 surface 논리 좌표.
- zig-wayland 0.7.0 클라이언트에 `getFd` · `prepareRead` · `readEvents` · `cancelRead` · `dispatchPending` · `flush`가 있다 — poll 루프를 짤 수 있다.
- 리스트 벤치(616 × 752, 행 24, 13 px 한글 레이블, ReleaseSafe 200회 중앙값): 한 레이어 통째 357 µs(바탕만 160), 행마다 레이어 358, `↓` 한 번의 부분(616 × 48)
  34 µs — clip 밖 행을 안 거르면 131, 버퍼 안 복사 스크롤 57. 1240 폭 통째 518. 10만 · 1,000만 행에서 선택 이동 · End는 200 ns 안팎, 그린 행은 늘 32.
- `Painter.drawGlyphs`는 clip 밖 글자도 하나씩 자른다 — 리스트가 `clipBounds()`로 행을 걸러야 한다.
- 마우스 주입(`-usb -device usb-mouse` + HMP `mouse_move` · `mouse_button`)과 `sendkey` 이동 키 이름은 다른 체인이 이미 쓴다. sendkey 기본 누름 100 ms는
  반복 지연 250 ms보다 짧다.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `tk-m2`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — 입력과 뼈대(화면 변화 0): 할 일 1~4. 체인 toolkit 판정 1~9가 그대로 초록.
- 단계 B — 리스트 · 스크롤 · 데모 · 체인: 할 일 5~8.

## 착수 전에 확정한 것

1. xkb 없이 간다. `toolkit/src/input.zig`(모듈 `tk_input`, 층 밖 순수 값 — `geom`과 같은 자리)에 `Mods` · `Key` · `Event`와 evdev 코드 → `Key` 표, mask → `Mods`.
   keymap fd는 지금처럼 닫고 까닭을 주석에. 글자 키의 문자 표는 TK-M4.

   ```
   Mods  = packed struct { shift, ctrl, alt, super, caps }
   Key   = enum { tab, enter, escape, space, up, down, left, right, page_up, page_down, home, end, other }
   Event = union(enum) {
       key: { code: u32, key: Key, pressed: bool, repeat: bool, mods: Mods },
       focus: bool,                                             // wl_keyboard enter / leave
       pointer_motion: { x: f32, y: f32 },                      // enter도 이것으로
       pointer_leave,
       button: { code: u32, pressed: bool, x: f32, y: f32 },
       scroll: { dy: f32, discrete: i32, x: f32, y: f32 },      // wl_pointer.frame에서 모은 값
   }
   ```
2. 키 반복은 창 층이 한다(R-KEY-2). 상태 기계는 순수 파일 `window/repeat.zig`(시각을 인자로 — `age.zig`와 같은 처리): `repeat_info`의 rate · delay를 들고,
   반복하는 키(수정키 · Tab · Enter · Esc가 아닌 것)를 누르면 delay 뒤 1/rate 간격으로 `repeat = true` 키 이벤트. 뗌 · 다른 키 누름 · `leave`에 멈춤. rate 0이면
   반복 없음. `run`은 `prepareRead` → `flush` → `poll(display fd, timerfd)` → `readEvents`/`cancelRead` → `dispatchPending`. 밀린 반복은 몰아서 내지 않는다 —
   타이머가 늦게 깨면 그때 한 번만 낸다(키가 쌓여 그림이 밀리지 않게).
3. `Handler.key` → `Handler.input(ctx, Event)`. 줄 `tk> key code= state=`는 그대로, 반복이면 끝에 ` repeat=1`. 포인터는 capabilities에 있으면 `get_pointer`,
   frame 단위로 이벤트 하나. `set_cursor`는 보내지 않는다(서버가 화살표를 그린다).
4. 층: 새 모듈 `tk_kit`(`src/kit/`)이 AppKit 층. `tk_ca` · `tk_cg` · `tk_geom` · `tk_input`을 알고 `tk_window`는 모른다(호스트 검사가 Wayland 없이 선다 —
   R-ARCH-4). 모양은 `window → cg → ca → kit`과 층 밖의 `geom` · `input`. 잇는 자리는 `tk.zig`(kit의 `Root`를 창의 `Handler.input`에).
5. hit-test(R-CA-6)는 CA: `Tree.hitTest(x, y) ?*Layer`(논리 좌표). hidden과 불투명도 0은 건너뛰고, masks 레이어는 자기 사각형 밖이면 하위 트리 전체를 건너뛰며,
   자식은 뒤에서 앞으로(위에 그려진 것 먼저), 가장 깊은 레이어. `Layer.owner: ?*anyopaque` 하나를 더한다(CA는 뷰를 모른다). `hit` 플래그는 두지 않는다.
6. 뷰가 레이어를 가진다: `View { layer, parent, children, vtable, ctx, name }`. vtable은 `keyDown(ev) bool` · `scroll(ev) bool` · `mouseDown(ev, lx, ly) bool` ·
   `acceptsFocus() bool` · `focusChanged(bool)` · `windowFocusChanged(bool)`.
7. responder chain(R-KIT-1): 키는 first responder → 부모 → … → 루트 뷰, 아무도 안 받으면 `Root.unhandled`(TK-M6의 단축키 표 자리). Super가 섞인 키도 같은 길.
   Tab · Shift+Tab은 체인을 다 돈 뒤 루트가 처리(R-KIT-2) — 뷰 트리의 깊이 우선 순서에서 `acceptsFocus`이고 보이는 것, 끝에서 처음으로 돈다.
   클릭: hit-test → owner 뷰 → 조상으로 `acceptsFocus`인 첫 뷰가 first responder, `mouseDown`은 그 뷰부터 체인. 휠: 포인터 아래 뷰부터 조상으로 `scroll`을 받는
   첫 뷰(포커스와 무관).
8. 포커스 표시: 새 토큰 `TK_SELECTION_INACTIVE`(값은 단계 A가 셸 색 · 앱 색과 안 겹치게 고른다 — 기존 comptime 검사가 지킨다)과 `tokens.color.selection_inactive`.
   리스트의 강조는 first responder이고 창이 키보드 포커스를 가질 때만 `TK_SELECTION`, 아니면 흐린 색. 일반 포커스 링은 버튼 · 텍스트 필드가 올 때.
9. 리스트(R-KIT-4): `ListSource { ctx, count, drawRow(ctx, p, index, rect, state) }`, `RowState { selected, focused }`. 행 높이 고정(토큰 `size.row` = 24).
   오프셋은 정수 논리 픽셀 `u64`(f32 레이어 frame으로 큰 콘텐츠를 옮기지 않는다 — 정밀도). 범위는 `offset / row_h .. ceil((offset + view_h) / row_h)` — 행 수에
   비례하는 일이 없다. 레이어는 컨테이너(masks · 바탕) → 강조 레이어 → 글자 레이어(content, clip 밖 행 건너뜀) → 막대 레이어. 선택 행의 글자색은 그대로
   `TK_TEXT`(선택 이동의 더티가 강조 레이어의 옛 ∪ 새로 끝난다).
10. 키: `↓` `↑` 한 행, PgDn PgUp = 보이는 행 수 − 1, Home End. 선택이 보이게 스크롤은 최소만(아래로 넘으면 행 바닥을 뷰 바닥에, 위로 넘으면 꼭대기를 꼭대기에).
    휠: `discrete`가 있으면 칸당 3행, 없으면 `dy` px. 휠은 선택을 안 바꾼다. 클릭은 그 행을 선택.
11. 스크롤 한 번 = 리스트 통째 다시 그림. 버퍼 안 복사와 부드러운 스크롤은 carryover. 강조 레이어의 이동만 `animate(.frame)` 120 ms `easeOutCubic`
    (녹화 C의 "짧게 움직인다"), 스크롤이 생기는 이동은 애니메이션 없이 바로. 데모 인자 `--anim-ms`가 이 길이도 정한다(없으면 120).
12. 스크롤 막대: 레이어 하나(폭 6, `radius.s`, `TK_TEXT_DIM`), 높이 max(24, view_h² / content_h), 위치는 오프셋 비례. 내용이 뷰보다 짧으면 hidden. 드래그 ·
    자동 숨김 없음.
13. 데모: `tars-tk-demo --list N`. 가로 스택에 리스트 둘 — 왼쪽 `list1`(N행, 남는 폭) · 오른쪽 `list2`(50행, 폭 200). 처음 first responder는 `list1`, 선택은 둘 다 0.
    인자가 없으면 지금 화면 그대로(판정 1~9를 한 글자도 안 바꾼다). 레이블은 셈으로 만든다("문서 000123.txt" 꼴 — 메모리가 행 수와 무관).
14. 로그: `tk> focus view=` · `tk> list view= sel= first= offset=`(키 · 클릭마다 한 줄) · `tk> scroll view= offset= by=wheel` · `tk> hit x= y= view=`(클릭만).
15. 체인 toolkit: 부팅에 `-usb -device usb-mouse`를 더한다(판정 1~9의 덤프가 그대로인지 단계 B가 확인 — 달라지면 lead에 보고하고 리스트 판정만 둘째 부팅으로).
    판정 9 뒤 같은 부팅에서 `tars-tk-demo --list 100000 > /tmp/tk2.log`.
    - 10 `↓` 열 번: 서버 `wl> key code=108 state=1` 열 줄, 덤프에서 `list1`의 행 10이 `TK_SELECTION`(글자를 피한 상자는 잉크 0, 글자 상자는 잉크 > 0),
      행 0 · 9 · 11은 바탕. 부분 blit은 통째가 아니다. `tk> list view=list1 sel=10 first=0 offset=0`.
    - 11 `End`: 맨 아래 행이 강조, 막대가 바닥, `tk> list view=list1 sel=99999 … offset=<count × 24 − view_h>`.
    - 12 클릭 · 휠: `Home` 뒤 행 4를 클릭 → `wl> button` 두 줄 · `tk> hit … view=list1` · 덤프의 행 4 강조. 휠 아래 한 칸 → `tk> scroll view=list1 offset=72 by=wheel`.
    - 13 `Tab`: `tk> focus view=list2`, `list1`의 강조가 흐린 색, `list2`의 행 0이 `TK_SELECTION`, `↓` 뒤 `list2`의 행 1. `Shift+Tab`에 `list1`로.
    - 14 반복: HMP `sendkey down 1000` → `tk> key code=108 state=1 repeat=1`이 3줄 이상이고 선택이 그만큼 내려감(TCG라 느슨한 하한, 실제 수는 참고 줄로).
    - 끝에 둘째 데모 로그의 `draw = commit`(idle commit 0), 앞 판정들의 셈 이름표를 갱신.

## 할 일

1. (A) `input.zig` · `window/repeat.zig` · 창 층의 keyboard enter/leave/modifiers/repeat_info · pointer · poll 루프 · `Handler.input`, 데모의 space를 이 길로.
2. (A) CA `hitTest` · `Layer.owner`.
3. (A) `kit/`(View · Root · responder · first responder · Tab 순환 · 클릭 포커스 · 휠 라우팅), `build.zig`의 `layerModules`에 `input` · `kit`, `tk.zig` 잇기, 토큰.
4. (A) 호스트 검사: 반복 상태 기계(지어낸 시각 — 지연 · 간격 · 뗌 · 다른 키 · leave · rate 0 · 늦게 깬 타이머), hit-test 표(겹침 · masks · hidden · 불투명도 0),
   responder 표(받음 · 부모로 · unhandled), Tab/Shift+Tab 순환(숨은 뷰 건너뜀), 클릭 포커스 · 휠 라우팅.
5. (B) 리스트 뷰(확정 9~12). 호스트 검사 넷: 행 수 100 · 100,000 · 10,000,000에서 같은 조작열의 선택 · 오프셋 · 더티 표가 같다, 세는 데이터 소스로 통째
   `drawRow` ≤ ceil(view_h / row_h) + 1 · 선택 이동은 0번 · 부분은 clip과 겹치는 행만, 부분 = 통째 바이트 비교(무작위 조작), 끝 경계(0행 · 1행 · 뷰보다 짧음 ·
   맨 위 `↑` · 맨 아래 `↓`의 더티 없음).
6. (B) 데모 `--list N`(확정 13 · 14).
7. (B) 체인 판정 10~14, 머리 주석, `tk>` 줄. 파이프 끝 `grep -q` 금지(`> /dev/null`로 — GA-M0 입구 검사).
8. (B) `measurements.md` 109(게스트의 리스트 통째 · `↓` 부분 · 스크롤 한 프레임의 `tk> draw us=`와 서버 `wl> blit us=`, 네이티브 숫자와 나란히).
9. lead: 단계마다 대조 · commit, 끝에 루트 게이트(36).

## 판정

- 호스트 검사, `make quick`, 체인 toolkit 두 번 연속 · terminal PASS, 루트 게이트 36/36, verify mismatch 0.

## plan에서 실측할 것

1. 게스트의 리스트 통째 `tk> draw us=`(616 · 1240)와 같은 프레임의 서버 blit — 스크롤 한 프레임이 16 ms 하한 안에 드는가(R-KIT-4). 2. `↓` 한 번의 부분
그리기와 강조 애니메이션의 프레임 수. 3. `↓`를 1초 누르는 동안의 키 이벤트 수와 그림 수(그림이 반복을 따라가는가). 4. sendkey `down` 열 번 사이의 그림 수.
5. usb-mouse를 더한 부팅에서 판정 1~9의 덤프가 그대로인가, 휠 아래 한 칸이 `v=10`인가. 6. 10만 행 데모의 VmRSS(TK-M1 데모와 비교). 7. 호스트 검사의 MaxRSS ·
시간. 8. 둘째 데모 로그를 console로 꺼낸 줄이 쪼개지지 않는가.

## 결과

구현은 `tk-m2`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `f31b239`: `input.zig`(모듈 `tk_input`) · `window/repeat.zig` · `kit/`(View · Root) · CA `hitTest` · `Layer.owner` · 창 층의 poll 루프와 포인터 ·
   토큰 `TK_SELECTION_INACTIVE = 465A78`(활성 강조의 채도를 뺀 회청색 — 바탕 · 활성과 채널 차가 커 덤프 판정이 갈린다). 화면 변화 0: 체인 toolkit 두 번 ·
   terminal PASS, 판정 1~9의 문장이 그대로(애니메이션 163프레임, 부분 draw 중앙 55 µs — poll 루프가 그리기를 느리게 하지 않았다). 호스트 검사 덩어리 8~10
   (반복 13줄 · hit-test 12줄 · kit 19줄), compile MaxRSS 503 MB.
   plan과 달라진 것: (가) 잇는 자리 — 창이 Root를 직접 부르지 않고 앱의 `input` 콜백이 `root.handle(ev)`로 넘긴다(앱이 자기 키를 먼저 볼 자리),
   `tk.connectRoot`는 포커스 줄 훅만. (나) 키 뗌은 뷰에 안 간다, 클릭은 왼쪽 누름만. (다) 반복은 `dispatchPending` 뒤에 낸다(같은 깨움에 온 뗌이 먼저 멈추게).
   (라) keyboard `leave`에 수정키도 비운다. (마) 불투명도 0은 하위 트리째 hit-test에서 빠진다. (바) `size.row` 토큰은 단계 B로.
   배운 것: 같은 작업 트리에서 체인 둘을 겹쳐 돌리면 `terminal/.zig-cache` 빌드가 경합한다(`libhighway.a`를 못 엶).
