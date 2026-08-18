# TARS Input Policy IP-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** IP-M0가 넓혀 놓은 바닥(`[]const u8` 반환) 위에 **이스케이프
시퀀스**를 올린다. 방향키·Home/End·Delete·PageUp/PageDown이 셸의 줄
편집기까지 도달하고, 그 시퀀스의 모양을 **추측하지 않고 VT에게 물어본다**
(DECCKM). 그리고 지금 거짓말을 하고 있는 `TERM`을 `xterm`으로 고치고 그
terminfo를 게스트에 넣는다. 이 milestone이 끝나면 게스트 셸에서 **줄 가운데를
고칠 수 있다.**

**Design doc:** `docs/superpowers/specs/2026-08-15-tars-input-policy-design.md`
(결정 5·6·7이 이 milestone의 몫)

**배경 자료:** `docs/study/2026-08-15-keyboard-escape-sequence-crash-course.md`

**Tech Stack:** Zig 0.16.0, libghostty-vt(`modes.get`), bash, QEMU monitor
`sendkey`, Docker(`tars-devcontainer`, arm64), Debian `ncurses-base`

---

## 왜 이 순서인가

```
Task 1   Context 구조체 도착 (시그니처만 넓힘)      ← 자리 만들기
  ↓      동작 불변. main은 아직 .{} 상수를 넘긴다
Task 2   특수키 → 이스케이프 시퀀스                 ← 이 milestone의 본체
  ↓      호스트 테스트가 DECCKM 두 형태를 다 본다
Task 3   main.zig가 DECCKM을 실제로 읽어 채운다     ← 값이 진짜가 된다
  ↓
Task 4   TERM=xterm + terminfo (이미지 재빌드)      ← 상대에게 진실을 말한다
  ↓      다른 두 체인에 영향이 가므로 여기서 확인
Task 5   게이트 확장 — 방향키 + TERM                ← 증명
  ↓      부팅은 여전히 한 번. sendkey 열 개쯤 추가
Task 6   루트 게이트 4체인 3/3
```

Task 1과 2를 나누는 이유는 IP-M0의 Task 2/3 분리와 같다. **시그니처를 넓히는
변경과 동작을 바꾸는 변경을 한 커밋에 섞으면, 실패했을 때 어느 쪽이
원인인지 알 수 없다.** Task 1이 끝난 시점에서 `zig build test`는 M0와 똑같이
통과해야 한다 — 그게 "아직 아무것도 안 바뀌었다"의 증거다.

Task 3이 Task 2 뒤인 이유는 관측 가능성이다. `cursor_keys`를 채워도 특수키가
없으면 그 값을 읽는 코드가 없다. IP-M0에서 Alt/Meta 넷을 미룬 것과 같은
기준이다.

Task 4가 게이트보다 앞인 이유는 **`TERM` 변경이 이 milestone에서 가장 넓게
번지는 변경**이기 때문이다. `terminal`은 세 체인(TF/CP/IP)이 전부 띄우는
프로세스이고, 셸이 보는 `TERM`이 바뀌면 셸이 그리는 프롬프트가 바뀔 수 있다.
게이트를 고치기 전에 기존 게이트가 살아 있는지부터 본다.

## 미리 밝혀두는 범위 조정 둘

**1. F1~F12·키패드·Insert는 넣지 않는다.** design doc 비목표 그대로다. 표에
넣는 비용 자체는 싸지만 게이트가 볼 수 없는 표를 늘리는 것은
`project_gate_chain_composition`이 경고한 부채다. 이번에 넣는 특수키는 아홉
개다 — ↑↓←→, Home, End, Delete, PageUp, PageDown.

**2. modifier + 특수키 조합(`Ctrl+←` 등)은 이번이 아니다.** 터미널 관례는
`ESC [ 1 ; 5 D` 같은 형태인데, 이건 design doc 결정 2의 **2번 단계(조합
dispatch)** 에 속하고 그 자리는 IP-M2가 연다. 이번 코드에서 `Ctrl+←`는 Ctrl을
무시하고 그냥 `←`를 보낸다. **의도된 동작이며, `input_test`에 그렇게
적어둔다** — 나중에 M2가 이 줄을 고치면서 "여기가 바뀌는 자리"임을 알게 된다.

`State.seq`가 8바이트인데 이번에 가장 긴 시퀀스는 4바이트(`ESC [ 3 ~`)다.
6바이트를 쓰는 것은 위 1번 형태이므로 M2다.

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

**이번 편집은 전부 국소 블록 교체다.** `input.zig`가 209줄이지만 고치는 곳은
30줄 안팎의 블록 넷이므로 인라인으로 제시한다(IP-M0에서 이 방식이 잘 통했다).
`/tmp` + `cp` + `diff` 경로는 이번에 쓰지 않는다.

---

## Task 1: `Context` 구조체가 도착한다

design doc 결정 6의 자리를 만든다. **동작은 하나도 바뀌지 않는다** — 아무도
`ctx`를 읽지 않는다. IP-M0가 "M0에는 채울 내용이 없어서 미뤘다"고 적어둔 것을
지금 꺼낸다.

`input.zig`가 `vt.zig`를 import하지 않는 이유를 다시 짚어둔다. 지금 `main.zig`
하나만 다섯 모듈(`drm`/`font`/`input`/`pty`/`vt`)을 알고 그 다섯은 서로
모른다. `input → vt` 화살표를 그리는 순간 이 성질이 깨지고, 다음에 `vt`가
무언가 필요해지면 순환이 생긴다. 그리고 `input_test`는 `ghostty-vt`를 링크하지
않으므로(`build.zig:73-83`) import가 생기면 **호스트 테스트가 아예 빌드되지
않는다.** 저울이 먼저 부서진다.

**Files:**
- Modify: `terminal/src/input.zig` (`Context` 추가, `handleKey`/`readKeys` 시그니처)
- Modify: `terminal/src/input_test.zig` (`expect` 헬퍼)
- Modify: `terminal/src/main.zig:146`

- [ ] **Step 1: 테스트의 헬퍼를 먼저 바꾼다**

`terminal/src/input_test.zig:6-14`의 `expect` 함수를 이것으로 바꾼다.

```zig
/// IP-M0부터 handleKey는 바이트 **하나**가 아니라 바이트 **열**을 돌려준다.
/// "보낼 것 없음"은 null이 아니라 빈 슬라이스다.
///
/// IP-M1부터 handleKey는 `Context`도 받는다. 대부분의 검사는 기본값
/// (`cursor_keys=false`)으로 충분하므로 여기서 채워 넣고, DECCKM 두 형태를
/// 비교해야 하는 검사만 아래 expectCtx를 직접 부른다.
fn expect(state: *input.State, code: u16, value: i32, want: []const u8) !void {
    return expectCtx(state, .{}, code, value, want);
}

fn expectCtx(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    want: []const u8,
) !void {
    const got = state.handleKey(code, value, ctx);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print(
        "FAIL: code={d} value={d} ckm={} -> got={any}, want={any}\n",
        .{ code, value, ctx.cursor_keys, got, want },
    );
    return error.UnexpectedBytes;
}
```

M0가 쓴 검사 스물몇 줄은 **한 글자도 안 고친다.** `expect`의 겉모습이
그대로이기 때문이다 — 그게 이 헬퍼를 둘로 나눈 이유다.

- [ ] **Step 2: 컴파일이 깨지는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: **컴파일 에러.** `input.Context`가 아직 없고, `handleKey`는 인자를 셋만
받는다. 대략 이런 메시지 둘이 나온다.

```
error: struct 'input' has no member named 'Context'
error: expected 3 argument(s), found 4
```

- [ ] **Step 3: `input.zig`에 `Context`를 추가**

`terminal/src/input.zig:80-81`의 `none` 정의 **바로 앞에** 다음을 넣는다.

```zig
/// 키 하나를 어떻게 번역할지 바꾸는, **바깥에서 들어오는** 상태.
///
/// design doc 결정 6: `input.zig`는 `vt.zig`를 import하지 않는다. DECCKM
/// 상태가 VT 안에 있다고 해서 여기서 직접 부르게 하면 (1) 지금 단방향인
/// 모듈 의존(main만 다섯을 안다)이 깨지고, (2) `ghostty-vt`를 링크하지 않는
/// `input_test`가 빌드조차 되지 않는다. 그래서 `main.zig`가 매 키마다
/// **값으로** 채워 넘긴다 — packed struct의 비트 읽기 한 번이라 값이 없다.
pub const Context = struct {
    /// DECCKM(DEC Cursor Key Mode, private mode 1). 켜져 있으면 방향키와
    /// Home/End가 `ESC [` 대신 `ESC O`로 시작한다. 이 모드를 켜는 것은
    /// 셸이 보내는 `ESC [ ? 1 h`이고, 그 시퀀스는 이미 우리가 파싱해서
    /// libghostty-vt에 먹이고 있다. main.zig가
    /// `screen.term.modes.get(.cursor_keys)`로 되읽어 채운다.
    cursor_keys: bool = false,

    /// PC 키보드 보정(design doc 결정 9). **IP-M2에서 처음 읽힌다** —
    /// 지금은 자리만 있다. 여기 적어두는 이유는 Context가 생기는 이유가
    /// DECCKM 하나가 아니라는 것을 남기기 위해서다.
    swap_alt_meta: bool = false,
};
```

- [ ] **Step 4: `handleKey`와 `readKeys`가 `ctx`를 받게 한다**

세 곳이다. 먼저 `input.zig:131-134`의 `handleKey` 선언.

```zig
    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    /// PTY로 보낼 바이트열을 반환한다. 보낼 것이 없으면 빈 슬라이스다.
    pub fn handleKey(self: *State, code: u16, value: i32, ctx: Context) []const u8 {
```

이 Task에서는 본문에서 `ctx`를 읽지 않으므로, 함수 첫 줄에 다음을 넣어
"안 쓰는 인자" 에러를 막는다. **Task 2에서 이 줄을 지운다.**

```zig
        // Task 2가 이 줄을 지우고 진짜로 읽는다.
        _ = ctx;
```

다음으로 `input.zig:178`의 `readKeys` 선언과 `:196`의 호출.

```zig
pub fn readKeys(self: *State, fd: c_int, out: []u8, ctx: Context) []const u8 {
```

```zig
        for (self.handleKey(ev.code, ev.value, ctx)) |byte| {
```

- [ ] **Step 5: `main.zig`가 아직은 기본값을 넘긴다**

`terminal/src/main.zig:146`의

```zig
            const bytes = input.readKeys(&key_state, keyboard_fd, &key_buf);
```

을 이것으로.

```zig
            // Task 3에서 여기에 실제 DECCKM 값이 들어온다. 지금은 기본값
            // (cursor_keys=false)이라 M0와 동작이 완전히 같다.
            const bytes = input.readKeys(&key_state, keyboard_fd, &key_buf, .{});
```

- [ ] **Step 6: 통과하는 것을 확인 (아무것도 안 바뀌었다는 증거)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: M0와 **글자 하나 다르지 않은** 출력.

```
input_event size = 24 (expected 24)
PASS
```

x86_64 본체도 여전히 빌드되는지 함께 본다(`main.zig`를 고쳤으므로).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "./prepare.sh"
```

기대: 에러 없이 끝난다.

- [ ] **Step 7: Commit**

Claude가 수행한다. 커밋 메시지: `Pass a translation context into every key event`

---

## Task 2: 특수키가 이스케이프 시퀀스가 된다

이 milestone의 본체다. 여기서 처음으로 `State.seq`가 1바이트보다 길게 쓰인다 —
IP-M0가 8바이트로 잡아두고 한 번도 안 썼던 그 배열이다.

**표를 어떻게 둘 것인가.** 기존 `keymap`은 `[2]u8`(Shift 안 누름 / 누름)
배열이라 여러 바이트를 담을 수 없다. 그리고 방향키는 코드 102~111에 있어서
지금 표(0~57)를 그 자리까지 늘리면 **58~101 마흔네 칸이 전부 `.{ 0, 0 }`인
표**가 된다. 그래서 특수키는 별도 `switch`로 뺀다. 조회가 `keymap` 배열 밖에서
일어나므로 `code >= keymap.len` 검사보다 **먼저** 물어봐야 한다.

**두 가지 모양뿐이다.**

| 모양 | 예 | DECCKM |
|---|---|---|
| 커서 계열 `ESC [ X` / `ESC O X` | ↑↓→← Home End | **영향 받음** |
| 틸드 계열 `ESC [ N ~` | Delete PageUp PageDown | 영향 없음 |

그래서 union 하나로 표현하고, 마지막 글자(또는 숫자)만 표에 적는다.

**Files:**
- Modify: `terminal/src/input_test.zig` (검사 추가)
- Modify: `terminal/src/input.zig` (`SpecialKey`, `escape`, `handleKey`)

- [ ] **Step 1: 실패하는 검사를 먼저 추가**

`terminal/src/input_test.zig`의 마지막 검사(`try expect(&state, 46, 1, "c");`,
102줄) **뒤에**, `std.debug.print("PASS\n", .{});` **앞에** 다음을 넣는다.

```zig
    // ── 특수키 → 이스케이프 시퀀스 (IP-M1) ──────────────────────────────
    //
    // 여기서 처음으로 키 하나가 바이트 여러 개가 된다. IP-M0가 반환 타입을
    // []const u8로 바꾼 이유가 이것이다 — 표를 아무리 늘려도 ?u8로는
    // `ESC [ D` 세 바이트를 표현할 수 없었다.

    // DECCKM 꺼짐(기본): `ESC [ X`
    try expect(&state, 103, 1, "\x1b[A"); // KEY_UP
    try expect(&state, 108, 1, "\x1b[B"); // KEY_DOWN
    try expect(&state, 106, 1, "\x1b[C"); // KEY_RIGHT
    try expect(&state, 105, 1, "\x1b[D"); // KEY_LEFT
    try expect(&state, 102, 1, "\x1b[H"); // KEY_HOME
    try expect(&state, 107, 1, "\x1b[F"); // KEY_END

    // 틸드 계열은 DECCKM과 무관하게 언제나 같은 모양이다.
    try expect(&state, 111, 1, "\x1b[3~"); // KEY_DELETE
    try expect(&state, 104, 1, "\x1b[5~"); // KEY_PAGEUP
    try expect(&state, 109, 1, "\x1b[6~"); // KEY_PAGEDOWN

    // 뗄 때는 여전히 아무것도 안 보낸다.
    try expect(&state, 105, 0, "");
    // 자동 반복은 보낸다 — 방향키를 누르고 있으면 계속 움직여야 한다.
    try expect(&state, 105, 2, "\x1b[D");

    // ── DECCKM 켜짐: 커서 계열만 `ESC O X`로 바뀐다 ─────────────────────
    //
    // 이 모드가 실제로 켜지는지는 셸에 달려 있고(smkx), --no-config로 뜬
    // 셸이 안 보내면 게이트는 이 경로를 한 번도 밟지 않는다(design doc
    // 위험 4). 그래서 **여기서** 두 형태를 다 본다.
    const ckm = input.Context{ .cursor_keys = true };
    try expectCtx(&state, ckm, 103, 1, "\x1bOA"); // KEY_UP
    try expectCtx(&state, ckm, 108, 1, "\x1bOB"); // KEY_DOWN
    try expectCtx(&state, ckm, 106, 1, "\x1bOC"); // KEY_RIGHT
    try expectCtx(&state, ckm, 105, 1, "\x1bOD"); // KEY_LEFT
    try expectCtx(&state, ckm, 102, 1, "\x1bOH"); // KEY_HOME
    try expectCtx(&state, ckm, 107, 1, "\x1bOF"); // KEY_END

    // 틸드 계열은 DECCKM이 켜져도 그대로다. 이 세 줄이 위 여섯 줄만큼
    // 중요하다 — "모드가 켜지면 전부 O로 바꾼다"는 흔한 오해를 막는다.
    try expectCtx(&state, ckm, 111, 1, "\x1b[3~");
    try expectCtx(&state, ckm, 104, 1, "\x1b[5~");
    try expectCtx(&state, ckm, 109, 1, "\x1b[6~");

    // ── 아직 안 하는 것을 적어둔다 ──────────────────────────────────────
    //
    // modifier + 특수키(`Ctrl+←` = `ESC [ 1 ; 5 D`)는 design doc 결정 2의
    // 2번 단계(조합 dispatch)이고 그 자리는 IP-M2가 연다. 지금은 Ctrl을
    // 무시하고 맨 방향키를 보낸다 — 의도된 동작이다. M2가 이 줄을 고칠 때
    // "여기가 바뀌는 자리"임을 알 수 있게 남긴다.
    try expect(&state, 29, 1, ""); // LEFTCTRL press
    try expect(&state, 105, 1, "\x1b[D"); // Ctrl+← → 아직은 그냥 ←
    try expect(&state, 29, 0, ""); // LEFTCTRL release

    // Shift도 마찬가지다. keymap의 [2]u8는 특수키에 아예 닿지 않는다.
    try expect(&state, 42, 1, ""); // LEFTSHIFT press
    try expect(&state, 105, 1, "\x1b[D"); // Shift+← → 아직은 그냥 ←
    try expect(&state, 42, 0, ""); // LEFTSHIFT release

    // 특수키 사이의 빈 코드(F1=59 등)는 여전히 조용히 무시된다. 표에 넣는
    // 비용은 싸지만 게이트가 볼 수 없는 표를 늘리지 않는다(design doc 비목표).
    try expect(&state, 59, 1, ""); // KEY_F1
    try expect(&state, 110, 1, ""); // KEY_INSERT
```

- [ ] **Step 2: 실패하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: 컴파일은 되고 **실행이 실패**한다. 첫 실패는 `code=103 value=1`이며
`got={ }`, `want={ 27, 91, 65 }`다. 지금 103은 `code >= keymap.len`(58)에 걸려
빈 슬라이스로 떨어진다 — 그것이 지금 방향키가 아무 일도 안 하는 이유의 전부다.

`27, 91, 65`가 `ESC [ A`라는 것을 눈으로 확인하고 넘어간다. 0x1b=27,
`[`=91, `A`=65.

- [ ] **Step 3: `input.zig`에 특수키 표를 추가**

`terminal/src/input.zig`의 `Context` 정의와 `none` 사이(= keymap 배열 바로
뒤)에 다음을 넣는다.

```zig
/// 특수키가 만드는 이스케이프 시퀀스는 모양이 **둘뿐**이다.
///
/// 이 셋을 keymap 배열에 넣지 않는 이유는 두 가지다. (1) keymap의 칸은
/// `[2]u8`(Shift 안 누름 / 누름) 문자 한 쌍이라 여러 바이트를 담을 수 없다.
/// (2) 방향키는 evdev 코드 102~111에 있어서 표를 거기까지 늘리면 58~101
/// 마흔네 칸이 전부 `.{ 0, 0 }`인 표가 된다.
const SpecialKey = union(enum) {
    /// `ESC [ X`. DECCKM이 켜져 있으면 `ESC O X`가 된다(design doc 결정 5).
    cursor: u8,
    /// `ESC [ N ~`. **DECCKM의 영향을 받지 않는다** — 흔한 오해라 여기 적어둔다.
    tilde: u8,
};

/// evdev 코드 → 특수키. 대상이 아니면 null.
///
/// F1~F12(59~88)·키패드·Insert(110)는 일부러 없다. TUI 앱이 하나도 없어서
/// 누를 이유가 없고, 게이트가 볼 수 없는 표를 늘리는 것은
/// project_gate_chain_composition이 경고한 부채다(design doc 비목표).
fn specialKey(code: u16) ?SpecialKey {
    return switch (code) {
        c.KEY_UP => .{ .cursor = 'A' },
        c.KEY_DOWN => .{ .cursor = 'B' },
        c.KEY_RIGHT => .{ .cursor = 'C' },
        c.KEY_LEFT => .{ .cursor = 'D' },
        c.KEY_HOME => .{ .cursor = 'H' },
        c.KEY_END => .{ .cursor = 'F' },
        c.KEY_DELETE => .{ .tilde = '3' },
        c.KEY_PAGEUP => .{ .tilde = '5' },
        c.KEY_PAGEDOWN => .{ .tilde = '6' },
        else => null,
    };
}
```

- [ ] **Step 4: `State`에 `escape`를 추가**

`input.zig`의 `one` 함수(`:125-129`) **바로 뒤에** 다음을 넣는다.

```zig
    /// 특수키의 바이트열을 seq에 담아 슬라이스로 돌려준다.
    /// `one`과 같은 저장소를 쓴다 — 호출자가 즉시 복사하므로 안전하다.
    fn escape(self: *State, key: SpecialKey, ctx: Context) []const u8 {
        self.seq[0] = 0x1b; // ESC
        switch (key) {
            .cursor => |final| {
                // 여기가 결정 5다. `ESC [`인지 `ESC O`인지를 **추측하지
                // 않는다** — 셸이 보낸 `ESC [ ? 1 h`를 libghostty-vt가 이미
                // 받아뒀고, main.zig가 그 값을 ctx에 담아 넘겨준다.
                self.seq[1] = if (ctx.cursor_keys) 'O' else '[';
                self.seq[2] = final;
                return self.seq[0..3];
            },
            .tilde => |num| {
                self.seq[1] = '[';
                self.seq[2] = num;
                self.seq[3] = '~';
                return self.seq[0..4];
            },
        }
    }
```

- [ ] **Step 5: `handleKey`가 특수키를 먼저 보게 한다**

`input.zig`의 `handleKey`에서 Task 1이 넣어둔 `_ = ctx;` 줄을 **지우고**,
`if (value == 0) return none;` 과 `if (code >= keymap.len) return none;`
**사이에** 다음을 넣는다.

```zig
        // 특수키를 keymap 조회보다 **먼저** 본다. 방향키(102~111)는 어차피
        // keymap 배열 밖이라 순서를 바꿔도 결과는 같지만, design doc 결정 2가
        // 정한 "가로챌 것을 먼저 가로채고 남은 것만 평소대로"를 코드 순서로
        // 남겨둔다 — IP-M2의 조합 dispatch가 이 위에 얹힌다.
        //
        // modifier와의 조합(`Ctrl+←` = `ESC [ 1 ; 5 D`)은 그 M2의 몫이다.
        // 지금은 Ctrl/Shift를 무시하고 맨 시퀀스를 보낸다.
        if (specialKey(code)) |key| return self.escape(key, ctx);

```

바뀐 뒤 `handleKey`의 아랫부분은 이렇게 된다.

```zig
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return none;

        if (specialKey(code)) |key| return self.escape(key, ctx);

        if (code >= keymap.len) return none;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        if (ch == 0) return none;
        ...
```

- [ ] **Step 6: 통과하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대:

```
input_event size = 24 (expected 24)
PASS
```

**여기서 `error: no field named 'KEY_PAGEUP'` 류가 나오면 알려 달라.**
`@cImport(linux/input.h)`가 `input-event-codes.h`를 통해 이 상수들을
가져오는지는 컨테이너의 `linux-libc-dev` 버전에 달려 있다. 실패하면 숫자
리터럴(103/108/106/105/102/107/111/104/109)로 대체하고 주석에 이름을 적는
것이 우회다 — 다만 이름 쪽이 읽기 좋으므로 먼저 이렇게 시도한다.

- [ ] **Step 7: Commit**

Claude가 수행한다. 커밋 메시지: `Turn the arrow and edit keys into escape sequences`

---

## Task 3: `main.zig`가 DECCKM을 실제로 읽는다

Task 2까지의 `cursor_keys`는 언제나 `false`다. 이제 진짜 값을 넣는다.

`vt.zig`의 `Screen`이 `term` 필드를 공개하고 있고(`vt.zig:24`),
libghostty-vt의 `Terminal`에 `modes` 필드가 있으며
(`ghostty-src/src/terminal/Terminal.zig:83`), `ModeState.get`이
`pub fn get(self: *const ModeState, mode: Mode) bool`이다
(`modes.zig:47`). `cursor_keys`는 `modes.zig:288`에 private mode 1로 등록돼
있다. **필요한 것이 전부 이미 있다.**

**Files:**
- Modify: `terminal/src/main.zig:145-151`

- [ ] **Step 1: 키를 읽기 직전에 모드를 되읽는다**

`terminal/src/main.zig:145-151`의 블록을 이것으로 바꾼다.

```zig
        if (fds[0].revents & c.POLLIN != 0) {
            // DECCKM은 셸이 언제든 켜고 끌 수 있으므로(rl_prep_terminal /
            // smkx는 프롬프트를 그릴 때마다 오간다) 캐시하지 않고 **키를
            // 읽는 순간의 값**을 쓴다. packed struct의 비트 읽기 한 번이라
            // 비용이 없다 — design doc 결정 6이 "값으로 넘긴다"를 고르면서
            // 감수하기로 한 대가가 이것이다.
            const ctx = input.Context{
                .cursor_keys = screen.term.modes.get(.cursor_keys),
            };
            const bytes = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
            if (bytes.len > 0) {
                // 앞부분("terminal: key> ")은 input/check.sh가 grep하는
                // 마커라 **그대로 둔다**. 뒤에 decckm을 덧붙이는 이유는
                // design doc 위험 4다 — 게이트가 `ESC O` 경로를 밟았는지
                // 아니면 `ESC [`만 봤는지를 로그로 알 수 있어야 한다.
                std.debug.print("terminal: key> {d} byte(s) decckm={}\n", .{
                    bytes.len, ctx.cursor_keys,
                });
                pty.write(session.master_fd, bytes);
            }
        }
```

- [ ] **Step 2: 빌드되는지 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "./prepare.sh && zig build test"
```

기대: 빌드 성공 + `PASS`.

실패한다면 볼 곳은 `screen.term`이다. `screen`은 `*Screen`이므로
`screen.term.modes`가 바로 닿는다. `error: no field named 'modes'`가 나오면
vendor된 ghostty 버전이 다르다는 뜻이니 알려 달라 —
`terminal/ghostty-src/src/terminal/Terminal.zig`에서 `modes:`를 다시 찾는다.

- [ ] **Step 3: Commit**

Claude가 수행한다. 커밋 메시지: `Ask the VT which cursor key mode is active`

---

## Task 4: `TERM`이 진실을 말하게 한다

지금 PTY 셸이 보는 `TERM`은 `linux`다. 커널의 `envp_init`이 준 값이 PID 1을
거쳐 그대로 내려온 것이고(`docs/decisions/project_guest_environment.md`),
**그런데 그 셸이 말을 거는 상대는 리눅스 콘솔이 아니라 libghostty-vt**다.
xterm 계열이고, 특수키 시퀀스가 실제로 다르다.

이 Task는 이 milestone에서 **가장 넓게 번지는 변경**이다. `terminal`은 세
체인이 전부 띄우는 프로세스이므로, 셸이 능력을 더 갖게 되면 프롬프트가
그려지는 방식이 바뀔 수 있다. 그래서 게이트를 고치기 **전에** 기존 게이트가
살아 있는지부터 본다.

**Files:**
- Modify: `devcontainer/Dockerfile:53-66`
- Modify: `terminal/src/main.zig` (extern 선언 + `setenv`)
- Modify: `kernel/make_initrd.sh:134` 뒤

- [ ] **Step 1: `ncurses-base`를 sysroot에 굽는다**

`devcontainer/Dockerfile:58`의 `zsh-common \` 뒤에 한 줄을 넣는다.

```dockerfile
        zsh-common \
        ncurses-base \
```

그리고 `:47`의 주석 문단 뒤에 다음을 덧붙인다.

```dockerfile
# IP-M1이 ncurses-base를 더한다. terminal이 PTY 셸의 TERM을 xterm으로
# 바꾸므로(design doc 결정 7) 그 terminfo가 게스트에 있어야 진실이 된다 —
# /usr/share/terminfo/x/xterm이 여기 들어 있다. fish-common/zsh-common과
# 같이 architecture: all이라 :amd64를 붙이지 않는다. design doc 위험 3이
# "arch: all 패키지에 :amd64를 붙이면 apt 버전에 따라 다르게 처리될 수
# 있다"고 적었는데, 이 Dockerfile은 이미 arch: all 둘을 :amd64 없이 받고
# 있으므로 그 선례를 따르면 된다.
```

- [ ] **Step 2: 이미지를 다시 굽고 terminfo가 들어왔는지 확인**

```bash
docker build -t tars-devcontainer -f devcontainer/Dockerfile . 2>&1 | tail -20
```

이어서:

```bash
docker run --rm tars-devcontainer bash -c \
  "ls -l /usr/local/amd64-sysroot/usr/share/terminfo/x/ | head -20"
```

기대: `xterm`이 목록에 있다(보통 `xterm`, `xterm-256color`, `xterm-color`,
`xterm-mono`, `xterm-r6` 등이 함께 나온다).

**`xterm`이 없으면 멈추고 알린다.** 그 경우 두 갈래다 — Debian trixie의
`ncurses-base`가 xterm을 `ncurses-term`으로 옮겼거나, `dpkg -x`가
`/usr/share/terminfo`를 다른 자리에 풀었거나. 아래로 확인한다.

```bash
docker run --rm tars-devcontainer bash -c \
  "find /usr/local/amd64-sysroot -name 'xterm' -path '*terminfo*'"
```

- [ ] **Step 3: `terminal`이 `forkpty` 직전에 `TERM`을 덮어쓴다**

`terminal/src/main.zig:11`(cImport 블록 닫는 줄) **뒤에** extern 선언을
추가한다.

```zig
/// libc의 setenv를 직접 선언한다. 이 파일의 @cImport는 poll.h 하나뿐이고,
/// setenv 하나 때문에 stdlib.h를 통째로 끌어오면 이름 충돌 가능성만 는다.
/// `input.zig`가 open/read를, `pty.zig`가 execv를 이렇게 선언한 것과 같다.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
```

그리고 `main.zig:116`의 `const argv = ...` **바로 앞에** 다음을 넣는다.

```zig
    // TERM은 지금까지 거짓말을 하고 있었다. 커널의 envp_init이 준
    // `TERM=linux`가 PID 1을 거쳐 여기까지 상속되는데(project_guest_environment),
    // 이 셸이 말을 거는 상대는 리눅스 콘솔이 아니라 libghostty-vt다. 셸과
    // ncurses 프로그램은 terminfo를 보고 시퀀스를 고르므로, 이름이 틀리면
    // 우리가 보내는 특수키와 셸이 기대하는 것이 어긋난다.
    //
    // execv는 환경을 그대로 상속하므로 **fork 전에** 고쳐두면 자식이 받는다.
    // 이 setenv가 PID 1이 아니라 여기 있는 이유는 시리얼 콘솔 셸 때문이다 —
    // 그쪽은 정말로 커널 콘솔이라 TERM=linux가 맞다. 같은 기계 안에서 두
    // 셸의 TERM이 다른 것이 정상이다(design doc 결정 7).
    //
    // xterm-256color가 아니라 xterm인 이유는 우리가 아직 색을 하나도 그리지
    // 않기 때문이다(TEXT_COLOR 상수 하나). 256색을 광고하면 반대 방향의
    // 거짓말이 된다.
    _ = setenv("TERM", "xterm", 1);
```

- [ ] **Step 4: terminfo 파일을 initrd에 넣는다**

`kernel/make_initrd.sh:134`(`__fish_build_paths.fish`를 복사하는 줄) **뒤에**
다음을 넣는다.

```bash
# IP-M1: terminal이 PTY 셸의 TERM을 xterm으로 바꾸므로(design doc 결정 7)
# 그 terminfo가 게스트에 있어야 한다. 없으면 부팅은 계속되지만 셸이 능력을
# 덜 쓴다 — 조용한 실패라서 input/check.sh가 initrd 목록을 직접 확인한다.
#
# 디렉터리를 통째로 복사하지 않고 파일 하나만 넣는다. ncurses-base의
# /usr/share/terminfo에는 수백 개가 들어 있고 우리가 광고하는 이름은
# 하나뿐이다. 시리얼 콘솔 셸이 쓰는 `linux`는 넣지 않는다 — 그쪽은 terminfo
# 없이도 지금까지 잘 돌아왔고, 넣는 순간 "무엇이 왜 필요한가"가 흐려진다.
mkdir -p "$WORKDIR/usr/share/terminfo/x"
cp "$SYSROOT/usr/share/terminfo/x/xterm" "$WORKDIR/usr/share/terminfo/x/xterm"
```

- [ ] **Step 5: initrd에 실제로 들어갔는지 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c \
  "cd init && zig build && cd ../terminal && ./prepare.sh && cd ../kernel && ./make_initrd.sh && zcat initrd.cpio | cpio -t 2>/dev/null | grep terminfo"
```

기대 출력:

```
./usr/share/terminfo
./usr/share/terminfo/x
./usr/share/terminfo/x/xterm
```

- [ ] **Step 6: 기존 두 체인이 살아 있는지 확인 (이 Task의 핵심)**

`TERM`이 바뀌면 셸이 프롬프트를 그리는 방식이 바뀔 수 있다. TF와 CP 체인은
화면 덤프를 grep하므로 **여기서 깨질 수 있다.** 게이트를 고치기 전에 본다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash config/check.sh
```

기대: 둘 다 `PASS`.

**깨진다면 무엇이 달라졌는지가 중요하다.** 화면 덤프 줄을 그대로 붙여 달라.
예상되는 변화는 셋이다.

- fish가 이제 색을 쓴다 → 덤프는 codepoint만 찍으므로 **영향 없어야 한다**.
  영향이 있다면 libghostty-vt가 SGR을 셀에 남기는 방식과 관련이 있다.
- fish가 bracketed paste(`ESC [ ? 2004 h`)나 `smkx`(`ESC [ ? 1 h`)를 보낸다 →
  **이건 오히려 좋은 소식이다.** 후자가 오면 design doc 위험 4가 해소되고
  게이트가 `ESC O` 경로를 실제로 밟는다.
- 프롬프트가 줄 전체 repaint 방식으로 바뀌어 덤프의 행 구성이 달라진다 →
  grep 패턴을 손봐야 할 수 있다. 이때는 **패턴을 느슨하게 만들지 말고**
  무엇이 달라졌는지 먼저 설명한다(게이트가 헛되게 통과하지 않도록).

- [ ] **Step 7: Commit**

Claude가 수행한다. 커밋 메시지: `Tell the shell it is talking to an xterm`

---

## Task 5: 게이트가 방향키를 증명한다

부팅은 여전히 **한 번**이다. IP-M0 게이트가 Ctrl+C를 끝내고 프롬프트로
돌아온 그 자리에서 이어서 친다 — 부팅을 하나 더 붙이는 대신 `sendkey` 열
몇 개(≈4초)를 더하는 쪽이 싸다.

**게이트가 헛되게 통과하지 않게 하는 장치가 이번에도 있다.** 방향키가 통째로
무시돼도 `echo abcX`는 멀쩡히 실행되어 화면에 출력이 뜬다. 그래서 **`aXbc`가
있어야 한다**와 **`abcX`가 없어야 한다**를 함께 본다. IP-M0의 `notdead`
검사와 같은 종류다.

**Files:**
- Modify: `input/check.sh`

- [ ] **Step 1: initrd에 terminfo가 있는지부터 검사**

`input/check.sh:42-45`의 `make_initrd.sh` 블록 **뒤에** 다음을 넣는다.

```bash
# TERM=xterm이 진실이려면 그 terminfo가 게스트 안에 있어야 한다(design doc
# 결정 7). 없어도 부팅은 계속되고 셸은 기능을 덜 쓸 뿐이라 **조용한
# 실패**다 — 부팅해서 알아내는 것보다 여기서 cpio 목록을 보는 편이 싸고
# 정확하다.
#
# 파이프라인 대신 변수에 담아 case로 보는 이유는 이 스크립트의 `set -o
# pipefail`이다. `... | grep -q`는 grep이 첫 매치에서 빠져나가며 앞단에
# SIGPIPE를 일으키고, pipefail이 그것을 실패로 판정한다.
INITRD_LIST="$(zcat ../kernel/initrd.cpio | cpio -t 2>/dev/null)"
case "$INITRD_LIST" in
  *usr/share/terminfo/x/xterm*) ;;
  *)
    echo "FAIL: xterm terminfo is missing from the initrd"
    echo "      (devcontainer/Dockerfile needs ncurses-base, and"
    echo "       kernel/make_initrd.sh needs to copy the file)"
    exit 1
    ;;
esac
```

- [ ] **Step 2: Ctrl+C 검사 뒤에 두 검사를 이어 붙인다**

지금 `input/check.sh:181-197`은 이 순서다: `FOUND` 루프 → monitor 닫기 →
QEMU 죽이기 → `FOUND` 판정. 새 검사를 넣으려면 **판정을 앞으로 당기고
QEMU를 더 살려둬야 한다.**

`:181-197`을 통째로 이것으로 바꾼다.

```bash
FOUND=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| ctrlcok" "$LOG"; then FOUND=1; break; fi
  sleep 1
done

# 판정을 여기서 한다. 아래 검사들이 프롬프트가 살아 있다는 전제 위에
# 서 있으므로, 그 전제가 깨졌으면 더 진행할 이유가 없다. report_failure는
# exit하고, QEMU는 trap의 cleanup이 거둔다.
if [ "$FOUND" != "1" ]; then
  report_failure "ctrl-c did not return the shell to a prompt (sleep survived, or the byte never arrived)"
fi
echo "ctrl-c killed the foreground child and the shell came back"

# ── 5) TERM이 xterm인지 (IP-M1, design doc 결정 7) ────────────────────
# sendkey는 문자가 아니라 **키**를 보내므로 대문자는 shift-로 조합한다.
# `$`는 shift-4다. 덕분에 이 줄은 Shift+문자 경로도 덤으로 한 번 더 밟는다.
#
# 출력 행(행 첫머리가 xterm인 것)을 본다. 방금 타이핑한 명령줄 행에도
# TERM이라는 글자가 있지만 그 행은 프롬프트와 echo로 시작한다.
echo "=== typing 'echo \$TERM' ==="
type_keys e c h o spc shift-4 shift-t shift-e shift-r shift-m ret

TERM_OK=0
for _ in $(seq 1 20); do
  if grep -q "terminal: screen>.*| xterm" "$LOG"; then TERM_OK=1; break; fi
  sleep 1
done
if [ "$TERM_OK" != "1" ]; then
  report_failure "the pty shell's TERM is not xterm (setenv before forkpty did not take effect)"
fi
echo "TERM is xterm inside the pty shell"

# ── 6) 방향키 (IP-M1의 본검사) ────────────────────────────────────────
# `echo abc`를 친 뒤 커서를 왼쪽으로 두 칸 옮기고 X를 끼운다.
#
#   방향키가 동작하면  → echo aXbc → 출력 행 "aXbc"
#   방향키가 무시되면  → echo abcX → 출력 행 "abcX"
#
# 그래서 **둘 다** 검사한다. 긍정 검사만으로는 "방향키가 통째로 무시됐다"를
# 구분할 수 없다 — 게이트는 자기가 안 보는 것을 통과시킨다
# (docs/decisions/project_gate_chain_composition.md).
#
# 방향키를 친 뒤에도 화면 검사를 하지 않고 Enter까지 가는 이유는, 편집 중인
# 명령줄 행은 프롬프트로 시작해서 "행 첫머리" 규칙을 쓸 수 없기 때문이다.
# 실행된 출력 행만이 깨끗한 증거다.
echo "=== typing 'echo abc', then left left X ==="
type_keys e c h o spc a b c
type_keys left left
type_keys shift-x
type_keys ret

ARROW_OK=0
ARROW_IGNORED=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| aXbc" "$LOG"; then ARROW_OK=1; break; fi
  if grep -q "terminal: screen>.*| abcX" "$LOG"; then ARROW_IGNORED=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

if [ "$ARROW_IGNORED" = "1" ]; then
  report_failure "the arrow keys did nothing: the line ran as 'echo abcX'"
fi
if [ "$ARROW_OK" != "1" ]; then
  report_failure "neither 'aXbc' nor 'abcX' appeared: the cursor went somewhere unexpected, or the escape sequence was wrong for this shell"
fi
echo "the arrow keys moved the cursor inside the line"

# design doc 위험 4의 관측. --no-config로 뜬 셸이 smkx를 보내지 않으면
# DECCKM은 계속 꺼져 있고 `ESC O` 경로는 게이트가 한 번도 밟지 않는다.
# 실패가 아니라 **어느 쪽이었는지 기록**이다 — 안 밟은 경로는 input_test가
# 덮는다.
if grep -q "decckm=true" "$LOG"; then
  echo "DECCKM was on: this run exercised the ESC O form"
else
  echo "DECCKM stayed off: this run only exercised the ESC [ form (input_test covers the other)"
fi
```

- [ ] **Step 3: 마커 목록에 하나 더한다**

`input/check.sh:83`의 `"terminal: screen>" \` 뒤(= `"terminal: key>"` 앞)는
그대로 두고, `report_failure`의 마커 목록 맨 뒤에 한 줄을 넣는다. `:84`의

```bash
    "terminal: key>"; do
```

를

```bash
    "terminal: key>" \
    "TERM"; do
```

으로 바꾼다. 실패했을 때 `TERM`이라는 글자가 화면 덤프에 아예 없으면
"타이핑이 안 됐다", 있는데 `xterm` 행이 없으면 "`setenv`가 안 먹었다"로
갈라진다.

- [ ] **Step 4: IP 체인을 단독으로 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash input/check.sh
```

기대: 맨 끝에 `PASS`, 그 앞에 이 네 줄이 순서대로.

```
the foreground child is blocking the shell
ctrl-c killed the foreground child and the shell came back
TERM is xterm inside the pty shell
the arrow keys moved the cursor inside the line
DECCKM ...
```

**실패하면 `report_failure`가 찍는 마커 목록과 마지막 화면 덤프 다섯 줄을
그대로 붙여 달라.** 구분해야 할 실패가 넷이다.

- `TERM` 행이 아예 없다 → `shift-4`(`$`)나 `shift-t` 같은 키 이름이 QEMU에
  없거나 우리 keymap에서 다르게 번역됐다. 화면 덤프의 명령줄 행을 보면
  무엇이 찍혔는지 바로 보인다.
- `TERM`은 보이는데 출력 행이 `linux`다 → `setenv`가 안 먹었다. `execv`가
  환경을 상속한다는 전제(`pty.zig:41`)를 다시 본다.
- `abcX`가 나왔다 → 방향키가 통째로 무시됐다. `terminal: key>` 줄의 바이트
  수를 본다. 방향키가 `3 byte(s)`로 찍혔는데도 무시됐다면 셸 쪽 문제이고,
  `key>` 자체가 안 찍혔다면 `sendkey left`가 게스트에 안 닿은 것이다.
- 둘 다 없다 → 커서가 엉뚱한 데로 갔다. `ESC O D`를 보냈는데 셸이 DECCKM을
  안 켠 상태라면 셸은 그걸 `ESC` + `OD`로 읽는다. `decckm=` 로그가 이때
  결정적인 증거다.

- [ ] **Step 5: Commit**

Claude가 수행한다. 커밋 메시지: `Make the gate edit the middle of a line`

---

## Task 6: 루트 게이트 전체

**Files:**
- Modify: `check.sh:53`

- [ ] **Step 1: 체인 이름을 갱신**

`check.sh:53`의

```bash
run_chain "IP-M0" ./input/check.sh
```

를

```bash
run_chain "IP-M1" ./input/check.sh
```

로 바꾼다. 그 위 주석 블록(`:50-53` 앞)의 IP 문단 끝에 한 문장을 덧붙인다.

```bash
# IP-M1부터 이 체인은 같은 부팅 안에서 Ctrl+C · TERM · 방향키 셋을 이어서
# 검사한다. 부팅을 늘리지 않고 sendkey만 열 개쯤 더한다 — 부팅 자체는 ~4초인데
# sendkey는 글자당 0.3초라, 이 체인에서 비싼 쪽은 타이핑이다.
```

- [ ] **Step 2: 전체 게이트 (오래 걸린다 — 20분 안팎)**

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh
```

기대: 마지막 줄이
`TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**측정값을 기록해 달라** — IP-M0가 19분 49초였다. 늘어난 분량이 추가한
`sendkey` 개수(≈14개 × 0.3초 × 3회 ≈ 13초)와 맞는지 본다. 그보다 훨씬 크면
`TERM` 변경이 셸의 시작 시간이나 렌더 횟수를 늘린 것이므로 따로 봐야 한다.

- [ ] **Step 3: Commit + push**

Claude가 수행한다. 커밋 메시지: `Retarget the aggregate gate at IP-M1`

---

## 완료 조건

- [ ] `input.Context`가 있고 `handleKey`/`readKeys`가 그것을 받는다
- [ ] ↑↓←→·Home·End가 `ESC [ X`를, DECCKM이 켜지면 `ESC O X`를 보낸다
- [ ] Delete·PageUp·PageDown이 `ESC [ N ~`을 보내고 **DECCKM에 흔들리지 않는다**
- [ ] `main.zig`가 `screen.term.modes.get(.cursor_keys)`로 그 값을 채운다
- [ ] PTY 셸의 `TERM`이 `xterm`이고 시리얼 콘솔 셸은 `linux` 그대로다
- [ ] `/usr/share/terminfo/x/xterm`이 initrd에 있고 게이트가 그것을 확인한다
- [ ] 게이트가 `echo abc` → ← ← → `X` → `echo aXbc`를 증명하고 `echo abcX`가
      **없음**을 함께 확인한다
- [ ] 루트 게이트가 4체인 3/3으로 PASS한다

## 이 milestone이 남기는 것 (IP-M2가 이어받는다)

- **Alt/Meta 넷이 여전히 추적되지 않는다.** modifier 여덟 개의 나머지 절반은
  dispatch 표와 함께 M2에서 처음 관측 가능해진다.
- **`Context.swap_alt_meta`가 아무도 안 읽는 필드로 남는다.** `keyboard=`
  설정이 도착하는 M2까지.
- **modifier + 특수키 조합이 맨 시퀀스로 새어 나간다.** `Ctrl+←`가 지금
  `ESC [ D`다. design doc 결정 2의 2번 단계(조합 dispatch)가 이 위에 얹히면
  가로채진다. `input_test`에 그 줄이 명시돼 있다.
- **`State.seq`는 아직 4바이트까지만 쓴다.** 6바이트(`ESC [ 1 ; 5 D`)는 M2다.
- **QEMU `sendkey meta_l`이 게스트에 닿는지 미검증.** M2의 첫 확인 대상이며,
  안 되면 `keyboard=pc` 쪽으로 게이트를 돌리는 우회가 있다(design doc 위험 1).
- **fish의 기본 바인딩이 design doc 결정 8의 표와 맞는지 미검증.** M2 게이트는
  `/usr/bin/bash`를 쳐서 readline 지형으로 들어간 뒤 검사한다 — 절대 경로인
  이유는 게스트에 `PATH`가 없기 때문이다(`project_guest_environment`).
