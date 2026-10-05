const std = @import("std");
const pointer = @import("pointer.zig");
const c = pointer.c;

/// `/proc/bus/input/devices`의 `B:` 줄(높은 워드가 앞, 워드는 64비트)을
/// ioctl이 채우는 모양(낮은 바이트부터)으로 바꾼다.
///
/// 검사 데이터를 게스트에서 본 글자 그대로 적기 위한 것이다(PD-M0 plan
/// 확정 6). 두 형식이 반대 순서라는 것이 design 결정 2의 요점이고, 이 함수가
/// 그 변환을 한 자리에서 한다 — 틀리면 검사 2가 잡는다.
fn fromSysfs(comptime n: usize, comptime text: []const u8) [n]u8 {
    @setEvalBranchQuota(10_000);
    var out: [n]u8 = @splat(0);
    var words: [16]u64 = undefined;
    var count: usize = 0;
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    while (it.next()) |w| : (count += 1) {
        words[count] = std.fmt.parseInt(u64, w, 16) catch unreachable;
    }
    // 마지막 워드가 워드 0이다.
    for (0..count) |i| {
        const word = words[count - 1 - i];
        for (0..8) |b| {
            const at = i * 8 + b;
            if (at < n) out[at] = @truncate(word >> @intCast(b * 8));
        }
    }
    return out;
}

/// 게스트의 `B:` 줄 다섯으로 `Caps`를 만든다. 없는 줄은 `"0"`이다.
fn caps(
    comptime prop: []const u8,
    comptime ev: []const u8,
    comptime key: []const u8,
    comptime rel: []const u8,
    comptime abs: []const u8,
) pointer.Caps {
    const z: pointer.Caps = .{};
    return .{
        .prop = fromSysfs(z.prop.len, prop),
        .ev = fromSysfs(z.ev.len, ev),
        .key = fromSysfs(z.key.len, key),
        .rel = fromSysfs(z.rel.len, rel),
        .abs = fromSysfs(z.abs.len, abs),
    };
}

fn expectKind(what: []const u8, got: pointer.Kind, want: pointer.Kind) !void {
    if (got == want) {
        std.debug.print("pointer_test: {s} is {s} OK\n", .{ what, @tagName(got) });
        return;
    }
    std.debug.print("FAIL: {s} classified as {s}, want {s}\n", .{ what, @tagName(got), @tagName(want) });
    return error.WrongKind;
}

fn expectTrue(what: []const u8, ok: bool) !void {
    if (ok) {
        std.debug.print("pointer_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s}\n", .{what});
    return error.CheckFailed;
}

fn expectNum(what: []const u8, got: u64, want: u64) !void {
    if (got == want) {
        std.debug.print("pointer_test: {s} = 0x{x} OK\n", .{ what, got });
        return;
    }
    std.debug.print("FAIL: {s} = 0x{x}, want 0x{x}\n", .{ what, got, want });
    return error.WrongNumber;
}

fn expectFrame(what: []const u8, got: ?pointer.Frame, want: ?pointer.Frame) !void {
    if (std.meta.eql(got, want)) {
        std.debug.print("pointer_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s}: got {any}, want {any}\n", .{ what, got, want });
    return error.WrongFrame;
}

fn expectAt(what: []const u8, p: *const pointer.Pointer, x: u32, y: u32) !void {
    if (p.x == x and p.y == y) {
        std.debug.print("pointer_test: {s} at {d},{d} OK\n", .{ what, x, y });
        return;
    }
    std.debug.print("FAIL: {s}: at {d},{d}, want {d},{d}\n", .{ what, p.x, p.y, x, y });
    return error.WrongPosition;
}

/// 마우스 디코더에 이벤트 하나를 먹이고 결과를 돌려준다. 검사를 이벤트
/// 목록처럼 읽히게 하려는 것이다.
fn feed(m: *pointer.Mouse, ev_type: anytype, code: anytype, value: i32) ?pointer.Frame {
    return m.feed(@intCast(ev_type), @intCast(code), value);
}

/// 포인터 장치의 분류 · 디코더 · 좌표를 본다. 부팅도 fd도 안 쓴다(PD design
/// 결정 3). 게이트(`pointer/check.sh`)가 빨개졌을 때 어느 층인지 가르는 자리다.
pub fn main() !void {
    // ── 검사 1: ioctl 비트맵은 낮은 번호부터다 ─────────────────────────
    {
        const map = [_]u8{ 0b0000_0011, 0b1000_0000 };
        try expectTrue("bit 0 and 1 in byte 0", pointer.bitSet(&map, 0) and pointer.bitSet(&map, 1));
        try expectTrue("bit 2 is clear", !pointer.bitSet(&map, 2));
        try expectTrue("bit 15 is the top of byte 1", pointer.bitSet(&map, 15));
        try expectTrue("bit 16 is past the map", !pointer.bitSet(&map, 16));
    }

    // ── 검사 2: 게스트의 B: 줄을 바꾼 결과 ───────────────────────────
    //
    // USB 마우스의 `KEY=1f0000 0 0 0 0`은 워드 4의 비트 16~20이다 —
    // 4 × 64 + 16 = 0x110 = BTN_LEFT부터 다섯(BTN_EXTRA 0x114까지).
    {
        const key = fromSysfs((pointer.Caps{}).key.len, "1f0000 0 0 0 0");
        try expectTrue("mouse KEY has BTN_LEFT", pointer.bitSet(&key, c.BTN_LEFT));
        try expectTrue("mouse KEY has BTN_EXTRA (0x114)", pointer.bitSet(&key, 0x114));
        try expectTrue("mouse KEY lacks 0x115", !pointer.bitSet(&key, 0x115));
        try expectTrue("mouse KEY lacks KEY_A", !pointer.bitSet(&key, c.KEY_A));
    }

    // ── 검사 3: 게스트에서 본 장치 넷(PD-M0 plan 확정 6) ─────────────
    //
    // 2026-10-05, `-usb -device usb-mouse -device usb-tablet`으로 뜬 게스트의
    // `/proc/bus/input/devices`. 글자 그대로다.
    try expectKind("Power Button", pointer.classify(&caps("0", "3", "8000 10000000000000 0", "0", "0")), .none);
    try expectKind("AT Translated Set 2 keyboard", pointer.classify(&caps(
        "0",
        "120013",
        "402000007 ff803078f800d001 feffffdfffcfffff fffffffffffffffe",
        "0",
        "0",
    )), .none);
    try expectKind("QEMU QEMU USB Mouse", pointer.classify(&caps("0", "17", "1f0000 0 0 0 0", "903", "0")), .mouse);
    try expectKind("QEMU QEMU USB Tablet", pointer.classify(&caps("0", "1f", "70000 0 0 0 0", "900", "3")), .none);

    // ── 검사 4: 게스트에 없는 장치(흔한 값, 실측 아님) ─────────────────
    //
    // PS/2 Synaptics 터치패드: PROP=5(POINTER · BUTTONPAD), ABS에 X · Y ·
    // PRESSURE · TOOL_WIDTH · MT_SLOT · MT_POSITION_X/Y · TRACKING_ID ·
    // MT_PRESSURE, KEY에 BTN_LEFT · BTN_TOOL_FINGER · BTN_TOUCH · TOOL_*TAP.
    try expectKind("Synaptics touchpad", pointer.classify(&caps(
        "5",
        "b",
        "e520 10000 0 0 0 0",
        "0",
        "660800011000003",
    )), .touchpad);
    // PROP가 0이어도 BTN_TOOL_FINGER가 있으면 터치패드다(design 결정 2의 "또는").
    try expectKind("touchpad without INPUT_PROP_POINTER", pointer.classify(&caps(
        "0",
        "b",
        "e520 10000 0 0 0 0",
        "0",
        "660800011000003",
    )), .touchpad);
    // 터치스크린: PROP=2(DIRECT). ABS_MT가 있어도 none이다(비목표 4).
    try expectKind("touchscreen", pointer.classify(&caps("2", "b", "400 0 0 0 0 0", "0", "260800000000003")), .none);
    // TrackPoint: PROP=21(POINTER · POINTING_STICK)이지만 ABS가 없다 — 마우스다.
    try expectKind("TrackPoint", pointer.classify(&caps("21", "7", "70000 0 0 0 0", "3", "0")), .mouse);

    // ── 검사 5: ioctl 요청 번호 ───────────────────────────────────────
    //
    // 오른쪽은 컨테이너의 `/usr/include/linux/input.h`를 C로 컴파일해 찍은
    // 값이다(PD-M0 plan 확정 4). x86_64와 aarch64가 같은 `asm-generic/ioctl.h`
    // 배치를 쓴다.
    {
        const z: pointer.Caps = .{};
        try expectNum("EVIOCGBIT(0, 4)", pointer.eviocgbit(0, z.ev.len), 0x80044520);
        try expectNum("EVIOCGBIT(EV_KEY, 96)", pointer.eviocgbit(c.EV_KEY, z.key.len), 0x80604521);
        try expectNum("EVIOCGBIT(EV_REL, 2)", pointer.eviocgbit(c.EV_REL, z.rel.len), 0x80024522);
        try expectNum("EVIOCGBIT(EV_ABS, 8)", pointer.eviocgbit(c.EV_ABS, z.abs.len), 0x80084523);
        try expectNum("EVIOCGPROP(4)", pointer.eviocgprop(z.prop.len), 0x80044509);
        try expectNum("EVIOCGNAME(64)", pointer.eviocgname(64), 0x80404506);
        try expectNum("EVIOCGABS(ABS_MT_POSITION_X)", pointer.eviocgabs(c.ABS_MT_POSITION_X), 0x80184575);
    }

    // ── 검사 6: 디코더는 SYN_REPORT에 한 Frame을 낸다 ──────────────────
    //
    // 이벤트의 순서는 게스트에서 읽은 바이트 그대로다(PD design 실측 2).
    {
        var m: pointer.Mouse = .{};
        try expectFrame("REL_X 10 is held until SYN", feed(&m, c.EV_REL, c.REL_X, 10), null);
        _ = feed(&m, c.EV_REL, c.REL_Y, 5);
        try expectFrame("mouse_move 10 5", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .dx = 10, .dy = 5 });

        _ = feed(&m, c.EV_MSC, c.MSC_SCAN, 0x90001);
        _ = feed(&m, c.EV_KEY, c.BTN_LEFT, 1);
        try expectFrame("mouse_button 1", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .buttons = .{ .left = true } });
        // 버튼은 보고를 넘어 유지된다.
        _ = feed(&m, c.EV_REL, c.REL_X, 1);
        try expectFrame("a move keeps the held button", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .dx = 1, .buttons = .{ .left = true } });
        _ = feed(&m, c.EV_MSC, c.MSC_SCAN, 0x90001);
        _ = feed(&m, c.EV_KEY, c.BTN_LEFT, 0);
        try expectFrame("mouse_button 0", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{});

        // 커널은 고해상도 휠을 함께 낸다. 그것을 세면 휠이 두 번 움직인다.
        _ = feed(&m, c.EV_REL, c.REL_WHEEL, 1);
        _ = feed(&m, c.EV_REL, c.REL_WHEEL_HI_RES, 120);
        try expectFrame("mouse_move 0 0 1 drops REL_WHEEL_HI_RES", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .wheel = 1 });

        // 오른쪽 · 가운데는 상태만 든다. 키 코드와 BTN_SIDE는 버린다.
        _ = feed(&m, c.EV_KEY, c.BTN_RIGHT, 1);
        _ = feed(&m, c.EV_KEY, c.BTN_MIDDLE, 1);
        _ = feed(&m, c.EV_KEY, c.BTN_SIDE, 1);
        _ = feed(&m, c.EV_KEY, c.KEY_A, 1);
        try expectFrame("right and middle, no KEY_A or BTN_SIDE", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .buttons = .{ .right = true, .middle = true } });
        _ = feed(&m, c.EV_KEY, c.BTN_RIGHT, 0);
        _ = feed(&m, c.EV_KEY, c.BTN_MIDDLE, 0);
        _ = feed(&m, c.EV_SYN, c.SYN_REPORT, 0);
    }

    // ── 검사 7: QEMU가 쪼갠 큰 이동은 보고 셋이다(plan 확정 2) ─────────
    {
        var m: pointer.Mouse = .{};
        var sum: i32 = 0;
        var frames: usize = 0;
        for ([_]i32{ 127, 127, 46 }) |dx| {
            _ = feed(&m, c.EV_REL, c.REL_X, dx);
            if (feed(&m, c.EV_SYN, c.SYN_REPORT, 0)) |f| {
                sum += f.dx;
                frames += 1;
            }
        }
        try expectTrue("mouse_move 300 0 arrives as three frames summing to 300", frames == 3 and sum == 300);
    }

    // ── 검사 8: SYN_DROPPED 뒤에는 다음 SYN_REPORT까지 버린다 ─────────
    {
        var m: pointer.Mouse = .{};
        _ = feed(&m, c.EV_REL, c.REL_X, 7);
        try expectFrame("SYN_DROPPED itself", feed(&m, c.EV_SYN, c.SYN_DROPPED, 0), null);
        _ = feed(&m, c.EV_REL, c.REL_X, 3);
        try expectFrame("the report after SYN_DROPPED is dropped", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), null);
        _ = feed(&m, c.EV_REL, c.REL_X, 2);
        try expectFrame("the next report is whole again", feed(&m, c.EV_SYN, c.SYN_REPORT, 0), .{ .dx = 2 });
    }

    // ── 검사 9: 좌표는 가운데에서 출발하고 화면 안에 머문다 ─────────────
    //
    // 게이트의 프레임버퍼는 1280 × 800이다. 체인 검사 2 · 5가 같은 수를 본다.
    {
        var p = pointer.Pointer.init(1280, 800);
        try expectAt("start", &p, 640, 400);
        const e = p.apply(0, .{ .dx = 10, .dy = 5 });
        try expectAt("after 10,5", &p, 650, 405);
        try expectTrue("a move is a move", e.moved and e.wheel == 0);
        _ = p.apply(0, .{ .dx = -2000, .dy = -2000 });
        try expectAt("clamped to the top left", &p, 0, 0);
        _ = p.apply(0, .{ .dx = 5000, .dy = 5000 });
        try expectAt("clamped to the bottom right", &p, 1279, 799);
        const w = p.apply(0, .{ .wheel = -1 });
        try expectTrue("a wheel frame is not a move", !w.moved and w.wheel == -1);
        _ = p.apply(0, .{ .dx = std.math.minInt(i32), .dy = std.math.maxInt(i32) });
        try expectAt("extreme deltas do not overflow", &p, 0, 799);
    }

    // ── 검사 10: 버튼은 장치별로 들고 합이 바뀔 때만 눌림 · 뗌이 나온다 ──
    //
    // 마우스로 누른 채 다른 장치로 눌렀다 떼도 뗌이 한 번이다(design 결정 3).
    {
        var p = pointer.Pointer.init(1280, 800);
        const left: pointer.Buttons = .{ .left = true };
        var e = p.apply(0, .{ .buttons = left });
        try expectTrue("device 0 presses left", e.pressed.left and !e.released.left and p.buttons.left);
        e = p.apply(1, .{ .buttons = left });
        try expectTrue("device 1 pressing too is not a second press", !e.pressed.left);
        e = p.apply(0, .{});
        try expectTrue("device 0 lets go, device 1 still holds", !e.released.left and p.buttons.left);
        e = p.apply(1, .{});
        try expectTrue("the last one lets go: one release", e.released.left and !p.buttons.left);

        _ = p.apply(2, .{ .buttons = .{ .right = true } });
        e = p.forget(2);
        try expectTrue("a device pulled while holding releases its button", e.released.right and p.buttons.bits() == 0);
        try expectTrue("bits follow QEMU mouse_button (1 left, 2 right, 4 middle)", (pointer.Buttons{ .left = true }).bits() == 1 and
            (pointer.Buttons{ .right = true }).bits() == 2 and (pointer.Buttons{ .middle = true }).bits() == 4);
    }

    // ── 검사 11: uevent에서 새 evdev 노드만 고른다 ─────────────────────────
    //
    // 앞의 넷은 2026-10-05 `pointer` 체인의 `device_add` · `device_del`이 낸
    // uevent 그대로다(PD-M0 plan 확정 7, NUL이 필드 사이와 끝에 있다). 뒤의
    // 둘은 같은 모양으로 만든 것이다 — 노드 없는 `inputN`의 `add`와, 이
    // 커널에서는 안 오는 `mouseN`.
    {
        const add_event3 = "add@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00ACTION=add\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00SUBSYSTEM=input\x00MAJOR=13\x00MINOR=67\x00DEVNAME=input/event3\x00SEQNUM=686\x00";
        const remove_event3 = "remove@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00ACTION=remove\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4/event3\x00SUBSYSTEM=input\x00MAJOR=13\x00MINOR=67\x00DEVNAME=input/event3\x00SEQNUM=690\x00";
        const remove_input4 = "remove@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4\x00ACTION=remove\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1/1-2.1:1.0/0003:0627:0001.0002/input/input4\x00SUBSYSTEM=input\x00PRODUCT=3/627/1/1\x00NAME=\"QEMU QEMU USB Mouse\"\x00PROP=0\x00EV=17\x00KEY=1f0000 0 0 0 0\x00REL=903\x00MSC=10\x00SEQNUM=691\x00";
        const bind_usb = "bind@/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1\x00ACTION=bind\x00DEVPATH=/devices/pci0000:00/0000:00:01.2/usb1/1-2/1-2.1\x00SUBSYSTEM=usb\x00MAJOR=189\x00MINOR=3\x00DEVNAME=bus/usb/001/004\x00DEVTYPE=usb_device\x00DRIVER=usb\x00SEQNUM=689\x00";
        const add_input4 = "add@/devices/virtual/input/input4\x00ACTION=add\x00SUBSYSTEM=input\x00NAME=\"QEMU QEMU USB Mouse\"\x00SEQNUM=685\x00";
        const add_mouse0 = "add@/devices/virtual/input/input4/mouse0\x00ACTION=add\x00SUBSYSTEM=input\x00DEVNAME=input/mouse0\x00SEQNUM=687\x00";
        const got = pointer.ueventAddedNode(add_event3);
        try expectTrue("uevent add of input/event3 names event3", got != null and std.mem.eql(u8, got.?, "event3"));
        try expectTrue("uevent remove of the same node is ignored", pointer.ueventAddedNode(remove_event3) == null);
        try expectTrue("uevent remove of inputN (no node) is ignored", pointer.ueventAddedNode(remove_input4) == null);
        try expectTrue("uevent of a usb device node is ignored", pointer.ueventAddedNode(bind_usb) == null);
        try expectTrue("uevent add of inputN (no DEVNAME) is ignored", pointer.ueventAddedNode(add_input4) == null);
        try expectTrue("uevent add of input/mouse0 is ignored", pointer.ueventAddedNode(add_mouse0) == null);
    }

    std.debug.print("pointer_test: all checks passed\n", .{});
}
