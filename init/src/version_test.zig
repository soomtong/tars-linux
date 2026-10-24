const std = @import("std");
const version = @import("version.zig");

/// format의 결과가 want와 같은가. 다르면 무엇이 나왔는지 찍는다.
fn same(got: []const u8, want: []const u8, what: []const u8) bool {
    if (std.mem.eql(u8, got, want)) return true;
    std.debug.print("FAIL: {s}: got '{s}', want '{s}'\n", .{ what, got, want });
    return false;
}

pub fn main() !void {
    var buf: [version.MAX]u8 = undefined;

    // ── 1. design 결정 2의 표 네 칸 ──
    //
    // 릴리즈 ISO는 첫 칸뿐이다. 나머지 셋은 스스로 릴리즈가 아니라고 말해야 한다.
    if (!same(version.format(&buf, "0.1.0", "0a6d4bc", true, false), "0.1.0", "tag, clean")) return error.ReleaseNotBare;
    if (!same(version.format(&buf, "0.1.0", "0a6d4bc", true, true), "0.1.0+0a6d4bc-dirty", "tag, dirty")) return error.DirtyTagBare;
    if (!same(version.format(&buf, "0.1.0", "cf1a41a", false, false), "0.1.0+cf1a41a", "after tag, clean")) return error.NoCommit;
    if (!same(version.format(&buf, "0.1.0", "cf1a41a", false, true), "0.1.0+cf1a41a-dirty", "after tag, dirty")) return error.NoDirty;

    // ── 2. 결정 3: git을 못 쓰면 VERSION 그대로 — dirty라고 들어와도 ──
    if (!same(version.format(&buf, "0.1.0", null, false, true), "0.1.0", "no git")) return error.NoGitNotBare;

    // ── 3. 결정 1: VERSION 파일의 글자 ──
    {
        const got = version.base(" 0.1.0\r\n") catch return error.BaseRefused;
        if (!same(got, "0.1.0", "base trims")) return error.BaseNotTrimmed;
    }
    if (version.base(" \n")) |_| {
        std.debug.print("FAIL: an empty VERSION was taken\n", .{});
        return error.EmptyTaken;
    } else |_| {}
    {
        const long: [version.BASE_MAX + 1]u8 = @splat('1');
        if (version.base(&long)) |_| {
            std.debug.print("FAIL: a {d}-byte VERSION was taken\n", .{long.len});
            return error.LongTaken;
        } else |_| {}
        if (version.base(long[0..version.BASE_MAX])) |_| {} else |_| {
            std.debug.print("FAIL: a {d}-byte VERSION was refused\n", .{version.BASE_MAX});
            return error.FitRefused;
        }
    }

    std.debug.print("version_test: VERSION is trimmed, and only a clean tagged tree builds a bare version (5 cases)\n", .{});
}
