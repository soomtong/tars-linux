const std = @import("std");
const pacing = @import("pacing.zig");

// 그리는 간격의 하한을 호스트에서 본다(RS-M2). 시스템 콜이 없는 산수다 — 시계를 읽고
// `poll`에 넘기는 것은 `main.zig`이고 효과는 RS 프로브가 잰다.

fn expectWait(now: i64, last: ?i64, pending: bool, want: c_int) !void {
    const got = pacing.wait(now, last, pending);
    if (got == want) return;
    std.debug.print("FAIL: wait({d}, {?d}, {}) = {d}, want {d}\n", .{ now, last, pending, got, want });
    return error.WrongWait;
}

fn expectSoonest(a: c_int, b: c_int, want: c_int) !void {
    const got = pacing.soonest(a, b);
    if (got == want) return;
    std.debug.print("FAIL: soonest({d}, {d}) = {d}, want {d}\n", .{ a, b, got, want });
    return error.WrongSoonest;
}

pub fn main() !void {
    // ── 검사 1: 그릴 것이 없으면 기다릴 프레임도 없다 ─────────────────────
    // 마지막 프레임이 방금이어도 -1이다. 여기서 0이나 양수를 내면 할 일 없는 `poll`이
    // 계속 깨어 CPU를 쓴다.
    try expectWait(1000, 995, false, -1);
    try expectWait(1000, null, false, -1);
    std.debug.print("pacing_test: 1. nothing pending waits forever OK\n", .{});

    // ── 검사 2: 처음 프레임은 기다리지 않는다 ───────────────────────────
    try expectWait(0, null, true, 0);
    try expectWait(5000, null, true, 0);
    std.debug.print("pacing_test: 2. the first frame never waits OK\n", .{});

    // ── 검사 3: 하한 안이면 남은 시간, 경계와 그 뒤는 0 ─────────────────
    // 16ms 하한에서 마지막이 1000이면 1016부터 그린다.
    try expectWait(1000, 1000, true, 16);
    try expectWait(1001, 1000, true, 15);
    try expectWait(1015, 1000, true, 1);
    try expectWait(1016, 1000, true, 0);
    try expectWait(9000, 1000, true, 0);
    std.debug.print("pacing_test: 3. inside the gap waits the rest, at and after it draws OK\n", .{});

    // ── 검사 4: 두 timeout 중 먼저 오는 것, -1은 무한 ───────────────────
    // `@min(-1, 7)`은 -1이다. 그것이 이 함수가 있는 이유다 — 배터리가 없을 때(-1)
    // 미룬 프레임의 7ms가 사라지면 다음 키까지 화면이 안 바뀐다.
    try expectSoonest(-1, 7, 7);
    try expectSoonest(7, -1, 7);
    try expectSoonest(-1, -1, -1);
    try expectSoonest(60000, 7, 7);
    try expectSoonest(0, 16, 0);
    std.debug.print("pacing_test: 4. the sooner timeout wins and -1 means never OK\n", .{});
}
