# SW-M1 — column당 3 한도

Date: 2026-11-18
Design: `docs/specs/2026-11-18-tars-strip-workspace-design.md`(결정 12, 요구사항 결정 7)
Status: 끝났다(2026-11-18). 결과는 맨 아래. SW-M0의 게이트가 도는 동안 썼고, 그 결과(34/34, 바뀐 전제 없음)와 대조한 뒤 넘겼다. 브랜치 `app-layer-0-3`.

## 누가 무엇을 하나

구현은 Herdr 서브에이전트(Opus). lead는 plan · diff 대조 · 게이트 · commit. 서브에이전트는 commit하지 않는다.

고치는 파일:

- `terminal/src/layout.zig` — `MAX_PER_COLUMN = 3`, `split(.below)`의 거절. `columnOf`(slot → column 순번 · column 수) 하나.
- `terminal/src/layout_test.zig` — 검사 18을 한도 안의 모양으로 옮기고, 새 검사 20.
- `terminal/src/main.zig` — `strip>` 줄.
- `pane/check.sh` — 검사 16d(새 — 파일에 하위 꼬리표 `16c(음성)`가 이미 있어 d).
- `docs/help/desk.md` — `Cmd+Shift+D` 줄에 한도.

## 이 milestone이 끝나면

- 한 column에 pane이 셋이면 `Cmd+Shift+D`는 `pane> split refused`를 찍고 아무 일도 하지 않는다(화면 · 포커스 그대로).
- column 안 셋은 47줄에서 15 · 15 · 15다(M0부터 그렇다 — M1은 게이트가 처음 그것을 본다).
- 배치가 바뀔 때마다 `terminal: strip> cols=<n> focus_col=<k> heights=<a,b,…>` 한 줄. `heights`는 column마다 pane 수다.

## 착수 전에 확정한 것

1. `pane>` 줄은 안 바꾼다. `pointer/check.sh:611`이 그 줄 전체를 글자 그대로 견주고(`= "…sep ink=0"`), 다른 체인도
   `rect=… ` 뒤의 공백까지 본다. column 정보는 새 줄 `strip>`로 낸다. 찍는 자리는 `dumpPane` 바로 옆이고, 같은 방식으로
   지난 값(`last_strip_sig`)과 같으면 안 찍는다. 첫 프레임에는 찍는다.
2. 한도의 판정 순서: pane 여덟(전체) → 없는 slot → `.below`이고 그 column이 셋 → 크기(`L ≥ 2n-1`). 넷 다 null이고
   `main.zig`는 지금처럼 `split refused`를 찍는다. 거절 이유를 줄에 더하지 않는다 — 판정은 줄 수와 `pane>` 줄로 충분하다.
3. 한도가 서면 M0의 검사 18(오른쪽 column 넷)은 만들 수 없는 모양이다. column이 셋 이하일 때 옆 column의 구분선 줄에 시작
   줄이 떨어지는 격자는 5~9줄뿐이다(lead가 셈). 검사 18을 8줄 격자로 옮긴다. 왼쪽 둘(`0,0 x3` · 구분선 3 · `4 x4`),
   오른쪽 셋(시작 0 · 3 · 6, 높이 2 · 2 · 2)이고, 오른쪽 둘째의 `←`는 구분선 위의 왼쪽 첫 pane이다.
4. 검사 15의 생성기는 `.below`가 거절되면 `_ =`로 넘어간다. 잎 수가 여덟에 못 미치는 모양이 생기지만 판정은 그대로다.
   물은 수(지금 71,680)가 줄어드는 것은 정상이다 — 새 수를 결과에 적는다.
5. pane 체인 검사 16d는 검사 16 뒤, 검사 6 앞에 넣는다. 검사 6은 `0 | (1 / 2)`에서 포커스 2를 닫는 것을 전제한다.
   그래서 16c는 끝에서 그 모양으로 되돌린다.
   - 포커스 2에서 `Cmd+Shift+D` → `panes=4 focus=3 rect=78,32 77x15`, `strip> cols=2 focus_col=2 heights=1,3`
   - 한 번 더 → `pane> split refused` 한 줄 더, 마지막 `pane>` 줄이 그대로, `spawned` 줄 수가 그대로
   - `Cmd+W` → `hangup leaf=3`, 포커스가 위(2)로 → `panes=3 focus=2 rect=78,24 77x23`
   검사 6은 섞이지 않는다(lead가 봄). `hangup leaf=2 pid=` · `closed leaf=2`를 정규식으로 찾고, `child exited` 수는
   `Cmd+W` 직전에 다시 센다(`EXITS_BEFORE`). 16c의 닫기는 `child exited`가 하나 는 것까지 기다린 뒤 끝낸다.
6. 도움말: `Cmd+D` · `Cmd+Shift+D` 줄에 "아래로는 한 줄에 셋까지"를 더한다. `make quick`의 하위 명령 대조는 안 걸린다.

## `layout_test`

- 검사 1~17 · 19: 그대로. 18은 확정 3대로 옮긴다.
- 새 검사 20: 한 column에 셋 → 넷째 `.below`는 null, `count`와 사각형이 그대로. 다른 column의 `.below`는 된다.
  `.right`는 한도와 무관하다.

## 할 일

1. `layout.zig` · `layout_test.zig`. 호스트 `zig run terminal/src/layout_test.zig`.
2. `main.zig`의 `strip>` 줄.
3. `pane/check.sh` 16c, 도움말.
4. lead: `make quick`, 체인 `pane`(그리고 `pointer` · `dictation` — 안 바뀌었음을 본다), 루트 게이트.

## 판정

- `layout_test` 통과. 체인 `pane` PASS(16c 포함), `pointer` · `dictation` PASS. 루트 게이트 34/34.

## 결과 (2026-11-18)

1. 구현은 Herdr 서브에이전트(`sw-impl`, Opus) 3분 31초. lead가 diff를 대조했다 — 지운 줄은 검사 18의 옛 판, `split` 주석,
   도움말 한 줄, `main.zig`의 "덤프 열둘" 주석 넷(→ 열셋)뿐이다.
2. lead가 고친 것 둘: 새 검사의 이름을 16c → 16d(검사 16 안에 하위 꼬리표 `16c(음성)`가 이미 있다), 도움말의 "한 줄에" →
   "한 열(column)에"(가로 줄로 읽힌다).
3. `layout_test` 통과. 검사 15의 물음은 71,680 → 66,384(거절된 `.below`가 넘어간다, 확정 4).
4. `strip>` 줄은 `dumpPane` 바로 뒤에 찍힌다. 덤프 순서의 계약(`dumpCursor`는 `dumpInk` 뒤 · `dumpScroll` 앞, `dumpPointerAt`
   맨 뒤)과 닿지 않고, `pointer` · `dictation` 체인이 그대로 PASS다.
5. 체인: `pane` 199초(16d 포함) · `pointer` 276초 · `dictation` 237초 PASS. 16d의 줄: 셋째 `rect=78,32 77x15`, 구분선 픽셀
   15,872 → 25,728(가로선 77칸 × 셀 8×16 = 9,856), 넷째는 `split refused`만, 3을 닫으면 `focus=2 rect=78,24 77x23`.
6. 루트 게이트: 33/34(2,246초, `out/gate-logs/20261118-131938`). 빨강은 `bluetooth`(BT-M2) 하나 — `btvirt` Segmentation fault의
   간헐(`carryover.md`, 다섯 번째, lane 20). 같은 산출물로 체인만 다시 돌린 판은 초록(206초). SW-M1은 블루투스와 닿지 않는다.
