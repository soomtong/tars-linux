# TARS Search Position SP-M1 — Implementation Plan

**Date:** 2026-08-30
**Design:** `docs/superpowers/specs/2026-08-29-tars-search-position-design.md`
(결정 5·6·7·8과 위험 1·2·3)
**앞 milestone:** SP-M0(현재 매치 색, 2026-08-29) · 그것이 남긴 숙제는
2026-08-30에 풀었다

**Goal:** 검색 오버레이에 `/needle [3/12]`를 띄워, 지금 보고 있는 매치가
스크롤백 전체에서 몇 번째인지 사람이 알게 만든다.

**Architecture:** CS-M1이 만든 `find_missed` 플래그의 **뜻을 넓혀**
`find_status`("마지막 검색 명령의 결과를 보여 주는 중")로 바꾼다. 켜는 곳은
`findSubmit`·`findNext`·`findPrev` 셋이고, 끄는 곳은 이미 있는 두 자리
(`main.zig`의 copy 명령 직전 · `copyExit`)를 그대로 쓴다. **새 상태도 새 로그도
안 만든다** — `promptText`가 `findMatchCount()`로 "못 찾음"과 번호를 가르고,
`find> overlay text=`가 이미 매 프레임 그 결과를 찍는다.

**Tech Stack:** Zig 0.16 · ghostty-vt(vendored) · QEMU 부팅 게이트(bash)

---

## 왜 이 순서인가

**창구를 먼저 맞추고 화면은 나중이다.** CS-M0의 실측 9("Task를 넷으로 가른
것이 값을 했다")와 같은 규율이다 — Task 2가 `vt.zig`의 값이 맞다는 것을
확인해 주므로, Task 3에서 화면 글자가 틀리면 **의심할 자리가 `promptText`
하나뿐**이다.

| Task | 무엇 | 파일 |
|---|---|---|
| 1 | 플래그를 넓힌다 | `vt.zig` · `main.zig`(호출 이름) · `vt_test.zig`(호출 이름) |
| 2 | 창구가 맞는지 본다 | `vt_test.zig`(검사 41~44) |
| 3 | 오버레이 글자를 만든다 | `main.zig` |
| 4 | 화면에 그렇게 쓰였는지 본다 | `copy/check.sh`(검사 20) |
| 5 | 루트 게이트 | — |

## 착수 전에 실측으로 확정한 것 (2026-08-30)

**전부 `out/probe/serial1.log`(숙제를 풀며 뽑아 둔 copy 체인 로그)에서 읽었고,
짐작이 하나도 없다.**

1. **기존 게이트 검사 넷이 전부 안전하다.** SP-M1이 오버레이를 띄우면
   `dumpStyles`가 `overlaid_row`(맨 아랫줄 46)를 건너뛰는데, 색을 세는 두
   검사의 매치가 거기에 없다.

   | 검사 | 매치가 있는 줄 | 오버레이가 덮는 줄 | 겹치는가 |
   |---|---|---|---|
   | 16(하이라이트) | **0** | 46 | 아니다 |
   | 19(두 색) | **44 · 45** | 46 | 아니다 |

   검사 17은 오버레이를 안 보고, 검사 18은 매치가 0이라 문구가 그대로다.

2. **검사 19가 끝난 자리의 번호는 `[1/4]`다.** 로그가
   `copy> enter row=46 col=11` → `copy> find_submit row=45 col=3`을 찍는다 —
   커서(46)보다 매치(45)가 위라 `above_only`가 첫 매치를 통과시키고, 그래서
   인덱스가 0이다. `find> submit matches=4`이므로 분모가 4다.

3. **`vt_test`의 `ns`·`ns_i`·`nhit`·`ncur`·`nstat`·`nmiss`가 안 쓰였다.**
   `main()` 하나가 파일 전체라 지역 변수가 서로 부딪치고 **Zig가 shadowing을
   컴파일 에러로 막는다.**

4. **`refreshMatches`는 매치가 0이어도 슬라이스를 만든다**(`vt.zig:801`).
   그래서 `findMatchCount()`가 0을 주고, `findMissed()`가 그 0을 조건으로
   쓸 수 있다.

---

## Task 1: 플래그를 넓힌다

**Files:**
- Modify: `terminal/src/vt.zig` (필드 · `findMissed` 둘레 · `findSubmit` ·
  `findNext`/`findPrev` · `copyExit`)
- Modify: `terminal/src/main.zig:685` (호출 이름 하나)
- Modify: `terminal/src/vt_test.zig:1097` (호출 이름 하나)

**이름을 바꾸는 이유.** 뜻이 "못 찾았다"에서 "결과를 보여 주는 중"으로
넓어졌으므로 `find_missed`라는 이름을 두면 **성공한 검색도 켜는데 이름은
실패를 말하는** 상태가 된다. 이 저장소가 반복해서 부딪친 "주석과 코드가
어긋난다"의 같은 종류다.

- [ ] **Step 1: 필드의 이름과 주석을 바꾼다** (`vt.zig:196~207`)

`지울 것`
```zig
    /// 마지막 검색이 아무것도 못 찾았는가(design 결정 9). **오버레이 한 줄에
    /// `/needle: not found`를 쓰는 조건이다.**
    ///
    /// `findSubmit`이 정하고, **`main.zig`가 copy 명령을 처리하기 직전 한
    /// 자리에서 끈다.** 시계를 안 들여오는 이유는 poll 루프가 지금 시각을 안
    /// 보기 때문이고, 다음 키까지 떠 있으면 사람이 메시지를 못 보고 넘길 일도
    /// 없다.
    ///
    /// **메시지에 쓸 글자는 `find_last`에서 온다.** 메시지가 뜰 때는 프롬프트가
    /// 이미 닫혀 있어서 `findNeedle()`이 null을 주기 때문이다 — 결정 8과 9가
    /// 맞물리는 자리가 여기다.
    find_missed: bool = false,
```

`넣을 것`
```zig
    /// 마지막 검색 명령의 결과를 보여 주는 중인가(SP design 결정 5).
    ///
    /// **CS-M1의 `find_missed`를 넓힌 것이다.** 그때는 "못 찾았다"만 뜻했는데,
    /// SP-M1이 성공한 검색에도 `[3/12]`를 띄우면서 두 경우가 같은 수명을 갖게
    /// 됐다. **플래그를 둘로 나누면 켜고 끄는 자리가 두 벌이 되고**, 그중
    /// 하나를 빠뜨리면 증상이 "글자가 화면 아랫줄에 영영 붙어 있다"이다.
    ///
    /// - **켜는 곳**: `findSubmit`·`findNext`·`findPrev` 셋. `refreshMatches()`를
    ///   셋 다에서 부르는 것과 정확히 같은 자리이고 같은 규율이다.
    /// - **끄는 곳**: `main.zig`가 copy 명령을 처리하기 **직전** 한 자리와
    ///   `copyExit`. **새 자리를 안 만든다.**
    ///
    /// 시계를 안 들여오는 이유는 poll 루프가 지금 시각을 안 보기 때문이고,
    /// 다음 키까지 떠 있으면 사람이 글자를 못 보고 넘길 일도 없다.
    ///
    /// **보여 줄 글자는 `find_last`에서 온다.** 결과가 뜰 때는 프롬프트가 이미
    /// 닫혀 있어서 `findNeedle()`이 null을 주기 때문이다 — CS design 결정 8과
    /// 9가 맞물리는 자리가 여기다.
    find_status: bool = false,
```

- [ ] **Step 2: 창구 셋을 만든다** (`vt.zig:635~655`)

`지울 것`
```zig
    /// 못 찾은 검색어. **메시지가 꺼져 있으면 null이다**(design 결정 9).
    ///
    /// `findNeedle`과 짝이다 — 그쪽은 "지금 치고 있는 것", 이쪽은 "방금 못 찾은
    /// 것"이고, 오버레이 한 줄을 두 갈래로 가르는 것이 이 둘이다.
    ///
    /// **`main.zig`가 `find_last`를 직접 읽지 않게 하려고 함수로 낸다** —
    /// `findNeedle`·`clipboard`·`copyCursor`와 같은 규율이다.
    pub fn findMissed(self: *const Screen) ?[]const u8 {
        if (!self.find_missed) return null;
        return self.find_last[0..self.find_last_len];
    }

    /// "못 찾았다" 메시지를 끈다. **`main.zig`가 copy 명령을 처리하기 직전
    /// 한 자리에서 부른다**(design 결정 9).
    ///
    /// 끄는 것이 명령 처리보다 **앞**이라, 새로 실패한 검색의 메시지는
    /// `findSubmit`이 그 뒤에 다시 켜서 살아남는다. 순서 하나로 "다음 키에
    /// 사라진다"와 "새로 실패하면 다시 뜬다"가 함께 나온다(plan 결정 2).
    pub fn findClearMissed(self: *Screen) void {
        self.find_missed = false;
    }
```

`넣을 것`
```zig
    /// 결과를 보여 주는 중인 검색어. **상태가 꺼져 있으면 null이다.**
    ///
    /// `findNeedle`과 짝이다 — 그쪽은 "지금 치고 있는 것", 이쪽은 "방금 검색한
    /// 것"이고, 오버레이 한 줄을 가르는 것이 이 둘이다.
    ///
    /// **`main.zig`가 `find_last`를 직접 읽지 않게 하려고 함수로 낸다** —
    /// `findNeedle`·`clipboard`·`copyCursor`와 같은 규율이다.
    pub fn findStatusNeedle(self: *const Screen) ?[]const u8 {
        if (!self.find_status) return null;
        return self.find_last[0..self.find_last_len];
    }

    /// 못 찾은 검색어. **상태가 켜져 있고 매치가 하나도 없을 때만 준다.**
    ///
    /// **CS-M1이 만든 계약을 새 플래그 위에서 그대로 낸다**(SP design 결정 5).
    /// 그때는 `find_missed`가 "실패했다"를 직접 뜻했는데, 지금은 "결과를 보여
    /// 주는 중"과 "매치가 0"이라는 **두 사실을 여기서 곱한다.** 그래서
    /// `vt_test`의 검사 34·35·36이 한 글자도 안 바뀐 채 통과한다.
    ///
    /// **`promptText`의 두 갈래를 가르는 것이 `findMatchCount()` 하나**라는
    /// 뜻이기도 하다 — 검사 44가 그것을 못 박는다.
    pub fn findMissed(self: *const Screen) ?[]const u8 {
        const n = self.findStatusNeedle() orelse return null;
        if (self.findMatchCount() != 0) return null;
        return n;
    }

    /// 결과 표시를 끈다. **`main.zig`가 copy 명령을 처리하기 직전 한 자리에서
    /// 부른다**(SP design 결정 7).
    ///
    /// 끄는 것이 명령 처리보다 **앞**이라, 새 검색의 결과는 `findSubmit`·
    /// `findNext`·`findPrev`가 그 뒤에 다시 켜서 살아남는다. 순서 하나로
    /// "다음 키에 사라진다"와 "새로 검색하면 다시 뜬다"가 함께 나온다.
    pub fn findClearStatus(self: *Screen) void {
        self.find_status = false;
    }
```

- [ ] **Step 3: `findSubmit`이 조건 없이 켜게 한다** (`vt.zig`, `findSubmit`의 끝)

`지울 것`
```zig
        const count = self.find.?.matchesLen();
        // **켜기만 하지 않고 매번 값을 정한다**(CS-M1 plan 결정 1). design은
        // "0이면 켠다"라고 적었는데, 그대로 하면 끄는 자리가 `main.zig` 하나뿐이
        // 되어 **성공한 검색이 앞의 실패를 안 지우는 경로**가 생긴다. poll 루프를
        // 안 거치는 호출자(`vt_test`)가 그렇다.
        //
        // 켜는 자리와 끄는 자리를 안 가르는 것이 요점이고, CS-M0이
        // `refreshMatches`를 셋 다에서 부른 것과 같은 규율이다.
        self.find_missed = count == 0;
        return .{ .matches = count, .moved = moved };
```

`넣을 것`
```zig
        const count = self.find.?.matchesLen();
        // **결과 표시를 켠다**(SP design 결정 5). CS-M1은 여기서
        // `find_missed = count == 0`으로 **실패일 때만** 켰는데, SP-M1이 성공한
        // 검색에도 `[3/12]`를 띄우면서 그 조건이 사라졌다 — 성공이든 실패든
        // "방금 검색했다"는 같고, **무엇을 보여 줄지는 `promptText`가
        // `findMatchCount()`로 가른다.**
        //
        // 조건이 없어진 것이 CS-M1보다 오히려 안전하다. 그때 조건을 붙여야
        // 했던 이유는 **성공한 검색이 앞의 실패를 안 지우는 경로**를 막기
        // 위해서였는데(poll 루프를 안 거치는 `vt_test`), 지금은 성공도 켜므로
        // 그 경로가 아예 없다.
        self.find_status = true;
        return .{ .matches = count, .moved = moved };
```

- [ ] **Step 4: `findNext`/`findPrev`도 켜게 한다** (`vt.zig`)

`지울 것`
```zig
    pub fn findNext(self: *Screen) !bool {
        const moved = try self.findStep(.next, false);
        try self.refreshMatches();
        return moved;
    }

    /// `N`. 목록의 이전(미래 방향) 매치로.
    pub fn findPrev(self: *Screen) !bool {
        const moved = try self.findStep(.prev, false);
        try self.refreshMatches();
        return moved;
    }
```

`넣을 것`
```zig
    pub fn findNext(self: *Screen) !bool {
        const moved = try self.findStep(.next, false);
        try self.refreshMatches();
        // **검색이 살아 있을 때만 켠다**(SP design 결정 5). 모드에 들어와 `/`
        // 없이 `n`을 누르면 보여 줄 것이 없다. **`moved`로 판단하면 안 된다** —
        // 매치가 하나뿐이라 안 움직인 경우에도 false가 나오는데, 그때는 번호를
        // 보여 주는 것이 맞다.
        if (self.find != null) self.find_status = true;
        return moved;
    }

    /// `N`. 목록의 이전(미래 방향) 매치로.
    pub fn findPrev(self: *Screen) !bool {
        const moved = try self.findStep(.prev, false);
        try self.refreshMatches();
        if (self.find != null) self.find_status = true;
        return moved;
    }
```

- [ ] **Step 5: `copyExit`의 한 줄** (`vt.zig`, `copyExit` 안)

`지울 것`
```zig
        // "못 찾았다" 메시지도 끈다(design 결정 9). 안 끄면 모드를 나간 뒤에도
        // 화면 아랫줄에 메시지가 남는다.
```

`넣을 것`
```zig
        // 결과 표시도 끈다(CS design 결정 9 · SP design 결정 5). 안 끄면 모드를
        // 나간 뒤에도 화면 아랫줄에 글자가 남는다. **"못 찾았다"와 `[3/12]`가
        // 같은 플래그를 쓰므로 이 한 줄이 둘 다 끈다.**
```

`지울 것`
```zig
        self.find_missed = false;
```

`넣을 것`
```zig
        self.find_status = false;
```

- [ ] **Step 6: 부르는 쪽 두 자리의 이름을 맞춘다**

`main.zig:685` — `지울 것`
```zig
                screen.findClearMissed();
```

`넣을 것`
```zig
                screen.findClearStatus();
```

`vt_test.zig:1097`(검사 35 안) — `지울 것`
```zig
    ls.findClearMissed();
```

`넣을 것`
```zig
    ls.findClearStatus();
```

- [ ] **Step 7: 빌드와 기존 검사**

**`zig build`를 함께 돌린다.** Zig가 참조되지 않는 함수를 분석하지 않아서
`zig build test`만으로는 `main.zig`의 실수를 못 잡는다(HANDOFF의 실측 1).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

기대: **`PASS`**. 검사 32~40이 전부 그대로 통과해야 한다. 특히 **검사 34·35·36이
`findMissed()`를 그대로 보고 있으므로**, 여기서 깨지면 Step 2의 곱셈이 틀린
것이다.

- [ ] **Step 8: 커밋**

```bash
git add terminal/src/vt.zig terminal/src/main.zig terminal/src/vt_test.zig
git commit -m "Widen the find flag to cover a successful search"
```

---

## Task 2: 창구가 맞는지 본다

**Files:**
- Modify: `terminal/src/vt_test.zig` (검사 40 뒤, `PASS` 앞)

**`promptText`는 여기서 못 부른다** — `main.zig`의 private 함수다. 그래서 이
파일은 **번호의 재료**(`findCurrentIndex()`와 `findMatchCount()`)를 보고,
글자 자체는 Task 4의 게이트가 본다.

- [ ] **Step 1: 새 화면과 검사 넷을 넣는다**

`vt_test.zig`의 검사 40이 끝난 자리, `std.debug.print("PASS\n", .{});` **앞**에
넣는다.

```zig
    // ── SP-M1: 결과 표시 ────────────────────────────────────────────────
    //
    // **자기 화면을 새로 만든다.** `hs`(CS-M0)·`ls`(CS-M1)와 같은 20x5에 같은
    // 8·18번 줄을 표적으로 두는 것은 게으름이 아니라 **기대값(`matches=2`)을
    // 옮겨 쓰기 위한 것이다.**
    //
    // 이름이 `ns`인 이유: `main()` 하나가 파일 전체라 이 파일의 모든 지역
    // 변수가 서로 부딪치고 Zig가 shadowing을 컴파일 에러로 막는다.
    // `cm`·`painted`·`pruned`·`wm`·`fm`·`fs`·`hs`·`ls`·`ps`가 이미 쓰여 있다.
    const ns = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer ns.deinit();
    var ns_i: usize = 1;
    while (ns_i <= 20) : (ns_i += 1) {
        if (ns_i == 8 or ns_i == 18) {
            ns.feed("xxTARGETxx\r\n");
        } else {
            ns.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{ns_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다.
    _ = try ns.cells(&buf);
    ns.copyEnter();

    // 검사 41. **성공한 검색이 결과 표시를 켜고, 그것은 "못 찾음"이 아니다.**
    //
    // CS-M1에서는 성공한 검색이 플래그를 **껐다.** SP-M1이 그것을 뒤집으므로
    // 여기가 그 변경의 자리다 — `findStatusNeedle()`은 needle을 주고
    // `findMissed()`는 null이어야 한다. **둘이 같은 플래그 위에 서 있으면서도
    // 서로 다른 답을 내는 것이 결정 5의 요점이다.**
    ns.findOpen();
    for ("TARGET") |ch| ns.findChar(ch);
    const nhit = try ns.findSubmit();
    if (nhit.matches != 2) {
        std.debug.print("FAIL: /TARGET found {d} match(es) (expected 2)\n", .{nhit.matches});
        return error.StatusSetupWrong;
    }
    const nneedle = ns.findStatusNeedle() orelse {
        std.debug.print("FAIL: findStatusNeedle() was null after a search found matches\n", .{});
        return error.StatusFlagNotSet;
    };
    if (!std.mem.eql(u8, nneedle, "TARGET")) {
        std.debug.print("FAIL: findStatusNeedle() gave '{s}' (expected 'TARGET')\n", .{nneedle});
        return error.StatusNeedleWrong;
    }
    if (ns.findMissed() != null) {
        std.debug.print("FAIL: findMissed() was set after a search that found matches\n", .{});
        return error.MissedSetOnSuccess;
    }
    std.debug.print("vt_test: 성공한 검색이 결과 표시를 켠다 OK (needle={s})\n", .{nneedle});

    // 검사 42. **번호의 재료가 맞고 `n`이 그것을 하나 올린다.**
    //
    // `promptText`가 쓰는 값이 정확히 이 둘이다 — `findCurrentIndex() + 1`과
    // `findMatchCount()`. **그 함수는 `main.zig`의 private이라 여기서 못
    // 부르므로**, 재료를 보는 것이 이 파일이 할 수 있는 전부이고 글자 자체는
    // 게이트의 `find> overlay text=`가 본다.
    //
    // 검사 37·38이 `idx`만 보았고 이 검사가 **분모까지** 함께 본다. 분모는
    // 스냅숏에서 오므로(`findMatchCount`), 그것이 `matchesLen()`과 어긋나면
    // `[3/12]`의 뒤 숫자가 조용히 틀린다.
    if (ns.findMatchCount() != 2) {
        std.debug.print("FAIL: findMatchCount()={d} (expected 2)\n", .{ns.findMatchCount()});
        return error.StatusTotalWrong;
    }
    const nidx = ns.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index right after the search\n", .{});
        return error.StatusIndexMissing;
    };
    if (nidx != 0) {
        std.debug.print("FAIL: the first match has index {d} (expected 0)\n", .{nidx});
        return error.StatusIndexWrong;
    }
    if (!try ns.findNext()) {
        std.debug.print("FAIL: n did not move to another match\n", .{});
        return error.StatusIndexNoMove;
    }
    const nidx2 = ns.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index after n\n", .{});
        return error.StatusIndexMissing;
    };
    if (nidx2 != 1 or ns.findMatchCount() != 2) {
        std.debug.print("FAIL: after n the numbers are [{d}/{d}] (expected [2/2])\n", .{
            nidx2 + 1, ns.findMatchCount(),
        });
        return error.StatusIndexWrong;
    }
    std.debug.print("vt_test: 번호가 [{d}/{d}]로 간다 OK\n", .{ nidx2 + 1, ns.findMatchCount() });

    // 검사 43. **끄면 사라지고 `n`이 다시 켠다.**
    //
    // 결정 7의 수명이 이것이다 — 다음 키에 사라지고, 그 키가 검색 키면 다시
    // 뜬다. `main.zig`가 `switch`보다 **앞**에서 끄기 때문에 그 순서가 나온다.
    // **여기서는 그 순서를 손으로 흉내 낸다** — poll 루프를 안 거치기 때문이다.
    ns.findClearStatus();
    if (ns.findStatusNeedle() != null) {
        std.debug.print("FAIL: findClearStatus() did not turn the status off\n", .{});
        return error.StatusNotCleared;
    }
    if (!try ns.findNext()) {
        std.debug.print("FAIL: the second n did not move\n", .{});
        return error.StatusIndexNoMove;
    }
    if (ns.findStatusNeedle() == null) {
        std.debug.print("FAIL: n did not turn the status back on\n", .{});
        return error.StatusNotReset;
    }
    std.debug.print("vt_test: 끄면 사라지고 n이 다시 켠다 OK\n", .{});

    // 검사 44. **매치가 없으면 번호가 아니라 "못 찾음"이다**(design 위험 1).
    //
    // 같은 플래그가 켜져 있는데 `findMissed()`가 needle을 주고
    // `findCurrentIndex()`는 null이며 `hlSpans()`는 비어 있다 — **`promptText`의
    // 두 갈래를 가르는 것이 `findMatchCount()` 하나**라는 것을 여기서 못 박는다.
    ns.findOpen();
    for ("NOPE") |ch| ns.findChar(ch);
    const nhit2 = try ns.findSubmit();
    if (nhit2.matches != 0) {
        std.debug.print("FAIL: /NOPE found {d} match(es) (expected none)\n", .{nhit2.matches});
        return error.StatusMissSetupWrong;
    }
    const nmiss = ns.findMissed() orelse {
        std.debug.print("FAIL: findMissed() was null after a search found nothing\n", .{});
        return error.StatusMissNotSet;
    };
    if (!std.mem.eql(u8, nmiss, "NOPE")) {
        std.debug.print("FAIL: findMissed() gave '{s}' (expected 'NOPE')\n", .{nmiss});
        return error.StatusMissNeedleWrong;
    }
    if (ns.findCurrentIndex() != null) {
        std.debug.print("FAIL: there is a current index with no matches\n", .{});
        return error.StatusIndexOnEmpty;
    }
    _ = try ns.cells(&buf);
    if (ns.hlSpans().len != 0) {
        std.debug.print("FAIL: {d} span(s) painted with no matches\n", .{ns.hlSpans().len});
        return error.StatusSpansOnEmpty;
    }
    std.debug.print("vt_test: 매치가 없으면 번호가 아니라 못 찾음이다 OK (needle={s})\n", .{nmiss});
```

- [ ] **Step 2: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

기대: 검사 41~44의 네 줄이 새로 나오고 마지막이 **`PASS`**다.

```
vt_test: 성공한 검색이 결과 표시를 켠다 OK (needle=TARGET)
vt_test: 번호가 [2/2]로 간다 OK
vt_test: 끄면 사라지고 n이 다시 켠다 OK
vt_test: 매치가 없으면 번호가 아니라 못 찾음이다 OK (needle=NOPE)
PASS
```

- [ ] **Step 3: 커밋**

```bash
git add terminal/src/vt_test.zig
git commit -m "Check the numbers behind the match position"
```

---

## Task 3: 오버레이 글자를 만든다

**Files:**
- Modify: `terminal/src/main.zig` (`promptText`와 그 주석 · `prompt_buf`)

- [ ] **Step 1: `promptText`를 세 갈래로 만든다** (`main.zig:177~205`)

`지울 것`
```zig
/// 오버레이 한 줄에 쓸 글자를 정한다. **프롬프트가 우선이고, 닫혀 있으면
/// "못 찾았다" 메시지다**(design 결정 9). 둘 다 없으면 null이고, 그러면
/// 오버레이를 아예 안 그린다.
///
/// **`drawPrompt`는 이것을 모른다.** 그리는 함수는 "한 줄을 준 색으로 쓴다"
/// 하나만 알고, 무엇을 쓸지는 여기서 끝난다 — CN-M1이 앞의 `/`를 `vt.zig`가
/// 아니라 `main.zig`에서 붙인 것과 같은 경계다(모양은 여기가 정한다).
///
/// **프롬프트를 먼저 보는 것에 뜻이 있다.** 못 찾은 뒤에 `/`를 다시 열면 사람이
/// 지금 치고 있는 것이 화면에 나와야 한다. 순서를 뒤집으면 새 검색어를 치는
/// 동안 지난 실패 메시지가 화면에 남는다.
///
/// `buf`는 최소 **140바이트**여야 한다: `/` 하나 + needle 128 + `: not found`
/// 열하나.
fn promptText(screen: *vt.Screen, buf: []u8) ?[]const u8 {
    const MISS = ": not found";
    if (screen.findNeedle()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        return buf[0 .. 1 + n.len];
    }
    if (screen.findMissed()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        @memcpy(buf[1 + n.len ..][0..MISS.len], MISS);
        return buf[0 .. 1 + n.len + MISS.len];
    }
    return null;
}
```

`넣을 것`
```zig
/// 오버레이 한 줄에 쓸 글자를 정한다. **갈래가 셋이다**(SP design 결정 7).
///
/// ```
/// 프롬프트가 열려 있다        → /needle
/// 닫혀 있고 상태가 켜져 있다  → 매치 0이면  /needle: not found
///                               아니면      /needle [3/12]
/// 그 밖                       → null (오버레이를 아예 안 그린다)
/// ```
///
/// **`drawPrompt`는 이것을 모른다.** 그리는 함수는 "한 줄을 준 색으로 쓴다"
/// 하나만 알고, 무엇을 쓸지는 여기서 끝난다 — CN-M1이 앞의 `/`를 `vt.zig`가
/// 아니라 `main.zig`에서 붙인 것과 같은 경계다(모양은 여기가 정한다).
///
/// **프롬프트를 먼저 보는 것에 뜻이 있다.** 검색을 마친 뒤에 `/`를 다시 열면
/// 사람이 지금 치고 있는 것이 화면에 나와야 한다. 순서를 뒤집으면 새 검색어를
/// 치는 동안 지난 결과가 화면에 남는다.
///
/// **두 갈래를 가르는 것은 `findMatchCount()` 하나다.** `find_status`는 "방금
/// 검색했다"만 말하고 성패를 모른다 — `vt_test`의 검사 44가 그 갈림을 본다.
///
/// **번호는 라이브러리가 준 값을 그대로 쓴다**(결정 6). `idx + 1`이고
/// `total - idx`로 뒤집지 않는다 — 뒤집으면 off-by-one이 들어갈 자리가 하나
/// 생기고, 그 증상은 "번호가 하나씩 어긋난다"라 조용하다.
///
/// **`findCurrentIndex()`가 null이면 번호를 안 붙이고 needle만 쓴다**
/// (design 위험 1). 매치는 있는데 선택이 없는 경로이고, 그때 0이나 1을
/// 지어내면 사람이 커서와 어긋난 번호를 보게 된다.
///
/// `buf`는 최소 **173바이트**여야 한다: `/` 하나 + needle 128 + ` [` 둘 +
/// 숫자 20 + `/` 하나 + 숫자 20 + `]` 하나. `usize`가 최대 스무 자리다.
fn promptText(screen: *vt.Screen, buf: []u8) ?[]const u8 {
    const MISS = ": not found";
    if (screen.findNeedle()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        return buf[0 .. 1 + n.len];
    }

    const n = screen.findStatusNeedle() orelse return null;
    buf[0] = '/';
    @memcpy(buf[1 .. 1 + n.len], n);
    const len = 1 + n.len;

    const total = screen.findMatchCount();
    if (total == 0) {
        @memcpy(buf[len..][0..MISS.len], MISS);
        return buf[0 .. len + MISS.len];
    }

    const idx = screen.findCurrentIndex() orelse return buf[0..len];
    // **`bufPrint`가 실패하면 needle만 남긴다.** 위의 산수대로면 일어나지
    // 않지만, 버퍼 크기를 누가 줄였을 때 증상이 panic이 되지 않게 막는다.
    const tail = std.fmt.bufPrint(buf[len..], " [{d}/{d}]", .{ idx + 1, total }) catch
        return buf[0..len];
    return buf[0 .. len + tail.len];
}
```

- [ ] **Step 2: 버퍼를 173바이트로 늘린다** (`main.zig:820~822`)

`지울 것`
```zig
        // 버퍼가 needle보다 **열두 칸** 크다. 앞의 `/` 하나와 뒤의
        // `: not found` 열하나 때문이다(CS-M1).
        var prompt_buf: [140]u8 = undefined;
```

`넣을 것`
```zig
        // 버퍼가 needle보다 **마흔다섯 칸** 크다. 앞의 `/` 하나와, 뒤에 올 수
        // 있는 것 중 **긴 쪽**인 ` [20/20]` 마흔넷 때문이다(SP-M1). `usize`가
        // 최대 스무 자리라 숫자 둘이 마흔이고, ` [`·`/`·`]`가 넷이다.
        // `: not found` 열하나는 그보다 짧으므로 이 크기가 둘 다 덮는다.
        var prompt_buf: [173]u8 = undefined;
```

- [ ] **Step 3: 빌드와 검사**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

기대: **`PASS`**. 이 Task는 `vt_test`가 안 보는 자리를 고치므로 검사 결과가
Task 2와 같아야 한다 — **달라지면 그 자체가 신호다.**

- [ ] **Step 4: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Number the current match on the overlay line"
```

---

## Task 4: 화면에 그렇게 쓰였는지 본다

**Files:**
- Modify: `copy/check.sh` (검사 19 뒤, NUL 음성 검사 앞)

**검사 19가 끝난 자리를 그대로 쓴다**(design 결정 9). copy mode가 살아 있고
`/zq`의 매치 넷도 살아 있다 — **새 부팅도 새 검색도 없고 키는 둘뿐이다.**

- [ ] **Step 1: 검사 20을 넣는다**

`copy/check.sh`의 `echo "both match colours reached the framebuffer ..."` 줄
**바로 뒤**, `# ── 음성 검사: 로그에 NUL이 ...` **앞**에 넣는다.

```bash
# ── 검사 20: 현재 매치의 번호가 오버레이에 뜬다 (SP-M1) ────────────────
#
# **검사 19가 끝난 자리를 그대로 쓴다**(design 결정 9). copy mode가 살아 있고
# `/zq`의 매치 넷도 살아 있다 — 새 부팅도 새 검색도 없다.
#
# **오버레이는 `screen>`에도 `style>`에도 안 나온다**(CN-M1 design 결정 7,
# main.zig의 `overlaid_row`). 그래서 `find> overlay` 한 줄이 유일한 관측
# 수단이고, CS-M1이 그 용도로 만들었다 — **SP-M1은 새 로그를 하나도 안 더한다**
# (design 결정 8).
#
# **`[1/4]`인 것에 산수가 있다.** `zq`가 명령줄과 출력줄에 둘씩이라 넷이고,
# `/`는 가장 최근 매치에 서므로 인덱스가 0이다(`vt_test`의 검사 37이 그 뜻을
# 고정했다). 번호는 `idx + 1`이므로 1이다(design 결정 6).
#
# **커서가 매치보다 아래에 있는 것을 확인했다**(2026-08-30 실측). 로그가
# `copy> enter row=46` → `copy> find_submit row=45`를 찍으므로 `above_only`가
# 첫 매치를 건너뛰지 않는다 — 건너뛰면 인덱스가 1이 되어 `[2/4]`가 뜬다.
if [ "$(last_frame | grep -acF 'terminal: find> overlay text=/zq [1/4]' || true)" -eq 0 ]; then
  echo "--- overlay lines ---"
  grep -a 'terminal: find> overlay' "$LOG" | tail -n 5
  report_failure "the overlay did not number the current match as [1/4]"
fi
echo "the overlay numbered the current match: /zq [1/4]"

# **판정.** `n`이 번호를 하나 올린다.
#
# 앞 줄이 "번호가 뜬다"를 보고 이 줄이 **"그 번호가 커서를 따라간다"**를 본다.
# 하나만 보면 안 된다 — 고정된 숫자를 찍는 코드도 앞 줄을 통과한다.
type_keys n
sleep 2
if [ "$(last_frame | grep -acF 'terminal: find> overlay text=/zq [2/4]' || true)" -eq 0 ]; then
  echo "--- overlay lines ---"
  grep -a 'terminal: find> overlay' "$LOG" | tail -n 5
  report_failure "n did not move the number to [2/4]"
fi
echo "n moved the number to [2/4]"

# **판정(음성).** 다음 키 하나에 번호가 사라진다(design 결정 7).
#
# 검사 18이 "못 찾음" 쪽에 대해 같은 것을 보는데, **SP-M1 뒤로 둘이 같은
# 플래그를 쓰므로** 번호 쪽에서도 본다. 플래그를 넓히면서 끄는 자리를 빠뜨리면
# 증상이 **"번호가 화면 아랫줄에 영영 붙어 있다"**이고, 사람에게는 "터미널이
# 고장 났다"로 보인다.
#
# `k`는 copy 커서를 한 칸 올릴 뿐이라 화면의 다른 것을 안 건드린다.
type_keys k
sleep 2
if [ "$(last_frame | grep -ac 'terminal: find> overlay' || true)" -ne 0 ]; then
  echo "--- last frame overlay lines ---"
  last_frame | grep -a 'terminal: find> overlay'
  report_failure "the match number survived the next key"
fi
echo "the next key cleared the match number"
```

- [ ] **Step 2: 문법을 먼저 본다**

```bash
bash -n copy/check.sh && echo "syntax OK"
```

- [ ] **Step 3: copy 체인 단독으로 돌린다 — 8분 걸린다**

`run_in_background`로 돌린다. 로그를 함께 빼내면 실패했을 때 다시 안 돌려도
된다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/gate.out 2>&1; rc=$?
  mkdir -p /workspace/out/probe
  cp /tmp/gate.out /workspace/out/probe/gate.out
  for f in /tmp/tmp.*; do
    [ -f "$f" ] && gzip -c "$f" > /workspace/out/probe/serial.log.gz
  done
  echo "rc=$rc"
'
```

기대: `rc=0`이고 아래 세 줄이 나온다.

```
the overlay numbered the current match: /zq [1/4]
n moved the number to [2/4]
the next key cleared the match number
```

**검사 16과 19도 그대로 통과해야 한다.** 오버레이가 새로 뜨면서
`dumpStyles`가 맨 아랫줄(46)을 건너뛰는데, 착수 전 실측대로면 두 검사의
매치가 0번과 44·45번 줄이라 안 겹친다. **거기서 깨지면 그 실측이 틀린
것이므로, 고치기 전에 `style>` 줄의 행 번호를 먼저 읽는다.**

- [ ] **Step 4: 커밋**

```bash
git add copy/check.sh
git commit -m "Check that the overlay numbers the current match"
```

---

## Task 5: 루트 게이트

- [ ] **Step 1: 여덟 체인을 돌린다 — 16분 걸린다**

`run_in_background`로 돌리고 시간을 함께 잰다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
```

`--platform`을 붙이지 않는다(`project_build_host_arch`).

기대: 여덟 체인 **3/3**. 기준선은 SP-M0 뒤의 **16분 30초~45초**다.

**값이 크게 벗어나면 코드를 의심하기 전에 기계를 먼저 의심한다** — 이 게이트의
잡음은 ±3분이고, TR-M2 때 8배가 나온 원인은 Chrome의 영상 재생이었다.

- [ ] **Step 2: 세 번 재서 기준선을 갱신한다**

SP-M1이 더한 것은 키 둘(`n`·`k`)과 `sleep` 4초, 체인당 세 회차이므로
`4×3 + 2×0.135×3 ≈ 13초`다. **잡음보다 훨씬 작으므로 "늘었다"를 증명할 수
없고, 확인만 한다.**

- [ ] **Step 3: 문서와 기억을 갱신하고 닫는다**

- `docs/superpowers/specs/2026-08-29-tars-search-position-design.md`의
  `Status:`를 **SP-M1 완료**로
- `docs/decisions/project_search_position.md`에 SP-M1이 실행으로 증명한 것
- `HANDOFF.md`의 "copy mode가 지금 할 수 있는 것" 표에 번호 한 줄, 이월
  숙제에서 SP-M1을 끝난 숙제로, **핵심 파일의 줄 번호를 다시 재서**
- `MEMORY.md`는 색인이므로 새 파일이 없으면 안 건드린다

```bash
git add -A docs HANDOFF.md
git commit -m "Close out SP-M1"
```

---

## 이 plan이 미리 답해 둔 것

**1. 기존 게이트 검사가 안 깨진다** — 착수 전 실측 1·2에 표로 있다. 짐작이
아니라 `out/probe/serial1.log`에서 읽은 행 번호다.

**2. `vt_test`의 검사 34·35·36이 안 바뀐다** — `findMissed()`의 계약을 그대로
두고 구현만 곱셈으로 바꾸기 때문이다. Task 1 Step 7이 그것을 바로 확인한다.

**3. "못 찾음" 문구를 안 바꾼다** — 게이트의 검사 18이
`find> overlay text=/zzz: not found`를 **글자 그대로** 비교한다(design 위험 3).

**4. 새 로그도 새 체인도 없다** — `find> overlay`가 CS-M1부터 매 프레임
오버레이 내용을 찍고 있다. monitor 포트 45462는 계속 비어 있다.

## 위험과 그것을 볼 자리

| 위험 | 증상 | 보는 자리 |
|---|---|---|
| 켜는 자리를 하나 빠뜨린다 | `n` 뒤에 번호가 안 뜬다 | 검사 43 · 게이트의 `[2/4]` |
| 끄는 자리를 놓친다 | 번호가 화면에 붙어 있다 | 검사 20의 음성 판정 |
| `idx`와 분모가 다른 순간의 것 | 번호가 조용히 어긋난다 | 검사 42가 둘을 함께 본다 |
| 매치 0인데 번호를 그린다 | `[1/0]` | 검사 44 · 게이트의 검사 18 |
| 오버레이가 매치 색을 가린다 | 검사 16·19가 깨진다 | 착수 전 실측 1(안 겹친다) |
