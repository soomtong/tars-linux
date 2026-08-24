# TARS Copy Mode CM-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** `Cmd+Shift+C`로 copy mode에 들어가서 `hjkl`(과 방향키)로 커서를 옮기고
`Esc`로 나온다. **모드 안에서는 어떤 키도 PTY로 나가지 않는다.** 게이트가 그것을
음성 검사로 증명하고, 나온 뒤에 다시 나간다는 대조군까지 본다.

**Design doc:** `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`
(결정 1·2·3·4·7·8이 이 milestone의 몫이다. 선택과 클립보드를 다루는 결정 5·6은
CM-M1, 붙여넣기 결정 9는 CM-M2다. design은 승인되어 있으므로 다시 논의하지 않는다.)

**Tech Stack:** Zig 0.16, libghostty-vt(`RenderState.cursor.viewport` ·
`Terminal.scrollViewport`), evdev, DRM dumb buffer, QEMU monitor `sendkey`,
bash 게이트 스크립트

---

## 착수 전에 이미 확정된 사실 (2026-08-24 실측)

**다시 조사하지 않는다.** 프로브는 `/tmp/probe.zig`를 `terminal/src/vt_test.zig`
자리에 마운트해 `zig build test`로 돌렸다(저장소는 안 건드린다).

1. **`screens.active`는 이미 포인터다.** `&screen.term.screens.active`라고 쓰면
   `**Screen`이 되어 `does not support field access`로 컴파일이 막힌다. CM-M0은
   이 필드를 안 쓰지만 CM-M1이 쓴다.
2. **`RenderState.rows`·`cols`는 `u16`이다**(`size.CellCountInt = u16`,
   `render.zig:82-83`). `cursor.viewport`도 같은 폭의 좌표다.
3. **`main.zig:450`의 `scrollToBottom()`이 가지치기를 구조적으로 막고 있었다.**
   그 자리의 주석이 부수 효과로 적어 둔 것이고, CM-M0이 그 호출을 억제하면서
   창이 열린다(design 위험 1).
4. **`terminal: key>` 줄은 PTY로 바이트가 나갈 때만 찍힌다**(`main.zig:402-409`,
   `if (keys.bytes.len > 0)` 안에 있다). **이 성질이 CM-M0 음성 검사의 도구다** —
   모드 안에서 키를 아무리 쳐도 이 줄이 안 늘어나는 것으로 "PTY로 안 샌다"를 볼
   수 있다. 화면 내용만 보는 것보다 정확하다.

## 이번에 정하는 것 넷 (design doc이 안 정한 자리)

### 1. `Copy` enum은 CM-M0이 쓰는 여섯 개만 먼저 만든다

design 결정 2의 코드 조각은 `select_char`·`yank`·`paste`까지 적었지만, 지금
넣으면 `main.zig`의 `switch`가 죽은 가지 셋을 갖거나 `else => {}`로 열려야 한다.
**`else`로 열어 두면 CM-M1에서 variant를 더했을 때 배선을 잊어도 컴파일이
통과한다.** 그래서 M0은 여섯 개만 만들고 switch를 닫아 둔다 — M1이 variant를
더하는 순간 컴파일러가 배선할 자리를 알려준다.

### 2. 방향키도 `hjkl`과 같이 받는다

design 결정 4의 표에는 `hjkl`만 있지만, `project_copy_mode`가 기록한 원래 요청은
**"커서 키로 이동하고"**였다. 표 네 줄을 더하는 비용이고 검사도 같은 모양이라
둘 다 받는다.

### 3. copy mode 중에는 셸 커서를 그리지 않는다

반전된 셀이 둘이면 게이트가 어느 것이 copy 커서인지 못 가른다. copy mode 동안
셸 커서 반전을 끄고 copy 커서만 반전한다. 모드를 나가면 저절로 돌아온다.

### 4. `scrollToBottom` 억제는 코드만 넣고 게이트는 CM-M2에서 본다

게이트가 이 분기를 밟으려면 **copy mode 중에 PTY 출력이 도착해야** 하는데, 모드
안에서는 셸에 아무것도 보낼 수 없어서 출력을 만들 방법이 없다. 백그라운드 작업을
띄우는 방법은 게이트를 취약하게 만든다. CM-M2에서 붙여넣기가 출력을 만들므로
그때 본다. **못 보는 것을 못 본다고 여기 적어 둔다**(`project_gate_chain_composition`).

---

## Task 1: `input.zig`에 모드와 `Action.copy`를 넣는다

**Files:**
- Modify: `terminal/src/input.zig`
- Test: `terminal/src/input_test.zig`

### Step 1: `Action`에 variant를 더하고 `Copy`를 만든다

`input.zig:160-165`의 `Action` 정의를 **지울 것**:

```zig
pub const Action = union(enum) {
    /// PTY로 보낼 바이트열. 빈 슬라이스는 "보낼 것이 없다"는 뜻이다.
    bytes: []const u8,
    /// 우리가 처리할 동작. **PTY로 보내지 않는다.**
    scroll: Scroll,
};
```

**넣을 것**:

```zig
pub const Action = union(enum) {
    /// PTY로 보낼 바이트열. 빈 슬라이스는 "보낼 것이 없다"는 뜻이다.
    bytes: []const u8,
    /// 우리가 처리할 동작. **PTY로 보내지 않는다.**
    scroll: Scroll,
    /// copy mode의 명령. 이것도 PTY로 보내지 않는다.
    copy: Copy,
};

/// copy mode 안에서 키가 만드는 명령.
///
/// design 결정 2의 조각은 `select_char`·`yank`·`paste`까지 적었지만 CM-M0은
/// 여섯 개만 만든다. **variant를 미리 만들어 두면 `main.zig`의 switch가
/// `else`로 열려야 하고, 그러면 CM-M1에서 배선을 잊어도 컴파일이 통과한다.**
/// 지금 닫아 두면 variant를 더하는 순간 컴파일러가 배선할 자리를 알려준다.
pub const Copy = enum {
    enter,
    exit,
    left,
    down,
    up,
    right,
};
```

### Step 2: `Keys`에 `copies`를 더한다

`input.zig:168-174`의 `Keys` 정의를 **지울 것**:

```zig
pub const Keys = struct {
    bytes: []const u8,
    /// **순서대로 적용해야 한다.** PageUp을 누르고 있으면 자동 반복이 한
    /// 번의 read에 여러 개를 실어 오는데, 마지막 하나만 보면 몇 번을 눌렀든
    /// 한 화면만 올라간다.
    scrolls: []const Scroll,
};
```

**넣을 것**:

```zig
pub const Keys = struct {
    bytes: []const u8,
    /// **순서대로 적용해야 한다.** PageUp을 누르고 있으면 자동 반복이 한
    /// 번의 read에 여러 개를 실어 오는데, 마지막 하나만 보면 몇 번을 눌렀든
    /// 한 화면만 올라간다.
    scrolls: []const Scroll,
    /// copy mode 명령도 같은 이유로 순서대로 모은다. `j`를 누르고 있으면
    /// 자동 반복이 여러 개를 실어 오고, 그만큼 내려가야 한다.
    copies: []const Copy,
};
```

### Step 3: `State`에 모드와 저장소를 더한다

`input.zig:278`의 `scrolls` 필드 **바로 뒤에 넣을 것**(지울 것 없음):

```zig
    scrolls: [8]Scroll = undefined,

    /// 한 번의 read에서 나온 copy 명령의 저장소. `seq`·`scrolls`와 같은
    /// 이유로 힙을 쓰지 않는다.
    copies: [8]Copy = undefined,

    /// 지금 키를 어떻게 해석하는가. **모드가 `input`에 있는 이유가 design
    /// 결정 1이다** — "이 키를 어떻게 해석하는가"는 번역의 문제이고, 선택
    /// 영역이 `vt`에 있는 것은 그것이 화면 상태이기 때문이다.
    mode: Mode = .normal,
```

그리고 `State` 정의 안, 위 필드들 아래에 **넣을 것**:

```zig
    pub const Mode = enum { normal, copy };
```

### Step 4: `chord()`의 Meta 분기에 진입키를 넣는다

`input.zig:367-381`의 Meta 분기를 **지울 것**:

```zig
        if (self.metaed()) {
            // Cmd 계열은 제어 문자 한 바이트다. 0x01이 beginning-of-line인
            // 이유는 그것이 readline의 기본 바인딩이기 때문이지 Cmd와 A
            // 사이에 무슨 관계가 있어서가 아니다.
            return switch (code) {
```

**넣을 것**:

```zig
        if (self.metaed()) {
            // copy mode 진입(CM-M0). **Meta 분기 안에서 Shift를 한 번 더 보는
            // 예외가 여기 하나뿐이어야 한다**(design 위험 2). iTerm2의 copy
            // mode 진입키와 같은 자리를 고른 대가다.
            //
            // 모드를 여기서 바로 세우고 나가는 이유는, 이 뒤에 오는 키들이
            // handleKey 앞쪽의 copy 분기로 빠져야 하기 때문이다.
            if (self.shifted() and code == c.KEY_C) {
                self.mode = .copy;
                return .{ .copy = .enter };
            }
            // Cmd 계열은 제어 문자 한 바이트다. 0x01이 beginning-of-line인
            // 이유는 그것이 readline의 기본 바인딩이기 때문이지 Cmd와 A
            // 사이에 무슨 관계가 있어서가 아니다.
            return switch (code) {
```

### Step 5: `handleKey`에 copy 분기를 넣는다

`input.zig:462`의 `if (value == 0) return nothing;` **바로 뒤에 넣을 것**(지울 것
없음):

```zig
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return nothing;

        // 1.5번 단계 — copy mode(design 결정 3). **아는 키만 명령이 되고
        // 나머지는 전부 삼킨다.** "모르는 키는 흘려보낸다"로 하면 모드 안에서
        // 친 글자가 셸에 도착하는 사고가 조용히 나고, 그것이 이 milestone의
        // 음성 검사 대상이다.
        //
        // chord()보다 **앞**이라 모드 안에서는 Cmd 조합도 전부 삼켜진다.
        // CM-M1의 `Cmd+C`와 CM-M2의 `Cmd+V`는 chord()가 아니라 이 표에
        // 들어와야 한다.
        //
        // 방향키를 함께 받는 이유는 project_copy_mode가 기록한 원래 요청이
        // "커서 키로 이동하고"였기 때문이다.
        if (self.mode == .copy) {
            switch (code) {
                c.KEY_ESC => {
                    self.mode = .normal;
                    return .{ .copy = .exit };
                },
                c.KEY_H, c.KEY_LEFT => return .{ .copy = .left },
                c.KEY_J, c.KEY_DOWN => return .{ .copy = .down },
                c.KEY_K, c.KEY_UP => return .{ .copy = .up },
                c.KEY_L, c.KEY_RIGHT => return .{ .copy = .right },
                else => return nothing,
            }
        }
```

### Step 6: `readKeys`가 copy 명령을 모은다

`input.zig:508-542`의 `readKeys` 본문에서 **지울 것**:

```zig
    const n = read(fd, &raw, raw.len);
    if (n <= 0) return .{ .bytes = out[0..0], .scrolls = self.scrolls[0..0] };

    const count = @as(usize, @intCast(n)) / ev_size;
    var written: usize = 0;
    var scrolled: usize = 0;
    var i: usize = 0;
```

**넣을 것**:

```zig
    const n = read(fd, &raw, raw.len);
    if (n <= 0) return .{
        .bytes = out[0..0],
        .scrolls = self.scrolls[0..0],
        .copies = self.copies[0..0],
    };

    const count = @as(usize, @intCast(n)) / ev_size;
    var written: usize = 0;
    var scrolled: usize = 0;
    var copied: usize = 0;
    var i: usize = 0;
```

같은 함수에서 **지울 것**:

```zig
            .scroll => |s| if (scrolled < self.scrolls.len) {
                self.scrolls[scrolled] = s;
                scrolled += 1;
            },
        }
    }
    return .{ .bytes = out[0..written], .scrolls = self.scrolls[0..scrolled] };
```

**넣을 것**:

```zig
            .scroll => |s| if (scrolled < self.scrolls.len) {
                self.scrolls[scrolled] = s;
                scrolled += 1;
            },
            // 스크롤과 같은 이유로 순서대로 모은다. 넘치면 버리는 것도 같다.
            .copy => |cmd| if (copied < self.copies.len) {
                self.copies[copied] = cmd;
                copied += 1;
            },
        }
    }
    return .{
        .bytes = out[0..written],
        .scrolls = self.scrolls[0..scrolled],
        .copies = self.copies[0..copied],
    };
```

### Step 7: 검사를 먼저 깨뜨린다 — `input_test.zig`의 헬퍼를 고친다

`Action`에 variant가 늘었으므로 `expectCtx`의 `switch`가 **컴파일 에러가 난다.**
이것이 의도된 신호다 — 새 동작이 조용히 무시되지 않는다.

`input_test.zig:31-50` 근처의 `expectCtx` 안, `.scroll` 팔 **뒤에 넣을 것**:

```zig
        .copy => |cmd| {
            std.debug.print(
                "FAIL: code={d} value={d} -> got copy .{s}, want bytes {any}\n",
                .{ code, value, @tagName(cmd), want },
            );
            return error.UnexpectedCopy;
        },
```

### Step 8: copy mode 검사 헬퍼를 더한다

`input_test.zig`의 `expectCtx` 정의 **바로 뒤에 넣을 것**:

```zig
/// copy 명령이 나오기를 기대한다. **바이트가 오면 실패다** — 그것이 정확히
/// "모드 안에서 키가 PTY로 샌다"는 사고이기 때문이다.
fn expectCopy(state: *input.State, code: u16, want: input.Copy) !void {
    switch (state.handleKey(code, 1, .{})) {
        .copy => |cmd| {
            if (cmd == want) return;
            std.debug.print(
                "FAIL: code={d} -> got copy .{s}, want copy .{s}\n",
                .{ code, @tagName(cmd), @tagName(want) },
            );
            return error.UnexpectedCopyCommand;
        },
        .bytes => |bytes| {
            std.debug.print(
                "FAIL: code={d} -> got {d} byte(s) {any}, want copy .{s}\n",
                .{ code, bytes.len, bytes, @tagName(want) },
            );
            return error.LeakedToPty;
        },
        .scroll => |s| {
            std.debug.print(
                "FAIL: code={d} -> got scroll .{s}, want copy .{s}\n",
                .{ code, @tagName(s), @tagName(want) },
            );
            return error.UnexpectedScroll;
        },
    }
}
```

### Step 9: 검사 여섯을 더한다

`input_test.zig`의 `main` 함수 **맨 끝**, 마지막 `std.debug.print`/`PASS` 출력
**앞에 넣을 것**:

```zig
    // ── CM-M0: copy mode ────────────────────────────────────────────────
    //
    // 검사 1. 대조군. 모드에 들어가기 전의 `h`는 평범한 글자다. 이것이
    // 없으면 아래 검사 3이 "원래부터 h가 안 나갔다"로도 통과한다.
    var cm: input.State = .{};
    try expect(&cm, K.KEY_H, 1, "h");

    // 검사 2. Cmd+Shift+C가 모드를 연다.
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    if (cm.mode != .copy) {
        std.debug.print("FAIL: Cmd+Shift+C did not switch the mode\n", .{});
        return error.ModeNotEntered;
    }
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");

    // 검사 3. 모드 안에서 hjkl과 방향키가 명령이 된다.
    try expectCopy(&cm, K.KEY_H, .left);
    try expectCopy(&cm, K.KEY_J, .down);
    try expectCopy(&cm, K.KEY_K, .up);
    try expectCopy(&cm, K.KEY_L, .right);
    try expectCopy(&cm, K.KEY_LEFT, .left);
    try expectCopy(&cm, K.KEY_DOWN, .down);
    try expectCopy(&cm, K.KEY_UP, .up);
    try expectCopy(&cm, K.KEY_RIGHT, .right);

    // 검사 4. **모르는 키는 삼킨다**(design 결정 3). 게이트의 음성 검사와
    // 같은 사실을 여기서 먼저 본다.
    try expect(&cm, K.KEY_Q, 1, "");
    try expect(&cm, K.KEY_W, 1, "");
    try expect(&cm, K.KEY_E, 1, "");
    try expect(&cm, K.KEY_R, 1, "");
    try expect(&cm, K.KEY_T, 1, "");
    try expect(&cm, K.KEY_ENTER, 1, "");

    // 검사 5. Cmd 조합도 모드 안에서는 chord()에 닿지 않는다. 모드 밖이라면
    // Cmd+←가 0x01(beginning-of-line)이 되지만, 안에서는 copy 표가 먼저다.
    // **CM-M1의 Cmd+C와 CM-M2의 Cmd+V가 chord()가 아니라 copy 표에 들어와야
    // 하는 이유가 이것이다.**
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expectCopy(&cm, K.KEY_LEFT, .left);
    try expect(&cm, K.KEY_LEFTMETA, 0, "");

    // 검사 6. Esc가 모드를 닫고, 닫힌 뒤에는 h가 다시 글자가 된다.
    // **이 대조군이 없으면 "영영 못 나온다"도 통과한다.**
    try expectCopy(&cm, K.KEY_ESC, .exit);
    if (cm.mode != .normal) {
        std.debug.print("FAIL: Esc did not leave copy mode\n", .{});
        return error.ModeNotLeft;
    }
    try expect(&cm, K.KEY_H, 1, "h");
    std.debug.print("input_test: copy mode OK\n", .{});
```

### Step 10: 호스트 검사를 돌린다 (Claude가 실행)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: `input_test: copy mode OK`가 찍히고 `PASS`. 실패하면 `expectCopy`가 어떤
키에서 무엇을 받았는지 찍으므로 그 줄을 읽고 고친다.

### Step 11: 커밋 (Claude가 실행)

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Teach the key pipeline about a copy mode"
```

---

## Task 2: `vt.zig`에 copy 커서를 넣는다

**Files:**
- Modify: `terminal/src/vt.zig`
- Test: `terminal/src/vt_test.zig`

### Step 1: 커서 상태와 조작 함수를 넣는다

`vt.zig`의 `Screen` 안, `state: ghostty_vt.RenderState,` **바로 뒤에 넣을 것**:

```zig
    /// copy mode의 커서. null이면 copy mode가 아니다.
    ///
    /// **뷰포트 좌표다**(0이 화면 맨 윗줄). 절대 행이 아닌 이유는 이동이
    /// 화면 위의 일이기 때문이다 — 뷰포트가 한 줄 올라가면 커서는 화면의
    /// 같은 자리에 남고, 그래서 가리키는 내용이 한 줄 위가 된다. 그것이
    /// 화면 끝에서 계속 움직였을 때 사람이 기대하는 동작이다.
    ///
    /// 앵커(선택의 시작점)는 여기 두지 않는다. CM-M1이 라이브러리의 tracked
    /// selection에 맡긴다(design 결정 5).
    copy_cursor: ?Cursor = null,
```

`Screen` 정의 안, `Scrollbar` 선언 **앞에 넣을 것**:

```zig
    /// 뷰포트 좌표 한 쌍. 로그와 검사가 함께 쓴다.
    pub const Cursor = struct { x: u16, y: u16 };

    /// copy mode에 들어간다. 커서는 셸 커서 자리에서 시작한다.
    ///
    /// 셸 커서가 뷰포트 밖에 있으면(스크롤백을 올려다보는 중이면) 화면 맨
    /// 왼쪽 위에서 시작한다 — 안 보이는 자리에 커서를 두면 사람이 무엇을
    /// 움직이는지 알 수 없다.
    pub fn copyEnter(self: *Screen) void {
        self.copy_cursor = if (self.state.cursor.viewport) |vp|
            .{ .x = vp.x, .y = vp.y }
        else
            .{ .x = 0, .y = 0 };
    }

    /// copy mode를 나간다.
    pub fn copyExit(self: *Screen) void {
        self.copy_cursor = null;
    }

    pub fn copyActive(self: *const Screen) bool {
        return self.copy_cursor != null;
    }

    pub fn copyCursor(self: *const Screen) ?Cursor {
        return self.copy_cursor;
    }

    /// 커서를 옮긴다. **화면 끝을 넘으면 뷰포트가 대신 움직인다.**
    ///
    /// 좌우는 화면 안에서 멈춘다(줄을 넘나들지 않는다). 위아래는 화면 끝에서
    /// 뷰포트를 한 줄 밀고 커서는 그 끝에 남는다 — 스크롤백을 거슬러 올라가며
    /// 훑는 동작이 이것으로 만들어진다.
    ///
    /// `cells()`보다 먼저 불려도 안전하다. `state.rows`·`cols`는 init에서
    /// 준 격자 크기이고 매 프레임 같은 값이다.
    pub fn copyMove(self: *Screen, dx: i32, dy: i32) void {
        const cur = self.copy_cursor orelse return;
        if (self.state.cols == 0 or self.state.rows == 0) return;

        const max_x: i32 = @as(i32, self.state.cols) - 1;
        const max_y: i32 = @as(i32, self.state.rows) - 1;

        var x: i32 = @as(i32, cur.x) + dx;
        if (x < 0) x = 0;
        if (x > max_x) x = max_x;

        var y: i32 = @as(i32, cur.y) + dy;
        if (y < 0) {
            self.scrollByRows(-1);
            y = 0;
        } else if (y > max_y) {
            self.scrollByRows(1);
            y = max_y;
        }

        self.copy_cursor = .{ .x = @intCast(x), .y = @intCast(y) };
    }
```

### Step 2: `cells()`가 copy 커서를 반전한다

`vt.zig:163-171`의 커서 처리를 **지울 것**:

```zig
                // 커서는 inverse와 **같은 연산**이다(design 결정 2). 그래서
                // 렌더러는 커서라는 것도 배우지 않는다. 뷰포트 밖으로
                // 나가면 viewport가 null이므로 TR-M2가 이 자리를 다시
                // 손대지 않아도 된다.
                if (cursor) |vp| {
                    if (@as(usize, vp.x) == x and @as(usize, vp.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }
```

**넣을 것**:

```zig
                // 커서는 inverse와 **같은 연산**이다(design 결정 2). 그래서
                // 렌더러는 커서라는 것도 배우지 않는다. 뷰포트 밖으로
                // 나가면 viewport가 null이므로 TR-M2가 이 자리를 다시
                // 손대지 않아도 된다.
                //
                // **copy mode 중에는 셸 커서를 그리지 않는다**(CM-M0). 반전된
                // 셀이 둘이면 게이트가 어느 것이 copy 커서인지 못 가른다.
                if (self.copy_cursor) |cc| {
                    if (@as(usize, cc.x) == x and @as(usize, cc.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                } else if (cursor) |vp| {
                    if (@as(usize, vp.x) == x and @as(usize, vp.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }
```

### Step 3: `vt_test.zig`에 검사 넷을 더한다

`vt_test.zig`의 `main` 함수 **맨 끝에 넣을 것**:

```zig
    // ── CM-M0: copy 커서 ────────────────────────────────────────────────
    //
    // 이 검사들은 앞의 스크롤백 검사가 만들어 둔 화면 위에서 돈다.

    // 검사 1. 들어가면 커서가 생기고, 나가면 사라진다.
    if (screen.copyActive()) {
        std.debug.print("FAIL: copy mode was active before we entered\n", .{});
        return error.CopyActiveTooEarly;
    }
    screen.copyEnter();
    const entered = screen.copyCursor() orelse return error.NoCopyCursor;
    std.debug.print("copy cursor starts at {d},{d}\n", .{ entered.y, entered.x });

    // 검사 2. 반전. 커서가 앉은 셀은 fg와 bg가 맞바뀌어 나온다.
    //
    // **글자가 없는 셀이어도 나와야 한다** — 반전된 배경이 그릴 것이기
    // 때문이다(TR design 결정 3). 그래서 좌표를 화면 왼쪽 위로 옮겨 놓고 본다.
    screen.copyExit();
    screen.copyEnter();
    while (screen.copyCursor().?.x > 0) screen.copyMove(-1, 0);
    while (screen.copyCursor().?.y > 0) screen.copyMove(0, -1);
    var cbuf: [8192]vt.CellGlyph = undefined;
    const with_cursor = try screen.cells(&cbuf);
    var found = false;
    for (with_cursor) |cell| {
        if (cell.row != 0 or cell.col != 0) continue;
        found = true;
        if (cell.bg != screen.defaultFg()) {
            std.debug.print(
                "FAIL: cell 0,0 bg={X} but the copy cursor should have made it {X}\n",
                .{ cell.bg, screen.defaultFg() },
            );
            return error.CursorNotInverted;
        }
    }
    if (!found) {
        std.debug.print("FAIL: cell 0,0 is missing while the copy cursor sits on it\n", .{});
        return error.CursorCellMissing;
    }

    // 검사 3. 맨 윗줄에서 위로 더 가면 **뷰포트가 대신 올라간다.**
    const before = screen.scrollbar().offset;
    screen.copyMove(0, -1);
    const after = screen.scrollbar().offset;
    if (screen.copyCursor().?.y != 0) {
        std.debug.print("FAIL: the cursor left row 0 instead of moving the viewport\n", .{});
        return error.CursorEscapedTop;
    }
    if (after >= before) {
        std.debug.print(
            "FAIL: viewport did not move up (offset {d} -> {d})\n",
            .{ before, after },
        );
        return error.ViewportDidNotFollow;
    }
    std.debug.print("copy cursor pushed the viewport {d} -> {d}\n", .{ before, after });

    // 검사 4. 나가면 커서가 사라지고 셸 커서가 돌아온다.
    screen.copyExit();
    if (screen.copyActive()) {
        std.debug.print("FAIL: copy mode stayed active after copyExit\n", .{});
        return error.CopyStillActive;
    }
    std.debug.print("vt_test: copy cursor OK\n", .{});
```

**주의.** 검사 3은 앞선 스크롤백 검사가 history를 만들어 둔 상태여야 뜻이 있다.
`vt_test`의 기존 마지막 상태가 바닥이면 `offset`이 이미 최대라 위로 갈 자리가
있다 — 그것이 이 검사의 전제이고, 만약 화면이 history 없이 비어 있으면
`scrollByRows(-1)`이 아무 일도 못 해서 검사 3이 실패한다. 그때는 검사 3 앞에
`screen.feed("x\r\n" ** 100)`으로 history를 만들고 다시 돌린다.

### Step 4: 호스트 검사를 돌린다 (Claude가 실행)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: `copy cursor starts at R,C` · `copy cursor pushed the viewport N -> M` ·
`vt_test: copy cursor OK` 세 줄이 찍히고 `PASS`.

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Give the screen a copy-mode cursor of its own"
```

---

## Task 3: `main.zig`에 배선과 로그를 넣는다

**Files:**
- Modify: `terminal/src/main.zig`

### Step 1: `dumpCopy`를 만든다

`main.zig`의 `dumpScroll` 함수 **바로 뒤에 넣을 것**:

```zig
/// copy mode에서 무슨 일이 일어났는지를 찍는다.
///
/// **게이트가 모드 안을 볼 수 있는 유일한 창구다.** 화면만 보면 "모드에
/// 들어갔다"와 "아무 일도 안 일어났다"가 구분되지 않는다 — 모드에 들어가도
/// 화면에서 달라지는 것은 커서 반전 하나뿐이기 때문이다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8). 기존
/// 체인들과 같은 구조이고, **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpCopy(screen: *vt.Screen, what: []const u8) void {
    if (screen.copyCursor()) |cc| {
        std.debug.print("terminal: copy> {s} row={d} col={d}\n", .{ what, cc.y, cc.x });
    } else {
        // exit에는 좌표가 없다. 커서가 이미 사라졌기 때문이다.
        std.debug.print("terminal: copy> {s}\n", .{what});
    }
}
```

### Step 2: 키 루프에 copy 배선을 넣는다

`main.zig:418-426`의 스크롤 루프 **바로 뒤에 넣을 것**(지울 것 없음):

```zig
            // copy mode 명령도 PTY로 나가지 않는다(design 결정 3). 스크롤과
            // 같은 이유로 순서대로 돈다 — j를 누르고 있으면 자동 반복이 여러
            // 개를 실어 온다.
            for (keys.copies) |cmd| {
                switch (cmd) {
                    .enter => screen.copyEnter(),
                    .exit => screen.copyExit(),
                    .left => screen.copyMove(-1, 0),
                    .down => screen.copyMove(0, 1),
                    .up => screen.copyMove(0, -1),
                    .right => screen.copyMove(1, 0),
                }
                dumpCopy(screen, @tagName(cmd));
                needs_redraw = true;
            }
```

### Step 3: copy mode 중에는 바닥으로 안 내려간다

`main.zig:450`을 **지울 것**:

```zig
            screen.scrollToBottom();
```

**넣을 것**:

```zig
            // **copy mode 중에는 억제한다**(CM-M0). 백그라운드 출력이 한 줄만
            // 도착해도 사람이 올라가서 보고 있던 자리가 화면 밖으로 튕기기
            // 때문이다.
            //
            // 그 대가로 위 주석이 말한 창이 열린다 — 뷰포트가 history에
            // 머무는 동안 가지치기가 일어날 수 있게 된다(design 위험 1).
            // copy mode 중에 1000줄이 쏟아져야 닿는 자리라 게이트로 만들지
            // 않았고, CM-M1이 선택이 무효가 됐는지를 매 프레임 보는 방어를
            // 넣는다.
            if (!screen.copyActive()) screen.scrollToBottom();
```

### Step 4: 빌드 (Claude가 실행)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

기대: 빌드 성공, 호스트 검사 `PASS`.

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/main.zig
git commit -m "Wire copy-mode commands into the terminal loop"
```

---

## Task 4: 게이트 체인 `copy/check.sh`를 만든다

**Files:**
- Create: `copy/check.sh`

### Step 1: 스크립트를 만든다

`render/check.sh`의 앞부분(빌드 단계 · `cleanup` · `type_keys` · QEMU 기동 ·
monitor 접속)과 **같은 뼈대**를 쓴다. 100줄이 넘으므로 Claude가 `/tmp`에 원본을
만들어 `diff`로 보인 뒤 사용자가 `cp`로 넣는다.

전체 내용:

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# CM 체인 — copy mode.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Cmd+Shift+C를 누른다
#   → evdev가 KEY_LEFTMETA·KEY_LEFTSHIFT·KEY_C를 올린다
#   → input.zig의 chord()가 그것을 .copy = .enter로 바꾸고 모드를 연다
#   → main.zig가 vt.zig의 copy 커서를 만들고 copy> 줄을 찍는다
#   → 모드 안에서 친 키가 **PTY로 나가지 않는다**
#   → Esc로 나오면 다시 나간다
#
# **음성 검사가 이 체인의 값이다.** "모드에 들어갔다"만 보면 키를 삼키는지
# 아닌지는 아무것도 증명되지 않는다 — 그리고 키가 새는 것이 이 기능의 가장
# 흔한 실패 방식이다.
#
# 음성 검사의 도구는 `terminal: key>` 줄이다. 그 줄은 PTY로 바이트가 나갈
# 때만 찍히므로(main.zig의 `if (keys.bytes.len > 0)`), 줄 개수가 안 늘어나는
# 것이 곧 "아무것도 안 나갔다"이다. 화면 내용만 보는 것보다 정확하다.
#
# grep에 -a를 붙이는 이유는 로그에 NUL이 한 바이트라도 섞이면 grep이 파일을
# binary로 취급해 "Binary file matches"만 뱉기 때문이다.
#
# 디스크를 물지 않는다. copy mode는 설정과 무관하다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 모드 분기와 copy 커서는 전부 여기서 먼저 걸러진다 — 부팅 1.5초를 쓰기 전에
# 0.1초로 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (input_test or vt_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR. 겹치지 않는
# 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지
# 않기 위해서다.
MONITOR_PORT=45461

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "terminal: screen>" \
    "terminal: copy>" \
    "terminal: scroll>" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- copy lines ---"
  grep -a 'terminal: copy>' "$LOG" | tail -n 20
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

# key> 줄이 지금까지 몇 개 찍혔는지. 음성 검사가 이 값의 변화를 본다.
key_lines() {
  grep -ac 'terminal: key>' "$LOG" || true
}

# copy> 줄에서 값 하나를 뽑는다. **언제나 마지막 줄을 본다** — 마지막 줄이
# 곧 지금의 상태다.
copy_value() {
  grep -a 'terminal: copy>' "$LOG" | tail -n 1 |
    sed -E "s/.*$1=([0-9]+).*/\1/"
}

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 스크롤백을 만든다 ───────────────────────────────────────────────────
#
# `seq 200`. 게스트에 seq 바이너리는 없지만 fish가 seq를 함수로 갖고 있고
# (make_initrd.sh가 fish의 functions 디렉터리를 통째로 복사한다) PATH가 비어
# 있어도 동작한다 — render/check.sh가 쓰는 것과 같은 방법이다.
#
# history가 필요한 이유는 검사 4(커서가 화면 끝에서 뷰포트를 민다) 때문이다.
echo "=== typing 'seq 200' ==="
type_keys s e q spc 2 0 0 ret
sleep 3

# ── 검사 1: 대조군 — 모드 밖에서는 키가 PTY로 나간다 ───────────────────
#
# **이 검사가 없으면 아래 음성 검사가 뜻을 잃는다.** 키가 원래부터 안 나가고
# 있었다면 "모드가 삼켰다"를 증명하지 못한다.
BEFORE_CONTROL="$(key_lines)"
type_keys z
sleep 1
AFTER_CONTROL="$(key_lines)"
if [ "$AFTER_CONTROL" -le "$BEFORE_CONTROL" ]; then
  report_failure "typing outside copy mode did not reach the PTY (key> stayed at ${BEFORE_CONTROL})"
fi
echo "control: a keystroke outside copy mode reached the PTY (${BEFORE_CONTROL} -> ${AFTER_CONTROL})"

# 친 글자를 지운다. 뒤의 검사들이 깨끗한 입력줄을 보게 한다.
type_keys backspace
sleep 1

# ── 모드에 들어간다 ─────────────────────────────────────────────────────
#
# QEMU monitor의 조합 키는 `-`로 잇는다. meta_l이 Cmd, shift가 Shift다.
# **세 키 조합이 게스트까지 도착하는지가 design 위험 4다** — 실패하면 아래
# 검사 2가 걸리고, 그때는 진입키를 두 키 조합으로 바꾼다.
echo "=== entering copy mode (Cmd+Shift+C) ==="
type_keys meta_l-shift-c
sleep 2

# ── 검사 2: 모드에 들어갔는가 ───────────────────────────────────────────
ENTER_LINE="$(grep -aE 'terminal: copy> enter row=[0-9]+ col=[0-9]+' "$LOG" | tail -n 1)"
if [ -z "$ENTER_LINE" ]; then
  report_failure "Cmd+Shift+C did not open copy mode (no 'copy> enter' line)"
fi
echo "entered copy mode: ${ENTER_LINE}"

# ── 검사 3: 음성 검사 — 모드 안에서 친 키가 PTY로 안 샌다 ──────────────
#
# **이 체인에서 CM-M0이 더하는 가장 값진 검사다.** q w e r t는 copy mode의
# 명령이 아니므로 전부 삼켜져야 하고, Enter도 마찬가지다.
#
# 두 겹으로 본다. (1) key> 줄이 안 늘어난다 = PTY로 바이트가 안 나갔다.
# (2) 화면에 qwert가 없다 = 셸이 그것을 되울리지 않았다. 앞의 것이 정확하고
# 뒤의 것은 사람이 로그를 볼 때 이해하기 쉽다.
BEFORE_LEAK="$(key_lines)"
echo "=== typing 'qwert' and Enter inside copy mode (should be swallowed) ==="
type_keys q w e r t ret
sleep 2
AFTER_LEAK="$(key_lines)"
if [ "$AFTER_LEAK" -ne "$BEFORE_LEAK" ]; then
  report_failure "keys leaked to the PTY inside copy mode (key> ${BEFORE_LEAK} -> ${AFTER_LEAK})"
fi
if grep -aq 'terminal: screen>.*qwert' "$LOG"; then
  report_failure "the shell echoed 'qwert' — copy mode did not swallow the keys"
fi
echo "copy mode swallowed every key (key> stayed at ${AFTER_LEAK})"

# ── 검사 4: 커서가 움직이고, 화면 끝에서는 뷰포트가 대신 움직인다 ──────
#
# 먼저 아래로 한 번 가서 row가 1 늘어나는지 본다. "움직이기만 하면 통과"가
# 되지 않도록 정확한 값을 요구한다.
ROW_BEFORE="$(copy_value row)"
type_keys j
sleep 1
ROW_AFTER="$(copy_value row)"
if [ "$ROW_AFTER" -ne "$((ROW_BEFORE + 1))" ]; then
  report_failure "j moved the cursor from row ${ROW_BEFORE} to ${ROW_AFTER} (expected $((ROW_BEFORE + 1)))"
fi
echo "j moved the copy cursor ${ROW_BEFORE} -> ${ROW_AFTER}"

COL_BEFORE="$(copy_value col)"
type_keys l
sleep 1
COL_AFTER="$(copy_value col)"
if [ "$COL_AFTER" -ne "$((COL_BEFORE + 1))" ]; then
  report_failure "l moved the cursor from col ${COL_BEFORE} to ${COL_AFTER} (expected $((COL_BEFORE + 1)))"
fi
echo "l moved the copy cursor ${COL_BEFORE} -> ${COL_AFTER}"

# ── 검사 5: 맨 위에 닿으면 뷰포트가 올라간다 ───────────────────────────
#
# 커서를 맨 윗줄까지 올리고(화면이 47줄이므로 넉넉히 60번) 한 번 더 올린다.
# 그러면 커서는 row=0에 남고 scroll> offset이 줄어야 한다.
SCROLL_BEFORE="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
  sed -E 's/.*offset=([0-9]+).*/\1/')"
echo "=== pushing the cursor to the top of the viewport ==="
for _ in $(seq 1 60); do
  echo "sendkey k" >&3
  sleep 0.05
done
sleep 2
SCROLL_AFTER="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
  sed -E 's/.*offset=([0-9]+).*/\1/')"
ROW_TOP="$(copy_value row)"
if [ "$ROW_TOP" -ne 0 ]; then
  report_failure "the cursor stopped at row ${ROW_TOP} instead of reaching row 0"
fi
if [ "$SCROLL_AFTER" -ge "$SCROLL_BEFORE" ]; then
  report_failure "the viewport did not follow the cursor up (offset ${SCROLL_BEFORE} -> ${SCROLL_AFTER})"
fi
echo "the viewport followed the cursor up (offset ${SCROLL_BEFORE} -> ${SCROLL_AFTER})"

# ── 검사 6: Esc로 나오고, 나온 뒤에는 다시 PTY로 나간다 ────────────────
#
# **이 대조군이 없으면 "영영 못 나온다"도 통과한다.**
echo "=== leaving copy mode (Esc) ==="
type_keys esc
sleep 2
if ! grep -aq 'terminal: copy> exit' "$LOG"; then
  report_failure "Esc did not leave copy mode (no 'copy> exit' line)"
fi

BEFORE_AGAIN="$(key_lines)"
type_keys z
sleep 1
AFTER_AGAIN="$(key_lines)"
if [ "$AFTER_AGAIN" -le "$BEFORE_AGAIN" ]; then
  report_failure "keys stopped reaching the PTY after leaving copy mode (key> stayed at ${BEFORE_AGAIN})"
fi
echo "keys reach the PTY again after leaving copy mode (${BEFORE_AGAIN} -> ${AFTER_AGAIN})"

# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
#
# grep -qP '\x00'은 GNU grep 3.11에서 매치되지 않으므로 바이트 수를 센다.
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "the serial log contains NUL bytes"
fi

echo "CM-M0 check PASS"
```

### Step 2: 실행 권한을 준다 (Claude가 실행)

```bash
chmod +x copy/check.sh
```

### Step 3: 체인을 한 번 돌린다 (Claude가 실행, 약 4~6분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash copy/check.sh
```

기대: `CM-M0 check PASS`.

**검사 2에서 걸리면 design 위험 4다.** 그때는 세 키 조합이 도착하는지를 먼저
가른다 — Cmd 없이 `shift-c`만 보내서 화면에 `C`(대문자)가 나타나는지 본다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/gate.out 2>&1
  grep -a "terminal: screen>" /tmp/tmp.* | tail -n 3
'
```

대문자가 나오면 Shift는 도착하는 것이므로 Meta가 문제이고, 진입키를 두 키
조합(`meta_l-c`, 즉 `Cmd+C` 진입)으로 바꾸고 design doc 결정 4를 함께 고친다.

### Step 4: 커밋 (Claude가 실행)

```bash
git add copy/check.sh
git commit -m "Prove copy mode swallows every key it does not know"
```

---

## Task 5: 루트 게이트에 체인을 등록하고 3/3을 돌린다

**Files:**
- Modify: `check.sh`

### Step 1: 체인을 더한다

`check.sh:108`의 `run_chain "TR-M2" ./render/check.sh` **바로 뒤에 넣을 것**:

```bash
run_chain "CM-M0" ./copy/check.sh
```

### Step 2: 루트 게이트를 돌린다 (Claude가 백그라운드로 실행, 약 50분)

**Bash 도구의 10분 타임아웃을 넘으므로 `run_in_background`로 돌린다.**
직전 기준선은 45분 41초이고(2026-08-24, 한가한 기계) 이번에 부팅 3회가 는다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**시간을 재기 전에 기계를 비운다.** 값이 기준선에서 크게 벗어나면 코드를
의심하기 전에 기계를 먼저 의심한다 — TR-M2를 끝내며 처음 잰 값이 6시간
12분이었고, 원인은 회귀가 아니라 Chrome이 영상을 재생하고 있던 것이었다.

### Step 3: 커밋 (Claude가 실행)

```bash
git add check.sh
git commit -m "Run the copy mode chain in the root gate"
```

---

## Task 6: 문서를 고친다

**Files:**
- Modify: `HANDOFF.md`
- Modify: `docs/decisions/project_copy_mode.md`
- Modify: `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`

### Step 1: design doc에 CM-M0의 결과를 붙인다

design doc의 "milestone 구성" 절 표 아래에 CM-M0의 실측 결과(진입키가
도착했는지, 게이트 시간이 얼마나 늘었는지, 위험 4가 어떻게 결말났는지)를
인용 블록으로 붙인다. TR design doc이 milestone마다 하는 것과 같은 방식이다.

### Step 2: `project_copy_mode` 기억을 고친다

선행 조건 표에서 클립보드가 아직 남아 있음을 유지하되, **CM-M0이 끝났고 통로가
실제로 뚫렸다**는 것과 `scrollToBottom` 억제가 연 창(design 위험 1)을 적는다.

### Step 3: `HANDOFF.md`를 다시 쓴다

- 진행 중인 서브프로젝트: Copy Mode(CM-M0 완료, 다음은 CM-M1)
- 게이트 현황: 여덟 체인, 새 기준선 시간, 45461이 쓰였고 45462가 비었다
- 로그 문구 목록에 `terminal: copy>` 추가
- 이월 숙제는 그대로 옮긴다

### Step 4: 커밋 (Claude가 실행)

```bash
git add HANDOFF.md docs/decisions/project_copy_mode.md \
  docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md
git commit -m "Record what CM-M0 settled"
```

---

## 완료 조건

- [ ] `zig build test`가 `input_test: copy mode OK`와 `vt_test: copy cursor OK`를 찍는다
- [ ] `copy/check.sh` 단독 실행이 `CM-M0 check PASS`
- [ ] 루트 게이트 여덟 체인이 3/3
- [ ] 게이트 시간의 증가분을 실측해 기록했다
- [ ] design doc·`project_copy_mode`·`HANDOFF.md`가 최신이다
