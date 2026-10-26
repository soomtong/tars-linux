const std = @import("std");
const linux = std.os.linux;
const disk = @import("disk.zig");
const control = @import("control.zig");

/// install 체인의 자리. `zig build test`는 init/에서 돈다.
const INSTALL_CHECK: [:0]const u8 = "../install/check.sh";

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

/// 파일 하나를 buf에. config_front_edit_test의 것과 같은 루프다.
fn readAll(path: [:0]const u8, buf: []u8) ![]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (linux.errno(rc) != .SUCCESS) {
        std.debug.print("FAIL: cannot open {s}\n", .{path});
        return error.NoFile;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (linux.errno(n) != .SUCCESS) {
            std.debug.print("FAIL: cannot read {s}\n", .{path});
            return error.NoFile;
        }
        if (n == 0) break;
        len += n;
    }
    return buf[0..len];
}

fn expectState(got: disk.State, want: disk.State, what: []const u8) !void {
    const same = std.meta.activeTag(got) == std.meta.activeTag(want) and
        std.mem.eql(u8, disk.stateWord(got), disk.stateWord(want));
    if (!same) {
        std.debug.print("FAIL: {s}: want .{s} '{s}', got .{s} '{s}'\n", .{
            what, @tagName(want), disk.stateWord(want), @tagName(got), disk.stateWord(got),
        });
        return error.WrongState;
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
        const wipe_twice = [_][*:0]const u8{ "/dev/nvme0n1", "--wipe", "--wipe" };
        if (disk.parseArgs(&wipe_twice) != .usage) return error.WipeTwiceAccepted;
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
            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init
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
            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init tars.installed
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
        // 주석 줄은 limine에게 주석이다. 표지를 받으면 안 된다.
        {
            var o: [64]u8 = undefined;
            const g = disk.espConf(&o, "# cmdline: x\n    cmdline: a\n") orelse return error.CommentConfNull;
            try expectText(g, "# cmdline: x\n    cmdline: a tars.installed\n", "comment line untouched");
        }
        // 마지막 줄에 개행이 없으면 결과에도 없다.
        {
            var o: [64]u8 = undefined;
            const g = disk.espConf(&o, "/T\n cmdline: a") orelse return error.NoNewlineConfNull;
            try expectText(g, "/T\n cmdline: a tars.installed", "no final newline");
        }
        // 버퍼 경계. 결과 길이와 딱 같으면 되고 한 바이트 모자라면 null이다.
        {
            const exact_want = " cmdline: a tars.installed";
            var fit: [exact_want.len]u8 = undefined;
            const g = disk.espConf(&fit, " cmdline: a") orelse return error.ExactFitNull;
            try expectText(g, exact_want, "exact fit");
            var short: [exact_want.len - 1]u8 = undefined;
            if (disk.espConf(&short, " cmdline: a") != null) return error.OneShortAccepted;
        }
    }

    // ── 11. clip — 넘치는 줄은 앞부분과 `...\n` (DC-M2) ────────────────
    {
        var small: [16]u8 = undefined;
        try expectText(disk.clip(&small, "a {s}\n", .{"b"}), "a b\n", "a line that fits");
        // 넘치면 앞 12바이트가 남고 끝 넷이 `...\n`이다. 이 검사가 Zig의
        // bufPrint가 넘칠 때 buf를 채워 둔다는 것까지 본다 — 안 채우면 앞
        // 12바이트가 undefined라 글자가 안 맞는다.
        try expectText(
            disk.clip(&small, "tars-install: {s} end\n", .{"/dev/aaaaaaaaaaaaaaaaaaaaaaaa"}),
            "tars-install...\n",
            "a line that overflows",
        );
    }

    // ── 12. 앞의 구조가 뒤의 옛 서명을 이긴다 (DC-M2) ─────────────────
    {
        // 4Kn 디스크의 GPT. 보호 MBR은 0에, 헤더는 LBA 1 = 4096에 있다.
        const h = clear();
        h[510] = 0x55;
        h[511] = 0xAA;
        @memcpy(h[4096..][0..8], "EFI PART");
        try expectKind(disk.describe(h), .gpt, "", "4Kn gpt");
    }
    {
        // TARS ISO를 구웠던 스틱을 남의 도구로 GPT로 다시 만든 것. PVD가 남아
        // 있어도 GPT다 — 전에는 `iso9660 TARS`로 읽혀 부팅 매체 취급을 받았다.
        const h = clear();
        h[32768] = 1;
        @memcpy(h[32769..][0..5], "CD001");
        @memset(h[32768 + 40 ..][0..32], ' ');
        @memcpy(h[32768 + 40 ..][0..4], "TARS");
        h[510] = 0x55;
        h[511] = 0xAA;
        @memcpy(h[512..][0..8], "EFI PART");
        try expectKind(disk.describe(h), .gpt, "", "gpt over a stale iso");
    }
    {
        // 같은 스틱을 통째로 mkfs.ext2한 것. ext2 라벨이 이긴다.
        const h = clear();
        h[32768] = 1;
        @memcpy(h[32769..][0..5], "CD001");
        @memcpy(h[32768 + 40 ..][0..4], "TARS");
        h[1024 + 56] = 0x53;
        h[1024 + 57] = 0xEF;
        @memcpy(h[1024 + 120 ..][0..5], "stick");
        try expectKind(disk.describe(h), .ext2, "stick", "ext2 over a stale iso");
    }

    // ── 13. PVD의 음성 둘 (DI-M1 실측 15의 이월) ──────────────────────
    {
        // type 바이트가 1이 아니다. CD001 뒤의 모양이 같아도 primary volume
        // descriptor가 아니면(2는 supplementary) ISO로 안 읽는다.
        const h = clear();
        h[32768] = 2;
        @memcpy(h[32769..][0..5], "CD001");
        @memcpy(h[32768 + 40 ..][0..4], "TARS");
        if (disk.describe(h).kind == .iso9660) {
            std.debug.print("FAIL: a descriptor of type 2 was read as a primary volume\n", .{});
            return error.WrongPvdType;
        }
    }
    {
        // 볼륨 ID 32바이트를 공백 없이 꽉 채웠다. 라벨은 32글자 그대로이고,
        // `TARS`로 시작해도 TARS 매체가 아니다 — 접두사가 아니라 같음으로 본다.
        const h = clear();
        h[32768] = 1;
        @memcpy(h[32769..][0..5], "CD001");
        const id = "TARSXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
        @memcpy(h[32768 + 40 ..][0..32], id);
        const seen = disk.describe(h);
        try expectKind(seen, .iso9660, id, "a full 32-byte volume id");
        if (disk.isTarsMedium(seen)) {
            std.debug.print("FAIL: a volume id that only starts with TARS was taken as the medium\n", .{});
            return error.TarsPrefixTaken;
        }
    }

    // ── 14. 크기와 상태 (HC-M2) ──────────────────────────────────────
    if (disk.sectorsToBytes("2097152") != 1024 * 1024 * 1024) {
        std.debug.print("FAIL: 2097152 sectors are not 1 GiB\n", .{});
        return error.WrongBytes;
    }
    for ([_][]const u8{ "", "x", "-1", "12 " }) |t| {
        if (disk.sectorsToBytes(t) != null) {
            std.debug.print("FAIL: sectorsToBytes took '{s}'\n", .{t});
            return error.WrongBytes;
        }
    }
    try expectState(disk.headState(&buf, null), .{ .other = "unreadable" }, "a head that could not be read");
    try expectState(disk.headState(&buf, .{ .kind = .iso9660, .label = "TARS" }), .medium, "a second TARS stick");
    try expectState(disk.headState(&buf, .{ .kind = .iso9660, .label = "DEBIAN" }), .{ .other = "foreign (iso9660 DEBIAN)" }, "another iso");
    try expectState(disk.headState(&buf, .{ .kind = .blank }), .{ .other = "blank" }, "a blank disk");
    try expectText(disk.stateWord(.medium), "boot medium", "stateWord medium");
    try expectText(disk.stateWord(.installed), "TARS installed", "stateWord installed");
    try expectText(disk.stateWord(.{ .other = "foreign (gpt)" }), "foreign (gpt)", "stateWord other");

    // ── 15. 목록의 행 (HC-M2) ────────────────────────────────────────
    // 조각은 서식의 칸 그대로다 — `  {s:<14} {s:>7}  {s:<22} {s:<9}  {s}\n`.
    var out_buf: [2048]u8 = undefined;
    var out = control.Out{ .buf = &out_buf };
    disk.listRow(&out, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "0", "blank");
    try expectText(out.bytes(), "  " ++ "/dev/nvme0n1  " ++ " " ++ "   1 GB" ++ "  " ++ "QEMU NVMe Ctrl        " ++ " " ++
        "internal " ++ "  " ++ "blank\n", "an internal blank row");
    out = control.Out{ .buf = &out_buf };
    disk.listRow(&out, "/dev/sda", "16 GB", "USB Stick", "1", "TARS installed");
    try expectText(out.bytes(), "  " ++ "/dev/sda      " ++ " " ++ "  16 GB" ++ "  " ++ "USB Stick             " ++ " " ++
        "removable" ++ "  " ++ "TARS installed\n", "a removable installed row");

    // ── 16. 계획 (HC-M2) ─────────────────────────────────────────────
    const P1 = "  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n";
    out = control.Out{ .buf = &out_buf };
    disk.planLines(&out, true, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "TARS installed", true);
    try expectText(out.bytes(), "tars-install: /dev/nvme0n1 (1 GB, QEMU NVMe Ctrl) already has TARS. p1 will be updated, p2 (your settings) is kept.\n" ++
        P1 ++
        "  p2    1 GiB  Linux       ext2   tars-config <- not opened\n" ++
        "  tars-install /dev/nvme0n1 --wipe erases both instead\n", "the update plan");
    out = control.Out{ .buf = &out_buf };
    disk.planLines(&out, false, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "blank", false);
    const fresh = "tars-install: /dev/nvme0n1 (1 GB, QEMU NVMe Ctrl) will be erased. it now holds: blank\n" ++
        P1 ++
        "  p2    1 GiB  Linux       ext2   tars-config <- your settings, empty at first\n" ++
        "  rest unallocated\n";
    try expectText(out.bytes(), fresh, "the fresh plan");
    out = control.Out{ .buf = &out_buf };
    disk.planLines(&out, false, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "blank", true);
    try expectText(out.bytes(), fresh ++ "  the settings now on p2 are erased too\n", "the fresh plan over old settings");

    // ── 17. 도구가 끝난 모양 (HC-M2) ─────────────────────────────────
    // status는 wait4의 모양으로 짓는다 — exit는 code << 8, 시그널은 번호 그대로.
    out = control.Out{ .buf = &out_buf };
    if (!disk.toolOk(&out, "/usr/bin/sfdisk", 0) or out.len != 0) {
        std.debug.print("FAIL: exit 0 was not ok, or it said something\n", .{});
        return error.WrongTool;
    }
    if (disk.toolOk(&out, "/usr/bin/sfdisk", 1 << 8)) {
        std.debug.print("FAIL: exit 1 was ok\n", .{});
        return error.WrongTool;
    }
    try expectText(out.bytes(), "/usr/bin/sfdisk failed (exit 1); what it said:", "exit 1");
    out = control.Out{ .buf = &out_buf };
    if (disk.toolOk(&out, "/usr/bin/mke2fs", 9)) {
        std.debug.print("FAIL: SIGKILL was ok\n", .{});
        return error.WrongTool;
    }
    try expectText(out.bytes(), "/usr/bin/mke2fs was killed (signal 9); what it said:", "SIGKILL");

    // ── 18. 쓰는 법 — 마지막 줄이 install 체인의 LIST_END (HC-M2) ──────
    out = control.Out{ .buf = &out_buf };
    disk.usageLines(&out);
    try expectText(out.bytes(), "tars-install <disk>         install onto <disk>; a disk that has TARS is only updated\n" ++
        "tars-install <disk> --yes   same, without asking\n" ++
        "tars-install <disk> --wipe  erase <disk> even if it has TARS, settings too\n", "usage");
    var check_buf: [65536]u8 = undefined;
    const check = try readAll(INSTALL_CHECK, &check_buf);
    const key = "\nLIST_END=\"";
    const from = (std.mem.indexOf(u8, check, key) orelse {
        std.debug.print("FAIL: install/check.sh has no LIST_END=\"\n", .{});
        return error.NoListEnd;
    }) + key.len;
    const to = std.mem.indexOfScalarPos(u8, check, from, '"') orelse return error.NoListEnd;
    const lines = out.bytes();
    const last = std.mem.trimEnd(u8, lines, "\n");
    try expectText(last[(std.mem.lastIndexOfScalar(u8, last, '\n') orelse 0) + 1 ..], check[from..to], "the last usage line is the chain's LIST_END");

    std.debug.print("disk_test: signatures, sizes, arguments, labels, the YES gate and the ESP conf hold\n", .{});
    std.debug.print("disk_test: the state column, a list row, both plans, a tool's end and the usage lines are the installer's words\n", .{});
}
