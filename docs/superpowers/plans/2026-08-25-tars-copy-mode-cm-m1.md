# TARS Copy Mode CM-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** copy mode 안에서 `v`/`V`로 영역을 잡고, 잡힌 영역이 **화면에 반전되어
보이고**, `y`(또는 `Cmd+C`)가 그 글자를 클립보드로 옮기면서 모드를 닫는다.
게이트가 `terminal: clip> len=11 text=echo PASTED`를 실제 게스트에서 본다.

**Design doc:** `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`
(결정 5·6이 이 milestone의 몫이다. 붙여넣기 결정 9는 CM-M2다. design은 승인되어
있으므로 다시 논의하지 않는다.)

**Tech Stack:** Zig 0.16, libghostty-vt(`Screen.select` · `Screen.selectionString` ·
`Screen.selectLine` · `Selection.order` · `RenderState.Row.selection` ·
`PageList.pin` · `PageList.pointFromPin`), evdev, DRM dumb buffer,
QEMU monitor `sendkey`, bash 게이트 스크립트

---

## 착수 전에 이미 확정된 사실

### CM-M0이 실측으로 남긴 것 (2026-08-24) — 다시 조사하지 않는다

1. **`screens.active`는 이미 포인터다.** `&`를 붙이면 `**Screen`이 되어
   `does not support field access`로 막힌다. **CM-M1이 이 필드를 실제로 쓴다.**
2. **copy 커서는 언제나 화면 맨 아랫줄에서 시작한다.** 셸 프롬프트가 거기 있기
   때문이다(`row=46`, 화면은 47줄). 그래서 게이트에서 **아래로 먼저 갈 수 없다** —
   CM-M1의 선택 검사도 `k`로 올라가는 것으로 시작한다.
3. **`Action`이나 `Keys`를 건드리면 `zig build test`만으로 모자란다.** Zig가
   참조되지 않는 함수를 분석하지 않아서 `readKeys`가 쓰는 필드가 통째로 사라진
   것을 호스트 검사가 두 번 놓쳤다. **`Copy`에 variant를 더하는 이번 작업에 그대로
   해당된다** — Task 4에서 `zig build`를 함께 돌린다.
4. **`sendkey`는 0.05초 간격으로 80번을 보내도 하나도 안 떨어진다.**
5. **`terminal: key>` 줄은 PTY로 바이트가 나갈 때만 찍힌다.** 이것이 "모드가
   닫혔는가"를 보는 가장 정확한 도구다. CM-M1은 `y` 뒤에 이 도구를 다시 쓴다.

### CM-M0 착수 전 프로브가 확정한 것 (2026-08-24) — 그대로 유효

| 확인한 것 | 결과 |
|---|---|
| `Screen.select()`에 untracked `Selection`을 넘기면 | 화면이 tracked로 바꿔서 가져간다 |
| `Screen.selectionString(alloc, .{ .sel = … })` | `[hello]` len=5 |
| `RenderState.Row.selection` | `row 0 selection={ 0, 4 }` — 라이브러리가 채운다 |
| `Screen.selectLine(.{ .pin = … })` | `[hello world]` — 줄 끝 공백을 알아서 트림한다 |
| 뷰포트가 밀린 뒤에도 | 선택은 여전히 `[hello]` |

### 이번 plan을 쓰면서 vendor 소스에서 읽어낸 것 넷

프로브를 돌리는 대신 `terminal/ghostty-src/src/terminal/`을 직접 읽었다. **넷 다
아래 Task의 검사가 실행으로 다시 증명한다** — 읽은 것을 믿고 넘어가지 않는다.

1. **`Row.selection`은 `?[2]u16`이고 양 끝을 포함한다.**
   `render.zig:704`가 `assert(start.x <= end.x)` 뒤에 `.{ start.x, end.x }`를
   넣는다. 그래서 렌더는 `x >= range[0] and x <= range[1]`이다.
2. **역방향 선택은 라이브러리가 정렬해 준다**(design 위험 3의 답).
   `selectionString`은 `formatter.zig:669-671`에서 `sel.topLeft()`/
   `sel.bottomRight()`를 쓰고, 렌더도 `render.zig:667-669`에서 같은 둘을 쓴다.
   **우리가 `ordered()`를 부를 자리는 없다.** Task 2의 검사 2가 이것을 실행으로
   확인한다.
3. **`select()`는 `screen.dirty.selection`을 세우고, 그 비트가 다음 프레임을
   full redraw로 만든다**(`render.zig:377-382`). 그래서 선택이 줄어들 때 옛 행에
   범위가 남는 일이 구조적으로 없다 — `RowBuilder`가 매 행을 다시 지으면서
   `sels[y] = null`부터 한다(`render.zig:1042`).
4. **가지치기는 선택을 null로 만들지 않는다.** 아래에서 따로 다룬다.

---

## 이번에 정하는 것 다섯 (design doc이 안 정했거나, 소스가 뒤집은 자리)

### 1. **가지치기 방어를 "selection이 null인가"로 짜면 영영 안 걸린다**

`HANDOFF.md`와 design 위험 1이 적어 둔 방어는 "매 프레임 `selection`이 null이
됐는지 보고 그러면 모드를 나간다"였다. **그 조건은 절대 참이 되지 않는다.**

`PageList.erasePage`(`PageList.zig:5455-5470`)와 `eraseRows`
(`PageList.zig:5409-5419`)가 하는 일은 이렇다.

```zig
// Update any tracked pins to move to the previous or next page.
for (pin_keys) |p| {
    if (p.node != node) continue;
    p.node = node.prev orelse node.next orelse unreachable;
    p.y = 0;
    p.x = 0;
}
```

**pin을 무효로 만들지 않고 살아 있는 이웃 페이지의 왼쪽 위로 옮긴다.**
`Screen.selection`은 그대로 있고, tracked pin도 그대로 유효하다. 달라진 것은
그것이 가리키는 **내용**뿐이다. 즉 이 상황의 증상은 "선택이 사라진다"가 아니라
**"엉뚱한 자리를 조용히 복사한다"**이고, 그것이 design 위험 1이 막고 싶어 했던
바로 그 사고다.

그래서 방어를 다시 짠다. **앵커의 screen 좌표 y를 기억해 두고, 출력을 먹인 뒤에
그 값이 달라졌으면 모드를 나간다.**

- screen 좌표는 전체 목록의 맨 위에서부터 세는 절대 좌표라, **아래에 줄이
  붙는 것으로는 안 변한다.** 변하는 경우는 앞에서 줄이 지워졌을 때(가지치기)와
  pin이 옮겨졌을 때뿐이다 — 우리가 잡고 싶은 것이 정확히 그 둘이다.
- 대체 화면(vim 등)으로 갈아타서 `selection`이 사라지는 경우도 같은 조건에
  걸린다. 그때 모드를 나가는 것도 옳다.

`total`(전체 행 수)이 줄었는지로 보는 안은 버렸다. 한 번의 `feed`에 한 페이지
(약 286줄)보다 많이 들어오면 늘어난 것과 지워진 것이 상쇄되어 못 잡는다.

**이 방어는 게이트가 못 본다**(copy mode 중에 1000줄을 쏟아부을 방법이 없다).
그래서 `vt_test`가 대신 보고, **가지치기가 없을 때는 모드가 안 끊긴다는 대조군을
같이 둔다** — 그것이 없으면 "언제나 나간다"도 통과한다.

### 2. `Copy` enum은 아홉 개까지만 연다 (`paste`는 CM-M2)

CM-M0이 여섯으로 닫아 둔 이유가 그대로다. `main.zig`의 switch가 `else` 없이
닫혀 있으므로, variant를 더하는 순간 컴파일러가 배선할 자리를 알려준다.
`paste`를 지금 넣으면 CM-M2가 그 신호를 잃는다.

### 3. `v`/`V`는 **같은 것을 다시 누르면 풀고, 다른 것을 누르면 앵커를 새로 잡는다**

design 결정 4의 표는 "선택 시작/해제"까지만 정했다. `v`로 잡던 중에 `V`를 누르면
vim은 앵커를 유지하지만, 우리는 **앵커를 지금 커서 자리로 새로 잡는다.** 앵커를
유지하려면 "문자 앵커를 줄 앵커로 승격하는" 자리가 하나 더 생기는데, 게이트가 볼
수 없는 표를 늘리는 일이라 지금 하지 않는다. 대신 그 선택을 여기 적어 둔다.

### 4. **커서가 선택 안에 있으면 두 번 뒤집혀 원래 색으로 돌아온다**

선택도 커서도 "색 둘을 맞바꾼다"는 같은 연산이므로(design 결정 6), 겹치면 상쇄된다.
숨기지 않고 그대로 둔다 — 반전된 띠 가운데 뚫린 구멍이 곧 커서라서 오히려 잘
보이고, 예외를 넣으면 "선택"이라는 개념이 렌더 쪽으로 새어 나간다.
**`vt_test`가 이 성질을 못 박는다.**

### 5. `y` 뒤의 로그는 `copy> exit`이 아니라 `copy> yank`다

design 결정 7의 시나리오는 "`clip> …`, 이어서 `copy> exit`"이라고 적었다. 실제로는
`main.zig`가 명령 이름을 그대로 찍으므로 `copy> yank`가 된다. 줄을 하나 더
만들지 않고 이름만 다르게 간다. **design doc의 그 문장을 Task 7에서 고친다.**

---

## Task 1: `input.zig`에 `v`·`V`·`y`·`Cmd+C`를 넣는다

**Files:**
- Modify: `terminal/src/input.zig`
- Test: `terminal/src/input_test.zig`

### Step 1: `Copy` enum에 variant 셋을 더한다

`input.zig:169-182`를 **지울 것**:

```zig
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

**넣을 것**:

```zig
/// copy mode 안에서 키가 만드는 명령.
///
/// **`paste`는 아직 없다**(CM-M2의 몫이다). CM-M0이 여섯 개로 닫아 둔 이유가
/// 그대로 유효하다 — `main.zig`의 switch가 `else` 없이 닫혀 있으므로, variant를
/// 더하는 순간 컴파일러가 배선할 자리를 알려준다. 미리 만들어 두면 그 신호를
/// 잃는다.
pub const Copy = enum {
    enter,
    exit,
    left,
    down,
    up,
    right,
    /// `v` — 문자 단위 선택 시작/해제.
    select_char,
    /// `V` — 줄 단위 선택 시작/해제.
    select_line,
    /// `y` 또는 `Cmd+C` — 클립보드로 옮기고 **모드를 나간다.**
    yank,
};
```

### Step 2: copy 표에 세 줄을 더한다

`input.zig:516-528`을 **지울 것**:

```zig
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

**넣을 것**:

```zig
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
                // Shift를 여기서 보는 것은 chord()의 예외와 성격이 다르다.
                // 모드 안의 표는 원래 문자 키를 직접 읽으므로, 대문자 V가
                // 소문자 v와 다른 명령이라는 것을 볼 자리가 여기뿐이다.
                c.KEY_V => return .{
                    .copy = if (self.shifted()) .select_line else .select_char,
                },
                // yank는 **모드를 닫는다.** 여기서 mode를 되돌리지 않으면
                // 복사는 했는데 모드에 갇혀서 그다음 키가 전부 삼켜진다 —
                // 게이트의 검사 9가 정확히 그것을 본다.
                c.KEY_Y => {
                    self.mode = .normal;
                    return .{ .copy = .yank };
                },
                // **Cmd+C가 chord()가 아니라 여기 있는 이유**(design 결정 4).
                // copy 분기가 chord()보다 앞이라 모드 안에서는 Cmd 조합이
                // chord()에 아예 닿지 않는다. CM-M2의 Cmd+V도 이 자리에 온다.
                //
                // Cmd 없이 누른 c는 전과 같이 삼켜진다.
                c.KEY_C => {
                    if (!self.metaed()) return nothing;
                    self.mode = .normal;
                    return .{ .copy = .yank };
                },
                else => return nothing,
            }
        }
```

### Step 3: `input_test.zig`에 검사 넷을 더한다

`input_test.zig`의 `main` 함수에서 **CM-M0이 남긴 마지막 줄**

```zig
    std.debug.print("input_test: copy mode OK\n", .{});
```

을 찾아, 그 **바로 앞에 넣을 것**(지울 것 없음):

```zig
    // ── CM-M1: 선택과 복사 ──────────────────────────────────────────────
    //
    // 검사 7. v와 V가 갈린다. 같은 키코드가 Shift 하나로 다른 명령이 되므로,
    // **둘을 나란히 보지 않으면 "언제나 select_char"도 통과한다.**
    //
    // 앞의 검사 6이 Esc로 모드를 닫아 두었으므로 먼저 다시 연다. modifier 키
    // 자체는 언제나 빈 바이트열이라 expect로 본다.
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    if (cm.mode != .copy) {
        std.debug.print("FAIL: could not re-enter copy mode for the CM-M1 checks\n", .{});
        return error.ModeNotEntered;
    }

    try expectCopy(&cm, K.KEY_V, .select_char);
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_V, .select_line);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expectCopy(&cm, K.KEY_V, .select_char);

    // 검사 8. Cmd 없는 c는 여전히 삼켜진다. **이것이 없으면 아래 검사 9가
    // "c는 언제나 yank"로도 통과한다.**
    try expect(&cm, K.KEY_C, 1, "");
    if (cm.mode != .copy) {
        std.debug.print("FAIL: a bare 'c' left copy mode\n", .{});
        return error.ModeLeftByBareC;
    }

    // 검사 9. y가 yank를 내고 **모드를 닫는다.** 닫혔다는 것을 h가 다시
    // 글자가 되는 것으로 확인한다.
    try expectCopy(&cm, K.KEY_Y, .yank);
    if (cm.mode != .normal) {
        std.debug.print("FAIL: y did not leave copy mode\n", .{});
        return error.YankDidNotLeave;
    }
    try expect(&cm, K.KEY_H, 1, "h");

    // 검사 10. Cmd+C도 같은 일을 한다. 모드 밖에서는 Cmd+C가 표에 없어
    // 그냥 'c'가 된다는 것도 함께 본다 — **normal 모드의 Cmd+C를 비워 두는
    // 것이 design 결정 4다.**
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_C, 1, "c");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expectCopy(&cm, K.KEY_C, .yank);
    if (cm.mode != .normal) {
        std.debug.print("FAIL: Cmd+C did not leave copy mode\n", .{});
        return error.YankDidNotLeave;
    }
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    try expect(&cm, K.KEY_H, 1, "h");
```

**주의.** `expectCopy`는 `handleKey(code, 1, .{})`를 부르므로 **누름(1)만 본다.**
modifier를 떼는 이벤트(value 0)와 modifier 키 자체는 언제나 `expect`로 본다.

### Step 4: 호스트 검사를 돌린다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: `input_test: copy mode OK`가 찍히고 `PASS`.

**이 시점에 `vt.zig`·`main.zig`는 아직 안 고쳤다.** `Copy`에 variant가 늘었지만
`main.zig`의 switch는 `zig build test`가 컴파일하지 않으므로 여기서는 안 걸린다 —
Task 4의 `zig build`가 걸어 준다. **그것이 CM-M0이 배운 교훈의 자리다.**

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Teach copy mode the selection and yank keys"
```

---

## Task 2: `vt.zig`에 선택·클립보드·가지치기 방어를 넣는다

**Files:**
- Modify: `terminal/src/vt.zig`
- Test: `terminal/src/vt_test.zig`

### Step 1: 상태 넷을 더한다

`vt.zig:46-55`의 `copy_cursor` 선언을 **지울 것**:

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

**넣을 것**:

```zig
    /// copy mode의 커서. null이면 copy mode가 아니다.
    ///
    /// **뷰포트 좌표다**(0이 화면 맨 윗줄). 절대 행이 아닌 이유는 이동이
    /// 화면 위의 일이기 때문이다 — 뷰포트가 한 줄 올라가면 커서는 화면의
    /// 같은 자리에 남고, 그래서 가리키는 내용이 한 줄 위가 된다. 그것이
    /// 화면 끝에서 계속 움직였을 때 사람이 기대하는 동작이다.
    ///
    /// 앵커(선택의 시작점)는 여기 두지 않는다. 라이브러리의 tracked
    /// selection이 든다(design 결정 5) — 뷰포트가 움직여도 저절로 따라간다.
    copy_cursor: ?Cursor = null,

    /// 지금 무엇을 잡고 있는가. null이면 커서만 움직이는 중이다.
    copy_kind: ?SelectKind = null,

    /// 앵커의 **screen 좌표 y**. 가지치기 감시용이다(CM-M1).
    ///
    /// 이 값이 왜 필요한지가 이 milestone에서 가장 미묘한 자리다.
    /// `main.zig`가 copy mode 중에 `scrollToBottom()`을 억제하므로, 뷰포트가
    /// history에 머무는 동안 가지치기가 일어날 수 있다(design 위험 1).
    /// **그때 라이브러리는 선택을 null로 만들지 않는다** — tracked pin을
    /// 살아 있는 이웃 페이지의 왼쪽 위로 옮긴다
    /// (`PageList.erasePage`, `PageList.eraseRows`). 선택은 멀쩡히 존재하고
    /// 가리키는 내용만 달라진다. 그래서 "selection이 null인가"로는 절대 못
    /// 잡고, 조용히 엉뚱한 자리를 복사하게 된다.
    ///
    /// screen 좌표는 목록 맨 위에서부터 세는 절대 좌표라 **아래에 줄이 붙는
    /// 것으로는 안 변한다.** 변하는 경우가 앞에서 줄이 지워졌을 때와 pin이
    /// 옮겨졌을 때뿐이고, 그 둘이 정확히 우리가 잡고 싶은 것이다.
    copy_anchor_y: ?u32 = null,

    /// 가지치기 때문에 모드가 끊겼다는 것을 `main.zig`가 한 번 가져간다.
    copy_pruned: bool = false,

    /// 클립보드. `y`가 만든 문자열을 **소유한다.**
    ///
    /// 프로세스 하나가 디스플레이를 독점하는 구조(TF design 결정 1)에서는
    /// 버퍼 하나로 충분하다(`project_copy_mode`). 다음 `y`가 옛것을 해제한다.
    clip: ?[:0]const u8 = null,
```

### Step 2: `deinit`이 클립보드를 해제한다

`vt.zig:108-114`를 **지울 것**:

```zig
    pub fn deinit(self: *Screen) void {
        const alloc = self.alloc;
        self.state.deinit(alloc);
        self.stream.deinit();
        self.term.deinit(alloc);
        alloc.destroy(self);
    }
```

**넣을 것**:

```zig
    pub fn deinit(self: *Screen) void {
        const alloc = self.alloc;
        if (self.clip) |text| alloc.free(text);
        self.state.deinit(alloc);
        self.stream.deinit();
        self.term.deinit(alloc);
        alloc.destroy(self);
    }
```

### Step 3: `feed`가 가지치기를 감시한다

`vt.zig:116-119`를 **지울 것**:

```zig
    /// PTY에서 읽은 바이트를 ANSI 파서에 먹인다. 화면 상태가 갱신된다.
    pub fn feed(self: *Screen, bytes: []const u8) void {
        self.stream.nextSlice(bytes);
    }
```

**넣을 것**:

```zig
    /// PTY에서 읽은 바이트를 ANSI 파서에 먹인다. 화면 상태가 갱신된다.
    ///
    /// **먹인 뒤에 앵커가 제자리에 있는지 본다**(CM-M1, design 위험 1).
    /// 어긋났으면 모드를 통째로 닫는다 — 조용히 엉뚱한 자리를 복사하는 것보다
    /// 낫고, 사람은 다시 `Cmd+Shift+C`를 누르면 된다.
    ///
    /// 대체 화면(vim 등)으로 갈아타서 `selection`이 사라지는 경우도 같은
    /// 조건에 걸린다. 그때 나가는 것도 옳다.
    ///
    /// 선택 중이 아니면(`copy_anchor_y`가 null이면) 아무 일도 안 한다.
    /// 커서만 있는 상태에서는 잘못 복사될 것이 없기 때문이다.
    pub fn feed(self: *Screen, bytes: []const u8) void {
        self.stream.nextSlice(bytes);

        const want = self.copy_anchor_y orelse return;
        const now = anchorY(self.term.screens.active);
        if (now != null and now.? == want) return;

        self.copyExit();
        self.copy_pruned = true;
    }

    /// 지금 선택의 앵커가 screen 좌표로 몇 번째 행에 있는가.
    ///
    /// 선택이 없으면 null이다. `pointFromPin`은 라이브러리가 스스로 "느리다"고
    /// 적어 둔 함수라(`Selection.zig`의 NOTE) 셀마다 부르면 안 되지만, 여기는
    /// **선택이 있을 때 PTY 출력 한 조각에 한 번**이라 문제가 되지 않는다.
    fn anchorY(s: *ghostty_vt.Screen) ?u32 {
        const sel = s.selection orelse return null;
        const pt = s.pages.pointFromPin(.screen, sel.start()) orelse return null;
        return pt.screen.y;
    }
```

### Step 4: 선택을 만들고 지우고 복사하는 함수들

`vt.zig`의 `copyExit`을 **지울 것**:

```zig
    /// copy mode를 나간다.
    pub fn copyExit(self: *Screen) void {
        self.copy_cursor = null;
    }
```

**넣을 것**:

```zig
    /// copy mode를 나간다. **선택도 함께 지운다** — 안 지우면 모드를 나간 뒤에도
    /// 반전된 띠가 화면에 남는다.
    pub fn copyExit(self: *Screen) void {
        self.copy_cursor = null;
        self.copy_kind = null;
        self.copy_anchor_y = null;
        self.term.screens.active.clearSelection();
    }

    /// 가지치기로 모드가 끊겼다는 사실을 **한 번만** 돌려준다.
    /// `main.zig`가 로그 한 줄을 찍는 데 쓴다.
    pub fn copyTakePruned(self: *Screen) bool {
        defer self.copy_pruned = false;
        return self.copy_pruned;
    }
```

`copyMove` 정의 **바로 뒤에 넣을 것**(지울 것 없음. `copyMove` 자체는 Step 5에서
고친다):

```zig
    /// 선택 방식. `v`가 char, `V`가 line이다.
    pub const SelectKind = enum { char, line };

    /// 지금 커서 자리를 라이브러리의 pin으로 바꾼다.
    ///
    /// 뷰포트 좌표를 그대로 넘길 수 있는 것이 요점이다 — 절대 행 번호를 우리가
    /// 셀 필요가 없다. 뷰포트 밖이거나 폭이 줄어든 페이지면 null이다.
    fn copyPin(self: *Screen) ?ghostty_vt.Pin {
        const cc = self.copy_cursor orelse return null;
        return self.term.screens.active.pages.pin(.{
            .viewport = .{ .x = cc.x, .y = cc.y },
        });
    }

    /// `v`/`V`. **같은 방식을 다시 누르면 푼다.**
    ///
    /// 다른 방식을 누르면 앵커를 지금 커서 자리로 새로 잡는다. vim은 앵커를
    /// 유지하지만, 그러려면 "문자 앵커를 줄 앵커로 승격하는" 자리가 하나 더
    /// 생긴다 — 게이트가 볼 수 없는 표를 늘리는 일이라 지금 하지 않는다.
    pub fn copySelect(self: *Screen, kind: SelectKind) !void {
        if (self.copy_cursor == null) return;
        if (self.copy_kind) |cur| {
            if (cur == kind) {
                self.copy_kind = null;
                self.copy_anchor_y = null;
                self.term.screens.active.clearSelection();
                return;
            }
        }
        self.copy_kind = kind;
        const pin = self.copyPin() orelse return;
        try self.copyApply(pin, pin);
    }

    /// 앵커와 커서로 선택을 다시 만들어 화면에 넘긴다.
    ///
    /// **역방향(앵커보다 커서가 앞)을 우리가 정렬하지 않는다**(design 위험 3의
    /// 답). `selectionString`은 `sel.topLeft()`/`bottomRight()`를 쓰고
    /// (`formatter.zig`), 렌더도 같은 둘을 쓴다(`render.zig`). 그래서
    /// `ordered()`를 부를 자리가 없다.
    fn copyApply(
        self: *Screen,
        anchor: ghostty_vt.Pin,
        cursor: ghostty_vt.Pin,
    ) !void {
        const s = self.term.screens.active;
        const kind = self.copy_kind orelse return;

        const sel: ghostty_vt.Selection = switch (kind) {
            .char => .init(anchor, cursor, false),
            // 줄 선택은 양 끝을 줄 전체로 넓힌다. **줄 끝 공백 트림을 손으로
            // 짜지 않는다** — selectLine이 이미 한다.
            .line => copyLineSel(s, anchor, cursor) orelse .init(anchor, cursor, false),
        };
        try s.select(sel);
        self.copy_anchor_y = anchorY(s);
    }

    /// 앵커 줄과 커서 줄을 합친 선택.
    ///
    /// 어느 쪽이 위인지를 **라이브러리에게 묻는다**. 화면 좌표를 우리가 세면
    /// 스크롤백 위에서 틀린다 — 앵커가 뷰포트 밖에 있을 수 있기 때문이다.
    fn copyLineSel(
        s: *ghostty_vt.Screen,
        anchor: ghostty_vt.Pin,
        cursor: ghostty_vt.Pin,
    ) ?ghostty_vt.Selection {
        const a = s.selectLine(.{ .pin = anchor }) orelse return null;
        const b = s.selectLine(.{ .pin = cursor }) orelse return null;
        const probe: ghostty_vt.Selection = .init(a.start(), b.start(), false);
        return switch (probe.order(s)) {
            // 앵커 줄이 아래에 있다. 위아래를 뒤집어 담는다.
            .reverse => .init(a.end(), b.start(), false),
            else => .init(a.start(), b.end(), false),
        };
    }

    /// `y`. 선택을 클립보드로 옮기고 **모드를 나간다.**
    ///
    /// 돌려주는 슬라이스는 `self.clip`이 소유한다 — 다음 `y`까지만 유효하다.
    /// 선택이 없으면 null을 돌려주고 클립보드는 그대로 둔다(모드는 나간다).
    pub fn copyYank(self: *Screen) !?[]const u8 {
        const s = self.term.screens.active;
        const sel = s.selection orelse {
            self.copyExit();
            return null;
        };
        const text = try s.selectionString(self.alloc, .{ .sel = sel });
        if (self.clip) |old| self.alloc.free(old);
        self.clip = text;
        // copyExit이 선택을 지우므로 **문자열을 먼저 뽑아 둔 뒤에** 부른다.
        self.copyExit();
        return text;
    }
```

### Step 5: `copyMove`가 선택을 따라 갱신한다

`vt.zig`의 `copyMove` 마지막 두 줄을 **지울 것**:

```zig
        self.copy_cursor = .{ .x = @intCast(x), .y = @intCast(y) };
    }
```

**넣을 것**:

```zig
        self.copy_cursor = .{ .x = @intCast(x), .y = @intCast(y) };

        // 선택 중이면 커서를 따라 넓힌다. 앵커는 우리가 안 들고 있고
        // **지금 선택의 start가 곧 앵커다**(design 결정 5). 줄 선택일 때 그
        // start는 앵커 줄 위의 어느 pin이므로, selectLine이 같은 줄을 다시
        // 돌려준다.
        if (self.copy_kind == null) return;
        const sel = self.term.screens.active.selection orelse return;
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }
```

그리고 같은 함수의 시그니처를 **지울 것**:

```zig
    pub fn copyMove(self: *Screen, dx: i32, dy: i32) void {
```

**넣을 것**:

```zig
    pub fn copyMove(self: *Screen, dx: i32, dy: i32) !void {
```

**왜 `!void`로 바꾸는가.** 이동할 때마다 선택을 다시 만들어야 하고 그 일이
할당을 한다. 별도의 `copySync()`를 두고 호출부가 부르게 하는 안도 있었지만,
그러면 **부르는 것을 잊어도 컴파일이 통과한다.** 반환을 넓히면 호출부가 전부
컴파일 에러로 드러난다 — CM-M0이 `Copy` enum을 닫아 둔 것과 같은 규율이다.

### Step 6: `vt_test.zig`에 CM-M1 검사 여섯을 더한다

`vt_test.zig:344-349`(CM-M0의 검사 4)를 **지울 것**:

```zig
    // 검사 4. 나가면 커서가 사라지고 셸 커서가 돌아온다.
    fresh.copyExit();
    if (fresh.copyActive()) {
        std.debug.print("FAIL: copy mode stayed active after copyExit\n", .{});
        return error.CopyStillActive;
    }
    std.debug.print("vt_test: copy cursor OK\n", .{});
```

**넣을 것**:

```zig
    // 검사 4. 나가면 커서가 사라지고 셸 커서가 돌아온다.
    fresh.copyExit();
    if (fresh.copyActive()) {
        std.debug.print("FAIL: copy mode stayed active after copyExit\n", .{});
        return error.CopyStillActive;
    }
    std.debug.print("vt_test: copy cursor OK\n", .{});

    // ── CM-M1: 선택과 클립보드 ──────────────────────────────────────────
    //
    // 작은 화면을 새로 만든다. 앞의 화면들은 스크롤백 검사가 지나간 뒤라
    // 몇 번째 줄에 무엇이 있는지가 검사마다 달라지고, 그러면 아래 단언들이
    // 무엇을 보는지 흐려진다.
    const cm = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer cm.deinit();
    cm.feed("hello world\r\nsecond line\r\n");

    // 검사 5. 문자 선택 → 반전 → 복사.
    //
    // 커서는 셸 커서 자리(row 2, col 0)에서 시작하므로 두 번 올라가면 row 0이다.
    cm.copyEnter();
    try cm.copyMove(0, -1);
    try cm.copyMove(0, -1);
    const at = cm.copyCursor() orelse return error.NoCopyCursor;
    if (at.x != 0 or at.y != 0) {
        std.debug.print("FAIL: expected the copy cursor at 0,0 but it is {d},{d}\n", .{ at.y, at.x });
        return error.WrongCopyCursor;
    }
    try cm.copySelect(.char);
    var moved: usize = 0;
    while (moved < 4) : (moved += 1) try cm.copyMove(1, 0);

    // 색을 먼저 본다. **복사보다 렌더를 먼저 보는 이유**는, y가 선택을
    // 지우고 나가기 때문이다.
    //
    // 이 시점의 선택은 col 0..4 = "hello"이고 커서는 col 4다. col 0은
    // 반전되어 있어야 하고, **col 4는 선택과 커서가 겹쳐 두 번 뒤집히므로
    // 기본 색으로 돌아와 있어야 한다**(이번에 정하는 것 4).
    const painted = try cm.cells(&buf);
    var saw_start = false;
    var saw_cursor = false;
    for (painted) |cell| {
        if (cell.row != 0) continue;
        if (cell.col == 0) {
            saw_start = true;
            if (cell.fg != cm.defaultBg() or cell.bg != cm.defaultFg()) {
                std.debug.print(
                    "FAIL: selected cell 0,0 is fg=#{X:0>6} bg=#{X:0>6} (expected the two swapped)\n",
                    .{ cell.fg, cell.bg },
                );
                return error.SelectionNotInverted;
            }
        }
        if (cell.col == 4) {
            saw_cursor = true;
            if (cell.fg != cm.defaultFg() or cell.bg != cm.defaultBg()) {
                std.debug.print(
                    "FAIL: cell 0,4 is fg=#{X:0>6} bg=#{X:0>6}; the cursor inside the selection should cancel out\n",
                    .{ cell.fg, cell.bg },
                );
                return error.DoubleSwapWrong;
            }
        }
    }
    if (!saw_start or !saw_cursor) {
        std.debug.print("FAIL: row 0 is missing col 0 ({}) or col 4 ({})\n", .{ saw_start, saw_cursor });
        return error.SelectedCellMissing;
    }
    std.debug.print("vt_test: 선택이 셀의 색을 맞바꾼다 OK\n", .{});

    const yanked = (try cm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, yanked, "hello")) {
        std.debug.print("FAIL: yanked '{s}' (expected 'hello')\n", .{yanked});
        return error.WrongClipText;
    }
    if (cm.copyActive()) {
        std.debug.print("FAIL: y did not leave copy mode\n", .{});
        return error.YankDidNotLeave;
    }
    std.debug.print("vt_test: 문자 선택과 y OK ('{s}')\n", .{yanked});

    // 검사 6. **역방향 선택**(design 위험 3). 앵커를 col 4에 두고 왼쪽으로
    // 끌어도 같은 글자가 나와야 한다. 라이브러리가 topLeft/bottomRight로
    // 정렬한다는 것을 여기서 실행으로 확인한다.
    cm.copyEnter();
    try cm.copyMove(0, -1);
    try cm.copyMove(0, -1);
    moved = 0;
    while (moved < 4) : (moved += 1) try cm.copyMove(1, 0);
    try cm.copySelect(.char);
    moved = 0;
    while (moved < 4) : (moved += 1) try cm.copyMove(-1, 0);
    const backward = (try cm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, backward, "hello")) {
        std.debug.print("FAIL: backward selection yanked '{s}' (expected 'hello')\n", .{backward});
        return error.BackwardSelectionWrong;
    }
    std.debug.print("vt_test: 역방향 선택도 같은 글자를 준다 OK ('{s}')\n", .{backward});

    // 검사 7. 줄 선택. **줄 끝 공백이 트림되어 나오는 것**이 요점이다 —
    // 화면은 20칸이고 글자는 11자다.
    cm.copyEnter();
    try cm.copyMove(0, -1);
    try cm.copySelect(.line);
    const whole_line = (try cm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, whole_line, "second line")) {
        std.debug.print("FAIL: line selection yanked '{s}' (expected 'second line')\n", .{whole_line});
        return error.LineSelectionWrong;
    }
    std.debug.print("vt_test: 줄 선택이 끝 공백을 트림한다 OK ('{s}')\n", .{whole_line});

    // 검사 8. 같은 방식을 다시 누르면 선택이 풀린다. 풀린 뒤의 y는 아무것도
    // 안 준다. **이것이 없으면 "v는 언제나 새 선택"도 통과한다.**
    cm.copyEnter();
    try cm.copySelect(.char);
    try cm.copySelect(.char);
    if ((try cm.copyYank()) != null) {
        std.debug.print("FAIL: yank found a selection after v toggled it off\n", .{});
        return error.SelectionNotCleared;
    }
    std.debug.print("vt_test: v를 다시 누르면 선택이 풀린다 OK\n", .{});

    // 검사 9. **가지치기 방어**(design 위험 1). 두 겹으로 본다.
    const pruned = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer pruned.deinit();
    var pl: usize = 1;
    while (pl <= 200) : (pl += 1) {
        pruned.feed(std.fmt.bufPrint(&line, "P{d}\r\n", .{pl}) catch unreachable);
    }
    pruned.scrollByRows(-10);
    pruned.copyEnter();
    try pruned.copySelect(.char);

    // (1) 대조군 — 평범한 출력으로는 모드가 안 끊긴다. **이것이 없으면
    //     "언제나 나간다"도 통과한다.**
    pruned.feed("just a line\r\n");
    if (!pruned.copyActive()) {
        std.debug.print("FAIL: an ordinary line of output dropped copy mode\n", .{});
        return error.PruneGuardTooEager;
    }
    if (pruned.copyTakePruned()) {
        std.debug.print("FAIL: an ordinary line of output was reported as pruning\n", .{});
        return error.PruneGuardTooEager;
    }

    // (2) 한도를 넘겨 가지치기를 일으킨다. 한도는 1000줄이다(vt.zig의 init).
    pl = 1;
    while (pl <= 3000) : (pl += 1) {
        pruned.feed(std.fmt.bufPrint(&line, "Q{d}\r\n", .{pl}) catch unreachable);
    }
    if (pruned.copyActive()) {
        std.debug.print("FAIL: pruning did not drop copy mode\n", .{});
        return error.PruneNotDetected;
    }
    if (!pruned.copyTakePruned()) {
        std.debug.print("FAIL: copy mode ended without reporting the pruning\n", .{});
        return error.PruneNotReported;
    }
    if (pruned.copyTakePruned()) {
        std.debug.print("FAIL: copyTakePruned reported the same event twice\n", .{});
        return error.PruneReportedTwice;
    }
    std.debug.print("vt_test: 가지치기가 copy mode를 끊는다 OK\n", .{});
    std.debug.print("vt_test: copy selection OK\n", .{});
```

**CM-M0의 검사 2·3이 `copyMove`를 부르는 자리 넷도 `try`를 붙여야 한다.**
`vt_test.zig:305-306`과 `:328`을 **지울 것**:

```zig
    while (fresh.copyCursor().?.x > 0) fresh.copyMove(-1, 0);
    while (fresh.copyCursor().?.y > 0) fresh.copyMove(0, -1);
```

```zig
    fresh.copyMove(0, -1);
```

**넣을 것**:

```zig
    while (fresh.copyCursor().?.x > 0) try fresh.copyMove(-1, 0);
    while (fresh.copyCursor().?.y > 0) try fresh.copyMove(0, -1);
```

```zig
    try fresh.copyMove(0, -1);
```

### Step 7: 호스트 검사를 돌린다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 아래 여섯 줄이 차례로 찍히고 `PASS`.

```
vt_test: 선택이 셀의 색을 맞바꾼다 OK
vt_test: 문자 선택과 y OK ('hello')
vt_test: 역방향 선택도 같은 글자를 준다 OK ('hello')
vt_test: 줄 선택이 끝 공백을 트림한다 OK ('second line')
vt_test: v를 다시 누르면 선택이 풀린다 OK
vt_test: 가지치기가 copy mode를 끊는다 OK
```

**검사 5의 색이 걸리면 Task 3을 아직 안 했기 때문이다.** `cells()`가 선택을
읽는 코드는 다음 Task에 있다 — Step 6을 넣은 직후에는 `SelectionNotInverted`가
나는 것이 정상이다. Task 3을 끝내고 다시 돌린다.

> 순서를 이렇게 잡은 것이 의도다. **검사를 먼저 깨뜨려 놓고 구현으로 통과시킨다.**

### Step 8: 커밋 (Claude가 실행)

**Task 3까지 통과한 뒤에** 커밋한다(검사가 빨간 상태로 커밋하지 않는다).
Task 3 Step 3에서 한 번에 커밋한다.

---

## Task 3: `cells()`가 선택 영역을 반전한다

**Files:**
- Modify: `terminal/src/vt.zig`

### Step 1: 행별 선택 범위를 꺼낸다

`vt.zig:137-139`를 **지울 것**:

```zig
        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
```

**넣을 것**:

```zig
        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
        // 그 행에서 선택된 x 범위. **라이브러리가 채워 준다**
        // (`render.zig`가 `sel.topLeft()`/`bottomRight()`로 계산한다). 절대 행
        // 번호를 우리가 세지 않는 이유가 이것이다(design 결정 6).
        const row_sels = row_data.items(.selection);
```

### Step 2: 범위 안의 셀에서 색 둘을 맞바꾼다

`vt.zig:173-188`을 **지울 것**:

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

**넣을 것**:

```zig
                // 선택 영역도 inverse·커서와 **같은 연산**이다(design 결정 6).
                // 그래서 렌더러는 "선택"이라는 말을 배우지 않는다. 양 끝을
                // 포함하는 범위다(`render.zig`가 `start.x <= end.x`를 단언한
                // 뒤 그대로 담는다).
                if (row_sels[y]) |range| {
                    if (x >= @as(usize, range[0]) and x <= @as(usize, range[1])) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }

                // 커서는 inverse와 **같은 연산**이다(design 결정 2). 그래서
                // 렌더러는 커서라는 것도 배우지 않는다. 뷰포트 밖으로
                // 나가면 viewport가 null이므로 TR-M2가 이 자리를 다시
                // 손대지 않아도 된다.
                //
                // **copy mode 중에는 셸 커서를 그리지 않는다**(CM-M0). 반전된
                // 셀이 둘이면 게이트가 어느 것이 copy 커서인지 못 가른다.
                //
                // 커서가 선택 안에 있으면 위에서 한 번, 여기서 또 한 번
                // 맞바뀌어 **원래 색으로 돌아온다**(CM-M1). 예외를 두지 않는다 —
                // 반전된 띠 가운데 뚫린 구멍이 곧 커서라 오히려 잘 보이고,
                // 예외를 넣으면 "선택"이 렌더 쪽으로 새어 나간다.
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

### Step 2b: 호스트 검사를 다시 돌린다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: Task 2 Step 7의 여섯 줄이 전부 찍히고 `PASS`.

### Step 3: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Let the screen hold a selection and a clipboard"
```

---

## Task 4: `main.zig`에 배선과 `clip>` 로그를 넣는다

**Files:**
- Modify: `terminal/src/main.zig`

### Step 1: `dumpClip`을 만든다

`main.zig:266-273`의 `dumpCopy` **바로 뒤에 넣을 것**(지울 것 없음):

```zig
/// `y`가 클립보드에 무엇을 담았는지를 찍는다.
///
/// **게이트가 클립보드를 볼 수 있는 유일한 창구다.** 화면만 보면 복사가 됐는지
/// 알 방법이 아예 없다 — 복사는 화면을 안 바꾼다.
///
/// `len`을 함께 찍는 이유는 글자가 잘리거나 뒤에 뭐가 더 붙는 경우를 게이트가
/// 한 줄로 가릴 수 있게 하기 위해서다. `text=`가 맞아도 `len=`이 다르면 그것은
/// 다른 문자열이다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8).
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpClip(text: ?[]const u8) void {
    if (text) |t| {
        std.debug.print("terminal: clip> len={d} text={s}\n", .{ t.len, t });
    } else {
        // 선택이 없는데 y를 눌렀다. 조용히 넘어가면 게이트가 "복사가 안 됐다"와
        // "y가 아예 안 도착했다"를 못 가른다.
        std.debug.print("terminal: clip> empty\n", .{});
    }
}
```

### Step 2: 키 루프의 switch에 세 팔을 더한다

`main.zig:447-458`을 **지울 것**:

```zig
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

**넣을 것**:

```zig
            for (keys.copies) |cmd| {
                switch (cmd) {
                    .enter => screen.copyEnter(),
                    .exit => screen.copyExit(),
                    .left => try screen.copyMove(-1, 0),
                    .down => try screen.copyMove(0, 1),
                    .up => try screen.copyMove(0, -1),
                    .right => try screen.copyMove(1, 0),
                    .select_char => try screen.copySelect(.char),
                    .select_line => try screen.copySelect(.line),
                    // yank는 **모드를 나간다.** 그래서 아래 dumpCopy는 좌표
                    // 없이 `copy> yank`만 찍는다 — 커서가 이미 사라졌기
                    // 때문이다.
                    .yank => dumpClip(try screen.copyYank()),
                }
                dumpCopy(screen, @tagName(cmd));
                needs_redraw = true;
            }
```

### Step 3: 가지치기로 모드가 끊긴 것을 찍는다

`main.zig:491-492`를 **지울 것**:

```zig
            if (!screen.copyActive()) screen.scrollToBottom();
            needs_redraw = true;
```

**넣을 것**:

```zig
            if (!screen.copyActive()) screen.scrollToBottom();
            // 위 feed가 가지치기를 만났으면 vt.zig가 모드를 이미 닫았다
            // (design 위험 1). **로그를 안 남기면 사람이 "왜 갑자기 모드가
            // 풀렸지"를 영영 모른다.**
            if (screen.copyTakePruned()) dumpCopy(screen, "pruned");
            needs_redraw = true;
```

### Step 4: 빌드와 호스트 검사를 함께 돌린다 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**`zig build`를 반드시 함께 돌린다.** `Copy`에 variant가 늘었고 `copyMove`의
반환이 넓어졌으므로, `readKeys`와 `main`을 실제로 컴파일하는 쪽이 아니면
안 걸리는 실수가 생긴다 — CM-M0에서 `State.scrolls`가 통째로 사라진 것을
`zig build test`가 두 번 놓친 자리다.

기대: 빌드 성공, 호스트 검사 `PASS`.

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/main.zig
git commit -m "Wire selection and yank into the terminal loop"
```

---

## Task 5: `copy/check.sh`가 게스트에서 복사를 본다

**Files:**
- Modify: `copy/check.sh`

### Step 1: `clip>` 마커와 프레임 헬퍼를 더한다

`copy/check.sh:83-93`의 marker 목록을 **지울 것**:

```bash
  for marker in \
    "terminal: screen>" \
    "terminal: copy>" \
    "terminal: scroll>" \
    "terminal: key>"; do
```

**넣을 것**:

```bash
  for marker in \
    "terminal: screen>" \
    "terminal: copy>" \
    "terminal: clip>" \
    "terminal: scroll>" \
    "terminal: key>"; do
```

`copy/check.sh:114-119`의 `copy_value` **바로 뒤에 넣을 것**(지울 것 없음):

```bash
# 마지막 프레임만 잘라낸다.
#
# **누적으로 세면 안 되는 이유**가 있다. style> 줄은 매 프레임 다시 찍히므로,
# 로그 전체에서 세면 "지금 화면이 어떻게 생겼는가"가 아니라 "부팅 이후 몇 번
# 찍혔는가"가 된다. main.zig가 한 프레임을 screen> 로 시작하므로(dumpScreen이
# render 직후 첫 번째다) 마지막 screen> 부터 파일 끝까지가 곧 마지막 프레임이다.
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

# 마지막 프레임에서 그 행의 **반전된 셀**이 몇 개인가.
#
# 기본 색은 fg=FFFFFF bg=102030이고(vt.zig의 init), 반전되면 정확히 뒤집힌
# 값이 된다. 선택도 커서도 "색 둘을 맞바꾼다"는 같은 연산이므로 둘 다 이
# 모양으로 나타난다 — 그래서 선택 **전후**를 비교해야 뜻이 생긴다.
inverted_cells() {
  last_frame | grep -acE "terminal: style> $1,[0-9]+ fg=102030 bg=FFFFFF" || true
}
```

### Step 2: 검사 일곱부터 아홉까지를 더한다

`copy/check.sh:290`의 NUL 검사

```bash
# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
```

**바로 앞에 넣을 것**(지울 것 없음):

```bash
# ── 검사 7: 복사할 줄을 만든다 ─────────────────────────────────────────
#
# 검사 6이 친 z가 입력줄에 남아 있다. 지우고 시작한다.
type_keys backspace
sleep 1

# 복사 대상을 `echo echo PASTED`의 **출력 줄**로 만드는 것이 요령이다
# (design 결정 7). sendkey로 따옴표를 치지 않아도 되고, 화면에 그 글자만
# 있는 줄이 하나 생긴다. 대문자는 shift-를 붙인다.
echo "=== typing 'echo echo PASTED' ==="
type_keys e c h o spc e c h o spc shift-p shift-a shift-s shift-t shift-e shift-d ret
sleep 3

# screen> 은 행 사이를 ' | '로 구분하므로(main.zig의 dumpScreen), "어떤 줄에
# 그 글자만 있다"는 '| echo PASTED |'로 쓸 수 있다.
if ! grep -aqF '| echo PASTED |' "$LOG"; then
  report_failure "the shell did not produce a line containing only 'echo PASTED'"
fi
echo "the output line is on the screen"

# ── 검사 8: 줄을 잡으면 그 줄이 반전되어 보인다 ────────────────────────
echo "=== entering copy mode again ==="
type_keys meta_l-shift-c
sleep 2
ROW_ENTER="$(copy_value row)"

# 출력 줄은 프롬프트 바로 위다. **커서는 언제나 맨 아랫줄(프롬프트)에서
# 시작하므로 위로 한 칸이 그 줄이다**(CM-M0 실측).
type_keys k
sleep 1
ROW_TARGET="$(copy_value row)"
if [ "$ROW_TARGET" -ne "$((ROW_ENTER - 1))" ]; then
  report_failure "k moved the cursor from row ${ROW_ENTER} to ${ROW_TARGET} (expected $((ROW_ENTER - 1)))"
fi

# 대조군. **선택하기 전에 그 줄에서 반전된 셀은 copy 커서 하나뿐이다.**
# 이것이 없으면 아래 검사가 "원래부터 색이 있었다"로도 통과한다.
BEFORE_SEL="$(inverted_cells "$ROW_TARGET")"
if [ "$BEFORE_SEL" -ne 1 ]; then
  report_failure "row ${ROW_TARGET} had ${BEFORE_SEL} inverted cell(s) before selecting (expected exactly 1: the copy cursor)"
fi

echo "=== selecting the line (V) ==="
type_keys shift-v
sleep 2
if ! grep -aqE "terminal: copy> select_line row=${ROW_TARGET} col=[0-9]+" "$LOG"; then
  report_failure "V did not produce a 'copy> select_line' line for row ${ROW_TARGET}"
fi

# `echo PASTED`는 11자다. 거기에 커서 셀이 하나 더 있다 — 커서는 col 11에
# 있고 선택은 col 0..10이라 겹치지 않기 때문이다. 겹쳤다면 두 번 뒤집혀
# 상쇄되므로 11이 된다. 그래서 하한을 11로 둔다.
AFTER_SEL="$(inverted_cells "$ROW_TARGET")"
if [ "$AFTER_SEL" -lt 11 ]; then
  report_failure "row ${ROW_TARGET} has ${AFTER_SEL} inverted cell(s) after V (expected at least 11)"
fi
echo "the selection reached the renderer (row ${ROW_TARGET}: ${BEFORE_SEL} -> ${AFTER_SEL} inverted cells)"

# ── 검사 9: y가 그 글자를 클립보드에 담고 모드를 닫는다 ────────────────
echo "=== yanking (y) ==="
type_keys y
sleep 2

# len과 text를 **한 줄에서 함께** 본다. text만 보면 뒤에 뭐가 더 붙어도
# 통과하고, len만 보면 다른 11자여도 통과한다.
if ! grep -aq 'terminal: clip> len=11 text=echo PASTED' "$LOG"; then
  report_failure "y did not put 'echo PASTED' on the clipboard"
fi
if ! grep -aq 'terminal: copy> yank' "$LOG"; then
  report_failure "no 'copy> yank' line — the yank command never reached main.zig"
fi
echo "the clipboard holds the output line"

# 대조군. **이것이 없으면 "복사는 했는데 모드에 갇혀 있다"가 통과한다.**
# key> 줄은 PTY로 바이트가 나갈 때만 찍히므로, 그것이 늘어나는 것이 곧
# "모드가 닫혔다"이다.
BEFORE_YANK_EXIT="$(key_lines)"
type_keys z
sleep 1
AFTER_YANK_EXIT="$(key_lines)"
if [ "$AFTER_YANK_EXIT" -le "$BEFORE_YANK_EXIT" ]; then
  report_failure "keys stopped reaching the PTY after y (key> stayed at ${BEFORE_YANK_EXIT})"
fi
echo "keys reach the PTY again after y (${BEFORE_YANK_EXIT} -> ${AFTER_YANK_EXIT})"

type_keys backspace
sleep 1
```

### Step 3: 마지막 줄의 이름을 고친다

`copy/check.sh`의 마지막 줄을 **지울 것**:

```bash
echo "CM-M0 check PASS"
```

**넣을 것**:

```bash
echo "CM-M1 check PASS"
```

### Step 4: 체인을 한 번 돌린다 (Claude가 실행, 약 6~8분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash copy/check.sh
```

기대: `CM-M1 check PASS`.

**검사 9의 `clip>`이 틀린 글자를 담고 걸리면 `k` 횟수 문제다.** 실패 출력의
`--- copy lines ---`와 함께 클립보드 줄을 확인한다. 프롬프트 글자가 섞여 나오면
출력 줄이 한 칸 더 위에 있다는 뜻이므로, 검사 8의 `type_keys k`를 두 번으로
늘리고 `ROW_TARGET` 비교식을 `$((ROW_ENTER - 2))`로 바꾼다. 실제 화면을 직접
보려면 한 번의 `docker run` 안에서 로그를 뒤진다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash copy/check.sh > /tmp/gate.out 2>&1
  grep -a "terminal: screen>" /tmp/tmp.* | tail -n 2
'
```

**검사 8의 대조군(`BEFORE_SEL -ne 1`)이 걸리면** 그 줄에 우리가 모르는 색이
있다는 뜻이다. `last_frame | grep style>`로 무엇이 찍혔는지 보고, 셸 프롬프트가
색을 쓰기 시작한 것이라면 대상 줄을 바꾸는 대신 대조군의 기대값을 실제 값으로
고치고 **왜 그 값인지를 주석에 적는다.**

### Step 5: 커밋 (Claude가 실행)

```bash
git add copy/check.sh
git commit -m "Prove a yank reaches the clipboard inside the guest"
```

---

## Task 6: 루트 게이트를 3/3으로 돌린다

**Files:**
- Modify: `check.sh`

### Step 1: 체인 이름을 고친다

`check.sh:109`를 **지울 것**:

```bash
run_chain "CM-M0" ./copy/check.sh
```

**넣을 것**:

```bash
run_chain "CM-M1" ./copy/check.sh
```

### Step 2: 루트 게이트를 돌린다 (Claude가 백그라운드로 실행, 약 55분)

**Bash 도구의 10분 타임아웃을 넘으므로 `run_in_background`로 돌린다.**
직전 기준선은 **51분 20초**다(2026-08-24, 한가한 기계). 이번에 부팅이 늘지는
않고 CM 체인의 타이핑이 회차당 20초쯤 는다(`echo echo PASTED` 16키 + 나머지).
그러니 **53~54분**을 기대한다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**시간을 재기 전에 기계를 비운다.** 값이 기준선에서 크게 벗어나면 코드를
의심하기 전에 기계를 먼저 의심한다 — TR-M2를 끝내며 처음 잰 값이 6시간
12분이었고 원인은 Chrome이 영상을 재생하고 있던 것이었다.

### Step 3: 커밋 (Claude가 실행)

```bash
git add check.sh
git commit -m "Rename the copy chain for CM-M1"
```

---

## Task 7: 문서를 고친다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`
- Modify: `docs/decisions/project_copy_mode.md`
- Modify: `HANDOFF.md`

### Step 1: design doc에 CM-M1의 결과를 붙인다

"milestone 구성" 절의 CM-M0 인용 블록 **뒤에** CM-M1 블록을 붙인다. 적을 것은
넷이다.

1. **위험 1의 방어가 바뀌었다.** "selection이 null이 됐는지 본다"는 **영영 참이
   되지 않는 조건**이었다 — `PageList.erasePage`가 tracked pin을 무효로 만들지
   않고 이웃 페이지의 왼쪽 위로 옮긴다. 앵커의 screen 좌표 y를 기억해 두고
   비교하는 것으로 바꿨고, `vt_test`가 대조군과 함께 본다.
2. **위험 3이 해소됐다.** 역방향 선택을 라이브러리가 `topLeft`/`bottomRight`로
   정렬한다. `ordered()`를 쓰지 않았고, `vt_test`가 실행으로 확인했다.
3. **결정 7의 시나리오에서 `copy> exit`이 `copy> yank`가 됐다.** 명령 이름을
   그대로 찍기 때문이다. 줄을 하나 더 만들지 않았다.
4. **게이트 시간의 실측값.**

### Step 2: `project_copy_mode` 기억을 고친다

CM-M1이 끝났고 클립보드 버퍼가 실제로 생겼다는 것, 그리고 **가지치기 방어의
조건이 소스를 읽고 바뀌었다**는 것을 적는다. 두 번째가 중요하다 — 다음에 이
자리를 만지는 사람이 design doc의 옛 문장만 보고 다시 null 검사를 짜지 않게
한다.

### Step 3: `HANDOFF.md`를 다시 쓴다

- 진행 중인 서브프로젝트: Copy Mode(CM-M1 완료, 다음은 CM-M2)
- 게이트 현황: 여덟 체인, 새 기준선 시간
- 로그 문구 목록에 `terminal: clip>` 추가
- "CM-M1이 실측으로 알아낸 것"으로 위 Step 1의 넷을 옮긴다
- CM-M2가 해야 하는 것: `Cmd+V`는 `chord()`가 아니라 **copy 표에 넣을 수 없다** —
  붙여넣기는 모드 **밖에서**도 되어야 하므로(design 결정 4) `chord()`의 Meta
  분기에 들어간다. **CM-M0/M1의 `Cmd+C`와 자리가 다르다는 것을 적어 둔다.**
- 이월 숙제는 그대로 옮긴다

### Step 4: 커밋 (Claude가 실행)

```bash
git add HANDOFF.md docs/decisions/project_copy_mode.md \
  docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md
git commit -m "Record what CM-M1 settled"
```

---

## 게이트가 못 보는 것 (적어 두고 넘어간다)

`project_gate_chain_composition`이 "못 보는 것을 적어 두라"고 한 자리다.

- **문자 선택(`v`)과 역방향 선택.** 게이트는 `V`만 누른다. 게스트에서 문자
  선택을 검사하려면 커서를 정확한 칸까지 옮기는 `sendkey`가 십여 개 더 필요한데,
  체인 1회가 회차당 1분 53초이고 3회 도는 것을 감안해 `vt_test`에 맡겼다.
- **가지치기 방어.** copy mode 중에 1000줄을 쏟아부을 방법이 없다 — 모드 안에서는
  셸에 아무것도 보낼 수 없다. `vt_test`가 대조군과 함께 본다.
- **클립보드 버퍼의 수명.** `y`를 두 번 눌러 옛 문자열이 해제되는 경로는 게이트가
  안 밟는다. `vt_test`가 `y`를 네 번 부르므로 해제 경로 자체는 밟힌다.

## 완료 조건

- [ ] `zig build test`가 `input_test: copy mode OK`와 `vt_test: copy selection OK`를 찍는다
- [ ] `zig build`가 통과한다 (`Copy`에 variant를 더했으므로 함께 돌린다)
- [ ] `copy/check.sh` 단독 실행이 `CM-M1 check PASS`
- [ ] 루트 게이트 여덟 체인이 3/3
- [ ] 게이트 시간을 실측해 기록했다
- [ ] design doc·`project_copy_mode`·`HANDOFF.md`가 최신이다
