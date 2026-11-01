# TARS Multi Click — Design

Date: 2026-11-01
Status: MC-M0 끝(2026-11-01, 실측), MC-M1 착수 전. plan은 `docs/plans/2026-11-01-tars-multi-click-mc-m0.md`.

PD design(`docs/specs/2026-10-05-tars-pointer-devices-design.md`)의 비목표 2 "더블클릭 단어 선택 · 세 번 클릭 줄 선택 · Shift
클릭으로 늘리기"를 연다. 사용자가 2026-11-01에 HANDOFF의 "PD 비목표" 셋(더블클릭 · 휠 방향 · 포인터 가속) 가운데 골랐다. 같은
자리에서 정한 것 둘:

- 범위는 더블 + 트리플이다. Shift 클릭 늘리기는 비목표로 남긴다(아래 "비목표" 1).
- 뗌은 곧바로 복사다. 끌기와 같은 규칙 "뗌 = 클립보드 + copy mode 종료"(PD 결정 6)를 그대로 따른다.

## 한 줄 요약

왼쪽 버튼을 500ms 안에, 처음 누른 자리에서 한 칸 너비(8픽셀) 안에서 다시 누르면 두 번째는 단어, 세 번째는 줄을 고른다.
누른 채 끌면 단어 · 줄 단위로 늘어나고, 떼면 그 글자가 클립보드에 들어간다(`Cmd+C`와 같은 바이트). 횟수를 세는 것은 순수한
`pointer.Gesture`이고, 시각은 커널이 이벤트에 찍은 `ev.time`(장치를 열 때 `CLOCK_MONOTONIC`으로 고른다)이다. 단어 경계는 `w`/`b`가
이미 쓰는 `WORD_BOUNDARY`와 라이브러리의 `selectWord` · `selectWordBetween`이 판정한다.

## 배경 — 착수 전 조사 (2026-11-01, HEAD `5eed148`)

1. 클릭 하나의 길. `drainPointer`(`terminal/src/main.zig`)가 evdev 이벤트를 디코더(`pointer.Mouse` · `touchpad.Touchpad`)에 먹이고,
   버튼 전이를 `PointerEdge{ down, button, x, y }`로 회차마다 모은다. 시각은 안 담는다. `PointerWire.edge` → `press` · `release`가
   픽셀을 칸으로 바꿔 `pointer.Gesture`에 넘기고, 돌아온 `Intent`(`cancel` · `focus` · `select_start` · `select_to` · `scroll` ·
   `copy`)를 `PointerWire.run`이 `else` 없는 switch로 실행한다.
2. `Gesture`의 상태는 `idle · pressed · dragging · ignored`다. 누름은 copy mode에 들어가지 않고(클릭마다 `COPY`가 한 프레임
   뜨는 것을 막으려고), 첫 칸 이동이 `select_start` · `select_to`를 낸다. 뗌은 `dragging`이고 누른 패널이 copy mode일 때만
   `copy`를 낸다. 클릭(안 끈 뗌)은 아무 일도 없다.
3. 선택은 copy mode의 기계다. `vt.Screen.copyEnterAt`이 커서를 놓고 `copySelect(.char)`, `copyPointTo`가 끝을 옮기고, 모든 이동
   수단이 `copyApply(anchor, cursor)`라는 문 하나를 지난다(CM design 결정 11). 앵커는 지금 선택의 `start()`다. 선택 방식은
   `SelectKind = enum { char, line }` 둘이고, `.line`은 `copyLineSel`이 양 끝을 `selectLine`으로 넓힌다.
4. 단어 경계는 CN-M0이 이미 정했다 — `vt.zig`의 `WORD_BOUNDARY`(ghostty 검사의 기본값과 같은 20개)와 라이브러리 `selectWord`.
   `selectWord`는 공백 덩어리도 한 단어로 세고, 쓰이지 않은 셀에서는 null이다.
5. 시각. 마우스 디코더는 `ev.time`을 안 본다. 터치패드 디코더만 탭 판정(180ms)에 `ev.time`을 마이크로초로 넘겨 쓴다. 장치를 열
   때 `EVIOCSCLOCKID`를 안 부르므로 evdev의 기본 시계 `CLOCK_REALTIME`이다 — chronyd가 시계를 크게 맞추는 순간 두 이벤트의 차가
   틀어진다(터치패드 탭도 같다).
6. 라이브러리에 같은 기계가 있다. 우리가 빌드하는 ghostty(`terminal/ghostty-src/src/terminal/SelectionGesture.zig`, `lib_vt`가
   `SelectionGesture`로 export)는 `repeat_interval` 안 · `max_distance` 안의 누름을 1 → 2 → 3으로 세고(3에서 멈춘다), 횟수마다
   cell · word · line으로 고르고 끌기를 넓힌다. 앱(`Surface.zig`)은 `max_distance`에 셀 너비, `repeat_interval`에
   `click-repeat-interval`(0이면 OS 값, 없으면 500ms)을 넘긴다. 단어 끌기는 `dragSelectionWord` — 누른 자리에서 끄는 자리
   쪽으로 가장 가까운 단어(`selectWordBetween`)와 그 반대 방향의 단어를 이어 붙인다. 줄 끌기는 `dragSelectionLine`. 둘 다 private
   함수지만 몸통이 부르는 `Screen.selectWordBetween` · `selectLine`은 public이다.
7. 게이트가 클릭을 넣는 법. `pointer/check.sh`의 `hmp`는 열어 둔 fd 3에 HMP 명령 한 줄을 쓰고 50ms 잔다. `button_down` ·
   `button_up`은 `press` · `release` 줄이 하나 늘 때까지(0.1초 간격, 15초) 기다린다. 기다리지 않고 `mouse_button 1` · `0` · `1` ·
   `0`을 이어 보내면 명령 사이가 약 50ms다. 게스트가 받는 `ev.time`의 간격은 재 본 적이 없다(MC-M0).
8. 마우스 보고(PD-M4). 자식이 모드 9 · 1000 · 1002 · 1003을 켰고 copy mode가 아니고 Shift가 없으면 누름은 자식의 것이고
   (`pointer.Grab`) `Gesture.handOff`가 `ignored`로 둔다. Shift를 누른 클릭은 우리 것이다.
9. 로그. 누름은 `terminal: pointer> press leaf=L row=R col=C`(여백이면 `press none`), 뗌은 `pointer> release drag=0|1`, 복사는
   `clip> len=N text=…` 뒤 `copy> yank`. `pointer/check.sh`는 `press` 줄을 글자 그대로 비교하는 자리가 여럿이다 — 이 줄의 모양을
   바꾸면 그 비교가 다 흔들린다.

## 실측 (M0, 2026-11-01)

값과 표는 MC-M0 plan의 "실측한 것" 절에 있다. 결정에 닿는 것만 옮긴다.

1. `EVIOCSCLOCKID(CLOCK_MONOTONIC)`가 게스트에서 `rc=0`이고, 그 뒤 `ev.time`과 읽은 순간의 단조 시계 차가 0.05~0.23ms다(결정 2).
2. 게이트의 `hmp` 네 명령에서 두 누름 차는 단독 96.8~117.6ms, 루트 게이트 부하 아래 103.1~119.7ms다. 500ms까지 380ms가 남는다 —
   위험 1의 대책은 안 쓴다.
3. 결정 4의 단어 식은 오른쪽 · 왼쪽 끌기 · 빈 칸으로 끌기 · soft wrap에서 섰다. 공백을 두 번 누르면 공백만이 아니라 이웃한 경계
   문자(괄호 · 따옴표 등)와 한 덩어리이고, `selectionString`이 끝 공백을 자른다(`)  ` → `)`). ghostty와 같아 그대로 둔다.

## 결정

### 결정 1 — 횟수는 우리 `pointer.Gesture`가 센다. 라이브러리 `SelectionGesture`는 안 쓴다

조사 6의 기계를 그대로 쓰면 횟수 · 시간 · 거리 판정을 안 짜도 된다. 그래도 안 쓴다. 이유 셋.

- 라이브러리 것은 화면(`Terminal`) 하나에 하나다. 우리는 패널마다 `vt.Screen`이 따로라, "다른 패널을 누르면 처음부터"를 우리가
  패널 사이에서 따로 맞춰야 한다. 클릭의 주인은 패널이 아니라 포인터 하나다.
- 결과로 `Selection`을 돌려주고 호출자가 `Screen.select`로 바로 놓는다. 그러면 copy mode의 앵커(`copy_cursor` + `copyApply`)를
  건너뛰는 두 번째 선택 경로가 생긴다. 끄는 중에 키보드의 `v` · `V` · `w`가 copy 표로 가는데(PD 결정 6의 표) 그 키들은 우리 앵커를
  본다 — 두 경로의 앵커가 어긋나면 "어떤 수단으로 늘렸느냐에 따라 복사되는 글자가 다르다"가 된다.
- 어려운 부분(단어 경계)은 어느 쪽이든 라이브러리 몫이다(결정 4). 우리가 새로 짜는 것은 시각과 픽셀을 비교하는 몇 줄이고, 그
  몇 줄은 순수해서 호스트 `pointer_test`가 시각을 숫자로 넣어 본다.

라이브러리의 규칙(간격 · 거리 · 3에서 멈춤)은 그대로 옮긴다. 다른 것은 "끈 누름 뒤는 처음부터"(결정 3) 하나다.

### 결정 2 — 시각은 `ev.time`이고, 장치를 열 때 `CLOCK_MONOTONIC`을 고른다

`PointerEdge`에 `t_us: i64`를 더한다. 값은 그 전이를 만든 이벤트(마우스는 `SYN_REPORT`, 터치패드 탭도 끝낸 `SYN_REPORT`)의
`ev.time`을 마이크로초로 바꾼 것이다 — 터치패드 디코더에 넘기는 식과 같다. 디코더는 안 바꾼다. `drainPointer`가 그 이벤트의
시각을 전이 칸에 함께 담는다.

우리가 poll에서 깬 시각을 쓰지 않는 이유. 사람이 누른 간격은 커널이 찍은 시각에 있고, 우리가 깨어난 시각에는 우리 회차의 지연이
섞인다. 프레임을 그리는 동안 두 클릭이 한 회차에 같이 들어오면 우리 시계로는 간격이 0이 된다.

장치를 연 직후 `EVIOCSCLOCKID`(`_IOW('E', 0xa0, int)`)에 `CLOCK_MONOTONIC`을 넘긴다. 조사 5 — 기본 `CLOCK_REALTIME`은 시계
맞춤에 뛴다. 실패해도 장치는 쓴다(로그 한 줄). 그때는 뒤로 간 시각을 "처음부터"로 친다(라이브러리 `timeSince`와 같다). 터치패드의
탭 판정도 같은 시계를 받는다 — 차만 쓰므로 동작은 같고, 시계 맞춤에 안 흔들리게 된다.

### 결정 3 — 반복의 조건: 500ms · 8픽셀 · 같은 잎 · 앞 누름이 안 끌렸다

새 누름이 앞 누름의 반복(횟수 + 1)이 되는 조건은 넷 다다.

1. 앞 누름과의 시각 차가 0 이상 `MULTI_CLICK_US = 500_000` 이하다. 500ms는 ghostty의 기본값이고 macOS 기본과 같다. GTK는 400ms다.
   설정은 비목표 3.
2. 이 연속의 첫 누름 자리에서 픽셀 거리가 `CELL_W`(8) 이하다. 라이브러리처럼 마지막 누름이 아니라 첫 누름에서 잰다 — 손이
   조금씩 흘러도 세 번째가 첫 자리에서 멀어지면 끊긴다. 칸이 아니라 픽셀인 이유는 칸 경계 위를 누르면 한 픽셀 떨림에도 칸이
   바뀌기 때문이다. 터치패드의 탭은 패드의 2% 안에서 움직여도 탭이다(PD-M3) — 그 떨림이 화면 몇 픽셀이 된다.
3. 같은 워크스페이스의 같은 잎이다. 패널 경계 근처에서 두 번 누른 것이 두 패널에 갈라지면 반복이 아니다.
4. 앞 누름이 끌기가 되지 않았고(`dragging`에 안 들어갔고) 자식의 것(`handOff`)도 여백(`press none`)도 아니었다. 끈 뒤의 뗌은
   이미 복사하고 모드를 나갔다 — 그 직후의 클릭을 "더블"로 읽으면 사람이 의도하지 않은 단어 선택이 된다. ghostty는 끈 누름
   뒤에도 센다. 여기만 다르다.

횟수는 3에서 멈춘다(네 번째도 줄). 라이브러리와 같다. xterm은 감는다(넷째가 다시 문자) — 감기는 쪽은 실수로 한 번 더 누르면
선택이 사라진다.

조건이 깨지면 그 누름이 새 연속의 첫 누름(횟수 1)이다.

### 결정 4 — 두 번째 누름이 단어를, 세 번째가 줄을 곧바로 고른다. 경계는 라이브러리가 판정한다

횟수 1은 지금과 같다 — 누름은 copy mode에 안 들어가고 첫 칸 이동을 기다린다(조사 2).

횟수 2 · 3은 누름에서 곧바로 고른다. 기다릴 이유가 없다 — 두 번째 누름은 이미 "고르겠다"는 뜻이고, 첫 클릭이 `COPY`를 깜빡이지
않게 한 PD 결정 6의 이유는 첫 누름의 것이다. `Gesture`가 `dragging`으로 가고 `select_start`를 낸다. 그래서 뗌은 기존 길 그대로
`copy`를 낸다(결정 5).

`vt.Screen.SelectKind`에 `.word`를 더한다. `copyApply`의 갈래 하나다.

- `.word`: 앵커 쪽 단어 = `selectWordBetween(anchor, cursor)`, 커서 쪽 단어 = `selectWordBetween(cursor, anchor)`. 커서가 앵커보다
  앞이면 `(커서 쪽.start, 앵커 쪽.end)`, 아니면 `(앵커 쪽.start, 커서 쪽.end)`. 라이브러리 `dragSelectionWord`의 몸통을 옮긴
  것이다(private이라 부를 수 없다). 앵커와 커서가 같으면 그 자리의 `selectWord` 하나다.
- `.line`: 이미 있는 `copyLineSel`이다. 세 번째 누름이 `copySelect(.line)`이면 끌기도 줄 단위로 따라온다 — 키보드 `V`와 같은 길.

경계 문자는 `WORD_BOUNDARY` 하나다. 더블클릭과 `w`/`b`가 다른 경계를 쓰면 "`w`로 간 자리와 더블클릭이 고른 단어가 다르다"가 된다.

단어가 없는 자리(쓰이지 않은 셀)를 두 번 누르면 `selectWord`가 null이다. 그때 선택은 비고, 뗌의 `copyYank`가 null을 돌려
클립보드를 그대로 두고 모드를 나간다 — 이미 있는 길이다(`clip>` 줄이 안 나온다). 공백 위를 두 번 누르면 공백과 이웃한 경계 문자의
덩어리가 고른다(실측 3, ghostty와 같다).

앵커가 단어 선택의 `start()`라는 점이 하나 걸린다. `copyApply`는 앵커를 "지금 선택의 start"로 받는데(조사 3), `.word`의 start는
누른 자리가 아니라 그 단어의 첫 글자다. 거기서 다시 `selectWordBetween`을 불러도 같은 단어가 나오므로 결과는 같다. 왼쪽으로 끌어
선택이 뒤집히면 start가 커서 쪽 단어의 첫 글자가 되는데, 그러면 앵커가 끌려간다. 이것을 막으려고 `.word`일 때는 앵커 pin을
선택에서 읽지 않고 따로 든다(`copy_word_anchor`, 누른 자리를 `trackPin`). 줄 선택은 `copyLineSel`이 앵커 줄을 이미 따로 다루므로
안 바꾼다. 어느 쪽이 맞는지는 호스트 `vt_test`가 "오른쪽으로 끌었다가 앵커 왼쪽으로 넘어가기"로 본다(MC-M1).

### 결정 5 — 뗌은 지금 길 그대로 복사한다

사용자 결정(2026-11-01). 더블 · 트리플도 `dragging`에서 떼므로 `Gesture.release`가 `copy`를 낸다. `PointerWire.run`의 `.copy`
갈래가 `clips.yank` → `copy> yank` → `forceMode(.normal)`. 반전은 누른 동안만 보이고 떼면 사라진다 — PD 비목표 5(뗀 뒤 반전
남기기)는 그대로 비목표다.

### 결정 6 — `Intent.select_start`가 방식을 든다

`select_start: Cell`을 `select_start: Start`(`Start = struct { at: Cell, unit: Unit }`, `Unit = enum { char, word, line }`)로
바꾼다. 새 variant 둘(`select_word` · `select_line`)을 더하지 않는 이유 — 셋은 "copy mode에 들어가며 이 칸에서 선택을 시작한다"는
한 일이고 갈래는 방식 하나뿐이다. 실행 쪽(`PointerWire.run`)은 `copyEnterAt(col, row, unit)`에 넘긴다. `pointer.zig`는
`vt.zig`를 import하지 않으므로(머리 주석) `Unit`은 `pointer.zig`의 것이고 `main.zig`가 `vt.Screen.SelectKind`로 옮겨 담는다.

`copyEnterAt`이 방식을 받는다. `.char`면 지금과 같고, `.word` · `.line`이면 `copySelect`에 그 방식을 넘긴다.

### 결정 7 — 로그: `press` 줄은 그대로 두고, 반복일 때만 `repeat` 줄 하나

`press` 줄의 모양을 안 바꾼다(조사 9). 횟수가 2 이상인 누름에서 `press` 줄 바로 뒤에
`terminal: pointer> repeat n=N dt=MS` 한 줄을 찍는다. `dt`는 앞 누름과의 차(밀리초, 내림)다. 게이트는 `n`을 판정하고 `dt`는 읽기만
한다(TCG의 시각이라 값이 흔들린다). 횟수 1에서 이 줄이 없다는 것이 "느린 두 클릭은 반복이 아니다"의 판정이 된다.

### 결정 8 — 마우스 보고 · 터치패드는 같은 길을 탄다

- 자식이 마우스를 원하는 패널(vim `mouse=a`)에서 맨 더블클릭은 자식의 것이다 — vim이 자기 더블클릭을 한다. `handOff`가 연속을
  끊는다(결정 3의 4). Shift를 누른 더블클릭은 우리 것이고 단어를 고른다.
- 터치패드의 탭은 끝낸 `SYN_REPORT`에서 누름 · 뗌 둘을 함께 낸다(PD-M3). 두 번 탭하면 두 누름의 차가 "두 탭이 끝난 시각의
  차"이고 그것이 500ms 안이면 더블이다. 탭-끌기(두 번째 탭을 누른 채 끌기)는 PD-M3이 안 만들었고 이번에도 안 한다(비목표 5).

## 검증

호스트(MC-M1).

- `pointer_test`: 시각 · 자리를 숫자로 넣어 반복의 조건 넷(결정 3)을 각각 깨 본다 — 501ms · 9픽셀 · 다른 잎 · 끈 뒤 · `handOff`
  뒤 · 여백 뒤 · 뒤로 간 시각. 1 → 2 → 3 → 3. 두 번째 누름의 `Intents`가 `cancel` · `select_start(word)`이고 뗌이 `copy`.
- `vt_test`: `.word` 방식의 `copyApply` — 한 단어, 오른쪽으로 끌어 다음 단어까지, 앵커 왼쪽으로 넘어가기(결정 4의 앵커),
  공백 덩어리, 쓰이지 않은 셀(null), 줄 넘김(soft wrap)으로 이어진 단어. 문자열은 `selectionString`으로 비교한다.

게스트(MC-M2, `pointer` 체인 부팅 A에 검사를 더한다). 판정은 `clip>` 줄이다(화면 에코와 무관, PD 검사 17과 같다).

1. 단어 위 더블클릭 → `repeat n=2` 한 줄, `clip> … text=<그 단어>`, 상태 줄 `COPY`가 꺼진다.
2. 트리플클릭 → `repeat n=3`, `clip>`이 그 줄(끝 공백 없이).
3. 더블클릭 뒤 누른 채 오른쪽 다음 단어로 끌기 → 두 단어가 통째로(첫 단어의 앞 글자가 잘리지 않는다).
4. 느린 두 클릭(사이 `sleep 0.8`) → `repeat` 줄 없음, 새 `clip>` 줄 없음.
5. 끌어 복사한 직후의 클릭 한 번 → `repeat` 줄 없음(결정 3의 4).

mutation(MC-M2): 간격 비교를 늘 거짓으로 → 검사 1 빨강. `.word`를 `.char`로 → 검사 1의 `clip>` 글자가 다르다. 끈 뒤 조건을 지움 →
검사 5 빨강.

## Milestone

- MC-M0 — 실측. (1) evdev 기본 시계가 `CLOCK_REALTIME`이고 `EVIOCSCLOCKID`가 translate-c로 넘어와 게스트에서 성공하는가. (2)
  `pointer` 체인과 같은 QEMU에서 HMP `mouse_button 1` · `0` · `1` · `0`을 50ms 간격으로 보낼 때 게스트 `ev.time`의 두 누름 차 —
  단독과 루트 게이트 부하 아래. 500ms에 얼마나 여유가 있는지가 검사 1~3의 성립 조건이다. (3) `selectWordBetween`이 우리
  `WORD_BOUNDARY`로 결정 4의 모양을 내는가(호스트 프로브). 코드는 안 남긴다.
- MC-M1 — 순수 층. `pointer.Gesture`의 횟수 세기와 `Intent.select_start`의 방식, `vt.Screen`의 `.word` 방식과 `copyEnterAt`의 방식
  인자. 호스트 테스트만. `main.zig`는 컴파일이 되게 하는 최소(방식 `.char`를 넘긴다)까지.
- MC-M2 — 배선과 게이트. `PointerEdge.t_us` · `EVIOCSCLOCKID` · `repeat` 줄 · `pointer` 체인 검사 다섯 · mutation 셋 · 루트 게이트.
  닫기.

## 위험

1. 게이트 부하 아래 HMP 명령 사이가 500ms를 넘으면 검사 1~3이 간헐로 빨개진다. M0이 잰다. 여유가 작으면 검사 쪽에서 네 명령을
   한 번의 `printf`로 fd 3에 쓰는 식으로 줄인다(코드의 500ms는 사람의 값이라 게이트에 맞춰 안 늘린다).
2. TCG의 게스트 시계가 부하 아래 늦게 가면 `ev.time`의 차가 실제보다 작거나 클 수 있다. 같은 이유로 M0이 루트 게이트 아래에서
   잰다.
3. 앵커를 따로 드는 `trackPin`(결정 4)은 copy mode가 끝날 때 놓아야 한다. 가지치기는 이미 앵커 줄의 변화로 알아채고
   `copyExit`을 부른다(`vt.zig`의 `copy_pruned = true` 두 자리) — 앵커 pin을 `copyExit` 안에서 `untrackPin`하면 모든 출구(Esc ·
   `y` · 뗌 · 가지치기 · `resetInputMode`)가 한 자리를 지난다. 놓지 않으면 pin이 PageList에 쌓인다.
4. 두 클릭 사이에 출력이 와서 같은 자리의 글자가 바뀌면 두 번째 누름은 새 글자의 단어를 고른다. 라이브러리도 같다(조사 6의
   머리 주석 "선택은 그 순간의 화면으로 계산한다"). 고치지 않는다.
5. 첫 누름의 `cancel`이 키보드 copy mode를 닫는다(PD 결정 6). 키보드 copy mode에서 더블클릭하면 첫 누름이 모드를 닫고 두 번째가
   새로 연다 — 키보드로 만들던 선택은 사라진다. 지금 클릭의 동작과 같아 바꾸지 않는다.

## 비목표

다시 열 조건을 함께 적는다.

1. Shift 클릭으로 늘리기. 뗌이 복사하고 모드를 나가므로 늘릴 선택이 남아 있지 않고, Shift는 자식의 마우스 보고를 넘는 키로 이미
   쓰인다(PD 결정 12). 뗀 뒤 반전 남기기(PD 비목표 5)가 열리면 함께 연다.
2. 네 번 이상의 클릭 방식(문단 · 명령 출력 — 라이브러리의 `.output`). 셸 통합(OSC 133)이 없으면 출력 경계를 모른다.
3. 간격 · 거리의 설정(`tars.conf`). PD 비목표 7과 함께 연다.
4. 더블클릭이 URL 전체를 고르기(ghostty `linkAtPin`). URL 인식이 없다(PD 비목표 12).
5. 터치패드의 탭-끌기 · 두 손가락 탭 = 오른쪽 버튼. 실기에서 필요해지면.
6. 오른쪽 버튼의 단어 선택(ghostty는 문맥 메뉴용으로 한다). 오른쪽 메뉴가 없다(PD 비목표 8).
7. 가장자리 자동 스크롤(PD 비목표 3) — 단어 · 줄 끌기에도 없다. 끄는 중의 휠이 대신이다.

## 관련

- PD design 결정 6(선택은 copy mode의 기계) · 결정 12(마우스 보고) · 비목표 2(이번에 연 것).
- CM design 결정 11(이동 수단은 `copyApply` 하나를 지난다) · CN-M0 plan(단어 경계 · `WORD_BOUNDARY`).
- `docs/decisions/project_pointer_devices.md` · `project_copy_mode.md`.
