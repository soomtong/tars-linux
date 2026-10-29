//! `verify.zig`의 산수를 호스트에서 본다(DR-M1 plan Task 1, 행 비교는 DR-M2 plan Task 1).
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

    try rowTests();
}

/// `vt.CellGlyph`와 같은 모양의 가짜 셀(DR-M2 plan Task 1). `vt.zig`를 import하면 ghostty가
/// 따라오므로 여기서 다시 적는다 — 필드 순서와 크기가 같아 `dirtyRows`의 패딩 단언도 같이 본다.
const Cell = struct { codepoint: u32, col: u16, row: u16, fg: u32, bg: u32 };

fn cell(row: u16, col: u16, cp: u32) Cell {
    return .{ .codepoint = cp, .col = col, .row = row, .fg = 0xFFFFFF, .bg = 0x102030 };
}

fn expectStarts(got: []const u32, want: []const u32, what: []const u8) !void {
    if (!std.mem.eql(u32, got, want)) return fail("{s}: starts={any}, want {any}", .{ what, got, want });
}

fn expectDirty(got: []const bool, want: []const bool, n: u16, what: []const u8) !void {
    if (!std.mem.eql(bool, got, want)) return fail("{s}: dirty={any}, want {any}", .{ what, got, want });
    var count: u16 = 0;
    for (want) |d| if (d) {
        count += 1;
    };
    if (n != count) return fail("{s}: n={d}, want {d}", .{ what, n, count });
}

/// 행 비교(DR-M2 plan 확정 6 · 11). 격자는 4행이다.
fn rowTests() !void {
    var starts: [5]u32 = undefined;

    // 검사 6. 빈 목록 — 모든 행이 0에서 시작하고 끝난다.
    if (!verify.rowStarts(Cell, &.{}, &starts)) return fail("빈 목록이 false다", .{});
    try expectStarts(&starts, &.{ 0, 0, 0, 0, 0 }, "빈 목록");
    std.debug.print("verify_test: 빈 목록의 행 시작은 전부 0이다 OK\n", .{});

    // 검사 7. 0행 둘 · 2행 하나 — 1행과 3행은 비어 있다.
    const a = [_]Cell{ cell(0, 0, 'a'), cell(0, 1, 'b'), cell(2, 5, 'c') };
    if (!verify.rowStarts(Cell, &a, &starts)) return fail("정렬된 목록이 false다", .{});
    try expectStarts(&starts, &.{ 0, 2, 2, 3, 3 }, "행 셋");
    std.debug.print("verify_test: 빈 행은 앞 행의 끝에서 시작하고 끝난다 OK\n", .{});

    // 검사 8. 행이 거꾸로 오거나 격자를 넘으면 false다.
    const back = [_]Cell{ cell(2, 0, 'a'), cell(1, 0, 'b') };
    if (verify.rowStarts(Cell, &back, &starts)) return fail("거꾸로 온 행이 true다", .{});
    const over = [_]Cell{ cell(0, 0, 'a'), cell(4, 0, 'b') };
    if (verify.rowStarts(Cell, &over, &starts)) return fail("격자를 넘는 행이 true다", .{});
    std.debug.print("verify_test: 거꾸로 온 행과 격자 밖 행은 false다 OK\n", .{});

    // 검사 9. 같은 목록은 dirty가 없다. 2행의 색 하나가 바뀌면 2행만, 0행에 셀이 하나 늘면
    // 0행만(길이가 다르다), 비어 있던 3행에 셀이 생기면 3행만 dirty다.
    // 검사 8의 false 호출이 `starts`를 반쯤 덮었으므로 `a`의 것을 다시 계산한다.
    _ = verify.rowStarts(Cell, &a, &starts);
    var dirty: [4]bool = undefined;
    var starts_b: [5]u32 = undefined;
    var b = a;
    _ = verify.rowStarts(Cell, &b, &starts_b);
    try expectDirty(&dirty, &.{ false, false, false, false }, verify.dirtyRows(Cell, &a, &starts, &b, &starts_b, &dirty), "같은 목록");

    b[2].fg = 0xCC6666;
    try expectDirty(&dirty, &.{ false, false, true, false }, verify.dirtyRows(Cell, &a, &starts, &b, &starts_b, &dirty), "2행의 색");

    const grown = [_]Cell{ cell(0, 0, 'a'), cell(0, 1, 'b'), cell(0, 2, 'x'), cell(2, 5, 'c') };
    _ = verify.rowStarts(Cell, &grown, &starts_b);
    try expectDirty(&dirty, &.{ true, false, false, false }, verify.dirtyRows(Cell, &a, &starts, &grown, &starts_b, &dirty), "0행이 늘었다");

    const tail = [_]Cell{ cell(0, 0, 'a'), cell(0, 1, 'b'), cell(2, 5, 'c'), cell(3, 0, 'z') };
    _ = verify.rowStarts(Cell, &tail, &starts_b);
    try expectDirty(&dirty, &.{ false, false, false, true }, verify.dirtyRows(Cell, &a, &starts, &tail, &starts_b, &dirty), "3행이 생겼다");
    std.debug.print("verify_test: 바뀐 행만 dirty다 OK\n", .{});
}
