# CT-M1 — 통로 · 감독 규칙 · `tars-service`

> 이 plan을 실행하는 사람에게: 코드는 Claude Code가 넣는다(CLAUDE.md 진행 방식 2).
> 매 편집 뒤 `git diff --stat`으로 더한 줄과 지운 줄을 세고, 지우는 편집은
> `git diff | grep '^-'`로 의도한 줄만 지워졌는지 본다. 명령은 전부 저장소 뿌리에서
> 친다.

Goal: CT design 결정 2~7을 코드로 세운다 — PID 1이 `/run/tars/init.sock`에서 요청
하나를 받아 답하고, 감독 루프가 `hold` · `kill_at`을 따르고, 게스트에 `tars-service`가
실린다. 호스트 검사가 순수한 쪽과 소켓 왕복을 보고, 부팅 하나(체인 아님)가 게스트에서
동사 넷을 손으로 쳐 본다. 체인 `service/check.sh`의 부팅은 M2다.

Architecture: 새 파일 `init/src/control.zig`가 통로의 양 끝(`open` · `receive` · `reply`
와 `dial` · `awaitReply`)과 감독 규칙(`apply` · `reaped` · `overdue` · `wantsRunning` ·
`stateOf`)과 글자(`parseRequest` · `row` · `parseRow`)를 든다. 규칙은 `Child`를 모르고
필드 이름(`pid` · `given_up` · `fast_restarts` · `hold` · `kill_at`)으로만 만진다
(`anytype`) — 그래서 호스트 검사가 가짜 구조체로 전부 본다. `main.zig`는 listen fd를
`poll`에 붙이고 규칙 함수를 부르는 자리만 바뀐다. `init/src/service_cli.zig`가
`tars-service`다.

Tech Stack: Zig 0.16(`std.os.linux` raw syscall, libc 없음) · `zig build test` · bash ·
QEMU

---

## M0 실측이 정한 것과 이 plan이 새로 정하는 것

M0에서 온 것(design 실측 1~6):

- 시그널은 SIGTERM · SIGKILL 둘 다 `kill(-pid)`로 그룹에 보낸다(결정 4, 실측 5).
- 요청 길이는 `recvfrom(..., MSG_TRUNC)`의 반환값으로 가른다. 답은 `MSG_NOSIGNAL`로
  보낸다(실측 2).
- sshd의 멈춤은 `exited status 0`과 `killed signal 15` 두 모양이다(실측 3). 감독 규칙은
  죽은 모양을 보지 않고 `hold`만 본다.

이 plan이 정하는 것:

- M1-A. 클라이언트는 이름을 거르지 않고 보낸다. 거르는 것은 PID 1 한 곳이다 — 그래야
  게이트가 `tars-service stop 'a b'`(→ `error: bad request`)와 70바이트 이름(→ `error:
  request of 75 bytes, at most 64`)으로 PID 1의 거절을 게스트에서 본다. 클라이언트의 요청
  버퍼는 256이다.
- M1-B. 클라이언트의 기다림은 5초가 아니라 8초다. SIGTERM을 무시하는 서비스는
  `kill_at`이 초 단위(`monotonicSeconds`)라 2~3초 뒤에 시한이 되고, 루프가 1초마다
  깨므로 SIGKILL이 최악 4초, 거둠이 최악 5초다. 5초는 경계라 8초로 둔다(design 결정 6을
  고친다).
- M1-C. exit code에 사용법 오류 64(`EX_USAGE`)를 더한다. 2는 "통로 없음"이 쓴다.
- M1-D. 이름 없는 대상의 거절은 `error: no service named terminal` 하나다. `console
  shell`은 공백이 있어 이름 한 개로 올 수 없다(design 결정 5의 오류 문구를 고친다).
- M1-E. 로그 줄. 게이트(M2)가 grep할 것이다.
  - `tars-init: control socket /run/tars/init.sock` · `tars-init: no control socket (<단계>
    errno N)`
  - `tars-init: control: stop service sshd -> stopping`
  - `tars-init: service sshd stopped on request` · `tars-init: restarting service sshd on
    request`
  - `tars-init: service stubborn outlived SIGTERM by 3s, sent SIGKILL to group N`
  - `tars-init: control: bad request (N bytes)` · `tars-init: control client sent nothing
    in 200ms`

## 파일

| 파일 | 무엇 |
|---|---|
| 새 `init/src/control.zig` | 통로 · 규칙 · 글자 |
| 새 `init/src/control_test.zig` | 호스트 검사 |
| 새 `init/src/service_cli.zig` | `tars-service` |
| `init/src/services.zig` | `LABEL_PREFIX`를 `pub`으로 |
| `init/src/main.zig` | `Child`의 두 칸 · `supervise`의 listen fd · `serveControl` · `answer` · `main()`의 `control.open` |
| `init/build.zig` | `tars-service` exe · `control_test` |
| `kernel/make_initrd.sh` | `/usr/bin/tars-service` |

## Task 1 — 검사를 먼저 쓴다

- [ ] Step 1: `init/src/control_test.zig`

```zig
const std = @import("std");
const linux = std.os.linux;
const control = @import("control.zig");

/// 이 검사가 쓰는 소켓 자리. 게스트가 아니라 빌드 컨테이너의 /tmp다.
const DIR = "/tmp/tars-control-test";
const PATH = DIR ++ "/init.sock";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn fail(comptime fmt: []const u8, args: anytype) error{Failed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Failed;
}

/// `Child`에서 규칙이 만지는 다섯 칸만 든 가짜. 필드 이름이 곧 계약이다.
const Fake = struct {
    pid: linux.pid_t = -1,
    given_up: bool = false,
    fast_restarts: u32 = 0,
    hold: control.Hold = .none,
    kill_at: isize = 0,
};

fn expectParse(bytes: []const u8, verb: ?control.Verb, name: ?[]const u8) !void {
    const got = control.parseRequest(bytes);
    if (verb == null) {
        if (got != null) return fail("parseRequest(\"{s}\") accepted, want rejected", .{bytes});
        return;
    }
    const r = got orelse return fail("parseRequest(\"{s}\") rejected", .{bytes});
    if (r.verb != verb.?) return fail("parseRequest(\"{s}\") verb {s}", .{ bytes, @tagName(r.verb) });
    if ((r.name == null) != (name == null)) return fail("parseRequest(\"{s}\") name presence", .{bytes});
    if (name) |n| if (!std.mem.eql(u8, r.name.?, n)) return fail("parseRequest(\"{s}\") name {s}", .{ bytes, r.name.? });
}

fn expectRow(label: []const u8, state: control.State, pid: linux.pid_t, up: isize, want: []const u8) !void {
    var buf: [256]u8 = undefined;
    var out = control.Out{ .buf = &buf };
    control.row(&out, label, state, pid, up);
    if (!std.mem.eql(u8, out.bytes(), want)) return fail("row gave [{s}], want [{s}]", .{ out.bytes(), want });
    const seen = control.parseRow(out.bytes(), label) orelse return fail("parseRow could not read [{s}]", .{want});
    if (seen.state != state or seen.pid != pid) return fail("parseRow read {s}/{d} from [{s}]", .{ @tagName(seen.state), seen.pid, want });
}

fn expectApplied(got: control.Applied, outcome: control.Outcome, signal: bool) !void {
    if (got.outcome != outcome or got.signal != signal)
        return fail("apply gave {s}/signal={any}, want {s}/signal={any}", .{ @tagName(got.outcome), got.signal, @tagName(outcome), signal });
}

fn expectState(c: *const Fake, want: control.State) !void {
    const got = control.stateOf(c);
    if (got != want) return fail("stateOf gave {s}, want {s}", .{ @tagName(got), @tagName(want) });
}

fn rawConnect() !i32 {
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return fail("socket errno {d}", .{@intFromEnum(e)});
    const fd: i32 = @intCast(rc);
    var a: linux.sockaddr.un = .{ .path = [_]u8{0} ** 108 };
    @memcpy(a.path[0..PATH.len], PATH);
    if (failed(linux.connect(fd, &a, @sizeOf(linux.sockaddr.un)))) |e| return fail("connect errno {d}", .{@intFromEnum(e)});
    return fd;
}

pub fn main() !void {
    // ── 요청의 글자 ─────────────────────────────────────────────────
    try expectParse("status", .status, null);
    try expectParse("status sshd", .status, "sshd");
    try expectParse("stop sshd", .stop, "sshd");
    try expectParse("start web-1.x", .start, "web-1.x");
    try expectParse("restart sshd", .restart, "sshd");
    try expectParse("a" ** 0, null, null);
    try expectParse("stop", null, null);
    try expectParse("fly sshd", null, null);
    try expectParse("stop a b", null, null);
    try expectParse("stop  sshd", null, null);
    try expectParse("stop sshd\n", null, null);
    try expectParse("stop " ++ "n" ** 32, .stop, "n" ** 32);
    try expectParse("stop " ++ "n" ** 33, null, null);
    try expectParse("stop \x1b[2J", null, null);
    var req_buf: [control.REQUEST_MAX]u8 = undefined;
    const req = control.formatRequest(&req_buf, .restart, "sshd") orelse return fail("formatRequest failed", .{});
    try expectParse(req, .restart, "sshd");
    std.debug.print("control_test: requests — four verbs, one name, nothing else\n", .{});

    // ── 답의 글자 ──────────────────────────────────────────────────
    try expectRow("service sshd", .running, 51, 118, "service sshd    running   pid 51   up 118s\n");
    try expectRow("console shell", .running, 46, 120, "console shell   running   pid 46   up 120s\n");
    try expectRow("service broken", .given_up, -1, 0, "service broken  given up\n");
    try expectRow("service web", .stopped, -1, 0, "service web     stopped\n");
    try expectRow("service web", .stopping, 70, 3, "service web     stopping  pid 70   up 3s\n");
    try expectRow("service web", .restarting, 70, 3, "service web     restarting pid 70   up 3s\n");
    try expectRow("service web", .starting, -1, 0, "service web     starting\n");
    const long = "service " ++ "l" ** 32;
    try expectRow(long, .running, 9, 1, long ++ " running   pid 9   up 1s\n");
    if (control.parseRow("service sshd2   running   pid 5   up 1s\n", "service sshd") != null)
        return fail("parseRow matched service sshd2 for service sshd", .{});
    var tiny: [8]u8 = undefined;
    var small = control.Out{ .buf = &tiny };
    control.row(&small, "service sshd", .running, 51, 118);
    if (!small.full) return fail("an 8-byte Out did not report full", .{});
    std.debug.print("control_test: rows — fixed columns, parseRow reads back what row wrote\n", .{});

    // ── 감독 규칙 ──────────────────────────────────────────────────
    const now: isize = 100;
    var c = Fake{ .pid = 51 };
    try expectState(&c, .running);
    try expectApplied(control.apply(.start, &c, now), .already_running, false);
    try expectApplied(control.apply(.stop, &c, now), .stopping, true);
    if (c.hold != .stop or c.kill_at != now + control.GRACE_SECONDS) return fail("stop left hold {s} kill_at {d}", .{ @tagName(c.hold), c.kill_at });
    try expectState(&c, .stopping);
    try expectApplied(control.apply(.stop, &c, now + 1), .stopping, false); // 두 번 보내지 않는다
    if (c.kill_at != now + control.GRACE_SECONDS) return fail("a second stop moved kill_at", .{});
    if (control.overdue(&c, now + control.GRACE_SECONDS - 1)) return fail("overdue before the grace ran out", .{});
    if (!control.overdue(&c, now + control.GRACE_SECONDS)) return fail("not overdue when the grace ran out", .{});
    if (control.overdue(&c, now + control.GRACE_SECONDS + 1)) return fail("overdue twice for one stop", .{});
    c.pid = -1;
    if (control.reaped(&c) != .stays_stopped) return fail("a stopped death did not stay stopped", .{});
    if (control.wantsRunning(&c)) return fail("a stopped service wants to run", .{});
    try expectState(&c, .stopped);
    try expectApplied(control.apply(.stop, &c, now), .already_stopped, false);
    try expectApplied(control.apply(.start, &c, now), .starting, false);
    if (!control.wantsRunning(&c)) return fail("a started service does not want to run", .{});
    std.debug.print("control_test: stop sends SIGTERM once, holds after the reap, start lets go\n", .{});

    c = Fake{ .pid = 60, .fast_restarts = 2 };
    try expectApplied(control.apply(.restart, &c, now), .restarting, true);
    try expectApplied(control.apply(.restart, &c, now), .restarting, false);
    if (c.fast_restarts != 0) return fail("restart kept fast_restarts {d}", .{c.fast_restarts});
    try expectState(&c, .restarting);
    c.pid = -1;
    if (control.reaped(&c) != .restarts) return fail("a restarted death did not restart", .{});
    if (c.hold != .none or c.kill_at != 0) return fail("restart left hold {s} kill_at {d}", .{ @tagName(c.hold), c.kill_at });
    if (!control.wantsRunning(&c)) return fail("a restarted service does not want to run", .{});
    try expectState(&c, .starting);
    std.debug.print("control_test: restart is not a fast death and comes back\n", .{});

    c = Fake{ .given_up = true, .fast_restarts = 3 };
    try expectState(&c, .given_up);
    try expectApplied(control.apply(.start, &c, now), .starting, false);
    if (c.given_up or c.fast_restarts != 0) return fail("start did not clear a given-up service", .{});
    c = Fake{ .given_up = true };
    try expectApplied(control.apply(.restart, &c, now), .starting, false);
    if (c.given_up) return fail("restart did not clear a given-up service", .{});
    c = Fake{ .pid = 70 };
    _ = control.apply(.stop, &c, now);
    try expectApplied(control.apply(.start, &c, now), .starting, false); // 죽어 가는 중이면 뜻만 바꾼다
    c.pid = -1;
    if (control.reaped(&c) != .restarts) return fail("start during a stop did not restart", .{});
    c = Fake{ .pid = 80 };
    if (control.reaped(&c) != .normal) return fail("an unrequested death was not normal", .{});
    std.debug.print("control_test: start revives a given-up service, a plain death is normal\n", .{});

    // ── 클라이언트가 기다리는 끝 ─────────────────────────────────────
    if (!control.reached(.stop, .{ .state = .stopped, .pid = -1 }, 5)) return fail("reached stop", .{});
    if (control.reached(.stop, .{ .state = .stopping, .pid = 5 }, 5)) return fail("reached stop while stopping", .{});
    if (!control.reached(.start, .{ .state = .running, .pid = 6 }, -1)) return fail("reached start", .{});
    if (control.reached(.restart, .{ .state = .running, .pid = 5 }, 5)) return fail("reached restart with the old pid", .{});
    if (!control.reached(.restart, .{ .state = .running, .pid = 6 }, 5)) return fail("reached restart", .{});
    std.debug.print("control_test: the client waits for stopped, running, or running with a new pid\n", .{});

    // ── 소켓 왕복 ─────────────────────────────────────────────────
    const lfd = control.open(DIR, PATH) orelse return fail("open gave no socket", .{});
    var st: linux.Statx = undefined;
    _ = linux.statx(linux.AT.FDCWD, PATH, 0, .{ .TYPE = true, .MODE = true }, &st);
    if (st.mode != 0o140600) return fail("socket mode {o}, want 140600", .{st.mode});

    const d = control.dial(PATH, "stop sshd");
    const cfd = switch (d) {
        .fd => |fd| fd,
        .failed => |e| return fail("dial errno {d}", .{@intFromEnum(e)}),
    };
    var in_buf: [control.REQUEST_MAX]u8 = undefined;
    const got = control.receive(lfd, &in_buf) orelse return fail("receive got nothing", .{});
    switch (got.what) {
        .request => |bytes| if (!std.mem.eql(u8, bytes, "stop sshd")) return fail("receive got [{s}]", .{bytes}),
        else => return fail("receive got {s}", .{@tagName(got.what)}),
    }
    control.reply(got.fd, "stopping service sshd (pid 51)\n");
    var out_buf: [control.REPLY_MAX]u8 = undefined;
    const answer = control.awaitReply(cfd, &out_buf, 1000) orelse return fail("awaitReply got nothing", .{});
    if (!std.mem.eql(u8, answer, "stopping service sshd (pid 51)\n")) return fail("awaitReply got [{s}]", .{answer});

    const big = [_]u8{'x'} ** 100;
    const bfd = switch (control.dial(PATH, &big)) {
        .fd => |fd| fd,
        .failed => |e| return fail("dial big errno {d}", .{@intFromEnum(e)}),
    };
    const g2 = control.receive(lfd, &in_buf) orelse return fail("receive big got nothing", .{});
    switch (g2.what) {
        .too_long => |n| if (n != 100) return fail("too_long {d}, want 100", .{n}),
        else => return fail("a 100-byte request was {s}", .{@tagName(g2.what)}),
    }
    control.reply(g2.fd, "x");
    _ = linux.close(bfd);

    const sfd = try rawConnect();
    const g3 = control.receive(lfd, &in_buf) orelse return fail("receive silent got nothing", .{});
    if (g3.what != .silent) return fail("a silent client was {s}", .{@tagName(g3.what)});
    _ = linux.close(g3.fd);
    _ = linux.close(sfd);
    if (control.receive(lfd, &in_buf) != null) return fail("receive with nobody waiting returned something", .{});

    _ = linux.close(lfd);
    switch (control.dial(PATH, "status")) {
        .failed => |e| if (e != .CONNREFUSED) return fail("dial to a closed listener errno {d}", .{@intFromEnum(e)}),
        .fd => return fail("dial to a closed listener succeeded", .{}),
    }
    _ = linux.unlink(PATH);
    switch (control.dial(PATH, "status")) {
        .failed => |e| if (e != .NOENT) return fail("dial to no socket errno {d}", .{@intFromEnum(e)}),
        .fd => return fail("dial to no socket succeeded", .{}),
    }
    std.debug.print("control_test: socket — 0600, one request each way, 100 bytes too long, silence ends, no listener is refused\n", .{});
}
```

- [ ] Step 2: `init/build.zig`에 검사를 등록한다

`login_test` 블록 뒤, `test_step` 앞에:

```zig
    // CT-M1: 통로 · 감독 규칙 · 글자. login_test와 같은 이유로 host_target이다 —
    // 규칙은 anytype으로 필드만 만져 가짜 구조체로 보고, 소켓은 /tmp에 연다.
    const control_test_mod = b.createModule(.{
        .root_source_file = b.path("src/control_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const control_test = b.addExecutable(.{
        .name = "control_test",
        .root_module = control_test_mod,
    });
```

그리고 `test_step.dependOn(&b.addRunArtifact(login_test).step);` 뒤에:

```zig
    test_step.dependOn(&b.addRunArtifact(control_test).step);
```

- [ ] Step 3: 돌려서 실패를 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | tail -5
```

기대: `control.zig`가 없어 컴파일이 실패한다(`unable to load ... control.zig` 모양).

## Task 2 — `control.zig`

- [ ] Step 1: `init/services.zig`의 `LABEL_PREFIX`를 `pub`으로

```zig
pub const LABEL_PREFIX = "service ";
```

`main.zig`가 이름과 라벨을 잇는 자리에서 쓴다(Task 3).

- [ ] Step 2: `init/src/control.zig`

```zig
//! CT-M1. 사람의 명령이 PID 1까지 오는 세 번째 입력 — Unix 소켓 하나.
//!
//! PID 1이 바깥에서 받는 입력은 시그널 둘과 전원 버튼 fd였다(CT design 확인 3). 이
//! 파일은 셋째 입력의 양 끝을 든다 — `main.zig`의 감독 루프가 쓰는 listen 쪽(`open` ·
//! `receive` · `reply`)과 `tars-service`가 쓰는 connect 쪽(`dial` · `awaitReply`).
//!
//! 감독 규칙(무엇을 띄우고 무엇을 두는가)도 여기 있다. 규칙은 `Child`를 모르고 필드
//! 이름(`pid` · `given_up` · `fast_restarts` · `hold` · `kill_at`)으로만 만진다 —
//! `anytype`이라 호스트 검사가 가짜 구조체로 전부 본다(`control_test.zig`). 시그널을
//! 보내는 것은 규칙이 아니라 `main.zig`다. 규칙은 "보내라"를 돌려줄 뿐이다.
const std = @import("std");
const linux = std.os.linux;
const services = @import("services.zig");

pub const DIR: [:0]const u8 = "/run/tars";
pub const PATH: [:0]const u8 = "/run/tars/init.sock";

/// 요청 한 개의 상한(design 결정 3). 가장 긴 옳은 요청이 "restart " + 32 = 40이다.
pub const REQUEST_MAX: usize = 64;
/// 답 한 개의 상한. status 한 벌이 줄 열 개 × 70바이트 안팎이고, SEQPACKET은 1000바이트
/// 답을 `recv` 한 번에 보냈다(CT-M0 실측 2).
pub const REPLY_MAX: usize = 2048;
/// 붙은 상대가 요청을 보낼 때까지 PID 1이 기다리는 시간. 이것이 PID 1이 한 연결에
/// 붙잡히는 상한이다(결정 3, 실측 2).
pub const WAIT_MS: i32 = 200;
/// SIGTERM 뒤 SIGKILL까지의 유예. `power.zig`의 종료 유예와 같은 값이다.
pub const GRACE_SECONDS: isize = 3;

pub const ERROR_PREFIX = "error: ";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

// ── 요청 ───────────────────────────────────────────────────────────

pub const Verb = enum { status, stop, start, restart };

pub const Request = struct {
    verb: Verb,
    /// 서비스 이름. `status`만 null일 수 있다. 요청 버퍼 안을 가리킨다.
    name: ?[]const u8,
};

/// 이름은 services.d의 파일 이름이라 무엇이든 될 수 있지만, 요청으로 오는 이름은
/// 공백과 제어 문자를 받지 않는다 — 공백은 낱말을 가르고, 제어 문자는 PID 1이 그 이름을
/// 로그와 답에 되돌려 찍을 때 터미널을 조종한다(DI-M1 실측 15와 같은 까닭).
fn nameOk(name: []const u8) bool {
    if (name.len == 0 or name.len > services.NAME_MAX) return false;
    for (name) |b| if (b <= 0x20 or b == 0x7f) return false;
    return true;
}

/// "동사" 또는 "동사 이름". 공백 하나로만 가르고 줄 끝 문자도 받지 않는다 — 요청을
/// 짓는 것은 `formatRequest` 하나라서 그 모양 밖의 것은 전부 거절이다.
pub fn parseRequest(bytes: []const u8) ?Request {
    var it = std.mem.splitScalar(u8, bytes, ' ');
    const word = it.next() orelse return null;
    const verb = std.meta.stringToEnum(Verb, word) orelse return null;
    const name = it.next();
    if (it.next() != null) return null;
    if (name) |n| {
        if (!nameOk(n)) return null;
    } else if (verb != .status) return null;
    return .{ .verb = verb, .name = name };
}

pub fn formatRequest(buf: []u8, verb: Verb, name: ?[]const u8) ?[]const u8 {
    const text = if (name) |n|
        std.fmt.bufPrint(buf, "{s} {s}", .{ @tagName(verb), n })
    else
        std.fmt.bufPrint(buf, "{s}", .{@tagName(verb)});
    return text catch null;
}

// ── 감독 규칙 ───────────────────────────────────────────────────────

/// 사람이 요청한 것. `none`이 SV의 감독 그대로다.
pub const Hold = enum { none, stop, restart };

pub const State = enum {
    running,
    stopping,
    restarting,
    stopped,
    given_up,
    starting,

    pub fn word(self: State) []const u8 {
        return switch (self) {
            .given_up => "given up",
            else => @tagName(self),
        };
    }
};

/// status 한 줄의 상태. 살아 있으면 `hold`가, 죽어 있으면 그 뒤의 뜻이 가른다.
/// `starting`은 죽었고 다시 뜰 차례라는 뜻이다(재시작 1초 사이 · start 직후).
pub fn stateOf(c: anytype) State {
    if (c.pid >= 0) return switch (c.hold) {
        .none => .running,
        .stop => .stopping,
        .restart => .restarting,
    };
    if (c.hold == .stop) return .stopped;
    if (c.given_up) return .given_up;
    return .starting;
}

/// 감독 루프 머리의 띄우는 조건(design 결정 4 규칙 1).
pub fn wantsRunning(c: anytype) bool {
    return c.pid < 0 and !c.given_up and c.hold != .stop;
}

pub const Outcome = enum { stopping, stopped, already_stopped, starting, already_running, restarting };

pub const Applied = struct {
    outcome: Outcome,
    /// true면 `main.zig`가 지금 그룹에 SIGTERM을 보낸다.
    signal: bool,
};

fn revive(c: anytype) void {
    c.hold = .none;
    c.given_up = false;
    c.fast_restarts = 0;
}

/// 사람의 요청 하나를 칸에 반영한다. SIGTERM은 한 죽음에 한 번만 보낸다 — 이미 보낸
/// 뒤(`hold`가 `none`이 아니고 살아 있다)에 온 요청은 뜻만 바꾼다. 시한도 그때 한 번
/// 정해진다.
pub fn apply(verb: Verb, c: anytype, now: isize) Applied {
    switch (verb) {
        .status => unreachable,
        .stop => {
            if (c.pid < 0) {
                const was = c.hold == .stop;
                c.hold = .stop;
                return .{ .outcome = if (was) .already_stopped else .stopped, .signal = false };
            }
            const sent = c.hold != .none;
            c.hold = .stop;
            if (!sent) c.kill_at = now + GRACE_SECONDS;
            return .{ .outcome = .stopping, .signal = !sent };
        },
        .start => {
            if (c.pid >= 0) {
                if (c.hold == .none) return .{ .outcome = .already_running, .signal = false };
                // 죽어 가는 중이다. 거두고 나서 다시 띄우게 뜻만 바꾼다.
                c.hold = .restart;
                c.fast_restarts = 0;
                return .{ .outcome = .starting, .signal = false };
            }
            revive(c);
            return .{ .outcome = .starting, .signal = false };
        },
        .restart => {
            if (c.pid < 0) {
                revive(c);
                return .{ .outcome = .starting, .signal = false };
            }
            const sent = c.hold != .none;
            c.hold = .restart;
            c.fast_restarts = 0;
            if (!sent) c.kill_at = now + GRACE_SECONDS;
            return .{ .outcome = .restarting, .signal = !sent };
        },
    }
}

pub const Reaped = enum { normal, stays_stopped, restarts };

/// 감독 루프가 자식을 거두고 `pid = -1`로 둔 직후에 부른다. 사람이 요청한 죽음이면
/// 빨리 죽음으로 세지 않는다(design 결정 4 규칙 2) — 세면 `restart` 셋에 포기된다
/// (CT-M0 실측 6).
pub fn reaped(c: anytype) Reaped {
    c.kill_at = 0;
    return switch (c.hold) {
        .none => .normal,
        .stop => .stays_stopped,
        .restart => blk: {
            c.hold = .none;
            break :blk .restarts;
        },
    };
}

/// SIGTERM의 유예가 지났는가. true를 한 번만 돌려준다 — 시한을 지우므로 SIGKILL도
/// 한 죽음에 한 번이다.
pub fn overdue(c: anytype, now: isize) bool {
    if (c.pid < 0 or c.kill_at == 0 or now < c.kill_at) return false;
    c.kill_at = 0;
    return true;
}

/// 클라이언트가 기다리는 끝(design 결정 6). restart는 옛 pid와 다른 pid로 돌아야 끝이다.
pub fn reached(verb: Verb, seen: Seen, old_pid: linux.pid_t) bool {
    return switch (verb) {
        .status => true,
        .stop => seen.state == .stopped,
        .start => seen.state == .running,
        .restart => seen.state == .running and seen.pid != old_pid,
    };
}

// ── 답의 글자 ───────────────────────────────────────────────────────

/// 고정 버퍼에 이어 쓴다. 넘치면 멈추고 `full`을 세운다 — PID 1이 답을 짓다가 죽는
/// 길을 두지 않는다.
pub const Out = struct {
    buf: []u8,
    len: usize = 0,
    full: bool = false,

    pub fn print(self: *Out, comptime fmt: []const u8, args: anytype) void {
        if (self.full) return;
        const s = std.fmt.bufPrint(self.buf[self.len..], fmt, args) catch {
            self.full = true;
            return;
        };
        self.len += s.len;
    }

    pub fn bytes(self: *const Out) []const u8 {
        return self.buf[0..self.len];
    }
};

const LABEL_COLUMN: usize = 16;
const STATE_COLUMN: usize = 10;

/// 칸을 맞춘다. 이미 넘었으면 공백 하나 — 라벨과 상태가 붙어 버리면 `parseRow`가 못 읽는다.
fn pad(out: *Out, used: usize, column: usize) void {
    var n: usize = if (used < column) column - used else 1;
    while (n > 0) : (n -= 1) out.print(" ", .{});
}

/// status의 한 줄. 살아 있을 때만 pid와 산 시간이 붙는다.
pub fn row(out: *Out, label: []const u8, state: State, pid: linux.pid_t, up: isize) void {
    out.print("{s}", .{label});
    pad(out, label.len, LABEL_COLUMN);
    const w = state.word();
    out.print("{s}", .{w});
    if (pid >= 0) {
        pad(out, w.len, STATE_COLUMN);
        out.print("pid {d}   up {d}s", .{ pid, up });
    }
    out.print("\n", .{});
}

pub fn outcome(out: *Out, o: Outcome, label: []const u8, pid: linux.pid_t) void {
    switch (o) {
        .stopping => out.print("stopping {s} (pid {d})\n", .{ label, pid }),
        .stopped => out.print("stopped {s}\n", .{label}),
        .already_stopped => out.print("{s} is already stopped\n", .{label}),
        .starting => out.print("starting {s}\n", .{label}),
        .already_running => out.print("{s} is already running (pid {d})\n", .{ label, pid }),
        .restarting => out.print("restarting {s} (pid {d})\n", .{ label, pid }),
    }
}

pub const Seen = struct { state: State, pid: linux.pid_t };

/// `row`가 쓴 줄에서 상태와 pid를 읽는다. 라벨 바로 뒤가 공백이어야 한다 — 그래야
/// `service sshd2`가 `service sshd`로 읽히지 않는다.
pub fn parseRow(line: []const u8, label: []const u8) ?Seen {
    if (!std.mem.startsWith(u8, line, label)) return null;
    const after = line[label.len..];
    if (after.len == 0 or after[0] != ' ') return null;
    const rest = std.mem.trimStart(u8, after, " ");
    const states = [_]State{ .given_up, .running, .stopping, .restarting, .stopped, .starting };
    for (states) |s| {
        const w = s.word();
        if (!std.mem.startsWith(u8, rest, w)) continue;
        var tail = std.mem.trimStart(u8, rest[w.len..], " ");
        var pid: linux.pid_t = -1;
        if (std.mem.startsWith(u8, tail, "pid ")) {
            tail = tail["pid ".len..];
            const end = std.mem.indexOfAny(u8, tail, " \n") orelse tail.len;
            pid = std.fmt.parseInt(linux.pid_t, tail[0..end], 10) catch return null;
        }
        return .{ .state = s, .pid = pid };
    }
    return null;
}

// ── 소켓 ───────────────────────────────────────────────────────────

const ALEN: linux.socklen_t = @sizeOf(linux.sockaddr.un);

fn addrOf(path: []const u8) ?linux.sockaddr.un {
    var a: linux.sockaddr.un = .{ .path = [_]u8{0} ** 108 };
    if (path.len >= a.path.len) return null;
    @memcpy(a.path[0..path.len], path);
    return a;
}

fn noSocket(step: []const u8, e: linux.E) ?i32 {
    std.debug.print("tars-init: no control socket ({s} errno {d})\n", .{ step, @intFromEnum(e) });
    return null;
}

fn closeAnd(fd: i32, step: []const u8, e: linux.E) ?i32 {
    _ = linux.close(fd);
    return noSocket(step, e);
}

/// PID 1 쪽. 소켓을 세우고 listen fd를 돌려준다. 무엇이 실패해도 null로 돌아온다 —
/// 통로가 없는 것은 CT 전의 상태 그대로다(feedback_boot_never_blocks).
///
/// NONBLOCK은 `receive`의 accept가 "없다"를 EAGAIN으로 답하게 하고, CLOEXEC는 이 fd가
/// 서비스와 콘솔 셸로 새지 않게 한다(위험 2, CT-M0 실측 2 · 7).
pub fn open(dir: [:0]const u8, path: [:0]const u8) ?i32 {
    if (failed(linux.mkdir(dir.ptr, 0o755))) |e| if (e != .EXIST) return noSocket("mkdir", e);
    _ = linux.unlink(path.ptr);
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return noSocket("socket", e);
    const fd: i32 = @intCast(rc);
    const a = addrOf(path) orelse return closeAnd(fd, "path", .NAMETOOLONG);
    if (failed(linux.bind(fd, @ptrCast(&a), ALEN))) |e| return closeAnd(fd, "bind", e);
    if (failed(linux.chmod(path.ptr, 0o600))) |e| return closeAnd(fd, "chmod", e);
    if (failed(linux.listen(fd, 4))) |e| return closeAnd(fd, "listen", e);
    std.debug.print("tars-init: control socket {s}\n", .{path});
    return fd;
}

pub const Received = struct {
    /// 받은 연결. 부른 쪽이 `reply`로 닫는다.
    fd: i32,
    what: union(enum) {
        /// WAIT_MS 안에 아무것도 안 왔다.
        silent,
        /// REQUEST_MAX를 넘었다. 값은 원래 길이다(MSG_TRUNC, 실측 2).
        too_long: usize,
        request: []const u8,
    },
};

/// PID 1 쪽. listen fd가 읽을 수 있다고 깨웠을 때 부른다. 연결 하나를 받아 요청 하나를
/// 읽는다. null이면 받을 연결이 없었다.
pub fn receive(lfd: i32, buf: *[REQUEST_MAX]u8) ?Received {
    const rc = linux.accept4(lfd, null, null, linux.SOCK.CLOEXEC);
    if (failed(rc)) |_| return null;
    const fd: i32 = @intCast(rc);
    var p = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const ready = linux.poll(&p, 1, WAIT_MS);
    if (failed(ready) != null or ready == 0) return .{ .fd = fd, .what = .silent };
    const n = linux.recvfrom(fd, buf, buf.len, linux.MSG.TRUNC | linux.MSG.DONTWAIT, null, null);
    if (failed(n) != null) return .{ .fd = fd, .what = .silent };
    if (n > buf.len) return .{ .fd = fd, .what = .{ .too_long = n } };
    return .{ .fd = fd, .what = .{ .request = buf[0..n] } };
}

/// 답을 보내고 연결을 닫는다. 상대가 이미 닫았으면 EPIPE이고 그것으로 끝이다 —
/// MSG_NOSIGNAL이라 SIGPIPE는 없다(실측 2).
pub fn reply(fd: i32, bytes: []const u8) void {
    _ = linux.sendto(fd, bytes.ptr, bytes.len, linux.MSG.NOSIGNAL | linux.MSG.DONTWAIT, null, 0);
    _ = linux.close(fd);
}

pub const Dialed = union(enum) { fd: i32, failed: linux.E };

/// `tars-service` 쪽. 붙어서 요청을 보낸다. 답은 `awaitReply`가 읽는다 — 둘을 가른
/// 것은 호스트 검사가 한 스레드에서 양 끝을 다 돌리기 위해서다. 받는 쪽이 없으면
/// ECONNREFUSED(소켓 파일만 남았다)나 ENOENT(파일도 없다)다(실측 2).
pub fn dial(path: [:0]const u8, request: []const u8) Dialed {
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0);
    if (failed(rc)) |e| return .{ .failed = e };
    const fd: i32 = @intCast(rc);
    const a = addrOf(path) orelse {
        _ = linux.close(fd);
        return .{ .failed = .NAMETOOLONG };
    };
    if (failed(linux.connect(fd, &a, ALEN))) |e| {
        _ = linux.close(fd);
        return .{ .failed = e };
    }
    if (failed(linux.sendto(fd, request.ptr, request.len, linux.MSG.NOSIGNAL, null, 0))) |e| {
        _ = linux.close(fd);
        return .{ .failed = e };
    }
    return .{ .fd = fd };
}

/// 답 하나를 읽고 닫는다. `ms` 안에 안 오면 null. 빈 답(PID 1이 답 없이 닫았다)은 빈
/// 슬라이스다.
pub fn awaitReply(fd: i32, buf: []u8, ms: i32) ?[]const u8 {
    defer _ = linux.close(fd);
    var p = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const ready = linux.poll(&p, 1, ms);
    if (failed(ready) != null or ready == 0) return null;
    const n = linux.recvfrom(fd, buf.ptr, buf.len, 0, null, null);
    if (failed(n) != null) return null;
    return buf[0..n];
}
```

- [ ] Step 3: 돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | tail -20
```

기대: `control_test:` 줄 여섯이 찍히고 다른 검사 여덟의 줄도 그대로다. 컴파일 에러가
나면 문구와 고친 모양을 적는다(M0 실측 1이 잰 모양 밖의 것 — `std.mem.trimStart` ·
`std.meta.stringToEnum` · `indexOfAny`).

- [ ] Step 4: 커밋

```bash
git status --short
git diff --stat
git add init/src/control.zig init/src/control_test.zig init/src/services.zig init/build.zig
git commit -m "Add control.zig: the socket, the hold rules and their host test"
```

## Task 3 — `main.zig`에 잇는다

- [ ] Step 1: import와 `Child`의 두 칸

import 목록 끝(`const login = …` 뒤):

```zig
const control = @import("control.zig");
```

`Child`의 `rescue` 칸 뒤:

```zig
    /// CT-M1. 사람이 요청한 것과 SIGKILL의 시한. 규칙은 `control.zig`에 있고 이 두
    /// 칸은 필드 이름으로만 만져진다 — 이름을 바꾸면 `control.zig`가 컴파일에서 막는다.
    hold: control.Hold = .none,
    kill_at: isize = 0,
```

- [ ] Step 2: `supervise`의 인자와 `poll` 배열

시그니처에 `control_fd: ?i32`를 `buttons` 뒤에 더한다. `fds` 배열을 한 칸 늘리고 listen
fd를 버튼 뒤에 붙인다:

```zig
    // poll에 넘길 배열. 버튼 fd들 뒤에 CT-M1의 listen fd가 한 칸 붙는다.
    var fds: [devices.MAX_BUTTONS + 1]linux.pollfd = undefined;
    for (buttons, 0..) |fd, i| {
        fds[i] = .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 };
    }
    const control_slot = buttons.len;
    var nfds: linux.nfds_t = buttons.len;
    if (control_fd) |fd| {
        fds[control_slot] = .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 };
        nfds += 1;
    }
```

(원래의 `const nfds: linux.nfds_t = buttons.len;` 한 줄이 지워진다.)

- [ ] Step 3: 루프 머리 — 띄우는 조건과 SIGKILL

```zig
        for (children) |*c| {
            if (control.wantsRunning(c)) start(c, envp);
        }

        // CT-M1 결정 4 규칙 3. SIGTERM을 무시한 서비스에게 유예 뒤 SIGKILL을 그룹으로
        // 보낸다(CT-M0 실측 5 — 리더에게만 보내면 자식이 고아로 남는다).
        const now = monotonicSeconds();
        for (children) |*c| {
            if (control.overdue(c, now)) {
                _ = linux.kill(-c.pid, .KILL);
                std.debug.print("tars-init: {s} outlived SIGTERM by {d}s, sent SIGKILL to group {d}\n", .{
                    c.label, control.GRACE_SECONDS, c.pid,
                });
            }
        }
```

(원래의 `if (c.pid < 0 and !c.given_up) start(c, envp);`가 지워진다.)

- [ ] Step 4: 거둔 뒤 — 요청한 죽음은 세지 않는다

`exited` / `killed` 로그 줄의 `if … else` 블록 바로 뒤, `if (lived < FAST_EXIT_SECONDS)` 앞에:

```zig
            // CT-M1 결정 4 규칙 2. 사람이 요청한 죽음은 빨리 죽음으로 세지 않는다 —
            // 세면 restart 셋에 포기된다(CT-M0 실측 6).
            switch (control.reaped(c)) {
                .normal => {},
                .stays_stopped => {
                    std.debug.print("tars-init: {s} stopped on request\n", .{c.label});
                    continue;
                },
                .restarts => {
                    std.debug.print("tars-init: restarting {s} on request\n", .{c.label});
                    continue;
                },
            }
```

- [ ] Step 5: `poll` 뒤 — 통로를 본다

버튼 fd의 `for` 블록 뒤(`supervise`의 `while (true)` 끝):

```zig
        // ── CT-M1. 셋째 입력 ────────────────────────────────────────
        if (control_fd != null and fds[control_slot].revents != 0) {
            const p = &fds[control_slot];
            if (p.revents & linux.POLL.IN != 0) serveControl(children, p.fd);
            const broken = linux.POLL.ERR | linux.POLL.HUP | linux.POLL.NVAL;
            if (p.revents & broken != 0) {
                std.debug.print("tars-init: control socket went away (revents {d})\n", .{p.revents});
                p.fd = -1;
            }
        }
```

- [ ] Step 6: `serveControl` · `answer` · `findService`

`supervise` 앞에:

```zig
/// CT-M1. 서비스 이름으로 자식을 찾는다. terminal과 콘솔 셸은 서비스가 아니라 안
/// 걸린다(design 결정 5).
fn findService(children: []Child, name: []const u8) ?*Child {
    for (children) |*c| {
        if (c.kind != .service) continue;
        if (std.mem.eql(u8, c.label[services.LABEL_PREFIX.len..], name)) return c;
    }
    return null;
}

/// 요청 하나에 답을 짓는다. 시그널은 여기서 보낸다 — 규칙(`control.apply`)은 "보내라"를
/// 돌려줄 뿐이다. 그룹에 보낸다(CT-M0 실측 5). 서비스는 fork 직후 `setsid`하므로 그 전의
/// 아주 짧은 창에서는 그룹이 아직 없어 ESRCH다 — 그때는 `kill_at`의 SIGKILL이 받는다.
fn answer(children: []Child, req: control.Request, out: *control.Out) void {
    const now = monotonicSeconds();
    if (req.verb == .status) {
        for (children) |*c| {
            if (req.name) |n| {
                if (c.kind != .service or !std.mem.eql(u8, c.label[services.LABEL_PREFIX.len..], n)) continue;
            }
            control.row(out, c.label, control.stateOf(c), c.pid, now - c.started_at);
        }
        if (req.name != null and out.len == 0)
            out.print(control.ERROR_PREFIX ++ "no service named {s}\n", .{req.name.?});
        return;
    }
    const name = req.name.?;
    const c = findService(children, name) orelse {
        out.print(control.ERROR_PREFIX ++ "no service named {s}\n", .{name});
        std.debug.print("tars-init: control: {s} {s} -> no such service\n", .{ @tagName(req.verb), name });
        return;
    };
    const pid = c.pid;
    const done = control.apply(req.verb, c, now);
    if (done.signal) _ = linux.kill(-pid, .TERM);
    control.outcome(out, done.outcome, c.label, pid);
    std.debug.print("tars-init: control: {s} {s} -> {s}\n", .{ @tagName(req.verb), c.label, @tagName(done.outcome) });
}

/// listen fd가 깨웠을 때 연결 하나를 처리한다. 붙잡히는 시간은 `control.WAIT_MS`가
/// 상한이다(design 결정 3).
fn serveControl(children: []Child, lfd: i32) void {
    var req_buf: [control.REQUEST_MAX]u8 = undefined;
    const got = control.receive(lfd, &req_buf) orelse return;
    var reply_buf: [control.REPLY_MAX]u8 = undefined;
    var out = control.Out{ .buf = &reply_buf };
    switch (got.what) {
        .silent => {
            std.debug.print("tars-init: control client sent nothing in {d}ms\n", .{control.WAIT_MS});
            _ = linux.close(got.fd);
            return;
        },
        .too_long => |n| {
            out.print(control.ERROR_PREFIX ++ "request of {d} bytes, at most {d}\n", .{ n, control.REQUEST_MAX });
            std.debug.print("tars-init: control: bad request ({d} bytes)\n", .{n});
        },
        .request => |bytes| {
            if (control.parseRequest(bytes)) |req| {
                answer(children, req, &out);
            } else {
                // 요청의 바이트는 찍지 않는다 — 누구든 ESC를 심을 수 있다.
                out.print(control.ERROR_PREFIX ++ "bad request\n", .{});
                std.debug.print("tars-init: control: bad request ({d} bytes)\n", .{bytes.len});
            }
        },
    }
    control.reply(got.fd, out.bytes());
}
```

- [ ] Step 7: `main()` — 통로를 열고 넘긴다

`supervise(...)` 호출 바로 앞에:

```zig
    // CT-M1. 서비스를 띄우기 전에 연다 — 사람이 부팅 직후에 쳐도 받을 자리가 있다.
    // 못 열면 로그 한 줄이고 CT 전과 같은 부팅이다.
    const control_fd = control.open(control.DIR, control.PATH);
```

호출을 `supervise(children[0 .. 2 + service_list.len], button_fds[0..button_count], control_fd, envp);`로.

- [ ] Step 8: 빌드와 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && zig build test 2>&1 | tail -3'
git diff --stat
git diff init/src/main.zig | grep '^-' | grep -v '^---'
```

기대: 빌드가 되고, 지워진 줄은 셋이다 — `const nfds: linux.nfds_t = buttons.len;` ·
`if (c.pid < 0 and !c.given_up) start(c, envp);` · 옛 `supervise(...)` 호출(과 시그니처
한 줄, `var fds` 한 줄).

- [ ] Step 9: 커밋

```bash
git add init/src/main.zig
git commit -m "Serve the control socket from PID 1 and follow hold in the supervisor"
```

## Task 4 — `tars-service`

- [ ] Step 1: `init/src/service_cli.zig`

```zig
//! CT-M1. `tars-service` — 사람이 서비스를 보고 멈추고 띄우는 명령.
//!
//! PID 1에게 요청 하나를 보내고 답을 찍는다. 기다림은 이쪽이 진다(design 결정 6) —
//! PID 1은 SIGTERM을 보내고 곧바로 답하므로, stop · start · restart는 `status NAME`을
//! 다시 물어 원하는 상태가 될 때까지 본다. 이름은 거르지 않고 보낸다(M1-A) — 거르는
//! 것은 PID 1 한 곳이다.
const std = @import("std");
const linux = std.os.linux;
const control = @import("control.zig");

const EXIT_OK: u8 = 0;
/// PID 1이 `error: `로 답했다.
const EXIT_REFUSED: u8 = 1;
/// 소켓이 없거나 PID 1이 답하지 않았다.
const EXIT_UNREACHABLE: u8 = 2;
/// 원하는 상태가 시한 안에 안 됐다.
const EXIT_TIMEOUT: u8 = 3;
const EXIT_USAGE: u8 = 64;

const REPLY_WAIT_MS: i32 = 2000;
/// 기다림의 시한(M1-B). SIGTERM을 무시하는 서비스가 최악 5초에 거둬진다.
const SETTLE_MS: u64 = 8000;
const SETTLE_STEP_MS: u64 = 200;

fn writeAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (linux.errno(n) != .SUCCESS) {
            if (linux.errno(n) == .INTR) continue;
            return;
        }
        off += n;
    }
}

fn complain(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-service: " ++ fmt ++ "\n", args) catch return;
    writeAll(2, text);
}

fn usage() u8 {
    writeAll(2,
        \\usage: tars-service status [NAME]
        \\       tars-service stop|start|restart NAME
        \\
    );
    return EXIT_USAGE;
}

fn sleepMs(ms: u64) void {
    const ts: linux.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = linux.nanosleep(&ts, null);
}

const Asked = union(enum) { reply: []const u8, down: linux.E, silent };

fn ask(request: []const u8, buf: []u8) Asked {
    return switch (control.dial(control.PATH, request)) {
        .failed => |e| .{ .down = e },
        .fd => |fd| if (control.awaitReply(fd, buf, REPLY_WAIT_MS)) |r|
            (if (r.len == 0) .silent else .{ .reply = r })
        else
            .silent,
    };
}

/// `status NAME`을 물어 한 줄을 읽는다. 못 읽으면 null.
fn look(name: []const u8, label: []const u8, buf: []u8) ?control.Seen {
    var req_buf: [256]u8 = undefined;
    const req = control.formatRequest(&req_buf, .status, name) orelse return null;
    return switch (ask(req, buf)) {
        .reply => |r| control.parseRow(r, label),
        else => null,
    };
}

fn settle(verb: control.Verb, name: []const u8, label: []const u8, old_pid: linux.pid_t) u8 {
    var buf: [control.REPLY_MAX]u8 = undefined;
    var waited: u64 = 0;
    while (waited <= SETTLE_MS) : (waited += SETTLE_STEP_MS) {
        if (look(name, label, &buf)) |seen| {
            if (control.reached(verb, seen, old_pid)) {
                var line: [control.REPLY_MAX]u8 = undefined;
                var out = control.Out{ .buf = &line };
                control.row(&out, label, seen.state, seen.pid, 0);
                // 산 시간은 방금 뜬 것이라 0 안팎이다 — 상태와 pid만 보인다.
                writeAll(1, out.bytes()[0 .. std.mem.indexOf(u8, out.bytes(), "   up ") orelse out.len]);
                writeAll(1, "\n");
                return EXIT_OK;
            }
        }
        sleepMs(SETTLE_STEP_MS);
    }
    complain("{s} did not {s} in {d}s", .{ label, @tagName(verb), SETTLE_MS / 1000 });
    return EXIT_TIMEOUT;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len < 2 or argv.len > 3) return usage();
    const verb = std.meta.stringToEnum(control.Verb, std.mem.span(argv[1])) orelse return usage();
    const name: ?[]const u8 = if (argv.len == 3) std.mem.span(argv[2]) else null;
    if (verb != .status and name == null) return usage();

    var req_buf: [256]u8 = undefined;
    const req = control.formatRequest(&req_buf, verb, name) orelse return usage();
    var label_buf: [256]u8 = undefined;
    const label: []const u8 = if (name) |n|
        (std.fmt.bufPrint(&label_buf, "service {s}", .{n}) catch return usage())
    else
        "";

    var buf: [control.REPLY_MAX]u8 = undefined;
    // restart는 옛 pid를 먼저 안다 — 다른 pid로 running이 되는 것이 "다시 떴다"다.
    const old_pid: linux.pid_t = if (verb == .restart)
        (if (look(name.?, label, &buf)) |s| s.pid else -1)
    else
        -1;

    const text = switch (ask(req, &buf)) {
        .down => |e| {
            complain("cannot reach init at {s} (errno {d})", .{ control.PATH, @intFromEnum(e) });
            return EXIT_UNREACHABLE;
        },
        .silent => {
            complain("init did not answer", .{});
            return EXIT_UNREACHABLE;
        },
        .reply => |r| r,
    };
    writeAll(1, text);
    if (std.mem.startsWith(u8, text, control.ERROR_PREFIX)) return EXIT_REFUSED;
    if (verb == .status) return EXIT_OK;
    return settle(verb, name.?, label, old_pid);
}
```

- [ ] Step 2: `init/build.zig`에 exe

`tars-install` 블록 뒤:

```zig
    // CT-M1: 서비스를 멈추고 띄우는 명령. tars-install과 같은 까닭으로 따로 된 exe이고
    // 같은 타깃 · 모드다. make_initrd.sh가 zig-out/bin/tars-service를 usr/bin에 싣는다.
    const service_mod = b.createModule(.{
        .root_source_file = b.path("src/service_cli.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const service_exe = b.addExecutable(.{
        .name = "tars-service",
        .root_module = service_mod,
    });
    b.installArtifact(service_exe);
```

- [ ] Step 3: `kernel/make_initrd.sh`

`tars-install`의 `chmod` 줄 뒤:

```bash

# CT-M1: 서비스 제어 명령. tars-install과 같은 까닭으로 정적이고 /usr/bin이다.
cp ../init/zig-out/bin/tars-service "$WORKDIR/usr/bin/tars-service"
chmod 0755 "$WORKDIR/usr/bin/tars-service"
```

- [ ] Step 4: 빌드

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && ls -la zig-out/bin'
```

기대: `init` · `tars-install` · `tars-service`.

- [ ] Step 5: 커밋

```bash
git add init/src/service_cli.zig init/build.zig kernel/make_initrd.sh
git commit -m "Add tars-service and carry it in the initrd"
```

## Task 5 — 게스트에서 손으로 쳐 본다 (부팅 하나, 약 3분)

CT-M0의 하네스(`/tmp/ct/`)를 다시 쓴다. 디스크는 같은 것(sshd 링크 · `sleeper` ·
`stubborn`)이고, 게스트 스크립트에 단계 `m1` 하나를 더한다.

- [ ] Step 1: `/tmp/ct/seed/ctm1.sh`를 쓰고 디스크에 넣는다

```bash
cat > /tmp/ct/seed/ctm1.sh <<'EOF'
#!/bin/bash
# CT-M1. 사람이 칠 모양 그대로 친다. 표지는 "CTM1-<이름> ".
mark() { printf 'CTM1-%s %s\n' "$1" "$2"; }
t() {  # $1 = 이름, 나머지 = tars-service 인자
  local tag="$1"; shift
  local out rc s
  s=$(date +%s%N)
  out=$(tars-service "$@" 2>&1); rc=$?
  mark RUN "$tag rc=$rc ms=$(( ($(date +%s%N) - s) / 1000000 )) out=[$(echo "$out" | tr '\n' ';')]"
}
t status0 status
t stop-sleeper stop sleeper
mark ORPHAN "sleep under pid 1: [$(ps -eo ppid=,comm= | grep -cE '^ *1 sleep$')]"
t stop-again stop sleeper
sleep 3
t status-stopped status sleeper
t start-sleeper start sleeper
t restart-sshd restart sshd
t restart-sshd2 restart sshd
t restart-sshd3 restart sshd
t restart-sshd4 restart sshd
t stop-stubborn stop stubborn
t start-running start sshd
t no-such stop nope
t terminal stop terminal
t bad stop 'a b'
t long stop "$(printf 'x%.0s' $(seq 1 70))"
t usage bogus
t status1 status
mark DONE m1
EOF
chmod 755 /tmp/ct/seed/ctm1.sh
docker run --rm -v /tmp/ct:/tmp/ct tars-devcontainer bash -c 'cd /tmp/ct && debugfs -w -R "write seed/ctm1.sh ctm1.sh" cfg.img 2>&1 | tail -1'
```

- [ ] Step 2: 하네스를 고쳐 돌린다

```bash
sed -e 's|bash /config/ctm0.sh %s|bash /config/ctm1.sh %s|' -e 's|CTM0-DONE|CTM1-DONE|g' /tmp/ct/boot.sh \
  | awk '/^run sock$/ { print "run m1"; skip = 1 } /^echo "=== done ==="/ { skip = 0 } !skip' > /tmp/ct/boot-m1.sh
tail -3 /tmp/ct/boot-m1.sh
docker run --rm -v "$PWD":/workspace -v /tmp/ct:/tmp/ct -w /workspace \
  tars-devcontainer bash /tmp/ct/boot-m1.sh > /tmp/ct/run-m1.log 2>&1; echo "exit=$?"
grep -aoE "CTM1-[A-Z]+ .*" /tmp/ct/guest.log | tr -d '\r'
grep -aE "tars-init: (control|.*on request|.*outlived|.*giving up|service )" /tmp/ct/guest.log | tr -d '\r'
```

기대(판정은 M2 체인이 한다 — 여기서는 눈으로 본다):

- `status0` rc 0, 다섯 줄(terminal · console shell · sleeper · sshd · stubborn), 전부 running.
- `stop-sleeper` rc 0, `stopping service sleeper (pid N)` 뒤 `service sleeper  stopped`.
  `ORPHAN` 0 — 그룹에 보냈다.
- `stop-again` rc 0, `service sleeper is already stopped`.
- `status-stopped` 3초 뒤에도 `stopped` — 되살아나지 않았다.
- `start-sleeper` rc 0, `running`.
- `restart-sshd` 넷 모두 rc 0, pid가 매번 바뀐다. init 로그에 `giving up on service sshd`가
  없다(CT-M0 실측 6과 반대).
- `stop-stubborn` rc 0이고 `ms`가 3000~5000, init 로그에 `outlived SIGTERM by 3s`.
- `start-running` rc 0, `service sshd is already running (pid N)`.
- `no-such` · `terminal` rc 1, `error: no service named …`.
- `bad` rc 1, `error: bad request`. `long` rc 1, `error: request of 75 bytes, at most 64`.
- `usage` rc 64.

- [ ] Step 3: 기대와 다르면

그 줄과 init 로그를 적고 원인을 찾는다(superpowers:systematic-debugging). 고친 것은 Task
2~4의 해당 커밋 뒤에 따로 커밋한다.

## Task 6 — 이웃 체인 셋

`main.zig`의 감독 루프가 바뀌었으므로 그 루프를 가장 많이 보는 체인 셋을 돌린다. 각 5~10분.

```bash
for c in service boot power; do
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./$c/check.sh > /tmp/ct/$c.log 2>&1
  echo "$c exit=$? $(grep -c FAIL /tmp/ct/$c.log) FAIL, last: $(tail -1 /tmp/ct/$c.log)"
done
```

기대: 셋 다 `exit=0`, `FAIL` 0줄. `boot/check.sh`는 terminal의 재시작을 정확히 셋으로 센다 —
`wantsRunning`이 `hold == .none`일 때 옛 조건과 같다는 것의 판정이다.

## Task 7 — design에 적고 닫는다

- [ ] Step 1: design을 고친다

- 결정 5의 오류 문구를 M1-D로, 결정 6의 시한을 8초와 exit code 64로(M1-B · C).
- "CT-M1이 실행으로 증명한 것" 절 — 호스트 검사의 줄, Task 5의 `CTM1-RUN` 줄, Task 6의 셋.
- `Status:` 줄을 "M1 끝났다"로.

- [ ] Step 2: 커밋

```bash
git status --short
git diff --stat
git add docs/specs/2026-09-27-tars-service-control-design.md \
        docs/plans/2026-09-27-tars-service-control-ct-m1.md
git commit -m "Close CT-M1: control socket, hold rules, tars-service"
```

## 이 milestone이 끝난 자리

통로 · 규칙 · 명령이 서고 호스트 검사가 본다. 게스트의 판정은 눈으로만 했다 — M2가
`service/check.sh`에 부팅을 더해 그 판정을 게이트로 옮기고, 반사실 둘(규칙 2 · 규칙 1)과
가이드를 더한다.
