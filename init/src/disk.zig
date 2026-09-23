const std = @import("std");
const storage = @import("storage.zig");

/// tars-install이 시스템 콜 없이 정하는 것들. 디스크 앞머리를 읽고 무엇이
/// 보이는지 말하는 것 · 크기를 사람이 읽는 수로 바꾸는 것 · 인자를 읽는 것.
///
/// install.zig와 가른 이유는 storage.zig가 tarsLabel과 findConfigDisk를 가른
/// 것과 같다 — 순수한 쪽은 disk_test가 호스트에서 0.1초에 본다. 시스템 콜을
/// 하는 쪽은 install 체인이 OVMF 부팅으로 본다.

/// 앞머리를 이만큼 읽는다. ISO9660의 primary volume descriptor가 오프셋
/// 32768(섹터 16)에서 시작하고 2048바이트다. ext2 superblock(1024~2047)과
/// GPT 헤더(512)와 MBR 서명(510)은 전부 그 앞에 든다.
pub const HEAD_BYTES: usize = 32768 + 2048;

const ISO_PVD: usize = 32768;
const ISO_ID_LEN: usize = 32; // volume identifier, 오프셋 40, 공백으로 채운다
const GPT_SIG_OFF: usize = 512;

pub const Kind = enum { blank, iso9660, ext2, gpt, mbr, unknown };

/// 디스크에서 보이는 것. label은 head 안을 가리킨다 — ISO면 볼륨 ID, ext2면
/// 라벨, 나머지는 빈 문자열이다.
pub const Seen = struct {
    kind: Kind,
    label: []const u8 = "",
};

/// 앞머리에 무엇이 보이는가. 순서가 뜻이 있다.
///
///   iso9660이 첫째다. 하이브리드 ISO는 MBR 서명도 갖고 있어서(make_iso.sh의
///   --protective-msdos-label) MBR을 먼저 보면 USB 스틱의 ISO가 "mbr"로 읽힌다.
///   ext2가 GPT보다 먼저다. 둘은 겹치지 않지만(GPT 디스크의 1080은 첫 파티션
///   항목의 이름 자리다) 파티션 없는 ext2가 게이트 디스크의 모양이라 먼저 둔다.
///   blank는 끝에서 둘째다. 다 0이면 어떤 서명도 안 맞았다는 뜻이다.
pub fn describe(head: []const u8) Seen {
    if (head.len >= ISO_PVD + 40 + ISO_ID_LEN and head[ISO_PVD] == 1 and
        std.mem.eql(u8, head[ISO_PVD + 1 ..][0..5], "CD001"))
    {
        const id = head[ISO_PVD + 40 ..][0..ISO_ID_LEN];
        return .{ .kind = .iso9660, .label = std.mem.trimEnd(u8, id, " ") };
    }
    if (storage.ext2Label(head)) |label| return .{ .kind = .ext2, .label = label };
    if (head.len >= GPT_SIG_OFF + 8 and std.mem.eql(u8, head[GPT_SIG_OFF..][0..8], "EFI PART")) {
        return .{ .kind = .gpt };
    }
    if (head.len >= 512 and head[510] == 0x55 and head[511] == 0xAA) return .{ .kind = .mbr };
    for (head) |b| {
        if (b != 0) return .{ .kind = .unknown };
    }
    return .{ .kind = .blank };
}

/// 라벨을 화면에 찍을 모양으로. 제어 문자(0x00~0x1f · 0x7f)는 `?`로 바꾼다 —
/// 라벨은 디스크에 있는 바이트라 누구든 ESC를 심을 수 있고, 그대로 찍으면
/// 목록이 터미널을 조종한다(DI-M1 실측 15). 0x80 위는 그대로 둔다. UTF-8
/// 라벨이 깨지지 않게 하기 위해서다. C1 제어 문자(0x80~0x9f)는 거르지 않는다
/// — UTF-8을 지키는 대가다. buf보다 긴 부분은 자른다.
pub fn printable(buf: []u8, text: []const u8) []const u8 {
    const n = @min(buf.len, text.len);
    for (text[0..n], 0..) |c, i| buf[i] = if (c < 0x20 or c == 0x7f) '?' else c;
    return buf[0..n];
}

/// 목록의 상태 칸. 지울 내용을 한 단어라도 보여 주는 것이 "알고 설치한다"의
/// 최소다(DI design 결정 7).
pub fn stateText(buf: []u8, seen: Seen) []const u8 {
    const what: []const u8 = switch (seen.kind) {
        .blank => return "blank",
        .iso9660 => "iso9660",
        .ext2 => "ext2",
        .gpt => "gpt",
        .mbr => "mbr",
        .unknown => "unknown data",
    };
    if (seen.label.len == 0) {
        return std.fmt.bufPrint(buf, "foreign ({s})", .{what}) catch "foreign";
    }
    var label_buf: [ISO_ID_LEN]u8 = undefined;
    const label = printable(&label_buf, seen.label);
    return std.fmt.bufPrint(buf, "foreign ({s} {s})", .{ what, label }) catch "foreign";
}

/// ISO의 볼륨 ID. boot/make_iso.sh의 `-V TARS`와 같아야 한다.
pub const MEDIUM_VOLUME: []const u8 = "TARS";

/// 앞머리가 TARS의 부팅 매체인가. 붙여서 확인한 매체(findMedium)는 하나뿐인데
/// TARS를 구운 스틱이 둘 꽂혀 있으면 나머지 하나가 설치 대상으로 보인다
/// (DI-M1 실측 15). 그것도 대상에서 빼려고 볼륨 ID로 한 번 더 본다.
pub fn isTarsMedium(seen: Seen) bool {
    return seen.kind == .iso9660 and std.mem.eql(u8, seen.label, MEDIUM_VOLUME);
}

/// p1의 앞머리가 FAT32 부트 섹터인가. mkfs.fat이 오프셋 82(BS_FilSysType)에
/// "FAT32   "을, 510에 55 AA를 쓴다. 82의 여덟 글자는 FAT 규격상 참고용이지만
/// 우리가 판정하는 것은 "tars-install이 만든 p1인가"이고 그것을 만든 것이
/// mkfs.fat이다. 오프셋이 맞는지는 install 체인의 부팅 3이 본다.
pub fn isFat32(head: []const u8) bool {
    return head.len >= 512 and head[510] == 0x55 and head[511] == 0xAA and
        std.mem.eql(u8, head[82..][0..8], "FAT32   ");
}

/// 바이트를 목록에 찍을 수로. 디스크 제조사처럼 10진이다 — 512 GB라고 팔린
/// SSD가 목록에서 476이면 사람이 다른 디스크로 읽는다.
pub fn formatSize(buf: []u8, bytes: u64) []const u8 {
    const gb: u64 = 1_000_000_000;
    const mb: u64 = 1_000_000;
    if (bytes >= gb) return std.fmt.bufPrint(buf, "{d} GB", .{bytes / gb}) catch "?";
    if (bytes >= mb) return std.fmt.bufPrint(buf, "{d} MB", .{bytes / mb}) catch "?";
    return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "?";
}

pub const Command = union(enum) {
    /// 인자 없음. 목록만 찍는다.
    list,
    /// `<disk>` 뒤에 `--yes` · `--wipe`가 각각 많아야 한 번, 순서는 상관없다.
    install: struct { disk: [:0]const u8, yes: bool, wipe: bool },
    /// 그 밖의 전부. 쓰는 법을 찍고 2로 끝난다.
    usage,
};

/// argv[1..]을 읽는다. 디스크가 맨 앞이고 플래그는 그 뒤에만 온다 — 그래야
/// `tars-install --yes`(디스크를 빠뜨림)가 "--yes라는 디스크"가 아니라 쓰는
/// 법으로 떨어진다. 플래그끼리의 순서는 안 본다. 같은 플래그가 두 번이면
/// 쓰는 법이다 — 오타를 조용히 삼키지 않는다.
pub fn parseArgs(args: []const [*:0]const u8) Command {
    if (args.len == 0) return .list;
    if (args.len > 3) return .usage;
    const disk = std.mem.span(args[0]);
    if (std.mem.startsWith(u8, disk, "-")) return .usage;

    var yes = false;
    var wipe = false;
    for (args[1..]) |arg| {
        const flag = std.mem.span(arg);
        if (!yes and std.mem.eql(u8, flag, "--yes")) {
            yes = true;
        } else if (!wipe and std.mem.eql(u8, flag, "--wipe")) {
            wipe = true;
        } else return .usage;
    }
    return .{ .install = .{ .disk = disk, .yes = yes, .wipe = wipe } };
}

/// 사용자가 친 이름이 storage.DISKS의 것이면 그 원소를(수명이 무한한
/// 리터럴이다), 아니면 null. 파티션(`/dev/nvme0n1p1`)과 오타가 여기서 걸린다.
pub fn knownDisk(path: []const u8) ?[:0]const u8 {
    for (storage.DISKS) |d| {
        if (std.mem.eql(u8, d, path)) return d;
    }
    return null;
}

/// `/dev/nvme0n1` → `nvme0n1`. /sys/block/<이름>을 짓는 데 쓴다.
pub fn sysName(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[slash + 1 ..];
}

/// 확인 줄이 정확히 YES인가. 줄 끝의 개행과 공백만 벗긴다 — `yes`나 `y`는
/// 아니다. 디스크를 통째로 지우거나 부트 파일을 덮는 질문이라 대문자 세 글자를
/// 요구한다.
pub fn confirmed(line: []const u8) bool {
    return std.mem.eql(u8, std.mem.trim(u8, line, " \t\r\n"), "YES");
}

/// sfdisk에 stdin으로 넘기는 배치(DI design 결정 2 · 3). DI-M0 실측 8이 이
/// 세 줄을 그대로 먹였다.
pub const SFDISK_SCRIPT =
    \\label: gpt
    \\size=256MiB, type=uefi, name=TARS-BOOT
    \\size=1GiB, type=linux, name=TARS-CONFIG
    \\
;

pub const ESP_LABEL: [:0]const u8 = "TARS-BOOT";
pub const CONFIG_LABEL: [:0]const u8 = "tars-config";

/// limine의 설정 파일. 매체의 판정(MEDIUM_MARK)이자 ESP로 갈 때 한 줄이
/// 바뀌는 유일한 파일이다(espConf).
pub const LIMINE_CONF: [:0]const u8 = "boot/limine/limine.conf";

/// 부팅 매체에서 ESP로 가는 넷(DI design 확인 1). 경로가 양쪽에서 같다.
pub const BOOT_FILES = [_][:0]const u8{
    "boot/bzImage",
    "boot/initrd.cpio",
    LIMINE_CONF,
    "EFI/BOOT/BOOTX64.EFI",
};

/// BOOT_FILES를 놓기 전에 ESP에 만들 디렉터리. 부모가 먼저다.
pub const ESP_DIRS = [_][:0]const u8{ "boot", "boot/limine", "EFI", "EFI/BOOT" };

/// 매체라고 판정하는 파일(DI design 결정 4). 이름이 아니라 쓰임으로 본다.
pub const MEDIUM_MARK: [:0]const u8 = LIMINE_CONF;

/// ISO의 limine.conf를 ESP에 쓸 모양으로 바꿔 out에 담는다. `cmdline:` 줄마다
/// 끝에 storage.INSTALLED_TOKEN을 붙이고 나머지 바이트는 그대로다.
///
/// design 확인 2는 "바이트 그대로 복사한다"였고 DI-M2가 이것을 바꿨다. init은
/// 이 표지가 있어야 파티션을 설정 디스크 후보로 본다 — ISO로 뜬 기계가
/// 설치된 p2를 붙여 두면 --wipe가 막히기 때문이다(storage.INSTALLED_TOKEN).
///
/// cmdline 줄이 하나도 없거나 out이 모자라면 null이다. 표지 없이 설치하면
/// 설치된 기계가 설정 디스크를 못 찾는다 — 그런 설치는 시작하지 않는다.
/// 이미 표지가 있는 줄에는 다시 붙이지 않는다.
/// LF 파일만 다룬다(boot/limine.conf가 그렇다). CRLF면 표지가 \r 뒤에 붙는다.
/// limine의 kernel_cmdline: 별칭은 안 본다 — 그 키로 바꾸면 null이 되어 설치가 시작되지 않는다.
pub fn espConf(out: []u8, conf: []const u8) ?[]const u8 {
    const key = "cmdline:";
    const mark = " " ++ storage.INSTALLED_TOKEN;
    var n: usize = 0;
    var marked = false;
    var lines = std.mem.splitScalar(u8, conf, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) {
            if (n + 1 > out.len) return null;
            out[n] = '\n';
            n += 1;
        }
        first = false;
        if (n + line.len > out.len) return null;
        @memcpy(out[n..][0..line.len], line);
        n += line.len;

        const body = std.mem.trimStart(u8, line, " \t");
        if (!std.mem.startsWith(u8, body, key)) continue;
        marked = true;
        if (storage.cmdlineInstalled(body[key.len..])) continue;
        if (n + mark.len > out.len) return null;
        @memcpy(out[n..][0..mark.len], mark);
        n += mark.len;
    }
    return if (marked) out[0..n] else null;
}
