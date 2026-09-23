const std = @import("std");
const linux = std.os.linux;
const storage = @import("storage.zig");
const disk = @import("disk.zig");

/// tars-install — 부팅 매체의 부트 파일 넷을 내장 디스크에 옮겨 USB 없이
/// 뜨게 한다(DI design). 인자 없이 치면 목록, 디스크를 주면 계획을 보이고
/// YES를 받는다. `--yes`가 그 질문을 건너뛴다.
///
/// init 옆의 별도 실행 파일인 이유는 DI design 결정 5다 — 부팅 경로에 안
/// 들어가야 게이트의 열두 체인에 닿지 않고, storage.zig를 같이 써야 목록에
/// 보이는 이름과 부팅 때 찾는 이름이 같은 코드에서 나온다.
///
/// init처럼 libc 없이 시스템 콜만 쓴다. 게스트에 `mount` 명령이 없어서다
/// (design 확인 6). 파티션과 포맷만 외부 도구 셋에 맡긴다(결정 3).

/// main.zig·storage.zig에도 같은 함수가 있다. 세 줄짜리 헬퍼 하나 때문에
/// 공용 모듈을 만들지 않는다는 devices.zig의 규칙 그대로다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

// ── 출력 ─────────────────────────────────────────────────────────────

fn writeAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return;
        }
        off += n;
    }
}

/// 사람이 읽는 줄은 stdout으로. 게이트는 시리얼에서 이것을 읽는다.
fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    writeAll(1, text);
}

/// 실패는 stderr로. 한 줄에 무엇이 몇으로 죽었는지가 다 있어야 한다
/// (design 결정 5).
fn complain(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-install: " ++ fmt ++ "\n", args) catch return;
    writeAll(2, text);
}

// ── 작은 파일 읽기 ───────────────────────────────────────────────────

/// devices.readFile과 같은 루프다. sysfs 속성은 전부 한 페이지 안이다.
fn readFile(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return null;
        }
        if (n == 0) break;
        len += n;
    }
    return buf[0..len];
}

/// /sys/block/<이름>/<속성>의 내용을 앞뒤 공백 없이. 없으면 null.
fn sysAttr(name: []const u8, attr: []const u8, buf: []u8) ?[]const u8 {
    var path: [128]u8 = undefined;
    const p = std.fmt.bufPrintZ(&path, "/sys/block/{s}/{s}", .{ name, attr }) catch return null;
    const text = readFile(p.ptr, buf) orelse return null;
    return std.mem.trim(u8, text, " \t\r\n");
}

/// 바이트 크기. /sys/block/<이름>/size는 장치의 논리 섹터 크기와 무관하게
/// 늘 512바이트 단위다(커널 문서 Documentation/ABI/stable/sysfs-block).
fn sizeBytes(name: []const u8) ?u64 {
    var buf: [32]u8 = undefined;
    const text = sysAttr(name, "size", &buf) orelse return null;
    const sectors = std.fmt.parseInt(u64, text, 10) catch return null;
    return sectors * 512;
}

fn exists(path: [*:0]const u8) bool {
    return failed(linux.access(path, linux.F_OK)) == null;
}

// ── 부팅 매체 ────────────────────────────────────────────────────────

const WORK_DIR: [:0]const u8 = "/tmp/tars-install";
const MEDIUM_DIR: [:0]const u8 = "/tmp/tars-install/medium";
const ESP_DIR: [:0]const u8 = "/tmp/tars-install/esp";

/// 매체일 수 있는 것. 광학 드라이브 둘(QEMU의 -cdrom · 실기의 외장 드라이브)과
/// 디스크 전부(dd로 ISO를 쓴 USB 스틱은 /dev/sdX다). 광학 드라이브는 init의
/// 설정 디스크 후보에는 없다 — ISO는 ext2가 아니다(design 결정 4).
const MEDIUM_CANDIDATES = [_][:0]const u8{ "/dev/sr0", "/dev/sr1" } ++ storage.DISKS;

fn mkdirOk(path: [*:0]const u8) bool {
    const rc = linux.mkdir(path, 0o755);
    if (failed(rc)) |e| return e == .EXIST;
    return true;
}

/// 앞머리가 ISO9660이고, 붙여 보니 limine.conf가 있는 첫 후보. 찾으면
/// MEDIUM_DIR에 붙인 채로 돌려준다.
///
/// 앞머리를 먼저 읽는 이유는 RM design 결정 11과 같다 — 열여섯을 mount로
/// 두드리지 않는다. 매체가 없는 광학 드라이브는 읽기가 실패해서 여기서
/// 빠진다. 노드가 있다는 것으로 아무것도 결론짓지 않는다(DI-M0 실측 9 —
/// QEMU는 -cdrom이 없어도 빈 sr0을 붙인다).
fn findMedium() ?[:0]const u8 {
    if (!mkdirOk(WORK_DIR.ptr) or !mkdirOk(MEDIUM_DIR.ptr)) {
        complain("cannot create {s}", .{MEDIUM_DIR});
        return null;
    }
    var mark_buf: [128]u8 = undefined;
    const mark = std.fmt.bufPrintZ(&mark_buf, "{s}/{s}", .{ MEDIUM_DIR, disk.MEDIUM_MARK }) catch unreachable;

    for (MEDIUM_CANDIDATES) |path| {
        var buf: [disk.HEAD_BYTES]u8 = undefined;
        const head = storage.readHead(path, &buf) orelse continue;
        if (disk.describe(head).kind != .iso9660) continue;

        const rc = linux.mount(path.ptr, MEDIUM_DIR.ptr, "iso9660", linux.MS.RDONLY, 0);
        if (failed(rc)) |_| continue;
        if (exists(mark.ptr)) return path;
        _ = linux.umount(MEDIUM_DIR.ptr);
    }
    return null;
}

// ── 목록 ─────────────────────────────────────────────────────────────

fn printUsage() void {
    say("tars-install <disk>        install onto <disk>; everything on it is erased\n", .{});
    say("tars-install <disk> --yes  same, without asking\n", .{});
}

/// 한 디스크의 상태 칸. 매체면 그 이름, 아니면 앞머리에 보이는 것.
fn stateOf(path: [:0]const u8, medium: ?[:0]const u8, buf: []u8) []const u8 {
    if (medium) |m| {
        if (std.mem.eql(u8, m, path)) return "boot medium";
    }
    var head_buf: [disk.HEAD_BYTES]u8 = undefined;
    const head = storage.readHead(path, &head_buf) orelse return "unreadable";
    return disk.stateText(buf, disk.describe(head));
}

fn list(medium: ?[:0]const u8) void {
    if (medium) |m| {
        var head_buf: [disk.HEAD_BYTES]u8 = undefined;
        const head = storage.readHead(m, &head_buf) orelse &[_]u8{};
        const seen = disk.describe(head);
        var size_buf: [16]u8 = undefined;
        const size = disk.formatSize(&size_buf, sizeBytes(disk.sysName(m)) orelse 0);
        say("tars-install: boot medium {s} (iso9660 {s}, {s})\n", .{ m, seen.label, size });
    } else {
        say("tars-install: no boot medium found; boot from the TARS ISO or USB stick to install\n", .{});
    }
    say("\n", .{});

    var shown: usize = 0;
    for (storage.DISKS) |path| {
        const name = disk.sysName(path);
        const bytes = sizeBytes(name) orelse continue;
        shown += 1;

        var size_buf: [16]u8 = undefined;
        var model_buf: [64]u8 = undefined;
        var rem_buf: [8]u8 = undefined;
        var state_buf: [64]u8 = undefined;
        const model = sysAttr(name, "device/model", &model_buf) orelse "-";
        const removable = sysAttr(name, "removable", &rem_buf) orelse "0";
        say("  {s:<14} {s:>7}  {s:<22} {s:<9}  {s}\n", .{
            path,
            disk.formatSize(&size_buf, bytes),
            model,
            if (std.mem.eql(u8, removable, "1")) "removable" else "internal",
            stateOf(path, medium, &state_buf),
        });
    }
    if (shown == 0) say("  (no disks)\n", .{});
    say("\n", .{});
    printUsage();
}

// ── 외부 도구 ────────────────────────────────────────────────────────

/// argv[0]을 fork+execve로 돌리고 끝나기를 기다린다. 0으로 끝나면 true.
///
/// 도구의 stdout·stderr는 로그 파일로 보내고, 실패했을 때만 그것을 보여
/// 준다. 성공한 도구의 말은 사람에게 소음이다 — mkfs.vfat은 성공해도 iconv
/// 경고 세 줄을 찍는다(DI-M0 실측 8).
///
/// stdin은 input이 있으면 파이프로, 없으면 /dev/null로 준다. 도구가
/// 무엇을 묻더라도 매달리지 않게 한다 — mke2fs는 옛 파일시스템을 보면
/// tty에서 "Proceed anyway?"를 묻는다.
fn runTool(
    argv: [*:null]const ?[*:0]const u8,
    input: ?[]const u8,
    log: [:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) bool {
    const tool = std.mem.span(argv[0].?);
    var fds: [2]i32 = .{ -1, -1 };
    if (input != null) {
        if (failed(linux.pipe(&fds))) |e| {
            complain("pipe for {s} failed (errno {d})", .{ tool, @intFromEnum(e) });
            return false;
        }
    }

    const pid = linux.fork();
    if (failed(pid)) |e| {
        complain("fork for {s} failed (errno {d})", .{ tool, @intFromEnum(e) });
        return false;
    }
    if (pid == 0) {
        if (input != null) {
            _ = linux.dup2(fds[0], 0);
            _ = linux.close(fds[0]);
            _ = linux.close(fds[1]);
        } else {
            const nul = linux.open("/dev/null", .{ .ACCMODE = .RDONLY }, 0);
            if (failed(nul) == null) _ = linux.dup2(@intCast(nul), 0);
        }
        const out = linux.open(log.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        if (failed(out) == null) {
            _ = linux.dup2(@intCast(out), 1);
            _ = linux.dup2(@intCast(out), 2);
        }
        _ = linux.execve(argv[0].?, argv, envp);
        linux.exit(127);
    }

    if (input) |text| {
        _ = linux.close(fds[0]);
        // 배치는 세 줄이라 파이프 버퍼(64KiB) 안에 든다. 자식이 읽기 전에
        // 다 써도 막히지 않는다.
        writeAll(fds[1], text);
        _ = linux.close(fds[1]);
    }

    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), &status, 0, null);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            complain("waiting for {s} failed (errno {d})", .{ tool, @intFromEnum(e) });
            return false;
        }
        break;
    }
    if (linux.W.IFEXITED(status) and linux.W.EXITSTATUS(status) == 0) return true;

    if (linux.W.IFEXITED(status)) {
        complain("{s} failed (exit {d}); what it said:", .{ tool, linux.W.EXITSTATUS(status) });
    } else {
        complain("{s} was killed (signal {d}); what it said:", .{ tool, @intFromEnum(linux.W.TERMSIG(status)) });
    }
    var said: [4096]u8 = undefined;
    if (readFile(log.ptr, &said)) |text| writeAll(2, text);
    return false;
}

/// sfdisk가 돌아온 뒤 파티션 노드를 기다린다. 최대 3초, 100ms 간격 — HD-M2가
/// 키보드에 쓴 한정된 기다림이다(design 위험 2). DI-M0에서는 첫 확인에
/// 있었지만 실기의 답은 모른다.
fn waitForNode(path: [:0]const u8) bool {
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        if (exists(path.ptr)) return true;
        const req: linux.timespec = .{ .sec = 0, .nsec = 100 * std.time.ns_per_ms };
        _ = linux.nanosleep(&req, null);
    }
    return exists(path.ptr);
}

// ── 복사 ─────────────────────────────────────────────────────────────

/// 파일 하나를 통째로. 돌려주는 것은 쓴 바이트 수다. 41MB initrd도 64KiB씩
/// 읽고 쓰면 된다 — 힙이 없고 필요도 없다.
fn copyFile(src: [:0]const u8, dst: [:0]const u8) ?u64 {
    const in_rc = linux.open(src.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(in_rc)) |e| {
        complain("cannot open {s} (errno {d})", .{ src, @intFromEnum(e) });
        return null;
    }
    const in_fd: i32 = @intCast(in_rc);
    defer _ = linux.close(in_fd);

    const out_rc = linux.open(dst.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(out_rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ dst, @intFromEnum(e) });
        return null;
    }
    const out_fd: i32 = @intCast(out_rc);
    defer _ = linux.close(out_fd);

    var buf: [64 * 1024]u8 = undefined;
    var total: u64 = 0;
    while (true) {
        const n = linux.read(in_fd, &buf, buf.len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            complain("reading {s} failed (errno {d})", .{ src, @intFromEnum(e) });
            return null;
        }
        if (n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const w = linux.write(out_fd, buf[off..].ptr, n - off);
            if (failed(w)) |e| {
                if (e == .INTR) continue;
                complain("writing {s} failed (errno {d})", .{ dst, @intFromEnum(e) });
                return null;
            }
            off += w;
        }
        total += n;
    }
    return total;
}

// ── 설치 ─────────────────────────────────────────────────────────────

fn install(
    target: [:0]const u8,
    yes: bool,
    medium: ?[:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) u8 {
    const path = disk.knownDisk(target) orelse {
        complain("{s} is not a disk tars-install knows; run tars-install alone for the list", .{target});
        return 2;
    };
    const name = disk.sysName(path);
    const bytes = sizeBytes(name) orelse {
        complain("{s} is not present on this machine", .{path});
        return 1;
    };
    const src = medium orelse {
        complain("no boot medium to copy from; boot from the TARS ISO or USB stick first", .{});
        return 1;
    };
    if (std.mem.eql(u8, src, path)) {
        complain("{s} is the boot medium; pick another disk", .{path});
        return 1;
    }

    // ── 계획 ──
    var size_buf: [16]u8 = undefined;
    var model_buf: [64]u8 = undefined;
    var state_buf: [64]u8 = undefined;
    const model = sysAttr(name, "device/model", &model_buf) orelse "-";
    say("tars-install: {s} ({s}, {s}) will be erased. it now holds: {s}\n", .{
        path, disk.formatSize(&size_buf, bytes), model, stateOf(path, medium, &state_buf),
    });
    say("  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n", .{});
    say("  p2    1 GiB  Linux       ext2   tars-config <- your settings, empty at first\n", .{});
    say("  rest unallocated\n", .{});

    if (!yes) {
        say("type YES to continue: ", .{});
        var line: [64]u8 = undefined;
        const n = linux.read(0, &line, line.len);
        if (failed(n) != null or !disk.confirmed(line[0..n])) {
            say("tars-install: not confirmed; nothing was changed.\n", .{});
            return 1;
        }
    }

    var p1_buf: [32]u8 = undefined;
    var p2_buf: [32]u8 = undefined;
    const p1 = storage.partitionName(&p1_buf, path, 1).?;
    const p2 = storage.partitionName(&p2_buf, path, 2).?;

    // ── 파티션 ──
    // --wipe-partitions always: 새 파티션 자리에 남은 옛 서명을 지운다. 이미
    // TARS가 있던 디스크에 다시 설치하면 p2 자리에 옛 ext2가 그대로 있고,
    // mke2fs가 그것을 보고 머뭇거린다.
    // 앞선 실행이 복사 도중 죽었으면(Ctrl-C) p1이 ESP_DIR에 붙은 채 남아 있고,
    // sfdisk가 "in use"로 거부한다. 게스트에 umount 명령이 없어 사람이 뗄 길이
    // 없으므로 여기서 뗀다. 안 붙어 있으면 EINVAL이고 그것이 보통의 경우다.
    _ = linux.umount(ESP_DIR.ptr);

    say("tars-install: writing the partition table\n", .{});
    const sfdisk = [_:null]?[*:0]const u8{ "/usr/bin/sfdisk", "--wipe", "always", "--wipe-partitions", "always", path };
    if (!runTool(&sfdisk, disk.SFDISK_SCRIPT, WORK_DIR ++ "/sfdisk.log", envp)) return 1;
    if (!waitForNode(p1) or !waitForNode(p2)) {
        complain("{s} and {s} never appeared after 3s", .{ p1, p2 });
        return 1;
    }

    // ── 포맷 ──
    say("tars-install: formatting {s} (FAT32, {s})\n", .{ p1, disk.ESP_LABEL });
    const mkvfat = [_:null]?[*:0]const u8{ "/usr/bin/mkfs.vfat", "-F", "32", "-n", disk.ESP_LABEL, p1 };
    if (!runTool(&mkvfat, null, WORK_DIR ++ "/mkfs.vfat.log", envp)) return 1;

    say("tars-install: formatting {s} (ext2, {s})\n", .{ p2, disk.CONFIG_LABEL });
    const mke2fs = [_:null]?[*:0]const u8{ "/usr/bin/mke2fs", "-q", "-t", "ext2", "-L", disk.CONFIG_LABEL, p2 };
    if (!runTool(&mke2fs, null, WORK_DIR ++ "/mke2fs.log", envp)) return 1;

    // ── 복사 ──
    if (!mkdirOk(ESP_DIR.ptr)) {
        complain("cannot create {s}", .{ESP_DIR});
        return 1;
    }
    if (failed(linux.mount(p1.ptr, ESP_DIR.ptr, "vfat", 0, 0))) |e| {
        complain("cannot mount {s} as vfat (errno {d})", .{ p1, @intFromEnum(e) });
        return 1;
    }
    const copied = copyAll();
    // sync가 umount보다 먼저다. 캐시에만 있는 41MB는 전원 버튼과 함께
    // 사라진다(design 위험 3). umount도 쓰기를 내보내지만 실패하면 안
    // 내보내므로 sync를 따로 부른다.
    say("tars-install: syncing\n", .{});
    linux.sync();
    if (failed(linux.umount(ESP_DIR.ptr))) |e| {
        complain("cannot unmount {s} (errno {d})", .{ ESP_DIR, @intFromEnum(e) });
        return 1;
    }
    if (!copied) return 1;

    say("tars-install: done. remove the boot medium and reboot.\n", .{});
    return 0;
}

/// 매체는 findMedium이 MEDIUM_DIR에 붙여 두었고 p1은 install이 ESP_DIR에
/// 붙였다. 여기는 두 디렉터리 사이의 일만 한다.
fn copyAll() bool {
    for (disk.ESP_DIRS) |d| {
        var buf: [128]u8 = undefined;
        const p = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ ESP_DIR, d }) catch unreachable;
        if (!mkdirOk(p.ptr)) {
            complain("cannot create {s}", .{p});
            return false;
        }
    }
    say("tars-install: copying the boot files\n", .{});
    for (disk.BOOT_FILES) |rel| {
        var from_buf: [128]u8 = undefined;
        var to_buf: [128]u8 = undefined;
        const from = std.fmt.bufPrintZ(&from_buf, "{s}/{s}", .{ MEDIUM_DIR, rel }) catch unreachable;
        const to = std.fmt.bufPrintZ(&to_buf, "{s}/{s}", .{ ESP_DIR, rel }) catch unreachable;
        const n = copyFile(from, to) orelse return false;
        say("  {s} {d} bytes\n", .{ rel, n });
    }
    return true;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    const envp = init.environ.block.slice.ptr;
    const cmd = disk.parseArgs(if (argv.len > 1) argv[1..] else argv[0..0]);
    if (cmd == .usage) {
        printUsage();
        return 2;
    }

    // 매체는 목록에도 설치에도 필요하다. 붙인 채로 돌려받고 끝에서 뗀다 —
    // 읽기 전용이라 떼는 순서가 디스크에 아무것도 안 바꾼다.
    const medium = findMedium();
    defer if (medium != null) {
        _ = linux.umount(MEDIUM_DIR.ptr);
    };

    return switch (cmd) {
        .list => blk: {
            list(medium);
            break :blk 0;
        },
        .install => |i| install(i.disk, i.yes, medium, envp),
        .usage => unreachable,
    };
}
