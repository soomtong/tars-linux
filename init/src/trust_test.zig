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

    try runs();
}

const ENVP = [_:null]?[*:0]const u8{ "PATH=/usr/bin:/bin", null };

fn nowMs() i64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

/// 죽었는가 — `/proc/PID/stat`이 없거나 상태 칸이 Z(아직 아무도 안 거둔 좀비). 컨테이너의 PID 1이 고아를 거두지 않아도 맞게 본다.
fn dead(pid: linux.pid_t) bool {
    var p_buf: [64]u8 = undefined;
    const p = std.fmt.bufPrintSentinel(&p_buf, "/proc/{d}/stat", .{pid}, 0) catch return false;
    const rc = linux.open(p.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return true;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var buf: [256]u8 = undefined;
    const n = linux.read(fd, &buf, buf.len);
    if (linux.errno(n) != .SUCCESS) return true;
    const text = buf[0..n];
    // "pid (comm) S ..." — comm에 괄호가 들 수 있어 마지막 ')' 뒤를 본다.
    const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return false;
    return close + 2 < text.len and text[close + 2] == 'Z';
}

fn readPid(path: [*:0]const u8) ?linux.pid_t {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var buf: [32]u8 = undefined;
    const n = linux.read(fd, &buf, buf.len);
    if (linux.errno(n) != .SUCCESS) return null;
    return std.fmt.parseInt(linux.pid_t, std.mem.trim(u8, buf[0..n], " \n"), 10) catch null;
}

/// SS-M2. 명령을 시한 안에 돌리는 길 — 부팅의 CA 갱신이 쓰는 그것.
fn runs() !void {
    const t_argv = [_:null]?[*:0]const u8{ "/bin/true", null };
    if (trust.runWithin("/bin/true", &t_argv, &ENVP, 2000) != .ok) return fail("/bin/true did not run ok", .{});
    const f_argv = [_:null]?[*:0]const u8{ "/bin/false", null };
    switch (trust.runWithin("/bin/false", &f_argv, &ENVP, 2000)) {
        .failed => |st| if (!linux.W.IFEXITED(st) or linux.W.EXITSTATUS(st) != 1) return fail("/bin/false status {d}", .{st}),
        else => return fail("/bin/false was not failed", .{}),
    }
    const n_argv = [_:null]?[*:0]const u8{ "/nope/missing", null };
    switch (trust.runWithin("/nope/missing", &n_argv, &ENVP, 2000)) {
        .failed => |st| if (!linux.W.IFEXITED(st) or linux.W.EXITSTATUS(st) != 127) return fail("a missing command status {d}", .{st}),
        else => return fail("a missing command was not failed", .{}),
    }
    std.debug.print("trust_test: runWithin — ok, a failure, and a missing command (127)\n", .{});

    // 시한 넘김. 셸이 손자 sleep을 띄우고 기다린다 — update-ca-certificates가 run-parts · openssl을 띄우는 모양이다.
    // 셸만 죽이면 손자가 남는다. 그룹째 죽여야 이 검사가 선다.
    _ = linux.unlink("trust-grandchild.pid");
    const s_argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", "sleep 30 & echo $! > trust-grandchild.pid; wait", null };
    const t0 = nowMs();
    const got = trust.runWithin("/bin/sh", &s_argv, &ENVP, 300);
    const took = nowMs() - t0;
    if (got != .timed_out) return fail("a 30s command under a 300ms limit was {s}", .{@tagName(got)});
    if (took < 300 or took > 2000) return fail("the 300ms limit took {d}ms", .{took});
    const gpid = readPid("trust-grandchild.pid") orelse return fail("the shell did not write its child's pid", .{});
    var gone = false;
    for (0..20) |_| {
        if (dead(gpid)) {
            gone = true;
            break;
        }
        const ts: linux.timespec = .{ .sec = 0, .nsec = 50_000_000 };
        _ = linux.nanosleep(&ts, null);
    }
    if (!gone) {
        _ = linux.kill(gpid, .KILL);
        return fail("the grandchild sleep {d} outlived the time-out (only the shell was killed)", .{gpid});
    }
    std.debug.print("trust_test: a command over its limit is killed with its whole group in {d}ms\n", .{took});
}
