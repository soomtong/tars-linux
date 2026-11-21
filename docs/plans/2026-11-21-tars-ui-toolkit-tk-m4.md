# TK-M4 — 비례폭 텍스트 · 텍스트 필드(text-input · preedit) · 클립보드 · 경로 입력 · 검색

Date: 2026-11-21
Design: `docs/specs/2026-11-20-tars-ui-toolkit-design.md`(결정 5 · 8 · 13 · 15, milestone 표 TK-M4), 요구사항 R-TXT-1~4, R-KIT-6, R-FM-2 · 4 · 8, R-KEY-6, 녹화 C,
WY design 결정 32~43
Status: 끝(2026-11-21). 브랜치 `app-layer-0-3`.

## 확인(조사 `tk-m4`, 세션 scratchpad `tk4/research.md` — HEAD `a8397d4`, 읽기만 한 조사)

- 영문 글자는 text-input을 켠 창에서도 `wl_keyboard`로 온다(한글 층은 `hangul_on`이 거짓이면 키를 그대로 보낸다). 한글 모드에서도 숫자 · 기호 · Space · Enter는
  "확정 → 키"로 온다(wayland 판정 26). 글자 키 표(evdev → 문자)는 어느 경우든 필요하다.
- 서버 키맵 `terminal/vendor/keymap-us.xkb`는 us · pc105 고정, 글자 키 타입은 `ALPHABETIC`(Shift+Caps는 소문자). 서버 mask의 Lock은 locked에만.
- Pretendard cmap: 조합형 자모(U+1100~11FF) 0개 · U+FFFD 없음 · 한자 없음. `…`(U+2026) · `›` · 호환 자모(U+3131~) · 결합 악센트(U+0301) · `□`(U+25A1)는 있다.
- `cg/text.zig`에는 `measure`와 그리기만 있다 — 클러스터 · 캐럿 x ↔ 색인 · 생략 · 줄 나누기 · 대체가 없고, `Utf8` 반복자는 잘못된 바이트를 소리 없이 건너뛴다.
  `shared/glyph.zig`에는 글리프가 없는지 물을 길이 없다.
- 서버의 text-input 상태는 `enter`마다 리셋된다 — 필드가 포커스인 동안 `enter`마다 다시 enable + commit. `done` 하나에 확정과 다음 조합이 같이 온다(확정이 그 뒤의
  키보다 먼저). `set_cursor_rectangle` 등은 받기만 한다. 창이 조합 중에 disable하면 서버 쪽 음절은 다음 키 배치에서 말없이 버려진다.
- 클립보드: 서버는 `set_selection`을 받는 자리에서 사본을 읽고(1 MiB · 2초) offer는 늘 서버 사본이다 — 자기 복사를 자기가 붙여도 교착이 없다. serial 값은 안 본다.
  툴킷은 SIGPIPE를 무시하지 않고 키 serial을 저장하지 않는다.
- 툴킷 스캐너에 text-input xml(`terminal/vendor/wayland/text-input-unstable-v3.xml`)과 `wl_data_device_manager`를 더하면 된다.
- wayland 판정 26~28의 한글 치기: 디스크 없는 부팅의 자판은 신세벌 PCS, `m f s` = 한, 한/영은 `shift-spc`, enable(`wl> ti enable to=ID`)을 기다린 뒤 전환.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트 `tk-m4`(Opus — 조사도 같은 에이전트)에 세 단계로. lead는 plan · 대조 · 게이트 · commit. 루트 게이트는 단계 B 뒤와 단계 C 뒤에 한 번씩.

- 단계 A — 표시: 할 일 1~3. 화면 변화는 긴 이름의 가운데 생략뿐.
- 단계 B — 편집(design의 끝나는 조건): 할 일 4~8.
- 단계 C — 필터 · 검색: 할 일 9~10. 확정은 단계 B의 결과를 보고 lead가 이 plan에 더한다.

## 착수 전에 확정한 것

1. 측정 층은 `Metrics`(advance · kern)를 받는 순수 함수다(호스트 표는 고정 폭 가짜 Metrics, 실제 글꼴 표 하나로 `measure` = 그리기의 끝 펜). 자리는 `cg/`.
2. 클러스터 = 캐럿이 설 경계: 정상 코드포인트 하나 · 잘못된 바이트 하나(표시는 `?`, 버퍼의 바이트는 그대로) · 결합 표시(U+0300~036F)는 앞 글자에 붙음 · 현대 조합형
   자모 L V T?는 한 클러스터이고 표시할 때 음절로 합친다(홀로 선 자모는 호환 자모로). 글리프가 없으면 `□`. 대체는 측정과 그리기가 같은 함수를 지난다.
   정규화는 표시에서만 — 버퍼 · 경로 · 정렬은 바이트 그대로. `shared/glyph.zig`에는 `hasGlyph` 하나만 더한다(terminal 변화 0).
3. API: 클러스터 반복자 · `caretXs` · `indexAt`(가운데를 넘으면 오른쪽) · `elideMiddle`(꼬리 쪽으로 기울임 — 확장자가 남는다, `…`도 안 들어가면 빈 글) ·
   `wrap`(공백 뒤 · 한글/CJK는 글자 단위 · 긴 낱말 강제 · 최소 금칙 · `\n` — 소비자는 TK-M6, 여기서는 순수 함수와 표만). `Painter.drawGlyphs`는 클러스터 반복자를 쓴다.
4. 글자 키 표: `tk_input.charFor(code, mods) ?u21` — Ctrl · Alt · Super가 있으면 null, 글자는 `shift != caps`면 대문자, 나머지는 Shift만. `Key`에 `backspace` · `delete`.
   호스트 검사가 `keymap-us.xkb`를 읽어 표 전부를 대조한다(키맵이 바뀌면 깨진다 — design 결정 13의 뜻).
5. `tars-files`의 이름 칸 = 행 왼쪽 16 ~ (디렉터리) `›` 왼쪽 − 4 / (파일) 막대 왼쪽 − 4, 넘치면 가운데 생략. 미리보기 이름 줄도. `tk> column` 줄에 ` shown=`.
6. 텍스트 필드 모델(순수): 바이트 버퍼(4096) · `caret` · `anchor`(클러스터 경계) · preedit(64, 버퍼에 넣지 않고 캐럿 자리에 겹쳐 그림) · `scroll_x` · 되돌리기 한 단계
   (묶음의 시작에서 스냅숏, 다시 누르면 맞바꿈). 선택이 있을 때 첫 확정 · 첫 preedit은 선택을 먼저 지운다.
7. 필드의 키: `←` `→` 클러스터 · Shift 선택 · `Opt+←` `→` 낱말(공백 · 구두점 · `/`가 경계) · Home End · `Ctrl+A` `Ctrl+E` · `Cmd+←` `→` · Backspace · Delete ·
   `Opt+Backspace` · `Cmd+A` · `Cmd+C` `X` `V` · `Cmd+Z` · Enter(앱 콜백) · Esc(앱 콜백) · 글자(`charFor`). 받지 않은 Cmd 조합은 위로.
8. 그리기: 바탕 `TK_SURFACE` 둥근 사각형, 포커스 링 2 px(새 토큰 `color.focus_ring` = accent), 선택 `TK_SELECTION`(창 포커스 없으면 흐린 색), preedit 밑줄 1 논리 px을
   baseline + 2에, 캐럿 1 px. 캐럿은 깜빡이지 않는다(깜빡이면 idle commit 0과 덤프 판정이 깨진다 — carryover). 편집의 더티는 필드 사각형.
9. text-input 클라이언트: 순수 상태 기계 `window/ime.zig`(`want(on)` · enter · leave · preedit · commit · done → 보낼 요청과 올릴 이벤트). `entered && want`면 enable +
   content_type(normal) + commit, `enter`마다 다시, `done`에서 모은 것을 한 번에 올림(serial이 달라도 적용, 로그에 `match=`). `set_cursor_rectangle`은 안 보낸다.
   `get_text_input` · `get_data_device`는 창보다 먼저.
10. 이벤트는 `tk_input.Event.ime { commit, preedit }` 하나(`done` 하나 = 이벤트 하나), `VTable.textInput`. enable의 계기는 kit `Root`의 훅(first responder가
    `wantsTextInput`) → `tk.connectRoot`가 창의 `setTextInput(on)`에(kit은 창을 모른다).
11. 앱 안에서 필드가 포커스를 잃을 때 preedit이 남았으면 클라이언트가 본문에 넣어 확정한다(WY 결정 42와 같은 뜻). 서버의 "enable에서 앱 조합을 버림"은 carryover
    (TK-M4에는 필드가 하나).
12. 클립보드: `win.copyText(bytes)`(source 하나 · mime 넷 · 마지막 키/버튼 serial, `send`에서 그 자리에서 쓰고 닫음 — 4096 이하라 파이프에 다 든다) ·
    `win.pasteText(buf)`(receive → flush → 닫기 → poll 1초씩 읽기, 동기). 창 층이 SIGPIPE를 무시한다. 붙여넣는 글은 첫 줄 바꿈에서 자른다. mime 고르기는 순수 함수.
13. 바: 창 위 한 줄(높이 32, 평소 숨김), 루트는 세로 스택 [바 | 분할 뷰]. `Cmd+L` · `Cmd+F` · `Cmd+K`가 같이 쓰고 왼쪽에 이름표. Esc는 닫기 → 포커스는 포커스 열.
14. `Cmd+L`: 포커스 열의 경로로 채우고 캐럿은 끝. Enter — 해석(절대 · `~` · 상대는 포커스 열 기준 · `.` `..` · 겹친 `/` · 끝 `/`) → 목표가 시작 경로 안이면 열 0부터,
    밖이면 `/`부터 조상마다 열 하나(깊이 32), 각 열의 선택은 다음 성분의 이름(로딩이 그 이름을 만나면 고른다), 포커스는 마지막 열, 목표가 파일이면 부모까지 열고 선택.
    없으면 바를 열어 둔 채 `tk> path error=`. kit에 `ColumnView.setColumns(sources)`. 해석은 순수 함수.
15. `Cmd+C`(필드가 포커스가 아닐 때) = 포커스 열 경로 + 선택 이름(R-FM-8).
16. 로그: `tk> ti enter|leave|enable|disable` · `tk> ime commit= preedit= serial= match=` · `tk> copy len= serial=` · `tk> send mime= len=` · `tk> cancelled` ·
    `tk> offer mimes=`|`offer none` · `tk> paste len=` · `tk> field text= action=enter|escape` · `tk> path error=`.
17. 체인 toolkit(같은 부팅, 판정 18 뒤 — 좌표는 단계가 실제 덤프로 정한다):
    - 19(A) 가운데 생략: 긴 이름 디렉터리 행 — `tk> column … shown=`에 `…`와 앞 · 뒤, `›` 왼쪽 틈에 글자 잉크 없음.
    - 20(B) 경로 복사: `Cmd+C` → `wl> selection from=ID mime=text/plain;charset=utf-8` · `clip> len=10 text=/tmp/tkf/a` → 셸에서 `Cmd+V`로 찍힘(녹화 C의 장면).
    - 21(B) 경로 필드 영문: `Cmd+L` → `wl> ti enable to=ID` → 글자 → Enter → `wl> ti disable` · `tk> columns` · 글자 수만큼 `wl> key … to=ID`.
    - 22(B, design의 끝나는 조건) 한글: `Cmd+L` → `/` → 한/영 → `m f s` → `wl> ime to=ID commit=(none) preedit=한` → 덤프의 밑줄 띠 → 한/영 → `commit=한` → 띠 없음 ·
      글자 잉크 → Enter → `/tmp/tkf/한`의 열. 먹은 키의 `wl> key … to=ID` 0. 끝에 한글을 끈다.
    - 23(B) 필드 클립보드: 셸에서 복사한 글을 필드에 `Cmd+V` → `tk> paste len=`.
18. 단계 C(단계 B 뒤에 확정, 2026-11-21): 바를 세 모드가 같이 쓴다 — `Cmd+L` 경로 · `Cmd+F` 필터 · `Cmd+K` 검색(이름표 글만 다르다). 열린 바에서 다른 모드 키는 모드를
    바꾸고 필드를 비운다. 필드에 `Delegate.changed`(글이 바뀔 때 — 타이핑 · IME 확정 · 붙여넣기 · 지움, 조합 중은 아님).
19. 필터(`Cmd+F`): 포커스 열의 항목을 이름 부분 일치(ASCII 대소문자 무시, 그 밖은 바이트)로 거른 색인 배열 — 열의 `count` · `drawRow`가 그것을 본다. 선택은 이름으로
    `follow`. Enter는 바만 닫고 필터는 남긴다, Esc는 필터를 풀고 닫는다. 다시 `Cmd+F`면 남은 글로 연다. 그 열이 다른 경로로 다시 쓰이거나 버려지면 필터도 사라진다.
    갱신(창 포커스)은 필터를 지킨다. 줄 `tk> filter text= n=`. 순수 부분(일치 · 색인)은 `files/model.zig`.
20. 검색(`Cmd+K`, R-FM-4): 뿌리 = 열 0의 경로(`/`면 `/proc` · `/sys` · `/dev` · `/run` 제외), 너비 우선, idle 한 조각 = getdents 한 번(`DirSource` 그대로 — 호스트 검사는
    가짜 소스와 주입한 시계), 숨김 · 링크 따라가기 없음, 상한 20만 항목 · 10초(`tk> search walked= ms= capped= results=`). 후보 = 질의가 뿌리 기준 상대 경로의 부분열
    (ASCII 대소문자 무시, 한글은 음절 그대로). 점수 = 연속 · 성분 처음 · 이름 안 일치 가산, 짧은 경로 우대, 상위 100(같은 점수는 경로 바이트 순 — 전순서). 질의가 앞을
    이으면 지난 후보만 다시 매긴다(걷기가 안 끝났으면 새 항목도). 결과는 열 자리를 덮는 `kit.List` 하나(행 = 상대 경로, 가운데 생략), `↑` `↓`는 필드에서 리스트로 넘긴다.
    Enter = 고른 결과를 경로 바의 Enter와 같은 길로(파일이면 부모까지 열고 선택), Esc = 닫고 열로 돌아감. 초성 검색 · 결과 미리보기 · 필터의 fuzzy는 뒤로.
21. 판정 24 · 25(같은 부팅, 넷째 앱에 이어서): 24 `Cmd+F` · `m` → 첫 열에 `m.txt` 한 행 · `tk> filter text=m n=1` → Esc로 넷. 25 `Cmd+K` · `xtxt` →
    `tk> search … results=`와 결과 행에 `a/b/x.txt` · `한/x.txt` → Enter → 열 셋 · 선택 `x.txt`. PASS 이름표 `TK-M4`.

## 할 일

1. (A) `glyph.hasGlyph`, `cg/`의 클러스터 · 대체 · NFD 합치기 · `caretXs` · `indexAt` · `elideMiddle` · `wrap`, `drawGlyphs`를 클러스터 반복자로.
2. (A) `tk_input.charFor` · `Key.backspace` · `delete`(반복하는 키). `tars-files` 이름 칸 · 미리보기 줄의 생략과 `shown=`. 판정 19.
3. (A) 호스트 표: 클러스터(잘못된 바이트 · 결합 표시 · L V T · 홀로 선 자모 · 4바이트), 대체의 폭이 측정 = 그리기, 캐럿 x 왕복, 실제 글꼴에서 `measure` = 끝 펜,
   생략(들어가면 그대로 · 결과 폭 ≤ max · 경계 · 꼬리 기울기 · `…`도 안 들어감 · NFD 이름), 줄 나누기, `charFor` = 키맵 대조 + Shift/Caps 넷 + 명령 수정키는 null,
   긴 이름 행의 부분 = 통째.
4. (B) 스캐너 둘, 창 층 text-input(`ime.zig`) · data device · serial 저장 · SIGPIPE 무시, `Event.ime` · `VTable.textInput` · `Root` 훅.
5. (B) `kit.TextField`(확정 6~8) · 토큰.
6. (B) `tars-files`: 바 · `Cmd+L` · 경로 해석 · `ColumnView.setColumns` · `Cmd+C`.
7. (B) 호스트 표: 필드 편집 표 · IME 적용(확정이 선택을 지움 · preedit은 버퍼를 안 바꿈 · 한 done에 확정 + preedit · 포커스 잃음은 본문으로) · 스크롤 · ime 상태 기계 ·
   mime 고르기 · 붙여넣기 정리 · 경로 해석 · `setColumns` · 필드 그림 픽셀(밑줄 행 · 선택 · 캐럿)과 부분 = 통째.
8. (B) 판정 20~23, `docs/help/desk.md`(새 키), `measurements.md` 111.
9. (C) `Cmd+F` 필터(포커스 열, 이름 부분 일치, 안정 선택) · `Cmd+K` 검색(R-FM-4 — idle 조각 걷기 · fuzzy · 상위 100 · 10초 · 20만 상한). 세부는 단계 B 뒤에 확정.
10. (C) 호스트 표와 판정 24 · 25.
11. lead: 단계마다 대조 · commit, 단계 B 뒤와 C 뒤에 루트 게이트(36).

## 판정

- 호스트 검사, `make quick`, 체인 toolkit 두 번 연속 · terminal(공유 `glyph.zig`가 바뀐다) · wayland PASS, 루트 게이트 36/36, verify mismatch 0.

## plan에서 실측할 것

1. Pretendard의 `.notdef` · U+0301 · `…` · `›` · `□` · `?`의 13 px advance. 2. 생략이 붙은 열 그림의 `tk> draw us=`. 3. 필드 한 글자 · preedit 바뀜의 더티와 draw ·
서버 blit, 바를 여닫는 프레임. 4. `sendkey` → `wl> ime` → `tk> draw`의 지연. 5. `send` 쓰기 · 동기 붙여넣기의 게스트 시간. 6. 호스트 검사 시간 · 메모리.
7. (C) 게스트 트리의 항목 수 · 걷기 시간 · 20만 항목 점수 매기기. 8. 체인 toolkit 시간과 루트 게이트 lane(지금 111초). 9. 판정 22의 밑줄 띠 좌표. 10. enable/disable
왕복 뒤 `match=1`.

## 결과

구현은 `tk-m4`(Herdr, Opus — 조사도 같은 에이전트), lead는 대조 · 게이트 · commit.

1. 단계 A `ca95301`: `cg/layout.zig`(`Metrics`만 받는 놓기 층 — `Clusters` · `resolve` · `stops` · `caretXs` · `indexAt` · `spanWidth` · `elideMiddle` · `wrap`),
   `Painter.drawGlyphs`가 같은 `Placer`를 지남(옛 `Utf8` 반복자 지움), `glyph.hasGlyph`, `input.charFor` · `US_CHARS` · `Key.backspace` · `delete`, `tars-files` 이름 칸 ·
   미리보기 줄의 생략과 `shown=`, 판정 19. 체인 toolkit 두 번 · terminal PASS(공유 `glyph.zig`는 함수 하나 더하기 — terminal 그대로).
   판정 19의 실제 값: `shown=long-directo…bcdefghij-end` · `shown=long-file-name…efghij-tail.txt`, `›` 왼쪽 틈(화면 x 826..829)에 잉크 0.
   호스트 검사 덩어리 15: 클러스터 표(NFD 한 9바이트 → 음절 하나, 홀로 선 자모 → 호환 자모), `measure` = 그리기 끝 펜, 캐럿 x 왕복, 생략(결과 ≤ 폭 · 경계가 NFD를
   안 가름), 줄 나누기 표 열둘, `charFor` = `keymap-us.xkb` 대조(글자 키 48개).
   실측: 13 px advance `…` 9.902 · `›` 4.367 · `□` 11.324 · U+0301 0(앞 글자에 겹침). 생략 셈은 그림 시간에서 안 보인다(부분 0.80~1.37 ms).
   plan과 달라진 것: (가) 생략의 꼬리 기울기는 개수로만 — 넓은 클러스터가 꼬리를 막으면 머리가 한두 개 더 채운다. (나) 판정 19는 셋째 `tars-files`(`/tmp/tkl`)로
   (`/tmp/tkf`에 더하면 판정 15의 행 수가 바뀐다). (다) 잘못된 바이트가 이제 `?`로 보인다(옛 그림은 소리 없이 뺐다). (라) 판정 15 · 18의 `tk> column` 패턴에 ` shown=`.
   lead의 화면 판정: 4배 덤프에서 `long-directo…bcdefghij-end ›`가 `›` 앞에서 멈추고 꼬리가 남는다.
2. 단계 B `b7feb42`(design의 끝나는 조건): `kit/textfield.zig`(순수 `Model` + 뷰) · `window/ime.zig` · `window/clip.zig` · 창 층의 text-input · data device · serial · SIGPIPE 무시 ·
   `Event.ime` · `VTable.textInput` · `Root`의 ime 훅 · `ColumnView.setColumns` · `files/model.zig`의 `resolvePath` · `columnPaths` · `tars-files`의 바 · `Cmd+L` · `Cmd+C` ·
   `docs/help/desk.md` · 판정 20~23 · `measurements.md` 111. 서버는 고치지 않았다. 체인 toolkit 두 번 · terminal · wayland PASS.
   판정의 실제 값: 20 `clip> len=10 text=/tmp/tkf/a` → 셸 `Cmd+V`로 화면에 찍힘. 21 `/a/b`의 키 넷이 `wl> key … to=6`(영문은 키로 온다) · `columns n=3 focus=2 scroll=201`.
   22 `wl> ime to=6 commit=(none) preedit=한` → 덤프의 밑줄(화면 y 43, x 767..778 전부 `f4f6f8`) → `commit=한 preedit=(none)` → 그 행에 띠 없음 · 글자 잉크 →
   Enter → `tk> field text=/tmp/tkf/한 action=enter` · `한/`의 열. 한글을 켠 뒤 먹은 키의 `wl> key` 0, 앱의 `match=0` 줄 0. 23 `tk> paste len=12` → 열 셋.
   호스트 검사 덩어리 16(필드 편집 표 · IME 적용 · ime 상태 기계 100번 왕복 · mime · 경로 해석 · 필드 픽셀 — 밑줄 행 · 링 · 캐럿 · 부분 = 통째).
   plan과 달라진 것: (가) 판정 22에 `Cmd+A`(21 뒤 채워진 글을 덮어쓴다). (나) 23은 붙인 뒤 Enter까지. (다) 줄 `tk> bar open|close` · `tk> copy path=`, `send` · `paste`에
   `us=`. (라) 크기 토큰은 `tokens.zig`에 직접(`shared/theme.zig` 그대로). (마) 낱말 경계는 `/` · `-` · `.`. (바) 시작 경로 비교는 지금의 열 0.
   첫 체인 판은 FAIL이었다 — 판정 22의 "먹은 키 0"을 한글을 켜기 전의 영문 `m` `f`까지 센 판정 쪽 잘못, 켠 뒤부터 세게 고쳤다(코드는 그대로).
   lead의 화면 판정: 4배 덤프 둘 — 조합 중 `한` 아래 밑줄과 포커스 링, 확정 뒤 밑줄 없음.
   실측: 필드 편집 한 번의 더티는 필드 사각형(536 × 24) · draw 중앙 1.1 ms · 서버 blit 30~39 µs. 바를 여는 프레임 2.9~17.3 ms(통째). `send` 225~266 µs,
   동기 붙여넣기 1.2 ms. enable/disable 왕복 뒤 모두 `match=1`.
   루트 게이트 36/36 첫 판(`out/gate-logs/20261121-064938`, toolkit lane 148초), verify mismatch 0.
3. 단계 C `b0ff7d2`: `files/search.zig`(순수 — `Walker` 너비 우선 · 상한 20만/10초 · `score` · 상위 100 · `setQuery`의 이음) · `model.nameMatches` · `filterInto` ·
   바의 세 모드 · 열의 필터(갱신이 지킴) · 결과 리스트 · `TextField`의 `Delegate.changed` · 숨긴 필드는 다시 안 그림 · `docs/help/desk.md` · 판정 24 · 25 ·
   `measurements.md` 112. 체인 toolkit 두 번 · terminal PASS(첫 판부터).
   판정의 실제 값: 24 `tk> filter text=m n=1` · 첫 열에 `m.txt` 한 행 · a가 걸러져 오른쪽 열이 버려짐 → Esc에 `n=4` · 선택이 `m.txt`(행 3)를 따라감.
   25 `xtxt` → 결과 `a/b/x.txt` · `한/x.txt` → Enter → `tk> search open=/tmp/tkf/a/b/x.txt` · 열 셋 · 선택 `x.txt`.
   호스트 검사 덩어리 17(걷기 상한 · 숨김 · 링크 · 제외, 점수 순서 표, 상위 100 = 전체 정렬의 앞 100, 질의 잇기 = 처음부터, 필터의 안정 선택).
   plan과 달라진 것: (가) 판정 23의 `Cmd+Q`를 25 뒤로(같은 앱에 이어서). (나) 결과 리스트의 선택은 흐린 색 — 포커스는 필드에 있다. (다) "짧은 경로"는 바이트 길이.
   (라) 호스트 검사의 모델 모듈이 `files_search`.
   lead의 화면 판정: 4배 덤프 — 이름표 "검색" · 필드 `xtxt` · 결과 두 행.
   실측: 게스트 initrd 트리 1,633항목 걷기 74 ms, 점수 첫 글자 11.6 ms · 이음 2 ms, 결과 리스트의 다시 그림 10.6~33.2 ms(점수보다 크다 — carryover).
   네이티브 20만 가짜 항목(Debug): 걷기 43 ms · 첫 글자 49 ms.
4. 루트 게이트 36/36 첫 판(`out/gate-logs/20261121-075907`, toolkit lane 157초), verify mismatch 0. TK-M4의 게이트는 둘(단계 B 뒤 · 단계 C 뒤) 다 첫 판 PASS.
