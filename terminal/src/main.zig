const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");

const c = @cImport({
    @cInclude("unistd.h");
});

const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const TEXT_X: u32 = 20;
const TEXT_Y: u32 = 20;

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

    // "TARS 하이"
    const codepoints = [_]u32{ 'T', 'A', 'R', 'S', ' ', 0xD558, 0xC774 };
    const cache = try font.build(allocator, font_data, &codepoints);

    var x: u32 = TEXT_X;
    for (cache.glyphs) |glyph| {
        drawGlyph(fb, glyph, x, TEXT_Y);
        x += glyph.cell_width;
    }
    std.debug.print("terminal: rendered test string\n", .{});
    try fb.present();

    while (true) {
        _ = c.sleep(1);
    }
}
