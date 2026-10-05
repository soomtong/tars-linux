const std = @import("std");
const pointer = @import("pointer.zig");
const touchpad = @import("touchpad.zig");
const c = pointer.c;

/// 게이트의 되감기 도구(`pointer/replay/`)가 만드는 패드와 같은 축이다. 세로의
/// resolution이 가로와 달라서 "세로를 같은 mm당 픽셀로 맞춘다"가 숫자로 보인다 —
/// 가로는 1280 / 1000 = 1.28픽셀/단위, 세로는 1.28 × 10 / 12 = 16/15픽셀/단위.
const PAD: touchpad.Setup = .{
    .mode = .mt,
    .x = .{ .min = 0, .max = 1000, .res = 10 },
    .y = .{ .min = 0, .max = 600, .res = 12 },
    .slots = 2,
};

/// 게이트 프레임버퍼의 가로와, `main.zig`가 넘기는 눈금(`WHEEL_ROWS` 3 ×
/// `ROW_HEIGHT` 16).
const SCREEN: touchpad.Screen = .{ .w = 1280, .notch_px = 48 };

/// 디코더 하나와 시계 하나. 낸 `Frame`을 다 모아 둔다.
const Pad = struct {
    tp: touchpad.Touchpad,
    t_us: i64 = 1_000_000,
    frames: [64]pointer.Frame = undefined,
    n: usize = 0,

    fn init(setup: touchpad.Setup) Pad {
        return .{ .tp = touchpad.Touchpad.init(setup, SCREEN) };
    }

    fn ev(self: *Pad, ev_type: anytype, code: anytype, value: i32) void {
        const out = self.tp.feed(@intCast(ev_type), @intCast(code), value, self.t_us);
        for (out.slice()) |f| {
            self.frames[self.n] = f;
            self.n += 1;
        }
    }

    fn syn(self: *Pad) void {
        self.ev(c.EV_SYN, c.SYN_REPORT, 0);
    }

    fn wait(self: *Pad, ms: i64) void {
        self.t_us += ms * 1000;
    }

    /// 칸 `slot`에 새 접촉. 자리를 함께 알린다.
    fn down(self: *Pad, slot: i32, id: i32, x: i32, y: i32) void {
        self.ev(c.EV_ABS, c.ABS_MT_SLOT, slot);
        self.ev(c.EV_ABS, c.ABS_MT_TRACKING_ID, id);
        self.ev(c.EV_ABS, c.ABS_MT_POSITION_X, x);
        self.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
    }

    fn up(self: *Pad, slot: i32) void {
        self.ev(c.EV_ABS, c.ABS_MT_SLOT, slot);
        self.ev(c.EV_ABS, c.ABS_MT_TRACKING_ID, -1);
    }

    fn sumDx(self: *const Pad) i32 {
        var s: i32 = 0;
        for (self.frames[0..self.n]) |f| s += f.dx;
        return s;
    }

    fn sumDy(self: *const Pad) i32 {
        var s: i32 = 0;
        for (self.frames[0..self.n]) |f| s += f.dy;
        return s;
    }

    fn sumWheel(self: *const Pad) i32 {
        var s: i32 = 0;
        for (self.frames[0..self.n]) |f| s += f.wheel;
        return s;
    }

    /// 왼쪽 버튼이 선 `Frame`의 수. 물리 버튼을 안 쓰는 검사에서는 탭의 수다.
    fn lefts(self: *const Pad) usize {
        var k: usize = 0;
        for (self.frames[0..self.n]) |f| {
            if (f.buttons.left) k += 1;
        }
        return k;
    }

    fn moved(self: *const Pad) bool {
        for (self.frames[0..self.n]) |f| {
            if (f.dx != 0 or f.dy != 0) return true;
        }
        return false;
    }

    fn clear(self: *Pad) void {
        self.n = 0;
    }
};

/// ioctl 비트맵의 비트 `n`을 세운다(낮은 번호부터, `pointer.bitSet`의 짝).
fn setBit(map: []u8, n: usize) void {
    map[n / 8] |= @as(u8, 1) << @intCast(n % 8);
}

fn expectTrue(what: []const u8, ok: bool) !void {
    if (ok) {
        std.debug.print("touchpad_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s}\n", .{what});
    return error.CheckFailed;
}

fn expectInt(what: []const u8, got: i64, want: i64) !void {
    if (got == want) {
        std.debug.print("touchpad_test: {s} = {d} OK\n", .{ what, got });
        return;
    }
    std.debug.print("FAIL: {s} = {d}, want {d}\n", .{ what, got, want });
    return error.WrongNumber;
}

fn expectFrames(what: []const u8, p: *const Pad, want: []const pointer.Frame) !void {
    const got = p.frames[0..p.n];
    if (got.len == want.len) {
        var same = true;
        for (got, want) |g, w| {
            if (!std.meta.eql(g, w)) same = false;
        }
        if (same) {
            std.debug.print("touchpad_test: {s} OK\n", .{what});
            return;
        }
    }
    std.debug.print("FAIL: {s}: got {any}, want {any}\n", .{ what, got, want });
    return error.WrongFrames;
}

/// 한 손가락을 (500, 300)에 대고 `steps`번 (dx, dy)씩 민 뒤 뗀다. 한 번에
/// `step_ms`씩 흐른다. 되감기 도구의 `move`와 같은 모양이다.
fn swipe(p: *Pad, id: i32, steps: usize, dx: i32, dy: i32, step_ms: i64) void {
    p.down(0, id, 500, 300);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
    p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
    p.syn();
    var x: i32 = 500;
    var y: i32 = 300;
    for (0..steps) |_| {
        p.wait(step_ms);
        x += dx;
        y += dy;
        if (dx != 0) p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, x);
        if (dy != 0) p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
        p.syn();
    }
    p.wait(step_ms);
    p.up(0);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
    p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
    p.syn();
}

/// 두 손가락을 (400, 300) · (600, 300)에 대고 `steps`번 세로로 `dy`씩 민 뒤
/// 함께 뗀다. 되감기 도구의 `scroll`과 같은 모양이다.
fn twoFinger(p: *Pad, steps: usize, dy: i32) void {
    p.down(0, 10, 400, 300);
    p.down(1, 11, 600, 300);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
    p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 1);
    p.syn();
    var y: i32 = 300;
    for (0..steps) |_| {
        p.wait(8);
        y += dy;
        p.ev(c.EV_ABS, c.ABS_MT_SLOT, 0);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
        p.ev(c.EV_ABS, c.ABS_MT_SLOT, 1);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
        p.syn();
    }
    p.wait(8);
    p.up(0);
    p.up(1);
    p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
    p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 0);
    p.syn();
}

/// 터치패드 디코더를 본다. 부팅도 fd도 안 쓴다(PD design 결정 3). 게이트의
/// 부팅 B가 같은 시나리오를 uinput으로 보고, 빨개졌을 때 이 검사가 "디코더냐
/// 배관이냐"를 가른다.
pub fn main() !void {
    // ── 검사 1: 어느 방식으로 읽나 ─────────────────────────────────────
    {
        var mt: pointer.Caps = .{};
        setBit(&mt.abs, c.ABS_MT_SLOT);
        setBit(&mt.abs, c.ABS_MT_POSITION_X);
        setBit(&mt.abs, c.ABS_MT_POSITION_Y);
        try expectTrue("MT slots and positions read as protocol B", touchpad.modeOf(&mt) == .mt);
        var st: pointer.Caps = .{};
        setBit(&st.abs, c.ABS_X);
        setBit(&st.abs, c.ABS_Y);
        try expectTrue("ABS_X and ABS_Y alone read as single touch", touchpad.modeOf(&st) == .st);
        var a: pointer.Caps = .{};
        setBit(&a.abs, c.ABS_MT_POSITION_X);
        setBit(&a.abs, c.ABS_MT_POSITION_Y);
        try expectTrue("MT positions without a slot and without ABS_X are not read", touchpad.modeOf(&a) == null);
    }

    // ── 검사 2: 한 손가락 이동의 배율 ───────────────────────────────────
    //
    // 가로 100단위(10단위씩 열 번)가 128픽셀이다 — 패드 가로 1000이 화면 가로
    // 1280이다. 10단위는 12.8픽셀이라 나머지를 넘겨야 합이 맞는다. 많이 움직였으니
    // 짧아도 탭이 아니다.
    {
        var p = Pad.init(PAD);
        swipe(&p, 1, 10, 10, 0, 8);
        try expectInt("one finger, 100 units across: dx", p.sumDx(), 128);
        try expectInt("one finger, 100 units across: dy", p.sumDy(), 0);
        try expectInt("a swipe of 100 units in 88ms is no tap", @intCast(p.lefts()), 0);

        // 세로 60단위는 64픽셀이다(16/15 배). 다시 닿은 손가락은 x만 알린다 —
        // 커널은 바뀐 값만 보내고 y는 직전 접촉의 300 그대로다. 디코더가 칸의
        // 옛 y를 지웠다면 여기서 튄다.
        p.clear();
        p.down(0, 2, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        try expectInt("a new contact moves nothing on its first report", @intCast(p.n), 0);
        var y: i32 = 300;
        for (0..6) |_| {
            p.wait(8);
            y += 10;
            p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
            p.syn();
        }
        try expectInt("one finger, 60 units down: dy (y follows the mm of x)", p.sumDy(), 64);
        try expectInt("one finger, 60 units down: dx", p.sumDx(), 0);
    }

    // ── 검사 3: 탭은 클릭이고, 긴 누름은 아무것도 아니다 ───────────────
    {
        var p = Pad.init(PAD);
        swipe(&p, 3, 0, 0, 0, 40);
        try expectFrames("a 40ms tap is a press and a release", &p, &.{
            .{ .buttons = .{ .left = true } },
            .{},
        });

        p.clear();
        swipe(&p, 4, 0, 0, 0, 500);
        try expectInt("a 500ms hold gives no frame", @intCast(p.n), 0);

        // 경계. 179ms는 탭이고 180ms는 아니다.
        p.clear();
        swipe(&p, 5, 0, 0, 0, 179);
        try expectInt("a 179ms touch is a tap", @intCast(p.lefts()), 1);
        p.clear();
        swipe(&p, 6, 0, 0, 0, 180);
        try expectInt("a 180ms touch is no tap", @intCast(p.lefts()), 0);
    }

    // ── 검사 4: 짧아도 많이 움직인 탭은 클릭이 아니다 ─────────────────
    //
    // 축 범위의 2%는 가로 20단위, 세로 12단위다. 20까지는 탭이고 21부터 아니다.
    {
        var p = Pad.init(PAD);
        swipe(&p, 7, 2, 10, 0, 8);
        try expectInt("a quick touch that drifts 20 units is still a tap", @intCast(p.lefts()), 1);
        try expectTrue("the drift still moved the pointer", p.moved());
        p.clear();
        swipe(&p, 8, 3, 7, 0, 8);
        try expectInt("a quick touch that drifts 21 units is no tap", @intCast(p.lefts()), 0);
        p.clear();
        swipe(&p, 9, 1, 0, 13, 8);
        try expectInt("a quick touch that drifts 13 units down is no tap", @intCast(p.lefts()), 0);
    }

    // ── 검사 5: 두 손가락 세로는 휠이고, 포인터는 안 움직인다 ───────────
    //
    // 90단위는 96픽셀이고 눈금은 48픽셀이라 둘이다. 손가락을 아래로 밀면 양수 —
    // 휠을 앞으로 민 것과 같은 쪽이다(내용이 손가락을 따라 내려간다).
    {
        var p = Pad.init(PAD);
        twoFinger(&p, 6, 15);
        try expectInt("two fingers, 90 units down: wheel", p.sumWheel(), 2);
        try expectTrue("two fingers never move the pointer", !p.moved());
        try expectInt("two fingers are no tap", @intCast(p.lefts()), 0);
        p.clear();
        twoFinger(&p, 6, -15);
        try expectInt("two fingers, 90 units up: wheel", p.sumWheel(), -2);

        // 칸은 하나만 찼는데 BTN_TOOL_DOUBLETAP이 둘이라고 하는 장치. 손가락 수는
        // 둘이고, 있는 접촉 하나의 변화로 스크롤한다.
        p.clear();
        p.down(0, 12, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 1);
        p.syn();
        var y: i32 = 300;
        for (0..6) |_| {
            p.wait(8);
            y += 15;
            p.ev(c.EV_ABS, c.ABS_MT_POSITION_Y, y);
            p.syn();
        }
        try expectInt("DOUBLETAP with one slot filled still scrolls", p.sumWheel(), 2);
        try expectTrue("and does not move the pointer", !p.moved());
    }

    // ── 검사 6: 버튼을 누른 채 두 손가락이면 늦게 닿은 손가락이 끈다 ────
    //
    // 엄지(칸 0)로 clickpad를 누르고 검지(칸 1)로 끈다(design 결정 8). 스크롤로
    // 안 가고, 버튼은 그대로 통과한다.
    {
        var p = Pad.init(PAD);
        p.down(0, 20, 300, 500);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        p.wait(8);
        p.ev(c.EV_KEY, c.BTN_LEFT, 1);
        p.syn();
        try expectFrames("the physical button passes through", &p, &.{.{ .buttons = .{ .left = true } }});
        p.clear();
        p.wait(8);
        p.down(1, 21, 600, 300);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 1);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_SLOT, 1);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 650);
        p.syn();
        try expectFrames("the later finger drags with the button held", &p, &.{
            .{ .dx = 64, .buttons = .{ .left = true } },
        });
        p.clear();
        p.wait(8);
        p.ev(c.EV_KEY, c.BTN_LEFT, 0);
        p.syn();
        p.wait(8);
        p.up(0);
        p.up(1);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_DOUBLETAP, 0);
        p.syn();
        try expectFrames("letting go releases the button and is no tap", &p, &.{.{}});
    }

    // ── 검사 7: SYN_DROPPED 뒤에는 모두 뗀 것으로 하고 새로 센다 ─────────
    {
        var p = Pad.init(PAD);
        p.down(0, 30, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.ev(c.EV_KEY, c.BTN_LEFT, 1);
        p.syn();
        p.clear();
        p.ev(c.EV_SYN, c.SYN_DROPPED, 0);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 900);
        p.ev(c.EV_KEY, c.BTN_LEFT, 0);
        p.syn();
        try expectFrames("the report after SYN_DROPPED releases the held button", &p, &.{.{}});
        p.clear();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 950);
        p.syn();
        try expectInt("a finger still down from before the drop moves nothing", @intCast(p.n), 0);
        p.wait(8);
        p.up(0);
        p.syn();
        p.wait(8);
        p.down(0, 31, 500, 300);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 550);
        p.syn();
        try expectFrames("a new contact after the drop moves again", &p, &.{.{ .dx = 64 }});
    }

    // ── 검사 8: 두 손가락 탭은 클릭이 아니다(비목표 6) ──────────────────
    {
        var p = Pad.init(PAD);
        twoFinger(&p, 0, 0);
        try expectInt("a quick two-finger touch gives no frame", @intCast(p.n), 0);
    }

    // ── 검사 9: 단일 터치 장치 ──────────────────────────────────────────
    //
    // `ABS_X` · `ABS_Y`와 `BTN_TOUCH`만 있다. 칸 0 하나로 이동과 탭이 된다.
    {
        var st = PAD;
        st.mode = .st;
        var p = Pad.init(st);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.ev(c.EV_ABS, c.ABS_X, 500);
        p.ev(c.EV_ABS, c.ABS_Y, 300);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_X, 550);
        p.syn();
        p.wait(8);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
        p.syn();
        try expectFrames("single touch: 50 units across, then no tap", &p, &.{.{ .dx = 64 }});
        p.clear();
        p.wait(100);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 1);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        p.wait(40);
        p.ev(c.EV_KEY, c.BTN_TOUCH, 0);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 0);
        p.syn();
        try expectInt("single touch: a 40ms touch is a tap", @intCast(p.lefts()), 1);
    }

    // ── 검사 10: 범위 밖의 칸은 버린다 ──────────────────────────────────
    {
        var p = Pad.init(PAD);
        p.down(7, 40, 100, 100);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 300);
        p.syn();
        try expectInt("events for slot 7 of a two-slot pad are dropped", @intCast(p.n), 0);
        p.down(0, 41, 500, 300);
        p.ev(c.EV_KEY, c.BTN_TOOL_FINGER, 1);
        p.syn();
        p.wait(8);
        p.ev(c.EV_ABS, c.ABS_MT_POSITION_X, 550);
        p.syn();
        try expectFrames("slot 0 still works after a stray slot", &p, &.{.{ .dx = 64 }});
    }

    std.debug.print("touchpad_test: all checks passed\n", .{});
}
