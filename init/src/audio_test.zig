const std = @import("std");
const audio = @import("audio.zig");

// AU-M1. 믹서를 켜고 적는 배관의 순수한 쪽 넷. 게스트에서 alsactl이 실제로 믹서를
// 바꾸는 것은 audio 체인이 샘플의 값으로 본다 — 여기는 그 앞에서 "어느 동사로 ·
// 어떤 인자로 · 끝을 어떻게 읽고 · 끌 때 적을지"를 0.1초로 본다.
//
// AU-M2. 기본 카드를 고르는 순수한 쪽 셋(`addNode` · `defaultsFor` · `render`). 꽂고 뽑을
// 때 소리가 실제로 그 카드로 가는 것은 audio 체인의 부팅 D가 본다.

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

    // ── 어느 카드가 기본인가(AU-M2) ────────────────────────────────────
    //
    // /dev/snd의 이름에서 장치 0의 재생 · 녹음만 센다. 아래 목록은 게스트의 실제
    // 모양이다 — HDA(카드 0, 재생과 녹음)에 USB 스피커(카드 1, 재생만)가 꽂힌 것.
    var cards: audio.Cards = .{};
    for ([_][]const u8{ "controlC0", "controlC1", "pcmC0D0c", "pcmC0D0p", "pcmC1D0p", "timer", "seq" }) |name| audio.addNode(&cards, name);
    if (cards.playback != 0b11 or cards.capture != 0b01) return fail("HDA plus a USB speaker reads as playback 0x{x} capture 0x{x}, want 0x3 0x1", .{ cards.playback, cards.capture });
    // 장치 0이 아닌 것 · 모양이 다른 것은 안 센다. HDMI 코덱만 가진 카드는 장치 1(디지털)이다.
    var none: audio.Cards = .{};
    for ([_][]const u8{ "pcmC2D1p", "pcmC2D3p", "pcmC0D0", "pcmCD0p", "pcmC32D0p", "pcmCxD0p", "pcmC1D0px", "hwC0D0", "midiC1D0" }) |name| audio.addNode(&none, name);
    if (none.playback != 0 or none.capture != 0) return fail("names that are not device 0 counted as playback 0x{x} capture 0x{x}", .{ none.playback, none.capture });
    std.debug.print("audio_test: only pcmC<card>D0p and pcmC<card>D0c count\n", .{});

    // 재생과 녹음 각각 번호가 가장 큰 카드. 마이크 없는 USB 스피커가 꽂혀도 녹음은 0에 남는다.
    const split = audio.defaultsFor(cards);
    if (split.playback != 1 or split.capture != 0) return fail("HDA plus a USB speaker picks playback {?d} capture {?d}, want 1 and 0", .{ split.playback, split.capture });
    const headset = audio.defaultsFor(.{ .playback = 0b101, .capture = 0b101 });
    if (headset.playback != 2 or headset.capture != 2) return fail("a headset on card 2 picks playback {?d} capture {?d}, want 2 and 2", .{ headset.playback, headset.capture });
    const empty = audio.defaultsFor(.{});
    if (empty.playback != null or empty.capture != null) return fail("no card picks playback {?d} capture {?d}, want none", .{ empty.playback, empty.capture });
    const top = audio.defaultsFor(.{ .playback = 0x8000_0001, .capture = 0 });
    if (top.playback != 31 or top.capture != null) return fail("card 31 picks playback {?d} capture {?d}", .{ top.playback, top.capture });
    std.debug.print("audio_test: the highest card wins, for playback and capture apart\n", .{});

    // 파일의 글자. 손으로 적은 글자와 비교한다(tautology가 아니게). 카드 번호는 getenv의
    // 기본값 자리에 들어간다 — ALSA_CARD가 있으면 그것이 이긴다.
    var buf: [1024]u8 = undefined;
    const head = "# tars-init이 쓴다(AU-M2). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n";
    const play1 = "\tplayback.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"1\" } ]\n\t}\n";
    const cap0 = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"0\" } ]\n\t}\n";
    const cap3 = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"3\" } ]\n\t}\n";
    try expectText("split", audio.render(&buf, split), head ++ play1 ++ cap0 ++ "}\ndefaults.ctl.card 1\n");
    try expectText("capture only", audio.render(&buf, .{ .capture = 3 }), head ++ cap3 ++ "}\ndefaults.ctl.card 3\n");
    if (audio.render(&buf, .{}) != null) return fail("no card must render no file", .{});
    std.debug.print("audio_test: /etc/asound.conf points default at sysdefault:CARD=N unless ALSA_CARD says otherwise, and no card means no file\n", .{});
}

fn expectText(what: []const u8, got: ?[]const u8, want: []const u8) !void {
    const g = got orelse return fail("{s} rendered nothing", .{what});
    if (!std.mem.eql(u8, g, want)) return fail("{s} rendered\n{s}\nwant\n{s}", .{ what, g, want });
}
