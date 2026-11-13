//! `yield.Machine`의 호스트 검사(DY-M0). 가짜 `ops`가 부른 것을 적고, 그 기록으로 전이를 본다.
//! fd는 진짜가 아니다 — 숫자만 오간다.

const std = @import("std");
const yield = @import("yield.zig");
const proto = @import("display_proto");

const Fake = struct {
    drop_fails: bool = false,
    /// `setMaster`가 이 횟수만큼 `MasterBusy`를 낸 뒤 성공한다.
    busy_left: u32 = 0,
    drops: u32 = 0,
    sets: u32 = 0,
    modesets: u32 = 0,
    sent: [8]struct { fd: i32, r: proto.Reply } = undefined,
    nsent: usize = 0,
    closed: [8]i32 = undefined,
    nclosed: usize = 0,
    /// `pgid`가 돌려줄 값. null이면 그 pid가 자기 그룹의 리더다.
    group: ?i32 = null,
    kills: [4]struct { target: i32, sig: yield.Signal } = undefined,
    nkills: usize = 0,
    /// 키보드의 문(DY-M1). 넘긴 uid와 되돌린 횟수, 그리고 그 순간 이미 보낸 답의 수(`ok` 앞인가를 본다).
    handed: ?u32 = null,
    handed_after_sent: usize = 0,
    taken: u32 = 0,
    taken_before_set: bool = false,

    pub fn dropMaster(self: *Fake) !void {
        if (self.drop_fails) return error.IoctlFailed;
        self.drops += 1;
    }
    pub fn setMaster(self: *Fake) !void {
        self.sets += 1;
        if (self.busy_left > 0) {
            self.busy_left -= 1;
            return error.MasterBusy;
        }
    }
    pub fn modeset(self: *Fake) !void {
        self.modesets += 1;
    }
    pub fn send(self: *Fake, fd: i32, r: proto.Reply) void {
        self.sent[self.nsent] = .{ .fd = fd, .r = r };
        self.nsent += 1;
    }
    pub fn close(self: *Fake, fd: i32) void {
        self.closed[self.nclosed] = fd;
        self.nclosed += 1;
    }

    pub fn handInputs(self: *Fake, uid: u32) void {
        self.handed = uid;
        self.handed_after_sent = self.nsent;
    }
    pub fn takeInputs(self: *Fake) void {
        self.taken += 1;
        self.taken_before_set = self.sets == 0;
    }

    pub fn pgid(self: *Fake, pid: i32) ?i32 {
        return self.group orelse pid;
    }
    pub fn kill(self: *Fake, target: i32, sig: yield.Signal) void {
        self.kills[self.nkills] = .{ .target = target, .sig = sig };
        self.nkills += 1;
    }

    fn lastSent(self: *const Fake) ?proto.Reply {
        return if (self.nsent == 0) null else self.sent[self.nsent - 1].r;
    }
};

fn expect(ok: bool, what: []const u8) !void {
    if (!ok) {
        std.debug.print("FAIL: {s}\n", .{what});
        return error.TestFailed;
    }
}

pub fn main() !void {
    // ── 1. 양보와 복귀 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        try expect(m.ownsScreen() and m.timeout(0) == -1, "starts ours, no timeout");
        m.arrive(&f, 10, 100, 1000);
        try expect(m.ownsScreen() and f.nsent == 0, "a guest that has not asked keeps the screen ours");
        m.said(&f, "yield");
        try expect(!m.ownsScreen() and m.state == .yielded, "yield → yielded");
        try expect(f.drops == 1 and f.lastSent() == .ok and f.sent[0].fd == 10, "dropMaster then ok to the guest");
        try expect(!m.retry(&f, 0) and f.sets == 0, "retry does nothing while the guest holds the screen");
        try expect(m.gone(&f), "the guest leaves → reclaimed");
        try expect(m.ownsScreen() and f.sets == 1 and f.modesets == 1, "setMaster then modeset");
        try expect(f.nclosed == 1 and f.closed[0] == 10 and m.guest_fd == -1, "the guest fd is closed");
    }
    // ── 2. 둘째 손님은 busy — 양보 중에도, 묻기 전에도 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100, 1000);
        m.arrive(&f, 11, 101, 1000);
        try expect(f.lastSent() == .busy and f.sent[0].fd == 11 and f.closed[0] == 11, "a second guest before yield gets busy and is closed");
        m.said(&f, "yield");
        m.arrive(&f, 12, 102, 1000);
        try expect(f.lastSent() == .busy and f.closed[1] == 12, "a guest during yield gets busy");
        try expect(m.guest_fd == 10 and m.state == .yielded, "the first guest is untouched");
    }
    // ── 3. yield 전에 닫힘 — 화면은 처음부터 우리 것이다 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100, 1000);
        try expect(!m.gone(&f), "leaving before yield reclaims nothing");
        try expect(f.sets == 0 and f.modesets == 0 and m.ownsScreen() and m.guest_fd == -1, "no ioctl, the slot is free");
        m.arrive(&f, 11, 101, 1000);
        try expect(m.guest_fd == 11, "the next guest is taken");
    }
    // ── 4. 남이 아직 master — waiting, 1초마다, 줄은 한 번 ──
    {
        var f: Fake = .{ .busy_left = 2 };
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100, 1000);
        m.said(&f, "yield");
        try expect(!m.gone(&f) and m.state == .waiting, "MasterBusy → waiting");
        try expect(m.timeout(0) == yield.RETRY_MS and !m.ownsScreen(), "waiting asks poll for a 1s wake and does not draw");
        m.arrive(&f, 11, 101, 1000);
        try expect(f.lastSent() == .busy, "a guest while waiting gets busy");
        try expect(!m.retry(&f, 0) and m.state == .waiting, "still busy on the first retry");
        try expect(m.retry(&f, 0) and m.ownsScreen() and f.sets == 3 and f.modesets == 1, "the second retry reclaims, modeset once");
    }
    // ── 5. 놓지 못함 · 모르는 요청 — refused, 화면은 그대로 ──
    {
        var f: Fake = .{ .drop_fails = true };
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100, 1000);
        m.said(&f, "yield");
        try expect(f.lastSent() == .refused and f.closed[0] == 10 and m.ownsScreen() and m.guest_fd == -1, "dropMaster fails → refused");
        var g: Fake = .{};
        m.arrive(&g, 11, 101, 1000);
        m.said(&g, "yield\n");
        try expect(g.lastSent() == .refused and g.drops == 0 and m.ownsScreen(), "an unknown word → refused, no ioctl");
    }
    // ── 6. 양보 뒤의 말은 무시한다 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100, 1000);
        m.said(&f, "yield");
        m.said(&f, "yield");
        try expect(f.drops == 1 and f.nsent == 1 and m.state == .yielded, "a second yield is ignored");
    }
    // ── 7. 탈출 조합(DY-M1) — SIGTERM을 그룹에, 2초 뒤 SIGKILL 한 번 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        m.escape(&f, 1000);
        try expect(f.nkills == 0, "the chord does nothing while the screen is ours");
        m.arrive(&f, 10, 100, 1000);
        m.said(&f, "yield");
        m.escape(&f, 1000);
        try expect(f.nkills == 1 and f.kills[0].target == -100 and f.kills[0].sig == .term, "SIGTERM to the guest's group");
        try expect(m.timeout(1500) == 1500, "poll wakes at the SIGKILL deadline (1000 + 2000)");
        m.escape(&f, 1200);
        try expect(f.nkills == 1, "pressing it again within the deadline sends nothing more");
        try expect(!m.retry(&f, 2999) and f.nkills == 1, "no SIGKILL before the deadline");
        try expect(!m.retry(&f, 3000) and f.nkills == 2 and f.kills[1].target == -100 and f.kills[1].sig == .kill, "SIGKILL at the deadline");
        try expect(!m.retry(&f, 4000) and f.nkills == 2 and m.timeout(4000) == -1, "SIGKILL only once, no more wakes");
        try expect(m.gone(&f) and m.ownsScreen(), "the guest dies → reclaimed");
        try expect(m.kill_at == null and !m.killed, "the deadline is cleared");
    }
    // ── 8. 기한 전에 떠나면 SIGKILL은 없다 · 그룹 리더가 아니면 pid 하나 ──
    {
        var f: Fake = .{ .group = 7 };
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100, 1000);
        m.said(&f, "yield");
        m.escape(&f, 0);
        try expect(f.kills[0].target == 100, "not a group leader → the pid alone, not the shell's group");
        try expect(m.gone(&f), "SIGTERM was enough");
        try expect(!m.retry(&f, 5000) and f.nkills == 1, "no SIGKILL after the guest left");
    }
    // ── 9. 키보드의 문(DY-M1, design 결정 8a) — `ok` 앞에 손님의 uid로, 되찾기 앞에 root로, 한 번씩 ──
    {
        var f: Fake = .{ .busy_left = 1 };
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100, 1000);
        try expect(f.handed == null, "nothing is handed before yield");
        m.said(&f, "yield");
        try expect(f.handed == 1000 and f.handed_after_sent == 0 and f.lastSent() == .ok, "handed to uid 1000 before ok");
        try expect(!m.gone(&f) and m.state == .waiting, "MasterBusy → waiting");
        try expect(f.taken == 1 and f.taken_before_set, "taken back before SET_MASTER, even when still waiting");
        try expect(m.retry(&f, 0) and f.taken == 1, "the retry reclaims without taking them twice");
        var g: Fake = .{ .drop_fails = true };
        var n: yield.Machine = .{};
        n.arrive(&g, 10, 100, 1000);
        n.said(&g, "yield");
        try expect(g.handed == null and g.taken == 0, "refused → nothing handed, nothing to take");
        var h: Fake = .{};
        var o: yield.Machine = .{};
        o.arrive(&h, 10, 100, 1000);
        try expect(!o.gone(&h) and h.taken == 0, "leaving before yield takes nothing");
    }
    // ── 10. master 없이 뜬 terminal(DY-M1, design 결정 11) — 손님 없는 기다림, 키는 셸에, 되찾으면 보통 ──
    {
        var f: Fake = .{ .busy_left = 1 };
        var m: yield.Machine = .{};
        m.startWaiting();
        try expect(!m.ownsScreen() and !m.holdsInput() and m.timeout(0) == yield.RETRY_MS, "blind waiting: no drawing, keys to the shell, 1s wakes");
        m.escape(&f, 0);
        try expect(f.nkills == 0, "the chord has no one to signal");
        m.arrive(&f, 10, 100, 1000);
        try expect(f.lastSent() == .busy, "a guest while blind-waiting gets busy");
        try expect(!m.retry(&f, 0) and m.state == .waiting, "still busy");
        try expect(m.retry(&f, 0) and m.ownsScreen() and !m.blind and f.taken == 0, "reclaimed; nothing to take back");
        m.arrive(&f, 11, 101, 1000);
        m.said(&f, "yield");
        try expect(m.holdsInput(), "a later yield holds input as usual");
    }
    std.debug.print("yield_test: a terminal started without master waits blind, gives keys to the shell, then works as usual\n", .{});

    std.debug.print("yield_test: inputs go to the guest's uid before ok and back to root before reclaim, once\n", .{});

    std.debug.print("yield_test: the chord sends SIGTERM to the guest's group, SIGKILL once after 2s, nothing if it left\n", .{});

    std.debug.print("yield_test: yield and reclaim, busy for a second guest, waiting retries, refused leaves the screen ours\n", .{});
}
