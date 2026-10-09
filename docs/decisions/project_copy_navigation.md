---
name: project_copy_navigation
description: "copy 커서에 얹은 이동 수단 둘 — 단어 이동 w/b(CN-M0)와 검색 /·n·N과 프롬프트 오버레이(CN-M1), 2026-08-27 종료. 함정 — 라이브러리의 '단어'에 공백 덩어리가 포함된다 · pointFromPin은 뷰포트 아래쪽 밖을 안 알려준다 · ScreenSearch는 우리 선택을 안 건드리고 Select.next는 주석과 달리 감긴다 · n의 뜻은 분기 순서가 정한다"
metadata:
  node_type: memory
  type: project
---

2026-08-26 시작, 이월 숙제에서 사용자가 골랐다. copy mode 자체는 [[project_copy_mode]]가
닫았고 여기는 그 커서에 이동 수단을 얹는 별개의 서브프로젝트다. design은
`docs/specs/2026-08-26-tars-copy-navigation-design.md`. milestone별 경과와 게이트 시간은
2026-10-10에 지웠다(커밋 이력에 있다).

## 결정

- `w`는 줄을 안 넘는다. 줄 사이 이동은 `j` · `k`와 `/`가 하고, 넘게 하려면 분기가 셋
  는다(빈 지대 · 뷰포트 밀기 · 스크롤백 끝). `e` · `W` · `B` · `E`도 일부러 없다(design
  결정 2) — Shift는 단어 이동을 안 가르고 `input_test`가 그것을 못 박는다.
- `?`(아래로 검색)는 없다(design 결정 4). `/`는 위로 찾고 `n`은 같은 방향, `N`은 반대다.
- `searchAll()`은 블로킹이다(design 결정 5). 스크롤백 416줄에 48.8ms(TCG 위)라 사람이
  느끼는 문턱의 절반이고, 증분 검색으로 옮길 이유가 지금은 없다. 첫 검색이 뒤의 검색보다
  세 배 느린 이유는 [[project_copy_search_feedback]]에 있다.
- 새 체인을 안 만들고 `copy/check.sh`를 늘렸다(design 결정 1) — 스크롤백 1000줄을 만드는
  준비가 같고 체인 하나는 부팅 셋이다. 게이트는 커서 좌표와 PTY 누출만 보고, 선택이 함께
  넓어지는 것은 `vt_test`가 정확한 문자열로 본다.

## 라이브러리의 "단어"는 vim의 단어가 아니다

`Screen.selectWord(pin, boundary)`는 이동이 아니라 범위다 — pin이 놓인 단어의
`Selection`을 준다. 그리고 그 "단어"에 공백 덩어리가 포함된다("exclusively whitespace
or exclusively non-whitespace"). 그래서 `"ABC  DEF"`가 세 단어이고, vim의 `w`를
만들려면 공백 덩어리를 한 번 더 건너뛰는 일을 우리가 한다 — `vt.zig`의 `wordNext`가
`hop < 2`로. 세 번째 hop은 있을 수 없다(경계 문자가 연달아 오면 라이브러리가 한
덩어리로 묶는다).

빈 셀에서는 null을 준다. "쓰인 공백"과 "한 번도 안 쓰인 셀"이 다르고 `written()`이
`cell.hasText()`로 그 둘을 가른다 — `"alpha"` 뒤의 공백은 건너뛸 대상이지만 줄 끝의
남은 칸은 멈출 자리다. 경계 코드포인트는 설정에서 받게 되어 있어 우리가
`WORD_BOUNDARY` 상수로 넘긴다(값은 ghostty 자신의 검사가 쓰는 기본값).

선택은 커서 셀을 포함한다 — `v`로 잡고 `w`로 가면 yank 결과가 끝 셀까지다(`vt_test`가
실측으로 확정했다. plan은 "미리 정확히 적을 수 없다"로 두었던 자리다).

## `pointFromPin(.viewport, …)`은 위아래가 비대칭이다

뷰포트 위쪽 밖이면 null이지만 아래쪽 밖은 알려주지 않는다 — `rows`보다 큰 y를 그냥
준다. 아래쪽은 우리가 가른다(`copyPlace`의 `if (co.y >= rows) return;`). 빠뜨리면 증상이
크래시가 아니라 "커서가 안 보인다"라 훨씬 늦게 발견된다. 검색도 같은 함수를 쓴다.

`Terminal.ScrollViewport`에는 `.pin`이 없고 `Screen.Scroll`에는 있다 —
`screens.active.scroll(.{ .pin = p })`이 그 pin을 뷰포트 맨 위로 만든다(x는 무시).
`assertIntegrity`와 kitty dirty 표시까지 해 주므로 `pages.scroll`을 직접 부르지 않는다.

## 라이브러리의 검색은 우리 선택을 안 건드린다

design 위험 1("`ScreenSearch`가 `Screen.selection`을 만지면 우리 선택과 다툰다")은
해소됐다 — `selectNext` · `selectPrev`가 하는 일은 tracked pin을 잡고 `self.selected`를
바꾸는 것뿐이고 `search/` 셋 전체에 `screen.select(`도 `screen.selection =`도 없다.
그래서 `ScreenSearch`를 "매치의 좌표를 알려주는 것"으로만 쓴다. 매치에서 pin을 꺼내는
길은 `selectedMatch()`가 주는 `FlattenedHighlight`의 `startPin()`이고, 그것이
`copyPlace`가 받는 타입과 같아서 검색의 커서 이동은 CN-M0 함수의 재사용이다.

`Select.next`의 주석은 "non-wrapping"인데 코드는 감긴다(`selectNext`가 끝에서 0으로).
코드가 맞다. `n`을 계속 누르면 가장 오래된 매치 다음에 가장 최근 매치로 돌아오고,
감추지 않기로 했다 — 막으려면 "끝에 닿았다"는 상태와 그것을 알릴 자리가 는다.
`Select`의 "next"는 과거 방향이라 우리 `/`가 위로 찾는 것과 방향이 같다.

`ScreenSearch`가 `*Screen`을 들고 있어서 대체 화면(vim)으로 갈아타면 그 포인터가
낡는다. `feed`에서 포인터 하나를 비교해 잡는다 — 앵커 감시로는 못 잡는다(그쪽은 선택
중일 때만 돌고 검색은 선택 없이도 살아 있다).

## `n`의 뜻이 세 층에서 갈리고, 그것을 정하는 것은 분기 순서다

`handleKey`에서 `.find` 분기가 copy 표보다 앞이다. 그래서 같은 `n`이 모드 밖에서는
바이트 `"n"`, copy mode에서는 `.find_next`, 프롬프트 안에서는 글자 `'n'`이다. 순서를
뒤집으면 copy 표가 먼저 삼켜 검색어에 `n`을 못 친다. `input_test`가 세 층을 전부 밟는다.
한글 입력의 한/영 전환도 같은 갈림을 만났다([[project_hangul_input]]).

프롬프트 상태가 두 곳에 있는 것이 옳다 — `input.State.mode`의 `.find`와
`vt.Screen.find_open`. `input.zig`는 키를 글자로 돌리기 위해, `vt.zig`는 그리기 위해
알아야 하고 `input.zig`는 `vt.zig`를 import하지 않는다(IP design 결정 6). 갱신 경로가
`main.zig`의 배선 하나뿐이라 어긋날 자리가 없다.

`Copy`가 `union(enum)`인 이유는 `find_char: u8` 하나다. 전환은 variant 추가와 다른
커밋으로 했다 — 한 Step에 두면 컴파일 에러 목록에 둘이 섞인다. union에는 `==`가 없어서
`input_test`의 `expectCopy`가 `std.meta.eql`을 쓴다. `w`를 배선하는 순간 `KEY_W`를
"모르는 키"의 예로 쓰던 검사가 깨진 것은 CM-M2의 `Cmd+V`와 같은 축이다
([[project_copy_mode]]).

## 게이트가 밟은 함정

- QEMU `sendkey`의 키 이름은 전부 소문자다. `sendkey F`는 조용히 버려지고 체인은
  monitor 응답을 안 읽어 에러도 없다. `echo FINDME`가 `echo `로 도착했는데 "화면에 표적이
  없다"는 검사가 그것을 통과시켰다 — 밀려난 것과 안 쳐진 것을 못 가른다. needle은
  소문자(`findme`), 실제로 쳐졌는지는 `find> type needle=…`로 따로 본다.
- `copy> row=`은 뷰포트 안의 행이라 검색에서는 늘 0이다(`copyPlace`가 매치를 뷰포트 맨
  위로 올린다). `scroll> offset`을 더해 절대 행으로 센다.
- `copyMove`의 좌우가 줄을 안 넘고 x를 0에서 멈추므로 `h`를 40번 누르면 반드시 col 0이다 —
  프롬프트 길이에 기대지 않는 길이다. 대상 줄은 새로 만든다(화면에 이미 있는 줄은
  프롬프트가 섞여 col을 못 센다).
- `echo findme` 한 번이 스크롤백에 두 줄(되비춘 명령줄과 출력줄)을 남겨 매치가 넷이다.
  커서가 선 줄을 yank하면 `len=6 text=findme` — 여섯 자가 곧 "명령줄이 아니라
  출력줄에 섰다"의 증거다.

관련: [[project_copy_mode]] · [[project_input_policy]] · [[project_terminal_rendering]] ·
[[project_gate_chain_composition]]
