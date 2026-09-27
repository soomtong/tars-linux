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

pub const LABEL_PREFIX = "service ";

/// DS-M1 결정 M1-A. init이 `services.d` 없이 스스로 감독 목록에 넣는 둘의 이름이다
/// (DS design 결정 1). label은 `LABEL_PREFIX ++ 이 이름`이라 `tars-service`가 같은
/// 이름으로 부른다.
pub const DHCPCD = "dhcpcd";
pub const CHRONYD = "chronyd";
/// 같은 이름이 `services.d`에 있으면 건너뛴다(DS design 결정 5). 둘이 같은 label을
/// 달면 `tars-service stop dhcpcd`가 무엇을 멈출지 모호하다.
pub const RESERVED = [_][]const u8{ DHCPCD, CHRONYD };
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
                .reserved => {
                    std.debug.print("tars-init: service {s} is a name init keeps for itself, skipped\n", .{name});
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
