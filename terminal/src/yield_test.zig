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
        try expect(m.ownsScreen() and m.timeout() == -1, "starts ours, no timeout");
        m.arrive(&f, 10, 100);
        try expect(m.ownsScreen() and f.nsent == 0, "a guest that has not asked keeps the screen ours");
        m.said(&f, "yield");
        try expect(!m.ownsScreen() and m.state == .yielded, "yield → yielded");
        try expect(f.drops == 1 and f.lastSent() == .ok and f.sent[0].fd == 10, "dropMaster then ok to the guest");
        try expect(!m.retry(&f) and f.sets == 0, "retry does nothing while the guest holds the screen");
        try expect(m.gone(&f), "the guest leaves → reclaimed");
        try expect(m.ownsScreen() and f.sets == 1 and f.modesets == 1, "setMaster then modeset");
        try expect(f.nclosed == 1 and f.closed[0] == 10 and m.guest_fd == -1, "the guest fd is closed");
    }
    // ── 2. 둘째 손님은 busy — 양보 중에도, 묻기 전에도 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100);
        m.arrive(&f, 11, 101);
        try expect(f.lastSent() == .busy and f.sent[0].fd == 11 and f.closed[0] == 11, "a second guest before yield gets busy and is closed");
        m.said(&f, "yield");
        m.arrive(&f, 12, 102);
        try expect(f.lastSent() == .busy and f.closed[1] == 12, "a guest during yield gets busy");
        try expect(m.guest_fd == 10 and m.state == .yielded, "the first guest is untouched");
    }
    // ── 3. yield 전에 닫힘 — 화면은 처음부터 우리 것이다 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100);
        try expect(!m.gone(&f), "leaving before yield reclaims nothing");
        try expect(f.sets == 0 and f.modesets == 0 and m.ownsScreen() and m.guest_fd == -1, "no ioctl, the slot is free");
        m.arrive(&f, 11, 101);
        try expect(m.guest_fd == 11, "the next guest is taken");
    }
    // ── 4. 남이 아직 master — waiting, 1초마다, 줄은 한 번 ──
    {
        var f: Fake = .{ .busy_left = 2 };
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100);
        m.said(&f, "yield");
        try expect(!m.gone(&f) and m.state == .waiting, "MasterBusy → waiting");
        try expect(m.timeout() == yield.RETRY_MS and !m.ownsScreen(), "waiting asks poll for a 1s wake and does not draw");
        m.arrive(&f, 11, 101);
        try expect(f.lastSent() == .busy, "a guest while waiting gets busy");
        try expect(!m.retry(&f) and m.state == .waiting, "still busy on the first retry");
        try expect(m.retry(&f) and m.ownsScreen() and f.sets == 3 and f.modesets == 1, "the second retry reclaims, modeset once");
    }
    // ── 5. 놓지 못함 · 모르는 요청 — refused, 화면은 그대로 ──
    {
        var f: Fake = .{ .drop_fails = true };
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100);
        m.said(&f, "yield");
        try expect(f.lastSent() == .refused and f.closed[0] == 10 and m.ownsScreen() and m.guest_fd == -1, "dropMaster fails → refused");
        var g: Fake = .{};
        m.arrive(&g, 11, 101);
        m.said(&g, "yield\n");
        try expect(g.lastSent() == .refused and g.drops == 0 and m.ownsScreen(), "an unknown word → refused, no ioctl");
    }
    // ── 6. 양보 뒤의 말은 무시한다 ──
    {
        var f: Fake = .{};
        var m: yield.Machine = .{};
        m.arrive(&f, 10, 100);
        m.said(&f, "yield");
        m.said(&f, "yield");
        try expect(f.drops == 1 and f.nsent == 1 and m.state == .yielded, "a second yield is ignored");
    }
    std.debug.print("yield_test: yield and reclaim, busy for a second guest, waiting retries, refused leaves the screen ours\n", .{});
}
