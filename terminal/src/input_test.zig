const std = @import("std");
const input = @import("input.zig");

/// evdev 키코드를 커널이 정한 이름으로 쓴다. `input.c`는 input.zig가
/// `@cImport("linux/input.h")`한 것을 그대로 공개한 것이다(IP-M2).
/// 숫자를 남겨두면 "105가 ←였나 →였나"를 매번 헤아려야 하는데, 이 파일은
/// IP-M2에서 검사가 두 배로 는다.
const K = input.c;

/// IP-M0부터 handleKey는 바이트 **하나**가 아니라 바이트 **열**을 돌려준다.
/// "보낼 것 없음"은 null이 아니라 빈 슬라이스다.
///
/// IP-M1부터 handleKey는 `Context`도 받는다. 대부분의 검사는 기본값
/// (`cursor_keys=false`)으로 충분하므로 여기서 채워 넣고, DECCKM 두 형태를
/// 비교해야 하는 검사만 아래 expectCtx를 직접 부른다.
fn expect(state: *input.State, code: u16, value: i32, want: []const u8) !void {
    return expectFull(state, .{}, code, value, 0, want);
}

/// HI-M3부터 `handleKey`는 시각도 받는다. **본체를 `expectFull`로 옮기고 기존
/// 헬퍼는 시각 0을 채우는 껍데기가 된다** — `expectCtx` 호출이 26군데라
/// 인자를 하나 더하면 26줄이 바뀌고, 그러면 "기존 검사가 한 글자도 안 바뀐 채
/// 통과했다"는 Task 1의 증거가 사라진다.
///
/// `Context`가 IP-M1에 들어왔을 때와 정확히 같은 모양이다.
fn expectAt(
    state: *input.State,
    code: u16,
    value: i32,
    time_us: u64,
    want: []const u8,
) !void {
    return expectFull(state, .{}, code, value, time_us, want);
}

/// TR-M2부터 handleKey는 바이트열이 아니라 `Action`을 돌려준다. 이 파일의
/// 검사 대부분은 여전히 바이트를 보므로, **"바이트가 아닌 것이 왔다"를
/// 실패로 취급하는 것**이 이 헬퍼의 새 일이다. 그냥 무시하면 스크롤 키가
/// 실수로 PTY 쪽 표에 들어갔을 때 검사가 조용히 통과한다.
fn expectCtx(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    want: []const u8,
) !void {
    return expectFull(state, ctx, code, value, 0, want);
}

fn expectFull(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    time_us: u64,
    want: []const u8,
) !void {
    switch (state.handleKey(code, value, time_us, ctx)) {
        .bytes => |bytes| {
            if (std.mem.eql(u8, bytes, want)) return;
            std.debug.print(
                "FAIL: code={d} value={d} ckm={} -> got={any}, want={any}\n",
                .{ code, value, ctx.cursor_keys, bytes, want },
            );
            return error.UnexpectedBytes;
        },
        .scroll => |s| {
            std.debug.print(
                "FAIL: code={d} value={d} -> got scroll .{s}, want bytes {any}\n",
                .{ code, value, @tagName(s), want },
            );
            return error.UnexpectedScroll;
        },
        .copy => |cmd| {
            std.debug.print(
                "FAIL: code={d} value={d} -> got copy .{s}, want bytes {any}\n",
                .{ code, value, @tagName(cmd), want },
            );
            return error.UnexpectedCopy;
        },
        .hangul => {
            std.debug.print(
                "FAIL: code={d} value={d} -> got hangul, want bytes {any}\n",
                .{ code, value, want },
            );
            return error.UnexpectedHangul;
        },
    }
}

/// copy 명령이 나오기를 기대한다. **바이트가 오면 실패다** — 그것이 정확히
/// "모드 안에서 키가 PTY로 샌다"는 사고이기 때문이다.
fn expectCopy(state: *input.State, code: u16, want: input.Copy) !void {
    switch (state.handleKey(code, 1, 0, .{})) {
        .copy => |cmd| {
            // **union에는 `==`가 없다**(CN-M1 Task 1). `std.meta.eql`이 태그를
            // 먼저 보고 payload를 그다음에 본다 — `.find_char`가 생기면 글자까지
            // 비교하게 되고, 그것이 우리가 원하는 것이다.
            if (std.meta.eql(cmd, want)) return;
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
        .hangul => {
            std.debug.print(
                "FAIL: code={d} -> got hangul, want copy .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedHangul;
        },
    }
}

/// 스크롤 동작을 기대하는 검사. **바이트가 오면 실패다** — 그것이 곧
/// "스크롤 키가 PTY로 샜다"는 뜻이고, design 결정 11이 막으려는 바로 그
/// 상황이다.
fn expectScroll(
    state: *input.State,
    code: u16,
    value: i32,
    want: input.Scroll,
) !void {
    switch (state.handleKey(code, value, 0, .{})) {
        .scroll => |s| {
            if (s == want) return;
            std.debug.print(
                "FAIL: code={d} -> got scroll .{s}, want .{s}\n",
                .{ code, @tagName(s), @tagName(want) },
            );
            return error.WrongScroll;
        },
        .bytes => |bytes| {
            std.debug.print(
                "FAIL: code={d} -> got bytes {any}, want scroll .{s}\n",
                .{ code, bytes, @tagName(want) },
            );
            return error.ExpectedScroll;
        },
        .copy => |cmd| {
            std.debug.print(
                "FAIL: code={d} -> got copy .{s}, want scroll .{s}\n",
                .{ code, @tagName(cmd), @tagName(want) },
            );
            return error.UnexpectedCopy;
        },
        .hangul => {
            std.debug.print(
                "FAIL: code={d} -> got hangul, want scroll .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedHangul;
        },
    }
}

/// 한글 층이 이 키를 처리하기를 기대한다(HI-M1). **바이트가 오면 실패다** —
/// 그것이 곧 "조합 중인 자모가 PTY로 샜다"이고, 이 milestone의 가장 흔한
/// 실패 방식이다.
///
/// 셋을 한 번에 본다: 어느 variant가 왔는가 · 무엇이 확정됐는가 · 무엇을
/// 조합 중인가. **셋이 함께 있어야 뜻이 선다** — 확정만 보면 화면이 안 바뀐
/// 것을 못 잡고, 조합만 보면 확정된 글자가 셸에 안 간 것을 못 잡는다.
fn expectHangul(
    state: *input.State,
    code: u16,
    want_commit: []const u8,
    want_preedit: ?u21,
) !void {
    return expectHangulAt(state, code, 1, 0, want_commit, want_preedit);
}

/// 시각과 누름/뗌을 직접 주는 형태(HI-M3). **tap이 한/영을 바꾸는 것은 키를
/// 뗄 때이므로**(결정 8) `value = 0`을 넣을 수 있어야 하는데, 위 껍데기는
/// 언제나 누름(1)이다.
fn expectHangulAt(
    state: *input.State,
    code: u16,
    value: i32,
    time_us: u64,
    want_commit: []const u8,
    want_preedit: ?u21,
) !void {
    switch (state.handleKey(code, value, time_us, .{})) {
        .hangul => {},
        .bytes => |bytes| {
            std.debug.print(
                "FAIL: code={d} -> got {d} byte(s) {any}, want hangul\n",
                .{ code, bytes.len, bytes },
            );
            return error.LeakedToPty;
        },
        .scroll => |s| {
            std.debug.print(
                "FAIL: code={d} -> got scroll .{s}, want hangul\n",
                .{ code, @tagName(s) },
            );
            return error.UnexpectedScroll;
        },
        .copy => |cmd| {
            std.debug.print(
                "FAIL: code={d} -> got copy .{s}, want hangul\n",
                .{ code, @tagName(cmd) },
            );
            return error.UnexpectedCopy;
        },
    }
    try expectCommit(state, code, want_commit);
    try expectPreedit(state, code, want_preedit);
}

/// 확정된 글자를 본다. **`handleKey`를 부른 직후에만 뜻이 있다** — 한 번
/// 가져가면 비워지기 때문이다(`takeCommit`). `readKeys`가 지키는 순서를 이
/// 파일이 같은 순서로 흉내 내는 자리다.
fn expectCommit(state: *input.State, code: u16, want: []const u8) !void {
    const got = state.takeCommit();
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print(
        "FAIL: code={d} -> committed \"{s}\", want \"{s}\"\n",
        .{ code, got, want },
    );
    return error.WrongCommit;
}

/// 조합 중인 글자를 본다. null이 "조합 중이 아니다"이다.
fn expectPreedit(state: *input.State, code: u16, want: ?u21) !void {
    const got = state.preedit();
    if (std.meta.eql(got, want)) return;
    std.debug.print(
        "FAIL: code={d} -> preedit {?d}, want {?d}\n",
        .{ code, got, want },
    );
    return error.WrongPreedit;
}

pub fn main() !void {
    // struct input_event가 @cImport로 제대로 넘어왔는지부터 확인한다.
    std.debug.print("input_event size = {d} (expected 24)\n", .{input.eventSize()});
    if (input.eventSize() != 24) {
        std.debug.print("FAIL: unexpected struct input_event size\n", .{});
        return error.UnexpectedEventSize;
    }

    var state: input.State = .{};

    // "hi" 타이핑: 누를 때만 문자가 나오고, 뗄 때는 안 나온다.
    try expect(&state, K.KEY_H, 1, "h");
    try expect(&state, K.KEY_H, 0, "");
    try expect(&state, K.KEY_I, 1, "i");
    try expect(&state, K.KEY_I, 0, "");

    // Enter는 CR을 보낸다.
    try expect(&state, K.KEY_ENTER, 1, "\r");

    // Shift를 누르면 그 자체는 문자가 없고, 이어지는 키가 대문자가 된다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_H, 1, "H"); // shifted
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_H, 1, "h"); // unshifted 복귀

    // 좌우 Shift는 각자 추적된다. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도
    // Shift는 풀리지 않아야 한다 — 손은 아직 왼쪽을 누르고 있다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_RIGHTSHIFT, 1, "");
    try expect(&state, K.KEY_RIGHTSHIFT, 0, "");
    try expect(&state, K.KEY_H, 1, "H"); // 여전히 대문자
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_H, 1, "h"); // 이제 소문자

    // Shift + 숫자 = 기호.
    try expect(&state, K.KEY_RIGHTSHIFT, 1, "");
    try expect(&state, K.KEY_1, 1, "!"); // shifted
    try expect(&state, K.KEY_RIGHTSHIFT, 0, "");

    // 자동 반복(value=2)도 문자를 만든다. 방향키를 누르고 있으면 계속
    // 움직여야 하므로 이 성질은 오히려 필요하다.
    try expect(&state, K.KEY_A, 2, "a"); // autorepeat

    // 표에 없는 키코드는 조용히 무시한다. 여기만 숫자로 남기는 이유는 이
    // 줄의 요점이 **이름이 없는 코드**라서다 — 이름을 붙이면 뜻이 사라진다.
    try expect(&state, 200, 1, "");

    // ── Ctrl 제어 문자 (IP-M0) ──────────────────────────────────────────
    //
    // 규칙은 한 줄이다: Shift를 먼저 적용해 문자를 정한 뒤 `& 0x1F`.
    // ASCII에서 제어 문자 0x00~0x1F는 `@ABC…Z[\]^_`(0x40~0x5F)에서 상위 두
    // 비트를 뗀 것이므로, 마스크가 곧 정의다.

    try expect(&state, K.KEY_LEFTCTRL, 1, ""); // 그 자체는 문자 없음
    try expect(&state, K.KEY_C, 1, "\x03"); // Ctrl+C → SIGINT를 부르는 바이트
    try expect(&state, K.KEY_D, 1, "\x04"); // Ctrl+D → EOF
    try expect(&state, K.KEY_Z, 1, "\x1a"); // Ctrl+Z → SIGTSTP
    try expect(&state, K.KEY_BACKSLASH, 1, "\x1c"); // Ctrl+\ → SIGQUIT
    try expect(&state, K.KEY_LEFTBRACE, 1, "\x1b"); // Ctrl+[ → ESC
    try expect(&state, K.KEY_SPACE, 1, "\x00"); // Ctrl+Space → NUL

    // 마스크가 의미 있는 것은 문자가 0x40~0x7F일 때뿐이다. Ctrl+1에
    // 적용하면 0x31 & 0x1F = 0x11(XON)이 나오는데 아무도 그런 뜻으로 쓰지
    // 않는다. 대상이 아닌 문자는 Ctrl을 무시하고 원래 문자를 보낸다.
    try expect(&state, K.KEY_1, 1, "1"); // Ctrl+1 → 그냥 '1'

    // Shift가 함께 눌려도 제어 문자는 같다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_C, 1, "\x03"); // Ctrl+Shift+C → 여전히 0x03
    // Shift+2는 '@'이고 '@' & 0x1F = 0x00이다.
    try expect(&state, K.KEY_2, 1, "\x00"); // Ctrl+Shift+2 → NUL
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");

    try expect(&state, K.KEY_LEFTCTRL, 0, "");
    try expect(&state, K.KEY_C, 1, "c"); // Ctrl을 떼면 다시 평문

    // 오른쪽 Ctrl도 같다.
    try expect(&state, K.KEY_RIGHTCTRL, 1, "");
    try expect(&state, K.KEY_C, 1, "\x03");
    try expect(&state, K.KEY_RIGHTCTRL, 0, "");

    // 좌우 Ctrl 각자 추적. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도 안 풀린다.
    try expect(&state, K.KEY_LEFTCTRL, 1, "");
    try expect(&state, K.KEY_RIGHTCTRL, 1, "");
    try expect(&state, K.KEY_RIGHTCTRL, 0, "");
    try expect(&state, K.KEY_C, 1, "\x03"); // 여전히 Ctrl
    try expect(&state, K.KEY_LEFTCTRL, 0, "");
    try expect(&state, K.KEY_C, 1, "c");

    // ── 특수키 → 이스케이프 시퀀스 (IP-M1) ──────────────────────────────
    //
    // 여기서 처음으로 키 하나가 바이트 여러 개가 된다. IP-M0가 반환 타입을
    // []const u8로 바꾼 이유가 이것이다 — 표를 아무리 늘려도 ?u8로는
    // `ESC [ D` 세 바이트를 표현할 수 없었다.

    // DECCKM 꺼짐(기본): `ESC [ X`
    try expect(&state, K.KEY_UP, 1, "\x1b[A");
    try expect(&state, K.KEY_DOWN, 1, "\x1b[B");
    try expect(&state, K.KEY_RIGHT, 1, "\x1b[C");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D");
    try expect(&state, K.KEY_HOME, 1, "\x1b[H");
    try expect(&state, K.KEY_END, 1, "\x1b[F");

    // 틸드 계열은 DECCKM과 무관하게 언제나 같은 모양이다.
    try expect(&state, K.KEY_DELETE, 1, "\x1b[3~");
    try expect(&state, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expect(&state, K.KEY_PAGEDOWN, 1, "\x1b[6~");

    // 뗄 때는 여전히 아무것도 안 보낸다.
    try expect(&state, K.KEY_LEFT, 0, "");
    // 자동 반복은 보낸다 — 방향키를 누르고 있으면 계속 움직여야 한다.
    try expect(&state, K.KEY_LEFT, 2, "\x1b[D");

    // ── DECCKM 켜짐: 커서 계열만 `ESC O X`로 바뀐다 ─────────────────────
    //
    // 이 모드가 실제로 켜지는지는 셸에 달려 있고(smkx), --no-config로 뜬
    // 셸이 안 보내면 게이트는 이 경로를 한 번도 밟지 않는다(design doc
    // 위험 4). 그래서 **여기서** 두 형태를 다 본다.
    const ckm = input.Context{ .cursor_keys = true };
    try expectCtx(&state, ckm, K.KEY_UP, 1, "\x1bOA");
    try expectCtx(&state, ckm, K.KEY_DOWN, 1, "\x1bOB");
    try expectCtx(&state, ckm, K.KEY_RIGHT, 1, "\x1bOC");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bOD");
    try expectCtx(&state, ckm, K.KEY_HOME, 1, "\x1bOH");
    try expectCtx(&state, ckm, K.KEY_END, 1, "\x1bOF");

    // 틸드 계열은 DECCKM이 켜져도 그대로다. 이 세 줄이 위 여섯 줄만큼
    // 중요하다 — "모드가 켜지면 전부 O로 바꾼다"는 흔한 오해를 막는다.
    try expectCtx(&state, ckm, K.KEY_DELETE, 1, "\x1b[3~");
    try expectCtx(&state, ckm, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expectCtx(&state, ckm, K.KEY_PAGEDOWN, 1, "\x1b[6~");

    // ── modifier가 넷에서 여덟으로 (IP-M2, design doc 결정 4) ────────────
    //
    // Alt 좌우(56/100)와 Meta 좌우(125/126)가 들어온다. IP-M0가 이 넷을
    // "관측 가능해지는 시점에 넣는다"며 미룬 이유가 아래 두 줄이다 —
    // modifier 비트만 있으면 반환값이 한 글자도 안 바뀌어서 검사가 성립하지
    // 않는다. 그 시점이 바로 다음 블록(조합 dispatch)이다.
    try expect(&state, K.KEY_LEFTALT, 1, ""); // 그 자체는 문자가 없다
    try expect(&state, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFTMETA, 1, ""); // 125는 keymap.len(58) 밖이다
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    // ── Option 조합 (design doc 결정 8) ─────────────────────────────────
    //
    // 셸이 **이미 아는 언어**로 번역한다(A안). ESC 접두사는 터미널에서
    // "Meta+그 글자"를 뜻하는 오래된 관례이고, readline/zle/fish가 전부
    // 기본값으로 안다 — 설정 파일 없이 동작한다는 것이 A안을 고른 결정적
    // 이유였다(그래야 --no-config로 뜬 셸에서 게이트가 증명할 수 있다).
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // backward-word
    try expect(&state, K.KEY_RIGHT, 1, "\x1bf"); // forward-word
    try expect(&state, K.KEY_BACKSPACE, 1, "\x1b\x7f"); // backward-kill-word
    try expect(&state, K.KEY_DELETE, 1, "\x1bd"); // kill-word

    // 표에 없는 조합은 modifier를 무시하고 원래 키를 보낸다. Ctrl이 마스크
    // 대상이 아닌 문자(Ctrl+1 → '1')를 다루는 방식과 같은 규칙이다 —
    // 가로챌 것만 가로채고 나머지는 평소대로.
    try expect(&state, K.KEY_B, 1, "b"); // Option+b는 이번 범위가 아니다
    try expect(&state, K.KEY_UP, 1, "\x1b[A"); // Option+↑도 그냥 ↑
    try expect(&state, K.KEY_LEFTALT, 0, "");

    // 오른쪽 Alt(100)도 같다. 좌우를 따로 추적하는 이유는 Shift/Ctrl과
    // 같다 — 하나를 누른 채 다른 하나를 눌렀다 떼도 풀리면 안 된다.
    try expect(&state, K.KEY_RIGHTALT, 1, "");
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_RIGHTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // 여전히 Option
    try expect(&state, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // 이제 맨 ←

    // ── Cmd 조합 ────────────────────────────────────────────────────────
    //
    // 이쪽은 ESC 접두사가 아니라 **제어 문자 한 바이트**다. Cmd+←가 0x01
    // (Ctrl+A)인 이유는 그것이 readline의 beginning-of-line이기 때문이지
    // 무슨 대응 관계가 있어서가 아니다 — "셸이 이미 아는 언어"라는 것이
    // 유일한 기준이다.
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // beginning-of-line
    try expect(&state, K.KEY_RIGHT, 1, "\x05"); // end-of-line
    try expect(&state, K.KEY_BACKSPACE, 1, "\x15"); // 줄 앞부분 삭제

    // Cmd+Delete는 표에 없다 → 맨 Delete가 나간다.
    try expect(&state, K.KEY_DELETE, 1, "\x1b[3~");
    // Cmd+C는 **여전히 일부러 비워둔 자리**다(design doc 비목표, CM design
    // 결정 4). 모드 밖에서는 무엇을 복사할지가 정해져 있지 않다.
    try expect(&state, K.KEY_C, 1, "c");
    // **Cmd+V는 CM-M2가 채웠다.** 원래 이 자리에 "복사·붙여넣기는 그때 이 두
    // 줄이 바뀐다"고 적혀 있었는데, 바뀐 것은 둘 중 하나뿐이다 — 붙여넣기는
    // 모드 밖에서도 뜻이 있지만 복사는 그렇지 않기 때문이다.
    //
    // 바이트가 아니라 copy 명령이 오는 것이 핵심이고, 그것을 여기서 보는 것은
    // 아래 copy mode 검사들과 다른 일이다. 이 줄은 **모드가 normal일 때**를
    // 본다 — 즉 chord()의 Meta 분기 쪽이다.
    try expectCopy(&state, K.KEY_V, .paste);
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    try expect(&state, K.KEY_RIGHTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // 오른쪽 Meta(126)도 같다
    try expect(&state, K.KEY_RIGHTMETA, 0, "");

    // ── 둘 다 눌리면 Cmd가 이긴다 ───────────────────────────────────────
    //
    // 임의의 선택이지만 **결정적**이어야 한다. macOS에서 Cmd가 더 강한
    // modifier라는 직관과 맞고, 코드에서는 chord가 Meta를 먼저 보는 것으로
    // 표현된다. 이 줄이 그 순서를 못 박는다.
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // ESC b가 아니라 0x01
    try expect(&state, K.KEY_LEFTMETA, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // Meta를 떼면 Option으로
    try expect(&state, K.KEY_LEFTALT, 0, "");

    // ── 조합은 DECCKM보다 강하다 ────────────────────────────────────────
    //
    // dispatch가 특수키 조회보다 **먼저** 오기 때문이다(design doc 결정 2의
    // "가로챌 것을 먼저"). Option+←는 DECCKM이 켜져 있어도 ESC b이고,
    // ESC O D로 바뀌지 않는다. 순서가 뒤집히면 이 줄이 먼저 터진다.
    try expectCtx(&state, ckm, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bb");
    try expectCtx(&state, ckm, K.KEY_LEFTALT, 0, "");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bOD"); // 조합이 없으면 다시 DECCKM

    // ── keyboard=pc: Alt와 Meta를 맞바꾼다 (IP-M2, design doc 결정 9) ────
    //
    // 스페이스 옆 두 키의 순서가 Apple과 PC에서 정확히 뒤집혀 있다.
    //   Apple: [Ctrl] [Option 56] [Cmd 125]
    //   PC:    [Ctrl] [Win 125]   [Alt 56]
    // 그래서 하는 일은 modifier를 기록하기 **전에** 코드를 맞바꾸는 것뿐이고,
    // 그 뒤 로직(chord, keymap, specialKey)은 어느 키보드인지 전혀 모른다.
    //
    // 이 검사가 게이트보다 중요한 이유가 하나 있다: 게이트는 QEMU가 보내는
    // 물리 키 하나만 볼 수 있지만, 여기서는 네 키를 다 볼 수 있다.
    const pc = input.Context{ .swap_alt_meta = true };

    // 물리 Alt(56)를 누르면 Meta로 기록된다 → Cmd 의미가 나온다.
    try expectCtx(&state, pc, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x01"); // ESC b가 아니라 0x01
    try expectCtx(&state, pc, K.KEY_RIGHT, 1, "\x05");
    try expectCtx(&state, pc, K.KEY_LEFTALT, 0, "");

    // 물리 Meta(125)를 누르면 Alt로 기록된다 → Option 의미가 나온다.
    try expectCtx(&state, pc, K.KEY_LEFTMETA, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1bb"); // 0x01이 아니라 ESC b
    try expectCtx(&state, pc, K.KEY_BACKSPACE, 1, "\x1b\x7f");
    try expectCtx(&state, pc, K.KEY_LEFTMETA, 0, "");

    // 오른쪽 짝(100↔126)도 같이 바뀐다. 왼쪽만 고치는 실수를 여기서 잡는다.
    try expectCtx(&state, pc, K.KEY_RIGHTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x01");
    try expectCtx(&state, pc, K.KEY_RIGHTALT, 0, "");
    try expectCtx(&state, pc, K.KEY_RIGHTMETA, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1bb");
    try expectCtx(&state, pc, K.KEY_RIGHTMETA, 0, "");

    // 교환은 **modifier 키에만** 일어난다. 글자 키는 그대로다.
    try expectCtx(&state, pc, K.KEY_A, 1, "a");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1b[D");

    // 뗌 이벤트도 같은 ctx로 들어오므로 짝이 맞는다. 부팅 중에 keyboard
    // 설정이 바뀌는 일은 없다 — PID 1이 부팅 시점에 한 번 정해서 argv로
    // 넘기고, 그 값은 프로세스가 사는 동안 상수다.
    try expectCtx(&state, pc, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // 아무 modifier도 안 남았다

    // ── Shift 스크롤 (TR-M2, design 결정 11·12) ─────────────────────────
    //
    // 여기서 처음으로 키가 **바이트가 아닌 것**을 돌려준다. IP-M2까지
    // handleKey의 반환은 []const u8 하나였고, 그래서 "PTY로 보내지 않고
    // 우리가 처리한다"를 표현할 방법이 아예 없었다.
    //
    // 몇 줄이 한 화면인지는 여기 안 나온다. input.zig는 격자 크기를 모르고,
    // page_up을 rows 만큼의 delta로 바꾸는 것은 main.zig의 일이다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expectScroll(&state, K.KEY_PAGEUP, 1, .page_up);
    try expectScroll(&state, K.KEY_PAGEDOWN, 1, .page_down);
    try expectScroll(&state, K.KEY_HOME, 1, .top);
    try expectScroll(&state, K.KEY_END, 1, .bottom);

    // 자동 반복도 스크롤한다 — 누르고 있으면 계속 올라가야 한다.
    try expectScroll(&state, K.KEY_PAGEUP, 2, .page_up);
    // 뗄 때는 여전히 아무 일도 없다.
    try expect(&state, K.KEY_PAGEUP, 0, "");

    // Shift+표에 없는 특수키는 평소대로 PTY로 나간다.
    try expect(&state, K.KEY_DELETE, 1, "\x1b[3~");
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");

    // **Shift를 떼면 넷 다 원래대로 돌아온다.** 이 줄들이 없으면 "스크롤이
    // 되는가"만 보고 "안 되어야 할 때 원래대로인가"를 안 보게 된다. Home/End는
    // 특히 중요하다 — 셸의 줄 편집이 쓰는 키다.
    try expect(&state, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expect(&state, K.KEY_PAGEDOWN, 1, "\x1b[6~");
    try expect(&state, K.KEY_HOME, 1, "\x1b[H");
    try expect(&state, K.KEY_END, 1, "\x1b[F");

    // 오른쪽 Shift도 같다. 좌우를 따로 추적하는 성질은 그대로다.
    try expect(&state, K.KEY_RIGHTSHIFT, 1, "");
    try expectScroll(&state, K.KEY_PAGEUP, 1, .page_up);
    try expect(&state, K.KEY_RIGHTSHIFT, 0, "");

    // ── Cmd가 Shift를 이긴다 ────────────────────────────────────────────
    //
    // chord가 Meta를 먼저 보고, 조합이 표에 없으면 null로 chord 전체를
    // 끝내기 때문이다. 그래서 Cmd+Shift+PageUp은 스크롤하지 않고 맨 PageUp이
    // 된다. 임의의 선택이지만 결정적이어야 하고, Cmd는 project_copy_mode가
    // 예약한 자리라 여기서 뜻을 더하지 않는다.
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    // Option도 마찬가지다.
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_HOME, 1, "\x1b[H");
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_LEFTALT, 0, "");

    // ── 여전히 안 하는 것 ───────────────────────────────────────────────
    //
    // Ctrl+방향키(`ESC [ 1 ; 5 D`)와 Shift+방향키는 **TR-M2도 하지 않는다.**
    // 바로 위에서 Shift에 뜻이 생겼지만 그것은 PageUp/PageDown/Home/End 넷뿐이고,
    // 방향키 자체는 여전히 맨 시퀀스로 나간다.
    // IP-M1의 주석은 "M2의 조합 dispatch가 이 위에 얹히면서 바뀐다"고 적었지만
    // 그렇지 않았다 — 결정 8의 표에 있는 것은 Option과 Cmd 일곱 줄뿐이고,
    // Ctrl+방향키를 누를 이유가 있는 앱이 아직 하나도 없다(design doc 비목표:
    // "게이트가 볼 수 없는 표를 늘리지 않는다").
    //
    // 그래서 State.seq의 8바이트 중 이번에도 4바이트까지만 쓴다. 6바이트를
    // 쓰는 형태가 바로 이 `ESC [ 1 ; 5 D`다.
    try expect(&state, K.KEY_LEFTCTRL, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // Ctrl+← → 아직도 그냥 ←
    try expect(&state, K.KEY_LEFTCTRL, 0, "");

    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // Shift+← → 아직도 그냥 ←
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");

    // 특수키 사이의 빈 코드(F1 등)는 여전히 조용히 무시된다.
    try expect(&state, K.KEY_F1, 1, "");
    try expect(&state, K.KEY_INSERT, 1, "");

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
    //
    // **CN-M0이 이 목록에서 `w`를 뺐다.** 그것이 이제 `.word_next`라서
    // 여기서는 "모르는 키"가 아니다. 자리를 `z`로 메운다 — 게이트가 대조군으로
    // 쓰는 것과 같은 키다.
    //
    // **`n`은 CN-M1의 검색이 가져갔다.** CN-M0이 여기 남긴 예고가 그것이었고,
    // 이 목록에 `n`이 없었던 덕에 이번에는 아무 줄도 안 깨졌다 — `w`를 배선할
    // 때와 갈리는 자리다.
    //
    // **`e`는 아직 모르는 키다.** CN이 일부러 안 만든 단어 이동이고
    // (design 결정 2), 누군가 `e`를 더하면 그때 이 줄이 바뀐다.
    // 예고를 여기서 갚는다.
    try expect(&cm, K.KEY_Q, 1, "");
    try expect(&cm, K.KEY_Z, 1, "");
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

    // 검사 8. Cmd 없는 c는 여전히 삼켜진다. **이것이 없으면 아래 검사 10이
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

    // ── CN-M1: 검색 프롬프트 ────────────────────────────────────────────
    //
    // 검사 17. `/`가 프롬프트를 열고, **그 안에서 키가 글자가 된다.**
    // `n`으로 보는 것이 핵심이다 — 그것은 Task 5에서 copy 표의 명령이 되므로,
    // 표보다 프롬프트가 먼저 보지 않으면 needle에 `n`을 못 치게 된다.
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    try expectCopy(&cm, K.KEY_SLASH, .find_open);
    try expectCopy(&cm, K.KEY_N, .{ .find_char = 'n' });
    try expectCopy(&cm, K.KEY_E, .{ .find_char = 'e' });
    try expectCopy(&cm, K.KEY_W, .{ .find_char = 'w' });

    // 검사 18. **Shift가 대문자를 만든다.** 프롬프트는 명령 표가 아니라
    // keymap을 그대로 쓰므로 대소문자가 갈린다 — `w`/`b`가 Shift를 안 가르는
    // 것과 정확히 반대다.
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_A, .{ .find_char = 'A' });
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");

    // 검사 19. Backspace와 Enter와 Esc.
    try expectCopy(&cm, K.KEY_BACKSPACE, .find_erase);
    try expectCopy(&cm, K.KEY_ENTER, .find_submit);
    // Enter가 프롬프트를 닫았으므로 여기서 `n`은 다시 **명령 표의 것**이다.
    // Task 2 시점에는 모르는 키라 삼켜졌고, Task 5가 검색 이동을 붙이면서
    // `.find_next`가 됐다 — **이 줄이 그 예고를 갚은 자리다.**
    try expectCopy(&cm, K.KEY_N, .find_next);

    // 검사 20. **Esc는 프롬프트만 닫는다**(design 결정 9). 이 검사가 없으면
    // "Esc 한 번에 모드까지 나간다"도 통과하고, 그러면 오타를 고치려던 사람이
    // 스크롤 위치와 선택을 잃는다.
    try expectCopy(&cm, K.KEY_SLASH, .find_open);
    try expectCopy(&cm, K.KEY_X, .{ .find_char = 'x' });
    try expectCopy(&cm, K.KEY_ESC, .find_cancel);
    if (cm.mode != .copy) {
        std.debug.print("FAIL: Esc in the find prompt left copy mode\n", .{});
        return error.FindCancelLeftMode;
    }
    // **두 번째 Esc가 모드를 닫는다.**
    try expectCopy(&cm, K.KEY_ESC, .exit);

    // 검사 21. **모드 밖의 `/`는 평범한 글자다.** CN-M0의 검사 14와 같은
    // 대조군이고, 이것이 없으면 셸에 `/`를 못 치게 된 것을 아무도 모른다.
    try expect(&cm, K.KEY_SLASH, 1, "/");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expect(&cm, K.KEY_SLASH, 1, "?");
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");

    // 검사 22. **`n`/`N`이 모드 안에서 명령이고 밖에서는 글자다.**
    try expect(&cm, K.KEY_N, 1, "n");
    try expect(&cm, K.KEY_LEFTMETA, 1, "");
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_C, .enter);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expect(&cm, K.KEY_LEFTMETA, 0, "");
    try expectCopy(&cm, K.KEY_N, .find_next);
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_N, .find_prev);
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");

    // 검사 23. **프롬프트 안에서는 `n`이 다시 글자다.** 이것이 이 milestone에서
    // 순서 하나가 정하는 사실이고, 깨지면 "검색어에 n을 못 친다"가 된다.
    try expectCopy(&cm, K.KEY_SLASH, .find_open);
    try expectCopy(&cm, K.KEY_N, .{ .find_char = 'n' });
    try expect(&cm, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&cm, K.KEY_N, .{ .find_char = 'N' });
    try expect(&cm, K.KEY_LEFTSHIFT, 0, "");
    try expectCopy(&cm, K.KEY_ESC, .find_cancel);
    // 프롬프트를 닫았으니 `n`은 다시 명령이다.
    try expectCopy(&cm, K.KEY_N, .find_next);
    try expectCopy(&cm, K.KEY_ESC, .exit);

    std.debug.print("input_test: copy mode OK\n", .{});

    // ── HI-M1: 한글 ───────────────────────────────────────────────────

    // **자판을 명시한다.** 아래 검사 여덟은 전부 두벌식을 보는데, HI-M2부터
    // `State`의 기본값이 `shin_pcs`다(설정의 기본값과 같게 둔다). 안 적으면
    // `r`이 ㄱ이 아니라 ㅓ가 되어 전부 갈린다.
    var hg: input.State = .{ .hangul_layout = .dubeol };

    // 검사 24. **대조군 — 한글이 꺼져 있으면 아무것도 안 바뀐다.**
    // 이 검사가 없으면 아래 검사들이 "한글이 되는가"만 보고 "영문이 계속
    // 되는가"를 안 본다. `r`은 두벌식에서 ㄱ이라 가장 잘 갈린다.
    try expect(&hg, K.KEY_R, 1, "r");
    try expectPreedit(&hg, K.KEY_R, null);

    // 검사 25. **Shift+Space가 한/영을 바꾸고 공백은 PTY로 안 나간다.**
    // 빈 슬라이스가 아니라 `.hangul`이 와야 한다 — `.bytes = ""`로 만들면
    // 화면이 다시 안 그려져서 그 뒤의 조합이 안 보인다.
    try expect(&hg, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&hg, K.KEY_SPACE, "", null);
    try expect(&hg, K.KEY_LEFTSHIFT, 0, "");
    if (!hg.hangul_on) {
        std.debug.print("FAIL: Shift+Space did not turn hangul on\n", .{});
        return error.ToggleFailed;
    }

    // 검사 26. **두벌식으로 `한글`을 친다.** `gksrmf`이고 `hangul_test`의
    // 검사 4가 같은 글자열을 오토마타 쪽에서 본다 — **이 검사가 보는 것은
    // 오토마타가 아니라 배선이다.** evdev 코드 → keymap → dubeol → feed까지
    // 한 줄이라도 어긋나면 여기서 갈린다.
    try expectHangul(&hg, K.KEY_G, "", 'ㅎ');
    try expectHangul(&hg, K.KEY_K, "", '하');
    try expectHangul(&hg, K.KEY_S, "", '한');
    // `ㄱ`은 `ㄴ`과 겹받침이 안 되므로 `한`이 확정되고 새 초성이 된다.
    try expectHangul(&hg, K.KEY_R, "한", 'ㄱ');
    try expectHangul(&hg, K.KEY_M, "", '그');
    try expectHangul(&hg, K.KEY_F, "", '글');

    // 검사 27. **Enter가 확정시키고, 확정된 글자와 CR이 둘 다 나간다.**
    // `expect`가 반환된 바이트를, 이어지는 `expectCommit`이 그보다 **먼저**
    // 나갈 글자를 본다 — 두 줄의 순서가 곧 `readKeys`의 계약이다.
    try expect(&hg, K.KEY_ENTER, 1, "\r");
    try expectCommit(&hg, K.KEY_ENTER, "글");
    try expectPreedit(&hg, K.KEY_ENTER, null);

    // 검사 28. **확정을 유발하는 것 넷**(design 결정 6). 넷이 서로 다른
    // 갈래로 빠진다: 공백(자모가 아닌 문자 키) · 방향키(표 밖) ·
    // Ctrl 조합 · Meta 조합으로 copy mode 진입.
    //
    // **Cmd+Shift+C가 이 목록에서 가장 미묘하다.** 반환값이 `.copy = .enter`라
    // 확정된 글자를 담을 자리가 없고, 그래서 `commit_buf`라는 통로가 생겼다.
    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_SPACE, 1, " ");
    try expectCommit(&hg, K.KEY_SPACE, "가");

    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFT, 1, "\x1b[D");
    try expectCommit(&hg, K.KEY_LEFT, "가");

    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFTCTRL, 1, "");
    try expect(&hg, K.KEY_C, 1, "\x03");
    try expectCommit(&hg, K.KEY_C, "가");
    try expect(&hg, K.KEY_LEFTCTRL, 0, "");

    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFTMETA, 1, "");
    try expect(&hg, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&hg, K.KEY_C, .enter);
    try expectCommit(&hg, K.KEY_C, "가");
    try expect(&hg, K.KEY_LEFTSHIFT, 0, "");
    try expect(&hg, K.KEY_LEFTMETA, 0, "");

    // 검사 29. **한글이 켜져 있어도 copy mode의 `j`는 아래로 간다.**
    // 한글 층이 copy 표보다 **뒤**라는 것이 이 한 줄이고, 순서를 뒤집으면
    // 모드 안에서 커서가 안 움직이고 ㅓ가 조합된다.
    if (!hg.hangul_on) {
        std.debug.print("FAIL: copy mode entry turned hangul off\n", .{});
        return error.HangulLostOnCopyEnter;
    }
    try expectCopy(&hg, K.KEY_J, .down);
    try expectCopy(&hg, K.KEY_ESC, .exit);
    // **모드를 나와도 한/영은 그대로다**(design 결정 5의 직교성).
    if (!hg.hangul_on) {
        std.debug.print("FAIL: leaving copy mode turned hangul off\n", .{});
        return error.HangulLostOnCopyExit;
    }

    // 검사 30. **Backspace가 자모를 하나씩 뺀다.** 마지막 하나가 대조군이다 —
    // 조합이 비고 나면 평소처럼 DEL이 나가야 한다. 그 줄이 없으면 "조합 중이
    // 아닌데도 Backspace를 삼킨다"가 통과하고, 증상은 "셸에서 글자를 못
    // 지운다"라 원인에서 멀다.
    try expectHangul(&hg, K.KEY_G, "", 'ㅎ');
    try expectHangul(&hg, K.KEY_K, "", '하');
    try expectHangul(&hg, K.KEY_S, "", '한');
    try expectHangul(&hg, K.KEY_BACKSPACE, "", '하');
    try expectHangul(&hg, K.KEY_BACKSPACE, "", 'ㅎ');
    try expectHangul(&hg, K.KEY_BACKSPACE, "", null);
    try expect(&hg, K.KEY_BACKSPACE, 1, "\x7f");

    // 검사 31. **한/영을 끄면 조합이 먼저 확정된다.** 이것이
    // "`hangul_buf`가 비지 않았으면 `hangul_on`이 참"이라는 불변식을 세우는
    // 자리다 — 안 확정하면 꺼진 채로 조합이 남아 화면에 글자가 붙박인다.
    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&hg, K.KEY_SPACE, "가", null);
    try expect(&hg, K.KEY_LEFTSHIFT, 0, "");
    if (hg.hangul_on) {
        std.debug.print("FAIL: Shift+Space did not turn hangul off\n", .{});
        return error.ToggleFailed;
    }
    // 껐으니 `r`은 다시 `r`이다.
    try expect(&hg, K.KEY_R, 1, "r");

    std.debug.print("input_test: hangul OK\n", .{});

    // ── HI-M2: 자판이 되돌려 주는 기호 ────────────────────────────────

    // 검사 32. **세벌식은 숫자 열이 자모라 되돌려 줄 자리가 필요하다.**
    // 3-P3에서 `1`은 종성 ㅋ이고, 숫자 `1`은 Shift+M에 있다. 이것이 없으면
    // 3-P3 사용자는 한글 상태에서 숫자를 아예 못 친다.
    var sb: input.State = .{ .hangul_layout = .sebeol_3p3 };
    try expect(&sb, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&sb, K.KEY_SPACE, "", null);
    try expect(&sb, K.KEY_LEFTSHIFT, 0, "");

    // 조합이 비어 있을 때 — 기호만 나간다.
    try expect(&sb, K.KEY_LEFTSHIFT, 1, "");
    try expect(&sb, K.KEY_M, 1, "1");
    try expectCommit(&sb, K.KEY_M, "");
    try expect(&sb, K.KEY_LEFTSHIFT, 0, "");

    // **조합 중이면 음절이 먼저 나간다.** 뒤집히면 셸에 `1가`가 도착한다.
    // `kf`가 3-P3의 `가`이고, `hangul_test`가 같은 글자열을 오토마타 쪽에서
    // 본다 — **여기가 보는 것은 배선이다.**
    try expectHangul(&sb, K.KEY_K, "", 'ㄱ');
    try expectHangul(&sb, K.KEY_F, "", '가');
    try expect(&sb, K.KEY_LEFTSHIFT, 1, "");
    try expect(&sb, K.KEY_M, 1, "1");
    try expectCommit(&sb, K.KEY_M, "가");
    try expectPreedit(&sb, K.KEY_M, null);
    try expect(&sb, K.KEY_LEFTSHIFT, 0, "");

    // 검사 33. **신세벌 P2는 유니코드 기호를 준다.** `nonSyllable`이 `?u8`이
    // 아니라 `?u21`인 이유가 이 한 줄이고, UTF-8 세 바이트가 `seq`에 담겨
    // 나간다.
    var sp: input.State = .{ .hangul_layout = .shin_p2 };
    try expect(&sp, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&sp, K.KEY_SPACE, "", null);
    try expect(&sp, K.KEY_Y, 1, "✕");
    try expect(&sp, K.KEY_LEFTSHIFT, 0, "");

    std.debug.print("input_test: layout symbols OK\n", .{});

    // ── HI-M2: 영문 드보락 ────────────────────────────────────────────

    // 검사 34. **드보락이 라틴 문자를 바꾼다.** 쿼티의 `s` 자리(KEY_S)가
    // 드보락에서는 `o`이고, `z` 자리는 `;`다.
    var dv: input.State = .{ .latin_layout = .dvorak, .hangul_layout = .dubeol };
    try expect(&dv, K.KEY_S, 1, "o");
    try expect(&dv, K.KEY_Z, 1, ";");
    try expect(&dv, K.KEY_R, 1, "p");
    // Shift도 드보락 표를 탄다.
    try expect(&dv, K.KEY_LEFTSHIFT, 1, "");
    try expect(&dv, K.KEY_S, 1, "O");
    try expect(&dv, K.KEY_LEFTSHIFT, 0, "");

    // 검사 35. **그런데 한글 배열은 안 흔들린다**(design 결정 13). 이것이 이
    // 검사의 전부다 — 한글 자판이 쓰는 것은 문자가 아니라 물리 키 위치이고,
    // 그 위치를 부르는 이름이 쿼티 배치의 문자다.
    //
    // KEY_R은 드보락에서 `p`인데, 두벌식에서 ㄱ이 나와야 한다. **틀리면
    // 여기서 ㅔ가 나온다**(두벌식의 `p`) — 증상이 "안 된다"가 아니라 "다른
    // 글자가 나온다"라 원인을 오토마타에서 찾게 되는 자리다.
    try expect(&dv, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&dv, K.KEY_SPACE, "", null);
    try expect(&dv, K.KEY_LEFTSHIFT, 0, "");
    try expectHangul(&dv, K.KEY_R, "", 'ㄱ');
    try expectHangul(&dv, K.KEY_K, "", '가');

    std.debug.print("input_test: dvorak OK\n", .{});

    // ── HI-M3: 한/영 키와 전환 키 설정 ────────────────────────────────

    // 검사 36. **실기의 한/영 키(122)가 전환한다.** 게이트가 이 키를 못
    // 보내므로(HI-M0 실측 1) 이 검사가 그 갈래를 덮는 **유일한** 자리다.
    var hk: input.State = .{ .hangul_layout = .dubeol };
    try expectHangul(&hk, K.KEY_HANGEUL, "", null);
    if (!hk.hangul_on) {
        std.debug.print("FAIL: KEY_HANGEUL did not turn hangul on\n", .{});
        return error.ToggleFailed;
    }
    try expectHangul(&hk, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hk, K.KEY_K, "", '가');
    // **조합 중이던 글자가 확정되고 나간다.** 전환 키 넷이 전부 지켜야 하는
    // 계약이고, 그것을 `toggleHangul` 한 자리로 모아 둔 이유다.
    try expectHangul(&hk, K.KEY_HANGEUL, "가", null);
    if (hk.hangul_on) {
        std.debug.print("FAIL: KEY_HANGEUL did not turn hangul off\n", .{});
        return error.ToggleFailed;
    }

    // 검사 37. **꺼 두면 그 키는 아무 일도 안 한다.** 설정이 실제로 갈래를
    // 끄는지 보는 자리다 — 안 보면 "목록을 파싱만 하고 안 쓰는" 코드가
    // 통과한다.
    var tg_off: input.State = .{
        .hangul_layout = .dubeol,
        .toggles = .{ .capslock_tap = true },
    };
    try expect(&tg_off, K.KEY_HANGEUL, 1, "");
    if (tg_off.hangul_on) {
        std.debug.print("FAIL: KEY_HANGEUL toggled with hangul_key off\n", .{});
        return error.ToggleFailed;
    }
    // **Shift+Space도 꺼졌으니 공백이 PTY로 나간다.** 음성 검사가 아니라
    // **양성** 검사인 것에 뜻이 있다 — 삼키면 빈 문자열이 온다. 이것이
    // HI-M1이 적어 둔 "대가"를 없애는 길이다.
    try expect(&tg_off, K.KEY_LEFTSHIFT, 1, "");
    try expect(&tg_off, K.KEY_SPACE, 1, " ");
    try expect(&tg_off, K.KEY_LEFTSHIFT, 0, "");

    std.debug.print("input_test: toggle keys OK\n", .{});

    std.debug.print("PASS\n", .{});
}
