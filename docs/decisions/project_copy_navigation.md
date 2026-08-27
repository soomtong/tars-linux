---
name: project_copy_navigation
description: copy mode의 커서에 이동 수단 둘을 얹는 서브프로젝트 — CN-M0이 단어 이동(w/b), CN-M1이 검색(/·n·N). 라이브러리의 "단어"에 공백 덩어리가 포함된다는 것, pointFromPin이 뷰포트 아래쪽 밖을 안 알려준다는 것, Terminal.ScrollViewport에 .pin이 없다는 것이 여기 있다.
metadata:
  node_type: memory
  type: project
---

2026-08-26 시작. Gate Latency가 끝나고 이월 숙제에서 사용자가 골랐다. copy
mode 자체는 [[project_copy_mode]]가 CM-M2로 닫았고, **여기는 그 커서에 이동
수단을 얹는 별개의 서브프로젝트**다.

| | 내용 | 상태 |
|---|---|---|
| CN-M0 | 단어 이동 `w`/`b` | **완료(2026-08-27)** |
| CN-M1 | 검색 `/`·`n`·`N`과 프롬프트 오버레이 | 계획 미작성 |

design은 `docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md`,
CN-M0 plan은 `docs/superpowers/plans/2026-08-26-tars-copy-navigation-cn-m0.md`.

## 라이브러리의 "단어"는 vim의 단어가 아니다

**`Screen.selectWord(pin, boundary)`는 이동이 아니라 범위다**
(`Screen.zig:3217`). pin이 놓인 단어의 `Selection`을 준다. 그리고 그
"단어"에 **공백 덩어리가 포함된다** — 주석이 "exclusively whitespace or
exclusively non-whitespace"라고 정의한다. 그래서 **`"ABC  DEF"`가 세
단어**이고, vim의 `w`를 만들려면 공백 덩어리를 한 번 더 건너뛰는 일을 우리가
해야 한다.

`vt.zig`의 `wordNext`가 `hop < 2`로 그것을 한다. **세 번째 hop은 있을 수
없다** — 경계 문자가 연달아 오면 라이브러리가 애초에 한 덩어리로 묶는다.

**빈 셀에서는 null을 준다**("areas where the screen is not yet written").
그래서 "쓰인 공백"과 "한 번도 안 쓰인 셀"이 다르고, `written()`이
`cell.hasText()`로 그 둘을 가른다. `"alpha"` 뒤의 공백은 건너뛸 대상이지만
줄 끝의 남은 칸은 **멈출** 자리다.

**경계 코드포인트는 우리가 넘긴다.** 라이브러리는 설정에서 받도록 되어 있고
(`Surface.zig:1217`의 `selection_word_chars`) 우리에게는 설정이 없으므로
`vt.zig`의 `WORD_BOUNDARY` 상수에 스무 개를 박았다. 값은 ghostty 자신의 검사가
쓰는 기본값과 같다(`Screen.zig:9800`).

## `pointFromPin(.viewport, …)`은 위아래가 비대칭이다

`PageList.zig:5614`. 뷰포트 **위쪽** 밖이면 null이지만 **아래쪽 밖은
알려주지 않는다** — 노드를 따라가며 y를 더해 `rows`보다 큰 값을 그냥 준다.
**아래쪽은 우리가 가른다**(`copyPlace`의 `if (co.y >= rows) return;`).

**빠뜨리면 증상이 크래시가 아니라 "커서가 안 보인다"이다.** 훨씬 늦게
발견된다. **CN-M1의 검색도 같은 함수를 쓰므로 다시 밟을 자리다.**

## `Terminal.ScrollViewport`에 `.pin`이 없다

`Terminal.zig:2504`. 그런데 `Screen.Scroll`에는 있다(`Screen.zig:1565`·
`:1576`) — `screens.active.scroll(.{ .pin = p })`이 그 pin을 뷰포트의 top
left로 만든다(x는 무시). `assertIntegrity`와 kitty dirty 표시까지 해 주므로
**`pages.scroll`을 직접 부르지 않는다.**

기존 `scrollByRows`로는 위쪽을 못 다루는 이유가 이것이다. HANDOFF가 TR-M2
때부터 적어 둔 "두 타입의 이름이 다르다"의 또 다른 얼굴이다.

## 선택은 커서 셀을 **포함한다** (CN-M0이 실측으로 확정)

plan이 "기대 문자열을 미리 정확히 적을 수 없다"고 표시해 둔 자리인데,
`vt_test`의 검사 16이 답을 냈다. col 6(`beta`의 `b`)에서 `v`로 잡고 `w`를
눌러 col 11(`gamma`의 `g`)로 가면 yank 결과가 **`"beta g"` 여섯 자**다.
`copyApply`가 만드는 `Selection`이 끝 셀을 포함한다.

## `w`는 줄을 안 넘는다 (CN-M0 결정)

vim은 다음 줄의 첫 단어로 가지만 **우리는 멈춘다.** 줄 사이 이동은 `j`/`k`가
이미 하고, 스크롤백을 훑어 한 줄을 잡는 실제 용도에서 `w`는 줄 **안에서**
쓰인다. 다음 줄로 가려면 빈 지대를 지나 다음 줄의 첫 텍스트 셀을 찾고, 화면
끝이면 뷰포트를 밀고, 스크롤백 맨 아래면 멈춰야 해서 분기가 셋 는다.

**CN-M1이 검색을 넣고 나면 줄 사이 이동의 주력이 `/`가 되므로 그때 다시
저울질할 값이 생긴다.**

`e`·`W`·`B`·`E`도 일부러 안 만들었다(design 결정 2). **`W`/`B`가 없으므로
Shift는 단어 이동을 안 가른다** — 대문자도 같은 명령이고, `input_test`의
검사 16이 그것을 못 박는다.

## CN-M0이 다시 밟은 축: 키의 의미가 바뀌는 것

`Copy`에 variant를 더하는 것 자체는 `input_test`를 안 깨뜨렸는데,
**`input_test.zig:497`이 `KEY_W`를 "모르는 키는 삼킨다"의 대상으로 쓰고
있어서** `w`를 배선하는 순간 그 줄이 깨졌다. CM-M2가 `Cmd+V`에서 배운 것의
정확한 재현이다([[project_copy_mode]]).

**CM-M2 때는 예고 주석이 있었지만 여기에는 없었다.** 그래서 이번에는 그 자리에
`e`와 `n`에 대한 예고를 남겼다 — `n`은 CN-M1의 검색이 가져간다.

`main.zig`의 copy switch에 `else`가 없는 규율은 이번에도 값을 했다. variant
둘을 더하자 컴파일러가 `unhandled enumeration value: 'word_next'`로 배선할
자리를 짚어 주었다. **`Copy`는 지금 열둘이고, CN-M1이 검색어 payload를 위해
`union(enum)`으로 바꾼다**(design 결정 6).

## 게이트는 새 체인을 안 만들었다

`copy/check.sh`를 늘렸다(design 결정 1). 스크롤백 1000줄을 만드는 준비가
그대로 필요한데 그것을 새 부팅에서 다시 하는 것은 중복이고, 체인 하나는 부팅
세 번이다. **monitor 포트 45462는 계속 비어 있다.**

**게이트는 커서 좌표와 PTY 누출만 본다**(CN-M0 plan 결정 3). 선택이 함께
넓어지는 것은 `vt_test`가 정확한 문자열로 본다 — 게이트에서 왕복을 보려면 기대
문자열을 미리 적어야 하는데 그 값은 호스트 검사로만 확정된다.

검사 14가 기대는 것 둘. **`copyMove`의 좌우가 줄을 안 넘나들고 x를 0에서
멈추므로** `h`를 40번 누르면 반드시 col 0이다(프롬프트 길이는 fish가 정해서
셀 수 없다). 그리고 **대상 줄을 `echo alpha beta gamma`로 새로 만든다** —
화면에 이미 있는 줄들은 프롬프트가 섞여 col을 못 센다.

## 관련

[[project_copy_mode]] · [[project_input_policy]] ·
[[project_terminal_rendering]] · [[project_gate_chain_composition]] ·
[[project_gate_latency]]
