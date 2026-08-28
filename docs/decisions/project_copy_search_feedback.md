# Copy Search Feedback — 검색이 사람에게 보이게 만든 것

CN-M1이 검색을 넣었지만 사람이 받는 신호는 커서가 움직이는 것 하나뿐이었다.
CS-M0(2026-08-28)이 **화면에 보이는 모든 매치를 어두운 앰버 바탕으로 칠했다.**
CS-M1(검색 기록 · "못 찾았다" 메시지)은 아직 안 했다.

design: `docs/superpowers/specs/2026-08-28-tars-copy-search-feedback-design.md`
plan(M0): `docs/superpowers/plans/2026-08-28-tars-copy-search-feedback-cs-m0.md`

## 실행이 증명한 것

### 1. `matches()`가 준 목록은 다음 `select()`에서 죽는다

**이것이 이 milestone에서 가장 값진 사실이다.** `ScreenSearch.matches(alloc)`은
`@memcpy`로 구조체만 옮기는 **얕은 복사**를 준다(`search/screen.zig:234`). 거기까지는
소스를 읽어 알았는데, 수명이 "우리가 해제할 때까지"가 아니라는 것은 몰랐다.

`select()`는 먼저 `reloadActive()`를 부르고, 그 함수가 `active_results`의 원소를
**전부 `deinit`한 뒤** 활성 영역을 다시 찾는다(`:682-683`). `pruneHistory()`도
history 쪽에 같은 일을 한다(`:402`). **라이브러리 주석에는 이 말이 없다.**

처음 구현은 `matches()`를 `findStep`(→ `select`) **앞**에서 불렀다. 그래서
`cells()`가 읽을 때 chunk 내용이 전부 `0xAA`였다 — 디버그 allocator가 해제한
메모리에 채우는 값이다. **증상이 크래시가 아니라 "하이라이트가 하나도 안
나온다"였고**, 값을 찍어 보기 전까지는 뷰포트 판정을 의심하고 있었다.

처방은 스냅숏을 `select()` **뒤에** 뜨는 것이고 `refreshMatches()`가 그 자리다.
`select`를 부르는 자리는 `findStep` 하나이고 그것을 부르는 것은 `findSubmit` ·
`findNext` · `findPrev` 셋뿐이다.

**깊은 복사(`Flattened.clone`)로 가지 않았다.** 그러면 하이라이트가 낡은 목록을,
`n`이 새 목록을 보게 되어 [[project_copy_navigation]]이 겪은 "조용히 어긋난다"가
그대로 생긴다.

### 2. 매치는 맞바꿈으로 표현할 수 없다

`cells()`의 색 결정은 inverse도 선택도 커서도 전부 `std.mem.swap(fg, bg)` 하나다
([[project_terminal_rendering]]). 매치도 그렇게 만들면 **선택 안의 매치가 두 번
뒤집혀 원래 색으로 돌아온다** — 커서는 그렇게 동작하는 것이 옳지만(반전된 띠
가운데 뚫린 구멍이 곧 커서다) 매치는 안 보이게 된다.

그래서 매치만 **값을 정하는 층**이다. 순서가 `inverse → 매치 → 선택 → 커서`이고,
그 순서 때문에 넷이 전부 다른 색이 된다.

| 상태 | 바탕 | 글자 |
|---|---|---|
| 기본 | `#102030` | 흰색 |
| 선택 | 흰색 | `#102030` |
| 매치 | `#705000` | 흰색 |
| 선택 안의 매치 | 흰색 | `#705000` |

**`fg`는 안 건드린다** — 매치가 원래 무슨 색 글자였는지를 지우지 않기 위해서다.

### 3. 매치 여섯 칸 중 하나는 언제나 뒤집혀 있다

`/` 뒤 copy 커서는 매치의 첫 칸에 선다(`copyPlace`가 `top_x`로 옮긴다). 커서는
매치 **위**에 얹히는 층이라 그 한 칸이 또 맞바뀐다. 그래서 `bg == MATCH_BG`인
셀을 세면 여섯이 아니라 **다섯**이다.

**plan은 이것을 여섯으로 적었고 틀렸다.** 그리고 `vt_test`의 검사 29(`plain=5
cursor=1`)와 부팅 게이트의 검사 16(`5 cell(s) reached the framebuffer`)이
**정확히 같은 값을 봤다** — 단위 검사와 실기가 만나는 자리다.

### 4. 좌표를 푸는 방향을 뒤집어야 한다

`pointFromPin`은 뷰포트 top-left에서 `node.next`를 따라 **앞으로** 훑고, 뷰포트
**위**에 있는 pin은 목록 끝까지 훑은 뒤에야 null이 된다(`PageList.zig:5614~5645`).
copy mode에서 매치 대부분이 거기 있다. 라이브러리도 `Pin.before`에 "very
expensive... **should not be called in performance critical paths**"라고 적어
두었고 `isBetween`도 같은 성질이라, **싼 pin 순서 비교는 라이브러리에 없다.**

그래서 뷰포트가 덮는 page node를 **한 번만** 훑고 매치 쪽은 `chunks`가 이미 든
`{node, serial, start, end}`와 **비교만** 한다. 뷰포트가 걸치는 node는 보통
한두 개다.

**매치 쪽 node 포인터를 역참조하는 자리가 코드에 없다.** 비교에만 쓴다 —
`Flattened`가 그런 모양인 이유가 "pruned되었을 수 있는 node를 역참조하지 않고
훑기 위해서"이고(`highlight.zig:107`) `serial`이 그 짝이다. 그래서 serial 비교를
빠뜨려도 최악이 "안 칠해야 할 자리를 칠한다"이지 메모리 오류가 아니다.

### 5. 하이라이트 계산은 100마이크로초 언저리다

루트 게이트 세 번 × 체인 세 회차, 곧 **아홉 번의 부팅이 전부
`spans=1 cells=6`을 찍었고 `us`는 58~171** 사이였다. 같은 부팅에서 `searchAll()`이
`us=65228`(65밀리초)이었으므로 **수백 배 싸다.** 첫 프레임이 209밀리초인
시스템에서 0.1밀리초는 잴 수 없는 수준이다.

**그래서 하이라이트 매치 수에 상한을 두지 않는다.** 상한을 두면 게이트가 "다
칠했다"로 읽히는데 실제로는 잘렸을 수 있다.

### 6. `ViewportSearch`는 쓰지 않는다

라이브러리가 이 용도로 만든 것이 맞고 뷰포트 fingerprint까지 들어 있다. 그런데
**검색 객체가 둘이 되면 칠해지는 목록과 `n`이 도는 목록이 서로 다른 객체가
된다.** 어긋나면 증상이 "`n`을 눌렀는데 안 칠해진 자리로 갔다"이다. `find`가
이미 매치 전부를 갖고 있으므로 진실을 하나로 둔다.

## 코드를 읽을 때 알아야 할 것

- **Zig는 struct의 필드 사이에 선언을 끼우는 것을 막는다.** `RowSpan`·`HlStats`가
  `Screen` 안이 아니라 파일 스코프에 있는 이유다. `Screen`의 기존 선언들
  (`Cursor`·`SelectKind`)이 전부 필드 뒤에 있는 것도 같은 규칙이다.
- **`vt.Screen`이 `io`를 필드로 든다.** `cells()`에서 시간을 재기 위해서다.
  `init`이 받아 `Terminal`에 넘기고 버리던 값이다.
- **`find> hl` 줄은 검색이 살아 있는 매 프레임 찍힌다.** "바뀔 때만"은 상태를
  하나 더 만들고 그 판정이 틀리면 증상이 "로그가 안 나온다"라 조사하기 나쁘다.
- **`vt_test`의 새 검사는 자기 화면 `hs`를 만든다**(20x5, 20줄, 8·18번 줄이
  표적). 남의 화면에 붙이면 앞 검사가 흔들린다.

## 관련

[[project_copy_navigation]] · [[project_copy_mode]] ·
[[project_terminal_rendering]] · [[project_gate_chain_composition]]
