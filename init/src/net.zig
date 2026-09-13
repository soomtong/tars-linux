const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");

/// config.zig·main.zig와 같은 세 줄짜리 헬퍼다. 넷째 자리라 슬슬 sys.zig로
/// 모을 때가 됐지만, 이 milestone에서 하지 않는다 — 파일 넷을 한꺼번에
/// 건드리는 변경과 새 층을 세우는 변경을 같은 커밋에 섞지 않는다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 이 기계가 쓰는 인터페이스 이름(NW-M2 결정 D).
///
/// 상수인 이유는 init에 libc도 힙도 없기 때문이다. `/sys/class/net`을 훑어
/// `lo`가 아닌 첫 장치를 고르려면 `getdents64`를 직접 다뤄야 하는데,
/// `devices.zig`가 evdev에 대해 그것을 피하려고 event0부터 서른둘을 열어
/// 보고 있다. 그쪽은 이름이 번호라서 그 수법이 섰고 여기는 안 선다.
///
/// 지금 필요한 이름이 하나뿐인 근거는 커널에 있다 — 켠 NIC 드라이버가
/// CONFIG_VIRTIO_NET 하나다(M1 실측 13). 실머신 NIC는 design 비목표 1이고,
/// 그것이 들어오는 날 이 상수가 디렉터리 순회로 바뀐다.
pub const IFACE: []const u8 = "eth0";

/// 장치가 있는지 먼저 묻는 자리. sysfs는 커널이 드라이버를 붙이면서 직접
/// 만든다(M1 실측 14) — 이 경로가 없으면 드라이버가 안 붙은 것이고,
/// 있는데 ioctl이 실패하면 다른 실패다. 두 실패가 로그에서 갈리는 것이
/// 이 한 번의 open이 하는 일 전부다.
const SYS_IFACE: [:0]const u8 = "/sys/class/net/eth0";

/// include/uapi/linux/sockios.h. 이름이 아니라 숫자로 적는 이유는 Zig의
/// linux 바인딩에 이 상수가 없기 때문이고, 커널 ABI라 안 바뀐다.
const SIOCGIFFLAGS: u32 = 0x8913;
const SIOCSIFFLAGS: u32 = 0x8914;

/// include/uapi/linux/if.h. IFF_UP 하나만 세운다 — IFF_RUNNING은 커널이
/// 링크 상태를 보고 자기가 세우는 것이라 우리가 쓰면 거짓말이 된다.
const IFF_UP: u16 = 0x1;

/// include/uapi/linux/if.h의 struct ifreq.
///
/// 이름 16바이트 뒤에 오는 것은 union이고 그중 가장 큰 것이 struct
/// sockaddr(16바이트)이다. 그래서 전체가 32바이트다. flags는 그 union의
/// 첫 2바이트를 빌려 쓰는 것이고, 나머지 14바이트는 커널이 안 보지만
/// 구조체 크기가 맞아야 한다.
const ifreq = extern struct {
    name: [16]u8,
    flags: u16,
    _pad: [14]u8,
};

// 크기가 틀리면 게스트에서 `ioctl`이 EINVAL을 내는 것으로만 드러난다.
// 그 실패는 부팅한 뒤에야 보이고 원인에서 멀다 — 컴파일 타임에 못 박는다.
// config.zig의 `TOGGLE_ARG_MAX` 아래에 같은 모양의 블록이 하나 더 있다.
comptime {
    if (@sizeOf(ifreq) != 32)
        @compileError("struct ifreq must be 32 bytes to match the kernel ABI");
}

/// dhcpcd가 사는 자리. guest_tools.sh가 usr/sbin/dhcpcd를 여기로 넣는다 —
/// PATH가 /usr/bin:/bin이라 /usr/sbin은 이름으로 안 닿는다(M0 실측 8).
/// 그 파일의 오른쪽과 이 상수가 어긋나면 증상이 execve 실패 하나뿐이다.
const DHCPCD_PATH: [:0]const u8 = "/usr/bin/dhcpcd";

/// `/sys/class/net/eth0`이 있는가.
fn ifacePresent() bool {
    const rc = linux.open(SYS_IFACE.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
    if (failed(rc) != null) return false;
    _ = linux.close(@intCast(rc));
    return true;
}

/// 링크를 UP으로 올린다. 성공하면 true.
///
/// 읽고-고쳐-쓰는 이유는 flags가 비트 묶음이기 때문이다. SIOCSIFFLAGS는
/// 통째로 덮어쓰므로 IFF_UP만 담아 보내면 커널이 세워 둔 다른 비트를
/// 지우게 된다.
fn linkUp() bool {
    // 주소를 다루는 ioctl이라 소켓이 필요하다. 어느 소켓이든 되지만
    // AF_INET/SOCK_DGRAM이 관습이고, 이 커널에 INET이 있다(design 결정 2).
    const srv = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(srv)) |e| {
        std.debug.print("tars-init: cannot open a socket to bring {s} up (errno {d})\n", .{
            IFACE, @intFromEnum(e),
        });
        return false;
    }
    const fd: i32 = @intCast(srv);
    defer _ = linux.close(fd);

    var req = ifreq{ .name = [_]u8{0} ** 16, .flags = 0, ._pad = [_]u8{0} ** 14 };
    @memcpy(req.name[0..IFACE.len], IFACE);

    if (failed(linux.ioctl(fd, SIOCGIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot read the flags of {s} (errno {d})\n", .{
            IFACE, @intFromEnum(e),
        });
        return false;
    }
    if (req.flags & IFF_UP != 0) {
        std.debug.print("tars-init: {s} was already up\n", .{IFACE});
        return true;
    }

    req.flags |= IFF_UP;
    if (failed(linux.ioctl(fd, SIOCSIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot bring {s} up (errno {d})\n", .{
            IFACE, @intFromEnum(e),
        });
        return false;
    }
    // net/check.sh가 이 줄을 grep한다.
    std.debug.print("tars-init: net link {s} is up\n", .{IFACE});
    return true;
}

/// dhcpcd를 띄운다. 감독 목록에 안 넣는다(design 결정 9의 갈래 A).
///
/// 근거가 M0의 실측 4다. dhcpcd는 주소를 받으면 `forked to background`를
/// 찍고 배경으로 내려가는데, 그러면 부모가 죽으면서 PID 1에 재부모화된다
/// (`tars-init: reaped orphan pid 119`). 즉 감독 목록에 없어도 이미 init의
/// 자식이고 `reapAll()`이 그것을 센다. 그리고 SIGTERM에 죽으므로 SL-M2가
/// 세운 `grace period expired` 판정에 안 걸린다.
///
/// envp를 받는 것이 중요하다(결정 F). dhcpcd가 주소를 받으면 hook을 부르고
/// 그 hook이 sed·rm·cat을 이름으로 부른다 — PATH가 없으면 주소는 붙는데
/// /etc/resolv.conf만 안 생긴다. 그래서 이 함수는 main()에서 env 블록이
/// 지어진 뒤에 불려야 한다.
fn startDhcpcd(envp: [*:null]const ?[*:0]const u8) void {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for dhcpcd (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{ DHCPCD_PATH.ptr, "eth0", null };
        _ = linux.execve(DHCPCD_PATH.ptr, &argv, envp);
        // 여기 닿았다는 것은 execve가 실패했다는 뜻이다.
        std.debug.print("tars-init: cannot exec {s}\n", .{DHCPCD_PATH});
        linux.exit(127);
    }
    // net/check.sh가 이 줄을 grep한다.
    std.debug.print("tars-init: started dhcpcd on {s} (pid {d})\n", .{ IFACE, pid });
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나다.
///
/// `off`일 때 아무 말도 안 하지 않는다. 침묵은 "안 켰다"와 "켜려다 실패했다"를
/// 못 가르고, 이 저장소가 그 값을 여러 번 지불했다.
pub fn bringUp(want: config.Net, envp: [*:null]const ?[*:0]const u8) void {
    if (want == .off) {
        std.debug.print("tars-init: net=off, leaving the network alone\n", .{});
        return;
    }
    if (!ifacePresent()) {
        std.debug.print("tars-init: net=dhcp but there is no {s} under /sys/class/net\n", .{
            IFACE,
        });
        return;
    }
    if (!linkUp()) return;
    startDhcpcd(envp);
}
