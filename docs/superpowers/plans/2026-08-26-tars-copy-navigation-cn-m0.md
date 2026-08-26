# TARS Copy Navigation CN-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** copy mode에서 `w`와 `b`가 커서를 **단어 단위로** 옮긴다. 지금은
`hjkl`로 한 칸씩 가는 것이 전부라 한 줄을 가로지르는 데만 키를 열몇 번 눌러야
한다.

**Design doc:** `docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md`
(결정 1·2·3·11이 이 milestone의 몫이다. **design은 승인되어 있으므로 다시
논의하지 않는다.**)

**Tech Stack:** Zig 0.16, libghostty-vt, evdev, QEMU monitor `sendkey`,
bash 게이트 스크립트

**이 milestone은 CN-M1보다 훨씬 작다.** 새 개념을 만들지 않고 기존 구조에
형제 함수 하나와 표 두 줄을 더한다. 화면에 새로 그리는 것도 없다.

---

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

### CM-M0~M2가 실측으로 남긴 것

1. **copy 커서는 언제나 화면 맨 아랫줄에서 시작한다**(`row=46`, 화면은 47줄).
   셸 프롬프트가 거기 있기 때문이다. 게이트는 `k`로 올라간다.
2. **`sendkey`를 0.05초 간격으로 80번 보내도 하나도 안 떨어진다.** Task 3이 그
   루프를 `h`로 다시 쓴다.
3. **`terminal: key>` 줄은 PTY로 바이트가 나갈 때만 찍힌다.** 음성 검사의
   도구다.
4. **`copyMove`의 좌우는 줄을 넘나들지 않는다**(`vt.zig:359-361`에서 x를 0과
   `cols-1`로 clamp한다). 그래서 `h`를 충분히 많이 누르면 **반드시** col 0에
   선다 — Task 3이 이것에 기댄다.
5. **`Copy`를 건드리면 `zig build test`만으로 모자라다.** Zig가 참조되지 않는
   함수를 분석하지 않아서 `readKeys` 쪽 깨짐을 놓친다. Task 2에서 `zig build`를
   함께 돌린다.
6. **검사도 화면을 만든 뒤 `cells()`를 한 번 부르고 시작한다.** `copyEnter`가
   `state.cursor.viewport`를 읽는데 한 번도 그리지 않은 화면에서는 그 값이
   null이라 커서가 왼쪽 위에서 시작한다.

### 이 plan을 쓰면서 소스에서 확인한 것 일곱

**전부 vendor된 ghostty 소스를 직접 읽어서 얻었다. 프로브는 돌리지 않았고, 이
사실들은 Task 1의 검사로 옮겨 실행으로 다시 증명한다.**

1. **`Screen.selectWord(pin, boundary_codepoints)`** (`Screen.zig:3217`)는
   **이동이 아니라 범위**다. pin이 놓인 단어의 `Selection`을 준다.
2. **그 "단어"에는 공백 덩어리도 포함된다** — "exclusively whitespace or
   exclusively non-whitespace". `"ABC  DEF"`가 **세 단어**다.
3. **빈 셀에서는 null을 준다** — "If our cell is empty we can't select a word,
   because we can't select areas where the screen is not yet written."
4. **경계 코드포인트는 우리가 넘긴다.** ghostty 자신의 검사가 쓰는 기본값
   스무 개가 `Screen.zig:9800`에 있다.
5. **`Pin.rightWrap(n)` / `Pin.leftWrap(n)`** (`PageList.zig:7228`, `:7208`)이
   줄을 넘나들며 한 칸 옮기고, 화면 끝을 넘으면 **null**을 준다.
6. **`Screen.scroll(.{ .pin = p })`가 있다**(`Screen.zig:1565`, `:1576`). 그
   pin을 뷰포트의 **top left**로 만든다(x는 무시). `assertIntegrity`까지
   해 주므로 `pages.scroll`을 직접 부르지 않는다.
   **`Terminal.ScrollViewport`에는 `.pin`이 없다**(`Terminal.zig:2504`) —
   HANDOFF가 경고한 "이름이 다르다"의 또 다른 얼굴이다.
7. **`PageList.pointFromPin(.viewport, pin)`** (`:5614`)은 뷰포트 **위쪽**
   밖이면 null을 주지만 **아래쪽 밖은 알려주지 않는다.** 노드를 계속 따라가며
   y를 더해서 `rows`보다 큰 값을 그냥 돌려준다. **아래쪽은 우리가 가른다.**

### 그리고 우리 저장소에서 확인한 것 하나 — **이것이 이번의 함정이다**

**`input_test.zig:497`이 `KEY_W`를 "모르는 키는 삼킨다"의 대상으로 쓰고
있다.**

```zig
    try expect(&cm, K.KEY_Q, 1, "");
    try expect(&cm, K.KEY_W, 1, "");   // ← w가 명령이 되면 이 줄이 깨진다
```

`expect`는 `.copy`가 오면 실패로 처리하므로(`input_test.zig:47`), Task 2에서
`w`를 배선하는 순간 이 검사가 깨진다. **CM-M2가 배운 축의 정확한 재현이다** —
`Copy`에 variant를 더하는 것 자체는 아무것도 안 깨뜨리지만, **키의 의미가
바뀌는 것**은 그것을 보던 검사를 깨뜨린다. CM-M2 때는 그 자리에 예고 주석이
있었지만 **여기에는 없다.**

Task 2 Step 3a가 이것을 고친다. **모르고 실행하면 Step 6에서 영문 모를 실패를
만난다.**

---

## 이번에 정하는 것 셋 (design doc이 안 정한 자리)

### 1. **쓰이지 않은 자리에 닿으면 이동하지 않는다**

`alpha beta gamma`가 20칸 화면에 있으면 col 16~19는 한 번도 쓰이지 않은
셀이다. `gamma`에서 `w`를 누르면 그 지대에 닿는데, 여기서 **아무 일도 안
한다.**

**vim은 다음 줄의 첫 단어로 간다. 우리는 안 간다.** 셋을 저울질했다.

- **다음 줄로 간다(vim)** — 줄 끝의 빈 지대를 지나 다음 줄의 첫 텍스트 셀을
  찾아야 한다. 화면 끝이면 뷰포트를 밀어야 하고, 스크롤백 맨 아래면 멈춰야
  한다. 분기가 셋 는다.
- **빈 셀을 한 칸씩 기어간다** — 구현은 가장 쉽지만 `w`가 `l`과 같아지는
  구간이 생긴다. 사람이 "고장 났나"로 읽는다.
- **멈춘다(고른 것)** — 줄 사이 이동은 `j`/`k`가 이미 한다. 스크롤백을 훑어
  한 줄을 잡는 실제 용도에서 `w`는 줄 **안에서** 쓰인다.

**이 차이를 감추지 않는다.** CN-M1이 검색을 넣고 나면 줄 사이 이동의 주력이
`/`가 되므로, 그때 다시 저울질할 값이 생긴다.

### 2. `b`는 단어 중간에서 그 단어의 시작으로 먼저 간다

vim과 같다. 넣지 않으면 `b`가 단어를 하나씩 건너뛰어 `w`와 대칭이 되지
않는다 — `w`로 간 자리에서 `b`를 눌러도 원래 자리로 안 돌아온다.

판정은 "지금 pin이 그 단어의 `start()`와 같은가"이고, `Pin`은
`{ node, y, x }`라 셋을 비교한다.

### 3. 게이트는 커서 좌표만 보고, 선택 넓히기는 호스트 검사가 본다

`w`/`b`도 선택을 함께 넓혀야 한다(design 결정 11). 그런데 그것을 게이트에서
보려면 `v` → `w` → `y` → `clip>`의 왕복이 필요하고, **기대 문자열을 미리
정확히 적을 수 없다** — 선택이 커서 셀을 포함하는지가 한 글자를 가른다.

`vt_test`는 즉시 돌려볼 수 있어서 값을 확정할 수 있다. **게이트는 "게스트까지
키가 도달해 커서가 단어 단위로 움직였다"와 "PTY로 안 샜다"만 본다.** 이것이
게이트 시간도 아낀다(design 위험 3).

---

## Task 1: `vt.zig`가 단어 단위로 커서를 옮긴다

**Files:**
- Modify: `terminal/src/vt.zig` (`copyMove` 뒤, `SelectKind` 앞)
- Modify: `terminal/src/vt_test.zig` (파일 끝의 `PASS` 직전)

### Step 1: `vt_test.zig`에 검사를 먼저 더한다 (사용자가 편집)

**넣을 것** — `vt_test.zig`에서 다음 두 줄을 찾는다.

```zig
    std.debug.print("vt_test: copy selection OK\n", .{});

    std.debug.print("PASS\n", .{});
```

**그 사이에** 아래를 넣는다.

```zig
    // ── CN-M0: 단어 단위 이동 ───────────────────────────────────────────
    //
    // 화면을 따로 만든다. 위의 cm·pruned는 검사가 여럿 지나간 자리라 몇 번째
    // 줄에 무엇이 있는지가 흐려진다(CM-M1이 같은 이유로 cm을 새로 만들었다).
    //
    // 20칸 화면에 "alpha beta gamma"(16자)를 넣으면 자리가 이렇게 된다.
    //
    //   col:  0....4 5 6...9 10 11...15 16......19
    //         alpha  _ beta  _  gamma   (쓰인 적 없음)
    //
    // **공백 둘(col 5, col 10)이 이 검사의 핵심이다.** 라이브러리는 그것도
    // 한 단어로 세므로(plan의 확정 사실 2), 우리 w가 한 번 더 건너뛰지
    // 않으면 아래 첫 단언에서 6이 아니라 5가 나온다.
    const wm = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer wm.deinit();
    wm.feed("alpha beta gamma\r\n");
    // 한 프레임을 먼저 그린다 — copyEnter가 셸 커서 자리를 RenderState에서
    // 읽는다(CM-M1이 배운 것).
    _ = try wm.cells(&buf);
    wm.copyEnter();
    // 셸 커서는 다음 줄(row 1)에 있다. 한 번 올라가면 글자가 있는 줄이다.
    try wm.copyMove(0, -1);

    // 검사 11. `w`가 **다음 단어의 첫 글자**로 간다.
    try wm.copyMoveWord(.next);
    var wc = wm.copyCursor() orelse return error.NoCopyCursor;
    if (wc.y != 0 or wc.x != 6) {
        std.debug.print(
            "FAIL: w landed at row={d} col={d} (expected row=0 col=6, the 'b' of beta)\n",
            .{ wc.y, wc.x },
        );
        return error.WordNextWrong;
    }
    try wm.copyMoveWord(.next);
    wc = wm.copyCursor().?;
    if (wc.x != 11) {
        std.debug.print(
            "FAIL: the second w landed at col {d} (expected 11, the 'g' of gamma)\n",
            .{wc.x},
        );
        return error.WordNextWrong;
    }
    std.debug.print("vt_test: w가 공백 덩어리를 건너뛴다 OK (0 -> 6 -> 11)\n", .{});

    // 검사 12. **쓰이지 않은 자리에 닿으면 움직이지 않는다**(plan 결정 1).
    // gamma가 마지막 단어이고 col 16부터는 한 번도 쓰인 적이 없다.
    //
    // **이 검사가 없으면 "빈 셀을 한 칸씩 기어간다"도 통과한다** — 그 구현은
    // w가 l과 같아지는 구간을 만든다.
    try wm.copyMoveWord(.next);
    wc = wm.copyCursor().?;
    if (wc.x != 11) {
        std.debug.print(
            "FAIL: w walked into the unwritten area (col {d}, expected to stay at 11)\n",
            .{wc.x},
        );
        return error.WordNextRanOff;
    }
    std.debug.print("vt_test: w가 쓰이지 않은 자리에서 멈춘다 OK\n", .{});

    // 검사 13. `b`가 `w`를 정확히 되돌린다.
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.x != 6) {
        std.debug.print("FAIL: b landed at col {d} (expected 6)\n", .{wc.x});
        return error.WordPrevWrong;
    }
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.x != 0) {
        std.debug.print("FAIL: the second b landed at col {d} (expected 0)\n", .{wc.x});
        return error.WordPrevWrong;
    }
    std.debug.print("vt_test: b가 w를 되돌린다 OK (11 -> 6 -> 0)\n", .{});

    // 검사 14. 줄 맨 앞에서 `b`를 더 눌러도 위로 안 샌다. 이 화면의 row 0
    // 위에는 아무것도 없다.
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.y != 0 or wc.x != 0) {
        std.debug.print(
            "FAIL: b escaped the top of the screen to row={d} col={d}\n",
            .{ wc.y, wc.x },
        );
        return error.WordPrevRanOff;
    }
    std.debug.print("vt_test: b가 화면 위로 안 샌다 OK\n", .{});

    // 검사 15. **단어 중간에서 b는 그 단어의 시작으로 간다**(plan 결정 2).
    //
    // col 0에서 오른쪽으로 여덟 칸 = beta의 't'(col 8). 거기서 b는 col 6이다.
    // **이 검사가 없으면 "언제나 이전 단어로 간다"도 통과하고**, 그러면 w로
    // 간 자리에서 b를 눌러도 원래 자리로 안 돌아온다.
    var step: usize = 0;
    while (step < 8) : (step += 1) try wm.copyMove(1, 0);
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.x != 6) {
        std.debug.print(
            "FAIL: b from the middle of 'beta' landed at col {d} (expected 6)\n",
            .{wc.x},
        );
        return error.WordPrevMidWrong;
    }
    std.debug.print("vt_test: 단어 중간의 b가 그 단어 앞으로 간다 OK\n", .{});

    // 검사 16. **선택 중이면 함께 넓힌다**(design 결정 11).
    //
    // col 6('b')에서 v로 잡고 w를 누르면 커서가 col 11로 가고, 선택은
    // col 6..11이 된다. **끝 셀이 포함되므로 여섯 자다** — "beta g".
    // 게이트는 이 왕복을 안 본다(plan 결정 3). 여기가 유일한 자리다.
    try wm.copySelect(.char);
    try wm.copyMoveWord(.next);
    const grabbed = (try wm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, grabbed, "beta g")) {
        std.debug.print(
            "FAIL: v then w yanked '{s}' (expected 'beta g')\n",
            .{grabbed},
        );
        return error.WordSelectionWrong;
    }
    std.debug.print("vt_test: 선택이 w를 따라 넓어진다 OK ('{s}')\n", .{grabbed});
```

### Step 2: 검사가 **컴파일에서** 실패하는 것을 확인한다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

**기대:** `no member named 'copyMoveWord'` 또는 그에 준하는 컴파일 에러.

**이것이 이 단계의 "빨간불"이다.** Zig에서는 없는 함수를 부르는 검사가 실행에
못 가고 컴파일에서 멈춘다. 에러가 **다른 이유**로 나면(예: `wm`이 이미 있는
이름) 그것부터 고친다.

에러 본문이 길면 `grep -aE '^src/.*error'`로 뽑는 편이 빠르다(HANDOFF).

### Step 3: `vt.zig`에 단어 이동을 넣는다 (사용자가 편집)

**넣을 것** — `vt.zig`에서 `copyMove`의 끝인 다음 세 줄을 찾는다.

```zig
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }
```

**그 뒤, `/// 선택 방식. \`v\`가 char, \`V\`가 line이다.` 앞에** 아래를 넣는다.

```zig

    /// 단어 경계로 치는 코드포인트.
    ///
    /// **값은 ghostty 자신의 검사가 쓰는 기본값과 같다**(`Screen.zig:9800`).
    /// 라이브러리는 이 목록을 설정에서 받도록 되어 있는데
    /// (`Surface.zig:1217`의 `selection_word_chars`) 우리에게는 설정이 없으므로
    /// 상수로 둔다. `/config/tars.conf`로 뺄 수 있는 자리이지만 바꾸고 싶어 한
    /// 사람이 없다 — 필요해지면 그때 뺀다.
    const WORD_BOUNDARY = [_]u21{
        0,   ' ', '\t', '\'', '"',
        '│',
        '`', '|', ':',  ';',  ',',
        '(', ')', '[',  ']',  '{',
        '}', '<', '>',  '$',
    };

    /// 단어 이동의 방향. `w`가 next, `b`가 prev다.
    pub const WordDir = enum { next, prev };

    /// 그 자리에 글자가 쓰였는가. **한 번도 안 쓰인 셀과 공백은 다르다** —
    /// `"alpha"` 뒤의 공백은 쓰인 셀이고, 줄 끝의 남은 칸은 아니다.
    /// `selectWord`가 후자에서 null을 주므로(plan 확정 사실 3) 우리도 그
    /// 경계를 같은 기준으로 본다.
    fn written(pin: ghostty_vt.Pin) bool {
        return pin.rowAndCell().cell.hasText();
    }

    /// 그 자리가 단어 경계인가. **쓰이지 않은 셀도 경계로 친다.**
    fn boundaryAt(pin: ghostty_vt.Pin) bool {
        const cell = pin.rowAndCell().cell;
        if (!cell.hasText()) return true;
        return std.mem.indexOfScalar(
            u21,
            &WORD_BOUNDARY,
            cell.content.codepoint.data,
        ) != null;
    }

    /// 두 pin이 같은 자리인가. `Pin`은 `{ node, y, x }`라 셋을 본다.
    fn samePin(a: ghostty_vt.Pin, b: ghostty_vt.Pin) bool {
        return a.node == b.node and a.y == b.y and a.x == b.x;
    }

    /// `w`/`b`. **커서를 단어 단위로 옮긴다.**
    ///
    /// **라이브러리가 세는 "단어"와 vim의 `w`는 다르다**(design 결정 3).
    /// `selectWord`는 공백 덩어리도 한 단어로 세므로(`"ABC  DEF"`가 셋),
    /// 공백에 내려앉으면 한 번 더 건너뛰는 일을 우리가 한다. **경계 판정이라는
    /// 어려운 부분은 끝까지 라이브러리에 남는다** — 우리가 정하는 것은 "어느
    /// 방향으로 몇 번 부르는가"뿐이다.
    ///
    /// 쓰이지 않은 자리에 닿으면 **움직이지 않는다**(CN-M0 plan 결정 1).
    /// vim은 다음 줄의 첫 단어로 가지만, 줄 사이 이동은 `j`/`k`가 이미 한다.
    pub fn copyMoveWord(self: *Screen, dir: WordDir) !void {
        if (self.copy_cursor == null) return;
        const s = self.term.screens.active;
        const from = self.copyPin() orelse return;

        const target = switch (dir) {
            .next => wordNext(s, from),
            .prev => wordPrev(s, from),
        } orelse return;

        self.copyPlace(target);

        // 선택 중이면 커서를 따라 넓힌다. **`copyMove`와 같은 문을 통과한다**
        // (design 결정 11) — 이동 수단마다 선택 갱신을 따로 짜면 그중 하나만
        // 어긋나도 "어떤 키로 움직였느냐에 따라 복사되는 글자가 다르다"가 된다.
        if (self.copy_kind == null) return;
        const sel = s.selection orelse return;
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }

    /// 다음 단어의 첫 글자. 갈 곳이 없으면 null.
    ///
    /// **두 번까지만 건너뛴다.** 지금 단어에서 한 번, 그것이 공백 덩어리면 한
    /// 번 더다. 세 번째는 있을 수 없다 — 경계 문자들이 연달아 오면 라이브러리가
    /// 그것을 **한 덩어리로** 묶기 때문이다(`expect_boundary` 로직).
    fn wordNext(s: *ghostty_vt.Screen, from: ghostty_vt.Pin) ?ghostty_vt.Pin {
        var pin = from;
        var hop: u8 = 0;
        while (hop < 2) : (hop += 1) {
            const word = s.selectWord(pin, &WORD_BOUNDARY) orelse return null;
            pin = word.end().rightWrap(1) orelse return null;
            if (!written(pin)) return null;
            if (!boundaryAt(pin)) return pin;
        }
        return pin;
    }

    /// 이전 단어의 첫 글자. 갈 곳이 없으면 null.
    ///
    /// **커서가 단어 중간이면 그 단어의 시작으로 간다**(vim과 같다,
    /// CN-M0 plan 결정 2). 그러지 않으면 `w`로 간 자리에서 `b`를 눌러도 원래
    /// 자리로 안 돌아온다.
    fn wordPrev(s: *ghostty_vt.Screen, from: ghostty_vt.Pin) ?ghostty_vt.Pin {
        if (s.selectWord(from, &WORD_BOUNDARY)) |word| {
            const st = word.start();
            if (!samePin(st, from)) return st;
        }

        var pin = from.leftWrap(1) orelse return null;
        var hop: u8 = 0;
        while (hop < 2) : (hop += 1) {
            if (!written(pin)) return null;
            const word = s.selectWord(pin, &WORD_BOUNDARY) orelse return null;
            if (!boundaryAt(pin)) return word.start();
            pin = word.start().leftWrap(1) orelse return null;
        }
        return pin;
    }

    /// 목표 pin에 커서를 놓는다. **화면 밖이면 뷰포트를 옮긴다.**
    ///
    /// `pointFromPin(.viewport, …)`이 뷰포트 **위쪽** 밖은 null로 알려주지만
    /// **아래쪽 밖은 알려주지 않는다** — 노드를 계속 따라가며 y를 더해서
    /// `rows`보다 큰 값을 그냥 돌려준다(`PageList.zig:5614`). 그래서 아래쪽은
    /// 우리가 가른다. **이것을 빠뜨리면 커서가 화면 밖 좌표를 갖고, 증상은
    /// 크래시가 아니라 "커서가 안 보인다"가 된다.**
    ///
    /// 뷰포트를 미는 두 경로가 모두 `Screen.scroll`을 통과하는 것에 뜻이 있다.
    /// `pages.scroll`을 직접 부르면 `assertIntegrity`와 kitty dirty 표시를
    /// 건너뛴다(`Screen.zig:1576`). **`Terminal.ScrollViewport`에는 `.pin`이
    /// 없어서**(`Terminal.zig:2504`) 기존 `scrollByRows`로는 위쪽을 못 다룬다.
    fn copyPlace(self: *Screen, pin: ghostty_vt.Pin) void {
        const s = self.term.screens.active;
        const rows: u32 = s.pages.rows;

        if (s.pages.pointFromPin(.viewport, pin)) |pt| {
            const co = pt.coord();
            if (co.y < rows) {
                self.copy_cursor = .{ .x = @intCast(co.x), .y = @intCast(co.y) };
                return;
            }
            // 뷰포트 **아래**다. 최소한만 민다 — 목표가 맨 아랫줄이 된다.
            s.scroll(.{ .delta_row = @intCast(co.y - rows + 1) });
        } else {
            // 뷰포트 **위**다. 목표를 화면 맨 윗줄로 올린다.
            s.scroll(.{ .pin = pin });
        }

        const pt = s.pages.pointFromPin(.viewport, pin) orelse return;
        const co = pt.coord();
        if (co.y >= rows) return;
        self.copy_cursor = .{ .x = @intCast(co.x), .y = @intCast(co.y) };
    }
```

### Step 4: 호스트 검사를 돌린다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

**기대:** `vt_test`가 검사 11~16의 여섯 줄을 찍고 `PASS`로 끝난다.

```
vt_test: w가 공백 덩어리를 건너뛴다 OK (0 -> 6 -> 11)
vt_test: w가 쓰이지 않은 자리에서 멈춘다 OK
vt_test: b가 w를 되돌린다 OK (11 -> 6 -> 0)
vt_test: b가 화면 위로 안 샌다 OK
vt_test: 단어 중간의 b가 그 단어 앞으로 간다 OK
vt_test: 선택이 w를 따라 넓어진다 OK ('beta g')
```

**검사 16의 기대 문자열이 틀릴 수 있다.** 선택이 커서 셀을 포함하는지가 한
글자를 가르는데, 그 답은 `Selection.init(anchor, cursor, false)`의 의미에
달려 있고 우리가 소스로 확정하지 않았다. **`'beta g'`가 아닌 다른 값이 나오면
그 값이 맞는 답이다** — 검사의 기대값을 실측값으로 고치고, **왜 그것이 맞는지
한 줄을 주석에 남긴다.** 실패가 아니라 확정이다.

그 외의 실패는 진짜 실패다. 특히 **검사 11에서 6이 아니라 5가 나오면** 공백
덩어리 건너뛰기(`wordNext`의 두 번째 hop)가 동작하지 않은 것이다.

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Move the copy cursor by words"
```

---

## Task 2: `w`/`b`가 키에서 화면까지 이어진다

**Files:**
- Modify: `terminal/src/input.zig:175`(`Copy` enum), `:536~`(copy 표)
- Modify: `terminal/src/input_test.zig` (copy 검사들 뒤)
- Modify: `terminal/src/main.zig:495~`(copy 배선 switch)

### Step 1: `Copy` enum에 variant 둘을 더한다 (사용자가 편집)

**지울 것** — `input.zig`의 `Copy` enum 주석 첫 문단이 "CM-M2로 표가
닫혔다"고 말하는데, **더 이상 닫혀 있지 않다.**

```zig
/// copy mode 안에서 키가 만드는 명령.
///
/// **CM-M2로 표가 닫혔다.** CM-M0부터 지켜 온 규율은 "쓰지 않을 variant를 미리
/// 만들어 두지 않는다"였다 — `main.zig`의 switch가 `else` 없이 닫혀 있어서,
/// variant를 더하는 순간 컴파일러가 배선할 자리를 알려주기 때문이다. 미리
/// 만들어 두면 그 신호를 잃는다. 다음에 표를 늘릴 사람도 같은 순서로 하면 된다.
pub const Copy = enum {
```

**넣을 것**

```zig
/// copy mode 안에서 키가 만드는 명령.
///
/// **CM-M2가 닫았던 표를 CN-M0이 다시 연다.** CM-M0부터 지켜 온 규율은 "쓰지
/// 않을 variant를 미리 만들어 두지 않는다"였다 — `main.zig`의 switch가 `else`
/// 없이 닫혀 있어서, variant를 더하는 순간 컴파일러가 배선할 자리를 알려주기
/// 때문이다. 미리 만들어 두면 그 신호를 잃는다. **이번에도 같은 순서로 한다:
/// 여기에 둘을 더하면 `main.zig`가 컴파일 에러로 배선을 요구한다.**
///
/// **CN-M1이 이 타입을 `union(enum)`으로 바꾼다**(design 결정 6). 검색
/// 프롬프트에 친 글자를 실어 나를 payload가 필요하기 때문이고, payload가 없는
/// 지금은 바꾸지 않는다.
pub const Copy = enum {
```

**그리고** `select_char` 바로 앞(즉 `right,` 다음 줄)에 아래를 넣는다.

```zig
    /// `w` — 다음 단어의 첫 글자로.
    ///
    /// **쓰이지 않은 자리에 닿으면 움직이지 않는다**(CN-M0 plan 결정 1).
    /// vim과 다른 자리이고, 줄 사이 이동은 `j`/`k`가 한다.
    word_next,
    /// `b` — 이전 단어의 첫 글자로. 단어 중간이면 **그 단어의 시작**으로 간다.
    word_prev,
```

### Step 2: copy 표에 두 줄을 더한다 (사용자가 편집)

**넣을 것** — `input.zig`의 copy 분기에서 방향키 네 줄을 찾는다.

```zig
                c.KEY_H, c.KEY_LEFT => return .{ .copy = .left },
                c.KEY_J, c.KEY_DOWN => return .{ .copy = .down },
                c.KEY_K, c.KEY_UP => return .{ .copy = .up },
                c.KEY_L, c.KEY_RIGHT => return .{ .copy = .right },
```

**그 뒤에** 아래를 넣는다.

```zig
                // 단어 이동(CN-M0). **방향키 짝이 없다** — evdev에는 "다음
                // 단어" 키가 없고, macOS의 Option+←/→가 그 뜻이지만 그 조합은
                // chord()의 표에 이미 다른 뜻으로 있다(IP 결정 8). 모드 안에서
                // 그것을 가로채면 두 표가 같은 키에 다른 뜻을 갖게 된다.
                c.KEY_W => return .{ .copy = .word_next },
                c.KEY_B => return .{ .copy = .word_prev },
```

**`KEY_B`를 `KEY_V`보다 앞에 두는 것에 뜻은 없다.** switch의 팔은 겹치지
않으므로 순서가 결과를 안 바꾼다. 방향키 넷 바로 뒤에 두는 것은 **읽는
사람에게 "이것도 이동이다"를 보이기 위해서**다.

### Step 3: `input_test.zig`의 **기존 검사 하나를 고치고** 새 검사를 더한다 (사용자가 편집)

#### 3a. 검사 4가 `KEY_W`를 "모르는 키"로 쓰고 있다 — **이 줄이 깨진다**

**이것이 CM-M2가 배운 축의 정확한 재현이다.** `Copy`에 variant를 더하는 것
자체는 `input_test`를 안 깨뜨리지만, **`w`가 "삼켜지는 키"에서 "명령이 되는
키"로 의미가 바뀌는 것**은 그것을 보던 검사를 깨뜨린다. CM-M2에서는 IP 시절의
`expect(&state, K.KEY_V, 1, "v")`가 같은 이유로 깨졌고, 그 자리에는 예고
주석이 있었다. **여기에는 없다** — `w`가 언젠가 뜻을 가질 것을 CM-M0이
예상하지 못했기 때문이다.

**지울 것** — `input_test.zig:494-501`의 검사 4.

```zig
    // 검사 4. **모르는 키는 삼킨다**(design 결정 3). 게이트의 음성 검사와
    // 같은 사실을 여기서 먼저 본다.
    try expect(&cm, K.KEY_Q, 1, "");
    try expect(&cm, K.KEY_W, 1, "");
    try expect(&cm, K.KEY_E, 1, "");
    try expect(&cm, K.KEY_R, 1, "");
    try expect(&cm, K.KEY_T, 1, "");
    try expect(&cm, K.KEY_ENTER, 1, "");
```

**넣을 것**

```zig
    // 검사 4. **모르는 키는 삼킨다**(design 결정 3). 게이트의 음성 검사와
    // 같은 사실을 여기서 먼저 본다.
    //
    // **CN-M0이 이 목록에서 `w`를 뺐다.** 그것이 이제 `.word_next`라서
    // 여기서는 "모르는 키"가 아니다. 자리를 `z`로 메운다 — 게이트가 대조군으로
    // 쓰는 것과 같은 키다.
    //
    // **`e`와 `n`은 아직 모르는 키이지만 영영 그렇지는 않다.** `e`는 CN이
    // 일부러 안 만든 단어 이동이고(design 결정 2), `n`은 CN-M1의 검색이
    // 가져간다. **그때 이 줄들이 바뀐다** — CM-M2가 `Cmd+V`에 대해 남긴
    // 예고를 여기서 갚는다.
    try expect(&cm, K.KEY_Q, 1, "");
    try expect(&cm, K.KEY_Z, 1, "");
    try expect(&cm, K.KEY_E, 1, "");
    try expect(&cm, K.KEY_R, 1, "");
    try expect(&cm, K.KEY_T, 1, "");
    try expect(&cm, K.KEY_ENTER, 1, "");
```

#### 3b. CN-M0 검사를 더한다

**넣을 것** — `input_test.zig`에서 CM-M2 검사 13의 끝인 다음 두 줄을 찾는다.

```zig
    try expectCopy(&cm, K.KEY_ESC, .exit);

    std.debug.print("input_test: copy mode OK\n", .{});
```

**그 사이에** 아래를 넣는다. 앞 검사 13이 Esc로 모드를 닫아 두었으므로
**모드 밖에서 시작한다.**

```zig

    // ── CN-M0: 단어 이동 ────────────────────────────────────────────────
    //
    // 검사 14. **모드 밖의 `w`와 `b`는 평범한 글자다.** 대조군을 먼저 본다 —
    // 이것이 없으면 "`w`가 언제나 삼켜진다"도 통과하고, 그러면 셸에 `w`를 못
    // 치게 된 것을 아무도 모른다. **variant를 더하는 축만 보면 이 사고가
    // 안 보인다**(CM-M2가 배운 것).
    try expect(&cm, K.KEY_W, 1, "w");
    try expect(&cm, K.KEY_B, 1, "b");

    // 검사 15. 모드 안에서는 단어 이동 명령이 된다. **expectCopy는 `.bytes`가
    // 오면 LeakedToPty로 실패하므로**, 이 두 줄이 곧 "PTY로 안 샌다"의
    // 증명이다.
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    try expectCopy(&cm, K.KEY_W, .word_next);
    try expectCopy(&cm, K.KEY_B, .word_prev);

    // **단어 이동은 모드를 안 닫는다.** `y`와 갈리는 자리이고, 안 그러면 `w`를
    // 한 번 누른 뒤의 키가 전부 셸로 샌다.
    if (cm.mode != .copy) {
        std.debug.print("FAIL: a word motion left copy mode\n", .{});
        return error.WordMotionLeftMode;
    }

    // 검사 16. **Shift는 단어 이동을 안 가른다.** vim의 `W`/`B`(WORD 단위)를
    // 만들지 않았으므로(design 결정 2) 대문자도 같은 명령이다. 이것을 적어
    // 두지 않으면 나중에 `W`를 더하는 사람이 "원래 갈려 있었나"를 못 안다.
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_W, .word_next);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");

    try expectCopy(&cm, K.KEY_ESC, .exit);
```

### Step 4: `main.zig`가 컴파일 에러로 배선을 요구하는 것을 확인한다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build 2>&1 | head -30'
```

**기대:** `main.zig`의 copy switch에서 `.word_next`·`.word_prev`가 처리되지
않았다는 에러.

**이것이 결정 6이 말한 "컴파일러가 배선할 자리를 알려준다"의 실물이다.**
에러가 안 나면 그 switch에 `else`가 생긴 것이므로 **그것부터 확인한다** —
`else`가 있으면 앞으로 variant를 더할 때 이 신호를 영영 못 받는다.

### Step 5: `main.zig`에 배선 두 줄을 더한다 (사용자가 편집)

**넣을 것** — `main.zig`의 copy switch에서 다음 네 줄을 찾는다.

```zig
                    .left => try screen.copyMove(-1, 0),
                    .down => try screen.copyMove(0, 1),
                    .up => try screen.copyMove(0, -1),
                    .right => try screen.copyMove(1, 0),
```

**그 뒤에** 아래를 넣는다.

```zig
                    // 단어 이동(CN-M0). copyMove와 형제이고 선택 갱신도 같은
                    // copyApply를 통과한다 — 그래서 여기 배선은 한 줄이다.
                    .word_next => try screen.copyMoveWord(.next),
                    .word_prev => try screen.copyMoveWord(.prev),
```

로그는 따로 더하지 않는다. switch 아래의 `dumpCopy(screen, @tagName(cmd))`가
**이미** `copy> word_next row=… col=…`을 찍는다 — 게이트가 Task 3에서 볼
줄이 그것이다.

### Step 6: 빌드와 호스트 검사를 함께 돌린다 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**둘 다 돌리는 이유가 있다.** `zig build test`만으로는 `readKeys` 쪽 깨짐을
놓친다 — Zig가 참조되지 않는 함수를 분석하지 않아서 `State.scrolls` 필드가
통째로 사라진 것을 **두 번** 놓쳤다(HANDOFF 실측 1). `input_test`는
`handleKey`만 부른다.

**기대:** 빌드가 조용히 끝나고, 검사가 Task 1의 여섯 줄 + Step 3의 새 줄들과
함께 `PASS`.

### Step 7: 커밋 (Claude가 실행)

```bash
git add terminal/src/input.zig terminal/src/input_test.zig terminal/src/main.zig
git commit -m "Bind w and b to word motion in copy mode"
```

---

## Task 3: 게이트가 게스트에서 단어 이동을 본다

**Files:**
- Modify: `copy/check.sh` (검사 13 뒤, NUL 음성 검사 앞)

### Step 1: 검사 14를 더한다 (사용자가 편집)

**넣을 것** — `copy/check.sh`에서 다음 두 줄을 찾는다.

```bash
# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
```

**그 앞에** 아래를 넣는다.

```bash
# ── 검사 14: 단어 단위 이동 (CN-M0) ────────────────────────────────────
#
# **게이트가 보는 것은 둘뿐이다**(CN-M0 plan 결정 3): 키가 게스트까지 도달해
# 커서가 단어 단위로 움직였다는 것과, 그 키가 PTY로 안 샜다는 것이다. 선택이
# 함께 넓어지는 것은 vt_test가 정확한 문자열로 본다 — 여기서 왕복을 보려면
# 기대 문자열을 미리 정확히 적어야 하는데 그 값은 호스트 검사로만 확정된다.
#
# 대상 줄을 새로 만든다. 화면에 이미 있는 줄들은 프롬프트가 섞여 있어서 col
# 값을 미리 셀 수 없다.
#
#   col:  0....4 5 6...9 10 11...15
#         alpha  _ beta  _  gamma
echo "=== typing 'echo alpha beta gamma' ==="
type_keys e c h o spc a l p h a spc b e t a spc g a m m a ret
sleep 3

if ! grep -aqF '| alpha beta gamma |' "$LOG"; then
  report_failure "the shell did not produce a line containing only 'alpha beta gamma'"
fi

echo "=== entering copy mode for the word motions ==="
type_keys meta_l-shift-c
sleep 2

# 출력줄은 프롬프트 바로 위다(CM-M0 실측: 커서는 언제나 맨 아랫줄에서 시작).
type_keys k
sleep 1

# **커서를 col 0으로 확실히 보낸다.** copyMove의 좌우는 줄을 넘나들지 않고
# x를 0에서 멈추므로(vt.zig), h를 충분히 많이 누르면 반드시 col 0이다.
# 프롬프트 길이에 기대지 않는 것이 요점이다 — 그 길이는 fish가 정한다.
for _ in $(seq 1 40); do
  echo "sendkey h" >&3
  sleep 0.05
done
sleep 2
COL_HOME="$(copy_value col)"
if [ "$COL_HOME" -ne 0 ]; then
  report_failure "h did not reach column 0 (col ${COL_HOME})"
fi
ROW_WORD="$(copy_value row)"

# 음성 검사의 기준선. w와 b는 PTY로 나가면 안 된다.
KEYS_BEFORE_WORD="$(key_lines)"

# **판정 1.** w가 공백을 건너뛰어 'beta'의 b(col 6)로 간다. 건너뛰기가 없으면
# 여기서 5가 나온다.
type_keys w
sleep 1
COL_W1="$(copy_value col)"
if [ "$COL_W1" -ne 6 ]; then
  report_failure "w landed at col ${COL_W1} (expected 6, the 'b' of beta)"
fi

# **판정 2.** 한 번 더 누르면 'gamma'의 g(col 11)다.
type_keys w
sleep 1
COL_W2="$(copy_value col)"
if [ "$COL_W2" -ne 11 ]; then
  report_failure "the second w landed at col ${COL_W2} (expected 11)"
fi

# **판정 3.** b가 그것을 정확히 되돌린다.
type_keys b
sleep 1
COL_B1="$(copy_value col)"
if [ "$COL_B1" -ne 6 ]; then
  report_failure "b landed at col ${COL_B1} (expected 6)"
fi

# **판정 4.** 줄을 안 넘었다. 단어 이동은 줄 안의 일이다.
ROW_AFTER_WORD="$(copy_value row)"
if [ "$ROW_AFTER_WORD" -ne "$ROW_WORD" ]; then
  report_failure "the word motions changed rows (${ROW_WORD} -> ${ROW_AFTER_WORD})"
fi

# **판정 5(음성).** 셋 다 PTY로 안 나갔다. 모드 안에서 친 w가 셸에 도착하면
# 입력줄이 더럽혀지고, 그것이 이 기능의 가장 흔한 실패 방식이다.
KEYS_AFTER_WORD="$(key_lines)"
if [ "$KEYS_AFTER_WORD" -ne "$KEYS_BEFORE_WORD" ]; then
  report_failure "the word motions leaked to the PTY (key> ${KEYS_BEFORE_WORD} -> ${KEYS_AFTER_WORD})"
fi
echo "word motions moved the cursor 0 -> 6 -> 11 -> 6 without leaking to the PTY"

type_keys esc
sleep 1
```

### Step 2: `copy` 체인만 한 번 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'bash copy/check.sh' > /tmp/cn-m0-copy.out 2>&1
```

**긴 명령이므로 `run_in_background`로 돌리고 따로 들여다본다.** `| tail -N`을
붙이지 않는다 — `tail`이 파이프가 닫힐 때까지 아무것도 안 내보내서 진행
상황을 볼 수 없다(HANDOFF).

**기대:** 마지막 줄이 `CM-M2 check PASS`이고, 그 앞에

```
word motions moved the cursor 0 -> 6 -> 11 -> 6 without leaking to the PTY
```

**col 값이 다르게 나오면 코드가 아니라 화면을 먼저 의심한다.** fish가 출력줄
앞에 무언가를 붙였거나, `k` 한 번이 출력줄이 아닌 다른 줄에 섰을 수 있다.
그때는 한 번의 `docker run` 안에서 로그를 뒤진다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/gate.out 2>&1
  grep -ah "alpha beta gamma" /tmp/tmp.*
'
```

`grep`에 `-a`를 반드시 붙인다(HANDOFF).

### Step 3: 커밋 (Claude가 실행)

```bash
git add copy/check.sh
git commit -m "Check word motion in the copy chain"
```

---

## Task 4: 루트 게이트와 문서

### Step 1: 루트 게이트를 3/3으로 돌린다 (Claude가 실행, 약 20분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/cn-m0-gate.out 2>&1
```

**`--platform`을 붙이지 않는다**(`project_build_host_arch`).
**`run_in_background`로 돌린다** — 18분 기준선이 Bash 도구의 10분 상한을
넘는다(HANDOFF).

**기대:** 여덟 체인 3/3.

**시간 해석.** 기준선은 **18분 08초**다. 이번에 더한 타이핑은 검사 14의
`echo alpha beta gamma`(22키) + 모드 진입·`k`·`w`·`w`·`b`·`esc`(6키) =
**28키 × 0.3초 ≈ 8.4초**, 여기에 `h` 40번(0.05초 간격 ≈ 2초)과 `sleep` 합
약 10초를 더해 **회차당 약 20초**다. copy 체인은 3회 부팅이므로 **약 1분
증가**를 예상한다.

**하지만 이 게이트의 시간은 ±3분 수준의 잡음을 가진다**(HANDOFF). 1분 증가는
**측정으로 갈리지 않는다.** 그러므로 값을 기록하되 "우리 코드가 1분을 더했다"고
주장하지 않는다. 값이 20분을 크게 넘으면 **코드를 의심하기 전에 기계를 먼저
의심한다** — 이 게이트는 arm64 위에서 `qemu-system-x86_64`를 TCG로 돌리므로
전부 CPU 바운드다.

### Step 2: design doc의 Status를 고친다 (Claude가 편집)

`docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md`의 넷째 줄.

```
**Status:** 설계 확정. CN-M0 미착수
```

를

```
**Status:** 설계 확정. **CN-M0 완료(2026-08-26)**. CN-M1 미착수
```

로 바꾼다.

**HANDOFF가 "design doc 셋의 `Status:` 줄이 낡았다"를 이월 숙제로 들고 있는
이유가 이 한 줄을 매번 빠뜨렸기 때문이다.** 같은 빚을 새로 만들지 않는다.

### Step 3: 기억을 갱신한다 (Claude가 편집)

`docs/decisions/project_copy_mode.md`에 CN-M0 절을 더할지, 새 기억
`project_copy_navigation.md`를 만들지를 **Task 4를 시작할 때 정한다.** 판단
기준은 "CN이 CM과 다른 사실을 만들었는가"이고, 지금 시점의 후보는 셋이다.

1. **라이브러리의 "단어"에 공백 덩어리가 포함된다** — CM은 몰라도 됐던 사실.
2. **`pointFromPin`이 뷰포트 아래쪽 밖을 안 알려준다** — 검색(CN-M1)도 같은
   함수를 쓰므로 다시 밟을 자리다.
3. **`Terminal.ScrollViewport`에 `.pin`이 없고 `Screen.Scroll`에는 있다** —
   HANDOFF의 "이름이 다르다"에 붙는 사례.

셋 다 CM이 아니라 CN의 사실이므로 **새 파일 쪽으로 기운다.** 만들면
`MEMORY.md`에 한 줄을 더한다 — **본문을 색인에 쓰지 않는다.**

### Step 4: `HANDOFF.md`를 갱신한다 (Claude가 편집)

CN-M0이 끝난 상태로 고친다. 최소한 이 넷을 반영한다.

- 제목과 "지금 어디인가"를 **Copy Navigation 진행 중, CN-M1이 다음**으로.
- 게이트 기준선을 Step 1의 실측값으로. **잡음 범위를 함께 적는다.**
- "로그 문구는 두 곳에 중복된다" 목록에 **`terminal: copy> word_next` ·
  `word_prev`**를 더한다.
- 핵심 파일의 `input.zig` 줄 번호가 밀렸으므로 다시 센다. `Copy` enum이 "열
  개로 닫혔다"고 적힌 자리를 **"열둘이고 CN-M1이 union으로 바꾼다"**로 고친다.

### Step 5: 커밋 (Claude가 실행)

```bash
git add docs/superpowers/specs/2026-08-26-tars-copy-navigation-design.md \
        docs/superpowers/plans/2026-08-26-tars-copy-navigation-cn-m0.md \
        docs/decisions/ MEMORY.md HANDOFF.md
git commit -m "Close out CN-M0"
```

**`git add` 전에 `git status`로 `M`과 신규를 가른다**(HANDOFF). 이 저장소는
kernel/init/terminal을 직접 빌드하므로 바이너리 산출물이 계속 생긴다.

---

## 이 plan이 일부러 하지 않는 것

- **`e`·`W`·`B`·`E`** — design 결정 2.
- **`Copy`를 `union(enum)`으로 바꾸기** — design 결정 6. CN-M1의 몫이고,
  payload가 필요해지기 전에 바꾸면 컴파일러의 신호를 미리 써 버린다.
- **`w`가 줄을 넘어 다음 줄의 첫 단어로 가기** — plan 결정 1.
- **단어 경계를 설정으로 빼기** — 바꾸고 싶어 한 사람이 없다.
- **게이트에서 선택 넓히기를 왕복으로 보기** — plan 결정 3. `vt_test`의 검사
  16이 정확한 문자열로 본다.
