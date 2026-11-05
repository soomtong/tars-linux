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
    /// `<disk>` 뒤에 `--yes` · `--wipe` · `--beside`가 각각 많아야 한 번, 순서는 상관없다.
    install: struct { disk: [:0]const u8, yes: bool, wipe: bool, beside: bool = false },
    /// 그 밖의 전부. 쓰는 법을 찍고 2로 끝난다.
    usage,
};

/// argv[1..]을 읽는다. 디스크가 맨 앞이고 플래그는 그 뒤에만 온다 — 그래야
/// `tars-install --yes`(디스크를 빠뜨림)가 "--yes라는 디스크"가 아니라 쓰는
/// 법으로 떨어진다. 플래그끼리의 순서는 안 본다. 같은 플래그가 두 번이면
/// 쓰는 법이다 — 오타를 조용히 삼키지 않는다.
pub fn parseArgs(args: []const [*:0]const u8) Command {
    if (args.len == 0) return .list;
    if (args.len > 4) return .usage;
    const disk = std.mem.span(args[0]);
    if (std.mem.startsWith(u8, disk, "-")) return .usage;

    var yes = false;
    var wipe = false;
    var beside = false;
    for (args[1..]) |arg| {
        const flag = std.mem.span(arg);
        if (!yes and std.mem.eql(u8, flag, "--yes")) {
            yes = true;
        } else if (!wipe and std.mem.eql(u8, flag, "--wipe")) {
            wipe = true;
        } else if (!beside and std.mem.eql(u8, flag, "--beside")) {
            beside = true;
        } else return .usage;
    }
    return .{ .install = .{ .disk = disk, .yes = yes, .wipe = wipe, .beside = beside } };
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
/// 모양을 그대로 먹였다. p1은 KU-M0에서 256MiB → 1GiB가 됐다가 HP-M0에서
/// 768MiB가 됐고(HP design 결정 2, 사용자) 이미지 슬롯 둘(약 125MB씩)이
/// 들어간다 — 한 벌이 384MB를 넘기 전까지. p2는 설정뿐이라 256MiB면 과분하다.
/// p3는 size가 없어 나머지 전부이고 `/home`이 된다(ext4). 그 전에 설치된
/// 옛 배치의 ESP는 갱신이 건드리지 않는다.
pub const SFDISK_SCRIPT =
    \\label: gpt
    \\size=768MiB, type=uefi, name=TARS-BOOT
    \\size=256MiB, type=linux, name=TARS-CONFIG
    \\type=linux, name=TARS-HOME
    \\
;

/// 설치를 받는 가장 작은 디스크(HP design 결정 2 — 사용자가 "어떤 임베디드에
/// 들어갈지 모른다"며 4GiB를 보장하라고 정했다). p1 + p2가 1GiB라 p3에 3GiB
/// 남짓이 남는다. GPT 앞의 1MiB 정렬과 뒤의 백업 헤더 몫을 더했다. 이보다
/// 작은 디스크는 YES를 묻기 전에 거절한다 — 묻고 나서 sfdisk가 실패하면 늦다.
pub const MIN_DISK_BYTES: u64 = (4 << 30) + (2 << 20);

/// 거절 줄에 쓰는 최소 크기의 글자. formatSize는 10진 버림이라 최소 크기와
/// 4GB 스틱이 둘 다 `4 GB`로 찍혀서 "4 GB는 4 GB가 필요하다"가 된다.
pub const MIN_DISK_WORDS = "more than 4 GiB";

pub fn bigEnough(bytes: u64) bool {
    return bytes >= MIN_DISK_BYTES;
}

pub const ESP_LABEL: [:0]const u8 = "TARS-BOOT";
pub const CONFIG_LABEL: [:0]const u8 = "tars-config";
/// `/home`의 라벨. 판정은 storage.zig에 있다 — init이 찾는 것과 설치기가
/// 굽는 것이 한 상수여야 한다(DI design 결정 5와 같은 이유).
pub const HOME_LABEL: [:0]const u8 = storage.HOME_LABEL;

/// limine의 설정 파일. 매체의 판정(MEDIUM_MARK)이자 ESP로 갈 때 한 줄이
/// 바뀌는 유일한 파일이다(espConf).
pub const LIMINE_CONF: [:0]const u8 = "boot/limine/limine.conf";

/// 부팅 매체에서 ESP로 가는 여섯(DI design 확인 1). 경로가 양쪽에서 같다. 끝의 둘은 Apple 부팅 선택 화면이 "EFI
/// Boot" 대신 보이는 이름 그림이다(2026-11-05 사용자 요청, boot/make_disk_label.sh). 로더처럼 슬롯이 아니라 한 벌이다.
pub const BOOT_FILES = [_][:0]const u8{
    "boot/bzImage",
    "boot/initrd.cpio",
    LIMINE_CONF,
    "EFI/BOOT/BOOTX64.EFI",
    "EFI/BOOT/.disk_label",
    "EFI/BOOT/.disk_label_2x",
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
    sink.print("tars-install <disk> --beside  keep what <disk> has; install into its largest free space\n", .{});
    sink.print("tars-install <partition>    erase that one partition (say /dev/sda3) and install there\n", .{});
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

/// 설치의 계획. 갱신은 TARS-BOOT만 갈고 TARS-CONFIG를 남긴다(DI design 결정 8). 새 설치는 지울 디스크가
/// 지금 무엇을 들고 있는지 보인다. settings_on은 `tars-` 라벨이 든 TARS-CONFIG의 번호이고 새 설치일 때만
/// 뜻이 있다.
///
/// DB-M0부터 갱신은 번호를 받는다 — nums는 이름으로 찾은 TARS-BOOT · TARS-CONFIG · TARS-HOME(없으면 0)이다.
/// 통째 설치는 {1, 2, 3}이라 글자가 전과 같다. beside는 디스크에 TARS 아닌 파티션이 있다는 뜻이고, 그때
/// `--wipe` 혼자는 macOS까지 지우므로 다시 까는 길로 `--beside --wipe`를 말한다.
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
    settings_on: ?u8,
    nums: [3]u8,
    beside: bool,
    new_ver: []const u8,
    cur_ver: ?[]const u8,
    rot: Rotation,
) void {
    if (update) {
        sink.print("tars-install: {s} ({s}, {s}) already has TARS. p{d} will be updated, p{d} (your settings) is kept.\n", .{
            path, size, model, nums[0], nums[1],
        });
        sink.print("  boot/      <- TARS {s}\n", .{new_ver});
        if (rot == .rotate) {
            sink.print("  boot/old/  <- TARS {s}, for the boot menu if the new one fails\n", .{cur_ver orelse "?"});
        } else {
            sink.print("  boot/old/  <- left as it is\n", .{});
        }
        sink.print("  p{d} (tars-config) <- not opened\n", .{nums[1]});
        if (nums[2] != 0) sink.print("  p{d} (tars-home) <- not opened\n", .{nums[2]});
        if (beside) {
            sink.print("  tars-install {s} --beside --wipe erases the TARS partitions instead, your home too; --wipe alone erases the whole disk\n", .{path});
        } else {
            sink.print("  tars-install {s} --wipe erases all three instead, your home too\n", .{path});
        }
    } else {
        sink.print("tars-install: {s} ({s}, {s}) will be erased. it now holds: {s}\n", .{
            path, size, model, state,
        });
        layoutRows(sink, .{ 1, 2, 3 });
        if (settings_on) |n| sink.print("  the settings now on p{d} are erased too\n", .{n});
    }
}

/// 새 설치가 만들 계정 한 줄(HP-M1 plan Task 2). 질문 뒤 · YES 앞에, `--yes`면 계획 바로
/// 뒤에 찍는다 — 질문이 없는 길에서도 무엇이 만들어지는지 보인다. 비밀번호 글자는 어디에도
/// 안 찍고 기본값인지만 말한다.
pub fn userLine(sink: anytype, name: []const u8, default_password: bool) void {
    sink.print("  user  {s}  (home /home/{s}, password {s})\n", .{
        name, name, if (default_password) "tars-linux, the default" else "as typed",
    });
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

/// 빈 자리 줄. esp는 TARS-BOOT의 번호다(통째 설치는 1). no_room이면 거절 줄이 뒤따른다 — 그 뒤에는 아무것도 안 바뀐다.
/// 둘 다 YES를 묻기 전에 찍힌다.
pub fn roomLines(sink: anytype, esp: u8, free: u64, old_slot: u64, need: u64, rot: Rotation) void {
    sink.print("tars-install: p{d} has {d} bytes free and {d} bytes in boot/old; the new image needs {d}\n", .{
        esp, free, old_slot, need,
    });
    if (rot == .no_room) sink.print("tars-install: p{d} has no room for two images; nothing was changed.\n", .{esp});
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

// ── GPT 엔트리 (DB-M0) ───────────────────────────────────────────────
//
// `--beside`가 남의 파티션 옆에 깔려면 GPT의 엔트리를 읽어야 한다. 그리고 설치기와 init이 TARS 파티션을
// 번호가 아니라 이름(`TARS-BOOT` · `TARS-CONFIG` · `TARS-HOME`)으로 찾는다(DB design 결정 5). 여기의 함수는
// 디스크 앞머리(HEAD_BYTES) 하나만 받는다 — 엔트리 128개는 LBA 2부터 16KiB라 512바이트 섹터면 17408,
// 4Kn이면 24576에서 끝나서 둘 다 HEAD_BYTES 안이다. 그 밖에 엔트리를 둔 GPT는 null이다(읽을 수 없는
// 것은 거절한다).

/// GUID 글자(`C12A7328-F81F-11D2-...`)를 디스크 위 16바이트로. 앞의 세 칸은 리틀엔디안, 뒤의 두 칸은
/// 적힌 순서다(UEFI 규격 부록 A). 이것을 틀리면 타입이 하나도 안 맞는다 — disk_test 검사 22가 진짜
/// sfdisk가 쓴 바이트로 본다.
pub fn guidBytes(comptime text: []const u8) [16]u8 {
    return comptime blk: {
        if (text.len != 36) @compileError("a GUID is 36 characters");
        var hex: [32]u8 = undefined;
        var n: usize = 0;
        for (text) |c| {
            if (c == '-') continue;
            hex[n] = c;
            n += 1;
        }
        var raw: [16]u8 = undefined;
        _ = std.fmt.hexToBytes(&raw, &hex) catch @compileError("not a GUID");
        var out = raw;
        std.mem.reverse(u8, out[0..4]);
        std.mem.reverse(u8, out[4..6]);
        std.mem.reverse(u8, out[6..8]);
        break :blk out;
    };
}

/// 목록이 이름으로 말하는 타입 셋(DB design 결정 9). 나머지는 `other`다.
pub const GUID_EFI = guidBytes("C12A7328-F81F-11D2-BA4B-00A0C93EC93B");
pub const GUID_APFS = guidBytes("7C3457EF-0000-11AA-AA11-00306543ECAC");
pub const GUID_HFS = guidBytes("48465300-0000-11AA-AA11-00306543ECAC");
/// 지정 설치(DB-M1)가 가리는 타입 둘. 디스크 유틸리티의 MS-DOS(FAT) · ExFAT 파티션은 Microsoft Basic Data다 —
/// Boot Camp의 NTFS도 같은 타입이라 타입만으로는 못 받는다(파일시스템을 함께 본다, takeable). Apple Boot는
/// HFS+ 맥의 Recovery HD다.
pub const GUID_BASIC = guidBytes("EBD0A0A2-B9E5-4433-87C0-68B6B72699C7");
pub const GUID_APPLE_BOOT = guidBytes("426F6F74-0000-11AA-AA11-00306543ECAC");

/// GPT 파티션 이름. 통째 설치의 SFDISK_SCRIPT와 `--beside`의 appendScript가 같은 이름을 쓴다.
/// ESP는 FAT 라벨과 GPT 이름이 같은 글자다(ESP_LABEL).
pub const NAME_BOOT: []const u8 = ESP_LABEL;
pub const NAME_CONFIG: []const u8 = "TARS-CONFIG";
pub const NAME_HOME: []const u8 = "TARS-HOME";

pub const PartKind = enum { efi, apfs, hfs, basic, apple_boot, other };
pub const Role = enum { none, boot, config, home };

pub const Part = struct {
    /// 엔트리 자리 + 1. 커널이 매기는 파티션 번호(`nvme0n1p<N>`)와 같다.
    number: u8,
    kind: PartKind,
    role: Role,
    first: u64,
    last: u64,
};

pub const MAX_PARTS = 128;

pub const Gpt = struct {
    sector: u64,
    first_usable: u64,
    last_usable: u64,
    /// 헤더가 말하는 엔트리 수. 빈 엔트리 번호를 셀 때의 끝이다.
    entries: u32,
    parts: [MAX_PARTS]Part = undefined,
    count: usize = 0,

    pub fn slice(self: *const Gpt) []const Part {
        return self.parts[0..self.count];
    }

    /// 그 이름의 파티션이 정확히 하나면 그것, 없거나 둘 이상이면 null. 둘이면 어느 쪽이 우리 것인지
    /// 모른다 — 설치되지 않은 디스크로 보고 `--beside --wipe`만 받는다(TARS 이름 전부를 지운다).
    pub fn find(self: *const Gpt, role: Role) ?Part {
        var got: ?Part = null;
        for (self.slice()) |p| {
            if (p.role != role) continue;
            if (got != null) return null;
            got = p;
        }
        return got;
    }

    /// TARS 이름의 파티션이 하나라도 있는가.
    pub fn hasTars(self: *const Gpt) bool {
        for (self.slice()) |p| {
            if (p.role != .none) return true;
        }
        return false;
    }

    /// TARS 이름이 아닌 파티션이 있는가. 있으면 `--beside`로 깔린 디스크다 — `--wipe` 혼자는 그
    /// 파티션까지 지운다는 것을 계획이 말해야 한다.
    pub fn hasOthers(self: *const Gpt) bool {
        for (self.slice()) |p| {
            if (p.role == .none) return true;
        }
        return false;
    }

    /// 그 번호의 파티션. 없으면 null.
    pub fn byNumber(self: *const Gpt, number: u8) ?Part {
        for (self.slice()) |p| {
            if (p.number == number) return p;
        }
        return null;
    }

    /// 그 번호의 파티션을 뺀 사본(DB-M1). 지정 설치가 `sfdisk --delete` 뒤의 표를 미리 본다 — freeNumbers가
    /// 이 사본에서 sfdisk가 매길 번호를 센다.
    pub fn without(self: *const Gpt, number: u8) Gpt {
        var g = self.*;
        g.count = 0;
        for (self.slice()) |p| {
            if (p.number == number) continue;
            g.parts[g.count] = p;
            g.count += 1;
        }
        return g;
    }
};

/// 엔트리 이름(UTF-16LE 36글자, 72바이트)이 ASCII 글자 name과 같은가. 남는 자리는 0이어야 한다.
fn nameIs(raw: []const u8, name: []const u8) bool {
    if (name.len * 2 > raw.len) return false;
    for (name, 0..) |c, i| {
        if (raw[i * 2] != c or raw[i * 2 + 1] != 0) return false;
    }
    for (raw[name.len * 2 ..]) |b| {
        if (b != 0) return false;
    }
    return true;
}

fn roleOf(raw_name: []const u8) Role {
    if (nameIs(raw_name, NAME_BOOT)) return .boot;
    if (nameIs(raw_name, NAME_CONFIG)) return .config;
    if (nameIs(raw_name, NAME_HOME)) return .home;
    return .none;
}

fn kindOf(guid: *const [16]u8) PartKind {
    if (std.mem.eql(u8, guid, &GUID_EFI)) return .efi;
    if (std.mem.eql(u8, guid, &GUID_APFS)) return .apfs;
    if (std.mem.eql(u8, guid, &GUID_HFS)) return .hfs;
    if (std.mem.eql(u8, guid, &GUID_BASIC)) return .basic;
    if (std.mem.eql(u8, guid, &GUID_APPLE_BOOT)) return .apple_boot;
    return .other;
}

/// head에서 GPT를 읽는다. sector는 장치의 논리 섹터 크기(512 · 4096)이고 헤더는 LBA 1(오프셋 sector)에
/// 있다. 하나라도 이상하면 null이다 — 헤더나 엔트리의 CRC가 안 맞으면 커널과 sfdisk는 백업 GPT를 믿고,
/// 우리가 본 엔트리와 그들이 쓰는 엔트리가 갈린다. 남의 디스크에 쓸 자리를 이것으로 고르므로 의심스러운
/// 것은 읽지 않는다.
pub fn parseGpt(head: []const u8, sector: u64) ?Gpt {
    if (sector != 512 and sector != 4096) return null;
    const h_off: usize = @intCast(sector);
    if (!hasGptAt(head, h_off) or head.len < h_off + 92) return null;
    const h = head[h_off..];

    // 헤더 CRC는 헤더 크기만큼, CRC 칸(16)을 0으로 두고 센다.
    const h_size = std.mem.readInt(u32, h[12..16], .little);
    if (h_size < 92 or h_size > sector or h_off + h_size > head.len) return null;
    var crc = std.hash.Crc32.init();
    crc.update(h[0..16]);
    crc.update(&[_]u8{ 0, 0, 0, 0 });
    crc.update(h[20..h_size]);
    if (crc.final() != std.mem.readInt(u32, h[16..20], .little)) return null;

    const first_usable = std.mem.readInt(u64, h[40..48], .little);
    const last_usable = std.mem.readInt(u64, h[48..56], .little);
    const entries_lba = std.mem.readInt(u64, h[72..80], .little);
    const entries = std.mem.readInt(u32, h[80..84], .little);
    const e_size = std.mem.readInt(u32, h[84..88], .little);
    if (first_usable > last_usable or e_size != 128 or entries == 0 or entries > MAX_PARTS) return null;
    if (entries_lba < 2 or entries_lba > head.len / sector) return null;
    const e_off: usize = @intCast(entries_lba * sector);
    const e_len: usize = @as(usize, entries) * 128;
    if (e_off + e_len > head.len) return null;
    const table = head[e_off..][0..e_len];
    if (std.hash.Crc32.hash(table) != std.mem.readInt(u32, h[88..92], .little)) return null;

    var g = Gpt{ .sector = sector, .first_usable = first_usable, .last_usable = last_usable, .entries = entries };
    var i: usize = 0;
    while (i < entries) : (i += 1) {
        const e = table[i * 128 ..][0..128];
        if (std.mem.allEqual(u8, e[0..16], 0)) continue;
        const first = std.mem.readInt(u64, e[32..40], .little);
        const last = std.mem.readInt(u64, e[40..48], .little);
        // 쓸 수 있는 구간 밖의 엔트리는 규격 위반이다. 빈 자리를 셀 수 없으니 통째로 안 읽는다.
        if (first > last or first < first_usable or last > last_usable) return null;
        g.parts[g.count] = .{
            .number = @intCast(i + 1),
            .kind = kindOf(e[0..16]),
            .role = roleOf(e[56..128]),
            .first = first,
            .last = last,
        };
        g.count += 1;
    }
    return g;
}

/// 빈 구간. 섹터 단위이고 end는 안 든다. 두 끝 다 1MiB에 맞췄다.
pub const Gap = struct {
    start: u64,
    end: u64,

    pub fn bytes(self: Gap, sector: u64) u64 {
        return (self.end - self.start) * sector;
    }
};

/// 파티션 사이(와 앞뒤)의 빈 구간 중 가장 큰 것. 시작은 1MiB 위로, 끝은 1MiB 아래로 맞춘다 — sfdisk와
/// macOS의 정렬이 1MiB이고, 맞추고 나서 남는 것이 진짜 쓸 자리다. without_tars면 TARS 이름의 파티션을
/// 없는 것으로 친다(`--beside --wipe`가 그 셋을 지운 뒤의 자리). 빈 구간이 없으면 null.
pub fn largestGap(g: *const Gpt, without_tars: bool) ?Gap {
    const step: u64 = (1 << 20) / g.sector;
    var used: [MAX_PARTS][2]u64 = undefined;
    var n: usize = 0;
    for (g.slice()) |p| {
        if (without_tars and p.role != .none) continue;
        // 시작 순으로 끼워 넣는다. 많아야 128개다.
        var j = n;
        while (j > 0 and used[j - 1][0] > p.first) : (j -= 1) used[j] = used[j - 1];
        used[j] = .{ p.first, p.last };
        n += 1;
    }

    var best: ?Gap = null;
    var cursor = g.first_usable;
    var k: usize = 0;
    while (k <= n) : (k += 1) {
        // 마지막 바퀴는 끝(last_usable 다음)까지의 꼬리다.
        const stop = if (k < n) used[k][0] else g.last_usable + 1;
        if (stop > cursor) {
            const s = std.mem.alignForward(u64, cursor, step);
            const e = std.mem.alignBackward(u64, stop, step);
            if (e > s and (best == null or e - s > best.?.end - best.?.start)) best = .{ .start = s, .end = e };
        }
        if (k < n) cursor = @max(cursor, used[k][1] + 1);
    }
    return best;
}

/// sfdisk가 매길 번호 셋. sfdisk는 `--append`의 새 파티션에 비어 있는 첫 엔트리를 준다(DB-M0 plan
/// 착수 전 3에서 2.41.5로 확인). without_tars는 largestGap과 같다. 빈 엔트리가 셋이 안 되면 null.
pub fn freeNumbers(g: *const Gpt, without_tars: bool) ?[3]u8 {
    var out: [3]u8 = undefined;
    var got: usize = 0;
    var n: u32 = 1;
    outer: while (n <= g.entries and got < 3) : (n += 1) {
        for (g.slice()) |p| {
            if (p.number == n and !(without_tars and p.role != .none)) continue :outer;
        }
        out[got] = @intCast(n);
        got += 1;
    }
    return if (got == 3) out else null;
}

/// 섹터 단위의 한 파티션 자리.
pub const Range = struct { start: u64, size: u64 };

/// `--beside`의 배치. 크기는 통째 설치와 같다 — 768MiB · 256MiB · 구간의 나머지(DB design 결정 4).
pub const Layout = struct { boot: Range, config: Range, home: Range };

pub const BOOT_BYTES: u64 = 768 << 20;
pub const CONFIG_BYTES: u64 = 256 << 20;

/// 구간이 MIN_DISK_BYTES보다 작으면 null(통째 설치와 같은 최소다 — HP design 결정 2).
pub fn besideLayout(gap: Gap, sector: u64) ?Layout {
    if (gap.bytes(sector) < MIN_DISK_BYTES) return null;
    const b = BOOT_BYTES / sector;
    const c = CONFIG_BYTES / sector;
    return .{
        .boot = .{ .start = gap.start, .size = b },
        .config = .{ .start = gap.start + b, .size = c },
        .home = .{ .start = gap.start + b + c, .size = gap.end - (gap.start + b + c) },
    };
}

/// `sfdisk --append`에 먹이는 세 줄. 셋 다 start와 size를 섹터로 적는다 — 생략하면 sfdisk가 첫 빈 자리를
/// 고를 수 있어 우리가 고른 구간과 갈린다(DB design 결정 4). `label:` 줄이 없다 — 있는 표를 그대로 두고
/// 덧붙인다. buf가 모자라면 null.
pub fn appendScript(buf: []u8, l: Layout) ?[]const u8 {
    return std.fmt.bufPrint(buf,
        \\start={d}, size={d}, type=uefi, name={s}
        \\start={d}, size={d}, type=linux, name={s}
        \\start={d}, size={d}, type=linux, name={s}
        \\
    , .{
        l.boot.start,   l.boot.size,   NAME_BOOT,
        l.config.start, l.config.size, NAME_CONFIG,
        l.home.start,   l.home.size,   NAME_HOME,
    }) catch null;
}

/// 목록의 상태 칸과 계획이 말하는 GPT 디스크(DB design 결정 9). 예: `GPT: EFI, macOS (APFS); 6 GB free`.
/// 파티션을 번호 순으로 이름 짓고 TARS 셋은 `TARS` 하나로, 나머지는 `N other`로 센다. 빈 자리는
/// largestGap(`--beside`가 쓸 자리)이다. buf가 모자라면 `GPT`.
pub fn gptText(buf: []u8, g: *const Gpt) []const u8 {
    var w = Fill{ .out = buf };
    w.put("GPT: ");
    var said = false;
    var tars = false;
    var others: usize = 0;
    for (g.slice()) |p| {
        const word: []const u8 = if (p.role != .none) blk: {
            if (tars) continue;
            tars = true;
            break :blk "TARS";
        } else switch (p.kind) {
            .efi => "EFI",
            .apfs => "macOS (APFS)",
            .hfs => "macOS (HFS+)",
            // 목록 줄의 글자는 DB-M0 그대로 둔다(체인들이 읽는다). 이름은 파티션 줄(DB-M1)이 말한다.
            .basic, .apple_boot, .other => {
                others += 1;
                continue;
            },
        };
        if (said) w.put(", ");
        w.put(word);
        said = true;
    }
    if (others > 0) {
        var num: [24]u8 = undefined;
        if (said) w.put(", ");
        w.put(std.fmt.bufPrint(&num, "{d} other", .{others}) catch "other");
        said = true;
    }
    if (!said) w.put("no partitions");
    if (largestGap(g, false)) |gap| {
        var size: [16]u8 = undefined;
        w.put("; ");
        w.put(formatSize(&size, gap.bytes(g.sector)));
        w.put(" free");
    } else {
        w.put("; no free space");
    }
    if (w.full) return "GPT";
    return buf[0..w.n];
}

/// 자리가 모자란 `--beside`의 거절 줄(DB design 결정 3). macOS에서 자리를 내는 명령을 함께 말한다 —
/// HFS+ 맥이면 `resizeVolume`, 아니면 APFS의 `resizeContainer`다. `disk0s2`는 맥의 보통 모양이고
/// 사람이 `diskutil list`로 확인한다(running-tars.md). 줄은 `Complain`으로 간다.
pub fn roomRefusal(sink: anytype, path: []const u8, g: *const Gpt, gap_bytes: u64) void {
    var size: [16]u8 = undefined;
    var hfs = false;
    for (g.slice()) |p| {
        if (p.kind == .hfs) hfs = true;
    }
    sink.print("the largest free space on {s} is {s}; TARS needs " ++ MIN_DISK_WORDS ++ "; nothing was changed.", .{
        path, formatSize(&size, gap_bytes),
    });
    sink.print("make room in macOS first: diskutil {s} disk0s2 <smaller size> (see diskutil list)", .{
        if (hfs) "resizeVolume" else "apfs resizeContainer",
    });
}

/// `--beside`의 계획. 디스크에 있는 것을 그대로 둔다는 것과, 어느 구간에 무엇이 몇 번으로 들어가는지를
/// 말한다. wipe_nums는 `--beside --wipe`가 먼저 지울 TARS 파티션 번호다(없으면 빈 슬라이스).
pub fn besideLines(
    sink: anytype,
    path: []const u8,
    size: []const u8,
    model: []const u8,
    holds: []const u8,
    gap: Gap,
    sector: u64,
    nums: [3]u8,
    wipe_nums: []const u8,
) void {
    sink.print("tars-install: {s} ({s}, {s}) keeps its partitions. it now holds: {s}\n", .{ path, size, model, holds });
    if (wipe_nums.len > 0) {
        sink.print("  the TARS partitions are erased first, your settings and home too:", .{});
        for (wipe_nums) |n| sink.print(" p{d}", .{n});
        sink.print("\n", .{});
    }
    sink.print("  TARS goes into the free space from MiB {d} to MiB {d}; no other partition is touched\n", .{
        gap.start * sector >> 20, gap.end * sector >> 20,
    });
    layoutRows(sink, nums);
    sink.print("  the Mac still starts macOS; hold Option at power-on and pick EFI Boot for TARS\n", .{});
}

/// 새 설치가 만드는 세 줄. 통째 설치는 {1, 2, 3}이다.
pub fn layoutRows(sink: anytype, nums: [3]u8) void {
    sink.print("  p{d}  768 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n", .{nums[0]});
    sink.print("  p{d}  256 MiB  Linux       ext2   tars-config <- your settings, empty at first\n", .{nums[1]});
    sink.print("  p{d}     rest  Linux       ext4   tars-home   <- your home, empty at first\n", .{nums[2]});
}

// ── 기존 파티션 지정 (DB-M1) ──────────────────────────────────────────
//
// macOS의 디스크 유틸리티로 나누면 새 자리가 늘 포맷된 파티션이 된다(크기만 주는 `diskutil apfs
// resizeContainer`만 빈 자리를 남긴다). `tars-install /dev/sda3`이 그 파티션을 지우고 그 자리(와 바로 붙은
// 빈 자리)에 셋을 놓는다. 쓰기는 `--beside --wipe`의 길 그대로다 — 지울 번호가 TARS 셋이 아니라 사람이
// 고른 하나일 뿐이다. 남의 파티션을 지우는 일이라 받는 것을 좁게 정한다(takeable).

/// 파티션 노드(`/dev/sda3` · `/dev/nvme0n1p3` · `/dev/mmcblk0p3`)의 디스크와 번호. 디스크는 storage.DISKS의
/// 원소이고(수명이 무한한 리터럴), 이름은 storage.partitionName과 같은 규칙으로 지어 맞춘다 — 부팅 때 init이
/// 찾는 이름과 갈리지 않게. 번호는 GPT 엔트리 수(MAX_PARTS)까지다.
pub const PartArg = struct { disk: [:0]const u8, number: u8 };

pub fn splitPartition(path: []const u8) ?PartArg {
    for (storage.DISKS) |d| {
        if (!std.mem.startsWith(u8, path, d)) continue;
        var n: u8 = 1;
        while (n <= MAX_PARTS) : (n += 1) {
            var buf: [32]u8 = undefined;
            const name = storage.partitionName(&buf, d, n) orelse continue;
            if (std.mem.eql(u8, name, path)) return .{ .disk = d, .number = n };
        }
    }
    return null;
}

/// 파티션 머리에 보이는 파일시스템. 머리는 HEAD_BYTES(34KiB) — 아래의 서명은 전부 그 안이다.
pub const Fs = enum { none, fat12, fat16, fat32, exfat, ntfs, hfs, apfs, ext, other };

pub const FsSeen = struct {
    fs: Fs,
    /// FAT의 부트 섹터 라벨(공백을 벗긴 것, `NO NAME`은 빈 문자열). head 안을 가리킨다.
    label: []const u8 = "",
};

/// 순서가 뜻이 있다. NTFS · exFAT은 부트 섹터 끝에 55 AA를 가져서 FAT보다 먼저 OEM 이름(오프셋 3)으로
/// 가린다. FAT은 FAT32의 BS_FilSysType(82)과 FAT12/16의 것(54)을 본다. HFS+는 1024의 `H+`·`HX`, APFS는
/// 컨테이너 superblock의 `NXSB`(32), ext는 superblock의 매직(1080의 53 EF)이다. 다 0이면 none이다.
pub fn fsOf(head: []const u8) FsSeen {
    if (head.len >= 11 and std.mem.eql(u8, head[3..11], "NTFS    ")) return .{ .fs = .ntfs };
    if (head.len >= 11 and std.mem.eql(u8, head[3..11], "EXFAT   ")) return .{ .fs = .exfat };
    if (head.len >= 512 and head[510] == 0x55 and head[511] == 0xAA) {
        if (std.mem.eql(u8, head[82..90], "FAT32   ")) return .{ .fs = .fat32, .label = fatLabel(head[71..82]) };
        if (std.mem.eql(u8, head[54..62], "FAT16   ")) return .{ .fs = .fat16, .label = fatLabel(head[43..54]) };
        if (std.mem.eql(u8, head[54..62], "FAT12   ")) return .{ .fs = .fat12, .label = fatLabel(head[43..54]) };
    }
    if (head.len >= 36 and std.mem.eql(u8, head[32..36], "NXSB")) return .{ .fs = .apfs };
    if (head.len >= 1026 and (std.mem.eql(u8, head[1024..1026], "H+") or std.mem.eql(u8, head[1024..1026], "HX"))) return .{ .fs = .hfs };
    if (head.len >= 1082 and head[1080] == 0x53 and head[1081] == 0xEF) return .{ .fs = .ext };
    for (head) |b| {
        if (b != 0) return .{ .fs = .other };
    }
    return .{ .fs = .none };
}

fn fatLabel(raw: []const u8) []const u8 {
    const t = std.mem.trimEnd(u8, raw, " ");
    return if (std.mem.eql(u8, t, "NO NAME")) "" else t;
}

pub fn fsWord(fs: Fs) []const u8 {
    return switch (fs) {
        .none => "empty",
        .fat12 => "FAT12",
        .fat16 => "FAT16",
        .fat32 => "FAT32",
        .exfat => "exFAT",
        .ntfs => "NTFS",
        .hfs => "HFS+",
        .apfs => "APFS",
        .ext => "ext",
        .other => "unknown data",
    };
}

/// 지정 설치가 거절하는 까닭(DB-M1 plan 결정 13).
pub const Refusal = enum { tars, efi, macos, recovery, ntfs, filesystem };

/// 받는 것은 둘이다 — Basic Data 타입의 FAT · exFAT(디스크 유틸리티의 MS-DOS(FAT) · ExFAT), 그리고 머리가
/// 비어 있는 파티션(타입이 macOS 쪽이 아닐 때). 나머지는 null이 아니라 까닭이다. APFS · HFS+ 타입은 머리와
/// 상관없이 거절한다 — 빈 APFS 컨테이너인지 macOS인지 가리려면 APFS를 읽어야 하는데 그것을 안 한다.
pub fn takeable(p: Part, fs: Fs) ?Refusal {
    if (p.role != .none) return .tars;
    switch (p.kind) {
        .efi => return .efi,
        .apfs, .hfs => return .macos,
        .apple_boot => return .recovery,
        .basic, .other => {},
    }
    if (fs == .none) return null;
    if (fs == .ntfs) return .ntfs;
    if (p.kind == .basic and (fs == .fat12 or fs == .fat16 or fs == .fat32 or fs == .exfat)) return null;
    return .filesystem;
}

/// 그 파티션의 구간에 바로 앞뒤의 빈 구간을 붙인 것(DB-M1 plan 결정 14). 디스크 유틸리티는 파티션 사이에
/// 여유를 두기도 한다 — 그 자리까지 쓴다. 다른 곳의 빈 자리는 안 쓴다(사람이 고른 곳에 깐다). 두 끝은
/// largestGap과 같이 1MiB에 맞춘다. 맞춘 뒤 비면 null.
pub fn gapAround(g: *const Gpt, number: u8) ?Gap {
    const me = g.byNumber(number) orelse return null;
    var lo = g.first_usable;
    var hi = g.last_usable + 1;
    for (g.slice()) |p| {
        if (p.number == number) continue;
        if (p.last < me.first) lo = @max(lo, p.last + 1);
        if (p.first > me.last) hi = @min(hi, p.first);
    }
    const step: u64 = (1 << 20) / g.sector;
    const s = std.mem.alignForward(u64, lo, step);
    const e = std.mem.alignBackward(u64, hi, step);
    if (e <= s) return null;
    return .{ .start = s, .end = e };
}

/// 파티션 줄의 이름 칸. TARS는 GPT 이름, macOS 쪽은 타입, 나머지는 파일시스템과 라벨이다.
pub fn partWhat(buf: []u8, p: Part, seen: FsSeen) []const u8 {
    switch (p.role) {
        .boot => return NAME_BOOT,
        .config => return NAME_CONFIG,
        .home => return NAME_HOME,
        .none => {},
    }
    switch (p.kind) {
        .efi => return "EFI",
        .apfs => return "macOS (APFS)",
        .hfs => return "macOS (HFS+)",
        .apple_boot => return "macOS Recovery",
        .basic, .other => {},
    }
    if (seen.label.len == 0) return fsWord(seen.fs);
    var label_buf: [16]u8 = undefined;
    return std.fmt.bufPrint(buf, "{s} \"{s}\"", .{ fsWord(seen.fs), printable(&label_buf, seen.label) }) catch fsWord(seen.fs);
}

/// 목록에서 GPT 디스크 줄 밑의 파티션 한 줄(DB-M1 plan 결정 16). 디스크 줄보다 두 칸 더 들인다 — 체인들은
/// `^  /dev/<disk> +`로 디스크 줄을 고르므로 이 줄에 안 걸린다. here면 지정 설치의 명령을 붙인다.
pub fn partRow(sink: anytype, node: []const u8, size: []const u8, what: []const u8, here: bool) void {
    if (here) {
        sink.print("    {s:<14} {s:>7}  {s}  <- tars-install {s} installs here\n", .{ node, size, what, node });
    } else {
        sink.print("    {s:<14} {s:>7}  {s}\n", .{ node, size, what });
    }
}

/// 지정 설치의 계획. besideLines와 같은 모양이고, 첫 줄이 지울 파티션을 말한다.
pub fn takeLines(
    sink: anytype,
    node: []const u8,
    what: []const u8,
    part_size: []const u8,
    path: []const u8,
    size: []const u8,
    model: []const u8,
    holds: []const u8,
    gap: Gap,
    sector: u64,
    nums: [3]u8,
) void {
    // 두 줄이다 — 한 줄이면 11인치 화면(1366 폭)에서 꺾였다(2026-11-05 Air 실기).
    sink.print("tars-install: {s} ({s}, {s}) will be erased, the files on it too.\n", .{ node, what, part_size });
    sink.print("  the other partitions of {s} ({s}, {s}) are kept. it now holds: {s}\n", .{ path, size, model, holds });
    sink.print("  TARS goes into {s} and the free space next to it, from MiB {d} to MiB {d}; no other partition is touched\n", .{
        node, gap.start * sector >> 20, gap.end * sector >> 20,
    });
    layoutRows(sink, nums);
    sink.print("  the Mac still starts macOS; hold Option at power-on and pick EFI Boot for TARS\n", .{});
}

/// 지정 설치의 거절 줄(DB-M1 plan 결정 13). 줄은 `Complain`으로 간다. path는 그 파티션의 디스크다.
pub fn takeRefusal(sink: anytype, node: []const u8, path: []const u8, why: Refusal, seen: FsSeen) void {
    switch (why) {
        .tars => sink.print("{s} is a TARS partition; tars-install {s} updates TARS and tars-install {s} --beside --wipe lays it down again", .{ node, path, path }),
        .efi => sink.print("{s} is an EFI System partition the firmware boots from; nothing was changed", .{node}),
        .macos => {
            sink.print("{s} is an APFS or HFS+ partition and may hold macOS; nothing was changed.", .{node});
            sink.print("if you made it for TARS, turn it into free space in macOS (diskutil eraseVolume free free diskXsN) and use tars-install {s} --beside", .{path});
        },
        .recovery => sink.print("{s} is the macOS Recovery partition; nothing was changed", .{node}),
        .ntfs => sink.print("{s} holds NTFS (Windows or Boot Camp); tars-install takes only an empty, FAT or exFAT partition. nothing was changed", .{node}),
        .filesystem => sink.print("{s} holds {s}; tars-install takes only an empty, FAT or exFAT partition. nothing was changed", .{ node, fsWord(seen.fs) }),
    }
}
