const std = @import("std");
const config = @import("config.zig");

/// config.zig에서 유일하게 시스템 콜이 없는 함수가 parse다. HANDOFF가
/// "단위 테스트가 없다"고 오래 적어두고 있었는데, keyboard 키가 들어오면서
/// 파서의 분기가 둘이 된 지금이 그 저울을 놓을 자리다.
///
/// terminal/src/input_test.zig와 같은 모양(호스트 아키텍처 실행 파일,
/// 실패하면 0이 아닌 종료 코드)으로 맞춘다 — 체인 스크립트가 둘을 똑같이
/// 다룰 수 있어야 한다.
fn expect(text: []const u8, want: config.Config) !void {
    const got = config.parse(text);
    if (got.shell == want.shell and got.keyboard == want.keyboard) return;
    std.debug.print(
        "FAIL: input={s}\n  got  shell={s} keyboard={s}\n  want shell={s} keyboard={s}\n",
        .{
            text,
            @tagName(got.shell),
            @tagName(got.keyboard),
            @tagName(want.shell),
            @tagName(want.keyboard),
        },
    );
    return error.UnexpectedConfig;
}

pub fn main() !void {
    // 빈 입력은 기본값이다. 이 한 줄이 "설정 파일이 없을 때의 TARS"를 못
    // 박는다 — Config의 기본값을 바꾸면 여기가 먼저 터진다.
    try expect("", .{});

    // 각 키 하나씩.
    try expect("shell=zsh\n", .{ .shell = .zsh });
    try expect("keyboard=pc\n", .{ .keyboard = .pc });

    // 둘이 함께. IP 체인의 2차 부팅이 실제로 쓰는 조합이다.
    try expect("shell=bash\nkeyboard=pc\n", .{ .shell = .bash, .keyboard = .pc });

    // 주석·빈 줄·양쪽 공백. 사람이 손으로 고치는 파일이라 이 셋이 규칙이다.
    try expect("# a comment\n\n  shell = zsh  \n", .{ .shell = .zsh });

    // CRLF. 호스트에서 편집한 파일을 넣었을 때 값이 "zsh\r"이 되면 원인을
    // 찾기 어렵다 — trim이 \r까지 떼는 이유다.
    try expect("shell=zsh\r\nkeyboard=pc\r\n", .{ .shell = .zsh, .keyboard = .pc });

    // 마지막 줄에 개행이 없어도 된다.
    try expect("keyboard=pc", .{ .keyboard = .pc });

    // ── 깨진 입력은 전부 기본값으로 떨어진다 ────────────────────────────
    //
    // 이것이 CP design doc의 "설정 하나로 부팅이 막히지 않게 하는 장치"다.
    // 어느 줄도 예외를 던지지 않고, 어느 줄도 부팅을 멈추지 않는다.
    try expect("shell=nushell\n", .{}); // enum에 없는 셸
    try expect("keyboard=dvorak\n", .{}); // enum에 없는 키보드
    try expect("colour=red\n", .{}); // 모르는 키
    try expect("no equals here\n", .{}); // '=' 없음
    try expect("=value\n", .{}); // 키 없음
    try expect("shell=\n", .{}); // 값 없음

    // shell=/etc/passwd 같은 입력이 애초에 성립하지 않는다는 것 —
    // 화이트리스트가 이름만 받고 경로를 안 받는다는 설계의 증거다.
    try expect("shell=/usr/bin/fish\n", .{});

    // 첫 번째 '='에서만 나눈다. 값 쪽에 '='가 남으면 enum에 없는 이름이 된다.
    try expect("shell=zsh=extra\n", .{});

    // 뒤에 오는 줄이 이긴다. "마지막이 이긴다"는 정책을 못 박아 둔다.
    try expect("shell=zsh\nshell=bash\n", .{ .shell = .bash });

    // 한 줄이 깨져도 나머지 줄은 살아남는다. 이 성질이 없으면 오타 하나가
    // 파일 전체를 무효로 만든다.
    try expect("shell=nope\nkeyboard=pc\n", .{ .keyboard = .pc });

    std.debug.print("PASS\n", .{});
}
