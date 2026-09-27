//! SV-M2 결정 9. ssh로 붙은 세션이 콘솔과 같은 셸 · 같은 env를 갖게 한다.
//!
//! sshd는 세션의 셸을 `/etc/passwd`에서, env를 자기 설정의 `SetEnv`에서 얻는다 —
//! `init`의 env 블록은 sshd에서 멈춘다(SV-M0 실측 6). 그래서 부팅 때 둘을 쓴다.
//! 둘 다 initramfs의 루트에 쓰고 `/config`에는 안 쓴다 — 부팅마다 `tars.conf`에서
//! 새로 나온다(M2-A). sshd를 안 켠 기계에서도 쓴다.
const std = @import("std");
const linux = std.os.linux;

pub const PASSWD_PATH: [:0]const u8 = "/etc/passwd";
pub const SSH_ENV_PATH: [:0]const u8 = "/etc/ssh/sshd_config.d/tars-env.conf";

/// 파일 머리. 사람이 이 파일을 고치고 싶어질 때 어디를 봐야 하는지 적는다.
pub const SETENV_HEADER = "# Written by tars-init at boot from tars.conf (SV design decision 9).\n";

/// `make_initrd.sh`의 passwd는 두 줄 · 100바이트 안팎이다.
const PASSWD_MAX: usize = 1024;
const ENV_MAX: usize = 1024;

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// `root:` 줄의 마지막 필드(셸)만 `shell`로 바꾼 사본을 `out`에 짓는다. root 줄이
/// 없거나 자리가 모자라면 null.
pub fn replaceRootShell(in: []const u8, shell: []const u8, out: []u8) ?[]const u8 {
    var len: usize = 0;
    var found = false;
    var lines = std.mem.splitScalar(u8, in, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) {
            if (len >= out.len) return null;
            out[len] = '\n';
            len += 1;
        }
        first = false;
        var piece: []const u8 = line;
        var tail: []const u8 = "";
        if (std.mem.startsWith(u8, line, "root:")) {
            const colon = std.mem.lastIndexOfScalar(u8, line, ':') orelse return null;
            piece = line[0 .. colon + 1];
            tail = shell;
            found = true;
        }
        if (len + piece.len + tail.len > out.len) return null;
        @memcpy(out[len..][0..piece.len], piece);
        len += piece.len;
        @memcpy(out[len..][0..tail.len], tail);
        len += tail.len;
    }
    return if (found) out[0..len] else null;
}

/// `NAME=VALUE`들을 `SetEnv NAME="VALUE" …` 한 줄로 `out`에 짓는다. `=`가 없거나 값에
/// `"` · 줄바꿈이 있으면 null — 따옴표를 벗기는 규칙을 우리가 새로 만들지 않는다(M2-B).
pub fn renderSetEnv(out: []u8, entries: []const []const u8) ?[]const u8 {
    var w: std.Io.Writer = .fixed(out);
    w.writeAll(SETENV_HEADER ++ "SetEnv") catch return null;
    for (entries) |e| {
        const eq = std.mem.indexOfScalar(u8, e, '=') orelse return null;
        const value = e[eq + 1 ..];
        if (std.mem.indexOfAny(u8, value, "\"\n") != null) return null;
        w.print(" {s}=\"{s}\"", .{ e[0..eq], value }) catch return null;
    }
    w.writeAll("\n") catch return null;
    return w.buffered();
}

fn readAll(path: [:0]const u8, buf: []u8) ?[]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(rc)) |_| return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return null;
        }
        if (n == 0) return buf[0..len];
        len += n;
    }
    return null; // 버퍼가 찼다 — 파일이 생각보다 크다
}

fn writeAll(path: [:0]const u8, text: []const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    if (failed(rc)) |_| return false;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var done: usize = 0;
    while (done < text.len) {
        const n = linux.write(fd, text[done..].ptr, text.len - done);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return false;
        }
        done += n;
    }
    return true;
}

/// 두 파일을 쓴다. 무엇이 실패해도 반환한다 — 이것이 안 되면 ssh 세션이 SV 전과
/// 같은 `/bin/sh`와 sshd 기본 env가 될 뿐이고, 부팅은 계속된다.
pub fn apply(
    passwd_path: [:0]const u8,
    env_path: [:0]const u8,
    shell_path: []const u8,
    entries: []const []const u8,
) void {
    var in_buf: [PASSWD_MAX]u8 = undefined;
    var out_buf: [PASSWD_MAX]u8 = undefined;
    const passwd_ok = blk: {
        const in = readAll(passwd_path, &in_buf) orelse break :blk false;
        const out = replaceRootShell(in, shell_path, &out_buf) orelse break :blk false;
        break :blk writeAll(passwd_path, out);
    };
    var env_buf: [ENV_MAX]u8 = undefined;
    const env_ok = blk: {
        const text = renderSetEnv(&env_buf, entries) orelse break :blk false;
        break :blk writeAll(env_path, text);
    };
    if (passwd_ok and env_ok) {
        std.debug.print("tars-init: login shell {s}, ssh env in {s}\n", .{ shell_path, env_path });
    } else {
        std.debug.print("tars-init: login shell {s} {s}, ssh env {s}\n", .{
            shell_path,
            if (passwd_ok) "set" else "NOT set",
            if (env_ok) "written" else "NOT written",
        });
    }
}
