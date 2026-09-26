const std = @import("std");
const clock = @import("clock.zig");

/// 기대하는 설정 파일은 글자로 한 벌 더 적는다. `renderConf`로 만든 것과
/// 비교하면 검사가 tautology가 된다 — sntp_test의 `reply`가 stub의 바이트
/// 배치를 손으로 한 벌 더 적었던 것과 같은 이유다.
fn expectConf(server: [4]u8, keep: bool, want: []const u8) !void {
    var buf: [clock.CONF_MAX]u8 = undefined;
    const got = clock.renderConf(&buf, server, keep) orelse {
        std.debug.print("FAIL: the config for {d}.{d}.{d}.{d} (keep={}) did not fit\n", .{
            server[0], server[1], server[2], server[3], keep,
        });
        return error.ConfTooLong;
    };
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: got\n{s}---\nwant\n{s}---\n", .{ got, want });
        return error.WrongConf;
    }
}

fn expectServer(text: []const u8, want: [4]u8) !void {
    const got = clock.parseServerFile(text) orelse {
        std.debug.print("FAIL: no server found in [{s}]\n", .{text});
        return error.NoServer;
    };
    if (!std.mem.eql(u8, &got, &want)) {
        std.debug.print("FAIL: got {d}.{d}.{d}.{d} from [{s}]\n", .{
            got[0], got[1], got[2], got[3], text,
        });
        return error.WrongServer;
    }
}

fn expectNoServer(text: []const u8) !void {
    if (clock.parseServerFile(text)) |got| {
        std.debug.print("FAIL: found {d}.{d}.{d}.{d} in [{s}], expected none\n", .{
            got[0], got[1], got[2], got[3], text,
        });
        return error.UnexpectedServer;
    }
}

pub fn main() !void {
    // ── renderConf ─────────────────────────────────────────────────────
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
    // 가장 긴 모양. 109바이트라 CONF_MAX(128)에 든다.
    try expectConf(.{ 255, 255, 255, 255 }, true, "confdir /config/chrony.d\nserver 255.255.255.255 iburst\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    std.debug.print("clock_test: with /config it reads chrony.d first and keeps its drift there\n", .{});

    // ── parseServerFile ────────────────────────────────────────────────
    //
    // TS-M2부터 있던 검사 그대로다. dhcpcd가 hook에 넘기는 `$new_ntp_servers`는
    // 공백으로 갈린 목록이고, hook은 그것을 그대로 파일에 쓴다. 첫 것만 쓴다
    // (TS design 비목표 2).
    try expectServer("10.0.2.2\n", .{ 10, 0, 2, 2 });
    try expectServer("192.168.0.1 192.168.0.2\n", .{ 192, 168, 0, 1 });
    // 개행 없이 끝나도 받는다. `printf`로 쓴 파일이 그렇다.
    try expectServer("1.2.3.4", .{ 1, 2, 3, 4 });
    // 빈 파일. hook이 빈 값으로 불린 경우다.
    try expectNoServer("");
    try expectNoServer("\n");
    // 이름은 안 받는다(TS design 결정 5 — init에 resolver가 없다).
    try expectNoServer("pool.ntp.org\n");
    // 첫 토큰만 본다. 그것이 주소가 아니면 뒤를 안 뒤진다.
    try expectNoServer("garbage 10.0.2.2\n");
    std.debug.print("clock_test: the server file gives up its first address and nothing else\n", .{});

    std.debug.print("PASS\n", .{});
}
