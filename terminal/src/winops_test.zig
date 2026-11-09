const std = @import("std");
const winops = @import("winops.zig");

// `CSI 10 ; Ps t` 훑기를 호스트에서 본다(FU-M1). 화면에 닿는 것은 fullscreen 체인이 본다.
// 위험은 다른 프로그램에서 전체 화면이 저절로 켜지는 것이다(design 위험 3) — 비슷한 시퀀스 · 잘린 입력 · 끼어드는 바이트를 덮는다.

var checks: usize = 0;

/// 새 Scanner에 `input`을 한 덩이로 먹인다.
fn expectOnce(input: []const u8, start: bool, want: bool) !void {
    checks += 1;
    var s: winops.Scanner = .{};
    const got = s.feed(input, start);
    if (got == want) return;
    std.debug.print("FAIL: feed({any}, {}) = {}, want {}\n", .{ input, start, got, want });
    return error.WrongState;
}

/// `input`을 모든 자리에서 둘로 나눠 두 번 먹인다 — read 경계에서 잘린 시퀀스.
fn expectSplit(input: []const u8, start: bool, want: bool) !void {
    for (0..input.len + 1) |cut| {
        checks += 1;
        var s: winops.Scanner = .{};
        const got = s.feed(input[cut..], s.feed(input[0..cut], start));
        if (got == want) continue;
        std.debug.print("FAIL: split at {d} of {any}: {}, want {}\n", .{ cut, input, got, want });
        return error.WrongState;
    }
    // 한 바이트씩.
    checks += 1;
    var s: winops.Scanner = .{};
    var on = start;
    for (input) |b| on = s.feed(&.{b}, on);
    if (on != want) {
        std.debug.print("FAIL: byte by byte {any}: {}, want {}\n", .{ input, on, want });
        return error.WrongState;
    }
}

pub fn main() !void {
    // 켜기 · 끄기 · 바꾸기 · 빈 Ps.
    try expectOnce("\x1b[10;1t", false, true);
    try expectOnce("\x1b[10;0t", true, false);
    try expectOnce("\x1b[10;2t", false, true);
    try expectOnce("\x1b[10;2t", true, false);
    try expectOnce("\x1b[10;2t\x1b[10;2t", false, false);
    try expectOnce("\x1b[10;t", true, false);
    try expectOnce("\x1b[10;1t", true, true); // 같은 상태로의 요청
    try expectOnce("\x1b[010;01t", false, true); // 앞자리 0은 값이 같다
    std.debug.print("winops_test: requests ok\n", .{});

    // 무시 — 꺼진 상태에서 켜지면 안 되고, 켜진 상태에서 꺼지면 안 된다.
    const ignored = [_][]const u8{
        "\x1b[10t", // 칸 하나
        "\x1b[1;10t", // 첫 칸이 10이 아니다
        "\x1b[10;1q", // 다른 끝 바이트
        "\x1b[10;1;0t", // 칸 셋
        "\x1b[?10;1t", // 개인 표지
        "\x1b[>10;1t",
        "\x1b[10;1 t", // 중간 바이트
        "\x1b[10:1t", // 부분 매개변수
        "\x1b[10;3t", // 모르는 Ps
        "\x1b[;1t", // 첫 칸이 비었다
        "\x1b[99999;1t", // 값이 크다
        "\x1b[10;99999999999t",
        "\x1b]10;1t\x07", // OSC — CSI가 아니다
        "\x1bP10;1t\x1b\\", // DCS
        "10;1t", // ESC 없음
        "[10;1t",
        "\x9b10;1t", // 8비트 CSI는 보지 않는다
        "\x1b[10;\x181t", // CAN이 버렸다
        "\x1b[10;\x1a1t", // SUB
        "\x1b[10;\xc3\xa91t", // UTF-8 글자가 끼었다
    };
    for (ignored) |in| {
        try expectOnce(in, false, false);
        try expectOnce(in, true, true);
    }
    std.debug.print("winops_test: {d} look-alikes ignored\n", .{ignored.len});

    // 끼어듦 — ESC는 새로 열고, C0는 시퀀스를 안 끊는다.
    try expectOnce("\x1b[10\x1b[10;1t", false, true);
    try expectOnce("\x1b[?1049h\x1b[10;1t", false, true); // 앞의 다른 시퀀스가 끝난 뒤
    try expectOnce("\x1b[?10;1t\x1b[10;1t", false, true); // skip에서 끝 바이트로 돌아온 뒤
    try expectOnce("\x1b[10;\n1t", false, true);
    try expectOnce("\x1b[10;1tabc\x1b[10;0t", false, false);
    try expectOnce("abc\x1b[10;1tdef", false, true);
    std.debug.print("winops_test: interleaving ok\n", .{});

    // 잘림 — 모든 자리에서 둘로, 그리고 한 바이트씩.
    try expectSplit("\x1b[10;1t", false, true);
    try expectSplit("\x1b[10;0t", true, false);
    try expectSplit("hello \x1b[10;2t world", false, true);
    try expectSplit("\x1b[1;10t", false, false);
    try expectSplit("\x1b[10;1tx\x1b[10;0t", false, false);
    std.debug.print("winops_test: split reads ok\n", .{});

    // 잘린 채 남은 상태가 다음 덩이를 오해하지 않는다 — `ESC [ 1` 뒤에 `0;1t`가 오면 10이다(이어 읽기),
    // 그러나 `ESC [ 1 q` 뒤의 `0;1t`는 ground의 글자다.
    {
        checks += 1;
        var s: winops.Scanner = .{};
        var on = s.feed("\x1b[1q", false);
        on = s.feed("0;1t", on);
        if (on) return error.WrongState;
    }
    std.debug.print("winops_test: {d} checks, all passed\n", .{checks});
}
