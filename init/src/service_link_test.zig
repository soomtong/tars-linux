//! TP-M11. `service_link.zig`의 판정 — 이름, 링크 가르기, 무엇을 할지, reload 답 읽기.
const std = @import("std");
const sl = @import("service_link.zig");

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

pub fn main() !void {
    const good = [_][]const u8{ "postgres", "mysql", "sshd", "my-app_2", "a" };
    for (good) |n| if (!sl.nameOk(n)) return fail("nameOk({s}) = false", .{n});
    const long: [33]u8 = @splat('a');
    const bad = [_][]const u8{ "", ".", "..", ".hidden", "../etc/x", "a/b", "a b", "a\tb", "a\x7f", &long };
    for (bad) |n| if (sl.nameOk(n)) return fail("nameOk([{s}]) = true", .{n});
    std.debug.print("service_link_test: names — no slash, no leading dot, no space or control, 32 bytes at most\n", .{});

    const t = "/etc/tars/services/redis";
    if (sl.classify(null, false, t) != .none) return fail("no entry is not none", .{});
    if (sl.classify(t, false, t) != .template) return fail("our link is not template", .{});
    if (sl.classify("/etc/tars/services/redis2", false, t) != .other) return fail("another target is not other", .{});
    if (sl.classify("redis", false, t) != .other) return fail("a relative link is not other", .{});
    if (sl.classify(null, true, t) != .other) return fail("a plain file is not other", .{});
    std.debug.print("service_link_test: links — none, ours, anything else is someone's\n", .{});

    const cases = [_]struct { v: sl.Verb, l: sl.Link, s: sl.Step }{
        .{ .v = .enable, .l = .none, .s = .link },
        .{ .v = .enable, .l = .template, .s = .already_on },
        .{ .v = .enable, .l = .other, .s = .foreign },
        .{ .v = .disable, .l = .none, .s = .already_off },
        .{ .v = .disable, .l = .template, .s = .unlink },
        .{ .v = .disable, .l = .other, .s = .foreign },
    };
    for (cases) |c| {
        const got = sl.decide(c.v, c.l);
        if (got != c.s) return fail("decide({s}, {s}) = {s}, want {s}", .{ @tagName(c.v), @tagName(c.l), @tagName(got), @tagName(c.s) });
    }
    std.debug.print("service_link_test: steps — link, unlink, already, and never touch someone's file\n", .{});

    const reply =
        \\net: dhcp
        \\service redis2: stops
        \\service redis: starts (new in /config/services.d)
        \\service nginx: no free slot until the next boot (8 at most)
        \\service caddy: stops
        \\service mysql: starts
        \\
    ;
    if (sl.said(reply, "service redis") != .starts) return fail("redis (new) is not starts", .{});
    if (sl.said(reply, "service mysql") != .starts) return fail("mysql (revive) is not starts", .{});
    if (sl.said(reply, "service caddy") != .stops) return fail("caddy is not stops", .{});
    if (sl.said(reply, "service nginx") != null) return fail("no free slot is not null", .{});
    if (sl.said(reply, "service postgres") != null) return fail("an absent name is not null", .{});
    if (sl.said("nothing changed\n", "service redis") != null) return fail("nothing changed is not null", .{});
    std.debug.print("service_link_test: reload replies — starts, stops, and nothing to wait for\n", .{});
}
