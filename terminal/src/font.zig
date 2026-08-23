const std = @import("std");

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

/// 구워 놓은 글자 하나.
///
/// `x_offset`·`y_offset`은 **셀의 왼쪽 위 모서리에서** 비트맵을 찍을 곳까지의
/// 거리다. stb가 주는 `yoff`는 baseline 기준이라 음수인데(실측: 'A'가 -10,
/// '한'이 -12), 그대로 쓰면 글자가 화면 위로 솟는다. 굽는 자리에서 ascent를
/// 더해 셀 기준으로 바꿔 둔다 — **렌더러가 baseline이라는 개념을 배우지 않게
/// 하려는 것이고, TR-M0이 색을 vt.zig에서 확정해 넘긴 것과 같은 경계다.**
///
/// TR-M1 전까지는 이 두 값을 stb에게 받아서 그냥 버렸다. 그래서 'g'의
/// 디센더가 화면에서 사라지고 있었다.
pub const Glyph = struct {
    codepoint: u32,
    width: u32,
    height: u32,
    /// 이 글자가 차지하는 폭(픽셀). **폰트의 advance에서 가져온다** —
    /// 실측으로 라틴이 8.00, 한글이 16.00이다. 옛 `cellWidth` 함수는
    /// "0x7F를 넘으면 16"이라고 판정해서 'é'(advance 8)를 틀리게 봤다.
    cell_width: u32,
    x_offset: i32,
    y_offset: i32,
    /// 폰트에 없는 글자와 공백은 **둘 다 null이다.** stb가 양쪽에 똑같이
    /// 0x0 비트맵을 주고, 구분할 이유도 없다 — 어느 쪽이든 그릴 것이 없다.
    ///
    /// unifont로 바꾼 뒤로 앞쪽 절반은 실제로는 일어나지 않는다. 미할당
    /// 코드포인트에도 글리프가 있고 .notdef조차 모양을 가져서, 화면에
    /// 두부(tofu)가 뜨지 않는 대신 null은 공백에서만 온다.
    bitmap: ?[*]u8,
};

/// 처음 쓸 때 구워서 넣어 두는 글리프 캐시.
///
/// 부팅 때 ASCII 95자를 미리 굽던 배열을 대신한다. 한글이 들어오면서 미리
/// 굽기가 성립하지 않게 됐다 — 이 폰트에 **완성형 11172자가 하나도 빠짐없이**
/// 들어 있고, 전부 구우면 비트맵만 2.07MB에 컨테이너(arm64 native)에서
/// 396밀리초가 든다. 이 바이너리가 Debug로 빌드되기 때문인데(build.zig가
/// standardOptimizeOption의 기본값을 쓰고 prepare.sh가 옵션 없이 부른다),
/// ReleaseFast로 재면 같은 기계에서 46밀리초다. 게스트는 qemu-system-x86_64를
/// TCG로 도는 환경이라 그 위에 몇십 배가 더 붙는다.
///
/// **메모리가 아니라 시간이 이유다.** 2.07MB는 128MB 게스트가 감당하지만,
/// 커널이 /init에 넘기는 시각이 1.12초인 기계에서 부팅에 그만한 시간을
/// 더할 이유가 없다. 화면에 실제로 나오는 글자는 수십 자다.
///
/// **`font_data`가 캐시보다 오래 살아야 한다.** stb_truetype은 그 바이트를
/// 복사하지 않고 참조만 한다.
pub const Cache = struct {
    alloc: std.mem.Allocator,
    info: stb.stbtt_fontinfo,
    scale: f32,
    /// baseline까지의 픽셀. stb의 `yoff`를 셀 기준으로 옮길 때 더한다.
    /// unifont는 ascent=56, descent=-8, unitsPerEm=64라 16px에서 scale이
    /// 정확히 0.25이고 이 값이 14가 된다. 남는 2px이 descent 몫이라 16x16
    /// 격자에 빈틈없이 맞아떨어진다.
    ascent_px: i32,
    glyphs: std.AutoHashMapUnmanaged(u32, Glyph),
    /// 지금까지 구운 비트맵의 합계. design 위험 3을 게이트가 볼 수 있게
    /// 하는 유일한 창구다.
    bitmap_bytes: usize,

    pub fn init(alloc: std.mem.Allocator, font_data: []const u8) !Cache {
        var info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const pixel_height: f32 = 16.0;
        const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_height);

        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        stb.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

        return .{
            .alloc = alloc,
            .info = info,
            .scale = scale,
            .ascent_px = @intFromFloat(@round(@as(f32, @floatFromInt(ascent)) * scale)),
            .glyphs = .empty,
            .bitmap_bytes = 0,
        };
    }

    /// 비트맵 자체는 stb가 libc의 malloc으로 잡은 것이라 여기서 안 푼다.
    /// 프로세스가 끝날 때 함께 사라진다 — 셸이 끝나면 terminal도 끝나고
    /// PID 1이 새로 띄운다(main.zig 마지막 주석).
    pub fn deinit(self: *Cache) void {
        self.glyphs.deinit(self.alloc);
    }

    /// 글자 하나를 돌려준다. 캐시에 없으면 굽는다.
    ///
    /// **폰트에 없는 글자도 캐시에 넣는다.** 안 넣으면 그 글자가 화면에
    /// 남아 있는 동안 프레임마다 다시 굽는다.
    pub fn find(self: *Cache, codepoint: u32) !Glyph {
        const gop = try self.glyphs.getOrPut(self.alloc, codepoint);
        if (gop.found_existing) return gop.value_ptr.*;

        var w: c_int = 0;
        var h: c_int = 0;
        var xoff: c_int = 0;
        var yoff: c_int = 0;
        const bitmap = stb.stbtt_GetCodepointBitmap(
            &self.info,
            self.scale,
            self.scale,
            @intCast(codepoint),
            &w,
            &h,
            &xoff,
            &yoff,
        );

        // 공백과 폰트에 없는 글자는 0x0 비트맵으로 온다. 그것은 정상이다.
        // w*h가 0이 아닌데 null이면 malloc이 실패한 것이고, 그때는 알아야
        // 한다. 캐시에 들어가므로 이 경고는 글자마다 한 번만 찍힌다.
        if (bitmap == null and w * h != 0) {
            std.debug.print("font: WARN could not rasterize U+{X}\n", .{codepoint});
        }

        var advance: c_int = 0;
        var lsb: c_int = 0;
        stb.stbtt_GetCodepointHMetrics(&self.info, @intCast(codepoint), &advance, &lsb);

        gop.value_ptr.* = .{
            .codepoint = codepoint,
            .width = @intCast(w),
            .height = @intCast(h),
            .cell_width = @intFromFloat(
                @round(@as(f32, @floatFromInt(advance)) * self.scale),
            ),
            .x_offset = @intCast(xoff),
            // 여기가 baseline이 사라지는 자리다. 위 doc comment 참고.
            .y_offset = self.ascent_px + @as(i32, @intCast(yoff)),
            .bitmap = bitmap,
        };
        self.bitmap_bytes += @as(usize, @intCast(w)) * @as(usize, @intCast(h));
        return gop.value_ptr.*;
    }

    pub fn count(self: *const Cache) usize {
        return self.glyphs.count();
    }
};
