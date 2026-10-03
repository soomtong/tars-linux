//! `image.zig`의 산수를 호스트에서 본다(TG-M2 plan Task 1).
//!
//! 기대값은 쓰기 전에 계산했다. 합성 값 `889098`은 plan의 식으로 파이썬에서
//! 한 번 더 셈했다.
const std = @import("std");
const vt = @import("vt.zig");
const image = @import("image.zig");

const BG: u32 = 0x00102030;

/// 64×64 화면 하나. 프레임버퍼 대신 들어간다.
const Fake = struct {
    px: [64 * 64]u32 = @splat(BG),

    pub fn getPixel(self: *const Fake, x: u32, y: u32) u32 {
        return self.px[y * 64 + x];
    }
    pub fn setPixel(self: *Fake, x: u32, y: u32, color: u32) void {
        self.px[y * 64 + x] = color;
    }
    /// 사각형 안의 픽셀이 전부 `want`인가.
    fn all(self: *const Fake, x0: u32, y0: u32, w: u32, h: u32, want: u32) bool {
        var y = y0;
        while (y < y0 + h) : (y += 1) {
            var x = x0;
            while (x < x0 + w) : (x += 1) if (self.getPixel(x, y) != want) return false;
        }
        return true;
    }
};

const FULL: image.Clip = .{ .x0 = 0, .y0 = 0, .x1 = 64, .y1 = 64 };

/// 빨강 · 초록 · 파랑 · 흰색. 왼쪽 위부터 행 순서.
const RGB_2x2 = [_]u8{ 0xFF, 0, 0, 0, 0xFF, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF };

fn quad(dst_x: i32, dst_y: i32) vt.ImagePlacement {
    return .{
        .layer = .above_text, .z = 0, .image_id = 1, .format = .rgb, .data = &RGB_2x2,
        .width = 2, .height = 2, .src_x = 0, .src_y = 0, .src_w = 2, .src_h = 2,
        .dst_x = dst_x, .dst_y = dst_y, .dst_w = 32, .dst_h = 32,
    };
}

fn fail(comptime fmt: []const u8, args: anytype) error{ImageTestFailed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.ImageTestFailed;
}

pub fn main() !void {
    // 검사 1. 2×2를 32×32로 늘리면 사분면마다 16×16이 한 색이다.
    //
    // 최근접 이웃의 정수 나눗셈이 배율 16에서 경계를 정확히 8·16에 떨어뜨리는지
    // 본다. 원점 (4,4)를 줘서 origin을 더하는 것도 함께 본다.
    var f1: Fake = .{};
    image.draw(&f1, quad(0, 0), 4, 4, FULL);
    if (!f1.all(4, 4, 16, 16, 0xFF0000)) return fail("왼쪽 위 사분면이 빨강이 아니다", .{});
    if (!f1.all(20, 4, 16, 16, 0x00FF00)) return fail("오른쪽 위 사분면이 초록이 아니다", .{});
    if (!f1.all(4, 20, 16, 16, 0x0000FF)) return fail("왼쪽 아래 사분면이 파랑이 아니다", .{});
    if (!f1.all(20, 20, 16, 16, 0xFFFFFF)) return fail("오른쪽 아래 사분면이 흰색이 아니다", .{});
    if (f1.getPixel(3, 4) != BG or f1.getPixel(36, 4) != BG) return fail("사각형 바깥을 칠했다", .{});
    std.debug.print("image_test: 2x2를 32x32로 늘리면 사분면이 한 색이다 OK\n", .{});

    // 검사 2. 반투명 흰색(a=0x80)이 바탕 102030 위에서 889098이 된다.
    const half = [_]u8{ 0xFF, 0xFF, 0xFF, 0x80 };
    var f2: Fake = .{};
    var p2 = quad(0, 0);
    p2.format = .rgba;
    p2.data = &half;
    p2.width = 1;
    p2.height = 1;
    p2.src_w = 1;
    p2.src_h = 1;
    p2.dst_w = 16;
    p2.dst_h = 16;
    image.draw(&f2, p2, 0, 0, FULL);
    if (!f2.all(0, 0, 16, 16, 0x889098)) return fail("반투명 흰색이 {X:0>6}다(889098이어야 한다)", .{f2.getPixel(0, 0)});
    std.debug.print("image_test: 알파 합성이 889098이다 OK\n", .{});

    // 검사 3. 완전히 투명하면 바탕이 그대로다.
    const clear = [_]u8{ 0xFF, 0xFF, 0xFF, 0 };
    var f3: Fake = .{};
    p2.data = &clear;
    image.draw(&f3, p2, 0, 0, FULL);
    if (!f3.all(0, 0, 16, 16, BG)) return fail("투명한 픽셀이 바탕을 바꿨다", .{});
    std.debug.print("image_test: 투명한 픽셀은 안 칠한다 OK\n", .{});

    // 검사 4. 위로 반쯤 나간 사각형(dst_y = −16)은 아래 절반만 칠해진다.
    //
    // 자르기 y0 = 8로 격자 원점이 여백 아래에 있는 모양을 흉내낸다. 그 위
    // 여덟 줄은 한 픽셀도 안 바뀌어야 한다 — 프레임버퍼에서는 이 줄이 여백이고,
    // 화면 맨 위였다면 mmap 밖이다. 남은 절반은 잘리기 전과 같은 원본을
    // 가져오므로 파랑 · 흰색이다.
    var f4: Fake = .{};
    image.draw(&f4, quad(0, -16), 0, 8, .{ .x0 = 0, .y0 = 8, .x1 = 64, .y1 = 64 });
    if (!f4.all(0, 0, 64, 8, BG)) return fail("자르기 위쪽을 칠했다", .{});
    if (!f4.all(0, 8, 16, 16, 0x0000FF) or !f4.all(16, 8, 16, 16, 0xFFFFFF))
        return fail("남은 절반이 파랑 · 흰색이 아니다", .{});
    if (f4.getPixel(0, 24) != BG) return fail("사각형 아래를 칠했다", .{});
    std.debug.print("image_test: 위로 나간 부분을 자른다 OK\n", .{});

    // 검사 5. 오른쪽 끝을 넘는 사각형은 자르기 밖 열을 안 건드린다.
    var f5: Fake = .{};
    image.draw(&f5, quad(48, 0), 0, 0, .{ .x0 = 0, .y0 = 0, .x1 = 56, .y1 = 64 });
    if (!f5.all(48, 0, 8, 16, 0xFF0000)) return fail("자르기 안쪽이 빨강이 아니다", .{});
    if (!f5.all(56, 0, 8, 64, BG)) return fail("자르기 오른쪽을 칠했다", .{});
    std.debug.print("image_test: 오른쪽 끝을 자른다 OK\n", .{});

    // 검사 6. 원본 사각형 x=1, w=1이면 오른쪽 열(초록 · 흰색)만 나온다.
    var f6: Fake = .{};
    var p6 = quad(0, 0);
    p6.src_x = 1;
    p6.src_w = 1;
    p6.dst_w = 16;
    image.draw(&f6, p6, 0, 0, FULL);
    if (!f6.all(0, 0, 16, 16, 0x00FF00) or !f6.all(0, 16, 16, 16, 0xFFFFFF))
        return fail("원본 사각형의 오른쪽 열이 안 나왔다", .{});
    std.debug.print("image_test: 원본 사각형을 따른다 OK\n", .{});

    std.debug.print("PASS\n", .{});
}
