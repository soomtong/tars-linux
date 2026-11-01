# MC-M1 — 순수 층: 횟수를 세고, 단어 방식을 더한다

> 동작은 아직 안 바뀐다. `main.zig`는 컴파일이 되게 하는 최소만 고치고 시각을 넘기지 않는다(`null`) — 시각이 없으면
> 반복이 없으므로 게스트의 클릭은 PD-M2 그대로다. 시각 · `EVIOCSCLOCKID` · `repeat` 줄 · 게스트 검사는 MC-M2다.

Goal: design 결정 1 · 3 · 4 · 6을 순수한 두 층(`pointer.Gesture` · `vt.Screen`)에 넣고 호스트 테스트로 선다.

Architecture: `Gesture`가 지난 누름을 `Last` 하나로 기억하고 새 누름을 견준다. 두 번째 · 세 번째 누름은 곧바로
`select_start{ unit = word | line }`를 낸다. `vt.Screen`은 `SelectKind.word`와 그 앵커(`trackPin`)를 들고, `copyApply`가 단어
식(MC-M0 측정 4)으로 선택을 짓는다.

---

## 착수 전에 확정한 것

1. 시각이 없는 누름(`Stamp.t_us == null`)은 반복이 될 수 없다 — 라이브러리 `pressRepeat`의 `p.time orelse return
   error.PressRequiresReset`와 같다. M1의 `main.zig`가 이것을 쓴다. 그래서 M1의 게스트 동작은 바뀌지 않는다.
2. 조건 4의 "끌렸다"는 `phase`가 아니라 "선택 끝이 누른 칸을 떠났다"다. 두 번째 누름은 누름에서 곧바로 `dragging`이 되므로,
   `phase`로 보면 세 번째 누름이 늘 처음부터가 된다. `select_to`를 낸 움직임과 누른 채의 휠이 연속을 끊는다.
3. 단어 방식의 앵커를 선택의 `start()`에서 읽으면, 왼쪽으로 넘어간 뒤 다시 오른쪽으로 끌 때 앵커 단어가 사라진다(design 결정 4).
   그래서 `.word`일 때만 누른 자리를 `trackPin`으로 따로 든다. pin은 그 pin을 만든 `PageList`에서 놓아야 하므로 화면도 함께 든다.
4. `PageList.countTrackedPins()`가 있다(`PageList.zig:5738`). `vt_test`가 모드를 나간 뒤 수가 원래대로인지 센다.
5. 거리의 상한 8은 `main.zig`의 `CELL_W`와 같은 수여야 한다. `pointer.zig`는 `main.zig`를 못 보므로 상수를 따로 두고,
   `main.zig`에 comptime 단언 한 줄을 둔다.

## Task 1: `pointer.zig` — 횟수

더할 것.

```zig
/// 다시 누름으로 치는 간격과 거리(design 결정 3).
pub const MULTI_CLICK_US: i64 = 500_000;
pub const MULTI_CLICK_PX: u32 = 8; // main.zig의 CELL_W와 같다(comptime 단언)

/// 선택의 단위. `vt.Screen.SelectKind`와 짝이다 — main.zig가 옮겨 담는다.
pub const Unit = enum { char, word, line };
pub const Start = struct { at: Cell, unit: Unit };

/// 누름 하나의 때와 자리. `t_us`가 null이면 반복이 될 수 없다(확정 1).
pub const Stamp = struct { t_us: ?i64, x: u32, y: u32, ws: usize };
```

`Intent.select_start: Cell` → `select_start: Start`. 기존 두 자리(`motion`의 첫 이동 · `wheel`의 `pressed`)는 `.unit = .char`.

`Gesture`에 필드 셋.

```zig
/// 이 연속의 기억(design 결정 3). null이면 다음 누름은 처음부터다.
last: ?Last = null,
/// 마지막 누름이 몇 번째였나(1~3). main.zig가 `repeat` 줄에 쓴다.
clicks: u2 = 0,
/// 마지막 누름과 그 앞 누름의 차(µs). `clicks >= 2`일 때만 뜻이 있다.
gap_us: i64 = 0,

const Last = struct { t_us: i64, x0: u32, y0: u32, leaf: u4, ws: usize, count: u2 };
```

`press(hit, focus, at: Stamp)`.

- `hit == null` → 지금처럼 `ignored`, 그리고 `last = null`, `clicks = 0`.
- `repeat(at, h)`가 참이면 `count = @min(last.count + 1, 3)`, `last.t_us = at.t_us`(x0 · y0은 첫 누름 그대로). 아니면
  `last = { at.t_us, at.x, at.y, h.leaf, at.ws, 1 }` — 단 `at.t_us`가 null이면 `last = null`이고 `clicks = 1`.
- 횟수 1: 지금과 같다(`cancel` · `focus?`, `pressed`).
- 횟수 2 · 3: `cancel` · `focus?` · `select_start{ h, .word | .line }`, `phase = dragging`, `cur = start = h`.

`repeat`의 조건(전부 참이어야 한다): `last != null`, `at.t_us != null`, `0 <= at.t_us - last.t_us <= MULTI_CLICK_US`,
`(at.x − x0)² + (at.y − y0)² <= MULTI_CLICK_PX²`(i64로), `h.leaf == last.leaf`, `at.ws == last.ws`.

연속을 끊는 자리(`last = null`): `motion`이 `select_to`를 낼 때, `wheel`이 `scroll`을 낼 때, `handOff`, 그리고 `ignored`로 가는
모든 자리(키보드가 모드를 닫음 · `gone`). `release`는 안 끊는다.

## Task 2: `pointer_test.zig`

기존 `g.press(x, f)` 호출은 전부 `g.press(x, f, NO_TIME)`(`const NO_TIME: pointer.Stamp = .{ .t_us = null, .x = 0, .y = 0, .ws = 0 }`)로,
`.{ .select_start = a }`는 `.{ .select_start = .{ .at = a, .unit = .char } }`로 — 기대값의 뜻은 안 바뀐다.

새 검사(번호는 파일 끝의 다음 번호부터).

1. 1 → 2 → 3 → 3: 100ms 간격 네 누름. 둘째의 Intents가 `cancel` · `select_start(word)`, 셋째가 `cancel` · `select_start(line)`,
   넷째도 line. 각 누름 뒤 `clicks`, 둘째의 `gap_us == 100_000`.
2. 둘째 누름 뒤 `release(.copy)`가 `copy`를 낸다(결정 5).
3. 끊김 일곱: 501ms · 9픽셀(대각선 6, 6 = 72 > 64도) · 다른 잎 · 다른 ws · 앞 누름을 끌었다 · `handOff` 뒤 · 여백 누름 뒤 ·
   뒤로 간 시각(−1µs). 각각 `clicks == 1`이고 Intents가 횟수 1의 것. 경계값 하나씩: 500ms 정확히 · 8픽셀 정확히는 반복이다.
4. 시각 없음: `t_us = null` 두 누름 → 둘 다 `clicks == 1`(확정 1).
5. 두 번째 누름 뒤 끌기: `motion`이 `select_to`를 내고, 그 뒤 뗌 → `copy`, 다음 누름(100ms 뒤 같은 자리)은 `clicks == 1`(확정 2).
6. 다른 패널에 포커스가 있을 때의 두 번째 누름: `cancel` · `focus` · `select_start` 셋(버퍼 3을 꽉 채운다).

## Task 3: `vt.zig` — 단어 방식

- `SelectKind = enum { char, line, word }`.
- 필드 `copy_word: ?WordAnchor = null`, `const WordAnchor = struct { screen: *ghostty_vt.Screen, pin: *ghostty_vt.Pin }`.
- `fn dropWordAnchor(self)` — 있으면 `screen.pages.untrackPin(pin)`, null로. 부르는 자리: `copyExit`, `copySelect`가 방식을 풀거나
  바꿀 때, `copySelect(.word)`가 새로 잡기 전.
- `copySelect(.word)`: 커서 pin을 `trackPin`해 `copy_word`에 둔다. 그 뒤 `copyApply(pin, pin)`.
- `copyApply`의 `.word` 갈래: 앵커는 인자가 아니라 `copy_word.pin.*`(확정 3). `copyWordSel(s, anchor, cursor)` — MC-M0 측정 4의
  식. null이면 선택을 비운다(`s.clearSelection()`) — `.init(anchor, cursor)`로 떨어지지 않는다(쓰이지 않은 칸을 두 번 누른 것이
  문자 선택이 되면 안 된다).
- `copyEnterAt(x, y, kind: SelectKind)`: 마지막 줄의 `copySelect(.char)`를 `copySelect(kind)`로.
- `WORD_BOUNDARY`는 그대로 하나(design 결정 4).

## Task 4: `vt_test.zig`

기존 `copyEnterAt(x, y)` 다섯 자리에 `.char`. 새 검사(문자열 `alpha beta-gamma (delta)  eps`, 판정은 `copyYank`의 문자열).

1. `copyEnterAt(7, 0, .word)` → `beta-gamma`.
2. 그 뒤 `copyPointTo(1, 0)`(왼쪽으로 넘어감) → `alpha beta-gamma`.
3. 다시 `copyPointTo(19, 0)`(오른쪽 `delta`) → `beta-gamma (delta`. 앵커를 `start()`에서 읽으면 `alpha …`가 남는다 — 확정 3의
   검사이고 mutation 1이 이것을 노린다.
4. `.line`: `copyEnterAt(7, 0, .line)` → 줄 전체(끝 공백 없이).
5. 쓰이지 않은 칸 `copyEnterAt(35, 0, .word)` → `copyYank`가 null.
6. 새는 pin 없음: 들어가기 전 `countTrackedPins()` = N, `.word`로 들어간 동안 N + 1, `copyExit` 뒤 N. `v`로 방식을 바꾼 뒤에도 N.
7. soft wrap(10열): 아랫줄 글자에서 `.word` → `wrapword12`.

## Task 5: `main.zig` — 컴파일되는 최소

- `PointerWire.press`: `self.gesture.press(hit, self.ws.focus, .{ .t_us = null, .x = x, .y = y, .ws = self.current })`.
- `run`의 `.select_start => |st|`: `copyEnterAt(st.at.col, st.at.row, unitKind(st.unit))`. `unitKind`는 `pointer.Unit` →
  `vt.Screen.SelectKind`의 switch(`else` 없음).
- `comptime std.debug.assert(pointer.MULTI_CLICK_PX == CELL_W);`

## Task 6: 판정

1. `make quick`(fmt · ast-check · shellcheck).
2. 컨테이너 `cd terminal && ./prepare.sh && zig build test` — `pointer_test` · `vt_test` PASS.
3. mutation 둘(되돌린다): (1) `copyApply`의 `.word`가 앵커를 `copy_word.pin.*` 대신 인자 `anchor`로 → vt 검사 3 빨강. (2) `repeat`의
   시각 상한 비교를 지움 → pointer 검사 3의 501ms 빨강.
4. 게스트 동작은 안 바뀌었으므로 `pointer` · `copy` 체인을 단독으로 하나씩(각 약 3분). 루트 게이트는 M2에서.
5. 이 plan 끝에 "결과" 절, design Status 줄, 커밋 `MC-M1: count repeated presses and add the word selection kind`.

## 결과 (2026-11-01)

lead가 직접 구현했다. `git diff --stat` 다섯 파일 +440 −36 — `pointer.zig` · `pointer_test.zig` · `vt.zig` · `vt_test.zig` ·
`main.zig`(+24 −3, 컴파일되는 최소). 지운 줄은 시그니처 · `select_start`의 타입 · 그것을 쓰던 호출 자리뿐이다.

판정.

1. `make quick` PASS(shellcheck 52파일 · fmt · ast-check). 처음 회차는 이름 그림자 둘(`fn at` · capture `c`)과 comptime 블록의
   doc 주석으로 멈췄다 — 고쳤다.
2. 컨테이너 `zig build test` exit 0. `pointer_test` 검사 29~34, `vt_test` 검사 107~113 다 OK.
3. mutation 둘 다 잡혔다. (1) `.word`의 앵커를 인자로 → vt 검사 108 `yanked 'alpha', want 'alpha beta-gamma'`. 노린 109보다 앞에서
   잡혔다 — `.word`일 때 `copyPointTo`가 `copyApply(cursor, cursor)`로 부르므로 인자를 앵커로 쓰면 앵커가 커서가 된다. 같은 결함
   (앵커를 `copy_word`에서 안 읽음)이 더 이른 자리에서 드러난 것이다. (2) 시각 상한 지움 → pointer 검사 31 `501ms starts over = 0x2,
   want 0x1`.
4. 게스트는 안 바뀌었다 — `pointer` 체인 단독 201초 PASS, `copy` 체인 단독 302초 PASS.

바로잡은 것. 검사 112의 기대값을 처음에 "기준 + 1"로 적었는데 라이브러리의 선택 자체가 tracked다 — 양 끝을 pin 둘로 든다.
실측: 선택 없음 2, 문자 선택 4, 단어 선택 5, `copyExit` 뒤 2, 단어에서 `v`로 바꾼 뒤 4(문자 선택의 양 끝은 남고 앵커는 풀림).
단어 앵커는 정확히 하나만 더하고 모든 출구에서 풀린다. 검사 주석에 적었다.

구현에서 plan과 달라진 것. `u2`인 `count`를 `@min(l.count + 1, 3)`으로 올리면 3 + 1이 `u2` 안에서 넘친다(넷째 누름에서 safety
panic) — `if (l.count < 3) l.count += 1`. `copyPointTo`는 `.word`일 때 "지금 선택이 없으면 그만"을 건너뛴다 — 단어 앵커는 선택과
따로 있어서, 쓰이지 않은 칸을 두 번 누른 뒤 단어 쪽으로 끌면 선택이 생겨야 한다.
