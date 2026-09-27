const std = @import("std");
const linux = std.os.linux;
const services = @import("services.zig");

/// 이 검사가 만드는 가짜 services.d. 게스트가 아니라 빌드 컨테이너의 /tmp다.
const ROOT = "/tmp/tars-services-test";
const DIR = ROOT ++ "/services.d";
const MISSING = ROOT ++ "/nope";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

var path_buf: [256]u8 = undefined;

fn join(comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const text = std.fmt.bufPrint(path_buf[0 .. path_buf.len - 1], fmt, args) catch unreachable;
    path_buf[text.len] = 0;
    return path_buf[0..text.len :0];
}

fn mkdirOne(path: [:0]const u8) !void {
    const rc = linux.mkdir(path.ptr, 0o755);
    if (failed(rc)) |e| {
        if (e == .EXIST) return;
        std.debug.print("FAIL: mkdir {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.MkdirFailed;
    }
}

/// 내용은 상관없다 — discover는 모드만 본다. mode는 umask를 거치므로
/// 0o755 · 0o644만 쓴다(umask 022에서 그대로 남는다).
fn touch(name: []const u8, mode: linux.mode_t) !void {
    const path = join("{s}/{s}", .{ DIR, name });
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, mode);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: create {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.OpenFailed;
    }
    _ = linux.close(@intCast(rc));
    // 두 번째 실행에서 이미 있던 파일은 open이 모드를 안 바꾼다.
    _ = linux.chmod(path.ptr, mode);
}

fn link(name: []const u8, target: []const u8) !void {
    var target_buf: [256]u8 = undefined;
    const t = std.fmt.bufPrintZ(&target_buf, "{s}", .{target}) catch unreachable;
    const path = join("{s}/{s}", .{ DIR, name });
    _ = linux.unlink(path.ptr);
    const rc = linux.symlink(t.ptr, path.ptr);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: symlink {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.SymlinkFailed;
    }
}

fn expectVerdict(name: []const u8, want: services.Verdict) !void {
    const got = services.judgeName(name);
    if (got != want) {
        std.debug.print("FAIL: judgeName(\"{s}\") = {s}, want {s}\n", .{ name, @tagName(got), @tagName(want) });
        return error.WrongVerdict;
    }
}

pub fn main() !void {
    // ── 이름만으로 가르는 것 ─────────────────────────────────────────
    try expectVerdict("sshd", .ok);
    try expectVerdict(".hidden", .hidden);
    try expectVerdict(".", .hidden);
    try expectVerdict("..", .hidden);
    try expectVerdict("a" ** services.NAME_MAX, .ok);
    try expectVerdict("a" ** (services.NAME_MAX + 1), .too_long);
    std.debug.print("services_test: names — dot means hidden, {d} bytes is the limit\n", .{services.NAME_MAX});

    // ── 정렬 ───────────────────────────────────────────────────────
    var names = [_][]const u8{ "z-last", "a-first", "m-mid", "a-fir" };
    services.sortNames(&names);
    const sorted = [_][]const u8{ "a-fir", "a-first", "m-mid", "z-last" };
    for (names, sorted) |got, want| {
        if (!std.mem.eql(u8, got, want)) {
            std.debug.print("FAIL: sorted order has {s} where {s} belongs\n", .{ got, want });
            return error.WrongOrder;
        }
    }
    std.debug.print("services_test: names sort bytewise\n", .{});

    // ── 디렉터리가 없으면 0개 ─────────────────────────────────────────
    try mkdirOne(ROOT);
    var list = services.List{};
    list.len = 99; // discover가 0으로 되돌리는지까지 본다
    services.discover(MISSING, &list);
    if (list.len != 0) {
        std.debug.print("FAIL: a missing directory gave {d} services\n", .{list.len});
        return error.MissingDirNotEmpty;
    }
    std.debug.print("services_test: a missing directory is zero services\n", .{});

    // ── 실제 디렉터리 ───────────────────────────────────────────────
    // 만드는 순서를 이름순과 다르게 둔다 — getdents 순서가 결과에 새면 여기서 걸린다.
    try mkdirOne(DIR);
    try touch("z-last", 0o755);
    try touch("m-noexec", 0o644);
    try touch(".hidden", 0o755);
    try mkdirOne(join("{s}/{s}", .{ DIR, "subdir" }));
    try touch("a-first", 0o755);
    try link("l-link", DIR ++ "/a-first");
    try link("k-broken", DIR ++ "/does-not-exist");
    var i: u8 = 0;
    while (i < 7) : (i += 1) {
        const name = [_]u8{ 'n', '0' + i };
        try touch(&name, 0o755);
    }
    try touch("b" ** (services.NAME_MAX + 1), 0o755);

    // 실행 파일은 a-first · l-link · n0..n6 · z-last 열 개다. 앞의 여덟이 뽑힌다.
    services.discover(DIR, &list);
    const want = [_][]const u8{ "a-first", "l-link", "n0", "n1", "n2", "n3", "n4", "n5" };
    if (list.len != want.len) {
        std.debug.print("FAIL: discover picked {d} services, want {d}\n", .{ list.len, want.len });
        return error.WrongCount;
    }
    for (list.slice(), want) |*e, w| {
        const want_path = join("{s}/{s}", .{ DIR, w });
        if (!std.mem.eql(u8, e.path(), want_path)) {
            std.debug.print("FAIL: path {s}, want {s}\n", .{ e.path(), want_path });
            return error.WrongPath;
        }
        var label_buf: [64]u8 = undefined;
        const want_label = std.fmt.bufPrint(&label_buf, "service {s}", .{w}) catch unreachable;
        if (!std.mem.eql(u8, e.label(), want_label)) {
            std.debug.print("FAIL: label {s}, want {s}\n", .{ e.label(), want_label });
            return error.WrongLabel;
        }
        // execve에 넘기는 것은 포인터다. NUL이 제자리에 있어야 한다.
        if (e.path().ptr[e.path().len] != 0) {
            std.debug.print("FAIL: path {s} is not NUL-terminated\n", .{e.path()});
            return error.NotTerminated;
        }
    }
    std.debug.print("services_test: eight executables in name order, the rest skipped or ignored\n", .{});
}
