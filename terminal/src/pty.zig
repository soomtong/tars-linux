const std = @import("std");

const c = @cImport({
    @cInclude("pty.h");
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

/// fish를 `-c <command>`로 비대화형 실행한다(프롬프트/설정 파일 없음).
/// PTY(forkpty)를 쓰는 이유는 자식의 stdout/stderr를 PTY slave로 연결해서
/// 실제 터미널처럼 동작하는 경로를 그대로 검증하기 위함이다 — 대화형 입력을
/// 이 함수에서 write할 필요는 없다(`-c`가 명령을 인자로 직접 받음).
pub fn spawnFish(command: [:0]const u8) !Session {
    var master_fd: c_int = undefined;
    const pid = c.forkpty(&master_fd, null, null, null);
    if (pid < 0) return error.ForkptyFailed;

    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{
            "fish",
            "--no-config",
            "-c",
            command.ptr,
        };
        _ = execv("/usr/bin/fish", &argv);
        // execv가 돌아왔다는 건 실패했다는 뜻이다.
        c._exit(127);
    }

    return Session{ .master_fd = master_fd, .child_pid = pid };
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
