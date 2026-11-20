//! 글자(TK design 결정 5). `shared/glyph.zig`(stb 한 겹) 위에 툴킷이 쓰는 모양을 얹는다 — em 기준 크기, 서브픽셀 x 위치(한 픽셀을
//! 넷으로 나눈 칸), f32 advance, kern, 굽고 나서 복사해 두는 캐시. 그리는 것은 `canvas.zig`이고 여기는 픽셀을 모른다.
//!
//! 셰이핑은 없다(R-TXT-4) — 코드포인트 하나가 글리프 하나다. 줄 나누기 · 커서 위치는 TK-M4(비례폭 텍스트)의 것이다.

const std = @import("std");
const glyph = @import("glyph");

/// 서브픽셀 x 위치의 칸 수. 펜의 소수 부분을 이 칸으로 반올림해 굽는다 — 넷이면 0.25 px 단위라 글자 사이가 고르고(조사:
/// 정수 반올림은 `0123456789`가 `01234 56789`처럼 벌어졌다), 캐시는 글자마다 많아야 넷이다.
pub const SUBPIXELS: u32 = 4;

/// 구워서 복사해 둔 글자 하나. `pixels`는 `Face`의 allocator가 잡은 것이다(stb의 malloc 사본은 곧바로 돌려준다).
pub const Glyph = struct {
    pixels: []const u8,
    width: u32,
    height: u32,
    /// 펜 위치(baseline 위, 서브픽셀 칸으로 반올림한 뒤의 정수 x)에서 비트맵 왼쪽 위까지.
    x_offset: i32,
    y_offset: i32,
};

const Key = struct { cp: u32, sub: u32 };

/// 글꼴 하나를 em 크기 하나로 연 것. `data`는 이것보다 오래 살아야 한다(stb는 참조만 한다).
pub const Face = struct {
    alloc: std.mem.Allocator,
    face: glyph.Face,
    /// em 크기(픽셀, 배율을 곱한 물리 값).
    px: f32,
    /// baseline 위 · 아래(아래는 양수) · 한 줄의 높이 — 픽셀, 소수. 줄 높이는 hhea의 ascent − descent + line_gap.
    ascent: f32,
    descent: f32,
    line_height: f32,
    glyphs: std.AutoHashMapUnmanaged(Key, Glyph) = .empty,
    advances: std.AutoHashMapUnmanaged(u32, f32) = .empty,

    pub fn init(alloc: std.mem.Allocator, data: []const u8, em_px: f32) glyph.Face.InitError!Face {
        const f = try glyph.Face.init(data, .{ .em = em_px });
        const vm = f.vmetrics();
        const asc = @as(f32, @floatFromInt(vm.ascent)) * f.scale;
        const desc = -@as(f32, @floatFromInt(vm.descent)) * f.scale;
        const gap = @as(f32, @floatFromInt(vm.line_gap)) * f.scale;
        return .{
            .alloc = alloc,
            .face = f,
            .px = em_px,
            .ascent = asc,
            .descent = desc,
            .line_height = asc + desc + gap,
        };
    }

    pub fn deinit(self: *Face) void {
        var it = self.glyphs.valueIterator();
        while (it.next()) |g| self.alloc.free(g.pixels);
        self.glyphs.deinit(self.alloc);
        self.advances.deinit(self.alloc);
    }

    /// 글자 하나를 서브픽셀 칸 `sub`(0..SUBPIXELS-1)로 구운 것. 처음이면 굽고 복사해 캐시에 넣는다.
    pub fn get(self: *Face, cp: u32, sub: u32) !Glyph {
        const gop = try self.glyphs.getOrPut(self.alloc, .{ .cp = cp, .sub = sub });
        if (gop.found_existing) return gop.value_ptr.*;
        const shift = @as(f32, @floatFromInt(sub)) / @as(f32, @floatFromInt(SUBPIXELS));
        const bm = self.face.bitmap(cp, shift);
        defer glyph.freeBitmap(bm.pixels);
        const n = @as(usize, bm.width) * bm.height;
        const copy = self.alloc.alloc(u8, n) catch |e| {
            _ = self.glyphs.remove(.{ .cp = cp, .sub = sub });
            return e;
        };
        if (bm.pixels) |p| @memcpy(copy, p[0..n]);
        gop.value_ptr.* = .{
            .pixels = copy,
            .width = bm.width,
            .height = bm.height,
            .x_offset = bm.x_offset,
            .y_offset = bm.y_offset,
        };
        return gop.value_ptr.*;
    }

    pub fn advance(self: *Face, cp: u32) f32 {
        if (self.advances.get(cp)) |a| return a;
        const a = self.face.advance(cp);
        self.advances.put(self.alloc, cp, a) catch {};
        return a;
    }

    pub fn kern(self: *const Face, left: u32, right: u32) f32 {
        return self.face.kern(left, right);
    }

    /// UTF-8 한 줄의 폭(픽셀, 소수). 그리는 `canvas.text`와 같은 펜 규칙(advance + kern)이다. 잘못된 바이트는 건너뛴다.
    pub fn measure(self: *Face, str: []const u8) f32 {
        var pen: f32 = 0;
        var prev: ?u32 = null;
        var it = Utf8.init(str);
        while (it.next()) |cp| {
            if (prev) |p| pen += self.kern(p, cp);
            pen += self.advance(cp);
            prev = cp;
        }
        return pen;
    }
};

/// 펜 x(소수)를 정수 픽셀과 서브픽셀 칸으로 가른다. 칸이 SUBPIXELS로 넘치면 다음 픽셀의 0칸이다.
pub fn splitPen(x: f32) struct { ix: i32, sub: u32 } {
    const fl = @floor(x);
    var ix: i32 = @intFromFloat(fl);
    var sub: u32 = @intFromFloat(@round((x - fl) * @as(f32, @floatFromInt(SUBPIXELS))));
    if (sub == SUBPIXELS) {
        sub = 0;
        ix += 1;
    }
    return .{ .ix = ix, .sub = sub };
}

/// 툴킷의 감마 기본값(design 결정 5). TK-M0 결정 4의 화면 판정(실제 QEMU screendump, 13 · 14 px)에서 lead가 골랐다 — 1.0에서는
/// 14 px 글자에 coverage 255인 픽셀이 없어 획이 흐렸다.
pub const GAMMA: f32 = 1.8;

/// coverage → 섞는 양의 표(감마). 1.0이면 그대로다.
pub fn gammaLut(gamma: f32) [256]u8 {
    var lut: [256]u8 = undefined;
    for (&lut, 0..) |*v, i| {
        const a = @as(f32, @floatFromInt(i)) / 255.0;
        v.* = @intFromFloat(@round(std.math.pow(f32, a, 1.0 / gamma) * 255.0));
    }
    return lut;
}

/// UTF-8 코드포인트를 차례로. 잘못된 바이트는 하나씩 건너뛴다(그릴 것이 없다).
pub const Utf8 = struct {
    s: []const u8,
    i: usize = 0,

    pub fn init(s: []const u8) Utf8 {
        return .{ .s = s };
    }

    pub fn next(self: *Utf8) ?u32 {
        while (self.i < self.s.len) {
            const n = std.unicode.utf8ByteSequenceLength(self.s[self.i]) catch {
                self.i += 1;
                continue;
            };
            if (self.i + n > self.s.len) {
                self.i = self.s.len;
                return null;
            }
            const cp = std.unicode.utf8Decode(self.s[self.i .. self.i + n]) catch {
                self.i += 1;
                continue;
            };
            self.i += n;
            return cp;
        }
        return null;
    }
};
