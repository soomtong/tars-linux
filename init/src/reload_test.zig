//! TC-M2. `reload.zig`의 검사 — PID 1이 reload에서 무엇을 할지를 호스트에서 다 본다(reload design
//! 결정 8). config_test와 같은 모양이다 — 실패하면 `FAIL:` 줄을 찍고 0이 아닌 코드로 끝난다.
const std = @import("std");
const config = @import("config.zig");
const control = @import("control.zig");
const reload = @import("reload.zig");

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

fn expectText(got: []const u8, want: []const u8, what: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) return fail("{s}:\n--- got ---\n{s}\n--- want ---\n{s}", .{ what, got, want });
}

/// 키마다 기본값이 아닌 값 하나. `config.parse`로 짓는다 — init이 읽는 그 길이다.
const OTHER = [_][]const u8{
    "shell=zsh",       "keyboard=pc",       "hangul_layout=dubeol", "latin_layout=dvorak",
    "hangul_toggle=shift_space", "shell_config=off", "net=dhcp", "ntp=10.0.2.2",
    "timezone=Asia/Seoul", "firewall=on", "esc_latin=off", "clipboard=pane",
};

const S = reload.Slot;

fn expectActions(slots: []const S, names: []const []const u8, want: []const reload.SvcAction, what: []const u8) !void {
    var out: [16]reload.SvcAction = undefined;
    const n = reload.serviceActions(slots, names, &out);
    if (n != want.len) return fail("{s}: {d} actions, want {d}", .{ what, n, want.len });
    for (out[0..n], want, 0..) |g, w, i| {
        if (!std.meta.eql(g, w)) return fail("{s}: action {d} is {any}, want {any}", .{ what, i, g, w });
    }
}

pub fn main() !void {
    // ── 1. 열두 키가 다 한 갈래에 든다 ──────────────────────────────────
    //
    // groupOf가 모르는 키는 컴파일 에러다 — 이 루프가 컴파일되면 열둘 다 들었다. 갈래의 수를 세서
    // design 결정 2의 표(지금 셋 · 다음에 뜰 때부터 셋 · 화면 여섯)와 견준다.
    var counts = [_]usize{ 0, 0, 0 };
    inline for (@typeInfo(config.Config).@"struct".fields) |f| counts[@intFromEnum(comptime reload.groupOf(f.name))] += 1;
    if (counts[0] != 3 or counts[1] != 3 or counts[2] != 6) return fail("groups now/next/terminal = {d}/{d}/{d}, want 3/3/6", .{ counts[0], counts[1], counts[2] });
    std.debug.print("reload_test: twelve keys in three groups — three now, three at the next spawn, six on the screen\n", .{});

    // ── 2. diff — 키 하나를 바꾸면 그 비트 하나 ────────────────────────
    const def = config.Config{};
    if (!reload.changed(def, def).empty()) return fail("default against default changed something", .{});
    for (OTHER, 0..) |line, i| {
        const c = config.parse(line);
        const k = reload.changed(def, c);
        if (k.bits != (@as(u16, 1) << @intCast(i))) return fail("{s}: changed bits {b}, want bit {d}", .{ line, k.bits, i });
    }
    // 정규형이 같으면 같은 값이다 — 순서가 다른 전환 키 목록 · 0으로 시작하는 주소.
    if (!reload.changed(config.parse("hangul_toggle=lctrl_tap,shift_space"), config.parse("hangul_toggle=shift_space,lctrl_tap")).empty())
        return fail("the same toggles in another order count as a change", .{});
    if (!reload.changed(config.parse("ntp=10.0.2.2"), config.parse("ntp=010.0.2.2")).empty())
        return fail("the same ntp address written with a leading zero counts as a change", .{});
    std.debug.print("reload_test: the diff flips one bit per changed key and none for the same value written another way\n", .{});

    // ── 3. 대기 — 화면 쪽 키만 ─────────────────────────────────────────
    const live = config.parse("keyboard=pc\nnet=dhcp\ntimezone=Asia/Seoul\n");
    const p = reload.pending(live, def);
    if (!p.has("keyboard") or !p.has("timezone") or p.has("net")) return fail("pending bits {b}", .{p.bits});

    // ── 4. 답의 글자 ────────────────────────────────────────────────────
    var buf: [control.REPLY_MAX]u8 = undefined;
    var out = reload.Out{ .buf = &buf };
    reload.configReply(&out, live, def);
    try expectText(out.bytes(),
        "shell=fish\nkeyboard=pc\nhangul_layout=shin_pcs\nlatin_layout=qwerty\n" ++
        "hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap\nshell_config=on\nnet=dhcp\nntp=off\n" ++
        "timezone=Asia/Seoul\nfirewall=off\nesc_latin=on\nclipboard=shared\n" ++
        "screen keyboard=apple timezone=UTC\n", "configReply");
    var kb: [1024]u8 = undefined;
    var ko = reload.Out{ .buf = &kb };
    reload.keyLines(&ko, def, live);
    try expectText(ko.bytes(),
        "keyboard: apple -> pc (the screen keeps the old value until the next boot)\n" ++
        "net: off -> dhcp (now)\n" ++
        "timezone: UTC -> Asia/Seoul (the next console shell, ssh login and service; the screen keeps the old value until the next boot)\n",
        "keyLines");
    // 넘치면 멈춘다 — PID 1이 답을 짓다가 죽지 않는다.
    var tiny: [10]u8 = undefined;
    var to = reload.Out{ .buf = &tiny };
    reload.configReply(&to, live, def);
    if (!to.full or to.len > tiny.len) return fail("a 10-byte reply buffer did not stop cleanly", .{});
    std.debug.print("reload_test: config answers twelve key=value lines and the screen's line; a full buffer stops, it does not panic\n", .{});

    // ── 5. 데몬 · 방화벽 ────────────────────────────────────────────────
    const table = [_]struct { bool, bool, bool, reload.Step }{
        .{ false, false, false, .keep }, .{ false, true, false, .start }, .{ false, true, true, .start },
        .{ true, false, false, .stop },  .{ true, false, true, .stop },   .{ true, true, false, .keep },
        .{ true, true, true, .restart },
    };
    for (table) |t| if (reload.step(t[0], t[1], t[2]) != t[3]) return fail("step({}, {}, {})", .{ t[0], t[1], t[2] });
    if (reload.firewallStep(.off, .on) != .up or reload.firewallStep(.on, .off) != .down or
        reload.firewallStep(.on, .on) != .keep or reload.firewallStep(.off, .off) != .keep) return fail("firewallStep", .{});
    std.debug.print("reload_test: a daemon starts, stops, restarts on a rewritten config or is left alone; the firewall goes up or down\n", .{});

    // ── 6. services.d ───────────────────────────────────────────────────
    const empty = S{ .name = "", .off = true, .alive = false };
    // 새 이름 둘이 앞의 빈 칸 둘에.
    try expectActions(&[_]S{ empty, empty, empty }, &[_][]const u8{ "a", "sshd" }, &[_]reload.SvcAction{
        .{ .add = .{ .slot = 0, .name = 0 } }, .{ .add = .{ .slot = 1, .name = 1 } },
    }, "two new names");
    // 이미 있는 것은 안 건드린다.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true }, empty }, &[_][]const u8{"a"}, &[_]reload.SvcAction{}, "nothing changed");
    // 사라진 것은 멈춘다. 멈춘 사람의 것(hold)은 칸의 off가 아니라 상관없다.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true }, .{ .name = "sshd", .off = false, .alive = true } }, &[_][]const u8{"a"}, &[_]reload.SvcAction{
        .{ .stop = 1 },
    }, "a name gone");
    // 다시 나타난 것은 되살린다 — 새 칸이 아니라 그 칸이다.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true }, .{ .name = "sshd", .off = true, .alive = false }, empty }, &[_][]const u8{ "a", "sshd" }, &[_]reload.SvcAction{
        .{ .revive = 1 },
    }, "a name back");
    // 꺼졌고 거둬진 칸은 다른 새 이름에게 간다. 멈추는 중(alive)인 칸은 안 준다.
    try expectActions(&[_]S{ .{ .name = "old", .off = true, .alive = true }, .{ .name = "gone", .off = true, .alive = false } }, &[_][]const u8{"new"}, &[_]reload.SvcAction{
        .{ .add = .{ .slot = 1, .name = 0 } },
    }, "reuse a reaped slot, not a dying one");
    // 칸이 없으면 다음 부팅.
    try expectActions(&[_]S{ .{ .name = "a", .off = false, .alive = true } }, &[_][]const u8{ "a", "b" }, &[_]reload.SvcAction{
        .{ .no_room = 1 },
    }, "no room");
    // out보다 많으면 out만큼 — 셈이 넘치지 않는다.
    var small: [1]reload.SvcAction = undefined;
    const m = reload.serviceActions(&[_]S{ empty, empty }, &[_][]const u8{ "a", "b" }, &small);
    if (m != 1) return fail("serviceActions into a one-slot array gave {d}", .{m});
    std.debug.print("reload_test: services.d — new names take free slots, gone names stop, returning names revive, a dying slot is not reused\n", .{});

    std.debug.print("PASS\n", .{});
}
