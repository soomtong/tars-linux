# TARS Copy Search Feedback — Design

**Date:** 2026-08-28
**Status:** 설계 확정. **CS-M0 완료(2026-08-28)**. CS-M1 미착수

## 한 줄 요약

**검색이 사람에게 무엇을 찾았는지 보여 주게 만든다.** CN-M1이 검색을 넣었지만
지금 사람이 받는 신호는 커서가 움직이는 것 하나뿐이다 — 매치가 몇 개인지도,
지금 몇 번째인지도, 아예 못 찾았는지도 화면에 없다. 화면의 모든 매치를 칠하고
(CS-M0), 못 찾았을 때 알리고 지난 검색어를 기억한다(CS-M1).

## 배경

Copy Navigation(CN-M0·M1)이 2026-08-27에 끝나면서 진행 중인 서브프로젝트가
없어졌다. `HANDOFF.md`의 이월 숙제에서 사용자가 이것을 골랐다.

CN design의 "비워 두는 자리"가 이 셋을 이렇게 적어 두었다.

> **매치 하이라이트.** 화면의 모든 매치를 표시하는 것. `ViewportSearch`가 그
> 용도로 있지만 `cells()`가 넘기는 색 결정에 손을 대야 한다.

> **검색 기록.** `/`를 다시 열었을 때 지난 needle을 되부르는 것.

> **매치를 못 찾았을 때 화면에 알리기.** 로그에는 `matches=0`이 남지만 사람은
> 프롬프트가 닫히는 것 말고 아무 신호도 못 받는다.

**"`ViewportSearch`가 그 용도로 있다"는 절반만 맞았다.** 아래 결정 2가 그것을
안 쓰는 이유를 적는다 — 검색 객체가 둘이 되면 칠해지는 목록과 `n`이 도는
목록이 갈릴 수 있고, 그 값이 아끼는 비용보다 크다.

## 출발 시점의 저장소 상태 (2026-08-28 실측)

- **`cells()`의 색 결정은 전부 "두 색을 맞바꾼다"이다**(`vt.zig:236~330`).
  inverse도 선택도 커서도 같은 `std.mem.swap` 한 줄이고, 그래서 `main.zig`는
  "반전"이라는 개념을 배우지 않는다. **매치는 이 연산으로 표현할 수 없다** —
  결정 1이 그 이유다.
- **선택 범위는 라이브러리가 행별로 준다**(`row_sels`, `render.zig`가
  `sel.topLeft()`/`bottomRight()`로 계산한다). 절대 행을 우리가 세지 않는
  규율이 여기서 왔고, 매치도 같은 모양(행별 범위)으로 만든다.
- **`find`는 `?ghostty_vt.search.Screen` 하나다**(`vt.zig:118`). 매치 목록을
  이미 전부 들고 있고, `findStep`이 `select`/`selectedMatch`로 그중 하나를
  가리킨다. **우리는 목록 전체를 본 적이 없다.**
- **오버레이는 마지막 줄 하나이고 `drawPrompt`가 그린다**(`main.zig:91`).
  `render` 안, `fb.present()` 바로 앞에서 그린다. `cells()`에 안 섞이므로
  `screen>` 덤프를 흔들지 않는다.
- **`?Prompt`를 만드는 자리는 한 곳이다**(`main.zig:731`). `findNeedle()`이
  null이 아니면 `/`를 앞에 붙여 만든다.
- **`copy/check.sh`는 774줄에 검사 열다섯이고 monitor 포트 45461을 쓴다.**
  다음 포트 45462는 여전히 비어 있다.

## 착수 전 조사로 확정한 사실 (2026-08-28)

vendor된 ghostty 소스를 직접 읽어 확인했다. **CM-M1·M2·CN-M0·M1이 그랬듯
프로브를 돌리지 않았고**, 여기서 얻은 사실은 각 milestone에서 검사로 옮겨
실행으로 다시 증명한다.

| 확인한 것 | 결과 |
|---|---|
| `ScreenSearch.matches(alloc)` (`search/screen.zig:234`) | 매치 전부를 `[]FlattenedHighlight`로 준다. **최신→오래된 순**(화면 아래→위) |
| 그 슬라이스의 소유권 | `@memcpy`로 구조체만 복사한다 — **`chunks`는 ScreenSearch 내부 버퍼를 공유하는 얕은 복사다** |
| `FlattenedHighlight`(`highlight.zig:112`)의 표현 | `chunks: MultiArrayList(Chunk)` + `top_x` + `bot_x`. `Chunk = {node, serial, start, end}` |
| `Flattened`가 그런 모양인 이유 (`:107~110`) | "traversing the entire highlighted area **without needing to read any terminal state or dereference any page nodes (which may have been pruned)**" |
| `PageList.List.Node`의 `serial` (`PageList.zig:52`) | 있다. 주석이 "pointer stability is not guaranteed, but the serial"이라고 명시한다 |
| `pointFromPin`의 비용 (`PageList.zig:5614~5645`) | 뷰포트 top-left에서 `node.next`를 따라 **앞으로 훑는다.** 못 찾으면 목록 끝까지 훑고 null |
| `Pin.before`의 주석 (`PageList.zig:7151`) | "**very expensive** since it requires traversing the linked list of pages. This should not be called in performance critical paths" |
| `Pin.isBetween` (`:7080`) | 같은 성질이다. 싼 pin 순서 비교는 라이브러리에 없다 |
| `ViewportSearch` (`search/viewport.zig`) | 뷰포트 fingerprint로 재검색을 줄인다. `next()`가 sliding window를 소진하는 반복자다 |
| `ViewportSearch`가 찾는 범위 (`:21~23`) | "searches all the pages that viewport covers, so this **can include extra matches outside the viewport**" |

## 결정

### 결정 1. 매치는 맞바꿈이 아니라 바탕색을 정하는 층이다

`cells()`의 기존 셋(inverse·선택·커서)은 전부 `std.mem.swap(fg, bg)`이다.
매치도 맞바꿈으로 만들면 **선택 안에 든 매치가 두 번 뒤집혀 원래 색으로
돌아온다.** 커서가 지금 정확히 그렇게 동작하고 그것은 의도된 것이지만
(CM-M1: "반전된 띠 가운데 뚫린 구멍이 곧 커서라 오히려 잘 보인다"), 매치에는
맞지 않다 — 선택 안의 매치가 안 보이게 되고, 반전된 띠가 선택인지 매치인지
사람도 게이트도 못 가른다.

그래서 매치는 `bg = MATCH_BG`로 **값을 정한다.** 순서는 이렇다.

```
1. style에서 fg/bg를 푼다        (그대로)
2. inverse 맞바꿈                 (그대로)
3. ★ 매치면 bg = MATCH_BG        ← 새 층. 맞바꿈이 아니다
4. 선택 맞바꿈                    (그대로)
5. 커서 맞바꿈                    (그대로)
```

**3이 2와 4 사이인 것에 뜻이 있다.** inverse는 셀이 원래 가진 성질이라 매치가
덮어써야 하고, 선택과 커서는 사람이 지금 하는 동작이라 매치 위에 얹혀야 한다.
그 결과 네 상태가 전부 다른 색이 된다. 아래 표의 글자색은 **셸이 색을 안 준
셀**(스크롤백의 대부분)을 기준으로 적은 것이다.

| 상태 | 바탕 | 글자 |
|---|---|---|
| 기본 | `#102030` | 흰색 |
| 선택 | 흰색 | `#102030` |
| 매치 | `#705000` | 흰색 |
| 선택 안의 매치 | 흰색 | `#705000` |

**`fg`는 건드리지 않는다.** 매치가 원래 무슨 색 글자였는지를 지우지 않기
위해서이고, "매치는 바탕만 정한다"가 한 줄로 말할 수 있는 규칙이기 때문이다.

`MATCH_BG = 0x00705000`(어두운 앰버)을 고른 이유는 배경 `#102030`과도 반전된
흰색과도 멀고, 색이 하나뿐이라 `style>`·`pixel>` 줄에서 게이트가 셀 수 있기
때문이다. 상수는 `vt.zig`에 둔다 — 색을 확정하는 것이 그 파일의 일이다
(TR design 결정 1).

### 결정 2. 매치 목록은 `find` 하나에서만 온다 — `ViewportSearch`를 쓰지 않는다

`ViewportSearch`는 이 용도로 만들어진 것이 맞고 뷰포트가 안 바뀌면 재검색을
건너뛰는 fingerprint까지 들어 있다. 그런데도 안 쓰는 이유는 **검색 객체가
둘이 되기 때문이다.**

needle이 두 곳에 있고 `findSubmit`·`copyExit`·`feed` 세 자리에서 함께 다뤄야
한다. 그것만이라면 줄 세 개다. 진짜 비용은 **칠해지는 매치 목록과 `n`이 도는
매치 목록이 서로 다른 객체가 된다는 것**이다. 둘이 어긋나면 증상이 "`n`을
눌렀는데 안 칠해진 자리로 갔다"이고, 이 저장소가 CM-M1의 앵커에서 배운 "조용히
어긋난다"와 같은 종류다. `ViewportSearch`가 "뷰포트가 걸친 페이지 전체"를
찾아 뷰포트 밖 매치를 섞어 주는 성질도 같은 방향의 위험이다.

`find`는 이미 매치 전부를 들고 있다. `matches(alloc)`을 `findSubmit`에서 한 번
불러 슬라이스를 보관한다. **진실이 하나면 어긋날 자리가 없다.**

### 결정 3. 화면 좌표는 뷰포트가 덮는 node를 먼저 모아서 구한다

매치마다 `pointFromPin`을 부르는 것은 못 쓴다. 그 함수는 뷰포트 top-left에서
`node.next`를 따라 앞으로 훑고, **뷰포트보다 위에 있는 pin은 목록 끝까지 다
훑은 뒤에야 null이 된다.** copy mode에서 스크롤백을 올려다볼 때 매치 대부분이
거기 있다. 라이브러리가 `Pin.before`에 "should not be called in performance
critical paths"라고 직접 적어 뒀고 `isBetween`도 같은 성질이라, 싼 pin 순서
비교는 애초에 없다.

대신 방향을 뒤집는다. 프레임마다 `pages.getTopLeft(.viewport)`에서 시작해
화면 행 수를 덮을 때까지 `node.next`를 따라가며 이것을 모은다.

```
{ node, serial, 노드 안 시작 y, 노드 안 끝 y, 뷰포트 행 오프셋 }
```

**페이지 목록 훑기는 이 한 번뿐이고**, 뷰포트가 걸치는 node는 보통 한두 개다.
매치 쪽은 `chunks`가 이미 `{node, serial, start, end}`를 들고 있으므로, 매치
하나를 판정하는 데 **포인터 비교 한두 번과 y 범위 비교**면 끝난다.

**`serial`을 함께 비교하는 것이 필수다.** `Flattened`가 그런 모양인 이유가
"pruned되었을 수 있는 node를 역참조하지 않고 훑기 위해서"라고 주석에 적혀
있다. 우리는 **살아 있는 뷰포트에서 얻은 node만 역참조**하고 매치 쪽 포인터는
비교에만 쓴다. 가지치기로 주소가 재사용되면 serial이 달라 걸러진다. 빠뜨리면
증상이 크래시가 아니라 **"엉뚱한 자리가 칠해진다"**이다.

### 결정 4. 행별 범위 목록을 만들고 `cells()`는 커서 하나로 따라간다

`RowSpan = { row: u16, x0: u16, x1: u16 }`을 **row 오름차순으로** 담는다.
`cells()`의 바깥 루프가 y를 0에서 rows-1로 올라가므로, 목록에 인덱스 하나를
두고 **앞으로만 밀며** 따라가면 전체가 O(span 수)다. 셀마다 목록을 훑지
않는다.

이 모양이 라이브러리가 `row_sels`로 주는 것과 같다 — 행마다 범위. 선택과 매치가
같은 모양이면 `cells()` 안에서 둘을 나란히 읽을 수 있고, 나중에 셋째가 생겨도
자리가 이미 있다.

soft wrap으로 두 줄에 걸친 매치는 `chunks`가 표현한다. 첫 줄은 `top_x`부터, 끝
줄은 `bot_x`까지, 사이 줄은 `0..cols-1` 전체다.

### 결정 5. 하이라이트 매치 수에 상한을 두지 않는다

한 글자 needle이면 매치가 수만 개일 수 있다. 지금 그 수를 모르고, 모르는 채로
상한을 두면 **게이트가 "다 칠했다"로 읽히는데 실제로는 잘렸을 수** 있다
(`HANDOFF.md`의 "No silent caps").

대신 `terminal: find> hl spans=… us=…` 한 줄을 찍어 실측을 남긴다. CN-M1이
`searchAll()`에 대해 한 것과 같은 방식이고, 그때 60~70밀리초라는 숫자가 나와서
"증분 검색으로 옮길 이유가 없다"를 근거 있게 말할 수 있었다. 정말로 문제가
되면 그때 이 숫자를 근거로 상한을 붙인다.

### 결정 6. `matches()`가 준 슬라이스는 바깥만 해제한다

`matches()`는 `@memcpy`로 구조체만 복사하므로 각 `Flattened`의 `chunks`는
**ScreenSearch 내부 버퍼를 공유한다.** 원소를 `deinit`하면 이중 해제다.
`alloc.free(slice)` 하나만 부른다.

해제 자리는 `find`와 **정확히 같은 셋**이다 — `findSubmit`의 옛것 정리 ·
`copyExit` · `Screen.deinit`. 두 값을 언제나 나란히 다루면 한쪽만 남는 상태를
만들 수 없다.

**CS-M0 구현 중에 이 결정에 사실 하나가 더해졌다(2026-08-28).** 슬라이스의 수명은
"우리가 해제할 때까지"가 아니라 **"다음 `select()`까지"**다. `select`는 먼저
`reloadActive()`를 부르는데 그것이 `active_results`의 원소를 전부 `deinit`한 뒤
활성 영역을 다시 찾고(`search/screen.zig:682-683`), `pruneHistory()`도 history
쪽에 같은 일을 한다(`:402`). **라이브러리 주석에는 이 말이 없다.**

처음 구현은 `matches()`를 `findStep` **앞**에서 불렀고, 그래서 `cells()`가 읽을
때 chunk 내용이 전부 `0xAA`(디버그 allocator가 해제한 메모리에 채우는 값)였다.
**증상이 크래시가 아니라 "하이라이트가 하나도 안 나온다"였다.**

**처방은 스냅숏을 `select()` 뒤에 뜨는 것이고 `refreshMatches()`가 그 자리다.**
깊은 복사(`Flattened.clone`)로 가지 않는 이유는 그러면 하이라이트가 낡은 목록을,
`n`이 새 목록을 보게 되기 때문이다 — **결정 2가 피하려던 어긋남이 그대로 생긴다.**
`select`를 부르는 자리는 `findStep` 하나이고 그것을 부르는 것은 `findSubmit` ·
`findNext` · `findPrev` 셋뿐이라, 셋 다 끝에서 `refreshMatches()`를 부른다.

### 결정 7. 매치 목록은 `searchAll()` 시점의 스냅숏이고 갱신하지 않는다

`find`에 `feed`/`tick`/`reloadActive`를 부르지 않는다. 그래서 검색 뒤 도착한
출력은 안 찾는다. **CN-M1이 이미 그렇게 동작하고 있고**, 하이라이트는 그
사실을 눈에 보이게 만들 뿐 새로 만들지 않는다. 갱신하려면 "언제 다시
찾는가"라는 판정이 생기고, 그 판정이 틀렸을 때 증상이 "낡은 하이라이트"라 조용하다.

copy mode 중에는 `scrollToBottom()`이 억제되어 있어 새 출력이 화면을 밀지
않으므로, 사람이 보는 화면과 스냅숏이 어긋나는 일은 드물다.

### 결정 8. 검색 기록은 `find_last` 하나이고 `copyExit`이 이것만 안 지운다

`find_last: [128]u8` + `find_last_len`. `find_buf`와 같은 고정 크기이고 같은
이유다(CN-M1 결정 8 — 동적 할당은 해제 자리를 세 곳에 나눈다).

`findSubmit`이 빈 검색어를 받으면 `find_last`를 needle로 쓴다. 그것도 비어
있으면 지금처럼 프롬프트만 닫는다. **성공·실패와 무관하게 비지 않은 검색어는
전부 `find_last`에 남긴다** — 못 찾은 검색어를 고쳐 다시 치는 것이 흔한 일이고,
vim도 그렇게 한다.

`/`는 **언제나 빈 프롬프트로 연다.** 지난 검색어를 미리 채우면 전혀 다른 것을
찾을 때 먼저 여러 번 지워야 한다.

`copyExit`이 `find`·`find_matches`·`find_buf`는 지우고 `find_last`만 남긴다.
**모드를 나갔다 다시 들어와도 `/`+Enter가 동작하는 것이 이 기능의 전부다.**

### 결정 9. "못 찾았다"는 오버레이 줄에 쓰고 다음 키에 지운다

상태줄을 만들지 않는다. CN design 결정 7이 그것을 버린 이유가 그대로
유효하다 — 격자를 한 줄 줄이면 셸이 `SIGWINCH`를 받아 화면을 다시 그리므로
**copy mode 진입이 화면을 흔들고**, 처음부터 한 줄을 떼어 두면 평소에 한 줄을
놀린다. 무엇보다 격자 크기는 TF design 1번 결정 이래 **셸과의 계약**이고 copy
mode는 그 계약 바깥에서 끝나야 한다. 이미 있는 오버레이 한 줄을 쓴다.

`findSubmit`이 `matches == 0`이면 플래그를 켠다. `main.zig`가 copy 명령을
처리하기 **직전 한 자리**에서 끈다 — 시계를 들여오지 않는 이유는 poll 루프가
지금 시각을 안 보기 때문이고, 다음 키까지 떠 있으면 사람이 메시지를 못 보고
넘길 일도 없다.

`?Prompt`를 만드는 자리(`main.zig:731`)가 두 갈래가 된다. 프롬프트가 열려
있으면 `/needle`, 아니면 메시지가 켜져 있으면 `/needle: not found`.
**`drawPrompt`는 안 바뀐다.**

### 결정 10. 게이트는 새 체인을 만들지 않고 `copy/check.sh`를 늘린다

CN-M0·CN-M1과 같다. 스크롤백을 만드는 준비가 그대로 필요한데 그것을 새
부팅에서 다시 하는 것은 중복이고, 체인 하나는 부팅 세 번이다. monitor 포트
45462는 계속 비워 둔다.

## Milestone 구성

| Milestone | 무엇 | 왜 여기서 끊는가 |
|---|---|---|
| **CS-M0** | 매치 하이라이트 | `cells()`의 색 결정과 `vt.zig`의 좌표 계산에만 손댄다. 오버레이 문자열은 안 건드린다 |
| **CS-M1** | 검색 기록 + 못 찾음 메시지 | 오버레이 문자열과 `findSubmit`의 입력 처리에만 손댄다. 색 결정은 안 건드린다 |

**둘이 건드리는 코드 경로가 겹치지 않는 것이 이 선의 근거다.** M0이 깨지면
색이 틀리고 M1이 깨지면 글자가 틀린다 — 섞이지 않는다. CN-M1이 "형태 전환과
기능 추가를 다른 커밋으로 가른 것이 값을 했다"고 적은 것과 같은 이유다.

**CS-M1의 plan은 CS-M0이 끝난 뒤에 쓴다**(저장소 규칙).

## 위험

### 위험 1. 이중 해제

결정 6이 처방이다. `matches()`의 얕은 복사를 원소까지 `deinit`하면 ScreenSearch가
같은 버퍼를 다시 해제한다. 증상은 crash일 수도, 조용한 손상일 수도 있다.

**검사로 옮기는 법**: `vt_test`에서 검색을 두 번 돌리고(같은 화면에서 `/`를 두
번) 그 뒤에 `cells()`를 부른다. 첫 검색의 슬라이스가 잘못 해제됐다면 두 번째
검색의 매치가 망가지거나 allocator가 잡는다.

### 위험 2. `serial` 비교를 빠뜨리는 것

결정 3이 처방이다. 이 위험은 **게이트가 밟기 어렵다** — 가지치기가 일어나고
그 자리에 새 node가 같은 주소로 배정되어야 하기 때문이다. CM-M2가 가지치기
자체를 게이트에서 밟는 데 성공했으므로(`copy/check.sh`) 그 준비를 재사용할 수
있지만, 주소 재사용까지 강제할 방법은 없다.

**그래서 이것은 검사가 아니라 코드로 막는다.** 매치 쪽 node 포인터를 **역참조
하는 자리가 코드에 아예 없게** 쓴다 — 비교에만 쓰고, y 범위와 x는 전부 우리가
뷰포트에서 얻은 값과 `chunk`의 정수 필드에서 온다. 그러면 serial 비교를
빠뜨려도 최악이 "안 칠해야 할 자리를 칠한다"이지 메모리 오류가 아니다.

### 위험 3. 하이라이트 계산이 프레임을 느리게 만드는 것

결정 5가 처방(측정)이다. `us=`가 밀리초 단위로 나오면 그때 상한을 논의한다.
**CN-M1의 `searchAll()`이 60~70밀리초였고 사람이 못 느꼈다**는 기준선이 있다 —
하이라이트는 매 프레임이라 그보다 두 자릿수는 작아야 한다.

### 위험 4. 게이트 시간이 는다

CN-M0이 53초, CN-M1이 2분 38초를 더해 지금 21분 38초다. **이 게이트의 잡음이
±3분 수준이라 우리 코드의 증가분을 갈랐다고 주장할 수 없다**(GL-M0의 30분
06초만이 갈렸다). CS-M0은 타이핑을 거의 안 더한다(검색 한 번이면 되고 그것은
이미 검사 15가 친다) — 새 검사는 **같은 부팅에서 `style>` 줄을 더 보는 것**에
가깝다.

## 비워 두는 자리

- **매치 위치 표시(`[3/12]`).** 프롬프트에 지금 몇 번째인지 쓰는 것. 사용자가
  범위에서 뺐다 — copy 커서가 현재 매치의 첫 칸에 서 있으므로 정보가 겹친다.
  다시 집으려면 "선택된 매치가 목록의 몇 번째인가"를 라이브러리에서 꺼내는
  자리가 하나 필요하다.
- **현재 매치를 다른 색으로.** 같은 이유로 뺐다(색 하나를 고름). 다시 집으면
  게이트가 색을 두 가지로 세게 된다.
- **`?`(아래로 검색).** CN design 결정 4가 뺀 그대로다.
- **검색 결과의 실시간 갱신.** 결정 7.
- **`/` 프롬프트에서 지난 검색어 되부르기(`↑`).** 결정 8이 `find_last` 하나만
  둔다. 여러 개를 기억하려면 목록과 그것을 훑는 키가 필요하다.

## 참고

- CN design: `docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md`
- CM design: `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`
- TR design(색을 `vt.zig`에서 확정하는 규율):
  `docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`
- 기억: `docs/decisions/project_copy_navigation.md` ·
  `docs/decisions/project_copy_mode.md` ·
  `docs/decisions/project_terminal_rendering.md`
