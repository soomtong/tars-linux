const std = @import("std");
const linux = std.os.linux;
const devices = @import("devices.zig");

/// 이 검사가 만드는 가짜 트리의 뿌리. 게스트가 아니라 빌드 컨테이너의
/// /tmp에 만든다.
const ROOT = "/tmp/tars-devices-test";
const FULL = ROOT ++ "/full";
const BUTTON = ROOT ++ "/button";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 경로를 조립하는 버퍼. 돌려준 슬라이스는 **다음 호출에서 덮인다** —
/// 아래 호출들이 전부 만들자마자 바로 쓰기 때문에 이것으로 충분하다.
var path_buf: [256]u8 = undefined;

fn join(comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const text = std.fmt.bufPrint(path_buf[0 .. path_buf.len - 1], fmt, args) catch unreachable;
    path_buf[text.len] = 0;
    return path_buf[0..text.len :0];
}

/// 있으면 그냥 넘어간다. 검사를 두 번 돌려도 같은 결과가 나와야 한다.
fn mkdirOne(path: [:0]const u8) !void {
    const rc = linux.mkdir(path.ptr, 0o755);
    if (failed(rc)) |e| {
        if (e == .EXIST) return;
        std.debug.print("FAIL: mkdir {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.MkdirFailed;
    }
}

fn writeFile(path: [:0]const u8, text: []const u8) !void {
    const rc = linux.open(path.ptr, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: create {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.OpenFailed;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var written: usize = 0;
    while (written < text.len) {
        const n = linux.write(fd, text.ptr + written, text.len - written);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("FAIL: write {s} (errno {d})\n", .{ path, @intFromEnum(e) });
            return error.WriteFailed;
        }
        if (n == 0) return error.WriteFailed;
        written += n;
    }
}

/// 진짜 sysfs에서 device는 심볼릭 링크지만 여기서는 그냥 디렉터리로 만든다.
/// 우리가 하는 일은 그 아래의 파일을 열어 읽는 것뿐이라 결과가 같다.
fn makeDevice(
    root: []const u8,
    n: u8,
    name: []const u8,
    ev: []const u8,
    key: []const u8,
) !void {
    try mkdirOne(join("{s}/event{d}", .{ root, n }));
    try mkdirOne(join("{s}/event{d}/device", .{ root, n }));
    try mkdirOne(join("{s}/event{d}/device/capabilities", .{ root, n }));
    try writeFile(join("{s}/event{d}/device/name", .{ root, n }), name);
    try writeFile(join("{s}/event{d}/device/capabilities/ev", .{ root, n }), ev);
    try writeFile(join("{s}/event{d}/device/capabilities/key", .{ root, n }), key);
}

/// config_test·power_test와 같은 모양이다: 호스트 아키텍처 실행 파일이고,
/// 실패하면 0이 아닌 종료 코드로 끝난다. 체인 스크립트가 셋을 똑같이 다룰
/// 수 있어야 한다.
pub fn main() !void {
    // ── 1. 워드의 방향 ────────────────────────────────────────────────
    //
    // 이 파일에서 가장 중요한 두 줄이다. sysfs는 가장 높은 워드를 맨 앞에
    // 찍으므로(drivers/input/input.c의 input_print_bitmap), "1 0"은 워드가
    // 둘이고 **뒤엣것이 0번 워드**다. 따라서 64번 비트가 서 있고 0번 비트는
    // 비어 있다. 방향을 뒤집어 읽으면 정확히 반대로 나오는데, 그래도 아래
    // 검사들이 대부분 통과해 버리기 때문에 여기서 못 잡으면 못 잡는다.
    if (!devices.bitSet("1 0", 64)) {
        std.debug.print("FAIL: bit 64 of \"1 0\" should be set (words run high to low)\n", .{});
        return error.WordOrderReversed;
    }
    if (devices.bitSet("1 0", 0)) {
        std.debug.print("FAIL: bit 0 of \"1 0\" should be clear (words run high to low)\n", .{});
        return error.WordOrderReversed;
    }

    // ── 2. 워드가 모자란 경우 ─────────────────────────────────────────
    //
    // 커널은 비어 있는 상위 워드를 아예 안 찍는다. 그래서 물어본 비트가
    // 찍힌 워드 수를 넘어가면 그 비트는 "서 있지 않다"가 정답이다. 전원
    // 버튼의 ev가 "3" 한 워드뿐이라 이 경로를 실제로 밟는다.
    if (devices.bitSet("3", 116)) {
        std.debug.print("FAIL: \"3\" has one word, bit 116 cannot be set\n", .{});
        return error.MissingWordNotHandled;
    }

    // ── 3. 실제 값으로 읽어 본다 ──────────────────────────────────────
    //
    // EV_KEY는 1번이다. 0번은 EV_SYN이고, 그것은 거의 모든 장치가 갖고
    // 있어서 판정에 쓸 수 없다.
    if (!devices.bitSet("3", 1)) {
        std.debug.print("FAIL: \"3\" should have EV_KEY (bit 1)\n", .{});
        return error.BitNotFound;
    }
    // KEY_POWER는 116번이라 1번 워드의 52번 비트다. 0x10000000000000이
    // 정확히 1<<52이고, 그것이 QEMU의 전원 버튼이 내놓는 값이다.
    if (!devices.bitSet("10000000000000 0", 116)) {
        std.debug.print("FAIL: KEY_POWER (116) should be set\n", .{});
        return error.BitNotFound;
    }
    // 같은 장치에 KEY_A(30)는 없다. 전원 버튼이 키보드로 오인되지 않는
    // 근거가 이것이다.
    if (devices.bitSet("10000000000000 0", 30)) {
        std.debug.print("FAIL: KEY_A (30) should not be set on a power button\n", .{});
        return error.UnexpectedBit;
    }

    std.debug.print("devices_test: bitmap words are read from the tail end\n", .{});

    // ── 4. capability 판정 ────────────────────────────────────────────
    //
    // QEMU의 AT 키보드가 실제로 내놓는 값이다. 마지막 워드
    // 0xfffffffffffffffe에 1~63번 비트가 전부 서 있어서 KEY_ESC(1)부터
    // KEY_D(32)까지의 조건을 채운다.
    const keyboard_key = "402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe";
    if (!devices.looksLikeKeyboard("120013", keyboard_key)) {
        std.debug.print("FAIL: the AT keyboard should look like a keyboard\n", .{});
        return error.KeyboardNotRecognized;
    }
    // 전원 버튼은 EV_KEY를 갖고 있다. 그래서 ev만 보면 키보드와 구별되지
    // 않고, KEY_ESC~KEY_D 범위를 요구하는 것이 유일한 구분선이다.
    if (devices.looksLikeKeyboard("3", "10000000000000 0")) {
        std.debug.print("FAIL: a power button must not pass as a keyboard\n", .{});
        return error.PowerButtonMisread;
    }
    // ev를 실제로 본다는 증거. 키는 완전한 키보드인데 EV_KEY가 없으면
    // 통과하면 안 된다.
    if (devices.looksLikeKeyboard("0", keyboard_key)) {
        std.debug.print("FAIL: a device without EV_KEY must not pass\n", .{});
        return error.EvBitmapIgnored;
    }

    std.debug.print("devices_test: capability decides, not the name\n", .{});

    // ── 5. 가짜 sysfs 트리 ────────────────────────────────────────────
    //
    // 진짜 /sys를 읽지 않는 이유는 design 결정 5다. 이 검사는 빌드
    // 컨테이너에서 도는데, 그 안의 /sys는 개발 기계의 것이라 무엇이 꽂혀
    // 있느냐에 따라 결과가 달라진다.
    try mkdirOne(ROOT);
    try mkdirOne(FULL);
    try mkdirOne(BUTTON);

    // 값 셋 다 sysfs가 실제로 주는 모양이다 — 줄 끝의 개행까지 포함한다.
    // 개행을 빼고 검사하면 tokenize가 그것을 걸러 준다는 사실을 못 보게 된다.
    try makeDevice(FULL, 0, "Power Button\n", "3\n", "10000000000000 0\n");
    try makeDevice(FULL, 1, "AT Translated Set 2 keyboard\n", "120013\n",
        "402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe\n");
    // BTN_LEFT(0x110 = 272)만 가진 장치. EV_KEY는 있지만 키보드는 아니다.
    try makeDevice(FULL, 2, "TARS fake mouse\n", "3\n", "10000 0 0 0 0\n");

    const found = devices.findKeyboard(FULL) orelse {
        std.debug.print("FAIL: no keyboard found in the fake tree\n", .{});
        return error.KeyboardNotFound;
    };
    if (found != 1) {
        std.debug.print("FAIL: picked event{d}, want event1\n", .{found});
        return error.WrongDevicePicked;
    }

    // 순서가 중요하다. event0(전원 버튼)이 먼저 오는데도 event1을 골랐다는
    // 것은 번호가 아니라 성질로 판단했다는 뜻이다. ACPI를 켜면 실제로 이
    // 배치가 된다(design 조사 5).
    std.debug.print("devices_test: picked event1 past a power button at event0\n", .{});

    // ── 6. 키보드가 하나도 없으면 ─────────────────────────────────────
    try makeDevice(BUTTON, 0, "Power Button\n", "3\n", "10000000000000 0\n");
    if (devices.findKeyboard(BUTTON) != null) {
        std.debug.print("FAIL: a lone power button was reported as a keyboard\n", .{});
        return error.PowerButtonMisread;
    }

    // ── 7. 폴백은 부팅을 막지 않는다 (design 결정 6) ──────────────────
    var fallback = devices.Path{};
    devices.resolveKeyboard(BUTTON, &fallback);
    if (!std.mem.eql(u8, fallback.slice(), "/dev/input/event0")) {
        std.debug.print("FAIL: fallback gave '{s}', want /dev/input/event0\n", .{
            fallback.slice(),
        });
        return error.WrongFallback;
    }

    var resolved = devices.Path{};
    devices.resolveKeyboard(FULL, &resolved);
    if (!std.mem.eql(u8, resolved.slice(), "/dev/input/event1")) {
        std.debug.print("FAIL: resolved '{s}', want /dev/input/event1\n", .{
            resolved.slice(),
        });
        return error.WrongPath;
    }

    std.debug.print("devices_test: a missing keyboard falls back to event0\n", .{});

    // ── 8. 전원 버튼 판정 (HD-M2) ─────────────────────────────────────
    //
    // **이 절의 첫 두 줄이 HD-M2에서 가장 중요한 검사다.** QEMU의 AT
    // 키보드도 KEY_POWER를 갖고 있다 — 위 keyboard_key의 1번 워드
    // 0xfeffffdfffefffff의 52번 비트가 그것이다. atkbd가 ACPI 확장 키를
    // 스캔코드 표에 갖고 있기 때문이고, 실 하드웨어의 USB 키보드도 대개
    // 같다. 그래서 "KEY_POWER가 서 있는 장치"를 그대로 후보로 삼으면
    // 키보드가 딸려 들어오고, PID 1이 글자 하나마다 깨어나게 된다.
    if (!devices.bitSet(keyboard_key, 116)) {
        std.debug.print("FAIL: the AT keyboard is expected to have KEY_POWER\n", .{});
        return error.KeyboardLostPowerKey;
    }
    if (devices.looksLikePowerButton("120013", keyboard_key)) {
        std.debug.print("FAIL: a keyboard must not pass as a power button\n", .{});
        return error.KeyboardMisreadAsButton;
    }
    // 진짜 전원 버튼은 통과해야 한다.
    if (!devices.looksLikePowerButton("3", "10000000000000 0")) {
        std.debug.print("FAIL: the ACPI power button should look like one\n", .{});
        return error.PowerButtonNotRecognized;
    }
    // BTN_LEFT만 가진 장치는 KEY_POWER가 없으므로 통과하면 안 된다.
    if (devices.looksLikePowerButton("3", "10000 0 0 0 0")) {
        std.debug.print("FAIL: a mouse must not pass as a power button\n", .{});
        return error.MouseMisreadAsButton;
    }

    std.debug.print("devices_test: a keyboard has KEY_POWER but is not a button\n", .{});

    // ── 9. 가짜 트리에서 후보를 고른다 ────────────────────────────────
    //
    // FULL에는 전원 버튼(event0) · 키보드(event1) · 마우스(event2)가 있다.
    // 골라야 할 것은 event0 하나뿐이다. 키보드가 함께 나오면 위 8번이
    // 잡지 못한 무언가가 findPowerButtons에 있다는 뜻이다.
    var buttons: [devices.MAX_BUTTONS]u8 = undefined;
    const count = devices.findPowerButtons(FULL, &buttons);
    if (count != 1) {
        std.debug.print("FAIL: found {d} power buttons in the fake tree, want 1\n", .{count});
        return error.WrongButtonCount;
    }
    if (buttons[0] != 0) {
        std.debug.print("FAIL: picked event{d} as the power button, want event0\n", .{buttons[0]});
        return error.WrongButtonPicked;
    }

    // 전원 버튼만 있는 트리에서도 같은 답이 나와야 한다.
    const lone = devices.findPowerButtons(BUTTON, &buttons);
    if (lone != 1 or buttons[0] != 0) {
        std.debug.print("FAIL: a lone power button was not found (count {d})\n", .{lone});
        return error.ButtonNotFound;
    }

    std.debug.print("devices_test: picked the power button and left the keyboard alone\n", .{});
}
