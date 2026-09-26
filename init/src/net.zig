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
const DHCPCD_PATH: [:0]const u8 = "/usr/bin/dhcpcd";

/// dhcpcd를 띄운다. 감독 목록에 안 넣는다(design 결정 9의 갈래 A).
///
/// 근거가 M0의 실측 4다. dhcpcd는 주소를 받으면 `forked to background`를
/// 찍고 배경으로 내려가는데, 그러면 부모가 죽으면서 PID 1에 재부모화된다
/// (`tars-init: reaped orphan pid 119`). 즉 감독 목록에 없어도 이미 init의
/// 자식이고 `reapAll()`이 그것을 센다. 그리고 SIGTERM에 죽으므로 SL-M2가
/// 세운 `grace period expired` 판정에 안 걸린다.
///
/// WN-M2부터는 배경으로 가는 시점이 주소를 받기 전이다(WN design 실측 12).
/// 인터페이스 이름을 안 주므로 manager mode로 돌기 때문이다. 재부모화되어
/// init의 자식으로 남는다는 것은 그대로다.
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
        // `-o ntp_servers`가 TS design 위험 3의 처방이다(TS-M0 실측 8).
        // dhcpcd의 요청 목록은 /etc/dhcpcd.conf와 컴파일 타임 기본값에서
        // 오는데, sysroot의 그 파일에 `option ntp_servers`가 있고
        // make_initrd.sh가 그 파일을 initrd에 안 넣는다. 파일을 넣는 대신
        // 한 단어를 여기 적는다 — 그 파일에는 우리가 고른 적 없는 줄이
        // 서른 넘게 들어 있어서, 넣으면 무엇이 왜 켜졌는지가 흐려진다.
        //
        // 옵션 이름을 dhcpcd가 파일 없이 아는 것을 sysroot에서 확인했다 —
        // /usr/share/dhcpcd에 정의 파일이 없고 바이너리 안에
        // `define 42 array ipaddress ntp_servers`가 박혀 있다. 이것이
        // 아니었다면 증상이 "주소가 안 붙는다"로 나와서 원인에서 멀다.
        //
        // 이 단어가 뜻을 갖는 것은 실기계에서뿐이다. 게이트의 SLIRP는
        // option 42를 영영 안 주므로(TS 확인 5) 있든 없든 게이트의 답이
        // 같고, 그래서 TS-M2는 그 간극을 hook과 파일로 잘라서 증명한다.
        //
        // `-j /dev/console`은 WN-M2가 더했다(design 실측 12 · 13). 인터페이스
        // 이름을 주지 않으면 dhcpcd는 manager mode로 돌고, lease를 받기 전에
        // 배경으로 간다. 배경으로 간 뒤의 로그는 syslog로 가는데 게스트에는
        // syslog가 없다 — 주소는 붙는데 `leased` 줄은 어디에도 안 남는다.
        // 로그 파일을 콘솔로 주면 모든 줄이 `Sep 26 11:07:33 [78]: ` 머리를
        // 달고 시리얼에 나온다. 배경으로 가기 전 세 줄만 stderr와 파일로 두 번
        // 찍힌다.
        //
        // `-b`는 안 붙인다(실측 14). manager mode가 이미 곧바로 배경으로 가고,
        // 인터페이스가 하나도 없어도 끝나지 않고 기다린다.
        const argv = [_:null]?[*:0]const u8{
            DHCPCD_PATH.ptr, "-j", "/dev/console", "-o", "ntp_servers", null,
        };
        _ = linux.execve(DHCPCD_PATH.ptr, &argv, envp);
        // 여기 닿았다는 것은 execve가 실패했다는 뜻이다.
        std.debug.print("tars-init: cannot exec {s}\n", .{DHCPCD_PATH});
        linux.exit(127);
    }
    // net/check.sh의 검사 4가 이 줄을 grep한다.
    std.debug.print("tars-init: started dhcpcd (pid {d}), it picks the interface\n", .{pid});
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나다.
///
/// `off`일 때 아무 말도 안 하지 않는다. 침묵은 "안 켰다"와 "켜려다 실패했다"를
/// 못 가르고, 이 저장소가 그 값을 여러 번 지불했다.
///
/// `dhcp`이면 NIC가 있는지 안 묻고 띄운다(WN design 결정 6). 없으면 dhcpcd가
/// `no valid interfaces found`를 찍고 살아서 기다리다가, 나중에 꽂힌 USB
/// 동글을 잡는다(실측 14). 부팅은 그동안 평소대로 끝난다 — dhcpcd는 감독
/// 목록 밖에서 fork되고 init은 기다리지 않는다.
pub fn bringUp(want: config.Net, envp: [*:null]const ?[*:0]const u8) void {
    if (want == .off) {
        std.debug.print("tars-init: net=off, leaving the network alone\n", .{});
        return;
    }
    startDhcpcd(envp);
}
