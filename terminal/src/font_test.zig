const std = @import("std");
const font = @import("font.zig");

/// 폰트 캐시의 검사. 부팅을 안 쓰고 도는 자리다 — 래스터라이저는 게스트
/// 하드웨어와 상관이 없다.
///
/// 기대값은 plan을 쓰면서 컨테이너에서 직접 재 둔 것이다. 짐작으로 적으면
/// 틀리는 자리가 둘이다: **`yoff`가 글자마다 다르고**(A는 -14, 한은 -16),
/// **폰트에 없는 글자는 에러가 아니라 빈 비트맵으로 온다.**
pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const file = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/Hanme_8x4x4.ttf",
        allocator,
        .unlimited,
    );

    var cache = try font.Cache.init(allocator, file);
    defer cache.deinit();

    // ── 1. 굽지 않은 캐시는 비어 있다 ─────────────────────────────────
    if (cache.count() != 0) {
        std.debug.print("FAIL: 새 캐시에 글리프가 {d}개 있다\n", .{cache.count()});
        return error.CacheNotEmpty;
    }

    // ── 2. 글자마다 기대하는 모양 ─────────────────────────────────────
    //
    // y_offset은 stb의 yoff에 ascent(16px)를 더한 값이다. 셀 위쪽 모서리에서
    // 몇 픽셀 아래에 찍는가를 뜻한다. 'g'가 'A'보다 3픽셀 아래인 것이
    // 디센더이고, 이 값을 버리면 그 디센더가 사라진다.
    const Want = struct {
        cp: u32,
        w: u32,
        h: u32,
        cell_width: u32,
        x_offset: i32,
        y_offset: i32,
        what: []const u8,
    };
    const wants = [_]Want{
        .{ .cp = 'A', .w = 7, .h = 10, .cell_width = 8, .x_offset = 0, .y_offset = 2, .what = "라틴 대문자" },
        .{ .cp = 'g', .w = 7, .h = 10, .cell_width = 8, .x_offset = 0, .y_offset = 5, .what = "디센더가 아래로 내려간다" },
        .{ .cp = 0xD55C, .w = 15, .h = 15, .cell_width = 16, .x_offset = 1, .y_offset = 0, .what = "한글 '한'은 폭 2칸" },
        .{ .cp = 0xAC00, .w = 13, .h = 13, .cell_width = 16, .x_offset = 3, .y_offset = 1, .what = "한글 '가'" },
        // 0x7F를 넘지만 폭이 1칸이다. cellWidth의 옛 규칙이 틀렸던 자리다.
        .{ .cp = 0x00E9, .w = 7, .h = 10, .cell_width = 8, .x_offset = 1, .y_offset = 2, .what = "é는 0x7F를 넘어도 1칸" },
    };

    for (wants) |want| {
        const glyph = try cache.find(want.cp);
        if (glyph.width != want.w or glyph.height != want.h or
            glyph.cell_width != want.cell_width or
            glyph.x_offset != want.x_offset or glyph.y_offset != want.y_offset)
        {
            std.debug.print(
                "FAIL: {s}: U+{X} {d}x{d} cell_width={d} x_offset={d} y_offset={d}" ++
                    " (expected {d}x{d} cell_width={d} x_offset={d} y_offset={d})\n",
                .{
                    want.what,
                    want.cp,
                    glyph.width,
                    glyph.height,
                    glyph.cell_width,
                    glyph.x_offset,
                    glyph.y_offset,
                    want.w,
                    want.h,
                    want.cell_width,
                    want.x_offset,
                    want.y_offset,
                },
            );
            return error.WrongGlyphMetrics;
        }
        if (glyph.bitmap == null) {
            std.debug.print("FAIL: {s}: U+{X}에 비트맵이 없다\n", .{ want.what, want.cp });
            return error.NoBitmap;
        }
        std.debug.print("font_test: {s} OK\n", .{want.what});
    }

    // ── 3. 글리프가 셀 밖으로 새지 않는다 ─────────────────────────────
    //
    // 오프셋을 반영한 뒤에 이것이 지켜지지 않으면 setPixel이 범위 검사를
    // 하지 않으므로(drm.zig:128) 게스트가 죽는다. 폰트 전체를 훑는다.
    var cp: u32 = 0xAC00;
    var worst_bottom: i32 = 0;
    while (cp <= 0xD7A3) : (cp += 1) {
        const glyph = try cache.find(cp);
        const bottom = glyph.y_offset + @as(i32, @intCast(glyph.height));
        if (bottom > worst_bottom) worst_bottom = bottom;
        if (glyph.y_offset < 0 or bottom > 16 or
            glyph.x_offset < 0 or
            glyph.x_offset + @as(i32, @intCast(glyph.width)) > 16)
        {
            std.debug.print(
                "FAIL: U+{X}가 셀 밖으로 샌다: x_offset={d} w={d} y_offset={d} h={d}\n",
                .{ cp, glyph.x_offset, glyph.width, glyph.y_offset, glyph.height },
            );
            return error.GlyphOutsideCell;
        }
    }
    std.debug.print(
        "font_test: 한글 음절 11172자가 전부 16x16 셀 안에 들어간다 (가장 아래가 {d}행) OK\n",
        .{worst_bottom},
    );

    // ── 4. 폰트에 없는 글자는 에러가 아니다 ───────────────────────────
    //
    // 이 폰트에는 한자도 호환 자모(ㄱ)도 없다. stb는 glyph_index 0에
    // 0x0 비트맵을 준다 — 공백과 똑같은 모양이라 구분되지 않고, 구분할
    // 이유도 없다. **캐시에는 들어가야 한다.** 안 넣으면 그 글자가 화면에
    // 남아 있는 동안 프레임마다 다시 굽는다.
    const before = cache.count();
    const missing = try cache.find(0x4E00);
    if (missing.bitmap != null) {
        std.debug.print("FAIL: 폰트에 없는 U+4E00에 비트맵이 있다\n", .{});
        return error.UnexpectedBitmap;
    }
    if (cache.count() != before + 1) {
        std.debug.print("FAIL: 폰트에 없는 글자가 캐시에 안 들어갔다\n", .{});
        return error.MissingGlyphNotCached;
    }
    std.debug.print("font_test: 폰트에 없는 글자도 캐시에 들어간다 OK\n", .{});

    // ── 5. 두 번째 요청은 캐시에서 나온다 ─────────────────────────────
    const count_before = cache.count();
    _ = try cache.find('A');
    if (cache.count() != count_before) {
        std.debug.print("FAIL: 이미 구운 글자를 다시 구웠다\n", .{});
        return error.CacheMiss;
    }
    std.debug.print("font_test: 같은 글자를 두 번 찾아도 한 번만 굽는다 OK\n", .{});

    // ── 6. 전부 구운 캐시의 크기 (design 위험 3) ──────────────────────
    //
    // 11172자를 위에서 전부 구웠으므로 이 값이 **최악의 경우**다.
    std.debug.print(
        "font_test: 한글 전체를 구운 캐시 = {d} glyph(s), {d} bitmap bytes ({d:.2} MB)\n",
        .{
            cache.count(),
            cache.bitmap_bytes,
            @as(f64, @floatFromInt(cache.bitmap_bytes)) / 1048576.0,
        },
    );

    std.debug.print("PASS\n", .{});
}
