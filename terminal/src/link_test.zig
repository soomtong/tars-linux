const std = @import("std");
const link = @import("link.zig");
const native = @import("builtin").cpu.arch.endian();

// 링크 칸의 순수한 층을 호스트에서 본다(LK-M0). 입력은 커널이 보낼 netlink 메시지를 바이트로 지은 것이다.
// 검사 번호는 `docs/plans/2026-11-14-tars-link-status-lk-m0.md`의 "검사" 표와 같다.

// ── 바이트 짓기 ───────────────────────────────────────────────────────

/// 메시지 하나를 짓는다. `begin` → `raw`/`attr`/`nest` → `end`. 여러 메시지를 이어 붙일 수 있다.
const Builder = struct {
    buf: [1024]u8 = @splat(0),
    len: usize = 0,
    start: usize = 0,

    fn pad(self: *Builder) void {
        while (self.len % 4 != 0) : (self.len += 1) self.buf[self.len] = 0;
    }

    fn begin(self: *Builder, kind: u16, seq: u32) void {
        self.pad();
        self.start = self.len;
        self.len += 16;
        std.mem.writeInt(u16, self.buf[self.start + 4 ..][0..2], kind, native);
        std.mem.writeInt(u32, self.buf[self.start + 8 ..][0..4], seq, native);
    }

    fn raw(self: *Builder, b: []const u8) void {
        @memcpy(self.buf[self.len..][0..b.len], b);
        self.len += b.len;
    }

    fn attr(self: *Builder, kind: u16, data: []const u8) void {
        self.pad();
        std.mem.writeInt(u16, self.buf[self.len..][0..2], @intCast(4 + data.len), native);
        std.mem.writeInt(u16, self.buf[self.len + 2 ..][0..2], kind, native);
        self.len += 4;
        self.raw(data);
    }

    /// 중첩 attribute의 머리를 열고 그 자리를 돌려준다. `NLA_F_NESTED` 비트를 켠다.
    fn nestBegin(self: *Builder, kind: u16) usize {
        self.pad();
        const at = self.len;
        std.mem.writeInt(u16, self.buf[at + 2 ..][0..2], kind | 0x8000, native);
        self.len += 4;
        return at;
    }

    fn nestEnd(self: *Builder, at: usize) void {
        std.mem.writeInt(u16, self.buf[at..][0..2], @intCast(self.len - at), native);
    }

    /// 메시지 길이를 적는다. 끝의 패딩은 다음 `begin`이 붙인다 — 커널도 `nlmsg_len`에 끝 패딩을 안 넣는다.
    fn end(self: *Builder) void {
        std.mem.writeInt(u32, self.buf[self.start..][0..4], @intCast(self.len - self.start), native);
    }

    fn bytes(self: *const Builder) []const u8 {
        return self.buf[0..self.len];
    }

    /// 마지막 메시지의 payload.
    fn payload(self: *const Builder) []const u8 {
        return self.buf[self.start + 16 .. self.len];
    }
};

fn u32le(v: u32) [4]u8 {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, v, native);
    return b;
}

/// `ifinfomsg` 16바이트.
fn ifinfo(arphrd: u16, index: i32) [16]u8 {
    var b: [16]u8 = @splat(0);
    std.mem.writeInt(u16, b[2..4], arphrd, native);
    std.mem.writeInt(i32, b[4..8], index, native);
    return b;
}

const IF_OPER_UP = 6;
const IF_OPER_DORMANT = 5;

const LinkSpec = struct {
    index: i32,
    name: []const u8,
    arphrd: u16 = link.ARPHRD_ETHER,
    oper: ?u8 = IF_OPER_UP,
    info_kind: ?[]const u8 = null,
    slave_kind: ?[]const u8 = null,
};

fn linkMsg(b: *Builder, s: LinkSpec) void {
    b.begin(link.RTM_NEWLINK, 0);
    b.raw(&ifinfo(s.arphrd, s.index));
    var name: [32]u8 = @splat(0);
    @memcpy(name[0..s.name.len], s.name);
    b.attr(3, name[0 .. s.name.len + 1]);
    if (s.oper) |o| b.attr(16, &.{o});
    if (s.info_kind != null or s.slave_kind != null) {
        const at = b.nestBegin(18);
        if (s.info_kind) |k| b.attr(1, k);
        if (s.slave_kind) |k| b.attr(4, k);
        b.nestEnd(at);
    }
    b.end();
}

/// `parseLink`가 돌려주는 `name`은 메시지 바이트를 가리킨다. 지역 `Builder`에 지으면 함수가 끝날 때
/// 그 바이트가 사라지므로, 검사 하나가 쓰는 동안은 살아 있는 ring에 짓는다.
var link_ring: [16]Builder = undefined;
var link_ring_next: usize = 0;

fn parsedLink(s: LinkSpec) link.LinkMsg {
    const b = &link_ring[link_ring_next % link_ring.len];
    link_ring_next += 1;
    b.* = .{};
    linkMsg(b, s);
    return link.parseLink(b.payload()).?;
}

fn addrMsg(b: *Builder, family: u8, index: u32, local: ?[4]u8, address: ?[4]u8) void {
    b.begin(link.RTM_NEWADDR, 0);
    b.raw(&.{ family, 24, 0, 0 });
    b.raw(&u32le(index));
    if (address) |a| b.attr(1, &a);
    if (local) |a| b.attr(2, &a);
    b.end();
}

fn addr(index: u32, a: [4]u8) link.AddrMsg {
    return .{ .index = index, .addr = a };
}

fn ifaceMsg(b: *Builder, index: u32, iftype: u32, ssid: ?[]const u8) void {
    b.begin(30, 0);
    b.raw(&.{ 7, 1, 0, 0 }); // genlmsghdr: NL80211_CMD_NEW_INTERFACE
    b.attr(1, &u32le(0)); // NL80211_ATTR_WIPHY — 안 읽는 attribute가 앞에 있어도 된다
    b.attr(3, &u32le(index));
    b.attr(4, "wlan0\x00");
    b.attr(5, &u32le(iftype));
    if (ssid) |s| b.attr(52, s);
    b.end();
}

fn wifi(index: u32, iftype: u32, ssid: ?[]const u8) link.WifiMsg {
    return .{ .index = index, .iftype = iftype, .ssid = ssid };
}

/// `NEW_SCAN_RESULTS` 하나. `status`가 null이면 BSS_STATUS를 안 넣는다(붙지 않은 BSS).
fn scanMsg(b: *Builder, status: ?u32, ies: ?[]const u8, beacon: ?[]const u8) void {
    b.begin(30, 0);
    b.raw(&.{ link.NL80211_CMD_NEW_SCAN_RESULTS, 1, 0, 0 });
    b.attr(3, &u32le(3));
    const at = b.nestBegin(47);
    b.attr(1, &.{ 2, 0, 0, 0, 0, 1 }); // NL80211_BSS_BSSID — 안 읽는다
    if (ies) |x| b.attr(6, x);
    if (beacon) |x| b.attr(11, x);
    if (status) |st| b.attr(9, &u32le(st));
    b.nestEnd(at);
    b.end();
}

const STATION = 2;
const AP = 3;

// ── 기대 ─────────────────────────────────────────────────────────────

var failures: usize = 0;

fn check(ok: bool, comptime what: []const u8, args: anytype) void {
    if (ok) return;
    failures += 1;
    std.debug.print("FAIL: " ++ what ++ "\n", args);
}

/// 칸이 `want`(null이면 칸 없음)이고 토막의 색이 `classes`인가.
fn expectCell(t: *const link.Table, want: ?[]const u8, classes: []const link.Class, comptime tag: []const u8) void {
    const got = link.cell(t);
    if (want == null) {
        check(got == null, tag ++ ": cell = \"{s}\", want none", .{if (got) |c| c.bytes() else ""});
        return;
    }
    const c = got orelse {
        check(false, tag ++ ": cell = none, want \"{s}\"", .{want.?});
        return;
    };
    check(std.mem.eql(u8, c.bytes(), want.?), tag ++ ": cell = \"{s}\", want \"{s}\"", .{ c.bytes(), want.? });
    var n: usize = 0;
    for (c.pieces) |p| {
        const piece = p orelse continue;
        if (n < classes.len) check(piece.class == classes[n], tag ++ ": piece {d} \"{s}\" class .{s}, want .{s}", .{
            n, c.pieceText(piece), @tagName(piece.class), @tagName(classes[n]),
        });
        n += 1;
    }
    check(n == classes.len, tag ++ ": {d} pieces, want {d}", .{ n, classes.len });
}

fn expectSsid(raw: []const u8, want: []const u8) void {
    var out: [link.SSID_MAX]u8 = undefined;
    const got = link.cleanSsid(raw, &out);
    check(std.mem.eql(u8, got, want), "cleanSsid({any}) = \"{s}\", want \"{s}\"", .{ raw, got, want });
}

// ── 검사 ─────────────────────────────────────────────────────────────

pub fn main() !void {
    // 1. 메시지 순회 — 첫째의 길이가 4의 배수가 아니다(패딩을 건너야 둘째가 맞다).
    {
        var b: Builder = .{};
        b.begin(link.RTM_NEWLINK, 7);
        b.raw("abcde");
        b.end();
        b.begin(link.NLMSG_DONE, 8);
        b.raw(&u32le(0));
        b.end();
        var it: link.MsgIter = .{ .buf = b.bytes() };
        const m1 = it.next();
        const m2 = it.next();
        check(m1 != null and m1.?.kind == link.RTM_NEWLINK and m1.?.seq == 7 and std.mem.eql(u8, m1.?.payload, "abcde"), "1: first message", .{});
        check(m2 != null and m2.?.kind == link.NLMSG_DONE and m2.?.seq == 8 and m2.?.payload.len == 4, "1: second message after padding", .{});
        check(it.next() == null, "1: no third message", .{});
    }

    // 2. 메시지 순회 — 길이가 남은 바이트보다 크다 · 16보다 작다.
    {
        var b: Builder = .{};
        b.begin(link.RTM_NEWLINK, 0);
        b.raw("abcd");
        b.end();
        var it: link.MsgIter = .{ .buf = b.bytes()[0 .. b.len - 1] };
        check(it.next() == null, "2: truncated message is not read", .{});
        std.mem.writeInt(u32, b.buf[0..4], 8, native);
        it = .{ .buf = b.bytes() };
        check(it.next() == null, "2: length below the header stops", .{});
        it = .{ .buf = b.bytes()[0..10] };
        check(it.next() == null, "2: fewer bytes than a header", .{});
    }

    // 3. attribute 순회 — 패딩 · NESTED 비트 · 잘린 attribute.
    {
        var b: Builder = .{};
        b.attr(5, "x"); // 길이 5, 패딩 3
        const at = b.nestBegin(18);
        b.attr(1, "veth");
        b.nestEnd(at);
        b.attr(9, "zzzz");
        var it: link.AttrIter = .{ .buf = b.bytes()[0 .. b.len - 1] };
        const a1 = it.next();
        const a2 = it.next();
        check(a1 != null and a1.?.kind == 5 and std.mem.eql(u8, a1.?.data, "x"), "3: first attribute", .{});
        check(a2 != null and a2.?.kind == 18 and a2.?.data.len == 8, "3: nested attribute keeps the low 14 bits", .{});
        check(it.next() == null, "3: truncated attribute stops", .{});
    }

    // 4. parseLink — 실NIC, operstate UP.
    {
        const m = parsedLink(.{ .index = 2, .name = "eth0" });
        check(m.index == 2 and std.mem.eql(u8, m.name, "eth0") and m.arphrd == link.ARPHRD_ETHER and m.up and !m.virtual, "4: physical up link = {any}", .{m});
    }

    // 5. parseLink — veth · slave만 · DORMANT · operstate 없음 · 짧은 payload.
    {
        const veth = parsedLink(.{ .index = 5, .name = "veth1", .info_kind = "veth\x00" });
        check(veth.virtual, "5: IFLA_INFO_KIND makes it virtual", .{});
        const slave = parsedLink(.{ .index = 6, .name = "eth1", .slave_kind = "bridge\x00" });
        check(!slave.virtual, "5: IFLA_INFO_SLAVE_KIND alone is not virtual", .{});
        const dormant = parsedLink(.{ .index = 3, .name = "wlan0", .oper = IF_OPER_DORMANT });
        check(!dormant.up, "5: DORMANT is not up", .{});
        const none = parsedLink(.{ .index = 3, .name = "wlan0", .oper = null });
        check(!none.up, "5: no operstate is not up", .{});
        check(link.parseLink(&.{ 0, 0, 1, 0 }) == null, "5: short payload", .{});
        check(link.parseLink(&ifinfo(1, 0)) == null, "5: index 0", .{});
    }

    // 6. parseAddr — IFA_LOCAL · IFA_ADDRESS만 · AF_INET6.
    {
        var b: Builder = .{};
        addrMsg(&b, 2, 4, .{ 10, 0, 2, 15 }, .{ 10, 0, 2, 1 });
        const a = link.parseAddr(b.payload());
        check(a != null and a.?.index == 4 and std.mem.eql(u8, &a.?.addr, &.{ 10, 0, 2, 15 }), "6: IFA_LOCAL wins", .{});
        b = .{};
        addrMsg(&b, 2, 4, null, .{ 192, 168, 1, 9 });
        const c = link.parseAddr(b.payload());
        check(c != null and std.mem.eql(u8, &c.?.addr, &.{ 192, 168, 1, 9 }), "6: IFA_ADDRESS alone", .{});
        b = .{};
        addrMsg(&b, 10, 4, .{ 1, 2, 3, 4 }, null);
        check(link.parseAddr(b.payload()) == null, "6: AF_INET6 is skipped", .{});
    }

    // 7. parseInterface · parseFamilyId · parseError.
    {
        var b: Builder = .{};
        ifaceMsg(&b, 3, STATION, "tars-wl");
        const w = link.parseInterface(b.payload());
        check(w != null and w.?.index == 3 and w.?.iftype == STATION and std.mem.eql(u8, w.?.ssid.?, "tars-wl"), "7: station with ssid", .{});
        b = .{};
        ifaceMsg(&b, 4, AP, null);
        const ap = link.parseInterface(b.payload());
        check(ap != null and ap.?.iftype == AP and ap.?.ssid == null, "7: no ssid attribute", .{});

        b = .{};
        b.begin(link.GENL_ID_CTRL, 0);
        b.raw(&.{ 1, 2, 0, 0 });
        b.attr(2, "nl80211\x00");
        b.attr(1, &.{ 0x22, 0 });
        b.end();
        check(link.parseFamilyId(b.payload()) == 0x22, "7: family id", .{});

        var e: [4]u8 = undefined;
        std.mem.writeInt(i32, &e, -19, native);
        check(link.parseError(&e) == -19, "7: error code", .{});
    }

    // 8. 요청 넷의 바이트(plan 확정 3 · 4).
    {
        var buf: [link.REQUEST_MAX]u8 = undefined;
        const getlink = link.buildDump(&buf, link.RTM_GETLINK, 1);
        const zeros: [16]u8 = @splat(0);
        const want_link = [_]u8{ 32, 0, 0, 0, 18, 0, 0x01, 0x03, 1, 0, 0, 0, 0, 0, 0, 0 } ++ zeros;
        check(std.mem.eql(u8, getlink, &want_link), "8: GETLINK dump = {any}", .{getlink});

        const getaddr = link.buildDump(&buf, link.RTM_GETADDR, 2);
        const want_addr = [_]u8{ 24, 0, 0, 0, 22, 0, 0x01, 0x03, 2, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0 };
        check(std.mem.eql(u8, getaddr, &want_addr), "8: GETADDR dump = {any}", .{getaddr});

        const fam = link.buildGetFamily(&buf, 3);
        const want_fam = [_]u8{ 32, 0, 0, 0, 16, 0, 1, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 1, 0, 0, 12, 0, 2, 0 } ++ "nl80211\x00".*;
        check(std.mem.eql(u8, fam, &want_fam), "8: GETFAMILY = {any}", .{fam});

        const gi = link.buildGetInterface(&buf, 0x22, 4, 3);
        const want_gi = [_]u8{ 28, 0, 0, 0, 0x22, 0, 1, 0, 4, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 8, 0, 3, 0, 3, 0, 0, 0 };
        check(std.mem.eql(u8, gi, &want_gi), "8: GET_INTERFACE = {any}", .{gi});

        // 짓은 요청을 우리 순회가 다시 읽는다.
        var it: link.MsgIter = .{ .buf = gi };
        const m = it.next();
        check(m != null and m.?.kind == 0x22 and m.?.payload.len == 12, "8: GET_INTERFACE reads back", .{});
    }

    // 9. 유선 흐름 — 후보 → 판정 요청 → 유선 → 주소.
    {
        var t: link.Table = .{};
        const r1 = t.applyLink(parsedLink(.{ .index = 2, .name = "eth0", .oper = 2 }));
        check(r1.new and r1.ask and r1.changed, "9: new candidate asks nl80211 = {any}", .{r1});
        expectCell(&t, null, &.{}, "9 before the answer");
        check(t.applyWifi(2, null), "9: error answer makes it wired", .{});
        check(t.find(2).?.kind == .wired, "9: kind wired", .{});
        expectCell(&t, null, &.{}, "9 wired but down");
        const r2 = t.applyLink(parsedLink(.{ .index = 2, .name = "eth0" }));
        check(r2.changed and !r2.ask and !r2.new, "9: wired going up does not ask = {any}", .{r2});
        expectCell(&t, "LAN", &.{.wait}, "9 up without address");
        check(t.applyAddr(addr(2, .{ 10, 0, 2, 15 }), true), "9: address added", .{});
        expectCell(&t, "LAN", &.{.ready}, "9 up with address");
        const r3 = t.applyLink(parsedLink(.{ .index = 2, .name = "eth0" }));
        check(!r3.changed and !r3.ask, "9: the same NEWLINK again changes nothing = {any}", .{r3});
    }

    // 10. 같은 주소의 NEWADDR 두 번 + DELADDR 한 번 → 0(design 결정 7).
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 2, .name = "eth0" }));
        _ = t.applyWifi(2, null);
        const a = addr(2, .{ 10, 0, 2, 15 });
        check(t.applyAddr(a, true), "10: first NEWADDR", .{});
        check(!t.applyAddr(a, true), "10: lease renewal NEWADDR changes nothing", .{});
        check(t.applyAddr(a, false), "10: DELADDR", .{});
        check(t.find(2).?.n_addrs == 0, "10: no address left", .{});
        expectCell(&t, "LAN", &.{.wait}, "10");
        check(!t.applyAddr(addr(9, .{ 1, 1, 1, 1 }), true), "10: unknown interface", .{});
    }

    // 11. 무선 흐름 — station이 올라오면 묻고, SSID를 받는다.
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0", .oper = IF_OPER_DORMANT }));
        check(t.applyWifi(3, wifi(3, STATION, null)), "11: station without ssid yet", .{});
        expectCell(&t, null, &.{}, "11 dormant");
        const r = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        check(r.ask and r.changed, "11: station going up asks again = {any}", .{r});
        expectCell(&t, "WLAN", &.{.wait}, "11 up before the answer");
        check(t.applyWifi(3, wifi(3, STATION, "tars-wl")), "11: ssid arrives", .{});
        expectCell(&t, "tars-wl", &.{.wait}, "11 associated");
        _ = t.applyAddr(addr(3, .{ 192, 168, 4, 2 }), true);
        expectCell(&t, "tars-wl", &.{.ready}, "11 with address");
        check(!t.applyWifi(3, wifi(3, STATION, "tars-wl")), "11: the same answer changes nothing", .{});
    }

    // 12. AP가 같은 SSID로 올라와도 칸에는 station 하나다(design 확인 3).
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        _ = t.applyWifi(3, wifi(3, AP, "tars-wl"));
        _ = t.applyLink(parsedLink(.{ .index = 4, .name = "wlan1" }));
        _ = t.applyWifi(4, wifi(4, STATION, "tars-wl"));
        _ = t.applyAddr(addr(4, .{ 192, 168, 4, 2 }), true);
        check(t.find(3).?.kind == .wifi_other and t.find(3).?.ssid_len == null, "12: AP keeps no ssid", .{});
        expectCell(&t, "tars-wl", &.{.ready}, "12");
    }

    // 13. 둘 다 — 유선 앞, 사이 두 칸, 색이 따로.
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 2, .name = "eth0" }));
        _ = t.applyWifi(2, null);
        _ = t.applyAddr(addr(2, .{ 10, 0, 2, 15 }), true);
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        _ = t.applyWifi(3, wifi(3, STATION, "tars-wl"));
        expectCell(&t, "LAN  tars-wl", &.{ .ready, .wait }, "13");
        const c = link.cell(&t).?;
        check(std.mem.eql(u8, c.pieceText(c.pieces[1].?), "tars-wl"), "13: second piece text", .{});
        // 같은 표에서 두 번 지은 칸은 `std.meta.eql`로 같다(plan 확정 7).
        check(std.meta.eql(c, link.cell(&t).?), "13: cells compare equal", .{});
    }

    // 14. down · DELLINK.
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        _ = t.applyWifi(3, wifi(3, STATION, "tars-wl"));
        expectCell(&t, "tars-wl", &.{.wait}, "14 up");
        const r = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0", .oper = IF_OPER_DORMANT }));
        check(r.changed and !r.ask, "14: going down = {any}", .{r});
        check(t.find(3).?.ssid_len == null, "14: ssid forgotten", .{});
        expectCell(&t, null, &.{}, "14 down");
        check(t.removeLink(3) and t.len == 0, "14: DELLINK removes", .{});
        check(!t.removeLink(3), "14: removing twice", .{});
    }

    // 15. 가상 · 비ether는 묻지 않고 칸에 안 오른다.
    {
        var t: link.Table = .{};
        const r1 = t.applyLink(parsedLink(.{ .index = 1, .name = "lo", .arphrd = 772, .oper = 0 }));
        const r2 = t.applyLink(parsedLink(.{ .index = 7, .name = "docker0", .info_kind = "bridge\x00" }));
        check(r1.new and !r1.ask and r2.new and !r2.ask, "15: no nl80211 question", .{});
        check(t.find(1).?.kind == .not_ether and t.find(7).?.kind == .virtual, "15: kinds", .{});
        check(!t.applyWifi(7, null), "15: a stray answer for a virtual link is ignored", .{});
        _ = t.applyAddr(addr(7, .{ 172, 17, 0, 1 }), true);
        expectCell(&t, null, &.{}, "15");
        check(std.mem.eql(u8, link.kindName(.virtual), "ignored(virtual)"), "15: kindName", .{});
    }

    // 16. station이 내려갔다가 AP로 올라온다 → 다시 묻고 칸에서 빠진다.
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        _ = t.applyWifi(3, wifi(3, STATION, "home"));
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0", .oper = 2 }));
        const r = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        check(r.ask, "16: asks again when it comes back up", .{});
        check(t.applyWifi(3, wifi(3, AP, "tars-wl")), "16: the answer is now AP", .{});
        expectCell(&t, null, &.{}, "16");
    }

    // 17. SSID attribute가 없는 station은 WLAN이다.
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        _ = t.applyWifi(3, wifi(3, STATION, null));
        expectCell(&t, "WLAN", &.{.wait}, "17");
    }

    // 18. station 둘이 붙으면 ifindex가 작은 쪽이다(본 순서와 반대로 넣는다).
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 9, .name = "wlan1" }));
        _ = t.applyWifi(9, wifi(9, STATION, "dongle"));
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        _ = t.applyWifi(3, wifi(3, STATION, "inside"));
        expectCell(&t, "inside", &.{.wait}, "18");
    }

    // 19. 표가 찬다.
    {
        var t: link.Table = .{};
        var i: i32 = 1;
        while (i <= link.IFACE_MAX) : (i += 1) {
            const r = t.applyLink(parsedLink(.{ .index = i, .name = "veth", .info_kind = "veth\x00" }));
            check(!r.full, "19: interface {d} fits", .{i});
        }
        const r = t.applyLink(parsedLink(.{ .index = 99, .name = "eth9" }));
        check(r.full and !r.ask and t.len == link.IFACE_MAX, "19: ninth is dropped = {any}", .{r});
    }

    // 20. cleanSsid(plan 확정 8).
    {
        expectSsid("tars-wl", "tars-wl");
        expectSsid("우리집", "우리집");
        expectSsid("a\x00b\x1Fc\x7F", "a?b?c?");
        expectSsid("x\xFFy", "x?y");
        expectSsid("\xC2\x85z", "??z"); // U+0085(C1)
        expectSsid("ab\xED\x95", "ab??"); // 잘린 `한`
        expectSsid("\xED\xA0\x80", "???"); // 서로게이트
        expectSsid("0123456789abcdef0123456789abcdefX", "0123456789abcdef0123456789abcdef");
        // 이름이 15바이트를 넘으면 표가 자른다.
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 2, .name = "averyveryverylongname" }));
        check(std.mem.eql(u8, t.find(2).?.nameText(), "averyveryverylo"), "20: name cut at 15 bytes", .{});
    }

    // 21. GET_SCAN 요청의 바이트 — GET_INTERFACE와 명령 · flags만 다르다.
    {
        var buf: [link.REQUEST_MAX]u8 = undefined;
        const gs = link.buildGetScan(&buf, 0x22, 5, 3);
        const want = [_]u8{ 28, 0, 0, 0, 0x22, 0, 0x01, 0x03, 5, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 8, 0, 3, 0, 3, 0, 0, 0 };
        check(std.mem.eql(u8, gs, &want), "21: GET_SCAN = {any}", .{gs});
    }

    // 22. parseScanBss — associated BSS의 probe 요소, beacon 요소만, 붙지 않은 BSS, 숨긴 망, 잘린 요소.
    {
        // 요소: SUPP_RATES(1)가 앞, 그 뒤 SSID(0) "tars-wl".
        const ies = [_]u8{ 1, 2, 0x82, 0x84, 0, 7 } ++ "tars-wl".*;
        var b: Builder = .{};
        scanMsg(&b, 1, &ies, null);
        const a = link.parseScanBss(b.payload());
        check(a != null and a.?.associated and std.mem.eql(u8, a.?.ssid.?, "tars-wl"), "22: associated bss with ies", .{});

        b = .{};
        scanMsg(&b, null, null, &([_]u8{ 0, 4 } ++ "home".*));
        const c = link.parseScanBss(b.payload());
        check(c != null and !c.?.associated and std.mem.eql(u8, c.?.ssid.?, "home"), "22: beacon ies only, not associated", .{});

        check(link.ieSsid(&.{ 0, 0, 1, 1, 2 }) == null, "22: hidden ssid (length 0) is none", .{});
        check(link.ieSsid(&.{ 1, 9, 0, 0 }) == null, "22: truncated element stops", .{});
        check(link.parseScanBss(&.{ 34, 1, 0, 0 }) == null, "22: no NL80211_ATTR_BSS", .{});
    }

    // 23. GET_INTERFACE에 SSID가 없는 station(Country IE 없는 AP, LK-M1 결과 3) → GET_SCAN으로 채운다.
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        _ = t.applyWifi(3, wifi(3, STATION, null));
        check(t.needsScan(3), "23: station up without ssid needs a scan", .{});
        check(t.applySsid(3, "tars-wl") == .changed, "23: ssid from the scan", .{});
        check(t.applySsid(3, "tars-wl") == .same, "23: the same ssid again", .{});
        check(!t.needsScan(3), "23: no scan once the ssid is known", .{});
        expectCell(&t, "tars-wl", &.{.wait}, "23");
        // 내려가면 잊고, 다시 올라오면 또 필요하다.
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0", .oper = IF_OPER_DORMANT }));
        check(!t.needsScan(3), "23: down needs no scan", .{});
        _ = t.applyLink(parsedLink(.{ .index = 3, .name = "wlan0" }));
        check(t.needsScan(3), "23: up again needs a scan", .{});
    }

    // 24. applySsid는 station만 받는다.
    {
        var t: link.Table = .{};
        _ = t.applyLink(parsedLink(.{ .index = 2, .name = "eth0" }));
        _ = t.applyWifi(2, null);
        _ = t.applyLink(parsedLink(.{ .index = 4, .name = "wlan1" }));
        _ = t.applyWifi(4, wifi(4, AP, "tars-wl"));
        check(t.applySsid(2, "x") == .ignored and t.applySsid(4, "x") == .ignored and t.applySsid(9, "x") == .ignored, "24: ignored", .{});
        check(!t.needsScan(2) and !t.needsScan(4), "24: wired and AP need no scan", .{});
        expectCell(&t, "LAN", &.{.wait}, "24");
    }

    if (failures > 0) {
        std.debug.print("link_test: {d} FAILED\n", .{failures});
        std.process.exit(1);
    }
    std.debug.print("link_test: all 24 checks passed\n", .{});
}
