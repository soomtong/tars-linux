const std = @import("std");
const battery = @import("battery.zig");

// 배터리 칸의 순수한 층을 호스트에서 본다(BS-M0). 입력은 sysfs 파일과 uevent의 바이트를
// 글자로 적은 것이다 — 파일의 모양은 `docs/plans/2026-10-08-tars-battery-status-bs-m0.md`의
// 확정 2, 검사 번호는 그 plan의 Task 2 표와 같다.

fn expectStatus(bytes: []const u8, want: battery.Status) !void {
    const got = battery.parseStatus(bytes);
    if (got == want) return;
    std.debug.print("FAIL: parseStatus({any}) = .{s}, want .{s}\n", .{ bytes, @tagName(got), @tagName(want) });
    return error.WrongStatus;
}

fn expectCapacity(bytes: []const u8, want: ?u8) !void {
    const got = battery.parseCapacity(bytes);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: parseCapacity({any}) = {?d}, want {?d}\n", .{ bytes, got, want });
    return error.WrongCapacity;
}

fn expectCounts(kind: []const u8, present: ?[]const u8, scope: ?[]const u8, want: bool) !void {
    const got = battery.counts(kind, present, scope);
    if (got == want) return;
    std.debug.print("FAIL: counts({any}, {any}, {any}) = {}, want {}\n", .{ kind, present, scope, got, want });
    return error.WrongCounts;
}

fn expectPick(names: []const []const u8, want: ?[]const u8) !void {
    const got = battery.pick(names);
    const same = if (got == null or want == null) got == null and want == null else std.mem.eql(u8, got.?, want.?);
    if (same) return;
    std.debug.print("FAIL: pick({d} names) = {?s}, want {?s}\n", .{ names.len, got, want });
    return error.WrongPick;
}

fn expectClass(status: battery.Status, capacity: ?u8, want: battery.Class) !void {
    const got = battery.class(status, capacity);
    if (got == want) return;
    std.debug.print("FAIL: class(.{s}, {?d}) = .{s}, want .{s}\n", .{ @tagName(status), capacity, @tagName(got), @tagName(want) });
    return error.WrongClass;
}

fn expectCell(capacity: ?u8, want: []const u8) !void {
    var buf: [battery.CELL_LEN]u8 = undefined;
    const got = battery.cellText(capacity, &buf);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print("FAIL: cellText({?d}) = \"{s}\", want \"{s}\"\n", .{ capacity, got, want });
    return error.WrongCell;
}

fn expectUevent(msg: []const u8, want: bool) !void {
    const got = battery.ueventIsPowerSupply(msg);
    if (got == want) return;
    std.debug.print("FAIL: ueventIsPowerSupply({any}) = {}, want {}\n", .{ msg, got, want });
    return error.WrongUevent;
}

fn expectTimeout(now_ms: i64, due_ms: ?i64, want: c_int) !void {
    const got = battery.pollTimeout(now_ms, due_ms);
    if (got == want) return;
    std.debug.print("FAIL: pollTimeout({d}, {?d}) = {d}, want {d}\n", .{ now_ms, due_ms, got, want });
    return error.WrongTimeout;
}

pub fn main() !void {
    // ── 검사 1: sysfs의 다섯 글자 ───────────────────────────────────────
    // 커널이 `status` 파일에 쓰는 글자 그대로다. 줄바꿈이 붙어 온다.
    try expectStatus("Unknown\n", .unknown);
    try expectStatus("Charging\n", .charging);
    try expectStatus("Discharging\n", .discharging);
    try expectStatus("Not charging\n", .not_charging);
    try expectStatus("Full\n", .full);
    std.debug.print("battery_test: 1. the five status words OK\n", .{});

    // ── 검사 2: 모르는 글자는 unknown이다 ──────────────────────────────
    // 소문자는 test_power 파라미터의 글자이지 파일의 글자가 아니다. 빈 값은 읽기가
    // 실패했을 때 main.zig가 넘기는 것이다.
    try expectStatus("charging\n", .unknown);
    try expectStatus("Bogus\n", .unknown);
    try expectStatus("", .unknown);
    try expectStatus("Charging \n", .unknown);
    std.debug.print("battery_test: 2. unknown status words are unknown OK\n", .{});

    // ── 검사 3: statusName과 parseStatus의 왕복 ─────────────────────────
    // battery.zig의 ALL_STATUS가 하나를 빠뜨리면 그 값이 unknown으로 돌아와 여기서 빨개진다.
    for ([_]battery.Status{ .unknown, .charging, .discharging, .not_charging, .full }) |s| {
        try expectStatus(battery.statusName(s), s);
    }
    std.debug.print("battery_test: 3. statusName round-trips through parseStatus OK\n", .{});

    // ── 검사 4: capacity — design 끝 조건 1의 여섯 ──────────────────────
    try expectCapacity("100\n", 100);
    try expectCapacity("0", 0);
    try expectCapacity("105", 100);
    try expectCapacity("-3", 0);
    try expectCapacity("", null);
    try expectCapacity("abc", null);
    std.debug.print("battery_test: 4. capacity clamps to 0..100 and refuses non-integers OK\n", .{});

    // ── 검사 5: capacity — 그 밖 ───────────────────────────────────────
    try expectCapacity("50\n", 50);
    try expectCapacity("15\n", 15);
    try expectCapacity("12abc", null);
    try expectCapacity("\n", null);
    try expectCapacity("99999999999", null);
    std.debug.print("battery_test: 5. capacity edge texts OK\n", .{});

    // ── 검사 6: counts — test_power의 장치 셋 ──────────────────────────
    // test_battery에는 scope 파일이 없고, test_ac · test_usb에는 present 파일이 없다.
    try expectCounts("Battery\n", "0\n", null, false);
    try expectCounts("Battery\n", "1\n", null, true);
    try expectCounts("Mains\n", null, null, false);
    try expectCounts("USB\n", null, null, false);
    std.debug.print("battery_test: 6. counts on test_power's three supplies OK\n", .{});

    // ── 검사 7: counts — 실기의 모양 ───────────────────────────────────
    // ACPI 배터리는 scope를 안 내고, 주변기기 배터리는 Device다.
    try expectCounts("Battery\n", null, null, true);
    try expectCounts("Battery\n", "1\n", "System\n", true);
    try expectCounts("Battery\n", "1\n", "Device\n", false);
    try expectCounts("Battery\n", "1\n", "Unknown\n", true);
    try expectCounts("Battery", "1", null, true);
    std.debug.print("battery_test: 7. counts on present, scope and missing files OK\n", .{});

    // ── 검사 8: pick — 바이트 순서로 첫째 ──────────────────────────────
    {
        const none = [_][]const u8{};
        const one = [_][]const u8{"test_battery"};
        const reversed = [_][]const u8{ "BAT1", "BAT0" };
        const ordered = [_][]const u8{ "BAT0", "BAT1" };
        try expectPick(&none, null);
        try expectPick(&one, "test_battery");
        try expectPick(&reversed, "BAT0");
        try expectPick(&ordered, "BAT0");
    }
    std.debug.print("battery_test: 8. pick takes the first name in byte order OK\n", .{});

    // ── 검사 9: class — 꽂혀 있으면 잔량과 무관하게 plugged ──────────────
    try expectClass(.charging, 5, .plugged);
    try expectClass(.full, 100, .plugged);
    try expectClass(.not_charging, 10, .plugged);
    try expectClass(.charging, null, .plugged);
    std.debug.print("battery_test: 9. charging, full and not charging are plugged OK\n", .{});

    // ── 검사 10: class — 문턱 15의 양쪽 ────────────────────────────────
    // `<=`가 `<`로 바뀌면 15가, 문턱이 바뀌면 16이 빨개진다.
    try expectClass(.discharging, 15, .low);
    try expectClass(.discharging, 16, .normal);
    try expectClass(.discharging, 0, .low);
    try expectClass(.discharging, 100, .normal);
    std.debug.print("battery_test: 10. low is 15 and below while discharging OK\n", .{});

    // ── 검사 11: class — 상태나 잔량을 모를 때 ──────────────────────────
    try expectClass(.discharging, null, .normal);
    try expectClass(.unknown, null, .normal);
    try expectClass(.unknown, 50, .normal);
    try expectClass(.unknown, 10, .low);
    std.debug.print("battery_test: 11. unknown status or capacity OK\n", .{});

    // ── 검사 12: cellText — 넉 자 넷 ──────────────────────────────────
    try expectCell(100, "100%");
    try expectCell(85, " 85%");
    try expectCell(5, "  5%");
    try expectCell(null, "  ?%");
    std.debug.print("battery_test: 12. the four cell texts OK\n", .{});

    // ── 검사 13: cellText — 0~100 전부 넉 자이고 %의 자리가 같다 ─────────
    {
        var v: u8 = 0;
        while (v <= 100) : (v += 1) {
            var buf: [battery.CELL_LEN]u8 = undefined;
            const got = battery.cellText(v, &buf);
            const digits = std.mem.trimStart(u8, got[0 .. got.len - 1], " ");
            const back = std.fmt.parseInt(u8, digits, 10) catch 255;
            if (got.len != battery.CELL_LEN or got[battery.CELL_LEN - 1] != '%' or back != v) {
                std.debug.print("FAIL: cellText({d}) = \"{s}\"\n", .{ v, got });
                return error.WrongCell;
            }
        }
        try expectCell(255, "255%");
    }
    std.debug.print("battery_test: 13. every capacity fills exactly four cells OK\n", .{});

    // ── 검사 14: uevent — power_supply의 것 ────────────────────────────
    // test_power의 battery_present를 쓰면 uevent는 test_battery가 아니라 test_ac에서 온다.
    try expectUevent("change@/devices/virtual/power_supply/test_ac\x00ACTION=change\x00" ++
        "DEVPATH=/devices/virtual/power_supply/test_ac\x00SUBSYSTEM=power_supply\x00" ++
        "POWER_SUPPLY_NAME=test_ac\x00POWER_SUPPLY_TYPE=Mains\x00POWER_SUPPLY_ONLINE=1\x00SEQNUM=812\x00", true);
    try expectUevent("add@/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00ACTION=add\x00" ++
        "DEVPATH=/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00SUBSYSTEM=power_supply\x00" ++
        "POWER_SUPPLY_NAME=BAT0\x00SEQNUM=1200\x00", true);
    try expectUevent("remove@/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00ACTION=remove\x00" ++
        "DEVPATH=/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00SUBSYSTEM=power_supply\x00SEQNUM=1201\x00", true);
    std.debug.print("battery_test: 14. power_supply uevents from any device and action OK\n", .{});

    // ── 검사 15: uevent — 아닌 것 ─────────────────────────────────────
    // thermal zone은 test_battery가 등록하지만 SUBSYSTEM이 thermal이다. 머리만 있는 것은
    // 경로에 power_supply가 있어도 아니다.
    try expectUevent("add@/devices/platform/i8042/serio1/input/input3/event3\x00ACTION=add\x00" ++
        "DEVPATH=/devices/platform/i8042/serio1/input/input3/event3\x00SUBSYSTEM=input\x00DEVNAME=input/event3\x00", false);
    try expectUevent("add@/devices/virtual/thermal/thermal_zone0\x00ACTION=add\x00" ++
        "DEVPATH=/devices/virtual/thermal/thermal_zone0\x00SUBSYSTEM=thermal\x00", false);
    try expectUevent("change@/devices/virtual/power_supply/test_ac", false);
    try expectUevent("", false);
    std.debug.print("battery_test: 15. other uevents are not power_supply OK\n", .{});

    // ── 검사 16: pollTimeout ──────────────────────────────────────────
    // 주기 경로는 게이트가 못 본다(design 결정 11). 이 다섯이 그 길의 검증이다.
    try expectTimeout(1_000, 61_000, 60_000);
    try expectTimeout(61_000, 61_000, 0);
    try expectTimeout(70_000, 61_000, 0);
    try expectTimeout(5, null, -1);
    try expectTimeout(0, std.math.maxInt(i64), std.math.maxInt(c_int));
    try expectTimeout(std.math.minInt(i64), std.math.maxInt(i64), std.math.maxInt(c_int));
    try expectTimeout(std.math.maxInt(i64), std.math.minInt(i64), 0);
    std.debug.print("battery_test: 16. poll timeout before, at and after the due time, without a battery and past c_int OK\n", .{});

    // ── 검사 17: design의 수 ──────────────────────────────────────────
    if (battery.PERIOD_MS != 60_000 or battery.LOW_MAX != 15 or battery.CELL_LEN != 4) {
        std.debug.print("FAIL: PERIOD_MS={d} LOW_MAX={d} CELL_LEN={d}, want 60000 15 4\n", .{ battery.PERIOD_MS, battery.LOW_MAX, battery.CELL_LEN });
        return error.WrongConstants;
    }
    std.debug.print("battery_test: 17. period 60s, low at 15, four cells OK\n", .{});

    std.debug.print("battery_test: all checks passed\n", .{});
}
