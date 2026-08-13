const std = @import("std");
const linux = std.os.linux;

/// 리눅스는 시스템 콜 실패를 "음수 errno"로 그대로 돌려준다. libc가 그것을
/// -1 리턴 + errno 전역 변수로 바꿔주는데, 여기서는 libc를 링크하지 않으므로
/// 그 변환을 직접 한다. 성공이면 null, 실패면 errno를 돌려준다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn mountFs(source: [:0]const u8, target: [:0]const u8, fstype: [:0]const u8) void {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, 0, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to mount {s} at {s} (errno {d})\n", .{
            fstype, target, @intFromEnum(e),
        });
    } else {
        std.debug.print("tars-init: mounted {s} at {s}\n", .{ fstype, target });
    }
}

/// devtmpfs는 드라이버가 등록한 장치 노드만 담기 때문에 /dev/pts 디렉터리를
/// 만들어주지 않는다. forkpty()는 /dev/ptmx를 연 뒤 커널이 지정한
/// /dev/pts/N을 열어야 하므로, 마운트 지점을 먼저 만들고 devpts를 붙인다.
fn mountDevpts() void {
    const rc = linux.mkdir("/dev/pts", 0o755);
    if (failed(rc)) |e| {
        // 이미 있으면 문제가 아니다. Rust판의 create_dir_all이 조용히
        // 넘어가던 경우와 같다.
        if (e != .EXIST) {
            std.debug.print("tars-init: failed to create /dev/pts (errno {d})\n", .{
                @intFromEnum(e),
            });
            return;
        }
    }
    mountFs("devpts", "/dev/pts", "devpts");
}

fn logDrmDevicePresence() void {
    // 열지 않고 존재만 본다. 곧 fork될 /terminal이 이 장치를 독점해서
    // 열 것이므로 여기서는 건드리지 않는 편이 안전하다.
    if (failed(linux.access("/dev/dri/card0", linux.F_OK))) |_| {
        std.debug.print("tars-init: /dev/dri/card0 not found\n", .{});
    } else {
        std.debug.print("tars-init: /dev/dri/card0 exists\n", .{});
    }
}

fn runTerminal(envp: [*:null]const ?[*:0]const u8) void {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: fork for terminal failed (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{"/terminal"};
        _ = linux.execve("/terminal", &argv, envp);
        // execve가 돌아왔다는 것은 실패했다는 뜻이다.
        std.debug.print("tars-init: execve /terminal failed\n", .{});
        linux.exit(1);
    }
    std.debug.print("tars-init: forked terminal (pid {d})\n", .{pid});
}

fn setupControllingTerminal() void {
    const rc = linux.open("/dev/console", .{ .ACCMODE = .RDWR }, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to open /dev/console (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    const fd: i32 = @intCast(rc);

    _ = linux.setsid();
    _ = linux.ioctl(fd, linux.T.IOCSCTTY, 0);
    _ = linux.dup2(fd, 0);
    _ = linux.dup2(fd, 1);
    _ = linux.dup2(fd, 2);
    if (fd > 2) _ = linux.close(fd);

    std.debug.print("tars-init: set up /dev/console as controlling terminal\n", .{});
}

pub fn main(init: std.process.Init.Minimal) void {
    // 커널이 PID 1의 스택에 올려준 환경 변수 블록. Rust판이 libc의 `environ`
    // 전역을 extern으로 가져다 쓰던 자리를 대신한다.
    const envp = init.environ.block.slice.ptr;

    std.debug.print("tars-init: starting as PID 1\n", .{});

    mountFs("proc", "/proc", "proc");
    mountFs("sysfs", "/sys", "sysfs");
    mountFs("devtmpfs", "/dev", "devtmpfs");
    mountDevpts();

    logDrmDevicePresence();

    runTerminal(envp);

    setupControllingTerminal();

    const argv = [_:null]?[*:0]const u8{"/usr/bin/fish"};
    _ = linux.execve("/usr/bin/fish", &argv, envp);

    // 여기 도달했다는 것은 fish를 띄우지 못했다는 뜻이다. Rust판과 마찬가지로
    // PID 1이 그냥 반환하며, 커널이 곧 패닉을 낸다. 그 동작을 유지한다.
    std.debug.print("tars-init: execve failed\n", .{});
}
