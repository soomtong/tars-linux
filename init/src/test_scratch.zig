//! GP-M2: 호스트 검사가 파일을 만드는 자리를 프로세스마다 나눈다.
//!
//! 루트 게이트가 체인을 동시에 돌리면 같은 컨테이너 안에서 `zig build test`가 여럿 겹친다.
//! 검사들이 /tmp 아래 고정 경로(소켓 · 가짜 디스크 · 설정 파일 · 가짜 트리)를 쓰던 때는 한
//! 검사가 연 listener에 다른 검사가 붙었다(GP-M2의 첫 게이트, control_test). 그래서 검사의
//! 경로 상수는 상대 경로로 두고, main이 맨 먼저 `enter`로 이 프로세스만의 디렉터리에 들어간다.
const std = @import("std");
const linux = std.os.linux;

/// `/tmp/tars-test-<pid>`를 만들고 그리로 옮긴다. 검사가 끝나도 지우지 않는다 — 고정 경로를
/// 쓰던 때도 남겼고, 컨테이너가 `--rm`이다.
pub fn enter() !void {
    var buf: [48]u8 = undefined;
    const dir = std.fmt.bufPrint(buf[0 .. buf.len - 1], "/tmp/tars-test-{d}", .{linux.getpid()}) catch unreachable;
    buf[dir.len] = 0;
    const path: [*:0]const u8 = buf[0..dir.len :0];
    switch (linux.errno(linux.mkdir(path, 0o755))) {
        .SUCCESS, .EXIST => {},
        else => return error.ScratchDir,
    }
    if (linux.errno(linux.chdir(path)) != .SUCCESS) return error.ScratchDir;
}
