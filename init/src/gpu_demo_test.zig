const std = @import("std");
const demo = @import("gpu_demo.zig");

/// DY-M2의 호스트 검사. SDL을 부르는 부분은 체인 `display`가 게스트에서 보고, 여기서는 순수한 셋(인자 · 판 글자 ·
/// 띠 색)만 본다. 다른 *_test와 같은 모양이다(실패하면 0이 아닌 종료 코드).
pub fn main() !void {
    // 1. 인자: 없음 · `--seconds N`(N > 0)만.
    const none = demo.parseArgs(&.{}) orelse return fail("no arguments were refused");
    if (none.seconds != 0) return fail("no arguments did not mean wait for Esc");
    const five = demo.parseArgs(&.{ "--seconds", "5" }) orelse return fail("--seconds 5 was refused");
    if (five.seconds != 5) return fail("--seconds 5 did not give 5");
    const bad = [_][]const []const u8{
        &.{"--seconds"},
        &.{ "--seconds", "0" },
        &.{ "--seconds", "x" },
        &.{ "--secs", "5" },
        &.{ "--seconds", "5", "6" },
    };
    for (bad) |argv| if (demo.parseArgs(argv) != null) return fail("a bad argument list was taken");

    // 2. 판 글자: SDL_VERSIONNUM(3, 2, 10).
    var buf: [32]u8 = undefined;
    if (!std.mem.eql(u8, demo.versionText(&buf, 3002010), "3.2.10")) return fail("3002010 is not 3.2.10");

    // 3. 띠 색은 시간에 따라 바뀌고(멈춘 화면이 보인다), 띠끼리도 다르다.
    if (std.mem.eql(u8, &demo.bandColor(0, 0), &demo.bandColor(0, 400))) return fail("a band kept its colour for 400ms");
    if (std.mem.eql(u8, &demo.bandColor(0, 0), &demo.bandColor(1, 0))) return fail("two bands share a colour");

    std.debug.print("gpu_demo_test: arguments, the version text and the band colours\n", .{});
}

fn fail(what: []const u8) error{GpuDemoTest} {
    std.debug.print("FAIL: {s}\n", .{what});
    return error.GpuDemoTest;
}
