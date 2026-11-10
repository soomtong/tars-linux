const std = @import("std");
const scratch = @import("test_scratch.zig");
const linux = std.os.linux;
const services = @import("services.zig");

/// 이 검사가 만드는 가짜 services.d. 게스트가 아니라 빌드 컨테이너의 /tmp 아래, 프로세스마다 따로인 자리다(test_scratch.zig).
const ROOT = "tars-services-test";
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
        std.debug.print("FAIL: mkdir {s} (errno {d})\n", .{ path, @backingInt(e) });
        return error.MkdirFailed;
    }
}

/// 내용은 상관없다 — discover는 모드만 본다. mode는 umask를 거치므로
/// 0o755 · 0o644만 쓴다(umask 022에서 그대로 남는다).
fn touch(name: []const u8, mode: linux.mode_t) !void {
    const path = join("{s}/{s}", .{ DIR, name });
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, mode);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: create {s} (errno {d})\n", .{ path, @backingInt(e) });
        return error.OpenFailed;
    }
    _ = linux.close(@intCast(rc));
    // 두 번째 실행에서 이미 있던 파일은 open이 모드를 안 바꾼다.
    _ = linux.chmod(path.ptr, mode);
}

fn link(name: []const u8, target: []const u8) !void {
    var target_buf: [256]u8 = undefined;
    const t = std.fmt.bufPrintSentinel(&target_buf, "{s}", .{target}, 0) catch unreachable;
    const path = join("{s}/{s}", .{ DIR, name });
    _ = linux.unlink(path.ptr);
    const rc = linux.symlink(t.ptr, path.ptr);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: symlink {s} (errno {d})\n", .{ path, @backingInt(e) });
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
    try scratch.enter();
    // ── 이름만으로 가르는 것 ─────────────────────────────────────────
    try expectVerdict("sshd", .ok);
    try expectVerdict(".hidden", .hidden);
    try expectVerdict(".", .hidden);
    try expectVerdict("..", .hidden);
    try expectVerdict(&@as([services.NAME_MAX]u8, @splat('a')), .ok);
    try expectVerdict(&@as([services.NAME_MAX + 1]u8, @splat('a')), .too_long);
    // DS-M1 결정 M1-A. init이 스스로 띄우는 둘과 같은 이름은 services.d에서 안 받는다.
    // 한 글자라도 다르면 받는다 — 막는 것은 tars-service가 헷갈리는 자리뿐이다.
    try expectVerdict(services.DHCPCD, .reserved);
    try expectVerdict(services.CHRONYD, .reserved);
    try expectVerdict(services.WPA_SUPPLICANT, .reserved);
    try expectVerdict("dhcpcd2", .ok);
    try expectVerdict("chrony", .ok);
    std.debug.print("services_test: names — dot means hidden, {d} bytes is the limit, dhcpcd, chronyd and wpa_supplicant are init's\n", .{services.NAME_MAX});

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
    // 대상은 이름만 준다. symlink의 상대 대상은 링크가 놓인 디렉터리에서 풀리므로 같은 자리의
    // 형제를 가리킨다 — DIR가 상대 경로(GP-M2)라서 `DIR ++ "/a-first"`는 없는 곳이 된다.
    try link("l-link", "a-first");
    try link("k-broken", "does-not-exist");
    var i: u8 = 0;
    while (i < 7) : (i += 1) {
        const name = [_]u8{ 'n', '0' + i };
        try touch(&name, 0o755);
    }
    try touch(&@as([services.NAME_MAX + 1]u8, @splat('b')), 0o755);

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

    try stopLines();
}

fn expectStop(text: []const u8, want: services.StopLine) !void {
    const got = services.findStop(text);
    const same = switch (want) {
        .none => got == .none,
        .bad => got == .bad,
        .ok => |w| got == .ok and got.ok.sig == w.sig and got.ok.grace == w.grace,
    };
    if (!same) {
        std.debug.print("FAIL: findStop([{s}]) = {s}, want {s}\n", .{ text, @tagName(got), @tagName(want) });
        return error.WrongStop;
    }
}

fn writeFile(path: [:0]const u8, text: []const u8) !void {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o755);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: create {s} (errno {d})\n", .{ path, @backingInt(e) });
        return error.OpenFailed;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    if (linux.write(fd, text.ptr, text.len) != text.len) return error.WriteFailed;
    _ = linux.chmod(path.ptr, 0o755);
}

/// SS-M1. 스크립트 머리의 `# tars-stop:` 줄.
fn stopLines() !void {
    const head = "#!/bin/sh\n# TARS postgres service\n";
    try expectStop(head ++ "# tars-stop: INT 10\nexec x\n", .{ .ok = .{ .sig = .INT, .grace = 10 } });
    try expectStop(head ++ "# tars-stop: TERM 30\n", .{ .ok = .{ .sig = .TERM, .grace = 30 } });
    try expectStop("# tars-stop: QUIT 1", .{ .ok = .{ .sig = .QUIT, .grace = 1 } });
    try expectStop("# tars-stop:\tHUP   60 \r\n", .{ .ok = .{ .sig = .HUP, .grace = 60 } });
    std.debug.print("services_test: tars-stop takes TERM, INT, QUIT and HUP with 1 to 60 seconds\n", .{});

    const bad = [_][]const u8{
        "# tars-stop: KILL 10\n", "# tars-stop: SIGINT 10\n", "# tars-stop: int 10\n", "# tars-stop: INT 0\n",
        "# tars-stop: INT 61\n",  "# tars-stop: INT ten\n",   "# tars-stop: INT\n",    "# tars-stop: INT 10 x\n",
        "# tars-stop: INT -5\n",  "# tars-stop:\n",
    };
    for (bad) |b| try expectStop(b, .bad);
    try expectStop(head ++ "exec x\n", .none);
    try expectStop("", .none);
    // 접두사는 줄 머리에서만 — 들여쓴 줄 · 다른 주석 안의 글자는 아니다.
    try expectStop("  # tars-stop: INT 10\n# see tars-stop: INT 10\n", .none);
    // 첫 줄만 쓴다.
    try expectStop("# tars-stop: INT 10\n# tars-stop: TERM 30\n", .{ .ok = .{ .sig = .INT, .grace = 10 } });
    std.debug.print("services_test: other signals, out of range, extra words and look-alikes are bad or ignored\n", .{});

    // 1,024바이트 밖의 줄은 못 보고, 경계에서 잘린 줄은 안 읽는다(잘린 "10"을 "1"로 읽지 않는다).
    var big: [services.STOP_HEAD + 64]u8 = @splat('x');
    big[0] = '#';
    const line = "# tars-stop: INT 10\n";
    big[services.STOP_HEAD - 1] = '\n';
    @memcpy(big[services.STOP_HEAD .. services.STOP_HEAD + line.len], line);
    try expectStop(&big, .none);
    var cut: [services.STOP_HEAD + 8]u8 = @splat('x');
    const cut_line = "\n# tars-stop: INT 1";
    @memcpy(cut[services.STOP_HEAD - cut_line.len .. services.STOP_HEAD], cut_line);
    cut[services.STOP_HEAD] = '0';
    cut[services.STOP_HEAD + 1] = '\n';
    try expectStop(&cut, .none);
    std.debug.print("services_test: only the first {d} bytes count, and a line cut there is not read\n", .{services.STOP_HEAD});

    // discover가 Entry에 담는다 — 링크는 따라간다(tars-service enable의 모양).
    const dir = ROOT ++ "/stop.d";
    try mkdirOne(dir);
    try writeFile(dir ++ "/a-pg", head ++ "# tars-stop: INT 10\nexec sleep 1\n");
    try writeFile(dir ++ "/b-plain", head ++ "exec sleep 1\n");
    try writeFile(dir ++ "/c-bad", "# tars-stop: KILL 10\n");
    _ = linux.unlink(dir ++ "/d-link");
    if (failed(linux.symlink("a-pg", dir ++ "/d-link")) != null) return error.SymlinkFailed;
    var list = services.List{};
    services.discover(dir, &list);
    const want = [_]services.Stop{ .{ .sig = .INT, .grace = 10 }, .{}, .{}, .{ .sig = .INT, .grace = 10 } };
    if (list.len != want.len) {
        std.debug.print("FAIL: stop.d gave {d} services, want {d}\n", .{ list.len, want.len });
        return error.WrongCount;
    }
    for (list.slice(), want) |*e, w| {
        if (e.stop.sig != w.sig or e.stop.grace != w.grace) {
            std.debug.print("FAIL: {s} stops with {s} {d}s, want {s} {d}s\n", .{
                e.label(), services.sigName(e.stop.sig), e.stop.grace, services.sigName(w.sig), w.grace,
            });
            return error.WrongStop;
        }
    }
    std.debug.print("services_test: discover keeps the line's signal and grace, through a link, and the default otherwise\n", .{});
}
