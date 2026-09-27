# SV-M1 — `init`이 `/config/services.d`를 읽고 감독한다

> 이 plan을 실행하는 사람에게: 순서는 Task 1(순수한 쪽과 그 검사) → Task 2(`main.zig`
> 배선) → Task 3(체인) → Task 4(반사실) → Task 5(이웃 체인) → Task 6(기록)이다.
> Task 1은 TDD다 — 검사를 먼저 쓰고 빨간 것을 본 뒤 구현한다. 코드 편집은 Claude가
> 하고, 편집마다 `git diff --stat`으로 더한 줄 · 지운 줄을 세고 지운 줄은 직접 읽는다
> (`CLAUDE.md` 진행 방식 2).

Goal: 사람이 `/config/services.d/`에 둔 실행 파일을 `init`이 부팅 때 한 번 읽어
terminal · 콘솔 셸과 같은 규칙으로 띄우고 감독한다. 열여섯번째 체인
`service/check.sh`가 부팅 하나로 그것을 판정한다.

Architecture: 새 파일 `init/src/services.zig`가 디렉터리를 읽어 고른 결과를 고정 크기
`List`(최대 8)에 담는다. 순수한 판정(`judgeName` · `sortNames` · `joinPath`)과 시스템
콜(`discover`: `open` · `getdents64` · `statx`)이 한 파일에 있고, `discover`가 경로를
인자로 받으므로 호스트에서 `/tmp`의 가짜 디렉터리로 검사된다. `main.zig`는 `Kind`에
`.service`를 더하고 `Child`에 로그 이름 `label`을 더해, `children` 배열을
`2 + services.MAX` 크기로 짓고 앞 둘 뒤에 서비스를 붙인다. 감독 규칙(재시작 1초 ·
빨리 셋이면 포기)은 한 글자도 안 바뀐다.

Tech Stack: Zig 0.16(`std.os.linux`의 `getdents64` · `statx` · `setsid`) · bash ·
`debugfs` · QEMU(`virtio-net-pci` + SLIRP `hostfwd`)

---

## 이 milestone의 결정

design 결정 4가 큰 모양을 정했다. 아래는 그 아래에서 이 plan이 정하는 것이다.

- M1-A. 이름 한도는 32바이트, 한 번에 보는 항목은 64개. 64를 넘는 항목은 세기만
  하고 안 본다(한 줄). 정렬은 64개 안에서 하고, 그중 앞의 8개를 띄운다 — 8개를
  넘는 것이 무엇인지는 이름순으로 정해진다.
- M1-B. 실행 가능 판정은 `statx`(링크를 따라간다)로 "일반 파일이고 실행 비트가
  하나라도 있다"다. `access(X_OK)`를 안 쓰는 이유 — root에게는 디렉터리도
  `X_OK`를 통과한다. 끊어진 링크는 `statx`가 `ENOENT`이고 "읽을 수 없다"로 뺀다.
- M1-C. 서비스 자식은 `setsid()`로 자기 세션을 갖고 stdin을 `/dev/null`로 돌린다.
  stdout · stderr는 물려받은 콘솔이다. stdin을 안 돌리면 서비스가 시리얼 콘솔의
  입력을 콘솔 셸과 나눠 읽는다.
- M1-D. `Child`에 `label: []const u8`를 더하고 로그 일곱 자리가 `c.kind.name()`
  대신 그것을 쓴다. terminal은 `"terminal"`, 콘솔 셸은 `"console shell"` — 지금
  글자 그대로다(다른 체인이 `started terminal` · `giving up on terminal` ·
  `started console shell`을 grep한다). 서비스는 `"service <이름>"`이다. `Kind.name()`은
  지운다 — 이름의 출처가 둘이 되지 않게.
- M1-E. 로그 문구.

| 경우 | 줄 |
|---|---|
| 디렉터리 없음 | `tars-init: no /config/services.d, 0 services` |
| 못 엶(그 밖) | `tars-init: cannot open /config/services.d (errno N), 0 services` |
| 이름이 김 | `tars-init: service name <이름> is longer than 32 bytes, skipped` |
| 64개 초과 | `tars-init: /config/services.d has more than 64 entries, N not looked at` |
| 못 읽음 | `tars-init: service <이름> cannot be read (errno N), skipped` |
| 실행 파일 아님 | `tars-init: service <이름> is not an executable file, skipped` |
| 8개 초과 | `tars-init: service <이름> ignored, at most 8 services` |
| 끝 | `tars-init: N services from /config/services.d` |

`.`으로 시작하는 이름은 조용히 건너뛴다(`ls`와 같다). 시작 · 종료 · 포기 줄은 기존
감독 루프의 것이 `label`로 그대로 나온다 — `started service a-greet (pid N,
/config/services.d/a-greet)` · `giving up on service b-die after 3 fast exits`.

- M1-F. 체인의 포트 — monitor `45481`, 서비스 `a-greet`가 듣는 게스트 7000 ↔
  컨테이너 `45482`. 45474~45480은 FW가 쓴다.

## 파일

| 파일 | 무엇 |
|---|---|
| `init/src/services.zig` (새) | 디렉터리를 읽고 고른다 |
| `init/src/services_test.zig` (새) | 호스트에서 도는 검사 |
| `init/build.zig` | `services_test`를 `test` 스텝에 더한다 |
| `init/src/main.zig` | `Kind.service` · `Child.label` · `spawn`의 서비스 갈래 · `children` 확장 · `discover` 호출 |
| `service/check.sh` (새) | 열여섯번째 체인 |
| `check.sh` | `CHAINS`에 한 줄 |

## Task 1 — `services.zig`와 그 검사 (TDD)

Files:
- Create: `init/src/services_test.zig`
- Create: `init/src/services.zig`
- Modify: `init/build.zig` (disk_test 블록 뒤, `test_step` 줄들)

- [ ] Step 1: 검사를 쓴다

`init/src/services_test.zig`:

```zig
const std = @import("std");
const linux = std.os.linux;
const services = @import("services.zig");

/// 이 검사가 만드는 가짜 services.d. 게스트가 아니라 빌드 컨테이너의 /tmp다.
const ROOT = "/tmp/tars-services-test";
const DIR = ROOT ++ "/services.d";
const MISSING = ROOT ++ "/nope";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

var path_buf: [256]u8 = undefined;

fn join(comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const text = std.fmt.bufPrint(path_buf[0 .. path_buf.len - 1], fmt, args) catch unreachable;
    path_buf[text.len] = 0;
    return path_buf[0..text.len :0];
}

fn mkdirOne(path: [:0]const u8) !void {
    const rc = linux.mkdir(path.ptr, 0o755);
    if (failed(rc)) |e| {
        if (e == .EXIST) return;
        std.debug.print("FAIL: mkdir {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.MkdirFailed;
    }
}

/// 내용은 상관없다 — discover는 모드만 본다. mode는 umask를 거치므로
/// 0o755 · 0o644만 쓴다(umask 022에서 그대로 남는다).
fn touch(name: []const u8, mode: linux.mode_t) !void {
    const path = join("{s}/{s}", .{ DIR, name });
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, mode);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: create {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.OpenFailed;
    }
    _ = linux.close(@intCast(rc));
    // 두 번째 실행에서 이미 있던 파일은 open이 모드를 안 바꾼다.
    _ = linux.chmod(path.ptr, mode);
}

fn link(name: []const u8, target: []const u8) !void {
    var target_buf: [256]u8 = undefined;
    const t = std.fmt.bufPrintZ(&target_buf, "{s}", .{target}) catch unreachable;
    const path = join("{s}/{s}", .{ DIR, name });
    _ = linux.unlink(path.ptr);
    const rc = linux.symlink(t.ptr, path.ptr);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: symlink {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.SymlinkFailed;
    }
}

fn expectVerdict(name: []const u8, want: services.Verdict) !void {
    const got = services.judgeName(name);
    if (got != want) {
        std.debug.print("FAIL: judgeName(\"{s}\") = {s}, want {s}\n", .{ name, @tagName(got), @tagName(want) });
        return error.WrongVerdict;
    }
}

pub fn main() !void {
    // ── 이름만으로 가르는 것 ─────────────────────────────────────────
    try expectVerdict("sshd", .ok);
    try expectVerdict(".hidden", .hidden);
    try expectVerdict(".", .hidden);
    try expectVerdict("..", .hidden);
    try expectVerdict("a" ** services.NAME_MAX, .ok);
    try expectVerdict("a" ** (services.NAME_MAX + 1), .too_long);
    std.debug.print("services_test: names — dot means hidden, {d} bytes is the limit\n", .{services.NAME_MAX});

    // ── 정렬 ───────────────────────────────────────────────────────
    var names = [_][]const u8{ "z-last", "a-first", "m-mid", "a-fir" };
    services.sortNames(&names);
    const sorted = [_][]const u8{ "a-fir", "a-first", "m-mid", "z-last" };
    for (names, sorted) |got, want| {
        if (!std.mem.eql(u8, got, want)) {
            std.debug.print("FAIL: sorted order has {s} where {s} belongs\n", .{ got, want });
            return error.WrongOrder;
        }
    }
    std.debug.print("services_test: names sort bytewise\n", .{});

    // ── 디렉터리가 없으면 0개 ─────────────────────────────────────────
    try mkdirOne(ROOT);
    var list = services.List{};
    list.len = 99; // discover가 0으로 되돌리는지까지 본다
    services.discover(MISSING, &list);
    if (list.len != 0) {
        std.debug.print("FAIL: a missing directory gave {d} services\n", .{list.len});
        return error.MissingDirNotEmpty;
    }
    std.debug.print("services_test: a missing directory is zero services\n", .{});

    // ── 실제 디렉터리 ───────────────────────────────────────────────
    // 만드는 순서를 이름순과 다르게 둔다 — getdents 순서가 결과에 새면 여기서 걸린다.
    try mkdirOne(DIR);
    try touch("z-last", 0o755);
    try touch("m-noexec", 0o644);
    try touch(".hidden", 0o755);
    try mkdirOne(join("{s}/{s}", .{ DIR, "subdir" }));
    try touch("a-first", 0o755);
    try link("l-link", DIR ++ "/a-first");
    try link("k-broken", DIR ++ "/does-not-exist");
    var i: u8 = 0;
    while (i < 7) : (i += 1) {
        const name = [_]u8{ 'n', '0' + i };
        try touch(&name, 0o755);
    }
    try touch("b" ** (services.NAME_MAX + 1), 0o755);

    // 실행 파일은 a-first · l-link · n0..n6 · z-last 열 개다. 앞의 여덟이 뽑힌다.
    services.discover(DIR, &list);
    const want = [_][]const u8{ "a-first", "l-link", "n0", "n1", "n2", "n3", "n4", "n5" };
    if (list.len != want.len) {
        std.debug.print("FAIL: discover picked {d} services, want {d}\n", .{ list.len, want.len });
        return error.WrongCount;
    }
    for (list.slice(), want) |*e, w| {
        const want_path = join("{s}/{s}", .{ DIR, w });
        if (!std.mem.eql(u8, e.path(), want_path)) {
            std.debug.print("FAIL: path {s}, want {s}\n", .{ e.path(), want_path });
            return error.WrongPath;
        }
        var label_buf: [64]u8 = undefined;
        const want_label = std.fmt.bufPrint(&label_buf, "service {s}", .{w}) catch unreachable;
        if (!std.mem.eql(u8, e.label(), want_label)) {
            std.debug.print("FAIL: label {s}, want {s}\n", .{ e.label(), want_label });
            return error.WrongLabel;
        }
        // execve에 넘기는 것은 포인터다. NUL이 제자리에 있어야 한다.
        if (e.path().ptr[e.path().len] != 0) {
            std.debug.print("FAIL: path {s} is not NUL-terminated\n", .{e.path()});
            return error.NotTerminated;
        }
    }
    std.debug.print("services_test: eight executables in name order, the rest skipped or ignored\n", .{});
}
```

`k-broken`(끊어진 링크) · `m-noexec` · `subdir` · `.hidden` · 33바이트 이름은 뽑히면 안
되는 것들이고, `n6` · `z-last`는 실행 파일이지만 여덟 밖이다. 각각이 찍는 줄(M1-E)은
검사가 보지 않는다 — 문구는 체인이 게스트 로그에서 본다.

- [ ] Step 2: `build.zig`에 더한다

`init/build.zig`의 `disk_test` 정의 뒤에:

```zig
    // SV-M1: services.d를 읽고 고르는 것의 검사. devices_test와 같은 이유로
    // host_target이다 — discover가 디렉터리 경로를 인자로 받으므로 /tmp의 가짜
    // 디렉터리를 읽는다.
    const services_test_mod = b.createModule(.{
        .root_source_file = b.path("src/services_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const services_test = b.addExecutable(.{
        .name = "services_test",
        .root_module = services_test_mod,
    });
```

그리고 `test_step` 줄들 끝에:

```zig
    test_step.dependOn(&b.addRunArtifact(services_test).step);
```

- [ ] Step 3: 빨간 것을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | tail -5
```

기대: `services.zig`가 없어 컴파일 에러(`unable to load 'src/services.zig'` 류).

- [ ] Step 4: `init/src/services.zig`를 쓴다

```zig
//! SV-M1. `/config/services.d/`에서 감독할 서비스를 고른다.
//!
//! 읽는 것은 부팅 때 한 번이다(SV design 결정 4). 고른 결과는 `List`에 담기고,
//! `main.zig`가 그것을 terminal · 콘솔 셸 뒤에 `children`으로 붙인다. 이 파일은
//! 아무것도 띄우지 않는다 — 띄우고 감독하는 것은 `main.zig`의 `supervise`다.
//!
//! 시스템 콜을 하는 `discover`도 디렉터리 경로를 인자로 받는다. 그래서 이 파일
//! 전체가 호스트에서 /tmp의 가짜 디렉터리로 검사된다(`services_test.zig`).
const std = @import("std");
const linux = std.os.linux;

/// 게스트의 진짜 자리. 검사는 여기에 /tmp의 디렉터리를 넣는다.
pub const DIR: [:0]const u8 = "/config/services.d";

/// 감독하는 서비스의 상한. 힙이 없어서 `main.zig`의 `children`이 이 수로
/// 크기를 정한다(design 결정 4).
pub const MAX: usize = 8;

/// 이름의 상한(바이트). 로그와 `label`에 그대로 들어가는 이름이라 짧게 둔다.
pub const NAME_MAX: usize = 32;

/// 한 번에 보는 항목의 상한(M1-A). 정렬하려면 전부 들고 있어야 하므로 이 수가
/// 곧 스택에 잡는 이름 버퍼의 수다 — 64 × 32바이트.
const SCAN_MAX: usize = 64;

/// "디렉터리/이름\0". 게스트의 가장 긴 것이 18 + 1 + 32 + 1 = 52이고, 검사의
/// /tmp 경로가 그보다 조금 길다.
const PATH_MAX: usize = 128;

const LABEL_PREFIX = "service ";
const LABEL_MAX: usize = LABEL_PREFIX.len + NAME_MAX;

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 고른 서비스 하나. 경로와 로그 이름을 제 버퍼에 든다 — `List`가 `main()`의
/// 스택에 살고 `supervise()`가 영영 반환하지 않으므로 여기서 꺼낸 포인터가
/// argv로 가도 뜨지 않는다(`keyboard_path`와 같은 근거).
pub const Entry = struct {
    path_buf: [PATH_MAX]u8 = undefined,
    path_len: usize = 0,
    label_buf: [LABEL_MAX]u8 = undefined,
    label_len: usize = 0,

    pub fn path(self: *const Entry) [:0]const u8 {
        return self.path_buf[0..self.path_len :0];
    }

    /// 감독 루프의 로그 이름. `"service sshd"`.
    pub fn label(self: *const Entry) []const u8 {
        return self.label_buf[0..self.label_len];
    }
};

pub const List = struct {
    entries: [MAX]Entry = undefined,
    len: usize = 0,

    pub fn slice(self: *const List) []const Entry {
        return self.entries[0..self.len];
    }
};

pub const Verdict = enum { ok, hidden, too_long };

/// 이름만 보고 가른다. `.`으로 시작하면 숨긴 것이다 — `.`과 `..`도 여기서 빠진다.
pub fn judgeName(name: []const u8) Verdict {
    if (name.len == 0 or name[0] == '.') return .hidden;
    if (name.len > NAME_MAX) return .too_long;
    return .ok;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// 바이트 순서로 정렬한다. getdents64의 순서는 파일시스템이 정하는 것이라
/// (ext2는 대개 만든 순서다) 부팅마다 같은 순서로 띄우려면 우리가 정한다.
pub fn sortNames(names: [][]const u8) void {
    std.sort.insertion([]const u8, names, {}, lessThan);
}

/// `dir/name`을 NUL로 끝나게 `buf`에 짓는다. 자리가 모자라면 null.
pub fn joinPath(buf: []u8, dir: []const u8, name: []const u8) ?[:0]const u8 {
    if (buf.len == 0) return null;
    const text = std.fmt.bufPrint(buf[0 .. buf.len - 1], "{s}/{s}", .{ dir, name }) catch return null;
    buf[text.len] = 0;
    return buf[0..text.len :0];
}

const Check = union(enum) {
    ok,
    not_executable,
    unreadable: linux.E,
};

/// 따라간 끝이 일반 파일이고 실행 비트가 하나라도 있는가(M1-B). 링크를 따라가는
/// 것이 design 결정 6의 켜는 법(`ln -s`)을 받치는 자리다.
fn check(path: [:0]const u8) Check {
    var st: linux.Statx = undefined;
    const rc = linux.statx(linux.AT.FDCWD, path.ptr, 0, .{ .TYPE = true, .MODE = true }, &st);
    if (failed(rc)) |e| return .{ .unreadable = e };
    const mode: linux.mode_t = st.mode;
    if (!linux.S.ISREG(mode) or mode & 0o111 == 0) return .not_executable;
    return .ok;
}

/// `dir`을 읽어 `list`를 채운다. 무엇이 일어나도 반환한다 — 서비스가 없는 것은
/// 이 저장소가 지금까지 돌려 온 상태 그 자체다(feedback_boot_never_blocks).
pub fn discover(dir: [:0]const u8, list: *List) void {
    list.len = 0;

    const rc = linux.open(dir.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc)) |e| {
        if (e == .NOENT) {
            std.debug.print("tars-init: no {s}, 0 services\n", .{dir});
        } else {
            std.debug.print("tars-init: cannot open {s} (errno {d}), 0 services\n", .{ dir, @intFromEnum(e) });
        }
        return;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    // ── 이름을 모은다 ────────────────────────────────────────────────
    var name_bufs: [SCAN_MAX][NAME_MAX]u8 = undefined;
    var names: [SCAN_MAX][]const u8 = undefined;
    var count: usize = 0;
    var overflow: usize = 0;

    var buf: [4096]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &buf, buf.len);
        if (failed(n)) |e| {
            std.debug.print("tars-init: cannot read {s} (errno {d})\n", .{ dir, @intFromEnum(e) });
            break;
        }
        if (n == 0) break;

        var off: usize = 0;
        while (off < n) {
            const d: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += d.reclen;
            const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&d.name)), 0);
            switch (judgeName(name)) {
                .hidden => continue,
                .too_long => {
                    std.debug.print("tars-init: service name {s} is longer than {d} bytes, skipped\n", .{ name, NAME_MAX });
                    continue;
                },
                .ok => {},
            }
            if (count == SCAN_MAX) {
                overflow += 1;
                continue;
            }
            @memcpy(name_bufs[count][0..name.len], name);
            names[count] = name_bufs[count][0..name.len];
            count += 1;
        }
    }
    if (overflow > 0) {
        std.debug.print("tars-init: {s} has more than {d} entries, {d} not looked at\n", .{ dir, SCAN_MAX, overflow });
    }

    // ── 이름순으로 보고 여덟까지 담는다 ──────────────────────────────────
    sortNames(names[0..count]);

    for (names[0..count]) |name| {
        var path_buf: [PATH_MAX]u8 = undefined;
        const path = joinPath(&path_buf, dir, name) orelse {
            std.debug.print("tars-init: service {s} has a path too long, skipped\n", .{name});
            continue;
        };
        switch (check(path)) {
            .unreadable => |e| {
                std.debug.print("tars-init: service {s} cannot be read (errno {d}), skipped\n", .{ name, @intFromEnum(e) });
                continue;
            },
            .not_executable => {
                // 실행 비트를 잊은 것이 가장 흔한 실수다(SV-M0 실측 3). 이 줄이
                // 없으면 execve가 EACCES로 셋 죽고 포기되며 원인이 로그 깊숙이
                // 묻힌다 — resolveShell이 미리 보는 것과 같은 생각이다.
                std.debug.print("tars-init: service {s} is not an executable file, skipped\n", .{name});
                continue;
            },
            .ok => {},
        }
        if (list.len == MAX) {
            std.debug.print("tars-init: service {s} ignored, at most {d} services\n", .{ name, MAX });
            continue;
        }
        const e = &list.entries[list.len];
        e.path_len = (joinPath(&e.path_buf, dir, name) orelse unreachable).len;
        e.label_len = (std.fmt.bufPrint(&e.label_buf, LABEL_PREFIX ++ "{s}", .{name}) catch unreachable).len;
        list.len += 1;
    }

    std.debug.print("tars-init: {d} services from {s}\n", .{ list.len, dir });
}
```

- [ ] Step 5: 초록을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | tail -20
```

기대: `services_test:` 네 줄(names · sort · missing · eight executables)과 다른 검사들의
통과 줄. 사이에 `tars-init:` 줄들(`no /tmp/tars-services-test/nope` · `name bbbb… is longer` ·
`k-broken cannot be read (errno 2)` · `m-noexec is not an executable file` · `subdir is not`
· `n6 ignored` · `z-last ignored` · `8 services from`)이 stderr로 섞여 나온다 — 그 줄들이
M1-E의 문구를 눈으로 확인하는 자리다.

Zig 0.16의 API 이름이 다르면(예: `std.sort.insertion` · `linux.S.ISREG`의 인자 타입)
컴파일 에러가 가리키는 대로 고치고, 고친 것을 이 plan에 적는다.

- [ ] Step 6: 커밋

```bash
git add init/src/services.zig init/src/services_test.zig init/build.zig
git diff --cached --stat
git commit -m "Add services.zig: pick executables from services.d in name order"
```

## Task 2 — `main.zig`에 배선한다

Files:
- Modify: `init/src/main.zig`

- [ ] Step 1: import

`const firewall = @import("firewall.zig");` 근처(다른 import들과 같은 자리)에:

```zig
const services = @import("services.zig");
```

- [ ] Step 2: `Kind`에 `.service`를 더하고 `name()`을 지운다

```zig
/// 감독 대상의 종류. 무엇을 실행할지는 여기 없다 — 그것은 Child가
/// 들고 있고, 설정을 읽은 뒤 main에서 한 번 정해진다. Kind는 fork한 자식이
/// execve 전에 무엇을 준비하는가만 결정한다 — 콘솔 셸은 제어 터미널을 잡고,
/// 서비스는 세션을 따로 갖고 stdin을 끊는다(SV-M1 M1-C). 로그 이름은
/// `Child.label`이다(SV-M1 M1-D) — 서비스는 종류 하나에 이름이 여럿이다.
const Kind = enum {
    terminal,
    console_shell,
    service,
};
```

- [ ] Step 3: `Child`에 `label`을 더한다

`kind: Kind,` 바로 뒤에:

```zig
    /// 로그에 찍는 이름. terminal과 콘솔 셸은 SV 전의 글자 그대로다 — 다른
    /// 체인이 `started terminal` · `giving up on terminal` · `started console
    /// shell`을 grep한다. 서비스는 `"service <이름>"`이고 `services.Entry`가
    /// 버퍼를 든다.
    label: []const u8,
```

- [ ] Step 4: 로그 일곱 자리의 `c.kind.name()`을 `c.label`로

`spawn`의 fork 실패 줄, `start`의 `started` 줄, 거두는 쪽의 `exited` · `killed` 줄,
탈출로 줄, `giving up` 줄, `restarting` 줄. `sd`로 한 번에 바꾸고 남은 것이 없는지 본다.

```bash
sd -F 'c.kind.name()' 'c.label' init/src/main.zig
rg -n 'kind.name|\.name\(\)' init/src/main.zig
```

기대: 두 번째 명령이 아무것도 안 찍는다.

- [ ] Step 5: `spawn`의 자식 쪽

```zig
    if (pid == 0) {
        // 여기부터는 자식이다.
        switch (c.kind) {
            .terminal => {},
            .console_shell => setupControllingTerminal(),
            .service => detachService(),
        }
        _ = linux.execve(c.path.ptr, &c.argv, envp);
```

그리고 `setupControllingTerminal` 뒤에 새 함수:

```zig
/// SV-M1 M1-C. 서비스는 콘솔을 제어 터미널로 잡지 않고, 콘솔의 입력을 안 읽는다.
///
/// setsid가 먼저인 이유 — 새 세션에는 제어 터미널이 없으므로 이 뒤로 서비스가
/// 무엇을 열어도 콘솔이 제어 터미널이 되지 않는다(O_NOCTTY를 잊은 open 하나가
/// 콘솔 셸의 SIGINT를 가로챌 수 있다). stdin을 /dev/null로 돌리는 이유 — 안
/// 돌리면 서비스가 물려받은 fd 0(콘솔)을 읽어 사람이 콘솔 셸에 친 글자를
/// 나눠 먹는다. stdout · stderr는 그대로다 — 서비스의 출력이 시리얼 로그에 남는
/// 것이 로그 파일을 따로 두지 않는(비목표 3) 이 설계의 로그다.
fn detachService() void {
    _ = linux.setsid();
    const rc = linux.open("/dev/null", .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return;
    const fd: i32 = @intCast(rc);
    _ = linux.dup2(fd, 0);
    if (fd != 0) _ = linux.close(fd);
}
```

- [ ] Step 6: `main()`에서 읽고 `children`을 짓는다

`clock.start(...)` 줄 바로 뒤에:

```zig
    // SV-M1. `clock.start` 뒤인 것이 이 자리의 뜻이다(SV design 결정 4) — 서비스가
    // 뜨는 시점에 방화벽 규칙과 dhcpcd가 이미 서 있다. 여기서는 읽기만 한다.
    // 띄우는 것은 아래 `supervise`의 첫 바퀴이고, terminal · 콘솔 셸과 한 바퀴에
    // 함께 뜬다 — 어느 서비스도 부팅 경로에서 기다리지 않는다.
    //
    // `/config`가 안 붙은 부팅은 tmpfs의 빈 `/config`라 "no … 0 services" 한 줄로
    // 끝난다. 조건을 따로 두지 않는다.
    //
    // 이 값도 `main()`의 스택에 산다. 아래 argv가 이 안의 경로를 가리키고
    // `supervise()`가 영영 반환하지 않으므로 프로세스 수명 내내 유효하다.
    var service_list = services.List{};
    services.discover(services.DIR, &service_list);
```

기존 `var children = [_]Child{ … };`와 `supervise(&children, …)`를 다음으로 바꾼다.
앞 둘의 필드는 지금 그대로이고 `.label`만 더한다.

```zig
    // SV-M1. 앞 둘은 SV 전과 같고, 서비스가 이름순으로 그 뒤에 붙는다. 크기는
    // 컴파일 타임에 정해진다(힙이 없다) — 쓰는 것은 앞에서 `2 + len`까지다.
    var children: [2 + services.MAX]Child = undefined;
    children[0] = .{
        .kind = .terminal,
        .label = "terminal",
        .path = TERMINAL_PATH,
        // (지금의 주석과 argv · rescue 그대로)
    };
    children[1] = .{
        .kind = .console_shell,
        .label = "console shell",
        .path = shell_path,
        // (지금의 주석과 argv · rescue 그대로)
    };
    for (service_list.slice(), 0..) |*s, i| {
        children[2 + i] = .{
            .kind = .service,
            .label = s.label(),
            .path = s.path(),
            // 인자는 없다 — 서비스는 실행 파일 하나이고(결정 2), 준비할 것은
            // 스크립트가 한다. 탈출로도 없다(결정 3).
            .argv = .{ s.path().ptr, null, null, null, null, null, null, null },
        };
    }
    supervise(children[0 .. 2 + service_list.len], button_fds[0..button_count], envp);
```

"(지금의 주석과 argv · rescue 그대로)"는 자리 표시가 아니라 지시다 — 기존
리터럴의 `.argv = …`와 `.rescue = …`와 그 위 주석을 한 글자도 안 바꾸고 옮긴다.
편집 뒤 `git diff`의 `-` 줄에 그 주석이 있고 `+` 줄에 같은 글이 있어야 한다.

- [ ] Step 7: 빌드와 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && zig build test 2>&1 | tail -3'
git diff --stat
git diff init/src/main.zig | grep '^-' | grep -v '^---'
```

기대: 빌드 성공. 지운 줄은 `Kind.name()` 함수 몸통 · `c.kind.name()` 일곱 · `[_]Child{`
리터럴의 머리와 끝 · `supervise(&children` 한 줄뿐이다. 옮긴 주석이 `-`에만 있고
`+`에 없으면 옮기다 잃은 것이다.

- [ ] Step 8: 커밋

```bash
git add init/src/main.zig
git commit -m "Supervise services.d entries after the terminal and console shell"
```

## Task 3 — 체인 `service/check.sh`

Files:
- Create: `service/check.sh`
- Modify: `check.sh` (`CHAINS` 끝에 한 줄, 그 위 주석에 한 문단)

- [ ] Step 1: 체인을 쓴다

```bash
mkdir -p service
cat > service/check.sh <<'CHAIN'
#!/usr/bin/env bash
# SV 체인. init이 /config/services.d의 실행 파일을 읽어 띄우고 감독하는가를 본다.
#
# 부팅 하나다. 설정 디스크가 싣는 것.
#   tars.conf                   net=dhcp — a-greet에 바깥에서 붙으려고
#   services.d/a-greet          붙는 사람에게 자기 $0과 PATH를 한 줄 보낸다
#   services.d/b-die            곧바로 죽는다 — 셋 뜨고 포기된다
#   services.d/c-noexec         실행 비트가 없다 — 사전 확인이 뺀다
#   services.d/d-link           → /config/linked.sh. 세션과 stdin을 콘솔에 적고 잔다
#   services.d/.hidden          숨긴 이름 — 조용히 무시된다
#
# services.d에 쓰는 순서를 이름의 역순으로 둔다. ext2의 getdents는 대개 만든
# 순서라, init이 정렬을 안 하면 시작 순서 검사가 빨갛다.
#
# 우리 코드는 init/src/services.zig(고르기)와 main.zig의 감독 루프(띄우기)다.
set -uo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd .. && pwd)"

source ../gate_lib.sh

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# services_test가 부팅 전에 0.1초로 고르기를 본다 — 여덟 한도와 끊어진 링크는
# 부팅으로 재기에 비싸다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 포트. 45474~45480은 FW가 쓴다.
MONITOR_PORT=45481
GREET_PORT=45482   # → 게스트 7000, a-greet가 듣는다
HOSTFWD="hostfwd=tcp:127.0.0.1:${GREET_PORT}-10.0.2.15:7000"

DISK="${REPO_ROOT}/out/service.img"
LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$LOG"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "services from /config/services.d" \
    "tars-init: started console shell" \
    "tars-init: started service" \
    ": leased" \
    "terminal: screen>"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  local pattern
  for pattern in "$@"; do
    grep -a "$pattern" "$LOG" | head -5 | sed 's/^/  /' || true
  done
  echo "--- tars-init lines ---"
  grep -a "tars-init:" "$LOG" | tail -n 30 || true
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

wait_for_log() {
  local pattern="$1" seconds="$2" i
  for i in $(seq 1 "$seconds"); do
    if grep -aE "$pattern" "$LOG" >/dev/null; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 1
  done
  return 1
}

# 패턴의 첫 줄 번호. 없으면 빈 값.
line_of() {
  grep -anE "$1" "$LOG" | head -1 | cut -d: -f1
}

# ── 디스크 ────────────────────────────────────────────────────────────
# debugfs의 write는 원본의 모드를 따른다(SV-M0 실측 2) — 실행 비트는 호스트의
# chmod가 정한다. 링크는 debugfs의 symlink다.
mkdir -p "${REPO_ROOT}/out"
SEED="$(mktemp -d)"
printf 'net=dhcp\n' > "$SEED/tars.conf"
cat > "$SEED/a-greet" <<'EOF'
#!/bin/sh
# 판정 글자(sv-greet)는 붙은 쪽이 읽는 바이트에만 있다. 매 연결마다 한 줄.
while true; do
  printf 'sv-greet %s %s\n' "$0" "$PATH" | nc -l -p 7000 > /dev/null 2>&1
done
EOF
printf '#!/bin/sh\nexit 3\n' > "$SEED/b-die"
printf '#!/bin/sh\necho sv-noexec-ran\n' > "$SEED/c-noexec"
printf '#!/bin/sh\necho sv-hidden-ran\n' > "$SEED/hidden"
cat > "$SEED/linked.sh" <<'EOF'
#!/bin/sh
# d-link로 불린다. shebang이 /bin/bash면 execve가 ENOENT다 — 게스트의 /bin에는
# sh 하나만 산다(make_initrd.sh:81, SV-M1 첫 실행이 그렇게 빨갛다).
# $0이 링크의 경로다(SV-M0 실측 3). stdin이 /dev/null이면 read가
# 곧바로 EOF(rc 1)이고, 콘솔이면 1초를 채우고 142 언저리다. sid가 pid와 같으면
# setsid가 됐다.
read -r -t 1 _; rc=$?
printf 'sv-linked %s sid=%s pid=%s stdin-rc=%s\n' "$0" "$(ps -o sid= -p $$ | tr -d ' ')" "$$" "$rc"
exec sleep 100000
EOF
chmod 755 "$SEED/a-greet" "$SEED/b-die" "$SEED/hidden" "$SEED/linked.sh"
chmod 644 "$SEED/c-noexec"

rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-sv "$DISK"
dbg() { debugfs -w -R "$1" "$DISK" 2>&1 | grep -v '^debugfs' || true; }
dbg "write $SEED/tars.conf tars.conf"
dbg "write $SEED/linked.sh linked.sh"
dbg "mkdir services.d"
dbg "write $SEED/hidden services.d/.hidden"
dbg "symlink services.d/d-link /config/linked.sh"
dbg "write $SEED/c-noexec services.d/c-noexec"
dbg "write $SEED/b-die services.d/b-die"
dbg "write $SEED/a-greet services.d/a-greet"
rm -rf "$SEED"

echo "=== boot: net=dhcp, services.d with a-greet b-die c-noexec d-link .hidden ==="
qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0,${HOSTFWD}" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

wait_for_log "terminal: screen>" 120 || fail "terminal never rendered a prompt"
connected=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
  sleep 0.5
done
[ "$connected" = "1" ] || fail "could not connect to the QEMU monitor"

# ── 검사 1: 셋을 골랐다 ────────────────────────────────────────────────
# a-greet · b-die · d-link. c-noexec는 사전 확인이, .hidden은 이름이 뺐다.
grep -a "tars-init: 3 services from /config/services.d" "$LOG" >/dev/null \
  || fail "init did not pick exactly three services" "services from" "tars-init: service"
echo "init picked three services from /config/services.d"

# ── 검사 2: 실행 비트 없는 것은 한 줄로 빠졌고 한 번도 안 떴다 ──────────────
grep -a "tars-init: service c-noexec is not an executable file, skipped" "$LOG" >/dev/null \
  || fail "c-noexec was not skipped by the pre-check" "c-noexec"
if grep -a "started service c-noexec" "$LOG" >/dev/null; then
  fail "c-noexec was started despite having no execute bit" "c-noexec"
fi
echo "c-noexec was skipped before it could fail"

# ── 검사 3: 숨긴 이름은 흔적이 없다 ─────────────────────────────────────
if grep -aE "service \.hidden|sv-hidden-ran" "$LOG" >/dev/null; then
  fail ".hidden was looked at" ".hidden" "sv-hidden-ran"
fi
echo ".hidden left no trace"

# ── 검사 4: 이름순으로, 콘솔 셸 뒤에 떴다 ──────────────────────────────
# 디스크에는 역순으로 썼다. 정렬이 빠지면 여기가 빨갛다.
SHELL_LINE="$(line_of 'tars-init: started console shell')"
A_LINE="$(line_of 'tars-init: started service a-greet \(pid [0-9]+, /config/services.d/a-greet\)')"
B_LINE="$(line_of 'tars-init: started service b-die ')"
D_LINE="$(line_of 'tars-init: started service d-link ')"
[ -n "$SHELL_LINE" ] && [ -n "$A_LINE" ] && [ -n "$B_LINE" ] && [ -n "$D_LINE" ] \
  || fail "a start line is missing (shell=${SHELL_LINE} a=${A_LINE} b=${B_LINE} d=${D_LINE})" "tars-init: started"
[ "$SHELL_LINE" -lt "$A_LINE" ] && [ "$A_LINE" -lt "$B_LINE" ] && [ "$B_LINE" -lt "$D_LINE" ] \
  || fail "services did not start in name order after the console shell (shell=${SHELL_LINE} a=${A_LINE} b=${B_LINE} d=${D_LINE})" "tars-init: started"
echo "a-greet, b-die, d-link started in name order after the console shell"

# ── 검사 5: 곧바로 죽는 서비스는 셋 뜨고 포기된다 ────────────────────────
# 셋이라는 수가 MAX_FAST_RESTARTS 정책이다 — boot 체인이 terminal에 대해 세는
# 것과 같은 수다.
wait_for_log "tars-init: giving up on service b-die after 3 fast exits" 30 \
  || fail "b-die was never given up on" "b-die"
B_STARTS="$(grep -ac "tars-init: started service b-die " "$LOG" || true)"
[ "$B_STARTS" = "3" ] || fail "b-die started ${B_STARTS} times, want 3" "b-die"
echo "b-die started three times and was given up on"

# ── 검사 6: 링크로 켠 서비스가 제 세션에 있고 stdin이 끊겨 있다 ──────────────
wait_for_log "sv-linked /config/services.d/d-link sid=" 30 \
  || fail "d-link never reported" "d-link" "sv-linked"
LINKED="$(grep -aoE "sv-linked /config/services.d/d-link sid=[0-9]+ pid=[0-9]+ stdin-rc=[0-9]+" "$LOG" | head -1)"
SID="$(sed -E 's/.* sid=([0-9]+) .*/\1/' <<<"$LINKED")"
PID="$(sed -E 's/.* pid=([0-9]+) .*/\1/' <<<"$LINKED")"
RC="$(sed -E 's/.* stdin-rc=([0-9]+)$/\1/' <<<"$LINKED")"
[ "$SID" = "$PID" ] || fail "d-link is not its own session leader (${LINKED})" "sv-linked"
[ "$RC" = "1" ] || fail "d-link's stdin is not /dev/null (${LINKED})" "sv-linked"
echo "d-link ran through its link, leads its own session and reads EOF on stdin"

# ── 검사 7: 서비스가 init의 env를 받고 바깥에서 닿는다 ─────────────────────
# PATH가 init의 것(/usr/bin:/bin)이면 envp가 서비스까지 왔다.
wait_for_log "eth0: leased 10\.0\.2\.15 " 60 \
  || fail "dhcpcd never leased an address" ": leased" "dhcpcd"
GOT=""
for _ in $(seq 1 20); do
  if exec 5<>"/dev/tcp/127.0.0.1/${GREET_PORT}"; then
    read -r -t 5 GOT <&5 || true
    exec 5<&-
    exec 5>&-
  fi
  [ -n "$GOT" ] && break
  sleep 0.5
done
[ "$GOT" = "sv-greet /config/services.d/a-greet /usr/bin:/bin" ] \
  || fail "a-greet did not answer as expected (got: [${GOT}])" "a-greet"
echo "a-greet answered from outside with init's PATH"

# ── 검사 8: 살아 있는 서비스 둘은 한 번도 안 죽었고, 콘솔 셸도 그대로다 ───────
for who in "service a-greet" "service d-link" "console shell"; do
  if grep -aE "tars-init: ${who} (exited|killed)" "$LOG" >/dev/null; then
    fail "${who} died during the boot" "tars-init: ${who}"
  fi
done
echo "a-greet, d-link and the console shell stayed up"

echo "system_powerdown" >&3
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""
exec 3<&-
exec 3>&-

echo "SV chain PASS"
CHAIN
chmod +x service/check.sh
```

검사 7의 `read`가 받는 줄에 판정 글자가 있고 게스트에 친 명령은 없다 — 이 체인은
게스트에 한 글자도 안 친다(device 체인과 같다). 그래서 `project_gate_screen_echo`의
함정이 이 체인에는 없다.

- [ ] Step 2: `check.sh`의 `CHAINS`에 더한다

`"FW-M2:./firewall/check.sh"` 줄 뒤에:

```bash
  "SV-M1:./service/check.sh"
```

그리고 `CHAINS=(` 바로 위의 체인 설명 문단들 끝에:

```bash
#
# SV 체인은 init이 /config/services.d의 실행 파일을 골라 띄우고 감독하는가를
# 본다. device 체인처럼 게스트에 한 글자도 안 치고 판정이 시리얼 로그와 바깥에서
# 붙은 TCP 한 줄이다. 회차당 부팅 1회(30초 안팎)라 총 부팅 횟수가 셋 는다.
```

- [ ] Step 3: 진입 검사만 돌려 본다

```bash
bash -c 'source <(sed -n "/^require_build_steps()/,/^}/p;/^BUILD_STEPS=/,/^)/p;/^EARLY_EXIT_PIPE=/p;/^require_no_early_exit_pipe()/,/^}/p;/^require_explicit_nic()/,/^}/p" check.sh); require_build_steps ./service/check.sh && require_no_early_exit_pipe ./service/check.sh && require_explicit_nic ./service/check.sh && echo entry-ok'
```

기대: `entry-ok`.

## Task 4 — 체인을 돌리고 반사실 셋

- [ ] Step 1: 체인 (빌드 캐시가 있으면 약 1~2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./service/check.sh 2>&1 | tail -25
```

기대: 검사 1 ~ 8의 줄과 `SV chain PASS`. 빨간 것이 있으면 `fail`이 찍는 `tars-init`
줄들을 읽고 원인을 고친 뒤 다시 돈다 — 체인을 느슨하게 고쳐 초록을 만들지 않는다.

- [ ] Step 2: 반사실 셋

각각 한 자리를 되돌려 체인을 돌리고, 겨냥한 검사가 겨냥한 문구로 빨간 것을 본 뒤
`git checkout init/src/services.zig init/src/main.zig`로 되돌린다. 캐시 문제
(`project_zig_out_staleness`)를 피하려고 각 반사실 전에 컨테이너 안에서
`rm -rf init/.zig-cache init/zig-out`를 한다.

| 반사실 | 고치는 자리 | 빨개야 하는 검사 |
|---|---|---|
| 정렬 없음 | `services.zig`의 `sortNames(names[0..count]);` 줄을 지운다 | 검사 4(`did not start in name order`) — 그 전에 `zig build test`의 sort 검사가 먼저 빨갛다면 그것도 적는다 |
| 사전 확인 없음 | `check`의 `not_executable` 분기가 `.ok`를 돌려주게 | 검사 1(`exactly three`) 또는 2 |
| 세션 · stdin 없음 | `spawn`의 `.service => detachService(),`를 `.service => {},`로 | 검사 6 |

정렬 반사실은 호스트 검사가 먼저 잡으므로 체인까지 안 간다. 그 경우 체인의
`zig build test` 단계를 잠시 주석으로 막아 부팅 쪽 검사 4도 빨간지를 따로 본다 —
두 겹이 각각 서 있는지가 궁금한 것이다. 막은 주석은 반사실 뒤 되돌린다.

```bash
# 한 반사실의 모양 (정렬 없음의 예)
sd -F '    sortNames(names[0..count]);' '' init/src/services.zig
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'rm -rf init/.zig-cache init/zig-out && ./service/check.sh' 2>&1 | tail -15
git checkout init/src/services.zig
```

## Task 5 — 이웃 체인

로그 이름을 `label`로 옮긴 것과, 모든 부팅에 한 줄(`no /config/services.d, 0 services`
또는 `0 services from …`)이 느는 것이 남의 판정을 건드리는지 본다(design 위험 4).
supervisor 문구를 grep하는 체인들 — boot(terminal 재시작 수를 3으로 센다) · device ·
machine · config — 과 서비스를 모르는 체인 하나(firewall).

- [ ] Step 1: 다섯을 돌린다 (약 10~12분)

```bash
for c in boot device machine config firewall; do
  echo "=== $c ==="
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./$c/check.sh 2>&1 | tail -3
done
```

기대: 다섯 다 `PASS`. 루트 게이트(16체인 3/3, 약 47분)는 SV-M2가 끝날 때 돈다 —
M1에서 돌지 않는 것은 M2가 initrd와 체인을 다시 바꾸기 때문이다.

## Task 6 — 기록하고 커밋한다

- [ ] Step 1: design에 "SV-M1이 실행으로 증명한 것" 절을 더한다

M0 절 뒤에 실측 8부터 이어 번호를 매긴다. 체인 출력(검사 1 ~ 8의 줄)과 걸린 시간,
반사실 셋의 결과, 이웃 다섯의 결과, `init` 바이너리 크기 변화(`zig-out/bin/init`,
M1 전후), Task 1 Step 5에서 Zig API를 고친 것이 있으면 그것. `Status:` 줄을 "M1
끝났다 — 다음은 M2(sshd)"로 고친다.

- [ ] Step 2: 커밋

```bash
git status --short
git add service/check.sh check.sh \
        docs/superpowers/specs/2026-09-27-tars-boot-services-design.md \
        docs/superpowers/plans/2026-09-27-tars-boot-services-sv-m1.md
git diff --cached --stat
git commit -m "Close SV-M1: init supervises services.d, sixteenth chain service/check.sh"
```

기대: `out/service.img`는 `.gitignore`의 `out/`로 빠져 목록에 없다.

## 이 milestone이 끝난 자리

`init`이 `/config/services.d`의 실행 파일을 이름순으로 여덟까지 띄우고 감독한다.
열여섯번째 체인이 그것을 판정한다. sshd는 아직 없다 — 다음은 SV-M2의 plan이고, 그
plan을 쓰기 전에 사용자와 정할 것이 둘 있다(M0 실측 6 · 7: ssh 세션의 셸 · env와
terminfo).
