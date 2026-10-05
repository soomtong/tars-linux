const std = @import("std");
const audio = @import("audio.zig");

// AU-M1. 믹서를 켜고 적는 배관의 순수한 쪽 넷. 게스트에서 alsactl이 실제로 믹서를
// 바꾸는 것은 audio 체인이 샘플의 값으로 본다 — 여기는 그 앞에서 "어느 동사로 ·
// 어떤 인자로 · 끝을 어떻게 읽고 · 끌 때 적을지"를 0.1초로 본다.

fn fail(comptime fmt: []const u8, args: anytype) error{Mismatch} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.Mismatch;
}

/// argv를 글자 하나로 펴서 기대하는 글자와 비교한다. 기대값을 상수에서 다시 짓지
/// 않고 손으로 적는다 — 그래야 이 검사가 tautology가 아니다(clock_test와 같은 이유).
fn expectArgv(what: []const u8, argv: [*:null]const ?[*:0]const u8, want: []const u8) !void {
    var buf: [128]u8 = undefined;
    var len: usize = 0;
    var i: usize = 0;
    while (argv[i]) |arg| : (i += 1) {
        const a = std.mem.span(arg);
        if (i > 0) {
            buf[len] = ' ';
            len += 1;
        }
        @memcpy(buf[len .. len + a.len], a);
        len += a.len;
    }
    if (!std.mem.eql(u8, buf[0..len], want)) return fail("{s} argv is '{s}', want '{s}'", .{ what, buf[0..len], want });
}

fn expectOutcome(status: u32, want: audio.Outcome) !void {
    const got = audio.outcome(status);
    if (!std.meta.eql(got, want)) return fail("status 0x{x} reads as {any}, want {any}", .{ status, got, want });
}

pub fn main() !void {
    // ── 어느 동사로 켜나 ────────────────────────────────────────────────
    //
    // 파일은 `/config`가 붙었을 때만 의미가 있다. 붙지 않은 부팅의 `/config`는 tmpfs의
    // 빈 디렉터리라 파일이 있을 수 없지만, 있다고 해도 init이어야 한다.
    if (audio.verbFor(true, true) != .restore) return fail("mounted with a state file must restore", .{});
    if (audio.verbFor(true, false) != .init) return fail("mounted without a state file must init", .{});
    if (audio.verbFor(false, false) != .init) return fail("no /config must init", .{});
    if (audio.verbFor(false, true) != .init) return fail("no /config must init even if a file is seen", .{});
    std.debug.print("audio_test: restore only with /config and a state file, init otherwise\n", .{});

    // ── 어떤 인자로 ─────────────────────────────────────────────────────
    //
    // -U가 빠지면 부팅마다 UCM 경고 두 줄이 찍힌다. -f가 빠지면 alsactl이 기본 경로
    // (/var/lib/alsa)를 쓰고 잠금 파일을 /var/lock에 만들려 든다 — 게스트에 둘 다 없다.
    try expectArgv("restore", audio.argvFor(.restore), "/usr/bin/alsactl -U -f /config/asound.state restore");
    try expectArgv("init", audio.argvFor(.init), "/usr/bin/alsactl -U init");
    try expectArgv("store", &audio.STORE_ARGV, "/usr/bin/alsactl -f /config/asound.state store");
    std.debug.print("audio_test: alsactl gets -U, and -f /config/asound.state wherever a file is read or written\n", .{});

    // ── 끝을 어떻게 읽나 ────────────────────────────────────────────────
    //
    // wait status의 모양은 커널의 것이다 — 정상 종료는 코드가 둘째 바이트, 시그널은
    // 첫 바이트의 아래 일곱 비트. 99는 alsactl이 범용 규칙으로 켠 것(성공)이고, 254는
    // 일꾼이 카드를 못 본 것이고, 2는 restore가
    // 파일을 못 연 것(ENOENT)이고, 127은 execve가 실패한 것이다.
    try expectOutcome(0x0000, .done);
    try expectOutcome(99 << 8, .generic);
    try expectOutcome(254 << 8, .no_card);
    try expectOutcome(127 << 8, .{ .exited = 127 });
    try expectOutcome(2 << 8, .{ .exited = 2 });
    try expectOutcome(9, .{ .killed = 9 });
    try expectOutcome(15, .{ .killed = 15 });
    std.debug.print("audio_test: a wait status reads as done, generic (99), no card, an exit code or a signal\n", .{});

    // ── 끌 때 적나 ─────────────────────────────────────────────────────
    //
    // 이 부팅에 믹서를 못 세웠으면 안 적는다. 적으면 커널의 꺼진 기본값이 사람이
    // 남긴 파일을 덮는다 — 일꾼이 카드를 기다리는 사이에 전원 버튼이 눌린 경우다.
    if (audio.storeDecision(true, true) != .store) return fail("set and mounted must store", .{});
    if (audio.storeDecision(true, false) != .no_config) return fail("set without /config must not store", .{});
    if (audio.storeDecision(false, true) != .not_set) return fail("not set must not store", .{});
    if (audio.storeDecision(false, false) != .not_set) return fail("not set without /config must not store", .{});
    std.debug.print("audio_test: the mixer is stored only when it was set this boot and /config is there\n", .{});
}
