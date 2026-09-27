# DS-M1 — dhcpcd와 chronyd가 감독 목록에 들어간다

> 이 plan을 실행하는 사람에게: Task 1 · 2는 호스트 검사를 먼저 고쳐 빨간 것을 보고
> 구현한다. Task 3~6은 게스트 동작이라 호스트 검사가 없고, Task 8의 체인이 판정한다.
> 커밋은 넷이다(Task 1 · Task 5 · Task 7 뒤 · Task 9).

Goal: DS design 결정 1~6을 코드로 넣고, 로그 줄이 바뀌어 흔들리는 이웃 체인 셋(net ·
nic · firewall)을 초록으로 되돌린다. 새 판정(재시작 · `status` · 버튼 fd · 반사실)은
M2다.

Architecture: `net.zig`와 `clock.zig`는 더 이상 fork하지 않는다. 각자 "띄울 것인가"를
답하고(안 띄우면 이유를 한 줄 찍는다) argv 상수를 내놓는다. `main.zig`가 그 둘을
`Kind.service`로 `children`의 2 · 3번 칸에 넣고, `services.d`의 서비스가 그 뒤에 붙는다.
chronyd의 서버는 `ntp=<주소>`면 설정에, `ntp=dhcp`면 hook이 쓰는
`/run/tars/chrony.sources/dhcp.sources`에 있다(결정 3, M0 실측 5 · 6).

Tech Stack: Zig 0.16(`std.os.linux`) · POSIX sh(dhcpcd hook) · bash(체인)

---

## 결정 — design이 plan에 맡긴 것

- M1-A — 이름. label은 `service dhcpcd` · `service chronyd`이고, 그 이름 둘은
  `services.zig`의 `DHCPCD` · `CHRONYD`가 한 번 정한다. `judgeName`이 같은 상수로
  `services.d`의 같은 이름을 `.reserved`로 가른다(결정 5).
- M1-B — argv는 각 파일의 `pub const`다. 타입은 `main.zig`의 `Child.argv`와 같은
  `[8:null]?[*:0]const u8`이다. 어긋나면 컴파일이 막는다.
- M1-C — 로그 줄. `init`의 `started dhcpcd (pid N), it picks the interface`는 없어지고
  감독자의 `started service dhcpcd (pid N, /usr/bin/dhcpcd)`가 그 자리를 받는다. 체인
  넷이 `tars-init: started service dhcpcd (pid`로 grep을 바꾼다. 부팅 때 무엇을
  하기로 했는지는 `tars-init: dhcpcd joins the services, it picks the interface` 한 줄로
  남긴다. chronyd 쪽은 `chronyd will ask <주소> (<설정>)`을 글자 그대로 둔다(net 체인
  검사 18이 본다). `ntp=dhcp`면 `chronyd will ask whoever dhcpcd names in
  /run/tars/chrony.sources`다. `clock child (pid N)` · `waiting for` · `came from` ·
  `gave up waiting`은 없어진다.
- M1-D — hook은 `new_ntp_servers`의 첫 토큰을 셸 접미사 제거로 꺼낸다(`set --`는
  dhcpcd-run-hooks의 위치 인자를 망가뜨린다 — hook은 source된다). 파일은 `.tmp`에 쓰고
  `mv`한다. chrony는 `.sources`로 끝나는 파일만 읽으므로 반쯤 쓰인 파일을 안 본다.
  `chronyc`는 `-h /run/chrony/chronyd.sock`으로 소켓을 못 박는다 — 없으면 곧바로
  실패하고(컨테이너의 호스트 검사도 그렇다), 실패는 `|| true`로 삼킨다(M0 실측 5).
- M1-E — net 체인 부팅 B가 initrd에 심는 파일이 `ntp_servers`에서
  `chrony.sources/dhcp.sources`로 바뀐다. `init`이 그 파일을 안 읽으므로 검사 21은
  로그가 아니라 화면에서 `chronyc -n sources`의 답으로 본다. 판정 글자(주소)는 친
  명령에 없다(`project_gate_screen_echo`).

## 파일

| 파일 | 무엇이 바뀌나 |
|---|---|
| `init/src/services.zig` · `services_test.zig` | `DHCPCD` · `CHRONYD` · `RESERVED` · `Verdict.reserved` |
| `init/src/clock.zig` · `clock_test.zig` | `renderConf`가 `?[4]u8`를 받는다 · `prepare` · 기다림 코드와 `parseServerFile` 삭제 |
| `init/src/net.zig` | `wantsDhcpcd` · `DHCPCD_ARGV` · `startDhcpcd`/`bringUp` 삭제 |
| `init/src/main.zig` | 두 칸을 `children`에 넣는다 · 주석 |
| `init/src/devices.zig` | 버튼 fd에 `.CLOEXEC = true` |
| `kernel/dhcpcd-hooks/30-tars-ntp` | `.sources`를 쓰고 reload |
| `net/check.sh` | 호스트 hook 검사 · 부팅 B의 심는 파일 · 검사 4 · 21 · 표지 목록 · 주석 |
| `nic/check.sh` · `firewall/check.sh` · `check.sh` | grep 글자와 주석 |

## Task 0 — 시작 상태

- [ ] Step 1

```bash
git status --short
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test > /tmp/ds-test0.log 2>&1; echo "exit=$?"
grep -c PASS /tmp/ds-test0.log; grep FAIL /tmp/ds-test0.log
```

기대: 이 plan만 `??`, `exit=0`, `FAIL` 0줄. `zig build test`의 끝줄은 판정이 아니다 —
exit code와 `FAIL` 줄로 본다.

## Task 1 — 예약된 이름 (결정 5)

Files: `init/src/services_test.zig:68-74` · `init/src/services.zig`

- [ ] Step 1: 검사를 먼저 더한다. `services_test.zig`의 `too_long` 줄 다음에:

```zig
    // DS-M1 결정 M1-A. init이 스스로 띄우는 둘과 같은 이름은 services.d에서 안 받는다.
    // 한 글자라도 다르면 받는다 — 막는 것은 tars-service가 헷갈리는 자리뿐이다.
    try expectVerdict(services.DHCPCD, .reserved);
    try expectVerdict(services.CHRONYD, .reserved);
    try expectVerdict("dhcpcd2", .ok);
    try expectVerdict("chrony", .ok);
```

그리고 그 아래 요약 줄을 바꾼다.

```zig
    std.debug.print("services_test: names — dot means hidden, {d} bytes is the limit, dhcpcd and chronyd are init's\n", .{services.NAME_MAX});
```

- [ ] Step 2: 빨간 것을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | grep -E "error|FAIL" | head
```

기대: `root source file struct 'services' has no member named 'DHCPCD'`.

- [ ] Step 3: `services.zig`를 고친다. `LABEL_PREFIX` 아래에:

```zig
/// DS-M1 결정 M1-A. init이 `services.d` 없이 스스로 감독 목록에 넣는 둘의 이름이다
/// (DS design 결정 1). label은 `LABEL_PREFIX ++ 이 이름`이라 `tars-service`가 같은
/// 이름으로 부른다.
pub const DHCPCD = "dhcpcd";
pub const CHRONYD = "chronyd";
/// 같은 이름이 `services.d`에 있으면 건너뛴다(DS design 결정 5). 둘이 같은 label을
/// 달면 `tars-service stop dhcpcd`가 무엇을 멈출지 모호하다.
pub const RESERVED = [_][]const u8{ DHCPCD, CHRONYD };
```

`Verdict`와 `judgeName`:

```zig
pub const Verdict = enum { ok, hidden, too_long, reserved };

/// 이름만 보고 가른다. `.`으로 시작하면 숨긴 것이다 — `.`과 `..`도 여기서 빠진다.
pub fn judgeName(name: []const u8) Verdict {
    if (name.len == 0 or name[0] == '.') return .hidden;
    if (name.len > NAME_MAX) return .too_long;
    for (RESERVED) |r| {
        if (std.mem.eql(u8, name, r)) return .reserved;
    }
    return .ok;
}
```

`discover`의 `switch (judgeName(name))`에 갈래 하나:

```zig
                .reserved => {
                    std.debug.print("tars-init: service {s} is a name init keeps for itself, skipped\n", .{name});
                    continue;
                },
```

- [ ] Step 4: 초록을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test > /tmp/ds-test1.log 2>&1; echo "exit=$?"
grep FAIL /tmp/ds-test1.log; grep "dhcpcd and chronyd are init's" /tmp/ds-test1.log
```

- [ ] Step 5: 커밋

```bash
git diff --stat
git add init/src/services.zig init/src/services_test.zig
git commit -m "Services: dhcpcd and chronyd are names init keeps for itself"
```

## Task 2 — chronyd 설정: 서버가 없으면 `sourcedir` (결정 3)

Files: `init/src/clock_test.zig`(전체) · `init/src/clock.zig`

- [ ] Step 1: `clock_test.zig`를 새로 쓴다. `expectConf`는 `?[4]u8`를 받고,
  `parseServerFile`의 검사 셋(`expectServer` · `expectNoServer`와 그 호출)은 지운다.

```zig
const std = @import("std");
const clock = @import("clock.zig");

/// 기대하는 설정 파일은 글자로 한 벌 더 적는다. `renderConf`로 만든 것과
/// 비교하면 검사가 tautology가 된다 — sntp_test의 `reply`가 stub의 바이트
/// 배치를 손으로 한 벌 더 적었던 것과 같은 이유다.
fn expectConf(server: ?[4]u8, keep: bool, want: []const u8) !void {
    var buf: [clock.CONF_MAX]u8 = undefined;
    const got = clock.renderConf(&buf, server, keep) orelse {
        std.debug.print("FAIL: the config (server={any}, keep={}) did not fit\n", .{ server, keep });
        return error.ConfTooLong;
    };
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: got\n{s}---\nwant\n{s}---\n", .{ got, want });
        return error.WrongConf;
    }
}

pub fn main() !void {
    // ── ntp=<주소> ─────────────────────────────────────────────────────
    //
    // 세 줄이 TD design 결정 4와 TD-M0 실측 2다. makestep이 빠지면 chrony는
    // 2031년까지 몇 달에 걸쳐 slew한다 — 게이트의 검사 18이 그것을 잡지만,
    // 원인에서 가장 가까운 자리가 여기다.
    try expectConf(.{ 10, 0, 2, 2 }, false, "server 10.0.2.2 iburst\nmakestep 1 3\ncmdport 0\n");
    // 가장 긴 주소. CONF_MAX가 모자라면 여기서 난다.
    try expectConf(.{ 255, 255, 255, 255 }, false, "server 255.255.255.255 iburst\nmakestep 1 3\ncmdport 0\n");
    std.debug.print("clock_test: without /config the chrony config names the server, steps once and closes the udp command port\n", .{});

    // TD-M2. /config가 붙은 부팅. confdir가 맨 앞이어야 사람이 적은 같은
    // 서버가 이긴다(TD design 실측 9) — 이 순서를 바꾸는 사람은 게이트의
    // 검사 26이 빨개지는 것을 보게 된다.
    try expectConf(.{ 10, 0, 2, 2 }, true, "confdir /config/chrony.d\nserver 10.0.2.2 iburst\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    try expectConf(.{ 255, 255, 255, 255 }, true, "confdir /config/chrony.d\nserver 255.255.255.255 iburst\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    std.debug.print("clock_test: with /config it reads chrony.d first and keeps its drift there\n", .{});

    // ── ntp=dhcp ───────────────────────────────────────────────────────
    //
    // DS design 결정 3. 서버 대신 디렉터리 하나다. dhcpcd의 hook이 그 안에
    // dhcp.sources를 쓰고 chronyc로 알린다(DS-M0 실측 5). 경로는 hook
    // kernel/dhcpcd-hooks/30-tars-ntp의 기본값과 같은 글자여야 한다.
    try expectConf(null, false, "sourcedir /run/tars/chrony.sources\nmakestep 1 3\ncmdport 0\n");
    // 가장 긴 모양. 114바이트라 CONF_MAX(128)에 든다.
    try expectConf(null, true, "confdir /config/chrony.d\nsourcedir /run/tars/chrony.sources\nmakestep 1 3\ndriftfile /config/chrony.drift\ncmdport 0\n");
    std.debug.print("clock_test: with ntp=dhcp chronyd starts with no server and reads the directory dhcpcd writes into\n", .{});

    std.debug.print("PASS\n", .{});
}
```

- [ ] Step 2: 빨간 것을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | grep -E "error" | head
```

기대: `expected type '[4]u8', found '@TypeOf(null)'`(또는 같은 뜻의 타입 에러).

- [ ] Step 3: `clock.zig`를 고친다

머리 주석의 둘째 문단을 바꾼다.

```zig
// TS의 sntp.zig였다. 패킷을 짓고 읽고 시계를 뛰던 절반을 TD-M1이 지웠고,
// 서버 파일을 기다리던 나머지 절반을 DS-M1이 지웠다. 이제 fork도 없다 —
// chronyd를 띄우고 감독하는 것은 main.zig의 supervise다(DS design 결정 1).
```

`power` import를 지운다(`resetToDefault`를 부르던 자식이 없어진다).

`CONF_MAX` 주석을 고친다.

```zig
/// `renderConf`에 넘길 버퍼의 크기. 가장 긴 모양(`ntp=dhcp`에 `/config`의
/// 두 줄까지)이 114바이트이고, `clock_test`가 그 경우를 직접 본다.
pub const CONF_MAX = 128;
```

`CONFIG_DRIFT` 아래에 상수 하나:

```zig
/// DS design 결정 3. `ntp=dhcp`일 때 chronyd가 서버를 찾는 디렉터리.
/// kernel/dhcpcd-hooks/30-tars-ntp의 기본값과 같은 글자여야 한다 — 어긋나면
/// chronyd가 서버 0개로 영영 기다리고, 증상은 "시계가 안 맞는다" 하나다.
pub const SOURCES_DIR = "/run/tars/chrony.sources";
```

`renderConf`의 주석 첫 줄 표와 본문:

```zig
/// chronyd의 설정 파일을 짓는다. 시스템 콜이 없는 순수 함수다.
///
/// 언제나 있는 세 줄(TD design 결정 4). 첫 줄이 `server`에 따라 둘로 갈린다.
///   server …  iburst   `ntp=<주소>`. 처음 네 번을 2초 간격으로 묻는다
///   sourcedir …        `ntp=dhcp`(server가 null). dhcpcd의 hook이 이 안에
///                      `server … iburst` 한 줄을 쓴다(DS design 결정 3)
///   makestep 1 3       (그대로)
///   cmdport 0          (그대로)
///
/// (`keep` 두 줄의 설명은 그대로 둔다.)
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
```

지운다: `parseServerFile` · `FILE_WAIT_TRIES` · `FILE_WAIT_SLEEP_MS` · `SERVER_FILE` ·
`sleepMillis` · `serverFromFile` · `waitForServerFile` · `execChronyd` · `start`.

`CHRONYD_PATH`를 `pub`으로 바꾸고 argv를 더한다.

```zig
/// DS 결정 M1-B. 감독 목록에 들어가는 chronyd의 argv. 인자 넷이 TD design 결정 3이다.
///   -d        갈라지지 않는다. 갈라지면 PID 1이 쥔 pid가 틀린 값이 된다
///   -u root   게스트에 _chrony가 없다
///   -f        설정을 /run에서 읽는다
///   (-F 없음) 커널에 seccomp가 없다
pub const CHRONYD_ARGV = [8:null]?[*:0]const u8{
    CHRONYD_PATH.ptr, "-d", "-u", "root", "-f", CONF_PATH.ptr, null, null,
};
```

`writeConf`는 `server: ?[4]u8`를 받게 시그니처만 바꾸고, 주석 "자식 안에서만
불린다"를 "부팅 때 PID 1이 한 번 부른다"로 바꾼다. `mkdir` 주석의 "`ntp=<주소>`면
hook이 안 돌아서"는 "hook보다 먼저 불리므로"로 바꾼다.

`start` 자리에 `prepare`:

```zig
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
        std.debug.print("tars-init: ntp=off, leaving the clock alone\n", .{});
        return false;
    }
    // 네트워크가 꺼져 있으면 주소가 붙을 리 없으므로 chronyd도 없다.
    if (net == .off) {
        std.debug.print("tars-init: ntp={s} but net=off, leaving the clock alone\n", .{
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
        std.debug.print("tars-init: chronyd keeps its drift in {s}\n", .{CONFIG_DRIFT});
    } else {
        std.debug.print("tars-init: no /config, chronyd forgets its drift at power-off\n", .{});
    }
    // net/check.sh의 검사 18이 앞의 줄을 grep한다.
    if (server) |ip| {
        std.debug.print("tars-init: chronyd will ask {d}.{d}.{d}.{d} ({s})\n", .{
            ip[0], ip[1], ip[2], ip[3], CONF_PATH,
        });
    } else {
        std.debug.print("tars-init: chronyd will ask whoever dhcpcd names in {s}\n", .{SOURCES_DIR});
    }
    return true;
}
```

- [ ] Step 4: 호스트 검사 초록 — 아직 `main.zig`가 `clock.start`를 부르므로 `zig build`는
  깨진다. 여기서는 `clock_test`만 본다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test > /tmp/ds-test2.log 2>&1; echo "exit=$?"
grep -E "clock_test|FAIL|error" /tmp/ds-test2.log
```

기대: `clock_test:` 세 줄. `main.zig`의 `clock.start` 에러가 함께 나오면 그것은 Task 4가
고친다(테스트 실행 파일은 `main.zig`를 안 물므로 `clock_test`는 돈다). 커밋은 Task 7 뒤다.

## Task 3 — dhcpcd: 띄우지 않고 답한다 (결정 1 · 2)

File: `init/src/net.zig:98-181`

- [ ] Step 1: `DHCPCD_PATH`부터 파일 끝까지를 바꾼다

```zig
/// dhcpcd가 사는 자리. guest_tools.sh가 usr/sbin/dhcpcd를 여기로 넣는다 —
/// PATH가 /usr/bin:/bin이라 /usr/sbin은 이름으로 안 닿는다(M0 실측 8).
/// 그 파일의 오른쪽과 이 상수가 어긋나면 증상이 execve 실패 하나뿐이다.
pub const DHCPCD_PATH: [:0]const u8 = "/usr/bin/dhcpcd";

/// DS 결정 M1-B. 감독 목록에 들어가는 dhcpcd의 argv.
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
/// 목록은 /etc/dhcpcd.conf와 컴파일 타임 기본값에서 오는데 make_initrd.sh가 그
/// 파일을 initrd에 안 넣는다. 옵션 이름을 dhcpcd가 파일 없이 안다 — 바이너리 안에
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
```

`linux`와 `failed`가 아직 쓰이는지 본다 — `loopbackUp`이 쓰므로 남는다.

## Task 4 — `main.zig`가 두 칸을 넣는다

File: `init/src/main.zig:935-1059`

- [ ] Step 1: `net.bringUp` · `clock.start` 두 호출과 그 주석을 바꾼다

```zig
    // NW-M2 · DS-M1. 여기서는 띄우지 않고 답만 듣는다 — dhcpcd를 감독 목록에
    // 넣을지다. 띄우는 것은 아래 `supervise`의 첫 바퀴이고, 그때는 위
    // `firewall.up`이 이미 끝나 있다(FW design 결정 5의 순서가 그대로 선다).
    const want_dhcpcd = net.wantsDhcpcd(cfg.net);

    // TS-M1 · TD-M1 · DS-M1. chronyd의 설정을 쓰고 감독 목록에 넣을지를 답한다.
    // 기다리는 것이 없다 — `ntp=dhcp`의 서버는 dhcpcd의 hook이 나중에
    // `/run/tars/chrony.sources`에 쓰고 chronyc로 알린다(DS design 결정 3).
    const want_chronyd = clock.prepare(cfg.net, cfg.ntp, storage_mounted);
```

그 아래 SV-M1 주석의 "`clock.start` 뒤인 것이 이 자리의 뜻이다(SV design 결정
4) — 서비스가 뜨는 시점에 방화벽 규칙과 dhcpcd가 이미 서 있다"를 이렇게 바꾼다.

```zig
    // SV-M1. 서비스는 아래 `children`에서 dhcpcd · chronyd 뒤에 붙는다(SV design
    // 결정 4의 순서를 DS-M1부터는 배열이 지킨다). 여기서는 읽기만 한다.
```

- [ ] Step 2: `children`을 짓는 자리

```zig
    // SV-M1 · DS-M1. 앞 둘은 SV 전과 같고, 그 뒤에 init이 스스로 넣는 데몬 둘이
    // (DS design 결정 1), 그 뒤에 서비스가 이름순으로 붙는다. 크기는 컴파일
    // 타임에 정해진다(힙이 없다) — 쓰는 것은 앞에서 `n`까지다.
    var children: [2 + services.RESERVED.len + services.MAX]Child = undefined;
```

`children[1] = .{ … };` 다음, 서비스 `for` 앞에:

```zig
    var n: usize = 2;
    // DS-M1. 서비스와 같은 Kind라 CT의 규칙(그룹 시그널 · 요청한 죽음은 안 셈 ·
    // tars-service의 동사 넷)이 코드 없이 그대로 선다. 탈출로는 없다.
    if (want_dhcpcd) {
        children[n] = .{
            .kind = .service,
            .label = services.LABEL_PREFIX ++ services.DHCPCD,
            .path = net.DHCPCD_PATH,
            .argv = net.DHCPCD_ARGV,
        };
        n += 1;
    }
    if (want_chronyd) {
        children[n] = .{
            .kind = .service,
            .label = services.LABEL_PREFIX ++ services.CHRONYD,
            .path = clock.CHRONYD_PATH,
            .argv = clock.CHRONYD_ARGV,
        };
        n += 1;
    }
```

서비스 `for`의 `children[2 + i]`를 `children[n + i]`로, `supervise` 호출을 이렇게 바꾼다.

```zig
    supervise(children[0 .. n + service_list.len], button_fds[0..button_count], control_fd, envp);
```

- [ ] Step 3: 빌드와 호스트 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && zig build test' > /tmp/ds-test4.log 2>&1; echo "exit=$?"
grep -E "FAIL|error" /tmp/ds-test4.log
```

기대: `exit=0`, 0줄. `envp`가 `main()`에서 쓰이지 않게 되면 컴파일이 그 자리를 말한다 —
`supervise`가 받으므로 쓰인다.

## Task 5 — 버튼 fd에 `CLOEXEC` (결정 6)

File: `init/src/devices.zig:396`

- [ ] Step 1

```zig
        // DS design 결정 6. CLOEXEC가 없으면 콘솔 셸 · 서비스와 그 자식이 이 fd를
        // 물려받는다(CT design 실측 7 · DS-M0의 기준선 `3 -> /dev/input/event0`).
        const rc = linux.open(path.cstr(), .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
```

위의 `O_NONBLOCK으로 여는 이유` 주석은 그대로 둔다.

- [ ] Step 2: 빌드 · 검사 후 커밋

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && zig build test' > /tmp/ds-test5.log 2>&1; echo "exit=$?"
grep -E "FAIL|error" /tmp/ds-test5.log
git diff --stat init/src/devices.zig
git add init/src/devices.zig
git commit -m "Open power button fds with CLOEXEC so children do not inherit them"
```

`clock.zig` · `net.zig` · `main.zig`는 아직 add하지 않는다 — hook과 체인과 함께 Task 7
뒤에 커밋한다.

## Task 6 — hook (결정 3 · M1-D)

File: `kernel/dhcpcd-hooks/30-tars-ntp`(전체)

- [ ] Step 1

```sh
# dhcpcd가 option 42로 받은 NTP 서버를 chronyd에게 건넨다(DS design 결정 3).
# 서버를 source 파일로 쓰고 chronyd에게 다시 읽으라고 알린다. chronyd의 설정은
# init이 부팅 때 쓰고(init/src/clock.zig), 그 설정의 `sourcedir`가 이 디렉터리다.
#
# 이 자리에 우리 파일을 두는 근거는 이웃들이다. make_initrd.sh가 같은
# 디렉터리에 20-resolv.conf를 넣고 있고, 그것이 $new_domain_name_servers로
# /etc/resolv.conf를 쓰는 것이 지금 게이트에서 매번 돈다. 우리는 같은 계약을
# $new_ntp_servers에 대해 쓴다. initrd에 안 넣는 50-timesyncd.conf도 같은
# 변수를 쓰는 기성 hook이다 — 우리가 지어낸 이름이 아니다.
#
# 실행되는 것이 아니라 source된다(dhcpcd-run-hooks의 `. "$hook"`). 그래서
# 세 가지를 지킨다 — 변수 이름에 tars_ 접두사를 붙여 남의 hook과 안 부딪치게
# 하고, return을 안 쓰고(net/check.sh의 호스트 검사는 이 파일을 sh로 직접
# 돌린다), `set --`를 안 쓴다(부르는 쪽의 위치 인자를 덮는다).
#
# 경로를 변수로 한 번 정하는 이유가 그 호스트 검사다(TS-M2 결정 M2-C).
# 이 기본값과 init/src/clock.zig의 SOURCES_DIR이 같은 글자여야 한다.
: "${tars_sources_dir:=/run/tars/chrony.sources}"

# 변수가 비었으면 아무것도 안 한다. option 42가 없는 리스다 — chronyd는
# 서버 0개로 계속 기다리고, 그것이 게이트의 SLIRP에서 늘 일어나는 일이다.
#
# 첫 주소만 쓴다(TS design 비목표 2). 셸의 접미사 제거로 꺼낸다.
#
# .tmp에 쓰고 mv한다. chrony는 .sources로 끝나는 파일만 읽으므로 반쯤 쓰인
# 파일을 볼 일이 없다.
#
# chronyc의 실패는 삼킨다(DS-M0 실측 5). chronyd가 아직 없거나 재시작 중이면
# `506 Cannot talk to daemon`으로 rc 1인데, chronyd는 뜰 때 이 디렉터리를
# 읽으므로(실측 6) 알리지 못해도 잃는 것이 없다. -h로 소켓을 못 박는 것은
# 그 실패가 UDP 재시도 없이 곧바로 오게 하려는 것이다.
if [ -n "${new_ntp_servers:-}" ]; then
	tars_ntp_first="${new_ntp_servers%% *}"
	mkdir -p "$tars_sources_dir"
	printf 'server %s iburst\n' "$tars_ntp_first" > "$tars_sources_dir/dhcp.sources.tmp"
	mv "$tars_sources_dir/dhcp.sources.tmp" "$tars_sources_dir/dhcp.sources"
	chronyc -h /run/chrony/chronyd.sock reload sources >/dev/null 2>&1 || true
fi
```

`kernel/make_initrd.sh:245` 근처 주석의 "이쪽은 $new_ntp_servers로 /run/tars/ntp_servers를
쓴다"를 "이쪽은 $new_ntp_servers로 /run/tars/chrony.sources/dhcp.sources를 쓴다"로
바꾼다.

## Task 7 — 체인이 새 줄을 본다 (M1-C · M1-E)

- [ ] Step 1: grep 글자 — 여섯 자리를 `tars-init: started service dhcpcd (pid`로 바꾼다

```bash
sd -F '"tars-init: started dhcpcd (pid"' '"tars-init: started service dhcpcd (pid"' net/check.sh nic/check.sh firewall/check.sh
sd -F "'tars-init: started dhcpcd \(pid'" "'tars-init: started service dhcpcd \(pid'" nic/check.sh
rg -n "started dhcpcd" net nic firewall check.sh
```

기대: 남는 것은 주석과 `fail`/`echo` 문구뿐이다. `net/check.sh:545`의 `fail`의 둘째 표지
`"tars-init: started dhcpcd"`는 `"tars-init: started service dhcpcd"`로 손으로 바꾸고,
`firewall/check.sh:202`가 `grep -an "tars-init: started service dhcpcd (pid"`가 됐는지
본다. 주석 셋(`nic/check.sh:18` · `check.sh:277` · `net/check.sh:559-560`)의
`started dhcpcd`를 `started service dhcpcd`로 바꾼다.

- [ ] Step 2: `net/check.sh`의 호스트 hook 검사(250~290행)를 바꾼다

```bash
# ── 호스트 검사: hook이 chrony의 source 파일을 쓰는가 (TS-M2 · DS-M1) ──────
#
# 경로 중 "hook → 파일" 조각은 게스트도 QEMU도 없이 증명된다 — dhcpcd가 하는
# 일이 변수를 채우고 이 파일을 source하는 것뿐이므로, 변수를 우리가 채우면
# 같은 코드가 같은 일을 한다. chronyc는 컨테이너에서 곧바로 실패하고 hook이
# 그 실패를 삼킨다 — 그것도 이 검사가 함께 본다(rc 0).
#
# tars_sources_dir을 덮어쓰는 유일한 자리다(TS-M2 결정 M2-C). 안 덮으면 이
# 검사가 컨테이너의 진짜 /run/tars에 쓴다.
HOOK=../kernel/dhcpcd-hooks/30-tars-ntp
HOOKDIR="$(mktemp -d)"

if ! new_ntp_servers='192.0.2.1 198.51.100.7' \
     tars_sources_dir="${HOOKDIR}/src" sh "$HOOK"; then
  echo "FAIL: the dhcpcd hook exited non-zero"
  rm -rf "$HOOKDIR"
  exit 1
fi
HOOK_LINE="$(cat "${HOOKDIR}/src/dhcp.sources" 2>/dev/null || true)"
if [ "$HOOK_LINE" != "server 192.0.2.1 iburst" ]; then
  echo "FAIL: the dhcpcd hook wrote [${HOOK_LINE}] where 'server 192.0.2.1 iburst' was expected"
  rm -rf "$HOOKDIR"
  exit 1
fi
if [ -e "${HOOKDIR}/src/dhcp.sources.tmp" ]; then
  echo "FAIL: the dhcpcd hook left its .tmp file behind"
  rm -rf "$HOOKDIR"
  exit 1
fi

# 음성. option 42가 없는 리스에서는 디렉터리도 안 만든다 — chronyd는 서버
# 0개로 기다리는 것이 맞다.
rm -rf "${HOOKDIR}/src"
if ! tars_sources_dir="${HOOKDIR}/src" sh "$HOOK"; then
  echo "FAIL: the dhcpcd hook exited non-zero with no ntp servers"
  rm -rf "$HOOKDIR"
  exit 1
fi
if [ -e "${HOOKDIR}/src" ]; then
  echo "FAIL: the dhcpcd hook made a sources directory with no ntp servers to write"
  rm -rf "$HOOKDIR"
  exit 1
fi
rm -rf "$HOOKDIR"
echo "the dhcpcd hook writes the first ntp server as a chrony source and nothing else"
```

- [ ] Step 3: 부팅 B가 심는 파일(`build_ntp_initrd`)

```bash
  mkdir -p "${extra}/run/tars/chrony.sources"
  printf 'server %s iburst\n' "$NTP_DEAD_SERVER" > "${extra}/run/tars/chrony.sources/dhcp.sources"
```

그 위 주석의 "init에게는 우리가 심은 파일과 dhcpcd의 hook이 쓴 파일이 구별되지
않는다"를 "chronyd에게는 …"으로, "`파일 → init` 조각"을 "`파일 → chronyd` 조각"으로
바꾼다. 부팅 B 머리의 echo와 주석 "initrd에 /run/tars/ntp_servers가 미리 있다" ·
"1. init이 그 파일을 읽는다 — 로그가 심은 주소를 이름 대며 찍는다"를 새 경로와
"1. chronyd가 그 파일을 읽는다 — `chronyc sources`가 심은 주소를 댄다"로 바꾼다.
`planted … in /run/tars/ntp_servers` echo도 새 경로로.

- [ ] Step 4: 검사 21을 바꾼다

```bash
# ── 검사 21: chronyd가 심은 source를 읽었나 ───────────────────────────
# DS-M1 결정 M1-E. init은 이제 이 파일을 안 읽는다 — chronyd가 sourcedir로
# 뜰 때 읽는다(DS design 결정 3 · DS-M0 실측 6). 그래서 chronyd에게 묻는다.
#
# 판정 글자(주소)가 친 명령에 없다(project_gate_screen_echo). 답의 줄머리
# `^?`는 "아직 한 번도 못 닿았다"다 — 상대가 없는 것이 이 부팅의 설계다.
#
# 주소까지 보는 것에 뜻이 있다. SLIRP가 option 42를 주는 날이 오면 hook이
# 심은 파일을 10.0.2.x로 덮어쓰고 이 검사가 그것을 알린다.
CONNECTED_B=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${NTP_DHCP_MONITOR_PORT}"; then CONNECTED_B=1; break; fi
  sleep 0.5
done
[ "$CONNECTED_B" = "1" ] || \
  fail "could not connect to the ntp=dhcp guest's QEMU monitor" "terminal: screen>"
echo "=== typing 'chronyc -n sources' ==="
type_keys c h r o n y c spc minus n spc s o u r c e s ret
if ! wait_for_screen "${NTP_DEAD_SERVER//./\\.}"; then
  fail "chronyd did not list ${NTP_DEAD_SERVER} from the planted chrony.sources" \
    "tars-init: chronyd" "chronyd"
fi
exec 3<&-
exec 3>&-
echo "chronyd read ${NTP_DEAD_SERVER} out of the planted chrony.sources"
```

`wait_for_screen`은 전역 `$LOG`를 본다. 부팅 B의 머리에서 `LOG="$LOGB"`인지 확인한다.

- [ ] Step 5: 검사 16의 주석(`grace period expired`, 990행 근처)을 고친다

"이 부팅에는 dhcpcd가 있고 그것은 감독 목록 밖에 있다(결정 9의 갈래 A) — … 우리가
띄운 것 중 유일하게 Child 배열에 없는 프로세스다." 문단을 이렇게 바꾼다.

```bash
# DS-M1부터 dhcpcd는 감독 목록 안이다(DS design 결정 1). 전원 경로는 그와
# 무관하게 kill(-1)로 모두에게 보내고, dhcpcd는 SIGTERM에 100~150ms에 죽는다
# (DS-M0 실측 3). 그 전제가 깨지는 날 여기가 빨간불이 된다.
```

- [ ] Step 6: 남은 옛 글자가 없는지

```bash
rg -n "ntp_servers|came from|clock child|waiting for /run|gave up waiting|bringUp|clock\.start|startDhcpcd" \
  init/src net nic firewall check.sh kernel/make_initrd.sh kernel/dhcpcd-hooks service
```

기대: `-o ntp_servers`(net.zig의 argv와 그 주석) · `$new_ntp_servers`(hook) 말고는
없다. 나오면 그 자리를 읽고 새 모양으로 고친다.

## Task 8 — 체인 넷을 돌린다 (약 25분)

- [ ] Step 1: 순서대로 돌린다. 커널 빌드를 공유하므로 병렬로 돌리지 않는다.

```bash
for c in net nic firewall service; do
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./$c/check.sh > /tmp/ds-$c.log 2>&1
  echo "$c exit=$?"; grep -c '^FAIL' /tmp/ds-$c.log
done
```

`run_in_background`로 돌린다(Bash 10분 상한).

- [ ] Step 2: 읽는다

```bash
grep -E "dhcpcd joins|started service (dhcpcd|chronyd)|chronyd will ask|service .* is a name init keeps" /tmp/ds-*.log | head -20
grep -E "^(the |init |chronyd |dhcpcd )" /tmp/ds-net.log | tail -40
```

적을 것 — 네 체인의 exit와 `FAIL` 수, 부팅마다 `started service dhcpcd`와
`started service chronyd`가 한 번씩인가(재시작이 없었나 — `restarting` · `giving up`이
있으면 그 까닭), net 부팅 B의 검사 21, service 체인의 `status` 표에 두 줄이 더해졌는데
기존 검사가 그것에 흔들렸는가.

- [ ] Step 3: 빨간 것이 있으면 `superpowers:systematic-debugging`으로 원인을 먼저 찾는다.
  plan의 결정을 바꿔야 하면 멈추고 사용자에게 알린다.

## Task 9 — 커밋 · 실측 · 닫기

- [ ] Step 1: Task 2~4 · 6 · 7을 한 커밋으로. 지운 줄을 읽는다.

```bash
git status --short
git diff --stat
git diff init/src/clock.zig init/src/net.zig | grep '^-' | grep -v '^---' | head -120
git add init/src/clock.zig init/src/clock_test.zig init/src/net.zig init/src/main.zig \
        kernel/dhcpcd-hooks/30-tars-ntp kernel/make_initrd.sh \
        net/check.sh nic/check.sh firewall/check.sh check.sh
git commit -m "Supervise dhcpcd and chronyd; chrony takes DHCP servers via sourcedir"
```

- [ ] Step 2: design에 "DS-M1이 실행으로 증명한 것"(실측 8부터)과 "M1이 M2에 넘기는 것"을
  적고, `Status:`를 "M1 끝났다"로 고친다. plan과 함께 커밋한다.

```bash
git add docs/superpowers/specs/2026-09-27-tars-daemon-supervision-design.md \
        docs/superpowers/plans/2026-09-27-tars-daemon-supervision-ds-m1.md
git commit -m "Close DS-M1: dhcpcd and chronyd under the supervisor"
```

## 이 milestone이 끝난 자리

두 데몬이 감독 목록에 있고, 이웃 체인이 새 로그 줄로 초록이다. 새 성질(죽이면
다시 뜬다 · `tars-service`가 다룬다 · 버튼 fd가 안 샌다 · `ntp=dhcp`에서 chronyd가
재시작 없이 산다)은 아직 게이트가 안 본다 — M2의 일이다.
