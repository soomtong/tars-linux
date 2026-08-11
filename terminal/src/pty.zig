const std = @import("std");

const c = @cImport({
    @cInclude("pty.h");
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
});

/// libc의 execv를 직접 선언한다. @cImport가 만들어주는 `c.execv`는
/// `char *const argv[]`를 `[*c]const [*c]u8`(비-const u8 포인터의 배열)로
/// 옮기기 때문에 Zig의 `?[*:0]const u8` 배열을 그대로 넘길 수 없다.
/// const를 벗기는 캐스팅을 하느니 처음부터 맞는 시그니처로 선언한다.
extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;

pub const Session = struct {
    master_fd: c_int,
    child_pid: c.pid_t,
};

/// PTY를 만들고 그 안에서 임의의 프로그램을 실행한다.
/// cols/rows를 winsize로 넘기는 것이 핵심이다 — 이 값이 0이면 대화형 셸이
/// 화면 폭을 모르는 상태로 프롬프트를 그려서 줄바꿈이 엉킨다.
pub fn spawn(
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    cols: u16,
    rows: u16,
) !Session {
    var ws: c.struct_winsize = .{
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    var master_fd: c_int = undefined;
    const pid = c.forkpty(&master_fd, null, null, &ws);
    if (pid < 0) return error.ForkptyFailed;

    if (pid == 0) {
        _ = execv(path, argv);
        // execv가 돌아왔다는 건 실패했다는 뜻이다.
        c._exit(127);
    }

    return Session{ .master_fd = master_fd, .child_pid = pid };
}

/// fish를 `-c <command>`로 비대화형 실행한다(프롬프트/설정 파일 없음).
/// TF-M2부터 있던 함수를 `spawn` 위에 다시 얹은 것 — `pty_test`가 그대로
/// 동작하도록 시그니처를 유지한다.
pub fn spawnFish(command: [:0]const u8) !Session {
    const argv = [_:null]?[*:0]const u8{
        "fish",
        "--no-config",
        "-c",
        command.ptr,
    };
    return spawn("/usr/bin/fish", &argv, 80, 25);
}

/// master fd에서 자식이 끝날 때까지(EOF) 나오는 모든 바이트를 읽는다.
/// 호출자가 미리 충분히 큰 buf를 넘긴다(fixed buffer, 동적 할당 없음).
pub fn readAll(fd: c_int, buf: []u8) []const u8 {
    var total: usize = 0;
    while (total < buf.len) {
        const n = c.read(fd, buf.ptr + total, buf.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }
    return buf[0..total];
}

/// master fd에서 딱 한 번 read한다. poll이 "읽을 게 있다"고 알려준 뒤에만
/// 호출하므로 여기서 멈추지 않는다. 0 이하(EOF 또는 에러)면 빈 슬라이스.
pub fn readSome(fd: c_int, buf: []u8) []const u8 {
    const n = c.read(fd, buf.ptr, buf.len);
    if (n <= 0) return buf[0..0];
    return buf[0..@intCast(n)];
}

/// master fd에 바이트를 써 넣는다. 자식 프로세스 입장에서는 사용자가
/// 키보드로 친 것과 구분되지 않는다.
pub fn write(fd: c_int, bytes: []const u8) void {
    var sent: usize = 0;
    while (sent < bytes.len) {
        const n = c.write(fd, bytes.ptr + sent, bytes.len - sent);
        if (n <= 0) return;
        sent += @intCast(n);
    }
}
