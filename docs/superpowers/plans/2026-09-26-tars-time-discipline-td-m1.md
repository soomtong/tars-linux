# TD-M1 — 시계를 chronyd에게 넘긴다

> 이 plan을 실행하는 사람에게: 저장소 코드가 바뀌는 첫 milestone이다. Task마다
> `git diff --stat`으로 더한 줄과 지운 줄을 세고, 지우는 편집은
> `git diff | grep '^-'`로 내용을 읽는다(CLAUDE.md 진행 방식 2).

Goal: `init/src/sntp.zig`의 프로토콜 부분을 지우고, 남는 배관을
`init/src/clock.zig`로 옮겨 `execve chronyd`로 끝낸다. `net` 체인이 지금과 같은
사실(2031년으로 뛴다 · 서버가 DHCP 파일에서 온다 · 안 닿는 서버가 부팅을 안
막는다 · 종료가 유예를 안 쓴다)을 chronyd의 로그와 화면에서 본다.

Architecture: PID 1은 지금처럼 fork만 하고 다음 줄로 간다. 자식이 서버를
정하고(`ntp=<주소>` 또는 `/run/tars/ntp_servers`), 기본 경로를 기다리고,
`/run/tars/chrony.conf`를 쓰고, `chronyd -d -u root -f …`로 자기 자신을
바꾼다. 이미지(Dockerfile)에 패키지 다섯이 들어가고 initrd에 바이너리 둘과
라이브러리 넷이 들어간다.

Tech Stack: Zig(init, libc 없음) · chrony 4.6.1 · bash(게이트) · perl(stub)

---

## TD-M0이 정해 준 것

design의 "M1 · M2가 가져다 쓸 넷"(실측 1~9) 중 M1이 쓰는 셋이다.

1. 싣는 것 — Dockerfile에 `chrony` · `libseccomp2` · `libedit2` · `libbsd0` ·
   `libmd0`, `guest_tools.sh`에 `chronyd` · `chronyc` 두 줄.
2. 게이트가 grep할 줄 — `Selected source 10.0.2.2` · `System clock was stepped by`.
3. 설정에 `cmdport 0`(실측 2).

`confdir`와 `driftfile`은 M2다(design 결정 4 · 5 · 8).

## 이 plan이 새로 정하는 것

### 결정 M1-A — `power.resetToDefault()`는 남긴다 (design 결정 2 정정)

design 결정 2는 "`execve`를 하므로 부를 필요가 없어진다 — 지운다"고 적었다.
틀렸다. 자식은 `execve` 전에 우리 코드로 최대 30초를 기다린다(`ntp=dhcp`의
파일, 그리고 결정 M1-B의 기본 경로). 그 사이에 전원 버튼이 눌리면 부모에게
물려받은 핸들러 때문에 SIGTERM을 무시하고, `reapAll()`이 유예 3초를 다 써서
`grace period expired`가 찍힌다. 그래서 fork 직후 첫 줄로 남긴다. `power.zig`의
주석만 "그런 자식은 `clock.zig`의 것 하나이고, `execve` 전까지만 그렇다"로
고친다.

게이트가 이 창을 직접 밟지는 않는다는 것도 적어 둔다. 부팅 B는 파일을 미리
심어서 기다림이 즉시 끝나고, 전원을 끌 때 살아 있는 것은 이미 chronyd다.
TS 때는 자식이 끝까지 우리 코드였으므로 부팅 B가 이 줄의 시험이었지만 이제는
아니다. 창이 30초로 좁고 처방이 한 줄이라 새 부팅을 더하지 않는다.

### 결정 M1-B — 자식은 기본 경로가 생길 때까지 기다린 뒤 chronyd가 된다

⚠ Task 6 Step 2의 반사실이 이 결정의 전제를 뒤집었다(design 실측 13). 기다림이
없어도 점프가 1초 차이로 같은 자리에 왔고, `ea72b85`가 기다리는 코드를 걷어
냈다. 아래는 그 전의 판단이다.

M0 하네스는 주소가 붙고 8초 뒤에 chronyd를 띄웠다. `init`에서는 순서가 다르다 —
자식은 dhcpcd가 막 태어난 직후에 fork되고, TS-M1 실측 10으로 리스는 10초 안팎
뒤에 온다. chrony의 `iburst`는 처음 네 번을 2초 간격으로 묻고 그 뒤로는
`minpoll`의 기본값 6(64초)로 물러난다. 네 번이 전부 `ENETUNREACH`로 날아가면
첫 점프가 1분 넘게 늦어진다. TS의 SNTP는 1~3초 간격으로 30번 다시 물어서 이
틈을 덮었다.

그래서 자식이 `/proc/net/route`에 기본 경로(Destination `00000000`)가 생길
때까지 0.5초 간격으로 최대 30초 기다린다. dhcpcd가 리스를 받으면 그 줄을
쓴다(`net` 체인 검사 8이 보는 `default via 10.0.2.2`). 끝내 안 생기면 그래도
chronyd를 띄운다 — chronyd는 64초마다 다시 묻고, 그것이 네트워크가 없는
기계에서 우리가 바랄 수 있는 전부다. 부팅은 여전히 안 막는다. 기다리는 쪽이
자식이다.

`ntp=dhcp`는 파일이 리스 뒤에 생기므로 사실상 기다림이 없다. 두 갈래에 같은
코드를 거는 것은 갈래를 줄이려는 것이다.

파싱은 순수 함수 `hasDefaultRoute`로 두어 `clock_test`가 본다.

### 결정 M1-C — 이름

| 전 | 후 | 이유 |
|---|---|---|
| `init/src/sntp.zig` | `init/src/clock.zig` | design 결정 2 |
| `init/src/sntp_test.zig` | `init/src/clock_test.zig` | 같다 |
| `sntp.sync(net, ntp)` | `clock.start(net, ntp, envp)` | 동기화가 아니라 "시계를 맡을 것을 띄운다"이고, `execve`에 envp가 든다 |
| `net/sntp_stub.pl` | `net/ntp_stub.pl` | chrony가 말하는 것은 SNTP가 아니라 NTP다. stub은 흐르는 시계가 된다 |

로그 줄:

| 자리 | 글자 |
|---|---|
| 부모 | `tars-init: clock child (pid N) will ask <설정값>` |
| 자식 · 경로 | `tars-init: default route is up after N ms` / `tars-init: no default route after 30000 ms, starting chronyd anyway` |
| 자식 · 설정 | `tars-init: chronyd will ask A.B.C.D (/run/tars/chrony.conf)` |
| 자식 · 실패 | `tars-init: cannot exec /usr/bin/chronyd` 등 |

`ntp=off` · `net=off`의 두 줄과 `ntp server … came from /run/tars/ntp_servers`는
글자를 안 바꾼다. 검사 21이 뒤의 것을 grep한다.

### 결정 M1-D — 게이트의 검사 18이 보는 것

지금은 `tars-init: clock stepped to ${STUB_UNIX}`를 본다. stub의 시계가 흐르므로
정확한 값이 없어지고, 그 줄을 찍던 코드도 없어진다. 셋을 순서대로 본다.

1. `tars-init: chronyd will ask 10.0.2.2` — 우리 배관이 끝까지 왔다
2. `Selected source 10.0.2.2` — chronyd가 stub을 믿었다
3. `System clock was stepped by` — 뛰었다

값의 검사는 검사 19(`tsyear=2031`)가 그대로 한다. 2031년은 stub 말고는 줄 수
없는 값이다.

대기 상한은 90초 그대로다. 결정 M1-B가 맞다면 리스 뒤 몇 초 안에 뛴다.

## Task 1 — 이미지에 chrony를 굽는다

Files: Modify `devcontainer/Dockerfile`

- [ ] Step 1: 다운로드 목록 끝(`tzdata)` 앞)에 다섯 줄을 더한다

`libext2fs2t64:amd64 \` 다음, `tzdata) \` 앞에:

```
        chrony:amd64 \
        libseccomp2:amd64 \
        libedit2:amd64 \
        libbsd0:amd64 \
        libmd0:amd64 \
```

- [ ] Step 2: 층 설명 주석을 DI-M0 블록 뒤(`ENV AMD64_SYSROOT` 앞)에 더한다

```dockerfile
#
# ── TD-M1: 층 8(시계를 길들이는 것) ──────────────────────────────────────
#
# chrony 하나에 라이브러리 넷이다(TD-M0 실측 1). chronyd가 부르는 것 중
# libgnutls · libnettle · libcap은 curl과 ip가 이미 데려왔고, 새로 드는 것은
#
#   libseccomp2   chronyd. 커널에 CONFIG_SECCOMP가 없어 필터는 안 켜지만
#                 (-F를 안 준다) 동적 링크가 이름을 요구한다
#   libedit2      chronyc. 사람이 drift를 보는 창이다(TD design 결정 9)
#   libbsd0       libedit가 부른다
#   libmd0        libbsd가 부른다
#
# 넷이 푼 것 기준 547,688바이트, initrd에서 gzip으로 약 424KB다(바이너리
# 둘 포함). 패키지에 딸려 오는 ifupdown · NetworkManager · dhclient · ppp용
# hook은 initrd에 안 넣는다 — guest_tools.sh는 바이너리 둘만 적는다.
```

- [ ] Step 3: 이미지를 다시 굽는다 (수 분)

```bash
{ time docker build -t tars-devcontainer devcontainer/ ; } 2>&1 | tail -3
```

- [ ] Step 4: sysroot에 둘과 넷이 있는지 본다

```bash
docker run --rm tars-devcontainer bash -c 'S=$AMD64_SYSROOT; ls -l $S/usr/sbin/chronyd $S/usr/bin/chronyc; for l in libseccomp.so.2 libedit.so.2 libbsd.so.0 libmd.so.0; do ls $S/usr/lib/x86_64-linux-gnu/$l; done'
```

기대: 여섯 줄 전부 있다.

- [ ] Step 5: 커밋

```bash
git add devcontainer/Dockerfile
git commit -m "Bake chrony and its four libraries into the build image"
```

## Task 2 — initrd에 chronyd와 chronyc를 싣는다

Files: Modify `kernel/guest_tools.sh`

- [ ] Step 1: 층 7 뒤, 배열의 닫는 `)` 앞에 층 8을 더한다

```bash

  # ── 층 8 · 시계 2 ──────────────────────────────────────────────────────
  # TD-M1. init의 clock.zig가 fork한 자식이 /usr/bin/chronyd로 execve한다.
  # 오른쪽이 /usr/bin인 이유는 dhcpcd와 같다(PATH가 /usr/bin:/bin). 그 상수와
  # 여기의 오른쪽이 어긋나면 증상이 `cannot exec /usr/bin/chronyd` 하나다.
  #
  # 새 라이브러리(TD-M0 실측 1. 푼 것 기준):
  #   chronyd   338,760바이트   1개 — libseccomp
  #   chronyc   117,896바이트   3개 — libedit · libbsd · libmd
  usr/sbin/chronyd:usr/bin/chronyd
  usr/bin/chronyc:usr/bin/chronyc
```

- [ ] Step 2: `tools` 체인만 돌려 initrd 목록 검사가 둘을 보는지 본다 (약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash tools/check.sh 2>&1 | tail -5
```

기대: `all 77 tools the list names`와 `PASS`. `copy_lib_deps`가 넷을 못 찾으면
`make_initrd: cannot resolve …`로 죽는다 — Task 1의 이미지가 안 쓰인 것이다.

- [ ] Step 3: 커밋

```bash
git add kernel/guest_tools.sh
git commit -m "Carry chronyd and chronyc in the initrd"
```

## Task 3 — `sntp.zig`를 `clock.zig`로 줄인다

Files: Delete `init/src/sntp.zig` · `init/src/sntp_test.zig`, Create
`init/src/clock.zig` · `init/src/clock_test.zig`, Modify `init/build.zig` ·
`init/src/main.zig` · `init/src/power.zig` · `init/src/config.zig`

- [ ] Step 1: 옮긴다

```bash
git mv init/src/sntp.zig init/src/clock.zig
git mv init/src/sntp_test.zig init/src/clock_test.zig
```

`git mv`로 옮기는 이유는 `parseServerFile` · `serverFromFile` ·
`waitForServerFile`이 글자 그대로 남기 때문이다. 히스토리가 그 셋을 잇는다.

- [ ] Step 2: `clock_test.zig`를 먼저 쓴다 (전문)

```zig
const std = @import("std");
const clock = @import("clock.zig");

/// 기대하는 설정 파일은 글자로 한 벌 더 적는다. `renderConf`로 만든 것과
/// 비교하면 검사가 tautology가 된다 — sntp_test의 `reply`가 stub의 바이트
/// 배치를 손으로 한 벌 더 적었던 것과 같은 이유다.
fn expectConf(server: [4]u8, want: []const u8) !void {
    var buf: [clock.CONF_MAX]u8 = undefined;
    const got = clock.renderConf(&buf, server) orelse {
        std.debug.print("FAIL: the config for {d}.{d}.{d}.{d} did not fit\n", .{
            server[0], server[1], server[2], server[3],
        });
        return error.ConfTooLong;
    };
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: got\n{s}---\nwant\n{s}---\n", .{ got, want });
        return error.WrongConf;
    }
}

fn expectRoute(text: []const u8, want: bool) !void {
    if (clock.hasDefaultRoute(text) != want) {
        std.debug.print("FAIL: hasDefaultRoute said {} for\n{s}\n", .{ !want, text });
        return error.WrongRoute;
    }
}

fn expectServer(text: []const u8, want: [4]u8) !void {
    const got = clock.parseServerFile(text) orelse {
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
    if (clock.parseServerFile(text)) |got| {
        std.debug.print("FAIL: found {d}.{d}.{d}.{d} in [{s}], expected none\n", .{
            got[0], got[1], got[2], got[3], text,
        });
        return error.UnexpectedServer;
    }
}

/// /proc/net/route의 머리 줄. 커널이 탭으로 가르고 줄 끝에 공백을 붙인다
/// (net/ipv4/fib_trie.c의 fib_route_seq_show). 머리와 몸이 같은 모양이라
/// 머리 줄의 `Destination`을 주소로 읽는 실수가 쉽다.
const ROUTE_HEAD =
    "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT                                                       \n";

pub fn main() !void {
    // ── renderConf ─────────────────────────────────────────────────────
    //
    // 세 줄이 TD design 결정 4와 TD-M0 실측 2다. makestep이 빠지면 chrony는
    // 2031년까지 몇 달에 걸쳐 slew한다 — 게이트의 검사 18이 그것을 잡지만,
    // 원인에서 가장 가까운 자리가 여기다.
    try expectConf(.{ 10, 0, 2, 2 }, "server 10.0.2.2 iburst\nmakestep 1 3\ncmdport 0\n");
    // 가장 긴 주소. CONF_MAX가 모자라면 여기서 난다.
    try expectConf(.{ 255, 255, 255, 255 }, "server 255.255.255.255 iburst\nmakestep 1 3\ncmdport 0\n");
    std.debug.print("clock_test: the chrony config names the server, steps once and closes the udp command port\n", .{});

    // ── hasDefaultRoute ────────────────────────────────────────────────
    //
    // dhcpcd가 리스를 받은 뒤의 모양이다. 첫 몸 줄이 기본 경로다.
    try expectRoute(ROUTE_HEAD ++
        "eth0\t00000000\t0202000A\t0003\t0\t0\t1002\t00000000\t0\t0\t0                                                                               \n" ++
        "eth0\t0002000A\t00000000\t0001\t0\t0\t1002\t00FFFFFF\t0\t0\t0                                                                               \n", true);
    // 링크만 올라오고 리스 전. 서브넷 줄조차 없다.
    try expectRoute(ROUTE_HEAD, false);
    // 서브넷 줄만 있다. 주소는 붙었는데 게이트웨이가 아직이다.
    try expectRoute(ROUTE_HEAD ++
        "eth0\t0002000A\t00000000\t0001\t0\t0\t1002\t00FFFFFF\t0\t0\t0                                                                               \n", false);
    // 빈 입력. 파일을 못 읽은 경우다.
    try expectRoute("", false);
    std.debug.print("clock_test: a default route is a body line whose destination is 00000000\n", .{});

    // ── parseServerFile ────────────────────────────────────────────────
    //
    // TS-M2부터 있던 검사 그대로다. dhcpcd가 hook에 넘기는 `$new_ntp_servers`는
    // 공백으로 갈린 목록이고, hook은 그것을 그대로 파일에 쓴다. 첫 것만 쓴다
    // (TS design 비목표 2).
    try expectServer("10.0.2.2\n", .{ 10, 0, 2, 2 });
    try expectServer("192.168.0.1 192.168.0.2\n", .{ 192, 168, 0, 1 });
    // 개행 없이 끝나도 받는다. `printf`로 쓴 파일이 그렇다.
    try expectServer("1.2.3.4", .{ 1, 2, 3, 4 });
    // 빈 파일. hook이 빈 값으로 불린 경우다.
    try expectNoServer("");
    try expectNoServer("\n");
    // 이름은 안 받는다(TS design 결정 5 — init에 resolver가 없다).
    try expectNoServer("pool.ntp.org\n");
    // 첫 토큰만 본다. 그것이 주소가 아니면 뒤를 안 뒤진다.
    try expectNoServer("garbage 10.0.2.2\n");
    std.debug.print("clock_test: the server file gives up its first address and nothing else\n", .{});

    std.debug.print("PASS\n", .{});
}
```

- [ ] Step 3: `init/build.zig`의 등록을 바꾼다

`sntp_test_mod` · `sntp_test` · `src/sntp_test.zig` · `"sntp_test"`를
`clock_test_mod` · `clock_test` · `src/clock_test.zig` · `"clock_test"`로 바꾸고,
위 주석을 이렇게 바꾼다.

```zig
    // TD-M1: 시계를 chronyd에게 넘기는 배관의 순수한 쪽 셋(설정 파일 ·
    // 기본 경로 · 서버 파일). 위 다섯과 같은 이유로 host_target이다 —
    // clock.zig에서 시스템 콜을 하는 부분은 이 셋 아래에만 있다.
    //
    // TS-M1부터 있던 sntp_test의 자리다. 패킷과 era를 보던 검사는 그 코드와
    // 함께 지웠다(TD design 결정 1).
```

- [ ] Step 4: 검사가 빨간지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | tail -5
```

기대: `renderConf` · `CONF_MAX` · `hasDefaultRoute`가 `clock.zig`에 없다는
컴파일 에러.

- [ ] Step 5: `clock.zig`를 쓴다 (전문)

```zig
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const power = @import("power.zig");

// 시계에 관한 일은 chronyd가 한다(TD design 결정 1). 이 파일이 하는 것은
// 그 chronyd를 띄우기까지의 배관이다 — 갈래를 고르고, fork하고, 서버를
// 정하고, 기본 경로를 기다리고, 설정 파일을 쓰고, execve한다.
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

/// `/proc/net/route`에 기본 경로가 있는가. 시스템 콜이 없는 순수 함수다.
///
/// 첫 줄은 머리라 건너뛴다. 몸 줄의 둘째 칸(Destination)이 `00000000`이면
/// 기본 경로다 — 커널이 주소를 16진수 여덟 글자로 찍는다.
pub fn hasDefaultRoute(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    _ = lines.next(); // 머리
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        _ = fields.next() orelse continue; // Iface
        const dest = fields.next() orelse continue;
        if (std.mem.eql(u8, dest, "00000000")) return true;
    }
    return false;
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

// ── 여기서부터는 시스템 콜을 한다. 위의 셋만 clock_test가 본다 ───────────

/// 기다리는 상한과 간격. 서버 파일과 기본 경로가 같은 값을 쓴다.
///
/// 30초인 근거는 리스다. 서버 파일을 쓰는 것은 dhcpcd의 hook이고 기본 경로를
/// 쓰는 것도 dhcpcd라서, 기다리는 대상이 결국 리스다 — `net/check.sh`의 리스
/// 대기 상한이 60초이고 실제 관측이 10초 안팎이다(TS-M1 실측 10).
///
/// 이 수가 부팅 시간에 영향을 안 준다. 부모는 이미 다음 줄로 갔고, 이
/// 기다림은 자식 안에서만 돈다(TS design 결정 3).
const WAIT_TRIES: usize = 60;
const WAIT_SLEEP_MS: isize = 500;

/// dhcpcd의 hook이 option 42를 적어 두는 자리(TS design 결정 4).
/// kernel/dhcpcd-hooks/30-tars-ntp의 기본값과 같은 글자여야 한다.
const SERVER_FILE: [:0]const u8 = "/run/tars/ntp_servers";

const ROUTE_FILE: [:0]const u8 = "/proc/net/route";

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
    while (tries < WAIT_TRIES) : (tries += 1) {
        if (serverFromFile()) |ip| return ip;
        sleepMillis(WAIT_SLEEP_MS);
    }
    // 실기계에서 이 줄이 뜻하는 것은 "DHCP 서버가 option 42를 안 준다"이고,
    // 그것이 TS design 위험 3이 게이트로 영영 못 가리는 바로 그 상태다.
    std.debug.print("tars-init: gave up waiting for {s}\n", .{SERVER_FILE});
    return null;
}

/// `/proc/net/route`를 한 번 읽어 기본 경로가 있는지 본다.
fn routeIsUp() bool {
    const rc = linux.open(ROUTE_FILE.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc) != null) return false;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    // 머리 한 줄과 몸 한 줄이 각각 128바이트다. 기본 경로는 dhcpcd가 서브넷
    // 줄보다 먼저 넣으므로 앞의 1KB 안에 있다.
    var buf: [1024]u8 = undefined;
    const n = linux.read(fd, &buf, buf.len);
    if (failed(n) != null) return false;
    return hasDefaultRoute(buf[0..n]);
}

/// 기본 경로가 생길 때까지 기다린다. 자식 안에서만 불린다(TD-M1 결정 M1-B).
///
/// chrony의 `iburst`는 처음 네 번만 2초 간격이고 그 뒤로는 64초로
/// 물러난다. 주소가 붙기 전에 chronyd가 뜨면 그 넷이 전부 `ENETUNREACH`로
/// 날아가고 첫 점프가 1분 넘게 늦어진다. 그래서 길이 난 뒤에 넘긴다.
///
/// 끝내 안 생겨도 false를 돌려줄 뿐 chronyd는 띄운다. 64초마다 다시 묻는
/// 것이 네트워크가 없는 기계에서 바랄 수 있는 전부다.
fn waitForRoute() void {
    var tries: usize = 0;
    while (tries < WAIT_TRIES) : (tries += 1) {
        if (routeIsUp()) {
            std.debug.print("tars-init: default route is up after {d} ms\n", .{
                @as(isize, @intCast(tries)) * WAIT_SLEEP_MS,
            });
            return;
        }
        sleepMillis(WAIT_SLEEP_MS);
    }
    std.debug.print("tars-init: no default route after {d} ms, starting chronyd anyway\n", .{
        @as(isize, @intCast(WAIT_TRIES)) * WAIT_SLEEP_MS,
    });
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
        // 우리 코드로 최대 30초를 기다리고, 그동안은 부모의 SIGTERM 핸들러를
        // 갖고 있다. 되돌리지 않으면 그 창에 전원을 끌 때 이 자식만 안 죽는다.
        power.resetToDefault();
        const server: [4]u8 = switch (want) {
            .off => unreachable, // 위에서 돌아갔다
            .dhcp => waitForServerFile() orelse linux.exit(0),
            .server => |ip| ip,
        };
        waitForRoute();
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
```

- [ ] Step 6: `main.zig`의 두 자리를 바꾼다

`const sntp = @import("sntp.zig");` → `const clock = @import("clock.zig");`

`sntp.sync(cfg.net, cfg.ntp);`와 그 위 주석을:

```zig
    // TS-M1 · TD-M1. `net.bringUp` 다음인 것이 이 한 줄의 유일한 제약이다 —
    // `ntp=dhcp`가 읽는 파일을 쓰는 것이 dhcpcd의 hook이고, 자식이 기다리는
    // 기본 경로도 dhcpcd가 넣는다. 그리고 여기서 fork한 자식은 부모를 한
    // 순간도 안 세운다(TS design 결정 3) — 기다리는 것도 chronyd가 되는
    // 것도 자식이다.
    clock.start(cfg.net, cfg.ntp, envp);
```

- [ ] Step 7: 주석 둘을 고친다

`init/src/power.zig:85-87`:

```zig
/// `net.zig`의 dhcpcd 자식은 이 함수가 필요 없다 — `execve`가 다뤄진
/// 시그널을 전부 `SIG_DFL`로 되돌려 주기 때문이다. `execve` 전에 우리 코드로
/// 오래 머무는 자식만 손으로 해야 하고, 지금 그런 자식은 `clock.zig`의 것
/// 하나다 — 서버 파일과 기본 경로를 최대 30초씩 기다린 뒤에 chronyd가 된다.
```

`init/src/config.zig:47`의 `` `sntp.zig` ``를 `` `clock.zig` ``로.

- [ ] Step 8: 검사가 초록인지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build test 2>&1 | tail -12 && zig build && echo build-ok'
```

기대: `clock_test:` 세 줄과 `PASS`, `build-ok`.

- [ ] Step 9: diff를 읽는다

```bash
git diff --stat HEAD
git diff HEAD -M -- init/src/clock.zig | grep '^-' | grep -v '^---'
```

지워진 것이 `buildRequest` · `parseReply` · era 상수 · `makeNonce` · `step` ·
`askAndStep` · `MAX_TRIES` 등 프로토콜 쪽과 `sync`의 옛 몸뿐인지 본다.

- [ ] Step 10: 커밋

```bash
git add init/build.zig init/src/clock.zig init/src/clock_test.zig init/src/main.zig init/src/power.zig init/src/config.zig
git commit -m "Hand the clock to chronyd and keep only the plumbing in init"
```

## Task 4 — stub의 시계가 흐른다

Files: Rename `net/sntp_stub.pl` → `net/ntp_stub.pl`

- [ ] Step 1: 옮기고 본문을 바꾼다 (전문)

```bash
git mv net/sntp_stub.pl net/ntp_stub.pl
```

```perl
#!/usr/bin/perl
# net 체인의 NTP 서버. 컨테이너 안에서 배경으로 돌면서 UDP 한 포트를 듣는다.
#
# TS 때는 몇 번을 묻든 같은 시각을 답했다(net/sntp_stub.pl). 상대가 한 번
# 묻고 뛰는 우리 SNTP였기 때문이다. TD-M1부터 상대가 chronyd이고, chronyd는
# 여러 번 물어 그 사이에 흐른 시간으로 주파수를 추정하므로 멈춘 시계를
# 상대로는 엉뚱한 값을 배운다(TD design 확인 3). 그래서 흐른다.
#
#   답하는 시각 = 출발 시각 + (지금 - 시작) × (1 + ppm / 10^6)
#
# ppm은 M2가 쓴다. 0이면 컨테이너 시계와 같은 빠르기로 흐른다.
#
# 인자: 포트 · 출발 시각(unix) · ppm
use strict;
use warnings;
use IO::Socket::INET;
use Socket;    # sockaddr_in·inet_ntoa. IO::Socket::INET은 이것을 자기
               # 네임스페이스로만 들여오므로 여기서 따로 써야 한다.
use Time::HiRes qw(time);

$| = 1;    # 배경으로 돌므로 버퍼를 안 쌓는다.

my $port = $ARGV[0] // 123;
my $base = $ARGV[1] // 1930367167;    # 2031-03-04T05:06:07Z
my $ppm  = $ARGV[2] // 0;

my $NTP_EPOCH = 2208988800;    # NTP의 초는 1900부터 센다
my $start = time();
my $rate  = 1 + $ppm / 1e6;

sub now_ntp {
    my $t = $base + (time() - $start) * $rate + $NTP_EPOCH;
    my $sec = int($t);
    return pack('NN', $sec, int(($t - $sec) * 4294967296));
}

my $sock = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'udp',
) or die "ntp-stub: cannot bind udp/$port: $!\n";

printf "ntp-stub: listening on udp/%d, starting at unix %d, %s ppm\n",
    $port, $base, $ppm;

# 시작 때의 시각을 reference timestamp로 쓴다. 0이면 chrony가 "서버가 한 번도
# 동기화된 적 없다"로 읽는다.
my $ref = now_ntp();
my $count = 0;

while (1) {
    my $req;
    # 메서드가 아니라 내장 함수 꼴로 부른다. IO::Socket에는 recv 메서드가
    # 없어서 메서드 꼴은 버전에 따라 조용히 안 돈다.
    my $from = recv($sock, $req, 512, 0);
    next unless defined $from;
    my $rx = now_ntp();
    my ($fport, $faddr) = sockaddr_in($from);
    if (length($req) < 48) {
        printf "ntp-stub: ignoring a %d-byte datagram\n", length($req);
        next;
    }
    # 요청의 transmit(40-47)을 originate(24-31)로 되돌린다. chrony는 이것이
    # 자기가 보낸 값과 다르면 답을 버린다.
    my $orig = substr($req, 40, 8);
    my $poll = unpack('c', substr($req, 2, 1));
    # LI 0 · VN 4 · mode 4(server) → 0x24. stratum 1 · poll은 요청값 그대로 ·
    # precision -20(약 1µs). root delay · root dispersion은 0이다.
    my $reply = pack('CCcc', 0x24, 1, $poll, -20)
              . pack('NN', 0, 0)
              . 'TARS'
              . $ref . $orig . $rx . now_ntp();
    send($sock, $reply, 0, $from) or print "ntp-stub: send failed: $!\n";
    $count++;
    printf "ntp-stub: answer #%d to %s:%d\n", $count, inet_ntoa($faddr), $fport;
}
```

- [ ] Step 2: 문법을 본다

```bash
docker run --rm -v "$PWD":/workspace tars-devcontainer perl -c /workspace/net/ntp_stub.pl
```

## Task 5 — `net` 체인이 새 줄을 본다

Files: Modify `net/check.sh` · `net/make_disk.sh` · `kernel/dhcpcd-hooks/30-tars-ntp`

- [ ] Step 1: 머리 주석(TS-M1 절, 43~54행)을 바꾼다

```bash
# TS-M1이 부팅을 하나 더 얹었고 TD-M1이 그 안을 chronyd로 바꿨다. 앞의
# 열여섯이 "바이트가 오간다"였다면 이쪽은 "그 바이트가 시계가 된다"다:
#
#   컨테이너의 perl stub이 UDP 123을 듣는다(시계가 흐른다)
#   설정 디스크의 ntp=10.0.2.2 → init이 fork한 자식이 기본 경로를 기다리고
#   → /run/tars/chrony.conf를 쓰고 chronyd가 된다
#   → chronyd가 묻고, 믿고, makestep으로 시계를 뛴다
#   → 게스트의 date가 2031년을 찍는다
#
# 이 부팅에서 우리 코드는 init/src/clock.zig의 배관이고 시계는 chronyd가
# 만진다. 상대는 우리가 쓴 perl 서른 줄이고, 그 둘 사이의 모든 것(SLIRP ·
# 커널의 UDP · dhcpcd의 주소)은 앞의 열여섯이 이미 따로 증명한 것들이다.
```

그리고 TS-M2 절의 `#   그 주소가 어디에도 없다 → 자식이 답 없이 재시도만 한다`를
`#   그 주소가 어디에도 없다 → chronyd가 답 없이 묻기만 한다`로.

- [ ] Step 2: `fail()`의 stub 머리를 바꾼다

`echo "--- sntp stub ---"` → `echo "--- ntp stub ---"`.

- [ ] Step 3: stub을 띄우는 자리

```bash
perl ./ntp_stub.pl "$NTP_PORT" "$STUB_UNIX" 0 > "$STUBLOG" 2>&1 &
STUB_PID=$!
sleep 1
if ! kill -0 "$STUB_PID" 2>/dev/null; then
  echo "FAIL: the ntp stub died at startup"
  cat "$STUBLOG"
  exit 1
fi
echo "the ntp stub is listening on udp/${NTP_PORT}"
```

- [ ] Step 4: 검사 18을 통째로 바꾼다

```bash
# ── 검사 18: chronyd가 시계를 뛰었나 ──────────────────────────────────
# TD-M1 plan 결정 M1-D. 셋을 순서대로 본다 — 우리 배관이 끝까지 왔다 ·
# chronyd가 stub을 믿었다 · 뛰었다. 앞에서 멈추면 어느 자리인지가 실패
# 메시지에 그대로 나온다.
#
# 값은 여기서 안 본다. stub의 시계가 흐르므로 정확한 수가 없고, 값의 검사는
# 검사 19의 2031년이 한다 — 그 해는 stub 말고는 줄 수 없다.
#
# 기다리는 이유. 자식은 dhcpcd가 리스를 받을 때까지 기본 경로를 기다린
# 뒤에 chronyd가 되므로(결정 M1-B) 이 줄들은 리스 뒤에 나온다. 그 대기가
# 검사 5와 같은 크기다.
wait_log() {
  local pattern="$1" i
  for i in $(seq 1 90); do
    if grep -a "$pattern" "$LOGA" >/dev/null; then return 0; fi
    if ! kill -0 "$QEMU_PID_A" 2>/dev/null; then return 1; fi
    sleep 1
  done
  return 1
}
wait_log "tars-init: chronyd will ask ${NTP_SERVER}" || \
  fail "init never handed the clock to chronyd" "tars-init: clock" "tars-init: default route"
wait_log "Selected source ${NTP_SERVER}" || \
  fail "chronyd never selected ${NTP_SERVER}" "tars-init: chronyd" "chronyd"
wait_log "System clock was stepped by" || \
  fail "chronyd never stepped the clock" "Selected source" "System clock"
echo "chronyd selected ${NTP_SERVER} and stepped the clock"
```

- [ ] Step 5: 부팅 A의 종료 검사 주석과 stub 수

```bash
# SL-M2가 세운 것을 이 부팅에도 건다. 이 게스트에는 chronyd가 있었고, 그것이
# SIGTERM에 끝나는지가 여기서 갈린다 — chronyd는 execve로 태어났으므로 부모의
# 핸들러를 안 물려받는다(TD design 확인 2).
```

```bash
echo "the ntp stub answered $(grep -ac 'answer #' "$STUBLOG") request(s)"
```

- [ ] Step 6: 부팅 B의 주석 · 힌트 · 끝 문장

머리 주석의 마지막 문단을:

```bash
# 상대가 없는 것이 이 부팅의 설계다. stub은 바로 위에서 이미 죽였고 심은
# 주소는 어느 네트워크에도 없다. 그래서 chronyd는 답 없이 묻기만 하다가
# 전원을 끄는 순간까지 살아 있다.
```

검사 21의 "기다리는 이유" 문단의 `fork 뒤에 시그널 정책을 되돌리고`는 그대로
맞다. 힌트 `"tars-init: sntp"` 두 자리를 `"tars-init: clock"`으로.

종료 검사 주석을:

```bash
# SL-M2가 세운 것. 전원을 끄는 순간 chronyd가 안 닿는 주소를 묻는 중이라
# 분명히 살아 있다. SIGTERM에 안 죽으면 reapAll()이 유예 3초를 다 쓰고
# `grace period expired`를 찍는다.
```

끝 문장을 `echo "nothing outlived SIGTERM — chronyd went down with the rest"`로.

- [ ] Step 7: 곁의 주석 둘

`net/make_disk.sh:81`의 `sntp.zig의 갈래 둘` → `clock.zig의 갈래 둘`.
`kernel/dhcpcd-hooks/30-tars-ntp:3`의 `init/src/sntp.zig다.` →
`init/src/clock.zig다.`, 19행의 `init/src/sntp.zig의 SERVER_FILE` →
`init/src/clock.zig의 SERVER_FILE`.

- [ ] Step 8: 저장소에 `sntp`가 남았는지 센다

```bash
rg -n -i "sntp" --glob '!docs/**' --glob '!HANDOFF.md' --glob '!kernel/src/**' .
```

기대: `CLAUDE.md`의 TS 표 한 줄과 `net/ntp_stub.pl`의 역사 주석, `clock.zig`와
`build.zig`의 역사 주석만. 살아 있는 코드가 가리키는 `sntp`는 0이다.

- [ ] Step 9: 체인 단독 (약 1분 30초)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash net/check.sh > /tmp/tdm1-net.log 2>&1 ; } 2>&1 | tail -3
tail -5 /tmp/tdm1-net.log
grep -a "tars-init: default route\|tars-init: chronyd\|Selected source\|System clock was stepped\|chronyd exiting" /tmp/tdm1-net.log | head
```

기대: `PASS`. 로그에서 `default route is up after N ms` → `chronyd will ask` →
`Selected source` → `stepped`가 이 순서로 나온다. `N`과, 리스에서 점프까지가
몇 초인지를 실측으로 적는다.

- [ ] Step 10: 커밋

```bash
git add net/check.sh net/ntp_stub.pl net/make_disk.sh kernel/dhcpcd-hooks/30-tars-ntp
git commit -m "Read chronyd's own lines in the network chain"
```

## Task 6 — 반사실

컨테이너 안에서 `rm -rf init/.zig-cache init/zig-out` 뒤에 돌린다(HANDOFF의
경고 1 — DC-M1의 첫 반사실이 낡은 바이너리로 거짓 초록이었다).

- [ ] Step 1: `makestep`을 빼면 검사 18의 셋째 줄에서 빨강

`clock.zig`의 `renderConf`에서 `\\makestep 1 3` 줄을 지우고:

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c 'rm -rf init/.zig-cache init/zig-out && bash net/check.sh' > /tmp/tdm1-cf1.log 2>&1; tail -8 /tmp/tdm1-cf1.log
git checkout init/src/clock.zig
```

기대: `FAIL: chronyd never stepped the clock`. `Selected source`는 나온다 —
chronyd는 서버를 믿지만 1초 넘게 틀린 시계를 뛰지 않고 slew만 한다.

- [ ] Step 2: 기본 경로를 안 기다리면 늦는가 (결정 M1-B의 반사실)

`start`의 `waitForRoute();` 한 줄을 지우고 같은 명령으로 돌린다. 결과가 둘 중
하나다.

| 결과 | 뜻 |
|---|---|
| 검사 18이 90초 안에 못 봐서 빨강 | 결정 M1-B가 막는 것이 실제로 있다 |
| 초록이지만 `stepped`가 리스 뒤 60초 넘게 늦다 | 막는 것은 있고, 게이트의 상한이 그것을 덮는다 |
| 초록이고 늦지도 않다 | 결정 M1-B의 전제가 틀렸다. 실측으로 적고 사용자에게 알린다 |

```bash
git checkout init/src/clock.zig
```

## Task 7 — 루트 게이트 (약 40분)

- [ ] Step 1: 3/3

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/tdm1-gate.log 2>&1 ; } 2>&1 | tail -3
tail -3 /tmp/tdm1-gate.log; grep -c "^FAIL" /tmp/tdm1-gate.log
```

기대: `TARS check PASS`, `FAIL` 0줄. DC-M2의 38분 38초와 견준다.

## Task 8 — 닫는다

- [ ] Step 1: `check.sh`의 `CHAINS`에서 `"NW-M3:./net/check.sh"` → `"TD-M1:./net/check.sh"`
- [ ] Step 2: design에 `## TD-M1이 실행으로 증명한 것`(실측 11부터), 결정 2에 M1-A의
  정정을 한 줄, Status 줄
- [ ] Step 3: 기억 `docs/decisions/project_time_discipline.md`와 `MEMORY.md` 한 줄
- [ ] Step 4: `HANDOFF.md`
- [ ] Step 5: diff를 세고 커밋

```bash
git diff --stat
git add check.sh docs/superpowers/specs/2026-09-26-tars-time-discipline-design.md docs/decisions/project_time_discipline.md MEMORY.md HANDOFF.md
git commit -m "Close TD-M1: chronyd owns the clock and the gate holds"
```
