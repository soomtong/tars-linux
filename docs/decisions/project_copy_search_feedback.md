---
name: project_copy_search_feedback
description: "검색이 사람에게 보이게 만든 층 — 화면의 모든 매치를 앰버 바탕으로(CS-M0), 검색 기록과 '못 찾음' 메시지(CS-M1), 2026-08-28 종료. 함정 — matches()가 준 목록은 다음 select()에서 죽는다 · 매치는 fg/bg 맞바꿈으로 표현할 수 없다 · 좌표는 뷰포트 쪽에서 풀어야 싸다 · 오버레이는 screen>에 안 나와 find> overlay 줄이 창구다 · 게이트의 첫 검색 값은 TCG 번역 비용을 포함한다"
metadata:
  node_type: memory
  type: project
---

CN-M1이 검색을 넣었지만 사람이 받는 신호는 커서가 움직이는 것 하나뿐이었다. CS-M0이
화면에 보이는 모든 매치를 어두운 앰버 바탕으로 칠했고, CS-M1이 지난 검색어를 기억하고
못 찾았을 때 화면에 알린다. design은
`docs/specs/2026-08-28-tars-copy-search-feedback-design.md`. milestone별 경과와 게이트
시간은 2026-10-10에 지웠다(커밋 이력에 있다). 현재 매치를 따로 밝히는 색과 `[3/12]`는
그 뒤 SP가 얹었다([[project_search_position]]).

## `matches()`가 준 목록은 다음 `select()`에서 죽는다

`ScreenSearch.matches(alloc)`은 `@memcpy`로 구조체만 옮기는 얕은 복사다. 수명이 "우리가
해제할 때까지"가 아니다 — `select()`가 먼저 `reloadActive()`를 부르고 그 함수가
`active_results`의 원소를 전부 `deinit`한다(`pruneHistory()`도 history 쪽에 같은 일을
한다). 라이브러리 주석에는 이 말이 없다. 처음 구현은 `matches()`를 `select` 앞에서 불렀고
`cells()`가 읽을 때 chunk 내용이 전부 `0xAA`(디버그 allocator가 해제한 메모리에 채우는
값)였다. 증상은 크래시가 아니라 "하이라이트가 하나도 안 나온다"였다.

처방은 스냅숏을 `select()` 뒤에 뜨는 것이고 `refreshMatches()`가 그 자리다 —
`findSubmit` · `findNext` · `findPrev` 셋 모두의 끝. 깊은 복사(`Flattened.clone`)로
가지 않았다. 그러면 하이라이트가 낡은 목록을, `n`이 새 목록을 보게 되어 조용히
어긋난다. 같은 이유로 `ViewportSearch`도 안 쓴다 — 검색 객체가 둘이면 칠해지는 목록과
`n`이 도는 목록이 다른 객체가 된다. `find`가 이미 매치 전부를 갖고 있으므로 진실을
하나로 둔다.

## 매치는 맞바꿈으로 표현할 수 없다

`cells()`의 색 결정은 inverse도 선택도 커서도 전부 `std.mem.swap(fg, bg)` 하나다
([[project_terminal_rendering]]). 매치도 그렇게 하면 선택 안의 매치가 두 번 뒤집혀
원래 색으로 돌아온다 — 커서는 그래야 맞지만(반전된 띠 가운데 뚫린 구멍이 곧 커서)
매치는 안 보이게 된다. 그래서 매치만 값을 정하는 층이고 순서가 `inverse → 매치 → 선택 →
커서`다. `fg`는 안 건드린다 — 매치가 원래 무슨 색 글자였는지를 지우지 않기 위해서다.

| 상태 | 바탕 | 글자 |
|---|---|---|
| 기본 | `#102030` | 흰색 |
| 선택 | 흰색 | `#102030` |
| 매치(`MATCH_BG`) | `#705000` | 흰색 |
| 선택 안의 매치 | 흰색 | `#705000` |

커서는 매치 위에 얹히는 층이라 `/` 뒤 커서가 선 매치의 첫 칸은 또 맞바뀐다. 그래서
`bg == MATCH_BG`인 셀을 세면 여섯 자 needle에서 여섯이 아니라 다섯이다 — plan은 여섯으로
적었고 틀렸다. `vt_test`와 부팅 게이트가 정확히 같은 값(5)을 봤다.

## 좌표를 푸는 방향을 뒤집어야 한다

`pointFromPin`은 뷰포트 top-left에서 앞으로 훑고, 뷰포트 위에 있는 pin은 목록 끝까지
훑은 뒤에야 null이 된다. copy mode에서 매치 대부분이 거기 있다. 라이브러리의
`Pin.before` · `isBetween`도 "very expensive"라 싼 pin 순서 비교는 없다. 그래서 뷰포트가
덮는 page node를 한 번만 훑고 매치 쪽은 `chunks`가 이미 든 `{node, serial, start, end}`와
비교만 한다. 매치 쪽 node 포인터를 역참조하는 자리가 코드에 없다 — `Flattened`가 그런
모양인 이유가 "pruned되었을 수 있는 node를 역참조하지 않기 위해서"이고 `serial`이 그
짝이다. serial 비교를 빠뜨려도 최악이 "안 칠해야 할 자리를 칠한다"이지 메모리 오류가
아니다. 하이라이트 계산은 100µs 언저리라(`searchAll()`의 수백분의 일) 매치 수에 상한을
두지 않는다 — 상한을 두면 게이트가 "다 칠했다"로 읽는데 실제로는 잘렸을 수 있다.

## 검색 기록과 "못 찾음" — 플래그는 켜는 것이 아니라 매번 정한다

- 빈 Enter는 이미 `findSubmit`까지 도착하고 있었다. `input.zig`의 `.find` 분기가
  `KEY_ENTER`를 버퍼 내용과 무관하게 넘기고 `vt.zig`의 `if (len == 0) return none;` 한
  줄이 버리고 있었다. 그 한 줄이 검색 기록의 전부다. 메시지에 쓸 글자가 `find_last`에서
  올 수밖에 없는 이유는 메시지가 뜰 때 프롬프트가 이미 닫혀 `findNeedle()`이 null이기
  때문이다 — 결정 8(기록)과 9(메시지)는 따로 만들 수 없었다.
- design의 글자는 "`matches == 0`이면 켠다"였는데 그대로 하면 끄는 자리가 `main.zig`
  하나뿐이 되어 poll 루프를 안 거치는 호출자(`vt_test`)에서 성공한 검색이 앞의 실패를
  안 지운다. `findSubmit`의 끝에서 매번 값을 정한다. SP-M1이 이 플래그를 `find_status`로
  넓혔다([[project_search_position]]).
- 끄는 자리는 `main.zig`의 copy 명령 루프에서 `switch` 바로 앞이다. 그래서 모든 copy
  명령이 메시지를 지우고(다음 키에 사라진다) 그중 `.find_submit`만이 그 뒤에 다시 켠다.
  루프 밖에 두면 안 되는 이유는 자동 반복이다 — 한 read에 여러 키가 실려 오면 첫 키만
  지운다.
- `copyExit`은 검색 상태를 전부 버리는데 `find_last`만 예외다. `vt_test`가 그 예외와
  반대쪽(`find_status`는 안 남는다)을 나란히 본다.

## 오버레이는 `screen>`에 안 나온다 — `find> overlay` 줄이 창구다

`docs/guides/lessons.md`의 로그 문구 절("`find> overlay`가 오버레이 내용의 유일한 관측
수단이다")과 `docs/guides/dead-ends.md`의 "`find> submit matches=0`으로 …" · "`matches`로
빈 Enter가 …(CS-M1)" 항목. 여기에만 있는 것 — 그 줄은 `render()`에 넘어간 바로 그 값을
받아 찍는다(다시 만들면 그리는 것과 찍는 것이 갈릴 수 있다). 게이트 검사 순서 — "못
찾음"을 먼저 검사하면 그 needle이 `find_last`를 덮어 이어지는 빈 Enter도 `matches=0`을
내므로 기록 검사를 먼저 둔다.

## 게이트의 첫 검색 값은 번역 비용을 포함한다

같은 needle로 같은 스크롤백을 훑는데 그 부팅의 첫 검색이 39.7~69.6ms(±55%), 빈 Enter로
되돌린 세 번째가 18.2~20.7ms(±6%)였다. 코드가 아낀 것일 수 없다(CS-M1이 더한 것은
`@memcpy` 둘). 이 게이트는 arm64 위에서 x86_64를 TCG로 돌리므로 첫 값에 그 루프를
번역하는 비용이 섞여 있다는 설명이 가장 잘 맞는다 — 증명이 아니라 설명이다. 검색 비용을
인용할 때 이 단서를 함께 읽는다.

## 코드를 읽을 때 알아야 할 것

전부 가이드에 있다 — `docs/guides/dead-ends.md`의 "struct의 필드 사이에 `const`"(`RowSpan` ·
`HlStats`가 파일 스코프인 이유) · "`std.time.Timer`…"(`vt.Screen`이 `io`를 드는 이유) ·
"`vt_test`의 검사를 남의 화면에 붙이기" 항목, `docs/guides/lessons.md`의 "`find> hl`과
`find> overlay`는 매 프레임 찍힌다" 문단.

관련: [[project_copy_navigation]] · [[project_copy_mode]] · [[project_search_position]] ·
[[project_terminal_rendering]] · [[project_gate_chain_composition]]
