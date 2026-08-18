const std = @import("std");
const input = @import("input.zig");

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

pub fn main() !void {
    // struct input_event가 @cImport로 제대로 넘어왔는지부터 확인한다.
    std.debug.print("input_event size = {d} (expected 24)\n", .{input.eventSize()});
    if (input.eventSize() != 24) {
        std.debug.print("FAIL: unexpected struct input_event size\n", .{});
        return error.UnexpectedEventSize;
    }

    var state: input.State = .{};

    // "hi" 타이핑: 누를 때만 문자가 나오고, 뗄 때는 안 나온다.
    try expect(&state, 35, 1, "h"); // KEY_H press
    try expect(&state, 35, 0, ""); // KEY_H release
    try expect(&state, 23, 1, "i"); // KEY_I press
    try expect(&state, 23, 0, ""); // KEY_I release

    // Enter는 CR을 보낸다.
    try expect(&state, 28, 1, "\r"); // KEY_ENTER press

    // Shift를 누르면 그 자체는 문자가 없고, 이어지는 키가 대문자가 된다.
    try expect(&state, 42, 1, ""); // KEY_LEFTSHIFT press
    try expect(&state, 35, 1, "H"); // KEY_H press (shifted)
    try expect(&state, 42, 0, ""); // KEY_LEFTSHIFT release
    try expect(&state, 35, 1, "h"); // KEY_H press (unshifted 복귀)

    // 좌우 Shift는 각자 추적된다. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도
    // Shift는 풀리지 않아야 한다 — 손은 아직 왼쪽을 누르고 있다.
    try expect(&state, 42, 1, ""); // LEFTSHIFT press
    try expect(&state, 54, 1, ""); // RIGHTSHIFT press
    try expect(&state, 54, 0, ""); // RIGHTSHIFT release
    try expect(&state, 35, 1, "H"); // 여전히 대문자
    try expect(&state, 42, 0, ""); // LEFTSHIFT release
    try expect(&state, 35, 1, "h"); // 이제 소문자

    // Shift + 숫자 = 기호.
    try expect(&state, 54, 1, ""); // KEY_RIGHTSHIFT press
    try expect(&state, 2, 1, "!"); // KEY_1 press (shifted)
    try expect(&state, 54, 0, ""); // KEY_RIGHTSHIFT release

    // 자동 반복(value=2)도 문자를 만든다. 방향키를 누르고 있으면 계속
    // 움직여야 하므로 이 성질은 오히려 필요하다.
    try expect(&state, 30, 2, "a"); // KEY_A autorepeat

    // 표에 없는 키코드는 조용히 무시한다.
    try expect(&state, 200, 1, "");

    // ── Ctrl 제어 문자 (IP-M0) ──────────────────────────────────────────
    //
    // 규칙은 한 줄이다: Shift를 먼저 적용해 문자를 정한 뒤 `& 0x1F`.
    // ASCII에서 제어 문자 0x00~0x1F는 `@ABC…Z[\]^_`(0x40~0x5F)에서 상위 두
    // 비트를 뗀 것이므로, 마스크가 곧 정의다.

    try expect(&state, 29, 1, ""); // KEY_LEFTCTRL press — 그 자체는 문자 없음
    try expect(&state, 46, 1, "\x03"); // Ctrl+C → SIGINT를 부르는 바이트
    try expect(&state, 32, 1, "\x04"); // Ctrl+D → EOF
    try expect(&state, 44, 1, "\x1a"); // Ctrl+Z → SIGTSTP
    try expect(&state, 43, 1, "\x1c"); // Ctrl+\ → SIGQUIT
    try expect(&state, 26, 1, "\x1b"); // Ctrl+[ → ESC
    try expect(&state, 57, 1, "\x00"); // Ctrl+Space → NUL

    // 마스크가 의미 있는 것은 문자가 0x40~0x7F일 때뿐이다. Ctrl+1에
    // 적용하면 0x31 & 0x1F = 0x11(XON)이 나오는데 아무도 그런 뜻으로 쓰지
    // 않는다. 대상이 아닌 문자는 Ctrl을 무시하고 원래 문자를 보낸다.
    try expect(&state, 2, 1, "1"); // Ctrl+1 → 그냥 '1'

    // Shift가 함께 눌려도 제어 문자는 같다.
    try expect(&state, 42, 1, ""); // LEFTSHIFT press
    try expect(&state, 46, 1, "\x03"); // Ctrl+Shift+C → 여전히 0x03
    // Shift+2는 '@'이고 '@' & 0x1F = 0x00이다.
    try expect(&state, 3, 1, "\x00"); // Ctrl+Shift+2 → NUL
    try expect(&state, 42, 0, ""); // LEFTSHIFT release

    try expect(&state, 29, 0, ""); // KEY_LEFTCTRL release
    try expect(&state, 46, 1, "c"); // Ctrl을 떼면 다시 평문

    // 오른쪽 Ctrl도 같다.
    try expect(&state, 97, 1, ""); // KEY_RIGHTCTRL press
    try expect(&state, 46, 1, "\x03");
    try expect(&state, 97, 0, "");

    // 좌우 Ctrl 각자 추적. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도 안 풀린다.
    try expect(&state, 29, 1, ""); // LEFTCTRL press
    try expect(&state, 97, 1, ""); // RIGHTCTRL press
    try expect(&state, 97, 0, ""); // RIGHTCTRL release
    try expect(&state, 46, 1, "\x03"); // 여전히 Ctrl
    try expect(&state, 29, 0, ""); // LEFTCTRL release
    try expect(&state, 46, 1, "c");

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

    std.debug.print("PASS\n", .{});
}
