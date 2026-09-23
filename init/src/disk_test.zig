const std = @import("std");
const disk = @import("disk.zig");

/// tars-install의 순수한 쪽을 본다. storage_test와 같은 모양이다 — 호스트
/// 아키텍처로 컨테이너가 직접 돌리고, 실패하면 무엇이 틀렸는지 한 줄 찍고
/// 에러로 끝난다.
///
/// 서명 오프셋(ISO 32769 · GPT 512 · MBR 510)은 이 파일과 disk.zig가 같은 수를
/// 두 번 적은 것이라 여기서는 원리적으로 못 잡는다. 그것을 보는 것은 install
/// 체인이다 — 부팅 1의 목록 머리 줄이 진짜 ISO를 `iso9660 TARS`로 읽어야 한다.
var head: [disk.HEAD_BYTES]u8 = undefined;

fn clear() []u8 {
    @memset(&head, 0);
    return &head;
}

fn expectKind(got: disk.Seen, want: disk.Kind, label: []const u8, what: []const u8) !void {
    if (got.kind != want or !std.mem.eql(u8, got.label, label)) {
        std.debug.print("FAIL: {s}: want {s} '{s}', got {s} '{s}'\n", .{
            what, @tagName(want), label, @tagName(got.kind), got.label,
        });
        return error.WrongKind;
    }
}

fn expectText(got: []const u8, want: []const u8, what: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: {s}: want '{s}', got '{s}'\n", .{ what, want, got });
        return error.WrongText;
    }
}

pub fn main() !void {
    var buf: [64]u8 = undefined;

    // ── 1. describe — 넷의 서명과 빈 디스크 ─────────────────────────
    try expectKind(disk.describe(clear()), .blank, "", "all zero");

    {
        const h = clear();
        h[32768] = 1;
        @memcpy(h[32769..][0..5], "CD001");
        @memset(h[32768 + 40 ..][0..32], ' ');
        @memcpy(h[32768 + 40 ..][0..4], "TARS");
        // 하이브리드 ISO는 MBR 서명도 있다. 그래도 iso9660으로 읽어야 한다 —
        // 이것이 없으면 USB 스틱의 ISO가 목록에 "mbr"로 보인다.
        h[510] = 0x55;
        h[511] = 0xAA;
        try expectKind(disk.describe(h), .iso9660, "TARS", "hybrid iso");
    }
    {
        const h = clear();
        h[1024 + 56] = 0x53;
        h[1024 + 57] = 0xEF;
        @memcpy(h[1024 + 120 ..][0..11], "debian-root");
        try expectKind(disk.describe(h), .ext2, "debian-root", "whole-disk ext2");
    }
    {
        const h = clear();
        h[510] = 0x55;
        h[511] = 0xAA;
        @memcpy(h[512..][0..8], "EFI PART");
        try expectKind(disk.describe(h), .gpt, "", "gpt with protective mbr");
    }
    {
        const h = clear();
        h[510] = 0x55;
        h[511] = 0xAA;
        try expectKind(disk.describe(h), .mbr, "", "plain mbr");
    }
    {
        const h = clear();
        h[4000] = 0x01;
        try expectKind(disk.describe(h), .unknown, "", "one stray byte");
    }
    // 짧은 읽기. 매체가 HEAD_BYTES보다 작아도 죽지 않는다.
    try expectKind(disk.describe(clear()[0..600]), .blank, "", "short read");

    // ── 2. stateText ────────────────────────────────────────────────
    try expectText(disk.stateText(&buf, .{ .kind = .blank }), "blank", "blank state");
    try expectText(disk.stateText(&buf, .{ .kind = .gpt }), "foreign (gpt)", "gpt state");
    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "tars-config" }), "foreign (ext2 tars-config)", "ext2 state");
    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "" }), "foreign (ext2)", "unlabelled ext2 state");
    try expectText(disk.stateText(&buf, .{ .kind = .unknown }), "foreign (unknown data)", "unknown state");

    // ── 3. formatSize — 10진이다 ────────────────────────────────────
    try expectText(disk.formatSize(&buf, 2 * 1024 * 1024 * 1024), "2 GB", "2 GiB disk");
    try expectText(disk.formatSize(&buf, 512_110_190_592), "512 GB", "512 GB ssd");
    try expectText(disk.formatSize(&buf, 50_640_896), "50 MB", "the iso");
    try expectText(disk.formatSize(&buf, 0), "0 B", "empty");

    // ── 4. parseArgs ────────────────────────────────────────────────
    {
        const none = [_][*:0]const u8{};
        if (disk.parseArgs(&none) != .list) return error.NoArgsNotList;

        const one = [_][*:0]const u8{"/dev/nvme0n1"};
        switch (disk.parseArgs(&one)) {
            .install => |i| if (!std.mem.eql(u8, i.disk, "/dev/nvme0n1") or i.yes) return error.OneArgWrong,
            else => return error.OneArgNotInstall,
        }

        const two = [_][*:0]const u8{ "/dev/nvme0n1", "--yes" };
        switch (disk.parseArgs(&two)) {
            .install => |i| if (!i.yes) return error.YesIgnored,
            else => return error.TwoArgsNotInstall,
        }

        // 디스크를 빠뜨리고 --yes만 친 경우. "--yes라는 디스크"로 가면 안 된다.
        const flag_only = [_][*:0]const u8{"--yes"};
        if (disk.parseArgs(&flag_only) != .usage) return error.FlagTakenAsDisk;

        const swapped = [_][*:0]const u8{ "--yes", "/dev/nvme0n1" };
        if (disk.parseArgs(&swapped) != .usage) return error.SwappedAccepted;

        const typo = [_][*:0]const u8{ "/dev/nvme0n1", "--yse" };
        if (disk.parseArgs(&typo) != .usage) return error.TypoAccepted;

        const three = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "x" };
        if (disk.parseArgs(&three) != .usage) return error.ThreeAccepted;

        // --wipe는 혼자서도, --yes와 어느 순서로도 온다(DI-M2).
        const wipe = [_][*:0]const u8{ "/dev/nvme0n1", "--wipe" };
        switch (disk.parseArgs(&wipe)) {
            .install => |i| if (!i.wipe or i.yes) return error.WipeWrong,
            else => return error.WipeNotInstall,
        }
        const wipe_yes = [_][*:0]const u8{ "/dev/nvme0n1", "--wipe", "--yes" };
        const yes_wipe = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "--wipe" };
        for ([_][]const [*:0]const u8{ &wipe_yes, &yes_wipe }) |args| {
            switch (disk.parseArgs(args)) {
                .install => |i| if (!i.wipe or !i.yes) return error.WipeYesWrong,
                else => return error.WipeYesNotInstall,
            }
        }
        // 같은 플래그 둘. 조용히 받으면 `--yes --yes`로 --wipe를 빠뜨린 오타가
        // 설치로 간다.
        const twice = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "--yes" };
        if (disk.parseArgs(&twice) != .usage) return error.TwiceAccepted;
        const wipe_only = [_][*:0]const u8{"--wipe"};
        if (disk.parseArgs(&wipe_only) != .usage) return error.WipeTakenAsDisk;
        const four = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "--wipe", "x" };
        if (disk.parseArgs(&four) != .usage) return error.FourAccepted;
    }

    // ── 5. knownDisk — 파티션과 부팅 매체는 대상이 아니다 ─────────────
    if (disk.knownDisk("/dev/nvme0n1") == null) return error.NvmeUnknown;
    if (disk.knownDisk("/dev/sda") == null) return error.SdaUnknown;
    if (disk.knownDisk("/dev/nvme0n1p1") != null) return error.PartitionAccepted;
    if (disk.knownDisk("/dev/sr0") != null) return error.CdromAccepted;
    if (disk.knownDisk("nvme0n1") != null) return error.BareNameAccepted;

    try expectText(disk.sysName("/dev/nvme0n1"), "nvme0n1", "sysName");

    // ── 6. confirmed — 대문자 YES만 ─────────────────────────────────
    if (!disk.confirmed("YES\n")) return error.YesRefused;
    if (!disk.confirmed("YES\r\n")) return error.YesCrLfRefused;
    if (disk.confirmed("yes\n")) return error.LowerYesAccepted;
    if (disk.confirmed("y\n")) return error.YAccepted;
    if (disk.confirmed("\n")) return error.EmptyAccepted;
    if (disk.confirmed("YES please\n")) return error.YesPrefixAccepted;

    // ── 7. 라벨의 제어 문자는 ? 로 찍힌다 ────────────────────────────
    //
    // 라벨은 디스크의 바이트다. ESC가 든 라벨이 목록을 거쳐 터미널을 조종하면
    // 안 된다(DI-M1 실측 15). UTF-8은 그대로 둔다.
    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "a\x1b[2Jb" }), "foreign (ext2 a?[2Jb)", "esc in a label");
    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "del\x7f" }), "foreign (ext2 del?)", "del in a label");
    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "설정" }), "foreign (ext2 설정)", "utf-8 label");
    {
        var small: [3]u8 = undefined;
        try expectText(disk.printable(&small, "abcdef"), "abc", "printable cuts at the buffer");
    }

    // ── 8. isTarsMedium — 볼륨 ID TARS인 ISO만 ────────────────────────
    if (!disk.isTarsMedium(.{ .kind = .iso9660, .label = "TARS" })) return error.TarsMediumMissed;
    if (disk.isTarsMedium(.{ .kind = .iso9660, .label = "ISOIMAGE" })) return error.OtherIsoTaken;
    if (disk.isTarsMedium(.{ .kind = .ext2, .label = "TARS" })) return error.Ext2TarsTaken;

    // ── 9. isFat32 — 82의 여덟 글자와 55 AA ──────────────────────────
    {
        const h = clear();
        @memcpy(h[82..][0..8], "FAT32   ");
        h[510] = 0x55;
        h[511] = 0xAA;
        if (!disk.isFat32(h)) return error.Fat32Missed;
        h[511] = 0;
        if (disk.isFat32(h)) return error.Fat32WithoutSignature;
        h[511] = 0xAA;
        @memcpy(h[82..][0..8], "FAT16   ");
        if (disk.isFat32(h)) return error.Fat16Taken;
        if (disk.isFat32(clear()[0..511])) return error.ShortFat32;
    }

    // ── 10. espConf — cmdline 줄에만 표지 하나 ──────────────────────
    //
    // 원본은 boot/limine.conf의 항목 부분을 글자 그대로 옮긴 것이다. 파일
    // 자체를 이 검사가 못 읽으므로(패키지 밖) 실물이 표지를 받는지는 install
    // 체인 부팅 2의 `Kernel command line:` 줄이 본다.
    {
        const iso =
            \\serial: yes
            \\timeout: 0
            \\
            \\/TARS
            \\    protocol: linux
            \\    kernel_path: boot():/boot/bzImage
            \\    module_path: boot():/boot/initrd.cpio
            \\    cmdline: console=ttyS0
            \\
        ;
        const want =
            \\serial: yes
            \\timeout: 0
            \\
            \\/TARS
            \\    protocol: linux
            \\    kernel_path: boot():/boot/bzImage
            \\    module_path: boot():/boot/initrd.cpio
            \\    cmdline: console=ttyS0 tars.installed
            \\
        ;
        var out: [512]u8 = undefined;
        const got = disk.espConf(&out, iso) orelse return error.EspConfNull;
        try expectText(got, want, "esp limine.conf");
        // 한 번 더 지나도 표지는 하나다.
        var again: [512]u8 = undefined;
        const twice_got = disk.espConf(&again, got) orelse return error.EspConfAgainNull;
        try expectText(twice_got, want, "esp limine.conf twice");
        // cmdline이 없는 설정은 거부한다 — 표지 없이 설치하면 설정을 못 찾는다.
        if (disk.espConf(&out, "serial: yes\n/TARS\n    protocol: linux\n") != null) return error.NoCmdlineAccepted;
        // 모자란 버퍼는 null이지 잘린 파일이 아니다.
        var tiny: [40]u8 = undefined;
        if (disk.espConf(&tiny, iso) != null) return error.TruncatedConf;
    }

    std.debug.print("disk_test: signatures, sizes, arguments, labels, the YES gate and the ESP conf hold\n", .{});
}
