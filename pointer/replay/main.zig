//! PD-M3의 게이트 전용 되감기 도구 `tp-replay`(PD design 결정 10).
//!
//! `/dev/uinput`으로 가짜 터치패드 하나를 만들고, stdin에서 한 줄씩 명령을 받아
//! 그 손동작의 이벤트를 쓴다. 커널의 입력 core가 진짜 드라이버의 이벤트와 같은
//! 길로 evdev 노드에 내보내므로, terminal은 이 장치를 부팅 뒤에 꽂힌 터치패드로
//! 본다 — uevent로 알고, ioctl로 분류하고, 축 범위를 읽고, 디코더에 먹인다.
//!
//!   move DX DY   한 손가락을 패드 가운데에 대고 (DX, DY) 단위만큼 10단위씩
//!                8ms 간격으로 민 뒤 뗀다
//!   tap          가운데에 40ms 대었다 뗀다
//!   hold         가운데에 500ms 대었다 뗀다
//!   scroll DY    두 손가락을 대고 함께 세로로 DY 단위만큼 15단위씩 민 뒤 뗀다
//!   quit         장치를 없애고 끝난다(stdin이 끝나도 같다)
//!
//! 이벤트의 시각은 커널이 주입하는 순간에 찍으므로 탭의 길이는 이 도구가 자는
//! 시간이 정한다. 명령을 마친 뒤에는 아무것도 찍지 않는다 — 출력이 패널에 오면
//! 그 패널이 바닥으로 돌아가 스크롤 검사가 흔들린다.
//!
//! 제품 initrd에는 없다. pointer 체인이 빌드해 설정 디스크의 `pd/tp-replay`로
//! 싣고 게스트 셸에서 친다.
const std = @import("std");
const linux = std.os.linux;

// linux/uinput.h의 요청 번호. `_IOW('U', nr, T)`는 (1 << 30) | (sizeof T << 16) |
// ('U' << 8) | nr이다. 번역(translate-c)을 안 쓰는 이유는 이 도구가 init처럼 libc
// 없이 빌드되고 번역 패키지에 기대지 않아서다. 값은 PD-M3 plan 확정 7이 컨테이너의
// 헤더를 C로 컴파일해 대조했다.
const UI_DEV_CREATE: u32 = 0x5501;
const UI_DEV_DESTROY: u32 = 0x5502;
const UI_DEV_SETUP: u32 = 0x405c5503;
const UI_ABS_SETUP: u32 = 0x401c5504;
const UI_SET_EVBIT: u32 = 0x40045564;
const UI_SET_KEYBIT: u32 = 0x40045565;
const UI_SET_ABSBIT: u32 = 0x40045567;
const UI_SET_PROPBIT: u32 = 0x4004556e;

// linux/input-event-codes.h · linux/input.h의 값.
const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const EV_ABS: u16 = 0x03;
const SYN_REPORT: u16 = 0;
const BTN_LEFT: u16 = 0x110;
const BTN_TOOL_FINGER: u16 = 0x145;
const BTN_TOUCH: u16 = 0x14a;
const BTN_TOOL_DOUBLETAP: u16 = 0x14d;
const BTN_TOOL_TRIPLETAP: u16 = 0x14e;
const ABS_X: u16 = 0x00;
const ABS_Y: u16 = 0x01;
const ABS_MT_SLOT: u16 = 0x2f;
const ABS_MT_POSITION_X: u16 = 0x35;
const ABS_MT_POSITION_Y: u16 = 0x36;
const ABS_MT_TRACKING_ID: u16 = 0x39;
const INPUT_PROP_POINTER: u16 = 0x00;
const INPUT_PROP_BUTTONPAD: u16 = 0x02;
const BUS_VIRTUAL: u16 = 0x06;

const InputId = extern struct { bustype: u16, vendor: u16, product: u16, version: u16 };
const DevSetup = extern struct { id: InputId, name: [80]u8, ff_effects_max: u32 };
const AbsInfo = extern struct { value: i32 = 0, minimum: i32, maximum: i32, fuzz: i32 = 0, flat: i32 = 0, resolution: i32 = 0 };
const AbsSetup = extern struct { code: u16, absinfo: AbsInfo };
/// `struct input_event`. x86_64에서 시각은 `long` 둘이다. uinput은 쓰는 쪽의
/// 시각을 버리고 커널이 다시 찍는다.
const Event = extern struct { sec: i64 = 0, usec: i64 = 0, type: u16, code: u16, value: i32 };

comptime {
    std.debug.assert(@sizeOf(DevSetup) == 92);
    std.debug.assert(@sizeOf(AbsSetup) == 28);
    std.debug.assert(@sizeOf(Event) == 24);
}

/// 패드의 축. `touchpad_test`의 `PAD`와 같다 — 세로의 resolution이 가로와 달라서
/// terminal이 세로를 같은 mm당 픽셀로 맞추는지가 좌표로 보인다.
const PAD_W = 1000;
const PAD_H = 600;
const RES_X = 10;
const RES_Y = 12;
const CX = 500;
const CY = 300;
const NAME = "TARS Replay Touchpad";

const STEP_MS: u64 = 8;
const MOVE_STEP: i32 = 10;
const SCROLL_STEP: i32 = 15;
const TAP_MS: u64 = 40;
const HOLD_MS: u64 = 500;

fn writeAll(fd: i32, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        switch (linux.errno(n)) {
            .SUCCESS => off += n,
            .INTR => continue,
            else => return false,
        }
    }
    return true;
}

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tp-replay: " ++ fmt ++ "\n", args) catch return;
    _ = writeAll(2, text);
}

fn sleepMs(ms: u64) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

fn ioctl(fd: i32, request: u32, arg: usize) bool {
    return linux.errno(linux.ioctl(fd, request, arg)) == .SUCCESS;
}

/// 한 묶음(`SYN_REPORT`까지)의 이벤트를 모아 한 번에 쓴다.
const Batch = struct {
    evs: [24]Event = undefined,
    n: usize = 0,

    fn add(self: *Batch, ev_type: u16, code: u16, value: i32) void {
        self.evs[self.n] = .{ .type = ev_type, .code = code, .value = value };
        self.n += 1;
    }

    fn send(self: *Batch, fd: i32) bool {
        self.add(EV_SYN, SYN_REPORT, 0);
        const bytes = std.mem.sliceAsBytes(self.evs[0..self.n]);
        self.n = 0;
        return writeAll(fd, bytes);
    }
};

const Pad = struct {
    fd: i32,
    next_id: i32 = 1,

    fn create() ?Pad {
        const rc = linux.open("/dev/uinput", .{ .ACCMODE = .WRONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
        if (linux.errno(rc) != .SUCCESS) {
            say("cannot open /dev/uinput (errno {d})", .{@intFromEnum(linux.errno(rc))});
            return null;
        }
        const fd: i32 = @intCast(rc);
        var ok = ioctl(fd, UI_SET_EVBIT, EV_KEY) and ioctl(fd, UI_SET_EVBIT, EV_ABS);
        for ([_]u16{ BTN_LEFT, BTN_TOOL_FINGER, BTN_TOUCH, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP }) |k| {
            ok = ok and ioctl(fd, UI_SET_KEYBIT, k);
        }
        for ([_]u16{ INPUT_PROP_POINTER, INPUT_PROP_BUTTONPAD }) |p| {
            ok = ok and ioctl(fd, UI_SET_PROPBIT, p);
        }
        const axes = [_]AbsSetup{
            .{ .code = ABS_X, .absinfo = .{ .minimum = 0, .maximum = PAD_W, .resolution = RES_X } },
            .{ .code = ABS_Y, .absinfo = .{ .minimum = 0, .maximum = PAD_H, .resolution = RES_Y } },
            .{ .code = ABS_MT_SLOT, .absinfo = .{ .minimum = 0, .maximum = 1 } },
            .{ .code = ABS_MT_POSITION_X, .absinfo = .{ .minimum = 0, .maximum = PAD_W, .resolution = RES_X } },
            .{ .code = ABS_MT_POSITION_Y, .absinfo = .{ .minimum = 0, .maximum = PAD_H, .resolution = RES_Y } },
            .{ .code = ABS_MT_TRACKING_ID, .absinfo = .{ .minimum = 0, .maximum = 65535 } },
        };
        for (&axes) |*a| {
            ok = ok and ioctl(fd, UI_SET_ABSBIT, a.code) and ioctl(fd, UI_ABS_SETUP, @intFromPtr(a));
        }
        var setup: DevSetup = .{
            .id = .{ .bustype = BUS_VIRTUAL, .vendor = 0x7a35, .product = 0x0003, .version = 1 },
            .name = @splat(0),
            .ff_effects_max = 0,
        };
        @memcpy(setup.name[0..NAME.len], NAME);
        ok = ok and ioctl(fd, UI_DEV_SETUP, @intFromPtr(&setup)) and ioctl(fd, UI_DEV_CREATE, 0);
        if (!ok) {
            say("uinput setup failed", .{});
            _ = linux.close(fd);
            return null;
        }
        return .{ .fd = fd };
    }

    fn destroy(self: *Pad) void {
        _ = ioctl(self.fd, UI_DEV_DESTROY, 0);
        _ = linux.close(self.fd);
    }

    fn id(self: *Pad) i32 {
        const v = self.next_id;
        self.next_id = if (v >= 65535) 1 else v + 1;
        return v;
    }

    /// 한 손가락을 (x, y)에 댄다. 커널의 터치패드 드라이버처럼 포인터 흉내
    /// (`ABS_X` · `ABS_Y`)와 `BTN_TOUCH` · `BTN_TOOL_FINGER`를 함께 낸다.
    fn touch1(self: *Pad, x: i32, y: i32) bool {
        var b: Batch = .{};
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, self.id());
        b.add(EV_ABS, ABS_MT_POSITION_X, x);
        b.add(EV_ABS, ABS_MT_POSITION_Y, y);
        b.add(EV_ABS, ABS_X, x);
        b.add(EV_ABS, ABS_Y, y);
        b.add(EV_KEY, BTN_TOUCH, 1);
        b.add(EV_KEY, BTN_TOOL_FINGER, 1);
        return b.send(self.fd);
    }

    fn lift1(self: *Pad) bool {
        var b: Batch = .{};
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, -1);
        b.add(EV_KEY, BTN_TOUCH, 0);
        b.add(EV_KEY, BTN_TOOL_FINGER, 0);
        return b.send(self.fd);
    }

    fn move(self: *Pad, dx: i32, dy: i32) bool {
        if (!self.touch1(CX, CY)) return false;
        const steps: i32 = @max(1, @divTrunc(@max(abs(dx), abs(dy)) + MOVE_STEP - 1, MOVE_STEP));
        var i: i32 = 1;
        while (i <= steps) : (i += 1) {
            sleepMs(STEP_MS);
            const x = CX + @divTrunc(dx * i, steps);
            const y = CY + @divTrunc(dy * i, steps);
            var b: Batch = .{};
            b.add(EV_ABS, ABS_MT_POSITION_X, x);
            b.add(EV_ABS, ABS_MT_POSITION_Y, y);
            b.add(EV_ABS, ABS_X, x);
            b.add(EV_ABS, ABS_Y, y);
            if (!b.send(self.fd)) return false;
        }
        sleepMs(STEP_MS);
        return self.lift1();
    }

    fn press(self: *Pad, ms: u64) bool {
        if (!self.touch1(CX, CY)) return false;
        sleepMs(ms);
        return self.lift1();
    }

    fn scroll(self: *Pad, dy: i32) bool {
        const x0 = CX - 100;
        const x1 = CX + 100;
        var b: Batch = .{};
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, self.id());
        b.add(EV_ABS, ABS_MT_POSITION_X, x0);
        b.add(EV_ABS, ABS_MT_POSITION_Y, CY);
        b.add(EV_ABS, ABS_MT_SLOT, 1);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, self.id());
        b.add(EV_ABS, ABS_MT_POSITION_X, x1);
        b.add(EV_ABS, ABS_MT_POSITION_Y, CY);
        b.add(EV_ABS, ABS_X, x0);
        b.add(EV_ABS, ABS_Y, CY);
        b.add(EV_KEY, BTN_TOUCH, 1);
        b.add(EV_KEY, BTN_TOOL_DOUBLETAP, 1);
        if (!b.send(self.fd)) return false;
        const steps: i32 = @max(1, @divTrunc(abs(dy) + SCROLL_STEP - 1, SCROLL_STEP));
        var i: i32 = 1;
        while (i <= steps) : (i += 1) {
            sleepMs(STEP_MS);
            const y = CY + @divTrunc(dy * i, steps);
            b.add(EV_ABS, ABS_MT_SLOT, 0);
            b.add(EV_ABS, ABS_MT_POSITION_Y, y);
            b.add(EV_ABS, ABS_MT_SLOT, 1);
            b.add(EV_ABS, ABS_MT_POSITION_Y, y);
            b.add(EV_ABS, ABS_Y, y);
            if (!b.send(self.fd)) return false;
        }
        sleepMs(STEP_MS);
        b.add(EV_ABS, ABS_MT_SLOT, 0);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, -1);
        b.add(EV_ABS, ABS_MT_SLOT, 1);
        b.add(EV_ABS, ABS_MT_TRACKING_ID, -1);
        b.add(EV_KEY, BTN_TOUCH, 0);
        b.add(EV_KEY, BTN_TOOL_DOUBLETAP, 0);
        return b.send(self.fd);
    }
};

fn abs(v: i32) i32 {
    return if (v < 0) -v else v;
}

/// 한 줄을 실행한다. 끝내야 하면 false다.
fn run(pad: *Pad, line: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    const verb = it.next() orelse return true;
    const a = if (it.next()) |t| std.fmt.parseInt(i32, t, 10) catch null else null;
    const b = if (it.next()) |t| std.fmt.parseInt(i32, t, 10) catch null else null;
    const ok = if (std.mem.eql(u8, verb, "move"))
        pad.move(a orelse 0, b orelse 0)
    else if (std.mem.eql(u8, verb, "tap"))
        pad.press(TAP_MS)
    else if (std.mem.eql(u8, verb, "hold"))
        pad.press(HOLD_MS)
    else if (std.mem.eql(u8, verb, "scroll"))
        pad.scroll(a orelse 0)
    else if (std.mem.eql(u8, verb, "quit"))
        return false
    else blk: {
        say("unknown command '{s}'", .{verb});
        break :blk true;
    };
    if (!ok) say("writing to /dev/uinput failed during '{s}'", .{verb});
    return ok;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    _ = init;
    var pad = Pad.create() orelse return 1;
    defer pad.destroy();
    _ = writeAll(1, "tp-replay: ready\n");

    var buf: [512]u8 = undefined;
    var len: usize = 0;
    while (true) {
        if (len == buf.len) len = 0; // 줄이 너무 길면 버린다
        const n = linux.read(0, buf[len..].ptr, buf.len - len);
        switch (linux.errno(n)) {
            .SUCCESS => {},
            .INTR => continue,
            else => return 1,
        }
        if (n == 0) return 0;
        len += n;
        while (std.mem.indexOfScalar(u8, buf[0..len], '\n')) |nl| {
            const keep = run(&pad, buf[0..nl]);
            std.mem.copyForwards(u8, buf[0 .. len - nl - 1], buf[nl + 1 .. len]);
            len -= nl + 1;
            if (!keep) return 0;
        }
    }
}
