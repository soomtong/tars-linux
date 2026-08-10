const std = @import("std");

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

pub const Glyph = struct {
    codepoint: u32,
    width: u32,
    height: u32,
    cell_width: u32,
    bitmap: ?[*]u8,
};

pub const GlyphCache = struct {
    glyphs: []Glyph,
};

fn cellWidth(codepoint: u32) u32 {
    // 8x4x4-fonts는 라틴 8px, 한글 16px 고정 grid다(design doc 4번 결정).
    return if (codepoint > 0x7F) 16 else 8;
}

pub fn build(allocator: std.mem.Allocator, font_data: []const u8, codepoints: []const u32) !GlyphCache {
    var font: stb.stbtt_fontinfo = undefined;
    if (stb.stbtt_InitFont(&font, font_data.ptr, 0) == 0) {
        return error.FontInitFailed;
    }

    const glyphs = try allocator.alloc(Glyph, codepoints.len);
    const pixel_height: f32 = 16.0;
    const scale = stb.stbtt_ScaleForPixelHeight(&font, pixel_height);

    for (codepoints, 0..) |codepoint, i| {
        var w: c_int = 0;
        var h: c_int = 0;
        var xoff: c_int = 0;
        var yoff: c_int = 0;
        const bitmap = stb.stbtt_GetCodepointBitmap(
            &font,
            scale,
            scale,
            @intCast(codepoint),
            &w,
            &h,
            &xoff,
            &yoff,
        );
        // 공백처럼 잉크가 없는 글자는 stb가 0x0 비트맵(bitmap == null)을
        // 돌려준다 — 에러가 아니라 "그릴 게 없다"는 정상 결과다.
        if (bitmap == null and w * h != 0) return error.RasterizeFailed;

        glyphs[i] = Glyph{
            .codepoint = codepoint,
            .width = @intCast(w),
            .height = @intCast(h),
            .cell_width = cellWidth(codepoint),
            .bitmap = bitmap,
        };
    }

    return GlyphCache{ .glyphs = glyphs };
}

pub fn find(cache: GlyphCache, codepoint: u32) ?Glyph {
    for (cache.glyphs) |glyph| {
        if (glyph.codepoint == codepoint) return glyph;
    }
    return null;
}
