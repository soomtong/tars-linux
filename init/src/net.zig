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

// LB-M1. `lo`를 올린다(LB design 결정 1~4). 아래 상수 둘과 `ifreq`는 NW-M1이
// `eth0`을 올리려고 넣었다가 WN-M2가 지운 것(`1acf9f6`)을 그대로 되살린 것이다.
// 그때 그 일은 dhcpcd에게 갔지만 dhcpcd는 `lo`를 안 만진다(WN design 덤).

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
comptime {
    if (@sizeOf(ifreq) != 32)
        @compileError("struct ifreq must be 32 bytes to match the kernel ABI");
}

/// `lo`를 UP으로 올린다. 주소는 안 붙인다 — 커널이 `IFF_UP`을 보고
/// `127.0.0.1/8`을 스스로 붙인다(LB-M0 실측 3).
///
/// `net` 설정을 안 받는다. loopback은 기계 밖으로 나가는 길이 아니라 기계
/// 안의 길이라 `net=off`와 다른 층이고(결정 1), `main()`이 설정을 읽기 전에
/// 부르는 것으로 그것을 구조가 보장한다(결정 3).
///
/// 읽고-고쳐-쓰는 이유는 flags가 비트 묶음이기 때문이다. SIOCSIFFLAGS는
/// 통째로 덮어쓰므로 IFF_UP만 담아 보내면 커널이 세워 둔 다른 비트
/// (`lo`에서는 IFF_LOOPBACK)를 지우게 된다.
///
/// 실패해도 부팅을 안 막는다(결정 4). 그때 사라지는 것은 기계 안의
/// `127.0.0.1`뿐이고, 못 올린 이유는 단계마다 다른 줄로 남는다.
pub fn loopbackUp() void {
    // 인터페이스 ioctl에는 소켓이 필요하다. 어느 소켓이든 되지만
    // AF_INET/SOCK_DGRAM이 관습이다. 여기서 실패하면 커널에 INET이 없다.
    const srv = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(srv)) |e| {
        std.debug.print("tars-init: cannot open a socket to raise lo (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    const fd: i32 = @intCast(srv);
    defer _ = linux.close(fd);

    var req = ifreq{ .name = [_]u8{0} ** 16, .flags = 0, ._pad = [_]u8{0} ** 14 };
    @memcpy(req.name[0..2], "lo");

    if (failed(linux.ioctl(fd, SIOCGIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot read the flags of lo (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    if (req.flags & IFF_UP != 0) {
        std.debug.print("tars-init: lo was already up\n", .{});
        return;
    }

    req.flags |= IFF_UP;
    if (failed(linux.ioctl(fd, SIOCSIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot raise lo (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    // LB-M3의 검사가 이 줄을 grep한다.
    std.debug.print("tars-init: lo up\n", .{});
}

// WN-M2. 여기에 있던 것 — 인터페이스 이름 상수 `eth0`, `/sys/class/net/eth0`을
// 열어 보는 확인, `SIOCGIFFLAGS` · `SIOCSIFFLAGS`로 `IFF_UP`을 세우는 ioctl과 그
// `struct ifreq` — 을 전부 뺐다. 인터페이스를 고르고 올리는 일이 dhcpcd에게
// 갔다(WN design 결정 4). 인자 없는 dhcpcd가 `lo`가 아닌 인터페이스를 스스로
// 찾아 올리고(실측 3), 부팅 뒤에 생긴 장치도 udev 없이 잡는다(실측 6 · 14).
// TD가 시계에 대해 한 것과 같은 방향이다 — 어려운 일은 그 일을 하는 도구가
// 하고 init은 배관만 한다.

/// dhcpcd가 사는 자리. guest_tools.sh가 usr/sbin/dhcpcd를 여기로 넣는다 —
/// PATH가 /usr/bin:/bin이라 /usr/sbin은 이름으로 안 닿는다(M0 실측 8).
/// 그 파일의 오른쪽과 이 상수가 어긋나면 증상이 execve 실패 하나뿐이다.
pub const DHCPCD_PATH: [:0]const u8 = "/usr/bin/dhcpcd";

/// DS 결정 M1-B. 감독 목록에 들어가는 dhcpcd의 argv. 타입이 main.zig의
/// `Child.argv`와 같다.
///
/// `-B`는 DS design 결정 2다. 인터페이스 이름 없이 도는 manager mode는 lease 전에
/// 배경으로 가는데(WN design 실측 12), 그러면 PID 1이 쥔 pid는 곧 죽고 일은
/// 손자가 한다. `-B`면 쥔 pid가 곧 dhcpcd이고, 인터페이스가 없어도 기다리다가
/// 나중에 꽂힌 동글을 잡는 성질은 그대로다(DS-M0 실측 1 · 7).
///
/// `-j /dev/console`은 남긴다(DS-M0 실측 2). `-B`에서는 stderr만으로 모든 줄이
/// 콘솔에 와서 줄이 두 벌이 되지만, `-j`의 줄머리 `[pid]`로 nic 체인이 "같은
/// dhcpcd가 동글을 잡았다"를 가른다.
///
/// `-o ntp_servers`가 TS design 위험 3의 처방이다(TS-M0 실측 8). dhcpcd의 요청
/// 목록은 /etc/dhcpcd.conf와 컴파일 타임 기본값에서 오는데, make_initrd.sh가 그
/// 파일을 initrd에 안 넣는다 — 그 파일에는 우리가 고른 적 없는 줄이 서른 넘게
/// 들어 있다. 옵션 이름을 dhcpcd가 파일 없이 안다 — 바이너리 안에
/// `define 42 array ipaddress ntp_servers`가 박혀 있다. 게이트의 SLIRP는 option
/// 42를 영영 안 주므로(TS 확인 5) 이 단어가 뜻을 갖는 것은 실기계에서뿐이다.
///
/// `-b`는 안 붙인다(WN 실측 14).
pub const DHCPCD_ARGV = [8:null]?[*:0]const u8{
    DHCPCD_PATH.ptr, "-B", "-j", "/dev/console", "-o", "ntp_servers", null, null,
};

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나다.
///
/// dhcpcd를 감독 목록에 넣을지를 답한다(DS design 결정 1). 띄우는 것은
/// `supervise`의 첫 바퀴다 — 그때는 방화벽이 이미 서 있다(FW 결정 5).
///
/// `off`일 때 아무 말도 안 하지 않는다. 침묵은 "안 켰다"와 "켜려다 실패했다"를
/// 못 가르고, 이 저장소가 그 값을 여러 번 지불했다.
///
/// `dhcp`이면 NIC가 있는지 안 묻는다(WN design 결정 6). 없으면 dhcpcd가
/// `no valid interfaces found`를 찍고 살아서 기다리다가, 나중에 꽂힌 USB
/// 동글을 잡는다(WN 실측 14 · DS-M0 실측 7). 부팅은 그동안 평소대로 끝난다.
///
/// envp는 감독자가 넘긴다. dhcpcd가 주소를 받으면 hook을 부르고 그 hook이
/// sed·rm·mv·chronyc를 이름으로 부른다(NW 결정 F) — PATH가 없으면 주소는
/// 붙는데 /etc/resolv.conf만 안 생긴다.
pub fn wantsDhcpcd(want: config.Net) bool {
    if (want == .off) {
        std.debug.print("tars-init: net=off, leaving the network alone\n", .{});
        return false;
    }
    // DS 결정 M1-C. 감독자의 `started service dhcpcd (pid N, …)`가 뒤따른다.
    std.debug.print("tars-init: dhcpcd joins the services, it picks the interface\n", .{});
    return true;
}
