const std = @import("std");
const input = @import("input.zig");

/// IP-M0부터 handleKey는 바이트 **하나**가 아니라 바이트 **열**을 돌려준다.
/// "보낼 것 없음"은 null이 아니라 빈 슬라이스다.
fn expect(state: *input.State, code: u16, value: i32, want: []const u8) !void {
    const got = state.handleKey(code, value);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print(
        "FAIL: code={d} value={d} -> got={any}, want={any}\n",
        .{ code, value, got, want },
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

    std.debug.print("PASS\n", .{});
}
