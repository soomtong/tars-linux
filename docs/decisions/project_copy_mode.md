---
name: project_copy_mode
description: "스크롤백 위의 vim modal 선택 모드(커서 이동 → v/V → y)와 Cmd+V 붙여넣기(CM-M0~M2, 2026-08-24~26). 함정 — Cmd+V는 키 표 두 곳에 있어야 한다 · 가지치기는 pin을 무효로 만들지 않고 조용히 엉뚱한 자리를 가리킨다 · copyMove는 격자 크기를 RenderState에서 읽으면 안 된다 · 키의 뜻을 바꾸는 것은 enum을 넓히는 것과 다른 축이다"
metadata:
  node_type: memory
  type: project
---

2026-08-15 사용자 요청("실행 가능한 단계에 도달하게 되면 구현해보도록 하자") —
스크롤백이 생기면 특정 키로 선택 모드에 들어가 vim처럼 커서를 움직이고 `v`(문자) ·
`V`(줄)로 잡아 복사하고 `Cmd+V`로 붙인다. iTerm2 · WezTerm의 copy mode다. 선행 조건
셋(스크롤백 · 선택 렌더링 · 클립보드) 중 앞 둘은 TR이, 클립보드는 CM-M1이 만들었다.
design은 `docs/specs/2026-08-24-tars-copy-mode-design.md`. milestone별 경과와 게이트
시간은 2026-10-10에 지웠다(커밋 이력에 있다).

## 결정

- 진입키는 `Cmd+Shift+C`. `Cmd+C`는 모드 안에서만 뜻을 갖고 `Cmd+V`는 모드 안팎 다
  붙여넣기다(design 결정 4). IP가 `Cmd`+문자 조합을 비워 둔 것이 이 자리를 위해서였다
  ([[project_input_policy]]).
- 모드 안에서는 키를 전부 삼킨다. `handleKey`의 copy 분기가 `chord()`보다 앞이라 모드
  안에서는 Cmd 조합조차 `chord()`에 닿지 못한다. 그래서 사람에게 모드를 알리는 표시가
  필요해졌다([[project_copy_indicator]]).
- 붙여넣기는 모드를 닫지 않는다(CM-M2). 게이트가 `scrollToBottom` 억제 분기를 밟을
  유일한 길이 붙여넣은 글자의 에코였기 때문이다. 대가 — 뷰포트를 올려 둔 채 붙이면
  에코가 화면 밖에 찍혀 아무 일도 안 일어난 것처럼 보인다. 그리고 그 밟기는 대역이다.
  억제 분기가 막으려던 진짜 상황은 백그라운드 출력이고 게이트는 "분기가 실행된다"까지만
  증명한다.
- bracketed paste(결정 9)는 CM이 "셸이 받는지 실측 전에는 안 넣는다"로 비워 뒀고,
  PE-M1(2026-10-04)이 실측해 넣었다 — 자식이 모드 2004를 켰으면 감싼다
  ([[project_paste_ergonomics]]).
- 클립보드는 CM-M1이 `vt.Screen`의 버퍼 하나로 만들었는데, WP가 `Screen`을 패널마다
  두면서 패널 수만큼이 됐고 CB가 terminal 전체에 하나인 `clipboard.zig`로 옮겼다
  ([[project_clipboard_scope]]). `copyYank`가 그 `Clipboard`를 받는다.

## 선택은 우리가 안 든다

`Screen.select()`에 넘기면 라이브러리가 tracked selection으로 가져가고 뷰포트가
움직여도 따라간다. 우리가 드는 것은 뷰포트 좌표의 커서 하나와 "문자를 잡는가 줄을
잡는가"뿐이고, 앵커는 지금 선택의 `start()`다. 역방향 선택을 우리가 정렬하지 않는다 —
`selectionString`도 렌더도 `topLeft()` · `bottomRight()`를 쓰므로 `ordered()`를 부를
자리가 없다.

## 가지치기가 pin을 무효로 만들지 않는다 — 다시 조사하지 말 것

`PageList.erasePage` · `eraseRows`는 tracked pin을 살아 있는 이웃 페이지의 왼쪽 위로
옮긴다. `Screen.selection`은 그대로 남고 pin도 유효하며, 달라지는 것은 그것이 가리키는
내용뿐이다. 그래서 증상은 "선택이 사라진다"가 아니라 "조용히 엉뚱한 자리를 복사한다"
이고, 처음 계획한 `selection == null` 검사는 참이 되는 날이 없는 죽은 코드다.

처방은 앵커의 screen 좌표 y(`copy_anchor_y`)를 기억해 두고 `feed` 뒤에 비교하는 것이다.
screen 좌표는 목록 맨 위에서부터 세는 절대 좌표라 아래에 줄이 붙는 것으로는 안 변하고,
변하는 경우가 앞에서 줄이 지워졌을 때와 pin이 옮겨졌을 때뿐이다 — 그 둘이 정확히 잡고
싶은 것이다. 대체 화면(vim)으로 갈아타는 경우도 같은 조건에 걸린다. "전체 행 수가
줄었는가"로 보는 안은 버렸다 — 한 `feed`에 한 페이지(약 286줄)보다 많이 들어오면 늘어난
것과 지워진 것이 상쇄된다.

이 창이 열린 이유는 copy mode 중에 `main.zig`가 `scrollToBottom()`을 안 부르기 때문이다.
그 호출이 부수 효과로 막고 있던 "뷰포트가 history에 머무는 동안의 가지치기"가 모드
안에서만 가능해진다. WP가 패널마다 `Screen`을 옮길 때 같은 병을 다시 만났다
([[project_workspace_panes]]).

## `copyMove`는 격자 크기를 `RenderState`에서 읽으면 안 된다

`RenderState`는 마지막 `cells()`가 찍은 스냅숏이고 `init`은 그것을 `.empty`(0×0)로
둔다. 그래서 한 번도 그리지 않은 화면에서 `state.cols` · `state.rows`를 읽는 `copyMove`는
크래시 없이 조용히 아무 일도 안 한다. 실전에서 안 드러난 이유는 `main.zig`가 키를 받기
전에 이미 한 프레임을 그렸기 때문이다. 격자는 `pages.cols` · `pages.rows`에서 읽는다 —
언제나 살아 있는 값이다. `copyEnter`가 읽는 `state.cursor.viewport`는 진짜 렌더 상태라
그대로 두고, 대신 검사는 화면을 만든 뒤 `cells()`를 한 번 부르고 시작한다.

## `Cmd+V`는 키 표 두 곳에 있다 — 한쪽만 고치면 조용히 안 먹는다

`chord()`의 Meta 분기가 모드 밖의 붙여넣기를, copy 표가 모드 안의 붙여넣기를 맡는다.
한쪽만 넣으면 나머지 모드에서 에러 없이 아무 일도 안 일어난다 — `input_test`가 양쪽을
따로 본다. copy 표 쪽은 `KEY_V`가 `v` · `Shift+V`로 이미 차 있어서 세 갈래로 가르는
편집이었고 Meta를 가장 먼저 보는 순서는 `chord()`와 맞췄다.

## 키의 의미를 바꾸는 것은 enum을 넓히는 것과 다른 축이다

`Copy`에 variant를 더하는 것 자체는 `input_test`를 안 깨뜨리는데(`expectCopy` ·
`expectCtx`는 `Action`만 훑는다), `Cmd+V`가 바이트에서 copy 명령으로 뜻이 바뀌자 IP
시절의 `expect(&state, K.KEY_V, 1, "v")`가 깨졌다. 두 축을 따로 센다. 그리고 `Action` ·
`Keys` · `Copy`를 건드리면 `zig build`도 함께 돌린다 — Zig가 참조되지 않는 함수를
분석하지 않아서 `readKeys`가 쓰는 필드가 사라진 것을 `zig build test`가 두 번 놓쳤다
(`input_test`는 `handleKey`만 부른다). `main.zig`의 copy switch에 `else`가 없는 규율이
새 variant의 배선 자리를 컴파일러가 짚게 한다.

## 비워 둔 것과 그 뒤

단어 이동 · 검색은 CN이([[project_copy_navigation]]), 마우스는 PD가
([[project_pointer_devices]]), 프로세스 간 클립보드는 CB가 패널 사이에서 했다. OSC 52 ·
normal 모드의 `Cmd+C` · "붙여넣기가 모드를 닫아야 하는가"(안 닫는다로 정했다)는 그대로
닫혀 있다.

관련: [[project_terminal_rendering]], [[project_input_policy]], [[user_learning_goal]]
