---
name: project_copy_mode
description: 스크롤백 위에서 vim modal 방식 선택 모드(커서 이동 → v/V로 영역 선택 → 복사)와 Cmd+V 붙여넣기. iTerm2/WezTerm의 copy mode에 해당. CM-M0(2026-08-24)에서 모드·커서·게이트가 들어갔고 남은 선행 조건은 클립보드다.
metadata:
  node_type: memory
  type: project
---

2026-08-15 사용자 요청("지금은 아니지만 … 실행 가능한 단계에 도달하게 되면
구현해보도록 하자"). 입력 정책(IP) 서브프로젝트 설계 중 macOS 의미론 매핑
표를 검토하다가 나왔다.

**요청 내용:** 스크롤백이 생기면, 특정 키로 **선택 모드**에 들어가서 화면
일부를 선택할 수 있어야 한다. 방식은 **vim의 modal 에디팅** — 커서 키로
이동하고 `v`(문자 단위)/`V`(줄 단위)로 영역을 잡고 복사한다. 붙여넣기는
**Cmd+V**. iTerm2와 WezTerm에 있는 기능(copy mode)을 가리킨다.

**선행 조건이 셋이었다. 2026-08-23에 둘이 끝났고 남은 것은 클립보드
하나다.**

1. ~~**스크롤백**~~ — **TR-M2(2026-08-23)에서 끝났다.** `vt.zig`에
   `scrollToTop`·`scrollToBottom`·`scrollByRows`·`scrollbar` 넷이 생겼고,
   한도가 1000줄이며(바이트 한도를 `null`로 함께 풀어야 걸린다),
   `RenderState`가 뷰포트를 따라가므로 `cells()`는 손댈 것이 없었다. 자세히는
   [[project_terminal_rendering]].
2. ~~**선택 상태와 렌더링**~~ — **TR-M0(2026-08-23)에서 끝났다.** `cells()`가
   셀마다 `fg`·`bg`를 확정해 넘기고 렌더러가 셀 배경을 칠한다. 라이브러리에
   `RenderState.Row.selection: ?[2]CellCountInt` 자리가 이미 있다
   (`render.zig:234`) — 아직 안 건드렸다.
3. **클립보드** — 프로세스 간 클립보드가 없다. 단일 프로세스가 디스플레이를
   독점하는 구조(TF design 1번 결정)라 당장은 `terminal` 안의 버퍼 하나로
   충분하지만, 개념 자체가 아직 없다. **이것이 마지막 선행 조건이다.**

**IP 설계가 이 기능을 위해 지금 지키는 것 둘.**

- **파이프라인의 dispatch 단계가 그대로 진입점이다.** IP는 키 처리를
  `modifier 갱신 → 조합 dispatch → 기본 번역` 순으로 짜고, dispatch에서
  매치된 키는 **PTY로 보내지 않는다.** 선택 모드 진입키는 이 자리에 표
  한 줄로 붙는다. 모드에 들어간 뒤 `v`/`V`/`hjkl`을 전부 가로채는 것은
  "현재 모드"라는 상태가 하나 더 필요하지만, 갈림길 자체는 이미 있다.

  **TR-M2가 그 통로를 실제로 넓혀 놓았다.** `handleKey`의 반환이
  `input.Action = union(enum) { bytes, scroll }`이고, copy mode는 여기에 자기
  variant를 더하면 된다 — "PTY로 안 보내고 우리가 처리한다"를 표현할 타입이
  이미 있다는 뜻이다. 모드 상태는 아직 안 들어갔다.
- **`Cmd+V`와 `Cmd+C`를 다른 용도로 쓰지 않는다.** IP의 macOS 의미론 표는
  Cmd를 방향키·Backspace와만 조합한다(Cmd+←/→/Backspace). 문자 키와의 Cmd
  조합은 전부 비워둔 채로 남긴다.

**순서에 대한 판단:** 이 기능은 "터미널 완성도"(스크롤백·색상) 서브프로젝트
뒤에 온다. 그 서브프로젝트가 선행 조건 1·2를 만들고 나면, copy mode는
클립보드 버퍼 하나만 더해서 시작할 수 있다.

## 2026-08-24 — CM-M0이 끝났다. 통로가 실제로 뚫렸다

위에서 "갈림길 자체는 이미 있다"고 적어 둔 자리에 **모드가 들어갔다.**

- `input.Action`에 `copy: Copy` variant가 생겼고, `State.mode`가 `.normal`과
  `.copy`를 가른다. **copy 분기가 `chord()`보다 앞에 있다** — 그래서 모드
  안에서는 Cmd 조합조차 `chord()`에 닿지 못하고 전부 삼켜진다. CM-M1의
  `Cmd+C`와 CM-M2의 `Cmd+V`는 `chord()`가 아니라 **copy 표에** 들어와야 한다.
- `vt.Screen`에 `copy_cursor`(뷰포트 좌표)와 `copyEnter`/`copyExit`/
  `copyMove`/`copyActive`/`copyCursor`가 생겼다. 화면 끝에서 더 움직이면
  뷰포트가 대신 움직인다.
- 게이트 체인 `copy/check.sh`(monitor 포트 45461)가 신설됐고 루트 게이트가
  여덟 체인 3/3이다. **51분 20초**(직전 45분 41초).
- **진입키는 `Cmd+Shift+C`로 확정됐다.** QEMU `sendkey meta_l-shift-c`가 세 키
  조합을 게스트까지 옮긴다는 것이 실측으로 확인됐다.

**남은 선행 조건은 여전히 클립보드 하나다.** CM-M1이 그것을 만든다.

**`scrollToBottom` 억제가 창을 열었다.** `main.zig`가 copy mode 중에는
`scrollToBottom()`을 부르지 않는다. 그전까지 그 호출이 **부수 효과로** 막고
있던 것이 있다 — 뷰포트가 history에 머무는 동안 가지치기가 일어나는 상황이다.
가지치기는 그 페이지를 가리키던 pin을 무효로 만든다. copy mode 중에 1000줄이
쏟아져야 닿는 자리라 게이트로 만들지 않았고, **CM-M1이 매 프레임
`selection`이 null이 됐는지 보고 그러면 모드를 나가는 방어를 넣는다.**

**`Action`을 넓힐 때는 `zig build`도 함께 돌린다.** Zig가 참조되지 않는 함수를
분석하지 않아서, `readKeys`가 쓰는 `State.scrolls` 필드가 사라진 것을
`zig build test`가 두 번 놓쳤다 — `input_test`는 `handleKey`만 부른다.
`main.zig`가 `readKeys`를 부르는 `zig build`에서 비로소 드러났다.

관련: [[project_boot_shell_selection]], [[project_config_persistence]],
[[user_learning_goal]]
