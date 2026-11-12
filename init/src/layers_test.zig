//! TP-M1. layers.zig의 순수한 판단과 디렉터리 읽기. loop · mount(`mountAll`)는 devtools 체인이 본다.
const std = @import("std");
const scratch = @import("test_scratch.zig");
const linux = std.os.linux;
const layers = @import("layers.zig");

/// 가짜 `/home/.tars/layers`. 프로세스마다 따로인 /tmp 아래다(test_scratch.zig).
const DIR = "tars-layers-test";
const MISSING = "tars-layers-test-nope";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn fail(comptime fmt: []const u8, args: anytype) error{Check} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Check;
}

/// scan의 줄을 받아 stderr로. 검사가 보는 것은 반환값과 목록이다.
const Quiet = struct {
    pub fn print(_: Quiet, comptime fmt: []const u8, args: anytype) void {
        std.debug.print("  (scan) " ++ fmt ++ "\n", args);
    }
};

fn touch(name: []const u8, body: []const u8) !void {
    var buf: [128]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&buf, "{s}/{s}", .{ DIR, name }, 0) catch unreachable;
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |e| return fail("create {s} (errno {d})", .{ path, @backingInt(e) });
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    _ = linux.write(fd, body.ptr, body.len);
}

fn checkNames() !void {
    const good = [_][2][]const u8{
        .{ "base.sqfs", "base" },
        .{ "lang-jvm.sqfs", "lang-jvm" },
        .{ "a0.sqfs", "a0" },
    };
    for (good) |g| switch (layers.judgeName(g[0])) {
        .ok => |n| if (!std.mem.eql(u8, n, g[1])) return fail("judgeName({s}) = {s}, want {s}", .{ g[0], n, g[1] }),
        else => return fail("judgeName({s}) is not ok", .{g[0]}),
    };
    // 설치기가 쓰다 만 것, 버전 줄, 다른 파일은 조용히 넘긴다.
    for ([_][]const u8{ "version", "base.sqfs.new", "notes.txt", "sqfs" }) |f| {
        if (layers.judgeName(f) != .other) return fail("judgeName({s}) is not other", .{f});
    }
    // lowerdir 글자를 깨뜨릴 이름 · 빈 이름 · 대문자 · 너무 긴 이름.
    const long = @as([layers.NAME_MAX + 1]u8, @splat('a')) ++ ".sqfs";
    for ([_][]const u8{ ".sqfs", "Base.sqfs", "a:b.sqfs", "a,b.sqfs", "a b.sqfs", "-x.sqfs", "a_b.sqfs", long }) |f| {
        if (layers.judgeName(f) != .bad) return fail("judgeName({s}) is not bad", .{f});
    }
    const max = @as([layers.NAME_MAX]u8, @splat('a')) ++ ".sqfs";
    if (layers.judgeName(max) != .ok) return fail("a name of {d} bytes is not ok", .{layers.NAME_MAX});
}

fn checkVersion() !void {
    const own = "0.1.5+0b66cb8";
    const cases = [_]struct { text: ?[]const u8, want: layers.VersionJudge }{
        .{ .text = "0.1.5+0b66cb8\n", .want = .same },
        .{ .text = "  0.1.5+0b66cb8 \r\n", .want = .same },
        .{ .text = "0.1.4\n", .want = .differs },
        .{ .text = "0.1.5+0b66cb8-dirty\n", .want = .differs },
        .{ .text = "", .want = .missing },
        .{ .text = "\n", .want = .missing },
        .{ .text = null, .want = .missing },
    };
    for (cases) |c| {
        const got = layers.judgeVersion(c.text, own);
        if (got != c.want) return fail("judgeVersion({?s}) = {s}, want {s}", .{ c.text, @tagName(got), @tagName(c.want) });
    }
}

fn checkLowerdir() !void {
    var buf: [256]u8 = undefined;
    const names = [_][]const u8{ "base", "lang-jvm" };
    const got = layers.lowerdir(&buf, layers.MOUNT_ROOT, &names) orelse return fail("lowerdir returned null", .{});
    const want = "/usr:/run/tars-layers/base/usr:/run/tars-layers/lang-jvm/usr";
    if (!std.mem.eql(u8, got, want)) return fail("lowerdir = {s}, want {s}", .{ got, want });
    if (got.ptr[got.len] != 0) return fail("lowerdir is not NUL-terminated", .{});
    // mount(2)에 넘기는 글자라 잘린 채로 가면 안 된다.
    var small: [20]u8 = undefined;
    if (layers.lowerdir(&small, layers.MOUNT_ROOT, &names) != null) return fail("lowerdir fit in 20 bytes", .{});
    // 가장 긴 경우가 mountAll의 버퍼(1024)에 든다.
    var big: [1024]u8 = undefined;
    var many: [layers.MAX][]const u8 = undefined;
    const longest: [layers.NAME_MAX]u8 = @splat('a');
    for (&many) |*n| n.* = &longest;
    if (layers.lowerdir(&big, layers.MOUNT_ROOT, &many) == null) return fail("sixteen longest names do not fit in 1024", .{});
}

fn checkScan() !void {
    var list: layers.List = .{};
    if (layers.scan(Quiet{}, MISSING, &list) != .no_dir) return fail("scan of a missing dir is not no_dir", .{});

    switch (linux.errno(linux.mkdir(DIR, 0o755))) {
        .SUCCESS, .EXIST => {},
        else => return fail("mkdir {s}", .{DIR}),
    }
    if (layers.scan(Quiet{}, DIR, &list) != .ok or list.len != 0) return fail("an empty dir gave {d} layers", .{list.len});

    try touch("lang-jvm.sqfs", "");
    try touch("base.sqfs", "");
    try touch("util.sqfs", "");
    try touch("base.sqfs.new", "");
    try touch("version", "0.1.5\n");
    try touch("Bad.sqfs", "");
    if (layers.scan(Quiet{}, DIR, &list) != .ok) return fail("scan is not ok", .{});
    const want = [_][]const u8{ "base", "lang-jvm", "util" };
    if (list.len != want.len) return fail("scan found {d} layers, want {d}", .{ list.len, want.len });
    for (want, 0..) |w, i| {
        if (!std.mem.eql(u8, list.name(i), w)) return fail("layer {d} is {s}, want {s}", .{ i, list.name(i), w });
    }
    if (list.skipped != 1) return fail("skipped {d}, want 1 (Bad.sqfs)", .{list.skipped});

    var vbuf: [64]u8 = undefined;
    const v = layers.readVersion(DIR, &vbuf) orelse return fail("readVersion found nothing", .{});
    if (layers.judgeVersion(v, "0.1.5") != .same) return fail("readVersion gave {s}", .{v});
    if (layers.readVersion(MISSING, &vbuf) != null) return fail("readVersion of a missing dir is not null", .{});

    // LD-M0(LD design 결정 2): base의 칸. 비슷한 이름(base-x)과 앞에 오는 이름(aaa)에 안 속고, base가 없으면 null이다.
    const empty: layers.List = .{};
    if (layers.baseIndex(&empty) != null) return fail("baseIndex of an empty list is not null", .{});
    if (layers.baseIndex(&list) != 0) return fail("baseIndex is not 0 in base, lang-jvm, util", .{});
    try touch("aaa.sqfs", "");
    try touch("base-x.sqfs", "");
    if (layers.scan(Quiet{}, DIR, &list) != .ok) return fail("scan is not ok", .{});
    const at = layers.baseIndex(&list) orelse return fail("baseIndex lost base among aaa, base-x", .{});
    if (!std.mem.eql(u8, list.name(at), "base") or at != 1) return fail("baseIndex is {d} ({s}), want 1 (base)", .{ at, list.name(at) });
    var del_buf: [64]u8 = undefined;
    const del = std.fmt.bufPrintSentinel(&del_buf, "{s}/base.sqfs", .{DIR}, 0) catch unreachable;
    if (failed(linux.unlink(del.ptr))) |e| return fail("unlink {s} (errno {d})", .{ del, @backingInt(e) });
    if (layers.scan(Quiet{}, DIR, &list) != .ok) return fail("scan is not ok", .{});
    if (layers.baseIndex(&list) != null) return fail("baseIndex found base after base.sqfs was removed", .{});
}

fn checkLocal() !void {
    var buf: [160]u8 = undefined;
    const got = layers.localData(&buf, layers.LOCAL_TARGET, layers.LOCAL_DIR) orelse return fail("localData returned null", .{});
    const want = "lowerdir=/usr/local,upperdir=/home/.tars/local/upper,workdir=/home/.tars/local/work";
    if (!std.mem.eql(u8, got, want)) return fail("localData: got {s}, want {s}", .{ got, want });
    if (got.ptr[got.len] != 0) return fail("localData is not NUL-terminated", .{});
    var small: [40]u8 = undefined;
    if (layers.localData(&small, layers.LOCAL_TARGET, layers.LOCAL_DIR) != null) return fail("localData fit in 40 bytes", .{});
}

pub fn main() !void {
    try scratch.enter();
    try checkNames();
    try checkVersion();
    try checkLowerdir();
    try checkScan();
    try checkLocal();
    std.debug.print("layers_test: names, version, lowerdir, scan and the /usr/local data as planned\n", .{});
}
