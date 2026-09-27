const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");

/// net.zig · clock.zig와 같은 세 줄짜리 헬퍼다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// nft가 사는 자리. guest_tools.sh의 층 10이 usr/sbin/nft를 여기로 넣는다.
const NFT_PATH: [:0]const u8 = "/usr/bin/nft";
/// make_initrd.sh가 굽는 둘(design 결정 3 · 5).
const RULES_PATH: [:0]const u8 = "/etc/tars/firewall.nft";
const BASE_PATH: [:0]const u8 = "/etc/tars/firewall-base.nft";

/// `nft -f path`를 돌리고 끝나기를 기다린다. 0으로 끝났으면 true다.
///
/// 기다리는 것이 dhcpcd · chronyd와 다른 점이다(design 확인 3). nft는 로컬
/// netlink만 쓰므로 네트워크를 기다리지 않고, 규칙이 서기 전에 주소가 붙는
/// 틈을 없애려면 끝을 봐야 한다. 이 자리에는 SIGCHLD 핸들러가 없고 자식을
/// 거두는 것은 뒤의 감독 루프뿐이라, wait4(pid)가 남에게 뺏기지 않는다.
///
/// nft의 stderr는 따로 안 잡는다. init의 fd 2가 콘솔이라 자식이 그대로
/// 물려받고, 사람의 파일이 틀렸으면 nft가 파일 · 행 · 열을 짚는 그 글자가
/// 콘솔에 그대로 나온다(FW-M0 실측 8).
fn load(path: [:0]const u8, envp: [*:null]const ?[*:0]const u8) bool {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for nft (errno {d})\n", .{@intFromEnum(e)});
        return false;
    }
    if (pid == 0) {
        // 부모의 SIGTERM · SIGINT 핸들러는 execve가 기본값으로 되돌린다. clock.zig가
        // power.resetToDefault()를 부르는 것은 execve 전에 우리 코드가 오래
        // 돌기 때문이고, 이 자식은 곧바로 execve한다.
        const argv = [_:null]?[*:0]const u8{ NFT_PATH.ptr, "-f", path.ptr, null };
        _ = linux.execve(NFT_PATH.ptr, &argv, envp);
        std.debug.print("tars-init: cannot exec {s}\n", .{NFT_PATH});
        linux.exit(127);
    }

    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), &status, 0, null);
        if (failed(rc)) |e| {
            // SA_RESTART가 꺼져 있어(power.zig) 전원 버튼이 이 기다림을 깨운다.
            // 플래그는 이미 섰고 감독 루프가 곧 본다 — 여기서는 다시 기다린다.
            if (e == .INTR) continue;
            std.debug.print("tars-init: waiting for nft failed (errno {d})\n", .{@intFromEnum(e)});
            return false;
        }
        break;
    }
    if (linux.W.IFEXITED(status) and linux.W.EXITSTATUS(status) == 0) return true;
    if (linux.W.IFEXITED(status)) {
        std.debug.print("tars-init: nft -f {s} exited {d}\n", .{ path, linux.W.EXITSTATUS(status) });
    } else {
        std.debug.print("tars-init: nft -f {s} was killed (signal {d})\n", .{
            path, @intFromEnum(linux.W.TERMSIG(status)),
        });
    }
    return false;
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나이고,
/// dhcpcd가 뜨기 전이어야 한다(design 결정 5). DS-M1부터 dhcpcd는 `supervise`의
/// 첫 바퀴에 뜨므로 `main()`에서 그보다 앞이면 된다.
///
/// 갈래는 `off`까지 넷이고 각각 한 줄을 남긴다. 게이트가 grep하는 것이 이
/// 넷의 앞머리(`tars-init: firewall`)다.
///   off  — nft를 안 부른다
///   1    — 기본 규칙 + 사람의 파일이 섰다
///   2    — 사람의 파일 때문에 1이 실패해서 기본 규칙만 섰다. 닫혀 있다
///   3    — 기본 규칙도 실패했다(nft가 없다 · 커널 옵션이 모자라다). 열려 있다.
///          네트워크를 막는 쪽으로 가지 않는 이유는 design 결정 5의 셋째 항목
pub fn up(want: config.Firewall, envp: [*:null]const ?[*:0]const u8) void {
    if (want == .off) {
        std.debug.print("tars-init: firewall=off, inbound is open\n", .{});
        return;
    }
    if (load(RULES_PATH, envp)) {
        std.debug.print("tars-init: firewall up from {s}, inbound closed but for /config/nftables.d\n", .{RULES_PATH});
        return;
    }
    if (load(BASE_PATH, envp)) {
        std.debug.print("tars-init: firewall up from {s} without /config/nftables.d (nft said why above)\n", .{BASE_PATH});
        return;
    }
    std.debug.print("tars-init: firewall NOT up, inbound is open\n", .{});
}
