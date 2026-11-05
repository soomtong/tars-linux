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

        // DB-M0: --beside는 셋째 플래그다. 셋 다 어느 순서로도, 한 번씩만.
        const beside = [_][*:0]const u8{ "/dev/sda", "--beside" };
        switch (disk.parseArgs(&beside)) {
            .install => |i| if (!i.beside or i.yes or i.wipe) return error.BesideWrong,
            else => return error.BesideNotInstall,
        }
        const all = [_][*:0]const u8{ "/dev/sda", "--wipe", "--yes", "--beside" };
        switch (disk.parseArgs(&all)) {
            .install => |i| if (!i.beside or !i.yes or !i.wipe) return error.AllThreeWrong,
            else => return error.AllThreeNotInstall,
        }
        switch (disk.parseArgs(&two)) {
            .install => |i| if (i.beside) return error.BesideByDefault,
            else => return error.TwoArgsNotInstall,
        }
        const beside_twice = [_][*:0]const u8{ "/dev/sda", "--beside", "--yes", "--beside" };
        if (disk.parseArgs(&beside_twice) != .usage) return error.BesideTwiceAccepted;
        const five = [_][*:0]const u8{ "/dev/sda", "--beside", "--yes", "--wipe", "x" };
        if (disk.parseArgs(&five) != .usage) return error.FiveAccepted;
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

    // ── 10. espConf — timeout 3, 엔트리 하나 또는 둘 (DI-M2, KU-M0) ──────
    //
    // 원본은 boot/limine.conf를 글자 그대로 옮긴 것이다. 파일 자체를 이 검사가
    // 못 읽으므로(패키지 밖) 실물이 표지를 받는지는 install 체인 부팅 2의
    // `Kernel command line:` 줄이, 엔트리 둘은 부팅 4 · 4b가 본다.
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
        const one =
            \\serial: yes
            \\timeout: 3
            \\
            \\/TARS 0.1.4
            \\    protocol: linux
            \\    kernel_path: boot():/boot/bzImage
            \\    module_path: boot():/boot/initrd.cpio
            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init tars.installed
            \\
        ;
        const two = one ++
            \\
            \\/TARS 0.1.3 (old)
            \\    protocol: linux
            \\    kernel_path: boot():/boot/old/bzImage
            \\    module_path: boot():/boot/old/initrd.cpio
            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init tars.installed tars.slot=old
            \\
        ;
        var out: [1024]u8 = undefined;
        const got = disk.espConf(&out, iso, "0.1.4", null) orelse return error.EspConfNull;
        try expectText(got, one, "esp limine.conf, one entry");
        const got2 = disk.espConf(&out, iso, "0.1.4", "0.1.3") orelse return error.EspConfTwoNull;
        try expectText(got2, two, "esp limine.conf, new and old");
        // 엔트리 하나의 결과를 다시 넣어도 표지는 하나다.
        var again: [1024]u8 = undefined;
        const twice_got = disk.espConf(&again, one, "0.1.4", null) orelse return error.EspConfAgainNull;
        try expectText(twice_got, one, "esp limine.conf twice");
        // 엔트리가 둘인 conf(ESP의 것)는 원본이 될 수 없다.
        if (disk.espConf(&again, two, "0.1.4", null) != null) return error.TwoEntriesAccepted;
        // cmdline이 없는 설정은 거부한다 — 표지 없이 설치하면 설정을 못 찾는다.
        if (disk.espConf(&out, "timeout: 0\n/TARS\n    protocol: linux\n", "0.1.4", null) != null) return error.NoCmdlineAccepted;
        // timeout:이 없으면 ISO conf의 모양이 바뀐 것이다.
        if (disk.espConf(&out, "serial: yes\n/TARS\n    cmdline: a\n", "0.1.4", null) != null) return error.NoTimeoutAccepted;
        // old의 경로를 못 바꾸면 거부한다 — old 엔트리가 new의 파일을 가리키게 된다.
        {
            const odd = "timeout: 0\n/TARS\n    kernel_path: boot(2):/bzImage\n    cmdline: a\n";
            if (disk.espConf(&out, odd, "0.1.4", "0.1.3") != null) return error.OldPathUnmoved;
            // old가 없으면 그 줄은 손대지 않으니 된다.
            _ = disk.espConf(&out, odd, "0.1.4", null) orelse return error.OddOneNull;
        }
        // 버전 글자에 개행 · 공백이 있으면 거부한다(plainVersion).
        if (disk.espConf(&out, iso, "0.1.4", "0.1.3\n/X") != null) return error.NewlineVersion;
        if (disk.espConf(&out, iso, "", null) != null) return error.EmptyVersion;
        // 모자란 버퍼는 null이지 잘린 파일이 아니다.
        var tiny: [40]u8 = undefined;
        if (disk.espConf(&tiny, iso, "0.1.4", null) != null) return error.TruncatedConf;
        // 주석 줄은 limine에게 주석이다. 표지를 받으면 안 된다.
        {
            var o: [96]u8 = undefined;
            const g = disk.espConf(&o, "timeout: 0\n/T\n# cmdline: x\n    cmdline: a\n", "1", null) orelse return error.CommentConfNull;
            try expectText(g, "timeout: 3\n/TARS 1\n# cmdline: x\n    cmdline: a tars.installed\n", "comment line untouched");
        }
        // 마지막 줄에 개행이 없어도 결과는 개행으로 끝난다.
        {
            var o: [64]u8 = undefined;
            const g = disk.espConf(&o, "timeout: 0\n/T\n cmdline: a", "1", null) orelse return error.NoNewlineConfNull;
            try expectText(g, "timeout: 3\n/TARS 1\n cmdline: a tars.installed\n", "no final newline in, one out");
        }
        // 버퍼 경계. 결과 길이와 딱 같으면 되고 한 바이트 모자라면 null이다.
        {
            const exact_want = "timeout: 3\n/TARS 1\n cmdline: a tars.installed\n";
            var fit: [exact_want.len]u8 = undefined;
            const g = disk.espConf(&fit, "timeout: 0\n/T\n cmdline: a\n", "1", null) orelse return error.ExactFitNull;
            try expectText(g, exact_want, "exact fit");
            var short: [exact_want.len - 1]u8 = undefined;
            if (disk.espConf(&short, "timeout: 0\n/T\n cmdline: a\n", "1", null) != null) return error.OneShortAccepted;
        }
        // plainVersion — BV의 글자는 통과하고, 빈 것 · 공백 · 개행 · 65자는 아니다.
        if (!disk.plainVersion("0.1.3") or !disk.plainVersion("0.1.3+abc1234-dirty")) return error.PlainVersionRejected;
        if (disk.plainVersion("") or disk.plainVersion("0.1 3") or disk.plainVersion("0.1.3\n")) return error.PlainVersionAccepted;
        const long: [65]u8 = @splat('x');
        if (disk.plainVersion(&long) or !disk.plainVersion(long[0..64])) return error.PlainVersionLength;
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

    // ── 16. 계획 (HC-M2, KU-M0) ──────────────────────────────────────
    const P1 = "  p1  768 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n";
    const UPDATE_HEAD = "tars-install: /dev/nvme0n1 (1 GB, QEMU NVMe Ctrl) already has TARS. p1 will be updated, p2 (your settings) is kept.\n" ++
        "  boot/      <- TARS 0.1.4\n";
    const UPDATE_TAIL = "  p2 (tars-config) <- not opened\n" ++
        "  p3 (tars-home) <- not opened\n" ++
        "  tars-install /dev/nvme0n1 --wipe erases all three instead, your home too\n";
    out = control.Out{ .buf = &out_buf };
    disk.planLines(&out, true, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "TARS installed", null, .{ 1, 2, 3 }, false, "0.1.4", "0.1.3", .rotate);
    try expectText(out.bytes(), UPDATE_HEAD ++
        "  boot/old/  <- TARS 0.1.3, for the boot menu if the new one fails\n" ++ UPDATE_TAIL, "the rotating update plan");
    out = control.Out{ .buf = &out_buf };
    disk.planLines(&out, true, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "TARS installed", null, .{ 1, 2, 3 }, false, "0.1.4", null, .overwrite);
    try expectText(out.bytes(), UPDATE_HEAD ++ "  boot/old/  <- left as it is\n" ++ UPDATE_TAIL, "the overwriting update plan");
    out = control.Out{ .buf = &out_buf };
    disk.planLines(&out, false, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "blank", null, .{ 1, 2, 3 }, false, "0.1.4", null, .rotate);
    const fresh = "tars-install: /dev/nvme0n1 (1 GB, QEMU NVMe Ctrl) will be erased. it now holds: blank\n" ++
        P1 ++
        "  p2  256 MiB  Linux       ext2   tars-config <- your settings, empty at first\n" ++
        "  p3     rest  Linux       ext4   tars-home   <- your home, empty at first\n";
    try expectText(out.bytes(), fresh, "the fresh plan");
    out = control.Out{ .buf = &out_buf };
    disk.planLines(&out, false, "/dev/nvme0n1", "1 GB", "QEMU NVMe Ctrl", "blank", 2, .{ 1, 2, 3 }, false, "0.1.4", null, .rotate);
    try expectText(out.bytes(), fresh ++ "  the settings now on p2 are erased too\n", "the fresh plan over old settings");
    // HP-M1: 계정 한 줄. 비밀번호의 글자는 안 찍는다.
    out = control.Out{ .buf = &out_buf };
    disk.userLine(&out, "tars", true);
    try expectText(out.bytes(), "  user  tars  (home /home/tars, password tars-linux, the default)\n", "the default user line");
    out = control.Out{ .buf = &out_buf };
    disk.userLine(&out, "hpuser", false);
    try expectText(out.bytes(), "  user  hpuser  (home /home/hpuser, password as typed)\n", "the typed user line");

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
        "tars-install <disk> --beside  keep what <disk> has; install into its largest free space\n" ++
        "tars-install <partition>    erase that one partition (say /dev/sda3) and install there\n" ++
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

    // ── 19. 최소 디스크 (KU-M0) ──────────────────────────────────────
    if (disk.bigEnough(2 << 30)) return error.TwoGibAccepted;
    if (!disk.bigEnough(disk.MIN_DISK_BYTES) or disk.bigEnough(disk.MIN_DISK_BYTES - 1)) return error.MinBoundary;
    if (disk.bigEnough(64 << 20) or disk.bigEnough(2_000_000_000)) return error.SmallDiskAccepted;
    if (!disk.bigEnough(100_000_000_000)) return error.SsdRejected;

    // ── 20. rotation — 무엇을 하나, 경계는 == 에서 된다 (KU-M0) ─────────
    {
        const need: u64 = 103 << 20;
        const Case = struct { v: bool, free: u64, old: u64, cur: u64, want: disk.Rotation, what: []const u8 };
        const cases = [_]Case{
            .{ .v = true, .free = 900 << 20, .old = 0, .cur = 102 << 20, .want = .rotate, .what = "version, room to spare" },
            .{ .v = true, .free = 50 << 20, .old = 53 << 20, .cur = 102 << 20, .want = .rotate, .what = "version, fits once old is cleared (==)" },
            .{ .v = true, .free = 50 << 20, .old = 0, .cur = 102 << 20, .want = .no_room, .what = "version, no room even with cur" },
            .{ .v = false, .free = 900 << 20, .old = 0, .cur = 0, .want = .overwrite, .what = "no version, room to spare" },
            .{ .v = false, .free = 1 << 20, .old = 0, .cur = 102 << 20, .want = .overwrite, .what = "no version, fits once cur is truncated (==)" },
            .{ .v = false, .free = 1 << 20, .old = 200 << 20, .cur = 50 << 20, .want = .no_room, .what = "no version, old is not freed" },
        };
        for (cases) |c| {
            const got = disk.rotation(c.v, c.free, c.old, c.cur, need);
            if (got != c.want) {
                std.debug.print("FAIL: rotation {s}: want {s}, got {s}\n", .{ c.what, @tagName(c.want), @tagName(got) });
                return error.WrongRotation;
            }
        }
        out = control.Out{ .buf = &out_buf };
        disk.roomLines(&out, 1, 50, 0, 103, .no_room);
        try expectText(out.bytes(), "tars-install: p1 has 50 bytes free and 0 bytes in boot/old; the new image needs 103\n" ++
            "tars-install: p1 has no room for two images; nothing was changed.\n", "the no-room lines");
        out = control.Out{ .buf = &out_buf };
        disk.roomLines(&out, 1, 900, 0, 103, .rotate);
        try expectText(out.bytes(), "tars-install: p1 has 900 bytes free and 0 bytes in boot/old; the new image needs 103\n", "the room line");
    }

    // ── 21. ROTATION — 어느 op 뒤에 끊겨도 뜨는 엔트리가 있다 (KU design 결정 4) ──
    //
    // 모형: 디렉터리 둘의 내용과 conf의 엔트리 수. 엔트리가 뜨는 조건은 "conf에
    // 있고 그 디렉터리가 비지도 반쪽도 아니다". copy_new는 도중(partial)과 뒤를
    // 따로 본다. 시작은 둘 — 슬롯 전에 깔린 디스크(엔트리 하나, old 없음)와 이미
    // 회전한 디스크(엔트리 둘, old 있음).
    {
        const starts = [_]Model{
            .{ .new = .current, .old = .empty, .conf_two = false },
            .{ .new = .current, .old = .prev, .conf_two = true },
        };
        for (starts, 0..) |start, si| {
            var m = start;
            if (!m.bootable()) return error.StartNotBootable;
            for (disk.ROTATION) |op| {
                if (op == .copy_new) {
                    var mid = m;
                    mid.new = .partial;
                    if (!mid.bootable()) {
                        std.debug.print("FAIL: start {d}: nothing boots while copy_new is half done\n", .{si});
                        return error.CutDuringCopy;
                    }
                }
                m.apply(op);
                if (!m.bootable()) {
                    std.debug.print("FAIL: start {d}: nothing boots after {s}\n", .{ si, @tagName(op) });
                    return error.CutAfterOp;
                }
            }
            if (m.new != .next or m.old != .current or !m.conf_two) {
                std.debug.print("FAIL: start {d}: ends as new={s} old={s} two={}\n", .{ si, @tagName(m.new), @tagName(m.old), m.conf_two });
                return error.WrongEnd;
            }
        }
    }

    // ── 22. GPT 엔트리 — 진짜 sfdisk가 쓴 바이트로 (DB-M0) ─────────────
    //
    // REAL_HEADER · REAL_ENTRIES는 util-linux 2.41.5의 sfdisk(게스트 initrd와 같은 판)가 쓴 7GiB "맥 디스크"의
    // LBA 1 앞 92바이트와 LBA 2의 엔트리 다섯이다. p1 · p2는 dualboot/mac_gpt.pl이, p3~p5는 sfdisk가
    // `--append`로 붙였다(DB-M0 plan 착수 전 3). 헤더의 CRC가 엔트리 128개(다섯 뒤는 0)의 CRC를 담고 있어서,
    // 이 바이트가 그대로 통과하면 CRC 계산과 GUID의 바이트 순서가 둘 다 sfdisk와 같다는 뜻이다 — 검사와
    // 구현이 같은 수를 두 번 적은 것이 아니다.
    {
        var g = realGpt(512) orelse {
            std.debug.print("FAIL: the GPT sfdisk wrote did not parse\n", .{});
            return error.RealGptRejected;
        };
        if (g.count != 5) return error.WrongPartCount;
        const Want = struct { n: u8, kind: disk.PartKind, role: disk.Role, first: u64, last: u64 };
        const want = [_]Want{
            .{ .n = 1, .kind = .efi, .role = .none, .first = 2048, .last = 411647 },
            .{ .n = 2, .kind = .apfs, .role = .none, .first = 411648, .last = 2508799 },
            .{ .n = 3, .kind = .efi, .role = .boot, .first = 2508800, .last = 4081663 },
            .{ .n = 4, .kind = .other, .role = .config, .first = 4081664, .last = 4605951 },
            .{ .n = 5, .kind = .other, .role = .home, .first = 4605952, .last = 14678015 },
        };
        for (g.slice(), want) |p, w| {
            if (p.number != w.n or p.kind != w.kind or p.role != w.role or p.first != w.first or p.last != w.last) {
                std.debug.print("FAIL: entry {d}: got p{d} {s} {s} {d}-{d}\n", .{ w.n, p.number, @tagName(p.kind), @tagName(p.role), p.first, p.last });
                return error.WrongEntry;
            }
        }
        if (g.first_usable != 34 or g.last_usable != 14680030) return error.WrongUsable;
        if ((g.find(.boot) orelse return error.NoBoot).number != 3) return error.BootNotP3;
        if ((g.find(.config) orelse return error.NoConfig).number != 4) return error.ConfigNotP4;
        if (!g.hasTars() or !g.hasOthers()) return error.WrongMix;

        // 빈 자리. sfdisk의 셋이 디스크를 끝까지 채웠다 — 앞(34~2047)과 뒤(14678016~14680030)는 1MiB가 안 된다.
        if (disk.largestGap(&g, false) != null) return error.GapOnAFullDisk;
        try expectText(disk.gptText(&buf, &g), "GPT: EFI, macOS (APFS), TARS; no free space", "the state of a disk with TARS beside macOS");
        // TARS 셋을 없는 것으로 치면(`--beside --wipe`) 구간이 그 셋의 자리 그대로다. 그 배치가 sfdisk가 받아 준
        // 그 수다 — appendScript의 세 줄이 착수 전 3에서 먹인 것과 같다.
        const gap = disk.largestGap(&g, true) orelse return error.NoGapWithoutTars;
        if (gap.start != 2508800 or gap.end != 14678016) {
            std.debug.print("FAIL: gap without TARS is {d}-{d}\n", .{ gap.start, gap.end });
            return error.WrongGap;
        }
        const l = disk.besideLayout(gap, 512) orelse return error.LayoutRefused;
        var script_buf: [512]u8 = undefined;
        try expectText(disk.appendScript(&script_buf, l) orelse return error.NoScript, "start=2508800, size=1572864, type=uefi, name=TARS-BOOT\n" ++
            "start=4081664, size=524288, type=linux, name=TARS-CONFIG\n" ++
            "start=4605952, size=10072064, type=linux, name=TARS-HOME\n", "the append script");
        const fresh_nums = disk.freeNumbers(&g, true) orelse return error.NoNumbers;
        const next_nums = disk.freeNumbers(&g, false) orelse return error.NoNumbers;
        if (!std.mem.eql(u8, &fresh_nums, &.{ 3, 4, 5 }) or !std.mem.eql(u8, &next_nums, &.{ 6, 7, 8 })) return error.WrongNumbers;
        // TARS-HOME의 타입은 Linux filesystem이다. 그 GUID도 sfdisk가 쓴 바이트와 맞아야 한다.
        if (!std.mem.eql(u8, head[1024 + 3 * 128 ..][0..16], &disk.guidBytes("0FC63DAF-8483-4772-8E79-3D69D8477DE4"))) {
            return error.LinuxGuidOrder;
        }

        // 바이트 하나가 틀리면 통째로 안 읽는다. 엔트리의 CRC, 헤더의 CRC.
        _ = realGpt(512);
        head[1024 + 2 * 128 + 33] ^= 1;
        if (disk.parseGpt(&head, 512) != null) return error.EntryCrcIgnored;
        _ = realGpt(512);
        head[512 + 48] ^= 1;
        if (disk.parseGpt(&head, 512) != null) return error.HeaderCrcIgnored;

        // 4Kn. 같은 헤더와 엔트리를 4096 · 8192에 놓는다. 512로 읽으면 없다.
        g = realGpt(4096) orelse return error.FourKnRejected;
        if (g.count != 5 or g.sector != 4096) return error.FourKnWrong;
        if (disk.parseGpt(&head, 512) != null) return error.FourKnReadAs512;
        if (disk.parseGpt(&head, 1024) != null) return error.OddSectorAccepted;

        // 맥 디스크(TARS 전). sfdisk 엔트리 셋을 지우고 CRC를 다시 맞춘다 — CRC가 맞다는 것은 위에서 봤으니
        // 여기서 쓰는 seal은 같은 셈을 하는 도우미다.
        _ = realGpt(512);
        @memset(head[1024 + 2 * 128 ..][0 .. 3 * 128], 0);
        seal(512);
        g = disk.parseGpt(&head, 512) orelse return error.MacRejected;
        try expectText(disk.gptText(&buf, &g), "GPT: EFI, macOS (APFS); 6 GB free", "the state of a Mac disk");
        if (g.hasTars() or g.find(.boot) != null) return error.MacHasTars;
        const mac_nums = disk.freeNumbers(&g, false) orelse return error.NoNumbers;
        if (!std.mem.eql(u8, &mac_nums, &.{ 3, 4, 5 })) return error.WrongMacNumbers;
        const mac_gap = disk.largestGap(&g, false) orelse return error.NoMacGap;
        if (mac_gap.start != 2508800 or mac_gap.end != 14678016) return error.WrongMacGap;

        // 가운데에 남의 파티션 하나(8000000~8999999). 뒤쪽 구간이 더 크다 — 시작은 1MiB 위로 맞춘 9000960이다.
        // 이름 `TARS-BOOTX`는 TARS가 아니다(전체 일치).
        {
            const e = head[1024 + 2 * 128 ..][0..128];
            @memcpy(e[0..16], &disk.guidBytes("0FC63DAF-8483-4772-8E79-3D69D8477DE4"));
            e[16] = 1;
            std.mem.writeInt(u64, e[32..40], 8000000, .little);
            std.mem.writeInt(u64, e[40..48], 8999999, .little);
            for ("TARS-BOOTX", 0..) |c, i| e[56 + i * 2] = c;
            seal(512);
        }
        g = disk.parseGpt(&head, 512) orelse return error.MiddleRejected;
        if (g.hasTars()) return error.PrefixTakenAsName;
        const mid = disk.largestGap(&g, false) orelse return error.NoMiddleGap;
        if (mid.start != 9000960 or mid.end != 14678016) {
            std.debug.print("FAIL: with a partition in the middle the gap is {d}-{d}\n", .{ mid.start, mid.end });
            return error.WrongMiddleGap;
        }
        try expectText(disk.gptText(&buf, &g), "GPT: EFI, macOS (APFS), 1 other; 2 GB free", "a Mac disk with another partition");

        // 쓸 수 있는 구간 밖의 엔트리는 GPT를 통째로 거절한다.
        std.mem.writeInt(u64, head[1024 + 2 * 128 + 40 ..][0..8], 14680031, .little);
        seal(512);
        if (disk.parseGpt(&head, 512) != null) return error.OutOfRangeAccepted;

        // 같은 이름 둘 — 어느 것이 우리 것인지 모르면 find는 null이다.
        _ = realGpt(512);
        @memcpy(head[1024 + 5 * 128 ..][0..128], head[1024 + 2 * 128 ..][0..128]);
        seal(512);
        g = disk.parseGpt(&head, 512) orelse return error.TwinRejected;
        if (g.find(.boot) != null or !g.hasTars()) return error.TwinFound;
    }

    // ── 23. 자리의 경계와 거절 줄 (DB-M0) ───────────────────────────
    {
        const need: u64 = disk.MIN_DISK_BYTES / 512;
        if (disk.besideLayout(.{ .start = 2048, .end = 2048 + need }, 512) == null) return error.MinGapRefused;
        if (disk.besideLayout(.{ .start = 2048, .end = 2048 + need - 1 }, 512) != null) return error.SmallGapAccepted;
        const l4k = disk.besideLayout(.{ .start = 256, .end = 256 + disk.MIN_DISK_BYTES / 4096 }, 4096) orelse return error.FourKnLayout;
        if (l4k.boot.size != 196608 or l4k.config.start != 256 + 196608) return error.FourKnSectors;

        _ = realGpt(512);
        const g = disk.parseGpt(&head, 512) orelse return error.RealGptRejected;
        out = control.Out{ .buf = &out_buf };
        disk.roomRefusal(&out, "/dev/sda", &g, 1_900_000_000);
        try expectText(out.bytes(), "the largest free space on /dev/sda is 1 GB; TARS needs more than 4 GiB; nothing was changed." ++
            "make room in macOS first: diskutil apfs resizeContainer disk0s2 <smaller size> (see diskutil list)", "the room refusal");

        out = control.Out{ .buf = &out_buf };
        disk.besideLines(&out, "/dev/sda", "7 GB", "Mac SSD", "GPT: EFI, macOS (APFS); 6 GB free", .{ .start = 2508800, .end = 14678016 }, 512, .{ 3, 4, 5 }, &.{});
        try expectText(out.bytes(), "tars-install: /dev/sda (7 GB, Mac SSD) keeps its partitions. it now holds: GPT: EFI, macOS (APFS); 6 GB free\n" ++
            "  TARS goes into the free space from MiB 1225 to MiB 7167; no other partition is touched\n" ++
            "  p3  768 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n" ++
            "  p4  256 MiB  Linux       ext2   tars-config <- your settings, empty at first\n" ++
            "  p5     rest  Linux       ext4   tars-home   <- your home, empty at first\n" ++
            "  the Mac still starts macOS; hold Option at power-on and pick EFI Boot for TARS\n", "the beside plan");
        out = control.Out{ .buf = &out_buf };
        disk.planLines(&out, true, "/dev/sda", "7 GB", "Mac SSD", "TARS installed", null, .{ 3, 4, 5 }, true, "0.1.4", null, .overwrite);
        if (std.mem.indexOf(u8, out.bytes(), "already has TARS. p3 will be updated, p4 (your settings) is kept.") == null or
            std.mem.indexOf(u8, out.bytes(), "--beside --wipe erases the TARS partitions instead") == null)
        {
            std.debug.print("FAIL: the update plan of a disk beside macOS:\n{s}", .{out.bytes()});
            return error.WrongBesideUpdate;
        }
        // 통째 설치의 배치와 GPT 이름이 같은 글자다 — init과 설치기가 이 이름으로 찾는다.
        for ([_][]const u8{ disk.NAME_BOOT, disk.NAME_CONFIG, disk.NAME_HOME }) |n| {
            var name_buf: [32]u8 = undefined;
            const want = std.fmt.bufPrint(&name_buf, "name={s}\n", .{n}) catch unreachable;
            if (std.mem.indexOf(u8, disk.SFDISK_SCRIPT, want) == null) return error.ScriptNameDrifted;
        }
    }

    // ── 24. 기존 파티션 지정 (DB-M1) ─────────────────────────────────
    {
        // 노드 이름. 디스크 이름이 숫자로 끝나면 p가 든다(storage.partitionName).
        const sda3 = disk.splitPartition("/dev/sda3") orelse return error.SdaPartRejected;
        if (!std.mem.eql(u8, sda3.disk, "/dev/sda") or sda3.number != 3) return error.SdaPartWrong;
        const nv = disk.splitPartition("/dev/nvme3n1p12") orelse return error.NvmePartRejected;
        if (!std.mem.eql(u8, nv.disk, "/dev/nvme3n1") or nv.number != 12) return error.NvmePartWrong;
        const mmc = disk.splitPartition("/dev/mmcblk0p3") orelse return error.MmcPartRejected;
        if (!std.mem.eql(u8, mmc.disk, "/dev/mmcblk0") or mmc.number != 3) return error.MmcPartWrong;
        for ([_][]const u8{ "/dev/nvme0n1", "/dev/sda", "/dev/nvme0n13", "/dev/sda0", "/dev/sdz1", "/dev/sda129", "sda3" }) |bad| {
            if (disk.splitPartition(bad) != null) {
                std.debug.print("FAIL: splitPartition accepted {s}\n", .{bad});
                return error.NotAPartitionAccepted;
            }
        }

        // 서명. NTFS · exFAT은 55 AA가 있어도 FAT보다 먼저다.
        var h = clear();
        if (disk.fsOf(h).fs != .none) return error.ZeroNotEmpty;
        h[510] = 0x55;
        h[511] = 0xAA;
        @memcpy(h[82..90], "FAT32   ");
        @memcpy(h[71..82], "TARS       ");
        const seen = disk.fsOf(h);
        if (seen.fs != .fat32) return error.Fat32Missed;
        try expectText(seen.label, "TARS", "the FAT32 label");
        @memcpy(h[71..82], "NO NAME    ");
        try expectText(disk.fsOf(h).label, "", "NO NAME is no label");
        @memcpy(h[3..11], "NTFS    ");
        if (disk.fsOf(h).fs != .ntfs) return error.NtfsMissed;
        @memcpy(h[3..11], "EXFAT   ");
        if (disk.fsOf(h).fs != .exfat) return error.ExfatMissed;
        h = clear();
        h[510] = 0x55;
        h[511] = 0xAA;
        @memcpy(h[54..62], "FAT16   ");
        if (disk.fsOf(h).fs != .fat16) return error.Fat16Missed;
        h = clear();
        @memcpy(h[32..36], "NXSB");
        if (disk.fsOf(h).fs != .apfs) return error.ApfsMissed;
        h = clear();
        @memcpy(h[1024..1026], "H+");
        if (disk.fsOf(h).fs != .hfs) return error.HfsMissed;
        h = clear();
        h[1080] = 0x53;
        h[1081] = 0xEF;
        if (disk.fsOf(h).fs != .ext) return error.ExtMissed;
        h = clear();
        h[20000] = 1;
        if (disk.fsOf(h).fs != .other) return error.OtherMissed;

        // 받는 표(plan 결정 13).
        const basic = disk.Part{ .number = 3, .kind = .basic, .role = .none, .first = 0, .last = 0 };
        var other = basic;
        other.kind = .other;
        if (disk.takeable(basic, .fat32) != null or disk.takeable(basic, .exfat) != null or disk.takeable(basic, .none) != null or
            disk.takeable(other, .none) != null) return error.TakeableRefused;
        if (disk.takeable(basic, .ntfs) != .ntfs) return error.NtfsTaken;
        if (disk.takeable(other, .fat32) != .filesystem) return error.LinuxFatTaken;
        if (disk.takeable(basic, .ext) != .filesystem) return error.ExtTaken;
        var p = basic;
        p.kind = .efi;
        if (disk.takeable(p, .fat32) != .efi) return error.EfiTaken;
        p.kind = .apfs;
        if (disk.takeable(p, .none) != .macos) return error.ApfsTaken;
        p.kind = .hfs;
        if (disk.takeable(p, .hfs) != .macos) return error.HfsTaken;
        p.kind = .apple_boot;
        if (disk.takeable(p, .hfs) != .recovery) return error.RecoveryTaken;
        p = basic;
        p.role = .home;
        if (disk.takeable(p, .ext) != .tars) return error.TarsTaken;

        // dualboot 체인의 "디스크 유틸리티로 나눈 맥"(8GiB): p1 EFI · p2 APFS · 128MiB 틈 · p3 FAT · p4 NTFS(끝 256MiB).
        var g = disk.Gpt{ .sector = 512, .first_usable = 34, .last_usable = 16777182, .entries = 128 };
        const rows = [_]disk.Part{
            .{ .number = 1, .kind = .efi, .role = .none, .first = 2048, .last = 411647 },
            .{ .number = 2, .kind = .apfs, .role = .none, .first = 411648, .last = 2508799 },
            .{ .number = 3, .kind = .basic, .role = .none, .first = 2770944, .last = 16252927 },
            .{ .number = 4, .kind = .basic, .role = .none, .first = 16252928, .last = 16777182 },
        };
        for (rows) |r| {
            g.parts[g.count] = r;
            g.count += 1;
        }
        // 빈 자리는 p2와 p3 사이의 128MiB 틈뿐이다 — `--beside`가 거절하고 지정 설치를 말하는 디스크다.
        const lg = disk.largestGap(&g, false) orelse return error.GuiMacNoGap;
        if (lg.start * 512 >> 20 != 1225 or lg.end * 512 >> 20 != 1353) {
            std.debug.print("FAIL: the GUI Mac disk's largest gap is MiB {d}-{d}\n", .{ lg.start * 512 >> 20, lg.end * 512 >> 20 });
            return error.GuiMacGap;
        }
        const ga = disk.gapAround(&g, 3) orelse return error.NoGapAround;
        if (ga.start * 512 >> 20 != 1225 or ga.end * 512 >> 20 != 7936) {
            std.debug.print("FAIL: gapAround p3 is MiB {d}-{d}\n", .{ ga.start * 512 >> 20, ga.end * 512 >> 20 });
            return error.WrongGapAround;
        }
        if (disk.besideLayout(ga, 512) == null) return error.GapAroundTooSmall;
        // p4 뒤(끝)는 1MiB 아래로 맞추면 남는 것이 p4 그 자체다 — 256MiB라 자리가 안 된다.
        const g4 = disk.gapAround(&g, 4) orelse return error.NoGapAroundP4;
        if (disk.besideLayout(g4, 512) != null) return error.P4BigEnough;
        const rest = g.without(3);
        if (rest.count != 3 or rest.byNumber(3) != null) return error.WithoutKeptP3;
        const nums = disk.freeNumbers(&rest, false) orelse return error.NoNumbers;
        if (nums[0] != 3 or nums[1] != 5 or nums[2] != 6) {
            std.debug.print("FAIL: sfdisk numbers after deleting p3: {any}\n", .{nums});
            return error.WrongNumbers;
        }
        // gptText의 글자는 DB-M0 그대로 — 새 타입은 other로 센다.
        var text_buf: [128]u8 = undefined;
        try expectText(disk.gptText(&text_buf, &g), "GPT: EFI, macOS (APFS), 2 other; 134 MB free", "the GUI Mac disk's state");

        // 문장.
        var what_buf: [48]u8 = undefined;
        try expectText(disk.partWhat(&what_buf, rows[2], .{ .fs = .fat32, .label = "TARS" }), "FAT32 \"TARS\"", "a FAT row");
        try expectText(disk.partWhat(&what_buf, rows[1], .{ .fs = .other }), "macOS (APFS)", "an APFS row");
        try expectText(disk.partWhat(&what_buf, rows[3], .{ .fs = .ntfs }), "NTFS", "an NTFS row");
        try expectText(disk.partWhat(&what_buf, rows[2], .{ .fs = .fat32, .label = "A\x1bB" }), "FAT32 \"A?B\"", "a label with ESC");
        out = control.Out{ .buf = &out_buf };
        disk.partRow(&out, "/dev/nvme3n1p3", "6 GB", "FAT32 \"TARS\"", true);
        disk.partRow(&out, "/dev/nvme3n1p4", "268 MB", "NTFS", false);
        try expectText(out.bytes(), "    /dev/nvme3n1p3    6 GB  FAT32 \"TARS\"  <- tars-install /dev/nvme3n1p3 installs here\n" ++
            "    /dev/nvme3n1p4  268 MB  NTFS\n", "partition rows");
        out = control.Out{ .buf = &out_buf };
        disk.takeLines(&out, "/dev/sda3", "FAT32 \"TARS\"", "6 GB", "/dev/sda", "8 GB", "Mac SSD", "GPT: EFI, macOS (APFS), 2 other; 134 MB free", ga, 512, nums);
        try expectText(out.bytes(), "tars-install: /dev/sda3 (FAT32 \"TARS\", 6 GB) will be erased, the files on it too.\n" ++
            "  the other partitions of /dev/sda (8 GB, Mac SSD) are kept. it now holds: GPT: EFI, macOS (APFS), 2 other; 134 MB free\n" ++
            "  TARS goes into /dev/sda3 and the free space next to it, from MiB 1225 to MiB 7936; no other partition is touched\n" ++
            "  p3  768 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n" ++
            "  p5  256 MiB  Linux       ext2   tars-config <- your settings, empty at first\n" ++
            "  p6     rest  Linux       ext4   tars-home   <- your home, empty at first\n" ++
            "  the Mac still starts macOS; hold Option at power-on and pick EFI Boot for TARS\n", "the take plan");
        out = control.Out{ .buf = &out_buf };
        disk.takeRefusal(&out, "/dev/sda2", "/dev/sda", .macos, .{ .fs = .apfs });
        try expectText(out.bytes(), "/dev/sda2 is an APFS or HFS+ partition and may hold macOS; nothing was changed." ++
            "if you made it for TARS, turn it into free space in macOS (diskutil eraseVolume free free diskXsN) and use tars-install /dev/sda --beside", "the macOS refusal");
        out = control.Out{ .buf = &out_buf };
        disk.takeRefusal(&out, "/dev/sda4", "/dev/sda", .ntfs, .{ .fs = .ntfs });
        try expectText(out.bytes(), "/dev/sda4 holds NTFS (Windows or Boot Camp); tars-install takes only an empty, FAT or exFAT partition. nothing was changed", "the NTFS refusal");
    }

    std.debug.print("disk_test: signatures, sizes, arguments, labels, the YES gate and the ESP conf hold\n", .{});
    std.debug.print("disk_test: the state column, a list row, both plans, a tool's end and the usage lines are the installer's words\n", .{});
    std.debug.print("disk_test: the minimum disk, the rotation rule and its order (something boots after every step) hold\n", .{});
    std.debug.print("disk_test: GPT entries as sfdisk writes them (512 and 4Kn), names, the largest free space and the beside plan hold\n", .{});
    std.debug.print("disk_test: partition nodes, file system signatures, what a named partition install takes and where it goes hold\n", .{});
}

/// 검사 22의 진짜 바이트(dualboot 체인과 같은 7GiB 맥 디스크 + sfdisk --append, util-linux 2.41.5).
const REAL_HEADER =
    "4546492050415254000001005c000000d0716df2000000000100000000000000ffffdf0000000000220000000000" ++
    "0000deffdf0000000000dbb00ddb00000040800000000000db000200000000000000800000008000000043937bdf";
const REAL_ENTRIES =
    "28732ac11ff8d211ba4b00a0c93ec93b010000db0000004080000000000000010008000000000000ff4706000000000000000000000000004500460049002000" ++
    "530079007300740065006d00200050006100720074006900740069006f006e000000000000000000000000000000000000000000000000000000000000000000" ++
    "ef57347c0000aa11aa1100306543ecac020000db0000004080000000000000020048060000000000ff4726000000000000000000000000000000000000000000" ++
    "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ++
    "28732ac11ff8d211ba4b00a0c93ec93b3f057184bbacd243ba998cd6de70ec0e0048260000000000ff473e000000000000000000000000005400410052005300" ++
    "2d0042004f004f005400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ++
    "af3dc60f838472478e793d69d8477de4cac1efb75a326642b8db5848c582413200483e0000000000ff4746000000000000000000000000005400410052005300" ++
    "2d0043004f004e004600490047000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ++
    "af3dc60f838472478e793d69d8477de464b2ab67903bad44aa95c1791703f9e40048460000000000fff7df000000000000000000000000005400410052005300" ++
    "2d0048004f004d004500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

/// head를 비우고 REAL_HEADER를 LBA 1(sector)에, REAL_ENTRIES를 LBA 2에 놓은 뒤 읽는다.
fn realGpt(sector: usize) ?disk.Gpt {
    _ = clear();
    _ = std.fmt.hexToBytes(head[sector..][0..92], REAL_HEADER) catch unreachable;
    _ = std.fmt.hexToBytes(head[2 * sector ..][0 .. REAL_ENTRIES.len / 2], REAL_ENTRIES) catch unreachable;
    return disk.parseGpt(&head, sector);
}

/// 엔트리를 고친 뒤 두 CRC를 다시 맞춘다. 엔트리 128개 · 헤더 92바이트(REAL_HEADER의 모양)다.
fn seal(sector: usize) void {
    const h = head[sector..][0..92];
    std.mem.writeInt(u32, h[88..92], std.hash.Crc32.hash(head[2 * sector ..][0 .. 128 * 128]), .little);
    std.mem.writeInt(u32, h[16..20], 0, .little);
    std.mem.writeInt(u32, h[16..20], std.hash.Crc32.hash(h), .little);
}

/// 검사 21의 모형. 디렉터리가 담은 것은 이렇다.
///   empty    없다
///   prev     회전 전의 old
///   current  회전 전의 new(지금 이미지)
///   partial  복사 도중
///   next     새 이미지
const Dir = enum { empty, prev, current, partial, next };

const Model = struct {
    new: Dir,
    old: Dir,
    conf_two: bool,

    fn complete(d: Dir) bool {
        return d != .empty and d != .partial;
    }

    /// 기본 엔트리(new)가 뜨거나, conf에 old 엔트리가 있고 그것이 뜬다.
    fn bootable(self: Model) bool {
        return complete(self.new) or (self.conf_two and complete(self.old));
    }

    fn apply(self: *Model, op: disk.Op) void {
        switch (op) {
            .clear_old => self.old = .empty,
            .write_conf => self.conf_two = true,
            .move_to_old => {
                self.old = self.new;
                self.new = .empty;
            },
            .copy_new => self.new = .next,
            .write_version => {},
        }
    }
};
