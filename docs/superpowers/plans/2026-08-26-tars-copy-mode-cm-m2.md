# TARS Copy Mode CM-M2 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** `Cmd+V`가 클립보드를 셸에 써 넣고, **CM-M1이 복사한 바로 그 글자가
붙여넣기를 거쳐 셸의 실행 결과로 화면에 다시 나타나는 것**을 게이트가 본다.
덤으로 CM-M0이 넣어 두고 아무도 밟은 적 없는 `scrollToBottom` 억제 분기를
실제 게스트에서 밟는다.

**Design doc:** `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`
(결정 4의 마지막 줄과 결정 7의 시나리오 6·7·8, 그리고 결정 9가 이 milestone의
몫이다. **design은 승인되어 있으므로 다시 논의하지 않는다.**)

**Tech Stack:** Zig 0.16, libghostty-vt, evdev, DRM dumb buffer,
QEMU monitor `sendkey`, bash 게이트 스크립트

**이 milestone이 Copy Mode의 마지막이다.** 끝나면 서브프로젝트가 닫히므로
Task 6의 문서 작업이 CM-M0·M1 때보다 한 겹 많다.

---

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

### CM-M0·CM-M1이 실측으로 남긴 것

1. **copy 커서는 언제나 화면 맨 아랫줄에서 시작한다**(`row=46`, 화면은 47줄).
   셸 프롬프트가 거기 있기 때문이다. 그래서 게이트는 `k`로 올라간다.
2. **`sendkey`를 0.05초 간격으로 80번 보내도 하나도 안 떨어진다.** 커서를 46줄
   올리고 뷰포트를 34줄 미는 데 정확히 80이 맞았다. **이번 Task 4의 검사 13이
   그 루프를 그대로 다시 쓴다.**
3. **`sendkey meta_l-shift-c`가 세 키 조합을 게스트까지 옮긴다.** 두 키 조합인
   `meta_l-v`는 그보다 쉬운 경우다.
4. **`terminal: key>` 줄은 PTY로 바이트가 나갈 때만 찍힌다.** 단, **붙여넣기는
   이 줄을 안 만든다** — `pty.write`를 직접 부르지 `keys.bytes`를 거치지 않기
   때문이다. 그래서 이번 게이트의 도구는 `key>`가 아니라 `clip>`와 `scroll>`다.
5. **`Action`이나 `Keys`를 건드리면 `zig build test`만으로 모자란다.** Zig가
   참조되지 않는 함수를 분석하지 않는다. **Task 3에서 `zig build`를 함께
   돌린다.**
6. **`RenderState`에서 격자 크기를 읽으면 조용히 no-op이 된다.** 이번 작업은
   `state`를 새로 읽는 자리를 만들지 않으므로 해당되지 않지만, 새 검사를 쓸
   때는 여전히 `cells()`를 한 번 부르고 시작한다.

### 이번 plan을 쓰면서 소스에서 확인한 것 넷

읽은 것을 믿고 넘어가지 않는다. **넷 다 아래 Task의 검사가 실행으로 다시
증명한다.**

1. **`Copy`에 variant를 더해도 `input_test`는 안 깨진다.** `expectCopy`와
   `expectCtx`는 `Action` union을 훑을 뿐 `Copy` enum을 훑지 않는다
   (`input_test.zig:60`·`:31`). **깨지는 것은 `main.zig:469`의 switch 하나
   뿐이다** — `HANDOFF.md`의 "`input_test`의 `expectCtx`·`expectCopy`도 같다"는
   `Action`을 넓힐 때의 이야기이고 이번에는 해당되지 않는다. 의도된 신호는
   그대로 하나 남아 있으므로 계획을 바꿀 이유는 없다.
2. **copy 표의 `KEY_V`가 이미 차 있다**(`input.zig:535`). `Cmd+V`를 모드 안에
   넣는다는 것은 줄을 하나 더하는 일이 아니라 **있는 줄을 세 갈래로 가르는**
   일이다. `HANDOFF.md`는 "양쪽에 들어가야 한다"까지만 적었고 이 충돌은 안
   적었다.
3. **`chord()`의 Meta 분기는 `switch (code)` 한 덩어리다**(`input.zig:418`).
   `Cmd+V`는 그 switch에 줄 하나로 들어간다. Shift 예외(`KEY_C`)는 그 위에
   따로 있으므로 건드리지 않는다 — design 위험 2가 "예외는 이 한 줄뿐이어야
   한다"고 못 박은 자리를 지킨다.
4. **`selectionString`은 줄 선택에도 개행을 안 붙인다.** CM-M1의 게이트가
   `len=11 text=echo PASTED`를 실측했다. **그래서 붙여넣기가 저절로 실행되지
   않는다** — Enter는 게이트가 따로 친다.

---

## 이번에 정하는 것 넷 (design doc이 안 정한 자리)

### 1. **붙여넣기는 모드를 닫지 않는다** (`y`와 갈리는 자리)

design 결정 4의 표는 `Cmd+V`를 "어느 모드에서든 클립보드를 PTY에 쓴다"까지만
정했다. 모드를 어떻게 하는지는 안 적었으므로 여기서 정한다. **아무것도 하지
않는다.**

이유가 둘이다.

- **design이 시킨 일만 한다.** `y`가 모드를 닫는 것은 결정 4의 표에 명시되어
  있고, `Cmd+V`에는 그런 문구가 없다.
- **게이트가 `scrollToBottom` 억제 분기를 밟을 수 있는 유일한 길이다.** 모드
  안에서는 셸에 아무것도 보낼 수 없어서 CM-M0·M1이 이 분기를 못 봤다
  (`main.zig:518`). 붙여넣기가 출력을 만드는데, **그 출력이 도착하는 순간에
  모드가 이미 닫혀 있으면 억제할 것이 없다.**

**대가를 감춘다면 정직하지 않다.** 뷰포트를 위로 올려 둔 채 모드 안에서
붙여넣으면 에코가 화면 밖(활성 영역 맨 아래)에 찍히므로 **사람 눈에는 아무 일도
안 일어난 것처럼 보인다.** Esc를 누르면 그때부터 다음 출력이 뷰포트를 바닥으로
되돌린다. 이 어긋남을 없애는 안("붙여넣으면 모드를 닫는다" 또는 "붙여넣으면
바닥으로 내린다")은 아래 "비워 두는 자리"에 적어 둔다.

### 2. 붙여넣기 로그는 **새 접두사를 만들지 않고** `clip>`를 쓴다

design 결정 8이 "새 로그 줄은 `copy>`와 `clip>` 둘뿐"이라고 정했다. 그래서
`paste>`를 만들지 않고 `terminal: clip> paste len=11`을 쓴다. 클립보드의
내용에 관한 줄이므로 접두사의 뜻과도 맞는다.

`text=`를 다시 찍지 않는 이유는 **같은 글자를 두 번 증명하지 않기 위해서다.**
무엇이 담겼는지는 `y` 시점의 `clip> len=11 text=echo PASTED`가 이미 증명했고,
붙여넣기가 증명해야 하는 것은 "그것이 셸에 닿았는가"인데 그 답은 로그가 아니라
**화면에 있다**(검사 11·12).

`len`을 찍는 이유는 CM-M1의 `dumpClip`과 같다 — 0바이트를 쓴 것과 11바이트를
쓴 것을 게이트가 한 줄로 가를 수 있어야 한다.

### 3. `main.zig`가 `screen.clip`을 직접 읽지 않는다

`clip`은 `pub` 필드라 `main.zig`가 그냥 읽을 수 있지만, 접근자
`Screen.clipboard()`를 만든다. `copyCursor()`·`scrollbar()`와 같은 규율이다
(TR design 결정 1: `main.zig`가 라이브러리 타입을 배우지 않는다). 반환 타입을
`?[]const u8`로 좁혀서 **소유권이 `Screen`에 있다는 것을 타입으로도 드러낸다** —
`clip` 자체는 `?[:0]const u8`이고, sentinel을 밖으로 내보내면 호출부가 그것을
직접 free해도 되는 값으로 오해할 여지가 생긴다.

### 4. 게이트는 왕복을 **화면에서 두 번** 센다

design 결정 7의 시나리오 6·8이 짝을 이루는 대조군이라고 적어 두었다. 그것을
그대로 짜되, 검사 11에 한 겹을 더 둔다.

- **검사 10(대조군)** — 붙여넣기 전에 `| PASTED |`가 **로그 전체에 없다.**
- **검사 11** — 붙여넣기 직후 마지막 프레임의 `echo PASTED` 횟수가 **는다.**
  절대값을 쓸 수 없는 이유는, 검사 7이 친 명령줄 `echo echo PASTED`가 부분
  문자열로 걸려서 붙여넣기 전에 이미 둘이기 때문이다. **전후 차이를 본다.**
- **검사 12(판정)** — Enter 뒤에 `| PASTED |`가 나타난다.

---

## Task 1: `input.zig`에 `Cmd+V`를 **두 곳** 넣는다

**Files:**
- Modify: `terminal/src/input.zig`
- Test: `terminal/src/input_test.zig`

### Step 1: `Copy` enum에 `paste`를 더한다

`input.zig:169-188`을 **지울 것**:

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

**넣을 것**:

```zig
/// copy mode 안에서 키가 만드는 명령.
///
/// **CM-M2로 표가 닫혔다.** CM-M0부터 지켜 온 규율은 "쓰지 않을 variant를 미리
/// 만들어 두지 않는다"였다 — `main.zig`의 switch가 `else` 없이 닫혀 있어서,
/// variant를 더하는 순간 컴파일러가 배선할 자리를 알려주기 때문이다. 미리
/// 만들어 두면 그 신호를 잃는다. 다음에 표를 늘릴 사람도 같은 순서로 하면 된다.
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
    /// `Cmd+V` — 클립보드를 PTY에 쓴다. **모드를 건드리지 않는다.**
    ///
    /// 이 variant만 모드 **밖에서도** 만들어진다(design 결정 4). 그래서
    /// `chord()`의 Meta 분기와 copy 표 **양쪽에** 같은 뜻이 적혀 있다 —
    /// 한쪽만 넣으면 나머지 모드에서 조용히 안 먹는다.
    paste,
};
```

### Step 2: `chord()`의 Meta 분기에 한 줄을 더한다

`input.zig:418-427`을 **지울 것**:

```zig
            return switch (code) {
                c.KEY_LEFT => .{ .bytes = self.one(0x01) }, // beginning-of-line
                c.KEY_RIGHT => .{ .bytes = self.one(0x05) }, // end-of-line
                // 0x15는 bash에서 커서 앞까지, zsh에서는 줄 전체를 지운다.
                // macOS의 Cmd+Backspace는 bash 쪽이다 — 셸을 바꿔 끼울 수
                // 있는 시스템에서 이 어긋남은 A안을 고른 대가이고, 감추지
                // 않고 여기 적어둔다(design doc 결정 8).
                c.KEY_BACKSPACE => .{ .bytes = self.one(0x15) },
                else => null,
            };
```

**넣을 것**:

```zig
            return switch (code) {
                c.KEY_LEFT => .{ .bytes = self.one(0x01) }, // beginning-of-line
                c.KEY_RIGHT => .{ .bytes = self.one(0x05) }, // end-of-line
                // 0x15는 bash에서 커서 앞까지, zsh에서는 줄 전체를 지운다.
                // macOS의 Cmd+Backspace는 bash 쪽이다 — 셸을 바꿔 끼울 수
                // 있는 시스템에서 이 어긋남은 A안을 고른 대가이고, 감추지
                // 않고 여기 적어둔다(design doc 결정 8).
                c.KEY_BACKSPACE => .{ .bytes = self.one(0x15) },
                // Cmd+V(CM-M2). **이 줄은 모드 밖의 붙여넣기만 담당한다** —
                // 모드 안에서는 아래 copy 표가 chord()보다 먼저라 여기까지
                // 오지 않으므로, 같은 뜻이 그쪽에도 적혀 있다(design 결정 4).
                //
                // 바이트가 아니라 copy 명령인 이유는, 무엇을 보낼지가
                // 클립보드에 달려 있고 클립보드는 vt.zig가 들기 때문이다.
                // input.zig는 vt.zig를 import하지 않는다(IP design 결정 6).
                c.KEY_V => .{ .copy = .paste },
                else => null,
            };
```

### Step 3: copy 표의 `KEY_V`를 세 갈래로 가른다

**여기가 이 Task에서 가장 놓치기 쉬운 자리다.** `KEY_V`는 이미 차 있다.

`input.zig:532-537`을 **지울 것**:

```zig
                // Shift를 여기서 보는 것은 chord()의 예외와 성격이 다르다.
                // 모드 안의 표는 원래 문자 키를 직접 읽으므로, 대문자 V가
                // 소문자 v와 다른 명령이라는 것을 볼 자리가 여기뿐이다.
                c.KEY_V => return .{
                    .copy = if (self.shifted()) .select_line else .select_char,
                },
```

**넣을 것**:

```zig
                // `v` 하나가 세 갈래다(CM-M2에서 늘었다).
                //
                //   Cmd+V   → 붙여넣기. **모드를 닫지 않는다.**
                //   Shift+V → 줄 선택
                //   v       → 문자 선택
                //
                // **Meta를 가장 먼저 보는 것은 chord()의 규칙과 같다** — 둘 다
                // 눌렸을 때 Cmd가 이긴다. 임의의 선택이지만 결정적이어야 해서
                // 두 곳이 같은 순서를 쓴다.
                //
                // Shift를 여기서 보는 것은 chord()의 예외와 성격이 다르다.
                // 모드 안의 표는 원래 문자 키를 직접 읽으므로, 대문자 V가
                // 소문자 v와 다른 명령이라는 것을 볼 자리가 여기뿐이다.
                c.KEY_V => {
                    if (self.metaed()) return .{ .copy = .paste };
                    return .{
                        .copy = if (self.shifted()) .select_line else .select_char,
                    };
                },
```

### Step 4: `input_test.zig`에 검사 셋을 더한다

`input_test.zig:570`의

```zig
    std.debug.print("input_test: copy mode OK\n", .{});
```

**바로 앞에 넣을 것**(지울 것 없음):

```zig
    // ── CM-M2: 붙여넣기 ─────────────────────────────────────────────────
    //
    // 검사 11. **Cmd+V는 모드 밖에서도 붙여넣는다**(design 결정 4). 여기가
    // Cmd+C와 갈리는 자리다 — Cmd+C는 모드 안에서만 뜻이 있어서 copy 표 한
    // 곳이면 됐지만, Cmd+V는 chord()의 Meta 분기에도 있어야 한다.
    //
    // 대조군으로 Cmd 없는 v가 여전히 평범한 글자라는 것을 먼저 본다.
    // **이것이 없으면 "v는 언제나 paste"도 통과한다.**
    try expect(&cm, K.KEY_V, 1, "v");
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expectCopy(&cm, K.KEY_V, .paste);
    if (cm.mode != .normal) {
        std.debug.print("FAIL: Cmd+V outside copy mode changed the mode\n", .{});
        return error.PasteChangedMode;
    }
    try expect(&cm, K.KEY_LEFTMETA, 0, "");

    // 검사 12. 모드 **안에서도** 붙여넣는다. copy 분기가 chord()보다 앞이라
    // 모드 안에서는 Cmd 조합이 chord()에 아예 닿지 않으므로, 같은 뜻을 표
    // 양쪽에 적어야 한다. **한쪽만 넣으면 나머지 모드에서 조용히 안 먹는다.**
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expectCopy(&cm, K.KEY_V, .paste);

    // **붙여넣기는 모드를 닫지 않는다** — y와 갈리는 자리다. 게이트의 억제
    // 검사가 이 성질에 기댄다: 모드가 닫히면 에코가 도착할 때
    // scrollToBottom이 그대로 불려서 볼 것이 없어진다.
    if (cm.mode != .copy) {
        std.debug.print("FAIL: Cmd+V inside copy mode closed the mode\n", .{});
        return error.PasteLeftCopyMode;
    }
    try expect(&cm, K.KEY_LEFTMETA, 0, "");

    // 검사 13. Cmd를 뗀 v는 모드 안에서 다시 선택 명령이다. **Meta 분기가 v를
    // 통째로 가져가지 않았다**는 것을 이 셋이 못 박는다 — Step 3에서 갈라 놓은
    // 세 갈래를 나란히 보는 자리다.
    try expectCopy(&cm, K.KEY_V, .select_char);
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_V, .select_line);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expectCopy(&cm, K.KEY_ESC, .exit);
```

**주의.** `expectCopy`는 `handleKey(code, 1, .{})`를 부르므로 **누름(1)만 본다.**
modifier를 떼는 이벤트(value 0)는 언제나 `expect`로 본다.

### Step 5: 호스트 검사를 돌린다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: `input_test: copy mode OK`가 찍히고 `PASS`.

**이 시점에 `main.zig`는 아직 안 고쳤고, 그래서 `zig build`는 깨져 있다.**
`Copy`에 variant가 늘어 `main.zig:469`의 switch가 더는 exhaustive하지 않기
때문이다. **의도된 신호이고 Task 3이 끈다** — `zig build test`는 `main.zig`를
컴파일하지 않으므로 여기서는 안 걸린다.

### Step 6: 커밋 (Claude가 실행)

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Teach both key tables what Cmd+V means"
```

---

## Task 2: `vt.zig`가 클립보드를 되읽게 한다

**Files:**
- Modify: `terminal/src/vt.zig`
- Test: `terminal/src/vt_test.zig`

### Step 1: 접근자를 더한다

`vt.zig:477`의 `copyYank` 닫는 중괄호

```zig
        self.copyExit();
        return text;
    }
```

**바로 뒤에 넣을 것**(지울 것 없음):

```zig
    /// 클립보드의 지금 내용. `y`를 한 번도 안 눌렀으면 null이다.
    ///
    /// `main.zig`가 `self.clip`을 직접 읽지 않게 하려고 함수로 낸다 —
    /// `copyCursor`·`scrollbar`와 같은 규율이다(TR design 결정 1).
    ///
    /// 반환 타입이 `?[]const u8`인 것에 뜻이 있다. `clip`은 실제로
    /// `?[:0]const u8`인데, sentinel을 밖으로 내보내면 호출부가 그것을 직접
    /// free해도 되는 값으로 오해할 여지가 생긴다. **소유권은 `Screen`에 있고
    /// 다음 `y`가 옛것을 해제한다.**
    ///
    /// `return self.clip;` 한 줄로 줄이지 않는다. 그렇게 쓰면 `?[:0]const u8`을
    /// `?[]const u8`로 바꾸는 일을 **optional 껍질을 쓴 채** 요구하게 된다.
    /// 먼저 풀고 나서 돌려주면 sentinel을 떼는 평범한 슬라이스 coercion이 되고,
    /// 그 형태는 바로 위 `copyYank`가 이미 쓰고 있는 것이다.
    pub fn clipboard(self: *const Screen) ?[]const u8 {
        const text = self.clip orelse return null;
        return text;
    }
```

### Step 2: `vt_test.zig`에 검사 하나를 더한다

`vt_test.zig:510-511`을 **지울 것**:

```zig
    std.debug.print("vt_test: 가지치기가 copy mode를 끊는다 OK\n", .{});
    std.debug.print("vt_test: copy selection OK\n", .{});
```

**넣을 것**:

```zig
    std.debug.print("vt_test: 가지치기가 copy mode를 끊는다 OK\n", .{});

    // ── CM-M2: 클립보드를 되읽는다 ──────────────────────────────────────
    //
    // 검사 10. `clipboard()`가 마지막 y의 결과를 그대로 들고 있다.
    //
    // **검사 8이 아무것도 못 담은 y를 불렀는데도 값이 남아 있어야 한다.**
    // 빈 yank가 클립보드를 지우면 붙여넣기가 조용히 사라지는데, 그 사고는
    // 게이트가 못 본다 — 게이트는 y를 한 번만 누른다.
    const held = cm.clipboard() orelse {
        std.debug.print("FAIL: the clipboard is empty after four yanks\n", .{});
        return error.ClipboardEmpty;
    };
    if (!std.mem.eql(u8, held, "second line")) {
        std.debug.print("FAIL: the clipboard holds '{s}' (expected 'second line')\n", .{held});
        return error.WrongClipboard;
    }

    // 대조군. y를 한 번도 안 부른 화면의 클립보드는 null이다. **이것이 없으면
    // "clipboard()가 언제나 무언가를 준다"도 통과한다.**
    if (pruned.clipboard() != null) {
        std.debug.print("FAIL: a screen that never yanked already has a clipboard\n", .{});
        return error.ClipboardNotEmpty;
    }
    std.debug.print("vt_test: 클립보드를 되읽는다 OK ('{s}')\n", .{held});

    std.debug.print("vt_test: copy selection OK\n", .{});
```

**`held`가 `"second line"`인 이유를 짚어 둔다.** `cm` 화면 위에서 `y`가 네 번
불렸다 — 검사 5가 `hello`, 검사 6이 `hello`(역방향), 검사 7이 `second line`,
검사 8이 **선택이 풀린 뒤라 null**을 돌려줬다. `copyYank`는 선택이 없으면
`self.clip`을 건드리지 않고 나가므로 검사 7의 값이 남아 있다.

### Step 3: 호스트 검사를 돌린다 (Claude가 실행, 약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 아래 줄이 새로 찍히고 `PASS`.

```
vt_test: 클립보드를 되읽는다 OK ('second line')
```

### Step 4: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Let the screen hand its clipboard back"
```

---

## Task 3: `main.zig`가 클립보드를 PTY에 쓴다

**Files:**
- Modify: `terminal/src/main.zig`

### Step 1: `dumpPaste`를 만든다

`main.zig:286-294`의 `dumpClip` **바로 뒤에 넣을 것**(지울 것 없음):

```zig
/// `Cmd+V`가 클립보드를 셸에 쓴다.
///
/// 쓰는 일과 찍는 일을 한 함수에 둔 이유는 **길이가 두 곳에서 갈리지 않게**
/// 하기 위해서다. 게이트가 `len=11`을 보고 "11바이트가 나갔다"로 읽는데, 쓰기와
/// 로그가 떨어져 있으면 그 둘이 다른 슬라이스를 볼 여지가 생긴다.
///
/// **bracketed paste로 감싸지 않는다**(design 결정 9). 여러 줄을 붙이면 개행이
/// 곧 실행이 되는 것을 감수한다 — 셸이 그 모드를 받는지 확인한 적이 없고,
/// 확인 없이 넣으면 게이트가 못 보는 코드가 느는 것이
/// `project_gate_chain_composition`이 경고한 부채 그대로다.
///
/// 새 접두사를 만들지 않고 `clip>`를 쓰는 것은 design 결정 8이다. 문구가 이
/// 파일과 `copy/check.sh` 양쪽에 중복된다 — **한쪽을 고치면 다른 쪽도 고쳐야
/// 한다.**
fn dumpPaste(screen: *vt.Screen, master_fd: c_int) void {
    const text = screen.clipboard() orelse {
        // 아직 아무것도 복사하지 않았는데 Cmd+V를 눌렀다. 조용히 넘어가면
        // 게이트가 "클립보드가 비었다"와 "Cmd+V가 아예 안 도착했다"를 못 가른다.
        std.debug.print("terminal: clip> paste empty\n", .{});
        return;
    };
    pty.write(master_fd, text);
    std.debug.print("terminal: clip> paste len={d}\n", .{text.len});
}
```

### Step 2: switch에 팔 하나를 더한다

`main.zig:468-485`를 **지울 것**:

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
                    // 붙여넣기는 **모드를 건드리지 않는다.** 그래서 모드 안에서
                    // 누르면 아래 dumpCopy가 좌표를 그대로 찍고, 모드 밖에서
                    // 누르면 `copy> paste`만 찍힌다. 게이트가 그 차이로 "모드가
                    // 살아 있는가"를 본다.
                    //
                    // 이것이 copies 배열에서 **유일하게 PTY로 나가는 명령**이다.
                    // 다른 아홉은 전부 우리 안에서 끝난다.
                    .paste => dumpPaste(screen, session.master_fd),
                }
                dumpCopy(screen, @tagName(cmd));
                needs_redraw = true;
            }
```

### Step 3: 억제 주석의 마지막 문단을 고친다

CM-M0이 남긴 문장이 "CM-M1이 방어를 넣는다"에서 멈춰 있고, 그 방어가 실제로는
다른 모양이 됐다(가지치기는 선택을 null로 만들지 않는다). 그리고 이제 이 분기를
게이트가 실제로 밟으므로 그 사실을 적는다.

`main.zig:512-517`을 **지울 것**:

```zig
            // 그 대가로 위 주석이 말한 창이 열린다 — 뷰포트가 history에
            // 머무는 동안 가지치기가 일어날 수 있게 된다(design 위험 1).
            // copy mode 중에 1000줄이 쏟아져야 닿는 자리라 게이트로 만들지
            // 않았고, CM-M1이 선택이 무효가 됐는지를 매 프레임 보는 방어를
            // 넣는다.
```

**넣을 것**:

```zig
            // 그 대가로 위 주석이 말한 창이 열린다 — 뷰포트가 history에
            // 머무는 동안 가지치기가 일어날 수 있게 된다(design 위험 1).
            // CM-M1이 방어를 넣었는데, **계획했던 모양이 아니다**: 가지치기는
            // 선택을 null로 만들지 않고 tracked pin을 이웃 페이지의 왼쪽 위로
            // 옮기므로, vt.zig의 feed가 앵커의 screen 좌표 y를 대신 감시한다.
            //
            // **이 억제 분기 자체는 CM-M2의 게이트가 밟는다.** 모드 안에서는
            // 셸에 아무것도 보낼 수 없어 출력을 만들 방법이 없었는데,
            // Cmd+V가 그 방법이 됐다 — 붙여넣은 글자를 셸이 되울리는 것이
            // 곧 "모드 중에 도착한 PTY 출력"이다.
```

### Step 4: 빌드와 호스트 검사를 함께 돌린다 (Claude가 실행, 약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**`zig build`를 반드시 함께 돌린다.** `Copy`에 variant를 더했으므로 `readKeys`와
`main`을 실제로 컴파일하는 쪽이 아니면 안 걸리는 실수가 생긴다 — CM-M0에서
`State.scrolls`가 통째로 사라진 것을 `zig build test`가 두 번 놓친 자리다.

기대: 빌드 성공, 호스트 검사 `PASS`. **Task 1 Step 5에서 깨져 있던 빌드가 이
Step에서 다시 붙는다.**

### Step 5: 커밋 (Claude가 실행)

```bash
git add terminal/src/main.zig
git commit -m "Send the clipboard to the shell on Cmd+V"
```

---

## Task 4: `copy/check.sh`가 게스트에서 왕복을 본다

**Files:**
- Modify: `copy/check.sh`

### Step 1: 헬퍼 둘을 더하고 스크롤 조회를 하나로 모은다

`copy/check.sh:137-139`의 `inverted_cells` **바로 뒤에 넣을 것**(지울 것 없음):

```bash
# scroll> 줄에서 값 하나를 뽑는다. copy_value와 같은 모양이고, **언제나 마지막
# 줄을 본다** — 그 줄이 곧 지금의 뷰포트 위치다.
scroll_field() {
  grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
    sed -E "s/.*$1=([0-9]+).*/\1/"
}

# 마지막 프레임의 화면 줄에서 그 문자열이 몇 번 나오는가.
#
# **누적으로 세면 안 된다.** screen> 줄은 매 프레임 다시 찍히므로 로그 전체에서
# 세면 "부팅 이후 몇 번 찍혔는가"가 된다. last_frame이 그것을 막는다.
#
# grep -o는 겹치는 매치를 세지 않는다. 아래 검사들이 세는 두 문자열은 화면에서
# 서로 떨어져 나타나므로(사이에 프롬프트 줄이 있다) 문제가 되지 않는다.
screen_count() {
  last_frame | grep -a 'terminal: screen>' | grep -oaF "$1" | wc -l
}
```

`copy/check.sh:272-273`과 `:280-281`(검사 5의 인라인 sed 둘)을 **지울 것**:

```bash
SCROLL_BEFORE="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
  sed -E 's/.*offset=([0-9]+).*/\1/')"
```

```bash
SCROLL_AFTER="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1 |
  sed -E 's/.*offset=([0-9]+).*/\1/')"
```

**넣을 것**(각각 한 줄로):

```bash
SCROLL_BEFORE="$(scroll_field offset)"
```

```bash
SCROLL_AFTER="$(scroll_field offset)"
```

### Step 2: 체인 머리 주석에 붙여넣기를 더한다

`copy/check.sh:8-14`를 **지울 것**:

```bash
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Cmd+Shift+C를 누른다
#   → evdev가 KEY_LEFTMETA·KEY_LEFTSHIFT·KEY_C를 올린다
#   → input.zig의 chord()가 그것을 .copy = .enter로 바꾸고 모드를 연다
#   → main.zig가 vt.zig의 copy 커서를 만들고 copy> 줄을 찍는다
#   → 모드 안에서 친 키가 **PTY로 나가지 않는다**
#   → Esc로 나오면 다시 나간다
```

**넣을 것**:

```bash
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Cmd+Shift+C를 누른다
#   → evdev가 KEY_LEFTMETA·KEY_LEFTSHIFT·KEY_C를 올린다
#   → input.zig의 chord()가 그것을 .copy = .enter로 바꾸고 모드를 연다
#   → main.zig가 vt.zig의 copy 커서를 만들고 copy> 줄을 찍는다
#   → 모드 안에서 친 키가 **PTY로 나가지 않는다**
#   → V로 잡은 줄이 화면에서 반전되고 y가 그 글자를 클립보드로 옮긴다
#   → Cmd+V가 그 글자를 셸에 써 넣고, Enter를 치면 셸이 그것을 실행한다
#   → **복사한 글자가 실행 결과로 화면에 다시 나타난다**
#   → Esc로 나오면 다시 나간다
#
# **마지막 줄이 CM-M2가 더하는 값이다.** 클립보드에 글자가 담겼다는 것까지는
# CM-M1이 로그로 증명했지만, 그것이 셸에 닿는다는 것은 왕복으로만 증명된다.
```

### Step 3: 검사 열부터 열셋까지를 더한다

`copy/check.sh:398`의 NUL 검사

```bash
# ── 음성 검사: 로그에 NUL이 섞이지 않았다 ──────────────────────────────
```

**바로 앞에 넣을 것**(지울 것 없음):

```bash
# ── 검사 10: 대조군 — 붙여넣기 전에는 그 줄이 어디에도 없다 ────────────
#
# **이것이 없으면 아래 검사 12가 "원래부터 화면에 있었다"로도 통과한다**
# (design 결정 7의 시나리오 6). IP-M0이 sleep에서 데인 것과 같은 병이고,
# project_gate_chain_composition이 "성공 경로가 하나뿐인가"를 물으라고 적어
# 둔 자리다.
#
# screen> 은 행 사이를 ' | '로 구분하므로 '| PASTED |'는 **그 글자만 있는 줄**을
# 뜻한다. 검사 7이 만든 '| echo PASTED |'와는 겹치지 않는다 — 거기서 PASTED
# 앞에 오는 것은 '| '가 아니라 'o '다.
#
# 마지막 프레임이 아니라 **로그 전체**를 보는 것이 일부러다. "지금 화면에
# 없다"보다 "지금까지 한 번도 없었다"가 더 강한 대조군이다.
if grep -aqF '| PASTED |' "$LOG"; then
  report_failure "a line containing only 'PASTED' was on the screen before any paste"
fi
echo "control: nothing has printed 'PASTED' on a line of its own yet"

# ── 검사 11: Cmd+V가 클립보드를 셸의 입력줄에 써 넣는다 ────────────────
#
# 붙여넣기는 화면에 **입력줄의 에코**로 나타난다. 그것을 'echo PASTED'의
# 등장 횟수로 세는데, **절대값을 쓸 수 없다** — 붙여넣기 전에 이미 둘이다.
# 검사 7이 친 명령줄 'echo echo PASTED'가 부분 문자열로 걸리고, 그 출력줄이
# 하나 더 있기 때문이다. 그래서 전후 차이를 본다.
#
# key> 줄은 여기서 쓸 수 없다. 붙여넣기는 pty.write를 직접 부르지
# keys.bytes를 거치지 않으므로 그 줄을 만들지 않는다.
ECHOES_BEFORE="$(screen_count 'echo PASTED')"
echo "=== pasting (Cmd+V) ==="
type_keys meta_l-v
sleep 3

if ! grep -aq 'terminal: clip> paste len=11' "$LOG"; then
  report_failure "Cmd+V did not write the 11-byte clipboard to the PTY"
fi
ECHOES_AFTER="$(screen_count 'echo PASTED')"
if [ "$ECHOES_AFTER" -le "$ECHOES_BEFORE" ]; then
  report_failure "the pasted text never showed up on screen ('echo PASTED' stayed at ${ECHOES_BEFORE})"
fi
echo "the clipboard reached the shell (echoes ${ECHOES_BEFORE} -> ${ECHOES_AFTER})"

# ── 검사 12: 판정 — 왕복이 닫힌다 ──────────────────────────────────────
#
# 붙여넣은 것이 실행되면 'PASTED'만 있는 줄이 새로 생긴다. 검사 10과 짝을
# 이루는 자리이고, **이 체인 전체가 증명하려는 한 문장이 여기서 참이 된다** —
# 화면에서 잡은 글자가 클립보드를 거쳐 셸까지 돌아왔다.
echo "=== running the pasted command (Enter) ==="
type_keys ret
sleep 3
if ! grep -aqF '| PASTED |' "$LOG"; then
  report_failure "the pasted command did not produce a line containing only 'PASTED'"
fi
echo "the round trip closed: a yanked line came back as the shell's output"

# ── 검사 13: copy mode 중에는 뷰포트가 출력을 따라가지 않는다 ──────────
#
# **CM-M0이 넣어 두고 아무도 밟은 적 없는 분기다**(main.zig의
# `if (!screen.copyActive()) screen.scrollToBottom();`). 모드 안에서는 셸에
# 아무것도 보낼 수 없어 출력을 만들 방법이 없었는데, 붙여넣기가 그 방법이 된다.
#
# 억제를 보려면 뷰포트가 **바닥이 아니어야 한다.** 바닥에 있으면
# scrollToBottom이 원래 아무 일도 안 하므로 억제했는지 안 했는지 구분되지
# 않는다. 그래서 먼저 위로 올린다.
echo "=== entering copy mode and scrolling up ==="
type_keys meta_l-shift-c
sleep 2
OFFSET_BOTTOM="$(scroll_field offset)"

# 커서를 맨 윗줄까지 올리고(화면이 47줄이라 46번) 한참 더 올린다. 80번을
# 0.05초 간격으로 보내도 하나도 안 떨어지는 것은 CM-M0이 실측했다.
for _ in $(seq 1 80); do
  echo "sendkey k" >&3
  sleep 0.05
done
sleep 2
OFFSET_UP="$(scroll_field offset)"
if [ "$OFFSET_UP" -ge "$OFFSET_BOTTOM" ]; then
  report_failure "the viewport did not scroll up before the paste (offset ${OFFSET_BOTTOM} -> ${OFFSET_UP})"
fi

echo "=== pasting inside copy mode ==="
PASTES_BEFORE="$(grep -ac 'terminal: clip> paste len=11' "$LOG" || true)"
type_keys meta_l-v
sleep 3
PASTES_AFTER="$(grep -ac 'terminal: clip> paste len=11' "$LOG" || true)"
if [ "$PASTES_AFTER" -le "$PASTES_BEFORE" ]; then
  report_failure "Cmd+V did nothing inside copy mode (clip> paste count stayed at ${PASTES_BEFORE})"
fi

# **모드가 안 닫혔다.** 붙여넣기는 y와 달리 모드를 건드리지 않는다. dumpCopy가
# 좌표를 찍는 것이 곧 copy 커서가 살아 있다는 뜻이다 — 모드 밖이었다면 좌표
# 없이 'copy> paste'만 찍힌다.
if ! grep -aqE 'terminal: copy> paste row=[0-9]+ col=[0-9]+' "$LOG"; then
  report_failure "the paste inside copy mode did not keep the copy cursor alive"
fi

# **판정.** 셸이 붙여넣은 글자를 되울렸는데도 뷰포트가 그대로다.
OFFSET_AFTER="$(scroll_field offset)"
if [ "$OFFSET_AFTER" -ne "$OFFSET_UP" ]; then
  report_failure "output that arrived during copy mode moved the viewport (offset ${OFFSET_UP} -> ${OFFSET_AFTER})"
fi
echo "copy mode held the viewport still while output arrived (offset stayed at ${OFFSET_UP})"

# 대조군. **이것이 없으면 "scrollToBottom이 아예 안 불린다"도 통과한다.**
# 모드를 나가고 Enter를 치면 셸이 붙여넣은 명령을 실행하고, 그 출력이 도착할
# 때는 억제가 풀려 있으므로 뷰포트가 바닥으로 돌아와야 한다.
#
# "바닥에 있다"는 offset == total - len이다(vt.zig의 scrollbar 주석).
echo "=== leaving copy mode and running the pasted command ==="
type_keys esc
sleep 1
type_keys ret
sleep 3
TOTAL_END="$(scroll_field total)"
OFFSET_END="$(scroll_field offset)"
LEN_END="$(scroll_field len)"
if [ "$OFFSET_END" -ne "$((TOTAL_END - LEN_END))" ]; then
  report_failure "the viewport did not return to the bottom after leaving copy mode (offset ${OFFSET_END}, expected $((TOTAL_END - LEN_END)))"
fi
echo "the viewport followed the output again once copy mode was closed (offset ${OFFSET_END})"

# 붙여넣은 명령이 정말로 셸까지 갔다는 것은, 그것이 **두 번째** 출력줄을
# 만드는 것으로 증명된다. Enter 하나만으로도 새 프롬프트가 생기며 뷰포트는
# 바닥으로 돌아오므로, 위 검사만으로는 "붙여넣기는 실패했는데 Enter만 먹었다"가
# 걸러지지 않는다.
PASTED_ROWS="$(screen_count '| PASTED |')"
if [ "$PASTED_ROWS" -lt 2 ]; then
  report_failure "expected two rows containing only 'PASTED' but found ${PASTED_ROWS}"
fi
echo "the paste inside copy mode reached the shell too (${PASTED_ROWS} 'PASTED' rows)"
```

### Step 4: 마지막 줄의 이름을 고친다

`copy/check.sh`의 마지막 줄을 **지울 것**:

```bash
echo "CM-M1 check PASS"
```

**넣을 것**:

```bash
echo "CM-M2 check PASS"
```

### Step 5: 체인을 한 번 돌린다 (Claude가 실행, 약 7~9분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash copy/check.sh
```

기대: `CM-M2 check PASS`.

**걸렸을 때 어디를 보는가.**

- **검사 11의 `clip> paste len=11`이 없으면** `Cmd+V`가 모드 **밖에서** 안 먹은
  것이다. Task 1 Step 2(`chord()`의 Meta 분기)를 확인한다. 로그에
  `terminal: key> 1 byte(s)`가 그 시각에 찍혔으면 `v`가 그냥 글자로 나간 것이다.
- **검사 11의 에코 수가 안 늘면** 바이트는 나갔는데 셸이 안 받은 것이다. 한
  번의 `docker run` 안에서 마지막 화면을 직접 본다.

  ```bash
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
    bash copy/check.sh > /tmp/gate.out 2>&1
    grep -a "terminal: screen>" /tmp/tmp.* | tail -n 2
  '
  ```

- **검사 13의 `copy> paste row=` 가 없으면** 모드 안의 `Cmd+V`가 안 먹었거나
  (Task 1 Step 3의 세 갈래), 붙여넣기가 모드를 닫아 버린 것이다. 로그에
  `copy> paste`가 좌표 없이 찍혔다면 후자다.
- **검사 13의 offset이 움직였으면** 억제 분기가 안 밟힌 것이다. `main.zig`의
  `if (!screen.copyActive())`를 확인한다. 반대로 **위로 안 올라갔으면**(`OFFSET_UP`
  검사) 앞선 검사들이 화면 상태를 예상과 다르게 남긴 것이므로 `scroll>` 줄들을
  훑어본다.
- **`PASTED_ROWS`가 1이면** 두 번째 붙여넣기가 셸에 안 닿았거나, 두 출력줄이
  화면에서 밀려났다. `screen>` 마지막 줄을 직접 보고 어느 쪽인지 가른다.

**`grep`에 `-a`를 반드시 붙인다.** 로그에 NUL이 한 바이트라도 있으면 `grep`이
파일을 binary로 취급한다.

### Step 6: 커밋 (Claude가 실행)

```bash
git add copy/check.sh
git commit -m "Prove the clipboard makes it back to the shell"
```

---

## Task 5: 루트 게이트를 3/3으로 돌린다

**Files:**
- Modify: `check.sh`

### Step 1: 체인 이름을 고친다

`check.sh:109`를 **지울 것**:

```bash
run_chain "CM-M1" ./copy/check.sh
```

**넣을 것**:

```bash
run_chain "CM-M2" ./copy/check.sh
```

### Step 2: 루트 게이트를 돌린다 (Claude가 백그라운드로 실행, 약 56분)

**Bash 도구의 10분 타임아웃을 넘으므로 `run_in_background`로 돌린다.**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**시간을 어떻게 읽는가.** 직전 기준선은 **54분 40초**다(2026-08-25). 이번에 CM
체인이 회차당 더 쓰는 시간은 이렇게 갈린다.

| 항목 | 회차당 |
|---|---|
| `type_keys` 여섯 개(0.3초씩) | 1.8초 |
| `sendkey k` 80번(0.05초씩) | 4.0초 |
| 명시적 `sleep`(3+3+2+2+3+1+3) | 17.0초 |
| 합계 | 약 23초 |

체인이 3회 도므로 **약 1분 10초**가 는다. 그러니 **55분 50초 ~ 56분 30초**를
기대한다.

**기계를 비우고 잰다.** 값이 기준선에서 크게 벗어나면 코드를 의심하기 전에
기계를 먼저 의심한다 — TR-M2를 끝내며 처음 잰 값이 6시간 12분이었고 원인은
Chrome이 영상을 재생하고 있던 것이었다.

**CM-M1에서 3분 20초가 늘었는데 그중 1분만 설명됐다는 것을 기억해 둔다.** 이번
값이 위 예상보다 2분 이상 크면, 그때는 배경 부하를 `pmset -g log`로 확인해서
**갈랐다고 말할 수 있는 값을 만든다.** 확인하지 않았으면 확인하지 않았다고 적는다.

### Step 3: 커밋 (Claude가 실행)

```bash
git add check.sh
git commit -m "Rename the copy chain for CM-M2"
```

---

## Task 6: 문서를 닫는다

**이 Task가 CM-M0·M1 때보다 한 겹 많다.** CM-M2가 끝나면 Copy Mode 서브프로젝트
자체가 끝나므로, "다음 milestone"이 아니라 "다음 서브프로젝트"를 가리켜야 한다.

**Files:**
- Modify: `docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md`
- Modify: `docs/decisions/project_copy_mode.md`
- Modify: `CLAUDE.md`
- Modify: `HANDOFF.md`

### Step 1: design doc에 CM-M2의 결과를 붙인다

머리의 `**Status:**` 줄을 "설계 확정. **CM-M2 완료(2026-08-26)로 서브프로젝트가
끝났다**"로 고치고, "milestone 구성" 절의 CM-M1 인용 블록 **뒤에** CM-M2 블록을
붙인다. 적을 것은 다섯이다.

1. **`Cmd+V`가 두 곳에 들어갔다.** `chord()`의 Meta 분기(모드 밖)와 copy 표
   (모드 안)이고, 후자는 **줄을 더한 것이 아니라 이미 차 있던 `KEY_V`를 세
   갈래로 가른 것**이다. design 결정 4의 표는 이 충돌을 안 적었다.
2. **붙여넣기는 모드를 닫지 않기로 정했다**(design이 안 정한 자리). 그 덕에
   게이트가 `scrollToBottom` 억제 분기를 처음으로 밟았다. 대가는 "모드 안에서
   뷰포트를 올려 둔 채 붙여넣으면 눈에 아무 일도 안 보인다"이고, 감췄다가
   나중에 발견되게 두지 않고 여기 적는다.

   **그리고 이 밟기는 대역이다.** 억제 분기가 존재하는 진짜 이유는 붙여넣기
   에코가 아니라 **백그라운드 출력**이다(`main.zig`의 그 자리 주석: "백그라운드
   출력이 한 줄만 도착해도 사람이 올라가서 보고 있던 자리가 화면 밖으로
   튕기기 때문"). 게이트가 증명하는 것은 **"그 분기가 실행된다"**이지 **"그
   기능이 막으려던 사고가 막힌다"**가 아니다. 진짜 상황으로 보려면 copy mode에
   들어가기 전에 fish 백그라운드 잡을 띄워 두어야 하는데, 타이핑 40여 개와
   회차당 15초를 더 쓰는 일이라 이번에는 하지 않기로 했다(2026-08-26 결정).
   **못 보는 것을 못 본다고 적어 두는 자리가 여기다.**
3. **결정 8을 지켰다.** 붙여넣기 로그가 새 접두사를 만들지 않고
   `clip> paste len=…`으로 들어갔다.
4. **위험 6이 이제 반쯤 보인다.** copy mode 중에 PTY 출력이 도착하는 상황을
   게이트가 실제로 만들었다. 다만 **가지치기를 일으킬 만큼(1000줄)은 여전히 못
   만든다** — 붙여넣기 한 번이 만드는 출력은 한 줄이다.
5. **게이트 시간의 실측값.**

### Step 2: `project_copy_mode` 기억을 고친다

**서브프로젝트가 끝났다**는 것과, 이 기억을 나중에 읽을 사람이 실제로 필요로 할
사실 셋을 적는다.

- `Cmd+V`는 표 **두 곳**에 있고 한쪽만 고치면 나머지 모드에서 조용히 안 먹는다.
- 붙여넣기는 bracketed paste를 안 쓴다(결정 9). 여러 줄을 붙이면 개행이 곧
  실행이다. **다시 논의하려면 셸이 그 모드를 받는지부터 실측한다.**
- 비워 둔 자리: 단어 이동(`w`/`b`)·검색(`/`)·마우스·OSC 52·normal 모드의
  `Cmd+C`·"붙여넣기가 모드를 닫아야 하는가".

### Step 3: `CLAUDE.md`의 "참고" 절을 고친다

지금 "진행 중인 서브프로젝트: Display Foundation"이라고 적혀 있다. **완료된
서브프로젝트 목록에 Copy Mode를 넣고, 진행 중인 것이 없다는 사실을 적는다.**
다음 후보는 `HANDOFF.md`의 이월 숙제가 든다.

### Step 4: `HANDOFF.md`를 다시 쓴다

- 머리: **Copy Mode가 끝났다. 다음 일은 다음 서브프로젝트를 고르는 것이다.**
- 게이트 현황: 여덟 체인 `CM-M2`, 새 기준선 시간, 다음 monitor 포트는 45462.
- 로그 문구 목록에 `terminal: clip> paste`를 더한다.
- "CM-M2가 실측으로 알아낸 것"으로 위 Step 1의 다섯을 옮긴다.
- **이월 숙제를 그대로 옮기고 1순위를 명시한다.** `init`을 `ReleaseSafe`로
  (initrd 73.0MB → gzip 16.76MB, 커널 부팅 1.12초 중 0.573초가 압축 해제)와
  체인의 `sleep 0.3` 줄이기(게이트 56분의 상당 부분)가 서로 맞물린다 — **둘 다
  게이트 시간을 줄이는 일이므로 한 서브프로젝트로 묶는 안을 적어 둔다.**
- "시도했으나 안 되는 접근"은 그대로 옮기고, 이번에 하나를 더한다:
  **`key>` 줄로 붙여넣기를 감지하기** — 붙여넣기는 `pty.write`를 직접 부르므로
  그 줄을 만들지 않는다.

### Step 5: 커밋 (Claude가 실행)

```bash
git add HANDOFF.md CLAUDE.md docs/decisions/project_copy_mode.md \
  docs/superpowers/specs/2026-08-24-tars-copy-mode-design.md
git commit -m "Close out Copy Mode"
```

---

## 게이트가 못 보는 것 (적어 두고 넘어간다)

`project_gate_chain_composition`이 "못 보는 것을 적어 두라"고 한 자리다.

- **빈 클립보드로 누른 `Cmd+V`**(`clip> paste empty` 가지). 게이트는 언제나 `y`
  뒤에 붙여넣으므로 이 가지를 안 밟는다. `vt_test`의 대조군이 `clipboard()`가
  null인 화면이 있다는 것까지는 보지만, `main.zig`의 분기 자체는 아무도 안
  밟는다. **한 줄짜리 분기라 감수한다.**
- **여러 줄 붙여넣기.** 결정 9가 감수하기로 한 자리다. 클립보드에 개행이 든
  경우를 아무도 안 만든다 — 게이트의 `V`는 한 줄만 잡는다.
- **`Cmd+V`가 `swap_alt_meta`(PC 키보드)를 거치는 경로.** 다른 Cmd 조합과 같은
  보정을 지나가지만, IP-M2 이후 그 보정은 `handleKey` 맨 앞 한 곳뿐이라 키마다
  따로 볼 것이 없다.
- **억제 분기가 막으려던 진짜 상황 — 백그라운드 출력.** 검사 13이 밟는 것은
  붙여넣기 에코이고, 그것은 대역이다. 분기가 실행된다는 것은 증명되지만,
  "사람이 올려다보는 중에 백그라운드 잡이 한 줄을 뱉어도 자리가 안 튕긴다"는
  증명되지 않는다. 그것을 보려면 copy mode에 들어가기 전에 fish 백그라운드 잡을
  띄워 두어야 하고, 타이핑 40여 개와 회차당 15초가 든다. **다음에 이 자리를
  만질 사람이 값을 다시 저울질할 수 있게 비용까지 적어 둔다.**
- **모드 안에서 붙여넣은 뒤 그대로 `y`를 누르는 경우.** 선택이 살아 있는 채로
  에코가 도착하면 앵커 감시가 돌지만, 한 줄 출력으로는 가지치기가 안 나므로
  아무 일도 안 일어난다. **`vt_test`의 검사 9 (1)번 대조군이 같은 성질을 본다.**

## 완료 조건

- [ ] `zig build test`가 `input_test: copy mode OK`와 `vt_test: copy selection OK`를 찍는다
- [ ] `vt_test`가 `클립보드를 되읽는다 OK ('second line')`을 찍는다
- [ ] `zig build`가 통과한다 (`Copy`에 variant를 더했으므로 함께 돌린다)
- [ ] `copy/check.sh` 단독 실행이 `CM-M2 check PASS`
- [ ] 루트 게이트 여덟 체인이 3/3
- [ ] 게이트 시간을 실측해 기록했고, **기준선과의 차이를 설명했거나 설명하지
      못했다고 적었다**
- [ ] design doc·`project_copy_mode`·`CLAUDE.md`·`HANDOFF.md`가 최신이다
