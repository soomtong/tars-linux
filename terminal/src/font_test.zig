const std = @import("std");
const font = @import("font.zig");

/// 폰트 캐시의 검사. 부팅을 안 쓰고 도는 자리다 — 래스터라이저는 게스트
/// 하드웨어와 상관이 없다.
///
/// 기대값은 컨테이너에서 직접 재 둔 것이다. 짐작으로 적으면 틀리는 자리가
/// 둘이다: **`yoff`가 글자마다 다르고**(A는 -10, 한은 -12), **그릴 것이
/// 없는 글자는 에러가 아니라 빈 비트맵으로 온다.**
///
/// **이 파일의 기대값은 unifont 17.0.03의 실측이다.** vendor_fonts.sh가 그
/// 버전에 고정하고 sha256으로 확인한다. 폰트를 바꾸면 다시 재야 하는 곳이
/// 기대값 표만이 아니다 — 아래 4번 검사의 표본도 폰트를 탄다.
pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const file = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/unifont.otf",
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
    // y_offset은 stb의 yoff에 ascent(unifont는 14px)를 더한 값이다. 셀 위쪽
    // 모서리에서 몇 픽셀 아래에 찍는가를 뜻한다. 'g'의 아래끝이 5+11=16이라
    // baseline인 14보다 2픽셀 더 내려가는데 그것이 디센더이고, 이 값을
    // 버리면 그 디센더가 사라진다.
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
        .{ .cp = 'A', .w = 6, .h = 10, .cell_width = 8, .x_offset = 1, .y_offset = 4, .what = "라틴 대문자" },
        .{ .cp = 'g', .w = 6, .h = 11, .cell_width = 8, .x_offset = 1, .y_offset = 5, .what = "디센더가 아래로 내려간다" },
        .{ .cp = 0xD55C, .w = 15, .h = 14, .cell_width = 16, .x_offset = 1, .y_offset = 2, .what = "한글 '한'은 폭 2칸" },
        .{ .cp = 0xAC00, .w = 14, .h = 14, .cell_width = 16, .x_offset = 2, .y_offset = 2, .what = "한글 '가'" },
        // 0x7F를 넘지만 폭이 1칸이다. cellWidth의 옛 규칙이 틀렸던 자리다.
        .{ .cp = 0x00E9, .w = 6, .h = 12, .cell_width = 8, .x_offset = 1, .y_offset = 2, .what = "é는 0x7F를 넘어도 1칸" },
        // **겹받침 호환 자모도 두 칸이다**(HI-M2). 종성만 있는 조합 상태를
        // 그리기로 정한 근거가 이 두 줄이다 — 세벌식은 종성 전용 키가 있어서
        // 그 상태를 만들고, `JONG` 표의 값이 전부 호환 자모라 겹받침까지
        // 코드포인트 하나로 그려진다. **폭이 16이라는 것이 요점이다**:
        // 조합하는 내내 폭이 안 바뀐다는 HI-M0 실측 3의 전제가 여기까지 선다.
        //
        // 폭이 다른 둘을 고른 이유는 표가 한 줄 밀렸을 때 잡히게 하기
        // 위해서다(ㄳ 12픽셀, ㄺ 11픽셀).
        .{ .cp = 0x3133, .w = 12, .h = 9, .cell_width = 16, .x_offset = 3, .y_offset = 4, .what = "겹받침 ㄳ도 두 칸" },
        .{ .cp = 0x313A, .w = 11, .h = 9, .cell_width = 16, .x_offset = 3, .y_offset = 4, .what = "겹받침 ㄺ도 두 칸" },
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
    //
    // **unifont는 여유가 0이다.** 가장 아래가 정확히 16행이라 셀을 꽉 채운다
    // (Hanme은 15였다). ascent가 14px이고 descent가 2px이라 16x16 격자에
    // 정확히 맞아떨어지는 폰트이기 때문이고, 그래서 이 단언이 실패한다면
    // 그것은 대개 폰트가 바뀌었다는 뜻이다.
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

    // ── 4. 그릴 것이 없는 글자도 에러가 아니다 ────────────────────────
    //
    // stb는 비어 있는 글자에 0x0 비트맵을 준다. **캐시에는 들어가야 한다.**
    // 안 넣으면 그 글자가 화면에 남아 있는 동안 프레임마다 다시 굽는다.
    //
    // 표본이 공백인 데에는 이유가 있다. Hanme을 쓸 때는 U+4E00(한자)을
    // 표본으로 삼았는데, **unifont에는 "폰트에 없는 글자"라고 부를 것이
    // 없다.** 미할당 코드포인트에도 글리프가 있고, 그마저 없는 자리는
    // .notdef가 빈 글리프가 아니라 모양을 가진다 — U+FFFF·U+E000·U+1F600을
    // 재 보면 셋 다 6x11 비트맵이 나온다. 공백은 어느 폰트에나 있으면서
    // 그릴 것이 없어서, font.zig가 "폰트에 없는 글자와 공백은 둘 다 null"
    // 이라고 적어 둔 계약을 폰트와 무관하게 확인해 준다.
    const before = cache.count();
    const blank = try cache.find(' ');
    if (blank.bitmap != null) {
        std.debug.print("FAIL: 공백에 비트맵이 있다\n", .{});
        return error.UnexpectedBitmap;
    }
    if (cache.count() != before + 1) {
        std.debug.print("FAIL: 그릴 것이 없는 글자가 캐시에 안 들어갔다\n", .{});
        return error.MissingGlyphNotCached;
    }
    std.debug.print("font_test: 그릴 것이 없는 글자도 캐시에 들어간다 OK\n", .{});

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
