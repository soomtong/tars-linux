const std = @import("std");
const logline = @import("logline.zig");
const screen_args = @import("screen_args");
const config = @import("config.zig");

// BT-M1. 블루투스는 BlueZ의 bluetoothd가 하고, bluetoothd는 D-Bus 시스템 버스 위에
// 선다(BT design 확인 3 · 결정 3). init이 하는 것은 둘을 감독 목록에 넣을지 답하는
// 것 하나다 — wifi.zig의 `wants`와 같은 모양이고, 둘은 한 답을 나눠 갖는다.

/// 감독 목록에 들어가는 것은 데몬이 아니라 래퍼 둘이다(BT design 결정 4). dbus 쪽은
/// 소켓 자리를 만들고 dbus-daemon을 `exec`하고, bluetoothd 쪽은 키가 남을 자리를
/// 만들고 버스를 기다린 뒤 bluetoothd를 `exec`한다 — 그래서 PID 1이 쥔 pid가 곧 데몬이다.
/// 자리가 `kernel/make_initrd.sh`와 같은 글자여야 한다 — 어긋나면 증상이
/// `execve … failed (errno 2)` 하나다.
pub const DBUS_PATH: [:0]const u8 = "/usr/lib/tars/tars-dbus";
pub const BLUETOOTHD_PATH: [:0]const u8 = "/usr/lib/tars/tars-bluetoothd";

pub const DBUS_ARGV = [screen_args.ARGC:null]?[*:0]const u8{ DBUS_PATH.ptr, null, null, null, null, null, null, null, null, null };
pub const BLUETOOTHD_ARGV = [screen_args.ARGC:null]?[*:0]const u8{ BLUETOOTHD_PATH.ptr, null, null, null, null, null, null, null, null, null };

/// 둘을 감독 목록에 넣을지 답한다. 넣지 않을 때도 이유를 한 줄 남긴다 — 침묵은
/// "안 켰다"와 "켜려다 실패했다"를 못 가른다(DS 결정 1).
///
/// `bluetooth=off`(기본값)면 안 넣는다. 라디오를 켜는 것은 이 기계를 쓰는 사람이
/// 정한다(BT design 결정 5, `net`과 같은 근거).
///
/// `/config`가 안 붙었으면 안 넣는다. 페어링 키가 남을 자리가 없어 재부팅마다 다시
/// 페어링해야 한다 — 그것은 "되는데 안 된다"다. 키가 `on`이면 `/config`는 보통 붙어
/// 있지만 `tars.noconfig`의 길이 있어 따로 본다.
pub fn wants(bt: config.Bluetooth, mounted: bool) bool {
    if (bt == .off) {
        logline.print("tars-init: bluetooth=off, bluetooth stays off\n", .{});
        return false;
    }
    if (!mounted) {
        logline.print("tars-init: no /config, bluetooth stays off\n", .{});
        return false;
    }
    // 감독자의 `started service dbus (pid N, …)` · `started service bluetoothd (pid N, …)`가 뒤따른다.
    logline.print("tars-init: dbus and bluetoothd join the services, keys live in /config/bluetooth\n", .{});
    return true;
}
