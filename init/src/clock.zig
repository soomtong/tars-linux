const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const power = @import("power.zig");

// 시계에 관한 일은 chronyd가 한다(TD design 결정 1). 이 파일이 하는 것은
// 그 chronyd를 띄우기까지의 배관이다 — 갈래를 고르고, fork하고, 서버를
// 정하고, 설정 파일을 쓰고, execve한다.
//
// TS의 sntp.zig였다. 패킷을 짓고 읽고 시계를 뛰던 절반을 TD-M1이 지웠고,
// 서버 파일을 기다리는 절반이 글자 그대로 남았다.

/// config.zig·main.zig·net.zig와 같은 세 줄짜리 헬퍼다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// `renderConf`에 넘길 버퍼의 크기. 가장 긴 주소(255.255.255.255)를 넣어도
/// 60바이트이고, `clock_test`가 그 경우를 직접 본다.
pub const CONF_MAX = 128;

/// chronyd의 설정 파일을 짓는다. 시스템 콜이 없는 순수 함수다.
///
/// 세 줄이다(TD design 결정 4).
///   server …  iburst   처음 네 번을 2초 간격으로 묻는다
///   makestep 1 3       첫 세 번의 갱신까지는 1초보다 틀리면 뛴다. 이것이
///                      TS가 하던 부팅 점프다. chrony의 기본값은 뛰지 않는
///                      것이라, 이 줄이 없으면 2031년까지 몇 달이 걸린다
///   cmdport 0          UDP 명령 포트를 닫는다. 커널에 IPv6가 없어 매번
///                      `Could not open command socket`이 찍히던 줄이고
///                      (TD-M0 실측 2), chronyc는 unix socket으로 붙는다
///
/// `confdir`와 `driftfile`은 M2가 더한다.
pub fn renderConf(buf: []u8, server: [4]u8) ?[]const u8 {
    return std.fmt.bufPrint(buf,
        \\server {d}.{d}.{d}.{d} iburst
        \\makestep 1 3
        \\cmdport 0
        \\
    , .{ server[0], server[1], server[2], server[3] }) catch null;
}

/// `/run/tars/ntp_servers`의 내용에서 주소 하나를 꺼낸다. 시스템 콜이 없는
/// 순수 함수다.
///
/// 첫 토큰만 본다(TS design 비목표 2). 여럿이 와도 첫 것만 쓰기로 했으므로,
/// 첫 것이 주소가 아니면 뒤를 뒤지지 않는다 — 뒤지면 "첫 것을 쓴다"가
/// 조용히 "쓸 만한 첫 것을 쓴다"로 바뀌고, 그 둘은 실기에서 다른 서버를
/// 고르게 된다.
pub fn parseServerFile(text: []const u8) ?[4]u8 {
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    const first = it.next() orelse return null;
    return config.parseIpv4(first);
}

// ── 여기서부터는 시스템 콜을 한다. 위의 둘만 clock_test가 본다 ───────────

/// `ntp=dhcp`일 때 파일이 생기기를 기다리는 상한과 간격(TS-M2).
///
/// 30초인 근거는 리스다. 이 파일을 쓰는 것은 dhcpcd의 hook이고 hook은 리스를
/// 받은 뒤에 불리므로, 기다리는 대상이 결국 리스다 — `net/check.sh`의 리스
/// 대기 상한이 60초이고 실제 관측이 10초 안팎이다(TS-M1 실측 10).
///
/// 이 수가 부팅 시간에 영향을 안 준다. 부모는 이미 다음 줄로 갔고, 이
/// 기다림은 자식 안에서만 돈다(TS design 결정 3).
///
/// 기본 경로는 기다리지 않는다. chrony는 주소가 붙기 전에 보내기에 실패한
/// 요청을 `iburst`의 네 번으로 세지 않고, 붙은 뒤에 2초 간격으로 응답을
/// 모아 뛴다 — TD-M1이 기다리는 코드를 넣었다가 반사실로 재 보니 점프가
/// 1초 차이였다(TD design 실측 13).
const FILE_WAIT_TRIES: usize = 60;
const FILE_WAIT_SLEEP_MS: isize = 500;

/// dhcpcd의 hook이 option 42를 적어 두는 자리(TS design 결정 4).
/// kernel/dhcpcd-hooks/30-tars-ntp의 기본값과 같은 글자여야 한다.
const SERVER_FILE: [:0]const u8 = "/run/tars/ntp_servers";

/// init이 부팅마다 새로 쓰는 chronyd 설정(TD design 결정 3). `/etc`가 아니라
/// `/run`인 이유가 그것이다.
const CONF_DIR: [:0]const u8 = "/run/tars";
const CONF_PATH: [:0]const u8 = "/run/tars/chrony.conf";

/// chronyd가 사는 자리. guest_tools.sh가 usr/sbin/chronyd를 여기로 넣는다 —
/// dhcpcd와 같은 이유(PATH가 /usr/bin:/bin)로 /usr/sbin을 안 쓴다. 그 파일의
/// 오른쪽과 이 상수가 어긋나면 증상이 `cannot exec` 한 줄뿐이다.
const CHRONYD_PATH: [:0]const u8 = "/usr/bin/chronyd";

/// devices.zig·power.zig에도 같은 함수가 있다. `failed`와 같은 이유로 공용
/// 모듈을 만들지 않는다.
fn sleepMillis(ms: isize) void {
    const req = linux.timespec{
        .sec = @divTrunc(ms, 1000),
        .nsec = @rem(ms, 1000) * 1_000_000,
    };
    _ = linux.nanosleep(&req, null);
}

/// `ntp=dhcp`일 때 서버를 찾는 자리. 한 번 열어 보고 못 읽으면 null이다.
/// 기다리는 것은 아래 `waitForServerFile`이 한다(TS-M2).
fn serverFromFile() ?[4]u8 {
    const rc = linux.open(SERVER_FILE.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| {
        // ENOENT는 조용히 지나간다. 이 함수는 기다리는 루프 안에서 불리고
        // 그 루프의 정상 상태가 "아직 없다"이기 때문이다 — 안 가리면 같은
        // 줄이 예순 번 찍혀서 정말 이상한 실패(권한 · 마운트)를 덮는다.
        if (e != .NOENT) {
            std.debug.print("tars-init: cannot open {s} (errno {d})\n", .{
                SERVER_FILE, @intFromEnum(e),
            });
        }
        return null;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    // 주소 여럿이 공백으로 이어져 와도 담긴다. 넘치면 잘려서 첫 토큰만
    // 남는데, 어차피 첫 것만 쓴다.
    var buf: [128]u8 = undefined;
    const n = linux.read(fd, &buf, buf.len);
    if (failed(n)) |e| {
        std.debug.print("tars-init: cannot read {s} (errno {d})\n", .{
            SERVER_FILE, @intFromEnum(e),
        });
        return null;
    }
    const ip = parseServerFile(buf[0..n]) orelse {
        std.debug.print("tars-init: {s} has no address we can read\n", .{SERVER_FILE});
        return null;
    };
    // net/check.sh의 부팅 B가 이 줄을 grep한다. 주소까지 함께 보므로 형식을
    // 바꾸는 사람은 그 체인도 같이 본다.
    std.debug.print("tars-init: ntp server {d}.{d}.{d}.{d} came from {s}\n", .{
        ip[0], ip[1], ip[2], ip[3], SERVER_FILE,
    });
    return ip;
}

/// 파일이 생길 때까지 기다린다. 자식 안에서만 불린다(TS-M2 결정 M2-A).
///
/// 왜 inotify가 아닌가. init에 libc도 힙도 없으므로 `inotify_add_watch`를
/// 직접 다뤄야 하고, 그러면 "디렉터리가 아직 없을 때"를 또 다뤄야 한다 —
/// `/run/tars`를 만드는 것도 hook이다. 0.5초마다 열어 보는 쪽이 코드가
/// 절반이고 최악의 손해가 0.5초다.
fn waitForServerFile() ?[4]u8 {
    std.debug.print("tars-init: ntp=dhcp, waiting for {s}\n", .{SERVER_FILE});
    var tries: usize = 0;
    while (tries < FILE_WAIT_TRIES) : (tries += 1) {
        if (serverFromFile()) |ip| return ip;
        sleepMillis(FILE_WAIT_SLEEP_MS);
    }
    // 실기계에서 이 줄이 뜻하는 것은 "DHCP 서버가 option 42를 안 준다"이고,
    // 그것이 TS design 위험 3이 게이트로 영영 못 가리는 바로 그 상태다.
    std.debug.print("tars-init: gave up waiting for {s}\n", .{SERVER_FILE});
    return null;
}

/// 설정 파일을 쓴다. 자식 안에서만 불린다.
fn writeConf(server: [4]u8) bool {
    var buf: [CONF_MAX]u8 = undefined;
    const text = renderConf(&buf, server) orelse {
        std.debug.print("tars-init: chrony config does not fit in {d} bytes\n", .{CONF_MAX});
        return false;
    };

    // `ntp=<주소>`면 hook이 안 돌아서 /run/tars가 없을 수 있다.
    const mk = linux.mkdir(CONF_DIR.ptr, 0o755);
    if (failed(mk)) |e| {
        if (e != .EXIST) {
            std.debug.print("tars-init: cannot make {s} (errno {d})\n", .{
                CONF_DIR, @intFromEnum(e),
            });
            return false;
        }
    }

    const rc = linux.open(CONF_PATH.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: cannot open {s} (errno {d})\n", .{
            CONF_PATH, @intFromEnum(e),
        });
        return false;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    const n = linux.write(fd, text.ptr, text.len);
    if (failed(n)) |e| {
        std.debug.print("tars-init: cannot write {s} (errno {d})\n", .{
            CONF_PATH, @intFromEnum(e),
        });
        return false;
    }
    if (n != text.len) {
        std.debug.print("tars-init: short write to {s} ({d} of {d})\n", .{
            CONF_PATH, n, text.len,
        });
        return false;
    }
    return true;
}

/// 자기 자신을 chronyd로 바꾼다. pid가 그대로라 부모가 찍은 pid가 곧
/// chronyd이고, 종료 때의 SIGTERM이 그대로 닿는다(TD design 확인 2).
///
/// 인자 넷이 TD design 결정 3이다.
///   -d        갈라지지 않는다. 갈라지면 PID 1이 모르는 고아가 생긴다
///   -u root   게스트에 _chrony가 없다
///   -f        설정을 /run에서 읽는다
///   (-F 없음) 커널에 seccomp가 없다
fn execChronyd(envp: [*:null]const ?[*:0]const u8) noreturn {
    const argv = [_:null]?[*:0]const u8{
        CHRONYD_PATH.ptr, "-d", "-u", "root", "-f", CONF_PATH.ptr, null,
    };
    _ = linux.execve(CHRONYD_PATH.ptr, &argv, envp);
    // 여기 닿았다는 것은 execve가 실패했다는 뜻이다.
    std.debug.print("tars-init: cannot exec {s}\n", .{CHRONYD_PATH});
    linux.exit(127);
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나다.
///
/// `net.zig`의 `bringUp`과 같은 모양이고 같은 규칙을 따른다 — `off`일 때도
/// 로그 한 줄을 남긴다. 침묵은 "안 켰다"와 "켜려다 실패했다"를 못 가른다.
///
/// envp를 받는 이유는 execve다. chronyd가 PATH를 쓰지는 않지만 TZ를 비롯한
/// 블록이 셸과 같아야 로그를 읽는 사람이 헷갈리지 않는다.
pub fn start(net: config.Net, want: config.Ntp, envp: [*:null]const ?[*:0]const u8) void {
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;

    if (want == .off) {
        std.debug.print("tars-init: ntp=off, leaving the clock alone\n", .{});
        return;
    }
    // `net`을 먼저 본다. 네트워크가 꺼져 있으면 주소가 붙을 리 없으므로
    // fork도 chronyd도 없다.
    if (net == .off) {
        std.debug.print("tars-init: ntp={s} but net=off, leaving the clock alone\n", .{
            want.arg(&ntp_buf),
        });
        return;
    }

    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for chronyd (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (pid == 0) {
        // 첫 줄이어야 한다(TD-M1 plan 결정 M1-A). execve 전까지 이 자식은
        // 우리 코드로 서버 파일을 최대 30초 기다리고, 그동안은 부모의
        // SIGTERM 핸들러를 갖고 있다. 되돌리지 않으면 그 창에 전원을 끌 때
        // 이 자식만 안 죽는다.
        power.resetToDefault();
        const server: [4]u8 = switch (want) {
            .off => unreachable, // 위에서 돌아갔다
            .dhcp => waitForServerFile() orelse linux.exit(0),
            .server => |ip| ip,
        };
        if (!writeConf(server)) linux.exit(1);
        // net/check.sh의 검사 18이 이 줄을 grep한다.
        std.debug.print("tars-init: chronyd will ask {d}.{d}.{d}.{d} ({s})\n", .{
            server[0], server[1], server[2], server[3], CONF_PATH,
        });
        execChronyd(envp);
    }
    // `net.zig`의 `started dhcpcd on eth0 (pid N)`과 짝이 되는 자리이고,
    // 자식이 아무 말도 못 하고 죽은 회차에 "태어나기는 했다"를 남긴다.
    std.debug.print("tars-init: clock child (pid {d}) will ask {s}\n", .{
        pid, want.arg(&ntp_buf),
    });
}
