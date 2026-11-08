//! TP-M11. `trust.zig`가 부팅 때 명령을 부를지 — `.crt` 이름과 디렉터리 읽기.
const std = @import("std");
const linux = std.os.linux;
const scratch = @import("test_scratch.zig");
const trust = @import("trust.zig");

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

fn mkdir(path: [*:0]const u8) !void {
    switch (linux.errno(linux.mkdir(path, 0o755))) {
        .SUCCESS, .EXIST => {},
        else => return error.Failed,
    }
}

fn touch(path: [*:0]const u8) !void {
    const rc = linux.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .CLOEXEC = true }, 0o644);
    if (linux.errno(rc) != .SUCCESS) return error.Failed;
    _ = linux.close(@intCast(rc));
}

pub fn main() !void {
    try scratch.enter();

    const yes = [_][]const u8{ "mkcert_development_CA_1.crt", "a.crt", "x.y.crt" };
    for (yes) |n| if (!trust.isCrt(n)) return fail("isCrt({s}) = false", .{n});
    const no = [_][]const u8{ ".crt", ".hidden.crt", "a.pem", "a.crt.new", "crt", "a.CRT", "" };
    for (no) |n| if (trust.isCrt(n)) return fail("isCrt([{s}]) = true", .{n});
    std.debug.print("trust_test: names — *.crt only, not hidden, not .pem or .new\n", .{});

    if (trust.hasCrt("trust-none")) return fail("a missing directory has a .crt", .{});
    try mkdir("trust-d");
    if (trust.hasCrt("trust-d")) return fail("an empty directory has a .crt", .{});
    try touch("trust-d/readme.txt");
    try touch("trust-d/.x.crt");
    if (trust.hasCrt("trust-d")) return fail("readme.txt or .x.crt counted", .{});
    try mkdir("trust-d/sub");
    try mkdir("trust-d/sub/deep");
    try touch("trust-d/sub/deep/z.crt");
    if (trust.hasCrt("trust-d")) return fail("two levels down counted", .{});
    try touch("trust-d/sub/y.crt");
    if (!trust.hasCrt("trust-d")) return fail("one level down was missed", .{});
    try mkdir("trust-e");
    try touch("trust-e/mkcert_development_CA_1.crt");
    if (!trust.hasCrt("trust-e")) return fail("a top-level .crt was missed", .{});
    std.debug.print("trust_test: directories — missing, empty, others, top level, one level down but not two\n", .{});
}
