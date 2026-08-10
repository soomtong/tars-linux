const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
};

/// bytes를 libghostty-vt로 파싱해(ANSI 이스케이프 포함) 빈 칸이 아닌 셀만
/// 왼쪽-위부터 순서대로 뽑아 반환한다. 색상/스타일은 읽지 않는다(TF-M2
/// 범위 밖 — design 결정 참고).
pub fn parseToCells(
    io: std.Io,
    alloc: std.mem.Allocator,
    bytes: []const u8,
    cols: u16,
    rows: u16,
) ![]CellGlyph {
    var t: ghostty_vt.Terminal = try .init(io, alloc, .{ .cols = cols, .rows = rows });
    defer t.deinit(alloc);

    var stream = t.vtStream();
    defer stream.deinit();
    stream.nextSlice(bytes);

    var state: ghostty_vt.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    var out: std.ArrayList(CellGlyph) = .empty;
    defer out.deinit(alloc);

    const row_data = state.row_data.slice();
    const row_cells = row_data.items(.cells);
    for (0..state.rows) |y| {
        const cells_slice = row_cells[y].slice();
        const raws = cells_slice.items(.raw);
        for (0..state.cols) |x| {
            const cp = raws[x].codepoint();
            if (cp == 0) continue;
            try out.append(alloc, .{
                .codepoint = @intCast(cp),
                .col = @intCast(x),
                .row = @intCast(y),
            });
        }
    }

    return out.toOwnedSlice(alloc);
}
