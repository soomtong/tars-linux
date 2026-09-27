const std = @import("std");
const linux = std.os.linux;
const wifi = @import("wifi.zig");

// WL-M2. `wifi.wants`의 네 갈래. 설정 파일은 게스트가 아니라 빌드 컨테이너의
// /tmp에 만든다 — `wants`가 경로를 인자로 받는 이유가 이것이다.

const ROOT = "/tmp/tars-wifi-test";
const CONF = ROOT ++ "/wpa_supplicant.conf";

fn expect(what: []const u8, got: bool, want: bool) !void {
    if (got != want) {
        std.debug.print("FAIL: {s} — got {}, want {}\n", .{ what, got, want });
        return error.Mismatch;
    }
}

pub fn main() !void {
    _ = linux.mkdir(ROOT, 0o755);
    _ = linux.unlink(CONF);

    // 파일이 없다. 나머지 둘이 켜져 있어도 안 넣는다.
    try expect("no file", wifi.wants(.dhcp, true, CONF), false);

    const rc = linux.open(CONF, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o600);
    if (linux.errno(rc) != .SUCCESS) return error.OpenFailed;
    _ = linux.close(@intCast(rc));

    // 파일이 있다. 넣는다 — 이 milestone의 양성이다.
    try expect("file, net=dhcp, mounted", wifi.wants(.dhcp, true, CONF), true);
    // 파일이 있어도 net=off면 안 넣는다(WL design 결정 4). 주소를 받을 dhcpcd가 없다.
    try expect("file, net=off", wifi.wants(.off, true, CONF), false);
    // `/config`가 안 붙은 부팅. 파일 경로는 붙었는지와 무관한 /tmp라서 access는
    // 성공하지만 그 전에 돌아가야 한다 — 이 줄이 순서를 본다.
    try expect("file, not mounted", wifi.wants(.dhcp, false, CONF), false);

    std.debug.print("wifi_test: wpa_supplicant joins only with the file, a network and /config\n", .{});
}
