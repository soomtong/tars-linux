const std = @import("std");
const backlight = @import("backlight.zig");

/// LP-M2 — 밝기의 순수한 층. 실제 패널은 실기가 본다(QEMU에 백라이트가 없다).
fn expectStep(name: []const u8, cur: u32, max: u32, delta: i32, want: u32) !void {
    const got = backlight.step(cur, max, delta);
    if (got != want) {
        std.debug.print("FAIL {s}: step({d}, {d}, {d}) = {d}, want {d}\n", .{ name, cur, max, delta, got, want });
        return error.Step;
    }
}

pub fn main() !void {
    // 1. 순위 — raw(intel_backlight)가 firmware(acpi_video0)를 이긴다. sysfs의 줄바꿈까지.
    if (backlight.rank("raw\n") != 0 or backlight.rank("platform\n") != 1 or backlight.rank("firmware\n") != 2)
        return error.Rank;
    if (backlight.rank("Raw\n") != null or backlight.rank("") != null) return error.RankUnknown;
    {
        const names = [_][]const u8{ "acpi_video0", "intel_backlight", "acpi_video1" };
        const ranks = [_]u8{ 2, 0, 2 };
        if (backlight.pick(&names, &ranks) != 1) return error.PickRaw;
        const ties = [_][]const u8{ "acpi_video1", "acpi_video0" };
        const tie_ranks = [_]u8{ 2, 2 };
        if (backlight.pick(&ties, &tie_ranks) != 1) return error.PickTieByName;
        if (backlight.pick(&[_][]const u8{}, &[_]u8{}) != null) return error.PickEmpty;
    }
    // 2. 값 읽기.
    if (backlight.parseLevel("1220\n") != 1220 or backlight.parseLevel("x\n") != null) return error.Parse;

    // 3. 단계 — MacBookAir4,1의 intel_backlight max는 실기에서 본다. 여기서는 흔한 둘(1500 · 7)과 끝.
    //    16단계라 한 단계는 max/16. 1500이면 94.
    try expectStep("up from mid", 750, 1500, 1, 844);
    try expectStep("down from mid", 750, 1500, -1, 656);
    try expectStep("two up", 750, 1500, 2, 938);
    // 펌웨어가 둔 단계 밖의 값 — 가장 가까운 단계(8)에서 움직인다.
    try expectStep("off-step up", 760, 1500, 1, 844);
    // 끝. 가장 밝은 단계에서 더 밝게는 그대로, 가장 낮은 단계는 0이 아니라 한 단계(94)다.
    try expectStep("top stays", 1500, 1500, 1, 1500);
    try expectStep("bottom is one step", 188, 1500, -1, 94);
    try expectStep("bottom stays", 94, 1500, -1, 94);
    try expectStep("from zero up", 0, 1500, 1, 94);
    // max가 작은 패널(7) — 이웃 단계가 같은 값이라도 키마다 값이 바뀐다.
    try expectStep("small up", 3, 7, 1, 4);
    try expectStep("small down", 3, 7, -1, 2);
    try expectStep("small bottom", 1, 7, -1, 1);
    // 자동 반복으로 여럿이 한 배치에 온 것.
    try expectStep("many down", 1500, 1500, -20, 94);
    // max 0(읽기 실패) · delta 0은 그대로.
    try expectStep("no max", 5, 0, 1, 5);
    try expectStep("no delta", 5, 1500, 0, 5);

    std.debug.print("backlight_test: raw wins, sixteen steps that always move, never below one step\n", .{});
}
