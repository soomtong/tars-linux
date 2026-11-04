//! KK-M0의 게이트 전용 Apple 대역 키보드 `kk-apple`(KK design 결정 7, 확인 3).
//!
//! QEMU의 `usb-kbd`는 vendor를 바꿀 수 없어서 게이트에 Apple 키보드가 없다. 이
//! 도구가 `/dev/uinput`으로 vendor 0x05ac(Apple)인 USB 키보드 하나를 만들고, 정해진
//! 키를 스스로 친 뒤 장치를 없앤다. 커널의 입력 core가 진짜 드라이버의 이벤트와
//! 같은 길로 evdev 노드에 내보내므로, terminal은 이 장치를 부팅 뒤에 꽂힌 키보드로
//! 본다 — uevent로 알고, `EVIOCGID`로 vendor를 읽는다(M1부터).
//!
//! 치는 것: `echo mm nn`, 왼쪽 Alt를 쥔 채 ←, Shift를 쥔 채 `x`, Enter.
//! 이 키보드가 `apple`로 읽히면 Alt+←는 Option+←(단어 이동)라 줄이 `echo mm Xnn`이고,
//! `pc`로 읽히면 Cmd+←(줄 처음)라 `Xecho mm nn`이다.
//!
//! stdin으로 명령을 안 받는다(`tp-replay`와 다른 점). 이 도구가 친 키는 terminal을
//! 거쳐 패널의 전경 프로세스에 간다 — 도구가 전경이면 자기가 친 키를 자기가 받는다.
//! 그래서 셸에서 `&`로 띄우고, 셸이 전경으로 남아 그 키를 읽는다.
//!
//! 이름에 `Apple`을 안 넣는다. terminal의 판정은 이름을 안 본다(design 결정 2) —
//! 이름으로 고르는 잘못된 구현이 이 장치로 초록이 되지 않게.
//!
//! 제품 initrd에는 없다. input 체인이 빌드해 1차 부팅 디스크의 `kk/kk-apple`로
//! 싣고 게스트 셸에서 친다.
const std = @import("std");
const linux = std.os.linux;

// linux/uinput.h의 요청 번호. 값과 그 유도는 pointer/replay/main.zig와 같다
// (PD-M3 plan 확정 7이 컨테이너의 헤더를 C로 컴파일해 대조했다).
const UI_DEV_CREATE: u32 = 0x5501;
const UI_DEV_DESTROY: u32 = 0x5502;
const UI_DEV_SETUP: u32 = 0x405c5503;
const UI_SET_EVBIT: u32 = 0x40045564;
const UI_SET_KEYBIT: u32 = 0x40045565;

// linux/input-event-codes.h · linux/input.h의 값.
const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const SYN_REPORT: u16 = 0;
const BUS_USB: u16 = 0x03;
const KEY_ENTER: u16 = 28;
const KEY_LEFTSHIFT: u16 = 42;
const KEY_X: u16 = 45;
const KEY_LEFTALT: u16 = 56;
const KEY_SPACE: u16 = 57;
const KEY_LEFT: u16 = 105;
const KEY_E: u16 = 18;
const KEY_C: u16 = 46;
const KEY_H: u16 = 35;
const KEY_O: u16 = 24;
const KEY_M: u16 = 50;
const KEY_N: u16 = 49;

/// Apple의 USB vendor(KK design 확인 2). product는 아무 값이다.
const VENDOR_APPLE: u16 = 0x05ac;
const PRODUCT: u16 = 0x0250;
const NAME = "TARS KK Keyboard";

/// 켜는 키 비트의 끝(포함). terminal의 키보드 판정(`KEY_ESC` ~ `KEY_D`, KH 결정 2)과
/// 이 도구가 치는 키(`KEY_LEFT` = 105)를 다 덮는다. `EV_REP`는 안 켠다 — 커널 자동
/// 반복이 쥔 Alt · Shift를 되풀이하면 판정이 흔들린다(DM 실측 1).
const KEY_LAST: u16 = 127;

/// 장치를 만든 뒤 terminal이 uevent로 노드를 열 때까지 쉬는 시간(design 위험 2).
const OPEN_WAIT_MS: u64 = 1000;
/// 키 하나의 누름과 뗌 사이, 그리고 다음 키 앞에 쉬는 시간.
const KEY_MS: u64 = 10;
/// 다 친 뒤 장치를 없애기 전에 쉬는 시간. 마지막 뗌을 terminal이 읽게 둔다.
const TAIL_MS: u64 = 500;

const InputId = extern struct { bustype: u16, vendor: u16, product: u16, version: u16 };
const DevSetup = extern struct { id: InputId, name: [80]u8, ff_effects_max: u32 };
/// `struct input_event`. x86_64에서 시각은 `long` 둘이다. uinput은 쓰는 쪽의
/// 시각을 버리고 커널이 다시 찍는다.
const Event = extern struct { sec: i64 = 0, usec: i64 = 0, type: u16, code: u16, value: i32 };

comptime {
    std.debug.assert(@sizeOf(DevSetup) == 92);
    std.debug.assert(@sizeOf(Event) == 24);
}

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
    const text = std.fmt.bufPrint(&buf, "kk-apple: " ++ fmt ++ "\n", args) catch return;
    _ = writeAll(2, text);
}

fn sleepMs(ms: u64) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

fn ioctl(fd: i32, request: u32, arg: usize) bool {
    return linux.errno(linux.ioctl(fd, request, arg)) == .SUCCESS;
}

const Keyboard = struct {
    fd: i32,

    fn create() ?Keyboard {
        const rc = linux.open("/dev/uinput", .{ .ACCMODE = .WRONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
        if (linux.errno(rc) != .SUCCESS) {
            say("cannot open /dev/uinput (errno {d})", .{@backingInt(linux.errno(rc))});
            return null;
        }
        const fd: i32 = @intCast(rc);
        var ok = ioctl(fd, UI_SET_EVBIT, EV_KEY);
        var k: u16 = 1;
        while (k <= KEY_LAST) : (k += 1) {
            ok = ok and ioctl(fd, UI_SET_KEYBIT, k);
        }
        var setup: DevSetup = .{
            .id = .{ .bustype = BUS_USB, .vendor = VENDOR_APPLE, .product = PRODUCT, .version = 1 },
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

    fn destroy(self: *Keyboard) void {
        _ = ioctl(self.fd, UI_DEV_DESTROY, 0);
        _ = linux.close(self.fd);
    }

    /// 키 하나의 상태 바꿈(1 = 누름, 0 = 뗌)을 `SYN_REPORT`와 함께 쓰고 쉰다.
    fn set(self: *Keyboard, code: u16, value: i32) bool {
        const evs = [_]Event{
            .{ .type = EV_KEY, .code = code, .value = value },
            .{ .type = EV_SYN, .code = SYN_REPORT, .value = 0 },
        };
        const ok = writeAll(self.fd, std.mem.sliceAsBytes(&evs));
        sleepMs(KEY_MS);
        return ok;
    }

    fn tap(self: *Keyboard, code: u16) bool {
        return self.set(code, 1) and self.set(code, 0);
    }

    /// `held`를 쥔 채 `code`를 누르고 뗀다.
    fn chord(self: *Keyboard, held: u16, code: u16) bool {
        return self.set(held, 1) and self.tap(code) and self.set(held, 0);
    }
};

/// `echo mm nn`
const LINE = [_]u16{ KEY_E, KEY_C, KEY_H, KEY_O, KEY_SPACE, KEY_M, KEY_M, KEY_SPACE, KEY_N, KEY_N };

fn typeAll(kbd: *Keyboard) bool {
    for (LINE) |code| {
        if (!kbd.tap(code)) return false;
    }
    return kbd.chord(KEY_LEFTALT, KEY_LEFT) and
        kbd.chord(KEY_LEFTSHIFT, KEY_X) and
        kbd.tap(KEY_ENTER);
}

pub fn main(init: std.process.Init.Minimal) u8 {
    _ = init;
    var kbd = Keyboard.create() orelse return 1;
    defer kbd.destroy();
    // 친 뒤에는 아무것도 안 찍는다 — 출력이 패널에 섞이면 화면 판정이 흔들린다.
    // 이 한 줄은 키보다 앞이라 셸의 `[1] PID` 줄 근처에 남을 뿐이다.
    say("ready", .{});
    sleepMs(OPEN_WAIT_MS);
    if (!typeAll(&kbd)) {
        say("writing to /dev/uinput failed", .{});
        return 1;
    }
    sleepMs(TAIL_MS);
    return 0;
}
