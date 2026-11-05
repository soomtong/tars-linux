//! TP-M1. 개발 도구 층을 `/usr` 위에 얹는다(TP design 결정 9 · 10 · 11 · 13).
//!
//! 묶음은 p3의 `/.tars/layers/<이름>.sqfs`다 — 게스트에서는 `/home`이 붙은 뒤의 `DIR`이다. 부팅마다
//! 묶음마다 loop를 잡아 squashfs로 `/run/tars-layers/<이름>`에 붙이고, 선 것들을 overlay 하나로 `/usr`에
//! 겹친다. upper가 없으므로 `/usr`는 읽기 전용이 된다. 무엇이 실패하든 부팅은 간다 — 로그 한 줄을 남기고
//! 그 묶음(또는 개발 도구 층 전체)을 건너뛴다.
//!
//! 순수한 판단(`judgeName` · `judgeVersion` · `lowerdir`)과 디렉터리 읽기(`scan`)는 경로를 인자로 받아
//! 호스트에서 검사된다(`layers_test.zig`). loop · mount를 하는 `mountAll`은 게스트에서만 돈다 —
//! devtools 체인이 그것을 본다.
const std = @import("std");
const logline = @import("logline.zig");
const linux = std.os.linux;

/// 게스트의 진짜 자리. tars-install이 p3의 `/.tars/layers`에 쓴다(TP-M1 plan 결정 B).
pub const DIR: [:0]const u8 = "/home/.tars/layers";
/// 묶음을 붙이는 자리. `/run`은 initrd 안의 디렉터리(RAM)다.
pub const MOUNT_ROOT: [:0]const u8 = "/run/tars-layers";
/// tars-install이 묶음 옆에 쓰는 버전 한 줄의 이름(plan 결정 E).
pub const VERSION_FILE = "version";
pub const SUFFIX = ".sqfs";

/// 묶음의 상한. design 결정 7의 목록이 열이다.
pub const MAX: usize = 16;
/// 이름(`.sqfs` 앞)의 상한. 로그 줄과 lowerdir에 그대로 들어간다.
pub const NAME_MAX: usize = 32;
/// 한 번에 보는 디렉터리 항목의 상한. `.sqfs.new`(설치기가 쓰다 만 것)와 `version`이 함께 산다.
const SCAN_MAX: usize = 64;

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

// ── 순수한 판단 ──────────────────────────────────────────────────────

pub const NameJudge = union(enum) {
    /// `.sqfs`로 끝나지 않는다 — `version`, `*.sqfs.new` 등. 조용히 넘긴다.
    other,
    /// `.sqfs`로 끝나지만 이름이 규칙 밖이다. 로그 한 줄로 넘긴다.
    bad,
    ok: []const u8,
};

/// `<이름>.sqfs`인가. 이름은 `[a-z0-9-]` 1~NAME_MAX자이고 `-`로 시작하지 않는다. 이름이 mount 옵션
/// 글자(lowerdir)에 들어가므로 `:` · `,` · `\` 같은 것이 끼면 안 된다.
pub fn judgeName(file: []const u8) NameJudge {
    if (!std.mem.endsWith(u8, file, SUFFIX)) return .other;
    const name = file[0 .. file.len - SUFFIX.len];
    if (name.len == 0 or name.len > NAME_MAX or name[0] == '-') return .bad;
    for (name) |c| {
        const fine = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-';
        if (!fine) return .bad;
    }
    return .{ .ok = name };
}

pub const VersionJudge = enum { same, differs, missing };

/// tars-install이 쓴 버전 줄(null이면 파일이 없다)과 이 init의 버전. 앞뒤 공백 · 줄바꿈은 벗긴다.
/// 빈 파일은 없는 것과 같다 — 설치기는 끝에 이 파일을 쓰므로 비었다면 끝까지 못 쓴 것이다.
pub fn judgeVersion(text: ?[]const u8, own: []const u8) VersionJudge {
    const t = std.mem.trim(u8, text orelse return .missing, " \t\r\n");
    if (t.len == 0) return .missing;
    return if (std.mem.eql(u8, t, own)) .same else .differs;
}

/// overlay의 `lowerdir=` 값. 맨 왼쪽이 맨 위다 — initrd의 `/usr`를 맨 위에 둬서 같은 경로는 initrd가
/// 이긴다(design 결정 4, plan 결정 C.5). 그 아래로 묶음들이 이름 순이다. 버퍼가 모자라면 null.
pub fn lowerdir(buf: []u8, root: []const u8, names: []const []const u8) ?[:0]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    w.writeAll("/usr") catch return null;
    for (names) |n| w.print(":{s}/{s}/usr", .{ root, n }) catch return null;
    w.writeByte(0) catch return null;
    return buf[0 .. w.end - 1 :0];
}

// ── 디렉터리 읽기 ────────────────────────────────────────────────────

/// 고른 묶음 이름들. `main()`의 스택에 산다.
pub const List = struct {
    bufs: [MAX][NAME_MAX]u8 = undefined,
    lens: [MAX]usize = undefined,
    len: usize = 0,
    /// 규칙 밖 이름 · 상한을 넘은 것의 수. 로그는 scan이 찍는다.
    skipped: usize = 0,

    pub fn name(self: *const List, i: usize) []const u8 {
        return self.bufs[i][0..self.lens[i]];
    }

    fn insertSorted(self: *List, n: []const u8) void {
        var at = self.len;
        while (at > 0 and std.mem.order(u8, self.name(at - 1), n) == .gt) : (at -= 1) {
            self.bufs[at] = self.bufs[at - 1];
            self.lens[at] = self.lens[at - 1];
        }
        @memcpy(self.bufs[at][0..n.len], n);
        self.lens[at] = n.len;
        self.len += 1;
    }
};

pub const ScanResult = enum { ok, no_dir, unreadable };

/// init의 sink. `scan`의 줄은 머리말 · 줄바꿈 없이 지어지고, 부른 쪽이 자기 이름을 붙인다 — tars-install은
/// 매체의 `boot/layers`를 같은 함수로 읽고 `tars-install:`로 찍는다.
pub const InitLog = struct {
    pub fn print(_: InitLog, comptime fmt: []const u8, args: anytype) void {
        logline.print("tars-init: " ++ fmt ++ "\n", args);
    }
};

/// dir의 `*.sqfs`를 이름 순으로 모은다. 디렉터리가 없으면 no_dir(로그는 부른 쪽이), 못 열면 unreadable.
pub fn scan(sink: anytype, dir: [:0]const u8, list: *List) ScanResult {
    list.len = 0;
    list.skipped = 0;
    const rc = linux.open(dir.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc)) |e| {
        if (e == .NOENT) return .no_dir;
        sink.print("layers: cannot open {s} (errno {d})", .{ dir, @backingInt(e) });
        return .unreadable;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var seen: usize = 0;
    var buf: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &buf, buf.len);
        if (failed(n)) |e| {
            sink.print("layers: cannot read {s} (errno {d})", .{ dir, @backingInt(e) });
            break;
        }
        if (n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const d: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += d.reclen;
            const file = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&d.name)), 0);
            seen += 1;
            if (seen > SCAN_MAX) {
                list.skipped += 1;
                continue;
            }
            switch (judgeName(file)) {
                .other => {},
                .bad => {
                    sink.print("layer {s}: bad name, skipped", .{file});
                    list.skipped += 1;
                },
                .ok => |name| {
                    if (list.len == MAX) {
                        sink.print("layer {s}: more than {d} layers, skipped", .{ name, MAX });
                        list.skipped += 1;
                        continue;
                    }
                    list.insertSorted(name);
                },
            }
        }
    }
    return .ok;
}

/// dir/VERSION_FILE의 앞부분. 없으면 null.
pub fn readVersion(dir: []const u8, buf: []u8) ?[]const u8 {
    var path_buf: [128]u8 = undefined;
    const path = std.fmt.bufPrintSentinel(&path_buf, "{s}/{s}", .{ dir, VERSION_FILE }, 0) catch return null;
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(rc) != null) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    const n = linux.read(fd, buf.ptr, buf.len);
    if (failed(n) != null) return null;
    return buf[0..n];
}

// ── loop (include/uapi/linux/loop.h, 커널 6.18.60) ─────────────────────

const LOOP_CONFIGURE: u32 = 0x4C0A;
const LOOP_CTL_GET_FREE: u32 = 0x4C82;
const LO_FLAGS_READ_ONLY: u32 = 1;
/// 마지막 fd가 닫히면 커널이 loop를 스스로 푼다(`drivers/block/loop.c`의 `lo_release`). mount가 그
/// 장치를 쥐고 있는 동안은 살아 있고, umount하거나 mount가 실패해 우리 fd만 닫히면 풀린다 —
/// 그래서 `LOOP_CLR_FD`를 따로 부르지 않는다(TP-M1 확인한 것).
const LO_FLAGS_AUTOCLEAR: u32 = 4;

const LoopInfo64 = extern struct {
    device: u64 = 0,
    inode: u64 = 0,
    rdevice: u64 = 0,
    offset: u64 = 0,
    sizelimit: u64 = 0,
    number: u32 = 0,
    encrypt_type: u32 = 0,
    encrypt_key_size: u32 = 0,
    flags: u32 = 0,
    file_name: [64]u8 = @splat(0),
    crypt_name: [64]u8 = @splat(0),
    encrypt_key: [32]u8 = @splat(0),
    init: [2]u64 = @splat(0),
};

const LoopConfig = extern struct {
    fd: u32,
    block_size: u32 = 0,
    info: LoopInfo64 = .{},
    reserved: [8]u64 = @splat(0),
};

comptime {
    // 헤더의 크기와 다르면 ioctl이 엉뚱한 칸을 읽는다.
    if (@sizeOf(LoopInfo64) != 232) @compileError("loop_info64 is 232 bytes");
    if (@sizeOf(LoopConfig) != 304) @compileError("loop_config is 304 bytes");
}

/// 묶음 하나를 붙인다. 실패하면 단계 이름과 errno를 한 줄 남기고 false.
fn mountOne(dir: []const u8, name: []const u8) bool {
    var file_buf: [128]u8 = undefined;
    const file = std.fmt.bufPrintSentinel(&file_buf, "{s}/{s}{s}", .{ dir, name, SUFFIX }, 0) catch return false;
    var target_buf: [96]u8 = undefined;
    const target = std.fmt.bufPrintSentinel(&target_buf, "{s}/{s}", .{ MOUNT_ROOT, name }, 0) catch return false;

    const back_rc = linux.open(file.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(back_rc)) |e| return step(name, "open", e);
    const back: i32 = @intCast(back_rc);
    defer _ = linux.close(back);

    const ctl_rc = linux.open("/dev/loop-control", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
    if (failed(ctl_rc)) |e| return step(name, "loop-control", e);
    const ctl: i32 = @intCast(ctl_rc);
    const free_rc = linux.ioctl(ctl, LOOP_CTL_GET_FREE, 0);
    _ = linux.close(ctl);
    if (failed(free_rc)) |e| return step(name, "loop number", e);

    var dev_buf: [32]u8 = undefined;
    const dev = std.fmt.bufPrintSentinel(&dev_buf, "/dev/loop{d}", .{free_rc}, 0) catch return false;
    const loop_rc = linux.open(dev.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(loop_rc)) |e| return step(name, "loop open", e);
    const loop: i32 = @intCast(loop_rc);
    // 이 fd가 닫히는 순간 mount가 안 쥐고 있으면 AUTOCLEAR가 loop를 푼다.
    defer _ = linux.close(loop);

    var cfg: LoopConfig = .{ .fd = @intCast(back) };
    cfg.info.flags = LO_FLAGS_READ_ONLY | LO_FLAGS_AUTOCLEAR;
    if (failed(linux.ioctl(loop, LOOP_CONFIGURE, @intFromPtr(&cfg)))) |e| return step(name, "loop configure", e);

    if (failed(linux.mkdir(target.ptr, 0o755))) |e| {
        if (e != .EXIST) return step(name, "mkdir", e);
    }
    const flags = linux.MS.RDONLY | linux.MS.NOSUID | linux.MS.NODEV;
    if (failed(linux.mount(dev.ptr, target.ptr, "squashfs", flags, 0))) |e| return step(name, "mount", e);
    return true;
}

fn step(name: []const u8, what: []const u8, e: linux.E) bool {
    logline.print("tars-init: layer {s}: {s} failed (errno {d})\n", .{ name, what, @backingInt(e) });
    return false;
}

fn monotonicMs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / std.time.ns_per_ms;
}

/// 부팅마다 한 번, `/home`이 붙은 직후에 부른다(design 결정 9). own은 이 init의 버전이다.
pub fn mountAll(dir: [:0]const u8, own: []const u8) void {
    var list: List = .{};
    switch (scan(InitLog{}, dir, &list)) {
        .no_dir => {
            logline.print("tars-init: layers: none in {s}\n", .{dir});
            return;
        },
        .unreadable => return,
        .ok => {},
    }
    if (list.len == 0) {
        logline.print("tars-init: layers: none in {s}\n", .{dir});
        return;
    }

    // design 결정 13 · plan 결정 E. 버전이 다르면 하나도 안 얹는다 — old 슬롯으로 뜬 부팅과 반쪽 갱신.
    var ver_buf: [128]u8 = undefined;
    const ver = readVersion(dir, &ver_buf);
    switch (judgeVersion(ver, own)) {
        .same => {},
        .missing => {
            logline.print("tars-init: layers: no {s} file in {s}, none mounted\n", .{ VERSION_FILE, dir });
            return;
        },
        .differs => {
            logline.print("tars-init: layers: built for {s}, this image is {s}, none mounted\n", .{
                std.mem.trim(u8, ver.?, " \t\r\n"), own,
            });
            return;
        },
    }

    const t0 = monotonicMs();
    if (failed(linux.mkdir(MOUNT_ROOT.ptr, 0o755))) |e| {
        if (e != .EXIST) {
            logline.print("tars-init: layers: cannot create {s} (errno {d})\n", .{ MOUNT_ROOT, @backingInt(e) });
            return;
        }
    }

    var up: [MAX][]const u8 = undefined;
    var n_up: usize = 0;
    for (0..list.len) |i| {
        const name = list.name(i);
        if (mountOne(dir, name)) {
            up[n_up] = name;
            n_up += 1;
        }
    }
    if (n_up == 0) return;

    var low_buf: [1024]u8 = undefined;
    const low = lowerdir(&low_buf, MOUNT_ROOT, up[0..n_up]) orelse return;
    var data_buf: [1100]u8 = undefined;
    const data = std.fmt.bufPrintSentinel(&data_buf, "lowerdir={s}", .{low}, 0) catch return;
    if (failed(linux.mount("overlay", "/usr", "overlay", linux.MS.RDONLY, @intFromPtr(data.ptr)))) |e| {
        logline.print("tars-init: overlay /usr failed (errno {d})\n", .{@backingInt(e)});
        // 붙인 묶음을 뗀다. umount가 loop의 마지막 참조를 놓으면 AUTOCLEAR가 loop를 푼다.
        for (up[0..n_up]) |name| {
            var t_buf: [96]u8 = undefined;
            const t = std.fmt.bufPrintSentinel(&t_buf, "{s}/{s}", .{ MOUNT_ROOT, name }, 0) catch continue;
            _ = linux.umount(t.ptr);
        }
        return;
    }
    logline.print("tars-init: overlay /usr from {d} layers in {d}ms\n", .{ n_up, monotonicMs() - t0 });

    // design 결정 10. overlay 뒤에 각 묶음의 etc/를 /etc로.
    for (up[0..n_up]) |name| {
        var src_buf: [PATH_MAX]u8 = undefined;
        const src = std.fmt.bufPrintSentinel(&src_buf, "{s}/{s}/etc", .{ MOUNT_ROOT, name }, 0) catch continue;
        var copied: usize = 0;
        copyTree(name, src, "/etc", 0, &copied);
        if (copied > 0) logline.print("tars-init: layer {s}: {d} files into /etc\n", .{ name, copied });
    }
}

// ── etc/ 복사 (design 결정 10) ──────────────────────────────────────────

const PATH_MAX: usize = 256;
/// `etc/` 아래 깊이의 상한. 스택에 경로 버퍼가 깊이만큼 쌓인다.
const DEPTH_MAX: usize = 8;

/// src 아래를 dst 아래로. 디렉터리는 만들고, 보통 파일은 없을 때만 복사한다(initrd가 이긴다).
/// 링크 · 장치 등은 싣지 않고 한 줄. src가 없으면(etc/가 없는 묶음) 조용하다.
fn copyTree(name: []const u8, src: [:0]const u8, dst: [:0]const u8, depth: usize, copied: *usize) void {
    const rc = linux.open(src.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc) != null) return;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var buf: [2048]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &buf, buf.len);
        if (failed(n) != null or n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const d: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += d.reclen;
            const entry = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&d.name)), 0);
            if (std.mem.eql(u8, entry, ".") or std.mem.eql(u8, entry, "..")) continue;

            var s_buf: [PATH_MAX]u8 = undefined;
            var t_buf: [PATH_MAX]u8 = undefined;
            const s = std.fmt.bufPrintSentinel(&s_buf, "{s}/{s}", .{ src, entry }, 0) catch continue;
            const t = std.fmt.bufPrintSentinel(&t_buf, "{s}/{s}", .{ dst, entry }, 0) catch continue;
            switch (d.type) {
                linux.DT.DIR => {
                    if (depth + 1 >= DEPTH_MAX) {
                        logline.print("tars-init: layer {s}: {s} is deeper than {d}, skipped\n", .{ name, s, DEPTH_MAX });
                        continue;
                    }
                    if (failed(linux.mkdir(t.ptr, 0o755))) |e| {
                        if (e != .EXIST) continue;
                    }
                    copyTree(name, s, t, depth + 1, copied);
                },
                linux.DT.REG => {
                    if (copyFile(s, t)) copied.* += 1;
                },
                else => logline.print("tars-init: layer {s}: {s} is not a file or directory, skipped\n", .{ name, s }),
            }
        }
    }
}

/// 있으면 안 덮는다(`O_EXCL`). 모드는 원본의 것이다.
fn copyFile(src: [:0]const u8, dst: [:0]const u8) bool {
    var st: linux.Statx = undefined;
    if (failed(linux.statx(linux.AT.FDCWD, src.ptr, 0, .{ .MODE = true }, &st)) != null) return false;
    const in_rc = linux.open(src.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(in_rc) != null) return false;
    const in_fd: i32 = @intCast(in_rc);
    defer _ = linux.close(in_fd);
    const out_rc = linux.open(dst.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .CLOEXEC = true }, st.mode & 0o7777);
    if (failed(out_rc)) |e| {
        if (e == .EXIST) return false;
        logline.print("tars-init: layers: cannot create {s} (errno {d})\n", .{ dst, @backingInt(e) });
        return false;
    }
    const out_fd: i32 = @intCast(out_rc);
    defer _ = linux.close(out_fd);
    var buf: [16 * 1024]u8 = undefined;
    while (true) {
        const n = linux.read(in_fd, &buf, buf.len);
        if (failed(n) != null) return false;
        if (n == 0) return true;
        var w: usize = 0;
        while (w < n) {
            const k = linux.write(out_fd, buf[w..].ptr, n - w);
            if (failed(k) != null) return false;
            w += k;
        }
    }
}
