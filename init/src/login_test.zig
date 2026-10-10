const std = @import("std");
const scratch = @import("test_scratch.zig");
const linux = std.os.linux;
const login = @import("login.zig");

const ROOT = "tars-login-test";
const PASSWD = ROOT ++ "/passwd";
const ENV = ROOT ++ "/tars-env.conf";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn writeFile(path: [:0]const u8, text: []const u8) !void {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |_| return error.OpenFailed;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    if (linux.write(fd, text.ptr, text.len) != text.len) return error.WriteFailed;
}

fn readFile(path: [:0]const u8, buf: []u8) ![]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return error.OpenFailed;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    const n = linux.read(fd, buf.ptr, buf.len);
    if (failed(n)) |_| return error.ReadFailed;
    return buf[0..n];
}

fn expectEql(what: []const u8, got: []const u8, want: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: {s}\n--- got ---\n{s}\n--- want ---\n{s}\n", .{ what, got, want });
        return error.Mismatch;
    }
}

const PASSWD_IN =
    "root:x:0:0:root:/:/bin/sh\n" ++
    "sshd:x:100:65534::/run/sshd:/usr/sbin/nologin\n";

pub fn main() !void {
    try scratch.enter();
    // ── passwd의 root 셸 자리만 바뀐다 ───────────────────────────────
    var out: [512]u8 = undefined;
    const replaced = login.replaceRootShell(PASSWD_IN, "/usr/bin/zsh", &out) orelse {
        std.debug.print("FAIL: replaceRootShell gave up on a normal passwd\n", .{});
        return error.NoResult;
    };
    try expectEql("root's shell", replaced,
        "root:x:0:0:root:/:/usr/bin/zsh\n" ++
        "sshd:x:100:65534::/run/sshd:/usr/sbin/nologin\n");
    // 두 번 해도 같다 — 부팅은 initramfs의 원본에서 시작하지만, 함수는 멱등이어야 한다.
    var out2: [512]u8 = undefined;
    const again = login.replaceRootShell(replaced, "/usr/bin/zsh", &out2).?;
    try expectEql("idempotent", again, replaced);
    if (login.replaceRootShell("sshd:x:100:65534::/run/sshd:/x\n", "/usr/bin/zsh", &out) != null) {
        std.debug.print("FAIL: a passwd without root must give null\n", .{});
        return error.NoRootAccepted;
    }
    var tiny: [8]u8 = undefined;
    if (login.replaceRootShell(PASSWD_IN, "/usr/bin/zsh", &tiny) != null) {
        std.debug.print("FAIL: a buffer too small must give null\n", .{});
        return error.Overflow;
    }
    std.debug.print("login_test: only root's shell field changes\n", .{});

    // ── SetEnv 한 줄 ───────────────────────────────────────────────
    const entries = [_][]const u8{
        "PATH=/usr/bin:/bin",
        "XDG_DATA_HOME=/config/xdg",
        "TZ=Asia/Seoul",
        "HISTFILE=/config/zsh_history",
    };
    const env = login.renderSetEnv(&out, &entries) orelse {
        std.debug.print("FAIL: renderSetEnv gave up\n", .{});
        return error.NoResult;
    };
    try expectEql("SetEnv", env,
        login.SETENV_HEADER ++
        "SetEnv PATH=\"/usr/bin:/bin\" XDG_DATA_HOME=\"/config/xdg\" TZ=\"Asia/Seoul\" HISTFILE=\"/config/zsh_history\"\n");
    const bad = [_][]const u8{"TZ=a\"b"};
    if (login.renderSetEnv(&out, &bad) != null) {
        std.debug.print("FAIL: a value with a quote must give null\n", .{});
        return error.QuoteAccepted;
    }
    const noeq = [_][]const u8{"JUSTANAME"};
    if (login.renderSetEnv(&out, &noeq) != null) {
        std.debug.print("FAIL: an entry without = must give null\n", .{});
        return error.NoEqAccepted;
    }
    std.debug.print("login_test: the env becomes one quoted SetEnv line\n", .{});

    // ── apply가 두 파일을 쓴다 ─────────────────────────────────────
    _ = linux.mkdir(ROOT, 0o755);
    try writeFile(PASSWD, PASSWD_IN);
    _ = linux.unlink(ENV);
    login.apply(PASSWD, ENV, "/usr/bin/bash", &entries);
    var rb: [512]u8 = undefined;
    try expectEql("passwd on disk", try readFile(PASSWD, &rb),
        "root:x:0:0:root:/:/usr/bin/bash\n" ++
        "sshd:x:100:65534::/run/sshd:/usr/sbin/nologin\n");
    var rb2: [512]u8 = undefined;
    try expectEql("env on disk", try readFile(ENV, &rb2), env);
    std.debug.print("login_test: apply writes both files\n", .{});
}
