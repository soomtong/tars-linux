const std = @import("std");
const bluetooth = @import("bluetooth.zig");

// BT-M1. `bluetooth.wants`의 세 갈래. 시스템 콜이 없어 /tmp도 필요 없다 — 설정 값과
// `/config`가 붙었는지 둘로만 답한다(wifi_test와 달리 파일을 안 본다).

fn expect(what: []const u8, got: bool, want: bool) !void {
    if (got != want) {
        std.debug.print("FAIL: {s} — got {}, want {}\n", .{ what, got, want });
        return error.Mismatch;
    }
}

pub fn main() !void {
    // 기본값. 이 키를 안 적은 기계는 한 글자도 안 바뀐다(BT design 결정 5).
    try expect("off, mounted", bluetooth.wants(.off, true), false);
    // 켰고 /config가 있다 — 이 milestone의 양성이다.
    try expect("on, mounted", bluetooth.wants(.on, true), true);
    // 켰지만 /config가 안 붙은 부팅(tars.noconfig). 키가 남을 자리가 없다.
    try expect("on, not mounted", bluetooth.wants(.on, false), false);
    try expect("off, not mounted", bluetooth.wants(.off, false), false);

    std.debug.print("bluetooth_test: dbus and bluetoothd join only with bluetooth=on and /config\n", .{});
}
