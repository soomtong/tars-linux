const std = @import("std");
const logline = @import("logline.zig");
const linux = std.os.linux;
const config = @import("config.zig");

// 시계에 관한 일은 chronyd가 한다(TD design 결정 1). 이 파일이 하는 것은
// 그 chronyd를 띄우기 전의 배관이다 — 갈래를 고르고, 서버를 정하고, 설정
// 파일을 쓴다.
//
// TS의 sntp.zig였다. 패킷을 짓고 읽고 시계를 뛰던 절반을 TD-M1이 지웠고,
// 서버 파일을 기다리던 나머지 절반을 DS-M1이 지웠다. 이제 fork도 없다 —
// chronyd를 띄우고 감독하는 것은 main.zig의 supervise다(DS design 결정 1).

/// config.zig·main.zig·net.zig와 같은 세 줄짜리 헬퍼다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// `renderConf`에 넘길 버퍼의 크기. 가장 긴 모양(`ntp=dhcp`에 `/config`의
/// 두 줄까지)이 114바이트이고, `clock_test`가 그 경우를 직접 본다.
pub const CONF_MAX = 128;

/// `/config`가 붙은 부팅에서 chronyd가 쓰는 두 자리(TD design 결정 5 · 8).
const CONFIG_CONFDIR = "/config/chrony.d";
const CONFIG_DRIFT = "/config/chrony.drift";

/// DS design 결정 3. `ntp=dhcp`일 때 chronyd가 서버를 찾는 디렉터리.
/// kernel/dhcpcd-hooks/30-tars-ntp의 기본값과 같은 글자여야 한다 — 어긋나면
/// chronyd가 서버 0개로 영영 기다리고, 증상은 "시계가 안 맞는다" 하나다.
pub const SOURCES_DIR = "/run/tars/chrony.sources";

/// chronyd의 설정 파일을 짓는다. 시스템 콜이 없는 순수 함수다.
///
/// 언제나 있는 세 줄(TD design 결정 4). 첫 줄이 `server`에 따라 둘로 갈린다.
///   server …  iburst   `ntp=<주소>`. 처음 네 번을 2초 간격으로 묻는다
///   sourcedir …        `ntp=dhcp`(server가 null). dhcpcd의 hook이 이 안에
///                      `server … iburst` 한 줄을 쓰고 chronyc로 알린다
///                      (DS design 결정 3 · DS-M0 실측 5 · 6)
///   makestep 1 3       첫 세 번의 갱신까지는 1초보다 틀리면 뛴다. 이것이
///                      TS가 하던 부팅 점프다. chrony의 기본값은 뛰지 않는
///                      것이라, 이 줄이 없으면 2031년까지 몇 달이 걸린다
///   cmdport 0          UDP 명령 포트를 닫는다. 커널에 IPv6가 없어 매번
///                      `Could not open command socket`이 찍히던 줄이고
///                      (TD-M0 실측 2), chronyc는 unix socket으로 붙는다
///
/// `keep`(= `/config`가 붙었다)일 때 더하는 두 줄(TD-M2).
///   confdir …          맨 앞이다. 같은 서버가 두 번 적히면 먼저 적힌 쪽이
///                      이기므로(TD-M0 실측 9) 사람이 chrony.d에 적은 것이
///                      우리 기본값보다 앞선다. 디렉터리가 없으면 chronyd가
///                      말없이 넘어간다
///   driftfile …        배운 주파수를 끌 때와 한 시간마다 쓰고, 다음 부팅이
///                      그 값에서 출발한다
pub fn renderConf(buf: []u8, server: ?[4]u8, keep: bool) ?[]const u8 {
    const head: []const u8 = if (keep) "confdir " ++ CONFIG_CONFDIR ++ "\n" else "";
    const tail: []const u8 = if (keep) "driftfile " ++ CONFIG_DRIFT ++ "\n" else "";
    if (server) |ip| {
        return std.fmt.bufPrint(buf, "{s}server {d}.{d}.{d}.{d} iburst\nmakestep 1 3\n{s}cmdport 0\n", .{
            head, ip[0], ip[1], ip[2], ip[3], tail,
        }) catch null;
    }
    return std.fmt.bufPrint(buf, "{s}sourcedir " ++ SOURCES_DIR ++ "\nmakestep 1 3\n{s}cmdport 0\n", .{
        head, tail,
    }) catch null;
}

// ── 여기서부터는 시스템 콜을 한다. 위의 하나만 clock_test가 본다 ─────────

/// init이 부팅마다 새로 쓰는 chronyd 설정(TD design 결정 3). `/etc`가 아니라
/// `/run`인 이유가 그것이다.
const CONF_DIR: [:0]const u8 = "/run/tars";
const CONF_PATH: [:0]const u8 = "/run/tars/chrony.conf";

/// chronyd가 사는 자리. guest_tools.sh가 usr/sbin/chronyd를 여기로 넣는다 —
/// dhcpcd와 같은 이유(PATH가 /usr/bin:/bin)로 /usr/sbin을 안 쓴다. 그 파일의
/// 오른쪽과 이 상수가 어긋나면 증상이 `cannot exec` 한 줄뿐이다.
pub const CHRONYD_PATH: [:0]const u8 = "/usr/bin/chronyd";

/// DS 결정 M1-B. 감독 목록에 들어가는 chronyd의 argv. 타입이 main.zig의
/// `Child.argv`와 같다. 인자 넷이 TD design 결정 3이다.
///   -d        갈라지지 않는다. 갈라지면 PID 1이 쥔 pid가 틀린 값이 된다
///   -u root   게스트에 _chrony가 없다
///   -f        설정을 /run에서 읽는다
///   (-F 없음) 커널에 seccomp가 없다
pub const CHRONYD_ARGV = [9:null]?[*:0]const u8{
    CHRONYD_PATH.ptr, "-d", "-u", "root", "-f", CONF_PATH.ptr, null, null, null,
};

/// 설정 파일을 쓴다. 부팅 때 PID 1이 한 번 부른다.
fn writeConf(server: ?[4]u8, keep: bool) bool {
    var buf: [CONF_MAX]u8 = undefined;
    const text = renderConf(&buf, server, keep) orelse {
        logline.print("tars-init: chrony config does not fit in {d} bytes\n", .{CONF_MAX});
        return false;
    };

    // hook보다 먼저 불리므로 /run/tars가 아직 없을 수 있다.
    const mk = linux.mkdir(CONF_DIR.ptr, 0o755);
    if (failed(mk)) |e| {
        if (e != .EXIST) {
            logline.print("tars-init: cannot make {s} (errno {d})\n", .{
                CONF_DIR, @intFromEnum(e),
            });
            return false;
        }
    }

    const rc = linux.open(CONF_PATH.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |e| {
        logline.print("tars-init: cannot open {s} (errno {d})\n", .{
            CONF_PATH, @intFromEnum(e),
        });
        return false;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    const n = linux.write(fd, text.ptr, text.len);
    if (failed(n)) |e| {
        logline.print("tars-init: cannot write {s} (errno {d})\n", .{
            CONF_PATH, @intFromEnum(e),
        });
        return false;
    }
    if (n != text.len) {
        logline.print("tars-init: short write to {s} ({d} of {d})\n", .{
            CONF_PATH, n, text.len,
        });
        return false;
    }
    return true;
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나다.
///
/// chronyd를 감독 목록에 넣을지를 답한다(DS design 결정 1). 넣을 때는 설정
/// 파일을 먼저 쓴다 — 기다리는 것이 없으므로 부모가 써도 부팅을 안 막는다
/// (결정 3). `ntp=dhcp`면 서버는 나중에 hook이 가져온다.
///
/// `net.zig`의 `wantsDhcpcd`와 같은 모양이고 같은 규칙을 따른다 — 안 넣을 때도
/// 로그 한 줄을 남긴다. 침묵은 "안 켰다"와 "켜려다 실패했다"를 못 가른다.
///
/// `keep`은 `/config`가 붙었는가다(`main.zig`의 `storage_mounted`). 붙었을 때만
/// chronyd가 chrony.d를 읽고 driftfile을 쓴다(TD-M2).
pub fn prepare(net: config.Net, want: config.Ntp, keep: bool) bool {
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;

    if (want == .off) {
        logline.print("tars-init: ntp=off, leaving the clock alone\n", .{});
        return false;
    }
    // 네트워크가 꺼져 있으면 주소가 붙을 리 없으므로 chronyd도 없다.
    if (net == .off) {
        logline.print("tars-init: ntp={s} but net=off, leaving the clock alone\n", .{
            want.arg(&ntp_buf),
        });
        return false;
    }

    const server: ?[4]u8 = switch (want) {
        .off => unreachable, // 위에서 돌아갔다
        .dhcp => null,
        .server => |ip| ip,
    };
    if (!writeConf(server, keep)) return false;

    // net/check.sh의 검사 25가 앞의 줄을 grep한다. 뒤의 줄은 설정 디스크가
    // 없는 부팅(ISO로 뜬 설치 세션 등)의 것이고, 침묵 대신 한 줄을 남긴다.
    if (keep) {
        logline.print("tars-init: chronyd keeps its drift in {s}\n", .{CONFIG_DRIFT});
    } else {
        logline.print("tars-init: no /config, chronyd forgets its drift at power-off\n", .{});
    }
    // net/check.sh의 검사 18이 앞의 줄을 grep한다. 뒤의 줄은 DS 결정 M1-C다.
    if (server) |ip| {
        logline.print("tars-init: chronyd will ask {d}.{d}.{d}.{d} ({s})\n", .{
            ip[0], ip[1], ip[2], ip[3], CONF_PATH,
        });
    } else {
        logline.print("tars-init: chronyd will ask whoever dhcpcd names in {s}\n", .{SOURCES_DIR});
    }
    return true;
}
