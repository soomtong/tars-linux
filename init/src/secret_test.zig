const std = @import("std");
const secret = @import("secret.zig");

/// PW design 판정의 첫 줄 — `Editor`의 규칙을 본다. 실제 tty(termios · `*`가 화면에 나가는 것)는 home 체인이 본다.
///
/// 바이트 열을 먹이고, 찍힌 화면(`*` · `\b \b`를 그대로 이은 글)과 끝난 모양을 돌려준다.
const Outcome = struct {
    screen: []const u8,
    end: enum { done, cancel, eof, open },
    line: []const u8,
    overflow: bool,
};

var screen_buf: [4096]u8 = undefined;
var line_buf: [16]u8 = undefined;

fn run(input: []const u8) Outcome {
    var ed: secret.Editor = .{ .buf = &line_buf };
    var s: usize = 0;
    for (input) |b| {
        switch (ed.feed(b)) {
            .none => {},
            .star => {
                screen_buf[s] = '*';
                s += 1;
            },
            .erase => |k| for (0..k) |_| {
                @memcpy(screen_buf[s..][0..3], "\x08 \x08");
                s += 3;
            },
            .done => return .{ .screen = screen_buf[0..s], .end = .done, .line = ed.line(), .overflow = ed.overflow },
            .cancel => return .{ .screen = screen_buf[0..s], .end = .cancel, .line = ed.line(), .overflow = ed.overflow },
            .eof => return .{ .screen = screen_buf[0..s], .end = .eof, .line = ed.line(), .overflow = ed.overflow },
        }
    }
    return .{ .screen = screen_buf[0..s], .end = .open, .line = ed.line(), .overflow = ed.overflow };
}

fn expect(name: []const u8, input: []const u8, screen: []const u8, end: @TypeOf(@as(Outcome, undefined).end), line: []const u8, overflow: bool) !void {
    const got = run(input);
    if (!std.mem.eql(u8, got.screen, screen) or got.end != end or !std.mem.eql(u8, got.line, line) or got.overflow != overflow) {
        std.debug.print(
            "FAIL {s}: screen {any} end {s} line '{s}' overflow {} — want screen {any} end {s} line '{s}' overflow {}\n",
            .{ name, got.screen, @tagName(got.end), got.line, got.overflow, screen, @tagName(end), line, overflow },
        );
        return error.SecretEditor;
    }
}

const BS = "\x08 \x08";

/// `s`를 `n`번 이은 글. Zig 0.17에는 배열 반복 연산자가 없다.
fn rep(comptime s: []const u8, comptime n: usize) []const u8 {
    comptime var out: []const u8 = "";
    inline for (0..n) |_| out = out ++ s;
    return out;
}

pub fn main() !void {
    // 1. 글자마다 `*` 하나, Enter에서 끝. `\r`도 Enter다.
    try expect("plain", "abc\n", "***", .done, "abc", false);
    try expect("cr", "ab\r", "**", .done, "ab", false);
    // 2. 빈 줄은 빈 값이다(설치기의 "기본값"이 이것을 쓴다).
    try expect("empty", "\n", "", .done, "", false);
    // 3. UTF-8 한 글자는 `*` 하나 — "한"은 세 바이트다. Backspace는 그 세 바이트를 함께 뺀다.
    try expect("hangul", "a\xed\x95\x9c\n", "**", .done, "a\xed\x95\x9c", false);
    try expect("hangul-bs", "a\xed\x95\x9c\x7f\n", "**" ++ BS, .done, "a", false);
    // 4. Backspace(0x7f · 0x08)는 한 글자를 빼고 `\b \b`. home 체인이 치는 모양이 이것이다.
    try expect("bs", "hp-secret-1X\x7f\n", "************" ++ BS, .done, "hp-secret-1", false);
    try expect("ctrl-h", "ab\x08c\n", "**" ++ BS ++ "*", .done, "ac", false);
    // 5. 빈 칸의 Backspace는 아무것도 안 한다.
    try expect("bs-empty", "\x7f\x7fa\n", "*", .done, "a", false);
    // 6. Ctrl+U는 다 지운다.
    try expect("ctrl-u", "abc\x15d\n", "***" ++ BS ++ BS ++ BS ++ "*", .done, "d", false);
    // 7. Ctrl+C는 언제든 취소, Ctrl+D는 빈 칸에서만 EOF.
    try expect("ctrl-c", "ab\x03", "**", .cancel, "ab", false);
    try expect("ctrl-d-empty", "\x04", "", .eof, "", false);
    try expect("ctrl-d-typed", "a\x04b\n", "**", .done, "ab", false);
    // 8. 화살표(ESC [ D) · SS3(ESC O A)는 삼킨다. 다른 제어 바이트(Tab)도 무시한다.
    try expect("arrow", "a\x1b[Db\x1bOA\tc\n", "***", .done, "abc", false);
    try expect("csi-param", "a\x1b[1;5Cb\n", "**", .done, "ab", false);
    // 9. buf(16)보다 길면 `*`는 계속 찍고 Enter에서 넘침으로 끝난다. Backspace로는 되돌아오지 않고 Ctrl+U는 새로 시작한다.
    try expect("overflow", "0123456789abcdefg\n", comptime rep("*", 17), .done, "0123456789abcdef", true);
    try expect("overflow-bs", "0123456789abcdefg\x7f\n", comptime rep("*", 17) ++ BS, .done, "0123456789abcdef", true);
    try expect("overflow-ctrl-u", "0123456789abcdefg\x15ok\n", comptime rep("*", 17) ++ rep(BS, 17) ++ "**", .done, "ok", false);
    std.debug.print("secret_test: a star per character, backspace takes one UTF-8 character, Ctrl+C/D/U and arrows behave\n", .{});
}
