---
name: project_search_position
description: "검색에서 '지금 몇 번째 매치인가'를 꺼내는 자리와 그 위에 세운 색(SP-M0)과 오버레이의 [3/12] 번호(SP-M1), 2026-08-29·30 종료. 함정 — 색이 둘이 되면 span 루프의 break가 뜻을 갖고 한 색만 세는 음성 검사는 아무것도 안 본다 · cur은 커서를 몰라 프레임버퍼와 1 차이다 · /는 커서 자리의 매치를 건너뛴다(vim과 같다) · 조사 로그는 통째로 호스트로 빼낸다"
metadata:
  type: project
---

CS-M0이 화면의 모든 매치를 한 색으로 칠했지만 그중 어느 것이 현재 매치인지는 copy
커서 한 칸으로만 알 수 있었다. SP-M0이 현재 매치를 밝은 앰버로, SP-M1이 오버레이에
`/needle [3/12]`를 띄운다. design은 `docs/specs/2026-08-29-tars-search-position-design.md`.
milestone별 경과와 게이트 시간은 2026-10-10에 지웠다(커밋 이력에 있다).

## 1. 라이브러리의 `selected.idx`와 `matches()` 슬라이스는 같은 좌표계다

이 서브프로젝트 전체가 이 사실 하나 위에 서 있다. `ScreenSearch.selected.?.idx`는
"Index from the end of the match list (0 = most recent match)"이고, `selectedMatch()`가
활성 영역은 `active_results[active_len - 1 - idx]`, history는
`history_results[idx - active_len]`로 푸는데 `matches()`도 활성 영역을 `reverse`한 뒤
history를 이어 붙이므로 같다. 그래서 `find_matches[idx]`가 곧 현재 매치다. 둘이 어긋날
수 없는 것은 CS-M0이 `refreshMatches()`를 `select()` 직후에 부르는 규율 덕이다.

`selectedIndex()` 같은 공개 함수는 없어서 내부 필드를 `vt.zig`의 `findCurrentIndex()`
하나로 감쌌다. 이름이 바뀌면 컴파일이 막혀 시끄럽고, 뜻이 조용히 바뀌는 쪽은
`vt_test`(`/` 직후 0, `n` 뒤 1)가 막는다.

## 2. 색이 둘이 되면 `break`의 뜻이 바뀐다

`cells()`의 매치 층은 행 안의 span을 돌다 처음 걸린 것에서 `break` 했다. 색이 하나일
때는 순수한 최적화였는데 둘이 되면 "목록 순서가 색을 정한다"가 된다. 매치끼리 겹칠 일이
없다고 믿지만 증명한 적이 없어서 행 안을 끝까지 보고 현재 매치가 이기게 했다.

같은 종류의 문제가 검사 쪽에도 있었다. `vt_test`와 게이트의 음성 판정이 둘 다
`MATCH_BG`만 세는데 SP-M0 뒤로 그 화면에는 `MATCH_BG`가 애초에 안 쓰인다 — 안 고쳐도
통과하지만 아무것도 안 보는 검사다. 둘 다 두 색을 함께 세도록 넓혔다. 색은
`MATCH_BG = 0x705000`(어두운 앰버) · `CURRENT_BG = 0xC08000`(같은 계열의 밝은 색) —
같은 종류인데 이것이 지금 것이라는 뜻이다.

## 3. 한 줄에 매치 둘을 심으면 판정이 스크롤에 안 딸린다

두 색을 함께 보려면 매치가 둘 이상 한 화면에 있어야 한다. 그 자리를 찾는 대신 검사가
자기 조건을 스스로 만든다 — `echo zq zq`처럼 needle을 같은 줄에 두 번 심으면 뷰포트가
어디에 있든 둘이 함께 보인다. needle이 두 글자인 이유는 `style>` 덤프에 프레임당
상한(`STYLE_DUMP_LIMIT`)이 있어 긴 needle이면 뒤쪽 색이 안 찍히고 "색이 안 닿았다"로
잘못 읽히기 때문이다. 게이트의 needle을 고를 때 기존 판정을 깨뜨리지 않는지 본다 —
`findme`를 더 심으면 `matches=4`를 쓰는 검사가 깨진다.

## 4. `cur`은 커서를 모르고, 그 차이가 정확히 1이다

`hlStats().cur`은 `findSpans`가 센 값이라 커서를 모른다 — 커서는 `cells()`가 그 뒤에
얹는 층이다. 그래서 게이트에서 두 숫자가 다르게 나오는 것이 정상이고 차이가 언제나
1이다(매치 하나가 현재일 때 `cells` 6 · `cur` 6 · 프레임버퍼의 현재 색 5). 음성 검사를
"그 색이 0개"로 쓰면 이 1이 빠진 자리를 세고 있을 수 있다 — 한글 입력의 `dumpInk`
상한에서 같은 종류의 함정이 다시 나왔다([[project_hangul_input]]).

## 5. `/`는 커서 자리의 매치를 건너뛴다 — vim과 같고 고치지 않는다

게이트 검사 하나의 주석이 "`n`이 매치 하나를 건너뛴다"고 의심했는데 건너뛴 것은 `/`였고
의도된 동작이다. 세 가지가 겹친다 — 첫 검색이 `copyPlace`로 매치를 뷰포트 맨 윗줄에
올렸고 `copyExit`은 뷰포트를 되돌리지 않는다 · 재진입 때 셸 커서가 화면 밖이라
`copyEnter`가 커서를 `{0, 0}`에 둔다(로그 `copy> enter row=0 col=0`, 첫 진입의
`row=46`과 대비) · `findStep`의 `above_only`가 커서보다 위를 요구해 커서와 같은 줄의
매치는 자격이 없다. 고치려면 CN design 결정 4를 다시 열어야 한다.

처방은 검사에 `col` 판정을 더한 것이다 — 명령줄이면 프롬프트 뒤(`copy/check.sh`의
`col 20`, UT가 `/etc/passwd`를 넣어 16에서 20이 됐다), 출력줄이면 0. row 폭만 보던
옛 판정은 "위로 갔다"까지만 말해서 매치를 건너뛰었는지를 못 가른다.

## 6. 조사 로그는 통째로 호스트로 빼내는 것이 낫다

체인은 시리얼 로그를 `mktemp`에 담고 통과하면 버린다. 무엇을 봐야 할지 모르는 조사에서
한 `docker run` 안의 좁힌 `grep`은 나쁘다 — `head`에 잘려 실패했고, 좁힌 `grep`도 "그
줄을 볼 생각을 했어야" 맞는다. `-v "$PWD":/workspace`가 붙어 있으므로 `out/`(gitignore)
아래로 `gzip`해서 복사하고 여러 각도로 본다. 답을 준 `copy> enter row=0 col=0`은 애초에
찾을 목록에 없던 줄이다. 루트 게이트의 `clean()`이 `out`을 통째로 지우므로 조사를 다
끝내고 게이트를 돌린다. 명령은 `docs/guides/lessons.md`의 "범용 명령"에 있다.

## 7. 상태를 하나로 두는 것이 켜고 끄는 자리를 한 벌로 만든다 (SP-M1)

CS-M1의 `find_missed`("마지막 검색이 실패했다")를 `find_status`("마지막 검색 명령의
결과를 보여 주는 중")로 넓혔다. 플래그를 새로 만들지 않은 이유는 수명이 같기 때문이다 —
`[3/12]`도 "못 찾음"도 다음 키에 사라진다. 둘로 나누면 켜는 자리 셋과 끄는 자리 둘이
각각 두 벌이 되고 하나를 빠뜨리면 증상이 "글자가 화면 아랫줄에 영영 붙어 있다"이다.
`findMissed()`는 이름도 계약도 그대로 두고 구현만 곱셈으로 바꿨다
(`findStatusNeedle()`이 있고 `findMatchCount() == 0`일 때) — CS-M1의 검사 셋이 한 글자도
안 바뀐 채 통과한 것이 그 증거다.

`findNext` · `findPrev`는 `find != null`일 때만 켠다. `moved`로 판단하면 안 된다 — 매치가
하나뿐이라 안 움직인 경우에도 false인데 그때도 번호를 보여 주는 것이 맞다.

## 8. 번호는 두 파일이 나눠 본다 — `promptText`가 private이기 때문이다

`promptText`는 `main.zig`의 private 함수라 `vt_test`가 못 부른다. `vt_test`는 번호의
재료(`findCurrentIndex() + 1`과 `findMatchCount()`)를, 게이트는 글자(`find> overlay
text=/zq [1/4]`)를 본다. 둘 중 하나만 있으면 실패했을 때 원인을 못 좁힌다. 게이트 판정을
셋으로 둔 이유도 같다 — `[1/4]`만 보면 고정된 숫자를 찍는 코드도 통과하므로 `n` 뒤의
`[2/4]`가 "번호가 커서를 따라간다"를, `k` 뒤의 "오버레이 0개"가 수명을 본다. 상태 줄이
같은 모양을 따랐다([[project_input_status]]).

오버레이가 검색 성공에도 뜨면서 `dumpStyles`가 맨 아랫줄을 건너뛰기 시작한다. 색을 세는
검사가 깨질 수 있었는데 착수 전에 로그로 매치의 행 번호를 읽어 안 겹치는 것을 확인했다
(매치 0 · 44 · 45행, 오버레이 46행). 겹쳤다면 증상이 "색이 안 닿았다"라 원인을
오버레이에서 찾기 어려웠을 것이다 — 짐작으로 검사를 쓰지 않는다.

관련: [[project_copy_search_feedback]] · [[project_copy_navigation]] ·
[[project_copy_mode]] · [[project_terminal_rendering]] ·
[[project_gate_chain_composition]]
