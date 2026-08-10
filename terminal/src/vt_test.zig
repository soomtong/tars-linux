const std = @import("std");
const vt = @import("vt.zig");

pub fn main(init: std.process.Init) !void {
    const cells = try vt.parseToCells(
        init.io,
        init.gpa,
        "TARS \xed\x95\x98\xec\x9d\xb4\r\n", // "TARS 하이" (UTF-8) + CRLF
        20,
        5,
    );
    defer init.gpa.free(cells);

    std.debug.print("parsed {d} non-empty cells\n", .{cells.len});
    for (cells) |cell| {
        std.debug.print("  row={d} col={d} codepoint=U+{X}\n", .{ cell.row, cell.col, cell.codepoint });
    }

    if (cells.len == 0) {
        std.debug.print("FAIL: expected non-empty cells\n", .{});
        return error.NoCells;
    }
    // 첫 셀은 'T'(U+0054)여야 한다.
    if (cells[0].codepoint != 'T' or cells[0].row != 0 or cells[0].col != 0) {
        std.debug.print("FAIL: expected first cell to be 'T' at (0,0)\n", .{});
        return error.UnexpectedFirstCell;
    }
    std.debug.print("PASS\n", .{});
}
