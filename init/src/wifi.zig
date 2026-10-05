const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");

// WL-M2. 무선은 wpa_supplicant가 붙이고 주소는 dhcpcd가 받는다(WL design 결정 4).
// init이 하는 것은 wpa_supplicant를 감독 목록에 넣을지 답하는 것 하나다. net.zig의
// `wantsDhcpcd`와 같은 모양이다.

/// 사람이 쓰는 파일. wpa_supplicant의 원래 형식 그대로다(사용자가 골랐다).
/// `kernel/wifi/tars-wifi`와 `kernel/dhcpcd-hooks/10-tars-wifi`가 같은 글자를
/// 쓴다 — 셋이 어긋나면 init은 띄우는데 wpa_supplicant가 파일을 못 찾는다.
pub const CONF_PATH: [:0]const u8 = "/config/wpa_supplicant.conf";

/// 감독 목록에 들어가는 것은 wpa_supplicant가 아니라 이 셸 스크립트다. 뜰 때
/// 지금 있는 무선 인터페이스를 세어 argv를 짓고 wpa_supplicant를 `exec`한다 —
/// 그래서 PID 1이 쥔 pid가 곧 wpa_supplicant다(DS design 결정 2의 교훈).
///
/// argv를 여기서 못 짓는 이유는 인터페이스가 부팅마다 · 재시작마다 다르기
/// 때문이다. `Child.argv`는 고정이고, Debian의 wpa_supplicant에는 이름 패턴으로
/// 고르는 `-M`이 없다(WL design 실측 5). 부팅 뒤에 생긴 인터페이스는 dhcpcd의
/// hook이 `interface_add`로 넣는다.
pub const WIFI_PATH: [:0]const u8 = "/usr/lib/tars/tars-wifi";

pub const WIFI_ARGV = [9:null]?[*:0]const u8{ WIFI_PATH.ptr, null, null, null, null, null, null, null, null };

/// wpa_supplicant를 감독 목록에 넣을지 답한다. 넣지 않을 때도 이유를 한 줄
/// 남긴다 — 침묵은 "안 켰다"와 "켜려다 실패했다"를 못 가른다(DS 결정 1).
///
/// `net=off`면 안 넣는다. 주소를 받을 dhcpcd가 없고 늦은 인터페이스를 넣는 hook도
/// 안 돈다 — 연결만 서는 것은 사람이 볼 때 "붙었는데 안 된다"다.
///
/// `/config`가 안 붙었으면 파일이 있을 수 없다. tmpfs의 빈 `/config`에서
/// `access`가 답하는 것과 같지만, 이유가 다르므로 줄을 가른다.
///
/// `conf`를 인자로 받는 것은 wifi_test가 가짜 경로로 부르기 위해서다.
pub fn wants(net: config.Net, mounted: bool, conf: [:0]const u8) bool {
    if (net == .off) {
        std.debug.print("tars-init: net=off, wifi stays off\n", .{});
        return false;
    }
    if (!mounted) {
        std.debug.print("tars-init: no /config, wifi stays off\n", .{});
        return false;
    }
    if (linux.errno(linux.access(conf.ptr, linux.F_OK)) != .SUCCESS) {
        std.debug.print("tars-init: no {s}, wifi stays off\n", .{conf});
        return false;
    }
    // 감독자의 `started service wpa_supplicant (pid N, …)`가 뒤따른다.
    std.debug.print("tars-init: wpa_supplicant joins the services, tars-wifi picks the interfaces\n", .{});
    return true;
}
