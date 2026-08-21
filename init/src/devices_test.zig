const std = @import("std");
const linux = std.os.linux;
const devices = @import("devices.zig");

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
}
