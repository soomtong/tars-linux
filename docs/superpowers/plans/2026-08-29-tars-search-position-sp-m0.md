# SP-M0 구현 계획 — 현재 매치를 다른 색으로

> **실행 방식은 이 저장소의 규칙을 따른다**(`CLAUDE.md`). 구현 파일 편집은
> **사용자가** 하고, 빌드·QEMU·게이트 실행은 **Claude가** 한다. subagent를
> 띄우지 않는다. 각 Task의 "넣을 것"을 Claude가 제시하면 사용자가 파일에
> 넣고, Claude가 그 자리에서 검증 명령을 돌려 결과를 줄 단위로 설명한다.

**목표:** 검색이 찾은 매치 중 **지금 선택된 하나**를 나머지와 다른 바탕색으로
칠한다.

**구조:** 라이브러리가 이미 들고 있는 `selected.idx`를 창구 하나로 꺼내고
(Task 1), 그 인덱스를 `findSpans`가 만드는 행별 범위에 실어 보내고(Task 3),
`cells()`가 그 표식을 보고 색 둘 중 하나를 고른다(Task 4). 좌표 계산은 한
벌뿐이고 색만 갈린다.

**참고 문서:** `docs/superpowers/specs/2026-08-29-tars-search-position-design.md`

---

## 이 계획이 서 있는 실측 (2026-08-29)

**1. 라이브러리의 `selected.idx`와 `matches()` 슬라이스는 같은 좌표계다.**
`selectedMatch()`(`search/screen.zig:771`)와 `matches()`(`:234`)가 같은 색인
규칙을 쓴다 — 활성 영역은 뒤집어 담고 history는 그대로 이어 붙인다. 그래서
`find_matches[idx]`가 곧 현재 매치다.

**2. 검사 16의 자리는 `spans=1 cells=6`이다.** copy 체인을 한 번 돌려 확인했다
(`the match highlight: terminal: find> hl spans=1 cells=6 us=56`). **화면에
보이는 매치가 하나이고 그것이 곧 현재 매치이므로, SP-M0은 그 자리에서
`bg=705000`을 0개로 만든다** — Task 6이 그 검사를 고치는 이유다.

**3. 체인 전체에는 `spans=2 cells=12`인 프레임도 있다**(부팅 3회에서 6번).
그러나 **그 프레임이 어느 검색인지 못 박지 못했다** — 조사 명령의 `head`가
`find>` 줄에 닿기 전에 잘렸다. 그래서 Task 7의 검사 19는 **그 자리를 찾아
쓰지 않고 자기 조건을 스스로 만든다**(plan 결정 4).

**4. `vt_test`의 새 이름은 안 부딪친다.** `ps`·`ps_i`·`phit`·`pspans`·
`pcur`·`cur_i`·`sel_i`를 `rg`로 확인했고 전부 미사용이다. `main()` 하나가 파일
전체라 Zig가 shadowing을 컴파일 에러로 막으므로 이 확인이 필수다.

**5. `HANDOFF.md`의 `main.zig` 줄 번호가 네 줄쯤 앞을 가리킨다.** 이 계획은
2026-08-29에 직접 확인한 줄 번호를 쓴다.

---

## plan 결정

### plan 결정 1. 인덱스 창구는 `?usize`이고 범위를 함께 본다

`findCurrentIndex()`가 null을 주는 경우가 넷이다: 검색이 없다 · 선택이 없다 ·
스냅숏이 없다 · **인덱스가 스냅숏 길이를 벗어난다.** 마지막이 design 위험 2다.
라이브러리도 `selectedMatch()`에서 같은 방어를 한다(`:783`).

넷을 한 함수에서 전부 null로 접는 이유는 **부르는 쪽이 "현재 매치가 없다"
하나만 알면 되기 때문**이다. 넷을 갈라 주면 `findSpans`가 그 갈림을 다시
합쳐야 한다.

### plan 결정 2. `RowSpan.current`에 기본값을 주지 않는다

만드는 자리가 `findSpans` 한 곳뿐이다. 기본값 `= false`를 주면 나중에 두 번째
자리가 생겼을 때 **정하는 것을 잊어도 컴파일이 통과한다.** 기본값을 안 주면
Zig가 그 자리에서 막는다.

### plan 결정 3. `cells()`는 current를 만났을 때만 `break` 한다

지금 코드는 **처음 걸린 span에서** `break` 한다. 색이 하나일 때는 순수한
최적화였지만, 색이 둘이 되면 그 `break`가 **"목록 순서가 색을 정한다"**로 뜻이
바뀐다(design 결정 3).

그래서 두 표식을 따로 세우고, `current`를 만나면 그때는 더 볼 것이 없으므로
`break` 한다. 안 만나면 행 안의 span을 끝까지 본다 — 행마다 몇 개라 비용이
없다.

### plan 결정 4. 검사 19는 자기 조건을 스스로 만들고 needle이 **두 글자**다

두 색을 함께 보려면 매치가 둘 이상 한 화면에 있어야 한다. 앞 검사가 남긴
스크롤 위치에 기대면 **판정이 스크롤에 딸리게 되고**, 실측 3이 말하듯 그 자리를
아직 못 박지 못했다.

**needle을 한 줄에 두 번 심는다.** 같은 줄이면 뷰포트가 어디에 있든 둘이 함께
보인다 — 스크롤과 무관해진다.

**needle을 두 글자로 두는 것에 이유가 있다.** `style>`는 프레임당 16줄이
상한이고(`STYLE_DUMP_LIMIT`), 넘으면 조용히 잘리는 대신 "N more cell(s) not
shown"이 뜬다. 일곱 글자 needle이면 명령줄 14칸 + 출력줄 14칸 = 28칸이라 상한을
넘고, **그러면 뒤쪽 색이 안 찍혀 "색이 안 닿았다"로 잘못 읽힌다.** 두 글자면
8칸이라 넉넉하다.

**`findme`를 쓰면 안 된다.** 검사 15와 17이 `matches=4`를 판정에 쓰므로 새
매치가 그 숫자를 깨뜨린다. `zq`는 이 화면 어디에도 없고 검사 18의 `zzz`와도
안 겹친다.

### plan 결정 5. `cur=`은 `cells=` 뒤·`us=` 앞에 넣는다

검사 16이 `sed -E 's/.*cells=([0-9]+).*/\1/'`로 `cells=`를 뽑는다. 그 뒤에
필드를 더하는 것은 안전하지만 **`cells=`를 옮기거나 이름을 겹치게 만들면
깨진다.** 새 필드 이름을 `cur`로 두는 것도 그 때문이다 — `cells`를 부분
문자열로 갖지 않는다.

---

## Task 1: 인덱스 창구를 만든다

**Files:**
- Modify: `terminal/src/vt.zig` — `findMatchCount`(`:706~709`) **바로 뒤**

- [ ] **Step 1: 넣을 것**

`vt.zig`의 `findMatchCount` 함수가 끝나는 `}` 다음 줄에, `refreshMatches` 주석
블록이 시작되기 **전에** 넣는다.

```zig
    /// 지금 선택된 매치가 `find_matches`의 몇 번째인가. 없으면 null이다.
    ///
    /// **라이브러리의 내부 필드를 읽는 유일한 자리다**(SP design 결정 1).
    /// `ScreenSearch`에 `selectedIndex()` 같은 공개 함수가 없어서 `selected.idx`를
    /// 직접 본다. 한 함수로 감싸 두는 이유는 나중에 라이브러리에 함수가 생기거나
    /// 다른 방법으로 바꿀 때 고칠 자리를 하나로 두기 위해서다 — `findMissed`가
    /// `find_last`를 감싼 것과 같은 경계다.
    ///
    /// **`idx`가 `find_matches`의 인덱스와 같은 좌표계라는 것이 이 함수의
    /// 전제다.** `selectedMatch()`와 `matches()`가 같은 색인 규칙을 쓴다
    /// (`search/screen.zig:771`과 `:234`) — 활성 영역은 뒤집어 담고 history는
    /// 그대로 이어 붙이는 그 규칙이다. **그 전제가 조용히 깨지면 증상이 "번호가
    /// 거꾸로 나온다"라 눈에 안 띄므로 `vt_test`의 검사 37·38이 뜻을 고정한다.**
    ///
    /// 범위를 함께 보는 이유는 라이브러리도 그렇게 하기 때문이다
    /// (`selectedMatch()`가 `:783`에서 null을 준다). `select()`가
    /// `reloadActive()`·`pruneHistory()`를 먼저 부르므로 목록이 줄어들 수 있고,
    /// 그때 낡은 `idx`를 그대로 쓰면 범위를 벗어난다. **넷을 전부 null 하나로
    /// 접는 것이 요점이다**(plan 결정 1) — 부르는 쪽은 "현재 매치가 없다"만
    /// 알면 된다.
    pub fn findCurrentIndex(self: *const Screen) ?usize {
        if (self.find == null) return null;
        const sel = self.find.?.selected orelse return null;
        const m = self.find_matches orelse return null;
        if (sel.idx >= m.len) return null;
        return sel.idx;
    }
```

- [ ] **Step 2: 빌드가 지나가는지 본다 (Claude가 실행, 약 3분)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 조용히 끝나고 `vt_test`가 CS-M1까지와 **글자 하나 다르지 않은 PASS**를
낸다. 이 Task는 아직 아무 동작도 안 바꾼다 — 아무도 안 부르는 함수 하나가
늘었을 뿐이다.

**`zig build`를 함께 도는 이유**는 HANDOFF의 실측 1이다. Zig가 참조되지 않는
함수를 분석하지 않으므로, `zig build test`만 돌면 이 함수의 컴파일 오류를
못 잡을 수 있다.

**실패한다면 무엇을 뜻하나:** `selected`가 없는 필드라는 에러가 나면 vendor된
ghostty가 이 계획이 읽은 것과 다른 버전이다. 그때는 `terminal/ghostty-src/src/
terminal/search/screen.zig`의 `pub const SelectedMatch`를 다시 읽는다.

- [ ] **Step 3: 커밋 (Claude가 실행)**

```bash
git add terminal/src/vt.zig
git commit -m "Give the current match an index the terminal can read"
```

---

## Task 2: `vt_test`가 인덱스의 뜻을 고정한다 (검사 37·38)

design 결정 1이 "뜻이 조용히 바뀌는 것은 검사로 막는다"라고 정한 자리다.
**여기서 새 화면 `ps`를 만들고 Task 5까지 계속 쓴다.**

**Files:**
- Modify: `terminal/src/vt_test.zig` — 마지막 `std.debug.print("PASS\n", .{});`
  (`:1119`) **바로 앞**

- [ ] **Step 1: 넣을 것**

```zig
    // ── SP-M0: 현재 매치 ────────────────────────────────────────────────
    //
    // **자기 화면을 새로 만든다.** 화면마다 크기와 history가 다르므로 남의
    // 검사에 붙이면 기대값이 흔들린다. `hs`(CS-M0)와 같은 20x5에 같은 8·18번
    // 줄을 표적으로 두는 것은 게으름이 아니라 **기대값을 옮겨 쓰기 위한
    // 것이다** — 다른 것은 8번 줄에 매치가 **둘**이라는 점 하나다.
    //
    // 이름이 `ps`인 이유: `main()` 하나가 파일 전체라 이 파일의 모든 지역
    // 변수가 서로 부딪치고 Zig가 shadowing을 컴파일 에러로 막는다.
    // `cm`·`painted`·`pruned`·`wm`·`fm`·`fs`·`hs`·`ls`가 이미 쓰여 있다.
    const ps = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer ps.deinit();
    var ps_i: usize = 1;
    while (ps_i <= 20) : (ps_i += 1) {
        if (ps_i == 8) {
            // **한 줄에 매치 둘.** 같은 줄이면 뷰포트가 어디에 있든 함께
            // 보이므로, 두 색을 나란히 보는 검사가 스크롤에 안 딸린다.
            ps.feed("qqzqqqzqqq\r\n");
        } else if (ps_i == 18) {
            ps.feed("qqzqqqqqqq\r\n");
        } else {
            ps.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{ps_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다.
    _ = try ps.cells(&buf);
    ps.copyEnter();

    // 검사 37. **`/` 직후의 인덱스는 0이다.**
    //
    // 라이브러리 주석이 "0 = most recent match"라고 적었고(`SelectedMatch`),
    // `select(.next)`가 선택이 없을 때 인덱스 0을 만든다(`selectNext`의 첫
    // 분기). **그 뜻을 여기서 실행으로 고정한다** — 소스를 읽어 얻은 사실을
    // 검사로 옮기는 규율이고, 이것이 깨지면 SP-M1의 번호가 거꾸로 나온다.
    ps.findOpen();
    for ("zq") |ch| ps.findChar(ch);
    const phit = try ps.findSubmit();
    if (phit.matches != 3) {
        std.debug.print("FAIL: /zq found {d} match(es) (expected 3)\n", .{phit.matches});
        return error.CurrentMatchSetupWrong;
    }
    const pcur = ps.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index right after the search\n", .{});
        return error.CurrentIndexMissing;
    };
    if (pcur != 0) {
        std.debug.print("FAIL: the first match has index {d} (expected 0)\n", .{pcur});
        return error.CurrentIndexWrong;
    }
    std.debug.print("vt_test: 검색 직후의 현재 매치는 0번이다 OK (matches={d})\n", .{phit.matches});

    // 검사 38. **`n`이 인덱스를 하나 올린다.**
    //
    // 검사 37이 "0에서 시작한다"를 보고 이 검사가 "한 칸씩 간다"를 본다.
    // 둘이 함께 있어야 번호가 뜻을 갖는다 — 시작점만 맞고 걸음이 틀리면
    // `[3/12]`가 조용히 어긋난다.
    if (!try ps.findNext()) {
        std.debug.print("FAIL: n did not move to another match\n", .{});
        return error.CurrentIndexNoMove;
    }
    const pcur2 = ps.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index after n\n", .{});
        return error.CurrentIndexMissing;
    };
    if (pcur2 != 1) {
        std.debug.print("FAIL: after one n the index is {d} (expected 1)\n", .{pcur2});
        return error.CurrentIndexWrong;
    }
    std.debug.print("vt_test: n이 현재 매치를 한 칸 옮긴다 OK (idx={d})\n", .{pcur2});
```

- [ ] **Step 2: 검사를 돌린다 (Claude가 실행, 약 3분)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 검사 36까지의 줄이 그대로 나오고 그 뒤에 두 줄이 더 나온다.

```
vt_test: 검색 직후의 현재 매치는 0번이다 OK (matches=3)
vt_test: n이 현재 매치를 한 칸 옮긴다 OK (idx=1)
PASS
```

**`matches=3`이 아니면 화면 준비가 틀린 것이다.** 8번 줄에 둘, 18번 줄에 하나로
셋이다. 다른 숫자가 나오면 `qqzqqqzqqq`가 의도대로 안 들어간 것이므로 그
줄부터 본다.

- [ ] **Step 3: 커밋 (Claude가 실행)**

```bash
git add terminal/src/vt_test.zig
git commit -m "Pin down what the current match index means"
```

---

## Task 3: 범위에 "현재"라는 표식을 싣는다

**Files:**
- Modify: `terminal/src/vt.zig` — `RowSpan`(`:26`) · `HlStats`(`:41`) ·
  `hl_stats` 필드 기본값(`:217`) · `findSpans`(`:750~823`)

- [ ] **Step 1: `RowSpan`에 필드를 더한다**

**지울 것** (`vt.zig:26~29`)

```zig
pub const RowSpan = struct {
    row: u16,
    x0: u16,
    x1: u16,
```

**넣을 것**

```zig
pub const RowSpan = struct {
    row: u16,
    x0: u16,
    x1: u16,
    /// 이 범위가 **지금 선택된 매치**인가(SP design 결정 2).
    ///
    /// **기본값을 안 주는 것에 뜻이 있다**(plan 결정 2). 만드는 자리가
    /// `findSpans` 하나뿐인데, 기본값이 있으면 두 번째 자리가 생겼을 때
    /// 정하는 것을 잊어도 컴파일이 통과한다.
    current: bool,
```

- [ ] **Step 2: `HlStats`에 셈을 더한다**

**지울 것** (`vt.zig:41`)

```zig
pub const HlStats = struct { spans: usize, cells: usize, us: i64 };
```

**넣을 것**

```zig
/// `cur`은 **현재 매치가 칠한 셀 수**다(SP-M0). `cells`는 뜻을 안 바꾼다 —
/// 여전히 보이는 매치 **전부**의 셀 수이고, 게이트의 검사 16이 그 뜻에 기대
/// "needle 길이의 배수"를 본다.
pub const HlStats = struct { spans: usize, cells: usize, cur: usize, us: i64 };
```

- [ ] **Step 3: 필드 기본값을 고친다**

**지울 것** (`vt.zig:217`)

```zig
    hl_stats: HlStats = .{ .spans = 0, .cells = 0, .us = 0 },
```

**넣을 것**

```zig
    hl_stats: HlStats = .{ .spans = 0, .cells = 0, .cur = 0, .us = 0 },
```

- [ ] **Step 4: `findSpans`가 인덱스를 본다**

**지울 것** (`vt.zig:751~752`, 함수 첫 두 줄)

```zig
        self.hl_spans.clearRetainingCapacity();
        self.hl_stats = .{ .spans = 0, .cells = 0, .us = 0 };
```

**넣을 것**

```zig
        self.hl_spans.clearRetainingCapacity();
        self.hl_stats = .{ .spans = 0, .cells = 0, .cur = 0, .us = 0 };
```

**지울 것** (`vt.zig:775`, 매치를 도는 루프의 머리)

```zig
            for (matches) |m| {
```

**넣을 것**

```zig
            for (matches, 0..) |m, mi| {
```

**지울 것** (`vt.zig:798~802`, span을 담는 자리)

```zig
                        try self.hl_spans.append(self.alloc, .{
                            .row = row0 + (ry - y),
                            .x0 = if (is_first) m.top_x else 0,
                            .x1 = if (is_last) m.bot_x else cols - 1,
                        });
```

**넣을 것**

```zig
                        try self.hl_spans.append(self.alloc, .{
                            .row = row0 + (ry - y),
                            .x0 = if (is_first) m.top_x else 0,
                            .x1 = if (is_last) m.bot_x else cols - 1,
                            // **좌표를 두 번 풀지 않는 것이 요점이다**(SP design
                            // 결정 2). 현재 매치만 따로 다시 푸는 길로 가면 같은
                            // 계산이 두 벌이 되고, 어긋났을 때 증상이 "색만
                            // 엉뚱한 자리에 있다"라 조사하기 나쁘다.
                            .current = if (cur_i) |ci| ci == mi else false,
                        });
```

- [ ] **Step 5: 인덱스를 루프 밖에서 한 번만 읽는다**

**지울 것** (`vt.zig:763`, 시계를 재기 시작하는 줄의 앞뒤)

```zig
        const t0 = std.Io.Clock.now(.awake, self.io);
```

**넣을 것**

```zig
        // **루프 밖에서 한 번만 읽는다.** 매치마다 부르면 같은 값을 매치 수만큼
        // 다시 구하는 셈이고, 이 함수는 매 프레임 돈다.
        const cur_i = self.findCurrentIndex();

        const t0 = std.Io.Clock.now(.awake, self.io);
```

- [ ] **Step 6: 셀 수를 두 갈래로 센다**

**지울 것** (`vt.zig:816~822`, 함수 끝)

```zig
        var painted: usize = 0;
        for (self.hl_spans.items) |sp| painted += @as(usize, sp.x1 - sp.x0) + 1;
        self.hl_stats = .{
            .spans = self.hl_spans.items.len,
            .cells = painted,
            .us = @intCast(@divTrunc(t0.untilNow(self.io, .awake).nanoseconds, 1000)),
        };
```

**넣을 것**

```zig
        var painted: usize = 0;
        var painted_cur: usize = 0;
        for (self.hl_spans.items) |sp| {
            const w = @as(usize, sp.x1 - sp.x0) + 1;
            painted += w;
            if (sp.current) painted_cur += w;
        }
        self.hl_stats = .{
            .spans = self.hl_spans.items.len,
            .cells = painted,
            .cur = painted_cur,
            .us = @intCast(@divTrunc(t0.untilNow(self.io, .awake).nanoseconds, 1000)),
        };
```

- [ ] **Step 7: 빌드와 검사 (Claude가 실행, 약 3분)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** `PASS`. 색은 아직 안 바뀌었으므로 CS-M0의 검사 28·29가 그대로 통과해야
한다 — **이 Task가 색을 안 건드렸다는 것의 증명이 그것이다.**

`.current`에 기본값을 안 주었으므로, 담는 자리를 빠뜨렸다면 여기서
`missing struct field` 에러가 난다. **그것이 plan 결정 2가 노린 것이다.**

- [ ] **Step 8: 커밋 (Claude가 실행)**

```bash
git add terminal/src/vt.zig
git commit -m "Mark which highlighted span is the current match"
```

---

## Task 4: 색을 둘로 가른다

**Files:**
- Modify: `terminal/src/vt.zig` — `MATCH_BG`(`:57`) 뒤 · `cells()`의 매치
  층(`:422~427`)

- [ ] **Step 1: 상수를 더한다**

`MATCH_BG` 선언(`vt.zig:57`) **바로 뒤**에 넣는다.

```zig

/// 지금 선택된 매치의 바탕색(SP design 결정 4). **`MATCH_BG`와 같은 계열의
/// 더 밝은 색이다.**
///
/// 색상 계열을 같게 두고 밝기만 올리는 것에 뜻이 있다 — "같은 종류인데 이것이
/// 지금 것"이라는 뜻을 밝기 차이가 전달한다. 다른 계열을 고르면 두 색이 서로
/// 다른 것을 뜻하는 것처럼 보인다.
///
/// | 상태 | 바탕 | 글자 |
/// |---|---|---|
/// | 기본 | `#102030` | 흰색 |
/// | 선택 | 흰색 | `#102030` |
/// | 매치 | `#705000` | 흰색 |
/// | **현재 매치** | **`#C08000`** | 흰색 |
/// | 선택 안의 매치 | 흰색 | `#705000` |
///
/// **`fg`는 여전히 안 건드린다.** 그래서 CS design 결정 1의 "매치는 바탕만
/// 정한다"가 한 줄 그대로 남는다.
pub const CURRENT_BG: u32 = 0x00C08000;
```

- [ ] **Step 2: `cells()`의 매치 층을 고친다**

**지울 것** (`vt.zig:422~427`)

```zig
                for (row_spans) |sp| {
                    if (x >= @as(usize, sp.x0) and x <= @as(usize, sp.x1)) {
                        bg = MATCH_BG;
                        break;
                    }
                }
```

**넣을 것**

```zig
                // **먼저 걸린 것에서 멈추지 않는다**(plan 결정 3). 색이 하나일
                // 때는 그 `break`가 순수한 최적화였지만, 둘이 되면 **목록
                // 순서가 색을 정하는 것**이 된다. 매치끼리 겹칠 일이 없다고
                // 믿고 있지만 증명한 적이 없으므로, 겹치면 **현재 매치가
                // 이기게** 한다.
                //
                // `current`를 만났을 때는 더 볼 것이 없으므로 그때만 멈춘다.
                var hit_match = false;
                var hit_current = false;
                for (row_spans) |sp| {
                    if (x >= @as(usize, sp.x0) and x <= @as(usize, sp.x1)) {
                        hit_match = true;
                        if (sp.current) {
                            hit_current = true;
                            break;
                        }
                    }
                }
                if (hit_match) bg = if (hit_current) CURRENT_BG else MATCH_BG;
```

- [ ] **Step 3: 빌드와 검사 (Claude가 실행, 약 3분)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대: `zig build`는 통과하고 `zig build test`는 실패한다.** 실패가 **의도된
결과**다 — CS-M0의 검사 29가 `hs` 화면에서 매치 셀의 바탕이 `MATCH_BG`인 것을
보는데, 그 화면은 매치가 **하나**만 보이고 그 하나가 곧 현재 매치라 이제
`CURRENT_BG`가 된다.

기대하는 실패 문구는 이것이다.

```
FAIL: 0 plain + 0 inverted match cell(s) (expected 5 + 1)
```

**이 실패가 SP-M0이 실제로 동작한다는 첫 증거다.** 이 자리에서 통과해 버리면
색이 안 바뀐 것이다.

- [ ] **Step 4: CS-M0의 검사 29를 새 사실에 맞춘다**

**지울 것** (`vt_test.zig:934~957` 언저리, 검사 29의 본문)

```zig
    var hcnt: usize = 0;
    var hcursor: usize = 0;
    for (try hs.cells(&buf)) |c| {
        // 이름이 `painted`가 아닌 이유: CM-M0의 검사가 `:386`에서 그 이름을
        // 쓰고 있고, `main()` 하나가 파일 전체라 Zig가 shadowing을 막는다.
        const hpaint = c.bg == vt.MATCH_BG or c.fg == vt.MATCH_BG;
        if (!hpaint) continue;
        if (c.row != 0 or c.col < 2 or c.col > 7) {
            std.debug.print("FAIL: painted a cell outside the match at {d},{d}\n", .{
                c.row, c.col,
            });
            return error.HighlightPaintedWrongCell;
        }
        if (c.bg == vt.MATCH_BG) hcnt += 1 else hcursor += 1;
    }
    if (hcnt != 5 or hcursor != 1) {
        std.debug.print("FAIL: {d} plain + {d} inverted match cell(s) (expected 5 + 1)\n", .{
            hcnt, hcursor,
        });
        return error.HighlightPaintCountWrong;
    }
    std.debug.print("vt_test: 매치 셀의 바탕이 MATCH_BG다 OK (plain={d} cursor={d})\n", .{
        hcnt, hcursor,
    });
```

**넣을 것**

```zig
    // **SP-M0이 색을 바꿨다.** 이 화면은 매치가 하나만 보이고 그 하나가 곧
    // 현재 매치이므로, 여기 칠해지는 것은 `MATCH_BG`가 아니라 `CURRENT_BG`다.
    // **`MATCH_BG` 쪽을 보는 검사는 `ps` 화면의 검사 39가 이어받는다** — 매치가
    // 둘 이상 보여야 두 색이 함께 나오기 때문이다.
    var hcnt: usize = 0;
    var hcursor: usize = 0;
    for (try hs.cells(&buf)) |c| {
        // 이름이 `painted`가 아닌 이유: CM-M0의 검사가 `:386`에서 그 이름을
        // 쓰고 있고, `main()` 하나가 파일 전체라 Zig가 shadowing을 막는다.
        const hpaint = c.bg == vt.CURRENT_BG or c.fg == vt.CURRENT_BG;
        if (!hpaint) continue;
        if (c.row != 0 or c.col < 2 or c.col > 7) {
            std.debug.print("FAIL: painted a cell outside the match at {d},{d}\n", .{
                c.row, c.col,
            });
            return error.HighlightPaintedWrongCell;
        }
        if (c.bg == vt.CURRENT_BG) hcnt += 1 else hcursor += 1;
    }
    if (hcnt != 5 or hcursor != 1) {
        std.debug.print("FAIL: {d} plain + {d} inverted match cell(s) (expected 5 + 1)\n", .{
            hcnt, hcursor,
        });
        return error.HighlightPaintCountWrong;
    }
    std.debug.print("vt_test: 현재 매치 셀의 바탕이 CURRENT_BG다 OK (plain={d} cursor={d})\n", .{
        hcnt, hcursor,
    });
```

- [ ] **Step 5: 검사 30을 함께 고친다**

**같은 `hs` 화면을 보므로 이 검사도 반드시 함께 깨진다.** 계획을 쓰면서 본문을
읽어 확인했다(`vt_test.zig:960~977`).

**지울 것**

```zig
    try hs.copySelect(.line);
    var hswapped: usize = 0;
    for (try hs.cells(&buf)) |c| {
        if (c.fg == vt.MATCH_BG and c.bg != vt.MATCH_BG) hswapped += 1;
    }
```

**넣을 것**

```zig
    // **SP-M0이 이 화면의 색을 `CURRENT_BG`로 바꿨다.** 보이는 매치가 하나이고
    // 그것이 곧 현재 매치이기 때문이다. 이 검사가 보는 것은 색의 값이 아니라
    // **"맞바꿈이 아니라 값을 정하는 층인가"**이므로, 상수만 옮기면 뜻이 그대로
    // 남는다.
    try hs.copySelect(.line);
    var hswapped: usize = 0;
    for (try hs.cells(&buf)) |c| {
        if (c.fg == vt.CURRENT_BG and c.bg != vt.CURRENT_BG) hswapped += 1;
    }
```

- [ ] **Step 6: 검사 31을 두 색으로 넓힌다**

**이쪽은 안 고쳐도 통과한다 — 그것이 문제다.** `copyExit` 뒤에 `MATCH_BG`인
셀을 세어 0인지 보는데, SP-M0 뒤로는 이 화면에 `MATCH_BG`가 애초에 없으므로
**아무것도 안 보는 검사가 된다.** 게이트의 음성 판정을 넓히는 것(Task 7 Step 2)과
정확히 같은 이유다.

**지울 것**

```zig
    var hleft: usize = 0;
    for (try hs.cells(&buf)) |c| {
        if (c.bg == vt.MATCH_BG or c.fg == vt.MATCH_BG) hleft += 1;
    }
```

**넣을 것**

```zig
    // **두 색을 함께 센다**(SP-M0). 한 색만 보면, 이 화면처럼 그 색이 애초에
    // 안 쓰이는 경우에 **아무것도 안 보는 검사**가 된다.
    var hleft: usize = 0;
    for (try hs.cells(&buf)) |c| {
        const hgone = c.bg == vt.MATCH_BG or c.fg == vt.MATCH_BG or
            c.bg == vt.CURRENT_BG or c.fg == vt.CURRENT_BG;
        if (hgone) hleft += 1;
    }
```

- [ ] **Step 7: 다시 돌린다 (Claude가 실행, 약 3분)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test' 2>&1 | tail -30
```

**기대:** `PASS`. 검사 29·30·31 세 줄이 예전과 같은 숫자로 나온다.

```
vt_test: 현재 매치 셀의 바탕이 CURRENT_BG다 OK (plain=5 cursor=1)
vt_test: 선택 안의 매치가 맞바뀌어 남는다 OK (cells=5)
vt_test: copy mode를 나가면 하이라이트가 사라진다 OK
```

**숫자가 예전과 같은 것이 판정이다.** 색만 바뀌고 셈은 안 바뀌어야 한다 — 셈이
바뀌었다면 층 순서를 건드린 것이다.

- [ ] **Step 8: 커밋 (Claude가 실행)**

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Paint the current match in its own colour"
```

---

## Task 5: 두 색이 함께 있는 것을 `vt_test`가 본다 (검사 39)

Task 4까지는 색이 **하나뿐인** 화면만 보았다. 두 색이 나란히 나오는 것은 이
검사가 처음 본다.

**Files:**
- Modify: `terminal/src/vt_test.zig` — Task 2가 넣은 검사 38 **바로 뒤**

- [ ] **Step 1: 넣을 것**

```zig
    // 검사 39. **두 색이 한 화면에 나란히 있다.**
    //
    // `n`을 한 번 눌렀으므로 현재 매치는 8번 줄의 두 매치 중 하나다.
    // `copyPlace`가 그 줄을 뷰포트 맨 위로 올리므로 **같은 줄의 다른 매치도
    // 함께 보인다** — 한 줄에 둘을 심은 이유가 이것이고, 그래서 이 판정이
    // 스크롤 위치에 안 딸린다.
    //
    // **어느 쪽이 현재 매치인지는 안 본다.** 라이브러리가 한 줄 안의 매치를
    // 어느 순서로 주는지 확인한 적이 없고, 그것에 기대면 검사가 라이브러리의
    // 안 적힌 성질에 딸리게 된다. 왼쪽이든 오른쪽이든 **셈은 똑같다.**
    _ = try ps.cells(&buf);
    const pspans = ps.hlSpans();
    if (pspans.len != 2) {
        std.debug.print("FAIL: {d} span(s) in view (expected 2)\n", .{pspans.len});
        for (pspans) |sp| {
            std.debug.print("  span row={d} x0={d} x1={d} current={}\n", .{
                sp.row, sp.x0, sp.x1, sp.current,
            });
        }
        return error.CurrentSpanCountWrong;
    }
    var cur_n: usize = 0;
    for (pspans) |sp| {
        if (sp.current) cur_n += 1;
    }
    if (cur_n != 1) {
        std.debug.print("FAIL: {d} span(s) marked current (expected exactly 1)\n", .{cur_n});
        return error.CurrentSpanMarkWrong;
    }

    // **셈이 이렇게 갈린다.** needle이 두 글자이므로 매치 하나가 두 칸이다.
    //   - 현재 매치: 첫 칸에 copy 커서가 서서 한 번 더 맞바뀌므로
    //     `bg=CURRENT_BG`가 **하나**, `fg=CURRENT_BG`가 **하나**
    //   - 다른 매치: `bg=MATCH_BG`가 **둘**
    // CS-M0의 검사 29가 `plain=5 cursor=1`로 본 것과 **같은 갈림**이고, HANDOFF의
    // 실측 3("매치 여섯 칸 중 하나는 언제나 뒤집혀 있다")이 여기서도 그대로다.
    var p_cur_plain: usize = 0;
    var p_cur_cursor: usize = 0;
    var p_other: usize = 0;
    for (try ps.cells(&buf)) |c| {
        if (c.bg == vt.CURRENT_BG) p_cur_plain += 1;
        if (c.fg == vt.CURRENT_BG) p_cur_cursor += 1;
        if (c.bg == vt.MATCH_BG) p_other += 1;
    }
    if (p_cur_plain != 1 or p_cur_cursor != 1 or p_other != 2) {
        std.debug.print("FAIL: current plain={d} cursor={d}, other={d} (expected 1, 1, 2)\n", .{
            p_cur_plain, p_cur_cursor, p_other,
        });
        return error.CurrentPaintCountWrong;
    }
    std.debug.print("vt_test: 현재 매치와 나머지가 다른 색이다 OK (cur={d}+{d} other={d})\n", .{
        p_cur_plain, p_cur_cursor, p_other,
    });

    // 검사 40. **`hlStats`의 `cur`이 현재 매치만 센다.**
    //
    // 검사 39는 `cells()`가 내놓은 색을 세고, 이 검사는 `vt.zig`가 **스스로 센
    // 값**을 본다. 둘이 어긋나면 게이트의 `cur=`을 믿을 수 없게 된다 —
    // 게이트는 색을 직접 못 세고 이 숫자에 기댄다.
    //
    // **`cur`은 커서를 모른다.** 커서는 `cells()`가 얹는 층이라 `findSpans`
    // 뒤에 온다. 그래서 `cur=2`이고 화면에 보이는 `bg=CURRENT_BG`는 하나다 —
    // **둘이 다른 것이 정상이고, 그 차이가 정확히 1이다.**
    const pstats = ps.hlStats() orelse {
        std.debug.print("FAIL: hlStats() was null while a search was live\n", .{});
        return error.CurrentStatsMissing;
    };
    if (pstats.cells != 4 or pstats.cur != 2) {
        std.debug.print("FAIL: cells={d} cur={d} (expected 4 and 2)\n", .{
            pstats.cells, pstats.cur,
        });
        return error.CurrentStatsWrong;
    }
    if (pstats.cur != p_cur_plain + p_cur_cursor) {
        std.debug.print("FAIL: cur={d} but the framebuffer shows {d}+{d}\n", .{
            pstats.cur, p_cur_plain, p_cur_cursor,
        });
        return error.CurrentStatsMismatch;
    }
    std.debug.print("vt_test: hlStats의 cur이 현재 매치만 센다 OK (cells={d} cur={d})\n", .{
        pstats.cells, pstats.cur,
    });
```

- [ ] **Step 2: 검사를 돌린다 (Claude가 실행, 약 3분)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test' 2>&1 | tail -20
```

**기대:**

```
vt_test: 현재 매치와 나머지가 다른 색이다 OK (cur=1+1 other=2)
vt_test: hlStats의 cur이 현재 매치만 센다 OK (cells=4 cur=2)
PASS
```

**`pspans.len`이 2가 아니면** 8번 줄이 뷰포트 맨 위로 안 올라간 것이거나 `n`이
18번 줄 안에서 움직인 것이다. 그때는 실패 출력이 찍는 `span row= x0= x1=
current=` 네 줄을 읽고 어느 줄의 매치인지 먼저 가른다. **`ps` 화면이 5줄이고
8번 줄이 스크롤백에 있다는 것이 전제다.**

- [ ] **Step 3: 커밋 (Claude가 실행)**

```bash
git add terminal/src/vt_test.zig
git commit -m "Check that the two match colours appear side by side"
```

---

## Task 6: 게이트가 볼 수 있게 로그에 숫자를 더한다

**Files:**
- Modify: `terminal/src/main.zig` — `dumpHighlight`(`:446~451`)

- [ ] **Step 1: 넣을 것**

**지울 것** (`main.zig:448~450`)

```zig
    std.debug.print("terminal: find> hl spans={d} cells={d} us={d}\n", .{
        hl.spans, hl.cells, hl.us,
    });
```

**넣을 것**

```zig
    // **`cur=`을 `cells=` 뒤·`us=` 앞에 넣는다**(SP-M0 plan 결정 5).
    // `copy/check.sh`의 검사 16이 `sed -E 's/.*cells=([0-9]+).*/\1/'`로
    // `cells=`를 뽑으므로 그 뒤에 필드를 더하는 것은 안전하지만, **`cells=`를
    // 옮기거나 `cells`를 부분 문자열로 갖는 이름을 쓰면 깨진다.**
    std.debug.print("terminal: find> hl spans={d} cells={d} cur={d} us={d}\n", .{
        hl.spans, hl.cells, hl.cur, hl.us,
    });
```

- [ ] **Step 2: 빌드 (Claude가 실행, 약 3분)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test' 2>&1 | tail -5
```

**기대:** `PASS`. `vt_test`는 로그 문구를 안 보므로 안 흔들린다.

- [ ] **Step 3: 커밋 (Claude가 실행)**

```bash
git add terminal/src/main.zig
git commit -m "Report how many cells the current match painted"
```

---

## Task 7: 게이트의 검사 16을 새 색에 맞춘다

**이 Task가 SP-M0에서 유일하게 "고치는" 게이트 작업이다.** CS-M0도 CS-M1도
더하기만 했다 — 왜 이번에는 못 그러는지는 design 결정 10에 있다.

**Files:**
- Modify: `copy/check.sh` — 검사 16의 양성 판정(`:783~791`)과 음성
  판정(`:800~806`)

- [ ] **Step 1: 양성 판정을 고친다**

**지울 것**

```bash
# **판정.** 마지막 프레임의 셀이 정말 MATCH_BG를 받았다.
#
# 커서가 선 한 칸은 매치 위에서 또 한 번 맞바뀌므로 `fg=705000 bg=FFFFFF`가
# 되고, 나머지는 `fg=FFFFFF bg=705000`이다. 아래는 후자를 센다. vt_test의
# 검사 29가 같은 갈림을 `plain=5 cursor=1`로 확인한다.
HL_STYLED="$(last_frame | grep -acE 'terminal: style> [0-9]+,[0-9]+ fg=FFFFFF bg=705000' || true)"
if [ "$HL_STYLED" -lt 1 ]; then
  echo "--- style lines in the last frame ---"
  last_frame | grep -a 'terminal: style>' | tail -n 20
  report_failure "no cell reached the framebuffer with the match background"
fi
echo "${HL_STYLED} cell(s) reached the framebuffer with bg=705000"
```

**넣을 것**

```bash
# **판정.** 마지막 프레임의 셀이 정말 CURRENT_BG를 받았다.
#
# **SP-M0이 이 자리의 색을 바꿨다.** 2026-08-29 실측으로 이 자리는 `spans=1`,
# 곧 **화면에 보이는 매치가 하나**이고 직전에 `n`으로 그리로 갔으므로 그
# 하나가 곧 현재 매치다. 그래서 여기 칠해지는 것은 `MATCH_BG`가 아니라
# `CURRENT_BG`이고, 옛 `bg=705000`을 그대로 두면 0개가 되어 실패한다.
#
# **두 색이 함께 있는 것은 검사 19가 본다** — 그쪽은 자기 조건을 스스로 만든다.
#
# 커서가 선 한 칸은 매치 위에서 또 한 번 맞바뀌므로 `fg=C08000 bg=FFFFFF`가
# 되고, 나머지는 `fg=FFFFFF bg=C08000`이다. 아래는 후자를 센다. vt_test의
# 검사 29가 같은 갈림을 `plain=5 cursor=1`로 확인한다.
HL_STYLED="$(last_frame | grep -acE 'terminal: style> [0-9]+,[0-9]+ fg=FFFFFF bg=C08000' || true)"
if [ "$HL_STYLED" -lt 1 ]; then
  echo "--- style lines in the last frame ---"
  last_frame | grep -a 'terminal: style>' | tail -n 20
  report_failure "no cell reached the framebuffer with the current-match background"
fi
echo "${HL_STYLED} cell(s) reached the framebuffer with bg=C08000"
```

- [ ] **Step 2: 음성 판정을 두 색으로 넓힌다**

**지울 것**

```bash
if [ "$(last_frame | grep -acE 'bg=705000' || true)" -ne 0 ]; then
```

**넣을 것**

```bash
# **두 색을 함께 본다**(SP-M0). 한 색만 보면 다른 색으로 칠해진 하이라이트가
# 살아남았을 때 이 검사가 그것을 놓친다 — 지금 이 자리는 현재 매치 하나뿐이라
# `bg=705000`만 보면 **아무것도 안 보는 검사**가 된다.
if [ "$(last_frame | grep -acE 'bg=(705000|C08000)' || true)" -ne 0 ]; then
```

- [ ] **Step 3: copy 체인만 돌려 확인한다 (Claude가 실행, 약 8분,
      background process)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/gate.out 2>&1
  echo "chain exit=$?"
  grep -a "cell(s) reached the framebuffer" /tmp/gate.out
  grep -a "the match highlight" /tmp/gate.out
  grep -ah "terminal: find> hl" /tmp/tmp.* | sed -E "s/ us=[0-9]+//" | sort | uniq -c
' > /tmp/sp-m0-chain.out 2>&1
```

**기대:** `chain exit=0`, 그리고

```
5 cell(s) reached the framebuffer with bg=C08000
the match highlight: terminal: find> hl spans=1 cells=6 cur=6 us=…
```

**`cur=6`이 판정의 핵심이다.** 이 자리는 매치가 하나이고 그것이 현재 매치이므로
`cells`와 `cur`이 **같아야** 한다. 다르면 `findCurrentIndex()`가 null을 주고
있다는 뜻이고, 그러면 화면도 옛 색으로 칠해졌을 것이다.

**5인 것도 판정이다.** 여섯이 나오면 커서가 매치의 첫 칸에 안 선 것이다.

- [ ] **Step 4: 커밋 (Claude가 실행)**

```bash
git add copy/check.sh
git commit -m "Point check 16 at the current-match colour"
```

---

## Task 8: 두 색이 함께 있는 것을 게이트가 본다 (검사 19)

**Files:**
- Modify: `copy/check.sh` — 검사 18이 끝난 뒤, "음성 검사: 로그에 NUL이 섞이지
  않았다" **바로 앞**

- [ ] **Step 1: 넣을 것**

```bash
# ── 검사 19: 현재 매치와 나머지가 다른 색이다 (SP-M0) ──────────────────
#
# **이 검사는 자기 조건을 스스로 만든다**(plan 결정 4). 두 색을 함께 보려면
# 매치가 둘 이상 한 화면에 있어야 하는데, 검사 16의 자리는 `spans=1`이라
# (2026-08-29 실측) 거기서는 못 본다. 앞 검사가 남긴 스크롤 위치에 기대면
# 판정이 스크롤에 딸리게 되므로, **needle을 한 줄에 두 번 심는다** — 같은
# 줄이면 뷰포트가 어디에 있든 둘이 함께 보인다.
#
# **`findme`를 쓰면 안 된다.** 검사 15와 17이 `matches=4`를 판정에 쓰고 있어
# 새 매치가 그 숫자를 깨뜨린다. `zq`는 이 화면 어디에도 없고, 검사 18의 `zzz`와도
# 안 겹친다.
#
# **needle이 두 글자인 것에도 이유가 있다.** `style>`는 프레임당 16줄이
# 상한이라(main.zig의 STYLE_DUMP_LIMIT), 긴 needle이면 명령줄과 출력줄의 매치
# 넷이 상한을 넘어 **뒤쪽 색이 안 찍히고 "색이 안 닿았다"로 잘못 읽힌다.**
# 두 글자면 여덟 칸이라 넉넉하다.
#
# **검사 18이 copy mode 안에서 끝났으므로 먼저 나간다.** 안 나가면 아래 타이핑이
# 셸이 아니라 copy 명령으로 먹힌다.
type_keys esc
sleep 1

echo "=== planting a line with two matches on it ==="
type_keys e c h o spc z q spc z q ret
sleep 3

type_keys meta_l-shift-c
sleep 2
type_keys slash z q ret
sleep 3

# **판정.** 매치가 둘 이상 보이고, 그중 현재 매치가 두 칸이다.
#
# `zq`가 명령줄과 출력줄에 각각 둘씩이라 검색은 넷을 찾고, 화면에는 적어도
# 출력줄의 둘이 보인다. 명령줄까지 보이면 넷이다 — **몇인지는 못 박지 않고
# "둘 이상"만 본다.** 프롬프트가 화면 어디에 오는지는 앞 검사들이 남긴 상태에
# 딸린 값이기 때문이다.
HL2="$(grep -a 'terminal: find> hl' "$LOG" | tail -n 1)"
if [ -z "$HL2" ]; then
  report_failure "no find> hl line after searching for zq"
fi
HL2_SPANS=$(echo "$HL2" | sed -E 's/.*spans=([0-9]+).*/\1/')
HL2_CUR=$(echo "$HL2" | sed -E 's/.*cur=([0-9]+).*/\1/')
if [ "$HL2_SPANS" -lt 2 ]; then
  report_failure "expected at least two visible matches, got: ${HL2}"
fi
# **현재 매치는 정확히 하나이고 needle이 두 글자다.** `cur`이 4면 두 매치가
# 함께 현재로 표시된 것이고, 0이면 findCurrentIndex()가 null을 준 것이다 —
# 두 실패가 서로 다른 원인이라 숫자로 갈린다.
if [ "$HL2_CUR" -ne 2 ]; then
  report_failure "expected the current match to cover two cells, got: ${HL2}"
fi
echo "two match colours are live: ${HL2}"

# **판정.** 두 색이 **함께** 프레임버퍼에 닿았다.
#
# `find> hl`은 vt.zig가 센 값이고 이쪽은 그 색이 정말 셀에 닿았는지다. 한 겹만
# 보면 "셌지만 안 칠했다"를 못 잡는다 — 검사 16이 두 겹으로 보는 것과 같은
# 규율이다.
CUR_CELLS="$(last_frame | grep -acE 'terminal: style> [0-9]+,[0-9]+ fg=FFFFFF bg=C08000' || true)"
OTHER_CELLS="$(last_frame | grep -acE 'terminal: style> [0-9]+,[0-9]+ fg=FFFFFF bg=705000' || true)"
if [ "$CUR_CELLS" -lt 1 ] || [ "$OTHER_CELLS" -lt 1 ]; then
  echo "--- style lines in the last frame ---"
  last_frame | grep -a 'terminal: style>' | tail -n 20
  report_failure "expected both colours on screen (current=${CUR_CELLS} other=${OTHER_CELLS})"
fi
echo "both match colours reached the framebuffer (current=${CUR_CELLS} other=${OTHER_CELLS})"
```

- [ ] **Step 2: copy 체인을 돌린다 (Claude가 실행, 약 8분, background process)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/gate.out 2>&1
  echo "chain exit=$?"
  tail -25 /tmp/gate.out
' > /tmp/sp-m0-chain2.out 2>&1
```

**기대:** `chain exit=0`, 그리고 마지막 줄들에

```
two match colours are live: terminal: find> hl spans=… cur=2 …
both match colours reached the framebuffer (current=1 other=…)
CM-M2 check PASS
```

**`current=1`이 맞는 값이다.** 현재 매치는 두 칸인데 첫 칸에 copy 커서가 서서
맞바뀌므로, `fg=FFFFFF bg=C08000`으로 남는 것은 **하나**다. `vt_test`의 검사
39가 같은 갈림을 `cur=1+1`로 본다.

**실패한다면 어디를 먼저 보나:**

| 증상 | 뜻 |
|---|---|
| `no find> hl line after searching for zq` | `/zq`가 프롬프트에 안 도착했다. `find> type needle=zq len=2`를 먼저 본다 |
| `expected at least two visible matches` | 두 매치가 한 화면에 안 보인다. `echo zq zq`가 한 줄에 안 들어갔거나 뷰포트가 그 줄을 안 덮는다 |
| `cur=4` | 현재 매치 표식이 두 span에 붙었다. `findSpans`의 `ci == mi` 비교를 본다 |
| `cur=0` | `findCurrentIndex()`가 null이다. `refreshMatches()`가 `select()` 뒤인지 본다 |

- [ ] **Step 3: 커밋 (Claude가 실행)**

```bash
git add copy/check.sh
git commit -m "Check both match colours on screen at once"
```

---

## Task 9: 루트 게이트와 마무리

- [ ] **Step 1: 루트 게이트를 세 번 돈다 (Claude가 실행, 약 48분,
      background process)**

```bash
for i in 1 2 3; do
  { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
      bash check.sh > /tmp/gate-sp-m0-$i.out 2>&1 ; } 2> /tmp/gate-sp-m0-$i.time
done
```

**기대:** 여덟 체인이 전부 3/3이고, 시간이 **16분 01초~11초** 언저리다(GL-M3
직후의 기준선).

**값이 기준선에서 크게 벗어나면 코드를 의심하기 전에 기계를 먼저 의심한다.**
TR-M2 때 처음 잰 값이 6시간 12분이었고 원인은 Chrome의 영상 재생이었다.

**`skipping make`가 23회인 것도 함께 본다.** 24회면 `clean()`이 지운 자리에서도
건너뛴 것이라 잘못이다.

```bash
grep -c 'skipping make' /tmp/gate-sp-m0-1.out
```

- [ ] **Step 2: 못 푼 것 하나를 로그에서 확인한다 (Claude가 실행)**

**검사 15의 주석과 실측이 어긋나 있다.** 주석은 "`/`는 표적 2의 출력줄로 가고
`n`은 **그 위의 명령줄**로 올라간다"고 적었는데, 같은 검사가 찍는 이동 폭이
`row 312 -> 210`으로 **102줄**이다. 명령줄과 출력줄은 붙어 있으므로 1이어야
한다. **둘 중 하나가 틀렸고 아직 어느 쪽인지 모른다.**

SP-M0의 판정에는 영향이 없다(그 검사는 "위로 갔다"만 본다). 그러나 **SP-M1의
`[3/12]`는 이것에 딸린다** — `n`이 정말 매치를 건너뛴다면 번호가 1에서 3으로
뛴다. 그래서 이 게이트 로그에서 값을 하나 더 읽어 둔다.

```bash
grep -a 'n moved the cursor up the scrollback' /tmp/gate-sp-m0-1.out
```

**읽고 나서 판단만 기록한다.** 여기서 고치지 않는다 — SP-M1의 design 질문이다.

- [ ] **Step 3: 문서와 기억을 갱신한다 (Claude가 실행)**

- `docs/superpowers/specs/2026-08-29-tars-search-position-design.md`의
  `Status:`를 "SP-M0 완료, SP-M1 미착수"로 바꾸고, **결정 10의 열린 질문에 답을
  적는다**(검사 19가 자기 조건을 만드는 길로 갔다는 것).
- `docs/decisions/project_search_position.md`를 새로 만들고 `MEMORY.md`에 한 줄
  더한다.
- `HANDOFF.md`를 SP-M0 기준으로 다시 쓴다. **`main.zig`의 낡은 줄 번호도 이때
  고친다**(실측 5).
- 새 로그 문구 `terminal: find> hl … cur=…`를 HANDOFF의 "로그 문구는 두 곳에
  중복된다" 목록에 더한다.

- [ ] **Step 4: 커밋 (Claude가 실행)**

```bash
git add docs/ MEMORY.md HANDOFF.md
git commit -m "Close out SP-M0"
```

---

## 자기 점검 (계획을 다 쓰고 나서)

**1. design 항목이 전부 Task로 덮였나.**

| design | Task |
|---|---|
| 결정 1(인덱스 창구, 검사로 뜻 고정) | Task 1 · Task 2 |
| 결정 2(`RowSpan.current`, `cur` 셈) | Task 3 |
| 결정 3(겹치면 현재가 이긴다) | Task 4 Step 2 |
| 결정 4(`CURRENT_BG`) | Task 4 Step 1 |
| 결정 8(로그 `cur=`) | Task 6 |
| 결정 9(새 체인 없이 `copy/check.sh`) | Task 7 · Task 8 |
| 결정 10(검사 16 수정 + 검사 19 추가) | Task 7 · Task 8 |
| 위험 1(매치가 있는데 `selected`가 null) | Task 1의 `orelse` 넷 |
| 위험 2(`idx`가 범위를 벗어남) | Task 1의 `sel.idx >= m.len` |
| 위험 4(게이트 시간) | Task 9 Step 1 |

**결정 5·6·7은 SP-M1의 것이라 이 계획에 없다.** 그것이 milestone을 가른 선이다.

**2. 이름이 앞뒤로 같나.** `findCurrentIndex` · `RowSpan.current` ·
`HlStats.cur` · `CURRENT_BG` · `cur=` 다섯이 Task 1·3·4·6과 검사들에서 같은
철자로 쓰였다.

**3. 남은 빈칸.** 없다. 처음에는 Task 4에 "검사 30이 함께 깨질 수 **있다**"라고
짐작으로 적었는데, 계획을 다 쓴 뒤 `vt_test.zig:960~995`를 직접 읽어
**확정으로 바꿨다** — 검사 30은 반드시 깨지고(Step 5), 검사 31은 안 깨지지만
**아무것도 안 보는 검사가 되므로** 함께 넓힌다(Step 6).

**그래도 plan이 틀릴 수 있다.** CS-M0에서 두 번 드러났다 — 매치 셀 수가 6이
아니라 5였고, `RowSpan`을 struct의 필드 사이에 둔 배치가 컴파일되지 않았다.
**계획을 그대로 밟되 실측이 다르면 실측이 답이다.**

**4. 이 계획이 손대는 파일은 넷이다.** `terminal/src/vt.zig`(Task 1·3·4) ·
`terminal/src/vt_test.zig`(Task 2·4·5) · `terminal/src/main.zig`(Task 6) ·
`copy/check.sh`(Task 7·8). **`input.zig`도 `input_test.zig`도 안 건드린다** —
SP-M0은 키의 뜻을 하나도 안 바꾸기 때문이고, CS-M0·CS-M1이 그랬던 것과 같다.
