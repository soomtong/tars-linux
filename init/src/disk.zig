const std = @import("std");
const linux = std.os.linux;
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

/// 4Kn 디스크(논리 섹터 4096바이트)의 GPT 헤더 자리. GPT 헤더는 LBA 1에
/// 있으므로 섹터 크기가 곧 오프셋이다(DC 결정 5의 1).
const GPT_SIG_OFF_4KN: usize = 4096;

/// 앞머리에 무엇이 보이는가. 순서가 뜻이 있다(DC-M2가 바꿨다).
///
///   앞에 있는 구조를 먼저 믿는다. 파티션 도구와 mkfs는 디스크 맨 앞(512 ·
///   1080 · 4096)을 새로 쓰지만 32KiB의 ISO PVD는 안 건드리는 일이 많다 —
///   ISO를 구웠던 스틱을 다른 도구로 GPT나 ext2로 다시 만들면 옛 PVD가 남고,
///   ISO를 먼저 보면 그 스틱이 `iso9660 TARS`, 곧 부팅 매체로 읽혔다(DI-M1
///   실측 15). tars-install은 sfdisk --wipe always로 PVD까지 지우므로 이것은
///   남의 도구로 만든 디스크의 이야기다.
///
///   ext2가 GPT보다 먼저다. 둘은 겹치지 않지만(512바이트 섹터 GPT의 1080은 첫
///   파티션 항목의 이름 자리다) 파티션 없는 ext2가 게이트 디스크의 모양이다.
///   GPT는 512와 4096 둘 다 본다. 4Kn 디스크에서 512만 보면 보호 MBR만 보여
///   `mbr`로 읽혔고, 설치된 4Kn 디스크가 TARS installed로 안 보여 갱신 대신
///   새 설치(설정까지 지운다)로 갔다.
///   iso9660은 MBR보다 먼저다. 하이브리드 ISO는 MBR 서명도 갖고 있어서
///   (make_iso.sh의 --protective-msdos-label) MBR을 먼저 보면 USB 스틱의 ISO가
///   "mbr"로 읽힌다. 우리 ISO에는 GPT가 없다(512 · 4096에 `EFI PART`가 없다 —
///   DC-M2 plan) — 그래서 GPT를 ISO보다 먼저 봐도 진짜 매체는 그대로다.
///   blank는 끝에서 둘째다. 다 0이면 어떤 서명도 안 맞았다는 뜻이다.
pub fn describe(head: []const u8) Seen {
    if (storage.ext2Label(head)) |label| return .{ .kind = .ext2, .label = label };
    if (hasGptAt(head, GPT_SIG_OFF) or hasGptAt(head, GPT_SIG_OFF_4KN)) return .{ .kind = .gpt };
    if (head.len >= ISO_PVD + 40 + ISO_ID_LEN and head[ISO_PVD] == 1 and
        std.mem.eql(u8, head[ISO_PVD + 1 ..][0..5], "CD001"))
    {
        const id = head[ISO_PVD + 40 ..][0..ISO_ID_LEN];
        return .{ .kind = .iso9660, .label = std.mem.trimEnd(u8, id, " ") };
    }
    if (head.len >= 512 and head[510] == 0x55 and head[511] == 0xAA) return .{ .kind = .mbr };
    for (head) |b| {
        if (b != 0) return .{ .kind = .unknown };
    }
    return .{ .kind = .blank };
}

fn hasGptAt(head: []const u8, off: usize) bool {
    return head.len >= off + 8 and std.mem.eql(u8, head[off..][0..8], "EFI PART");
}

/// 한 줄을 buf에 짓는다. 넘치면 앞부분을 남기고 끝을 `...\n`으로 덮는다 —
/// install.zig의 say와 complain이 쓴다(DC 결정 5의 3).
///
/// 전에는 넘치면 줄을 통째로 버렸다. 긴 인자를 되풀이하는 에러
/// (`<arg> is not a disk ...`)가 그래서 아무 말 없이 종료 코드만 남겼다.
///
/// Zig의 bufPrint는(0.16에서 확인) 넘칠 때 NoSpaceLeft를 돌려주면서 buf에 들어간
/// 만큼은 채워 둔다(DC-M2 plan에서 확인). 그 동작에 기댄다 — 바뀌면
/// disk_test의 검사 11이 빨개진다. buf는 4바이트보다 커야 한다.
pub fn clip(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch {
        const tail = "...\n";
        @memcpy(buf[buf.len - tail.len ..], tail);
        return buf;
    };
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

/// 상태 칸의 두 값. install은 `State`의 칸으로 갈래를 고르고 이 글자를 찍는다.
pub const STATE_MEDIUM = "boot medium";
pub const STATE_INSTALLED = "TARS installed";

/// 한 디스크의 상태. install은 `medium`이면 거절하고 `installed`면 갱신으로 간다(`--wipe`가 없을 때).
pub const State = union(enum) { medium, installed, other: []const u8 };

pub fn stateWord(s: State) []const u8 {
    return switch (s) {
        .medium => STATE_MEDIUM,
        .installed => STATE_INSTALLED,
        .other => |t| t,
    };
}

/// 앞머리를 읽은 뒤의 상태. seen이 null이면 못 읽은 것이다.
///
/// 그 앞의 둘 — 붙여서 확인한 매체 · 설치됨 — 은 install의 `stateOf`가 먼저 본다. 설치됨은 p1을
/// 붙여 보는 일이라 매체 디스크에서는 부르지 않는다(HC-M2 plan 확정 3).
pub fn headState(buf: []u8, seen: ?Seen) State {
    const s = seen orelse return .{ .other = "unreadable" };
    if (isTarsMedium(s)) return .medium;
    return .{ .other = stateText(buf, s) };
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

/// /sys/block/<이름>/size의 글자를 바이트로. 그 수는 장치의 논리 섹터 크기와 무관하게
/// 늘 512바이트 단위다(커널 문서 Documentation/ABI/stable/sysfs-block). 수가 아니면 null.
pub fn sectorsToBytes(text: []const u8) ?u64 {
    const sectors = std.fmt.parseInt(u64, text, 10) catch return null;
    return sectors * 512;
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
/// 세 줄을 그대로 먹였다. p1은 KU-M0에서 256MiB → 1GiB가 됐다(KU design
/// 결정 8) — 이미지 슬롯 둘(약 102MB씩)이 들어가고, 한 벌이 약 500MB가 될
/// 때까지 둘이 들어간다. 그 전에 설치된 256MiB ESP는 갱신이 키우지 않는다.
pub const SFDISK_SCRIPT =
    \\label: gpt
    \\size=1GiB, type=uefi, name=TARS-BOOT
    \\size=1GiB, type=linux, name=TARS-CONFIG
    \\
;

/// 위 배치가 들어가는 가장 작은 디스크(KU-M0 plan 확정 값). p1 · p2에 GPT
/// 앞의 1MiB 정렬과 뒤의 백업 헤더 몫을 더했다. 이보다 작은 디스크는 YES를
/// 묻기 전에 거절한다 — 묻고 나서 sfdisk가 실패하면 늦다.
pub const MIN_DISK_BYTES: u64 = (2 << 30) + (2 << 20);

/// 거절 줄에 쓰는 최소 크기의 글자. formatSize는 10진 버림이라 최소 크기와
/// 2GB 스틱이 둘 다 `2 GB`로 찍혀서 "2 GB는 2 GB가 필요하다"가 된다.
pub const MIN_DISK_WORDS = "more than 2 GiB";

pub fn bigEnough(bytes: u64) bool {
    return bytes >= MIN_DISK_BYTES;
}

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

/// BOOT_FILES를 놓기 전에 ESP에 만들 디렉터리. 부모가 먼저다. `boot/old`는
/// old 슬롯의 자리다(KU design 결정 2). 새 설치에서는 빈 채로 둔다.
pub const ESP_DIRS = [_][:0]const u8{ "boot", "boot/old", "boot/limine", "EFI", "EFI/BOOT" };

/// 이미지 슬롯(KU design 결정 1 · 2). new는 `boot/`, old는 `boot/old/`이고 파일
/// 이름은 둘이 같다. `version`은 버전 글자 한 줄이고 늘 맨 마지막에 쓴다 —
/// 이 파일이 있으면 그 슬롯은 끝까지 써진 것이다(결정 5).
pub const NEW_DIR = "boot";
pub const OLD_DIR = "boot/old";
pub const SLOT_FILES = [_][:0]const u8{ "bzImage", "initrd.cpio", "version" };

/// old 엔트리의 cmdline에 붙는 낱말. init은 안 쓴다 — 사람과 게이트가
/// /proc/cmdline으로 "old로 떴다"를 알아보는 표지다.
pub const SLOT_OLD_TOKEN = "tars.slot=old";

/// ESP conf의 메뉴 대기 초. ISO conf는 0 그대로다(KU design 결정 3).
pub const MENU_TIMEOUT = "3";

/// 디스크에서 읽은 버전 글자를 conf 제목에 넣어도 되는가. 비지 않았고 64자
/// 이하이며 글자가 전부 눈에 보이는 ASCII(공백 제외)여야 한다 — 개행이 섞이면
/// conf의 줄이 갈라지고, 제어 문자는 메뉴를 어지럽힌다. BV의 버전 글자
/// (`0.1.3`, `0.1.3+abc1234-dirty`)는 늘 통과한다.
pub fn plainVersion(text: []const u8) bool {
    if (text.len == 0 or text.len > 64) return false;
    for (text) |c| {
        if (c <= ' ' or c > '~') return false;
    }
    return true;
}

/// 매체라고 판정하는 파일(DI design 결정 4). 이름이 아니라 쓰임으로 본다.
pub const MEDIUM_MARK: [:0]const u8 = LIMINE_CONF;

/// ISO의 limine.conf로 ESP의 conf를 지어 out에 담는다(KU design 결정 3).
///
/// ISO conf를 첫 엔트리(`/`로 시작하는 줄) 앞의 전역 줄과 엔트리 블록으로
/// 가른다.
/// - 전역 줄은 그대로 옮기되 `timeout:`의 값만 MENU_TIMEOUT으로 바꾼다. ISO는
///   고를 것이 없어 0이고, 설치된 디스크는 old를 고를 틈이 있어야 한다.
/// - 엔트리 블록을 제목 `/TARS <new_ver>`로 한 번 쓴다. `cmdline:` 줄 끝에는
///   storage.INSTALLED_TOKEN을 붙인다(DI-M2 — init은 이 표지가 있어야 파티션을
///   설정 디스크 후보로 본다). 이미 있으면 다시 안 붙인다.
/// - old_ver가 있으면 빈 줄 하나 뒤에 블록을 다시 쓴다. 제목은
///   `/TARS <old_ver> (old)`, `path:` · `kernel_path:` · `module_path:` 값의
///   `boot():/boot/`를 `boot():/boot/old/`로, cmdline 끝에 SLOT_OLD_TOKEN을 더한다.
///   경로 줄에 `boot():/boot/`가 없으면 null이다 — old 엔트리가 조용히 new의
///   파일을 가리키면 그 엔트리로 돌아갈 곳이 없다.
///
/// null인 경우: 버전 글자가 plainVersion이 아니다 · 엔트리가 하나가 아니다 ·
/// 전역 `timeout:`이 없다(ISO conf의 모양이 바뀐 것이다) · 블록에 cmdline 줄이
/// 없다(표지 없이 설치하면 설정 디스크를 못 찾는다) · out이 모자란다. 어느
/// 것이든 설치는 시작하지 않는다.
///
/// 결과는 늘 개행으로 끝난다. LF 파일만 다룬다(boot/limine.conf가 그렇다).
/// limine의 kernel_cmdline: 별칭은 안 본다 — 그 키로 바꾸면 null이 된다.
pub fn espConf(out: []u8, conf: []const u8, new_ver: []const u8, old_ver: ?[]const u8) ?[]const u8 {
    if (!plainVersion(new_ver)) return null;
    if (old_ver) |v| {
        if (!plainVersion(v)) return null;
    }

    // 엔트리 머리 줄을 센다. 하나여야 하고, 그 앞에 timeout:이 있어야 한다.
    var entry_at: ?usize = null;
    var entries: usize = 0;
    var timeout_seen = false;
    {
        var off: usize = 0;
        var it = std.mem.splitScalar(u8, conf, '\n');
        while (it.next()) |line| : (off += line.len + 1) {
            const body = std.mem.trimStart(u8, line, " \t");
            if (std.mem.startsWith(u8, body, "/")) {
                entries += 1;
                if (entry_at == null) entry_at = off;
            } else if (entry_at == null and std.mem.startsWith(u8, body, "timeout:")) {
                timeout_seen = true;
            }
        }
    }
    const at = entry_at orelse return null;
    if (entries != 1 or !timeout_seen) return null;

    var w = Fill{ .out = out };
    // conf[0..at]는 '\n'으로 끝난다. 그래서 마지막 조각은 빈 글자이고 쓰지 않는다.
    var globals = std.mem.splitScalar(u8, conf[0..at], '\n');
    while (globals.next()) |line| {
        if (globals.index == null) break;
        const body = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, body, "timeout:")) {
            w.put("timeout: " ++ MENU_TIMEOUT);
        } else {
            w.put(line);
        }
        w.put("\n");
    }
    const block = std.mem.trimEnd(u8, conf[at..], "\n");
    if (!entryBlock(&w, block, new_ver, false)) return null;
    if (old_ver) |v| {
        w.put("\n");
        if (!entryBlock(&w, block, v, true)) return null;
    }
    if (w.full) return null;
    return out[0..w.n];
}

/// 엔트리 블록 하나를 쓴다. cmdline 줄이 없거나, old인데 경로를 못 바꿨으면 거짓.
fn entryBlock(w: *Fill, block: []const u8, ver: []const u8, old: bool) bool {
    const from = "boot():/boot/";
    var cmdline = false;
    var it = std.mem.splitScalar(u8, block, '\n');
    while (it.next()) |line| {
        const body = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, body, "/")) {
            w.put("/TARS ");
            w.put(ver);
            if (old) w.put(" (old)");
        } else if (std.mem.startsWith(u8, body, "cmdline:")) {
            cmdline = true;
            w.put(line);
            if (!storage.cmdlineInstalled(body["cmdline:".len..])) w.put(" " ++ storage.INSTALLED_TOKEN);
            if (old) w.put(" " ++ SLOT_OLD_TOKEN);
        } else if (old and (std.mem.startsWith(u8, body, "path:") or
            std.mem.startsWith(u8, body, "kernel_path:") or
            std.mem.startsWith(u8, body, "module_path:")))
        {
            const i = std.mem.indexOf(u8, line, from) orelse return false;
            w.put(line[0 .. i + from.len]);
            w.put("old/");
            w.put(line[i + from.len ..]);
        } else {
            w.put(line);
        }
        w.put("\n");
    }
    return cmdline;
}

/// 고정 버퍼에 이어 쓴다. 넘치면 그 뒤로 아무것도 안 쓰고 full만 남긴다 —
/// 부르는 쪽이 끝에서 한 번 본다.
const Fill = struct {
    out: []u8,
    n: usize = 0,
    full: bool = false,

    fn put(self: *Fill, s: []const u8) void {
        if (self.full) return;
        if (self.n + s.len > self.out.len) {
            self.full = true;
            return;
        }
        @memcpy(self.out[self.n..][0..s.len], s);
        self.n += s.len;
    }
};

// ── 문장 ──────────────────────────────────────────────────────────────
//
// 여러 줄을 찍는 함수는 `sink`를 받는다 — `print(fmt, args)`가 있는 것이면 된다. install은 줄마다 `say`
// 한 번인 `Say`와 줄마다 `complain` 한 번인 `Complain`(접두사와 개행은 `complain`이 붙인다)을, 검사는
// `control.Out`을 준다. `config_edit`의 문장 절과 같은 모양이다(HC-M0 plan 확정 3).

/// 마지막 줄이 목록의 끝이다. install 체인이 그 줄을 기다린다.
pub fn usageLines(sink: anytype) void {
    sink.print("tars-install <disk>         install onto <disk>; a disk that has TARS is only updated\n", .{});
    sink.print("tars-install <disk> --yes   same, without asking\n", .{});
    sink.print("tars-install <disk> --wipe  erase <disk> even if it has TARS, settings too\n", .{});
}

/// 목록의 한 행. removable은 /sys/block/<이름>/removable의 글자다(`1`이면 떼는 장치).
pub fn listRow(sink: anytype, path: []const u8, size: []const u8, model: []const u8, removable: []const u8, state: []const u8) void {
    sink.print("  {s:<14} {s:>7}  {s:<22} {s:<9}  {s}\n", .{
        path,
        size,
        model,
        if (std.mem.eql(u8, removable, "1")) "removable" else "internal",
        state,
    });
}

/// 설치의 계획. 갱신은 p1만 갈고 p2를 남긴다(DI design 결정 8). 새 설치는 지울 디스크가 지금 무엇을
/// 들고 있는지 보인다. p2_settings는 p2에 `tars-` 라벨이 있는가이고 새 설치일 때만 뜻이 있다.
///
/// 갱신은 KU-M0부터 슬롯을 말한다. 크기 칸은 뺐다 — 256MiB ESP로 깔린 디스크도
/// 갱신되고, 갱신은 ESP 크기를 안 바꾼다(KU design 결정 8). `rot`가 rotate면
/// 지금 이미지(cur_ver)가 old로 가고, overwrite면 old 자리는 그대로다. no_room은
/// 계획까지 오지 않는다(roomLines가 먼저 거절한다). 새 설치에서 cur_ver · rot는
/// 안 쓴다.
pub fn planLines(
    sink: anytype,
    update: bool,
    path: []const u8,
    size: []const u8,
    model: []const u8,
    state: []const u8,
    p2_settings: bool,
    new_ver: []const u8,
    cur_ver: ?[]const u8,
    rot: Rotation,
) void {
    if (update) {
        sink.print("tars-install: {s} ({s}, {s}) already has TARS. p1 will be updated, p2 (your settings) is kept.\n", .{
            path, size, model,
        });
        sink.print("  boot/      <- TARS {s}\n", .{new_ver});
        if (rot == .rotate) {
            sink.print("  boot/old/  <- TARS {s}, for the boot menu if the new one fails\n", .{cur_ver orelse "?"});
        } else {
            sink.print("  boot/old/  <- left as it is\n", .{});
        }
        sink.print("  p2 (tars-config) <- not opened\n", .{});
        sink.print("  tars-install {s} --wipe erases both instead\n", .{path});
    } else {
        sink.print("tars-install: {s} ({s}, {s}) will be erased. it now holds: {s}\n", .{
            path, size, model, state,
        });
        sink.print("  p1    1 GiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n", .{});
        sink.print("  p2    1 GiB  Linux       ext2   tars-config <- your settings, empty at first\n", .{});
        sink.print("  rest unallocated\n", .{});
        if (p2_settings) sink.print("  the settings now on p2 are erased too\n", .{});
    }
}

// ── 슬롯 회전 (KU-M0) ────────────────────────────────────────────────

/// 새 이미지 두 파일에 더하는 여유. conf · version 몇 바이트와 FAT의 클러스터
/// 반올림(파일마다 한 클러스터 아래)의 몫이다.
pub const NEED_SLACK: u64 = 1 << 20;

pub const Rotation = enum { rotate, overwrite, no_room };

/// 갱신이 할 일(KU design 결정 5, 위험 2). 모든 수는 바이트다.
///   has_version  boot/version이 있다 — 지금 이미지가 끝까지 써졌다
///   free         ESP의 빈 자리
///   old_slot     boot/old의 bzImage + initrd.cpio — rotate가 맨 먼저 지운다
///   cur_slot     boot/의 bzImage + initrd.cpio — overwrite가 O_TRUNC로 덮는다
///   need         매체의 bzImage + initrd.cpio + NEED_SLACK
///
/// 지금 이미지가 끝까지 써졌으면 old로 보낸다. 반쪽이면 old로 보내지 않고 그
/// 자리를 덮는다 — 반쪽을 old로 보내면 멀쩡한 old가 지워진다. 어느 쪽이든 풀리는
/// 몫까지 더해도 need에 모자라면 아무것도 안 건드린다. 검사 없이 회전하면
/// old를 지운 뒤 복사가 ENOSPC로 죽어, new는 반쪽이고 old는 없는 디스크가 된다.
pub fn rotation(has_version: bool, free: u64, old_slot: u64, cur_slot: u64, need: u64) Rotation {
    if (has_version) return if (free +| old_slot >= need) .rotate else .no_room;
    return if (free +| cur_slot >= need) .overwrite else .no_room;
}

/// 빈 자리 줄. no_room이면 거절 줄이 뒤따른다 — 그 뒤에는 아무것도 안 바뀐다.
/// 둘 다 YES를 묻기 전에 찍힌다.
pub fn roomLines(sink: anytype, free: u64, old_slot: u64, need: u64, rot: Rotation) void {
    sink.print("tars-install: p1 has {d} bytes free and {d} bytes in boot/old; the new image needs {d}\n", .{
        free, old_slot, need,
    });
    if (rot == .no_room) sink.print("tars-install: p1 has no room for two images; nothing was changed.\n", .{});
}

pub const Op = enum { clear_old, write_conf, move_to_old, copy_new, write_version };

/// 회전의 순서(KU design 결정 4). install.zig가 이 배열을 그대로 돌고, op마다
/// sync한다. disk_test 검사 21이 같은 배열을 상태 모형 위에서 돌려, 어느 op
/// 뒤에 끊겨도 뜨는 엔트리가 하나는 있는지 본다.
///   clear_old      boot/old의 셋을 지운다. ESP에는 두 벌만 들어가므로 먼저다
///   write_conf     엔트리 둘의 conf. new는 아직 지금 이미지를, old는 빈 자리를 가리킨다
///   move_to_old    boot/의 셋을 boot/old/로 rename한다
///   copy_new       매체의 두 파일을 boot/로
///   write_version  boot/version. 이것이 있어야 이 슬롯이 다음 회전의 old가 된다
/// write_conf가 move_to_old보다 앞이어야 한다. 거꾸로면 옛 conf(엔트리 하나)가
/// 빈 boot/bzImage를 가리키는 순간이 생긴다.
pub const ROTATION = [_]Op{ .clear_old, .write_conf, .move_to_old, .copy_new, .write_version };

/// 도구가 0으로 끝났는가. 아니면 무엇으로 끝났는지 한 줄을 찍는다 — 그 뒤에 도구가 한 말이 온다.
/// status는 wait4의 것이다(`audio.outcome`과 같은 읽기). 줄은 `Complain`으로 가므로 개행이 없다.
pub fn toolOk(sink: anytype, tool: []const u8, status: u32) bool {
    if (linux.W.IFEXITED(status) and linux.W.EXITSTATUS(status) == 0) return true;

    if (linux.W.IFEXITED(status)) {
        sink.print("{s} failed (exit {d}); what it said:", .{ tool, linux.W.EXITSTATUS(status) });
    } else {
        sink.print("{s} was killed (signal {d}); what it said:", .{ tool, @backingInt(linux.W.TERMSIG(status)) });
    }
    return false;
}
