const std = @import("std");
const linux = std.os.linux;
const storage = @import("storage.zig");
const disk = @import("disk.zig");
const config = @import("config.zig");
const account = @import("account.zig");
const screen_args = @import("screen_args");
const build_info = @import("build_info");

/// tars-install — 부팅 매체의 부트 파일 넷을 내장 디스크에 옮겨 USB 없이
/// 뜨게 한다(DI design). 인자 없이 치면 목록, 디스크를 주면 계획을 보이고
/// YES를 받는다. `--yes`가 그 질문을 건너뛴다. 이미 TARS가 있는 디스크는
/// TARS-BOOT만 갈고 TARS-CONFIG(설정)를 남긴다. `--wipe`가 그것 대신 통째로 지운다(DI-M2).
/// `--beside`는 남의 파티션을 그대로 두고 가장 큰 빈 자리에 셋을 덧붙인다(DB-M0). TARS 파티션은
/// 번호가 아니라 GPT 이름으로 찾는다.
///
/// init 옆의 별도 실행 파일인 이유는 DI design 결정 5다 — 부팅 경로에 안
/// 들어가야 게이트의 다른 체인들에 닿지 않고, storage.zig를 같이 써야 목록에
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
/// 넘치는 줄은 잘라서라도 찍는다(disk.clip). 그대로 버리면 긴 인자를 되풀이하는
/// 에러가 말없이 사라진다(DC 결정 5의 3).
fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    writeAll(1, disk.clip(&buf, fmt, args));
}

/// 실패는 stderr로. 한 줄에 무엇이 몇으로 죽었는지가 다 있어야 한다
/// (design 결정 5).
fn complain(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    writeAll(2, disk.clip(&buf, "tars-install: " ++ fmt ++ "\n", args));
}

/// `config.zig`의 로그가 root에서 찾는 이름(TC design 결정 3의 수법). 설치기가 `config.save`로
/// p2의 `tars.conf`를 쓸 때 그 함수가 하는 말이 `tars-init:`이 아니라 `tars-install:`로 나간다.
pub fn configLog(comptime fmt: []const u8, args: anytype) void {
    say("tars-install: " ++ fmt ++ "\n", args);
}

/// `disk`의 여러 줄 함수에 주는 sink. 줄마다 `say` · `complain` 한 번 — 옮기기 전과 같은 `write`다.
const Say = struct {
    pub fn print(_: Say, comptime fmt: []const u8, args: anytype) void {
        say(fmt, args);
    }
};

const Complain = struct {
    pub fn print(_: Complain, comptime fmt: []const u8, args: anytype) void {
        complain(fmt, args);
    }
};

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
    const p = std.fmt.bufPrintSentinel(&path, "/sys/block/{s}/{s}", .{ name, attr }, 0) catch return null;
    const text = readFile(p.ptr, buf) orelse return null;
    return std.mem.trim(u8, text, " \t\r\n");
}

/// 바이트 크기(disk.sectorsToBytes).
fn sizeBytes(name: []const u8) ?u64 {
    var buf: [32]u8 = undefined;
    const text = sysAttr(name, "size", &buf) orelse return null;
    return disk.sectorsToBytes(text);
}

fn exists(path: [*:0]const u8) bool {
    return failed(linux.access(path, linux.F_OK)) == null;
}

/// 파일 크기. 끝으로 lseek한 자리다. 없거나 못 열면 null.
fn fileSize(path: [*:0]const u8) ?u64 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    const end = linux.lseek(fd, 0, linux.SEEK.END);
    if (failed(end)) |_| return null;
    return end;
}

/// x86_64의 struct statfs. 필드가 전부 8바이트인 arch/x86의 모양이다. Zig 0.17의
/// std.os.linux에는 statfs가 없어서 시스템 콜을 직접 부른다(KU-M0 plan 확정 2).
const Statfs = extern struct {
    type: i64,
    bsize: i64,
    blocks: u64,
    bfree: u64,
    bavail: u64,
    files: u64,
    ffree: u64,
    fsid: [2]i32,
    namelen: i64,
    frsize: i64,
    flags: i64,
    spare: [4]i64,
};

comptime {
    std.debug.assert(@sizeOf(Statfs) == 120);
    std.debug.assert(@offsetOf(Statfs, "bavail") == 32);
}

/// path가 있는 파일시스템에서 root가 아닌 사람이 쓸 수 있는 바이트(f_bavail).
/// FAT에는 예약 블록이 없어 bfree와 같다.
fn freeBytes(path: [*:0]const u8) ?u64 {
    var st: Statfs = undefined;
    if (failed(linux.syscall2(.statfs, @intFromPtr(path), @intFromPtr(&st)))) |_| return null;
    return st.bavail * @as(u64, @intCast(st.bsize));
}

// ── 부팅 매체 ────────────────────────────────────────────────────────

const WORK_DIR: [:0]const u8 = "/tmp/tars-install";
const MEDIUM_DIR: [:0]const u8 = "/tmp/tars-install/medium";
const ESP_DIR: [:0]const u8 = "/tmp/tars-install/esp";
/// 새 설치가 계정을 쓰려고 p2 · p3를 잠깐 붙이는 자리(HP-M1).
const CONFIG_DIR: [:0]const u8 = "/tmp/tars-install/config";
const HOME_DIR: [:0]const u8 = "/tmp/tars-install/home";

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
    const mark = std.fmt.bufPrintSentinel(&mark_buf, "{s}/{s}", .{ MEDIUM_DIR, disk.MEDIUM_MARK }, 0) catch unreachable;

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
    disk.usageLines(Say{});
}

/// 장치의 논리 섹터 크기(512 · 4096). GPT 헤더가 LBA 1에 있으므로 이것이 곧 헤더의 오프셋이다(DB design
/// 위험 2). sfdisk의 start= · size=도 이 단위다.
fn sectorSize(name: []const u8) ?u64 {
    var buf: [16]u8 = undefined;
    const text = sysAttr(name, "queue/logical_block_size", &buf) orelse return null;
    return std.fmt.parseInt(u64, text, 10) catch null;
}

/// 디스크의 GPT 엔트리(disk.parseGpt). GPT가 아니거나 CRC가 안 맞거나 섹터 크기를 모르면 null.
fn readGpt(path: [:0]const u8) ?disk.Gpt {
    var head_buf: [disk.HEAD_BYTES]u8 = undefined;
    const head = storage.readHead(path, &head_buf) orelse return null;
    if (disk.describe(head).kind != .gpt) return null;
    const sector = sectorSize(disk.sysName(path)) orelse return null;
    return disk.parseGpt(head, sector);
}

/// 디스크에 TARS가 설치돼 있는가(DI design 결정 7). 셋을 다 본다.
///
///   GPT에 `TARS-BOOT` · `TARS-CONFIG` 이름이 하나씩 있다(DB-M0 — 번호가 아니라 이름이다)
///   TARS-BOOT가 FAT32이고, 붙여 보면 boot/bzImage나 boot/old/bzImage가 있다
///   TARS-CONFIG가 `tars-` 라벨의 ext2
///
/// bzImage를 보는 것이 design 위험 4의 처방이다. sfdisk와 mkfs까지 되고
/// 복사 전에 죽은 디스크는 installed가 아니라 새 설치로 가야 한다. 그래서
/// 이 판정만은 앞머리가 아니라 TARS-BOOT를 읽기 전용으로 붙여 본다.
///
/// 통째 설치 디스크는 이름이 p1~p3에 있을 뿐 같은 길로 읽힌다(DI-M1부터 이름이 있다).
fn isInstalled(path: [:0]const u8) bool {
    const g = readGpt(path) orelse return false;
    const boot = g.find(.boot) orelse return false;
    const conf = g.find(.config) orelse return false;

    var head_buf: [disk.HEAD_BYTES]u8 = undefined;
    var p1_buf: [32]u8 = undefined;
    var p2_buf: [32]u8 = undefined;
    const p1 = storage.partitionName(&p1_buf, path, boot.number) orelse return false;
    const p2 = storage.partitionName(&p2_buf, path, conf.number) orelse return false;
    const h1 = storage.readHead(p1, &head_buf) orelse return false;
    if (!disk.isFat32(h1)) return false;
    const h2 = storage.readHead(p2, &head_buf) orelse return false;
    if (storage.tarsLabel(h2) == null) return false;

    if (!mkdirOk(WORK_DIR.ptr) or !mkdirOk(ESP_DIR.ptr)) return false;
    if (failed(linux.mount(p1.ptr, ESP_DIR.ptr, "vfat", linux.MS.RDONLY, 0)) != null) return false;
    defer _ = linux.umount(ESP_DIR.ptr);
    // 둘 중 하나면 된다(KU design 결정 6). 회전이 boot/의 셋을 boot/old/로 옮긴
    // 뒤 새 파일을 다 쓰기 전에 끊긴 디스크는 boot/bzImage가 없다 — 그 디스크가
    // 새 설치(p2 지우기)로 가면 안 된다.
    var kernel_buf: [128]u8 = undefined;
    for ([_][]const u8{ disk.NEW_DIR, disk.OLD_DIR }) |dir| {
        const kernel = slotPath(&kernel_buf, dir, "bzImage");
        if (exists(kernel.ptr)) return true;
    }
    return false;
}

/// ESP_DIR 아래 슬롯 파일의 경로. 이름이 다 짧아 128바이트를 못 넘는다.
fn slotPath(buf: []u8, dir: []const u8, file: []const u8) [:0]const u8 {
    return std.fmt.bufPrintSentinel(buf, "{s}/{s}/{s}", .{ ESP_DIR, dir, file }, 0) catch unreachable;
}

/// 갱신이 YES 전에 p1에서 읽는 것(KU-M0). 버전은 plainVersion을 통과한 것만이다 —
/// 깨진 version 파일은 "끝까지 안 써진 슬롯"과 같이 다룬다(disk.rotation).
const Slots = struct {
    cur_ver: ?[]const u8,
    old_ver: ?[]const u8,
    cur_bytes: u64,
    old_bytes: u64,
    free: u64,
};

/// p1을 읽기 전용으로 붙여 두 슬롯과 빈 자리를 읽고 뗀다. isInstalled와 같은 모양이다.
/// 버전 글자는 부르는 쪽의 버퍼에 남는다.
fn readSlots(p1: [:0]const u8, cur_buf: []u8, old_buf: []u8) ?Slots {
    if (!mkdirOk(WORK_DIR.ptr) or !mkdirOk(ESP_DIR.ptr)) {
        complain("cannot create {s}", .{ESP_DIR});
        return null;
    }
    if (failed(linux.mount(p1.ptr, ESP_DIR.ptr, "vfat", linux.MS.RDONLY, 0))) |e| {
        complain("cannot mount {s} as vfat (errno {d})", .{ p1, @backingInt(e) });
        return null;
    }
    defer _ = linux.umount(ESP_DIR.ptr);
    const free = freeBytes(ESP_DIR.ptr) orelse {
        complain("cannot read the free space on {s}", .{p1});
        return null;
    };
    return .{
        .cur_ver = slotVersion(disk.NEW_DIR, cur_buf),
        .old_ver = slotVersion(disk.OLD_DIR, old_buf),
        .cur_bytes = slotBytes(disk.NEW_DIR),
        .old_bytes = slotBytes(disk.OLD_DIR),
        .free = free,
    };
}

/// 슬롯의 version 한 줄. 없거나, buf를 채울 만큼 길거나, plainVersion이 아니면 null.
fn slotVersion(dir: []const u8, buf: []u8) ?[]const u8 {
    var path_buf: [128]u8 = undefined;
    const text = readFile(slotPath(&path_buf, dir, "version").ptr, buf) orelse return null;
    if (text.len == buf.len) return null;
    const ver = std.mem.trim(u8, text, " \t\r\n");
    return if (disk.plainVersion(ver)) ver else null;
}

/// 슬롯의 bzImage + initrd.cpio. 없는 파일은 0이다.
fn slotBytes(dir: []const u8) u64 {
    var path_buf: [128]u8 = undefined;
    var total: u64 = 0;
    for (disk.SLOT_FILES[0..2]) |f| total += fileSize(slotPath(&path_buf, dir, f).ptr) orelse 0;
    return total;
}

/// 매체의 bzImage + initrd.cpio. 갱신의 need가 여기서 온다.
fn mediumBytes() ?u64 {
    var total: u64 = 0;
    for (disk.SLOT_FILES[0..2]) |f| {
        var path_buf: [128]u8 = undefined;
        const p = std.fmt.bufPrintSentinel(&path_buf, "{s}/{s}/{s}", .{ MEDIUM_DIR, disk.NEW_DIR, f }, 0) catch unreachable;
        total += fileSize(p.ptr) orelse {
            complain("cannot read the size of {s}", .{p});
            return null;
        };
    }
    return total;
}

/// TARS-CONFIG에 `tars-` 라벨이 있으면 그 번호. 새 설치가 "설정도 지워진다"고 경고할 조건이다.
/// isInstalled보다 넓게 본다 — 갱신 도중 전원이 나가 TARS-BOOT가 망가졌거나 bzImage가
/// 없어진 디스크는 installed로 안 보이지만, 설정은 살아 있을 수 있다.
/// 그 디스크도 목록에는 GPT로만 보이므로 이 한 줄이 "알고
/// 설치한다"(design 결정 7)를 지킨다.
fn settingsOn(path: [:0]const u8, gpt: ?disk.Gpt) ?u8 {
    const g = gpt orelse return null;
    const conf = g.find(.config) orelse return null;
    var p2_buf: [32]u8 = undefined;
    const p2 = storage.partitionName(&p2_buf, path, conf.number) orelse return null;
    var head_buf: [disk.HEAD_BYTES]u8 = undefined;
    const head = storage.readHead(p2, &head_buf) orelse return null;
    return if (storage.tarsLabel(head) != null) conf.number else null;
}

/// 한 디스크의 상태 칸. 매체 · 설치됨 · 앞머리에 보이는 것 순이다.
///
/// 매체는 둘로 본다. 붙여서 확인한 것(medium)과, 볼륨 ID가 TARS인 ISO다.
/// 스틱이 둘 꽂혀 있으면 findMedium은 첫 것만 붙인다(DI-M1 실측 15).
fn stateOf(path: [:0]const u8, medium: ?[:0]const u8, buf: []u8) disk.State {
    if (medium) |m| {
        if (std.mem.eql(u8, m, path)) return .medium;
    }
    if (isInstalled(path)) return .installed;
    return headText(path, buf);
}

/// 앞머리에 보이는 것. 읽히는 GPT면 파티션과 빈 자리를 말한다(DB design 결정 9) — `GPT: EFI, macOS
/// (APFS); 6 GB free`. 통째 설치의 계획도 이 글자로 무엇을 지우는지 말한다(설치된 디스크여도).
fn headText(path: [:0]const u8, buf: []u8) disk.State {
    var head_buf: [disk.HEAD_BYTES]u8 = undefined;
    const head = storage.readHead(path, &head_buf) orelse return disk.headState(buf, null);
    const seen = disk.describe(head);
    if (seen.kind == .gpt) {
        if (sectorSize(disk.sysName(path))) |sector| {
            if (disk.parseGpt(head, sector)) |g| return .{ .other = disk.gptText(buf, &g) };
        }
    }
    return disk.headState(buf, seen);
}

fn list(medium: ?[:0]const u8) void {
    if (medium) |m| {
        var head_buf: [disk.HEAD_BYTES]u8 = undefined;
        const head = storage.readHead(m, &head_buf) orelse &[_]u8{};
        const seen = disk.describe(head);
        var size_buf: [16]u8 = undefined;
        const size = disk.formatSize(&size_buf, sizeBytes(disk.sysName(m)) orelse 0);
        var label_buf: [32]u8 = undefined;
        say("tars-install: boot medium {s} (iso9660 {s}, {s})\n", .{ m, disk.printable(&label_buf, seen.label), size });
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
        var state_buf: [128]u8 = undefined;
        const model = sysAttr(name, "device/model", &model_buf) orelse "-";
        const removable = sysAttr(name, "removable", &rem_buf) orelse "0";
        const state = disk.stateWord(stateOf(path, medium, &state_buf));
        disk.listRow(Say{}, path, disk.formatSize(&size_buf, bytes), model, removable, state);
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
            complain("pipe for {s} failed (errno {d})", .{ tool, @backingInt(e) });
            return false;
        }
    }

    const pid = linux.fork();
    if (failed(pid)) |e| {
        complain("fork for {s} failed (errno {d})", .{ tool, @backingInt(e) });
        return false;
    }
    if (pid == 0) {
        // main이 무시하게 둔 SIGPIPE를 되돌린다. 무시 상태는 execve를 넘어
        // 남아서, 그대로 두면 도구들이 끊긴 파이프에서 죽지 않고 EPIPE를
        // 다뤄야 한다 — 그 도구들이 기대하는 환경이 아니다.
        const dfl: linux.Sigaction = .{
            .handler = .{ .handler = linux.SIG.DFL },
            .mask = linux.sigemptyset(),
            .flags = 0,
        };
        _ = linux.sigaction(.PIPE, &dfl, null);
        if (input != null) {
            _ = linux.dup2(fds[0], 0);
            _ = linux.close(fds[0]);
            _ = linux.close(fds[1]);
        } else {
            const nul = linux.open("/dev/null", .{ .ACCMODE = .RDONLY }, 0);
            if (failed(nul) == null) _ = linux.dup2(@intCast(nul), 0);
        }
        // 0600: mkpasswd의 로그에는 해시가 남는다(HP-M1). 다른 도구의 로그도 사람이 읽을
        // 까닭이 root 말고는 없다.
        const out = linux.open(log.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600);
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
        const rc = linux.wait4(@intCast(pid), @ptrCast(&status), 0, null);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            complain("waiting for {s} failed (errno {d})", .{ tool, @backingInt(e) });
            return false;
        }
        break;
    }
    if (disk.toolOk(Complain{}, tool, status)) return true;
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
        complain("cannot open {s} (errno {d})", .{ src, @backingInt(e) });
        return null;
    }
    const in_fd: i32 = @intCast(in_rc);
    defer _ = linux.close(in_fd);

    const out_rc = linux.open(dst.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(out_rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ dst, @backingInt(e) });
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
            complain("reading {s} failed (errno {d})", .{ src, @backingInt(e) });
            return null;
        }
        if (n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const w = linux.write(out_fd, buf[off..].ptr, n - off);
            if (failed(w)) |e| {
                if (e == .INTR) continue;
                complain("writing {s} failed (errno {d})", .{ dst, @backingInt(e) });
                return null;
            }
            off += w;
        }
        total += n;
    }
    return total;
}

/// 매체의 limine.conf로 ESP의 conf를 짓는다(disk.espConf). 원본은 1KB 아래라
/// (DI-M0 실측 7의 908바이트) 버퍼 하나에 든다. old_ver가 있으면 old 엔트리가
/// 붙는다 — 쓰기가 끝난 뒤 boot/old/에 있을 이미지의 버전이다.
///
/// 디스크를 건드리기 전, YES를 묻기 전에 부른다 — espConf가 거부할 conf면
/// 아무것도 지우지 않고 멈춰야 한다(disk.espConf의 약속).
fn prepareConf(in_buf: []u8, out_buf: []u8, new_ver: []const u8, old_ver: ?[]const u8) ?[]const u8 {
    var src_buf: [128]u8 = undefined;
    const src = std.fmt.bufPrintSentinel(&src_buf, "{s}/{s}", .{ MEDIUM_DIR, disk.LIMINE_CONF }, 0) catch unreachable;
    const conf = readFile(src.ptr, in_buf) orelse {
        complain("cannot read {s}", .{src});
        return null;
    };
    if (conf.len == in_buf.len) {
        complain("{s} does not fit in {d} bytes", .{ src, in_buf.len });
        return null;
    }
    return disk.espConf(out_buf, conf, new_ver, old_ver) orelse {
        complain("{s} is not one entry with a timeout and a cmdline line to mark with {s}", .{ src, storage.INSTALLED_TOKEN });
        return null;
    };
}

/// prepareConf가 지은 표지 붙은 text를 dst에 그대로 쓴다. 옛 copyConf의
/// 쓰기 루프를 그대로 옮긴 것이다.
fn writeConf(dst: [:0]const u8, text: []const u8) ?u64 {
    const rc = linux.open(dst.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ dst, @backingInt(e) });
        return null;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var off: usize = 0;
    while (off < text.len) {
        const w = linux.write(fd, text[off..].ptr, text.len - off);
        if (failed(w)) |e| {
            if (e == .INTR) continue;
            complain("writing {s} failed (errno {d})", .{ dst, @backingInt(e) });
            return null;
        }
        off += w;
    }
    return text.len;
}

/// fd에서 개행까지 한 줄. 개행 없이 EOF가 오면 거기까지, 에러나 buf가 차도록
/// 개행이 없으면 null이다(너무 긴 답은 YES가 아니다).
///
/// read 한 번으로 받던 때는 입력이 파이프로 쪼개져 오면 첫 조각만 봤다.
/// `YES`와 ` please\n`로 나뉘어 오면 `YES please`를 확인으로 읽고 디스크를
/// 지웠다(DC-M2가 찾았다 — DI의 이월 목록은 "거절하는 쪽으로 틀린다"고 적었지만
/// 반대쪽도 있었다). 한 바이트씩 읽는 것은 개행 뒤의 입력을 삼키지 않기
/// 위해서다. 사람이 치는 한 줄이라 비용이 없다.
fn readLine(fd: i32, buf: []u8) ?[]const u8 {
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, 1);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return null;
        }
        if (n == 0) return buf[0..len];
        if (buf[len] == '\n') return buf[0 .. len + 1];
        len += 1;
    }
    return null;
}

// ── 계정 (HP-M1) ─────────────────────────────────────────────────────

/// 새 설치가 만들 사용자 하나. 질문의 답이거나(`askAccount`) `--yes`의 기본값이다.
/// 힙이 없어 글자를 값으로 든다.
const Account = struct {
    name_buf: [account.NAME_MAX]u8 = undefined,
    name_len: usize = 0,
    pw_buf: [account.PASSWORD_MAX]u8 = undefined,
    pw_len: usize = 0,
    default_pw: bool = true,

    fn defaults() Account {
        var a: Account = .{};
        a.setName(account.DEFAULT_NAME);
        a.setPassword(account.DEFAULT_PASSWORD);
        return a;
    }

    fn setName(self: *Account, n: []const u8) void {
        @memcpy(self.name_buf[0..n.len], n);
        self.name_len = n.len;
    }

    fn setPassword(self: *Account, pw: []const u8) void {
        @memcpy(self.pw_buf[0..pw.len], pw);
        self.pw_len = pw.len;
    }

    fn name(self: *const Account) []const u8 {
        return self.name_buf[0..self.name_len];
    }

    fn password(self: *const Account) []const u8 {
        return self.pw_buf[0..self.pw_len];
    }

    /// 해시를 만든 뒤 비밀번호를 지운다. 프로세스가 곧 끝나지만 sfdisk · mkfs를 기다리는
    /// 수십 초 동안 메모리에 둘 까닭이 없다.
    fn forgetPassword(self: *Account) void {
        @memset(&self.pw_buf, 0);
        self.pw_len = 0;
    }
};

/// 한 줄을 읽고 끝의 개행을 뗀다. EOF(아무것도 없이 끝남)면 `.eof`, 버퍼보다 길면 그 줄의
/// 나머지를 버리고 `.too_long` — 남은 글자가 다음 질문의 답으로 읽히지 않게 한다.
const Answer = union(enum) { line: []const u8, eof, too_long };

fn readAnswer(buf: []u8) Answer {
    const got = readLine(0, buf) orelse {
        var b: [1]u8 = undefined;
        while (true) {
            const n = linux.read(0, &b, 1);
            if (failed(n)) |e| {
                if (e == .INTR) continue;
                return .eof;
            }
            if (n == 0) return .eof;
            if (b[0] == '\n') return .too_long;
        }
    };
    if (got.len == 0) return .eof;
    return .{ .line = std.mem.trimEnd(u8, got, "\r\n") };
}

/// echo를 끄고 prompt를 찍은 뒤 한 줄을 읽는다. 표준 입력이 tty가 아니면(파이프) 그대로 읽는다.
/// `config_front.readSecret`과 같은 몇 줄이다 — 설치기는 그 파일을 import하지 않는다
/// (공용 모듈을 안 만드는 이 파일 머리의 규칙).
///
/// 순서가 뜻이다. echo를 먼저 끄고 prompt를 찍는다 — 거꾸로면 prompt를 보고 곧바로 친
/// 글자가 echo가 꺼지기 전에 도착해 화면에 찍힌다. 끌 때는 `.FLUSH`(prompt 전에 미리 친
/// 것은 버린다), 되돌릴 때는 `.NOW`(그 사이 친 다음 답 — YES — 를 버리지 않는다).
fn readSecretAnswer(prompt: []const u8, buf: []u8) Answer {
    var old: linux.termios = undefined;
    const tty = failed(linux.tcgetattr(0, &old)) == null;
    if (tty) {
        var quiet = old;
        quiet.lflag.ECHO = false;
        _ = linux.tcsetattr(0, .FLUSH, &quiet);
    }
    say("{s}", .{prompt});
    const a = readAnswer(buf);
    if (tty) {
        _ = linux.tcsetattr(0, .NOW, &old);
        // echo가 꺼져 있어 사람이 친 Enter가 화면에 안 나왔다. 다음 줄을 위해 대신 넘긴다.
        say("\n", .{});
    }
    return a;
}

/// 이름과 비밀번호를 묻는다(HP design 결정 5). Enter만 치면 괄호 안의 기본값이다. 규칙 밖이면
/// 이유 한 줄 뒤 같은 질문을 다시 묻는다. EOF면 null — 아무것도 안 바꾸고 끝낸다.
fn askAccount() ?Account {
    var a = Account.defaults();
    while (true) {
        say("user name [" ++ account.DEFAULT_NAME ++ "]: ", .{});
        var line: [128]u8 = undefined;
        const n = switch (readAnswer(&line)) {
            .eof => return null,
            .too_long => {
                say("tars-install: that is longer than a user name can be (up to {d})\n", .{account.NAME_MAX});
                continue;
            },
            .line => |l| std.mem.trim(u8, l, " \t"),
        };
        if (n.len == 0) break;
        if (!account.validName(n)) {
            say("tars-install: '{s}' is not a user name; use a-z, 0-9, _ and -, start with a-z or _, up to {d}, and not a system name like root\n", .{ n, account.NAME_MAX });
            continue;
        }
        a.setName(n);
        break;
    }
    while (true) {
        var line: [account.PASSWORD_MAX + 2]u8 = undefined;
        const pw = switch (readSecretAnswer("password [" ++ account.DEFAULT_PASSWORD ++ "]: ", &line)) {
            .eof => return null,
            .too_long => {
                say("tars-install: the password is too long (up to {d})\n", .{account.PASSWORD_MAX});
                continue;
            },
            .line => |l| l,
        };
        defer @memset(&line, 0);
        if (pw.len == 0) break;
        if (!account.validPassword(pw)) {
            say("tars-install: the password has a control character; type it again\n", .{});
            continue;
        }
        a.setPassword(pw);
        a.default_pw = false;
        break;
    }
    return a;
}

fn monotonicMs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / std.time.ns_per_ms;
}

/// `mkpasswd -m yescrypt -s`로 해시를 만든다(HP-M1 plan 확정 2). 비밀번호는 stdin으로만
/// 준다 — argv면 `/proc/<pid>/cmdline`에 보인다. 출력은 로그 파일로 받아 읽고 지운다.
/// YES 뒤 · sfdisk 앞에 부른다(확정 3) — 디스크를 지운 뒤에 실패하면 늦다.
fn makeHash(pw: []const u8, out: *[account.HASH_MAX]u8, envp: [*:null]const ?[*:0]const u8) ?[]const u8 {
    if (!mkdirOk(WORK_DIR.ptr)) {
        complain("cannot create {s}", .{WORK_DIR});
        return null;
    }
    var input: [account.PASSWORD_MAX + 1]u8 = undefined;
    defer @memset(&input, 0);
    @memcpy(input[0..pw.len], pw);
    input[pw.len] = '\n';

    const log = WORK_DIR ++ "/mkpasswd.log";
    defer _ = linux.unlink(log);
    const argv = [_:null]?[*:0]const u8{ "/usr/bin/mkpasswd", "-m", "yescrypt", "-s" };
    const t0 = monotonicMs();
    if (!runTool(&argv, input[0 .. pw.len + 1], log, envp)) return null;
    const ms = monotonicMs() - t0;

    var buf: [512]u8 = undefined;
    const text = readFile(log.ptr, &buf) orelse {
        complain("cannot read {s}", .{log});
        return null;
    };
    const hash = account.hashFromTool(text) orelse {
        complain("mkpasswd did not give a yescrypt hash; nothing was changed", .{});
        return null;
    };
    @memcpy(out[0..hash.len], hash);
    say("tars-install: password hashed (yescrypt) in {d}ms\n", .{ms});
    return out[0..hash.len];
}

/// 새로 구운 p2에 `tars.conf`(`user=` 포함)와 `shadow`를, p3에 홈 디렉터리를 만든다(HP design
/// 결정 5 · 7). 영속되는 계정은 이 셋이 전부이고 passwd · group은 init이 부팅마다 짓는다.
fn writeAccount(p2: [:0]const u8, p3: [:0]const u8, name: []const u8, hash: []const u8) bool {
    if (!mkdirOk(CONFIG_DIR.ptr) or !mkdirOk(HOME_DIR.ptr)) {
        complain("cannot create {s} or {s}", .{ CONFIG_DIR, HOME_DIR });
        return false;
    }

    if (failed(linux.mount(p2.ptr, CONFIG_DIR.ptr, "ext2", 0, 0))) |e| {
        complain("cannot mount {s} as ext2 (errno {d})", .{ p2, @backingInt(e) });
        return false;
    }
    const settings = writeSettings(name, hash);
    linux.sync();
    _ = linux.umount(CONFIG_DIR.ptr);
    if (!settings) return false;

    if (failed(linux.mount(p3.ptr, HOME_DIR.ptr, "ext4", 0, 0))) |e| {
        complain("cannot mount {s} as ext4 (errno {d})", .{ p3, @backingInt(e) });
        return false;
    }
    const home = makeHome(name);
    linux.sync();
    _ = linux.umount(HOME_DIR.ptr);
    return home;
}

fn writeSettings(name: []const u8, hash: []const u8) bool {
    const user = config.User.parse(name) orelse {
        complain("'{s}' is not a user name", .{name});
        return false;
    };
    config.save(CONFIG_DIR ++ "/tars.conf", .{ .user = user }) catch return false;

    var line_buf: [account.NAME_MAX + account.HASH_MAX + 4]u8 = undefined;
    const line = account.storeLine(&line_buf, name, hash) orelse {
        complain("the shadow line for {s} does not fit", .{name});
        return false;
    };
    const shadow = CONFIG_DIR ++ "/shadow";
    // 0600 root. 해시는 root만 읽는다 — init이 부팅마다 /etc/shadow로 옮긴다.
    const rc = linux.open(shadow.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, 0o600);
    if (failed(rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ shadow, @backingInt(e) });
        return false;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    writeAll(fd, line);
    say("tars-install: wrote tars.conf (user={s}) and shadow\n", .{name});
    return true;
}

fn makeHome(name: []const u8) bool {
    var buf: [HOME_DIR.len + account.NAME_MAX + 2]u8 = undefined;
    const dir = std.fmt.bufPrintSentinel(&buf, "{s}/{s}", .{ HOME_DIR, name }, 0) catch unreachable;
    if (failed(linux.mkdir(dir.ptr, 0o700))) |e| {
        complain("cannot create /home/{s} (errno {d})", .{ name, @backingInt(e) });
        return false;
    }
    if (failed(linux.chown(dir.ptr, screen_args.USER_UID, screen_args.USER_GID))) |e| {
        complain("cannot give /home/{s} to uid {d} (errno {d})", .{ name, screen_args.USER_UID, @backingInt(e) });
        return false;
    }
    say("tars-install: made /home/{s}\n", .{name});
    return true;
}

// ── 설치 ─────────────────────────────────────────────────────────────

fn install(
    target: [:0]const u8,
    yes: bool,
    wipe: bool,
    beside: bool,
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
    if (medium == null) {
        complain("no boot medium to copy from; boot from the TARS ISO or USB stick first", .{});
        return 1;
    }

    var size_buf: [16]u8 = undefined;
    var model_buf: [64]u8 = undefined;
    var state_buf: [128]u8 = undefined;
    const model = sysAttr(name, "device/model", &model_buf) orelse "-";
    const state = stateOf(path, medium, &state_buf);
    if (state == .medium) {
        complain("{s} is a TARS boot medium; pick another disk", .{path});
        return 1;
    }
    const installed = state == .installed;
    // 설치된 디스크에 --wipe가 없으면 갱신이다(design 결정 8). `--beside`가 있어도 같다(DB design
    // 결정 6). 설치 안 된 디스크의 --wipe는 뜻이 없다 — 어차피 통째로 지운다.
    const update = installed and !wipe;
    // 남의 파티션 옆에 새로 깐다(DB-M0). `--beside --wipe`는 TARS 이름의 셋만 지우고 그 자리에 다시 깐다.
    const beside_new = beside and !update;

    // 지금 디스크의 GPT. 갱신은 여기서 번호를 찾고, `--beside`는 빈 자리를 고른다. 통째 설치의 계획은
    // holds로 무엇을 지우는지 말한다 — 설치된 디스크여도 `TARS installed`가 아니라 그 안의 파티션이다
    // (DB design 결정 7 · 9). macOS 옆에 깔린 디스크를 `--wipe`로 통째 지우면 macOS가 사라진다.
    const gpt = readGpt(path);
    var holds_buf: [128]u8 = undefined;
    const holds = disk.stateWord(headText(path, &holds_buf));
    const size_text = disk.formatSize(&size_buf, bytes);

    // ── YES 전의 판단 (KU-M0, DB-M0) ──
    // 디스크를 건드리기 전에 다 정한다. 새 설치는 배치가 들어가는가, 갱신은
    // TARS-BOOT에 새 이미지가 들어갈 자리가 있는가와 old로 무엇이 남는가.
    const new_ver: []const u8 = build_info.version;
    var layout: disk.Layout = undefined;
    var gap: disk.Gap = undefined;
    // sfdisk가 매길 번호. 통째 설치는 늘 1 · 2 · 3이다.
    var nums: [3]u8 = .{ 1, 2, 3 };
    // `--beside --wipe`가 먼저 지울 TARS 파티션. 이름이 같은 것이 셋보다 많으면 거절한다(아래).
    var wipe_buf: [3]u8 = undefined;
    var wipe_nums: []const u8 = &.{};
    if (beside_new) {
        const g = gpt orelse {
            if (std.mem.startsWith(u8, holds, "foreign (gpt")) {
                complain("cannot read the GPT partition entries of {s}; nothing was changed", .{path});
            } else {
                complain("--beside needs a GPT disk; {s} holds {s}. leave out --beside to give TARS the whole disk", .{ path, holds });
            }
            return 1;
        };
        // 이름은 있는데 설치가 아닌 디스크 — sfdisk 뒤에 mkfs나 복사가 끊겼다. 그 위에 셋을 더 붙이면 이름이
        // 둘씩 되어 어느 것이 우리 것인지 모른다(disk.Gpt.find).
        if (!wipe and g.hasTars()) {
            complain("{s} has TARS partitions that are not a whole install; tars-install {s} --beside --wipe replaces them", .{ path, path });
            return 1;
        }
        if (wipe) {
            var n: usize = 0;
            for (g.slice()) |p| {
                if (p.role == .none) continue;
                if (n == wipe_buf.len) {
                    complain("{s} has more than three TARS partitions; nothing was changed", .{path});
                    return 1;
                }
                wipe_buf[n] = p.number;
                n += 1;
            }
            wipe_nums = wipe_buf[0..n];
        }
        gap = disk.largestGap(&g, wipe) orelse .{ .start = 0, .end = 0 };
        layout = disk.besideLayout(gap, g.sector) orelse {
            disk.roomRefusal(Complain{}, path, &g, gap.bytes(g.sector));
            return 1;
        };
        nums = disk.freeNumbers(&g, wipe) orelse {
            complain("{s} has no three free GPT entries; nothing was changed", .{path});
            return 1;
        };
    } else if (!update and !disk.bigEnough(bytes)) {
        complain("{s} is {s}; TARS needs " ++ disk.MIN_DISK_WORDS, .{ path, size_text });
        return 1;
    }

    var cur_buf: [72]u8 = undefined;
    var old_buf: [72]u8 = undefined;
    var rot: disk.Rotation = .rotate;
    var cur_ver: ?[]const u8 = null;
    // 쓰기가 끝난 뒤 boot/old/에 있을 이미지의 버전. 이것이 있어야 old 엔트리가 생긴다.
    var old_after: ?[]const u8 = null;
    var esp_buf: [32]u8 = undefined;
    var on_beside = false;
    if (update) {
        // isInstalled가 방금 이 이름으로 판정했다. 그 사이 디스크가 바뀌었으면 여기서 멈춘다.
        const g = gpt orelse {
            complain("cannot read the GPT of {s} again; nothing was changed", .{path});
            return 1;
        };
        const boot = g.find(.boot) orelse return 1;
        const conf = g.find(.config) orelse return 1;
        nums = .{ boot.number, conf.number, if (g.find(.home)) |h| h.number else 0 };
        on_beside = g.hasOthers();
        const esp = storage.partitionName(&esp_buf, path, boot.number) orelse return 1;
        const slots = readSlots(esp, &cur_buf, &old_buf) orelse return 1;
        const need = (mediumBytes() orelse return 1) + disk.NEED_SLACK;
        rot = disk.rotation(slots.cur_ver != null, slots.free, slots.old_bytes, slots.cur_bytes, need);
        disk.roomLines(Say{}, boot.number, slots.free, slots.old_bytes, need, rot);
        if (rot == .no_room) return 1;
        cur_ver = slots.cur_ver;
        old_after = if (rot == .rotate) slots.cur_ver else slots.old_ver;
    }

    // 지을 수 있는 conf인지 먼저 본다. 디스크를 지운 뒤에 알면 늦다.
    var conf_in: [8192]u8 = undefined;
    var conf_out: [2 * 8192]u8 = undefined;
    const esp_conf = prepareConf(&conf_in, &conf_out, new_ver, old_after) orelse return 1;

    // ── 계획 ──
    if (beside_new) {
        disk.besideLines(Say{}, path, size_text, model, holds, gap, gpt.?.sector, nums, wipe_nums);
    } else {
        // 설정 파티션은 새 설치일 때만 읽는다(HC-M2 plan 확정 3).
        const settings = if (update) null else settingsOn(path, gpt);
        disk.planLines(Say{}, update, path, size_text, model, if (update) disk.stateWord(state) else holds, settings, nums, on_beside, new_ver, cur_ver, rot);
    }

    // ── 계정 (HP-M1) ──
    // 새 설치만 묻는다. 갱신은 설정 · 홈을 안 열므로(design 결정 10) 물을 것이 없다.
    var acct = Account.defaults();
    if (!update) {
        if (!yes) acct = askAccount() orelse {
            say("tars-install: not confirmed; nothing was changed.\n", .{});
            return 1;
        };
        disk.userLine(Say{}, acct.name(), acct.default_pw);
    }

    if (!yes) {
        say("type YES to continue: ", .{});
        var line: [64]u8 = undefined;
        const got = readLine(0, &line);
        if (got == null or !disk.confirmed(got.?)) {
            say("tars-install: not confirmed; nothing was changed.\n", .{});
            return 1;
        }
    }

    if (update) {
        const esp = storage.partitionName(&esp_buf, path, nums[0]) orelse return 1;
        if (!fillEsp(esp, esp_conf, new_ver, rot == .rotate)) return 1;
        say("tars-install: updated. remove the boot medium and reboot.\n", .{});
        return 0;
    }

    // ── 해시 (HP-M1 plan 확정 3) ──
    var hash_buf: [account.HASH_MAX]u8 = undefined;
    const hash = makeHash(acct.password(), &hash_buf, envp) orelse return 1;
    acct.forgetPassword();

    // ── 파티션 ──
    if (beside_new) {
        if (!besidePartitions(path, layout, wipe_nums, envp)) return 1;
    } else {
        // --wipe-partitions always: 새 파티션 자리에 남은 옛 서명을 지운다. 이미
        // TARS가 있던 디스크에 다시 설치하면 p2 자리에 옛 ext2가 그대로 있고,
        // mke2fs가 그것을 보고 머뭇거린다.
        say("tars-install: writing the partition table\n", .{});
        const sfdisk = [_:null]?[*:0]const u8{ "/usr/bin/sfdisk", "--wipe", "always", "--wipe-partitions", "always", path };
        if (!runTool(&sfdisk, disk.SFDISK_SCRIPT, WORK_DIR ++ "/sfdisk.log", envp)) return 1;
    }

    // sfdisk가 쓴 표를 다시 읽어 이름으로 번호를 찾는다(DB design 결정 4). 통째 설치는 1 · 2 · 3이고
    // `--beside`는 sfdisk가 매긴 빈 엔트리다. 여기서부터는 포맷이라, 찾은 자리가 계획과 다르면 멈춘다.
    const after = readGpt(path) orelse {
        complain("cannot read the GPT of {s} back after sfdisk; nothing was formatted", .{path});
        return 1;
    };
    const roles = [3]disk.Role{ .boot, .config, .home };
    var parts: [3]disk.Part = undefined;
    for (roles, 0..) |role, i| {
        parts[i] = after.find(role) orelse {
            complain("sfdisk left no single {s} partition on {s}; nothing was formatted", .{ @tagName(role), path });
            return 1;
        };
    }
    if (beside_new) {
        const want = [3]disk.Range{ layout.boot, layout.config, layout.home };
        for (parts, want) |p, w| {
            if (p.first != w.start or p.last + 1 != w.start + w.size) {
                complain("sfdisk put p{d} at sectors {d}-{d}, not {d}-{d} as planned; nothing was formatted", .{
                    p.number, p.first, p.last, w.start, w.start + w.size - 1,
                });
                return 1;
            }
        }
    }

    var p1_buf: [32]u8 = undefined;
    var p2_buf: [32]u8 = undefined;
    var p3_buf: [32]u8 = undefined;
    const p1 = storage.partitionName(&p1_buf, path, parts[0].number) orelse return 1;
    const p2 = storage.partitionName(&p2_buf, path, parts[1].number) orelse return 1;
    const p3 = storage.partitionName(&p3_buf, path, parts[2].number) orelse return 1;
    if (!waitForNode(p1) or !waitForNode(p2) or !waitForNode(p3)) {
        complain("{s}, {s} and {s} never appeared after 3s", .{ p1, p2, p3 });
        return 1;
    }
    // 노드가 GPT의 그 자리를 가리키는가. 커널이 표를 다시 못 읽었으면 노드는 옛 표의 것이다 — 그 노드에
    // mkfs를 하면 남의 파티션을 지운다.
    for (parts, [3][:0]const u8{ p1, p2, p3 }) |p, node| {
        if (!nodeAt(name, node, p.first * after.sector)) return 1;
    }

    // ── 포맷 ──
    say("tars-install: formatting {s} (FAT32, {s})\n", .{ p1, disk.ESP_LABEL });
    const mkvfat = [_:null]?[*:0]const u8{ "/usr/bin/mkfs.vfat", "-F", "32", "-n", disk.ESP_LABEL, p1 };
    if (!runTool(&mkvfat, null, WORK_DIR ++ "/mkfs.vfat.log", envp)) return 1;

    say("tars-install: formatting {s} (ext2, {s})\n", .{ p2, disk.CONFIG_LABEL });
    const mke2fs = [_:null]?[*:0]const u8{ "/usr/bin/mke2fs", "-q", "-t", "ext2", "-L", disk.CONFIG_LABEL, p2 };
    if (!runTool(&mke2fs, null, WORK_DIR ++ "/mke2fs.log", envp)) return 1;

    // p3는 ext4다(HP design 결정 1) — 홈과 패키지 매니저의 자리라 파일이 많고
    // 쓰기가 잦아 저널이 값을 한다. `-e remount-ro`는 superblock의 오류 동작이라
    // init이 마운트 옵션 문자열을 안 넘겨도 된다. initrd에 /etc/mke2fs.conf가
    // 없어서 -t ext4의 feature 목록은 e2fsprogs의 내장 기본값이다(HP-M0 실측 3).
    say("tars-install: formatting {s} (ext4, {s})\n", .{ p3, disk.HOME_LABEL });
    const mkext4 = [_:null]?[*:0]const u8{ "/usr/bin/mke2fs", "-q", "-t", "ext4", "-e", "remount-ro", "-L", disk.HOME_LABEL, p3 };
    if (!runTool(&mkext4, null, WORK_DIR ++ "/mke2fs-home.log", envp)) return 1;

    // 계정. 여기서 실패한 디스크는 파티션만 있고 ESP가 비어 TARS로 안 보인다 — 다시 치면
    // 새 설치로 처음부터 간다(`--beside`는 TARS 이름이 남아 있어 `--beside --wipe`로).
    if (!writeAccount(p2, p3, acct.name(), hash)) {
        complain("the account was not written; run tars-install {s}{s} again", .{ path, if (beside_new) " --beside --wipe" else "" });
        return 1;
    }

    if (!fillEsp(p1, esp_conf, new_ver, false)) return 1;
    say("tars-install: done. remove the boot medium and reboot.\n", .{});
    return 0;
}

/// `--beside`의 파티션(DB design 결정 4 · 7). `--beside --wipe`면 먼저 TARS 파티션만 `sfdisk --delete`로
/// 지우고, 세 줄을 `--append`로 덧붙인다.
///
/// `--wipe always`는 안 쓴다 — 디스크 머리의 서명(보호 MBR · GPT)을 지우는 옵션이라 남의 표를 다시 쓰게
/// 된다. `--wipe never`로 그 기본값(auto)도 막는다. `--wipe-partitions always`는 새 파티션 자리의 옛
/// 서명만 지운다(`--beside --wipe`가 지운 옛 tars-config가 거기 있다). sfdisk는 남의 파티션과 겹치는
/// start=를 `Sector N already used`로 거절한다(DB-M0 plan 착수 전 3) — 우리 계산이 틀려도 마지막 문이다.
fn besidePartitions(path: [:0]const u8, layout: disk.Layout, wipe_nums: []const u8, envp: [*:null]const ?[*:0]const u8) bool {
    if (wipe_nums.len > 0) {
        say("tars-install: deleting the TARS partitions", .{});
        for (wipe_nums) |n| say(" p{d}", .{n});
        say("\n", .{});
        var num_text: [3][4]u8 = undefined;
        var argv = [_:null]?[*:0]const u8{ "/usr/bin/sfdisk", "--delete", path, null, null, null };
        for (wipe_nums, 0..) |n, i| {
            argv[3 + i] = (std.fmt.bufPrintSentinel(&num_text[i], "{d}", .{n}, 0) catch unreachable).ptr;
        }
        if (!runTool(&argv, null, WORK_DIR ++ "/sfdisk-delete.log", envp)) return false;
    }
    var script_buf: [512]u8 = undefined;
    const script = disk.appendScript(&script_buf, layout) orelse return false;
    say("tars-install: adding the TARS partitions to the partition table\n", .{});
    const sfdisk = [_:null]?[*:0]const u8{ "/usr/bin/sfdisk", "--append", "--wipe", "never", "--wipe-partitions", "always", path };
    return runTool(&sfdisk, script, WORK_DIR ++ "/sfdisk.log", envp);
}

/// 커널의 파티션 노드가 디스크의 byte_off에서 시작하는가. /sys/block/<disk>/<part>/start는 512바이트
/// 단위다(섹터 크기와 무관 — sectorsToBytes와 같은 규칙).
fn nodeAt(disk_name: []const u8, node: [:0]const u8, byte_off: u64) bool {
    var attr_buf: [64]u8 = undefined;
    const attr = std.fmt.bufPrint(&attr_buf, "{s}/start", .{disk.sysName(node)}) catch return false;
    var buf: [32]u8 = undefined;
    const text = sysAttr(disk_name, attr, &buf) orelse {
        complain("cannot read where the kernel put {s}; nothing was formatted", .{node});
        return false;
    };
    const start = disk.sectorsToBytes(text) orelse 0;
    if (start != byte_off) {
        complain("the kernel has {s} at byte {d}, the GPT says {d}; nothing was formatted", .{ node, start, byte_off });
        return false;
    }
    return true;
}

/// p1을 붙이고 쓰고 sync하고 뗀다. 새 설치와 갱신이 같은 입구다 — 갱신은
/// 이 앞의 sfdisk와 mkfs를 건너뛸 뿐이다.
///
/// rotate면 disk.ROTATION을 돈다(KU design 결정 4). 지금 이미지를 boot/old/로
/// 보내고 새 것을 쓰므로, 도중에 끊겨도 메뉴에서 뜨는 엔트리가 하나는 남는다.
/// 아니면 boot/의 파일을 제자리에서 덮는다(O_TRUNC). 새 설치와, 지금 이미지에
/// version이 없는 갱신(끝까지 안 써졌거나 슬롯 전에 깔린 것 — 결정 5)이다.
/// 어느 쪽이든 boot/version을 맨 마지막에 쓴다.
fn fillEsp(p1: [:0]const u8, esp_conf: []const u8, new_ver: []const u8, rotate: bool) bool {
    if (!mkdirOk(ESP_DIR.ptr)) {
        complain("cannot create {s}", .{ESP_DIR});
        return false;
    }
    if (failed(linux.mount(p1.ptr, ESP_DIR.ptr, "vfat", 0, 0))) |e| {
        complain("cannot mount {s} as vfat (errno {d})", .{ p1, @backingInt(e) });
        return false;
    }
    const written = makeDirs() and (if (rotate) rotateAll(esp_conf, new_ver) else copyAll(esp_conf) and writeVersion(new_ver));
    // sync가 umount보다 먼저다. 캐시에만 있는 41MB는 전원 버튼과 함께
    // 사라진다(design 위험 3). umount도 쓰기를 내보내지만 실패하면 안
    // 내보내므로 sync를 따로 부른다.
    say("tars-install: syncing\n", .{});
    linux.sync();
    if (failed(linux.umount(ESP_DIR.ptr))) |e| {
        complain("cannot unmount {s} (errno {d})", .{ ESP_DIR, @backingInt(e) });
        return false;
    }
    return written;
}

fn makeDirs() bool {
    for (disk.ESP_DIRS) |d| {
        var buf: [128]u8 = undefined;
        const p = std.fmt.bufPrintSentinel(&buf, "{s}/{s}", .{ ESP_DIR, d }, 0) catch unreachable;
        if (!mkdirOk(p.ptr)) {
            complain("cannot create {s}", .{p});
            return false;
        }
    }
    return true;
}

/// 매체는 findMedium이 MEDIUM_DIR에 붙여 두었고 p1은 install이 ESP_DIR에
/// 붙였다. limine.conf는 esp_conf(디스크를 건드리기 전에 prepareConf가 이미
/// 지어 둔 text)를 그대로 쓰고, 나머지 셋만 두 디렉터리 사이에서 바이트 그대로
/// 옮긴다.
fn copyAll(esp_conf: []const u8) bool {
    say("tars-install: copying the boot files\n", .{});
    for (disk.BOOT_FILES) |rel| {
        const ok = if (std.mem.eql(u8, rel, disk.LIMINE_CONF)) writeEspConf(esp_conf, false) else copyFromMedium(rel);
        if (!ok) return false;
    }
    return true;
}

/// 매체의 rel을 ESP의 같은 자리로. 쓴 크기를 한 줄 찍는다(판정 5 · 12가 센다).
fn copyFromMedium(rel: []const u8) bool {
    var from_buf: [128]u8 = undefined;
    var to_buf: [128]u8 = undefined;
    const from = std.fmt.bufPrintSentinel(&from_buf, "{s}/{s}", .{ MEDIUM_DIR, rel }, 0) catch unreachable;
    const to = std.fmt.bufPrintSentinel(&to_buf, "{s}/{s}", .{ ESP_DIR, rel }, 0) catch unreachable;
    const n = copyFile(from, to) orelse return false;
    say("  {s} {d} bytes\n", .{ rel, n });
    return true;
}

/// ESP의 limine.conf. via_tmp면 `.tmp`에 쓰고 rename한다 — 회전 도중 conf가
/// 반쪽인 순간이 없게. vfat의 rename은 있는 이름 위로 덮는다(KU-M0 plan Task 2
/// 결과 절에 실제 동작을 적는다).
fn writeEspConf(esp_conf: []const u8, via_tmp: bool) bool {
    var to_buf: [128]u8 = undefined;
    const to = std.fmt.bufPrintSentinel(&to_buf, "{s}/{s}", .{ ESP_DIR, disk.LIMINE_CONF }, 0) catch unreachable;
    if (!via_tmp) {
        const n = writeConf(to, esp_conf) orelse return false;
        say("  {s} {d} bytes\n", .{ disk.LIMINE_CONF, n });
        return true;
    }
    var tmp_buf: [128]u8 = undefined;
    const tmp = std.fmt.bufPrintSentinel(&tmp_buf, "{s}.tmp", .{to}, 0) catch unreachable;
    const n = writeConf(tmp, esp_conf) orelse return false;
    if (failed(linux.rename(tmp.ptr, to.ptr))) |e| {
        complain("cannot rename {s} to {s} (errno {d})", .{ tmp, to, @backingInt(e) });
        return false;
    }
    say("  {s} {d} bytes\n", .{ disk.LIMINE_CONF, n });
    return true;
}

/// boot/version — 이 슬롯은 끝까지 써졌다는 표지(KU design 결정 5). 늘 맨 마지막이다.
fn writeVersion(ver: []const u8) bool {
    var text_buf: [80]u8 = undefined;
    const text = std.fmt.bufPrint(&text_buf, "{s}\n", .{ver}) catch unreachable;
    var path_buf: [128]u8 = undefined;
    const n = writeConf(slotPath(&path_buf, disk.NEW_DIR, "version"), text) orelse return false;
    say("  {s}/version {d} bytes\n", .{ disk.NEW_DIR, n });
    return true;
}

// ── 회전 (KU-M0) ─────────────────────────────────────────────────────

/// disk.ROTATION을 순서 그대로 돈다. op마다 sync해서 캐시가 순서를 뒤섞지 않게
/// 한다 — 결정 4의 "어느 순간에 끊겨도"는 디스크에 닿은 순서에 대한 말이다.
fn rotateAll(esp_conf: []const u8, new_ver: []const u8) bool {
    for (disk.ROTATION) |op| {
        const ok = switch (op) {
            .clear_old => clearOld(),
            .write_conf => writeEspConf(esp_conf, true),
            .move_to_old => moveToOld(),
            .copy_new => copyNew(),
            .write_version => writeVersion(new_ver),
        };
        if (!ok) return false;
        linux.sync();
    }
    return true;
}

/// boot/old/의 셋을 지운다. 없는 것은 넘어간다(첫 회전에는 비어 있다).
fn clearOld() bool {
    for (disk.SLOT_FILES) |f| {
        var buf: [128]u8 = undefined;
        const p = slotPath(&buf, disk.OLD_DIR, f);
        if (failed(linux.unlink(p.ptr))) |e| {
            if (e == .NOENT) continue;
            complain("cannot remove {s} (errno {d})", .{ p, @backingInt(e) });
            return false;
        }
    }
    return true;
}

/// boot/의 셋을 boot/old/로. 같은 파일시스템 안의 rename이라 복사가 없다.
/// rotate는 boot/version이 있을 때만 오므로 셋이 다 있어야 한다.
fn moveToOld() bool {
    say("tars-install: moving the current image to {s}\n", .{disk.OLD_DIR});
    for (disk.SLOT_FILES) |f| {
        var from_buf: [128]u8 = undefined;
        var to_buf: [128]u8 = undefined;
        const from = slotPath(&from_buf, disk.NEW_DIR, f);
        const to = slotPath(&to_buf, disk.OLD_DIR, f);
        if (failed(linux.rename(from.ptr, to.ptr))) |e| {
            complain("cannot move {s} to {s} (errno {d})", .{ from, to, @backingInt(e) });
            return false;
        }
        say("  {s}/{s} -> {s}/{s}\n", .{ disk.NEW_DIR, f, disk.OLD_DIR, f });
    }
    return true;
}

/// 매체의 커널 · initrd와 EFI 로더를 쓴다. 로더도 이 자리에서 덮는다 — 새 ISO의
/// Limine 판이 다를 수 있다. 로더는 슬롯이 아니라 한 벌뿐이다.
fn copyNew() bool {
    say("tars-install: copying the boot files\n", .{});
    for (disk.BOOT_FILES) |rel| {
        if (std.mem.eql(u8, rel, disk.LIMINE_CONF)) continue;
        if (!copyFromMedium(rel)) return false;
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

    // SIGPIPE를 무시한다. sfdisk가 배치를 읽기 전에 죽으면 runTool의 write가
    // 끊긴 파이프에 쓰고, 기본 동작이면 tars-install이 그 자리에서 말없이
    // 죽는다(DI-M1 실측 15). 무시하면 write가 EPIPE로 돌아오고, 그 뒤의
    // wait4가 sfdisk가 무엇으로 죽었는지를 찍는다. SIG_IGN은 execve를 넘어
    // 자식에게 남으므로 fork한 자식에서는 기본값으로 되돌린다(runTool).
    const ignore: linux.Sigaction = .{
        .handler = .{ .handler = linux.SIG.IGN },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    _ = linux.sigaction(.PIPE, &ignore, null);

    // 앞선 실행이 복사 도중 죽었으면(Ctrl-C) p1이 ESP_DIR에 붙은 채 남아
    // 있다. 게스트에 umount 명령이 없어 사람이 뗄 길이 없으므로 여기서 뗀다.
    // 안 붙어 있으면 EINVAL이고 그것이 보통의 경우다. 목록보다 먼저인 것은
    // isInstalled가 같은 자리에 p1을 붙여 보기 때문이고, 설치보다 먼저인 것은
    // 남은 마운트가 있으면 sfdisk가 "in use"로 거부하기 때문이다(DI-M1 271fe17).
    // 매체 자리도 같은 이유로 뗀다 — 남은 매체 위에 findMedium이 한 겹 더
    // 붙이지 않게.
    _ = linux.umount(ESP_DIR.ptr);
    _ = linux.umount(MEDIUM_DIR.ptr);

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
        .install => |i| install(i.disk, i.yes, i.wipe, i.beside, medium, envp),
        .usage => unreachable,
    };
}
