//! `verify.zig`의 산수를 호스트에서 본다(DR-M1 plan Task 1).
//!
//! 화면은 폭 8픽셀(32바이트) · pitch 40(패딩 8바이트) · 격자 원점 20 · 행 높이 16이다.
//! 높이는 검사마다 다르다 — 격자 4행이면 20 + 64 + 20 = 104, 10행이면 200.
const std = @import("std");
const verify = @import("verify.zig");

const WIDTH_BYTES = 32;
const PITCH = 40;

fn fail(comptime fmt: []const u8, args: anytype) error{VerifyTestFailed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.VerifyTestFailed;
}

fn grid(rows: u16) verify.Grid {
    return .{ .top = 20, .row_height = 16, .rows = rows };
}

/// 픽셀 행 `y`의 첫 바이트를 바꾼다.
fn poke(buf: []u8, y: u32) void {
    buf[y * PITCH] +%= 1;
}

fn expectRows(r: verify.Report, rows: u16, first: []const u16, what: []const u8) !void {
    if (r.rows != rows) return fail("{s}: rows={d}, want {d}", .{ what, r.rows, rows });
    if (!std.mem.eql(u16, r.listed(), first)) return fail("{s}: first={any}, want {any}", .{ what, r.listed(), first });
}

pub fn main() !void {
    // 검사 1. 같은 버퍼는 `ok`다.
    var a: [104 * PITCH]u8 = @splat(0x5a);
    var b: [104 * PITCH]u8 = @splat(0x5a);
    try expectRows(verify.compare(&a, &b, WIDTH_BYTES, PITCH, 104, grid(4)), 0, &.{}, "같은 버퍼");
    if (!verify.compare(&a, &b, WIDTH_BYTES, PITCH, 104, grid(4)).ok()) return fail("같은 버퍼가 ok가 아니다", .{});
    std.debug.print("verify_test: 같은 버퍼는 ok OK\n", .{});

    // 검사 2. 픽셀 행 21 · 30(둘 다 격자 0행)과 50(1행)이 다르면 격자 행은 둘이다.
    poke(&b, 21);
    poke(&b, 30);
    poke(&b, 50);
    try expectRows(verify.compare(&a, &b, WIDTH_BYTES, PITCH, 104, grid(4)), 2, &.{ 0, 1 }, "픽셀 행 셋");
    std.debug.print("verify_test: 한 격자 행의 픽셀 행 둘은 한 행이다 OK\n", .{});

    // 검사 3. 격자 아래(y 90)는 `rows`번, 위 여백(y 5)은 0번이다.
    b = a;
    poke(&b, 90);
    try expectRows(verify.compare(&a, &b, WIDTH_BYTES, PITCH, 104, grid(4)), 1, &.{4}, "격자 아래");
    b = a;
    poke(&b, 5);
    try expectRows(verify.compare(&a, &b, WIDTH_BYTES, PITCH, 104, grid(4)), 1, &.{0}, "위 여백");
    std.debug.print("verify_test: 여백은 이웃 행에 붙는다 OK\n", .{});

    // 검사 4. 패딩만 다르면 `ok`다 — 바이트 32~39는 안 본다.
    b = a;
    b[21 * PITCH + WIDTH_BYTES] +%= 1;
    b[21 * PITCH + PITCH - 1] +%= 1;
    try expectRows(verify.compare(&a, &b, WIDTH_BYTES, PITCH, 104, grid(4)), 0, &.{}, "패딩");
    std.debug.print("verify_test: pitch의 패딩은 안 본다 OK\n", .{});

    // 검사 5. 격자 10행이 전부 다르고 아래 여백도 다르면 rows 11, first는 앞 여덟이다.
    var c: [200 * PITCH]u8 = @splat(0);
    var d: [200 * PITCH]u8 = @splat(0);
    var row: u32 = 0;
    while (row < 10) : (row += 1) poke(&d, 20 + row * 16 + 3);
    poke(&d, 195);
    try expectRows(verify.compare(&c, &d, WIDTH_BYTES, PITCH, 200, grid(10)), 11, &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, "열한 행");
    _ = &c;
    std.debug.print("verify_test: 여덟을 넘으면 수만 센다 OK\n", .{});
}
