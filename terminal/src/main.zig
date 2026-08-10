const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");
const pty = @import("pty.zig");
const vt = @import("vt.zig");

const c = @cImport({
    @cInclude("unistd.h");
});

const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const GRID_COLS: u16 = 20;
const GRID_ROWS: u16 = 5;
const ROW_HEIGHT: u32 = 16;

fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32) void {
    const bitmap = glyph.bitmap orelse return;
    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(x + col, y + row, TEXT_COLOR);
            }
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    std.debug.print("terminal: filled framebuffer with background\n", .{});

    const font_data = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/Hanme_8x4x4.ttf",
        allocator,
        .unlimited,
    );

    // "TARS 하이" — PTY로 fish에게 시킬 명령이 그대로 만들어낼 출력과
    // 동일한 코드포인트 집합을 미리 래스터라이징해둔다.
    const codepoints = [_]u32{ 'T', 'A', 'R', 'S', ' ', 0xD558, 0xC774 };
    const cache = try font.build(allocator, font_data, &codepoints);

    const session = try pty.spawnFish("echo \"TARS 하이\"");
    var pty_buf: [4096]u8 = undefined;
    const pty_output = pty.readAll(session.master_fd, &pty_buf);
    std.debug.print("terminal: read {d} bytes from pty\n", .{pty_output.len});

    const cells = try vt.parseToCells(init.io, allocator, pty_output, GRID_COLS, GRID_ROWS);

    var x: u32 = GRID_X;
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            x = GRID_X;
            last_row = cell.row;
        }
        if (font.find(cache, cell.codepoint)) |glyph| {
            const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
            drawGlyph(fb, glyph, x, y);
            x += glyph.cell_width;
        }
    }
    std.debug.print("terminal: rendered {d} cells from pty output\n", .{cells.len});
    try fb.present();

    while (true) {
        _ = c.sleep(1);
    }
}
