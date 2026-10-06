const std = @import("std");
const audio = @import("audio.zig");

// AU-M1. 믹서를 켜고 적는 배관의 순수한 쪽 넷. 게스트에서 alsactl이 실제로 믹서를
// 바꾸는 것은 audio 체인이 샘플의 값으로 본다 — 여기는 그 앞에서 "어느 동사로 ·
// 어떤 인자로 · 끝을 어떻게 읽고 · 끌 때 적을지"를 0.1초로 본다.
//
// AU-M2. 기본 카드를 고르는 순수한 쪽 셋(`addNode` · `defaultsFor` · `render`). 꽂고 뽑을
// 때 소리가 실제로 그 카드로 가는 것은 audio 체인의 부팅 D가 본다.
//
// AU-M3. `addNode`(/dev/snd의 이름)가 `addPcmLine`(/proc/asound/pcm의 줄)이 됐다. 녹음의
// 세 단(USB 마이크 · 내장 DMIC · 장치 0)은 QEMU에 DMIC가 없어 여기서만 본다 — 아래
// SOF · AMD의 줄은 커널의 snd_pcm_proc_read 모양에 그 드라이버들이 짓는 id를 넣은 것이다.

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

    // ── 어느 카드가 기본인가(AU-M2 · M3) ───────────────────────────────
    //
    // /proc/asound/pcm의 줄에서 장치 0의 재생 · 녹음과, 녹음 쪽의 USB · DMIC 표지를
    // 센다. 첫 목록은 게스트의 실제 모양이다 — QEMU의 HDA(카드 0, 재생과 녹음)에 USB
    // 스피커(카드 1, 재생만)가 꽂힌 것.
    const qemu = scan(&.{
        "00-00: Generic Analog : Generic Analog : playback 1 : capture 1",
        "01-00: USB Audio : USB Audio : playback 1",
        "",
    });
    if (qemu.playback != 0b11 or qemu.capture != 0b01 or qemu.usb_capture != 0 or qemu.dmic != 0)
        return fail("HDA plus a USB speaker reads as playback 0x{x} capture 0x{x} usb 0x{x} dmic 0x{x}, want 0x3 0x1 0 0", .{ qemu.playback, qemu.capture, qemu.usb_capture, qemu.dmic });
    // 장치 0이 아닌 것 · 모양이 다른 것은 장치 0으로 안 센다. HDMI 코덱만 가진 카드는 장치
    // 1(디지털)이나 3(HDMI)이다.
    const none = scan(&.{
        "02-01: ALC257 Digital : ALC257 Digital : playback 1",
        "02-03: HDMI 0 : HDMI 0 : playback 1",
        "32-00: Generic Analog : Generic Analog : playback 1 : capture 1",
        "x0-00: Generic Analog : Generic Analog : playback 1 : capture 1",
        "0-00: Generic Analog : Generic Analog : playback 1",
        "00-00 Generic Analog : Generic Analog : playback 1",
        "00-00: Generic Analog",
        "card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]",
    });
    if (none.playback != 0 or none.capture != 0 or none.dmic != 0)
        return fail("lines that are not device 0 counted as playback 0x{x} capture 0x{x} dmic 0x{x}", .{ none.playback, none.capture, none.dmic });
    std.debug.print("audio_test: only device 0 counts for playback, from /proc/asound/pcm lines\n", .{});

    // 재생과 녹음 각각 번호가 가장 큰 카드. 마이크 없는 USB 스피커가 꽂혀도 녹음은 0에 남는다.
    const split = audio.defaultsFor(qemu);
    if (split.playback != 1 or split.capture != 0 or split.capture_dev != 0) return fail("HDA plus a USB speaker picks playback {?d} capture {?d}:{d}, want 1 and 0:0", .{ split.playback, split.capture, split.capture_dev });
    const headset = audio.defaultsFor(.{ .playback = 0b101, .capture = 0b101 });
    if (headset.playback != 2 or headset.capture != 2) return fail("a headset on card 2 picks playback {?d} capture {?d}, want 2 and 2", .{ headset.playback, headset.capture });
    const empty = audio.defaultsFor(.{});
    if (empty.playback != null or empty.capture != null) return fail("no card picks playback {?d} capture {?d}, want none", .{ empty.playback, empty.capture });
    const top = audio.defaultsFor(.{ .playback = 0x8000_0001, .capture = 0 });
    if (top.playback != 31 or top.capture != null) return fail("card 31 picks playback {?d} capture {?d}", .{ top.playback, top.capture });
    std.debug.print("audio_test: the highest card wins, for playback and capture apart\n", .{});

    // Intel SOF(sof-hda-dsp). 장치 0의 녹음은 헤드셋 잭, 내장 마이크는 장치 6이다.
    const sof_lines = [_][]const u8{
        "00-00: HDA Analog (*) :  : playback 1 : capture 1",
        "00-03: HDMI1 (*) :  : playback 1",
        "00-04: HDMI2 (*) :  : playback 1",
        "00-05: HDMI3 (*) :  : playback 1",
        "00-06: DMIC (*) :  : capture 1",
        "00-07: DMIC16kHz (*) :  : capture 1",
        "00-31: Deepbuffer HDA Analog (*) :  : playback 1",
    };
    const sof = audio.defaultsFor(scan(&sof_lines));
    if (sof.playback != 0 or sof.capture != 0 or sof.capture_dev != 6) return fail("a SOF laptop picks playback {?d} capture {?d}:{d}, want 0 and 0:6", .{ sof.playback, sof.capture, sof.capture_dev });
    // 같은 노트북에 USB 헤드셋. 사람이 꽂은 마이크가 내장 DMIC를 이긴다.
    const sof_usb = audio.defaultsFor(scan(&(sof_lines ++ [_][]const u8{"01-00: USB Audio : USB Audio : playback 1 : capture 1"})));
    if (sof_usb.playback != 1 or sof_usb.capture != 1 or sof_usb.capture_dev != 0) return fail("a SOF laptop with a USB headset picks playback {?d} capture {?d}:{d}, want 1 and 1:0", .{ sof_usb.playback, sof_usb.capture, sof_usb.capture_dev });
    // 마이크 없는 USB 스피커는 녹음을 안 가져간다.
    const sof_spk = audio.defaultsFor(scan(&(sof_lines ++ [_][]const u8{"01-00: USB Audio : USB Audio : playback 1"})));
    if (sof_spk.playback != 1 or sof_spk.capture != 0 or sof_spk.capture_dev != 6) return fail("a SOF laptop with a USB speaker picks playback {?d} capture {?d}:{d}, want 1 and 0:6", .{ sof_spk.playback, sof_spk.capture, sof_spk.capture_dev });
    // AMD. GPU 쪽 HDA(HDMI뿐) · 아날로그 HDA · ACP(DMIC)가 따로 카드다. 번호의 차례는
    // probe 순서라 정해져 있지 않다 — 어느 차례든 녹음은 ACP다.
    const amd = audio.defaultsFor(scan(&.{
        "00-03: HDMI 0 : HDMI 0 : playback 1",
        "01-00: ALC257 Analog : ALC257 Analog : playback 1 : capture 1",
        "02-00: DMIC capture dmic-hifi-0 :  : capture 1",
    }));
    if (amd.playback != 1 or amd.capture != 2 or amd.capture_dev != 0) return fail("an AMD laptop picks playback {?d} capture {?d}:{d}, want 1 and 2:0", .{ amd.playback, amd.capture, amd.capture_dev });
    const amd_swapped = audio.defaultsFor(scan(&.{
        "00-03: HDMI 0 : HDMI 0 : playback 1",
        "01-00: DMIC capture dmic-hifi-0 :  : capture 1",
        "02-00: ALC257 Analog : ALC257 Analog : playback 1 : capture 1",
    }));
    if (amd_swapped.playback != 2 or amd_swapped.capture != 1 or amd_swapped.capture_dev != 0) return fail("an AMD laptop with the ACP first picks playback {?d} capture {?d}:{d}, want 2 and 1:0", .{ amd_swapped.playback, amd_swapped.capture, amd_swapped.capture_dev });
    std.debug.print("audio_test: capture goes to a plugged USB mic, else the built-in DMIC, else device 0\n", .{});

    // 파일의 글자. 손으로 적은 글자와 비교한다(tautology가 아니게). 카드 번호는 getenv의
    // 기본값 자리에 들어간다 — ALSA_CARD가 있으면 그것이 이긴다.
    var buf: [1024]u8 = undefined;
    const head = "# tars-init이 쓴다(AU-M2 · M3). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생은 장치 0을 가진 카드 중 번호가 가장 큰 것, 녹음은 USB 마이크 · 내장 DMIC ·\n" ++
        "# 그 밖의 장치 0 순으로 처음 있는 단에서 번호가 가장 큰 것이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n";
    const play0 = "\tplayback.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"0\" } ]\n\t}\n";
    const play1 = "\tplayback.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"1\" } ]\n\t}\n";
    const cap0 = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"0\" } ]\n\t}\n";
    const cap3 = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"sysdefault:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"3\" } ]\n\t}\n";
    const cap0dmic = "\tcapture.pcm {\n\t\t@func concat\n" ++
        "\t\tstrings [ \"plughw:CARD=\" { @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"0\" } \",DEV=6\" ]\n\t}\n";
    try expectText("split", audio.render(&buf, split), head ++ play1 ++ cap0 ++ "}\ndefaults.ctl.card 1\n");
    try expectText("capture only", audio.render(&buf, .{ .capture = 3 }), head ++ cap3 ++ "}\ndefaults.ctl.card 3\n");
    try expectText("sof", audio.render(&buf, sof), head ++ play0 ++ cap0dmic ++ "}\ndefaults.ctl.card 0\n");
    if (audio.render(&buf, .{}) != null) return fail("no card must render no file", .{});
    std.debug.print("audio_test: /etc/asound.conf points default at sysdefault:CARD=N unless ALSA_CARD says otherwise, and no card means no file\n", .{});
    std.debug.print("audio_test: a DMIC that is not device 0 is opened as plughw:CARD=N,DEV=D\n", .{});
}

/// /proc/asound/pcm의 줄들을 차례로 더한다.
fn scan(lines: []const []const u8) audio.Cards {
    var cards: audio.Cards = .{};
    for (lines) |line| audio.addPcmLine(&cards, line);
    return cards;
}

fn expectText(what: []const u8, got: ?[]const u8, want: []const u8) !void {
    const g = got orelse return fail("{s} rendered nothing", .{what});
    if (!std.mem.eql(u8, g, want)) return fail("{s} rendered\n{s}\nwant\n{s}", .{ what, g, want });
}
