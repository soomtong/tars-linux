const std = @import("std");
const input = @import("input.zig");

fn expectByte(state: *input.State, code: u16, value: i32, want: ?u8) !void {
    const got = state.handleKey(code, value);
    if (got == null and want == null) return;
    if (got != null and want != null and got.? == want.?) return;
    std.debug.print(
        "FAIL: code={d} value={d} -> got={?d}, want={?d}\n",
        .{ code, value, got, want },
    );
    return error.UnexpectedByte;
}

pub fn main() !void {
    // struct input_event가 translate-c로 제대로 넘어왔는지부터 확인한다
    // (이 plan의 "가설 1").
    std.debug.print("input_event size = {d} (expected 24)\n", .{input.eventSize()});
    if (input.eventSize() != 24) {
        std.debug.print("FAIL: unexpected struct input_event size\n", .{});
        return error.UnexpectedEventSize;
    }

    var state: input.State = .{};

    // "hi" 타이핑: 누를 때만 문자가 나오고, 뗄 때는 안 나온다.
    try expectByte(&state, 35, 1, 'h'); // KEY_H press
    try expectByte(&state, 35, 0, null); // KEY_H release
    try expectByte(&state, 23, 1, 'i'); // KEY_I press
    try expectByte(&state, 23, 0, null); // KEY_I release

    // Enter는 CR을 보낸다.
    try expectByte(&state, 28, 1, '\r'); // KEY_ENTER press

    // Shift를 누르면 그 자체는 문자가 없고, 이어지는 키가 대문자가 된다.
    try expectByte(&state, 42, 1, null); // KEY_LEFTSHIFT press
    try expectByte(&state, 35, 1, 'H'); // KEY_H press (shifted)
    try expectByte(&state, 42, 0, null); // KEY_LEFTSHIFT release
    try expectByte(&state, 35, 1, 'h'); // KEY_H press (unshifted 복귀)

    // Shift + 숫자 = 기호.
    try expectByte(&state, 54, 1, null); // KEY_RIGHTSHIFT press
    try expectByte(&state, 2, 1, '!'); // KEY_1 press (shifted)
    try expectByte(&state, 54, 0, null); // KEY_RIGHTSHIFT release

    // 자동 반복(value=2)도 문자를 만든다.
    try expectByte(&state, 30, 2, 'a'); // KEY_A autorepeat

    // 표에 없는 키코드는 조용히 무시한다.
    try expectByte(&state, 200, 1, null);

    std.debug.print("PASS\n", .{});
}
