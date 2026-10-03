const std = @import("std");

// C 헤더는 build.zig가 번역해 `c_pty`로 넘긴다(ZU-M1). fortify는 켜져 있다.
const c = @import("c_pty");

/// libc의 execv를 직접 선언한다. 번역이 만들어주는 `c.execv`는
/// `char *const argv[]`를 `[*c]const [*c]u8`(비-const u8 포인터의 배열)로
/// 옮기기 때문에 Zig의 `?[*:0]const u8` 배열을 그대로 넘길 수 없다.
/// const를 벗기는 캐스팅을 하느니 처음부터 맞는 시그니처로 선언한다.
extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;

/// `kill` · `waitpid`도 같은 모양으로 직접 선언한다(WP-M1 plan 확정 5).
/// `c_pty` 번역에 `signal.h` · `sys/wait.h`를 더하면 fortify가 번역을 깨뜨릴
/// 자리가 는다(`project_zig_c_uapi_rule`) — 함수 둘 때문에 치를 값이 아니다.
extern "c" fn kill(pid: c.pid_t, sig: c_int) c_int;
extern "c" fn waitpid(pid: c.pid_t, status: ?*c_int, options: c_int) c.pid_t;

/// 리눅스의 SIGHUP. 값은 `asm-generic/signal.h`의 것이고 x86_64도 같다.
/// 헤더를 안 끌어오므로 여기 적는다.
const SIGHUP: c_int = 1;

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

/// 자식이 보는 창 크기를 바꾼다(WP design 결정 3). 패널이 갈리거나
/// 닫혀 크기가 바뀔 때 `vt.Screen.resize`와 짝으로 부른다 — 한쪽만 바꾸면
/// 셸이 아는 폭과 우리가 그리는 폭이 어긋나 줄바꿈이 엉킨다(`spawn`의
/// 주석과 같은 병).
///
/// SIGWINCH는 우리가 안 보낸다. `TIOCSWINSZ`가 크기가 바뀌었으면 커널이
/// 전경 프로세스 그룹에 보낸다.
pub fn resize(fd: c_int, cols: u16, rows: u16) void {
    var ws: c.struct_winsize = .{
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    _ = c.ioctl(fd, c.TIOCSWINSZ, &ws);
}

/// 셸에게 끝내라고 한다(WP design 결정 5). 보내기만 하고 기다리지 않는다 —
/// 셸이 끝나면 PTY가 EOF를 내고, 그 길(`close`)이 패널을 닫는다. 셸에
/// `exit`를 친 것과 같은 길을 지나게 하려는 것이다.
///
/// SIGHUP인 이유는 zsh · bash가 SIGTERM을 무시하고 SIGHUP에는 끝나기
/// 때문이다(`project_shutdown_signals`).
pub fn hangup(s: Session) void {
    _ = kill(s.child_pid, SIGHUP);
}

/// 패널의 PTY를 닫고 자식을 거둔다(WP design 결정 5).
///
/// WP 전에는 셸이 끝나면 terminal도 끝나서 좀비가 문제가 안 됐다. 이제
/// 패널이 닫혀도 terminal이 살아 있으므로 거둬야 한다.
///
/// `waitpid`가 막을 수 있는데 짧다. 여기 오는 것은 EOF 뒤이고, EOF는 slave
/// fd가 전부 닫혔다는 뜻이라 자식은 이미 끝났거나 끝나는 중이다. 배경 job이
/// slave를 쥐고 있으면 EOF 자체가 안 오므로 여기 안 온다.
pub fn close(s: Session) void {
    _ = c.close(s.master_fd);
    _ = waitpid(s.child_pid, null, 0);
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
