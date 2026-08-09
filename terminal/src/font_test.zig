const std = @import("std");
const font = @import("font.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const file = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/Hanme_8x4x4.ttf",
        allocator,
        .unlimited,
    );

    // "TARS 하이"
    const codepoints = [_]u32{ 'T', 'A', 'R', 'S', ' ', 0xD558, 0xC774 };
    const cache = try font.build(allocator, file, &codepoints);

    for (cache.glyphs) |glyph| {
        if (glyph.bitmap) |bitmap| {
            var nonzero: usize = 0;
            var idx: usize = 0;
            while (idx < glyph.width * glyph.height) : (idx += 1) {
                if (bitmap[idx] > 0) nonzero += 1;
            }
            std.debug.print(
                "codepoint U+{X}: {d}x{d} pixels, cell_width={d}, {d} non-zero\n",
                .{ glyph.codepoint, glyph.width, glyph.height, glyph.cell_width, nonzero },
            );
        } else {
            std.debug.print(
                "codepoint U+{X}: no bitmap (whitespace), cell_width={d}\n",
                .{ glyph.codepoint, glyph.cell_width },
            );
        }
    }
}
