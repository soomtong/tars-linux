# TARS Copy Search Feedback CS-M0 Implementation Plan

> **협업 방식(이 저장소 규칙):** 구현 파일 편집은 **사용자**가 한다. 각 Step의
> "넣을 것"/"지울 것"을 그대로 넣으면 된다. 빌드·검사·QEMU·게이트 실행과
> git commit은 **Claude**가 한다.

**Goal:** copy mode에서 검색한 뒤 **화면에 보이는 모든 매치를 어두운 앰버 바탕으로
칠한다.** 지금은 커서가 옮겨지는 것 말고 아무 신호도 없다.

**Design doc:** `docs/superpowers/specs/2026-08-28-tars-copy-search-feedback-design.md`

**Architecture:** `ScreenSearch`가 이미 가진 매치 목록을 `findSubmit`에서 한 번
받아 두고, `cells()`가 매 프레임 그것을 **행별 범위**로 풀어 `bg`를 정한다. 좌표를
푸는 방향이 이 milestone의 핵심이다 — 매치마다 `pointFromPin`을 부르는 대신 뷰포트가
덮는 page node를 한 번만 훑고 매치 쪽은 비교만 한다.

**Tech Stack:** Zig 0.16, libghostty-vt(`search.Screen`, `highlight.Flattened`,
`PageList`), QEMU monitor

---

## 이 milestone은 CN-M1보다 작다

**키를 하나도 안 더한다.** `input.zig`도 `input_test.zig`도 안 건드린다 — 검색은
CN-M1이 이미 다 만들었고 우리는 그 결과를 **그리기만** 한다. HANDOFF의 "서브프로젝트를
넘어 유효한 실측" 1·2·3이 말하는 함정(`Action`/`Keys`/`Copy`를 건드릴 때의 것들)이
이번에는 통째로 해당되지 않는다.

**게이트에 타이핑을 한 키도 안 더한다.** 검사 16은 검사 15가 끝난 자리를 그대로
쓴다 — copy mode가 살아 있고 `/findme`의 매치 목록도 살아 있다. 게이트 증가분이
거의 없어야 한다는 뜻이고, 그것이 위험 4에 대한 답이다.

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

### design doc이 소스에서 확인해 둔 것

design doc의 "착수 전 조사로 확정한 사실" 표 열 줄이 전부 여기 해당한다. 특히
이 넷을 다시 확인하지 않는다.

**1. `ScreenSearch.matches(alloc)`이 매치 전부를 준다**(`search/screen.zig:234`).
최신→오래된 순이고, **`@memcpy`로 구조체만 옮기는 얕은 복사**다.

**2. `Flattened`는 node를 역참조하지 않고 훑기 위한 표현이다**(`highlight.zig:107`).
`chunks`가 `{node, serial, start, end}`를 들고 `top_x`/`bot_x`가 양 끝 x다.

**3. `pointFromPin`은 앞으로 훑는다**(`PageList.zig:5614~5645`). 뷰포트 위에 있는
pin은 목록 끝까지 훑은 뒤에야 null이다. `Pin.before`의 주석이 "very expensive...
should not be called in performance critical paths"라고 직접 적어 두었다.

**4. `ghostty_vt`가 `highlight`와 `PageList`를 내보낸다**(`lib_vt.zig:47`·`:66`).
그래서 `ghostty_vt.highlight.Flattened`와 `ghostty_vt.PageList.List.Node`를 필드
타입으로 쓸 수 있다.

### 이 plan을 쓰면서 우리 소스에서 확인한 것 다섯

**1. `Node.rows()`가 있다**(`PageList.zig:214`, `size.CellCountInt` = u16을
돌려준다). `pointFromPin` 자신이 `tl.node.rows()`로 쓴다.

**2. `Node.serial`이 있다**(`PageList.zig:52`). 주석이 "pointer stability is not
guaranteed, but the serial"이라고 명시한다.

**3. `copyPlace`는 뷰포트 위의 매치를 화면 맨 윗줄로 올린다**(`vt.zig:748`,
`s.scroll(.{ .pin = pin })`). 그래서 **검색 직후 매치는 언제나 viewport row 0**이다.

**4. `dumpStyles`의 상한은 프레임당 16줄이다**(`main.zig:207`의
`STYLE_DUMP_LIMIT`). 넘으면 `N more cell(s) not shown`을 찍는다 — 조용히 자르지
않는다. **게이트가 셀 색을 셀 때 이 상한을 넘지 않게 짜야 한다.**

**5. `vt_test`의 `buf`는 `[100]vt.CellGlyph`이고 `line`은 `[32]u8`이다**
(`vt_test.zig:24`·`:154`). 20x5 화면이 정확히 100셀이라 새 검사도 그 크기를 쓴다.

**6. `hs`·`hl_i`·`hhit`는 `vt_test.zig`에서 아직 안 쓰인 이름이다.** `main()` 하나가
파일 전체라 지역 변수 이름이 서로 부딪치고, Zig는 shadowing을 컴파일 에러로
막는다. **새 이름을 더 쓸 일이 생기면 `rg`로 먼저 확인한다.**

## 이번에 정하는 것 넷 (design doc이 안 정한 자리)

### 결정 1. `vt.Screen`이 `io`를 들고 있는다

design 결정 5가 `us=`를 찍으라고 했는데 `cells()`에는 `io`가 없다. `Screen.init`이
`io`를 받아 `Terminal.init`에 넘기고 버린다(`vt.zig:121`).

**필드로 저장한다.** 대안은 `cells()`에 인자를 더하는 것인데, 그러면 `vt_test`의
호출부 열댓 곳이 전부 바뀐다 — 이 milestone과 무관한 diff가 그만큼 생긴다.
`Terminal`이 이미 같은 값을 들고 있으므로 새로운 종류의 의존도 아니다.

### 결정 2. `find> hl` 줄은 검색이 살아 있는 매 프레임 찍는다

"바뀔 때만 찍는다"는 상태를 하나 더 만들고, 그 판정이 틀리면 증상이 "로그가 안
나온다"라 조사하기 나쁘다. copy mode의 프레임은 키를 누를 때만 생기므로 줄 수가
많지 않고, `style>`는 이미 **매 프레임 최대 16줄**을 찍는다.

`hlStats()`가 `find == null`이면 null을 주므로, 검색이 없을 때는 한 줄도 안 찍힌다.

### 결정 3. 검사는 `find> hl`과 `style>` 두 겹으로 본다

`find> hl`은 `vt.zig`가 센 값이고 `style>`는 그 색이 정말 셀에 닿았는지다. 한 겹만
보면 "셌지만 안 칠했다"를 못 잡는다 — TR design 결정 7이 `style>`/`pixel>`를 두 겹으로
둔 것과 같은 규율이고, HD-M2가 잡은 "조용한 실패"와 같은 종류의 구멍이다.

### 결정 4. 게이트의 음성 검사는 `Esc` 뒤에 둔다

검사 15가 이미 끝에서 `type_keys esc`를 친다. **그 자리에서 하이라이트가 사라졌는지
본다** — `copyExit`이 `find_matches`를 안 버렸다면 여기서 잡히고, 그 상태는 다음
검색에서 이중 해제로 이어진다. 새 타이핑이 한 키도 안 든다.

---

## Task 1: 매치 목록을 보관한다 (아직 아무것도 안 칠한다)

**Files:**
- Modify: `terminal/src/vt.zig` (필드 하나, `deinit`, `copyExit`, `findSubmit`,
  접근자 하나)
- Modify: `terminal/src/vt_test.zig` (검사 26·27)

**이 Task는 화면을 하나도 안 바꾼다.** 목록을 받아 두고, 두 번 검색해도 안 깨지는
것만 확인한다. 이중 해제가 이 milestone에서 가장 조용한 실패 방식이라 **가장 먼저
막는다.**

### Step 1: 필드를 더한다 (사용자가 편집)

**넣을 것** — `terminal/src/vt.zig`의 `find: ?ghostty_vt.search.Screen = null,`
(`:118`) **바로 다음 줄**, 즉 `pub fn init(` 앞이다.

```zig

    /// 확정된 검색의 매치 **전부**. `findSubmit`이 만들고 `copyExit`이 버린다.
    ///
    /// **`ScreenSearch.matches()`가 주는 것은 얕은 복사다**
    /// (`search/screen.zig:234`가 `@memcpy`로 구조체만 옮긴다). 각 `Flattened`의
    /// `chunks`는 ScreenSearch 내부 버퍼를 그대로 가리키므로, **원소를
    /// `deinit`하면 이중 해제**다. `alloc.free(slice)` 하나만 부른다
    /// (design 결정 6).
    ///
    /// `find`와 **언제나 나란히** 다룬다 — 한쪽만 남은 상태를 만들지 않는다.
    /// 해제 자리가 셋이고 `find`의 것과 정확히 같다: `findSubmit`의 옛것 정리 ·
    /// `copyExit` · `deinit`.
    ///
    /// 왜 `find`에게 매번 물어보지 않고 슬라이스를 들고 있는가: `matches()`가
    /// 부를 때마다 할당한다. 매 프레임 부르는 자리(`cells`)가 생기므로 한 번만
    /// 받아 둔다. **목록은 `searchAll()` 시점의 스냅숏이고 갱신하지 않는다**
    /// (design 결정 7).
    find_matches: ?[]ghostty_vt.highlight.Flattened = null,
```

### Step 2: `deinit`에서 해제한다 (사용자가 편집)

**지울 것** — `terminal/src/vt.zig:176`.

```zig
        if (self.find) |*f| f.deinit();
```

**넣을 것**

```zig
        if (self.find) |*f| f.deinit();
        // **바깥 슬라이스만 해제한다**(design 결정 6). 원소의 `chunks`는 위
        // `f.deinit()`이 이미 해제한 버퍼를 가리키는 얕은 복사다.
        if (self.find_matches) |m| alloc.free(m);
```

### Step 3: `copyExit`에서 해제한다 (사용자가 편집)

**지울 것** — `terminal/src/vt.zig:377-378`.

```zig
        if (self.find) |*f| f.deinit();
        self.find = null;
```

**넣을 것**

```zig
        if (self.find) |*f| f.deinit();
        self.find = null;
        // 매치 목록도 같은 자리에서 버린다(design 결정 6). **바깥 슬라이스만**
        // 해제한다 — 원소는 방금 `f.deinit()`이 해제한 버퍼를 가리킨다.
        if (self.find_matches) |m| self.alloc.free(m);
        self.find_matches = null;
```

### Step 4: `findSubmit`이 목록을 받아 둔다 (사용자가 편집)

**편집 ①** — 옛것 정리. **지울 것**은 `terminal/src/vt.zig:457-458`이다.

```zig
        if (self.find) |*old| old.deinit();
        self.find = null;
```

**넣을 것**

```zig
        if (self.find) |*old| old.deinit();
        self.find = null;
        if (self.find_matches) |m| self.alloc.free(m);
        self.find_matches = null;
```

**편집 ②** — 새 목록 받기. **지울 것**은 `terminal/src/vt.zig:476` 한 줄이다.

```zig
        self.find = fresh;
```

**넣을 것**

```zig
        // **매치 목록을 지금 한 번만 받는다**(design 결정 2·6). `self.find`에
        // 옮기기 **전에** 부르는 것에 뜻이 있다 — 여기서 실패하면 위의
        // `errdefer fresh.deinit()`이 온전한 상태를 정리하고, `self.find`는
        // 아직 아무것도 안 가리킨다.
        //
        // 슬라이스의 원소는 `fresh` 내부 버퍼를 가리키는 얕은 복사인데, 아래에서
        // `fresh`를 **값으로** 옮겨도 그 버퍼는 힙에 그대로 있으므로 유효하다.
        const found = try fresh.matches(self.alloc);
        errdefer self.alloc.free(found);

        self.find = fresh;
        self.find_matches = found;
```

**편집 ③** — 접근자. **넣을 것**은 `findSubmit`의 닫는 `}` **바로 다음**, 즉
`findNext` 선언 앞이다.

```zig

    /// 보관 중인 매치가 몇 개인가. 검색이 없으면 0이다.
    ///
    /// **`matchesLen()`과 언제나 같아야 한다.** 다르면 슬라이스가 낡은 것이고,
    /// 그것은 곧 `find`와 `find_matches`가 따로 놀았다는 뜻이다. 검사 26이 이
    /// 등식을 본다.
    pub fn findMatchCount(self: *const Screen) usize {
        const m = self.find_matches orelse return 0;
        return m.len;
    }
```

### Step 5: 빌드가 지나가는지 본다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 조용히 끝나고 `vt_test`가 **CN-M1까지와 글자 하나 다르지 않은 PASS**를
낸다. 이 Task는 아직 아무 동작도 안 바꾼다.

**`zig build`와 `zig build test`를 함께 도는 이유**는 HANDOFF의 실측 1이다 —
Zig가 참조되지 않는 함수를 분석하지 않아서 `zig build test`만으로는 `main.zig`가
깨진 것을 두 번 놓쳤다. 이번에 `main.zig`를 안 건드리더라도 습관을 지킨다.

### Step 6: 검사 26·27을 더한다 (사용자가 편집)

**넣을 것** — `terminal/src/vt_test.zig`에서 `std.debug.print("PASS\n", .{});`
**바로 앞**이다.

```zig

    // ── CS-M0: 매치 하이라이트 ────────────────────────────────────────────
    //
    // **새 화면을 만든다.** 앞의 `fs`는 20x5에 60줄을 먹였고 검사 22~25가 그
    // 커서 자리에 기대고 있다 — 남의 화면에 붙이면 앞 검사가 흔들린다.
    // CM-M1이 `cm`, CM-M2가 `pruned`, CN-M0이 `wm`, CN-M1이 `fm`·`fs`를 새로
    // 만든 것과 같은 규율이다.
    //
    // 표적을 **두 줄**(8번·18번)에 심는다. 5줄짜리 화면이라 한 번에 하나만
    // 보이고, 그래서 "화면에 보이는 것만 칠한다"를 검사가 가를 수 있다.
    const hs = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer hs.deinit();
    var hl_i: usize = 1;
    while (hl_i <= 20) : (hl_i += 1) {
        if (hl_i == 8 or hl_i == 18) {
            hs.feed("xxTARGETxx\r\n");
        } else {
            hs.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{hl_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다(HANDOFF의 "시도했으나
    // 안 되는 접근").
    _ = try hs.cells(&buf);
    hs.copyEnter();

    // 검사 26. 보관한 매치 수가 검색이 찾은 수와 같다.
    hs.findOpen();
    for ("TARGET") |ch| hs.findChar(ch);
    const hhit = try hs.findSubmit();
    if (hhit.matches == 0) {
        std.debug.print("FAIL: /TARGET found nothing\n", .{});
        return error.HighlightSearchFoundNothing;
    }
    if (hs.findMatchCount() != hhit.matches) {
        std.debug.print("FAIL: kept {d} match(es) but the search found {d}\n", .{
            hs.findMatchCount(), hhit.matches,
        });
        return error.FindMatchSliceWrong;
    }
    std.debug.print("vt_test: 매치 목록을 그대로 보관한다 OK (matches={d})\n", .{hhit.matches});

    // 검사 27. **다시 검색해도 앞 목록이 이중 해제되지 않는다.**
    //
    // `matches()`가 주는 것은 얕은 복사라(design 결정 6), 원소를 `deinit`하면
    // ScreenSearch가 같은 버퍼를 다시 해제한다. 그 실수는 **두 번째 검색에서**
    // 터진다 — 첫 검색만 하는 검사로는 영영 안 잡힌다.
    hs.findOpen();
    for ("R1") |ch| hs.findChar(ch);
    const hhit2 = try hs.findSubmit();
    if (hs.findMatchCount() != hhit2.matches) {
        std.debug.print("FAIL: after re-searching, kept {d} but found {d}\n", .{
            hs.findMatchCount(), hhit2.matches,
        });
        return error.FindMatchSliceStale;
    }
    std.debug.print("vt_test: 다시 검색해도 매치 목록이 온전하다 OK (matches={d})\n", .{hhit2.matches});

    // 아래 검사들이 볼 수 있게 목록을 TARGET으로 되돌린다.
    hs.findOpen();
    for ("TARGET") |ch| hs.findChar(ch);
    _ = try hs.findSubmit();
```

### Step 7: 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 새 줄 둘이 나오고 `PASS`로 끝난다.

```
vt_test: 매치 목록을 그대로 보관한다 OK (matches=2)
vt_test: 다시 검색해도 매치 목록이 온전하다 OK (matches=...)
PASS
```

**`matches=2`가 아니면 그 숫자를 먼저 읽는다.** `TARGET`을 두 줄에 심었으므로 2가
기대값이다 — CN-M1의 게이트에서 `echo findme`가 **두 줄**을 남겨 4가 나온 것과 달리,
여기는 셸이 없어 되비추는 줄이 없다. 다르게 나오면 **plan이 아니라 실측이 답이다**.

**크래시가 나면 그것이 곧 Step 4의 편집 ②를 잘못 넣었다는 뜻이다** — `errdefer`나
해제 자리 셋 중 하나가 빠졌다.

### Step 8: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Keep the search match list alongside the search"
```

---

## Task 2: 화면에 보이는 매치를 행별 범위로 푼다 (아직 안 칠한다)

**Files:**
- Modify: `terminal/src/vt.zig` (`io` 필드, `RowSpan`/`HlStats`, `hl_spans`,
  `findSpans`, 접근자 둘, `cells`의 첫 줄)
- Modify: `terminal/src/vt_test.zig` (검사 28)

**색은 다음 Task다.** 좌표 계산과 색 결정을 나누는 이유는 CN-M1의 실측 8과 같다 —
한꺼번에 넣으면 "좌표를 잘못 풀었다"와 "색을 잘못 넣었다"를 가르는 데 빌드 한 바퀴가
든다.

### Step 1: `io`를 필드로 들고 있는다 (사용자가 편집)

**편집 ①** — **넣을 것**은 `terminal/src/vt.zig:37`의
`alloc: std.mem.Allocator,` **바로 다음 줄**이다.

```zig
    /// 시간을 재기 위해 들고 있는다(CS-M0 plan 결정 1). `init`이 `Terminal`에
    /// 넘기고 버리던 값이다.
    ///
    /// `cells()`에 인자로 넘기지 않는 이유는 그 호출부가 `vt_test`에만 열댓 곳
    /// 있기 때문이다 — 이 milestone과 무관한 diff가 그만큼 생긴다.
    io: std.Io,
```

**편집 ②** — **넣을 것**은 `terminal/src/vt.zig:128`의 `.alloc = alloc,`
**바로 다음 줄**이다.

```zig
            .io = io,
```

### Step 2: 타입 둘과 버퍼를 더한다 (사용자가 편집)

**넣을 것** — Task 1에서 넣은 `find_matches` 선언 **바로 다음 줄**이다.

```zig

    /// 매치 하이라이트의 행별 범위 하나. **양 끝을 포함한다** — 라이브러리가
    /// `row_sels`로 주는 선택 범위와 같은 규약이다(design 결정 4).
    pub const RowSpan = struct {
        row: u16,
        x0: u16,
        x1: u16,

        fn lessThan(_: void, a: RowSpan, b: RowSpan) bool {
            if (a.row != b.row) return a.row < b.row;
            return a.x0 < b.x0;
        }
    };

    /// 마지막 `cells()`가 만든 하이라이트의 실측(design 결정 5).
    ///
    /// **상한을 안 두기로 한 결정의 근거를 남기는 값이다.** `us`가 밀리초 단위로
    /// 커지면 그때 상한을 논의한다.
    pub const HlStats = struct { spans: usize, cells: usize, us: i64 };

    /// 하이라이트의 행별 범위. **매 `cells()`가 다시 만든다.**
    ///
    /// 매치 목록은 스냅숏이지만(design 결정 7) 좌표는 아니다 — 뷰포트가 움직이면
    /// 같은 매치가 다른 행에 온다. 버퍼를 들고 있는 이유는 프레임마다 새로
    /// 할당하지 않기 위해서다(`clearRetainingCapacity`).
    hl_spans: std.ArrayListUnmanaged(RowSpan) = .empty,
    hl_stats: HlStats = .{ .spans = 0, .cells = 0, .us = 0 },
```

### Step 3: `deinit`에서 버퍼를 해제한다 (사용자가 편집)

**지울 것** — Task 1의 Step 2에서 만든 두 줄이다.

```zig
        if (self.find) |*f| f.deinit();
        // **바깥 슬라이스만 해제한다**(design 결정 6). 원소의 `chunks`는 위
        // `f.deinit()`이 이미 해제한 버퍼를 가리키는 얕은 복사다.
        if (self.find_matches) |m| alloc.free(m);
```

**넣을 것**

```zig
        if (self.find) |*f| f.deinit();
        // **바깥 슬라이스만 해제한다**(design 결정 6). 원소의 `chunks`는 위
        // `f.deinit()`이 이미 해제한 버퍼를 가리키는 얕은 복사다.
        if (self.find_matches) |m| alloc.free(m);
        self.hl_spans.deinit(alloc);
```

### Step 4: `copyExit`이 범위도 비운다 (사용자가 편집)

**넣을 것** — Task 1의 Step 3에서 넣은 `self.find_matches = null;` **바로 다음
줄**이다.

```zig
        // 좌표도 함께 비운다. 안 비우면 모드를 나간 프레임에 지난 범위가 한 번
        // 더 칠해진다 — 게이트의 음성 검사(plan 결정 4)가 그것을 본다.
        self.hl_spans.clearRetainingCapacity();
```

### Step 5: `findSpans`를 더한다 (사용자가 편집)

**넣을 것** — Task 1에서 넣은 `findMatchCount` 함수의 닫는 `}` **바로 다음**이다.

```zig

    /// 화면에 보이는 매치를 행별 범위로 푼다. **`cells()`가 매 프레임 부른다.**
    ///
    /// **매치마다 `pointFromPin`을 부르지 않는다**(design 결정 3). 그 함수는
    /// 뷰포트 top-left에서 `node.next`를 따라 앞으로 훑고, 뷰포트보다 **위**에
    /// 있는 pin은 목록 끝까지 훑은 뒤에야 null이 된다 — copy mode에서 매치
    /// 대부분이 거기 있다. 라이브러리도 `Pin.before`에 "very expensive... should
    /// not be called in performance critical paths"라고 적어 두었고 `isBetween`도
    /// 같은 성질이라, 싼 pin 순서 비교는 애초에 없다.
    ///
    /// 그래서 방향을 뒤집는다. 뷰포트가 덮는 page node를 **한 번만** 훑고, 매치
    /// 쪽은 `chunks`가 이미 든 `{node, serial, start, end}`와 비교만 한다.
    /// 뷰포트가 걸치는 node는 보통 한두 개다.
    ///
    /// **매치 쪽 node 포인터를 역참조하는 자리가 이 함수에 없다**(design 위험 2).
    /// 비교에만 쓴다 — 가지치기된 페이지를 읽지 않기 위해서이고, `Flattened`가
    /// 그런 모양인 이유가 정확히 그것이다(`highlight.zig:107`). `serial`까지
    /// 비교하는 것은 주소가 재사용된 경우를 거르기 위해서다.
    fn findSpans(self: *Screen) !void {
        self.hl_spans.clearRetainingCapacity();
        self.hl_stats = .{ .spans = 0, .cells = 0, .us = 0 };

        const matches = self.find_matches orelse return;
        const pages = &self.term.screens.active.pages;
        const rows = pages.rows;
        const cols = pages.cols;
        // **격자를 `state`가 아니라 `pages`에서 읽는다**(CM-M1이 `copyMove`에서
        // 고친 것과 같다). `state`는 마지막 `cells()`의 스냅숏이라 첫 프레임에
        // 0이고, 그러면 이 함수가 조용히 아무 일도 안 한다.
        if (rows == 0 or cols == 0) return;

        const t0 = std.Io.Clock.now(.awake, self.io);

        const tl = pages.getTopLeft(.viewport);
        // `row0`은 지금 노드의 첫 보이는 행이 화면 몇 번째 행인가,
        // `y`는 지금 노드에서 몇 번째 행부터 보이는가다.
        var row0: u16 = 0;
        var y: u16 = tl.y;
        var node_: ?*ghostty_vt.PageList.List.Node = tl.node;
        while (node_) |node| : (node_ = node.next) {
            if (row0 >= rows) break;
            const take = @min(node.rows() - y, rows - row0);

            for (matches) |m| {
                const chunks = m.chunks.slice();
                if (chunks.len == 0) continue;
                const c_nodes = chunks.items(.node);
                const c_serials = chunks.items(.serial);
                const c_starts = chunks.items(.start);
                const c_ends = chunks.items(.end);
                for (0..chunks.len) |ci| {
                    // **역참조가 아니라 비교다.** `c_nodes[ci]`가 가리키는
                    // 메모리를 읽지 않는다 — 그것이 가지치기된 페이지일 수 있다.
                    if (c_nodes[ci] != node) continue;
                    if (c_serials[ci] != node.serial) continue;

                    // `end`는 제외다(`endPin`이 `ends[last] - 1`을 쓴다).
                    var ry = @max(c_starts[ci], y);
                    const ry_end = @min(c_ends[ci], y + take);
                    while (ry < ry_end) : (ry += 1) {
                        // 첫 행만 `top_x`에서 시작하고 끝 행만 `bot_x`에서
                        // 끝난다. soft wrap으로 여러 줄이 된 매치의 가운데
                        // 줄은 줄 전체다.
                        const is_first = ci == 0 and ry == c_starts[0];
                        const is_last = ci == chunks.len - 1 and
                            ry == c_ends[chunks.len - 1] - 1;
                        try self.hl_spans.append(self.alloc, .{
                            .row = row0 + (ry - y),
                            .x0 = if (is_first) m.top_x else 0,
                            .x1 = if (is_last) m.bot_x else cols - 1,
                        });
                    }
                }
            }

            row0 += take;
            y = 0;
        }

        // **`cells()`가 커서 하나로 따라갈 수 있게 정렬한다**(design 결정 4).
        // 노드 사이는 이미 오름차순이지만 한 노드 안에서는 매치가 최신→오래된
        // 순, 곧 행 내림차순으로 들어온다.
        std.mem.sort(RowSpan, self.hl_spans.items, {}, RowSpan.lessThan);

        var painted: usize = 0;
        for (self.hl_spans.items) |sp| painted += @as(usize, sp.x1 - sp.x0) + 1;
        self.hl_stats = .{
            .spans = self.hl_spans.items.len,
            .cells = painted,
            .us = @intCast(@divTrunc(t0.untilNow(self.io, .awake).nanoseconds, 1000)),
        };
    }

    /// 마지막 `cells()`가 만든 하이라이트의 실측. **검색이 없으면 null이다** —
    /// `main.zig`가 이 null로 "찍을 것이 없다"를 판정한다(plan 결정 2).
    pub fn hlStats(self: *const Screen) ?HlStats {
        if (self.find == null) return null;
        return self.hl_stats;
    }

    /// 하이라이트의 행별 범위. **검사가 좌표를 직접 보는 창구다.**
    ///
    /// `main.zig`는 이것을 안 쓴다 — 색은 `cells()`가 이미 해소해서 넘긴다
    /// (TR design 결정 1).
    pub fn hlSpans(self: *const Screen) []const RowSpan {
        return self.hl_spans.items;
    }
```

### Step 6: `cells()`가 매 프레임 부른다 (사용자가 편집)

**지울 것** — `terminal/src/vt.zig`의 `cells()` 첫 두 줄 뒤, 즉
`try self.state.update(self.alloc, &self.term);` **다음 빈 줄**이다. 아래 줄을
찾는다.

```zig
        try self.state.update(self.alloc, &self.term);

        const colors = &self.state.colors;
```

**넣을 것**

```zig
        try self.state.update(self.alloc, &self.term);

        // 매치 하이라이트의 좌표를 먼저 푼다(CS-M0). 검색이 없으면 곧바로
        // 돌아온다.
        try self.findSpans();

        const colors = &self.state.colors;
```

### Step 7: 검사 28을 더한다 (사용자가 편집)

**넣을 것** — Task 1의 Step 6에서 넣은 마지막 줄(`_ = try hs.findSubmit();`)
**바로 다음**이다.

```zig

    // 검사 28. **화면에 보이는 매치 하나만 범위가 된다.**
    //
    // `copyPlace`가 뷰포트 위의 매치를 화면 맨 윗줄로 올리므로(`vt.zig:748`)
    // `/`가 끝난 자리에서 매치는 언제나 row 0이다. 표적을 두 줄에 심었지만
    // 화면이 5줄이라 한 번에 하나만 보인다 — 그것이 이 검사의 요점이다.
    //
    // **`cells()`를 부르고 나서 본다.** 범위는 그 안에서 만들어진다.
    _ = try hs.cells(&buf);
    const hspans = hs.hlSpans();
    if (hspans.len != 1) {
        std.debug.print("FAIL: {d} span(s) in view (expected 1)\n", .{hspans.len});
        for (hspans) |sp| {
            std.debug.print("  span row={d} x0={d} x1={d}\n", .{ sp.row, sp.x0, sp.x1 });
        }
        return error.HighlightSpanCountWrong;
    }
    // `xxTARGETxx`에서 TARGET은 x=2..7이다.
    if (hspans[0].row != 0 or hspans[0].x0 != 2 or hspans[0].x1 != 7) {
        std.debug.print("FAIL: span is row={d} x0={d} x1={d} (expected 0,2,7)\n", .{
            hspans[0].row, hspans[0].x0, hspans[0].x1,
        });
        return error.HighlightSpanWrong;
    }
    const hstats = hs.hlStats() orelse {
        std.debug.print("FAIL: hlStats() was null while a search was live\n", .{});
        return error.HighlightStatsMissing;
    };
    if (hstats.cells != 6) {
        std.debug.print("FAIL: highlight covered {d} cell(s) (expected 6)\n", .{hstats.cells});
        return error.HighlightCellCountWrong;
    }
    std.debug.print("vt_test: 보이는 매치만 범위가 된다 OK (spans={d} cells={d})\n", .{
        hstats.spans, hstats.cells,
    });
```

### Step 8: 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 새 줄 하나가 더 나오고 `PASS`로 끝난다.

```
vt_test: 보이는 매치만 범위가 된다 OK (spans=1 cells=6)
```

**타입 에러가 나면 `@intCast`의 대상부터 본다.** `nanoseconds`의 정수 폭이 Zig
버전에 딸린 값이라 `HlStats.us`의 `i64`가 안 맞을 수 있다 — 컴파일러가 정확한
타입을 짚어 주므로 그것으로 맞춘다.

**`spans=2`가 나오면 뷰포트 판정이 틀린 것이다.** 5줄 화면에 8번과 18번 줄이 함께
보일 수 없다. `take` 계산이나 `row0 >= rows` 탈출을 다시 본다.

### Step 9: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Resolve visible matches into per-row spans"
```

---

## Task 3: `cells()`가 매치의 바탕색을 정한다

**Files:**
- Modify: `terminal/src/vt.zig` (상수 하나, `cells`의 행 루프와 셀 루프)
- Modify: `terminal/src/vt_test.zig` (검사 29·30·31)

**이 Task가 화면을 바꾸는 유일한 자리다.**

### Step 1: 색 상수를 더한다 (사용자가 편집)

**넣을 것** — `terminal/src/vt.zig:20`의 `fn packRgb(` **바로 앞**이다(파일 위쪽,
`Screen` 선언 밖).

```zig
/// 매치 하이라이트의 바탕색(design 결정 1). **맞바꿈이 아니라 값이다.**
///
/// 배경 `#102030`과도 반전된 흰색과도 멀어야 사람이 넷을 가릴 수 있고, 색이
/// **하나**여야 게이트가 `style>` 줄에서 셀 수 있다. 어두운 앰버를 골랐다.
///
/// | 상태 | 바탕 | 글자 |
/// |---|---|---|
/// | 기본 | `#102030` | 흰색 |
/// | 선택 | 흰색 | `#102030` |
/// | 매치 | `#705000` | 흰색 |
/// | 선택 안의 매치 | 흰색 | `#705000` |
///
/// 상수가 `main.zig`가 아니라 여기 있는 이유는 색을 확정하는 것이 이 파일의
/// 일이기 때문이다(TR design 결정 1). `pub`인 것은 `vt_test`가 본다.
pub const MATCH_BG: u32 = 0x00705000;

```

### Step 2: 행 루프가 범위를 잘라 준다 (사용자가 편집)

**지울 것** — `cells()`의 행 루프 첫 줄. 지금은 이렇다.

```zig
        for (0..self.state.rows) |y| {
            const cells_slice = row_cells[y].slice();
```

**넣을 것**

```zig
        // 정렬된 범위 목록을 **앞으로만** 미는 커서다(design 결정 4). 셀마다
        // 목록을 훑지 않으므로 전체가 O(범위 수)다.
        const spans = self.hl_spans.items;
        var hl_at: usize = 0;

        for (0..self.state.rows) |y| {
            // `@as(usize, ...)`는 이 파일의 기존 규율이다 — 바로 아래 선택
            // 범위를 보는 자리가 `x >= @as(usize, range[0])`로 쓴다.
            while (hl_at < spans.len and
                @as(usize, spans[hl_at].row) < y) : (hl_at += 1)
            {}
            var hl_end = hl_at;
            while (hl_end < spans.len and
                @as(usize, spans[hl_end].row) == y) : (hl_end += 1)
            {}
            const row_spans = spans[hl_at..hl_end];

            const cells_slice = row_cells[y].slice();
```

### Step 3: 셀 루프가 바탕색을 정한다 (사용자가 편집)

**넣을 것** — `cells()`의 셀 루프에서 inverse를 푸는 블록이 닫힌 **바로 다음**,
선택을 보는 `if (row_sels[y]) |range| {` **바로 앞**이다. 아래 두 줄 사이다.

```zig
                    if (st.flags.inverse) std.mem.swap(u32, &fg, &bg);
                }

                // ← 여기
                // 선택 영역도 inverse·커서와 **같은 연산**이다(design 결정 6).
```

넣을 코드:

```zig
                // 매치 하이라이트(CS-M0 design 결정 1). **맞바꿈이 아니라 값을
                // 정한다.** 맞바꿈이면 선택 안의 매치가 아래에서 두 번 뒤집혀
                // 원래 색으로 돌아와 안 보이고, 반전된 띠가 선택인지 매치인지
                // 사람도 게이트도 못 가른다.
                //
                // **inverse 뒤·선택 앞이 이 층의 자리다.** inverse는 셀이 원래
                // 가진 성질이라 매치가 덮어써야 하고, 선택과 커서는 사람이 지금
                // 하는 동작이라 매치 **위에** 얹혀야 한다.
                //
                // **`fg`는 안 건드린다** — 매치가 원래 무슨 색 글자였는지를
                // 지우지 않기 위해서다. 그래서 이 층은 한 줄로 말할 수 있다:
                // "매치는 바탕만 정한다".
                for (row_spans) |sp| {
                    if (x >= @as(usize, sp.x0) and x <= @as(usize, sp.x1)) {
                        bg = MATCH_BG;
                        break;
                    }
                }

```

### Step 4: 검사 29·30·31을 더한다 (사용자가 편집)

**넣을 것** — Task 2의 Step 7에서 넣은 마지막 `std.debug.print` **바로 다음**이다.

```zig

    // 검사 29. **매치 셀의 바탕이 MATCH_BG다.**
    //
    // 범위를 옳게 풀고도 색을 안 넣을 수 있다 — 검사 28과 이 검사가 그 둘을
    // 가른다.
    var hcnt: usize = 0;
    for (try hs.cells(&buf)) |c| {
        if (c.bg != vt.MATCH_BG) continue;
        hcnt += 1;
        if (c.row != 0 or c.col < 2 or c.col > 7) {
            std.debug.print("FAIL: painted a cell outside the match at {d},{d}\n", .{
                c.row, c.col,
            });
            return error.HighlightPaintedWrongCell;
        }
    }
    if (hcnt != 6) {
        std.debug.print("FAIL: {d} cell(s) got the match background (expected 6)\n", .{hcnt});
        return error.HighlightPaintCountWrong;
    }
    std.debug.print("vt_test: 매치 셀의 바탕이 MATCH_BG다 OK (cells={d})\n", .{hcnt});

    // 검사 30. **선택 안의 매치는 맞바뀌어 여전히 갈린다.**
    //
    // 매치를 맞바꿈으로 만들었다면 여기서 두 번 뒤집혀 기본 색으로 돌아왔을
    // 것이고, 이 검사가 그것을 잡는다. 커서가 매치의 첫 칸에 서 있으므로
    // (`copyPlace`가 `top_x`로 옮긴다) **그 한 칸은 또 한 번 맞바뀐다** — 그래서
    // 뒤집힌 매치 셀은 여섯이 아니라 다섯이다.
    try hs.copySelect(.line);
    var hswapped: usize = 0;
    for (try hs.cells(&buf)) |c| {
        if (c.fg == vt.MATCH_BG and c.bg != vt.MATCH_BG) hswapped += 1;
    }
    if (hswapped != 5) {
        std.debug.print("FAIL: {d} match cell(s) survived the selection (expected 5)\n", .{
            hswapped,
        });
        return error.HighlightUnderSelectionWrong;
    }
    std.debug.print("vt_test: 선택 안의 매치가 맞바뀌어 남는다 OK (cells={d})\n", .{hswapped});

    // 검사 31. **copy mode를 나가면 하이라이트가 사라진다.**
    //
    // `copyExit`이 `find_matches`를 안 버리면 여기서 잡힌다. 게이트의 음성
    // 검사(plan 결정 4)와 같은 것을 보지만, 이쪽이 훨씬 빨리 실패를 알려준다.
    hs.copyExit();
    var hleft: usize = 0;
    for (try hs.cells(&buf)) |c| {
        if (c.bg == vt.MATCH_BG or c.fg == vt.MATCH_BG) hleft += 1;
    }
    if (hleft != 0) {
        std.debug.print("FAIL: {d} highlighted cell(s) survived copyExit\n", .{hleft});
        return error.HighlightSurvivedExit;
    }
    if (hs.hlStats() != null) {
        std.debug.print("FAIL: hlStats() was not null after copyExit\n", .{});
        return error.HighlightStatsSurvivedExit;
    }
    std.debug.print("vt_test: copy mode를 나가면 하이라이트가 사라진다 OK\n", .{});
```

### Step 5: 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 새 줄 셋이 더 나오고 `PASS`로 끝난다.

```
vt_test: 매치 셀의 바탕이 MATCH_BG다 OK (cells=6)
vt_test: 선택 안의 매치가 맞바뀌어 남는다 OK (cells=5)
vt_test: copy mode를 나가면 하이라이트가 사라진다 OK
```

**검사 30이 6으로 나오면 커서가 매치 위에 없다는 뜻이다.** 그 경우 기대값이
틀린 것이지 코드가 틀린 것이 아닐 수 있다 — `copy> ` 좌표를 찍어 확인하고
**실측을 따른다**(CN-M1 Task 6에서 `matches=2`가 실제로는 4였던 것과 같은 종류다).

### Step 6: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Paint search matches with a distinct background"
```

---

## Task 4: 하이라이트의 실측을 로그로 낸다

**Files:**
- Modify: `terminal/src/main.zig` (`dumpHighlight` 추가, `poll` 루프에서 호출)

**게이트가 볼 창구를 만드는 Task다.** `style>`는 프레임당 16줄이 상한이라
(`STYLE_DUMP_LIMIT`) 셀 수를 그것만으로 세면 잘릴 수 있다. 이 줄은 상한이 없다.

### Step 1: `dumpHighlight`를 더한다 (사용자가 편집)

**넣을 것** — `terminal/src/main.zig`의 `dumpFind` 함수가 닫히는 `}` **바로
다음**이다(`:374` 근처, `dumpClip`의 주석 앞).

```zig

/// 매치 하이라이트가 이 프레임에 무엇을 칠했는지(design 결정 5).
///
/// **상한을 안 두기로 한 결정의 근거를 남기는 줄이다.** `us=`가 밀리초 단위로
/// 커지면 그때 상한을 논의한다. `style>`는 프레임당 16줄이 상한이라 셀 수를
/// 그것만으로 셀 수 없다 — 이 줄에는 상한이 없고, 둘을 함께 보는 것이
/// plan 결정 3이다.
///
/// **검색이 없으면 한 줄도 안 찍는다.** `hlStats()`가 null을 주는 자리가
/// 그것이다(plan 결정 2).
///
/// **반드시 `render()` 뒤에 부른다** — 값은 그 프레임의 `cells()`가 만든다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다.
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpHighlight(screen: *vt.Screen) void {
    const hl = screen.hlStats() orelse return;
    std.debug.print("terminal: find> hl spans={d} cells={d} us={d}\n", .{
        hl.spans, hl.cells, hl.us,
    });
}
```

### Step 2: 프레임마다 부른다 (사용자가 편집)

**넣을 것** — `terminal/src/main.zig`에서 `dumpScreen(cells);` **바로 다음
줄**이다(`:754` 근처, `dumpStyles` 호출 앞의 주석 앞).

```zig
        dumpHighlight(screen);
```

### Step 3: 빌드하고 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 조용히 끝나고 `vt_test`가 Task 3과 같은 `PASS`를 낸다. 이 Task는
`vt_test`가 안 보는 자리(`main.zig`)만 바꾸므로 검사 출력이 안 변하는 것이 정상이다.

**그래도 `zig build`를 함께 도는 이유**가 여기 있다 — 이 Task의 실수는 `zig build
test`가 영영 못 잡는다.

### Step 4: 커밋 (Claude가 실행)

```bash
git add terminal/src/main.zig
git commit -m "Log what the match highlight painted each frame"
```

---

## Task 5: 게이트가 하이라이트를 본다

**Files:**
- Modify: `copy/check.sh` (검사 16 추가, 검사 15 끝의 `esc` 자리를 늘린다)

**새 부팅도 새 타이핑도 없다.** 검사 15가 `/findme`를 끝낸 자리를 그대로 쓴다.

### Step 1: 검사 16을 더한다 (사용자가 편집)

**지울 것** — `copy/check.sh`에서 검사 15의 마지막 부분이다. 아래 네 줄을 찾는다
(`:757` 근처).

```sh
echo "n moved the cursor up the scrollback (row ${ROW_FIRST} -> ${ROW_SECOND})"

type_keys esc
sleep 1
```

**넣을 것**

```sh
echo "n moved the cursor up the scrollback (row ${ROW_FIRST} -> ${ROW_SECOND})"

# ── 검사 16: 매치 하이라이트 (CS-M0) ────────────────────────────────────
#
# **검사 15가 끝난 자리를 그대로 쓴다.** copy mode가 살아 있고 `/findme`의 매치
# 목록도 살아 있다 — 새 부팅도 새 타이핑도 없다. 게이트 시간을 안 늘리는 것이
# design 위험 4에 대한 답이다.
#
# **두 겹으로 본다**(plan 결정 3). `find> hl`은 vt.zig가 센 값이고 `style>`는 그
# 색이 정말 셀에 닿았는지다. 한 겹만 보면 "셌지만 안 칠했다"를 못 잡는다 —
# TR design 결정 7이 style>/pixel>을 두 겹으로 둔 것과 같은 규율이다.
HL="$(grep -a 'terminal: find> hl' "$LOG" | tail -n 1)"
if [ -z "$HL" ]; then
  report_failure "no find> hl line; the highlight never ran"
fi
HL_CELLS=$(echo "$HL" | sed -E 's/.*cells=([0-9]+).*/\1/')
# **needle이 여섯 자이므로 보이는 매치 하나당 정확히 여섯 칸이다.** 화면에 몇
# 개가 보이는지는 스크롤 위치에 딸린 값이라 못 박지 않고, 여섯의 배수인 것과
# 최소 하나는 있는 것만 본다.
if [ "$HL_CELLS" -lt 6 ] || [ $(( HL_CELLS % 6 )) -ne 0 ]; then
  report_failure "expected a multiple of six highlighted cells, got: ${HL}"
fi
# design 결정 5의 실측이다. **판정하지 않고 기록만 한다** — 상한을 둘지는 이
# 값을 보고 사람이 정한다.
echo "the match highlight: ${HL}"

# **판정.** 마지막 프레임의 셀이 정말 MATCH_BG를 받았다.
#
# 커서가 선 한 칸은 매치 위에서 또 한 번 맞바뀌므로 `fg=705000 bg=FFFFFF`가
# 되고, 나머지는 `fg=FFFFFF bg=705000`이다. 아래는 후자를 센다.
HL_STYLED="$(last_frame | grep -acE 'terminal: style> [0-9]+,[0-9]+ fg=FFFFFF bg=705000' || true)"
if [ "$HL_STYLED" -lt 1 ]; then
  echo "--- style lines in the last frame ---"
  last_frame | grep -a 'terminal: style>' | tail -n 20
  report_failure "no cell reached the framebuffer with the match background"
fi
echo "${HL_STYLED} cell(s) reached the framebuffer with bg=705000"

type_keys esc
sleep 1

# **판정(음성).** Esc가 copy mode를 닫으면 매치 목록도 함께 버려지므로
# (design 결정 6의 해제 자리 셋 중 하나) 하이라이트가 화면에서 사라진다.
#
# 안 사라지면 `copyExit`이 `find_matches`를 안 버린 것이고, 그 상태는 다음
# 검색에서 **이중 해제**로 이어진다 — 증상이 여기서는 색이지만 다음에는
# 크래시다.
if [ "$(last_frame | grep -acE 'bg=705000' || true)" -ne 0 ]; then
  echo "--- style lines in the last frame ---"
  last_frame | grep -a 'terminal: style>' | tail -n 20
  report_failure "the highlight survived leaving copy mode"
fi
echo "leaving copy mode cleared the highlight"
```

### Step 2: `copy` 체인만 단독으로 돌린다 (Claude가 실행, **약 8분**)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash copy/check.sh
```

**8분이라 Bash 도구의 10분 상한에 가깝다** — `run_in_background`로 돌린다.

**기대:** 검사 15까지 지금과 같고, 새 줄 셋이 더 나온 뒤 체인이 통과한다.

```
the match highlight: terminal: find> hl spans=... cells=... us=...
... cell(s) reached the framebuffer with bg=705000
leaving copy mode cleared the highlight
```

**`us=`를 특히 본다.** 이 값이 이 milestone이 남기는 실측이고, HANDOFF와 기억에
그대로 옮긴다. **CN-M1의 `searchAll()`이 60~70밀리초(`us=64423` 등)였다** — 그것은
Enter 한 번에 한 번이지만 이것은 매 프레임이므로 **두 자릿수는 작아야 한다.**

**`cells=`가 6의 배수가 아니면 그 숫자를 먼저 읽는다.** 매치가 줄 끝에 걸려 잘렸을
수 있고, 그러면 plan이 아니라 실측이 답이다.

**실패하면 `report_failure`가 `--- style lines in the last frame ---`를 뿜는다.**
그 목록에 `N more cell(s) not shown`이 섞여 있으면 `STYLE_DUMP_LIMIT`(16)에 걸린
것이라 판정이 아니라 상한 문제다.

### Step 3: 커밋 (Claude가 실행)

```bash
git add copy/check.sh
git commit -m "Check that the gate sees the match highlight"
```

---

## Task 6: 루트 게이트와 마무리

**Files:**
- Modify: `docs/superpowers/specs/2026-08-28-tars-copy-search-feedback-design.md`
  (`Status:` 줄)
- Modify: `HANDOFF.md`
- Modify: `MEMORY.md` + Create: `docs/decisions/project_copy_search_feedback.md`

### Step 1: 루트 게이트를 돌린다 (Claude가 실행, **약 22분**)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
```

**22분이라 Bash 도구의 상한을 넘는다** — `run_in_background`로 돌린다.
**`| tail`을 붙이지 않는다**(HANDOFF: 진행 상황이 안 보이고 종료 코드가 `tail`의
것이 된다).

**기대:** 여덟 체인 3/3, 부팅 30회 이상.

확인할 것 셋.

```bash
grep -c 'skipping make' /tmp/gate.out    # 23이어야 한다 (GL-M1)
tail -n 30 /tmp/gate.out                 # 3/3 판정
cat /tmp/gate.time                       # 기준선과 비교
```

**`skipping make`가 23이어야 한다.** 24면 `clean()`이 지운 자리에서도 건너뛴
것이라 잘못이다.

**기준선은 21분 38초다.** 이 milestone은 타이핑을 한 키도 안 더했으므로 **잡음
범위(±3분) 안에 있어야 한다.** 크게 벗어나면 코드를 의심하기 전에 기계를 먼저
의심한다(HANDOFF: TR-M2의 6시간 12분은 Chrome이 원인이었다).

### Step 2: 게이트를 세 번 돌린다 (Claude가 실행, **약 66분**)

한 번의 통과는 판정이 아니다. 위 명령을 세 번 돌려 전부 3/3인 것을 본다.
**`run_in_background`로 순차 실행한다.**

### Step 3: design doc의 `Status:`를 갱신한다 (Claude가 편집)

`docs/superpowers/specs/2026-08-28-tars-copy-search-feedback-design.md`의 3번째
줄을 `**Status:** 설계 확정. **CS-M0 완료(2026-08-28)**. CS-M1 미착수`로 바꾼다.

**이 저장소에는 `Status:` 줄이 낡은 design doc이 이미 셋 있다**(Config Persistence ·
Power Management · Hardware Discovery). CN design은 그 빚을 새로 만들지 않았고,
CS design도 만들지 않는다.

### Step 4: 기억을 만든다 (Claude가 편집)

`docs/decisions/project_copy_search_feedback.md`를 새로 만들고 `MEMORY.md`에 한 줄
더한다. **담을 것**은 실행이 증명한 것만이다.

- `pointFromPin`이 뷰포트 **위**의 pin에 대해 목록 끝까지 훑는다는 것, 그래서
  좌표를 푸는 방향을 뒤집었다는 것
- `Flattened`가 node를 역참조하지 않게 만들어졌고 `serial`이 그 짝이라는 것
- `matches()`가 얕은 복사라 바깥 슬라이스만 해제한다는 것
- `find> hl`의 `us=` 실측값
- 매치를 맞바꿈으로 만들면 안 되는 이유(선택 안에서 상쇄된다)

### Step 5: `HANDOFF.md`를 갱신한다 (Claude가 편집)

- 제목과 "지금 어디인가"를 CS-M0 이후로
- copy mode 표에 하이라이트 한 줄
- 로그 문구 목록에 `terminal: find> hl spans=… cells=… us=…`
- 게이트 기준선을 실측으로
- "이월 숙제"에서 매치 하이라이트를 **끝난 숙제**로 옮긴다
- 핵심 파일의 줄 번호를 CS-M0 이후로

### Step 6: 커밋 (Claude가 실행)

```bash
git status --short
git add docs/ HANDOFF.md MEMORY.md
git commit -m "Close out CS-M0"
```

**`git add`로 디렉터리를 통째로 넣기 전에 `git status`를 먼저 본다**(저장소 규칙).

---

## 완료 조건

- [ ] `zig build && zig build test`가 통과하고 `vt_test`에 검사 26~31이 있다
- [ ] `copy` 체인이 단독으로 통과하고 `find> hl` 줄에 `us=` 실측이 남는다
- [ ] 루트 게이트가 **3회 연속 8체인 3/3**이고 `skipping make`가 매번 23이다
- [ ] design doc의 `Status:`가 CS-M0 완료로 갱신됐다
- [ ] `docs/decisions/project_copy_search_feedback.md`와 `MEMORY.md` 한 줄이 있다
- [ ] `HANDOFF.md`가 CS-M0 이후 상태를 적고 있다

## 이 milestone이 안 하는 것

- **키를 안 더한다.** `input.zig`·`input_test.zig`를 안 건드린다.
- **현재 매치를 다른 색으로 하지 않는다**(design "비워 두는 자리").
- **`[3/12]` 표시를 안 한다**(같은 자리).
- **검색 결과를 갱신하지 않는다**(design 결정 7).
- **검색 기록도 "못 찾음" 메시지도 안 한다** — 그것이 CS-M1이고, **plan은 CS-M0이
  끝난 뒤에 쓴다.**
