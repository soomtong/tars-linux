const std = @import("std");
const clock = @import("clock.zig");

/// 기대하는 설정 파일은 글자로 한 벌 더 적는다. `renderConf`로 만든 것과
/// 비교하면 검사가 tautology가 된다 — sntp_test의 `reply`가 stub의 바이트
/// 배치를 손으로 한 벌 더 적었던 것과 같은 이유다.
fn expectConf(server: ?[4]u8, keep: bool, want: []const u8) !void {
    var buf: [clock.CONF_MAX]u8 = undefined;
    const got = clock.renderConf(&buf, server, keep) orelse {
        std.debug.print("FAIL: the config (server={any}, keep={}) did not fit\n", .{ server, keep });
        return error.ConfTooLong;
    };
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: got\n{s}---\nwant\n{s}---\n", .{ got, want });
        return error.WrongConf;
    }
}

pub fn main() !void {
    // ── ntp=<주소> ─────────────────────────────────────────────────────
    //
    // 세 줄이 TD design 결정 4와 TD-M0 실측 2다. makestep이 빠지면 chrony는
    // 2031년까지 몇 달에 걸쳐 slew한다 — 게이트의 검사 18이 그것을 잡지만,
    // 원인에서 가장 가까운 자리가 여기다.
    try expectConf(.{ 10, 0, 2, 2 }, false, "server 10.0.2.2 iburst\nmakestep 1 3\ncmdport 0\n");
    // 가장 긴 주소. CONF_MAX가 모자라면 여기서 난다.
    try expectConf(.{ 255, 255, 255, 255 }, false, "server 255.255.255.255 iburst\nmakestep 1 3\ncmdport 0\n");
    std.debug.print("clock_test: without /config the chrony config names the server, steps once and closes the udp command port\n", .{});

    // TD-M2. /config가 붙은 부팅. confdir가 맨 앞이어야 사람이 적은 같은
    // 서버가 이긴다(TD design 실측 9) — 이 순서를 바꾸는 사람은 게이트의
    // 검사 26이 빨개지는 것을 보게 된다.
    try expectConf(.{ 10, 0, 2, 2 }, true, "confdir /config/chrony.d\nserver 10.0.2.2 iburst\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    try expectConf(.{ 255, 255, 255, 255 }, true, "confdir /config/chrony.d\nserver 255.255.255.255 iburst\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    std.debug.print("clock_test: with /config it reads chrony.d first and keeps its drift there\n", .{});

    // ── ntp=dhcp ───────────────────────────────────────────────────────
    //
    // DS design 결정 3. 서버 대신 디렉터리 하나다. dhcpcd의 hook이 그 안에
    // dhcp.sources를 쓰고 chronyc로 알린다(DS-M0 실측 5). 경로는 hook
    // kernel/dhcpcd-hooks/30-tars-ntp의 기본값과 같은 글자여야 한다.
    try expectConf(null, false, "sourcedir /run/tars/chrony.sources\nmakestep 1 3\ncmdport 0\n");
    // 가장 긴 모양. 114바이트라 CONF_MAX(128)에 든다.
    try expectConf(null, true, "confdir /config/chrony.d\nsourcedir /run/tars/chrony.sources\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    std.debug.print("clock_test: with ntp=dhcp chronyd starts with no server and reads the directory dhcpcd writes into\n", .{});

    std.debug.print("PASS\n", .{});
}
