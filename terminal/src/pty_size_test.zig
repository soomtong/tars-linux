const std = @import("std");
const pty = @import("pty.zig");
const c = @import("c_pty");

// 자식이 보는 창 크기에 픽셀이 실리는지 호스트에서 본다(LE-M0). `pty_test`는 게스트용 fish를
// exec해서 호스트에서 못 도는데, 이것은 `openpty`로 쌍만 만들고 아무것도 exec하지 않는다 —
// `pty.resize`가 master에 건 `TIOCSWINSZ`를 slave 쪽 `TIOCGWINSZ`로 되읽는다. 자식이 읽는
// 쪽이 slave다. 검사 4는 자식을 띄우는 길(`execChild`)의 SIGPIPE를 본다(RF-M0) — 호스트의 /bin/sh를 띄운다.

fn expectSize(got: c.struct_winsize, cols: u16, rows: u16, xpixel: u16, ypixel: u16, what: []const u8) !void {
    if (got.ws_col == cols and got.ws_row == rows and got.ws_xpixel == xpixel and got.ws_ypixel == ypixel) return;
    std.debug.print("FAIL: {s}: col={d} row={d} xpixel={d} ypixel={d}, want {d} {d} {d} {d}\n", .{
        what, got.ws_col, got.ws_row, got.ws_xpixel, got.ws_ypixel, cols, rows, xpixel, ypixel,
    });
    return error.WrongSize;
}

pub fn main() !void {
    // 검사 1. 패널 하나의 크기(분할된 왼쪽 패널 77x47, 셀 8x16)가 slave에서 그대로 읽힌다.
    var master: c_int = undefined;
    var slave: c_int = undefined;
    if (c.openpty(&master, &slave, null, null, null) != 0) {
        std.debug.print("FAIL: openpty\n", .{});
        return error.OpenptyFailed;
    }
    defer _ = c.close(master);
    defer _ = c.close(slave);

    pty.resize(master, 77, 47, 8, 16);
    var got: c.struct_winsize = undefined;
    if (c.ioctl(slave, c.TIOCGWINSZ, &got) != 0) {
        std.debug.print("FAIL: TIOCGWINSZ\n", .{});
        return error.IoctlFailed;
    }
    try expectSize(got, 77, 47, 616, 752, "resize 77x47 cell 8x16");
    std.debug.print("pty_size_test: resize가 픽셀을 slave까지 싣는다 OK\n", .{});

    // 검사 2. 곱이 u16을 넘으면 그 축만 0("모른다")이다. 칸 수는 그대로다.
    try expectSize(pty.winsize(9000, 47, 8, 16), 9000, 47, 0, 752, "winsize 9000 cols");
    // 검사 3. 셀 크기를 모르면(`spawnFish`) 0이다 — LE 전과 같은 값이다.
    try expectSize(pty.winsize(80, 25, 0, 0), 80, 25, 0, 0, "winsize cell 0x0");
    std.debug.print("pty_size_test: 넘치거나 셀을 모르면 픽셀이 0이다 OK\n", .{});

    // 검사 4(RF-M0). terminal은 SIGPIPE를 무시한다(`ignoreSigpipe`). `execChild`로 띄운 자식은 기본 처리로 돌아가 있어야 한다 — 자식 셸이
    // 제게 SIGPIPE를 보내면 그것으로 죽는다. 무시를 물려받았으면(받아쓰기의 옛 길 — 맨 execve) 살아서 0으로 끝난다. 그런 자식(`tars-dictate`)
    // 안의 파이프 쓰기는 EPIPE를 만나 "write error"를 낸다.
    pty.ignoreSigpipe();
    const pid = std.c.fork();
    if (pid < 0) return error.ForkFailed;
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{ "sh", "-c", "kill -PIPE $$; exit 0" };
        pty.execChild("/bin/sh", &argv, std.c.environ);
    }
    var status: c_int = 0;
    if (std.c.waitpid(pid, &status, 0) != pid) return error.WaitFailed;
    // 시그널로 끝났으면 아래 7비트가 그 번호다(SIGPIPE 13), 정상 종료면 0이다.
    const sig = status & 0x7f;
    if (sig != 13) {
        std.debug.print("FAIL: the child of execChild did not die of SIGPIPE (status=0x{x})\n", .{status});
        return error.SigpipeInherited;
    }
    std.debug.print("pty_size_test: execChild의 자식은 SIGPIPE 기본 처리다 OK\n", .{});
    std.debug.print("PASS\n", .{});
}
