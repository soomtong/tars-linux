const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const power = @import("power.zig");

/// config.zig·main.zig·net.zig와 같은 세 줄짜리 헬퍼다. 다섯째 자리라 이제는
/// sys.zig로 모을 때가 됐지만, 그 변경은 파일 다섯을 한꺼번에 건드리는
/// 것이라 이 milestone에서 하지 않는다(net.zig의 같은 주석과 같은 판단이다).
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// NTP 타임스탬프는 1970이 아니라 1900부터 센다(design 결정 11).
/// 1900-01-01과 1970-01-01 사이가 70년 + 윤일 17번 = 2,208,988,800초다.
pub const NTP_EPOCH_DELTA: i64 = 2_208_988_800;

/// era 1(2036-02-07 06:28:16 UTC 이후)의 초에 더하는 값. 2^32에서
/// NTP_EPOCH_DELTA를 뺀 것이고, 32비트가 한 바퀴 돈 것을 되돌린다.
pub const ERA1_DELTA: i64 = 4_294_967_296 - NTP_EPOCH_DELTA;

/// SNTP 패킷의 길이. 요청도 응답도 이 길이다.
pub const PACKET_LEN = 48;

/// 요청의 첫 바이트. LI 0(경고 없음) · VN 4 · Mode 3(client).
const CLIENT_HEADER: u8 = 0x23;

/// 응답에서 우리가 받아 주는 Mode. 4가 server다.
const SERVER_MODE: u8 = 4;

/// 서버가 알려 준 시각. `clock_settime`이 먹는 모양 그대로다.
pub const Time = struct {
    sec: i64,
    nsec: i64,
};

/// 응답을 버리는 이유. 이름 그대로 로그에 찍히므로(`@errorName`) 게스트
/// 로그만 보고도 어느 검사에서 걸렸는지 안다.
pub const ReplyError = error{
    ShortPacket,
    NotAServer,
    KissOfDeath,
    OriginMismatch,
    ZeroTransmit,
};

/// 48바이트 클라이언트 요청을 짓는다. 시스템 콜이 없는 순수 함수다.
///
/// 채우는 것이 둘뿐이다 — 첫 바이트와 transmit timestamp. 나머지 마흔은
/// 0이고, 서버는 그 자리를 안 본다.
///
/// nonce를 transmit timestamp 자리에 넣는 것이 design 결정 12의 마지막
/// 항목이 기대는 계약이다. 서버는 그 8바이트를 응답의 originate timestamp
/// (24~31)로 그대로 베끼게 되어 있고, TS-M0 실측 1이 `NONCE123`으로 그것을
/// 직접 확인했다.
pub fn buildRequest(nonce: u64) [PACKET_LEN]u8 {
    var buf = [_]u8{0} ** PACKET_LEN;
    buf[0] = CLIENT_HEADER;
    std.mem.writeInt(u64, buf[40..48], nonce, .big);
    return buf;
}

/// 응답 48바이트를 시각으로 바꾼다. 시스템 콜이 없는 순수 함수다.
///
/// 검사 순서에 뜻이 있다. origin(우리 것인가)을 transmit(값이 쓸 만한가)
/// 보다 먼저 본다 — 그래야 남의 패킷이 우연히 transmit=0일 때 로그가
/// `ZeroTransmit`이 아니라 `OriginMismatch`라고 말한다. 앞은 서버 잘못을
/// 가리키고 뒤는 "우리 것이 아니다"를 가리키는데, 그 둘은 고치는 자리가
/// 완전히 다르다.
///
/// 배열로 복사해서 읽는다. `std.mem.readInt`는 길이가 컴파일 타임에 정해진
/// 포인터를 받으므로, 이 편이 읽는 사람에게 "여기 48바이트가 확실히 있다"를
/// 보인다.
pub fn parseReply(raw: []const u8, nonce: u64) ReplyError!Time {
    if (raw.len < PACKET_LEN) return error.ShortPacket;
    var buf: [PACKET_LEN]u8 = undefined;
    @memcpy(&buf, raw[0..PACKET_LEN]);

    // Mode는 첫 바이트의 아래 세 비트다.
    if (buf[0] & 0x07 != SERVER_MODE) return error.NotAServer;
    // stratum 0은 Kiss-o'-Death다 — 시각이 아니라 네 글자 코드가 들어 있다.
    if (buf[1] == 0) return error.KissOfDeath;
    if (std.mem.readInt(u64, buf[24..32], .big) != nonce) return error.OriginMismatch;

    const transmit = std.mem.readInt(u64, buf[40..48], .big);
    // 안 버리면 1900년으로 뛴다. era 1의 첫 1초가 이 검사에 함께 걸리는
    // 것을 우리가 알고 있다(TS-M1 plan의 "2036년의 1초를 우리가 못 읽는다").
    if (transmit == 0) return error.ZeroTransmit;

    const secs: u32 = @truncate(transmit >> 32);
    const frac: u32 = @truncate(transmit);

    // RFC 4330의 규칙 그대로다. 최상위 비트가 서 있으면 era 0(1968~2036),
    // 아니면 era 1(2036 이후)이다.
    const sec: i64 = if (secs & 0x8000_0000 != 0)
        @as(i64, secs) - NTP_EPOCH_DELTA
    else
        @as(i64, secs) + ERA1_DELTA;

    // 소수부는 2^32분의 1초 단위다. u64로 올려서 곱하면 넘치지 않는다 —
    // 최악이 (2^32-1) × 10^9 ≈ 4.3 × 10^18이고 u64의 상한이 1.8 × 10^19다.
    const nsec: i64 = @intCast((@as(u64, frac) * 1_000_000_000) >> 32);

    return .{ .sec = sec, .nsec = nsec };
}

/// `/run/tars/ntp_servers`의 내용에서 주소 하나를 꺼낸다. 시스템 콜이 없는
/// 순수 함수다.
///
/// 첫 토큰만 본다(design 비목표 2). 여럿이 와도 첫 것만 쓰기로 했으므로,
/// 첫 것이 주소가 아니면 뒤를 뒤지지 않는다 — 뒤지면 "첫 것을 쓴다"가
/// 조용히 "쓸 만한 첫 것을 쓴다"로 바뀌고, 그 둘은 실기에서 다른 서버를
/// 고르게 된다.
pub fn parseServerFile(text: []const u8) ?[4]u8 {
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    const first = it.next() orelse return null;
    return config.parseIpv4(first);
}

// ── 여기서부터는 시스템 콜을 한다. 위의 셋만 sntp_test가 본다 ───────────

/// 답을 기다리는 시간. 짧게 잡는 이유는 재시도가 있기 때문이다 — 한 번에
/// 오래 기다리는 것보다 여러 번 묻는 편이 주소가 늦게 붙는 경우를 잘 덮는다.
const RECV_TIMEOUT_SECONDS: isize = 2;

/// 몇 번까지 묻는가.
///
/// 이 수가 부팅 시간에 영향을 안 준다는 것이 design 결정 3의 덤이다. 부모는
/// 이미 다음 줄로 갔고, 이 루프는 자식 안에서만 돈다.
///
/// 30인 근거는 dhcpcd다. `sync()`가 불리는 시점은 dhcpcd가 방금 태어난
/// 직후라 아직 주소가 없고, NW-M2 실측 17이 `started dhcpcd`와 실제 리스
/// 사이에 시리얼 로그 3500줄이 있다고 쟀다. 한 회가 최악 3초이므로 30회면
/// 약 90초를 덮는다 — `net/check.sh`의 리스 대기 상한 60초보다 길다.
const MAX_TRIES: usize = 30;

/// 실패한 회차 뒤에 쉬는 시간. 답이 없어서 실패한 회차는 이미 2초를
/// 기다렸으므로 안 쉰다 — 이 쉼은 `sendto`가 즉시 실패한 회차의 것이다.
const RETRY_SLEEP_MS: isize = 1000;

/// dhcpcd의 hook이 option 42를 적어 두는 자리(design 결정 4). M1은 이 파일을
/// 읽기만 한다. 만드는 것은 M2의 hook이다.
const SERVER_FILE: [:0]const u8 = "/run/tars/ntp_servers";

/// NTP의 포트. TS-M0 실측 1이 컨테이너에서 이 포트를 실제로 열었으므로
/// 게이트도 여기를 쓴다 — 주소에 포트를 적는 문법이 필요 없다(위험 4가
/// 닫혔다).
const NTP_PORT: u16 = 123;

/// devices.zig·power.zig에도 같은 함수가 있다. `failed`와 같은 이유로 공용
/// 모듈을 만들지 않는다.
fn sleepMillis(ms: isize) void {
    const req = linux.timespec{
        .sec = @divTrunc(ms, 1000),
        .nsec = @rem(ms, 1000) * 1_000_000,
    };
    _ = linux.nanosleep(&req, null);
}

/// 이번 요청을 우리 것으로 표시하는 값(design 결정 12).
///
/// 난수가 아니다. 여기서 막으려는 것이 공격이 아니라 "엉뚱한 패킷"이고,
/// 부팅마다 다르면 그 일에 충분하다. 0을 피하는 이유는 0이 "서버가 아무것도
/// 안 채웠다"와 같은 값이기 때문이다.
fn makeNonce() u64 {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 1;
    const sec: u64 = @bitCast(@as(i64, ts.sec));
    const nsec: u64 = @bitCast(@as(i64, ts.nsec));
    const n = (sec << 32) | (nsec & 0xFFFF_FFFF);
    return if (n == 0) 1 else n;
}

/// 시계를 뛴다. 자식 안에서만 불린다.
fn step(t: Time) void {
    var before: linux.timespec = undefined;
    // 실패하면 0을 찍는다. 로그의 "was" 값이 진단용이라 여기서 돌아갈 이유가
    // 없다.
    const had: i64 = if (failed(linux.clock_gettime(.REALTIME, &before)) == null)
        @intCast(before.sec)
    else
        0;

    const ts = linux.timespec{ .sec = @intCast(t.sec), .nsec = @intCast(t.nsec) };
    if (failed(linux.clock_settime(.REALTIME, &ts))) |e| {
        std.debug.print("tars-init: cannot step the clock (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    // net/check.sh가 이 줄을 grep한다. 숫자가 stub이 정한 값과 정확히 같아야
    // 하므로 형식을 바꾸는 사람은 그 체인도 함께 본다.
    std.debug.print("tars-init: clock stepped to {d} (was {d})\n", .{ t.sec, had });
}

/// 자식이 하는 일 전부. 묻고, 받고, 뛴다.
fn askAndStep(server: [4]u8) void {
    const rc = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: sntp cannot open a socket (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    // design 결정 3의 안쪽 겹이다. 바깥 겹은 이 함수가 자식 안에서 돈다는
    // 것 자체이고, 그래서 이 타임아웃이 틀려도 부팅은 안 선다.
    const tv = linux.timeval{ .sec = RECV_TIMEOUT_SECONDS, .usec = 0 };
    if (failed(linux.setsockopt(
        fd,
        linux.SOL.SOCKET,
        linux.SO.RCVTIMEO,
        @ptrCast(&tv),
        @sizeOf(linux.timeval),
    ))) |e| {
        // 여기서 돌아가지 않는다. 타임아웃이 없으면 `recvfrom`이 영영 안
        // 돌아올 수 있지만, 그 자식이 매달리는 것은 부팅을 안 막는다.
        // 로그 한 줄이 그 상태를 알리는 전부다.
        std.debug.print("tars-init: sntp has no receive timeout (errno {d})\n", .{
            @intFromEnum(e),
        });
    }

    // 바이트 순서가 둘 다 네트워크 순서다. 포트는 정수라 뒤집어야 하고,
    // 주소는 이미 바이트 배열이라 그대로 얹으면 된다.
    const addr = linux.sockaddr.in{
        .port = std.mem.nativeToBig(u16, NTP_PORT),
        .addr = @bitCast(server),
    };

    var tries: usize = 0;
    while (tries < MAX_TRIES) : (tries += 1) {
        // 회차마다 새로 만든다. 그래야 지난 회차의 늦은 답이 이번 회차의
        // 답으로 읽히지 않는다 — 읽히면 왕복 시간이 한 회차만큼 어긋난 채
        // 시계를 뛴다.
        const nonce = makeNonce();
        const req = buildRequest(nonce);

        if (failed(linux.sendto(
            fd,
            &req,
            req.len,
            0,
            @ptrCast(&addr),
            @sizeOf(linux.sockaddr.in),
        ))) |e| {
            // 주소가 아직 안 붙었으면 여기가 ENETUNREACH(101)다. 실패가
            // 아니라 "아직"이고, 그래서 이 줄이 자주 찍히는 것이 정상이다.
            std.debug.print("tars-init: sntp send failed (errno {d}), try {d}\n", .{
                @intFromEnum(e), tries + 1,
            });
            sleepMillis(RETRY_SLEEP_MS);
            continue;
        }

        var buf: [PACKET_LEN]u8 = undefined;
        var from: linux.sockaddr.in = undefined;
        var from_len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
        const n = linux.recvfrom(fd, &buf, buf.len, 0, @ptrCast(&from), &from_len);
        if (failed(n)) |e| {
            // 타임아웃이면 EAGAIN(11)이다. 이미 2초를 기다렸으므로 안 쉰다.
            std.debug.print("tars-init: sntp got no answer (errno {d}), try {d}\n", .{
                @intFromEnum(e), tries + 1,
            });
            continue;
        }

        // 소스 주소를 보고 버리지는 않는다. 우리가 이 주소를 안 재 봤고
        // (TS-M0은 컨테이너 쪽에서만 봤다), 위조를 막는 일은 nonce가 한다
        // (design 결정 12). 다르면 알리기만 해서 다음 사이클이 그것을 알고
        // 결정하게 한다.
        const from_ip: [4]u8 = @bitCast(from.addr);
        if (!std.mem.eql(u8, &from_ip, &server)) {
            std.debug.print("tars-init: sntp answer came from {d}.{d}.{d}.{d}, not the server\n", .{
                from_ip[0], from_ip[1], from_ip[2], from_ip[3],
            });
        }

        const got = parseReply(buf[0..n], nonce) catch |e| {
            std.debug.print("tars-init: sntp reply rejected ({s}), try {d}\n", .{
                @errorName(e), tries + 1,
            });
            continue;
        };
        step(got);
        return;
    }

    std.debug.print("tars-init: sntp gave up after {d} tries\n", .{MAX_TRIES});
}

/// `ntp=dhcp`일 때 서버를 찾는 자리. M1은 한 번만 열어 보고 없으면 끝낸다
/// (TS-M1 plan 결정 M1-D) — 기다리는 것은 M2가 더한다.
fn serverFromFile() ?[4]u8 {
    const rc = linux.open(SERVER_FILE.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: ntp=dhcp but {s} is not there (errno {d})\n", .{
            SERVER_FILE, @intFromEnum(e),
        });
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
    std.debug.print("tars-init: ntp server {d}.{d}.{d}.{d} came from {s}\n", .{
        ip[0], ip[1], ip[2], ip[3], SERVER_FILE,
    });
    return ip;
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나다.
///
/// `net.zig`의 `bringUp`과 같은 모양이고 같은 규칙을 따른다 — `off`일 때도
/// 로그 한 줄을 남긴다. 침묵은 "안 켰다"와 "켜려다 실패했다"를 못 가른다.
///
/// 갈래 넷이 design 결정 3의 표 그대로다.
pub fn sync(net: config.Net, want: config.Ntp) void {
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;

    if (want == .off) {
        std.debug.print("tars-init: ntp=off, leaving the clock alone\n", .{});
        return;
    }
    // `net`을 먼저 본다. 네트워크가 꺼져 있으면 주소가 붙을 리 없으므로
    // 소켓도 fork도 만들지 않는다.
    if (net == .off) {
        std.debug.print("tars-init: ntp={s} but net=off, leaving the clock alone\n", .{
            want.arg(&ntp_buf),
        });
        return;
    }

    const server: [4]u8 = switch (want) {
        .off => unreachable, // 위에서 돌아갔다
        .dhcp => serverFromFile() orelse return,
        .server => |ip| ip,
    };

    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for sntp (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (pid == 0) {
        // 첫 줄이어야 한다(TS-M1 plan 결정 M1-A). `execve`를 안 하는 자식이라
        // 부모의 SIGTERM 핸들러를 그대로 갖고 있고, 그대로 두면 전원을 끌 때
        // 이 자식만 안 죽는다.
        power.resetToDefault();
        askAndStep(server);
        linux.exit(0);
    }
    // net/check.sh가 이 줄을 grep하지는 않는다. `net.zig`의
    // `started dhcpcd on eth0 (pid N)`과 짝이 되는 자리이고, 자식이 아무 말도
    // 못 하고 죽은 회차에 "태어나기는 했다"를 남긴다.
    std.debug.print("tars-init: sntp child (pid {d}) will ask {d}.{d}.{d}.{d}\n", .{
        pid, server[0], server[1], server[2], server[3],
    });
}
