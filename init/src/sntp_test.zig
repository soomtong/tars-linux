const std = @import("std");
const sntp = @import("sntp.zig");
const config = @import("config.zig");

/// 48바이트 응답 하나를 짓는다. 검사마다 바꾸고 싶은 것만 인자로 받는다 —
/// 나머지는 정상값이라 "이 검사가 무엇을 보는지"가 인자 목록에 그대로
/// 드러난다.
///
/// 이 헬퍼가 stub의 pack 템플릿과 같은 바이트 배치를 손으로 한 벌 더 적는
/// 것이라는 점이 중요하다. `buildRequest`로 조립해서 검사하면 검사가
/// tautology가 된다 — SD-M1이 씨앗과 목록을 두 벌로 나눈 것과 같은 이유다.
fn reply(mode: u8, stratum: u8, origin: u64, transmit: u64) [48]u8 {
    var buf = [_]u8{0} ** 48;
    buf[0] = (4 << 3) | mode; // LI 0, VN 4, Mode는 인자
    buf[1] = stratum;
    buf[2] = 4; // poll
    buf[3] = @bitCast(@as(i8, -6)); // precision
    std.mem.writeInt(u64, buf[24..32], origin, .big);
    std.mem.writeInt(u64, buf[40..48], transmit, .big);
    return buf;
}

/// NTP 초(1900 기준)와 소수부를 8바이트 타임스탬프 하나로 만든다.
fn stamp(secs: u32, frac: u32) u64 {
    return (@as(u64, secs) << 32) | @as(u64, frac);
}

fn expectAccepted(buf: []const u8, nonce: u64, want_sec: i64, want_nsec: i64) !void {
    const got = sntp.parseReply(buf, nonce) catch |e| {
        std.debug.print("FAIL: reply rejected with {s}, expected sec={d}\n", .{
            @errorName(e), want_sec,
        });
        return error.RejectedGoodReply;
    };
    if (got.sec != want_sec or got.nsec != want_nsec) {
        std.debug.print("FAIL: got sec={d} nsec={d}, want sec={d} nsec={d}\n", .{
            got.sec, got.nsec, want_sec, want_nsec,
        });
        return error.WrongTime;
    }
}

fn expectRejected(buf: []const u8, nonce: u64, want: anyerror) !void {
    if (sntp.parseReply(buf, nonce)) |got| {
        std.debug.print("FAIL: reply accepted as sec={d}, expected {s}\n", .{
            got.sec, @errorName(want),
        });
        return error.AcceptedBadReply;
    } else |e| {
        if (e != want) {
            std.debug.print("FAIL: rejected with {s}, expected {s}\n", .{
                @errorName(e), @errorName(want),
            });
            return error.WrongRejection;
        }
    }
}

fn expectServer(text: []const u8, want: [4]u8) !void {
    const got = sntp.parseServerFile(text) orelse {
        std.debug.print("FAIL: no server found in [{s}]\n", .{text});
        return error.NoServer;
    };
    if (!std.mem.eql(u8, &got, &want)) {
        std.debug.print("FAIL: got {d}.{d}.{d}.{d} from [{s}]\n", .{
            got[0], got[1], got[2], got[3], text,
        });
        return error.WrongServer;
    }
}

fn expectNoServer(text: []const u8) !void {
    if (sntp.parseServerFile(text)) |got| {
        std.debug.print("FAIL: found {d}.{d}.{d}.{d} in [{s}], expected none\n", .{
            got[0], got[1], got[2], got[3], text,
        });
        return error.UnexpectedServer;
    }
}

pub fn main() !void {
    // ── buildRequest ───────────────────────────────────────────────────
    //
    // 보는 것이 셋이다. 길이 · 첫 바이트 · nonce가 40~47에 들어가는가.
    //
    // 첫 바이트 0x23은 LI 0(경고 없음) · VN 4 · Mode 3(client)이다.
    // 이 값이 틀리면 서버가 답을 안 하거나 엉뚱한 모드로 답하는데, 그
    // 증상은 게스트에서 "답이 안 온다" 하나라 원인에서 멀다.
    const nonce: u64 = 0x0123456789ABCDEF;
    const req = sntp.buildRequest(nonce);
    if (req.len != 48) {
        std.debug.print("FAIL: request is {d} bytes, want 48\n", .{req.len});
        return error.BadRequestLength;
    }
    if (req[0] != 0x23) {
        std.debug.print("FAIL: first byte is 0x{x:0>2}, want 0x23\n", .{req[0]});
        return error.BadRequestHeader;
    }
    if (std.mem.readInt(u64, req[40..48], .big) != nonce) {
        std.debug.print("FAIL: the nonce is not in the transmit timestamp\n", .{});
        return error.NonceNotSent;
    }
    // 나머지 바이트가 전부 0인지 본다. 서버가 안 보는 자리라도 쓰레기를
    // 보내지 않는다는 것이 이 함수의 계약이다.
    for (req[1..40]) |b| {
        if (b != 0) {
            std.debug.print("FAIL: request bytes 1..39 are not all zero\n", .{});
            return error.DirtyRequest;
        }
    }
    std.debug.print("sntp_test: the request is 48 bytes of client mode 3 and a nonce\n", .{});

    // ── parseReply: 정상 ───────────────────────────────────────────────
    //
    // stub이 답하는 값 그대로다. 1930367167 + 2208988800 = 4139355967이고
    // 그것이 2031-03-04T05:06:07Z다. net/check.sh의 STUB_UNIX와 같은 수여야
    // 한다 — 이 숫자가 두 자리에 있다는 것을 알고 두는 것이다.
    const ok = reply(4, 1, nonce, stamp(4_139_355_967, 0));
    try expectAccepted(&ok, nonce, 1_930_367_167, 0);

    // 소수부가 나노초가 되는가. 0x80000000은 정확히 절반이므로 500,000,000ns다.
    const half = reply(4, 1, nonce, stamp(4_139_355_967, 0x8000_0000));
    try expectAccepted(&half, nonce, 1_930_367_167, 500_000_000);
    std.debug.print("sntp_test: a server reply becomes unix seconds and nanoseconds\n", .{});

    // ── parseReply: era 경계 양쪽(design 결정 11) ──────────────────────
    //
    // era 0의 마지막 초. 0xFFFFFFFF - 2208988800 = 2085978495이고
    // 2036-02-07T06:28:15Z다.
    const era0_last = reply(4, 1, nonce, stamp(0xFFFF_FFFF, 0));
    try expectAccepted(&era0_last, nonce, 2_085_978_495, 0);

    // era 1의 첫 "읽을 수 있는" 순간. 초가 0이고 소수부가 1이다.
    // 초 0 · 소수부 0은 아래에서 일부러 버린다.
    const era1_first = reply(4, 1, nonce, stamp(0, 1));
    try expectAccepted(&era1_first, nonce, 2_085_978_496, 0);

    // era 1로 넘어간 지 1초. 부호 없는 32비트를 그대로 빼는 코드를 쓰면
    // 여기서 1900년이 나온다.
    const era1_next = reply(4, 1, nonce, stamp(1, 0));
    try expectAccepted(&era1_next, nonce, 2_085_978_497, 0);
    std.debug.print("sntp_test: both sides of the 2036 era boundary read right\n", .{});

    // ── parseReply: 검증 넷(design 결정 12) ────────────────────────────
    //
    // Mode가 4가 아니다. 3이면 우리가 보낸 것이 그대로 되돌아온 것이다.
    const echoed = reply(3, 1, nonce, stamp(4_139_355_967, 0));
    try expectRejected(&echoed, nonce, error.NotAServer);

    // stratum 0은 Kiss-o'-Death다. 시각 자리에 사람이 읽는 글자가 들어 있다.
    const kod = reply(4, 0, nonce, stamp(4_139_355_967, 0));
    try expectRejected(&kod, nonce, error.KissOfDeath);

    // origin이 우리 nonce가 아니다. 아무 UDP 패킷이나 시계를 옮기는 것을
    // 막는 자리이고, 결정 12가 가장 중요하다고 적은 줄이다.
    const stranger = reply(4, 1, nonce ^ 1, stamp(4_139_355_967, 0));
    try expectRejected(&stranger, nonce, error.OriginMismatch);

    // transmit이 0이다. 안 버리면 1900년으로 뛴다.
    const empty = reply(4, 1, nonce, 0);
    try expectRejected(&empty, nonce, error.ZeroTransmit);

    // 짧은 패킷. UDP는 무엇이든 올 수 있다.
    const short = [_]u8{0} ** 20;
    try expectRejected(&short, nonce, error.ShortPacket);
    std.debug.print("sntp_test: mode, stratum, origin and transmit each reject a bad reply\n", .{});

    // ── 2036년의 그 1초 ────────────────────────────────────────────────
    //
    // era 1의 첫 순간은 8바이트가 통째로 0이라 "안 채운 패킷"과 구별되지
    // 않는다. 우리는 그것을 버리는 쪽을 골랐다(TS-M1 plan의 "2036년의 1초"
    // 절). 이 검사는 버그가 아니라 선택이라는 표시다 — 지우려는 사람은
    // 그 절을 먼저 읽게 된다.
    const era1_zero = reply(4, 1, nonce, stamp(0, 0));
    try expectRejected(&era1_zero, nonce, error.ZeroTransmit);
    std.debug.print("sntp_test: the one second we cannot read in 2036 is rejected on purpose\n", .{});

    // ── parseServerFile ────────────────────────────────────────────────
    //
    // dhcpcd가 hook에 넘기는 `$new_ntp_servers`는 공백으로 갈린 목록이고,
    // hook은 그것을 그대로 파일에 쓴다. 첫 것만 쓴다(design 비목표 2).
    try expectServer("10.0.2.2\n", .{ 10, 0, 2, 2 });
    try expectServer("192.168.0.1 192.168.0.2\n", .{ 192, 168, 0, 1 });
    // 개행 없이 끝나도 받는다. `printf`로 쓴 파일이 그렇다.
    try expectServer("1.2.3.4", .{ 1, 2, 3, 4 });
    // 빈 파일. hook이 빈 값으로 불린 경우다.
    try expectNoServer("");
    try expectNoServer("\n");
    // 이름은 안 받는다(design 결정 5 — init에 resolver가 없다).
    try expectNoServer("pool.ntp.org\n");
    // 첫 토큰만 본다. 그것이 주소가 아니면 뒤를 안 뒤진다.
    try expectNoServer("garbage 10.0.2.2\n");
    std.debug.print("sntp_test: the server file gives up its first address and nothing else\n", .{});

    std.debug.print("PASS\n", .{});
}
