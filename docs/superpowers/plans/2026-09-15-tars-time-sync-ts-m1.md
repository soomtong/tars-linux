# TS-M1 — 우리 코드가 시계를 뛴다

Date: 2026-09-15
design: `docs/superpowers/specs/2026-09-15-tars-time-sync-design.md`

TS-M0이 미지수를 거의 다 없앴다. SLIRP가 나가는 UDP를 컨테이너에 넘기고
(실측 2), 컨테이너가 UDP 123을 열 수 있고(실측 1), 게스트에서 벽시계를 뛸 수
있고(실측 5), 5년을 뛰어도 게스트가 그대로 돈다(실측 6). 남은 미지수는
하나다 — 렌더가 점프를 견디는지(실측 7). 이 milestone의 부팅 A가 그것까지
함께 답한다.

Goal: `tars.conf`에 `ntp=<IPv4>`를 적은 기계가 부팅할 때 그 주소에 SNTP로
한 번 묻고 `clock_settime`으로 시계를 뛴다. 그 일이 게이트 안에서 매번
증명된다.

Architecture: 순수 계산과 시스템 콜을 가른다. 48바이트를 짓고 읽는 것은
호스트에서 도는 순수 함수이고(`sntp_test`가 본다), 소켓을 열고 시계를 뛰는
것은 `fork`한 자식 하나다. 부모는 그 자식을 한 순간도 안 기다린다
(design 결정 3). 게이트의 상대는 컨테이너에서 도는 perl stub이고, 그것이
답하는 시각이 CMOS로도 커널로도 나올 수 없는 2031년이라 "우리 코드가
움직였다"가 "원래 그 값이었다"와 갈린다(실측 4가 그 필요를 만들었다).

Tech Stack: Zig 0.16(`std.os.linux`만. libc도 힙도 없다) · perl
(`IO::Socket::INET`) · bash · QEMU 10.0.11 · debugfs(e2fsprogs)

---

## design에 없던 결정 넷

코드를 읽으면서 나온 것들이다. design을 고치지는 않고(틀린 것이 아니라 덜
적힌 것이다) 이 plan이 근거와 함께 정한다.

### 결정 M1-A — 자식이 시그널 정책을 되돌린다

`main.zig:524`의 `power.install()`이 SIGTERM·SIGINT 핸들러를 달고, 그것은
`net.bringUp`(:676)보다 앞이다. 그래서 그 뒤에 `fork`하는 자식은 그 핸들러를
물려받는다.

`net.zig`의 dhcpcd 자식은 이 문제가 없다 — `execve`가 다뤄진 시그널을 전부
`SIG_DFL`로 되돌리기 때문이다. SNTP 자식은 `execve`를 안 하므로(확인 3) 그
일이 안 일어나고, 물려받은 `onSignal`은 죽는 대신 정수 하나만 남긴다.

그대로 두면 증상이 종료에서 나온다. 전원을 끄면 PID 1이 `kill(-1, .TERM)`을
보내는데(SL-M1) 이 자식만 안 죽고, `reapAll()`이 유예 3초를 다 쓰고
`grace period expired`를 찍는다 — SL-M2가 세운 음성 검사가 그 줄을 실패로
판정한다. 즉 시계는 맞는데 게이트가 빨간불이 되고, 그 둘이 서로 멀어서
원인을 찾기 어렵다.

그래서 `power.zig`에 `resetToDefault()`를 더하고 자식의 첫 줄에서 부른다.
정책을 세우는 파일이 정책을 되돌리는 함수도 갖는 것이 맞다.

M1의 부팅 A에서는 자식이 몇 초 만에 끝나므로 이 줄이 없어도 초록일
가능성이 높다. M2의 부팅 B가 그 반대다 — 안 닿는 주소라 자식이 끝까지
재시도하고, 전원을 끄는 순간 살아 있다. 그 자리에서 터질 것을 여기서 막는다.

### 결정 M1-B — 자식은 재시도한다. 주소가 붙기를 기다리는 것이 그 일이다

`sntp.sync()`를 부르는 자리는 `net.bringUp()` 바로 다음인데, 그 시점에는
dhcpcd가 방금 태어났을 뿐 주소가 없다. NW-M2 실측 17이 그 간격을 쟀다 —
`started dhcpcd`가 시리얼 로그 256번째 줄이고 `soliciting a DHCP lease`가
3745번째 줄이다. 첫 `sendto`는 주소도 경로도 없어서 실패한다.

갈래가 셋이었다.

| 갈래 | 왜 안 골랐나 |
|---|---|
| 리스를 기다렸다가 fork | 부모가 기다리는 것은 결정 3이 금지한다 |
| 자식이 주소를 직접 확인(`SIOCGIFADDR`) | ioctl 한 벌이 더 들고, 주소가 붙는 것과 경로가 서는 것이 또 다르다 |
| 자식이 그냥 재시도 | `sendto`의 errno가 곧 답이다 |

셋째를 고른다. 재시도의 비용이 부팅 시간에 0이라는 것이 결정 3의 덤이다 —
부모는 이미 다음 줄로 갔다.

상한은 30회다. 한 회가 `sendto` + 답 없으면 2초(`SO_RCVTIMEO`) + 1초 쉼이라
최악이 약 90초이고, 그 90초는 아무것도 안 막는다. 게이트의 부팅 하나가
그보다 짧으므로 M2의 부팅 B에서는 자식이 끝을 못 보고 전원과 함께 죽는다 —
그것이 정상이고, 결정 M1-A가 그 죽음을 조용하게 만든다.

### 결정 M1-C — `parseIpv4`는 `config.zig`에 산다

HANDOFF는 순수 함수 넷을 전부 `sntp.zig`에 적었다. 그대로 두면 import가
순환한다 — `config.zig`는 값을 파싱하려고 `sntp`를 부르고, `sntp.zig`는
`config.Ntp` 타입을 쓴다.

기존 방향이 답이다. `net.zig`가 `config.Net`을 받고 `config.zig`는 `net`을
모른다. 그 방향을 지키려면 설정 값을 문자열에서 만드는 코드가 `config.zig`에
있어야 하고, 실제로 그것이 `Toggles.parse`가 있는 자리다.

그래서 넷이 이렇게 나뉜다.

| 함수 | 사는 곳 | 보는 검사 |
|---|---|---|
| `parseIpv4` | `config.zig` | `config_test` |
| `Ntp.parse` · `Ntp.arg` | `config.zig` | `config_test` |
| `buildRequest` · `parseReply` · `parseServerFile` | `sntp.zig` | `sntp_test` |

`parseServerFile`이 `config.parseIpv4`를 부른다. 방향이 하나라 순환이 없다.

### 결정 M1-D — `ntp=dhcp`도 M1에서 돈다. 다만 안 기다린다

`parseServerFile`을 M1에 넣으면서 아무도 안 부르는 코드로 두지 않는다.
`ntp=dhcp`면 `/run/tars/ntp_servers`를 한 번 열어 보고, 없으면 로그 한 줄을
찍고 끝낸다.

M2가 더하는 것이 그 파일을 만드는 hook과 "제한 시간 안에서 기다리는 것"
둘이다. 즉 M1은 "파일이 있으면 읽는다"까지이고 M2가 "파일이 생길 때까지
기다린다"를 더한다. 이 순서면 M1이 죽은 코드를 안 남기고, M2의 변경이
"기다림" 하나로 좁아진다.

## 2036년의 1초를 우리가 못 읽는다

결정 11과 결정 12가 정확히 한 자리에서 부딪친다.

- 결정 12는 transmit timestamp가 0이면 버리라고 한다. 안 버리면 서버가
  아무것도 안 채운 패킷으로 1900년에 뛴다.
- 결정 11은 NTP 초의 최상위 비트가 0이면 era 1(2036년 이후)로 읽으라고 한다.

era 1의 첫 순간은 초도 0이고 소수부도 0이다. 그래서 8바이트가 통째로 0이고,
그 값은 "안 채운 패킷"과 바이트가 같다.

가릴 방법이 없다. 그래서 우리는 그 1초
(2036-02-07T06:28:16.000000000Z)를 버린다. 대가는 그 한 순간에 정확히 도착한
응답 하나를 버리고 1초 뒤에 재시도하는 것이고, 재시도가 이미 있다
(결정 M1-B). `sntp_test`가 이 선택을 검사로 못 박아서 나중에 누가
"버그"로 고치지 못하게 한다.

## Task 0 — 지금 상태를 재고 시작한다

- [ ] Step 1: 호스트 검사가 지금 초록인지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

기대: `PASS`가 다섯 번(config · power · devices · storage · environ). 지금
빨간불이면 이 milestone이 만든 것이 아니므로 먼저 가른다.

- [ ] Step 2: `net` 체인 단독 시간을 잰다 (약 1분, design 위험 5)

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh 2>&1 | tail -20
```

기대: `PASS`. 그 시간이 부팅 A를 더하기 전의 기준선이다 — Task 9에서 같은
명령으로 다시 재서 증가분을 적는다. NW-M3 시절이 33.7초였고 IN이 검사
넷을 더했으므로 그보다 크다.

## Task 1 — `sntp_test.zig`를 먼저 쓴다 (RED)

파일: `init/src/sntp_test.zig` (새 파일)

이 저장소의 호스트 검사 모양을 따른다 — 실패하면 0이 아닌 종료 코드이고
마지막 줄이 `PASS`다(`config_test`·`storage_test`와 같다).

RED의 모양이 컴파일 에러라는 것을 미리 적어 둔다. `sntp.zig`가 아직 없으므로
`zig build test`가 `unable to load 'src/sntp.zig'`로 죽는다. 그것이 이
단계의 빨간불이고, Task 2가 그것을 초록으로 만든다.

- [ ] Step 1: 파일을 만든다

```zig
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
    for (req[1..24]) |b| {
        if (b != 0) {
            std.debug.print("FAIL: request bytes 1..23 are not all zero\n", .{});
            return error.DirtyRequest;
        }
    }

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

    // ── 2036년의 그 1초 ────────────────────────────────────────────────
    //
    // era 1의 첫 순간은 8바이트가 통째로 0이라 "안 채운 패킷"과 구별되지
    // 않는다. 우리는 그것을 버리는 쪽을 골랐다(이 plan의 "2036년의 1초"
    // 절). 이 검사는 버그가 아니라 선택이라는 표시다 — 지우려는 사람은
    // 그 절을 먼저 읽게 된다.
    const era1_zero = reply(4, 1, nonce, stamp(0, 0));
    try expectRejected(&era1_zero, nonce, error.ZeroTransmit);

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

    std.debug.print("PASS\n", .{});
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
```

- [ ] Step 2: `build.zig`에 검사를 붙인다

`environ_test_mod` 블록 바로 뒤에 더한다.

```zig
    // TS-M1: SNTP 패킷을 짓고 읽는 순수 함수의 검사. 위 다섯과 같은 이유로
    // host_target이다 — `sntp.zig`에서 시스템 콜을 하는 부분은 `sync()`
    // 아래에만 있고, 이 검사가 부르는 셋은 바이트 계산뿐이다.
    //
    // 이 검사가 있는 자리가 곧 design 결정 11·12다. era 경계는 10년 뒤에
    // 한 번 오는 일이라 게이트가 영영 못 보고, 검증 넷은 stub이 착한
    // 서버라서 게이트가 안 밟는다.
    const sntp_test_mod = b.createModule(.{
        .root_source_file = b.path("src/sntp_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const sntp_test = b.addExecutable(.{
        .name = "sntp_test",
        .root_module = sntp_test_mod,
    });
```

그리고 `test_step` 목록에 한 줄을 더한다.

```zig
    test_step.dependOn(&b.addRunArtifact(sntp_test).step);
```

- [ ] Step 3: 빨간불을 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test' 2>&1 | tail -20
```

기대: `sntp.zig`가 없다는 컴파일 에러. 이 단계에서 `PASS`가 나오면 파일을
잘못 놓은 것이다.

## Task 2 — `sntp.zig`의 순수 함수 셋 (GREEN)

파일: `init/src/sntp.zig` (새 파일)

이 Task에서는 순수 함수만 넣는다. 소켓과 `fork`는 Task 4다 — 검사가 초록이
되는 것과 게스트가 도는 것을 다른 커밋으로 가른다.

- [ ] Step 1: 파일을 만든다

```zig
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const power = @import("power.zig");

/// config.zig·main.zig·net.zig와 같은 세 줄짜리 헬퍼다. 다섯째 자리라
/// 이제는 sys.zig로 모을 때가 됐지만, 그 변경은 파일 다섯을 한꺼번에
/// 건드리는 것이라 이 milestone에서 하지 않는다(net.zig의 같은 주석과
/// 같은 판단이다).
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// NTP 타임스탬프는 1970이 아니라 1900부터 센다(design 결정 11).
/// 1900-01-01과 1970-01-01 사이가 70년 + 윤일 17번 = 2,208,988,800초다.
pub const NTP_EPOCH_DELTA: i64 = 2_208_988_800;

/// era 1(2036-02-07 06:28:16 UTC 이후)의 초에 더하는 값.
/// 2^32 - NTP_EPOCH_DELTA이고, 32비트가 한 바퀴 돈 것을 되돌린다.
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
/// (24~47이 아니라 24~31)로 그대로 베끼게 되어 있고, TS-M0 실측 1이
/// `NONCE123`으로 그것을 직접 확인했다.
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
/// 배열로 복사해서 읽는다. `std.mem.readInt`는 길이가 컴파일 타임에
/// 정해진 포인터를 받으므로, 슬라이스를 그대로 자르는 것보다 이 편이
/// 읽는 사람에게 "여기 48바이트가 확실히 있다"를 보인다.
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
    // 것을 우리가 알고 있다(plan의 "2036년의 1초를 우리가 못 읽는다").
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
```

- [ ] Step 2: 초록을 확인한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test' 2>&1 | tail -20
```

기대: `PASS` 여섯 개.

`config.parseIpv4`가 아직 없으므로 이 단계도 컴파일 에러로 죽는다. 순서를
지키려면 Task 3 Step 1(파서)을 먼저 넣고 이 Step으로 돌아온다 — 두 파일이
한 함수로 묶여 있어서 갈라지지 않는다. 실행 순서를 Task 3 → Task 2 Step 2로
적어 둔다.

- [ ] Step 3: 더한 줄과 지운 줄을 센다

```bash
git diff --stat
git diff | grep '^-'
```

지운 줄은 `build.zig`의 `test_step` 근처뿐이어야 한다.

## Task 3 — `tars.conf`의 여덟째 키 `ntp`

파일: `init/src/config.zig` · `init/src/config_test.zig`

- [ ] Step 1: `Net` 선언 바로 뒤에 `parseIpv4`와 `Ntp`를 넣는다

```zig
/// 점 넷으로 적은 IPv4 주소를 바이트 넷으로 바꾼다. 시스템 콜이 없는 순수
/// 함수이고, 이 파일에서 `parse`·`cmdlineWantsNoConfig`와 같은 성질이다.
///
/// 이 저장소의 첫 자유 문자열 설정 값이라 파서가 필요해졌다(TS 확인 9).
/// 다른 일곱 키는 전부 `stringToEnum` 화이트리스트라 "모르는 값은 기본값"이
/// 공짜로 따라왔는데, 주소는 그 수법이 안 선다.
///
/// `inet_aton`과 다르게 구는 자리가 하나다 — `010`을 8이 아니라 10으로
/// 읽는다. 8진수 해석은 사람을 놀라게 하는 쪽이고, 설정 파일은 사람이 손으로
/// 고치는 물건이다.
///
/// 힙이 없으므로 돌려주는 것이 배열이다. optional이라 "못 읽었다"가 값으로
/// 온다.
pub fn parseIpv4(text: []const u8) ?[4]u8 {
    var out: [4]u8 = undefined;
    var i: usize = 0;
    var it = std.mem.splitScalar(u8, text, '.');
    while (it.next()) |part| {
        // 다섯째 조각이 오면 주소가 아니다. `1.2.3.4.5`가 여기서 걸린다.
        if (i == 4) return null;
        if (part.len == 0 or part.len > 3) return null;
        var v: u16 = 0;
        for (part) |ch| {
            if (ch < '0' or ch > '9') return null;
            v = v * 10 + (ch - '0');
        }
        if (v > 255) return null;
        out[i] = @intCast(v);
        i += 1;
    }
    // 조각이 넷이 아니면 주소가 아니다. `1.2.3`이 여기서 걸린다.
    if (i != 4) return null;
    return out;
}

/// `Ntp.arg`가 만드는 문자열을 담을 버퍼의 크기. 가장 긴 것이
/// `255.255.255.255` 15바이트이고 NUL 하나가 더 든다.
pub const NTP_ARG_MAX = 16;

comptime {
    const longest = "255.255.255.255";
    if (longest.len + 1 > NTP_ARG_MAX)
        @compileError("NTP_ARG_MAX is too small for a dotted quad");
}

/// 부팅할 때 시각을 어디에 묻는가(TS design 결정 5).
///
/// 키 하나가 "켜고 끄는 것"과 "어디에 묻는지"를 함께 정한다. 그래서 "켰는데
/// 어디에 물을지를 안 적은" 모순 상태가 구조적으로 없다.
///
/// `Net`과 달리 enum이 아니라 union인 이유는 셋째 값이 자유 문자열이기
/// 때문이다. 이것이 이 파일에서 `stringToEnum` 화이트리스트가 아닌 두
/// 번째 값이고(앞은 `Toggles`), 둘 다 파싱 함수를 자기가 갖는다.
///
/// 기본값이 `off`인 근거는 `net`과 같다(확인 10). `net=off`인 기계에서
/// 이 키가 켜져 있으면 자식이 매 부팅마다 헛되이 태어나 실패하고 죽는다.
pub const Ntp = union(enum) {
    off,
    dhcp,
    server: [4]u8,

    /// 설정 파일의 값을 이 타입으로 바꾼다. 모르는 값이면 null이고,
    /// 호출자가 로그를 찍고 기본값에 머문다 — 다른 일곱 키와 같은 규칙이다.
    pub fn parse(value: []const u8) ?Ntp {
        if (std.mem.eql(u8, value, "off")) return .off;
        if (std.mem.eql(u8, value, "dhcp")) return .dhcp;
        const ip = parseIpv4(value) orelse return null;
        return .{ .server = ip };
    }

    /// 로그와 씨앗 파일에 찍을 정규형. 버퍼는 호출자가 준다 —
    /// `Toggles.arg`와 같은 이유로, 이 파일에는 힙이 없고 주소는 상수
    /// 문자열로 돌려줄 수가 없다.
    pub fn arg(self: Ntp, buf: []u8) [:0]const u8 {
        switch (self) {
            .off => return "off",
            .dhcp => return "dhcp",
            .server => |ip| {
                const text = std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{
                    ip[0], ip[1], ip[2], ip[3],
                }) catch return "off";
                buf[text.len] = 0;
                return buf[0..text.len :0];
            },
        }
    }

    /// 두 값이 같은가. `config_test`의 필드 비교가 쓴다 — union은 `==`로
    /// 비교되지 않고, 그 자리에 `std.meta.eql`을 쓰면 검사가 무엇을 보는지가
    /// 흐려진다.
    pub fn eql(self: Ntp, other: Ntp) bool {
        return switch (self) {
            .off => other == .off,
            .dhcp => other == .dhcp,
            .server => |a| switch (other) {
                .server => |b| std.mem.eql(u8, &a, &b),
                else => false,
            },
        };
    }
};
```

- [ ] Step 2: `Config`에 필드를 더한다

`net: Net = .off,` 바로 아래다.

```zig
    /// 기본값이 `off`인 둘째 키다. 근거는 바로 위 `net`과 같고 하나가 더
    /// 있다 — 이 키는 `net`이 꺼져 있으면 아무 일도 못 한다(design 결정 3).
    ntp: Ntp = .off,
```

- [ ] Step 3: `parse`에 분기를 더한다

`net` 분기 바로 뒤, `else` 앞이다.

```zig
        } else if (std.mem.eql(u8, key, "ntp")) {
            // 앞의 일곱과 모양이 다른 유일한 자리다. `stringToEnum`이 아니라
            // `Ntp.parse`인 이유는 값의 셋째 갈래가 주소 리터럴이기
            // 때문이다(design 결정 5). 모르는 값을 흘려보내는 규칙은 같다.
            var ntp_buf: [NTP_ARG_MAX]u8 = undefined;
            c.ntp = Ntp.parse(value) orelse {
                std.debug.print("tars-init: unknown ntp '{s}', falling back to {s}\n", .{
                    value, c.ntp.arg(&ntp_buf),
                });
                continue;
            };
```

- [ ] Step 4: `save`가 여덟째 줄을 쓰게 한다

`net={s}` 다음에 더하고, 인자 목록의 `@tagName(c.net)` 뒤에
`c.ntp.arg(&ntp_buf)`를 더한다. `toggle_buf` 선언 옆에 버퍼를 하나 더 잡는다.

```zig
    var ntp_buf: [NTP_ARG_MAX]u8 = undefined;
```

```
        \\# ntp: off | dhcp | <IPv4 주소>
        \\#   dhcp면 DHCP 서버가 알려 준 NTP 서버에 묻는다. 주소를 적으면
        \\#   그 주소에 묻는다. 부팅할 때 한 번만 묻고 시계를 그 값으로
        \\#   뛴다 — 그 뒤로는 시계를 안 건드린다. net=off면 아무 일도 안 한다
        \\ntp={s}
```

- [ ] Step 5: `main.zig`의 설정 로그 줄을 넓힌다

`tars-init: config shell=...` 줄에 `ntp={s}`를 맨 뒤에 붙인다. 맨 뒤여야
하는 이유가 있다 — 체인 아홉 자리가 이 줄을 `config shell=zsh.*shell_config=on`
꼴로 grep하고 `net/check.sh:256`이 `config shell=.* net=dhcp`로 본다. 뒤에
붙이면 그 아홉이 한 글자도 안 바뀐다.

```zig
    var ntp_buf: [config.NTP_ARG_MAX]u8 = undefined;
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s} net={s} ntp={s}\n",
        .{
            // … 기존 일곱 …
            @tagName(cfg.net),
            cfg.ntp.arg(&ntp_buf),
        },
    );
```

- [ ] Step 6: `config_test.zig`를 넓힌다

`expect`의 필드 비교에 한 줄을 더한다. 안 더하면 새 키의 검사가 아무것도
안 보고 초록이 뜬다 — HI-M2가 같은 자리에서 배운 것이고 그 주석이 이미
파일에 있다.

```zig
        got.shell_config == want.shell_config and got.net == want.net and
        got.ntp.eql(want.ntp))
```

그리고 `main()`에 절을 하나 더한다.

```zig
    // ── TS-M1: 여덟째 키 ntp ────────────────────────────────────────────
    //
    // 앞의 일곱과 다른 유일한 키다(design 확인 9). 값 셋 중 하나가 자유
    // 문자열이라 `stringToEnum` 화이트리스트가 안 서고, 그래서 이 저장소에
    // 처음으로 주소 파서가 들어왔다.
    try expect("ntp=off", .{ .ntp = .off });
    try expect("ntp=dhcp", .{ .ntp = .dhcp });
    try expect("ntp=10.0.2.2", .{ .ntp = .{ .server = .{ 10, 0, 2, 2 } } });
    try expect("ntp=255.255.255.255", .{ .ntp = .{ .server = .{ 255, 255, 255, 255 } } });
    try expect("ntp=0.0.0.0", .{ .ntp = .{ .server = .{ 0, 0, 0, 0 } } });
    // 공백은 이미 떼어져서 온다(`parse`가 값의 양쪽을 trim한다).
    try expect("ntp = 10.0.2.2 ", .{ .ntp = .{ .server = .{ 10, 0, 2, 2 } } });
    // 모르는 값은 기본값에 머문다. 다른 일곱 키와 같은 규칙이다.
    try expect("ntp=pool.ntp.org", .{ .ntp = .off });
    try expect("ntp=10.0.2", .{ .ntp = .off });
    try expect("ntp=10.0.2.2.2", .{ .ntp = .off });
    try expect("ntp=10.0.2.256", .{ .ntp = .off });
    try expect("ntp=10.0.2.-1", .{ .ntp = .off });
    try expect("ntp=10.0.2.0002", .{ .ntp = .off });
    try expect("ntp=", .{ .ntp = .off });
    // 다른 키와 함께 있어도 서로 안 흔든다.
    try expect("net=dhcp\nntp=10.0.2.2\n", .{ .net = .dhcp, .ntp = .{ .server = .{ 10, 0, 2, 2 } } });

    // arg()가 왕복하는가. 씨앗 파일이 이 함수로 써지므로, 왕복이 깨지면
    // init이 만든 tars.conf를 init 자신이 다시 못 읽는다.
    try expectNtpRoundTrip(.off, "off");
    try expectNtpRoundTrip(.dhcp, "dhcp");
    try expectNtpRoundTrip(.{ .server = .{ 10, 0, 2, 2 } }, "10.0.2.2");
    try expectNtpRoundTrip(.{ .server = .{ 255, 255, 255, 255 } }, "255.255.255.255");
```

그 헬퍼는 파일 끝에 둔다.

```zig
/// `arg()`가 만든 글자를 `parse()`가 도로 읽는가. 씨앗 파일(`save`)이
/// `arg()`로 써지고 다음 부팅이 `parse()`로 읽으므로, 이 왕복이 이 키가
/// 부팅을 넘는 유일한 길이다.
fn expectNtpRoundTrip(value: config.Ntp, want_text: []const u8) !void {
    var buf: [config.NTP_ARG_MAX]u8 = undefined;
    const text = value.arg(&buf);
    if (!std.mem.eql(u8, text, want_text)) {
        std.debug.print("FAIL: ntp arg is [{s}], want [{s}]\n", .{ text, want_text });
        return error.BadNtpArg;
    }
    const back = config.Ntp.parse(text) orelse {
        std.debug.print("FAIL: ntp arg [{s}] does not parse back\n", .{text});
        return error.NtpRoundTripFailed;
    };
    if (!back.eql(value)) {
        std.debug.print("FAIL: ntp round trip changed the value at [{s}]\n", .{text});
        return error.NtpRoundTripChanged;
    }
}
```

- [ ] Step 7: 검사를 돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test' 2>&1 | tail -20
```

기대: `PASS` 여섯 개. 여기서 Task 2 Step 2가 함께 초록이 된다.

## Task 4 — 자식이 묻고 시계를 뛴다

파일: `init/src/power.zig` · `init/src/sntp.zig` · `init/src/main.zig`

- [ ] Step 1: `power.zig`에 `resetToDefault()`를 더한다

`install()` 바로 뒤에 넣는다. 정책을 세우는 함수와 되돌리는 함수가 나란히
있어야 읽는 사람이 짝을 본다.

```zig
/// `fork`한 자식이 PID 1의 시그널 정책을 물려받지 않게 되돌린다.
///
/// 왜 필요한가. `install()`이 단 핸들러는 죽는 대신 정수 하나를 남기는
/// 것이고(`onSignal` → `request`), 그 정수를 꺼내 실제로 종료를 시작하는
/// 것은 `main.zig`의 감독 루프다. 자식에는 그 루프가 없으므로 물려받은
/// 핸들러는 "SIGTERM을 무시한다"와 같은 뜻이 된다.
///
/// `net.zig`의 dhcpcd 자식은 이 함수가 필요 없다 — `execve`가 다뤄진
/// 시그널을 전부 `SIG_DFL`로 되돌려 주기 때문이다. `execve`를 안 하는
/// 자식만 손으로 해야 하고, 지금 그런 자식은 `sntp.zig`의 것 하나다.
///
/// 안 부르면 증상이 종료에서 난다. `shutdown()`의 SIGTERM에 그 자식만
/// 안 죽고 유예 3초를 다 써서 `grace period expired`가 찍히고, SL-M2가
/// 세운 음성 검사가 그것을 실패로 판정한다. 원인(시계)과 증상(종료)이
/// 멀어서 찾기 어려운 종류다.
pub fn resetToDefault() void {
    const act: linux.Sigaction = .{
        .handler = .{ .handler = linux.SIG.DFL },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    // 실패해도 할 일이 없다. 자식이고, 여기서 로그를 찍으면 부모의 로그에
    // 섞여서 읽는 사람을 헷갈리게 한다.
    _ = linux.sigaction(.TERM, &act, null);
    _ = linux.sigaction(.INT, &act, null);
}
```

- [ ] Step 2: `sntp.zig`에 나머지를 더한다

Task 2에서 만든 파일의 끝에 붙인다.

```zig
/// 답을 기다리는 시간. 짧게 잡는 이유는 재시도가 있기 때문이다 — 한 번에
/// 오래 기다리는 것보다 여러 번 묻는 편이 주소가 늦게 붙는 경우를 잘 덮는다.
const RECV_TIMEOUT_SECONDS: isize = 2;

/// 몇 번까지 묻는가.
///
/// 이 수가 부팅 시간에 영향을 안 준다는 것이 결정 3의 덤이다. 부모는 이미
/// 다음 줄로 갔고, 이 루프는 자식 안에서만 돈다.
///
/// 30인 근거는 dhcpcd다. `sntp.sync()`가 불리는 시점은 dhcpcd가 방금
/// 태어난 직후라 아직 주소가 없고, NW-M2 실측 17이 `started dhcpcd`와 실제
/// 리스 사이에 시리얼 로그 3500줄이 있다고 쟀다. 한 회가 최악 3초이므로
/// 30회면 약 90초를 덮는다 — `net/check.sh`의 리스 대기 상한 60초보다 길다.
const MAX_TRIES: usize = 30;

/// 실패한 회차 뒤에 쉬는 시간. 답이 없어서 실패한 회차는 이미 2초를
/// 기다렸으므로 안 쉰다 — 이 쉼은 `sendto`가 즉시 실패한 회차의 것이다.
const RETRY_SLEEP_MS: isize = 1000;

/// dhcpcd의 hook이 option 42를 적어 두는 자리(design 결정 4).
/// M1은 이 파일을 읽기만 한다. 만드는 것은 M2의 hook이다.
const SERVER_FILE: [:0]const u8 = "/run/tars/ntp_servers";

/// NTP의 포트. TS-M0 실측 1이 컨테이너에서 이 포트를 실제로 열었으므로
/// 게이트도 여기를 쓴다 — 주소에 포트를 적는 문법이 필요 없다(위험 4가
/// 닫혔다).
const NTP_PORT: u16 = 123;

/// devices.zig·power.zig에도 같은 함수가 있다. `failed`와 같은 이유로
/// 공용 모듈을 만들지 않는다.
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
    // 실패하면 0을 찍는다. 로그의 "was" 값이 진단용이라 여기서 돌아갈
    // 이유가 없다.
    const had = if (failed(linux.clock_gettime(.REALTIME, &before)) == null)
        @as(i64, before.sec)
    else
        0;

    const ts = linux.timespec{ .sec = @intCast(t.sec), .nsec = @intCast(t.nsec) };
    if (failed(linux.clock_settime(.REALTIME, &ts))) |e| {
        std.debug.print("tars-init: cannot step the clock (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    // net/check.sh가 이 줄을 grep한다. 숫자가 stub이 정한 값과 정확히
    // 같아야 하므로 형식을 바꾸는 사람은 그 체인도 함께 본다.
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
/// (plan 결정 M1-D) — 기다리는 것은 M2가 더한다.
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
        // 첫 줄이어야 한다(plan 결정 M1-A). `execve`를 안 하는 자식이라
        // 부모의 SIGTERM 핸들러를 그대로 갖고 있고, 그대로 두면 전원을 끌 때
        // 이 자식만 안 죽는다.
        power.resetToDefault();
        askAndStep(server);
        linux.exit(0);
    }
    // net/check.sh가 이 줄을 grep하지는 않는다. `net.zig`의
    // `started dhcpcd on eth0 (pid N)`과 짝이 되는 자리이고, 자식이 아무
    // 말도 못 하고 죽은 회차에 "태어나기는 했다"를 남긴다.
    std.debug.print("tars-init: sntp child (pid {d}) will ask {d}.{d}.{d}.{d}\n", .{
        pid, server[0], server[1], server[2], server[3],
    });
}
```

- [ ] Step 3: `main.zig`가 부른다

`net.bringUp(cfg.net, envp);` 바로 다음 줄이다.

```zig
const sntp = @import("sntp.zig");
```

```zig
    // TS-M1. `net.bringUp` 다음인 것이 이 한 줄의 유일한 제약이다 —
    // `ntp=dhcp`가 읽는 파일을 쓰는 것이 dhcpcd의 hook이고, `ntp=<주소>`도
    // 링크가 올라와 있어야 나간다. 그리고 여기서 fork한 자식은 부모를 한
    // 순간도 안 세운다(design 결정 3) — 주소가 아직 없어서 첫 `sendto`가
    // 실패하는 것이 정상이고, 자식이 그것을 재시도로 덮는다.
    sntp.sync(cfg.net, cfg.ntp);
```

- [ ] Step 4: 빌드와 호스트 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test' 2>&1 | tail -20
```

기대: 조용히 끝나고 `PASS` 여섯.

- [ ] Step 5: 더한 줄과 지운 줄을 센다

```bash
git diff --stat
git diff | grep '^-'
```

지운 줄은 로그 형식 한 줄(`config shell=…`)과 `save`의 인자 목록 근처뿐이어야
한다.

## Task 5 — 게이트의 상대: `net/sntp_stub.pl`

파일: `net/sntp_stub.pl` (새 파일)

TS-M0의 `/tmp/ts/stub.pl`을 저장소로 옮긴 것이다. 다른 점이 셋이다 —
답하는 시각을 인자로 받고, 평문 갈래를 없애고(게이트에는 probe A가 없다),
표지를 `TSM0-STUB`에서 `sntp-stub`으로 바꾼다.

- [ ] Step 1: 파일을 만든다

```perl
#!/usr/bin/perl
# net/check.sh의 부팅 A가 쓰는 상대. 컨테이너 안에서 배경으로 돌면서 UDP
# 한 포트를 듣고, 받은 요청마다 고정된 시각으로 답한다.
#
# 왜 perl인가. 이 컨테이너에는 nc·ncat·socat·python3·busybox가 하나도 없고
# (NW-M0), bash의 /dev/udp는 거는 것만 된다. QEMU의 guestfwd는 TCP 전용이라
# TS에는 못 쓴다. perl의 IO::Socket::INET이 그 자리를 메운다(TS 확인 6).
#
# 왜 고정된 시각인가. 게스트의 벽시계는 NTP 없이도 이미 맞다 — 커널이
# CMOS를 읽고 QEMU가 그것을 호스트 시각으로 채운다(TS-M0 실측 4). 그래서
# "맞아졌다"로는 판정할 수 없고, 현실에 있을 수 없는 값으로만 갈린다.
#
# 미래여야 하는 이유는 mtime이다(design 위험 2). 과거로 뛰면 게이트가 만든
# 파일의 시각이 뒤집혀서 다른 자리에서 이상한 일이 날 수 있다.
use strict;
use warnings;
use IO::Socket::INET;
use Socket;    # sockaddr_in·inet_ntoa. IO::Socket::INET은 이것을 자기
               # 네임스페이스로만 들여온다.

$| = 1;    # 배경으로 돌므로 버퍼를 안 쌓는다. 안 하면 로그가 끝에 몰린다.

my $port = $ARGV[0] // 123;
my $fixed_unix = $ARGV[1] // 1930367167;    # 2031-03-04T05:06:07Z

# NTP의 초는 1970이 아니라 1900부터 센다(design 결정 11).
my $NTP_EPOCH = 2208988800;

my $sock = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'udp',
) or die "sntp-stub: cannot bind udp/$port: $!\n";

printf "sntp-stub: listening on udp/%d, answering unix %d (%s)\n",
    $port, $fixed_unix, scalar(gmtime($fixed_unix));

while (1) {
    my $req;
    # 메서드가 아니라 내장 함수 꼴로 부른다. IO::Socket에는 recv 메서드가
    # 없어서 메서드 꼴은 버전에 따라 조용히 안 돈다.
    my $from = recv($sock, $req, 512, 0);
    unless (defined $from) {
        print "sntp-stub: recv failed: $!\n";
        next;
    }
    my ($fport, $faddr) = sockaddr_in($from);
    my $len = length($req);
    printf "sntp-stub: recv %d bytes from %s:%d\n", $len, inet_ntoa($faddr), $fport;

    if ($len != 48) {
        # 게이트에서 48이 아닌 것이 오는 일은 없어야 한다. 왔다면 우리
        # 코드가 잘못 만든 것이고, 조용히 답하면 그 사실이 묻힌다.
        printf "sntp-stub: ignoring a %d-byte datagram (we only answer 48)\n", $len;
        next;
    }

    # RFC 4330의 서버 응답. 바이트 배치는 이렇다.
    #   0      LI(0) VN(4) Mode(4)      → 0x24
    #   1      stratum 1 (primary)
    #   2      poll 4
    #   3      precision -6 (부호 있는 바이트)
    #   4-7    root delay 0
    #   8-11   root dispersion 0
    #   12-15  reference ID
    #   16-23  reference timestamp
    #   24-31  originate timestamp  ← 요청의 transmit timestamp를 그대로
    #   32-39  receive timestamp
    #   40-47  transmit timestamp
    #
    # 24-31을 요청에서 그대로 베끼는 것이 design 결정 12의 마지막 줄이 보는
    # 자리다. init의 parseReply가 이 여덟 바이트를 자기 nonce와 대조한다.
    #
    # 템플릿이 CCCc다. 넷째가 부호 있는 바이트(precision -6)이고 앞의 셋이
    # 부호 없는 것이다. CCcC로 쓰면 결과 바이트는 두 보수라 같지만 perl이
    # `Character in 'C' format wrapped`를 찍는다 — TS-M0의 self-test가
    # 이것을 잡았고 `perl -c`는 문법만 보므로 못 잡는다.
    my $orig = substr($req, 40, 8);
    my $ts = pack('NN', $fixed_unix + $NTP_EPOCH, 0);
    my $reply = pack('CCCc', 0x24, 1, 4, -6)
              . pack('NN', 0, 0)
              . 'TARS'
              . $ts . $orig . $ts . $ts;
    send($sock, $reply, 0, $from) or print "sntp-stub: send failed: $!\n";
    print "sntp-stub: sent 48 bytes (origin echoed)\n";
}
```

- [ ] Step 2: 문법을 먼저 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  perl -c net/sntp_stub.pl
```

기대: `net/sntp_stub.pl syntax OK`

- [ ] Step 3: 컨테이너 안에서 한 번 왕복시킨다 (QEMU 없이)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  perl net/sntp_stub.pl 123 1930367167 & STUB=$!
  sleep 1
  perl -MIO::Socket::INET -e "
    my \$s = IO::Socket::INET->new(PeerAddr=>q(127.0.0.1), PeerPort=>123, Proto=>q(udp)) or die;
    my \$req = pack(qq(C), 0x23) . (qq(\x00) x 39) . q(NONCE123);
    \$s->send(\$req);
    my \$r; \$s->recv(\$r, 512);
    printf qq(len=%d mode=%d stratum=%d origin=[%s] transmit=%d\n),
      length(\$r), ord(substr(\$r,0,1)) & 7, ord(substr(\$r,1,1)),
      substr(\$r,24,8), unpack(qq(N), substr(\$r,40,4));
  "
  kill $STUB
'
```

기대:

```
len=48 mode=4 stratum=1 origin=[NONCE123] transmit=4139355967
```

`4139355967`이 `1930367167 + 2208988800`이다. 이 값이 다르면 아래 게이트
판정이 전부 어긋난다 — QEMU를 띄우기 전에 여기서 잡는다(TS-M0이 같은
self-test로 `pack` 버그를 잡았다).

## Task 6 — 부팅 A의 설정 디스크

파일: `net/make_disk.sh`

지금 이 스크립트는 이미지 하나를 굽는다. 둘을 굽게 고친다 — 기존
`out/net.img`(검사 1~16이 쓰는 것)와 새 `out/net-ntp.img`(부팅 A의 것)다.

디스크를 나누는 이유는 격리다. 한 디스크에 `ntp=`를 더하면 검사 1~16이
전부 시계가 2031년인 게스트에서 돌게 되고, 그 열여섯이 실패하는 날 원인이
"받는 길"인지 "시계"인지 안 갈린다. 부팅이 하나 늘어나는 대신 실패가
갈린다(design 위험 5가 그 비용을 이미 계산했다).

- [ ] Step 1: 파일을 이렇게 바꾼다

`SIZE` 아래부터 끝까지를 교체한다.

```bash
SIZE=16M

# TS-M1. 부팅 A가 물을 주소를 체인이 정해서 넘긴다. 기본값을 두는 이유는
# 이 스크립트를 손으로 돌리는 사람 때문이고, 게이트는 언제나 넘긴다 —
# 그래야 이 주소를 아는 자리가 net/check.sh 한 곳이다.
NTP_SERVER="${1:-10.0.2.2}"

mkdir -p ../out

# 이미지 하나를 굽는다. 인자가 (경로, 라벨, tars.conf 내용)이다.
#
# debugfs로 미리 담는 것이 NW-M2의 수법이다. 마운트도 loop 장치도 특권도
# 필요 없다 — 이미지 파일을 파일로 읽고 쓸 뿐이라 이 게이트가 아무 특권
# 없이 도는 성질을 안 버린다.
#
# 라벨 접두사가 tars- 여야 한다. init/src/storage.zig의 LABEL_PREFIX가
# 그것이고(RM-M2), 정확히 하나로 박지 않은 이유가 게이트 디스크가 여럿이기
# 때문이다.
bake() {
  local img="$1" label="$2" body="$3"
  local conf
  conf="$(mktemp)"
  printf '%s' "$body" > "$conf"

  rm -f "$img"
  truncate -s "$SIZE" "$img"
  mkfs.ext2 -F -q -m 0 -L "$label" "$img"
  debugfs -w -R "write ${conf} tars.conf" "$img" 2>&1 | grep -v '^debugfs' || true
  rm -f "$conf"

  echo "make_disk: created ${img} (${SIZE}, ext2, label ${label})"
}

# 검사 1~16이 쓰는 디스크. 한 줄만 적는다 — 나머지 일곱 키가 기본값이고,
# 그래서 이 부팅의 셸이 fish이며 체인의 화면 좌표가 다른 체인들과 같다.
#
# init이 이 파일을 읽으면 save()를 안 부른다 — load가 null이 아니기
# 때문이다. 즉 이 디스크의 tars.conf는 부팅 뒤에도 이 줄 그대로다.
bake ../out/net.img tars-net 'net=dhcp
'

# TS-M1. 부팅 A가 쓰는 디스크. 위의 것과 다른 것이 ntp 한 줄뿐이다.
#
# 라벨을 tars-ntp로 다르게 두는 이유는 진단이다. 두 디스크가 같은 라벨이면
# 엉뚱한 이미지를 물린 회차에 게스트 로그가 똑같이 생긴다.
bake ../out/net-ntp.img tars-ntp "net=dhcp
ntp=${NTP_SERVER}
"
```

- [ ] Step 2: 돌려 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd net && ./make_disk.sh 10.0.2.2 && ls -la ../out/*.img'
```

기대: `make_disk: created` 두 줄과 16MB 이미지 둘.

- [ ] Step 3: 담긴 내용을 눈으로 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  debugfs -R "cat tars.conf" out/net-ntp.img
```

기대: `net=dhcp`와 `ntp=10.0.2.2` 두 줄.

## Task 7 — `net/check.sh`에 부팅 A

파일: `net/check.sh`

검사 셋이 는다. 열일곱이 설정, 열여덟이 init 로그, 열아홉이 화면이다.

- [ ] Step 1: 파일 머리에 상수를 더한다

`REVERSE_PORT`·`GUEST_REVERSE_PORT` 블록 바로 뒤에 넣는다.

```bash
# ── TS-M1 ───────────────────────────────────────────────────────────────
#
# 부팅 A가 쓰는 것들이다. 이 체인에서 두 번째 QEMU이고, 앞의 열여섯 검사가
# 끝나고 첫 게스트가 꺼진 뒤에 뜬다.
#
# 45467은 monitor 대역(45455~45464 · 45471)과 IN이 쓰는 둘(45465 · 45466)
# 밖이다.
NTP_MONITOR_PORT=45467

# 게스트가 시각을 묻는 자리. SLIRP에서 호스트(=이 컨테이너)를 가리키는
# 주소이고, TS-M0 실측 2가 여기로 간 UDP가 실제로 컨테이너에 닿는 것을 봤다.
NTP_SERVER=10.0.2.2
NTP_PORT=123

# stub이 답하는 시각. 이 두 값은 서로 맞아야 한다 — 1930367167이
# 2031-03-04T05:06:07Z다.
#
# 현실에 있을 수 없는 값이어야 한다는 것이 design 결정 6이고, 그것이
# 취향이 아니라 필수라는 것을 TS-M0 실측 4가 만들었다 — 게스트의 벽시계는
# NTP 없이도 이미 호스트 시각이라 "맞아졌다"로는 아무것도 못 가린다.
STUB_UNIX=1930367167
STUB_YEAR=2031

LOGA="$(mktemp)"
STUBLOG="$(mktemp)"
QEMU_PID_A=""
STUB_PID=""
```

- [ ] Step 2: `cleanup`을 넓힌다

```bash
cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  # TS-M1. 부팅 A의 게스트와 stub. 순서에 뜻은 없지만 게스트를 먼저 보내는
  # 편이 stub 로그의 끝이 깔끔하다.
  if [ -n "$QEMU_PID_A" ] && kill -0 "$QEMU_PID_A" 2>/dev/null; then
    kill "$QEMU_PID_A" 2>/dev/null || true
    wait "$QEMU_PID_A" 2>/dev/null || true
  fi
  if [ -n "$STUB_PID" ] && kill -0 "$STUB_PID" 2>/dev/null; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
  rm -f "$PAYLOAD"
}
```

- [ ] Step 3: `fail`이 stub 로그도 보여 주게 한다

`--- last 60 lines ---` 바로 앞에 넣는다.

```bash
  # TS-M1. 부팅 A에서 죽었으면 이쪽이 진단의 절반이다 — 게스트가 보낸
  # datagram이 여기까지 왔는지는 게스트 로그만으로는 안 갈린다.
  if [ -s "$STUBLOG" ]; then
    echo "--- sntp stub ---"
    tail -n 20 "$STUBLOG"
  fi
```

- [ ] Step 4: 부팅 A를 더한다

첫 게스트의 유예 음성 검사(`grace period expired`) 바로 뒤, `echo "PASS"`
앞에 넣는다.

```bash
# ══ 부팅 A: 우리 코드가 시계를 뛴다 (TS-M1) ═══════════════════════════
#
# 여기서부터 게스트가 새로 뜬다. 앞의 열여섯과 디스크가 다르고
# (out/net-ntp.img — net=dhcp에 ntp=10.0.2.2 한 줄이 더 있다) 상대가 하나
# 더 있다(컨테이너에서 도는 perl stub).
#
# 왜 앞의 부팅에 얹지 않는가. 얹으면 검사 1~16이 전부 시계가 2031년인
# 게스트에서 돌고, 그 열여섯이 실패하는 날 원인이 "받는 길"인지 "시계"인지
# 안 갈린다. 부팅 하나를 더 치르고 실패를 가른다.
#
# 이 부팅이 design 실측 7이 남긴 숙제도 함께 답한다. TS-M0의 하네스는
# 콘솔 셸만 써서 "렌더가 살아 있다"와 "화면에 할 일이 없다"가 같은 값이었다
# (TR-M2의 needs_redraw 문지기). 이 부팅은 시계를 뛴 뒤에 화면에 타이핑을
# 하므로, 검사 19가 서는 것 자체가 렌더가 점프를 견뎠다는 증거다.
echo "=== booting again with ntp=${NTP_SERVER} ==="

# stub을 먼저 띄운다. 게스트가 부팅하는 동안 이미 듣고 있어야 한다.
perl ./sntp_stub.pl "$NTP_PORT" "$STUB_UNIX" > "$STUBLOG" 2>&1 &
STUB_PID=$!
sleep 1
if ! kill -0 "$STUB_PID" 2>/dev/null; then
  echo "FAIL: the sntp stub died at startup"
  cat "$STUBLOG"
  exit 1
fi
echo "the sntp stub is listening on udp/${NTP_PORT}"

# type_keys·wait_for_screen·fail이 보는 것은 전역 $LOG다. 이 체인은 이제
# 부팅이 둘이고, 그 둘을 잇는 자리가 이 한 줄이다(config/check.sh의
# edit_config_in_guest가 같은 모양이다).
LOG="$LOGA"

# 앞의 QEMU 줄에서 hostfwd·guestfwd를 뺀 것이다. 이 부팅은 TCP를 하나도
# 안 쓴다 — 나가는 UDP는 SLIRP이 아무 설정 없이 내보낸다(TS-M0 실측 2).
qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="${REPO_ROOT}/out/net-ntp.img",if=virtio,format=raw \
  -serial file:"$LOGA" \
  -monitor tcp:127.0.0.1:${NTP_MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID_A=$!

READY=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOGA" >/dev/null; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID_A" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || fail "the ntp guest never rendered a prompt"

# ── 검사 17: 설정이 읽혔고 ntp가 실효값인가 ───────────────────────────
# 검사 3과 같은 자리를 새 키에 대해 한 번 더 본다. 이것이 없으면 아래 둘이
# 실패했을 때 "디스크를 안 물었다"와 "코드가 틀렸다"가 안 갈린다.
if ! grep -aE "tars-init: config shell=.* net=dhcp ntp=${NTP_SERVER}" "$LOGA" >/dev/null; then
  fail "the ntp config disk did not reach init" "tars-init: config shell="
fi
echo "the guest read ntp=${NTP_SERVER} off the config disk"

# ── 검사 18: 우리 코드가 시계를 뛰었나 ────────────────────────────────
# 이 체인에서 우리 코드가 하는 일 전부가 이 한 줄이다. 숫자가 stub이 정한
# 값과 정확히 같아야 한다 — 그래야 "시계가 움직였다"가 아니라 "이 서버가
# 말한 값으로 움직였다"가 된다.
#
# 기다리는 이유. 자식은 dhcpcd가 리스를 받기 전에 태어나므로 첫 sendto가
# ENETUNREACH로 실패하고 재시도한다(sntp.zig의 MAX_TRIES). 즉 이 줄은 리스
# 뒤에 나오고, 그 대기가 검사 5와 같은 크기다.
STEPPED=0
for _ in $(seq 1 90); do
  if grep -a "tars-init: clock stepped to ${STUB_UNIX}" "$LOGA" >/dev/null; then
    STEPPED=1; break
  fi
  if ! kill -0 "$QEMU_PID_A" 2>/dev/null; then break; fi
  sleep 1
done
[ "$STEPPED" = "1" ] || fail "init never stepped the clock to ${STUB_UNIX}" \
  "tars-init: sntp" "tars-init: clock"
echo "init stepped the clock to ${STUB_UNIX}"

# ── 검사 19: 사람이 그것을 볼 수 있나 ─────────────────────────────────
# 검사 18과 같은 사실을 다른 자리에서 묻는다. 저쪽은 우리 코드가 자기
# 입으로 한 말이고 이쪽은 게스트의 date가 실제로 무엇을 찍는가다 —
# clock_settime이 성공을 돌려주고도 시계가 안 움직이는 경우가 갈린다.
#
# 화면 판정이 서려면 먼저 monitor에 붙어야 한다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${NTP_MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the ntp guest's QEMU monitor" \
  "terminal: screen>"

# 판정 글자가 명령줄에 없어야 한다(NW-M3 실측 2). wait_for_screen은 마지막
# 프레임이 아니라 로그 전체의 screen> 줄을 보므로 친 명령의 에코도 화면이다.
# `date`를 그냥 치면 그 네 글자가 화면에 남고, 연도는 출력에만 생긴다 —
# 그래서 echo와 명령 치환으로 tsyear=NNNN을 만든다.
#
# -u가 중요하다(design 결정 7). TS-M3이 시간대를 넣으면 지역 시간의 연도가
# 12월 31일 밤에 한 해 어긋날 수 있고, 그러면 이 판정이 일 년에 몇 시간
# 흔들린다.
#
# 키 이름 셋이 새로 쓰인다 — +가 shift-equal, %가 shift-5, Y가 shift-y다.
# $( 와 ) 는 검사 10·12·14가 이미 쓰는 것과 같다.
echo "=== typing 'echo tsyear=\$(date -u +%Y)' ==="
type_keys e c h o spc t s y e a r equal \
  shift-4 shift-9 d a t e spc minus u spc shift-equal shift-5 shift-y shift-0 ret

if ! wait_for_screen "tsyear=${STUB_YEAR}"; then
  fail "the guest's clock does not show ${STUB_YEAR} on screen" "terminal: screen>"
fi
echo "the guest shows ${STUB_YEAR} — the render survived the jump too"

# ── 부팅 A를 끈다 ─────────────────────────────────────────────────────
echo "=== sending system_powerdown to the ntp guest ==="
echo "system_powerdown" >&3
sleep 0.3
exec 3<&-
exec 3>&-

GONE_A=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID_A" 2>/dev/null; then GONE_A=1; break; fi
  sleep 1
done
[ "$GONE_A" = "1" ] || fail "the ntp guest did not switch itself off" \
  "tars-init: shutdown requested"

# SL-M2가 세운 것을 이 부팅에도 건다. 여기서 이 검사가 갖는 뜻이 앞의
# 부팅보다 하나 더 크다 — 이 게스트에는 SNTP 자식이 있었고, 그 자식은
# execve를 안 해서 부모의 SIGTERM 핸들러를 물려받을 뻔했다(plan 결정 M1-A).
# power.resetToDefault()를 지우면 여기가 빨간불이 된다.
if grep -a "grace period expired" "$LOGA" >/dev/null; then
  fail "something outlived SIGTERM in the ntp guest" "grace period expired"
fi

# stub을 보낸다. 여기서 명시적으로 죽이는 이유는 로그 마지막 줄까지 사람이
# 볼 수 있게 하기 위해서다(trap도 같은 일을 하지만 그때는 출력이 끝난 뒤다).
kill "$STUB_PID" 2>/dev/null || true
wait "$STUB_PID" 2>/dev/null || true
STUB_PID=""
echo "the sntp stub answered $(grep -ac 'sent 48 bytes' "$STUBLOG") request(s)"
```

- [ ] Step 5: `make_disk.sh` 호출에 주소를 넘긴다

체인 머리의 빌드 절에서 한 글자를 바꾼다.

```bash
if ! ./make_disk.sh "$NTP_SERVER"; then
```

`NTP_SERVER`가 그 줄보다 위에서 정의돼 있어야 한다 — Step 1의 상수 블록을
빌드 절보다 앞에 두거나, `make_disk.sh` 호출을 상수 블록 뒤로 옮긴다.
지금 파일에서는 상수들이 빌드 절보다 아래에 있으므로 상수 블록 전체를
`source ../gate_lib.sh` 바로 뒤로 올린다.

- [ ] Step 6: 체인 머리의 설명 주석을 넓힌다

파일 맨 위 주석의 끝(IN-M1을 설명하는 문단 뒤)에 문단을 하나 더한다.

```bash
# TS-M1이 부팅을 하나 더 얹었다. 앞의 열여섯이 "바이트가 오간다"였다면
# 이쪽은 "그 바이트가 시계가 된다"다:
#
#   컨테이너의 perl stub이 UDP 123을 듣는다
#   설정 디스크의 ntp=10.0.2.2 → init이 fork한 자식이 48바이트를 보낸다
#   → SLIRP가 그것을 컨테이너에 넘긴다(TS-M0 실측 2)
#   → 자식이 답의 nonce를 대조하고 clock_settime으로 시계를 뛴다
#   → 게스트의 date가 2031년을 찍는다
#
# 이 부팅에서 우리 코드는 init/src/sntp.zig 하나다. 상대는 우리가 쓴 perl
# 스무 줄이고, 그 둘 사이의 모든 것(SLIRP · 커널의 UDP · dhcpcd의 주소)은
# 앞의 열여섯이 이미 따로 증명한 것들이다.
```

## Task 8 — 체인을 돌린다

- [ ] Step 1: 빌드부터 돌린다 (약 2~3분)

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash net/check.sh 2>&1 | tail -40
```

기대: 검사 19까지 초록, 마지막이 `PASS`.

- [ ] Step 2: 첫 회가 깨졌으면 이 순서로 가른다

| 증상 | 먼저 볼 것 |
|---|---|
| 검사 17에서 죽는다 | `debugfs -R "cat tars.conf" out/net-ntp.img`. 디스크가 안 구워졌거나 라벨이 달라 게스트가 다른 디스크를 물었다 |
| 검사 18에서 죽고 stub 로그가 비었다 | 게스트가 보낸 것이 안 왔다. 게스트 로그의 `tars-init: sntp send failed`를 본다 — errno 101(ENETUNREACH)이면 리스가 30회 안에 안 온 것이다 |
| 검사 18에서 죽고 stub 로그에 `recv`가 있다 | 답은 왔는데 우리가 버렸다. 게스트 로그의 `sntp reply rejected (…)`가 이유를 이름으로 말한다 |
| 검사 19에서 죽는다 | 시계는 뛰었는데 화면이 안 따라왔다. 실측 7이 남긴 숙제가 현실이 된 것이고, 그 자체가 큰 실측이다 |
| 검사 1~16 중 하나가 죽는다 | 이 milestone과 무관한 자리다. `git stash`로 갈라서 확인한다 |

- [ ] Step 3: 게스트가 무엇을 말했는지 한 번 통째로 읽는다

초록이어도 읽는다. 자식이 몇 번 재시도했는지가 M2가 `-o ntp_servers`를
붙일 때 쓸 값이다.

```bash
grep -a "tars-init: sntp\|tars-init: clock\|tars-init: ntp" /tmp/<부팅 A 로그>
```

체인이 `mktemp`를 쓰므로 경로는 실행할 때 `LOGA`를 찍게 한 줄을 임시로
더하거나, `docker run`을 `-v /tmp/ts:/tmp/ts`로 띄우고 `LOGA=/tmp/ts/boota.log`로
고정해서 본다. 값을 적었으면 되돌린다.

- [ ] Step 4: 체인 단독 시간을 Task 0 Step 2와 비교한다

design 위험 5가 예상한 것이 부팅 하나에 12~13초다. 증가분이 그보다 크면
자식의 재시도가 리스를 오래 기다린 것이고, 그 값이 M2의 대기 설계에 쓰인다.

## Task 9 — 반사실: stub이 없으면 죽는가

- [ ] Step 1: stub을 안 띄우는 사본을 만든다

저장소 파일은 안 고친다. `/tmp` 사본을 `-v`로 덮어씌우는 것이 이 저장소의
음성 확인 방법이다(SD가 세웠다) — 되돌리는 것을 잊는 경로가 없다.

```bash
mkdir -p /tmp/ts
sd 'perl \./sntp_stub\.pl' 'true skip-stub' net/check.sh > /tmp/ts/check_nostub.sh
grep -n "skip-stub" /tmp/ts/check_nostub.sh
```

기대: 한 줄이 잡힌다. `perl ... &`가 `true skip-stub ... &`가 되어 배경
프로세스가 즉시 끝난다 — `kill -0` 검사가 그것을 잡을 수도 있으므로, 잡히면
증상이 "stub이 startup에서 죽었다"이고 그것도 유효한 반사실이다. 검사 18까지
가게 하려면 `true` 대신 `sleep 600`으로 바꾼다.

```bash
sd 'perl \./sntp_stub\.pl' 'sleep 600 --' net/check.sh > /tmp/ts/check_nostub.sh
```

- [ ] Step 2: 그 사본으로 체인을 돌린다 (약 4~5분)

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/ts/check_nostub.sh:/workspace/net/check.sh \
  -w /workspace tars-devcontainer bash net/check.sh 2>&1 | tail -30
```

기대: 검사 1~16과 17이 초록이고 검사 18에서

```
FAIL: init never stepped the clock to 1930367167
```

그리고 진단에 `tars-init: sntp got no answer (errno 11)`가 서른 줄 보인다.
errno 11이 EAGAIN이고 그것이 `SO_RCVTIMEO`가 실제로 걸려 있다는 증거다 —
안 걸려 있으면 자식이 첫 회에 영영 매달려서 그 줄이 하나도 안 나온다.

- [ ] Step 3: 겨냥한 자리에서 죽었는지 확인한다

검사 17보다 앞에서 죽었으면 이 반사실이 아무것도 증명하지 못한 것이다
(SL-M2가 `.HUP` 반사실에서 겪은 것과 같은 함정 — 겨냥한 검사가 아니라 앞의
검사에 걸렸다). 그러면 사본을 다시 만들어 stub만 정확히 없앤다.

- [ ] Step 4: 저장소가 안 바뀐 것을 확인한다

```bash
git status --short net/check.sh
```

기대: 아무것도 안 나온다(마운트로 덮었으므로).

## Task 10 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 절을 더한다

`## Milestone` 앞, `## TS-M0이 실행으로 증명한 것`의 뒤에 넣는다.

```markdown
## TS-M1이 실행으로 증명한 것

(실측 9부터 번호를 이어 붙인다. 숫자는 로그에서 그대로 옮긴다.)
```

적을 것이 최소 다섯이다.

1. 부팅 A가 초록이다. 우리 코드가 판 SNTP 왕복으로 시계가 뛴다.
2. 자식이 몇 번 재시도했는가(결정 M1-B가 고른 30이 맞았는지).
3. 응답의 소스 주소가 무엇이었는가. 게스트 쪽에서는 한 번도 안 재 본
   값이고, `sntp answer came from …` 줄이 나왔는지 안 나왔는지가 답이다.
   안 나왔으면 소스가 서버 주소와 같다는 뜻이고, 그러면 M2 이후에 그것을
   거부 조건으로 승격할 수 있다.
4. 실측 7이 남긴 렌더 숙제의 답(검사 19가 섰는가).
5. 체인 단독 시간의 증가분(위험 5).

반사실의 결과도 함께 적는다 — 죽은 자리와 errno.

- [ ] Step 2: design의 위험 절을 고친다

- 위험 2의 `⚠ 렌더 하나가 안 닫혔다` 문단을 결과로 바꾼다.
- 위험 5에 실제 증가분을 적는다.

- [ ] Step 3: 더한 줄과 지운 줄을 따로 센다

```bash
git diff --stat
git diff | grep '^-'
```

지우는 편집이 design 위험 절에만 있는지 본다.

- [ ] Step 4: 새 파일이 전부 들어가는지 본다

```bash
git status --short
```

새 파일이 셋이다 — `init/src/sntp.zig` · `init/src/sntp_test.zig` ·
`net/sntp_stub.pl`. `out/*.img`는 `.gitignore`가 막고 있어야 한다. 안 막고
있으면 먼저 그것부터 고친다(BF-M0이 빌드 산출물을 커밋한 적이 있다).

- [ ] Step 5: 커밋한다

```bash
git add init/src/sntp.zig init/src/sntp_test.zig init/src/config.zig \
        init/src/config_test.zig init/src/main.zig init/src/power.zig \
        init/build.zig net/sntp_stub.pl net/make_disk.sh net/check.sh \
        docs/superpowers/specs/2026-09-15-tars-time-sync-design.md \
        docs/superpowers/plans/2026-09-15-tars-time-sync-ts-m1.md
git commit -m "Ask the network what time it is and step the clock"
```

디렉터리를 통째로 넣지 않는다.

## 이 milestone이 끝난 자리

- `init/src/sntp.zig` — 우리가 쓰는 SNTP 전부. 순수 함수 셋과 자식 하나.
- `init/src/sntp_test.zig` — era 경계 양쪽과 검증 넷을 호스트가 본다.
- `init/src/config.zig`의 여덟째 키 `ntp`와 이 저장소의 첫 주소 파서.
- `init/src/power.zig`의 `resetToDefault()` — `execve` 없이 fork하는 자식이
  생길 때마다 쓰이게 될 함수.
- `net/sntp_stub.pl` — 게이트의 상대. 우리가 쓴 perl 스무 줄.
- `net/check.sh`가 검사 열아홉이 되고 부팅이 둘이 된다.
- `net/make_disk.sh`가 이미지 둘을 굽는다.

끝 기준: 부팅 A가 초록이고, stub을 안 띄운 반사실이 검사 18에서 죽는다.
호스트 검사가 era 경계 양쪽과 검증 넷을 본다.

## M2가 이어받을 것

- `net.zig`의 argv에 `-o ntp_servers` 한 단어(TS-M0 실측 8이 처방을 정했다).
- `kernel/make_initrd.sh`에 hook `30-tars-ntp`.
- `ntp=dhcp`가 `/run/tars/ntp_servers`를 제한 시간 안에서 기다리는 것.
  M1은 한 번 열어 보고 없으면 끝낸다(결정 M1-D).
- 부팅 B. 죽은 주소를 심은 initrd로, 셸이 평소와 같은 시각에 뜨는 것을 본다.
  그 부팅에서 SNTP 자식은 전원이 꺼질 때까지 재시도하고 있을 것이고,
  결정 M1-A가 그 자식이 조용히 죽게 만든다.
