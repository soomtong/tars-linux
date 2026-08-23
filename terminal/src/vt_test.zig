const std = @import("std");
const vt = @import("vt.zig");

pub fn main(init: std.process.Init) !void {
    const screen = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer screen.deinit();

    var buf: [100]vt.CellGlyph = undefined;

    // 1차: "TARS 하이" — TF-M2와 동일한 검증.
    screen.feed("TARS \xed\x95\x98\xec\x9d\xb4\r\n");
    const first = try screen.cells(&buf);
    std.debug.print("after 1st feed: {d} cells\n", .{first.len});
    if (first.len == 0) return error.NoCells;
    if (first[0].codepoint != 'T' or first[0].row != 0 or first[0].col != 0) {
        std.debug.print("FAIL: expected first cell 'T' at (0,0)\n", .{});
        return error.UnexpectedFirstCell;
    }

    // 2차: 두 번째 조각을 먹인다. **1차 내용이 살아 있어야 한다** —
    // 이게 TF-M3에서 새로 필요해진 성질이다.
    screen.feed("OK\r\n");
    const second = try screen.cells(&buf);
    std.debug.print("after 2nd feed: {d} cells\n", .{second.len});
    for (second) |cell| {
        std.debug.print("  row={d} col={d} codepoint=U+{X}\n", .{ cell.row, cell.col, cell.codepoint });
    }
    if (second.len <= first.len) {
        std.debug.print("FAIL: 2nd feed should ADD cells, not replace them\n", .{});
        return error.StateNotRetained;
    }
    if (second[0].codepoint != 'T') {
        std.debug.print("FAIL: 1st feed content was lost\n", .{});
        return error.StateNotRetained;
    }

    // 이스케이프 시퀀스가 조각 경계에서 잘려도 파서 상태가 이어지는지 확인.
    // "\x1b[" + "2J"는 합쳐야 화면 지우기(ED)가 된다.
    screen.feed("\x1b[");
    screen.feed("2J");
    const third = try screen.cells(&buf);
    std.debug.print("after split escape (clear): {d} cells\n", .{third.len});
    // TR-M0 전까지 이 단언은 `third.len != 0`이었다. 결정 3 뒤로는 **커서
    // 셀 하나가 남는다** — 글자는 없지만 색이 반전되어 기본 배경과 다르기
    // 때문이다. 회귀가 아니라 의도한 결과이고, 그래서 "글자가 하나도
    // 안 남았는가"로 조건을 옮긴다.
    if (third.len != 1) {
        std.debug.print("FAIL: expected only the cursor cell to remain\n", .{});
        return error.SplitEscapeNotHandled;
    }
    if (third[0].codepoint != 0) {
        std.debug.print("FAIL: a glyph survived the clear (cp={d})\n", .{third[0].codepoint});
        return error.SplitEscapeNotHandled;
    }

    // ── TR-M0: 색 ─────────────────────────────────────────────────────
    //
    // 기대값은 plan을 쓰면서 컨테이너에서 직접 재 둔 것이다. 팔레트가 xterm
    // 고전값이 아니라는 것이 요점이다 — 빨강이 #CD0000이 아니라 #CC6666이다.
    screen.feed("\x1b[2J\x1b[H");
    screen.feed("A\x1b[31mB\x1b[0m\x1b[41mC\x1b[0m\x1b[1;31mD\x1b[0m\x1b[7mE\x1b[0m\x1b[38;2;18;52;86mF\x1b[0mG");
    const styled = try screen.cells(&buf);

    const Want = struct { cp: u32, fg: u32, bg: u32, what: []const u8 };
    const wants = [_]Want{
        .{ .cp = 'A', .fg = 0xFFFFFF, .bg = 0x102030, .what = "스타일을 가진 적 없는 셀" },
        .{ .cp = 'B', .fg = 0xCC6666, .bg = 0x102030, .what = "SGR 31 빨강 전경" },
        .{ .cp = 'C', .fg = 0xFFFFFF, .bg = 0xCC6666, .what = "SGR 41 빨강 배경" },
        .{ .cp = 'D', .fg = 0xD54E53, .bg = 0x102030, .what = "SGR 1;31 bold는 밝게" },
        .{ .cp = 'E', .fg = 0x102030, .bg = 0xFFFFFF, .what = "SGR 7 inverse는 맞바꾼다" },
        .{ .cp = 'F', .fg = 0x123456, .bg = 0x102030, .what = "truecolor" },
        // A와 다른 것을 본다. A는 스타일을 가진 적이 없고, G는 **가졌다가
        // SGR 0으로 되돌아온** 셀이다. 리셋이 고장나면 A는 멀쩡한데 G만
        // 틀린다.
        .{ .cp = 'G', .fg = 0xFFFFFF, .bg = 0x102030, .what = "SGR 0 뒤의 셀" },
    };

    for (wants) |want| {
        var found = false;
        for (styled) |cell| {
            if (cell.codepoint != want.cp) continue;
            found = true;
            if (cell.fg != want.fg or cell.bg != want.bg) {
                std.debug.print(
                    "FAIL: {s}: '{c}' fg=#{X:0>6} bg=#{X:0>6} (expected fg=#{X:0>6} bg=#{X:0>6})\n",
                    .{ want.what, @as(u8, @intCast(want.cp)), cell.fg, cell.bg, want.fg, want.bg },
                );
                return error.WrongColor;
            }
            std.debug.print("vt_test: {s} OK\n", .{want.what});
            break;
        }
        if (!found) {
            std.debug.print("FAIL: {s}: '{c}' 셀이 없다\n", .{ want.what, @as(u8, @intCast(want.cp)) });
            return error.CellMissing;
        }
    }

    std.debug.print("PASS\n", .{});
}
