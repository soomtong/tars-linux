//! 글리프 래스터 한 겹 — stb_truetype 위의 얇은 층(TK design 결정 2 · 5). terminal과 툴킷이 같은 파일을 컴파일한다.
//!
//! 여기 있는 것은 글꼴 하나를 한 크기로 읽고, 글자 하나의 8비트 coverage 비트맵과 metric을 돌려주는 것뿐이다. 무엇을
//! 어떻게 쓰는지(셀 격자 · 문턱값 · sprite · 비례폭 배치 · 감마)는 부르는 쪽의 것이다 — terminal은 `src/font.zig`가
//! 16 px · unifont · 정수 셀 폭 · sprite를 감싸고, 툴킷은 em 기준 크기 · 서브픽셀 x · f32 advance · kern을 쓴다.
//!
//! `@import("c_stb_truetype")`는 부르는 build.zig가 꽂는다(대상마다 번역이 따로다 — 게스트 x86_64와 호스트 arm64).
//! 그래서 이 파일은 shared/의 다른 파일과 달리 `zig run` 혼자로는 안 돌고, quick_check의 순수 검사 목록에 없다.
//! stb의 구현(`STB_TRUETYPE_IMPLEMENTATION`)도 부르는 쪽이 C 파일 하나로 링크한다.

const stb = @import("c_stb_truetype");

/// 크기를 정하는 두 길. 같은 "16"이 글꼴마다 다른 크기가 되는 것이 `pixel_height`이고(ascent − descent가 그 픽셀),
/// CSS의 font-size처럼 글꼴마다 같은 크기가 되는 것이 `em`이다.
pub const Size = union(enum) {
    /// `stbtt_ScaleForPixelHeight` — terminal이 unifont 16 px에 쓰는 길(scale이 정확히 0.25가 된다).
    pixel_height: f32,
    /// `stbtt_ScaleForMappingEmToPixels` — 툴킷의 길(design 결정 5).
    em: f32,
};

/// 구운 글자 하나. 비트맵은 stb가 libc malloc으로 잡은 것이고 주인은 부른 쪽이다(`freeBitmap`).
///
/// `x_offset` · `y_offset`은 펜 위치(baseline 위의 점)에서 비트맵 왼쪽 위까지의 거리 — stb가 준 그대로다. y는 baseline
/// 기준이라 보통 음수다. 셀 기준으로 옮기는 것은 부르는 쪽 일이다(terminal은 `ascent_px`를 더한다).
pub const Bitmap = struct {
    /// 공백과 글꼴에 없는 글자는 0x0이고 null이다. 크기가 0이 아닌데 null이면 malloc 실패다.
    pixels: ?[*]u8,
    width: u32,
    height: u32,
    x_offset: i32,
    y_offset: i32,
};

/// 글꼴 하나를 한 크기로 연 것. `data`는 이것보다 오래 살아야 한다 — stb는 바이트를 복사하지 않고 참조만 한다.
pub const Face = struct {
    info: stb.stbtt_fontinfo,
    /// 글꼴 단위 → 픽셀.
    scale: f32,

    pub const InitError = error{FontInitFailed};

    /// 파일의 첫 글꼴(.ttc라면 0번)을 연다.
    pub fn init(data: []const u8, size: Size) InitError!Face {
        var info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&info, data.ptr, 0) == 0) return error.FontInitFailed;
        const scale = switch (size) {
            .pixel_height => |px| stb.stbtt_ScaleForPixelHeight(&info, px),
            .em => |px| stb.stbtt_ScaleForMappingEmToPixels(&info, px),
        };
        return .{ .info = info, .scale = scale };
    }

    /// hhea의 세로 metric(글꼴 단위 그대로). 픽셀은 `× scale` — 반올림 규칙은 부르는 쪽이 정한다.
    pub const VMetrics = struct { ascent: i32, descent: i32, line_gap: i32 };

    pub fn vmetrics(self: *const Face) VMetrics {
        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        stb.stbtt_GetFontVMetrics(&self.info, &ascent, &descent, &line_gap);
        return .{ .ascent = ascent, .descent = descent, .line_gap = line_gap };
    }

    /// 글자 하나의 coverage 비트맵. `subpixel_x`는 0 이상 1 미만의 가로 이동(펜 위치의 소수 부분)이다 — 0이면
    /// `stbtt_GetCodepointBitmap`과 바이트까지 같다(stb가 그 함수를 shift 0으로 부른다).
    pub fn bitmap(self: *const Face, codepoint: u32, subpixel_x: f32) Bitmap {
        var w: c_int = 0;
        var h: c_int = 0;
        var xoff: c_int = 0;
        var yoff: c_int = 0;
        const pixels = stb.stbtt_GetCodepointBitmapSubpixel(
            &self.info,
            self.scale,
            self.scale,
            subpixel_x,
            0.0,
            @intCast(codepoint),
            &w,
            &h,
            &xoff,
            &yoff,
        );
        return .{
            .pixels = pixels,
            .width = @intCast(w),
            .height = @intCast(h),
            .x_offset = @intCast(xoff),
            .y_offset = @intCast(yoff),
        };
    }

    /// 펜이 나아가는 거리(픽셀, 소수). terminal은 이것을 반올림해 셀 폭으로 쓴다.
    pub fn advance(self: *const Face, codepoint: u32) f32 {
        var adv: c_int = 0;
        var lsb: c_int = 0;
        stb.stbtt_GetCodepointHMetrics(&self.info, @intCast(codepoint), &adv, &lsb);
        return @as(f32, @floatFromInt(adv)) * self.scale;
    }

    /// 두 글자 사이의 kern(픽셀, 소수). stb는 GPOS의 pair kerning을 먼저, 없으면 `kern` 표를 본다(1.19 · 1.22). 셰이핑은
    /// 없다(R-TXT-4).
    pub fn kern(self: *const Face, left: u32, right: u32) f32 {
        const k = stb.stbtt_GetCodepointKernAdvance(&self.info, @intCast(left), @intCast(right));
        return @as(f32, @floatFromInt(k)) * self.scale;
    }
};

/// `Face.bitmap`이 준 비트맵을 돌려준다. terminal은 부르지 않는다(구운 것을 프로세스 끝까지 캐시에 둔다).
pub fn freeBitmap(pixels: ?[*]u8) void {
    if (pixels) |p| stb.stbtt_FreeBitmap(p, null);
}
