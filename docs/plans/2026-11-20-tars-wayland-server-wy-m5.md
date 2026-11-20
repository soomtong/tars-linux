# WY-M5 — 한글 text-input-v3

Date: 2026-11-20
Design: `docs/specs/2026-11-19-tars-wayland-server-design.md`(결정 38~43), 요구사항 R-WY-9 · R-KEY-6
Status: 진행 중. 브랜치 `app-layer-0-3`.

## 확인(조사 `wy-m5`, 세션 scratchpad `wy-m5/research.md` — HEAD `1cb942a`, wayland-protocols 1.44, SDL 3.2.10 소스)

- vendor xml은 저장소 밖(`.gitignore`)이고 `terminal/vendor_wayland_xml.sh`가 받는다. 1.44의 `text-input-unstable-v3.xml` sha256
  `49048087a67011a8840bca889cd2b0ba374382be1ed54ec98adf7837fdca1982`.
- 오토마타(`hangul.zig`)는 순수하고, 상태(`hangul_on` · `hangul_buf` · `toggles` · 자판)는 `input.State` 하나다. 셸 쪽 한글 층
  `hangulLayer`(`input.zig:1202-1318`)의 아홉 갈래가 app 쪽에도 그대로 필요한 표다. 확정이 키보다 먼저인 자리는 `takeCommit`.
- app 쪽 키(`readKeysApp` · `appKey`)는 지금 한글 층을 안 지나고 tap도 리셋한다 — 한/영이 app에서 안 돈다.
- text-input-v3: 요청은 이중 버퍼(`commit`), 이벤트도 `done`에서 적용(순서 고정 — 한 done에 확정 + 다음 조합). `done(serial)`은 그 객체의
  `commit` 요청 수. enter/leave는 키보드 포커스를 따른다. 키 이벤트와의 관계는 xml에 없다.
- SDL3: manager를 v1로 bind, `SDL_StartTextInput` 창이 키보드 포커스를 받을 때 enable(text_input `enter`가 아니라 `wl_keyboard.enter`에).
  켜진 동안 받은 `wl_keyboard.key`마다 글자를 만든다 — 먹은 키를 보내면 두 번 찍힌다. 저장소에 SDL 텍스트 앱이 없다 — SDL 쪽은 소스 사실로만 선다.
- 기본 설정(디스크 없음)의 자판은 신세벌 PCS — `한` = `m f s`, 다음 `k`가 `한`을 확정하고 `ㄱ`. QEMU는 `lang1`을 버린다 — 전환은 `shift-spc`.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `wy-m5`(Opus — 조사도 같은 에이전트)에 두 단계로. lead는 plan · 대조 · 게이트 · commit.

- 단계 A — xml · protocol · 객체 상태 · 포커스의 enter/leave · `imeActive` · `imeSend`(아직 아무도 안 부름) · `tars-wl-test --text-input`.
  키 경로는 한 바이트도 안 바뀐다. 할 일 1~3.
- 단계 B — 오토마타 연결 · 키 소비 · 포커스 이동 확정 · 체인. 할 일 4~6.

## 착수 전에 확정한 것

1. vendor 스크립트에 fetch 한 줄(+ 머리 주석), `build.zig`에 `addCustomProtocol` + `generate("zwp_text_input_manager_v3", 1)`. 컨테이너의
   `/usr/share/wayland-protocols/…` sha256과 같은지 한 번 잰다.
2. 객체 상태(결정 43): pending/current enable, commit 셈, entered surface. 순수 셈은 `wl_logic`(연속 enable, enable 없는 commit, enter 뒤 리셋,
   leave 뒤 요청 무시, serial 셈)에 호스트 검사. 상태 요청은 받기만, content_type은 `wl> ti content purpose= hint=` 한 줄.
3. `setFocus`: `selection` → text_input `enter` → 키보드 `enter`, 옛 클라이언트에는 text_input `leave`(키보드 leave 근처). 포커스 클라이언트가
   `get_text_input`을 늦게 보내면 그 자리에서 `enter`. 로그 `wl> ti enable to=ID` · `wl> ti disable to=ID`(current가 바뀔 때).
4. `imeActive() bool`: 키보드 포커스 창의 클라이언트에 enabled이고 entered가 그 surface인 text_input이 있다. `imeSend(commit, preedit)`:
   commit이 있으면 `commit_string`, 늘 `preedit_string(preedit, len, len)`, `done(commits)`. 로그 `wl> ime to=ID commit=… preedit=…`(빈 것은 `(none)`).
5. app 키(결정 40 · 41): `Context.ime`(읽는 순간의 `imeActive`). false면 지금과 같다. true면 누름을 `hangulLayer`에 — `.redraw` 소비,
   `.bytes` 소비 + commit에 덧붙임, null이면 확정분을 먼저 IME로 내고 키는 제 길로. CapsLock · 왼쪽 Ctrl tap 판정도 ime일 때 app 쪽에서.
   `AppKeys`의 키 배열을 `AppOut = union(enum) { key, ime }`로 — 차례대로 `srv.key` / `srv.imeSend`. 넘치면 지금처럼 버림(크기 128).
   반복은 지금처럼 `.none`.
6. 포커스 이동(결정 42): `syncFocus` 머리에서 포커스가 바뀌고 조합이 있으면 주인(`hangul_owner: shell | app`)에게 확정 — app이면 `imeSend(조합, "")`,
   셸이면 그 PTY에. 창이 닫혀 잃으면 버린다. 포인터 `.cancel`의 창 slot `continue`(`main.zig:4033`)도 이 길을 탄다. tap은 셸 ↔ 앱 전환에 리셋.
7. 상태 줄: app 쪽에서 한/영이 바뀌면 redraw. app 길에서도 `hangul> on= preedit=` 줄을 찍는다.
8. `tars-wl-test --text-input`: manager bind, 창보다 먼저 `get_text_input`, text_input `enter`에 enable + `set_content_type(none, normal)` + `commit`
   (`wl-test> ti enter`), `leave`에 `wl-test> ti leave`. 이벤트는 pending에 담고 `done`에서 `wl-test> commit text=…`(있을 때) · `wl-test> preedit text= cursor=a,b` ·
   `wl-test> done serial=N match=1|0`.

## 체인

wayland 부팅 1, 판정 25 뒤 · 9 앞:

26. 켠 창의 조합 · 확정, 두 번 안 감. `tars-wl-test --follow-size --text-input > /tmp/wl6.log &` → `wl> ti enable to=ID`. `shift-spc` → `hangul> on=true`.
    `m f s` → `wl> ime to=ID commit=(none) preedit=한`, 그동안 `wl> key code=50|33|31 … to=ID` 0줄. `k` → `commit=한 preedit=ㄱ`. `spc` →
    `commit=ㄱ preedit=(none)` 다음 줄에 `wl> key code=57 state=1 to=ID`(확정 먼저). `shift-spc`로 끔. 클라이언트 줄 `c26-2-0-0`(commit 2 · key 50 0 · match=0 0).
27. 포커스를 잃으면 확정. 켜고 `m f`(preedit `하`) → `Cmd+[` → `wl> ime to=ID commit=하 preedit=(none)`이 키보드 leave 줄 앞, 셸 `hangul> preedit=(none)`.
28. 켜지 않은 창은 지금처럼 키. `--text-input` 없는 창, 한글 켬, `m` → `wl> key code=50 state=1 to=ID2` 1줄, `wl> ime` 0줄. 끝에 끈다.

## 할 일

1. (A) xml · build · global · 객체 상태 · `wl_logic` 셈과 호스트 검사.
2. (A) `setFocus`의 enter/leave 순서, 늦은 `get_text_input`, `imeActive` · `imeSend`.
3. (A) `tars-wl-test --text-input`. 손으로(임시 스크립트) `ti enter` · `wl> ti enable` 줄을 한 번.
4. (B) `Context.ime`, `appKey`의 한글 층 · tap, `AppOut`, `readKeyboardApp`의 차례 보내기, 상태 줄 · `hangul>` 줄. `input_test`에 app 갈래.
5. (B) `syncFocus`의 확정 · `hangul_owner` · 포인터 `.cancel` 창 slot · tap 리셋.
6. (B) 판정 26~28, 머리 주석 · PASS 줄. 도움말(`docs/help/desk.md` 또는 한글 도움말)에 "텍스트 입력을 켠 앱에서는 한/영 전환과 조합이 셸과 같다" 한 줄.
7. lead: 체인 · verify grep · 루트 게이트.

## 판정

- 호스트 검사, 체인 wayland · hangul · pointer · display PASS(hangul은 셸 쪽 회귀), 루트 게이트 35/35, verify mismatch 0.

## plan에서 실측할 것

1. 컨테이너 xml sha256. 2. zig-wayland 이름(`zwp.TextInputManagerV3` · `zwp.TextInputV3`). 3. 디스크 없는 부팅의 `hangul layout=… toggles=` 줄.
4. 판정 26에서 `ti enable`이 `shift-spc`보다 먼저인가(경쟁이면 그 줄을 기다린다). 5. 바퀴 순서상 `syncFocus`보다 먼저 키를 읽는 길이 있는가.
6. 서버 로그에 한글이 그대로 찍히는가. 7. SDL에서 한 done의 commit + preedit — 실측 불가(SDL 텍스트 앱 없음)를 결과에 적는다.

## 결과

구현은 `wy-m5`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A: text-input xml(1.44, 컨테이너의 Debian 패키지와 sha256 같음) · `zwp.TextInputManagerV3` 1 · 객체 상태(`wl_logic.TextInput`, 단언 13 —
   leave 뒤 commit도 serial에는 센다) · `setFocus`의 순서(text_input `leave` → 키보드 `leave`, selection → text_input `enter` → 키보드 `enter`) · 늦은
   `get_text_input`의 enter · `imeActive` · `imeSend`(부르는 자리 없음) · `tars-wl-test --text-input`. 키 경로 불변. 체인 단독 terminal · wayland(413초) ·
   hangul · pointer PASS, verify mismatch 0. 디스크 없는 부팅은 `hangul layout=shin_pcs … toggles=hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin`.
   plan과 다른 것: `wl> ti enable/disable` 줄은 commit뿐 아니라 enter · leave · 창 사라짐 · destroy로 current가 바뀔 때도 찍힌다.
